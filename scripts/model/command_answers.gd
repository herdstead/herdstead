class_name CommandAnswers
extends RefCounted
## What the fleet says about one pane at one instant (HerdrFleet.answers()),
## as plain values: for each kind of command asked about, why it would be
## refused now; the target a command aimed there now would carry; and what
## the commands of the staff panel's block carry or are judged by (what a
## close takes with it, the side a split goes to, the shell's directory, the
## workspace a worktree is made of, the name each kind's next start gets, how
## the last start there is going). The agent card reads these instead of the
## fleet (CardActions.View), so what a press aims is worked out from values.
##
## Never kept: the card asks for a new one each time it looks, a press
## included, and the command a press aims is built from the one asked for at
## that press. An answer is how things stood when it was asked; the boundary
## judges the aimed command again when it is sent.

## What refusal() says of a kind nobody asked about: never NONE.
const UNASKED := CommandRefusal.Reason.NOT_CONNECTED

## A context aimed at the pane when this was asked (HerdrFleet.context_for());
## null for answers no fleet gave.
var target: CommandContext
## What a close takes with it (CloseScope.of()); a missing scope for no pane.
var scope := CloseScope.new()
## The side a split goes to, `right` or `down`; empty when the pane does not split.
var direction := ""
## The shell's directory exactly as the snapshot carries it; empty for no pane.
var cwd := ""
## The pane's workspace, as the office cleaned it and as herdr spelled it
## (empty when the snapshot lists no such workspace).
var workspace_id := ""
var wire_workspace_id := ""
## The name the next start of each kind asked about gets (HerdrFleet.next_agent_name()).
var names: Dictionary[String, String] = {}
## The last start sent to the pane this run, the last write to it, how that
## start is going by the snapshot, and whether a write there waits for a look.
var launch: LaunchWatch
var last_write: CommandTicket
var launch_outcome := LaunchWatch.Outcome.GONE
var must_look := false

var _refusals: Dictionary[CommandContext.Kind, CommandRefusal.Reason] = {}
## A start's answer is per agent kind.
var _starts: Dictionary[String, CommandRefusal.Reason] = {}


## Note the answer for `kind` (a START: for a start of `agent_kind`).
func answer(kind: CommandContext.Kind, reason: CommandRefusal.Reason, agent_kind := "") -> void:
	if kind == CommandContext.Kind.START:
		_starts[agent_kind] = reason
	else:
		_refusals[kind] = reason


## Why a command of `kind` (a START: of `agent_kind`) would have been refused
## when this was asked, or NONE; UNASKED for a kind that was not asked about.
func refusal(kind: CommandContext.Kind, agent_kind := "") -> CommandRefusal.Reason:
	var said: CommandRefusal.Reason = UNASKED
	if kind == CommandContext.Kind.START:
		said = _starts.get(agent_kind, UNASKED)
	else:
		said = _refusals.get(kind, UNASKED)
	return said


## The start of `agent_kind` these answers describe, under its next name,
## aimed at the terminal text `preview`; `sure_anyway` as CommandContext.starting()
## takes it. Null without a target, like every command below.
func starting(agent_kind: String, preview: CommandPreview, sure_anyway := false) -> CommandContext:
	if target == null:
		return null
	var named: String = names.get(agent_kind, "")
	return target.starting(agent_kind, named, preview, sure_anyway)


## The split, to the side the pane's shape gave.
func splitting() -> CommandContext:
	return null if target == null else target.splitting(direction)


## The close, taking the scope read with it.
func closing() -> CommandContext:
	return null if target == null else target.closing(scope)


## The new space, in the shell's directory.
func spacing() -> CommandContext:
	return null if target == null else target.spacing(cwd)


## The worktree of the pane's workspace, on `branch`.
func branching(branch: String) -> CommandContext:
	return null if target == null else target.branching(workspace_id, wire_workspace_id, branch)
