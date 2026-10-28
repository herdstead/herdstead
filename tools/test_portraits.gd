extends "res://tools/test_base.gd"
## Headless tests for the portraits family: PixelPortraits (the manifest read
## into typed fields against the pixel people, bad manifests refused, every cell
## as imported), PortraitLook (the seat's person resolved by the seat's own call,
## the extras picked by the people's hash under their own names, defaults with
## no pane), which cell each layer shows (none and a hood draw nothing) and
## ArtContract's portrait check.
## Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_portraits.gd -- --work=<tmp dir>

## A pane key as HerdrFleet.pane_key() spells it: machine, U+001F, pane id.
const PANE_P7 := "local\u001fw0:t9:p7"
const PANE_P8 := "local\u001fw0:t9:p8"
const CELL_COUNT := 81

var args: Dictionary[String, String] = {}
var people: PixelPeople
var portraits: PixelPortraits
var _fixtures := 0
## The directory fixture manifests are written to, next to a copy of the sheet.
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
	portraits = PixelPortraits.from_manifest(PixelPortraits.MANIFEST, people)
	if portraits == null:
		print("TEST_HARNESS_ERROR: %s does not load" % PixelPortraits.MANIFEST)
		quit(2)
		return
	await run_cases()


func _marker() -> String:
	return "PORTRAITS TESTS"


func _after_case() -> void:
	people.agent_catalog = AgentCatalog.new(_save_path())


# --- helpers ----------------------------------------------------------------------


## A fresh saved-looks path under --work for one case.
func _save_path() -> String:
	_saves += 1
	var directory := args.work.path_join("portrait_avatars_%d" % _saves)
	DirAccess.make_dir_recursive_absolute(directory)
	return directory.path_join("herdstead_avatars.json")


## A catalog reading `text` as its saved file, and the people resolving from it.
func _catalog_with(text: String) -> void:
	var path := _save_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	people.agent_catalog = AgentCatalog.new(path)


## A fixture manifest: the shipped one with `change` applied, next to a copy of
## the shipped sheet so a valid one loads. No tracked file is edited.
func _fixture(change: Callable) -> String:
	if _fixture_root.is_empty():
		_fixture_root = args.work.path_join("portraits_fixture")
		DirAccess.make_dir_recursive_absolute(_fixture_root)
		var copied := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(PixelPortraits.ROOT + PixelPortraits.SHEET),
			_fixture_root.path_join(PixelPortraits.SHEET)
		)
		_check(copied == OK, "fixture sheet copied")
	var data := ArtFamily.read_json(PixelPortraits.MANIFEST).duplicate(true)
	change.call(data)
	_fixtures += 1
	var path := _fixture_root.path_join("portraits_fixture_%d.json" % _fixtures)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return path


## A portrait look of exactly these slots and extras (no pane, no catalog).
func _look(slots: Dictionary[StringName, StringName], expression := &"smile", marks := &"none") -> PortraitLook:
	var look := PortraitLook.new()
	look.look = people.look_for("claude", AvatarLook.with_slots(slots))
	look.set_extra(PortraitLook.EXPRESSION, expression)
	look.set_extra(PortraitLook.MARKS, marks)
	look.set_extra(PortraitLook.NECKWEAR, &"none")
	return look


## The seven slots a portrait shows, and legs, of a look.
func _slots(look: AvatarLook) -> Array[StringName]:
	var found: Array[StringName] = []
	for id in AvatarLook.SLOTS:
		found.append(look.slot(id))
	return found


# --- the manifest ---------------------------------------------------------------


