extends "res://tools/command_test_base.gd"
## The write boundary (HerdrCommands, reached through HerdrFleet), the agent
## card's terminal preview and its one write, and `--read-only`, against two
## fake herdrs of this suite's own whose pane ids collide. The terminal
## monitor's raw mode is tools/test_raw_input.gd's. Run through
## tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_commands.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## The boundary's transport cases pump a HerdrCommands outside the tree on
## synthetic time, the way tools/test_client.gd pumps its client; everything
## the card does runs in a live office on real frames, driven by real input.
## The last case sums up both fakes: nothing reached them that no case opened.


func _marker() -> String:
	return "COMMAND TESTS"


# --- the boundary --------------------------------------------------------------


## Only scripts/herdr_commands.gd may name a herdr method beyond ping, snapshot
## and subscribe, and it names exactly the allowlist the fixture records. The
## list is herdr 0.9.0's own (tools/fixtures/herdr_methods.json).
func test_only_the_command_module_names_herdr_methods() -> void:
	var methods := _schema_methods()
	_check(methods.size() > 90, "herdr's method list is loaded: %d" % methods.size())
	_eq(_named(' var x := "pane.send_keys"', methods), ["pane.send_keys"], "the scan finds a quoted method")
	_eq(_named('"pane.focused"', methods), [], "an event that begins like a method is not one")
	var allowlist := _schema_allowlist()
	_eq(
		allowlist,
		[
			"agent.get",
			"agent.prompt",
			"agent.start",
			"pane.close",
			"pane.focus",
			"pane.read",
			"pane.send_input",
			"pane.send_keys",
			"pane.send_text",
			"pane.split",
			"workspace.create",
			"worktree.create"
		],
		"the fixture's allowlist"
	)
	_check(allowlist.all(func(method: String) -> bool: return method in methods), "each one a method herdr has")
	_eq(
		OPERABLE.duplicate().map(func(method: String) -> String: return method),
		[
			"pane.read",
			"pane.focus",
			"pane.send_keys",
			"pane.send_input",
			"pane.send_text",
			"agent.prompt",
			"agent.start",
			"pane.split",
			"agent.get",
			"pane.close",
			"workspace.create",
			"worktree.create"
		],
		"what the fakes may open is that allowlist"
	)
	var offenders := PackedStringArray()
	for path in _gd_files("res://scripts"):
		var named := _named(FileAccess.get_file_as_string(path), methods)
		if path == "res://scripts/herdr_commands.gd":
			_eq(named, allowlist, "the command module names exactly its allowlist")
			continue
		for method: String in named:
			if not method in READ_ONLY_METHODS:
				offenders.append("%s names %s" % [path, method])
	_eq(offenders, PackedStringArray(), "no other file under scripts/ names a method beyond the read-only three")


## Anything outside the allowlist is refused before a socket is opened.
func test_the_allowlist_refuses_before_any_socket() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p1")
	var refused: Array[CommandContext] = [
		target,
		target.reading("visible", 12),
		target.reading("recent", 12),
		target.reading(CommandContext.SOURCE_RECENT, 0),
		target.reading(CommandContext.SOURCE_RECENT, 201),
	]
	for context in refused:
		_eq(
			HerdrCommands.refusal(context, facts),
			CommandRefusal.Reason.NOT_ALLOWED,
			"refused: %s %d" % [context.source, context.lines]
		)
	var allowed: Array[CommandContext] = [
		target.reading(CommandContext.SOURCE_RECENT, 1),
		target.reading(CommandContext.SOURCE_DETECTION, 200),
		target.focusing(),
	]
	for context in allowed:
		_eq(
			HerdrCommands.refusal(context, facts),
			CommandRefusal.Reason.NONE,
			"allowed: %s %d" % [context.source, context.lines]
		)
	var commands := _boundary()
	var ticket := commands.submit(target.reading("visible", 12), facts)
	_eq(
		[ticket.state, ticket.refusal],
		[CommandTicket.State.REFUSED, CommandRefusal.Reason.NOT_ALLOWED],
		"refused at once"
	)
	_eq(commands.open_count(), 0, "nothing was opened")
	_eq(commands.read_log()[0].refusal, "NOT_ALLOWED", "and the audit says why")
	await _frames(2)
	_eq(_count("control-a", "pane.read"), 0, "herdr never heard of it")
	commands.free()


## herdr's `pane.read` answer is nested under `read`; exactly the allowlisted
## payload goes out, with herdr's own spelling of the pane id.
func test_a_read_parses_herdr_s_nested_result() -> void:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "one\ntwo\n"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var ticket := commands.submit(_aim(facts, "alpha:p3").reading(CommandContext.SOURCE_RECENT, 12), facts)
	_eq(ticket.state, CommandTicket.State.UNSENT, "queued: it goes out on the next frame")
	_settle(commands, ticket, "the read")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "accepted")
	if ticket.read != null:
		_eq(
			[ticket.read.pane_id, ticket.read.source, ticket.read.text],
			["alpha:p3", "recent_unwrapped", "one\ntwo\n"],
			"read"
		)
		_eq([ticket.read.truncated, ticket.read.cut], [false, false], "nothing cut")
	var asked := _asked("control-a", "pane.read")
	_eq(asked.size(), 1, "one request")
	if asked.size() == 1:
		var params: Dictionary = asked[0]
		_eq(params.keys().size(), 5, "no other field")
		_eq(
			[params.get("pane_id"), params.get("source"), params.get("format"), params.get("strip_ansi")],
			["alpha:p3", "recent_unwrapped", "text", true],
			"the allowlisted payload"
		)
		_eq(_number(params, "lines"), 12.0, "exactly the rows the card shows")
	commands.free()


## Terminal text is remote input: controls and bidi overrides go, `\n` and `\t`
## stay, and over 64 KiB only the tail is kept, cut at a character boundary.
func test_a_read_is_cleaned_and_keeps_only_its_tail() -> void:
	_fakes()
	var dirty := "a\u0007b\tc\r\nd\u202ee\u2066f\u2069\u0085g\u2028h\n"
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p1", "text": dirty, "truncated": true})
	var long := "h\u00e9llo\n" + "\u00df".repeat(40000) + "\nEND\n"
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "text": long})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var cleaned := commands.submit(_aim(facts, "alpha:p1").reading(CommandContext.SOURCE_RECENT, 12), facts)
	_settle(commands, cleaned, "the dirty read")
	_eq(cleaned.state, CommandTicket.State.ACCEPTED, "accepted")
	if cleaned.read != null:
		_eq(cleaned.read.text, "ab\tc\ndefgh\n", "controls and bidi overrides gone, newline and tab kept")
		_eq([cleaned.read.truncated, cleaned.read.cut], [true, false], "herdr's own truncation, separate from ours")
	var tailed := commands.submit(_aim(facts, "alpha:p3").reading(CommandContext.SOURCE_RECENT, 12), facts)
	_settle(commands, tailed, "the long read")
	_eq(tailed.state, CommandTicket.State.ACCEPTED, "accepted")
	if tailed.read != null:
		var kept := tailed.read.text.to_utf8_buffer().size()
		_check(
			kept <= PaneReadResult.TEXT_MAX and kept > PaneReadResult.TEXT_MAX - 4, "the last 64 KiB: %d bytes" % kept
		)
		_check(tailed.read.text.begins_with("\u00df"), "cut at a character boundary, never inside one")
		_check(tailed.read.text.ends_with("\nEND\n"), "the tail is what is kept")
		_eq([tailed.read.cut, tailed.read.truncated], [true, false], "cut here, not by herdr")
		_eq(tailed.read.bytes, long.to_utf8_buffer().size(), "the audit's byte count is what herdr sent")
	commands.free()


## A command that times out, is dropped after herdr carried it out, or is cut
## mid-answer ends UNKNOWN; herdr refusing ends REJECTED. None is ever retried.
func test_a_lost_answer_ends_unknown_and_nothing_is_retried() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "hang", "method": "pane.focus"})
	var hung := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_settle(commands, hung, "the timeout", 0.5)
	_eq(
		[hung.state, hung.failure],
		[CommandTicket.State.UNKNOWN, "no answer in time"],
		"timed out: it may have happened"
	)
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "pane.focus"})
	var dropped := commands.submit(_aim(facts, "alpha:p3").focusing(), facts)
	_settle(commands, dropped, "the dropped answer")
	_eq(dropped.state, CommandTicket.State.UNKNOWN, "dropped after herdr did it")
	_eq(_ctl("control-a", "stats").get("focused_pane_id"), "alpha:p3", "herdr did act on it")
	_ctl("control-a", "next", {"action": "close_midreply", "method": "pane.focus"})
	var halved := commands.submit(_aim(facts, "bravo:p1").focusing(), facts)
	_settle(commands, halved, "the half answer")
	_eq(halved.state, CommandTicket.State.UNKNOWN, "cut mid-answer")
	# alpha:p1's write ended unknown: nothing more goes to it before a look.
	var unlooked := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_eq(unlooked.refusal, CommandRefusal.Reason.LOOK_FIRST, "not before a look at alpha:p1")
	await _look(commands, facts, "alpha:p1")
	_ctl("control-a", "next", {"action": "refuse", "method": "pane.focus", "code": "busy", "message": "not now"})
	var rejected := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_settle(commands, rejected, "the refusal")
	_eq(
		[rejected.state, rejected.error_code, rejected.error_message],
		[CommandTicket.State.REJECTED, "busy", "not now"],
		"rejected"
	)
	await _frames(3)
	_eq(_count("control-a", "pane.focus"), 4, "four sent, none again, the unlooked one never")
	var states := commands.write_log().map(func(entry: CommandAuditEntry) -> String: return entry.last_state())
	_eq(states, ["UNKNOWN", "UNKNOWN", "UNKNOWN", "REFUSED", "REJECTED"], "the audit agrees")
	commands.free()


