extends "res://tools/command_test_base.gd"
## NEW PANE BESIDE on the agent card: a click splits the picked agent's
## pane with `pane.split`, and the office then picks the new pane, a selection
## only, whose card offers START AGENT, a second gesture of its own. Every gate
## of the write boundary, by real input: the exact params, the side the shape
## gives, too small or no size refused, a lost answer unknown and never
## resent, the look owed, a machine that drops or is replaced between press
## and release, answer mode, the keyboard, no gesture and `--read-only`. An
## operator office against two fake herdrs of this suite's own (Local on A,
## bee on B, whose pane ids collide). Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_split.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Every case first resets both fakes and opens only what it needs (_fakes()),
## and asserts the exact requests each fake received. The last case sums up
## both fakes: nothing reached them that no case opened.

## Local's codex, idle in snapshot_basic, 80x40 cells: the agent split here.
var p3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3")
## The pane a first split of alpha:p3 makes on the fake (its next id there).
var p4 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p4")


func _marker() -> String:
	return "SPLIT TESTS"


## Picked, the idle codex's card offers NEW PANE BESIDE CODEX with one button,
## `New pane →` for its 80x40 shape, and no kind. A click sends one split with
## exactly herdr's target id, the side and `focus: false`, and nothing else;
## herdr's own focus stays on alpha:p1. Within two seconds the office picks
## the new pane, a shell on an empty seat, and its card offers START AGENT with
## every kind Local shows; nothing is sent to it. Back on alpha:p3, the footer
## names the new pane while its look is owed.
func test_new_pane_splits_beside_the_agent_with_no_focus_and_picks_it() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	var split := _split_button(office)
	_eq(_title(office), "NEW PANE BESIDE CODEX", "the block's title names the agent")
	_eq(split.text, "New pane →", "one button, to the right for an 80x40 pane")
	_eq(_note(office), "Splits a new pane next to alpha:p3", "the note")
	_eq(_kinds_shown(office), [], "no kind: an agent's card starts nothing")
	_check("focus stays" in split.tooltip_text, "the tooltip says herdr's focus stays: " + split.tooltip_text)
	_check(not "pane.split" in split.tooltip_text, "and never names the method")
	var clicked := Time.get_ticks_msec()
	await _click_control(split)
	await _until(func() -> bool: return office.picked_key == p4, "the office picks the new pane")
	_check(Time.get_ticks_msec() - clicked < 2000, "within two seconds of the click")
	_eq(_writes_seen("control-a"), PackedStringArray(["pane.split right alpha:p3"]), "one split, no re-read")
	_eq(_asked("control-a", "pane.split"), [{"target_pane_id": "alpha:p3", "direction": "right", "focus": false}], "")
	_eq(_dict(_ctl("control-a", "stats"), "snapshot").get("focused_pane_id"), "alpha:p1", "herdr's focus stays")
	await _until(func() -> bool: return _title(office) == "START AGENT", "the new pane's card: START AGENT")
	_eq(_kinds_shown(office), ["CLAUDE", "CODEX", "PI"], "every kind Local shows")
	await _until(func() -> bool: return card.preview_text() == "$ \n", "its prompt is shown")
	_check(_station_of(office, p4).actor() == null, "the new pane is an empty seat")
	await _wait(1.5)
	_eq(_count("control-a", "agent.start"), 0, "the pick started nothing")
	_eq(_writes_seen("control-a"), PackedStringArray(["pane.split right alpha:p3"]), "and wrote nothing more")
	await _pick_local(office, "alpha:p3")
	await _until(
		func() -> bool: return card.outcome_text() == "New pane alpha:p4", "back on alpha:p3: the new pane named"
	)
	_eq(_writes_seen("control-b"), PackedStringArray(), "bee heard nothing")


