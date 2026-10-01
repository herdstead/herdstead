extends "res://tools/machine_test_base.gd"
## Headless tests for herdr machines: the machine list adapter, the SSH forward
## (with tools/fake_ssh.py standing in for ssh), and the office aggregating two
## fake herdr servers whose pane ids collide. Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_machines.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir> \
##     --ssh=<executable running tools/fake_ssh.py>
##
## Unlike test_client.gd this runs on real frames: the office, its clients and
## the forward all live in the tree. Exits 0 when every check passes, 1 on any
## failure, 2 on a harness error.


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket-a", "control-a", "socket-b", "control-b", "work", "ssh"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s= (use tools/run_tests.sh)" % name)
			quit(2)
			return
	# Every forward and every leftover sweep stays inside the test's own directory,
	# and every ssh any office starts is the fake one.
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("socks"))
	OS.set_environment("HERDSTEAD_SSH", args.ssh)
	MachineLink.reset_socket_directory()
	_run()


func _run() -> void:
	# A press only reaches a Control that is inside the viewport, and headless
	# starts with a 64x64 one. Give the root the size the offices here pretend
	# to have, so `_press` lands where a click in a real window would. The
	# window only takes a size once the main loop is running.
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "MACHINE TESTS"


# --- pure ---------------------------------------------------------------------


func test_machine_list_adapter() -> void:
	_eq(MachineRoster.parse_list("[]"), [], "empty list")
	_eq(MachineRoster.parse_list("not json"), null, "garbage is not a list")
	_eq(MachineRoster.parse_list('{"error": 1}'), null, "an object without a list is not a list")
	var documented: Array[MachineRoster.Machine] = (
		MachineRoster
		. parse_list(
			(
				JSON
				. stringify(
					[
						{
							"profile_id": "p1",
							"label": "Build box",
							"ssh_target": "me@build",
							"remote_session": "work",
							"enabled": true
						},
						{"id": "p2", "name": "gpu", "target": "gpu.lan", "session": null, "enabled": false},
						{"profile": "p3", "ssh": "pi@pi", "enabled": "true"},
						{"label": "no target"},
						{"profile_id": "p1", "ssh_target": "dup@again"},
						"not a record",
					]
				)
			)
		)
	)
	_eq(
		documented.map(func(m: MachineRoster.Machine) -> String: return m.key),
		["machine:p1", "machine:p2", "machine:p3"],
		"keys from the profile id; no target or a repeat id is dropped"
	)
	_eq(
		_machine_fields(documented[0]), ["machine:p1", "p1", "Build box", "me@build", "work", true], "documented fields"
	)
	_eq(
		[documented[1].label, documented[1].target, documented[1].session, documented[1].enabled],
		["gpu", "gpu.lan", "", false],
		"alias spellings, null session, disabled"
	)
	_eq(
		[documented[2].label, documented[2].enabled], ["pi@pi", true], "label falls back to the target; enabled as text"
	)
	var wrapped: Array = MachineRoster.parse_list('{"machines": [{"ssh_target": "a@b"}]}')
	_eq(wrapped.size(), 1, "an object wrapping the list")
	_eq(
		[wrapped[0].key, wrapped[0].enabled],
		["machine:a@b/", true],
		"no id: keyed by target and session, enabled by default"
	)
	# The roster announces a list only when it differs, field for field.
	var record := {"profile_id": "p1", "label": "Build box", "ssh_target": "me@build", "remote_session": "work"}
	var again: Array[MachineRoster.Machine] = [MachineRoster.normalize(record)]
	var first: Array[MachineRoster.Machine] = [documented[0]]
	_check(MachineRoster.same_list(again, first), "the same machine read twice is the same list")
	again[0].label = "renamed"
	_check(not MachineRoster.same_list(again, first), "a new label is a new list")
	var none: Array[MachineRoster.Machine] = []
	_check(not MachineRoster.same_list(none, first), "and so is a shorter one")
	# JSON numbers are floats in Godot: `1` must not read as disabled, `7` not as `7.0`.
	var typed: Array = (
		MachineRoster
		. parse_list(
			(
				JSON
				. stringify(
					[
						{"profile_id": 7, "label": 42, "ssh_target": "a@b", "enabled": 1},
						{"profile_id": 8.5, "ssh_target": "c@d", "enabled": 0},
						{"profile_id": "p9", "ssh_target": "e@f", "enabled": "off"},
						{"profile_id": "p10", "ssh_target": "g@h", "enabled": null},
						{"profile_id": "p11", "ssh_target": "i@j", "enabled": [1]},
					]
				)
			)
		)
	)
	_eq(
		typed.map(func(m: MachineRoster.Machine) -> Array: return [m.key, m.label, m.enabled]),
		[
			["machine:7", "42", true],
			["machine:8.5", "c@d", false],
			["machine:p9", "e@f", false],
			["machine:p10", "g@h", true],
			["machine:p11", "i@j", false],
		],
		"numbers, text and null for enabled; whole numbers without .0"
	)
	var sneaky := MachineRoster.normalize({"profile_id": "p\u001fx", "label": "a\nb\u2028c", "ssh_target": "k@l"})
	_eq([sneaky.key, sneaky.label], ["machine:px", "abc"], "control characters never reach keys or labels")


## What `herdr machine list --json` prints is remote input (invariant 9): text
## that is not JSON reads as no list, and none of it reaches the log. The engine
## quotes the first word it cannot read, letters only, into JSON.parse_string()'s
## error, so the marker is a bare word where a value belongs. A list that is JSON
## reads as it always did, bare, wrapped or pretty-printed.
func test_a_machine_list_that_is_not_json_is_never_echoed() -> void:
	var marker := "machinelistsentinel"
	var printed := '[{"ssh_target": "me@far", "label": %s}]' % marker
	var garbled: Variant = _never_logged(marker, func() -> Variant: return MachineRoster.parse_list(printed))
	_eq(garbled, null, "a list that is not JSON is no list")
	var rows := [{"profile_id": "p1", "label": "Build box", "ssh_target": "me@build", "remote_session": "work"}]
	var texts := [JSON.stringify(rows), JSON.stringify(rows, "  ")]
	for key: String in ["machines", "profiles", "items"]:
		texts.append(JSON.stringify({key: rows}))
	for text: String in texts:
		var listed: Variant = MachineRoster.parse_list(text)
		var machines: Array = listed if listed is Array else []
		_eq(
			machines.map(func(m: MachineRoster.Machine) -> Array: return _machine_fields(m)),
			[["machine:p1", "p1", "Build box", "me@build", "work", true]],
			"reads as before: " + text.left(48).c_escape()
		)


func test_machine_socket_args() -> void:
	var parsed := (
		MachineRoster
		. parse_socket_args(
			PackedStringArray(
				[
					"--wait=1",
					"--machine-socket=bee=/tmp/b.sock",
					"--machine-socket=odd=/tmp/x=y.sock",
					"--machine-socket=nolabel",
					"--machine-socket==/tmp/c.sock",
					"--machine-socket=empty=",
					"--machine-socket=a\u001fb=/tmp/x.sock",
				]
			)
		)
	)
	_eq(
		parsed.map(func(entry: MachineRoster.DebugSocket) -> Array: return [entry.label, entry.socket]),
		[["bee", "/tmp/b.sock"], ["odd", "/tmp/x=y.sock"]],
		"label ends at the first =; malformed skipped"
	)


func test_link_argv() -> void:
	_eq(
		MachineLink.home_argv("me@build"),
		PackedStringArray(
			[
				"-n",
				"-T",
				"-o",
				"BatchMode=yes",
				"-o",
				"ConnectTimeout=10",
				"-o",
				"ControlPath=none",
				"-o",
				"LogLevel=ERROR",
				"--",
				"me@build",
				"printf '\\nHS_HOME=%s\\nHS_END\\n' \"$HOME\"",
			]
		),
		"home lookup argv"
	)
	_eq(
		Array(MachineLink.forward_argv("t", "/d/a%b.sock", "/h/50%/x.sock")).slice(-4, -1),
		["-L", "/d/a%%b.sock:/h/50%%/x.sock", "--"],
		"% is escaped on both sides of -L"
	)
	_eq(
		MachineLink.forward_argv("me@build", "/tmp/hs-1-1.sock", "/home/me/.config/herdr/herdr.sock"),
		PackedStringArray(
			[
				"-N",
				"-n",
				"-T",
				"-o",
				"BatchMode=yes",
				"-o",
				"ConnectTimeout=10",
				"-o",
				"ControlPath=none",
				"-o",
				"LogLevel=ERROR",
				"-o",
				"ExitOnForwardFailure=yes",
				"-o",
				"ServerAliveInterval=15",
				"-o",
				"ServerAliveCountMax=3",
				"-o",
				"StreamLocalBindUnlink=yes",
				"-L",
				"/tmp/hs-1-1.sock:/home/me/.config/herdr/herdr.sock",
				"--",
				"me@build",
			]
		),
		"forward argv"
	)
	_check(
		not "StrictHostKeyChecking=no" in MachineLink.forward_argv("a", "b", "c"), "never accepts unknown hosts blindly"
	)
	_eq(MachineLink.remote_socket_path("/home/me", ""), "/home/me/.config/herdr/herdr.sock", "default session socket")
	_eq(
		MachineLink.remote_socket_path("/home/me/", "default"),
		"/home/me/.config/herdr/herdr.sock",
		"herdr's explicit default session uses the root socket"
	)
	_eq(
		MachineLink.remote_socket_path("/home/me/", "work"),
		"/home/me/.config/herdr/sessions/work/herdr.sock",
		"named session socket"
	)
	for named: String in ["Default", "default-work"]:
		_eq(
			MachineLink.remote_socket_path("/home/me", named),
			"/home/me/.config/herdr/sessions/%s/herdr.sock" % named,
			"only the exact name 'default' is special"
		)
	_eq(MachineLink.check_target("me@build"), "", "a plain target is fine")
	_eq(MachineLink.check_target("ssh://me@build:2222"), "", "an ssh URI is fine")
	for bad: String in [
		"",
		"-oProxyCommand=touch /tmp/x",
		"-p",
		"me@build extra",
		"me@build\n",
		"me@build\u00a0",
		"me\u2028@b",
		"me\u007f@b",
		"me\u200b@b"
	]:
		_check(not MachineLink.check_target(bad).is_empty(), "refuses target %s" % JSON.stringify(bad))
	for bad: String in ["..", ".", "a/b", "a:b", "a%b", "a b", "a\u2028b", "caf\u00e9", "a$b"]:
		_check(not MachineLink.check_session(bad).is_empty(), "refuses session %s" % JSON.stringify(bad))
	_eq(MachineLink.check_session(""), "", "default session")
	_eq(MachineLink.check_session("default"), "", "herdr's explicit default session")
	_eq(MachineLink.check_session("work.1_x-Y"), "", "herdr's session characters")
	var path := MachineLink.next_local_socket()
	_check(
		path.begins_with(args.work.path_join("socks/hs-%d-" % OS.get_process_id())) and path.ends_with(".sock"),
		"local socket in the socket directory with our pid"
	)
	_check(path.to_utf8_buffer().size() < 104, "local socket path fits AF_UNIX")
	_check(MachineLink.next_local_socket() != path, "every forward gets its own path")


func test_link_home_checks() -> void:
	for good: String in ["/home/me", "/Users/John Smith", "/h/50%"]:
		_eq(MachineLink.check_home(good), "", "accepts home " + good)
	for bad: String in ["", "home/me", "~", "/a\nb", "/a:b", "/a${USER}b", "/a$b", "/caf\u00e9", "/" + "x".repeat(300)]:
		_check(not MachineLink.check_home(bad).is_empty(), "refuses home %s" % JSON.stringify(bad.left(40)))
	_eq(MachineLink.parse_home("\nHS_HOME=/home/me\nHS_END\n"), "/home/me", "plain answer")
	_eq(
		MachineLink.parse_home("Welcome to Ubuntu\nnvm: v20\n\nHS_HOME=/home/me\nHS_END\nbye\n"),
		"/home/me",
		"rc noise before and after"
	)
	_eq(MachineLink.parse_home("HS_HOME=/fake\nHS_END\n\nHS_HOME=/real\nHS_END\n"), "/real", "the last pair wins")
	_eq(MachineLink.parse_home("/home/me"), null, "no markers is no answer")
	_eq(MachineLink.parse_home("\nHS_HOME=/a\nb\nHS_END\n"), "/a\nb", "a multi-line HOME comes back whole")
	var split := str(MachineLink.parse_home("\nHS_HOME=/a\nb\nHS_END\n"))
	_check(not MachineLink.check_home(split).is_empty(), "and is refused")


