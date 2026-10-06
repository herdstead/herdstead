extends "res://tools/test_base.gd"
## The agent card's picture (CardPicture): what the card shows for the facts it
## is given, as tables. Pure: no scene, no office, no fleet, no herdr, and the
## clock is a number in the facts. The words the write suites assert through
## real gestures are pinned here whole, text and tooltip, one arm at a time.
## Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_card_picture.gd

const QUESTION := "Allow this?\n  1. Yes\n  2. No\n"
const NEXT_TIP := "N: the next agent who needs you."
const SWITCH_TIP := (
	"Switches the shared view of herdr to this pane: every terminal attached to it follows."
	+ "\nIt also clears UNREAD for every pane on this tab, not just this one."
)
const ANSWER_ON_ITS_WAY := "The answer is on its way: the card reads the terminal again first, then sends."


func _initialize() -> void:
	run_cases.call_deferred()


func _marker() -> String:
	return "CARD PICTURE TESTS"


# --- the facts the cases start from ---------------------------------------------


## An agent's pane on machine `local`: claude, blocked, in space `web`, tab `main`.
func _agent(state := "blocked", provider := "claude") -> PaneModel:
	var pane := PaneModel.new()
	pane.pane_id = "w1:p1"
	pane.key = HerdrFleet.pane_key("local", "w1:p1")
	pane.terminal_id = "term-1"
	pane.provider = provider
	pane.state = state
	pane.starting_known = true
	pane.workspace_label = "web"
	pane.tab_label = "main"
	pane.cwd = "/home/u/repo"
	return pane


## A picked pane on an operator office, at full height, its question shown
## three seconds ago, nothing in flight, nothing said, everything pressable.
func _facts(pane: PaneModel = _agent()) -> CardPicture.Facts:
	var facts := CardPicture.Facts.new()
	facts.pane = pane
	facts.pick = OfficePaneInspector.Pick.PICKED
	facts.state_caption = "" if pane == null else pane.state.to_upper()
	facts.state_badge = &"" if pane == null else StringName(pane.state)
	facts.connected = true
	facts.next_tip = NEXT_TIP
	facts.preview = OfficePaneInspector.PreviewState.SHOWN
	facts.text = QUESTION
	facts.source = CommandContext.SOURCE_DETECTION
	facts.read_at_msec = 10000
	facts.now_msec = 13000
	facts.line_bytes_max = 1024
	facts.answer_possible = true
	return facts


## A command of `kind` aimed at `pane`, as the fleet would aim it.
func _aimed(pane: PaneModel, kind: CommandContext.Kind) -> CommandContext:
	var target := CommandContext.aimed(
		"local", 1, pane.key, pane.pane_id, pane.pane_id, pane.identity_key(), 1, "term-1"
	)
	var aimed := target.replying("hello", null)
	match kind:
		CommandContext.Kind.READ:
			aimed = target.reading(CommandContext.SOURCE_RECENT, 12)
		CommandContext.Kind.FOCUS:
			aimed = target.focusing()
		CommandContext.Kind.KEYS:
			aimed = target.keying("1", null)
		CommandContext.Kind.START:
			aimed = target.starting("claude", "claude-2", null)
		CommandContext.Kind.SPLIT:
			aimed = target.splitting("right")
		CommandContext.Kind.CLOSE:
			aimed = target.closing(CloseScope.new())
		CommandContext.Kind.SPACE:
			aimed = target.spacing("/home/u/repo")
		CommandContext.Kind.WORKTREE:
			aimed = target.branching("w1", "w1", "feat")
	return aimed


## A ticket of `kind` for `pane` in `state`.
func _ticket(pane: PaneModel, kind: CommandContext.Kind, state := CommandTicket.State.UNSENT) -> CommandTicket:
	var ticket := CommandTicket.new(_aimed(pane, kind))
	if state == CommandTicket.State.REFUSED:
		ticket.refuse(CommandRefusal.Reason.LOOK_FIRST)
	elif state != CommandTicket.State.UNSENT:
		ticket.settle(state, "timed out")
	return ticket


## The footer's text and tooltip for `facts`.
func _footer(facts: CardPicture.Facts) -> Array:
	var actions := CardPicture.actions_of(facts)
	return [actions.footer, actions.footer_tip]


## Every script variable of `thing`, by name, objects inside it likewise: for
## comparing two values field by field.
func _flat(thing: Object) -> Dictionary:
	var out := {}
	if thing == null:
		return out
	for property: Dictionary in thing.get_property_list():
		var usage: int = property.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var name := str(property.name)
		var value: Variant = thing.get(name)
		if value is Object:
			var inner: Object = value
			out[name] = _flat(inner)
		else:
			out[name] = value
	return out


# --- the footer -----------------------------------------------------------------


## The footer says one thing: the first of its arms that has something to
## say. With every arm loaded at once, taking the winner away each time walks
## the whole order down to nothing.
func test_the_footer_arms_speak_in_their_order() -> void:
	var pane := _agent("working")
	var facts := _facts(pane)
	facts.switching = true
	facts.input = _ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.SENT)
	facts.outcome = "Sent"
	facts.outcome_detail = "herdr accepted the keystrokes; not whether the agent acted."
	facts.outcome_identity = pane.identity_key()
	facts.launch_line = "claude-2 started"
	facts.launch_detail = "claude-2 started: herdr detects the agent and no longer reports it launching."
	facts.pick = OfficePaneInspector.Pick.FOLLOWING
	facts.keys_refusal = CommandRefusal.Reason.UNSEEN
	facts.line_refusal = CommandRefusal.Reason.AGENT_BUSY
	facts.switch_refusal = CommandRefusal.Reason.LOOK_FIRST
	_eq(_footer(facts), ["Switching…", "The switch is on its way to herdr."], "1: the switch in flight")
	facts.switching = false
	_eq(_footer(facts), ["Sending…", ANSWER_ON_ITS_WAY], "2: an input in flight")
	facts.input = null
	_eq(_footer(facts), ["Sent", facts.outcome_detail], "3: what became of the last write")
	facts.outcome = ""
	_eq(_footer(facts), ["claude-2 started", facts.launch_detail], "4: how the start is going")
	facts.launch_line = ""
	# From here in answer mode, with nothing pressable: its own word waits
	# behind whose pane this is.
	facts.answering = true
	var following := "This card follows herdr's own focus. Click a desk to pick it: only a desk you picked can switch herdr."
	_eq(_footer(facts), ["Following herdr's focus", following], "5: a pane nobody picked")
	facts.pick = OfficePaneInspector.Pick.REPLACED
	var replaced := "Another terminal has taken this pane's id since you picked it. Click the desk to pick it again."
	_eq(_footer(facts), ["New terminal: pick again", replaced], "6: a pick another terminal took")
	facts.pick = OfficePaneInspector.Pick.PICKED
	_eq(
		_footer(facts),
		["No answer: busy", "The answer controls are off: " + CommandRefusal.detail(CommandRefusal.Reason.AGENT_BUSY)],
		"7: answer mode's own word"
	)
	facts.answering = false
	var look := "a write to this pane just ended. Wait for the preview to read the terminal again, then look."
	_eq(
		_footer(facts), ["No writes: look first", "The switch and the answers are off: " + look], "8: every write waits"
	)
	facts.switch_refusal = CommandRefusal.Reason.MACHINE_OFFLINE
	_eq(_footer(facts), ["No switch: offline", "The switch is off: the machine is offline."], "9: the switch is off")
	facts.switch_refusal = CommandRefusal.Reason.NONE
	_eq(_footer(facts), ["", ""], "and with nothing to say, nothing")


