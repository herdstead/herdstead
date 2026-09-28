class_name AgentList
extends HdPanel
## The right-hand drawer's agent list, like an IM client's contacts: every pane of every
## machine, flat by urgency or as herdr's tree (AgentListModel), with a filter
## box, folding groups and the local attention actions on each row.
##
## Plain model data in, pane keys and attention record ids out: it knows no
## herdr and no machine, and the office decides what a pick means. Rows and
## headers are kept by key and changed in place; a node is made the first time
## its line is drawn and dropped only when its pane, History line or group is gone.
##
## Out of sight (the drawer closed, or its EVENTS page shown) it renders
## nothing: what it is given is kept, and rendered once it can be seen again
## (NOTIFICATION_VISIBILITY_CHANGED) or a reader asks first, so every reader
## sees the latest. The nodes stay as they are meanwhile.
##
## Keys are the list's only while it holds the keyboard: Up/Down move the
## cursor (and pick the pane under it), Left/Right fold and unfold, Enter opens
## like a double-click, the Menu key (Shift+F10, `.`) opens the row's actions,
## Escape lets go. Every other key goes on to the office.

## A pane was chosen, by a click or by the cursor landing on it.
signal pane_picked(key: String, by_keyboard: bool)
## A pane was opened: a double-click, Enter, or the row menu's Open.
signal pane_activated(key: String)
## The mouse came onto a row about pane `key`, or left it (`""`).
signal pane_pointed(key: String)
signal snooze_requested(id: String, seconds: int)
signal hidden_changed(id: String, is_hidden: bool)
## A History line's View: pick pane `key` again, if it still is that terminal.
signal history_locate_requested(key: String)
## The view or a fold changed: what the office may remember between runs.
signal layout_changed
## The list, or its filter box, took or lost the keyboard.
signal keyboard_changed

enum Action { OPEN, SNOOZE, HIDE, VIEW }

const SNOOZE_SECONDS := 300

@export var row_scene: PackedScene
@export var group_scene: PackedScene

var view := AgentListModel.View.FLAT
## How many times the rows were rendered, for tests (like
## OfficeStrategicPlan.draws): none while the list is out of sight.
var renders := 0

## Group key -> folded, for the groups the viewer folded or unfolded.
var _collapsed: Dictionary[String, bool] = {}
var _rows: Dictionary[String, AgentListRow] = {}
var _groups: Dictionary[String, AgentListGroup] = {}
var _entries: Array[AgentListModel.Entry] = []
var _entry_by_key: Dictionary[String, AgentListModel.Entry] = {}
## What the last show_agents() was given, so a fold or the filter redraws it.
var _office_frame := OfficeFrame.new()
var _active: Array[AttentionItem] = []
var _history: Array[AgentHistory.Line] = []
var _now := 0
## The pane the office has selected, and the list's keyboard cursor.
var _selected := ""
var _cursor := ""
var _reveal_pending := false
## The rows are laid out and the scroll is yet to measure them (_on_rows_sorted()).
var _revealing := false
var _menu_key := ""
## The top bar's state filter (WORKING, IDLE); empty shows every state.
var _presences: Array[AgentListModel.Presence] = []
## Something changed while the list was out of sight: render it before it is
## seen or read (_flush()).
var _dirty := false


func _ready() -> void:
	var flat: Button = %Flat
	var tree: Button = %Tree
	flat.pressed.connect(set_view.bind(AgentListModel.View.FLAT))
	tree.pressed.connect(set_view.bind(AgentListModel.View.TREE))
	var filter: LineEdit = %Filter
	filter.text_changed.connect(func(_text: String) -> void: _render())
	filter.text_submitted.connect(func(_text: String) -> void: _activate())
	var menu: PopupMenu = %Actions
	menu.id_pressed.connect(_on_action)
	for control: Control in [self, filter]:
		control.focus_entered.connect(_on_focus_moved)
		control.focus_exited.connect(_on_focus_moved)
	_rows_box().sort_children.connect(_on_rows_sorted)
	# The drawer's thin bar, shown only when rows overflow (the scroll reserves
	# its room either way), never focused: the arrows move the list's cursor.
	var scroll: ScrollContainer = %Scroll
	var bar := scroll.get_v_scroll_bar()
	bar.theme_type_variation = &"DrawerScroll"
	bar.focus_mode = Control.FOCUS_NONE
	bar.value_changed.connect(func(_value: float) -> void: _mark_in_view())
	scroll.resized.connect(_mark_in_view)
	scroll.sort_children.connect(_on_scroll_sorted)
	_show_view_buttons()


