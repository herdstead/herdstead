class_name PixelPeople
extends ArtFamily
## assets/pixel_people/people_manifest.json: the pixel people, small
## frame-animated figures drawn at density 1 or 2 (texture pixels per unit,
## sampled NEAREST; geometry, the pivot and the frame are always in units, and
## dress() scales a sprite back by 1/density). A family of its own, shared by
## every theme: each ArtPack loads it as `people`, and PixelPerson is its prefab.
##
## A figure is six layers, bottom to top legs, top, body (skin, eyes and what
## the hands hold), glasses, hair and headwear. Each layer shows one *strip*
## per facing holding every frame of every track in the same columns, so one
## `frame` key of the one AnimationPlayer shows the same moment on every layer
## whichever way the figure faces: facing is a texture swap (and flip_h for the
## mirrored side), never a second animated channel.
##
## Which strip a layer shows comes from the look's slots (AvatarLook): a shape
## slot picks the layer's drawing (or `none`, nothing at all), a colour slot the
## swatch it was baked in. The strips of one facing ship packed into one sheet
## (`<facing>.png`, strips stacked with no gutter; packed at build time, never at
## runtime), and a layer's texture is an AtlasTexture region of it. Every layer
## of every person then draws from one texture, so a person's six layers batch
## into one draw call (docs/ASSET_SPEC.md, "Pixel people").
##
## from_manifest() is the only place the manifest's JSON is read (null and a
## push_error naming the file and the rule when it cannot be drawn from);
## everything after it is typed. tools/build_pixel_people.py writes the
## manifest from art/pixel_people/people.json.

const ROOT := "res://assets/pixel_people/"
const MANIFEST := ROOT + "people_manifest.json"
## Texels per unit the family may ship at; tools/build_pixel_people.py DENSITIES.
const PEOPLE_DENSITIES: Array[int] = [1, 2]
const SCHEMA_VERSION := 2
const LEGS := &"legs"
const TOP := &"top"
const BODY := &"body"
const GLASSES := &"glasses"
const HAIR := &"hair"
const HEADWEAR := &"headwear"
## The prefab's layers, bottom to top. A manifest has to draw exactly these.
const LAYERS: Array[StringName] = [LEGS, TOP, BODY, GLASSES, HAIR, HEADWEAR]
## The Sprite2D that shows each layer in scenes/people/pixel_person.tscn; the
## animation library keys their `frame`.
const SPRITES: Dictionary[StringName, String] = {
	LEGS: "Layers/Legs",
	TOP: "Layers/Top",
	BODY: "Layers/Body",
	GLASSES: "Layers/Glasses",
	HAIR: "Layers/Hair",
	HEADWEAR: "Layers/Headwear",
}
const FRONT := &"front"
const BACK := &"back"
const SIDE := &"side"
const LEFT := &"left"
const RIGHT := &"right"
## The facings a strip can be drawn for. Every track draws the front, and a
## facing a track does not draw falls back to it.
const DRAWN: Array[StringName] = [FRONT, BACK, SIDE]
## Every state herdr reports and the office animates, which state_tracks has to
## map in both contexts.
const STATES: Array[StringName] = [&"idle", &"done", &"unknown", &"working", &"blocked", &"starting"]
## The key roles a colour slot recolours.
const ROLES: Array[StringName] = [&"skin", &"top", &"legs", &"hair", &"hat"]
## The per-pane variation's hash input starts with this: changing the scheme
## means changing it, which reshuffles everyone once, on purpose.
const VARIATION_SCHEME := "herdstead.look/1"
## Between the hash input's fields: U+001F, the same separator a pane key uses
## (HerdrFleet.KEY_SEPARATOR), so no field can forge a boundary.
const VARIATION_SEPARATOR := "\u001f"
const PRODUCT_KEYS: Array[String] = [
	"schema_version",
	"density",
	"filter",
	"frame_size",
	"pivot",
	"columns",
	"facings",
	"side_faces",
	"layers",
	"tracks",
	"state_tracks",
	"slots",
	"default_look",
	"variation",
	"keys",
	"fixed",
	"strips",
	"files",
	"mock_files",
]
const TRACK_KEYS: Array[String] = ["start", "facings", "durations", "loop"]