func test_manifest_reads_into_typed_fields() -> void:
	_eq(portraits.density, 2, "density 2, the pixel people's")
	_eq(portraits.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "sampled nearest")
	_eq(portraits.canvas, Vector2i(40, 40), "a 40x40-unit square")
	_eq(portraits.pivot, Vector2(20, 40), "its origin at the bottom centre")
	_eq(portraits.columns, 9, "nine cells to a row")
	_eq(portraits.layers.keys(), PixelPortraits.LAYERS, "the nine layers, bottom to top")
	_eq(portraits.extras.keys(), PortraitLook.EXTRAS, "the three extras")
	_eq(portraits.cells.size(), CELL_COUNT, "81 cells")
	_eq(portraits.files, PackedStringArray([PixelPortraits.SHEET]), "one sheet")
	_check(portraits.people == people, "bound to the people it was read against")
	var bound: Dictionary[StringName, Array] = {
		PixelPortraits.TOP: [&"", AvatarLook.TOP],
		PixelPortraits.HEAD: [&"", AvatarLook.SKIN],
		PixelPortraits.FACE: [PortraitLook.EXPRESSION, AvatarLook.SKIN],
		PixelPortraits.BROWS: [PortraitLook.EXPRESSION, AvatarLook.HAIR_COLOUR],
		PixelPortraits.MARKS: [PortraitLook.MARKS, AvatarLook.SKIN],
		PixelPortraits.NECKWEAR: [PortraitLook.NECKWEAR, &""],
		PixelPortraits.GLASSES: [AvatarLook.GLASSES, &""],
		PixelPortraits.HAIR: [AvatarLook.HAIR_STYLE, AvatarLook.HAIR_COLOUR],
		PixelPortraits.HEADWEAR: [AvatarLook.HEADWEAR, AvatarLook.HEADWEAR_COLOUR],
	}
	for layer in bound:
		_eq([portraits.layers[layer].shape, portraits.layers[layer].colour], bound[layer], "%s's slots" % layer)
	var expression := portraits.extras[PortraitLook.EXPRESSION]
	_eq(expression.options, [&"smile", &"smirk", &"focus"] as Array[StringName], "three expressions")
	_eq([expression.default, expression.allows_none], [&"smile", false], "a smile when there is no pane")
	for id: StringName in [PortraitLook.MARKS, PortraitLook.NECKWEAR]:
		var extra := portraits.extras[id]
		var none := 0
		for value in extra.pool:
			none += int(value == str(AvatarLook.NONE))
		_eq([extra.default, extra.allows_none, none, extra.pool.size()], [&"none", true, 5, 6], "%s: 1 in 6" % id)
	_eq(ArtContract.portrait_cells(portraits).size(), CELL_COUNT, "the contract asks for every cell")


## Every mutation is refused on its own: the fixture copies the sheet, so a
## rejection is the changed field's, never a missing picture's.
func test_bad_manifests_are_refused() -> void:
	_check(
		PixelPortraits.from_manifest(_fixture(func(_data: Dictionary) -> void: pass), people) != null, "a copy loads"
	)
	_check(PixelPortraits.from_manifest(PixelPortraits.MANIFEST, null) == null, "no people to bind to")
	_check(PixelPortraits.from_manifest(args.work.path_join("nowhere.json"), people) == null, "no file")
	var changes: Dictionary[String, Callable] = {
		"an unknown field": func(data: Dictionary) -> void: data["glow"] = true,
		"density 1": func(data: Dictionary) -> void: data["density"] = 1,
		"a linear filter": func(data: Dictionary) -> void: data["filter"] = "linear",
		"another schema": func(data: Dictionary) -> void: data["schema_version"] = 2,
		"a 48x48 canvas": func(data: Dictionary) -> void: data["canvas"] = [48, 48],
		"a pivot off the centre": func(data: Dictionary) -> void: data["pivot"] = [19, 40],
		"no columns": func(data: Dictionary) -> void: data["columns"] = 0,
		"columns the sheet is not": func(data: Dictionary) -> void: data["columns"] = 8,
		"a cell outside the sheet": func(data: Dictionary) -> void: _dict(data, "cells")["top_slate"] = CELL_COUNT,
		"a negative cell": func(data: Dictionary) -> void: _dict(data, "cells")["top_slate"] = -1,
		"a layer the node does not have": func(data: Dictionary) -> void: _dict(data, "layers")["beard"] = {},
		"a layer missing": func(data: Dictionary) -> void: _dict(data, "layers").erase("brows"),
		"a colour slot that is a shape slot":
		func(data: Dictionary) -> void: _dict(_dict(data, "layers"), "hair")["colour"] = "hair_style",
		"a colour slot the people do not have":
		func(data: Dictionary) -> void: _dict(_dict(data, "layers"), "head")["colour"] = "eyeliner",
		"a shape that is no slot and no extra":
		func(data: Dictionary) -> void: _dict(_dict(data, "layers"), "face")["shape"] = "mood",
		"an unknown layer field": func(data: Dictionary) -> void: _dict(_dict(data, "layers"), "top")["z"] = 1,
		"an extra missing": func(data: Dictionary) -> void: _dict(data, "extras").erase("marks"),
		"a default not drawn":
		func(data: Dictionary) -> void: _dict(_dict(data, "extras"), "expression")["default"] = "none",
		"a pool naming no option":
		func(data: Dictionary) -> void: _dict(_dict(data, "extras"), "marks")["pool"] = ["none", "scar"],
		"another sheet": func(data: Dictionary) -> void: data["files"] = ["faces.png"],
	}
	for label in changes:
		_check(PixelPortraits.from_manifest(_fixture(changes[label]), people) == null, "refused: " + label)


