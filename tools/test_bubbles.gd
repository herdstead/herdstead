extends "res://tools/command_test_base.gd"
## The chips over blocked agents and what a click in the world or on the
## bar does with them, against two fake herdrs of this suite's own whose pane
## ids collide: the reads behind the chips (only blocked panes on screen, one
## at a time, each at most every ten seconds, never a look), the question in a
## chip's hover, a click on a chip, a far badge, a blocked seat or the
## blocked counter, NEXT and its wait, and the counters sending nothing; the
## reader's read of a blocked agent still launching, and the compact NEXT's
## whole words. Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_bubbles.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Everything runs in a live office on real frames, driven by real input
## (clicks, keys). Every gate asserts the exact requests each fake received.
## The last case sums up both fakes: nothing reached them that no case opened.


func _marker() -> String:
	return "BUBBLE TESTS"


# --- the chips' question reads -------------------------------------------------


## bee's alpha floor with its alpha:p1 and alpha:p3 blocked, both asking
## QUESTION in their detection text; Local as the fixture has it. Shown on bee's
## floor while the card still follows Local's focus, every read fake B hears
## is a chip's.
## Pan bee's alpha floor so both of its chips stand inside the world, below
## the bar and above the staff panel: the reader reads only chips on screen.
func _bee_bubbles_on_screen(office: OfficeDouble) -> void:
	var top := _station_of(office, HerdrFleet.pane_key(BEE, "alpha:p1")).chip_rect().position.y
	var room := office.hud.world_rect()
	office.camera.pan = Vector2(office.camera.pan.x, top - room.position.y - 16)
	await _frames(2)
	for pane_id: String in ["alpha:p1", "alpha:p3"]:
		var bubble := _station_of(office, HerdrFleet.pane_key(BEE, pane_id)).chip_rect()
		bubble.position -= office.camera.position
		_check(room.encloses(bubble), "%s's bubble is on screen: %s" % [pane_id, bubble])


func _blocked_pair() -> void:
	_fakes()
	var raw := _changed(
		_changed(_raw(), "alpha:p1", {"agent_status": "blocked"}), "alpha:p3", {"agent_status": "blocked"}
	)
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	for pane_id: String in ["alpha:p1", "alpha:p3"]:
		_ctl("control-b", "set_preview", {"pane_id": pane_id, "source": "detection", "text": QUESTION})


## An office whose chips' reader is on and has read nothing yet: minimized from
## before its first frame, both machines live. bee's map is the one shown, its
## chips on screen, for as long as bee's snapshot is in and Local's is not, so
## an office left to settle first may have read them already. The case says the
## window is back (`office.pacer.note_minimized(false)`) once its scene is set.
func _minimized_office(screen := Vector2(SCREEN)) -> OfficeDouble:
	var office := await _office_with(false, true, false, screen, true)
	office.pacer.note_minimized(true)
	await _until(
		func() -> bool: return office.fleet.size() == 2 and office.fleet.live_count() == 2, "both machines live"
	)
	return office


## The chips read what a blocked agent on screen asks, and nothing else: only
## the blocked panes of the floor shown (bee's alpha here, while the card reads
## Local's focus on fake A), the card's own payload (`detection`, 200 lines), one
## at a time for the whole office (the first reply held back holds the second
## read back too), and no pane again within ten seconds. A floor that is
## not shown (Local's bravo, blocked too) is not read; working, done and shell
## panes are not; nothing is ever written. The reader keeps the asking line.
func test_bubbles_read_blocked_panes_on_screen_one_at_a_time() -> void:
	_blocked_pair()
	# Held from before the office is there: bee's map is the one shown, its
	# chips on screen and read, for as long as bee's snapshot is in and Local's
	# is not.
	_ctl("control-b", "next", {"action": "hold", "method": "pane.read"})
	var office := await _office_with(false, true, true, Vector2(SCREEN), true)
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	await _bee_bubbles_on_screen(office)
	await _until(func() -> bool: return _number(_ctl("control-b", "stats"), "held_replies") == 1, "a read is held")
	await _wait(0.6)
	_eq(_read_panes("control-b"), ["alpha:p1"], "the longest-waiting first, and while it is out, nothing else")
	_check(office.questions.reading(), "the reader says a read is out")
	_ctl("control-b", "release_held")
	await _until_stats(
		"control-b", func(_stats: Dictionary) -> bool: return _read_panes("control-b").size() >= 2, "the second read"
	)
	await _until_stats(
		"control-b", func(_stats: Dictionary) -> bool: return _read_panes("control-b").size() >= 3, "the third read"
	)
	await _wait(1.5)
	# bee's blocked bravo:p1 is another zone of the same map now, its chip on
	# screen under alpha's: it is read too, after alpha's two, in wait order.
	_eq(
		_read_panes("control-b"),
		["alpha:p1", "alpha:p3", "bravo:p1"],
		"then the other, then bravo's, one at a time, and none again within ten seconds"
	)
	_eq(
		_sequence("control-b"),
		PackedStringArray(["pane.read detection 200", "pane.read detection 200", "pane.read detection 200"]),
		"the card's own payload, nothing else asked of bee"
	)
	_eq(_read_panes("control-a"), [], "Local's blocked bravo:p1 is on a map not shown: not read")
	var station := _station_of(office, HerdrFleet.pane_key(BEE, "alpha:p1"))
	var p1 := HerdrFleet.pane_key(BEE, "alpha:p1")
	await _until(
		func() -> bool: return _question_of(office, p1) == "Do you want to proceed?", "the reader keeps the asking line"
	)
	_ctl(
		"control-b",
		"set_snapshot",
		{
			"snapshot":
			_changed(_changed(_raw(), "alpha:p1", {"agent_status": "working"}), "alpha:p3", {"agent_status": "done"})
		}
	)
	await _until(func() -> bool: return not station.chip().visible, "no longer blocked: no bubble")
	await _wait(1.0)
	_eq(_read_panes("control-b").size(), 3, "working, done and the shell are never read")
	_eq(_all_inputs(), 0, "no input went anywhere")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "no switch either")
	_eq(office.fleet.write_log().size(), 0, "and the audit has no write")


