extends "res://tools/command_test_base.gd"
## Answer mode: the approval keys and the one-line reply the agent
## card sends through the write boundary, against two fake herdrs of this
## suite's own whose pane ids collide. The bubbles' reads and the clicks that
## open answer mode from the world are tools/test_bubbles.gd's. Run through
## tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_answers.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## The send port's cases pump a HerdrCommands outside the tree on synthetic
## time; everything the card does runs in a live office on real frames, driven
## by real input (clicks, keys, typing). Every gate asserts the exact requests
## each fake received. The last case sums up both fakes: nothing reached them
## that no case opened.


func _marker() -> String:
	return "ANSWER TESTS"


# --- input at the boundary: keys and a line -----------------------------------------


## Only the answer keys, spelled exactly, ever reach the socket. herdr takes far
## more (`C-c`, capitals, arrows …), and so does the fake: the allowlist is the
## only guard, and a leak would show up here as a recorded write.
func test_only_the_answer_keys_are_ever_sent() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var target := _aim(facts, "bravo:p1")
	var outside: Array[String] = ["C-c", "ctrl+c", "Y", "N", "escape", "Escape", "Enter", "ENTER", "return"]
	outside.append_array(["tab", "space", "backspace", "up", "f1", "0", "10", "yy", "", " y", "y ", "y\n"])
	outside.append_array([char(0x1b), char(0x03), char(0xff11), "1​"])
	for key in outside:
		var context := target.keying(key, seen)
		_eq(HerdrCommands.refusal(context, facts), CommandRefusal.Reason.KEY_NOT_ALLOWED, "refused: " + key.c_escape())
		var ticket := commands.submit(context, facts, _facts_now(facts))
		_eq(
			[ticket.state, ticket.refusal],
			[CommandTicket.State.REFUSED, CommandRefusal.Reason.KEY_NOT_ALLOWED],
			"refused at the send port: " + key.c_escape()
		)
	for key in HerdrCommands.KEY_NAMES:
		_eq(HerdrCommands.refusal(target.keying(key, seen), facts), CommandRefusal.Reason.NONE, "an answer key: " + key)
	_eq(commands.open_count(), 0, "nothing was opened")
	_check(not commands.must_look(target.pane_key), "refused at the gesture: nothing to look at")
	await _frames(3)
	_eq(_count("control-a", "pane.send_keys"), 0, "no request reached herdr")
	_eq(_all_inputs(), 0, "and no byte of any key")
	commands.free()


## Every class of line the send port refuses is refused by name, and none of it
## reaches the socket; nothing is rewritten to make it pass.
func test_every_refused_line_class_is_refused_by_name() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	var target := _aim(facts, "alpha:p3")
	var refused: Dictionary[String, CommandRefusal.Reason] = {}
	for blank: String in ["", " ", "   ", "　 ", "  ⠀"]:
		refused[blank] = CommandRefusal.Reason.LINE_BLANK
	for code: int in [
		0x01, 0x03, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0d, 0x1b, 0x1f, 0x7f, 0x80, 0x85, 0x9b, 0x2028, 0x2029
	]:
		refused["yes" + char(code) + "no"] = CommandRefusal.Reason.LINE_CONTROL
	# The end of a bracketed paste, typed: its ESC is what would end the paste early.
	refused[char(0x1b) + "[201~rm -rf x"] = CommandRefusal.Reason.LINE_CONTROL
	var invisible: Array[int] = [0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e]
	invisible.append_array([0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0x2066, 0x2067, 0x2068, 0x2069, 0x061c, 0xfeff])
	invisible.append_array([0x00ad, 0x180e, 0x3164, 0xe0041])
	for code in invisible:
		refused["ok" + char(code) + "go"] = CommandRefusal.Reason.LINE_INVISIBLE
	for code: int in [0xfffd, 0xfffe, 0xffff]:
		refused["ok" + char(code)] = CommandRefusal.Reason.LINE_BROKEN
	refused["x".repeat(HerdrCommands.LINE_BYTES_MAX + 1)] = CommandRefusal.Reason.LINE_TOO_LONG
	refused["é".repeat(513)] = CommandRefusal.Reason.LINE_TOO_LONG
	refused["界".repeat(342)] = CommandRefusal.Reason.LINE_TOO_LONG
	refused["x".repeat(70000)] = CommandRefusal.Reason.LINE_TOO_LONG
	for line: String in refused:
		var what := line.left(24).c_escape()
		_eq(HerdrCommands.line_refusal(line), refused[line], "refused: " + what)
		var ticket := commands.submit(target.replying(line, seen), facts, _facts_now(facts))
		_eq([ticket.state, ticket.refusal], [CommandTicket.State.REFUSED, refused[line]], "at the send port: " + what)
	var fine: Array[String] = ["yes", "  go on  ", "中文 ok", "résumé", "👍 ship it", "❤️", "x".repeat(1024)]
	fine.append_array(["é".repeat(512), "界".repeat(341) + "x", "$HOME; not expanded here", "a\\nb"])
	for line in fine:
		_eq(HerdrCommands.line_refusal(line), CommandRefusal.Reason.NONE, "a line: " + line.left(24))
	_eq(commands.open_count(), 0, "nothing was opened")
	await _frames(3)
	_eq(_count("control-a", "agent.prompt"), 0, "no request reached herdr")
	_eq(_all_inputs(), 0, "and no byte of any line")
	commands.free()


## Answer keys go only to an agent herdr reports blocked; a line only to one
## that is idle or done. A shell takes neither, one still launching no line
## (keys when it asks), and one working, or in a state herdr did not say, no line.
func test_who_may_receive_what() -> void:
	_fakes()
	var raw := _changed(_raw(), "alpha:p3", {"agent_status": "done"})
	var none := CommandRefusal.Reason.NONE
	# [pane, status (null: as the fixture has it), extra fields, keys, line]
	var cases: Array = [
		["bravo:p1", null, {}, none, CommandRefusal.Reason.AGENT_ASKING],
		["alpha:p3", "done", {}, CommandRefusal.Reason.NOT_ASKING, none],
		["alpha:p3", "idle", {}, CommandRefusal.Reason.NOT_ASKING, none],
		["alpha:p1", "working", {}, CommandRefusal.Reason.NOT_ASKING, CommandRefusal.Reason.AGENT_BUSY],
		["alpha:p1", "unknown", {}, CommandRefusal.Reason.NOT_ASKING, CommandRefusal.Reason.AGENT_BUSY],
		["alpha:p1", "sleeping", {}, CommandRefusal.Reason.NOT_ASKING, CommandRefusal.Reason.AGENT_BUSY],
		["alpha:p2", "blocked", {}, CommandRefusal.Reason.NOT_AN_AGENT, CommandRefusal.Reason.NOT_AN_AGENT],
		["alpha:p2", "idle", {}, CommandRefusal.Reason.NOT_AN_AGENT, CommandRefusal.Reason.NOT_AN_AGENT],
		["bravo:p1", "blocked", {"launch_pending": true}, none, CommandRefusal.Reason.AGENT_STARTING],
	]
	var commands := _boundary()
	for case: Array in cases:
		var pane_id: String = case[0]
		var changes: Dictionary = case[2]
		var changed := raw
		if case[1] != null:
			changes = changes.duplicate()
			changes["agent_status"] = case[1]
		if not changes.is_empty():
			changed = _changed(raw, pane_id, changes)
		var now := _facts(args["socket-a"], changed)
		var target := _aim(now, pane_id)
		var what := "%s %s" % [pane_id, case[1] if case[1] != null else "as is"]
		_eq(HerdrCommands.refusal(target.keying("y", null), now), case[3], "keys to " + what)
		_eq(HerdrCommands.refusal(target.replying("ok", null), now), case[4], "a line to " + what)
		# And through the send port, with a real preview frozen: refused alike.
		var keys_seen := _seen(commands, now, pane_id, CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
		var keys := commands.submit(target.keying("y", keys_seen), now, _facts_now(now))
		if case[3] != none:
			_eq(keys.refusal, case[3], "keys refused to " + what)
		else:
			_settle(commands, keys, "keys to " + what)
		var line_seen := _seen(commands, now, pane_id, CommandContext.SOURCE_RECENT, 12)
		var line := commands.submit(target.replying("ok", line_seen), now, _facts_now(now))
		if case[4] != none:
			_eq(line.refusal, case[4], "a line refused to " + what)
		else:
			_settle(commands, line, "a line to " + what)
		if case[3] == none or case[4] == none:
			_eq([keys.state, line.state].count(CommandTicket.State.ACCEPTED), 1, "the one it may receive went: " + what)
			await _look(commands, now, pane_id)
	await _frames(3)
	var sent := _inputs("control-a").map(
		func(record: Dictionary) -> String: return "%s %s" % [record.get("pane_id"), record.get("method")]
	)
	_eq(
		sent,
		["bravo:p1 pane.send_keys", "alpha:p3 agent.prompt", "alpha:p3 agent.prompt", "bravo:p1 pane.send_keys"],
		"only a blocked agent took keys, only a done or idle one a line"
	)
	commands.free()


## An answer key is one ticket: the pane's write slot is taken at the gesture,
## the whole question is read again from the source the press saw, and only then
## does the key go, once, with herdr's own pane id.
func test_a_key_rereads_the_whole_question_then_sends_once() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	_eq(seen.text, QUESTION, "the press saw the question")
	var context := _aim(facts, "bravo:p1").keying("1", seen)
	var ticket := commands.submit(context, facts, _facts_now(facts))
	_check(commands.writing(context.pane_key), "the write slot is taken at the gesture")
	_eq(ticket.state, CommandTicket.State.UNSENT, "re-reading: nothing written yet")
	_settle(commands, ticket, "the key")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	var bytes := QUESTION.to_utf8_buffer().size()
	_eq([ticket.recheck_bytes, ticket.recheck_matched], [bytes, true], "the re-read matched, all of it")
	_eq(
		_sequence("control-a"),
		PackedStringArray(["pane.read detection 200", "pane.read detection 200 check", 'pane.send_keys ["1"]']),
		"read, re-read, key: nothing else, in that order"
	)
	var inputs := _inputs("control-a")
	_eq(inputs.size(), 1, "one write")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("pane_id"), input.get("keys")], ["bravo:p1", ["1"]], "the one key, to herdr's pane id")
	var entry: CommandAuditEntry = commands.write_log().back()
	_eq(
		[entry.method, entry.key_name, entry.line_bytes, entry.recheck_bytes, entry.recheck_matched],
		["pane.send_keys", "1", -1, bytes, true],
		"the audit: the key's name and the re-read"
	)
	_eq(entry.states, PackedStringArray(["UNSENT", "SENT", "ACCEPTED"]), "a re-read is no write: SENT only then")
	_check(not commands.writing(context.pane_key), "the slot is free again")
	_check(commands.must_look(context.pane_key), "and a look comes before the next write")
	_eq(commands.last_write(context.pane_key), ticket, "which remembers this one")
	commands.free()


