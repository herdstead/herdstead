extends "res://tools/walking_test_base.gd"
## The people of the shown floor walking (OfficePresentation): in at the lift
## door, out of it as a ghost, to the pantry and back, over to a new seat;
## one body per worker through every change of mind; cold wherever the floor is
## drawn afresh or the machine was away; frozen while it is. The office is real,
## its snapshots are handed to its stopped client, and time is stepped through
## the floor view's own walk(), so every position asserted is one a frame drew.
## Who rests where (the seat, the pantry) has its own suite, tools/test_office_rests.gd.
##
## godot --headless --path . --script tools/test_office_walking.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>


func _marker() -> String:
	return "WALKING TESTS"


# --- arriving and leaving ---------------------------------------------------------


## A pane that gains an agent gets its worker at once, in the lift door: they
## walk down the corridor to the seat's approach, step to the seat and sit. The
## seat's plate, badge and click target say so from the start; the body is the
## seat's own worker all the way, facing the way it walks, on the route, onward
## every frame, at the pace the route asks for, and in six seconds at most.
func test_an_arrival_walks_in_from_the_door_to_the_seat() -> void:
	var office := await _live_office()
	var station := _station(office, _pane("api:p3"))
	_eq(station.actor(), null, "api:p3 starts as a shell")
	_feed(office, _with(fixture, "api:p3", {"agent": "codex"}))
	var body := station.actor()
	_check(body != null, "the seat has its worker at once")
	if body == null:
		_done(office)
		return
	_eq(_plate(station).text, "CODEX", "its plate names them at once")
	_check(_badge(station).visible, "and its badge shows")
	var target: Area2D = station.get_node("Target")
	_check(target.input_pickable, "and it answers a click")
	_eq(_floor_point(office, body), _door(office), "the worker comes in at the lift door")
	var route := _route(office, body)
	_check(route.size() >= 3 and route[0] == _door(office), "and walks from there: %s" % [route])
	_eq(_segment_of(_threshold(office), route), 0, "over the door's threshold, straight down from it")
	_eq(_last(route), _seat_of(office, "api:p3"), "to the seat")
	_eq(body.get_parent(), station, "the seat's own worker while they walk")
	_eq([body.track, body.look.context], [ArtContract.TRACK_WALK, AvatarLook.STAND], "walking on their feet")
	var speed := _speed(office, body)
	_check(is_equal_approx(speed, maxf(96.0, OfficeWalkGraph.length(route) / 6.0)), "as fast as the route asks")
	_check(is_equal_approx(body.paced(), speed / 96.0), "their feet keeping time: %s" % body.paced())
	var frames := _walk_along(office, body, route, 1.0 / FPS)
	_check(frames > 0 and frames <= ceili(6.0 * FPS) + 1, "in six seconds at most: %d frames" % frames)
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "they end on the seat")
	_eq([str(body.look.context), str(body.look.orientation)], ["desk", "back"], "sitting, a near worker's back turned")
	_check(_shape_of(body).disabled, "feet off")
	_eq(body.animation, &"working", "playing what the seat says")
	_eq(body.paced(), 1.0, "at the family's own pace again")
	_eq(_ids(_walkers(office)), [], "and nobody walks any more")
	_done(office)


## A worker whose pane closes or loses its agent leaves: the same body, taken
## out of its seat at once into the sorted root, walks from where it sat to the
## lift door and is gone. It is a ghost: no plate, no badge, nothing that
## answers a click, and the seat it left is empty at once. A pane moving to
## another workspace (another zone of the same map now, not another floor)
## changes seats instead: the same worker walks over to it.
func test_a_departure_walks_out_as_a_ghost() -> void:
	var closed := _without(fixture, "api:p2")
	var moved := _with(fixture, "api:p2", {"workspace_id": "web", "tab_id": "web:t1"})
	var shell := _with(fixture, "api:p2", {"agent": null})
	var office := await _live_office()
	var mover := _station(office, _pane("api:p2")).actor()
	_feed(office, moved)
	_eq(_ids(_ghosts(office)), [], "moved to web's zone: nobody walks out")
	_eq(_station(office, _pane("api:p2")).actor(), mover, "the same worker, now web's seat's")
	_eq(_last(_route(office, mover)), _seat_of(office, "api:p2"), "walking over to it")
	_done(office)
	for leaving: Dictionary in [closed, shell]:
		office = await _live_office()
		var station := _station(office, _pane("api:p2"))
		var body := station.actor()
		var seat := _seat_of(office, "api:p2")
		_feed(office, leaving)
		var how := "closed" if leaving == closed else "a shell"
		_eq(station.actor(), null, how + ": the seat lets its worker go at once")
		_eq(_ids(_ghosts(office)), _ids([body]), how + ": the same worker walks out")
		_eq(body.get_parent(), office.floor_view.sorted, how + ": straight in the sorted root")
		_check(str(body.name).begins_with("Ghost"), how + ": as a ghost, " + str(body.name))
		_eq(
			[body.find_children("*", "Label", true, false), body.find_children("*", "Area2D", true, false)],
			[[], []],
			how + ": with no plate and nothing to click"
		)
		_eq(_floor_point(office, body), seat, how + ": from where they sat")
		var route := _route(office, body)
		_check(not route.is_empty() and route[route.size() - 1] == _door(office), how + ": to the lift door")
		_eq(_segment_of(_threshold(office), route), route.size() - 2, how + ": over its threshold, straight up to it")
		var frames := _walk_along(office, body, route, 1.0 / FPS)
		_check(frames <= ceili(6.0 * FPS) + 1, how + ": in six seconds at most: %d frames" % frames)
		_check(not is_instance_valid(body) or not body.is_inside_tree(), how + ": and is gone through the door")
		_eq(_ids(_ghosts(office)), [], how + ": nobody is left on the way out")
		_done(office)


## An idle agent walks from the seat to the pantry and back by the seat's own
## leg: a far one straight out of the table along its column, a near one beside
## the chair (a sidestep to the table's standing spot, then down that column),
## never along the chair's column; back in the same way. The plate, badge and
## click target move with the observation, the body catches up; the same node
## throughout.
func test_going_to_the_pantry_and_back_walks_the_seat_legs() -> void:
	var both_sides := _both_sides()
	var office := await _live_office(both_sides)
	var ids := {}
	for pane_id: String in ["api:p1", "api:p3"]:
		ids[pane_id] = _station(office, _pane(pane_id)).actor().get_instance_id()
	var idle := _with(_with(both_sides, "api:p1", {"agent_status": "idle"}), "api:p3", {"agent_status": "idle"})
	var sides := {}
	for step: int in 2:
		var out := step == 0
		_feed(office, idle if out else both_sides)
		var routes: Dictionary[String, PackedVector2Array] = {}
		for pane_id: String in ["api:p1", "api:p3"]:
			var station := _station(office, _pane(pane_id))
			var body := station.actor()
			var seat := _seat_of(office, pane_id)
			var leg := _seat_leg_of(office.layout_plan(), _pane(pane_id))
			var where := "%s (%s) %s" % [pane_id, station.side, "to the pantry" if out else "back to the seat"]
			sides[station.side] = true
			_eq(body.get_instance_id(), ids[pane_id], where + ": the same worker")
			_eq(station.away(), out, where + ": the seat's labels and click target move at once")
			var route := _route(office, body)
			routes[pane_id] = route
			if out:
				_eq(route[0], seat, where + ": from the seat")
				_eq(_last(route), station.position + station.rest_position(), where + ": to the pantry spot")
			else:
				_eq(_last(route), seat, where + ": to the seat")
			if station.side == "near":
				var inward := leg.slice(1)
				var outward := inward.duplicate()
				outward.reverse()
				if out:
					_eq(route.slice(0, 3), outward, where + ": a sidestep to the spot, then down its column")
				else:
					_eq(route.slice(route.size() - 3), inward, where + ": up the spot's column, a sidestep in")
				_check(not _runs_along(route, seat.x), where + ": never along the chair's column: %s" % [route])
			else:
				var next := route[1] if out else route[route.size() - 2]
				_eq(next.x, seat.x, where + ": straight along the seat's own column, out of the table")
		_check_routes(office.floor_view, office.art.people, "to the pantry" if out else "back to the seats")
		for pane_id: String in ["api:p1", "api:p3"]:
			var station := _station(office, _pane(pane_id))
			var body := station.actor()
			var where := "%s (%s) %s" % [pane_id, station.side, "to the pantry" if out else "back to the seat"]
			_walk_along(office, body, routes[pane_id], 1.0 / FPS)
			var goal := station.position + station.rest_position()
			_eq(_floor_point(office, body), goal, where + ": ends where they belong")
			_eq(str(body.look.context), "stand" if out else "desk", where + ": standing or sitting")
			if out:
				_eq(str(body.facing), "front", where + ": facing the viewer")
	_eq(sides.keys().size(), 2, "one worker on each side of the table")
	_done(office)


