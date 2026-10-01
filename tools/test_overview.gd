extends "res://tools/command_test_base.gd"
## The OVERVIEW: the table of every pane with its state, FOR, BLOCKED,
## TIMES and its timeline since this office opened, over the world. Its model
## and timeline on their own, then the table in a live office as an operator,
## against two fake herdrs of this suite's own (Local on A, bee on B, whose pane
## ids collide). Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_overview.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Every interaction is real input: clicks, keys. The overview writes nothing:
## every case but one opens only `pane.read` (the card's preview) and checks
## that no gesture wrote; the one that answers through the staff panel under
## the overview sends one key on purpose. The last case sums up both fakes.

## Local's panes by pane key (HerdrFleet.pane_key()): its claude at work, its
## codex idle, and its pi blocked on another floor, in snapshot_basic.
var local_p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1")
var local_p3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3")
var local_blocked := HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo:p1")


func _marker() -> String:
	return "OVERVIEW TESTS"


# --- the model and the timeline on their own ------------------------------------------


## STATE sorts by attention: blocked, done, working, idle, unknown, a shell,
## offline; the longest in its state first, then by pane key. A chip keeps only
## the live panes in its state; ALL keeps the offline one and the shell too.
## FOR is the open state's observed time, `+` when its start was not observed.
func test_the_model_sorts_by_attention_and_filters_live_states() -> void:
	var ledger := StateLog.new()
	var local: Array[StateLog.Sighting] = [
		_sighting("local", "w:idle", "idle", "codex"),
		_sighting("local", "w:blocked", "blocked", "claude"),
		_sighting("local", "w:shell", "", ""),
		_sighting("local", "w:done", "done", "pi"),
		_sighting("local", "w:working", "working", "claude"),
	]
	ledger.observe("local", "Local", true, local, 1000, 1e9)
	ledger.observe("bee", "bee", true, [_sighting("bee", "w:gone", "blocked", "claude")], 1000, 1e9)
	# One more blocked pane, seen blocking later: shorter in its state.
	local.append(_sighting("local", "w:late", "blocked", "claude", 1e9 + 5.0))
	ledger.observe("local", "Local", true, local, 6000, 1e9 + 5.0)
	ledger.observe("bee", "bee", false, [], 7000, 1e9 + 6.0)
	var frame := _frame({"local": false, "bee": true}, ledger)
	var model := OverviewModel.of(
		frame, ledger, _pane("local", "w:done"), OverviewModel.Sort.STATE, false, OverviewModel.Filter.ALL, 11000
	)
	_eq(
		model.keys(),
		PackedStringArray(
			[
				_pane("local", "w:blocked"),
				_pane("local", "w:late"),
				_pane("local", "w:done"),
				_pane("local", "w:working"),
				_pane("local", "w:idle"),
				_pane("local", "w:shell"),
				_pane("bee", "w:gone"),
			]
		),
		"attention order, the longest blocked first, offline last"
	)
	var first := model.rows[0]
	_eq([first.for_msec, first.for_plus, first.times, first.blocked_plus], [10000, true, 1, true], "a baseline block")
	var late := model.rows[1]
	_eq([late.for_msec, late.for_plus, late.blocked_msec], [5000, false, 5000], "a block seen starting")
	var gone := model.rows[6]
	_eq([gone.offline, gone.state, gone.for_msec, gone.names_machine], [true, "blocked", 0, true], "offline")
	_eq(gone.place(), "space / tab @ bee", "another machine's pane names it")
	_check(model.rows[2].selected and not model.rows[0].selected, "the staff panel's pane is the selected row")
	_eq(model.panes, 6, "the live machine's panes only")
	var blocked := OverviewModel.of(
		frame, ledger, "", OverviewModel.Sort.STATE, false, OverviewModel.Filter.BLOCKED, 11000
	)
	_eq(
		blocked.keys(),
		PackedStringArray([_pane("local", "w:blocked"), _pane("local", "w:late")]),
		"BLOCKED: live blocked panes only"
	)
	_check(
		blocked.tracked.has(_pane("bee", "w:gone")), "the offline pane is still tracked: its row hides, it is not gone"
	)
	var by_for := OverviewModel.of(frame, ledger, "", OverviewModel.Sort.FOR, true, OverviewModel.Filter.ALL, 11000)
	_eq(
		by_for.keys()[by_for.rows.size() - 2],
		_pane("local", "w:late"),
		"FOR descending: the late one after the baseline"
	)
	_eq(by_for.keys()[by_for.rows.size() - 1], _pane("bee", "w:gone"), "and offline, 0, last")
	var by_agent := OverviewModel.of(
		frame, ledger, "", OverviewModel.Sort.AGENT, false, OverviewModel.Filter.ALL, 11000
	)
	_eq(by_agent.keys()[0], _pane("local", "w:shell"), "AGENT ascending: the shell's empty name first")


