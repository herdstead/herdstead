extends "res://tools/client_test_base.gd"
## Headless tests for HerdrClient against tools/fake_herdr.py, the typed
## snapshot it reads (HerdrSnapshot), plus the pure projection, layout and
## minimap of office.gd. Run through tools/run_tests.sh. The client, the fake
## herdr and the fixtures it stands on are tools/client_test_base.gd.
##
## godot --headless --path . --script tools/test_client.gd -- --socket=<fake herdr> --control=<fake control>
##
## Exits 0 when every case passes, 1 on any failure, 2 on a harness error.


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--socket="):
			socket_path = argument.trim_prefix("--socket=")
		if argument.begins_with("--control="):
			control_path = argument.trim_prefix("--control=")
	if socket_path.is_empty() or control_path.is_empty():
		print("TEST_HARNESS_ERROR: pass --socket= and --control= (use tools/run_tests.sh)")
		quit(2)
		return
	_run()


## Cases run inside the main loop, not inside _initialize: a Container only
## lays its children out at the end of a frame, so a HUD case has to be able to
## wait for one. The client itself is still never in the tree and still only
## moves when a case pumps it.
func _run() -> void:
	await run_cases()


func _marker() -> String:
	return "TESTS"


## Every case gets a fresh client; the one it left behind stops and frees here.
func _after_case() -> void:
	_finish_client()


func _summary_suffix() -> String:
	return ", slowest _process %.1fms" % (max_step_usec / 1000.0)


# --- client cases -------------------------------------------------------------


func test_resolve_socket_path() -> void:
	var saved := OS.get_environment("HERDR_SOCKET_PATH")
	OS.set_environment("HERDR_SOCKET_PATH", "/tmp/from-env.sock")
	_eq(
		HerdrClient.resolve_socket_path(PackedStringArray(["--wait=1", "--socket=/tmp/flag.sock"])),
		"/tmp/flag.sock",
		"--socket= wins"
	)
	_eq(HerdrClient.resolve_socket_path(PackedStringArray()), "/tmp/from-env.sock", "environment is second")
	OS.unset_environment("HERDR_SOCKET_PATH")
	_eq(
		HerdrClient.resolve_socket_path(PackedStringArray()),
		OS.get_environment("HOME").path_join(".config/herdr/herdr.sock"),
		"default session socket"
	)
	if not saved.is_empty():
		OS.set_environment("HERDR_SOCKET_PATH", saved)


func test_normal_path() -> void:
	_ctl("reset", {"fixture": "snapshot_basic"})
	_start_client()
	if not _settle():
		return
	var fixture := _fixture("snapshot_basic")
	var stats := _server_until(func(s: Dictionary) -> bool: return s.streams_live == 1, "one live stream")
	# ping -> subscribe (topology only: no panes known yet) -> snapshot ->
	# subscribe again now that the panes are known -> snapshot for the gap.
	_eq(
		stats.methods,
		["ping", "events.subscribe", "session.snapshot", "events.subscribe", "session.snapshot"],
		"handshake order"
	)
	_eq(rec.order.slice(0, 2), ["connected", "snapshot"], "connected before the first snapshot")
	_eq(rec.connected, 1, "connected once")
	_eq(rec.disconnected, 0, "never disconnected")
	_check(client.online, "online")
	_eq(client.snapshot.signature(), _view(fixture).signature(), "snapshot equals the served payload, as read")
	var first: Array = stats.params[1].subscriptions
	_eq(first.size(), HerdrClient.TOPOLOGY.size(), "first subscribe carries only the global topology events")
	_eq(stats.last_subscribe_types, HerdrClient.TOPOLOGY, "every topology event is subscribed")
	for event: String in ["worktree.created", "worktree.opened", "worktree.removed"]:
		_check(_list(stats, "last_subscribe_types").has(event), "worktree subscription: " + event)
	_eq(stats.last_subscribe_panes, _pane_ids(fixture), "one status subscription per pane")
	_eq(stats.stream_panes, [_pane_ids(fixture)], "the first stream was closed, only the full one lives")
	var ids: Array = stats.ids
	var unique := {}
	for id: String in ids:
		unique[id] = true
	_eq(unique.size(), ids.size(), "request ids are unique strings")
	_eq(stats.params[0], {}, "ping takes empty params")
	_eq(stats.params[2], {}, "session.snapshot takes empty params")


func test_no_snapshot_before_subscription_started() -> void:
	_ctl("reset", {"fixture": "snapshot_basic"})
	_ctl("hold_ack", {"hold": true})
	_start_client()
	_server_until(func(s: Dictionary) -> bool: return s.streams_pending == 1, "subscription waiting for its ack")
	# Well inside SUBSCRIBE_TIMEOUT, and bytes get every chance to move.
	for i in 40:
		_step(0.1)
		_pump_frames(5)
	var stats := _ctl("stats")
	_eq(stats.methods, ["ping", "events.subscribe"], "no snapshot while the stream is not live")
	_eq(rec.order, [], "no signal before subscription_started")
	_check(not client.online, "not online yet")
	_ctl("release")
	_pump(func() -> bool: return rec.snapshots > 0, "first snapshot after the ack")
	_eq(rec.order.slice(0, 2), ["connected", "snapshot"], "connected, then snapshot")
	_eq(
		_list(_ctl("stats"), "methods").slice(0, 3),
		["ping", "events.subscribe", "session.snapshot"],
		"snapshot only after the ack"
	)


func test_subscribe_timeout() -> void:
	_ctl("reset", {"fixture": "snapshot_basic"})
	_ctl("hold_ack", {"hold": true})
	_start_client()
	_server_until(func(s: Dictionary) -> bool: return s.streams_pending == 1, "subscription waiting for its ack")
	_step(HerdrClient.SUBSCRIBE_TIMEOUT - 0.1)
	_pump_frames(10)
	_eq(rec.disconnected, 0, "still waiting just before SUBSCRIBE_TIMEOUT")
	_step(0.2)
	_eq(rec.disconnected, 1, "a silent subscribe gives up after SUBSCRIBE_TIMEOUT")
	_check(client._sub.is_empty(), "the stalled stream is dropped")
	_server_until(func(s: Dictionary) -> bool: return s.streams_pending == 0, "server sees the stream closed")
	_ctl("hold_ack", {"hold": false})
	_step(HerdrClient.BACKOFF_MIN)
	_settle()
	_eq(rec.connected, 1, "reconnects once herdr answers again")


func test_reconnect_waits_for_a_fresh_snapshot() -> void:
	if not _connect_settled():
		return
	_eq(client.snapshot_current, true, "a completed snapshot is current")
	_eq(rec.readiness, 1, "first complete snapshot announces readiness once")
	var before := client.snapshot.signature()
	_ctl("next", {"action": "hang", "method": "session.snapshot"})
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 1, "connection is lost")
	_eq(client.snapshot_current, false, "disconnect invalidates the old snapshot")
	_step(HerdrClient.BACKOFF_MIN)
	_server_until(func(stats: Dictionary) -> bool: return stats.hung == 1, "the first reconnect snapshot is withheld")
	_check(client.online, "the subscription is already live while the snapshot is withheld")
	_eq(client.snapshot.signature(), before, "the old snapshot remains available for frozen display")
	_eq(client.snapshot_current, false, "live subscription does not make old data current")
	_eq(rec.readiness, 2, "disconnect announces not-ready, subscribe does not announce ready")
	var received := rec.events.size()
	_ctl(
		"emit",
		{"envelope": {"event": "pane.agent_status_changed", "data": {"pane_id": "alpha:p1", "agent_status": "working"}}}
	)
	_pump(func() -> bool: return rec.events.size() > received, "an event may arrive before the full snapshot")
	_eq(client.snapshot_current, false, "a status event is not a complete snapshot")
	_eq(client.snapshot.signature(), before, "a pre-baseline event keeps the frozen snapshot unchanged")
	_step(HerdrClient.REQUEST_TIMEOUT - 0.1)
	_pump_frames(5)
	_step(0.2)
	_pump(func() -> bool: return rec.disconnected == 2, "the withheld request times out")
	_step(HerdrClient.BACKOFF_MIN)
	_settle()
	_eq(client.snapshot.signature(), before, "the newly fetched snapshot can contain exactly the same data")
	_eq(client.snapshot_current, true, "only the fresh complete response restores currency")
	_eq(rec.readiness, 3, "same-content recovery still announces a liveness change")
	client.stop()
	_eq(client.snapshot_current, false, "stop also invalidates currency")
	client.start(socket_path)
	_eq(client.snapshot_current, false, "start waits for a new complete response")


func test_reconnect_events_cannot_establish_a_clock_before_first_snapshot() -> void:
	if not _connect_settled():
		return
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 1, "connection is lost")
	_ctl("status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	_ctl("next", {"action": "hold_snapshot", "method": "session.snapshot"})
	_step(HerdrClient.BACKOFF_MIN)
	_server_until(
		func(stats: Dictionary) -> bool: return stats.held_snapshots == 1,
		"the first reconnect snapshot is held on its live request"
	)
	_check(client.online and not client.snapshot_current, "stream is live but its snapshot is not yet current")
	var before := client.snapshot.signature()
	var snapshots_before := rec.snapshots
	for status: String in ["working", "blocked"]:
		var received := rec.events.size()
		_eq(_ctl("status", {"pane_id": "alpha:p1", "agent_status": status}).sent, 1, "status reaches live stream")
		_pump(func() -> bool: return rec.events.size() > received, "status before the first complete snapshot")
		_eq(client.snapshot.signature(), before, "pre-baseline events retain the last frozen snapshot")
		_eq(client.state_since("alpha:p1"), -1.0, "events without a current identity baseline cannot start clocks")
	_eq(rec.snapshots, snapshots_before, "pre-baseline events never emit changed snapshots")
	_eq(_ctl("release_snapshots").released, 1, "release the same request without a reconnect or timeout")
	_pump(func() -> bool: return client.snapshot_current, "the held first snapshot arrives")
	_eq(_pane_status("alpha:p1"), "blocked", "first fresh snapshot agrees with the last event")
	_eq(client.state_since("alpha:p1"), -1.0, "same-state first snapshot establishes an unknown-time baseline")
	_eq(rec.disconnected, 1, "no intervening disconnect cleared the clock")
	_eq(_ctl("stats").held_snapshots, 0, "held request is released")
	var received := rec.snapshots
	_ctl("status", {"pane_id": "alpha:p1", "agent_status": "working"})
	_pump(func() -> bool: return rec.snapshots > received, "status after the baseline")
	_check(client.state_since("alpha:p1") > 0.0, "a transition after the current baseline starts a clock")


func test_topology_debounce() -> void:
	if not _connect_settled():
		return
	var base: int = _ctl("stats").snapshot_count
	for event: String in ["pane_updated", "layout_updated", "workspace_focused"]:
		_eq(_ctl("emit", {"fixture_event": event}).sent, 1, "server delivered " + event)
	_pump(func() -> bool: return rec.events.size() == 3, "three topology events")
	_eq(
		rec.events.map(func(e: Array) -> String: return e[0]),
		["pane_updated", "layout_updated", "workspace_focused"],
		"wire names reach event_received"
	)
	_eq(str(rec.event_data(0).get("type", "")), "pane_updated", "event data arrives intact")
	_eq(_ctl("stats").snapshot_count, base, "no fetch while time stands still")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE * 0.5)
	_pump_frames(10)
	_eq(_ctl("stats").snapshot_count, base, "no fetch inside the debounce window")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE * 0.6)
	_settle()
	_pump_frames(20)
	_eq(_ctl("stats").snapshot_count, base + 1, "a burst of three events costs one fetch")
	# A later event restarts the window instead of stacking a second fetch.
	_ctl("emit", {"fixture_event": "tab_renamed"})
	_pump(func() -> bool: return rec.events.size() == 4, "fourth event")
	_step(0.08)
	_ctl("emit", {"fixture_event": "pane_exited"})
	_pump(func() -> bool: return rec.events.size() == 5, "fifth event")
	_step(0.08)
	_pump_frames(10)
	_eq(_ctl("stats").snapshot_count, base + 1, "each event restarts the debounce window")
	_step(0.03)
	_settle()
	_pump_frames(20)
	_eq(_ctl("stats").snapshot_count, base + 2, "one fetch once the stream goes quiet")


