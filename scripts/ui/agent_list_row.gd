class_name AgentListRow
extends Button
## One pane, or one attention record, in the agent list: its presence icon, the
## provider and its label, and on the right how long it has waited, UNREAD, or
## why it is quiet. Kept for as long as its pane (or record) exists and updated
## in place, so the icon keeps its pulse across refreshes and view switches.
##
## The icon is a StatusBadge. While a live blocked pane waits, the label on
## the right is handed to it: OfficeAttention writes that number on the same
## beat and in the same words as the badge over the desk and the card's clock,
## and writes none for a dropped machine. Otherwise the label is the row's own.
##
## A refresh that changes nothing on a row writes nothing to it (Look).

## A click: select this pane, like clicking its desk.
signal picked(key: String)
## A double-click: open this pane (the monitor, once it lands).
signal activated(key: String)
## A right-click or the `…` button: this row's local actions, at `at` on screen.
signal menu_requested(key: String, at: Vector2)

## Palette-driven looks for the row that is selected and the rest.
const LOOKS := {
	true: {"row": &"ListRowCurrent", "name": &"LabelPaper", "detail": &"LabelPaper", "note": &"LabelPaper"},
	false: {"row": &"ListRow", "name": &"LabelWoodDark", "detail": &"LabelSlate", "note": &"LabelSlate"},
}

## Presence -> the pack image the icon wears: a state (its badge), or one of
## the two UI overlays for a pane still launching and a machine that dropped.
const MARKS: Dictionary[AgentListModel.Presence, StringName] = {
	AgentListModel.Presence.BLOCKED: ArtContract.STATE_BLOCKED,
	AgentListModel.Presence.UNREAD: ArtContract.STATE_DONE,
	AgentListModel.Presence.WORKING: ArtContract.STATE_WORKING,
	AgentListModel.Presence.IDLE: ArtContract.STATE_IDLE,
	AgentListModel.Presence.UNKNOWN: ArtContract.STATE_UNKNOWN,
	AgentListModel.Presence.STARTING: ArtContract.UI_STARTING,
	AgentListModel.Presence.OFFLINE: ArtContract.UI_OFFLINE,
	AgentListModel.Presence.SHELL: &"",
}


## Everything a row shows, as one typed value: show_entry() compares it with
## the one drawn and touches no node while they are the same. The tooltip is
## not in it; it is written only when asked for (_get_tooltip()).
class Look:
	extends RefCounted
	var kind := AgentListModel.Kind.PANE
	var title := ""
	var detail := ""
	var note := ""
	var mark := &""
	var presence := AgentListModel.Presence.UNKNOWN
	var muted := false
	var depth := 0
	var current := false
	var grey := false
	var actions := false
	## The badge's clock: a live blocked or UNREAD pane pulses and (blocked)
	## has its wait written; everything else rests.
	var pulse := &""
	var machine := ""
	var pane_id := ""

	## Whether `entry`, `current` or not, looks exactly like this: compared
	## field by field, so an unchanged row costs no allocation at all.
	func shows(entry: AgentListModel.Entry, is_current: bool) -> bool:
		return (
			current == is_current
			and kind == entry.kind
			and title == entry.title
			and detail == entry.detail
			and note == entry.note
			and depth == entry.depth
			and presence == entry.presence
			and muted == entry.muted
			and actions == AgentListRow.has_actions(entry)
			and machine == entry.machine
			and pane_id == entry.pane_id
		)


## The composite pane key, or `history:<pane key>`; empty until show_entry().
var key := ""
var presence := AgentListModel.Presence.UNKNOWN
## How many times this row has written its nodes: a refresh that changes
## nothing on it adds none (diagnostic, like the office's layout attempts).
var draws := 0

var _art: ArtPack
## What the row shows now; null until the first show_entry() and after rest().
var _look: Look
## Inside the list's scroll box. The renderer culls a row's labels that are
## scrolled out of it, but not its badge (a Sprite2D under the clip): measured,
## 75 of them cost 29 draw calls at 80 panes. The list says which rows are in.
var _in_view := true
## The line last shown, for the tooltip.
var _entry: AgentListModel.Entry
var _now := 0


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(key))
	var more: Button = %More
	more.pressed.connect(func() -> void: menu_requested.emit(key, more.get_global_rect().end))


## Take the pack's icon art. A theme switch calls this again and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	_draw_badge()


## Draw `entry`; `current` is the row the list has selected. Nothing is written
## when the row already shows exactly this.
func show_entry(entry: AgentListModel.Entry, current: bool, now_msec: int) -> void:
	key = entry.key
	presence = entry.presence
	_entry = entry
	_now = now_msec
	if _look != null and _look.shows(entry, current):
		return
	var next := look_of(entry, current)
	var was := _look
	_look = next
	draws += 1
	var tones: Dictionary = LOOKS[current]
	theme_type_variation = tones.row
	var name_label: Label = %Name
	var detail: Label = %Detail
	var tail: Label = %Tail
	name_label.text = next.title
	name_label.theme_type_variation = tones.name if not next.grey or current else &"LabelMuted"
	detail.text = next.detail
	detail.theme_type_variation = tones.detail if not next.grey or current else &"LabelMuted"
	var indent: PanelContainer = %Indent
	indent.visible = next.depth > 0
	indent.theme_type_variation = StringName("ListIndent%d" % next.depth)
	# The `…` only on the selected row: on every row it would take the label's
	# room. A right-click opens the same menu on any row that has one.
	var more: Button = %More
	more.visible = next.actions and current
	if was == null or was.mark != next.mark:
		_draw_badge()
	# One label on the right: the wait the attention clock writes while a live
	# blocked pane waits, else this row's own word (UNREAD, OFFLINE …).
	var badge: StatusBadge = %Badge
	if next.pulse == ArtContract.STATE_BLOCKED:
		tail.theme_type_variation = tones.name
		if was == null or was.pulse != next.pulse:
			tail.text = ""
		badge.wait = tail
		badge.pulse_for(next.machine, next.pane_id, next.pulse)
		return
	badge.wait = null
	if next.pulse.is_empty():
		badge.stop_pulsing()
	else:
		badge.pulse_for(next.machine, next.pane_id, next.pulse)
	tail.text = next.note
	tail.theme_type_variation = tones.note if not next.grey or current else &"LabelMuted"