## A pane there from the start opens in its state at the timeline's left edge,
## even though the log opened a moment before (a machine still connecting);
## one that appeared later opens on a hatch; one whose machine dropped keeps
## what was observed and ends on a hatch. Every edge is a whole unit.
func test_the_timeline_spans_start_observed_and_hatch_what_nobody_watched() -> void:
	var ledger := StateLog.new()
	ledger.observe("local", "Local", false, [], 500, 1e9)
	var seen: Array[StateLog.Sighting] = [_sighting("local", "w:a", "working", "claude")]
	ledger.observe("local", "Local", true, seen, 1000, 1e9 + 0.5)
	seen.append(_sighting("local", "w:b", "idle", "codex", 1e9 + 5.5))
	ledger.observe("local", "Local", true, seen, 6000, 1e9 + 5.5)
	ledger.observe("local", "Local", false, [], 8000, 1e9 + 7.5)
	var model := OverviewModel.of(
		_frame({"local": false}, ledger), ledger, "", OverviewModel.Sort.AGENT, false, OverviewModel.Filter.ALL, 11000
	)
	_eq(model.opened_msec, 1000, "the left edge is the first pane seen, not the log's first observation")
	var a := OverviewTimeline.spans(ledger.track(_pane("local", "w:a")), model.opened_msec, model.now_msec, 104.0, 2)
	_eq(a.size(), 2, "observed, then the machine away: %s" % [a])
	_eq(Array(a[0]), [2.0, 2.0, 72.0], "working from the left edge (inset 2) to the drop at 7/10")
	_eq(Array(a[1]), [-1.0, 72.0, 102.0], "then a hatch to now")
	var b := OverviewTimeline.spans(ledger.track(_pane("local", "w:b")), model.opened_msec, model.now_msec, 104.0, 2)
	_eq(Array(b[0]), [-1.0, 2.0, 52.0], "the later pane opens on a hatch until it appeared at 5/10")
	_eq(Array(b[1]), [3.0, 52.0, 72.0], "then idle")
	_eq(OverviewAxis.step_minutes(25 * 60000), 5, "a short span ticks every 5 minutes")
	_eq(OverviewAxis.step_minutes(3 * 3600000), 30, "three hours, every 30")
	_eq(OverviewAxis.step_minutes(9 * 3600000), 60, "longer, hourly")


# --- opening and closing ---------------------------------------------------------------


## A click on PANES opens the overview over the world and both side columns:
## PANES reads pressed, the world and the signposts are hidden, the minimap and
## the drawer stay where they are, and nothing is laid out again (no floor
## planned, no room changed). It stands from under the bar to the columns'
## bottom edge. Its `X  Esc`, clicked, closes it and brings the world back.
func test_the_panes_counter_opens_the_overview_and_x_closes_it() -> void:
	var office := await _blocked_bee()
	var hud := office.hud
	var attempts := office.layout_attempt_count()
	var room := hud.world_rect()
	var moves: Array[int] = [0]
	hud.room_changed.connect(func() -> void: moves[0] += 1)
	var panes := hud.bar.counter(&"panes")
	_eq(panes.theme_type_variation, &"Counter", "PANES starts unpressed")
	await _click_control(panes)
	_check(hud.overview_open(), "PANES opens the overview")
	_eq(panes.theme_type_variation, &"CounterOn", "and reads pressed")
	_check(not office.world.visible, "the world is out of sight")
	_check(not hud.edge_arrows.visible, "so are the edge arrows")
	_check(hud.spaces.visible and hud.right_column.visible, "the minimap and the drawer stay, covered")
	_eq(hud.world_rect(), room, "the world's room is what it was")
	_eq(office.layout_attempt_count(), attempts, "no floor is planned for it")
	_eq(moves[0], 0, "and no room changed")
	var placed := hud.placed(hud.overview)
	_eq([placed.position.x, placed.position.y, placed.end.x], [16.0, 40.0, 784.0], "under the bar, 16 in")
	_eq(placed.end.y, hud.placed(hud.spaces).end.y, "down to the columns' bottom edge")
	_check(hud.overview.get_global_rect().encloses(Rect2(room.position, room.size)), "covering the world")
	await _frames(2)
	_check(_part(hud.overview, "%Summary").visible, "800 wide: the summary shows")
	_heading_apart(hud.overview, "800x480")
	await _click_control(_part(hud.overview, "%Close"))
	_check(not hud.overview_open(), "X closes it")
	_eq(panes.theme_type_variation, &"Counter", "PANES is released")
	_check(office.world.visible, "the world is back")
	_eq(office.layout_attempt_count(), attempts, "still nothing planned")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## `O` opens and closes it, again and again; Escape closes it. Nothing is
## written, the pick and the drawer stay as they were.
func test_o_toggles_and_esc_closes_only_the_overview() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var hud := office.hud
	var picked := office.picked_key
	var drawer := hud.drawer_open()
	await _tap(KEY_O)
	_check(hud.overview_open(), "O opens it")
	await _tap(KEY_O)
	_check(not hud.overview_open(), "O again closes it")
	await _tap(KEY_O)
	_check(hud.overview_open(), "and opens it once more")
	await _tap(KEY_ESCAPE)
	_check(not hud.overview_open(), "Escape closes it")
	await _tap(KEY_ESCAPE)
	_check(not hud.overview_open(), "and a second Escape opens nothing")
	_eq([office.picked_key, hud.drawer_open()], [picked, drawer], "nothing else changed")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## Answer mode stays usable under the overview, and Escape peels one layer at
