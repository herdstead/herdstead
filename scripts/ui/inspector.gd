class_name OfficePaneInspector
extends HdPanel
## The agent card, which is the staff panel along the screen's bottom (the
## names "card" and "inspector" stay: card = the staff panel): who is at the
## selected desk, in what state, for how long and where; a live preview of that
## pane's terminal; "Switch herdr here", which switches herdr's own view to the
## pane; and answer mode, which sends an approval key or one line of text to an
## agent's terminal. At its right end, NEXT names whom `N` picks next.
##
## The HUD shows the panel as one line (set_compact()) at every size until it is
## opened: Enter, the line's `Open` and answer mode open it to full height,
## Escape out of answer mode and `▾ Esc` fold it (OfficeHud._fit_staff()). The
## line keeps `‹ ›` (NEXT's queue, selection only), Monitor and NEXT.
##
## Every label is permanent and reached by its unique name; a refresh writes
## text, never nodes. The portrait is re-configured only when the provider or
## the pack changes, so its animation runs on across refreshes.
##
## The preview and every write go through the fleet's command calls only (a
## CommandContext in, a CommandTicket out); the card never names a herdr method.
## Without a fleet — the showroom, a panel shown on its own — or in read-only
## mode the preview says it is unavailable and no action is offered.
##
## A line that does not fit its column says it in full in its tooltip.
##
## Answer mode (docs/WRITE_BOUNDARY.md §2). Only for a desk the viewer picked, on an agent.
## Enter, or the "Answer" chip, opens it; nothing else does, and the Enter
## itself sends nothing. The HUD then stands the card in the middle of the
## screen as a modal (OfficeHud._fit_staff()), and the card turns its boxes to
## lay itself out top to bottom (_show_answer()): the header, the preview across
## the whole card (still 12 rows), the answer keys, "Send Esc", the reply box
## and the best-effort line under it, and Monitor, Close and the outcome along
## the foot. It trades the switch and the details list for them. Buttons are aimed at their
## press and sent at their release, and never take keyboard focus. In answer
## mode the keyboard sends only 1–9 and y, by key position: `N` leaves and goes
## to the next agent (never sends "n"), Escape only leaves, Enter never sends.
## While the reply box has focus every key is typing. A press freezes the
## preview shown (CommandPreview): if the card shows another read by the
## release, or the terminal reads differently right before the write, nothing
## is sent. Which keys are offered never depends on the terminal's text.
##
## START AGENT (docs/WRITE_BOUNDARY.md §4). Beside a picked shell's preview, one button
## per agent kind the machine's snapshot shows: a click (aimed at the press,
## sent at the release) has herdr type that kind's command and Enter into this
## terminal, under the next free name. Only after a prompt: a last row that
## ends like one sends at once; one that ends otherwise (a theme's prompt, a
## half-typed line) only arms a confirm showing that row, and a second click on
## the same kind, on the same screen within CONFIRM_SECONDS, sends; nothing
## whole to look at sends nothing. The footer then says how the start is going.
## No key ever starts an agent.
##
## NEW PANE BESIDE (docs/WRITE_BOUNDARY.md §4). In the same place for a picked agent: one
## button has herdr split its pane towards the side its shape gives, leaving
## herdr's focus where it is. The split is the whole gesture: the footer names
## the new pane, and the office then picks it (a selection, never a write), so
## its card offers START AGENT, which takes a click of its own. No key splits.

## "Monitor" was pressed: open the terminal monitor on pane `pane_key`.
signal monitor_requested(pane_key: String)
## NEXT was pressed: the office does what `N` does.
signal next_requested
## `Open` on the one-line row was pressed: the HUD opens the panel up. Only
## that: it never opens answer mode.
signal open_requested
## `▾ Esc` was pressed: the HUD folds the panel back to its line.
signal fold_requested
## `‹` (-1) or `›` (+1) on the one-line row was pressed: the office picks the
## one before or after the pick in NEXT's queue, and only picks.
signal step_requested(direction: int)
## A split from this card of pane `target_key` made pane `pane_id` (herdr's
## spelling) with terminal `terminal_id`, on that machine at `generation`: the
## office picks it once a snapshot shows it, if the viewer's pick is still the
## pane split. Only a selection follows; nothing is sent to it.
signal pane_split(target_key: String, pane_id: String, terminal_id: String, generation: int)
## A new space or worktree from this card of pane `from_key` made workspace
## `workspace_id` with root pane `pane_id` (herdr's spelling) in terminal
## `terminal_id`, on that machine at `generation`: the office picks that
## shell once a snapshot shows it, in its new zone, if the viewer's pick is
## still the pane it came from. Only a selection follows; nothing is sent to it.
signal space_created(from_key: String, workspace_id: String, pane_id: String, terminal_id: String, generation: int)

## Whether the pane shown is the viewer's own pick, as the office decides it
## (OfficeNavigator.is_picked()). Only a pick can switch herdr or be answered.
enum Pick {
	## Nobody picked it: the card follows herdr's own focus.
	FOLLOWING,
	## The viewer picked this desk, and it still holds the terminal they picked.
	PICKED,
	## The viewer picked this desk, but another terminal has taken its pane id since.
	REPLACED,
}

## What the START AGENT block offers (_launch_form()).
enum Form {
	## Nothing: no block.
	NONE,
	## A start in the shell shown.
	START,
	## A new pane beside the agent shown.
	SPLIT,
	## Only the manage rows (Close pane, New space, New worktree): a pane that
	## neither starts nor splits (launching, or on a dimmed machine).
	MANAGE_ONLY,
}

## Why the office did not pick a new pane a split of this card made
## (new_pane_not_picked()).
enum Unpicked {
	## No snapshot showed it within the office's wait (PENDING_PICK_MSEC).
	UNSEEN,
	## The viewer had moved on while it was on its way: another zone, or answer mode.
	MOVED_ON,
	## It showed with another terminal than the one herdr named for it.
	OTHER_TERMINAL,
}

enum PreviewState {
	## No pane is shown.
	NONE,
	## The first read of this pane is under way.
	LOADING,
	## Text from the last read is shown; the caption says how old it is.
	SHOWN,
	## Nothing may be read now; preview_reason() says why.
	UNAVAILABLE,
	## The last read came back without usable text.
	FAILED,
}

## NEXT's tooltip where the office cannot write (`--read-only`, the showroom):
## there it only picks, so the scene's "opens their panel, answer keys" is not said.
const NEXT_PICKS_TIP := (
	"N: the next agent who needs you: the blocked, longest wait first; the done once nobody is blocked."
	+ " This office cannot write: it picks them and shows their desk, and opens nothing."
)
## Rows the preview shows, and asks herdr for when the pane is not blocked.
const PREVIEW_ROWS := 12
## Lines asked for a blocked pane's `detection` text: the whole question (herdr
## keeps at least 24), so that what an answer is checked against is all of it.
const BLOCKED_LINES := 200
## Seconds from one read's end to the next: a blocked agent is the one someone
## is about to answer, so it is read more often.
const BLOCKED_INTERVAL := 1.0
const QUIET_INTERVAL := 3.0
## Seconds after a write ends before the read that may count as looking at it
## (HerdrCommands.LOOK_DELAY_MSEC, with a frame or two to spare).
const LOOK_WAIT := 0.6
## Drafts kept in memory, one per pane and terminal; the oldest goes first.
const DRAFTS_MAX := 32
## The keys answer mode's keyboard sends, by InputMap action.
const KEY_ACTIONS: Dictionary[StringName, String] = {
	&"card_key_1": "1",
	&"card_key_2": "2",
	&"card_key_3": "3",
	&"card_key_4": "4",
	&"card_key_5": "5",
	&"card_key_6": "6",
	&"card_key_7": "7",
	&"card_key_8": "8",
	&"card_key_9": "9",
	&"card_key_y": "y",
}
## What the layout must make of each of those key positions for the key to be
## sent: the same key, unshifted. On AZERTY the key at US `6` types `-` (the
## office's zoom out) and on QWERTZ the key at US `y` is labelled Z: both are
## the office's, never an answer. A layout that has no unshifted digit sends no
## digit from the keyboard; the buttons still do.
const KEY_CODES: Dictionary[StringName, Key] = {
	&"card_key_1": KEY_1,
	&"card_key_2": KEY_2,
	&"card_key_3": KEY_3,
	&"card_key_4": KEY_4,
	&"card_key_5": KEY_5,
	&"card_key_6": KEY_6,
	&"card_key_7": KEY_7,
	&"card_key_8": KEY_8,
	&"card_key_9": KEY_9,
	&"card_key_y": KEY_Y,
}
const HEADING := "AGENT"
## Kind buttons in the START AGENT block (LaunchBlock, which shows it).
const KINDS_MAX := LaunchBlock.KINDS_MAX
## How long a confirm armed by a first click waits for the second one.
const CONFIRM_SECONDS := LaunchBlock.CONFIRM_SECONDS
## Seconds between looks at how the shown pane's start is going.
const LAUNCH_TICK := 0.25
## The writes the launch block's buttons send: from outside answer mode, and
## checked against no screen.
const FROM_THE_BLOCK: Array[CommandContext.Kind] = [
	CommandContext.Kind.START,
	CommandContext.Kind.SPLIT,
	CommandContext.Kind.CLOSE,
	CommandContext.Kind.SPACE,
	CommandContext.Kind.WORKTREE,
]