## The import hands out the builder's cells texel for texel: every cell's
## region of the imported sheet is the built PNG's cell.
func test_every_imported_cell_is_the_builder_s() -> void:
	var built := Image.load_from_file(ProjectSettings.globalize_path(PixelPortraits.ROOT + PixelPortraits.SHEET))
	built.convert(Image.FORMAT_RGBA8)
	var sheet := load(PixelPortraits.ROOT + PixelPortraits.SHEET) as Texture2D
	_check(sheet != null and not sheet.get_image().has_mipmaps(), "the sheet imports, without mipmaps")
	for name in portraits.cells:
		var region := portraits.cell_texture(name) as AtlasTexture
		_check(region != null and region.atlas == sheet, "%s is a region of the imported sheet itself" % name)
		if region == null:
			continue
		_eq(Rect2i(region.region), portraits.cell_rect(portraits.cells[name]), "%s: its cell" % name)
		var imported := region.get_image()
		imported.convert(Image.FORMAT_RGBA8)
		var expected := built.get_region(portraits.cell_rect(portraits.cells[name]))
		var differ := 0
		for y in expected.get_height():
			for x in expected.get_width():
				var want := expected.get_pixel(x, y)
				var got := imported.get_pixel(x, y)
				if want.a8 != got.a8 or (want.a8 != 0 and want.to_rgba32() != got.to_rgba32()):
					differ += 1
		_eq(differ, 0, "%s: the imported cell is the built one" % name)
	var first := portraits.cell_texture("top_slate")
	_check(portraits.cell_texture("top_slate") == first, "a region is made once and shared")


func test_the_family_is_not_a_theme() -> void:
	_check(not PixelPortraits.MANIFEST.ends_with("/manifest.json"), "its manifest is not a theme's manifest.json")
	_check(not FileAccess.file_exists(PixelPortraits.ROOT + "manifest.json"), "and no theme manifest sits beside it")
	_check(PixelPortraits.ROOT != PixelPeople.ROOT, "a family of its own, beside the people")


# --- the look ---------------------------------------------------------------------