## a time: the first leaves answer mode (sending nothing), the second folds the
## opened staff panel to its line, the third closes the overview. Escape
## never reaches pane.send_keys.
func test_esc_leaves_answer_mode_first_and_never_sends() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	await _tap(KEY_O)
	_check(office.hud.overview_open(), "O opens the overview over answer mode")
	_check(card.answering(), "and the card is still answering")
	await _tap(KEY_ESCAPE)
	_check(not card.answering(), "the first Escape leaves answer mode")
	_check(office.hud.overview_open(), "and leaves the overview open")
	_check(not office.hud.card_compact(), "and the panel open")
	await _tap(KEY_ESCAPE)
	_check(office.hud.card_compact(), "the second folds the panel to its line")
	_check(office.hud.overview_open(), "and leaves the overview open")
	await _tap(KEY_ESCAPE)
	_check(not office.hud.overview_open(), "the third closes the overview")
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "neither Escape sent anything")
	_eq(_all_inputs(), 0, "not a key")


## A click on a row picks that pane, as its desk would: the staff panel shows it
## and the row reads selected. The staff panel answers under the overview: the
## one intended write of this suite, a `1`.
func test_a_row_click_picks_the_pane_and_the_staff_panel_can_answer() -> void:
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with()
	await _tap(KEY_O)
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var line := office.hud.overview.line_for(key)
	_check(line != null and line.is_visible_in_tree(), "bee's blocked pane has a row")
	_check(office.picked_key != key, "not picked yet")
	await _click_control(line)
	_eq(office.picked_key, key, "the click picks it")
	_eq(line.theme_type_variation, &"OverviewRowCurrent", "its row reads selected")
	_check(office.hud.overview_open(), "the overview stays open")
	_eq(
		[office.navigator.shown_key, office.navigator.current_zone(office.frame)],
		[BEE, HerdrFleet.pane_key(BEE, "alpha")],
		"its machine's map is the one shown now, its zone current"
	)
	_check(not office.world.visible, "and the world built for it stays out of sight")
	var card := _card(office)
	# The panel is one line until opened: Enter opens it, under the overview too.
	await _open_panel(office)
	await _until(func() -> bool: return card.preview_text() == QUESTION and card.answer_offered(), "the question")
	await _open_answer(office)
	await _tap(KEY_1)
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the key went")
	_eq(_writes_seen("control-b").slice(-1), PackedStringArray(['pane.send_keys ["1"]']), "one 1, to bee")
	_eq(_inputs("control-b").size(), 1, "and only that")
	_eq(_inputs("control-a").size(), 0, "Local is sent nothing")


# --- the table ----------------------------------------------------------------------------


