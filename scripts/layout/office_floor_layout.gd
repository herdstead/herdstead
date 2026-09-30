class_name OfficeFloorLayout
extends RefCounted
## The map planner: every zone of a MapModel (a workspace, OfficeZoneLayout's
## pod rows) placed on one open-plan map of lanes, with the entry band and the
## main corridor around them. It resolves business identity, not rendering.
##
## The map is `lanes` lanes wide (FloorLayoutPolicy: a lane is
## zone_width_cells, an aisle column between two lanes), fixed at the first
## plan from the window's width and widened only when a zone needs more lanes
## than the map has. A zone stands in one or more adjacent lanes under an aisle
## row of its own (its slot). The placement is a masonry that only grows, down
## or right, and never moves a zone it does not have to:
## - the map widens first, once, to the most lanes any zone needs (retained
##   or new), so every decision below is taken against its final width;
## - every retained zone first holds its slot;
## - a retained zone that grows (taller, or wider by any number of lanes)
##   grows in place while the cells it grows over are free of every held
##   slot; otherwise it alone moves, and its old slot is a gap;
## - then the zones that move and the new ones, in (number, key) order, take
##   the top-most, then left-most gap their slot fits in (a new mezzanine first
##   tries directly below its source).
## The map keeps its largest extents: removing a zone leaves a gap, never a
## smaller map. A failure anywhere fails the whole map (the plan cache keeps
## the previous one); the zones at fault are named in failing_zones.
##
## The work is bounded before it is done: an empty workspace (one empty pod
## row) is charged to the table budget like a table; a map whose zones' slots
## cannot fit the dimensional budget even packed edge to edge at the final
## lane count is refused before any placement (_cannot_fit()); and a first-fit
## search stops at the first top whose slot would end past max_height_cells.


## What the slots placed so far take, lane by lane, for the first-fit search:
## each lane's taken rows as sorted, disjoint [start, end) spans (slots never
## overlap, and a slot takes whole lanes), and every row a first fit may start
## at (the zones' top and every slot's bottom), sorted. A lookup is a binary
## search, not a scan of every slot: planning many zones stays near n² log n.
class Taken:
	var lanes: Array[Lane] = []
	var tops: Array[int] = []

	class Lane:
		var starts: Array[int] = []
		var ends: Array[int] = []

	func _init(count: int, first_top: int) -> void:
		for lane in count:
			lanes.append(Lane.new())
		tops.append(first_top)

	## Take `slot`'s rows in its lanes.
	func add(slot: Rect2i, rules: FloorLayoutPolicy) -> void:
		var first := rules.lane_of(slot.position.x)
		for lane in range(first, first + rules.lanes_for_width(slot.size.x)):
			var spans := lanes[lane]
			var at := spans.starts.bsearch(slot.position.y)
			spans.starts.insert(at, slot.position.y)
			spans.ends.insert(at, slot.end.y)
		var top := tops.bsearch(slot.end.y)
		if top >= tops.size() or tops[top] != slot.end.y:
			tops.insert(top, slot.end.y)

	## Whether rows [from, to) are open in `count` lanes from `first`.
	func open(first: int, count: int, from: int, to: int) -> bool:
		for lane in range(first, first + count):
			var spans := lanes[lane]
			var after := spans.starts.bsearch(to)
			if after > 0 and spans.ends[after - 1] > from:
				return false
		return true


