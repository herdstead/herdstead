extends "res://tools/test_base.gd"
## Headless tests for the pixel people: PixelPeople (the manifest read into
## typed fields, bad manifests refused, the built sheets as imported, the look
## resolved slot by slot and the per-pane variation, the one shared animation
## library), AgentCatalog's saved looks (v2, the v1 migration, a damaged or
## newer file, the atomic write), the PixelPerson prefab (node ids kept, six
## layers in step, pause across states, the mirrored side, sit and stand) and
## the standalone showroom through real input.
## Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_pixel_people.gd -- --work=<tmp dir>

const PERSON_SCENE := preload("res://scenes/people/pixel_person.tscn")
const SHOWROOM_SCENE := preload("res://scenes/people_showroom.tscn")
## Big enough that every showroom control is inside the window.
const SCREEN := Vector2i(1920, 960)
## A moment inside a frame, past its key and short of the next one.
const INSIDE := 0.01
## A pane key as HerdrFleet.pane_key() spells it: machine, U+001F, pane id.
const PANE_P7 := "local\u001fw0:t9:p7"
const PANE_P8 := "local\u001fw0:t9:p8"

var args: Dictionary[String, String] = {}
var people: PixelPeople
## Everything a case put into the tree, freed after it.
var _spawned: Array[Node] = []
var _fixtures := 0
## The directory fixture manifests are written to, next to copies of the sheets.
var _fixture_root := ""
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
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	if people == null:
		print("TEST_HARNESS_ERROR: %s does not load" % PixelPeople.MANIFEST)
		quit(2)
		return
	# Nobody's saved looks: every case starts from the shipped defaults.
	people.agent_catalog = AgentCatalog.new(_save_path())
	_run()


func _run() -> void:
	# The headless root is 64x64 and a control outside it never gets an event:
	# the window only takes a size once the main loop runs.
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "PIXEL PEOPLE TESTS"


func _after_case() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()
	people.agent_catalog = AgentCatalog.new(_save_path())


# --- helpers ----------------------------------------------------------------------


## A look of these slots, in a pose.
func _look(
	chosen: Dictionary[StringName, StringName] = {}, context := AvatarLook.STAND, orientation := AvatarLook.FRONT
) -> AvatarLook:
	var look := AvatarLook.with_slots(chosen)
	look.context = context
	look.orientation = orientation
	return look


## A person in the tree, dressed from `with` (the shipped family by default),
## its player on manual callbacks so a reading is exactly what seek set.
func _person(look: AvatarLook = null, with: PixelPeople = null, manual := true) -> PixelPerson:
	var person: PixelPerson = PERSON_SCENE.instantiate()
	root.add_child(person)
	_spawned.append(person)
	var worn := look if look != null else _look({AvatarLook.HAIR_STYLE: &"short", AvatarLook.GLASSES: &"round"})
	person.configure(with if with != null else people, "codex", worn)
	if manual:
		_player(person).callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return person


func _player(person: Node) -> AnimationPlayer:
	return person.get_node("AnimationPlayer") as AnimationPlayer


func _sprite(person: Node, layer: StringName) -> Sprite2D:
	return person.get_node(PixelPeople.SPRITES[layer]) as Sprite2D


func _sprites(person: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	for layer in PixelPeople.LAYERS:
		found.append(_sprite(person, layer))
	return found


## The instance id of `node` and of everything under it, sorted.
func _ids(node: Node) -> Array[int]:
	var found: Array[int] = [node.get_instance_id()]
	for each in node.find_children("*", "", true, false):
		found.append(each.get_instance_id())
	found.sort()
	return found


## Put the person's player at `at` seconds into what it plays, the way a
## running one would be.
func _seek(person: PixelPerson, at: float) -> void:
	_player(person).seek(at, true)


## A fixture manifest: the shipped one with `change` applied, next to copies of
## the shipped sheets so a valid one loads. `numbers` replaces a quoted
## placeholder with raw JSON number text (JSON has no infinity to write).
func _fixture(change: Callable, numbers: Dictionary[String, String] = {}) -> String:
	if _fixture_root.is_empty():
		_fixture_root = args.work.path_join("pixel_people_fixture")
		DirAccess.make_dir_recursive_absolute(_fixture_root)
		for relative in people.files:
			var target := _fixture_root.path_join(relative)
			var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(PixelPeople.ROOT + relative), target)
			_check(copied == OK, "fixture sheet %s copied" % relative)
	var data := ArtFamily.read_json(PixelPeople.MANIFEST).duplicate(true)
	change.call(data)
	_fixtures += 1
	var path := _fixture_root.path_join("people_fixture_%d.json" % _fixtures)
	var text := JSON.stringify(data)
	for placeholder in numbers:
		text = text.replace('"%s"' % placeholder, numbers[placeholder])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _track_entry(data: Dictionary, track: String) -> Dictionary:
	return _dict(_dict(data, "tracks"), track)


## A fresh saved-looks path under --work for one case.
func _save_path() -> String:
	_saves += 1
	var directory := args.work.path_join("avatars_%d" % _saves)
	DirAccess.make_dir_recursive_absolute(directory)
	return directory.path_join("herdstead_avatars.json")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## A catalog reading `text` as its saved file, and the family resolving from it.
func _catalog_with(text: String) -> AgentCatalog:
	var path := _save_path()
	if not text.is_empty():
		_write(path, text)
	var catalog := AgentCatalog.new(path)
	people.agent_catalog = catalog
	return catalog


# --- real input -------------------------------------------------------------------