func test_interval_backstop() -> void:
	if not _connect_settled():
		return
	var base: int = _ctl("stats").snapshot_count
	_step(HerdrClient.SNAPSHOT_INTERVAL - 0.1)
	_pump_frames(10)
	_eq(_ctl("stats").snapshot_count, base, "nothing before SNAPSHOT_INTERVAL")
	_step(0.2)
	_settle()
	_eq(_ctl("stats").snapshot_count, base + 1, "periodic re-fetch without any event")


func test_pane_set_change_resubscribes() -> void:
	if not _connect_settled():
		return
	var before: Dictionary = _ctl("stats")
	var grown := _fixture("snapshot_grown")
	_ctl("set_snapshot", {"fixture": "snapshot_grown"})
	_ctl("emit", {"fixture_event": "pane_created"})
	_pump(func() -> bool: return rec.events.size() == 1, "pane_created")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	if not _settle():
		return
	var stats := _server_until(
		func(s: Dictionary) -> bool: return s.streams_live == 1 and s.stream_panes == [_pane_ids(grown)],
		"stream follows the new pane set"
	)
	_eq(stats.subscribe_count, before.subscribe_count + 1, "exactly one new subscription")
	_eq(stats.last_subscribe_panes, _pane_ids(grown), "new subscription covers the new pane set")
	_eq(client._sub_panes, PackedStringArray(_pane_ids(grown)), "client tracks the new pane set")
	_eq(rec.disconnected, 0, "re-subscribing is not a disconnect")
	# The new pane's status now reaches the client; the closed one is gone.
	_eq(
		_ctl("status", {"pane_id": "bravo:p2", "agent_status": "blocked"}).sent,
		1,
		"server routes the new pane's status"
	)
	_pump(func() -> bool: return _pane_status("bravo:p2") == "blocked", "status of the new pane")


func test_status_updates_in_place() -> void:
	if not _connect_settled():
		return
	var count: int = _ctl("stats").snapshot_count
	var signals := rec.snapshots
	var held := client.snapshot
	_eq(_ctl("status", {"pane_id": "alpha:p1", "agent_status": "blocked"}).sent, 1, "server routes a subscribed pane")
	_pump(func() -> bool: return rec.snapshots > signals, "snapshot_changed from the status event")
	_eq(_pane_status("alpha:p1"), "blocked", "status applied in place")
	_eq(rec.events.back()[0], "pane.agent_status_changed", "dotted per-pane event name")
	_eq(_ctl("stats").snapshot_count, count, "applied without a round trip")
	_check(is_same(client.snapshot, held), "same snapshot, patched in place")
	_eq(_pane_status("alpha:p3"), "idle", "other panes untouched")
	# `agent` rides along when herdr sends it: a shell pane that starts an agent.
	_ctl("status", {"pane_id": "alpha:p2", "agent_status": "working", "agent": "codex"})
	_pump(func() -> bool: return _pane_agent("alpha:p2") == "codex", "agent from the status event")
	_eq(_pane_status("alpha:p2"), "working", "shell pane status")
	# Aggregates moved too, so the debounce still re-fetches, and herdr agrees.
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	_settle()
	_eq(_ctl("stats").snapshot_count, count + 1, "one debounced re-fetch after status events")
	_eq(_pane_status("alpha:p1"), "blocked", "re-fetched snapshot agrees")


## Time-in-state bookkeeping as pure functions: a pane seen for the first time
## has no real start, an unchanged status keeps its start, a changed one starts
## now, a pane that is gone drops out, and only a real change moves the clock.
## An identity the snapshot does not give (a terminal_id missing from one
## malformed snapshot) is an identity we do not know, not a new one: the same
## status keeps its clock, before and after, so the longest waiter stays the
## longest. A pane missing from a single snapshot comes back with its clock.
## Both through the client's own snapshots, on a live connection.
func _state_since_survives_one_malformed_snapshot() -> void:
	var probe := HerdrClient.new()
	var blocked := {"panes": [_status_pane("p1", "working"), _status_pane("p2", "working")]}
	probe._apply_snapshot(blocked)
	var first := {"panes": [_status_pane("p1", "blocked"), _status_pane("p2", "working")]}
	probe._apply_snapshot(first)
	var started := probe.state_since("p1")
	_check(started > 0.0, "p1's blocked began while we watched")
	OS.delay_msec(5)
	var nameless := _status_pane("p1", "blocked")
	nameless.erase("terminal_id")
	probe._apply_snapshot({"panes": [nameless, _status_pane("p2", "working")]})
	_eq(probe.state_since("p1"), started, "a snapshot without p1's terminal keeps its clock")
	OS.delay_msec(5)
	probe._apply_snapshot(first)
	_eq(probe.state_since("p1"), started, "and its terminal back, the same clock")
	OS.delay_msec(5)
	probe._apply_snapshot({"panes": [_status_pane("p2", "working")]})
	_eq(probe.state_since("p1"), -1.0, "missing from a snapshot, nobody reads its start")
	OS.delay_msec(5)
	probe._apply_snapshot(first)
	_eq(probe.state_since("p1"), started, "back the next snapshot with the same identity: the same clock")
	probe._apply_snapshot({"panes": [_status_pane("p2", "working")]})
	probe._apply_snapshot({"panes": [_status_pane("p2", "working")]})
	OS.delay_msec(5)
	probe._apply_snapshot(first)
	_check(probe.state_since("p1") > started, "gone for two snapshots it is new to the connection: a later start")
	probe.free()


func test_state_since_carries_across_snapshots() -> void:
	var known := HerdrClient.carry_states(
		{}, _typed([_status_pane("p1", "working"), _status_pane("p2", "blocked")]), 100.0
	)
	_check(_started_at(known, "p1") == -1.0 and _started_at(known, "p2") == -1.0, "first sight is unknown")
	known = HerdrClient.carry_states(known, _typed([_status_pane("p1", "working"), _status_pane("p2", "idle")]), 105.0)
	_eq(known.p1.since, -1.0, "unchanged status keeps its start")
	_eq([known.p2.status, known.p2.since], ["idle", 105.0], "changed status starts now")
	known = HerdrClient.carry_states(known, _typed([_status_pane("p1", "working"), _status_pane("p2", "idle")]), 110.0)
	_eq([known.p2.status, known.p2.since], ["idle", 105.0], "a repeated snapshot does not reset the clock")
	known = HerdrClient.carry_states(
		known, _typed([_status_pane("p2", "idle"), _status_pane("p3", "done")]), 115.0, true
	)
	# A pane missing from one snapshot keeps its clock through it (a single
	# malformed snapshot must not reset who waited longest). Missing from two in
	# a row, it drops out (below).
	_check(known.has("p1") and known.p1.missing, "a pane missing from one snapshot is kept, marked missing")
	# A pane new to a connection we were watching began while we watched, a
	# known start, so it ranks after everyone already there.
	_eq(known.p3.since, 115.0, "a pane appearing on a watched connection starts now")
	var fresh := HerdrClient.carry_states({}, _typed([_status_pane("p4", "done")]), 116.0)
	_eq(fresh.p4.since, -1.0, "a pane in a connection's first snapshot is unknown")
	HerdrClient.mark_status(known, _typed([_status_pane("p2", "idle")])[0], 120.0)
	_eq([known.p2.status, known.p2.since], ["idle", 105.0], "an event repeating the status keeps its start")
	HerdrClient.mark_status(known, _typed([_status_pane("p2", "blocked")])[0], 125.0)
	_eq([known.p2.status, known.p2.since], ["blocked", 125.0], "an event changing the status starts now")
	known = HerdrClient.carry_states(known, _typed([_status_pane("p2", "blocked")]), 130.0)
	_eq([known.p2.status, known.p2.since], ["blocked", 125.0], "the next snapshot keeps the event's start")
	_check(not known.has("p1") and known.has("p3"), "missing from two snapshots in a row, a pane drops out")


## The same rules through the client's own entry points, including the
## disconnect that must forget every start time: a status may have changed and
## changed back while we were away.
func test_state_since_through_the_client() -> void:
	var probe := HerdrClient.new()
	probe._apply_snapshot({"panes": [_status_pane("p1", "blocked"), _status_pane("p2", "done")]})
	_eq(probe.state_since("p1"), -1.0, "the first snapshot is unknown")
	probe._apply_status({"pane_id": "p1", "agent_status": "working"})
	var started := probe.state_since("p1")
	_check(started > 0.0, "a status event starts the clock")
	probe._apply_snapshot({"panes": [_status_pane("p1", "working"), _status_pane("p2", "done")]})
	_eq(probe.state_since("p1"), started, "the next snapshot keeps it")
	probe._apply_snapshot({"panes": [_status_pane("p1", "working")]})
	_eq(probe.state_since("p2"), -1.0, "a gone pane is unknown")
	_eq(probe.state_since("nope"), -1.0, "a never-seen pane is unknown")
	probe._go_offline()
	_eq(probe.state_since("p1"), -1.0, "offline forgets every start")
	probe._apply_snapshot({"panes": [_status_pane("p1", "working")]})
	_eq(probe.state_since("p1"), -1.0, "after a reconnect the same status is still unknown")
	probe.free()
	# In this case to keep the suite under gdlint's public-method cap.
	_state_since_survives_one_malformed_snapshot()


## When a machine was last heard from (HerdrClient.heard_at, which the top
## bar's MACHINES counter says on hover): a snapshot read, or a status event
## applied to it, is hearing from the machine; a refused snapshot, an event
## held back while stale, and a drop are not, and a drop keeps the last time.
func test_heard_at_follows_snapshots_and_status_events() -> void:
	var probe := HerdrClient.new()
	_eq(probe.heard_at, -1.0, "never heard from")
	var before := Time.get_unix_time_from_system()
	probe._apply_snapshot({"panes": [_status_pane("p1", "blocked")]})
	var first := probe.heard_at
	_check(first >= before and first <= Time.get_unix_time_from_system(), "a snapshot read is now: %s" % first)
	OS.delay_msec(5)
	probe._apply_status({"pane_id": "p1", "agent_status": "working"})
	_check(probe.heard_at > first, "a status event applied is later")
	var heard := probe.heard_at
	var refused: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		refused.append({})
	probe._apply_snapshot({"panes": refused})
	_check(not probe.snapshot_current, "a snapshot over the caps is refused")
	_eq(probe.heard_at, heard, "which is not hearing from the machine")
	probe._apply_status({"pane_id": "p1", "agent_status": "done"})
	_eq(probe.heard_at, heard, "nor is an event held back while stale")
	probe._go_offline()
	_eq(probe.heard_at, heard, "a drop keeps when it was last heard")
	probe.free()


