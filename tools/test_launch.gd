extends "res://tools/command_test_base.gd"
## The three launch writes at the boundary: a one-line reply sent as
## `agent.prompt`, `agent.start` in a shell and `pane.split`, against two fake
## herdrs of this suite's own whose pane ids collide (Local on A, bee on B).
## Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_launch.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## The send port's cases pump a HerdrCommands outside the tree on synthetic
## time, the way tools/test_answers.gd does, and assert the exact requests and
## params each fake received; every case first resets both fakes and opens
## only the methods it needs. The last case sums up both fakes: nothing
## reached them that no case opened.

## The fake's pane ids for the cases here (tools/fixtures/snapshot_basic.json):
## a claude working, a shell, a codex idle, a pi blocked.
const FAKE := "socket:fake"


func _marker() -> String:
	return "LAUNCH TESTS"


# --- agent.prompt -----------------------------------------------------------------


## A line to an idle agent goes as `agent.prompt` with herdr's pane id as
## `target` and the text, and nothing else: no `keys` (herdr types Enter
## itself), no `wait`, no `pane_id`. Read, re-read, then the one request.
func test_a_line_goes_as_an_agent_prompt_with_target_and_text_only() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.prompt"])
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "done.\n$ \n"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	var line := "ship it: 中文 ✓ " + SENTINEL
	var bytes := line.to_utf8_buffer().size()
	var ticket := commands.submit(_aim(facts, "alpha:p3").replying(line, seen), facts, _facts_now(facts))
	_settle(commands, ticket, "the prompt")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	_eq(
		_sequence("control-a"),
		PackedStringArray(
			["pane.read recent_unwrapped 12", "pane.read recent_unwrapped 12 check", "agent.prompt %d bytes" % bytes]
		),
		"read, re-read, one prompt"
	)
	var asked := _asked("control-a", "agent.prompt")
	_eq(asked, [{"target": "alpha:p3", "text": line}], "target and text, exactly, and nothing else")
	var inputs := _inputs("control-a")
	if inputs.size() == 1:
		var input: Dictionary = inputs[0]
		_eq([input.get("method"), input.get("text"), input.get("keys")], ["agent.prompt", line, ["enter"]], "")
	else:
		_fail("one prompt expected, got %d writes" % inputs.size())
	var entry: CommandAuditEntry = commands.write_log().back()
	_eq([entry.method, entry.line_bytes], ["agent.prompt", bytes], "audited by size")
	_check(not SENTINEL in _entry_text(entry) and not "ship it" in _entry_text(entry), "never by its text")
	commands.free()


## herdr's own refusals of a prompt are typed (CommandRejection) and shown as
## herdr said them, bounded: a blocked agent the office thought idle (herdr
## writes nothing), a shell the office thought an agent, an agent still
## launching, and a message whose grapheme clusters would freeze text shaping.
func test_herdrs_prompt_errors_are_typed_and_bounded() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.prompt", "agent.start"])
	_ctl("control-a", "set_launch", {"pane_id": "alpha:p2", "outcome": "never"})
	var raw := _raw()
	var commands := _boundary()
	# (a) herdr says blocked; the office's facts still say idle.
	var idle_pi := _facts(args["socket-a"], _changed(raw, "bravo:p1", {"agent_status": "idle"}))
	var ticket := _prompted(commands, idle_pi, "bravo:p1", "yes")
	_eq([ticket.state, ticket.error_code], [CommandTicket.State.REJECTED, "agent_blocked"], "herdr refused it")
	_eq(ticket.rejection, CommandRejection.Code.AGENT_BLOCKED, "typed")
	_eq(_inputs("control-a"), [], "and wrote nothing")
	# (b) a shell the office took for an idle agent.
	var shell_as_agent := _facts(
		args["socket-a"], _changed(raw, "alpha:p2", {"agent": "codex", "agent_status": "idle"})
	)
	ticket = _prompted(commands, shell_as_agent, "alpha:p2", "hello")
	_eq([ticket.rejection, ticket.error_code], [CommandRejection.Code.AGENT_NOT_FOUND, "agent_not_found"], "no agent")
	# (c) an agent herdr is still launching (a start that never comes up).
	await _look(commands, shell_as_agent, "alpha:p2")
	var facts := _facts(args["socket-a"], raw)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var start := commands.submit(_aim(facts, "alpha:p2").starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, start, "the start")
	_eq(start.state, CommandTicket.State.ACCEPTED, "the start went")
	await _look(commands, facts, "alpha:p2")
	var launching := _facts(args["socket-a"], _changed(raw, "alpha:p2", {"agent": "claude", "agent_status": "idle"}))
	ticket = _prompted(commands, launching, "alpha:p2", "hello")
	_eq([ticket.rejection, ticket.error_code], [CommandRejection.Code.AGENT_NOT_READY, "agent_not_ready"], "starting")
	# (d) a message of a letter and 300 combining marks, then 400 letters.
	var message := "x" + char(0x0301).repeat(300) + "y".repeat(400)
	_ctl(
		"control-a", "next", {"action": "refuse", "method": "agent.prompt", "code": "agent_blocked", "message": message}
	)
	ticket = _prompted(commands, facts, "alpha:p3", "hello")
	_eq(ticket.state, CommandTicket.State.REJECTED, "refused with the long message")
	_check(_clusters_bounded(ticket.error_message), "every cluster of herdr's message is bounded")
	_eq(ticket.error_message.length(), HerdrCommands.ERROR_TEXT_MAX, "and it is cut to its length")
	_check(ticket.error_message.begins_with("xyy"), "the letter kept, its marks dropped")
	_eq(CommandRejection.of("agent_Blocked"), CommandRejection.Code.OTHER, "codes are compared exactly")
	_eq(CommandRejection.text(CommandRejection.Code.AGENT_BLOCKED), "blocked: use the keys", "a few words")
	_eq(_count("control-a", "agent.prompt"), 4, "each prompt asked once")
	_eq(_inputs("control-a"), [], "none of them written")
	commands.free()


# --- agent.start ------------------------------------------------------------------


## A start in a shell: its recent output is read again, then `agent.start`
## goes once with the name, the kind and herdr's pane id, and nothing else. The
## answer says herdr began: the start is remembered, and the next snapshot
## shows the name, still launching, with no agent yet.
func test_a_start_rereads_the_prompt_then_types_the_kind_once() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start"])
	_ctl("control-a", "set_launch", {"pane_id": "alpha:p2", "outcome": "never"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "ls\nfoo bar\n$ \n"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var context := _aim(facts, "alpha:p2").starting("claude", "claude-1", seen)
	var ticket := commands.submit(context, facts, _facts_now(facts))
	_check(commands.writing(context.pane_key), "the write slot is taken at the gesture")
	_settle(commands, ticket, "the start")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	_eq(
		_sequence("control-a"),
		PackedStringArray(
			["pane.read recent_unwrapped 12", "pane.read recent_unwrapped 12 check", "agent.start claude claude-1"]
		),
		"read, re-read, one start"
	)
	_eq(
		_asked("control-a", "agent.start"),
		[{"name": "claude-1", "kind": "claude", "pane_id": "alpha:p2"}],
		"name, kind and pane id, exactly: no args, no timeout"
	)
	_check(ticket.launch != null, "its result is read")
	if ticket.launch != null:
		_eq([ticket.launch.name, ticket.launch.launch_pending], ["claude-1", true], "herdr's name, still launching")
	var watch := commands.launch_of(context.pane_key)
	_check(watch != null and watch.name == "claude-1" and watch.kind == "claude", "the start is remembered")
	_eq(commands.launch_names(FAKE), PackedStringArray(["claude-1"]), "and its name")
	var stats := _ctl("control-a", "stats")
	_check(_dict(stats, "launches").has("alpha:p2"), "herdr is launching it")
	var record := _record_of(_dict(stats, "snapshot"), "alpha:p2")
	_eq([record.get("name"), record.get("launch_pending"), record.has("agent")], ["claude-1", true, false], "")
	var next := _pane_of(HerdrSnapshot.from_wire(_dict(stats, "snapshot")), "alpha:p2")
	_check(next != null, "the next snapshot has the pane")
	if next != null:
		_eq([next.agent, next.agent_name, next.launch_pending], ["", "claude-1", true], "a shell, named, starting")
	commands.free()


## A start goes after a last line that ends like a prompt; after one that ends
## otherwise (a half-typed line, many prompt themes) only when the viewer
## confirmed it; never when there is no whole recent output to look at. The
## refusals come at the gesture: one read, no re-read, nothing written.
func test_a_start_reads_the_last_line_as_plain_unsure_or_no_prompt() -> void:
	var plain: Array[String] = ["$ \n", "% ", "❯ ", "user@host:~ $   \n", "> ", "# ", "➜ ", "λ ", "» "]
	plain.append("ls\nfoo\n$ \n\n\n")
	for text in plain:
		_eq(HerdrCommands.prompt_state(text).kind, PromptState.Kind.PLAIN, "a prompt: " + text.c_escape())
	var unsure: Array[String] = ["$ echo PARTIAL\n", "ls\n", "$ ec", "➜  repo git:(main) ✗ ", "Press any key"]
	for text in unsure:
		_eq(HerdrCommands.prompt_state(text).kind, PromptState.Kind.UNSURE, "not sure: " + text.c_escape())
	for text: String in ["", "\n\n", "   \n  \t"]:
		_eq(HerdrCommands.prompt_state(text).kind, PromptState.Kind.NO_PROMPT, "nothing: " + text.c_escape())
	_eq(HerdrCommands.prompt_state("ls\n$ echo PARTIAL  \n\n").last_line, "$ echo PARTIAL", "the last line, trimmed")
	var sure := PromptState.of_text("$ ")
	var odd := PromptState.of_text("$ ec")
	var none := PromptState.of_text("")
	var rules: Array = [
		[sure, false, CommandRefusal.Reason.NONE],
		[odd, false, CommandRefusal.Reason.PROMPT_UNSURE],
		[odd, true, CommandRefusal.Reason.NONE],
		[none, false, CommandRefusal.Reason.NO_PROMPT],
		[none, true, CommandRefusal.Reason.NO_PROMPT],
		[null, true, CommandRefusal.Reason.NO_PROMPT],
	]
	for rule: Array in rules:
		var state: PromptState = rule[0]
		var sure_anyway: bool = rule[1]
		var what := "%s confirmed %s" % ["null" if state == null else PromptState.name_of(state.kind), sure_anyway]
		_eq(HerdrCommands.prompt_refusal(state, sure_anyway), rule[2], what)
	_fakes("snapshot_basic", ["pane.read", "agent.start"])
	_ctl("control-a", "set_launch", {"pane_id": "alpha:p2", "outcome": "never"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var target := _aim(facts, "alpha:p2")
	_eq(PromptState.of(null).kind, PromptState.Kind.NO_PROMPT, "no preview: nothing to look at")
	_ctl(
		"control-a",
		"set_preview",
		{"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n", "truncated": true}
	)
	var cut := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	_eq(PromptState.of(cut).kind, PromptState.Kind.NO_PROMPT, "a cut preview: nothing whole")
	var detection := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_DETECTION, 12)
	_eq(PromptState.of(detection).kind, PromptState.Kind.NO_PROMPT, "another source: not the recent output")
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ echo PARTIAL\n"})
	var partial := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var unconfirmed := commands.submit(target.starting("claude", "claude-1", partial), facts, _facts_now(facts))
	_eq(
		[unconfirmed.state, unconfirmed.refusal], [CommandTicket.State.REFUSED, CommandRefusal.Reason.PROMPT_UNSURE], ""
	)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "\n\n"})
	var blank := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var nothing := commands.submit(target.starting("claude", "claude-1", blank, true), facts, _facts_now(facts))
	_eq([nothing.state, nothing.refusal], [CommandTicket.State.REFUSED, CommandRefusal.Reason.NO_PROMPT], "confirmed")
	var reads := PackedStringArray(["pane.read recent_unwrapped 12", "pane.read detection 12"])
	reads.append_array(["pane.read recent_unwrapped 12", "pane.read recent_unwrapped 12"])
	_eq(_sequence("control-a"), reads, "refused at the gesture: no re-read, no start")
	_eq(_dict(_ctl("control-a", "stats"), "launches"), {}, "herdr launched nothing")
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ echo PARTIAL\n"})
	partial = _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var confirmed := commands.submit(target.starting("claude", "claude-1", partial, true), facts, _facts_now(facts))
	_settle(commands, confirmed, "the confirmed start")
	_eq(confirmed.state, CommandTicket.State.ACCEPTED, "confirmed, it goes")
	reads.append_array(["pane.read recent_unwrapped 12", "pane.read recent_unwrapped 12 check"])
	reads.append("agent.start claude claude-1")
	_eq(_sequence("control-a"), reads, "read again, then the one start")
	commands.free()


## A start goes only to a shell herdr is not launching anything in, with a
## kind this machine's snapshot shows, spelled as herdr spells names, and a
## name no agent there holds; the machine current and the same one. Each is
## refused before a socket is opened. A name herdr holds that the snapshot
## does not show is herdr's to refuse: REJECTED, shown, never sent again.
func test_a_start_goes_only_to_a_shell_with_a_seen_kind_and_a_free_name() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p1", "source": "recent_unwrapped", "text": "$ \n"})
	var raw := _raw()
	var base := _facts(args["socket-a"], raw)
	var stale := _facts(args["socket-a"], raw)
	stale.current = false
	var replaced := _facts(args["socket-a"], raw, 2)
	var starting := _facts(args["socket-a"], _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "x-1"}))
	var holding := _facts(args["socket-a"], _changed(raw, "alpha:p1", {"name": "claude-1"}))
	var commands := _boundary()
	var seen := {
		"alpha:p1": _seen(commands, base, "alpha:p1", CommandContext.SOURCE_RECENT, 12),
		"alpha:p2": _seen(commands, base, "alpha:p2", CommandContext.SOURCE_RECENT, 12),
	}
	# [pane, the facts judged against, kind, name, the reason]
	var cases: Array = [
		["alpha:p1", base, "claude", "claude-9", CommandRefusal.Reason.NOT_A_SHELL],
		["alpha:p2", starting, "claude", "claude-9", CommandRefusal.Reason.AGENT_STARTING],
		["alpha:p2", base, "gemini", "gemini-1", CommandRefusal.Reason.KIND_UNKNOWN],
		["alpha:p2", base, "Claude", "claude-9", CommandRefusal.Reason.KIND_INVALID],
		["alpha:p2", base, "claude code", "claude-9", CommandRefusal.Reason.KIND_INVALID],
		["alpha:p2", base, "c".repeat(33), "claude-9", CommandRefusal.Reason.KIND_INVALID],
		["alpha:p2", base, "claude", "Claude-1", CommandRefusal.Reason.NAME_INVALID],
		["alpha:p2", base, "claude", "", CommandRefusal.Reason.NAME_INVALID],
		["alpha:p2", base, "claude", "claude-1\n", CommandRefusal.Reason.NAME_INVALID],
		["alpha:p2", base, "claude", "c".repeat(33), CommandRefusal.Reason.NAME_INVALID],
		["alpha:p2", holding, "claude", "claude-1", CommandRefusal.Reason.NAME_TAKEN],
		["alpha:p2", stale, "claude", "claude-9", CommandRefusal.Reason.SNAPSHOT_NOT_CURRENT],
		["alpha:p2", replaced, "claude", "claude-9", CommandRefusal.Reason.MACHINE_REPLACED],
	]
	_eq(HerdrCommands.kinds_of(base.snapshot), PackedStringArray(["claude", "codex", "pi"]), "the kinds seen here")
	_eq(HerdrCommands.names_of(holding.snapshot), PackedStringArray(["claude-1"]), "the names held here")
	for case: Array in cases:
		var pane_id: String = case[0]
		var facts: HerdrCommands.Machine = case[1]
		var kind: String = case[2]
		var named: String = case[3]
		var what := "%s %s as %s" % [pane_id, kind.c_escape().left(12), named.c_escape().left(12)]
		var target := _aim(base, pane_id)
		var frozen: CommandPreview = seen[pane_id]
		_eq(HerdrCommands.refusal(target.starting(kind, named, null), facts), case[4], what)
		var ticket := commands.submit(target.starting(kind, named, frozen, true), facts, _facts_now(facts))
		_eq([ticket.state, ticket.refusal], [CommandTicket.State.REFUSED, case[4]], "at the send port: " + what)
	await _frames(3)
	_eq(_count("control-a", "agent.start"), 0, "no start reached herdr")
	# Another office got claude-1 started in another shell; this office's
	# snapshot does not show it, and this office never sent it.
	var two := _shell_beside(raw, "alpha:p2", "alpha:p4")
	_ctl("control-a", "set_snapshot", {"snapshot": two})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p4", "source": "recent_unwrapped", "text": "$ \n"})
	var facts := _facts(args["socket-a"], two)
	var another := _boundary()
	var first_seen := _seen(another, facts, "alpha:p4", CommandContext.SOURCE_RECENT, 12)
	var first_context := _aim(facts, "alpha:p4").starting("claude", "claude-1", first_seen)
	var first := another.submit(first_context, facts, _facts_now(facts))
	_settle(another, first, "the other office's start")
	_eq(first.state, CommandTicket.State.ACCEPTED, "claude-1 starts in alpha:p4")
	another.free()
	var again_seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var context := _aim(facts, "alpha:p2").starting("claude", "claude-1", again_seen)
	var ticket := commands.submit(context, facts, _facts_now(facts))
	_settle(commands, ticket, "the second start")
	_eq([ticket.state, ticket.rejection], [CommandTicket.State.REJECTED, CommandRejection.Code.AGENT_NAME_TAKEN], "")
	_check("cwd=" in ticket.error_message, "herdr's words, shown: %s" % ticket.error_message)
	_check(_clusters_bounded(ticket.error_message), "and bounded")
	await _frames(5)
	_eq(_count("control-a", "agent.start"), 2, "each start asked once: no other name tried, nothing resent")
	commands.free()