## A portrait is the seat's person: its look is what the seat's own call
## (people.look_for with the pane key) resolves, slot by slot, for a provider
## with a default, one whose default wears a hat, an unknown one and a provider
## the user pinned.
func test_the_portrait_is_the_seat_s_person() -> void:
	for provider: String in ["claude", "codex", "nobody-knows"]:
		for pane: String in [PANE_P7, PANE_P8, ""]:
			var seat := people.look_for(provider, AvatarLook.facing(AvatarLook.DESK, AvatarLook.BACK), pane)
			var portrait := portraits.look_of(provider, pane)
			_eq(_slots(portrait.look), _slots(seat), "%s on %s: the seat's person" % [provider, pane.c_escape()])
	_eq(portraits.look_of("codex", "").look.headwear, &"cap", "codex's own default wears a cap")
	_catalog_with('{"schema_version": 2, "looks": {"claude": {"top": "lilac", "glasses": "round"}}}')
	for pane: String in [PANE_P7, PANE_P8]:
		var portrait := portraits.look_of("claude", pane)
		_eq([portrait.look.top, portrait.look.glasses], [&"lilac", &"round"], "a pinned provider's pins")
		_eq(_slots(portrait.look), _slots(people.look_for("claude", null, pane)), "still the seat's person")


## The extras are picked by the people's hash under their own names, pinned to
## values computed outside Godot (Python's hashlib, SHA-256 of
## "herdstead.look/1␟provider␟pane␟portrait.<extra>", first four bytes).
func test_extras_are_fixed_by_provider_and_pane() -> void:
	_eq(PixelPeople.pick("claude", PANE_P7, &"portrait.expression"), 3433880066, "the hash itself")
	_eq(PixelPeople.pick("claude", PANE_P7, &"portrait.marks"), 3351123454, "one per extra")
	_eq(PixelPeople.pick("claude", PANE_P7, &"portrait.neckwear"), 132833846, "and the third")
	var expected: Dictionary[String, Array] = {
		"claude|p7": [&"focus", &"none", &"none"],
		"claude|p8": [&"focus", &"freckles", &"headphones"],
		"codex|p7": [&"focus", &"none", &"none"],
		"codex|p2": [&"focus", &"freckles", &"headphones"],
		"claude|p1": [&"smirk", &"none", &"none"],
		"claude|p3": [&"smile", &"none", &"none"],
	}
	for case in expected:
		var parts := case.split("|")
		var look := portraits.look_of(parts[0], "local\u001fw0:t9:" + parts[1])
		_eq([look.expression, look.marks, look.neckwear], expected[case], "%s: expression, marks, neckwear" % case)
	var again := portraits.look_of("claude", PANE_P8)
	_eq(again.key(), portraits.look_of("claude", PANE_P8).key(), "asked twice, the same portrait")


func test_no_pane_gives_the_defaults() -> void:
	for provider: String in ["claude", "codex", "nobody-knows"]:
		var look := portraits.look_of(provider, "")
		_eq([look.expression, look.marks, look.neckwear], [&"smile", &"none", &"none"], provider + ": the defaults")
		_eq(_slots(look.look), _slots(people.look_for(provider)), provider + ": the provider's own look")


## The extras are new names under the same hash, so nobody's look moved: the
## scheme is not bumped and the people's own pinned picks stand.
func test_the_people_s_picks_did_not_move() -> void:
	_eq(PixelPeople.VARIATION_SCHEME, "herdstead.look/1", "the scheme is not bumped")
	_eq(PixelPeople.pick("claude", PANE_P7, AvatarLook.SKIN), 1107191239, "the skin's hash")
	_eq(PixelPeople.pick("claude", PANE_P7, AvatarLook.HAIR_STYLE), 2977282868, "the hair's")
	var look := portraits.look_of("claude", PANE_P7).look
	_eq(
		[look.skin, look.hair_style, look.hair_colour, look.glasses, look.top, look.headwear, look.headwear_colour],
		[&"deep", &"long", &"brown", &"none", &"terra", &"cap", &"cream"],
		"claude on p7 is who the people's suite pins"
	)


# --- which cell each layer shows -------------------------------------------------------