## One track: where its frames start in every strip, how long each lasts,
## whether it loops, and which facings draw it.
class Track:
	extends RefCounted

	var id := &""
	## The strip column of the track's first frame; the same in every facing.
	var start := 0
	var durations := PackedFloat32Array()
	var loop := true
	## Facings that draw this track, the front first.
	var facings: Array[StringName] = []

	func frame_count() -> int:
		return durations.size()

	## The frame index (strip column) that shows frame `index` of this track.
	func frame(index: int) -> int:
		return start + index

	## How long one pass through the track takes.
	func length() -> float:
		var total := 0.0
		for duration in durations:
			total += duration
		return total

	## When frame `index` starts, counted from the beginning of the track.
	func starts_at(index: int) -> float:
		var at := 0.0
		for before in mini(index, durations.size()):
			at += durations[before]
		return at

	## The facing this track shows when `wanted` is asked for: that facing when
	## the track draws it, otherwise its first (the front).
	func shown(wanted: StringName) -> StringName:
		return wanted if facings.has(wanted) else facings[0]


## One slot of a look: a shape slot (which drawing a layer shows) or a colour
## slot (which swatch a role is baked in).
class Slot:
	extends RefCounted

	var id := &""
	var layer := &""
	## The key role a colour slot recolours; empty for a shape slot.
	var role := &""
	## A shape slot's drawings, in manifest order.
	var shapes: Array[StringName] = []
	## Shapes that hide the hair layer while worn (a hood).
	var hides_hair: Array[StringName] = []
	## A colour slot's swatches, in manifest order, and each one's light, mid and
	## dark tones.
	var swatches: Array[StringName] = []
	var ramps: Dictionary[StringName, PackedColorArray] = {}
	## Whether `none` (draw nothing) is an option.
	var allows_none := false

	func is_colour() -> bool:
		return not role.is_empty()

	## Everything the slot can be set to, in order, `none` last.
	func options() -> Array[StringName]:
		var found: Array[StringName] = []
		found.assign(swatches if is_colour() else shapes)
		if allows_none:
			found.append(AvatarLook.NONE)
		return found

	func has_option(value: StringName) -> bool:
		return options().has(value)


## One frame, in units.
var frame_size := Vector2i(32, 48)
## The feet inside a frame, in units; its x is the frame's centre, so a
## mirrored figure keeps its feet on the same spot.
var pivot := Vector2(16, 46)
## Frames in every strip: the sum of every track's frames.
var columns := 1
var facings: Array[StringName] = []
## Which way the side strip is drawn (right or left); the other way is its
## mirror.
var side_faces := RIGHT
var tracks: Dictionary[StringName, Track] = {}
## Context -> semantic animation -> track; the inner dictionaries are
## Dictionary[StringName, StringName].
var state_tracks: Dictionary[StringName, Dictionary] = {}
## Every slot of AvatarLook.SLOTS.
var slots: Dictionary[StringName, Slot] = {}
## The pack's look: every slot set.
var default_look := AvatarLook.new()
## Slot -> the options a pane's look is picked from when the user has not
## pinned that slot; a repeat is a weight. A slot missing here does not vary.
var variation: Dictionary[StringName, PackedStringArray] = {}
## Role -> its three key colours, as sources are painted.
var keys: Dictionary[StringName, PackedColorArray] = {}
## The colours sources pass through unchanged, by name.
var fixed: Dictionary[StringName, Color] = {}
## Every strip, in the row order of every facing's sheet.
var strips := PackedStringArray()
## The packed sheets that ship (one per facing), relative to base_path.
var files := PackedStringArray()
## Source strips the builder still draws as placeholders: the artist's to-do.
var mock_files := PackedStringArray()
## Herdr's agent list, each provider's default and the user's saved looks.
## Made on first use unless assigned (an ArtPack can share its own).
var agent_catalog: AgentCatalog

var _library: AnimationLibrary
var _rows: Dictionary[String, int] = {}
## "<facing>/<strip>" -> its region of the facing's sheet, made once.
var _regions: Dictionary[String, AtlasTexture] = {}