# --- pane.split -------------------------------------------------------------------


## A split goes with all three params, always: herdr's pane id as the target,
## the side the shape gives, and no focus; no cwd. herdr's answer names the new
## pane, which starts where the old one's shell is, beside it, and the shared
## focus stays where it was.
func test_a_split_carries_target_direction_and_no_focus_and_reads_the_new_pane() -> void:
	_fakes("snapshot_basic", ["pane.split"])
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var choice := HerdrCommands.split_choice(facts.snapshot, "alpha:p3")
	_eq([choice.direction, choice.reason], ["right", CommandRefusal.Reason.NONE], "80x40 splits right")
	var ticket := commands.submit(_aim(facts, "alpha:p3").splitting("right"), facts)
	_settle(commands, ticket, "the split")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr split it")
	_eq(_sequence("control-a"), PackedStringArray(["pane.split right alpha:p3"]), "one request, no read")
	_eq(
		_asked("control-a", "pane.split"),
		[{"target_pane_id": "alpha:p3", "direction": "right", "focus": false}],
		"target, direction and focus false, exactly"
	)
	_check(ticket.split != null, "the new pane is read")
	if ticket.split == null:
		commands.free()
		return
	_eq(ticket.split.pane_id, "alpha:p4", "a new pane id")
	_check(not ticket.split.terminal_id.is_empty(), "with its own terminal")
	var raw := _dict(_ctl("control-a", "stats"), "snapshot")
	var after := HerdrSnapshot.from_wire(raw)
	var old := _pane_of(after, "alpha:p3")
	var new := _pane_of(after, "alpha:p4")
	_check(new != null and old != null, "both panes are in the next snapshot")
	if new != null and old != null:
		_eq([new.terminal_id, new.cwd, new.agent], [ticket.split.terminal_id, old.foreground_cwd, ""], "a shell there")
	var sizes := {}
	for layout in after.layouts:
		for slot in layout.panes:
			sizes[slot.pane_id] = [slot.x, slot.width, slot.height]
	_eq([sizes.get("alpha:p3"), sizes.get("alpha:p4")], [[80, 40, 40], [120, 40, 40]], "the slot halved")
	_eq(after.focused_pane_id, "alpha:p1", "the shared focus did not move")
	_eq(
		PaneSplitResult.from_wire(
			{"type": "pane_info", "pane": {"pane_id": "alpha:p3", "terminal_id": "t"}}, "alpha:p3"
		),
		null,
		""
	)
	commands.free()


## The side follows the pane's shape: right when it is at least twice as wide
## as high, else down, the other when that half would be under 40 columns or
## 10 rows; neither: refused. No size: refused. At the send port too, and a
## side that is not the one the shape gives is refused as well.
func test_the_split_direction_follows_the_shape_and_small_panes_are_refused() -> void:
	var raw := _raw()
	# [width, height, direction, reason]
	var shapes: Array = [
		[160, 80, "right", CommandRefusal.Reason.NONE],
		[80, 40, "right", CommandRefusal.Reason.NONE],
		[80, 80, "down", CommandRefusal.Reason.NONE],
		[60, 40, "down", CommandRefusal.Reason.NONE],
		[80, 19, "right", CommandRefusal.Reason.NONE],
		[79, 30, "down", CommandRefusal.Reason.NONE],
		[79, 19, "", CommandRefusal.Reason.PANE_TOO_SMALL],
		[30, 10, "", CommandRefusal.Reason.PANE_TOO_SMALL],
		[0, 0, "", CommandRefusal.Reason.SIZE_UNKNOWN],
		[-1, -1, "", CommandRefusal.Reason.SIZE_UNKNOWN],
	]
	for shape: Array in shapes:
		var width: int = shape[0]
		var height: int = shape[1]
		var sized := HerdrSnapshot.from_wire(_sized(raw, "alpha:p3", width, height))
		var choice := HerdrCommands.split_choice(sized, "alpha:p3")
		_eq([choice.direction, choice.reason], [shape[2], shape[3]], "%sx%s" % [shape[0], shape[1]])
	_fakes("snapshot_basic", ["pane.split"])
	var commands := _boundary()
	var small := _facts(args["socket-a"], _sized(raw, "alpha:p3", 30, 10))
	var ticket := commands.submit(_aim(small, "alpha:p3").splitting("right"), small)
	_eq([ticket.state, ticket.refusal], [CommandTicket.State.REFUSED, CommandRefusal.Reason.PANE_TOO_SMALL], "small")
	var facts := _facts(args["socket-a"], raw)
	ticket = commands.submit(_aim(facts, "alpha:p3").splitting("left"), facts)
	_eq(ticket.refusal, CommandRefusal.Reason.DIRECTION_INVALID, "left is no side herdr splits to")
	ticket = commands.submit(_aim(facts, "alpha:p3").splitting("down"), facts)
	_eq(ticket.refusal, CommandRefusal.Reason.DIRECTION_INVALID, "down, when the shape gives right")
	await _frames(3)
	_eq(_count("control-a", "pane.split"), 0, "no split reached herdr")
	commands.free()


# --- the launch, as snapshots show it -----------------------------------------------


