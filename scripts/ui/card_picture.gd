class_name CardPicture
extends RefCounted
## What the agent card shows this instant, as one value: every text,
## visibility, enabled flag and tooltip the card (OfficePaneInspector) and its
## header (CardDetails) write, worked out from the card's Facts and nothing
## else. Pure: no node, no fleet, no command, and no clock of its own
## (`Facts.now_msec` is the clock). Asking twice changes nothing, the facts
## included.
##
## One record of seven blocks, each a function of the same Facts and of no
## other block: `stack` (which parts of the panel show, in which form),
## `header` (who sits there, in what state and where, and the PANE list),
## `preview` (the terminal's rows and the caption over them), `actions` (the
## switch, Monitor, `▾ Esc` and the footer sentence), `answer` (answer mode's
## chip, title, keys and "Send line"), `next` (the NEXT pill) — and `more`,
## whether the PANE list has its room. The card writes the block an event can
## have moved; of() is all of them.
##
## The footer's priority (footer_of()) lives here and only here: the switch in
## flight; an answer, start, split, close, space or worktree in flight; what
## became of this terminal's last write; how the pane's start is going; the
## card following herdr's focus; a pane taken over since it was picked; answer
## mode's own word; a write that waits (another one out, a look owed); why the
## switch is off; and nothing.
##
## Not in the picture: the launch block (LaunchBlock, CardActions) words its
## own buttons, notes and confirms, and hands the footer its launch line as a
## fact; the time in state and NEXT's wait are OfficeAttention's to tick.

const PREVIEW_ROWS := OfficePaneInspector.PREVIEW_ROWS
const HEADING := OfficePaneInspector.HEADING


## Everything the picture is worked out from. Values only: what the office
## showed, what the card remembers, what its nodes measured, what the fleet
## answered when the card asked, and the clock.
class Facts:
	## The pane shown (null: the empty state), its machine's label (empty with
	## one machine), whether that machine dropped, and whether the viewer picked it.
	var pane: PaneModel
	var machine := ""
	var dimmed := false
	var pick := OfficePaneInspector.Pick.FOLLOWING
	## What the pack calls the pane's state, and the badge it wears for it
	## (CardDetails.caption_of(), badge_of()): the pack itself is no fact.
	var state_caption := ""
	var state_badge := &""
	## A fleet is connected, and it may not write (`--read-only`).
	var connected := false
	var read_only := false
	## The panel's form, as the HUD set it, and answer mode.
	var compact := false
	var card := false
	var wide := true
	var answering := false
	## The launch block shows (its own to decide), and the card is narrower
	## than the width at which the PANE list fits beside it.
	var launch_shown := false
	var narrow := false
	## Whom NEXT names (null: nobody), and NEXT's tooltip as the scene says it.
	var next: NextModel
	var next_tip := ""
	## The preview: its state, why it is unavailable, the read that failed
	## (FAILED only), the text shown with its source and whether it was cut,
	## how many shown rows the label clips, and when it was read.
	var preview := OfficePaneInspector.PreviewState.NONE
	var preview_reason := CommandRefusal.Reason.NONE
	var preview_failed: CommandTicket
	var text := ""
	var source := ""
	var cut := false
	var rows_clipped := 0
	var read_at_msec := -1
	## The clock, on the scale of `read_at_msec`.
	var now_msec := 0
	## The switch is in flight; the one input command in flight (null: none).
	var switching := false
	var input: CommandTicket
	## What became of this binding's last write, the same in full, and the
	## terminal it went to (empty for the card's own words).
	var outcome := ""
	var outcome_detail := ""
	var outcome_identity := ""
	## How the pane's start is going (CardActions.launch_line()), and the same
	## in full; empty with nothing to say.
	var launch_line := ""
	var launch_detail := ""
	## The reply typed, why it cannot go as a line (NONE: it can), and herdr's cap.
	var reply := ""
	var reply_refusal := CommandRefusal.Reason.NONE
	var line_bytes_max := 0
	## Why the switch, a key and a line may not be pressed now (NONE: may),
	## and whether answer mode has anything to press at all.
	var switch_refusal := CommandRefusal.Reason.NONE
	var keys_refusal := CommandRefusal.Reason.NONE
	var line_refusal := CommandRefusal.Reason.NONE
	var answer_possible := false