## Rows are pooled by pane key: a state change and a sort move the rows that
## are there, and make none. FOR's head sorts longest first, pressed again
## shortest first.
func test_rows_are_pooled_and_sorted_by_move_child() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var overview := office.hud.overview
	# Two panes change state a second apart, so FOR tells them apart.
	_ctl("control-a", "status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	await _wait(1.1)
	_ctl("control-a", "status", {"pane_id": "alpha:p3", "agent_status": "working"})
	await _until(func() -> bool: return _held_state(office, local_p3) == "working", "alpha:p3 works")
	await _tap(KEY_O)
	await _frames(2)
	var nodes := _hud_nodes(office)
	var p1 := overview.line_for(local_p1)
	await _click_control(_part(overview, "%HeadFor"))
	var shown := overview.shown_keys()
	_eq(shown.slice(-2), PackedStringArray([local_p1, local_p3]), "FOR descending: the two changed last, newest last")
	_eq(overview.sort(), OverviewModel.Sort.FOR, "sorted by FOR")
	_check(overview.descending(), "longest first")
	await _click_control(_part(overview, "%HeadFor"))
	shown = overview.shown_keys()
	_eq(shown.slice(0, 2), PackedStringArray([local_p3, local_p1]), "pressed again: shortest first")
	_eq(_hud_nodes(office), nodes, "sorting makes no node")
	_check(overview.line_for(local_p1) == p1, "the same row, moved")
	_ctl("control-a", "status", {"pane_id": "bravo:p1", "agent_status": "idle"})
	await _until(func() -> bool: return _state_text(office, local_blocked) == "IDLE", "the row says IDLE")
	# bravo:p1 stopped waiting: the agent list's History (the StateLog) has its
	# first line. The drawer is closed (every run starts so), and a list out of
	# sight renders nothing: not even that group's header is made yet.
	_eq(_hud_nodes(office), nodes, "nor does a state change")
	var history := office.hud.agent_list.group_for(AgentListModel.FLAT_HISTORY)
	_check(history != null, "the list's History has its first line once the list is read")
	_eq(overview.shown_keys()[0], local_blocked, "which moves its row: the shortest in its state now")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## FOR and BLOCKED say `+` (at least) for a state whose start this office did
## not see: the baseline. Seen changing, FOR loses its `+`; BLOCKED keeps it
## (its first block began before the office watched) and TIMES counts both
## blocks. FOR moves with the clock once a second, without a refresh.
func test_columns_say_for_blocked_times_with_plus_for_unobserved_starts() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	await _tap(KEY_O)
	await _until(func() -> bool: return _text(office, local_blocked, "%Times") == "1", "the blocked row")
	_check(
		_text(office, local_blocked, "%For").ends_with("s+"), "FOR at least: " + _text(office, local_blocked, "%For")
	)
	_check(_text(office, local_blocked, "%Blocked").ends_with("+"), "BLOCKED at least")
	_eq(_state_text(office, local_blocked), "BLOCKED", "STATE in herdr's word")
	_ctl("control-a", "status", {"pane_id": "bravo:p1", "agent_status": "working"})
	await _until(func() -> bool: return _state_text(office, local_blocked) == "WORKING", "working")
	_ctl("control-a", "status", {"pane_id": "bravo:p1", "agent_status": "blocked"})
	await _until(func() -> bool: return _text(office, local_blocked, "%Times") == "2", "blocked again")
	_check(not _text(office, local_blocked, "%For").ends_with("+"), "seen starting: FOR has no +")
	_check(_text(office, local_blocked, "%Blocked").ends_with("+"), "BLOCKED keeps its + for the first block")
	var before := _seconds(_text(office, local_blocked, "%For"))
	var refreshes := office.refreshes
	await _wait(2.1)
	var after := _text(office, local_blocked, "%For")
	_check(_seconds(after) > before, "FOR moved on: %ds, then %s" % [before, after])
	_eq(office.refreshes, refreshes, "on the overview's own tick, not a refresh")


## A chip keeps only the live panes in its state; a pane whose machine is away
## shows only under ALL, muted, `offline`, with no FOR (invariant 4).
func test_chips_filter_by_live_state_and_offline_rows_only_under_all() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var overview := office.hud.overview
	await _tap(KEY_O)
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "bee drops")
	var bee := HerdrFleet.pane_key(BEE, "alpha:p1")
	await _until(func() -> bool: return _state_text(office, bee) == "offline", "bee's row says offline")
	_eq(overview.line_for(bee).theme_type_variation, &"OverviewRowDim", "muted")
	_eq(_text(office, bee, "%For"), "-", "no FOR")
	_check(overview.shown_keys().has(bee), "shown under ALL")
	await _click_control(_part(overview, "%ChipBlocked"))
	_eq(overview.filter(), OverviewModel.Filter.BLOCKED, "BLOCKED keeps the blocked")
	_eq(overview.shown_keys(), PackedStringArray([local_blocked]), "Local's one blocked pane, bee's none")
	_check(not overview.line_for(bee).visible, "bee's rows are hidden, not gone")
	await _click_control(_part(overview, "%ChipAll"))
	_check(overview.shown_keys().has(bee), "ALL brings them back")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## In the office: a pane there when it opened is its state from the left edge
## (no hatch first); one that appears later opens on a hatch; one whose machine
## drops keeps what was seen and ends on a hatch. Idle is a colour of its own,
## apart from working and from the panel's paper and cream.
func test_the_timeline_draws_baseline_states_and_hatches_the_unobserved() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var overview := office.hud.overview
	await _tap(KEY_O)
	await _wait(1.2)
	var inset := float(overview.get_theme_constant(&"inset", &"Timeline"))
	var first := _spans(office, local_p1)
	_check(not first.is_empty() and first[0][0] >= 0.0, "a baseline pane starts in its state: %s" % [first])
	_eq(first[0][1], inset, "at the left edge")
	_ctl("control-a", "set_snapshot", {"snapshot": _plus(_raw(), "alpha:p3", "alpha:p9")})
	# A status event makes the client read the new snapshot at once.
	_ctl("control-a", "status", {"pane_id": "alpha:p1", "agent_status": "working"})
	var added := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p9")
	await _until(func() -> bool: return overview.line_for(added) != null, "the new pane has a row")
	await _wait(1.2)
	var late := _spans(office, added)
	_check(late.size() >= 2 and late[0][0] == -1.0 and late[1][0] >= 0.0, "it opens on a hatch: %s" % [late])
	var bee := HerdrFleet.pane_key(BEE, "alpha:p1")
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "bee drops")
	await _wait(1.2)
	var dropped := _spans(office, bee)
	_check(dropped.size() >= 2, "seen, then away: %s" % [dropped])
	# bee answered a moment after Local, which set the left edge: whatever
	# sliver of hatch comes first, what was seen of it stays, working.
	var kinds: Array[float] = []
	for span in dropped:
		kinds.append(span[0])
	_check(2.0 in kinds, "what was seen stays: working, in %s" % [dropped])
	_eq(kinds[kinds.size() - 1], -1.0, "and it ends on a hatch")
	var idle := overview.get_theme_color(&"idle", &"Timeline")
	_check(idle != overview.get_theme_color(&"working", &"Timeline"), "idle is not working's colour")
	var art := office.art
	_check(idle != art.color(ArtContract.PAPER) and idle != art.color(ArtContract.CREAM), "nor the panel's")