## No socket, no command: CANCELLED, never SENT, and so safe to ask again.
func test_an_unreachable_socket_cancels_the_command() -> void:
	var facts := _facts(args.work.path_join("nobody-here.sock"), _raw())
	var commands := _boundary()
	var ticket := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_eq(ticket.state, CommandTicket.State.CANCELLED, "never sent: its socket is not there")
	_eq(commands.open_count(), 0, "and nothing stays open")
	_eq(commands.write_log()[0].states, PackedStringArray(["CANCELLED"]), "the audit never saw it go out")
	commands.free()


## A machine that closes, drops or is replaced settles every open command:
## UNKNOWN once sent, CANCELLED before. Nothing stays SENT.
func test_a_machine_going_settles_its_open_commands() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "hang", "method": "pane.focus"})
	var sent := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	var deadline := Time.get_ticks_msec() + 2000
	while sent.state == CommandTicket.State.UNSENT and Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(1000)
	_eq(sent.state, CommandTicket.State.SENT, "the first is on the wire")
	var unsent := commands.submit(_aim(facts, "alpha:p3").focusing(), facts)
	_eq(unsent.state, CommandTicket.State.UNSENT, "the second is only queued")
	commands.settle_machine(facts.key)
	_eq(
		[sent.state, unsent.state],
		[CommandTicket.State.UNKNOWN, CommandTicket.State.CANCELLED],
		"settled: unknown once sent, cancelled before"
	)
	_eq(commands.open_count(), 0, "nothing left open")
	await _frames(3)
	_eq(_count("control-a", "pane.focus"), 1, "only the sent one reached herdr")
	commands.free()
	# Through the fleet: bee replaced while a write to it hangs.
	var office := await _office_with()
	_ctl("control-b", "next", {"action": "hang", "method": "pane.focus"})
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var open := office.fleet.focus_pane(office.fleet.context_for(key, 1).focusing())
	await _until(func() -> bool: return open.state == CommandTicket.State.SENT, "the write is on the wire")
	office.fleet._roster.sockets = _debug_socket("bee", args["socket-a"])
	office.fleet._sync_sites()
	_eq(open.state, CommandTicket.State.UNKNOWN, "replacing its machine settles it at once")


## One write per pane at a time; another pane's write is not held up, and
## reads are not writes.
func test_one_write_per_pane_at_a_time() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "delay", "method": "pane.focus", "seconds": 0.4})
	var first := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	var again := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_eq(
		[again.state, again.refusal],
		[CommandTicket.State.REFUSED, CommandRefusal.Reason.IN_FLIGHT],
		"the same pane waits"
	)
	var other := commands.submit(_aim(facts, "alpha:p3").focusing(), facts)
	_check(not other.is_finished(), "another pane does not")
	var read_one := commands.submit(_aim(facts, "alpha:p1").reading(CommandContext.SOURCE_RECENT, 12), facts)
	var read_two := commands.submit(_aim(facts, "alpha:p1").reading(CommandContext.SOURCE_RECENT, 12), facts)
	_check(not read_one.is_finished() and not read_two.is_finished(), "reads are not single-flight")
	var open: Array[CommandTicket] = [first, other, read_one, read_two]
	for ticket in open:
		_settle(commands, ticket, "an open command")
	# The first settled, and nobody has looked at alpha:p1 since.
	var unlooked := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_eq(unlooked.refusal, CommandRefusal.Reason.LOOK_FIRST, "settled, but not looked at: still no write")
	# read_one was asked for before the write ended: showing it is no look.
	commands.saw(read_one)
	_check(commands.must_look(first.context.pane_key), "an older read is no look")
	await _look(commands, facts, "alpha:p1")
	var after := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_settle(commands, after, "the next write")
	_eq(after.state, CommandTicket.State.ACCEPTED, "once settled and looked at, the pane takes a write again")
	_eq(_count("control-a", "pane.focus"), 3, "three writes went out, the refused ones never did")
	commands.free()


## Writes and reads keep separate bounded rings, so the card's reads never push
## a write out; every entry is known by machine, generation and request id.
func test_the_audit_keeps_writes_and_reads_apart_and_bounded() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw(), 7)
	var commands := _boundary()
	var write := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_settle(commands, write, "the write")
	for index in HerdrCommands.AUDIT_READS + 6:
		var read := commands.submit(_aim(facts, "alpha:p3").reading(CommandContext.SOURCE_DETECTION, 12), facts)
		_settle(commands, read, "a read")
	var writes := commands.write_log()
	var reads := commands.read_log()
	_eq(writes.size(), 1, "the write is still there after %d reads" % (HerdrCommands.AUDIT_READS + 6))
	_eq(reads.size(), HerdrCommands.AUDIT_READS, "the read ring is bounded")
	if writes.size() == 1:
		var entry := writes[0]
		_eq([entry.machine, entry.generation, entry.request_id], [facts.key, 7, write.request_id], "keyed")
		_eq([entry.method, entry.pane_key], ["pane.focus", HerdrFleet.pane_key(facts.key, "alpha:p1")], "what, where")
		_eq(entry.states, PackedStringArray(["UNSENT", "SENT", "ACCEPTED"]), "every state it went through")
		_eq(entry.times.size(), 3, "each with its time")
	var last := reads[reads.size() - 1]
	_eq([last.source, last.lines, last.truncated, last.cut], ["detection", 12, false, false], "a read's shape")
	_check(last.bytes > 0, "and its byte count")
	var ids := {}
	for entry in reads:
		ids[entry.request_id] = true
	_eq(ids.size(), reads.size(), "every request its own id")
	commands.free()


## A fake that allows no write refuses one with that request's own id, so the
## boundary files it as herdr's refusal, not as an answer to another request.
func test_a_refusal_carries_the_request_s_own_id() -> void:
	_fakes("snapshot_basic", [])
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var ticket := commands.submit(_aim(facts, "alpha:p1").focusing(), facts)
	_settle(commands, ticket, "the refused write")
	provoked["control-a"].append("non read-only method: pane.focus")
	_eq(
		[ticket.state, ticket.error_code],
		[CommandTicket.State.REJECTED, "invalid_request"],
		"rejected by herdr, matched by id"
	)
	commands.free()


## The audit holds the office's own spelling of a pane, never herdr's wire id:
## a command is audited before it is checked, so one refused because herdr's
## id carries a control or a bidi character must not carry it into the audit.
## A bidi override counts as such a character (MachineRoster.clean_text()), so
## that pane is refused, not sent.
func test_the_audit_holds_only_the_office_s_own_spelling() -> void:
	_fakes()
	var raw := _changed(_raw(), "alpha:p1", {"pane_id": "alpha:p1" + char(7)})
	raw = _changed(raw, "alpha:p3", {"pane_id": "alpha:p3" + char(0x202e)})
	var facts := _facts(args["socket-a"], raw)
	var commands := _boundary()
	for index: int in [0, 2]:
		# Aimed the way the fleet aims: at the pane as the office names it.
		var context := _aim(facts, facts.snapshot.panes[index].pane_id)
		_check(context.wire_pane_id != context.pane_id, "herdr spells %s its own way" % context.pane_id)
		var ticket := commands.submit(context.focusing(), facts)
		_eq(
			[ticket.state, ticket.refusal],
			[CommandTicket.State.REFUSED, CommandRefusal.Reason.WIRE_ID_MISMATCH],
			"%s is refused before anything is sent" % context.pane_id
		)
	var entries := commands.write_log()
	_eq(entries.size(), 2, "both are audited")
	for entry in entries:
		var parts := HerdrFleet.split_key(entry.pane_key)
		for text: String in [entry.summary, entry.machine, parts[0], parts[1]]:
			_eq(MachineRoster.clean_text(text), text, "the audit holds only cleaned text: " + text.c_escape())
	_eq(
		entries.map(func(entry: CommandAuditEntry) -> String: return entry.summary),
		["pane.focus alpha:p1", "pane.focus alpha:p3"],
		"summaries name the panes as the office does"
	)
	await _frames(2)
	_eq(_count("control-a", "pane.focus"), 0, "nothing reached herdr")
	commands.free()


