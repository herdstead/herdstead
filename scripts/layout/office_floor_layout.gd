class_name OfficeFloorLayout
extends RefCounted
## Small, bounded row allocator. It resolves business identity, not rendering.


class Candidate:
	extends RefCounted
	var row := -1
	var x := 0
	var distance := 0
	var waste := 0


## Plan `floor_model`, keeping what `previous` placed where it still fits. With a
## `decor` planner and a `fixtures` planner the candidate is furnished before
## its validation. What is optional is left out when the furnished floor does not
## validate, never a desk: the standing furniture first, then the pantry, then
## the reception with its queue, at most three validations in all (see
## _validate_furnished()).
static func plan(
	floor_model: ZoneModel,
	previous: FloorPlan = null,
	policy: FloorLayoutPolicy = null,
	decor: OfficeDecorPlanner = null,
	fixtures: OfficeFixturePlanner = null
) -> FloorLayoutResult:
	var result := FloorLayoutResult.new()
	var rules := policy if policy != null else FloorLayoutPolicy.new()
	result.problems = _input_problems(floor_model, rules)
	if not result.problems.is_empty():
		return result
	var retained := previous
	if (
		retained != null
		and (retained.floor_key != floor_model.key or retained.policy_signature != rules.geometry_signature())
	):
		retained = null
	if retained != null:
		result.problems = validate(retained, rules)
		if not result.problems.is_empty():
			return result
	var next := FloorPlan.new()
	next.floor_key = floor_model.key
	next.policy_signature = rules.geometry_signature()
	var minimum := _quantized(OfficeTable.measure(2).reserved_rect).size.x + _side_space(rules)
	next.initial_width_cells = (retained.initial_width_cells if retained != null else maxi(minimum, rules.width_cells))
	var width := retained.floor_cells.size.x if retained != null else next.initial_width_cells
	var old_by_key: Dictionary[String, DeskPlacement] = {}
	if retained != null:
		for old_row in retained.rows:
			var row := RowPlan.new()
			row.index = old_row.index
			row.exclusive_tab_key = old_row.exclusive_tab_key
			next.rows.append(row)
		for old in retained.desks:
			old_by_key[old.tab_key] = old
	var rooms: Array[RoomModel] = floor_model.rooms.duplicate()
	rooms.sort_custom(_by_room)
	var wanted: Dictionary[String, DeskPlacement] = {}
	var remaining_nodes := rules.max_desk_nodes
	for room in rooms:
		var old: DeskPlacement = old_by_key.get(room.key)
		var seats := OfficeSeatPlanner.plan(room, old)
		result.diagnostics.append_array(seats.diagnostics)
		# Count retained capacity, not occupied seats. Empty stations still own
		# equipment and pick targets; status changes may furnish every slot.
		if seats.capacity > rules.max_width_cells:
			result.problems.append("table capacity exceeds the floor width budget")
			return result
		remaining_nodes -= OfficeDeskView.node_budget(seats.capacity)
		if remaining_nodes < 0:
			result.problems.append("floor exceeds desk node budget")
			return result
		var placed := DeskPlacement.new()
		placed.tab_key = room.key
		placed.capacity = seats.capacity
		placed.seats = seats.seats
		wanted[room.key] = placed
		# Hold every surviving old rectangle while other groups are allocated.
		# Simultaneous growth cannot steal another surviving table's position.
		if old != null:
			next.rows[old.row].desks.append(old)
	# Only allocate per-column measurements once the whole floor fits.
	for placed: DeskPlacement in wanted.values():
		placed.measure = OfficeTable.measure(placed.capacity)
		var local := _quantized(placed.measure.reserved_rect)
		if local.size.y > rules.row_height_cells - rules.wall_cells - rules.cross_corridor_cells:
			result.problems.append("table measurement exceeds the fixed row height")
			return result
		placed.reserved_cells.size = local.size
	for row in next.rows:
		if not wanted.has(row.exclusive_tab_key):
			row.exclusive_tab_key = ""
	var bay_width := next.initial_width_cells - _side_space(rules)
	for room in rooms:
		var placed := wanted[room.key]
		var old: DeskPlacement = old_by_key.get(room.key)
		var oversized := placed.reserved_cells.size.x > bay_width
		if old != null:
			var row := next.rows[old.row]
			row.desks.erase(old)
			var exclusive := oversized or row.exclusive_tab_key == room.key
			var at := old.reserved_cells.position.x
			var requested_width := maxi(
				width, at + placed.reserved_cells.size.x + rules.main_corridor_cells + rules.outer_side_cells
			)
			var requested_size := Vector2i(requested_width, _height(next.rows.size(), rules))
			if (
				(not exclusive or row.desks.is_empty())
				and (requested_width == width or exclusive)
				and _within_budget(requested_size, rules)
			):
				if _fits(row, at, placed.reserved_cells.size.x, requested_width, rules):
					_assign(placed, row, at, rules)
					if exclusive:
						row.exclusive_tab_key = room.key
					width = requested_width
		if placed.row < 0:
			var candidate := _find(next, placed, old, oversized, width, rules, retained == null)
			if candidate.row == next.rows.size():
				var row := RowPlan.new()
				row.index = candidate.row
				next.rows.append(row)
			var target := next.rows[candidate.row]
			_assign(placed, target, candidate.x, rules)
			if oversized:
				target.exclusive_tab_key = room.key
			width = maxi(
				width, candidate.x + placed.reserved_cells.size.x + rules.main_corridor_cells + rules.outer_side_cells
			)
		# Reject before adding rows or enumerating a huge rectangular floor.
		var size := Vector2i(width, _height(next.rows.size(), rules))
		if not _within_budget(size, rules):
			result.problems.append("floor exceeds width, height or cell budget")
			return result
		next.desks.append(placed)
	_finalize(next, width, rules)
	if decor != null:
		decor.furnish(next)
	if fixtures != null:
		fixtures.furnish(next)
	result.problems = _validate_furnished(next, rules)
	if result.problems.is_empty():
		result.plan = next
	return result