## An input command in flight is said by what it is and how far it got: an
## answer or a start is checking the screen until its first byte goes; a split,
## a close, a space and a worktree read no screen.
func test_an_input_in_flight_is_said_by_its_kind_and_stage() -> void:
	var pane := _agent()
	var start := "The start is on its way: the card reads the terminal again first, then herdr types the command."
	var table := [
		[CommandContext.Kind.KEYS, CommandTicket.State.UNSENT, "Checking the screen…", ANSWER_ON_ITS_WAY],
		[CommandContext.Kind.KEYS, CommandTicket.State.SENT, "Sending…", ANSWER_ON_ITS_WAY],
		[CommandContext.Kind.LINE, CommandTicket.State.UNSENT, "Checking the screen…", ANSWER_ON_ITS_WAY],
		[CommandContext.Kind.LINE, CommandTicket.State.SENT, "Sending…", ANSWER_ON_ITS_WAY],
		[CommandContext.Kind.START, CommandTicket.State.UNSENT, "Checking the screen…", start],
		[CommandContext.Kind.START, CommandTicket.State.SENT, "Sending…", start],
		[CommandContext.Kind.SPLIT, CommandTicket.State.UNSENT, "Splitting…", "The split is on its way to herdr."],
		[CommandContext.Kind.SPLIT, CommandTicket.State.SENT, "Splitting…", "The split is on its way to herdr."],
		[CommandContext.Kind.CLOSE, CommandTicket.State.SENT, "Closing…", "The close is on its way to herdr."],
		[
			CommandContext.Kind.SPACE,
			CommandTicket.State.SENT,
			"Making the space…",
			"The new space is on its way to herdr."
		],
		[
			CommandContext.Kind.WORKTREE,
			CommandTicket.State.SENT,
			"Making the worktree…",
			"The new worktree is on its way to herdr; git runs there first."
		],
	]
	for row: Array in table:
		var kind: CommandContext.Kind = row[0]
		var state: CommandTicket.State = row[1]
		var facts := _facts(pane)
		facts.input = _ticket(pane, kind, state)
		# Whatever was said before waits behind it.
		facts.outcome = "Sent"
		facts.launch_line = "claude-2 started"
		_eq(
			_footer(facts),
			[row[2], row[3]],
			"%s %s" % [CommandContext.Kind.find_key(kind), CommandTicket.state_name(state)]
		)
		_check(CardPicture.actions_of(facts).focus_off, "and the switch waits")


## What became of a write, as the card keeps it (CardWords) and the footer
## says it: sent, switched, refused by this office, refused by herdr, never
## sent, and sent with no answer back.
func test_what_became_of_a_write_is_said_as_it_ended() -> void:
	var pane := _agent()
	var rejected := _ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.REJECTED)
	rejected.error_code = "boom"
	rejected.error_message = "it broke"
	var typed := _ticket(pane, CommandContext.Kind.LINE, CommandTicket.State.REJECTED)
	typed.rejection = CommandRejection.Code.AGENT_BLOCKED
	typed.error_code = "agent_blocked"
	typed.error_message = "agent is blocked"
	var look := "a write to this pane just ended. Wait for the preview to read the terminal again, then look."
	var table := [
		[
			_ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.ACCEPTED),
			"Sent",
			"herdr accepted the keystrokes; not whether the agent acted."
		],
		[
			_ticket(pane, CommandContext.Kind.LINE, CommandTicket.State.ACCEPTED),
			"Sent",
			"herdr typed the line and Enter; not whether the agent acted."
		],
		[
			_ticket(pane, CommandContext.Kind.FOCUS, CommandTicket.State.ACCEPTED),
			"herdr switched here",
			"herdr switched its shared view to this pane, and this tab's UNREAD is cleared."
		],
		[
			_ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.REFUSED),
			"Not sent: look first",
			"Nothing was sent: " + look
		],
		[rejected, "herdr refused (boom)", "herdr refused the answer: it broke (boom)."],
		[
			typed,
			"herdr refused: " + CommandRejection.text(CommandRejection.Code.AGENT_BLOCKED),
			(
				"herdr refused the answer: %s (agent_blocked: agent is blocked)."
				% CommandRejection.detail(CommandRejection.Code.AGENT_BLOCKED).trim_suffix(".")
			)
		],
		[
			_ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.CANCELLED),
			"Not sent: unreachable",
			"Nothing was sent: herdr's socket could not be reached, or the machine went first."
		],
		[
			_ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.UNKNOWN),
			"Unknown result: look first",
			(
				"The answer went out but no usable answer came back (timed out): herdr may have acted on it."
				+ " Look at the terminal before writing again; nothing is retried."
			)
		],
	]
	for row: Array in table:
		var ticket: CommandTicket = row[0]
		var facts := _facts(pane)
		facts.outcome = CardWords.write_outcome(ticket)
		facts.outcome_detail = CardWords.write_outcome_detail(ticket)
		facts.outcome_identity = ticket.context.identity_key
		var name := (
			"%s %s" % [CommandContext.Kind.find_key(ticket.context.kind), CommandTicket.state_name(ticket.state)]
		)
		_eq(_footer(facts), [row[1], row[2]], name)
	# The card's own words for a press that never reached the fleet.
	_eq(CardWords.TARGET_CHANGED, "Not sent: target changed", "a press whose card moved on")
	_eq(
		[CardWords.HELD_DETAIL, CardWords.SWITCH_MOVED_DETAIL],
		[
			"Nothing was sent: the card moved to another pane or terminal while an answer button was held.",
			"Nothing was sent: the card moved to another pane or terminal between your press and release."
		],
		"in full, for a held answer button and for the switch"
	)
	_eq(
		[
			CardWords.not_sent(CommandRefusal.Reason.LINE_COMPOSING),
			CardWords.not_sent_detail(CommandRefusal.Reason.LINE_COMPOSING)
		],
		[
			"Not sent: still composing",
			"Nothing was sent: an input method is still composing in the reply box. Finish it, then press Send line."
		],
		"and a line the card itself refused"
	)