## The side follows the pane's shape, and a pane the shape gives no side is
## refused on the card with the reason in the tooltip: 30x10 too small, no
## layout slot no size. A click on the off button sends nothing. Given room
## again, an 80x80 pane splits down.
func test_the_direction_follows_the_shape_and_small_panes_refuse() -> void:
	_fakes("snapshot_basic", ["pane.read", "pane.split"])
	_ctl("control-a", "set_snapshot", {"snapshot": _sized(_raw(), "alpha:p3", 30, 10)})
	var office := await _office_with()
	await _pick_local(office, "alpha:p3")
	var split := _split_button(office)
	await _until(split.is_visible_in_tree, "the split button")
	await _frames(3)
	_check(split.disabled, "30x10: off")
	_check(
		"less than 40 columns or 10 rows" in split.tooltip_text, "too small, says the tooltip: " + split.tooltip_text
	)
	await _click_control(split)
	await _frames(5)
	_eq(_count("control-a", "pane.split"), 0, "a click on it sends nothing")
	_ctl("control-a", "set_snapshot", {"snapshot": _sized(_raw(), "alpha:p3", -1, 0)})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return "no size" in split.tooltip_text, "no layout slot: size unknown")
	_check(split.disabled, "and off")
	await _click_control(split)
	await _frames(5)
	_eq(_count("control-a", "pane.split"), 0, "a click on it sends nothing")
	_ctl("control-a", "set_snapshot", {"snapshot": _sized(_raw(), "alpha:p3", 80, 80)})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return split.text == "New pane ↓" and not split.disabled, "80x80: down")
	await _click_control(split)
	await _until(func() -> bool: return _count("control-a", "pane.split") == 1, "the split")
	_eq(_writes_seen("control-a"), PackedStringArray(["pane.split down alpha:p3"]), "down, and only that")


## A split herdr carried out but whose answer was lost is an unknown result:
## the footer says look first, the button is off until the preview has read
## the pane again, and the office does not pick the new pane it cannot name,
## though a snapshot shows it. Nothing is split again.
func test_a_lost_split_answer_is_unknown_and_nothing_follows() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	var split := _split_button(office)
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "pane.split"})
	await _click_control(split)
	await _until(func() -> bool: return card.outcome_text() == "Unknown result: look first", "an unknown result")
	_check(split.disabled, "the split waits")
	_check("look" in split.tooltip_text, "for a look: " + split.tooltip_text)
	_eq(_list(_ctl("control-a", "stats"), "splits").size(), 1, "herdr made the pane")
	await _until(func() -> bool: return office.frame.pane(p4) != null, "a snapshot shows it")
	await _wait(1.0)
	_eq(office.picked_key, p3, "not picked: the office never learned its id")
	await _until(func() -> bool: return not split.disabled, "looked at: the split is offered again")
	await _wait(1.0)
	_eq(_count("control-a", "pane.split"), 1, "never split again")


