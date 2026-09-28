class_name AgentCatalog
extends RefCounted
## Canonical Herdr agent IDs, each provider's default look, and the user's own
## saved looks.
##
## Herdr detection names are data, not art-pack IDs. Keeping this catalog
## separate means a theme can change without duplicating the supported-agent
## list, and a user's look survives a theme switch.
##
## A provider's default (`look` in data/agent_catalog.json) is sparse: only the
## clothes, never a signal (docs/VISUAL_LANGUAGE.md, "Looks": the name plate is
## the provider's only channel). The user's saved looks live in
## `user://herdstead_avatars.json`, and this is the only place that file is read
## or written:
##
##   {"schema_version": 2, "looks": {"<provider>": {"<slot>": "<option>" | {"rgb": "rrggbb"}}}}
##
## Sparse: a provider lists only the slots the user pinned. `{"rgb": ...}` is
## kept and written back; no runtime colour lookup reads it in this build. One id rule for every id
## this catalog reads or writes — catalog ids, saved provider ids, slot ids,
## option ids: `[a-z0-9][a-z0-9_-]*`, at most 64 characters, the whole text
## (valid_id()).
##
## **A save never loses or hides anything, or it does not save.** It changes
## only the slots it was asked to, of the one provider it was asked for, and
## keeps the rest of the file: ids this build does not draw, picked colours,
## slots, keys and values it does not know or cannot read, entries past its
## bounds. Before it writes, it reads its own text back with the loader's reader
## and checks it (verify()): the size, that it reads, that every value it read
## before still reads the same, that what it set reads back, and that everything
## else is the same JSON. When a check fails nothing is written and `note` says
## which. What "the same" means for JSON: values round-trip, whole numbers
## within ±2^53 keep their integer form, other numbers keep their exact double
## (so an integer past 2^53, already rounded when read, keeps its double value,
## not its decimal text; `-0` is written `0`). Strings are written the way
## JsonText.encode() writes them: every C0 control character and DEL as
## `\u00XX`, so any strict JSON parser reads the file. The key order is kept.
## Changed by the parser before the guard can see them, so not kept: duplicate
## keys (the last wins), anything after a NUL byte, a `\u0000` escape (read as
## U+FFFD), a number too small for a double (`5e-324` reads as 0).
##
## The file on disk is the one that was read: its size and SHA-256 (or that it
## is absent) are noted at load and after every save, and a save that finds
## anything else there writes nothing ("changed on disk since it was read").
## Unpinning a provider can bring one past MAX_PROVIDERS into effect (it is
## then among the first 256 read); that shows something, it hides nothing.
##
## Today's file without `schema_version` ({"<agent>": {"hair", "outfit"}}) is
## migrated in memory through a frozen table (migrate_v1()); the first save
## keeps the old file beside the new one under a free name, or refuses to save.
##
## Reading never writes. A file that cannot be read at all (not UTF-8, not
## JSON, not an object, a broken version) is left where it is and the catalog
## starts from defaults; the first save moves it aside under a free name and
## says where (`note`), then writes. A file a newer Herdstead wrote, or one too
## large or too deep for this build, is not read and never written over. Every
## write goes to a temporary file of its own, flushed and closed, then renamed
## over the old one: a failed or crashed write leaves the old file whole. When
## the saved file is a symbolic link, the file it links to is the one replaced,
## and the link stays; more than MAX_LINKS links, and the save is refused, never
## replacing a link with a file. Godot offers `flush()`, not fsync, so
## this protects against a process that dies, not against power loss
## (docs/ASSET_SPEC.md).

## What reading the saved file found.
enum FileState {
	## No file yet.
	ABSENT,
	## Schema 2, read.
	READ,
	## Today's unversioned file, migrated in memory; the first save keeps it under a free name.
	MIGRATED,
	## Unreadable: defaults are used, and the first save moves it aside.
	DAMAGED,
	## Written by a newer Herdstead: nothing is read and nothing is written.
	NEWER,
	## Too large or too deep for this build: nothing is read and nothing is written.
	OUT_OF_BOUNDS,
}