## A line to an idle agent: its recent output is read again, then the text and
## Enter go in one request, byte for byte. The audit keeps the byte count only.
func test_a_line_rereads_then_sends_its_text_and_enter() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "done.\n$ \n"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	var line := "ship it: 中文 ✓ " + SENTINEL
	var bytes := line.to_utf8_buffer().size()
	var ticket := commands.submit(_aim(facts, "alpha:p3").replying(line, seen), facts, _facts_now(facts))
	_settle(commands, ticket, "the line")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	_eq(
		_sequence("control-a"),
		PackedStringArray(
			[
				"pane.read recent_unwrapped 12",
				"pane.read recent_unwrapped 12 check",
				"agent.prompt %d bytes" % bytes,
			]
		),
		"read, re-read, the line and Enter in one request"
	)
	var inputs := _inputs("control-a")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("text"), input.get("keys")], [line, ["enter"]], "byte for byte, then Enter")
	else:
		_fail("one line expected, got %d writes" % inputs.size())
	var entry: CommandAuditEntry = commands.write_log().back()
	_eq([entry.method, entry.line_bytes, entry.key_name], ["agent.prompt", bytes, ""], "audited by size")
	_check(not SENTINEL in _entry_text(entry) and not "ship it" in _entry_text(entry), "never by its text")
	commands.free()


## A re-read that reads differently anywhere in the whole question (here in
## row 1, above the 12 the card shows), comes back cut, refused, garbled, cut
## off or not at all: nothing is written, each with its reason, and the pane
## then waits for a look.
func test_a_reread_that_differs_writes_nothing() -> void:
	_fakes()
	var rows := PackedStringArray()
	for index in 31:
		rows.append("row %d of the question" % (index + 1))
	var question := "\n".join(rows) + "\n"
	var garbled := '{"id":"$ID","result":{"type":"pane_read","read":42}}'
	# [what the re-read gets, the reason, what]
	var cases: Array = [
		[
			{"action": "stage", "preview": {"pane_id": "bravo:p1", "text": question.replace("row 1 of", "row 1 in")}},
			CommandRefusal.Reason.SCREEN_CHANGED,
			"row 1, above the rows shown, changed"
		],
		[
			{"action": "stage", "preview": {"pane_id": "bravo:p1", "text": question + "x\n"}},
			CommandRefusal.Reason.SCREEN_CHANGED,
			"a row more"
		],
		[
			{"action": "stage", "preview": {"pane_id": "bravo:p1", "text": question.replace("of", "of\u0007")}},
			CommandRefusal.Reason.SCREEN_CHANGED,
			"the same once cleaned, not byte for byte"
		],
		[
			{"action": "stage", "preview": {"pane_id": "bravo:p1", "text": question, "truncated": true}},
			CommandRefusal.Reason.SCREEN_CUT,
			"cut by herdr"
		],
		[{"action": "refuse", "code": "pane_not_found"}, CommandRefusal.Reason.RECHECK_FAILED, "refused by herdr"],
		[{"action": "close_midreply"}, CommandRefusal.Reason.RECHECK_FAILED, "cut off mid-answer"],
		[{"action": "reply", "line": garbled}, CommandRefusal.Reason.RECHECK_FAILED, "unreadable"],
		[{"action": "hang"}, CommandRefusal.Reason.RECHECK_FAILED, "never answered"],
	]
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	for case: Array in cases:
		var what: String = case[2]
		_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "text": question})
		var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
		var base: Dictionary = case[0]
		var hook := base.duplicate(true)
		hook["method"] = "pane.read"
		hook["id_suffix"] = HerdrCommands.CHECK_SUFFIX
		_ctl("control-a", "next", hook)
		var ticket := commands.submit(_aim(facts, "bravo:p1").keying("1", seen), facts, _facts_now(facts))
		# Small steps: a real re-read has to come back well inside its timeout.
		_settle(commands, ticket, what, 0.05)
		_eq([ticket.state, ticket.refusal], [CommandTicket.State.REFUSED, case[1]], what)
		_check(commands.must_look(ticket.context.pane_key), what + ": look first")
		await _look(commands, facts, "bravo:p1")
	_eq(_checks("control-a"), cases.size(), "every one was read again")
	_eq(_count("control-a", "pane.send_keys"), 0, "and not one key went")
	_eq(_all_inputs(), 0, "nothing was written")
	var refusals := commands.write_log().map(func(entry: CommandAuditEntry) -> String: return entry.refusal)
	_eq(refusals.count("SCREEN_CHANGED"), 3, "the audit says why")
	commands.free()


