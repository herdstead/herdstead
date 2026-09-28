class_name EventList
extends HdPanel
## The drawer's EVENTS page: the fleet's StateLog events as rows (EventRow),
## newest on top, the NEWS strip's entries and older ones in the same words.
## A click on a row picks its pane, as the agent list does.
##
## Plain log data in, pane keys out. Rows are kept by event id and changed in
## place; a row is made the first time its event is drawn and dropped when the
## log's ring lets the event go, or it falls below the ROWS_MAX newest. Nothing
## is laid out while the page is out of sight: the office shows it only then.

## A pickable row was clicked: pick pane `pane_key`.
signal picked(pane_key: String)
## The mouse came onto a row about pane `pane_key`, or left it (`""`).
signal pointed(pane_key: String)

## The newest events drawn; the log keeps up to StateLog.EVENTS_MAX.
const ROWS_MAX := 200

@export var row_scene: PackedScene

var _rows: Dictionary[int, EventRow] = {}


func _ready() -> void:
	# The drawer's thin bar, shown only when rows overflow (the scroll reserves
	# its room either way), never focused.
	var scroll: ScrollContainer = %Scroll
	var bar := scroll.get_v_scroll_bar()
	bar.theme_type_variation = &"DrawerScroll"
	bar.focus_mode = Control.FOCUS_NONE


## Draw `events` (StateLog.events(), oldest first), newest on top: `pickable`
## says whether a pane key is still there to pick, `selected` is the office's
## selected pane (its newest row is highlighted), `opened_unix` when the log
## began. `several` machines add `@ machine` to a pane's row.
func show_events(
	events: Array[StateLog.Event], pickable: Callable, selected: String, opened_unix: float, several := false
) -> void:
	var since: Label = %Since
	var said := "since %s · %d events" % [OfficeAttention.wall_clock(opened_unix), events.size()]
	if opened_unix < 0.0:
		said = ""
	if since.text != said:
		since.text = said
	var wanted: Array[EventRow] = []
	var current_done := false
	for index in range(events.size() - 1, maxi(events.size() - ROWS_MAX, 0) - 1, -1):
		var event := events[index]
		var row: EventRow = _rows.get(event.id)
		if row == null:
			row = _row(event.id)
		var current := not current_done and not selected.is_empty() and event.pane_key == selected
		current_done = current_done or current
		var can_pick: bool = not event.pane_key.is_empty() and pickable.call(event.pane_key)
		row.show_event(event, several, can_pick, current)
		wanted.append(row)
	_keep(wanted)
	var empty: Label = %Empty
	empty.visible = wanted.is_empty()


## The row drawn for event `id`, or null.
func row_for(id: int) -> EventRow:
	return _rows.get(id)


## The ids of the rows drawn, top to bottom.
func shown_ids() -> PackedInt64Array:
	var result := PackedInt64Array()
	for node in _rows_box().get_children():
		var row := node as EventRow
		if row != null:
			result.append(row.event_id)
	return result


## Take the pack's art, here and in every row. A theme switch rebuilds nothing.
func dress(pack: ArtPack) -> void:
	super(pack)
	for id: int in _rows:
		_rows[id].dress(pack)


## Drop the rows whose events are gone and put the rest in `wanted`'s order.
## Nothing already in its place is moved.
func _keep(wanted: Array[EventRow]) -> void:
	var keep: Dictionary[int, bool] = {}
	for row in wanted:
		keep[row.event_id] = true
	for id: int in _rows.keys():
		if not keep.has(id):
			var gone := _rows[id]
			_rows.erase(id)
			_rows_box().remove_child(gone)
			gone.queue_free()
	var box := _rows_box()
	for index in wanted.size():
		if box.get_child(index) != wanted[index]:
			box.move_child(wanted[index], index)


func _row(id: int) -> EventRow:
	var row: EventRow = row_scene.instantiate()
	row.picked.connect(func(key: String) -> void: picked.emit(key))
	row.mouse_entered.connect(func() -> void: pointed.emit(row.pane_key))
	row.mouse_exited.connect(func() -> void: pointed.emit(""))
	_rows_box().add_child(row)
	if art != null:
		row.dress(art)
	_rows[id] = row
	return row


func _rows_box() -> VBoxContainer:
	return %Rows