## Every request goes out through HerdrClient.request_line(), the client's and
## this boundary's alike: JSON a strict parser takes, whatever its strings hold.
## JSON.stringify() leaves most C0 characters and DEL raw and writes 0x0B as
## `\v`, which is no JSON escape.
func test_requests_are_json_a_strict_parser_takes() -> void:
	var codes: Array = range(1, 0x20) + [0x7f]
	for code: int in codes:
		var text := "a" + char(code) + "b"
		var line := JsonText.encode({"s": text})
		var raw := false
		for byte in line.to_utf8_buffer():
			raw = raw or byte < 0x20 or byte == 0x7f
		_check(not raw, "U+%04X is never written raw" % code)
		_eq(line, '{"s":"a' + "\\u%04x" % code + 'b"}', "U+%04X is a \\u00XX escape" % code)
		_eq(HerdrClient.parse_line(line), {"s": text}, "U+%04X reads back as it was" % code)
	var tricky := {
		"quote": 'say "hi"',
		"slash": "C:\\very\\new",
		"mixed": "\\" + char(0x0b) + "v" + char(7) + '"',
		"unicode": "中文 ✓ " + char(0x2028),
		"nested": [{"pane_id": "p" + char(0x0b)}, "x" + char(1), 7, true, null, 2.5],
		"names": PackedStringArray(["a" + char(0x1b), "b"]),
	}
	var encoded := JsonText.encode(tricky)
	var parsed: Variant = HerdrClient.parse_line(encoded)
	_check(parsed is Dictionary, "the whole request reads back: " + encoded.c_escape())
	if parsed is Dictionary:
		var data: Dictionary = parsed
		for key: String in ["quote", "slash", "mixed", "unicode"]:
			_eq(data.get(key), tricky[key], "%s reads back as it was" % key)
		# JSON numbers read back as floats.
		_eq(data.get("nested"), [{"pane_id": "p" + char(0x0b)}, "x" + char(1), 7.0, true, null, 2.5], "nested")
		_eq(data.get("names"), ["a" + char(0x1b), "b"], "a PackedStringArray is a list")
	var request := HerdrClient.request_line("7", "ping", {})
	_eq(request.get_string_from_utf8(), '{"id":"7","method":"ping","params":{}}\n', "one NDJSON line per request")
	_eq(HerdrClient.parse_line("not json " + SENTINEL_WORD), null, "a line that is not JSON reads as nothing")


## A pane id with a control character in it: herdr's own spelling is what the
## client's per-pane subscription names, and that request is JSON a strict
## parser takes now. Before, herdr refused it as malformed and the machine went
## offline for good, retrying. The office draws the cleaned ids, and never aims
## a command at such a pane (its wire and cleaned ids differ).
func test_control_characters_in_pane_ids_keep_the_machine_current() -> void:
	_fakes("snapshot_control_ids")
	var violations := _list(_ctl("control-a", "stats"), "violations").size()
	var office := await _office_with(false, false)
	var stats := _ctl("control-a", "stats")
	var wire: Array = ["ctl:p1" + char(7), "ctl:p2" + char(0x0b), "ctl:p3"]
	_eq(_list(stats, "last_subscribe_panes"), wire, "the subscription names herdr's ids, control characters and all")
	_eq(_list(stats, "stream_errors"), [], "and herdr took it")
	_eq(_list(stats, "violations").size(), violations, "every request was JSON a strict parser takes")
	await _wait(1.0)
	_check(office.fleet.snapshot_is_current(HerdrFleet.LOCAL), "the machine is live and current, and stays so")
	var held := office.fleet.snapshot(HerdrFleet.LOCAL).panes
	_eq(
		held.map(func(pane: HerdrSnapshot.Pane) -> String: return pane.pane_id),
		["ctl:p1", "ctl:p2", "ctl:p3"],
		"cleaned"
	)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "ctl:p2")
	_eq(office.fleet.can_operate(key), CommandRefusal.Reason.WIRE_ID_MISMATCH, "no command is aimed at such a pane")
	# A status event names the pane as herdr spells it, and reaches it. (The
	# control socket takes this suite's own JSON.stringify(): a raw BEL passes
	# there, a vertical tab's `\v` would not.)
	_ctl("control-a", "status", {"pane_id": "ctl:p1" + char(7), "agent_status": "blocked"})
	await _until(
		func() -> bool: return _held_status(office, HerdrFleet.LOCAL, "ctl:p1") == "blocked",
		"the status event for ctl:p1"
	)


# --- the switch ----------------------------------------------------------------


## The positive control: one real click sends exactly one pane.focus, with
## herdr's own pane id, to the machine the pane is on, while the same pane id
## exists on both machines.
func test_one_click_sends_one_focus_to_the_right_machine() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	await _pick_bee(office, "alpha:p3")
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "alpha:p3"), "bee's alpha:p3 is picked")
	await _until(func() -> bool: return button.visible and not button.disabled, "the switch is offered")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "nothing before the click")
	await _click_control(button)
	await _until(func() -> bool: return card.outcome_text() == "herdr switched here", "herdr accepted")
	_eq(_asked("control-b", "pane.focus"), [{"pane_id": "alpha:p3"}], "one focus, herdr's pane id, on bee")
	_eq(_count("control-a", "pane.focus"), 0, "Local has that pane id too and heard nothing")
	_eq(_ctl("control-b", "stats").get("focused_pane_id"), "alpha:p3", "bee's herdr moved its focus")
	var writes := office.fleet.write_log()
	_eq(writes.size(), 1, "one write in the audit")
	if writes.size() == 1:
		_eq([writes[0].machine, writes[0].last_state()], [BEE, "ACCEPTED"], "on bee, accepted")


## Refreshes, status events, timers, floor changes, a card opened, hidden and
## shown, herdr moving its own focus so the card rebinds: no write, only reads.
func test_nothing_is_written_without_a_gesture() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var bindings := card.binding()
	for index in 30:
		office.refresh()
	_ctl("control-a", "status", {"pane_id": "alpha:p1", "agent_status": "blocked"})
	_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": "done"})
	await _navigate_key(office, KEY_PAGEDOWN)
	await _navigate_key(office, KEY_PAGEUP)
	await _pick_bee(office, "alpha:p1")
	card.visible = false
	await _wait(0.5)
	card.visible = true
	# Back to following herdr, which then moves its own focus.
	office.picked_key = ""
	office.refresh()
	var moved := _raw()
	moved.focused_pane_id = "alpha:p3"
	_ctl("control-a", "set_snapshot", {"snapshot": moved})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	var local_p3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3")
	await _until(func() -> bool: return office.navigator.active_key == local_p3, "the card follows herdr's focus")
	# The panel is one line until opened: Enter opens a followed pane's too.
	await _open_panel(office)
	await _wait(3.5)
	_check(card.binding() >= bindings + 3, "the card rebound along the way: %d -> %d" % [bindings, card.binding()])
	_check(_count("control-a", "pane.read") > 0 and _count("control-b", "pane.read") > 0, "it read both machines")
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "and wrote to neither")


## The switch never takes keyboard focus: Enter and Space after a click send
## nothing. A double click is one switch, in flight or already done.
func test_keys_and_double_clicks_send_at_most_one() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	_eq(button.focus_mode, Control.FOCUS_NONE, "the switch never takes keyboard focus")
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return not button.disabled, "the switch is offered")
	# A double click while the first is still on its way.
	_ctl("control-b", "next", {"action": "delay", "method": "pane.focus", "seconds": 0.6})
	for half: Array in [[true, false], [false, false], [true, true], [false, false]]:
		var down: bool = half[0]
		var double: bool = half[1]
		_half_click(button, down, double)
		await process_frame
	_check(card.switching() and button.disabled, "in flight, the switch is off")
	await _until(func() -> bool: return not card.switching(), "the switch settles")
	_eq(_count("control-b", "pane.focus"), 1, "a double click in flight is one switch")
	# A double click whose first click has already been answered.
	await _until(func() -> bool: return not button.disabled, "the switch is back")
	_half_click(button, true)
	await process_frame
	_half_click(button, false)
	await _until(func() -> bool: return _count("control-b", "pane.focus") == 2, "the first click went")
	await _until(func() -> bool: return not card.switching(), "and was answered")
	_half_click(button, true, true)
	await process_frame
	_half_click(button, false)
	await _frames(4)
	_eq(_count("control-b", "pane.focus"), 2, "the second press of a double click is not a click")
	for code: Key in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
		await _tap(code)
	await _frames(4)
	_eq(_count("control-b", "pane.focus"), 2, "Enter and Space never reach it")
	_eq(_count("control-a", "pane.focus"), 0, "nor anything else")


