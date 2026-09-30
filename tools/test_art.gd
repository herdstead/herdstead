extends "res://tools/test_base.gd"
## Headless tests for the art layer: scripts/art/. What a manifest means once it
## is typed, what the loader refuses, what a pack has to carry for the scenes to
## draw at all, and that a node the pack hands out covers the same density-1
## rectangle whatever density it was built at. Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_art.gd -- --work=<short tmp dir>
##
## No herdr and no office: an art pack is not a client, and the fixtures it
## needs are written under --work. Exits 0 when every case passes, 1 on any
## failure, 2 on a harness error.

const MANIFEST := "res://assets/daylight/manifest.json"

## Where fixture packs are written; --work, from tools/run_tests.sh.
var work_dir := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--work="):
			work_dir = argument.trim_prefix("--work=")
	if work_dir.is_empty():
		print("TEST_HARNESS_ERROR: missing --work= (use tools/run_tests.sh)")
		quit(2)
		return
	_run()


func _run() -> void:
	await process_frame
	await run_cases()


func _marker() -> String:
	return "ART TESTS"


# --- cases --------------------------------------------------------------------


func test_bundled_typography_keeps_latin_and_cjk_readable() -> void:
	var text_server := TextServerManager.get_primary_interface()
	var weight := text_server.name_to_tag("wght")
	for path: String in [MANIFEST]:
		var pack := ArtPack.from_manifest(path)
		var drawing := OfficeDraw.new(pack)
		var text := drawing.font as FontVariation
		_check(text != null and text.base_font == pack.font, "the pack, not a platform font, owns Latin glyphs")
		_check(pack.font.get_font_name().begins_with("Nunito Sans"), "both themes ship the intended face")
		var text_axes := text_server.font_get_variation_coordinates(text.get_rids()[0])
		_eq(text_axes.get(weight), 500.0, "the renderer actually uses medium weight, not the ExtraLight default")
		_check(not text.fallbacks.is_empty(), "Chinese keeps an explicit platform fallback")
		for character: String in ["数", "据", "▲", "▼"]:
			_check(text.has_char(character.unicode_at(0)), "fallback covers " + character)
		var theme := HudTheme.build(pack, text)
		_eq(theme.default_font, text, "world labels and HUD use the same text face")
		var heading := theme.get_font("font", "Heading16") as FontVariation
		_check(heading != null and heading != text, "headings have their own weight")
		var heading_axes := text_server.font_get_variation_coordinates(heading.get_rids()[0])
		_eq(heading_axes.get(weight), 700.0, "the renderer actually uses bold for headings")
		_check(text.get_string_size("CLAUDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= 64.0, "name fits its seat column")


## Godot sizes a text row by the tallest font in the fallback chain. Linux's
## Noto Sans CJK is taller than the pack's face (macOS's Hiragino is not), and
## on CI it grew the agent card's twelve preview rows out of the staff panel.
## A fallback may draw its glyphs, never make a Latin row taller.
func test_a_fallback_never_makes_a_row_taller() -> void:
	for path: String in [MANIFEST]:
		var pack := ArtPack.from_manifest(path)
		var text := OfficeDraw.new(pack).font
		var theme := HudTheme.build(pack, text)
		for name: StringName in HudTheme.LABEL_SIZES:
			var pixels := HudTheme.LABEL_SIZES[name]
			var height := theme.get_font("font", name).get_height(pixels)
			_check(
				height <= pack.font.get_height(pixels), "%s at %d: %s, no taller than its face" % [name, pixels, height]
			)
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(HudTheme.MONO_FACES)
		var preview := theme.get_font("font", "PreviewText").get_height(HudTheme.PREVIEW_SIZE)
		_check(
			preview <= mono.get_height(HudTheme.PREVIEW_SIZE),
			"a preview row: %s, no taller than the mono face" % preview
		)


## The set of semantic IDs the scenes draw with lives in GDScript, next to the
## code that draws, and every pack is held to it. A pack that lacks one is
## named, not quietly missing a texture at runtime.
func test_art_contract_names_every_id_a_pack_lacks() -> void:
	_check(ArtContract.problems(ArtPack.from_manifest(MANIFEST)).is_empty(), "the shipped pack dresses the scenes")
	var missing := {
		"a palette colour": func(m: Dictionary) -> void: _drop(m, ["palette", "task_light"]),
		"a tile": func(m: Dictionary) -> void: _drop(m, ["tiles", "rug.middle_center"]),
		"a prop": func(m: Dictionary) -> void: _drop(m, ["props", "sign"]),
		"a UI image": func(m: Dictionary) -> void: _drop(m, ["ui", "branch"]),
		"a state": func(m: Dictionary) -> void: _drop(m, ["states", "blocked"]),
	}
	var named := {
		"a palette colour": "task_light",
		"a tile": "rug.middle_center",
		"a prop": "sign",
		"a UI image": "branch",
		"a state": "blocked",
	}
	for what: String in missing:
		var change: Callable = missing[what]
		var pack := ArtPack.from_manifest(_mutated_pack("lacks-" + what, change))
		var problems := ArtContract.problems(pack)
		var wanted: String = named[what]
		_check(not problems.is_empty(), "a pack without " + what + " is refused")
		_check(
			Array(problems).any(func(line: String) -> bool: return line.contains(wanted)),
			"and the refusal names " + wanted + ": " + " / ".join(Array(problems))
		)
	# A state may only name a badge the pack really draws and an animation the
	# pixel people really have a track for.
	var stray := func(m: Dictionary) -> void: _dict(_dict(m, "states"), "blocked").badge = "no_such_icon"
	var mismatched := ArtContract.problems(ArtPack.from_manifest(_mutated_pack("stray-badge", stray)))
	_check(
		Array(mismatched).any(func(line: String) -> bool: return line.contains("no_such_icon")),
		"a state whose badge is not a UI image is named: " + " / ".join(Array(mismatched))
	)
	# The pack's people are held to what the office draws with them: a semantic
	# animation with no track, or a desk track with no back for the near side.
	var crowd := ArtPack.from_manifest(MANIFEST)
	crowd.people.tracks[&"desk_work"].facings.erase(PixelPeople.BACK)
	var mapped: Dictionary[StringName, StringName] = crowd.people.state_tracks[AvatarLook.STAND]
	mapped[ArtContract.ANIMATION_BLOCKED] = &"no_such_track"
	var unfit := Array(ArtContract.problems(crowd))
	for wanted: String in ["no_such_track", "desk_work"]:
		_check(
			unfit.any(func(line: String) -> bool: return line.contains(wanted)),
			"people that cannot draw a worker are named (%s): %s" % [wanted, " / ".join(unfit)]
		)
	# The density fixtures ship no table at all, which is legal to load and
	# refused here: a pack with no table cannot furnish a floor.
	var tableless := ArtContract.problems(ArtPack.from_manifest(_dense_pack(1)))
	_check(
		Array(tableless).any(func(line: String) -> bool: return line.contains("no shared table")),
		"a pack with no shared table cannot furnish a floor: " + " / ".join(Array(tableless))
	)


## A manifest that cannot be drawn returns null and says why; it never invents a
## value and never asserts, because --export-release strips assert().
func test_art_pack_refuses_a_manifest_it_cannot_draw() -> void:
	var broken := {
		"no id": func(m: Dictionary) -> void: m.erase("id"),
		"a tile_size that is not a number": func(m: Dictionary) -> void: m.tile_size = "32",
		"an atlas_size that is not a pair": func(m: Dictionary) -> void: m.atlas_size = 256,
		"no atlas": func(m: Dictionary) -> void: m.erase("atlas"),
		"a palette colour that is not hex": func(m: Dictionary) -> void: m.palette.ink = "not-a-colour",
		"a tile with no cell": func(m: Dictionary) -> void: m.tiles["floor.walkway"] = {},
		"a prop with no pivot": func(m: Dictionary) -> void: _drop(m, ["props", "sign", "pivot"]),
		"a UI image with no path": func(m: Dictionary) -> void: _drop(m, ["ui", "panel", "path"]),
		"a state with no badge": func(m: Dictionary) -> void: _drop(m, ["states", "idle", "badge"]),
		"no font": func(m: Dictionary) -> void: m.erase("font"),
		"a font with no licence": func(m: Dictionary) -> void: _drop(m, ["font", "license"]),
		"a stale_modulate that is not hex": func(m: Dictionary) -> void: m.stale_modulate = "dusk",
		"a task_lights nobody drew": func(m: Dictionary) -> void: m.task_lights = "blinding",
	}
	for what: String in broken:
		var change: Callable = broken[what]
		var path := _mutated_pack("broken-" + what, change)
		_check(ArtPack.from_manifest(path) == null, "a pack with " + what + " does not load")
	_check(ArtPack.from_manifest("res://assets/no-such-pack/manifest.json") == null, "nor does a manifest that is gone")


## An `item` block (docs/ITEMS.md) reads into ItemSpec: what the item stands
## on, its footprint, whether it blocks, its pool and weight; a prop without
## one (the door) has none. A pool is its members by id, whatever order a file lists them in.
func test_an_item_block_reads_into_typed_fields() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var mug := art.prop_sprite(&"desk_mug").item
	_check(mug != null, "the mug has an item block")
	_eq(
		[mug.place, mug.footprint, mug.blocks, mug.group, mug.weight],
		[&"desk", Vector2(7, 3), false, &"desk", 1],
		"a desk item"
	)
	var plant := art.prop_sprite(&"plant").item
	_eq(
		[plant.place, plant.footprint, plant.blocks, plant.group],
		[&"floor", Vector2(20, 10), true, &"plant"],
		"a floor item blocks"
	)
	_eq(art.prop_sprite(&"wall_frame").item.place, &"wall", "a wall item needs no footprint")
	_eq(art.prop_sprite(&"done_stack").item.group, &"", "a signal is in no pool")
	_check(art.prop_sprite(&"door").item == null, "the door is placed by code, by its id")
	var desk: Array[StringName] = []
	for member in art.items_in(&"desk"):
		desk.append(member.id)
	_eq(desk, [&"desk_headphones", &"desk_mug", &"desk_notebook", &"desk_papers", &"desk_plant"], "by id")
	_check(art.items_in(&"nothing").is_empty(), "a pool nobody is in is empty")


## Equal weights draw as one randi_range() over the pool; a weight of 0 is never
## drawn; an empty pool, nothing.
func test_a_pool_draws_by_weight_and_equal_weights_keep_old_choices() -> void:
	var cats := ArtPack.from_manifest(MANIFEST).items_in(&"cat")
	for seed_value in 200:
		var drawn := RandomNumberGenerator.new()
		drawn.seed = seed_value
		var old := RandomNumberGenerator.new()
		old.seed = seed_value
		_eq(ArtPack.pick(cats, drawn).id, cats[old.randi_range(0, cats.size() - 1)].id, "seed %d" % seed_value)
	var never := func(m: Dictionary) -> void:
		m.props.cat_loaf.item.weight = 0
		m.props.cat_sit.item.weight = 3
	var weighted := ArtPack.from_manifest(_mutated_pack("weighted-cats", never)).items_in(&"cat")
	var seen: Dictionary[StringName, int] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for draw in 400:
		var id := ArtPack.pick(weighted, rng).id
		seen[id] = seen.get(id, 0) + 1
	_check(not seen.has(&"cat_loaf"), "a weight of 0 is never drawn: %s" % seen)
	var sit: int = seen.get(&"cat_sit", 0)
	var sleep: int = seen.get(&"cat_sleep", 0)
	_check(sit > sleep * 2, "three times the weight, about three times the draws: %s" % seen)
	var none: Array[ArtSprite] = []
	_check(ArtPack.pick(none, rng) == null, "an empty pool draws nothing")


## The display face is optional: the shipped pack names Tiny5, read as a font
## drawn hard (no antialiasing, no hinting, whole-pixel positions); a pack that
## names none loads with none, and HudTheme falls back to the main face; one
## that names a file it does not ship is refused.
func test_the_display_font_is_optional_and_drawn_hard() -> void:
	var shipped := ArtPack.from_manifest(MANIFEST)
	_check(shipped.display_font is FontFile, "the shipped pack has its display face")
	var face := shipped.display_font as FontFile
	if face != null:
		_eq(face.antialiasing, TextServer.FONT_ANTIALIASING_NONE, "no antialiasing")
		_eq(face.subpixel_positioning, TextServer.SUBPIXEL_POSITIONING_DISABLED, "whole pixels")
	var theme := HudTheme.build(shipped, OfficeDraw.new(shipped).font)
	_eq(theme.get_font("font", "Wordmark"), shipped.display_font, "the wordmark wears it")
	var without := ArtPack.from_manifest(
		_mutated_pack("no-display", func(m: Dictionary) -> void: m.erase("display_font"))
	)
	_check(without != null and without.display_font == null, "a pack without one loads, with none")
	if without != null:
		var plain := HudTheme.build(without, OfficeDraw.new(without).font)
		_check(plain.get_font("font", "Wordmark") != shipped.display_font, "and the wordmark keeps the main face")
	var missing := func(m: Dictionary) -> void: m.display_font.path = "fonts/nowhere.ttf"
	_eq(
		ArtPack.from_manifest(_mutated_pack("lost-display", missing)),
		null,
		"a display face it does not ship is refused"
	)


## A broken item block refuses the whole pack, like any other contract error:
## a misspelt key must not read as an absent one.
func test_a_broken_item_block_refuses_the_pack() -> void:
	var broken := {
		"an unknown key": func(m: Dictionary) -> void: m.props.desk_mug.item.colour = "red",
		"a place that is none": func(m: Dictionary) -> void: m.props.desk_mug.item.place = "roof",
		"a desk item with no footprint":
		func(m: Dictionary) -> void: _drop(m, ["props", "desk_mug", "item", "footprint"]),
		"a footprint wider than the canvas": func(m: Dictionary) -> void: m.props.desk_mug.item.footprint = [30, 3],
		"an empty footprint": func(m: Dictionary) -> void: m.props.desk_mug.item.footprint = [0, 3],
		"blocks on a desk item": func(m: Dictionary) -> void: m.props.desk_mug.item.blocks = true,
		"a floor item that does not block": func(m: Dictionary) -> void: m.props.plant.item.blocks = false,
		"a group that is not an id": func(m: Dictionary) -> void: m.props.desk_mug.item.group = "Desk!",
		"a weight with no group": func(m: Dictionary) -> void: m.props.done_stack.item.weight = 2,
		"a negative weight": func(m: Dictionary) -> void: m.props.desk_mug.item.weight = -1,
		"an item on a UI image": func(m: Dictionary) -> void: m.ui.panel.item = {"place": "wall"},
	}
	for what: String in broken:
		var change: Callable = broken[what]
		var path := _mutated_pack("item-" + what, change)
		_check(ArtPack.from_manifest(path) == null, "a pack with " + what + " does not load")


## Every pool a scene draws from has members, and each stands where its pool
## is drawn; the done paper stack (the pod's small one), a signal, is never in one.
func test_the_contract_names_an_empty_or_misplaced_pool() -> void:
	var catless := func(m: Dictionary) -> void:
		for cat: String in ["cat_loaf", "cat_sleep", "cat_sit"]:
			_drop(m, ["props", cat, "item", "group"])
	var problems := ArtContract.problems(ArtPack.from_manifest(_mutated_pack("pool-catless", catless)))
	_check(problems.has("props: nothing in the cat pool"), "an empty pool: %s" % problems)
	var misplaced := func(m: Dictionary) -> void:
		m.props.plant_b.item = {"place": "desk", "footprint": [20, 10], "group": "plant"}
	problems = ArtContract.problems(ArtPack.from_manifest(_mutated_pack("pool-misplaced", misplaced)))
	_check(
		problems.has("props: plant_b is in the plant pool but stands on the desk"), "a misplaced member: %s" % problems
	)
	var pooled := func(m: Dictionary) -> void: m.props.done_stack_small.item.group = "desk"
	problems = ArtContract.problems(ArtPack.from_manifest(_mutated_pack("pool-signal", pooled)))
	_check(problems.has("props: done_stack_small is a signal, never in a pool"), "a signal in a pool: %s" % problems)


func test_art_pack_rejects_wrong_json_containers() -> void:
	for field: String in ["palette", "tiles", "props", "ui", "states", "font"]:
		var absent := func(m: Dictionary) -> void: m.erase(field)
		_check(ArtPack.from_manifest(_mutated_pack("absent-" + field, absent)) == null, field + " object is required")
		for value: Variant in [[], "object", 7, null]:
			var change := func(m: Dictionary) -> void: m[field] = value
			var path := _mutated_pack("container-" + field, change)
			_check(ArtPack.from_manifest(path) == null, "%s refuses %s, without a script error" % [field, str(value)])
	for field: String in ["tiles", "props", "ui", "states"]:
		var change := func(m: Dictionary) -> void: _dict(m, field)["invalid"] = []
		_check(ArtPack.from_manifest(_mutated_pack("entry-" + field, change)) == null, field + " entries are objects")


func test_art_pack_rejects_invalid_geometry_before_drawing() -> void:
	var broken := {
		"wrong tile units": func(m: Dictionary) -> void: m.tile_size = 31,
		"fractional atlas": func(m: Dictionary) -> void: m.atlas_size = [256, 128.5],
		"partial atlas cell": func(m: Dictionary) -> void: m.atlas_size = [256, 127],
		"fractional cell": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [3.5, 0],
		"nearly whole cell": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [3.000000001, 0],
		"duplicate cell": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [0, 0],
		"past atlas x": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [8, 0],
		"past atlas y": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [3, 4],
		"far outside atlas": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [999, 999],
		"wrapping cell": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [4294967299, 0],
		"negative cell y": func(m: Dictionary) -> void: m.tiles["floor.walkway"].cell = [3, -1],
		"empty width": func(m: Dictionary) -> void: m.props.sign.size = [0, 24],
		"negative height": func(m: Dictionary) -> void: m.props.sign.size = [64, -1],
		"fractional size": func(m: Dictionary) -> void: m.props.sign.size = [64, 24.5],
		"negative pivot y": func(m: Dictionary) -> void: m.props.sign.pivot = [32, -1],
		"past pivot x": func(m: Dictionary) -> void: m.props.sign.pivot = [65, 22],
		"past pivot y": func(m: Dictionary) -> void: m.props.sign.pivot = [32, 25],
		"fractional pivot": func(m: Dictionary) -> void: m.props.sign.pivot = [32, 22.5],
		"patch object": func(m: Dictionary) -> void: m.ui.panel.nine_patch = {},
		"patch wrong length": func(m: Dictionary) -> void: m.ui.panel.nine_patch = [4, 4, 4],
		"patch negative": func(m: Dictionary) -> void: m.ui.panel.nine_patch = [4, -1, 4, 4],
		"patch fractional": func(m: Dictionary) -> void: m.ui.panel.nine_patch = [4, 4, 4.5, 4],
		"patch no middle x": func(m: Dictionary) -> void: m.ui.panel.nine_patch = [3, 5, 29, 26],
		"patch no middle y": func(m: Dictionary) -> void: m.ui.panel.nine_patch = [3, 5, 28, 27],
	}
	for what: String in broken:
		var change: Callable = broken[what]
		_check(ArtPack.from_manifest(_mutated_pack(what, change)) == null, "rejects " + what + " at the JSON boundary")
	var edges := func(m: Dictionary) -> void:
		m.tiles["floor.walkway"].cell = [7, 3]
		m.props.sign.pivot = [64, 24]
		m.ui.panel.nine_patch = [3, 5, 28, 26]
	var valid := ArtPack.from_manifest(_mutated_pack("geometry-edges", edges))
	_check(valid != null, "last atlas cell, inclusive foot pivot and one-unit patch middle remain legal")
	if valid == null:
		return
	_eq(valid.prop_sprite(&"sign").pivot, Vector2(64, 24), "both pivot edges survive parsing")
	_eq([valid.panel().patch_right, valid.panel().patch_bottom], [28, 26], "asymmetric margins are preserved")
	var built := valid.tileset()
	_check(built != null, "accepted edge geometry really builds a TileSet")
	if built != null:
		var atlas: TileSetAtlasSource = built.get_source(0)
		_eq(atlas.get_tile_data(Vector2i(7, 3), 0).get_custom_data("semantic_id"), "floor.walkway", "last cell draws")


func test_art_pack_requires_decodable_images_at_declared_density() -> void:
	var no_density_or_filter := func(m: Dictionary) -> void:
		m.erase("density")
		m.erase("filter")
	# A density the copied images are not at, whatever the shipped pack's is.
	var other_density := func(m: Dictionary) -> void: m.density = 4 if ArtFamily.whole(m.density) == 2 else 2
	var broken := {
		"atlas missing": func(m: Dictionary) -> void: m.atlas = "missing.png",
		"atlas path type": func(m: Dictionary) -> void: m.atlas = [],
		"prop missing": func(m: Dictionary) -> void: m.props.sign.path = "missing.png",
		"UI path type": func(m: Dictionary) -> void: m.ui.panel.path = 42,
		"atlas width mismatch": func(m: Dictionary) -> void: m.atlas_size = [288, 128],
		"prop height mismatch": func(m: Dictionary) -> void: m.props.sign.size = [64, 25],
		"UI width mismatch": func(m: Dictionary) -> void: m.ui.panel.size = [33, 32],
		"wrong image density": other_density,
		"no density": func(m: Dictionary) -> void: m.erase("density"),
		"no density or filter": no_density_or_filter,
	}
	for what: String in broken:
		var change: Callable = broken[what]
		_check(ArtPack.from_manifest(_mutated_pack(what, change)) == null, "rejects " + what)
	for image_path: String in ["terrain.png", "props/sign.png", "ui/panel.png"]:
		var path := _mutated_pack("corrupt-" + image_path.replace("/", "-"), func(_m: Dictionary) -> void: pass)
		_check(ArtPack.from_manifest(path) != null, "the copied pack is valid before corrupting " + image_path)
		var file := FileAccess.open(path.get_base_dir().path_join(image_path), FileAccess.WRITE)
		file.store_string("not a PNG")
		file.close()
		_check(ArtPack.from_manifest(path) == null, "rejects undecodable " + image_path + " before drawing")
	var imported := ArtPack.from_manifest(MANIFEST)
	_check(imported.texture(imported.font_path) == null, "an existing non-texture res:// resource is not an image")


func test_art_pack_palette_and_options_do_not_coerce_bad_values() -> void:
	for value: Variant in ["abc", "ABCDEF", "#abcdef", "abcdef12", [], null]:
		var palette_change := func(m: Dictionary) -> void: m.palette.ink = value
		_check(
			ArtPack.from_manifest(_mutated_pack("hex-palette", palette_change)) == null,
			"palette needs six lowercase hex"
		)
		var tint_change := func(m: Dictionary) -> void: m.stale_modulate = value
		_check(ArtPack.from_manifest(_mutated_pack("hex-tint", tint_change)) == null, "tint needs six lowercase hex")
	var broken := {
		"lights": func(m: Dictionary) -> void: m.task_lights = [],
		"name": func(m: Dictionary) -> void: m.name = [],
		"state label": func(m: Dictionary) -> void: m.states.idle.label = [],
		"font path": func(m: Dictionary) -> void: m.font.path = [],
		"font license": func(m: Dictionary) -> void: m.font.license = [],
	}
	for what: String in broken:
		var change: Callable = broken[what]
		_check(ArtPack.from_manifest(_mutated_pack("text-" + what, change)) == null, what + " is not coerced into text")


func test_art_tileset_failure_is_not_cached() -> void:
	var pack := ArtPack.from_manifest(_dense_pack(1))
	# Public typed fields are mutable. Fail after some cells could have been
	# created, then repair and retry: no half-built resource may escape.
	pack.tiles[&"invalid"] = Vector2i(999, 999)
	pack.tiles[&"after_invalid"] = Vector2i(7, 3)
	_check(pack.tileset() == null, "an atlas construction failure returns null")
	_check(pack.tileset() == null, "a second attempt does not return a cached partial tileset")
	pack.tiles.erase(&"invalid")
	var rebuilt := pack.tileset()
	_check(rebuilt != null, "a repaired pack can retry construction")
	if rebuilt == null:
		return
	var atlas: TileSetAtlasSource = rebuilt.get_source(0)
	_eq(atlas.get_tiles_count(), pack.tiles.size(), "a successful retry contains all and only the declared tiles")
	_eq(
		atlas.get_tile_data(Vector2i(7, 3), 0).get_custom_data("semantic_id"),
		"after_invalid",
		"retry finishes later cells"
	)
	_eq(pack.tileset(), rebuilt, "only the complete tileset is cached")


## The keys docs/ASSET_SPEC.md calls optional are the only ones that default.
## Everything else is a contract error, so a misspelt key cannot read as a
## plausible value.
func test_art_pack_optional_keys_default_as_documented() -> void:
	var plain := ArtPack.from_manifest(_mutated_pack("plain", func(m: Dictionary) -> void: m.erase("stale_modulate")))
	_eq(plain.stale_tint, ArtPack.STALE_DEFAULT, "a pack that names no stale tint gets the built-in dim")
	_eq(plain.task_lights, ArtPack.TASK_LIGHTS_SOFT, "and daylight-strength desk lamps")
	var lamp_lit_keys := func(m: Dictionary) -> void:
		m.stale_modulate = "8f96b8"
		m.task_lights = "strong"
	var lamp_lit := ArtPack.from_manifest(_mutated_pack("lamp-lit", lamp_lit_keys))
	_eq(lamp_lit.stale_tint, Color("#8f96b8"), "a pack may name its own stale tint")
	_eq(lamp_lit.task_lights, ArtPack.TASK_LIGHTS_STRONG, "and strong desk lamps")
	# `filter` is optional in the schema and always written by the builder; a
	# hand-written manifest gets the rule every other family follows. The
	# shipped pack names nearest, so the dense pack that names nothing comes
	# from a fixture.
	var unstated := func(m: Dictionary) -> void: m.erase("filter")
	_eq(
		ArtPack.from_manifest(_mutated_pack("no-filter", unstated, _dense_pack(4))).filter,
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"a dense pack that names no filter is minified through its mipmaps"
	)
	_eq(
		ArtPack.from_manifest(_mutated_pack("no-filter-flat", unstated, _dense_pack(1))).filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"and a density 1 one is only ever magnified, so nearest"
	)
	# The name is what the top bar shows; a pack that gives none is its own id.
	var nameless := func(m: Dictionary) -> void: m.erase("name")
	_eq(ArtPack.from_manifest(_mutated_pack("nameless", nameless)).display_name, "daylight", "no name means the id")


## The same manifest read from res:// and from a directory outside it gives the
## same pack: one reader, two ways of reaching the bytes.
func test_loose_and_res_packs_read_the_same() -> void:
	var shipped := ArtPack.from_manifest(MANIFEST)
	# The same pack at the same density and sampling (nearest), written
	# outside res://.
	var loose := ArtPack.from_manifest(_dense_pack(shipped.density))
	_eq([loose.id, loose.display_name], [shipped.id, shipped.display_name], "same identity")
	_eq([loose.density, loose.filter], [shipped.density, shipped.filter], "same density and sampling")
	_eq([loose.tile_size, loose.atlas_size], [shipped.tile_size, shipped.atlas_size], "same tile geometry")
	_eq(loose.palette, shipped.palette, "same palette")
	_eq(loose.tiles, shipped.tiles, "same atlas cells")
	# JSON.stringify sorts its keys, so the fixture's manifest lists them in a
	# different order than the shipped one: the set is what has to match.
	_eq(_sorted_names(loose.props), _sorted_names(shipped.props), "same props")
	_eq(_sorted_names(loose.ui), _sorted_names(shipped.ui), "same UI images")
	for id in shipped.ui:
		_eq(
			[loose.ui[id].path, loose.ui[id].size, loose.ui[id].pivot],
			[shipped.ui[id].path, shipped.ui[id].size, shipped.ui[id].pivot],
			"ui/%s reads the same either way" % id
		)
	_eq(
		[loose.panel().patch_left, loose.panel().patch_bottom],
		[shipped.panel().patch_left, shipped.panel().patch_bottom],
		"including the nine-patch margins"
	)
	for name in shipped.states:
		_eq(
			[loose.state(name).animation, loose.state(name).badge, loose.state(name).label],
			[shipped.state(name).animation, shipped.state(name).badge, shipped.state(name).label],
			"state %s reads the same either way" % name
		)
	_eq([loose.stale_tint, loose.task_lights], [shipped.stale_tint, shipped.task_lights], "same optional keys")
	# The pixel people are the same shared res:// family whichever way the pack
	# came; the fixture ships no table of its own, and ArtContract says so.
	_eq(
		[loose.people.density, loose.people.filter, loose.people.files],
		[shipped.people.density, shipped.people.filter, shipped.people.files],
		"the shared pixel people are the same either way"
	)
	_check(loose.people.agent_catalog == loose.agent_catalog, "and resolve looks against the pack's own catalog")
	# Both hand out the panel they were asked for, one imported, one read as is.
	_check(
		loose.sprite_texture(loose.panel()).get_size() == shipped.sprite_texture(shipped.panel()).get_size(),
		"and both draw the panel at the same size"
	)


## Schema 1 is density 1, nearest, and names neither; schema 2 names a density.
## The shipped default is schema 2 density 2 nearest, while the contract still keeps old packs readable,
## still accepts the other densities and refuses malformed combinations.
func test_art_contract() -> void:
	var shipped_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var v1 := shipped_data.duplicate(true)
	v1.schema_version = 1
	v1.erase("density")
	v1.erase("filter")
	_eq(ArtPack.contract_error(v1), "", "a legacy schema 1 pack")
	var shipped := ArtPack.from_manifest(MANIFEST)
	_eq(
		[shipped.density, shipped.filter],
		[ArtFamily.whole(shipped_data.get("density")), CanvasItem.TEXTURE_FILTER_NEAREST],
		"the shipped pack is read at the density its manifest declares, sampled nearest"
	)
	_eq(
		[shipped.density, shipped_data.get("filter")],
		[2, "nearest"],
		"and that is density 2, named nearest: two texels a unit, so an even zoom lands each on whole screen pixels"
	)
	var with := func(changes: Dictionary) -> Dictionary:
		var manifest := v1.duplicate()
		manifest.merge(changes, true)
		for key: String in changes:
			if changes[key] == null:
				manifest.erase(key)
		return manifest
	# JSON numbers are floats; a whole float is the same number.
	for density: float in [1.0, 2.0, 4.0, 8.0]:
		_eq(
			ArtPack.contract_error(with.call({"schema_version": 2.0, "density": density})),
			"",
			"schema 2, density %d" % density
		)
	_eq(
		ArtPack.contract_error(with.call({"schema_version": 2, "density": 4, "filter": "linear"})),
		"",
		"schema 2, linear"
	)
	var refused := {
		"schema 3": {"schema_version": 3},
		"schema as text": {"schema_version": "2", "density": 2},
		"no schema": {"schema_version": null},
		"schema 1 with density": {"density": 2},
		"schema 1 with filter": {"filter": "nearest"},
		"schema 2 without density": {"schema_version": 2, "filter": "nearest"},
		"density 3": {"schema_version": 2, "density": 3},
		"density 16": {"schema_version": 2, "density": 16},
		"density 2.5": {"schema_version": 2, "density": 2.5},
		"density as text": {"schema_version": 2, "density": "2"},
		"filter bilinear": {"schema_version": 2, "density": 2, "filter": "bilinear"},
		"density 1 linear": {"schema_version": 2, "density": 1, "filter": "linear"},
	}
	for name: String in refused:
		_check(not ArtPack.contract_error(with.call(refused[name])).is_empty(), "refuses " + name)
	_check(not ArtPack.contract_error([]).is_empty(), "refuses a manifest that is not an object")
	var legacy := func(m: Dictionary) -> void:
		m.schema_version = 1
		m.erase("density")
		m.erase("filter")
	var loaded := ArtPack.from_manifest(_mutated_pack("legacy", legacy, _dense_pack(1)))
	_check(loaded != null, "a real schema 1 pack with density-1 PNGs still loads")
	if loaded != null:
		_eq(loaded.tileset().tile_size, Vector2i(32, 32), "legacy tiles draw at their original size")


## The other direction of the same contract: what a pack carries that no scene
## asks for. `make check-packs` prints it for every pack without failing, so an
## asset going cold is noticed here instead of by grepping the scenes.
func test_art_contract_names_ids_no_scene_asks_for() -> void:
	var shipped := ArtPack.from_manifest(MANIFEST)
	var unused := ArtContract.unused(shipped)
	_eq(_sorted_names(unused), ["props", "table", "tiles", "ui"], "every category is reported")
	_eq(
		Array(unused[&"tiles"]),
		["wall.front_center", "wall.front_left", "wall.front_right", "wall.threshold"],
		"the front wall nothing lays: it would cover the near seats (docs/WORLD_MODEL.md)"
	)
	# The pods of desks draw the pod's art (lane B1); what the long table, the
	# big paper stack and the big selection frame drew is shipped and drawn by
	# nothing now, until lane C prunes it from the pack; the zone partitions
	# land before lane B2 draws them: exactly these ids.
	_eq(
		Array(unused[&"props"]),
		[
			"done_stack",
			"partition_corner_bl",
			"partition_corner_br",
			"partition_h",
			"partition_h_end_l",
			"partition_h_end_r",
			"partition_post",
			"partition_v",
		],
		"every prop but the long table's paper and the zone partitions is placed somewhere"
	)
	_eq(Array(unused[&"ui"]), ["selection"], "every UI image but the long table's frame is drawn somewhere")
	_eq(
		Array(unused[&"table"]),
		[
			"divider_left",
			"divider_mid",
			"divider_right",
			"leg",
			"surface_left",
			"surface_mid_a",
			"surface_mid_b",
			"surface_right",
		],
		"every shared-table module but the long table's is laid or is a furniture view"
	)
	for id in ArtContract.tile_ids():
		_check(not Array(unused[&"tiles"]).has(str(id)), "a wanted tile is never called unused: " + id)
	for id in ArtContract.ui_ids():
		_check(not Array(unused[&"ui"]).has(str(id)), "a wanted UI image is never called unused: " + id)
	var invent_one := func(m: Dictionary) -> void:
		var images: Dictionary = m["ui"]
		var branch: Dictionary = images["branch"]
		images["spare"] = branch.duplicate()
	var spare := ArtPack.from_manifest(_mutated_pack("spare ui", invent_one))
	_check(Array(ArtContract.unused(spare)[&"ui"]).has("spare"), "an id a pack invents is reported")
	_eq(_sorted_names(ArtContract.unused(null)), [], "a pack that did not load reports nothing")


## Textures are handed out exactly as built: for a res:// pack the very object
## load() returns, with whatever mipmaps its family's import rule gave it, so
## nothing here depends on the screen. The shipped pack, its table (density 2)
## and the pixel people (density 1) sample nearest and are never minified (the
## smallest zoom is 2: a density-2 texel is one screen pixel), so they import
## without mipmaps; the provider logos are minified by the Avatar Studio
## and import with them. A pack outside res:// has no import, so a linear one
## has its mipmaps built as it is read.
func test_art_textures_as_built() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var base := MANIFEST.get_base_dir()
	_check(
		art.sprite_texture(art.prop_sprite(&"cabinet")) == load(base.path_join(art.props[&"cabinet"].path)),
		"a prop is the imported resource itself"
	)
	var shipped_atlas: TileSetAtlasSource = art.tileset().get_source(0)
	_check(shipped_atlas.texture == load(base.path_join(art.atlas_path)), "so is the tile atlas")
	_check(art.agent_badge(&"codex") == load("res://assets/agent_badges/codex.png"), "so is a provider logo")
	var desk_look := art.people.look_for("codex", AvatarLook.facing(AvatarLook.DESK, &""))
	var region := art.people.layer_texture(PixelPeople.BODY, desk_look, PixelPeople.FRONT) as AtlasTexture
	_check(
		region != null and region.atlas == load(PixelPeople.ROOT + "front.png"),
		"so is a pixel people sheet: a strip is a region of the imported sheet itself"
	)
	# Every texture the shipped pack draws, and whether its import gave it
	# mipmaps. The pack's own art, its table and the pixel people are nearest
	# families never minified (the smallest zoom is 2, a density-2 texel one
	# screen pixel), and NEAREST at or above 1:1 never reads a mip level, so
	# their imports make none (a mip chain there is
	# memory spent on nothing). The provider logos are the other rule: the
	# Avatar Studio shows them scaled down, and TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# quietly samples plain linear when a texture has none, so one missed
	# .import would pass every other check and only show up on screen.
	var drawn: Dictionary[String, Texture2D] = {}
	for id in art.props:
		drawn["props/%s" % id] = art.sprite_texture(art.props[id])
	for id in art.ui:
		drawn["ui/%s" % id] = art.sprite_texture(art.ui[id])
	drawn["atlas"] = shipped_atlas.texture
	for id in art.table.modules:
		drawn["table/" + id] = art.table.module_texture(id)
	for sheet in art.people.files:
		drawn["people/" + sheet] = art.people.texture(sheet)
	for where: String in drawn:
		var texture := drawn[where]
		_check(
			texture != null and not texture is ImageTexture, where + ": handed out as imported, never rebuilt in memory"
		)
		# CompressedTexture2D.has_mipmaps() answers for its RID, not the import.
		_check(
			not texture.get_image().has_mipmaps(),
			where + ": a nearest family is never minified, so it imports without mipmaps"
		)
	for id in AgentCatalog.new().ids():
		var logo := art.agent_badge(StringName(id))
		_check(logo != null and not logo is ImageTexture, "logo/%s: handed out as imported" % id)
		if logo != null:
			_check(logo.get_image().has_mipmaps(), "logo/%s: a minified family imports with mipmaps" % id)
	var flat := ArtPack.from_manifest(_dense_pack(1))
	_eq(flat.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "a density 1 pack samples nearest")
	_eq(flat.tileset().tile_size, Vector2i(32, 32), "its tiles stay the 32px it built")
	_eq(flat.sprite_texture(flat.panel()).get_size(), Vector2(32, 32), "and its panel 32px")
	_check(
		not flat.sprite_texture(flat.panel()).get_image().has_mipmaps(),
		"a nearest pack is only ever magnified, so it needs none"
	)
	var loose := ArtPack.from_manifest(_dense_pack(2, "linear"))
	_eq(loose.filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "a linear pack samples through mipmaps")
	_check(
		loose.sprite_texture(loose.panel()).get_image().has_mipmaps(),
		"a loose linear pack has no import, so they are built as it loads"
	)
	var dense := ArtPack.from_manifest(_dense_pack(8))
	_eq(dense.tileset().tile_size, Vector2i(256, 256), "a density 8 pack holds 256px tiles whatever the screen shows")
	_eq(dense.unit_scale(), Vector2.ONE / 8.0, "and scales every node it hands out back by 1/8")
	# The filter follows the family the texture came from, exactly as the
	# density does. The pack's own `filter` governs the pack's own art only:
	# the shared table is sampled on its own terms, and the pixel people are
	# only ever magnified, nearest, whatever the pack around them samples.
	# Everything shipped samples nearest (the pack and its table at density 2,
	# the people at 1), so the families that disagree come from the linear
	# fixture and from the family rule itself.
	_eq(art.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "the shipped pack names nearest and samples it")
	_eq(art.people.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "so do the density 1 pixel people inside it")
	_eq(art.table.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "and its shared table, which names nearest too")
	_eq(
		loose.people.filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"a linear pack's pixel people still sample nearest: the family decides, not the pack"
	)
	_eq(
		ArtFamily.read_filter({"density": 4}),
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"and a denser companion family that names no filter is minified through its mipmaps"
	)
	_eq(flat.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "a density 1 pack still draws its own 32px art nearest")
	_eq(
		ArtFamily.read_filter({"density": 1}),
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"a density 1 family is only magnified by whole numbers"
	)
	_eq(
		ArtFamily.read_filter({"density": 4, "filter": "nearest"}),
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"a family that names nearest keeps nearest"
	)
	_eq(
		ArtFamily.read_filter({}),
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"a family with no manifest at all reads as density 1"
	)
	_eq(
		[art.density, dense.density, dense.people.density, ArtFamily.read_density({})],
		[ArtFamily.whole(ArtFamily.read_json(MANIFEST).get("density")), 8, art.people.density, 1],
		"density comes from the same family, never from the pack around it: an 8x pack's people are the people's own"
	)
	# A pack that ships no table is still a pack: the density fixtures draw
	# props and tiles with one. It is ArtContract that refuses to furnish a
	# floor from it.
	_eq(flat.table.modules.size(), 0, "a fixture pack has no shared table")
	_eq(flat.table.density, 1, "and its empty table family reads as density 1, nearest")
	_eq(flat.table.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "sampled nearest like any density 1 family")


## The import rule is per family, never per file (docs/ASSET_SPEC.md): a PNG
## under res://assets has mipmaps exactly when its family is minified. The
## family's own manifest (the nearest one above the PNG) says how it is
## sampled; a nearest family (density 1 or 2) is never minified, since the
## smallest zoom is 2, so it never reads a mip level. The provider logos have no
## manifest and are the one family drawn smaller than built (the Avatar Studio's
## list). Anything else is a PNG no family owns. A new PNG gets the project
## default, which is the nearest families' rule.
func test_imports_follow_their_family() -> void:
	var defaults: Variant = ProjectSettings.get_setting("importer_defaults/texture", {})
	_check(defaults is Dictionary, "the project names texture importer defaults")
	if defaults is Dictionary:
		var texture_defaults: Dictionary = defaults
		_eq(texture_defaults.get("mipmaps/generate"), false, "a new PNG imports as a nearest family: no mipmaps")
	var counted: Dictionary[bool, int] = {true: 0, false: 0}
	for path in _pngs("res://assets"):
		var minified: bool
		var manifest := _family_manifest(path)
		if path.begins_with(ArtPack.BADGE_ROOT):
			minified = true
		elif manifest.is_empty():
			_check(false, path + ": belongs to no family (no manifest above it)")
			continue
		else:
			var sampled := ArtFamily.read_filter(ArtFamily.read_json(manifest))
			minified = sampled == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var texture := load(path) as Texture2D
		_check(texture != null, path + ": imports")
		if texture == null:
			continue
		counted[minified] += 1
		_eq(
			texture.get_image().has_mipmaps(),
			minified,
			(
				"%s: mipmaps exactly when its family (%s) is minified"
				% [path, "logos" if manifest.is_empty() else manifest]
			)
		)
	_check(counted[false] > 0 and counted[true] > 0, "both rules are exercised: %s" % counted)
	for family: String in [MANIFEST, PixelPeople.MANIFEST]:
		_eq(
			ArtFamily.read_filter(ArtFamily.read_json(family)),
			CanvasItem.TEXTURE_FILTER_NEAREST,
			family + " is a nearest family, never minified, so its PNGs import without mipmaps"
		)


## Whatever the density, a node the pack hands out covers the same density-1
## rectangle: pivot at the node's position, cells on the 32px grid, panels at
## their bounds with margins in proportion.
func test_art_nodes() -> void:
	var packs := [
		["density 1", ArtPack.from_manifest(_dense_pack(1))],
		["density 2", ArtPack.from_manifest(_dense_pack(2))],
		["density 4", ArtPack.from_manifest(_dense_pack(4))],
		["density 8", ArtPack.from_manifest(_dense_pack(8))],
		["density 2 linear", ArtPack.from_manifest(_dense_pack(2, "linear"))]
	]
	for entry: Array in packs:
		var name: String = entry[0]
		var art: ArtPack = entry[1]
		var density: int = art.density
		var pen := OfficeDraw.new(art)
		var parent := Control.new()
		var desk := pen.prop(parent, &"cabinet", Vector2(100, 200))
		var spec := art.prop_sprite(&"cabinet")
		var size := Vector2(spec.size)
		var pivot := spec.pivot
		_eq(desk.texture.get_size(), size * density, name + ": desk texture")
		_eq(desk.scale, Vector2.ONE / density, name + ": desk scale")
		_eq(desk.offset, -pivot * density, name + ": desk offset")
		_eq(desk.transform * desk.offset, Vector2(100, 200) - pivot, name + ": desk top-left sits pivot above its spot")
		_eq(
			desk.transform * (desk.offset + desk.texture.get_size()),
			Vector2(100, 200) - pivot + size,
			name + ": desk covers its density-1 size"
		)
		# The pixel people are their own family: they keep the density their own
		# manifest declares, whatever the pack around them.
		var portrait := pen.portrait(parent, "claude", ArtContract.ANIMATION_WORKING, Vector2(40, 60))
		var strip: Sprite2D = portrait.get_node(PixelPeople.SPRITES[PixelPeople.BODY])
		var people_density: int = art.people.density
		_eq(
			Vector2(strip.texture.get_size().x / art.people.columns, strip.texture.get_size().y),
			Vector2(art.people.frame_size) * people_density,
			name + ": person frame"
		)
		_eq(strip.offset * strip.scale, -art.people.pivot, name + ": person pivot")
		portrait.scale *= 2
		_eq(
			strip.offset * strip.scale * portrait.scale,
			-art.people.pivot * 2,
			name + ": a doubled portrait keeps its pivot"
		)
		var tiles := pen.layer(parent, Vector2(16, 48))
		_eq(tiles.tile_set.tile_size, Vector2i(32, 32) * density, name + ": tile size")
		_eq(
			tiles.transform * tiles.map_to_local(Vector2i(3, 2)),
			Vector2(16, 48) + Vector2(3 * 32 + 16, 2 * 32 + 16),
			name + ": cell centres on the 32px grid"
		)
		var atlas: TileSetAtlasSource = tiles.tile_set.get_source(0)
		_eq(atlas.texture.get_size(), Vector2(art.atlas_size) * density, name + ": atlas")
		pen.panel(parent, Rect2(40, 50, 144, 300))
		var panel: NinePatchRect = parent.get_children().filter(func(n: Node) -> bool: return n is NinePatchRect)[0]
		_eq(panel.get_rect().position, Vector2(40, 50), name + ": panel position")
		_eq(panel.size * panel.scale, Vector2(144, 300), name + ": panel covers its bounds")
		_eq(
			panel.patch_margin_left * panel.scale.x,
			float(art.panel().patch_left),
			name + ": panel corners keep their density-1 margin"
		)
		_eq(panel.texture.get_size(), Vector2(art.panel().size) * density, name + ": panel texture")
		var filter := (
			CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			if name.ends_with("linear")
			else CanvasItem.TEXTURE_FILTER_NEAREST
		)
		_eq(art.filter, filter, name + ": filter")
		_check(
			[desk.texture_filter, tiles.texture_filter, panel.texture_filter].all(
				func(f: int) -> bool: return f == filter
			),
			name + ": every node of the pack's own art samples the way the pack says"
		)
		_eq(
			strip.texture_filter,
			CanvasItem.TEXTURE_FILTER_NEAREST,
			name + ": but the density 1 pixel people sample on their own terms: nearest"
		)
		parent.free()


## Every agent herdr knows has a logo for the Avatar Studio's list and a whole
## pixel person in every pose the office draws, in options the family draws, its
## clothes the catalog's default for it; an unknown one is the generic person. A
## hood hides the hair, a cap does not, and a strip is the right row of its
## facing's sheet, not a cached other one.
func test_agent_avatar_catalog() -> void:
	var catalog := AgentCatalog.new(_missing_avatars())
	var ids := catalog.ids()
	_eq(ids.size(), 23, "the Herdr catalog contains every supported agent")
	var art := ArtPack.from_manifest(MANIFEST)
	var people := art.people
	people.agent_catalog = catalog
	var strip_size := Vector2(people.columns * people.frame_size.x, people.frame_size.y) * people.density
	for id: String in ids:
		# Exported PNGs are remapped imports: ResourceLoader, never FileAccess.
		_check(ResourceLoader.exists("res://assets/agent_badges/" + id + ".png"), "logo exists for " + id)
		_check(art.agent_badge(StringName(id)) != null, "logo loads for " + id)
		for context in AvatarLook.CONTEXTS:
			for orientation in AvatarLook.ORIENTATIONS:
				var look := people.look_for(id, AvatarLook.facing(context, orientation), "pane-of-" + id)
				var where := "%s %s/%s" % [id, context, orientation]
				_eq([look.context, look.orientation], [context, orientation], where + ": the pose asked for")
				for slot_id in AvatarLook.SLOTS:
					_check(
						people.slots[slot_id].has_option(look.slot(slot_id)),
						"%s: %s is an option the family draws (%s)" % [where, slot_id, look.slot(slot_id)]
					)
				var provided := catalog.default_look(id)
				for slot_id: StringName in [AvatarLook.TOP, AvatarLook.LEGS, AvatarLook.HEADWEAR]:
					_eq(
						look.slot(slot_id),
						provided.slot(slot_id),
						"%s: %s is the provider's default" % [where, slot_id]
					)
				for layer: StringName in [PixelPeople.LEGS, PixelPeople.TOP, PixelPeople.BODY]:
					var strip := people.layer_texture(layer, look, orientation)
					_check(
						strip != null and strip.get_size() == strip_size,
						"%s: a whole %s strip, every frame of every track" % [where, layer]
					)
	# A future herdr provider still gets a whole generic person, and no logo.
	var odd := AvatarLook.with_slots({AvatarLook.TOP: &"sequins", AvatarLook.HAIR_STYLE: &"mohawk"})
	var unknown := people.look_for("future-agent", odd)
	_eq(
		[unknown.top, unknown.hair_style],
		[people.default_look.top, people.default_look.hair_style],
		"undrawn options fall back"
	)
	_eq(people.look_for("future-agent").badge, &"generic", "an unknown provider is the generic agent")
	_check(art.agent_badge(&"generic") == null, "which has no logo")
	_eq(catalog.default_look("codex").headwear, &"cap", "codex wears the cap it always did")
	_eq(catalog.default_look("pi").headwear, &"hood", "and pi the hood")
	for orientation in AvatarLook.ORIENTATIONS:
		for colour in people.slots[AvatarLook.HEADWEAR_COLOUR].swatches:
			var hooded := people.look_for(
				"generic", AvatarLook.with_slots({AvatarLook.HEADWEAR: &"hood", AvatarLook.HEADWEAR_COLOUR: colour})
			)
			var name := "headwear_hood_%s" % colour
			_eq(people.strip_name(PixelPeople.HEADWEAR, hooded), name, "the hood in its own colour")
			_eq(people.layer_texture(PixelPeople.HAIR, hooded, orientation), null, "a hood hides the hair")
			var actual := people.layer_texture(PixelPeople.HEADWEAR, hooded, orientation)
			var sheet := people.texture("%s.png" % orientation).get_image()
			var row := people.strips.find(name)
			var reference := sheet.get_region(Rect2i(0, row * int(strip_size.y), int(strip_size.x), int(strip_size.y)))
			_check(
				actual != null and actual.get_image().get_data() == reference.get_data(),
				"the selected hood's row, not a cached other one: %s %s" % [orientation, name]
			)
			hooded.headwear = &"cap"
			_check(people.layer_texture(PixelPeople.HAIR, hooded, orientation) != null, "a cap shows the hair")


## A saved-looks path under the work directory that nothing has written: these
## cases must not read the developer's own saved looks.
func _missing_avatars() -> String:
	return OS.get_temp_dir().path_join("herdstead-test-no-avatars-%d.json" % OS.get_process_id())


## The pixel people, their one animation library and the state -> track
## mapping every worker plays through. The pixel people and the shared table
## are families of their own: each keeps its own density whatever the pack
## around them is built at.
func test_avatar_layers_and_tracks() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var people := art.people
	var seated := people.look_for("codex", AvatarLook.facing(AvatarLook.DESK, &""))
	var body := people.layer_texture(PixelPeople.BODY, seated, PixelPeople.FRONT)
	_eq(art.table.density, art.density, "the shared table is at the pack's density: the two flip together")
	_eq(
		[art.density, art.table.density, people.density],
		[2, 2, 2],
		"the pack, its table and the pixel people all ship at density 2, each on its own terms"
	)
	_eq(
		body.get_size(),
		Vector2(people.columns * people.frame_size.x, people.frame_size.y) * people.density,
		"a layer strip holds every frame of every track, at the family's texels per unit"
	)
	_check(not body is ImageTexture, "handed out as imported, not resampled into a new one")
	_eq(
		art.table.module_texture(&"surface_left").get_size(),
		Vector2(32, 80) * art.table.density,
		"a table module is its size in units at the table's density"
	)
	_check(art.table.module_texture(&"no_such_module") == null, "an unknown module is null, not a crash")
	var library := people.animation_library()
	_check(people.animation_library() == library, "one animation library for the pack's people")
	var names: Array = Array(library.get_animation_list()).map(func(n: StringName) -> String: return str(n))
	names.sort()
	var tracks: Array = []
	for id in people.tracks:
		tracks.append(str(id))
	tracks.sort()
	_eq(names, tracks, "an animation per manifest track")
	var work := library.get_animation(&"desk_work")
	var entry := people.tracks[&"desk_work"]
	_eq(work.loop_mode, Animation.LOOP_LINEAR, "desk_work loops")
	_eq(work.get_track_count(), PixelPeople.LAYERS.size(), "one value track per layer")
	_eq(
		work.track_get_path(0),
		NodePath(PixelPeople.SPRITES[PixelPeople.LAYERS[0]] + ":frame"),
		"keyed on the layer's frame"
	)
	_eq(work.value_track_get_update_mode(0), Animation.UPDATE_DISCRETE, "frames step, never blend")
	var last := work.get_track_count() - 1
	var times: Array = []
	var values: Array = []
	for key in work.track_get_key_count(last):
		times.append(snappedf(work.track_get_key_time(last, key), 0.001))
		values.append(work.track_get_key_value(last, key))
	var frames: Array = []
	var starts: Array = []
	for index in entry.frame_count():
		frames.append(entry.frame(index))
		starts.append(snappedf(entry.starts_at(index), 0.001))
	_eq(values, frames, "desk_work's frames, on the top layer as on the bottom one")
	_eq(times, starts, "at the cumulative durations")
	_eq(snappedf(work.length, 0.001), snappedf(entry.length(), 0.001), "the track lasts its durations")
	_eq(
		[
			people.track(AvatarLook.DESK, ArtContract.ANIMATION_WORKING),
			people.track(AvatarLook.STAND, ArtContract.ANIMATION_BLOCKED),
			people.track(AvatarLook.DESK, art.animation_for_state(ArtContract.STATE_DONE)),
			people.track(AvatarLook.STAND, art.animation_for_state(ArtContract.STATE_DONE))
		],
		[&"desk_work", &"stand_blocked", &"desk_idle", &"stand_idle"],
		"states map through state_tracks; a done worker stands idle"
	)
	_eq(
		art.animation_for_state(ArtContract.STATE_IDLE, true),
		ArtContract.ANIMATION_STARTING,
		"a launching pane shows the starting pose"
	)
	_eq(art.animation_for_state("some-new-state"), "idle", "a state the pack does not know is idle")


# --- harness --------------------------------------------------------------------


## The ids of a typed art dictionary, sorted, for a comparison that does not
## depend on the order a manifest happened to list them in.
func _sorted_names(entries: Dictionary) -> Array:
	var result: Array = []
	for id: StringName in entries:
		result.append(str(id))
	result.sort()
	return result


## Every PNG under `directory`, recursively, as res:// paths.
func _pngs(directory: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".png"):
			found.append(directory.path_join(file))
	for sub in DirAccess.get_directories_at(directory):
		found.append_array(_pngs(directory.path_join(sub)))
	return found


## The manifest of the family a PNG belongs to: the nearest `*manifest.json`
## in its directory or above it, up to res://assets; empty when there is none.
func _family_manifest(png: String) -> String:
	var directory := png.get_base_dir()
	while directory.begins_with("res://assets/"):
		for file in DirAccess.get_files_at(directory):
			if file.ends_with("manifest.json"):
				return directory.path_join(file)
		directory = directory.get_base_dir()
	return ""


## A drawable pack copied before mutation: a rejection must be caused by the
## changed field, never by unrelated missing images. No tracked art is edited.
func _mutated_pack(name: String, change: Callable, source := MANIFEST) -> String:
	var root_dir := work_dir.path_join("pack-" + name.replace(" ", "-"))
	var manifest_path := root_dir.path_join("manifest.json")
	var base := source.get_base_dir()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	var paths: Array = [data.atlas, data.font.path, data.font.license]
	if data.has("display_font"):
		paths.append_array([data.display_font.path, data.display_font.license])
	for category: String in ["props", "ui"]:
		for spec: Dictionary in _dict(data, category).values():
			paths.append(spec.path)
	for path: String in paths:
		DirAccess.make_dir_recursive_absolute(root_dir.path_join(path).get_base_dir())
		_check(DirAccess.copy_absolute(base.path_join(path), root_dir.path_join(path)) == OK, "fixture copies " + path)
	change.call(data)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return manifest_path


func _dense_pack(density: int, filter := "nearest") -> String:
	var root_dir := work_dir.path_join("pack-x%d-%s" % [density, filter])
	var manifest_path := root_dir.path_join("manifest.json")
	if FileAccess.file_exists(manifest_path):
		return manifest_path
	var base := MANIFEST.get_base_dir()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var source_density := int(_number(data, "density", 1))
	var images: Array = [data.atlas]
	for category: String in ["props", "ui"]:
		for id: String in data[category]:
			images.append(data[category][id].path)
	for path: String in images:
		# get_image() can be the texture's own image: resize a copy.
		var image: Image = (load(base.path_join(path)) as Texture2D).get_image().duplicate()
		var target_size := Vector2i(
			image.get_width() / source_density * density, image.get_height() / source_density * density
		)
		image.resize(target_size.x, target_size.y, Image.INTERPOLATE_NEAREST)
		DirAccess.make_dir_recursive_absolute(root_dir.path_join(path).get_base_dir())
		image.save_png(root_dir.path_join(path))
	for face: String in ["font", "display_font"]:
		if not data.has(face):
			continue
		var font_path := str(_dict(data, face).get("path", ""))
		DirAccess.make_dir_recursive_absolute(root_dir.path_join(font_path).get_base_dir())
		var font := FileAccess.open(root_dir.path_join(font_path), FileAccess.WRITE)
		font.store_buffer(FileAccess.get_file_as_bytes(base.path_join(font_path)))
		font.close()
		var license_path := str(_dict(data, face).get("license", ""))
		DirAccess.copy_absolute(base.path_join(license_path), root_dir.path_join(license_path))
	data.schema_version = 2
	data.density = density
	data.filter = filter
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return manifest_path
