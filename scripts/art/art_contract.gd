class_name ArtContract
extends RefCounted
## What the scenes need from an art pack, and the check that a pack has it.
##
## The set of semantic IDs a scene draws with is only known to the code that
## draws, so it is written down here, next to that code, and every pack is
## checked against it (tools/check_packs.gd in `make check`, tools/check_pack.gd
## inside an exported PCK). Scene code names an ID through these constants, so a
## typo is a parse error rather than a missing texture at runtime.
##
## `tools/build_assets.py` keeps the other half: what a pack's own files have to
## look like (PNG geometry, hard alpha, palette discipline, atlas cells). It no
## longer guesses which of them the scenes use.

# --- palette --------------------------------------------------------------------

const INK := &"ink"
const SLATE := &"slate"
const CREAM := &"cream"
const PAPER := &"paper"
const CREAM_SHADOW := &"cream_shadow"
const MUTED := &"muted"
const WOOD_DARK := &"wood_dark"
const WOOD_SHADOW := &"wood_shadow"
const WORKING := &"working"
const BLOCKED := &"blocked"
const TASK_LIGHT := &"task_light"
const CONTACT_SHADOW := &"contact_shadow"
## The done state's own colour (its badge is `unread`): an UNREAD window in the
## building section.
const UNREAD := &"unread"
## Structure accents, never state: a worktree group's floors share one on their
## plates (HudTheme's PlateAccent variations, in this order).
const SAGE := &"sage"
const SKY := &"sky"
const TERRA := &"terra"
const TEAL := &"teal"
const LILAC := &"lilac"
const ACCENTS: Array[StringName] = [SAGE, SKY, TERRA, TEAL, LILAC]
## Several of these carry a broad surface and text or an icon at once (`ink` is
## outline and body text, `cream` is wall and top-bar text, `paper` is panel and
## heading, `blocked` is badge and selection frame, `muted` is the top bar's
## theme name), so a new theme may not darken only one of the two.
const PALETTE_KEYS: Array[StringName] = [
	INK,
	SLATE,
	CREAM,
	PAPER,
	CREAM_SHADOW,
	MUTED,
	WOOD_DARK,
	WOOD_SHADOW,
	WORKING,
	BLOCKED,
	TASK_LIGHT,
	CONTACT_SHADOW,
	UNREAD,
	SAGE,
	SKY,
	TERRA,
	TEAL,
	LILAC,
]

# --- tiles ----------------------------------------------------------------------

const FLOOR_WALKWAY := &"floor.walkway"
## The three interchangeable wood variants, picked per cell so a floor does not
## read as one plank repeated; their outer 3px match, so the seam never moves.
const FLOOR_WOOD: Array[StringName] = [&"floor.wood_a", &"floor.wood_b", &"floor.wood_c"]
const RUG_ROWS: Array[StringName] = [&"top", &"middle", &"bottom"]
const RUG_COLUMNS: Array[StringName] = [&"left", &"center", &"right"]
## The floor's shell: behind every row of tables stand two courses of brick,
## the cap on top and the face below it, and the two side walls run the whole
## depth of the floor. `wall.front_*` and `wall.threshold` stay unused — see
## docs/WORLD_MODEL.md for why there is no front wall.
const WALL_CAP := &"cap"
const WALL_FACE := &"face"
const WALL_COURSES: Array[StringName] = [WALL_CAP, WALL_FACE]
const WALL_ENDS: Array[StringName] = [&"left", &"center", &"right"]
## The finite topology of the office: inner walls meet the left shell and
## finish before the right-hand main aisle. Each junction owns both courses.
const WALL_T_LEFT := &"t_left"
const WALL_END_RIGHT := &"end_right"
const WALL_JUNCTIONS: Array[StringName] = [WALL_T_LEFT, WALL_END_RIGHT]
const WALL_SIDE_LEFT := &"wall.side_left"
const WALL_SIDE_RIGHT := &"wall.side_right"

