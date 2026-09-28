class_name MachineLink
extends Node
## Keeps one SSH socket forward up for a remote herdr machine. Knows no rendering
## and no herdr protocol: it only makes a remote herdr socket appear at
## `local_socket`, where an ordinary HerdrClient can connect to it.
##
## Every machine runs its own herdr server, reachable only through its own
## socket. First ask the remote shell for $HOME once (`ssh -L` does not expand
## `~` on the far side), then hold `ssh -N -L local.sock:remote.sock` open and
## restart it with exponential backoff whenever it exits.
##
## Never blocks while running: ssh runs through OS.execute_with_pipe and is
## polled every frame. Only the one-time socket directory check and the startup
## leftover sweep run short commands synchronously.
## Credentials belong to OpenSSH. BatchMode means no password prompt ever, and an
## unknown host key fails here instead of being accepted blindly.

## Phase or detail changed; `state` and `last_error` say what.
signal state_changed

## What the forward is doing: nothing, asking the remote shell for $HOME,
## holding the forward open, or backing off after a failure.
enum State { STOPPED, RESOLVING, FORWARDING, WAITING }

const CONNECT_TIMEOUT := 10
const ALIVE_INTERVAL := 15
const ALIVE_COUNT := 3
## The one-shot $HOME lookup gets this long before it counts as a failure.
const RESOLVE_TIMEOUT := 30.0
const BACKOFF_MIN := 1.0
const BACKOFF_MAX := 60.0
## A forward that stayed up this long earns a fresh backoff when it drops.
const STABLE_AFTER := 30.0
## AF_UNIX paths stop at ~104 bytes on macOS; leave room for the file name.
const LOCAL_PATH_MAX := 100
## Local forwards are hs-<godot pid>-<n>.sock, each with an hs-<pid>-<n>.pid
## sidecar naming its ssh, in a directory only this user can enter.
const LEFTOVER_PATTERN := "^(hs-(\\d+)-\\d+)\\.(sock|pid)$"
## The remote shell only prints a variable between markers, so whatever its rc
## files print around it (motd, nvm, echo) is ignored. fish, bash and zsh agree.
const HOME_COMMAND := "printf '\\nHS_HOME=%s\\nHS_END\\n' \"$HOME\""
const HOME_MAX := 256
const OUTPUT_KEEP := 65536
const STDERR_KEEP := 4096

static var _serial := 0
static var _directory := ""
static var _directory_error := ""
static var _directory_checked := false

## `HERDSTEAD_SSH` swaps the ssh binary, for tests and unusual installs.
var ssh_path := ""
var target := ""
var remote_session := ""
var local_socket := ""
var remote_socket := ""
var state := State.STOPPED
## Last thing that went wrong, for the name plate; cleared once a client got through.
var last_error := ""

var _home := ""
## The one ssh this link runs at a time: the $HOME lookup, then the forward.
## Both streams keep only their tail; the HOME markers come last.
var _ssh := ChildProcess.new(OUTPUT_KEEP, STDERR_KEEP)
var _left := 0.0
var _up_for := 0.0
var _backoff := BACKOFF_MIN
var _warned := ""


func _init() -> void:
	var override := OS.get_environment("HERDSTEAD_SSH")
	ssh_path = override if not override.is_empty() else "ssh"


## Empty when `value` can be handed to ssh as its destination. A leading `-`
## would be read as an option, so it is refused rather than escaped. So is any
## whitespace or invisible character, so the plate shows our reason, not ssh's.
static func check_target(value: String) -> String:
	if value.is_empty():
		return "empty SSH target"
	if value.begins_with("-"):
		return "SSH target must not start with '-'"
	for index in value.length():
		if _invisible(value.unicode_at(index)):
			return "SSH target has whitespace or control characters"
	return ""