## Validate a furnished candidate, leaving out what is optional until it
## validates: the first validation takes everything; the second leaves out the
## standing furniture, or the pantry where there is none, or else the reception;
## the third and last leaves out the pantry alone when only the pantry's own
## checks still fail, and both fixtures otherwise. A desk is never left out.
## A floor that validates at once, which every shipped width does, is flood
## filled once; the second and third are the rare cases.
static func _validate_furnished(next: FloorPlan, rules: FloorLayoutPolicy) -> PackedStringArray:
	var problems := validate(next, rules)
	if problems.is_empty() or (next.decorations.is_empty() and next.reception == null):
		return problems
	if not next.decorations.is_empty():
		next.decorations.clear()
	elif next.pantry != null:
		next.pantry = null
	else:
		next.reception = null
	problems = validate(next, rules)
	if problems.is_empty() or next.reception == null:
		return problems
	var pantry_only := next.pantry != null
	for problem in problems:
		pantry_only = pantry_only and problem.contains("pantry")
	next.pantry = null
	if not pantry_only:
		next.reception = null
	return validate(next, rules)


## Includes geometric clearance and reachability; no scene nodes are needed.
static func validate(value: FloorPlan, policy: FloorLayoutPolicy = null) -> PackedStringArray:
	var rules := policy if policy != null else FloorLayoutPolicy.new()
	return OfficeFloorValidation.problems(value, rules)


static func _input_problems(floor_model: ZoneModel, rules: FloorLayoutPolicy) -> PackedStringArray:
	var found := rules.problems()
	if floor_model == null or floor_model.key.is_empty():
		found.append("floor has no stable identity")
		return found
	if floor_model.rooms.size() > rules.max_tables:
		found.append("input exceeds table budget")
		return found
	if floor_model.pane_count() > rules.max_panes:
		found.append("input exceeds pane budget")
		return found
	# The modular table owns column spacing. Measure its paired-column growth
	# instead of duplicating that spacing here, before allocating any seats.
	var minimum := _quantized(OfficeTable.measure(2).reserved_rect).size.x
	var pair_growth := _quantized(OfficeTable.measure(4).reserved_rect).size.x - minimum
	var available := rules.max_width_cells - _side_space(rules)
	if pair_growth <= 0 or available < minimum:
		found.append("floor width budget cannot contain the minimum table")
		return found
	var max_capacity := 2 + 2 * floori(float(available - minimum) / pair_growth)
	var groups: Dictionary[String, bool] = {}
	var panes: Dictionary[String, bool] = {}
	for room in floor_model.rooms:
		if room.panes.size() > max_capacity * 2:
			found.append("tab exceeds measured width budget: " + room.key)
			return found
		if room.key.is_empty() or groups.has(room.key):
			found.append("duplicate or missing tab identity")
		groups[room.key] = true
		for pane in room.panes:
			if pane.key.is_empty() or panes.has(pane.key):
				found.append("duplicate or missing pane identity")
			panes[pane.key] = true
			if pane.explicit_layout and (pane.table_x < 0 or pane.side not in ["far", "near"]):
				found.append("invalid explicit seat hint")
	return found


static func _by_room(a: RoomModel, b: RoomModel) -> bool:
	return a.key < b.key if a.number == b.number else a.number < b.number


static func _quantized(bounds: Rect2) -> Rect2i:
	var start := Vector2i((bounds.position / FloorLayoutPolicy.GRID).floor())
	var end := Vector2i((bounds.end / FloorLayoutPolicy.GRID).ceil())
	return Rect2i(start, end - start)


static func _side_space(rules: FloorLayoutPolicy) -> int:
	return 2 * rules.outer_side_cells + rules.main_corridor_cells