## The default directory is private to us; anything group- or world-open is not.
func test_socket_directory() -> void:
	OS.unset_environment("HERDSTEAD_SOCKET_DIR")
	MachineLink.reset_socket_directory()
	var chosen := MachineLink.socket_directory()
	var uid := _output("id", ["-u"]).strip_edges()
	_check(not chosen.is_empty(), "a default socket directory exists: " + MachineLink.socket_directory_error())
	_eq(MachineLink._private_problem(chosen, uid), "", "and it is private to this user")
	_check(chosen.to_utf8_buffer().size() + 24 <= MachineLink.LOCAL_PATH_MAX, "and short enough for socket paths")
	var open: String = args.work.path_join("open")
	DirAccess.make_dir_recursive_absolute(open)
	OS.execute("chmod", ["755", open])
	_check(MachineLink._private_problem(open, uid).contains("not private"), "a 0755 directory is refused")
	OS.execute("chmod", ["700", open])
	_eq(MachineLink._private_problem(open, uid), "", "a 0700 one is fine")
	# Any uid that is not this one; running as root is a container-CI reality, so
	# "0" cannot be hardcoded as "someone else".
	var stranger := "1" if uid == "0" else "0"
	_check(MachineLink._private_problem(open, stranger).contains("belongs to"), "someone else's is refused")
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("socks"))
	MachineLink.reset_socket_directory()


func test_link_refuses_option_target() -> void:
	var log_path: String = args.work.path_join("refuse.log")
	OS.set_environment("FAKE_SSH_LOG", log_path)
	var link := _link()
	link.start("-oProxyCommand=touch /tmp/owned")
	_eq(link.state, MachineLink.State.STOPPED, "no retry loop for a bad target")
	_check(not link.last_error.is_empty(), "the refusal is reported")
	_check(link.ssh_pid() < 0, "no ssh process was started")
	# fake_ssh logs asynchronously; give a spawn it did not make time to show.
	for i in 20:
		await process_frame
	_check(not FileAccess.file_exists(log_path), "ssh never ran")
	link.start("me@build", "../etc")
	_eq(link.state, MachineLink.State.STOPPED, "a session that escapes the sessions directory is refused too")
	link.free()
	OS.unset_environment("FAKE_SSH_LOG")


func test_leftover_cleanup() -> void:
	var dir: String = args.work.path_join("left")
	DirAccess.make_dir_recursive_absolute(dir)
	var dead := 999999
	while MachineLink.process_exists(dead):
		dead -= 1
	# A Herdstead that died without exiting: its ssh still runs and listens.
	var orphan_sock := dir.path_join("hs-%d-1.sock" % dead)
	var orphan := OS.create_process(args.ssh, MachineLink.forward_argv("me@far", orphan_sock, args["socket-b"]))
	_sidecar(dir.path_join("hs-%d-1.pid" % dead), orphan)
	await _until(func() -> bool: return _socket_exists(orphan_sock), "orphan listening")
	# The sidecar points at a recycled pid that runs something else entirely.
	var stranger := OS.create_process("sleep", ["30"])
	_bind(dir.path_join("hs-%d-2.sock" % dead))
	_sidecar(dir.path_join("hs-%d-2.pid" % dead), stranger)
	# An earlier life of this very pid.
	_bind(dir.path_join("hs-%d-9.sock" % OS.get_process_id()))
	# A living owner (pid 1 always exists), even with no one listening.
	_bind(dir.path_join("hs-1-1.sock"))
	_sidecar(dir.path_join("hs-1-1.pid"), stranger)
	# Not ours: a regular file with our name, and a socket with another name.
	FileAccess.open(dir.path_join("hs-%d-3.sock" % dead), FileAccess.WRITE).store_string("not a socket")
	_bind(dir.path_join("other-%d-1.sock" % dead))
	var removed := MachineLink.clean_leftovers(dir)
	removed.sort()
	var expected := PackedStringArray(
		[
			dir.path_join("hs-%d-1.pid" % dead),
			orphan_sock,
			dir.path_join("hs-%d-2.pid" % dead),
			dir.path_join("hs-%d-2.sock" % dead),
			dir.path_join("hs-%d-9.sock" % OS.get_process_id()),
		]
	)
	expected.sort()
	_eq(removed, expected, "a dead owner's forward and sidecar, and our own earlier life")
	await _until(func() -> bool: return not OS.is_process_running(orphan), "orphan ssh terminated")
	_check(OS.is_process_running(stranger), "a recycled pid running something else is not killed")
	var left := DirAccess.get_files_at(dir)
	left.sort()
	var kept := PackedStringArray(["hs-1-1.pid", "hs-1-1.sock", "hs-%d-3.sock" % dead, "other-%d-1.sock" % dead])
	kept.sort()
	_eq(left, kept, "a living owner, regular files and strangers stay")
	# Never leave either behind, even when the sweep failed: an orphan holds the
	# test's output pipe open and would hang run_tests.sh.
	for pid: int in [orphan, stranger]:
		if OS.is_process_running(pid):
			OS.kill(pid)


## A sidecar is a file in the socket directory, so it holds whatever a crash or
## someone else left there. One that is not JSON goes with its socket like any
## other leftover, and none of it reaches the log (the marker as in
## test_a_machine_list_that_is_not_json_is_never_echoed).
func test_a_sidecar_that_is_not_json_is_never_echoed() -> void:
	var marker := "sidecarsentinel"
	var dir: String = args.work.path_join("garbled")
	DirAccess.make_dir_recursive_absolute(dir)
	var dead := 999999
	while MachineLink.process_exists(dead):
		dead -= 1
	var sidecar := dir.path_join("hs-%d-1.pid" % dead)
	var socket := dir.path_join("hs-%d-1.sock" % dead)
	_write(sidecar, '{"ssh_pid": %s}' % marker)
	_bind(socket)
	var swept: Variant = _never_logged(marker, func() -> Variant: return MachineLink.clean_leftovers(dir))
	var removed: PackedStringArray = swept if swept is PackedStringArray else PackedStringArray()
	removed.sort()
	var expected := PackedStringArray([sidecar, socket])
	expected.sort()
	_eq(removed, expected, "the unreadable sidecar and its socket are swept like any other")


# --- forward ------------------------------------------------------------------


func test_link_forwards_and_cleans_up() -> void:
	# A % in the remote home must survive ssh's own % expansion.
	var home: String = args.work.path_join("h%1")
	DirAccess.make_dir_recursive_absolute(home.path_join(".config/herdr"))
	OS.execute("ln", ["-sf", args["socket-b"], home.path_join(".config/herdr/herdr.sock")])
	var log_path: String = args.work.path_join("forward.log")
	OS.set_environment("FAKE_SSH_HOME", home)
	OS.set_environment("FAKE_SSH_LOG", log_path)
	# Login shells print things; only the markers count.
	OS.set_environment("FAKE_SSH_NOISE", "Welcome!\nHS_HOME=/decoy\nnvm ready\n")
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	var link := _link()
	root.add_child(link)
	link.start("me@far away-host")
	_eq(link.state, MachineLink.State.STOPPED, "a target with a space is refused")
	link.start("me@far")
	_eq(link.state, MachineLink.State.RESOLVING, "starts by asking for $HOME")
	await _until(
		func() -> bool: return link.state == MachineLink.State.FORWARDING and _socket_exists(link.local_socket),
		"forward listening"
	)
	_eq(
		link.remote_socket,
		home.path_join(".config/herdr/herdr.sock"),
		"remote socket from the remote $HOME, past the noise"
	)
	var calls := FileAccess.get_file_as_string(log_path).strip_edges().split("\n")
	_eq(calls.size(), 2, "one home lookup, one forward")
	_eq(JSON.parse_string(calls[0]), Array(MachineLink.home_argv("me@far")), "home lookup argv as sent")
	_eq(
		JSON.parse_string(calls[1]),
		Array(MachineLink.forward_argv("me@far", link.local_socket, link.remote_socket)),
		"forward argv as sent"
	)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(link._sidecar_path()))
	var sidecar: Dictionary = parsed if parsed is Dictionary else {}
	_eq(int(_number(sidecar, "ssh_pid")), link.ssh_pid(), "the sidecar names this ssh")
	var herdr := HerdrClient.new()
	root.add_child(herdr)
	herdr.start(link.local_socket)
	await _until(
		func() -> bool: return herdr.online and herdr.snapshot.panes.size() == 4, "client online through the forward"
	)
	var pid := link.ssh_pid()
	var local := link.local_socket
	var sidecar_path := link._sidecar_path()
	herdr.stop()
	herdr.free()
	# Leaving the tree is what a quitting office does to its links.
	root.remove_child(link)
	_check(not _socket_exists(local), "local socket removed on exit")
	_check(not FileAccess.file_exists(sidecar_path), "sidecar removed on exit")
	_check(not _alive(pid), "ssh killed on exit")
	_eq(link.state, MachineLink.State.STOPPED, "stopped")
	link.free()
	OS.unset_environment("FAKE_SSH_LOG")
	OS.unset_environment("FAKE_SSH_NOISE")


## `HERDSTEAD_SOCKET_DIR` naming a directory that does not exist yet, as the
## smoke, capture and perf runs and most suites set it: the startup sweep looks
## there without making it, and must not remember the miss, or the first forward
## has nowhere to listen. In the office's order: the sweep, then a forward
## through fake_ssh that a client gets through.
func test_a_forced_directory_is_made_by_the_first_forward() -> void:
	var fresh: String = args.work.path_join("fresh/socks")
	OS.set_environment("HERDSTEAD_SOCKET_DIR", fresh)
	MachineLink.reset_socket_directory()
	_eq(MachineLink.clean_leftovers(), PackedStringArray(), "the startup sweep has nothing to remove")
	_check(not DirAccess.dir_exists_absolute(fresh), "and makes no directory")
	var home: String = args.work.path_join("fresh-home")
	DirAccess.make_dir_recursive_absolute(home.path_join(".config/herdr"))
	OS.execute("ln", ["-sf", args["socket-b"], home.path_join(".config/herdr/herdr.sock")])
	var home_before := OS.get_environment("FAKE_SSH_HOME")
	OS.set_environment("FAKE_SSH_HOME", home)
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	var link := _link()
	root.add_child(link)
	link.start("me@far")
	await _until(
		func() -> bool: return link.state == MachineLink.State.FORWARDING and _socket_exists(link.local_socket),
		"the first forward listening"
	)
	_check(link.local_socket.begins_with(fresh + "/"), "in the forced directory: " + link.local_socket)
	_check(_output("ls", ["-ldn", fresh]).begins_with("drwx------"), "which it made, private to this user")
	var herdr := HerdrClient.new()
	root.add_child(herdr)
	herdr.start(link.local_socket)
	await _until(func() -> bool: return herdr.online and herdr.snapshot.panes.size() == 4, "a client through it")
	herdr.stop()
	herdr.free()
	root.remove_child(link)
	link.free()
	if home_before.is_empty():
		OS.unset_environment("FAKE_SSH_HOME")
	else:
		OS.set_environment("FAKE_SSH_HOME", home_before)
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("socks"))
	MachineLink.reset_socket_directory()


