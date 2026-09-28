extends "res://tools/test_base.gd"
## OfficeNavigator and OfficeFrame as pure objects: which desk is selected and
## which floor is shown, decided from frames made straight from the fixture
## snapshots, and the command line the office starts from. No office, no scene,
## no herdr. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_office_navigator.gd

const LOCAL := HerdrFleet.LOCAL
const BEE := "socket:bee"

## tools/fixtures/snapshot_floors.json, which Local serves: focus on api:p1,
## blocked agents on web and infra, UNREAD ones on web and infra.
var floors: Dictionary = {}
## tools/fixtures/snapshot_basic.json, which bee serves: a blocked pi on bravo.
var basic: Dictionary = {}


func _initialize() -> void:
	floors = _fixture("snapshot_floors")
	basic = _fixture("snapshot_basic")
	if floors.is_empty() or basic.is_empty():
		print("TEST_HARNESS_ERROR: cannot read the office fixtures")
		quit(2)
		return
	run_cases()


func _marker() -> String:
	return "OFFICE NAVIGATOR TESTS"


func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/%s.json" % name))
	if parsed is not Dictionary:
		return {}
	var file: Dictionary = parsed
	return _dict(file, "snapshot")


## Local serving `local`, and bee serving `bee` when there is one.
func _frame(local: Dictionary, bee: Dictionary = {}, bee_stale := false) -> OfficeFrame:
	var machines: Array[MachineView] = [MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(local), false)]
	if not bee.is_empty():
		machines.append(MachineView.new(BEE, "bee", HerdrSnapshot.from_wire(bee), bee_stale))
	return OfficeProjection.frame(machines, PackedStringArray(["working", "blocked", "done", "idle", "unknown"]))


func _local(id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, id)


func _bee(id: String) -> String:
	return HerdrFleet.pane_key(BEE, id)


## `raw` with one pane's fields changed.
func _with(raw: Dictionary, pane_id: String, changes: Dictionary) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	for pane: Dictionary in _list(result, "panes"):
		if str(pane.get("pane_id", "")) == pane_id:
			pane.merge(changes, true)
	return result


## `raw` without one workspace, so the floor it was goes away.
func _without(raw: Dictionary, workspace_id: String) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	result.workspaces = _list(result, "workspaces").filter(
		func(space: Dictionary) -> bool: return str(space.get("workspace_id", "")) != workspace_id
	)
	return result


## A navigator showing `key` of `frame`, as the office leaves one after a refresh.
func _showing(frame: OfficeFrame, key: String) -> OfficeNavigator:
	var navigator := OfficeNavigator.new()
	navigator.settle(frame)
	navigator.show_floor(frame, key, Vector2.ZERO)
	return navigator


# --- the frame ----------------------------------------------------------------


## One projection answers every lookup a refresh makes: each pane once by key,
## the floor it sits on, the floors in PageUp order, the live panes and herdr's
## focus, Local's first. A dropped machine's panes are not live, but the
## inspector still knows them.
func test_the_frame_indexes_one_projection() -> void:
	var frame := _frame(floors, basic)
	_eq(
		frame.buildings.map(func(building: BuildingModel) -> String: return building.key),
		[LOCAL, BEE],
		"one building per machine, Local first"
	)
	_eq(frame.pane_by_key.size(), 17, "every pane of both machines, by key")
	_eq(frame.pane(_local("web:p1")).workspace_label, "web", "each with its workspace's label")
	_eq(frame.pane(_local("web:p1")).tab_label, "ui", "and its tab's")
	_eq(frame.floor_of(_local("infra:p2")), _local("infra"), "the floor a desk sits on")
	_eq(frame.floor_of(_bee("bravo:p1")), _bee("bravo"), "on either machine")
	_eq(frame.floor_order.size(), 7, "five Local floors and bee's two, bottom to top")
	_eq(frame.floor_order[5], _bee("alpha"), "the next building's lowest after Local's top")
	_eq(frame.herdr_focus, _local("api:p1"), "Local's focus first")
	_eq(frame.live_panes.size(), 17, "both machines are live")
	_check(frame.several_machines() and not _frame(floors).several_machines(), "several machines only past Local")
	var dropped := _frame(floors, basic, true)
	_eq(dropped.live_panes.size(), 13, "a dropped machine's panes are not live")
	_check(dropped.pane(_bee("bravo:p1")) != null, "but the inspector still knows them")