## A switch whose answer never comes, is lost after herdr carried it out, or
## that herdr refuses: the card says which, the machine stays live, and nothing
## is sent again.
func test_a_lost_or_refused_switch_says_so_and_keeps_its_machine() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return not button.disabled, "the switch is offered")
	_ctl("control-b", "next", {"action": "execute_then_drop", "method": "pane.focus"})
	await _click_control(button)
	await _until(
		func() -> bool: return card.outcome_text() == "Unknown result: look first", "an unknown outcome is said"
	)
	_eq(_ctl("control-b", "stats").get("focused_pane_id"), "alpha:p3", "herdr did switch")
	_check(office.fleet.snapshot_is_current(BEE), "bee stays live")
	_ctl("control-b", "next", {"action": "refuse", "method": "pane.focus", "code": "busy", "message": "not now"})
	await _until(func() -> bool: return not button.disabled, "the switch is back")
	await _click_control(button)
	await _until(func() -> bool: return card.outcome_text() == "herdr refused (busy)", "herdr's refusal is said")
	_check(office.fleet.snapshot_is_current(BEE), "bee stays live")
	_ctl("control-b", "next", {"action": "hang", "method": "pane.focus"})
	await _until(func() -> bool: return not button.disabled, "the switch is back again")
	await _click_control(button)
	_check(card.switching() and button.disabled, "in flight, the switch is off")
	await _until(func() -> bool: return not card.switching(), "herdr never answers: the write times out")
	_eq(card.outcome_text(), "Unknown result: look first", "a timeout is unknown too")
	_check(office.fleet.snapshot_is_current(BEE), "a timeout does not take bee offline")
	await _frames(4)
	_eq(_count("control-b", "pane.focus"), 3, "three clicks, three writes, none sent again")


## Following herdr's focus, the card offers the switch switched off, and says why.
func test_the_switch_is_off_while_the_card_follows_herdr() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	_eq(office.picked_key, "", "nothing picked: the card follows herdr's focus")
	# Enter opens the followed pane's panel: it reads, and shows the switch off.
	await _open_panel(office)
	await _until(
		func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN,
		"the card reads the focused pane"
	)
	_check(button.visible and button.disabled, "offered, switched off")
	_eq(card.outcome_text(), "Following herdr's focus", "and it says why")
	await _click_control(button)
	await _frames(4)
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "a click on it sends nothing")
	await _pick_local(office, "alpha:p1")
	await _until(func() -> bool: return not button.disabled, "picking that very pane turns it on")
	_eq(card.outcome_text(), "", "with nothing left to explain")


## herdr's focus marks the whole tab seen (measured on 0.9.0, modelled by the
## fake): after a switch the next snapshot shows every `done` there `idle`, and
## the office draws it; another tab keeps its UNREAD.
func test_a_switch_clears_unread_on_the_whole_table() -> void:
	var raw := _raw()
	for pane_id: String in ["alpha:p1", "alpha:p3", "bravo:p1"]:
		raw = _changed(raw, pane_id, {"agent_status": "done"})
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	var office := await _office_with()
	var bee := func(pane_id: String) -> String: return _pane_state(office, HerdrFleet.pane_key(BEE, pane_id))
	await _until(func() -> bool: return bee.call("alpha:p1") == "done", "bee reads done")
	await _pick_bee(office, "alpha:p3")
	var button := _switch(office)
	await _until(func() -> bool: return not button.disabled, "the switch is offered")
	await _click_control(button)
	await _until(
		func() -> bool: return bee.call("alpha:p1") == "idle" and bee.call("alpha:p3") == "idle",
		"the next snapshot shows the whole table seen"
	)
	_eq(bee.call("bravo:p1"), "done", "another table keeps its UNREAD")
	_eq(office.frame.find_floor(HerdrFleet.pane_key(BEE, "alpha")).floor_model.done, 0, "the floor counts none")


## An SSH machine is a site like any other: a switch reaches its herdr through
## the forward (fake_ssh), and a switch still out when the machine is closed
## settles, never staying sent.
func test_a_switch_over_an_ssh_forward_settles_when_its_machine_goes() -> void:
	if not args.has("ssh"):
		_fail("no --ssh= (use tools/run_tests.sh)")
		return
	_fakes()
	var home := args.work.path_join("command-ssh-home")
	var remote := MachineLink.remote_socket_path(home, "")
	DirAccess.make_dir_recursive_absolute(remote.get_base_dir())
	OS.execute("ln", ["-sf", args["socket-b"], remote])
	OS.set_environment("FAKE_SSH_HOME", home)
	var listing := args.work.path_join("command-machines.json")
	var lister := args.work.path_join("command-machine-list.sh")
	_write(lister, '#!/bin/sh\n[ "$*" = "machine list --json" ] || exit 64\ncat \'%s\'\n' % listing)
	OS.execute("chmod", ["+x", lister])
	_write(listing, JSON.stringify([{"id": "far", "label": "far", "target": "me@far", "enabled": true}]))
	OS.set_environment("HERDR_BIN_PATH", lister)
	var office := await _office_with(false, false, false)
	var far := "machine:far"
	await _until(
		func() -> bool: return office.fleet.snapshot_is_current(far), "the SSH machine is live through its forward"
	)
	_eq(office.fleet.link_state(far), MachineLink.State.FORWARDING, "through an ssh -L forward")
	var key := HerdrFleet.pane_key(far, "alpha:p3")
	await _floor_pick(office, HerdrFleet.pane_key(far, "alpha"))
	await _click_visible_pane(office, key)
	await _open_panel(office)
	var card := _card(office)
	var button := _switch(office)
	await _until(func() -> bool: return not button.disabled, "the switch is offered on the SSH machine")
	_eq(button.text, "Switch herdr on far", "the button names the machine it switches")
	await _click_control(button)
	await _until(func() -> bool: return card.outcome_text() == "herdr switched here", "switched through the forward")
	_eq(_asked("control-b", "pane.focus"), [{"pane_id": "alpha:p3"}], "one focus reached the far herdr")
	_ctl("control-b", "next", {"action": "hang", "method": "pane.focus"})
	await _until(func() -> bool: return not button.disabled, "the switch is back")
	await _click_control(button)
	await _until(func() -> bool: return _last_write(office) == "SENT", "the second switch is out")
	_write(listing, "[]")
	office.fleet._roster._left = 0.0
	await _until(func() -> bool: return not office.fleet.has(far), "the SSH machine is closed")
	_eq(_last_write(office), "UNKNOWN", "its open switch settles unknown, and is not sent again")
	_eq(_count("control-b", "pane.focus"), 2, "two clicks, two writes")
	OS.set_environment("HERDR_BIN_PATH", _no_herdr())
	OS.unset_environment("FAKE_SSH_HOME")


# --- refusals ------------------------------------------------------------------


## A context aimed at one connection never matches another: replaced, re-enabled
## and reconnected machines refuse it, each tried once the new connection is
## live and current with the same pane identity, so nothing else refuses it.
func test_a_held_context_never_matches_a_new_connection() -> void:
	_fakes()
	var office := await _office_with()
	var fleet := office.fleet
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	# Which machine connects first is scheduling, not the counter's contract.
	var bee := fleet.generation(BEE)
	_check(bee != fleet.generation(HerdrFleet.LOCAL) and bee > 0, "one fleet-wide counter: two machines, two numbers")
	var held := fleet.context_for(key, 1).focusing()
	var generation := fleet.generation(BEE)
	fleet._roster.sockets = _debug_socket("bee", args["socket-a"])
	fleet._sync_sites()
	await _until(func() -> bool: return _ready_as(fleet, key, held), "the replacement is current")
	_check(fleet.generation(BEE) > generation, "a replaced machine is a new generation")
	_eq(_refusal(fleet.focus_pane(held)), CommandRefusal.Reason.MACHINE_REPLACED, "replaced")
	held = fleet.context_for(key, 1).focusing()
	fleet._roster.sockets = []
	fleet._sync_sites()
	_eq(_refusal(fleet.focus_pane(held)), CommandRefusal.Reason.MACHINE_GONE, "a machine no longer shown")
	fleet._roster.sockets = _debug_socket("bee", args["socket-a"])
	fleet._sync_sites()
	await _until(func() -> bool: return _ready_as(fleet, key, held), "re-enabled and current")
	_eq(_refusal(fleet.focus_pane(held)), CommandRefusal.Reason.MACHINE_REPLACED, "re-enabled")
	held = fleet.context_for(key, 1).focusing()
	generation = fleet.generation(BEE)
	_ctl("control-a", "vanish")
	await _until(func() -> bool: return fleet.is_stale(BEE), "the connection drops")
	_eq(_refusal(fleet.focus_pane(held)), CommandRefusal.Reason.MACHINE_OFFLINE, "offline")
	_ctl("control-a", "appear")
	await _until(func() -> bool: return _ready_as(fleet, key, held), "reconnected and current")
	_check(fleet.generation(BEE) > generation, "a reconnect is a new generation")
	_eq(_refusal(fleet.focus_pane(held)), CommandRefusal.Reason.MACHINE_REPLACED, "reconnected")
	await _frames(3)
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "none of them reached herdr")