## While the overview covers the world the chips' reader reads nothing and
## no tooltip shows; a click where a chip was picks no desk (it lands on the
## overview). Closed again, the chip is read on schedule.
func test_bubbles_read_nothing_and_no_tip_while_the_overview_covers_the_world() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p1", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p1", "source": "detection", "text": QUESTION})
	var office := await _office_with(false, true, true, Vector2(SCREEN), true)
	var key := HerdrFleet.pane_key(BEE, "alpha:p1")
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	var at := await _bubble_point(office, key)
	await _until_stats(
		"control-b", func(_stats: Dictionary) -> bool: return _read_panes("control-b").size() >= 1, "read"
	)
	_eq(_read_panes("control-b"), ["alpha:p1"], "the bubble is read once")
	var picked := office.picked_key
	await _tap(KEY_O)
	_check(office.hud.overview_open(), "the overview covers the world")
	_check(not office.questions.reading(), "the reader stops")
	await _wait(OfficeScene.QUESTION_WATCH_SECONDS * 3 + 10.5)
	_eq(_read_panes("control-b"), ["alpha:p1"], "under the overview, past the ten seconds: nothing read")
	_check(not office.questions.reading(), "and nothing out")
	await _move_pointer(at)
	_check(not office.hud.world_tip_shown(), "no tooltip where the bubble is")
	# No row under the pointer: DONE keeps nobody, so the click lands on the
	# overview's own panel, where the chip would be.
	await _click_control(_part(office.hud.overview, "%ChipDone"))
	_eq(office.hud.overview.shown_keys(), PackedStringArray(), "no row shown")
	_check(office.hud.overview.get_global_rect().has_point(at), "the bubble's place is under the overview")
	await _click(at)
	await _frames(3)
	_eq(office.picked_key, picked, "the click picked no desk")
	await _tap(KEY_O)
	await _until_stats(
		"control-b", func(_stats: Dictionary) -> bool: return _read_panes("control-b").size() >= 2, "read again"
	)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "no write")


## The arrows are the table's while the overview is open: the world does not
## pan. So are `A` and PageUp: no list takes the keyboard, no floor changes.
func test_arrows_scroll_the_table_not_the_world() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with(false, true, true, Vector2(480, 320))
	await _tap(KEY_O)
	office.camera.pan = Vector2.ZERO
	await _frames(2)
	var pan := office.camera.pan
	_check(office.hud.holds_keyboard(), "the overview holds the keyboard")
	await _hold(KEY_DOWN, 5)
	_eq(office.camera.pan, pan, "the world does not pan under it")
	var shown := [office.navigator.shown_key, office.navigator.current_zone(office.frame)]
	await _tap(KEY_A)
	# PageDown: the key that would pan on from the rail's first zone, were it the office's.
	await _tap(KEY_PAGEDOWN)
	_check(not office.hud.agent_list.has_keyboard(), "A: the list does not take the keyboard")
	_eq([office.navigator.shown_key, office.navigator.current_zone(office.frame)], shown, "PageDown: no other zone")
	_check(office.hud.overview_open(), "the overview is still open")
	await _tap(KEY_O)
	_check(not office.hud.holds_keyboard(), "closed, it lets go")
	await _hold(KEY_DOWN, 5)
	_check(office.camera.pan != pan, "and the arrows pan the world again: %s" % office.camera.pan)


## The smallest screen takes the compact column set: BLOCKED and TIMES go,
## heads and rows alike, the table fits the overview's width with no sideways
## scroll, and the overview stands above the compact staff panel.
func test_the_smallest_screen_uses_the_compact_columns() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with(false, true, true, Vector2(480, 320))
	var overview := office.hud.overview
	await _tap(KEY_O)
	await _frames(3)
	for unique: String in ["%HeadBlocked", "%HeadTimes"]:
		_check(not (overview.get_node(unique) as Control).visible, unique + " is left out")
	for key in overview.shown_keys():
		var line := overview.line_for(key)
		_check(not (line.get_node("%Blocked") as Control).visible, key + ": no BLOCKED")
		_check(not (line.get_node("%Times") as Control).visible, key + ": no TIMES")
	var columns: Control = overview.get_node("%Columns")
	_check(columns.size.x <= 448.0, "the columns fit: %s" % columns.size.x)
	var scroll: ScrollContainer = overview.get_node("%Scroll")
	_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "no sideways scroll")
	_eq(office.hud.placed(overview), Rect2(16, 40, 448, 208), "above the compact staff panel")
	_check(overview.get_global_rect().end.x <= 464.0, "inside the screen's gutter")
	# The heading: no room for the summary beside the chips, so it goes (its
	# words are the title's tooltip) and nothing passes under anything.
	_check(not _part(overview, "%Summary").visible, "no summary on the compact heading")
	_check(_part(overview, "%Title").tooltip_text.contains("panes"), "its words are the title's tooltip")
	_heading_apart(overview, "480x320")
	# A label too long for its column ends in an ellipsis, never a glyph cut.
	for key in overview.shown_keys():
		for unique: String in ["%AgentName", "%Space", "%State", "%For"]:
			var label: Label = overview.line_for(key).get_node(unique)
			_eq(label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "%s %s: an ellipsis" % [key, unique])
			_check(not label.clip_text, "%s %s: not clipped" % [key, unique])


