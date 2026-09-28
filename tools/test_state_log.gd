extends "res://tools/office_test_base.gd"
## The state log (StateLog): the segments and events HerdrFleet records
## from its clients, and the rules it records them by, both on the log alone
## (clocks handed in) and through a live office's fleet; plus what the office
## lets go of while the overview covers it. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_state_log.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## What each pane of tools/fixtures/snapshot_floors.json reads as in the log:
## the shells (no agent) and data:p2 (still launching) as unknown.
const FIXTURE_STATES: Dictionary[String, String] = {
	"api:p1": "working",
	"api:p2": "idle",
	"api:p3": "unknown",
	"api:p4": "working",
	"web:p1": "blocked",
	"web:p2": "done",
	"web:p3": "unknown",
	"infra:p1": "blocked",
	"infra:p2": "done",
	"infra:p3": "idle",
	"notes:p1": "unknown",
	"data:p1": "working",
	"data:p2": "unknown",
}


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("state-log-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "STATE LOG TESTS"


# --- through the fleet --------------------------------------------------------


## The first snapshot is the baseline: every pane opens one segment whose start
## this office did not see (the clock has none yet), and none of it is news:
## the one event is the machine coming online.
func test_a_first_snapshot_opens_baseline_segments_without_events() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	_eq(ledger.tracks().size(), FIXTURE_STATES.size(), "a track for each of the fixture's panes")
	for pane_id: String in FIXTURE_STATES:
		var track := ledger.track(_pk(pane_id))
		_check(track != null, "%s has a track" % pane_id)
		if track == null:
			continue
		_eq(track.segments.size(), 1, "%s: one segment" % pane_id)
		var segment := track.segments[0]
		_eq(segment.state, FIXTURE_STATES[pane_id], "%s: its state word" % pane_id)
		_check(segment.observed, "%s: watched from now on" % pane_id)
		_check(not segment.observed_start, "%s: but its start was not seen" % pane_id)
		_eq(segment.end_msec, -1, "%s: and it is open" % pane_id)
		_eq(track.times, 1 if segment.state == "blocked" else 0, "%s: a blocked baseline counts once" % pane_id)
		_eq(track.blocked_plus, segment.state == "blocked", "%s: and reads `+`" % pane_id)
	_eq(_kinds(ledger), [StateLog.Kind.MACHINE_ONLINE], "the only event is Local coming online")
	_eq(ledger.events()[0].machine, LOCAL, "Local's")
	_check(ledger.opened_msec >= 0 and ledger.opened_unix > 0.0, "the ledger knows when it opened")
	_done(office)


## A status change is one STATE event and a new segment that starts when the
## client's clock says, the event's own moment; the segment it ended was a
## baseline, so its length reads `+`.
func test_a_status_event_closes_a_segment_and_writes_one_event() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var before := ledger.events().size()
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	var news := ledger.events().slice(before)
	_eq(news.size(), 1, "one event, not one per signal the client sent")
	var event: StateLog.Event = news[0]
	_eq(event.kind, StateLog.Kind.STATE, "a state change")
	_eq(event.pane_key, _pk("api:p1"), "of api:p1")
	_eq([event.agent, event.space, event.tab], ["claude", "api", "main"], "its agent, space and tab")
	_eq([event.previous_state, event.state], ["working", "blocked"], "from working to blocked")
	_check(event.for_plus, "the segment it ended began before the office watched")
	_check(event.for_msec >= 0, "and lasted what the office saw of it")
	var track := ledger.track(_pk("api:p1"))
	_eq(track.segments.size(), 2, "api:p1 has two segments")
	var blocked := track.segments[1]
	_check(blocked.observed_start, "the new one's start was seen")
	_eq(blocked.start_msec, event.msec, "it starts at the event")
	_eq(track.segments[0].end_msec, blocked.start_msec, "where the old one ends")
	_eq([track.times, track.blocked_plus], [1, false], "blocked once, from a start the office saw")
	_done(office)


## Two changes that land before the office draws either are still two events:
## the log is fed where the client's snapshots arrive, not where the office refreshes.
func test_a_flap_within_one_refresh_is_two_events() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var before := ledger.events().size()
	_local(office)._apply_snapshot(_with(fixture, "api:p1", {"agent_status": "blocked"}))
	_local(office)._apply_snapshot(_with(fixture, "api:p1", {"agent_status": "working"}))
	var news := ledger.events().slice(before)
	_eq(news.size(), 2, "blocked and back are two events")
	var states: Array = []
	for event: StateLog.Event in news:
		states.append([event.kind, event.previous_state, event.state])
	_eq(states, [[StateLog.Kind.STATE, "working", "blocked"], [StateLog.Kind.STATE, "blocked", "working"]], "in order")
	var track := ledger.track(_pk("api:p1"))
	_eq(track.segments.size(), 3, "three segments")
	_eq(track.times, 1, "blocked once")
	_done(office)


## A disconnect closes every open segment and opens one nobody watched; the
## reconnect is a new baseline. A snapshot refused whole (over MAX_PANES) is a
## disconnect to the log too, though its clocks are cleared before the client
## says so and a disconnect's after: the two logs read the same, with one
## MACHINE_OFFLINE each.
func test_offline_closes_every_segment_as_not_observed_and_refusal_does_the_same() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	_set_online(office, false)
	_eq(_kinds(ledger), [StateLog.Kind.MACHINE_ONLINE, StateLog.Kind.MACHINE_OFFLINE], "one OFFLINE")
	for track in ledger.tracks():
		var count := track.segments.size()
		_eq(count, 2, "%s: the baseline and the gap" % track.key)
		if count < 2:
			continue
		var gap := track.segments[count - 1]
		_check(not gap.observed, "%s: the gap is not observed" % track.key)
		_eq(gap.state, "", "%s: and has no state" % track.key)
		_eq(track.segments[count - 2].end_msec, gap.start_msec, "%s: it starts where the last one ended" % track.key)
	var dropped := _shape(ledger)
	_set_online(office, true)
	_eq(
		_kinds(ledger),
		[StateLog.Kind.MACHINE_ONLINE, StateLog.Kind.MACHINE_OFFLINE, StateLog.Kind.MACHINE_ONLINE],
		"back online is one ONLINE and no pane event"
	)
	for track in ledger.tracks():
		var back := track.segments[track.segments.size() - 1]
		_check(back.observed and not back.observed_start, "%s: a new baseline, its start unseen" % track.key)
	_eq(ledger.tracks().size(), FIXTURE_STATES.size(), "the same tracks, kept across the gap")
	var refused := await _live_office()
	_feed(refused, _over_cap())
	_check(office.fleet.state_log() != refused.fleet.state_log(), "each office has its own log")
	_eq(_shape(refused.fleet.state_log()), dropped, "a refusal reads as the disconnect did")
	_done(refused)
	_done(office)


## The log and the top bar read one clock: the segment's start is the start
## state_since() gives, its length what the card writes on its beat.
func test_the_log_and_the_top_bar_read_the_same_start() -> void:
	var office := await _live_office()
	var key := _pk("api:p1")
	_eq(office.navigator.active_key, key, "herdr's focus, api:p1, is on the card")
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	var ledger := office.fleet.state_log()
	var since := office.fleet.state_since(LOCAL, "api:p1")
	_check(since >= 0.0, "the client saw api:p1's block begin")
	var track := ledger.track(key)
	var open := track.segments[track.segments.size() - 1]
	_eq(open.start_unix, since, "the segment is labelled with that very start")
	var length := ledger.state_for(track, Time.get_ticks_msec())
	var clock := (Time.get_unix_time_from_system() - since) * 1000.0
	_check(absf(length - clock) < 50.0, "and has lasted what the clock says: %d ms, %.0f ms" % [length, clock])
	await _text_tick()
	var written := office.hud.inspector.duration_label().text
	var after := ledger.state_for(track, Time.get_ticks_msec())
	# The card writes on a quarter-second beat: the log's length a beat ago or now.
	var ago := after - int(OfficeAttention.TEXT_INTERVAL * 1000.0) - 100
	var words := [OfficeAttention.format_duration(after / 1000.0), OfficeAttention.format_duration(ago / 1000.0)]
	_check(written in words, "the card's `%s` is the log's %s" % [written, words])
	_done(office)


## Another terminal in the same pane is another agent run: REPLACED, and its
## blocked totals start from nothing.
func test_a_new_terminal_in_the_same_pane_starts_over() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	var track := ledger.track(_pk("api:p1"))
	_eq(track.times, 1, "blocked once")
	await _frames(2)
	var before := ledger.events().size()
	_feed(office, _with(fixture, "api:p1", {"terminal_id": "t-new"}))
	var news := ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.REPLACED], "one REPLACED")
	if news.size() == 1:
		var event: StateLog.Event = news[0]
		_eq([event.previous_state, event.state], ["blocked", "working"], "from the old run's state to the new one's")
		_check(event.for_msec >= 0 and not event.for_plus, "the old run's block, seen whole")
	_eq(ledger.track(_pk("api:p1")), track, "the same track")
	_eq(track.segments.size(), 3, "a new segment")
	_check(track.segments[2].observed_start, "whose start was seen")
	_eq([track.times, track.blocked_msec, track.blocked_plus], [0, 0, false], "the totals start over")
	_eq(ledger.blocked_for(track, Time.get_ticks_msec()), 0, "nothing blocked in this run")
	_done(office)


