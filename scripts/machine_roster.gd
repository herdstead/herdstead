class_name MachineRoster
extends Node
## Which herdr machines exist: `herdr machine list --json`, polled without
## blocking, plus debug sockets from `--machine-socket=<label>=<path>`.
## Knows no rendering and opens no connection itself.

## `machines` or `sockets` changed.
signal changed

const INTERVAL := 10.0
## A list call still running after this long is killed and counts as a failure.
const TIMEOUT := 8.0
## herdr missing this many polls in a row means it is gone, not hiccuping.
const MISSING_LIMIT := 3
## How much of the list call's output is read. A list longer than this is not
## one this office could show anyway, and reads as not being a list at all.
const OUTPUT_KEEP := 1048576
const STDERR_KEEP := 4096

## C0 controls, DEL, C1 controls, the two Unicode line separators, and the bidi
## embeddings, overrides and isolates (U+202A–U+202E, U+2066–U+2069): what
## clean_text() drops. A remote label or id carrying one could otherwise reorder
## what the office draws around it. U+2028–U+202E is one run: the separators and
## the first five bidi controls. Compiled once; most text holds none of them.
static var _control := RegEx.create_from_string("[\\x{0}-\\x{1f}\\x{7f}-\\x{9f}\\x{2028}-\\x{202e}\\x{2066}-\\x{2069}]")

## Saved machines, normalized by `normalize()`, in herdr's order. Disabled ones
## stay listed with `enabled` false; the office decides what to show.
var machines: Array[Machine] = []
## Debug machines straight from the command line.
var sockets: Array[DebugSocket] = []
## Finished list calls, successful or not; a probe waits for the first.
var attempts := 0

var _lister := ChildProcess.new(OUTPUT_KEEP, STDERR_KEEP)
var _left := 0.0
var _running_for := 0.0
var _succeeded := false
var _failing := false
var _missing := 0


## One saved machine as `normalize()` reads it.
class Machine:
	## `machine:<profile id>`, or target and session when herdr gave no id.
	var key := ""
	var id := ""
	## The label, or the target when herdr gave none.
	var label := ""
	var target := ""
	var session := ""
	var enabled := true

	func same_as(other: Machine) -> bool:
		return (
			key == other.key
			and id == other.id
			and label == other.label
			and target == other.target
			and session == other.session
			and enabled == other.enabled
		)


## `--machine-socket=<label>=<path>`: a herdr socket on this computer, shown as a machine.
class DebugSocket:
	var label := ""
	var socket := ""


## `HERDR_BIN_PATH` beats whatever `herdr` the PATH finds. An app started from
## Finder has a minimal PATH, so it needs the variable or a terminal launch.
static func herdr_binary() -> String:
	var from_environment := OS.get_environment("HERDR_BIN_PATH")
	return from_environment if not from_environment.is_empty() else "herdr"


## Every `--machine-socket=<label>=<path>`, in order. The label ends at the first
## `=`, so a path may contain one. Malformed ones are reported and skipped.
static func parse_socket_args(user_args: PackedStringArray) -> Array[DebugSocket]:
	var result: Array[DebugSocket] = []
	for argument in user_args:
		if not argument.begins_with("--machine-socket="):
			continue
		var spec := argument.trim_prefix("--machine-socket=")
		var cut := spec.find("=")
		if cut <= 0 or cut == spec.length() - 1 or clean_text(spec.substr(0, cut)) != spec.substr(0, cut):
			push_warning("Ignoring %s: expected --machine-socket=<label>=<path>" % argument)
			continue
		var entry := DebugSocket.new()
		entry.label = spec.substr(0, cut)
		entry.socket = spec.substr(cut + 1)
		result.append(entry)
	return result


## The one place that knows the field names of a saved machine. herdr 0.9.0
## documents only a profile id, label, SSH target, explicit session and enabled
## state, and prints `[]` with none saved, so the exact spelling is unverified:
## every plausible spelling is accepted, and a missing field reads as absent.
static func normalize(record: Dictionary) -> Machine:
	var machine := Machine.new()
	machine.id = _first(record, ["profile_id", "id", "profile", "machine_id"])
	machine.target = _first(record, ["ssh_target", "target", "ssh", "destination", "host"])
	machine.session = _first(record, ["remote_session", "session", "herdr_session", "session_name"])
	var label := _first(record, ["label", "name"])
	# Without an id, the target and session are what make it the same machine.
	var identity := machine.id if not machine.id.is_empty() else "%s/%s" % [machine.target, machine.session]
	machine.key = "machine:" + identity
	# A name plate: bounded like every remote string the office draws (invariant 9).
	machine.label = TerminalText.bound(label if not label.is_empty() else machine.target)
	machine.enabled = _flag(record.get("enabled"))
	return machine