func test_state_clock_terminal_session_and_provider() -> void:
	var raw := {
		"panes":
		[
			{
				"pane_id": "p",
				"terminal_id": "term",
				"agent": "codex",
				"agent_status": "idle",
				"agent_session": {"agent": "codex", "source": "hook", "kind": "session_id", "value": "one"}
			}
		]
	}
	var panes: Array = raw.panes
	var pane: Dictionary = panes[0]
	var identity: Dictionary = pane.agent_session
	var known := HerdrClient.carry_states({}, _clock_panes(raw), 10.0)
	pane.agent_status = "blocked"
	known = HerdrClient.carry_states(known, _clock_panes(raw), 20.0)
	_eq(known.p.since, 20.0, "a stable session's status change is observed")
	identity.source = "argv"
	known = HerdrClient.carry_states(known, _clock_panes(raw), 30.0)
	_eq(known.p.since, 20.0, "changing detection provenance keeps the clock")
	identity.value = "two"
	var unwatched := HerdrClient.carry_states(known, _clock_panes(raw), 40.0)
	_eq(unwatched.p.since, -1.0, "a new session seen in a connection's first snapshot has an unknown start")
	known = HerdrClient.carry_states(known, _clock_panes(raw), 40.0, true)
	# A new identity watched live starts the clock at the observation (a known
	# start that never inherits the old one).
	_eq(known.p.since, 40.0, "a new session watched live starts its clock now")
	pane.agent_status = "working"
	known = HerdrClient.carry_states(known, _clock_panes(raw), 50.0)
	_eq(known.p.since, 50.0, "a later change establishes the new session's clock")
	pane.terminal_id = "replacement"
	known = HerdrClient.carry_states(known, _clock_panes(raw), 60.0, true)
	_eq(known.p.since, 60.0, "a replaced terminal never inherits the clock: its own starts now")
	pane.agent_status = "blocked"
	known = HerdrClient.carry_states(known, _clock_panes(raw), 70.0)
	pane.agent = "claude"
	HerdrClient.mark_status(known, _clock_panes(raw)[0], 80.0)
	_eq(known.p.since, 80.0, "an event changing provider drops the old clock and starts the new agent's now")
	pane.erase("terminal_id")
	pane.agent_status = "working"
	HerdrClient.mark_status(known, _clock_panes(raw)[0], 90.0)
	_eq(known.p.since, -1.0, "missing terminal identity cannot establish a clock")


func test_state_clock_does_not_survive_launching() -> void:
	var raw := {"panes": [_status_pane("p", "idle")], "agents": [{"pane_id": "p", "terminal_id": "term-p"}]}
	var panes: Array = raw.panes
	var pane: Dictionary = panes[0]
	var agents: Array = raw.agents
	var agent: Dictionary = agents[0]
	var known := HerdrClient.carry_states({}, _clock_panes(raw), 10.0)
	pane.agent_status = "working"
	known = HerdrClient.carry_states(known, _clock_panes(raw), 20.0)
	_eq(known.p.since, 20.0, "a known non-launching status can be timed")
	agent.launch_pending = true
	known = HerdrClient.carry_states(known, _clock_panes(raw), 30.0)
	_eq(known.p.since, -1.0, "launching clears an earlier run's duration")
	pane.agent_status = "blocked"
	HerdrClient.mark_status(known, _clock_panes(raw)[0], 40.0)
	_eq(known.p.since, 40.0, "blocked comes first: a question asked during a launch is a known start")
	agent.erase("launch_pending")
	known = HerdrClient.carry_states(known, _clock_panes(raw), 50.0, true)
	# Blocked comes first: still blocked, the launch ending is no new state.
	_eq(known.p.since, 40.0, "leaving the launch while still blocked keeps the clock, not the old run's 20")
	pane.agent_status = "working"
	HerdrClient.mark_status(known, _clock_panes(raw)[0], 60.0)
	_eq(known.p.since, 60.0, "a later live transition can establish a new start")


## Blocked comes first on the empty-identity path too. A
## question asked during a launch keeps its start when the next snapshot has
## lost the terminal id but still says blocked and the launch is over.
func test_a_blocked_launch_keeps_its_clock_when_the_identity_goes_missing() -> void:
	var raw := {"panes": [_status_pane("p", "working")], "agents": [{"pane_id": "p", "terminal_id": "term-p"}]}
	var panes: Array = raw.panes
	var pane: Dictionary = panes[0]
	var agents: Array = raw.agents
	var agent: Dictionary = agents[0]
	var known := HerdrClient.carry_states({}, _clock_panes(raw), 10.0)
	agent.launch_pending = true
	pane.agent_status = "blocked"
	HerdrClient.mark_status(known, _clock_panes(raw)[0], 20.0)
	_eq(known.p.since, 20.0, "a question asked during a launch is a known start")
	agent.erase("launch_pending")
	pane.erase("terminal_id")
	known = HerdrClient.carry_states(known, _clock_panes(raw), 30.0, true)
	_eq(known.p.since, 20.0, "still blocked with no identity: the launch ending is no new state")


func test_status_event_precedes_agent_snapshot_without_losing_identity() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	_ctl(
		"emit",
		{"envelope": {"event": "pane.agent_status_changed", "data": {"pane_id": "alpha:p1", "agent_status": "blocked"}}}
	)
	_pump(func() -> bool: return rec.snapshots > signals, "event arrives before the refreshed snapshot")
	var model := OfficeProjection.panes_of(client.snapshot, _states())[0]
	_eq(model.state, "blocked", "older agents status never hides the immediate pane event")
	var provisional := client.state_since("alpha:p1")
	_check(model.session != null and provisional > 0.0, "the known session can time the observed event")
	var next := _fixture("snapshot_basic")
	var panes: Array = next.panes
	var pane: Dictionary = panes[0]
	pane.agent_status = "blocked"
	var session: Dictionary = pane.agent_session
	session.value = "replacement-session"
	var agents: Array = next.agents
	var pending: Dictionary = agents[0]
	pending.launch_pending = true
	pending.agent_session = session.duplicate()
	_ctl("set_snapshot", {"snapshot": next})
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	_settle()
	_check(client.state_since("alpha:p1") > provisional, "a new blocked session is timed anew")
	var updated := OfficeProjection.panes_of(client.snapshot, _states())[0]
	_check(updated.session != null, "replacement identity remains typed")
	if updated.session != null:
		_eq(updated.session.value, "replacement-session", "the replacement session reaches consumers")
	_check(updated.starting, "the matched provider's launch flag is applied")
	signals = rec.snapshots
	_ctl(
		"emit",
		{
			"envelope":
			{
				"event": "pane.agent_status_changed",
				"data":
				{
					"pane_id": "alpha:p1",
					"agent_status": "working",
					"agent": "codex",
				}
			}
		}
	)
	_pump(func() -> bool: return rec.snapshots > signals, "a provider change arrives before its snapshot")
	var replacement := OfficeProjection.panes_of(client.snapshot, _states())[0]
	_eq([replacement.provider, replacement.state], ["codex", "working"], "provider and status update immediately")
	_check(
		not replacement.starting and not replacement.starting_known, "the old provider's launch flag is not inherited"
	)
	# The new agent's state starts when it is seen.
	var codex_since := client.state_since("alpha:p1")
	_check(codex_since > 0.0, "the old provider's clock is not inherited: the new agent's starts now")


func test_stream_closed_by_server() -> void:
	if not _connect_settled():
		return
	var pings := _count(_list(_ctl("stats"), "methods"), "ping")
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 1, "disconnected after the stream closed")
	_check(not client.online, "offline")
	_check(not client.snapshot.is_empty(), "last snapshot stays readable")
	_eq(client._retry_left, HerdrClient.BACKOFF_MIN, "first retry after BACKOFF_MIN")
	_step(HerdrClient.BACKOFF_MIN - 0.01)
	_pump_frames(10)
	_eq(_count(_list(_ctl("stats"), "methods"), "ping"), pings, "no ping before the backoff elapses")
	_step(0.02)
	_settle()
	_eq(_count(_list(_ctl("stats"), "methods"), "ping"), pings + 1, "one ping after the backoff")
	_eq(rec.connected, 2, "connected again")
	_eq(rec.disconnected, 1, "one disconnect")


func test_socket_vanishes_with_backoff() -> void:
	if not _connect_settled():
		return
	_ctl("vanish")
	_pump(func() -> bool: return rec.disconnected == 1, "disconnected when herdr goes away")
	var stats := _ctl("stats")
	_check(not _flag(stats, "socket_present", true), "socket file is gone")
	var delays: Array = [client._retry_left]
	for attempt in 5:
		_step(client._retry_left)
		delays.append(client._retry_left)
	_eq(delays, [0.5, 1.0, 2.0, 4.0, 5.0, 5.0], "exponential backoff 0.5s -> 5s")
	_eq(rec.disconnected, 1, "one disconnected per offline episode")
	_step(client._retry_left - 0.01)
	_check(client._retry_left > 0.0 and client._retry_left < 0.02, "no attempt before the delay is up")
	_ctl("appear")
	_step(0.02)
	if not _settle():
		return
	_eq(rec.connected, 2, "connected again once the socket is back")
	_eq(client._backoff, HerdrClient.BACKOFF_MIN, "backoff resets after a live stream")
	# And the next episode starts from the bottom again.
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 2, "second episode")
	_eq(client._retry_left, HerdrClient.BACKOFF_MIN, "second episode retries after BACKOFF_MIN")


func test_stale_pane_id_recovers() -> void:
	# The client reconnects holding a snapshot whose pane herdr has closed since:
	# the subscribe fails with pane_not_found and the client refreshes, then retries.
	if not _connect_settled():
		return
	var grown := _fixture("snapshot_grown")
	_ctl("set_snapshot", {"fixture": "snapshot_grown"})
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 1, "disconnected")
	var mark := _list(_ctl("stats"), "methods").size()
	_step(HerdrClient.BACKOFF_MIN)
	if not _settle():
		return
	var stats := _server_until(func(s: Dictionary) -> bool: return s.streams_live == 1, "one live stream")
	_eq(
		_list(stats, "methods").slice(mark),
		["ping", "events.subscribe", "session.snapshot", "events.subscribe", "session.snapshot"],
		"stale subscribe -> snapshot -> subscribe"
	)
	_eq(stats.stream_errors, ["pane_not_found alpha:p2"], "herdr rejected the stale pane")
	_eq(stats.last_subscribe_panes, _pane_ids(grown), "retried with the fresh pane set")
	_eq(rec.disconnected, 1, "pane_not_found is not another disconnect")
	_eq(client._probe_retries, 0, "retry budget reset once live")


func test_request_timeout() -> void:
	if not _connect_settled():
		return
	_ctl("next", {"action": "hang", "method": "session.snapshot"})
	_ctl("emit", {"fixture_event": "pane_updated"})
	_pump(func() -> bool: return rec.events.size() == 1, "event")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	_server_until(func(s: Dictionary) -> bool: return s.hung == 1, "server holding the snapshot request")
	for second in 4:
		_step(1.0)
		_pump_frames(5)
	_check(client.online and rec.disconnected == 0, "still online while the request has time left")
	_eq(client._requests.size(), 1, "the silent request is still pending")
	# Small steps across the deadline: a big one would also run down the backoff.
	_step(0.99)
	_eq(rec.disconnected, 0, "not yet")
	_step(0.02)
	_eq(rec.disconnected, 1, "a request that never answers gives up after REQUEST_TIMEOUT")
	_check(client._requests.is_empty(), "no request left behind")
	_step(HerdrClient.BACKOFF_MIN)
	_settle()
	_eq(rec.connected, 2, "recovers after the timeout")


