class_name StrategicModel
extends RefCounted
## What the strategic view (`S`, OfficeStrategic) draws for the shown floor:
## its title, and per table of the floor's plan (its rows in `index` order,
## empty rows left out, each row's tables left to right) the seats that have a
## pane, with the look of that pane's FLOORS window (OfficeFloorRow.window_look(),
## the one colour scale) and, for an agent that asks on a machine that answers,
## how long it has waited (StateLog.wait_of() in OfficeAttention.wait_text():
## the OVERVIEW's FOR, the lens's line). A seat whose pane is gone is a vacancy,
## drawn as none; a pane the plan does not seat is the agent list's to show.
##
## Pure: built by the office from the plan, the frame's floor, the machine's
## state and the state log at a clock it is handed, never Time.*.


## One table: a tab of the floor, as the plan placed it.
class Table:
	extends RefCounted
	## The tab's key (RoomModel.key, DeskPlacement.tab_key).
	var key := ""
	## The tab's label, the caption over its box; empty for a tab gone from
	## the floor that a retained plan still places.
	var label := ""
	## Seat columns, one far and one near seat each (DeskPlacement.capacity).
	var capacity := 0
	## Which of the view's rows (the plan's non-empty rows, top to bottom) it is in.
	var row := 0
	var seats: Array[Seat] = []


## One seated pane.
class Seat:
	extends RefCounted
	## The composite pane key (HerdrFleet.pane_key).
	var key := ""
	var column := 0
	## `far` or `near`.
	var side := "far"
	## The FLOORS window's look (HudTheme.SECTION_PANELS key).
	var look: StringName = &"WindowDark"
	## The agent kind; empty for a shell.
	var provider := ""
	## herdr's state, for the pack's word for it (ArtPack.state()).
	var state_word_key: StringName = &""
	## herdr is still launching the agent and it asks nothing yet (PaneModel.launching()).
	var starting := false
	## How long it has waited, for an agent that asks on a live machine; else empty.
	var wait := ""
	## Where it sits: `space / tab · pane`.
	var place := ""
	## The selected pane: the corners go round it.
	var picked := false


## `3F  API`, a mezzanine `3A · CHECKOUT · worktree of 3F`, `LOBBY`; ` @ machine`
## after it while the office shows more than one machine.
var title := ""
## `OFFLINE` or `CONNECTING` for a machine that is not answering; else empty.
var state_text := ""
## The machine is not answering: every seat dark, no wait (invariant 4).
var stale := false
## The shown floor is a lobby: nothing herdr sent is laid out there.
var lobby := false
var tables: Array[Table] = []
## The clock the waits were read at.
var now_msec := 0


## The model of `found`'s floor laid out by `plan` (null for none: a lobby).
## `several` is the office showing more than one machine, `state` how the
## floor's machine answers, `ledger` the fleet's state log, `active_key` the
## pane selected (picked or followed), `now_msec` the log's clock now.
static func of(
	plan: FloorPlan,
	found: ZoneRef,
	several: bool,
	state: MachineLiveness.State,
	ledger: StateLog,
	active_key: String,
	clock: int
) -> StrategicModel:
	var model := StrategicModel.new()
	model.now_msec = clock
	model.stale = state != MachineLiveness.State.LIVE
	if state == MachineLiveness.State.OFFLINE:
		model.state_text = "OFFLINE"
	elif state == MachineLiveness.State.CONNECTING:
		model.state_text = "CONNECTING"
	if found == null:
		return model
	var floor_model := found.zone_model
	model.lobby = floor_model.lobby
	model.title = _title(found)
	if several:
		model.title += " @ " + found.building.label
	if plan == null:
		return model
	var rooms: Dictionary[String, RoomModel] = {}
	var panes: Dictionary[String, PaneModel] = {}
	for room in floor_model.rooms:
		rooms[room.key] = room
		for pane in room.panes:
			panes[pane.key] = pane
	var bands := plan.rows.duplicate()
	bands.sort_custom(func(a: RowPlan, b: RowPlan) -> bool: return a.index < b.index)
	var row := 0
	for band: RowPlan in bands:
		if band.desks.is_empty():
			continue
		var desks := band.desks.duplicate()
		desks.sort_custom(func(a: DeskPlacement, b: DeskPlacement) -> bool: return a.origin.x < b.origin.x)
		for desk: DeskPlacement in desks:
			var table := Table.new()
			table.key = desk.tab_key
			var room: RoomModel = rooms.get(desk.tab_key)
			table.label = "" if room == null else room.label
			table.capacity = desk.capacity
			table.row = row
			for placed in desk.seats:
				var pane: PaneModel = panes.get(placed.pane_key)
				if pane != null:
					table.seats.append(_seat(pane, placed, model.stale, ledger, active_key, clock))
			table.seats.sort_custom(_far_first)
			model.tables.append(table)
		row += 1
	return model


## Everything that decides what the view draws, apart from waits (the view
## adds the ones it writes in a square) and the pointer: a view drawn for one
## signature is drawn again only for another.
func signature() -> String:
	var parts: Array = [title, state_text, stale, lobby]
	for table in tables:
		var seats: Array = []
		for each in table.seats:
			seats.append([each.key, each.column, each.side, each.look, each.picked])
		parts.append([table.key, table.label, table.capacity, table.row, seats])
	return JSON.stringify(parts)


## The seat with pane `key`, or null.
func seat_of(key: String) -> Seat:
	for table in tables:
		for each in table.seats:
			if each.key == key:
				return each
	return null


## Per view row, each table's capacity, left to right: StrategicLayout.fit()'s input.
func row_capacities() -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	for table in tables:
		while rows.size() <= table.row:
			rows.append(PackedInt32Array())
		rows[table.row].append(table.capacity)
	return rows


## The floor as its plate names it (OfficeFloorPlate.show_floor()), a mezzanine
## with the floor its checkout belongs to.
static func _title(found: ZoneRef) -> String:
	var floor_model := found.zone_model
	if floor_model.lobby:
		return "LOBBY"
	var number := OfficeFloorRow.number_text(floor_model)
	if floor_model.mezzanine_of.is_empty():
		return "%s  %s" % [number, floor_model.label.to_upper()]
	var named := floor_model.worktree if not floor_model.worktree.is_empty() else floor_model.label
	var said := "%s · %s" % [number, named.to_upper()]
	for other in found.building.zones:
		if other.key == floor_model.mezzanine_of:
			said += " · worktree of " + OfficeFloorRow.number_text(other)
	return said


## Far seats before near ones, each side left to right: the order they are drawn in.
static func _far_first(a: Seat, b: Seat) -> bool:
	if a.side != b.side:
		return a.side == "far"
	return a.column < b.column


static func _seat(
	pane: PaneModel, placed: SeatPlacement, dropped: bool, ledger: StateLog, active_key: String, clock: int
) -> Seat:
	var made := Seat.new()
	made.key = pane.key
	made.column = placed.column
	made.side = placed.side
	made.look = OfficeFloorRow.window_look(pane, not dropped)
	made.provider = pane.provider
	made.state_word_key = StringName(pane.state)
	made.starting = pane.launching()
	made.picked = pane.key == active_key
	var pane_name := pane.label if not pane.label.is_empty() else pane.pane_id
	made.place = "%s / %s · %s" % [pane.workspace_label, pane.tab_label, pane_name]
	if not dropped and pane.asks() and ledger != null:
		var track := ledger.track(pane.key)
		if track != null:
			made.wait = OfficeAttention.wait_text(StateLog.wait_of(track, clock))
	return made