## Nothing is read while the window is minimized, while the chips are off
## screen (a pan brings them back without a refresh), while the terminal
## monitor covers the world, or while their machine is stale; the first read
## comes once all of them let it. Stale and never read, a chip shows no wait
## and no frame, and its tooltip promises no read: it says there is no question
## read yet.
func test_bubbles_read_nothing_while_minimized_covered_stale_or_off_screen() -> void:
	_blocked_pair()
	# Twelve more shells on bee's alpha:t1: a pod of eight columns (9 cells) takes
	# two lanes, a map (23 cells) wide enough to pan its blocked seats off the
	# 480-wide window; one lane's 13 cells leave only 76 units of pan (lane B2a).
	var wide := _changed(
		_changed(_raw(), "alpha:p1", {"agent_status": "blocked"}), "alpha:p3", {"agent_status": "blocked"}
	)
	var shell: Dictionary = {}
	for record: Dictionary in _list(wide, "panes"):
		if record.pane_id == "alpha:p2":
			shell = record
	for index in 12:
		var extra: Dictionary = shell.duplicate(true)
		extra.pane_id = "alpha:x%d" % index
		extra.terminal_id = "term-alpha-x%d" % index
		_list(wide, "panes").append(extra)
	_ctl("control-b", "set_snapshot", {"snapshot": wide})
	var office := await _minimized_office(Vector2(480, 320))
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	var station := _station_of(office, HerdrFleet.pane_key(BEE, "alpha:p1"))
	await _until(func() -> bool: return station.chip().visible, "the bubbles show")
	await _wait(1.0)
	_eq(_read_panes("control-b"), [], "minimized: nothing read")
	office.camera.pan = Vector2(10000, 10000)
	await _frames(3)
	for pane_id: String in ["alpha:p1", "alpha:p3"]:
		var bubble := _station_of(office, HerdrFleet.pane_key(BEE, pane_id)).chip_rect()
		var on_screen := Rect2(bubble.position - office.camera.position, bubble.size)
		_check(not on_screen.intersects(office.hud.world_rect()), "%s's bubble is panned off screen" % pane_id)
	office.pacer.note_minimized(false)
	await _wait(1.0)
	_eq(_read_panes("control-b"), [], "restored but off screen: nothing read")
	# The monitor, as the list's double-click asks for it, on the shell next door.
	office.hud.monitor_requested.emit(HerdrFleet.pane_key(BEE, "alpha:p2"))
	await _until(office.hud.monitor_open, "the monitor covers the world")
	office.reveal(HerdrFleet.pane_key(BEE, "alpha:p1"))
	await _frames(3)
	var bubble := station.chip_rect()
	var shown := Rect2(bubble.position - office.camera.position, bubble.size)
	_check(shown.intersects(office.hud.world_rect()), "alpha:p1's bubble is panned back on screen")
	await _wait(1.0)
	_eq(_read_panes("control-b"), [], "on screen under the monitor: nothing read")
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "bee drops")
	office.hud.close_monitor()
	await _until(func() -> bool: return not office.hud.monitor_open(), "the monitor closes")
	await _wait(1.0)
	_eq(_read_panes("control-b"), [], "on screen but stale: nothing read")
	var wait: Label = station.chip().get_node("%Wait")
	_eq(wait.text, "", "stale: the bubble shows no wait")
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	_check(not frame.visible, "nor an empty frame")
	await _move_pointer(await _bubble_point(office, station.pane_key))
	_check(office.hud.world_tip_shown(), "the tooltip shows over the bubble")
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.NOT_READ_TEXT, "and promises no read")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return not office.fleet.is_stale(BEE), "bee is back and current")
	await _until_stats(
		"control-b", func(_stats: Dictionary) -> bool: return not _read_panes("control-b").is_empty(), "a read at last"
	)
	_eq(_all_inputs(), 0, "and nothing written, ever")


## A chip's read is never the look that turns writes back on after one ended:
## once a key went to bee's alpha:p3, the chip reads its question again and
## shows it, and writes to that pane stay closed until the card's own preview
## read, begun after the write ended, comes back and is shown.
func test_a_bubble_read_is_not_a_look() -> void:
	var office := await _blocked_bee()
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the key went")
	_check(office.fleet.must_look(key), "a write ended: the pane waits for a look")
	await _click_visible_pane(office, HerdrFleet.pane_key(BEE, "alpha:p1"))
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "alpha:p1"), "the card is on another pane")
	var before := _read_panes("control-b").count("alpha:p3")
	# Past HerdrCommands.LOOK_DELAY_MSEC after the write ended: a read begun
	# sooner is no look however it is shown, so the reader's read has to start
	# after it for this case to catch a reader that calls preview_shown().
	await _wait(0.6)
	office.questions.enabled = true
	await _until_stats(
		"control-b",
		func(_stats: Dictionary) -> bool: return _read_panes("control-b").count("alpha:p3") > before,
		"the bubble reads alpha:p3"
	)
	await _until(
		func() -> bool: return _question_of(office, key) == "Do you want to proceed?", "and keeps its question"
	)
	await _wait(0.3)
	_check(office.fleet.must_look(key), "the bubble's read is no look: writes stay closed")
	await _click_visible_pane(office, key)
	# The panel is one line until opened: the look is the opened card's preview.
	await _open_panel(office)
	await _until(func() -> bool: return not office.fleet.must_look(key), "the card's own preview is the look")
	_eq(_inputs("control-b").size(), 1, "one key, and nothing since")


## A `--read-only` office reads nothing for its chips (it has no command
## boundary to read through) and says so in the tooltip over them.
func test_read_only_bubbles_read_nothing_and_say_so() -> void:
	_blocked_pair()
	var office := await _office_with(true, true, true, Vector2(SCREEN), true)
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	var station := _station_of(office, HerdrFleet.pane_key(BEE, "alpha:p1"))
	await _until(func() -> bool: return station.chip().visible, "the bubble shows")
	await _wait(1.0)
	await _move_pointer(await _bubble_point(office, station.pane_key))
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "the tooltip says read-only")
	_eq(_count("control-a", "pane.read") + _count("control-b", "pane.read"), 0, "and nothing was read")
	_eq(_all_inputs(), 0, "nor written")