const CATALOG_PATH := "res://data/agent_catalog.json"
const USER_PATH := "user://herdstead_avatars.json"
const FALLBACK_ID := &"generic"
const FALLBACK_NAME := "Unknown agent"
const SAVE_SCHEMA := 2
## Bounds on the saved file: it is local, but a file of any size or shape is
## still read in full. Past MAX_BYTES or MAX_DEPTH it is not read at all, and
## never written (OUT_OF_BOUNDS); past the counts, entries are not read into the
## look but are kept as they are.
const MAX_BYTES := 262144
## Nesting levels, the file's own object being the first. A look needs 4. Godot
## deep-copies at most ~100 levels ("Max recursion reached"), and this file's
## own walks recurse once per level, so nothing deeper is taken in.
const MAX_DEPTH := 100
const MAX_PROVIDERS := 256
const MAX_SLOTS := 32
const MAX_ID := 64
const ID_PATTERN := "^[a-z0-9][a-z0-9_-]*$"
## How long an unreadable value may be when it is shown.
const SHOWN_MAX := 16
## Whole numbers up to this size are exact in a double, and written as integers.
const EXACT_WHOLE := 9007199254740992.0
## How many symbolic links a save follows to the file it replaces.
const MAX_LINKS := 8


## One agent herdr can report, as the catalog describes it.
class Entry:
	extends RefCounted

	var id := &""
	var display_name := ""
	var command := ""
	## The provider's default clothes; sparse.
	var look := AvatarLook.new()


## One provider's saved choices this build can read.
class Saved:
	extends RefCounted

	## Slot -> option id: known slots and ids, and ones this build does not know.
	var ids: Dictionary[StringName, StringName] = {}
	## Colour slot -> "rrggbb", the colour picker's choice (kept; not drawn in this build).
	var colours: Dictionary[StringName, String] = {}

	func is_empty() -> bool:
		return ids.is_empty() and colours.is_empty()


## What the one reader made of some bytes: the file on load, and a save's own
## text before it is written.
class Reading:
	extends RefCounted

	var state := FileState.ABSENT
	var problem := ""
	## As parsed (or as migrated); a fresh schema 2 document when not read.
	var document: Dictionary = {}
	var saved: Dictionary[StringName, Saved] = {}
	## Providers in the document that are not read into `saved`.
	var skipped := 0

	func damaged(reason: String) -> Reading:
		state = FileState.DAMAGED
		problem = reason
		return self

	## Readable perhaps, but past this build's bounds: nothing of it is taken in.
	func beyond(reason: String) -> Reading:
		state = FileState.OUT_OF_BOUNDS
		problem = reason
		document = {}
		saved = {}
		return self


static var _id_rule: RegEx

## The saved file this catalog reads and writes.
var path := USER_PATH
var state := FileState.ABSENT
## Why the saved file could not be read; empty when it could.
var problem := ""
## What the last save did besides writing the file (kept a file aside, or why
## it wrote nothing); empty when there was nothing to say.
var note := ""

var _entries: Dictionary[StringName, Entry] = {}
var _saved: Dictionary[StringName, Saved] = {}
## The file as it was parsed (or as migrated), which a save patches and writes.
var _document: Dictionary = {}
## Saves attempted, for the temporary file's name.
var _writes := 0
## What the file a save replaces held when it was last read or written (size
## and SHA-256, or what stands there instead): a save that finds anything else
## there writes nothing.
var _seen := ""


func _init(user_path := USER_PATH) -> void:
	path = user_path
	_document = _fresh()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary:
		var root: Dictionary = parsed
		for listed: Variant in ArtFamily.read_list(root.get("agents", [])):
			var entry := _read_entry(listed)
			if entry != null:
				_entries[entry.id] = entry
	_load()


func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for id in _entries:
		result.append(str(id))
	result.sort()
	return result


func has(id: String) -> bool:
	return _entries.has(StringName(id))


func display_name(id: String) -> String:
	var entry := _entry(StringName(id))
	return entry.display_name if not entry.display_name.is_empty() else id


## The provider's default clothes (sparse), with its badge: the catalog's id,
## or the generic one for a provider it does not know.
func default_look(id: String) -> AvatarLook:
	var entry := _entry(StringName(id))
	var result := entry.look.clothes()
	result.badge = entry.id if has(id) else FALLBACK_ID
	return result