func test_every_layer_names_its_cell() -> void:
	var slots: Dictionary[StringName, StringName] = {
		AvatarLook.SKIN: &"tan",
		AvatarLook.HAIR_STYLE: &"curl",
		AvatarLook.HAIR_COLOUR: &"blonde",
		AvatarLook.TOP: &"teal",
		AvatarLook.HEADWEAR: &"cap",
		AvatarLook.HEADWEAR_COLOUR: &"sea",
		AvatarLook.GLASSES: &"square",
	}
	var look := _look(slots, &"smirk", &"freckles")
	look.set_extra(PortraitLook.NECKWEAR, &"headphones")
	var expected: Dictionary[StringName, String] = {
		PixelPortraits.TOP: "top_teal",
		PixelPortraits.HEAD: "head_tan",
		PixelPortraits.FACE: "face_smirk_tan",
		PixelPortraits.BROWS: "brows_smirk_blonde",
		PixelPortraits.MARKS: "marks_freckles_tan",
		PixelPortraits.NECKWEAR: "neckwear_headphones",
		PixelPortraits.GLASSES: "glasses_square",
		PixelPortraits.HAIR: "hair_curl_blonde",
		PixelPortraits.HEADWEAR: "headwear_cap_sea",
	}
	for layer in expected:
		_eq(portraits.cell_name(layer, look), expected[layer], "%s's cell" % layer)
		var texture := portraits.part_texture(layer, look) as AtlasTexture
		_check(texture != null and texture.atlas == load(PixelPortraits.ROOT + PixelPortraits.SHEET), "one sheet")
	_eq(portraits.cell_name(&"beard", look), "", "a layer the family does not have shows nothing")


func test_none_and_a_hood_draw_nothing_on_their_layer() -> void:
	var bare := _look({AvatarLook.GLASSES: AvatarLook.NONE, AvatarLook.HEADWEAR: AvatarLook.NONE})
	for layer: StringName in [PixelPortraits.GLASSES, PixelPortraits.HEADWEAR, PixelPortraits.MARKS]:
		_check(portraits.part_texture(layer, bare) == null, "%s at none: a null texture" % layer)
	_check(portraits.part_texture(PixelPortraits.NECKWEAR, bare) == null, "no headphones: nothing")
	_check(portraits.part_texture(PixelPortraits.HAIR, bare) != null, "bareheaded, the hair shows")
	var hooded := portraits.look_of("claude", PANE_P8)
	_eq(hooded.look.headwear, &"hood", "claude on p8 wears a hood")
	_check(portraits.part_texture(PixelPortraits.HAIR, hooded) == null, "a hood hides the hair")
	_eq(portraits.cell_name(PixelPortraits.HEADWEAR, hooded), "headwear_hood_terra", "and shows itself")
	var capped := portraits.look_of("claude", PANE_P7)
	_eq(capped.look.headwear, &"cap", "claude on p7 wears a cap")
	_check(portraits.part_texture(PixelPortraits.HAIR, capped) != null, "a cap leaves the hair below its brim")
	var bald := _look({AvatarLook.HAIR_STYLE: AvatarLook.NONE})
	_check(portraits.part_texture(PixelPortraits.HAIR, bald) == null, "no hair style: no hair")
	_check(portraits.part_texture(PixelPortraits.BROWS, bald) != null, "brows stay, in the hair's colour")
	var odd := _look({})
	odd.set_extra(PortraitLook.EXPRESSION, &"grin")
	_eq(portraits.cell_name(PixelPortraits.FACE, odd), "", "an expression the family does not draw: nothing")


# --- the contract -------------------------------------------------------------------


func test_the_contract_asks_for_every_cell() -> void:
	var art := ArtPack.from_manifest("res://assets/daylight/manifest.json")
	_check(art != null and art.portraits != null, "a pack loads the portraits beside the people")
	if art == null:
		return
	_check(art.portraits.people == art.people, "bound to the pack's own people (one catalog)")
	_eq(ArtContract.problems(art), PackedStringArray(), "daylight has every cell and the sheet")
	art.portraits = PixelPortraits.from_manifest(
		_fixture(func(data: Dictionary) -> void: _dict(data, "cells").erase("hair_curl_grey")), art.people
	)
	_check(art.portraits != null, "a manifest missing a cell still reads")
	_check(
		ArtContract.problems(art).has("portraits: no cell hair_curl_grey, which a look can show"),
		"the contract names the missing cell"
	)
	art.portraits = null
	_check(ArtContract.problems(art).has("portraits: the shared portraits did not load"), "and a missing family")