# --- props and UI images --------------------------------------------------------

## What a floor stands or hangs: the sign over each table row, the window and
## lift door on the outer wall, and the two pieces of standing furniture. All
## but the sign are furniture in the strict sense — they carry no herdr field —
## and `desk`, `monitor` and `chair` are drawn from the shared table's own art
## rather than from these.
const PROP_SIGN := &"sign"
const PROP_WINDOW := &"window"
## The same window at night (DayLight): its frame pixel for pixel, the view dark.
const PROP_WINDOW_NIGHT := &"window_night"
const PROP_DOOR := &"door"
const PROP_PLANT := &"plant"
## The second plant: the same piece in another pot, alternating with
## PROP_PLANT by place along a run (OfficeDecorPlanner.plant_at()).
const PROP_PLANT_B := &"plant_b"
const PROP_CABINET := &"cabinet"
## A framed picture on a row wall: furnishing hung beside the signs on a
## grid of the wall itself, never a signal.
const PROP_WALL_FRAME := &"wall_frame"
## The entry band's two counters (docs/VISUAL_LANGUAGE.md): furniture only.
## Idle agents rest at the pantry; nobody rests at the reception, which carries
## no herdr field at all (the space in front of it stays empty).
const PROP_RECEPTION := &"reception"
const PROP_PANTRY := &"pantry"
## A signal, not furniture: the stack of paper the table puts beside the laptop
## of a seat whose agent is done and not yet looked at (OfficeTable.show_papers()).
## Never in a pool (ITEM_GROUPS): it is placed by code, by state.
const PROP_DONE_STACK := &"done_stack"
const PROP_IDS: Array[StringName] = [
	PROP_SIGN,
	PROP_WINDOW,
	PROP_WINDOW_NIGHT,
	PROP_DOOR,
	PROP_PLANT,
	PROP_PLANT_B,
	PROP_CABINET,
	PROP_WALL_FRAME,
	PROP_RECEPTION,
	PROP_PANTRY,
]
## The pools scenes draw furniture from by weight (ItemSpec.group in the pack,
## docs/ITEMS.md), and what their members must stand on: never agent states.
## Every pack has at least one of each.
const ITEM_GROUPS: Dictionary[StringName, StringName] = {
	&"desk": ItemSpec.PLACE_DESK,
	&"cat": ItemSpec.PLACE_DESK,
	&"plant": ItemSpec.PLACE_FLOOR,
}
const UI_PANEL := &"panel"
const UI_SELECTION := &"selection"
const UI_BRANCH := &"branch"
## Three display overlays, not herdr states: a pane whose agent is still
## starting, a machine that has dropped, and one that is answering. The
## minimap's building headings wear all three.
const UI_STARTING := &"starting"
const UI_OFFLINE := &"offline"
const UI_CONNECTED := &"connected"

# --- states and animations ------------------------------------------------------

const STATE_WORKING := &"working"
const STATE_BLOCKED := &"blocked"
const STATE_DONE := &"done"
const STATE_IDLE := &"idle"
const STATE_UNKNOWN := &"unknown"
## Every state herdr reports and this office draws. The projection refuses any
## other, so a pack that misses one leaves panes undrawable.
const STATES: Array[StringName] = [STATE_WORKING, STATE_BLOCKED, STATE_DONE, STATE_IDLE, STATE_UNKNOWN]

const ANIMATION_IDLE := &"idle"
const ANIMATION_WORKING := &"working"
const ANIMATION_BLOCKED := &"blocked"
const ANIMATION_STARTING := &"starting"
## The semantic animations a state may name. The pixel people have to map every
## one of them to a track in both poses (see _people_problems()).
const ANIMATIONS: Array[StringName] = [ANIMATION_IDLE, ANIMATION_WORKING, ANIMATION_BLOCKED, ANIMATION_STARTING]
## The track anyone walking across a floor plays (OfficePresentation), whatever
## their state: drawn from the front, the back and the side, since a route
## turns all four ways.
const TRACK_WALK := &"walk"
## The track whoever rests in the pantry plays (OfficeStation), by name rather
## than through a state: `idle` is also who sits at a desk. Drawn from the
## front, since they face the viewer there.
const TRACK_DRINK := &"drink"