## A pane new to a live machine APPEARS, from a start the office saw; one gone
## from two snapshots in a row is GONE (from one, see the next case), though the
## second of those snapshots reads the same as the first and refreshes nothing.
func test_a_pane_that_appears_and_one_that_goes() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var more := _plus(fixture, "api:p2", "api:p9")
	var before := ledger.events().size()
	_feed(office, more)
	var news := ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.APPEARED], "api:p9 appeared")
	var track := ledger.track(_pk("api:p9"))
	_check(track != null, "with a track")
	if track != null:
		_eq(track.segments.size(), 1, "one segment")
		_check(track.segments[0].observed_start, "whose start was seen")
		_eq(track.segments[0].state, "idle", "idle, as api:p2 it copies")
	before = ledger.events().size()
	_feed(office, _without(more, "api:p2"))
	_eq(ledger.events().size(), before, "missing from one snapshot is not gone")
	# The same snapshot again changes nothing the office draws: the fleet hears
	# it (its clocks moved on) and tells the log, and the office is not refreshed.
	office.refreshes = 0
	_local(office)._apply_snapshot(_without(more, "api:p2"))
	_eq(office.refreshes, 0, "a snapshot that reads the same refreshes no office")
	news = ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.GONE], "missing from the next as well, it is GONE")
	var gone := ledger.track(_pk("api:p2"))
	_check(gone.gone and gone.gone_msec >= 0, "its track is gone")
	var last := gone.segments[gone.segments.size() - 1]
	_check(not last.observed, "and its last stretch is not observed")
	_eq(gone.segments[gone.segments.size() - 2].end_msec, last.start_msec, "from where it went")
	_check(ledger.tracks().has(gone), "a gone track is kept")
	_done(office)


