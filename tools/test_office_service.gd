extends "res://tools/test_base.gd"
## Pure: the entry band's fixtures as the plan places them and the
## validator walks them (OfficeFixturePlanner, OfficeFloorValidation,
## OfficeWalkGraph), and who rests where on a floor (OfficeRests), with the one
## ranking the pantry and the `N` key share. The reception's queue slots are
## still planned and walked (so no floor is laid out differently), but
## nobody rests there. No office, no scene.

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
		floor_model, previous, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(result.problems, PackedStringArray(), "a valid serviced floor: " + "; ".join(result.problems))
	return result.plan


## The entry band is three cells deep: the top wall's drawing clearance, the
## fixture row and the walking lane. A floor with one row of pods is 15 cells
## deep (it was 18 with the long tables' 13-cell rows), a lobby or an empty
## workspace still 12; the threshold stays where the
## first walkable centre under the door is, and the first row wall starts under
## the band.
func test_the_entry_band_is_three_cells_deep() -> void:
	var rules := _real_rules(20)
	_eq(rules.entry_cells, 3, "the policy's entry band")
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	_eq(plan.entry_cells, Rect2i(1, 2, 18, 3), "under the top wall, between the side walls")
	_eq(plan.floor_cells.size.y, 15, "one row of pods: 2 + 3 + 10 cells")
	_eq(plan.rows[0].wall_cells.position.y, 5, "the first row wall starts under the band")
	_eq(_plan(_floor([])).floor_cells.size.y, 12, "an empty workspace stays 12 deep")
	var graph := _graph_of(plan, rules)
	_eq(graph.threshold, Vector2(OfficeShell.door(plan).x, 112), "the threshold is where it was")
	_eq([graph.fixture_row, graph.walking_lane], [112.0, 144.0], "the fixture row and the walking lane under it")
	for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.end.x):
		_check(graph.walkable(Vector2i(x, 4)), "the walking lane is open at column %d" % x)


## Where the fixtures stand is a pure function of the plan: the reception's
## right edge DOOR_CLEARANCE left of the main corridor, its footprint ending
## short of the fixture row, its queue on that row leftwards from it a pitch
## apart, head first, every slot's approach straight below it on the walking
## lane; the pantry at the band's left end with its spots rightwards; FIXTURE_GAP
## at least between the two. The same plan twice is the same; growing a row
## leaves them where they are; widening the floor moves the reception and its
## queue with the main corridor and leaves the pantry where it was.
func test_fixtures_stand_where_the_plan_puts_them() -> void:
	var model := _floor([_room("a", 4), _room("b", 2, 1)])
	var plan := _serviced(model, 20)
	var reception := plan.reception
	var pantry := plan.pantry
	_check(reception != null and pantry != null, "a 20-cell floor has both")
	if reception == null or pantry == null:
		return
	var corridor := plan.main_corridor_cells.position.x * 32.0
	_eq(reception.footprint.end.x, corridor - OfficeShell.DOOR_CLEARANCE, "the reception keeps clear of the door")
	_check(reception.footprint.end.y <= 108.0, "its footprint ends short of the fixture row")
	_check(pantry.footprint.end.y <= 108.0, "and so does the pantry's")
	_eq(pantry.footprint.position.x, 32.0, "the pantry stands at the band's left end")
	_eq(
		reception.spots[0].x + OfficeShell.SPOT_PITCH / 2.0,
		reception.footprint.position.x,
		"the head is at the counter"
	)
	for fixture in plan.fixtures():
		for index in fixture.spots.size():
			var spot := fixture.spots[index]
			_eq(spot.y, 112.0, "%s %d on the fixture row" % [fixture.key, index])
			_eq(
				fixture.approaches[index],
				Vector2(spot.x, 144.0),
				"%s %d stepped up to from the lane" % [fixture.key, index]
			)
			if index > 0:
				var step := spot.x - fixture.spots[index - 1].x
				_eq(absf(step), OfficeShell.SPOT_PITCH, "%s %d a pitch from the last" % [fixture.key, index])
	var tail := reception.spots[reception.spots.size() - 1].x - OfficeShell.SPOT_PITCH / 2.0
	var last := pantry.spots[pantry.spots.size() - 1].x + OfficeShell.SPOT_PITCH / 2.0
	_check(tail - last >= OfficeShell.FIXTURE_GAP, "the queue and the pantry stand apart: %s" % (tail - last))
	_eq(_serviced(model, 20).geometry_signature(), plan.geometry_signature(), "the same plan twice")
	# Twenty panes: a ten-desk pod, 11 cells, more than the 10 the row has left.
	model.rooms.append(_room("c", 20, 2))
	var grown := _serviced(model, 20, plan)
	_check(grown.rows.size() > plan.rows.size(), "a new row")
	for fixture in plan.fixtures():
		var kept := grown.reception if fixture.key == "reception" else grown.pantry
		_eq(kept.geometry_signature(), fixture.geometry_signature(), "%s stays as it was" % fixture.key)
	# Wide enough to widen the floor: a table of 30 panes.
	var wide := _floor([_room("a", 4), _room("b", 30, 1)])
	var narrow := _serviced(_floor([_room("a", 4), _room("b", 2, 1)]), 20)
	var widened := _serviced(wide, 20, narrow)
	_check(widened.floor_cells.size.x > narrow.floor_cells.size.x, "the floor widened")
	var moved := widened.main_corridor_cells.position.x - narrow.main_corridor_cells.position.x
	_eq(
		widened.reception.position - narrow.reception.position,
		Vector2(moved * 32, 0),
		"the reception follows the corridor"
	)
	_eq(widened.reception.spots[0] - narrow.reception.spots[0], Vector2(moved * 32, 0), "and so does its queue's head")
	_eq(widened.pantry.position, narrow.pantry.position, "the pantry stays at the left end")


