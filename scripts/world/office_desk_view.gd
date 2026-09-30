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


## Node upper bound for a measured pod and everything this view owns, even
## when every retained slot gains a person. Measured on the dressed prefabs
## (the geometry suite's count, test_desk_node_budget_bounds_real_prefabs_and_retained_empty_slots,
## at 2, 4, 18 and 250 columns: 168, 310, 1304 and 17776 nodes with everybody
## seated): 26 fixed nodes (21 of the pod: its body, 12 holders, the footprint,
## the overlay, the frame and its 4 bars, and the 2 short legs; 5 of the
## background: itself, the lens's wash, the contact holder, the sign and the
## title) and 71 per column (20 of the pod's: a desk, an apron and a screen
## module, a bracket, 2 laptops, 2 three-node grommets, 2 lamps, 2 papers, 2
## seat and 2 standing markers; 1 contact shadow; two 15-node stations and two
## 10-node people). The bound decides which floors fit
## FloorLayoutPolicy.max_desk_nodes. Geometry tests count real dressed prefabs
## so changes to the scenes cannot silently invalidate this allocation
## contract. This bounds the settled live group, not temporary queue_free
## replacements.
static func node_budget(capacity: int) -> int:
	return 26 + 71 * capacity


func setup(drawing: OfficeDraw, ground: Node2D, sorted: Node2D, tab_key: String) -> void:
	_pen = drawing
	_ground = ground
	_sorted = sorted
	_name = "Table_" + tab_key.sha256_text().left(16)


## Bring this table to `next`. A plan the cache kept hands back the very same
## placement (FloorPlanCache.prepare()), which is unchanged by definition: only
## a different one is compared by its geometry. The title follows the room's
## label either way; labels never change a plan.
func reconcile(room: RoomModel, next: DeskPlacement, wall_y: float) -> void:
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
		_draw_background(next, wall_y)
	placement = next
	title.text = room.label.to_upper()


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
	# A vacated old slot may now hold another pane. Restore final occupancy only
	# after all rebindings, so a later vacate cannot erase the earlier occupant.
	# Retained shells keep their prompt; new occupants are furnished afterwards.
	for station in stations:
		table.equip(station.column, station.side, not station.pane_key.is_empty(), station.actor() == null)


func _available(used: Dictionary[OfficeStation, bool]) -> OfficeStation:
	for station in stations:
		if station.pane_key.is_empty() and not used.has(station):
			return station
	return null


static func _slot(column: int, side: String) -> int:
	return column * 2 + (1 if side == "near" else 0)


func _draw_background(next: DeskPlacement, wall_y: float) -> void:
	# The table owns SeatContacts. Move that holder to the new background before
	# deleting the old one; reparenting a queued-for-deletion node cannot save it.
	var previous := background
	_ground.remove_child(previous)
	background = Node2D.new()
	background.name = _name + "Ground"
	_ground.add_child(background)
	# No rug: the pod stands on the floor itself. The lens's wash covers the
	# cells under the pod's drawing, under the contact shadows, the sign and the title.
	var visual := next.measure.render_rect
	var grid := float(FloorLayoutPolicy.GRID)
	var start := (visual.position / grid).floor()
	var end := (visual.end / grid).ceil()
	wash = _pen.box(background, Rect2(next.origin + start * grid, (end - start) * grid), ArtContract.SLATE)
	wash.name = "LensWash"
	wash.visible = false
	table.contact_shadows(background)
	previous.queue_free()
	var middle := next.origin.x + next.measure.table_width / 2.0
	_pen.prop(background, ArtContract.PROP_SIGN, Vector2(middle, wall_y + OfficeShell.SIGN_FOOT))
	var bounds := OfficeShell.title_bounds(next, wall_y, _pen)
	title = _pen.clipped(background, "", bounds.position, bounds.size, 12, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	# Even a narrow sign must signal truncation. Godot's ordinary ellipsis mode
	# suppresses that mark when fewer than six characters fit.
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE


func release() -> void:
	for station in stations:
		_sorted.remove_child(station)
		station.queue_free()
	_sorted.remove_child(table)
	table.queue_free()
	_ground.remove_child(background)
	background.queue_free()