## herdr's own rule for session names: ASCII letters, digits, `.`, `_`, `-`,
## and not `.` or `..`. Empty and the literal `default` mean the default session.
static func check_session(value: String) -> String:
	if value in [".", ".."] or not RegEx.create_from_string("^[A-Za-z0-9._-]*$").search(value):
		return "remote session name must be ASCII letters, digits, '.', '_' or '-'"
	return ""


## Empty when a remote $HOME can go into `-L`: one line of printable ASCII,
## absolute, bounded. ssh splits `-L` on `:` and expands `${VAR}` from the
## local environment in it, with no escape for either, so both are refused.
static func check_home(home: String) -> String:
	if not home.begins_with("/"):
		return "remote $HOME is not an absolute path"
	if home.length() > HOME_MAX:
		return "remote $HOME is longer than %d characters" % HOME_MAX
	for index in home.length():
		var code := home.unicode_at(index)
		if code < 0x20 or code > 0x7e:
			return "remote $HOME is not one line of printable ASCII"
	if ":" in home or "$" in home:
		return "remote $HOME contains ':' or '$', which ssh -L cannot carry"
	return ""


## The value between the markers HOME_COMMAND prints, from the last complete
## pair; null when there is none. Whatever else the shell printed is ignored.
static func parse_home(output: String) -> Variant:
	var end := output.rfind("\nHS_END")
	if end < 0:
		return null
	var begin := output.rfind("HS_HOME=", end)
	if begin < 0:
		return null
	return output.substr(begin + 8, end - begin - 8)


## The remote socket as herdr lays it out: the default session, or a named one.
static func remote_socket_path(home: String, session: String) -> String:
	var base := home.trim_suffix("/").path_join(".config/herdr")
	if session.is_empty() or session == "default":
		return base.path_join("herdr.sock")
	return base.path_join("sessions").path_join(session).path_join("herdr.sock")


## ssh expands `%` tokens in `-L` paths on this side; `%%` is a literal `%`.
static func escape_forward(path: String) -> String:
	return path.replace("%", "%%")


static func common_options() -> PackedStringArray:
	return PackedStringArray(
		[
			"-n",
			"-T",
			"-o",
			"BatchMode=yes",
			"-o",
			"ConnectTimeout=%d" % CONNECT_TIMEOUT,
			# Our own connection, never a shared master: killing this ssh must take
			# the forward down with it.
			"-o",
			"ControlPath=none",
			"-o",
			"LogLevel=ERROR",
		]
	)


## argv for the one-shot $HOME lookup. The target is its own element after `--`.
static func home_argv(ssh_target: String) -> PackedStringArray:
	var argv := common_options()
	argv.append_array(["--", ssh_target, HOME_COMMAND])
	return argv


## argv for the long-lived forward.
static func forward_argv(ssh_target: String, local: String, remote: String) -> PackedStringArray:
	var argv := PackedStringArray(["-N"])
	argv.append_array(common_options())
	(
		argv
		. append_array(
			[
				"-o",
				"ExitOnForwardFailure=yes",
				"-o",
				"ServerAliveInterval=%d" % ALIVE_INTERVAL,
				"-o",
				"ServerAliveCountMax=%d" % ALIVE_COUNT,
				"-o",
				"StreamLocalBindUnlink=yes",
				"-L",
				"%s:%s" % [escape_forward(local), escape_forward(remote)],
				"--",
				ssh_target,
			]
		)
	)
	return argv


# --- socket directory ---------------------------------------------------------


