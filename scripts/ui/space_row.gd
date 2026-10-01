class_name OfficeSpaceRow
extends Button
## One zone of the SPACES rail: its number chip as its sign writes it (`3`, or
## `3A` indented for a mezzanine), its name in the sign's words, an icon with a
## count for each state that needs a human, and below them a strip of windows,
## one per pane seated in the zone, lit by its state.
##
## In the narrow rail (set_named(false), the default) the row keeps its chip,
## its blocked badge and count, and the windows directly under the chip; the
## name, the mezzanine's indent and the UNREAD icon and count step out, and the
## row's tooltip says them. Only `visible` and the tooltip change between the two.
##
## A row whose zone is in view wears a slim bar at its left edge
## (set_in_view(), `%InView`); a row a hovered HUD line names wears a 1-unit
## outline (set_pointed()). The two are apart, so a row can wear both.
##
## The row is kept for as long as the zone exists and updated in place, so its
## icons keep pulsing on the shared clock across refreshes. They are StatusBadges
## that pulse for a whole zone rather than one seat, which is what makes
## OfficeAttention step them with the machine's other badges and freeze them
## when it drops. The windows are a fixed set of nodes in the scene; a refresh
## shows, hides and relights them, and the rest past them are counted as `+N`.

## This row was pressed; `key` is the zone key the office gave it.
signal picked(key: String)

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

## The zone this row stands for; empty until show_zone().
var key := ""

var _art: ArtPack
var _machine := ""
## Whether the row says its zone's name (see set_named()).
var _named := false
## What show_zone() last drew, so set_named() can draw it again.
var _zone: ZoneModel
var _live := true
var _tip := ""
## A HUD line under the mouse names this zone (set_pointed()).
var _pointed := false


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(key))


## The chip's text for `zone`: the number its sign says (OfficeZoneSign.number_text():
## `3`, a mezzanine's `3A`). One function writes both, and the sign's tooltip
## and the edge arrows write zones the same way.
static func number_text(zone: ZoneModel) -> String:
	return OfficeZoneSign.number_text(zone)


## Take the pack's icon art. Called again on a theme switch, which re-dresses
## the two sprites and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	var blocked: Control = %BlockedIcon
	var done: Control = %DoneIcon
	_icon(blocked, ArtContract.STATE_BLOCKED)
	_icon(done, ArtContract.STATE_DONE)


## Say the zone's name, its indent and its UNREAD count (`named`), or only its
## number, windows and blocked count, as the rail does. Draws the same zone again.
func set_named(named: bool) -> void:
	if named == _named:
		return
	_named = named
	if _zone != null:
		show_zone(_zone, _machine, _live, _tip)


## This row's zone is in view on the shown map (`on`): the bar at its left edge
## shows. Written only when it changes.
func set_in_view(on: bool) -> void:
	var bar: Control = %InView
	if bar.visible != on:
		bar.visible = on


## Whether the row is marked as in view (set_in_view()).
func in_view() -> bool:
	var bar: Control = %InView
	return bar.visible


## A line of the HUD under the mouse names this zone (`on`): the row wears a
## 1-unit paper edge (SpaceRowPointed) until it does not.
func set_pointed(on: bool) -> void:
	if on == _pointed:
		return
	_pointed = on
	theme_type_variation = _row_look()


## Whether the row is marked as pointed at (set_pointed()).
func pointed() -> bool:
	return _pointed


## Whether the row says its zone's name (set_named()).
func is_named() -> bool:
	return _named


## Draw `zone` of `machine`; `live` is whether that machine is answering, and
## `tip` what the zone's sign tooltip says (repository, checkout, whose
## worktree). A machine that is not answering is dimmed, with no count and no
## lit window: a lost connection is not activity.
func show_zone(zone: ZoneModel, machine: String, live := true, tip := "") -> void:
	key = zone.key
	_machine = machine
	_zone = zone
	_live = live
	_tip = tip
	var number: Label = %Number
	var name_label: Label = %SpaceLabel
	var indent: Control = %Indent
	theme_type_variation = _row_look()
	number.text = number_text(zone)
	var mezzanine := not zone.mezzanine_of.is_empty()
	var pad: Control = %Pad
	# The rail has no room for the indent: its chip (`1A`) says a mezzanine.
	indent.visible = mezzanine and _named
	name_label.visible = _named
	# The rail's windows stand directly under the chip.
	pad.visible = _named
	# The sign's own words: the workspace's label, a mezzanine's checkout.
	name_label.text = OfficeZoneSign.title_text(zone)
	# A zone nobody is seated in steps back.
	name_label.theme_type_variation = &"LabelMuted" if zone.agents == 0 else &""
	var blocked: Control = %BlockedIcon
	var blocked_count: Label = %BlockedCount
	var done: Control = %DoneIcon
	var done_count: Label = %DoneCount
	var middle_gap: Control = %MiddleGap
	var blocked_now := zone.blocked if live else 0
	var done_now := zone.done if live else 0
	_count(blocked, blocked_count, ArtContract.STATE_BLOCKED, blocked_now)
	# The rail leaves the UNREAD count to the tooltip.
	var done_shown := done_now if _named else 0
	_count(done, done_count, ArtContract.STATE_DONE, done_shown)
	# The two icon groups sit a little further apart than an icon and its count.
	middle_gap.visible = blocked_now > 0 and done_shown > 0
	# The sign's words, the counts the narrow rail has no room for, and under
	# them what the sign's own tooltip says.
	var said := OfficeZoneSign.words(zone)
	if not _named:
		if blocked_now > 0:
			said += " · %d blocked" % blocked_now
		if done_now > 0:
			said += " · %d %s" % [done_now, _state_word(ArtContract.STATE_DONE)]
	if not tip.is_empty():
		said += "\n" + tip
	if tooltip_text != said:
		tooltip_text = said
	_show_windows(zone, live)
	modulate = Color.WHITE if live or _art == null else _art.stale_tint


## The badge of one of this row's icons, for the tests that follow the pulse.
func icon(state: StringName) -> StatusBadge:
	var holder: Control = %BlockedIcon if state == ArtContract.STATE_BLOCKED else %DoneIcon
	return holder.get_node("Sprite")


## One window per pane seated in the zone, in the order the zone seats them,
## as many as the scene holds; the rest are counted after the last one. A
## window's look and tooltip are only written when they change.
func _show_windows(zone: ZoneModel, live: bool) -> void:
	var windows: Control = %Windows
	var facade: Control = %Facade
	var more: Label = %More
	var cap := windows.get_child_count()
	var shown := 0
	for room in zone.rooms:
		for pane in room.panes:
			if shown < cap:
				var window: Control = windows.get_child(shown)
				var look := window_look(pane, live)
				if window.theme_type_variation != look:
					window.theme_type_variation = look
				var tip := _window_tip(pane, live)
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
func _window_tip(pane: PaneModel, live: bool) -> String:
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
func _count(holder: Control, label: Label, state: StringName, count: int) -> void:
	var badge: StatusBadge = holder.get_node("Sprite")
	holder.visible = count > 0
	label.visible = count > 0
	label.text = str(count)
	if count > 0:
		# A zone, not a seat: the pulse asks the machine, never a pane.
		badge.pulse_for(_machine, "", state)
	else:
		badge.stop_pulsing()


## The row's look: pointed at, or plain.
func _row_look() -> StringName:
	return &"SpaceRowPointed" if _pointed else &"SpaceRow"