## No pane is read again within ten seconds of its last read beginning,
## whatever it does meanwhile: bee's alpha:p1 goes working and blocked again,
## and the viewer steps a floor up and back (PageUp, PageDown); neither brings
## a second read. Blocked again, it has no question kept (a new block never
## shows the old one) until the spacing has passed and it is read afresh.
func test_a_pane_is_read_at_most_every_ten_seconds_whatever_it_does() -> void:
	_blocked_pair()
	var office := await _minimized_office()
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	await _bee_bubbles_on_screen(office)
	office.pacer.note_minimized(false)
	await _until_stats(
		"control-b", func(_stats: Dictionary) -> bool: return _read_panes("control-b").has("alpha:p1"), "p1 is read"
	)
	var first := Time.get_ticks_msec()
	var p1 := HerdrFleet.pane_key(BEE, "alpha:p1")
	var station := _station_of(office, p1)
	await _until(func() -> bool: return not _question_of(office, p1).is_empty(), "its question is kept")
	_ctl("control-b", "status", {"pane_id": "alpha:p1", "agent_status": "working"})
	await _until(func() -> bool: return not station.chip().visible, "working: no bubble")
	_ctl("control-b", "status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	await _until(func() -> bool: return station.chip().visible, "blocked again")
	_eq(_question_of(office, p1), "", "blocked again: the old question is not kept")
	# The rail is ascending: bravo (2) is the row after alpha (1).
	await _navigate_key(office, KEY_PAGEDOWN)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(BEE, "bravo"), "PageDown pans to bee's bravo")
	await _navigate_key(office, KEY_PAGEUP)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(BEE, "alpha"), "PageUp brings alpha back")
	await _wait(1.0)
	_eq(_read_panes("control-b").count("alpha:p1"), 1, "no second read of p1 within ten seconds")
	_eq(_read_panes("control-b").count("alpha:p3"), 1, "nor of p3")
	var deadline := first + 13000
	while _read_panes("control-b").count("alpha:p1") < 2 and Time.get_ticks_msec() < deadline:
		await _wait(0.2)
	var elapsed := (Time.get_ticks_msec() - first) / 1000.0
	_eq(_read_panes("control-b").count("alpha:p1"), 2, "then read again, the spacing past")
	# `first` is when the first read was seen, a little after it began.
	_check(elapsed >= 9.0, "no sooner than ten seconds after the first began: %.1f s" % elapsed)
	await _until(func() -> bool: return not _question_of(office, p1).is_empty(), "and its question is kept again")
	_eq(_all_inputs(), 0, "nothing written")


## Hovering a blocked agent's chip, by real pointer motion, shows the
## question's excerpt the reader keeps in a HUD tooltip near the pointer and
## inside the world's part of the screen, though its start was never seen and
## the chip draws no frame. The pane taking another terminal
## while still blocked, under the pointer, drops the old excerpt at once: the
## tooltip says no question is read yet, never the old session's (the next
## read waits for its ten seconds). The pointer leaving the chip takes it away.
func test_hovering_a_bubble_shows_the_question_it_read() -> void:
	_blocked_pair()
	var office := await _minimized_office()
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	await _bee_bubbles_on_screen(office)
	office.pacer.note_minimized(false)
	var p1 := HerdrFleet.pane_key(BEE, "alpha:p1")
	await _until(func() -> bool: return not _question_of(office, p1).is_empty(), "p1's question is read")
	var frame: NinePatchRect = _station_of(office, p1).chip().get_node("%Frame")
	_check(not frame.visible, "blocked in the first snapshot: no wait and no frame")
	var at := await _bubble_point(office, p1)
	await _move_pointer(at)
	_check(office.hud.world_tip_shown(), "the tooltip shows")
	_eq(office.hud.world_tip_text(), "Do you want to proceed?", "with the excerpt read")
	var tip: Control = office.hud.get_node("%WorldTip")
	_check(office.hud.world_rect().encloses(tip.get_global_rect()), "inside the world's part of the screen")
	var identity := office.frame.pane(p1).identity_key()
	var again := _changed(
		_changed(_raw(), "alpha:p1", {"agent_status": "blocked", "terminal_id": "term-alpha-p1-again"}),
		"alpha:p3",
		{"agent_status": "blocked"}
	)
	_ctl("control-b", "set_snapshot", {"snapshot": again})
	await _until(func() -> bool: return office.frame.pane(p1).identity_key() != identity, "p1 has another terminal")
	_check(office.hud.world_tip_shown(), "still blocked, still under the pointer: the tooltip stays")
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.NOT_READ_TEXT, "and drops the old session's question at once")
	await _move_pointer(at + Vector2(0, 60))
	_check(not office.hud.world_tip_shown(), "the pointer leaves: the tooltip goes")
	_eq(_all_inputs(), 0, "nothing written")


# --- a click on a blocked agent's chip ------------------------------------------


## A real click on the chip over bee's blocked alpha:p3 picks that pane as the
## list does, and the card goes into answer mode only once its preview read has
## come back and shows the question (held back here for half a second): until
## then it is not answering. The click itself sends nothing, nor does opening
## answer mode, and the chip holds no button to answer with. Blocked in bee's
## first snapshot, its start was never seen: the chip draws nothing, frame
## included, and its rectangle answers the click all the same.
func test_a_click_on_a_bubble_opens_answer_mode_once_the_question_is_shown() -> void:
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with()
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var station := _station_of(office, key)
	_eq(station.chip().find_children("*", "Button", true, false), [], "the bubble holds no button")
	await _wait(OfficeAttention.TEXT_INTERVAL + 0.15)
	var wait: Label = station.chip().get_node("%Wait")
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	_check(station.chip().visible and wait.text.is_empty(), "blocked, its start never seen: no wait")
	_check(not frame.visible, "and no frame")
	var card := _card(office)
	_ctl("control-b", "next", {"action": "delay", "method": "pane.read", "seconds": 0.5})
	await _click_bubble(office, key)
	_eq(office.picked_key, key, "the click picks the bubble's pane")
	_check(not card.answering(), "not answering before the question is shown")
	await _until(func() -> bool: return card.preview_text() == QUESTION, "the question is shown")
	await _until(card.answering, "then answer mode opens")
	await _frames(3)
	_eq(_writes_seen("control-b"), PackedStringArray(), "nothing was sent")
	_eq(_all_inputs(), 0, "not a byte")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "and no switch")


## At the smallest screen, where the card is a compact header, a click on a
## chip opens the card up and then answer mode, as Enter on a picked pane does.
func test_a_bubble_click_opens_a_compact_card() -> void:
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with(false, true, true, Vector2(480, 320))
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	_check(office.hud.card_compact(), "the card is a compact header")
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	await _click_bubble(office, key)
	_eq(office.picked_key, key, "the click picks the bubble's pane")
	_check(not office.hud.card_compact(), "and opens the card up")
	await _until(_card(office).answering, "answer mode, once the question is shown")
	_check(not office.hud.card_compact(), "the card stays open in answer mode")
	# The panel open on another pane: a chip click opens it for the
	# chip's pane at once, and answer mode there, not a fold a frame later.
	await _tap(KEY_ESCAPE)
	await _pick_bee(office, "alpha:p1")
	_check(not office.hud.card_compact(), "the panel open on alpha:p1")
	await _click_bubble(office, key)
	_eq(office.picked_key, key, "the bubble picks alpha:p3 again")
	await _until(_card(office).answering, "and answer mode opens there")
	_check(not office.hud.card_compact(), "the panel open for it")
	_eq(_all_inputs(), 0, "nothing was sent")