## Read the people manifest. Null, with a push_error naming the file and the
## problem, when it cannot be drawn from; never an assert, because
## `--export-release` strips those and a bad manifest must still fail loudly.
static func from_manifest(path: String) -> PixelPeople:
	var data := read_json(path)
	if data.is_empty():
		push_error("Pixel people %s: not a JSON object" % path)
		return null
	var result := PixelPeople.new()
	result.base_path = path.get_base_dir()
	var problem := result._read(data)
	if not problem.is_empty():
		push_error("Pixel people %s: %s" % [path, problem])
		return null
	return result


## The track that shows `semantic` in `context`; the semantic name itself when
## the manifest maps it to nothing.
func track(context: StringName, semantic: StringName) -> StringName:
	if not state_tracks.has(context):
		return semantic
	var mapped: Dictionary[StringName, StringName] = state_tracks[context]
	return mapped[semantic] if mapped.has(semantic) else semantic


## The strip `look` shows on `layer`: "<layer>[_<shape>][_<swatch>]"; empty when
## the layer shows nothing (a shape slot at `none`, the hair under a hood) or
## the look names an option the family does not draw.
func strip_name(layer: StringName, look: AvatarLook) -> String:
	var name := str(layer)
	for slot_id in slots:
		var slot := slots[slot_id]
		if slot.layer != layer or slot.is_colour():
			continue
		var shape := look.slot(slot_id)
		if shape == AvatarLook.NONE or not slot.shapes.has(shape):
			return ""
		name += "_" + str(shape)
	if layer == HAIR and _hides_hair(look):
		return ""
	for slot_id in slots:
		var slot := slots[slot_id]
		if slot.layer != layer or not slot.is_colour():
			continue
		var swatch := look.slot(slot_id)
		if not slot.swatches.has(swatch):
			return ""
		name += "_" + str(swatch)
	return name if _rows.has(name) else ""


## The texture of `layer` for `look` in the drawn facing `strip_facing`: the
## strip's region of that facing's sheet, made once and shared; null when the
## layer shows nothing.
func layer_texture(layer: StringName, look: AvatarLook, strip_facing: StringName) -> Texture2D:
	return strip_texture(strip_facing, strip_name(layer, look))


## One strip's region of the `strip_facing` sheet, by name; null for an empty
## name or one the family does not ship.
func strip_texture(strip_facing: StringName, strip: String) -> Texture2D:
	if strip.is_empty() or not _rows.has(strip):
		return null
	var key := "%s/%s" % [strip_facing, strip]
	if _regions.has(key):
		return _regions[key]
	var sheet := texture("%s.png" % strip_facing)
	if sheet == null:
		return null
	var region := AtlasTexture.new()
	region.atlas = sheet
	var texels := frame_size * density
	region.region = Rect2(0, _rows[strip] * texels.y, columns * texels.x, texels.y)
	_regions[key] = region
	return region


## Where frame `index` sits in every strip, in texture pixels (units times density).
func frame_rect(index: int) -> Rect2i:
	var texels := frame_size * density
	return Rect2i(Vector2i(index * texels.x, 0), texels)


## Whether `relative` (a source strip, "front/top.png") is still the builder's
## placeholder.
func is_mock(relative: String) -> bool:
	return mock_files.has(relative)


## A provider's look, slot by slot (docs/VISUAL_LANGUAGE.md, "Looks"):
##   1. the pack's default;
##   2. the provider's default from the catalog;
##   3. the user's saved choice for the provider (a pinned slot);
##   4. otherwise, when `vary_by` names the pane (HerdrFleet.pane_key) and the
##      family varies the slot, a fixed pick for that provider and pane (pick());
##   5. whatever `wanted` names (a studio preview, a showroom, a test).
## At every level a value the family does not draw is skipped. Pose and badge
## come from `wanted`; an unknown provider is the generic one.
func look_for(provider: String, wanted: AvatarLook = null, vary_by := "") -> AvatarLook:
	var known := catalog()
	var normalized := provider if known.has(provider) else str(AgentCatalog.FALLBACK_ID)
	return resolve(provider, known.pins(normalized), wanted, vary_by)