## An outcome kept for another terminal than the pane holds now is never said
## as this one's: the footer goes on to what is true of this terminal.
func test_another_terminals_outcome_is_never_said() -> void:
	var pane := _agent()
	var facts := _facts(pane)
	facts.outcome = "Sent"
	facts.outcome_detail = "herdr accepted the keystrokes; not whether the agent acted."
	facts.outcome_identity = pane.identity_key()
	facts.switch_refusal = CommandRefusal.Reason.LOOK_FIRST
	_eq(_footer(facts)[0], "Sent", "this terminal's outcome is said")
	pane.terminal_id = "term-2"
	_eq(_footer(facts)[0], "No writes: look first", "another terminal's is not: the look it owes is")
	facts.outcome_identity = ""
	_eq(_footer(facts)[0], "Sent", "the card's own words belong to no terminal and are said")
	_eq(
		[
			CardPicture.foreign("", pane),
			CardPicture.foreign("x", null),
			CardPicture.foreign(pane.identity_key(), pane),
			CardPicture.foreign("x", pane)
		],
		[false, false, false, true],
		"foreign: only another terminal's, on a pane shown"
	)


## How the pane's start is going is the launch line the card is told
## (LaunchWatch's words, on the clock given); the footer says it whole, and
## with none it goes on.
func test_how_a_start_goes_is_said_until_something_else_is() -> void:
	var watch := LaunchWatch.new()
	watch.name = "claude-2"
	watch.started_msec = 9000
	var table: Dictionary[LaunchWatch.Outcome, String] = {
		LaunchWatch.Outcome.PENDING: "Starting claude-2 · 4s",
		LaunchWatch.Outcome.READY: "claude-2 started",
		LaunchWatch.Outcome.BLOCKED_AT_START: "claude-2 asks: answer with the keys",
		LaunchWatch.Outcome.NOT_DETECTED: "claude-2 not detected after 31s: look at the terminal",
		LaunchWatch.Outcome.REPLACED: "Terminal changed",
		LaunchWatch.Outcome.GONE: "Pane gone",
		LaunchWatch.Outcome.FAILED: "claude-2 did not start: look at the terminal",
		LaunchWatch.Outcome.UNKNOWN: "claude-2: no answer from herdr",
		LaunchWatch.Outcome.NOT_CHECKED: "claude-2 not checked: the connection changed",
	}
	for outcome: LaunchWatch.Outcome in table:
		var facts := _facts(_agent("idle", ""))
		facts.launch_line = LaunchWatch.text(outcome, watch, facts.now_msec)
		facts.launch_detail = "%s: %s" % [facts.launch_line, LaunchWatch.detail(outcome)]
		_eq(
			_footer(facts),
			[table[outcome], "%s: %s" % [table[outcome], LaunchWatch.detail(outcome)]],
			LaunchWatch.name_of(outcome)
		)
	# A start that is over and looked at, on a later card: the card is told nothing.
	var later := _facts(_agent("idle"))
	_eq(_footer(later), ["", ""], "no launch line: nothing of it is said")
	later.pick = OfficePaneInspector.Pick.FOLLOWING
	_eq(_footer(later)[0], "Following herdr's focus", "and the next arm speaks")


## In answer mode the launch line is said while the mode has no word of its
## own; once it has one (nothing pressable, or a line that cannot go) that
## word wins. An answer mode with nothing to say leaves the footer empty: it
## never falls through to why the switch is off.
func test_answer_mode_speaks_over_the_launch_line_and_never_for_the_switch() -> void:
	var facts := _facts(_agent("blocked"))
	facts.answering = true
	facts.launch_line = "claude-2 asks: answer with the keys"
	facts.launch_detail = "claude-2 asks: answer with the keys: the agent is still launching."
	_eq(_footer(facts)[0], "claude-2 asks: answer with the keys", "something may be pressed: the launch line")
	facts.keys_refusal = CommandRefusal.Reason.UNSEEN
	facts.line_refusal = CommandRefusal.Reason.AGENT_BUSY
	var unseen := "no uncut terminal text of this pane was on the card when you pressed. Look at it first."
	_eq(
		_footer(facts),
		["No answer: look first", "The answer controls are off: " + unseen],
		"nothing pressable: a blocked agent's keys say why"
	)
	facts.pane.state = "idle"
	_eq(_footer(facts)[0], "No answer: busy", "any other agent's line says why")
	facts.keys_refusal = CommandRefusal.Reason.NONE
	facts.reply = "x".repeat(2000)
	facts.reply_refusal = CommandRefusal.Reason.LINE_TOO_LONG
	_eq(
		_footer(facts),
		[
			"Line: over 1024 bytes",
			"This line cannot be sent: the line is longer than 1024 bytes of UTF-8. Nothing is cut to make it fit."
		],
		"a typed line that cannot go says why, over the launch line"
	)
	facts.launch_line = ""
	facts.reply = ""
	facts.reply_refusal = CommandRefusal.Reason.LINE_BLANK
	facts.switch_refusal = CommandRefusal.Reason.LOOK_FIRST
	_eq(_footer(facts), ["", ""], "an empty box is no word; and the switch's reason is not answer mode's")
	facts.answering = false
	_eq(_footer(facts)[0], "No writes: look first", "out of answer mode it is said")


## A write that waits is every write's wait (another one out, a look owed);
## anything else that stops the switch is only the switch's.
func test_a_wait_is_every_writes_and_the_rest_is_the_switchs() -> void:
	var facts := _facts()
	facts.switch_refusal = CommandRefusal.Reason.IN_FLIGHT
	_eq(
		_footer(facts),
		[
			"No writes: in flight",
			"The switch and the answers are off: the last write to this pane is still on its way."
		],
		"in flight"
	)
	facts.switch_refusal = CommandRefusal.Reason.IDENTITY_CHANGED
	_eq(
		_footer(facts),
		["No switch: new terminal", "The switch is off: another terminal, agent or session has this pane id now."],
		"a reason of the switch's own"
	)
	_check(CardPicture.actions_of(facts).focus_off, "and the switch is off")


# --- the switch, Monitor, fold: who is offered what ---------------------------------


