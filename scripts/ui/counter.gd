class_name OfficeCounter
extends Button
## One of the top bar's counters (scenes/ui/counter.tscn): an icon, herdr's
## word for what it counts, the number, and for BLOCKED how long the longest
## wait is. Hovering it breaks the number down by machine and space; what a
## press does is the office's (OfficeBar.counter_pressed).
##
## Its nodes are permanent: data only changes their text, visibility and theme
## variation. The breakdown is kept as handed over and written into words only
## when the pointer asks for a tooltip, with the time it asks at: a wait is
## StateLog.wait_of() of the pane's track, the rule the OVERVIEW's FOR is read by.

## How a machine's MachineLiveness.State reads in the tooltip.
const MACHINE_WORDS: Dictionary[MachineLiveness.State, String] = {
	MachineLiveness.State.LIVE: "LIVE",
	MachineLiveness.State.CONNECTING: "CONNECTING",
	MachineLiveness.State.OFFLINE: "OFFLINE",
}

## What this counter counts: `&"machines"`, `&"blocked"`, `&"done"`,
## `&"working"`, `&"idle"` or `&"panes"`. Set in the scene.
@export var id: StringName
## Herdr's word for it, as the title and the tooltip's empty line say it. Set in the scene.
@export var title := ""

var _rows: Array[OfficeTotals.CounterRow] = []
var _machines: Array[OfficeTotals.MachineRow] = []
## Titles are shown (a wide enough bar); `%Extra` goes with them.
var _titled := true
## The pack gave this counter an icon (PANES has none), and the bar lets it show.
var _has_icon := false
var _iconic := true
var _active := false
var _hot := false
var _alarmed := false


func _ready() -> void:
	var label: Label = %Title
	label.text = title
	var line: Control = %Line
	line.minimum_size_changed.connect(_fit_line)
	_fit_line()


## A Button sizes by its own text and icon, and a counter has neither, while
## Button's own minimum ignores its children: the counter asks for its Line and
## the Line's inset, so the bar's row never squeezes a number into a clipped
## chip. Only the width: the row decides the height.
func _fit_line() -> void:
	var line: Control = %Line
	var wanted := line.get_combined_minimum_size().x + line.offset_left - line.offset_right
	if custom_minimum_size.x != wanted:
		custom_minimum_size = Vector2(wanted, custom_minimum_size.y)


## Wear `art`'s `icon_id` (a UI sprite id), or none for an empty one. The
## sprite stands at its own pivot inside the square, so every icon's picture
## fills the same 16 units whatever pivot the pack gives it.
func dress(art: ArtPack, icon_id: StringName) -> void:
	var slot: Control = %IconSlot
	_has_icon = not icon_id.is_empty()
	slot.visible = _has_icon and _iconic
	if icon_id.is_empty():
		return
	var badge: StatusBadge = slot.get_node("Sprite")
	# show_badge() only: a counter's icon never pulses with the agents'.
	badge.show_badge(art, icon_id)
	badge.position = art.ui_sprite(icon_id).pivot


## The number, and the small text after it (`max 12m`), which is only shown
## while the titles are.
func show_count(count_text: String, extra := "") -> void:
	var value: Label = %Value
	var more: Label = %Extra
	value.text = count_text
	more.text = extra
	more.visible = _titled and not extra.is_empty()


## Titles on a bar wide enough for them, off on a narrow one; `%Extra` follows.
func set_titled(on: bool) -> void:
	_titled = on
	var label: Label = %Title
	var more: Label = %Extra
	label.visible = on
	more.visible = on and not more.text.is_empty()


## The icon, or on a bar too crowded for it only the number (OfficeBar._fit_counters()).
func set_iconic(on: bool) -> void:
	_iconic = on
	var slot: Control = %IconSlot
	slot.visible = _has_icon and on


## The width this counter would need with its title (and `%Extra`) shown or
## not, and its icon shown or not, whatever it shows now: from its labels'
## texts, its icon square and the scene's gaps and inset. What the bar decides
## the counters can afford by (OfficeBar._fit_counters()).
func needed_width(titled: bool, iconic: bool) -> float:
	var line: HBoxContainer = %Line
	var figures_row: HBoxContainer = %Figures
	var label: Label = %Title
	var value: Label = %Value
	var more: Label = %Extra
	var figures := value.get_minimum_size().x
	if titled and not more.text.is_empty():
		figures += figures_row.get_theme_constant("separation") + more.get_minimum_size().x
	var width := maxf(label.get_minimum_size().x, figures) if titled else figures
	if iconic and _has_icon:
		var slot: Control = %IconSlot
		width += slot.get_combined_minimum_size().x + line.get_theme_constant("separation")
	return width + line.offset_left - line.offset_right