## A press held while the pick moves (`N` with the other hand) sends nothing at
## its release: the switch was aimed at the press, and the card has rebound to
## another pane it may switch to, so the button stays on and only the card's own
## binding check stands between the release and a write to the wrong pane.
func test_a_press_held_while_the_pick_moves_sends_nothing() -> void:
	# Only bee's alpha:p1 needs a human, so `N` picks it, on the floor shown.
	var quiet := _changed(_raw(), "bravo:p1", {"agent_status": "idle"})
	_fakes()
	_ctl("control-a", "set_snapshot", {"snapshot": quiet})
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(quiet, "alpha:p1", {"agent_status": "blocked"})})
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return not button.disabled, "the switch is offered for alpha:p3")
	var binding := card.binding()
	_half_click(button, true)
	await process_frame
	await _tap(KEY_N)
	var next := HerdrFleet.pane_key(BEE, "alpha:p1")
	await _until(func() -> bool: return card.binding() != binding, "the card rebinds to the next human")
	_eq(office.picked_key, next, "N picked bee's alpha:p1")
	_check(not button.disabled, "a picked pane the switch may reach: the button stays on under the held press")
	_half_click(button, false)
	await _frames(4)
	_eq(_count("control-b", "pane.focus"), 0, "a press aimed at alpha:p3 sends nothing at its release")
	_eq(card.outcome_text(), "Not sent: target changed", "and the card says so")


## A held press while another terminal takes over the pane id: nobody picked
## that terminal, so the switch turns off under the press, and Godot cancels a
## press on a button that is disabled mid-press. Nothing is sent either way;
## the binding check itself is test_a_press_held_while_the_pick_moves_sends_nothing.
func test_a_new_terminal_under_a_held_press_turns_the_switch_off() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return not button.disabled, "the switch is offered")
	var binding := card.binding()
	_half_click(button, true)
	await process_frame
	var swapped := _changed(_raw(), "alpha:p3", {"terminal_id": "term-alpha-3-new"})
	_ctl("control-b", "set_snapshot", {"snapshot": swapped})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return card.binding() != binding, "the card rebinds to the new terminal")
	_check(button.disabled, "nobody picked the new terminal: the switch is off")
	_eq(card.outcome_text(), "New terminal: pick again", "and the card says why")
	_half_click(button, false)
	await _frames(4)
	_eq(_count("control-b", "pane.focus"), 0, "the cancelled press sends nothing")


## A pick belongs to the terminal that was picked. After the picked pane
## closes and herdr later gives its id to a new terminal, the desk shows again
## but the switch stays off until the desk is picked again.
func test_a_pick_does_not_carry_over_to_a_reused_pane_id() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var button := _switch(office)
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return not button.disabled, "the switch is offered for the picked pane")
	_ctl("control-b", "set_snapshot", {"snapshot": _without(_raw(), "alpha:p3")})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.frame.pane(key) == null, "the picked pane closes")
	_eq(office.picked_key, key, "the pick outlives its pane, as it always has")
	var reused := _changed(_raw(), "alpha:p3", {"terminal_id": "term-alpha-3-reused"})
	_ctl("control-b", "set_snapshot", {"snapshot": reused})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.navigator.active_key == key, "a new terminal takes the id and is shown")
	await _frames(2)
	# The panel folded with the pane it was opened for; open it again, as a
	# viewer would, so the click below lands on the switch itself.
	await _open_panel(office)
	await _frames(2)
	_check(button.is_visible_in_tree() and button.disabled, "the switch is off for a terminal nobody picked")
	_eq(card.outcome_text(), "New terminal: pick again", "and the card says why")
	await _click_control(button)
	await _frames(4)
	_eq(_count("control-b", "pane.focus"), 0, "a click on it sends nothing")
	await _click_visible_pane(office, key)
	await _until(func() -> bool: return not button.disabled, "picking the desk again picks the new terminal")
	_eq(_count("control-b", "pane.focus"), 0, "and nothing was sent on the way")


## What cannot be told apart is never sent: a pane gone, a terminal changed or
## unknown, a pane id herdr spells differently or twice, a snapshot not current,
## a protocol this office does not know. The card offers nothing either.
func test_what_cannot_be_told_apart_is_never_sent() -> void:
	_fakes()
	var office := await _office_with()
	var fleet := office.fleet
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var raw := _raw()
	var without: Dictionary = raw.duplicate(true)
	without.panes = _list(raw, "panes").filter(func(pane: Dictionary) -> bool: return pane.pane_id != "alpha:p3")
	var twice: Dictionary = raw.duplicate(true)
	var third: Dictionary = _list(raw, "panes")[2]
	twice.panes = _list(raw, "panes") + [third.duplicate(true)]
	var cases: Array = [
		[without, CommandRefusal.Reason.PANE_GONE, "a pane gone"],
		[_changed(raw, "alpha:p3", {"terminal_id": null}), CommandRefusal.Reason.IDENTITY_UNKNOWN, "no terminal id"],
		# A C0 control (a BEL) and a bidi override: both gone once cleaned. The
		# machine stays current with either in an id, so nothing else refuses it:
		# every request, the client's subscription included, is JSON a strict
		# parser takes (HerdrClient.request_line()).
		[
			_changed(raw, "alpha:p3", {"pane_id": "alpha:p3" + char(7)}),
			CommandRefusal.Reason.WIRE_ID_MISMATCH,
			"herdr's id has a control"
		],
		[
			_changed(raw, "alpha:p3", {"pane_id": "alpha:p3" + char(0x202e)}),
			CommandRefusal.Reason.WIRE_ID_MISMATCH,
			"herdr's id has a bidi override"
		],
		[twice, CommandRefusal.Reason.WIRE_ID_DUPLICATE, "the id listed twice"],
	]
	for case: Array in cases:
		var snapshot: Dictionary = case[0]
		var reason: CommandRefusal.Reason = case[1]
		var what: String = case[2]
		_ctl("control-b", "set_snapshot", {"snapshot": snapshot})
		_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
		await _until(func() -> bool: return fleet.can_operate(key) == reason, what)
		_eq(_refusal(fleet.focus_pane(fleet.context_for(key, 1).focusing())), reason, what + ": refused")
		_eq(
			_refusal(fleet.read_pane(fleet.context_for(key, 1).reading(CommandContext.SOURCE_RECENT, 12))),
			reason,
			what + ": no read"
		)
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return fleet.can_operate(key) == CommandRefusal.Reason.NONE, "the pane is back")
	var held := fleet.context_for(key, 1).focusing()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(raw, "alpha:p3", {"terminal_id": "term-other"})})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return fleet.context_for(key, 1).identity_key != held.identity_key, "a new terminal")
	_eq(_refusal(fleet.focus_pane(held)), CommandRefusal.Reason.IDENTITY_CHANGED, "aimed at the old terminal")
	var huge := _raw()
	var records: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		records.append({})
	huge.panes = records
	_ctl("control-b", "set_snapshot", {"snapshot": huge})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(
		func() -> bool: return fleet.can_operate(key) == CommandRefusal.Reason.SNAPSHOT_NOT_CURRENT,
		"a refused snapshot"
	)
	_check(office.fleet.snapshot(BEE).panes.size() > 0, "online, its last picture kept")
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	_ctl("control-b", "set_protocol", {"protocol": 23})
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return fleet.is_stale(BEE), "offline")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return fleet.snapshot_is_current(BEE), "back on protocol 23")
	_eq(fleet.protocol(BEE), 23, "the handshake's protocol is kept for its connection")
	_eq(fleet.can_operate(key), CommandRefusal.Reason.UNKNOWN_PROTOCOL, "a protocol this office does not know")
	_eq(
		_refusal(fleet.focus_pane(fleet.context_for(key, 1).focusing())),
		CommandRefusal.Reason.UNKNOWN_PROTOCOL,
		"refused"
	)
	await _frames(3)
	_eq(_count("control-a", "pane.focus") + _count("control-b", "pane.focus"), 0, "no write reached herdr")


# --- the preview ---------------------------------------------------------------