## NEXT is `N`: three presses of the staff panel's NEXT pick the same three
## agents, in the same order, as three presses of N from the same start, each
## the one NEXT named, verb and all, before the press. Both do what the verb
## says: a blocked agent's answer mode opens once its question shows,
## a done one's panel opens. Neither sends anything: past the read-only three,
## the fakes hear only the card's preview reads of whom they picked.
func test_next_walks_the_same_queue_as_n_and_sends_nothing() -> void:
	var walks: Array[PackedStringArray] = []
	for by_key: bool in [false, true]:
		_fakes()
		_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "done"})})
		_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
		var office := await _office_with()
		await _frames(3)
		var card := _card(office)
		var button: Button = card.get_node("%NextButton")
		var how := "N" if by_key else "NEXT"
		var walk := PackedStringArray()
		for press in 3:
			var named := office.navigator.peek_next(office.frame)
			_check(not named.is_empty(), "%s %d: somebody is next" % [how, press])
			var next := office.frame.pane(named)
			var asks := next != null and next.asks()
			if next != null:
				var verb := "Answer" if asks else "Read"
				var who := "%s %s %s" % [verb, next.provider.to_upper(), next.workspace_label]
				_check(
					card.next_text().begins_with(who), "%s %d: NEXT names %s: %s" % [how, press, who, card.next_text()]
				)
			if by_key:
				await _tap(KEY_N)
			else:
				await _click_control(button)
			await _until(
				func() -> bool: return office.picked_key == named, "%s %d picks whom NEXT named" % [how, press]
			)
			_check(not office.hud.card_compact(), "%s %d opens the panel" % [how, press])
			if asks:
				await _until(card.answering, "%s %d: answer mode, once the question shows" % [how, press])
			else:
				await _frames(3)
				_check(not card.answering(), "%s %d: a done one opens no answer mode" % [how, press])
			walk.append(office.picked_key)
			await _frames(2)
		walks.append(walk)
		_eq(_all_inputs(), 0, how + ": nothing was sent")
		for which: String in ["control-a", "control-b"]:
			for entry in _sequence(which):
				_check(
					entry.begins_with("pane.read ") and not entry.ends_with(" check"),
					"%s: only previews, %s" % [how, entry]
				)
		root.remove_child(office)
		office.free()
	_eq(walks.size(), 2, "both walks ran")
	if walks.size() == 2:
		_eq(walks[0], walks[1], "NEXT walks the queue N walks")
		_eq(walks[0].size(), 3, "three picks")


## NEXT's wait ticks on the attention clock in the card's words, with the key
## after it; once nobody needs a human it says `All clear`, is off, and a press
## picks nobody.
func test_the_next_wait_ticks_and_all_clear_disables() -> void:
	_fakes()
	# Only bee's alpha:p3 will need a human; its start is seen, so its wait is known.
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "idle"})
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	_ctl("control-b", "set_snapshot", {"snapshot": quiet})
	var office := await _office_with()
	var card := _card(office)
	var button: Button = card.get_node("%NextButton")
	var line: Label = card.get_node("%NextLine")
	var wait: Label = card.get_node("%NextWait")
	await _until(func() -> bool: return line.text == "All clear", "nobody is next yet")
	_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": "blocked"})
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	await _until(func() -> bool: return office.navigator.peek_next(office.frame) == key, "bee's alpha:p3 is next")
	await _until(func() -> bool: return not button.disabled, "NEXT is on")
	var pane := office.frame.pane(key)
	var said := "Answer %s %s @ %s" % [pane.provider.to_upper(), pane.workspace_label, office.fleet.label(BEE)]
	_eq(line.text, said, "it names bee's alpha:p3, to answer, on bee")
	var ticking := RegEx.create_from_string("^\\d+s \\(N\\)$")
	await _until(func() -> bool: return ticking.search(wait.text) != null, "its wait ticks: " + wait.text)
	_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": "idle"})
	await _until(func() -> bool: return line.text == "All clear", "answered: nobody is next")
	_eq(wait.text, "", "and NEXT waits for nothing")
	_check(button.disabled, "it is off")
	await _click_control(button)
	await _frames(2)
	_eq(office.picked_key, "", "and a press picks nobody")
	_eq(_all_inputs(), 0, "nothing was sent")


## Real press and release through Input at `global` (a point in the world),
## brought on screen first by revealing pane `key`.
func _click_world(office: OfficeDouble, key: String, global: Vector2) -> void:
	office.reveal(key)
	await process_frame
	await process_frame
	var at := global - office.camera.position
	_check(office.hud.world_rect().has_point(at), "%s is on screen at %s" % [global, at])
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = at
		event.global_position = at
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await physics_frame


## Bee's alpha floor shown, and the station of its first far agent.
func _far_agent(office: OfficeDouble) -> OfficeStation:
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	for pane_id: String in ["alpha:p1", "alpha:p3"]:
		var station := _station_of(office, HerdrFleet.pane_key(BEE, pane_id))
		if station.side == "far":
			return station
	_fail("bee's alpha has no far agent")
	return null


## The middle of the far tag row of `station`, in the world: where its badge is
## drawn at rest, and inside the chip while one shows.
static func _badge_middle(station: OfficeStation) -> Vector2:
	return station.global_position + OfficeStation.BADGE_AT["far"] + Vector2(0, -8)


## The far badge answers a click in every state: on a working agent it picks
## the pane, and the card stays out of answer mode.
func test_a_click_on_a_far_badge_picks_a_working_pane() -> void:
	_fakes()
	var office := await _office_with()
	var station := await _far_agent(office)
	_check(not station.chip().visible, "a working agent has no bubble")
	await _click_world(office, station.pane_key, _badge_middle(station))
	_eq(office.picked_key, station.pane_key, "the badge picks its pane")
	await _wait(0.5)
	_check(not _card(office).answering(), "and opens no answer mode")
	_eq(_all_inputs(), 0, "nothing was sent")


