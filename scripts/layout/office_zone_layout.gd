class_name OfficeZoneLayout
extends RefCounted
## One zone's pod rows: the bounded row allocator a workspace's tables are
## placed by, in zone-local cells (x from the zone's left edge, the partition's
## pad first; y from the zone's top, one pod row after another, with no walls
## and no cross corridors between them). It resolves business identity, not
## rendering, and it knows nothing of lanes or of the other zones:
## OfficeFloorLayout places the zone on the map and composes every zone's
## rows and desks into map cells.
##
## What it keeps from the zone's previous placement: every table's row and x
## where the table still fits (growth is left-anchored), every row (a row never
## shrinks, an emptied one stays), and a row an oversized table owns. A new
## zone is laid out next-fit; a zone laid out before reuses any gap that fits.
## A table wider than the zone was first laid out owns a row of its own, and
## the zone grows as wide as that table needs (the map planner turns the width
## into lanes). An empty workspace still gets one empty pod row.


class Candidate:
	extends RefCounted
	var row := -1
	var x := 0
	var distance := 0
	var waste := 0


## What plan() made of one zone. `desks` and `rows` are zone-local: a desk's
## reserved_cells and origin are measured from the zone's top-left corner.
class Result:
	extends RefCounted
	var rows: Array[RowPlan] = []
	## In room order (number, then key).
	var desks: Array[DeskPlacement] = []
	## Why the zone cannot be laid out, each prefixed with the zone's key.
	var problems := PackedStringArray()
	## A budget of the whole map ran out while this zone was laid out
	## (OfficeFloorLayout reports it once, unprefixed).
	var budget := ""
	var diagnostics := PackedStringArray()
	## The zone's width in cells (its pad included), always a whole number of
	## lanes (FloorLayoutPolicy.zone_width()), and how many lanes that is.
	var width_cells := 0
	var lanes := 0
	## The width the zone was first laid out at: what makes a table oversized.
	var initial_width_cells := 0
	## OfficeDeskView.node_budget() of every table, empty columns included.
	var nodes := 0


## How deep a pod row is, in cells: the measured reservation of a table
## (OfficeTable.measure()), which is the same for every capacity.
static func pod_row_cells() -> int:
	return quantized(OfficeTable.measure(2).reserved_rect).size.y


static func quantized(bounds: Rect2) -> Rect2i:
	var start := Vector2i((bounds.position / FloorLayoutPolicy.GRID).floor())
	var end := Vector2i((bounds.end / FloorLayoutPolicy.GRID).ceil())
	return Rect2i(start, end - start)