## At a card narrower than this, the START AGENT block takes the PANE
## details' place; at this width or more both show (the scene sets it).
@export var details_beside_launch_from := 0.0
## The card's width in card mode (set_card()); the scene sets it.
@export var card_width := 0.0
## NEXT's height in card mode, where it is a pill on one line standing in the
## middle of the slot; elsewhere it fills its column. The scene sets it.
@export var next_pill_height := 0.0

## Null until the office connects one; the card then reads and writes through it.
var _fleet: HerdrFleet
## Answers whether the window is minimized (FramePacer.is_minimized()).
var _minimized: Callable
## Answers whether something covers the card (the compact card under the agent list).
var _covered: Callable
## The pane shown now and how: see show_pane().
var _pane: PaneModel
var _machine := ""
var _dimmed := false
var _pick := Pick.FOLLOWING
## Pane key, identity and machine generation the card is bound to, as one
## string; empty with no pane. A change is a new binding.
var _bound := ""
var _binding := 0
## The binding a click on a chip asked to answer once its question is shown
## (arm_answer()); -1 for none.
var _armed_binding := -1
## Aimed when the card bound its pane; every read of this binding starts here.
var _read_context: CommandContext
## The one read in flight, or null.
var _read_ticket: CommandTicket
var _read_seq := 0
## A read should start as soon as one may: the card opened, the pane's status
## moved, or the interval since the last one ran out.
var _read_due := false
var _next_read_in := 0.0
var _last_status := ""
var _state := PreviewState.NONE
var _reason := CommandRefusal.Reason.NONE
var _text := ""
var _source := ""
var _cut := false
## The accepted read whose text is shown now, and its sequence number: what a
## press freezes. Null whenever the preview shows no text.
var _shown_ticket: CommandTicket
var _shown_seq := 0
## The read a FAILED preview names; null in every other state.
var _read_failed: CommandTicket
## How many of the rows shown are wider than the preview (_measure_rows()).
var _rows_clipped := 0
## Time.get_ticks_msec() of the read whose text is shown.
var _read_at := -1
## The age the caption last said, in seconds: it is written again only when
## that moves (_show_age()).
var _caption_seconds := -1
## Aimed at the press of the switch; sent at its release, if still bound the same.
var _focus_context: CommandContext
var _focus_ticket: CommandTicket
## Aimed at the press of an answer button; sent at its release (see Aim).
var _aim: CardActions.Aim
## The one input command of this card in flight, or null.
var _input_ticket: CommandTicket
var _answering := false
## Pane key and identity -> the reply typed for it, in memory only.
var _drafts: Dictionary[String, Draft] = {}
## The draft key and pane key of the pane the box types for now.
var _draft_key := ""
var _draft_pane := ""
## What became of this binding's last write, and the same in full for its
## tooltip; both empty before one.
var _outcome := ""
var _outcome_detail := ""
## PaneModel.identity_key() of the terminal a write outcome shown in the footer
## was sent to; empty for the card's own words ("Not sent: …" before any write).
## An outcome for another terminal than the one bound now is not this
## terminal's news: the footer never says it (_foreign_outcome()).
var _outcome_identity := ""
## The HUD folded the panel to its compact line (set_compact()).
var _compact := false
## The Enter key's hint icon (dress()), beside `Open`, `Answer` and the answer keys' Enter.
var _key_enter_icon: Texture2D
## The screen is wide enough for the line's long words (set_wide()).
var _wide := true
## The HUD shows the compact panel as a card (set_card()).
var _card := false
## Whom NEXT names (show_next()); null for nobody.
var _next: NextModel
## NEXT's own tooltip as the scene says it; the compact line adds whom it names.
var _next_tip := ""
## The aiming family: what a press aims, the confirms, the launch line (CardActions).
var _actions := CardActions.new()
## The footer text a pending pick (a split's new pane, a new zone's shell) was
## announced with: new_pane_not_picked() speaks only while it still shows.
var _pending_outcome := ""
## Seconds to the next look at how this pane's start is going, and what that
## said last time: the footer is written again only when it changes.
var _launch_tick := 0.0
var _launch_said := ""
## Counts the shows (_show_action(), _show_answer(), _show_stack()). Hiding a
## button that is held down makes the engine release it at once, inside the
## write: its handler may change what the card remembers and show the card
## anew, and what the outer show had still to write is then old. A show that
## finds another ran inside it shows once more, from what is true now.
var _shows := 0


## A reply typed for one pane and terminal.
class Draft:
	var pane_key := ""
	var text := ""


func _ready() -> void:
	var button: Button = %FocusButton
	button.button_down.connect(_on_focus_down)
	button.pressed.connect(_on_focus_pressed)
	button.gui_input.connect(_on_double_click.bind(button))
	var hint: Button = %AnswerButton
	hint.pressed.connect(_on_answer_button)
	var monitor: Button = %MonitorButton
	monitor.pressed.connect(_on_monitor_pressed)
	var line_monitor: Button = %CompactMonitor
	line_monitor.pressed.connect(_on_monitor_pressed)
	var open: Button = %CompactOpen
	open.pressed.connect(func() -> void: open_requested.emit())
	var fold: Button = %FoldButton
	fold.pressed.connect(func() -> void: fold_requested.emit())
	var back: Button = %StepBack
	back.pressed.connect(func() -> void: step_requested.emit(-1))
	var on: Button = %StepOn
	on.pressed.connect(func() -> void: step_requested.emit(1))
	for key: Button in _key_buttons():
		_wire_input(key, CommandContext.Kind.KEYS, _key_of(key))
	var send_line: Button = %SendLine
	_wire_input(send_line, CommandContext.Kind.LINE, "")
	for kind: Button in _block().kind_buttons():
		_wire_input(kind, CommandContext.Kind.START, "")
	_wire_input(_block().split_button(), CommandContext.Kind.SPLIT, "")
	_wire_input(_block().close_button(), CommandContext.Kind.CLOSE, "")
	_wire_input(_block().space_button(), CommandContext.Kind.SPACE, "")
	_wire_input(_block().worktree_button(), CommandContext.Kind.WORKTREE, "")
	var branch: LineEdit = _block().branch_box()
	branch.text_changed.connect(_on_branch_changed)
	branch.gui_input.connect(_on_branch_input)
	resized.connect(_show_more)
	var box: LineEdit = %ReplyBox
	box.text_changed.connect(_on_draft_changed)
	box.gui_input.connect(_on_reply_input)
	var preview: Label = %Preview
	preview.resized.connect(_measure_rows)
	var next: Button = %NextButton
	next.pressed.connect(func() -> void: next_requested.emit())
	_next_tip = next.tooltip_text
	_show_preview()
	_show_action()
	show_next(null)
	# The card's own frame shows only in card mode (set_card()).
	var frame: HdPanel = %CardFrame
	frame.set_framed(false)


## Take the pack: the badge art, the portrait and this panel's own frame.
func dress(pack: ArtPack) -> void:
	super(pack)
	var frame: HdPanel = %CardFrame
	frame.dress(pack)
	# The key hints beside the buttons' words: the pack's icons, never a glyph
	# from a platform font (none of the pack's faces has a return or an expand
	# arrow, and a fallback glyph brings its own font's row height; measured on
	# Linux: `Open` 16 tall where every other row is 15).
	_key_enter_icon = pack.sprite_texture(pack.ui_sprite(ArtContract.UI_KEY_ENTER))
	var expand := pack.sprite_texture(pack.ui_sprite(ArtContract.UI_EXPAND))
	for unique: String in ["%CompactOpen", "%KeyEnter"]:
		var button: Button = get_node(unique)
		button.icon = _key_enter_icon
	for unique: String in ["%CompactMonitor", "%MonitorButton"]:
		var button: Button = get_node(unique)
		button.icon = expand
	var hint: Button = %AnswerButton
	if not _answering:
		hint.icon = _key_enter_icon
	# A pack swap is a new people family and animation library, so the portrait
	# is dressed again.
	_details().forget_look()


