extends "res://tools/test_base.gd"
## Pure: the map planner (OfficeFloorLayout) placing zones in lanes, as a
## masonry that only grows, and its plan cache's atomic failure; the partitions
## in the walk graph; the top-wall run and the lane gaps keeping clear. Split
## from the layout suite (tools/test_office_layout.gd) when it neared the lint
## cap; the helpers are its own.

## The widths a floor is first planned at in the shipped windows, narrowest to
## widest (the layout suite's).
const FURNISHED_WIDTHS: Array[int] = [11, 20, 32, 60]
## Panes of a pod that fills a pod row of a one-lane zone: 6 columns, 7 of its
## 8 inner cells, so no other pod shares its row (two 2-pane pods, 3 cells
## each, do share one).
const ROW := 12

var people: PixelPeople
## Made on first use by _pen().
var pen: OfficeDraw


func _initialize() -> void:
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	run_cases()


func _marker() -> String:
	return "OFFICE MAP TESTS"


func _pane(key: String, x := -1, side := "far", order := -1) -> PaneModel:
	var pane := PaneModel.new()
	pane.key = key
	pane.pane_id = key
	pane.explicit_layout = x >= 0
	pane.table_x = x
	pane.side = side
	pane.layout_order = order
	return pane


func _room(key: String, count := 0, number := 0) -> RoomModel:
	var room := RoomModel.new()
	room.key = key
	room.tab_id = key
	room.number = number
	for index in count:
		room.panes.append(_pane("%s-%03d" % [key, index]))
	return room


func _floor(rooms: Array[RoomModel]) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = "machine/workspace"
	floor_model.rooms = rooms
	return floor_model


func _plan(floor_model: ZoneModel, previous: FloorPlan = null, policy: FloorLayoutPolicy = null) -> FloorPlan:
	var rules := policy if policy != null else FloorLayoutPolicy.new()
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), previous, rules)
	_eq(result.problems, PackedStringArray(), "valid plan: " + "; ".join(result.problems))
	_check(result.plan != null, "plan returned")
	return result.plan


## The shipped pack's pen, made once: the decor planner measures its props and
## the lettering on the walls with it.
func _pen() -> OfficeDraw:
	if pen == null:
		pen = OfficeDraw.new(ArtPack.from_manifest("res://assets/daylight/manifest.json"))
	return pen


## A floor model under its own key.
func _keyed(key: String, rooms: Array[RoomModel]) -> ZoneModel:
	var floor_model := _floor(rooms)
	floor_model.key = key
	return floor_model


## A workspace `key` numbered `number` with `rooms`: one zone of a map.
func _zoned(key: String, number: int, rooms: Array[RoomModel]) -> ZoneModel:
	var zone := _keyed(key, rooms)
	zone.number = number
	return zone


## `map` (or a map of one workspace) planned `width` cells wide as the cache
## plans it: furnished, with its pantry, in one validation.
func _furnished(model: RefCounted, width: int) -> FloorPlan:
	var map := _map_of(model)
	var rules := _real_rules(width)
	var before := OfficeFloorValidation.validations
	var result := OfficeFloorLayout.plan(
		map, null, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "%d cells: a valid floor: %s" % [width, "; ".join(result.problems)])
	_eq(OfficeFloorValidation.validations - before, 1, "%d cells: validated once, furniture included" % width)
	return result.plan


## The furniture of `plan` standing in `gap` (its "%02d/gap/%04d" keys).
func _gap_pieces(plan: FloorPlan, gap: OfficeDecorPlanner.LaneGap) -> Array[DecorPlacement]:
	var found: Array[DecorPlacement] = []
	for placed in plan.decorations:
		if not placed.key.begins_with("%02d/gap/" % gap.lane):
			continue
		var row := placed.key.get_slice("/", 2).to_int()
		if row >= gap.top and row < gap.end:
			found.append(placed)
	return found


## A map of three workspaces of different heights, side by side and stacked,
## which leaves lane gaps under the shorter ones.
func _three_zones() -> MapModel:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", ROW), _room("b", ROW, 1), _room("c", ROW, 2)]),
		_zoned("machine/2", 2, [_room("d", 2)]),
		_zoned("machine/3", 3, [_room("e", ROW), _room("f", ROW, 1)]),
	]
	return MapModel.of_zones("machine", zones)


## `model` as a map: itself, or a map of that one workspace.
func _map_of(model: RefCounted) -> MapModel:
	if model is MapModel:
		return model as MapModel
	return MapModel.of(model as ZoneModel)


func _real_rules(width := 32) -> FloorLayoutPolicy:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = width
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	return rules


func _graph_of(plan: FloorPlan, rules: FloorLayoutPolicy) -> OfficeWalkGraph:
	return OfficeWalkGraph.of(plan, rules.actor_footprint, rules.actor_draw_rect)


## Every approach of `plan` is walked to from its door, through the threshold.
func _every_approach_walked(plan: FloorPlan, rules: FloorLayoutPolicy, where: String, least := 80) -> void:
	var graph := _graph_of(plan, rules)
	var count := 0
	for placed in plan.desks:
		for column in placed.capacity:
			for side: String in OfficeTable.SIDES:
				var approach := placed.origin + placed.measure.approach_position(column, side)
				var route := graph.from_door(OfficeWalkGraph.cell_of(approach))
				var named := "%s: %s %d %s" % [where, placed.tab_key, column, side]
				_check(
					route.size() >= 2 and route[0] == graph.door and route[1] == graph.threshold,
					named + " from the door"
				)
				if not route.is_empty():
					_eq(route[route.size() - 1], approach, named + " to the approach")
				count += 1
	_check(count >= least, "%s: every approach, %d of them" % [where, count])


## The plan of `zones` as one map "machine" (MapModel.of_zones()), `width`
## cells asked for, keeping what `previous` placed; asserts it is valid.
func _map_plan(zones: Array[ZoneModel], previous: FloorPlan = null, width := 25) -> FloorPlan:
	var result := OfficeFloorLayout.plan(MapModel.of_zones("machine", zones), previous, _real_rules(width))
	_eq(result.problems, PackedStringArray(), "a valid map: " + "; ".join(result.problems))
	_check(result.plan != null, "the map is planned")
	return result.plan


## Every zone's rectangle in `plan`, by key.
static func _areas(plan: FloorPlan) -> Dictionary[String, Rect2i]:
	var found: Dictionary[String, Rect2i] = {}
	for zone in plan.zones:
		found[zone.zone_key] = zone.cells
	return found