## A pane that drops out of a single snapshot and comes back is the same pane
## in the same state: nothing happened.
func test_a_pane_missing_from_one_snapshot_keeps_its_segment() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var before := ledger.events().size()
	_feed(office, _without(fixture, "api:p2"))
	_feed(office, fixture)
	_eq(ledger.events().size(), before, "no GONE, no APPEARED")
	var track := ledger.track(_pk("api:p2"))
	_eq(track.segments.size(), 1, "api:p2 still has its one segment")
	_check(track.segments[0].end_msec < 0 and not track.gone, "open, and not gone")
	_done(office)


# --- the ledger alone ------------------------------------------------------------


## Pane ids repeat across machines; the log keys by machine and pane.
func test_pane_ids_repeat_across_machines() -> void:
	var ledger := StateLog.new()
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "working")], 1000, 1e9)
	ledger.observe("machine:bee", "bee", true, [_sighting("machine:bee", "w:p1", "blocked")], 1000, 1e9)
	_eq(ledger.tracks().size(), 2, "two tracks")
	var here := ledger.track(HerdrFleet.pane_key("local", "w:p1"))
	var there := ledger.track(HerdrFleet.pane_key("machine:bee", "w:p1"))
	_check(here != null and there != null and here != there, "one per machine")
	if here != null and there != null:
		_eq([here.machine, there.machine], ["local", "machine:bee"], "each its own machine")
		_eq([here.segments[0].state, there.segments[0].state], ["working", "blocked"], "and its own state")
		_eq([here.machine_label, there.machine_label], ["Local", "bee"], "and name")