## Every check runs again when the re-read comes back, against what the fleet
## knows then, not the copy taken at the press: the agent stopped asking, the
## machine was replaced, went or dropped, the snapshot is no longer current,
## another terminal holds the pane. Nothing is written; a machine settled while
## its re-read is out cancels the ticket.
func test_every_check_runs_again_after_the_reread() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var raw := _raw()
	var socket: String = args["socket-a"]
	var working := _facts(socket, _changed(raw, "bravo:p1", {"agent_status": "working"}))
	var replaced := _facts(socket, raw, 2)
	var offline := _facts(socket, raw)
	offline.online = false
	var stale := _facts(socket, raw)
	stale.current = false
	var other := _facts(socket, _changed(raw, "bravo:p1", {"terminal_id": "term-bravo-new"}))
	var unknown := _facts(socket, _changed(raw, "bravo:p1", {"terminal_id": null}))
	var odd := _facts(socket, raw)
	odd.protocol = 23
	# [what the fleet knows once the re-read is back, the reason]
	var cases: Array = [
		[working, CommandRefusal.Reason.NOT_ASKING, "blocked -> working"],
		[replaced, CommandRefusal.Reason.MACHINE_REPLACED, "machine replaced"],
		[null, CommandRefusal.Reason.MACHINE_GONE, "machine gone"],
		[offline, CommandRefusal.Reason.MACHINE_OFFLINE, "machine offline"],
		[stale, CommandRefusal.Reason.SNAPSHOT_NOT_CURRENT, "online, not current"],
		[other, CommandRefusal.Reason.IDENTITY_CHANGED, "another terminal"],
		[unknown, CommandRefusal.Reason.IDENTITY_UNKNOWN, "no terminal id"],
		[odd, CommandRefusal.Reason.UNKNOWN_PROTOCOL, "another protocol"],
	]
	var facts := _facts(socket, raw)
	var commands := _boundary()
	var fleet_knows: Array[HerdrCommands.Machine] = [facts]
	var ask := func() -> HerdrCommands.Machine: return fleet_knows[0]
	for case: Array in cases:
		var what: String = case[2]
		fleet_knows[0] = facts
		var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
		var ticket := commands.submit(_aim(facts, "bravo:p1").keying("1", seen), facts, ask)
		_eq(ticket.state, CommandTicket.State.UNSENT, what + ": passed at the press")
		fleet_knows[0] = case[0]
		_settle(commands, ticket, what)
		_eq([ticket.state, ticket.refusal], [CommandTicket.State.REFUSED, case[1]], what)
		await _look(commands, facts, "bravo:p1")
	# Without anything to ask, nothing is known: refused.
	var seen_last := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var blind := commands.submit(_aim(facts, "bravo:p1").keying("1", seen_last), facts)
	_settle(commands, blind, "no fleet to ask")
	_eq(blind.refusal, CommandRefusal.Reason.MACHINE_GONE, "no fleet to ask: refused")
	await _look(commands, facts, "bravo:p1")
	# The machine goes while the re-read is out: cancelled, never sent.
	_ctl("control-a", "next", {"action": "hang", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX})
	var seen_gone := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var checked := _checks("control-a")
	var gone := commands.submit(_aim(facts, "bravo:p1").keying("1", seen_gone), facts, _facts_now(facts))
	var deadline := Time.get_ticks_msec() + 3000
	while _checks("control-a") == checked and Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(2000)
	_eq(_checks("control-a"), checked + 1, "the re-read is out")
	commands.settle_machine(facts.key)
	_eq(gone.state, CommandTicket.State.CANCELLED, "its machine went during the re-read: cancelled")
	_eq(commands.write_log().back().states, PackedStringArray(["UNSENT", "CANCELLED"]), "never SENT")
	await _frames(3)
	_eq(_count("control-a", "pane.send_keys"), 0, "no key went")
	_eq(_all_inputs(), 0, "nothing was written")
	commands.free()


## One pane, one write, from the gesture on: while an answer re-reads, a second
## key, a switch and Esc to that pane are refused IN_FLIGHT; another pane is not
## held up. Afterwards the pane waits for a look.
func test_one_write_per_pane_from_the_gesture_on() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var idle_seen := _seen(commands, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	var check := {"action": "delay", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "seconds": 0.4}
	_ctl("control-a", "next", check)
	var target := _aim(facts, "bravo:p1")
	var first := commands.submit(target.keying("1", seen), facts, _facts_now(facts))
	var refused: Array[CommandTicket] = [
		commands.submit(target.keying("2", seen), facts, _facts_now(facts)),
		commands.submit(target.focusing(), facts),
		commands.submit(target.keying("esc", seen), facts, _facts_now(facts)),
	]
	for ticket in refused:
		_eq(ticket.refusal, CommandRefusal.Reason.IN_FLIGHT, "in flight: %s" % ticket.context.kind)
	var other := commands.submit(_aim(facts, "alpha:p3").replying("go on", idle_seen), facts, _facts_now(facts))
	_check(not other.is_finished(), "another pane is not held up")
	_settle(commands, first, "the first key")
	_settle(commands, other, "the other pane's line")
	_eq([first.state, other.state], [CommandTicket.State.ACCEPTED, CommandTicket.State.ACCEPTED], "both went")
	var again := commands.submit(target.keying("2", seen), facts, _facts_now(facts))
	_eq(again.refusal, CommandRefusal.Reason.LOOK_FIRST, "right after, the pane waits for a look")
	await _frames(3)
	var sent := _inputs("control-a").map(
		func(record: Dictionary) -> String: return "%s %s" % [record.get("pane_id"), record.get("keys")]
	)
	sent.sort()
	_eq(sent, ['alpha:p3 ["enter"]', 'bravo:p1 ["1"]'], "one write per pane")
	commands.free()


## After a write ends, whatever became of it (accepted, rejected, unknown,
## cancelled, refused after its re-read), the pane takes no write until a read
## asked for LOOK_DELAY_MSEC later has been shown; an earlier one does not count.
func test_look_before_writing_again_after_every_outcome() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var changed := {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION + "?\n"}
	# [a hook for the send (or its re-read), the state it ends in]
	var cases: Array = [
		[{}, CommandTicket.State.ACCEPTED],
		[{"action": "refuse", "method": "pane.send_keys", "code": "busy"}, CommandTicket.State.REJECTED],
		[{"action": "execute_then_drop", "method": "pane.send_keys"}, CommandTicket.State.UNKNOWN],
		[
			{"action": "stage", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "preview": changed},
			CommandTicket.State.REFUSED
		],
	]
	for case: Array in cases:
		_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
		var hook: Dictionary = case[0]
		if not hook.is_empty():
			_ctl("control-a", "next", hook)
		var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
		var target := _aim(facts, "bravo:p1")
		var ticket := commands.submit(target.keying("1", seen), facts, _facts_now(facts))
		_settle(commands, ticket, "a write")
		var ended: CommandTicket.State = case[1]
		var what := CommandTicket.state_name(ended)
		_eq(ticket.state, ended, what)
		_check(commands.must_look(target.pane_key), what + ": look first")
		_eq(commands.last_write(target.pane_key), ticket, what + ": remembered")
		var early := commands.submit(target.reading(CommandContext.SOURCE_RECENT, 12), facts)
		_settle(commands, early, "a read asked for at once")
		commands.saw(early)
		_check(commands.must_look(target.pane_key), what + ": a read asked for at once is no look")
		var fresh := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
		var again := commands.submit(target.keying("2", fresh), facts, _facts_now(facts))
		_eq(again.refusal, CommandRefusal.Reason.LOOK_FIRST, what + ": no write before a look")
		await _look(commands, facts, "bravo:p1")
		_check(not commands.must_look(target.pane_key), what + ": looked")
	# Cancelled: its machine went while it re-read.
	_ctl("control-a", "next", {"action": "hang", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX})
	var last_seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var cancelled := commands.submit(_aim(facts, "bravo:p1").keying("1", last_seen), facts, _facts_now(facts))
	commands.pump(0.0)
	commands.settle_machine(facts.key)
	_eq(cancelled.state, CommandTicket.State.CANCELLED, "CANCELLED")
	_check(commands.must_look(cancelled.context.pane_key), "CANCELLED: look first")
	await _frames(3)
	var keys := _inputs("control-a").map(func(record: Dictionary) -> Variant: return record.get("keys"))
	_eq(keys, [["1"], ["1"]], "only the accepted and the dropped key were carried out")
	commands.free()


## An answer whose reply is lost after herdr carried it out, never comes, or is
## cut in half: UNKNOWN, and never sent again.
func test_a_lost_answer_is_unknown_and_never_resent() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "$ \n"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var hooks: Array = [
		[{"action": "execute_then_drop", "method": "pane.send_keys"}, "bravo:p1", "herdr did it, then dropped"],
		[{"action": "hang", "method": "pane.send_keys"}, "bravo:p1", "never answered"],
		[{"action": "close_midreply", "method": "agent.prompt"}, "alpha:p3", "half an answer"],
	]
	for hook: Array in hooks:
		var action: Dictionary = hook[0]
		var pane_id: String = hook[1]
		var what: String = hook[2]
		var blocked := pane_id == "bravo:p1"
		var source := CommandContext.SOURCE_DETECTION if blocked else CommandContext.SOURCE_RECENT
		var seen := _seen(commands, facts, pane_id, source, HerdrCommands.READ_LINES_MAX if blocked else 12)
		_ctl("control-a", "next", action)
		var target := _aim(facts, pane_id)
		var context := target.keying("y", seen) if blocked else target.replying("again", seen)
		var ticket := commands.submit(context, facts, _facts_now(facts))
		_settle(commands, ticket, what, 0.05)
		_eq(ticket.state, CommandTicket.State.UNKNOWN, what)
		await _look(commands, facts, pane_id)
	await _frames(3)
	_eq([_count("control-a", "pane.send_keys"), _count("control-a", "agent.prompt")], [2, 1], "each sent once")
	_eq(_all_inputs(), 2, "the dropped key and the half-answered line were carried out; the hung one was not")
	commands.free()


## Answers that come back out of order still settle their own tickets: the
## first is held while another pane's answer comes and goes.
func test_answers_out_of_order_settle_their_own_tickets() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var blocked := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var idle := _seen(commands, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	_ctl("control-a", "next", {"action": "hold", "method": "pane.send_keys"})
	var first := commands.submit(_aim(facts, "bravo:p1").keying("1", blocked), facts, _facts_now(facts))
	var deadline := Time.get_ticks_msec() + 3000
	while _number(_ctl("control-a", "stats"), "held_replies") == 0.0 and Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(2000)
	_eq(first.state, CommandTicket.State.SENT, "the first is out, its answer held")
	var second := commands.submit(_aim(facts, "alpha:p3").replying("next", idle), facts, _facts_now(facts))
	_settle(commands, second, "the second")
	_eq([first.state, second.state], [CommandTicket.State.SENT, CommandTicket.State.ACCEPTED], "the second first")
	_ctl("control-a", "release_held")
	_settle(commands, first, "the first, late")
	_eq(first.state, CommandTicket.State.ACCEPTED, "the late answer is the first's own")
	var ids := _inputs("control-a").map(func(record: Dictionary) -> Variant: return record.get("id"))
	_eq(ids, [first.request_id, second.request_id], "carried out in order, answered out of it")
	commands.free()


# --- answer mode on the card, by real input -----------------------------------------


## A click on "1" on a blocked agent's card, with the best-effort line on screen:
## the question is read again, then exactly that key goes to that pane on that
## machine, once. The card says "Sent", and not more than herdr said.
func test_one_click_on_a_key_sends_that_key_once() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	_check(_control(office, "AnswerButton").is_visible_in_tree(), "the heading offers answering")
	_check(not card.answering(), "not before Enter")
	await _open_answer(office)
	var best: Label = _control(office, "BestEffort")
	_check(best.is_visible_in_tree(), "the best-effort line is on screen")
	_eq(best.text, "Checks the screen first; it can still change", "in these words")
	_check(best.tooltip_text.contains("does not close it"), "and the whole rule in its tooltip")
	_check(not best.text.contains("only"), "never a claim that only the question shown is answered")
	var one := _key_button(office, "Key1")
	for unique: String in ["Key1", "Key9", "KeyY", "KeyN", "KeyEnter", "SendEsc", "SendLine", "AnswerButton"]:
		_eq(_key_button(office, unique).focus_mode, Control.FOCUS_NONE, unique + " never takes keyboard focus")
	_check(not one.disabled, "the key is on")
	await _click_control(one)
	await _until(func() -> bool: return card.outcome_text() == "Sent", "herdr accepted the key")
	var outcome: Label = card.get_node("%Outcome")
	_eq(outcome.tooltip_text, "herdr accepted the keystrokes; not whether the agent acted.", "Sent, and no more")
	_eq(
		_writes_seen("control-b"),
		PackedStringArray(["pane.read detection 200 check", 'pane.send_keys ["1"]']),
		"the question read again, then the key, once"
	)
	var inputs := _inputs("control-b")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("pane_id"), input.get("keys")], ["alpha:p3", ["1"]], "to bee's alpha:p3")
	_eq(_inputs("control-a").size(), 0, "Local has the same pane id and heard nothing")
	_check(not card.answering(), "a key that went ends answer mode")
	var entry: CommandAuditEntry = office.fleet.write_log().back()
	_eq(
		[entry.machine, entry.method, entry.key_name, entry.recheck_matched, entry.last_state()],
		[BEE, "pane.send_keys", "1", true, "ACCEPTED"],
		"the audit"
	)