func test_ping_timeout() -> void:
	_ctl("reset", {"fixture": "snapshot_basic"})
	_ctl("next", {"action": "hang", "method": "ping"})
	_start_client()
	_server_until(func(s: Dictionary) -> bool: return s.hung == 1, "server holding the ping")
	_step(HerdrClient.REQUEST_TIMEOUT - 0.1)
	_pump_frames(10)
	_eq(rec.disconnected, 0, "waits the whole timeout")
	_step(0.2)
	_eq(rec.disconnected, 1, "a silent ping counts as offline")
	_step(HerdrClient.BACKOFF_MIN)
	_settle()
	_eq(rec.connected, 1, "connects on the retry")


func test_ping_error_and_drop() -> void:
	_ctl("reset", {"fixture": "snapshot_basic"})
	_ctl(
		"next",
		{
			"action": "reply",
			"method": "ping",
			"line": '{"id":"$ID","error":{"code":"internal","message":"synthetic failure"}}'
		}
	)
	_ctl("next", {"action": "drop", "method": "ping"})
	_start_client()
	_pump(func() -> bool: return rec.disconnected == 1, "error reply to ping -> offline")
	_eq(client._retry_left, 0.5, "retry scheduled after an error reply")
	_step(client._retry_left)
	# Closed without an answer.
	_pump(func() -> bool: return client._retry_left > 0.0, "dropped ping -> retry scheduled")
	_eq(client._retry_left, 1.0, "second failure backs off further")
	_step(client._retry_left)
	_settle()
	_eq(rec.connected, 1, "third ping connects")
	_eq(rec.disconnected, 1, "one disconnect for the whole episode")


func test_malformed_stream_lines() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	_ctl(
		"raw",
		{
			"chunks":
			[
				"this is not json\n",
				"[1, 2, 3]\n",
				"{}\n",
				"\n",
				"42\n",
				'{"event":"mystery.thing","data":{"x":1}}\n',
				'{"event":"pane_updated"}\n',
				'{"event":"pane.agent_status_changed","data":{"pane_id":"ghost:p9","agent_status":"working"}}\n',
				'{"result":{"type":"something_else"}}\n',
			],
			"pause": 0.0
		}
	)
	_ctl("raw", {"hex": true, "chunks": ["fffe7b0a"], "pause": 0.0})
	_pump(func() -> bool: return rec.events.size() >= 3, "the well-formed envelopes")
	_pump_frames(20)
	_check(client.online and rec.disconnected == 0, "junk on the stream is not a disconnect")
	_eq(
		rec.events.map(func(e: Array) -> String: return e[0]),
		["mystery.thing", "pane_updated", "pane.agent_status_changed"],
		"unknown event names pass through"
	)
	_eq(rec.snapshots, signals, "status for an unknown pane changes nothing")
	# The stream still works afterwards.
	_ctl("status", {"pane_id": "alpha:p3", "agent_status": "done"})
	_pump(func() -> bool: return _pane_status("alpha:p3") == "done", "stream still alive after junk")
	_eq(_ctl("stats").streams_live, 1, "same stream")


func test_split_utf8_lines() -> void:
	if not _connect_settled():
		return
	# One status line and one event cut mid-way through multi-byte characters.
	var envelope := {"event": "tab_renamed", "data": {"type": "tab_renamed", "tab_id": "alpha:t1", "label": "中文标题 ✓"}}
	var bytes := (JSON.stringify(envelope) + "\n").to_utf8_buffer()
	var cut := bytes.find("中".to_utf8_buffer()[0]) + 1
	var chunks := [
		bytes.slice(0, cut).hex_encode(), bytes.slice(cut, cut + 4).hex_encode(), bytes.slice(cut + 4).hex_encode()
	]
	_ctl("raw", {"hex": true, "chunks": chunks, "pause": 0.05})
	_pump(func() -> bool: return rec.events.size() == 1, "reassembled event")
	if rec.events.size() == 1:
		_eq(rec.event_data(0).get("label", ""), "中文标题 ✓", "multi-byte text survives a split read")
	_check(client.online, "still online")


func test_malformed_responses() -> void:
	if not _connect_settled():
		return
	var held := client.snapshot.signature()
	var signals := rec.snapshots
	var count: int = _ctl("stats").snapshot_count
	for reply: String in ["this is not json", '{"id":"$ID","error":{"code":"internal","message":"synthetic failure"}}']:
		_ctl("next", {"action": "reply", "method": "session.snapshot", "line": reply})
		_step(HerdrClient.SNAPSHOT_INTERVAL)
		count += 1
		_server_until(func(s: Dictionary) -> bool: return s.snapshot_count == count, "snapshot request")
		_pump(func() -> bool: return client._requests.is_empty(), "request settled")
		_check(client.online and rec.disconnected == 0, "a bad snapshot reply keeps the stream: " + reply)
		_eq(rec.snapshots, signals, "nothing applied from a bad reply")
		_eq(client.snapshot.signature(), held, "snapshot unchanged")
		_check(not client._snapshot_inflight, "next fetch is not blocked")
	# A reply identical to the held snapshot is applied without an announcement,
	# so the good one carries a change the client has to announce.
	_ctl("set_snapshot", {"fixture": "snapshot_grown"})
	_step(HerdrClient.SNAPSHOT_INTERVAL)
	_pump(func() -> bool: return rec.snapshots > signals, "a good reply applies again")
	_eq(_held_pane_ids(), _pane_ids(_fixture("snapshot_grown")), "with what it carried")


# --- robustness cases -----------------------------------------------------------


## A ping reply that is not an envelope with an object `result` is a failed
## probe: one `disconnected`, backoff, and no snapshots while offline.
func test_unreadable_ping_reply_retries() -> void:
	var replies := [
		"this is not json",
		'{"id":"$ID","result":"pong"}',
		"[1, 2]",
		'{"id":"$ID"}',
		'{"id":"$ID","error":"boom"}',
	]
	for reply: String in replies:
		_ctl("reset", {"fixture": "snapshot_basic"})
		_ctl("next", {"action": "reply", "method": "ping", "line": reply})
		_start_client()
		_pump(func() -> bool: return rec.disconnected == 1, "offline after ping reply " + reply)
		_eq(client._retry_left, HerdrClient.BACKOFF_MIN, "retry scheduled after " + reply)
		_step(HerdrClient.BACKOFF_MIN)
		_settle()
		_eq(rec.connected, 1, "the retry connects after " + reply)
		_eq(
			_list(_ctl("stats"), "methods").slice(0, 4),
			["ping", "ping", "events.subscribe", "session.snapshot"],
			"nothing but pings before the stream after " + reply
		)
		_finish_client()
	# A server that keeps answering garbage: 30s of retries, not a single snapshot.
	_ctl("reset", {"fixture": "snapshot_basic"})
	for attempt in 12:
		_ctl("next", {"action": "reply", "method": "ping", "line": "this is not json"})
	_start_client()
	for tick in 300:
		_step(0.1)
		_pump_frames(1)
	var methods: Array = _ctl("stats").methods
	_eq(methods.filter(func(m: String) -> bool: return m != "ping"), [], "only pings while the probe keeps failing")
	_check(methods.size() >= 8, "kept retrying: %d pings in 30s" % methods.size())
	_eq(rec.disconnected, 1, "one disconnected for the whole episode")
	_check(
		not client.online and client._retry_left > 0.0 or client._requests.size() == 1, "still retrying, not stalled"
	)


## No snapshot request while offline, however long the outage, and the
## reconnect runs ping, subscribe, snapshot in that order.
func test_no_snapshot_while_offline() -> void:
	if not _connect_settled():
		return
	# A debounce is pending when the stream drops; it must not survive.
	_ctl("emit", {"fixture_event": "pane_updated"})
	_pump(func() -> bool: return rec.events.size() == 1, "event")
	for attempt in 6:
		_ctl("next", {"action": "drop", "method": "ping"})
	var mark := _list(_ctl("stats"), "methods").size()
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 1, "disconnected")
	_check(not client._want_snapshot and client._debounce_left <= 0.0, "offline keeps no wish to fetch")
	# Frame-sized steps across 0.5+1+2+4+5+5s of failed pings, well past the interval.
	for tick in 200:
		_step(0.1)
		_pump_frames(1)
	var during := _list(_ctl("stats"), "methods").slice(mark)
	_eq(during.filter(func(m: String) -> bool: return m != "ping"), [], "only pings during a 20s outage")
	_check(during.size() >= 5, "the outage was probed: %s" % [during])
	var back: int = during.size() + mark
	# Hold the ack: until the stream is live, the reconnect must not fetch.
	_ctl("hold_ack", {"hold": true})
	for tick in 60:
		_step(0.1)
		_pump_frames(1)
	_server_until(func(s: Dictionary) -> bool: return s.streams_pending == 1, "reconnect waiting for its ack")
	_eq(
		_list(_ctl("stats"), "methods").slice(back),
		["ping", "events.subscribe"],
		"no snapshot before subscription_started"
	)
	_ctl("release")
	_settle()
	var after := _list(_ctl("stats"), "methods").slice(back)
	_eq(after.slice(0, 3), ["ping", "events.subscribe", "session.snapshot"], "reconnect order")
	_eq(rec.connected, 2, "reconnected")


## Stream lines of the right syntax but the wrong types are ignored, and a
## non-object `error` still counts as an error.
func test_type_confused_stream_lines() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	_ctl(
		"raw",
		{
			"chunks":
			[
				'{"event":"pane_updated","data":null}\n',
				'{"event":"layout_updated","data":[1,2]}\n',
				'{"event":"pane.agent_status_changed","data":"alpha:p1"}\n',
				'{"result":"subscription_started"}\n',
				'{"result":null}\n',
				(
					JSON.stringify(
						{"event": "pane.agent_status_changed", "data": {"pane_id": "alpha:p1", "agent_status": "done"}}
					)
					+ "\n"
				),
			],
			"pause": 0.0
		}
	)
	_pump(func() -> bool: return _pane_status("alpha:p1") == "done", "good line after the bad ones")
	_eq(
		rec.events.map(func(e: Array) -> String: return e[0]),
		["pane.agent_status_changed"],
		"badly typed events never reach event_received"
	)
	_eq(rec.snapshots, signals + 1, "only the good status line changed the snapshot")
	_check(client.online and rec.disconnected == 0, "still online")
	for line: String in ['{"error":"boom"}', '{"error":42}']:
		_ctl("raw", {"chunks": [line + "\n"], "pause": 0.0})
		_pump(func() -> bool: return not client.online, "a non-object error is an error: " + line)
		_step(HerdrClient.BACKOFF_MIN)
		_settle()
		_check(client.online, "recovers after " + line)
	_eq(rec.disconnected, 2, "each bad error line was one offline episode")


