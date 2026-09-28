class_name OverviewLine
extends Button
## One pane's row in the OVERVIEW (scenes/ui/overview_line.tscn): its agent
## with the pack's badge for its state, SPACE / TAB, STATE, FOR, BLOCKED,
## TIMES, and its timeline. A click picks the pane. The row is pooled by pane
## key (OfficeOverview): the office writes it once a second, and a label is
## written only when its text changes, so a second in which nothing but the
## clock moved relays out only the FOR and BLOCKED labels that did.

## Pressed: the office picks pane `key`, as a click on its desk does.
signal picked(key: String)

## The OVERVIEW's words for a `+` (tooltip), shared with the column heads.
const AT_LEAST := "+ = at least: this began before this office was watching"
## Label variations by look: ink on the panel, paper on the selected row's ink,
## muted on an offline row; the agent's name the same, clear of its badge.
const TONES: Dictionary[StringName, StringName] = {
	&"OverviewRow": &"",
	&"OverviewRowCurrent": &"LabelPaper",
	&"OverviewRowDim": &"LabelMuted",
}
const AGENT_TONES: Dictionary[StringName, StringName] = {
	&"OverviewRow": &"OverviewAgent",
	&"OverviewRowCurrent": &"OverviewAgentPaper",
	&"OverviewRowDim": &"OverviewAgentMuted",
}

## HerdrFleet.pane_key of the pane shown.
var key := ""

var _art: ArtPack
var _mark := &""
var _tone := &"-"


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(key))


## Take the pack's badge art. A theme switch calls this again and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	_draw_badge(_mark)


## BLOCKED and TIMES shown (the full table) or left out (a narrow screen).
func set_compact(on: bool) -> void:
	for unique: String in ["%Blocked", "%Times"]:
		var label: Label = get_node(unique)
		label.visible = not on


## Draw `row` over the span `opened_msec` .. `now_msec`.
func show_row(row: OverviewModel.Row, opened_msec: int, now_msec: int) -> void:
	key = row.key
	var look := &"OverviewRow"
	if row.selected:
		look = &"OverviewRowCurrent"
	elif row.offline:
		look = &"OverviewRowDim"
	if theme_type_variation != look:
		theme_type_variation = look
	var tone: StringName = TONES[look]
	if tone != _tone:
		_tone = tone
		for unique: String in ["%Space", "%State", "%For", "%Blocked", "%Times"]:
			var label: Label = get_node(unique)
			label.theme_type_variation = tone
		var agent: Label = %AgentName
		agent.theme_type_variation = AGENT_TONES[look]
	_say("%AgentName", agent_text(row))
	_say("%Space", row.place())
	_say("%State", state_text(row))
	_say("%For", for_text(row))
	_say("%Blocked", duration_text(row.blocked_msec, row.blocked_plus))
	_say("%Times", str(row.times))
	var plus := row.for_plus or row.blocked_plus
	var hint := AT_LEAST if plus else ""
	if tooltip_text != hint:
		tooltip_text = hint
	var mark := _mark_of(row)
	if mark != _mark:
		_draw_badge(mark)
	var timeline: OverviewTimeline = %Timeline
	timeline.show_track(row.track, opened_msec, now_msec)


## Who the row is: the provider in capitals; the name herdr gave an agent it
## has not recognised yet (`CLAUDE-1`, the seconds after a start), as NEWS
## writes it; `shell` for a pane without either.
static func agent_text(row: OverviewModel.Row) -> String:
	if not row.agent.is_empty():
		return row.agent.to_upper()
	return "shell" if row.agent_name.is_empty() else row.agent_name.to_upper()


## What the STATE column says: herdr's word in capitals, `offline` for a
## machine that is away, `starting` in capitals while herdr launches the
## pane's agent, nothing for a shell.
static func state_text(row: OverviewModel.Row) -> String:
	if row.offline:
		return "offline"
	if row.starting:
		return "STARTING"
	if row.agent.is_empty():
		return ""
	return row.state.to_upper()


## FOR: `-` while offline (no live state to time), else the time with `+` when
## the state began before the office watched.
static func for_text(row: OverviewModel.Row) -> String:
	if row.offline:
		return "-"
	return duration_text(row.for_msec, row.for_plus)


## `12m`, `3m+`: OfficeAttention.wait_text(), `+` for "at least".
static func duration_text(msec: int, plus: bool) -> String:
	var wait := StateLog.Wait.new()
	wait.msec = msec
	wait.plus = plus
	return OfficeAttention.wait_text(wait)


func _say(unique: String, said: String) -> void:
	var label: Label = get_node(unique)
	if label.text != said:
		label.text = said


## The pack image the row's badge wears: a state's name, or a UI overlay's id
## (starting, offline), as the agent list's row wears it; empty for a shell.
func badge_mark() -> StringName:
	return _mark


## The badge the row wears: the offline mark; the starting mark while herdr
## launches the pane's agent and it has not asked anything (PaneModel.launching(),
## as the agent list and the desk show it; a blocked one wears blocked's); its
## state's; nothing for a shell.
static func _mark_of(row: OverviewModel.Row) -> StringName:
	if row.offline:
		return ArtContract.UI_OFFLINE
	if row.starting:
		return ArtContract.UI_STARTING
	if row.agent.is_empty():
		return &""
	if row.state in StateLog.STATES:
		return StringName(row.state)
	return ArtContract.STATE_UNKNOWN


func _draw_badge(mark: StringName) -> void:
	_mark = mark
	if _art == null:
		return
	var badge: StatusBadge = %Badge
	if mark.is_empty():
		badge.clear(_art)
		return
	# A state names its badge in the pack; the offline overlay is a UI image.
	var drawn := _art.state(mark)
	var id: StringName = drawn.badge if drawn != null else mark
	if _art.ui_sprite(id) == null:
		id = _art.state(ArtContract.STATE_UNKNOWN).badge
	badge.show_badge(_art, id)
	badge.visible = true