## Enter and keypad Enter only open answer mode: pressed twice, held, on an open
## answer mode or on the reply box, they send nothing, and never confirm the
## question's default answer.
func test_enter_never_sends() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _tap(KEY_ENTER)
	_check(card.answering(), "Enter opens answer mode")
	await _tap(KEY_ENTER)
	await _tap(KEY_KP_ENTER)
	await _hold(KEY_ENTER, 6)
	await _hold(KEY_KP_ENTER, 6)
	_check(card.answering(), "and more of it only keeps it open")
	await _tap(KEY_ESCAPE)
	_check(not card.answering(), "Escape leaves")
	await _tap(KEY_KP_ENTER)
	_check(card.answering(), "keypad Enter opens it too")
	await _click_control(_reply_box(office))
	await _type("yes")
	await _tap(KEY_ENTER)
	await _tap(KEY_KP_ENTER)
	_check(_reply_box(office).has_focus(), "Enter in the reply box keeps it")
	_eq(_reply_box(office).text, "yes", "and sends nothing of it")
	await _wait(0.5)
	_eq(_all_inputs(), 0, "no key, no line")
	_eq(_writes_seen("control-b"), PackedStringArray(), "nor anything read again for one")


## In answer mode the keyboard sends 1-9 and y by key position, one per press;
## N leaves and moves to the next agent without sending "n"; Escape leaves and
## is never sent.
func test_the_keyboard_sends_only_digits_and_y() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	await _tap(KEY_2)
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the 2 went")
	_check(not card.answering(), "each key sent ends answer mode")
	await _until(card.answer_offered, "a fresh look turns answering back on")
	await _open_answer(office)
	await _tap(KEY_Y)
	await _until(func() -> bool: return _inputs("control-b").size() == 2, "the y went")
	await _until(card.answer_offered, "looked again")
	await _open_answer(office)
	await _tap(KEY_ESCAPE)
	_check(not card.answering(), "Escape leaves answer mode")
	await _open_answer(office)
	var picked := office.picked_key
	await _tap(KEY_N)
	await _until(func() -> bool: return office.picked_key != picked, "N picks the next agent that needs a human")
	# N leaves this answer mode and, as NEXT's `Answer` says, opens the
	# next one's once its question shows; Escape leaves that one too.
	await _until(card.answering, "and answers the next one once its question shows")
	await _tap(KEY_ESCAPE)
	_check(not card.answering(), "Escape leaves it")
	for code: Key in [KEY_0, KEY_Q, KEY_1]:
		await _tap(code)
	await _wait(0.5)
	var keys := _inputs("control-b").map(func(record: Dictionary) -> Variant: return record.get("keys"))
	_eq(keys, [["2"], ["y"]], "only the 2 and the y; never n, never Escape, nothing outside answer mode")
	_eq(_inputs("control-a").size(), 0, "nothing to Local")


## n, Enter and Esc go only by their named buttons, each a click on a blocked
## agent's card.
func test_n_enter_and_esc_go_only_by_their_buttons() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	for unique: String in ["KeyN", "KeyEnter", "SendEsc"]:
		await _until(card.answer_offered, "answering is on")
		await _open_answer(office)
		var sent := _inputs("control-b").size()
		await _click_control(_key_button(office, unique))
		await _until(func() -> bool: return _inputs("control-b").size() == sent + 1, unique + " went")
		await _until(func() -> bool: return not card.writing(), unique + " settled")
	var keys := _inputs("control-b").map(func(record: Dictionary) -> Variant: return record.get("keys"))
	_eq(keys, [["n"], ["enter"], ["esc"]], "each by its button, as herdr names it")


## Button 1 and key 2 inside one re-read window: one write. Right after it, a
## press waits for a fresh look; a held key is one press, and a double click
## one click.
func test_one_answer_per_gesture_and_a_look_between() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	var check := {"action": "delay", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "seconds": 0.8}
	_ctl("control-b", "next", check)
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	_check(card.writing(), "the 1 is re-reading")
	_check(_key_button(office, "Key2").disabled, "every key is off meanwhile")
	await _tap(KEY_2)
	await _until(func() -> bool: return not card.writing(), "the 1 settles")
	_eq(_inputs("control-b").size(), 1, "button 1 then key 2 in one window: one write")
	_eq(card.keys_refusal(), CommandRefusal.Reason.LOOK_FIRST, "right after, the keys wait for a look")
	await _tap(KEY_ENTER)
	_check(not card.answering(), "and Enter has nothing to open")
	await _until(card.answer_offered, "a fresh preview turns them back on")
	await _open_answer(office)
	await _hold(KEY_3, 8)
	await _until(func() -> bool: return not card.writing(), "the held 3 settles")
	await _until(card.answer_offered, "looked again")
	await _open_answer(office)
	var four := _key_button(office, "Key4")
	for half: Array in [[true, false], [false, false], [true, true], [false, false]]:
		var down: bool = half[0]
		var double: bool = half[1]
		_half_click(four, down, double)
		await process_frame
	await _until(func() -> bool: return not card.writing(), "the double click settles")
	await _wait(0.5)
	var keys := _inputs("control-b").map(func(record: Dictionary) -> Variant: return record.get("keys"))
	_eq(keys, [["1"], ["3"], ["4"]], "one per gesture: a held key and a double click are one each")


