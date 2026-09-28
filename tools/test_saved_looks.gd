extends "res://tools/test_base.gd"
## Headless tests for the saved looks file (AgentCatalog): a save never loses or
## hides anything, or it refuses and says why. Its check of its own text, each
## check made to fail on purpose; a file grown past the size cap; a provider
## past the provider cap; an entry in a format this build does not read; the
## numbers' written form; the nesting bound; the id rule's whole-text match; a
## saved file that is a symbolic link; failed writes that leave nothing behind.
## Every case saves to its own file under --work, never the user's.
## Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_saved_looks.gd -- --work=<tmp dir>


## A catalog whose save text can be spoiled one way, to show each of the save's
## checks refusing it.
class Spoiled:
	extends AgentCatalog

	## Which way the text is spoiled; "" leaves it as it is.
	var fault := ""

	func _init(at: String) -> void:
		super(at)

	func encode(document: Dictionary) -> String:
		var copy := document.duplicate(true)
		var looks: Dictionary = copy["looks"]
		match fault:
			"size":
				return super(copy) + " ".repeat(AgentCatalog.MAX_BYTES)
			"reads back":
				return "{"
			"set reads back":
				var claude: Dictionary = looks["claude"]
				claude.erase("top")
			"readable before":
				var codex: Dictionary = looks["codex"]
				codex["top"] = "plum"
			"pass-through":
				var claude: Dictionary = looks["claude"]
				claude["cape"] = {"hem": 2}
		return super(copy)


var args: Dictionary[String, String] = {}
var _saves := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	if not args.has("work"):
		print("TEST_HARNESS_ERROR: missing --work= (use tools/run_tests.sh)")
		quit(2)
		return
	run_cases()


func _marker() -> String:
	return "SAVED LOOKS TESTS"


# --- helpers ----------------------------------------------------------------------


