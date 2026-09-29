class_name OfficeFloorView
extends RefCounted
## A FloorPlan rendered through the Ground / Sorted world convention, and the
## desks on it kept up to date in place: a status, a worker, the selection or a
## task lamp changes only the seat it belongs to, and a dropped machine dims and
## freezes the floor without rebuilding it. Its people walk between one
## observation and the next (`presentation`): in at the lift door, out of it,
## over to a new seat, and to the pantry in the entry band and back. The
## reception counter is furniture: nobody rests there and it shows nothing.


## A desk on the floor: its station node and what that station shows now, so
## the next update can tell an unchanged desk from one that has to be redrawn,
## and a mere selection change from a new worker.
class Seat:
	extends RefCounted
	var node: OfficeStation
	## PaneModel.desk_signature() of what is drawn there.
	var look := ""
	var selected := false
	## How hard this seat's task lamp burns now (OfficeTable.Lamp). Kept apart
	## from `look`: which tab a workspace has open is not part of any one desk.
	var lit := OfficeTable.Lamp.OFF

	func _init(station: OfficeStation) -> void:
		node = station


## What the lens (`L` held) multiplies the furnishing by: the shell (floor,
## walkways, walls, door, windows), the plants and cabinets, the counters and
## each table's trinkets. Signals stay as bright as they are.
const LENS_DIM := Color(0.55, 0.55, 0.55)
## How opaque the lens's wash over a rug is (OfficeDeskView.wash).
const LENS_WASH_ALPHA := 0.75

## The floor's own node (FloorRooms in the office): what dims as a whole when
## its machine drops.
var root: Node2D
var ground: Node2D
var sorted: Node2D
## Tab key -> the view that owns that tab's table and stations.
var desks: Dictionary[String, OfficeDeskView] = {}
## Pane key -> its seat. A key the floor carries twice cannot be told apart in
## place, so only the rebuild draws those.
var seats: Dictionary[String, Seat] = {}
## The floor's tables, one per room in floor order, for their selection frame.
var tables: Array[OfficeTable] = []
var plan: FloorPlan
## How many reconciles laid the floor's structure out again (the shell's key,
## the tree order, the seat index): a diagnostic, never a decision, so a test
## can prove that a refresh on an unchanged plan does none of it.
var structures := 0
## Who walks where on this floor, between the observations it is updated with.
var presentation := OfficePresentation.new()
## The hover mark (OfficePointer), the floor root's last child; point() moves it.
var pointer: OfficePointer
var _pen: OfficeDraw
## The lens is held: furnishing made while it is starts dimmed too.
var _lens := false
## How far into night the floor is drawn (set_night()); tables and windows made
## later start at it.
var _night := 0.0
## The outer wall's windows, for set_night()'s day / night view.
var _windows: Array[Sprite2D] = []
var _shell: Node2D
var _decor: Dictionary[String, OfficeDecor] = {}
## The entry band's counters, by fixture key.
var _fixtures: Dictionary[String, OfficeDecor] = {}
var _shell_signature := ""
## _rooms_key() of the model the last structural pass laid out.
var _rooms_signature := ""
## Connected to every station's `picked`: a click released over a desk.
var _picked: Callable
## Connected to every station's `asked`: a click released over a bubble.
var _asked: Callable
## Connected to every station's `bubble_hovered`: the pointer on or off a bubble.
var _hovered: Callable


func setup(
	drawing: OfficeDraw, floor_root: Node2D, picked := Callable(), asked := Callable(), hovered := Callable()
) -> void:
	_pen = drawing
	root = floor_root
	_picked = picked
	_asked = asked
	_hovered = hovered
	ground = Node2D.new()
	ground.name = "Ground"
	floor_root.add_child(ground)
	sorted = Node2D.new()
	sorted.name = "Sorted"
	sorted.y_sort_enabled = true
	floor_root.add_child(sorted)
	pointer = OfficePointer.new()
	pointer.dress(drawing.art)
	floor_root.add_child(pointer)
	presentation.setup(sorted, drawing.art.people)


## The seat drawn for pane `key`, or null.
func seat(key: String) -> Seat:
	return seats.get(key)