## herdr 0.9.0/0.9.1 machine list rows include the literal session "default".
## Reach two distinct snapshots so a named session cannot silently use default.
func test_machine_list_session_forwards() -> void:
	var machines: Array[MachineRoster.Machine] = (
		MachineRoster
		. parse_list(
			"""[
			{"id":"p1","label":"Default","target":"me@far","session":"default","enabled":true,"selected":true},
			{"id":"p2","label":"Work","target":"me@far","session":"work","enabled":true,"selected":false}
		]"""
		)
	)
	_eq(machines.size(), 2, "the complete upstream machine-list shape is accepted")
	var home := args.work.path_join("sessions")
	var sockets: Array[String] = [
		home.path_join(".config/herdr/herdr.sock"),
		home.path_join(".config/herdr/sessions/work/herdr.sock"),
	]
	var controls: Array[String] = ["control-b", "control-a"]
	var upstreams: Array[String] = [args["socket-b"], args["socket-a"]]
	var pane_counts: Array[int] = [4, 13]
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-a", "reset", {"fixture": "snapshot_floors"})
	OS.set_environment("FAKE_SSH_HOME", home)
	for index in machines.size():
		var machine := machines[index]
		var target := machine.target
		var session := machine.session
		var remote := sockets[index]
		DirAccess.make_dir_recursive_absolute(remote.get_base_dir())
		OS.execute("ln", ["-s", upstreams[index], remote])
		var log_path := args.work.path_join("session-%d.log" % index)
		OS.set_environment("FAKE_SSH_LOG", log_path)
		var link := _link()
		root.add_child(link)
		link.start(target, session)
		await _until(
			func() -> bool: return link.state == MachineLink.State.FORWARDING and _socket_exists(link.local_socket),
			"machine-list session forward listening"
		)
		_eq(link.remote_socket, remote, "machine-list session resolves to its upstream socket")
		var calls := FileAccess.get_file_as_string(log_path).strip_edges().split("\n")
		_eq(calls.size(), 2, "one home lookup and one forward per session")
		if calls.size() == 2:
			var forwarded: Array = JSON.parse_string(calls[1])
			_eq(
				forwarded.slice(-4),
				["-L", "%s:%s" % [link.local_socket, remote], "--", "me@far"],
				"fake ssh receives the expected socket and a separate target argv"
			)
		var herdr := HerdrClient.new()
		root.add_child(herdr)
		herdr.start(link.local_socket)
		await _until(func() -> bool: return herdr.online and herdr.snapshot_current, "machine-list session snapshot")
		_eq(herdr.snapshot.panes.size(), pane_counts[index], "snapshot came from the requested session")
		herdr.free()
		link.free()
		var stats := _ctl(controls[index], "stats")
		_eq(stats.violations, [], "forwarded requests remain well-formed and read-only")
		for method: String in stats.methods:
			_check(method in ["ping", "session.snapshot", "events.subscribe"], "only read-only methods are sent")
	OS.unset_environment("FAKE_SSH_HOME")
	OS.unset_environment("FAKE_SSH_LOG")


## A home ssh -L cannot carry stops the link for good; unreadable output retries.
func test_link_bad_home_stops() -> void:
	var log_path: String = args.work.path_join("badhome.log")
	OS.set_environment("FAKE_SSH_LOG", log_path)
	for bad: String in ["/a:b", "/a\nb", "/x${USER}", "/" + "y".repeat(400)]:
		OS.set_environment("FAKE_SSH_HOME", bad)
		var link := _link()
		root.add_child(link)
		link.start("me@far")
		await _until(func() -> bool: return link.state != MachineLink.State.RESOLVING, "home answer")
		_eq(link.state, MachineLink.State.STOPPED, "no retry loop for home %s" % JSON.stringify(bad.left(20)))
		_check(link.last_error.begins_with("remote $HOME"), "the plate says why: " + link.last_error)
		root.remove_child(link)
		link.free()
	_check(not FileAccess.get_file_as_string(log_path).contains('"-N"'), "no forward was ever started")
	OS.set_environment("FAKE_SSH_SWALLOW", "1")
	OS.set_environment("FAKE_SSH_NOISE", "motd only\n")
	var link := _link()
	root.add_child(link)
	link.start("me@far")
	await _until(func() -> bool: return link.state != MachineLink.State.RESOLVING, "unreadable answer")
	_eq(
		[link.state, link.last_error],
		[MachineLink.State.WAITING, "remote shell printed no HS_HOME line"],
		"output without markers has its own message and retries"
	)
	root.remove_child(link)
	link.free()
	OS.unset_environment("FAKE_SSH_SWALLOW")
	OS.unset_environment("FAKE_SSH_NOISE")
	OS.unset_environment("FAKE_SSH_LOG")
	OS.set_environment("FAKE_SSH_HOME", args.work.path_join("h%1"))


func test_link_failure_backs_off() -> void:
	OS.set_environment("FAKE_SSH_FAIL", "Permission denied (publickey).")
	var link := _link()
	root.add_child(link)
	link.start("me@far")
	await _until(func() -> bool: return link.state == MachineLink.State.WAITING, "first failure")
	_eq(link.last_error, "Permission denied (publickey).", "ssh's complaint is kept for the plate")
	_check(link._backoff == 2.0 and link._left > 0.0 and link._left <= 1.0, "first retry within 1s")
	_check(not _socket_exists(link.local_socket), "no socket while down")
	link._left = 0.0
	await _until(
		func() -> bool: return link.state == MachineLink.State.WAITING and link._backoff == 4.0, "second failure"
	)
	_check(link._left > 1.0 and link._left <= 2.0, "backoff doubles")
	for i in 8:
		link._fail("again")
	_eq(link._left, MachineLink.BACKOFF_MAX, "backoff stops at the cap")
	# Recovery: once a client gets through, the old complaint is history.
	OS.unset_environment("FAKE_SSH_FAIL")
	link._left = 0.0
	await _until(func() -> bool: return link.state == MachineLink.State.FORWARDING, "forwarding again")
	_eq(link.last_error, "again", "the complaint stays until a client gets through")
	link.clear_error()
	_eq(link.last_error, "", "cleared")
	root.remove_child(link)
	link.free()


func test_from_wire() -> void:
	var office := _office(Vector2(800, 480))
	var nothing := HerdrSnapshot.from_wire("nope")
	_check(nothing.is_empty(), "not an object")
	_eq(nothing.signature(), HerdrSnapshot.new().signature(), "reads as no snapshot at all")
	var clean := HerdrSnapshot.from_wire(_malformed())
	_eq(
		clean.workspaces.map(func(w: HerdrSnapshot.Workspace) -> Array: return [w.workspace_id, w.label, w.number]),
		[["", "", 0], ["w2", "w2", 3]],
		"non-objects dropped, wrong types read as absent"
	)
	_eq(
		clean.tabs.map(func(t: HerdrSnapshot.Tab) -> Array: return [t.tab_id, t.workspace_id, t.label, t.number]),
		[["w2:t1", "w2", "9", 0]],
		"tab fields typed"
	)
	_check(
		HerdrSnapshot.from_wire({"tabs": "nope", "panes": 3}).tabs.is_empty(),
		"a collection that is not a list is empty"
	)
	_eq(
		_pane_fields(clean.panes[0]),
		["5", "", "", "w2", "", "3", null, false, false, "", "", "", "unknown"],
		"every pane field typed"
	)
	_eq(
		HerdrSnapshot.from_wire({"panes": [{"pane_id": "w1\u001fp9"}]}).panes[0].pane_id,
		"w1p9",
		"no control character survives into a pane id"
	)
	_eq(HerdrSnapshot.from_wire({"panes": [{"pane_id": 5}]}).panes[0].pane_id, "5", "a numeric pane id reads as text")
	_eq(
		clean.layouts[0].panes.map(_drawn_slot),
		[["5", 0, 0, 0, 0]],
		"layout slots typed, a rect that is no object read as 0x0"
	)
	_eq(clean.focused_pane_id, "", "an object focus is no focus")
	# The projection eats the cleaned snapshot without a script error.
	_eq(OfficeProjection.project(clean, office.art.state_names()).size(), 2, "both readable workspaces become floors")
	_eq(clean.workspaces[1].active_tab_id, "", "a workspace that names no open tab keeps none")
	# Beside every pane, herdr's own id as it spelled it: what the client subscribes by.
	var bell := char(7)
	var spelled := HerdrSnapshot.from_wire({"panes": [{"pane_id": " p" + bell}, 5, {"agent": "x"}]})
	_eq(spelled.wire_pane_ids, PackedStringArray([" p" + bell, ""]), "wire ids as sent, one per pane")
	_eq(spelled.panes.map(func(p: HerdrSnapshot.Pane) -> String: return p.pane_id), ["p", ""], "the panes are cleaned")
	_eq(spelled.unreadable_panes, 1, "and what was no pane object is counted")
	_eq(
		spelled.signature(),
		HerdrSnapshot.from_wire({"panes": [{"pane_id": "p"}, {"agent": "x"}]}).signature(),
		"a spelling that reads as the same id is the same snapshot to the office"
	)
	office.free()


## The three fields the office started drawing with the walls: which tab a
## workspace has open, and the checkout a linked worktree stands in. A remote
## machine may send anything there, so absent, empty and the wrong type all have
## to mean "herdr did not say", never "no".
func test_from_wire_agent_launch_source() -> void:
	var raw := {
		"panes": [{"pane_id": "p", "terminal_id": "term", "agent": "codex", "agent_status": "working"}],
		"agents": [{"pane_id": "p", "terminal_id": "term", "agent_status": "idle", "launch_pending": true}],
	}
	var clean := HerdrSnapshot.from_wire(raw)
	var panes := OfficeProjection.panes_of(clean, PackedStringArray(["working", "idle", "unknown"]))
	_check(panes[0].starting, "official agents-only launch_pending reaches the starting display")
	_eq(panes[0].state, "working", "an agent snapshot never overwrites the pane's current status")
	var cleaned := clean.panes[0]
	_eq(cleaned.launch_pending_known, true, "a matched launch flag is known")
	var agents: Array = raw.agents
	var agent: Dictionary = agents[0]
	agent.erase("launch_pending")
	clean = HerdrSnapshot.from_wire(raw)
	cleaned = clean.panes[0]
	_eq(cleaned.launch_pending, false, "skip_false omits a known false launch flag")
	_eq(cleaned.launch_pending_known, true, "matched skip_false is still known")


func test_from_wire_agent_join_rejects_ambiguity() -> void:
	var pane := {"pane_id": "p", "terminal_id": "term", "workspace_id": "w", "tab_id": "t", "agent": "codex"}
	var agent := {
		"pane_id": "p",
		"terminal_id": "term",
		"workspace_id": "w",
		"tab_id": "t",
		"agent": "codex",
		"launch_pending": true
	}
	var invalid: Array[Dictionary] = [
		{"panes": [pane]},
		{"panes": [pane], "agents": [agent, agent]},
		{"panes": [pane, pane], "agents": [agent]},
	]
	for change: Dictionary in [
		{"terminal_id": "old"},
		{"terminal_id": "te\u0007rm"},
		{"pane_id": "p\u0007"},
		{"workspace_id": "other"},
		{"tab_id": "other"},
		{"agent": "claude"},
		{"launch_pending": "true"},
		{"launch_pending": null},
	]:
		var changed := agent.duplicate()
		changed.merge(change, true)
		invalid.append({"panes": [pane], "agents": [changed]})
	for index in invalid.size():
		var normalized := HerdrSnapshot.from_wire(invalid[index]).panes[0]
		_eq(normalized.launch_pending_known, false, "invalid association %d is unknown" % index)
		_eq(normalized.launch_pending, false, "invalid association %d cannot show starting" % index)
	var invented := pane.duplicate()
	invented.launch_pending = true
	_eq(
		HerdrSnapshot.from_wire({"panes": [invented]}).panes[0].launch_pending,
		false,
		"PaneInfo cannot invent a launch flag"
	)


func test_from_wire_context_and_session_identity() -> void:
	var raw := {
		"workspaces": [{"workspace_id": "w", "label": "Workspace"}],
		"tabs": [{"tab_id": "t", "workspace_id": "missing", "label": "Orphan tab"}],
		"panes":
		[
			{
				"pane_id": "p",
				"terminal_id": "term",
				"workspace_id": "w",
				"tab_id": "t",
				"agent": "codex",
				"agent_status": "blocked",
				"label": "Review\n task",
				"cwd": "/repo",
				"foreground_cwd": "/repo/sub",
				"agent_session": {"source": "hook", "agent": "codex", "kind": "session_id", "value": "session-1"},
			}
		],
	}
	var states := PackedStringArray(["blocked", "unknown"])
	var clean := HerdrSnapshot.from_wire(raw)
	var pane := OfficeProjection.panes_of(clean, states, "machine:a")[0]
	_eq(
		[pane.workspace_id, pane.tab_id, pane.workspace_label, pane.tab_label],
		["w", "t", "Workspace", "Orphan tab"],
		"unseated panes retain their context"
	)
	_eq(
		[pane.terminal_id, pane.label, pane.cwd, pane.foreground_cwd],
		["term", "Review task", "/repo", "/repo/sub"],
		"context is typed and display text is cleaned"
	)
	_check(pane.session != null, "a valid session has typed identity")
	if pane.session == null:
		return
	_eq(
		[pane.session.provider, pane.session.kind, pane.session.value],
		["codex", "session_id", "session-1"],
		"session fields are preserved"
	)
	var identity := pane.identity_key()
	pane.session.source = "screen"
	_eq(pane.identity_key(), identity, "a detection source is provenance, not a new session")
	pane.session.value = "session-2"
	_check(pane.identity_key() != identity, "another session has another identity")
	pane.session.value = "session-1"
	pane.terminal_id = "replacement"
	_check(pane.identity_key() != identity, "a terminal replacement has another identity")
	pane.terminal_id = "term"
	pane.provider = "claude"
	_check(pane.identity_key() != identity, "provider replacement has another identity")
	_eq(OfficeProjection.project(clean, states)[0].rooms.size(), 0, "this pane really cannot be seated")
	var raw_panes: Array = raw.panes
	var raw_pane: Dictionary = raw_panes[0]
	for invalid: Variant in [
		null,
		"session",
		{"agent": "pi", "kind": "session_id", "value": "session-1"},
		{"agent": "codex", "kind": "session_id", "value": 42},
		{"agent": "codex", "kind": "session_id", "value": "s\u0007"}
	]:
		raw_pane.agent_session = invalid
		_eq(
			OfficeProjection.panes_of(HerdrSnapshot.from_wire(raw), states)[0].session,
			null,
			"malformed identity is absent"
		)