## Leaving the card while an answer is out and coming back after it ended
## unknown: the card still says so, with every write off, until a fresh read
## has been shown.
func test_an_unknown_answer_is_still_said_when_coming_back() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	_ctl("control-b", "next", {"action": "hang", "method": "pane.send_keys"})
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return _last_write(office) == "SENT", "the key is out")
	await _pick_bee(office, "alpha:p1")
	_check(not card.answering(), "another desk: answer mode is over")
	var deadline := Time.get_ticks_msec() + int((HerdrCommands.INPUT_TIMEOUT + 3.0) * 1000)
	while _last_write(office) != "UNKNOWN" and Time.get_ticks_msec() < deadline:
		await process_frame
	_eq(_last_write(office), "UNKNOWN", "the key timed out: unknown")
	# Hold the card's first read on return, so the card can be seen before it.
	card.visible = false
	await _until(func() -> bool: return not card.reading(), "the card's reads stop")
	_ctl("control-b", "next", {"action": "delay", "method": "pane.read", "seconds": 1.5})
	await _pick_bee(office, "alpha:p3")
	card.visible = true
	await _frames(2)
	_eq(card.outcome_text(), "Unknown result: look first", "back on its pane, the card still says so")
	_eq(card.keys_refusal(), CommandRefusal.Reason.LOOK_FIRST, "every key is off")
	_check(not card.answer_offered() and not _control(office, "AnswerButton").is_visible_in_tree(), "no answering")
	_check(_switch(office).disabled, "nor the switch")
	await _until(card.answer_offered, "a fresh read, shown, turns them back on")
	_eq(_count("control-b", "pane.send_keys"), 1, "and nothing was sent again")


## A draft belongs to its pane and terminal: another desk takes the card out of
## answer mode and the box, Enter there sends nothing and shows an empty box;
## back on the first desk the draft is back; a new terminal in its pane drops it.
func test_a_draft_stays_with_its_pane() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("hello there")
	_eq(box.text, "hello there", "typed")
	await _pick_bee(office, "alpha:p1")
	_check(not card.answering() and not box.has_focus(), "another desk: no answer mode, no box focus")
	_eq(box.text, "", "its box is empty")
	await _tap(KEY_ENTER)
	await _wait(0.3)
	_eq(box.text, "", "Enter there shows no draft of another pane")
	_eq(_all_inputs(), 0, "and sends nothing")
	await _pick_bee(office, "alpha:p3")
	_eq(box.text, "hello there", "back: the draft is back")
	var binding := card.binding()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"terminal_id": "term-alpha-3-new"})})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.binding() != binding, "a new terminal in the pane")
	_eq(box.text, "", "the old terminal's draft is gone")
	await _click_visible_pane(office, HerdrFleet.pane_key(BEE, "alpha:p3"))
	_eq(box.text, "", "and does not come back for the new one")
	# Dropped, not merely hidden: even the old terminal's identity, were it to
	# come back, finds no draft.
	binding = card.binding()
	_ctl("control-b", "set_snapshot", {"snapshot": _raw()})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.binding() != binding, "the old identity again")
	await _click_visible_pane(office, HerdrFleet.pane_key(BEE, "alpha:p3"))
	_eq(box.text, "", "its draft was dropped when the terminal changed")
	_eq(_all_inputs(), 0, "nothing was sent all along")


## Tab from the reply box goes nowhere, and none of the actions takes keyboard
## focus; Escape leaves the box and answer mode, so a digit after it is no answer.
func test_the_reply_box_keeps_tab_and_escape_leaves_it() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	_check(box.has_focus(), "the box has the keyboard")
	await _tap(KEY_TAB)
	_eq(root.gui_get_focus_owner(), box, "Tab stays in the box")
	var shift_tab := InputEventKey.new()
	shift_tab.keycode = KEY_TAB
	shift_tab.physical_keycode = KEY_TAB
	shift_tab.shift_pressed = true
	shift_tab.pressed = true
	Input.parse_input_event(shift_tab)
	Input.flush_buffered_events()
	await _frames(2)
	_eq(root.gui_get_focus_owner(), box, "Shift-Tab too")
	await _tap(KEY_ESCAPE)
	_check(not card.answering() and not box.has_focus(), "Escape leaves the box and answer mode")
	await _tap(KEY_1)
	await _tap(KEY_Y)
	await _wait(0.5)
	_eq(_all_inputs(), 0, "a 1 and a y after Escape are no answers")


## Typing in the reply box never works the office (T, N, A, PageUp), nor
## answers; out of answer mode and the box, the card takes none of those keys.
func test_the_reply_box_and_the_office_keep_their_keys() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	var night := office.night
	var picked := office.picked_key
	var shown := office.navigator.shown_key
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("tna1y")
	await _tap(KEY_PAGEUP)
	await _tap(KEY_PAGEDOWN)
	_eq(box.text, "tna1y", "every key typed")
	_eq(
		[office.night, office.picked_key, office.navigator.shown_key, office.hud.holds_keyboard()],
		[night, picked, shown, false],
		"no light, no next, no floor, no agent list"
	)
	_eq(_all_inputs(), 0, "and no answer")
	await _tap(KEY_ESCAPE)
	_check(not card.answering(), "out of answer mode")
	await _tap(KEY_T)
	_check(office.night != night, "T is the office's again")
	await _tap(KEY_A)
	_check(office.hud.holds_keyboard(), "so is A")
	await _tap(KEY_A)
	_check(not office.hud.holds_keyboard(), "and A again")
	_eq(_all_inputs(), 0, "nothing was sent")


## Answer mode ends, and the reply box lets go, when the agent list takes the
## keyboard (`A`) and when another terminal takes the pane; a key button held
## down across that rebind sends nothing at its release: nothing reaches the
## boundary for it, not even a refused ticket.
func test_answer_mode_ends_on_attention_and_on_a_new_terminal() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	var box := _reply_box(office)
	await _open_answer(office)
	await _tap(KEY_A)
	_check(office.hud.holds_keyboard(), "A gives the agent list the keyboard from answer mode")
	_check(not card.answering(), "which ends answer mode")
	await _tap(KEY_A)
	_check(not office.hud.holds_keyboard() and not card.answering(), "letting go does not bring answer mode back")
	await _tap(KEY_1)
	await _wait(0.3)
	_eq(_all_inputs(), 0, "a 1 after it is no answer")
	# The list lets go of the keyboard to nobody: the chip opens answer mode
	# again.
	await _click_control(_control(office, "AnswerButton"))
	await _until(card.answering, "answer mode again, from the chip")
	await _click_control(box)
	await _type("draft")
	_check(box.has_focus(), "the box has the keyboard")
	var writes := office.fleet.write_log().size()
	var checked := _checks("control-b")
	var one := _key_button(office, "Key1")
	_half_click(one, true)
	await _frames(2)
	var binding := card.binding()
	var raw := _changed(_raw(), "alpha:p3", {"agent_status": "blocked", "terminal_id": "term-alpha-3-new"})
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.binding() != binding, "another terminal in the pane")
	_check(not card.answering(), "a new binding ends answer mode")
	_check(not box.has_focus(), "and the box lets go of the keyboard")
	_eq(card.outcome_text(), "Not sent: target changed", "the held key says so on the new binding, like the switch")
	_half_click(one, false)
	await _wait(0.5)
	_eq(office.fleet.write_log().size(), writes, "the release reached nothing: no ticket at all")
	_eq(_checks("control-b"), checked, "no re-read")
	_eq(_all_inputs(), 0, "and no key")


## AZERTY: the key at the US `6` position types `-`, the office's zoom out.
## In answer mode it zooms out and sends nothing, held or tapped; a key both at
## `6` and making `6` still answers. Answer keys go by the position and the
## layout's key together, never by either alone.
func test_an_azerty_minus_zooms_out_and_sends_nothing() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	office.zoom = 4
	await _tap(KEY_MINUS, KEY_6)
	await _wait(0.5)
	_eq(_inputs("control-b").size(), 0, "the AZERTY - at the 6 position sends nothing")
	_eq(office.zoom, 2, "it zooms out, as the office's -")
	_check(card.answering(), "and answer mode stays open")
	await _hold(KEY_MINUS, 3, KEY_6)
	await _wait(0.5)
	_eq(_inputs("control-b").size(), 0, "held, with its echoes: nothing")
	await _tap(KEY_6)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "a 6 that is a 6")
	var six: Dictionary = _inputs("control-b")[0]
	_eq(six.get("keys"), ["6"], "sends 6")


## QWERTZ: the key labelled Z sits at the US `y` position, and the key labelled
## Y at the US `z` position. Neither answers: the first is a Z, the second is not
## at the answer key's position. Fail closed: `y` goes by its button there.
func test_a_qwertz_z_or_y_sends_nothing() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	await _tap(KEY_Z, KEY_Y)
	await _tap(KEY_Y, KEY_Z)
	await _wait(0.8)
	_eq(_inputs("control-b").size(), 0, "neither the Z at y's place nor the Y at z's place answers")
	_check(card.answering(), "answer mode stays open")
	await _click_control(_key_button(office, "KeyY"))
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "the y button")
	var y: Dictionary = _inputs("control-b")[0]
	_eq(y.get("keys"), ["y"], "the button sends y")


