class_name LaunchBlock
extends VBoxContainer
## The launch block on the agent card, beside a picked pane's preview
## (docs/WRITE_BOUNDARY.md §4, §5): START AGENT for a shell, NEW PANE BESIDE for an agent, and
## under either (or alone, for a pane that neither starts nor splits) the
## manage rows: Close pane, New space, and a branch box with New
## worktree. What it shows only: the card (OfficePaneInspector, CardActions)
## decides what is offered, why a button is off and what a press sends; this
## block only writes the text, visibility, `disabled` and tooltips of the
## nodes the scene holds under it (a pool of KINDS_MAX kind buttons, the split
## button, a title, a note, the confirm's terminal row, the manage rows and
## their note). It never adds or frees a node, never lays anything out and
## never talks to the fleet.
##
## The script sits on the card scene's own `%Launch` node, so its children stay
## the card's unique names (`%Kind0`, `%LaunchNote`, …).

## Kind buttons in the block: as many as the scene holds.
const KINDS_MAX := 8
## How long a confirm armed by a first click waits for the second one.
const CONFIRM_SECONDS := 10.0
const TITLE := "START AGENT"
const NOTE := "Types the kind + Enter in this terminal"
const NONE := "No agent kind seen on %s yet: start one in herdr first"
const CONFIRM := 'Start anyway? Types "%s" + Enter after:'
const SPLIT_TITLE := "NEW PANE BESIDE %s"
const SPLIT_NOTE := "Splits a new pane next to %s"
## The split button's text by the side the new pane goes to; with no side, the
## right arrow (the button is off then).
const SPLIT_BUTTON: Dictionary[String, String] = {"right": "New pane →", "down": "New pane ↓"}
const SPLIT_SIDE: Dictionary[String, String] = {"right": "to the right of it", "down": "below it"}
## The block for a pane that neither starts nor splits (launching, or on a
## dimmed machine): only the manage rows.
const MANAGE_TITLE := "THIS PANE"
## The buttons' labels, measured to share the block's 108 units two to a row
## (`Close` 34 + `New space` 62; the branch box 46 + `Worktree` 55): the
## fuller words are in the tooltips and the notes.
const CLOSE_BUTTON := "Close"
const CLOSE_AGAIN := "Close · click again"
const CLOSE_KILLS := "Close · kills"
const SPACE_BUTTON := "New space"
const WORKTREE_BUTTON := "Worktree"
## The close confirm's note by the pane's state (a state with no line of its
## own gets CLOSE_NOTE), the same in full for its tooltip (the note has two
## lines of 108 units, about 17 characters each: the measured fit), and the
## line's endings by scope.
const CLOSE_NOTE := "Click Close again within %d s; anything else cancels."
const CLOSE_KILL_NOTES: Dictionary[String, String] = {
	"working": "Kills %s, still working.",
	"blocked": "Kills %s mid-question.",
	"starting": "Kills %s's launch.",
	"unknown": "Kills %s, state unknown.",
}
const CLOSE_KILL_DETAILS: Dictionary[String, String] = {
	"working": "%s is WORKING: closing kills it now, without asking it.",
	"blocked": "%s is BLOCKED: closing kills it with its question unanswered.",
	"starting": "%s is STARTING: closing kills the launch.",
	"unknown": "%s is in no known state: closing kills it now, without asking it.",
}
## Rows the confirm's line may take for a close (it wraps: what goes with the
## pane is the point); a start's row never wraps, like the terminal's.
const CLOSE_LINE_ROWS := 3
const CLOSE_LINE_SHELL := "Closes %s (shell)."
const CLOSE_LINE_AGENT := "Closes %s's pane %s."
const CLOSE_LINE_TAB := " and its tab %s (last pane of the tab)."
const CLOSE_LINE_SPACE := ' and space %s "%s" (last pane of the space).'
const CLOSE_LINE_MEZZANINE := ' and mezzanine %s "%s". The checkout stays on disk.'
const SPACE_NOTE := "New space: a space with one shell in %s"
const WORKTREE_NOTE := "New worktree: branch %s from this space"
const BRANCH_NOTE := "Branch: %s"