# --- the shared table -----------------------------------------------------------

## The modules OfficeTable lays along the table, and the two pieces of furniture
## it and OfficeStation place on and beside it.
const TABLE_MODULES: Array[StringName] = [
	&"surface_left",
	&"surface_mid_a",
	&"surface_mid_b",
	&"surface_right",
	&"apron_left",
	&"apron_mid",
	&"apron_right",
	&"divider_left",
	&"divider_mid",
	&"divider_right",
	&"leg",
	&"bracket",
]
const FURNITURE_CHAIR := &"chair"
const FURNITURE_MONITOR := &"monitor"
const CHAIR_FRONT := &"front"
const CHAIR_BACK := &"back"
const MONITOR_REAR := &"rear_shell"
const MONITOR_FRONT := &"front_privacy"
const SHELL_REAR := &"shell_rear"
const SHELL_FRONT := &"shell_front"


## Every reason `pack` cannot dress the scenes; empty when it can. Structure
## first (the IDs above), then referential integrity (a state's badge is a real
## UI image), then the files themselves, because a manifest that names an image
## it does not ship draws nothing and says nothing.
static func problems(pack: ArtPack) -> PackedStringArray:
	var found := PackedStringArray()
	if pack == null:
		found.append("the pack did not load")
		return found
	for key in PALETTE_KEYS:
		if not pack.palette.has(key):
			found.append("palette: no colour named " + key)
	for tile in tile_ids():
		if not pack.tiles.has(tile):
			found.append("tiles: no cell for " + tile)
	for piece in prop_ids():
		if pack.prop_sprite(piece) == null:
			found.append("props: no " + piece)
	for group in ITEM_GROUPS:
		var members := pack.items_in(group)
		if members.is_empty():
			found.append("props: nothing in the %s pool" % group)
		for member in members:
			if member.item.place != ITEM_GROUPS[group]:
				found.append("props: %s is in the %s pool but stands on the %s" % [member.id, group, member.item.place])
	var stack := pack.prop_sprite(PROP_DONE_STACK)
	if stack != null and stack.item != null and not stack.item.group.is_empty():
		found.append("props: %s is a signal, never in a pool" % PROP_DONE_STACK)
	for image in ui_ids():
		if pack.ui_sprite(image) == null:
			found.append("ui: no image named " + image)
	var panel := pack.panel()
	if panel != null and not panel.nine_patched():
		found.append("ui: the panel carries no nine_patch margins")
	for name in STATES:
		var drawn := pack.state(name)
		if drawn == null:
			found.append("states: herdr's " + name + " is not drawn")
			continue
		if not ANIMATIONS.has(drawn.animation):
			found.append("states: %s plays %s, which is not a semantic animation" % [name, drawn.animation])
		if pack.ui_sprite(drawn.badge) == null:
			found.append("states: %s wears %s, which is not a UI image" % [name, drawn.badge])
	if pack.state(STATE_DONE) != null and pack.state(STATE_DONE).badge != &"unread":
		found.append("states: done means unread, not task success")
	found.append_array(_people_problems(pack.people))
	found.append_array(_table_problems(pack.table))
	found.append_array(_file_problems(pack))
	return found


## Every tile a floor is laid out of: the wood variants, the walkway between the
## rows, the nine-slice rug under each table, and the floor's shell.
static func tile_ids() -> Array[StringName]:
	var result: Array[StringName] = [FLOOR_WALKWAY, WALL_SIDE_LEFT, WALL_SIDE_RIGHT]
	result.append_array(FLOOR_WOOD)
	for row in RUG_ROWS:
		for column in RUG_COLUMNS:
			result.append(rug_cell(row, column))
	for course in WALL_COURSES:
		for end in WALL_ENDS:
			result.append(wall_cell(course, end))
		for junction in WALL_JUNCTIONS:
			result.append(wall_cell(course, junction))
	return result