## No fixtures where there are no tables: the lobby and an empty workspace.
func test_no_fixtures_without_tables() -> void:
	var cache := FloorPlanCache.new()
	var lobby := cache.prepare(MapModel.of(OfficeProjection.lobby("machine")), _pen(), 640.0)
	_eq([lobby.reception, lobby.pantry], [null, null], "the lobby has none")
	var empty := cache.prepare(MapModel.of(_floor([])), _pen(), 640.0)
	_eq([empty.reception, empty.pantry], [null, null], "nor has an empty workspace")
	var tables := cache.prepare(MapModel.of(_floor([_room("a", 2)])), _pen(), 640.0)
	_check(tables.reception != null and tables.pantry != null, "a floor with a table has both")


## How many the queue and the pantry hold, from the narrowest floor to 60 cells
## wide, as the planner shares the row between them. Printed for the record.
func test_fixture_capacities_by_floor_width() -> void:
	var expected := {11: [2, 1], 20: [5, 4], 32: [9, 8], 60: [18, 17]}
	for width: int in expected:
		var plan := _serviced(_floor([_room("a", 2)]), width)
		_eq(plan.floor_cells.size.x, width, "%d cells wide" % width)
		var held := [plan.reception.spots.size(), plan.pantry.spots.size() if plan.pantry != null else 0]
		_eq(held, expected[width], "%d cells: queue and pantry" % width)
		print(
			(
				"FIXTURE_CAPACITY %d cells: queue %d, pantry %d, pitch %d"
				% [width, held[0], held[1], OfficeShell.SPOT_PITCH]
			)
		)


## A band too narrow for the counter, the door's clearance and MIN_QUEUE slots
## has neither fixture; one too narrow for the pantry's counter and a spot as
## well has only the reception. On hand-made plans: no shipped width is so narrow.
func test_a_narrow_band_drops_the_pantry_then_both() -> void:
	var planner := OfficeFixturePlanner.new(_pen())
	var cases := {5: [0, 0], 6: [2, 0], 7: [2, 0], 8: [2, 1]}
	for corridor: int in cases:
		var plan := FloorPlan.new()
		plan.rows.append(RowPlan.new())
		plan.entry_cells = Rect2i(1, 2, corridor - 1, 3)
		plan.main_corridor_cells = Rect2i(corridor, 2, 2, 16)
		planner.furnish(plan)
		var held := [
			plan.reception.spots.size() if plan.reception != null else 0,
			plan.pantry.spots.size() if plan.pantry != null else 0
		]
		_eq(held, cases[corridor], "a corridor at column %d: queue and pantry" % corridor)
		if plan.reception != null:
			_check(plan.reception.spots.size() >= OfficeShell.MIN_QUEUE, "never fewer than MIN_QUEUE slots")


