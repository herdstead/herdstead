extends "res://tools/command_test_base.gd"
## How a start that is over is said across cards of its pane (the footer's
## launch line, CardActions.launch_line()): the card that first sees a start
## over (the agent came up, another terminal took the pane) says so and keeps
## saying so; a later card of the same pane (the viewer left and came back)
## says it only while the look the start's write owes is still owed; and a
## pane that goes has no card at all, so nothing is said of its start until
## its id comes back. By real input, on an operator office against two fake
## herdrs of this suite's own (Local on A, bee on B). Run through
## tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_launch_news.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## A suite of its own because tools/test_launch.gd, where the cases before
## these live (a start that came up, left and returned to while a look is
## owed; a cancelled confirm; a click after the kinds change), stands at
## gdlint's file cap. Every case first resets both fakes and opens only what
## it needs; the last case sums up both fakes: nothing reached them that no
## case opened.


func _marker() -> String:
	return "LAUNCH NEWS TESTS"


## A start that came up and was looked at stays said on the card that saw it
## come up; a later card of the same pane (the viewer left and came back) says
## nothing of it: it was news, and it was seen.
func test_a_start_that_came_up_and_was_looked_at_is_said_on_its_first_card_only() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"], {"detect": 0.2, "delay": 0.6})
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start went")
	await _until(func() -> bool: return card.outcome_text() == "claude-1 started", "the card that saw it says so")
	await _until(func() -> bool: return not office.fleet.must_look(key), "its terminal was read again: looked at")
	await _frames(3)
	_eq(card.outcome_text(), "claude-1 started", "still said on the card that saw it come up")
	var first := card.binding()
	await _pick_local(office, "alpha:p1")
	await _pick_local(office, "alpha:p2")
	await _frames(3)
	_check(card.binding() != first, "left and came back: another card of the same pane")
	_eq(card.outcome_text(), "", "a later card says nothing of it")
	_eq(_count("control-a", "agent.start"), 1, "one start, never again")


## Another terminal takes the pane a start was sent to: the card that sees it
## says `Terminal changed`. While the look the start's write owes is still
## owed, a later card of the pane says it too; once the terminal was read
## again it is news no more.
func test_a_start_whose_terminal_changed_is_said_on_a_later_card_while_a_look_is_owed() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"], {"outcome": "never"})
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start went")
	# The card's next read of the terminal never answers: no look for five seconds.
	_ctl("control-a", "next", {"action": "hang", "method": "pane.read"})
	await _until(func() -> bool: return card.outcome_text().begins_with("Starting claude-1"), "starting")
	var moved := _changed(_dict(_ctl("control-a", "stats"), "snapshot"), "alpha:p2", {"terminal_id": "term-new"})
	_ctl("control-a", "set_snapshot", {"snapshot": moved})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.outcome_text() == "Terminal changed", "the card that sees it says so")
	_check(office.fleet.must_look(key), "the look is still owed")
	var first := card.binding()
	await _pick_local(office, "alpha:p1")
	await _pick_local(office, "alpha:p2")
	_check(card.binding() != first, "left and came back: another card of the same pane")
	_check(office.fleet.must_look(key), "the look still owed")
	_eq(card.outcome_text(), "Terminal changed", "still news there: nobody has looked")
	await _until(func() -> bool: return not office.fleet.must_look(key), "a read is shown: looked at")
	await _until(func() -> bool: return card.outcome_text() != "Terminal changed", "and it is news no more")
	_eq(card.outcome_text(), "", "the footer says nothing")
	_eq(_count("control-a", "agent.start"), 1, "one start, never again")