## The buildings-only lookups OfficeProjection keeps are the frame's own answers.
func test_the_projection_lookups_are_the_frames() -> void:
	var frame := _frame(floors, basic)
	var buildings := frame.buildings
	for key: String in [_local("web:p1"), _bee("alpha:p1"), _local("nobody"), ""]:
		_eq(OfficeProjection.floor_of(buildings, key), frame.floor_of(key), "floor_of %s" % key)
	_eq(OfficeProjection.floor_order(buildings), frame.floor_order, "floor_order")
	_eq(
		OfficeProjection.find_floor(buildings, _bee("bravo")).building.key,
		frame.find_floor(_bee("bravo")).building.key,
		"find_floor"
	)
	for picked: String in ["", _local("infra"), _local("gone")]:
		_eq(
			OfficeProjection.choose_floor(buildings, picked, _bee("bravo:p1")),
			frame.choose_floor(picked, _bee("bravo:p1")),
			"choose_floor from %s" % picked
		)
	_eq(
		OfficeProjection.effective_selection(buildings, _bee("alpha:p2"), frame.herdr_focus),
		frame.effective_selection(_bee("alpha:p2")),
		"effective_selection"
	)


# --- the selection and the floor ----------------------------------------------


## Herdr's focus is followed until the viewer picks a desk. A picked desk pulls
## its floor into view; once it is gone the selection goes back to the focus.
func test_the_selection_follows_focus_until_a_desk_is_picked() -> void:
	var navigator := OfficeNavigator.new()
	var frame := _frame(floors)
	_eq(navigator.settle(frame), _local("api"), "herdr's focus is on api")
	_eq(navigator.active_key, _local("api:p1"), "and is the selection")
	navigator.pick_desk(_local("web:p1"))
	_eq(navigator.settle(frame), _local("web"), "a picked desk pulls its floor into view")
	_eq(navigator.active_key, _local("web:p1"), "and is selected")
	var gone: Dictionary = floors.duplicate(true)
	gone.panes = _list(gone, "panes").filter(
		func(pane: Dictionary) -> bool: return str(pane.get("pane_id", "")) != "web:p1"
	)
	_eq(navigator.settle(_frame(gone)), _local("api"), "once it is gone, herdr's focus wins again")
	_eq(navigator.active_key, _local("api:p1"), "and is selected")
	_eq(navigator.picked_key, _local("web:p1"), "while the pick itself is remembered")


## A pane herdr knows but no floor can seat stays selected when picked: the
## inspector keeps its details, and the floor shown is the first real one.
func test_an_unplaced_pick_stays_selected() -> void:
	var frame := _frame(_with(floors, "notes:p1", {"workspace_id": "web"}))
	_eq(frame.floor_of(_local("notes:p1")), "", "the pane claims a workspace its tab is not in")
	var navigator := OfficeNavigator.new()
	navigator.pick_desk(_local("notes:p1"))
	_eq(navigator.settle(frame), _local("api"), "its floor is unknown, so the first floor is shown")
	_eq(navigator.active_key, _local("notes:p1"), "but it stays the selection")


## A floor the viewer picked wins over the selection's floor until it goes away,
## and then it is forgotten rather than waited for.
func test_a_picked_floor_wins_until_it_goes_away() -> void:
	var navigator := OfficeNavigator.new()
	navigator.pick_floor(_local("infra"))
	_eq(navigator.settle(_frame(floors)), _local("infra"), "the picked floor is shown")
	_eq(navigator.settle(_frame(_without(floors, "infra"))), _local("api"), "gone, the selection's floor is")
	_eq(navigator.picked_floor, "", "and the pick is forgotten")
	_eq(navigator.settle(_frame(floors)), _local("api"), "so it does not come back with the floor")