## The option ids the user pinned for this provider, sparse, in the slots this
## build knows; `pinned` lists them. An id may be one this build does not draw
## (a newer pack's). A colour picked as `rgb` is not an option and is not here
## (saved_colours()).
func pins(id: String) -> AvatarLook:
	var result := AvatarLook.new()
	if not _saved.has(StringName(id)):
		return result
	var saved := _saved[StringName(id)]
	for slot in AvatarLook.SLOTS:
		if saved.ids.has(slot):
			result.set_slot(slot, saved.ids[slot])
			result.pinned.append(slot)
	return result


## The colours the user picked for this provider by value, slot -> "rrggbb".
func saved_colours(id: String) -> Dictionary[StringName, String]:
	if not _saved.has(StringName(id)):
		return {}
	return _saved[StringName(id)].colours.duplicate()


## Every slot id saved for this provider, known to this build or not.
func saved_slots(id: String) -> Dictionary[StringName, StringName]:
	if not _saved.has(StringName(id)):
		return {}
	return _saved[StringName(id)].ids.duplicate()


## The slots this build knows where the provider's saved entry holds a value it
## cannot read (neither an id nor a picked colour): slot -> the value as JSON,
## cut to SHOWN_MAX characters. A save keeps each of them unless asked to
## change that slot.
func unreadable(id: String) -> Dictionary[StringName, String]:
	var result: Dictionary[StringName, String] = {}
	var entry: Variant = _looks().get(id)
	if not entry is Dictionary:
		return result
	var slots: Dictionary = entry
	var saved := _saved[StringName(id)] if _saved.has(StringName(id)) else Saved.new()
	for slot in AvatarLook.SLOTS:
		if slots.has(str(slot)) and not saved.ids.has(slot) and not saved.colours.has(slot):
			result[slot] = shown(slots[str(slot)])
	return result


## Whether the provider's saved entry is one a save can change: absent, or a
## JSON object. Anything else (a newer format) is never replaced.
func editable(id: String) -> bool:
	return not _looks().has(id) or _looks()[id] is Dictionary


## The saved file as this catalog holds it (a copy): what the last load, or the
## last save's own text read back, gave. The same as a fresh load of the file.
func held_document() -> Dictionary:
	return _document.duplicate(true)


## Pin this provider's `slots` to what `chosen` names; a slot of `slots` that
## `chosen` leaves empty is unpinned (it varies again). Every other slot, and
## everything else in the file, is kept. A pose is the office's business, not an
## identity, so only slots are kept. Refused, with `note` saying why and nothing
## written, when an id breaks valid_id(), the provider's entry is not one this
## build can change, or the text would not pass verify().
## OK, or the error; `note` says what else happened.
func save_look(id: String, chosen: AvatarLook, slots: Array[StringName] = AvatarLook.SLOTS) -> Error:
	note = _refusal(id, chosen, slots)
	if not note.is_empty():
		return ERR_FILE_CANT_WRITE if state in [FileState.NEWER, FileState.OUT_OF_BOUNDS] else ERR_INVALID_PARAMETER
	var text := encode(_patched(id, chosen, slots))
	var reading := _read_bytes(text.to_utf8_buffer())
	var failed := verify(text, reading, id, chosen, slots)
	if not failed.is_empty():
		note = "Not saved: %s. Nothing was written." % failed
		push_warning("Saved looks %s: %s" % [path, note])
		return ERR_INVALID_DATA
	var stored := _store(text)
	if stored != OK:
		return stored
	# What is on disk now, as the reader read it: a fresh load gives the same.
	_document = reading.document
	_saved = reading.saved
	state = FileState.READ
	problem = ""
	return OK


## The text a save writes for `document`: compact JSON in the document's own key
## order, whole numbers within ±2^53 as integers and every other number at full
## precision, so each value reads back as the same double; strings as
## JsonText.encode() writes them (control characters as \u00XX), so any
## strict JSON parser reads it.
func encode(document: Dictionary) -> String:
	return JsonText.encode(_for_writing(document), true) + "\n"