func test_from_wire_active_tab_and_worktree() -> void:
	_eq(_cleaned_space({"workspace_id": "w", "active_tab_id": "w:t2"}).active_tab_id, "w:t2", "the open tab")
	_eq(_cleaned_space({"workspace_id": "w"}).active_tab_id, "", "a workspace without the field does not gain one")
	_eq(
		_cleaned_space({"workspace_id": "w", "active_tab_id": ""}).active_tab_id,
		"",
		"an empty open tab is not an open tab"
	)
	_eq(
		_cleaned_space({"workspace_id": "w", "active_tab_id": {"id": "w:t1"}}).active_tab_id,
		"",
		"an object open tab says nothing"
	)
	# A tab id herdr sends as a number is cleaned the same way on both sides, so
	# the two still match; a long one is left as long as it came, like every id.
	_eq(_cleaned_space({"workspace_id": "w", "active_tab_id": 7}).active_tab_id, "7", "a numeric open tab")
	_eq(HerdrSnapshot.from_wire({"tabs": [{"tab_id": 7}]}).tabs[0].tab_id, "7", "and the tab it names")
	var long := "t".repeat(4096)
	_eq(_cleaned_space({"workspace_id": "w", "active_tab_id": long}).active_tab_id, long, "an over-long one")
	_eq(
		_cleaned_space({"workspace_id": "w", "active_tab_id": "a\u001fb\u0007c"}).active_tab_id,
		"abc",
		"no control character survives into an open tab id"
	)
	var linked := _cleaned_worktree(
		{"repo_name": "r", "checkout_path": "/home/t/.worktrees/lane-a", "is_linked_worktree": true}
	)
	_eq(
		[linked.repo_name, linked.checkout_path, linked.is_linked_worktree],
		["r", "/home/t/.worktrees/lane-a", true],
		"a linked worktree keeps its checkout"
	)
	# The repository both checkouts share, and where it stands: what groups a
	# linked worktree with the space it was made from. Remote text, cleaned as
	# every other text field is.
	var keyed := _cleaned_worktree(
		{"repo_key": "/home/t/r/.git", "repo_root": "/home/t/r", "checkout_path": "/home/t/r", "repo_name": "r"}
	)
	_eq([keyed.repo_key, keyed.repo_root], ["/home/t/r/.git", "/home/t/r"], "the repository key and root")
	var dirty := _cleaned_worktree({"repo_key": "/t/r\u0007/.git\u202e", "repo_root": "/t\u001f/r"})
	_eq([dirty.repo_key, dirty.repo_root], ["/t/r/.git", "/t/r"], "no control character survives into either")
	var odd_key := _cleaned_worktree({"repo_key": 7, "repo_root": ["/t/r"], "repo_name": "r"})
	_eq([odd_key.repo_key, odd_key.repo_root], ["7", ""], "a number reads as its text, a list as absent")
	_eq([linked.repo_key, linked.repo_root], ["", ""], "a worktree that names no repository has no key")
	# A worktree that is absent, null, not an object or an empty object is none;
	# any object with something in it is one, even when none of it reads.
	for none: Variant in [null, "tree", ["r"], {}]:
		_eq(
			_cleaned_space({"workspace_id": "w", "worktree": none}).worktree, null, "no worktree: %s" % var_to_str(none)
		)
	_eq(_cleaned_space({"workspace_id": "w"}).worktree, null, "and none without the field")
	var odd := _cleaned_worktree({"branch": "main"})
	_check(odd != null and odd.repo_name.is_empty() and not odd.is_linked_worktree, "an unreadable one is still one")
	_eq(
		_cleaned_worktree({"repo_name": "r", "checkout_path": ["/home/t"], "is_linked_worktree": true}).checkout_path,
		"",
		"a checkout that is not text is no checkout"
	)
	_eq(
		(
			_cleaned_worktree({"repo_name": "r", "checkout_path": "/t/la\u001fne", "is_linked_worktree": true})
			. checkout_path
		),
		"/t/lane",
		"no control character survives into a checkout path"
	)
	_eq(
		_cleaned_worktree({"repo_name": "r", "checkout_path": "/t/x", "is_linked_worktree": "true"}).is_linked_worktree,
		false,
		'the string "true" is not a linked worktree'
	)
	_eq(
		_cleaned_worktree({"repo_name": "r", "checkout_path": "/t/x"}).is_linked_worktree,
		false,
		"and neither is a worktree that does not say"
	)


# --- the typed snapshot -------------------------------------------------------


## Every fixture reads whole: each object herdr listed is there in its order, and
## the fields the office draws come through as herdr sent them.
func test_from_wire_reads_every_fixture() -> void:
	for name: String in [
		"snapshot_basic", "snapshot_floors", "snapshot_grown", "snapshot_office", "snapshot_worktrees"
	]:
		var raw := _fixture(name)
		var read := _view(raw)
		_check(not read.is_empty(), name + " is a snapshot")
		_eq(read.focused_pane_id, str(raw.focused_pane_id), name + ": herdr's focus")
		_eq(
			read.workspaces.map(func(w: HerdrSnapshot.Workspace) -> Array: return [w.workspace_id, w.label, w.number]),
			_list(raw, "workspaces").map(
				func(w: Dictionary) -> Array: return [w.workspace_id, w.label, int(_number(w, "number"))]
			),
			name + ": workspaces"
		)
		_eq(
			read.workspaces.map(func(w: HerdrSnapshot.Workspace) -> String: return w.active_tab_id),
			_list(raw, "workspaces").map(func(w: Dictionary) -> String: return str(w.get("active_tab_id", ""))),
			name + ": open tabs"
		)
		_eq(
			read.tabs.map(func(t: HerdrSnapshot.Tab) -> Array: return [t.tab_id, t.workspace_id, t.label, t.number]),
			_list(raw, "tabs").map(
				func(t: Dictionary) -> Array: return [t.tab_id, t.workspace_id, t.label, int(_number(t, "number"))]
			),
			name + ": tabs"
		)
		_eq(read.panes.map(_drawn_pane), _list(raw, "panes").map(_sent_pane), name + ": what every desk draws")
		_eq(
			read.layouts.map(func(l: HerdrSnapshot.Layout) -> Array: return [l.tab_id, l.panes.map(_drawn_slot)]),
			_list(raw, "layouts").map(
				func(l: Dictionary) -> Array: return [l.tab_id, _list(l, "panes").map(_sent_slot)]
			),
			name + ": layouts"
		)
		_eq(read.workspaces.map(_drawn_tree), _list(raw, "workspaces").map(_sent_tree), name + ": worktrees")
	# The joins the fixtures were written for.
	var office := _view_fixture("snapshot_office")
	var by_id: Dictionary[String, HerdrSnapshot.Pane] = {}
	for pane in office.panes:
		by_id[pane.pane_id] = pane
	_check(by_id["charlie:p4"].launch_pending and by_id["charlie:p4"].launch_pending_known, "p4 is launching")
	_check(not by_id["charlie:p2"].launch_pending and by_id["charlie:p2"].launch_pending_known, "p2 is not")
	_eq(by_id["charlie:p3"].agent, "", "p3 is a shell")
	_eq([by_id["charlie:p5"].agent_status, by_id["charlie:p5"].status()], ["", "unknown"], "p5 sent no status")
	_eq(by_id["charlie:p1"].agent_session.value, "fake-session-charlie-1", "p1's session is its own agent's")
	var worktrees := _view_fixture("snapshot_office").workspaces.map(
		func(w: HerdrSnapshot.Workspace) -> Variant: return null if w.worktree == null else w.worktree.repo_name
	)
	_eq(worktrees, ["echo-repo", "sample-repo", null], "a worktree where herdr sent one, none where it sent null")


## The signature holds every field the office keeps, sessions field by field,
## and nothing it does not keep.
func test_signature_is_stable_and_sensitive() -> void:
	var raw := _fixture("snapshot_office")
	var base := _view(raw).signature()
	_eq(_view(raw).signature(), base, "the same payload reads to the same signature")
	_eq(_view(raw.duplicate(true)).signature(), base, "and so does a copy of it")
	var ignored := raw.duplicate(true)
	ignored.version = "9.9.9"
	var first: Dictionary = _list(ignored, "panes")[0]
	first.revision = 99
	first.focused = true
	_eq(_view(ignored).signature(), base, "fields the office does not keep are not in it")
	_check(base != HerdrSnapshot.new().signature(), "a snapshot is not the empty one")
	var edits: Array[Callable] = [
		func(s: HerdrSnapshot) -> void: s.focused_pane_id = "echo:p1",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].workspace_id = "x",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].label = "x",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].number = 9,
		func(s: HerdrSnapshot) -> void: s.workspaces[0].active_tab_id = "echo:t9",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].worktree = null,
		func(s: HerdrSnapshot) -> void: s.workspaces[0].worktree.repo_name = "x",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].worktree.checkout_path = "/x",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].worktree.is_linked_worktree = true,
		func(s: HerdrSnapshot) -> void: s.workspaces[0].worktree.repo_key = "x",
		func(s: HerdrSnapshot) -> void: s.workspaces[0].worktree.repo_root = "/x",
		func(s: HerdrSnapshot) -> void: s.tabs[0].tab_id = "x",
		func(s: HerdrSnapshot) -> void: s.tabs[0].workspace_id = "x",
		func(s: HerdrSnapshot) -> void: s.tabs[0].label = "x",
		func(s: HerdrSnapshot) -> void: s.tabs[0].number = 9,
		func(s: HerdrSnapshot) -> void: s.panes[0].pane_id = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].terminal_id = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].tab_id = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].workspace_id = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].label = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].agent = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].agent_session = null,
		func(s: HerdrSnapshot) -> void: s.panes[0].agent_session.source = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].agent_session.provider = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].agent_session.kind = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].agent_session.value = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].launch_pending = true,
		func(s: HerdrSnapshot) -> void: s.panes[0].launch_pending_known = false,
		func(s: HerdrSnapshot) -> void: s.panes[0].cwd = "/x",
		func(s: HerdrSnapshot) -> void: s.panes[0].foreground_cwd = "/x",
		func(s: HerdrSnapshot) -> void: s.panes[0].terminal_title_stripped = "x",
		func(s: HerdrSnapshot) -> void: s.panes[0].agent_status = "blocked",
		func(s: HerdrSnapshot) -> void: s.panes[4].agent_status = "unknown",
		func(s: HerdrSnapshot) -> void: s.layouts[0].tab_id = "x",
		func(s: HerdrSnapshot) -> void: s.layouts[0].panes[0].pane_id = "x",
		func(s: HerdrSnapshot) -> void: s.layouts[0].panes[0].x = 7,
		func(s: HerdrSnapshot) -> void: s.layouts[0].panes[0].y = 7,
		func(s: HerdrSnapshot) -> void: s.layouts[0].panes[0].width = 7,
		func(s: HerdrSnapshot) -> void: s.layouts[0].panes[0].height = 7,
		func(s: HerdrSnapshot) -> void: s.panes.pop_back(),
	]
	for index in edits.size():
		var changed := _view(raw)
		edits[index].call(changed)
		_check(changed.signature() != base, "edit %d changes the signature" % index)