## One brick of a row's wall: the cap course or the face course, at the left
## end, the right end, a junction or anywhere between. Built rather than named,
## the way a rug cell is; atlas positions remain the art family's business.
static func wall_cell(course: StringName, end: StringName) -> StringName:
	return StringName("wall.%s_%s" % [course, end])


## One cell of the stretchable rug. The row and column come from the rug's size,
## so this is the one semantic ID the scenes build rather than name.
static func rug_cell(row: StringName, column: StringName) -> StringName:
	return StringName("rug.%s_%s" % [row, column])


## Every UI image a scene draws: the fixed ones, plus every state's badge.
static func ui_ids() -> Array[StringName]:
	return [
		UI_PANEL,
		UI_SELECTION,
		UI_BRANCH,
		UI_STARTING,
		UI_OFFLINE,
		UI_CONNECTED,
		&"working",
		&"blocked",
		&"unread",
		&"idle",
		&"unknown"
	]


## What the office asks of the pixel people, beyond what their manifest already
## promises: every semantic animation a state may name plays a track in both
## poses, drawn from the front for whoever faces the viewer, and at a desk from
## behind as well, because a near worker shows the viewer their back; and the
## walk (TRACK_WALK) is drawn every way a route can turn, and the pantry's drink
## (TRACK_DRINK) from the front.
static func _people_problems(people: PixelPeople) -> PackedStringArray:
	var found := PackedStringArray()
	if people == null:
		found.append("people: the shared pixel people did not load")
		return found
	for context in AvatarLook.CONTEXTS:
		for animation in ANIMATIONS:
			var id := people.track(context, animation)
			if not people.tracks.has(id):
				found.append("people: %s/%s maps to %s, which is not a track" % [context, animation, id])
				continue
			var drawn := people.tracks[id].facings
			if not drawn.has(PixelPeople.FRONT):
				found.append("people: %s/%s plays %s, which has no front" % [context, animation, id])
			if context == AvatarLook.DESK and not drawn.has(PixelPeople.BACK):
				found.append("people: desk/%s plays %s, which has no back for the near side" % [animation, id])
	if not people.tracks.has(TRACK_WALK):
		found.append("people: no %s track for whoever walks across a floor" % TRACK_WALK)
	else:
		for facing in PixelPeople.DRAWN:
			if not people.tracks[TRACK_WALK].facings.has(facing):
				found.append("people: %s has no %s, and a route turns every way" % [TRACK_WALK, facing])
	if not people.tracks.has(TRACK_DRINK):
		found.append("people: no %s track for whoever rests in the pantry" % TRACK_DRINK)
	elif not people.tracks[TRACK_DRINK].facings.has(PixelPeople.FRONT):
		found.append("people: %s has no front, and the pantry faces the viewer" % TRACK_DRINK)
	return found


static func _table_problems(table: TablePack) -> PackedStringArray:
	var found := PackedStringArray()
	if table == null or table.modules.is_empty():
		found.append("table: the pack ships no shared table, so it cannot furnish a floor")
		return found
	for module in TABLE_MODULES:
		if not table.modules.has(module):
			found.append("table: no module named " + module)
	var wanted := furniture_views()
	for name in wanted:
		var piece := table.piece(name)
		if piece == null:
			found.append("table: no furniture named " + name)
			continue
		for view: StringName in wanted[name]:
			var module := piece.view(view)
			if module.is_empty() or not table.modules.has(module):
				found.append("table: %s has no %s view" % [name, view])
	return found