## Plan `map`, keeping what `previous` placed where it still fits. With a
## `fixtures` planner and a `decor` planner the candidate is furnished (the
## pantry first, then the furniture that keeps clear of it) before its
## validation. What is optional is left out when the furnished map does not
## validate, never a desk: the furniture first, then the pantry, at most three
## validations in all (see _validate_furnished()).
static func plan(
	map: MapModel,
	previous: FloorPlan = null,
	policy: FloorLayoutPolicy = null,
	decor: OfficeDecorPlanner = null,
	fixtures: OfficeFixturePlanner = null
) -> FloorLayoutResult:
	var result := FloorLayoutResult.new()
	var rules := policy if policy != null else FloorLayoutPolicy.new()
	result.problems = _input_problems(map, rules, result.failing_zones)
	if not result.problems.is_empty():
		return result
	var retained := previous
	if retained != null and (retained.floor_key != map.key or retained.policy_signature != rules.geometry_signature()):
		retained = null
	if retained != null:
		result.problems = validate(retained, rules)
		if not result.problems.is_empty():
			return result
	var next := FloorPlan.new()
	next.floor_key = map.key
	next.policy_signature = rules.geometry_signature()
	next.lanes = retained.lanes if retained != null else rules.lanes_for(rules.width_cells)
	next.initial_width_cells = retained.initial_width_cells if retained != null else rules.map_width(next.lanes)
	var zones := _ordered(map)
	var layouts: Array[OfficeZoneLayout.Result] = []
	var nodes_left := rules.max_desk_nodes
	for zone in zones:
		var before: ZonePlacement = retained.zone(zone.key) if retained != null else null
		var layout := OfficeZoneLayout.plan(zone, before, _local_desks(retained, before), next.lanes, rules, nodes_left)
		result.diagnostics.append_array(layout.diagnostics)
		if not layout.budget.is_empty() or not layout.problems.is_empty():
			result.problems = layout.problems if layout.budget.is_empty() else PackedStringArray([layout.budget])
			result.failing_zones.append(zone.key)
			return result
		nodes_left -= layout.nodes
		layouts.append(layout)
	var slots: Dictionary[String, Rect2i] = {}
	if not _cannot_fit(next.lanes, zones, layouts, retained, rules):
		slots = _place(next, zones, layouts, retained, rules)
	if slots.size() != zones.size():
		result.problems.append("floor exceeds width, height or cell budget")
		return result
	var height := maxi(rules.min_height_cells, rules.wall_cells + rules.entry_cells)
	if retained != null:
		height = maxi(height, retained.floor_cells.size.y)
	for key: String in slots:
		height = maxi(height, slots[key].end.y)
	var size := Vector2i(rules.map_width(next.lanes), height)
	if not _within_budget(size, rules):
		result.problems.append("floor exceeds width, height or cell budget")
		return result
	for index in zones.size():
		next.zones.append(_compose(next, zones[index], layouts[index], slots[zones[index].key], rules))
	_finalize(next, size, rules)
	if fixtures != null:
		fixtures.furnish(next)
	if decor != null:
		decor.policy = rules
		decor.furnish(next)
	result.problems = _validate_furnished(next, rules)
	if result.problems.is_empty():
		result.plan = next
	return result


## Validate a furnished candidate, leaving out what is optional until it
## validates: the first validation takes everything; the second leaves out the
## furniture (or, with none, the pantry); the third and last, the pantry too.
## A desk is never left out. A map that validates at once, which every shipped
## width does, is flood filled once; the second and third are the rare cases.
static func _validate_furnished(next: FloorPlan, rules: FloorLayoutPolicy) -> PackedStringArray:
	var problems := validate(next, rules)
	if problems.is_empty() or (next.decorations.is_empty() and next.pantry == null):
		return problems
	if not next.decorations.is_empty():
		next.decorations.clear()
		problems = validate(next, rules)
		if problems.is_empty() or next.pantry == null:
			return problems
	next.pantry = null
	return validate(next, rules)


## Includes geometric clearance and reachability; no scene nodes are needed.
static func validate(value: FloorPlan, policy: FloorLayoutPolicy = null) -> PackedStringArray:
	var rules := policy if policy != null else FloorLayoutPolicy.new()
	return OfficeFloorValidation.problems(value, rules)