## look_for() with `pinned` standing for the user's saved choice (level 3): what
## the provider would look like with those pins, as the Avatar Studio previews
## an unsaved choice.
func resolve(provider: String, pinned: AvatarLook, wanted: AvatarLook = null, vary_by := "") -> AvatarLook:
	var known := catalog()
	var normalized := provider if known.has(provider) else str(AgentCatalog.FALLBACK_ID)
	var chosen := default_look.clothes()
	var provided := known.default_look(normalized)
	if pinned == null:
		pinned = AvatarLook.new()
	for slot_id in slots:
		var slot := slots[slot_id]
		if slot.has_option(provided.slot(slot_id)):
			chosen.set_slot(slot_id, provided.slot(slot_id))
		if slot.has_option(pinned.slot(slot_id)):
			chosen.set_slot(slot_id, pinned.slot(slot_id))
			chosen.pinned.append(slot_id)
		elif not vary_by.is_empty() and variation.has(slot_id):
			var pool := variation[slot_id]
			chosen.set_slot(slot_id, StringName(pool[pick(provider, vary_by, slot_id) % pool.size()]))
		if wanted != null and slot.has_option(wanted.slot(slot_id)):
			chosen.set_slot(slot_id, wanted.slot(slot_id))
	chosen.badge = provided.badge
	if wanted != null:
		chosen.context = wanted.context
		chosen.orientation = wanted.orientation
		if not wanted.badge.is_empty():
			chosen.badge = wanted.badge
	if not AvatarLook.CONTEXTS.has(chosen.context):
		chosen.context = AvatarLook.STAND
	if not AvatarLook.ORIENTATIONS.has(chosen.orientation):
		chosen.orientation = AvatarLook.FRONT
	return chosen


## The per-pane variation's number for one slot: the first four bytes,
## big-endian, of SHA-256 over UTF-8 "herdstead.look/1␟provider␟pane_key␟slot"
## (␟ = U+001F, HerdrFleet.KEY_SEPARATOR). SHA-256 is a fixed standard, so the
## same pane picks the same look on every run, platform and Godot version, and
## a test can pin values computed outside Godot. One hash per slot: a new slot
## or a changed pool never reshuffles another slot.
static func pick(provider: String, pane_key: String, slot: StringName) -> int:
	var text := VARIATION_SEPARATOR.join(PackedStringArray([VARIATION_SCHEME, provider, pane_key, str(slot)]))
	var digest := text.sha256_buffer()
	return (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]


## The agent catalog looks come from; the shared data file and the user's
## saved choices, read on first use.
func catalog() -> AgentCatalog:
	if agent_catalog == null:
		agent_catalog = AgentCatalog.new()
	return agent_catalog


## One AnimationLibrary for every person of this family, built once: per
## track, an animation whose discrete value tracks set every layer's `frame` at
## the track's cumulative durations. Every animation keys every layer, so no
## layer keeps a frame from the track before.
func animation_library() -> AnimationLibrary:
	if _library != null:
		return _library
	var library := AnimationLibrary.new()
	for id in tracks:
		var entry := tracks[id]
		var animation := Animation.new()
		animation.loop_mode = Animation.LOOP_LINEAR if entry.loop else Animation.LOOP_NONE
		animation.length = entry.length()
		for layer in LAYERS:
			var channel := animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(channel, NodePath("%s:frame" % SPRITES[layer]))
			animation.value_track_set_update_mode(channel, Animation.UPDATE_DISCRETE)
			for index in entry.frame_count():
				animation.track_insert_key(channel, entry.starts_at(index), entry.frame(index))
		library.add_animation(id, animation)
	_library = library
	return _library


func _hides_hair(look: AvatarLook) -> bool:
	for slot_id in slots:
		var slot := slots[slot_id]
		if slot.layer == HEADWEAR and not slot.is_colour() and slot.hides_hair.has(look.slot(slot_id)):
			return true
	return false


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
	var texels := whole(data.get("density"))
	if not PEOPLE_DENSITIES.has(texels):
		return '"density" must be one of %s: texture pixels per unit' % [PEOPLE_DENSITIES]
	density = texels
	filter = read_filter(data)
	if data.get("filter") != "nearest":
		return '"filter" must be "nearest"'
	var steps: Array[Callable] = [
		_read_geometry, _read_facings, _read_tracks, _read_state_tracks, _read_colours, _read_slots, _read_looks
	]
	for step in steps:
		var problem: String = step.call(data)
		if not problem.is_empty():
			return problem
	return _read_files(data)