## How a start is going is read from the snapshot's pane, never from its
## ticket: launching, ready, asking at once, not detected in time, another
## terminal or agent there, or the pane gone; and a shell that reads idle is
## not an agent that came up.
func test_launch_judgement_reads_the_snapshot_not_the_ticket() -> void:
	var watch := LaunchWatch.new()
	watch.name = "claude-1"
	watch.kind = "claude"
	watch.terminal_id = "term-alpha-2"
	watch.started_msec = 1000
	# [agent, name, launch_pending, interactive_ready, status, terminal, now, outcome]
	var cases: Array = [
		["", "claude-1", true, false, "unknown", "term-alpha-2", 5000, LaunchWatch.Outcome.PENDING],
		["claude", "claude-1", true, false, "unknown", "term-alpha-2", 5000, LaunchWatch.Outcome.PENDING],
		["claude", "claude-1", false, true, "idle", "term-alpha-2", 5000, LaunchWatch.Outcome.READY],
		["claude", "", false, false, "idle", "term-alpha-2", 5000, LaunchWatch.Outcome.READY],
		["", "", false, false, "idle", "term-alpha-2", 5000, LaunchWatch.Outcome.PENDING],
		["claude", "claude-1", true, false, "blocked", "term-alpha-2", 5000, LaunchWatch.Outcome.BLOCKED_AT_START],
		["claude", "claude-1", true, false, "unknown", "term-alpha-2", 32000, LaunchWatch.Outcome.NOT_DETECTED],
		["", "", false, false, "idle", "term-alpha-2", 32000, LaunchWatch.Outcome.NOT_DETECTED],
		["", "other", true, false, "unknown", "term-alpha-2", 5000, LaunchWatch.Outcome.REPLACED],
		["codex", "", false, false, "idle", "term-alpha-2", 5000, LaunchWatch.Outcome.REPLACED],
		["claude", "claude-1", false, true, "idle", "term-new", 5000, LaunchWatch.Outcome.REPLACED],
	]
	for case: Array in cases:
		var pane := HerdrSnapshot.Pane.new()
		pane.agent = case[0]
		pane.agent_name = case[1]
		pane.launch_pending = case[2]
		pane.interactive_ready = case[3]
		pane.agent_status = case[4]
		pane.terminal_id = case[5]
		var now: int = case[6]
		var expected: LaunchWatch.Outcome = case[7]
		var judged := LaunchWatch.judge(watch, pane, now, LaunchWatch.TIMEOUT_MSEC)
		_eq(LaunchWatch.name_of(judged), LaunchWatch.name_of(expected), "%s" % [case])
	_eq(LaunchWatch.judge(watch, null, 5000), LaunchWatch.Outcome.GONE, "no pane: gone")
	# The deadline's launch check, once it is back, says how a pending launch stands.
	var pending := HerdrSnapshot.Pane.new()
	pending.agent_name = "claude-1"
	pending.launch_pending = true
	pending.terminal_id = "term-alpha-2"
	var answers: Array = [
		[_checked(CommandTicket.State.REJECTED, "agent_not_found", false), LaunchWatch.Outcome.FAILED],
		[_checked(CommandTicket.State.ACCEPTED, "", true), LaunchWatch.Outcome.NOT_DETECTED],
		[_checked(CommandTicket.State.UNKNOWN, "", false), LaunchWatch.Outcome.UNKNOWN],
		[_checked(CommandTicket.State.REJECTED, "invalid_request", false), LaunchWatch.Outcome.UNKNOWN],
		[_checked(CommandTicket.State.UNSENT, "", false), LaunchWatch.Outcome.PENDING],
		[_checked(CommandTicket.State.REFUSED, "", false), LaunchWatch.Outcome.NOT_CHECKED],
	]
	for answer: Array in answers:
		watch.check = answer[0]
		var expected: LaunchWatch.Outcome = answer[1]
		var judged := LaunchWatch.judge(watch, pending, 5000)
		_eq(
			LaunchWatch.name_of(judged),
			LaunchWatch.name_of(expected),
			"the check says " + LaunchWatch.name_of(expected)
		)
	# Given up by herdr, then an agent of the same kind started by hand in that
	# shell: still the failed start, never "started".
	var by_hand := HerdrSnapshot.Pane.new()
	by_hand.agent = "claude"
	by_hand.agent_status = "idle"
	by_hand.terminal_id = "term-alpha-2"
	watch.check = _checked(CommandTicket.State.REJECTED, "agent_not_found", false)
	_eq(LaunchWatch.name_of(LaunchWatch.judge(watch, by_hand, 40000)), "FAILED", "a failed start stays failed")
	watch.check = null
	var lines := {
		LaunchWatch.Outcome.PENDING: "Starting claude-1 · 4s",
		LaunchWatch.Outcome.READY: "claude-1 started",
		LaunchWatch.Outcome.BLOCKED_AT_START: "claude-1 asks: answer with the keys",
		LaunchWatch.Outcome.NOT_DETECTED: "claude-1 not detected after 31s: look at the terminal",
		LaunchWatch.Outcome.FAILED: "claude-1 did not start: look at the terminal",
		LaunchWatch.Outcome.UNKNOWN: "claude-1: no answer from herdr",
		LaunchWatch.Outcome.NOT_CHECKED: "claude-1 not checked: the connection changed",
		LaunchWatch.Outcome.REPLACED: "Terminal changed",
		LaunchWatch.Outcome.GONE: "Pane gone",
	}
	for judged: LaunchWatch.Outcome in lines:
		_eq(LaunchWatch.text(judged, watch, 5000), lines[judged], LaunchWatch.name_of(judged))
		_check(not LaunchWatch.detail(judged).is_empty(), "a sentence for " + LaunchWatch.name_of(judged))


# --- all three ---------------------------------------------------------------------


## The audit of a prompt, a start and a split keeps the office's own words
## (the kind, the name it made, the side) and byte counts, and never any
## terminal text or the line.
func test_start_split_and_prompt_are_audited_without_terminal_text() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.prompt", "agent.start", "pane.split"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	var shown := "seen " + SENTINEL + "\n$ \n"
	for pane_id: String in ["alpha:p2", "alpha:p3"]:
		_ctl("control-a", "set_preview", {"pane_id": pane_id, "source": "recent_unwrapped", "text": shown})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var line := "the line " + SENTINEL
	var prompt := _prompted(commands, facts, "alpha:p3", line)
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var start := commands.submit(_aim(facts, "alpha:p2").starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, start, "the start")
	var split := commands.submit(_aim(facts, "alpha:p1").splitting("right"), facts)
	_settle(commands, split, "the split")
	var states := [prompt.state, start.state, split.state]
	_eq(states, [CommandTicket.State.ACCEPTED, CommandTicket.State.ACCEPTED, CommandTicket.State.ACCEPTED], "")
	var writes := commands.write_log()
	_eq(writes.size(), 3, "three writes audited")
	for entry in writes:
		var text := _entry_text(entry)
		_check(not SENTINEL in text and not "seen " in text and not "the line" in text, "no text: " + entry.summary)
	for entry in commands.read_log():
		_check(not SENTINEL in _entry_text(entry), "no terminal text in a read either")
	if writes.size() == 3:
		var line_bytes := line.to_utf8_buffer().size()
		_eq([writes[0].method, writes[0].line_bytes], ["agent.prompt", line_bytes], "the prompt, by size")
		_eq([writes[1].method, writes[1].agent_kind, writes[1].agent_name], ["agent.start", "claude", "claude-1"], "")
		_eq(writes[1].summary, "agent.start alpha:p2 claude as claude-1", "the start in the office's words")
		_eq(
			[writes[2].method, writes[2].direction, writes[2].summary],
			["pane.split", "right", "pane.split alpha:p1 right"],
			""
		)
	commands.free()


## A prompt, a start or a split whose answer is lost after herdr carried it
## out is UNKNOWN and never sent again; a lost start is remembered all the
## same, so its name is not handed out twice.
func test_lost_answers_to_start_split_and_prompt_are_unknown_and_never_resent() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.prompt", "agent.start", "pane.split"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	for pane_id: String in ["alpha:p2", "alpha:p3"]:
		_ctl("control-a", "set_preview", {"pane_id": pane_id, "source": "recent_unwrapped", "text": "$ \n"})
	for method: String in ["agent.prompt", "agent.start", "pane.split"]:
		_ctl("control-a", "next", {"action": "execute_then_drop", "method": method})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var prompt := _prompted(commands, facts, "alpha:p3", "hello", 0.05)
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var context := _aim(facts, "alpha:p2").starting("claude", "claude-1", seen)
	var start := commands.submit(context, facts, _facts_now(facts))
	_settle(commands, start, "the start", 0.05)
	var split := commands.submit(_aim(facts, "alpha:p1").splitting("right"), facts)
	_settle(commands, split, "the split", 0.05)
	var unknown := CommandTicket.State.UNKNOWN
	_eq([prompt.state, start.state, split.state], [unknown, unknown, unknown], "all three unknown")
	await _frames(5)
	var stats := _ctl("control-a", "stats")
	_eq([_inputs("control-a").size(), _dict(stats, "launches").size(), _list(stats, "splits").size()], [1, 1, 1], "")
	for method: String in ["agent.prompt", "agent.start", "pane.split"]:
		_eq(_count("control-a", method), 1, method + " asked once, never again")
	var watch := commands.launch_of(context.pane_key)
	_check(watch != null and watch.ticket == start, "the lost start is remembered")
	_eq(commands.launch_names(FAKE), PackedStringArray(["claude-1"]), "its name with it")
	commands.free()


## A start or a split is a write to its pane: the next write there waits for a
## look. The new pane a split made was never written to, and owes none.
func test_a_pane_written_by_start_or_split_waits_for_a_look() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "pane.split"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var facts := _facts(args["socket-a"], _raw())
	var commands := _boundary()
	var shell := _aim(facts, "alpha:p2")
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var start := commands.submit(shell.starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, start, "the start")
	_eq(start.state, CommandTicket.State.ACCEPTED, "the start went")
	_check(commands.must_look(shell.pane_key), "the shell owes a look")
	_eq(commands.blocker(shell.focusing()), CommandRefusal.Reason.LOOK_FIRST, "any write to it waits")
	_eq(commands.blocker(shell.splitting("right")), CommandRefusal.Reason.LOOK_FIRST, "a split too")
	await _look(commands, facts, "alpha:p2")
	_eq(commands.blocker(shell.focusing()), CommandRefusal.Reason.NONE, "a look later, it is free")
	var agent := _aim(facts, "alpha:p3")
	var split := commands.submit(agent.splitting("right"), facts)
	_settle(commands, split, "the split")
	_eq(split.state, CommandTicket.State.ACCEPTED, "the split went")
	_check(commands.must_look(agent.pane_key), "the pane split owes a look")
	_check(not commands.must_look(HerdrFleet.pane_key(FAKE, "alpha:p4")), "the new pane owes none")
	commands.free()


## herdr's agent record gives a pane its agent's name and readiness, both only
## while the record describes that agent; the name is remote text, bounded;
## and a change of readiness alone is a new snapshot.
func test_snapshot_reads_name_and_interactive_ready_and_signs_them() -> void:
	var raw := _raw()
	var ready := _with_record(raw, "alpha:p1", {"name": "claude-1", "interactive_ready": true})
	var pane := _pane_of(HerdrSnapshot.from_wire(ready), "alpha:p1")
	_eq([pane.agent_name, pane.interactive_ready], ["claude-1", true], "the name and readiness")
	var long_name := "c" + char(0x0301).repeat(300)
	pane = _pane_of(HerdrSnapshot.from_wire(_with_record(raw, "alpha:p1", {"name": long_name})), "alpha:p1")
	_check(_clusters_bounded(pane.agent_name), "a name's clusters are bounded")
	_eq(pane.agent_name, "c", "to its base")
	var other := _with_record(ready, "alpha:p1", {"agent": "codex"})
	pane = _pane_of(HerdrSnapshot.from_wire(other), "alpha:p1")
	_eq([pane.agent, pane.agent_name, pane.interactive_ready], ["claude", "", false], "a record of another agent")
	var odd := _with_record(raw, "alpha:p1", {"interactive_ready": "yes"})
	_eq(_pane_of(HerdrSnapshot.from_wire(odd), "alpha:p1").interactive_ready, false, "only a JSON boolean")
	var not_ready := _with_record(ready, "alpha:p1", {"interactive_ready": false})
	var one := HerdrSnapshot.from_wire(ready).signature()
	_check(one != HerdrSnapshot.from_wire(not_ready).signature(), "readiness alone changes the signature")
	var renamed := _with_record(ready, "alpha:p1", {"name": "claude-2"})
	_check(one != HerdrSnapshot.from_wire(renamed).signature(), "and so does the name")
	var shown := HerdrSnapshot.from_wire(ready)
	pane = _pane_of(shown, "alpha:p1")
	_check(pane.apply_status({"agent": "codex", "agent_status": "idle"}), "an event naming another agent changes it")
	_eq([pane.agent_name, pane.interactive_ready], ["", false], "and the record no longer describes it")


