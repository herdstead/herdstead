extends "res://tools/command_test_base.gd"
## The terminal monitor's raw mode at the write boundary (docs/WRITE_BOUNDARY.md §3),
## against two fake herdrs of this suite's own whose pane ids collide: its
## `ansi` reads and their sources, the raw key table, typing and pasting, the
## order, bound and pace of the queue, a lost answer, the refusals (offline,
## stale, replaced), the audit without text, no write without a gesture,
## `--read-only`, and input that follows the terminal, not its agent. Run
## through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_raw_input.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## The boundary's cases pump a HerdrCommands outside the tree on synthetic
## time; the monitor runs in a live office on real frames, driven by real input.
## The last case sums up both fakes: nothing reached them that no case opened.


func _marker() -> String:
	return "RAW INPUT TESTS"


# --- raw mode: the terminal monitor (docs/WRITE_BOUNDARY.md §3) -------------------


## The monitor's read is its own kind: `visible` with no line count, or
## `recent` with 1 to 999 lines, always `ansi` and never stripped. The card's
## read still refuses both sources. The answer keeps ESC for the SGR parser,
## drops every other control, must be `ansi` and must name the pane asked.
func test_the_monitor_reads_ansi_and_only_its_own_sources() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p1")
	var refused: Array[CommandContext] = [
		target.screening(CommandContext.SOURCE_VISIBLE, 12),
		target.screening(CommandContext.SOURCE_SCROLLBACK, 0),
		target.screening(CommandContext.SOURCE_SCROLLBACK, 1000),
		target.screening(CommandContext.SOURCE_DETECTION, 0),
		target.screening(CommandContext.SOURCE_RECENT, 12),
		target.reading(CommandContext.SOURCE_VISIBLE, 12),
	]
	for context in refused:
		_eq(HerdrCommands.refusal(context, facts), CommandRefusal.Reason.NOT_ALLOWED, "refused: %s" % context.source)
	var commands := _boundary()
	var screen := "\u001b[0m\u001b[38;5;2mok\u001b[0m \u0007bell\u202eflip\r\nrow two"
	_ctl("control-a", "set_screen", {"pane_id": "alpha:p1", "source": "visible", "ansi": screen, "revision": 7})
	var read := commands.submit(target.screening(CommandContext.SOURCE_VISIBLE, 0), facts)
	_settle(commands, read, "the screen read")
	_eq(read.state, CommandTicket.State.ACCEPTED, "read")
	var kept := "\u001b[0m\u001b[38;5;2mok\u001b[0m bellflip\r\nrow two"
	_eq(read.screen.text if read.screen != null else "", kept, "ESC, CR and LF kept, BEL and bidi dropped")
	if read.screen != null:
		_eq([read.screen.revision, read.screen.source, read.screen.cut], [7, "visible", false], "its fields")
	var payload: Dictionary = _asked("control-a", "pane.read").back()
	_eq(
		payload,
		{"pane_id": "alpha:p1", "source": "visible", "format": "ansi", "strip_ansi": false},
		"exactly the monitor's payload, no line count"
	)
	var back := commands.submit(target.screening(CommandContext.SOURCE_SCROLLBACK, 999), facts)
	_settle(commands, back, "the scrollback read")
	var scrollback: Dictionary = _asked("control-a", "pane.read").back()
	_eq(scrollback.get("lines"), 999, "recent asks for its lines")
	# Another format, or another pane's answer, is no screen at all.
	var text_reply := (
		'{"id":"$ID","result":{"type":"pane_read","read":{"pane_id":"alpha:p1","source":"visible",'
		+ '"format":"text","text":"x","revision":0,"truncated":false}}}'
	)
	_ctl("control-a", "next", {"action": "reply", "method": "pane.read", "line": text_reply})
	var plain := commands.submit(target.screening(CommandContext.SOURCE_VISIBLE, 0), facts)
	_settle(commands, plain, "a text answer")
	_eq([plain.state, plain.failure], [CommandTicket.State.UNKNOWN, "an unreadable screen"], "text is not ansi")
	var elsewhere := text_reply.replace("alpha:p1", "alpha:p2").replace('"text","text"', '"ansi","text"')
	_ctl("control-a", "next", {"action": "reply", "method": "pane.read", "line": elsewhere})
	var other := commands.submit(target.screening(CommandContext.SOURCE_VISIBLE, 0), facts)
	_settle(commands, other, "another pane's answer")
	_eq(other.state, CommandTicket.State.UNKNOWN, "another pane's screen is refused")
	_eq(commands.read_log().back().source, "visible", "reads are audited as reads")
	_eq(commands.write_log().size(), 0, "and nothing was a write")
	_eq(_all_inputs(), 0, "reads write nothing")
	commands.free()