## The card shows herdr's nested read in a fixed block of 12 rows, tail at the
## bottom; a blocked pane is read from `detection`, the rest from `recent_unwrapped`.
func test_the_preview_shows_the_tail_and_switches_source_when_blocked() -> void:
	_fakes()
	_ctl(
		"control-b",
		"set_preview",
		{"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "line one\nline two\n"}
	)
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": "Allow this? [y/n]\n"})
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return card.preview_text() == "line one\nline two\n", "the recent tail shows")
	_eq(card.preview_state(), OfficePaneInspector.PreviewState.SHOWN, "shown")
	_check(card.preview_caption().begins_with("recent · "), "the caption names the source: " + card.preview_caption())
	var label: Label = card.get_node("%Preview")
	_eq(label.text.split("\n").size(), OfficePaneInspector.PREVIEW_ROWS, "always a block of 12 rows")
	_check(label.text.ends_with("\nline one\nline two"), "the tail at the bottom")
	var last: Dictionary = _asked("control-b", "pane.read").back()
	_eq([last.get("pane_id"), last.get("source")], ["alpha:p3", "recent_unwrapped"], "asked for the recent output")
	_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": "blocked"})
	await _until(
		func() -> bool: return card.preview_text() == "Allow this? [y/n]\n", "a blocked pane shows its question"
	)
	# A blocked caption leads with how many rows of the question show; its
	# tooltip names the source.
	_check(card.preview_caption().begins_with("1 of 1 row · "), "rows shown: " + card.preview_caption())
	var caption: Label = card.get_node("%PreviewCaption")
	_check(caption.tooltip_text.contains("detection source"), "from detection: " + caption.tooltip_text)
	last = _asked("control-b", "pane.read").back()
	_eq(
		[last.get("source"), _number(last, "lines")],
		["detection", 200.0],
		"asked for all of what herdr's detection sees"
	)


## What the card shows is cleaned, tabs expanded, and a cut is marked.
func test_the_preview_is_cleaned_and_marks_a_cut() -> void:
	_fakes()
	_ctl(
		"control-b",
		"set_preview",
		{"pane_id": "alpha:p3", "text": "ok\u0007\u202e fine\u2066\n\tcol\r\n", "truncated": true}
	)
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "shown")
	_eq(card.preview_text(), "ok fine\n\tcol\n", "no control or bidi character reaches the card")
	var label: Label = card.get_node("%Preview")
	_check(label.text.ends_with("\nok fine\n        col"), "a tab is spaces to the next stop of 8")
	_check(card.preview_caption().ends_with(" · cut"), "herdr's cut is marked: " + card.preview_caption())


## A reply over the command's cap is a failure the card says, never an empty
## preview; the machine stays live.
func test_a_reply_over_the_cap_is_a_failure_not_an_empty_preview() -> void:
	_fakes()
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "fill": HerdrCommands.READ_LINE_MAX + 4096})
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _until(
		func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.FAILED, "the read fails"
	)
	_check(card.preview_caption().begins_with("Read failed: "), "and says so: " + card.preview_caption())
	_eq(card.preview_text(), "", "with no text passed off as the terminal's")
	_check(office.fleet.snapshot_is_current(BEE), "bee stays live")
	var reads := office.fleet.read_log()
	var failed := reads.filter(func(entry: CommandAuditEntry) -> bool: return entry.pane_key.ends_with("alpha:p3"))
	_check(not failed.is_empty(), "the failed read is in the audit")
	if not failed.is_empty():
		var entry: CommandAuditEntry = failed.back()
		_eq(entry.last_state(), "UNKNOWN", "filed unknown")


## A reply for a card that has moved on never lands on it, and there is never
## more than one read in flight.
func test_a_late_reply_never_lands_on_a_rebound_card() -> void:
	_fakes()
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "text": "THIRD PANE\n"})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p1", "text": "FIRST PANE\n"})
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return card.preview_text() == "THIRD PANE\n", "the third pane shows")
	var before := _count("control-b", "pane.read")
	_ctl("control-b", "next", {"action": "delay", "method": "pane.read", "seconds": 1.5})
	_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": "working"})
	await _until(card.reading, "a slow read of the third pane is in flight")
	await _until(func() -> bool: return _count("control-b", "pane.read") > before, "and has reached herdr")
	# herdr holds that reply 1.5 s from here: well inside that, it is still in flight.
	var in_flight_until := Time.get_ticks_msec() + 1200
	var asked := _count("control-b", "pane.read")
	await _click_visible_pane(office, HerdrFleet.pane_key(BEE, "alpha:p1"))
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "alpha:p1"), "the card moved to the first pane")
	# Another pane folds the panel: Enter opens it on the first pane.
	await _open_panel(office)
	_check(Time.get_ticks_msec() < in_flight_until, "and rebound while the slow read was still out")
	var most := asked
	var landed := false
	while Time.get_ticks_msec() < in_flight_until:
		most = maxi(most, _count("control-b", "pane.read"))
		landed = landed or card.preview_text() == "THIRD PANE\n"
		await process_frame
	_eq(most, asked, "the rebound card waits: no second read while one is in flight")
	var deadline := Time.get_ticks_msec() + 4000
	while card.preview_text() != "FIRST PANE\n" and Time.get_ticks_msec() < deadline:
		landed = landed or card.preview_text() == "THIRD PANE\n"
		await process_frame
	_eq(card.preview_text(), "FIRST PANE\n", "the first pane's text arrives")
	_check(not landed, "the third pane's late reply never showed on the first pane's card")


## Reads happen only while the card is on screen, the window is not minimized
## (the pacer's seam) and the machine is live and current.
func test_reads_stop_when_hidden_minimized_offline_or_not_current() -> void:
	var raw := _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "reading")
	var before := _count("control-b", "pane.read")
	await _wait(2.5)
	_check(_count("control-b", "pane.read") >= before + 2, "a blocked pane is read every second")
	card.visible = false
	await _quiet(card, "hidden")
	card.visible = true
	await _reading_again(card)
	office.pacer.note_minimized(true)
	await _quiet(card, "minimized")
	office.pacer.note_minimized(false)
	await _reading_again(card)
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "offline")
	await _quiet(card, "offline")
	_eq(card.preview_reason(), CommandRefusal.Reason.MACHINE_OFFLINE, "the card says why")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return office.fleet.snapshot_is_current(BEE), "back")
	await _reading_again(card)
	var huge := _raw()
	var records: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		records.append({})
	huge.panes = records
	_ctl("control-b", "set_snapshot", {"snapshot": huge})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "not current")
	await _quiet(card, "not current")
	_eq(card.preview_reason(), CommandRefusal.Reason.SNAPSHOT_NOT_CURRENT, "the card says why")


## At every size (800x480 and the 480x320 minimum) the picked agent's card
## is the staff panel's one line, whose preview cannot be seen: nothing is read
## while it is, reading starts once Enter opens the card up, and stops again
## once Escape folds it back. All through real keys.
func test_reads_stop_while_the_card_is_a_compact_header() -> void:
	for screen: Vector2 in [Vector2(SCREEN), Vector2(480, 320)]:
		# Blocked, so a read that leaked would come within a second.
		var raw := _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})
		_fakes()
		_ctl("control-b", "set_snapshot", {"snapshot": raw})
		var office := await _office_with(false, true, true, screen)
		var card := _card(office)
		await _pick_bee(office, "alpha:p3", false)
		_check(office.hud.card_compact(), "%s: the picked agent's card is a compact header" % screen)
		await _quiet(card, "%s: the card is a compact header" % screen)
		await _tap(KEY_ENTER)
		_check(not office.hud.card_compact(), "%s: Enter opens the card up" % screen)
		await _reading_again(card)
		await _tap(KEY_ESCAPE)
		_check(office.hud.card_compact(), "%s: Escape folds it back" % screen)
		await _quiet(card, "%s: the card is folded back" % screen)
		root.remove_child(office)
		office.free()


## With no fleet (the showroom, a HUD on its own) the card says unavailable and
## offers nothing, and never errors.
func test_a_card_without_a_fleet_is_unavailable() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: OfficeHud = scene.instantiate()
	hud.dress(art, OfficeDraw.new(art).font)
	root.add_child(hud)
	hud.fit(Vector2(SCREEN))
	var pane := PaneModel.new()
	pane.pane_id = "alpha:p3"
	pane.key = HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3")
	pane.terminal_id = "term-alpha-3"
	pane.provider = "codex"
	pane.state = "blocked"
	hud.inspector.show_pane(pane, "", false, OfficePaneInspector.Pick.PICKED)
	await _frames(3)
	var card := hud.inspector
	_eq(
		[card.preview_state(), card.preview_reason()],
		[OfficePaneInspector.PreviewState.UNAVAILABLE, CommandRefusal.Reason.NOT_CONNECTED],
		"unavailable"
	)
	var button: Button = card.get_node("%FocusButton")
	_check(not button.is_visible_in_tree(), "no switch without a fleet")
	_check(not card.reading(), "and nothing read")
	var hint: Button = card.get_node("%AnswerButton")
	_check(not hint.is_visible_in_tree() and not card.answer_offered(), "no answering without a fleet")
	var answer: Control = card.get_node("%Answer")
	_check(not answer.is_visible_in_tree(), "and no answer controls")
	hud.free()