## A pane whose seat moves (another column, the other side) walks its worker
## from the old seat to the new one: the same station, the same body, never a
## departure and an arrival.
func test_a_worker_whose_seat_moves_walks_there() -> void:
	var snapshot := _both_sides()
	var office := await _live_office(snapshot)
	var bodies: Dictionary[String, PixelPerson] = {}
	var seats: Dictionary[String, Vector2] = {}
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		bodies[pane_id] = _station(office, _pane(pane_id)).actor()
		seats[pane_id] = _seat_of(office, pane_id)
	var actors := _all_actor_ids(office)
	_feed(office, _swapped(snapshot))
	_eq(_ids(_ghosts(office)), [], "nobody leaves")
	_eq(_all_actor_ids(office), actors, "and nobody new comes")
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		var body := bodies[pane_id]
		var route := _route(office, body)
		_eq(_station(office, _pane(pane_id)).actor(), body, pane_id + ": the same worker at the new seat")
		_check(route.size() >= 2 and route[0] == seats[pane_id], pane_id + ": walks from the old seat")
		_eq(_last(route), _seat_of(office, pane_id), pane_id + ": to the new one")
		_check(_seat_of(office, pane_id) != seats[pane_id], pane_id + ": which really moved")
	office.settle()
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		var station := _station(office, _pane(pane_id))
		_eq(_floor_point(office, station.actor()), _seat_of(office, pane_id), pane_id + ": and sits there")
	_done(office)


## A pane that moves to another table of the floor takes its worker with it:
## out of the old table's seat before that seat is emptied, into the new one,
## the same body walking across.
func test_a_worker_whose_pane_changes_tables_walks_across() -> void:
	var office := await _live_office()
	var body := _station(office, _pane("api:p4")).actor()
	var from := _seat_of(office, "api:p4")
	_feed(office, _with(fixture, "api:p4", {"tab_id": "api:t1"}))
	var station := _station(office, _pane("api:p4"))
	_eq(station.actor(), body, "the same worker is the new seat's")
	_eq(_ids(_ghosts(office)), [], "never a ghost")
	var route := _route(office, body)
	_check(route.size() >= 2 and route[0] == from, "walking from the old table's seat")
	_eq(_last(route), _seat_of(office, "api:p4"), "to the new one")
	office.settle()
	_eq(_floor_point(office, body), _seat_of(office, "api:p4"), "where they sit down")
	_done(office)


## Changing its mind within one walk never makes a second body: a worker
## walking in whose pane closes turns round as that same body, a ghost now; a
## ghost whose pane comes back (the same terminal and agent) is taken back.
func test_turning_round_keeps_one_body() -> void:
	var office := await _live_office()
	var arrived := _with(fixture, "api:p3", {"agent": "codex"})
	_feed(office, arrived)
	var body := _station(office, _pane("api:p3")).actor()
	_step(office, 1.0 / FPS, 20)
	var halfway := _floor_point(office, body)
	_check(halfway != _door(office) and halfway != _seat_of(office, "api:p3"), "on the way in")
	_feed(office, fixture)
	_eq(_ids(_ghosts(office)), _ids([body]), "their pane leaves: the same body turns round, a ghost")
	var out := _route(office, body)
	_check(not out.is_empty() and out[0].is_equal_approx(halfway), "from where they stood")
	_eq(_last(out), _door(office), "back to the door")
	_step(office, 1.0 / FPS, 10)
	var leaving := _floor_point(office, body)
	_feed(office, arrived)
	_eq(_station(office, _pane("api:p3")).actor(), body, "their pane is back: the ghost is taken back")
	_eq(_ids(_ghosts(office)), [], "nobody else leaves")
	var back := _route(office, body)
	_check(not back.is_empty() and back[0].is_equal_approx(leaving), "from where they stood")
	_eq(_last(back), _seat_of(office, "api:p3"), "to the seat")
	office.settle()
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "where they sit")
	_eq(_all_actor_ids(office).count(body.get_instance_id()), 1, "one body throughout")
	_done(office)


## Status flapping within a walk walks the same worker wherever the latest
## observation says, and nothing an earlier one started lands them anywhere
## else: idle, working, idle, blocked ends blocked, back in the chair with a
## hand up (a blocked agent sits; idle is the one that walks away).
func test_flapping_states_end_where_the_last_one_says() -> void:
	var office := await _live_office()
	var body := _station(office, _pane("api:p1")).actor()
	var id := body.get_instance_id()
	for state: String in ["idle", "working", "idle", "blocked"]:
		_feed(office, _with(fixture, "api:p1", {"agent_status": state}))
		_check(
			_walkers(office).has(body),
			"%s: walks where the latest word sends them, from %s" % [state, _floor_point(office, body)]
		)
		_step(office, 1.0 / FPS, 3)
		_eq(_station(office, _pane("api:p1")).actor().get_instance_id(), id, state + ": the same worker")
	_step(office, 1.0 / FPS, ceili(6.0 * FPS))
	_eq(_ids(_walkers(office)), [], "every walk ends")
	_eq(_floor_point(office, body), _seat_of(office, "api:p1"), "at the seat, as the last word says")
	_eq([str(body.look.context), body.animation, body.track], ["desk", &"blocked", &"desk_blocked"], "blocked, hand up")
	_done(office)


## Another agent in the pane is another worker: the one who was there walks out
## as a ghost while the new one walks in at the door. The same agent with a new
## terminal walks nobody.
func test_another_agent_walks_out_and_in_and_a_new_terminal_walks_nobody() -> void:
	var office := await _live_office()
	var station := _station(office, _pane("api:p1"))
	var claude := station.actor()
	var at := claude.global_position
	_feed(office, _with(fixture, "api:p1", {"terminal_id": "term-api-p1-again"}))
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "a new terminal of the same agent walks nobody")
	_eq([station.actor(), claude.global_position], [claude, at], "the same worker stays put")
	_feed(office, _with(fixture, "api:p1", {"agent": "codex"}))
	var codex := station.actor()
	_eq(_ids(_ghosts(office)), _ids([claude]), "the old agent's worker walks out")
	_eq(claude.provider, "claude", "as themselves")
	_check(codex != null and codex != claude, "and a new worker is the seat's")
	_eq(codex.provider if codex != null else "", "codex", "the new agent")
	_eq(_floor_point(office, codex), _door(office), "coming in at the door")
	office.settle()
	_check(not is_instance_valid(claude) or not claude.is_inside_tree(), "the old one is gone")
	_eq(_floor_point(office, codex), _seat_of(office, "api:p1"), "the new one sits")
	_done(office)


