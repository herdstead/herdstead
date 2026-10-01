class_name CardWords
extends RefCounted
## The agent card's words that depend on nothing but what they are given: what
## became of a write, why a read brought nothing back, how old a preview is,
## why a new pane was not picked, and how the preview's rows are cut. Static
## only: no node, no fleet, no state (OfficePaneInspector says them).

## A row is clipped by the panel anyway; beyond this many characters it is not shaped at all.
const ROW_CHARS := 240
const TAB_COLUMNS := 8
const BEST_EFFORT := "Checks the screen first; it can still change"
const SENT_DETAIL := "herdr accepted the keystrokes; not whether the agent acted"
## A line is herdr's own prompt: it types the text and its Enter.
const LINE_SENT_DETAIL := "herdr typed the line and Enter; not whether the agent acted"
## A split herdr made, by the new pane's id; a space or a worktree it made, by
## the new workspace's id (and the branch); a pane it closed. And what the
## footer says after any of those when no snapshot showed the new pane in
## time (`%s` is that footer line: `New pane w2:p4 not seen yet`).
const NEW_PANE := "New pane %s"
const NEW_SPACE := "New space %s"
const NEW_WORKTREE := "New worktree %s → %s"
const CLOSED := "Closed %s"
const NEW_PANE_UNPICKED: Dictionary[OfficePaneInspector.Unpicked, String] = {
	OfficePaneInspector.Unpicked.UNSEEN: "%s not seen yet",
	OfficePaneInspector.Unpicked.MOVED_ON: "%s: not picked",
	OfficePaneInspector.Unpicked.OTHER_TERMINAL: "%s: another terminal, not picked",
}
## A lost answer, by what was asked: the snapshot is the only judge.
const CLOSE_UNKNOWN := "Close: no answer from herdr. The next snapshot shows whether %s closed."
const SPACE_UNKNOWN := "New space: no answer from herdr; if a new space appears, that is it."
const WORKTREE_UNKNOWN := "New worktree: no answer from herdr; git may have run. If a new space appears, that is it."


## `3s`, `12m`, `2h`: as short as the caption line needs.
static func age(seconds: int) -> String:
	if seconds < 60:
		return "%ds" % seconds
	if seconds < 3600:
		return "%dm" % floori(seconds / 60.0)
	return "%dh" % floori(seconds / 3600.0)


## `text` as terminal rows. herdr's text ends with a newline; the empty piece
## after it is not a row.
static func rows_of(text: String) -> PackedStringArray:
	if text.is_empty():
		return PackedStringArray()
	var rows := text.split("\n")
	if rows.size() > 0 and rows[rows.size() - 1].is_empty():
		rows.remove_at(rows.size() - 1)
	return rows


static func expand_tabs(row: String) -> String:
	if not "\t" in row:
		return row
	var out := ""
	for character in row:
		if character == "\t":
			out += " ".repeat(TAB_COLUMNS - out.length() % TAB_COLUMNS)
		else:
			out += character
	return out


## What the caption says about a read that brought no text back, in a few words.
static func failure(ticket: CommandTicket) -> String:
	if ticket == null:
		return "no answer"
	match ticket.state:
		CommandTicket.State.REJECTED:
			return "herdr refused"
		CommandTicket.State.CANCELLED:
			return "not sent"
	return "no answer"


## The same in full, for the caption's tooltip. herdr's own error text is
## cleaned and bounded by the boundary; this office's words never quote the terminal.
static func failure_detail(ticket: CommandTicket) -> String:
	if ticket == null:
		return "no usable answer."
	match ticket.state:
		CommandTicket.State.REJECTED:
			return "herdr refused it (%s: %s)." % [ticket.error_code, ticket.error_message]
		CommandTicket.State.CANCELLED:
			return "it was never sent (%s)." % ticket.failure
	return "no usable answer (%s)." % ticket.failure


## What became of a write, in one line.
static func write_outcome(ticket: CommandTicket) -> String:
	var focus := ticket.context != null and ticket.context.kind == CommandContext.Kind.FOCUS
	match ticket.state:
		CommandTicket.State.ACCEPTED:
			if ticket.split != null:
				return NEW_PANE % ticket.split.pane_id
			if ticket.space != null:
				if ticket.context.kind == CommandContext.Kind.WORKTREE:
					return NEW_WORKTREE % [ticket.context.branch, ticket.space.workspace_id]
				return NEW_SPACE % ticket.space.workspace_id
			if ticket.context != null and ticket.context.kind == CommandContext.Kind.CLOSE:
				return CLOSED % ticket.context.pane_id
			return "herdr switched here" if focus else "Sent"
		CommandTicket.State.REJECTED:
			if ticket.rejection == CommandRejection.Code.OTHER:
				return "herdr refused (%s)" % ticket.error_code
			if ticket.rejection == CommandRejection.Code.WORKTREE_CREATE_FAILED:
				# git's own headline, cleaned and bounded by the boundary.
				return "herdr refused: " + CommandRejection.text(ticket.rejection) + ticket.error_message
			return "herdr refused: " + CommandRejection.text(ticket.rejection)
		CommandTicket.State.REFUSED:
			return "Not sent: " + CommandRefusal.text(ticket.refusal)
		CommandTicket.State.CANCELLED:
			return "Not sent: unreachable"
	if ticket.context != null:
		match ticket.context.kind:
			CommandContext.Kind.CLOSE:
				return CLOSE_UNKNOWN % ticket.context.pane_id
			CommandContext.Kind.SPACE:
				return SPACE_UNKNOWN
			CommandContext.Kind.WORKTREE:
				return WORKTREE_UNKNOWN
	return "Unknown result: look first"


