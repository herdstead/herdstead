class_name OfficeOverview
extends HdPanel
## The OVERVIEW (scenes/ui/overview.tscn): one row per pane with its state,
## how long, its blocked time and count, and its timeline since this office
## opened, over the world and both side columns. The PANES counter or `O`
## opens it; `X  Esc`, Esc or `O` again closes it. A column head sorts by that
## column (again: the other way), a chip keeps one of herdr's states, and a
## row picks its pane, as a click on its desk does; the staff panel below
## stays, and answers as it always does.
##
## It draws an OverviewModel and nothing else: rows are pooled by pane key
## (a row whose pane went is dropped, one the filter leaves out is hidden),
## ordered with move_child, and a label is written only when its text changes.
## Where everything stands is the scene's.

## A row was pressed: the office picks pane `key`.
signal picked(key: String)
## The overview closed (its `X  Esc`, or close()).
signal closed
## A column head was pressed: the rows are to be ordered by `sort`.
signal sort_changed(sort: OverviewModel.Sort, descending: bool)
## A chip was pressed, or set_filter() called.
signal filter_changed(filter: OverviewModel.Filter)

const LINE_SCENE := preload("res://scenes/ui/overview_line.tscn")
## Each column head's node and its word.
const HEADS: Dictionary[OverviewModel.Sort, String] = {
	OverviewModel.Sort.AGENT: "%HeadAgent",
	OverviewModel.Sort.SPACE: "%HeadSpace",
	OverviewModel.Sort.STATE: "%HeadState",
	OverviewModel.Sort.FOR: "%HeadFor",
	OverviewModel.Sort.BLOCKED: "%HeadBlocked",
	OverviewModel.Sort.TIMES: "%HeadTimes",
}
const HEAD_WORDS: Dictionary[OverviewModel.Sort, String] = {
	OverviewModel.Sort.AGENT: "AGENT",
	OverviewModel.Sort.SPACE: "SPACE / TAB",
	OverviewModel.Sort.STATE: "STATE",
	OverviewModel.Sort.FOR: "FOR",
	OverviewModel.Sort.BLOCKED: "BLOCKED",
	OverviewModel.Sort.TIMES: "TIMES",
}
const CHIPS: Dictionary[OverviewModel.Filter, String] = {
	OverviewModel.Filter.ALL: "%ChipAll",
	OverviewModel.Filter.BLOCKED: "%ChipBlocked",
	OverviewModel.Filter.DONE: "%ChipDone",
	OverviewModel.Filter.WORKING: "%ChipWorking",
	OverviewModel.Filter.IDLE: "%ChipIdle",
}
## The arrow a sorted head carries: rows descending, or ascending.
const DOWN := " ▾"
const UP := " ▴"

## Pane key -> its row, shown or hidden.
var _lines: Dictionary[String, OverviewLine] = {}
var _sort := OverviewModel.Sort.STATE
var _descending := false
var _filter := OverviewModel.Filter.ALL
var _compact := false
## The row last shown selected: a new one is scrolled into view once.
var _selected := ""


func _ready() -> void:
	for by: OverviewModel.Sort in HEADS:
		var head: Button = get_node(HEADS[by])
		head.pressed.connect(_on_head.bind(by))
	for keep: OverviewModel.Filter in CHIPS:
		var chip: Button = get_node(CHIPS[keep])
		chip.pressed.connect(_on_chip.bind(keep))
	var close_button: Button = %Close
	close_button.pressed.connect(close)
	# The table's own scroll bar: the theme's thin one, shown only when rows
	# overflow (the scroll reserves its room either way), and never focused, so
	# the arrow keys stay the office's (_overview_key()) to scroll with.
	var scroll: ScrollContainer = %Scroll
	var bar := scroll.get_v_scroll_bar()
	bar.theme_type_variation = &"OverviewScroll"
	bar.focus_mode = Control.FOCUS_NONE
	_label_heads()


## The pack's panel, and every row's badge art. A theme switch calls this again.
func dress(pack: ArtPack) -> void:
	super(pack)
	for line: OverviewLine in _lines.values():
		line.dress(pack)


func open() -> void:
	visible = true


## Hide, and say so once.
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func sort() -> OverviewModel.Sort:
	return _sort


func descending() -> bool:
	return _descending


func filter() -> OverviewModel.Filter:
	return _filter


## Keep only `keep`'s rows: its chip reads pressed, and filter_changed says so.
func set_filter(keep: OverviewModel.Filter) -> void:
	_filter = keep
	var chip: Button = get_node(CHIPS[keep])
	if not chip.button_pressed:
		chip.button_pressed = true
	filter_changed.emit(keep)