## The event ring keeps the newest EVENTS_MAX; a track keeps SEGMENTS_MAX
## segments, folding the oldest, and its blocked total survives the fold.
func test_the_event_ring_and_segment_caps_drop_the_oldest() -> void:
	var ledger := StateLog.new()
	var now := 0
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "working")], now, 1e9)
	for index in 600:
		now += 10
		var state := "blocked" if index % 2 == 0 else "working"
		ledger.observe("local", "Local", true, [_sighting("local", "w:p1", state, 1e9)], now, 1e9)
	var events := ledger.events()
	_eq(events.size(), StateLog.EVENTS_MAX, "the ring holds 512")
	_eq(events[0].id, 89, "the oldest 89 (the ONLINE and 88 changes) dropped")
	_eq(events[events.size() - 1].id, 600, "the newest kept")
	_eq(ledger.last_id(), 600, "and it is the last id")
	var capped := StateLog.new()
	now = 0
	capped.observe("local", "Local", true, [_sighting("local", "w:p1", "working")], now, 1e9)
	for index in 300:
		now += 10
		var state := "blocked" if index % 2 == 0 else "working"
		capped.observe("local", "Local", true, [_sighting("local", "w:p1", state, 1e9)], now, 1e9)
	var track := capped.track(HerdrFleet.pane_key("local", "w:p1"))
	_eq(track.segments.size(), StateLog.SEGMENTS_MAX, "a track keeps 256 segments")
	_check(track.segments[0].elided and not track.segments[0].observed, "the oldest folded into one")
	_check(not track.segments[1].elided, "and only that one")
	# 301 segments of 10 ms, blocked every other one from the second: 150 closed blocks.
	_eq(capped.blocked_for(track, now), 150 * 10, "blocked for 1.5 s, the folded blocks included")
	_eq(track.times, 150, "150 times")
	var kept := 0
	for segment in track.segments:
		if segment.observed and segment.state == "blocked":
			kept += segment.end_msec - segment.start_msec
	_check(kept < capped.blocked_for(track, now), "more than the kept segments add up to")


## What the log holds is its own: a sighting changed afterwards changes no
## event or track; and nothing it holds is terminal text (a title or a path).
func test_labels_are_copies_and_never_terminal_text() -> void:
	var ledger := StateLog.new()
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "working")], 1000, 1e9)
	var sighting := _sighting("local", "w:p1", "blocked", 1e9)
	ledger.observe("local", "Local", true, [sighting], 2000, 1e9)
	sighting.agent = "changed"
	sighting.space = "changed"
	var event := ledger.events()[ledger.events().size() - 1]
	_eq([event.agent, event.space], ["claude", "space"], "the event keeps what it was told")
	var track := ledger.track(HerdrFleet.pane_key("local", "w:p1"))
	_eq([track.agent, track.space], ["claude", "space"], "and so does the track")
	# Every pane with a title and a path the ledger must never hold.
	var marked: Dictionary = fixture.duplicate(true)
	for pane: Dictionary in _list(marked, "panes"):
		pane.terminal_title_stripped = "TITLE-SECRET " + str(pane.pane_id)
		pane.terminal_title = "TITLE-SECRET " + str(pane.pane_id)
		pane.cwd = "/SECRET/" + str(pane.pane_id)
	var office := await _live_office(marked)
	_feed(office, _with(marked, "api:p1", {"agent_status": "blocked"}))
	_feed(office, _plus(marked, "api:p2", "api:p9"))
	_feed(office, _without(marked, "web:p1"))
	_feed(office, _without(marked, "web:p1"))
	var fleet_log := office.fleet.state_log()
	_check(fleet_log.events().size() >= 5, "there are pane events to read: %d" % fleet_log.events().size())
	var texts := PackedStringArray()
	for each in fleet_log.events():
		texts.append_array([each.machine, each.machine_label, each.pane_key, each.agent, each.space, each.tab])
		texts.append_array([each.state, each.previous_state])
	for each in fleet_log.tracks():
		texts.append_array([each.key, each.machine, each.machine_label, each.agent, each.space, each.tab])
		texts.append(each.identity)
		for segment in each.segments:
			texts.append(segment.state)
	for text in texts:
		_check(not "SECRET" in text, "no terminal title or path: %s" % text)
	_done(office)


