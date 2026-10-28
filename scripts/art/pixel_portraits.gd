class_name PixelPortraits
extends ArtFamily
## assets/portraits/portraits_manifest.json: the portraits, a head-and-shoulders
## picture of the seat's person for the HUD (the top bar's tiles, the agent
## card). A family of its own beside the pixel people, shared by every theme:
## each ArtPack loads it as `portraits`, after the people, and hands it `people`.
##
## A portrait is a 40x40-unit square (density 2, sampled NEAREST, its origin at
## the bottom centre) drawn as nine layers, bottom to top top, head, face,
## brows, marks, neckwear, glasses, hair and headwear. Each layer binds to the
## people's look slots by name (the head is coloured by `skin`, the hair shaped
## by `hair_style` and coloured by `hair_colour`, ...), so a pane's portrait is
## its seat's person by construction; three layers are shaped by the portrait's
## own extras (PortraitLook: the expression, marks, neckwear), picked per pane
## with the people's hash under their own names.
##
## Every layer of every look is one *cell* of one sheet (`portraits.png`, 80x80
## texel cells row-major, packed at build time, never at runtime), and a layer's
## texture is an AtlasTexture region of it: a portrait's nine layers batch into
## one draw call.
##
## from_manifest() is the only place the manifest's JSON is read (null and a
## push_error naming the file and the rule when it cannot be drawn from);
## everything after it is typed. tools/build_portraits.py writes the manifest
## from art/portraits/portraits.json.

const ROOT := "res://assets/portraits/"
const MANIFEST := ROOT + "portraits_manifest.json"
const SCHEMA_VERSION := 1
## Texels per unit: the pixel people's, so a portrait's texel is a person's.
const PORTRAIT_DENSITY := 2
## The portrait in units: the HUD's portrait window is built round it.
const CANVAS := Vector2i(40, 40)
const SHEET := "portraits.png"
const TOP := &"top"
const HEAD := &"head"
const FACE := &"face"
const BROWS := &"brows"
const MARKS := &"marks"
const NECKWEAR := &"neckwear"
const GLASSES := &"glasses"
const HAIR := &"hair"
const HEADWEAR := &"headwear"
## The layers, bottom to top. A manifest has to draw exactly these.
const LAYERS: Array[StringName] = [TOP, HEAD, FACE, BROWS, MARKS, NECKWEAR, GLASSES, HAIR, HEADWEAR]
## The Sprite2D that shows each layer in scenes/people/pixel_portrait.tscn
## (PixelPortrait), in the same order.
const SPRITES: Dictionary[StringName, String] = {
	TOP: "Layers/Top",
	HEAD: "Layers/Head",
	FACE: "Layers/Face",
	BROWS: "Layers/Brows",
	MARKS: "Layers/Marks",
	NECKWEAR: "Layers/Neckwear",
	GLASSES: "Layers/Glasses",
	HAIR: "Layers/Hair",
	HEADWEAR: "Layers/Headwear",
}
const PRODUCT_KEYS: Array[String] = [
	"schema_version",
	"density",
	"filter",
	"canvas",
	"pivot",
	"columns",
	"layers",
	"extras",
	"cells",
	"files",
	"mock_files",
]
const LAYER_KEYS: Array[String] = ["shape", "colour", "fixed"]
const EXTRA_KEYS: Array[String] = ["options", "none", "default", "pool"]
## The prefix of an extra's name in the people's per-pane hash (PixelPeople.pick()):
## "portrait.expression" never collides with a look slot, so no one's look moves.
const PICK_PREFIX := "portrait."


## One layer: the look slot or extra that picks its drawing (empty when it has
## one drawing) and the look's colour slot that picks its swatch (empty when it
## holds fixed colours only).
class Layer:
	extends RefCounted

	var id := &""
	var shape := &""
	var colour := &""


