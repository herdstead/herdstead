class_name EventRow
extends Button
## One event of the EVENTS page: its wall-clock time, the icon of the state it
## went to (a machine's connected or offline mark) and who, then on a line of
## its own what happened, in the NEWS strip's words (NewsItem.subject() /
## what()). That second line is the row's whole width, and the state a change
## went to (`→ working`) is a label of its own that never shrinks: in a narrow
## drawer the ended part (`working 1h 05m+`) is cut short, never the new state.
## A click picks the event's pane; a row whose pane is gone, or a machine's,
## cannot be clicked. Kept for as long as its event is in the log, updated in place.

## A click: pick this event's pane.
signal picked(pane_key: String)

## Palette-driven looks for the selected pane's row and the rest.
const LOOKS := {
	true: {"row": &"ListRowCurrent", "time": &"LabelPaper", "text": &"LabelPaper"},
	false: {"row": &"ListRow", "time": &"LabelSlate", "text": &"LabelWoodDark"},
}
## The row's words, for writing and for reading back.
const LINES: Array[String] = ["%Name", "%Ended", "%Now"]

## StateLog.Event.id of the event shown.
var event_id := -1
var pane_key := ""

var _art: ArtPack
var _mark := &""


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(pane_key))


## Take the pack's icon art. A theme switch calls this again and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	_draw_badge()


## Show `event`, `several` when the office shows more than one machine;
## `pickable` while its pane is still there to pick, `current` for the selected pane's row.
func show_event(event: StateLog.Event, several: bool, pickable: bool, current: bool) -> void:
	event_id = event.id
	pane_key = event.pane_key
	var tones: Dictionary = LOOKS[current]
	theme_type_variation = tones.row
	var time: Label = %Time
	var said := OfficeAttention.wall_clock(event.wall_unix)
	if time.text != said:
		time.text = said
	time.theme_type_variation = tones.time
	var subject := NewsItem.subject(event)
	if several and not NewsItem.is_machine(event):
		subject += " @ " + event.machine_label
	var before := NewsItem.ended(event)
	var words: Array[String] = [subject, NewsItem.what(event), ""]
	if not before.is_empty():
		words = [subject, before, "→ " + event.state]
	var tone: StringName = tones.text if pickable or current else &"LabelMuted"
	for index in LINES.size():
		var label: Label = get_node(LINES[index])
		if label.text != words[index]:
			label.text = words[index]
		label.theme_type_variation = tone
	disabled = not pickable
	# The whole of what happened first: a narrow drawer can cut the ended part short.
	if NewsItem.is_machine(event):
		tooltip_text = "%s · %s" % [event.machine_label, NewsItem.what(event)]
	else:
		tooltip_text = "%s\n%s" % [NewsItem.what(event), NewsItem.TIP_PICK if pickable else NewsItem.TIP_GONE]
	var wanted := mark_of(event)
	if wanted != _mark:
		_mark = wanted
		_draw_badge()


## The pack image the icon wears for `event`: the badge of the state it went
## to (unknown's for a pane that went, or has no state of herdr's), or the
## connected / offline mark for a machine.
static func mark_of(event: StateLog.Event) -> StringName:
	match event.kind:
		StateLog.Kind.MACHINE_ONLINE:
			return ArtContract.UI_CONNECTED
		StateLog.Kind.MACHINE_OFFLINE:
			return ArtContract.UI_OFFLINE
	if StateLog.STATES.has(event.state):
		return StringName(event.state)
	return ArtContract.STATE_UNKNOWN


## What the row says: who, then what happened (`working 38m → done`), as NEWS says it.
func shown_text() -> String:
	var name_label: Label = %Name
	var ended_label: Label = %Ended
	var now: Label = %Now
	return "%s\n%s" % [name_label.text, " ".join(PackedStringArray([ended_label.text, now.text])).strip_edges()]


## The UI image the icon shows: a state's badge as the pack names it, or the mark itself.
func mark() -> StringName:
	if _art == null or _mark.is_empty():
		return &""
	var drawn := _art.state(_mark)
	var id: StringName = drawn.badge if drawn != null else _mark
	if _art.ui_sprite(id) == null:
		id = _art.state(ArtContract.STATE_UNKNOWN).badge
	return id


func icon_badge() -> StatusBadge:
	return %Badge


func _draw_badge() -> void:
	if _art == null:
		return
	var badge: StatusBadge = %Badge
	var id := mark()
	if id.is_empty():
		badge.clear(_art)
		return
	badge.show_badge(_art, id)
	badge.visible = true
	# Every UI image declares its own pivot; the sprite stands at it inside its
	# square, as in the agent list's rows.
	badge.position = _art.ui_sprite(id).pivot