## Every name of the measured key table passes the raw key map, spelled as herdr
## does; everything else is refused at the send port with a typed reason,
## although herdr, and the fake, take far more. Home, End, PgUp, PgDn, Insert
## and Delete say they cannot be sent. What passes reaches herdr in order, in one request.
func test_raw_keys_are_the_table_and_nothing_else() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var table := PackedStringArray(["a", "A", "!", "\\", "+", "~", "enter", "tab", "shift+tab", "backspace", "esc"])
	table.append_array(["space", "ctrl+space", "shift+enter", "ctrl+enter", "alt+enter"])
	for letter: String in "az":
		table.append_array(["ctrl+" + letter, "alt+" + letter, "alt+shift+" + letter, "ctrl+alt+" + letter])
	for symbol: String in "[\\]^_@":
		table.append("ctrl+" + symbol)
	table.append_array(["alt+1", "alt+.", "alt+/"])
	for arrow: String in ["up", "down", "left", "right"]:
		for prefix: String in ["", "ctrl+", "alt+", "shift+", "ctrl+shift+"]:
			table.append(prefix + arrow)
	for number in range(1, 13):
		table.append("f%d" % number)
	for name in table:
		_eq(HerdrCommands.raw_key_refusal(name), CommandRefusal.Reason.NONE, "in the table: " + name)
	for name: String in ["home", "end", "pageup", "pagedown", "insert", "delete"]:
		_eq(HerdrCommands.raw_key_refusal(name), CommandRefusal.Reason.KEY_UNREACHABLE, "herdr has no " + name)
	var outside := ["C-c", "ctrl+C", "Ctrl+c", "Enter", "ENTER", "return", "escape", "f13", "f0", "shift+f1", "ctrl+f1"]
	outside.append_array(["ctrl+shift+a", "meta+a", "alt+A", "ctrl+1", "ctrl+", "alt+", "", " ", "ctrl+ab", "tab+x"])
	outside.append_array(["alt+shift+1", "ctrl+alt+up", "alt+space", "PageUp", "del", char(0x1b), char(0x03), "中"])
	var commands := _boundary()
	for name: String in outside:
		var reason := HerdrCommands.raw_key_refusal(name)
		var said := "refused: %s (%s)" % [name.c_escape(), CommandRefusal.name_of(reason)]
		_check(reason == CommandRefusal.Reason.KEY_UNSUPPORTED, said)
		var ticket := commands.submit(target.typing_keys(PackedStringArray([name])), facts, _facts_now(facts))
		_eq(ticket.state, CommandTicket.State.REFUSED, "refused at the send port: " + name.c_escape())
	var one := commands.submit(target.typing_keys(PackedStringArray(["up", "home"])), facts, _facts_now(facts))
	_eq(one.refusal, CommandRefusal.Reason.KEY_UNREACHABLE, "one unreachable key refuses its request whole")
	var none := commands.submit(target.typing_keys(PackedStringArray()), facts)
	_eq(none.refusal, CommandRefusal.Reason.INPUT_EMPTY, "no keys")
	_eq(_all_inputs(), 0, "nothing refused reached herdr")
	var all := commands.submit(target.typing_keys(table), facts, _facts_now(facts))
	_settle(commands, all, "the whole table")
	_eq(all.state, CommandTicket.State.ACCEPTED, "the whole table goes")
	var inputs := _inputs("control-a")
	_eq(inputs.size(), 1, "as one request")
	var sent: Dictionary = inputs[0] if not inputs.is_empty() else {}
	_eq(PackedStringArray(_list(sent, "keys")), table, "exactly those names, in order")
	commands.free()


