class_name ArtPack
extends ArtFamily
## The single visual boundary. Scene code uses semantic IDs, never image regions.
##
## A pack is read from its manifest once, into typed fields; nothing outside
## from_manifest() ever touches the parsed JSON. It is a Resource only so that a
## loader could one day be hung on it: packs are written by people and the
## Python builders, and loose packs (`--pack=/abs/path`, the fixtures) have to
## come from JSON anyway, so nothing here is authored in the Godot editor.
##
## The pack, the shared pixel people and the shared table are three families
## (see ArtFamily); this one is the pack's own art.

## Dim applied when herdr is unreachable, for packs that do not name their own.
const STALE_DEFAULT := Color(0.65, 0.65, 0.65)
## How hard the desk lamps and their contact shadows are drawn. A lamp-lit
## studio theme says "strong"; a pack that says nothing gets daylight.
const TASK_LIGHTS_SOFT := &"soft"
const TASK_LIGHTS_STRONG := &"strong"
const TASK_LIGHTS: Array[StringName] = [TASK_LIGHTS_SOFT, TASK_LIGHTS_STRONG]
const BADGE_ROOT := "res://assets/agent_badges/"
## A colour no pack holds, drawn when scene code asks for a key the pack lacks:
## a missing colour is a bug to see, not one to blend in.
const MISSING_COLOR := Color.MAGENTA

var id := &""
var display_name := ""
var tile_size := 32
var atlas_size := Vector2i.ZERO
## The tile atlas image, relative to base_path.
var atlas_path := ""
var palette: Dictionary[StringName, Color] = {}
## Semantic tile id -> its cell in the atlas.
var tiles: Dictionary[StringName, Vector2i] = {}
var props: Dictionary[StringName, ArtSprite] = {}
var ui: Dictionary[StringName, ArtSprite] = {}
var states: Dictionary[StringName, ArtState] = {}
var font: Font
var font_path := ""
## The font's licence, which ships beside it and may not be dropped.
var font_license_path := ""
## The optional pixel face for the HUD's few fixed ASCII headings (the
## wordmark, SPACES, NEWS, NEXT); null when the manifest names none. Drawn with
## no antialiasing, at sizes on its own grid (HudTheme.DISPLAY_SIZES).
var display_font: Font
var stale_tint := STALE_DEFAULT
var task_lights := TASK_LIGHTS_SOFT
## The pixel people every theme shares: who sits at a desk, stands in the
## showroom or looks out of the agent card. Never null in a loaded pack; it
## shares this pack's agent_catalog, so a look is resolved against one catalog.
var people: PixelPeople
## This pack's shared table. Never null in a loaded pack; a pack that ships no
## table manifest gets an empty one, and cannot furnish a floor.
var table: TablePack
## Herdr's agent list and the user's own avatar choices.
var agent_catalog: AgentCatalog

var _tiles: TileSet


## Read a pack from its manifest. Null, with a push_error naming the file and
## the problem, when the pack cannot be drawn: callers fall back (the office to
## its default pack, a tool to a non-zero exit). Nothing here asserts, because
## `--export-release` strips assert() and a bad pack must still fail loudly.
static func from_manifest(path: String) -> ArtPack:
	if not FileAccess.file_exists(path):
		push_error("Art pack %s: no such manifest" % path)
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var problem := contract_error(data)
	if not problem.is_empty():
		push_error("Art pack %s: %s" % [path, problem])
		return null
	var manifest: Dictionary = data
	var result := ArtPack.new()
	result.base_path = path.get_base_dir()
	result.density = maxi(1, whole(manifest.get("density", 1)))
	# The pack's own art follows the same rule as every other family: density 1
	# is only magnified by whole numbers, denser art is minified through mipmaps
	# unless the manifest names a filter. A built manifest always names one.
	result.filter = read_filter(manifest)
	problem = result._read(manifest)
	if not problem.is_empty():
		push_error("Art pack %s: %s" % [path, problem])
		return null
	return result


