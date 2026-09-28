class_name OfficeDecorPlanner
extends RefCounted
## Standing furniture for a candidate floor plan, row by row: a filing cabinet at
## the end of each row's wall bay and a plant at its start; between them the
## wall-foot run, more plants on a grid of the wall (OfficeShell.WALL_RUN_PITCH
## from the first plant, keyed by the place on that grid, "%06d/wall/%03d"); and
## where the row's last table ends well short of the main corridor, one plant
## in the middle of that spare bay ("%06d/bay"). A piece is kept only where its
## drawing stays on the floor and clear of every walkway, table, sign and wall
## title, and of the pieces kept before it. Furniture is optional: a piece that
## does not fit is left out, never a desk moved for it. None of it reads herdr:
## where a piece stands follows from the plan's geometry alone.
##
## This only proposes. OfficeFloorLayout.plan() furnishes its candidate before
## the one validation that plan gets, and leaves the whole batch out when the
## furnished floor would close a path to any seat. Drawing it is
## OfficeFloorView's business.

var _pen: OfficeDraw


## `pen` measures the pack's prop sprites and the lettering on the walls.
func _init(pen: OfficeDraw) -> void:
	_pen = pen


## Which plant stands at place `index` of a run (the row's first plant is place
## 0, the wall-foot run's pieces their grid step, the spare bay's plant its cell
## column): the two plants take turns by the place's parity, so a run reads as
## two kinds, not a stamp. Only the place: never a state, a tab or the time.
static func plant_at(index: int) -> StringName:
	return ArtContract.PROP_PLANT if posmod(index, 2) == 0 else ArtContract.PROP_PLANT_B


## Add every candidate that fits `next`, row by row. A new candidate plan can be
## furnished; a retained previous plan is immutable and never comes here.
func furnish(next: FloorPlan) -> void:
	var grid := float(FloorLayoutPolicy.GRID)
	var bay_end := float(next.main_corridor_cells.position.x * FloorLayoutPolicy.GRID)
	var cabinet_x := bay_end - OfficeShell.DECOR_FROM_END
	var plant_x := grid + OfficeShell.DECOR_FROM_END
	for row in next.rows:
		var top := float(row.wall_cells.position.y * FloorLayoutPolicy.GRID)
		var placed: Array[DecorPlacement] = []
		var candidates: Array[DecorPlacement] = [
			_candidate(
				"%06d/cabinet" % row.index, ArtContract.PROP_CABINET, Vector2(cabinet_x, top + OfficeShell.CABINET_FOOT)
			),
			_candidate("%06d/plant" % row.index, plant_at(0), Vector2(plant_x, top + OfficeShell.PLANT_FOOT))
		]
		for candidate in candidates:
			if _fits(next, row, placed, candidate, 0.0):
				placed.append(candidate)
		var step := 1
		while plant_x + step * OfficeShell.WALL_RUN_PITCH < cabinet_x:
			var at := Vector2(plant_x + step * OfficeShell.WALL_RUN_PITCH, top + OfficeShell.PLANT_FOOT)
			var candidate := _candidate("%06d/wall/%03d" % [row.index, step], plant_at(step), at)
			if _fits(next, row, placed, candidate, OfficeShell.WALL_RUN_GAP):
				placed.append(candidate)
			step += 1
		var bay := _spare_bay(next, row)
		if bay >= 0:
			var candidate := _candidate(
				"%06d/bay" % row.index, plant_at(bay), Vector2((bay + 0.5) * grid, top + OfficeShell.BAY_PLANT_FOOT)
			)
			if _fits(next, row, placed, candidate, 0.0):
				placed.append(candidate)
		# In key order, the order the floor view keeps them in in its sorted root,
		# so what is drawn lines up with the plan one for one.
		placed.sort_custom(_by_key)
		next.decorations.append_array(placed)


## The cell column the spare bay's plant stands in: the middle of the gap between
## the row's last table and the main corridor, when that gap is at least
## SPARE_BAY_CELLS wide. -1 for a row without one, or without a table.
static func _spare_bay(next: FloorPlan, row: RowPlan) -> int:
	var last := -1
	for placed in row.desks:
		last = maxi(last, placed.reserved_cells.end.x)
	var corridor := next.main_corridor_cells.position.x
	if last < 0 or corridor - last < OfficeShell.SPARE_BAY_CELLS:
		return -1
	return floori((last + corridor) / 2.0)


static func _by_key(a: DecorPlacement, b: DecorPlacement) -> bool:
	return a.key < b.key


func _candidate(key: String, piece: StringName, at: Vector2) -> DecorPlacement:
	var result := DecorPlacement.new()
	result.key = key
	result.piece = piece
	result.position = at
	var footprint: Vector2 = OfficeDecor.FOOTPRINT[piece]
	result.footprint = Rect2(at - Vector2(footprint.x / 2.0, footprint.y), footprint)
	var sprite := _pen.art.prop_sprite(piece)
	result.draw_rect = Rect2(at - sprite.pivot, Vector2(sprite.size))
	return result


## Whether `candidate` fits `row` of `next` beside the pieces `placed` in it so
## far: its drawing on the floor, its footprint off every walkway, and its
## drawing, grown by `gap` on every side, clear of the row's tables, their signs
## and titles and those pieces. A piece's drawing never leaves its row's band,
## so the other rows' tables and pieces cannot reach it.
func _fits(next: FloorPlan, row: RowPlan, placed: Array[DecorPlacement], candidate: DecorPlacement, gap: float) -> bool:
	if not next.render_bounds.encloses(candidate.draw_rect):
		return false
	for corridor in next.corridors:
		if candidate.footprint.intersects(
			Rect2(corridor.position * FloorLayoutPolicy.GRID, corridor.size * FloorLayoutPolicy.GRID)
		):
			return false
	var drawn := candidate.draw_rect.grow(gap)
	var wall_y := float(row.wall_cells.position.y * FloorLayoutPolicy.GRID)
	for desk in row.desks:
		if drawn.intersects(OfficeShell.wall_display_bounds(desk, wall_y, _pen)):
			return false
		var drawing := desk.measure.render_rect
		drawing.position += desk.origin
		if drawn.intersects(drawing):
			return false
	for other in placed:
		if drawn.intersects(other.draw_rect):
			return false
	return true