## What the manage rows show: the close button's text and why it is off, the
## armed confirm's note and line (empty: none armed), the space and worktree
## buttons' reasons, and the one-line note under them. Words only: the card
## decides them (CardActions), this block writes them.
class Manage:
	var close_text := CLOSE_BUTTON
	var close_reason := CommandRefusal.Reason.NONE
	var close_tip := ""
	var confirm_note := ""
	var confirm_tip := ""
	var confirm_line := ""
	var space_reason := CommandRefusal.Reason.NONE
	var space_tip := ""
	var worktree_reason := CommandRefusal.Reason.NONE
	var worktree_tip := ""
	var note := ""
	var note_tip := ""


## What one kind button offers: the kind, the name herdr would start it as,
## and why it may not be pressed now (NONE; PROMPT_UNSURE: a first click arms
## the confirm).
class Offer:
	var kind := ""
	var agent_name := ""
	var reason := CommandRefusal.Reason.NONE


## Every kind button, in the scene's order: KINDS_MAX of them.
func kind_buttons() -> Array[Button]:
	var found: Array[Button] = []
	for child in (%LaunchKinds as Container).get_children():
		if child is Button:
			found.append(child)
	return found


func split_button() -> Button:
	return %SplitButton


func close_button() -> Button:
	return %CloseButton


func space_button() -> Button:
	return %SpaceButton


func worktree_button() -> Button:
	return %WorktreeButton


func branch_box() -> LineEdit:
	return %BranchBox


## No block.
func close() -> void:
	visible = false
	hide_manage()


## The manage rows alone: no kind, no split, the title MANAGE_TITLE.
func show_manage_only() -> void:
	visible = true
	for button in kind_buttons():
		button.visible = false
		button.disabled = true
	split_button().visible = false
	split_button().disabled = true
	var title: Label = %LaunchTitle
	title.text = MANAGE_TITLE
	title.tooltip_text = ""
	var note: Label = %LaunchNote
	note.visible = false
	var screen: Control = %LaunchScreen
	screen.visible = false


## The manage rows under whatever the block shows: Close, New space, the
## branch box with Worktree, and their note. With `confirm_note` set, a
## first click on Close armed its confirm: the block's note and terminal row
## say what closes (as the START confirm uses them), and the other two
## controls step aside for them (the 480x320 card has no room for all).
func show_manage(manage: Manage) -> void:
	var armed := not manage.confirm_note.is_empty()
	var row: Control = %ManageRow
	row.visible = true
	var trees: Control = %WorktreeRow
	trees.visible = not armed
	var closer := close_button()
	closer.text = manage.close_text
	closer.disabled = manage.close_reason != CommandRefusal.Reason.NONE
	closer.tooltip_text = manage.close_tip
	if closer.disabled:
		closer.tooltip_text += "\nOff: " + CommandRefusal.detail(manage.close_reason)
	var spacer := space_button()
	spacer.visible = not armed
	spacer.text = SPACE_BUTTON
	spacer.disabled = manage.space_reason != CommandRefusal.Reason.NONE
	spacer.tooltip_text = manage.space_tip
	if spacer.disabled:
		spacer.tooltip_text += "\nOff: " + CommandRefusal.detail(manage.space_reason)
	var trees_button := worktree_button()
	trees_button.text = WORKTREE_BUTTON
	trees_button.disabled = manage.worktree_reason != CommandRefusal.Reason.NONE
	trees_button.tooltip_text = manage.worktree_tip
	if trees_button.disabled:
		trees_button.tooltip_text += "\nOff: " + CommandRefusal.detail(manage.worktree_reason)
	var note: Label = %ManageNote
	note.visible = not armed and not manage.note.is_empty()
	note.text = manage.note
	note.tooltip_text = manage.note_tip
	if not armed:
		return
	var launch_note: Label = %LaunchNote
	launch_note.visible = true
	launch_note.text = manage.confirm_note
	launch_note.tooltip_text = manage.confirm_tip
	var screen: Control = %LaunchScreen
	screen.visible = true
	var line: Label = %LaunchLine
	# Wrapped, so it measures its rows (a clipped label's minimum is one unit).
	line.clip_text = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.max_lines_visible = CLOSE_LINE_ROWS
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.text = manage.confirm_line
	line.tooltip_text = manage.confirm_line + "\nWhat closing this pane takes with it, as the snapshot reads now."