## The switch names the machine it switches when there are several, and may
## be pressed only on a picked pane, with nothing of this card in flight and
## nothing against it.
func test_the_switch_names_its_machine_and_waits_for_a_pick() -> void:
	var facts := _facts()
	var actions := CardPicture.actions_of(facts)
	_eq([actions.focus_text, actions.focus_tip], ["Switch herdr here", SWITCH_TIP], "one machine")
	_eq([actions.offered, actions.focus, actions.focus_off], [true, true, false], "picked and free: on")
	_eq([actions.monitor, actions.fold, actions.top], [true, true, true], "Monitor and the fold with it")
	facts.machine = "bee"
	actions = CardPicture.actions_of(facts)
	_eq(
		[actions.focus_text, actions.focus_tip],
		[
			"Switch herdr on bee",
			(
				"Switches the shared view of herdr on bee to this pane: every terminal attached to it follows."
				+ "\nIt also clears UNREAD for every pane on this tab, not just this one."
			)
		],
		"several machines"
	)
	for pick: OfficePaneInspector.Pick in [OfficePaneInspector.Pick.FOLLOWING, OfficePaneInspector.Pick.REPLACED]:
		facts.pick = pick
		_check(CardPicture.actions_of(facts).focus_off, "off for a pane that is not the viewer's pick")
	facts.pick = OfficePaneInspector.Pick.PICKED
	facts.switching = true
	_check(CardPicture.actions_of(facts).focus_off, "off while the switch is out")
	facts.switching = false
	facts.switch_refusal = CommandRefusal.Reason.LOOK_FIRST
	_check(CardPicture.actions_of(facts).focus_off, "off while a look is owed")
	facts.switch_refusal = CommandRefusal.Reason.NONE
	facts.answering = true
	actions = CardPicture.actions_of(facts)
	_eq([actions.focus, actions.fold, actions.top], [false, false, true], "answer mode trades the switch and the fold")


## No pane, no fleet, a read-only office: nothing to write with. No pane shows
## the empty state and no button; no fleet shows the pane and no Monitor;
## read-only shows Monitor (view-only) and neither the switch nor a footer.
func test_no_pane_no_fleet_and_read_only_offer_no_write() -> void:
	var none := _facts(null)
	none.preview = OfficePaneInspector.PreviewState.NONE
	none.answer_possible = false
	var actions := CardPicture.actions_of(none)
	_eq(
		[actions.offered, actions.focus, actions.focus_off, actions.monitor, actions.fold, actions.top],
		[false, false, true, false, false, false],
		"no pane: nothing"
	)
	_eq([actions.footer, actions.footer_tip], ["", ""], "and no footer")
	var stack := CardPicture.stack_of(none)
	_eq([stack.empty, stack.detail, stack.line, stack.message], [true, false, false, "This session has no panes."], "")
	none.dimmed = true
	_eq(CardPicture.stack_of(none).message, "Waiting for herdr.", "no pane on a machine that dropped")
	_eq(CardPicture.of(none).header, null, "no header to write")
	_check(not CardPicture.answer_of(none).chip, "no answer chip")
	var showroom := _facts()
	showroom.connected = false
	showroom.answer_possible = false
	showroom.switch_refusal = CommandRefusal.Reason.NOT_CONNECTED
	showroom.preview = OfficePaneInspector.PreviewState.UNAVAILABLE
	showroom.preview_reason = CommandRefusal.Reason.NOT_CONNECTED
	actions = CardPicture.actions_of(showroom)
	_eq(
		[actions.offered, actions.focus, actions.focus_off, actions.monitor, actions.fold, actions.top],
		[false, false, true, false, true, true],
		"no fleet: the pane and the fold, nothing that reads or writes"
	)
	_eq(_footer(showroom), ["", ""], "no footer")
	var caption := CardPicture.preview_of(showroom)
	_eq(
		[caption.caption, caption.caption_tip],
		["No preview: no herdr", "No terminal preview: nothing here is connected to herdr."],
		"and the preview says why"
	)
	var watching := _facts()
	watching.read_only = true
	watching.answer_possible = false
	watching.switch_refusal = CommandRefusal.Reason.READ_ONLY
	watching.outcome = "Sent"
	watching.launch_line = "claude-2 started"
	actions = CardPicture.actions_of(watching)
	_eq(
		[actions.offered, actions.focus, actions.focus_off, actions.monitor, actions.fold, actions.top],
		[false, false, true, true, true, true],
		"read-only: Monitor opens view-only; no switch"
	)
	_eq(_footer(watching), ["", ""], "and no footer, whatever the card remembers")
	watching.preview = OfficePaneInspector.PreviewState.UNAVAILABLE
	watching.preview_reason = CommandRefusal.Reason.READ_ONLY
	caption = CardPicture.preview_of(watching)
	_eq(
		[caption.caption, caption.caption_tip],
		[
			"No preview: read-only",
			"No terminal preview: this office was started read-only and sends herdr nothing but reads of its state."
		],
		"its preview says it is read-only"
	)


# --- the panel's forms ------------------------------------------------------------


## At full height the pane's details show under the heading, NEXT reads down
## with its wait, and the PANE list has its room.
func test_the_full_panel_shows_the_details_under_the_heading() -> void:
	var facts := _facts()
	var stack := CardPicture.stack_of(facts)
	_eq([stack.carded, stack.detail, stack.line, stack.title, stack.empty], [false, true, false, true, false], "")
	_eq([stack.full, stack.next_wait], [true, true], "NEXT reads down, with its wait")
	_eq([stack.monitor_word, stack.open_word], ["Monitor", "Open"], "the line's words, for when it folds")
	_check(CardPicture.more_of(facts), "the PANE list shows")
	var answer := CardPicture.answer_of(facts)
	_eq([answer.title, answer.title_text, answer.title_tip], [true, "AGENT", ""], "the heading")


## Folded to its line: the compact row and nothing of the details; on a
## narrow screen the long words go and NEXT's wait with them.
func test_the_line_keeps_the_row_and_drops_its_long_words_when_narrow() -> void:
	var facts := _facts()
	facts.compact = true
	var stack := CardPicture.stack_of(facts)
	_eq(
		[stack.carded, stack.detail, stack.line, stack.title, stack.full], [false, false, true, true, false], "the line"
	)
	_eq([stack.monitor_word, stack.open_word, stack.next_wait], ["Monitor", "Open", true], "wide: the words")
	facts.wide = false
	stack = CardPicture.stack_of(facts)
	_eq([stack.monitor_word, stack.open_word, stack.next_wait], ["", "", false], "narrow: icons, and no wait")
	facts.compact = false
	stack = CardPicture.stack_of(facts)
	_eq([stack.monitor_word, stack.next_wait], ["", true], "at full height NEXT's wait always has room")