## A line that herdr took while the card was on another desk is no draft when
## the card comes back: the box is empty, and no look turns it into a resend.
func test_a_line_that_went_is_no_draft_on_return() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("yes delete them")
	_ctl("control-b", "next", {"action": "delay", "method": "agent.prompt", "seconds": 1.5})
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return _last_write(office) == "SENT", "the line is out")
	await _pick_bee(office, "alpha:p1")
	await _until(func() -> bool: return _last_write(office) == "ACCEPTED", "herdr took it, the card elsewhere")
	await _pick_bee(office, "alpha:p3")
	await _frames(3)
	_eq(box.text, "", "back: the line that went is not in the box")
	await _until(card.answer_offered, "a look later, answers are on again")
	_eq(box.text, "", "still empty after the look")
	_eq(card.line_refusal(), CommandRefusal.Reason.LINE_BLANK, "Send line has nothing to send")
	await _open_answer(office)
	await _click_control(_key_button(office, "SendLine"))
	await _wait(0.5)
	_eq(_inputs("control-b").size(), 1, "it went once, and only once")


## Text typed into the box while a line is out is a new draft: when the line
## is accepted, the box keeps it (and only the line that went is dropped).
func test_text_typed_while_a_line_is_out_stays() -> void:
	var office := await _idle_bee()
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("first")
	_ctl("control-b", "next", {"action": "delay", "method": "agent.prompt", "seconds": 1.5})
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return _last_write(office) == "SENT", "the line is out")
	await _type(" second")
	_eq(box.text, "first second", "typing went on while the line was out")
	await _until(func() -> bool: return _last_write(office) == "ACCEPTED", "herdr took it")
	await _frames(3)
	_eq(box.text, "first second", "the box keeps what was typed after the line went")
	var sent: Dictionary = _inputs("control-b")[0]
	_eq([_inputs("control-b").size(), sent.get("text")], [1, "first"], "the line that went is the one aimed at")


## A write to one terminal is not another's news: once a new terminal takes the
## pane id, the card says "New terminal: pick again", not the old "Sent"; picked
## again, it never shows that "Sent" as this terminal's, and once the look is
## taken on the new terminal the old outcome is gone.
func test_a_new_terminal_does_not_inherit_the_old_ones_outcome() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return _last_write(office) == "ACCEPTED", "the key went")
	await _frames(3)
	_eq(card.outcome_text(), "Sent", "the card says what became of it")
	var binding := card.binding()
	var raw := _changed(_raw(), "alpha:p3", {"agent_status": "blocked", "terminal_id": "term-new"})
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.binding() != binding, "a new terminal in the pane")
	await _frames(3)
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	_eq(card.outcome_text(), "New terminal: pick again", "the new terminal is said, not the old Sent")
	_check(office.fleet.must_look(key), "the pane still owes its look")
	await _click_visible_pane(office, key)
	await _frames(3)
	_check(card.outcome_text() != "Sent", "picked again: the old Sent is not this terminal's: " + card.outcome_text())
	await _until(card.answer_offered, "the look, taken on the new terminal")
	_eq(card.outcome_text(), "", "after the look the old outcome is gone")
	_eq(_count("control-b", "pane.send_keys"), 1, "one key, sent once")


## Leaving while an answer is out and coming back before it ends: when it ends
## unknown, the card on the same pane says so, with every write off, and never
## "No switch" for what the answers are waiting on.
func test_back_before_an_answer_ends_still_hears_how_it_ended() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	_ctl("control-b", "next", {"action": "hang", "method": "pane.send_keys"})
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return _last_write(office) == "SENT", "the key is out")
	await _pick_bee(office, "alpha:p1")
	await _pick_bee(office, "alpha:p3")
	var deadline := Time.get_ticks_msec() + int((HerdrCommands.INPUT_TIMEOUT + 3.0) * 1000)
	while _last_write(office) != "UNKNOWN" and Time.get_ticks_msec() < deadline:
		await process_frame
	await _frames(3)
	_eq(_last_write(office), "UNKNOWN", "the key timed out")
	_eq(card.outcome_text(), "Unknown result: look first", "the card that came back says so")
	_check(not card.answer_offered(), "with the answers off")
	_eq(card.keys_refusal(), CommandRefusal.Reason.LOOK_FIRST, "until a look")
	_check(not card.outcome_text().begins_with("No switch"), "never 'No switch' for it")
	_eq(_count("control-b", "pane.send_keys"), 1, "and it was not sent again")


## Text typed while "Send line" is held down is not what was aimed at: the
## release sends nothing and says why. A clean click then sends the whole line.
## (An input method still composing is refused the same way at the press or the
## release; that cannot be driven headless.)
func test_a_line_edited_under_the_press_is_not_sent() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("ok")
	var send := _key_button(office, "SendLine")
	var writes := office.fleet.write_log().size()
	_half_click(send, true)
	await _frames(2)
	await _type("x")
	_check(box.has_focus() and box.text == "okx", "typing went on in the box: " + box.text)
	_half_click(send, false)
	await _frames(3)
	_eq(card.outcome_text(), "Not sent: the line changed", "refused at the release")
	_eq(office.fleet.write_log().size(), writes, "nothing reached the boundary")
	await _click_control(send)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "a clean click")
	var line: Dictionary = _inputs("control-b")[0]
	_eq(line.get("text"), "okx", "sends the line as it stands")


## A line that changes the agent's session (`/clear`) makes the pane a new
## identity, and the look it owes is owed all the same: no read asked for less
## than LOOK_DELAY_MSEC after the write ended turns writes back on, whatever
## terminal or session it reads. The rule's clock is the boundary's own
## (HerdrCommands.clock), held still here, so nothing depends on how fast the
## machine runs. First at the boundary, to the millisecond; then through the
## card, by real input: the re-pick of the desk under its new session meets the
## same rule, until the clock moves on.
func test_a_write_that_changes_the_session_still_waits_for_a_look() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "done.\n$ \n"})
	var cleared := {"source": "fixture", "agent": "codex", "kind": "session_id", "value": "fake-session-alpha-3-new"}
	var socket: String = args["socket-a"]
	var facts := _facts(socket, _raw())
	var after := _facts(socket, _changed(_raw(), "alpha:p3", {"agent_session": cleared}))
	var commands := _boundary()
	var now: Array[int] = [100000]
	commands.clock = func() -> int: return now[0]
	var seen := _seen(commands, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	var line := commands.submit(_aim(facts, "alpha:p3").replying("/clear", seen), facts, _facts_now(facts))
	_settle(commands, line, "the /clear line")
	_eq(line.state, CommandTicket.State.ACCEPTED, "the line went")
	var target := _aim(after, "alpha:p3")
	_check(target.identity_key != line.context.identity_key, "the pane holds a new session now")
	var looks: Array = [
		[0, true, "a read asked for at the settle"], [HerdrCommands.LOOK_DELAY_MSEC - 1, true, "1 ms short"]
	]
	looks.append([HerdrCommands.LOOK_DELAY_MSEC, false, "LOOK_DELAY_MSEC after"])
	for look: Array in looks:
		var at: int = look[0]
		var owed: bool = look[1]
		var what: String = look[2]
		now[0] = 100000 + at
		var read := commands.submit(target.reading(CommandContext.SOURCE_RECENT, 12), after)
		_settle(commands, read, what)
		commands.saw(read)
		var next := target.replying("next", CommandPreview.of(read, 2))
		_eq(
			commands.blocker(next),
			CommandRefusal.Reason.LOOK_FIRST if owed else CommandRefusal.Reason.NONE,
			"%s, of the new session: %s" % [what, "still owed" if owed else "looked"]
		)
	commands.free()
	# Through the card. The office's boundary clock stands still from here.
	var office := await _idle_bee()
	var card := _card(office)
	var boundary: HerdrCommands = office.fleet.get_node("Commands")
	var frozen: Array[int] = [Time.get_ticks_msec()]
	boundary.clock = func() -> int: return frozen[0]
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("/clear")
	await _click_control(_key_button(office, "SendLine"))
	await _until(func() -> bool: return _last_write(office) == "ACCEPTED", "the line went, from the card")
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_session": cleared})})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var identity := office.frame.pane(key).identity_key()
	await _until(
		func() -> bool: return office.frame.pane(key).identity_key() != identity, "the pane holds a new session"
	)
	await _click_visible_pane(office, key)
	var reads := _count("control-b", "pane.read")
	await _until(
		func() -> bool: return _count("control-b", "pane.read") > reads and not card.reading(),
		"a read after the re-pick"
	)
	await _until(
		func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "and it is shown"
	)
	_check(office.fleet.must_look(key), "the pane still owes a look")
	_eq(card.line_refusal(), CommandRefusal.Reason.LOOK_FIRST, "so the re-picked card sends no line")
	_check(not card.answer_offered(), "and offers no answer")
	frozen[0] += HerdrCommands.LOOK_DELAY_MSEC
	await _until(card.answer_offered, "the next read, asked for once the clock moved on, is the look")


## A line typed into the box and "Send line", to an idle agent: its recent
## output is read again, then the line and Enter go as one request; the box
## empties.
func test_a_line_typed_and_sent_to_an_idle_agent() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("hi there")
	var send := _key_button(office, "SendLine")
	_eq(
		send.tooltip_text.get_slice("\n", 0),
		"Send one line to this agent on bee: herdr types it and presses Enter (bracketed when the agent asked). 8 of 1024 bytes.",
		""
	)
	_check(not send.disabled, "Send line is on")
	await _click_control(send)
	await _until(func() -> bool: return card.outcome_text() == "Sent", "herdr took the line")
	_eq(
		_writes_seen("control-b"),
		PackedStringArray(["pane.read recent_unwrapped 12 check", "agent.prompt 8 bytes"]),
		"the output read again, then the line and Enter"
	)
	var inputs := _inputs("control-b")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("pane_id"), input.get("text"), input.get("keys")], ["alpha:p3", "hi there", ["enter"]], "")
	_eq(box.text, "", "the box empties")
	var entry: CommandAuditEntry = office.fleet.write_log().back()
	_eq([entry.method, entry.line_bytes], ["agent.prompt", 8], "audited by size")


