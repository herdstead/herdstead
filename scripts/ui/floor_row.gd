class_name OfficeFloorRow
extends Button
## One floor of the FLOORS minimap: its number chip (`3F`, or `3A` indented for a mezzanine), its
## name, an icon with a count for each state that needs a human, and below them
## a strip of windows, one per pane seated on the floor, lit by its state.
##
## In the narrow rail (set_named(false), the default) the row keeps its chip,
## its blocked badge and count, and the windows directly under the chip; the
## name, the mezzanine's indent and the UNREAD icon and count step out, and the
## row's tooltip says them. Only `visible` and the tooltip change between the two.
##
## The row is kept for as long as the floor exists and updated in place, so its
## icons keep pulsing on the shared clock across refreshes. They are StatusBadges
## that pulse for a whole floor rather than one seat, which is what makes
## OfficeAttention step them with the machine's other badges and freeze them
## when it drops. The windows are a fixed set of nodes in the scene; a refresh
## shows, hides and relights them, and the rest past them are counted as `+N`.

## This row was pressed; `key` is the floor key the office gave it.
signal floor_picked(key: String)

## Palette-driven looks the row switches between; everything else is the Theme.
const CURRENT := {
	true:
	{"row": &"FloorRowCurrent", "chip": &"RowChipCurrent", "number": &"RowNumberCurrent", "more": &"WindowMoreCurrent"},
	false: {"row": &"FloorRow", "chip": &"RowChip", "number": &"RowNumber", "more": &"WindowMore"},
}
## herdr's agent state -> the window's look (HudTheme.SECTION_PANELS). A state
## the office does not know is lit as unknown; a shell, a pane still starting
## its agent and every pane of a machine that is not answering are handled
## before this table (see window_look()).
const WINDOW_LOOKS: Dictionary[String, StringName] = {
	"working": &"WindowWorking",
	"blocked": &"WindowBlocked",
	"done": &"WindowDone",
	"idle": &"WindowIdle",
}

## The floor this row stands for; empty until show_floor().
var key := ""

var _art: ArtPack
var _machine := ""
## Whether the row says its floor's name (see set_named()).
var _named := false
## What show_floor() last drew, so set_named() can draw it again.
var _floor: ZoneModel
var _current := false
var _live := true
## A HUD line under the mouse names this floor (set_pointed()).
var _pointed := false


func _ready() -> void:
	pressed.connect(func() -> void: floor_picked.emit(key))


## The chip's text for `floor_model`: a mezzanine's own level label (`3A`),
## and every other zone's number with an F (`3F`). The zone sign's tooltip and
## the signposts write zones the same way.
static func number_text(floor_model: ZoneModel) -> String:
	if not floor_model.mezzanine_of.is_empty() and not floor_model.level_label.is_empty():
		return floor_model.level_label
	return "%dF" % floor_model.number


## Take the pack's icon art. Called again on a theme switch, which re-dresses
## the two sprites and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	var blocked: Control = %BlockedIcon
	var done: Control = %DoneIcon
	_icon(blocked, ArtContract.STATE_BLOCKED)
	_icon(done, ArtContract.STATE_DONE)


## Say the floor's name, its indent and its UNREAD count (`named`), or only its
## number, windows and blocked count, as the rail does. Draws the same floor again.
func set_named(named: bool) -> void:
	if named == _named:
		return
	_named = named
	if _floor != null:
		show_floor(_floor, _machine, _current, _live)


## A line of the HUD under the mouse names this floor (`on`): the row wears a
## 1-unit ink edge (FloorRowPointed) until it does not. The current floor's row
## keeps its own look.
func set_pointed(on: bool) -> void:
	if on == _pointed:
		return
	_pointed = on
	theme_type_variation = _row_look()


## Whether the row is marked as pointed at (set_pointed()).
func pointed() -> bool:
	return _pointed


## Whether the row says its floor's name (set_named()).
func is_named() -> bool:
	return _named


## Draw `floor_model` of `machine`; `current` is the floor the office shows, and
## `live` is whether that machine is answering. A building that is not is
## dimmed, with no count and no lit window: a lost connection is not activity.
func show_floor(floor_model: ZoneModel, machine: String, current: bool, live := true) -> void:
	key = floor_model.key
	_machine = machine
	_floor = floor_model
	_current = current
	_live = live
	var look: Dictionary = CURRENT[current]
	var chip: Panel = %Chip
	var number: Label = %Number
	var name_label: Label = %FloorLabel
	var indent: Control = %Indent
	theme_type_variation = _row_look()
	chip.theme_type_variation = look.chip
	number.theme_type_variation = look.number
	number.text = number_text(floor_model)
	var mezzanine := not floor_model.mezzanine_of.is_empty()
	var pad: Control = %Pad
	# The rail has no room for the indent: its chip (`1A`) says a mezzanine.
	indent.visible = mezzanine and _named
	name_label.visible = _named
	# The rail's windows stand directly under the chip.
	pad.visible = _named
	# A mezzanine is a checkout of its source floor's repository: its checkout
	# says which one, where the workspace's own label often repeats the source's.
	name_label.text = floor_model.worktree if mezzanine and not floor_model.worktree.is_empty() else floor_model.label
	var tip := "%s  %s" % [number.text, floor_model.label]
	if mezzanine and not floor_model.worktree.is_empty():
		tip += " · " + floor_model.worktree
	# A floor nobody is seated on steps back; the shown one is always readable.
	name_label.theme_type_variation = (&"LabelPaper" if current else &"LabelMuted" if floor_model.agents == 0 else &"")
	var blocked: Control = %BlockedIcon
	var blocked_count: Label = %BlockedCount
	var done: Control = %DoneIcon
	var done_count: Label = %DoneCount
	var middle_gap: Control = %MiddleGap
	var blocked_now := floor_model.blocked if live else 0
	var done_now := floor_model.done if live else 0
	_count(blocked, blocked_count, ArtContract.STATE_BLOCKED, blocked_now, current)
	# The rail leaves the UNREAD count to the tooltip.
	var done_shown := done_now if _named else 0
	_count(done, done_count, ArtContract.STATE_DONE, done_shown, current)
	# The two icon groups sit a little further apart than an icon and its count.
	middle_gap.visible = blocked_now > 0 and done_shown > 0
	if not _named:
		if blocked_now > 0:
			tip += " · %d blocked" % blocked_now
		if done_now > 0:
			tip += " · %d %s" % [done_now, _state_word(ArtContract.STATE_DONE)]
	tooltip_text = tip
	_show_windows(floor_model, current, live)
	modulate = Color.WHITE if live or _art == null else _art.stale_tint