## Where local forwards live: `HERDSTEAD_SOCKET_DIR` when set, else $TMPDIR when
## it is private to this user (macOS gives every user one), else /tmp/hs-<uid>,
## created 0700. Anyone else able to enter the directory could plant a socket a
## client would trust, so a directory that is not ours and private is refused.
## `HERDSTEAD_SOCKET_DIR` is a hook for tests, captures and debugging, taken as
## it is: neither its mode, its owner nor its length is checked, since whoever
## sets it answers for it. One that does not exist yet is made, 0700.
## Empty when unusable; `socket_directory_error()` says why. Checked once.
## With `create` false nothing is made on disk and a miss is not remembered:
## the startup sweep must not leave a directory behind for a user with no machines.
static func socket_directory(create := true) -> String:
	if _directory_checked:
		return _directory
	var forced := OS.get_environment("HERDSTEAD_SOCKET_DIR").trim_suffix("/")
	if not forced.is_empty():
		if not DirAccess.dir_exists_absolute(forced):
			if not create:
				return ""
			DirAccess.make_dir_recursive_absolute(forced)
			_run("chmod", ["700", forced])
		_directory_checked = true
		if DirAccess.dir_exists_absolute(forced):
			_directory = forced
			_directory_error = ""
		else:
			_directory_error = "cannot make " + forced
			push_warning("No directory for machine sockets: " + _directory_error)
		return _directory
	var uid := _run("id", ["-u"]).strip_edges()
	var candidates := PackedStringArray()
	var tmp := OS.get_environment("TMPDIR").trim_suffix("/")
	if tmp.begins_with("/"):
		candidates.append(tmp)
	candidates.append("/tmp/hs-" + uid)
	for candidate in candidates:
		if candidate.to_utf8_buffer().size() + 24 > LOCAL_PATH_MAX or "$" in candidate or ":" in candidate:
			_directory_error = "%s is too long or unusable for a socket path" % candidate
			continue
		if candidate.begins_with("/tmp/hs-") and not DirAccess.dir_exists_absolute(candidate):
			if not create:
				continue
			DirAccess.make_dir_absolute(candidate)
			_run("chmod", ["700", candidate])
		var problem := _private_problem(candidate, uid)
		if problem.is_empty():
			_directory_checked = true
			_directory = candidate
			_directory_error = ""
			return _directory
		_directory_error = problem
	if create:
		_directory_checked = true
		push_warning("No private directory for machine sockets: " + _directory_error)
	return ""


static func socket_directory_error() -> String:
	return _directory_error


## Forget the directory choice; tests change HERDSTEAD_SOCKET_DIR between runs.
static func reset_socket_directory() -> void:
	_directory_checked = false
	_directory = ""
	_directory_error = ""


static func _private_problem(path: String, uid: String) -> String:
	# The trailing slash follows a symlink to the directory itself.
	var fields := _run("ls", ["-ldn", path + "/"]).split(" ", false)
	if fields.size() < 3:
		return path + " does not exist"
	var mode: String = fields[0]
	if not mode.begins_with("d") or mode.substr(4, 6) != "------":
		return "%s is not private (%s)" % [path, mode.substr(0, 10)]
	if fields[2] != uid:
		return "%s belongs to uid %s, not %s" % [path, fields[2], uid]
	return ""


## A fresh short path for this process's next forward, or empty without a
## usable directory.
static func next_local_socket() -> String:
	var directory := socket_directory()
	if directory.is_empty():
		return ""
	_serial += 1
	return directory.path_join("hs-%d-%d.sock" % [OS.get_process_id(), _serial])


# --- leftovers ----------------------------------------------------------------