## A scalar as text, with control characters dropped: they would end up in
## composite pane keys and on name plates. JSON numbers arrive as floats, so a
## whole one reads `7`, not `7.0`. Anything else is absent.
static func clean_text(value: Variant) -> String:
	var text := ""
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			text = str(value)
		TYPE_INT:
			text = str(value)
		TYPE_FLOAT:
			var number: float = value
			# A JSON number that is whole prints as an integer, so an id does not
			# come back as "3.0" and stop matching the one herdr reported.
			text = str(int(number)) if is_equal_approx(number, roundf(number)) and absf(number) < 1e15 else str(number)
		TYPE_BOOL:
			text = "true" if value else "false"
	if _control.search(text) != null:
		text = _control.sub(text, "", true)
	return text.strip_edges()


## `enabled` as herdr might spell it; absent means enabled.
static func _flag(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return true
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).strip_edges().to_lower() in ["true", "1", "yes", "on"]
	return false


## `herdr machine list --json` output to normalized records, as an
## Array[Machine]. A bare array, or an object wrapping one, both read. Null when
## the text is not a machine list; text that is not JSON is never echoed.
static func parse_list(text: String) -> Variant:
	var data: Variant = HerdrClient.parse_line(text)
	if data is Dictionary:
		var wrapper: Dictionary = data
		for key: String in ["machines", "profiles", "items"]:
			if typeof(wrapper.get(key)) == TYPE_ARRAY:
				data = wrapper[key]
				break
	if not data is Array:
		return null
	var listed: Array = data
	var result: Array[Machine] = []
	var seen := {}
	for entry: Variant in listed:
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var machine := normalize(record)
		if machine.target.is_empty() or seen.has(machine.key):
			continue
		seen[machine.key] = true
		result.append(machine)
	return result


## The two lists name the same machines, field for field, in the same order.
static func same_list(a: Array[Machine], b: Array[Machine]) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if not a[index].same_as(b[index]):
			return false
	return true


static func _first(record: Dictionary, names: Array) -> String:
	for field: String in names:
		var text := clean_text(record.get(field))
		if not text.is_empty():
			return text
	return ""


func start(user_args: PackedStringArray) -> void:
	sockets = parse_socket_args(user_args)
	_left = 0.0
	set_process(true)
	if not sockets.is_empty():
		changed.emit()


func stop() -> void:
	set_process(false)
	_kill()


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if _lister.pid > 0:
		_poll(delta)
		return
	_left -= delta
	if _left <= 0.0:
		_left = INTERVAL
		_list()


func _list() -> void:
	_running_for = 0.0
	if not binary_present(herdr_binary()):
		_gone("cannot find " + herdr_binary())
		return
	if not _lister.spawn(herdr_binary(), PackedStringArray(["machine", "list", "--json"])):
		_gone("cannot run " + herdr_binary())
		return
	_missing = 0


## Whether `binary` is a file, directly or on PATH. A spawn of a missing binary
## still returns a pid in Godot, so this is how "herdr is gone" is told apart.
static func binary_present(binary: String) -> bool:
	if "/" in binary:
		return FileAccess.file_exists(binary)
	for directory in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(directory.path_join(binary)):
			return true
	return false


## herdr went away: after MISSING_LIMIT polls in a row, stop trusting the last
## list and fall back to Local.
func _gone(reason: String) -> void:
	_missing += 1
	_failed(reason)
	if _missing >= MISSING_LIMIT and not machines.is_empty():
		push_warning("%s %d times; showing Local only" % [reason, _missing])
		var none: Array[Machine] = []
		machines = none
		changed.emit()


func _poll(delta: float) -> void:
	# stderr is drained too: a chatty herdr must not block on a full stderr pipe.
	_lister.drain()
	if _lister.running():
		_running_for += delta
		if _running_for >= TIMEOUT:
			_kill()
			_failed("herdr machine list timed out")
		return
	var code := _lister.exit_code()
	_lister.drain()
	_lister.release()
	if code != 0:
		_failed("herdr machine list exited with %d" % code)
		return
	var parsed: Variant = parse_list(_lister.stdout.get_string_from_utf8())
	if parsed == null:
		_failed("herdr machine list printed something that is not a machine list")
		return
	attempts += 1
	_succeeded = true
	_failing = false
	var listed: Array[Machine] = parsed
	if not same_list(listed, machines):
		machines = listed
		changed.emit()


## No herdr, an old herdr or a hiccup: one warning per failing stretch, never
## one per poll. A list that worked before is kept, so a transient failure does
## not tear every SSH forward down; one that never worked stays empty.
func _failed(reason: String) -> void:
	attempts += 1
	if not _failing:
		_failing = true
		if _succeeded:
			push_warning(reason + "; keeping the last machine list")
		elif OS.is_stdout_verbose():
			print(reason + "; showing Local only")


func _kill() -> void:
	_lister.kill()