# --- read-only and flags ----------------------------------------------------------


## `--read-only`: no command of any kind, and the office says which mode it is in.
func test_read_only_sends_only_ping_snapshot_and_subscribe() -> void:
	_fakes()
	var logs := Captured.new()
	OS.add_logger(logs)
	var office := await _office_with(true)
	_check(office.fleet.read_only(), "a read-only fleet")
	_check(_logged(logs, "OFFICE_START: read-only herdr client on " + args["socket-a"]), "the startup line says so")
	_check(
		office.hud.bar.status_line().begins_with("LIVE / READ ONLY"), "so does the bar: " + office.hud.bar.status_line()
	)
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	_eq(
		[card.preview_state(), card.preview_reason()],
		[OfficePaneInspector.PreviewState.UNAVAILABLE, CommandRefusal.Reason.READ_ONLY],
		"no preview"
	)
	_check(not _switch(office).is_visible_in_tree(), "no switch")
	_check(not _control(office, "AnswerButton").is_visible_in_tree(), "no answering offered")
	await _tap(KEY_ENTER)
	_check(not card.answering() and not _control(office, "Answer").is_visible_in_tree(), "Enter opens nothing")
	var key := HerdrFleet.pane_key(BEE, "alpha:p3")
	var target := office.fleet.context_for(key, 1)
	_eq(_refusal(office.fleet.send_keys(target.keying("y", null))), CommandRefusal.Reason.READ_ONLY, "no key")
	_eq(_refusal(office.fleet.send_line(target.replying("ok", null))), CommandRefusal.Reason.READ_ONLY, "no line")
	_eq(office.fleet.can_operate(key, CommandContext.Kind.KEYS), CommandRefusal.Reason.READ_ONLY, "none may be")
	_eq(
		_refusal(office.fleet.focus_pane(office.fleet.context_for(key, 1).focusing())),
		CommandRefusal.Reason.READ_ONLY,
		"no write"
	)
	var read := office.fleet.read_pane(office.fleet.context_for(key, 1).reading(CommandContext.SOURCE_RECENT, 12))
	_eq(_refusal(read), CommandRefusal.Reason.READ_ONLY, "no read")
	_eq([office.fleet.write_log().size(), office.fleet.read_log().size()], [0, 0], "nothing to audit")
	await _wait(2.0)
	for which: String in ["control-a", "control-b"]:
		for method: String in _list(_ctl(which, "stats"), "methods"):
			_check(method in READ_ONLY_METHODS, "%s heard only read-only requests, not %s" % [which, method])
	var operator := await _office_with(false, false)
	OS.remove_logger(logs)
	_check(not operator.fleet.read_only(), "without the flag, an operator")
	_check(_logged(logs, "OFFICE_START: operator herdr client on " + args["socket-a"]), "whose startup line says so")
	_check(operator.hud.bar.status_line().begins_with("LIVE / OPERATOR"), "and bar: " + operator.hud.bar.status_line())


## `--read-only` counts on either side of `--`; a misspelling stops the office
## with a marker before it starts anything.
func test_the_read_only_flag_counts_anywhere_and_a_misspelling_stops() -> void:
	var before := AppArgs.parse(PackedStringArray(["--socket=x"]), PackedStringArray(["--read-only", "--quit"]))
	_check(before.read_only(), "before --")
	_check(AppArgs.parse(PackedStringArray(["--read-only"])).read_only(), "after --")
	_check(not AppArgs.parse(PackedStringArray(["--socket=x"])).read_only(), "and without it, an operator")
	_eq(
		AppArgs.parse(PackedStringArray(["--read-only"]), PackedStringArray(["--read-only"])).problems().size(),
		0,
		"fine"
	)
	# Any case, any run of dashes, and the dashes an editor or a paste puts in
	# place of `--` (en and em dash, minus sign, full-width hyphen-minus).
	var spellings: Array[String] = ["--readonly", "--read-only=yes", "--read_only", "--read"]
	spellings.append_array(["--Read-Only", "--READ-ONLY", "-read-only", "---read-only", "-Read_Only"])
	for dash: int in [0x2013, 0x2014, 0x2212, 0xff0d]:
		spellings.append(char(dash) + "read-only")
		spellings.append(char(dash) + char(dash) + "read-only")
	for spelled in spellings:
		_eq(AppArgs.parse(PackedStringArray([spelled])).problems().size(), 1, spelled + " after -- is refused")
		_eq(
			AppArgs.parse(PackedStringArray(), PackedStringArray([spelled])).problems().size(),
			1,
			spelled + " before --"
		)
		_check(not AppArgs.parse(PackedStringArray([spelled])).read_only(), spelled + " is not the switch itself")
	# A bare word and a value that merely contain it are not a flag. No flag of
	# this office begins with `read`, so any that does is refused, `--ready` too.
	var others: Dictionary[String, int] = {
		"read-only": 0, "--socket=/tmp/read-only.sock": 0, "--pack=res://read.json": 0, "--ready": 1
	}
	for other: String in others:
		_eq(AppArgs.parse(PackedStringArray([other])).problems().size(), others[other], other)
	var nowhere := args.work.path_join("flag-nowhere.sock")
	var output: Array = []
	var status := _godot(
		PackedStringArray(["--quit"]), PackedStringArray(["--socket=" + nowhere, "--readonly"]), output
	)
	var text := "".join(output)
	_check(text.contains("ARGS_ERROR: --readonly is not --read-only"), "the marker names it: " + text.right(400))
	_check(status != 0, "the office exits non-zero: %d" % status)
	_check(not text.contains("OFFICE_START"), "before it starts anything")
	# The same for an em-dashed switch, as a text editor writes `--`.
	var dashed := char(0x2014) + "read-only"
	output = []
	status = _godot(PackedStringArray(["--quit"]), PackedStringArray(["--socket=" + nowhere, dashed]), output)
	text = "".join(output)
	_check(text.contains("ARGS_ERROR: %s is not --read-only" % dashed), "an em dash is refused: " + text.right(400))
	_check(status != 0 and not text.contains("OFFICE_START"), "and stops the office before it starts: %d" % status)
	output = []
	status = _godot(PackedStringArray(["--read-only", "--quit"]), PackedStringArray(["--socket=" + nowhere]), output)
	text = "".join(output)
	_check(
		text.contains("OFFICE_START: read-only herdr client on " + nowhere),
		"before -- it is read-only: " + text.right(400)
	)
	_eq(status, 0, "and runs")


# --- privacy -------------------------------------------------------------------


