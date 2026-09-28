extends "res://tools/test_base.gd"
## Headless tests for the Avatar Studio (scenes/avatar_studio.tscn), through
## real input only: a click is a mouse button pushed into the window at the
## window pixel the studio's design point is shown at, a key is a key event.
## Every case saves to its own file under --work, never the user's.
## Run through run_tests.sh; its own process, because the studio sets the
## window's content scale.
##
## godot --headless --path . --script tools/test_avatar_studio.gd -- --work=<tmp dir>

const STUDIO_SCENE := preload("res://scenes/avatar_studio.tscn")
const Studio := preload("res://scripts/avatar_studio.gd")
const SCREEN := Vector2i(1920, 960)

var args: Dictionary[String, String] = {}
var _spawned: Array[Node] = []
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
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "AVATAR STUDIO TESTS"


func _after_case() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()


# --- helpers ----------------------------------------------------------------------


func _save_path(text := "") -> String:
	_saves += 1
	var directory := args.work.path_join("studio_%d" % _saves)
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("herdstead_avatars.json")
	if not text.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	return path


## The studio in the tree, saving to `path`.
func _studio(path: String) -> Studio:
	var studio: Studio = STUDIO_SCENE.instantiate()
	studio.args = AppArgs.parse(PackedStringArray(["--avatars=" + path]))
	root.add_child(studio)
	_spawned.append(studio)
	await _settle()
	return studio


func _settle() -> void:
	for _frame in 3:
		await process_frame


func _parsed(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


## A click at the window pixel that shows the studio's design point `at`.
func _click_design(at: Vector2) -> void:
	var window := root.get_final_transform() * at
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = window
		event.global_position = window
		event.pressed = down
		await _parsed(event)


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		await _parsed(event)


func _pins(studio: Studio) -> AvatarLook:
	return studio.pins


func _preview(studio: Studio) -> PixelPerson:
	return studio.preview


func _rects(studio: Studio, name: String) -> Array[Rect2]:
	match name:
		"next_rects":
			return studio.next_rects
		"back_rects":
			return studio.back_rects
	return studio.slot_rects


func _row(slot_id: StringName) -> int:
	return AvatarLook.SLOTS.find(slot_id)


func _people(studio: Studio) -> PixelPeople:
	return studio.art.people


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _status(studio: Studio) -> String:
	return studio.status_line.text


# --- cases ----------------------------------------------------------------------------


func test_clicking_a_row_s_arrow_changes_that_slot_only() -> void:
	var studio := await _studio(_save_path())
	var before := _pins(studio).clothes().key()
	var people := _people(studio)
	var top := _row(AvatarLook.TOP)
	await _click_design(_rects(studio, "next_rects")[top].get_center())
	var first: StringName = people.slots[AvatarLook.TOP].options()[0]
	_eq(_pins(studio).top, first, "› steps TOP from VARIES to its first option")
	_eq(_preview(studio).look.top, first, "and the preview wears it")
	var others := _pins(studio).clothes()
	others.top = &""
	_eq(others.key(), before, "no other slot changed")
	await _click_design(_rects(studio, "back_rects")[top].get_center())
	_eq(_pins(studio).top, &"", "‹ steps back to VARIES")


func test_keys_step_the_selected_row() -> void:
	var studio := await _studio(_save_path())
	var people := _people(studio)
	_eq(studio.slot_index, 0, "the first row is the keyboard's")
	await _key(KEY_BRACKETRIGHT)
	await _key(KEY_BRACKETRIGHT)
	_eq(studio.slot_index, _row(AvatarLook.HAIR_COLOUR), "] moves down the rows")
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	var second: StringName = people.slots[AvatarLook.HAIR_COLOUR].options()[1]
	_eq(_pins(studio).hair_colour, second, "→ steps the row's value")
	_eq(_preview(studio).look.hair_colour, second, "and the preview shows it")
	await _key(KEY_0)
	_eq(_pins(studio).hair_colour, &"", "0 unpins the row")
	await _key(KEY_BRACKETLEFT)
	_eq(studio.slot_index, _row(AvatarLook.HAIR_STYLE), "[ moves up")


## An unpinned row shows what a pane of the agent would show: its variation
## for the studio's sample pane; a pinned one shows the pin.
func test_varies_shows_the_pane_s_variation() -> void:
	var studio := await _studio(_save_path())
	var people := _people(studio)
	var varied := people.resolve("claude", AvatarLook.new(), null, "studio")
	_eq(_preview(studio).look.skin, varied.skin, "VARIES: the sample pane's skin")
	_eq(_preview(studio).look.top, &"terra", "and the provider's clothes")
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.SKIN)].get_center())
	_eq(_preview(studio).look.skin, people.slots[AvatarLook.SKIN].options()[0], "pinned: the pin")