static func _height(rows: int, rules: FloorLayoutPolicy) -> int:
	return maxi(rules.min_height_cells, rules.wall_cells + rules.entry_cells + rows * rules.row_height_cells)


static func _within_budget(size: Vector2i, rules: FloorLayoutPolicy) -> bool:
	return (
		size.x > 0
		and size.y > 0
		and size.x <= rules.max_width_cells
		and size.y <= rules.max_height_cells
		and size.x * size.y <= rules.max_floor_cells
	)


static func _fits(row: RowPlan, x: int, width: int, floor_width: int, rules: FloorLayoutPolicy) -> bool:
	if x < rules.outer_side_cells or x + width > floor_width - rules.outer_side_cells - rules.main_corridor_cells:
		return false
	for other in row.desks:
		if x < other.reserved_cells.end.x and x + width > other.reserved_cells.position.x:
			return false
	return true


static func _assign(placed: DeskPlacement, row: RowPlan, x: int, rules: FloorLayoutPolicy) -> void:
	placed.row = row.index
	var y := rules.wall_cells + rules.entry_cells + row.index * rules.row_height_cells + rules.wall_cells
	placed.reserved_cells.position = Vector2i(x, y)
	placed.origin = (
		Vector2(placed.reserved_cells.position - _quantized(placed.measure.reserved_rect).position)
		* FloorLayoutPolicy.GRID
	)
	row.desks.append(placed)


static func _find(
	next: FloorPlan,
	placed: DeskPlacement,
	old: DeskPlacement,
	oversized: bool,
	width: int,
	rules: FloorLayoutPolicy,
	initial: bool
) -> Candidate:
	var best: Candidate
	for row in next.rows:
		if not row.exclusive_tab_key.is_empty() and row.exclusive_tab_key != placed.tab_key:
			continue
		if oversized and not row.desks.is_empty():
			continue
		# Initial layout is next-fit, while later updates reuse any suitable gap.
		if initial and row.index != next.rows.size() - 1:
			continue
		var desks: Array[DeskPlacement] = row.desks.duplicate()
		desks.sort_custom(
			func(a: DeskPlacement, b: DeskPlacement) -> bool:
				return a.reserved_cells.position.x < b.reserved_cells.position.x
		)
		var x := rules.outer_side_cells
		for index in desks.size() + 1:
			var end := (
				desks[index].reserved_cells.position.x
				if index < desks.size()
				else width - rules.outer_side_cells - rules.main_corridor_cells
			)
			if end - x >= placed.reserved_cells.size.x or (oversized and desks.is_empty()):
				var candidate := Candidate.new()
				candidate.row = row.index
				candidate.x = x
				candidate.waste = maxi(0, end - x - placed.reserved_cells.size.x)
				if old != null:
					candidate.distance = (
						absi(row.index - old.row) * rules.row_height_cells + absi(x - old.reserved_cells.position.x)
					)
				if best == null or _better(candidate, best):
					best = candidate
			if index < desks.size():
				x = desks[index].reserved_cells.end.x
	if best != null:
		return best
	best = Candidate.new()
	best.row = next.rows.size()
	best.x = rules.outer_side_cells
	return best


static func _better(a: Candidate, b: Candidate) -> bool:
	if a.distance != b.distance:
		return a.distance < b.distance
	if a.waste != b.waste:
		return a.waste < b.waste
	return a.x < b.x if a.row == b.row else a.row < b.row


static func _finalize(next: FloorPlan, width: int, rules: FloorLayoutPolicy) -> void:
	var height := _height(next.rows.size(), rules)
	next.floor_cells = Rect2i(0, 0, width, height)
	var inside_width := width - 2 * rules.outer_side_cells
	next.entry_cells = Rect2i(rules.outer_side_cells, rules.wall_cells, inside_width, rules.entry_cells)
	next.main_corridor_cells = Rect2i(
		width - rules.outer_side_cells - rules.main_corridor_cells,
		rules.wall_cells,
		rules.main_corridor_cells,
		height - rules.wall_cells
	)
	next.corridors = [next.entry_cells, next.main_corridor_cells]
	for row in next.rows:
		var y := rules.wall_cells + rules.entry_cells + row.index * rules.row_height_cells
		row.band_cells = Rect2i(0, y, width, rules.row_height_cells)
		row.wall_cells = Rect2i(0, y, next.main_corridor_cells.position.x, rules.wall_cells)
		row.corridor_cells = Rect2i(
			rules.outer_side_cells,
			y + rules.row_height_cells - rules.cross_corridor_cells,
			inside_width,
			rules.cross_corridor_cells
		)
		next.corridors.append(row.corridor_cells)
	next.render_bounds = Rect2(
		next.floor_cells.position * FloorLayoutPolicy.GRID, next.floor_cells.size * FloorLayoutPolicy.GRID
	)
	for placed in next.desks:
		var drawing := placed.measure.render_rect
		drawing.position += placed.origin
		next.render_bounds = next.render_bounds.merge(drawing)