## A split aimed at the press is not sent when, by the release, the card is
## on another pane (`N` picked the next agent while the button was held: the
## same button, now another agent's), nor when the machine dropped (the block
## goes with the connection). A connection back without a current snapshot
## offers no split; once current again, one click splits, once.
func test_a_split_refuses_when_the_pick_or_machine_changes_before_the_release() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	var split := _split_button(office)
	var launch := _control(office, "Launch")
	_half_click(split, true)
	await _frames(2)
	await _tap(KEY_N)
	await _until(func() -> bool: return office.picked_key != p3, "N picks the next agent")
	# N opens the next one's panel, and a blocked one's answer mode
	# once its question shows: Escape leaves that, and the panel shows the split.
	await _until(func() -> bool: return card.answering() or split.is_visible_in_tree(), "its panel open")
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(func() -> bool: return split.is_visible_in_tree(), "whose card offers a split too")
	_half_click(split, false)
	await _frames(3)
	_eq(card.outcome_text(), "Not sent: target changed", "released on another pane: not sent")
	_eq(_count("control-a", "pane.split") + _count("control-b", "pane.split"), 0, "nothing split")
	var generation := office.fleet.generation(HerdrFleet.LOCAL)
	_ctl("control-a", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(HerdrFleet.LOCAL), "Local drops")
	_ctl("control-a", "hold_ack", {"hold": true})
	_ctl("control-a", "appear")
	var asked := func(stats: Dictionary) -> bool: return _count_in(stats, "events.subscribe") > 1
	await _until_stats("control-a", asked, "Local asks to subscribe again")
	await _pick_local(office, "alpha:p3")
	await _wait(1.0)
	_check(not office.fleet.snapshot_is_current(HerdrFleet.LOCAL), "back, not current yet")
	_check(not launch.is_visible_in_tree(), "no split offered without a current snapshot")
	_ctl("control-a", "release")
	await _until(func() -> bool: return office.fleet.generation(HerdrFleet.LOCAL) > generation, "a new connection")
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "current: offered again")
	await _settled(card)
	await _click_control(split)
	await _until(func() -> bool: return _count("control-a", "pane.split") == 1, "one click splits")
	await _until(func() -> bool: return office.picked_key == p4, "the new pane picked")
	await _pick_local(office, "alpha:p3")
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "looked at: offered")
	_half_click(split, true)
	await _frames(2)
	_ctl("control-a", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(HerdrFleet.LOCAL), "Local drops again")
	await _until(func() -> bool: return not launch.is_visible_in_tree(), "the block goes with it")
	_half_click(split, false)
	await _frames(5)
	_eq(_writes_seen("control-a"), PackedStringArray(["pane.split right alpha:p3"]), "dropped: nothing more sent")
	_eq(_writes_seen("control-b"), PackedStringArray(), "and bee heard nothing")


