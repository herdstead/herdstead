class_name LaunchWatch
extends RefCounted
## One start of an agent this office sent (accepted, or sent with its answer lost),
## as HerdrCommands remembers it, and how it is going. herdr answers a start at
## once and only then types into the shell; whether an agent came up shows in
## the snapshots after (measured on 0.9.0: recognised within 0.3 s, ready after
## about 3.4 s, or blocked on a question at once, still launching). judge()
## reads a snapshot's pane and never the ticket, and nothing it says ever
## makes a write: a start that is not detected is not retried, and herdr keeps
## its name.

## How it is going, as the latest snapshot shows the pane.
enum Outcome {
	## herdr is still launching it, or no snapshot shows the start yet.
	PENDING,
	## The agent came up: herdr no longer says it is launching, and it is ready
	## or in one of herdr's states.
	READY,
	## Still launching, and already blocked on a question (a trust prompt):
	## answer it with the keys.
	BLOCKED_AT_START,
	## Still launching after the timeout: nothing detected it. herdr keeps the name.
	NOT_DETECTED,
	## Another terminal, or another agent, holds the pane now.
	REPLACED,
	## The pane is gone.
	GONE,
	## herdr gave the start up: asked at the deadline, it knows no agent in the
	## pane any more (`agent_not_found`). The pane is a shell again.
	FAILED,
	## Asked at the deadline, herdr gave no usable answer: how it stands is
	## not known. Not asked again.
	UNKNOWN,
	## Not asked at the deadline: the machine was replaced or gone by then
	## (another connection is not the one the start was sent on). How it
	## stands is not known.
	NOT_CHECKED,
}

## The deadline of a start, in milliseconds from when it was asked for. herdr
## times a launch out itself after about 30.4 s (its default, measured), but
## settles that only when asked about that agent (nothing else does: the
## snapshot keeps the launch pending, the name taken and the pane busy): so the
## office's deadline comes just after herdr's, and its one launch check at the
## deadline is what makes herdr give the start up.
const TIMEOUT_MSEC := 31000

## Composite pane key (HerdrFleet.pane_key) and machine key.
var pane_key := ""
var machine := ""
## The name this office gave the agent, and its kind.
var name := ""
var kind := ""
## The pane's terminal when the start was aimed.
var terminal_id := ""
## When the start was asked for (the boundary's clock, CommandTicket.queued_msec).
var started_msec := 0
## When its ticket ended, on the same clock.
var ended_msec := 0
## The start's own ticket, final: ACCEPTED or UNKNOWN.
var ticket: CommandTicket
## Whether the deadline's launch check was decided: sent, or not needed (the
## snapshot no longer showed the launch pending). Never decided twice.
var decided := false
## The launch check sent at the deadline; null when none was.
var check: CommandTicket
## The deadline found the machine replaced or gone: nothing was asked.
var unchecked := false


## How `watch` is going, as `pane` (the pane in the latest current snapshot;
## null when it is gone) shows it at `now_msec`, with `timeout_msec` before an
## undetected start reads NOT_DETECTED.
static func judge(watch: LaunchWatch, pane: HerdrSnapshot.Pane, now_msec: int, timeout_msec := TIMEOUT_MSEC) -> Outcome:
	if watch == null or pane == null:
		return Outcome.GONE
	if not watch.terminal_id.is_empty() and pane.terminal_id != watch.terminal_id:
		return Outcome.REPLACED
	var other_name := not pane.agent_name.is_empty() and pane.agent_name != watch.name
	var other_agent := not pane.agent.is_empty() and pane.agent != watch.kind
	if other_name or other_agent:
		return Outcome.REPLACED
	var checked := _checked(watch)
	# herdr gave this start up: an agent that came up in the shell after that
	# (started by hand) is not it.
	if checked == Outcome.FAILED:
		return checked
	if pane.launch_pending:
		if pane.status() == "blocked":
			return Outcome.BLOCKED_AT_START
	else:
		# A shell reads idle too (a pane's status is not an agent's): ready
		# only once an agent is there, recognised or ready under this name.
		var ready := pane.interactive_ready and pane.agent_name == watch.name
		if ready or (not pane.agent.is_empty() and pane.status() in StateLog.STATES):
			return Outcome.READY
	if checked != Outcome.PENDING:
		return checked
	if watch.unchecked:
		return Outcome.NOT_CHECKED
	if now_msec - watch.started_msec >= timeout_msec:
		return Outcome.NOT_DETECTED
	return Outcome.PENDING