## Why the text a save of `id` would write must not be written, or "" when it
## may: `reading` is the text as the loader's reader reads it. Each reason ends
## with the name of the check that failed.
func verify(text: String, reading: Reading, id: String, chosen: AvatarLook, slots: Array[StringName]) -> String:
	var size := text.to_utf8_buffer().size()
	if size > MAX_BYTES:
		return "the file would be %d bytes, more than the %d this build reads (check: size)" % [size, MAX_BYTES]
	if reading.state != FileState.READ:
		return "the file would not read back: %s (check: reads back)" % reading.problem
	var sets := false
	for slot in slots:
		sets = sets or not chosen.slot(slot).is_empty()
	if sets and not reading.saved.has(StringName(id)) and reading.saved.size() >= MAX_PROVIDERS:
		return (
			"too many saved providers: %s would be past the first %d this build reads (check: provider cap)"
			% [id, MAX_PROVIDERS]
		)
	var after := reading.saved[StringName(id)] if reading.saved.has(StringName(id)) else Saved.new()
	for slot in slots:
		var value := chosen.slot(slot)
		var got: StringName = after.ids[slot] if after.ids.has(slot) else &""
		if got != value or (value.is_empty() and after.colours.has(slot)):
			var wanted := "unpinned" if value.is_empty() else str(value)
			return "%s's %s would not read back as %s (check: set reads back)" % [id, slot, wanted]
	var hidden := _hidden(reading, id, slots)
	if not hidden.is_empty():
		return hidden
	return _changed(reading.document, id, slots)


## A value as JSON for a person to read, cut to SHOWN_MAX characters.
static func shown(value: Variant) -> String:
	var text := JsonText.encode(_for_writing(value), true)
	return text if text.length() <= SHOWN_MAX else text.left(SHOWN_MAX - 1) + "…"


## `value` as an id when it follows the one id rule every id here follows
## (`[a-z0-9][a-z0-9_-]*`, 1 to 64 characters, the whole text); empty otherwise.
static func valid_id(value: Variant) -> StringName:
	if not (value is String or value is StringName):
		return &""
	var text := str(value)
	if text.is_empty() or text.length() > MAX_ID:
		return &""
	if _id_rule == null:
		_id_rule = RegEx.create_from_string(ID_PATTERN)
	var found := _id_rule.search(text)
	# `$` also matches before a final line break: the match must be the whole text.
	return StringName(text) if found != null and found.get_end() == text.length() else &""


## The temporary file the next save writes before it renames it over the saved
## file: beside the file it replaces, named for this process and the save, so
## two processes or two saves never share one.
func temporary_path() -> String:
	return "%s.%d-%d.tmp" % [_target(), OS.get_process_id(), _writes]


## A saved v1 look ({"hair", "outfit"}) as v2 slots: the frozen table from the
## day the slots replaced them (docs/ASSET_SPEC.md). A value this table does not
## know pins nothing for its slots.
static func migrate_v1(hair: StringName, outfit: StringName) -> Dictionary[StringName, StringName]:
	var result: Dictionary[StringName, StringName] = {}
	match hair:
		&"short":
			result = {AvatarLook.HAIR_STYLE: &"short", AvatarLook.HAIR_COLOUR: &"brown", AvatarLook.HEADWEAR: &"none"}
		&"curl":
			result = {AvatarLook.HAIR_STYLE: &"curl", AvatarLook.HAIR_COLOUR: &"auburn", AvatarLook.HEADWEAR: &"none"}
		&"cap":
			result = {
				AvatarLook.HAIR_STYLE: &"short",
				AvatarLook.HAIR_COLOUR: &"umber",
				AvatarLook.HEADWEAR: &"cap",
				AvatarLook.HEADWEAR_COLOUR: &"sea",
			}
		&"hood":
			result = {AvatarLook.HAIR_STYLE: &"short", AvatarLook.HAIR_COLOUR: &"brown", AvatarLook.HEADWEAR: &"hood"}
			# The hood took the outfit's colour; the outfits' tops are headwear
			# colours of the same names and ramps.
			if [&"slate", &"cream", &"terra", &"teal", &"lilac"].has(outfit):
				result[AvatarLook.HEADWEAR_COLOUR] = outfit
	var legs: Dictionary[StringName, StringName] = {
		&"slate": &"charcoal", &"cream": &"brown", &"terra": &"taupe", &"teal": &"denim", &"lilac": &"plum"
	}
	if legs.has(outfit):
		result[AvatarLook.TOP] = outfit
		result[AvatarLook.LEGS] = legs[outfit]
	return result


func _entry(id: StringName) -> Entry:
	if _entries.has(id):
		return _entries[id]
	var fallback := Entry.new()
	fallback.id = FALLBACK_ID
	fallback.display_name = FALLBACK_NAME
	return fallback