## Lay out `zone`. `previous` is where it was placed last (null for a new
## zone) and `old_desks` its tables then, by tab key, already zone-local.
## A new zone is sized for the first time: the fewest lanes its widest table
## fits in, then more, up to `lanes_cap`, while it would need more than
## `zone_tall_rows` pod rows. `nodes_left` is what the map's desk node budget
## still allows.
static func plan(
	zone: ZoneModel,
	previous: ZonePlacement,
	old_desks: Dictionary[String, DeskPlacement],
	lanes_cap: int,
	rules: FloorLayoutPolicy,
	nodes_left: int
) -> Result:
	var result := Result.new()
	var rooms: Array[RoomModel] = zone.rooms.duplicate()
	rooms.sort_custom(_by_room)
	var pod := pod_row_cells()
	var wanted: Dictionary[String, DeskPlacement] = {}
	var widest := 0
	for room in rooms:
		var old: DeskPlacement = old_desks.get(room.key)
		var seats := OfficeSeatPlanner.plan(room, old)
		result.diagnostics.append_array(seats.diagnostics)
		# Count retained capacity, not occupied seats. Empty stations still own
		# equipment and pick targets; status changes may furnish every slot.
		if seats.capacity > rules.max_width_cells:
			result.problems.append(_named(zone, "tab capacity exceeds the map width budget"))
			return result
		result.nodes += OfficeDeskView.node_budget(seats.capacity)
		if result.nodes > nodes_left:
			result.budget = "map exceeds desk node budget"
			return result
		var placed := DeskPlacement.new()
		placed.tab_key = room.key
		placed.zone_key = zone.key
		placed.capacity = seats.capacity
		placed.seats = seats.seats
		wanted[room.key] = placed
	# Only allocate per-column measurements once the whole zone fits the budget.
	for placed: DeskPlacement in wanted.values():
		placed.measure = OfficeTable.measure(placed.capacity)
		var local := quantized(placed.measure.reserved_rect)
		if local.size.y > pod:
			result.problems.append(_named(zone, "tab measurement exceeds the pod row"))
			return result
		placed.reserved_cells.size = local.size
		widest = maxi(widest, local.size.x)
	if previous != null:
		result.initial_width_cells = previous.initial_width_cells
		_allocate(result, rooms, wanted, old_desks, previous, previous.cells.size.x, rules, false)
		return _finish(result, zone, rules)
	# First placement: never narrower than the widest table, then wider while
	# the zone would stand taller than zone_tall_rows pod rows, up to the cap.
	var fewest := rules.lanes_for_inner(widest)
	var attempt: Result
	for lanes in range(fewest, maxi(fewest, lanes_cap) + 1):
		attempt = Result.new()
		attempt.nodes = result.nodes
		attempt.diagnostics = result.diagnostics
		attempt.initial_width_cells = rules.zone_width(lanes)
		for placed: DeskPlacement in wanted.values():
			placed.row = -1
		_allocate(attempt, rooms, wanted, old_desks, null, attempt.initial_width_cells, rules, true)
		if (
			not attempt.problems.is_empty()
			or not attempt.budget.is_empty()
			or attempt.rows.size() <= rules.zone_tall_rows
		):
			break
	return _finish(attempt, zone, rules)


## The row allocator: every table of `rooms` into a row of `result`, keeping
## what `previous` placed where it still fits. `width` is the zone's width now;
## an oversized table widens it.
static func _allocate(
	result: Result,
	rooms: Array[RoomModel],
	wanted: Dictionary[String, DeskPlacement],
	old_desks: Dictionary[String, DeskPlacement],
	previous: ZonePlacement,
	width: int,
	rules: FloorLayoutPolicy,
	initial: bool
) -> void:
	var pod := pod_row_cells()
	var rows: Array[RowPlan] = []
	if previous != null:
		for old_row in previous.rows:
			var row := RowPlan.new()
			row.index = old_row.index
			row.exclusive_tab_key = old_row.exclusive_tab_key if wanted.has(old_row.exclusive_tab_key) else ""
			rows.append(row)
	# Hold every surviving old rectangle while other tables are allocated:
	# simultaneous growth cannot steal another surviving table's place.
	for room in rooms:
		var old: DeskPlacement = old_desks.get(room.key)
		if old != null and old.row >= 0 and old.row < rows.size():
			rows[old.row].desks.append(old)
	var bay := result.initial_width_cells - rules.zone_pad_left_cells
	var max_rows := maxi(0, floori(float(rules.max_height_cells - rules.zones_top_cells()) / pod))
	for room in rooms:
		var placed := wanted[room.key]
		var old: DeskPlacement = old_desks.get(room.key)
		var oversized := placed.reserved_cells.size.x > bay
		if old != null and old.row >= 0 and old.row < rows.size():
			var row := rows[old.row]
			row.desks.erase(old)
			var exclusive := oversized or row.exclusive_tab_key == room.key
			var at := old.reserved_cells.position.x
			var requested := rules.zone_width(rules.lanes_for_width(maxi(width, at + placed.reserved_cells.size.x)))
			if (
				(not exclusive or row.desks.is_empty())
				and (requested == width or exclusive)
				and requested <= rules.max_zone_width_cells()
				and _fits(row, at, placed.reserved_cells.size.x, requested, rules)
			):
				_assign(placed, row, at, pod)
				if exclusive:
					row.exclusive_tab_key = room.key
				width = requested
		if placed.row < 0:
			var candidate := _find(rows, placed, old, oversized, width, rules, initial, pod)
			if candidate.row == rows.size():
				if rows.size() >= max_rows:
					result.budget = "map exceeds width, height or cell budget"
					return
				var row := RowPlan.new()
				row.index = candidate.row
				rows.append(row)
			var target := rows[candidate.row]
			_assign(placed, target, candidate.x, pod)
			if oversized:
				target.exclusive_tab_key = room.key
			width = maxi(width, rules.zone_width(rules.lanes_for_width(candidate.x + placed.reserved_cells.size.x)))
			if width > rules.max_zone_width_cells():
				result.budget = "map exceeds width, height or cell budget"
				return
		result.desks.append(placed)
	if rows.is_empty():
		# An empty workspace is still a zone: one empty pod row.
		rows.append(RowPlan.new())
	result.rows = rows
	result.width_cells = width