## Every image and font the pack names has to be there. Inside an exported PCK a
## PNG is a remapped import that FileAccess cannot see, so ArtFamily.has_file()
## asks ResourceLoader for res:// and the filesystem for a loose pack.
static func _file_problems(pack: ArtPack) -> PackedStringArray:
	var found := PackedStringArray()
	if not pack.has_file(pack.atlas_path):
		found.append("files: no tile atlas at " + pack.atlas_path)
	for sprite_id in pack.props:
		if not pack.has_file(pack.props[sprite_id].path):
			found.append("files: no props/%s at %s" % [sprite_id, pack.props[sprite_id].path])
	for sprite_id in pack.ui:
		if not pack.has_file(pack.ui[sprite_id].path):
			found.append("files: no ui/%s at %s" % [sprite_id, pack.ui[sprite_id].path])
	if not pack.has_file(pack.font_path):
		found.append("files: no font at " + pack.font_path)
	# The licence is not a resource: it only ships through the export preset's
	# include filter, so it is asked for on the filesystem in either case.
	if not FileAccess.file_exists(pack.base_path.path_join(pack.font_license_path)):
		found.append("files: no font licence at " + pack.font_license_path)
	if pack.table != null:
		for module in pack.table.modules:
			if not pack.table.has_file(pack.table.modules[module].path):
				found.append("files: no table module %s at %s" % [module, pack.table.modules[module].path])
	if pack.people != null:
		for strip in pack.people.files:
			if not pack.people.has_file(strip):
				found.append("files: no pixel people strip " + strip)
	return found


# --- what a pack carries that nothing above asks for ----------------------------


## Every prop a scene places by its id; the pools' members are drawn by group.
static func prop_ids() -> Array[StringName]:
	var ids: Array[StringName] = PROP_IDS.duplicate()
	ids.append(PROP_DONE_STACK)
	return ids


## Each piece of furniture on or beside a table, and the views it is drawn from.
static func furniture_views() -> Dictionary[StringName, Array]:
	return {
		FURNITURE_CHAIR: [CHAIR_FRONT, CHAIR_BACK],
		FURNITURE_MONITOR: [MONITOR_REAR, MONITOR_FRONT, SHELL_REAR, SHELL_FRONT],
	}


## Every shared-table module a scene draws: the ones OfficeTable lays along the
## table, plus whichever modules this pack's furniture names as its views.
static func table_module_ids(table: TablePack) -> Array[StringName]:
	var result: Array[StringName] = []
	result.append_array(TABLE_MODULES)
	if table == null:
		return result
	var views := furniture_views()
	for name in views:
		var piece := table.piece(name)
		if piece == null:
			continue
		for view: StringName in views[name]:
			var module := piece.view(view)
			if not module.is_empty() and not result.has(module):
				result.append(module)
	return result


## What a pack ships that no scene asks for, by category (tiles, props, ui,
## table). Not a failure: a pack may carry art for a scene nobody has written
## yet. But art nothing draws is dead weight, and finding it should not mean
## grepping the source, so `tools/check_packs.gd` prints this for every pack.
## It compares the pack's own contents with the sets declared above; it never
## looks at scene code.
static func unused(pack: ArtPack) -> Dictionary[StringName, PackedStringArray]:
	var found: Dictionary[StringName, PackedStringArray] = {}
	if pack == null:
		return found
	found[&"tiles"] = _unasked(pack.tiles.keys(), tile_ids())
	var placed := prop_ids()
	for group in ITEM_GROUPS:
		for member in pack.items_in(group):
			placed.append(member.id)
	found[&"props"] = _unasked(pack.props.keys(), placed)
	found[&"ui"] = _unasked(pack.ui.keys(), ui_ids())
	var modules: Array[StringName] = [] if pack.table == null else pack.table.modules.keys()
	found[&"table"] = _unasked(modules, table_module_ids(pack.table))
	return found


## The ids in `present` that `wanted` does not ask for, sorted so two runs read
## the same.
static func _unasked(present: Array[StringName], wanted: Array[StringName]) -> PackedStringArray:
	var found := PackedStringArray()
	for id in present:
		if not wanted.has(id):
			found.append(str(id))
	found.sort()
	return found