## An agent that asks a question while herdr still launches it (a trust
## prompt) takes the answer keys; a line still waits for it to come up.
func test_keys_reach_a_blocked_agent_still_launching() -> void:
	_fakes("snapshot_basic", ["pane.read", "pane.send_keys"])
	_ctl("control-a", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var facts := _facts(args["socket-a"], _changed(_raw(), "bravo:p1", {"launch_pending": true}))
	_check(facts.snapshot.panes[3].launch_pending, "the fact: blocked and still launching")
	var target := _aim(facts, "bravo:p1")
	_eq(HerdrCommands.refusal(target.keying("y", null), facts), CommandRefusal.Reason.NONE, "keys may go")
	_eq(HerdrCommands.refusal(target.replying("x", null), facts), CommandRefusal.Reason.AGENT_STARTING, "a line not")
	var commands := _boundary()
	var seen := _seen(commands, facts, "bravo:p1", CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX)
	var ticket := commands.submit(target.keying("y", seen), facts, _facts_now(facts))
	_settle(commands, ticket, "the key")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	_eq(
		_sequence("control-a"),
		PackedStringArray(["pane.read detection 200", "pane.read detection 200 check", 'pane.send_keys ["y"]']),
		"read, re-read, the key once"
	)
	commands.free()


## The fleet's calls for the card: the kinds a start may name, the next free
## name (past this run's own starts), whether a start or a split would go, the
## side, and how a start is going as snapshots show it, on the boundary's own
## clock. herdr sends no event for a start that nothing recognises (measured):
## the fleet fetches a snapshot at once after herdr took it, and the launch
## shows there. At the deadline the boundary asks herdr once how it stands.
func test_the_fleet_names_kinds_and_judges_starts() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "agent.get"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var office := await _office_with()
	var fleet := office.fleet
	var now := [7000000]
	fleet.use_command_clock(func() -> int: return now[0])
	var local := HerdrFleet.LOCAL
	var shell := HerdrFleet.pane_key(local, "alpha:p2")
	_eq(fleet.agent_kinds(local), PackedStringArray(["claude", "codex", "pi"]), "the kinds Local shows")
	_eq(fleet.next_agent_name(local, "claude"), "claude-1", "the first free name")
	_eq(fleet.next_agent_name(local, ""), "", "no kind, no name")
	_eq(fleet.can_start(shell, "claude"), CommandRefusal.Reason.NONE, "a start may go to the shell")
	_eq(fleet.can_start(HerdrFleet.pane_key(local, "alpha:p1"), "claude"), CommandRefusal.Reason.NOT_A_SHELL, "")
	_eq(fleet.can_start(shell, "gemini"), CommandRefusal.Reason.KIND_UNKNOWN, "not a kind seen here")
	var agent := HerdrFleet.pane_key(local, "alpha:p3")
	_eq([fleet.split_direction(agent), fleet.can_split(agent)], ["right", CommandRefusal.Reason.NONE], "a split")
	_eq(fleet.launch_outcome(shell), LaunchWatch.Outcome.GONE, "no start yet")
	var read := fleet.read_pane(fleet.context_for(shell, 1).reading(CommandContext.SOURCE_RECENT, 12))
	await _until(read.is_finished, "the read")
	var seen := CommandPreview.of(read, 1)
	_eq(HerdrFleet.prompt_state(seen).kind, PromptState.Kind.PLAIN, "the preview ends at a prompt")
	var named := fleet.next_agent_name(local, "claude")
	var start := fleet.start_agent(fleet.context_for(shell, 1).starting("claude", named, seen))
	await _until(start.is_finished, "the start")
	_eq(start.state, CommandTicket.State.ACCEPTED, "it went")
	_eq(fleet.next_agent_name(local, "claude"), "claude-2", "its name is not handed out again")
	_eq(fleet.can_start(shell, "claude"), CommandRefusal.Reason.LOOK_FIRST, "no second start there: a look first")
	_eq(fleet.launch_outcome(shell), LaunchWatch.Outcome.PENDING, "launching, as far as anything shows")
	await _until(func() -> bool: return fleet.snapshot(local).panes[1].launch_pending, "the snapshot shows it")
	# At the fake, on its own clock: the snapshot after the start came sooner
	# than the client's poll could have, which waits SNAPSHOT_INTERVAL after
	# the snapshot before it (and nothing else sent an event to fetch one).
	var gaps := _snapshot_gaps(_ctl("control-a", "stats"), "agent.start")
	_check(gaps.x >= 0.0 and gaps.x < 1.0, "a snapshot %.2f s after the start" % gaps.x)
	_check(
		gaps.y < HerdrClient.SNAPSHOT_INTERVAL - 1.0,
		"and %.2f s after the one before it: not the poll, which waits %.0f s" % [gaps.y, HerdrClient.SNAPSHOT_INTERVAL]
	)
	_eq(fleet.launch_outcome(shell), LaunchWatch.Outcome.PENDING, "launching")
	_eq(fleet.can_start(shell, "claude"), CommandRefusal.Reason.AGENT_STARTING, "no second start there")
	now[0] += LaunchWatch.TIMEOUT_MSEC - 1
	_eq(fleet.launch_outcome(shell), LaunchWatch.Outcome.PENDING, "just short of the timeout, on the boundary's clock")
	await _frames(5)
	_eq(_count("control-a", "agent.get"), 0, "no launch check before the deadline")
	now[0] += 1
	_eq(fleet.launch_outcome(shell), LaunchWatch.Outcome.NOT_DETECTED, "past the deadline: not detected")
	await _until(func() -> bool: return _count("control-a", "agent.get") == 1, "one launch check")
	_eq(_asked("control-a", "agent.get"), [{"target": "alpha:p2"}], "by herdr's pane id")
	var watch := fleet.launch_of(shell)
	await _until(func() -> bool: return watch.check != null and watch.check.is_finished(), "its answer")
	_eq(fleet.launch_outcome(shell), LaunchWatch.Outcome.NOT_DETECTED, "herdr still launches it: not detected")
	await _frames(10)
	_eq(_count("control-a", "agent.get"), 1, "and never asked again")
	_eq(_count("control-a", "agent.start"), 1, "one start, never again")
	_eq(
		_writes_seen("control-a"),
		PackedStringArray(["pane.read recent_unwrapped 12 check", "agent.start claude claude-1", "agent.get alpha:p2"]),
		""
	)


## herdr answers a start before any snapshot shows it (measured against herdr
## 0.9.0, docs/WRITE_BOUNDARY.md §6): for one snapshot interval after a start
## the office refuses another there, whatever the snapshot it has still says,
## so the card never offers it; once the snapshot shows the launch, that
## refuses it. A name this run already sent is not sent again either,
## elsewhere or later.
func test_a_second_start_in_the_snapshot_lag_is_refused() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	var raw := _shell_beside(_raw(), "alpha:p2", "alpha:p4")
	_ctl("control-a", "set_snapshot", {"snapshot": raw})
	for pane_id: String in ["alpha:p2", "alpha:p4"]:
		_ctl("control-a", "set_preview", {"pane_id": pane_id, "source": "recent_unwrapped", "text": "$ \n"})
	_eq(HerdrCommands.LAUNCH_GRACE_MSEC, int(HerdrClient.SNAPSHOT_INTERVAL * 1000), "the grace: one snapshot interval")
	# What the office knows during the lag: the snapshot from before the start.
	var facts := _facts(args["socket-a"], raw)
	var commands := _boundary()
	var now := [1000000]
	commands.clock = func() -> int: return now[0]
	var shell := _aim(facts, "alpha:p2")
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var first := commands.submit(shell.starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, first, "the first start")
	_eq(first.state, CommandTicket.State.ACCEPTED, "the first start went")
	now[0] += HerdrCommands.LOOK_DELAY_MSEC + 100
	await _look(commands, facts, "alpha:p2")
	var again := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var second := shell.starting("claude", "claude-2", again)
	_eq(HerdrCommands.refusal(second, facts), CommandRefusal.Reason.NONE, "the lagging snapshot still shows a shell")
	_eq(commands.blocker(second), CommandRefusal.Reason.AGENT_STARTING, "but a start went there just now")
	var refused := commands.submit(second, facts, _facts_now(facts))
	_eq([refused.state, refused.refusal], [CommandTicket.State.REFUSED, CommandRefusal.Reason.AGENT_STARTING], "")
	var elsewhere_seen := _seen(commands, facts, "alpha:p4", CommandContext.SOURCE_RECENT, 12)
	var elsewhere := _aim(facts, "alpha:p4").starting("claude", "claude-1", elsewhere_seen)
	_eq(commands.blocker(elsewhere), CommandRefusal.Reason.NAME_TAKEN, "claude-1 went out this run")
	refused = commands.submit(elsewhere, facts, _facts_now(facts))
	_eq(refused.refusal, CommandRefusal.Reason.NAME_TAKEN, "refused at the send port too")
	now[0] += HerdrCommands.LAUNCH_GRACE_MSEC
	_eq(commands.blocker(second), CommandRefusal.Reason.NONE, "a snapshot interval on, the grace is over")
	_eq(commands.blocker(elsewhere), CommandRefusal.Reason.NAME_TAKEN, "the name stays taken")
	var shown := _facts(args["socket-a"], _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "claude-1"}))
	var launching := _aim(shown, "alpha:p2").starting("claude", "claude-2", again)
	_eq(HerdrCommands.refusal(launching, shown), CommandRefusal.Reason.AGENT_STARTING, "the snapshot shows the launch")
	refused = commands.submit(launching, shown, _facts_now(shown))
	_eq(refused.refusal, CommandRefusal.Reason.AGENT_STARTING, "and refuses it")
	await _frames(3)
	_eq(_count("control-a", "agent.start"), 1, "none of those reached herdr")
	commands.free()


## A start's deadline comes just after herdr's own launch timeout, which herdr
## settles only when asked (docs/WRITE_BOUNDARY.md §6): at the deadline, with the
## snapshot still showing the launch pending, the boundary asks ONE agent.get
## by herdr's pane id. herdr gives the launch up (agent_not_found): the start
## FAILED, the pane is a shell again and a start may go there once more. The
## ask is a read: no write, and never a second one.
func test_the_deadline_asks_once_and_a_given_up_start_fails() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "agent.get"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	_ctl("control-a", "set_launch_timeout", {"seconds": 0})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var raw := _raw()
	var facts := _facts(args["socket-a"], raw)
	var launching := _facts(
		args["socket-a"], _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "claude-1"})
	)
	var commands := _boundary()
	var now := [2000000]
	commands.clock = func() -> int: return now[0]
	commands.machine_facts = func(_machine_key: String) -> HerdrCommands.Machine: return launching
	var shell := _aim(facts, "alpha:p2")
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var start := commands.submit(shell.starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, start, "the start")
	_eq(start.state, CommandTicket.State.ACCEPTED, "the start went")
	now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC - 1
	commands.pump(0.0)
	_eq(_count("control-a", "agent.get"), 0, "nothing asked before the deadline")
	now[0] += 1
	commands.pump(0.0)
	var watch := commands.launch_of(shell.pane_key)
	_check(watch.check != null, "at the deadline, one launch check")
	if watch.check == null:
		commands.free()
		return
	_settle(commands, watch.check, "the launch check")
	for index in 5:
		now[0] += 1000
		commands.pump(0.0)
	await _frames(3)
	_eq(_asked("control-a", "agent.get"), [{"target": "alpha:p2"}], "one agent.get, by herdr's pane id")
	_eq(
		[watch.check.state, watch.check.rejection],
		[CommandTicket.State.REJECTED, CommandRejection.Code.AGENT_NOT_FOUND],
		""
	)
	var stats := _ctl("control-a", "stats")
	_eq([_dict(stats, "names"), _dict(stats, "launches")], [{}, {}], "herdr gave it up: name and pane free")
	var settled := _facts(args["socket-a"], _dict(stats, "snapshot"))
	var pane := _pane_of(settled.snapshot, "alpha:p2")
	_eq([pane.launch_pending, pane.agent_name], [false, ""], "the record is gone: a shell again")
	var outcome := LaunchWatch.judge(watch, pane, commands.now_msec())
	_eq(LaunchWatch.name_of(outcome), "FAILED", "the start failed")
	_eq(
		LaunchWatch.name_of(LaunchWatch.judge(watch, _pane_of(launching.snapshot, "alpha:p2"), commands.now_msec())),
		"FAILED",
		"even on a stale snapshot"
	)
	await _look(commands, settled, "alpha:p2")
	var again := _aim(settled, "alpha:p2").starting("claude", "claude-2", null)
	_eq(
		[HerdrCommands.refusal(again, settled), commands.blocker(again)],
		[CommandRefusal.Reason.NONE, CommandRefusal.Reason.NONE],
		"a start may go there again"
	)
	_eq(commands.write_log().size(), 1, "the check wrote nothing: one write, the start")
	var read_methods := commands.read_log().map(func(entry: CommandAuditEntry) -> String: return entry.method)
	_eq(read_methods.count("agent.get"), 1, "it is audited once, as a read")
	_eq(_count("control-a", "agent.start"), 1, "and nothing was started again")
	commands.free()