## Every desk's origin in `plan`, by tab key.
static func _origins(plan: FloorPlan) -> Dictionary[String, Vector2]:
	var found: Dictionary[String, Vector2] = {}
	for placed in plan.desks:
		found[placed.tab_key] = placed.origin
	return found


## Four one-lane zones over two lanes: 1 is two pod rows deep, 2, 3 and 4 one.
func _four_zones() -> Array[ZoneModel]:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", ROW), _room("b", ROW, 1)]),
		_zoned("machine/2", 2, [_room("c", 2)]),
		_zoned("machine/3", 3, [_room("d", 2)]),
		_zoned("machine/4", 4, [_room("e", 2)]),
	]
	return zones


## Zones are placed in (number, key) order, each on the top-most, then
## left-most gap its whole slot (its aisle row and its rectangle) fits in, over
## two lanes of 9 cells with an aisle column between them: 1 and 2 side by
## side under the entry band, 3 under 2 (the top-most gap), 4 under 1.
func test_zones_take_the_top_most_left_most_fit_in_lanes() -> void:
	var plan := _map_plan(_four_zones())
	if plan == null:
		return
	var pod := OfficeZoneLayout.pod_row_cells()
	_eq([plan.lanes, plan.floor_cells.size.x], [2, 23], "two lanes, 10 * 2 + 3 cells")
	_eq(
		plan.zones.map(func(zone: ZonePlacement) -> String: return zone.zone_key),
		["machine/1", "machine/2", "machine/3", "machine/4"],
		"in order"
	)
	var expected := {
		"machine/1": Rect2i(1, 6, 9, 2 * pod),
		"machine/2": Rect2i(11, 6, 9, pod),
		"machine/3": Rect2i(11, 7 + pod, 9, pod),
		"machine/4": Rect2i(1, 7 + 2 * pod, 9, pod),
	}
	for zone in plan.zones:
		_eq(zone.cells, expected[zone.zone_key], zone.zone_key + ": its rectangle")
		_eq(
			zone.slot(),
			Rect2i(zone.cells.position - Vector2i(0, 1), zone.cells.size + Vector2i(0, 1)),
			zone.zone_key + ": its slot is its aisle row and it"
		)
		_eq([zone.first_lane, zone.lanes], [0 if zone.cells.position.x == 1 else 1, 1], zone.zone_key + ": one lane")
	_eq(plan.floor_cells.size.y, 7 + 3 * pod, "as deep as the lowest slot")
	for index in plan.zones.size():
		for later in range(index + 1, plan.zones.size()):
			_check(not plan.zones[index].slot().intersects(plan.zones[later].slot()), "slots never overlap")


## A removed zone leaves its slot a gap, and nothing moves into it until a zone
## that fits comes: the next new zone takes it (the top-most gap).
func test_a_removed_zone_leaves_a_gap_the_next_zone_that_fits_reuses() -> void:
	var zones := _four_zones()
	var first := _map_plan(zones)
	var gone := zones[1]
	zones.remove_at(1)
	var without := _map_plan(zones, first)
	if first == null or without == null:
		return
	for zone in without.zones:
		_eq(zone.cells, first.zone(zone.zone_key).cells, zone.zone_key + " keeps its rectangle")
	_eq(without.floor_cells, first.floor_cells, "the map keeps its extents")
	zones.append(_zoned("machine/5", 5, [_room("f", 2)]))
	var refilled := _map_plan(zones, without)
	if refilled == null:
		return
	_eq(refilled.zone("machine/5").cells, first.zone(gone.key).cells, "the new zone takes the gap")
	_eq(_areas(refilled).size(), 4, "four zones again")
	for zone in without.zones:
		_eq(refilled.zone(zone.zone_key).cells, zone.cells, zone.zone_key + " still where it was")


## The map keeps its largest extents: removing its lowest zone, emptying a
## lane, removing every zone, or a smaller zone coming back never shrinks it.
func test_the_map_keeps_its_extents_when_its_last_zone_goes() -> void:
	var zones := _four_zones()
	var first := _map_plan(zones)
	if first == null:
		return
	zones.remove_at(3)
	var lowest := _map_plan(zones, first)
	_eq(lowest.floor_cells, first.floor_cells, "the lowest zone goes: the map stays")
	zones = [zones[0]] as Array[ZoneModel]
	var one_lane := _map_plan(zones, lowest)
	_eq(one_lane.floor_cells, first.floor_cells, "the second lane empties: the map stays")
	_eq(one_lane.lanes, first.lanes, "and keeps its lanes")
	var none: Array[ZoneModel] = []
	var empty := _map_plan(none, one_lane)
	_eq(empty.floor_cells, first.floor_cells, "every zone goes: the map stays")
	_eq(empty.zones.size(), 0, "with no zone")
	var back: Array[ZoneModel] = [_zoned("machine/9", 9, [_room("z", 2)])]
	var small := _map_plan(back, empty)
	_eq(small.floor_cells, first.floor_cells, "a smaller zone comes back: the map stays")
	_eq(small.zone("machine/9").cells.position, Vector2i(1, 6), "at the top-left")


## A zone that grows taller grows down in place while the rows below it are
## free: every other zone keeps its rectangle and every other desk its origin.
func test_a_zone_grows_down_in_place_while_the_rows_below_are_free() -> void:
	var zones := _four_zones()
	var first := _map_plan(zones)
	zones[3].rooms.append(_room("e2", ROW, 1))
	var grown := _map_plan(zones, first)
	if first == null or grown == null:
		return
	var pod := OfficeZoneLayout.pod_row_cells()
	var before := first.zone("machine/4").cells
	_eq(
		grown.zone("machine/4").cells,
		Rect2i(before.position, before.size + Vector2i(0, pod)),
		"4 grows down by a pod row"
	)
	for zone in first.zones:
		if zone.zone_key != "machine/4":
			_eq(grown.zone(zone.zone_key).cells, zone.cells, zone.zone_key + " keeps its rectangle")
	for tab: String in _origins(first):
		_eq(grown.desk(tab).origin, first.desk(tab).origin, tab + " keeps its origin")
	_check(grown.floor_cells.size.y > first.floor_cells.size.y, "the map grows under it")


