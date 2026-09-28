class_name OverviewModel
extends RefCounted
## What the OVERVIEW shows at one moment: a row per pane the state log has a
## live track for, filtered and sorted the way the viewer asked, and the span
## its timelines cover (from the log's first observation to now). Made fresh by
## of(), a pure function of the frame, the log and the viewer's choices; the
## HUD only draws it.
##
## Everything here is observation: the durations are the log's (StateLog,
## which copies the one state clock the rest of the office reads), and `+`
## means "at least": the state began before this office was watching.

## Which column the rows are ordered by. STATE is the attention order the agent
## list uses: blocked, done, working, idle, unknown, a shell, then offline;
## within one, the longest in it first.
enum Sort { STATE, AGENT, SPACE, FOR, BLOCKED, TIMES }
## Which rows show: every one, or only the live panes in one of herdr's states.
enum Filter { ALL, BLOCKED, DONE, WORKING, IDLE }

## The word each Filter keeps; ALL keeps every row.
const FILTER_STATES: Dictionary[Filter, String] = {
	Filter.BLOCKED: "blocked",
	Filter.DONE: "done",
	Filter.WORKING: "working",
	Filter.IDLE: "idle",
}
## A column's natural order: the numbers largest first, the words A to Z, and
## STATE most urgent first (its ascending order). What a first click on a
## column's head picks (OfficeOverview); a second click reverses it.
const NATURALLY_DESCENDING: Array[Sort] = [Sort.FOR, Sort.BLOCKED, Sort.TIMES]


## One pane's line in the table.
class Row:
	## HerdrFleet.pane_key.
	var key := ""
	## The provider as herdr names it (`claude`); empty for a shell.
	var agent := ""
	## The name herdr gave the pane's agent (`claude-1`, bounded by the
	## snapshot); what the row is called while `agent` is still empty.
	var agent_name := ""
	## herdr is launching the pane's agent and it has not asked anything
	## (PaneModel.launching()): the STATE column says STARTING.
	var starting := false
	var space := ""
	var tab := ""
	## The machine's label, and whether the table names it (several machines,
	## and this one is not Local).
	var machine_label := ""
	var names_machine := false
	## herdr's word, StateLog.UNKNOWN, or "" for a shell. For an offline row, the
	## last word observed before its machine went.
	var state := ""
	## Its machine is not live now (invariant 4): dimmed, no live state, no FOR.
	var offline := false
	## How long the open state has been observed, and whether it began earlier.
	var for_msec := 0
	var for_plus := false
	## Observed blocked time since the office opened, and whether some of it
	## began earlier.
	var blocked_msec := 0
	var blocked_plus := false
	## Blocked segments, the baseline one included.
	var times := 0
	## Read only, for the timeline.
	var track: StateLog.Track
	## The pane the staff panel shows.
	var selected := false

	## The SPACE / TAB column: `api / main`, and `@ bee` on another machine's pane.
	func place() -> String:
		var said := space if tab.is_empty() else "%s / %s" % [space, tab]
		if names_machine:
			said += " @ " + machine_label
		return said

	## The rank STATE sorts by: 0 blocked … 3 idle, 4 unknown, 5 a shell, 6 offline.
	func rank() -> int:
		if offline:
			return 6
		if agent.is_empty():
			return 5
		var at := StateLog.STATES.find(state)
		return at if at >= 0 else 4


## After the filter, in the order asked.
var rows: Array[Row] = []
## Every pane the log has a live track for, whatever the filter keeps: a row
## the filter leaves out is hidden, one not here is gone.
var tracked: Dictionary[String, bool] = {}
## Every pane of every live machine (OfficeTotals.panes' rule).
var panes := 0
## The timelines' left edge (first_seen(), and its wall-clock time), the
## moment this model was made, and the span between them.
var opened_msec := 0
## -1 before the log observed anything.
var opened_unix := -1.0
var now_msec := 0
var since_opened_msec := 0
var sort := Sort.STATE
var descending := false
var filter := Filter.ALL