## Why this manifest is not a contract the runtime can draw; empty when it is.
## Schema 1 carries neither `density` nor `filter` and means density 1, nearest.
static func contract_error(manifest: Variant) -> String:
	if not manifest is Dictionary:
		return "manifest is not a JSON object"
	var data: Dictionary = manifest
	var schema := _whole_unit(data.get("schema_version"))
	if schema != 1 and schema != 2:
		return "schema_version %s is not 1 or 2" % str(data.get("schema_version"))
	if schema == 1:
		if data.has("density") or data.has("filter"):
			return "schema 1 declares density or filter; those need schema 2"
		return ""
	var value := _whole_unit(data.get("density"))
	if not DENSITIES.has(value):
		return "density %s is not one of 1, 2, 4, 8" % str(data.get("density"))
	var kind: Variant = data.get("filter", "nearest" if value == 1 else "linear")
	if not kind is String or not FILTERS.has(kind):
		return 'filter %s is not "nearest" or "linear"' % str(kind)
	if value == 1 and kind != "nearest":
		return "density 1 must be nearest"
	return ""


## The pack's colour for a palette key. A key the pack has no colour for is a
## bug in the scene, not in the pack: it is reported and drawn magenta, so it
## shows on screen instead of silently reading as black.
func color(key: StringName) -> Color:
	if not palette.has(key):
		push_error('Art pack %s: no palette colour named "%s"' % [id, key])
		return MISSING_COLOR
	return palette[key]


## The cell of a semantic tile id, e.g. "floor.wood_a" or "wall.cap_left".
func cell(tile: StringName) -> Vector2i:
	if not tiles.has(tile):
		push_error('Art pack %s: no tile named "%s"' % [id, tile])
		return Vector2i.ZERO
	return tiles[tile]


## A UI image by its semantic id. Null for an id this pack has no image for;
## the fixed ones (the panel, the selection mark) have accessors of their own.
func ui_sprite(sprite_id: StringName) -> ArtSprite:
	return ui[sprite_id] if ui.has(sprite_id) else null


func prop_sprite(sprite_id: StringName) -> ArtSprite:
	return props[sprite_id] if props.has(sprite_id) else null


## Every prop drawn from `group` (ItemSpec.group), by id: the pools the table
## and the floor planners draw from by weight. By id, never by where a manifest
## happens to list them: a tool that writes JSON with its keys sorted must not
## change what a table draws.
func items_in(group: StringName) -> Array[ArtSprite]:
	var found: Array[ArtSprite] = []
	for sprite_id in props:
		var member := props[sprite_id]
		if member.item != null and member.item.group == group:
			found.append(member)
	found.sort_custom(func(a: ArtSprite, b: ArtSprite) -> bool: return str(a.id) < str(b.id))
	return found


## One of `items` by their weights, from `rng`: with equal weights this is one
## randi_range() over them, so a table's picture keeps its old choices.
static func pick(items: Array[ArtSprite], rng: RandomNumberGenerator) -> ArtSprite:
	var total := 0
	for member in items:
		total += member.item.weight
	if total <= 0:
		return null
	var roll := rng.randi_range(0, total - 1)
	for member in items:
		roll -= member.item.weight
		if roll < 0:
			return member
	return null


## The light nine-patch the world's and the tools' panels are drawn from (the
## blocked chip, the Avatar Studio). Never null in a valid pack.
func panel() -> ArtSprite:
	return ui_sprite(ArtContract.UI_PANEL)


## The dark nine-patch every HUD panel is drawn from (HdPanel). Never null in a
## valid pack.
func hud_panel() -> ArtSprite:
	return ui_sprite(ArtContract.UI_HUD_PANEL)


## The frame drawn around the selected seat. Never null in a valid pack.
func selection_mark() -> ArtSprite:
	return ui_sprite(ArtContract.UI_SELECTION_SEAT)


## What one herdr state looks like here, or null when the pack does not draw it
## (`starting` and `offline` are display overlays, not herdr states).
func state(name: StringName) -> ArtState:
	return states[name] if states.has(name) else null