## A launch herdr still has (its own timeout not run out) answers agent_info:
## the start is NOT_DETECTED, and nobody asks again; a check with no usable
## answer is UNKNOWN, never asked again either. One ask per start.
func test_a_launch_still_pending_or_unanswered_is_asked_once() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "agent.get"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	var raw := _shell_beside(_raw(), "alpha:p2", "alpha:p4")
	_ctl("control-a", "set_snapshot", {"snapshot": raw})
	for pane_id: String in ["alpha:p2", "alpha:p4"]:
		_ctl("control-a", "set_preview", {"pane_id": pane_id, "source": "recent_unwrapped", "text": "$ \n"})
	var facts := _facts(args["socket-a"], raw)
	var shown := _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "claude-1"})
	shown = _with_record(shown, "alpha:p4", {"launch_pending": true, "name": "claude-2"})
	var launching := _facts(args["socket-a"], shown)
	var commands := _boundary()
	var now := [3000000]
	commands.clock = func() -> int: return now[0]
	commands.machine_facts = func(_machine_key: String) -> HerdrCommands.Machine: return launching
	var names: Dictionary[String, String] = {"alpha:p2": "claude-1", "alpha:p4": "claude-2"}
	for pane_id: String in names:
		var seen := _seen(commands, facts, pane_id, CommandContext.SOURCE_RECENT, 12)
		var start := commands.submit(
			_aim(facts, pane_id).starting("claude", names[pane_id], seen), facts, _facts_now(facts)
		)
		_settle(commands, start, "the start in " + pane_id)
	_ctl("control-a", "next", {"action": "drop", "method": "agent.get", "id_suffix": ""})
	now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC
	commands.pump(0.0)
	var outcomes := {}
	for pane_id: String in names:
		var watch := commands.launch_of(HerdrFleet.pane_key(FAKE, pane_id))
		_check(watch.check != null, "one check for " + pane_id)
		if watch.check != null:
			_settle(commands, watch.check, "the check of " + pane_id, 0.05)
			outcomes[pane_id] = LaunchWatch.name_of(
				LaunchWatch.judge(watch, _pane_of(launching.snapshot, pane_id), commands.now_msec())
			)
	for index in 5:
		now[0] += 1000
		commands.pump(0.0)
	await _frames(3)
	var got := _asked("control-a", "agent.get")
	_eq(got.size(), 2, "one agent.get per start")
	_eq(outcomes.values().count("NOT_DETECTED") + outcomes.values().count("UNKNOWN"), 2, "")
	_check("NOT_DETECTED" in outcomes.values(), "herdr still launching one: not detected")
	_check("UNKNOWN" in outcomes.values(), "no answer for the other: unknown")
	_eq(_dict(_ctl("control-a", "stats"), "launches").size(), 2, "herdr still holds both")
	_eq(commands.write_log().size(), 2, "no write beside the two starts")
	commands.free()


## A launch check goes only for a start this office sent that the snapshot
## still shows pending at the deadline: none for another client's launch,
## none once the agent came up, none with no facts to judge by.
func test_no_launch_check_without_a_pending_start_of_ours() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "agent.get"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var raw := _raw()
	var facts := _facts(args["socket-a"], raw)
	# Someone else's launch in alpha:p2, and nothing of ours.
	var theirs := _facts(args["socket-a"], _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "x-1"}))
	var commands := _boundary()
	var now := [4000000]
	commands.clock = func() -> int: return now[0]
	var shown_now := [theirs]
	commands.machine_facts = func(_machine_key: String) -> HerdrCommands.Machine:
		var held: HerdrCommands.Machine = shown_now[0]
		return held
	now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC * 3
	commands.pump(0.0)
	_eq(_count("control-a", "agent.get"), 0, "another client's launch is never asked about")
	# Ours, which came up before the deadline.
	shown_now[0] = facts
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var start := commands.submit(_aim(facts, "alpha:p2").starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, start, "our start")
	shown_now[0] = _facts(
		args["socket-a"],
		_changed(
			_with_record(raw, "alpha:p2", {"name": "claude-1", "interactive_ready": true}),
			"alpha:p2",
			{"agent": "claude", "agent_status": "idle"}
		)
	)
	now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC
	commands.pump(0.0)
	var watch := commands.launch_of(HerdrFleet.pane_key(FAKE, "alpha:p2"))
	_check(watch.decided and watch.check == null, "decided at the deadline, with nothing to ask")
	var came_up: HerdrCommands.Machine = shown_now[0]
	_eq(
		LaunchWatch.name_of(LaunchWatch.judge(watch, _pane_of(came_up.snapshot, "alpha:p2"), commands.now_msec())),
		"READY",
		""
	)
	# A boundary with no facts to ask never checks.
	var alone := _boundary()
	alone.clock = func() -> int: return now[0]
	var alone_seen := _seen(alone, facts, "alpha:p3", CommandContext.SOURCE_RECENT, 12)
	_check(alone_seen != null, "a read works without facts")
	now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC * 2
	alone.pump(0.0)
	commands.pump(0.0)
	await _frames(3)
	_eq(_count("control-a", "agent.get"), 0, "no agent.get at all")
	commands.free()
	alone.free()


## A launch check asks only about the very launch this office started, on the
## connection it started it on: a machine replaced (another generation) or
## gone before the deadline is not asked about at all, and the start reads
## NOT_CHECKED (not "no answer from herdr": nobody asked); a pane whose terminal
## changed is not asked about either. Nothing keeps the boundary pumping for them.
func test_a_launch_on_a_replaced_or_gone_machine_or_new_terminal_is_not_asked() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "agent.get"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	var raw := _shell_beside(_shell_beside(_raw(), "alpha:p2", "alpha:p4"), "alpha:p2", "alpha:p5")
	_ctl("control-a", "set_snapshot", {"snapshot": raw})
	for pane_id: String in ["alpha:p2", "alpha:p4", "alpha:p5"]:
		_ctl("control-a", "set_preview", {"pane_id": pane_id, "source": "recent_unwrapped", "text": "$ \n"})
	var facts := _facts(args["socket-a"], raw)
	var pending := _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "claude-1"})
	pending = _with_record(pending, "alpha:p4", {"launch_pending": true, "name": "claude-2"})
	var new_terminal := _changed(pending, "alpha:p5", {"terminal_id": "term-new"})
	new_terminal = _with_record(new_terminal, "alpha:p5", {"launch_pending": true, "name": "claude-3"})
	var replaced := _facts(args["socket-a"], pending, 2)
	var moved := _facts(args["socket-a"], new_terminal)
	var now := [5000000]
	# [pane, name, what the fleet answers at the deadline (null: the machine is gone), outcome]
	var cases: Array = [
		["alpha:p2", "claude-1", replaced, "NOT_CHECKED"],
		["alpha:p4", "claude-2", null, "NOT_CHECKED"],
		["alpha:p5", "claude-3", moved, "REPLACED"],
	]
	for case: Array in cases:
		var pane_id: String = case[0]
		var named: String = case[1]
		var answer: HerdrCommands.Machine = case[2]
		var commands := _boundary()
		commands.clock = func() -> int: return now[0]
		commands.machine_facts = func(_machine_key: String) -> HerdrCommands.Machine: return answer
		var seen := _seen(commands, facts, pane_id, CommandContext.SOURCE_RECENT, 12)
		var start := commands.submit(_aim(facts, pane_id).starting("claude", named, seen), facts, _facts_now(facts))
		_settle(commands, start, "the start in " + pane_id)
		_eq(start.state, CommandTicket.State.ACCEPTED, "the start in %s went" % pane_id)
		_check(commands.is_processing(), "%s: pumped until its deadline" % pane_id)
		now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC
		commands.pump(0.0)
		var watch := commands.launch_of(HerdrFleet.pane_key(FAKE, pane_id))
		_check(watch.decided and watch.check == null, "%s: decided at the deadline, nothing asked" % pane_id)
		_check(not commands.is_processing(), "%s: and nothing keeps the boundary busy" % pane_id)
		var shown := facts if answer == null else answer
		var outcome := LaunchWatch.judge(watch, _pane_of(shown.snapshot, pane_id), commands.now_msec())
		_eq(LaunchWatch.name_of(outcome), case[3], "%s: the outcome" % pane_id)
		commands.free()
	await _frames(3)
	_eq(_count("control-a", "agent.get"), 0, "no agent.get at all")
	_eq(_count("control-a", "agent.start"), 3, "the three starts, and nothing else written")


## A read-only office has no write boundary: it never asks herdr about a
## launch, not even one its snapshot shows pending.
func test_read_only_never_asks_about_a_launch() -> void:
	_fakes("snapshot_basic", [])
	var raw := _with_record(_raw(), "alpha:p2", {"launch_pending": true, "name": "claude-1"})
	_ctl("control-a", "set_snapshot", {"snapshot": raw})
	var office := await _office_with(true)
	var shell := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(
		func() -> bool: return office.fleet.snapshot(HerdrFleet.LOCAL).panes[1].launch_pending, "shown launching"
	)
	_eq(office.fleet.launch_of(shell), null, "no start of its own")
	_eq(office.fleet.launch_outcome(shell), LaunchWatch.Outcome.GONE, "nothing to judge")
	_eq(office.fleet.can_start(shell, "claude"), CommandRefusal.Reason.READ_ONLY, "and nothing to start")
	await _wait(1.0)
	_eq(_count("control-a", "agent.get") + _count("control-b", "agent.get"), 0, "no agent.get")
	_eq(_sequence("control-a") + _sequence("control-b"), PackedStringArray(), "nothing beyond the three reads")


# --- the START AGENT block on the card ------------------------------------------------


## A picked shell's card offers one button per agent kind its machine's
## snapshot shows, pooled: the same nodes for three kinds, one and none; with
## none, the note says where to start one. An agent's card starts nothing: its
## block offers a new pane beside it instead, with no kind button.
func test_a_shell_card_offers_the_kinds_seen_on_its_machine() -> void:
	var office := await _shell_card("$ \n", ["pane.read"])
	var launch := _control(office, "Launch")
	_check(launch.is_visible_in_tree(), "a picked shell: the START AGENT block")
	_eq((_control(office, "LaunchTitle") as Label).text, "START AGENT", "its title")
	_eq(_kinds_shown(office), ["CLAUDE", "CODEX", "PI"], "a button per kind Local shows, in capitals")
	_eq((_control(office, "LaunchNote") as Label).text, "Types the kind + Enter in this terminal", "the note")
	var tip := _kind(office, 0).tooltip_text
	_check(tip.begins_with("Types `claude` and Enter in this terminal"), "the tooltip says what it types: " + tip)
	_check("claude-1" in tip, "and the name herdr gives it")
	var nodes := _hud_nodes(office)
	var only_pi := _changed(_changed(_raw(), "alpha:p1", {"agent": null}), "alpha:p3", {"agent": null})
	_ctl("control-b", "set_snapshot", {"snapshot": only_pi})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	await _pick_bee(office, "alpha:p2")
	await _until(func() -> bool: return _kinds_shown(office) == ["PI"], "bee shows only pi")
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(only_pi, "bravo:p1", {"agent": null})})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	var note: Label = _control(office, "LaunchNote")
	await _until(func() -> bool: return _kinds_shown(office).is_empty(), "no kind on bee")
	_eq(note.text, "No agent kind seen on bee yet: start one in herdr first", "the note says where")
	_check(launch.is_visible_in_tree(), "the block stays, with its note")
	_eq(_hud_nodes(office), nodes, "pooled: no HUD node made or freed")
	await _pick_local(office, "alpha:p1")
	var title: Label = _control(office, "LaunchTitle")
	await _until(func() -> bool: return title.text == "NEW PANE BESIDE CLAUDE", "an agent's card: a new pane beside")
	_eq(_kinds_shown(office), [], "and no START AGENT")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "and nothing written")