# --- the node (S3 PORTRAIT P2, 2026-10-28: the card shows the seat's person as a portrait) ---


## A portrait node shown on its own, under `root`, in `art`'s portraits, freed
## by the case.
func _portrait_node(art: ArtPack, provider: String, pane: String) -> PixelPortrait:
	var holder := Node2D.new()
	root.add_child(holder)
	return OfficeDraw.seat_portrait(holder, null, art, provider, pane)


## A pack whose people resolve against a fresh saved-looks file under --work, so
## nobody's saved looks take part.
func _pack() -> ArtPack:
	var art := ArtPack.from_manifest("res://assets/daylight/manifest.json")
	if art != null:
		art.agent_catalog = AgentCatalog.new(_save_path())
		art.people.agent_catalog = art.agent_catalog
	return art


## Every layer is a Sprite2D dressed as the family's dress() says (its origin at
## the portrait's bottom-centre pivot, scaled back by the density, NEAREST), and
## the nine are regions of one sheet: the premise of one draw call per portrait.
func test_the_node_dresses_every_layer_from_one_sheet() -> void:
	var art := _pack()
	_check(art != null, "the pack loads")
	if art == null:
		return
	var node := _portrait_node(art, "claude", PANE_P8)
	_eq(node.get_node("Layers").get_child_count(), PixelPortraits.LAYERS.size(), "nine layer sprites")
	var order: Array[String] = []
	for child in node.get_node("Layers").get_children():
		order.append(str(child.name))
	var named: Array[String] = []
	for layer in PixelPortraits.LAYERS:
		named.append(PixelPortraits.SPRITES[layer].get_file())
	_eq(order, named, "in the layers' order, bottom to top")
	var sheets: Array[int] = []
	var drawn := 0
	for layer in PixelPortraits.LAYERS:
		var sprite := node.sprite_of(layer)
		_eq(sprite.centered, false, "%s: not centred" % layer)
		_eq(
			sprite.offset, -art.portraits.pivot * PixelPortraits.PORTRAIT_DENSITY, "%s: offset -pivot x density" % layer
		)
		_eq(sprite.scale, Vector2.ONE / PixelPortraits.PORTRAIT_DENSITY, "%s: scaled back by the density" % layer)
		_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s: sampled NEAREST" % layer)
		var region := sprite.texture as AtlasTexture
		_eq(sprite.texture, art.portraits.part_texture(layer, node.look), "%s: the family's texture" % layer)
		if region != null:
			drawn += 1
			if not sheets.has(region.atlas.get_instance_id()):
				sheets.append(region.atlas.get_instance_id())
	_check(drawn >= 6, "most layers draw something: %d" % drawn)
	_eq(sheets.size(), 1, "every drawn layer is a region of the one sheet")
	_eq(node.look.key(), art.portraits.look_of("claude", PANE_P8).key(), "the pane's portrait")
	_eq(node.provider, "claude", "for the provider asked")
	node.get_parent().free()