## Closing the last pane of a tab closes the tab: its table is gone at once,
## and its worker walks out from where the table was.
func test_the_last_pane_of_a_tab_walks_out_from_where_its_table_was() -> void:
	var office := await _live_office()
	var tab := JSON.stringify([LOCAL, "api", "api:t2"])
	var table := office.floor_view.desks[tab].table
	var body := _station(office, _pane("api:p4")).actor()
	var seat := _seat_of(office, "api:p4")
	var closed := _without(fixture, "api:p4")
	closed.tabs = _list(closed, "tabs").filter(func(each: Dictionary) -> bool: return each.tab_id != "api:t2")
	_feed(office, closed)
	_check(not office.floor_view.desks.has(tab), "the tab's table is gone at once")
	_check(not table.is_inside_tree(), "off the floor")
	_eq(_ids(_ghosts(office)), _ids([body]), "its worker walks out")
	_eq(_floor_point(office, body), seat, "from where they sat, where the table was")
	var route := _route(office, body)
	_eq(_last(route), _door(office), "to the door")
	_walk_along(office, body, route, 1.0 / FPS)
	_eq(_ids(_ghosts(office)), [], "and is gone")
	_done(office)


## Closing a workspace's last pane closes its zone, in place on the same map:
## its tables are released and its people walk out to the lift door as ghosts
## (a floor used to close, another shown cold, nobody walking). Many at once are
## bounded: at most MAX_GHOSTS on their way out, and whoever the routing budget
## or the route cap leaves over is placed (gone) rather than walked.
func test_closing_a_workspace_walks_its_people_out() -> void:
	var office := await _live_office()
	var world := office.world.get_instance_id()
	var bodies: Array = []
	for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
		bodies.append(_station(office, _pane(pane_id)).actor())
	var gone: Dictionary = fixture.duplicate(true)
	for field: String in ["workspaces", "tabs", "panes", "agents", "layouts"]:
		gone[field] = _list(gone, field).filter(
			func(each: Dictionary) -> bool: return str(each.get("workspace_id", "")) != "api"
		)
	gone.focused_pane_id = "web:p1"
	_feed(office, gone)
	_eq([office.navigator.shown_key, office.world.get_instance_id()], [LOCAL, world], "the same map, the same world")
	_eq(office.layout_plan().zone(HerdrFleet.pane_key(LOCAL, "api")), null, "api's zone is gone from it")
	var ghosts := _ghosts(office)
	_check(not ghosts.is_empty(), "its people walk out")
	for body: PixelPerson in bodies:
		if ghosts.has(body):
			_eq(_last(_route(office, body)), _door(office), "the same body, as a ghost, to the lift door")
		else:
			_check(not is_instance_valid(body) or not body.is_inside_tree(), "or, not walked, gone at once")
	_step(office, 1.0 / FPS, ceili(7.0 * FPS))
	_eq(_ids(_ghosts(office)), [], "and are gone")
	_done(office)
	# A crowd leaving at once: one workspace of 60 agents closes.
	var crowd: Dictionary = fixture.duplicate(true)
	_list(crowd, "workspaces").append({"workspace_id": "crowd", "number": 9, "label": "crowd"})
	_list(crowd, "tabs").append({"workspace_id": "crowd", "tab_id": "crowd:t", "number": 1, "label": "crowd"})
	for index in 60:
		var pane := {"pane_id": "crowd:p%02d" % index, "tab_id": "crowd:t", "workspace_id": "crowd"}
		pane.merge({"agent": "claude", "agent_status": "working", "terminal_id": "term-crowd-%02d" % index})
		_list(crowd, "panes").append(pane)
	office = await _live_office(crowd, Vector2(1600, 480))
	var everyone: Array = []
	for index in 60:
		everyone.append(_station(office, _pane("crowd:p%02d" % index)).actor())
	_feed(office, fixture)
	var leaving := _ghosts(office)
	_check(leaving.size() <= OfficePresentation.MAX_GHOSTS, "at most MAX_GHOSTS walk out: %d" % leaving.size())
	_check(leaving.size() < 60, "the rest are not walked: %d of 60 walk" % leaving.size())
	for body: PixelPerson in everyone:
		_check(
			leaving.has(body) or not is_instance_valid(body) or not body.is_inside_tree(),
			"each walks out as a ghost or is gone at once"
		)
	_check_routes(office.floor_view, office.art.people, "after the crowd's zone closed")
	_done(office)


# --- cold passes ------------------------------------------------------------------


## A new workspace is a new zone of the same map, placed in place (the world
## is not built again, nobody else moves), and its people walk in from the lift
## door to their seats.
func test_a_new_workspace_is_a_zone_its_people_walk_into() -> void:
	var office := await _live_office()
	var world := office.world.get_instance_id()
	var zones := {}
	for zone in office.layout_plan().zones:
		zones[zone.zone_key] = zone.cells
	var grown: Dictionary = fixture.duplicate(true)
	_list(grown, "workspaces").append({"workspace_id": "ops", "number": 6, "label": "ops"})
	_list(grown, "tabs").append({"workspace_id": "ops", "tab_id": "ops:t1", "number": 1, "label": "ops"})
	for index in 2:
		var pane := {"pane_id": "ops:p%d" % index, "tab_id": "ops:t1", "workspace_id": "ops"}
		pane.merge({"agent": "claude", "agent_status": "working", "terminal_id": "term-ops-%d" % index})
		_list(grown, "panes").append(pane)
	_feed(office, grown)
	_eq(office.world.get_instance_id(), world, "the same world")
	_check(office.layout_plan().zone(HerdrFleet.pane_key(LOCAL, "ops")) != null, "the new zone is placed")
	for key: String in zones:
		_eq(office.layout_plan().zone(key).cells, zones[key], "%s keeps its rectangle" % key)
	for index in 2:
		var body := _station(office, _pane("ops:p%d" % index)).actor()
		_check(_walkers(office).has(body), "ops:p%d walks in" % index)
		var route := _route(office, body)
		_check(not route.is_empty() and route[0] == _door(office), "from the lift door")
		_eq(_last(route), _seat_of(office, "ops:p%d" % index), "to their seat in the new zone")
	_check_routes(office.floor_view, office.art.people, "after a zone arrived")
	_done(office)


## PageDown pans to another zone of the same map: the world is not built again,
## so it is no cold pass: whoever was walking walks on, along the same route.
func test_a_pagedown_pans_without_rebuilding() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p1", {"agent_status": "idle"}))
	var body := _station(office, _pane("api:p1")).actor()
	_step(office, 1.0 / FPS, 3)
	_check(_walkers(office).has(body), "api:p1 is on its way to the pantry")
	var route := _route(office, body)
	var world := office.world.get_instance_id()
	var pan := office.camera.pan
	await _office_key(office, KEY_PAGEDOWN)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(LOCAL, "web"), "PageDown pans to web")
	_check(office.camera.pan != pan, "the camera moved")
	_eq(office.world.get_instance_id(), world, "the world is not built again")
	_check(_walkers(office).has(body), "api:p1 still walks: no cold pass")
	_eq(_route(office, body), route, "along the same route")
	_done(office)


## A map drawn afresh (another theme, or another machine's map and back) shows
## everyone where they belong, walks nobody and has no ghosts. (Another zone of
## the same map is no longer drawn afresh: test_a_pagedown_pans_without_rebuilding.)
func test_a_new_theme_or_floor_walks_nobody() -> void:
	var office := await _two_machine_office(fixture, PLAN_SCREEN)
	_feed(office, _without(_with(fixture, "api:p1", {"agent_status": "idle"}), "api:p2"))
	_check(_walkers(office).size() == 2 and _ghosts(office).size() == 1, "one worker goes to the pantry, one leaves")
	_step(office, 1.0 / FPS, 5)
	office.switch_theme(_second_pack())
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "a new theme walks nobody")
	var body := _station(office, _pane("api:p1")).actor()
	var resting := _station(office, _pane("api:p1"))
	_eq(_floor_point(office, body), resting.position + resting.rest_position(), "the idle worker is in the pantry")
	_feed(office, fixture)
	_check(_walkers(office).size() == 2, "going back to the seat walks, and so does coming back")
	await _visit_floor(office, HerdrFleet.pane_key(BEE, "hive"))
	_eq(office.navigator.shown_key, BEE, "bee's map")
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "api"))
	_eq(office.navigator.shown_key, LOCAL, "and Local's again")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "another machine and back walks nobody")
	body = _station(office, _pane("api:p1")).actor()
	_eq(_floor_point(office, body), _seat_of(office, "api:p1"), "the worker sits where they belong")
	_done(office)