## No manage rows (the block closed, or a form that has none).
func hide_manage() -> void:
	var row: Control = %ManageRow
	row.visible = false
	var trees: Control = %WorktreeRow
	trees.visible = false
	var note: Label = %ManageNote
	note.visible = false
	for button: Button in [close_button(), space_button(), worktree_button()]:
		button.disabled = true
	space_button().visible = true


## The confirm line for closing pane `pane_id` with `scope` (CloseScope):
## `Closes w2:p3 (shell).` / `Closes CODEX's pane w2:p3.`, and what goes with
## it: its tab, its space, or its mezzanine.
static func close_line(scope: CloseScope, pane_id: String) -> String:
	var who := scope.who()
	var line := CLOSE_LINE_SHELL % pane_id if who.is_empty() else CLOSE_LINE_AGENT % [who, pane_id]
	if scope.last_of_space:
		var space_words := CLOSE_LINE_MEZZANINE if scope.mezzanine else CLOSE_LINE_SPACE
		line = line.trim_suffix(".") + space_words % [scope.level_label, scope.space_label]
	elif scope.last_of_tab:
		line = line.trim_suffix(".") + CLOSE_LINE_TAB % scope.tab_id
	return line


## The confirm's note: heavier when the agent is not idle (closing kills it).
static func close_note(scope: CloseScope) -> String:
	if CLOSE_KILL_NOTES.has(scope.state) and not scope.who().is_empty():
		return CLOSE_KILL_NOTES[scope.state] % scope.who()
	return CLOSE_NOTE % int(CONFIRM_SECONDS)


## The same in full, for the note's tooltip.
static func close_note_detail(scope: CloseScope) -> String:
	if CLOSE_KILL_DETAILS.has(scope.state) and not scope.who().is_empty():
		return CLOSE_KILL_DETAILS[scope.state] % scope.who()
	return CLOSE_NOTE % int(CONFIRM_SECONDS)


## The close button's text: plain; armed, `Close · click again`, or `Close ·
## kills` when the agent is not idle (the note above names it: a kind's name
## on the button would not fit the block).
static func close_text(scope: CloseScope, armed: bool) -> String:
	if not armed:
		return CLOSE_BUTTON
	if CLOSE_KILL_NOTES.has(scope.state) and not scope.who().is_empty():
		return CLOSE_KILLS
	return CLOSE_AGAIN