## `--floor=<number>` names a Local floor by herdr's number, which only means
## something once Local has floors; it is used once.
func test_a_floor_number_waits_for_local() -> void:
	var navigator := OfficeNavigator.new()
	navigator.wanted_floor = AppArgs.parse(PackedStringArray(["--floor=3"])).number("floor", -1)
	_eq(navigator.settle(_frame({})), OfficeProjection.lobby(LOCAL).key, "before Local has floors, its lobby")
	_eq(navigator.wanted_floor, 3, "and the number waits")
	_eq(navigator.settle(_frame(floors)), _local("infra"), "the third floor once Local has it")
	_eq(navigator.wanted_floor, -1, "and only once")
	navigator.pick_floor(_local("web"))
	_eq(navigator.settle(_frame(floors)), _local("web"), "a later pick is the viewer's own")


# --- switching floors ---------------------------------------------------------


## A floor the viewer picks is the floor to show at once: nothing holds the
## one shown before, and a newer pick simply wins; nothing is pinned.
func test_a_new_choice_is_shown_at_once() -> void:
	var frame := _frame(floors)
	var navigator := OfficeNavigator.new()
	_eq(navigator.settle(frame), _local("api"), "the selection's floor first")
	navigator.show_floor(frame, _local("api"), Vector2.ZERO)
	navigator.pick_floor(_local("web"))
	_eq(navigator.settle(frame), _local("web"), "a pick is the floor to show")
	navigator.pick_floor(_local("notes"))
	_eq(navigator.settle(frame), _local("notes"), "and a newer one wins at once")
	navigator.show_floor(frame, _local("notes"), Vector2.ZERO)
	_eq(navigator.shown_key, _local("notes"), "shown")
	navigator.pick_floor(_local("api"))
	_eq(navigator.settle(frame), _local("api"), "down again the same way")


## PageUp/PageDown walk every floor bottom to top, from a building's top floor
## into the next building's lowest, and stop at either end.
func test_page_up_and_down_walk_the_buildings_and_stop_at_the_ends() -> void:
	var frame := _frame(floors, basic)
	var navigator := _showing(frame, _local("api"))
	_eq(navigator.step_floor(frame, -1), "", "nothing below the ground floor")
	_eq(navigator.step_floor(frame, 1), _local("web"), "one up")
	navigator.show_floor(frame, _local("data"), Vector2.ZERO)
	_eq(navigator.step_floor(frame, 1), _bee("alpha"), "Local's top floor leads into bee's lowest")
	navigator.show_floor(frame, _bee("bravo"), Vector2.ZERO)
	_eq(navigator.step_floor(frame, 1), "", "nothing above the top")
	_eq(navigator.step_floor(frame, -1), _bee("alpha"), "and back down")


## The building section draws the highest floor on top and hangs each
## worktree's mezzanines just below the floor they were made from, in letter
## order; PageUp/PageDown follow that same picture.
func test_steps_follow_the_section_with_its_mezzanines() -> void:
	var worktrees := _fixture("snapshot_worktrees")
	var frame := _frame(worktrees, basic)
	var navigator := _showing(frame, _local("hs"))
	_eq(navigator.step_floor(frame, -1), _local("hud"), "down from a source floor into its first mezzanine")
	navigator.show_floor(frame, _local("data"), Vector2.ZERO)
	_eq(navigator.step_floor(frame, -1), "", "the last mezzanine of the lowest floor is the bottom")
	_eq(navigator.step_floor(frame, 1), _local("hud"), "up the mezzanines")
	navigator.show_floor(frame, _local("hud"), Vector2.ZERO)
	_eq(navigator.step_floor(frame, 1), _local("hs"), "back to their source")
	navigator.show_floor(frame, _local("hs"), Vector2.ZERO)
	_eq(navigator.step_floor(frame, 1), _local("notes"), "and on to the floor above")