## What the input cannot be planned for, before anything is allocated: the
## policy, the map's identity and budgets, and each zone's own tables and
## panes (prefixed `zone <key>: `, the key added to `failing`). A pane key two
## zones both carry names both zones.
static func _input_problems(map: MapModel, rules: FloorLayoutPolicy, failing: PackedStringArray) -> PackedStringArray:
	var found := rules.problems()
	if map == null or map.key.is_empty():
		found.append("floor has no stable identity")
		return found
	var tables := 0
	var panes_total := 0
	var zone_keys: Dictionary[String, bool] = {}
	for zone in map.zones:
		if zone == null or zone.key.is_empty() or zone_keys.has(zone.key):
			found.append("duplicate or missing zone identity")
			return found
		zone_keys[zone.key] = true
		# An empty workspace still lays out (and places) one empty pod row.
		tables += maxi(zone.rooms.size(), 1)
		panes_total += zone.pane_count()
	if tables > rules.max_tables:
		found.append("input exceeds table budget")
		return found
	if panes_total > rules.max_panes:
		found.append("input exceeds pane budget")
		return found
	# The modular table owns column spacing. Measure its paired-column growth
	# instead of duplicating that spacing here, before allocating any seats.
	var minimum := OfficeZoneLayout.quantized(OfficeTable.measure(2).reserved_rect).size.x
	var pair_growth := OfficeZoneLayout.quantized(OfficeTable.measure(4).reserved_rect).size.x - minimum
	var available := rules.max_zone_width_cells() - rules.zone_pad_left_cells
	if pair_growth <= 0 or available < minimum:
		found.append("floor width budget cannot contain the minimum table")
		return found
	var max_capacity := 2 + 2 * floori(float(available - minimum) / pair_growth)
	var owners: Dictionary[String, String] = {}
	for zone in map.zones:
		var problems := PackedStringArray()
		var groups: Dictionary[String, bool] = {}
		var panes: Dictionary[String, bool] = {}
		for room in zone.rooms:
			if room.panes.size() > max_capacity * 2:
				problems.append("tab exceeds measured width budget: " + room.key)
				break
			if room.key.is_empty() or groups.has(room.key):
				problems.append("duplicate or missing tab identity")
			groups[room.key] = true
			for pane in room.panes:
				if pane.key.is_empty() or panes.has(pane.key):
					problems.append("duplicate or missing pane identity")
				elif owners.has(pane.key) and owners[pane.key] != zone.key:
					problems.append("pane %s is also in zone %s" % [pane.key, owners[pane.key]])
					if not failing.has(owners[pane.key]):
						failing.append(owners[pane.key])
				panes[pane.key] = true
				owners[pane.key] = zone.key
				if pane.explicit_layout and (pane.table_x < 0 or pane.side not in ["far", "near"]):
					problems.append("invalid explicit seat hint")
		if not problems.is_empty():
			if not failing.has(zone.key):
				failing.append(zone.key)
			for problem in problems:
				found.append("zone %s: %s" % [zone.key, problem])
	return found


## The zones laid out, in (number, key) order; an empty map lays out none.
static func _ordered(map: MapModel) -> Array[ZoneModel]:
	var zones: Array[ZoneModel] = []
	zones.assign(map.zones)
	zones.sort_custom(
		func(a: ZoneModel, b: ZoneModel) -> bool: return a.key < b.key if a.number == b.number else a.number < b.number
	)
	return zones


## `retained`'s desks of the zone `before` placed, as zone-local copies by tab
## key: the previous plan itself is never changed.
static func _local_desks(retained: FloorPlan, before: ZonePlacement) -> Dictionary[String, DeskPlacement]:
	var found: Dictionary[String, DeskPlacement] = {}
	if retained == null or before == null:
		return found
	for old in retained.desks:
		if old.zone_key != before.zone_key:
			continue
		var local := DeskPlacement.new()
		local.tab_key = old.tab_key
		local.zone_key = old.zone_key
		local.row = old.row
		local.capacity = old.capacity
		local.seats = old.seats
		local.measure = old.measure
		local.reserved_cells = Rect2i(old.reserved_cells.position - before.cells.position, old.reserved_cells.size)
		local.origin = old.origin - Vector2(before.cells.position * FloorLayoutPolicy.GRID)
		found[old.tab_key] = local
	return found


## Whether the zones' slots cannot fit the dimensional budget however they are
## packed, at the final lane count: the map as wide as that, and as deep as its
## top plus the slots' lane rows (a slot k lanes wide and t rows tall takes k·t
## of them) spread over every lane, or the deepest slot, or the retained map's
## depth. A lower bound: a map it passes may still fail after placement; one it
## fails always would, so no placement is tried.
static func _cannot_fit(
	lanes: int,
	zones: Array[ZoneModel],
	layouts: Array[OfficeZoneLayout.Result],
	retained: FloorPlan,
	rules: FloorLayoutPolicy
) -> bool:
	var pod := OfficeZoneLayout.pod_row_cells()
	var wide := final_lanes(lanes, zones, layouts, retained)
	var top := rules.zones_top_cells() - rules.zone_aisle_cells
	var area := 0
	var deepest := 0
	for index in zones.size():
		var before: ZonePlacement = retained.zone(zones[index].key) if retained != null else null
		var k := maxi(layouts[index].lanes, before.lanes if before != null else 0)
		var tall := layouts[index].rows.size() * pod + rules.zone_aisle_cells
		area += k * tall
		deepest = maxi(deepest, tall)
	var height := maxi(rules.min_height_cells, top + maxi(deepest, ceili(float(area) / wide)))
	if retained != null:
		height = maxi(height, retained.floor_cells.size.y)
	return not _within_budget(Vector2i(rules.map_width(wide), height), rules)


