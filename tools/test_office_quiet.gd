extends "res://tools/office_test_base.gd"
## What a refresh does not redo: the fleet's changes in one frame are drawn
## by one refresh at the frame's end (OfficeScene._queue_refresh()), while the
## state log still hears every one of them; and a refresh on a plan the cache
## kept builds no placement signature, lays no structure out again, redraws no
## lamp that burns as it did and keeps every node. Counters, not milliseconds:
## DeskPlacement.signatures, OfficeFloorView.structures, OfficeTable.lamps_drawn
## and OfficeDouble.refreshes. The live office (office_test_base) is why the
## suite runs --read-only with its own --socket and --work.

## Five status events for five panes of the fixture, each a real change.
const BURST: Array[Array] = [
	["api:p1", "blocked"],
	["api:p2", "working"],
	["web:p2", "idle"],
	["data:p1", "done"],
	["infra:p3", "working"],
]


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("quiet-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "QUIET REFRESH TESTS"


# --- one refresh per frame ----------------------------------------------------


## Five status events read in one frame (five stream lines, as herdr sends a
## burst) are drawn by one refresh at the end of that frame, never nested, and
## none after it; the state log heard all five, in order, before the office
## drew any, and the floor shows the last state of each.
func test_a_burst_of_status_events_in_one_frame_is_one_refresh() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var events := ledger.events().size()
	var refreshes := office.refreshes
	office.deepest_refresh = 0
	var said: Array[bool] = []
	office.data_refreshed.connect(func() -> void: said.append(true))
	for flip: Array in BURST:
		var pane_id: String = flip[0]
		var status: String = flip[1]
		_status(office, pane_id, status)
	_eq(office.refreshes, refreshes, "nothing is drawn while the frame reads its lines")
	var heard := ledger.events().slice(events)
	_eq(heard.size(), BURST.size(), "the state log heard every event at once")
	var states: Array = []
	for event: StateLog.Event in heard:
		states.append([HerdrFleet.split_key(event.pane_key)[1], event.state])
	var wanted: Array = []
	wanted.assign(BURST)
	_eq(states, wanted, "each pane's new state, in the order they came")
	await _frames(1)
	_eq(office.refreshes - refreshes, 1, "one refresh for the five, at the end of the frame")
	_eq(office.deepest_refresh, 1, "never one inside another")
	_eq(said.size(), 1, "and it says it drew new data, once")
	for flip: Array in BURST:
		var pane_id: String = flip[0]
		var status: String = flip[1]
		var pane := office.frame.pane(_pk(pane_id))
		_check(pane != null and pane.state == status, "%s drawn %s" % [pane_id, status])
	await _frames(3)
	_eq(office.refreshes - refreshes, 1, "and no refresh after it")
	_done(office)


## A click, a resize or a floor picked still refreshes at once, and that
## refresh takes a change the frame had queued in with it: the queued one then
## finds nothing to draw and does not run.
func test_a_refresh_at_once_takes_the_queued_change_in() -> void:
	var office := await _live_office()
	var refreshes := office.refreshes
	var said: Array[bool] = []
	office.data_refreshed.connect(func() -> void: said.append(true))
	_status(office, "api:p1", "blocked")
	office.refresh()
	_eq(office.refreshes - refreshes, 1, "the refresh at once")
	_eq(office.frame.pane(_pk("api:p1")).state, "blocked", "drew the change")
	_eq(said.size(), 1, "as new data")
	await _frames(2)
	_eq(office.refreshes - refreshes, 1, "and the queued refresh never ran")
	_eq(said.size(), 1, "nor said anything")
	# A refresh with nothing queued is not one for new data.
	office.refresh()
	_eq(said.size(), 1, "a refresh with no change queued is not new data")
	_done(office)


## An office taken out of the tree before the end of the frame draws nothing
## it queued (no script error from a half-torn-down office), and back in the
## tree it queues afresh on the next change.
func test_an_office_out_of_the_tree_draws_nothing_it_queued() -> void:
	var office := await _live_office()
	var refreshes := office.refreshes
	_status(office, "api:p1", "blocked")
	root.remove_child(office)
	await _frames(2)
	_eq(office.refreshes, refreshes, "nothing drawn out of the tree")
	root.add_child(office)
	_status(office, "api:p2", "working")
	await _frames(1)
	_eq(office.refreshes - refreshes, 1, "back in the tree, the next change is drawn")
	_eq(office.frame.pane(_pk("api:p1")).state, "blocked", "with the one it missed")
	_eq(office.frame.pane(_pk("api:p2")).state, "working", "and the new one")
	_done(office)


# --- quiet refreshes ----------------------------------------------------------


## A refresh on the plan the cache kept, with no change or with only a status
## change, builds no placement signature, lays out no structure (the shell's
## key, the tree order, the seat index), redraws no lamp and keeps every node
## of the floor: the same instances, in the same order.
func test_a_quiet_refresh_builds_no_signature_and_keeps_every_node() -> void:
	var office := await _live_office()
	office.refresh()
	await _frames(1)
	var nodes := _floor_nodes(office)
	var signatures := DeskPlacement.signatures
	var structures := office.floor_view.structures
	var lamps := _lamps_drawn(office)
	var plan := office.floor_view.plan
	office.refresh()
	office.refresh()
	_eq(DeskPlacement.signatures - signatures, 0, "no placement signature for an unchanged plan")
	_eq(office.floor_view.structures - structures, 0, "no structural pass")
	_eq(_lamps_drawn(office) - lamps, 0, "no lamp redrawn")
	_eq(office.floor_view.plan, plan, "the same plan")
	_eq(_floor_nodes(office), nodes, "every node kept, in order")
	# A status change keeps the plan too: only the seat that changed is furnished.
	_status(office, "api:p2", "working")
	await _frames(1)
	_eq(DeskPlacement.signatures - signatures, 0, "a status change builds no signature either")
	_eq(office.floor_view.structures - structures, 0, "nor a structural pass")
	_eq(_lamps_drawn(office) - lamps, 0, "nor a lamp")
	_eq(office.frame.pane(_pk("api:p2")).state, "working", "and it is drawn")
	_done(office)


## A table that grows is laid out again (a new plan): its structure and the
## lamps of the seats it rebuilt are drawn, and the plan after that is quiet again.
func test_a_new_plan_is_laid_out_and_the_next_refresh_is_quiet() -> void:
	var office := await _live_office()
	var structures := office.floor_view.structures
	var grown := _plus(fixture, "api:p2", "api:p9")
	_feed(office, grown)
	await _frames(1)
	_check(office.floor_view.structures > structures, "a new plan is laid out")
	_check(office.floor_view.seats.has(_pk("api:p9")), "with the new seat")
	var level := _lamps(office)
	_eq(level.get("api:p9", -1), OfficeTable.Lamp.ON, "whose lamp burns")
	var signatures := DeskPlacement.signatures
	structures = office.floor_view.structures
	office.refresh()
	_eq(DeskPlacement.signatures - signatures, 0, "then no signature")
	_eq(office.floor_view.structures - structures, 0, "and no structural pass")
	_done(office)


## The lamps still follow herdr's focus and the tab a workspace has open, and
## a refresh redraws exactly the lamps whose level moved.
func test_lamps_follow_focus_and_redraw_only_what_moved() -> void:
	var office := await _live_office()
	var before := _lamps(office)
	_eq(before.get("api:p1", -1), OfficeTable.Lamp.FOCUS, "herdr's focus burns brightest")
	var lamps := _lamps_drawn(office)
	_feed(office, _focused_on(fixture, "api:p2"))
	var after := _lamps(office)
	_eq(after.get("api:p2", -1), OfficeTable.Lamp.FOCUS, "the focus moved to api:p2")
	_eq(after.get("api:p1", -1), OfficeTable.Lamp.ON, "and api:p1 burns normally")
	_eq(_lamps_drawn(office) - lamps, _moved(before, after), "only the lamps that moved were drawn")
	lamps = _lamps_drawn(office)
	var open := _open_tab_of(_focused_on(fixture, "api:p2"), "api", "api:t2")
	_feed(office, open)
	var dimmed := _lamps(office)
	_eq(dimmed.get("api:p1", -1), OfficeTable.Lamp.DIM, "a tab its workspace does not have open is dimmed")
	_eq(dimmed.get("api:p4", -1), OfficeTable.Lamp.ON, "the open one burns")
	_eq(_lamps_drawn(office) - lamps, _moved(after, dimmed), "again only the lamps that moved")
	_done(office)


## A table set up again for another pack draws every lamp it keeps anew, at
## the level it had: a lamp's colour is the pack's, so the guard that skips a
## lamp already at its level must not skip these (dusk burns them harder).
func test_a_table_set_up_for_another_pack_redraws_its_lamps() -> void:
	var day := ArtPack.from_manifest(MANIFESTS[0])
	var dusk := ArtPack.from_manifest(MANIFESTS[1])
	var world := Node2D.new()
	var ground := Node2D.new()
	var sorted := Node2D.new()
	world.add_child(ground)
	world.add_child(sorted)
	root.add_child(world)
	var table := OfficeDraw.new(day).table(sorted, ground, "Lamps", Vector2(160, 240), 160, [48.0, 112.0])
	table.light(0, "far", OfficeTable.Lamp.FOCUS)
	table.light(1, "near", OfficeTable.Lamp.DIM)
	var drawn := table.lamps_drawn
	table.light(0, "far", OfficeTable.Lamp.FOCUS)
	_eq(table.lamps_drawn, drawn, "a lamp already at its level is not drawn again")
	var day_focus := table.lamp_color(OfficeTable.Lamp.FOCUS)
	_check(table.setup(dusk, 160, [48.0, 112.0]), "set up for dusk")
	_check(table.lamp_color(OfficeTable.Lamp.FOCUS) != day_focus, "dusk's focus lamp is another colour")
	_eq(table.task_light(0, "far").color, table.lamp_color(OfficeTable.Lamp.FOCUS), "the focus lamp in dusk's colour")
	_eq(table.task_light(1, "near").color, table.lamp_color(OfficeTable.Lamp.DIM), "the dim one too")
	_check(table.task_light(0, "far").visible and not table.task_light(0, "near").visible, "on and off as before")
	world.free()


# --- helpers ------------------------------------------------------------------


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## One `pane.agent_status_changed` event for `pane_id`, as the client's stream reads it.
func _status(office: OfficeDouble, pane_id: String, status: String) -> void:
	_local(office)._apply_status({"pane_id": pane_id, "agent_status": status})


## Every node of the shown floor, as instance ids in tree order.
func _floor_nodes(office: OfficeDouble) -> Array[int]:
	var ids: Array[int] = []
	for node: Node in office.floor_view.root.find_children("*", "", true, false):
		ids.append(node.get_instance_id())
	return ids


## How many lamps every table of the shown floor has drawn, together.
func _lamps_drawn(office: OfficeDouble) -> int:
	var total := 0
	for table in office.floor_view.tables:
		total += table.lamps_drawn
	return total


## How many seats burn at another level in `after` than in `before`.
static func _moved(before: Dictionary, after: Dictionary) -> int:
	var moved := 0
	for key: Variant in after:
		if before.get(key, -1) != after[key]:
			moved += 1
	return moved


## `snapshot` with a copy of pane `like` added to its tab as `pane_id`.
func _plus(snapshot: Dictionary, like: String, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var panes := _list(result, "panes")
	for pane: Dictionary in panes.duplicate():
		if pane.get("pane_id", "") == like:
			var copy: Dictionary = pane.duplicate(true)
			copy.pane_id = pane_id
			copy.terminal_id = "term-" + pane_id
			copy.erase("agent_session")
			copy.focused = false
			panes.append(copy)
	return result