## The block is not there in answer mode and back after it; no key splits, in
## answer mode or out of it, nor after a press on the button released off it
## (the button never takes the keyboard's focus); and with no gesture at all,
## status changes, events, a resize and three seconds, nothing is written.
func test_the_new_pane_block_hides_in_answer_mode_and_never_from_the_keyboard() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	var launch := _control(office, "Launch")
	await _tap(KEY_ENTER)
	await _until(card.answering, "answer mode")
	_check(not launch.is_visible_in_tree(), "answer mode: no block")
	for code: Key in [KEY_1, KEY_2, KEY_9, KEY_Y, KEY_SPACE, KEY_TAB, KEY_RIGHT, KEY_DOWN]:
		await _tap(code)
	await _tap(KEY_ESCAPE)
	await _until(func() -> bool: return not card.answering(), "left")
	await _until(launch.is_visible_in_tree, "the block is back")
	for code: Key in [KEY_SPACE, KEY_TAB, KEY_RIGHT, KEY_DOWN, KEY_1, KEY_Y]:
		await _tap(code)
	var split := _split_button(office)
	_half_click(split, true)
	await _frames(2)
	var off := split.get_global_rect().get_center() + Vector2(0, -200)
	await _move_pointer(off, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = off
	release.global_position = off
	root.push_input(release, true)
	await _frames(3)
	_check(not split.has_focus(), "a press released off the button leaves it no focus")
	for code: Key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		await _tap(code)
	if card.answering():
		await _tap(KEY_ESCAPE)
	for state: String in ["working", "idle", "done", "idle"]:
		_ctl("control-a", "status", {"pane_id": "alpha:p3", "agent_status": state, "agent": "codex"})
		await _wait(0.3)
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	root.size = Vector2i(900, 520)
	await _wait(3.0)
	root.size = SCREEN
	await _frames(3)
	_eq(_count("control-a", "pane.split"), 0, "no split")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written at all")


## Split, then start: two gestures. The picked new pane's kinds stay off while
## its preview shows no whole output, and nothing starts by itself; once it
## reads a prompt, a click on CLAUDE starts it there, one request. A second
## split and start on a pane herdr finds busy: herdr refuses the start, the
## split stands, and each went once per click.
func test_split_then_start_are_two_gestures_and_the_second_can_still_be_refused() -> void:
	var office := await _agent_card(["pane.read", "pane.split", "agent.start"], "")
	var card := _card(office)
	await _click_control(_split_button(office))
	await _until(func() -> bool: return office.picked_key == p4, "the new pane picked")
	await _until(func() -> bool: return _title(office) == "START AGENT", "START AGENT")
	await _wait(1.0)
	_eq(_kinds_enabled(office), [], "no whole output shown: every kind off")
	_eq(_count("control-a", "agent.start"), 0, "nothing starts by itself")
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p4", "source": "recent_unwrapped", "text": "$ \n"})
	await _until(func() -> bool: return card.preview_text() == "$ \n", "the prompt read")
	await _until(func() -> bool: return "CLAUDE" in _kinds_enabled(office), "CLAUDE may be pressed")
	var named := office.fleet.next_agent_name(HerdrFleet.LOCAL, "claude")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start went")
	_eq(
		_asked("control-a", "agent.start"),
		[{"name": named, "kind": "claude", "pane_id": "alpha:p4"}],
		"to the new pane"
	)
	var p5 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p5")
	_ctl("control-a", "set_busy", {"pane_id": "alpha:p5"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p5", "source": "recent_unwrapped", "text": "$ \n"})
	await _pick_local(office, "alpha:p3")
	var split := _split_button(office)
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "alpha:p3 may split again")
	await _click_control(split)
	await _until(func() -> bool: return office.picked_key == p5, "the second new pane picked")
	await _until(func() -> bool: return "CLAUDE" in _kinds_enabled(office), "CLAUDE may be pressed there")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return card.outcome_text() == "herdr refused: pane busy", "herdr refuses the start")
	_eq([_count("control-a", "pane.split"), _count("control-a", "agent.start")], [2, 2], "two splits, two starts")
	_eq(office.fleet.snapshot(HerdrFleet.LOCAL).panes.size(), 6, "the panes split stay")


## A split herdr answered but no snapshot shows in time: the office stops
## waiting and the footer says the new pane was not seen; when a snapshot
## shows it later, it is not picked. Nothing is split again.
func test_the_footer_says_so_when_the_new_pane_never_shows() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	office.pending_pick_msec = 1500
	var card := _card(office)
	var connection := office.fleet.generation(HerdrFleet.LOCAL)
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "hold_snapshot", "method": "session.snapshot"})
	await _click_control(_split_button(office))
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p4", "herdr made alpha:p4")
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p4 not seen yet", "not seen in time")
	var outcome: Label = card.get_node("%Outcome")
	_check("did not pick it" in outcome.tooltip_text, "the tooltip says it was not picked: " + outcome.tooltip_text)
	_eq(office.fleet.generation(HerdrFleet.LOCAL), connection, "given up on the same connection, not dropped")
	_ctl("control-a", "release_snapshots")
	await _until(func() -> bool: return office.frame.pane(p4) != null, "a snapshot shows it later")
	await _wait(1.0)
	_eq(office.picked_key, p3, "not picked then")
	_eq(_count("control-a", "pane.split"), 1, "never split again")