## Take the pack's art, here and in every row. A theme switch rebuilds nothing.
func dress(pack: ArtPack) -> void:
	super(pack)
	for key: String in _rows:
		_rows[key].dress(pack)


## Coming into sight (the drawer opened, AGENTS shown) renders what was kept.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_flush()


## Draw `frame`'s panes, with `active` (AttentionStore.active(): the episodes
## Snooze and Hide act on) and the History group's `history` (AgentHistory.of()),
## the pane `selected` (the office's selection) highlighted. `now_msec` judges snoozes.
func show_agents(
	frame: OfficeFrame, active: Array[AttentionItem], history: Array[AgentHistory.Line], selected: String, now_msec: int
) -> void:
	_office_frame = frame
	_active = active
	_history = history
	_now = now_msec
	if selected != _selected:
		# The first selection is herdr's focus at startup: the list opens at
		# its top, on who is waiting, not scrolled to that pane.
		_reveal_pending = not _selected.is_empty()
		_selected = selected
		# A pick from anywhere (a desk, `N`, the cursor itself) moves the cursor.
		_cursor = selected
	_render()


## Flat or tree. The rows are the same nodes in another order. `remember` is
## false when the list switches itself (taking the keyboard shows the flat
## view), which is not the viewer's choice to keep.
func set_view(next: AgentListModel.View, remember := true) -> void:
	if next == view:
		_show_view_buttons()
		return
	view = next
	_show_view_buttons()
	_reveal_pending = true
	_render()
	if remember:
		layout_changed.emit()


## Fold or unfold the group `key`.
func toggle(key: String) -> void:
	set_collapsed(key, not collapsed(key))


func set_collapsed(key: String, folded: bool) -> void:
	if collapsed(key) == folded:
		return
	_collapsed[key] = folded
	_render()
	layout_changed.emit()


func collapsed(key: String) -> bool:
	return AgentListModel.is_collapsed(key, _collapsed)


## The folds the viewer chose in the flat view, whose groups are the same in
## every run; the tree's name workspaces and tabs of this session only.
func flat_folds() -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for key: String in _collapsed:
		if AgentListModel.FLAT_GROUPS.has(key):
			result[key] = _collapsed[key]
	return result


## Folds and a view remembered from an earlier run; anything else is ignored.
func restore(flat_view: bool, folds: Dictionary[String, bool]) -> void:
	view = AgentListModel.View.FLAT if flat_view else AgentListModel.View.TREE
	for key: String in folds:
		if AgentListModel.FLAT_GROUPS.has(key):
			_collapsed[key] = folds[key]
	_show_view_buttons()
	_render()


## Whether the keyboard is the list's: it, or its filter box, has focus.
func has_keyboard() -> bool:
	if not is_inside_tree():
		return false
	var holder := get_viewport().gui_get_focus_owner()
	return holder != null and (holder == self or is_ancestor_of(holder))


## Take the keyboard in the flat view, the cursor on the selected pane.
func take_keyboard() -> void:
	_flush()
	set_view(AgentListModel.View.FLAT, false)
	_cursor = _selected if _shown(_selected) else _first_shown()
	_reveal_pending = true
	grab_focus()
	_render()


func release_keyboard() -> void:
	if has_keyboard():
		get_viewport().gui_get_focus_owner().release_focus()


## Show only the panes whose Presence is one of `presences` (the top bar's
## WORKING or IDLE counter); empty shows every state again.
func set_presence_filter(presences: Array[AgentListModel.Presence]) -> void:
	_presences = presences.duplicate()
	_render()


## The state filter set_presence_filter() left; empty for none.
func presence_filter() -> Array[AgentListModel.Presence]:
	return _presences.duplicate()