static func _finish(result: Result, zone: ZoneModel, rules: FloorLayoutPolicy) -> Result:
	result.lanes = rules.lanes_for_width(result.width_cells)
	for index in result.problems.size():
		if not result.problems[index].begins_with("zone "):
			result.problems[index] = _named(zone, result.problems[index])
	return result


static func _named(zone: ZoneModel, problem: String) -> String:
	return "zone %s: %s" % [zone.key, problem]


static func _by_room(a: RoomModel, b: RoomModel) -> bool:
	return a.key < b.key if a.number == b.number else a.number < b.number


static func _fits(row: RowPlan, x: int, width: int, zone_width: int, rules: FloorLayoutPolicy) -> bool:
	if x < rules.zone_pad_left_cells or x + width > zone_width:
		return false
	for other in row.desks:
		if x < other.reserved_cells.end.x and x + width > other.reserved_cells.position.x:
			return false
	return true


static func _assign(placed: DeskPlacement, row: RowPlan, x: int, pod: int) -> void:
	placed.row = row.index
	placed.reserved_cells.position = Vector2i(x, row.index * pod)
	placed.origin = (
		Vector2(placed.reserved_cells.position - quantized(placed.measure.reserved_rect).position)
		* FloorLayoutPolicy.GRID
	)
	row.desks.append(placed)


static func _find(
	rows: Array[RowPlan],
	placed: DeskPlacement,
	old: DeskPlacement,
	oversized: bool,
	width: int,
	rules: FloorLayoutPolicy,
	initial: bool,
	pod: int
) -> Candidate:
	var best: Candidate
	for row in rows:
		if not row.exclusive_tab_key.is_empty() and row.exclusive_tab_key != placed.tab_key:
			continue
		if oversized and not row.desks.is_empty():
			continue
		# A new zone is laid out next-fit; a zone laid out before reuses any gap.
		if initial and row.index != rows.size() - 1:
			continue
		var desks: Array[DeskPlacement] = row.desks.duplicate()
		desks.sort_custom(
			func(a: DeskPlacement, b: DeskPlacement) -> bool:
				return a.reserved_cells.position.x < b.reserved_cells.position.x
		)
		var x := rules.zone_pad_left_cells
		for index in desks.size() + 1:
			var end := desks[index].reserved_cells.position.x if index < desks.size() else width
			if end - x >= placed.reserved_cells.size.x or (oversized and desks.is_empty()):
				var candidate := Candidate.new()
				candidate.row = row.index
				candidate.x = x
				candidate.waste = maxi(0, end - x - placed.reserved_cells.size.x)
				if old != null:
					candidate.distance = absi(row.index - old.row) * pod + absi(x - old.reserved_cells.position.x)
				if best == null or _better(candidate, best):
					best = candidate
			if index < desks.size():
				x = desks[index].reserved_cells.end.x
	if best != null:
		return best
	best = Candidate.new()
	best.row = rows.size()
	best.x = rules.zone_pad_left_cells
	return best


static func _better(a: Candidate, b: Candidate) -> bool:
	if a.distance != b.distance:
		return a.distance < b.distance
	if a.waste != b.waste:
		return a.waste < b.waste
	return a.x < b.x if a.row == b.row else a.row < b.row