## What changed while the machine was away arrives with the first snapshot after
## it: placed, not walked. Whoever was walking is where they belong, and whoever
## was leaving is gone.
func test_a_reconnect_walks_nobody() -> void:
	var office := await _live_office()
	_feed(office, _without(_with(fixture, "api:p3", {"agent": "codex"}), "api:p2"))
	_check(not _walkers(office).is_empty() and not _ghosts(office).is_empty(), "someone walks in, someone out")
	_step(office, 1.0 / FPS, 10)
	_set_online(office, false)
	_eq(_ids(_ghosts(office)), [], "a dropped machine has no ghosts")
	# While stale, the snapshot moves on.
	_feed(office, _without(_with(fixture, "api:p3", {"agent": "codex"}), "api:p2"), false)
	_set_online(office, true)
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "reconnecting walks nobody")
	var body := _station(office, _pane("api:p3")).actor()
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "the arrival sits where they belong")
	_eq(str(body.look.context), "desk", "seated")
	_check(body.is_playing(), "and moving again")
	_done(office)


## A refresh whose input cannot be laid out updates nothing; the first one that
## can brings everything at once, and walks nobody.
func test_a_refresh_after_a_layout_problem_walks_nobody() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p3", {"agent": "codex"}))
	var arriving := _station(office, _pane("api:p3")).actor()
	_check(_walkers(office).has(arriving), "api:p3's worker walks in")
	var twice := _with(_with(fixture, "api:p3", {"agent": "codex"}), "api:p1", {"agent_status": "idle"})
	var repeated: Dictionary = _list(twice, "panes")[1]
	_list(twice, "panes").append(repeated.duplicate(true))
	_feed(office, twice)
	_check(not office.layout_problems().is_empty(), "the repeated pane cannot be laid out")
	_eq(_ids(_walkers(office)), _ids([arriving]), "nothing new moves for it; the walk under way goes on")
	_feed(office, _with(_with(fixture, "api:p3", {"agent": "codex"}), "api:p1", {"agent_status": "idle"}))
	_check(office.layout_problems().is_empty(), "the corrected input can")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "and walks nobody")
	var station := _station(office, _pane("api:p1"))
	_eq(
		_floor_point(office, station.actor()),
		station.position + station.rest_position(),
		"the idle worker is in the pantry"
	)
	_eq(station.rest, OfficeRests.Rest.PANTRY, "placed there")
	_done(office)


## A machine that drops freezes whoever is walking where they are: their place
## and the frame their animation shows stay put frame after frame, and nothing
## lands. Anyone on the way out is gone. The first snapshot after it is cold.
func test_a_stale_machine_freezes_walkers_where_they_are() -> void:
	var office := await _live_office()
	_feed(office, _without(_with(fixture, "api:p3", {"agent": "codex"}), "api:p2"))
	var body := _station(office, _pane("api:p3")).actor()
	_eq(_ghosts(office).size(), 1, "one worker walks out")
	var ghost: PixelPerson = _ghosts(office)[0] if not _ghosts(office).is_empty() else null
	for frame in 6:
		OS.delay_msec(20)
		await process_frame
	var moved := _floor_point(office, body)
	_check(moved != _door(office), "they really walk on the office's own frames: %s" % moved)
	_set_online(office, false)
	_check(ghost != null and (not is_instance_valid(ghost) or not ghost.is_inside_tree()), "the ghost is gone")
	var place := _floor_point(office, body)
	var frames := _layer_frames(body)
	for frame in 12:
		OS.delay_msec(20)
		await process_frame
		_eq(_floor_point(office, body), place, "frame %d: they stay where they stood" % frame)
		_eq(_layer_frames(body), frames, "frame %d: on the same frame of their walk" % frame)
	_check(place != _seat_of(office, "api:p3"), "short of the seat")
	_eq(body.track, ArtContract.TRACK_WALK, "still mid-stride")
	_set_online(office, true)
	_eq(_ids(_walkers(office)), [], "back again: nobody walks")
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "they are where they belong")
	_done(office)


# --- routes -----------------------------------------------------------------------


## A table that moves while someone walks to it (it grew too wide for its place)
## sends them on from where they are, to where the seat is now, with no jump.
## Four tabs make api a zone of two lanes, two tables to a pod row: api:t1,
## growing into api:t2 beside it, moves to a new row.
func test_a_table_that_moves_under_a_route_reroutes_its_walker() -> void:
	var office := await _wide_office(_four_tabs(fixture))
	var t1 := JSON.stringify([LOCAL, "api", "api:t1"])
	var t2 := JSON.stringify([LOCAL, "api", "api:t2"])
	var desks := office.layout_plan()
	_eq(desks.desk(t1).row, desks.desk(t2).row, "the wide floor puts both tables in one row")
	_feed(office, _four_tabs(_with(fixture, "api:p3", {"agent": "codex"})))
	var body := _station(office, _pane("api:p3")).actor()
	_step(office, 1.0 / FPS, 12)
	var here := _floor_point(office, body)
	var origin := office.layout_plan().desk(t1).origin
	_feed(office, _four_tabs(_grown(_with(fixture, "api:p3", {"agent": "codex"}), 3)))
	_check(office.layout_plan().desk(t1).origin != origin, "api:t1 grew out of its place and moved")
	_eq(_station(office, _pane("api:p3")).actor(), body, "the same worker")
	_check(_floor_point(office, body).is_equal_approx(here), "not moved by the move")
	var route := _route(office, body)
	_check(not route.is_empty() and route[0].is_equal_approx(here), "walking on from where they stood")
	_eq(_last(route), _seat_of(office, "api:p3"), "to the new seat")
	_walk_along(office, body, route, 1.0 / FPS)
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "and sit there")
	_done(office)


## A map that widens under someone walking can put an obstacle where they
## stand: a table too wide for its zone widens the map, the main corridor and
## the lift door move right, and the entry band's fixture-row barrier runs on
## over the old door's threshold. Whoever is inside it now is put where they
## belong at once; nobody walks through it.
func test_a_walker_the_floor_grows_over_is_put_where_they_belong() -> void:
	# api:t1 alone on the first row, api:t2 on the second (_stacked()).
	var office := await _live_office(_stacked(fixture))
	var grown: Dictionary = fixture.duplicate(true)
	var source: Dictionary = _list(grown, "panes")[3]
	var extra := source.duplicate(true)
	extra.pane_id = "api:p5"
	extra.terminal_id = "term-api-p5"
	_list(grown, "panes").append(extra)
	_feed(office, _stacked(grown))
	var body := _station(office, _pane("api:p5")).actor()
	var door := OfficeShell.door(office.layout_plan())
	var reached := false
	for frame in 400:
		_step(office, 1.0 / FPS)
		var at := _floor_point(office, body)
		if is_equal_approx(at.x, door.x) and at.y > 96.0 and at.y < 128.0:
			reached = true
			break
	_check(reached, "they come in through the fixture row at the lift door's column")
	var here := _floor_point(office, body)
	var width := office.layout_plan().floor_cells.size.x
	# Eleven agents: api:t1 a pod of 14 panes, 8 columns, 9 cells, more than a
	# lane's 8 inner cells: its zone takes two lanes and the map widens.
	_feed(office, _grown(grown, STACKED + 2))
	var plan := office.layout_plan()
	_check(plan.floor_cells.size.x > width, "api:t1 grew too wide for its zone and widened the map")
	_check(OfficeShell.door(plan).x > door.x, "the lift door moved right")
	var graph := OfficeWalkGraph.of(plan, PixelPerson.footprint(), PixelPerson.drawing_rect(office.art.people))
	_check(graph.inside(here), "the fixture-row barrier now runs where they stand")
	_check(not _walkers(office).has(body), "so they walk no further")
	_eq(_floor_point(office, body), _seat_of(office, "api:p5"), "and sit where they belong")
	_done(office)