## One extra: what it can be, what a portrait with no pane shows, and the pool a
## pane's pick comes from (a repeat is a weight).
class Extra:
	extends RefCounted

	var id := &""
	var options: Array[StringName] = []
	var allows_none := false
	var default := &""
	var pool := PackedStringArray()

	func has_option(value: StringName) -> bool:
		return options.has(value) or (allows_none and value == AvatarLook.NONE)


## The portrait in units, and its origin (the bottom centre).
var canvas := CANVAS
var pivot := Vector2(20, 40)
## Cells per row of the sheet.
var columns := 1
var layers: Dictionary[StringName, Layer] = {}
var extras: Dictionary[StringName, Extra] = {}
## Every cell, "<layer>[_<shape>][_<swatch>]", by its index in the sheet.
var cells: Dictionary[String, int] = {}
## The packed sheet that ships, relative to base_path.
var files := PackedStringArray()
## Parts the builder still draws as placeholders: the painter's to-do.
var mock_files := PackedStringArray()
## The pixel people whose looks the portraits show (their slots, swatches and
## per-pane variation); set by from_manifest().
var people: PixelPeople

var _rows := 0
## Cell name -> its region of the sheet, made once.
var _regions: Dictionary[String, AtlasTexture] = {}


## Read the portraits manifest against `with_people` (whose slots its layers
## bind to). Null, with a push_error naming the file and the problem, when it
## cannot be drawn from; never an assert, because `--export-release` strips
## those and a bad manifest must still fail loudly.
static func from_manifest(path: String, with_people: PixelPeople) -> PixelPortraits:
	if with_people == null:
		push_error("Portraits %s: no pixel people to bind to" % path)
		return null
	var data := read_json(path)
	if data.is_empty():
		push_error("Portraits %s: not a JSON object" % path)
		return null
	var result := PixelPortraits.new()
	result.base_path = path.get_base_dir()
	result.people = with_people
	var problem := result._read(data)
	if not problem.is_empty():
		push_error("Portraits %s: %s" % [path, problem])
		return null
	return result


## The portrait of `provider`'s agent in the pane `pane_key` (HerdrFleet.pane_key):
## the seat's person, resolved by the very call the seat makes, and each extra
## picked by the people's hash under "portrait.<extra>", or its default when
## there is no pane (a showroom, a preview). Never reads state.
func look_of(provider: String, pane_key: String) -> PortraitLook:
	var result := PortraitLook.new()
	result.look = people.look_for(provider, AvatarLook.facing(AvatarLook.STAND, AvatarLook.FRONT), pane_key)
	for id in PortraitLook.EXTRAS:
		var extra := extras[id]
		var value := extra.default
		if not pane_key.is_empty():
			var picked := PixelPeople.pick(provider, pane_key, StringName(PICK_PREFIX + str(id)))
			value = StringName(extra.pool[picked % extra.pool.size()])
		result.set_extra(id, value)
	return result


## The cell `wanted` shows on `layer`; empty when the layer shows nothing (a
## shape at `none`, the hair under a hood) or the look names an option the
## family does not draw.
func cell_name(layer: StringName, wanted: PortraitLook) -> String:
	if not layers.has(layer) or wanted == null or wanted.look == null:
		return ""
	var entry := layers[layer]
	var name := str(layer)
	if not entry.shape.is_empty():
		var shape := _shape_of(entry.shape, wanted)
		if shape.is_empty() or shape == AvatarLook.NONE:
			return ""
		name += "_" + str(shape)
	if layer == HAIR and people.hides_hair(wanted.look):
		return ""
	if not entry.colour.is_empty():
		name += "_" + str(wanted.look.slot(entry.colour))
	return name if cells.has(name) else ""


## The texture of `layer` for `wanted`: its cell's region of the sheet, made once
## and shared; null when the layer shows nothing.
func part_texture(layer: StringName, wanted: PortraitLook) -> Texture2D:
	return cell_texture(cell_name(layer, wanted))