## Every herdr state this pack draws, which is what the projection is allowed to
## show.
func state_names() -> PackedStringArray:
	var result := PackedStringArray()
	for name in states:
		result.append(str(name))
	return result


## One of this pack's images as built. Null when the pack has no such image.
func sprite_texture(spec: ArtSprite) -> Texture2D:
	return texture(spec.path) if spec != null else null


## A prop or UI image as a Sprite2D with the pack's convention: origin at the
## image's pivot, scaled back to density-1 units.
func sprite(spec: ArtSprite) -> Sprite2D:
	var result := Sprite2D.new()
	dress(result, sprite_texture(spec), spec.pivot if spec != null else Vector2.ZERO)
	return result


## Herdr's state as one of the pack's semantic animations (idle, working,
## blocked, starting). `offline` has no animation: callers pause the person.
func animation_for_state(name: StringName, starting := false) -> StringName:
	if starting:
		return ArtContract.ANIMATION_STARTING
	var drawn := state(name)
	return drawn.animation if drawn != null else ArtContract.ANIMATION_IDLE


## Tiles are `tile_size * density` pixels; OfficeDraw.layer() scales the layer back.
func tileset() -> TileSet:
	if _tiles:
		return _tiles
	var image := texture(atlas_path)
	if image == null:
		push_error("Art pack %s: atlas %s did not load" % [id, atlas_path])
		return null
	var result := TileSet.new()
	result.tile_size = Vector2i(tile_size, tile_size) * density
	result.add_custom_data_layer()
	result.set_custom_data_layer_name(0, "semantic_id")
	result.set_custom_data_layer_type(0, TYPE_STRING)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = image
	atlas.texture_region_size = result.tile_size
	# Padding extrudes every cell's edge inside a copy of the atlas. It is there
	# for a linear dense pack: at a content scale that is not a whole factor of
	# the cell (scale 3 on a 128px cell), a bilinear tap at the cell edge reads
	# the neighbouring tile, and a seam runs down the whole tile. The shipped
	# pack is density 2, nearest, and zoom only takes even values, so every
	# texel lands on whole screen pixels and no tap crosses a cell: it no longer
	# needs the padding, which stays harmless. The copy carries no mipmaps, and
	# a nearest family, never minified at zoom 2 or more, reads none anyway.
	# Only a future linear dense pack would want the cells extruded in the built
	# atlas instead (docs/ASSET_SPEC.md), with this turned off.
	atlas.use_texture_padding = true
	result.add_source(atlas, 0)
	for tile in tiles:
		if not atlas.has_room_for_tile(tiles[tile], Vector2i.ONE, 1, Vector2i.ZERO, 1):
			push_error("Art pack %s: cannot create atlas cell %s for %s" % [id, tiles[tile], tile])
			return null
		atlas.create_tile(tiles[tile])
		var tile_data := atlas.get_tile_data(tiles[tile], 0)
		if tile_data == null:
			push_error("Art pack %s: no tile data for %s" % [id, tile])
			return null
		tile_data.set_custom_data("semantic_id", str(tile))
	# Publish only the complete resource, so a failed build can be retried.
	_tiles = result
	return _tiles


# --- provider logos -------------------------------------------------------------


## The provider's logo as built, or null (an unknown provider has none). Nothing
## in the office wears it: at the pixel people's one texture pixel per unit a
## logo cannot be drawn on a person, so the name plate and the outfit colours
## say who sits there. The Avatar Studio lists the agents with it.
func agent_badge(provider: StringName) -> Texture2D:
	var path := BADGE_ROOT + str(provider) + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Every field the manifest carries, in typed form; the reason it cannot be
## drawn, otherwise. The only place a pack's parsed JSON is read.
func _read(manifest: Dictionary) -> String:
	id = read_name(manifest.get("id"))
	if id.is_empty():
		return 'no "id"'
	if not manifest.get("name", str(id)) is String:
		return '"name" is not text'
	display_name = str(manifest.get("name", id))
	# Check before any typed assignment: a Godot type error would abort the
	# reader rather than return a useful rejection to from_manifest().
	for field: String in ["palette", "tiles", "props", "ui", "states", "font"]:
		if not manifest.get(field) is Dictionary:
			return '"%s" is not a JSON object' % field
	var steps: Array[Callable] = [
		_read_palette, _read_tiles, _read_images, _read_states, _read_font, _read_display_font, _read_options
	]
	for step in steps:
		var problem: String = step.call(manifest)
		if not problem.is_empty():
			return problem
	return _read_families()