func _read_geometry(data: Dictionary) -> String:
	var size := _whole_pair(data.get("frame_size"))
	var feet := _whole_pair(data.get("pivot"))
	if size.x < 1 or size.y < 1:
		return '"frame_size" must be a pair of positive whole units'
	if feet.x < 0 or feet.y < 0 or feet.y > size.y:
		return '"pivot" must be a pair of whole units on the frame'
	if feet.x * 2 != size.x:
		return '"pivot" x must be the frame\'s centre, or a mirrored figure moves'
	frame_size = size
	pivot = Vector2(feet)
	columns = whole(data.get("columns"))
	if columns < 1:
		return '"columns" must be a positive whole number of frames'
	var listed: Array = []
	for layer in LAYERS:
		listed.append(str(layer))
	if data.get("layers") != listed:
		return '"layers" must be %s, the prefab\'s sprites' % [listed]
	return ""


func _read_facings(data: Dictionary) -> String:
	facings = _names(data.get("facings"))
	if facings.is_empty():
		return '"facings" must be a list of names'
	for listed in facings:
		if not DRAWN.has(listed):
			return 'facing "%s" is not one of %s' % [listed, DRAWN]
	if not facings.has(FRONT):
		return '"facings" must include front, the facing every track falls back to'
	var side := read_name(data.get("side_faces"))
	if side != RIGHT and side != LEFT:
		return '"side_faces" must be right or left'
	side_faces = side
	return ""


func _read_tracks(data: Dictionary) -> String:
	var listed: Variant = data.get("tracks")
	if not listed is Dictionary:
		return '"tracks" must name at least one track'
	var entries: Dictionary = listed
	if entries.is_empty():
		return '"tracks" must name at least one track'
	for id: String in entries:
		var problem := _read_track(StringName(id), entries[id])
		if not problem.is_empty():
			return 'track "%s": %s' % [id, problem]
	return ""


func _read_track(id: StringName, value: Variant) -> String:
	if not value is Dictionary:
		return "is not a JSON object"
	var spec: Dictionary = value
	var entry := Track.new()
	entry.id = id
	var steps: Array[Callable] = [_read_track_start, _read_durations, _read_loop, _read_track_facings]
	for step in steps:
		var problem: String = step.call(entry, spec)
		if not problem.is_empty():
			return problem
	tracks[id] = entry
	return ""


func _read_track_start(entry: Track, spec: Dictionary) -> String:
	for key: String in spec:
		if not TRACK_KEYS.has(key):
			return 'unknown field "%s"' % key
	entry.start = whole(spec.get("start"))
	return '"start" must be a whole column' if entry.start < 0 else ""


## Every frame's duration, and every frame inside the strip.
func _read_durations(entry: Track, spec: Dictionary) -> String:
	var durations := read_list(spec.get("durations"))
	if durations.is_empty():
		return '"durations" lists no frame'
	for duration: Variant in durations:
		var seconds := read_number(duration, NAN)
		if not (duration is int or duration is float) or not is_finite(seconds) or seconds <= 0.0:
			return '"durations" must be finite, positive seconds'
		entry.durations.append(seconds)
	if entry.start + entry.frame_count() > columns:
		return "frame %d is out of range: a strip holds %d" % [entry.start + entry.frame_count() - 1, columns]
	return ""


func _read_loop(entry: Track, spec: Dictionary) -> String:
	if not spec.get("loop") is bool:
		return '"loop" must be true or false'
	entry.loop = read_flag(spec.get("loop"))
	return ""


func _read_track_facings(entry: Track, spec: Dictionary) -> String:
	entry.facings = _names(spec.get("facings"))
	if entry.facings.is_empty() or entry.facings[0] != FRONT:
		return '"facings" must be a list of names starting with front'
	for listed in entry.facings:
		if not facings.has(listed):
			return 'facing "%s" is not one of the manifest\'s' % listed
	return ""