## The office picks the new pane only while the viewer's pick is still the
## pane split, on the same connection: a desk picked meanwhile, or Local
## replaced before any snapshot showed the new pane, and it is not picked when
## it shows. Nothing is split again.
func test_the_new_pane_is_not_picked_after_another_pick_or_a_new_connection() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var connection := office.fleet.generation(HerdrFleet.LOCAL)
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 2.5})
	await _click_control(_split_button(office))
	await _until(func() -> bool: return _card(office).outcome_text() == "New pane alpha:p4", "herdr made alpha:p4")
	await _pick_local(office, "alpha:p1")
	_check(office.frame.pane(p4) == null, "picked before any snapshot showed the new pane")
	await _until(func() -> bool: return office.frame.pane(p4) != null, "a snapshot shows the new pane")
	await _wait(1.0)
	_eq(office.picked_key, HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1"), "the viewer's own pick stays")
	_eq(office.fleet.generation(HerdrFleet.LOCAL), connection, "on the same connection")
	await _pick_local(office, "alpha:p3")
	var split := _split_button(office)
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "alpha:p3 may split again")
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "hold_snapshot", "method": "session.snapshot"})
	await _click_control(split)
	await _until(func() -> bool: return _card(office).outcome_text() == "New pane alpha:p5", "herdr made alpha:p5")
	var generation := office.fleet.generation(HerdrFleet.LOCAL)
	_ctl("control-a", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(HerdrFleet.LOCAL), "Local drops")
	_ctl("control-a", "appear")
	await _until(func() -> bool: return office.fleet.generation(HerdrFleet.LOCAL) > generation, "a new connection")
	var p5 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p5")
	await _until(func() -> bool: return office.frame.pane(p5) != null, "its snapshot shows alpha:p5")
	await _wait(1.0)
	_eq(office.picked_key, p3, "not picked on another connection")
	_eq(_count("control-a", "pane.split"), 2, "one split per click")


## The office leaves the viewer where they went while the new pane was on
## its way: another zone (by a real click on the minimap: a pan on the same map
## now, where it was another floor), or answer mode on the pane split. When the
## new pane shows it is not picked, the zone and the answer mode stay, and the
## footer names the new pane and says it was not picked. Nothing is split again.
func test_the_new_pane_is_not_picked_after_the_viewer_moved_floor_or_into_answer_mode() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	var bravo := HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo")
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 2.5})
	await _click_control(_split_button(office))
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p4", "herdr made alpha:p4")
	await _zone_pick(office, bravo)
	var zone := func() -> String: return office.navigator.current_zone(office.frame)
	await _until(func() -> bool: return zone.call() == bravo, "the viewer went to bravo")
	_check(office.frame.pane(p4) == null, "before any snapshot showed the new pane")
	await _until(func() -> bool: return office.frame.pane(p4) != null, "a snapshot shows the new pane")
	await _wait(1.0)
	_eq([office.picked_key, zone.call()], [p3, bravo], "not picked: the pick and the zone stay")
	_eq(card.outcome_text(), "New pane alpha:p4: not picked", "the footer says so")
	await _pick_local(office, "alpha:p3")
	var split := _split_button(office)
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "alpha:p3 may split again")
	await _until(card.answer_offered, "and be answered")
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 3.5})
	await _click_control(split)
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p5", "herdr made alpha:p5")
	await _until(card.answer_offered, "looked at: it may be answered again")
	await _tap(KEY_ENTER)
	await _until(card.answering, "the viewer answers alpha:p3")
	var p5 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p5")
	await _until(func() -> bool: return office.frame.pane(p5) != null, "a snapshot shows alpha:p5")
	await _wait(1.0)
	_check(card.answering(), "answer mode stays")
	_eq(office.picked_key, p3, "alpha:p5 not picked")
	_eq(_count("control-a", "pane.split"), 2, "one split per click")


