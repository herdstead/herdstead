extends "res://tools/command_test_base.gd"
## The one-line reply on the agent card, sent as herdr's own
## prompt: what the card says herdr did with it, in herdr's words, and
## that every gate before it still holds. An operator office against two fake
## herdrs of this suite's own (Local on A, bee on B, whose pane ids collide).
## Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_prompt.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Every gesture is real input: clicks on the card, typing into the reply
## box, Enter. Every case first resets both fakes and opens only what it needs
## (_fakes()), and asserts the exact requests each fake received. The last
## case sums up both fakes: nothing reached them that no case opened.

## bee's codex, idle in snapshot_basic: the agent every line here goes to.
var bee_p3 := HerdrFleet.pane_key(BEE, "alpha:p3")


func _marker() -> String:
	return "PROMPT TESTS"


## A line typed into the reply box goes as one prompt with the text alone:
## the card reads the output again first, then herdr types the line and its
## own Enter. The footer says `Sent` and, in its tooltip, only that herdr
## typed it, not that the agent acted; the box empties; Local hears nothing.
func test_send_line_prompts_the_agent_and_says_sent() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("ship it")
	var send := _key_button(office, "SendLine")
	_eq(
		send.tooltip_text,
		"Send one line to this agent on bee: herdr types it and presses Enter (bracketed when the agent asked). 7 of 1024 bytes.",
		"what Send line does, in fact"
	)
	await _click_control(send)
	await _until(func() -> bool: return card.outcome_text() == "Sent", "herdr took the line")
	var seen := _sequence("control-b")
	var at := seen.find("agent.prompt 7 bytes")
	_check(at >= 2, "the prompt went, after two reads: %s" % [seen])
	if at >= 2:
		_eq(
			seen.slice(at - 2, at + 1),
			PackedStringArray(
				["pane.read recent_unwrapped 12", "pane.read recent_unwrapped 12 check", "agent.prompt 7 bytes"]
			),
			"the output shown, read again, then the prompt"
		)
	_eq(_count("control-b", "agent.prompt"), 1, "one prompt")
	var inputs := _inputs("control-b")
	_eq(inputs.size(), 1, "herdr typed one line")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("text"), input.get("keys"), input.get("bracketed")], ["ship it", ["enter"], false], "")
	var outcome: Label = card.get_node("%Outcome")
	_eq(outcome.tooltip_text, "herdr typed the line and Enter; not whether the agent acted.", "Sent, and no more")
	_eq(box.text, "", "the box empties")
	_eq(_writes_seen("control-a"), PackedStringArray(), "Local hears nothing")


## A blocked agent takes no line: herdr would refuse the prompt too, and the
## card says so before herdr has to. If it turns blocked between the press and
## the send, the boundary's re-check refuses it after the re-read: nothing
## reaches herdr but that read.
func test_a_blocked_agent_is_refused_on_the_card_before_herdr_is() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("go on")
	var status := {"pane_id": "alpha:p3", "agent_status": "blocked"}
	_ctl(
		"control-b",
		"next",
		{
			"action": "stage",
			"method": "pane.read",
			"id_suffix": HerdrCommands.CHECK_SUFFIX,
			"status": status,
			"seconds": 0.5
		}
	)
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return _last_write(office) == "REFUSED", "refused after the re-read")
	await _frames(3)
	_eq(card.outcome_text(), "Not sent: asking: use keys", "the card says why")
	_eq(_writes_seen("control-b"), PackedStringArray(["pane.read recent_unwrapped 12 check"]), "only the re-read went")
	await _until(func() -> bool: return not office.fleet.must_look(bee_p3), "a look after the refusal")
	var send := _key_button(office, "SendLine")
	await _until(
		func() -> bool: return card.line_refusal() == CommandRefusal.Reason.AGENT_ASKING, "blocked: asking, on the card"
	)
	_check(card.answering(), "answer mode stayed open: nothing was written")
	_check(send.disabled, "Send line is off")
	_check(send.tooltip_text.contains("agent_blocked"), "herdr's own refusal is named: " + send.tooltip_text)
	_check(
		not send.tooltip_text.contains("confirm its default"), "not a reason of the office's own: " + send.tooltip_text
	)
	await _click_control(send)
	await _wait(0.3)
	_eq(_count("control-b", "agent.prompt"), 0, "no prompt reached herdr")
	_eq(_inputs("control-b"), [], "and herdr typed nothing")


