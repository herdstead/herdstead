class_name WorkstationArt
extends ArtFamily
## The approved generic character, A desk/chair and twin monitors as complete
## images. Shared by every theme, with its own palette; no rig, recolouring or
## runtime compositing. from_manifest() is the only raw-data boundary.
##
## Dress Body with sheet_texture(), set its hframes/vframes to columns/rows,
## and attach library to its parent's AnimationPlayer. Each animation keys
## Body:frame discretely. State transitions belong to the caller. An empty
## workstation uses empty_texture() with one frame and the same pivot.

const MANIFEST := "res://assets/daylight/workstation/manifest.json"
const SCHEMA_VERSION := 1
const WORKSTATION_DENSITY := 2
const CANVAS := Vector2i(80, 80)
const ORIGIN := Vector2(37.5, 70)
const COLUMNS := 4
const ROWS := 6
const SHEET := "state-workstation.png"
const EMPTY := "empty-workstation.png"
const PORTRAIT := "generic-portrait.png"
const PORTRAIT_SIZE := Vector2i(40, 40)
const PORTRAIT_PIVOT := Vector2(20, 40)
const PALETTE_SIZE := 37
const PRODUCT_KEYS: Array[String] = [
	"schema_version",
	"id",
	"name",
	"density",
	"filter",
	"frame_size",
	"pivot",
	"columns",
	"rows",
	"image",
	"empty_image",
	"portrait",
	"palette",
	"animations",
]
const TRACKS: Array[StringName] = [
	&"idle",
	&"working",
	&"blocked_enter",
	&"blocked",
	&"blocked_exit",
	&"done",
	&"starting",
	&"unknown",
]
const LOOPING: Array[StringName] = [&"idle", &"working", &"blocked"]


## A validated sequence of complete-image indices and their hold times.
class Track:
	extends RefCounted

	var frames: Array[int] = []
	var seconds: Array[float] = []
	var loop := false
	var duration := 0.0


var id := &""
var display_name := ""
## All geometry is in world units, not texture pixels.
var frame_size := CANVAS
var pivot := ORIGIN
var columns := COLUMNS
var rows := ROWS
## Image paths are relative to base_path, never interpreted by scene code.
var image_path := ""
var empty_path := ""
var portrait_path := ""
var portrait_size := PORTRAIT_SIZE
var portrait_pivot := PORTRAIT_PIVOT
var palette: Dictionary[StringName, Color] = {}
var tracks: Dictionary[StringName, Track] = {}
## Built once on load, ready to share between AnimationPlayers.
var library: AnimationLibrary


## Null and a diagnostic on a malformed manifest or an unusable image, also
## in release builds. Every value is checked before a typed assignment.
static func from_manifest(path: String = MANIFEST) -> WorkstationArt:
	var data := read_json(path)
	if data.is_empty():
		push_error("Workstation %s: not a JSON object" % path)
		return null
	var result := WorkstationArt.new()
	result.base_path = path.get_base_dir()
	var problem := result._read(data)
	if not problem.is_empty():
		push_error("Workstation %s: %s" % [path, problem])
		return null
	result.library = result._make_library()
	return result


func sheet_texture() -> Texture2D:
	return texture(image_path)


func empty_texture() -> Texture2D:
	return texture(empty_path)


func portrait_texture() -> Texture2D:
	return texture(portrait_path)


