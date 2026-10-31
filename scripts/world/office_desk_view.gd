class_name OfficeDeskView
extends RefCounted
## Owns one tab's objects while all standing objects remain direct Sorted children.

var table: OfficeTable
var background: Node2D
var title: Label
## The lens's wash over the pod's floor (OfficeFloorView.show_lens()): hidden
## until `L` is held, then the pod's most urgent state. Made with the background, so a
## zoom or a lens change never makes another; only its `visible` and `color` change.
var wash: ColorRect
var stations: Array[OfficeStation] = []
var pane_stations: Dictionary[String, OfficeStation] = {}
var placement: DeskPlacement
var _pen: OfficeDraw
var _ground: Node2D
var _sorted: Node2D
var _name := ""


## Two permanent 16-node stations and two markers per column; the pod and
## background use eleven fixed nodes. Empty slots cost the same as full
## ones. Geometry tests count the dressed scenes to guard this allocation cap.
static func node_budget(capacity: int) -> int:
	return 11 + 34 * capacity


func setup(drawing: OfficeDraw, ground: Node2D, sorted: Node2D, tab_key: String) -> void:
	_pen = drawing
	_ground = ground
	_sorted = sorted
	_name = "Table_" + tab_key.sha256_text().left(16)


## Bring this table to `next`. A plan the cache kept hands back the very same
## placement (FloorPlanCache.prepare()), which is unchanged by definition: only
## a different one is compared by its geometry. The title follows the room's
## label either way; labels never change a plan.
func reconcile(room: RoomModel, next: DeskPlacement) -> void:
	var changed := (
		placement == null or (placement != next and placement.geometry_signature() != next.geometry_signature())
	)
	if table == null:
		background = Node2D.new()
		background.name = _name + "Ground"
		_ground.add_child(background)
		table = _pen.table(_sorted, background, _name, next.origin, next.measure.table_width, next.measure.columns)
	elif changed:
		table.resize(next.capacity)
		table.relocate(next.origin)
	if changed:
		_sync_stations(next)
		_draw_background(next)
	placement = next
	# Nothing for the lone tab of a workspace while herdr calls it by its number.
	title.text = room.label_shown.to_upper()


func _sync_stations(next: DeskPlacement) -> void:
	var wanted: Dictionary[String, bool] = {}
	for seat in next.seats:
		wanted[seat.pane_key] = true
	for station in stations:
		if not station.pane_key.is_empty() and not wanted.has(station.pane_key):
			station.vacate()
		# Slot swaps cannot collide with another station's previous node name.
		station.name = "MovingSeat%d" % station.get_instance_id()
	var used: Dictionary[OfficeStation, bool] = {}
	var occupied: Dictionary[int, bool] = {}
	var assigned: Dictionary[String, OfficeStation] = {}
	for seat in next.seats:
		var station: OfficeStation = pane_stations.get(seat.pane_key)
		if station == null:
			station = _available(used)
		if station == null:
			station = _pen.station(_sorted, table, seat.column, seat.side)
			stations.append(station)
		station.rebind(table, seat.column, seat.side)
		station.pane_key = seat.pane_key
		used[station] = true
		occupied[_slot(seat.column, seat.side)] = true
		assigned[seat.pane_key] = station
	for column in next.capacity:
		for side: String in OfficeTable.SIDES:
			if occupied.has(_slot(column, side)):
				continue
			var station := _available(used)
			if station == null:
				station = _pen.station(_sorted, table, column, side)
				stations.append(station)
			station.rebind(table, column, side)
			station.vacate()
			used[station] = true
	var retained: Array[OfficeStation] = []
	for station in stations:
		if used.has(station):
			station.name = "%s%s%d" % [_name, station.side.capitalize(), station.column]
			retained.append(station)
		else:
			_sorted.remove_child(station)
			station.queue_free()
	retained.sort_custom(
		func(a: OfficeStation, b: OfficeStation) -> bool: return _slot(a.column, a.side) < _slot(b.column, b.side)
	)
	stations = retained
	pane_stations = assigned


## Transfer ownership before either tab reconciles. The station remains a
## Sorted child, so its animation and signal connections never leave the tree.
func take_station(key: String) -> OfficeStation:
	var station: OfficeStation = pane_stations.get(key)
	if station != null:
		pane_stations.erase(key)
		stations.erase(station)
		# Release the old slot name before any destination reuses that slot.
		station.name = "MovingSeat%d" % station.get_instance_id()
		placement = null
	return station


func adopt_station(station: OfficeStation) -> void:
	stations.append(station)
	pane_stations[station.pane_key] = station
	placement = null


func _available(used: Dictionary[OfficeStation, bool]) -> OfficeStation:
	for station in stations:
		if station.pane_key.is_empty() and not used.has(station):
			return station
	return null


static func _slot(column: int, side: String) -> int:
	return column * 2 + (1 if side == "near" else 0)


func _draw_background(next: DeskPlacement) -> void:
	var previous := background
	_ground.remove_child(previous)
	background = Node2D.new()
	background.name = _name + "Ground"
	_ground.add_child(background)
	# Four units below the drawing leave the pod's selection frame clear.
	var title_at := Vector2(0, next.measure.render_rect.end.y + 4.0)
	# No rug: the pod stands on the floor itself. The lens's wash covers the
	# cells under both the complete drawing and the tab title, including its gap.
	var title_rect := Rect2(title_at, Vector2(next.measure.table_width, OfficeDraw.TAB_LABEL_HEIGHT))
	var visual := next.measure.render_rect.merge(title_rect)
	var grid := float(FloorLayoutPolicy.GRID)
	var start := (visual.position / grid).floor()
	var end := (visual.end / grid).ceil()
	wash = _pen.box(background, Rect2(next.origin + start * grid, (end - start) * grid), ArtContract.SLATE)
	wash.name = "LensWash"
	wash.visible = false
	previous.queue_free()
	# The tab's name, small, on the floor right under the table's drawing and
	# no wider than the table; four units leave the selection frame clear.
	title = _pen.tab_label(background, next.origin + title_at, next.measure.table_width)


func release() -> void:
	for station in stations:
		_sorted.remove_child(station)
		station.queue_free()
	_sorted.remove_child(table)
	table.queue_free()
	_ground.remove_child(background)
	background.queue_free()