func test_down_loads_the_next_agent_s_pins() -> void:
	var path := _save_path('{"schema_version": 2, "looks": {"cline": {"glasses": "square", "top": "slate"}}}')
	var studio := await _studio(path)
	_eq(studio.agent_ids[studio.agent_index], "claude", "the studio opens on claude")
	await _key(KEY_DOWN)
	_eq(studio.agent_ids[studio.agent_index], "cline", "↓ is the next agent")
	_eq([_pins(studio).glasses, _pins(studio).top], [&"square", &"slate"], "with its saved pins")
	_eq(_pins(studio).skin, &"", "and nothing else pinned")
	await _key(KEY_UP)
	_eq(_pins(studio).glasses, &"", "↑ back to claude, who pinned nothing")


func test_enter_saves_exactly_the_pinned_rows_as_v2() -> void:
	var path := _save_path()
	var studio := await _studio(path)
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.GLASSES)].get_center())
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.HEADWEAR)].get_center())
	await _key(KEY_ENTER)
	var saved := _read(path)
	_eq(ArtFamily.whole(saved.get("schema_version")), 2, "schema 2")
	_eq(saved.get("looks"), {"claude": {"glasses": "round", "headwear": "cap"}}, "exactly the pinned rows")
	_check(_status(studio).begins_with("SAVED"), "the status says so: " + _status(studio))
	await _click_design(_rects(studio, "back_rects")[_row(AvatarLook.GLASSES)].get_center())
	await _click_design(studio.save_rect.get_center())
	_eq(_read(path).get("looks"), {"claude": {"headwear": "cap"}}, "the save button, clicked, unpins too")


func test_saving_over_a_v1_file_keeps_it() -> void:
	var v1 := '{"claude": {"hair": "cap", "outfit": "lilac"}}'
	var path := _save_path(v1)
	var studio := await _studio(path)
	_eq([_pins(studio).headwear, _pins(studio).top], [&"cap", &"lilac"], "the v1 look, migrated")
	await _key(KEY_ENTER)
	_eq(FileAccess.get_file_as_string(path.get_basename() + ".v1.json"), v1, "the v1 file is kept")
	_check(_status(studio).contains(".v1.json"), "and the status says where: " + _status(studio))
	_eq(
		_read(path).get("looks"),
		{
			"claude":
			{
				"hair_style": "short",
				"hair_colour": "umber",
				"headwear": "cap",
				"headwear_colour": "sea",
				"top": "lilac",
				"legs": "plum"
			}
		},
		"written as v2"
	)


func test_saving_over_a_damaged_file_keeps_it_and_says_where() -> void:
	var path := _save_path("][")
	var studio := await _studio(path)
	await _key(KEY_ENTER)
	_check(_status(studio).contains("damaged"), "the status names the kept file: " + _status(studio))
	var kept := 0
	for name in DirAccess.get_files_at(path.get_base_dir()):
		if name.contains(".damaged-"):
			kept += 1
	_eq(kept, 1, "the damaged file is beside the new one")
	_eq(ArtFamily.whole(_read(path).get("schema_version")), 2, "and the new one is v2")