## The atlas canvas, in whole cells, and its actual density-scaled texture.
func _read_atlas(manifest: Dictionary) -> String:
	tile_size = _whole_unit(manifest.get("tile_size"))
	if tile_size != 32:
		return '"tile_size" must be 32 density-1 units'
	atlas_size = _whole_pair(manifest.get("atlas_size"))
	if atlas_size.x < 1 or atlas_size.y < 1:
		return '"atlas_size" must be a pair of positive whole units'
	if atlas_size.x % tile_size != 0 or atlas_size.y % tile_size != 0:
		return '"atlas_size" must contain whole tile cells'
	atlas_path = str(read_name(manifest.get("atlas")))
	if atlas_path.is_empty():
		return 'no "atlas" image'
	return _image_error(atlas_path, atlas_size)


## The cell each semantic tile occupies in the validated atlas.
func _read_tiles(manifest: Dictionary) -> String:
	var problem := _read_atlas(manifest)
	if not problem.is_empty():
		return problem
	var cells: Dictionary = manifest.get("tiles", {})
	var occupied: Dictionary[Vector2i, String] = {}
	var grid := atlas_size / tile_size
	for tile: String in cells:
		if not cells[tile] is Dictionary:
			return 'tile "%s" is not a JSON object' % tile
		var spec: Dictionary = cells[tile]
		var at := _whole_pair(spec.get("cell"))
		if at.x < 0 or at.y < 0:
			return 'tile "%s" cell must be a pair of nonnegative whole coordinates' % tile
		if at.x >= grid.x or at.y >= grid.y:
			return 'tile "%s" cell %s is outside atlas grid %s' % [tile, at, grid]
		if occupied.has(at):
			return 'tile "%s" duplicates "%s" at atlas cell %s' % [tile, occupied[at], at]
		occupied[at] = tile
		tiles[StringName(tile)] = at
	return ""


## The colours every surface, label and icon in the office takes its look from.
func _read_palette(manifest: Dictionary) -> String:
	var colors: Dictionary = manifest.get("palette", {})
	for key: String in colors:
		if not _is_hex_color(colors[key]):
			return 'palette colour "%s" is not six lowercase hex digits' % key
		var hex: String = colors[key]
		palette[StringName(key)] = Color("#" + hex)
	return ""


## The props that stand on a floor and the UI images that float over it. Both
## are the same shape, so both are read the same way.
func _read_images(manifest: Dictionary) -> String:
	for category: String in ["props", "ui"]:
		var target := props if category == "props" else ui
		var listed: Dictionary = manifest.get(category, {})
		for sprite_id: String in listed:
			if not listed[sprite_id] is Dictionary:
				return "%s/%s is not a JSON object" % [category, sprite_id]
			var spec: Dictionary = listed[sprite_id]
			var read := _read_sprite(StringName(sprite_id), spec)
			if read == null:
				return "%s/%s has invalid image path, size, pivot or nine_patch geometry" % [category, sprite_id]
			var problem := _image_error(read.path, read.size)
			if not problem.is_empty():
				return "%s/%s: %s" % [category, sprite_id, problem]
			if spec.has("item"):
				if category != "props":
					return "%s/%s: only a prop has an item block" % [category, sprite_id]
				read.item = _read_item(spec["item"], read.size)
				if read.item == null:
					return "props/%s: its item block is not one (docs/ITEMS.md)" % sprite_id
			target[read.id] = read
	return ""