func _read_state_tracks(data: Dictionary) -> String:
	var listed: Variant = data.get("state_tracks")
	if not listed is Dictionary:
		return '"state_tracks" is not a JSON object'
	var contexts: Dictionary = listed
	for context in AvatarLook.CONTEXTS:
		var mapped: Variant = contexts.get(str(context))
		if not mapped is Dictionary:
			return 'state_tracks has no "%s" context' % context
		var states: Dictionary = mapped
		var typed: Dictionary[StringName, StringName] = {}
		for state in STATES:
			var id := read_name(states.get(str(state)))
			if id.is_empty():
				return 'state_tracks "%s" maps no track for "%s"' % [context, state]
			if not tracks.has(id):
				return 'state_tracks "%s": "%s" plays "%s", which is no track' % [context, state, id]
			typed[state] = id
		state_tracks[context] = typed
	return ""


## The key ramps and the fixed colours (for the studio's swatch chips; no
## runtime colour lookup reads them in this build).
func _read_colours(data: Dictionary) -> String:
	var listed: Variant = data.get("keys")
	if not listed is Dictionary:
		return '"keys" is not a JSON object'
	var roles: Dictionary = listed
	for role in ROLES:
		var ramp := _ramp(roles.get(str(role)))
		if ramp.is_empty():
			return 'keys "%s" must be three colours' % role
		keys[role] = ramp
	var named: Variant = data.get("fixed")
	if not named is Dictionary:
		return '"fixed" is not a JSON object'
	var colours: Dictionary = named
	for name: Variant in colours:
		var colour := _colour(colours[name])
		if not name is String or colour.a == 0.0:
			return 'fixed "%s" is not a colour' % name
		fixed[StringName(str(name))] = colour
	return ""


func _read_slots(data: Dictionary) -> String:
	var listed: Variant = data.get("slots")
	if not listed is Dictionary:
		return '"slots" is not a JSON object'
	var entries: Dictionary = listed
	var names: Array = entries.keys()
	names.sort()
	var expected: Array = []
	for slot_id in AvatarLook.SLOTS:
		expected.append(str(slot_id))
	expected.sort()
	# The order is AvatarLook.SLOTS'; the manifest only has to name them all.
	if names != expected:
		return '"slots" must be exactly %s' % [expected]
	for slot_id in AvatarLook.SLOTS:
		var slot := _read_slot(slot_id, entries[str(slot_id)])
		if slot == null:
			return 'slot "%s" is not a shape slot or a colour slot this family can draw' % slot_id
		slots[slot_id] = slot
	return ""


func _read_slot(id: StringName, value: Variant) -> Slot:
	if not value is Dictionary:
		return null
	var entry: Dictionary = value
	var slot := Slot.new()
	slot.id = id
	slot.layer = read_name(entry.get("layer"))
	if not LAYERS.has(slot.layer):
		return null
	var read := _read_colour_slot(slot, entry) if entry.has("role") else _read_shape_slot(slot, entry)
	return slot if read else null


## A colour slot's role and swatches; false when they cannot be drawn from.
static func _read_colour_slot(slot: Slot, entry: Dictionary) -> bool:
	slot.role = read_name(entry.get("role"))
	if not ROLES.has(slot.role) or not entry.get("swatches") is Dictionary:
		return false
	var swatches: Dictionary = entry["swatches"]
	for swatch: Variant in swatches:
		var ramp := _ramp(swatches[swatch])
		if not swatch is String or ramp.is_empty():
			return false
		slot.swatches.append(StringName(str(swatch)))
		slot.ramps[StringName(str(swatch))] = ramp
	return not slot.swatches.is_empty()


## A shape slot's shapes, which of them hide the hair, and whether none is an
## option; false when they cannot be drawn from.
static func _read_shape_slot(slot: Slot, entry: Dictionary) -> bool:
	if not entry.get("shapes") is Dictionary:
		return false
	var shapes: Dictionary = entry["shapes"]
	for shape: Variant in shapes:
		if not shape is String or not shapes[shape] is Dictionary:
			return false
		var flags: Dictionary = shapes[shape]
		slot.shapes.append(StringName(str(shape)))
		if read_flag(flags.get("hides_hair")):
			slot.hides_hair.append(StringName(str(shape)))
	slot.allows_none = read_flag(entry.get("none"))
	return not slot.shapes.is_empty()