## Each floor keeps where the viewer left it panned; a floor seen for the first
## time opens on the selection's table instead; a floor that goes away forgets.
func test_each_floor_keeps_its_pan_until_it_goes_away() -> void:
	var frame := _frame(floors)
	var navigator := _showing(frame, _local("api"))
	_check(navigator.reveals_table(true), "a floor seen for the first time opens on the selection's table")
	navigator.show_floor(frame, _local("web"), Vector2(10, 20))
	_check(navigator.reveals_table(true), "so does the next one")
	navigator.show_floor(frame, _local("api"), Vector2(30, 40))
	_eq(navigator.pan_of(_local("api")), Vector2(10, 20), "api is where it was left")
	_check(not navigator.reveals_table(true), "and keeps that pan")
	_check(not navigator.reveals_table(false), "nothing is revealed without a change of floor")
	_eq(navigator.pan_of(_local("web")), Vector2(30, 40), "web remembers its own")
	navigator.settle(_frame(_without(floors, "web")))
	_eq(navigator.pan_of(_local("web")), Vector2.ZERO, "until it goes away")


# --- who needs a human --------------------------------------------------------


## `N` walks everyone who needs a human across the live machines, the blocked
## only while anyone is (the UNREAD once nobody is, see
## test_the_done_join_the_queue_when_nobody_is_blocked), and wraps around. Each
## press picks the pane, its floor and a reveal.
func test_n_walks_everyone_who_needs_a_human_and_wraps() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "web", "agent": "pi", "agent_status": "blocked"})
	var frame := _frame(local, basic)
	var navigator := OfficeNavigator.new()
	var seen: Array = []
	for press in 7:
		var peeked := navigator.peek_next(frame)
		var before := navigator.picked_key
		_eq(navigator.peek_next(frame), peeked, "press %d: peeking twice names the same" % press)
		_eq(navigator.picked_key, before, "press %d: and picks nothing" % press)
		_check(navigator.next_human(frame), "press %d finds someone" % press)
		_eq(navigator.picked_key, peeked, "press %d picks whom peek_next() named" % press)
		_eq(navigator.reveal_on_arrival, navigator.picked_key, "press %d reveals whom it picked" % press)
		seen.append([navigator.picked_key, navigator.picked_floor])
	_eq(
		seen,
		[
			[_local("web:p1"), _local("web")],
			[_local("infra:p1"), _local("infra")],
			[_bee("bravo:p1"), _bee("bravo")],
			[_local("notes:p1"), ""],
			[_local("web:p1"), _local("web")],
			[_local("infra:p1"), _local("infra")],
			[_bee("bravo:p1"), _bee("bravo")],
		],
		"the blocked, the unplaced pane among them, then around again, never to the UNREAD"
	)
	# The pane no floor seats waits in the same order as the seated
	# (OfficeNavigator.waiting()): blocked, it comes after the seated whose
	# starts are as unknown as its.
	var dropped := _frame(floors, basic, true)
	navigator.picked_key = _local("infra:p2")
	navigator.next_human(dropped)
	_eq(navigator.picked_key, _local("web:p1"), "a dropped machine's agents are nobody's to answer")
	var quiet := _frame(_with(basic, "bravo:p1", {"agent_status": "working"}))
	navigator.picked_key = ""
	_eq(navigator.peek_next(quiet), "", "with nobody waiting, nobody is next")
	_check(not navigator.next_human(quiet), "with nobody waiting, `N` does nothing")
	_eq(navigator.picked_key, "", "and picks nothing")