## One line and the same in full for its tooltip.
class Line:
	var text := ""
	var tip := ""


## Which parts of the panel show: the details at full height, the compact
## line, the card form of it (`carded`), or the empty state.
class Stack:
	## The compact panel is a card: the header over the line's buttons.
	var carded := false
	## `%Detail`, `%CompactRow`, `%Title`, `%Empty`.
	var detail := false
	var line := false
	var title := false
	var empty := false
	## The panel is at full height: NEXT reads down and wraps, and the empty
	## state says why.
	var full := true
	## NEXT's wait has room.
	var next_wait := true
	## The line's long words, empty where the screen has no room for them.
	var monitor_word := ""
	var open_word := ""
	## What the empty state says.
	var message := ""


## Who sits at the desk shown, in what state and where: the header and the
## PANE list (CardDetails writes it).
class Header:
	var provider := ""
	var caption := ""
	var caption_tip := ""
	## The pill the caption stands in and the caption's own look (HudTheme).
	var pill := &""
	var caption_look := &""
	var machine_shown := false
	var machine := ""
	var seat := ""
	var pane_id := ""
	var pane_id_tip := ""
	var label := ""
	var label_shown := false
	var cwd := ""
	var cwd_tip := ""
	var foreground := ""
	var foreground_tip := ""
	var foreground_shown := false
	var session := ""
	var session_tip := ""
	var session_shown := false
	var title := ""
	## The note under the caption, and whether the state shown has one.
	var note := ""
	var has_note := false
	## The portrait: whether there is a person at all (a shell has none), and
	## whom to draw: provider, state, still starting, greyed and frozen, the
	## pane's key (the same person as at the seat), and the badge.
	var person := false
	var person_provider := ""
	var person_state := &""
	var starting := false
	var dimmed := false
	var key := ""
	var badge := &""
	## The compact line: provider, caption and seat in the header's words.
	var summary := ""
	var summary_tip := ""


## The terminal's rows and the caption over them.
class Preview:
	## PREVIEW_ROWS rows, joined: the last of the text, padded at the top.
	var rows := ""
	var caption := ""
	var caption_tip := ""
	## The age the caption says, in whole seconds; -1 unless text is shown.
	var seconds := -1


## The switch, Monitor, `▾ Esc`, and the footer under them.
class Actions:
	## The office may write to this pane's machine: the footer shows.
	var offered := false
	## The switch and its note show; the switch may not be pressed.
	var focus := false
	var focus_off := true
	var focus_text := ""
	var focus_tip := ""
	var monitor := false
	var fold := false
	var top := false
	var footer := ""
	var footer_tip := ""


## Answer mode: the heading's chip, the title, the keys and "Send line".
class Answer:
	## The chip shows; it opens answer mode (with the Enter hint) or closes it.
	var chip := false
	var chip_text := ""
	var chip_keyed := false
	var chip_tip := ""
	## Answer mode is open: its controls show and the card's boxes turn.
	var open := false
	var title := false
	var title_text := ""
	var title_tip := ""
	var keys_off := true
	var line_off := true
	var line_tip := ""
	var best_effort := ""
	## " on bee", or empty with one machine; and "\nOff: …", or empty while
	## the keys may be pressed.
	var on := ""
	var keys_why := ""

	## The tooltip of the button that sends key `key_name` (`1`, `y`, `enter`, `esc`).
	func key_tip(key_name: String) -> String:
		return CardPicture.key_words(key_name, on) + keys_why