## The card form: the compact panel on a tall screen. The header shows over
## the line's buttons, with no heading and no PANE list.
func test_the_card_form_shows_the_header_over_the_lines_buttons() -> void:
	var facts := _facts()
	facts.compact = true
	facts.card = true
	var stack := CardPicture.stack_of(facts)
	_eq([stack.carded, stack.detail, stack.line, stack.title, stack.full], [true, true, true, false, false], "")
	_check(not CardPicture.more_of(facts), "no PANE list in the card")
	_check(not CardPicture.answer_of(facts).title, "and no heading: the header says who")
	facts.compact = false
	_check(not CardPicture.stack_of(facts).carded, "a card only while compact")
	_check(CardPicture.answer_of(facts).title, "the heading is back at full height")


## Answer mode turns the card: its controls open, the chip closes it, the
## heading names who is answered, and the switch, the fold and the PANE list go.
func test_answer_mode_opens_its_controls_and_names_who_is_answered() -> void:
	var facts := _facts()
	var answer := CardPicture.answer_of(facts)
	_eq(
		[answer.chip, answer.chip_text, answer.chip_keyed, answer.open],
		[true, "Answer", true, false],
		"out of it: the chip opens it, with the Enter hint"
	)
	_eq(
		answer.chip_tip,
		"Enter: answer this agent. Opens the answer keys and the reply box; nothing is sent until you press one.",
		""
	)
	facts.answer_possible = false
	_check(not CardPicture.answer_of(facts).chip, "nothing to press: no chip")
	facts.answering = true
	answer = CardPicture.answer_of(facts)
	_eq(
		[answer.chip, answer.chip_text, answer.chip_keyed, answer.open, answer.chip_tip],
		[true, "Close", false, true, "Esc: leave answer mode. Nothing is sent."],
		"in it: the chip closes it, whatever may be pressed"
	)
	_eq(
		[answer.title, answer.title_text, answer.title_tip],
		[false, "CLAUDE · BLOCKED", "Answering: CLAUDE · BLOCKED"],
		"who is answered"
	)
	facts.machine = "bee"
	answer = CardPicture.answer_of(facts)
	_eq(
		[answer.title_text, answer.title_tip],
		["CLAUDE · BLOCKED · bee", "Answering: CLAUDE · BLOCKED · bee"],
		"and on which machine"
	)
	_check(not CardPicture.stack_of(facts).title, "the stack hides the heading too")
	_check(not CardPicture.more_of(facts), "and the PANE list gives its room")
	_eq(answer.best_effort, "Checks the screen first; it can still change", "the line under the reply box")


## The PANE list gives the launch block its room only on a narrow card.
func test_the_pane_list_gives_way_to_the_launch_block_on_a_narrow_card() -> void:
	var table := [
		# launch shown, narrow, answering, compact, card -> the list shows
		[false, false, false, false, false, true],
		[true, false, false, false, false, true],
		[false, true, false, false, false, true],
		[true, true, false, false, false, false],
		[false, false, true, false, false, false],
		[false, false, false, true, true, false],
		[false, false, false, true, false, true],
		[false, false, false, false, true, true],
	]
	for row: Array in table:
		var facts := _facts()
		facts.launch_shown = row[0]
		facts.narrow = row[1]
		facts.answering = row[2]
		facts.compact = row[3]
		facts.card = row[4]
		_eq(CardPicture.more_of(facts), row[5], str(row.slice(0, 5)))
		_eq(CardPicture.of(facts).more, row[5], "the whole picture says the same")


# --- answer mode's keys and line ---------------------------------------------------


## Each key button says what it sends and where, and why it is off.
func test_each_key_says_what_it_sends_and_why_it_is_off() -> void:
	var facts := _facts()
	var answer := CardPicture.answer_of(facts)
	_check(not answer.keys_off, "the keys are on")
	_eq(
		[answer.key_tip("1"), answer.key_tip("y"), answer.key_tip("n"), answer.key_tip("enter"), answer.key_tip("esc")],
		[
			"Sends 1. Key 1 in answer mode does the same, where your keyboard types 1 there without Shift.",
			"Sends y. Key y in answer mode does the same, where your keyboard types y there without Shift.",
			"Sends n. Only by click: the N key goes to the next agent.",
			"Sends Enter: it confirms whatever the question has selected. Only by click.",
			"Sends Escape to the terminal. The Esc key on your keyboard never does.",
		],
		"one machine"
	)
	facts.machine = "bee"
	facts.keys_refusal = CommandRefusal.Reason.LOOK_FIRST
	answer = CardPicture.answer_of(facts)
	_check(answer.keys_off, "off while a look is owed")
	var off := "\nOff: a write to this pane just ended. Wait for the preview to read the terminal again, then look."
	_eq(
		[answer.key_tip("2"), answer.key_tip("n"), answer.key_tip("enter"), answer.key_tip("esc")],
		[
			(
				"Sends 2 on bee. Key 2 in answer mode does the same, where your keyboard types 2 there without Shift."
				+ off
			),
			"Sends n on bee. Only by click: the N key goes to the next agent." + off,
			"Sends Enter on bee: it confirms whatever the question has selected. Only by click." + off,
			"Sends Escape to the terminal on bee. The Esc key on your keyboard never does." + off,
		],
		"on a named machine, off, saying why"
	)


## "Send line" counts the reply's bytes against herdr's cap, and is off for
## what refuses a line to this pane first, else for what refuses this text.
func test_send_line_counts_its_bytes_and_says_why_it_is_off() -> void:
	var facts := _facts()
	facts.reply = "héllo"
	var answer := CardPicture.answer_of(facts)
	var words := "Send one line to this agent: herdr types it and presses Enter (bracketed when the agent asked). "
	_eq([answer.line_off, answer.line_tip], [false, words + "6 of 1024 bytes."], "bytes, not characters")
	facts.reply = ""
	facts.reply_refusal = CommandRefusal.Reason.LINE_BLANK
	answer = CardPicture.answer_of(facts)
	_eq(
		[answer.line_off, answer.line_tip],
		[true, words + "0 of 1024 bytes.\nOff: the line is empty or only spaces."],
		"an empty box"
	)
	facts.line_refusal = CommandRefusal.Reason.AGENT_BUSY
	facts.machine = "bee"
	answer = CardPicture.answer_of(facts)
	_eq(
		answer.line_tip,
		(
			"Send one line to this agent on bee: herdr types it and presses Enter (bracketed when the agent asked)."
			+ " 0 of 1024 bytes.\nOff: "
			+ CommandRefusal.detail(CommandRefusal.Reason.AGENT_BUSY)
		),
		"the pane's own refusal comes before the text's"
	)
	_eq(
		[
			CardPicture.send_refusal(CommandRefusal.Reason.NONE, CommandRefusal.Reason.NONE),
			CardPicture.send_refusal(CommandRefusal.Reason.NONE, CommandRefusal.Reason.LINE_BLANK),
			CardPicture.send_refusal(CommandRefusal.Reason.AGENT_BUSY, CommandRefusal.Reason.NONE),
			CardPicture.send_refusal(CommandRefusal.Reason.AGENT_BUSY, CommandRefusal.Reason.LINE_BLANK),
		],
		[
			CommandRefusal.Reason.NONE,
			CommandRefusal.Reason.LINE_BLANK,
			CommandRefusal.Reason.AGENT_BUSY,
			CommandRefusal.Reason.AGENT_BUSY
		],
		"send_refusal: the line's, else the text's"
	)