## On a blocked agent the badge lies over the chip's right end and is drawn
## above it; a click there is the chip's: the pane is picked and answer mode
## opens once the question is shown. Blocked while bee is watched, its start is
## seen, and the wait shows in the chip's frame.
func test_a_click_on_a_blocked_far_badge_is_a_bubble_click() -> void:
	_fakes()
	var office := await _office_with()
	var station := await _far_agent(office)
	var pane_id := HerdrFleet.split_key(station.pane_key)[1]
	_ctl("control-b", "set_preview", {"pane_id": pane_id, "source": "detection", "text": QUESTION})
	_ctl("control-b", "status", {"pane_id": pane_id, "agent_status": "blocked"})
	await _until(func() -> bool: return station.chip().visible, "the bubble shows")
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	await _until(func() -> bool: return frame.visible, "blocked while watched: a wait, in its frame")
	_check(station.chip_rect().has_point(_badge_middle(station)), "the badge's middle is in the bubble")
	await _click_world(office, station.pane_key, _badge_middle(station))
	_eq(office.picked_key, station.pane_key, "the click picks the pane")
	await _until(_card(office).answering, "answer mode, once the question is shown")
	_eq(_all_inputs(), 0, "nothing was sent")


## On a blocked agent a click on the seat itself, below the chip, only picks.
func test_a_click_on_a_blocked_seat_only_picks() -> void:
	_fakes()
	var office := await _office_with()
	var station := await _far_agent(office)
	var pane_id := HerdrFleet.split_key(station.pane_key)[1]
	_ctl("control-b", "set_preview", {"pane_id": pane_id, "source": "detection", "text": QUESTION})
	_ctl("control-b", "status", {"pane_id": pane_id, "agent_status": "blocked"})
	await _until(func() -> bool: return station.chip().visible, "the bubble shows")
	var body := station.target_rect().get_center()
	_check(not station.chip_rect().has_point(body), "the seat's middle is not the bubble's")
	await _click_world(office, station.pane_key, body)
	_eq(office.picked_key, station.pane_key, "the click picks the pane")
	var card := _card(office)
	_check(office.hud.card_compact(), "and opens nothing: the panel stays one line")
	# Enter opens the panel, and only that: the question is read and shown.
	await _open_panel(office)
	await _until(func() -> bool: return card.preview_text() == QUESTION, "the question is shown")
	await _wait(0.5)
	_check(not card.answering(), "and answer mode stays shut: the seat's click, and Enter's opening, answer nothing")
	_eq(_all_inputs(), 0, "nothing was sent")


## Bee's alpha floor shown, and the station of one of its agents on the near side.
func _near_agent(office: OfficeDouble) -> OfficeStation:
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	for pane_id: String in ["alpha:p1", "alpha:p2", "alpha:p3"]:
		var station := _station_of(office, HerdrFleet.pane_key(BEE, pane_id))
		if station.side == "near" and station.actor() != null:
			return station
	_fail("bee's alpha has no near agent")
	return null


## A near agent's chip hangs below the chair, on the tag row: a click on the
## seat itself (the chair and the worker) only picks, and answer mode stays
## shut; a click on the chip, where its badge is drawn in its left half, picks
## and opens answer mode once the question is shown. Neither sends anything.
func test_a_near_chip_answers_and_the_near_seat_only_picks() -> void:
	_fakes()
	# alpha:p2 sits on the near side; the fixture has it a shell, so an agent here.
	var near := _changed(_raw(), "alpha:p2", {"agent": "claude", "agent_status": "working"})
	_ctl("control-b", "set_snapshot", {"snapshot": near})
	var office := await _office_with()
	var station := await _near_agent(office)
	var pane_id := HerdrFleet.split_key(station.pane_key)[1]
	_ctl("control-b", "set_preview", {"pane_id": pane_id, "source": "detection", "text": QUESTION})
	_ctl("control-b", "status", {"pane_id": pane_id, "agent_status": "blocked"})
	await _until(func() -> bool: return station.chip().visible, "the chip shows")
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	await _until(func() -> bool: return frame.visible, "blocked while watched: a wait, in its frame")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	var on_badge := badge.get_global_transform() * badge.get_rect()
	# Across, in the chip's left half; up and down it pulses (by up to 2), so
	# only its columns are compared.
	var chip := station.chip_rect()
	_check(
		(
			on_badge.position.x >= chip.position.x - 1.5
			and on_badge.end.x <= chip.position.x + OfficeChip.BADGE_SLOT + 0.5
		),
		"the badge is in the chip's left half, a unit over its edge: %s in %s" % [on_badge, chip]
	)
	var body := station.target_rect().get_center()
	_check(not station.chip_rect().has_point(body), "the seat's middle is not the chip's")
	_check(body.y < station.chip_rect().position.y, "the chip hangs below the seat")
	await _click_world(office, station.pane_key, body)
	_eq(office.picked_key, station.pane_key, "the seat's click picks the pane")
	await _wait(0.5)
	_check(not _card(office).answering(), "and opens no answer mode")
	await _click_world(office, station.pane_key, on_badge.get_center())
	_eq(office.picked_key, station.pane_key, "the chip's click picks the same pane")
	await _until(_card(office).answering, "and answer mode opens, once the question is shown")
	_eq(_all_inputs(), 0, "nothing was sent")


# --- the top bar's counters ------------------------------------------------------


## A real click on the top bar's BLOCKED picks the one blocked agent, bee's
## alpha:p3, on its floor, and the card goes into answer mode only once its
## preview read has come back and shows the question, the way a click on its
## chip does. The click itself sends nothing: what it causes is the card's
## preview reads of alpha:p3.
func test_a_blocked_counter_click_opens_answer_mode_once_the_question_is_shown() -> void:
	_fakes()
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "working"})
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(quiet, "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with()
	await _frames(3)
	var before_a := _sequence("control-a")
	var before_b := _sequence("control-b")
	var reads_before := _read_panes("control-b").size()
	var card := _card(office)
	_ctl("control-b", "next", {"action": "delay", "method": "pane.read", "seconds": 0.5})
	await _click_control(office.hud.bar.counter(&"blocked"))
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	_eq(office.picked_key, key, "the click picks the one blocked agent")
	_eq(
		[office.navigator.shown_key, office.navigator.current_zone(office.frame)],
		[BEE, HerdrFleet.pane_key(BEE, "alpha")],
		"on its machine's map, its zone current"
	)
	_check(not card.answering(), "not answering before the question is shown")
	await _until(func() -> bool: return card.preview_text() == QUESTION, "the question is shown")
	await _until(card.answering, "then answer mode opens")
	await _frames(3)
	_eq(_sequence("control-a"), before_a, "Local is asked nothing")
	# The card re-reads a blocked pane every second while it shows it, so how
	# many reads is a matter of timing; that every one is a preview read is not.
	var caused := _sequence("control-b").slice(before_b.size())
	_check(not caused.is_empty(), "bee is asked for the question")
	for entry in caused:
		_check(entry.begins_with("pane.read ") and not entry.ends_with(" check"), "only preview reads: " + entry)
	var read := _read_panes("control-b").slice(reads_before)
	_check(
		not read.is_empty() and read.all(func(id: Variant) -> bool: return id == "alpha:p3"), "of alpha:p3: %s" % [read]
	)
	_eq(_all_inputs(), 0, "nothing was sent")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "and no switch")