## `‹` (peek_prev(), step(-1)) walks NEXT's queue backwards: from
## a pick in it, the one before, wrapping from the first to the last; from a
## selection outside it (nobody, or a working agent), the last. While anyone is
## blocked the queue is the blocked only, so the last is the last
## blocked. step(+1) picks whom peek_next() names. Each step picks, shows the
## floor and reveals, as `N` does; with nobody waiting it picks nothing.
func test_peek_prev_walks_the_queue_backwards_and_wraps() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "web", "agent": "pi", "agent_status": "blocked"})
	var frame := _frame(local, basic)
	var navigator := OfficeNavigator.new()
	navigator.picked_key = ""
	# The end is the last blocked, not the last UNREAD (infra:p2).
	_eq(navigator.peek_prev(frame), _local("notes:p1"), "from nobody, going back starts from the end")
	navigator.picked_key = _local("api:p1")
	_eq(navigator.peek_prev(frame), _local("notes:p1"), "and from a selection outside the queue")
	var back: Array = []
	for press in 7:
		var peeked := navigator.peek_prev(frame)
		var before := navigator.picked_key
		_eq(navigator.peek_prev(frame), peeked, "back %d: peeking twice names the same" % press)
		_eq(navigator.picked_key, before, "back %d: and picks nothing" % press)
		_check(navigator.step(frame, -1), "back %d finds someone" % press)
		_eq(navigator.picked_key, peeked, "back %d picks whom peek_prev() named" % press)
		_eq(navigator.reveal_on_arrival, peeked, "back %d reveals whom it picked" % press)
		back.append([navigator.picked_key, navigator.picked_floor])
	_eq(
		back,
		[
			[_local("notes:p1"), ""],
			[_bee("bravo:p1"), _bee("bravo")],
			[_local("infra:p1"), _local("infra")],
			[_local("web:p1"), _local("web")],
			[_local("notes:p1"), ""],
			[_bee("bravo:p1"), _bee("bravo")],
			[_local("infra:p1"), _local("infra")],
		],
		"N's queue read backwards, and round again from its first to its last"
	)
	navigator.picked_key = _local("web:p1")
	var next := navigator.peek_next(frame)
	_check(navigator.step(frame, 1), "a step on finds someone")
	_eq(navigator.picked_key, next, "whom peek_next() named")
	_eq(next, _local("infra:p1"), "the one after web:p1")
	var quiet := _frame(_with(basic, "bravo:p1", {"agent_status": "working"}))
	navigator.picked_key = _local("api:p1")
	_eq(navigator.peek_prev(quiet), "", "with nobody waiting, nobody is before")
	_check(not navigator.step(quiet, -1) and not navigator.step(quiet, 1), "and neither step does anything")
	_eq(navigator.picked_key, _local("api:p1"), "the pick stays")


## While anyone is blocked, NEXT's queue is
## the blocked only, Civilization's turn blockers. Local's blocked web:p1
## (since 100) and infra:p1 (since 200), and the UNREAD web:p2 and infra:p2
## waiting longer than both: `N`, `›` and `‹` go round the two blocked and
## never reach a done one; DONE on the top bar still does.
func test_the_queue_is_the_blocked_while_anyone_is_blocked() -> void:
	var frame := _frame(floors)
	var starts: Dictionary[String, float] = {
		_local("web:p1"): 100.0, _local("infra:p1"): 200.0, _local("web:p2"): 60.0, _local("infra:p2"): 50.0
	}
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	navigator.picked_key = _local("web:p1")
	_eq(navigator.peek_next(frame), _local("infra:p1"), "after the longest blocked, the next blocked")
	_eq(navigator.peek_prev(frame), _local("infra:p1"), "and before it, round the other way, the last blocked")
	var walked: Array = []
	for press in 4:
		_check(navigator.next_human(frame), "press %d finds someone" % press)
		walked.append(navigator.picked_key)
	_eq(
		walked,
		[_local("infra:p1"), _local("web:p1"), _local("infra:p1"), _local("web:p1")],
		"N goes round the blocked, never to the done who waited longer"
	)
	var stepped: Array = []
	for direction: int in [1, 1, -1, -1]:
		_check(navigator.step(frame, direction), "a step finds someone")
		stepped.append(navigator.picked_key)
	_eq(
		stepped,
		[_local("infra:p1"), _local("web:p1"), _local("infra:p1"), _local("web:p1")],
		"‹ and › go round the blocked too"
	)
	_check(navigator.next_of(frame, "done"), "DONE still reaches a done agent while someone is blocked")
	_eq(navigator.picked_key, _local("infra:p2"), "the oldest UNREAD")