func _parsed(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


func _press(at: Vector2, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = at
	event.global_position = at
	event.pressed = down
	return event


## A click in window pixels, pressed and released, the way the platform sends it.
func _click(control: Control) -> void:
	_check(control.is_visible_in_tree(), "%s is on screen to be clicked" % control.name)
	var at := control.get_global_rect().get_center()
	await _parsed(_press(at, true))
	await _parsed(_press(at, false))


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event)
		await process_frame
		await process_frame


## Open an OptionButton by clicking it and pick `value` from its popup with the
## keyboard, then wait for the popup to close.
func _choose(button: OptionButton, value: String) -> void:
	var target := -1
	for index in button.item_count:
		if button.get_item_text(index) == value:
			target = index
	_check(target >= 0, "%s offers %s" % [button.name, value])
	await _click(button)
	var popup := button.get_popup()
	_check(popup.visible, "clicking %s opens its list" % button.name)
	var steps := target - popup.get_focused_item()
	for _step in absi(steps):
		await _key(KEY_DOWN if steps > 0 else KEY_UP)
	await _key(KEY_ENTER)
	await _settle()
	_check(not popup.visible, "the %s list closed" % button.name)
	_eq(button.get_item_text(button.selected), value, "%s shows the choice" % button.name)


func _settle() -> void:
	for _frame in 4:
		await process_frame


## The showroom in the tree, with `options` as its command line (`--key=value`
## each), read by AppArgs as the one on the real command line would be.
func _showroom(options: Dictionary[String, String] = {}) -> Control:
	var line := PackedStringArray()
	for key in options:
		line.append("--%s=%s" % [key, options[key]])
	var showroom: Control = SHOWROOM_SCENE.instantiate()
	showroom.set("args", AppArgs.parse(line))
	showroom.set("people", people)
	root.add_child(showroom)
	_spawned.append(showroom)
	await _settle()
	return showroom


func _node(showroom: Control, unique: String) -> Node:
	return showroom.get_node("%" + unique)


## Every person under a showroom container, in tree order.
func _people_in(container: Node) -> Array[PixelPerson]:
	var found: Array[PixelPerson] = []
	for each in container.find_children("*", "CharacterBody2D", true, false):
		var person := each as PixelPerson
		if person != null:
			found.append(person)
	return found


# --- 1. the family ------------------------------------------------------------------


func test_manifest_reads_into_typed_fields() -> void:
	var data := ArtFamily.read_json(PixelPeople.MANIFEST)
	_eq(people.density, ArtFamily.whole(data.get("density")), "density, as the manifest says")
	_check(PixelPeople.PEOPLE_DENSITIES.has(people.density), "texels per unit: 1 or 2")
	_eq(people.density, 2, "shipped at density 2: a unit is 2x2 texels")
	_eq(people.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the family is sampled nearest")
	_eq(people.unit_scale(), Vector2.ONE / float(people.density), "scaled back to units")
	_eq(people.frame_size, Vector2i(32, 48), "the avatar canvas")
	_eq(people.pivot, Vector2(16, 46), "the feet")
	var every: Array[StringName] = [PixelPeople.FRONT, PixelPeople.BACK, PixelPeople.SIDE]
	_eq(people.facings, every, "facings")
	_eq(people.side_faces, PixelPeople.RIGHT, "the side is drawn facing right")
	_eq(people.tracks.size(), _dict(data, "tracks").size(), "every track is read")
	var total := 0
	for id in people.tracks:
		total += people.tracks[id].frame_count()
	_eq(people.columns, total, "a strip holds every frame of every track")
	var walk := people.tracks[&"walk"]
	_eq(walk.frame_count(), 4, "walk has four frames")
	_check(walk.loop, "walk loops")
	_eq(walk.facings, every, "walk facings")
	var no_back: Array[StringName] = [PixelPeople.FRONT, PixelPeople.SIDE]
	_eq(people.tracks[&"drink"].facings, no_back, "drink facings")
	_eq(walk.start, people.tracks[&"stand_idle"].frame_count(), "tracks follow each other in the strip")
	_eq(
		people.frame_rect(walk.frame(1)),
		Rect2i(Vector2i((walk.start + 1) * 32, 0) * people.density, Vector2i(32, 48) * people.density),
		"frame rect, in texels"
	)
	_eq(people.track(AvatarLook.DESK, &"working"), &"desk_work", "desk working types")
	_eq(people.track(AvatarLook.STAND, &"blocked"), &"stand_blocked", "standing blocked raises a hand")
	_eq(people.slots.keys(), AvatarLook.SLOTS, "every slot, in order")
	var skin := people.slots[AvatarLook.SKIN]
	_check(skin.is_colour() and skin.layer == PixelPeople.BODY and skin.role == &"skin", "skin colours the body")
	_check(skin.swatches.size() >= 4, "at least four skin ramps")
	_eq(skin.ramps[&"fair"][0], Color.html("f5d3b4"), "a swatch's light tone")
	var headwear := people.slots[AvatarLook.HEADWEAR]
	_check(not headwear.is_colour() and headwear.allows_none, "headwear is a shape, and may be none")
	var hides: Array[StringName] = [&"hood"]
	_eq(headwear.hides_hair, hides, "the hood hides the hair")
	_eq(people.slots[AvatarLook.GLASSES].options().back(), AvatarLook.NONE, "none is an option, last")
	_eq(people.default_look.top, &"slate", "the pack's default top")
	var varied: Array = people.variation.keys().map(func(id: StringName) -> String: return str(id))
	varied.sort()
	_eq(varied, ["glasses", "hair_colour", "hair_style", "skin"], "what varies: the face and head")
	_eq(people.keys[&"hat"].size(), 3, "every role's key ramp")
	_check(people.fixed.has(&"ink") and people.fixed.has(&"lens"), "the fixed colours")
	_check(people.fixed.has(&"catchlight"), "every eye's catchlight colour")
	_eq(people.strips.size(), 47, "one strip per layer shape and swatch")
	var sheets := PackedStringArray(["front.png", "back.png", "side.png"])
	_eq(people.files, sheets, "one sheet per facing")
	_eq(people.mock_files.size(), _list(data, "mock_files").size(), "mock files")
	_check(people.is_mock("front/legs.png"), "the legs are the rig's own: always a placeholder")
	_check(not people.is_mock("front/top.png"), "the front top wears a torso skin: no longer a placeholder")


func test_bad_manifests_are_refused() -> void:
	var drop_layer := func(data: Dictionary) -> void: data["layers"] = ["body", "hair"]
	var out_of_range := func(data: Dictionary) -> void:
		_track_entry(data, "drink")["start"] = int(_number(data, "columns")) - 1
	var infinite := func(data: Dictionary) -> void:
		_track_entry(data, "walk")["durations"] = [0.1, "INFINITE", 0.1, 0.1]
	var zero := func(data: Dictionary) -> void: _track_entry(data, "walk")["durations"] = [0.1, 0.0, 0.1, 0.1]
	var text := func(data: Dictionary) -> void: _track_entry(data, "walk")["durations"] = [0.1, "0.2", 0.1, 0.1]
	var unknown_facing := func(data: Dictionary) -> void: _track_entry(data, "walk")["facings"] = ["front", "up"]
	var undeclared := func(data: Dictionary) -> void: data["facings"] = ["front", "back", "up"]
	var missing_track := func(data: Dictionary) -> void:
		_dict(_dict(data, "state_tracks"), "desk")["working"] = "desk_typo"
	var unmapped := func(data: Dictionary) -> void: _dict(_dict(data, "state_tracks"), "stand").erase("starting")
	var off_centre := func(data: Dictionary) -> void: data["pivot"] = [15, 46]
	# The sheets are drawn at the shipped density: the other one does not fit them.
	var unfit := 2 if people.density == 1 else 1
	var misfit := func(data: Dictionary) -> void: data["density"] = unfit
	var dense := func(data: Dictionary) -> void: data["density"] = 4
	var extra := func(data: Dictionary) -> void: data["shadow"] = true
	var old_schema := func(data: Dictionary) -> void: data["schema_version"] = 1
	var no_strip := func(data: Dictionary) -> void: _list(data, "strips").erase("hair_long_grey")
	var stray_strip := func(data: Dictionary) -> void: _list(data, "strips").append("hair_mohawk_grey")
	var no_sheet := func(data: Dictionary) -> void: _list(data, "files").erase("side.png")
	var no_front := func(data: Dictionary) -> void: _track_entry(data, "walk")["facings"] = ["side", "front"]
	var no_slot := func(data: Dictionary) -> void: _dict(data, "slots").erase("glasses")
	var undrawn_default := func(data: Dictionary) -> void: _dict(data, "default_look")["top"] = "sequins"
	var undrawn_pool := func(data: Dictionary) -> void: _dict(data, "variation")["skin"] = ["green"]
	var bad_ramp := func(data: Dictionary) -> void:
		_dict(_dict(_dict(data, "slots"), "top"), "swatches")["teal"] = ["5fb6b0", "3e8f8c"]
	var cases: Dictionary[String, Callable] = {
		"a missing layer": drop_layer,
		"a frame out of range": out_of_range,
		"a non-finite duration": infinite,
		"a zero duration": zero,
		"a duration that is text": text,
		"an unknown facing": unknown_facing,
		"a facing no strip is drawn for": undeclared,
		"state_tracks naming a missing track": missing_track,
		"a state with no track": unmapped,
		"a pivot off the frame's centre": off_centre,
		"a density the sheets are not drawn at": misfit,
		"density 4, which the family never ships": dense,
		"an unknown field": extra,
		"schema 1": old_schema,
		"a look with no strip": no_strip,
		"a strip no look shows": stray_strip,
		"a facing with no sheet": no_sheet,
		"a track that does not start with its front": no_front,
		"a missing slot": no_slot,
		"a default the slot does not draw": undrawn_default,
		"a variation the slot does not draw": undrawn_pool,
		"a ramp of two": bad_ramp,
	}
	for label in cases:
		_eq(PixelPeople.from_manifest(_fixture(cases[label], {"INFINITE": "1e999"})), null, "refused: " + label)
	var unchanged := func(_data: Dictionary) -> void: pass
	_check(PixelPeople.from_manifest(_fixture(unchanged)) != null, "the shipped manifest, copied, still loads")


## The built-sheet check the packing rests on (measured, not inferred): every
## strip's region of every imported sheet is the builder's own strip in its PNG,
## pixel for pixel wherever it is opaque, and transparent exactly where it is.
func test_every_imported_region_is_the_builder_s_strip() -> void:
	var width := people.columns * people.frame_size.x * people.density
	var height := people.frame_size.y * people.density
	for sheet in people.files:
		var built := Image.load_from_file(ProjectSettings.globalize_path(PixelPeople.ROOT + sheet))
		built.convert(Image.FORMAT_RGBA8)
		var strip_facing := StringName(sheet.get_basename())
		for row in people.strips.size():
			var name := people.strips[row]
			var region := people.strip_texture(strip_facing, name)
			_check(region is AtlasTexture, "%s %s is a region of the sheet" % [sheet, name])
			if region == null:
				continue
			var imported := region.get_image()
			imported.convert(Image.FORMAT_RGBA8)
			var expected := built.get_region(Rect2i(0, row * height, width, height))
			var differ := 0
			for y in expected.get_height():
				for x in expected.get_width():
					var want := expected.get_pixel(x, y)
					var got := imported.get_pixel(x, y)
					if want.a8 != got.a8 or (want.a8 != 0 and want.to_rgba32() != got.to_rgba32()):
						differ += 1
			_eq(differ, 0, "%s %s: the imported region is the built strip" % [sheet, name])


func test_every_semantic_animation_resolves_in_both_contexts() -> void:
	var semantics: Array[StringName] = []
	semantics.assign(ArtContract.ANIMATIONS)
	semantics.append_array([ArtContract.STATE_DONE, ArtContract.STATE_UNKNOWN])
	for context in AvatarLook.CONTEXTS:
		for semantic in semantics:
			var id := people.track(context, semantic)
			_check(people.tracks.has(id), "%s/%s maps to %s, a track" % [context, semantic, id])
			if people.tracks.has(id):
				_check(people.tracks[id].facings.has(PixelPeople.FRONT), "%s draws the front" % id)
	for semantic in ArtContract.ANIMATIONS:
		var seated := people.tracks[people.track(AvatarLook.DESK, semantic)]
		_check(seated.facings.has(PixelPeople.BACK), "a seated %s is drawn from behind, for the near side" % semantic)


func test_the_family_is_not_a_theme() -> void:
	_check(
		not FileAccess.file_exists(PixelPeople.ROOT + "manifest.json"),
		"no assets/pixel_people/manifest.json to be taken for a theme"
	)
	_check(FileAccess.file_exists(PixelPeople.MANIFEST), "the family's manifest is people_manifest.json")


## Every option of every slot shows on its layer, a strip of every frame of
## every track; `none` and a hidden layer show nothing.
func test_every_option_has_a_strip_per_facing() -> void:
	var expected := Vector2(people.columns * people.frame_size.x, people.frame_size.y) * people.density
	for slot_id in AvatarLook.SLOTS:
		var slot := people.slots[slot_id]
		for option in slot.options():
			var look := people.default_look.clothes()
			# A colour is worn on a shape: headwear colours on a cap.
			look.headwear = &"cap"
			look.set_slot(slot_id, option)
			for strip_facing in people.facings:
				var strip := people.layer_texture(slot.layer, look, strip_facing)
				if option == AvatarLook.NONE:
					_eq(strip, null, "%s none draws nothing on %s" % [slot_id, slot.layer])
					continue
				_check(strip != null, "%s %s %s has a strip" % [slot_id, option, strip_facing])
				if strip != null:
					_eq(strip.get_size(), expected, "%s %s %s strip size" % [slot_id, option, strip_facing])
	var hooded := _look(
		{AvatarLook.HEADWEAR: &"hood", AvatarLook.HEADWEAR_COLOUR: &"lilac", AvatarLook.HAIR_STYLE: &"curl"}
	)
	hooded.override_with(_look())
	var worn := people.default_look.clothes()
	worn.override_with(hooded)
	_eq(people.strip_name(PixelPeople.HAIR, worn), "", "a hood hides the hair")
	_eq(people.strip_name(PixelPeople.HEADWEAR, worn), "headwear_hood_lilac", "the hood in its own colour")
	worn.headwear = &"cap"
	_eq(people.strip_name(PixelPeople.HAIR, worn), "hair_curl_brown", "under a cap the hair shows")
	worn.top = &"sequins"
	_eq(people.strip_name(PixelPeople.TOP, worn), "", "no strip for an option the family does not draw")
	_eq(people.strip_name(PixelPeople.BODY, worn), "body_fair", "the body is the skin's")


func test_dress_scales_the_family_s_texels_back_to_units() -> void:
	var sprite := Sprite2D.new()
	people.dress(sprite, people.layer_texture(PixelPeople.BODY, people.default_look, &"front"), people.pivot)
	_eq(sprite.scale, Vector2.ONE / float(people.density), "a texel is 1/density of a unit")
	_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "nearest")
	_eq(sprite.offset, -people.pivot * people.density, "the origin is the feet (offset is in texels)")
	_check(not sprite.centered, "not centred")
	sprite.free()


## The same family at the other density (its sheets scaled by NEAREST, the way
## the builder's white model is) lays a person out on the same units: only the
## texels are finer. Density is the family's business, never the office's.
func test_a_density_two_family_lays_out_like_density_one() -> void:
	var other := 2 if people.density == 1 else 1
	var directory := args.work.path_join("pixel_people_density_%d" % other)
	DirAccess.make_dir_recursive_absolute(directory)
	for relative in people.files:
		var sheet := Image.load_from_file(ProjectSettings.globalize_path(PixelPeople.ROOT + relative))
		var size := sheet.get_size() * other / people.density
		sheet.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		_eq(sheet.save_png(directory.path_join(relative)), OK, "%s at density %d written" % [relative, other])
	var data := ArtFamily.read_json(PixelPeople.MANIFEST).duplicate(true)
	data["density"] = other
	var path := directory.path_join("people_manifest.json")
	_write(path, JSON.stringify(data))
	var twin := PixelPeople.from_manifest(path)
	_check(twin != null, "the family loads at density %d" % other)
	if twin == null:
		return
	var one := people if people.density == 1 else twin
	var two := twin if people.density == 1 else people
	_eq([one.density, two.density], [1, 2], "one family at each density")
	_eq(PixelPerson.drawing_rect(two), PixelPerson.drawing_rect(one), "the same drawing rect, in units")
	for index in one.columns:
		var rect := one.frame_rect(index)
		_eq(two.frame_rect(index), Rect2i(rect.position * 2, rect.size * 2), "frame %d: twice the texels" % index)
	var look := _look({AvatarLook.HAIR_STYLE: &"short", AvatarLook.GLASSES: &"round"})
	var fine := _person(look, two)
	var coarse := _person(look, one)
	fine.play_track(&"walk")
	coarse.play_track(&"walk")
	for layer in PixelPeople.LAYERS:
		var a := _sprite(coarse, layer)
		var b := _sprite(fine, layer)
		_eq(b.texture.get_size(), a.texture.get_size() * 2, "%s: the strip holds twice the texels" % layer)
		_eq(b.scale, a.scale / 2.0, "%s: and is scaled back twice as far" % layer)
		var placed_a := Rect2(a.get_rect().position * a.scale, a.get_rect().size * a.scale)
		var placed_b := Rect2(b.get_rect().position * b.scale, b.get_rect().size * b.scale)
		_eq(placed_b, placed_a, "%s: one frame covers the same units, on the same feet" % layer)


func test_the_library_keys_every_layer_in_every_animation() -> void:
	var library := people.animation_library()
	_check(library == people.animation_library(), "the library is built once and shared")
	_eq(library.get_animation_list().size(), people.tracks.size(), "an animation per track")
	for id in people.tracks:
		var entry := people.tracks[id]
		_check(library.has_animation(id), "%s is an animation" % id)
		if not library.has_animation(id):
			continue
		var animation := library.get_animation(id)
		_eq(animation.get_track_count(), PixelPeople.LAYERS.size(), "%s keys every layer, nothing else" % id)
		_check(is_equal_approx(animation.length, entry.length()), "%s lasts its durations" % id)
		_eq(animation.loop_mode, Animation.LOOP_LINEAR if entry.loop else Animation.LOOP_NONE, "%s loop" % id)
		for layer in PixelPeople.LAYERS:
			var channel := animation.find_track(NodePath("%s:frame" % PixelPeople.SPRITES[layer]), Animation.TYPE_VALUE)
			_check(channel >= 0, "%s keys %s's frame" % [id, layer])
			if channel < 0:
				continue
			_eq(
				animation.value_track_get_update_mode(channel),
				Animation.UPDATE_DISCRETE,
				"%s %s is discrete" % [id, layer]
			)
			_eq(animation.track_get_key_count(channel), entry.frame_count(), "%s %s: a key per frame" % [id, layer])
			for index in entry.frame_count():
				_check(
					is_equal_approx(animation.track_get_key_time(channel, index), entry.starts_at(index)),
					"%s %s key %d time" % [id, layer, index]
				)
				_eq(
					animation.track_get_key_value(channel, index),
					entry.frame(index),
					"%s %s key %d" % [id, layer, index]
				)


# --- 2. the look, slot by slot ------------------------------------------------------


## Each level of the chain overrides the one before, per slot: the pack's
## default, then the provider's, then the user's pin, then the caller's.
func test_each_level_overrides_the_one_before() -> void:
	_catalog_with('{"schema_version": 2, "looks": {"codex": {"top": "lilac"}}}')
	var generic := people.look_for("no-such-agent")
	_eq(generic.badge, AgentCatalog.FALLBACK_ID, "an unknown provider wears the generic badge")
	for slot_id in AvatarLook.SLOTS:
		_eq(generic.slot(slot_id), people.default_look.slot(slot_id), "1. pack default: %s" % slot_id)
	var codex := people.look_for("codex")
	_eq([codex.headwear, codex.headwear_colour, codex.legs], [&"cap", &"sea", &"denim"], "2. the provider's default")
	_eq(codex.top, &"lilac", "3. the user's pin wins over the provider's teal")
	_eq(codex.pinned, [AvatarLook.TOP] as Array[StringName], "and says it is pinned")
	_eq(codex.skin, people.default_look.skin, "an unpinned, unvaried slot keeps the pack's default")
	var asked := people.look_for("codex", _look({AvatarLook.TOP: &"cream", AvatarLook.GLASSES: &"round"}))
	_eq([asked.top, asked.glasses], [&"cream", &"round"], "4. the caller's choice wins over the pin")
	var posed := people.look_for("codex", AvatarLook.facing(&"floating", &"sideways"))
	_eq([posed.context, posed.orientation], [AvatarLook.STAND, AvatarLook.FRONT], "an unknown pose falls back")
	var odd := people.look_for("codex", _look({AvatarLook.TOP: &"sequins"}))
	_eq(odd.top, &"lilac", "an option the family does not draw is skipped, and the level before stands")


## The pane's variation, pinned to values computed outside Godot (Python's
## hashlib, SHA-256 of "herdstead.look/1␟provider␟pane␟slot"): the same on every
## run, in every process, on every platform.
func test_variation_is_fixed_by_provider_and_pane() -> void:
	_eq(PixelPeople.pick("claude", PANE_P7, AvatarLook.SKIN), 1107191239, "the hash itself")
	_eq(PixelPeople.pick("claude", PANE_P7, AvatarLook.HAIR_STYLE), 2977282868, "one per slot")
	# Glasses are 1 in 6 (the pool: ten none, round, square); p2 draws a pair.
	var expected: Dictionary[String, Array] = {
		"claude|p7": [&"deep", &"long", &"brown", &"none"],
		"claude|p8": [&"porcelain", &"long", &"umber", &"none"],
		"codex|p7": [&"deep", &"short", &"black", &"none"],
		"claude|p2": [&"deep", &"long", &"black", &"square"],
	}
	var panes: Dictionary[String, String] = {"p7": PANE_P7, "p8": PANE_P8, "p2": "local\u001fw0:t9:p2"}
	for case in expected:
		var parts := case.split("|")
		var look := people.look_for(parts[0], null, panes[parts[1]])
		_eq(
			[look.skin, look.hair_style, look.hair_colour, look.glasses],
			expected[case],
			"%s: skin, hair style, hair colour, glasses" % case
		)
	var again := people.look_for("claude", null, PANE_P7)
	_eq(again.key(), people.look_for("claude", null, PANE_P7).key(), "asked twice, the same person")
	_eq(people.look_for("claude").hair_style, people.default_look.hair_style, "no key: no variation")
	var clothed := people.look_for("claude", null, PANE_P7)
	_eq([clothed.top, clothed.legs], [&"terra", &"taupe"], "clothes are the provider's, never varied")


func test_a_pinned_slot_stops_varying() -> void:
	_catalog_with('{"schema_version": 2, "looks": {"claude": {"skin": "fair", "hair_style": "short"}}}')
	for pane: String in [PANE_P7, PANE_P8]:
		var look := people.look_for("claude", null, pane)
		_eq([look.skin, look.hair_style], [&"fair", &"short"], "pinned slots are the pin on every pane")
	_eq(people.look_for("claude", null, PANE_P8).hair_colour, &"umber", "an unpinned slot still varies")


func test_a_provider_change_is_a_new_draw() -> void:
	var person := _person()
	person.vary_by(PANE_P7)
	person.configure(people, "claude")
	_eq([person.look.hair_style, person.look.glasses], [&"long", &"none"], "claude at p7")
	var before := _ids(person)
	person.configure(people, "codex")
	_eq(
		[person.look.hair_style, person.look.hair_colour],
		[&"short", &"black"],
		"codex at the same pane is someone else"
	)
	_eq([person.look.top, person.look.headwear], [&"teal", &"cap"], "in codex's clothes")
	_eq(_ids(person), before, "the same nodes, re-dressed")


## Nothing live reaches the look: every state, both contexts, facings, pause
## and a stale tint leave the person exactly as they were dressed.
func test_variation_never_depends_on_state() -> void:
	var person := _person()
	person.vary_by(PANE_P8)
	person.configure(people, "claude")
	var dressed := person.look.clothes().key()
	var textures: Array[Texture2D] = []
	for sprite in _sprites(person):
		textures.append(sprite.texture)
	var seat := Marker2D.new()
	root.add_child(seat)
	_spawned.append(seat)
	for semantic in ArtContract.ANIMATIONS:
		person.play_state(semantic)
		person.sit(seat)
		person.play_state(semantic)
		person.stand_up()
		_eq(person.look.clothes().key(), dressed, "%s, seated and standing: the same clothes" % semantic)
	person.pause()
	person.modulate = Color(0.5, 0.5, 0.5)
	person.face(PixelPeople.FRONT)
	for index in PixelPeople.LAYERS.size():
		_eq(_sprites(person)[index].texture, textures[index], "%s: the same strip" % PixelPeople.LAYERS[index])


func test_none_and_a_hood_draw_nothing_on_their_layer() -> void:
	var person := _person(_look({AvatarLook.GLASSES: &"none", AvatarLook.HEADWEAR: &"hood"}))
	_eq(_sprite(person, PixelPeople.GLASSES).texture, null, "no glasses: no texture, no draw call")
	_eq(_sprite(person, PixelPeople.HAIR).texture, null, "under a hood the hair is not drawn")
	_check(_sprite(person, PixelPeople.HEADWEAR).texture != null, "the hood is")
	for layer: StringName in [PixelPeople.GLASSES, PixelPeople.HAIR]:
		var empty := _sprite(person, layer)
		_eq(
			[empty.texture_filter, empty.scale, empty.offset],
			[CanvasItem.TEXTURE_FILTER_NEAREST, Vector2.ONE / float(people.density), -people.pivot * people.density],
			"an empty %s layer is still dressed the family's way, ready for a look that fills it" % layer
		)
	person.configure(people, "codex", _look({AvatarLook.HEADWEAR: &"cap", AvatarLook.GLASSES: &"square"}))
	_check(_sprite(person, PixelPeople.HAIR).texture != null, "under a cap the hair shows again")
	_check(_sprite(person, PixelPeople.GLASSES).texture != null, "and the glasses are on")
	person.play_track(&"walk")
	_seek(person, people.tracks[&"walk"].starts_at(2) + INSIDE)
	for sprite in _sprites(person):
		_eq(sprite.frame, people.tracks[&"walk"].frame(2), "%s is on the frame the one key set" % sprite.name)


# --- 3. the saved looks --------------------------------------------------------------


func test_a_save_is_schema_2_with_only_the_pins() -> void:
	var catalog := _catalog_with("")
	_eq(catalog.state, AgentCatalog.FileState.ABSENT, "no file yet")
	var chosen := _look({AvatarLook.HAIR_STYLE: &"curl", AvatarLook.TOP: &"cream"}, AvatarLook.DESK, AvatarLook.BACK)
	_eq(catalog.save_look("claude", chosen), OK, "saved")
	var saved := _read(catalog.path)
	_eq(ArtFamily.whole(saved.get("schema_version")), 2, "schema 2")
	_eq(saved.get("looks"), {"claude": {"hair_style": "curl", "top": "cream"}}, "only the pinned slots, and no pose")
	_check(not FileAccess.file_exists(catalog.path + ".tmp"), "no temporary file is left")
	var reread := AgentCatalog.new(catalog.path)
	_eq(reread.pins("claude").pinned, [AvatarLook.HAIR_STYLE, AvatarLook.TOP] as Array[StringName], "read back")
	_eq(reread.save_look("claude", AvatarLook.new()), OK, "unpinning everything")
	_eq(_read(catalog.path).get("looks"), {}, "leaves nobody")


func test_a_v1_file_migrates_and_is_kept_at_the_first_save() -> void:
	var v1 := '{"claude": {"hair": "hood", "outfit": "teal"}, "codex": {"hair": "curl", "outfit": "slate"}}'
	var catalog := _catalog_with(v1)
	_eq(catalog.state, AgentCatalog.FileState.MIGRATED, "an unversioned file is v1")
	_eq(FileAccess.get_file_as_string(catalog.path), v1, "reading never writes")
	var claude := catalog.pins("claude")
	_eq(
		[claude.headwear, claude.headwear_colour, claude.top, claude.legs, claude.hair_style],
		[&"hood", &"teal", &"teal", &"denim", &"short"],
		"the hood keeps the outfit's colour, the outfit becomes a top and legs"
	)
	_eq(claude.skin, &"", "skin was never chosen in v1: it varies")
	var codex := people.look_for("codex", null, PANE_P7)
	_eq([codex.hair_style, codex.hair_colour, codex.headwear], [&"curl", &"auburn", &"none"], "codex's v1 curl")
	_eq(catalog.save_look("pi", _look({AvatarLook.GLASSES: &"round"})), OK, "the first save")
	_check(catalog.note.contains(".v1.json"), "says where the old file went: " + catalog.note)
	var backup := catalog.path.get_basename() + ".v1.json"
	_eq(FileAccess.get_file_as_string(backup), v1, "the v1 file, kept")
	var looks := _dict(_read(catalog.path), "looks")
	_eq(looks.size(), 3, "claude and codex migrated, pi added")
	_eq(_dict(looks, "codex").get("hair_style"), "curl", "migrated values written as v2")


func test_every_v1_value_migrates_to_a_drawn_option() -> void:
	for hair: StringName in [&"short", &"curl", &"cap", &"hood"]:
		for outfit: StringName in [&"slate", &"cream", &"terra", &"teal", &"lilac"]:
			var slots := AgentCatalog.migrate_v1(hair, outfit)
			_check(
				slots.has(AvatarLook.TOP) and slots.has(AvatarLook.HAIR_STYLE),
				"%s/%s pins clothes and hair" % [hair, outfit]
			)
			for slot_id in slots:
				_check(
					people.slots[slot_id].has_option(slots[slot_id]),
					"%s/%s -> %s %s, which the family draws" % [hair, outfit, slot_id, slots[slot_id]]
				)
	_eq(
		AgentCatalog.migrate_v1(&"mohawk", &"sequins"), {} as Dictionary[StringName, StringName], "unknown pins nothing"
	)


func test_unknown_ids_fall_back_per_slot_and_are_kept() -> void:
	var text := (
		'{"schema_version": 2, "looks": {"claude": {"top": "sequins", "legs": "plum", "beard": "full", '
		+ '"headwear_colour": {"rgb": "12ab34"}, "skin": 7, "glasses": {"rgb": "zz"}}}}'
	)
	var catalog := _catalog_with(text)
	_eq(catalog.state, AgentCatalog.FileState.READ, "read")
	var look := people.look_for("claude", null, PANE_P7)
	_eq(look.legs, &"plum", "a drawn pin is worn")
	_eq(look.top, &"terra", "an undrawn one falls back to the provider's")
	_eq(look.headwear_colour, people.default_look.headwear_colour, "a picked colour is not drawn yet")
	_eq(look.skin, &"deep", "an unreadable value leaves the slot varying")
	_eq(
		catalog.saved_colours("claude"),
		{AvatarLook.HEADWEAR_COLOUR: "12ab34"} as Dictionary[StringName, String],
		"rgb read"
	)
	var only_legs: Array[StringName] = [AvatarLook.LEGS]
	_eq(catalog.save_look("claude", _look({AvatarLook.LEGS: &"denim"}), only_legs), OK, "saved over it")
	var written: Dictionary = _dict(_dict(_read(catalog.path), "looks"), "claude")
	_eq(written.get("legs"), "denim", "the new pin")
	# A save writes back everything it did not change, readable here or not.
	_eq(written.get("beard"), "full", "an unknown slot is written back")
	_eq(written.get("headwear_colour"), {"rgb": "12ab34"}, "and a picked colour")
	_eq(written.get("top"), "sequins", "and an id this build does not draw")
	_eq(ArtFamily.whole(written.get("skin")), 7, "and a value it cannot read")
	_eq(written.get("glasses"), {"rgb": "zz"}, "and a colour it cannot read")


## Probe B: an id with a hyphen is saved, read back and survives another
## provider's save. One id rule, the same for reading and writing.
func test_ids_with_hyphens_round_trip() -> void:
	var catalog := _catalog_with("")
	_eq(catalog.save_look("claude-code", _look({AvatarLook.TOP: &"cream"})), OK, "claude-code saves")
	var reread := AgentCatalog.new(catalog.path)
	_eq(reread.pins("claude-code").top, &"cream", "and reads back")
	_eq(reread.save_look("claude", _look({AvatarLook.TOP: &"lilac"})), OK, "another provider saves")
	_eq(_dict(_dict(_read(catalog.path), "looks"), "claude-code").get("top"), "cream", "claude-code is still there")
	_eq(AgentCatalog.valid_id("gemini-cli"), &"gemini-cli", "hyphens are ids")
	for bad: String in ["Claude", "-lead", "a b", "", "x".repeat(65), "é"]:
		_eq(AgentCatalog.valid_id(bad), &"", "%s is not an id" % bad)
	_check(reread.save_look("Bad Id", _look({AvatarLook.TOP: &"cream"})) != OK, "an id the reader would not keep")
	_check(reread.note.contains("not an id"), "is refused, and the note says so: " + reread.note)
	_check(not _dict(_read(catalog.path), "looks").has("Bad Id"), "nothing was written for it")


## A save of one provider writes back every
## other provider, and every entry it cannot read, exactly as they were.
func test_a_save_keeps_what_it_cannot_read() -> void:
	var text := (
		'{"schema_version": 2, "presets": [1, 2], "looks": {"claude": {"top": "navy-blue", "legs": "plum"}, '
		+ '"Bad Id!": {"top": "cream"}, "codex": "not an object", "kimi": {"top": "Navy Blue", "legs": {"hex": 1}}}}'
	)
	var catalog := _catalog_with(text)
	_eq(catalog.state, AgentCatalog.FileState.READ, "read")
	_eq(catalog.pins("claude").top, &"navy-blue", "an id with a hyphen is read")
	_eq(catalog.save_look("pi", _look({AvatarLook.GLASSES: &"round"})), OK, "pi saves")
	var saved := _read(catalog.path)
	var parsed: Dictionary = JSON.parse_string(text)
	var before := _dict(parsed, "looks")
	var looks := _dict(saved, "looks")
	for provider: String in ["claude", "Bad Id!", "codex", "kimi"]:
		_eq(looks.get(provider), before.get(provider), "%s is written back as it was" % provider)
	# In the file's own bytes: whole numbers stay whole (never [1.0, 2.0]).
	_check(
		FileAccess.get_file_as_string(catalog.path).contains('"presets":[1,2]'), "and a key this build does not know"
	)
	_eq(_dict(looks, "pi"), {"glasses": "round"}, "with pi's save")


## Past the count caps, entries are not read into looks, and still go back to disk.
func test_entries_past_the_caps_are_kept() -> void:
	var slots := {}
	for index in AgentCatalog.MAX_SLOTS + 8:
		slots["extra-%d" % index] = "x"
	slots["top"] = "lilac"
	var looks := {"claude": slots}
	for index in AgentCatalog.MAX_PROVIDERS + 4:
		looks["agent-%d" % index] = {"top": "cream"}
	# Unsorted: claude first, then the providers past the cap.
	var catalog := _catalog_with(JSON.stringify({"schema_version": 2, "looks": looks}, "", false))
	_eq(catalog.pins("claude").top, &"lilac", "a known slot is read before unknown ones fill the cap")
	# A new provider would land past the cap, unread: refused, never saved unread and called SAVED.
	_check(catalog.save_look("pi", _look({AvatarLook.TOP: &"teal"})) != OK, "a provider past the cap is not saved")
	_check(catalog.note.contains("too many saved providers"), "and the note says why: " + catalog.note)
	# A new known slot is read first, and would push slots read before past the slot cap: refused.
	var only_legs: Array[StringName] = [AvatarLook.LEGS]
	_check(catalog.save_look("claude", _look({AvatarLook.LEGS: &"plum"}), only_legs) != OK, "a slot past the cap")
	_check(catalog.note.contains("check: readable before"), "is not hidden by a save: " + catalog.note)
	var only_top: Array[StringName] = [AvatarLook.TOP]
	_eq(catalog.save_look("claude", _look({AvatarLook.TOP: &"teal"}), only_top), OK, "a readable slot changes")
	var written := _dict(_read(catalog.path), "looks")
	_eq(written.size(), looks.size(), "every provider past the cap is still in the file")
	_eq(_dict(written, "claude").size(), slots.size(), "and every slot past the cap")
	# A save keeps the file's order, so the providers read on the next start are the same ones.
	var again := AgentCatalog.new(catalog.path)
	_eq(again.pins("claude").top, &"teal", "claude is still read after a save: the keys were not re-sorted")
	_eq(str(written.keys()[0]), "claude", "the file's first provider is still first")


func test_a_non_utf8_file_is_damaged() -> void:
	var path := _save_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer('{"schema_version": 2, "looks": {"cl'.to_utf8_buffer())
	file.store_buffer(PackedByteArray([0xE9, 0x4E]))
	file.store_buffer('": {"top": "cream"}}}'.to_utf8_buffer())
	file.close()
	var catalog := AgentCatalog.new(path)
	people.agent_catalog = catalog
	_eq(catalog.state, AgentCatalog.FileState.DAMAGED, "a byte that is not UTF-8 makes the file damaged")
	_check(catalog.problem.contains("UTF-8"), "and says why: " + catalog.problem)
	_eq(catalog.save_look("claude", _look({AvatarLook.TOP: &"cream"})), OK, "a save")
	_check(catalog.note.contains("damaged-"), "keeps it aside and says where: " + catalog.note)


## Probes E and E2: a v1 backup already there, or a directory in the way, is
## never replaced; the backup takes the next free name.
func test_the_v1_backup_takes_a_free_name() -> void:
	var v1 := '{"claude": {"hair": "curl", "outfit": "teal"}, "pi": {"hair": "mohawk", "outfit": "sequins"}}'
	var catalog := _catalog_with(v1)
	var first := catalog.path.get_basename() + ".v1.json"
	_write(first, "an earlier backup")
	DirAccess.make_dir_absolute(catalog.path.get_basename() + ".v1-2.json")
	_eq(catalog.save_look("codex", _look({AvatarLook.TOP: &"cream"})), OK, "saved")
	var third := catalog.path.get_basename() + ".v1-3.json"
	_eq(FileAccess.get_file_as_string(third), v1, "the v1 file is kept under the next free name, past a directory")
	_eq(FileAccess.get_file_as_string(first), "an earlier backup", "the earlier backup is untouched")
	_check(catalog.note.contains(third.get_file()), "and the note says where: " + catalog.note)


## When the v1 file cannot be kept, nothing is written over it.
func test_a_v1_file_is_never_overwritten_without_its_backup() -> void:
	var v1 := '{"claude": {"hair": "curl", "outfit": "teal"}}'
	var catalog := _catalog_with(v1)
	var directory := ProjectSettings.globalize_path(catalog.path.get_base_dir())
	# A folder nothing can be created in: the backup cannot be made.
	OS.execute("chmod", PackedStringArray(["a-w", directory]))
	var result := catalog.save_look("codex", _look({AvatarLook.TOP: &"cream"}))
	OS.execute("chmod", PackedStringArray(["u+w", directory]))
	_check(result != OK, "the save is refused")
	_eq(FileAccess.get_file_as_string(catalog.path), v1, "the v1 file is exactly as it was")
	_check(catalog.note.contains("could not be kept"), "and the note says why: " + catalog.note)
	_eq(catalog.save_look("codex", _look({AvatarLook.TOP: &"cream"})), OK, "once it can, it saves")


## The damaged file was moved aside, then the write failed: the note says where
## the file went, never that it is untouched.
func test_a_failed_write_after_moving_a_damaged_file_says_where_it_went() -> void:
	var catalog := _catalog_with("{ not json")
	DirAccess.make_dir_absolute(catalog.temporary_path())
	_check(catalog.save_look("claude", _look({AvatarLook.TOP: &"cream"})) != OK, "the write fails")
	_check(not catalog.note.contains("untouched"), "the note does not claim the file is untouched: " + catalog.note)
	_check(catalog.note.contains("damaged-"), "it says where it went: " + catalog.note)


func test_a_damaged_file_is_kept_aside_at_the_first_save() -> void:
	var catalog := _catalog_with("{ not json")
	_eq(catalog.state, AgentCatalog.FileState.DAMAGED, "unreadable")
	_check(catalog.problem.contains("not JSON"), "and why: " + catalog.problem)
	_eq(people.look_for("claude").top, &"terra", "defaults are used")
	_eq(FileAccess.get_file_as_string(catalog.path), "{ not json", "reading never writes")
	_eq(catalog.save_look("claude", _look({AvatarLook.TOP: &"cream"})), OK, "saving")
	var kept := ""
	for name in DirAccess.get_files_at(catalog.path.get_base_dir()):
		if name.contains(".damaged-"):
			kept = catalog.path.get_base_dir().path_join(name)
	_check(not kept.is_empty(), "the damaged file was moved aside")
	_eq(FileAccess.get_file_as_string(kept), "{ not json", "untouched")
	_check(catalog.note.contains(kept.get_file()), "and the note says where: " + catalog.note)
	_eq(_dict(_read(catalog.path), "looks").size(), 1, "the new file holds the save")
	var broken := _catalog_with('{"schema_version": "two"}')
	_eq(broken.state, AgentCatalog.FileState.DAMAGED, "a schema_version that is no number is damaged too")


func test_a_newer_file_is_never_written() -> void:
	var newer := '{"schema_version": 3, "looks": {"claude": {"top": "cream"}}, "presets": []}'
	var catalog := _catalog_with(newer)
	_eq(catalog.state, AgentCatalog.FileState.NEWER, "written by a newer Herdstead")
	_eq(people.look_for("claude").top, &"terra", "nothing of it is read")
	_check(catalog.save_look("claude", _look({AvatarLook.TOP: &"lilac"})) != OK, "saving refuses")
	_check(catalog.note.contains("newer"), "and says why: " + catalog.note)
	_eq(FileAccess.get_file_as_string(catalog.path), newer, "the file is exactly as it was")


func test_a_failed_write_leaves_the_old_file() -> void:
	var old := '{"schema_version": 2, "looks": {"claude": {"top": "cream"}}}'
	var catalog := _catalog_with(old)
	# A directory where the temporary file goes: the write cannot even open it.
	var temporary := catalog.temporary_path()
	_check(temporary.contains(str(OS.get_process_id())), "the temporary file is this process's own: " + temporary)
	DirAccess.make_dir_absolute(temporary)
	_check(catalog.save_look("claude", _look({AvatarLook.TOP: &"lilac"})) != OK, "the write fails")
	_eq(FileAccess.get_file_as_string(catalog.path), old, "the old file is whole")
	_check(catalog.note.contains("untouched"), "and the note says so: " + catalog.note)
	_check(catalog.temporary_path() != temporary, "the next save writes a temporary file of its own")
	_eq(catalog.save_look("claude", _look({AvatarLook.TOP: &"lilac"})), OK, "so it writes")
	DirAccess.remove_absolute(temporary)


func test_an_oversized_file_is_not_read() -> void:
	var catalog := _catalog_with('{"schema_version": 2, "looks": {}, "pad": "%s"}' % "x".repeat(AgentCatalog.MAX_BYTES))
	# Past the size cap it is not known to be unreadable: not read, never written, not DAMAGED.
	_eq(catalog.state, AgentCatalog.FileState.OUT_OF_BOUNDS, "past the size cap")
	_check(catalog.problem.contains("too large for this build"), "and why: " + catalog.problem)


# --- 4. the prefab --------------------------------------------------------------------


## What the office relies on in the prefab: the physics layers a worker walks
## on, the feet the layout policy measures (read from the scene, standing on
## the origin), a top-down body, and one sprite per layer under one player.
func test_the_prefab_is_shaped_for_the_office() -> void:
	var person: PixelPerson = PERSON_SCENE.instantiate()
	_spawned.append(person)
	_eq(person.collision_layer, OfficeWorld.ACTORS, "a person is an actor")
	_eq(person.collision_mask, OfficeWorld.FURNITURE, "furniture stops a person")
	var feet := person.get_node("Feet") as CollisionShape2D
	var box := feet.shape as RectangleShape2D
	var footprint := PixelPerson.footprint()
	_eq(footprint, Rect2(feet.position - box.size / 2.0, box.size), "footprint() is the scene's own Feet")
	_eq([footprint.end.y, footprint.get_center().x], [0.0, 0.0], "the feet end on the origin, centred on it")
	_eq(person.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING, "a top-down body: no floor, no gravity")
	var layers := person.get_node("Layers")
	_eq(layers.get_child_count(), PixelPeople.LAYERS.size(), "one sprite per layer")
	for index in PixelPeople.LAYERS.size():
		var layer := PixelPeople.LAYERS[index]
		_check(person.get_node_or_null(PixelPeople.SPRITES[layer]) is Sprite2D, "%s is a Sprite2D" % layer)
		_eq(
			layers.get_child(index).name,
			StringName(PixelPeople.SPRITES[layer].get_file()),
			"%s is drawn in its place" % layer
		)
	_eq(person.find_children("*", "AnimationPlayer", true, false).size(), 1, "one AnimationPlayer")


func test_configure_dresses_every_layer() -> void:
	var look := _look({AvatarLook.HAIR_STYLE: &"curl", AvatarLook.TOP: &"terra", AvatarLook.GLASSES: &"round"})
	var person := _person(look)
	_eq(
		[person.look.hair_style, person.look.top, person.look.glasses],
		[&"curl", &"terra", &"round"],
		"the look is taken"
	)
	for layer in PixelPeople.LAYERS:
		var sprite := _sprite(person, layer)
		_eq(
			sprite.texture,
			people.layer_texture(layer, person.look, PixelPeople.FRONT),
			"%s shows its front strip" % layer
		)
		_check(sprite.texture != null or layer == PixelPeople.HEADWEAR, "%s is drawn (codex's cap aside)" % layer)
		_eq(sprite.hframes, people.columns, "%s: a frame per column" % layer)
		_eq(sprite.vframes, 1, "%s: one row" % layer)
		_eq(sprite.scale, Vector2.ONE / float(people.density), "%s: scaled back to units" % layer)
		_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s: nearest" % layer)
		_eq(sprite.offset, -people.pivot * people.density, "%s: the origin is the feet" % layer)
	_check(_player(person).has_animation_library(&""), "the family's library is on the player")
	_check(_player(person).get_animation_library(&"") == people.animation_library(), "and it is the shared one")
	var first := _sprite(person, PixelPeople.LEGS).texture as AtlasTexture
	for sprite in _sprites(person):
		var region := sprite.texture as AtlasTexture
		if region != null:
			_check(region.atlas == first.atlas, "%s draws from the one front sheet" % sprite.name)


func test_node_ids_survive_look_state_facing_and_seat_changes() -> void:
	var person := _person()
	var before := _ids(person)
	var seat := Marker2D.new()
	root.add_child(seat)
	_spawned.append(seat)
	seat.position = Vector2(40, 60)
	person.configure(people, "claude", _look({AvatarLook.HEADWEAR: &"hood", AvatarLook.GLASSES: &"none"}))
	for semantic in ArtContract.ANIMATIONS:
		person.play_state(semantic)
	for facing: StringName in [
		PixelPeople.LEFT, PixelPeople.RIGHT, PixelPeople.SIDE, PixelPeople.BACK, PixelPeople.FRONT
	]:
		person.face(facing)
	person.play_track(&"walk")
	person.sit(seat)
	person.play_state(ArtContract.ANIMATION_WORKING)
	person.stand_up()
	person.configure(people, "pi", _look({AvatarLook.HEADWEAR: &"cap"}, AvatarLook.DESK, AvatarLook.BACK))
	_eq(_ids(person), before, "no node of the person was replaced")


func test_layers_show_the_same_frame_at_sampled_times() -> void:
	var person := _person()
	for id in people.tracks:
		var entry := people.tracks[id]
		person.play_track(id)
		for index in entry.frame_count():
			var begins := entry.starts_at(index)
			var middle := begins + entry.durations[index] / 2.0
			for at: float in [begins + INSIDE, middle]:
				_seek(person, at)
				for sprite in _sprites(person):
					_eq(sprite.frame, entry.frame(index), "%s at %.2fs: %s" % [id, at, sprite.name])


func test_play_state_picks_the_context_s_track() -> void:
	var person := _person()
	person.play_state(ArtContract.ANIMATION_WORKING)
	_eq(person.track, &"stand_idle", "standing, working shows stand_idle")
	person.play_state(ArtContract.ANIMATION_BLOCKED)
	_eq(person.track, &"stand_blocked", "standing blocked")
	person.sit()
	_eq(person.track, &"desk_blocked", "sitting down keeps the state and takes the desk track")
	person.play_state(ArtContract.ANIMATION_WORKING)
	_eq(person.track, &"desk_work", "seated working types")
	_eq(_player(person).assigned_animation, &"desk_work", "and the player plays it")


func test_a_paused_person_stays_paused_across_play_state() -> void:
	var person := _person(null, null, false)
	person.play_state(ArtContract.ANIMATION_IDLE)
	_check(person.is_playing(), "a person plays")
	person.pause()
	person.play_state(ArtContract.ANIMATION_BLOCKED)
	_check(not person.is_playing(), "a paused person stays paused whatever it is told")
	var entry := people.tracks[person.track]
	for sprite in _sprites(person):
		_eq(sprite.frame, entry.frame(0), "%s shows the new track's first frame" % sprite.name)
	person.face(PixelPeople.LEFT)
	_check(not person.is_playing(), "and paused across a turn")
	person.play()
	_check(person.is_playing(), "play() resumes")


func test_left_mirrors_every_layer_about_the_feet() -> void:
	var person := _person()
	person.play_track(&"walk")
	person.face(PixelPeople.LEFT)
	_eq(person.shown_facing(), PixelPeople.SIDE, "left shows the side strip")
	for sprite in _sprites(person):
		_check(sprite.flip_h, "%s is mirrored" % sprite.name)
		_eq(sprite.offset, -people.pivot * people.density, "%s keeps its origin on the feet" % sprite.name)
	_eq(
		_sprite(person, PixelPeople.BODY).texture,
		people.layer_texture(PixelPeople.BODY, person.look, PixelPeople.SIDE),
		"the body shows the side strip"
	)
	person.face(PixelPeople.RIGHT)
	for sprite in _sprites(person):
		_check(not sprite.flip_h, "%s: right is the drawing itself" % sprite.name)
	person.face(PixelPeople.SIDE)
	_eq(person.facing, people.side_faces, "side is the way the side strip is drawn")
	person.face(PixelPeople.FRONT)
	_eq(person.shown_facing(), PixelPeople.FRONT, "front")
	for sprite in _sprites(person):
		_check(not sprite.flip_h, "%s: the front is never mirrored" % sprite.name)
	_eq(person.look.orientation, AvatarLook.FRONT, "front is also the look's orientation")
	person.face(PixelPeople.BACK)
	_eq(person.look.orientation, AvatarLook.BACK, "and so is back")


func test_a_track_that_does_not_face_that_way_shows_its_front() -> void:
	var person := _person()
	person.face(PixelPeople.BACK)
	person.play_track(&"stand_blocked")
	_eq(person.shown_facing(), PixelPeople.FRONT, "stand_blocked has no back: its front shows")
	person.face(PixelPeople.LEFT)
	_eq(person.shown_facing(), PixelPeople.SIDE, "but it has a side")
	person.play_track(&"desk_work")
	_eq(person.shown_facing(), PixelPeople.FRONT, "desk_work has no side: its front")
	for sprite in _sprites(person):
		_check(not sprite.flip_h, "%s: a front shown for the left is not mirrored" % sprite.name)
	person.play_track(&"walk")
	_eq(person.shown_facing(), PixelPeople.SIDE, "walk faces the way asked for again")
	_check(_sprite(person, PixelPeople.HAIR).flip_h, "mirrored again")


func test_turning_keeps_the_step() -> void:
	var person := _person()
	person.play_track(&"walk")
	var entry := people.tracks[&"walk"]
	_seek(person, entry.starts_at(2) + INSIDE)
	person.face(PixelPeople.LEFT)
	for sprite in _sprites(person):
		_eq(sprite.frame, entry.frame(2), "%s is still on the same step after turning" % sprite.name)
	_check(
		is_equal_approx(_player(person).current_animation_position, entry.starts_at(2) + INSIDE),
		"the walk clock did not restart"
	)


func test_hold_shows_one_frame_paused() -> void:
	var person := _person(null, null, false)
	person.hold(&"carry_walk", 3)
	_check(not person.is_playing(), "a held frame does not play")
	for sprite in _sprites(person):
		_eq(sprite.frame, people.tracks[&"carry_walk"].frame(3), "%s holds the frame asked for" % sprite.name)


func test_sit_and_stand_up() -> void:
	var person := _person()
	var seat := Marker2D.new()
	root.add_child(seat)
	_spawned.append(seat)
	seat.position = Vector2(120, 80)
	var feet := person.get_node("Feet") as CollisionShape2D
	_check(not feet.disabled, "a standing person collides")
	person.face(PixelPeople.LEFT)
	person.play_state(ArtContract.ANIMATION_IDLE)
	person.sit(seat)
	_eq(person.global_position, seat.global_position, "snapped to the seat")
	_check(feet.disabled, "a chair is no obstacle to the person in it")
	_eq(person.look.context, AvatarLook.DESK, "the desk pose")
	_eq(person.facing, PixelPeople.FRONT, "a seated person faces the way the look says, not sideways")
	_eq(person.track, &"desk_idle", "idle at a desk")
	person.stand_up()
	_check(not feet.disabled, "standing collides again")
	_eq(person.look.context, AvatarLook.STAND, "the standing pose")
	_eq(person.track, &"stand_idle", "idle standing")


func test_drawing_rect_covers_every_frame() -> void:
	var bounds := PixelPerson.drawing_rect(people)
	_eq(bounds, Rect2(-people.pivot, Vector2(people.frame_size)), "the frame canvas, placed on the feet")
	for strip_facing in people.facings:
		for name in people.strips:
			var image := people.strip_texture(strip_facing, name).get_image()
			for index in people.columns:
				var used := image.get_region(people.frame_rect(index)).get_used_rect()
				if used.size == Vector2i.ZERO:
					continue
				# Texels back to units.
				var drawn := Rect2(
					Vector2(used.position) / people.density - people.pivot, Vector2(used.size) / people.density
				)
				# Mirrored about the feet: x -> -x.
				var mirrored := Rect2(Vector2(-drawn.end.x, drawn.position.y), drawn.size)
				_check(
					bounds.encloses(drawn), "%s %s frame %d is inside the drawing rect" % [strip_facing, name, index]
				)
				_check(
					bounds.encloses(mirrored), "%s %s frame %d, mirrored, is inside it" % [strip_facing, name, index]
				)


# --- 5. the showroom --------------------------------------------------------------------
# Real input only: a click is a mouse button pushed into the window at window
# pixels (the showroom draws one screen pixel per pixel); a choice in an
# OptionButton is its popup opened by a click and walked with the keyboard.


func test_the_showroom_shows_every_catalog_agent() -> void:
	var showroom := await _showroom()
	var shown := _people_in(_node(showroom, "Grid"))
	var catalog := people.catalog()
	_eq(shown.size(), catalog.ids().size(), "one person per catalog agent")
	for index in mini(shown.size(), catalog.ids().size()):
		var id := catalog.ids()[index]
		var expected := people.look_for(id, null, id)
		_eq(shown[index].provider, id, "in catalog order")
		_eq(shown[index].look.clothes().key(), expected.clothes().key(), "%s's look, varied by its id" % id)
		_check(shown[index].is_playing(), "%s plays" % id)
	_check((_node(showroom, "Grid") as Control).is_visible_in_tree(), "the grid is the first view")


func test_choosing_a_track_plays_it_on_every_person() -> void:
	var showroom := await _showroom()
	var grid := _node(showroom, "Grid")
	var before := _ids(grid)
	await _choose(_node(showroom, "Track") as OptionButton, "walk")
	for person in _people_in(grid):
		_eq(person.track, &"walk", "%s walks" % person.provider)
		_check(person.is_playing(), "%s is moving" % person.provider)
	_eq(_ids(grid), before, "choosing a track replaced no node")


func test_choosing_a_facing_turns_every_person() -> void:
	var showroom := await _showroom()
	await _choose(_node(showroom, "Track") as OptionButton, "walk")
	await _choose(_node(showroom, "Facing") as OptionButton, "left")
	for person in _people_in(_node(showroom, "Grid")):
		_eq(person.shown_facing(), PixelPeople.SIDE, "%s shows its side" % person.provider)
		_check(_sprite(person, PixelPeople.BODY).flip_h, "%s is mirrored" % person.provider)


func test_choosing_the_frames_view_lays_out_every_frame() -> void:
	var showroom := await _showroom()
	await _choose(_node(showroom, "View") as OptionButton, "frames")
	_check((_node(showroom, "Frames") as Control).is_visible_in_tree(), "the frames sheet shows")
	_check(not (_node(showroom, "Grid") as Control).is_visible_in_tree(), "the grid hides")
	var held := _people_in(_node(showroom, "Frames"))
	var expected := 0
	for id in people.tracks:
		expected += people.tracks[id].frame_count() * people.tracks[id].facings.size()
	_eq(held.size(), expected, "one cell per frame of every track in every facing it draws")
	var index := 0
	for id in people.tracks:
		var entry := people.tracks[id]
		for facing in entry.facings:
			for frame in entry.frame_count():
				if index < held.size():
					var person := held[index]
					_eq([person.track, person.shown_facing()], [id, facing], "cell %d is %s %s" % [index, id, facing])
					_eq(_sprite(person, PixelPeople.BODY).frame, entry.frame(frame), "cell %d holds its frame" % index)
					_check(not person.is_playing(), "cell %d is still" % index)
				index += 1


func test_choosing_a_look_redresses_the_frames() -> void:
	var showroom := await _showroom({"view": "frames"})
	var frames := _node(showroom, "Frames")
	var before := _ids(frames)
	await _choose(_node(showroom, "Headwear") as OptionButton, "hood")
	await _choose(_node(showroom, "HeadwearColour") as OptionButton, "teal")
	for person in _people_in(frames):
		_eq([person.look.headwear, person.look.headwear_colour], [&"hood", &"teal"], "every frame wears the look")
	var index := 0
	for id in people.tracks:
		var entry := people.tracks[id]
		for facing in entry.facings:
			for frame in entry.frame_count():
				var person := _people_in(frames)[index]
				_eq(
					[person.shown_facing(), _sprite(person, PixelPeople.BODY).frame],
					[facing, entry.frame(frame)],
					"cell %d keeps its facing and frame" % index
				)
				index += 1
	var first := _people_in(frames)[0]
	_eq(
		_sprite(first, PixelPeople.HEADWEAR).texture,
		people.strip_texture(first.shown_facing(), "headwear_hood_teal"),
		"the hood strip in its own colour"
	)
	_eq(_sprite(first, PixelPeople.HAIR).texture, null, "and no hair under it")
	_eq(_ids(frames), before, "a new look replaced no node")


## The contact sheet of every slot option: a group per option, the look with
## that one slot changed, from each facing, and every group keeps its own
## option when another slot changes.
func test_the_options_view_shows_every_option_of_every_slot() -> void:
	var showroom := await _showroom({"view": "options"})
	var sheet := _node(showroom, "Options")
	_check((sheet as Control).is_visible_in_tree(), "--view=options shows it")
	var options := 0
	for slot_id in AvatarLook.SLOTS:
		options += people.slots[slot_id].options().size()
	var facings := people.tracks[&"stand_idle"].facings.size()
	var held := _people_in(sheet)
	_eq(held.size(), options * facings, "a cell per option per facing the held track draws")
	var index := 0
	for slot_id in AvatarLook.SLOTS:
		for option in people.slots[slot_id].options():
			for _facing in facings:
				if index < held.size():
					_eq(held[index].look.slot(slot_id), option, "cell %d shows %s %s" % [index, slot_id, option])
				index += 1
	await _choose(_node(showroom, "Top") as OptionButton, "lilac")
	var glasses := _people_in(sheet).filter(func(p: PixelPerson) -> bool: return p.look.glasses == &"round")
	_check(not glasses.is_empty(), "the round glasses are still on show")
	for person: PixelPerson in glasses:
		_eq(person.look.top, &"lilac", "in the chosen top")


func test_the_play_button_pauses_and_resumes() -> void:
	var showroom := await _showroom()
	var play := _node(showroom, "Play") as Button
	await _click(play)
	for person in _people_in(_node(showroom, "Grid")):
		_check(not person.is_playing(), "%s paused" % person.provider)
	await _choose(_node(showroom, "Track") as OptionButton, "desk_work")
	for person in _people_in(_node(showroom, "Grid")):
		_check(not person.is_playing(), "%s stays paused on a new track" % person.provider)
	await _click(play)
	for person in _people_in(_node(showroom, "Grid")):
		_check(person.is_playing(), "%s plays again" % person.provider)


func test_command_line_options_reproduce_a_view() -> void:
	var options: Dictionary[String, String] = {
		"view": "frames", "track": "drink", "facing": "side", "look": "headwear:cap,top:teal,skin:sequins", "zoom": "3"
	}
	var showroom := await _showroom(options)
	_check((_node(showroom, "Frames") as Control).is_visible_in_tree(), "--view=frames")
	var view := _node(showroom, "View") as OptionButton
	_eq(view.get_item_text(view.selected), "frames", "the view control agrees")
	var track := _node(showroom, "Track") as OptionButton
	_eq(track.get_item_text(track.selected), "drink", "--track=")
	var facing := _node(showroom, "Facing") as OptionButton
	_eq(facing.get_item_text(facing.selected), "side", "--facing=")
	var top := _node(showroom, "Top") as OptionButton
	_eq(top.get_item_text(top.selected), "teal", "--look= sets the slot's control too")
	for person in _people_in(_node(showroom, "Frames")):
		_eq([person.look.headwear, person.look.top], [&"cap", &"teal"], "--look=")
		_eq(person.look.skin, people.default_look.skin, "an option the family does not draw keeps the default")
	for person in _people_in(_node(showroom, "Grid")):
		_eq(person.track, &"drink", "the grid plays --track= too")
		_eq(person.facing, people.side_faces, "and faces --facing=")
	_eq(showroom.get("zoom"), 3, "--zoom=")
	for person in _people_in(showroom):
		var stage := person.get_parent() as Node2D
		_eq(stage.scale, Vector2(3, 3), "every person is magnified by the whole zoom")
		_eq(person.position, person.position.round(), "and stands on a whole pixel")
	_eq(showroom.get_window().content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED, "one screen pixel per pixel")


## With nobody setting its command line, the showroom reads this process's own
## through AppArgs, as the office, the asset showroom and the studio do.
func test_the_showroom_reads_its_own_command_line() -> void:
	var showroom: Control = SHOWROOM_SCENE.instantiate()
	root.add_child(showroom)
	_spawned.append(showroom)
	await _settle()
	var read: Variant = showroom.get("args")
	_check(read is AppArgs, "it read a command line")
	if read is AppArgs:
		var line: AppArgs = read
		_eq(line.raw, OS.get_cmdline_user_args(), "this process's own")
		_eq(line.text("work"), args.work, "whose options it reads like any scene's")
	_check((_node(showroom, "Grid") as Control).is_visible_in_tree(), "and shows its first view")