## The viewer moving to another zone of the same map while a split's new pane
## is on its way is moving on (codex #5): a real click on bravo's FLOORS row,
## which only pans (the same map, the same world), and the new pane is not
## picked when a snapshot shows it; the footer says so; one split was sent.
## And moving away and back before it shows (PageDown then PageUp, alpha
## current again) is moving on too: the navigations count, not where the view
## ends up (before one map per machine, coming back to the same floor picked it).
func test_the_new_pane_is_not_picked_after_the_viewer_moved_to_another_zone() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	var bravo := HerdrFleet.pane_key(HerdrFleet.LOCAL, "bravo")
	var zone := func() -> String: return office.navigator.current_zone(office.frame)
	var world := office.world.get_instance_id()
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 2.5})
	await _click_control(_split_button(office))
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p4", "herdr made alpha:p4")
	await _zone_pick(office, bravo)
	_eq([office.navigator.shown_key, zone.call()], [HerdrFleet.LOCAL, bravo], "a pan to bravo, on Local's map")
	_eq(office.world.get_instance_id(), world, "the same world")
	_check(office.frame.pane(p4) == null, "before any snapshot showed the new pane")
	await _until(func() -> bool: return office.frame.pane(p4) != null, "a snapshot shows the new pane")
	await _wait(1.0)
	_eq([office.picked_key, zone.call()], [p3, bravo], "not picked: the pick and the zone stay")
	_eq(card.outcome_text(), "New pane alpha:p4: not picked", "the footer says so")
	_eq(_count("control-a", "pane.split"), 1, "one split sent")
	await _pick_local(office, "alpha:p3")
	var split := _split_button(office)
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "alpha:p3 may split again")
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 2.5})
	await _click_control(split)
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p5", "herdr made alpha:p5")
	var alpha: String = zone.call()
	# The rail is ascending: PageDown leaves alpha (1) for bravo, PageUp comes back.
	await _navigate_key(office, KEY_PAGEDOWN)
	var away: String = zone.call()
	_check(away != alpha, "PageDown: away from alpha")
	await _navigate_key(office, KEY_PAGEUP)
	_eq(zone.call(), alpha, "away and back: alpha current again")
	var p5 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p5")
	await _until(func() -> bool: return office.frame.pane(p5) != null, "a snapshot shows alpha:p5")
	await _wait(1.0)
	_eq(office.picked_key, p3, "not picked: the viewer navigated meanwhile")
	_eq(card.outcome_text(), "New pane alpha:p5: not picked", "and the footer says so")
	_eq(_count("control-a", "pane.split"), 2, "one split per click")


## When the new pane shows with another terminal than the one herdr named in
## its answer, it is not picked, and the footer says why.
func test_a_new_pane_with_another_terminal_is_not_picked_and_the_footer_says_so() -> void:
	var office := await _agent_card(["pane.read", "pane.split"])
	var card := _card(office)
	await _after_a_poll("control-a")
	_ctl("control-a", "next", {"action": "delay", "method": "session.snapshot", "seconds": 2.0})
	await _click_control(_split_button(office))
	await _until(func() -> bool: return card.outcome_text() == "New pane alpha:p4", "herdr made alpha:p4")
	var now := _dict(_ctl("control-a", "stats"), "snapshot")
	_ctl("control-a", "set_snapshot", {"snapshot": _changed(now, "alpha:p4", {"terminal_id": "term-someone-else"})})
	await _until(func() -> bool: return office.frame.pane(p4) != null, "a snapshot shows alpha:p4")
	await _wait(1.0)
	_eq(office.picked_key, p3, "not picked")
	_eq(card.outcome_text(), "New pane alpha:p4: another terminal, not picked", "the footer says why")
	var outcome: Label = card.get_node("%Outcome")
	_check("another terminal" in outcome.tooltip_text, "and the tooltip: " + outcome.tooltip_text)
	_eq(_count("control-a", "pane.split"), 1, "never split again")


## The block fits and says all of itself: at 480x320, opened on a working
## agent (Enter opens the card up; a working agent takes no answer), and at
## 800x480, the title NEW PANE BESIDE CLAUDE whole in at most two lines, the
## button's label whole, the note in two lines, all inside the block beside
## the preview. At 800x480 PANE's details stay beside it.
func test_the_new_pane_block_fits_and_shows_its_whole_title() -> void:
	_fakes("snapshot_basic", ["pane.read"])
	var office := await _office_with(false, true, true, Vector2(480, 320))
	var card := _card(office)
	var launch := _control(office, "Launch")
	await _pick_local(office, "alpha:p1", false)
	_check(office.hud.card_compact() and not launch.is_visible_in_tree(), "a compact line, no block")
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return not office.hud.card_compact(), "Enter opens the working agent's card")
	_check(not card.answering(), "a working agent: no answer mode")
	var split := _split_button(office)
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "New pane offered")
	await _frames(3)
	_block_whole(card, "480x320")
	await _tap(KEY_ESCAPE)
	await _until(office.hud.card_compact, "Esc folds it")
	office.test_screen = Vector2(800, 480)
	office.refresh()
	await _frames(2)
	_check(office.hud.card_compact(), "800x480: still one line")
	await _open_panel(office)
	await _until(launch.is_visible_in_tree, "800x480: the block")
	await _frames(3)
	_block_whole(card, "800x480")
	_check(_control(office, "More").is_visible_in_tree(), "800x480: PANE's details beside it")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## NEW PANE BESIDE and Switch herdr here stay reachable for a blocked agent at
