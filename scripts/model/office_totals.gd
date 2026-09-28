class_name OfficeTotals
extends RefCounted
## What the top bar's counters say, made once per refresh from the frame
## (OfficeTotals.of()): six numbers and, for each, where they come from, by
## machine and then by space, for the breakdown a hover shows.
##
## Only a machine whose snapshot is current counts (BuildingModel.stale): a lost
## connection is never idle, working or waiting (AGENTS.md invariant 4). An
## agent counts under herdr's own word for its state, the rule
## OfficeAttention.count() has: a provider, not still launching. `unknown` is in
## no count; shells are only in PANES.
##
## Durations are not in here: a breakdown row and the BLOCKED count carry each
## pane's StateLog track, and whoever writes a time (the counter's tooltip,
## attention's `max`) asks StateLog.wait_of() / longest() for it when it
## writes, the rule the OVERVIEW's FOR is read by. A start the log never saw
## reads as the stretch it did see, with `+`: at least that long.

## The four states a counter stands for, in the bar's order.
const STATES: Array[String] = ["blocked", "done", "working", "idle"]
## Written for a space whose label is empty.
const UNNAMED_SPACE := "?"


## One line of a counter's breakdown: how many of one machine's space are in its state.
class CounterRow:
	extends RefCounted
	## The machine as the fleet labels it.
	var machine := ""
	## The workspace's label, or UNNAMED_SPACE.
	var space := ""
	var count := 0
	## Each counted pane's StateLog track (null for one the log has none of);
	## only BLOCKED's and IDLE's rows fill it, as their tooltips say how long.
	var tracks: Array[StateLog.Track] = []


## One machine in the MACHINES breakdown. Filled by the office from the fleet:
## the model never reaches a connection (AGENTS.md invariant 1).
class MachineRow:
	extends RefCounted
	var label := ""
	var state := MachineLiveness.State.OFFLINE
	## Unix time the machine's client last read a snapshot or applied a status
	## event (HerdrFleet.heard_since()); −1 when it never has.
	var heard_since := -1.0
	## The SSH forward's last complaint; empty for none.
	var error := ""


## Machines answering now, and machines in the fleet.
var machines_live := 0
var machines_total := 0
## Panes the live snapshots carry, shells and unseated panes included.
var panes := 0
var blocked := 0
var done := 0
var working := 0
var idle := 0
## Every counted blocked pane's StateLog track (null for one the log has none
## of), for the BLOCKED counter's `max`: StateLog.longest() of them.
var blocked_tracks: Array[StateLog.Track] = []
## Each count's breakdown, in building order and then by workspace number; a
## space no floor seats after the numbered ones.
var blocked_rows: Array[CounterRow] = []
var done_rows: Array[CounterRow] = []
var working_rows: Array[CounterRow] = []
var idle_rows: Array[CounterRow] = []
## Every machine in the fleet, Local first, as handed in.
var machine_rows: Array[MachineRow] = []


## The counts of `frame`'s live buildings, with `machines` for the MACHINES
## breakdown (the office's, from the fleet) and `ledger` for each pane's track
## (HerdrFleet.state_log()).
static func of(frame: OfficeFrame, machines: Array[MachineRow], ledger: StateLog) -> OfficeTotals:
	var totals := OfficeTotals.new()
	totals.machine_rows = machines
	totals.machines_total = frame.buildings.size()
	for building in frame.buildings:
		if building.stale:
			continue
		totals.machines_live += 1
		totals.panes += building.panes
		# Seated panes first, by floor (the breakdown's order); then the rest.
		var numbers: Dictionary[String, int] = {}
		var ordered: Array[PaneModel] = []
		var seen: Dictionary[String, bool] = {}
		for floor_model in building.floors:
			for room in floor_model.rooms:
				for pane in room.panes:
					if not seen.has(pane.key):
						seen[pane.key] = true
						numbers[pane.workspace_id] = floor_model.number
						ordered.append(pane)
		for pane in building.all_panes:
			if not seen.has(pane.key):
				seen[pane.key] = true
				ordered.append(pane)
		for state in STATES:
			var counted: Array[PaneModel] = []
			for pane in ordered:
				if not pane.provider.is_empty() and not pane.launching() and pane.state == state:
					counted.append(pane)
			totals.rows_of(StringName(state)).append_array(_by_space(building.label, counted, numbers, state, ledger))
			if state == "blocked":
				for pane in counted:
					totals.blocked_tracks.append(ledger.track(pane.key))
	totals.blocked = _sum(totals.blocked_rows)
	totals.done = _sum(totals.done_rows)
	totals.working = _sum(totals.working_rows)
	totals.idle = _sum(totals.idle_rows)
	return totals


## The breakdown of counter `id` (`&"blocked"`, `&"done"`, `&"working"`,
## `&"idle"`); empty for any other. The array itself, not a copy.
func rows_of(id: StringName) -> Array[CounterRow]:
	match id:
		&"blocked":
			return blocked_rows
		&"done":
			return done_rows
		&"working":
			return working_rows
		&"idle":
			return idle_rows
	var none: Array[CounterRow] = []
	return none


## One machine's `counted` panes, all in `state`, a row per space: by herdr's workspace
## number (`numbers`, from its floors), a space no floor seats after them in
## the order its panes came. Only BLOCKED and IDLE keep the tracks.
static func _by_space(
	machine: String, counted: Array[PaneModel], numbers: Dictionary[String, int], state: String, ledger: StateLog
) -> Array[CounterRow]:
	var spaces: Dictionary[String, CounterRow] = {}
	var arrival: Array[String] = []
	for pane in counted:
		var row: CounterRow = spaces.get(pane.workspace_id)
		if row == null:
			row = CounterRow.new()
			row.machine = machine
			row.space = UNNAMED_SPACE if pane.workspace_label.is_empty() else pane.workspace_label
			spaces[pane.workspace_id] = row
			arrival.append(pane.workspace_id)
		row.count += 1
		if state == "blocked" or state == "idle":
			row.tracks.append(ledger.track(pane.key))
	var ranked: Array[String] = arrival.duplicate()
	ranked.sort_custom(
		func(a: String, b: String) -> bool:
			var seated_a := numbers.has(a)
			if seated_a != numbers.has(b):
				return seated_a
			if seated_a and numbers[a] != numbers[b]:
				return numbers[a] < numbers[b]
			return arrival.find(a) < arrival.find(b)
	)
	var result: Array[CounterRow] = []
	for id in ranked:
		result.append(spaces[id])
	return result


static func _sum(rows: Array[CounterRow]) -> int:
	var total := 0
	for row in rows:
		total += row.count
	return total