## The RegEx fast path drops exactly what the character loop it replaced
## dropped, for every kind of value clean_text() reads.
func test_clean_text_parity() -> void:
	var dropped := ""
	# C0, DEL, C1, the two line separators, and the
	# bidi embeddings, overrides and isolates U+202A–U+202E and U+2066–U+2069.
	var classes: Array = range(1, 0x20) + [0x7f] + range(0x80, 0xa0) + [0x2028, 0x2029]
	classes += range(0x202a, 0x202f) + range(0x2066, 0x206a)
	for code: int in classes:
		dropped += char(code)
	var values: Array = [
		"",
		"plain",
		"  padded  ",
		char(0xa0) + "kept nbsp" + char(0xa0),
		"tab\there\nand there",
		dropped,
		"a" + dropped + "b",
		" " + dropped + " edge " + dropped + " ",
		# The neighbours of every dropped range stay.
		"中文 ✓ " + char(0x2027) + char(0x202f) + char(0x2065) + char(0x206a) + char(0xa1) + " kept",
		_char(0),
		"nul" + _char(0) + "inside",
		StringName("name\u0007"),
		7,
		-3,
		7.0,
		-2.0,
		3.5,
		-0.25,
		1e20,
		true,
		false,
		null,
		["list"],
		{"a": 1},
	]
	for value: Variant in values:
		_eq(MachineRoster.clean_text(value), _loop_clean_text(value), "as the loop read %s" % var_to_str(value))
	_eq(MachineRoster.clean_text("a" + dropped + "b"), "ab", "every dropped class goes")
	_eq(
		MachineRoster.clean_text("ab\u202ecd\u2066ef\u2069gh\u202ai"),
		"abcdefghi",
		"a bidi override or isolate cannot reorder a label or id the office draws"
	)
	var neighbours := char(0x2027) + char(0x202f) + char(0x2065) + char(0x206a)
	_eq(MachineRoster.clean_text("x" + neighbours + "y"), "x" + neighbours + "y", "the code points around them stay")


## A layout slot's terminal rect size, the grid the terminal monitor draws: a
## whole number of cells from 1 to HerdrSnapshot.MAX_RECT_CELLS on each side.
## Anything else about either side makes the size unknown, 0x0, and never moves
## the rect's origin. A size never lets a snapshot past the record caps.
func test_from_wire_layout_rect_sizes() -> void:
	var cap := HerdrSnapshot.MAX_RECT_CELLS
	_eq(cap, 4096, "the bound the monitor can draw")
	_eq(_rect_read({"x": 3, "y": 4, "width": 80, "height": 24}), [3, 4, 80, 24], "a whole size reads as sent")
	_eq(_rect_read({"x": 3, "y": 4, "width": 80.0, "height": 24.0}), [3, 4, 80, 24], "a whole float reads whole")
	_eq(_rect_read({"width": 1, "height": cap}), [0, 0, 1, cap], "both bounds are in")
	for rect: Variant in [null, "80x24", [80, 24]]:
		_eq(_rect_read(rect), [0, 0, 0, 0], "no rect object: %s" % var_to_str(rect))
	var unknown: Array[Dictionary] = [
		{},
		{"width": 80},
		{"height": 24},
		{"width": 0, "height": 24},
		{"width": 80, "height": -1},
		{"width": cap + 1, "height": 24},
		{"width": 80, "height": 1e300},
		{"width": 80.5, "height": 24},
		{"width": "80", "height": 24},
		{"width": true, "height": 24},
		{"width": null, "height": 24},
		{"width": {"cells": 80}, "height": 24},
	]
	for size in unknown:
		var rect := {"x": 5, "y": 6}
		rect.merge(size)
		_eq(_rect_read(rect), [5, 6, 0, 0], "unknown size, origin kept: %s" % var_to_str(size))
	var slots: Array = []
	for index in HerdrSnapshot.MAX_LAYOUT_SLOTS + 1:
		slots.append({"pane_id": "p%d" % index, "rect": {"x": 0, "y": 0, "width": 80, "height": 24}})
	_eq(HerdrSnapshot.from_wire({"layouts": [{"tab_id": "t", "panes": slots}]}), null, "sized slots still count")


## Every record cap refuses a snapshot whole, counting whatever its list holds;
## a snapshot at the caps reads.
func test_from_wire_record_caps() -> void:
	var caps: Dictionary[String, int] = {
		"workspaces": HerdrSnapshot.MAX_WORKSPACES,
		"tabs": HerdrSnapshot.MAX_TABS,
		"layouts": HerdrSnapshot.MAX_TABS,
		"panes": HerdrSnapshot.MAX_PANES,
		"agents": HerdrSnapshot.MAX_PANES,
	}
	for key: String in caps:
		_eq(HerdrSnapshot.refusal({key: _records(caps[key])}), "", key + " at the cap is read")
		var over := {key: _records(caps[key] + 1)}
		_check(HerdrSnapshot.refusal(over).contains(str(caps[key])), key + " past the cap names it")
		_eq(HerdrSnapshot.from_wire(over), null, key + " past the cap is refused whole")
	var junk: Array = []
	junk.resize(HerdrSnapshot.MAX_PANES + 1)
	_eq(HerdrSnapshot.from_wire({"panes": junk}), null, "items that are no records still count")
	var slots := {
		"layouts":
		[
			{"tab_id": "a", "panes": _records(HerdrSnapshot.MAX_LAYOUT_SLOTS - 1)},
			{"tab_id": "b", "panes": _records(2)},
		]
	}
	_eq(HerdrSnapshot.from_wire(slots), null, "layout slots count across every layout")
	var full := HerdrSnapshot.from_wire({"panes": _records(HerdrSnapshot.MAX_PANES)})
	_check(full != null and full.panes.size() == HerdrSnapshot.MAX_PANES, "a snapshot at the cap reads whole")
	_eq(HerdrSnapshot.refusal("not a snapshot"), "", "what is no snapshot at all is empty, not refused")


## A status event changes the held pane by the rules from_wire() reads a pane
## by: the pane ends up as reading the same snapshot, so changed, would leave it.
func test_status_event_reads_like_a_snapshot() -> void:
	var pane := {
		"pane_id": "p",
		"terminal_id": "term",
		"workspace_id": "w",
		"tab_id": "t",
		"agent": "claude",
		"agent_status": "idle",
		"agent_session": {"source": "hook", "agent": "codex", "kind": "session_id", "value": "s1"},
	}
	var events: Array[Dictionary] = [
		{"agent_status": "working"},
		{"agent_status": 5},
		{"agent_status": null},
		{"agent": "codex"},
		{"agent": "codex", "agent_status": "blocked"},
		{"agent": ""},
		{"agent": null},
		{"agent": "gemini\u0007"},
		{},
	]
	for event in events:
		for record_agent: String in ["codex", "", "claude"]:
			for sends_status: bool in [true, false]:
				var raw := {
					"panes": [pane.duplicate(true)],
					"agents": [{"pane_id": "p", "terminal_id": "term", "agent": record_agent, "launch_pending": true}],
				}
				var raw_pane: Dictionary = _list(raw, "panes")[0]
				if not sends_status:
					raw_pane.erase("agent_status")
				var held := _view(raw)
				var changed := held.panes[0].apply_status(event)
				# What the client did before there was a typed snapshot: patch the
				# raw pane, then read the whole snapshot again.
				var before := _view(raw).signature()
				raw_pane.agent_status = event.get("agent_status", raw_pane.get("agent_status", "unknown"))
				if event.has("agent"):
					raw_pane.agent = event.agent
				var where := "%s, record %s, status %s" % [var_to_str(event), record_agent, sends_status]
				_eq(held.signature(), _view(raw).signature(), "reads like a snapshot: " + where)
				_eq(changed, held.signature() != before, "and says whether it changed: " + where)


# --- office -------------------------------------------------------------------