static func _read_entry(listed: Variant) -> Entry:
	if not listed is Dictionary:
		return null
	var data: Dictionary = listed
	var id := valid_id(data.get("id"))
	if id.is_empty():
		push_error("%s: agent id %s breaks the id rule %s" % [CATALOG_PATH, data.get("id"), ID_PATTERN])
		return null
	var result := Entry.new()
	result.id = id
	result.display_name = str(data.get("name", id))
	result.command = str(data.get("command", ""))
	var look: Variant = data.get("look", {})
	if look is Dictionary:
		var chosen: Dictionary = look
		for slot in AvatarLook.SLOTS:
			var value := valid_id(chosen.get(str(slot)))
			if not value.is_empty():
				result.look.set_slot(slot, value)
	return result


## "rrggbb" when `value` is {"rgb": six lowercase hex digits} and nothing else.
static func _rgb(value: Variant) -> String:
	if not value is Dictionary:
		return ""
	var picked: Dictionary = value
	if picked.size() != 1 or not picked.get("rgb") is String:
		return ""
	var text: String = picked["rgb"]
	if text.length() != 6 or not text.is_valid_hex_number() or text != text.to_lower():
		return ""
	return text


# --- the saved file ---------------------------------------------------------------


static func _fresh() -> Dictionary:
	return {"schema_version": SAVE_SCHEMA, "looks": {}}


func _load() -> void:
	var at := _target()
	# Noted before reading: a change in between makes the next save refuse, never write over it.
	_seen = _fingerprint(at)
	if not FileAccess.file_exists(at):
		state = FileState.ABSENT
		return
	var file := FileAccess.open(at, FileAccess.READ)
	if file == null:
		_apply(Reading.new().damaged("it cannot be opened (error %d)" % FileAccess.get_open_error()))
		return
	if file.get_length() > MAX_BYTES:
		_apply(Reading.new().beyond(_too_large()))
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	_apply(_read_bytes(bytes))


## What a reading of the file means for this catalog, said once in the log.
func _apply(reading: Reading) -> void:
	state = reading.state
	problem = reading.problem
	_document = reading.document if not reading.document.is_empty() else _fresh()
	_saved = reading.saved
	match state:
		FileState.DAMAGED:
			push_warning(
				(
					"Saved looks %s cannot be read: %s. Using the defaults; the file is kept aside at the first save."
					% [path, problem]
				)
			)
		FileState.NEWER, FileState.OUT_OF_BOUNDS:
			push_warning("Saved looks %s: %s; nothing is read and nothing will be written" % [path, problem])
	if reading.skipped > 0:
		push_warning(
			"Saved looks %s: %d entries are not readable here; they are kept as they are" % [path, reading.skipped]
		)