## A zone that cannot grow in place (2, with 3 under it) moves alone, to the
## top-most, left-most gap its new slot fits in; its old slot becomes a gap;
## every other zone keeps its rectangle and every other desk its origin.
func test_a_zone_that_cannot_grow_in_place_moves_alone() -> void:
	var zones := _four_zones()
	var first := _map_plan(zones)
	zones[1].rooms.append(_room("c2", ROW, 1))
	var grown := _map_plan(zones, first)
	if first == null or grown == null:
		return
	var pod := OfficeZoneLayout.pod_row_cells()
	var moved := grown.zone("machine/2").cells
	_check(moved.position != first.zone("machine/2").cells.position, "2 moved")
	_eq(moved.size, Vector2i(9, 2 * pod), "two pod rows deep now")
	# 2's own old slot is free now, but 3 stands under it; 4 under 1; so the
	# first fit is lane 1 under 3.
	_eq(moved.position, first.zone("machine/3").cells.position + Vector2i(0, pod + 1), "under 3, where it first fits")
	for zone in first.zones:
		if zone.zone_key != "machine/2":
			_eq(grown.zone(zone.zone_key).cells, zone.cells, zone.zone_key + " keeps its rectangle")
	for tab: String in ["a", "b", "d", "e"]:
		_eq(grown.desk(tab).origin, first.desk(tab).origin, tab + " keeps its origin")


## One observation takes a pod from 8 panes (4 columns, 5 cells: one lane) to 48
## (24 columns, 25 cells): its zone needs as many lanes as the measured pod's
## width asks (lanes_for_inner(), ceil((w + 2) / 10) for a pod w cells wide),
## three, more than the map's two, so the map widens first, by ten cells a
## lane: the main corridor and the lift door move right, the pantry stays, and
## the zone grows right in place (the other zone, one pod of two lanes, stands
## under it); the unrelated zone keeps its rectangle.
func test_a_pod_that_needs_more_lanes_widens_the_map_first() -> void:
	var rules := _real_rules(25)
	var zones: Array[ZoneModel] = [_zoned("machine/1", 1, [_room("a", 8)]), _zoned("machine/2", 2, [_room("b", 20)])]
	var fixtures := OfficeFixturePlanner.new(_pen())
	var first := OfficeFloorLayout.plan(MapModel.of_zones("machine", zones), null, rules, null, fixtures).plan
	zones[0].rooms[0].panes = _room("a", 48).panes
	var grown := OfficeFloorLayout.plan(MapModel.of_zones("machine", zones), first, rules, null, fixtures).plan
	_check(first != null and grown != null, "both maps are planned")
	if first == null or grown == null:
		return
	var width := OfficeZoneLayout.quantized(OfficeTable.measure(grown.desk("a").capacity).reserved_rect).size.x
	var lanes := ceili((width + 2) / 10.0)
	_eq(grown.desk("a").capacity, 24, "48 panes seat 24 columns")
	_eq(rules.lanes_for_inner(width), lanes, "the lane span is ceil((w + 2) / 10): %d cells, %d lanes" % [width, lanes])
	_eq(first.zone("machine/1").lanes, 1, "8 panes (4 columns, 5 cells) took one lane")
	_eq([width, lanes], [25, 3], "48 panes: 24 columns, 25 cells, three lanes")
	_eq([first.lanes, grown.lanes], [2, 3], "the map widened from two lanes to three")
	_eq(first.zone("machine/2").cells.position, Vector2i(1, 13), "the other zone stands under it")
	_eq(grown.zone("machine/1").lanes, lanes, "the zone spans them")
	_eq(grown.lanes, lanes, "the map widened to them first")
	_eq(grown.floor_cells.size.x - first.floor_cells.size.x, 10 * (lanes - first.lanes), "by ten cells a lane")
	var moved := (grown.main_corridor_cells.position.x - first.main_corridor_cells.position.x) * 32
	_eq(moved, 320 * (lanes - first.lanes), "the main corridor moves with it")
	_eq(OfficeShell.door(grown) - OfficeShell.door(first), Vector2(moved, 0), "and the lift door")
	_eq(grown.pantry.position, first.pantry.position, "the pantry stays")
	_eq(grown.zone("machine/1").cells.position, first.zone("machine/1").cells.position, "the zone grew in place")
	_eq(grown.zone("machine/2").cells, first.zone("machine/2").cells, "the other zone keeps its rectangle")
	_eq(grown.desk("b").origin, first.desk("b").origin, "and its desk its origin")


## Two zones grow in one observation: 1 wider (into the lane 2 holds) and 2
## taller. 2's slot is held while 1 grows, so 1 cannot take it: 1 moves alone,
## 2 grows down in place, 3 stays, and no slot overlaps another.
func test_simultaneous_growth_never_takes_a_held_zone() -> void:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", 2)]),
		_zoned("machine/2", 2, [_room("b", 2)]),
		_zoned("machine/3", 3, [_room("c", 2)]),
	]
	var first := _map_plan(zones)
	# Twenty panes: 10 columns, 11 cells, two lanes.
	zones[0].rooms[0].panes = _room("a", 20).panes
	zones[1].rooms.append(_room("b2", ROW, 1))
	var grown := _map_plan(zones, first)
	if first == null or grown == null:
		return
	var pod := OfficeZoneLayout.pod_row_cells()
	var two := first.zone("machine/2").cells
	_eq(grown.zone("machine/2").cells, Rect2i(two.position, two.size + Vector2i(0, pod)), "2 grows down in place")
	_eq(grown.zone("machine/3").cells, first.zone("machine/3").cells, "3 stays")
	var one := grown.zone("machine/1")
	_eq(one.lanes, 2, "1 spans two lanes now")
	_check(not one.slot().intersects(first.zone("machine/2").slot()), "1 never takes 2's held slot")
	_check(one.cells.position.y > first.zone("machine/3").cells.end.y, "it moved under everything in its lanes")
	_eq(grown.desk("c").origin, first.desk("c").origin, "3's desk keeps its origin")
	for index in grown.zones.size():
		for later in range(index + 1, grown.zones.size()):
			_check(not grown.zones[index].slot().intersects(grown.zones[later].slot()), "slots never overlap")