## Whether the row is inside the list's scroll box; only then is its badge drawn.
## It keeps pulsing and keeps its wait either way.
func set_in_view(inside: bool) -> void:
	if inside == _in_view:
		return
	_in_view = inside
	var badge: StatusBadge = %Badge
	badge.visible = inside and not mark().is_empty()


## The row is no longer drawn (its group folded, the filter left it out): its
## badge stops pulsing, and the next show_entry() draws it afresh.
func rest() -> void:
	if _look == null:
		return
	_look = null
	var badge: StatusBadge = %Badge
	badge.wait = null
	badge.stop_pulsing()


## What `entry` looks like on a row, `current` or not.
static func look_of(entry: AgentListModel.Entry, current: bool) -> Look:
	var look := Look.new()
	look.kind = entry.kind
	look.title = entry.title
	look.detail = entry.detail
	look.note = entry.note
	look.mark = MARKS.get(entry.presence, ArtContract.STATE_UNKNOWN)
	look.presence = entry.presence
	look.muted = entry.muted
	look.depth = entry.depth
	look.current = current
	look.grey = entry.presence == AgentListModel.Presence.OFFLINE or entry.kind == AgentListModel.Kind.HISTORY
	look.actions = has_actions(entry)
	var live := entry.kind == AgentListModel.Kind.PANE and not entry.muted
	if live and entry.presence == AgentListModel.Presence.BLOCKED:
		look.pulse = ArtContract.STATE_BLOCKED
	elif live and entry.presence == AgentListModel.Presence.UNREAD:
		look.pulse = ArtContract.STATE_DONE
	look.machine = entry.machine
	look.pane_id = entry.pane_id
	return look


## The badge beside the name, for the tests that follow its pulse and wait.
func icon_badge() -> StatusBadge:
	return %Badge


## The pack image the icon wears: a state's name, or a UI overlay's id; empty
## for a shell, which wears none.
func mark() -> StringName:
	return &"" if _look == null else _look.mark


## Everything the row has no room for, written only when the pointer asks.
func _get_tooltip(_at_position: Vector2) -> String:
	return "" if _entry == null else _tooltip(_entry, _now)


## A double-click opens; a right-click asks for the actions. Both are this
## row's own: the list and the office never see them.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT and click.double_click:
		accept_event()
		activated.emit(key)
	elif click.button_index == MOUSE_BUTTON_RIGHT and _has_menu():
		accept_event()
		menu_requested.emit(key, click.global_position)


## Snooze and hide belong to a pane's attention episode; a History line has
## View (greyed out once it cannot be located).
func _has_menu() -> bool:
	return _look != null and _look.actions


## Whether `entry`'s row has a menu (and its `…`): a live episode or a History line.
static func has_actions(entry: AgentListModel.Entry) -> bool:
	return entry.item != null or entry.history != null


## Everything the row has no room for: where the pane is, and for a History
## line what became of it, how often it was blocked and for how long.
static func _tooltip(entry: AgentListModel.Entry, now_msec: int) -> String:
	var lines := PackedStringArray([entry.title + ("  " + entry.detail if not entry.detail.is_empty() else "")])
	if entry.kind == AgentListModel.Kind.PANE:
		var pane := entry.pane
		var workspace := pane.workspace_label if not pane.workspace_label.is_empty() else "Unknown workspace"
		var tab := pane.tab_label if not pane.tab_label.is_empty() else "Unknown tab"
		lines.append("%s / %s" % [workspace, tab])
		if entry.presence == AgentListModel.Presence.OFFLINE:
			lines.append("Offline · last state unknown")
	if entry.history != null:
		var line := entry.history
		var workspace := line.space if not line.space.is_empty() else "Unknown workspace"
		var tab := line.tab if not line.tab.is_empty() else "Unknown tab"
		lines.append("%s / %s / %s" % [line.machine_label, workspace, tab])
		lines.append(AgentHistory.tooltip_of(line))
	var item := entry.item
	if item != null:
		if item.hidden:
			lines.append("Hidden locally")
		if item.is_snoozed(now_msec):
			var remaining := maxf(0.0, (item.snoozed_until_msec - now_msec) / 1000.0)
			lines.append("Snoozed locally · " + OfficeAttention.format_duration(remaining))
	return "\n".join(lines)


func _draw_badge() -> void:
	if _art == null:
		return
	var badge: StatusBadge = %Badge
	var wanted := mark()
	if wanted.is_empty():
		badge.clear(_art)
		return
	# A state names its badge in the pack; the two overlays are UI images.
	var drawn := _art.state(wanted)
	var id: StringName = drawn.badge if drawn != null else wanted
	if _art.ui_sprite(id) == null:
		id = _art.state(ArtContract.STATE_UNKNOWN).badge
	badge.show_badge(_art, id)
	badge.visible = _in_view
	# Every UI image declares its own pivot; the sprite stands at it inside its
	# square, so whatever the pack says the picture lands in the same place.
	badge.position = _art.ui_sprite(id).pivot