## The badge of one of this row's icons, for the tests that follow the pulse.
func icon(state: StringName) -> StatusBadge:
	var holder: Control = %BlockedIcon if state == ArtContract.STATE_BLOCKED else %DoneIcon
	return holder.get_node("Sprite")


## One window per pane seated on the floor, in the order the floor seats them,
## as many as the scene holds; the rest are counted after the last one. A
## window's look and tooltip are only written when they change.
func _show_windows(floor_model: ZoneModel, current: bool, live: bool) -> void:
	var windows: Control = %Windows
	var facade: Control = %Facade
	var more: Label = %More
	var cap := windows.get_child_count()
	var shown := 0
	for room in floor_model.rooms:
		for pane in room.panes:
			if shown < cap:
				var window: Control = windows.get_child(shown)
				var look := window_look(pane, live)
				if window.theme_type_variation != look:
					window.theme_type_variation = look
				var tip := _tip(pane, live)
				if window.tooltip_text != tip:
					window.tooltip_text = tip
				window.visible = true
			shown += 1
	for index in range(mini(shown, cap), cap):
		var unused: Control = windows.get_child(index)
		unused.visible = false
	facade.visible = shown > 0
	more.visible = shown > cap
	more.text = "+%d" % (shown - cap) if shown > cap else ""
	var more_look: StringName = CURRENT[current].more
	if more.theme_type_variation != more_look:
		more.theme_type_variation = more_look


## How a pane's window is lit. Dark for a shell and for every pane of a
## machine that is not answering (`live` false); a pane still starting its
## agent is lit plainly, as an idle one is, unless it already asks
## (PaneModel.launching()); otherwise its agent state's own colour. The one
## colour scale: the strategic view's squares (StrategicModel) and the lens's
## washes (OfficeLens.tone_for()) ask this too.
static func window_look(pane: PaneModel, live: bool) -> StringName:
	if not live or pane.provider.is_empty():
		return &"WindowDark"
	if pane.launching():
		return &"WindowIdle"
	return WINDOW_LOOKS.get(pane.state, &"WindowUnknown")


## The window's tooltip: the agent and its state in the pack's words, `shell`
## for a pane without one, and OFFLINE for a machine that is not answering.
func _tip(pane: PaneModel, live: bool) -> String:
	if pane.provider.is_empty():
		return "shell"
	if not live:
		return pane.provider + " · OFFLINE"
	if pane.launching():
		return pane.provider + " · STARTING"
	var drawn: ArtState = null if _art == null else _art.state(StringName(pane.state))
	return pane.provider + " · " + (pane.state.to_upper() if drawn == null else drawn.label)


## The pack's word for `state` (`UNREAD` for done), or herdr's in capitals
## before the row is dressed.
func _state_word(state: StringName) -> String:
	var drawn: ArtState = null if _art == null else _art.state(state)
	return str(state).to_upper() if drawn == null else drawn.label


## Take the pack's art for one icon. A theme switch is new textures on the same
## badge: what it pulses for is _count()'s to say, and survives the switch.
func _icon(holder: Control, state: StringName) -> void:
	var badge: StatusBadge = holder.get_node("Sprite")
	badge.show_badge(_art, _art.state(state).badge)


## An icon and its count only exist while the count does. A hidden icon stops
## pulsing too, so a frozen row costs the pulse nothing.
func _count(holder: Control, label: Label, state: StringName, count: int, current: bool) -> void:
	var badge: StatusBadge = holder.get_node("Sprite")
	holder.visible = count > 0
	label.visible = count > 0
	label.text = str(count)
	label.theme_type_variation = &"LabelPaper" if current else &""
	if count > 0:
		# A floor, not a seat: the pulse asks the machine, never a pane.
		badge.pulse_for(_machine, "", state)
	else:
		badge.stop_pulsing()


## The row's look: the current floor's, pointed at, or plain.
func _row_look() -> StringName:
	if _pointed and not _current:
		return &"FloorRowPointed"
	var look: Dictionary = CURRENT[_current]
	return look.row