## Whether herdr gave this start up when the deadline asked (agent_not_found):
## it freed the pane and the name then (measured against herdr 0.9.0).
func failed() -> bool:
	return _checked(self) == Outcome.FAILED


## What the deadline's launch check says, once it is final: FAILED (herdr
## knows no agent there), NOT_DETECTED (still launching), UNKNOWN (no usable
## answer), NOT_CHECKED (refused before it went: the connection changed);
## PENDING while there is none or it is out, or herdr says the launch is over
## (the snapshot tells how).
static func _checked(watch: LaunchWatch) -> Outcome:
	var asked := watch.check
	if asked == null or not asked.is_finished():
		return Outcome.PENDING
	if asked.state == CommandTicket.State.REJECTED and asked.rejection == CommandRejection.Code.AGENT_NOT_FOUND:
		return Outcome.FAILED
	if asked.state == CommandTicket.State.ACCEPTED and asked.agent_info != null:
		return Outcome.NOT_DETECTED if asked.agent_info.launch_pending else Outcome.PENDING
	if asked.state == CommandTicket.State.REFUSED:
		return Outcome.NOT_CHECKED
	return Outcome.UNKNOWN


## The card's footer line for `outcome`: `Starting claude-2 · 4s`,
## `claude-2 started`, `claude-2 asks: answer with the keys`,
## `claude-2 not detected after 31s: look at the terminal`, `claude-2 did not
## start: look at the terminal`, `claude-2: no answer from herdr`, `Terminal
## changed`, `Pane gone`.
static func text(outcome: Outcome, watch: LaunchWatch, now_msec: int, timeout_msec := TIMEOUT_MSEC) -> String:
	var named := "" if watch == null else watch.name
	match outcome:
		Outcome.PENDING:
			var started := 0 if watch == null else watch.started_msec
			var waited := OfficeAttention.format_duration(maxi(now_msec - started, 0) / 1000.0)
			return "Starting %s · %s" % [named, waited]
		Outcome.READY:
			return "%s started" % named
		Outcome.BLOCKED_AT_START:
			return "%s asks: answer with the keys" % named
		Outcome.NOT_DETECTED:
			var after := OfficeAttention.format_duration(timeout_msec / 1000.0)
			return "%s not detected after %s: look at the terminal" % [named, after]
		Outcome.REPLACED:
			return "Terminal changed"
		Outcome.FAILED:
			return "%s did not start: look at the terminal" % named
		Outcome.UNKNOWN:
			return "%s: no answer from herdr" % named
		Outcome.NOT_CHECKED:
			return "%s not checked: the connection changed" % named
	return "Pane gone"


## The same as a sentence, for the footer's tooltip.
static func detail(outcome: Outcome) -> String:
	match outcome:
		Outcome.PENDING:
			return "herdr took the start and is typing the command into the shell; nothing has detected the agent yet."
		Outcome.READY:
			return "herdr detects the agent and no longer reports it launching."
		Outcome.BLOCKED_AT_START:
			return "the agent is still launching and already asks a question. Answer it with the keys."
		Outcome.NOT_DETECTED:
			return (
				"herdr keeps the name pending and nothing is retried. The shell still shows what happened:"
				+ " look at the terminal."
			)
		Outcome.REPLACED:
			return "another terminal or agent holds this pane now."
		Outcome.FAILED:
			return (
				"herdr gave the start up: it detected no agent in time. The pane is a shell again; the terminal"
				+ " shows what happened."
			)
		Outcome.UNKNOWN:
			return "herdr gave no usable answer when asked how the start stands. Nothing is asked again."
		Outcome.NOT_CHECKED:
			return (
				"the machine was replaced or went away before the start's deadline, so herdr was not asked how it"
				+ " stands. Look at the terminal."
			)
	return "herdr no longer lists this pane."


## The Outcome's enum name, for logs and tests: `NOT_DETECTED`.
static func name_of(outcome: Outcome) -> String:
	return str(Outcome.find_key(outcome))