## The validator walks the fixtures as it walks the tables: a counter reaching
## over a slot's leg blocks that leg, and one reaching over the walking lane
## leaves the spots behind it unreached. Each is a problem of its own.
func test_the_validator_walks_to_the_fixtures() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	_eq(OfficeFloorLayout.validate(plan, rules), PackedStringArray(), "the serviced floor validates")
	var reception := plan.reception
	var counter := reception.footprint
	# Reaching left over the head's leg, down to the fixture row but not the lane.
	reception.footprint = Rect2(
		reception.spots[0].x - 2, counter.position.y, counter.end.x - reception.spots[0].x + 2, 20
	)
	var problems := OfficeFloorLayout.validate(plan, rules)
	_check(problems.has("blocked queue leg: 0"), "a counter over the head's leg blocks it: %s" % [problems])
	_check(not problems.has("unreachable queue approach: 0"), "though its approach is reached")
	reception.footprint = counter
	var pantry := plan.pantry
	var stands := pantry.footprint
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
## steps up into it, only along itself, and a queue shifts along its step legs,
## end to end; never from the queue to the pantry, or from spot to spot in it.
func test_nothing_runs_along_the_fixture_row() -> void:
	var rules := _real_rules(20)
	var plan := _serviced(_floor([_room("a", 2)]), 20)
	var graph := _graph_of(plan, rules)
	for x in range(plan.entry_cells.position.x, plan.main_corridor_cells.position.x):
		_check(not graph.walkable(Vector2i(x, 3)), "the fixture row's node at column %d is not walked to" % x)
		_check(not graph.linked(Vector2i(x, 3), OfficeWalkGraph.RIGHT), "nor walked along from it")
	var slots := plan.reception.spots
	var spots := plan.pantry.spots
	for fixture in plan.fixtures():
		for index in fixture.spots.size():
			var leg := OfficeWalkGraph.leg_to_fixture(fixture.approaches[index], fixture.spots[index])
			_check(graph.clear_route(leg), "%s %d: its leg steps up" % [fixture.key, index])
			var past := fixture.spots[index] + Vector2(0, -8)
			_check(not graph.clear(fixture.approaches[index], past), "%s %d: only along itself" % [fixture.key, index])
	for index in range(1, slots.size()):
		_check(graph.clear(slots[index], slots[index - 1]), "the queue steps from slot %d to %d" % [index, index - 1])
	_check(graph.clear(slots[slots.size() - 1], slots[0]), "and moves up several at once along them")
	_check(not graph.clear(slots[slots.size() - 1], spots[spots.size() - 1]), "never from the queue to the pantry")
	if spots.size() > 1:
		_check(not graph.clear(spots[0], spots[1]), "nor from spot to spot in the pantry")
	_check(
		not graph.clear(slots[0] + Vector2(-8, 0), slots[0] + Vector2(-8, 32)), "nor into the row anywhere but a leg"
	)


## A fixture that fails the validation is left out, never a desk: the pantry
## first, then the reception, at most three validations for a floor with
## furniture. A floor that validates at once is validated once, fixtures and
## furniture included.
func test_a_fixture_that_fails_is_left_out() -> void:
	var rules := _real_rules(20)
	var model := _floor([_room("a", 4), _room("b", 2, 1)])
	var before := OfficeFloorValidation.validations
	var fine := OfficeFloorLayout.plan(
		model, null, rules, OfficeDecorPlanner.new(_pen()), OfficeFixturePlanner.new(_pen())
	)
	_eq(OfficeFloorValidation.validations - before, 1, "one validation, fixtures and furniture included")
	_check(fine.plan != null and fine.plan.pantry != null and not fine.plan.decorations.is_empty(), "all of them")
	for breaking: String in ["pantry", "reception"]:
		var planner := BreakingFixtures.new(_pen())
		planner.breaking = breaking
		before = OfficeFloorValidation.validations
		var result := OfficeFloorLayout.plan(model, null, rules, OfficeDecorPlanner.new(_pen()), planner)
		var spent := OfficeFloorValidation.validations - before
		_eq(result.problems, PackedStringArray(), "a broken %s leaves the floor valid" % breaking)
		if result.plan == null:
			continue
		_eq(result.plan.desks.size(), 2, "with its desks")
		_eq(result.plan.pantry, null, "without the pantry (broken %s)" % breaking)
		_eq(result.plan.reception != null, breaking == "pantry", "the reception kept only when the pantry broke")
		_eq(spent, 3, "in three validations (broken %s)" % breaking)
		_check(result.plan.decorations.is_empty(), "the furniture went first")