## Lengths come from the monotonic clock handed in, which never runs backwards
## here; the wall clock only labels, once, and a wall clock set back an hour
## changes no length.
func test_durations_use_the_monotonic_clock_and_wall_labels_are_stamped_once() -> void:
	var ledger := StateLog.new()
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "working")], 1000, 1e9)
	var track := ledger.track(HerdrFleet.pane_key("local", "w:p1"))
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "working")], 61000, 1e9 - 3600.0)
	_eq(ledger.state_for(track, 61000), 60000, "a minute, whatever the wall clock did")
	_eq(track.segments[0].start_unix, 1e9, "the label stamped when it opened stays")
	_eq(ledger.since_opened(61000), 60000, "the ledger opened a minute ago")
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "blocked")], 500, 1e9 - 3600.0)
	var event := ledger.events()[ledger.events().size() - 1]
	_eq(event.msec, 61000, "a clock handed in backwards reads as the last one")
	_eq(event.for_msec, 60000, "so the working stretch lasted the minute")
	_eq(track.segments[0].end_msec, 61000, "and ended there")
	_eq(event.wall_unix, 1e9 - 3600.0, "the event is labelled with the wall clock it came with")


## HH:MM in the system's time zone: the one wall clock NEWS, EVENTS and the
## overview's axis write.
func test_wall_clock_is_local_hours_and_minutes() -> void:
	var zone := Time.get_time_zone_from_system()
	var bias: int = zone.get("bias", 0)
	for unix: float in [0.0, 45296.0, 1e9 + 59.9]:
		var minutes := posmod(int(unix) / 60 + bias, 24 * 60)
		var expected := "%02d:%02d" % [minutes / 60, minutes % 60]
		_eq(OfficeAttention.wall_clock(unix), expected, "%s at UTC%+d minutes" % [unix, bias])
		_eq(OfficeAttention.wall_clock(unix).length(), 5, "five characters")


# --- the overview's keyboard --------------------------------------------------


## While the overview is open it holds the keyboard: a held arrow does not pan
## the world under it. Shut, the arrow pans again.
func test_the_overview_flag_holds_the_keyboard_and_stops_the_pan() -> void:
	var office := await _live_office()
	_check(not office.hud.overview_open() and not office.hud.holds_keyboard(), "shut, it holds nothing")
	office.hud.overview.visible = true
	_check(office.hud.overview_open(), "open")
	_check(office.hud.holds_keyboard(), "it holds the keyboard")
	var pan := office.camera.pan
	await _hold_key(KEY_DOWN)
	_eq(office.camera.pan, pan, "a held arrow leaves the world where it was")
	office.hud.overview.visible = false
	_check(not office.hud.holds_keyboard(), "shut, it lets go")
	await _hold_key(KEY_DOWN)
	_check(office.camera.pan.y > pan.y, "and the arrow pans the world down again")
	_done(office)


# --- starting -------------------------------------------------------------------


## herdr began launching an agent in a shell: one LAUNCH event, named, and no
## new segment, since the state says nothing yet. The agent recognised, still
## launching, is another agent in the same terminal (REPLACED, AGENT); then it
## comes up, and its state is news like any other.
func test_a_launch_on_a_shell_is_an_event_without_a_new_segment() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var before := ledger.events().size()
	_feed(office, _with(fixture, "api:p3", {"launch_pending": true, "name": "claude-1"}))
	var news := ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.LAUNCH], "one LAUNCH")
	if news.size() == 1:
		var event: StateLog.Event = news[0]
		_eq([event.agent, event.agent_name, event.starting], ["", "claude-1", true], "a shell, named, starting")
		_eq([event.state, event.for_msec, event.changed], [StateLog.UNKNOWN, -1, StateLog.Changed.NONE], "")
	var track := ledger.track(_pk("api:p3"))
	_eq(track.segments.size(), 1, "still the one segment")
	before = ledger.events().size()
	_feed(office, _with(fixture, "api:p3", {"agent": "claude", "launch_pending": true, "name": "claude-1"}))
	news = ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.REPLACED], "the agent recognised: another run in the pane")
	if news.size() == 1:
		var event: StateLog.Event = news[0]
		_eq([event.changed, event.starting, event.agent], [StateLog.Changed.AGENT, true, "claude"], "a new agent")
	before = ledger.events().size()
	var ready := {"agent": "claude", "agent_status": "idle", "launch_pending": null, "interactive_ready": true}
	ready["name"] = "claude-1"
	_feed(office, _with(fixture, "api:p3", ready))
	news = ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.STATE], "it came up")
	if news.size() == 1:
		var event: StateLog.Event = news[0]
		_eq([event.previous_state, event.state, event.starting], [StateLog.UNKNOWN, "idle", false], "unknown to idle")
	_feed(office, _with(fixture, "api:p3", ready))
	_eq(ledger.events().size(), before + 1, "the same snapshot again is nothing new")
	_done(office)


