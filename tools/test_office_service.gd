extends "res://tools/test_base.gd"
## Pure: the entry band's pantry as the plan places it and the validator
## walks it (OfficeFixturePlanner, OfficeFloorValidation, OfficeWalkGraph), the
## fixture-row barrier every map with desks keeps, pantry or not, and who
## rests where on a map (OfficeRests), with the one ranking the pantry and the
## `N` key share. There is no reception. No office, no scene.

var people: PixelPeople
## Made on first use by _pen().
var pen: OfficeDraw


func _initialize() -> void:
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	run_cases()


func _marker() -> String:
	return "OFFICE SERVICE TESTS"


# --- the entry band's fixtures -------------------------------------------------


## A floor with tables planned with its fixtures, `width` cells wide.
func _serviced(floor_model: ZoneModel, width := 32, previous: FloorPlan = null) -> FloorPlan:
	var rules := _real_rules(width)
	var result := OfficeFloorLayout.plan(
		MapModel.of(floor_model), previous, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "a valid serviced floor: " + "; ".join(result.problems))
	return result.plan


## The entry band is three cells deep: the top wall's drawing clearance, the
## fixture row and the walking lane. A map of one zone of one pod row is
## 2 + 3 + 1 + the pod row's cells deep (the wall, the band, the zone's aisle
## row, the pod row: 6 cells on lane B1's pods, 12 in all); a lobby is still 12,
## and so is nothing smaller. The threshold stays where the first walkable
## centre under the door is, and the first zone starts under the band and its
## aisle row.
func test_the_entry_band_is_three_cells_deep() -> void:
	var rules := _real_rules(20)
	_eq(rules.entry_cells, 3, "the policy's entry band")
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	_eq(plan.entry_cells, Rect2i(1, 2, 11, 3), "under the top wall, between the side walls")
	var pod := OfficeZoneLayout.pod_row_cells()
	_eq(plan.floor_cells.size.y, 2 + 3 + 1 + pod, "one pod row: 2 + 3 + 1 + %d cells" % pod)
	_eq(plan.zones[0].cells.position.y, 6, "the first zone starts under the band and its aisle row")
	# An empty workspace is a zone of one empty pod row now: as deep as one table.
	_eq(_plan(_floor([])).floor_cells.size.y, 2 + 3 + 1 + pod, "an empty workspace is one pod row deep")
	var lobby := OfficeFloorLayout.plan(MapModel.of(OfficeProjection.lobby("machine")), null, _real_rules()).plan
	_eq(lobby.floor_cells.size.y, 12, "a lobby stays 12 deep")
	var graph := _graph_of(plan, rules)
	_eq(graph.threshold, Vector2(OfficeShell.door(plan).x, 112), "the threshold is where it was")
	_eq([graph.fixture_row, graph.walking_lane], [112.0, 144.0], "the fixture row and the walking lane under it")
	for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.end.x):
		_check(graph.walkable(Vector2i(x, 4)), "the walking lane is open at column %d" % x)