## Resting on each counter and clicking WORKING, IDLE, MACHINES, PANES and DONE
## (nobody is UNREAD here) asks either herdr nothing at all.
func test_counters_hover_and_filter_send_nothing() -> void:
	_fakes()
	var office := await _office_with()
	await _frames(3)
	var before_a := _sequence("control-a")
	var before_b := _sequence("control-b")
	var bar := office.hud.bar
	for counter in bar.counters():
		var at := counter.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await _frames(2)
		_check(not counter.get_tooltip(counter.get_local_mouse_position()).is_empty(), "%s has its hover" % counter.id)
	for id: StringName in [&"working", &"idle", &"machines", &"panes", &"done"]:
		await _click_control(bar.counter(id))
	_check(office.hud.agent_list.presence_filter() == [AgentListModel.Presence.IDLE], "IDLE's filter stands")
	await _frames(3)
	_eq(_sequence("control-a"), before_a, "Local is asked nothing")
	_eq(_sequence("control-b"), before_b, "nor is bee")
	_eq(_all_inputs(), 0, "not a byte")


## On the 480x320 compact line NEXT has no room for `NEXT:`, the verb and the
## machine: it names whom N picks, provider and space, whole, and its tooltip
## says the rest. On the 800x480 line (it stays one line there) it says
## `NEXT:` and the whole sentence in a row. With nobody next the compact line
## says `NEXT: All clear`, whole.
func test_the_compact_next_shows_whole_words() -> void:
	# bravo:p1 is blocked in the fixture, on both machines; Local's is first.
	_fakes()
	var office := await _office_with(false, true, true, Vector2(480, 320))
	var card := _card(office)
	var button: Button = card.get_node("%NextButton")
	var title: Label = card.get_node("%NextTitle")
	var line: Label = card.get_node("%NextLine")
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo:p1")
	await _until(func() -> bool: return office.navigator.peek_next(office.frame) == key, "Local's bravo:p1 is next")
	await _until(func() -> bool: return not button.disabled, "NEXT is on")
	await _frames(2)
	_check(card.compact(), "480x320: the compact line")
	var pane := office.frame.pane(key)
	var who := "%s %s" % [pane.provider.to_upper(), pane.workspace_label]
	var said := "Answer %s @ %s" % [who, office.fleet.label(HerdrFleet.LOCAL)]
	_check(button.is_visible_in_tree(), "NEXT is on the compact line")
	_check(not title.is_visible_in_tree(), "no `NEXT:` on the compact line")
	_eq(line.text, who, "whom, and where")
	_eq(card.next_text(), who, "what it shows")
	var font := line.get_theme_font("font")
	var needed := (
		font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size")).x
	)
	_check(needed <= line.size.x + 0.5, "`%s` whole: %.1f of %.1f" % [line.text, needed, line.size.x])
	var across := line.get_global_rect()
	var room := button.get_global_rect()
	_check(
		across.position.x >= room.position.x and across.end.x <= room.end.x,
		"across the button: %s in %s" % [across, room]
	)
	var own := "N: the next agent who needs you"
	_check(button.tooltip_text.begins_with(own), "the button's own sentence first: " + button.tooltip_text)
	_check(button.tooltip_text.ends_with("\nNext: " + said), "the tooltip says the rest: " + button.tooltip_text)
	office.test_screen = Vector2(800, 480)
	office.refresh()
	await _until(func() -> bool: return title.is_visible_in_tree(), "800x480: the wide line")
	await _frames(2)
	_check(card.compact(), "800x480: still the one line")
	_check(title.is_visible_in_tree(), "`NEXT:` before it again")
	_eq(line.text, said, "the whole sentence")
	_check(
		button.tooltip_text.begins_with(own) and button.tooltip_text.ends_with("\nNext: " + said),
		"the tooltip says it whole too, in case the line clips it: " + button.tooltip_text
	)
	for which: String in ["control-a", "control-b"]:
		_ctl(which, "status", {"pane_id": "bravo:p1", "agent_status": "idle"})
	await _until(func() -> bool: return line.text == "All clear", "answered: nobody is next")
	office.test_screen = Vector2(480, 320)
	office.refresh()
	await _until(card.compact, "480x320 again")
	await _frames(2)
	_check(title.is_visible_in_tree(), "`NEXT:` before nobody")
	var both := title.get_global_rect().merge(line.get_global_rect())
	for label: Label in [title, line]:
		var width := (
			label
			. get_theme_font("font")
			. get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
			. x
		)
		_check(width <= label.size.x + 0.5, "`%s` whole: %.1f of %.1f" % [label.text, width, label.size.x])
	_check(both.end.x <= button.get_global_rect().end.x, "`NEXT: All clear` across the button: %s" % both)
	_eq(button.tooltip_text.find("\nNext: "), -1, "nobody to say more of")
	_eq(_all_inputs(), 0, "nothing was sent")