## Few rows (eight at 800x480, room for ten): no scroll bar, and the room it
## would take is kept all the same, so the axis still ends where the timelines do.
func test_rows_that_fit_show_no_scroll_bar() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var overview := office.hud.overview
	await _tap(KEY_O)
	await _frames(3)
	_eq(overview.shown_keys().size(), 8, "two machines' four panes each")
	var scroll: ScrollContainer = overview.get_node("%Scroll")
	_check(not scroll.get_v_scroll_bar().visible, "every row fits: no bar")
	_bar_room(overview, "8 rows")


## More rows than the table holds at 800x480 with the staff panel opened
## (fourteen, room for ten): the theme's thin scroll bar shows beside the
## timelines, a gap clear of their `now` rule, never focused; the axis still
## ends where the timelines do.
func test_rows_past_the_bottom_show_a_scroll_bar() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var raw := _raw()
	for index in 6:
		raw = _plus(raw, "alpha:p3", "alpha:q%d" % index)
	_ctl("control-a", "set_snapshot", {"snapshot": raw})
	var office := await _office_with()
	var overview := office.hud.overview
	# Opened (Enter on the pane herdr focuses), the panel leaves the table ten rows.
	await _open_panel(office)
	await _tap(KEY_O)
	await _until(func() -> bool: return overview.shown_keys().size() == 14, "fourteen rows")
	await _frames(3)
	var scroll: ScrollContainer = overview.get_node("%Scroll")
	var bar := scroll.get_v_scroll_bar()
	_check(bar.is_visible_in_tree(), "rows past the bottom: the bar shows")
	_eq(bar.theme_type_variation, &"OverviewScroll", "the theme's bar")
	_eq(bar.focus_mode, Control.FOCUS_NONE, "never focused: the arrows stay the table's")
	_eq(bar.size.x, float(HudTheme.OVERVIEW_BAR), "as wide as the theme says")
	for key in overview.shown_keys():
		var timeline: Control = overview.line_for(key).get_node("%Timeline")
		var line_rect := timeline.get_global_rect()
		_check(not line_rect.intersects(bar.get_global_rect()), "%s: the bar is off its timeline" % key)
		_eq(
			bar.get_global_rect().position.x - line_rect.end.x,
			float(HudTheme.OVERVIEW_BAR_GAP),
			"%s: a gap between its `now` and the bar" % key
		)
	_bar_room(overview, "14 rows")


## The timelines are drawn once a second while the overview is open, not every frame.
func test_the_timeline_redraws_once_a_second_not_every_frame() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	await _tap(KEY_O)
	await _frames(3)
	var timeline: OverviewTimeline = office.hud.overview.line_for(local_p1).get_node("%Timeline")
	var draws: Array[int] = [0]
	timeline.draw.connect(func() -> void: draws[0] += 1)
	await _wait(1.2)
	var drawn := draws[0]
	_check(drawn >= 1 and drawn <= 3, "drawn %d times in 1.2 s" % drawn)


## Under the overview WORKING and IDLE set its chips and leave the agent list's
## filter alone; the counter pressed is the chip's, PANES stays pressed. Closed,
## the counters say the list's filter again.
func test_counters_while_open_drive_the_chips_not_the_list() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var bar := office.hud.bar
	var list := office.hud.agent_list
	await _click_control(bar.counter(&"idle"))
	_eq(list.presence_filter(), [AgentListModel.Presence.IDLE], "IDLE filters the list first")
	await _tap(KEY_O)
	_eq(bar.counter(&"idle").theme_type_variation, &"Counter", "open on ALL: IDLE is the chips', not pressed")
	await _click_control(bar.counter(&"working"))
	_eq(office.hud.overview.filter(), OverviewModel.Filter.WORKING, "WORKING sets the chip")
	_eq(list.presence_filter(), [AgentListModel.Presence.IDLE], "and leaves the list's filter")
	_eq(bar.counter(&"working").theme_type_variation, &"CounterOn", "WORKING reads pressed")
	_eq(bar.counter(&"panes").theme_type_variation, &"CounterOn", "PANES too")
	_check(office.hud.overview.shown_keys().size() >= 1, "working rows show")
	await _click_control(bar.counter(&"working"))
	_eq(office.hud.overview.filter(), OverviewModel.Filter.ALL, "again: ALL")
	_eq(bar.counter(&"working").theme_type_variation, &"Counter", "released")
	await _tap(KEY_O)
	_eq(bar.counter(&"idle").theme_type_variation, &"CounterOn", "closed: IDLE says the list's filter again")
	_eq(bar.counter(&"panes").theme_type_variation, &"Counter", "PANES released")