## Where the pantry stands is a pure function of the plan: at the band's left
## end, its footprint ending short of the fixture row, its spots on that row
## from the left wall on, a pitch apart, every spot's approach straight below it
## on the walking lane, the last FIXTURE_GAP at least short of the main corridor.
## The same plan twice is the same; a zone growing leaves it where it is;
## widening the map moves the lift door with the main corridor and leaves the
## pantry where it was. It is the only fixture: there is no reception.
func test_fixtures_stand_where_the_plan_puts_them() -> void:
	var model := _floor([_room("a", 4), _room("b", 2, 1)])
	var plan := _serviced(model, 20)
	var pantry := plan.pantry
	_check(pantry != null, "a 13-cell map has a pantry")
	if pantry == null:
		return
	_eq(plan.fixtures().size(), 1, "and no other fixture")
	var corridor := plan.main_corridor_cells.position.x * 32.0
	_check(pantry.footprint.end.y <= 108.0, "its footprint ends short of the fixture row")
	_eq(pantry.footprint.position.x, 32.0, "the pantry stands at the band's left end")
	for index in pantry.spots.size():
		var spot := pantry.spots[index]
		_eq(spot, Vector2(32.0 + OfficeShell.SPOT_PITCH * (index + 0.5), 112.0), "spot %d on the fixture row" % index)
		_eq(pantry.approaches[index], Vector2(spot.x, 144.0), "spot %d stepped up to from the lane" % index)
	var last := pantry.spots[pantry.spots.size() - 1].x + OfficeShell.SPOT_PITCH / 2.0
	_check(
		corridor - last >= OfficeShell.FIXTURE_GAP, "the last spot keeps off the main corridor: %s" % (corridor - last)
	)
	_eq(_serviced(model, 20).geometry_signature(), plan.geometry_signature(), "the same plan twice")
	# Ten panes: a five-desk pod, 6 cells, more than the 3 the pod row has left
	# beside a (3 cells) and b (2), and no wider than the zone's 8 inner cells.
	model.rooms.append(_room("c", 10, 2))
	var grown := _serviced(model, 20, plan)
	_check(grown.zones[0].rows.size() > plan.zones[0].rows.size(), "a new pod row")
	_eq(grown.pantry.geometry_signature(), pantry.geometry_signature(), "the pantry stays as it was")
	# Wide enough to widen the map: a table of 30 panes, 16 columns, 35 cells.
	var wide := _floor([_room("a", 4), _room("b", 30, 1)])
	var narrow := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 20)
	var widened := _serviced(wide, 20, narrow)
	_check(widened.lanes > narrow.lanes, "the map widened by lanes: %d -> %d" % [narrow.lanes, widened.lanes])
	var moved := widened.main_corridor_cells.position.x - narrow.main_corridor_cells.position.x
	_eq(moved, 10 * (widened.lanes - narrow.lanes), "the main corridor moves ten cells a lane")
	_eq(OfficeShell.door(widened) - OfficeShell.door(narrow), Vector2(moved * 32, 0), "and the lift door with it")
	_eq(widened.pantry.position, narrow.pantry.position, "the pantry stays at the left end")
	_eq(widened.pantry.spots.slice(0, narrow.pantry.spots.size()), narrow.pantry.spots, "its spots where they were")


## No pantry where there are no desks: the lobby and an empty workspace. No
## plan has a reception.
func test_no_fixtures_without_tables() -> void:
	var cache := FloorPlanCache.new()
	var lobby := cache.prepare(MapModel.of(OfficeProjection.lobby("machine")), _pen(), 640.0)
	_eq(lobby.fixtures().size(), 0, "the lobby has none")
	var empty := cache.prepare(MapModel.of(_floor([])), _pen(), 640.0)
	_eq(empty.fixtures().size(), 0, "nor has an empty workspace")
	var tables := cache.prepare(MapModel.of(_floor([_room("a", 2)])), _pen(), 640.0)
	_check(tables.pantry != null, "a map with a table has a pantry")
	for plan: FloorPlan in [lobby, empty, tables]:
		_check(not "reception" in plan, "a plan has no reception")
		for fixture in plan.fixtures():
			_eq([fixture.key, fixture.piece], ["pantry", ArtContract.PROP_PANTRY], "its one fixture is the pantry")


## How many the pantry holds, from the narrowest map to 60 cells asked for:
## its spots from the left wall to FIXTURE_GAP short of the main corridor, 48
## apart, at most MAX_PANTRY. Printed for the record.
func test_fixture_capacities_by_floor_width() -> void:
	var expected := {11: [13, 5], 20: [13, 5], 32: [23, 12], 60: [53, 24]}
	for width: int in expected:
		var plan := _serviced(_floor([_room("a", 2)]), width)
		var held := [plan.floor_cells.size.x, plan.pantry.spots.size() if plan.pantry != null else 0]
		_eq(held, expected[width], "%d cells asked: the map's width and the pantry" % width)
		print(
			(
				"FIXTURE_CAPACITY %d cells asked, %d wide: pantry %d, pitch %d"
				% [width, held[0], held[1], OfficeShell.SPOT_PITCH]
			)
		)