## What herdr's states look like here. A state has to name both an animation and
## a badge; ArtContract is what checks they exist.
func _read_states(manifest: Dictionary) -> String:
	var drawn_states: Dictionary = manifest.get("states", {})
	for name: String in drawn_states:
		if not drawn_states[name] is Dictionary:
			return 'state "%s" is not a JSON object' % name
		var spec: Dictionary = drawn_states[name]
		var drawn := ArtState.new()
		drawn.id = StringName(name)
		drawn.animation = read_name(spec.get("animation"))
		drawn.badge = read_name(spec.get("badge"))
		if not spec.get("label", "") is String:
			return 'state "%s" label is not text' % name
		drawn.label = str(spec.get("label", ""))
		if drawn.animation.is_empty() or drawn.badge.is_empty():
			return 'state "%s" names no animation or badge' % name
		states[drawn.id] = drawn
	return ""


## The pack's font, which ships with its licence beside it.
func _read_font(manifest: Dictionary) -> String:
	var font_spec: Dictionary = manifest.get("font", {})
	font_path = str(read_name(font_spec.get("path")))
	font_license_path = str(read_name(font_spec.get("license")))
	if font_path.is_empty() or font_license_path.is_empty():
		return '"font" names no file or no licence'
	font = _load_font(base_path.path_join(font_path))
	if font == null:
		return "font %s did not load" % font_path
	return ""


## The optional display face, which ships with its licence beside it as the
## main font does. Absent is legal (display_font stays null); named, it must load.
func _read_display_font(manifest: Dictionary) -> String:
	if not manifest.has("display_font"):
		return ""
	if not manifest["display_font"] is Dictionary:
		return '"display_font" is not a JSON object'
	var spec: Dictionary = manifest["display_font"]
	var path := str(read_name(spec.get("path")))
	if path.is_empty() or str(read_name(spec.get("license"))).is_empty():
		return '"display_font" names no file or no licence'
	display_font = _load_font(base_path.path_join(path))
	if display_font == null:
		return "display font %s did not load" % path
	if display_font is FontFile:
		# A pixel face: hard edges, whole pixels, whatever the import said.
		var face := display_font as FontFile
		face.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		face.hinting = TextServer.HINTING_NONE
		face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return ""


## The two additive optional keys, documented in docs/ASSET_SPEC.md. Absent is
## legal and documented; a value nobody drew is a contract error, not a default.
func _read_options(manifest: Dictionary) -> String:
	if manifest.has("stale_modulate"):
		if not _is_hex_color(manifest["stale_modulate"]):
			return '"stale_modulate" is not six lowercase hex digits'
		var hex: String = manifest["stale_modulate"]
		stale_tint = Color("#" + hex)
	task_lights = read_name(manifest.get("task_lights", str(TASK_LIGHTS_SOFT)))
	if not TASK_LIGHTS.has(task_lights):
		return '"task_lights" is %s, not "soft" or "strong"' % task_lights
	return ""


## The two companion families and the agent catalog. The pixel people are
## shared res:// art every theme draws, and resolve looks against this pack's
## catalog; the shared table belongs to this pack.
func _read_families() -> String:
	agent_catalog = AgentCatalog.new()
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	if people == null:
		return "the shared pixel people did not load"
	people.agent_catalog = agent_catalog
	var table_manifest := base_path.path_join("table/manifest.json")
	if not FileAccess.file_exists(table_manifest):
		# Legal, and refused by ArtContract: a pack with no table can draw props
		# and tiles (the density fixtures do) but cannot furnish a floor.
		table = TablePack.new()
		table.base_path = table_manifest.get_base_dir()
		return ""
	table = TablePack.from_manifest(table_manifest)
	return "" if table != null else "its shared table did not load"