## A new mezzanine is placed directly below its source's slot, in the same
## lanes, even where the first fit is elsewhere; only when it is first placed.
## Forming or breaking a group later changes no signature and moves nothing.
func test_a_mezzanine_lands_below_its_source_once_and_grouping_moves_nothing() -> void:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", ROW), _room("b", ROW, 1)]),
		_zoned("machine/2", 2, [_room("c", 2)]),
	]
	var first := _map_plan(zones)
	var loose := _zoned("machine/9", 9, [_room("m", 2)])
	var plain: Array[ZoneModel] = [zones[0], zones[1], loose]
	var fitted := _map_plan(plain, first)
	var mezzanine := _zoned("machine/9", 9, [_room("m", 2)])
	mezzanine.mezzanine_of = "machine/1"
	var grouped: Array[ZoneModel] = [zones[0], zones[1], mezzanine]
	var below := _map_plan(grouped, first)
	if first == null or fitted == null or below == null:
		return
	var source := first.zone("machine/1")
	_eq(
		fitted.zone("machine/9").cells.position,
		Vector2i(11, 7 + OfficeZoneLayout.pod_row_cells()),
		"a plain zone takes the first fit, under 2"
	)
	_eq(
		below.zone("machine/9").slot().position,
		Vector2i(source.cells.position.x, source.cells.end.y),
		"a mezzanine lands right under its source"
	)
	_eq(below.zone("machine/9").first_lane, source.first_lane, "in its lanes")
	var signature := below.geometry_signature()
	mezzanine.mezzanine_of = ""
	var broken := _map_plan(grouped, below)
	_eq(broken.geometry_signature(), signature, "breaking the group moves nothing")
	loose.mezzanine_of = "machine/1"
	var formed := _map_plan(plain, fitted)
	_eq(formed.geometry_signature(), fitted.geometry_signature(), "forming it later moves nothing either")
	_eq(
		MapModel.of_zones("machine", plain).geometry_signature(),
		(
			MapModel
			. of_zones("machine", [zones[0], zones[1], _zoned("machine/9", 9, [_room("m", 2)])] as Array[ZoneModel])
			. geometry_signature()
		),
		"a grouping is not geometry"
	)


## The mezzanine hint steers a zone's first placement only. A mezzanine first
## placed while its source was not open takes the first fit (lane 0, top); its
## source opening later is placed as any new zone (lane 1, under A); when the
## mezzanine then has to move (B stands under it), it takes the first fit
## again, the top-most, left-most (lane 0, under B), not the gap directly below
## its source (lane 1, as deep).
func test_a_mezzanine_hint_steers_only_its_first_placement() -> void:
	var mezzanine := _zoned("machine/9", 9, [_room("m", 2)])
	mezzanine.mezzanine_of = "machine/1"
	var zones: Array[ZoneModel] = [mezzanine, _zoned("machine/10", 10, [_room("a", 2)])]
	zones.append(_zoned("machine/11", 11, [_room("b", 2)]))
	var first := _map_plan(zones)
	zones.append(_zoned("machine/1", 1, [_room("s", 2)]))
	var opened := _map_plan(zones, first)
	mezzanine.rooms.append(_room("m2", ROW, 1))
	var moved := _map_plan(zones, opened)
	if first == null or opened == null or moved == null:
		return
	var pod := OfficeZoneLayout.pod_row_cells()
	_eq(first.zone("machine/9").cells.position, Vector2i(1, 6), "no source open: the first fit, lane 0 at the top")
	_eq(first.zone("machine/11").cells.position, Vector2i(1, 7 + pod), "B under it")
	var source := opened.zone("machine/1")
	_eq(source.cells.position, Vector2i(11, 7 + pod), "the source opens as any new zone does: lane 1, under A")
	_eq(opened.zone("machine/9").cells, first.zone("machine/9").cells, "the mezzanine stays where it is")
	var zone := moved.zone("machine/9")
	_eq(zone.cells.size.y, 2 * pod, "grown to two pod rows, it had to move")
	_eq(zone.cells.position, Vector2i(1, 8 + 2 * pod), "to the first fit, lane 0 under B")
	_check(zone.slot().position != Vector2i(source.cells.position.x, source.cells.end.y), "not below its source")


## An empty workspace is still a zone: one empty pod row, no desk. A lobby
## lays out no zone at all.
func test_an_empty_workspace_is_a_zone_of_one_empty_row() -> void:
	var plan := _plan(_floor([]))
	_eq(plan.zones.size(), 1, "one zone")
	_eq(plan.zones[0].rows.size(), 1, "of one pod row")
	_eq(plan.zones[0].rows[0].desks.size(), 0, "with no desk in it")
	_eq(plan.zones[0].cells.size, Vector2i(9, OfficeZoneLayout.pod_row_cells()), "one lane, one pod row")
	_eq(plan.desks.size(), 0, "no invented table")
	var empty := OfficeFloorLayout.plan(MapModel.empty("machine"), null, _real_rules()).plan
	_eq([empty.zones.size(), empty.desks.size()], [0, 0], "an empty map has no zone")


## A map's signature is its key and its zones' signatures, sorted: the order
## the zones come in and a mezzanine grouping change nothing, their geometry
## does. A map of one zone signs as that zone does.
func test_a_map_signature_sorts_zones_and_ignores_grouping() -> void:
	var one := _zoned("machine/1", 1, [_room("a", 2)])
	var two := _zoned("machine/2", 2, [_room("b", 2)])
	var forward := MapModel.of_zones("machine", [one, two] as Array[ZoneModel])
	var backward := MapModel.of_zones("machine", [two, one] as Array[ZoneModel])
	_eq(forward.geometry_signature(), backward.geometry_signature(), "the zones' order changes nothing")
	var signatures := [one.geometry_signature(), two.geometry_signature()]
	signatures.sort()
	_eq(forward.geometry_signature(), JSON.stringify(["machine", signatures]), "the key and the sorted zones")
	var signature := forward.geometry_signature()
	two.mezzanine_of = "machine/1"
	_eq(forward.geometry_signature(), signature, "a grouping changes nothing")
	two.rooms.append(_room("c", 2, 1))
	_check(forward.geometry_signature() != signature, "a zone's geometry does")
	_check(
		(
			MapModel.of_zones("other", [one] as Array[ZoneModel]).geometry_signature()
			!= MapModel.of_zones("machine", [one, two] as Array[ZoneModel]).geometry_signature()
		),
		"and so do its zones"
	)
	_eq(
		MapModel.of_zones("machine", [one] as Array[ZoneModel]).geometry_signature(),
		one.geometry_signature(),
		"one zone signs as that zone"
	)
	var fresh := MapModel.of_zones("machine", [one, two] as Array[ZoneModel])
	_eq(
		[fresh.rooms.size(), fresh.pane_count()],
		[3, one.pane_count() + two.pane_count()],
		"its rooms (flattened when it is made) and panes, every zone's"
	)


