class_name OfficeFloorValidation
extends RefCounted
## Whether a map plan can be drawn and walked: its bounds, budgets, zones in
## their lanes, pod rows, tables and furniture, then cell-centre connectivity
## against physical
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
		found.append("map must be a positive rectangle at the fixed origin")
	if size.x > rules.max_width_cells or size.y > rules.max_height_cells or size.x * size.y > rules.max_floor_cells:
		found.append("map exceeds width, height or cell budget")
	if not found.is_empty():
		return found
	# Previous plans are inputs too. Reject before copying rows, enumerating
	# historical columns or allocating measurements for any of their desks.
	if value.desks.size() > rules.max_tables:
		return PackedStringArray(["layout exceeds tab budget"])
	var remaining_nodes := rules.max_desk_nodes
	var remaining_panes := rules.max_panes
	for placed in value.desks:
		if placed.capacity < 2 or placed.capacity % 2 != 0 or placed.capacity > rules.max_width_cells:
			return PackedStringArray(["tab capacity must be at least two and grow in pairs"])
		remaining_nodes -= OfficeDeskView.node_budget(placed.capacity)
		if remaining_nodes < 0:
			return PackedStringArray(["map exceeds desk node budget"])
		remaining_panes -= placed.seats.size()
		if remaining_panes < 0:
			return PackedStringArray(["layout exceeds pane budget"])
	var grid := FloorLayoutPolicy.GRID
	if value.lanes < 1 or size.x != rules.map_width(value.lanes):
		found.append("map width is not its lanes' width")
	var inside_width := size.x - 2 * rules.outer_side_cells
	var expected_entry := Rect2i(rules.outer_side_cells, rules.wall_cells, inside_width, rules.entry_cells)
	var expected_main := Rect2i(
		size.x - rules.outer_side_cells - rules.main_corridor_cells,
		rules.wall_cells,
		rules.main_corridor_cells,
		size.y - rules.wall_cells
	)
	if value.entry_cells != expected_entry or value.main_corridor_cells != expected_main:
		found.append("map does not contain its declared entrance and main corridor")
	if value.corridors.size() != 2 or value.corridors[0] != expected_entry or value.corridors[1] != expected_main:
		found.append("walkways are not the entrance and the main corridor")
	if not value.render_bounds.encloses(Rect2(value.floor_cells.position * grid, size * grid)):
		found.append("drawing bounds do not contain the complete map")
	found.append_array(_zone_problems(value, rules))
	var keys: Dictionary[String, bool] = {}
	var panes: Dictionary[String, bool] = {}
	var keep_out: Array[Rect2i] = value.corridors.duplicate()
	keep_out.append_array(value.aisles)
	for placed in value.desks:
		if placed.tab_key.is_empty() or keys.has(placed.tab_key):
			found.append("duplicate or missing tab identity")
		keys[placed.tab_key] = true
		var zone := value.zone(placed.zone_key)
		if zone == null or placed.row < 0 or placed.row >= zone.rows.size() or placed.measure == null:
			found.append("tab has no valid zone, row or measurement")
			continue
		if not zone.rows[placed.row].desks.has(placed):
			found.append("tab missing from its row")
		var measurement := placed.measure
		if measurement.capacity != placed.capacity or measurement.columns.size() != placed.capacity:
			found.append("tab capacity and measurement disagree")
		# The renderer uses table_width to allocate modules. A stale/tampered
		# measure must not buy an arbitrarily wide table with a small capacity.
		var expected := OfficeTable.measure(placed.capacity)
		if measurement.table_width != expected.table_width or measurement.columns != expected.columns:
			found.append("tab width or columns disagree with measured capacity")
		for positions: Array[Vector2] in [measurement.far_approaches, measurement.near_approaches]:
			if positions.size() != placed.capacity:
				found.append("tab is missing measured approaches")
		if not placed.origin.is_finite():
			found.append("tab origin is not finite")
		var reserved := Rect2(placed.reserved_cells.position * grid, placed.reserved_cells.size * grid)
		for bounds: Rect2 in [measurement.reserved_rect, measurement.render_rect, measurement.physical_rect]:
			if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area():
				found.append("invalid tab measurement")
			bounds.position += placed.origin
			if not reserved.encloses(bounds):
				found.append("tab measurement leaves its reservation")
		var drawing := measurement.render_rect
		drawing.position += placed.origin
		if not value.render_bounds.encloses(drawing):
			found.append("drawing bounds omit part of a tab")
		var inner := Rect2i(
			zone.cells.position.x + rules.zone_pad_left_cells,
			zone.cells.position.y,
			zone.cells.size.x - rules.zone_pad_left_cells,
			zone.cells.size.y
		)
		if not inner.encloses(placed.reserved_cells):
			found.append("tab reservation leaves its zone")
		if not zone.rows[placed.row].band_cells.encloses(placed.reserved_cells):
			found.append("tab reservation leaves its row")
		for walkway in keep_out:
			if placed.reserved_cells.intersects(walkway):
				found.append("tab reservation intersects a corridor or aisle")
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
				found.append("seat does not belong to the measured tab")
	for index in value.desks.size():
		for later in range(index + 1, value.desks.size()):
			if value.desks[index].reserved_cells.intersects(value.desks[later].reserved_cells):
				found.append("tab reservations overlap")
	for walkway in keep_out:
		if not value.floor_cells.encloses(walkway):
			found.append("corridor or aisle leaves the map")
	found.append_array(_decor_problems(value))
	found.append_array(_fixture_problems(value))
	if not found.is_empty():
		return found
	found.append_array(_route_problems(value, rules))
	return found