## Fixtures that close a walk: a pantry or a reception whose counter reaches
## across the walking lane (see test_a_fixture_that_fails_is_left_out).
class BreakingFixtures:
	extends OfficeFixturePlanner
	var breaking := ""

	func furnish(next: FloorPlan) -> void:
		super.furnish(next)
		var fixture := next.pantry if breaking == "pantry" else next.reception
		if fixture != null:
			var stands := fixture.footprint
			fixture.footprint = Rect2(stands.position.x, stands.position.y, stands.size.x, 60)


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
## moves anyone already there.
func test_the_pantry_keeps_everyone_on_their_spot() -> void:
	var room := _room("a")
	for index in 3:
		room.panes.append(_agent("i%d" % index, "idle"))
	var plan := _serviced(_floor([room]), 32)
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
	var replanned := _serviced(_floor([room]), 32, plan)
	_eq(replanned.pantry.geometry_signature(), plan.pantry.geometry_signature(), "the same pantry")
	var second := OfficeRests.assign(replanned, MapModel.of(_floor([room])))
	for index in 3:
		_eq(second.places["i%d" % index].index, first.places["i%d" % index].index, "i%d stays put" % index)
	for index in spots:
		room.panes.append(_agent("crowd%d" % index, "idle", 1000.0 + index))
	var crowded := _serviced(_floor([room]), 32, replanned)
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


## A floor without the entry band's fixtures (a band too narrow for them):
## everyone sits, the idle too, and nobody has a spot.
func test_blocked_and_done_sit_on_a_floor_without_fixtures() -> void:
	var room := _room("a")
	for state: String in ["working", "blocked", "done", "idle", "unknown"]:
		room.panes.append(_agent(state, state))
	var plan := _serviced(_floor([room]), 20)
	plan.reception = null
	plan.pantry = null
	var service := OfficeRests.assign(plan, MapModel.of(_floor([room])))
	_eq(service.places.size(), 5, "every agent has a place")
	for key: String in service.places:
		_eq([service.places[key].rest, service.places[key].index], [OfficeRests.Rest.SEAT, -1], key + ": the seat")


## The plan still reserves the reception's queue slots in front of its counter
## (so no floor is laid out differently), but nobody rests there: however many
## are blocked, done or idle, every place is a seat or one of the pantry's spots.
func test_nobody_rests_at_the_reception() -> void:
	var room := _room("a")
	var states: Array[String] = ["blocked", "done", "idle"]
	for index in 12:
		room.panes.append(_agent("s%d" % index, states[index % 3], 10.0 * index))
	var plan := _serviced(_floor([room]), 20)
	_check(plan.reception != null and plan.reception.spots.size() >= OfficeShell.MIN_QUEUE, "the plan keeps the slots")
	var service := OfficeRests.assign(plan, MapModel.of(_floor([room])))
	var pantry := 0
	for key: String in service.places:
		var place := service.places[key]
		if place.rest == OfficeRests.Rest.PANTRY:
			pantry += 1
			_check(place.index >= 0 and place.index < plan.pantry.spots.size(), key + ": on a pantry spot")
		else:
			_eq([place.rest, place.index], [OfficeRests.Rest.SEAT, -1], key + ": at the seat")
	_eq(pantry, mini(4, plan.pantry.spots.size()), "the idle fill the pantry, nobody else goes near the counters")


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


func _plan(floor_model: ZoneModel) -> FloorPlan:
	var rules := _real_rules()
	var result := OfficeFloorLayout.plan(floor_model, null, rules)
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