## A fresh saved-looks path under --work for one case, holding `text` if any.
func _save_path(text := "") -> String:
	_saves += 1
	var directory := args.work.path_join("looks_%d" % _saves)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("herdstead_avatars.json")
	if not text.is_empty():
		_write(path, text)
	return path


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## `text` as a JSON object; empty when it is not one.
func _object(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var found: Dictionary = parsed
		return found
	return {}


func _looks(path: String) -> Dictionary:
	return _dict(_object(_text(path)), "looks")


func _pin(slot: StringName, value: StringName) -> AvatarLook:
	return AvatarLook.with_slots({slot: value})


func _only(slot: StringName) -> Array[StringName]:
	return [slot]


## The files in `path`'s folder whose names end in `.tmp`.
func _temporaries(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	for name in DirAccess.get_files_at(path.get_base_dir()):
		if name.ends_with(".tmp"):
			found.append(name)
	return found


## A schema 2 file with `count` readable providers agent-0 ... and `first` before them.
func _crowded(count: int, first := {}) -> String:
	var looks := first.duplicate()
	for index in count:
		looks["agent-%d" % index] = {"top": "cream"}
	return JSON.stringify({"schema_version": 2, "looks": looks}, "", false)


# --- cases ----------------------------------------------------------------------------


## The guard: before it writes, a save reads its own text back with the loader's
## reader. Each check, made to fail, refuses the save, names itself, writes
## nothing and leaves the catalog as it was.
func test_a_save_checks_its_own_text_before_writing() -> void:
	var text := '{"schema_version": 2, "looks": {"claude": {"top": "navy", "cape": {"hem": 1}}, "codex": {"top": "cream"}}}'
	for fault: String in ["size", "reads back", "set reads back", "readable before", "pass-through"]:
		var path := _save_path(text)
		var catalog := Spoiled.new(path)
		catalog.fault = fault
		var result := catalog.save_look("claude", _pin(AvatarLook.TOP, &"lilac"), _only(AvatarLook.TOP))
		_check(result != OK, "%s: refused" % fault)
		_check(catalog.note.contains("(check: %s)" % fault), "%s: the note names the check: %s" % [fault, catalog.note])
		_check(catalog.note.ends_with("Nothing was written."), "%s: and says nothing was written" % fault)
		_eq(_text(path), text, "%s: the file is exactly as it was" % fault)
		_eq(_temporaries(path), PackedStringArray(), "%s: no temporary file" % fault)
		_eq(catalog.pins("claude").top, &"navy", "%s: the catalog still holds what is on disk" % fault)
		catalog.fault = ""
		_eq(catalog.save_look("codex", _pin(AvatarLook.LEGS, &"plum"), _only(AvatarLook.LEGS)), OK, "%s: then" % fault)
		var claude := _dict(_looks(path), "claude")
		_eq(claude.get("top"), "navy", "%s: a later save does not carry the refused change" % fault)
		_eq(claude.get("cape"), {"hem": 1.0}, "%s: and keeps what it cannot read" % fault)


## A file another writer wrote compact, near the size cap. A save writes
## compact too, so it does not grow; one that would pass the cap is refused.
func test_a_save_never_grows_the_file_past_the_size_cap() -> void:
	var looks := {}
	for index in 4000:
		looks["agent-%d" % index] = {"top": "cream", "legs": "plum"}
	var compact := JSON.stringify({"schema_version": 2, "looks": looks, "pad": "x".repeat(40000)}, "", false)
	var path := _save_path(compact)
	_check(compact.length() < AgentCatalog.MAX_BYTES, "a compact file under the cap: %d bytes" % compact.length())
	var catalog := AgentCatalog.new(path)
	_eq(catalog.state, AgentCatalog.FileState.READ, "is read")
	_eq(catalog.save_look("agent-7", _pin(AvatarLook.TOP, &"lilac"), _only(AvatarLook.TOP)), OK, "a save")
	var grown := _text(path).length() - compact.length()
	_check(grown <= 8, "writes it compact, the same size: %d bytes more" % grown)
	var again := AgentCatalog.new(path)
	_eq(again.state, AgentCatalog.FileState.READ, "and it still reads")
	_eq(again.pins("agent-7").top, &"lilac", "with the save")
	var full := '{"schema_version":2,"looks":{},"pad":"%s"}'
	var padding := AgentCatalog.MAX_BYTES - full.length() + 2 - 8
	var near := _save_path(full % "x".repeat(padding))
	var crowded := AgentCatalog.new(near)
	_eq(crowded.state, AgentCatalog.FileState.READ, "a file 8 bytes short of the cap is read")
	var before := _text(near)
	_check(crowded.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "a save that would pass the cap")
	_check(crowded.note.contains("(check: size)"), "is refused, and says why: " + crowded.note)
	_eq(_text(near), before, "the file is untouched")


## A pin that would land past MAX_PROVIDERS would be unread the moment it
## is written: refused, with a note that says so.
func test_a_provider_past_the_provider_cap_is_refused() -> void:
	var path := _save_path(_crowded(AgentCatalog.MAX_PROVIDERS + 44))
	var catalog := AgentCatalog.new(path)
	var before := _text(path)
	_check(catalog.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "a new provider past the cap")
	_check(catalog.note.contains("too many saved providers"), "is refused: " + catalog.note)
	_eq(_text(path), before, "the file is untouched")
	_eq(catalog.pins("claude").pinned, [] as Array[StringName], "and nothing claims it was pinned")
	# Unpinned, a provider leaves the file; pinned again, it would come last.
	var first := _save_path(_crowded(AgentCatalog.MAX_PROVIDERS, {"claude": {"top": "navy"}}))
	var ahead := AgentCatalog.new(first)
	_eq(ahead.pins("claude").top, &"navy", "claude is read, first in the file")
	_eq(ahead.save_look("claude", AvatarLook.new()), OK, "unpinning it")
	_check(ahead.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "pinning it again, past the cap")
	_check(ahead.note.contains("too many saved providers"), "is refused: " + ahead.note)


## A provider whose saved value is not an object (a newer format) is never
## replaced; the note says why.
func test_a_provider_saved_in_another_format_is_never_replaced() -> void:
	for value: String in ['"future-format"', "7", "null", '["a", 1]']:
		var text := '{"schema_version": 2, "looks": {"claude": %s, "codex": {"top": "cream"}}}' % value
		var path := _save_path(text)
		var catalog := AgentCatalog.new(path)
		_check(not catalog.editable("claude"), "%s: not editable" % value)
		_check(catalog.save_look("claude", _pin(AvatarLook.TOP, &"slate")) != OK, "%s: refused" % value)
		_check(catalog.note.contains("format this build doesn't read"), "%s: and says why: %s" % [value, catalog.note])
		_eq(_text(path), text, "%s: the file is exactly as it was" % value)
		_eq(catalog.save_look("pi", _pin(AvatarLook.TOP, &"slate")), OK, "%s: another provider saves" % value)
		_eq(JSON.stringify(_looks(path).get("claude")), JSON.stringify(JSON.parse_string(value)), "%s: kept" % value)


## The saved file's bytes: schema_version and every whole number keep their
## integer form, a float keeps its exact double; again after a second save.
func test_numbers_keep_their_written_form() -> void:
	var text := (
		'{"schema_version": 2, "looks": {"claude": {"skin": 7, "top": "navy", "x_prec": 0.1234567890123456, '
		+ '"x_neg": -3, "x_big": 12345678901234567890}}}'
	)
	var path := _save_path(text)
	var catalog := AgentCatalog.new(path)
	for pass_number: int in 2:
		_eq(
			catalog.save_look("pi", _pin(AvatarLook.GLASSES, &"round" if pass_number == 0 else &"square")), OK, "a save"
		)
		var written := _text(path)
		_check(written.contains('"schema_version":2,'), "%d: schema_version stays 2: %s" % [pass_number, written])
		_check(written.contains('"skin":7,'), "%d: a whole number stays whole" % pass_number)
		_check(written.contains('"x_neg":-3,'), "%d: a negative one too" % pass_number)
		_check(written.contains('"x_prec":0.1234567890123456,'), "%d: a float keeps every digit" % pass_number)
		var claude := _dict(_dict(_object(written), "looks"), "claude")
		_eq(claude.get("x_big"), 12345678901234567890.0, "%d: past 2^53, the same double" % pass_number)


## A file nested deeper than MAX_DEPTH, or larger than MAX_BYTES, is not read
## and never written; one at the depth bound is read, and a save keeps it whole.
func test_a_file_too_deep_or_too_large_is_never_written() -> void:
	var inner := AgentCatalog.MAX_DEPTH - 3
	var nested := "[".repeat(inner) + "]".repeat(inner)
	var text := '{"schema_version": 2, "looks": {"claude": {"top": "navy", "deep": %s}}}' % nested
	var path := _save_path(text)
	var catalog := AgentCatalog.new(path)
	_eq(catalog.state, AgentCatalog.FileState.READ, "%d levels are read" % AgentCatalog.MAX_DEPTH)
	_eq(catalog.save_look("claude", _pin(AvatarLook.LEGS, &"plum"), _only(AvatarLook.LEGS)), OK, "a save")
	_check(_text(path).contains('"deep":%s' % nested), "keeps them all")
	var deeper := "[".repeat(inner + 1) + "]".repeat(inner + 1)
	var past := _save_path('{"schema_version": 2, "looks": {"claude": {"top": "navy", "deep": %s}}}' % deeper)
	var deep := AgentCatalog.new(past)
	var before := _text(past)
	# A file this build reads, only deeper: not read, never written, not DAMAGED and not moved aside.
	_eq(deep.state, AgentCatalog.FileState.OUT_OF_BOUNDS, "one level more is not read")
	_check(deep.problem.contains("too deep for this build"), "and says why: " + deep.problem)
	_check(deep.save_look("codex", _pin(AvatarLook.TOP, &"lilac")) != OK, "a save is refused")
	_check(deep.note.contains("never written over"), "and says so: " + deep.note)
	_eq(_text(past), before, "the file is exactly as it was")
	_eq(DirAccess.get_files_at(past.get_base_dir()).size(), 1, "and nothing was put beside it")
	var large := _save_path('{"schema_version": 2, "looks": {}, "pad": "%s"}' % "x".repeat(AgentCatalog.MAX_BYTES))
	var big := AgentCatalog.new(large)
	_eq(big.state, AgentCatalog.FileState.OUT_OF_BOUNDS, "a file past the size cap is not read")
	_check(big.save_look("codex", _pin(AvatarLook.TOP, &"lilac")) != OK, "nor written")
	_check(big.note.contains("too large for this build"), "and says why: " + big.note)
	_eq(DirAccess.get_files_at(large.get_base_dir()).size(), 1, "nothing was put beside it")


## The id rule is the whole text: `$` alone also matches before a final line break.
func test_an_id_with_a_line_break_is_not_an_id() -> void:
	_eq(AgentCatalog.valid_id("cream\n"), &"", "a trailing line break")
	_eq(AgentCatalog.valid_id("cream"), &"cream", "without it, an id")
	var path := _save_path('{"schema_version": 2, "looks": {"claude": {"top": "cream\\n"}}}')
	var catalog := AgentCatalog.new(path)
	_eq(catalog.pins("claude").top, &"", "is not read as a pin")
	# Shown as the file writes it: the line break as \u000a.
	_eq(catalog.unreadable("claude").get(AvatarLook.TOP), '"cream\\u000a"', "it is a value this build cannot read")
	_check(catalog.save_look("claude\n", _pin(AvatarLook.TOP, &"lilac")) != OK, "nor saved as a provider")


## When the saved file is a symbolic link (dotfiles), a save replaces the file it
## links to; the link stays a link.
func test_a_saved_file_that_is_a_link_stays_a_link() -> void:
	var path := _save_path()
	var real := path.get_base_dir().path_join("elsewhere").path_join("real.json")
	DirAccess.make_dir_recursive_absolute(real.get_base_dir())
	_write(real, '{"schema_version": 2, "looks": {"codex": {"top": "cream"}}}')
	var made := OS.execute("ln", PackedStringArray(["-s", "elsewhere/real.json", ProjectSettings.globalize_path(path)]))
	if made != 0:
		print("  (no symbolic links here: ln exited %d; the case checks nothing)" % made)
		return
	var catalog := AgentCatalog.new(path)
	_eq(catalog.pins("codex").top, &"cream", "read through the link")
	_eq(catalog.save_look("claude", _pin(AvatarLook.TOP, &"lilac")), OK, "a save")
	var folder := DirAccess.open(path.get_base_dir())
	_check(folder.is_link(path.get_file()), "the saved file is still a link")
	_eq(_dict(_looks(real), "claude").get("top"), "lilac", "the file it links to holds the save")
	_eq(_dict(_looks(real), "codex").get("top"), "cream", "and what it held")
	_eq(_temporaries(real), PackedStringArray(), "no temporary file beside it")


## M21: an option id the reader would not keep is refused before anything else,
## and the note says which.
func test_an_option_id_the_reader_would_not_keep_is_refused() -> void:
	var path := _save_path('{"schema_version": 2, "looks": {"claude": {"top": "navy"}}}')
	var catalog := AgentCatalog.new(path)
	var before := _text(path)
	_check(catalog.save_look("claude", _pin(AvatarLook.TOP, &"Navy Blue")) != OK, "refused")
	_check(catalog.note.contains('"Navy Blue" is not an option id'), "the note names it: " + catalog.note)
	_eq(_text(path), before, "nothing written")


## M22: a save whose write fails changes nothing in the catalog either; the
## next save does not carry it to disk.
func test_a_failed_write_is_not_carried_by_the_next_save() -> void:
	var path := _save_path('{"schema_version": 2, "looks": {"claude": {"top": "cream"}}}')
	var catalog := AgentCatalog.new(path)
	var blocked := catalog.temporary_path()
	DirAccess.make_dir_absolute(blocked)
	_check(catalog.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "the write fails")
	_eq(catalog.pins("claude").top, &"cream", "the catalog still holds what is on disk")
	_eq(catalog.save_look("codex", _pin(AvatarLook.TOP, &"slate")), OK, "another provider saves")
	_eq(_dict(_looks(path), "claude").get("top"), "cream", "without the failed change")
	DirAccess.remove_absolute(blocked)


## M25: a write that fails after its temporary file was made removes it.
func test_a_failed_rename_leaves_no_temporary_file() -> void:
	var path := _save_path()
	# The saved file's name is a folder with something in it: the rename over it fails.
	DirAccess.make_dir_absolute(path)
	_write(path.path_join("keep"), "x")
	var catalog := AgentCatalog.new(path)
	_check(catalog.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "the rename fails")
	_eq(_temporaries(path), PackedStringArray(), "and its temporary file is gone")
	_check(catalog.note.contains("Not saved"), "the note says so: " + catalog.note)
	_check(catalog.note.contains(path) and catalog.note.contains("folder"), "naming the path and why: " + catalog.note)


## The file on disk is the one that was read. Anything else there
## at save time (a hand edit, a damaged file, a newer Herdstead's, another
## studio's save, nothing at all) is never written over: refused, and said.
func test_a_file_changed_on_disk_since_it_was_read_is_never_written_over() -> void:
	var text := '{"schema_version": 2, "looks": {"claude": {"top": "navy"}}}'
	var swaps: Dictionary[String, String] = {
		"a hand edit": '{"schema_version": 2, "looks": {"claude": {"top": "navy"}, "codex": {"note": "hand edit"}}}',
		"a damaged file": "{ not json",
		"a newer file": '{"schema_version": 3, "looks": {}, "cape": {"v": 3}}',
		"the same size": text.replace("navy", "teal"),
	}
	for swap: String in swaps:
		var path := _save_path(text)
		var catalog := AgentCatalog.new(path)
		_write(path, swaps[swap])
		_check(catalog.save_look("pi", _pin(AvatarLook.GLASSES, &"round")) != OK, "%s: refused" % swap)
		_check(
			catalog.note.contains("changed on disk since it was read"), "%s: and says why: %s" % [swap, catalog.note]
		)
		_eq(_text(path), swaps[swap], "%s: the file on disk is exactly as it was put there" % swap)
		_eq(DirAccess.get_files_at(path.get_base_dir()).size(), 1, "%s: nothing was put beside it" % swap)
	var gone := _save_path(text)
	var removed := AgentCatalog.new(gone)
	DirAccess.remove_absolute(gone)
	_check(removed.save_look("pi", _pin(AvatarLook.GLASSES, &"round")) != OK, "a file removed since: refused")
	_check(not FileAccess.file_exists(gone), "and not written")
	# Two catalogs on one file: the second save finds the first one's.
	var shared := _save_path(text)
	var first := AgentCatalog.new(shared)
	var second := AgentCatalog.new(shared)
	_eq(first.save_look("claude", _pin(AvatarLook.LEGS, &"plum"), _only(AvatarLook.LEGS)), OK, "one saves")
	_check(second.save_look("pi", _pin(AvatarLook.GLASSES, &"round")) != OK, "the other is refused")
	_eq(_dict(_looks(shared), "claude").get("legs"), "plum", "the first save stays")
	_eq(first.save_look("codex", _pin(AvatarLook.TOP, &"cream")), OK, "a catalog's own saves follow one another")
	_eq(AgentCatalog.new(shared).save_look("pi", _pin(AvatarLook.TOP, &"cream")), OK, "and a fresh read saves")


## Every C0 control character and DEL in a string is written as \u00XX, so any
## strict JSON parser reads the file (Godot writes 0x0B as `\v`, no JSON at all).
func test_control_characters_are_written_as_escapes() -> void:
	var text := (
		'{"schema_version": 2, "looks": {"claude": {"top": "navy", "cape": "a\\u0001b\\u000bc\\u001fd\\u007fe\\tf"}}, '
		+ '"n\\u000bote": "x"}'
	)
	var path := _save_path(text)
	var catalog := AgentCatalog.new(path)
	_eq(catalog.state, AgentCatalog.FileState.READ, "read")
	_eq(catalog.save_look("pi", _pin(AvatarLook.GLASSES, &"round")), OK, "a save")
	var bytes := FileAccess.get_file_as_bytes(path)
	var raw := PackedByteArray()
	for index in bytes.size() - 1:
		if bytes[index] < 0x20 or bytes[index] == 0x7f:
			raw.append(bytes[index])
	_eq(raw, PackedByteArray(), "no raw control character or DEL, as strict JSON requires")
	_eq(bytes[bytes.size() - 1], 0x0a, "one line break, at the end")
	var written := _text(path)
	_check(written.contains('"a\\u0001b\\u000bc\\u001fd\\u007fe\\u0009f"'), "each one escaped: " + written)
	_check(written.contains('"n\\u000bote":"x"'), "in keys too")
	_check(not written.contains("\\v"), "never `\\v`")
	var again := AgentCatalog.new(path)
	_eq(again.state, AgentCatalog.FileState.READ, "and it reads back")


## More links than MAX_LINKS, or a loop: refused, and no link is replaced by a file.
func test_a_chain_of_too_many_links_is_refused() -> void:
	var path := _save_path()
	var folder := path.get_base_dir()
	_write(folder.path_join("real.json"), '{"schema_version": 2, "looks": {"claude": {"top": "navy"}}}')
	var made := OS.execute("ln", PackedStringArray(["-s", "real.json", folder.path_join("l8")]))
	for index in range(7, 0, -1):
		made += OS.execute("ln", PackedStringArray(["-s", "l%d" % (index + 1), folder.path_join("l%d" % index)]))
	made += OS.execute("ln", PackedStringArray(["-s", "l1", path]))
	if made != 0:
		print("  (no symbolic links here; the case checks nothing)")
		return
	var catalog := AgentCatalog.new(path)
	_eq(catalog.pins("claude").top, &"navy", "read through nine links")
	_check(catalog.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "a save is refused")
	_check(catalog.note.contains("symbolic links") and catalog.note.contains(path), "naming it: " + catalog.note)
	var still := DirAccess.open(folder)
	for name: String in ["herdstead_avatars.json", "l1", "l4", "l8"]:
		_check(still.is_link(name), "%s is still a link" % name)
	_eq(_dict(_looks(folder.path_join("real.json")), "claude").get("top"), "navy", "the file is untouched")
	var loop := _save_path()
	var other := loop.get_base_dir().path_join("other.json")
	OS.execute("ln", PackedStringArray(["-s", "other.json", loop]))
	OS.execute("ln", PackedStringArray(["-s", "herdstead_avatars.json", other]))
	var round_trip := AgentCatalog.new(loop)
	_check(round_trip.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "a loop is refused too")
	_check(DirAccess.open(loop.get_base_dir()).is_link(loop.get_file()), "and stays a link")
	var to_folder := _save_path()
	var target := to_folder.get_base_dir().path_join("a-folder")
	DirAccess.make_dir_absolute(target)
	OS.execute("ln", PackedStringArray(["-s", "a-folder", to_folder]))
	var foldered := AgentCatalog.new(to_folder)
	_check(foldered.save_look("claude", _pin(AvatarLook.TOP, &"lilac")) != OK, "a link to a folder is refused")
	_check(
		foldered.note.contains(target) and foldered.note.contains("folder"), "naming the path and why: " + foldered.note
	)


## A provider saved as `{}` is kept by a save that does not change it.
func test_an_empty_provider_is_kept() -> void:
	var path := _save_path('{"schema_version": 2, "looks": {"claude": {}, "codex": {"top": "cream"}}}')
	var catalog := AgentCatalog.new(path)
	_eq(catalog.save_look("pi", _pin(AvatarLook.GLASSES, &"round")), OK, "another provider saves")
	_eq(_looks(path).get("claude"), {}, "the empty one is kept")
	var nothing: Array[StringName] = []
	_eq(catalog.save_look("claude", AvatarLook.new(), nothing), OK, "a save of it that changes nothing")
	_eq(_looks(path).get("claude"), {}, "keeps it too")
	_eq(catalog.save_look("claude", AvatarLook.new()), OK, "unpinning what it does not have")
	_eq(_looks(path).get("claude"), {}, "keeps it as well")


## After a save, the catalog holds exactly what a fresh load of the file gives.
func test_after_a_save_memory_is_what_a_fresh_load_gives() -> void:
	var path := _save_path(
		'{"schema_version": 2, "presets": [1, 2.5], "looks": {"claude": {"skin": 7, "top": "navy"}, "codex": "x"}}'
	)
	var catalog := AgentCatalog.new(path)
	_eq(catalog.save_look("pi", _pin(AvatarLook.GLASSES, &"round")), OK, "a save")
	var fresh := AgentCatalog.new(path)
	_eq(
		JSON.stringify(catalog.held_document(), "", false, true),
		JSON.stringify(fresh.held_document(), "", false, true),
		"the document, number types and all"
	)
	for provider: String in ["claude", "codex", "pi"]:
		_eq(catalog.pins(provider).key(), fresh.pins(provider).key(), "%s's pins" % provider)
		_eq(catalog.unreadable(provider), fresh.unreadable(provider), "%s's unreadable values" % provider)