## The done come into NEXT's queue only when nobody is blocked, in wait
## order, and round again; the moment somebody blocks they drop out of it (from
## the one blocked, the next is that one again), and come back once it is
## answered.
func test_the_done_join_the_queue_when_nobody_is_blocked() -> void:
	var calm := _with(_with(floors, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "idle"})
	var starts: Dictionary[String, float] = {_local("web:p2"): 80.0, _local("infra:p2"): 50.0, _local("web:p1"): 300.0}
	var frame := _frame(calm)
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	var walked: Array = []
	for press in 3:
		_check(navigator.next_human(frame), "press %d finds a done one" % press)
		walked.append(navigator.picked_key)
	_eq(walked, [_local("infra:p2"), _local("web:p2"), _local("infra:p2")], "the done, oldest first, and round")
	_eq(navigator.peek_prev(frame), _local("web:p2"), "and back round the other way")
	var asking := _frame(_with(calm, "web:p1", {"agent_status": "blocked"}))
	_stamp(asking, starts)
	_eq(navigator.peek_next(asking), _local("web:p1"), "somebody blocks: from a done one, NEXT names them")
	_check(navigator.next_human(asking), "N picks them")
	_eq(navigator.picked_key, _local("web:p1"), "the one blocked")
	_eq(navigator.peek_next(asking), _local("web:p1"), "and from them, the next is them again, not a done one")
	_eq(navigator.peek_prev(asking), _local("web:p1"), "and so is the one before")
	_eq(navigator.peek_next(frame), _local("infra:p2"), "answered: the done are back, from the top")


## From a pick outside the queue (nobody, a working agent, or a done one
## while somebody is blocked), NEXT names the blocked who has waited longest and
## `‹` the newest blocked, whoever else waited longer.
func test_from_outside_the_queue_next_is_the_longest_waiting_blocked() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "web", "agent": "pi", "agent_status": "blocked"})
	var frame := _frame(local, basic)
	var starts: Dictionary[String, float] = {
		_local("web:p1"): 300.0,
		_local("infra:p1"): 100.0,
		_local("notes:p1"): 200.0,
		_bee("bravo:p1"): 400.0,
		_local("web:p2"): 20.0,
		_local("infra:p2"): 10.0,
	}
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	for outside: String in ["", _local("api:p1"), _local("infra:p2"), _local("web:p2")]:
		navigator.picked_key = outside
		_eq(navigator.peek_next(frame), _local("infra:p1"), "from '%s', the longest-waiting blocked" % outside)
		_eq(navigator.peek_prev(frame), _bee("bravo:p1"), "from '%s', back is the newest blocked" % outside)
	navigator.picked_key = _local("infra:p2")
	_check(navigator.next_human(frame), "N from the oldest done")
	_eq(navigator.picked_key, _local("infra:p1"), "picks the longest-waiting blocked")
	_eq(navigator.picked_floor, _local("infra"), "shows its floor")
	_eq(navigator.reveal_on_arrival, _local("infra:p1"), "and reveals it")


## The top bar's BLOCKED and DONE (next_of()): only that state, longest wait
## first by state_since, the pane no floor seats ranked with the seated,
## then round again; a
## selection outside the queue starts from the top. A dropped machine and a
## shell are never in it; an agent still launching is, once it asks.
func test_next_of_walks_one_state_and_done_starts_from_the_oldest() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	local = _with(_with(local, "data:p2", {"agent_status": "blocked"}), "api:p3", {"agent_status": "blocked"})
	var frame := _frame(local, basic, true)
	var starts: Dictionary[String, float] = {
		_local("web:p1"): 200.0,
		_local("infra:p1"): 100.0,
		_local("notes:p1"): 150.0,
		_local("web:p2"): 80.0,
		_local("infra:p2"): 50.0
	}
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	var walked: Array = []
	for press in 5:
		_check(navigator.next_of(frame, "blocked"), "press %d finds somebody blocked" % press)
		walked.append([navigator.picked_key, navigator.picked_floor, navigator.reveal_on_arrival])
	# Blocked comes first: data:p2, blocked while still launching, is in the
	# queue, its start unknown, so first.
	_eq(
		walked,
		[
			[_local("data:p2"), _local("data"), _local("data:p2")],
			[_local("infra:p1"), _local("infra"), _local("infra:p1")],
			[_local("notes:p1"), "", _local("notes:p1")],
			[_local("web:p1"), _local("web"), _local("web:p1")],
			[_local("data:p2"), _local("data"), _local("data:p2")],
		],
		"unknown start first, then longest wait, the unseated pane by its wait too, then round; no shell or dropped bee"
	)
	# notes:p1, which no floor seats, ranks by its wait like the seated:
	# blocked since 150, it comes between infra:p1 (100) and web:p1 (200).
	navigator.picked_key = _local("api:p1")
	navigator.next_of(frame, "blocked")
	_eq(navigator.picked_key, _local("data:p2"), "a selection outside the queue starts from the top")
	navigator.picked_key = ""
	_check(navigator.next_of(frame, "done"), "somebody is UNREAD")
	_eq(navigator.picked_key, _local("infra:p2"), "DONE starts from the oldest")
	navigator.next_of(frame, "done")
	_eq(navigator.picked_key, _local("web:p2"), "then the next")
	var quiet := _frame(_with(basic, "bravo:p1", {"agent_status": "working"}))
	navigator.picked_key = ""
	_check(not navigator.next_of(quiet, "blocked"), "nobody blocked: nothing to walk")
	_eq(navigator.picked_key, "", "and nothing picked")