## The NEXT pill.
class Next:
	## Somebody is next: the button and `‹ ›` are on, the marks show.
	var somebody := false
	var title := true
	var line := ""
	var muted := true
	var tip := ""


var stack: Stack
var header: Header
var preview: Preview
var actions: Actions
var answer: Answer
var next: Next
## The PANE list has its room (more_of()).
var more := false


## The whole picture for `facts`. `header` is null in the empty state.
static func of(facts: Facts) -> CardPicture:
	var picture := CardPicture.new()
	picture.stack = stack_of(facts)
	picture.header = null if facts.pane == null else header_of(facts)
	picture.preview = preview_of(facts)
	picture.actions = actions_of(facts)
	picture.answer = answer_of(facts)
	picture.next = next_of(facts)
	picture.more = more_of(facts)
	return picture


# --- the stack ----------------------------------------------------------------


static func stack_of(facts: Facts) -> Stack:
	var made := Stack.new()
	made.carded = facts.compact and facts.card
	made.detail = facts.pane != null and (not facts.compact or made.carded)
	made.line = facts.pane != null and facts.compact
	made.title = not made.carded and not facts.answering
	made.empty = facts.pane == null
	made.full = not facts.compact
	made.next_wait = not facts.compact or facts.wide
	made.monitor_word = "Monitor" if facts.wide else ""
	made.open_word = "Open" if facts.wide else ""
	made.message = "Waiting for herdr." if facts.dimmed else "This session has no panes."
	return made


## Whether the PANE list shows: it gives the launch block its room on a narrow
## card, answer mode's controls theirs always, and the card form has none.
static func more_of(facts: Facts) -> bool:
	var carded := facts.compact and facts.card
	return not facts.answering and not carded and not (facts.launch_shown and facts.narrow)


# --- the header -----------------------------------------------------------------


## The header and details of `facts.pane`, which is never null here.
static func header_of(facts: Facts) -> Header:
	var pane := facts.pane
	var made := Header.new()
	var state := StringName(pane.state)
	var starting := pane.launching()
	# A start herdr took but whose kind it has not detected yet: the name it gave.
	var named := starting and pane.provider.is_empty() and not pane.agent_name.is_empty()
	made.provider = (
		pane.agent_name.to_upper() if named else "SHELL" if pane.provider.is_empty() else pane.provider.to_upper()
	)
	# A shell has no agent, so no person and no agent state: herdr's idle for it is the terminal's.
	var shell := pane.provider.is_empty() and not starting
	made.caption = (
		"STALE / OFFLINE" if facts.dimmed else "STARTING" if starting else "no agent" if shell else facts.state_caption
	)
	made.pill = CardDetails.pill_of(state, facts.dimmed or starting or shell)
	made.caption_look = &"LabelPaper" if made.pill == &"StatePillQuiet" else &"LabelInk"
	made.caption_tip = "herdr reports no agent in this pane: a shell." if shell else ""
	if not pane.provider.is_empty():
		made.caption_tip = (
			"Launch status not reported"
			if not pane.starting_known
			else "Launching" if pane.starting else "Not launching"
		)
	made.machine_shown = not facts.machine.is_empty()
	made.machine = "@ " + facts.machine
	# A pane whose workspace or tab the snapshot does not carry still names its seat.
	var space := pane.workspace_label if not pane.workspace_label.is_empty() else "?"
	var tab := pane.tab_label if not pane.tab_label.is_empty() else "?"
	made.seat = "%s / %s" % [space, tab]
	made.pane_id = pane.pane_id
	made.pane_id_tip = "Pane: " + pane.pane_id + "\nTerminal: " + pane.terminal_id
	made.label = pane.label
	made.label_shown = not pane.label.is_empty()
	var cwd := pane.cwd_name()
	made.cwd = cwd if not cwd.is_empty() else "-"
	made.cwd_tip = "Working directory: " + pane.cwd
	made.foreground_shown = not pane.foreground_cwd.is_empty() and pane.foreground_cwd != pane.cwd
	made.foreground = "Foreground: " + pane.foreground_cwd.trim_suffix("/").get_file()
	made.foreground_tip = "Foreground directory: " + pane.foreground_cwd
	made.session_shown = pane.session != null
	if pane.session != null:
		made.session = "Session: " + pane.session.value
		made.session_tip = (
			"%s / %s / %s\n%s" % [pane.session.provider, pane.session.source, pane.session.kind, pane.session.value]
		)
	made.title = pane.terminal_title
	# The note under the caption explains the state it names: a dropped
	# machine's, or UNREAD's. Other states need none.
	made.has_note = facts.dimmed or (state == ArtContract.STATE_DONE and not starting)
	made.note = (
		"Connection lost.\nNot an idle signal." if facts.dimmed else "UNREAD = not yet seen\nNot task success."
	)
	made.person = not shell
	made.person_provider = pane.provider
	made.person_state = &"" if shell else state
	made.starting = starting
	made.dimmed = facts.dimmed
	made.key = pane.key
	made.badge = (
		ArtContract.UI_OFFLINE if facts.dimmed else ArtContract.UI_STARTING if starting else facts.state_badge
	)
	# The compact line says the same three things in the same words.
	made.summary = "%s · %s · %s" % [made.provider, made.caption, made.seat]
	made.summary_tip = made.summary if facts.machine.is_empty() else made.summary + " @ " + facts.machine
	return made


