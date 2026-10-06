class_name CardActions
extends RefCounted
## The agent card's aiming family: why a press may not go now (ladder(), the
## one place that says so for the card: answer keys, a line, a start, a
## split, a close, a new space, a new worktree), what a press on the launch
## block's buttons aims, the confirms a first click arms (an unsure prompt's
## kind, the close's two clicks) and how long they hold, and the footer's
## launch line. No node and no fleet: the card (OfficePaneInspector) hands in
## what it shows this instant as a View, the fleet's answers about the pane
## among it (CommandAnswers, asked at that instant), and keeps the nodes, the
## signals and the release (its `_release()` checks the binding, the pane, the
## pick and the mode again before anything reaches the fleet). Every aim
## fixes its CommandContext at the press, from the target the fleet aimed
## then (HerdrFleet.context_for(), in the View's answers); nothing here sends.


## One press: the command it would send, fixed at the press. A kind button's
## press on an unsure prompt sends nothing: it `arms` that kind's confirm at
## the release, if the card still shows `text` on `binding`. A first click on
## Close likewise `arms_close` its confirm.
class Aim:
	var context: CommandContext
	var button: Button
	var arms := ""
	var arms_close := false
	var text := ""
	var binding := 0
	## A close's scope at the press, for the confirm it arms.
	var scope: CloseScope


## A first click's confirm of a start: a second click on `kind` sends, while
## the card is on `binding` and shows `text`, until `until_msec`. `last_line`
## is the row herdr would type after (PromptState.last_line), shown as it reads.
class Confirm:
	var kind := ""
	var binding := 0
	var text := ""
	var last_line := ""
	var until_msec := 0


## A first click's confirm of a close: a second click sends while the card is
## on `binding`, the pane still has `identity_key`, what the close takes with
## it still signs `scope_signature`, and until `until_msec`.
class CloseConfirm:
	var binding := 0
	var identity_key := ""
	var scope_signature := ""
	var until_msec := 0


## A line the footer says, and the same in full for its tooltip.
class Said:
	var text := ""
	var detail := ""


## What the card shows this instant, handed to every call, all of it values:
## what the fleet answers about the pane now (asked for the kinds asked() names
## for the form; answers no fleet gave when the card has none), the pane and
## binding, the block's form, the preview frozen now (and its text, and
## whether it is shown), why the card itself refuses a write (NONE for none),
## the branch box's text, the machine's label (empty for one machine), and
## the clock.
class View:
	var answers := CommandAnswers.new()
	var pane: PaneModel
	var binding := 0
	var form := OfficePaneInspector.Form.NONE
	var frozen: CommandPreview
	var shown := false
	var text := ""
	var card_refusal := CommandRefusal.Reason.NONE
	var branch := ""
	var machine := ""
	var now_msec := 0


## The armed confirms, the kinds offered (in the block's button order) and the
## launch line's memory of which start it last said was over, and on which binding.
var confirm: Confirm
var close_confirm: CloseConfirm
var launch_kinds := PackedStringArray()
var over_watch: LaunchWatch
var over_binding := -1


## Nothing armed: a new binding, a spent confirm.
func clear() -> void:
	confirm = null
	close_confirm = null


## Drop a confirm whose time ran out; true when one did.
func expire(now_msec: int) -> bool:
	var expired := false
	if confirm != null and now_msec >= confirm.until_msec:
		confirm = null
		expired = true
	if close_confirm != null and now_msec >= close_confirm.until_msec:
		close_confirm = null
		expired = true
	return expired


# --- the ladder -------------------------------------------------------------------


## Why a press of `kind` may not go now, or NONE: four steps in this order,
## the first that refuses being the answer. `card`, the card's own state (no
## fleet or pane, read-only, a pane not picked, a write of its own on its
## way); `seam`, the fleet's word on the pane for that kind
## (HerdrFleet.command_refusal(), or the same in a View's answers); whether
## the preview shows what that kind is checked against (shown_refusal());
## and `typed`, what only this press's payload says (the prompt a start ends
## at, the branch typed). Every refusal the card shows for a press comes
## through here.
static func ladder(
	kind: CommandContext.Kind,
	card: CommandRefusal.Reason,
	seam: CommandRefusal.Reason,
	shown: bool,
	frozen: CommandPreview,
	typed := CommandRefusal.Reason.NONE
) -> CommandRefusal.Reason:
	if card != CommandRefusal.Reason.NONE:
		return card
	if seam != CommandRefusal.Reason.NONE:
		return seam
	var seen := shown_refusal(kind, shown, frozen)
	return seen if seen != CommandRefusal.Reason.NONE else typed