# --- the preview ---------------------------------------------------------------------


## A preview that shows no text says why in its caption, and its rows are
## blank whatever text the card still remembers.
func test_a_preview_without_text_says_why() -> void:
	var pane := _agent()
	var refused := _ticket(pane, CommandContext.Kind.READ, CommandTicket.State.REJECTED)
	refused.error_code = "pane_not_found"
	refused.error_message = "no such pane"
	var table := [
		[OfficePaneInspector.PreviewState.NONE, null, "", ""],
		[OfficePaneInspector.PreviewState.LOADING, null, "Reading…", "Reading this pane's terminal from herdr."],
		[
			OfficePaneInspector.PreviewState.FAILED,
			null,
			"Read failed: no answer",
			"The last read brought no text back: no usable answer."
		],
		[
			OfficePaneInspector.PreviewState.FAILED,
			refused,
			"Read failed: herdr refused",
			"The last read brought no text back: herdr refused it (pane_not_found: no such pane)."
		],
		[
			OfficePaneInspector.PreviewState.FAILED,
			_ticket(pane, CommandContext.Kind.READ, CommandTicket.State.CANCELLED),
			"Read failed: not sent",
			"The last read brought no text back: it was never sent (timed out)."
		],
		[
			OfficePaneInspector.PreviewState.FAILED,
			_ticket(pane, CommandContext.Kind.READ, CommandTicket.State.UNKNOWN),
			"Read failed: no answer",
			"The last read brought no text back: no usable answer (timed out)."
		],
	]
	for row: Array in table:
		var facts := _facts(pane)
		facts.preview = row[0]
		facts.preview_failed = row[1]
		var preview := CardPicture.preview_of(facts)
		_eq([preview.caption, preview.caption_tip], [row[2], row[3]], str(row[2]))
		_eq(preview.rows, "\n".repeat(11), "twelve blank rows")
		_eq(preview.seconds, -1, "and no age")
	var offline := _facts(pane)
	offline.preview = OfficePaneInspector.PreviewState.UNAVAILABLE
	offline.preview_reason = CommandRefusal.Reason.MACHINE_OFFLINE
	var stale := CardPicture.preview_of(offline)
	_eq(
		[stale.caption, stale.caption_tip, stale.rows],
		["No preview: offline", "No terminal preview: the machine is offline.", "\n".repeat(11)],
		"a machine that dropped: its text is not live, and is not shown"
	)


## Shown text is captioned by where it was read from and how long ago, on the
## clock the picture is given: seconds, then minutes, then hours.
func test_shown_text_is_captioned_by_its_source_and_its_age_on_the_clock_given() -> void:
	var facts := _facts(_agent("working"))
	facts.source = CommandContext.SOURCE_RECENT
	facts.text = "$ make\nok\n"
	var ages := [[10000, "0s", 0], [13999, "3s", 3], [14000, "4s", 4], [135000, "2m", 125], [7300000, "2h", 7290]]
	for row: Array in ages:
		var now: int = row[0]
		facts.now_msec = now
		var preview := CardPicture.preview_of(facts)
		_eq(
			[preview.caption, preview.caption_tip, preview.seconds],
			[
				"recent · %s ago" % row[1],
				"The last 12 lines of herdr's recent_unwrapped source, read %s ago." % row[1],
				row[2]
			],
			"recent, %d ms on" % (now - 10000)
		)
	_eq(
		[CardPicture.age_seconds(10000, 10999), CardPicture.age_seconds(10000, 11000)],
		[0, 1],
		"whole seconds: the caption moves when one is full"
	)
	facts.source = CommandContext.SOURCE_DETECTION
	facts.now_msec = 13000
	facts.text = QUESTION
	var question := CardPicture.preview_of(facts)
	var detection := "rows of herdr's detection source (what its agent detection reads), read 3s ago."
	_eq(
		[question.caption, question.caption_tip],
		["3 of 3 rows · 3s ago", "The last 3 of the 3 " + detection],
		"a question leads with how many of its rows show"
	)
	facts.text = "Allow?\n"
	_eq(CardPicture.preview_of(facts).caption, "1 of 1 row · 3s ago", "one row is a row")
	facts.text = "row\n".repeat(30)
	question = CardPicture.preview_of(facts)
	_eq(
		[question.caption, question.caption_tip],
		["12 of 30 rows · 3s ago", "The last 12 of the 30 " + detection],
		"a long question: the last twelve of them"
	)


## Text that was cut says so before rows that are merely clipped by the
## card's width; the tooltip says both. A question's caption gives its age up
## for either.
func test_cut_comes_before_clipped_in_the_caption() -> void:
	var clipped := " 2 of them wider than the card and clipped: look at herdr for the rest."
	var cut := " Cut: only the end of it is shown."
	var recent := "The last 12 lines of herdr's recent_unwrapped source, read 3s ago."
	var detection := "The last 3 of the 3 rows of herdr's detection source (what its agent detection reads), read 3s ago."
	var table := [
		# source, cut, rows clipped -> caption, tooltip
		[CommandContext.SOURCE_RECENT, false, 0, "recent · 3s ago", recent],
		[CommandContext.SOURCE_RECENT, false, 2, "recent · 3s ago · clipped", recent + clipped],
		[CommandContext.SOURCE_RECENT, true, 0, "recent · 3s ago · cut", recent + cut],
		[CommandContext.SOURCE_RECENT, true, 2, "recent · 3s ago · cut", recent + clipped + cut],
		[CommandContext.SOURCE_DETECTION, false, 0, "3 of 3 rows · 3s ago", detection],
		[CommandContext.SOURCE_DETECTION, false, 2, "3 of 3 rows · clipped", detection + clipped],
		[CommandContext.SOURCE_DETECTION, true, 0, "3 of 3 rows · cut", detection + cut],
		[CommandContext.SOURCE_DETECTION, true, 2, "3 of 3 rows · cut", detection + clipped + cut],
	]
	for row: Array in table:
		var facts := _facts()
		facts.source = row[0]
		facts.cut = row[1]
		facts.rows_clipped = row[2]
		var preview := CardPicture.preview_of(facts)
		_eq([preview.caption, preview.caption_tip], [row[3], row[4]], str(row.slice(0, 3)))