## One click on CLAUDE over an empty prompt: one agent.start, named claude-1,
## with exactly name, kind and pane_id, after the re-read. Every kind waits
## meanwhile. The footer says it is starting, then that it started; the seat
## fills with somebody walking in under the hourglass, named CLAUDE-1 until
## herdr detects the kind. The viewer's pick holds through it, so the new
## agent takes a line, and the footer then says that line's outcome.
func test_a_kind_click_starts_the_agent_once_named_kind_n() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start", "agent.prompt"], {"detect": 1.2, "delay": 2.0})
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	_check(_kinds_enabled(office).is_empty(), "every kind waits while the start is out")
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start went")
	_eq(_asked("control-a", "agent.start"), [{"name": "claude-1", "kind": "claude", "pane_id": "alpha:p2"}], "")
	await _until(func() -> bool: return card.outcome_text().begins_with("Starting claude-1 · "), "starting")
	var station := _station_of(office, key)
	var hourglass := office.art.sprite_texture(office.art.ui_sprite(ArtContract.UI_STARTING))
	await _until(func() -> bool: return _plate(station).text == "CLAUDE-1", "the seat names the agent")
	_eq(_badge(station).texture, hourglass, "under the hourglass")
	_check(not office.floor_view.presentation.walkers().is_empty(), "somebody walks in")
	_eq((card.get_node("%Provider") as Label).text, "CLAUDE-1", "the card names it too")
	await _until(func() -> bool: return card.outcome_text() == "claude-1 started", "it started")
	_eq(_plate(station).text, "CLAUDE", "the seat names the kind once detected")
	_eq(_kinds_shown(office), [], "an agent now: no START AGENT")
	_eq((_control(office, "LaunchTitle") as Label).text, "NEW PANE BESIDE CLAUDE", "a new pane beside it instead")
	await _until(card.answer_offered, "the pick held: the new agent takes a line")
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("hello")
	await _click_control(_control(office, "SendLine"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "the line's outcome replaces the start's")
	_eq(
		_writes_seen("control-a"),
		PackedStringArray(
			[
				"pane.read recent_unwrapped 12 check",
				"agent.start claude claude-1",
				"pane.read recent_unwrapped 12 check",
				"agent.prompt 5 bytes"
			]
		),
		"read, start, then the line: nothing else"
	)


## A last row that does not end like a prompt (oh-my-zsh's) is not refused:
## the first click only arms a confirm that shows what herdr types after, with
## that row as it reads; a second click on the same kind sends, confirmed. A
## half-typed `$ ec` reads the same way; a click on another kind arms that one.
func test_an_unsure_prompt_needs_a_second_click_on_the_same_kind() -> void:
	var zsh := "➜  repo git:(main) ✗ \n"
	var office := await _shell_card(zsh, ["pane.read", "agent.start"])
	var card := _card(office)
	var note: Label = _control(office, "LaunchNote")
	var line: Label = _control(office, "LaunchLine")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed, to confirm")
	_check("confirm" in _kind(office, 0).tooltip_text, "the tooltip says a first click asks to confirm")
	await _click_control(_kind(office, 1))
	_eq(note.text, 'Start anyway? Types "codex" + Enter after:', "CODEX armed its confirm")
	await _click_control(_kind(office, 0))
	_eq(note.text, 'Start anyway? Types "claude" + Enter after:', "CLAUDE armed its own instead")
	_check(line.is_visible_in_tree(), "the row it types after is shown")
	_eq(line.text, "➜  repo git:(main) ✗", "as it reads, trailing blanks aside")
	await _frames(10)
	_eq(_writes_seen("control-a"), PackedStringArray(), "arming writes nothing")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the second click sent it")
	_eq(_asked("control-a", "agent.start"), [{"name": "claude-1", "kind": "claude", "pane_id": "alpha:p2"}], "")
	_eq(note.text, "Types the kind + Enter in this terminal", "the confirm is spent")
	_check(not line.is_visible_in_tree(), "and its row gone")
	await _until(func() -> bool: return not card.writing(), "the start settled")
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ ec\n"})
	await _pick_bee(office, "alpha:p2")
	await _until(func() -> bool: return card.preview_text() == "$ ec\n", "a half-typed line on bee")
	await _click_control(_kind(office, 2))
	_eq(note.text, 'Start anyway? Types "pi" + Enter after:', "a half-typed line asks too")
	_eq(line.text, "$ ec", "showing it")
	await _frames(10)
	_eq(_count("control-b", "agent.start"), 0, "nothing sent on bee")
	_eq(
		_writes_seen("control-a"),
		PackedStringArray(["pane.read recent_unwrapped 12 check", "agent.start claude claude-1"]),
		""
	)


## An armed confirm is the screen it was armed on: another text read in, a
## pick of another desk, or 10 s without the second click cancel it, and the
## click after that only arms again. A re-read of the same text does not.
func test_the_confirm_is_cancelled_by_a_new_screen_another_pick_or_ten_seconds() -> void:
	var office := await _shell_card("➜  repo \n", ["pane.read", "agent.start"])
	var card := _card(office)
	var note: Label = _control(office, "LaunchNote")
	var armed := 'Start anyway? Types "claude" + Enter after:'
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	_eq(note.text, armed, "armed")
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "➜  api \n"})
	await _until(func() -> bool: return card.preview_text() == "➜  api \n", "another text read in")
	_eq(note.text, "Types the kind + Enter in this terminal", "a new screen cancels it")
	await _click_control(_kind(office, 0))
	_eq(note.text, armed, "the next click arms again, and sends nothing")
	await _pick_local(office, "alpha:p1")
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return card.preview_text() == "➜  api \n", "back on the shell")
	_eq(note.text, "Types the kind + Enter in this terminal", "another pick cancelled it")
	await _click_control(_kind(office, 0))
	_eq(note.text, armed, "armed once more")
	_eq(OfficePaneInspector.CONFIRM_SECONDS, 10.0, "a confirm waits ten seconds")
	await _wait(7.0)
	_eq(note.text, armed, "re-reads of the same screen keep it armed")
	await _wait(3.5)
	_eq(note.text, "Types the kind + Enter in this terminal", "10 s without a second click cancel it")
	await _click_control(_kind(office, 0))
	_eq(note.text, armed, "so this click only arms")
	await _frames(10)
	_eq(_count("control-a", "agent.start"), 0, "nothing was ever sent")


## Nothing whole to look at (blank rows only) is no prompt: every kind is off
## and says why, and a click sends nothing. Once a prompt reads in, they are on.
func test_a_start_waits_for_a_prompt_on_the_screen() -> void:
	var office := await _shell_card("\n\n", ["pane.read", "agent.start"])
	await _frames(3)
	_eq(_kinds_shown(office), ["CLAUDE", "CODEX", "PI"], "the kinds show")
	_eq(_kinds_enabled(office), [], "all of them off")
	_check(
		"Off: no whole recent output" in _kind(office, 0).tooltip_text, "saying why: " + _kind(office, 0).tooltip_text
	)
	await _click_control(_kind(office, 0))
	await _frames(5)
	_eq(_writes_seen("control-a"), PackedStringArray(), "a click sends nothing")
	_eq((_control(office, "LaunchNote") as Label).text, "Types the kind + Enter in this terminal", "nor arms")
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "~/api $ \n"})
	await _until(func() -> bool: return _kinds_enabled(office).size() == 3, "a prompt read in: every kind is on")


## A start herdr takes and immediately blocks on a question (a trust prompt)
## is said in the footer, and its card offers the keys: the preview reads the
## question from herdr's detection text, and a key goes. A line does not.
func test_a_blocked_start_offers_the_keys() -> void:
	var office := await _shell_card(
		"$ \n", ["pane.read", "agent.start", "pane.send_keys"], {"outcome": "blocked", "detect": 0.2, "delay": 0.4}
	)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "detection", "text": QUESTION})
	var card := _card(office)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(
		func() -> bool: return card.outcome_text() == "claude-1 asks: answer with the keys", "the footer says it asks"
	)
	await _until(card.answer_offered, "and the card offers the keys")
	_eq(card.preview_text(), QUESTION, "reading the question herdr detects")
	await _open_answer(office)
	_eq(card.line_refusal(), CommandRefusal.Reason.AGENT_STARTING, "a line waits for the agent")
	await _until(func() -> bool: return not _key_button(office, "Key1").disabled, "key 1 is on")
	await _click_control(_key_button(office, "Key1"))
	await _until(func() -> bool: return _inputs("control-a").size() == 1, "key 1 went")
	var sent: Dictionary = _inputs("control-a")[0]
	_eq(sent.get("keys"), ["1"], "as 1")
	_eq(_count("control-a", "agent.start"), 1, "one start")


## However far a start has got, how it went is said: herdr still launching
## past the deadline (not detected), no answer to the deadline's question
## (unknown), herdr gave it up (did not start), the connection changed before
## the deadline (not checked), another terminal in the pane. On the boundary's
## clock; the seconds in the text are the card's.
func test_the_footer_says_how_a_start_that_never_came_up_ended() -> void:
	var raw := _shell_beside(_shell_beside(_raw(), "alpha:p2", "alpha:p4"), "alpha:p2", "alpha:p5")
	var office := await _shell_card("$ \n", ["pane.read", "agent.start", "agent.get"], {"outcome": "never"}, raw)
	var card := _card(office)
	var skip := [0]
	office.fleet.use_command_clock(func() -> int: return Time.get_ticks_msec() + skip[0])
	for pane_id: String in ["alpha:p4", "alpha:p5"]:
		_ctl("control-a", "set_preview", {"pane_id": pane_id, "source": "recent_unwrapped", "text": "$ \n"})
	_ctl("control-b", "set_launch", {"outcome": "never"})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var picks := [["alpha:p2", "claude-1"], ["alpha:p4", "claude-2"], ["alpha:p5", "claude-3"], ["bee", "claude-1"]]
	for pick: Array in picks:
		var pane_id: String = pick[0]
		if pane_id == "bee":
			await _pick_bee(office, "alpha:p2")
		else:
			await _pick_local(office, pane_id)
		await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE on " + pane_id)
		await _click_control(_kind(office, 0))
		await _until(func() -> bool: return card.outcome_text().begins_with("Starting " + str(pick[1])), "starting")
	# Local asks about p2 first and loses the answer; p4 and p5 are still launching.
	_ctl("control-a", "next", {"action": "drop", "method": "agent.get"})
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(BEE), "bee drops")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return office.fleet.live_count() == 2, "and comes back as a new connection")
	skip[0] = LaunchWatch.TIMEOUT_MSEC + 1000
	await _until(func() -> bool: return _count("control-a", "agent.get") == 3, "the deadline asks about each")
	var said: Dictionary[String, String] = {
		"alpha:p2": "claude-1: no answer from herdr",
		"alpha:p4": "claude-2 not detected after 31s: look at the terminal",
		"bee": "claude-1 not checked: the connection changed",
	}
	for pane_id: String in said:
		if pane_id == "bee":
			await _pick_bee(office, "alpha:p2")
		else:
			await _pick_local(office, pane_id)
		var text := said[pane_id]
		await _until(func() -> bool: return card.outcome_text() == text, text)
	_eq(_count("control-b", "agent.get"), 0, "bee's start was never asked about: another connection")
	var moved := _changed(_dict(_ctl("control-a", "stats"), "snapshot"), "alpha:p5", {"terminal_id": "term-new"})
	_ctl("control-a", "set_snapshot", {"snapshot": moved})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _pick_local(office, "alpha:p5")
	await _until(func() -> bool: return card.outcome_text() == "Terminal changed", "another terminal in p5")
	_eq(_count("control-a", "agent.start") + _count("control-b", "agent.start"), 4, "four starts, none again")


## herdr gives a start up when asked at the deadline: the footer says it did
## not start; the pane is a shell again and, after a look, takes another,
## under the same name: herdr freed it, and so does this run.
func test_a_start_herdr_gave_up_is_said_and_the_shell_is_offered_again() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start", "agent.get"], {"outcome": "never"})
	_ctl("control-a", "set_launch_timeout", {"seconds": 0})
	var card := _card(office)
	var skip := [0]
	office.fleet.use_command_clock(func() -> int: return Time.get_ticks_msec() + skip[0])
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return card.outcome_text().begins_with("Starting claude-1"), "starting")
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return office.frame.pane(key).starting, "the snapshot shows it launching")
	skip[0] = LaunchWatch.TIMEOUT_MSEC + 1000
	var failed := "claude-1 did not start: look at the terminal"
	await _until(func() -> bool: return card.outcome_text() == failed, "herdr gave it up")
	_eq([card.outcome_text(), _count("control-a", "agent.get")], [failed, 1], "asked once, and said")
	_check("gave the start up" in (card.get_node("%Outcome") as Label).tooltip_text, "the tooltip says how")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "the shell takes a start again")
	_check("claude-1" in _kind(office, 0).tooltip_text, "under the name herdr freed")
	_eq(_count("control-a", "agent.start"), 1, "nothing was retried")


## Every key the card's keyboard knows, pressed over a picked shell whose
## kinds are on: no start, no write of any kind.
func test_the_keyboard_never_starts_an_agent() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"])
	await _until(func() -> bool: return _kinds_enabled(office).size() == 3, "every kind is on")
	for code: Key in [KEY_ENTER, KEY_KP_ENTER, KEY_1, KEY_2, KEY_9, KEY_Y, KEY_SPACE, KEY_TAB]:
		await _tap(code)
	for code: Key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		await _tap(code)
	await _hold(KEY_1, 5)
	_eq(_kinds_enabled(office).size(), 3, "still the shell's card, every kind on")
	# Escape folds the opened panel, Enter opens it again: neither starts anything.
	await _tap(KEY_ESCAPE)
	_check(office.hud.card_compact(), "Escape folds the panel")
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return _kinds_enabled(office).size() == 3, "Enter opens it again, every kind on")
	# Last: N is the office's, and moves the pick on.
	await _tap(KEY_N)
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "no key wrote anything")