## NEXT's verb on a blocked agent is `Answer`: `N` picks it and opens
## its panel, and answer mode once its question shows. A digit pressed before
## that sends nothing; once the question shows, a digit sends exactly one key.
## Enter never sends.
func test_next_on_a_blocked_agent_opens_answer_mode_and_n_then_a_digit_sends_one_key() -> void:
	_fakes()
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "working"})
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(quiet, "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with()
	await _frames(3)
	var card := _card(office)
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	_eq(office.navigator.peek_next(office.frame), key, "the one blocked agent is next")
	_check(card.next_text().begins_with("Answer CODEX alpha"), "NEXT says what a press does: " + card.next_text())
	_ctl("control-b", "next", {"action": "delay", "method": "pane.read", "seconds": 1.0})
	await _tap(KEY_N)
	await _until(func() -> bool: return office.picked_key == key, "N picks it")
	_check(not office.hud.card_compact(), "and opens its panel")
	_check(not card.answering(), "not answering before the question shows")
	await _tap(KEY_1)
	await _tap(KEY_ENTER)
	await _frames(3)
	_eq(_count("control-b", "pane.send_keys"), 0, "a digit (and Enter) before the question shows sends nothing")
	await _until(card.answering, "answer mode once the question shows")
	await _tap(KEY_ENTER)
	await _frames(3)
	_eq(_count("control-b", "pane.send_keys"), 0, "Enter never sends")
	await _tap(KEY_1)
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the key went")
	_eq(_count("control-b", "pane.send_keys"), 1, "exactly one key")
	_eq(_count("control-a", "pane.send_keys"), 0, "and none to Local")


## NEXT's verb on a done agent is `Read`: a real click on NEXT picks it and
## opens its panel, and no answer mode; nothing is sent.
func test_next_on_a_done_agent_opens_its_card_without_answer_mode() -> void:
	_fakes()
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "working"})
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(quiet, "alpha:p3", {"agent_status": "done"})})
	var office := await _office_with()
	await _frames(3)
	var card := _card(office)
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	_eq(office.navigator.peek_next(office.frame), key, "the one done agent is next")
	_check(card.next_text().begins_with("Read CODEX alpha"), "NEXT says what a press does: " + card.next_text())
	_check(office.hud.card_compact(), "the panel is one line")
	var next: Control = card.get_node("%NextButton")
	await _click_control(next)
	await _until(func() -> bool: return office.picked_key == key, "NEXT picks it")
	_check(not office.hud.card_compact(), "and opens its panel")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "its preview")
	await _frames(3)
	_check(not card.answering(), "no answer mode")
	_eq(_all_inputs(), 0, "nothing was sent")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "and no switch")


## What NEXT says it will do for pane `key`: `Answer CLAUDE alpha lab @ bee`.
func _answer_line(office: OfficeDouble, key: String) -> String:
	var pane := office.frame.pane(key)
	if pane == null:
		return "(no pane %s)" % key
	return "Answer %s %s @ %s" % [pane.provider.to_upper(), pane.workspace_label, office.fleet.label(pane.machine())]


## While anyone is blocked, `N` walks the
## blocked only, longest wait first, and round again among them. Local's
## alpha:p3 done first, then Local's alpha:p1, bee's alpha:p1 and bee's alpha:p3
## blocked in that order, every start seen. A real click picks the newest
## blocked; each real `N` then picks the next blocked, oldest first after it,
## and never the done one who has waited longest of all; each opens answer mode
## once its question shows (N leaves the one before and arms the next), and
## NEXT names a blocked agent to answer. Nothing is sent.
func test_n_from_the_newest_blocked_goes_to_the_oldest_blocked_not_a_done() -> void:
	_fakes()
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "working"})
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	_ctl("control-b", "set_snapshot", {"snapshot": quiet})
	for which: String in ["control-a", "control-b"]:
		_ctl(which, "set_preview", {"pane_id": "alpha:p1", "source": "detection", "text": QUESTION})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with()
	await _frames(3)
	var done := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3")
	var oldest := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1")
	var middle := HerdrFleet.pane_key(BEE, "alpha:p1")
	var newest := HerdrFleet.pane_key(BEE, "alpha:p3")
	var order: Array = [
		["control-a", "alpha:p3", "done", done],
		["control-a", "alpha:p1", "blocked", oldest],
		["control-b", "alpha:p1", "blocked", middle],
		["control-b", "alpha:p3", "blocked", newest],
	]
	for change: Array in order:
		var key: String = change[3]
		var state: String = change[2]
		_ctl(str(change[0]), "status", {"pane_id": str(change[1]), "agent_status": state})
		await _until(
			func() -> bool:
				var pane := office.frame.pane(key)
				return pane != null and pane.state == state and pane.state_since >= 0.0,
			"%s is %s, its start seen" % [key, state]
		)
		await _wait(0.05)
	var starts: Array[float] = []
	for key: String in [done, oldest, middle, newest]:
		starts.append(office.frame.pane(key).state_since)
	_check(
		starts[0] < starts[1] and starts[1] < starts[2] and starts[2] < starts[3],
		"the done one waited longest, then the blocked oldest first: %s" % [starts]
	)
	var card := _card(office)
	await _pick_bee(office, "alpha:p3", false)
	_eq(office.picked_key, newest, "a real click picks the newest blocked")
	await _until(
		func() -> bool: return card.next_text().begins_with(_answer_line(office, oldest)),
		"NEXT names the longest-waiting blocked: " + card.next_text()
	)
	var walked := PackedStringArray()
	for press in 4:
		var before := office.picked_key
		await _tap(KEY_N)
		await _until(func() -> bool: return office.picked_key != before, "N %d picks another" % press)
		var picked := office.picked_key
		walked.append(picked)
		_check(picked != done, "N %d never picks the done one" % press)
		_check(not office.hud.card_compact(), "N %d opens the panel" % press)
		await _until(card.answering, "N %d: answer mode, once the question shows" % press)
		var named := office.navigator.peek_next(office.frame)
		_check(named != done, "N %d: NEXT names a blocked one, not the done one" % press)
		await _until(
			func() -> bool: return card.next_text().begins_with(_answer_line(office, named)),
			"N %d: NEXT says %s: %s" % [press, _answer_line(office, named), card.next_text()]
		)
	_eq(walked, PackedStringArray([oldest, middle, newest, oldest]), "the blocked, oldest first, and round")
	_eq(_all_inputs(), 0, "nothing was sent")
	for which: String in ["control-a", "control-b"]:
		for entry in _sequence(which):
			_check(entry.begins_with("pane.read ") and not entry.ends_with(" check"), "only previews: " + entry)