## Whether the preview (`shown`, and `frozen` as a press would freeze it)
## shows uncut text from the source `kind` is checked against: the whole
## `detection` text for answer keys, the recent output for a line and a
## start. NONE for a kind that reads no screen (a split, a close, a new
## space, a new worktree).
static func shown_refusal(kind: CommandContext.Kind, shown: bool, frozen: CommandPreview) -> CommandRefusal.Reason:
	var wanted := ""
	match kind:
		CommandContext.Kind.KEYS:
			wanted = CommandContext.SOURCE_DETECTION
		CommandContext.Kind.LINE, CommandContext.Kind.START:
			wanted = CommandContext.SOURCE_RECENT
		_:
			return CommandRefusal.Reason.NONE
	if not shown or frozen == null or frozen.cut or frozen.source != wanted:
		return CommandRefusal.Reason.UNSEEN
	return CommandRefusal.Reason.NONE


## ladder() over a View: the seam's word is the View's answer for `kind` (a
## START: for a start of `agent_kind`).
static func refusal(
	view: View, kind: CommandContext.Kind, agent_kind := "", typed := CommandRefusal.Reason.NONE
) -> CommandRefusal.Reason:
	return ladder(kind, view.card_refusal, view.answers.refusal(kind, agent_kind), view.shown, view.frozen, typed)


## The kinds a View of `form` asks the fleet about: the block's own, and none
## for no block (nothing there may be pressed, so nothing is asked).
static func asked(form: OfficePaneInspector.Form) -> Array[CommandContext.Kind]:
	var manage: Array[CommandContext.Kind] = [
		CommandContext.Kind.CLOSE, CommandContext.Kind.SPACE, CommandContext.Kind.WORKTREE
	]
	match form:
		OfficePaneInspector.Form.NONE:
			return []
		OfficePaneInspector.Form.START:
			manage.push_front(CommandContext.Kind.START)
		OfficePaneInspector.Form.SPLIT:
			manage.push_front(CommandContext.Kind.SPLIT)
	return manage


# --- starts and splits ------------------------------------------------------------


## Why a start of `kind` may not be pressed now, or NONE: the card's own
## state, what the boundary says about the pane and the kind (a shell, not
## launching, a kind seen here, a free name, no open write, no look owed), and
## whether the preview shows a whole recent output ending as `prompt` says
## (PROMPT_UNSURE unless `confirmed`: a first click then arms the confirm).
func launch_refusal(view: View, kind: String, prompt: PromptState, confirmed: bool) -> CommandRefusal.Reason:
	return refusal(view, CommandContext.Kind.START, kind, HerdrFleet.prompt_refusal(prompt, confirmed))


## Why a split of the pane shown may not be pressed now, or NONE: the card's
## own state and what the boundary says (the pane's shape, a live and current
## machine, the same terminal and agent, no open write, no look owed). A split
## reads no screen, so the preview is not asked.
func split_refusal(view: View) -> CommandRefusal.Reason:
	return refusal(view, CommandContext.Kind.SPLIT)


## Aim the split button's press: the split it would send, to the side the
## pane's shape gives this instant. Null when it may not be pressed.
func aim_split(view: View, button: Button) -> Aim:
	if view.form != OfficePaneInspector.Form.SPLIT or split_refusal(view) != CommandRefusal.Reason.NONE:
		return null
	if view.answers.direction.is_empty():
		return null
	var aim := Aim.new()
	aim.button = button
	aim.context = view.answers.splitting()
	return aim


## Aim a kind button's press (`index` among the kinds offered): the start it
## would send, with the preview shown this instant frozen; on an unsure prompt
## not yet confirmed, only the confirm its release would arm. Null when it may
## not be pressed.
func aim_start(view: View, button: Button, index: int) -> Aim:
	if view.form != OfficePaneInspector.Form.START or index < 0 or index >= launch_kinds.size():
		return null
	var kind := launch_kinds[index]
	var confirmed := confirm_holds(view, kind)
	var reason := launch_refusal(view, kind, HerdrFleet.prompt_state(view.frozen), confirmed)
	var aim := Aim.new()
	aim.button = button
	if reason == CommandRefusal.Reason.PROMPT_UNSURE:
		aim.arms = kind
		aim.text = view.text
		aim.binding = view.binding
		return aim
	if reason != CommandRefusal.Reason.NONE or view.frozen == null:
		return null
	aim.context = view.answers.starting(kind, view.frozen, confirmed)
	return aim