## A start aimed at one pane is not sent to another: the pick moves between
## press and release; the terminal is replaced, or the machine drops, while
## the start re-reads the screen. Nothing is sent, and the footer says so.
func test_a_start_is_refused_when_the_pane_changes_between_click_and_send() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"])
	var card := _card(office)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	var binding := card.binding()
	_half_click(_kind(office, 0), true)
	await process_frame
	await _tap(KEY_N)
	await _until(func() -> bool: return card.binding() != binding, "N moved the pick under the press")
	_half_click(_kind(office, 0), false)
	await _frames(4)
	_eq(card.outcome_text(), "Not sent: target changed", "the card says so on the new binding")
	_eq(_writes_seen("control-a"), PackedStringArray(), "the pick moved: nothing written, not even a re-read")
	# N opened answer mode on the blocked agent it picked, and its panel stands
	# over the world's middle: Escape leaves it before the shell is clicked again.
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _pick_local(office, "alpha:p2")
	var check := {"action": "delay", "method": "pane.read", "id_suffix": HerdrCommands.CHECK_SUFFIX, "seconds": 1.2}
	_ctl("control-a", "next", check)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE again")
	await _click_control(_kind(office, 0))
	_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p2", {"terminal_id": "term-new"})})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return not card.writing(), "the start settled")
	# The re-read answered; the check after it, on the fleet's newest facts, found
	# another terminal: refused there, never written.
	_eq(_last_write(office), "REFUSED", "a new terminal by the send: refused")
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	_eq(office.fleet.last_write(key).refusal, CommandRefusal.Reason.IDENTITY_CHANGED, "for the new terminal")
	_eq(card.outcome_text(), "New terminal: pick again", "the card, now on it, says so")
	_eq(_count("control-a", "agent.start"), 0, "no start went")
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "the new terminal's CLAUDE")
	# The re-read held long enough for the drop to be seen first: the machine
	# went while it was open, so it is cancelled (HerdrCommands.settle_machine()).
	check["seconds"] = 4.0
	_ctl("control-a", "next", check)
	await _click_control(_kind(office, 0))
	_ctl("control-a", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(HerdrFleet.LOCAL), "Local drops")
	await _until(func() -> bool: return not card.writing(), "settled as the machine went")
	_eq(_last_write(office), "CANCELLED", "the machine gone while it re-read: cancelled")
	_ctl("control-a", "appear")
	_eq(_count("control-a", "agent.start"), 0, "no start reached herdr")


## herdr refusing a start (the pane is busy, the name is taken) is said, is
## never retried, and like any write ends with a look owed before the next.
func test_herdrs_refusals_of_a_start_are_said_and_owe_a_look() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"])
	var card := _card(office)
	for code: String in ["agent_pane_busy", "agent_name_taken"]:
		_ctl("control-a", "next", {"action": "refuse", "method": "agent.start", "code": code, "message": "no"})
		await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
		await _click_control(_kind(office, 0))
		var said := "herdr refused: " + CommandRejection.text(CommandRejection.of(code))
		await _until(func() -> bool: return card.outcome_text() == said, code + " is said: " + said)
		_check("look" in _kind(office, 0).tooltip_text, "every kind waits for a look: " + _kind(office, 0).tooltip_text)
	_eq(_count("control-a", "agent.start"), 2, "two gestures, two starts, nothing retried")


## 480x320: the shell's compact line opens with Enter (a shell with kinds to
## start may open now), and the block takes the PANE details' place, every
## button whole, inside the panel and off the others; Esc folds it. At 800x480,
## opened again (the panel is one line at every size), both show.
func test_the_launch_block_fits_the_smallest_screen_and_keeps_pane_details_when_wide() -> void:
	var office := await _shell_card("$ \n", ["pane.read"], {}, {}, Vector2(480, 320), false)
	var card := _card(office)
	var launch := _control(office, "Launch")
	var more := _control(office, "More")
	_check(office.hud.card_compact() and not launch.is_visible_in_tree(), "a compact line, no block")
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return not office.hud.card_compact(), "Enter opens the shell's card")
	await _until(func() -> bool: return _kinds_enabled(office).size() == 3, "its kinds are on")
	await _frames(3)
	_check(launch.is_visible_in_tree() and not more.is_visible_in_tree(), "the block in PANE's place")
	_eq(office.hud.placed(card).size, Vector2(448, 128), "the card at 480x320, opened")
	_eq(office.hud.world_rect().size, Vector2(340, 112), "the world above it keeps a desk's room")
	_launch_fits(card, "480x320")
	_panels_apart(office, "480x320, opened")
	_ctl(
		"control-a",
		"set_preview",
		{"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "➜  repo git:(main) ✗\n"}
	)
	await _until(func() -> bool: return card.preview_text().begins_with("➜"), "an unsure prompt read in")
	await _click_control(_kind(office, 0))
	await _frames(3)
	_check(_control(office, "LaunchLine").is_visible_in_tree(), "a confirm armed")
	_launch_fits(card, "480x320, a confirm")
	await _tap(KEY_ESCAPE)
	await _until(office.hud.card_compact, "Esc folds it")
	office.test_screen = Vector2(800, 480)
	office.refresh()
	await _frames(2)
	_check(office.hud.card_compact(), "800x480: still one line")
	await _open_panel(office)
	await _until(func() -> bool: return launch.is_visible_in_tree() and more.is_visible_in_tree(), "800x480: both")
	await _frames(3)
	_launch_fits(card, "800x480")
	_eq(_writes_seen("control-a"), PackedStringArray(), "nothing written")


## The pick follows this office's own start from the shell into the agent it
## became, and into that agent's first session; not past it: a later session
## (`/clear`) is a new one to pick again, like any agent's.
func test_the_pick_follows_a_start_into_its_first_session_only() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"])
	var card := _card(office)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return card.outcome_text() == "claude-1 started", "it started")
	await _until(card.answer_offered, "the pick followed the start into the agent")
	await _reshape(office, {"agent_session": _session("first")})
	await _until(card.answer_offered, "and into its first session")
	await _reshape(office, {"agent_session": _session("cleared")})
	_eq(card.outcome_text(), "New terminal: pick again", "a later session is picked again")
	_check(not card.answer_offered(), "nothing to answer until then")


## Carrying the pick over a start is a pick and nothing more: it counts as no
## navigation, into the agent and into its first session, and a press the
## viewer holds on the world meanwhile is still theirs (the office's pick of a
## new pane ends one; this does not).
func test_the_pick_carried_over_a_start_is_a_pick_and_nothing_more() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"])
	var card := _card(office)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	var navigations := office.navigator.nav_revision
	await _click_control(_kind(office, 0))
	await _until(card.answer_offered, "the pick followed the start into the agent")
	_check(office.navigator.is_picked(office.frame.pane(key)), "the agent is the pick")
	_eq(office.navigator.nav_revision, navigations, "carried: not a navigation")
	var at := office.hud.world_rect().get_center()
	await _world_button(at, true)
	_check(office.camera.dragging, "a press held on the world: a drag under way")
	await _reshape(office, {"agent_session": _session("first")})
	await _until(card.answer_offered, "and into its first session")
	_check(office.navigator.is_picked(office.frame.pane(key)), "the agent in its session is the pick")
	_eq(office.navigator.nav_revision, navigations, "still not a navigation")
	_check(office.camera.dragging, "the press under way is the viewer's still")
	await _world_button(at + Vector2(60, 0), false)
	_eq(office.picked_key, key, "its release, 60 px on, picks nothing")
	_eq(_count("control-a", "agent.start"), 1, "one start, nothing more")


## The pick follows only this office's start: not an agent the viewer never
## picked in that terminal: one of another kind, one of the same kind herdr
## lists without the start's name (it exited, and the same kind was started by
## hand), or anything after the office wrote to the pane again.
func test_the_pick_does_not_follow_into_an_agent_nobody_picked() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"], {"outcome": "never"})
	var card := _card(office)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return card.outcome_text().begins_with("Starting claude-1"), "starting")
	# Herdr gave up on it and a codex was started by hand: idle, ready, no name.
	await _reshape(office, {"agent": "codex", "agent_status": "idle"}, {"launch_pending": null, "name": null})
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	await _until(func() -> bool: return not office.fleet.must_look(key), "the start's look is done")
	await _until(func() -> bool: return card.preview_state() == OfficePaneInspector.PreviewState.SHOWN, "shown")
	_eq(card.outcome_text(), "Terminal changed", "the start's line: another holds the pane")
	_check(not card.answer_offered(), "another kind there: not the pick, nothing to answer")
	# One office at a time: the next one's Enter (it opens its panel) is its own.
	root.remove_child(office)
	office.free()
	office = await _shell_card("$ \n", ["pane.read", "agent.start"])
	card = _card(office)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(card.answer_offered, "the pick followed the start into the agent")
	await _reshape(office, {"agent_session": _session("by hand")}, {"name": null})
	_eq(card.outcome_text(), "New terminal: pick again", "the same kind without the start's name: picked again")
	_check(not card.answer_offered(), "and not answerable")
	root.remove_child(office)
	office.free()
	office = await _shell_card("$ \n", ["pane.read", "agent.start", "agent.prompt"])
	card = _card(office)
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(card.answer_offered, "the pick followed the start into the agent")
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("hi")
	await _click_control(_control(office, "SendLine"))
	await _until(func() -> bool: return card.outcome_text() == "Sent", "a line went: the office wrote again")
	await _reshape(office, {"agent_session": _session("after")})
	_eq(card.outcome_text(), "New terminal: pick again", "a session after that write: picked again")


## A write re-reads the screen, then goes: the footer says so as it happens,
## "Checking the screen…" and then "Sending…" while herdr has not answered,
## for a start as for a line (the ticket signals only its end, so the card
## looks at it each frame).
func test_the_footer_says_sending_once_the_screen_checked() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start", "agent.prompt"])
	var card := _card(office)
	_ctl("control-a", "next", {"action": "delay", "method": "agent.start", "seconds": 1.5})
	await _until(func() -> bool: return not _kind(office, 0).disabled, "CLAUDE may be pressed")
	await _click_control(_kind(office, 0))
	await _until(func() -> bool: return _count("control-a", "agent.start") == 1, "the start is at herdr")
	await _until(func() -> bool: return card.outcome_text() == "Sending…", "the start: Sending…")
	_check(card.writing(), "while herdr has not answered")
	await _until(func() -> bool: return not card.writing(), "the start settled")
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": "done.\n$ \n"})
	_ctl("control-b", "next", {"action": "delay", "method": "agent.prompt", "seconds": 1.5})
	await _pick_bee(office, "alpha:p3")
	await _until(card.answer_offered, "the idle codex takes a line")
	await _open_answer(office)
	await _click_control(_reply_box(office))
	await _type("hi")
	await _click_control(_control(office, "SendLine"))
	await _until(func() -> bool: return _count("control-b", "agent.prompt") == 1, "the line is at herdr")
	await _until(func() -> bool: return card.outcome_text() == "Sending…", "the line: Sending…")
	await _until(func() -> bool: return not card.writing(), "the line settled")


## Read-only: no block on a shell's card, and Enter does not open one; herdr
## hears nothing but the three reads.
func test_read_only_offers_no_launch() -> void:
	_fakes("snapshot_basic", [])
	var office := await _office_with(true, true, true, Vector2(480, 320))
	await _pick_local(office, "alpha:p2", false)
	await _frames(3)
	_check(office.hud.card_compact(), "the panel is one line")
	_check(not _control(office, "Launch").is_visible_in_tree(), "no START AGENT")
	await _tap(KEY_ENTER)
	await _frames(3)
	# Enter opens any pane's panel, read-only too; it offers no start.
	_check(not office.hud.card_compact(), "Enter opens the panel")
	_check(not _control(office, "Launch").is_visible_in_tree(), "with no START AGENT in it")
	_eq(_sequence("control-a") + _sequence("control-b"), PackedStringArray(), "nothing beyond the three reads")


## Zero gestures, zero writes: a shell's card with every kind on through
## status changes elsewhere, events, a new screen, a resize and seconds.
func test_a_start_writes_nothing_without_a_gesture() -> void:
	var office := await _shell_card("$ \n", ["pane.read", "agent.start"])
	await _until(func() -> bool: return _kinds_enabled(office).size() == 3, "every kind is on")
	for index in 30:
		_ctl("control-a", "status", {"pane_id": "alpha:p1", "agent_status": "idle" if index % 2 == 0 else "working"})
		_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
		await _frames(2)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ ls\n$ \n"})
	for screen: Vector2 in [Vector2(640, 400), Vector2(800, 480)]:
		office.test_screen = screen
		office.refresh()
		await _frames(3)
	await _wait(3.0)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## A shell's card says what it is, not an agent state: `SHELL`, `no agent`, no