# --- the preview ----------------------------------------------------------------


## How old the text read at `read_at_msec` is at `now_msec`, in whole seconds.
static func age_seconds(read_at_msec: int, now_msec: int) -> int:
	return int((now_msec - read_at_msec) / 1000.0)


static func preview_of(facts: Facts) -> Preview:
	var made := Preview.new()
	var shown := facts.preview == OfficePaneInspector.PreviewState.SHOWN
	var rows := CardWords.rows_of(facts.text if shown else "")
	made.rows = _rows_text(rows)
	match facts.preview:
		OfficePaneInspector.PreviewState.LOADING:
			made.caption = "Reading…"
			made.caption_tip = "Reading this pane's terminal from herdr."
		OfficePaneInspector.PreviewState.UNAVAILABLE:
			made.caption = "No preview: " + CommandRefusal.text(facts.preview_reason)
			made.caption_tip = "No terminal preview: " + CommandRefusal.detail(facts.preview_reason)
		OfficePaneInspector.PreviewState.FAILED:
			made.caption = "Read failed: " + CardWords.failure(facts.preview_failed)
			made.caption_tip = ("The last read brought no text back: " + CardWords.failure_detail(facts.preview_failed))
		OfficePaneInspector.PreviewState.SHOWN:
			_caption_shown(made, facts, rows.size())
	return made


## The last PREVIEW_ROWS of `rows`, tabs expanded, padded at the top so the
## block is always that many rows tall. Long rows are clipped by the label.
static func _rows_text(rows: PackedStringArray) -> String:
	if rows.size() > PREVIEW_ROWS:
		rows = rows.slice(rows.size() - PREVIEW_ROWS)
	var shown := PackedStringArray()
	for index in PREVIEW_ROWS - rows.size():
		shown.append("")
	for row in rows:
		shown.append(CardWords.expand_tabs(row.left(CardWords.ROW_CHARS)))
	return "\n".join(shown)