## A first click's release on an unsure prompt: arm the confirm, if the card
## still shows what it showed at the press. Sends nothing.
func arm(view: View, aim: Aim) -> void:
	if (
		aim.binding == view.binding
		and view.form == OfficePaneInspector.Form.START
		and view.shown
		and view.text == aim.text
	):
		var armed := Confirm.new()
		armed.kind = aim.arms
		armed.binding = view.binding
		armed.text = view.text
		armed.last_line = HerdrFleet.prompt_state(view.frozen).last_line
		armed.until_msec = view.now_msec + int(LaunchBlock.CONFIRM_SECONDS * 1000)
		confirm = armed
		# One confirm at a time: the note and the line belong to the last armed.
		close_confirm = null


## Whether the armed confirm lets a click on `kind` send: that kind, this
## binding, the block still offered, the same screen shown, in time.
func confirm_holds(view: View, kind: String) -> bool:
	if confirm == null or confirm.kind != kind or confirm.binding != view.binding:
		return false
	if view.form != OfficePaneInspector.Form.START or not view.shown or view.text != confirm.text:
		return false
	return view.now_msec < confirm.until_msec


# --- close, new space, new worktree -----------------------------------------------


## Why the pane shown may not be closed from here now, or NONE: the card's
## own state and what the boundary says (a live and current machine, the same
## terminal and agent, never the parent of an open worktree group, no open
## write, no look owed). The two clicks are the card's, judged apart.
func close_refusal(view: View) -> CommandRefusal.Reason:
	return refusal(view, CommandContext.Kind.CLOSE)


## Why a new space may not start from the pane shown now, or NONE.
func space_refusal(view: View) -> CommandRefusal.Reason:
	return refusal(view, CommandContext.Kind.SPACE)


## Why a new worktree may not be made from the pane shown now, or NONE: the
## card's own state, the boundary's word on the pane and its space, and the
## branch typed (HerdrFleet.branch_refusal()).
func worktree_refusal(view: View) -> CommandRefusal.Reason:
	return refusal(view, CommandContext.Kind.WORKTREE, "", HerdrFleet.branch_refusal(view.branch))


## Whether a first click on Close has armed its confirm for the pane shown:
## this binding, the same terminal and agent, what the close takes with it
## unchanged (the scope read now signs the same), in time.
func close_confirm_holds(view: View) -> bool:
	if close_confirm == null or close_confirm.binding != view.binding or view.pane == null:
		return false
	# No block (answer mode, a folded panel, a pane not picked, a dimmed
	# machine): nothing shows the confirm, so nothing holds it.
	if view.form == OfficePaneInspector.Form.NONE:
		return false
	if close_confirm.identity_key != view.pane.identity_key():
		return false
	if view.answers.scope.signature() != close_confirm.scope_signature:
		return false
	return view.now_msec < close_confirm.until_msec


## Aim the Close button's press: the close it would send when its confirm is
## armed and holds, else the confirm its release would arm. Null when it may
## not be pressed.
func aim_close(view: View, button: Button) -> Aim:
	if view.form == OfficePaneInspector.Form.NONE or close_refusal(view) != CommandRefusal.Reason.NONE:
		return null
	var scope := view.answers.scope
	if scope.missing or scope.group_parent:
		return null
	var aim := Aim.new()
	aim.button = button
	aim.scope = scope
	aim.binding = view.binding
	if not close_confirm_holds(view):
		aim.arms_close = true
		return aim
	aim.context = view.answers.closing()
	return aim


## A first click's release on Close: arm its confirm, if the card is still on
## the binding pressed and the pane still closes the same way. Sends nothing.
func arm_close(view: View, aim: Aim) -> void:
	if aim.binding != view.binding or view.pane == null or aim.scope == null:
		return
	if view.answers.scope.signature() != aim.scope.signature():
		return
	var armed := CloseConfirm.new()
	armed.binding = view.binding
	armed.identity_key = view.pane.identity_key()
	armed.scope_signature = aim.scope.signature()
	armed.until_msec = view.now_msec + int(LaunchBlock.CONFIRM_SECONDS * 1000)
	close_confirm = armed
	confirm = null


## Aim the New space button's press: the space it would send, from the pane's
## directory as the snapshot carries it this instant. Null when it may not be pressed.
func aim_space(view: View, button: Button) -> Aim:
	if view.form == OfficePaneInspector.Form.NONE or space_refusal(view) != CommandRefusal.Reason.NONE:
		return null
	var aim := Aim.new()
	aim.button = button
	aim.context = view.answers.spacing()
	return aim


## Aim the New worktree button's press: the worktree it would send, on the
## branch the box holds this instant. Null when it may not be pressed.
func aim_worktree(view: View, button: Button) -> Aim:
	if view.form == OfficePaneInspector.Form.NONE or worktree_refusal(view) != CommandRefusal.Reason.NONE:
		return null
	var aim := Aim.new()
	aim.button = button
	aim.context = view.answers.branching(view.branch)
	return aim