## The preview is always twelve rows: the last of the text, padded at the top,
## tabs expanded to columns of eight, the newline that ends herdr's text no row.
func test_the_preview_is_the_last_twelve_rows_padded_at_the_top() -> void:
	var facts := _facts()
	facts.text = "a\n\tb\nab\tc\n"
	_eq(CardPicture.preview_of(facts).rows, "\n".repeat(9) + "a\n        b\nab      c", "three rows under nine blank")
	var rows := PackedStringArray()
	for index in 30:
		rows.append("row %d" % index)
	facts.text = "\n".join(rows) + "\n"
	_eq(CardPicture.preview_of(facts).rows, "\n".join(rows.slice(18)), "the last twelve of thirty")
	facts.text = ""
	_eq(CardPicture.preview_of(facts).rows, "\n".repeat(11), "no text: twelve blank rows")
	facts.text = "x".repeat(500) + "\n"
	_eq(
		CardPicture.preview_of(facts).rows.length(),
		11 + CardWords.ROW_CHARS,
		"a row past 240 characters is not shaped beyond them"
	)


# --- NEXT --------------------------------------------------------------------------


## NEXT says what a press does and to whom; an office that cannot write has no
## verb and says herdr's state instead, with a tooltip that promises less.
func test_next_says_what_a_press_does_and_to_whom() -> void:
	var facts := _facts()
	facts.next = NextModel.of(_agent("blocked"), "", true)
	var pill := CardPicture.next_of(facts)
	_eq(
		[pill.somebody, pill.title, pill.line, pill.muted, pill.tip],
		[true, true, "Answer CLAUDE web", false, NEXT_TIP],
		"a blocked agent is answered"
	)
	facts.next = NextModel.of(_agent("done", "codex"), "bee", true)
	_eq(CardPicture.next_of(facts).line, "Read CODEX web @ bee", "a done one is read; several machines name theirs")
	facts.next = NextModel.of(_agent("blocked"), "", false)
	pill = CardPicture.next_of(facts)
	_eq(
		[pill.line, pill.tip],
		["CLAUDE web · blocked", OfficePaneInspector.NEXT_PICKS_TIP],
		"read-only: whom and herdr's state, and it only picks"
	)
	facts.next = NextModel.of(_agent("blocked", ""), "", false)
	_eq(CardPicture.next_of(facts).line, "SHELL web · blocked", "a pane with no agent is a shell")


## On the folded line NEXT's tooltip adds the whole sentence; a narrow line
## has room for whom alone, without `NEXT:` before it.
func test_next_on_the_line_says_whom_alone_when_narrow() -> void:
	var facts := _facts()
	facts.next = NextModel.of(_agent("blocked"), "bee", true)
	facts.compact = true
	var pill := CardPicture.next_of(facts)
	_eq(
		[pill.title, pill.line, pill.tip],
		[true, "Answer CLAUDE web @ bee", NEXT_TIP + "\nNext: Answer CLAUDE web @ bee"],
		"a wide line: the whole sentence, and again in the tooltip"
	)
	facts.wide = false
	pill = CardPicture.next_of(facts)
	_eq(
		[pill.title, pill.line, pill.tip],
		[false, "CLAUDE web", NEXT_TIP + "\nNext: Answer CLAUDE web @ bee"],
		"a narrow line: whom alone; the tooltip still says it all"
	)
	facts.compact = false
	pill = CardPicture.next_of(facts)
	_eq([pill.title, pill.line, pill.tip], [true, "Answer CLAUDE web @ bee", NEXT_TIP], "full height is never short")


## Nobody next: `All clear`, muted, in every form, and the button is off.
func test_nobody_next_is_all_clear_in_every_form() -> void:
	for form: Array in [[false, true], [true, true], [true, false]]:
		var facts := _facts()
		facts.compact = form[0]
		facts.wide = form[1]
		var pill := CardPicture.next_of(facts)
		_eq(
			[pill.somebody, pill.title, pill.line, pill.muted, pill.tip],
			[false, true, "All clear", true, NEXT_TIP],
			"compact %s, wide %s" % form
		)


# --- the header ---------------------------------------------------------------------


## The header says who, in what state (the pack's word for it, in the state's
## pill) and where; the compact line says the same three in the same words.
func test_the_header_says_who_in_what_state_and_where() -> void:
	var pane := _agent("blocked")
	var facts := _facts(pane)
	var header := CardPicture.header_of(facts)
	_eq(
		[header.provider, header.caption, header.pill, header.caption_look, header.caption_tip],
		["CLAUDE", "BLOCKED", &"StatePillBlocked", &"LabelInk", "Not launching"],
		"who and in what state"
	)
	_eq([header.seat, header.machine_shown, header.machine], ["web / main", false, "@ "], "where, on one machine")
	_eq([header.pane_id, header.pane_id_tip], ["w1:p1", "Pane: w1:p1\nTerminal: term-1"], "the pane and its terminal")
	_eq([header.cwd, header.cwd_tip], ["repo", "Working directory: /home/u/repo"], "its directory, by its last name")
	_eq(
		[header.person, header.person_provider, header.person_state, header.starting, header.dimmed, header.key],
		[true, "claude", &"blocked", false, false, pane.key],
		"the portrait: the person at that seat"
	)
	_eq(header.badge, &"blocked", "under the state's own badge")
	_eq(
		[header.summary, header.summary_tip],
		["CLAUDE · BLOCKED · web / main", "CLAUDE · BLOCKED · web / main"],
		"the line"
	)
	facts.machine = "bee"
	header = CardPicture.header_of(facts)
	_eq([header.machine_shown, header.machine], [true, "@ bee"], "several machines: which one")
	_eq(header.summary_tip, "CLAUDE · BLOCKED · web / main @ bee", "and the line's tooltip names it")
	pane.starting_known = false
	_eq(CardPicture.header_of(facts).caption_tip, "Launch status not reported", "herdr said nothing of a launch")
	var pills: Dictionary[String, StringName] = {
		"working": &"StatePillWorking",
		"blocked": &"StatePillBlocked",
		"done": &"StatePillDone",
		"idle": &"StatePillIdle",
		"unknown": &"StatePillQuiet",
	}
	for state: String in pills:
		var shown := CardPicture.header_of(_facts(_agent(state)))
		var look := &"LabelPaper" if state == "unknown" else &"LabelInk"
		_eq([shown.caption, shown.pill, shown.caption_look], [state.to_upper(), pills[state], look], state)