## The caption of shown text: its source, how old it is, and whether it was
## cut or has rows wider than the card. A blocked pane's caption leads with how
## many of its rows are shown.
static func _caption_shown(made: Preview, facts: Facts, rows_total: int) -> void:
	var seconds := age_seconds(facts.read_at_msec, facts.now_msec)
	made.seconds = seconds
	var shown := mini(rows_total, PREVIEW_ROWS)
	var clipped := (
		" %d of them wider than the card and clipped: look at herdr for the rest." % facts.rows_clipped
		if facts.rows_clipped > 0
		else ""
	)
	var cut := " Cut: only the end of it is shown." if facts.cut else ""
	if facts.source == CommandContext.SOURCE_DETECTION:
		var rows := "%d of %d row%s" % [shown, rows_total, "" if rows_total == 1 else "s"]
		var flag := (
			" · cut" if facts.cut else " · clipped" if facts.rows_clipped > 0 else " · %s ago" % CardWords.age(seconds)
		)
		made.caption = rows + flag
		made.caption_tip = (
			"The last %d of the %d rows of herdr's detection source (what its agent detection reads), read %s ago.%s%s"
			% [shown, rows_total, CardWords.age(seconds), clipped, cut]
		)
		return
	made.caption = (
		"recent · %s ago%s"
		% [CardWords.age(seconds), " · cut" if facts.cut else " · clipped" if facts.rows_clipped > 0 else ""]
	)
	made.caption_tip = (
		"The last %d lines of herdr's %s source, read %s ago.%s%s"
		% [PREVIEW_ROWS, facts.source, CardWords.age(seconds), clipped, cut]
	)


# --- the switch and the footer ----------------------------------------------------


## The switch, its note, Monitor, `▾ Esc` and the footer. Offered only with a
## fleet that may write; the switch enabled only for a picked pane that the
## boundary would send to now, and never while a write of this card is in
## flight. The button names the machine it switches whenever the office has
## more than one.
static func actions_of(facts: Facts) -> Actions:
	var made := Actions.new()
	made.offered = facts.pane != null and facts.connected and not facts.read_only
	made.focus = made.offered and not facts.answering
	# The terminal monitor: offered for any pane shown with a fleet; read-only
	# opens it view-only. The same on the one-line row.
	made.monitor = facts.pane != null and facts.connected
	# Escape in answer mode only leaves it: `▾ Esc` folds only out of it.
	made.fold = facts.pane != null and not facts.answering
	made.top = made.monitor or made.fold
	var where := "herdr" if facts.machine.is_empty() else "herdr on " + facts.machine
	made.focus_text = "Switch herdr here" if facts.machine.is_empty() else "Switch herdr on " + facts.machine
	made.focus_tip = (
		"Switches the shared view of %s to this pane: every terminal attached to it follows." % where
		+ "\nIt also clears UNREAD for every pane on this tab, not just this one."
	)
	if not made.offered:
		return made
	made.focus_off = (
		write_in_flight(facts)
		or facts.pick != OfficePaneInspector.Pick.PICKED
		or facts.switch_refusal != CommandRefusal.Reason.NONE
	)
	var said := footer_of(facts)
	made.footer = said.text
	made.footer_tip = said.tip
	return made


## Whether any write of this card is on its way. Every write control waits.
static func write_in_flight(facts: Facts) -> bool:
	return facts.switching or facts.input != null


## Whether the outcome kept for terminal `outcome_identity` is a write to
## another terminal than `pane` holds now (the pane id was taken over since):
## never said as this one's. The look it owes still holds (keyed by the pane),
## and says so as "No writes".
static func foreign(outcome_identity: String, pane: PaneModel) -> bool:
	return not outcome_identity.is_empty() and pane != null and outcome_identity != pane.identity_key()