## The manage rows' words for the pane shown (LaunchBlock.Manage): the close button (armed or not,
## heavier for an agent at work), the armed confirm's note and line, the
## space and worktree buttons' reasons, and the note under them.
func manage_words(view: View, on: String, machine: String) -> LaunchBlock.Manage:
	var manage := LaunchBlock.Manage.new()
	var scope := view.answers.scope
	var armed := close_confirm_holds(view)
	manage.close_reason = close_refusal(view)
	if manage.close_reason == CommandRefusal.Reason.NONE and scope.group_parent:
		manage.close_reason = CommandRefusal.Reason.GROUP_PARENT
	manage.close_text = LaunchBlock.close_text(scope, armed)
	manage.close_tip = (
		(
			"Closes %s%s in herdr: its terminal ends at once, and any agent in it is killed without being asked."
			% [view.pane.pane_id, on]
		)
		+ (" A first click shows what closes; a second within %d seconds closes it." % int(LaunchBlock.CONFIRM_SECONDS))
		+ " herdr's own view may move to another pane. Only by click."
	)
	if manage.close_reason == CommandRefusal.Reason.GROUP_PARENT:
		# The block adds the reason's detail after; this names the space.
		manage.close_tip += "\nLast pane of the repo's own space %s." % scope.level_label
	if armed:
		manage.confirm_note = LaunchBlock.close_note(scope)
		manage.confirm_tip = (
			LaunchBlock.close_note_detail(scope)
			+ (
				" Click Close again to close it; anything else (another pick, a change in what closes, %d seconds)"
				% int(LaunchBlock.CONFIRM_SECONDS)
			)
			+ " cancels and nothing is sent."
		)
		manage.confirm_line = LaunchBlock.close_line(scope, view.pane.pane_id)
	manage.space_reason = space_refusal(view)
	var directory := view.answers.cwd
	manage.space_tip = (
		(
			"Makes a new space%s: a space with one shell in %s."
			% [on, directory if not directory.is_empty() else "this pane's directory"]
		)
		+ " herdr's view stays where it is (except on an empty herdr). Only by click."
	)
	manage.worktree_reason = worktree_refusal(view)
	manage.worktree_tip = (
		(
			"Creates branch %s from this space's HEAD (or checks it out if it exists) in herdr's worktree directory;"
			% (view.branch if not view.branch.is_empty() else "<branch>")
		)
		+ (
			" runs the repo's git hooks on %s. A new space opens on the checkout; herdr's view stays. Only by click."
			% machine
		)
	)
	# The note has room only while it says something the buttons do not: the
	# branch typed, or why it cannot go (the space's words are its tooltip).
	if not view.branch.is_empty():
		var typed := HerdrFleet.branch_refusal(view.branch)
		if typed != CommandRefusal.Reason.NONE:
			manage.note = LaunchBlock.BRANCH_NOTE % CommandRefusal.text(typed)
			manage.note_tip = "This branch name cannot be sent: " + CommandRefusal.detail(typed)
		else:
			manage.note = LaunchBlock.WORKTREE_NOTE % view.branch
			manage.note_tip = manage.worktree_tip
	return manage


# --- the footer's launch line ---------------------------------------------------------


## How the pane's start is going, for the footer (LaunchWatch.text()): only
## for this run's own start while it is still the pane's last write. Still
## going or gone wrong, it is said until the next write; over (started,
## replaced, gone), on the card binding that first said so and while a look
## is owed. A start whose answer was lost and that no snapshot shows yet is an
## unknown result. Null when there is nothing to say.
func launch_line(view: View) -> Said:
	if view.pane == null:
		return null
	var watch := view.answers.launch
	if watch == null or view.answers.last_write != watch.ticket:
		return null
	var outcome := view.answers.launch_outcome
	var over := [LaunchWatch.Outcome.READY, LaunchWatch.Outcome.REPLACED, LaunchWatch.Outcome.GONE]
	if outcome in over:
		if over_watch != watch:
			over_watch = watch
			over_binding = view.binding
		if over_binding != view.binding and not view.answers.must_look:
			return null
	var said := Said.new()
	if watch.ticket.state == CommandTicket.State.UNKNOWN and outcome == LaunchWatch.Outcome.PENDING:
		said.text = CardWords.write_outcome(watch.ticket)
		said.detail = CardWords.write_outcome_detail(watch.ticket)
		return said
	said.text = LaunchWatch.text(outcome, watch, view.now_msec)
	var why := LaunchWatch.detail(outcome)
	said.detail = "%s: %s" % [said.text, why]
	return said