## Typed text is sent as it is, never bracketed; control characters go as
## keys and are refused as text. A paste goes through the paste path, which
## herdr brackets when the program asked; ESC or a C1 control anywhere in it,
## or more than 64 KiB, refuses it whole: nothing is cut.
func test_a_paste_refuses_escape_and_size_and_is_bracketed_by_herdr() -> void:
	_fakes()
	_ctl("control-a", "set_paste_mode", {"pane_id": "alpha:p2"})
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var commands := _boundary()
	var refused: Dictionary[String, CommandRefusal.Reason] = {
		"": CommandRefusal.Reason.INPUT_EMPTY,
		"ok\u001b[201~rm -rf x\n": CommandRefusal.Reason.PASTE_ESCAPE,
		"\u001b": CommandRefusal.Reason.PASTE_ESCAPE,
		"csi \u009b201~": CommandRefusal.Reason.PASTE_ESCAPE,
		"x".repeat(HerdrCommands.PASTE_BYTES_MAX + 1): CommandRefusal.Reason.PASTE_TOO_LONG,
		"中".repeat(21846): CommandRefusal.Reason.PASTE_TOO_LONG,
		"broken �": CommandRefusal.Reason.TEXT_BROKEN,
	}
	for pasted: String in refused:
		var ticket := commands.submit(target.pasting(pasted), facts, _facts_now(facts))
		_eq(ticket.refusal, refused[pasted], "paste refused: %s…" % pasted.left(12).c_escape())
	var typed: Dictionary[String, CommandRefusal.Reason] = {
		"": CommandRefusal.Reason.INPUT_EMPTY,
		"a\u001b": CommandRefusal.Reason.TEXT_CONTROL,
		"a\n": CommandRefusal.Reason.TEXT_CONTROL,
		"a\u0003": CommandRefusal.Reason.TEXT_CONTROL,
		"\u0085": CommandRefusal.Reason.TEXT_CONTROL,
		"x".repeat(HerdrCommands.TEXT_BYTES_MAX + 1): CommandRefusal.Reason.TEXT_TOO_LONG,
	}
	for text: String in typed:
		var ticket := commands.submit(target.typing_text(text), facts, _facts_now(facts))
		_eq(ticket.refusal, typed[text], "typed text refused: %s" % text.left(12).c_escape())
	_eq(_all_inputs(), 0, "nothing refused reached herdr")
	var whole := "line one\n\tline two ✓ 中文\n" + "y".repeat(HerdrCommands.PASTE_BYTES_MAX - 30)
	_eq(whole.to_utf8_buffer().size(), HerdrCommands.PASTE_BYTES_MAX, "exactly 64 KiB")
	var paste := commands.submit(target.pasting(whole), facts, _facts_now(facts))
	var text_ticket := commands.submit(target.typing_text("héllo 👍🏽"), facts, _facts_now(facts))
	_settle(commands, paste, "the paste")
	_settle(commands, text_ticket, "the typed text")
	_eq([paste.state, text_ticket.state], [CommandTicket.State.ACCEPTED, CommandTicket.State.ACCEPTED], "both went")
	var inputs := _inputs("control-a")
	_eq(inputs.size(), 2, "two requests")
	var pasted_in: Dictionary = inputs[0] if inputs.size() == 2 else {}
	var typed_in: Dictionary = inputs[1] if inputs.size() == 2 else {}
	var whole_in := [pasted_in.get("method"), pasted_in.get("text") == whole, pasted_in.get("keys")]
	_eq(whole_in, ["pane.send_input", true, []], "the paste, whole")
	_check(str(pasted_in.get("bracketed")) == "true", "herdr brackets a paste when the program asked")
	_eq([typed_in.get("method"), typed_in.get("text")], ["pane.send_text", "héllo 👍🏽"], "typed text as it is")
	_check(str(typed_in.get("bracketed")) == "false", "and never bracketed")
	commands.free()


