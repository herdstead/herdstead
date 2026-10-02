class_name CommandTicket
extends RefCounted
## What became of one command: HerdrFleet.read_pane(), focus_pane(), start_agent(), split_pane(),
## close_pane(), create_space(), create_worktree(), send_keys() and send_line() hand one back at once, and HerdrCommands moves it
## along. Only HerdrCommands writes it.
##
##   unsent -> sent -> accepted | rejected | unknown
##   unsent -> cancelled            never sent: see CANCELLED
##   refused                        never sent: see `refusal`
##
## An input command (KEYS, LINE, START) is one ticket for two requests: while it is
## UNSENT, HerdrCommands re-reads the terminal source the viewer saw, and only
## when that re-read matches does it write, in the same frame. A re-read that
## differs, is cut or fails, or a fresh check that finds a reason against the
## write, ends it REFUSED with that reason, and nothing was written. The re-read
## is never a write: a ticket is SENT only from the first byte of the write.
##
## A raw input of the terminal monitor (TYPE_KEYS, TYPE_TEXT, PASTE) has no
## re-read: it waits UNSENT in its pane's queue until the write before it is
## over, then is checked again against what the fleet knows and written. One
## that cannot be written then ends REFUSED, and so does every one queued
## behind it for that pane.
##
## A write is never retried, whatever state it ends in.

## The ticket reached a final state. Emitted once, on the frame after, so a
## caller that connects right after asking still hears it — as long as it holds
## the ticket: a deferred signal on a freed ticket is dropped.
signal finished

enum State {
	## Queued; no byte of it has reached herdr's socket.
	UNSENT,
	## Its first byte was written. From here a failure is UNKNOWN, never CANCELLED.
	SENT,
	## herdr answered with a result.
	ACCEPTED,
	## herdr answered with an error (`error_code`, `error_message`).
	REJECTED,
	## Sent, but no usable answer: timed out, dropped, cut mid-reply, over its
	## line cap, unreadable, or its machine went away. herdr may have acted on it.
	UNKNOWN,
	## Never sent: its socket was not there, nothing could be written, or its
	## machine closed, dropped or was replaced before the first byte.
	CANCELLED,
	## Refused before anything was written (`refusal` says why): at once, or
	## for an input command after its re-read.
	REFUSED,
}

## What was asked, exactly as it was aimed.
var context: CommandContext
var state := State.UNSENT
## REFUSED only: why; NONE otherwise.
var refusal := CommandRefusal.Reason.NONE
## herdr's request id; every command gets its own.
var request_id := ""
## REJECTED only: herdr's error code and message, cleaned and bounded (the
## message is remote free text: its grapheme clusters are bounded too), and
## the code typed (OTHER for one this office has no words for).
var error_code := ""
var error_message := ""
var rejection := CommandRejection.Code.OTHER
## UNKNOWN and CANCELLED: what happened, in this office's own words.
var failure := ""
## An accepted read's result; null for everything else.
var read: PaneReadResult
## An accepted SCREEN read's result (the monitor's); null for everything else.
var screen: ScreenReadResult
## An accepted SPLIT's result: the new pane's ids; null for everything else.
var split: PaneSplitResult
## An accepted SPACE's or WORKTREE's result: the new workspace's and its
## shell's ids; null for everything else. Used to name and pick the new space,
## never to write to it.
var space: SpaceCreateResult
## An accepted START's result: herdr's name for the agent and its launch flag;
## null for everything else. It says herdr began typing, never that an agent
## came up (LaunchWatch).
var launch: AgentStartResult
## An accepted LAUNCH_CHECK's result: the agent as herdr describes it now;
## null for everything else (a settled launch answers `agent_not_found`, REJECTED).
var agent_info: AgentInfoResult
## Time.get_ticks_msec() when it was asked for: a preview read counts as a look
## after a write only if it was asked for late enough (HerdrCommands.LOOK_DELAY_MSEC).
var queued_msec := 0
## KEYS, LINE and START: the re-read's UTF-8 byte count (-1 until it came back) and
## whether it matched the text frozen at the press.
var recheck_bytes := -1
var recheck_matched := false

var _announced := false


func _init(aimed: CommandContext) -> void:
	context = aimed


## A ticket refused before any transport exists, e.g. in read-only mode.
static func refused(aimed: CommandContext, reason: CommandRefusal.Reason) -> CommandTicket:
	var ticket := CommandTicket.new(aimed)
	ticket.refuse(reason)
	return ticket


## Whether it reached a final state (everything but UNSENT and SENT).
func is_finished() -> bool:
	return state != State.UNSENT and state != State.SENT


## Settle as REFUSED for `reason`.
func refuse(reason: CommandRefusal.Reason) -> void:
	refusal = reason
	settle(State.REFUSED)


## Move to `next`; a final state announces `finished` once, on the next frame.
## A ticket that is already final never moves again.
func settle(next: State, why := "") -> void:
	if is_finished():
		return
	state = next
	if not why.is_empty():
		failure = why
	if is_finished() and not _announced:
		_announced = true
		finished.emit.call_deferred()


## The state's enum name, for logs, the audit and tests: `ACCEPTED`.
static func state_name(of: State) -> String:
	return str(State.find_key(of))