## Partitions are obstacles of their own, inflated by the feet only: on a map
## of two lanes with zones one to three pod rows deep and its pantry, one of
## them against the main corridor, no node centre is inside a partition, no
## edge crosses one (the left band from the aisle into the pad column, the
## right band out of the passage, the bottom band down out of the zone), the
## pad column and the rows either side of the bottom band are walked, every
## approach is walked to from the door and every seat leg is clear.
func test_no_walk_edge_crosses_a_partition_and_every_approach_is_reached() -> void:
	var rules := _real_rules(25)
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", 2)]),
		_zoned("machine/2", 2, [_room("b", 2), _room("c", 2, 1)]),
		_zoned("machine/3", 3, [_room("d", 2), _room("e", 2, 1), _room("f", 2, 2)]),
	]
	var result := OfficeFloorLayout.plan(
		MapModel.of_zones("machine", zones), null, rules, null, OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "valid, seat legs and all")
	if result.plan == null:
		return
	var plan := result.plan
	_check(plan.pantry != null, "with its pantry")
	var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
	var against := false
	for zone in plan.zones:
		var area := zone.cells
		against = against or area.end.x == plan.main_corridor_cells.position.x
		for band in zone.partitions():
			var inflated := Rect2(band.position - rules.actor_footprint.end, band.size + rules.actor_footprint.size)
			for y in plan.floor_cells.size.y:
				for x in plan.floor_cells.size.x:
					if graph.walkable(Vector2i(x, y)):
						_check(
							(
								not inflated.has_point(OfficeWalkGraph.centre(Vector2i(x, y)))
								or _on_edge(inflated, OfficeWalkGraph.centre(Vector2i(x, y)))
							),
							"%s: node %d,%d outside the partition" % [zone.zone_key, x, y]
						)
		for y in range(area.position.y, area.end.y):
			_check(
				not graph.linked(Vector2i(area.position.x - 1, y), OfficeWalkGraph.RIGHT),
				"%s row %d: nothing steps in over the left band" % [zone.zone_key, y]
			)
			_check(
				not graph.linked(Vector2i(area.end.x - 1, y), OfficeWalkGraph.RIGHT),
				"%s row %d: nothing steps out over the right band" % [zone.zone_key, y]
			)
			_check(
				graph.walkable(Vector2i(area.position.x, y)), "%s row %d: the pad column is walked" % [zone.zone_key, y]
			)
		for x in range(area.position.x, area.end.x):
			_check(
				not graph.linked(Vector2i(x, area.end.y - 1), OfficeWalkGraph.DOWN),
				"%s column %d: nothing steps down over the bottom band" % [zone.zone_key, x]
			)
		if area.end.y < plan.floor_cells.size.y:
			_check(
				graph.walkable(Vector2i(area.position.x + 1, area.end.y)),
				"%s: the row under its bottom band is walked" % zone.zone_key
			)
	_check(against, "a zone stands against the main corridor")
	_every_approach_walked(plan, rules, "three zones", 24)
	var partitions := graph.obstacles.filter(
		func(each: OfficeWalkGraph.Obstacle) -> bool: return each.kind == OfficeWalkGraph.Kind.PARTITION
	)
	_eq(partitions.size(), 3 * plan.zones.size(), "three partition bands a zone, of their own kind")


## Whether `point` lies on the border of `box`: touching is not entering.
static func _on_edge(box: Rect2, point: Vector2) -> bool:
	return point.x == box.position.x or point.x == box.end.x or point.y == box.position.y or point.y == box.end.y


## One zone whose new input cannot be planned (an explicit seat hint off the
## table) fails the whole map: the cache keeps the whole previous plan and the
## model it was made for, names that zone, and applies none of the other
## zones' changes of that input either; a corrected input plans again.
func test_one_invalid_zone_keeps_the_whole_previous_map() -> void:
	var cache := FloorPlanCache.new()
	var zones: Array[ZoneModel] = [_zoned("machine/1", 1, [_room("a", 2)]), _zoned("machine/2", 2, [_room("b", 2)])]
	var valid := MapModel.of_zones("machine", zones)
	var plan := cache.prepare(valid, _pen(), 800.0)
	_check(plan != null and cache.problems().is_empty(), "a valid map")
	var bad := _zoned("machine/2", 2, [_room("b", 2)])
	bad.rooms[0].panes.append(_pane("hinted", 3, "sideways"))
	var grown := _zoned("machine/1", 1, [_room("a", 2), _room("a2", 2, 1)])
	var broken := MapModel.of_zones("machine", [grown, bad] as Array[ZoneModel])
	_eq(cache.prepare(broken, _pen(), 800.0), plan, "the whole previous plan stays")
	_eq(cache.failing_zones("machine"), PackedStringArray(["machine/2"]), "and names the zone at fault")
	_check("zone machine/2: invalid explicit seat hint" in cache.problems(), "and why: %s" % [cache.problems()])
	_eq(cache.planned_model("machine"), valid, "drawn from the model it was made for")
	_eq(plan.desk("a2"), null, "the other zone's change waits too")
	var fixed := MapModel.of_zones("machine", [grown, _zoned("machine/2", 2, [_room("b", 2)])] as Array[ZoneModel])
	var replanned := cache.prepare(fixed, _pen(), 800.0)
	_eq(
		[cache.problems(), cache.failing_zones("machine")],
		[PackedStringArray(), PackedStringArray()],
		"a corrected input clears both"
	)
	_check(replanned != plan and replanned.desk("a2") != null, "and plans it")


## An agent's pane that moves from one zone to another in the very input where
## the zone it left cannot be planned (codex's case) is never seated twice: the
## whole previous map stays, where it sat once, and the presentation sees it once.
func test_a_pane_moving_between_zones_during_a_failure_is_never_seated_twice() -> void:
	var cache := FloorPlanCache.new()
	var mover := _agent_pane("machine/p")
	var one := _zoned("machine/1", 1, [_room("a")])
	one.rooms[0].panes = [mover, _agent_pane("machine/q")] as Array[PaneModel]
	var two := _zoned("machine/2", 2, [_room("b")])
	two.rooms[0].panes = [_agent_pane("machine/r")] as Array[PaneModel]
	var before := MapModel.of_zones("machine", [one, two] as Array[ZoneModel])
	var plan := cache.prepare(before, _pen(), 800.0)
	var left := _zoned("machine/1", 1, [_room("a")])
	var stays := _agent_pane("machine/q")
	stays.explicit_layout = true
	stays.table_x = 0
	stays.side = "sideways"
	left.rooms[0].panes = [stays] as Array[PaneModel]
	var joined := _zoned("machine/2", 2, [_room("b")])
	joined.rooms[0].panes = [_agent_pane("machine/r"), _agent_pane("machine/p")] as Array[PaneModel]
	var after := MapModel.of_zones("machine", [left, joined] as Array[ZoneModel])
	_eq(after.repeated_keys(), {}, "the incoming map carries the pane once")
	_eq(cache.prepare(after, _pen(), 800.0), plan, "the zone it left fails: the whole previous plan stays")
	_eq(cache.failing_zones("machine"), PackedStringArray(["machine/1"]), "naming that zone")
	var drawn := cache.planned_model("machine")
	_eq(drawn, before, "drawn from the previous model")
	_eq(drawn.repeated_keys(), {}, "which carries it once")
	var seated := 0
	for placed in plan.desks:
		seated += 1 if placed.seat("machine/p") != null else 0
	_eq(seated, 1, "seated once")
	var sightings := OfficePresentation.new().sightings(plan, drawn)
	_eq(sightings.size(), 3, "and seen once, with the other two")