## A line the send port would refuse is refused on the card first: "Send line"
## is off and the result line says why; a click sends nothing.
func test_a_refused_line_is_refused_on_the_card() -> void:
	var office := await _idle_bee()
	var card := _card(office)
	await _open_answer(office)
	var box := _reply_box(office)
	await _click_control(box)
	await _type("ok" + char(0x200b) + "go")
	_eq(card.line_refusal(), CommandRefusal.Reason.LINE_INVISIBLE, "an invisible character")
	var send := _key_button(office, "SendLine")
	_check(send.disabled, "Send line is off")
	_eq(card.outcome_text(), "Line: invisible character", "and the card says why")
	await _click_control(send)
	await _wait(0.3)
	_eq(_all_inputs(), 0, "a click sends nothing")
	_eq(_writes_seen("control-b"), PackedStringArray(), "nor reads anything again for it")


## A shell takes no answer at all, a working agent no line and no key, a
## blocked one keys but no line: the card offers only what the pane may
## receive, and Enter opens nothing on a pane that may receive nothing.
func test_the_card_offers_only_what_the_pane_may_receive() -> void:
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	var office := await _office_with()
	var card := _card(office)
	var fleet := office.fleet
	await _pick_bee(office, "alpha:p2")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "a shell")
	_check(not card.answer_offered() and not _control(office, "AnswerButton").is_visible_in_tree(), "no answering")
	await _tap(KEY_ENTER)
	_check(not card.answering(), "Enter opens nothing on a shell")
	var shell := HerdrFleet.pane_key(BEE, "alpha:p2")
	_eq(fleet.can_operate(shell, CommandContext.Kind.KEYS), CommandRefusal.Reason.NOT_AN_AGENT, "no keys to a shell")
	_eq(fleet.can_operate(shell, CommandContext.Kind.LINE), CommandRefusal.Reason.NOT_AN_AGENT, "no line to a shell")
	await _pick_bee(office, "alpha:p1")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "working")
	_check(not card.answer_offered(), "a working agent: nothing to answer")
	_eq(card.line_refusal(), CommandRefusal.Reason.AGENT_BUSY, "no line: it is busy")
	_eq(card.keys_refusal(), CommandRefusal.Reason.NOT_ASKING, "no keys: it asks nothing")
	await _pick_bee(office, "alpha:p3")
	await _until(card.answer_offered, "a blocked agent")
	await _open_answer(office)
	_check(not _key_button(office, "Key1").disabled, "keys on")
	_check(_key_button(office, "SendLine").disabled, "Send line off")
	_eq(card.line_refusal(), CommandRefusal.Reason.AGENT_ASKING, "a line's Enter could confirm the default")
	_eq(card.outcome_text(), "", "while a key may be pressed, nothing to explain")
	await _wait(0.3)
	_eq(_all_inputs(), 0, "nothing sent")


## The whole question is read (lines 200) and compared, not only the 12 rows
## the card shows: 31 rows, "12 of 31 rows", and a change in row 1, which the
## card does not show, stops the key. A row wider than the card says "clipped".
func test_the_whole_question_is_compared_not_just_the_rows_shown() -> void:
	var rows := PackedStringArray()
	for index in 31:
		rows.append("row %d of the question" % (index + 1))
	var question := "\n".join(rows) + "\n"
	var office := await _blocked_bee(question)
	var card := _card(office)
	_check(card.preview_caption().begins_with("12 of 31 rows · "), "the caption says so: " + card.preview_caption())
	var last: Dictionary = _asked("control-b", "pane.read").back()
	_eq([last.get("source"), _number(last, "lines")], ["detection", 200.0], "the whole of it was read")
	var changed := {"pane_id": "alpha:p3", "source": "detection", "text": question.replace("row 1 of", "row 1 in")}
	var stage := {"action": "stage", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "preview": changed}
	_ctl("control-b", "next", stage)
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return not card.writing(), "the key settles")
	_eq(card.outcome_text(), "Not sent: the terminal changed, look again", "not sent, and the card says why")
	_check(card.answering(), "nothing went: answer mode stays, saying so")
	_eq(_writes_seen("control-b"), PackedStringArray(["pane.read detection 200 check"]), "read again, nothing written")
	_eq(_all_inputs(), 0, "no key")
	var wide := question + "x".repeat(200) + "\n"
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": wide})
	await _until(func() -> bool: return card.preview_text() == wide, "a wide row")
	await _until(
		func() -> bool: return card.preview_caption().ends_with("clipped"), "clipped: " + card.preview_caption()
	)
	_check(card.preview_caption().begins_with("12 of 32 rows"), "still the count: " + card.preview_caption())


## The agent stops asking between the press and the re-read: the key is refused
## with what the fleet knows by then, and nothing is written.
func test_a_state_flip_before_the_send_refuses_the_key() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	var flip := {"pane_id": "alpha:p3", "agent_status": "working"}
	var stage := {
		"action": "stage",
		"method": "pane.read",
		"id_suffix": HerdrCommands.CHECK_SUFFIX,
		"status": flip,
		"seconds": 0.5
	}
	_ctl("control-b", "next", stage)
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return not card.writing(), "the key settles")
	_eq(card.outcome_text(), "Not sent: not asking", "refused: the agent stopped asking")
	_eq(_writes_seen("control-b"), PackedStringArray(["pane.read detection 200 check"]), "nothing written")
	_eq(_all_inputs(), 0, "no key")


## A press held while the card shows a newer read: the release is refused on
## the card itself, even though the newer read says the same, and nothing at
## all goes to herdr for it, not even a re-read.
func test_a_press_held_across_a_new_read_sends_nothing() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	var one := _key_button(office, "Key1")
	var reads := _count("control-b", "pane.read")
	_half_click(one, true)
	await process_frame
	# A blocked card reads every second: wait for one to be shown under the press.
	await _until(func() -> bool: return _count("control-b", "pane.read") > reads + 1, "a newer read, shown")
	await _until(func() -> bool: return not card.reading(), "and settled")
	await _frames(2)
	_half_click(one, false)
	await _frames(4)
	_eq(card.outcome_text(), "Not sent: the terminal changed, look again", "refused at the release")
	_eq(_writes_seen("control-b"), PackedStringArray(), "nothing reached herdr for it")
	_eq(_all_inputs(), 0, "no key")


## The documented residual risk, as a regression case: the question changes
## after the re-read, or to one that reads the same. Nothing on the client can
## tell, so the key goes; what the viewer had was the best-effort line.
func test_same_text_a_to_b_is_sent_and_the_card_says_it_can_change() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	# Question B reads exactly like A where it is compared.
	var same := {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION}
	var stage := {"action": "stage", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "preview": same}
	_ctl("control-b", "next", stage)
	await _open_answer(office)
	var best: Label = _control(office, "BestEffort")
	_check(best.is_visible_in_tree() and best.text.ends_with("it can still change"), "the line says it can change")
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the key went")
	_eq(_inputs("control-b").size(), 1, "sent: the documented limit of a re-read, not a bug")