## At the 8 frames a second of a minimized window a walker covers 12 units a
## frame and more: every frame puts them on their route, exactly speed x delta
## further along, round corners too.
func test_a_low_frame_rate_stays_on_the_route() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p3", {"agent": "codex"}))
	var body := _station(office, _pane("api:p3")).actor()
	var route := _route(office, body)
	var speed := _speed(office, body)
	var last := 0.0
	var corners := 0
	var frames := 0
	while not _walkers(office).is_empty() and frames < 200:
		var segment := _segment_of(_floor_point(office, body), route)
		_step(office, 1.0 / MINIMIZED_FPS)
		frames += 1
		var at := _floor_point(office, body)
		_check(_segment_of(at, route) >= 0, "frame %d: on the route at %s" % [frames, at])
		var along := _along(at, route)
		if not _walkers(office).is_empty():
			_check(
				is_equal_approx(along - last, speed / MINIMIZED_FPS),
				"frame %d: %s units further, not %s" % [frames, speed / MINIMIZED_FPS, along - last]
			)
			corners += 1 if _segment_of(at, route) > segment else 0
		last = along
	_check(corners >= 2, "round %d corners" % corners)
	_check(frames <= ceili(6.0 * MINIMIZED_FPS) + 1, "in six seconds: %d frames" % frames)
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "and on the seat at the end")
	_done(office)


## Every arrival on the stress fixture's floor (ten tabs of eight agents), 20 and
## 32 cells asked (two lanes either way), either walks all its route within six seconds at 8 frames a
## second, never faster than TOP_SPEED and never off its route, or, when even
## TOP_SPEED would take longer, is placed at once, seated: no route is cut
## short or jumped.
func test_no_walk_on_the_stress_floor_needs_a_teleport() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var pen := OfficeDraw.new(art)
	var longest_walk := OfficePresentation.TOP_SPEED * OfficePresentation.LONGEST_WALK
	for width: int in [20, 32]:
		var plans := FloorPlanCache.new()
		var empty := MapModel.of(_stress_model(false))
		var plan := plans.prepare(empty, pen, width * 32.0)
		# Its four-column pods (5 cells) fit one lane: the map is the one the
		# width asked holds, one lane (13 cells) at 20, two (23) at 32.
		var lanes := 1 if width == 20 else 2
		_eq(
			plan.floor_cells.size.x, 10 * lanes + 3, "the stress map, %d cells asked, is %d lanes wide" % [width, lanes]
		)
		var holder := Node2D.new()
		root.add_child(holder)
		var view := OfficeFloorView.new()
		view.setup(pen, holder)
		view.reconcile(plan, empty)
		view.update_desks(empty, "", false)
		var full := MapModel.of(_stress_model(true))
		var next := plans.prepare(full, pen, width * 32.0)
		view.reconcile(next, full)
		view.update_desks(full, "", false)
		var graph := OfficeWalkGraph.of(next, PixelPerson.footprint(), PixelPerson.drawing_rect(art.people))
		var walkers := view.presentation.walkers()
		var routes := {}
		var placed := 0
		var too_long := 0
		for key: String in view.seats:
			var station := view.seats[key].node
			var body := station.actor()
			var leg := _seat_leg_of(next, key)
			var whole := graph.from_door(OfficeWalkGraph.cell_of(leg[0]))
			whole.append_array(leg)
			var span := OfficeWalkGraph.length(OfficeWalkGraph.straighten(whole))
			too_long += 1 if span > longest_walk else 0
			if walkers.has(body):
				var route := view.presentation.route_of(body)
				routes[body] = route
				_check(
					OfficeWalkGraph.length(route) <= longest_walk,
					"%d cells: %s walks %d units at most" % [width, key, longest_walk]
				)
				_check(
					view.presentation.speed_of(body) <= OfficePresentation.TOP_SPEED,
					"%d cells: %s at TOP_SPEED at most" % [width, key]
				)
			else:
				placed += 1
				_check(
					span > longest_walk,
					"%d cells: %s is placed only when its walk would be too long: %d units" % [width, key, span]
				)
				_eq(
					view.sorted.to_local(body.global_position),
					station.position,
					"%d cells: %s is placed on its seat" % [width, key]
				)
				_eq(str(body.look.context), "desk", "%d cells: seated" % width)
		_eq(walkers.size() + placed, 80, "%d cells: all eighty come in, walking or placed" % width)
		_eq(placed, too_long, "%d cells: placed exactly those too far to walk in six seconds" % width)
		_eq(view.presentation.pass_placed, placed, "%d cells: and the observation counts them" % width)
		_check_routes(view, art.people, "%d cells, all coming in" % width)
		var frames := 0
		while not view.presentation.walkers().is_empty() and frames < 100:
			view.walk(1.0 / MINIMIZED_FPS)
			frames += 1
			for body: PixelPerson in view.presentation.walkers():
				var at := view.sorted.to_local(body.global_position)
				var route: PackedVector2Array = routes[body]
				if _segment_of(at, route) < 0:
					_fail("%d cells: %s left its route at %s" % [width, body.name, at])
		_check(
			frames <= ceili(6.0 * MINIMIZED_FPS) + 1,
			"%d cells: every walk ends in six seconds: %d frames" % [width, frames]
		)
		# Measured, for the record: how long the walks in are, and how fast.
		var lengths: Array = routes.values().map(
			func(route: PackedVector2Array) -> float: return OfficeWalkGraph.length(route)
		)
		lengths.sort()
		if lengths.is_empty():
			lengths.append(0.0)
		var shortest: float = lengths[0]
		var furthest: float = lengths[lengths.size() - 1]
		print(
			(
				"STRESS_ROUTES %d cells: %d walk in, %d placed, %.0f to %.0f units, %.1f to %.1f units/s, %d frames at 8 fps"
				% [
					width,
					routes.size(),
					placed,
					shortest,
					furthest,
					maxf(96.0, shortest / 6.0),
					maxf(96.0, furthest / 6.0),
					frames
				]
			)
		)
		root.remove_child(holder)
		holder.free()


## However many leave at once, at most MAX_GHOSTS are on their way out: beyond
## it the oldest are gone first.
func test_the_ghosts_are_capped_oldest_first() -> void:
	var crowd := _crowded(40)
	var office := await _live_office(crowd)
	var bodies: Array[PixelPerson] = []
	for index in 40:
		bodies.append(_station(office, _pane("crowd:p%02d" % index)).actor())
	_feed(office, _without_many(crowd, 0, 20))
	_eq(_ghosts(office).size(), 20, "twenty walk out")
	_feed(office, _without_many(crowd, 0, 40))
	var ghosts := _ghosts(office)
	_eq(
		ghosts.size(), OfficePresentation.MAX_GHOSTS, "forty leaving, %d are on the way" % OfficePresentation.MAX_GHOSTS
	)
	var dropped := 0
	for index in 40:
		var body := bodies[index]
		var gone := not is_instance_valid(body) or not body.is_inside_tree()
		dropped += 1 if gone else 0
		if index >= 20:
			_check(not gone and ghosts.has(body), "crowd:p%02d left last and is still walking" % index)
	_eq(dropped, 40 - OfficePresentation.MAX_GHOSTS, "the oldest ones are gone")
	_done(office)


# --- legs, kept walks, budgets, outages -------------------------------------------