## The footer sentence of a card that may write, by priority: the first of
## these that has something to say, says it.
static func footer_of(facts: Facts) -> Line:
	var said := Line.new()
	var reason := facts.switch_refusal
	if facts.switching:
		said.text = "Switching…"
		said.tip = "The switch is on its way to herdr."
	elif facts.input != null:
		said.text = CardWords.input_progress(facts.input)
		said.tip = _on_its_way(facts.input.context.kind)
	elif not facts.outcome.is_empty() and not foreign(facts.outcome_identity, facts.pane):
		said.text = facts.outcome
		said.tip = facts.outcome_detail
	elif not facts.launch_line.is_empty() and not (facts.answering and answer_says(facts)):
		said.text = facts.launch_line
		said.tip = facts.launch_detail
	elif facts.pick == OfficePaneInspector.Pick.FOLLOWING:
		said.text = "Following herdr's focus"
		said.tip = ("This card follows herdr's own focus. Click a desk to pick it: only a desk you picked can switch herdr.")
	elif facts.pick == OfficePaneInspector.Pick.REPLACED:
		said.text = "New terminal: pick again"
		said.tip = "Another terminal has taken this pane's id since you picked it. Click the desk to pick it again."
	elif facts.answering:
		var off := answer_off(facts)
		if off != CommandRefusal.Reason.NONE:
			said.text = "No answer: " + CommandRefusal.text(off)
			said.tip = "The answer controls are off: " + CommandRefusal.detail(off)
		elif not facts.reply.is_empty() and facts.reply_refusal != CommandRefusal.Reason.NONE:
			said.text = "Line: " + CommandRefusal.text(facts.reply_refusal)
			said.tip = "This line cannot be sent: " + CommandRefusal.detail(facts.reply_refusal)
	elif reason == CommandRefusal.Reason.IN_FLIGHT or reason == CommandRefusal.Reason.LOOK_FIRST:
		# Every write to the pane waits, the switch and the answers alike.
		said.text = "No writes: " + CommandRefusal.text(reason)
		said.tip = "The switch and the answers are off: " + CommandRefusal.detail(reason)
	elif reason != CommandRefusal.Reason.NONE:
		said.text = "No switch: " + CommandRefusal.text(reason)
		said.tip = "The switch is off: " + CommandRefusal.detail(reason)
	return said


## An input command of `kind` in flight, in full.
static func _on_its_way(kind: CommandContext.Kind) -> String:
	match kind:
		CommandContext.Kind.START:
			return "The start is on its way: the card reads the terminal again first, then herdr types the command."
		CommandContext.Kind.SPLIT:
			return "The split is on its way to herdr."
		CommandContext.Kind.CLOSE:
			return "The close is on its way to herdr."
		CommandContext.Kind.SPACE:
			return "The new space is on its way to herdr."
		CommandContext.Kind.WORKTREE:
			return "The new worktree is on its way to herdr; git runs there first."
	return "The answer is on its way: the card reads the terminal again first, then sends."


## The reason worth saying when answer mode has nothing to press (NONE while
## something may be): the keys' for a blocked agent, the line's for any other.
static func answer_off(facts: Facts) -> CommandRefusal.Reason:
	if facts.keys_refusal == CommandRefusal.Reason.NONE or facts.line_refusal == CommandRefusal.Reason.NONE:
		return CommandRefusal.Reason.NONE
	var blocked := facts.pane != null and facts.pane.state == str(ArtContract.STATE_BLOCKED)
	return facts.keys_refusal if blocked else facts.line_refusal


## Whether answer mode has something of its own to say in the footer: why
## nothing may be pressed, or why the typed line cannot go.
static func answer_says(facts: Facts) -> bool:
	return (
		answer_off(facts) != CommandRefusal.Reason.NONE
		or (not facts.reply.is_empty() and facts.reply_refusal != CommandRefusal.Reason.NONE)
	)


# --- answer mode ------------------------------------------------------------------


## Why "Send line" is off for the reply typed: what refuses a line to this
## pane now (`line`), else what refuses this text (`typed`); NONE while it may go.
static func send_refusal(line: CommandRefusal.Reason, typed: CommandRefusal.Reason) -> CommandRefusal.Reason:
	return line if line != CommandRefusal.Reason.NONE else typed