## An agent pane (it has a worker to see).
func _agent_pane(key: String) -> PaneModel:
	var pane := _pane(key)
	pane.provider = "claude"
	pane.state = "working"
	return pane


## The desk node budget is charged on the composed map: two zones of a
## 200-column pod cost 28,452 nodes of 32,768 (26 + 71 a column); the first
## growing to 262 columns (18,628) fits on its own but not with the second's
## 14,226 (32,854 in all), so the whole map fails, the previous one stays, and
## the zone the total ran out at is named. (Codex's numbers, 31,666 and 32,930
## at 216 columns, were the long tables' 33 + 79 a column.)
func test_the_budget_is_charged_on_the_composed_map() -> void:
	var cache := FloorPlanCache.new()
	var zones: Array[ZoneModel] = [_zoned("machine/1", 1, [_room("a", 400)]), _zoned("machine/2", 2, [_room("b", 400)])]
	var plan := cache.prepare(MapModel.of_zones("machine", zones), _pen(), 800.0)
	_check(plan != null and cache.problems().is_empty(), "two 200-column zones fit: %s" % [cache.problems()])
	if plan == null:
		return
	_eq([plan.desk("a").capacity, plan.desk("b").capacity], [200, 200], "200 columns each")
	_eq(OfficeDeskView.node_budget(200) * 2, 28452, "28,452 nodes")
	_eq(OfficeDeskView.node_budget(262), 18628, "the grown first zone alone: 18,628")
	_eq(
		OfficeDeskView.node_budget(262) + OfficeDeskView.node_budget(200),
		32854,
		"a grown first zone and the second: 32,854"
	)
	var grown: Array[ZoneModel] = [_zoned("machine/1", 1, [_room("a", 524)]), _zoned("machine/2", 2, [_room("b", 400)])]
	_eq(
		cache.prepare(MapModel.of_zones("machine", grown), _pen(), 800.0),
		plan,
		"over the budget: the previous map stays"
	)
	_eq(cache.problems(), PackedStringArray(["map exceeds desk node budget"]), "charged on the whole map")
	_eq(cache.failing_zones("machine"), PackedStringArray(["machine/2"]), "the zone it ran out at")


## The furniture keeps clear of what the map draws: every top-wall plant and
## lane-gap piece, grown by WALL_RUN_GAP, clear of the lift door, every window,
## every picture, the pantry counter, every zone's slot (its partitions, posts
## and sign: the sign as the scene draws it lies in the slot's aisle row) and
## every workstation, with its footprint off every walkway and aisle. At every
## shipped width and on maps of several zones.
func test_top_run_and_lane_gap_pieces_clear_the_door_windows_pantry_signs_and_partitions() -> void:
	var board: OfficeZoneSign = OfficeFloorView.ZONE_SIGN_SCENE.instantiate()
	board.dress(_pen())
	var pieces := 0
	var tops := 0
	for width in FURNISHED_WIDTHS:
		for model: RefCounted in [_floor([_room("a", 2), _room("b", 2, 1)]), _three_zones()]:
			var plan := _furnished(model, width)
			if plan == null:
				continue
			var grid := 32.0
			var covers: Array[Rect2] = OfficeShell.wall_covers(plan, _pen())
			for foot in OfficeShell.frames(plan, _pen()):
				covers.append(OfficeShell.drawn(_pen(), ArtContract.PROP_WALL_FRAME, foot))
			for zone in plan.zones:
				var slot := Rect2(zone.slot().position * grid, zone.slot().size * grid)
				covers.append(slot)
				board.position = zone.sign_at
				var hung := board.drawn_rect()
				_check(slot.encloses(hung), "%d cells: %s's sign lies in its slot: %s" % [width, zone.zone_key, hung])
				var aisle := Rect2(slot.position, Vector2(slot.size.x, grid))
				_check(aisle.encloses(hung), "%d cells: in its aisle row" % width)
			for placed in plan.desks:
				var drawing := placed.measure.render_rect
				drawing.position += placed.origin
				covers.append(drawing)
			var walkways := OfficeFloorValidation.walkways(plan)
			for placed in plan.decorations:
				pieces += 1
				tops += 1 if placed.key.begins_with("top/") else 0
				var near := placed.draw_rect.grow(OfficeShell.WALL_RUN_GAP)
				for cover in covers:
					_check(not near.intersects(cover), "%d cells: %s clears %s" % [width, placed.key, cover])
				for walkway in walkways:
					_check(
						not placed.footprint.intersects(walkway),
						"%d cells: %s stands off %s" % [width, placed.key, walkway]
					)
	board.free()
	_check(pieces > 20 and tops > 0, "the maps stand furniture: %d pieces, %d on the top wall" % [pieces, tops])


## A lane gap's pieces are keyed by their lane and row: where another zone
## grows (in another lane, or down into its own lane's gap below), the pieces
## still in their gap keep their keys and their places.
func test_lane_gap_pieces_keep_their_keys_when_another_zone_grows() -> void:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", 2)]),
		_zoned("machine/2", 2, [_room("b", ROW), _room("c", ROW, 1), _room("d", ROW, 2)]),
	]
	var first := _furnished(MapModel.of_zones("machine", zones), 25)
	zones[1].rooms.append(_room("e", ROW, 3))
	var retained := (
		OfficeFloorLayout
		. plan(
			MapModel.of_zones("machine", zones),
			first,
			_real_rules(25),
			OfficeDecorPlanner.new(_pen()),
			OfficeFixturePlanner.new(_pen())
		)
		. plan
	)
	_check(first != null and retained != null, "planned")
	if first == null or retained == null:
		return
	_check(retained.zone("machine/2").cells.size.y > first.zone("machine/2").cells.size.y, "zone 2 grew")
	var kept := 0
	for placed in first.decorations:
		if not placed.key.begins_with("00/gap/"):
			continue
		var after: DecorPlacement = null
		for other in retained.decorations:
			if other.key == placed.key:
				after = other
		_check(after != null, "lane 0's %s is still there" % placed.key)
		if after != null:
			_eq([after.piece, after.position], [placed.piece, placed.position], "and where it was: " + placed.key)
			kept += 1
	_check(kept >= 3, "lane 0's gap stands pieces: %d" % kept)