## the minimum: at 480x320, out of answer mode by Escape, the panel stays open
## and offers both, and a real click on the split sends one split with herdr's
## target id and `focus: false`. Escape itself sent nothing.
func test_new_pane_beside_is_reachable_for_a_blocked_agent_after_escape() -> void:
	var office := await _blocked_bee(QUESTION, Vector2(480, 320))
	var card := _card(office)
	await _open_answer(office)
	var split := _split_button(office)
	_check(not split.is_visible_in_tree(), "answer mode hides the block")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(not card.answering(), "Escape leaves answer mode")
	_check(not office.hud.card_compact(), "and the panel stays open")
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "New pane offered")
	_eq(_title(office), "NEW PANE BESIDE CODEX", "for the blocked agent")
	_check(_switch(office).is_visible_in_tree(), "and Switch herdr here beside it")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing sent so far")
	await _click_control(split)
	await _until(func() -> bool: return _count("control-b", "pane.split") == 1, "the split went")
	_eq(_asked("control-b", "pane.split").size(), 1, "once")
	var asked: Dictionary = _asked("control-b", "pane.split")[0]
	_eq([asked.get("target_pane_id"), asked.get("focus")], ["alpha:p3", false], "to alpha:p3, herdr's focus left alone")
	_eq(_all_inputs(), 0, "and no key")


## A `--read-only` office offers no new pane, and a click where the button
## would be, Enter and the digits ask nothing but the read-only three.
func test_read_only_offers_no_new_pane() -> void:
	_fakes("snapshot_basic", [])
	var office := await _office_with(true)
	await _pick_local(office, "alpha:p3")
	await _frames(10)
	_check(not _control(office, "Launch").is_visible_in_tree(), "no block")
	_check(not _split_button(office).is_visible_in_tree(), "no split button")
	await _tap(KEY_ENTER)
	await _tap(KEY_1)
	await _frames(3)
	for which: String in ["control-a", "control-b"]:
		_eq(_sequence(which), PackedStringArray(), "%s: nothing beyond the read-only three" % which)


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)


# --- helpers only these cases use ------------------------------------------------


## Local's idle codex (alpha:p3) picked with a real click and its NEW PANE
## BESIDE button offered: both fakes reset with `methods` open, the new pane a
## split makes scripted to show `new_recent` (an empty prompt by default).
func _agent_card(methods: Array, new_recent := "$ \n") -> OfficeDouble:
	_fakes("snapshot_basic", methods)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "done.\n$ \n"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p4", "source": "recent_unwrapped", "text": new_recent})
	var office := await _office_with()
	await _pick_local(office, "alpha:p3")
	var split := _split_button(office)
	await _until(func() -> bool: return split.is_visible_in_tree() and not split.disabled, "New pane offered")
	return office


