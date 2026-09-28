extends SceneTree
## The harness behind tools/test_client.gd, tools/test_machines.gd and
## tools/test_office_incremental.gd: the assertions, the case list, the one
## summary line tools/run_tests.sh greps for, and the exit code.
##
## Cases discover themselves. Every method of the test script whose name starts
## with `test_` is a case, and they run in source order, which is the order
## `Script.get_script_method_list()` reports. There is no list to keep in step:
## a case that is written runs. Where a case has to run after the others
## (test_client.gd's `test_only_read_only_requests` sums up the whole run), it
## is kept last in its file and says so.
##
## A subclass parses its own arguments in `_initialize`, does whatever setup it
## needs, and then awaits `run_cases()`. It overrides `_marker` with its own
## summary text, `_after_case` to tear down what a case leaves behind, and
## `_summary_suffix` for anything only it counts.
##
## A GDScript runtime error ends the function it happens in, and whatever checks
## the case had left never run, so no check can fail for it: the case fails on
## the error itself (see ScriptErrorLog). tools/run_tests.sh still fails the
## whole run on any `SCRIPT ERROR` in the log, inside a case or not.

var failures: Array = []
## The case running now; every failure is reported under it.
var current := ""
## Assertions made, over every case.
var checks := 0


## The GDScript runtime errors raised while cases run. The engine hands them to
## every Logger as ERROR_TYPE_SCRIPT, the kind its console prints as
## `SCRIPT ERROR`. `push_error()` and the engine's own errors are
## ERROR_TYPE_ERROR and stay out: several cases provoke those on purpose (a
## broken pack, a bad manifest). The engine may call this from any thread, so it
## only records.
class ScriptErrorLog:
	extends Logger

	var _lock := Mutex.new()
	var _seen: Array[String] = []

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		var text := code if rationale.is_empty() else "%s (%s)" % [rationale, code]
		_lock.lock()
		_seen.append("%s at %s:%d in %s()" % [text, file, line, function])
		_lock.unlock()

	## Every error recorded since the last call, oldest first.
	func take() -> Array[String]:
		var taken: Array[String] = []
		_lock.lock()
		taken.assign(_seen)
		_seen.clear()
		_lock.unlock()
		return taken


## Every line the engine logs while it is installed: prints, warnings, errors.
## For the cases that prove something never reaches the log (terminal text, a
## remote line that is not JSON); ScriptErrorLog above hears script errors only.
class Captured:
	extends Logger

	var _lock := Mutex.new()
	var _lines: Array[String] = []

	func _log_message(message: String, _error: bool) -> void:
		_lock.lock()
		_lines.append(message)
		_lock.unlock()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		_error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_lines.append("%s %s:%d %s %s" % [function, file, line, code, rationale])
		_lock.unlock()

	func lines() -> Array[String]:
		_lock.lock()
		var copy := _lines.duplicate()
		_lock.unlock()
		return copy


## Every `test_` method of the concrete test script, in source order.
func case_names() -> PackedStringArray:
	var names := PackedStringArray()
	var script: Script = get_script()
	for entry: Dictionary in script.get_script_method_list():
		var method := str(entry.name)
		if method.begins_with("test_"):
			names.append(method)
	return names


## Run every discovered case, print the summary and quit. Discovering nothing is
## a harness error, not a green run: that is the whole point of discovery.
func run_cases() -> void:
	var names := case_names()
	if names.is_empty():
		print("TEST_HARNESS_ERROR: no test_ case found in %s" % get_script().resource_path)
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var errors := ScriptErrorLog.new()
	OS.add_logger(errors)
	for name: String in names:
		current = name
		var before := failures.size()
		await call(name)
		_after_case()
		# Whatever ran while this case did, its teardown included.
		for error in errors.take():
			_fail("script error: " + error)
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", name])
	OS.remove_logger(errors)
	# run_tests.sh greps this line for the marker and reads the case count off
	# it, so a file that silently loses its cases fails the run.
	print(
		(
			"%s %s: %d cases, %d checks, %d failures, %.1fs%s"
			% [
				_marker(),
				"OK" if failures.is_empty() else "FAILED",
				names.size(),
				checks,
				failures.size(),
				(Time.get_ticks_msec() - started) / 1000.0,
				_summary_suffix(),
			]
		)
	)
	for failure: String in failures:
		print("  FAILED " + failure)
	quit(0 if failures.is_empty() else 1)


## What the summary line starts with. run_tests.sh greps for it.
func _marker() -> String:
	return "TESTS"


## Called after every case, whether it passed or not.
func _after_case() -> void:
	pass


## Appended to the summary line, for what only one suite counts.
func _summary_suffix() -> String:
	return ""


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		_fail(message)


func _eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		_fail("%s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])


func _fail(message: String) -> void:
	failures.append("%s: %s" % [current, message])
	print("  FAIL %s: %s" % [current, message])


# --- reading what a fake herdr or a fixture sent ---------------------------------
# `Dictionary.get()` answers Variant, so a suite that wants to count, slice or
# walk what came back has to say what it expects. These say it once.


## A list inside `data`, empty when the key holds something else or nothing.
func _list(data: Dictionary, key: String) -> Array:
	if not data.get(key, []) is Array:
		return []
	var found: Array = data.get(key, [])
	return found


## An object inside `data`, empty when the key holds something else or nothing.
func _dict(data: Dictionary, key: String) -> Dictionary:
	if not data.get(key, {}) is Dictionary:
		return {}
	var found: Dictionary = data.get(key, {})
	return found


## A flag inside `data`; anything that is not a JSON boolean is `fallback`, so a
## missing key never reads as a deliberate false.
func _flag(data: Dictionary, key: String, fallback := false) -> bool:
	if not data.get(key) is bool:
		return fallback
	var found: bool = data.get(key)
	return found


## A number inside `data`, `fallback` when the key holds something else.
func _number(data: Dictionary, key: String, fallback := 0.0) -> float:
	if not (data.get(key) is int or data.get(key) is float):
		return fallback
	var found: float = data.get(key)
	return found


## Drop the key at the end of `path` from a nested object, for the fixtures that
## are the shipped manifest minus one thing.
func _drop(data: Dictionary, path: Array) -> void:
	var holder := data
	for step: String in path.slice(0, path.size() - 1):
		holder = _dict(holder, step)
	holder.erase(path[path.size() - 1])