## Raw input to one pane is written in the order it was given, one request at
## a time: the second waits for the first's answer, whatever the kinds.
func test_raw_input_keeps_its_order_one_request_at_a_time() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "hold", "method": "pane.send_keys"})
	var tickets: Array[CommandTicket] = [
		commands.submit(target.typing_keys(PackedStringArray(["ctrl+c"])), facts, _facts_now(facts)),
		commands.submit(target.typing_text("ab"), facts, _facts_now(facts)),
		commands.submit(target.typing_keys(PackedStringArray(["enter", "up"])), facts, _facts_now(facts)),
		commands.submit(target.pasting("pasted"), facts, _facts_now(facts)),
		commands.submit(target.typing_text("z"), facts, _facts_now(facts)),
	]
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(2000)
	_eq(tickets[0].state, CommandTicket.State.SENT, "the first is out, its answer held")
	_eq(tickets.slice(1).map(func(t: CommandTicket) -> int: return t.state), [0, 0, 0, 0], "the rest wait, unsent")
	_eq(commands.queued_events(target.pane_key), 2 + 2 + 1 + 1, "their events are queued")
	_eq(_inputs("control-a").size(), 1, "herdr has only the first")
	_ctl("control-a", "release_held")
	for ticket in tickets:
		_settle(commands, ticket, "each in turn")
	_eq(tickets.map(func(t: CommandTicket) -> int: return t.state), [2, 2, 2, 2, 2], "all accepted")
	var described := func(record: Dictionary) -> String:
		return "%s %s %s" % [record.get("method"), record.get("keys"), record.get("text")]
	var order := _inputs("control-a").map(described)
	_eq(
		order,
		[
			'pane.send_keys ["ctrl+c"] <null>',
			"pane.send_text [] ab",
			'pane.send_keys ["enter", "up"] <null>',
			"pane.send_input [] pasted",
			"pane.send_text [] z",
		],
		"herdr got them in order"
	)
	_check(not commands.writing(target.pane_key), "nothing open or queued after")
	commands.free()


## A pane's queue holds RAW_QUEUE_EVENTS events: the one that would overflow it
## is refused, QUEUE_FULL, and nothing already queued is dropped.
func test_the_raw_queue_is_bounded_and_refuses_the_newest() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "hold", "method": "pane.send_text"})
	var first := commands.submit(target.typing_text("first"), facts, _facts_now(facts))
	var deadline := Time.get_ticks_msec() + 1500
	while first.state == CommandTicket.State.UNSENT and Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(1000)
	var many := "q".repeat(HerdrCommands.RAW_QUEUE_EVENTS - 1)
	var full := commands.submit(target.typing_text(many), facts, _facts_now(facts))
	var last := commands.submit(target.typing_keys(PackedStringArray(["enter"])), facts, _facts_now(facts))
	_eq(commands.queued_events(target.pane_key), HerdrCommands.RAW_QUEUE_EVENTS, "the queue is full")
	var over := commands.submit(target.typing_keys(PackedStringArray(["up"])), facts, _facts_now(facts))
	_eq([over.state, over.refusal], [CommandTicket.State.REFUSED, CommandRefusal.Reason.QUEUE_FULL], "newest refused")
	_eq([full.state, last.state], [CommandTicket.State.UNSENT, CommandTicket.State.UNSENT], "nothing queued is dropped")
	_eq(commands.write_log().back().refusal, "QUEUE_FULL", "the audit says why")
	_ctl("control-a", "release_held")
	_settle(commands, last, "the queue drains")
	var short := func(r: Dictionary) -> String: return str(r.get("keys")) + str(r.get("text")).left(3)
	_eq(_inputs("control-a").map(short), ["[]fir", "[]qqq", '["enter"]<nu'], "all three went, the refused one never")
	commands.free()