func _split_button(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%SplitButton")


func _title(office: OfficeDouble) -> String:
	return (_control(office, "LaunchTitle") as Label).text


func _note(office: OfficeDouble) -> String:
	return (_control(office, "LaunchNote") as Label).text


## The card's kind button `index` (`%Kind0` …).
func _kind(office: OfficeDouble, index: int) -> Button:
	return office.hud.inspector.get_node("%%Kind%d" % index)


## The labels of the kind buttons shown, in order.
func _kinds_shown(office: OfficeDouble) -> Array:
	var shown: Array = []
	for index in OfficePaneInspector.KINDS_MAX:
		if _kind(office, index).is_visible_in_tree():
			shown.append(_kind(office, index).text)
	return shown


## The labels of the kind buttons shown and on.
func _kinds_enabled(office: OfficeDouble) -> Array:
	var shown: Array = []
	for index in OfficePaneInspector.KINDS_MAX:
		var kind := _kind(office, index)
		if kind.is_visible_in_tree() and not kind.disabled:
			shown.append(kind.text)
	return shown


## Right after fake `which` answered a snapshot poll: the next is
## HerdrClient.SNAPSHOT_INTERVAL away, so the next snapshot it is asked for
## is the one an event asks for.
func _after_a_poll(which: String) -> void:
	var before := _count(which, "session.snapshot")
	await _until(func() -> bool: return _count(which, "session.snapshot") > before, "a snapshot poll")
	await _frames(2)


## Until the card has kept one binding for a second: a connection coming
## back binds it again (its generation), and a press aimed before that is
## dropped at its release, as it should be.
func _settled(card: OfficePaneInspector) -> void:
	var binding := -1
	while binding != card.binding():
		binding = card.binding()
		await _wait(1.0)


## How many `method` requests `stats` (a fake's) records since its reset.
func _count_in(stats: Dictionary, method: String) -> int:
	return _list(stats, "methods").count(method)


## The launch block on `card` inside the panel and beside the preview, its
## title NEW PANE BESIDE CLAUDE whole in at most two lines, the split button's
## label whole, the note in at most two lines.
func _block_whole(card: OfficePaneInspector, what: String) -> void:
	var bounds := (card.get_node("Frame/Row") as Control).get_global_rect().grow(0.5)
	var block := (card.get_node("%Launch") as Control).get_global_rect()
	_check(bounds.encloses(block), "%s: the block %s inside the panel %s" % [what, block, bounds])
	var preview: Control = card.get_node("%Preview")
	_check(not preview.get_global_rect().intersects(block), "%s: beside the preview" % what)
	var title: Label = card.get_node("%LaunchTitle")
	_eq(title.text, "NEW PANE BESIDE CLAUDE", "%s: the title" % what)
	var lines := title.get_line_count()
	var whole := lines <= 2 and title.get_visible_line_count() >= lines
	if title.autowrap_mode == TextServer.AUTOWRAP_OFF:
		var size := title.get_theme_font_size("font_size")
		whole = whole and title.get_theme_font("font").get_string_size(title.text, 0, -1, size).x <= title.size.x
	_check(whole, "%s: the whole title shows (%d lines, %.0f wide)" % [what, lines, title.size.x])
	var button: Button = card.get_node("%SplitButton")
	var font_size := button.get_theme_font_size("font_size")
	var needed := button.get_theme_font("font").get_string_size(button.text, 0, -1, font_size).x
	needed += button.get_theme_stylebox("normal").get_minimum_size().x
	_check(button.size.x >= needed - 0.5, "%s: `%s` whole (%.0f of %.0f)" % [what, button.text, button.size.x, needed])
	_check(block.grow(0.5).encloses(button.get_global_rect()), "%s: the button inside the block" % what)
	var note: Label = card.get_node("%LaunchNote")
	_check(note.get_line_count() <= 2, "%s: the note in two lines: %d" % [what, note.get_line_count()])


## `raw` with pane `pane_id`'s layout slot `width` x `height` cells; a
## negative width takes the slot out of the layout.
func _sized(raw: Dictionary, pane_id: String, width: int, height: int) -> Dictionary:
	var result := raw.duplicate(true)
	for layout: Dictionary in _list(result, "layouts"):
		var kept: Array = []
		for slot: Dictionary in _list(layout, "panes"):
			if slot.get("pane_id") == pane_id:
				if width < 0:
					continue
				var rect := _dict(slot, "rect")
				rect["width"] = width
				rect["height"] = height
			kept.append(slot)
		layout["panes"] = kept
	return result