func test_office_two_machines() -> void:
	_ctl("control-a", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	var machines_json: String = args.work.path_join("machines.json")
	_write(machines_json, "[]")
	var lister: String = args.work.path_join("fake_herdr_list.sh")
	_write(lister, '#!/bin/sh\n[ "$*" = "machine list --json" ] || exit 64\ncat \'%s\'\n' % machines_json)
	OS.execute("chmod", ["+x", lister])
	OS.set_environment("HERDR_BIN_PATH", lister)
	OS.set_environment("HERDR_SOCKET_PATH", args["socket-a"])
	var office := _office(Vector2(800, 480))
	root.add_child(office)
	office.fleet._roster.sockets = _debug_socket("bee", args["socket-b"])
	office.fleet._sync_sites()
	var bee := "socket:bee"
	var local_alpha := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha")
	var bee_alpha := HerdrFleet.pane_key(bee, "alpha")
	await _until(func() -> bool: return office.fleet.size() == 2 and _all_have_panes(office, 4), "both machines live")
	office.refresh()
	var keys := _pane_keys(office)
	_eq(keys.size(), 8, "a desk per pane on both machines")
	_eq(_unique(keys).size(), 8, "colliding pane ids stay distinct desks")
	_check(
		HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1") in keys and HerdrFleet.pane_key(bee, "alpha:p1") in keys,
		"alpha:p1 on both"
	)
	_eq(
		office.navigator.active_key,
		HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1"),
		"Local's herdr focus is the default selection"
	)
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "and its machine's map is the one shown")
	_eq(
		_seats(office).map(func(seat: OfficeStation) -> String: return seat.pane_key),
		["alpha:p1", "alpha:p2", "alpha:p3", "bravo:p1"].map(
			func(id: String) -> String: return HerdrFleet.pane_key(HerdrFleet.LOCAL, id)
		),
		"only the shown machine has desks: every zone of its map"
	)
	_eq(
		office.frame.buildings.map(func(b: BuildingModel) -> String: return b.key),
		[HerdrFleet.LOCAL, bee],
		"one building per machine, Local first"
	)
	_eq(
		office.hud.spaces.row_keys(),
		[local_alpha, HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo"), bee_alpha, HerdrFleet.pane_key(bee, "bravo")],
		"the SPACES rail lists every zone, ascending, Local's section first"
	)
	_check(_floors_text(office).contains("BEE"), "a heading per building once a machine exists")
	_check(office.plate.shows_state(), "the plate names the machine once a machine exists")
	_eq(office.plate.state_text(), "LIVE", "plate says live")
	_eq(_counter(office, &"machines"), "2/2", "the bar counts both machines")
	_eq(_counter(office, &"panes"), "8", "and adds both machines' panes up")

	# The minimap reaches the other building; picking there hits the right machine.
	await _floor_pick(office, bee_alpha)
	_eq(office.navigator.shown_key, bee, "a click on bee's row shows bee's map")
	var bee_p1 := HerdrFleet.pane_key(bee, "alpha:p1")
	await _click_visible_pane(office, bee_p1)
	_eq(office.picked_key, bee_p1, "click picks the desk on the machine it sits on")
	_eq(office.navigator.active_key, office.picked_key, "and selects it")
	_eq(office.navigator.shown_key, bee, "picking a desk never changes the map")
	# The staff panel is one line until opened: Enter opens it, and its
	# details name the machine.
	await _card_key(KEY_ENTER)
	await _until(func() -> bool: return not office.hud.card_compact(), "Enter opens the panel")
	_check(_inspector_text(office).contains("@ bee"), "inspector names the machine")
	await _card_key(KEY_ESCAPE)
	await _until(office.hud.card_compact, "Escape folds it back to its line")
	# Pan the floor as far left as the office allows, so the panels sit over as
	# much of it as they ever will: a click there is the panel's, and so is one
	# over the inspector. Neither reaches the office at all. (That a desk really
	# under a panel is still not picked is test_a_click_over_a_panel_picks_nothing,
	# in the incremental suite, where the window can be narrowed to allow it.)
	var under := _desk_target(office, HerdrFleet.pane_key(bee, "alpha:p2")).get_center()
	office.camera.pan = Vector2(under.x - 40, 0)
	# _process clamps the pan to what the floor is wider than the world area by,
	# so the settled value is the one to hold the click to.
	await process_frame
	await process_frame
	var pan_at_panel: Vector2 = office.camera.pan
	_press(Vector2(40, under.y), MOUSE_BUTTON_LEFT)
	await process_frame
	_eq(office.picked_key, bee_p1, "a click over the minimap picks no desk")
	_eq(office.camera.pan, pan_at_panel, "and starts no pan")
	_check(not office.camera.dragging, "the office never saw the press")
	# On the one-line panel, its line's words: its buttons (`‹ ›`, Open, NEXT) are its own clicks.
	var line: Control = office.hud.inspector.get_node("%CompactLine")
	var inspector_at: Vector2 = line.get_global_rect().get_center()
	_press(inspector_at, MOUSE_BUTTON_LEFT)
	_press(inspector_at, MOUSE_BUTTON_WHEEL_DOWN)
	# A drag that starts over the world keeps the release, wherever it lands: the
	# press found no control, so the panels never take the button away from it.
	var world_at: Vector2 = office.hud.world_rect().get_center()
	_button(world_at, MOUSE_BUTTON_LEFT, true)
	_check(office.camera.dragging, "a press over the world starts a drag")
	_button(inspector_at, MOUSE_BUTTON_LEFT, false)
	_check(not office.camera.dragging, "and its release over a panel still ends it")
	await process_frame
	_eq(office.picked_key, bee_p1, "a click over the inspector picks no desk either")
	_eq(office.camera.pan, pan_at_panel, "and the wheel over it does not pan")
	office.camera.pan = Vector2.ZERO
	# Through the viewport's own GUI routing: a click on a row reaches the panel,
	# and neither it nor the wheel over the panel ever reaches the world.
	var pan_before: Vector2 = office.camera.pan
	_press(_row_position(office, local_alpha), MOUSE_BUTTON_WHEEL_DOWN)
	_eq(office.camera.pan, pan_before, "the wheel over the panel does not pan the office")
	_press(_row_position(office, local_alpha), MOUSE_BUTTON_LEFT)
	await process_frame
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "a real click on a row shows that zone's map")
	_eq(office.picked_key, bee_p1, "and picks no desk under the panel")
	var local_p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1")
	await _click_visible_pane(office, local_p1)
	_eq(office.picked_key, local_p1, "the same pane id on Local is its own desk")
	await _card_key(KEY_ENTER)
	await _until(func() -> bool: return not office.hud.card_compact(), "Enter opens Local's panel")
	_check(_inspector_text(office).contains("@ Local"), "inspector names Local")
	await _card_key(KEY_ESCAPE)
	await _until(office.hud.card_compact, "Escape folds it again")
	await _floor_pick(office, bee_alpha)
	await _click_visible_pane(office, bee_p1)
	_eq(office.picked_key, bee_p1, "bee is selected before its status and liveness change")

	# A status change reaches only its own machine's desk and floor, live.
	_ctl("control-b", "status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	await _until(func() -> bool: return _badge_state(bee, "alpha:p1") == "blocked", "status reaches bee's desk")
	_eq(
		_pane_state(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1")),
		"working",
		"Local's alpha:p1 keeps its own state"
	)
	_eq(office.frame.find_zone(bee_alpha).zone_model.blocked, 1, "bee's zone counts it")
	_check(_floor_badges(office).has([bee, "blocked"]), "and its minimap row shows it")
	_check(
		not office.attention.machine_stale(HerdrFleet.LOCAL) and not office.attention.machine_stale(bee),
		"attention knows each machine is live"
	)

	# One machine drops: its floor dims and freezes in place, the world is not rebuilt.
	var shown_world: Node2D = office.world
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(bee), "bee offline")
	var tint: Color = office.art.stale_tint
	_check(office.world == shown_world, "a dropped machine relabels, never rebuilds the world")
	_eq(office.floor_view.root.modulate, tint, "bee's rooms dim")
	_eq(_actors_playing(office), [false], "bee's workers freeze")
	_check(_plate_text(office, "state").begins_with("OFFLINE"), "bee's plate says offline")
	_eq(office.frame.find_zone(bee_alpha).zone_model.blocked, 0, "a dropped machine's zones report nobody waiting")
	_check(not _floor_badges(office).has([bee, "blocked"]), "and its minimap rows lose their icons")
	_check(
		_bar_text(office).begins_with("1 OFFLINE / READ ONLY"), "bar counts the dropped machine: " + _bar_text(office)
	)
	_check(office.hud.bar.alarmed(), "and turns that line to the blocked colour")
	_eq(_counter(office, &"machines"), "1/2", "MACHINES counts the dropped one out")
	_check(_inspector_text(office).contains("STALE / OFFLINE"), "the selected bee pane reads stale")
	_check(
		office.attention.machine_stale(bee) and not office.attention.machine_stale(HerdrFleet.LOCAL),
		"attention freezes only bee's badges"
	)
	# The rail is ascending: PageDown walks it down to bee's bravo (the same map,
	# a pan), PageUp back up past bee's first zone into Local's last, across
	# machines (bee's map is left dimmed and frozen).
	await _navigate_key(office, KEY_PAGEDOWN)
	_eq(office.navigator.shown_key, bee, "PageDown from bee's first zone pans to bee's next one")
	_eq(office.floor_view.root.modulate, tint, "on bee's map, still dim")
	await _navigate_key(office, KEY_PAGEUP)
	await _navigate_key(office, KEY_PAGEUP)
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "PageUp from bee's first zone reaches Local's last")
	_eq(office.floor_view.root.modulate, Color.WHITE, "Local's rooms do not dim")
	_eq(_actors_playing(office), [true], "Local's workers carry on")
	_eq(office.plate.state_text(), "LIVE", "Local's plate stays live")
	await _navigate_key(office, KEY_PAGEDOWN)
	_eq(office.navigator.shown_key, bee, "PageDown goes back onto bee's map")
	_eq(office.floor_view.root.modulate, tint, "a stale map is dim as soon as it is built")
	_ctl("control-b", "next", {"action": "hang", "method": "session.snapshot"})
	_ctl("control-b", "appear")
	# Online but not yet current is the state under test, and only the client tells it.
	await _until(func() -> bool: return _client(office, 1).online, "bee reconnects by itself")
	_check(not office.fleet.snapshot_is_current(bee), "subscription recovery does not make the cached snapshot live")
	_eq(office.fleet.live_count(), 1, "only Local counts as live while bee awaits its complete snapshot")
	_eq(_actors_playing(office), [false], "same-state workers stay frozen before a new snapshot")
	await _until(
		func() -> bool: return office.fleet.snapshot_is_current(bee), "bee obtains a complete current snapshot"
	)
	_eq(office.floor_view.root.modulate, Color.WHITE, "bee lights up again")
	_eq(office.plate.state_text(), "LIVE", "plate live again")
	_eq(_actors_playing(office), [true], "readiness liveness signal resumes even the same-state workers")

	# A machine answering nonsense cannot take the office down with it; its map
	# stays shown (the machine is still there), its zones now what it sent.
	_ctl("control-b", "set_snapshot", {"snapshot": _malformed()})
	_client(office, 1)._want_snapshot = true
	await _until(func() -> bool: return office.fleet.snapshot(bee).panes.size() == 2, "bee sends nonsense")
	office.refresh()
	var odd := _pane_keys(office)
	_eq(
		odd.filter(func(k: String) -> bool: return k.begins_with(HerdrFleet.LOCAL)).size(),
		4,
		"Local still projects all its desks"
	)
	_check(HerdrFleet.pane_key(bee, "w1:p9") in odd, "bee's readable pane still gets a desk")
	_eq(_counter(office, &"panes"), "6", "counts include what could be read")
	_eq(office.navigator.picked_machine, bee, "the machine is still there, so the viewer's pick of it stays")
	_eq(office.navigator.shown_key, bee, "and its map is still the one shown")
	_eq(office.navigator.current_zone(office.frame), "", "while no zone of it is current: alpha went away")
	_ctl("control-b", "set_snapshot", {"fixture": "snapshot_basic"})
	_client(office, 1)._want_snapshot = true
	await _until(func() -> bool: return office.fleet.snapshot(bee).panes.size() == 4, "bee back to normal")
	office.refresh()
	await _floor_pick(office, bee_alpha)
	await _click_visible_pane(office, bee_p1)
	_eq(office.picked_key, bee_p1, "bee is selected again after its snapshot returns")

	# Theme switch rebuilds the floor; resize retains its layout. Neither restarts a client.
	var clients := _clients(office)
	var picked: String = office.picked_key
	var other: String = _second_pack() if office.manifest_path == MANIFESTS[0] else MANIFESTS[0]
	var old_world: Node2D = office.world
	var old_rows: Array = office.hud.spaces.row_keys()
	office.switch_theme(other)
	_check(office.world != old_world, "theme switch rebuilds the world")
	_eq(_clients(office), clients, "same clients after the switch")
	_eq(office.fleet.live_count(), office.fleet.size(), "still online after the switch")
	_eq(office.picked_key, picked, "selection survives the switch")
	_eq(office.navigator.shown_key, bee, "and so does the shown map")
	_eq(office.hud.spaces.row_keys(), old_rows, "the minimap is redrawn with the same zones")
	office.test_screen = Vector2(1600, 960)
	office.refresh()
	_eq(
		_unique(_seats(office).map(func(seat: OfficeStation) -> String: return seat.pane_key)).size(),
		4,
		"resize keeps every desk of the map (bee's alpha and bravo zones: 3 + 1)"
	)
	_eq(office.navigator.active_key, picked, "resize keeps the selection")

	# Saved machines come and go through `herdr machine list --json`.
	_write(
		machines_json,
		JSON.stringify([{"profile_id": "p9", "label": "far", "ssh_target": "-oProxyCommand=x", "enabled": true}])
	)
	office.fleet._roster._left = 0.0
	await _until(func() -> bool: return office.fleet.size() == 3, "a saved machine appears")
	_eq(office.fleet.keys()[2], "machine:p9", "keyed by profile id")
	var far_client := _client(office, 2)
	var far_link := _site_link_of(office, 2)
	_check(
		not office.fleet.link_error("machine:p9").is_empty() and far_client.socket_path.is_empty(),
		"a bad target never gets a client or an ssh"
	)
	office.refresh()
	_eq(office.frame.buildings[2].zones.size(), 0, "a machine that never connected has no zone")
	_eq(office.frame.map_of("machine:p9").zones.size(), 0, "its map is empty")
	# A machine without zones has no row: a real click on its heading shows its map.
	await _heading_pick(office, "machine:p9")
	_eq(office.navigator.shown_key, "machine:p9", "the empty map can be shown")
	_check(_plate_text(office, "state").contains("must not start with '-'"), "its plate says why")
	_check(_plate_text(office, "note").contains("must not start with '-'"), "and so does its note, in full")
	_write(
		machines_json,
		JSON.stringify([{"profile_id": "p9", "label": "renamed", "ssh_target": "-oProxyCommand=x", "enabled": true}])
	)
	office.fleet._roster._left = 0.0
	await _until(func() -> bool: return office.fleet.label("machine:p9") == "renamed", "a rename arrives")
	_check(_client(office, 2) == far_client and _site_link_of(office, 2) == far_link, "a rename keeps the connection")
	office.refresh()
	_check(_floor_plate_text(office).contains("@ RENAMED"), "and relabels the plate")
	_check(_floors_text(office).contains("RENAMED"), "and the minimap heading")
	_write(
		machines_json,
		JSON.stringify([{"profile_id": "p9", "label": "far", "ssh_target": "-oProxyCommand=x", "enabled": false}])
	)
	office.fleet._roster._left = 0.0
	await _until(func() -> bool: return office.fleet.size() == 2, "a disabled machine goes")
	_eq(office.navigator.shown_key, bee, "its map goes with it, back to the selection's machine")
	_write(machines_json, "not json")
	office.fleet._roster._left = 0.0
	await _until(func() -> bool: return office.fleet._roster._failing, "a broken list is noticed")
	_eq(office.fleet.size(), 2, "a broken list changes nothing")
	# herdr itself disappears: tolerated twice, then the list is dropped.
	_write(machines_json, JSON.stringify([{"profile_id": "p9", "label": "far", "ssh_target": "x@y", "enabled": false}]))
	office.fleet._roster._left = 0.0
	await _until(func() -> bool: return office.fleet._roster.machines.size() == 1, "list back")
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-such-herdr"))
	for attempt in MachineRoster.MISSING_LIMIT:
		_eq(office.fleet._roster.machines.size(), 1, "kept after %d missing polls" % attempt)
		var before: int = office.fleet._roster.attempts
		office.fleet._roster._left = 0.0
		await _until(func() -> bool: return office.fleet._roster.attempts > before, "missing poll")
	_check(office.fleet._roster.machines.is_empty(), "dropped once herdr stayed gone")
	OS.set_environment("HERDR_BIN_PATH", lister)

	# Removing the last machine brings back the single-machine office.
	office.fleet._roster.sockets = MachineRoster.parse_socket_args(PackedStringArray())
	office.fleet._sync_sites()
	# The fleet's change is drawn by the one refresh at the end of the frame.
	await process_frame
	_eq(office.fleet.size(), 1, "only Local left")
	_eq(office.picked_key, picked, "the pick is remembered")
	_eq(
		office.navigator.active_key,
		HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1"),
		"but its desk is gone, so herdr focus wins"
	)
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "and brings its map")
	_check(not office.plate.shows_state(), "no machine on the plate with Local alone")
	_check(not _floors_text(office).contains("LOCAL"), "no building heading with Local alone")
	_check(_bar_text(office).begins_with("LIVE / READ ONLY"), "Local alone is live: " + _bar_text(office))
	_eq(_counter(office, &"machines"), "1/1", "one machine, answering")
	_check(not office.hud.bar.alarmed(), "and nothing is down")
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")