## Give the panes of `frame`, seated or not, the state starts in `starts` (pane
## key -> unix seconds), as the office's frame builder does from the fleet.
func _stamp(frame: OfficeFrame, starts: Dictionary[String, float]) -> void:
	for building_model in frame.buildings:
		for floor_model in building_model.floors:
			for room in floor_model.rooms:
				for pane in room.panes:
					pane.state_since = starts.get(pane.key, -1.0)
		for pane in building_model.all_panes:
			pane.state_since = starts.get(pane.key, -1.0)


## Attention's "View" selects the pane, shows its floor when it has one and asks
## for it to be revealed; a pick of another floor drops that pending reveal.
func test_locating_a_pane_selects_it_and_reveals_it_on_arrival() -> void:
	var frame := _frame(_with(floors, "notes:p1", {"workspace_id": "web"}))
	var navigator := OfficeNavigator.new()
	navigator.locate(frame, frame.pane(_local("infra:p2")))
	_eq(
		[navigator.picked_key, navigator.picked_floor, navigator.reveal_on_arrival],
		[_local("infra:p2"), _local("infra"), _local("infra:p2")],
		"the pane, its floor and a reveal"
	)
	navigator.revealed()
	_eq(navigator.reveal_on_arrival, "", "once revealed, no more")
	navigator.locate(frame, frame.pane(_local("notes:p1")))
	_eq(navigator.picked_floor, _local("infra"), "a pane no floor seats leaves the floor as it was")
	_eq(navigator.picked_key, _local("notes:p1"), "but is selected")
	navigator.pick_floor(_local("web"))
	_eq(navigator.reveal_on_arrival, "", "picking another floor drops the pending reveal")


# --- the command line ---------------------------------------------------------


## The office, the showrooms and the studio read one parser: options with
## their values, bare flags, the last of a repeated option, and every argument
## kept for the parsers that read their own.
func test_the_command_line_reads_options_and_flags() -> void:
	var raw := PackedStringArray(
		["--zoom=3", "--attention", "--pack=a.json", "--pack=b.json", "--capture=", "stray", "--wait=1.5", "--floor=x"]
	)
	var args := AppArgs.parse(raw)
	_eq(args.number("zoom", 2), 3, "a whole number")
	_check(args.flag("attention") and not args.has("attention"), "a bare flag is a flag, not an option")
	_eq(args.text("pack"), "b.json", "a repeated option takes its last value")
	_check(args.has("capture") and args.text("capture", "fallback").is_empty(), "an empty value is still given")
	_eq(args.decimal("wait", 0.0), 1.5, "a fraction")
	_eq(args.number("floor", -1), 0, "a word reads as 0, as String.to_int() does")
	_eq(args.number("missing", 7), 7, "an option not given takes its fallback")
	_check(not args.flag("stray") and not args.has("stray"), "an argument without -- is neither")
	_eq(args.raw, raw, "every argument is kept for the parsers that read their own")
