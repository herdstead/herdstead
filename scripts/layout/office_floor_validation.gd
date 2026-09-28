class_name OfficeFloorValidation
extends RefCounted
## Whether a floor plan can be drawn and walked: its bounds, budgets, rows,
## tables and furniture, then cell-centre connectivity against physical
## obstacles, not the reservation rectangles that also contain walkable space
## around each desk. The connectivity is OfficeWalkGraph's, the graph the
## office's people walk, so what passes here is what they can walk.

## How many plans this process has validated: a diagnostic, never a decision,
## so a test can prove that a new floor is flood-filled once, furniture included.
static var validations := 0


static func problems(value: FloorPlan, rules: FloorLayoutPolicy) -> PackedStringArray:
	validations += 1
	var found := rules.problems()
	if value == null:
		found.append("layout is null")
		return found
	var size := value.floor_cells.size
	if value.floor_cells.position != Vector2i.ZERO or size.x <= 0 or size.y <= 0:
		found.append("floor must be a positive rectangle at the fixed origin")
	if size.x > rules.max_width_cells or size.y > rules.max_height_cells or size.x * size.y > rules.max_floor_cells:
		found.append("floor exceeds width, height or cell budget")
	if not found.is_empty():
		return found
	# Previous plans are inputs too. Reject before copying rows, enumerating
	# historical columns or allocating measurements for any of their desks.
	if value.desks.size() > rules.max_tables:
		return PackedStringArray(["layout exceeds table budget"])
	var remaining_nodes := rules.max_desk_nodes
	var remaining_panes := rules.max_panes
	for placed in value.desks:
		if placed.capacity < 2 or placed.capacity % 2 != 0 or placed.capacity > rules.max_width_cells:
			return PackedStringArray(["table capacity must be at least two and grow in pairs"])
		remaining_nodes -= OfficeDeskView.node_budget(placed.capacity)
		if remaining_nodes < 0:
			return PackedStringArray(["floor exceeds desk node budget"])
		remaining_panes -= placed.seats.size()
		if remaining_panes < 0:
			return PackedStringArray(["layout exceeds pane budget"])
	var grid := FloorLayoutPolicy.GRID
	var inside_width := size.x - 2 * rules.outer_side_cells
	var expected_entry := Rect2i(rules.outer_side_cells, rules.wall_cells, inside_width, rules.entry_cells)
	var expected_main := Rect2i(
		size.x - rules.outer_side_cells - rules.main_corridor_cells,
		rules.wall_cells,
		rules.main_corridor_cells,
		size.y - rules.wall_cells
	)
	if value.entry_cells != expected_entry or value.main_corridor_cells != expected_main:
		found.append("floor does not contain its declared entrance and main corridor")
	if not value.corridors.has(expected_entry) or not value.corridors.has(expected_main):
		found.append("entrance or main corridor is missing from the walkways")
	if not value.render_bounds.encloses(Rect2(value.floor_cells.position * grid, size * grid)):
		found.append("drawing bounds do not contain the complete floor")
	var keys: Dictionary[String, bool] = {}
	var panes: Dictionary[String, bool] = {}
	for index in value.rows.size():
		var row := value.rows[index]
		if row.index != index or not value.floor_cells.encloses(row.band_cells):
			found.append("invalid row index or bounds")
		var y := rules.wall_cells + rules.entry_cells + index * rules.row_height_cells
		if row.band_cells != Rect2i(0, y, size.x, rules.row_height_cells):
			found.append("row does not match the fixed row policy")
		if row.wall_cells != Rect2i(0, y, expected_main.position.x, rules.wall_cells):
			found.append("row wall does not end before the main corridor")
		var expected_cross := Rect2i(
			rules.outer_side_cells,
			y + rules.row_height_cells - rules.cross_corridor_cells,
			inside_width,
			rules.cross_corridor_cells
		)
		if row.corridor_cells != expected_cross or not value.corridors.has(expected_cross):
			found.append("row cross corridor is missing or incorrectly measured")
		if not row.exclusive_tab_key.is_empty():
			if row.desks.size() != 1 or row.desks[0].tab_key != row.exclusive_tab_key:
				found.append("oversized row ownership is not exclusive")
	for placed in value.desks:
		if placed.tab_key.is_empty() or keys.has(placed.tab_key):
			found.append("duplicate or missing table identity")
		keys[placed.tab_key] = true
		if placed.row < 0 or placed.row >= value.rows.size() or placed.measure == null:
			found.append("table has no valid row or measurement")
			continue
		if not value.rows[placed.row].desks.has(placed):
			found.append("table missing from its row")
		var measurement := placed.measure
		if measurement.capacity != placed.capacity or measurement.columns.size() != placed.capacity:
			found.append("table capacity and measurement disagree")
		# The renderer uses table_width to allocate modules. A stale/tampered
		# measure must not buy an arbitrarily wide table with a small capacity.
		var expected := OfficeTable.measure(placed.capacity)
		if measurement.table_width != expected.table_width or measurement.columns != expected.columns:
			found.append("table width or columns disagree with measured capacity")
		for positions: Array[Vector2] in [measurement.far_approaches, measurement.near_approaches]:
			if positions.size() != placed.capacity:
				found.append("table is missing measured approaches")
		if not placed.origin.is_finite():
			found.append("table origin is not finite")
		var reserved := Rect2(placed.reserved_cells.position * grid, placed.reserved_cells.size * grid)
		for bounds: Rect2 in [measurement.reserved_rect, measurement.render_rect, measurement.physical_rect]:
			if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area():
				found.append("invalid table measurement")
			bounds.position += placed.origin
			if not reserved.encloses(bounds):
				found.append("table measurement leaves its reservation")
		var drawing := measurement.render_rect
		drawing.position += placed.origin
		if not value.render_bounds.encloses(drawing):
			found.append("drawing bounds omit part of a table")
		if not value.floor_cells.encloses(placed.reserved_cells):
			found.append("table reservation leaves the floor")
		for corridor in value.corridors:
			if placed.reserved_cells.intersects(corridor):
				found.append("table reservation intersects a corridor")
		for row in value.rows:
			if placed.reserved_cells.intersects(row.wall_cells):
				found.append("table reservation intersects a wall")
		var occupied: Dictionary[String, bool] = {}
		for seat in placed.seats:
			var seat_key := "%d:%s" % [seat.column, seat.side]
			if panes.has(seat.pane_key) or occupied.has(seat_key):
				found.append("duplicate pane or occupied seat")
			panes[seat.pane_key] = true
			occupied[seat_key] = true
			if (
				seat.tab_key != placed.tab_key
				or seat.column < 0
				or seat.column >= placed.capacity
				or seat.side not in ["far", "near"]
			):
				found.append("seat does not belong to the measured table")
	for index in value.desks.size():
		for later in range(index + 1, value.desks.size()):
			if value.desks[index].reserved_cells.intersects(value.desks[later].reserved_cells):
				found.append("table reservations overlap")
	for corridor in value.corridors:
		if not value.floor_cells.encloses(corridor):
			found.append("corridor leaves the floor")
	found.append_array(_decor_problems(value))
	found.append_array(_fixture_problems(value))
	if not found.is_empty():
		return found
	found.append_array(_route_problems(value, rules))
	return found


