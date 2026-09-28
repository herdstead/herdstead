class_name AgentHistory
extends RefCounted
## The agent list's History group, read from the StateLog: one line per pane
## whose agent needed a human this run (a blocked or done stretch the log
## watched) and does not now, newest first. Pure static functions: the log's
## tracks and one refresh's OfficeFrame in, lines out; nothing is written. The
## live episodes Snooze and Hide act on are AttentionStore's; what ended is
## told here.
##
## ENDED: the pane is there, its machine online, in another state now.
## OFFLINE: its machine is away, so what it does now is unknown. GONE: the pane
## closed. A pane still blocked or done on a machine that is online has no
## line: it waits in the list's Waiting or Unread group.
##
## A line is about the pane's current agent run. The log keeps one track per
## pane and starts a new run on it when another terminal, agent or session
## comes up there (StateLog.Track.run_start), so what the run before waited for
## is not this run's to show. Only an ENDED line can be located, and only while
## the frame's pane is the terminal, agent and session the log saw (same_run()).
## A refresh reads the lines through a Cache, built again only when the log,
## the frame's panes or the machines online changed.

const LINES_MAX := 200
const ENDED := "ENDED"
const OFFLINE := "OFFLINE"
const GONE := "GONE"
## herdr's two states that want a human.
const ASKED: Array[String] = ["blocked", "done"]


## One History line.
class Line:
	extends RefCounted
	## HerdrFleet.pane_key.
	var key := ""
	var machine := ""
	var machine_label := ""
	## The track's agent (the row writes it in capitals).
	var provider := ""
	## herdr's workspace and tab labels. The row shows the tab: the space is the
	## floor it stands on, which the tooltip names.
	var space := ""
	var tab := ""
	## ENDED, OFFLINE or GONE.
	var what := ""
	## The last state that wanted a human: "blocked" or "done".
	var was := ""
	## What an ENDED pane does now, in herdr's word, and since when (unix).
	var state := ""
	var since_unix := -1.0
	## When it stopped wanting a human (the log's milliseconds): the newest on top.
	var ended_msec := 0
	## The run's blocked stretches and their observed time (StateLog totals).
	var times := 0
	var blocked_msec := 0
	var blocked_plus := false
	## ENDED, and the frame's pane is still the terminal the log saw.
	var locatable := false


## The lines kept between refreshes (see the class notes).
class Cache:
	extends RefCounted
	## How many times lines() built the lines: a probe for tests and perf.
	var builds := 0
	var _ledger: StateLog
	var _version := -1
	var _panes := ""
	var _live: Dictionary[String, bool] = {}
	var _lines: Array[AgentHistory.Line] = []

	## AgentHistory.of(), or the lines it gave last time when neither `ledger`
	## (its version), `frame`'s panes (pane_signature()) nor `live` changed.
	func lines(
		ledger: StateLog, frame: OfficeFrame, live: Dictionary[String, bool], now_msec: int
	) -> Array[AgentHistory.Line]:
		var panes := AgentHistory.pane_signature(frame)
		if (
			ledger != null
			and ledger == _ledger
			and ledger.version == _version
			and panes == _panes
			and live.recursive_equal(_live, 1)
		):
			return _lines
		builds += 1
		_ledger = ledger
		_version = ledger.version if ledger != null else -1
		_panes = panes
		_live = live.duplicate()
		_lines = AgentHistory.of(ledger, frame, live, now_msec)
		return _lines


## The History lines of `ledger` for `frame`, newest first, at most LINES_MAX.
## `live` says which machines are online (not stale); one it lacks is not.
static func of(ledger: StateLog, frame: OfficeFrame, live: Dictionary[String, bool], now_msec: int) -> Array[Line]:
	var result: Array[Line] = []
	if ledger == null:
		return result
	for kept in ledger.tracks():
		var online: bool = live.get(kept.machine, false)
		var line := _line(ledger, kept, frame, online, now_msec)
		if line != null:
			result.append(line)
	result.sort_custom(_newer)
	if result.size() > LINES_MAX:
		result.resize(LINES_MAX)
	return result


## Every pane of `frame` with what its identity is made of (terminal, agent,
## session: PaneModel.identity_key()'s parts, without its encoding), in one
## string: what the Cache compares to tell whether the panes changed.
static func pane_signature(frame: OfficeFrame) -> String:
	var parts := PackedStringArray()
	for key: String in frame.pane_by_key:
		var pane := frame.pane_by_key[key]
		var session := "" if pane.session == null else pane.session.identity_key()
		parts.append("%s\t%s\t%s\t%s" % [key, pane.terminal_id, pane.provider, session])
	return "\n".join(parts)


## Whether `pane` is the agent run `kept` saw: the same terminal, agent and
## session (the log's identity is empty for a pane without a terminal id, which
## so never matches: such a pane cannot be told from a new one).
static func same_run(pane: PaneModel, kept: StateLog.Track) -> bool:
	return not kept.identity.is_empty() and pane.identity_key() == kept.identity


## The tooltip's line for `line`: what became of it (the row's word, which an
## ENDED row does not write), how often it was blocked and for how long, in
## herdr's words.
static func tooltip_of(line: Line) -> String:
	var said := "Pane gone"
	if line.what == OFFLINE:
		said = "Machine offline: current state unknown"
	elif line.what == ENDED:
		said = "No longer waiting: %s" % (line.state if not line.state.is_empty() else StateLog.UNKNOWN)
		if line.since_unix >= 0.0:
			said += " since " + OfficeAttention.wall_clock(line.since_unix)
	var blocked := OfficeAttention.format_duration(line.blocked_msec / 1000.0) + ("+" if line.blocked_plus else "")
	return "%s · %s · blocked %d× · %s" % [line.what, said, line.times, blocked]


## `kept`'s line, if its current run wanted a human and does not now.
static func _line(ledger: StateLog, kept: StateLog.Track, frame: OfficeFrame, online: bool, now_msec: int) -> Line:
	var count := kept.segments.size()
	if count == 0:
		return null
	var last: StateLog.Segment = kept.segments[count - 1]
	if not kept.gone and online and last.state in ASKED:
		return null
	var asked: StateLog.Segment = null
	for index in range(count - 1, kept.run_start - 1, -1):
		var segment := kept.segments[index]
		if segment.observed and segment.state in ASKED:
			asked = segment
			break
	if asked == null:
		return null
	var line := Line.new()
	line.key = kept.key
	line.machine = kept.machine
	line.machine_label = kept.machine_label
	line.provider = kept.agent
	line.space = kept.space
	line.tab = kept.tab
	line.was = asked.state
	line.times = kept.times
	line.blocked_msec = ledger.blocked_for(kept, now_msec)
	line.blocked_plus = kept.blocked_plus
	if kept.gone:
		line.what = GONE
		line.ended_msec = kept.gone_msec
	else:
		line.what = ENDED if online else OFFLINE
		line.ended_msec = asked.end_msec if asked.end_msec >= 0 else now_msec
	if line.what == ENDED:
		line.state = last.state
		line.since_unix = last.start_unix
		var pane := frame.pane(kept.key)
		line.locatable = pane != null and same_run(pane, kept)
	return line


static func _newer(first: Line, second: Line) -> bool:
	if first.ended_msec != second.ended_msec:
		return first.ended_msec > second.ended_msec
	return first.key < second.key