func test_saving_over_a_newer_file_writes_nothing() -> void:
	var newer := '{"schema_version": 9, "looks": {}}'
	var path := _save_path(newer)
	var studio := await _studio(path)
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.TOP)].get_center())
	await _key(KEY_ENTER)
	_check(_status(studio).contains("newer"), "the status says why: " + _status(studio))
	_eq(FileAccess.get_file_as_string(path), newer, "the file is untouched")


## Every label the studio shows, by its text.
func _texts(studio: Node) -> PackedStringArray:
	var found := PackedStringArray()
	for node in studio.find_children("*", "Label", true, false):
		var label: Label = node
		found.append(label.text)
	return found


## A saved pin this build does not draw (a newer pack's id) is shown as kept,
## written back untouched by a save, and left only when the user steps its row.
func test_a_pin_this_build_does_not_draw_is_kept() -> void:
	var path := _save_path('{"schema_version": 2, "looks": {"claude": {"top": "navy", "legs": "plum"}}}')
	var studio := await _studio(path)
	_check(_texts(studio).has("navy (not in this build)"), "the row shows the kept id: %s" % [_texts(studio)])
	_check(studio.save_rect.size != Vector2.ZERO, "the whole composer is drawn, SAVE included")
	await _click_design(studio.save_rect.get_center())
	_eq(_read(path).get("looks"), {"claude": {"top": "navy", "legs": "plum"}}, "a save writes it back untouched")
	_check(_status(studio).begins_with("SAVED"), "and says it saved: " + _status(studio))
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.LEGS)].get_center())
	await _key(KEY_ENTER)
	var looks := _dict(_read(path), "looks")
	_eq(_dict(looks, "claude").get("top"), "navy", "changing another row keeps it")
	var legs: String = _dict(looks, "claude").get("legs", "")
	_check(legs != "plum", "and saves that row's change: " + legs)
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.TOP)].get_center())
	_check(not _texts(studio).has("navy (not in this build)"), "stepping its row moves off it")
	await _click_design(_rects(studio, "back_rects")[_row(AvatarLook.TOP)].get_center())
	_check(_texts(studio).has("navy (not in this build)"), "and stepping back returns to it")
	await _key(KEY_ENTER)
	_eq(_dict(_dict(_read(path), "looks"), "claude").get("top"), "navy", "still kept")
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.TOP)].get_center())
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.TOP)].get_center())
	await _key(KEY_ENTER)
	var chosen: String = _dict(_dict(_read(path), "looks"), "claude").get("top")
	_check(
		_people(studio).slots[AvatarLook.TOP].has_option(StringName(chosen)),
		"the user's own step replaced it: " + chosen
	)


## A colour picked by value (`{"rgb"}`, for a later phase) shows as kept and a
## save writes it back untouched.
func test_a_picked_colour_is_kept() -> void:
	var file := '{"schema_version": 2, "looks": {"claude": {"headwear_colour": {"rgb": "12ab34"}}}}'
	var path := _save_path(file)
	var studio := await _studio(path)
	_check(_texts(studio).has("#12ab34 (not in this build)"), "the row shows the picked colour: %s" % [_texts(studio)])
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.GLASSES)].get_center())
	await _key(KEY_ENTER)
	var claude := _dict(_dict(_read(path), "looks"), "claude")
	_eq(claude.get("headwear_colour"), {"rgb": "12ab34"}, "a save writes it back untouched")
	_eq(claude.get("glasses"), "round", "with the row the user changed")