## Whether everyone can walk in, sit down, get up and walk out, on the graph the
## office's people walk (OfficeWalkGraph): the lift door's threshold is clear,
## every approach of every column is reached from the threshold's end (not from
## anywhere else in the entry band, which would prove nothing about the door),
## and from each approach both legs are clear: the L-shaped one to where the
## worker stands when done, and the one into the seat (straight on the far
## side, round the chair on the near side). The only obstacle a leg may enter
## is its own table, along that leg: the far seat is inside the footprint (the
## graph's entries). A leg from an approach nobody reaches is not looked at.
## The fixtures the same way: every queue slot's and pantry spot's approach is
## reached from the threshold's end, its leg up to the fixture row is clear, and
## so is each step of the queue towards its head.
static func _route_problems(value: FloorPlan, rules: FloorLayoutPolicy) -> PackedStringArray:
	var found := PackedStringArray()
	var graph := OfficeWalkGraph.build(value, rules.actor_footprint, rules.actor_draw_rect)
	var threshold := graph.threshold_problem()
	if not threshold.is_empty():
		found.append(threshold)
	for placed in value.desks:
		for column in placed.capacity:
			for side: String in ["far", "near"]:
				var where := "%s column %d %s" % [placed.tab_key, column, side]
				var approach := placed.origin + placed.measure.approach_position(column, side)
				var cell := OfficeWalkGraph.cell_of(approach)
				if not graph.reaches(cell) or not graph.clear(OfficeWalkGraph.centre(cell), approach):
					found.append("unreachable approach: " + where)
					continue
				var near := side == "near"
				var standing := placed.origin + placed.measure.standing_position(column, side)
				if not graph.clear_route(OfficeWalkGraph.leg_to_standing(approach, standing, near)):
					found.append("blocked standing leg: " + where)
				var seat := placed.origin + placed.measure.seat_position(column, side)
				if not graph.clear_route(OfficeWalkGraph.leg_to_seat(approach, seat, standing, near)):
					found.append("blocked seat leg: " + where)
	for fixture in value.fixtures():
		var what := "queue" if fixture.kind == FixturePlacement.Kind.RECEPTION else "pantry"
		for index in fixture.spots.size():
			var approach := fixture.approaches[index]
			var cell := OfficeWalkGraph.cell_of(approach)
			if not graph.reaches(cell) or not graph.clear(OfficeWalkGraph.centre(cell), approach):
				found.append("unreachable %s approach: %d" % [what, index])
			elif not graph.clear_route(OfficeWalkGraph.leg_to_fixture(approach, fixture.spots[index])):
				found.append("blocked %s leg: %d" % [what, index])
			if fixture.kind == FixturePlacement.Kind.RECEPTION and index > 0:
				if not graph.clear(fixture.spots[index], fixture.spots[index - 1]):
					found.append("blocked queue step: %d" % index)
	return found