## How hard a seat's task lamp burns. Herdr's own focus — the terminal the user
## is looking at — is the brightest thing on the floor; a desk on a tab its
## workspace does not have open is dimmed; everything else burns normally. A
## workspace that does not say which tab is open leaves them all burning:
## not saying is not a no, and a dimmed floor already means a lost machine.
static func lamp_of(pane: PaneModel, room: RoomModel) -> OfficeTable.Lamp:
	if pane.focused:
		return OfficeTable.Lamp.FOCUS
	return OfficeTable.Lamp.DIM if room.active == RoomModel.Active.NO else OfficeTable.Lamp.ON


## Same floor, same layout as on screen: redraw just the desks whose worker,
## state or selection moved. `active_key` is the selected desk; a worker drawn
## while the floor's machine is `frozen` starts frozen, like the rest of it.
func update_desks(model: FloorModel, active_key: String, frozen: bool) -> void:
	# Repeated keys are part of the layout model; the rebuild owns those desks.
	var repeated := model.repeated_keys()
	for room_index in model.rooms.size():
		var room := model.rooms[room_index]
		var table_selected := false
		for pane in room.panes:
			var is_selected := pane.key == active_key
			table_selected = table_selected or is_selected
			if repeated.has(pane.key):
				continue
			var desk: Seat = seats.get(pane.key)
			if desk == null:
				continue
			# Which tab a workspace has open moves on its own, and moves every
			# lamp of a room at once, so the lamp is looked at before the worker.
			var level := lamp_of(pane, room)
			desk.lit = level
			desk.node.light(level)
			var look := pane.desk_signature()
			if look == desk.look and is_selected == desk.selected:
				continue
			var same_worker := look == desk.look
			desk.look = look
			desk.selected = is_selected
			if same_worker:
				desk.node.select(is_selected)
				continue
			desk.node.furnish(
				pane.provider,
				StringName(pane.state),
				is_selected,
				pane.launching(),
				pane.pane_id,
				pane.machine(),
				pane.agent_name
			)
			var actor := desk.node.actor()
			if frozen and actor != null:
				actor.pause()
		if room_index < tables.size():
			tables[room_index].set_selected(table_selected)
	presentation.after(self, frozen)


## The lens (OfficeLens) is `held`: each seat's line says `texts[pane key]`
## (OfficeStation.show_lens(); missing is nothing), each table's rug is washed
## in `tones[tab key]`, a palette key, at LENS_WASH_ALPHA (missing: no wash),
## and the furnishing dims by LENS_DIM. Let go (`held` false), every line and
## wash hides and the furnishing is Color.WHITE again. Only visibility, text,
## colour and modulate change.
func show_lens(held: bool, texts: Dictionary[String, String], tones: Dictionary[String, StringName]) -> void:
	_lens = held
	for key: String in seats:
		var text: String = texts.get(key, "")
		seats[key].node.show_lens(held, text)
	for tab: String in desks:
		if desks[tab].table != null:
			desks[tab].table.set_lensed(held)
		var wash := desks[tab].wash
		if wash == null:
			continue
		var tone: StringName = tones.get(tab, &"")
		wash.visible = held and not tone.is_empty()
		if wash.visible:
			var color := _pen.art.color(tone)
			color.a = LENS_WASH_ALPHA
			if wash.color != color:
				wash.color = color
	var tint := _furnishing_tint()
	for node in furnishing():
		node.modulate = tint


## What the lens dims: the shell, every decor piece, the counters and each
## table's trinkets (its `%Decorations`).
func furnishing() -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	if _shell != null:
		found.append(_shell)
	for key: String in _decor:
		found.append(_decor[key])
	for key: String in _fixtures:
		found.append(_fixtures[key])
	for table in tables:
		found.append(table.get_node("%Decorations") as CanvasItem)
	return found


## Point at pane `key`'s desk (OfficePointer): its click area and, while it
## shows, its bubble. Empty, or a pane with no seat here, points at nothing.
func point(key: String) -> void:
	var desk: Seat = null if key.is_empty() else seats.get(key)
	if desk == null:
		pointer.clear()
		return
	var bounds := desk.node.target_rect()
	var bubble := desk.node.bubble_rect()
	if bubble.has_area():
		bounds = bounds.merge(bubble)
	pointer.point_at(key, root.get_global_transform().affine_inverse() * bounds)