## About 60 requests a second per pane: the next starts no sooner than
## RAW_INTERVAL_MSEC after the one before, however fast herdr answers.
func test_raw_input_is_paced_to_sixty_a_second() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var commands := _boundary()
	var now: Array[int] = [1000000]
	commands.clock = func() -> int: return now[0]
	var tickets: Array[CommandTicket] = []
	for letter: String in "abc":
		tickets.append(commands.submit(target.typing_text(letter), facts, _facts_now(facts)))
	_settle(commands, tickets[0], "the first")
	var deadline := Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(2000)
	_eq(tickets[1].state, CommandTicket.State.UNSENT, "the second waits: no time has passed")
	now[0] += HerdrCommands.RAW_INTERVAL_MSEC - 1
	commands.pump(0.0)
	_eq(tickets[1].state, CommandTicket.State.UNSENT, "still waits one millisecond short")
	now[0] += 1
	_settle(commands, tickets[1], "the second, on time")
	commands.pump(0.0)
	_eq(tickets[2].state, CommandTicket.State.UNSENT, "the third waits its own interval")
	now[0] += HerdrCommands.RAW_INTERVAL_MSEC
	_settle(commands, tickets[2], "the third")
	_eq(_inputs("control-a").size(), 3, "three requests, paced")
	_check(1000.0 / HerdrCommands.RAW_INTERVAL_MSEC <= 60.0, "never more than 60 a second")
	commands.free()


## A raw input whose answer is lost is UNKNOWN and never sent again; the
## terminal is live, so what the viewer types next still goes.
func test_a_lost_raw_answer_is_unknown_and_later_input_still_goes() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "pane.send_keys"})
	var lost := commands.submit(target.typing_keys(PackedStringArray(["ctrl+c"])), facts, _facts_now(facts))
	var after := commands.submit(target.typing_text("ls"), facts, _facts_now(facts))
	_settle(commands, lost, "the lost answer")
	_eq(lost.state, CommandTicket.State.UNKNOWN, "unknown: herdr may have acted")
	_settle(commands, after, "the next input")
	_eq(after.state, CommandTicket.State.ACCEPTED, "the next still goes: no look is owed in raw mode")
	var later := commands.submit(target.typing_text("x"), facts, _facts_now(facts))
	_settle(commands, later, "one more")
	await _frames(3)
	_eq(_inputs("control-a").size(), 3, "three carried out, the lost one once")
	_eq(_count("control-a", "pane.send_keys"), 1, "never resent")
	# The card's own writes still owe a look after raw input (answer mode's rules hold).
	var answer := commands.submit(target.focusing(), facts)
	_eq(answer.refusal, CommandRefusal.Reason.LOOK_FIRST, "a switch after raw input waits for a look")
	await _look(commands, facts, "alpha:p2")
	_check(not commands.must_look(target.pane_key), "a shown read is the look")
	commands.free()


