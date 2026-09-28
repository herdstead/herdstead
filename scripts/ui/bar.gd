class_name OfficeBar
extends Control
## The top bar: the wordmark on the left, six counters in herdr's words
## (MACHINES, BLOCKED, DONE, WORKING, IDLE, PANES) in the middle, and two
## right-aligned lines, the pack's name and how the office is running, as wide
## as the longest status needs at every window size (the scene's offsets).
## Where the counters do not all fit, they give up their titles first and then
## their icons: the numbers always show (_fit_counters()). At the right end of
## their row, against the lines, the chime switch (`CHIME ON` / `CHIME OFF`)
## shows where titles are allowed and takes its room from the counters; on a
## bar too narrow for titles it steps aside, as the titles do.
##
## Its nodes are permanent. Setting a Label's text to what it already holds is a
## no-op in Godot, so the office may call show_bar() and show_totals() on every
## refresh. A counter pressed is the office's to act on (counter_pressed).

## A counter was pressed; `id` is what it counts (OfficeCounter.id).
signal counter_pressed(id: StringName)
## The chime switch was clicked: `on` is what it asks for. The office decides,
## and says what it decided with show_chime().
signal chime_toggled(on: bool)

## What each fit tries, in order: titles and icons, icons alone, the numbers alone.
const LOOKS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(0, 1), Vector2i(0, 0)]
## What the theme line says while the lens is held (show_lens()).
const LENS_LINE := "LENS · hold L"
## What it says while the strategic view is open (show_strategic()).
const STRATEGIC_LINE := "STRATEGIC · S"
## What the chime switch says, on and off (show_chime()).
const CHIME_ON := "CHIME ON"
const CHIME_OFF := "CHIME OFF"

## The screen is wide enough for titles (OfficeHud.fit()); they still go when
## the counters would not fit with them.
var _titles_allowed := true
## The pack's name, for the theme line when the lens is let go and the
## strategic view closed.
var _theme_name := ""
var _lensed := false
var _strategic := false
## What the chime switch says (show_chime()).
var _chime_on := false


func _ready() -> void:
	for each in counters():
		var id := each.id
		each.pressed.connect(func() -> void: counter_pressed.emit(id))
	var switch: Button = %Chime
	switch.pressed.connect(func() -> void: chime_toggled.emit(not _chime_on))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_counters()


## The bar takes the mouse like the two panels do; see HdPanel._gui_input.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


## Every counter its icon from `art`: MACHINES the connected mark, a state's
## counter the pack's badge for that state. PANES has none: no picture of a
## pane is in the pack yet.
func dress(art: ArtPack) -> void:
	counter(&"machines").dress(art, ArtContract.UI_CONNECTED)
	for state: StringName in [
		ArtContract.STATE_BLOCKED, ArtContract.STATE_DONE, ArtContract.STATE_WORKING, ArtContract.STATE_IDLE
	]:
		counter(state).dress(art, art.state(state).badge)
	counter(&"panes").dress(art, &"")


## `theme_name` is the pack's name (plus `[T]` when there is more than one),
## `status` how the office runs (`LIVE / READ ONLY`, `1 OFFLINE / OPERATOR`,
## `OFFLINE / RECONNECTING`). `is_alarmed` is a machine being down: the line
## turns the blocked colour, and so does the MACHINES counter (show_totals()
## says the same from the same count).
func show_bar(theme_name: String, status: String, is_alarmed: bool) -> void:
	var status_label: Label = %StatusLine
	_theme_name = theme_name
	_say_theme()
	status_label.text = status
	status_label.theme_type_variation = &"LabelBlocked" if is_alarmed else &"LabelCream"


## The lens is held (`held`): the theme line says so, `LENS · hold L`; let go,
## the pack's name again. Only the text changes.
func show_lens(held: bool) -> void:
	var theme_label: Label = %ThemeLine
	if held and not _lensed and not _strategic:
		_theme_name = theme_label.text
	_lensed = held
	_say_theme()


## The strategic view is open (`on`): the theme line says so, `STRATEGIC · S`,
## over the lens's line (the two are never on together, but a lens let go in
## the same frame must not take the line back); closed, the pack's name again.
func show_strategic(on: bool) -> void:
	var theme_label: Label = %ThemeLine
	if on and not _strategic and not _lensed:
		_theme_name = theme_label.text
	_strategic = on
	_say_theme()


## The theme line: the strategic view's, the lens's, or the pack's name.
func _say_theme() -> void:
	var theme_label: Label = %ThemeLine
	theme_label.text = STRATEGIC_LINE if _strategic else LENS_LINE if _lensed else _theme_name