## Whether the zones are where the map planner puts them: each in whole lanes
## (its x its first lane's, 10k - 1 wide), from row 6 down, its height whole
## pod rows; the slots (aisle row and rectangle) disjoint and on the floor left
## of the main corridor; each zone's rows its bands, top to bottom, an oversized
## table alone in its row; the aisles exactly what the zones leave
## (OfficeFloorLayout.aisles_of()), and no zone over a corridor or an aisle.
static func _zone_problems(value: FloorPlan, rules: FloorLayoutPolicy) -> PackedStringArray:
	var found := PackedStringArray()
	var pod := OfficeZoneLayout.pod_row_cells()
	var bay := Rect2i(
		rules.outer_side_cells,
		rules.wall_cells + rules.entry_cells,
		rules.zone_width(value.lanes),
		value.floor_cells.size.y - rules.wall_cells - rules.entry_cells
	)
	var keys: Dictionary[String, bool] = {}
	var desks := 0
	for zone in value.zones:
		if zone.zone_key.is_empty() or keys.has(zone.zone_key):
			found.append("duplicate or missing zone identity")
		keys[zone.zone_key] = true
		var area := zone.cells
		if (
			zone.lanes < 1
			or zone.aisle_cells != rules.zone_aisle_cells
			or area.position.x != rules.lane_x(zone.first_lane)
			or area.size.x != rules.zone_width(zone.lanes)
			or zone.first_lane < 0
			or zone.first_lane + zone.lanes > value.lanes
		):
			found.append("zone %s is not in whole lanes" % zone.zone_key)
		if area.position.y < rules.zones_top_cells() or area.size.y <= 0 or area.size.y % pod != 0:
			found.append("zone %s is not whole pod rows under the top aisle" % zone.zone_key)
		if not bay.encloses(zone.slot()):
			found.append("zone %s leaves the map" % zone.zone_key)
		if zone.rows.size() * pod != area.size.y:
			found.append("zone %s rows do not fill it" % zone.zone_key)
		for index in zone.rows.size():
			var row := zone.rows[index]
			if (
				row.index != index
				or row.band_cells != Rect2i(area.position.x, area.position.y + index * pod, area.size.x, pod)
			):
				found.append("zone %s row %d does not match the pod row" % [zone.zone_key, index])
			if not row.exclusive_tab_key.is_empty():
				if row.desks.size() != 1 or row.desks[0].tab_key != row.exclusive_tab_key:
					found.append("oversized row ownership is not exclusive")
			for placed in row.desks:
				desks += 1
				if placed.zone_key != zone.zone_key or placed.row != index or not value.desks.has(placed):
					found.append("zone %s row %d holds a tab not placed there" % [zone.zone_key, index])
		for corridor in value.corridors:
			if area.intersects(corridor):
				found.append("zone %s stands on a corridor" % zone.zone_key)
	if desks != value.desks.size():
		found.append("a tab stands in no zone row")
	for index in value.zones.size():
		for later in range(index + 1, value.zones.size()):
			if value.zones[index].slot().intersects(value.zones[later].slot()):
				found.append("zones %s and %s overlap" % [value.zones[index].zone_key, value.zones[later].zone_key])
	if value.aisles != OfficeFloorLayout.aisles_of(value, rules):
		found.append("aisles are not what the zones leave")
	for zone in value.zones:
		for aisle in value.aisles:
			if zone.cells.intersects(aisle):
				found.append("zone %s stands on an aisle" % zone.zone_key)
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
## The pantry the same way: every spot's approach is reached from the
## threshold's end, and its leg up to the fixture row is clear.
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
		for index in fixture.spots.size():
			var approach := fixture.approaches[index]
			var cell := OfficeWalkGraph.cell_of(approach)
			if not graph.reaches(cell) or not graph.clear(OfficeWalkGraph.centre(cell), approach):
				found.append("unreachable %s approach: %d" % [fixture.key, index])
			elif not graph.clear_route(OfficeWalkGraph.leg_to_fixture(approach, fixture.spots[index])):
				found.append("blocked %s leg: %d" % [fixture.key, index])
	return found