## `‹ ›` on the one line walk NEXT's queue both ways, selection
## only: each real click picks whom peek_prev() / peek_next() named, the panel
## stays one line (an open one folds: the card is aimed elsewhere) and nothing
## opens answer mode; nothing is read or sent past the read-only three. With
## nobody waiting both are off.
func test_the_step_buttons_walk_the_queue_both_ways_and_send_nothing() -> void:
	_fakes()
	_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "done"})})
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	var office := await _office_with()
	await _frames(3)
	var card := _card(office)
	var back: Button = card.get_node("%StepBack")
	var on: Button = card.get_node("%StepOn")
	var before_a := _sequence("control-a")
	var before_b := _sequence("control-b")
	_check(back.is_visible_in_tree() and on.is_visible_in_tree(), "both on the one line")
	_check(not back.disabled and not on.disabled, "and on")
	var picks := PackedStringArray()
	for direction: int in [1, 1, -1, -1, -1]:
		var named := (
			office.navigator.peek_next(office.frame) if direction > 0 else office.navigator.peek_prev(office.frame)
		)
		await _click_control(on if direction > 0 else back)
		await _until(func() -> bool: return office.picked_key == named, "a step picks %s" % named)
		await _frames(2)
		_check(office.hud.card_compact(), "the panel stays one line after %s" % named)
		_check(not card.answering(), "no answer mode for %s" % named)
		picks.append(named)
	_eq(picks[2], picks[0], "back once from the second is the first")
	# `‹ ›` are the line's: the open panel has NEXT for the way on.
	var open: Control = card.get_node("%CompactOpen")
	await _click_control(open)
	await _frames(2)
	_check(not office.hud.card_compact(), "`Open` opens the panel")
	_check(not on.is_visible_in_tree() and not back.is_visible_in_tree(), "the open panel shows no `‹ ›`")
	var fold: Control = card.get_node("%FoldButton")
	await _click_control(fold)
	await _frames(2)
	_check(office.hud.card_compact() and on.is_visible_in_tree(), "`▾ Esc` folds it: `‹ ›` are back")
	_eq(_all_inputs(), 0, "nothing was sent")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "and no switch")
	for which: String in ["control-a", "control-b"]:
		var sequence := _sequence(which).slice((before_a if which == "control-a" else before_b).size())
		for entry in sequence:
			_check(entry.begins_with("pane.read ") and not entry.ends_with(" check"), "only previews: " + entry)
	for which: String in ["control-a", "control-b"]:
		for pane_id: String in ["alpha:p3", "bravo:p1"]:
			_ctl(which, "status", {"pane_id": pane_id, "agent_status": "working"})
	await _until(func() -> bool: return on.disabled and back.disabled, "nobody waiting: both off")
	_eq(_all_inputs(), 0, "still nothing sent")


## Blocked comes first: a start that asks at once is a blocked agent to the
## chips too. bee's alpha:p3 blocks while herdr still launches it: the
## reader reads it (the card's own payload, nothing else asked of bee), the
## hover over its chip shows the question, and a click on BLOCKED picks it
## and opens answer mode once the question is shown, the keys being open to a
## blocked start. Nothing is sent.
func test_the_reader_reads_a_blocked_agent_still_launching() -> void:
	_fakes()
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "working"})
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	var asking := _changed(quiet, "alpha:p3", {"agent_status": "blocked", "launch_pending": true})
	_ctl("control-b", "set_snapshot", {"snapshot": asking})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _minimized_office()
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	await _until(
		func() -> bool: return office.frame.pane(key) != null and office.frame.pane(key).starting, "still launching"
	)
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	var at := await _bubble_point(office, key)
	_check(_station_of(office, key).chip().visible, "its seat shows a bubble")
	office.pacer.note_minimized(false)
	await _until(func() -> bool: return _read_panes("control-b").has("alpha:p3"), "the reader reads it")
	_eq(_sequence("control-b"), PackedStringArray(["pane.read detection 200"]), "the card's own payload, nothing else")
	await _until(func() -> bool: return _question_of(office, key) == "Do you want to proceed?", "the asking line kept")
	await _move_pointer(at)
	_check(office.hud.world_tip_shown(), "the hover over its bubble shows")
	_eq(office.hud.world_tip_text(), "Do you want to proceed?", "the question it read")
	await _move_pointer(at + Vector2(0, 60))
	var card := _card(office)
	await _click_control(office.hud.bar.counter(&"blocked"))
	_eq(office.picked_key, key, "BLOCKED picks it")
	await _until(func() -> bool: return card.preview_text() == QUESTION, "the question is shown")
	await _until(card.answering, "then answer mode opens")
	_eq(_all_inputs(), 0, "nothing was sent")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "and no switch")


## The strategic view (`S`) covers the world, and the chips' reader
## stops at once, as under the monitor and the OVERVIEW: bee's two blocked
## chips stand on screen under it and nothing is read for two seconds; once
## `S` closes it, the longest-waiting is read. That read's reply is held back
## until the case has looked: the reader reads one pane at a time, so nothing
## else is out meanwhile; answered at once, the next watch would read the
## other pane before the look. Nothing is written either way.
func test_the_strategic_view_stops_the_question_reads() -> void:
	_blocked_pair()
	# Minimized until the view is open, so no read begins before it.
	var office := await _minimized_office()
	await _zone_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	await _bee_bubbles_on_screen(office)
	await _tap(KEY_S)
	_check(office.hud.strategic_open(), "S opens the strategic view")
	office.pacer.note_minimized(false)
	await _wait(2.0)
	_eq(_read_panes("control-b"), [], "under the strategic view: nothing read")
	for pane_id: String in ["alpha:p1", "alpha:p3"]:
		var bubble := _station_of(office, HerdrFleet.pane_key(BEE, pane_id)).chip_rect()
		bubble.position -= office.camera.position
		_check(office.hud.world_rect().encloses(bubble), "%s's bubble is still on screen under it" % pane_id)
	_ctl("control-b", "next", {"action": "hold", "method": "pane.read"})
	await _tap(KEY_S)
	_check(not office.hud.strategic_open(), "S closes it")
	await _until(func() -> bool: return _number(_ctl("control-b", "stats"), "held_replies") == 1, "a read is held")
	_eq(_read_panes("control-b"), ["alpha:p1"], "the longest-waiting is read once the view is gone")
	_eq(_sequence("control-b"), PackedStringArray(["pane.read detection 200"]), "the chip's read, nothing else")
	_check(office.questions.reading(), "and it is the one read out")
	_ctl("control-b", "release_held")
	var key := HerdrFleet.pane_key(BEE, "alpha:p1")
	await _until(func() -> bool: return _question_of(office, key) == "Do you want to proceed?", "its reply is kept")
	_eq(_all_inputs(), 0, "nothing written")
	_eq(office.fleet.write_log().size(), 0, "and the audit has no write")


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation but one a case provoked on purpose.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)