## The six numbers and their breakdowns, from the live machines only.
func show_totals(totals: OfficeTotals) -> void:
	var machines := counter(&"machines")
	machines.show_count("%d/%d" % [totals.machines_live, totals.machines_total])
	machines.set_alarmed(totals.machines_live < totals.machines_total)
	machines.show_machines(totals.machine_rows)
	var blocked := counter(&"blocked")
	blocked.show_count(str(totals.blocked), blocked.extra_text())
	blocked.set_hot(totals.blocked > 0)
	for id: StringName in [&"blocked", &"done", &"working", &"idle"]:
		counter(id).show_rows(totals.rows_of(id))
	counter(&"done").show_count(str(totals.done))
	counter(&"working").show_count(str(totals.working))
	counter(&"idle").show_count(str(totals.idle))
	counter(&"panes").show_count(str(totals.panes))
	_fit_counters()


## The longest wait among the blocked, as OfficeAttention words it (`12m`);
## empty for none. It ticks on attention's beat, not on a refresh.
func show_longest_wait(text: String) -> void:
	var blocked := counter(&"blocked")
	blocked.show_count(blocked.value_text(), "" if text.is_empty() else "max " + text)
	_fit_counters()


## The counter whose filter the agent list shows now reads pressed; `&""` for
## none. PANES is not a filter: it reads pressed while the overview is open
## (set_overview()), whatever the filter.
func set_filter(id: StringName) -> void:
	for each in counters():
		if each.id != &"panes":
			each.set_active(each.id == id)


## PANES reads pressed while the overview is open.
func set_overview(on: bool) -> void:
	counter(&"panes").set_active(on)


## Titles on a screen wide enough for them (OfficeHud.fit()); whether they
## show is still up to what fits (_fit_counters()). The chime switch shows on
## the same screens only.
func set_titled(on: bool) -> void:
	_titles_allowed = on
	var switch: Button = %Chime
	switch.visible = on
	_fit_counters()


## The chime is on (`on`) or off: the switch says so, in the lines' cream
## while it is on (BarSwitchOn) and their muted colour while it is off. This is
## the office telling the switch; a click only asks (chime_toggled), so a
## switch nobody answers, the showroom's, stays as it was.
func show_chime(on: bool) -> void:
	var switch: Button = %Chime
	_chime_on = on
	switch.text = CHIME_ON if on else CHIME_OFF
	switch.theme_type_variation = &"BarSwitchOn" if on else &"BarSwitch"
	_fit_counters()


## Whether the chime switch says the chime is on.
func chime_shown() -> bool:
	return _chime_on


## The richest look every counter fits in at once, from what each would need
## (OfficeCounter.needed_width()) and the room the scene leaves the row:
## titles and icons, else icons and numbers, else the numbers alone. The same
## for all six, so the row reads as one. The chime switch, when it shows,
## stands in the same row and is paid for first.
func _fit_counters() -> void:
	if not is_node_ready():
		return
	var row: HBoxContainer = %Counters
	var each := counters()
	var room := size.x * (row.anchor_right - row.anchor_left) + row.offset_right - row.offset_left
	var gaps := row.get_theme_constant("separation") * (each.size() - 1)
	var switch: Button = %Chime
	if switch.visible:
		gaps += row.get_theme_constant("separation") + ceili(switch.get_combined_minimum_size().x)
	var chosen: Vector2i = LOOKS[LOOKS.size() - 1]
	for look in LOOKS:
		if look.x == 1 and not _titles_allowed:
			continue
		var needed := float(gaps)
		for one in each:
			needed += one.needed_width(look.x == 1, look.y == 1)
		if needed <= room:
			chosen = look
			break
	for one in each:
		one.set_titled(chosen.x == 1)
		one.set_iconic(chosen.y == 1)


func counter(id: StringName) -> OfficeCounter:
	for each in counters():
		if each.id == id:
			return each
	return null


## The six, left to right.
func counters() -> Array[OfficeCounter]:
	var found: Array[OfficeCounter] = []
	var row: Control = %Counters
	for child in row.get_children():
		if child is OfficeCounter:
			found.append(child)
	return found


## The pack's name, as the first right-hand line shows it.
func theme_line() -> String:
	var theme_label: Label = %ThemeLine
	return theme_label.text


## How the office runs, as the second right-hand line shows it.
func status_line() -> String:
	var status_label: Label = %StatusLine
	return status_label.text


## Whether a machine is down: the MACHINES counter and the status line both say it.
func alarmed() -> bool:
	return counter(&"machines").alarmed()