## A working agent takes no line from the card, though herdr itself would
## type into it: answer mode does not open, Enter writes nothing, and the
## reason says so. The same prompt to the fake, from a boundary told the agent
## is idle, is carried out: the card and the boundary are the only gate.
func test_a_working_agent_takes_no_line_though_herdr_would() -> void:
	_fakes()
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p1", "text": "thinking…\n"})
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p1")
	await _until(func() -> bool: return card.preview_text() == "thinking…\n", "the working agent is shown")
	await _frames(5)
	_check(not card.answer_offered(), "no answer for a working agent")
	_check(not _control(office, "AnswerButton").visible, "no Answer chip")
	await _tap(KEY_ENTER)
	await _frames(3)
	_check(not card.answering(), "Enter opens nothing")
	_eq(card.line_refusal(), CommandRefusal.Reason.AGENT_BUSY, "a line: busy")
	_check(
		CommandRefusal.detail(CommandRefusal.Reason.AGENT_BUSY).ends_with(
			"herdr would type into a working agent; this office does not."
		),
		"the reason says herdr would"
	)
	_eq(_writes_seen("control-b"), PackedStringArray(), "nothing written to bee")
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p1", "source": "recent_unwrapped", "text": "thinking…\n"})
	var facts := _facts(args["socket-a"], _changed(_raw(), "alpha:p1", {"agent_status": "idle"}))
	var commands := _boundary()
	var seen := _seen(commands, facts, "alpha:p1", CommandContext.SOURCE_RECENT, 12)
	var ticket := commands.submit(_aim(facts, "alpha:p1").replying("keep going", seen), facts, _facts_now(facts))
	_settle(commands, ticket, "a prompt to a pane the boundary was told is idle")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	var inputs := _inputs("control-a")
	_eq(inputs.size(), 1, "and typed it into the working agent")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("pane_id"), input.get("text")], ["alpha:p1", "keep going"], "")
	commands.free()


## herdr's refusal of a prompt is said in its own words. A pane the fleet
## still holds as an idle agent (the snapshot poll has not come yet) but herdr
## knows no agent in: `herdr refused: no agent here`, with herdr's code in the
## tooltip, sent once and never again; once the poll comes, the card offers no
## line to it.
func test_not_found_and_not_ready_are_said_in_herdrs_words() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("ship it")
	await _after_a_poll("control-b")
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent": null})})
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return _last_write(office) == "REJECTED", "herdr refused the prompt")
	await _frames(3)
	_eq(card.outcome_text(), "herdr refused: no agent here", "in herdr's words")
	var outcome: Label = card.get_node("%Outcome")
	_check(outcome.tooltip_text.contains("agent_not_found"), "herdr's code in the tooltip: " + outcome.tooltip_text)
	_check(outcome.tooltip_text.contains("herdr knows no agent in this pane"), "and what it means")
	_eq(_inputs("control-b"), [], "herdr typed nothing")
	await _until(func() -> bool: return office.frame.pane(bee_p3).provider.is_empty(), "the next poll: a shell")
	await _frames(5)
	_check(not card.answer_offered(), "no line for a shell")
	await _wait(1.0)
	_eq(_count("control-b", "agent.prompt"), 1, "sent once, never again")


## An agent herdr is still launching takes no line. Once the fleet knows, the
## card refuses it itself (`starting`) and nothing is sent; while it does not
## know yet (no event, the poll still to come), herdr refuses it:
## `herdr refused: still starting`. One prompt in all, never sent again.
func test_a_line_to_an_agent_still_starting_is_refused_first_by_the_card_then_by_herdr() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	var send := _key_button(office, "SendLine")
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("ship it")
	var launching := _record_changed(_raw(), "alpha:p3", {"launch_pending": true})
	_ctl("control-b", "set_snapshot", {"snapshot": launching})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.frame.pane(bee_p3).starting, "the fleet sees it starting")
	await _frames(3)
	_eq(card.line_refusal(), CommandRefusal.Reason.AGENT_STARTING, "the card refuses it: starting")
	_check(send.disabled, "Send line is off")
	await _click_control(send)
	await _wait(0.3)
	_eq(_writes_seen("control-b"), PackedStringArray(), "nothing sent, not even a re-read")
	_ctl("control-b", "set_snapshot", {"snapshot": _raw()})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return not office.frame.pane(bee_p3).starting, "ready again")
	await _until(card.answer_offered, "answers are on again")
	if not card.answering():
		await _open_answer(office)
	await _after_a_poll("control-b")
	_ctl("control-b", "set_snapshot", {"snapshot": launching})
	await _click_control(send)
	await _until(func() -> bool: return _last_write(office) == "REJECTED", "herdr refused the prompt")
	await _frames(3)
	_eq(card.outcome_text(), "herdr refused: still starting", "in herdr's words")
	var outcome: Label = card.get_node("%Outcome")
	_check(outcome.tooltip_text.contains("agent_not_ready"), "herdr's code in the tooltip: " + outcome.tooltip_text)
	_eq(_inputs("control-b"), [], "herdr typed nothing")
	await _wait(1.0)
	_eq(_count("control-b", "agent.prompt"), 1, "one prompt, never sent again")