## A band too narrow for the pantry's counter and one spot has no pantry, and
## a map with desks keeps its fixture-row barrier all the same: no node on the
## fixture row is walked to left of the main corridor, and the walking lane
## stays. On hand-made plans: no real map is so narrow.
func test_a_narrow_band_drops_the_pantry_and_keeps_the_barrier() -> void:
	var planner := OfficeFixturePlanner.new(_pen())
	var cases := {3: 0, 4: 1, 5: 2, 6: 3}
	for corridor: int in cases:
		var plan := FloorPlan.new()
		var desk := DeskPlacement.new()
		desk.tab_key = "a"
		desk.capacity = 2
		desk.measure = OfficeTable.measure(2)
		desk.origin = Vector2(64, 480)
		plan.desks.append(desk)
		plan.floor_cells = Rect2i(0, 0, corridor + 3, 18)
		plan.entry_cells = Rect2i(1, 2, corridor + 1, 3)
		plan.main_corridor_cells = Rect2i(corridor, 2, 2, 16)
		planner.furnish(plan)
		var held := plan.pantry.spots.size() if plan.pantry != null else 0
		_eq(held, cases[corridor], "a corridor at column %d: the pantry" % corridor)
		var graph := OfficeWalkGraph.build(plan, PixelPerson.footprint(), PixelPerson.drawing_rect(people))
		_eq([graph.fixture_row, graph.walking_lane], [112.0, 144.0], "column %d: the rows stand" % corridor)
		for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.position.x):
			_check(not graph.walkable(Vector2i(x, 3)), "column %d: the fixture row's node %d is barred" % [corridor, x])


## The validator walks the pantry as it walks the tables: a counter reaching
## over a spot's leg blocks that leg, and one reaching over the walking lane
## leaves the spots behind it unreached. Each is a problem of its own.
func test_the_validator_walks_to_the_fixtures() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	_eq(OfficeFloorLayout.validate(plan, rules), PackedStringArray(), "the serviced floor validates")
	var pantry := plan.pantry
	var stands := pantry.footprint
	# Reaching down over the first spot's leg, to the fixture row but not the lane.
	pantry.footprint = Rect2(pantry.spots[0].x - 2, stands.position.y, 4, 20)
	var problems := OfficeFloorLayout.validate(plan, rules)
	_check(problems.has("blocked pantry leg: 0"), "a counter over the spot's leg blocks it: %s" % [problems])
	_check(not problems.has("unreachable pantry approach: 0"), "though its approach is reached")
	# Reaching down over the walking lane in front of every pantry spot.
	pantry.footprint = Rect2(
		stands.position, Vector2(pantry.spots[pantry.spots.size() - 1].x + 30 - stands.position.x, 60)
	)
	problems = OfficeFloorLayout.validate(plan, rules)
	_check(
		problems.has("unreachable pantry approach: 0"),
		"a counter over the lane leaves its spots unreached: %s" % [problems]
	)
	pantry.footprint = stands
	_eq(OfficeFloorLayout.validate(plan, rules), PackedStringArray(), "and all is well again")


## Nothing runs along the fixture row: no node on it is walkable left of the
## main corridor, and no edge joins two of its centres. Only a spot's own leg
## steps up into it, only along itself; never from spot to spot.
func test_nothing_runs_along_the_fixture_row() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	var graph := _graph_of(plan, rules)
	for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.position.x):
		_check(not graph.walkable(Vector2i(x, 3)), "the fixture row's node at column %d is not walked to" % x)
		_check(not graph.linked(Vector2i(x, 3), OfficeWalkGraph.RIGHT), "nor walked along from it")
	var spots := plan.pantry.spots
	for index in spots.size():
		var leg := OfficeWalkGraph.leg_to_fixture(plan.pantry.approaches[index], spots[index])
		_check(graph.clear_route(leg), "pantry %d: its leg steps up" % index)
		var past := spots[index] + Vector2(0, -8)
		_check(not graph.clear(plan.pantry.approaches[index], past), "pantry %d: only along itself" % index)
	_check(not graph.clear(spots[0], spots[1]), "nor from spot to spot in the pantry")
	_check(
		not graph.clear(spots[0] + Vector2(-8, 0), spots[0] + Vector2(-8, 32)), "nor into the row anywhere but a leg"
	)