## Everything answer mode shows, and which parts of the card it hides.
static func answer_of(facts: Facts) -> Answer:
	var made := Answer.new()
	made.chip = facts.answering or facts.answer_possible
	made.chip_text = "Close" if facts.answering else "Answer"
	made.chip_keyed = not facts.answering
	made.chip_tip = (
		"Esc: leave answer mode. Nothing is sent."
		if facts.answering
		else "Enter: answer this agent. Opens the answer keys and the reply box; nothing is sent until you press one."
	)
	made.open = facts.answering
	# The header under it already says who and in what state; so does a card's.
	made.title = not facts.answering and not (facts.compact and facts.card)
	made.title_text = HEADING
	if facts.answering and facts.pane != null:
		var who := "SHELL" if facts.pane.provider.is_empty() else facts.pane.provider.to_upper()
		made.title_text = "%s · %s" % [who, facts.state_caption]
		if not facts.machine.is_empty():
			made.title_text += " · " + facts.machine
		made.title_tip = "Answering: " + made.title_text
	made.on = "" if facts.machine.is_empty() else " on " + facts.machine
	var keys := facts.keys_refusal
	made.keys_off = keys != CommandRefusal.Reason.NONE
	made.keys_why = "" if keys == CommandRefusal.Reason.NONE else "\nOff: " + CommandRefusal.detail(keys)
	var line := send_refusal(facts.line_refusal, facts.reply_refusal)
	made.line_off = line != CommandRefusal.Reason.NONE
	made.line_tip = (
		(
			"Send one line to this agent%s: herdr types it and presses Enter (bracketed when the agent asked). %d of %d bytes."
			% [made.on, facts.reply.to_utf8_buffer().size(), facts.line_bytes_max]
		)
		+ ("" if line == CommandRefusal.Reason.NONE else "\nOff: " + CommandRefusal.detail(line))
	)
	made.best_effort = CardWords.BEST_EFFORT
	return made


## What the button that sends key `key_name` says it does; `on` names the
## machine (" on bee", or empty).
static func key_words(key_name: String, on: String) -> String:
	match key_name:
		"enter":
			return "Sends Enter%s: it confirms whatever the question has selected. Only by click." % on
		"esc":
			return "Sends Escape to the terminal%s. The Esc key on your keyboard never does." % on
		"n":
			return "Sends n%s. Only by click: the N key goes to the next agent." % on
	return (
		"Sends %s%s. Key %s in answer mode does the same, where your keyboard types %s there without Shift."
		% [key_name, on, key_name, key_name]
	)


# --- NEXT -------------------------------------------------------------------------


## NEXT's words. At full height `NEXT:` over what a press does and to whom
## (`Answer CLAUDE web`, `Read CODEX api`; ` @ bee` with several machines) and
## the wait; on a wide line the same three in a row. A narrow line has room
## for provider and space only, whole, and no `NEXT:` before them; on either
## line the button's tooltip says the whole sentence. An office that cannot
## write has no verb, and says whom and herdr's state instead (`CLAUDE web ·
## blocked`). `NEXT: All clear` fits every form.
static func next_of(facts: Facts) -> Next:
	var pill := Next.new()
	var whom := facts.next
	var short := facts.compact and not facts.wide
	pill.somebody = whom != null
	pill.title = not short or whom == null
	var tip := OfficePaneInspector.NEXT_PICKS_TIP if whom != null and whom.verb.is_empty() else facts.next_tip
	pill.tip = tip
	if whom == null:
		pill.line = "All clear"
		pill.muted = true
		return pill
	var who := "%s %s" % ["SHELL" if whom.provider.is_empty() else whom.provider.to_upper(), whom.space]
	var whole := "%s · %s" % [who, whom.state] if whom.verb.is_empty() else "%s %s" % [whom.verb, who]
	if not whom.machine.is_empty():
		whole += " @ " + whom.machine
	pill.line = who if short else whole
	# The one line clips what does not fit (a long space, ` @ machine`): its
	# tooltip says the whole sentence, at either width.
	if facts.compact:
		pill.tip = tip + "\nNext: " + whole
	pill.muted = false
	return pill