## Read and write through `fleet` from now on. `minimized` answers whether the
## window is minimized and `covered` whether something is drawn over the card
## (it is a compact header under the agent list); either stops the preview. The office calls this once.
func connect_fleet(fleet: HerdrFleet, minimized: Callable, covered := Callable()) -> void:
	_fleet = fleet
	_minimized = minimized
	_covered = covered


## Show `pane`, or the empty state when it is null. `machine` is the pane's
## machine, shown only when the office has more than one; `dimmed` is that
## machine having dropped, which greys the portrait and freezes it. `pick` says
## whether the viewer chose this pane themselves: only then can the switch and
## the answers be used, never for a pane the card merely follows herdr's focus
## to, nor for a terminal that took over a picked pane's id since.
func show_pane(pane: PaneModel, machine: String, dimmed: bool, pick := Pick.FOLLOWING) -> void:
	_pane = pane
	_machine = machine
	_dimmed = dimmed
	_pick = pick
	_show_stack()
	_bind(pane)
	if pane == null:
		_details().clear()
		_show_action()
		return
	var header := CardPicture.header_of(_facts(Time.get_ticks_msec()))
	_details().show_header(header, art)
	# The compact line says the same three things in the same words.
	var line: Label = %CompactLine
	line.text = header.summary
	line.tooltip_text = header.summary_tip
	# A status change is one more reason to read now, whatever the interval says.
	var status := "%s/%s" % [pane.state, pane.starting]
	if status != _last_status:
		_last_status = status
		_read_due = true
	_show_gate()
	_show_action()


## The time-in-state OfficeAttention ticks, right after the status caption.
func set_duration(text: String) -> void:
	var duration: Label = %Duration
	duration.text = text
	var wait: Label = %CompactWait
	wait.text = text


## The label the world's attention clock writes into, for the tests.
func duration_label() -> Label:
	return %Duration


## The HUD shows the panel as one line until it is opened: provider, state and
## seat, the wait, `‹ ›`, Monitor, `Open`, and NEXT. The line holds no
## preview, so the office counts a one-line panel as covered and reads nothing for it.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	# The block folds with the panel, and any confirm armed on it.
	_actions.clear()
	_show_stack()
	_word_next()


## On a screen tall enough (OfficeHud._fit_staff()), the compact panel is a
## card at the bottom-left, draft C's: the portrait, the name, the state pill
## and the seat over the line's buttons (`‹ ›`, Monitor, Open), in a frame of
## its own (%CardFrame), with NEXT at the panel's right end and the office
## showing between them. The panel's own frame is not drawn then. It is still
## the compact panel: it reads nothing (compact()), and the same nodes show.
func set_card(on: bool) -> void:
	if on == _card:
		return
	_card = on
	_show_stack()


## Whether the compact panel is a card (set_card()).
func card() -> bool:
	return _card


## Whether the panel shows its compact line (set_compact()).
func compact() -> bool:
	return _compact


## Whether the screen has room for the line's long words (`Monitor`,
## `Open`, and NEXT's `NEXT:`, whom and the wait in a row); the HUD says so
## from `staff_next_from`. Below it they are the icons and whom alone.
func set_wide(wide: bool) -> void:
	if wide == _wide:
		return
	_wide = wide
	_show_stack()
	_word_next()


## Whether NEXT stands at the panel's right end. The HUD takes it away only
## where the panel at full height would leave its preview no room.
func set_next_shown(shown: bool) -> void:
	var slot: Control = %NextSlot
	slot.visible = shown


## NEXT's width, the HUD's (its `next_width`, or `next_wide_width` on a wide line).
func set_next_width(width: float) -> void:
	var slot: Control = %NextSlot
	if slot.custom_minimum_size.x != width:
		slot.custom_minimum_size = Vector2(width, 0)


## NEXT names whom `N` picks next (OfficeNavigator.peek_next()): provider,
## floor and state in herdr's words; `next` null is nobody, and the button is
## off, and so are `‹ ›`. Its wait is OfficeAttention's to tick (set_next_wait()).
func show_next(next: NextModel) -> void:
	_next = next
	if next == null:
		set_next_wait("")
	_word_next()


## Write the NEXT pill (CardPicture.next_of()): whether anybody is next (the
## button and `‹ ›` are off with nobody), its words in the panel's form, and
## its tooltip.
func _word_next() -> void:
	var pill := CardPicture.next_of(_facts(Time.get_ticks_msec()))
	var button: Button = %NextButton
	var back: Button = %StepBack
	var on: Button = %StepOn
	var chevron: Control = %Chevron
	var play: Control = %PlayMark
	var title: Label = %NextTitle
	var line: Label = %NextLine
	button.disabled = not pill.somebody
	back.disabled = not pill.somebody
	on.disabled = not pill.somebody
	chevron.visible = pill.somebody
	play.visible = pill.somebody
	title.visible = pill.title
	button.tooltip_text = pill.tip
	line.text = pill.line
	line.theme_type_variation = &"LabelMuted" if pill.muted else &"Heading13"


## The wait under NEXT's line: `12m (N)`, `(N)` when its start is unknown,
## empty with nobody next.
func set_next_wait(text: String) -> void:
	var wait: Label = %NextWait
	if wait.text != text:
		wait.text = text


## The text NEXT shows, line and wait (a narrow line has no wait), for the tests.
func next_text() -> String:
	var line: Label = %NextLine
	var wait: Label = %NextWait
	var short := _compact and not _wide
	return line.text if wait.text.is_empty() or short else line.text + " " + wait.text


## Write the stack (CardPicture.stack_of()): the pane's details at full
## height, its compact line, the card form of it, or the empty state; the
## line's long words; and how NEXT reads (down at full height, along a wide
## line, whom alone on a narrow one). The boxes only change what shows.
func _show_stack() -> void:
	var stack := CardPicture.stack_of(_facts(Time.get_ticks_msec()))
	_shows += 1
	var mine := _shows
	_write_stack(stack)
	if _shows != mine:
		_show_stack()


func _write_stack(stack: CardPicture.Stack) -> void:
	var carded := stack.carded
	var detail: Control = %Detail
	var line: Control = %CompactRow
	detail.visible = stack.detail
	line.visible = stack.line
	# Card mode: the header (from %Detail) over the line's buttons (from
	# %CompactRow), which sit on its foot; the line's words and the rest of
	# the details stay hidden.
	for part: Control in [%Middle, %Actions]:
		part.visible = not carded
	# The header alone in the card takes the card's whole width.
	var left: Control = %Left
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL if carded else Control.SIZE_FILL
	var title: Control = %Title
	title.visible = stack.title
	_details().set_noted(not carded)
	_show_more()
	for words: Control in [%CompactLine, %CompactWait]:
		words.visible = not carded
	var monitor: Button = %CompactMonitor
	var open: Button = %CompactOpen
	monitor.text = stack.monitor_word
	open.text = stack.open_word
	set_framed(not carded)
	var frame: HdPanel = %CardFrame
	frame.set_framed(carded)
	frame.size_flags_horizontal = Control.SIZE_FILL if carded else Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size.x = card_width if carded else 0.0
	var gap: Control = %CardGap
	gap.visible = carded
	var next_button: Control = %NextButton
	next_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER if carded else Control.SIZE_EXPAND_FILL
	next_button.custom_minimum_size.y = next_pill_height if carded else 0.0
	var empty: Control = %Empty
	var no_pane: Control = %NoPane
	var message: Label = %Message
	empty.visible = stack.empty
	no_pane.visible = stack.full
	if stack.empty:
		message.text = stack.message
	var next: BoxContainer = %NextText
	var wait: Control = %NextWait
	var next_line: Label = %NextLine
	next.vertical = stack.full
	wait.visible = stack.next_wait
	next_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if stack.full else TextServer.AUTOWRAP_OFF


## The portrait's person while there is one; null in the empty state.
func portrait() -> PixelPerson:
	return _details().portrait()


## What the preview is doing now.
func preview_state() -> PreviewState:
	return _state


## Why the preview is unavailable; NONE unless preview_state() is UNAVAILABLE.
func preview_reason() -> CommandRefusal.Reason:
	return _reason if _state == PreviewState.UNAVAILABLE else CommandRefusal.Reason.NONE


## The terminal text shown, as read (cleaned, before rows are fitted).
func preview_text() -> String:
	return _text


## The caption over the preview: its source and age, or why there is none.
func preview_caption() -> String:
	var caption: Label = %PreviewCaption
	return caption.text