## The same with the look already paid: the card that sees the terminal change
## says so, and a later card of the pane does not.
func test_a_start_whose_terminal_changed_after_a_look_is_said_on_its_first_card_only() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"], {"outcome": "never"})
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start went")
	await _until(func() -> bool: return card.outcome_text().begins_with("Starting claude-1"), "starting")
	await _until(func() -> bool: return not office.fleet.must_look(key), "its terminal was read again: looked at")
	var moved := _changed(_dict(_ctl("control-a", "stats"), "snapshot"), "alpha:p2", {"terminal_id": "term-new"})
	_ctl("control-a", "set_snapshot", {"snapshot": moved})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.outcome_text() == "Terminal changed", "the card that sees it says so")
	_check(not office.fleet.must_look(key), "no look is owed")
	await _frames(3)
	_eq(card.outcome_text(), "Terminal changed", "and keeps saying so")
	var first := card.binding()
	await _pick_local(office, "alpha:p1")
	await _pick_local(office, "alpha:p2")
	await _frames(3)
	_check(card.binding() != first, "left and came back: another card of the same pane")
	_eq(card.outcome_text(), "", "a later card says nothing of it")
	_eq(_count("control-a", "agent.start"), 1, "one start, never again")


## The pane a start was sent to goes: the card has no such pane to show,
## follows herdr's focus and says nothing of the start (no card ever shows a
## pane the snapshot lacks, so `Pane gone` has no card to stand on). When its
## id comes back under another terminal and the viewer picks it, the start's
## write still owes its look, and the card says the terminal changed.
func test_a_start_whose_pane_goes_is_not_said_until_its_id_returns_under_another_terminal() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"], {"outcome": "never"})
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start went")
	# The card's next read of the terminal never answers: no look for five seconds.
	_ctl("control-a", "next", {"action": "hang", "method": "pane.read"})
	await _until(func() -> bool: return card.outcome_text().begins_with("Starting claude-1"), "starting")
	var gone := _without(_dict(_ctl("control-a", "stats"), "snapshot"), "alpha:p2")
	_ctl("control-a", "set_snapshot", {"snapshot": gone})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.shown_pane_key() != key, "the card has no such pane to show")
	await _frames(3)
	_eq(card.shown_pane_key(), HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1"), "it follows herdr's focus instead")
	_eq(card.outcome_text(), "Following herdr's focus", "and says so: nothing of the start")
	_eq(LaunchWatch.name_of(office.fleet.launch_outcome(key)), "GONE", "the fleet judges the start's pane gone")
	_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p2", {"terminal_id": "term-new"})})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.frame.pane(key) != null, "the id is back")
	await _pick_local(office, "alpha:p2")
	_check(office.fleet.must_look(key), "the start's write still owes its look")
	_eq(card.outcome_text(), "Terminal changed", "the id under another terminal: the card that sees it says so")
	await _until(func() -> bool: return not office.fleet.must_look(key), "a read is shown: looked at")
	await _frames(3)
	_eq(card.outcome_text(), "Terminal changed", "and keeps saying so: it is the card that first saw the start over")
	_eq(_count("control-a", "agent.start"), 1, "one start, never again")


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)


# --- helpers (tools/test_launch.gd's, as they stand there) -------------------------


## Local's shell alpha:p2 picked with a real click, `recent` its recent output
## and, at full height, shown: both fakes reset with `methods` open, Local on
## `raw` when given, its starts landing as `launch` says (quickly by default).
func _shell_card(
	recent: String, methods: Array, launch := {}, raw := {}, screen := Vector2(SCREEN), open := true
) -> OfficeDouble:
	_fakes("snapshot_basic", methods)
	if not raw.is_empty():
		_ctl("control-a", "set_snapshot", {"snapshot": raw})
	var plan := {"outcome": "ready", "detect": 0.2, "delay": 0.6}
	plan.merge(launch, true)
	_ctl("control-a", "set_launch", plan)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": recent})
	var office := await _office_with(false, true, true, screen)
	await _pick_local(office, "alpha:p2", open)
	if not office.hud.card_compact():
		var card := _card(office)
		await _until(func() -> bool: return card.preview_text() == recent, "the shell's recent output is shown")
	return office


## The card's kind button `index` (`%Kind0` …).
func _kind(office: OfficeDouble, index: int) -> Button:
	return office.hud.inspector.get_node("%%Kind%d" % index)