## A `--read-only` office opens the overview all the same (it is observation):
## a row per pane, the chips work, and nothing but the read-only three is asked.
func test_read_only_overview_opens_and_writes_nothing() -> void:
	_fakes("snapshot_basic", [])
	var office := await _office_with(true)
	await _tap(KEY_O)
	var overview := office.hud.overview
	_check(overview.is_visible_in_tree(), "it opens")
	await _until(func() -> bool: return overview.shown_keys().size() == 8, "a row per pane of both machines")
	await _click_control(_part(overview, "%ChipBlocked"))
	var both := PackedStringArray([local_blocked, HerdrFleet.pane_key(BEE, "bravo:p1")])
	_eq(overview.shown_keys(), both, "the chips work: both machines' blocked pi")
	await _click_control(_part(overview, "%ChipAll"))
	_eq(_sequence("control-a") + _sequence("control-b"), PackedStringArray(), "only the read-only three asked")


## A shell herdr is launching an agent in says STARTING in the STATE column,
## under the name herdr gave it while its kind is not recognised yet; it is no
## idle agent, so the IDLE chip leaves it out. Nothing is written.
func test_a_launching_pane_reads_starting_in_the_state_column() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var key := _pane(HerdrFleet.LOCAL, "alpha:p2")
	var raw := _launching(_raw(), "alpha:p2", {"launch_pending": true, "name": "claude-1"})
	_ctl("control-a", "set_snapshot", {"snapshot": raw})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(
		func() -> bool: return office.frame.pane(key) != null and office.frame.pane(key).starting, "p2 is starting"
	)
	await _tap(KEY_O)
	var overview := office.hud.overview
	await _until(func() -> bool: return _state_text(office, key) == "STARTING", "STATE says STARTING")
	_eq(_text(office, key, "%AgentName"), "CLAUDE-1", "under herdr's name for it")
	_eq(office.hud.overview.line_for(key).badge_mark(), ArtContract.UI_STARTING, "the starting badge, not unknown's")
	var starting_mark := AgentListRow.MARKS[AgentListModel.Presence.STARTING]
	_eq(office.hud.overview.line_for(key).badge_mark(), starting_mark, "the one the agent list wears for a start")
	var fields := {"launch_pending": true, "name": "claude-1", "agent": "claude", "agent_status": "unknown"}
	var detected := _launching(_raw(), "alpha:p2", fields)
	for pane: Dictionary in _list(detected, "panes"):
		if pane.get("pane_id") == "alpha:p2":
			pane["agent"] = "claude"
	_ctl("control-a", "set_snapshot", {"snapshot": detected})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return _text(office, key, "%AgentName") == "CLAUDE", "herdr detects claude")
	_eq(_state_text(office, key), "STARTING", "still launching: STARTING")
	_eq(office.hud.overview.line_for(key).badge_mark(), starting_mark, "and the starting badge, not unknown's `?`")
	_eq(office.hud.overview.line_for(local_p3).badge_mark(), ArtContract.STATE_IDLE, "an idle agent still wears idle's")
	_eq(_state_text(office, local_p3), "IDLE", "an idle agent still says IDLE")
	await _click_control(_part(overview, "%ChipIdle"))
	_check(not overview.shown_keys().has(key), "the IDLE chip leaves it out")
	_check(overview.shown_keys().has(local_p3), "and keeps the idle codex")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## Blocked comes first: an agent asking while herdr still launches it reads
## BLOCKED in the STATE column under the blocked badge, not STARTING under the
## hourglass, and FOR times it from when the office saw it block, with no `+`.
## Nothing is written.
func test_a_blocked_agent_still_launching_reads_blocked_in_the_state_column() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with()
	var asking := _changed(_raw(), "alpha:p1", {"agent_status": "blocked"})
	_ctl("control-a", "set_snapshot", {"snapshot": _launching(asking, "alpha:p1", {"launch_pending": true})})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(
		func() -> bool: return office.frame.pane(local_p1) != null and office.frame.pane(local_p1).starting,
		"alpha:p1 blocks while herdr still launches it"
	)
	await _tap(KEY_O)
	await _until(func() -> bool: return _state_text(office, local_p1) == "BLOCKED", "STATE says BLOCKED")
	_eq(office.hud.overview.line_for(local_p1).badge_mark(), ArtContract.STATE_BLOCKED, "under the blocked badge")
	var said := _text(office, local_p1, "%For")
	_check(said.ends_with("s") and not said.ends_with("+"), "FOR from when it blocked, no `+`: " + said)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)


# --- helpers ----------------------------------------------------------------------------