## The furnished map is validated once; what fails is left out, never a desk:
## the furniture first, then the pantry, at most three validations. A broken
## pantry takes all three: with everything, without the furniture (the pantry
## still breaks it), without both.
func test_a_fixture_that_fails_is_left_out() -> void:
	var rules := _real_rules(32)
	var model := _floor([_room("a", 4), _room("b", 2, 1)])
	var before := OfficeFloorValidation.validations
	var fine := OfficeFloorLayout.plan(
		MapModel.of(model), null, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(OfficeFloorValidation.validations - before, 1, "one validation, the pantry and furniture included")
	_check(fine.plan != null and fine.plan.pantry != null and not fine.plan.decorations.is_empty(), "all of them")
	var planner := BreakingFixtures.new(_pen())
	before = OfficeFloorValidation.validations
	var result := OfficeFloorLayout.plan(MapModel.of(model), null, rules, OfficeDecorPlanner.new(_pen()), planner)
	var spent := OfficeFloorValidation.validations - before
	_eq(result.problems, PackedStringArray(), "a broken pantry leaves the floor valid")
	if result.plan == null:
		return
	_eq(result.plan.desks.size(), 2, "with its desks")
	_eq(result.plan.pantry, null, "without the pantry")
	_eq(spent, 3, "in three validations")
	_check(result.plan.decorations.is_empty(), "the furniture went first")


## A pantry whose counter reaches across the walking lane (see
## test_a_fixture_that_fails_is_left_out).
class BreakingFixtures:
	extends OfficeFixturePlanner

	func furnish(next: FloorPlan) -> void:
		super.furnish(next)
		if next.pantry != null:
			var stands := next.pantry.footprint
			next.pantry.footprint = Rect2(stands.position.x, stands.position.y, stands.size.x, 60)


# --- who rests where (OfficeRests), pure ---------------------------------------


## A pane with an agent in `state` at `since` (-1: unknown), `key` its pane key.
func _agent(key: String, state: String, since := -1.0, starting := false) -> PaneModel:
	var pane := _pane(key)
	pane.provider = "claude"
	pane.state = state
	pane.state_since = since
	pane.starting = starting
	return pane


## One ranking for the pantry's spots and `N`: an unknown start first, as
## having waited longest, then the earliest start; ties, and the unknown among
## themselves, in projection order. Forty agents that went idle in the same
## snapshot rank in projection order.
func test_whoever_waited_longest_goes_first() -> void:
	var panes: Array[PaneModel] = [
		_agent("a", "idle", 300.0),
		_agent("b", "idle"),
		_agent("c", "idle", 100.0),
		_agent("d", "idle", 200.0),
		_agent("e", "idle"),
		_agent("f", "idle", 100.0)
	]
	var order := OfficeProjection.wait_order(panes).map(func(pane: PaneModel) -> String: return pane.key)
	_eq(order, ["b", "e", "c", "f", "d", "a"], "unknown first, then the earliest; ties in projection order")
	var tied: Array[PaneModel] = []
	for index in 40:
		tied.append(_agent("t%02d" % (39 - index), "idle", 500.0))
	var same := OfficeProjection.wait_order(tied).map(func(pane: PaneModel) -> String: return pane.key)
	_eq(same, tied.map(func(pane: PaneModel) -> String: return pane.key), "forty at once stand as projected")


## The places a floor's workers rest at, by state: the pantry for idle and the
## seat for everything else, working, starting (whatever its status), unknown,
## done and blocked; a shell rests nowhere.
func test_every_state_has_its_place() -> void:
	var room := _room("a")
	room.panes.assign(
		[
			_agent("working", "working"),
			_agent("starting", "blocked", -1.0, true),
			_agent("unknown", "unknown"),
			_agent("done", "done"),
			_agent("blocked", "blocked"),
			_agent("idle", "idle"),
			_agent("launching-done", "done", -1.0, true),
			_pane("shell")
		]
	)
	var plan := _serviced(_floor([room]), 20)
	var service := OfficeRests.assign(plan, MapModel.of(_floor([room])))
	var places := {}
	for key: String in service.places:
		places[key] = [service.places[key].rest, service.places[key].index]
	_eq(
		places,
		{
			"working": [OfficeRests.Rest.SEAT, -1],
			"starting": [OfficeRests.Rest.SEAT, -1],
			"unknown": [OfficeRests.Rest.SEAT, -1],
			"done": [OfficeRests.Rest.SEAT, -1],
			"blocked": [OfficeRests.Rest.SEAT, -1],
			"idle": [OfficeRests.Rest.PANTRY, service.places["idle"].index],
			"launching-done": [OfficeRests.Rest.SEAT, -1],
		},
		"each where its state rests it; the shell nowhere"
	)
	_check(service.places["idle"].index >= 0, "the idle one has a spot")
	_eq(OfficeRests.rest_of(ArtContract.STATE_IDLE, true), OfficeRests.Rest.SEAT, "an idle pane still launching sits")


## Every idle agent has a pantry spot of their own (a hash of the pane key);
## whoever finds it taken, in the waiting order, takes the next free one; a
## full pantry seats the rest. A newcomer, whose start is known and late, never
## moves anyone already there. Planned 60 cells wide (five lanes, the pantry's
## full 24 spots), so the crowd's table grows within the map's lanes and the
## pantry stays the same: a map widened for it would stand more spots.
func test_the_pantry_keeps_everyone_on_their_spot() -> void:
	var room := _room("a")
	for index in 3:
		room.panes.append(_agent("i%d" % index, "idle"))
	var plan := _serviced(_floor([room]), 60)
	var spots := plan.pantry.spots.size()
	var first := OfficeRests.assign(plan, MapModel.of(_floor([room])))
	var taken := {}
	for index in 3:
		var place := first.places["i%d" % index]
		_eq(place.rest, OfficeRests.Rest.PANTRY, "i%d rests in the pantry" % index)
		_check(not taken.has(place.index), "i%d on a spot of their own" % index)
		taken[place.index] = true
	var alone := OfficeRests.assign(plan, MapModel.of(_floor([_room_of([room.panes[1]])])))
	_eq(alone.places["i1"].index, posmod("i1".hash(), spots), "alone, i1 takes its own spot, its key's hash")
	var without := OfficeRests.assign(plan, MapModel.of(_floor([_room_of([room.panes[1], room.panes[2]])])))
	for index: int in [1, 2]:
		var kept: int = first.places["i%d" % index].index
		_eq(without.places["i%d" % index].index, kept, "i0 leaves: i%d keeps its spot" % index)
	room.panes.append(_agent("late", "idle", 999.0))
	var replanned := _serviced(_floor([room]), 60, plan)
	_eq(replanned.pantry.geometry_signature(), plan.pantry.geometry_signature(), "the same pantry")
	var second := OfficeRests.assign(replanned, MapModel.of(_floor([room])))
	for index in 3:
		_eq(second.places["i%d" % index].index, first.places["i%d" % index].index, "i%d stays put" % index)
	for index in spots:
		room.panes.append(_agent("crowd%d" % index, "idle", 1000.0 + index))
	var crowded := _serviced(_floor([room]), 60, replanned)
	_eq(crowded.pantry.geometry_signature(), plan.pantry.geometry_signature(), "still the same pantry")
	var full := OfficeRests.assign(crowded, MapModel.of(_floor([room])))
	var resting := 0
	var seated := 0
	for key: String in full.places:
		resting += 1 if full.places[key].rest == OfficeRests.Rest.PANTRY else 0
		seated += 1 if full.places[key].rest == OfficeRests.Rest.SEAT else 0
	_eq([resting, seated], [spots, 4], "a full pantry of %d seats the last four" % spots)
	_eq(full.places["late"].rest, OfficeRests.Rest.PANTRY, "whoever came earlier kept their spot")


## The `N` key visits a floor's blocked agents longest-waiting first (the
## pantry's order), every one of them at their seat, then its UNREAD in the same
## waiting order.
func test_n_follows_the_wait_order() -> void:
	var room := _room("a")
	var blocked: Array[PaneModel] = []
	for index in 8:
		var agent := _agent("b%d" % index, "blocked", -1.0 if index % 3 == 0 else 50.0 * (8 - index))
		room.panes.append(agent)
		blocked.append(agent)
	room.panes.append(_agent("d0", "done", 20.0))
	room.panes.append(_agent("d1", "done"))
	var floor_model := _floor([room])
	var plan := _serviced(floor_model, 20)
	var service := OfficeRests.assign(plan, MapModel.of(floor_model))
	var building := BuildingModel.new()
	building.zones.append(floor_model)
	var buildings: Array[BuildingModel] = [building]
	var order := OfficeProjection.attention_queue(buildings)
	var waited := OfficeProjection.wait_order(blocked).map(func(pane: PaneModel) -> String: return pane.key)
	_eq(order.slice(0, 8), waited, "N walks the blocked longest-waiting first")
	_eq(waited.slice(0, 3), ["b0", "b3", "b6"], "the unknown starts first")
	for key: String in order.slice(0, 8):
		_eq(service.places[key].rest, OfficeRests.Rest.SEAT, key + ": at the seat")
	_eq(order.slice(8), ["d1", "d0"], "then UNREAD, the unknown start first")


## A map without the entry band's pantry (a band too narrow for it): everyone
## sits, the idle too, and nobody has a spot.
func test_blocked_and_done_sit_on_a_floor_without_fixtures() -> void:
	var room := _room("a")
	for state: String in ["working", "blocked", "done", "idle", "unknown"]:
		room.panes.append(_agent(state, state))
	var plan := _serviced(_floor([room]), 20)
	plan.pantry = null
	var service := OfficeRests.assign(plan, MapModel.of(_floor([room])))
	_eq(service.places.size(), 5, "every agent has a place")
	for key: String in service.places:
		_eq([service.places[key].rest, service.places[key].index], [OfficeRests.Rest.SEAT, -1], key + ": the seat")


# --- the barrier and the walking lane, pantry or not --------------------------


## Every map with desks keeps the fixture row a barrier from the left wall to
## the main corridor, and the walking lane under it, whether or not a pantry
## stands there: the threshold is at (the door's column, 112), the fixture row
## at 112 and the walking lane at 144, no node on the fixture row left of the
## main corridor is walked to, and no route runs along it. A map without desks
## (an empty workspace, a lobby) has neither: nobody walks there.
func test_the_barrier_and_the_lane_stand_with_or_without_a_pantry() -> void:
	var rules := _real_rules(32)
	var served := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 32)
	var bare := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 32)
	bare.pantry = null
	for plan: FloorPlan in [served, bare]:
		var what := "with a pantry" if plan.pantry != null else "without one"
		var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
		_eq(graph.threshold, Vector2(OfficeShell.door(plan).x, 112), what + ": the threshold at the door's column")
		_eq([graph.fixture_row, graph.walking_lane], [112.0, 144.0], what + ": the fixture row and the walking lane")
		var barriers := graph.obstacles.filter(
			func(each: OfficeWalkGraph.Obstacle) -> bool:
				return each.kind == OfficeWalkGraph.Kind.FIXTURE and each.rect.size.y == 32.0
		)
		_eq(barriers.size(), 1, what + ": one fixture-row barrier")
		for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.position.x):
			_check(not graph.walkable(Vector2i(x, 3)), "%s: the fixture row at column %d is barred" % [what, x])
			_check(graph.walkable(Vector2i(x, 4)), "%s: the walking lane at column %d is open" % [what, x])
		var along := graph.route_between(
			Vector2i(1, 4),
			[Vector2i(plan.main_corridor_cells.position.x - 1, 4)] as Array[Vector2i],
			PackedFloat32Array([0.0]),
			PackedInt32Array([-1]),
			100000,
			1000
		)
		for point in along.points:
			_check(point.y != 112.0, "%s: a walk along the band never runs on the fixture row: %s" % [what, point])
	var empty := _plan(_floor([]))
	var empty_graph := OfficeWalkGraph.build(empty, rules.actor_footprint, rules.actor_draw_rect)
	_eq([empty_graph.fixture_row, empty_graph.walking_lane], [INF, INF], "a map without desks has no walked rows")
	_eq(empty.fixtures().size(), 0, "and no pantry")