## A near seat is walked into and out of beside the chair, never through it: in
## along the near lane to the standing spot's column, up to the spot and a
## sidestep into the seat; out by the same sidestep and down that column.
func test_a_near_seat_is_entered_and_left_beside_the_chair() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p3", {"agent": "codex"}))
	var station := _station(office, _pane("api:p3"))
	_eq(station.side, "near", "api:p3 sits on the near side")
	var body := station.actor()
	var leg := _seat_leg_of(office.layout_plan(), _pane("api:p3"))
	var seat := station.position
	_eq(leg.size(), 4, "the near seat leg: the approach, the spot's column, the spot, the seat")
	var route := _route(office, body)
	_eq(route.slice(route.size() - 3), leg.slice(1), "in: up the spot's column to the spot, a sidestep into the seat")
	_check(not _runs_along(route, seat.x), "nothing on the way in runs up the chair's column: %s" % [route])
	_walk_along(office, body, route, 1.0 / FPS)
	_eq(_floor_point(office, body), seat, "and they sit")
	_feed(office, fixture)
	var out := _route(office, body)
	var back := leg.slice(1)
	back.reverse()
	_eq(out.slice(0, 3), back, "out: a sidestep to the spot, then down its column")
	_check(not _runs_along(out, seat.x), "nothing on the way out runs down the chair's column: %s" % [out])
	_check_routes(office.floor_view, office.art.people, "leaving the near seat")
	_done(office)


## A walker a table grows over is placed, never walked through it. api:t1 a
## pod of five columns (6 cells) alone on its row leaves a passage inside the
## zone's right edge; growing it to eight columns at once (9 cells, more than a
## lane's 8 inner) widens its zone (and the map) and draws the pod on over that
## passage, where a newcomer was walking down beside it; the newcomer's pane
## closes in the same snapshot, and their ghost, standing inside the pod now, is
## gone at once. Every walk that is left keeps to the rules (_check_routes()).
func test_a_walker_a_table_moves_over_is_placed_not_walked_through() -> void:
	var office := await _live_office(_grown(fixture, 6))
	_feed(office, _grown(fixture, 7))
	var newcomer := _station(office, _pane("api:grow-6")).actor()
	var before := office.layout_plan().desk(JSON.stringify([LOCAL, "api", "api:t1"]))
	# Right of the pod, in the rows of the desks it will stand over: past the
	# middle of its depth, so the walk graph's nearest cell centre is on the
	# desk too (the far edge itself is a walkable row of centres; lane B1).
	var desk_rows := Vector2(before.origin.y - OfficeTable.SURFACE_DEPTH / 2.0, before.origin.y - 2)
	var desk_end := before.origin.x + before.measure.table_width
	var here := Vector2.INF
	for frame in 400:
		_step(office, 1.0 / FPS)
		var at := _floor_point(office, newcomer)
		if at.x > desk_end and at.y > desk_rows.x and at.y < desk_rows.y:
			here = at
			break
	_check(_walkers(office).has(newcomer), "the newcomer is walking down beside the table at %s" % here)
	_feed(office, _without(_grown(fixture, 14), "api:grow-6"))
	var table := office.layout_plan().desk(JSON.stringify([LOCAL, "api", "api:t1"]))
	var footprint := table.measure.physical_rect
	footprint.position += table.origin
	_check(footprint.has_point(here), "api:t1 stands where the newcomer was: %s in %s" % [here, footprint])
	_check(not is_instance_valid(newcomer) or not newcomer.is_inside_tree(), "so their ghost is gone at once")
	_eq(_ids(_ghosts(office)), [], "and nobody walks out through the table")
	_check(office.floor_view.presentation.pass_placed >= 1, "the observation placed them")
	_check_routes(office.floor_view, office.art.people, "after the table moved")
	_done(office)


## A plan change leaves alone every walk it does not touch: a worker walking in
## to api:t2 while a new tab's table takes a new pod row under the others (the
## zone grows down, the map as wide as it was) goes on along the very route
## they were on, from where they are, and nobody's route is searched for on the
## new floor.
func test_a_plan_change_keeps_the_walks_it_does_not_touch() -> void:
	# api:t1 alone on the first row (_stacked()), so it can grow where it is;
	# api alone on its map, so its zone can grow down (with the fixture's other
	# zones stacked below it in the one lane, it would move instead).
	var office := await _live_office(_only(_with(_stacked(fixture), "api:p4", {"agent": null}), "api"))
	_feed(office, _only(_stacked(fixture), "api"))
	var body := _station(office, _pane("api:p4")).actor()
	_step(office, 1.0 / FPS, 20)
	var here := _floor_point(office, body)
	var before := _route(office, body)
	var segment := _segment_of(here, before)
	var width := office.layout_plan().floor_cells.size.x
	var rows := office.layout_plan().zones[0].rows.size()
	# A new tab api:t3 of nine panes (5 columns, 6 cells): more than the 5 cells
	# api:t2 leaves on its pod row, so it takes a new one.
	var more := _only(_four_tabs(fixture, 1), "api")
	var seed_pane: Dictionary = _list(more, "panes").back()
	for index in 8:
		var extra: Dictionary = seed_pane.duplicate(true)
		extra.pane_id = "api:s0-%d" % index
		extra.terminal_id = "term-api-s0-%d" % index
		_list(more, "panes").append(extra)
	_feed(office, more)
	_eq(office.layout_plan().floor_cells.size.x, width, "the zone grew down: the map is as wide as before")
	_check(office.layout_plan().zones[0].rows.size() > rows, "a new pod row really came")
	var expected := PackedVector2Array([here])
	expected.append_array(before.slice(segment + 1))
	_eq(
		_route(office, body),
		OfficeWalkGraph.straighten(expected),
		"api:p4 walks on along their route, from where they are"
	)
	_eq(_floor_point(office, body), here, "not moved by the change")
	_check(office.floor_view.presentation.pass_kept >= 1, "the observation kept their walk")
	var graph := OfficeWalkGraph.of(
		office.layout_plan(), PixelPerson.footprint(), PixelPerson.drawing_rect(office.art.people)
	)
	_eq(graph.searches, 0, "and searched for nobody's route on the new floor")
	_check_routes(office.floor_view, office.art.people, "after api:t1 grew")
	_done(office)


## A worker whose place the floor moves is routed again with one search, from
## their goal, whichever of their ways back onto the graph they take: api:t1
## moves as it grows (into api:t2 beside it, in a zone of four tabs, two
## lanes), and its three workers, one of them still walking in, walk to their
## new seats on one search each; the three newcomers need none.
func test_a_rerouted_walker_takes_one_search() -> void:
	var office := await _wide_office(_four_tabs(fixture))
	var arriving := _with(fixture, "api:p3", {"agent": "codex"})
	_feed(office, _four_tabs(arriving))
	# Off the walking lane, into the zone: a walker still on the lane is routed
	# on off the door's field (the lane route), which takes no search at all.
	var newcomer := _station(office, _pane("api:p3")).actor()
	for frame in 400:
		_step(office, 1.0 / FPS)
		if _floor_point(office, newcomer).y > 192.0:
			break
	_check(_walkers(office).has(newcomer), "api:p3 is still walking in, inside the zone")
	var origin := office.layout_plan().desk(JSON.stringify([LOCAL, "api", "api:t1"])).origin
	_feed(office, _four_tabs(_grown(arriving, 3)))
	var plan := office.layout_plan()
	_check(plan.desk(JSON.stringify([LOCAL, "api", "api:t1"])).origin != origin, "api:t1 moved as it grew")
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		_check(office.floor_view.presentation.is_walking(_pane(pane_id)), pane_id + " walks to the new seat")
	var graph := OfficeWalkGraph.of(plan, PixelPerson.footprint(), PixelPerson.drawing_rect(office.art.people))
	_eq(graph.searches, 3, "one search for each of the three routed again")
	_check_routes(office.floor_view, office.art.people, "after api:t1 moved")
	_done(office)