## The zone sign is as wide as what it says (round 1's fixed 128-unit panel
## was mostly empty cream): PAD, the stripe, GAP, the number, GAP, the label,
## PAD; a longer label, a wider panel; at most MAX_WIDTH, a longer label cut
## with its forced ellipsis; never past the limit it is given (the floor view
## gives the zone's top-right post); and its hover area is the drawn panel.
func test_the_zone_sign_is_as_wide_as_what_it_says() -> void:
	var board: OfficeZoneSign = OfficeFloorView.ZONE_SIGN_SCENE.instantiate()
	board.dress(_pen())
	var panel: NinePatchRect = board.get_node("%Panel")
	var accent: ColorRect = board.get_node("%Accent")
	var number: Label = board.get_node("%Number")
	var title: Label = board.get_node("%Title")
	var shape: CollisionShape2D = board.get_node("%Shape")
	var face := title.get_theme_font("font")
	var widths: Array[float] = []
	for label: String in ["A", "API", "HERDSTEAD", "M".repeat(60)]:
		var zone := _zoned("machine/" + label, 3, [])
		zone.label = label
		for limit: float in [INF, 90.0]:
			board.show_zone(zone, limit)
			var drawn := board.drawn_rect()
			var what := "%s (limit %s)" % [label.left(12), limit]
			var natural := ceilf(face.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
			_eq(accent.position.x, panel.position.x + OfficeZoneSign.PAD, what + ": the stripe PAD in")
			_eq(number.position.x, accent.position.x + accent.size.x + OfficeZoneSign.GAP, what + ": the number GAP on")
			_eq(title.position.x, number.position.x + number.size.x + OfficeZoneSign.GAP, what + ": the label GAP on")
			_eq(
				drawn.end.x,
				title.position.x + title.size.x + OfficeZoneSign.PAD,
				what + ": the panel ends PAD after it"
			)
			_check(drawn.size.x <= OfficeZoneSign.MAX_WIDTH, what + ": at most MAX_WIDTH: %s" % drawn.size.x)
			_check(drawn.end.x <= limit, what + ": never past its limit: %s" % drawn.end.x)
			if drawn.size.x < OfficeZoneSign.MAX_WIDTH and drawn.end.x < limit:
				_eq(title.size.x, natural, what + ": the whole label, uncut")
			else:
				_check(title.size.x < natural, what + ": the label cut to fit")
				_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE, what + ": with an ellipsis")
			var hover := Rect2(shape.position - shape.shape.get_rect().size / 2.0, shape.shape.get_rect().size)
			_eq(hover, drawn, what + ": the hover area is the drawn panel")
			if limit == INF:
				widths.append(drawn.size.x)
	_check(widths[0] < widths[1] and widths[1] < widths[2], "a longer label, a wider panel: %s" % [widths])
	_eq(widths[3], OfficeZoneSign.MAX_WIDTH, "a very long one stops at MAX_WIDTH")
	_check(widths[1] < 64.0, "API's sign is small: %s" % widths[1])
	board.free()


## A workspace's label may be anything. The sign writes it in the pen's own
## display face (OfficeDraw.display: the pixel font over the system fallbacks,
## the one the plates and the chips wear), so the glyphs the pixel font lacks
## are filled and `数据` is not two missing-glyph boxes. One fallback list, the
## pen's: the sign makes no font of its own. A label with such glyphs leaves
## the panel as tall as it was, and its text inside the panel.
func test_the_zone_sign_writes_a_cjk_label_in_the_pens_display_face() -> void:
	var board: OfficeZoneSign = OfficeFloorView.ZONE_SIGN_SCENE.instantiate()
	board.dress(_pen())
	# In the tree: a Label reports its line's height only there.
	root.add_child(board)
	var pixel := _pen().art.display_font
	_check(pixel != null and not pixel.has_char("数".unicode_at(0)), "the pixel face alone has no 数")
	var panel: NinePatchRect = board.get_node("%Panel")
	var tall: Array[float] = []
	for label: String in ["DATA", "数据", "数据 PIPELINE"]:
		var zone := _zoned("machine/" + label, 5, [])
		zone.label = label
		# Twice, a frame apart, as the office's reconciles write it: a Label
		# takes its line's height once its minimum size has settled.
		board.show_zone(zone)
		await process_frame
		board.show_zone(zone)
		for part: String in ["%Number", "%Title"]:
			var text: Label = board.get_node(part)
			var face := text.get_theme_font("font")
			_check(face == _pen().display, "%s %s: the pen's display face" % [label, part])
			_check(not face.fallbacks.is_empty(), "%s %s: with its fallbacks" % [label, part])
			var box := Rect2(panel.position, panel.size * panel.scale)
			_check(
				box.encloses(Rect2(text.position, text.size)),
				"%s %s: inside the panel: %s in %s" % [label, part, Rect2(text.position, text.size), box]
			)
		var title: Label = board.get_node("%Title")
		_eq(title.text, label, label + ": written as it is")
		tall.append(board.drawn_rect().size.y)
	_eq(tall, [16.0, 16.0, 16.0] as Array[float], "the panel is 16 tall whatever the label")
	board.free()


## A fallback's glyphs can make the line taller than the room under the words
## (on Linux, Noto Sans CJK's line at 8 is 13 tall where the board leaves 12,
## and a CJK label hung a pixel below it). The line takes what it lacks from
## the padding above it and stays on the board; a line that fits stays where
## the scene puts it. A face five rows taller than the pixel face stands in
## for such a line on any machine.
func test_a_taller_line_stays_on_the_zone_signs_board() -> void:
	var pixel := _pen().art.display_font
	var tops: Array[float] = []
	for extra: int in [0, 5]:
		var own := OfficeDraw.new(_pen().art)
		var face := FontVariation.new()
		face.base_font = pixel
		face.spacing_top = extra
		own.display = face
		var board: OfficeZoneSign = OfficeFloorView.ZONE_SIGN_SCENE.instantiate()
		board.dress(own)
		root.add_child(board)
		var zone := _zoned("machine/data", 5, [])
		zone.label = "DATA"
		board.show_zone(zone)
		await process_frame
		board.show_zone(zone)
		var panel: NinePatchRect = board.get_node("%Panel")
		var box := Rect2(panel.position, panel.size * panel.scale)
		var title: Label = board.get_node("%Title")
		_eq(
			title.size.y,
			pixel.get_height(OfficeDraw.DISPLAY_PIXELS) + extra,
			"+%d: the line is as tall as its face" % extra
		)
		_check(
			box.encloses(Rect2(title.position, title.size)),
			"+%d: on the board: %s in %s" % [extra, Rect2(title.position, title.size), box]
		)
		_eq(board.drawn_rect().size.y, 16.0, "+%d: the board is 16 tall" % extra)
		tops.append(title.position.y)
		board.free()
	_eq(tops[0], -20.0, "a line that fits starts where the scene puts it")
	_check(tops[1] < tops[0], "a taller one starts higher: %s" % [tops])