func _read_looks(data: Dictionary) -> String:
	var listed: Variant = data.get("default_look")
	if not listed is Dictionary:
		return '"default_look" is not a JSON object'
	var look: Dictionary = listed
	for slot_id in AvatarLook.SLOTS:
		var value := read_name(look.get(str(slot_id)))
		if not slots[slot_id].has_option(value):
			return 'default_look "%s" is "%s", which the slot does not draw' % [slot_id, value]
		default_look.set_slot(slot_id, value)
	return _read_variation(data)


func _read_variation(data: Dictionary) -> String:
	var pools: Variant = data.get("variation")
	if not pools is Dictionary:
		return '"variation" is not a JSON object'
	var entries: Dictionary = pools
	for slot_key: Variant in entries:
		var slot_id := StringName(str(slot_key))
		if not slots.has(slot_id):
			return 'variation names no slot "%s"' % slot_key
		var pool := PackedStringArray(_strings(entries[slot_key]))
		if pool.is_empty():
			return 'variation "%s" must list options' % slot_id
		for value in pool:
			if not slots[slot_id].has_option(StringName(value)):
				return 'variation "%s" names "%s", which the slot does not draw' % [slot_id, value]
		variation[slot_id] = pool
	return ""


## Every strip every look can show ships, in one sheet per facing at the size
## of all the strips stacked, and the manifest lists nothing else.
func _read_files(data: Dictionary) -> String:
	strips = PackedStringArray(_strings(data.get("strips")))
	files = PackedStringArray(_strings(data.get("files")))
	mock_files = PackedStringArray(_strings(data.get("mock_files")))
	for row in strips.size():
		if _rows.has(strips[row]):
			return 'strip "%s" is listed twice' % strips[row]
		_rows[strips[row]] = row
	var expected := _expected_strips()
	for name in expected:
		if not _rows.has(name):
			return 'no strip "%s", which a look can show' % name
	for name in strips:
		if not expected.has(name):
			return 'strip "%s" is no look\'s' % name
	return _read_sheets()


## One sheet per facing, each every strip stacked: columns x frame wide, a row
## per strip tall, in texels (units times density).
func _read_sheets() -> String:
	var sheets := PackedStringArray()
	for listed in facings:
		sheets.append("%s.png" % listed)
	if files != sheets:
		return '"files" must be one sheet per facing, %s' % sheets
	var size := Vector2i(columns * frame_size.x, strips.size() * frame_size.y) * density
	for file in files:
		var image := texture(file)
		if image == null:
			return 'sheet "%s" did not load' % file
		if Vector2i(image.get_size()) != size:
			return 'sheet "%s" is %s, expected %s (columns x frame, a row per strip)' % [file, image.get_size(), size]
	return ""


## Every strip name the slots can produce, layer by layer.
func _expected_strips() -> PackedStringArray:
	var found := PackedStringArray()
	for layer in LAYERS:
		var shapes: Array[StringName] = []
		var swatches: Array[StringName] = []
		for slot_id in slots:
			var slot := slots[slot_id]
			if slot.layer == layer and slot.is_colour():
				swatches = slot.swatches
			elif slot.layer == layer:
				shapes = slot.shapes
		var names := PackedStringArray([str(layer)])
		if not shapes.is_empty():
			names = PackedStringArray()
			for shape in shapes:
				names.append("%s_%s" % [layer, shape])
		for name in names:
			if swatches.is_empty():
				found.append(name)
			for swatch in swatches:
				found.append("%s_%s" % [name, swatch])
	return found


static func _whole_pair(value: Variant) -> Vector2i:
	var pair := read_list(value)
	if pair.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(whole(pair[0]), whole(pair[1]))


## Three "rrggbb" colours, light to dark; empty when it is anything else.
static func _ramp(value: Variant) -> PackedColorArray:
	var found := PackedColorArray()
	for item: Variant in read_list(value):
		var colour := _colour(item)
		if colour.a == 0.0:
			return PackedColorArray()
		found.append(colour)
	return found if found.size() == 3 else PackedColorArray()


## "rrggbb" as an opaque colour; transparent when it is anything else.
static func _colour(value: Variant) -> Color:
	if not value is String:
		return Color.TRANSPARENT
	var text: String = value
	if text.length() != 6 or not text.is_valid_hex_number():
		return Color.TRANSPARENT
	return Color.html(text)


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