## Keys of the lines drawn now, top to bottom: groups, panes and history.
func shown_keys() -> PackedStringArray:
	_flush()
	var result := PackedStringArray()
	for entry in _entries:
		if entry.shown:
			result.append(entry.key)
	return result


func cursor() -> String:
	_flush()
	return _cursor


## The row drawn for pane `key` (or `history:<id>`), or null.
func row_for(key: String) -> AgentListRow:
	_flush()
	return _rows.get(key)


func group_for(key: String) -> AgentListGroup:
	_flush()
	return _groups.get(key)


## The line `key` as last built, or null.
func entry_for(key: String) -> AgentListModel.Entry:
	_flush()
	return _entry_by_key.get(key)


func _gui_input(event: InputEvent) -> void:
	super(event)
	if not event is InputEventKey or not event.is_pressed():
		return
	if event.is_action_pressed(&"ui_up", true):
		_move(-1)
	elif event.is_action_pressed(&"ui_down", true):
		_move(1)
	elif event.is_action_pressed(&"ui_left", true):
		_fold(true)
	elif event.is_action_pressed(&"ui_right", true):
		_fold(false)
	elif event.is_action_pressed(&"ui_accept"):
		_activate()
	elif event.is_action_pressed(&"list_row_menu", false, true):
		_menu_at_cursor()
	elif event.is_action_pressed(&"ui_cancel"):
		release_keyboard()
	else:
		return
	accept_event()


# --- drawing ------------------------------------------------------------------


## Render now if the list can be seen; out of sight, only remember to.
func _render() -> void:
	if not is_visible_in_tree():
		_dirty = true
		return
	_render_rows()


## Render what the list was last given, if it changed while out of sight.
func _flush() -> void:
	if _dirty:
		_render_rows()


func _render_rows() -> void:
	renders += 1
	_dirty = false
	var filter: LineEdit = %Filter
	# A folded History with no filter needs no lines, only its count.
	var history_lines := not collapsed(AgentListModel.FLAT_HISTORY) or not filter.text.strip_edges().is_empty()
	_entries = AgentListModel.build(_office_frame, _active, _history, view, _now, history_lines)
	AgentListModel.apply(_entries, _collapsed, filter.text, _presences)
	_entry_by_key.clear()
	for entry in _entries:
		_entry_by_key[entry.key] = entry
	if not _cursor.is_empty() and not _shown(_cursor) and has_keyboard():
		_cursor = _first_shown()
	var keyboard := has_keyboard()
	var highlight := _cursor if keyboard else _selected
	var wanted: Array[Control] = []
	var shown := 0
	for entry in _entries:
		var node: Control = null
		if entry.kind == AgentListModel.Kind.GROUP:
			node = _groups.get(entry.key)
			if node == null and entry.shown:
				node = _group(entry.key)
			if node != null and entry.shown:
				(node as AgentListGroup).show_group(entry, collapsed(entry.key), keyboard and entry.key == highlight)
		else:
			node = _rows.get(entry.key)
			if node == null and entry.shown:
				node = _row(entry.key)
			if node != null and entry.shown:
				(node as AgentListRow).show_entry(entry, entry.key == highlight, _now)
			elif node != null:
				(node as AgentListRow).rest()
		if node != null:
			node.visible = entry.shown
			wanted.append(node)
		if entry.shown:
			shown += 1
	_keep(wanted)
	var empty: Label = %Empty
	empty.visible = shown == 0
	var filtering := not filter.text.strip_edges().is_empty() or not _presences.is_empty()
	empty.text = "No agents match." if filtering else "No agents."


## Drop the nodes whose lines are gone and put the rest in `wanted`'s order.
## Nothing already in its place is touched.
func _keep(wanted: Array[Control]) -> void:
	var keep: Dictionary[Control, bool] = {}
	for node in wanted:
		keep[node] = true
	for key: String in _rows.keys():
		if not keep.has(_rows[key]):
			_drop(_rows[key])
			_rows.erase(key)
	for key: String in _groups.keys():
		if not keep.has(_groups[key]):
			_drop(_groups[key])
			_groups.erase(key)
	var box := _rows_box()
	for index in wanted.size():
		if box.get_child(index) != wanted[index]:
			box.move_child(wanted[index], index)