## The table for `frame` from `ledger` at `now_msec` (the log's clock, HerdrFleet's
## monotonic milliseconds), `selected` the staff panel's pane.
static func of(
	frame: OfficeFrame,
	ledger: StateLog,
	selected: String,
	by: Sort,
	reversed: bool,
	keep: Filter,
	now: int,
) -> OverviewModel:
	var model := OverviewModel.new()
	model.sort = by
	model.descending = reversed
	model.filter = keep
	model.now_msec = now
	model.opened_msec = first_seen(ledger, now)
	if ledger.opened_msec >= 0:
		model.opened_unix = ledger.opened_unix + (model.opened_msec - ledger.opened_msec) / 1000.0
	else:
		model.opened_unix = -1.0
	model.since_opened_msec = maxi(now - model.opened_msec, 0)
	var live: Dictionary[String, bool] = {}
	for building in frame.buildings:
		live[building.key] = not building.stale
		if not building.stale:
			model.panes += building.panes
	var several := frame.several_machines()
	for kept in ledger.tracks():
		if kept.gone:
			continue
		model.tracked[kept.key] = true
		var row := _row(kept, ledger, now)
		var pane := frame.pane(kept.key)
		row.offline = pane == null or not live.get(kept.machine, false)
		row.starting = pane != null and pane.launching()
		row.names_machine = several and kept.machine != HerdrFleet.LOCAL
		row.selected = kept.key == selected
		if row.offline:
			row.for_msec = 0
			row.for_plus = false
		if _kept(row, keep):
			model.rows.append(row)
	model.rows.sort_custom(func(a: Row, b: Row) -> bool: return _before(a, b, by, reversed))
	return model


## The timeline's left edge: the first moment the log saw a pane, which is
## when the first machine answered. The log itself opens on its first
## observation, usually that machine still connecting, a fraction of a second
## earlier: counted from there, every pane that was there from the start would
## open on a sliver of hatch, as if it had not been watched. `now` before any.
static func first_seen(ledger: StateLog, now: int) -> int:
	var first := -1
	for kept in ledger.tracks():
		if kept.segments.is_empty():
			continue
		var start := kept.segments[0].start_msec
		if first < 0 or start < first:
			first = start
	if first < 0:
		return ledger.opened_msec if ledger.opened_msec >= 0 else now
	return first


## The keys shown, in order: what a test compares.
func keys() -> PackedStringArray:
	var shown := PackedStringArray()
	for row in rows:
		shown.append(row.key)
	return shown


static func _row(kept: StateLog.Track, ledger: StateLog, now: int) -> Row:
	var row := Row.new()
	row.key = kept.key
	row.agent = kept.agent
	row.agent_name = kept.agent_name
	row.space = kept.space
	row.tab = kept.tab
	row.machine_label = kept.machine_label
	row.track = kept
	row.state = "" if kept.agent.is_empty() else _last_word(kept)
	var wait := StateLog.wait_of(kept, now)
	row.for_msec = wait.msec
	row.for_plus = wait.plus
	row.blocked_msec = ledger.blocked_for(kept, now)
	row.blocked_plus = kept.blocked_plus
	row.times = kept.times
	return row


## The last word the track observed: its open segment's, or, while its machine
## is away, the one before the unobserved stretch.
static func _last_word(kept: StateLog.Track) -> String:
	for index in range(kept.segments.size() - 1, -1, -1):
		var segment := kept.segments[index]
		if segment.observed:
			return segment.state
	return StateLog.UNKNOWN


static func _kept(row: Row, keep: Filter) -> bool:
	if keep == Filter.ALL:
		return true
	return not row.offline and not row.agent.is_empty() and row.state == FILTER_STATES[keep]


## Whether `a` stands above `b`: the column's order (reversed when asked),
## then the pane key, so equal rows keep one order from one second to the next.
static func _before(a: Row, b: Row, by: Sort, reversed: bool) -> bool:
	var order := _compare(a, b, by)
	if reversed:
		order = -order
	if order != 0:
		return order < 0
	return a.key < b.key


## -1 when `a` comes first in `by`'s ascending order, 1 when `b` does, 0 for a tie.
static func _compare(a: Row, b: Row, by: Sort) -> int:
	match by:
		Sort.STATE:
			if a.rank() != b.rank():
				return signi(a.rank() - b.rank())
			# The longest in its state first.
			return signi(b.for_msec - a.for_msec)
		Sort.AGENT:
			return signi(a.agent.nocasecmp_to(b.agent))
		Sort.SPACE:
			return signi(a.place().nocasecmp_to(b.place()))
		Sort.FOR:
			return signi(a.for_msec - b.for_msec)
		Sort.BLOCKED:
			return signi(a.blocked_msec - b.blocked_msec)
		Sort.TIMES:
			return signi(a.times - b.times)
	return 0