## The pane shown's composite key (HerdrFleet.pane_key()); empty for none. The
## HUD folds an opened panel when this changes (OfficeHud._process()).
func shown_pane_key() -> String:
	return "" if _pane == null else _pane.key


## The binding version: it moves whenever the card is aimed at another pane,
## terminal or connection, and whatever finishes for an older one is dropped.
func binding() -> int:
	return _binding


## Whether a read is in flight (there is never more than one).
func reading() -> bool:
	return _read_ticket != null


## Whether the switch is in flight.
func switching() -> bool:
	return _focus_ticket != null


## Whether an answer (keys or a line) or a start is in flight.
func writing() -> bool:
	return _input_ticket != null


## The footer under the actions: what became of the last write, or why the
## actions are off.
func outcome_text() -> String:
	var outcome: Label = %Outcome
	return outcome.text


## Whether the card is in answer mode.
func answering() -> bool:
	return _answering


## Whether answering this pane is possible right now: the heading's "Answer"
## chip shows, and Enter opens answer mode.
func answer_offered() -> bool:
	return _answer_possible()


## Why the answer keys are off, or NONE while they may be pressed.
func keys_refusal() -> CommandRefusal.Reason:
	return _input_refusal(CommandContext.Kind.KEYS)


## Why "Send line" is off for the reply typed now, or NONE while it may be pressed.
func line_refusal() -> CommandRefusal.Reason:
	return CardPicture.send_refusal(_input_refusal(CommandContext.Kind.LINE), HerdrFleet.line_refusal(_reply_text()))


## Leave answer mode and give up keyboard focus. The office calls this when a
## desk is picked and the HUD when the agent list takes the keyboard; the
## card itself on every new binding and on Escape. Sends nothing.
func leave_answer() -> void:
	_armed_binding = -1
	var box: LineEdit = %ReplyBox
	if box.has_focus():
		box.release_focus()
	var was := _answering
	_answering = false
	_aim = null
	_actions.clear()
	if was:
		_show_action()


## Answer mode for the pane shown, as a click on its chip asks: at once when
## something may be pressed now; else once this binding's next preview read is
## shown, if something may be pressed then. Either way only once, and leaving
## answer mode or a new binding forgets it. The office picks the pane first
## (a new binding leaves answer mode). Sends nothing.
func arm_answer() -> void:
	if _answering:
		return
	if _answer_possible():
		_armed_binding = -1
		_enter_answer()
		return
	_armed_binding = _binding


## A key the office has not handled yet: whether the card took it. Only
## answer mode and the one Enter that opens it are the card's; every other key
## is the office's (`T`, `N`, `A`, PageUp …), and while the reply box has focus
## nothing reaches here at all. The office asks this first.
func take_key(event: InputEvent) -> bool:
	if not event is InputEventKey or not _keys_are_mine():
		return false
	# Exact: Shift, Ctrl, Alt or Meta with any of these is not them.
	if event.is_action(&"card_answer", true):
		if event.is_action_pressed(&"card_answer", false, true) and not _answering and _answer_possible():
			_enter_answer()
		# Enter on a picked agent's card is the card's, pressed, held or released,
		# and never sends.
		return true
	return _answer_key(event) if _answering else false


## Whether keys may be the card's at all: a picked agent on an operator card,
## on screen and uncovered, and the reply box not holding the keyboard (Escape
## leaves it focused but not editing: no key of it ever answers then either).
func _keys_are_mine() -> bool:
	var box: LineEdit = %ReplyBox
	return _may_answer() and is_visible_in_tree() and not _out_of_sight() and not box.has_focus()


## A key in answer mode: Escape leaves, `N` leaves and lets the office move on,
## 1–9 and y are sent on their press (echo and release are taken, and do
## nothing) when both the key's position and the layout's key say so. Every
## other key is the office's.
func _answer_key(event: InputEvent) -> bool:
	if event.is_action(&"card_leave", true):
		if event.is_action_pressed(&"card_leave", false, true):
			leave_answer()
		return true
	if event.is_action_pressed(&"office_next_attention"):
		# "Next", never "n".
		leave_answer()
		return false
	var key := event as InputEventKey
	for action: StringName in KEY_ACTIONS:
		if event.is_action(action, true):
			# The position and what the layout makes of it, both (KEY_CODES);
			# never the character typed. Anything else is the office's key.
			if key.keycode != KEY_CODES[action]:
				return false
			if event.is_action_pressed(action, false, true):
				_key_pressed(KEY_ACTIONS[action])
			return true
	return false


func _process(delta: float) -> void:
	if _pane == null:
		return
	if _read_ticket == null and not _read_due:
		_next_read_in -= delta
		if _next_read_in <= 0.0:
			_read_due = true
	# A ticket signals only its end: its re-read passing (UNSENT to SENT) is
	# seen here, so the footer moves on from "Checking the screen…".
	if _input_ticket != null and CardWords.input_progress(_input_ticket) != outcome_text():
		_show_action()
	if _actions.expire(Time.get_ticks_msec()):
		_show_launch()
	# How this pane's start is going changes with time too (its seconds, the deadline).
	_launch_tick -= delta
	if _launch_tick <= 0.0:
		_launch_tick = LAUNCH_TICK
		var line := _actions.launch_line(_view())
		if ("" if line == null else line.text) != _launch_said:
			_show_action()
	# An unavailable preview waits for the refresh that makes it readable again
	# (_show_gate()): whatever closed it announces its change with one.
	if _read_due and _read_ticket == null and _state != PreviewState.UNAVAILABLE and _may_read():
		_start_read()
	_show_age()


# --- binding ------------------------------------------------------------------


## A new pane, terminal or connection is a new binding: nothing aimed at the
## old one is sent, and nothing that finishes for it is shown. Answer mode ends
## and the reply box lets go; each pane's draft stays its own.
func _bind(pane: PaneModel) -> void:
	var generation := -1 if pane == null or _fleet == null else _fleet.generation(pane.machine())
	var bound := "" if pane == null else JSON.stringify([pane.key, pane.identity_key(), generation])
	if bound == _bound:
		return
	_bound = bound
	_binding += 1
	_read_context = null
	_actions.clear()
	# A branch typed for one pane never follows the card to another.
	var branch: LineEdit = _block().branch_box()
	if branch.has_focus():
		branch.release_focus()
	branch.text = ""
	# An answer button still held down: its release will find nothing to send.
	var held := _aim != null and is_instance_valid(_aim.button) and _aim.button.is_pressed()
	leave_answer()
	_switch_draft(pane)
	# A press aimed at the old binding keeps its context: its release is checked
	# against the binding and dropped, saying why (_on_focus_pressed()).
	_outcome = ""
	_outcome_detail = ""
	_outcome_identity = ""
	# A write to this pane that ended and has not been looked at yet is still
	# news, whatever card was shown when it ended.
	if pane != null and _fleet != null and _fleet.must_look(pane.key):
		var last := _fleet.last_write(pane.key)
		# A start's own news is the footer's launch line (_launch_line()).
		if last != null and not _launch_speaks_for(last):
			_outcome = CardWords.write_outcome(last)
			_outcome_detail = CardWords.write_outcome_detail(last)
			_outcome_identity = last.context.identity_key
	if held:
		# Said on the new binding, like the switch's: nothing went anywhere.
		_outcome = CardWords.TARGET_CHANGED
		_outcome_detail = CardWords.HELD_DETAIL
		_outcome_identity = ""
	_last_status = ""
	_text = ""
	_source = ""
	_cut = false
	_read_at = -1
	_reason = CommandRefusal.Reason.NONE
	_next_read_in = 0.0
	# The card opened on a pane: read it at once.
	_read_due = pane != null
	if pane != null and _fleet != null:
		_read_context = _fleet.context_for(pane.key, _binding)
	_set_state(PreviewState.NONE if pane == null else PreviewState.LOADING)


# --- the preview --------------------------------------------------------------


## Why nothing may be read now, or NONE: no fleet, read-only, or anything the
## command boundary would refuse a read of this pane for.
func _gate() -> CommandRefusal.Reason:
	if _pane == null or _fleet == null:
		return CommandRefusal.Reason.NOT_CONNECTED
	if _fleet.read_only():
		return CommandRefusal.Reason.READ_ONLY
	return _fleet.can_operate(_pane.key, CommandContext.Kind.READ)


## Show whether the pane can be read at all; a refresh calls this.
func _show_gate() -> void:
	var reason := _gate()
	if reason != CommandRefusal.Reason.NONE:
		_reason = reason
		_text = ""
		_set_state(PreviewState.UNAVAILABLE)
	elif _state == PreviewState.UNAVAILABLE:
		_read_due = true
		_set_state(PreviewState.LOADING)