## Routing is budgeted per observation. With the budget lowered to almost
## nothing, the stress floor widening under eighty walkers routes whoever the
## budget covers and places the rest where they belong, spending no more than
## the budget; everyone else keeps to the rules. With the budget as shipped, the
## same pass stays within it too.
func test_routing_stops_at_its_budget_and_places_the_rest() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var pen := OfficeDraw.new(art)
	for budget: int in [400, OfficePresentation.ROUTING_BUDGET]:
		var plans := FloorPlanCache.new()
		var empty := MapModel.of(_stress_model(false))
		var holder := Node2D.new()
		root.add_child(holder)
		var view := OfficeFloorView.new()
		view.setup(pen, holder)
		view.reconcile(plans.prepare(empty, pen, 20 * 32.0), empty)
		view.update_desks(empty, "", false)
		var full := MapModel.of(_stress_model(true))
		view.reconcile(plans.prepare(full, pen, 20 * 32.0), full)
		view.update_desks(full, "", false)
		for frame in 30:
			view.walk(1.0 / FPS)
		var walking := view.presentation.walkers().size()
		_check(walking > 40, "budget %d: %d walk in" % [budget, walking])
		view.presentation.routing_budget = budget
		# 28 more on tab 0: a pod of 18 desks, 19 cells, over a 20-cell floor's 16.
		var grown := MapModel.of(_stress_model(true, 28))
		var next := plans.prepare(grown, pen, 20 * 32.0)
		_check(next.floor_cells.size.x > 20, "budget %d: tab 0 grew too wide and widened the floor" % budget)
		var graph := OfficeWalkGraph.of(next, PixelPerson.footprint(), PixelPerson.drawing_rect(art.people))
		var work := graph.expanded
		view.reconcile(next, grown)
		view.update_desks(grown, "", false)
		var presentation := view.presentation
		_check(graph.expanded - work <= budget, "budget %d: spent %d" % [budget, graph.expanded - work])
		_eq(presentation.pass_expanded, graph.expanded - work, "budget %d: the pass counts the graph's work" % budget)
		if budget < OfficePresentation.ROUTING_BUDGET:
			_check(
				presentation.pass_placed > 0, "budget %d: the rest are placed: %d" % [budget, presentation.pass_placed]
			)
		for key: String in view.seats:
			var station := view.seats[key].node
			var body := station.actor()
			if body == null or presentation.walkers().has(body):
				continue
			_eq(body.position, station.rest_position(), "budget %d: %s, placed, is where they belong" % [budget, key])
			_eq(body.paced(), 1.0, "budget %d: %s at rest at the family's pace" % [budget, key])
		_check_routes(view, art.people, "budget %d, the floor widened" % budget)
		print(
			(
				"ROUTING_BUDGET %d: %d walking when the floor widened: %d walk, %d kept, %d placed, %d expanded, %.1f ms"
				% [
					budget,
					walking,
					presentation.pass_walked,
					presentation.pass_kept,
					presentation.pass_placed,
					presentation.pass_expanded,
					presentation.pass_usec / 1000.0
				]
			)
		)
		root.remove_child(holder)
		holder.free()


## A machine that comes back with a snapshot that cannot be laid out presents
## nothing, so its walkers stay as the outage left them, in place and on the
## same frame of their walk, frame after frame; the first observation presented
## after that places everybody where they belong, moving again.
func test_a_reconnect_with_a_layout_problem_keeps_walkers_frozen() -> void:
	var office := await _live_office()
	var arriving := _with(fixture, "api:p3", {"agent": "codex"})
	_feed(office, arriving)
	var body := _station(office, _pane("api:p3")).actor()
	for frame in 6:
		OS.delay_msec(20)
		await process_frame
	_set_online(office, false)
	var twice: Dictionary = arriving.duplicate(true)
	var repeated: Dictionary = _list(twice, "panes")[1]
	_list(twice, "panes").append(repeated.duplicate(true))
	_feed(office, twice, false)
	_set_online(office, true)
	_check(not office.stale, "the machine is back")
	_check(not office.layout_problems().is_empty(), "with a snapshot that cannot be laid out")
	var place := _floor_point(office, body)
	var frames := _layer_frames(body)
	_check(place != _seat_of(office, "api:p3"), "short of the seat")
	for frame in 12:
		OS.delay_msec(20)
		await process_frame
		_eq(_floor_point(office, body), place, "frame %d: they stay where the outage left them" % frame)
		_eq(_layer_frames(body), frames, "frame %d: on the same frame of their walk" % frame)
	_check(not body.is_playing(), "their walk still paused")
	_feed(office, arriving)
	_eq(_ids(_walkers(office)), [], "the first observation presented walks nobody")
	_eq(_floor_point(office, body), _seat_of(office, "api:p3"), "they are on the seat")
	_check(body.is_playing(), "and moving again")
	_done(office)


## A walk's pace never outlasts the walk: a worker walking in, faster than the
## walk track's own pace, while their machine drops, whose pane then gets
## another agent, is seated at the family's own pace, like any seated worker
## and like a rebuild.
func test_a_stale_provider_swap_leaves_no_walk_pace() -> void:
	# api:t2 on the second row (_stacked()), 880 wide: two lanes, the lift door
	# ten cells further right than PLAN_SCREEN's one lane puts it, a walk long
	# enough to be paced up (one lane's is not, with pod rows 6 cells deep).
	var office := await _live_office(_with(_stacked(fixture), "api:p4", {"agent": null}), Vector2(880, 480))
	_feed(office, _stacked(fixture))
	var body := _station(office, _pane("api:p4")).actor()
	_check(body.paced() > 1.0, "api:p4 walks in faster than the walk's own pace: %s" % body.paced())
	_step(office, 1.0 / FPS, 10)
	_set_online(office, false)
	_feed(office, _with(_stacked(fixture), "api:p4", {"agent": "codex"}), false)
	var worker := _station(office, _pane("api:p4")).actor()
	_eq(worker.paced(), 1.0, "the seated worker plays at the family's own pace")
	await _same_as_rebuild(office, "after another agent took the pane while stale")
	_done(office)


## A seeded run of observations of the api floor (FuzzState), outages and theme
## switches, each followed by a random stretch of walking. After every step:
## one body per worker and ghost, nobody marked walking without a walk,
## everyone at rest where they belong at the family's own pace, frozen walkers
## not moving, no ghosts while stale, reconnects and themes placing everyone,
## routing within its budget, and every live route keeping to the rules
## (_check_routes()). At the end every walk ends and the floor is what a
## rebuild draws. Seeds 71, 151 and 168 walked a ghost through its own table
## before the entries; the others are for breadth.
func test_a_seeded_lifecycle_keeps_every_invariant() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value: int in [71, 151, 168, 5, 42]:
		rng.seed = 1000 + seed_value
		var office := await _live_office()
		var frozen := false
		for step in 25:
			var roll := rng.randf()
			var when := "seed %d step %d" % [seed_value, step]
			if roll < 0.12:
				frozen = not frozen
				_set_online(office, not frozen)
				if not frozen:
					_eq(_ids(_walkers(office)), [], when + ": a reconnect places everybody")
			elif roll < 0.16:
				var theme: String = [MANIFESTS[0], _second_pack()][rng.randi() % 2]
				office.switch_theme(theme)
				_eq(_ids(_walkers(office)), [], when + ": a new theme places everybody")
			else:
				var state := _random_state(rng)
				if not frozen:
					_feed(office, _variant(state))
					var presentation := office.floor_view.presentation
					_check(
						presentation.pass_expanded <= presentation.routing_budget,
						when + ": routing within its budget: %d" % presentation.pass_expanded
					)
			when += " (stale)" if frozen else ""
			_check_invariants(office, when + ", observed", frozen)
			if not frozen:
				_check_routes(office.floor_view, office.art.people, when + ", observed")
			var stood: Dictionary[int, Vector2] = {}
			if frozen:
				for body in _walkers(office):
					stood[body.get_instance_id()] = body.global_position
			_step(office, 1.0 / FPS, rng.randi() % 40)
			if frozen:
				for body in _walkers(office):
					if stood.has(body.get_instance_id()) and body.global_position != stood[body.get_instance_id()]:
						_fail(when + ": a frozen walker moved")
			_check_invariants(office, when + ", walked", frozen)
			if not frozen:
				_check_routes(office.floor_view, office.art.people, when + ", walked")
		if frozen:
			_set_online(office, true)
		_step(office, 1.0 / FPS, 200)
		_check_invariants(office, "seed %d, at the end" % seed_value, false)
		_eq(_ids(_walkers(office)), [], "seed %d: every walk ends" % seed_value)
		await _same_as_rebuild(office, "seed %d, at the end" % seed_value)
		_done(office)