## A REPLACED event says what the pane got: another terminal, another agent
## in the same terminal, or another session of the same agent.
func test_a_replaced_event_says_what_changed() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var session := {"source": "fixture", "agent": "claude", "kind": "session_id", "value": "s-2"}
	var steps: Array = [
		["api:p1", {"terminal_id": "t-new"}, StateLog.Changed.TERMINAL],
		["api:p2", {"agent": "pi"}, StateLog.Changed.AGENT],
		["infra:p3", {"agent_session": session}, StateLog.Changed.SESSION],
	]
	var fed := fixture
	for step: Array in steps:
		var pane_id: String = step[0]
		var changes: Dictionary = step[1]
		var before := ledger.events().size()
		fed = _with(fed, pane_id, changes)
		_feed(office, fed)
		var news := ledger.events().slice(before)
		_eq(_kinds_of(news), [StateLog.Kind.REPLACED], "%s: one REPLACED" % pane_id)
		if news.size() == 1:
			var event: StateLog.Event = news[0]
			_eq([event.pane_key, event.changed], [_pk(pane_id), step[2]], "%s: what it got" % pane_id)
	var before_state := ledger.events().size()
	_feed(office, _with(fed, "api:p4", {"agent_status": "done"}))
	var last: StateLog.Event = ledger.events()[before_state]
	_eq([last.kind, last.changed], [StateLog.Kind.STATE, StateLog.Changed.NONE], "a state change got nothing new")
	_done(office)


## Blocked comes first: a start that asks at once. herdr launches claude in
## the shell api:p3 and it blocks before the launch is over: that is a state
## change the log records, a blocked segment whose start it saw and one event
## that says `blocked` (the stretch it ended was no state of herdr's), so the
## top bar's `max`, the OVERVIEW's FOR and NEWS all have it. herdr finishing the
## launch while it still asks is no change: no segment, no event.
func test_a_blocked_start_opens_a_blocked_segment() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var launching := {"agent": "claude", "launch_pending": true, "name": "claude-1"}
	_feed(office, _with(fixture, "api:p3", launching))
	var asking := launching.duplicate()
	asking["agent_status"] = "blocked"
	var before := ledger.events().size()
	_feed(office, _with(fixture, "api:p3", asking))
	var news := ledger.events().slice(before)
	_eq(_kinds_of(news), [StateLog.Kind.STATE], "one state change")
	if news.size() == 1:
		var event: StateLog.Event = news[0]
		_eq([event.previous_state, event.state, event.starting], [StateLog.UNKNOWN, "blocked", true], "to blocked")
		_eq(NewsItem.what(event), "blocked", "NEWS says blocked")
	var track := ledger.track(_pk("api:p3"))
	var open := track.segments[track.segments.size() - 1]
	_eq(open.state, "blocked", "a blocked segment is open")
	_check(open.observed_start, "whose start the log saw")
	_eq([track.times, track.blocked_plus], [1, false], "blocked once, from a start the office saw")
	var waited := StateLog.wait_of(track, Time.get_ticks_msec())
	_check(waited.msec >= 0 and not waited.plus, "timed, with no `+`")
	var segments := track.segments.size()
	before = ledger.events().size()
	var ready := asking.duplicate()
	ready["launch_pending"] = null
	_feed(office, _with(fixture, "api:p3", ready))
	_eq(ledger.events().size(), before, "the launch ending while it still asks writes nothing")
	_eq(track.segments.size(), segments, "and opens no segment")
	_done(office)


