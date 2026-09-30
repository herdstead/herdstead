extends "res://tools/office_test_base.gd"
## What tools/test_office_walking.gd and tools/test_office_rests.gd stand on:
## the office they drive with the shared fixture (every agent on api at work),
## stepped time, the route and invariant checks and the seeded lifecycle's
## draws. A base of its own keeps each suite under gdlint's max-file-lines; it
## holds no cases of its own.

## The frame rates walks are stepped at: the office in use, and minimized.
const FPS := 30.0
const MINIMIZED_FPS := 8.0
## The second machine of the cases that need one (see _two_machine_office()).
const BEE := "socket:bee"
## The window these suites lay floors out in: 628x480 plans a floor 488 units
## wide (OfficeHud.plan_width()). The walks, pantries and rows the
## cases here measure stand on that geometry.
const PLAN_SCREEN := Vector2(628, 480)
## How many agents api:t1 takes on in _stacked(): enough that its pod (twelve
## panes, six columns, seven cells) and api:t2's (three cells) no longer share a
## pod row of the suites' one-lane map (eight inner cells), so api:t2 is laid
## out on the row below, as the long tables always were. (Ten made a pod of
## nine cells, which takes two lanes and api:t2 beside it.)
const STACKED := 9


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket", "work"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s= (use tools/run_tests.sh)" % name)
			quit(2)
			return
	# Nothing here may reach the user's herdr, machines or forwards.
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("walking-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	# The walking cases are about seats: every agent on api works (api:p2 is idle in
	# the shared fixture, and an agent arriving at api:p3 would be too), so
	# nobody rests in the pantry unless a case says so; the rests suite's cases
	# say so.
	fixture = _with(_with(fixture, "api:p2", {"agent_status": "working"}), "api:p3", {"agent_status": "working"})
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


# --- helpers ----------------------------------------------------------------------


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The instance ids of `bodies`, which read better in a failure than the bodies.
static func _ids(bodies: Array) -> Array:
	return bodies.map(func(body: Object) -> int: return body.get_instance_id())


## The last point of `route`; INF when it has none.
static func _last(route: PackedVector2Array) -> Vector2:
	return route[route.size() - 1] if not route.is_empty() else Vector2.INF


## Where `node` is in the floor's own coordinates: the sorted root's.
func _floor_point(office: OfficeDouble, node: Node2D) -> Vector2:
	return office.floor_view.sorted.to_local(node.global_position)


func _seat_of(office: OfficeDouble, pane_id: String) -> Vector2:
	return _station(office, _pane(pane_id)).position


func _walkers(office: OfficeDouble) -> Array[PixelPerson]:
	return office.floor_view.presentation.walkers()


func _ghosts(office: OfficeDouble) -> Array[PixelPerson]:
	return office.floor_view.presentation.ghosts()


func _route(office: OfficeDouble, body: PixelPerson) -> PackedVector2Array:
	return office.floor_view.presentation.route_of(body)


func _speed(office: OfficeDouble, body: PixelPerson) -> float:
	return office.floor_view.presentation.speed_of(body)


## Step the floor's walks `times` frames of `seconds`, the way the office does.
func _step(office: OfficeDouble, seconds: float, times := 1) -> void:
	for frame in times:
		office.floor_view.walk(seconds)


func _door(office: OfficeDouble) -> Vector2:
	return OfficeShell.door(office.layout_plan())


func _threshold(office: OfficeDouble) -> Vector2:
	var art := office.art
	return (
		OfficeWalkGraph
		. of(office.layout_plan(), PixelPerson.footprint(), PixelPerson.drawing_rect(art.people))
		. threshold
	)


## Walk `body` along `route` frame by frame at `seconds` a frame until it stops,
## checking every frame: on the route, onward, facing the way it goes. The
## number of frames it took.
func _walk_along(office: OfficeDouble, body: PixelPerson, route: PackedVector2Array, seconds: float) -> int:
	var last := -1.0
	var frames := 0
	while _walkers(office).has(body) and frames < 1000:
		_step(office, seconds)
		frames += 1
		if not _walkers(office).has(body):
			break
		var at := _floor_point(office, body)
		var segment := _segment_of(at, route)
		if segment < 0:
			_fail("frame %d: %s is off its route at %s" % [frames, body.name, at])
			break
		var along := _along(at, route)
		if along <= last:
			_fail("frame %d: %s went back from %s to %s" % [frames, body.name, last, along])
		last = along
		var heading := route[segment + 1] - route[segment]
		var wanted := (
			PixelPeople.RIGHT
			if heading.x > 0
			else PixelPeople.LEFT if heading.x < 0 else PixelPeople.FRONT if heading.y > 0 else PixelPeople.BACK
		)
		if body.facing != wanted:
			_fail("frame %d: %s faces %s walking %s" % [frames, body.name, body.facing, heading])
	return frames


## The segment of `route` that `point` is on, the later one at a corner; -1 off it.
static func _segment_of(point: Vector2, route: PackedVector2Array) -> int:
	for index in range(route.size() - 2, -1, -1):
		var a := route[index]
		var b := route[index + 1]
		var low := a.min(b) - Vector2(0.001, 0.001)
		var high := a.max(b) + Vector2(0.001, 0.001)
		var on_line := is_equal_approx(a.x, b.x) and is_equal_approx(point.x, a.x)
		on_line = on_line or (is_equal_approx(a.y, b.y) and is_equal_approx(point.y, a.y))
		if on_line and point.x >= low.x and point.x <= high.x and point.y >= low.y and point.y <= high.y:
			return index
	return -1


## How far along `route` `point` is.
static func _along(point: Vector2, route: PackedVector2Array) -> float:
	var segment := _segment_of(point, route)
	var total := 0.0
	for index in segment:
		total += route[index].distance_to(route[index + 1])
	return total + route[maxi(segment, 0)].distance_to(point)


## The fixture without pane `pane_id`, in its panes, agents and layouts.
func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result


## api:t1 laid out anew: api:p1 near in column 1, api:p2 far in column 0,
## api:p3 far in column 1 (as test_office_reconcile.gd swaps them).
func _swapped(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var columns: Dictionary[String, int] = {"api:p1": 1, "api:p2": 0, "api:p3": 1}
	var sides: Dictionary[String, String] = {"api:p1": "near", "api:p2": "far", "api:p3": "far"}
	for layout: Dictionary in _list(result, "layouts"):
		if layout.tab_id != "api:t1":
			continue
		for slot: Dictionary in _list(layout, "panes"):
			var pane_id := str(slot.pane_id)
			var rect := _dict(slot, "rect")
			rect.x = columns[pane_id] * 80
			rect.y = 40 if sides[pane_id] == "near" else 0
	return result


## `snapshot` with `count` more agents at api:t1, which grows by a column pair.
func _grown(snapshot: Dictionary, count: int) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var first: Dictionary = _list(result, "panes")[0]
	for index in count:
		var extra := first.duplicate(true)
		extra.pane_id = "api:grow-%d" % index
		extra.terminal_id = "term-grow-%d" % index
		_list(result, "panes").append(extra)
	return result


## `snapshot` with api:t1 STACKED agents larger (_grown()): api:t1 alone on the
## first row, api:t2 on the second.
func _stacked(snapshot: Dictionary) -> Dictionary:
	return _grown(snapshot, STACKED)


## An office of the shared fixture in the suites' window (PLAN_SCREEN).
func _live_office(snapshot: Dictionary = fixture, screen := PLAN_SCREEN) -> OfficeDouble:
	return await super(snapshot, screen)


## The fixture's api floor in a window wide enough to hold its two tables in
## one row: it is laid out the first time it is drawn, at the width it had.
func _wide_office(snapshot: Dictionary = {}) -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = Vector2(1600, 480)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	_feed(office, fixture if snapshot.is_empty() else snapshot)
	await _frames(2)
	return office


## One workspace, `crowd`, one tab of `count` agents.
func _crowded(count: int) -> Dictionary:
	var result := {
		"focused_pane_id": "crowd:p00",
		"workspaces": [{"workspace_id": "crowd", "number": 1, "label": "crowd"}],
		"tabs": [{"tab_id": "crowd:t1", "workspace_id": "crowd", "number": 1, "label": "crowd"}],
		"panes": [],
		"agents": [],
		"layouts": []
	}
	for index in count:
		var pane_id := "crowd:p%02d" % index
		var pane := {
			"pane_id": pane_id,
			"workspace_id": "crowd",
			"tab_id": "crowd:t1",
			"agent": "claude",
			"agent_status": "working",
			"terminal_id": "term-" + pane_id
		}
		_list(result, "panes").append(pane)
	return result


## The crowd without its panes from `first` up to `last`, the last left out.
func _without_many(snapshot: Dictionary, first: int, last: int) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var leaving := {}
	for index in range(first, last):
		leaving["crowd:p%02d" % index] = true
	result.panes = _list(result, "panes").filter(func(each: Dictionary) -> bool: return not leaving.has(each.pane_id))
	return result


## The stress fixture's floor as the office models it: ten tabs of eight panes
## (tab 0 `extra` more), two to a column, every one an agent, or every one a shell.
func _stress_model(agents: bool, extra := 0) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = HerdrFleet.pane_key(LOCAL, "stress")
	for tab in 10:
		var room := RoomModel.new()
		room.key = JSON.stringify([LOCAL, "stress", "t%d" % tab])
		room.tab_id = "t%d" % tab
		room.number = tab + 1
		for index in 8 + (extra if tab == 0 else 0):
			var pane := PaneModel.new()
			pane.pane_id = "t%d:p%d" % [tab, index]
			pane.key = HerdrFleet.pane_key(LOCAL, pane.pane_id)
			pane.terminal_id = "term-" + pane.pane_id
			pane.provider = "claude" if agents else ""
			pane.state = "working"
			pane.explicit_layout = true
			pane.table_x = floori(index / 2.0)
			pane.side = "far" if index % 2 == 0 else "near"
			pane.layout_order = index
			room.panes.append(pane)
		floor_model.rooms.append(room)
	return floor_model


# --- route, invariant and fuzz helpers ----------------------------------------------


## What one random observation of the fixture's api floor changes: api:p1's
## state and agent, an agent at api:p3 and a new terminal there, api:p2 moving
## to api:t2 or closing, api:t1 growing, api:p4 moving to api:t1, or its tab
## closing with it. Drawn in a fixed order off one seeded stream.
class FuzzState:
	extends RefCounted
	var p1 := "working"
	var p1_agent := "claude"
	var p3 := ""
	var p3_term := false
	var p2_tab := ""
	var grow := 0
	var p4_tab := false
	var p2_gone := false
	var p4_gone := false
	## api:p2 and api:p4 flap too, so the pantry fills and empties
	## (drawn after the others, so the older seeds keep theirs).
	var p2 := "working"
	var p4 := "working"


## The seat leg of pane `key` on `plan` (OfficeWalkGraph.leg_to_seat()).
static func _seat_leg_of(plan: FloorPlan, key: String) -> PackedVector2Array:
	for desk in plan.desks:
		var seat := desk.seat(key)
		if seat == null:
			continue
		return OfficeWalkGraph.leg_to_seat(
			desk.origin + desk.measure.approach_position(seat.column, seat.side),
			desk.origin + desk.measure.seat_position(seat.column, seat.side),
			desk.origin + desk.measure.standing_position(seat.column, seat.side),
			seat.side == "near"
		)
	return PackedVector2Array()


## Whether any segment of `route` runs up or down the column at `x`.
static func _runs_along(route: PackedVector2Array, x: float) -> bool:
	for index in range(1, route.size()):
		if route[index - 1].x == x and route[index].x == x and route[index - 1].y != route[index].y:
			return true
	return false


## Every far seat leg of every table on `plan`, where the table stands, by tab
## key, as pairs of points: the only way into a table's footprint. Read off the
## plan's own measure, not the walk graph.
static func _table_legs(plan: FloorPlan) -> Dictionary[String, PackedVector2Array]:
	var legs: Dictionary[String, PackedVector2Array] = {}
	for desk in plan.desks:
		var pairs := PackedVector2Array()
		for column in desk.capacity:
			pairs.append(desk.origin + desk.measure.approach_position(column, "far"))
			pairs.append(desk.origin + desk.measure.seat_position(column, "far"))
		legs[desk.tab_key] = pairs
	return legs


## Every leg up to a spot of `plan`'s pantry, as pairs of points: the only way
## onto the fixture row. Read off the plan's own fixtures, not the walk graph.
static func _fixture_legs(plan: FloorPlan) -> PackedVector2Array:
	var pairs := PackedVector2Array()
	for counter in plan.fixtures():
		for index in counter.spots.size():
			pairs.append(counter.approaches[index])
			pairs.append(counter.spots[index])
	return pairs


## Whether the part of the axis-aligned segment from `a` to `b` that lies in
## `box` lies on one of the segments `pairs` holds (as pairs of points).
static func _inside_on(a: Vector2, b: Vector2, box: Rect2, pairs: PackedVector2Array) -> bool:
	for index in range(0, pairs.size() - 1, 2):
		var p := pairs[index]
		var q := pairs[index + 1]
		if a.x == b.x and p.x == q.x and absf(a.x - p.x) < 0.01:
			var low := maxf(minf(a.y, b.y), box.position.y)
			var high := minf(maxf(a.y, b.y), box.end.y)
			if low >= minf(p.y, q.y) - 0.01 and high <= maxf(p.y, q.y) + 0.01:
				return true
		if a.y == b.y and p.y == q.y and absf(a.y - p.y) < 0.01:
			var low := maxf(minf(a.x, b.x), box.position.x)
			var high := minf(maxf(a.x, b.x), box.end.x)
			if low >= minf(p.x, q.x) - 0.01 and high <= maxf(p.x, q.x) + 0.01:
				return true
	return false


## Every live walk on `view`'s floor keeps to the rules, checked against the
## plan (_table_legs(), _fixture_legs()), not the presentation's bookkeeping:
## the walker is on its route; what it has left to walk is straight segments;
## none enters an obstacle but a table along one of its far seat legs where it
## stands now, the top wall's drawing clearance along the door's threshold leg,
## and the fixture row along a pantry spot's leg (nothing
## runs along the row otherwise); the route ends where the walker belongs (a
## ghost's at the door); nobody walks faster than TOP_SPEED.
func _check_routes(view: OfficeFloorView, people: PixelPeople, when: String) -> void:
	var plan := view.plan
	var graph := OfficeWalkGraph.of(plan, PixelPerson.footprint(), PixelPerson.drawing_rect(people))
	var legs := _table_legs(plan)
	var fixture_legs := _fixture_legs(plan)
	var door := OfficeShell.door(plan)
	var threshold := PackedVector2Array([door, graph.threshold])
	var ghosts := view.presentation.ghosts()
	for body in view.presentation.walkers():
		var route := view.presentation.route_of(body)
		var at := view.sorted.to_local(body.global_position)
		var segment := _segment_of(at, route)
		if segment < 0:
			_fail("%s: %s is off its route at %s: %s" % [when, body.name, at, route])
			continue
		var rest := PackedVector2Array([at])
		rest.append_array(route.slice(segment + 1))
		for index in range(1, rest.size()):
			var a := rest[index - 1]
			var b := rest[index]
			if a.x != b.x and a.y != b.y:
				_fail("%s: %s walks a diagonal %s -> %s" % [when, body.name, a, b])
				continue
			for obstacle in graph.obstacles:
				if OfficeWalkGraph.clear_link(a, b, [obstacle.rect]):
					continue
				var allowed := false
				if obstacle.kind == OfficeWalkGraph.Kind.TABLE:
					var pairs: PackedVector2Array = legs.get(obstacle.tab_key, PackedVector2Array())
					allowed = _inside_on(a, b, obstacle.rect, pairs)
				elif obstacle.kind == OfficeWalkGraph.Kind.WALL_DRAWING:
					allowed = _inside_on(a, b, obstacle.rect, threshold)
				elif obstacle.kind == OfficeWalkGraph.Kind.FIXTURE:
					allowed = _inside_on(a, b, obstacle.rect, fixture_legs)
				if not allowed:
					_fail(
						(
							"%s: %s's segment %s -> %s enters %s %s %s: %s"
							% [when, body.name, a, b, obstacle.kind, obstacle.rect, obstacle.tab_key, route]
						)
					)
		if view.presentation.speed_of(body) > OfficePresentation.TOP_SPEED + 0.001:
			_fail("%s: %s walks at %s" % [when, body.name, view.presentation.speed_of(body)])
		var goal := door
		if not ghosts.has(body):
			var station := body.get_parent() as OfficeStation
			goal = station.position + station.rest_position()
		if not _last(route).is_equal_approx(goal):
			_fail("%s: %s's route ends at %s, not at %s" % [when, body.name, _last(route), goal])


## The people of the shown floor as the rules want them after any step: one
## body per seat's worker and per ghost; a seat marked walking only while its
## worker walks (the machine not stale); a worker at rest on the seat or the
## spot, not playing the walk, at the family's own pace; no ghosts while stale.
func _check_invariants(office: OfficeDouble, when: String, frozen: bool) -> void:
	var presentation := office.floor_view.presentation
	var ghosts := presentation.ghosts()
	var actors := 0
	for key: String in office.floor_view.seats:
		var station: OfficeStation = office.floor_view.seats[key].node
		var actor := station.actor()
		if actor == null:
			if station.walking:
				_fail(when + ": " + key + " walking with nobody at the seat")
			continue
		actors += 1
		if presentation.is_walking(key) or frozen:
			continue
		if station.walking:
			_fail(when + ": " + key + " marked walking with no walk")
		var want := station.rest_position()
		if actor.position != want:
			_fail(when + ": %s at rest at %s, not %s" % [key, actor.position, want])
		if actor.track == ArtContract.TRACK_WALK:
			_fail(when + ": " + key + " at rest playing the walk")
		if actor.paced() != 1.0:
			_fail(when + ": %s at rest at pace %s" % [key, actor.paced()])
	var bodies := 0
	for body: Node in office.floor_view.root.find_children("*", "PixelPerson", true, false):
		bodies += 0 if body.is_queued_for_deletion() else 1
	if bodies != actors + ghosts.size():
		_fail(when + ": %d bodies on the floor for %d workers and %d ghosts" % [bodies, actors, ghosts.size()])
	if frozen and not ghosts.is_empty():
		_fail(when + ": ghosts while stale")


## One random FuzzState off `rng`, in a fixed order of draws.
static func _random_state(rng: RandomNumberGenerator) -> FuzzState:
	var statuses: Array[String] = ["working", "done", "blocked", "idle"]
	var agents: Array[String] = ["claude", "codex"]
	var shells: Array[String] = ["", "codex", "claude"]
	var grows: Array[int] = [0, 0, 1, 3, 9]
	var state := FuzzState.new()
	state.p1 = statuses[rng.randi() % 4]
	state.p1_agent = agents[rng.randi() % 2] if rng.randf() < 0.3 else "claude"
	state.p3 = shells[rng.randi() % 3]
	state.p3_term = rng.randf() < 0.2
	state.p2_tab = "api:t2" if rng.randf() < 0.25 else ""
	state.grow = grows[rng.randi() % 5]
	state.p4_tab = rng.randf() < 0.2
	# A repeated pane was one of the draws once; the draw stays, so the seeds do.
	rng.randf()
	state.p2_gone = rng.randf() < 0.25
	state.p4_gone = rng.randf() < 0.2
	state.p2 = statuses[rng.randi() % 4]
	state.p4 = statuses[rng.randi() % 4]
	return state


## The fixture as `state` changes it.
func _variant(state: FuzzState) -> Dictionary:
	var snapshot: Dictionary = fixture.duplicate(true)
	snapshot = _with(snapshot, "api:p1", {"agent_status": state.p1, "agent": state.p1_agent})
	snapshot = _with(snapshot, "api:p2", {"agent_status": state.p2})
	snapshot = _with(snapshot, "api:p4", {"agent_status": state.p4})
	snapshot = _with(snapshot, "api:p3", {"agent": null if state.p3.is_empty() else state.p3})
	if not state.p2_tab.is_empty():
		snapshot = _with(snapshot, "api:p2", {"tab_id": state.p2_tab})
	if state.p3_term:
		snapshot = _with(snapshot, "api:p3", {"terminal_id": "term-api-p3-b"})
	if state.grow > 0:
		snapshot = _grown(snapshot, state.grow)
	if state.p2_gone:
		snapshot = _without(snapshot, "api:p2")
	if state.p4_tab:
		snapshot = _with(snapshot, "api:p4", {"tab_id": "api:t1"})
	if state.p4_gone:
		snapshot = _without(snapshot, "api:p4")
		snapshot.tabs = _list(snapshot, "tabs").filter(func(each: Dictionary) -> bool: return each.tab_id != "api:t2")
	return snapshot