func _furnishing_tint() -> Color:
	return LENS_DIM if _lens else Color.WHITE


## Walk this floor's people `delta` seconds further; the office calls it every frame.
func walk(delta: float) -> void:
	presentation.walk(delta)


## Walk every walk on this floor to its end at once (OfficePresentation.settle()).
func settle() -> void:
	presentation.settle()


## The office could not lay out this refresh's input, so the floor was not
## updated: the next update is presented cold (OfficePresentation.lose_track()).
func lose_track() -> void:
	presentation.lose_track()


## A dropped connection keeps the floor on screen, dimmed by `tint` and frozen;
## a live one draws it plainly and lets every worker on it move again. Never
## dress a lost connection up as idle. Its walkers stop where they are and
## whoever was on the way out is gone (OfficePresentation.freeze()); when the
## machine is back they stay as they stopped, walk animation too, until the
## next observation places them (OfficePresentation.holding()).
func freeze(is_stale: bool, tint: Color) -> void:
	presentation.freeze(is_stale)
	root.modulate = tint if is_stale else Color.WHITE
	if not root.is_inside_tree():
		return
	var held: Dictionary[int, bool] = {}
	if presentation.holding():
		for body in presentation.walkers():
			held[body.get_instance_id()] = true
	for person: PixelPerson in root.get_tree().get_nodes_in_group("office_actors"):
		if not root.is_ancestor_of(person):
			continue
		if is_stale:
			person.pause()
		elif not held.has(person.get_instance_id()):
			person.play()


## Lay the floor out as `next` for `model`, keeping every table and seat that
## is still there. The presentation takes whoever leaves out of their seat
## first, and keeps whoever will walk where they stand; `frozen` says the
## shown machine is stale, which walks nobody.
func reconcile(next: FloorPlan, model: FloorModel, frozen := false) -> void:
	presentation.before(self, next, model, frozen)
	var wanted: Dictionary[String, RoomModel] = {}
	for room in model.rooms:
		wanted[room.key] = room
	for key: String in desks.keys():
		if not wanted.has(key):
			desks[key].release()
			desks.erase(key)
	# The plan the cache kept (FloorPlanCache.prepare() hands back the same
	# object) for the same rooms and seats in the same order: the shell, every
	# table and seat and their order in the tree are already what it says.
	var rooms_key := _rooms_key(model)
	var same := next == plan and rooms_key == _rooms_signature
	if not same:
		# The pictures on the row walls hang where the signs leave room, so
		# the shell is drawn again whenever a table's move moves one of them.
		var frames := OfficeShell.frames(next, _pen)
		var shell_key := _shell_key(next, frames)
		if shell_key != _shell_signature:
			_draw_shell(next, frames)
			_shell_signature = shell_key
	for placed in next.desks:
		var view: OfficeDeskView = desks.get(placed.tab_key)
		if view == null:
			view = OfficeDeskView.new()
			view.setup(_pen, ground, sorted, placed.tab_key)
			desks[placed.tab_key] = view
		var wall_y := float(next.rows[placed.row].wall_cells.position.y * FloorLayoutPolicy.GRID)
		view.reconcile(wanted[placed.tab_key], placed, wall_y)
	if not same:
		_order(model)
		plan = next
		_index(model)
		_rooms_signature = rooms_key
		structures += 1
	presentation.placed(self)


## The rooms in the model's order, each with its panes in order: what _order()
## and _index() lay out from, besides the plan.
static func _rooms_key(model: FloorModel) -> String:
	var parts := PackedStringArray()
	for room in model.rooms:
		parts.append(room.key)
		for pane in room.panes:
			parts.append(pane.key)
		# A room boundary no pane key can hold (keys come from the fleet, never empty).
		parts.append("")
	return "\n".join(parts)