## Snapshot replies of the wrong types are dropped without going offline,
## the backstop asks again, and non-object panes are skipped.
func test_type_confused_responses() -> void:
	if not _connect_settled():
		return
	var held := client.snapshot.signature()
	var signals := rec.snapshots
	var count: int = _ctl("stats").snapshot_count
	for reply: String in [
		"[1, 2]",
		'{"id":"$ID","result":"session_snapshot"}',
		'{"id":"$ID","result":{"type":"session_snapshot","snapshot":"nope"}}',
		'{"id":"$ID","result":{"type":"session_snapshot"}}',
		'{"id":"$ID","result":{"type":"session_snapshot","snapshot":{"panes":"nope"}}}',
		'{"id":"$ID","error":"boom"}',
	]:
		_ctl("next", {"action": "reply", "method": "session.snapshot", "line": reply})
		_step(HerdrClient.SNAPSHOT_INTERVAL)
		count += 1
		_server_until(func(s: Dictionary) -> bool: return s.snapshot_count == count, "snapshot request")
		_pump(func() -> bool: return client._requests.is_empty(), "request settled")
		_check(client.online and rec.disconnected == 0, "a badly typed snapshot keeps the stream: " + reply)
		_eq(rec.snapshots, signals, "nothing applied from " + reply)
		_eq(client.snapshot.signature(), held, "snapshot unchanged by " + reply)
		_check(not client._snapshot_inflight, "next fetch is not blocked after " + reply)
	# Junk among the panes: the objects still apply, the rest is skipped. One
	# status differs from the held snapshot, so applying it is announced.
	var mixed := _fixture("snapshot_basic")
	var panes := _list(mixed, "panes").duplicate()
	var first: Dictionary = panes[0]
	first.agent_status = "blocked"
	panes.insert(1, 7)
	panes.append("junk")
	panes.append(null)
	mixed.panes = panes
	var line := JSON.stringify({"id": "$ID", "result": {"type": "session_snapshot", "snapshot": mixed}})
	_ctl("next", {"action": "reply", "method": "session.snapshot", "line": line})
	_step(HerdrClient.SNAPSHOT_INTERVAL)
	_pump(func() -> bool: return rec.snapshots > signals, "snapshot with junk panes applied")
	_eq(_held_pane_ids(), _pane_ids(_fixture("snapshot_basic")), "only object panes are kept")
	_eq(_pane_status(str(first.pane_id)), "blocked", "and they are the ones the reply carried")
	_eq(
		client._pane_ids(),
		PackedStringArray(_pane_ids(_fixture("snapshot_basic"))),
		"pane set unchanged, no resubscribe needed"
	)
	_ctl("status", {"pane_id": "bravo:p1", "agent_status": "done"})
	_pump(func() -> bool: return _pane_status("bravo:p1") == "done", "status still applies")


## The pane loops themselves skip anything that is not an object, whatever
## put it into the snapshot.
func test_non_object_panes_in_client() -> void:
	_new_client()
	client._apply_snapshot(
		{
			"panes":
			[1, "x", null, [2], {"pane_id": "p2", "agent_status": "idle"}, {"pane_id": "p1", "agent_status": "idle"}]
		}
	)
	_eq(client._pane_ids(), PackedStringArray(["p1", "p2"]), "_pane_ids skips non-object panes")
	client._apply_status({"pane_id": "p1", "agent_status": "working"})
	_eq(_pane_status("p1"), "working", "_apply_status still finds the object pane")
	_eq(rec.snapshots, 2, "and announces it after the initial complete snapshot")
	client._apply_status({"pane_id": "ghost", "agent_status": "working"})
	_eq(rec.snapshots, 2, "an unknown pane changes nothing")
	# The one way in is the snapshot boundary now, which reads panes that are
	# not a list as none: a change from two panes, so it is announced once.
	client._apply_snapshot({"panes": "not a list"})
	var signals := rec.snapshots
	_eq(client._pane_ids(), PackedStringArray(), "panes that are not a list read as none")
	client._apply_status({"pane_id": "p1", "agent_status": "done"})
	_eq(rec.snapshots, signals, "nothing to update")


## Lines that arrived before herdr closed the stream are still read, and
## the close itself is noticed without reading the closed peer (run_tests.sh
## fails the run if the engine complains about a closed socket).
func test_closed_stream_keeps_last_lines() -> void:
	if not _connect_settled():
		return
	# Both land before the client polls again: data, then the hangup.
	_ctl("status", {"pane_id": "alpha:p3", "agent_status": "blocked"})
	_ctl("emit", {"fixture_event": "pane_exited"})
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 1, "disconnected")
	_eq(_pane_status("alpha:p3"), "blocked", "status line sent before the close was applied")
	_eq(
		rec.events.map(func(e: Array) -> String: return e[0]),
		["pane.agent_status_changed", "pane_exited"],
		"every line before the close was read"
	)


# --- announcing only change, and input caps -----------------------------------


## A re-fetch that brings back the snapshot the client already holds changes
## nothing on screen, so it announces nothing: neither the one a topology event
## asks for, nor the backstop's, which finds nothing new most of the time.
func test_unchanged_refetch_emits_nothing() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	var readiness := rec.readiness
	var count: int = _ctl("stats").snapshot_count
	_ctl("emit", {"fixture_event": "pane_updated"})
	_pump(func() -> bool: return rec.events.size() == 1, "a topology event")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	_settle()
	_pump_frames(10)
	_eq(_ctl("stats").snapshot_count, count + 1, "the event still asks for a snapshot")
	_eq(rec.snapshots, signals, "an identical snapshot is not announced")
	_check(client.online and client.snapshot_current, "and the client stays live and current")
	_step(HerdrClient.SNAPSHOT_INTERVAL + 0.01)
	_settle()
	_pump_frames(10)
	_eq(_ctl("stats").snapshot_count, count + 2, "the backstop fetched")
	_eq(rec.snapshots, signals, "an unchanged backstop snapshot is not announced either")
	_eq(rec.readiness, readiness, "and readiness does not flap")