## Clean up after Herdsteads that did not exit gracefully (SIGKILL, a crash,
## Force Quit): their ssh keeps running, still authenticated, still listening.
## A forward belongs to the process id in its name. When that process is gone,
## or is this very process (an earlier life with a recycled pid), its ssh is
## terminated, but only if that pid's command line still carries this socket
## in `-L`, then the socket and sidecar go. A living owner's files are not
## touched. Runs a few short commands synchronously: call it at startup only.
## Returns every path removed.
static func clean_leftovers(directory := "") -> PackedStringArray:
	var removed := PackedStringArray()
	if directory.is_empty():
		directory = socket_directory(false)
	var dir := DirAccess.open(directory) if not directory.is_empty() else null
	if dir == null:
		return removed
	var pattern := RegEx.create_from_string(LEFTOVER_PATTERN)
	var stems := {}
	for file_name in dir.get_files():
		var found := pattern.search(file_name)
		if found != null:
			stems[found.get_string(1)] = int(found.get_string(2))
	for stem: String in stems:
		var holder: int = stems[stem]
		if holder != OS.get_process_id() and process_exists(holder):
			continue
		var socket := directory.path_join(stem + ".sock")
		var sidecar := directory.path_join(stem + ".pid")
		if FileAccess.file_exists(sidecar):
			# Not JSON.parse_string(): it would echo a sidecar that is not JSON.
			var parsed: Variant = HerdrClient.parse_line(FileAccess.get_file_as_string(sidecar))
			if parsed is Dictionary:
				var record: Dictionary = parsed
				if typeof(record.get("ssh_pid")) == TYPE_FLOAT:
					var recorded: float = record.ssh_pid
					terminate_forward(int(recorded), socket)
			DirAccess.remove_absolute(sidecar)
			removed.append(sidecar)
		# FileAccess cannot see a socket; a regular file with our name is not ours.
		if dir.file_exists(stem + ".sock") and not FileAccess.file_exists(socket):
			if DirAccess.remove_absolute(socket) == OK:
				removed.append(socket)
	return removed


## Any process, any owner. `kill -0` cannot tell "gone" from "not yours".
static func process_exists(pid: int) -> bool:
	return pid > 0 and OS.execute("ps", ["-p", str(pid), "-o", "pid="], [], false) == 0


## SIGTERM `pid` only when its command line is an ssh forward of `socket`;
## a recycled pid running something else is left alone. True when signalled.
static func terminate_forward(pid: int, socket: String) -> bool:
	if pid <= 0:
		return false
	# -ww: never cut the command line to a terminal width.
	var command := _run("ps", ["-ww", "-p", str(pid), "-o", "command="])
	if not (" -L " in command and (" %s:" % escape_forward(socket)) in command):
		return false
	return OS.execute("kill", ["-TERM", str(pid)], [], false) == 0


static func _run(command: String, arguments: PackedStringArray) -> String:
	var output: Array = []
	OS.execute(command, arguments, output, false)
	return "" if output.is_empty() else str(output[0])


static func _invisible(code: int) -> bool:
	return (
		code <= 0x20
		or (code >= 0x7f and code <= 0xa0)
		or code == 0x1680
		or (code >= 0x2000 and code <= 0x200f)
		or (code >= 0x2028 and code <= 0x202f)
		or code == 0x205f
		or code == 0x3000
		or code == 0xfeff
	)


# --- lifecycle ----------------------------------------------------------------


func start(ssh_target: String, session := "") -> void:
	stop()
	target = ssh_target
	remote_session = session
	_home = ""
	remote_socket = ""
	_backoff = BACKOFF_MIN
	var problem := check_target(target)
	if problem.is_empty():
		problem = check_session(session)
	if problem.is_empty() and local_socket.is_empty():
		local_socket = next_local_socket()
		if local_socket.is_empty():
			problem = "no private socket directory: " + socket_directory_error()
	if not problem.is_empty():
		# A bad config line stays bad until it changes; no retry loop for it.
		_halt(problem)
		return
	set_process(true)
	_resolve()


## Kill ssh and remove the local socket. Safe to call any number of times.
func stop() -> void:
	set_process(false)
	_kill()
	_remove_socket()
	state = State.STOPPED


## A client got through, so whatever went wrong before no longer applies.
func clear_error() -> void:
	if last_error.is_empty():
		return
	last_error = ""
	_warned = ""
	_ssh.clear_stderr()
	state_changed.emit()


## The process id of the ssh running now, -1 while none is. The sidecar next to
## the local socket records the forward's too.
func ssh_pid() -> int:
	return _ssh.pid


func _exit_tree() -> void:
	stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_kill()
		_remove_socket()