## A second look on the same node keeps the same nine sprites and swaps their
## textures; a layer the look leaves at none (or the hair under a hood) gets a
## null texture.
func test_a_new_look_swaps_textures_on_the_same_sprites() -> void:
	var art := _pack()
	_check(art != null, "the pack loads")
	if art == null:
		return
	var node := _portrait_node(art, "claude", PANE_P7)
	var holder: Node2D = node.get_parent()
	var ids: Array[int] = []
	for layer in PixelPortraits.LAYERS:
		ids.append(node.sprite_of(layer).get_instance_id())
	var capped := node.look
	_eq(capped.look.headwear, &"cap", "claude on p7 wears a cap")
	_check(node.sprite_of(PixelPortraits.HAIR).texture != null, "and its hair shows under the brim")
	var again := OfficeDraw.seat_portrait(holder, node, art, "claude", PANE_P8)
	_eq(again, node, "the same node")
	_eq(holder.get_child_count(), 1, "no second portrait")
	var now: Array[int] = []
	for layer in PixelPortraits.LAYERS:
		now.append(node.sprite_of(layer).get_instance_id())
	_eq(now, ids, "the same nine sprites")
	_eq(node.look.look.headwear, &"hood", "claude on p8 wears a hood")
	_check(node.look.key() != capped.key(), "a new look")
	_check(node.sprite_of(PixelPortraits.HAIR).texture == null, "a hood: the hair layer draws nothing")
	_eq(
		node.sprite_of(PixelPortraits.HEADWEAR).texture,
		art.portraits.part_texture(PixelPortraits.HEADWEAR, node.look),
		"the hood's own cell"
	)
	_eq(node.look.neckwear, &"headphones", "claude on p8 wears headphones")
	OfficeDraw.seat_portrait(holder, node, art, "claude", "")
	_eq(node.look.neckwear, AvatarLook.NONE, "with no pane, no headphones")
	_check(node.sprite_of(PixelPortraits.NECKWEAR).texture == null, "and the neckwear layer draws nothing")
	_check(node.sprite_of(PixelPortraits.MARKS).texture == null, "nor the marks")
	holder.free()


## Identity: for every agent pane of the floors fixture, the person seated at its
## station (OfficeStation's PixelPerson) and its card portrait (the same
## seat_portrait() call the card makes) are one person on the seven slots a
## portrait shows, and again for a provider whose look the user pinned.
func test_the_card_portrait_and_the_seated_person_are_one_person() -> void:
	var art := _pack()
	_check(art != null, "the pack loads")
	if art == null:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	var file: Dictionary = parsed if parsed is Dictionary else {}
	var snapshot := HerdrSnapshot.from_wire(_dict(file, "snapshot"))
	_check(snapshot != null, "the floors fixture reads")
	if snapshot == null:
		return
	var shown: Array[StringName] = [
		AvatarLook.SKIN,
		AvatarLook.HAIR_STYLE,
		AvatarLook.HAIR_COLOUR,
		AvatarLook.TOP,
		AvatarLook.HEADWEAR,
		AvatarLook.HEADWEAR_COLOUR,
		AvatarLook.GLASSES,
	]
	var pen := OfficeDraw.new(art)
	var ground := Node2D.new()
	root.add_child(ground)
	var table := pen.table(ground, ground, "Table0", Vector2.ZERO, 160.0, [80.0])
	var station := pen.station(ground, table, 0, "far")
	var holder := Node2D.new()
	ground.add_child(holder)
	var portrait: PixelPortrait = null
	for pinned: bool in [false, true]:
		if pinned:
			_catalog_with('{"schema_version": 2, "looks": {"claude": {"top": "lilac", "glasses": "round"}}}')
			art.agent_catalog = people.agent_catalog
			art.people.agent_catalog = people.agent_catalog
		var compared := 0
		for pane in snapshot.panes:
			if pane.agent.is_empty():
				continue
			var key := HerdrFleet.pane_key("local", pane.pane_id)
			station.pane_key = key
			station.furnish(pane.agent, StringName(pane.agent_status))
			var seated := station.actor()
			portrait = OfficeDraw.seat_portrait(holder, portrait, art, pane.agent, key)
			_check(seated != null, "%s has a seated person" % pane.pane_id)
			if seated == null:
				continue
			for slot in shown:
				_eq(
					portrait.look.look.slot(slot),
					seated.look.slot(slot),
					"%s%s: the portrait's %s is the seat's" % [pane.pane_id, " (pinned)" if pinned else "", slot]
				)
			if pinned and pane.agent == "claude":
				_eq([portrait.look.look.top, portrait.look.look.glasses], [&"lilac", &"round"], "the pins show")
			compared += 1
		_check(compared >= 9, "every agent pane of the fixture compared: %d" % compared)
	ground.free()