## When the agent asked for bracketed paste, herdr brackets the prompt itself;
## the card says the same `Sent`.
func test_a_prompt_is_bracketed_by_herdr_when_the_agent_asked() -> void:
	var office := await _idle_bee()
	_ctl("control-b", "set_paste_mode", {"pane_id": "alpha:p3"})
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("ship it")
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "herdr took the line")
	var inputs := _inputs("control-b")
	_eq(inputs.size(), 1, "one line")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq(input.get("bracketed"), true, "bracketed by herdr")
		_check(str(input.get("bytes")).begins_with("1b5b3230307e"), "ESC [200~ first: %s" % input.get("bytes"))
		_eq(input.get("text"), "ship it", "the text as typed")
	var outcome: Label = card.get_node("%Outcome")
	_eq(outcome.tooltip_text, "herdr typed the line and Enter; not whether the agent acted.", "the same Sent")


## A prompt herdr carried out but never answered is `Unknown result: look
## first`; the line is no draft any more; every write to the pane waits for a
## look; and the next line is a new gesture, not a retry.
func test_a_lost_prompt_answer_is_unknown_and_the_line_is_no_draft() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("ship it")
	_ctl("control-b", "next", {"action": "execute_then_drop", "method": "agent.prompt"})
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return card.outcome_text() == "Unknown result: look first", "the answer is lost")
	var outcome: Label = card.get_node("%Outcome")
	_check(outcome.tooltip_text.contains("nothing is retried"), "and nothing is retried: " + outcome.tooltip_text)
	_eq(_inputs("control-b").size(), 1, "herdr carried it out once")
	_eq(box.text, "", "the line is no draft")
	_check(office.fleet.must_look(bee_p3), "the pane owes a look")
	_eq(office.fleet.can_operate(bee_p3), CommandRefusal.Reason.LOOK_FIRST, "every write waits for it")
	await _until(card.answer_offered, "a look later, answers are on again")
	if not card.answering():
		await _open_answer(office)
	await _click_control(box)
	await _type("and this")
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the new line went")
	_eq(_count("control-b", "agent.prompt"), 2, "two gestures, two prompts")
	var texts: Array = _inputs("control-b").map(func(input: Dictionary) -> String: return str(input.get("text")))
	_eq(texts, ["ship it", "and this"], "the second is the new line, not the first again")


## Every class of line the send port refuses is refused on the card before
## any request: blank, a control character, over 1024 bytes, an invisible
## character, U+FFFD. Each is typed for real; herdr hears none of them.
func test_every_refused_line_class_is_still_refused_with_agent_prompt() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	var send := _key_button(office, "SendLine")
	var lines: Dictionary[String, String] = {
		"   ": "Line: empty line",
		"yes" + char(0x2028) + "no": "Line: control character",
		"中".repeat(342): "Line: over 1024 bytes",
		"ok" + char(0x200b) + "go": "Line: invisible character",
		"ok" + char(0xfffd): "Line: broken character",
	}
	for line: String in lines:
		await _click_control(box)
		await _type(line)
		_eq(box.text, line, "typed as it is: %s" % line.left(8).c_escape())
		_check(send.disabled, "Send line is off: %s" % line.left(8).c_escape())
		_eq(card.outcome_text(), lines[line], "and the card says why")
		await _click_control(send)
		await _hold(KEY_BACKSPACE, box.text.length())
		_eq(box.text, "", "cleared by Backspace")
	await _wait(0.3)
	_eq(_count("control-b", "agent.prompt"), 0, "no prompt")
	_eq(_inputs("control-b"), [], "herdr typed nothing")
	_eq(_writes_seen("control-b"), PackedStringArray(), "not even a re-read")