## Reads happen only while the card is on screen and nothing covers it (the
## window is not minimized, the card is not a compact header), and the machine
## is live and current with this pane readable.
func _may_read() -> bool:
	if _read_context == null or not is_visible_in_tree() or _out_of_sight():
		return false
	return _gate() == CommandRefusal.Reason.NONE


## Whether the window is minimized or something covers the card.
func _out_of_sight() -> bool:
	for out_of_sight: Callable in [_minimized, _covered]:
		if out_of_sight.is_valid():
			var answer: bool = out_of_sight.call()
			if answer:
				return true
	return false


## A blocked pane is read from what herdr's detection sees, the whole of it; the
## rest from the recent output, as many rows as the preview shows.
func _start_read() -> void:
	_read_due = false
	_read_seq += 1
	# An agent still launching and already asking (a trust prompt) is read like
	# any blocked one: its keys are checked against the whole question.
	var blocked := _pane.state == str(ArtContract.STATE_BLOCKED)
	var context := (
		_read_context.reading(CommandContext.SOURCE_DETECTION, BLOCKED_LINES)
		if blocked
		else _read_context.reading(CommandContext.SOURCE_RECENT, PREVIEW_ROWS)
	)
	var ticket := _fleet.read_pane(context)
	_read_ticket = ticket
	ticket.finished.connect(_on_read_finished.bind(ticket, _binding, _read_seq), CONNECT_ONE_SHOT)


func _on_read_finished(ticket: CommandTicket, binding_then: int, seq: int) -> void:
	if ticket == _read_ticket:
		_read_ticket = null
	# A reply for an older binding or an older read is dropped, whatever it says.
	if binding_then != _binding or seq != _read_seq:
		return
	# A chip's click waits for this read, whatever it brings (arm_answer()).
	var armed := _armed_binding == _binding
	_armed_binding = -1
	var blocked := _pane != null and _pane.state == str(ArtContract.STATE_BLOCKED)
	_next_read_in = BLOCKED_INTERVAL if blocked else QUIET_INTERVAL
	# Whatever the read brought, a pane that may not be read now says why: text
	# from a machine that just dropped is not live, and its lost read is not a
	# failure of the read.
	var gate := _gate()
	if gate != CommandRefusal.Reason.NONE:
		_reason = gate
		_text = ""
		_set_state(PreviewState.UNAVAILABLE)
		return
	match ticket.state:
		CommandTicket.State.ACCEPTED:
			_text = ticket.read.text
			_source = ticket.context.source
			_cut = ticket.read.truncated or ticket.read.cut
			_read_at = Time.get_ticks_msec()
			_set_state(PreviewState.SHOWN, null, ticket, seq)
			# Shown: after a write, this may be the look that turns writes back on.
			_fleet.preview_shown(ticket)
			# Looked at on another terminal than the write's: that outcome is done with.
			if _foreign_outcome() and not _fleet.must_look(_pane.key):
				_outcome = ""
				_outcome_detail = ""
				_outcome_identity = ""
			_show_action()
			if armed and not _answering and _answer_possible():
				_enter_answer()
		CommandTicket.State.REFUSED:
			_reason = ticket.refusal
			_text = ""
			_set_state(PreviewState.UNAVAILABLE)
		_:
			_text = ""
			_set_state(PreviewState.FAILED, ticket)


## Move the preview to `next`. A FAILED preview names the `failed` read; a
## SHOWN one is `shown`, sequence `seq`, which a press would freeze.
func _set_state(next: PreviewState, failed: CommandTicket = null, shown: CommandTicket = null, seq := 0) -> void:
	_state = next
	_shown_ticket = shown if next == PreviewState.SHOWN else null
	_shown_seq = seq if next == PreviewState.SHOWN else 0
	_read_failed = failed if next == PreviewState.FAILED else null
	_show_preview()
	_show_answer()
	_show_launch()


## Write the preview (CardPicture.preview_of()): its rows, then, the rows
## measured, the caption over them.
func _show_preview() -> void:
	var picture := CardPicture.preview_of(_facts(Time.get_ticks_msec()))
	var preview: Label = %Preview
	if preview.text != picture.rows:
		preview.text = picture.rows
	_measure_rows()
	_show_caption()


## Write the caption over the preview: the source and age of shown text and
## whether it was cut or clipped, or why there is none.
func _show_caption() -> void:
	var picture := CardPicture.preview_of(_facts(Time.get_ticks_msec()))
	_caption_seconds = picture.seconds
	var caption: Label = %PreviewCaption
	caption.text = picture.caption
	caption.tooltip_text = picture.caption_tip


## The caption of shown text says how old it is: written again only when the
## number of seconds changes.
func _show_age() -> void:
	if _state != PreviewState.SHOWN:
		return
	if CardPicture.age_seconds(_read_at, Time.get_ticks_msec()) == _caption_seconds:
		return
	_show_caption()


## How many of the rows shown are wider than the preview, which clips them.
func _measure_rows() -> void:
	var preview: Label = %Preview
	var font := preview.get_theme_font("font")
	var font_size := preview.get_theme_font_size("font_size")
	var clipped := 0
	if font != null and preview.size.x > 0.0:
		for row in preview.text.split("\n"):
			var width := font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if not row.is_empty() and width > preview.size.x:
				clipped += 1
	if clipped != _rows_clipped:
		_rows_clipped = clipped
		_caption_seconds = -1
		_show_age()


# --- the switch ---------------------------------------------------------------


## "Monitor": ask for the terminal monitor on the pane shown. It opens and
## reads nothing on its own; the office decides.
func _on_monitor_pressed() -> void:
	if _pane != null:
		monitor_requested.emit(_pane.key)


## The second press of a double click is not a second gesture.
func _on_double_click(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).double_click:
		button.accept_event()


## Aim the switch at the press, from what the fleet knows this instant.
func _on_focus_down() -> void:
	_focus_context = null
	if _pane == null or _fleet == null or _pick != Pick.PICKED:
		return
	_focus_context = _fleet.context_for(_pane.key, _binding).focusing()


## Send it at the release, unless the card was aimed elsewhere in between.
func _on_focus_pressed() -> void:
	var context := _focus_context
	_focus_context = null
	if context == null:
		return
	if context.binding != _binding or _pane == null or context.pane_key != _pane.key or _pick != Pick.PICKED:
		_outcome = CardWords.TARGET_CHANGED
		_outcome_detail = CardWords.SWITCH_MOVED_DETAIL
		_outcome_identity = ""
		_show_action()
		return
	var ticket := _fleet.focus_pane(context)
	_focus_ticket = ticket
	ticket.finished.connect(_on_write_finished.bind(ticket), CONNECT_ONE_SHOT)
	_show_action()


## A write of this card (the switch or an answer) ended. It is news on the
## card whenever the card shows its pane, even under a newer binding (left and
## came back while it was out, or the write changed the pane's terminal or
## session); for another pane the boundary keeps it, and the card shows it on
## coming back to that pane before it is looked at. A line that went, or may
## have, stops being a draft either way.
func _on_write_finished(ticket: CommandTicket) -> void:
	if ticket == _focus_ticket:
		_focus_ticket = null
	if ticket == _input_ticket:
		_input_ticket = null
	if (
		ticket.context.kind == CommandContext.Kind.LINE
		and ticket.state in [CommandTicket.State.ACCEPTED, CommandTicket.State.UNKNOWN]
	):
		# The line went, or may have: it is no draft any more, whichever pane
		# the card shows now.
		_forget_draft(ticket.context)
	# Its pane's news whatever binding the card is on now: one that left and
	# came back while the write was out says what became of it.
	if ticket.split != null and ticket.state == CommandTicket.State.ACCEPTED:
		# The office picks the new pane once it shows, whatever this card shows now.
		var context := ticket.context
		_pending_outcome = CardWords.write_outcome(ticket)
		pane_split.emit(context.pane_key, ticket.split.pane_id, ticket.split.terminal_id, context.generation)
	if ticket.space != null and ticket.state == CommandTicket.State.ACCEPTED:
		# The office picks the new zone's shell once it shows, likewise.
		var made := ticket.context
		_pending_outcome = CardWords.write_outcome(ticket)
		space_created.emit(
			made.pane_key, ticket.space.workspace_id, ticket.space.pane_id, ticket.space.terminal_id, made.generation
		)
	if _pane != null and ticket.context.pane_key == _pane.key:
		_outcome = CardWords.write_outcome(ticket)
		_outcome_detail = CardWords.write_outcome_detail(ticket)
		_outcome_identity = ticket.context.identity_key
		if _launch_speaks_for(ticket):
			# Taken, or maybe: the footer's launch line says how it goes from here.
			_outcome = ""
			_outcome_detail = ""
			_outcome_identity = ""
		var written := (
			ticket.state in [CommandTicket.State.ACCEPTED, CommandTicket.State.REJECTED, CommandTicket.State.UNKNOWN]
		)
		if written and ticket.context.kind != CommandContext.Kind.FOCUS:
			# Each answer that reached herdr ends answer mode; one refused before
			# any write leaves it open, saying why.
			leave_answer()
		# Look before writing again: the next read that may count starts late enough.
		if _read_ticket == null:
			_read_due = false
			_next_read_in = maxf(_next_read_in, LOOK_WAIT)
	_show_action()