## From every approach of every table, with the pantry and without, the door's
## field leads down onto the walking lane (to_lane()) and back up from it
## (from_lane()): every way in from the door crosses the lane at the door's
## column, which the walkers' lane routes rely on. On a map of several zones in
## both lanes, partitions and all.
func test_to_lane_reaches_the_walking_lane_from_every_approach() -> void:
	var rules := _real_rules(32)
	var zones: Array[ZoneModel] = [
		_zone("machine/1", 1, [_room("a", 4), _room("b", 2, 1), _room("c", 2, 2)]),
		_zone("machine/2", 2, [_room("d", 6)]),
		_zone("machine/3", 3, [_room("e", 2), _room("f", 8, 1)]),
	]
	var result := OfficeFloorLayout.plan(
		MapModel.of_zones("machine", zones),
		null,
		rules,
		OfficeDecorPlanner.new(_pen()),
		OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "a valid map of three zones")
	if result.plan == null:
		return
	var plan := result.plan
	for with_pantry: bool in [true, false]:
		if not with_pantry:
			plan.pantry = null
		var graph := OfficeWalkGraph.build(plan, rules.actor_footprint, rules.actor_draw_rect)
		var count := 0
		for placed in plan.desks:
			for column in placed.capacity:
				for side: String in OfficeTable.SIDES:
					var cell := OfficeWalkGraph.cell_of(placed.origin + placed.measure.approach_position(column, side))
					var named := (
						"%s %s %d %s" % ["pantry" if with_pantry else "no pantry", placed.tab_key, column, side]
					)
					var down := graph.to_lane(cell)
					_check(not down.is_empty() and down[down.size() - 1].y == 144.0, named + ": to the walking lane")
					var up := graph.from_lane(cell)
					_check(not up.is_empty() and up[0].y == 144.0, named + ": from the walking lane")
					count += 1
		_check(count >= 30, "every approach: %d" % count)