## A narrow screen: BLOCKED and TIMES are left out, heads and rows alike, and
## the summary beside the title (its words are the title's tooltip).
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	# The summary too: beside the title and the chips it would have a sliver
	# at 480 wide. Its words stay on the title's tooltip.
	var summary: Label = %Summary
	summary.visible = not on
	for unique: String in ["%HeadBlocked", "%HeadTimes"]:
		var head: Button = get_node(unique)
		head.visible = not on
	for line: OverviewLine in _lines.values():
		line.set_compact(on)


func compact() -> bool:
	return _compact


## One step of the table's scroll, a row high: the arrow keys while it is open.
func scroll_rows(direction: int) -> void:
	var scroll: ScrollContainer = %Scroll
	var rows: VBoxContainer = %Rows
	if rows.get_child_count() == 0:
		return
	var first: Control = rows.get_child(0)
	scroll.scroll_vertical += direction * int(first.size.y)


## Draw `model`: its rows in its order, each row's timeline over its span,
## the heading's summary and the axis.
func show_overview(model: OverviewModel, pack: ArtPack) -> void:
	var rows: VBoxContainer = %Rows
	var shown: Dictionary[String, bool] = {}
	for index in model.rows.size():
		var row := model.rows[index]
		shown[row.key] = true
		var line: OverviewLine = _lines.get(row.key)
		if line == null:
			line = _make(row.key, pack)
		if not line.visible:
			line.visible = true
		line.show_row(row, model.opened_msec, model.now_msec)
		if line.get_index() != index:
			rows.move_child(line, index)
		if row.selected and row.key != _selected:
			var scroll: ScrollContainer = %Scroll
			scroll.ensure_control_visible.call_deferred(line)
	_selected = ""
	for row in model.rows:
		if row.selected:
			_selected = row.key
	for key: String in _lines.keys():
		if shown.has(key):
			continue
		if model.tracked.has(key):
			_lines[key].visible = false
		else:
			_drop(key)
	var summary: Label = %Summary
	var said := "%d panes · nothing observed yet · this session only" % model.panes
	if model.opened_unix >= 0.0:
		said = (
			"%d panes · since opened %s (%s) · this session only"
			% [
				model.panes,
				OfficeAttention.wall_clock(model.opened_unix),
				OfficeAttention.format_duration(model.since_opened_msec / 1000.0),
			]
		)
	if summary.text != said:
		summary.text = said
	var title: Label = %Title
	if title.tooltip_text != said:
		title.tooltip_text = said
	var axis: OverviewAxis = %Axis
	axis.show_span(model.opened_unix, model.since_opened_msec)


## The row for pane `key`, shown or not; null when there is none.
func line_for(key: String) -> OverviewLine:
	return _lines.get(key)


## The panes whose rows show, top to bottom.
func shown_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	var rows: VBoxContainer = %Rows
	for child in rows.get_children():
		var line := child as OverviewLine
		if line != null and line.visible:
			keys.append(line.key)
	return keys


func _make(key: String, pack: ArtPack) -> OverviewLine:
	var line: OverviewLine = LINE_SCENE.instantiate()
	line.key = key
	var rows: VBoxContainer = %Rows
	rows.add_child(line)
	line.dress(pack)
	line.set_compact(_compact)
	line.picked.connect(func(picked_key: String) -> void: picked.emit(picked_key))
	_lines[key] = line
	return line


func _drop(key: String) -> void:
	var line: OverviewLine = _lines[key]
	_lines.erase(key)
	line.get_parent().remove_child(line)
	line.queue_free()


## A head pressed: that column in its natural order (OverviewModel
## .NATURALLY_DESCENDING), or, pressed again, the other way.
func _on_head(by: OverviewModel.Sort) -> void:
	if by == _sort:
		_descending = not _descending
	else:
		_sort = by
		_descending = by in OverviewModel.NATURALLY_DESCENDING
	_label_heads()
	sort_changed.emit(_sort, _descending)


func _on_chip(keep: OverviewModel.Filter) -> void:
	if keep == _filter:
		return
	set_filter(keep)


## The sorted column's head carries its arrow; the others their word alone.
func _label_heads() -> void:
	for by: OverviewModel.Sort in HEADS:
		var head: Button = get_node(HEADS[by])
		var said := HEAD_WORDS[by]
		if by == _sort:
			said += DOWN if _descending else UP
		if head.text != said:
			head.text = said