func shows_title() -> bool:
	return _titled


func shows_icon() -> bool:
	var slot: Control = %IconSlot
	return slot.visible


## The list shows only what this counter counts (WORKING, IDLE): it reads as pressed.
func set_active(on: bool) -> void:
	_active = on
	_restyle()


## Somebody waits (BLOCKED above zero): the counter the bar makes loudest.
func set_hot(on: bool) -> void:
	_hot = on
	_restyle()


## A machine is not answering (MACHINES short of the fleet): as loud as BLOCKED.
func set_alarmed(on: bool) -> void:
	_alarmed = on
	_restyle()


func alarmed() -> bool:
	return _alarmed


## The breakdown a hover shows, by machine and then by space.
func show_rows(breakdown: Array[OfficeTotals.CounterRow]) -> void:
	_rows = breakdown


## Every machine, for the MACHINES counter's hover.
func show_machines(machines: Array[OfficeTotals.MachineRow]) -> void:
	_machines = machines


func value_text() -> String:
	var value: Label = %Value
	return value.text


func title_text() -> String:
	var label: Label = %Title
	return label.text


func extra_text() -> String:
	var more: Label = %Extra
	return more.text


func rows() -> Array[OfficeTotals.CounterRow]:
	return _rows


## Written only when the pointer rests on the counter, with the time it rests at.
func _get_tooltip(_at: Vector2) -> String:
	return tooltip_at(Time.get_unix_time_from_system(), Time.get_ticks_msec())


## The breakdown as the tooltip says it at `now` (unix seconds, for when a
## machine was last heard from) and `now_msec` (the state log's clock). MACHINES:
## each machine, how it answers and how long ago it was last heard from; every
## other counter: a line per machine and space, BLOCKED and IDLE with each
## pane's time in that state as the OVERVIEW's FOR says it (`3m`, `5s+` for a
## start this office did not see), longest first, `?` for a pane the state log
## has no track of. Nothing to break down: the title and its zero.
func tooltip_at(now: float, now_msec: int) -> String:
	var lines := PackedStringArray()
	for machine in _machines:
		var heard := "never" if machine.heard_since < 0.0 else _ago(now - machine.heard_since)
		var line := "%s · %s · last snapshot %s" % [machine.label, MACHINE_WORDS[machine.state], heard]
		if not machine.error.is_empty():
			line += " · " + machine.error
		lines.append(line)
	for row in _rows:
		var line := "%s · %s  %d" % [row.machine, row.space, row.count]
		if not row.tracks.is_empty():
			line += "  (%s)" % ", ".join(_durations(row.tracks, now_msec))
		lines.append(line)
	if lines.is_empty():
		return "%s %s" % [title, value_text()]
	return "\n".join(lines)


## `45s ago`; OfficeAttention.format_duration() words it.
static func _ago(seconds: float) -> String:
	return OfficeAttention.format_duration(maxf(seconds, 0.0)) + " ago"


## Each track's StateLog.wait_of() at `now_msec`, longest first, a missing
## track last as `?`.
static func _durations(tracks: Array[StateLog.Track], now_msec: int) -> PackedStringArray:
	var waits: Array[StateLog.Wait] = []
	var unknown := 0
	for kept in tracks:
		if kept == null:
			unknown += 1
		else:
			waits.append(StateLog.wait_of(kept, now_msec))
	waits.sort_custom(func(a: StateLog.Wait, b: StateLog.Wait) -> bool: return a.msec > b.msec)
	var words := PackedStringArray()
	for wait in waits:
		words.append(OfficeAttention.wait_text(wait))
	for index in unknown:
		words.append("?")
	return words


## Pressed (a filter) wins over loud. On the dark chip the title is muted
## under a paper number; pressed, both are paper; on the loud blocked chip, ink.
func _restyle() -> void:
	var look := &"Counter"
	if _active:
		look = &"CounterOn"
	elif _hot or _alarmed:
		look = &"CounterHot"
	theme_type_variation = look
	var label: Label = %Title
	var value: Label = %Value
	var more: Label = %Extra
	var loud := look == &"CounterHot"
	label.theme_type_variation = (
		&"CounterTitle" if loud else &"CounterTitlePaper" if _active else &"CounterTitleMuted"
	)
	more.theme_type_variation = label.theme_type_variation
	value.theme_type_variation = &"CounterValue" if loud else &"CounterValuePaper"