## The switch, its note and the footer, the heading's answer chip, answer
## mode and the launch block: everything a refresh, a gesture or a write's end
## can have moved.
##
## The stateful step comes first and is the card's: the launch block drops
## the confirms that hold no more and fixes the kinds offered in their order
## (_show_launch()), and the launch line notes which card first said a start
## was over (CardActions.launch_line()). The picture after it is pure.
func _show_action() -> void:
	_show_launch()
	var view := _view()
	var launch := _actions.launch_line(view)
	_launch_said = "" if launch == null else launch.text
	var facts := _facts(view.now_msec)
	_refusals(facts)
	facts.launch_line = _launch_said
	facts.launch_detail = "" if launch == null else launch.detail
	_shows += 1
	var mine := _shows
	_write_answer(CardPicture.answer_of(facts))
	_write_actions(CardPicture.actions_of(facts))
	if _shows != mine:
		_show_action()


## Write the switch, its note, Monitor, `▾ Esc` and the footer. A card that
## may not write shows none of the words under it: they keep what they said.
func _write_actions(actions: CardPicture.Actions) -> void:
	var button: Button = %FocusButton
	var note: Label = %FocusNote
	var outcome: Label = %Outcome
	button.visible = actions.focus
	note.visible = actions.focus
	outcome.visible = actions.offered
	var monitor: Button = %MonitorButton
	var line_monitor: Button = %CompactMonitor
	monitor.visible = actions.monitor
	line_monitor.visible = actions.monitor
	var fold: Button = %FoldButton
	fold.visible = actions.fold
	var top: Control = %TopRow
	top.visible = actions.top
	button.disabled = actions.focus_off
	if not actions.offered:
		return
	outcome.text = actions.footer
	outcome.tooltip_text = actions.footer_tip
	button.text = actions.focus_text
	button.tooltip_text = actions.focus_tip


## What the card shows this instant, as the picture's facts: what the office
## showed, what the card remembers and what its nodes measure, at `now_msec`.
## Nothing here asks the fleet about a write (_refusals() does), and nothing
## is changed by asking.
func _facts(now_msec: int) -> CardPicture.Facts:
	var facts := CardPicture.Facts.new()
	facts.pane = _pane
	facts.machine = _machine
	facts.dimmed = _dimmed
	facts.pick = _pick
	if _pane != null:
		var state := StringName(_pane.state)
		facts.state_caption = CardDetails.caption_of(art, state)
		facts.state_badge = CardDetails.badge_of(art, state)
	facts.connected = _fleet != null
	facts.read_only = _fleet != null and _fleet.read_only()
	facts.compact = _compact
	facts.card = _card
	facts.wide = _wide
	facts.answering = _answering
	facts.launch_shown = _block().visible
	facts.narrow = size.x < details_beside_launch_from
	facts.next = _next
	facts.next_tip = _next_tip
	facts.preview = _state
	facts.preview_reason = _reason
	facts.preview_failed = _read_failed
	facts.text = _text
	facts.source = _source
	facts.cut = _cut
	facts.rows_clipped = _rows_clipped
	facts.read_at_msec = _read_at
	facts.now_msec = now_msec
	facts.switching = _focus_ticket != null
	facts.input = _input_ticket
	facts.outcome = _outcome
	facts.outcome_detail = _outcome_detail
	facts.outcome_identity = _outcome_identity
	facts.reply = _reply_text()
	return facts


## The fleet's answers about a write, told to the picture's `facts`: why the
## switch, a key and a line may not be pressed now, whether answer mode has
## anything to press, and what the reply typed is refused for. The one place
## the facts get a refusal from.
func _refusals(facts: CardPicture.Facts) -> void:
	facts.switch_refusal = _switch_refusal()
	facts.keys_refusal = _input_refusal(CommandContext.Kind.KEYS)
	facts.line_refusal = _input_refusal(CommandContext.Kind.LINE)
	facts.answer_possible = _answer_possible()
	facts.reply_refusal = HerdrFleet.line_refusal(facts.reply)
	facts.line_bytes_max = HerdrFleet.line_bytes_max()


## Why the switch may not go to the pane shown now, or NONE: no fleet or pane,
## read-only, or what the boundary says of a write there.
func _switch_refusal() -> CommandRefusal.Reason:
	if _pane == null or _fleet == null:
		return CommandRefusal.Reason.NOT_CONNECTED
	if _fleet.read_only():
		return CommandRefusal.Reason.READ_ONLY
	return _fleet.can_operate(_pane.key)


## Whether the footer's outcome is a write to another terminal than the one
## bound now (the pane id was taken over since): never said as this one's. The
## look it owes still holds (keyed by the pane), and says so as "No writes".
func _foreign_outcome() -> bool:
	return CardPicture.foreign(_outcome_identity, _pane)


## Whether any write of this card is on its way. Every write control waits.
func _write_in_flight() -> bool:
	return _focus_ticket != null or _input_ticket != null


# --- answer mode --------------------------------------------------------------


## Whether this card may offer answers at all: a fleet that writes, a pane the
## viewer picked, and an agent in it (never a shell).
func _may_answer() -> bool:
	if _pane == null or _fleet == null or _fleet.read_only() or _pick != Pick.PICKED:
		return false
	return not _pane.provider.is_empty()


## Whether answer mode has anything that may be pressed now.
func _answer_possible() -> bool:
	if not _may_answer():
		return false
	return (
		_input_refusal(CommandContext.Kind.KEYS) == CommandRefusal.Reason.NONE
		or _input_refusal(CommandContext.Kind.LINE) == CommandRefusal.Reason.NONE
	)


## Why an input of `kind` may not be pressed now, or NONE: this card's own
## state, what the boundary says about the pane (its state, an open write, a
## look still owed), and whether the preview shows what that input is checked
## against (CardActions.ladder()).
func _input_refusal(kind: CommandContext.Kind) -> CommandRefusal.Reason:
	var own := _card_refusal()
	# A card that refuses by itself may have no fleet or pane: the fleet is not asked.
	var seam := CommandRefusal.Reason.NONE
	if own == CommandRefusal.Reason.NONE:
		seam = _fleet.command_refusal(_pane.key, kind)
	var frozen := CommandPreview.of(_shown_ticket, _shown_seq)
	return CardActions.ladder(kind, own, seam, _state == PreviewState.SHOWN, frozen)


## No fleet or pane, read-only, a pane the viewer did not pick, or a write of
## this card still on its way.
func _card_refusal() -> CommandRefusal.Reason:
	if _pane == null or _fleet == null:
		return CommandRefusal.Reason.NOT_CONNECTED
	if _fleet.read_only():
		return CommandRefusal.Reason.READ_ONLY
	if _pick != Pick.PICKED:
		return CommandRefusal.Reason.IDENTITY_CHANGED if _pick == Pick.REPLACED else CommandRefusal.Reason.UNSEEN
	if _write_in_flight():
		return CommandRefusal.Reason.IN_FLIGHT
	return CommandRefusal.Reason.NONE


## Whether the preview shows uncut text from the source `kind` is checked
## against: the whole `detection` text for keys, the recent output for a line.
func _shown_refusal(kind: CommandContext.Kind) -> CommandRefusal.Reason:
	var frozen := CommandPreview.of(_shown_ticket, _shown_seq)
	return CardActions.shown_refusal(kind, _state == PreviewState.SHOWN, frozen)


func _enter_answer() -> void:
	_answering = true
	# The block goes with answer mode, and any confirm armed on it.
	_actions.clear()
	_show_action()


## The heading chip: opens answer mode, or leaves it.
func _on_answer_button() -> void:
	if _answering:
		leave_answer()
	elif _answer_possible():
		_enter_answer()


## Answer mode's chip, title, keys and "Send line", as the preview's state
## leaves them (_set_state()).
func _show_answer() -> void:
	var facts := _facts(Time.get_ticks_msec())
	_refusals(facts)
	_shows += 1
	var mine := _shows
	_write_answer(CardPicture.answer_of(facts))
	if _shows != mine:
		_show_answer()