## Another terminal in the pane (herdr's REPLACED) starts a new agent run on
## the same track: `run_start` names its first segment; the ones before it
## are the run before. A second replacement moves it again.
func test_a_replacement_starts_a_new_run() -> void:
	var ledger := StateLog.new()
	var blocked := _sighting("local", "w:p1", "blocked", 1.0)
	ledger.observe("local", "Local", true, [blocked], 1000, 1.0)
	var track := ledger.track(HerdrFleet.pane_key("local", "w:p1"))
	_eq(track.run_start, 0, "the first run starts with the track")
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "idle", 2.0)], 2000, 2.0)
	_eq(track.run_start, 0, "a state change is the same run")
	var next := _sighting("local", "w:p1", "idle", 3.0)
	next.identity = "term-next"
	ledger.observe("local", "Local", true, [next], 3000, 3.0)
	_eq(_kinds(ledger).back(), StateLog.Kind.REPLACED, "herdr's replacement")
	_eq(track.segments.size(), 3, "a new segment")
	_eq(track.run_start, 2, "which starts the new run")
	_eq(track.segments[track.run_start].start_msec, 3000, "at the replacement")
	var again := _sighting("local", "w:p1", "working", 4.0)
	again.identity = "term-third"
	ledger.observe("local", "Local", true, [again], 4000, 4.0)
	_eq(track.run_start, 3, "another replacement, another run")


## Past SEGMENTS_MAX the oldest segments fold into one; `run_start` moves with
## the segment it names, and once that segment itself is folded away it is the
## folded head (0): nothing of the run before is left to mistake for this one.
func test_folding_keeps_the_run_start_on_its_segment() -> void:
	var ledger := StateLog.new()
	var now := 0
	for index in 240:
		now = _step(ledger, now, "term-w:p1", "blocked" if index % 2 == 0 else "working")
	var track := ledger.track(HerdrFleet.pane_key("local", "w:p1"))
	now = _step(ledger, now, "term-next", "idle")
	var began := track.segments[track.segments.size() - 1].start_msec
	_eq(track.run_start, track.segments.size() - 1, "the replacement starts a run")
	for index in 40:
		now = _step(ledger, now, "term-next", "working" if index % 2 == 0 else "idle")
	_eq(track.segments.size(), StateLog.SEGMENTS_MAX, "the track folded")
	_eq(track.segments[track.run_start].start_msec, began, "run_start still names the segment the run began with")
	for index in 300:
		now = _step(ledger, now, "term-next", "working" if index % 2 == 0 else "idle")
	_eq(track.run_start, 0, "folded past it: the folded head")
	_check(track.segments[0].elided, "which nobody watched")


## Another agent run that came up while its machine was away is a new run too,
## though no event says so: the reconnect starts the totals over, and
## `run_start` names the segment after the gap.
func test_a_silent_restart_across_an_offline_gap_starts_a_run() -> void:
	var ledger := StateLog.new()
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "blocked", 1.0)], 1000, 1.0)
	ledger.observe("local", "Local", false, [], 2000, 2.0)
	var other := _sighting("local", "w:p1", "idle", 3.0)
	other.identity = "term-other"
	var before := ledger.events().size()
	ledger.observe("local", "Local", true, [other], 3000, 3.0)
	_eq(_kinds_of(ledger.events().slice(before)), [StateLog.Kind.MACHINE_ONLINE], "no event names the new run")
	var track := ledger.track(HerdrFleet.pane_key("local", "w:p1"))
	_eq(track.times, 0, "its totals start over")
	_eq(track.segments.size(), 3, "blocked, the gap, idle")
	_eq(track.run_start, 2, "the run starts after the gap")
	var same := StateLog.new()
	same.observe("local", "Local", true, [_sighting("local", "w:p1", "blocked", 1.0)], 1000, 1.0)
	same.observe("local", "Local", false, [], 2000, 2.0)
	same.observe("local", "Local", true, [_sighting("local", "w:p1", "idle", 3.0)], 3000, 3.0)
	_eq(same.track(HerdrFleet.pane_key("local", "w:p1")).run_start, 0, "the same run after the gap is not a new one")