## One cell's region of the sheet, by name; null for an empty name or one the
## family does not ship.
func cell_texture(name: String) -> Texture2D:
	if name.is_empty() or not cells.has(name):
		return null
	if _regions.has(name):
		return _regions[name]
	var sheet := texture(SHEET)
	if sheet == null:
		return null
	var region := AtlasTexture.new()
	region.atlas = sheet
	region.region = Rect2(cell_rect(cells[name]))
	_regions[name] = region
	return region


## Where cell `index` sits in the sheet, in texture pixels.
func cell_rect(index: int) -> Rect2i:
	var texels := canvas * density
	return Rect2i(Vector2i(index % columns * texels.x, floori(index / float(columns)) * texels.y), texels)


## Whether `relative` (a part, "parts/head.png") is still the builder's placeholder.
func is_mock(relative: String) -> bool:
	return mock_files.has(relative)


## What a layer's shape slot or extra names in `wanted`.
func _shape_of(slot_id: StringName, wanted: PortraitLook) -> StringName:
	if extras.has(slot_id):
		var value := wanted.extra(slot_id)
		return value if extras[slot_id].has_option(value) else &""
	var value := wanted.look.slot(slot_id)
	return value if people.slots.has(slot_id) and people.slots[slot_id].has_option(value) else &""


# --- reading the manifest -------------------------------------------------------


## Every field the manifest carries, in typed form; the reason it cannot be
## drawn from, otherwise. Checked before any typed assignment, so a malformed
## value is a rejection and never a runtime type error.
func _read(data: Dictionary) -> String:
	for key: String in data:
		if not PRODUCT_KEYS.has(key):
			return 'unknown field "%s"' % key
	if whole(data.get("schema_version")) != SCHEMA_VERSION:
		return '"schema_version" must be %d' % SCHEMA_VERSION
	if whole(data.get("density")) != PORTRAIT_DENSITY:
		return '"density" must be %d, the pixel people\'s' % PORTRAIT_DENSITY
	density = PORTRAIT_DENSITY
	if data.get("filter") != "nearest":
		return '"filter" must be "nearest"'
	filter = read_filter(data)
	var steps: Array[Callable] = [_read_geometry, _read_extras, _read_layers, _read_cells]
	for step in steps:
		var problem: String = step.call(data)
		if not problem.is_empty():
			return problem
	return ""


func _read_geometry(data: Dictionary) -> String:
	var size := _whole_pair(data.get("canvas"))
	var origin := _whole_pair(data.get("pivot"))
	if size != CANVAS:
		return '"canvas" must be %s units, the HUD\'s portrait window' % [[CANVAS.x, CANVAS.y]]
	if origin.x * 2 != size.x or origin.y < 0 or origin.y > size.y:
		return '"pivot" must be a pair of whole units on the canvas, its x the canvas\'s centre'
	canvas = size
	pivot = Vector2(origin)
	columns = whole(data.get("columns"))
	if columns < 1:
		return '"columns" must be a positive whole number of cells'
	return ""


func _read_extras(data: Dictionary) -> String:
	if not data.get("extras") is Dictionary:
		return '"extras" is not a JSON object'
	var entries: Dictionary = data["extras"]
	var names: Array = entries.keys()
	var expected: Array = []
	for id in PortraitLook.EXTRAS:
		expected.append(str(id))
	if names != expected:
		return '"extras" must be exactly %s' % [expected]
	for id in PortraitLook.EXTRAS:
		var extra := _read_extra(id, entries[str(id)])
		if extra == null:
			return 'extra "%s" must list its options, its default and a pool of them' % id
		extras[id] = extra
	return ""


static func _read_extra(id: StringName, value: Variant) -> Extra:
	if not value is Dictionary:
		return null
	var entry: Dictionary = value
	for key: String in entry:
		if not EXTRA_KEYS.has(key):
			return null
	var extra := Extra.new()
	extra.id = id
	extra.options = _names(entry.get("options"))
	if extra.options.is_empty() or extra.options.has(AvatarLook.NONE):
		return null
	if entry.has("none") and not entry["none"] is bool:
		return null
	extra.allows_none = read_flag(entry.get("none"))
	extra.default = read_name(entry.get("default"))
	extra.pool = PackedStringArray(_strings(entry.get("pool")))
	if not extra.has_option(extra.default) or extra.pool.is_empty():
		return null
	for option in extra.pool:
		if not extra.has_option(StringName(option)):
			return null
	return extra