## Write everything answer mode shows, and which parts of the card it hides.
## Only `visible`, `disabled`, text and tooltips change: the scene holds the
## layout.
func _write_answer(answer: CardPicture.Answer) -> void:
	var title: Label = %Title
	var hint: Button = %AnswerButton
	var header: Control = %Header
	var controls: Control = %Answer
	hint.visible = answer.chip
	hint.text = answer.chip_text
	hint.icon = _key_enter_icon if answer.chip_keyed else null
	hint.tooltip_text = answer.chip_tip
	header.visible = true
	_show_more()
	controls.visible = answer.open
	# Answer mode is a modal (OfficeHud._fit_staff()) laid out top to bottom:
	# who and where, the terminal across the whole panel, the keys and the
	# reply under it, the actions and what became of the last write along the
	# foot. The same nodes, only the boxes turn: nothing moves between parents.
	var detail: BoxContainer = %Detail
	var middle: BoxContainer = %Middle
	var actions: BoxContainer = %Actions
	detail.vertical = answer.open
	middle.vertical = answer.open
	actions.vertical = not answer.open
	title.visible = answer.title
	title.text = answer.title_text
	title.tooltip_text = answer.title_tip
	for key: Button in _key_buttons():
		key.disabled = answer.keys_off
		key.tooltip_text = answer.key_tip(_key_of(key))
	var send_line: Button = %SendLine
	send_line.disabled = answer.line_off
	send_line.tooltip_text = answer.line_tip
	var best: Label = %BestEffort
	best.text = answer.best_effort


## Every button that sends a key, in the scene's order.
func _key_buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child in (%Digits as Container).get_children():
		if child is Button:
			found.append(child)
	for unique: String in ["%KeyY", "%KeyN", "%KeyEnter", "%SendEsc"]:
		found.append(get_node(unique))
	return found


## The key name a key button sends: its own label, but Enter (an icon) and "Send Esc" by name.
func _key_of(button: Button) -> String:
	if button == %KeyEnter:
		return "enter"
	if button == %SendEsc:
		return "esc"
	return button.text


## Aim at the press, send at the release; a double click's second press is none.
func _wire_input(button: Button, kind: CommandContext.Kind, key_name: String) -> void:
	button.button_down.connect(_on_input_down.bind(button, kind, key_name))
	button.pressed.connect(_on_input_pressed.bind(button))
	button.gui_input.connect(_on_double_click.bind(button))


## Aim an answer at the press: the target, the payload and the preview shown
## this instant, frozen.
func _on_input_down(button: Button, kind: CommandContext.Kind, key_name: String) -> void:
	_aim = null
	if kind in FROM_THE_BLOCK:
		_aim = _aim_from_block(kind, button)
		return
	if kind == CommandContext.Kind.LINE and _composing():
		_refuse_line(CommandRefusal.Reason.LINE_COMPOSING)
		return
	var context := _aimed(kind, key_name)
	if context == null:
		return
	var aim := CardActions.Aim.new()
	aim.context = context
	aim.button = button
	_aim = aim


## What a press on one of the launch block's buttons aims (CardActions), or
## null when it may not be pressed.
func _aim_from_block(kind: CommandContext.Kind, button: Button) -> CardActions.Aim:
	var view := _view()
	match kind:
		CommandContext.Kind.START:
			return _actions.aim_start(view, button, _block().kind_buttons().find(button))
		CommandContext.Kind.SPLIT:
			return _actions.aim_split(view, button)
		CommandContext.Kind.CLOSE:
			return _actions.aim_close(view, button)
		CommandContext.Kind.SPACE:
			return _actions.aim_space(view, button)
		CommandContext.Kind.WORKTREE:
			return _actions.aim_worktree(view, button)
	return null


## Send it at the release, unless the card was aimed elsewhere or shows another
## read in between.
func _on_input_pressed(button: Button) -> void:
	var aim := _aim
	_aim = null
	if aim == null or aim.button != button:
		return
	if not aim.arms.is_empty():
		_actions.arm(_view(), aim)
		_show_launch()
		return
	if aim.arms_close:
		_actions.arm_close(_view(), aim)
		_show_launch()
		return
	_release(aim.context)


## A key of answer mode's keyboard: aimed and sent at once (its echo and its
## release do nothing, see take_key()).
func _key_pressed(key_name: String) -> void:
	var context := _aimed(CommandContext.Kind.KEYS, key_name)
	if context != null:
		_release(context)


## The command an answer press aims, or null when it may not be pressed.
func _aimed(kind: CommandContext.Kind, key_name: String) -> CommandContext:
	if not _answering or _input_refusal(kind) != CommandRefusal.Reason.NONE:
		return null
	var frozen := CommandPreview.of(_shown_ticket, _shown_seq)
	if frozen == null:
		return null
	var target := _fleet.context_for(_pane.key, _binding)
	if kind == CommandContext.Kind.KEYS:
		return target.keying(key_name, frozen)
	return target.replying(_reply_text(), frozen)


## Hand an aimed answer to the fleet, unless the card moved on since the press.
func _release(context: CommandContext) -> void:
	var launch := context.kind in FROM_THE_BLOCK
	# An answer goes from answer mode, a start or a split from outside it (the
	# block is not there in answer mode).
	var wrong_mode := _answering if launch else not _answering
	if (
		context.binding != _binding
		or _pane == null
		or context.pane_key != _pane.key
		or _pick != Pick.PICKED
		or wrong_mode
	):
		_outcome = "Not sent: target changed"
		_outcome_detail = "Nothing was sent: the card moved to another pane, terminal or mode between press and release."
		_outcome_identity = ""
		_show_action()
		return
	if context.kind == CommandContext.Kind.LINE:
		# Exactly the line aimed at the press, fully typed: nothing composed or
		# typed while the button was held goes out unseen.
		if _composing():
			_refuse_line(CommandRefusal.Reason.LINE_COMPOSING)
			return
		if context.line != _reply_text():
			_refuse_line(CommandRefusal.Reason.LINE_EDITED)
			return
	if context.kind == CommandContext.Kind.CLOSE and not _actions.close_confirm_holds(_view()):
		# The ten seconds, the scope and the block are checked at the release
		# too: a press held across the deadline sends nothing.
		_refuse_line(CommandRefusal.Reason.CONFIRM_NEEDED)
		return
	if context.kind == CommandContext.Kind.WORKTREE and context.branch != _branch_text():
		# Exactly the branch aimed at the press: nothing typed while the button
		# was held goes out unseen.
		_refuse_line(CommandRefusal.Reason.BRANCH_EDITED)
		return
	# A split, a close, a space or a worktree reads no screen: none is checked against one.
	var reads := not (
		context.kind
		in [
			CommandContext.Kind.SPLIT,
			CommandContext.Kind.CLOSE,
			CommandContext.Kind.SPACE,
			CommandContext.Kind.WORKTREE
		]
	)
	if reads and (context.seen == null or _shown_ticket == null or context.seen.read_seq != _shown_seq):
		_outcome = "Not sent: " + CommandRefusal.text(CommandRefusal.Reason.SCREEN_CHANGED)
		_outcome_detail = ("Nothing was sent: the preview showed a newer read between your press and release. Look at it first.")
		_outcome_identity = ""
		_show_action()
		return
	var ticket: CommandTicket
	match context.kind:
		CommandContext.Kind.KEYS:
			ticket = _fleet.send_keys(context)
		CommandContext.Kind.START:
			# Spent: whatever becomes of it, another start is another two clicks.
			_actions.confirm = null
			ticket = _fleet.start_agent(context)
		CommandContext.Kind.SPLIT:
			ticket = _fleet.split_pane(context)
		CommandContext.Kind.CLOSE:
			# Spent likewise: another close is another two clicks.
			_actions.close_confirm = null
			ticket = _fleet.close_pane(context)
		CommandContext.Kind.SPACE:
			ticket = _fleet.create_space(context)
		CommandContext.Kind.WORKTREE:
			ticket = _fleet.create_worktree(context)
		_:
			ticket = _fleet.send_line(context)
	_input_ticket = ticket
	_outcome = ""
	_outcome_detail = ""
	_outcome_identity = ""
	ticket.finished.connect(_on_write_finished.bind(ticket), CONNECT_ONE_SHOT)
	_show_action()


# --- launching ------------------------------------------------------------------