## Offline, stale, replaced, gone or on an unknown protocol: raw input is
## refused with that reason at the gesture, and whatever is still queued when
## its turn comes, or when the machine drops, is refused too. None of it is written.
func test_raw_input_is_refused_offline_stale_or_replaced() -> void:
	_fakes()
	var target := _aim(_facts(args["socket-a"], _raw()), "alpha:p2")
	var cases: Dictionary[String, CommandRefusal.Reason] = {
		"offline": CommandRefusal.Reason.MACHINE_OFFLINE,
		"stale": CommandRefusal.Reason.SNAPSHOT_NOT_CURRENT,
		"replaced": CommandRefusal.Reason.MACHINE_REPLACED,
		"protocol": CommandRefusal.Reason.UNKNOWN_PROTOCOL,
		"gone": CommandRefusal.Reason.MACHINE_GONE,
	}
	for what: String in cases:
		var facts := _facts(args["socket-a"], _raw())
		var holder: Array[HerdrCommands.Machine] = [facts]
		var known := func() -> HerdrCommands.Machine: return holder[0]
		var commands := _boundary()
		_ctl("control-a", "next", {"action": "hold", "method": "pane.send_text"})
		var first := commands.submit(target.typing_text("first"), facts, known)
		var deadline := Time.get_ticks_msec() + 1500
		while first.state == CommandTicket.State.UNSENT and Time.get_ticks_msec() < deadline:
			commands.pump(0.0)
			OS.delay_usec(1000)
		var queued: Array[CommandTicket] = [
			commands.submit(target.typing_keys(PackedStringArray(["enter"])), facts, known),
			commands.submit(target.typing_text("more"), facts, known),
		]
		match what:
			"offline":
				facts.online = false
			"stale":
				facts.current = false
			"replaced":
				facts.generation += 1
			"protocol":
				facts.protocol = 99
			"gone":
				holder[0] = null
		var gesture := commands.submit(target.typing_text("x"), holder[0])
		_eq(gesture.refusal, cases[what], "%s: refused at the gesture" % what)
		_ctl("control-a", "release_held")
		_settle(commands, first, "the one out")
		for ticket in queued:
			_settle(commands, ticket, "the queued ones")
		_eq(
			queued.map(func(t: CommandTicket) -> CommandRefusal.Reason: return t.refusal),
			[cases[what], cases[what]],
			"%s: every queued input refused when its turn came" % what
		)
		_eq(_inputs("control-a").size(), 1, "%s: only the one already out reached herdr" % what)
		commands.free()
		_fakes()
	# The machine dropping, or being replaced, refuses the queue with that reason at once.
	for why: CommandRefusal.Reason in [CommandRefusal.Reason.MACHINE_OFFLINE, CommandRefusal.Reason.MACHINE_REPLACED]:
		var facts := _facts(args["socket-a"], _raw())
		var commands := _boundary()
		_ctl("control-a", "next", {"action": "hold", "method": "pane.send_text"})
		var out := commands.submit(target.typing_text("out"), facts, _facts_now(facts))
		var deadline := Time.get_ticks_msec() + 1500
		while out.state == CommandTicket.State.UNSENT and Time.get_ticks_msec() < deadline:
			commands.pump(0.0)
			OS.delay_usec(1000)
		var waiting := commands.submit(target.typing_text("waiting"), facts, _facts_now(facts))
		commands.settle_machine(facts.key, why)
		_eq(
			[out.state, waiting.state, waiting.refusal],
			[CommandTicket.State.UNKNOWN, CommandTicket.State.REFUSED, why],
			"settled: the one out unknown, the queue refused"
		)
		_eq(commands.queued_events(target.pane_key), 0, "nothing kept for a reconnect")
		commands.free()
		_fakes()


## The write audit keeps raw input's category, event count and byte count:
## never a key's name, never a character, never the clipboard.
func test_raw_input_is_audited_without_its_text() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var commands := _boundary()
	var tickets: Array[CommandTicket] = [
		commands.submit(target.typing_keys(PackedStringArray(["ctrl+c", "f5", "alt+x"])), facts, _facts_now(facts)),
		commands.submit(target.typing_text(SENTINEL), facts, _facts_now(facts)),
		commands.submit(target.pasting(SENTINEL + "\n" + SENTINEL), facts, _facts_now(facts)),
		commands.submit(target.pasting(SENTINEL + "\u001b"), facts, _facts_now(facts)),
	]
	for ticket in tickets:
		_settle(commands, ticket, "each input")
	var writes := commands.write_log()
	var size := SENTINEL.length()
	_eq(
		writes.map(func(e: CommandAuditEntry) -> String: return e.category), ["keys", "text", "paste", "paste"], "kinds"
	)
	_eq(writes.map(func(e: CommandAuditEntry) -> int: return e.events), [3, size, 1, 1], "event counts")
	_eq(writes.map(func(e: CommandAuditEntry) -> int: return e.text_bytes), [-1, size, size * 2 + 1, size + 1], "bytes")
	_eq(writes.back().refusal, "PASTE_ESCAPE", "the refused paste is audited as refused")
	for entry in writes:
		var text := _entry_text(entry) + entry.summary + entry.key_name
		_check(not SENTINEL in text, "an audit entry holds typed or pasted text: " + entry.summary)
		for name: String in ["ctrl+c", "f5", "alt+x"]:
			_check(not name in text, "an audit entry names a key: " + entry.summary)
	commands.free()