## Whether the fixtures are where the fixture planner puts them: only on a floor
## with rows, the pantry only beside a reception; each counter inside the entry
## band, left of the main corridor, its drawing on the floor; every spot on the
## fixture row with its approach straight below it on the walking lane, inside
## the bay, the queue's slots leftwards from its head and the pantry's
## rightwards, a pitch apart; no more of them than a queue or a pantry may hold.
static func _fixture_problems(value: FloorPlan) -> PackedStringArray:
	var found := PackedStringArray()
	if value.reception == null:
		if value.pantry != null:
			found.append("fixture: a pantry without a reception")
		return found
	if value.rows.is_empty():
		found.append("fixture: fixtures on a floor without tables")
	var grid := float(FloorLayoutPolicy.GRID)
	var band := Rect2(value.entry_cells.position * grid, value.entry_cells.size * grid)
	if band.size.y < OfficeShell.WALKING_LANE + grid / 2.0:
		found.append("fixture: the entry band has no fixture row and walking lane")
	var bay_end := value.main_corridor_cells.position.x * grid
	var row_y := band.position.y + OfficeShell.FIXTURE_ROW
	var lane_y := band.position.y + OfficeShell.WALKING_LANE
	var half := OfficeShell.SPOT_PITCH / 2.0
	for fixture in value.fixtures():
		var what := fixture.key
		var reception := fixture.kind == FixturePlacement.Kind.RECEPTION
		if fixture.key != ("reception" if reception else "pantry") or fixture.piece == &"":
			found.append("fixture: %s has no identity" % what)
		if (fixture == value.reception) != reception:
			found.append("fixture: %s is in the other fixture's place" % what)
		for bounds: Rect2 in [fixture.footprint, fixture.draw_rect]:
			if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area():
				found.append("fixture: invalid %s measurement" % what)
		if not band.encloses(fixture.footprint) or fixture.footprint.end.x > bay_end:
			found.append("fixture: %s stands outside the entry band's bay" % what)
		if not value.render_bounds.encloses(fixture.draw_rect):
			found.append("drawing bounds omit the %s" % what)
		var most := OfficeShell.MAX_QUEUE if reception else OfficeShell.MAX_PANTRY
		var least := OfficeShell.MIN_QUEUE if reception else 1
		if fixture.spots.size() < least or fixture.spots.size() > most:
			found.append("fixture: %s holds %d" % [what, fixture.spots.size()])
		if fixture.approaches.size() != fixture.spots.size():
			found.append("fixture: %s spots and approaches disagree" % what)
			continue
		var step := -OfficeShell.SPOT_PITCH if reception else OfficeShell.SPOT_PITCH
		for index in fixture.spots.size():
			var spot := fixture.spots[index]
			if (
				spot.y != row_y
				or fixture.approaches[index] != Vector2(spot.x, lane_y)
				or spot.x - half < band.position.x
				or spot.x + half > bay_end
				or (index > 0 and not is_equal_approx(spot.x - fixture.spots[index - 1].x, step))
			):
				found.append("fixture: %s spot %d is off its row" % [what, index])
	if value.pantry != null and not value.pantry.spots.is_empty() and not value.reception.spots.is_empty():
		var pantry_end := value.pantry.spots[value.pantry.spots.size() - 1].x + half
		var queue_tail := value.reception.spots[value.reception.spots.size() - 1].x - half
		if pantry_end + OfficeShell.FIXTURE_GAP > queue_tail + 0.001:
			found.append("fixture: the pantry runs into the queue")
		if value.pantry.footprint.intersects(value.reception.footprint):
			found.append("fixture: the counters overlap")
	return found