## Seats by pane key and tables by room, after a reconcile: a seat whose station
## survived keeps what it shows, so the next update_desks() redraws only change.
func _index(model: FloorModel) -> void:
	var indexed: Dictionary[String, Seat] = {}
	tables.clear()
	for room in model.rooms:
		var view: OfficeDeskView = desks.get(room.key)
		if view == null:
			continue
		tables.append(view.table)
		view.table.set_night(_night)
		for key in view.pane_stations:
			var station := view.pane_stations[key]
			var retained: Seat = seats.get(key)
			if retained == null or retained.node != station:
				retained = Seat.new(station)
			indexed[key] = retained
			if _picked.is_valid() and not station.picked.is_connected(_picked):
				station.picked.connect(_picked)
			if _asked.is_valid() and not station.asked.is_connected(_asked):
				station.asked.connect(_asked)
			if _hovered.is_valid() and not station.bubble_hovered.is_connected(_hovered):
				station.bubble_hovered.connect(_hovered)
	seats = indexed


func _order(model: FloorModel) -> void:
	var index := 0
	var ground_index := 1
	for room in model.rooms:
		var view: OfficeDeskView = desks.get(room.key)
		if view == null:
			continue
		ground.move_child(view.background, ground_index)
		ground_index += 1
		sorted.move_child(view.table, index)
		index += 1
		for station in view.stations:
			sorted.move_child(station, index)
			index += 1
	var decor_keys := _decor.keys()
	decor_keys.sort()
	for key: String in decor_keys:
		sorted.move_child(_decor[key], index)
		index += 1
	var fixture_keys := _fixtures.keys()
	fixture_keys.sort()
	for key: String in fixture_keys:
		sorted.move_child(_fixtures[key], index)
		index += 1


static func _shell_key(next: FloorPlan, frames: Array[Vector2]) -> String:
	var walls := PackedStringArray()
	for row in next.rows:
		walls.append(str(row.wall_cells))
	var furniture := PackedStringArray()
	for placed in next.decorations:
		furniture.append(placed.geometry_signature())
	for fixture in next.fixtures():
		furniture.append(fixture.geometry_signature())
	return JSON.stringify([next.floor_cells, walls, next.corridors, furniture, frames])


func _draw_shell(next: FloorPlan, frames: Array[Vector2]) -> void:
	if _shell != null:
		ground.remove_child(_shell)
		_shell.queue_free()
	_shell = Node2D.new()
	_shell.name = "Shell"
	_shell.modulate = _furnishing_tint()
	ground.add_child(_shell)
	ground.move_child(_shell, 0)
	var art := _pen.art
	var floor_layer := _pen.layer(_shell, Vector2.ZERO)
	floor_layer.name = "Floor"
	for y in next.floor_cells.size.y:
		for x in next.floor_cells.size.x:
			floor_layer.set_cell(Vector2i(x, y), 0, art.cell(ArtContract.FLOOR_WOOD[(x + 2 * y) % 3]))
	var paths := _pen.layer(_shell, Vector2.ZERO)
	paths.name = "Walkways"
	for corridor in next.corridors:
		for y in range(corridor.position.y, corridor.end.y):
			for x in range(corridor.position.x, corridor.end.x):
				paths.set_cell(Vector2i(x, y), 0, art.cell(ArtContract.FLOOR_WALKWAY))
	_draw_walls(next)
	_outer_wall(next)
	_hang_frames(frames)
	_furnish(next)


func _draw_walls(next: FloorPlan) -> void:
	var cells: Dictionary[Vector2i, StringName] = {}
	var width := next.floor_cells.size.x
	for y in next.floor_cells.size.y:
		cells[Vector2i(0, y)] = ArtContract.WALL_SIDE_LEFT
		cells[Vector2i(width - 1, y)] = ArtContract.WALL_SIDE_RIGHT
	for x in width:
		var end: StringName = ArtContract.WALL_ENDS[0 if x == 0 else 2 if x == width - 1 else 1]
		for course in ArtContract.WALL_COURSES.size():
			cells[Vector2i(x, course)] = ArtContract.wall_cell(ArtContract.WALL_COURSES[course], end)
	for row in next.rows:
		for x in range(row.wall_cells.position.x, row.wall_cells.end.x):
			var end := (
				ArtContract.WALL_T_LEFT
				if x == 0
				else ArtContract.WALL_END_RIGHT if x == row.wall_cells.end.x - 1 else &"center"
			)
			for course in ArtContract.WALL_COURSES.size():
				cells[Vector2i(x, row.wall_cells.position.y + course)] = ArtContract.wall_cell(
					ArtContract.WALL_COURSES[course], end
				)
	var walls := _pen.layer(_shell, Vector2.ZERO)
	walls.name = "Walls"
	for at in cells:
		walls.set_cell(at, 0, _pen.art.cell(cells[at]))