## At the smallest screen the HUD fits (480x320) the card is the staff panel's
## line along the bottom, and answer mode takes its full height: Enter opens it
## up (the question has to be read and shown first), a second Enter opens
## answer mode, 448x128, with a refusal in two lines, while the drawer's list
## (opened by a real click on its tab) stays open. No visible control leaves
## the panel, nothing overlaps along any row or column, and the preview keeps
## its 12 rows. Escape leaves answer mode and leaves the panel open; a second
## Escape folds it.
func test_answer_mode_fits_the_smallest_screen() -> void:
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION})
	var office := await _office_with(false, true, true, Vector2(480, 320))
	await _pick_bee(office, "alpha:p3", false)
	var card := _card(office)
	var tab: Control = office.hud.get_node("%DrawerTab")
	await _click_control(tab)
	await _frames(3)
	var list := office.hud.agent_list
	var scroll: ScrollContainer = list.get_node("%Scroll")
	_check(office.hud.card_compact() and list.is_visible_in_tree(), "picked: a compact line, the list beside")
	_panels_apart(office, "compact")
	# Six rows: the Waiting and Unread headers and four agents under them.
	_check(scroll.size.y >= 6 * 18, "the list shows at least six rows: %.0f units" % scroll.size.y)
	await _tap(KEY_ENTER)
	await _until(
		func() -> bool: return card.preview_text() == QUESTION and card.answer_offered(), "the question is shown"
	)
	await _frames(3)
	_check(list.is_visible_in_tree() and office.hud.drawer_open(), "the opened panel leaves the list open")
	_check(_control(office, "AnswerButton").is_visible_in_tree(), "the Answer chip shows")
	_fits(card, "outside answer mode")
	_panels_apart(office, "opened up")
	var changed := {"pane_id": "alpha:p3", "source": "detection", "text": QUESTION + "> 3. Other\n"}
	var stage := {"action": "stage", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "preview": changed}
	_ctl("control-b", "next", stage)
	await _open_answer(office)
	await _frames(3)
	_eq(office.hud.placed(card).size, Vector2(448, 128), "the card at 480x320 in answer mode")
	_eq(office.hud.world_rect().size, Vector2(216, 112), "the world above it keeps a desk's room, the drawer open")
	_fits(card, "answer mode")
	# The minimap keeps to the room between the bar and the panel, and scrolls.
	var floors := office.hud.floors
	_eq(floors.get_global_rect(), Rect2(16, 40, 72, 120), "the rail stands left 40..160, grown neither way")
	var rows: ScrollContainer = floors.get_node("%Scroll")
	_check(rows.get_v_scroll_bar().max_value > rows.size.y, "and scrolls the rows it has no room for")
	_panels_apart(office, "answer mode")
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return card.outcome_text().begins_with("Not sent: the terminal"), "a refusal")
	await _frames(3)
	var outcome: Label = card.get_node("%Outcome")
	_eq(outcome.get_visible_line_count(), 2, "the refusal takes its two lines, whole")
	_fits(card, "answer mode, a refusal in two lines")
	_panels_apart(office, "a refusal")
	var preview: Label = card.get_node("%Preview")
	_eq(preview.get_visible_line_count(), OfficePaneInspector.PREVIEW_ROWS, "the preview keeps its 12 rows")
	if card.answering():
		await _tap(KEY_ESCAPE)
		await _frames(2)
	_check(not card.answering() and not office.hud.card_compact(), "out of answer mode the panel stays open")
	_panels_apart(office, "answer mode left")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(office.hud.card_compact() and list.is_visible_in_tree(), "a second Escape folds the panel back")
	_panels_apart(office, "folded back")
	_eq(_all_inputs(), 0, "nothing was sent")


## The Escape ladder: in answer mode Escape only leaves answer mode, and
## the panel stays open with its details; out of it, Escape folds the panel to
## its line; one more Escape changes nothing. By real keys; nothing is sent.
func test_escape_leaves_answer_mode_first_and_folds_the_panel_second() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	_check(not office.hud.card_compact(), "answer mode stands at full height")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(not card.answering(), "the first Escape leaves answer mode")
	_check(not office.hud.card_compact(), "and leaves the panel open")
	_check(_control(office, "Detail").is_visible_in_tree(), "with its details")
	_check(_control(office, "FoldButton").is_visible_in_tree(), "and `▾ Esc` shown")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(office.hud.card_compact(), "the second Escape folds it to its line")
	_check(_control(office, "CompactRow").is_visible_in_tree(), "the line")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(office.hud.card_compact() and not card.answering(), "a third changes nothing")
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "alpha:p3"), "the pick stays")
	_eq(_all_inputs(), 0, "nothing was sent")


## A key sent from answer mode ends answer mode by itself; at the 480x320
## minimum the panel stays open, so its outcome ("Sent") stays in sight
## (invariant 12: the result is shown as it is), with the switch and NEW PANE
## BESIDE back beside it. Exactly one key went.
func test_a_sent_key_leaves_the_panel_open_with_its_outcome() -> void:
	var office := await _blocked_bee(QUESTION, Vector2(480, 320))
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the key went")
	await _until(func() -> bool: return not card.answering(), "answer mode ends by itself")
	await _frames(3)
	_check(not office.hud.card_compact(), "the panel stays open")
	var outcome: Label = card.get_node("%Outcome")
	_check(outcome.is_visible_in_tree(), "its outcome in sight")
	_eq(outcome.text, "Sent", "saying what became of the key")
	_check(_switch(office).is_visible_in_tree(), "Switch herdr here is back")
	_eq(_inputs("control-b").size(), 1, "one key")
	await _frames(10)
	_check(not office.hud.card_compact() and outcome.is_visible_in_tree(), "and it stays so")
	_eq(_inputs("control-b").size(), 1, "still one")


## Zero gestures, zero writes, with answer mode open on a blocked agent and a
## draft typed: refreshes, status changes, events and seconds of reading.
func test_answer_mode_writes_nothing_without_a_gesture() -> void:
	var office := await _blocked_bee()
	var card := _card(office)
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("draft")
	for index in 30:
		office.refresh()
	for status: String in ["working", "blocked", "done", "blocked"]:
		_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": status})
		await _wait(0.4)
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _wait(3.0)
	_check(_count("control-b", "pane.read") > 3, "it read all along")
	_eq(_all_inputs(), 0, "and wrote nothing")
	_eq(_writes_seen("control-b"), PackedStringArray(), "not even a re-read for one")
	_check(card.answering(), "answer mode stayed open")


# --- helpers only these cases use ------------------------------------------------


## How many input re-reads fake `which` has been asked for.
func _checks(which: String) -> int:
	return Array(_sequence(which)).filter(func(entry: String) -> bool: return entry.ends_with(" check")).size()


## Every visible control of `card` inside its frame, and in every row and
## column of it (each BoxContainer: the details beside one another, the answer
## rows under one another) the parts one after another, none overlapping, each
## at its whole size: `what` names the state. The details list is left out: it
## clips its own rows by design.
func _fits(card: OfficePaneInspector, what: String) -> void:
	var frame: Control = card.get_node("Frame/Row")
	var bounds := frame.get_global_rect().grow(0.5)
	var more: Control = card.get_node("%More")
	var outside := PackedStringArray()
	for node: Node in card.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree() or control == more or more.is_ancestor_of(control):
			continue
		if control == frame or control.is_ancestor_of(frame):
			continue
		if not bounds.encloses(control.get_global_rect()):
			outside.append("%s %s" % [card.get_path_to(control), control.get_global_rect()])
	_eq(outside, PackedStringArray(), what + ": every control inside the card")
	for node: Node in card.find_children("*", "BoxContainer", true, false):
		var box: BoxContainer = node
		if not box.is_visible_in_tree() or more.is_ancestor_of(box):
			continue
		var axis := 1 if box.vertical else 0
		var edge := box.get_global_rect().position[axis]
		for child: Node in box.get_children():
			if not child is Control:
				continue
			var part: Control = child
			if not part.visible:
				continue
			var rect := part.get_global_rect()
			_check(rect.position[axis] >= edge - 0.5, "%s: %s starts after the one before it" % [what, part.name])
			_check(
				rect.size[axis] >= part.get_combined_minimum_size()[axis] - 0.5,
				"%s: %s has its whole size" % [what, part.name]
			)
			edge = rect.end[axis]
		_check(edge <= box.get_global_rect().end[axis] + 0.5, "%s: %s ends inside itself" % [what, box.name])


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation but one a case provoked on purpose.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)