# --- clicks and depth -------------------------------------------------------------


## A ghost answers no click, and neither does the seat it left: a real click on
## either picks nothing. A worker still walking in is picked at their seat, as
## any worker is.
func test_clicks_pick_nobody_leaving_and_anybody_arriving() -> void:
	var office := await _live_office()
	await _click_desk(office, _pane("api:p1"))
	_eq(office.picked_key, _pane("api:p1"), "api:p1 is picked first")
	var emptied := _station(office, _pane("api:p2"))
	var seat_click := emptied.target_rect().get_center()
	_feed(office, _without(_with(fixture, "api:p3", {"agent": "codex"}), "api:p2"))
	_eq(_ghosts(office).size(), 1, "api:p2's worker walks out")
	if _ghosts(office).is_empty():
		_done(office)
		return
	var ghost: PixelPerson = _ghosts(office)[0]
	await _click(ghost.global_position + Vector2(0, -20) - office.camera.position)
	_eq(office.picked_key, _pane("api:p1"), "a click on the ghost picks nothing")
	await _click(seat_click - office.camera.position)
	_eq(office.picked_key, _pane("api:p1"), "nor does one on the seat it left")
	_step(office, 1.0 / FPS, 20)
	await _click(ghost.global_position + Vector2(0, -20) - office.camera.position)
	_eq(office.picked_key, _pane("api:p1"), "nor on the ghost further on its way")
	var arriving := _station(office, _pane("api:p3")).actor()
	_check(_walkers(office).has(arriving), "api:p3's worker is still walking in")
	await _click_desk(office, _pane("api:p3"))
	_eq(office.picked_key, _pane("api:p3"), "and their seat picks them")
	_done(office)


## Walking between two rows of tables, a worker sorts by their own feet: in
## front of the table behind them and behind the one in front, through nothing
## that is not y-sorted.
func test_a_walker_between_two_tables_sorts_by_their_feet() -> void:
	# api:t1 on the first row, api:t2 behind it on the second (_stacked()).
	var office := await _live_office(_stacked(fixture))
	var grown: Dictionary = fixture.duplicate(true)
	var source: Dictionary = _list(grown, "panes")[3]
	var extra := source.duplicate(true)
	extra.pane_id = "api:p5"
	extra.terminal_id = "term-api-p5"
	_list(grown, "panes").append(extra)
	_feed(office, _stacked(grown))
	var body := _station(office, _pane("api:p5")).actor()
	# api's two tables (the map's other zones have theirs).
	var tables: Array[OfficeTable] = []
	for tab: String in ["api:t1", "api:t2"]:
		tables.append(office.floor_view.desks[JSON.stringify([LOCAL, "api", tab])].table)
	tables.sort_custom(func(a: OfficeTable, b: OfficeTable) -> bool: return a.global_position.y < b.global_position.y)
	_check(tables.size() == 2, "two tables, one behind the other")
	var between := false
	for frame in 400:
		_step(office, 1.0 / FPS)
		var y := body.global_position.y
		if y > tables[0].global_position.y + 8.0 and y < tables[1].global_position.y - 8.0:
			between = true
			break
	_check(between, "the walk passes between the tables")
	_check(tables[0].global_position.y < body.global_position.y, "in front of the table behind them")
	_check(body.global_position.y < tables[1].global_position.y, "behind the table in front of them")
	_eq(_entity_of(office.floor_view.sorted, body), body, "sorted as themselves, by their own feet")
	_done(office)


## The agent card shows the person at the seat: two Claude panes on one floor,
## each picked by a real click, and each card's portrait resolves to that pane's
## seated worker, slot by slot. The two panes are two people.
func test_the_card_portrait_is_the_person_at_the_seat() -> void:
	var two := _with(fixture, "api:p2", {"agent": "claude", "agent_status": "working"})
	var office := await _live_office(two)
	await _frames(2)
	var inspector := office.hud.inspector
	var looks: Array[AvatarLook] = []
	for pane_id: String in ["api:p2", "api:p1"]:
		var key := HerdrFleet.pane_key(LOCAL, pane_id)
		await _click_desk(office, key)
		await _frames(2)
		_eq(office.picked_key, key, "%s is picked by the click" % pane_id)
		var seated := _station(office, key).actor()
		var portrait := inspector.portrait()
		_check(seated != null and portrait != null, "%s has a seated worker and a card portrait" % pane_id)
		if seated == null or portrait == null:
			continue
		_eq(portrait.provider, "claude", "%s's card is claude's" % pane_id)
		for slot in AvatarLook.SLOTS:
			_eq(portrait.look.slot(slot), seated.look.slot(slot), "%s: the card's %s is the seat's" % [pane_id, slot])
		looks.append(seated.look)
	if looks.size() == 2:
		var differ: Array[StringName] = []
		for slot: StringName in office.art.people.variation:
			if looks[0].slot(slot) != looks[1].slot(slot):
				differ.append(slot)
		_check(not differ.is_empty(), "the two Claude panes differ in a varied slot: %s" % [differ])
	_done(office)


## A seat whose worker stays but whose pane key changes (same provider) dresses
## the worker for the new pane: the look follows the key, never the node.
func test_a_seat_s_worker_follows_its_pane_key() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var pen := OfficeDraw.new(art)
	var ground := Node2D.new()
	root.add_child(ground)
	var table := pen.table(ground, ground, "Table0", Vector2.ZERO, 160.0, [80.0])
	var station := pen.station(ground, table, 0, "far")
	var keys: Array[String] = [HerdrFleet.pane_key(LOCAL, "api:p1"), HerdrFleet.pane_key(LOCAL, "api:p2")]
	var seen: Array[String] = []
	for key in keys:
		station.pane_key = key
		station.furnish("claude", ArtContract.STATE_WORKING)
		var worker := station.actor()
		_eq(worker.variation_key, key, "the worker is varied by the seat's pane key")
		var expected := art.people.look_for("claude", null, key)
		for slot in AvatarLook.SLOTS:
			_eq(worker.look.slot(slot), expected.slot(slot), "%s for %s" % [slot, key])
		seen.append(worker.look.clothes().key())
	_check(seen[0] != seen[1], "a new pane key, a new person")
	ground.free()


## `snapshot` with more tabs on the api floor, one shell each (api:t3, api:t4,
## ... `count` of them, two by default): four small tables make api a zone of
## two lanes, two tables to a pod row, which the zone's height preference asks for.
func _four_tabs(snapshot: Dictionary, count := 2) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var source: Dictionary = {}
	for pane: Dictionary in _list(result, "panes"):
		if pane.pane_id == "api:p4":
			source = pane
	for index in count:
		var tab := "api:t%d" % (index + 3)
		_list(result, "tabs").append({"tab_id": tab, "workspace_id": "api", "number": index + 3, "label": "more"})
		var pane := source.duplicate(true)
		pane.pane_id = "api:s%d" % index
		pane.tab_id = tab
		pane.terminal_id = "term-api-s%d" % index
		pane.erase("agent")
		pane.erase("agent_status")
		_list(result, "panes").append(pane)
	return result