## The block for a shell: a button per offer (the first KINDS_MAX; the rest of
## the pool hidden and off), then the note. `on` names the machine in the
## tooltips (" on bee", or empty), `machine` names it where no kind is seen.
## With `confirm_kind` set, a first click armed that kind's confirm: the note
## asks for the second click and `confirm_line` shows the row herdr types after.
func show_start(offers: Array[Offer], on: String, machine: String, confirm_kind := "", confirm_line := "") -> void:
	visible = true
	split_button().visible = false
	split_button().disabled = true
	var launch_note: Label = %LaunchNote
	launch_note.visible = true
	var buttons := kind_buttons()
	for index in buttons.size():
		var button := buttons[index]
		button.visible = index < offers.size()
		if not button.visible:
			button.disabled = true
			continue
		var offer := offers[index]
		button.text = offer.kind.to_upper()
		button.disabled = (
			offer.reason != CommandRefusal.Reason.NONE and offer.reason != CommandRefusal.Reason.PROMPT_UNSURE
		)
		button.tooltip_text = _kind_tooltip(offer.kind, offer.agent_name, on)
		if offer.reason == CommandRefusal.Reason.PROMPT_UNSURE:
			button.tooltip_text += ("\nThe last row does not end like a prompt: a first click shows it and asks you to confirm.")
		elif offer.reason != CommandRefusal.Reason.NONE:
			button.tooltip_text += "\nOff: " + CommandRefusal.detail(offer.reason)
	var title: Label = %LaunchTitle
	title.text = TITLE
	title.tooltip_text = ""
	var note: Label = %LaunchNote
	var screen: Control = %LaunchScreen
	var line: Label = %LaunchLine
	screen.visible = not confirm_kind.is_empty()
	if not confirm_kind.is_empty():
		note.text = CONFIRM % confirm_kind
		note.tooltip_text = (
			(
				"herdr types `%s` and Enter after what this row holds, on the same line. Click %s again to start"
				% [confirm_kind, confirm_kind.to_upper()]
			)
			+ " anyway; anything else, or %d seconds, and nothing is sent." % int(CONFIRM_SECONDS)
		)
		line.clip_text = true
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.max_lines_visible = -1
		line.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		line.text = confirm_line
		line.tooltip_text = "The last row of this terminal, as the card read it."
	elif offers.is_empty():
		note.text = NONE % machine
		note.tooltip_text = (
			"Only kinds herdr has detected on this machine are offered: start one agent of a kind in herdr"
			+ " itself, and it is offered here after."
		)
	else:
		note.text = NOTE
		note.tooltip_text = (
			"herdr types the kind's command and Enter into this shell, after whatever its last row holds."
			+ " The card checks that row ends at a prompt first; it can still change before herdr types."
		)


## The block for an agent: one button that splits pane `pane_id` (the agent
## `provider`'s, on the machine `on` names) towards `side`, `right` or `down`;
## empty when its shape gives none. `reason` is why the button is off, or NONE.
func show_split(provider: String, pane_id: String, side: String, reason: CommandRefusal.Reason, on: String) -> void:
	visible = true
	for button in kind_buttons():
		button.visible = false
		button.disabled = true
	var launch_note: Label = %LaunchNote
	launch_note.visible = true
	var title: Label = %LaunchTitle
	title.text = SPLIT_TITLE % provider.to_upper()
	title.tooltip_text = "New pane beside %s (%s%s)" % [provider.to_upper(), pane_id, on]
	var button := split_button()
	button.visible = true
	button.text = SPLIT_BUTTON.get(side, SPLIT_BUTTON["right"])
	button.disabled = reason != CommandRefusal.Reason.NONE or not SPLIT_SIDE.has(side)
	button.tooltip_text = (
		(
			"Splits %s%s: a new pane %s. herdr's focus stays where it is, and the new pane starts in"
			% [pane_id, on, SPLIT_SIDE.get(side, "beside it")]
		)
		+ " this pane's directory, as a shell. The office picks it; start an agent there next. Only by click."
	)
	if reason != CommandRefusal.Reason.NONE:
		button.tooltip_text += "\nOff: " + CommandRefusal.detail(reason)
	var note: Label = %LaunchNote
	note.text = SPLIT_NOTE % pane_id
	note.tooltip_text = "The new pane is a shell in this pane's directory; nothing starts in it until you click a kind there."
	var screen: Control = %LaunchScreen
	screen.visible = false


static func _kind_tooltip(kind: String, agent_name: String, on: String) -> String:
	return (
		"Types `%s` and Enter in this terminal%s: herdr starts it as %s." % [kind, on, agent_name]
		+ " Checks the screen for a prompt first; it can still change. Only by click."
	)