## At the shipped plan width (820 units, 25 cells: two lanes, a map 23 cells
## wide) the pantry holds twelve: from the left wall at 32 to 16 short of the
## main corridor at 640, 48 apart.
func test_twelve_pantry_spots_at_twenty_three_cells() -> void:
	var plan := _serviced(_floor([_room("a", 2)]), 25)
	_eq([plan.lanes, plan.floor_cells.size.x, plan.main_corridor_cells.position.x], [2, 23, 20], "two lanes, 23 cells")
	_eq(plan.pantry.spots.size(), 12, "twelve spots")
	_eq(plan.pantry.spots[11].x + OfficeShell.SPOT_PITCH / 2.0, 608.0, "the last ends at 608")
	_check(640.0 - 608.0 >= OfficeShell.FIXTURE_GAP, "FIXTURE_GAP short of the main corridor")


# --- helpers --------------------------------------------------------------------


## A room "a" holding exactly `panes`, as a plan seats them.
func _room_of(panes: Array[PaneModel]) -> RoomModel:
	var room := _room("a")
	room.panes.assign(panes)
	return room


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


## A workspace `key` numbered `number` with `rooms`: one zone of a map.
func _zone(key: String, number: int, rooms: Array[RoomModel]) -> ZoneModel:
	var zone := _floor(rooms)
	zone.key = key
	zone.number = number
	return zone


func _plan(floor_model: ZoneModel) -> FloorPlan:
	var rules := _real_rules()
	var result := OfficeFloorLayout.plan(MapModel.of(floor_model), null, rules)
	_eq(result.problems, PackedStringArray(), "valid plan: " + "; ".join(result.problems))
	return result.plan


## The shipped pack's pen, made once: the planners measure its props with it.
func _pen() -> OfficeDraw:
	if pen == null:
		pen = OfficeDraw.new(ArtPack.from_manifest("res://assets/daylight/manifest.json"))
	return pen


func _real_rules(width := 32) -> FloorLayoutPolicy:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = width
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	return rules


func _graph_of(plan: FloorPlan, rules: FloorLayoutPolicy) -> OfficeWalkGraph:
	return OfficeWalkGraph.of(plan, rules.actor_footprint, rules.actor_draw_rect)