## Keys and `--space=` on a real office: Local serves many zones, bee two.
func test_office_floor_keys() -> void:
	_ctl("control-a", "reset", {"fixture": "snapshot_floors"})
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-such-herdr"))
	OS.set_environment("HERDR_SOCKET_PATH", args["socket-a"])
	var office := _office(Vector2(800, 480))
	root.add_child(office)
	office.navigator.wanted_space = 3
	office.fleet._roster.sockets = _debug_socket("bee", args["socket-b"])
	office.fleet._sync_sites()
	var bee := "socket:bee"
	var local := func(id: String) -> String: return HerdrFleet.pane_key(HerdrFleet.LOCAL, id)
	await _until(
		func() -> bool:
			return (
				office.fleet.size() == 2
				and office.fleet.all_loaded()
				and office.fleet.live_count() == office.fleet.size()
			),
		"both machines live"
	)
	office.refresh()
	_eq(
		[office.navigator.shown_key, office.navigator.current_zone(office.frame)],
		[HerdrFleet.LOCAL, local.call("infra")],
		"--space=3 picks Local's third zone once it exists"
	)
	_eq(office.navigator.wanted_space, -1, "and only once")
	_eq(office.navigator.active_key, local.call("api:p1"), "herdr focus stays the selection in another zone")
	var world: Node2D = office.world
	office.refresh()
	_check(office.world == world, "an unchanged refresh rebuilds nothing")

	var order := func(presses: int, keycode: Key) -> Array:
		var seen: Array = []
		for press in presses:
			await _navigate_key(office, keycode)
			seen.append([office.navigator.shown_key, office.navigator.current_zone(office.frame)])
		return seen
	var at_local := func(id: String) -> Array: return [HerdrFleet.LOCAL, local.call(id)]
	var at_bee := func(id: String) -> Array: return [bee, HerdrFleet.pane_key(bee, id)]
	# The rail is ascending (PLAN_R2 §7): PageDown goes to the higher number.
	_eq(
		await order.call(5, KEY_PAGEDOWN),
		[
			at_local.call("notes"),
			at_local.call("data"),
			at_bee.call("alpha"),
			at_bee.call("bravo"),
			at_bee.call("bravo")
		],
		"PageDown walks down the rail, into bee's map after Local's last zone, and stops at the bottom"
	)
	_eq(
		await order.call(7, KEY_PAGEUP),
		[
			at_bee.call("alpha"),
			at_local.call("data"),
			at_local.call("notes"),
			at_local.call("infra"),
			at_local.call("web"),
			at_local.call("api"),
			at_local.call("api"),
		],
		"PageUp walks back up, across machines, and stops at the top"
	)

	# Two blocked agents with known waits (infra:p1 the longer), bee's of unknown start.
	for pane_id: String in ["infra:p1", "web:p1"]:
		_ctl("control-a", "status", {"pane_id": pane_id, "agent_status": "working"})
		await _until(
			func() -> bool: return _held_status(office, HerdrFleet.LOCAL, pane_id) == "working", pane_id + " working"
		)
		_ctl("control-a", "status", {"pane_id": pane_id, "agent_status": "blocked"})
		await _until(
			func() -> bool: return _held_status(office, HerdrFleet.LOCAL, pane_id) == "blocked",
			pane_id + " blocked again"
		)
		await _until(
			func() -> bool: return office.fleet.state_since(HerdrFleet.LOCAL, pane_id) > 0.0, pane_id + " start known"
		)
	var jumps: Array = []
	for press in 6:
		await _navigate_key(office, KEY_N)
		jumps.append([office.picked_key, office.navigator.shown_key])
		var target := _desk_rect(office, office.picked_key)
		var visible := Rect2(office.camera.pan, office.hud.world_rect().size)
		_check(visible.encloses(target), "N pans the desk into view: %s in %s" % [target, visible])
	# While anyone is blocked, N walks the blocked only (not the UNREAD web:p2
	# and infra:p2 after web:p1), and round again.
	_eq(
		jumps,
		# An unknown start is the longest wait, first, as a floor's
		# queue stands (docs/VISUAL_LANGUAGE.md, "State start").
		[
			[HerdrFleet.pane_key(bee, "bravo:p1"), bee],
			[local.call("infra:p1"), HerdrFleet.LOCAL],
			[local.call("web:p1"), HerdrFleet.LOCAL],
			[HerdrFleet.pane_key(bee, "bravo:p1"), bee],
			[local.call("infra:p1"), HerdrFleet.LOCAL],
			[local.call("web:p1"), HerdrFleet.LOCAL],
		],
		"N: blocked by longest wait, unknown first, then around again among the blocked"
	)
	# Once nobody is blocked, N goes to the UNREAD, and scrolls down to one.
	for pane_id: String in ["infra:p1", "web:p1"]:
		_ctl("control-a", "status", {"pane_id": pane_id, "agent_status": "working"})
	_ctl("control-b", "status", {"pane_id": "bravo:p1", "agent_status": "working"})
	await _until(
		func() -> bool: return office.navigator.peek_next(office.frame) == local.call("web:p2"), "nobody blocked"
	)
	var unread: Array = []
	for press in 2:
		await _navigate_key(office, KEY_N)
		unread.append([office.picked_key, office.navigator.shown_key])
		var target := _desk_rect(office, office.picked_key)
		var visible := Rect2(office.camera.pan, office.hud.world_rect().size)
		_check(visible.encloses(target), "N pans the desk into view: %s in %s" % [target, visible])
		if press == 1:
			_check(office.camera.pan.y > 0.0, "infra:p2 sits in the second row, so N scrolled down to it")
	_eq(
		unread,
		[[local.call("web:p2"), HerdrFleet.LOCAL], [local.call("infra:p2"), HerdrFleet.LOCAL]],
		"N: nobody blocked, the UNREAD in the same order"
	)
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")


## Saved SSH machines through the office, with fake_ssh as ssh: the client waits
## for its forward, and every way a live machine goes away kills its ssh and
## removes its socket and sidecar.
func test_office_ssh_machines() -> void:
	_ctl("control-a", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	OS.set_environment("FAKE_SSH_HOME", args.work.path_join("h%1"))
	var machines_json: String = args.work.path_join("machines.json")
	var lister: String = args.work.path_join("fake_herdr_list.sh")
	_write(machines_json, "[]")
	OS.set_environment("HERDR_BIN_PATH", lister)
	OS.set_environment("HERDR_SOCKET_PATH", args["socket-a"])
	OS.set_environment("FAKE_SSH_FAIL", "Permission denied (publickey).")
	var office := _office(Vector2(800, 480))
	root.add_child(office)
	var set_machines := func(machines: Array) -> void:
		_write(machines_json, JSON.stringify(machines))
		office.fleet._roster._left = 0.0
	set_machines.call([{"profile_id": "s1", "label": "far", "ssh_target": "me@far"}])
	await _until(func() -> bool: return office.fleet.size() == 2, "ssh machine listed")
	var far := "machine:s1"
	var far_client := _client(office, 1)
	var far_link := _site_link_of(office, 1)
	_check(far_client.socket_path.is_empty(), "no client before its forward exists")
	await _until(func() -> bool: return office.fleet.link_state(far) == MachineLink.State.WAITING, "ssh refused")
	office.refresh()
	# An empty map has no row to click: a real click on its heading shows it.
	await _heading_pick(office, far)
	_check(_plate_text(office, "state").contains("Permission denied"), "its empty map's plate shows ssh's reason")
	_check(_plate_text(office, "note").contains("Permission denied"), "and so does its note")
	_check(far_client.socket_path.is_empty(), "still no client while ssh fails")
	OS.unset_environment("FAKE_SSH_FAIL")
	far_link._left = 0.0
	await _until(func() -> bool: return _has_panes(office, far, 4), "far live through its forward")
	_eq(office.fleet.link_error(far), "", "a client got through, so the old complaint is gone")
	office.refresh()
	await _floor_pick(office, HerdrFleet.pane_key(far, "alpha"))
	_eq(office.plate.state_text(), "LIVE", "plate live on its map")

	var gone := func(link: MachineLink) -> Array: return [link.ssh_pid(), link.local_socket, link._sidecar_path()]
	var check_gone := func(what: Array, how: String) -> void:
		var pid: int = what[0]
		var socket: String = what[1]
		var sidecar_path: String = what[2]
		_check(not _alive(pid), how + ": ssh killed")
		_check(not _socket_exists(socket), how + ": socket removed")
		_check(not FileAccess.file_exists(sidecar_path), how + ": sidecar removed")
	var before: Array = gone.call(far_link)
	set_machines.call([{"profile_id": "s1", "label": "far", "ssh_target": "me@other"}])
	await _until(
		func() -> bool: return office.fleet.size() == 2 and _site_link_of(office, 1) != far_link,
		"target change applied"
	)
	check_gone.call(before, "target change")
	await _until(func() -> bool: return not office.fleet.is_stale(far), "new target live")
	before = gone.call(_site_link_of(office, 1))
	set_machines.call([{"profile_id": "s1", "label": "far", "ssh_target": "me@other", "enabled": false}])
	await _until(func() -> bool: return office.fleet.size() == 1, "disabled")
	check_gone.call(before, "disable")
	set_machines.call([{"profile_id": "s1", "label": "far", "ssh_target": "me@other"}])
	await _until(func() -> bool: return office.fleet.size() == 2 and not office.fleet.is_stale(far), "enabled again")
	before = gone.call(_site_link_of(office, 1))
	set_machines.call([])
	await _until(func() -> bool: return office.fleet.size() == 1, "removed")
	check_gone.call(before, "removal")
	set_machines.call([{"profile_id": "s1", "label": "far", "ssh_target": "me@other"}])
	await _until(
		func() -> bool: return office.fleet.size() == 2 and not office.fleet.is_stale(far), "back for the exit check"
	)
	before = gone.call(_site_link_of(office, 1))
	root.remove_child(office)
	office.free()
	check_gone.call(before, "office exit")
	OS.unset_environment("HERDR_BIN_PATH")


## A snapshot over the record caps is not herdr's picture of the machine: the
## office keeps the last one it read on screen, dimmed and frozen, and counts
## nobody on it as live (invariant 4), until a readable one comes.
func test_refused_snapshot_leaves_the_machine_stale() -> void:
	var office: OfficeDouble = await _two_machine_office()
	var bee := "socket:bee"
	_ctl("control-b", "set_snapshot", {"snapshot": _over_cap()})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.fleet.is_stale(bee), "a refused snapshot leaves bee stale")
	_eq(office.fleet.live_count(), 1, "only Local counts as live")
	_eq(office.fleet.snapshot(bee).panes.size(), 4, "bee keeps the last snapshot it read, for its frozen floor")
	_check(_bar_text(office).begins_with("1 OFFLINE / READ ONLY"), "the bar counts bee out: " + _bar_text(office))
	_check(office.attention.machine_stale(bee), "and attention freezes bee's badges")
	_eq(_ctl("control-b", "stats").get("streams_live"), 1, "while bee's stream itself stays up")
	_ctl("control-b", "set_snapshot", {"fixture": "snapshot_basic"})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.fleet.snapshot_is_current(bee), "a readable snapshot makes bee current")
	_eq(office.fleet.live_count(), 2, "and live again")
	_check(_bar_text(office).begins_with("LIVE / READ ONLY"), "the bar counts bee in: " + _bar_text(office))
	_check(not office.attention.machine_stale(bee), "and attention lets bee's badges move again")
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")


## The worst order: a new pane set makes the client subscribe again, herdr has
## dropped those panes by then (pane_not_found), and the snapshot fetched to
## recover is refused. No stream is left and only the backstop still asks; bee
## reads as stale until a readable snapshot lets it subscribe again.
func test_refusal_after_pane_not_found_reopens_the_stream() -> void:
	var office: OfficeDouble = await _two_machine_office()
	var bee := "socket:bee"
	# The next fetch answers with a new pane set. Everything after it, the
	# subscription that pane set asks for included, meets the refused snapshot.
	var grown := {"id": "$ID", "result": {"type": "session_snapshot", "snapshot": _fixture("snapshot_grown")}}
	_ctl("control-b", "next", {"action": "reply", "method": "session.snapshot", "line": JSON.stringify(grown)})
	_ctl("control-b", "set_snapshot", {"snapshot": _over_cap()})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.fleet.is_stale(bee), "the recovery snapshot is refused and bee is stale")
	var stats := _ctl("control-b", "stats")
	var errors := _list(stats, "stream_errors")
	_check(
		errors.any(func(error: Variant) -> bool: return str(error).begins_with("pane_not_found")),
		"the new pane set met pane_not_found: %s" % [errors]
	)
	_eq(stats.get("streams_live"), 0, "which left bee without a stream")
	_eq(office.fleet.snapshot(bee).panes.size(), 5, "bee keeps the pane set it read last")
	_eq(office.fleet.live_count(), 1, "only Local counts as live")
	_ctl("control-b", "set_snapshot", {"fixture": "snapshot_basic"})
	# Nothing but the backstop asks again, SNAPSHOT_INTERVAL after the refused fetch.
	await _until(
		func() -> bool: return office.fleet.snapshot_is_current(bee), "a readable snapshot makes bee current again"
	)
	var basic_ids: Array = _list(_fixture("snapshot_basic"), "panes").map(
		func(pane: Dictionary) -> String: return str(pane.pane_id)
	)
	basic_ids.sort()
	stats = await _until_stats(
		"control-b", func(s: Dictionary) -> bool: return s.get("streams_live") == 1, "bee subscribes again"
	)
	_eq(stats.get("stream_panes"), [basic_ids], "to the panes it has now")
	_eq(office.fleet.live_count(), 2, "and is live again")
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")