## A value this build cannot read at all, in a slot it knows, is kept like
## any kept value: shown raw, untouched by stepping off it and back, written
## back by a save; only `0` on its row removes it, and the status says so.
func test_an_unreadable_value_is_kept_until_the_user_removes_it() -> void:
	var file := (
		'{"schema_version": 2, "looks": {"claude": {"skin": 7, "top": "navy", '
		+ '"headwear_colour": {"rgb": "112233"}, "legs": {"rgb": "ZZ"}}}}'
	)
	var path := _save_path(file)
	var studio := await _studio(path)
	_check(_texts(studio).has("7 (not readable here)"), "the skin row shows the raw value: %s" % [_texts(studio)])
	_check(_texts(studio).has('{"rgb":"ZZ"} (not readable here)'), "and the legs row")
	await _key(KEY_ENTER)
	_check(_status(studio).begins_with("SAVED"), "a save: " + _status(studio))
	_eq(ArtFamily.whole(_dict(_dict(_read(path), "looks"), "claude").get("skin")), 7, "writes the skin value back")
	await _key(KEY_RIGHT)
	await _key(KEY_LEFT)
	_check(_texts(studio).has("7 (not readable here)"), "→ ← returns to it")
	await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.LEGS)].get_center())
	await _click_design(_rects(studio, "back_rects")[_row(AvatarLook.LEGS)].get_center())
	await _key(KEY_ENTER)
	var claude := _dict(_dict(_read(path), "looks"), "claude")
	_eq(ArtFamily.whole(claude.get("skin")), 7, "stepping off and back keeps the skin value")
	_eq(claude.get("legs"), {"rgb": "ZZ"}, "and the legs value")
	_eq(claude.get("top"), "navy", "and the rest")
	await _click_design(_rects(studio, "slot_rects")[_row(AvatarLook.SKIN)].get_center())
	await _key(KEY_0)
	await _key(KEY_ENTER)
	_check(not _dict(_dict(_read(path), "looks"), "claude").has("skin"), "0 on the row removes it")
	_check(_status(studio).contains("skin 7 (not readable here) removed"), "and the status says so: " + _status(studio))
	_eq(_dict(_dict(_read(path), "looks"), "claude").get("legs"), {"rgb": "ZZ"}, "nothing else goes with it")


## When the save would lose or hide something, the studio shows why instead of
## SAVED, and the file is untouched: an entry in another format, a
## provider past the provider cap.
func test_a_refused_save_says_why_instead_of_saved() -> void:
	var other := '{"schema_version": 2, "looks": {"claude": "future-format"}}'
	var looks := {}
	for index in AgentCatalog.MAX_PROVIDERS + 44:
		looks["agent-%d" % index] = {"top": "cream"}
	var crowded := JSON.stringify({"schema_version": 2, "looks": looks}, "", false)
	var expected: Dictionary[String, String] = {
		other: "format this build doesn't read", crowded: "too many saved providers"
	}
	for text: String in expected:
		var path := _save_path(text)
		var studio := await _studio(path)
		await _click_design(_rects(studio, "next_rects")[_row(AvatarLook.TOP)].get_center())
		await _key(KEY_ENTER)
		_check(not _status(studio).begins_with("SAVED"), "not SAVED: " + _status(studio))
		_check(_status(studio).contains(expected[text]), "the status says why: " + _status(studio))
		_eq(FileAccess.get_file_as_string(path), text, "the file is untouched")
		studio.free()


## The studio has read the file; another
## writer (a newer Herdstead) replaces it; ] → Enter must not write over it, and
## never says SAVED.
func test_a_file_changed_since_the_studio_read_it_is_not_saved() -> void:
	var path := _save_path('{"schema_version": 2, "looks": {"claude": {"top": "navy"}}}')
	var studio := await _studio(path)
	var newer := '{"schema_version": 3, "looks": {"claude": {"top": "navy"}}, "cape": {"v": 3}}'
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(newer)
	file.close()
	await _key(KEY_BRACKETRIGHT)
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	_check(not _status(studio).begins_with("SAVED"), "not SAVED: " + _status(studio))
	_check(_status(studio).contains("changed on disk"), "the status says why: " + _status(studio))
	_eq(FileAccess.get_file_as_string(path), newer, "the newer file is exactly as it was")