## The one reader: the saved file's bytes as this build reads them. Quiet:
## nothing it cannot read goes to the log.
static func _read_bytes(bytes: PackedByteArray) -> Reading:
	var result := Reading.new()
	if bytes.size() > MAX_BYTES:
		return result.beyond(_too_large())
	# Checked first, so decoding never logs what it cannot read.
	if not _is_utf8(bytes):
		return result.damaged("it is not UTF-8 text")
	# JSON.parse_string would print what it cannot read into the log.
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return result.damaged("it is not JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return result.damaged("it is not a JSON object")
	var root: Dictionary = json.data
	_read_root(root, result)
	# A file this build reads, only deeper than it takes in: kept as it is, never written.
	if result.state in [FileState.READ, FileState.MIGRATED] and _deeper_than(root, MAX_DEPTH):
		return result.beyond("it is too deep for this build (more than %d levels)" % MAX_DEPTH)
	return result


static func _too_large() -> String:
	return "it is too large for this build (more than %d bytes)" % MAX_BYTES


## The parsed file: today's unversioned v1, schema 2, a newer one, or damaged.
static func _read_root(root: Dictionary, result: Reading) -> void:
	if not root.has("schema_version"):
		result.document = _read_v1(root)
		result.state = FileState.MIGRATED
		_index(result)
		return
	var version := ArtFamily.whole(root["schema_version"])
	if version > SAVE_SCHEMA:
		result.state = FileState.NEWER
		result.problem = "a newer Herdstead wrote it (schema_version %d)" % version
		return
	if version != SAVE_SCHEMA:
		result.damaged("its schema_version is not one this build reads")
		return
	if root.has("looks") and not root["looks"] is Dictionary:
		result.damaged('its "looks" is not a JSON object')
		return
	if not root.has("looks"):
		root["looks"] = {}
	result.document = root
	result.state = FileState.READ
	_index(result)


## What of the document this build can read, into `saved`. Nothing is dropped
## from the document: what is not read here is kept as it is.
static func _index(result: Reading) -> void:
	var looks: Dictionary = result.document["looks"]
	for provider: Variant in looks:
		var id := valid_id(provider)
		if id.is_empty() or not looks[provider] is Dictionary or result.saved.size() >= MAX_PROVIDERS:
			result.skipped += 1
			continue
		var entry: Dictionary = looks[provider]
		var saved := _read_saved(entry)
		if not saved.is_empty():
			result.saved[id] = saved


## One provider's slots this build can read: the slots it knows first, so a
## file listing many unknown slots cannot push them past MAX_SLOTS. Anything
## else stays in the document, untouched.
static func _read_saved(entry: Dictionary) -> Saved:
	var saved := Saved.new()
	var order: Array = []
	for slot in AvatarLook.SLOTS:
		if entry.has(str(slot)):
			order.append(str(slot))
	for slot_key: Variant in entry:
		if not order.has(slot_key):
			order.append(slot_key)
	for slot_key: Variant in order:
		var slot := valid_id(slot_key)
		if slot.is_empty() or saved.ids.size() + saved.colours.size() >= MAX_SLOTS:
			continue
		var id := valid_id(entry[slot_key])
		var colour := _rgb(entry[slot_key])
		if not id.is_empty():
			saved.ids[slot] = id
		elif not colour.is_empty():
			saved.colours[slot] = colour
	return saved


static func _read_v1(root: Dictionary) -> Dictionary:
	var looks := {}
	for provider: Variant in root:
		var id := valid_id(provider)
		if id.is_empty() or not root[provider] is Dictionary or looks.size() >= MAX_PROVIDERS:
			continue
		var old: Dictionary = root[provider]
		var slots := migrate_v1(valid_id(old.get("hair")), valid_id(old.get("outfit")))
		if slots.is_empty():
			continue
		var entry := {}
		for slot in slots:
			entry[str(slot)] = str(slots[slot])
		looks[str(id)] = entry
	# What the table cannot translate stays in the old file, which the first
	# save keeps beside the new one.
	return {"schema_version": SAVE_SCHEMA, "looks": looks}


func _looks() -> Dictionary:
	var looks: Dictionary = _document.get("looks", {})
	_document["looks"] = looks
	return looks


## Why a save of `id` is refused before any text is made, or "": an id the
## reader would not keep, a newer file, an entry in a format this build does
## not read.
func _refusal(id: String, chosen: AvatarLook, slots: Array[StringName]) -> String:
	if valid_id(id).is_empty():
		return 'Not saved: "%s" is not an id this build keeps (%s, at most %d).' % [id, ID_PATTERN, MAX_ID]
	for slot in slots:
		var value := chosen.slot(slot)
		if not value.is_empty() and valid_id(value).is_empty():
			return 'Not saved: "%s" is not an option id this build keeps.' % value
	if state in [FileState.NEWER, FileState.OUT_OF_BOUNDS]:
		return "Not saved: %s, and it is never written over." % problem
	if not editable(id):
		return (
			"Not saved: %s's saved entry is in a format this build doesn't read (%s); it is left as it is."
			% [id, shown(_looks()[id])]
		)
	return ""


## The document with `id`'s `slots` set to what `chosen` names (dropped when
## empty) and schema_version as this build writes it. Shallow copies: every
## other value is the one that was read (never a deep copy, which stops at ~100
## levels), and the document itself is not changed.
func _patched(id: String, chosen: AvatarLook, slots: Array[StringName]) -> Dictionary:
	var looks := _looks().duplicate()
	var entry: Dictionary = {}
	if looks.has(id):
		var current: Dictionary = looks[id]
		entry = current.duplicate()
	var had := entry.size()
	for slot in slots:
		var value := chosen.slot(slot)
		if value.is_empty():
			entry.erase(str(slot))
		else:
			entry[str(slot)] = str(value)
	if not entry.is_empty():
		looks[id] = entry
	elif had > 0:
		# Emptied by this save. An entry that was already `{}` stays as it was.
		looks.erase(id)
	var document := _document.duplicate()
	document["schema_version"] = SAVE_SCHEMA
	document["looks"] = looks
	return document


## Which value read before a save of `id` would no longer read the same after it
## (other than the slots it was asked to change), as the reason verify() gives,
## or "".
func _hidden(reading: Reading, id: String, slots: Array[StringName]) -> String:
	for provider in _saved:
		var was := _saved[provider]
		var now := reading.saved[provider] if reading.saved.has(provider) else Saved.new()
		var asked := str(provider) == id
		for slot in was.ids:
			if not (asked and slots.has(slot)) and now.ids.get(slot, &"") != was.ids[slot]:
				return "%s's %s would no longer read as %s (check: readable before)" % [provider, slot, was.ids[slot]]
		for slot in was.colours:
			if not (asked and slots.has(slot)) and now.colours.get(slot, "") != was.colours[slot]:
				return (
					"%s's %s would no longer read as #%s (check: readable before)" % [provider, slot, was.colours[slot]]
				)
	return ""


## What a save of `id` would change that it was not asked to, as the reason
## verify() gives, or "": every top-level key, every other provider, and every
## other slot of `id`, compared as the JSON a save writes.
func _changed(after: Dictionary, id: String, slots: Array[StringName]) -> String:
	for key: Variant in _document:
		if key == "looks" or key == "schema_version":
			continue
		if not after.has(key) or not _same(_document[key], after[key]):
			return "the top-level %s would not be kept as it is (check: pass-through)" % shown(key)
	var before := _looks()
	var now: Dictionary = after["looks"]
	for provider: Variant in before:
		if not now.has(provider) and not (provider == id):
			return "%s's saved entry would not be kept (check: pass-through)" % shown(provider)
		if provider != id:
			if not _same(before[provider], now[provider]):
				return "%s's saved entry would not be kept as it is (check: pass-through)" % shown(provider)
			continue
		var was: Dictionary = before[provider]
		var is_now: Dictionary = now.get(provider, {})
		for slot: Variant in was:
			if slots.has(StringName(str(slot))):
				continue
			if not is_now.has(slot) or not _same(was[slot], is_now[slot]):
				return "%s's %s would not be kept as it is (check: pass-through)" % [id, shown(slot)]
	return ""


## Whether two JSON values are the same as a save writes them.
static func _same(one: Variant, other: Variant) -> bool:
	return JsonText.encode(_for_writing(one), true) == JsonText.encode(_for_writing(other), true)


## A copy of a JSON value to write: whole numbers within ±2^53 (JSON parses
## every number as a float) become integers again; everything else as it is.
static func _for_writing(value: Variant) -> Variant:
	if value is float:
		var number: float = value
		if number == floorf(number) and absf(number) <= EXACT_WHOLE:
			return int(number)
		return number
	if value is Dictionary:
		var source: Dictionary = value
		var copy := {}
		for key: Variant in source:
			copy[key] = _for_writing(source[key])
		return copy
	if value is Array:
		var list: Array = value
		var copy := []
		for item: Variant in list:
			copy.append(_for_writing(item))
		return copy
	return value


## Whether `value` nests more than `levels` deep (an object or array is one
## level); stops looking as soon as it knows.
static func _deeper_than(value: Variant, levels: int) -> bool:
	if not (value is Dictionary or value is Array):
		return false
	if levels <= 0:
		return true
	var children: Array = []
	if value is Dictionary:
		var map: Dictionary = value
		children = map.values()
	else:
		children = value
	for child: Variant in children:
		if _deeper_than(child, levels - 1):
			return true
	return false


## The file a save replaces: `path`, or where its symbolic links lead (at most
## MAX_LINKS; past that, the last link, which a save refuses).
func _target() -> String:
	var at := ProjectSettings.globalize_path(path)
	for _link in MAX_LINKS:
		var folder := DirAccess.open(at.get_base_dir())
		if folder == null or not folder.is_link(at.get_file()):
			return at
		var leads := folder.read_link(at.get_file())
		at = leads if leads.is_absolute_path() else at.get_base_dir().path_join(leads).simplify_path()
	return at


func _store(text: String) -> Error:
	note = ""
	var at := _target()
	if _is_link(at):
		note = (
			"Not saved: %s leads through more than %d symbolic links (or round in a loop); it is left as it is."
			% [ProjectSettings.globalize_path(path), MAX_LINKS]
		)
		return ERR_FILE_CANT_WRITE
	if _fingerprint(at) != _seen:
		note = "Not saved: the saved file changed on disk since it was read; reopen to see it. Nothing was written."
		return ERR_FILE_CANT_WRITE
	var kept := ""
	if _exists(at) and state == FileState.DAMAGED:
		var aside := _free_name(at, "damaged-" + _stamp())
		var moved := DirAccess.rename_absolute(at, aside)
		if moved != OK:
			note = "Not saved: the unreadable file could not be moved aside (error %d)." % moved
			return moved
		_seen = _fingerprint(at)
		kept = "The unreadable file was kept as %s." % aside
	elif _exists(at) and state == FileState.MIGRATED:
		var backup := _free_name(at, "v1")
		var copied := DirAccess.copy_absolute(at, backup)
		if copied != OK:
			note = "Not saved: the old file could not be kept as %s (error %d); nothing was written." % [backup, copied]
			return copied
		kept = "The old file was kept as %s." % backup
	var written := _write(at, text)
	if written != OK:
		var why := "it is a folder" if DirAccess.dir_exists_absolute(at) else error_string(written)
		note = "Not saved: %s could not be written (%s, error %d); the old file is untouched." % [at, why, written]
		if state == FileState.DAMAGED and not kept.is_empty():
			# The damaged file was already moved aside: say so, and where.
			note = (
				"Not saved: %s could not be written (%s, error %d). %s Nothing was written in its place."
				% [at, why, written, kept]
			)
		return written
	_seen = _fingerprint(at)
	note = kept
	return OK


## What stands at `at` now: a file's size and SHA-256, a folder, or nothing.
static func _fingerprint(at: String) -> String:
	if DirAccess.dir_exists_absolute(at):
		return "folder"
	if not FileAccess.file_exists(at):
		return "absent"
	var file := FileAccess.open(at, FileAccess.READ)
	if file == null:
		return "unopenable (error %d)" % FileAccess.get_open_error()
	var size := file.get_length()
	file.close()
	return "%d %s" % [size, FileAccess.get_sha256(at)]


static func _is_link(at: String) -> bool:
	var folder := DirAccess.open(at.get_base_dir())
	return folder != null and folder.is_link(at.get_file())


## The text to a temporary file of this save's own, flushed and closed, then
## renamed over `at`; the temporary file is removed on any failure.
func _write(at: String, text: String) -> Error:
	var temporary := temporary_path()
	_writes += 1
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var written := file.get_error()
	file.close()
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return written
	var renamed := DirAccess.rename_absolute(temporary, at)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
	return renamed


## `<file's name>.<label>.json` beside `at`, or with -2, -3 ... when taken (by a
## file or a directory).
static func _free_name(at: String, label: String) -> String:
	var base := at.get_basename()
	var candidate := "%s.%s.json" % [base, label]
	var index := 2
	while _exists(candidate):
		candidate = "%s.%s-%d.json" % [base, label, index]
		index += 1
	return candidate


static func _exists(at: String) -> bool:
	return FileAccess.file_exists(at) or DirAccess.dir_exists_absolute(at)


static func _stamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return (
		"%04d%02d%02d-%02d%02d%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]
	)


## Whether `bytes` is well-formed UTF-8 (no overlongs, surrogates or values past
## U+10FFFF), checked by hand so nothing is decoded, or logged, before it is.
static func _is_utf8(bytes: PackedByteArray) -> bool:
	var at := 0
	var size := bytes.size()
	while at < size:
		var lead := bytes[at]
		var length := 1
		var low := 0x80
		var high := 0xBF
		if lead < 0x80:
			at += 1
			continue
		if lead >= 0xC2 and lead <= 0xDF:
			length = 2
		elif lead >= 0xE0 and lead <= 0xEF:
			length = 3
			low = 0xA0 if lead == 0xE0 else 0x80
			high = 0x9F if lead == 0xED else 0xBF
		elif lead >= 0xF0 and lead <= 0xF4:
			length = 4
			low = 0x90 if lead == 0xF0 else 0x80
			high = 0x8F if lead == 0xF4 else 0xBF
		else:
			return false
		if at + length > size:
			return false
		if bytes[at + 1] < low or bytes[at + 1] > high:
			return false
		for next in range(at + 2, at + length):
			if bytes[next] < 0x80 or bytes[next] > 0xBF:
				return false
		at += length
	return true