static func _read_sprite(sprite_id: StringName, spec: Dictionary) -> ArtSprite:
	var result := ArtSprite.new()
	result.id = sprite_id
	result.path = str(read_name(spec.get("path")))
	var size := _whole_pair(spec.get("size"))
	var pivot := _whole_pair(spec.get("pivot"))
	if result.path.is_empty() or size.x < 1 or size.y < 1:
		return null
	# A foot anchor may be exactly on the bottom or right edge.
	if pivot.x < 0 or pivot.y < 0 or pivot.x > size.x or pivot.y > size.y:
		return null
	result.size = size
	result.pivot = pivot
	if spec.has("nine_patch"):
		var margins := read_list(spec["nine_patch"])
		if margins.size() != 4:
			return null
		for margin: Variant in margins:
			if _whole_unit(margin) < 0:
				return null
		result.patch_left = _whole_unit(margins[0])
		result.patch_top = _whole_unit(margins[1])
		result.patch_right = _whole_unit(margins[2])
		result.patch_bottom = _whole_unit(margins[3])
		if result.patch_left + result.patch_right >= size.x or result.patch_top + result.patch_bottom >= size.y:
			return null
	return result


## Validate JSON numbers before Vector2 (float32) rounding or Vector2i wrapping.
## The typed geometry uses signed 32-bit coordinates; -1 is the invalid marker.
## An `item` block (ItemSpec), or null when it is not one: an unknown key, a
## place that is none of the three, a desk or floor item without a footprint or
## one wider than its canvas, `blocks` off the floor, a group that is not an id,
## a weight without a group or not a whole number.
static func _read_item(value: Variant, size: Vector2i) -> ItemSpec:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	for key: Variant in data:
		if not key is String or not ItemSpec.KEYS.has(key):
			return null
	var item := ItemSpec.new()
	item.place = read_name(data.get("place"))
	if not ItemSpec.PLACES.has(item.place):
		return null
	if data.has("footprint"):
		var pair := _whole_pair(data["footprint"])
		if pair.x < 1 or pair.y < 1 or pair.x > size.x:
			return null
		item.footprint = Vector2(pair)
	elif item.place != ItemSpec.PLACE_WALL:
		return null
	item.blocks = item.place == ItemSpec.PLACE_FLOOR
	if data.has("blocks"):
		# Only true for now: nothing a person walks over stands on a floor yet,
		# and the walk graph takes every floor item's footprint as an obstacle.
		if not data["blocks"] is bool or item.place != ItemSpec.PLACE_FLOOR or not data["blocks"]:
			return null
		item.blocks = true
	if data.has("group"):
		item.group = read_name(data["group"])
		if not _is_group(item.group):
			return null
	if data.has("weight"):
		item.weight = _whole_unit(data["weight"])
		if item.weight < 0 or item.group.is_empty():
			return null
	return item


## `[a-z0-9_]+`: a pool's name.
static func _is_group(group: StringName) -> bool:
	var text := str(group)
	if text.is_empty():
		return false
	for character in text:
		if not (character == "_" or (character >= "a" and character <= "z") or (character >= "0" and character <= "9")):
			return false
	return true


static func _whole_unit(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = value
	if not is_finite(number) or number < 0 or number > 2147483647:
		return -1
	return whole(value)


static func _whole_pair(value: Variant) -> Vector2i:
	var pair := read_list(value)
	if pair.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(_whole_unit(pair[0]), _whole_unit(pair[1]))


static func _is_hex_color(value: Variant) -> bool:
	if not value is String:
		return false
	var hex: String = value
	if hex.length() != 6:
		return false
	for digit in hex:
		if not "0123456789abcdef".contains(digit):
			return false
	return true


## Check the actual decoded texture, not just the existence of its path. The
## normal family loader keeps imported resources and caches loose PNGs as-is.
func _image_error(relative: String, size: Vector2i) -> String:
	var image := texture(relative)
	if image == null:
		return 'image "%s" did not load' % relative
	var expected := Vector2(size) * density
	if image.get_size() != expected:
		return 'image "%s" is %s, expected %s (size × density)' % [relative, image.get_size(), expected]
	return ""


## Same split as ArtFamily.texture(). The loose font mirrors the shipped font's
## import settings where FontFile exposes them.
static func _load_font(path: String) -> Font:
	if path.begins_with("res://"):
		return load(path) as Font if ResourceLoader.exists(path) else null
	if not FileAccess.file_exists(path):
		return null
	var result := FontFile.new()
	if result.load_dynamic_font(path) != OK:
		return null
	result.disable_embedded_bitmaps = true
	result.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return result