## With the monitor open and nothing pressed, refreshes, status events,
## snapshot changes and five screen reads a second write nothing, ever.
func test_an_open_monitor_writes_nothing_without_a_gesture() -> void:
	_fakes()
	_ctl(
		"control-b", "set_screen", {"pane_id": "alpha:p3", "source": "visible", "ansi": "$ quiet\r\n", "animate": true}
	)
	var office := await _office_with()
	await _open_monitor(office, "alpha:p3")
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live")
	for index in 4:
		_ctl("control-b", "status", {"pane_id": "alpha:p3", "agent_status": "working" if index % 2 == 0 else "idle"})
		_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
		await _wait(0.5)
	var reads := _count("control-b", "pane.read")
	_check(reads >= 6, "it kept reading: %d reads" % reads)
	_eq(_all_inputs(), 0, "and never wrote")
	for which: String in ["control-a", "control-b"]:
		for method: String in _list(_ctl(which, "stats"), "methods"):
			_check(
				method in READ_ONLY_METHODS or method == "pane.read", "%s heard only reads, not %s" % [which, method]
			)
	_eq(office.fleet.write_log().size(), 0, "nothing in the write audit")


## `--read-only`: the monitor opens view-only, reads nothing and has no send
## path; the fakes hear nothing but the three read-only requests.
func test_the_monitor_in_read_only_sends_nothing_at_all() -> void:
	_fakes()
	var office := await _office_with(true)
	await _open_monitor(office, "alpha:p3")
	var monitor := office.hud.monitor
	_eq(monitor.mode(), TerminalMonitor.Mode.VIEW_ONLY, "view only")
	_eq(monitor.message_text(), "Read-only: herdr's screen is not read, no input", "and says so")
	var switch: Button = monitor.get_node("%SwitchButton")
	_check(not switch.is_visible_in_tree(), "no switch")
	await _type("ls")
	await _tap(KEY_ENTER)
	await _tap(KEY_ESCAPE)
	await _wait(1.5)
	var target := office.fleet.context_for(HerdrFleet.pane_key(BEE, "alpha:p3"), 1)
	var keys := office.fleet.type_keys(target.typing_keys(PackedStringArray(["enter"])))
	_eq(_refusal(keys), CommandRefusal.Reason.READ_ONLY, "no keys")
	_eq(_refusal(office.fleet.type_text(target.typing_text("x"))), CommandRefusal.Reason.READ_ONLY, "no text")
	_eq(_refusal(office.fleet.paste(target.pasting("x"))), CommandRefusal.Reason.READ_ONLY, "no paste")
	var screen := office.fleet.read_screen(target.screening(CommandContext.SOURCE_VISIBLE, 0))
	_eq(_refusal(screen), CommandRefusal.Reason.READ_ONLY, "no screen")
	_eq(office.fleet.input_refusal(target), CommandRefusal.Reason.READ_ONLY, "no input path")
	for which: String in ["control-a", "control-b"]:
		for method: String in _list(_ctl(which, "stats"), "methods"):
			_check(method in READ_ONLY_METHODS, "%s heard only the read-only three, not %s" % [which, method])
	_eq([office.fleet.write_log().size(), office.fleet.read_log().size()], [0, 0], "nothing to audit")


## The monitor is aimed at one terminal. When the pane's terminal changes,
## input stops and says so; nothing is sent until "Follow new terminal" is
## clicked and a read of the new terminal is on screen.
func test_a_new_terminal_stops_input_until_follow() -> void:
	_fakes()
	var office := await _office_with()
	await _open_monitor(office, "alpha:p3")
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live")
	await _type("a")
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "the first key went")
	var replaced := _changed(_raw(), "alpha:p3", {"terminal_id": "term-alpha-3-new"})
	_ctl("control-b", "set_snapshot", {"snapshot": replaced})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.STOPPED, "input stopped")
	_check(monitor.message_text().begins_with("New terminal"), "it says so: " + monitor.message_text())
	var follow: Button = monitor.get_node("%FollowButton")
	_check(follow.is_visible_in_tree(), "and offers to follow")
	await _type("b")
	await _wait(0.6)
	_eq(_inputs("control-b").size(), 1, "nothing typed into the new terminal")
	await _click_control(follow)
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live on the new terminal")
	_eq(monitor.target().identity_key, office.fleet.context_for(monitor.pane_key(), 1).identity_key, "aimed at it")
	await _type("c")
	await _until(func() -> bool: return _inputs("control-b").size() == 2, "the next key went")
	_eq(
		_inputs("control-b").map(func(r: Dictionary) -> Variant: return r.get("text")), ["a", "c"], "a, then c; never b"
	)