## A status event is shown at once; the debounced re-fetch that agrees with it
## is not a second change.
func test_status_then_identical_refetch_emits_once() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	var count: int = _ctl("stats").snapshot_count
	_ctl("status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	_pump(func() -> bool: return rec.snapshots > signals, "the status event is shown")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	_settle()
	_pump_frames(10)
	_eq(_ctl("stats").snapshot_count, count + 1, "the event is followed by one re-fetch")
	_eq(rec.snapshots, signals + 1, "which agrees with the event and announces nothing more")
	_eq(_pane_status("alpha:p1"), "blocked", "the status stays")


## Announcing only change must not swallow a real one: a new pane set is
## announced exactly once, although it also costs a re-subscription and the
## re-fetch that covers it.
func test_a_real_change_emits() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	_ctl("set_snapshot", {"fixture": "snapshot_grown"})
	_step(HerdrClient.SNAPSHOT_INTERVAL + 0.01)
	_settle()
	_pump_frames(10)
	_eq(_held_pane_ids(), _pane_ids(_fixture("snapshot_grown")), "the new pane set is held")
	_eq(rec.snapshots, signals + 1, "and announced once")


## A line that never ends: past LINE_MAX bytes its channel fails without any of
## it decoded. A snapshot reply fails its request the way a dead one does, and
## without waiting for its timeout; a stream line drops the stream. Either way
## the client goes offline and backs off as it does for any failed channel.
func test_oversized_line_fails_its_channel() -> void:
	if not _connect_settled():
		return
	var signals := rec.snapshots
	var held := client.snapshot.signature()
	_ctl("next", {"action": "flood", "method": "session.snapshot", "bytes": HerdrClient.LINE_MAX + 1})
	# The request goes out at the end of this step; no synthetic time passes
	# after it, so REQUEST_TIMEOUT cannot be what ends it.
	_step(HerdrClient.SNAPSHOT_INTERVAL + 0.01)
	_drain_until(func() -> bool: return rec.disconnected == 1, "the oversized reply fails its request")
	_check(not client.online, "the client goes offline")
	_eq(rec.snapshots, signals, "nothing of the reply is applied")
	_eq(client.snapshot.signature(), held, "the last snapshot stays readable")
	_step(HerdrClient.BACKOFF_MIN)
	_settle()
	_eq(rec.connected, 2, "and reconnects after the usual backoff")
	_server_until(func(s: Dictionary) -> bool: return s.streams_live == 1, "one live stream again")
	_eq(_ctl("flood", {"bytes": HerdrClient.LINE_MAX + 1}).sent, 1, "a flood reaches the live stream")
	_drain_until(func() -> bool: return rec.disconnected == 2, "the oversized stream line drops the stream")
	_check(not client.online, "the client goes offline again")
	_step(HerdrClient.BACKOFF_MIN)
	_settle()
	_eq(rec.connected, 3, "and reconnects after the usual backoff again")
	# A herdr whose every reply is too long must not make the client reconnect
	# twice a second: the stream coming back proves nothing until a snapshot is
	# read, so the backoff keeps growing and settles at BACKOFF_MAX.
	var floods := 5
	for flood in floods:
		_ctl("next", {"action": "flood", "method": "session.snapshot", "bytes": HerdrClient.LINE_MAX + 1})
	_step(HerdrClient.SNAPSHOT_INTERVAL + 0.01)
	var wait := HerdrClient.BACKOFF_MIN
	for flood in floods:
		_drain_until(func() -> bool: return rec.disconnected == 3 + flood, "flooded reply %d fails its request" % flood)
		_retry_after(wait, "flood %d" % flood)
		wait = minf(HerdrClient.BACKOFF_MAX, wait * 2.0)
	_eq(wait, HerdrClient.BACKOFF_MAX, "five floods are enough for the last wait checked to be BACKOFF_MAX")
	_settle()
	_check(client.online and client.snapshot_current, "the reply that fits is read")
	# Once a snapshot is read, a new episode starts from the bottom again.
	_ctl("close_streams")
	_pump(func() -> bool: return rec.disconnected == 3 + floods, "a later hangup")
	_retry_after(HerdrClient.BACKOFF_MIN, "a snapshot was read")
	_settle()


## A snapshot listing more panes than the cap is refused whole, every time it
## comes. The one held stays on screen, but it is no longer herdr's picture: the
## machine is stale (invariant 4) and status events wait, as after any gap. The
## stream stays live, and the next readable snapshot makes the machine current
## again, with no start time carried across the gap.
func test_too_many_records_are_refused() -> void:
	if not _connect_settled():
		return
	# A watched transition gives alpha:p1 a known start before the gap.
	var signals := rec.snapshots
	_ctl("status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	_pump(func() -> bool: return rec.snapshots > signals, "a watched transition")
	_step(HerdrClient.SNAPSHOT_DEBOUNCE + 0.01)
	_settle()
	_check(client.state_since("alpha:p1") > 0.0, "starts a clock")
	signals = rec.snapshots
	var readiness := rec.readiness
	var held := client.snapshot.signature()
	var huge := _fixture("snapshot_basic")
	# Empty records keep the reply small to parse: the cap counts records, not bytes.
	var panes: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		panes.append({})
	huge.panes = panes
	_ctl("set_snapshot", {"snapshot": huge})
	for attempt in 2:
		var count: int = _ctl("stats").snapshot_count
		_step(HerdrClient.SNAPSHOT_INTERVAL + 0.01)
		_server_until(func(s: Dictionary) -> bool: return s.snapshot_count == count + 1, "a re-fetch")
		_settle()
		_check(client.online and rec.disconnected == 0, "a refused snapshot keeps the stream (%d)" % attempt)
		_eq(rec.snapshots, signals, "and is not applied (%d)" % attempt)
		_eq(client.snapshot.signature(), held, "the held snapshot stays (%d)" % attempt)
		_check(not client.snapshot_current, "but is no longer current: the machine is stale (%d)" % attempt)
		_eq(rec.readiness, readiness + 1, "which is announced once (%d)" % attempt)
	var received := rec.events.size()
	var event := {"pane_id": "alpha:p1", "agent_status": "working"}
	_ctl("emit", {"envelope": {"event": "pane.agent_status_changed", "data": event}})
	_pump(func() -> bool: return rec.events.size() > received, "a status event while stale")
	_eq(_pane_status("alpha:p1"), "blocked", "waits for a snapshot to be read")
	_eq(rec.snapshots, signals, "and changes nothing on screen")
	_ctl("set_snapshot", {"fixture": "snapshot_grown"})
	_step(HerdrClient.SNAPSHOT_INTERVAL + 0.01)
	_pump(func() -> bool: return rec.snapshots > signals, "a readable snapshot applies again")
	_eq(_held_pane_ids(), _pane_ids(_fixture("snapshot_grown")), "with its own panes")
	_check(client.snapshot_current, "and the machine is current again")
	_eq(rec.readiness, readiness + 2, "which is announced once more")
	_eq(client.state_since("alpha:p1"), -1.0, "no start time survives the gap")


# --- office cases -------------------------------------------------------------


func test_office_projection() -> void:
	var states := _states()
	var floors := OfficeProjection.project(_view_fixture("snapshot_office"), states)
	_eq(
		floors.map(func(f: FloorModel) -> String: return f.label),
		["charlie", "中文 space", "echo"],
		"floors follow workspace number"
	)
	_eq(floors.map(func(f: FloorModel) -> int: return f.number), [1, 2, 3], "each floor keeps herdr's number")
	_eq(
		floors.map(func(f: FloorModel) -> String: return f.repo),
		["sample-repo", "", "echo-repo"],
		"repo from worktree, empty without one"
	)
	_eq(floors[0].key, HerdrFleet.pane_key(HerdrFleet.LOCAL, "charlie"), "floor key is machine key + workspace id")
	var charlie := floors[0]
	_eq(charlie.rooms.map(func(r: RoomModel) -> String: return r.label), ["first", "second"], "rooms follow tab number")
	var desks := charlie.rooms[0].panes
	# Rects: p3 (0,0), p2 (80,0), p4 (80,40); p5 has no layout slot.
	_eq(
		desks.map(func(p: PaneModel) -> String: return p.pane_id),
		["charlie:p3", "charlie:p2", "charlie:p4", "charlie:p5"],
		"desks left to right by terminal rect, unplaced last"
	)
	var sides := {}
	for desk in desks:
		sides[desk.pane_id] = desk.side
	_eq(
		sides,
		{"charlie:p3": "far", "charlie:p2": "far", "charlie:p4": "near", "charlie:p5": "far"},
		"layout y maps panes to opposite table sides"
	)
	_eq(desks[0].key, HerdrFleet.pane_key(HerdrFleet.LOCAL, "charlie:p3"), "desk key carries the machine")
	_eq(HerdrFleet.split_key(desks[0].key), PackedStringArray([HerdrFleet.LOCAL, "charlie:p3"]), "desk key splits back")
	_eq(desks[0].machine(), HerdrFleet.LOCAL, "and names the machine it stands on")
	var other := OfficeProjection.project(_view_fixture("snapshot_office"), states, "machine:x")
	_eq(
		other[0].rooms[0].panes[0].key,
		HerdrFleet.pane_key("machine:x", "charlie:p3"),
		"another machine keys its own desks"
	)
	_eq(other[0].key, HerdrFleet.pane_key("machine:x", "charlie"), "and its own floors")
	var by_id := {}
	for desk in desks:
		by_id[desk.pane_id] = desk
	var second: PaneModel = by_id["charlie:p2"]
	var shell: PaneModel = by_id["charlie:p3"]
	_eq(second.state, "unknown", "unknown agent_status falls back to unknown")
	_eq(by_id["charlie:p5"].state, "unknown", "missing agent_status reads as unknown")
	_eq(shell.provider, "", "no agent is a SHELL desk")
	_eq(shell.state, "idle", "shell keeps its state")
	var launching: PaneModel = by_id["charlie:p4"]
	_check(launching.starting, "launch_pending -> starting")
	_check(not second.starting, "no launch_pending -> not starting")
	_eq(second.provider, "codex", "provider from agent")
	# What the inspector shows rides on the desk too, so no panel reads a snapshot.
	_eq(
		[second.cwd, second.cwd_name(), second.terminal_title],
		["/home/tester/charlie", "charlie", "codex session"],
		"a desk carries the inspector's cwd and terminal title"
	)
	_eq(
		[second.workspace_label, second.tab_label],
		["charlie", "first"],
		"and the labels of the floor and room it sits in"
	)
	_eq(floors[2].rooms[0].panes[0].state, "blocked", "known states pass through")
	_check(OfficeProjection.project(HerdrSnapshot.new(), states).is_empty(), "empty snapshot, no floors")
	# The id arrives with a separator in it; neither the boundary nor the key lets it through.
	var sneaky := OfficeProjection.project(
		_view({"workspaces": [{"workspace_id": "w" + HerdrFleet.KEY_SEPARATOR + "socket:b", "number": 1}]}),
		states,
		"local"
	)
	_eq(sneaky[0].key, HerdrFleet.pane_key("local", "wsocket:b"), "a workspace id cannot smuggle in the separator")
	_eq(HerdrFleet.split_key(sneaky[0].key)[0], "local", "so no floor poses as another machine's")
	var twice := OfficeProjection.project(
		_view(
			{
				"workspaces":
				[
					{"workspace_id": "w", "number": 2, "label": "first"},
					{"workspace_id": "w", "number": 3, "label": "again"}
				]
			}
		),
		states
	)
	_eq(twice.map(func(f: FloorModel) -> String: return f.label), ["first"], "a repeated workspace id is one floor")


## Herdr's session focus reaches the desk it belongs to, and nothing else.
func test_office_focused_pane() -> void:
	var states := _states()
	var floors := OfficeProjection.project(_view_fixture("snapshot_floors"), states)
	var focused := PackedStringArray()
	for floor_model in floors:
		for room in floor_model.rooms:
			for pane in room.panes:
				if pane.focused:
					focused.append(pane.pane_id)
	_eq(focused, PackedStringArray(["api:p1"]), "exactly the pane herdr has focused")
	var unfocused_floor := OfficeProjection.project(_view(_two_panes("")), states)[0]
	var unfocused := unfocused_floor.rooms[0].panes
	_eq(
		unfocused.map(func(p: PaneModel) -> bool: return p.focused),
		[false, false],
		"a session without a focused pane focuses no desk"
	)
	var seated_floor := OfficeProjection.project(_view(_two_panes("p2")), states)[0]
	var seated := seated_floor.rooms[0].panes
	_eq(seated.map(func(p: PaneModel) -> bool: return p.focused), [false, true], "the focused desk is the focused one")
	_eq(
		seated[1].desk_signature(),
		unfocused[1].desk_signature(),
		"the focus moves a lamp, not the worker: it is no part of what seats a desk"
	)
	_eq(
		seated_floor.geometry_signature(),
		unfocused_floor.geometry_signature(),
		"and no part of the floor's geometry, so it never re-plans where desks stand"
	)


## Which tab of a workspace is open is a three-way answer: this one is, this one
## is not, and herdr did not say. Not saying is not a no.
func test_office_active_tab_is_three_valued() -> void:
	_eq(_open_tabs("w:t1"), [RoomModel.Active.YES, RoomModel.Active.NO], "the named tab is open, its sibling is not")
	_eq(
		_open_tabs(null),
		[RoomModel.Active.UNKNOWN, RoomModel.Active.UNKNOWN],
		"a workspace that names no open tab leaves every tab unknown"
	)
	for dirty: Variant in ["", {"id": "w:t1"}, ["w:t1"]]:
		_eq(
			_open_tabs(dirty),
			[RoomModel.Active.UNKNOWN, RoomModel.Active.UNKNOWN],
			"active_tab_id %s says nothing, so no tab is closed either" % var_to_str(dirty)
		)
	_eq(
		_open_tabs("w:t9"),
		[RoomModel.Active.NO, RoomModel.Active.NO],
		"an open tab this workspace does not hold closes the ones it does"
	)
	# A number is read as text at the boundary, as a numeric tab id is, so it
	# names the tab "7" (see test_from_wire_active_tab_and_worktree), which this
	# workspace does not hold.
	_eq(_open_tabs(7), [RoomModel.Active.NO, RoomModel.Active.NO], "a numeric open tab names the tab it spells")
	# Which tab is open is what a desk lamp shows, not where a desk stands: it
	# must never re-plan the floor.
	var states := _states()
	_eq(
		OfficeProjection.project(_view(_two_tabs("w:t2")), states)[0].geometry_signature(),
		OfficeProjection.project(_view(_two_tabs("w:t1")), states)[0].geometry_signature(),
		"the open tab moving is not a geometry change"
	)


## A linked worktree's checkout directory, which the floor plate shows after the
## repository. Anything else leaves the floor without one.
func test_office_floor_worktree() -> void:
	var linked := _worktree_floor(
		{"repo_name": "herdstead", "checkout_path": "/home/t/.worktrees/lane-a", "is_linked_worktree": true}
	)
	_eq([linked.repo, linked.worktree], ["herdstead", "lane-a"], "the checkout's last component, after the repo")
	_eq(
		(
			_worktree_floor({"repo_name": "herdstead", "checkout_path": "/home/t/lane-b/", "is_linked_worktree": true})
			. worktree
		),
		"lane-b",
		"a trailing separator is not a component"
	)
	_eq(
		_worktree_floor({"repo_name": "herdstead", "checkout_path": "/home/t/x", "is_linked_worktree": false}).worktree,
		"",
		"a worktree that is not linked is just the repo"
	)
	_eq(
		(
			_worktree_floor({"repo_name": "herdstead", "checkout_path": "/home/t/x", "is_linked_worktree": "true"})
			. worktree
		),
		"",
		'and the string "true" is not linked either'
	)
	_eq(
		(
			_worktree_floor({"repo_name": "herdstead", "checkout_path": ["/home/t/x"], "is_linked_worktree": true})
			. worktree
		),
		"",
		"a checkout path that is not text is no checkout"
	)
	_eq(_worktree_floor(null).worktree, "", "a workspace without a worktree has none")


func test_office_layout_ranks() -> void:
	var ranks := OfficeProjection.layout_ranks(_view_fixture("snapshot_basic"))
	# Snapshot order is p3, p1, p2; same x sorts top to bottom.
	_eq(ranks.get("alpha:t1", {}), {"alpha:p1": 0, "alpha:p2": 1, "alpha:p3": 2}, "rank by x, then y")
	_eq(
		OfficeProjection.layout_sides(_view_fixture("snapshot_basic")).get("alpha:t1", {}),
		{"alpha:p1": "far", "alpha:p2": "near", "alpha:p3": "far"},
		"layout sides retain herdr's y information"
	)
	_eq(
		OfficeProjection.layout_x(_view_fixture("snapshot_basic")).get("alpha:t1", {}),
		{"alpha:p1": 0, "alpha:p2": 0, "alpha:p3": 1},
		"layout x is the column's rank in the tab: the same x stays the same column"
	)
	var floors := OfficeProjection.project(_view_fixture("snapshot_grown"), _states())
	_eq(
		floors[1].rooms[0].panes.map(func(p: PaneModel) -> String: return p.pane_id),
		["bravo:p1", "bravo:p2"],
		"right-hand pane sits right"
	)


## Per-floor blocked/UNREAD counts follow OfficeAttention.count; a stale machine reports none.
func test_office_floor_counts() -> void:
	var states := _states()
	var snapshot := _view_fixture("snapshot_floors")
	var floors := OfficeProjection.project(snapshot, states)
	_eq(
		floors.map(func(f: FloorModel) -> String: return f.label),
		["api", "web", "infra", "notes", "数据 pipeline"],
		"floors by number, not listing order"
	)
	_eq(
		floors.map(func(f: FloorModel) -> Array: return [f.blocked, f.done]),
		[[0, 0], [1, 1], [1, 1], [0, 0], [0, 0]],
		"blocked and UNREAD per floor_model"
	)
	# data: a working agent plus one still launching; notes: a shell only.
	_eq(
		floors.map(func(f: FloorModel) -> int: return f.agents),
		[3, 2, 3, 0, 2],
		"agents per floor_model, a launching one included"
	)
	var total := OfficeAttention.count(OfficeProjection.panes_of(snapshot, states))
	var blocked := 0
	var done := 0
	for floor_model in floors:
		blocked += floor_model.blocked
		done += floor_model.done
	_eq([blocked, done], [total.blocked, total.done], "floors add up to the office's own count")
	var launching := _view_fixture("snapshot_floors")
	for pane in launching.panes:
		if pane.pane_id == "web:p1":
			pane.launch_pending = true
			pane.launch_pending_known = true
	_eq(
		OfficeProjection.project(launching, states)[1].blocked,
		1,
		"blocked comes first: a blocked agent still launching counts, as in OfficeAttention.count"
	)
	var dropped := OfficeProjection.project(snapshot, states, HerdrFleet.LOCAL, true)
	_eq(
		dropped.map(func(f: FloorModel) -> Array: return [f.blocked, f.done]),
		[[0, 0], [0, 0], [0, 0], [0, 0], [0, 0]],
		"a stale machine's floors report none"
	)
	_eq(
		dropped.map(func(f: FloorModel) -> String: return f.label),
		floors.map(func(f: FloorModel) -> String: return f.label),
		"but keep their rooms"
	)
	# The counts are not part of where desks stand: a machine that flaps must not re-plan it.
	var drawn := floors[1].geometry_signature()
	floors[1].agents += 1
	floors[1].blocked += 1
	floors[1].done += 1
	_eq(floors[1].geometry_signature(), drawn, "counts stay out of the floor's geometry")


## A building with no floors gets a lobby whose key no workspace can have.
func test_office_lobby() -> void:
	var states := _states()
	var empty := OfficeProjection.building("machine:x", "far", HerdrSnapshot.new(), states, true)
	_eq(empty.floors.size(), 1, "one lobby")
	var lobby := empty.floors[0]
	_check(lobby.lobby and lobby.rooms.is_empty(), "the lobby has no rooms")
	_eq(HerdrFleet.split_key(lobby.key)[0], "machine:x", "the lobby belongs to its machine")
	var blank := OfficeProjection.building(
		"machine:x", "far", _view({"workspaces": [{"workspace_id": "", "number": 1}]}), states, false
	)
	_eq(blank.floors.size(), 1, "a workspace whose id reads empty is a floor, not a lobby")
	_check(not blank.floors[0].lobby and blank.floors[0].key != lobby.key, "and never shares the lobby's key")
	var local := OfficeProjection.building("local", "Local", _view_fixture("snapshot_basic"), states, false)
	_eq(
		local.floors.map(func(f: FloorModel) -> bool: return f.lobby),
		[false, false],
		"a building with floors has no lobby"
	)
	# The bar adds machines up from these, not from the snapshot behind them.
	_eq([local.spaces, local.tabs, local.panes], [2, 2, 4], "a building counts its machine's whole snapshot")


func test_office_selection() -> void:
	var states := _states()
	var snapshot := _view_fixture("snapshot_office")
	var buildings: Array[BuildingModel] = [
		OfficeProjection.building(HerdrFleet.LOCAL, "Local", snapshot, states, false)
	]
	var focus := HerdrFleet.pane_key(HerdrFleet.LOCAL, "delta:p1")
	var picked := HerdrFleet.pane_key(HerdrFleet.LOCAL, "charlie:p4")
	_eq(OfficeProjection.effective_selection(buildings, "", focus), focus, "follows herdr focus by default")
	_eq(
		OfficeProjection.effective_selection(buildings, picked, focus),
		picked,
		"a picked pane wins over focus, on any floor"
	)
	# Same pane id on another machine is a different desk.
	var elsewhere: Array[BuildingModel] = [OfficeProjection.building("socket:b", "b", snapshot, states, false)]
	_eq(
		OfficeProjection.effective_selection(elsewhere, picked, focus),
		focus,
		"a picked pane id on another machine does not match"
	)
	var panes: Array[HerdrSnapshot.Pane] = []
	panes.assign(snapshot.panes.filter(func(p: HerdrSnapshot.Pane) -> bool: return p.pane_id != "charlie:p4"))
	snapshot.panes = panes
	var without: Array[BuildingModel] = [OfficeProjection.building(HerdrFleet.LOCAL, "Local", snapshot, states, false)]
	_eq(OfficeProjection.effective_selection(without, picked, focus), focus, "picked pane gone -> back to herdr focus")


## Picked floor, else the selection's floor, else the first real floor, else the lobby.
func test_office_floor_choice() -> void:
	var states := _states()
	var local := OfficeProjection.building(HerdrFleet.LOCAL, "Local", _view_fixture("snapshot_floors"), states, false)
	var bee := OfficeProjection.building("socket:bee", "bee", _view_fixture("snapshot_basic"), states, false)
	var buildings: Array[BuildingModel] = [local, bee]
	var floor_model := func(machine: String, workspace: String) -> String:
		return HerdrFleet.pane_key(machine, workspace)
	var on_api := HerdrFleet.pane_key(HerdrFleet.LOCAL, "api:p1")
	_eq(
		OfficeProjection.choose_floor(buildings, "", on_api),
		floor_model.call(HerdrFleet.LOCAL, "api"),
		"herdr focus brings its floor_model"
	)
	var on_bravo := HerdrFleet.pane_key("socket:bee", "bravo:p1")
	_eq(
		OfficeProjection.choose_floor(buildings, "", on_bravo),
		floor_model.call("socket:bee", "bravo"),
		"a selection on another building brings that floor_model"
	)
	_eq(
		OfficeProjection.choose_floor(buildings, str(floor_model.call(HerdrFleet.LOCAL, "infra")), on_bravo),
		floor_model.call(HerdrFleet.LOCAL, "infra"),
		"a picked floor_model beats the selection"
	)
	_eq(
		OfficeProjection.choose_floor(buildings, str(floor_model.call(HerdrFleet.LOCAL, "gone")), on_bravo),
		floor_model.call("socket:bee", "bravo"),
		"a picked floor_model that is gone falls back to the selection's"
	)
	var lobby_first: Array[BuildingModel] = [
		OfficeProjection.building(HerdrFleet.LOCAL, "Local", HerdrSnapshot.new(), states, true), bee
	]
	_eq(
		OfficeProjection.choose_floor(lobby_first, "", ""),
		floor_model.call("socket:bee", "alpha"),
		"no selection: the first real floor_model of the first building that has one"
	)
	var nothing: Array[BuildingModel] = [
		OfficeProjection.building(HerdrFleet.LOCAL, "Local", HerdrSnapshot.new(), states, true),
		OfficeProjection.building("socket:bee", "bee", HerdrSnapshot.new(), states, true)
	]
	_eq(OfficeProjection.choose_floor(nothing, "", ""), nothing[0].floors[0].key, "nothing anywhere: Local's lobby")
	_eq(
		OfficeProjection.floor_of(buildings, HerdrFleet.pane_key("socket:bee", "alpha:p1")),
		floor_model.call("socket:bee", "alpha"),
		"a desk's floor_model, by machine"
	)
	_eq(
		OfficeProjection.floor_of(buildings, HerdrFleet.pane_key("socket:bee", "api:p1")),
		"",
		"a pane id from another machine is not on this floor_model"
	)


## PageUp/PageDown walk every floor bottom to top, building after building;
## `N` takes blocked agents first, longest wait first, then UNREAD.
func test_office_floor_order_and_queue() -> void:
	var states := _states()
	var local := OfficeProjection.building(HerdrFleet.LOCAL, "Local", _view_fixture("snapshot_floors"), states, false)
	var bee := OfficeProjection.building("socket:bee", "bee", _view_fixture("snapshot_basic"), states, false)
	var far := OfficeProjection.building("machine:far", "far", HerdrSnapshot.new(), states, true)
	var buildings: Array[BuildingModel] = [local, bee, far]
	var numbers: Array = OfficeProjection.floor_order(buildings).map(
		func(key: String) -> String:
			var found := OfficeProjection.find_floor(buildings, key)
			return "%s/%s" % [found.building.label, "L" if found.floor_model.lobby else str(found.floor_model.number)]
	)
	_eq(
		numbers,
		["Local/1", "Local/2", "Local/3", "Local/4", "Local/5", "bee/1", "bee/2", "far/L"],
		"floor order across buildings"
	)
	_check(OfficeProjection.find_floor(buildings, "no such floor") == null, "a floor key nobody has is nobody's floor")
	var starts := {
		HerdrFleet.pane_key(HerdrFleet.LOCAL, "web:p1"): 200.0,
		HerdrFleet.pane_key(HerdrFleet.LOCAL, "infra:p1"): 100.0,
		HerdrFleet.pane_key(HerdrFleet.LOCAL, "web:p2"): 300.0,
	}
	# The office's frame builder stamps these (PaneModel.state_since).
	for building_model in buildings:
		for floor_model in building_model.floors:
			for room in floor_model.rooms:
				for pane in room.panes:
					pane.state_since = starts.get(pane.key, -1.0)
	var local_key := func(pane_id: String) -> String: return HerdrFleet.pane_key(HerdrFleet.LOCAL, pane_id)
	# An unknown start is ranked as the longest wait, first, as a
	# floor's queue stands (docs/VISUAL_LANGUAGE.md, "State start").
	_eq(
		OfficeProjection.attention_queue(buildings),
		[
			HerdrFleet.pane_key("socket:bee", "bravo:p1"),
			local_key.call("infra:p1"),
			local_key.call("web:p1"),
			local_key.call("infra:p2"),
			local_key.call("web:p2"),
		],
		"blocked by longest wait, unknown start first, then UNREAD the same way"
	)
	bee.stale = true
	_check(
		not HerdrFleet.pane_key("socket:bee", "bravo:p1") in OfficeProjection.attention_queue(buildings),
		"a stale machine's agents are not in the queue"
	)


## The minimap: buildings top to bottom, highest floor on top, the shown floor
## highlighted, a row press names the floor, counts as pulsing icons. The rows
## are scene nodes now, so the panel has to be in the tree and laid out.
func test_office_minimap() -> void:
	# 1280 wide: the column says the floors' names (below it, the rail; tools/test_floors.gd).
	var hud := await _hud(Vector2(1280, 480))
	var minimap: OfficeFloors = hud.floors
	var picked: Array = []
	hud.floor_picked.connect(func(key: String) -> void: picked.append(key))
	var tower: Array[FloorModel] = [
		_floor_row("a1", 1, 1, 0, 0), _floor_row("a2", 2, 0, 0, 0), _floor_row("a3", 3, 2, 1, 2)
	]
	var lobby := _floor_row("lobby", 0, 0, 0, 0)
	lobby.label = "LOBBY"
	lobby.lobby = true
	var empty: Array[FloorModel] = [lobby]
	var model: Array[BuildingRows] = [
		_building_rows("local", "Local", MachineLiveness.State.LIVE, tower),
		_building_rows("machine:far", "far", MachineLiveness.State.OFFLINE, empty)
	]
	minimap.show_buildings(model, "a2", true)
	await _frames(2)
	_eq(minimap.row_keys(), ["a3", "a2", "a1", "lobby"], "highest floor on top, buildings in order")
	_eq(
		minimap.headings().map(func(h: OfficeBuildingHeading) -> String: return _label_text(h, "%BuildingLabel")),
		["LOCAL", "FAR"],
		"a heading per building with more than Local"
	)
	_eq(_row_numbers(minimap), ["3F", "2F", "1F", "L"], "floor numbers, L for a lobby")
	var highlighted := minimap.row_keys().filter(
		func(key: String) -> bool:
			var row := minimap.row_for(key)
			return row.theme_type_variation == &"FloorRowCurrent"
	)
	_eq(highlighted, ["a2"], "the shown floor is the only highlighted row")
	_eq(_row_label(minimap, "a3").theme_type_variation, &"", "a floor with agents reads in ink")
	_eq(_row_label(minimap, "a1").theme_type_variation, &"", "so does a floor with one")
	_eq(_row_label(minimap, "lobby").theme_type_variation, &"LabelMuted", "a quiet floor steps back")
	var badges := _floor_icons(minimap)
	_eq(
		badges.map(func(b: StatusBadge) -> Array: return [b.machine, str(b.state), b.pane_id]),
		[["local", "blocked", ""], ["local", "done", ""]],
		"icons only for non-zero counts, with machine and state, no pane id"
	)
	_check(badges.all(func(b: StatusBadge) -> bool: return b.rest_offset == b.offset), "icons rest at the pack's pivot")
	_check(
		badges.all(func(b: StatusBadge) -> bool: return b.is_in_group(StatusBadge.GROUP)),
		"and they are the ones attention pulses"
	)
	# Every building says how its machine is answering with the pack's own icon,
	# not with a coloured square nobody has a legend for.
	var art: ArtPack = minimap.art
	_eq(
		minimap.headings().map(func(h: OfficeBuildingHeading) -> Texture2D: return h.mark_icon().texture),
		[ArtContract.UI_CONNECTED, ArtContract.UI_OFFLINE].map(
			func(id: StringName) -> Texture2D: return art.sprite_texture(art.ui_sprite(id))
		),
		"a live machine is connected, a dropped one is offline"
	)
	var connecting: Array[BuildingRows] = [
		_building_rows("local", "Local", MachineLiveness.State.LIVE, tower),
		_building_rows("machine:far", "far", MachineLiveness.State.CONNECTING, empty)
	]
	minimap.show_buildings(connecting, "a2", true)
	await _frames(1)
	_eq(
		minimap.headings()[1].mark_icon().texture,
		art.sprite_texture(art.ui_sprite(ArtContract.UI_STARTING)),
		"a machine still opening its forward is starting"
	)
	_check(
		minimap.headings().all(
			func(h: OfficeBuildingHeading) -> bool: return h.mark_icon().position == h.mark_icon().offset / -art.density
		),
		"each icon stands at its own pivot, so the picture lands in the same square"
	)
	minimap.show_buildings(model, "a2", true)
	await _frames(1)
	minimap.row_for("a1").pressed.emit()
	_eq(picked, ["a1"], "pressing a row names that floor")
	_check(
		minimap.headings()[0].mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"a heading takes no mouse, so it picks nothing"
	)
	var rows := minimap.row_keys().map(func(key: String) -> int: return minimap.row_for(key).get_instance_id())
	minimap.show_buildings(model, "a2", true)
	await _frames(1)
	_eq(
		minimap.row_keys().map(func(key: String) -> int: return minimap.row_for(key).get_instance_id()),
		rows,
		"the same model keeps every row node"
	)
	minimap.show_buildings(model, "a2", false)
	await _frames(1)
	_eq(minimap.row_keys(), ["a3", "a2", "a1", "lobby"], "without headings the rows stay")
	_eq(minimap.headings(), [], "but no building heading")
	# A building that goes away loses its heading, while the others keep theirs.
	minimap.show_buildings(model, "a2", true)
	await _frames(1)
	var kept := minimap.headings()[0]
	var alone: Array[BuildingRows] = [_building_rows("local", "Local", MachineLiveness.State.LIVE, tower)]
	minimap.show_buildings(alone, "a2", true)
	await _frames(1)
	_eq(
		minimap.headings().map(func(h: OfficeBuildingHeading) -> String: return _label_text(h, "%BuildingLabel")),
		["LOCAL"],
		"a machine that went away loses its heading"
	)
	_eq(minimap.headings()[0], kept, "and the one that stayed keeps its node")
	_eq(minimap.row_keys(), ["a3", "a2", "a1"], "with only its own floors left")
	minimap.show_buildings(model, "a2", false)
	await _frames(1)
	# A floor that goes away loses its row; the rest keep theirs.
	var short: Array[BuildingRows] = [
		_building_rows("local", "Local", MachineLiveness.State.LIVE, [tower[1], tower[2]] as Array[FloorModel])
	]
	minimap.show_buildings(short, "a2", false)
	await _frames(1)
	_eq(minimap.row_keys(), ["a3", "a2"], "a closed floor loses its row")
	_check(minimap.row_for("a1") == null, "and nothing keeps it alive")
	_eq(minimap.row_for("a2").get_instance_id(), rows[1], "the floors that stayed keep their row node")
	hud.free()


## A tall building in a short panel: the shown floor stays in view and the
## wheel scrolls the list in place.
func test_office_minimap_scroll() -> void:
	# 312 - 40 - 72 leaves a 200-tall panel: the staff panel's
	# compact line over the NEWS strip, and its gap (72 in all), stand under the column.
	var hud := await _hud(Vector2(800, 312))
	var minimap: OfficeFloors = hud.floors
	_eq(hud.placed(minimap).size.y, 200.0, "the minimap is the 200-tall panel")
	var high: Array[FloorModel] = []
	for number in range(1, 31):
		high.append(_floor_row("t%d" % number, number, 1, 0, 0))
	var tall: Array[BuildingRows] = [_building_rows("local", "Local", MachineLiveness.State.LIVE, high)]
	minimap.show_buildings(tall, "t1", false)
	await _frames(2)
	var list_height: float = minimap.list_height()
	# The panel's heading is all it keeps above the list now: the lift's
	# portal (108) and its footer (24) are gone, and the rows have that room.
	_eq(list_height, 168.0, "the short panel keeps only its heading and gives the rest to the rows")
	var bottom: Control = minimap.row_for("t1")
	var offset := minimap.scroll_offset()
	_check(
		bottom.position.y >= offset and bottom.position.y + bottom.size.y <= offset + list_height,
		"the shown floor at the bottom is scrolled into view"
	)
	var holder: Control = minimap.get_node("%Rows")
	minimap.scroll_by(-10000)
	await _frames(1)
	_eq(minimap.scroll_offset(), 0.0, "scrolling stops at the top")
	_check(minimap.get_node("%Rows") == holder, "scrolling is not a rebuild")
	minimap.scroll_by(10000)
	await _frames(1)
	_eq(minimap.scroll_offset(), 30.0 * OfficeFloors.ROW - list_height, "and at the bottom")
	minimap.scroll_by(-100)
	await _frames(1)
	minimap.show_buildings(tall, "t1", false)
	await _frames(2)
	_eq(
		minimap.scroll_offset(),
		30.0 * OfficeFloors.ROW - list_height - 100,
		"an unchanged model keeps the viewer's scroll"
	)
	hud.free()


func test_office_arrange() -> void:
	# Layout now consumes stable tab identity and measured geometry through a
	# public pure API. Viewport width is used only for the initial plan.
	var floor_model := OfficeProjection.project(_view_fixture("snapshot_office"), _states())[0]
	var policy := FloorLayoutPolicy.new()
	policy.width_cells = 15
	var initial := OfficeFloorLayout.plan(floor_model, null, policy)
	_check(initial.problems.is_empty(), "the fixture produces a valid floor plan")
	_check(initial.plan != null, "the public allocator returns its plan")
	if initial.plan == null:
		return
	_eq(initial.plan.desks.size(), floor_model.rooms.size(), "one placement per tab")
	for placed in initial.plan.desks:
		_check(initial.plan.floor_cells.encloses(placed.reserved_cells), "each tab is within the complete floor")
	var signature := initial.plan.geometry_signature()
	policy.width_cells = 40
	var widened := OfficeFloorLayout.plan(floor_model, initial.plan, policy)
	_check(widened.problems.is_empty(), "a wider viewport keeps a valid retained plan")
	_eq(widened.plan.geometry_signature(), signature, "viewport width does not rearrange existing desks")
	var empty := FloorModel.new()
	empty.key = "empty-workspace"
	var empty_result := OfficeFloorLayout.plan(empty, null, policy)
	_check(empty_result.plan != null, "an empty workspace still has a complete floor")
	_check(empty_result.plan.floor_cells.size.y > 0, "empty floor height is real, not zero")
	_eq(empty_result.plan.desks.size(), 0, "an empty workspace invents no tab")


## The world's origin and its room come from the HUD's panels. At 800x480 they
## land exactly on these values.
func test_hud_free_area() -> void:
	var hud := await _hud(Vector2(800, 480))
	_eq(
		hud.world_rect(),
		Rect2(96, 48, 660, 308),
		"right of the FLOORS rail, left of the drawer's tab, below the bar, above the staff panel's card"
	)
	_eq(hud.placed(hud.bar), Rect2(0, 0, 800, 32), "the bar spans the top")
	_eq(hud.placed(hud.floors), Rect2(16, 40, 72, 316), "the minimap is a 72-wide rail, 16 in from the left")
	_eq(
		hud.placed(hud.right_column),
		Rect2(764, 40, 20, 316),
		"the right column (the agent list's drawer) starts closed to its 20-wide tab, 16 in from the right"
	)
	# 480 high is tall enough for the compact panel's card (staff_tall_from): 80 high.
	_eq(hud.placed(hud.staff), Rect2(16, 372, 768, 80), "the staff panel's card slot spans the bottom, 16 in")
	_eq(hud.placed(hud.news), Rect2(16, 456, 768, 20), "the NEWS strip under it, along the bottom")
	hud.fit(Vector2(1600, 960))
	_eq(hud.placed(hud.floors).size.x, 120.0, "from 1280 wide the minimap names its floors")
	_eq(hud.world_rect(), Rect2(144, 48, 1412, 788), "a bigger window is more office, not a bigger HUD")
	await _frames(2)
	var lines: Control = hud.bar.get_node("%Lines")
	var at := lines.get_global_rect()
	# 132 units: the longest status, OFFLINE / RECONNECTING, is 131 (tools/test_top_bar.gd).
	_eq([at.position.x, at.size.x], [1452.0, 132.0], "the right-hand lines keep 132 units at the bar's right end")
	for counter in hud.bar.counters():
		_check(
			not lines.get_global_rect().intersects(counter.get_global_rect()),
			"the lines do not cover the %s counter" % counter.id
		)
	# The chime switch stands at the counters' row's right end, 4 units short
	# of the lines, and the counters stretch over the rest of the wider bar.
	var switch: Control = hud.bar.get_node("%Chime")
	var room := switch.get_global_rect()
	_check(not lines.get_global_rect().intersects(room), "the lines do not cover the chime switch")
	# The row stretches its counters to whole units, so its last child may end a unit short.
	var row: Control = hud.bar.get_node("%Counters")
	_eq(row.get_global_rect().end.x, at.position.x - 4.0, "the counters' row ends 4 units short of the lines")
	_check(absf(room.end.x - row.get_global_rect().end.x) <= 1.0, "and the switch ends with the row: %s" % room)
	_eq(
		hud.bar.counter(&"panes").get_global_rect().end.x + 3.0,
		room.position.x,
		"the wider bar gives the counters the room, up to the switch"
	)
	# Every panel swallows the mouse, so nothing over one reaches the office.
	for panel: Control in [hud.bar, hud.floors, hud.inspector, hud.agent_list]:
		_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "%s stops the mouse" % panel.name)
	hud.free()


## Sums up every request the client sent during the whole run, so it has to be
## the last `test_` function in this file: cases run in source order.
func test_only_read_only_requests() -> void:
	var stats := _ctl("stats")
	for method: String in stats.lifetime_methods:
		_check(method in READ_ONLY, "sent a non read-only request: " + method)
	_eq(stats.violations, [], "every request was a well-formed read-only envelope")
	_check(max_step_usec < MAX_STEP_MSEC * 1000, "_process never blocked (slowest %.1fms)" % (max_step_usec / 1000.0))