## `version` moves on every change the log records, events or not (a label, a
## machine going, a pane forgotten) and never on an observation that changes
## nothing: what may keep a model built from the log (AgentHistory.Cache).
func test_every_change_moves_the_version_and_nothing_else_does() -> void:
	var ledger := StateLog.new()
	var last := ledger.version
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "blocked", 1.0)], 1000, 1.0)
	_check(ledger.version > last, "the first observation moves the version")
	last = ledger.version
	ledger.observe("local", "Local", true, [_sighting("local", "w:p1", "blocked", 1.0)], 1100, 1.1)
	_eq(ledger.version, last, "the same observation again leaves it")
	var renamed := _sighting("local", "w:p1", "blocked", 1.0)
	renamed.tab = "renamed"
	ledger.observe("local", "Local", true, [renamed], 1200, 1.2)
	_check(ledger.version > last, "a tab renamed (no event) moves it")
	last = ledger.version
	ledger.observe("local", "Local Mac", true, [renamed], 1300, 1.3)
	_check(ledger.version > last, "the machine renamed (no event) moves it")
	last = ledger.version
	var idle := _sighting("local", "w:p1", "idle", 1.4)
	idle.tab = "renamed"
	ledger.observe("local", "Local Mac", true, [idle], 1400, 1.4)
	_check(ledger.version > last, "a state change moves it")
	last = ledger.version
	ledger.observe("local", "Local Mac", false, [], 1500, 1.5)
	_check(ledger.version > last, "going offline moves it")
	last = ledger.version
	ledger.observe("local", "Local Mac", false, [], 1600, 1.6)
	_eq(ledger.version, last, "offline again leaves it")
	ledger.forget_machine("local", 1700, 1.7)
	_check(ledger.version > last, "forgetting the offline machine (no event) moves it")
	_check(ledger.track(HerdrFleet.pane_key("local", "w:p1")).gone, "which is gone now")


# --- helpers ------------------------------------------------------------------


## One observation of Local's w:p1 in `state` from terminal `identity`, 10 ms
## after `now`; the new now.
func _step(ledger: StateLog, now: int, identity: String, state: String) -> int:
	var at := now + 10
	var sighting := _sighting("local", "w:p1", state, at / 1000.0)
	sighting.identity = identity
	ledger.observe("local", "Local", true, [sighting], at, at / 1000.0)
	return at


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _kinds(ledger: StateLog) -> Array:
	return _kinds_of(ledger.events())


func _kinds_of(events: Array) -> Array:
	var result: Array = []
	for event: StateLog.Event in events:
		result.append(event.kind)
	return result


## What a log says, for comparing two: its events' kinds, and per track (in
## order) its key and whether each segment was observed.
func _shape(ledger: StateLog) -> Array:
	var tracks: Array = []
	for track in ledger.tracks():
		var observed: Array = []
		for segment in track.segments:
			observed.append(segment.observed)
		tracks.append([track.key, observed])
	return [_kinds(ledger), tracks]


## One agent pane `pane_id` of `machine` in `status`, its start `since` (-1: unknown).
func _sighting(machine: String, pane_id: String, status: String, since := -1.0) -> StateLog.Sighting:
	var sighting := StateLog.Sighting.new()
	sighting.pane_key = HerdrFleet.pane_key(machine, pane_id)
	sighting.identity = "term-" + pane_id
	sighting.status = status
	sighting.since_unix = since
	sighting.agent = "claude"
	sighting.space = "space"
	sighting.tab = "tab"
	return sighting


## `snapshot` with one more pane, `pane_id`, a copy of `like` in its own terminal.
func _plus(snapshot: Dictionary, like: String, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		var copies: Array = []
		for each: Dictionary in _list(result, field):
			if each.get("pane_id", "") == like:
				var copy: Dictionary = each.duplicate(true)
				copy.pane_id = pane_id
				copy.terminal_id = "term-" + pane_id
				copies.append(copy)
		_list(result, field).append_array(copies)
	return result


## `snapshot` without pane `pane_id`, in its panes, agents and layouts.
func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result


## A snapshot over the pane cap, refused whole: its panes a list of empty records.
func _over_cap() -> Dictionary:
	var huge: Dictionary = fixture.duplicate(true)
	var panes: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		panes.append({})
	huge.panes = panes
	return huge


## Hold a key for a few frames, the way the camera polls arrows.
func _hold_key(keycode: Key) -> void:
	var event := _key(keycode)
	event.physical_keycode = keycode
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(6)
	event.pressed = false
	await _parsed(event)