## Raw mode is bound to the terminal, not to who runs in it: the same terminal
## with another agent or session (`/clear`, or an agent started in a shell) still
## takes typing and screen reads, queued input included. A new terminal does
## not. Answer mode and the switch keep the whole identity.
func test_raw_input_follows_the_terminal_not_its_agent() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var coder := _aim(facts, "alpha:p3")
	var shell := _aim(facts, "alpha:p2")
	var cleared := {"source": "fixture", "agent": "claude", "kind": "session_id", "value": "after-clear"}
	var moved := _changed(_raw(), "alpha:p3", {"agent": "claude", "agent_session": cleared})
	moved = _changed(moved, "alpha:p2", {"agent": "claude"})
	var now := _facts(args["socket-a"], moved)
	_check(_aim(now, "alpha:p3").identity_key != coder.identity_key, "the agent and session did change")
	_check(_aim(now, "alpha:p2").identity_key != shell.identity_key, "the shell now runs an agent")
	for aimed: CommandContext in [coder, shell]:
		var raw: Array[CommandContext] = [
			aimed.typing_keys(PackedStringArray(["enter"])),
			aimed.typing_text("x"),
			aimed.pasting("x"),
			aimed.screening(CommandContext.SOURCE_VISIBLE, 0),
		]
		for context in raw:
			_eq(HerdrCommands.refusal(context, now), CommandRefusal.Reason.NONE, "same terminal: %d" % context.kind)
	_eq(HerdrCommands.refusal(coder.focusing(), now), CommandRefusal.Reason.IDENTITY_CHANGED, "the switch is stricter")
	_eq(
		HerdrCommands.refusal(coder.keying("y", null), now), CommandRefusal.Reason.IDENTITY_CHANGED, "so is answer mode"
	)
	# Queued before the change, written after it.
	var holder: Array[HerdrCommands.Machine] = [facts]
	var known := func() -> HerdrCommands.Machine: return holder[0]
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "hold", "method": "pane.send_text"})
	var first := commands.submit(coder.typing_text("a"), facts, known)
	var deadline := Time.get_ticks_msec() + 1500
	while first.state == CommandTicket.State.UNSENT and Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(1000)
	var queued := commands.submit(coder.typing_text("b"), facts, known)
	holder[0] = now
	_ctl("control-a", "release_held")
	_settle(commands, queued, "the queued input")
	_eq(queued.state, CommandTicket.State.ACCEPTED, "it went to the same terminal")
	# A new terminal stops it.
	var replaced := _facts(args["socket-a"], _changed(_raw(), "alpha:p3", {"terminal_id": "term-alpha-3-new"}))
	for context: CommandContext in [coder.typing_text("x"), coder.screening(CommandContext.SOURCE_VISIBLE, 0)]:
		_eq(HerdrCommands.refusal(context, replaced), CommandRefusal.Reason.IDENTITY_CHANGED, "a new terminal")
	_eq(_inputs("control-a").map(func(r: Dictionary) -> Variant: return r.get("text")), ["a", "b"], "a and b")
	commands.free()


## Open the monitor on bee's pane `pane_id`: pick the desk and press the card's
## "Monitor", both by real clicks.
func _open_monitor(office: OfficeDouble, pane_id: String) -> void:
	await _pick_bee(office, pane_id)
	var button: Button = office.hud.inspector.get_node("%MonitorButton")
	await _until(button.is_visible_in_tree, "the card offers the monitor")
	await _click_control(button)
	await _until(office.hud.monitor_open, "the monitor is open")


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation but the one a case provoked on purpose.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)