## Nothing in the overview's heading overlaps anything else in it, and all of
## it stands inside the overview.
func _heading_apart(overview: OfficeOverview, what: String) -> void:
	var parts: Array[Control] = []
	for unique: String in [
		"%Title", "%Summary", "%ChipAll", "%ChipBlocked", "%ChipDone", "%ChipWorking", "%ChipIdle", "%Close"
	]:
		var part := _part(overview, unique)
		if part.is_visible_in_tree():
			parts.append(part)
	var inside := overview.get_global_rect()
	for i in parts.size():
		var rect := parts[i].get_global_rect()
		_check(inside.encloses(rect), "%s: %s inside the overview: %s" % [what, parts[i].name, rect])
		for j in range(i + 1, parts.size()):
			var other := parts[j].get_global_rect()
			_check(
				not rect.intersects(other),
				"%s: %s %s and %s %s apart" % [what, parts[i].name, rect, parts[j].name, other]
			)


## Pane `pane_id` of machine `machine`, keyed as the fleet keys it.
static func _pane(machine: String, pane_id: String) -> String:
	return HerdrFleet.pane_key(machine, pane_id)


## The heads leave the scroll bar's room too: the axis ends where every shown timeline does.
func _bar_room(overview: OfficeOverview, what: String) -> void:
	var axis: Control = overview.get_node("%Axis")
	for key in overview.shown_keys():
		var timeline: Control = overview.line_for(key).get_node("%Timeline")
		_eq(
			timeline.get_global_rect().end.x,
			axis.get_global_rect().end.x,
			"%s, %s: `now` under the axis's" % [what, key]
		)


## The overview's (or a row's) unique control `unique`.
func _part(from: Node, unique: String) -> Control:
	return from.get_node(unique)


## A pane as the fleet would hand it to the log.
func _sighting(machine: String, pane_id: String, status: String, agent: String, since := -1.0) -> StateLog.Sighting:
	var sighting := StateLog.Sighting.new()
	sighting.pane_key = HerdrFleet.pane_key(machine, pane_id)
	sighting.identity = "term-" + pane_id
	sighting.status = status
	sighting.since_unix = since
	sighting.agent = agent
	sighting.space = "space"
	sighting.tab = "tab"
	return sighting


## A frame of machines `stale` (key -> stale) with a pane for every track of theirs.
func _frame(stale: Dictionary, ledger: StateLog) -> OfficeFrame:
	var frame := OfficeFrame.new()
	for key: String in stale:
		var building := BuildingModel.new()
		building.key = key
		building.label = key
		building.stale = stale[key] == true
		for kept in ledger.tracks():
			if kept.machine == key and not kept.gone:
				building.panes += 1
				var pane := PaneModel.new()
				pane.key = kept.key
				frame.pane_by_key[kept.key] = pane
		frame.buildings.append(building)
	return frame


## `raw` with one more pane, `pane_id`, a copy of `like` in its own terminal.
func _plus(raw: Dictionary, like: String, pane_id: String) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
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


## `raw` with pane `pane_id`'s agent record given `fields`; a shell without
## one gets one with its ids, as herdr lists a shell it launches an agent in.
func _launching(raw: Dictionary, pane_id: String, fields: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var agents := _list(result, "agents")
	var record := {}
	for each: Dictionary in agents:
		if each.get("pane_id") == pane_id:
			record = each
	if record.is_empty():
		for pane: Dictionary in _list(result, "panes"):
			if pane.get("pane_id") == pane_id:
				for field: String in ["terminal_id", "pane_id", "workspace_id", "tab_id"]:
					record[field] = pane.get(field)
		agents.append(record)
		result["agents"] = agents
	record.merge(fields, true)
	return result


## What the row of pane `key` shows in its unique label `unique`; empty with no row.
func _text(office: OfficeDouble, key: String, unique: String) -> String:
	var line := office.hud.overview.line_for(key)
	if line == null:
		return ""
	var label: Label = line.get_node(unique)
	return label.text


func _state_text(office: OfficeDouble, key: String) -> String:
	return _text(office, key, "%State")


## The spans the row of pane `key` draws now.
func _spans(office: OfficeDouble, key: String) -> Array[PackedFloat64Array]:
	var line := office.hud.overview.line_for(key)
	if line == null:
		return []
	var timeline: OverviewTimeline = line.get_node("%Timeline")
	return timeline.segments_drawn()


## The state the office's frame holds for pane `key`.
func _held_state(office: OfficeDouble, key: String) -> String:
	var pane := office.frame.pane(key)
	return "" if pane == null else pane.state


## `12s` as 12; -1 for anything else (a minute or more, a `+`).
static func _seconds(said: String) -> int:
	var digits := said.trim_suffix("s")
	return digits.to_int() if digits.is_valid_int() else -1


## Every node the HUD holds, by instance (tools/office_test_base.gd's, which
## this suite does not extend): a rebuild anywhere shows as a different list.
func _hud_nodes(office: OfficeDouble) -> Array:
	var found: Array = []
	for node: Node in office.hud.find_children("*", "", true, false):
		found.append(node.get_instance_id())
	found.sort()
	return found