## A shell, a start and a dropped machine are quiet: no state colour, and
## their own words. A shell has no person at all; a start is named as herdr
## named it until its kind shows; done explains UNREAD.
func test_a_shell_a_start_and_a_dropped_machine_are_quiet() -> void:
	var shell := CardPicture.header_of(_facts(_agent("idle", "")))
	_eq(
		[shell.provider, shell.caption, shell.pill, shell.caption_look, shell.caption_tip],
		["SHELL", "no agent", &"StatePillQuiet", &"LabelPaper", "herdr reports no agent in this pane: a shell."],
		"a shell"
	)
	_eq([shell.person, shell.person_state, shell.has_note], [false, &"", false], "nobody sits there")
	var launching := _agent("unknown", "")
	launching.starting = true
	launching.agent_name = "claude-2"
	var start := CardPicture.header_of(_facts(launching))
	_eq(
		[start.provider, start.caption, start.pill, start.caption_tip],
		["CLAUDE-2", "STARTING", &"StatePillQuiet", ""],
		"a start herdr took: the name it gave"
	)
	_eq(
		[start.person, start.starting, start.badge],
		[true, true, ArtContract.UI_STARTING],
		"walking in under the hourglass"
	)
	launching.provider = "claude"
	start = CardPicture.header_of(_facts(launching))
	_eq([start.provider, start.caption, start.caption_tip], ["CLAUDE", "STARTING", "Launching"], "once its kind shows")
	launching.state = "blocked"
	var asks := CardPicture.header_of(_facts(launching))
	_eq(
		[asks.caption, asks.pill, asks.starting, asks.badge],
		["BLOCKED", &"StatePillBlocked", false, &"blocked"],
		"a start that asks at once is blocked first"
	)
	var dropped := _facts(_agent("working"))
	dropped.dimmed = true
	var stale := CardPicture.header_of(dropped)
	_eq(
		[stale.caption, stale.pill, stale.badge, stale.dimmed, stale.has_note, stale.note],
		[
			"STALE / OFFLINE",
			&"StatePillQuiet",
			ArtContract.UI_OFFLINE,
			true,
			true,
			"Connection lost.\nNot an idle signal."
		],
		"a dropped machine: stale, never idle"
	)
	_eq(stale.summary, "CLAUDE · STALE / OFFLINE · web / main", "and so says the line")
	var done := CardPicture.header_of(_facts(_agent("done")))
	_eq([done.has_note, done.note], [true, "UNREAD = not yet seen\nNot task success."], "done explains UNREAD")
	_check(not CardPicture.header_of(_facts(_agent("working"))).has_note, "no other state has a note")


## The PANE list shows only what the pane has: a label, a foreground directory
## that differs, a session; and a seat the snapshot does not name is `?`.
func test_the_pane_list_shows_only_what_the_pane_has() -> void:
	var bare := _agent("idle")
	bare.workspace_label = ""
	bare.tab_label = ""
	bare.cwd = ""
	var header := CardPicture.header_of(_facts(bare))
	_eq([header.seat, header.cwd, header.cwd_tip], ["? / ?", "-", "Working directory: "], "nothing known of where")
	_eq(
		[header.label_shown, header.foreground_shown, header.session_shown, header.session, header.title],
		[false, false, false, "", ""],
		"and nothing more to list"
	)
	var full := _agent("idle")
	full.label = "worker"
	full.foreground_cwd = "/home/u/repo/tools/"
	full.terminal_title = "vim notes"
	full.session = AgentSessionIdentity.new()
	full.session.provider = "claude"
	full.session.source = "hook"
	full.session.kind = "session"
	full.session.value = "abc-123"
	header = CardPicture.header_of(_facts(full))
	_eq([header.label_shown, header.label, header.title], [true, "worker", "vim notes"], "its label and title")
	_eq(
		[header.foreground_shown, header.foreground, header.foreground_tip],
		[true, "Foreground: tools", "Foreground directory: /home/u/repo/tools/"],
		"the foreground's directory when it is another"
	)
	_eq(
		[header.session_shown, header.session, header.session_tip],
		[true, "Session: abc-123", "claude / hook / session\nabc-123"],
		"and its session"
	)
	full.foreground_cwd = full.cwd
	_check(not CardPicture.header_of(_facts(full)).foreground_shown, "the same directory is not listed twice")


# --- the picture is a value ---------------------------------------------------------


## Asking for the picture changes nothing: the facts read the same after, and
## a second asking says the same, block by block. Each block alone is the
## whole picture's.
func test_asking_twice_says_the_same_and_leaves_the_facts_alone() -> void:
	var pane := _agent("blocked")
	var facts := _facts(pane)
	facts.machine = "bee"
	facts.next = NextModel.of(pane, "bee", true)
	facts.input = _ticket(pane, CommandContext.Kind.KEYS, CommandTicket.State.SENT)
	facts.outcome = "Sent"
	facts.outcome_identity = pane.identity_key()
	facts.launch_line = "claude-2 started"
	facts.reply = "hello"
	facts.rows_clipped = 1
	var before := _flat(facts)
	var first := CardPicture.of(facts)
	_eq(_flat(facts), before, "the facts are as they were")
	var second := CardPicture.of(facts)
	_eq(_flat(facts), before, "and again")
	_eq(_flat(second), _flat(first), "the same facts, the same picture")
	_eq(_flat(first.stack), _flat(CardPicture.stack_of(facts)), "the stack alone")
	_eq(_flat(first.header), _flat(CardPicture.header_of(facts)), "the header alone")
	_eq(_flat(first.preview), _flat(CardPicture.preview_of(facts)), "the preview alone")
	_eq(_flat(first.actions), _flat(CardPicture.actions_of(facts)), "the actions alone")
	_eq(_flat(first.answer), _flat(CardPicture.answer_of(facts)), "answer mode alone")
	_eq(_flat(first.next), _flat(CardPicture.next_of(facts)), "NEXT alone")
	# Only the clock moves the picture between two askings, and only the caption.
	facts.now_msec += 60000
	var later := CardPicture.of(facts)
	_eq(later.preview.caption, "3 of 3 rows · clipped", "a clipped question gives its age up")
	facts.rows_clipped = 0
	_eq(CardPicture.preview_of(facts).caption, "3 of 3 rows · 1m ago", "the clock given moved the caption")
	_eq(_flat(CardPicture.actions_of(facts)), _flat(first.actions), "and nothing else")