## Every zone's slot (its aisle row and its rectangle), by zone key, in map
## cells; widens `next` (its lanes) where a zone needs more lanes than it has.
## Fewer slots than zones when a first fit found none within max_height_cells.
static func _place(
	next: FloorPlan,
	zones: Array[ZoneModel],
	layouts: Array[OfficeZoneLayout.Result],
	retained: FloorPlan,
	rules: FloorLayoutPolicy
) -> Dictionary[String, Rect2i]:
	var pod := OfficeZoneLayout.pod_row_cells()
	var slots: Dictionary[String, Rect2i] = {}
	# The map's final width, before anything is held, grown or moved: widened
	# zone by zone, a zone judged against the narrower map moved although its
	# own place fits the map a later zone widens (codex's review of ba943f9).
	next.lanes = final_lanes(next.lanes, zones, layouts, retained)
	# (a) Every retained zone holds its slot while the others are placed.
	for zone in zones:
		var before: ZonePlacement = retained.zone(zone.key) if retained != null else null
		if before != null:
			slots[zone.key] = before.slot()
	# (b) A retained zone that grows: the map widens first when the zone needs
	# more lanes than it has, then the zone grows down and right in place while
	# every cell it grows over is free; otherwise it alone moves.
	var moving: Array[int] = []
	for index in zones.size():
		var zone := zones[index]
		var before: ZonePlacement = retained.zone(zone.key) if retained != null else null
		if before == null:
			moving.append(index)
			continue
		var lanes := maxi(layouts[index].lanes, before.lanes)
		var height := layouts[index].rows.size() * pod
		if lanes == before.lanes and height == before.cells.size.y:
			continue
		var grown := Rect2i(
			before.cells.position.x, before.slot().position.y, rules.zone_width(lanes), height + rules.zone_aisle_cells
		)
		if before.first_lane + lanes <= next.lanes and _free(grown, slots, zone.key):
			slots[zone.key] = grown
		else:
			slots.erase(zone.key)
			moving.append(index)
	# (c) The zones that move and the new ones, in order: a new mezzanine
	# directly below its source when that is free, else the top-most, then
	# left-most gap its whole slot fits in.
	var taken := Taken.new(next.lanes, rules.zones_top_cells() - rules.zone_aisle_cells)
	for key: String in slots:
		taken.add(slots[key], rules)
	for index in moving:
		var zone := zones[index]
		var lanes := layouts[index].lanes
		var size := Vector2i(rules.zone_width(lanes), layouts[index].rows.size() * pod + rules.zone_aisle_cells)
		var is_new := retained == null or retained.zone(zone.key) == null
		if is_new and not zone.mezzanine_of.is_empty() and slots.has(zone.mezzanine_of):
			var source := slots[zone.mezzanine_of]
			var below := Rect2i(Vector2i(source.position.x, source.end.y), size)
			if rules.lane_of(below.position.x) + lanes <= next.lanes and _free(below, slots, zone.key):
				slots[zone.key] = below
				taken.add(below, rules)
				continue
		var fit := _first_fit(size, lanes, next.lanes, taken, rules)
		if fit.size == Vector2i.ZERO:
			return slots
		slots[zone.key] = fit
		taken.add(fit, rules)
	return slots


## The lanes the map needs: `lanes` (today's), or more when a zone needs more,
## retained (at least as many as it had) or new.
static func final_lanes(
	lanes: int, zones: Array[ZoneModel], layouts: Array[OfficeZoneLayout.Result], retained: FloorPlan
) -> int:
	var wanted := lanes
	for index in zones.size():
		var before: ZonePlacement = retained.zone(zones[index].key) if retained != null else null
		wanted = maxi(wanted, maxi(layouts[index].lanes, before.lanes if before != null else 0))
	return wanted


## The top-most, then left-most slot of `size` (`lanes` lanes wide) that meets
## nothing `taken` holds. Only the top of the rows and the bottom of a slot can
## be the top of a first fit, so only those rows are tried, and none from the
## first whose slot would end past max_height_cells: then an empty Rect2i.
static func _first_fit(size: Vector2i, lanes: int, map_lanes: int, taken: Taken, rules: FloorLayoutPolicy) -> Rect2i:
	for top in taken.tops:
		if top + size.y > rules.max_height_cells:
			return Rect2i()
		for lane in map_lanes - lanes + 1:
			if taken.open(lane, lanes, top, top + size.y):
				return Rect2i(Vector2i(rules.lane_x(lane), top), size)
	# Not reached: `lanes` never exceeds `map_lanes` (the map widens first),
	# and at the lowest slot's end every lane is free, so the loop returns.
	return Rect2i()