func _drop(node: Control) -> void:
	_rows_box().remove_child(node)
	node.queue_free()


func _row(key: String) -> AgentListRow:
	var row: AgentListRow = row_scene.instantiate()
	row.picked.connect(_on_row_picked)
	row.activated.connect(_on_row_activated)
	row.menu_requested.connect(_open_menu)
	row.mouse_entered.connect(func() -> void: pane_pointed.emit(row.key))
	row.mouse_exited.connect(func() -> void: pane_pointed.emit(""))
	_rows_box().add_child(row)
	if art != null:
		row.dress(art)
	_rows[key] = row
	return row


func _group(key: String) -> AgentListGroup:
	var group: AgentListGroup = group_scene.instantiate()
	group.toggled_open.connect(_on_group_pressed)
	_rows_box().add_child(group)
	_groups[key] = group
	return group


func _show_view_buttons() -> void:
	var flat: Button = %Flat
	var tree: Button = %Tree
	flat.set_pressed_no_signal(view == AgentListModel.View.FLAT)
	tree.set_pressed_no_signal(view == AgentListModel.View.TREE)


# --- the cursor ---------------------------------------------------------------


func _shown(key: String) -> bool:
	var entry: AgentListModel.Entry = _entry_by_key.get(key)
	return entry != null and entry.shown


func _first_shown() -> String:
	for entry in _entries:
		if entry.shown and entry.kind == AgentListModel.Kind.PANE:
			return entry.key
	for entry in _entries:
		if entry.shown:
			return entry.key
	return ""


## Up or Down one drawn line. Landing on a pane picks it, like a click.
func _move(step: int) -> void:
	var keys := shown_keys()
	if keys.is_empty():
		return
	var at := keys.find(_cursor)
	var next: String = keys[0 if at < 0 else clampi(at + step, 0, keys.size() - 1)]
	if next == _cursor and at >= 0:
		return
	_cursor = next
	_reveal_pending = true
	_render()
	var entry := _entry_by_key[next]
	if entry.kind == AgentListModel.Kind.PANE:
		pane_picked.emit(next, true)


## Left folds the group under the cursor, or a line's own group (the cursor
## goes to it); Right unfolds it, or steps into it when it is open already.
func _fold(folding: bool) -> void:
	var entry: AgentListModel.Entry = _entry_by_key.get(_cursor)
	if entry == null:
		return
	if entry.kind != AgentListModel.Kind.GROUP:
		if folding and not entry.parent.is_empty():
			_cursor = entry.parent
			_reveal_pending = true
			set_collapsed(entry.parent, true)
			_render()
		return
	if folding and collapsed(entry.key) and not entry.parent.is_empty():
		_cursor = entry.parent
		_reveal_pending = true
		_render()
	elif folding:
		set_collapsed(entry.key, true)
	elif collapsed(entry.key):
		set_collapsed(entry.key, false)
	else:
		_move(1)


## Enter: open the pane under the cursor, fold a group, View a history line.
func _activate() -> void:
	var entry: AgentListModel.Entry = _entry_by_key.get(_cursor)
	if entry == null:
		return
	match entry.kind:
		AgentListModel.Kind.GROUP:
			toggle(entry.key)
		AgentListModel.Kind.PANE:
			pane_activated.emit(entry.key)
		AgentListModel.Kind.HISTORY:
			if entry.history.locatable:
				history_locate_requested.emit(entry.history.key)


## Focus moving between the list and its filter box leaves it for a moment:
## what counts is where it is once it has moved.
func _on_focus_moved() -> void:
	_settle_focus.call_deferred()


func _settle_focus() -> void:
	_render()
	keyboard_changed.emit()


## A line to reveal waits for the scroll too: `%RowsGap` stands between it
## and the rows, so the scroll learns their new height (its minimum size, which
## sets how far it scrolls) only when asked again after they are laid out.
func _on_rows_sorted() -> void:
	_mark_in_view()
	if _reveal_pending:
		_reveal_pending = false
		_revealing = true
		var scroll: ScrollContainer = %Scroll
		scroll.update_minimum_size()
		scroll.queue_sort()