## Whether the pantry is where the fixture planner puts it: only on a map with
## desks; its counter inside the entry band, left of the main corridor, its
## drawing on the floor; its spots on the fixture row from the left wall on, a
## pitch apart, ending FIXTURE_GAP at least before the main corridor, each
## approach straight below its spot on the walking lane; 1 to MAX_PANTRY spots.
static func _fixture_problems(value: FloorPlan) -> PackedStringArray:
	var found := PackedStringArray()
	var pantry := value.pantry
	if pantry == null:
		return found
	if value.desks.is_empty():
		found.append("fixture: a pantry on a map without desks")
	var grid := float(FloorLayoutPolicy.GRID)
	var band := Rect2(value.entry_cells.position * grid, value.entry_cells.size * grid)
	if band.size.y < OfficeShell.WALKING_LANE + grid / 2.0:
		found.append("fixture: the entry band has no fixture row and walking lane")
	var bay_end := value.main_corridor_cells.position.x * grid
	var row_y := band.position.y + OfficeShell.FIXTURE_ROW
	var lane_y := band.position.y + OfficeShell.WALKING_LANE
	var half := OfficeShell.SPOT_PITCH / 2.0
	if pantry.key != "pantry" or pantry.kind != FixturePlacement.Kind.PANTRY or pantry.piece == &"":
		found.append("fixture: the pantry has no identity")
	for bounds: Rect2 in [pantry.footprint, pantry.draw_rect]:
		if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.has_area():
			found.append("fixture: invalid pantry measurement")
	if not band.encloses(pantry.footprint) or pantry.footprint.end.x > bay_end:
		found.append("fixture: pantry stands outside the entry band's bay")
	if not value.render_bounds.encloses(pantry.draw_rect):
		found.append("drawing bounds omit the pantry")
	if pantry.spots.size() < 1 or pantry.spots.size() > OfficeShell.MAX_PANTRY:
		found.append("fixture: pantry holds %d" % pantry.spots.size())
	if pantry.approaches.size() != pantry.spots.size():
		found.append("fixture: pantry spots and approaches disagree")
		return found
	for index in pantry.spots.size():
		var spot := pantry.spots[index]
		if (
			spot.y != row_y
			or pantry.approaches[index] != Vector2(spot.x, lane_y)
			or not is_equal_approx(spot.x, band.position.x + half + index * OfficeShell.SPOT_PITCH)
			or spot.x + half + OfficeShell.FIXTURE_GAP > bay_end + 0.001
		):
			found.append("fixture: pantry spot %d is off its row" % index)
	return found


## Where no standing piece may stand, in map units: the entry band but its
## first row (the top wall's drawing clearance, where nobody walks and the
## top-wall run stands at the wall's foot), the main corridor and every aisle.
## The decor planner keeps to the same rule.
static func walkways(value: FloorPlan) -> Array[Rect2]:
	var grid := float(FloorLayoutPolicy.GRID)
	var band := value.entry_cells
	var found: Array[Rect2] = [
		Rect2(Vector2(band.position.x, band.position.y + 1) * grid, Vector2(band.size.x, band.size.y - 1) * grid)
	]
	var cells: Array[Rect2i] = [value.main_corridor_cells]
	cells.append_array(value.aisles)
	for walkway in cells:
		found.append(Rect2(walkway.position * grid, walkway.size * grid))
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
			found.append("decoration footprint leaves the map")
		if not value.render_bounds.encloses(decoration.draw_rect):
			found.append("drawing bounds omit a decoration")
		for walkway in walkways(value):
			if decoration.footprint.intersects(walkway):
				found.append("decoration blocks a corridor")
		for placed in value.desks:
			if placed.measure == null:
				continue
			var physical := placed.measure.physical_rect
			physical.position += placed.origin
			var drawing := placed.measure.render_rect
			drawing.position += placed.origin
			if decoration.footprint.intersects(physical):
				found.append("decoration overlaps a tab footprint")
			if decoration.draw_rect.intersects(drawing):
				found.append("decoration drawing overlaps a workstation")
	for index in value.decorations.size():
		for later in range(index + 1, value.decorations.size()):
			if value.decorations[index].footprint.intersects(value.decorations[later].footprint):
				found.append("decoration footprints overlap")
	return found