static func _free(slot: Rect2i, slots: Dictionary[String, Rect2i], own: String) -> bool:
	for key: String in slots:
		if key != own and slots[key].intersects(slot):
			return false
	return true


## Zone `zone` in `slot` of `next`: its rectangle under its aisle row, its rows
## and desks moved from zone-local into map cells.
static func _compose(
	next: FloorPlan, zone: ZoneModel, layout: OfficeZoneLayout.Result, slot: Rect2i, rules: FloorLayoutPolicy
) -> ZonePlacement:
	var pod := OfficeZoneLayout.pod_row_cells()
	var placed := ZonePlacement.new()
	placed.zone_key = zone.key
	placed.aisle_cells = rules.zone_aisle_cells
	placed.first_lane = rules.lane_of(slot.position.x)
	placed.lanes = rules.lanes_for_width(slot.size.x)
	placed.cells = Rect2i(
		slot.position.x, slot.position.y + rules.zone_aisle_cells, slot.size.x, slot.size.y - rules.zone_aisle_cells
	)
	placed.initial_width_cells = layout.initial_width_cells
	var grid := float(FloorLayoutPolicy.GRID)
	placed.sign_at = Vector2(
		placed.cells.position.x * grid + OfficeShell.PARTITION_THICKNESS / 2.0,
		placed.cells.position.y * grid + OfficeShell.POST_FOOT
	)
	placed.rows = layout.rows
	for row in placed.rows:
		row.band_cells = Rect2i(
			placed.cells.position.x, placed.cells.position.y + row.index * pod, placed.cells.size.x, pod
		)
	for desk in layout.desks:
		desk.reserved_cells.position += placed.cells.position
		desk.origin += Vector2(placed.cells.position) * grid
		next.desks.append(desk)
	return placed


static func _within_budget(size: Vector2i, rules: FloorLayoutPolicy) -> bool:
	return (
		size.x > 0
		and size.y > 0
		and size.x <= rules.max_width_cells
		and size.y <= rules.max_height_cells
		and size.x * size.y <= rules.max_floor_cells
	)


## The map's walls, walkways and keep-outs around its zones, and what it draws.
static func _finalize(next: FloorPlan, size: Vector2i, rules: FloorLayoutPolicy) -> void:
	next.floor_cells = Rect2i(Vector2i.ZERO, size)
	next.entry_cells = Rect2i(
		rules.outer_side_cells, rules.wall_cells, size.x - 2 * rules.outer_side_cells, rules.entry_cells
	)
	next.main_corridor_cells = Rect2i(
		size.x - rules.outer_side_cells - rules.main_corridor_cells,
		rules.wall_cells,
		rules.main_corridor_cells,
		size.y - rules.wall_cells
	)
	next.corridors = [next.entry_cells, next.main_corridor_cells]
	next.aisles = aisles_of(next, rules)
	next.render_bounds = Rect2(
		next.floor_cells.position * FloorLayoutPolicy.GRID, next.floor_cells.size * FloorLayoutPolicy.GRID
	)
	for placed in next.desks:
		var drawing := placed.measure.render_rect
		drawing.position += placed.origin
		next.render_bounds = next.render_bounds.merge(drawing)


## The keep-outs of `value`'s zones (drawn as plain floor, never stood on):
## every zone's aisle row, and every aisle column between two lanes, from under
## the entry band to the map's bottom, but where a zone spanning both lanes
## stands over it. In zone order, then the columns left to right, top down.
## The planner and the validator both work them out here.
static func aisles_of(value: FloorPlan, rules: FloorLayoutPolicy) -> Array[Rect2i]:
	var found: Array[Rect2i] = []
	for zone in value.zones:
		found.append(
			Rect2i(zone.cells.position.x, zone.cells.position.y - zone.aisle_cells, zone.cells.size.x, zone.aisle_cells)
		)
	var top := rules.wall_cells + rules.entry_cells
	for lane in value.lanes - 1:
		var column := rules.lane_x(lane) + rules.zone_width_cells
		var covered: Array[Vector2i] = []
		for zone in value.zones:
			var slot := zone.slot()
			if slot.position.x <= column and slot.end.x > column:
				covered.append(Vector2i(slot.position.y, slot.end.y))
		covered.sort()
		var y := top
		for span in covered:
			if span.x > y:
				found.append(Rect2i(column, y, rules.lane_aisle_cells, span.x - y))
			y = maxi(y, span.y)
		if value.floor_cells.size.y > y:
			found.append(Rect2i(column, y, rules.lane_aisle_cells, value.floor_cells.size.y - y))
	return found