func test_attention_socket_target_replacement_retires_suppressed_records() -> void:
	var snapshot := _attention_identity_fixture()
	_ctl("control-a", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-a", "set_snapshot", {"snapshot": snapshot})
	_ctl("control-b", "set_snapshot", {"snapshot": snapshot})
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr-attention"))
	OS.set_environment("HERDR_SOCKET_PATH", args["socket-a"])
	var office := _office(Vector2(800, 480))
	root.add_child(office)
	var machine := "socket:changing"
	office.fleet._roster.sockets = _debug_socket("changing", args["socket-b"])
	office.fleet._sync_sites()
	await _until(func() -> bool: return office.fleet.snapshot_is_current(machine), "original socket is current")
	var old := _machine_attention(office, machine)
	_eq(old.size(), 2, "two unknown-identity panes await attention")
	if old.size() == 2:
		office.attention_store.set_hidden(old[0].id, true)
		office.attention_store.snooze(old[1].id, 300.0, Time.get_ticks_msec())
		office.fleet._roster.sockets = _debug_socket("changing", args["socket-a"])
		office.fleet._sync_sites()
		await _until(func() -> bool: return office.fleet.snapshot_is_current(machine), "replacement socket is current")
		var replacement := _machine_attention(office, machine)
		_eq(replacement.size(), 2, "same pane IDs on another socket do not inherit hidden or snoozed state")
		for item in old:
			_check(item.retired and not item.available and not item.active, "former endpoint history stays unavailable")
		for item in replacement:
			_check(item.id != old[0].id and item.id != old[1].id, "replacement socket gets new episode IDs")
			_check(
				item.baseline and not item.hidden and not item.is_snoozed(Time.get_ticks_msec()),
				"replacement is a clean baseline"
			)
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")


func test_attention_roster_replacement_excludes_rename_and_reconnect() -> void:
	var snapshot := _attention_identity_fixture()
	_ctl("control-a", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	_ctl("control-b", "set_snapshot", {"snapshot": snapshot})
	var fake_home := args.work.path_join("attention-home")
	var default_socket := MachineLink.remote_socket_path(fake_home, "")
	var session_socket := MachineLink.remote_socket_path(fake_home, "next")
	DirAccess.make_dir_recursive_absolute(default_socket.get_base_dir())
	DirAccess.make_dir_recursive_absolute(session_socket.get_base_dir())
	OS.execute("ln", ["-s", args["socket-b"], default_socket])
	OS.execute("ln", ["-s", args["socket-b"], session_socket])
	OS.set_environment("FAKE_SSH_HOME", fake_home)
	var machines_json := args.work.path_join("attention-machines.json")
	var lister := args.work.path_join("attention-list.sh")
	_write(lister, '#!/bin/sh\n[ "$*" = "machine list --json" ] || exit 64\ncat \'%s\'\n' % machines_json)
	OS.execute("chmod", ["+x", lister])
	_write(machines_json, JSON.stringify([_attention_machine("Original", "me@one")]))
	OS.set_environment("HERDR_BIN_PATH", lister)
	OS.set_environment("HERDR_SOCKET_PATH", args["socket-a"])
	var office := _office(Vector2(800, 480))
	root.add_child(office)
	var replaced_keys: Array[String] = []
	office.fleet.machine_replaced.connect(func(key: String) -> void: replaced_keys.append(key))
	var machine := "machine:attention"
	await _until(func() -> bool: return office.fleet.snapshot_is_current(machine), "saved machine is current")
	var old := _machine_attention(office, machine)
	_eq(old.size(), 2, "saved machine has two blockers with unknown identity")
	if old.size() == 2:
		office.attention_store.set_hidden(old[0].id, true)
		office.attention_store.snooze(old[1].id, 300.0, Time.get_ticks_msec())
		var deadline := old[1].snoozed_until_msec
		_write(machines_json, JSON.stringify([_attention_machine("Renamed", "me@one")]))
		office.fleet._roster._left = 0.0
		await _until(func() -> bool: return office.fleet.label(machine) == "Renamed", "label rename arrives")
		_check(not old[0].retired and old[0].hidden, "label rename retains hidden episode")
		_eq(old[1].snoozed_until_msec, deadline, "label rename retains snooze deadline")
		_ctl("control-b", "vanish")
		await _until(func() -> bool: return office.fleet.is_stale(machine), "ordinary connection lost")
		_ctl("control-b", "appear")
		await _until(func() -> bool: return office.fleet.snapshot_is_current(machine), "same endpoint reconnects")
		_check(old[0].retired and not old[0].available and old[0].hidden, "unverified hidden identity remains history")
		_check(old[1].retired and not old[1].available, "unverified snoozed identity remains history")
		_eq(old[1].snoozed_until_msec, deadline, "retired history keeps its own snooze deadline")
		_eq(replaced_keys, [], "rename and ordinary reconnect emit no replacement")
		var reconnected := _machine_attention(office, machine)
		_eq(reconnected.size(), 2, "unverifiable reconnect creates unsuppressed baselines")
		for item in reconnected:
			_check(item.id != old[0].id and item.id != old[1].id, "reconnect cannot reuse unknown episode identities")
			_check(item.baseline and item.observed_at == -1.0 and item.since_msec == -1, "gap yields no new event time")
		if reconnected.size() == 2:
			office.attention_store.set_hidden(reconnected[0].id, true)
			office.attention_store.snooze(reconnected[1].id, 300.0, Time.get_ticks_msec())
		_write(machines_json, JSON.stringify([_attention_machine("Renamed", "me@two")]))
		office.fleet._roster._left = 0.0
		await _until(func() -> bool: return replaced_keys.size() == 1, "target replacement begins")
		await _until(func() -> bool: return office.fleet.snapshot_is_current(machine), "new SSH target is current")
		var replacement := _machine_attention(office, machine)
		_eq(replaced_keys, [machine], "target change emits one replacement for the existing machine key")
		_eq(replacement.size(), 2, "another SSH target does not inherit local suppression")
		for item in reconnected:
			_check(item.retired and not item.available, "old SSH target can never be located through replacement")
		if replacement.size() == 2:
			office.attention_store.set_hidden(replacement[0].id, true)
			_write(machines_json, JSON.stringify([_attention_machine("Renamed", "me@two", "next")]))
			office.fleet._roster._left = 0.0
			await _until(
				func() -> bool: return replacement[0].retired or office.fleet.is_stale(machine),
				"session replacement begins"
			)
			await _until(func() -> bool: return office.fleet.snapshot_is_current(machine), "new session is current")
			_eq(_machine_attention(office, machine).size(), 2, "another Herdr session gets unsuppressed baselines")
			_eq(replaced_keys, [machine, machine], "session change emits one more replacement")
			for item in replacement:
				_check(item.retired and not item.available, "old session history remains unavailable")
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")
	OS.unset_environment("FAKE_SSH_HOME")


## Each machine is one map with its own plan, world and pan (as each floor was):
## Local (40 agents, a pod of 20 columns, three lanes) and bee (snapshot_basic,
## one lane) plan apart. A real click on the other machine's FLOORS row is a
## cold switch: a new world, nobody walking. Back on Local, its same FloorPlan
## object. Each map remembers where a real drag left it.
func test_each_machine_keeps_its_own_map_world_and_pan() -> void:
	var office: OfficeDouble = await _two_machine_office()
	_ctl("control-a", "set_snapshot", {"snapshot": _one_tab_of(40)})
	_client(office, 0)._want_snapshot = true
	await _until(func() -> bool: return office.fleet.snapshot(HerdrFleet.LOCAL).panes.size() == 40, "Local's 40")
	office.refresh()
	var bee := "socket:bee"
	var plan_a: FloorPlan = office.layout_plan()
	_eq([office.navigator.shown_key, plan_a.floor_key], [HerdrFleet.LOCAL, HerdrFleet.LOCAL], "Local's map")
	_eq(plan_a.lanes, 3, "widened to three lanes for its pod")
	await process_frame
	var middle := office.hud.world_rect().get_center()
	await _drag_world(middle, Vector2(-120, -40))
	var pan_a: Vector2 = office.camera.pan
	_check(pan_a != Vector2.ZERO, "a real drag pans Local's map: %s" % pan_a)
	var attempts: int = office.layout_attempt_count()
	var world: Node2D = office.world
	await _floor_pick(office, HerdrFleet.pane_key(bee, "alpha"))
	var plan_b: FloorPlan = office.layout_plan()
	_eq([office.navigator.shown_key, plan_b.floor_key], [bee, bee], "a click on bee's row shows bee's map")
	_check(plan_b.floor_cells.size != plan_a.floor_cells.size, "planned apart, at its own size")
	_eq(office.layout_attempt_count(), attempts + 1, "once")
	_check(office.world != world, "a cold switch: the world is built again")
	_eq(office.floor_view.presentation.walkers(), [], "and nobody walks")
	_eq(office.navigator.pan_of(HerdrFleet.LOCAL), pan_a, "Local's map remembers where the drag left it")
	await process_frame
	await _drag_world(middle, Vector2(0, 30))
	var pan_b: Vector2 = office.camera.pan
	world = office.world
	await _floor_pick(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, "a"))
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "back on Local")
	_check(office.layout_plan() == plan_a, "on its same plan object")
	_eq(office.layout_attempt_count(), attempts + 1, "not planned again")
	_check(office.world != world, "cold again")
	_eq(office.floor_view.presentation.walkers(), [], "nobody walks")
	_eq(office.navigator.pan_of(bee), pan_b, "and bee's map remembers its own drag")
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")


## Another machine's blocked agents show only as its SPACES rows' counts: an edge arrow is for a zone
## of the shown map with a blocked desk off screen. Both serve snapshot_basic: bravo (2) has one blocked.
func test_another_machines_blocked_agents_show_only_as_rail_counts() -> void:
	var office: OfficeDouble = await _two_machine_office()
	var bee := "socket:bee"
	var local_bravo := HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo")
	var bee_bravo := HerdrFleet.pane_key(bee, "bravo")
	var zones := func() -> Array:
		return office.hud.edge_arrows.shown().map(func(arrow: OfficeEdgeArrow) -> String: return arrow.zone_key())
	var counted := func(key: String) -> String:
		var count: Label = office.hud.spaces.row_for(key).get_node("%BlockedCount")
		return count.text if count.visible else ""
	await process_frame
	await process_frame
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "Local's map is shown")
	var off := not _bubble_on_screen(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo:p1"))
	_check(off, "opening on its 1, the blocked desk of its 2 is off screen")
	_eq(zones.call(), [local_bravo], "an arrow for Local's 2, none for bee's")
	_eq([counted.call(local_bravo), counted.call(bee_bravo)], ["1", "1"], "both rows count their blocked agent")
	await _navigate_key(office, KEY_PAGEDOWN)
	await process_frame
	await process_frame
	_eq(office.navigator.shown_key, HerdrFleet.LOCAL, "PageDown pans to Local's 2, on the same map")
	_check(_bubble_on_screen(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo:p1")), "its blocked desk in view")
	_eq(zones.call(), [], "so its arrow goes, and bee's zone never had one")
	_eq(counted.call(bee_bravo), "1", "bee's row still counts it")
	await _heading_pick(office, bee)
	_eq(office.navigator.shown_key, bee, "a click on bee's heading shows bee's map")
	var on_bee: Array = zones.call()
	_check(on_bee.all(func(key: String) -> bool: return key == bee_bravo), "only bee's own zone can have an arrow")
	_eq(counted.call(local_bravo), "1", "and Local's blocked agent is its row's count")
	root.remove_child(office)
	office.free()
	OS.unset_environment("HERDR_BIN_PATH")