## The same in full, for the footer's tooltip: herdr's code and its own
## message (cleaned and bounded by the boundary) after the office's words.
static func write_outcome_detail(ticket: CommandTicket) -> String:
	var kind := ticket.context.kind if ticket.context != null else CommandContext.Kind.KEYS
	var focus := kind == CommandContext.Kind.FOCUS
	var what := "answer"
	match kind:
		CommandContext.Kind.FOCUS:
			what = "switch"
		CommandContext.Kind.START:
			what = "start"
		CommandContext.Kind.SPLIT:
			what = "split"
		CommandContext.Kind.CLOSE:
			what = "close"
		CommandContext.Kind.SPACE:
			what = "new space"
		CommandContext.Kind.WORKTREE:
			what = "new worktree"
	match ticket.state:
		CommandTicket.State.ACCEPTED:
			if focus:
				return "herdr switched its shared view to this pane, and this tab's UNREAD is cleared."
			if kind == CommandContext.Kind.CLOSE:
				return (
					(
						"herdr closed pane %s: its terminal ended at once. The next snapshot shows it gone;"
						% ticket.context.pane_id
					)
					+ " its tab or space goes with it when it was the last pane there."
				)
			if ticket.space != null and kind == CommandContext.Kind.WORKTREE:
				return (
					(
						"herdr made worktree %s as workspace %s; herdr's view stayed where it was."
						% [ticket.context.branch, ticket.space.workspace_id]
					)
					+ " The office picks the new space's shell once a snapshot shows it."
				)
			if ticket.space != null:
				return (
					(
						"herdr made workspace %s, a space with one shell; herdr's view stayed where it was."
						% ticket.space.workspace_id
					)
					+ " The office picks its shell once a snapshot shows it."
				)
			if ticket.split != null:
				return (
					(
						"herdr made pane %s beside this one, a shell in its directory; its focus stayed where it was."
						% ticket.split.pane_id
					)
					+ " The office picks the new pane once a snapshot shows it."
				)
			return (LINE_SENT_DETAIL if kind == CommandContext.Kind.LINE else SENT_DETAIL) + "."
		CommandTicket.State.REJECTED:
			if ticket.rejection == CommandRejection.Code.OTHER:
				return "herdr refused the %s: %s (%s)." % [what, ticket.error_message, ticket.error_code]
			return (
				"herdr refused the %s: %s (%s: %s)."
				% [
					what,
					CommandRejection.detail(ticket.rejection).trim_suffix("."),
					ticket.error_code,
					ticket.error_message,
				]
			)
		CommandTicket.State.REFUSED:
			return "Nothing was sent: " + CommandRefusal.detail(ticket.refusal)
		CommandTicket.State.CANCELLED:
			return "Nothing was sent: herdr's socket could not be reached, or the machine went first."
	return (
		"The %s went out but no usable answer came back (%s): herdr may have acted on it." % [what, ticket.failure]
		+ " Look at the terminal before writing again; nothing is retried."
	)


## An answer in flight, in a few words: still re-reading, or written.
static func input_progress(ticket: CommandTicket) -> String:
	match ticket.context.kind:
		CommandContext.Kind.SPLIT:
			return "Splitting…"
		CommandContext.Kind.CLOSE:
			return "Closing…"
		CommandContext.Kind.SPACE:
			return "Making the space…"
		CommandContext.Kind.WORKTREE:
			return "Making the worktree…"
	return "Checking the screen…" if ticket.state == CommandTicket.State.UNSENT else "Sending…"


## Why the office did not pick pane `pane_id`, a split of the card's pane, in
## full for the footer's tooltip (OfficePaneInspector.new_pane_not_picked()).
static func unpicked_detail(why: OfficePaneInspector.Unpicked, pane_id: String) -> String:
	var detail := ""
	match why:
		OfficePaneInspector.Unpicked.UNSEEN:
			detail = (
				"herdr answered that it made pane %s, but no snapshot has shown it since, so the office did not pick it."
				% pane_id
			)
		OfficePaneInspector.Unpicked.MOVED_ON:
			detail = (
				(
					"You had moved on (another space, or answer mode) before pane %s showed, so the office left you"
					% pane_id
				)
				+ " where you were and did not pick it."
			)
		OfficePaneInspector.Unpicked.OTHER_TERMINAL:
			detail = (
				(
					"Pane %s showed with another terminal than the one herdr named when it split, so the office did"
					% pane_id
				)
				+ " not pick it: it may not be the pane this split made."
			)
	detail += " Look for it in herdr, or pick its desk once it shows. Nothing is split again."
	return detail