func _on_scroll_sorted() -> void:
	if _revealing:
		_revealing = false
		_reveal.call_deferred()


## Tell every row whether it is inside the scroll box, so only those draw
## their badge (see AgentListRow.set_in_view()). After each layout and scroll.
func _mark_in_view() -> void:
	var scroll: ScrollContainer = %Scroll
	var top := float(scroll.scroll_vertical)
	var bottom := top + scroll.size.y
	for row: AgentListRow in _rows.values():
		row.set_in_view(row.visible and row.position.y + row.size.y > top and row.position.y < bottom)


func _reveal() -> void:
	var node: Control = _rows.get(_cursor, _groups.get(_cursor))
	if node != null and node.visible:
		var scroll: ScrollContainer = %Scroll
		scroll.ensure_control_visible(node)


# --- mouse --------------------------------------------------------------------


func _on_row_picked(key: String) -> void:
	_cursor = key
	var entry: AgentListModel.Entry = _entry_by_key.get(key)
	if entry != null and entry.kind == AgentListModel.Kind.PANE:
		pane_picked.emit(key, false)
	else:
		_render()


func _on_row_activated(key: String) -> void:
	_cursor = key
	_activate()


func _on_group_pressed(key: String) -> void:
	_cursor = key
	toggle(key)


# --- the row menu -------------------------------------------------------------


## The actions a line offers, as a native popup: a pane with a live attention
## episode has Open, Snooze and Hide; a History line only View (Details when
## its pane stands on no floor), greyed out once it cannot be located. Local
## only: none of them changes herdr.
func _open_menu(key: String, at: Vector2) -> void:
	var entry: AgentListModel.Entry = _entry_by_key.get(key)
	if entry == null or (entry.item == null and entry.history == null):
		return
	_menu_key = key
	var menu: PopupMenu = %Actions
	menu.clear()
	if entry.history != null:
		var seated := not _office_frame.floor_of(entry.history.key).is_empty()
		menu.add_item("View" if entry.history.locatable and seated else "Details", Action.VIEW)
		menu.set_item_disabled(menu.get_item_index(Action.VIEW), not entry.history.locatable)
		_pop(menu, at)
		return
	var item := entry.item
	menu.add_item("Open", Action.OPEN)
	var snoozed := item.is_snoozed(_now)
	menu.add_item("Resume reminder" if snoozed else "Snooze 5 min", Action.SNOOZE)
	menu.set_item_disabled(menu.get_item_index(Action.SNOOZE), not item.active or item.stale or not item.available)
	menu.add_item("Restore" if item.hidden else "Hide", Action.HIDE)
	_pop(menu, at)


func _pop(menu: PopupMenu, at: Vector2) -> void:
	menu.reset_size()
	menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


## The Menu key, Shift+F10 or `.` (InputMap `list_row_menu`): the cursor
## row's menu, under the row, to choose from with the keyboard. A row without
## actions opens nothing.
func _menu_at_cursor() -> void:
	var row: AgentListRow = _rows.get(_cursor)
	if row == null or not row.visible:
		return
	var box := row.get_global_rect()
	_open_menu(_cursor, Vector2(box.position.x, box.end.y))
	var menu: PopupMenu = %Actions
	if menu.visible and menu.item_count > 0:
		menu.set_focused_item(0)


## What a menu entry does, for the line it was opened on.
func _on_action(id: int) -> void:
	var entry: AgentListModel.Entry = _entry_by_key.get(_menu_key)
	if entry == null:
		return
	if entry.history != null:
		if id == Action.VIEW and entry.history.locatable:
			history_locate_requested.emit(entry.history.key)
		return
	var item := entry.item
	if item == null:
		return
	match id:
		Action.OPEN:
			pane_activated.emit(entry.key)
		Action.SNOOZE:
			snooze_requested.emit(item.id, 0 if item.is_snoozed(_now) else SNOOZE_SECONDS)
		Action.HIDE:
			hidden_changed.emit(item.id, not item.hidden)


## The menu, for tests that choose from it by real input.
func actions_menu() -> PopupMenu:
	return %Actions


func _rows_box() -> VBoxContainer:
	return %Rows