func _outer_wall(next: FloorPlan) -> void:
	_pen.prop(_shell, ArtContract.PROP_DOOR, OfficeShell.door(next))
	_windows.clear()
	for at in OfficeShell.window_xs(next, _pen):
		_windows.append(_pen.prop(_shell, _window_id(), Vector2(at, OfficeShell.WINDOW_FOOT)))


## Night falls or lifts on this floor by `amount` (DayLight.night_at()): the
## lamps and contact shadows of every table, and the windows' view, which turns
## to the night one past the middle of a fade (a texture swap, no node rebuilt).
func set_night(amount: float) -> void:
	_night = amount
	for table in tables:
		table.set_night(amount)
	var texture := _pen.art.sprite_texture(_pen.art.prop_sprite(_window_id()))
	for window in _windows:
		window.texture = texture


## The outer wall's windows as drawn now, for a test of the night view.
func windows() -> Array[Sprite2D]:
	return _windows.duplicate()


func _window_id() -> StringName:
	return ArtContract.PROP_WINDOW_NIGHT if DayLight.is_night(_night) else ArtContract.PROP_WINDOW


## The framed pictures on the row walls (OfficeShell.frames()), in the shell:
## laid on the wall like the signs, no footprint and nothing to walk round, and
## dimmed, hidden and frozen with the rest of the shell.
func _hang_frames(frames: Array[Vector2]) -> void:
	for index in frames.size():
		var picture := _pen.prop(_shell, ArtContract.PROP_WALL_FRAME, frames[index])
		picture.name = "WallFrame%d" % index


## The plan's standing pieces, each under a name made from its plan key (the
## key's `/` read as `_`), so a floor updated in place names its pieces the way
## a rebuild of the same plan does, however many came and went before: the
## wall-foot run and the spare bay's plant come and go with the tables.
func _furnish(next: FloorPlan) -> void:
	var wanted: Dictionary[String, bool] = {}
	for placed in next.decorations:
		wanted[placed.key] = true
	for key: String in _decor.keys():
		if not wanted.has(key):
			sorted.remove_child(_decor[key])
			_decor[key].queue_free()
			_decor.erase(key)
	for placed in next.decorations:
		_place_decor(placed.key, placed.piece, placed.position, wanted)
		_decor[placed.key].name = "Decor_" + placed.key.replace("/", "_")
	_place_fixtures(next)


## The counters of the entry band: made the first time a plan has them, moved
## with the plan (they follow the main corridor), gone with it. Both are plain
## furniture (OfficeDecor).
func _place_fixtures(next: FloorPlan) -> void:
	var wanted: Dictionary[String, FixturePlacement] = {}
	for fixture in next.fixtures():
		wanted[fixture.key] = fixture
	for key: String in _fixtures.keys():
		if not wanted.has(key):
			sorted.remove_child(_fixtures[key])
			_fixtures[key].queue_free()
			_fixtures.erase(key)
	for key: String in wanted:
		var fixture := wanted[key]
		var node: OfficeDecor = _fixtures.get(key)
		if node == null:
			node = _pen.decor(sorted, fixture.piece, fixture.position)
			if node == null:
				continue
			node.name = "Fixture_" + key
			node.modulate = _furnishing_tint()
			_fixtures[key] = node
		node.position = fixture.position


func _place_decor(key: String, piece: StringName, at: Vector2, wanted: Dictionary[String, bool]) -> void:
	wanted[key] = true
	var node: OfficeDecor = _decor.get(key)
	if node == null:
		node = _pen.decor(sorted, piece, at)
		node.modulate = _furnishing_tint()
		_decor[key] = node
	node.position = at