## What the launch block offers for the pane shown: nothing; a start, in a
## shell the viewer picked, on an office that writes, at full height, out of
## answer mode, on a live machine with a current snapshot and no start
## launching there yet; or, for an agent there, a new pane beside it.
func _launch_form() -> Form:
	if _pane == null or _fleet == null or _fleet.read_only() or _compact or _answering or _pick != Pick.PICKED:
		return Form.NONE
	if _dimmed or not _fleet.snapshot_is_current(_pane.machine()):
		# Nothing to offer on a machine that dropped or has not spoken yet: no
		# block at all, not a row of buttons that are all off.
		return Form.NONE
	if _pane.starting:
		# A start under way neither starts nor splits; it can still be closed.
		return Form.MANAGE_ONLY
	return Form.START if _pane.provider.is_empty() else Form.SPLIT


## The launch block (LaunchBlock): for a shell a button per kind the machine
## shows, why each is off, and the confirm a first click on an unsure prompt
## armed, while it holds; for an agent the split; under either, or alone, the
## manage rows (Close pane with its two-click confirm, New space, New worktree).
func _show_launch() -> void:
	var block := _block()
	var form := _launch_form()
	var view := _view()
	if _actions.confirm != null and not _actions.confirm_holds(view, _actions.confirm.kind):
		_actions.confirm = null
	if _actions.close_confirm != null and not _actions.close_confirm_holds(view):
		_actions.close_confirm = null
	var on := "" if _machine.is_empty() else " on " + _machine
	match form:
		Form.NONE:
			_actions.launch_kinds = PackedStringArray()
			block.close()
		Form.SPLIT:
			_actions.launch_kinds = PackedStringArray()
			var side := _fleet.split_direction(_pane.key)
			block.show_split(_pane.provider, _pane.pane_id, side, _actions.split_refusal(view), on)
		Form.MANAGE_ONLY:
			_actions.launch_kinds = PackedStringArray()
			block.show_manage_only()
		Form.START:
			_actions.launch_kinds = _fleet.agent_kinds(_pane.machine())
			var prompt := HerdrFleet.prompt_state(view.frozen)
			var offers: Array[LaunchBlock.Offer] = []
			for kind in _actions.launch_kinds.slice(0, KINDS_MAX):
				var offer := LaunchBlock.Offer.new()
				offer.kind = kind
				offer.agent_name = _fleet.next_agent_name(_pane.machine(), kind)
				offer.reason = _actions.launch_refusal(view, kind, prompt, _actions.confirm_holds(view, kind))
				offers.append(offer)
			var confirm := _actions.confirm
			var confirm_kind := "" if confirm == null else confirm.kind
			var confirm_line := "" if confirm == null else confirm.last_line
			block.show_start(offers, on, _fleet.label(_pane.machine()), confirm_kind, confirm_line)
	if form != Form.NONE:
		block.show_manage(_actions.manage_words(view, on, _fleet.label(_pane.machine())))
	_show_more()


## What the card shows this instant, for the aiming family (CardActions.View):
## values only, the fleet's answers about the pane among them, asked now for
## the kinds the block's form may press. Built anew at every call, a press and
## a release included: every answer in it was asked at that call. Only the
## list of kinds the block still offers (its buttons) comes from the last look.
func _view() -> CardActions.View:
	var view := CardActions.View.new()
	view.pane = _pane
	view.binding = _binding
	view.form = _launch_form()
	view.frozen = CommandPreview.of(_shown_ticket, _shown_seq)
	view.shown = _state == PreviewState.SHOWN
	view.text = _text
	view.card_refusal = _card_refusal()
	view.branch = _branch_text()
	view.machine = _machine
	view.now_msec = Time.get_ticks_msec()
	if _fleet != null and _pane != null:
		view.answers = _fleet.answers(_pane.key, _binding, CardActions.asked(view.form), _actions.launch_kinds)
	return view


func _branch_text() -> String:
	return _block().branch_box().text


## The branch box changed: the worktree button and the note follow the text.
func _on_branch_changed(_text_now: String) -> void:
	_show_launch()


## Escape in the branch box only lets the box go; Enter, which the box takes
## as "submit", sends nothing (nothing is wired to it).
func _on_branch_input(event: InputEvent) -> void:
	var box: LineEdit = _block().branch_box()
	if box.has_ime_text():
		return
	if event.is_action_pressed(&"card_leave"):
		box.accept_event()
		box.release_focus()


## The card's launch block.
func _block() -> LaunchBlock:
	return %Launch


## The office did not pick pane `pane_id`, made by a split of pane
## `target_key` from this card, for `why`: while the card shows that pane and
## its footer still names the new one, it says so. Nothing is retried, and
## nothing is picked.
func new_pane_not_picked(target_key: String, pane_id: String, why: Unpicked) -> void:
	if _pane == null or _pane.key != target_key or _pending_outcome.is_empty() or _outcome != _pending_outcome:
		return
	_outcome = CardWords.NEW_PANE_UNPICKED[why] % _pending_outcome
	_outcome_detail = CardWords.unpicked_detail(why, pane_id)
	_pending_outcome = ""
	_show_action()


## Whether `ticket` is a start this run remembers as the pane's launch: its
## news is the footer's launch line, not a write outcome.
func _launch_speaks_for(ticket: CommandTicket) -> bool:
	if ticket == null or ticket.context == null or ticket.context.kind != CommandContext.Kind.START or _fleet == null:
		return false
	var watch := _fleet.launch_of(ticket.context.pane_key)
	return watch != null and watch.ticket == ticket


## PANE's details give the START AGENT block their room on a narrow card
## (details_beside_launch_from), and answer mode's controls theirs always.
func _show_more() -> void:
	var more: Control = %More
	more.visible = CardPicture.more_of(_facts(Time.get_ticks_msec()))


# --- the reply box --------------------------------------------------------------


func _reply_text() -> String:
	var box: LineEdit = %ReplyBox
	return box.text


## Whether an input method is composing in the reply box: its text is not the line yet.
func _composing() -> bool:
	var box: LineEdit = %ReplyBox
	return box.has_ime_text()


## "Send line" refused on the card itself, before anything reaches the fleet.
func _refuse_line(reason: CommandRefusal.Reason) -> void:
	_outcome = CardWords.not_sent(reason)
	_outcome_detail = CardWords.not_sent_detail(reason)
	_outcome_identity = ""
	_show_action()


## Escape in the box leaves answer mode and the box (a box left focused but not
## editing would pass the next digit on as an answer key); Tab never moves on
## (the scene points every neighbour back at the box); Enter, which the box
## takes as "submit", sends nothing, and neither does an IME's composing Enter.
func _on_reply_input(event: InputEvent) -> void:
	var box: LineEdit = %ReplyBox
	if box.has_ime_text():
		return
	if event.is_action_pressed(&"card_leave"):
		box.accept_event()
		leave_answer()


func _on_draft_changed(_text_now: String) -> void:
	if not _draft_key.is_empty():
		_keep_draft(_draft_key, _draft_pane, _reply_text())
	_show_action()


## Keep the box's text for the pane the card leaves, and show the one kept for
## `pane` (empty for a pane never typed for). A draft for a terminal that no
## longer holds its pane id is dropped: it never shows for another terminal.
func _switch_draft(pane: PaneModel) -> void:
	var box: LineEdit = %ReplyBox
	if not _draft_key.is_empty():
		_keep_draft(_draft_key, _draft_pane, box.text)
	_draft_key = "" if pane == null else JSON.stringify([pane.key, pane.identity_key()])
	_draft_pane = "" if pane == null else pane.key
	if pane != null:
		for kept: String in _drafts.keys():
			if _drafts[kept].pane_key == pane.key and kept != _draft_key:
				_drafts.erase(kept)
	var draft: Draft = _drafts.get(_draft_key)
	var text := "" if draft == null else draft.text
	if box.text != text:
		box.text = text


func _keep_draft(key: String, pane_key: String, text: String) -> void:
	_drafts.erase(key)
	if text.is_empty():
		return
	var draft := Draft.new()
	draft.pane_key = pane_key
	draft.text = text
	_drafts[key] = draft
	while _drafts.size() > DRAFTS_MAX:
		_drafts.erase(_drafts.keys()[0])


## The line `context` sent is no draft any more: drop the draft kept for its
## pane and terminal, and empty the box if it types for them now, but only
## while either still holds that very line. Text typed while the line was out
## is a new draft, and stays.
func _forget_draft(context: CommandContext) -> void:
	var key := JSON.stringify([context.pane_key, context.identity_key])
	var kept: Draft = _drafts.get(key)
	if kept != null and kept.text == context.line:
		_drafts.erase(key)
	var box: LineEdit = %ReplyBox
	if key == _draft_key and box.text == context.line:
		box.text = ""
		_drafts.erase(key)


# --- the header and the details -----------------------------------------------


## The header and the PANE details (CardDetails, on the scene's `%Detail`).
func _details() -> CardDetails:
	return %Detail