## Terminal text is shown on the card and nowhere else: not in any logged
## message, not in the audit, not in a failure.
func test_terminal_text_never_reaches_a_log_or_the_audit() -> void:
	_fakes()
	for which: String in ["control-a", "control-b"]:
		for pane_id: String in ["alpha:p1", "alpha:p2", "alpha:p3", "bravo:p1"]:
			_ctl(which, "set_preview", {"pane_id": pane_id, "text": "secret %s\n\u0007%s\n" % [SENTINEL, SENTINEL]})
	var logs := Captured.new()
	OS.add_logger(logs)
	var office := await _office_with()
	var card := _card(office)
	await _pick_bee(office, "alpha:p3")
	await _until(func() -> bool: return card.preview_text().contains(SENTINEL), "the card shows it; that is its job")
	var fleet := office.fleet
	var failing: Array[CommandTicket] = []
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p1", "text": SENTINEL, "fill": HerdrCommands.READ_LINE_MAX})
	var bee_p1 := fleet.context_for(HerdrFleet.pane_key(BEE, "alpha:p1"), 1)
	failing.append(fleet.read_pane(bee_p1.reading(CommandContext.SOURCE_RECENT, 12)))
	_ctl("control-a", "next", {"action": "close_midreply", "method": "pane.read"})
	var local_p3 := fleet.context_for(HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3"), 1)
	failing.append(fleet.read_pane(local_p3.reading(CommandContext.SOURCE_RECENT, 12)))
	for ticket in failing:
		await _until(ticket.is_finished, "a failing read settles")
		_eq(ticket.state, CommandTicket.State.UNKNOWN, "it failed")
		_check(not SENTINEL in ticket.failure, "its failure says nothing of the text")
	# Lines that are not JSON, with the secret where a value belongs: a read's
	# answer (HerdrCommands), a stream line and a snapshot answer (HerdrClient).
	# JSON.parse_string() would quote the word into the log; nothing may.
	card.visible = false
	await _until(func() -> bool: return not card.reading(), "the card's own reads stop")
	var garbled := '{"id":"$ID","result":{"type":"pane_read","read":%s}}' % SENTINEL_WORD
	_ctl("control-b", "next", {"action": "reply", "method": "pane.read", "line": garbled})
	var unreadable := fleet.read_pane(bee_p1.reading(CommandContext.SOURCE_RECENT, 12))
	await _until(unreadable.is_finished, "the garbled read settles")
	_eq([unreadable.state, unreadable.failure], [CommandTicket.State.UNKNOWN, "an unreadable answer"], "unreadable")
	# A line carrying the secret goes to herdr and nowhere else; a re-read
	# herdr garbles, before another such line, leaves no trace of either.
	var bee_p3 := fleet.context_for(HerdrFleet.pane_key(BEE, "alpha:p3"), 1)
	var aimed_at := fleet.read_pane(bee_p3.reading(CommandContext.SOURCE_RECENT, 12))
	await _until(aimed_at.is_finished, "a read to aim the line at")
	var said := fleet.send_line(bee_p3.replying("say " + SENTINEL, CommandPreview.of(aimed_at, 1)))
	await _until(said.is_finished, "the line settles")
	_eq(said.state, CommandTicket.State.ACCEPTED, "the line went")
	var local_seen := fleet.read_pane(local_p3.reading(CommandContext.SOURCE_RECENT, 12))
	await _until(local_seen.is_finished, "a read of Local's alpha:p3")
	var check := {"action": "reply", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "line": garbled}
	_ctl("control-a", "next", check)
	var unchecked := fleet.send_line(local_p3.replying(SENTINEL, CommandPreview.of(local_seen, 1)))
	await _until(unchecked.is_finished, "the line whose re-read is garbled settles")
	_eq(
		[unchecked.state, unchecked.refusal],
		[CommandTicket.State.REFUSED, CommandRefusal.Reason.RECHECK_FAILED],
		"not sent: no re-read"
	)
	_check(not SENTINEL in unchecked.failure and not SENTINEL_WORD in unchecked.failure, "its failure quotes nothing")
	_ctl("control-a", "raw", {"chunks": [SENTINEL_WORD + " on the stream\n"]})
	var snapshots := _count("control-a", "session.snapshot")
	var reply := '{"id":"$ID","result":{"type":"session_snapshot","snapshot":%s}}' % SENTINEL_WORD
	_ctl("control-a", "next", {"action": "reply", "method": "session.snapshot", "line": reply})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(
		func() -> bool: return _count("control-a", "session.snapshot") > snapshots, "the garbled snapshot is asked for"
	)
	await _wait(1.0)
	OS.remove_logger(logs)
	_check(not logs.lines().is_empty(), "the logger heard the office")
	for line in logs.lines():
		_check(not SENTINEL in line, "a logged line holds terminal text: " + line.left(120))
		_check(not SENTINEL_WORD in line, "a logged line quotes a line herdr garbled: " + line.left(120))
	for entry in fleet.read_log() + fleet.write_log():
		_check(not SENTINEL in _entry_text(entry), "an audit entry holds terminal text")
		_check(not SENTINEL_WORD in _entry_text(entry), "an audit entry quotes a garbled line")


# --- helpers only these cases use ------------------------------------------------


func _schema_methods() -> PackedStringArray:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "herdr_methods.json"))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	return PackedStringArray(_list(data, "methods"))


## The fixture's `allowlist`: what scripts/herdr_commands.gd names, sorted.
func _schema_allowlist() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "herdr_methods.json"))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var found := _list(data, "allowlist").duplicate()
	found.sort()
	return found


## Every herdr method `source` names as a quoted literal, sorted.
func _named(source: String, methods: PackedStringArray) -> Array:
	var found: Array = []
	for method in methods:
		if source.contains('"%s"' % method):
			found.append(method)
	found.sort()
	return found


func _gd_files(root_dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	var pending := PackedStringArray([root_dir])
	while not pending.is_empty():
		var dir_path := pending[pending.size() - 1]
		pending.remove_at(pending.size() - 1)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for name in dir.get_directories():
			pending.append(dir_path.path_join(name))
		for name in dir.get_files():
			if name.ends_with(".gd"):
				found.append(dir_path.path_join(name))
	return found


## `key` on `fleet` is live and current again with the identity `held` was aimed at.
func _ready_as(fleet: HerdrFleet, key: String, held: CommandContext) -> bool:
	var parts := HerdrFleet.split_key(key)
	if not fleet.snapshot_is_current(parts[0]):
		return false
	return fleet.context_for(key, 1).identity_key == held.identity_key


## No read reaches bee for 1.6 s once the one in flight, if any, has settled:
## longer than a blocked pane's 1 s cadence, so the pane under watch must be blocked.
func _quiet(card: OfficePaneInspector, why: String) -> void:
	await _until(func() -> bool: return not card.reading(), "the read in flight settles (%s)" % why)
	var before := _count("control-b", "pane.read")
	await _wait(1.6)
	_eq(_count("control-b", "pane.read"), before, "no read while " + why)


func _reading_again(card: OfficePaneInspector) -> void:
	var before := _count("control-b", "pane.read")
	await _until(func() -> bool: return _count("control-b", "pane.read") > before, "reads resume")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "and show")


func _logged(logs: Captured, prefix: String) -> bool:
	return logs.lines().any(func(line: String) -> bool: return line.begins_with(prefix))


## Every button of the staff panel shows its whole label, never an ellipsis:
## the switch naming its machine, its note, Monitor and Answer, and in answer
## mode every key, at 960x480 (the 1920x960 window at 2x), at 800x480, and at the
## 480x320 minimum (the 960x640 window at 2x, the 1920x1280 one at 4x) opened
## up. The action column takes the room its labels need from the preview.
func test_the_staff_panels_buttons_show_their_whole_labels() -> void:
	var office := await _blocked_bee(QUESTION, Vector2(960, 480))
	var card := _card(office)
	_eq(_switch(office).text, "Switch herdr on bee", "the switch names its machine")
	for screen: Vector2 in [Vector2(960, 480), Vector2(800, 480), Vector2(480, 320)]:
		office.test_screen = screen
		office.refresh()
		await _frames(3)
		# The panel stays open across the resizes (a new window moves no
		# panel); answer mode by Enter, and Esc leaves it with the panel open.
		var compact := office.hud.card_compact()
		if not compact:
			_check(_switch(office).is_visible_in_tree(), "the switch is offered at %s" % screen)
			_whole_labels(card, "%s" % screen)
		await _open_answer(office)
		await _frames(3)
		_whole_labels(card, "%s, answer mode" % screen)
		await _tap(KEY_ESCAPE)
		await _frames(3)
	# Opened up without answer mode: Enter on a working agent, which has nothing to answer.
	await _pick_bee(office, "alpha:p1")
	await _tap(KEY_ENTER)
	await _frames(3)
	_check(not office.hud.card_compact() and not card.answering(), "a working agent's panel opened up")
	_check(_switch(office).is_visible_in_tree(), "the opened panel offers the switch")
	_whole_labels(card, "(480, 320), opened up")
	await _tap(KEY_ESCAPE)
	await _frames(2)
	_check(office.hud.card_compact(), "and Esc folds it back to its line")
	# The one line's own buttons (`‹ ›`, Monitor, Open, NEXT), short and long words.
	_whole_labels(card, "(480, 320), one line")
	office.test_screen = Vector2(800, 480)
	office.refresh()
	await _frames(3)
	_check(office.hud.card_compact(), "800x480: still one line")
	_eq((card.get_node("%CompactOpen") as Button).text, "Open ⏎", "in its long words")
	_whole_labels(card, "(800, 480), one line")
	_eq(_all_inputs(), 0, "nothing was sent")


## Each visible Button of `card` as wide as its label and padding need, and
## inside every ancestor that clips; the switch's note likewise. `what` names the state.
func _whole_labels(card: OfficePaneInspector, what: String) -> void:
	var controls: Array[Control] = [card.get_node("%FocusNote")]
	for node: Node in card.find_children("*", "Button", true, false):
		controls.append(node as Control)
	for control in controls:
		if not control.is_visible_in_tree():
			continue
		var text: String = control.get("text")
		if text.is_empty():
			continue
		var font := control.get_theme_font("font")
		var needed := (
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x
		)
		if control is Button:
			needed += control.get_theme_stylebox("normal").get_minimum_size().x
		var rect := control.get_global_rect()
		_check(rect.size.x >= needed - 0.5, "%s: `%s` whole (%.0f of %.0f)" % [what, text, rect.size.x, needed])
		var above := control.get_parent()
		while above is Control:
			var holder: Control = above
			if holder.clip_contents and not holder.get_global_rect().grow(0.5).encloses(rect):
				_fail("%s: `%s` %s is cut by %s %s" % [what, text, rect, holder.name, holder.get_global_rect()])
			above = holder.get_parent()


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation but the one a case provoked on purpose.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)