## A prompt holds the pane's one write: while it is out Send line and the
## switch are off and the footer says `Sending…`; after it, every write waits
## for a look. A machine that goes while a line is still being checked takes
## the line with it: nothing is written, and a machine that comes back is a
## new generation that the old press never matches.
func test_a_prompt_takes_the_pane_slot_and_a_replaced_machine_cancels_it() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	var send := _key_button(office, "SendLine")
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("one")
	_ctl("control-b", "next", {"action": "delay", "method": "agent.prompt", "seconds": 1.5})
	await _click_control(send)
	await _until(func() -> bool: return _last_write(office) == "SENT", "the prompt is out")
	_check(card.writing(), "the card's one answer in flight: " + card.outcome_text())
	_check(send.disabled, "Send line is off while it is out")
	_check(_switch(office).disabled, "so is the switch")
	_eq(office.fleet.can_operate(bee_p3), CommandRefusal.Reason.IN_FLIGHT, "the pane's one write")
	await _until(func() -> bool: return card.outcome_text() == "Sent", "herdr took it")
	_eq(office.fleet.can_operate(bee_p3), CommandRefusal.Reason.LOOK_FIRST, "every write waits for a look")
	await _until(card.answer_offered, "the look came")
	if not card.answering():
		await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("two")
	_ctl("control-b", "next", {"action": "hang", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX})
	await _click_control(send)
	await _until(func() -> bool: return card.outcome_text() == "Checking the screen…", "re-reading")
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return not card.writing(), "the line ends with its machine")
	await _frames(3)
	var refused: CommandAuditEntry = office.fleet.write_log().back()
	_eq(refused.last_state(), "REFUSED", "refused after the re-read failed: nothing written")
	_eq(refused.refusal, CommandRefusal.name_of(CommandRefusal.Reason.RECHECK_FAILED), "no re-read")
	_eq(card.outcome_text(), "Not sent: no re-read", "the card says so")
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "bee is offline")
	_eq(_count("control-b", "agent.prompt"), 1, "only the first prompt")
	_eq(_inputs("control-b").size(), 1, "herdr typed only the first line")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return office.fleet.snapshot_is_current(BEE), "bee is back")
	await _wait(1.0)
	_eq(_count("control-b", "agent.prompt"), 1, "nothing more sent after it came back")
	_eq(_inputs("control-b").size(), 1, "and nothing more typed")


## Zero gestures, zero writes: answer mode open on an idle agent with a draft
## typed, through refreshes, status changes, an event and seconds of reading.
func test_answer_mode_writes_nothing_without_a_gesture_with_agent_prompt() -> void:
	var office := await _idle_bee()
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("draft")
	for index in 30:
		office.refresh()
	for status: String in ["working", "done", "blocked", "idle"]:
		_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": status})
		await _wait(0.4)
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _wait(3.0)
	_check(_count("control-b", "pane.read") > 3, "it read all along")
	_eq(_count("control-b", "agent.prompt"), 0, "no prompt")
	_eq(_all_inputs(), 0, "and nothing typed")
	_eq(_writes_seen("control-b") + _writes_seen("control-a"), PackedStringArray(), "not even a re-read for one")


## A `--read-only` office offers no answer and no Send line, and asks nothing
## but the read-only three.
func test_read_only_prompts_nothing() -> void:
	_fakes("snapshot_basic", [])
	var office := await _office_with(true)
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _frames(10)
	_check(not card.answer_offered(), "no answer")
	_check(not _key_button(office, "SendLine").is_visible_in_tree(), "no Send line")
	await _tap(KEY_ENTER)
	await _frames(3)
	_check(not card.answering(), "Enter opens nothing")
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "methods"):
			_check(method in READ_ONLY_METHODS, "%s: only the read-only three: %s" % [which, method])
		_eq(_sequence(which), PackedStringArray(), "%s: nothing beyond them this case" % which)


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


## Right after fake `which` answered a snapshot poll: the next is
## HerdrClient.SNAPSHOT_INTERVAL away, so a snapshot set now stays unseen by
## the fleet (no event goes with it) for that long.
func _after_a_poll(which: String) -> void:
	var before := _count(which, "session.snapshot")
	await _until(func() -> bool: return _count(which, "session.snapshot") > before, "a snapshot poll")
	await _frames(2)


## `raw` with pane `pane_id`'s agent record changed by `fields` (a null
## removes one), where herdr keeps a launch: the pane record untouched.
func _record_changed(raw: Dictionary, pane_id: String, fields: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	for record: Dictionary in _list(result, "agents"):
		if record.get("pane_id") == pane_id:
			for field: String in fields:
				if fields[field] == null:
					record.erase(field)
				else:
					record[field] = fields[field]
	return result