func _make_library() -> AnimationLibrary:
	var result := AnimationLibrary.new()
	for name in TRACKS:
		var entry := tracks[name]
		var animation := Animation.new()
		animation.length = entry.duration
		animation.loop_mode = Animation.LOOP_LINEAR if entry.loop else Animation.LOOP_NONE
		var channel := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(channel, ^"Body:frame")
		animation.value_track_set_update_mode(channel, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(channel, Animation.INTERPOLATION_NEAREST)
		var at := 0.0
		for index in entry.frames.size():
			animation.track_insert_key(channel, at, entry.frames[index])
			at += entry.seconds[index]
		result.add_animation(name, animation)
	return result


func _read(data: Dictionary) -> String:
	if data.size() != PRODUCT_KEYS.size():
		return "manifest must declare exactly the workstation fields"
	for key: Variant in data:
		if not key is String or not PRODUCT_KEYS.has(key):
			return "unknown manifest field"
	if read_number(data.get("schema_version"), -1.0) != SCHEMA_VERSION:
		return '"schema_version" must be %d' % SCHEMA_VERSION
	if read_name(data.get("id")).is_empty() or read_name(data.get("name")).is_empty():
		return '"id" and "name" must be non-empty text'
	id = read_name(data["id"])
	display_name = str(read_name(data["name"]))
	var steps: Array[Callable] = [_read_geometry, _read_palette, _read_tracks, _read_images]
	for step in steps:
		var problem: String = step.call(data)
		if not problem.is_empty():
			return problem
	return ""


func _read_geometry(data: Dictionary) -> String:
	if read_number(data.get("density"), -1.0) != WORKSTATION_DENSITY or data.get("filter") != "nearest":
		return 'workstation density must be 2 and filter "nearest"'
	if (
		not _is_pair(data.get("frame_size"), Vector2(CANVAS))
		or not _is_pair(data.get("pivot"), ORIGIN)
		or read_number(data.get("columns"), -1.0) != COLUMNS
		or read_number(data.get("rows"), -1.0) != ROWS
	):
		return "workstation must be 4x6 cells of 80x80 units, pivot [37.5, 70]"
	if not data.get("portrait") is Dictionary:
		return '"portrait" must be a JSON object'
	var portrait: Dictionary = data["portrait"]
	if (
		portrait.size() != 3
		or portrait.get("image") != PORTRAIT
		or not _is_pair(portrait.get("size"), Vector2(PORTRAIT_SIZE))
		or not _is_pair(portrait.get("pivot"), PORTRAIT_PIVOT)
	):
		return "portrait must name generic-portrait.png, size [40, 40], pivot [20, 40]"
	density = WORKSTATION_DENSITY
	filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return ""


## Compare JSON numbers before Vector2's float32 conversion can round a
## fractional dimension or a shifted pivot onto the required native geometry.
static func _is_pair(value: Variant, expected: Vector2) -> bool:
	var pair := read_list(value)
	return pair.size() == 2 and read_number(pair[0], -1.0) == expected.x and read_number(pair[1], -1.0) == expected.y


func _read_palette(data: Dictionary) -> String:
	if not data.get("palette") is Dictionary:
		return '"palette" must be a JSON object'
	var colors: Dictionary = data["palette"]
	if colors.size() != PALETTE_SIZE:
		return "workstation must declare its own 37-colour palette"
	var seen: Array[Color] = []
	for key: Variant in colors:
		if not key is String or not colors[key] is String:
			return "palette names and colours must be text"
		var name: String = key
		var hex: String = colors[key]
		var valid_hex := hex.length() == 6
		for digit in hex:
			valid_hex = valid_hex and "0123456789abcdefABCDEF".contains(digit)
		if name.is_empty() or not valid_hex:
			return "palette needs non-empty names and six-digit RGB colours"
		var color := Color.from_string("#" + hex, Color.TRANSPARENT)
		if seen.has(color):
			return "palette colours must be distinct"
		seen.append(color)
		palette[StringName(name)] = color
	return ""


func _read_tracks(data: Dictionary) -> String:
	if not data.get("animations") is Dictionary:
		return '"animations" must be a JSON object'
	var entries: Dictionary = data["animations"]
	if entries.size() != TRACKS.size():
		return "animations must declare exactly %s" % [TRACKS]
	for name in TRACKS:
		var entry := _read_track(entries.get(str(name)))
		if entry == null:
			return 'animation "%s": needs whole frames 0..23 and finite positive seconds, one per frame' % name
		if entry.loop != LOOPING.has(name):
			return 'animation "%s": incorrect loop flag' % name
		if name in [&"starting", &"unknown"] and entry.frames != [0]:
			return 'animation "%s" must hold frame 0, never show activity' % name
		tracks[name] = entry
	return ""


static func _read_track(value: Variant) -> Track:
	if not value is Dictionary:
		return null
	var entry: Dictionary = value
	if (
		entry.size() != 3
		or not entry.get("frames") is Array
		or not entry.get("seconds") is Array
		or not entry.get("loop") is bool
	):
		return null
	var frames: Array = entry["frames"]
	var seconds: Array = entry["seconds"]
	if frames.is_empty() or frames.size() != seconds.size():
		return null
	var result := Track.new()
	result.loop = read_flag(entry["loop"])
	for index in frames.size():
		var frame := read_number(frames[index], -1.0)
		var hold := read_number(seconds[index], -1.0)
		if not is_finite(frame) or frame < 0 or frame >= COLUMNS * ROWS or frame != floorf(frame):
			return null
		var end := result.duration + hold
		if not is_finite(hold) or hold <= 0.0 or not is_finite(end) or end <= result.duration:
			return null
		result.frames.append(int(frame))
		result.seconds.append(hold)
		result.duration = end
	return result


func _read_images(data: Dictionary) -> String:
	if data.get("image") != SHEET or data.get("empty_image") != EMPTY:
		return "images must name state-workstation.png and empty-workstation.png"
	image_path = SHEET
	empty_path = EMPTY
	portrait_path = PORTRAIT
	var expected: Dictionary[String, Vector2i] = {
		image_path: frame_size * density * Vector2i(columns, rows),
		empty_path: frame_size * density,
		portrait_path: portrait_size * density,
	}
	for relative in expected:
		var image := texture(relative)
		if image == null:
			return 'image "%s" did not load' % relative
		if Vector2i(image.get_size()) != expected[relative]:
			return 'image "%s" must be %s pixels' % [relative, expected[relative]]
	return ""