func _process(delta: float) -> void:
	match state:
		State.RESOLVING:
			_ssh.drain()
			if _ssh.running():
				_left -= delta
				if _left <= 0.0:
					_kill()
					_fail("no answer from %s in %ds" % [target, int(RESOLVE_TIMEOUT)])
				return
			var code := _ssh.exit_code()
			_ssh.drain()
			_ssh.release()
			if code != 0:
				_fail(_complaint(code))
				return
			var home: Variant = parse_home(_ssh.stdout.get_string_from_utf8())
			if home == null:
				_fail("remote shell printed no HS_HOME line")
				return
			var problem := check_home(str(home))
			if not problem.is_empty():
				# The same answer would come back on every retry.
				_halt(problem)
				return
			_home = home
			remote_socket = remote_socket_path(_home, remote_session)
			_forward()
		State.FORWARDING:
			_ssh.drain()
			if _ssh.running():
				_up_for += delta
				if _up_for >= STABLE_AFTER:
					_backoff = BACKOFF_MIN
				# ssh keeps running when the remote socket is missing and only
				# reports it per connection; surface that while it lasts.
				var complaint := _last_line(_ssh.stderr)
				if complaint != last_error and not complaint.is_empty():
					_set_error(complaint)
				return
			var code := _ssh.exit_code()
			_ssh.drain()
			_ssh.release()
			_fail(_complaint(code))
		State.WAITING:
			_left -= delta
			if _left <= 0.0:
				if _home.is_empty():
					_resolve()
				else:
					_forward()


func _resolve() -> void:
	if not _spawn(home_argv(target)):
		return
	state = State.RESOLVING
	_left = RESOLVE_TIMEOUT
	state_changed.emit()


func _forward() -> void:
	# StreamLocalBindUnlink handles our own stale file too, but a leftover from
	# the previous attempt must not look like a live forward in the meantime.
	_remove_socket()
	if not _spawn(forward_argv(target, local_socket, remote_socket)):
		return
	# The sidecar lets a later Herdstead find this ssh if we die without exiting.
	var sidecar := FileAccess.open(_sidecar_path(), FileAccess.WRITE)
	if sidecar != null:
		sidecar.store_string(JSON.stringify({"ssh_pid": _ssh.pid, "socket": local_socket, "target": target}))
		sidecar.close()
	state = State.FORWARDING
	_up_for = 0.0
	state_changed.emit()


func _spawn(argv: PackedStringArray) -> bool:
	if not _ssh.spawn(ssh_path, argv):
		_fail("cannot run " + ssh_path)
		return false
	return true


func _kill() -> void:
	_ssh.kill()


func _complaint(code: int) -> String:
	var line := _last_line(_ssh.stderr)
	return line if not line.is_empty() else "ssh exited with %d" % code


static func _last_line(buffer: PackedByteArray) -> String:
	var lines := buffer.get_string_from_utf8().strip_edges().split("\n", false)
	return "" if lines.is_empty() else lines[lines.size() - 1].strip_edges()


func _fail(reason: String) -> void:
	_remove_socket()
	state = State.WAITING
	_left = _backoff
	_backoff = minf(BACKOFF_MAX, _backoff * 2.0)
	_set_error(reason)
	if OS.is_stdout_verbose():
		print("machine %s offline, retrying in %.0fs" % [target, _left])


## Stop for good: retrying cannot help until the configuration changes.
func _halt(reason: String) -> void:
	stop()
	_set_error(reason)


func _set_error(reason: String) -> void:
	last_error = reason
	# One warning per distinct complaint, not one per retry.
	if reason != _warned:
		_warned = reason
		push_warning("machine %s: %s" % [target, reason])
	state_changed.emit()


func _sidecar_path() -> String:
	return local_socket.get_basename() + ".pid"


func _remove_socket() -> void:
	if local_socket.is_empty():
		return
	var dir := DirAccess.open(local_socket.get_base_dir())
	if dir == null:
		return
	if dir.file_exists(local_socket.get_file()):
		DirAccess.remove_absolute(local_socket)
	if dir.file_exists(_sidecar_path().get_file()):
		DirAccess.remove_absolute(_sidecar_path())