## The map's final width is settled before any retained zone is held, grown or
## moved (codex's review of ba943f9, P1): in one refresh the blocker left of A
## goes, A grows 2 → 20 panes (two lanes) and B under both grows 20 → 48 (three
## lanes). Widened zone by zone, A was judged against the two-lane map and moved
## to (1, 6) although its own place fits the three-lane map B brings; widened
## first, A grows right in place at (11, 6) and B grows in place under it.
func test_the_map_widens_for_every_zone_before_any_zone_is_moved() -> void:
	var zones: Array[ZoneModel] = [
		_zoned("machine/0", 0, [_room("r0", 2)]),
		_zoned("machine/a", 1, [_room("ra", 2)]),
		_zoned("machine/b", 2, [_room("rb", 20)]),
	]
	var first := _map_plan(zones)
	if first == null:
		return
	_eq(
		[first.zone("machine/0").cells, first.zone("machine/a").cells, first.zone("machine/b").cells],
		[Rect2i(1, 6, 9, 6), Rect2i(11, 6, 9, 6), Rect2i(1, 13, 19, 6)],
		"the blocker and A side by side, B of two lanes under both"
	)
	var signature := first.geometry_signature()
	var after: Array[ZoneModel] = [_zoned("machine/a", 1, [_room("ra", 20)]), _zoned("machine/b", 2, [_room("rb", 48)])]
	var grown := _map_plan(after, first)
	if grown == null:
		return
	_eq(first.geometry_signature(), signature, "the previous map is unchanged")
	_eq(grown.lanes, 3, "the map widened to B's three lanes")
	_eq(grown.zone("machine/a").cells, Rect2i(11, 6, 19, 6), "A grew right in place, from (11, 6), over two lanes")
	_eq(grown.zone("machine/b").cells, Rect2i(1, 13, 29, 6), "B grew right in place under it, over three")


## Empty workspaces are bounded work (codex's review of ba943f9, P2): each is a
## zone of one empty pod row, so it is charged to the table budget, and a map
## whose slots cannot fit max_height_cells even packed lane by lane is refused
## before any placement. Straight from herdr's wire (HerdrSnapshot.from_wire(),
## OfficeProjection.project()): 100 empty workspaces plan; 290, the most two
## lanes hold (5 + 145 · 7 = 1020 of 1024 rows), plan too; 291 do not, nor 600
## (4.4 s before, placing every one first), nor 4096 (HerdrSnapshot's cap, over
## the table budget), each refused promptly and by name. The bound is generous
## for CI load: the refusals measure a few to 25 ms here.
func test_many_empty_workspaces_are_refused_before_they_are_placed() -> void:
	var cases := [
		[100, ""],
		[290, ""],
		[291, "map exceeds width, height or cell budget"],
		[600, "map exceeds width, height or cell budget"],
		[HerdrSnapshot.MAX_WORKSPACES, "input exceeds tab budget"],
	]
	for each: Array in cases:
		var count: int = each[0]
		var refusal: String = each[1]
		var workspaces: Array[Dictionary] = []
		for index in count:
			workspaces.append({"workspace_id": "workspace%04d" % index, "number": index})
		var snapshot := HerdrSnapshot.from_wire({"workspaces": workspaces, "tabs": [], "panes": []})
		_check(snapshot != null, "%d empty workspaces come off the wire" % count)
		if snapshot == null:
			continue
		var zones := OfficeProjection.project(snapshot, PackedStringArray(), "machine")
		_eq(zones.size(), count, "%d: one zone each" % count)
		var start := Time.get_ticks_usec()
		var result := OfficeFloorLayout.plan(MapModel.of_zones("machine", zones), null, _real_rules(25))
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		print("EMPTY_WORKSPACES %d: %.1f ms, %s" % [count, elapsed, result.problems])
		if refusal.is_empty():
			_eq(result.problems, PackedStringArray(), "%d: a valid map" % count)
			_check(result.plan != null and result.plan.zones.size() == count, "%d: every zone placed" % count)
		else:
			_check(result.plan == null, "%d: refused" % count)
			_eq(result.problems, PackedStringArray([refusal]), "%d: by name" % count)
			_check(elapsed < 250.0, "%d: promptly, %.1f ms" % [count, elapsed])


## A lane gap's plants take turns as well as its side tables: piece j is a side
## table when j is odd, else plant_at(j / 2), so a run of five stands a plant, a
## side table, the other plant, a side table and the first plant again (with
## plant_at(j) every plant of a run was the first one). Zone 1, three pods deep
## in lane 0, leaves lane 1 a gap of twelve rows under zone 2.
func test_a_lane_gap_stands_both_plants_between_its_side_tables() -> void:
	var zones: Array[ZoneModel] = [
		_zoned("machine/1", 1, [_room("a", ROW), _room("b", ROW, 1), _room("c", ROW, 2)]),
		_zoned("machine/2", 2, [_room("d", 2)]),
	]
	var plan := _furnished(MapModel.of_zones("machine", zones), 25)
	if plan == null:
		return
	var gaps := OfficeDecorPlanner.lane_gaps(plan, _real_rules(25))
	_eq(gaps.size(), 1, "one gap")
	if gaps.is_empty():
		return
	var pieces := _gap_pieces(plan, gaps[0])
	var kinds: Array[StringName] = []
	for placed in pieces:
		kinds.append(placed.piece)
	print("GAP_RUN lane %d rows %d..%d: %s" % [gaps[0].lane, gaps[0].top, gaps[0].end, kinds])
	var plant := OfficeDecorPlanner.plant_at(_pen().art, 0)
	var other := OfficeDecorPlanner.plant_at(_pen().art, 1)
	_check(plant != other, "the pack has two plants: %s, %s" % [plant, other])
	_eq(
		kinds,
		[plant, ArtContract.PROP_SIDE_TABLE, other, ArtContract.PROP_SIDE_TABLE, plant] as Array[StringName],
		"plant, side table, the other plant, side table, plant"
	)