func _read_layers(data: Dictionary) -> String:
	if not data.get("layers") is Dictionary:
		return '"layers" is not a JSON object'
	var entries: Dictionary = data["layers"]
	for key: Variant in entries:
		if not LAYERS.has(StringName(str(key))):
			return 'layer "%s" is not one the portrait draws (%s)' % [key, LAYERS]
	for id in LAYERS:
		if not entries.has(str(id)):
			return 'no layer "%s"' % id
		var problem := _read_layer(id, entries[str(id)])
		if not problem.is_empty():
			return 'layer "%s": %s' % [id, problem]
	return ""


func _read_layer(id: StringName, value: Variant) -> String:
	if not value is Dictionary:
		return "is not a JSON object"
	var entry: Dictionary = value
	for key: String in entry:
		if not LAYER_KEYS.has(key):
			return 'unknown field "%s"' % key
	var layer := Layer.new()
	layer.id = id
	if entry.get("shape") != null:
		layer.shape = read_name(entry.get("shape"), &"?")
		var shaped := people.slots.has(layer.shape) and not people.slots[layer.shape].is_colour()
		if not shaped and not extras.has(layer.shape):
			return 'shape "%s" is no look shape slot and no extra' % layer.shape
	if entry.get("colour") != null:
		layer.colour = read_name(entry.get("colour"), &"?")
		if not people.slots.has(layer.colour) or not people.slots[layer.colour].is_colour():
			return 'colour "%s" is no colour slot of the pixel people' % layer.colour
	layers[id] = layer
	return ""


## The one sheet, whole cells `columns` wide, and every cell inside it.
func _read_cells(data: Dictionary) -> String:
	files = PackedStringArray(_strings(data.get("files")))
	mock_files = PackedStringArray(_strings(data.get("mock_files")))
	if files != PackedStringArray([SHEET]):
		return '"files" must be the one sheet, %s' % SHEET
	var image := texture(SHEET)
	if image == null:
		return 'sheet "%s" did not load' % SHEET
	var texels := canvas * density
	var size := Vector2i(image.get_size())
	if size.x != columns * texels.x or size.y % texels.y != 0 or size.y == 0:
		return 'sheet "%s" is %s, not %d cells of %s wide and whole cells tall' % [SHEET, size, columns, texels]
	_rows = floori(size.y / float(texels.y))
	return _read_indices(data.get("cells"))


## Every cell's index, each inside the sheet.
func _read_indices(value: Variant) -> String:
	if not value is Dictionary:
		return '"cells" is not a JSON object'
	var entries: Dictionary = value
	for name: Variant in entries:
		var index := whole(entries[name])
		if not name is String or index < 0:
			return 'cell "%s" must be a whole index into the sheet' % name
		if index >= columns * _rows:
			return 'cell "%s" is at %d, outside the sheet (%d cells)' % [name, index, columns * _rows]
		cells[str(name)] = index
	return ""


static func _whole_pair(value: Variant) -> Vector2i:
	var pair := read_list(value)
	if pair.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(whole(pair[0]), whole(pair[1]))


## A JSON list of safe names, or empty when it is anything else or repeats one.
static func _names(value: Variant) -> Array[StringName]:
	var found: Array[StringName] = []
	for item: Variant in read_list(value):
		if not item is String:
			return []
		var label: String = item
		if label.is_empty() or not label.is_valid_ascii_identifier() or found.has(StringName(label)):
			return []
		found.append(StringName(label))
	return found


## A JSON list of strings, or empty when any item is something else.
static func _strings(value: Variant) -> Array[String]:
	var found: Array[String] = []
	for item: Variant in read_list(value):
		if not item is String:
			return []
		var text: String = item
		found.append(text)
	return found