static func _decor_problems(value: FloorPlan) -> PackedStringArray:
	var found := PackedStringArray()
	var keys: Dictionary[String, bool] = {}
	var grid := FloorLayoutPolicy.GRID
	var floor_rect := Rect2(value.floor_cells.position * grid, value.floor_cells.size * grid)
	for decoration in value.decorations:
		if decoration.key.is_empty() or decoration.piece == &"" or keys.has(decoration.key):
			found.append("duplicate or missing decoration identity")
		keys[decoration.key] = true
		if not decoration.position.is_finite():
			found.append("decoration position is not finite")
		for bounds: Rect2 in [decoration.footprint, decoration.draw_rect]:
			if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area():
				found.append("invalid decoration measurement")
		if not floor_rect.encloses(decoration.footprint):
			found.append("decoration footprint leaves the floor")
		if not value.render_bounds.encloses(decoration.draw_rect):
			found.append("drawing bounds omit a decoration")
		for corridor in value.corridors:
			if decoration.footprint.intersects(Rect2(corridor.position * grid, corridor.size * grid)):
				found.append("decoration blocks a corridor")
		for placed in value.desks:
			if placed.measure == null:
				continue
			var physical := placed.measure.physical_rect
			physical.position += placed.origin
			var drawing := placed.measure.render_rect
			drawing.position += placed.origin
			if decoration.footprint.intersects(physical):
				found.append("decoration overlaps a table footprint")
			if decoration.draw_rect.intersects(drawing):
				found.append("decoration drawing overlaps a workstation")
	for index in value.decorations.size():
		for later in range(index + 1, value.decorations.size()):
			if value.decorations[index].footprint.intersects(value.decorations[later].footprint):
				found.append("decoration footprints overlap")
	return found