## person and no badge, and no time in a state (herdr's idle for a shell is the
## terminal's). An agent's card is unchanged; while herdr launches an agent in
## the shell, the card shows the launch (its name, STARTING, a person, the badge).
func test_a_shell_card_says_no_agent_and_draws_no_person() -> void:
	var office := await _shell_card("$ \n", ["pane.read"])
	_eq((_control(office, "Provider") as Label).text, "SHELL", "the shell's name")
	_eq((_control(office, "Caption") as Label).text, "no agent", "and what it is, not IDLE")
	_check(not (_control(office, "PortraitArea") as Control).visible, "no person for a pane without an agent")
	_check(not (_card(office).get_node("%Badge") as Node2D).visible, "and no state badge")
	await _frames(20)
	_eq((_control(office, "Duration") as Label).text, "", "no time in a state")
	await _pick_local(office, "alpha:p1")
	var caption: Label = _control(office, "Caption")
	await _until(func() -> bool: return caption.text != "no agent", "an agent's card")
	_eq((_control(office, "Provider") as Label).text, "CLAUDE", "an agent's card names its provider")
	_check((_control(office, "PortraitArea") as Control).visible, "with its person")
	_check((_card(office).get_node("%Badge") as Node2D).visible, "and its state badge")
	_eq(caption.text, _card(office).art.state(&"working").label, "and its state in the pack's words")
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return caption.text == "no agent", "the shell again")
	var launching := _with_record(_raw(), "alpha:p2", {"launch_pending": true, "name": "claude-9"})
	_ctl("control-a", "set_snapshot", {"snapshot": launching})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return caption.text == "STARTING", "a launch in the shell: STARTING")
	_eq((_control(office, "Provider") as Label).text, "CLAUDE-9", "under the name herdr gave it")
	_check((_control(office, "PortraitArea") as Control).visible, "a person comes in")
	_check((_card(office).get_node("%Badge") as Node2D).visible, "with the starting badge")
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## herdr gave a start up at the deadline (agent_not_found): it freed the pane
## and the name at once (measured against herdr 0.9.0), so this run no longer holds the
## name either. After a look the same name may go to the same shell again; the
## start still reads FAILED, and its watch is still the pane's.
func test_a_start_herdr_gave_up_frees_its_name() -> void:
	_fakes("snapshot_basic", ["pane.read", "agent.start", "agent.get"])
	_ctl("control-a", "set_launch", {"outcome": "never"})
	_ctl("control-a", "set_launch_timeout", {"seconds": 0})
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ \n"})
	var raw := _raw()
	var facts := _facts(args["socket-a"], raw)
	var launching := _facts(
		args["socket-a"], _with_record(raw, "alpha:p2", {"launch_pending": true, "name": "claude-1"})
	)
	var commands := _boundary()
	var now := [3000000]
	commands.clock = func() -> int: return now[0]
	commands.machine_facts = func(_machine_key: String) -> HerdrCommands.Machine: return launching
	var shell := _aim(facts, "alpha:p2")
	var seen := _seen(commands, facts, "alpha:p2", CommandContext.SOURCE_RECENT, 12)
	var start := commands.submit(shell.starting("claude", "claude-1", seen), facts, _facts_now(facts))
	_settle(commands, start, "the start")
	_eq(start.state, CommandTicket.State.ACCEPTED, "the start went")
	_eq(commands.launch_names(shell.machine), PackedStringArray(["claude-1"]), "launching: its name is held")
	now[0] += HerdrCommands.LAUNCH_TIMEOUT_MSEC
	commands.pump(0.0)
	var watch := commands.launch_of(shell.pane_key)
	_check(watch.check != null, "at the deadline, one launch check")
	if watch.check == null:
		commands.free()
		return
	_settle(commands, watch.check, "the launch check")
	now[0] += HerdrCommands.LAUNCH_GRACE_MSEC
	var settled := _facts(args["socket-a"], _dict(_ctl("control-a", "stats"), "snapshot"))
	var pane := _pane_of(settled.snapshot, "alpha:p2")
	_eq(LaunchWatch.name_of(LaunchWatch.judge(watch, pane, commands.now_msec())), "FAILED", "herdr gave it up")
	_eq(commands.launch_names(shell.machine), PackedStringArray(), "and this run no longer holds its name")
	await _look(commands, settled, "alpha:p2")
	var again := _aim(settled, "alpha:p2").starting("claude", "claude-1", null)
	_eq(
		[HerdrCommands.refusal(again, settled), commands.blocker(again)],
		[CommandRefusal.Reason.NONE, CommandRefusal.Reason.NONE],
		"the same name may go to the same shell again"
	)
	_eq(commands.launch_of(shell.pane_key), watch, "the failed start is still the pane's last")
	_eq(_count("control-a", "agent.start"), 1, "nothing was started again")
	commands.free()


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)


# --- helpers -----------------------------------------------------------------------


## A line to pane `pane_id` as the card sends one: its recent output read,
## then the line aimed at it; settled.
func _prompted(
	commands: HerdrCommands, facts: HerdrCommands.Machine, pane_id: String, line: String, step := 0.0
) -> CommandTicket:
	var seen := _seen(commands, facts, pane_id, CommandContext.SOURCE_RECENT, 12)
	var ticket := commands.submit(_aim(facts, pane_id).replying(line, seen), facts, _facts_now(facts))
	_settle(commands, ticket, "the line to " + pane_id, step)
	return ticket


## A launch check's ticket as it ended: `state`, herdr's `code` for a
## rejection, and for an accepted one whether herdr still launches the agent.
func _checked(state: CommandTicket.State, code: String, pending: bool) -> CommandTicket:
	var ticket := CommandTicket.new(null)
	if state == CommandTicket.State.REJECTED:
		ticket.error_code = code
		ticket.rejection = CommandRejection.of(code)
	if state == CommandTicket.State.ACCEPTED:
		ticket.agent_info = AgentInfoResult.new()
		ticket.agent_info.launch_pending = pending
	if state != CommandTicket.State.UNSENT:
		ticket.settle(state)
	return ticket


## At a fake, by `stats` (its request log and the monotonic seconds each came
## at): how long after the first `method` request the next session.snapshot
## came (x), and how long after the session.snapshot before that one (y); -1
## for either that is not there.
func _snapshot_gaps(stats: Dictionary, method: String) -> Vector2:
	var methods := _list(stats, "methods")
	var times := _list(stats, "times")
	var at := -1
	for index in methods.size():
		if methods[index] == method:
			at = index
			break
	if at < 0 or times.size() != methods.size():
		return Vector2(-1, -1)
	var sent: float = times[at]
	var before := -1.0
	for index in at:
		if methods[index] == "session.snapshot":
			before = times[index]
	for index in range(at + 1, methods.size()):
		if methods[index] == "session.snapshot":
			var next: float = times[index]
			return Vector2(next - sent, next - before if before >= 0.0 else -1.0)
	return Vector2(-1, -1)


## Whether no grapheme cluster of `text` is over TerminalText.CLUSTER_MAX code points.
func _clusters_bounded(text: String) -> bool:
	var start := 0
	for end in TerminalText.breaks(text):
		if end - start > TerminalText.CLUSTER_MAX:
			return false
		start = end
	return true


## Pane `pane_id` of `snapshot`, or null.
func _pane_of(snapshot: HerdrSnapshot, pane_id: String) -> HerdrSnapshot.Pane:
	for pane in snapshot.panes:
		if pane.pane_id == pane_id:
			return pane
	return null


## Pane `pane_id`'s agent record in raw snapshot `raw`; empty with none.
func _record_of(raw: Dictionary, pane_id: String) -> Dictionary:
	for record: Dictionary in _list(raw, "agents"):
		if record.get("pane_id") == pane_id:
			return record
	return {}


## `raw` with pane `pane_id`'s agent record given `fields` (a null value
## removes one); a pane without a record gets one with its ids, as herdr lists
## a shell it is launching an agent in.
func _with_record(raw: Dictionary, pane_id: String, fields: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var record := _record_of(result, pane_id)
	if record.is_empty():
		for pane: Dictionary in _list(result, "panes"):
			if pane.get("pane_id") == pane_id:
				for field: String in ["terminal_id", "pane_id", "workspace_id", "tab_id"]:
					record[field] = pane.get(field)
		var agents := _list(result, "agents")
		agents.append(record)
		result["agents"] = agents
	for field: String in fields:
		if fields[field] == null:
			record.erase(field)
		else:
			record[field] = fields[field]
	return result


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


## `raw` with a second shell `new_id`, a copy of pane `like` with its own terminal.
func _shell_beside(raw: Dictionary, like: String, new_id: String) -> Dictionary:
	var result := raw.duplicate(true)
	var panes := _list(result, "panes")
	for pane: Dictionary in panes.duplicate():
		if pane.get("pane_id") == like:
			var copy: Dictionary = pane.duplicate(true)
			copy["pane_id"] = new_id
			copy["terminal_id"] = "term-" + new_id.replace(":", "-")
			panes.append(copy)
	result["panes"] = panes
	return result


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


## One half of a real left press at `at` (viewport pixels) on the world,
## through `Input` as a mouse sends it: the office asks
## `Input.is_mouse_button_pressed()` before it pans.
func _world_button(at: Vector2, down: bool) -> void:
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
		if _kind(office, index).is_visible_in_tree() and not _kind(office, index).disabled:
			shown.append(_kind(office, index).text)
	return shown


## The START AGENT block inside the panel and beside the preview, each of its
## controls inside it, each kind button wide enough for its whole label (the
## rule of test_commands.gd's _whole_labels()), and its note in two lines.
func _launch_fits(card: OfficePaneInspector, what: String) -> void:
	var bounds := (card.get_node("Frame/Row") as Control).get_global_rect().grow(0.5)
	var launch: Control = card.get_node("%Launch")
	var block := launch.get_global_rect()
	var preview: Control = card.get_node("%Preview")
	_check(bounds.encloses(block), "%s: the block %s inside the panel %s" % [what, block, bounds])
	_check(not preview.get_global_rect().intersects(block), "%s: beside the preview, not over it" % what)
	print("%s: preview %.0f wide, block %s" % [what, preview.size.x, block])
	for node: Node in launch.find_children("*", "Control", true, false):
		var control: Control = node
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		_check(block.grow(0.5).encloses(rect), "%s: %s %s inside the block" % [what, control.name, rect])
		if control is Button:
			var button: Button = control
			var size := button.get_theme_font_size("font_size")
			var needed := button.get_theme_font("font").get_string_size(button.text, 0, -1, size).x
			needed += button.get_theme_stylebox("normal").get_minimum_size().x
			_check(
				rect.size.x >= needed - 0.5, "%s: `%s` whole (%.0f of %.0f)" % [what, button.text, rect.size.x, needed]
			)
	var note: Label = card.get_node("%LaunchNote")
	_check(note.get_line_count() <= 2, "%s: `%s` whole in two lines: %d" % [what, note.text, note.get_line_count()])


## Every node under the HUD, by instance id, sorted: the same list after a
## refresh means nothing was made or freed.
func _hud_nodes(office: OfficeDouble) -> Array:
	var found: Array = []
	for node: Node in office.hud.find_children("*", "", true, false):
		found.append(node.get_instance_id())
	found.sort()
	return found


## Local's alpha:p2 in fake A's snapshot as it is now, changed by `changes`
## in its pane and agent record and by `record` in the record alone (a null
## removes a field), sent with an event; back once the office shows the change
## and the card has taken it in.
func _reshape(office: OfficeDouble, changes: Dictionary, record := {}) -> void:
	var raw := _changed(_dict(_ctl("control-a", "stats"), "snapshot"), "alpha:p2", changes)
	if not record.is_empty():
		raw = _with_record(raw, "alpha:p2", record)
	var expected := raw
	_ctl("control-a", "set_snapshot", {"snapshot": expected})
	_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
	var wanted := _pane_of(HerdrSnapshot.from_wire(expected), "alpha:p2")
	var shown := func() -> bool:
		var pane := office.frame.pane(key)
		return pane != null and pane.provider == wanted.agent and pane.identity_key() == _identity_of(wanted)
	await _until(shown, "the office shows alpha:p2 changed")
	await _frames(3)


## PaneModel.identity_key() of a snapshot pane.
func _identity_of(pane: HerdrSnapshot.Pane) -> String:
	return AgentSessionIdentity.runtime_key(pane.terminal_id, pane.agent, pane.agent_session)


## An agent session record of claude's, as herdr sends one.
func _session(value: String) -> Dictionary:
	return {"source": "fixture", "agent": "claude", "kind": "session_id", "value": value}


## The name plate and the state badge over a seat (scenes/world/station.tscn).
func _plate(station: Node) -> Label:
	return station.get_node("Overlay/Plate")


func _badge(station: Node) -> StatusBadge:
	return station.get_node("Overlay/Badge")
