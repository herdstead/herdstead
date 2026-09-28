class_name OfficeSeatPlanner
extends RefCounted
## Resolve one tab without consulting snapshot order or any other tab.


class Column:
	extends RefCounted
	var source_x := 0
	var slot := -1
	var panes: Array[PaneModel] = []


static func plan(room: RoomModel, previous: DeskPlacement = null) -> SeatPlan:
	var result := SeatPlan.new()
	var previous_seats: Dictionary[String, SeatPlacement] = {}
	if previous != null:
		for seat in previous.seats:
			previous_seats[seat.pane_key] = seat
	var groups: Dictionary[int, Column] = {}
	var missing: Array[PaneModel] = []
	for pane in room.panes:
		if not pane.explicit_layout:
			missing.append(pane)
			continue
		if not groups.has(pane.table_x):
			var group := Column.new()
			group.source_x = pane.table_x
			groups[pane.table_x] = group
		groups[pane.table_x].panes.append(pane)
	var ordered: Array[Column] = groups.values()
	ordered.sort_custom(func(a: Column, b: Column) -> bool: return a.source_x < b.source_x)
	var lower := 0
	var can_retain := true
	for group in ordered:
		group.panes.sort_custom(_by_hint)
		var anchor := -1
		for pane in group.panes:
			var old: SeatPlacement = previous_seats.get(pane.key)
			if old == null:
				continue
			if anchor >= 0 and anchor != old.column:
				can_retain = false
			anchor = old.column
		if anchor >= 0 and anchor < lower:
			can_retain = false
		group.slot = maxi(lower, anchor)
		lower = group.slot + 1
	if not can_retain:
		for index in ordered.size():
			ordered[index].slot = index
	var occupied: Dictionary[String, bool] = {}
	var overflow: Array[PaneModel] = []
	var extent := 0
	for group in ordered:
		extent = maxi(extent, group.slot + 1)
		for pane in group.panes:
			if occupied.has(_seat_key(group.slot, pane.side)):
				overflow.append(pane)
				continue
			_add(result, occupied, room.key, pane.key, group.slot, pane.side)
	for pane in overflow:
		_add(result, occupied, room.key, pane.key, extent, pane.side)
		extent += 1
	if not overflow.is_empty():
		result.diagnostics.append("%s: conflicting terminal rows use extra seat columns" % room.key)
	missing.sort_custom(func(a: PaneModel, b: PaneModel) -> bool: return a.key < b.key)
	var displaced: Array[PaneModel] = []
	var fresh: Array[PaneModel] = []
	for pane in missing:
		var old: SeatPlacement = previous_seats.get(pane.key)
		if old == null:
			fresh.append(pane)
		elif occupied.has(_seat_key(old.column, old.side)):
			displaced.append(pane)
		else:
			_add(result, occupied, room.key, pane.key, old.column, old.side)
			extent = maxi(extent, old.column + 1)
	var old_capacity := previous.capacity if previous != null else 0
	var limit := maxi(extent, old_capacity)
	var free_far: Array[int] = []
	var free_near: Array[int] = []
	for column in limit:
		if not occupied.has(_seat_key(column, "far")):
			free_far.append(column)
		if not occupied.has(_seat_key(column, "near")):
			free_near.append(column)
	for pane in displaced:
		var old := previous_seats[pane.key]
		var available := free_far if old.side == "far" else free_near
		var nearest := limit
		if available.is_empty():
			limit += 1
			if old.side == "far":
				free_near.append(nearest)
			else:
				free_far.append(nearest)
		else:
			var index := mini(available.bsearch(old.column), available.size() - 1)
			if index > 0 and absi(available[index - 1] - old.column) <= absi(available[index] - old.column):
				index -= 1
			nearest = available[index]
			available.remove_at(index)
		_add(result, occupied, room.key, pane.key, nearest, old.side)
		extent = maxi(extent, nearest + 1)
	var column := 0
	for pane in fresh:
		while occupied.has(_seat_key(column, "far")) and occupied.has(_seat_key(column, "near")):
			column += 1
		var side := "near" if occupied.has(_seat_key(column, "far")) else "far"
		_add(result, occupied, room.key, pane.key, column, side)
		extent = maxi(extent, column + 1)
	result.capacity = maxi(old_capacity, maxi(2, 2 * ceili(extent / 2.0)))
	result.seats.sort_custom(func(a: SeatPlacement, b: SeatPlacement) -> bool: return a.pane_key < b.pane_key)
	return result


static func _by_hint(a: PaneModel, b: PaneModel) -> bool:
	return a.key < b.key if a.layout_order == b.layout_order else a.layout_order < b.layout_order


static func _seat_key(column: int, side: String) -> String:
	return "%d:%s" % [column, side]


static func _add(
	result: SeatPlan, occupied: Dictionary[String, bool], tab_key: String, pane_key: String, column: int, side: String
) -> void:
	var placed := SeatPlacement.new()
	placed.pane_key = pane_key
	placed.tab_key = tab_key
	placed.column = column
	placed.side = side
	result.seats.append(placed)
	occupied[_seat_key(column, side)] = true
