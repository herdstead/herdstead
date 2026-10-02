class_name OfficeStrategicPlan
extends Control
## The strategic view's schematic (`%Plan` in scenes/ui/strategic.tscn): the
## shown machine's map as a section per zone, captioned with the words on the
## zone's sign (`3 INFRA`); under a caption every pod of that zone as a box with
## its tab's name above it, and one square per seated pane in its SPACES
## window's colour, a blocked one writing its wait where the square has room.
## A caption is plain text (paper, the sign's face; never the zone's accent,
## which is structure in the world) with a rule on to its column's edge; a
## section that runs on into another column repeats it with `…`; hovering one
## says what the sign's tooltip says. Captions are not clickable. A caption
## never changes the cell its desks get: one longer than its column has width
## for is cut with an ellipsis, and its tooltip leads with its whole words.
## The selected pane has four corners
## round its square (the world selection's shape, in the blocked colour), and
## a pane a HUD line points at has the pointer's ink / paper dash round it,
## both on the cell's edge, a unit of ink clear of the square.
## herdr's focus is not drawn. One CanvasItem, drawn in _draw() from the theme's
## `Strategic` type (HudTheme._strategic()); no texture, no node per seat.
##
## Where everything stands is StrategicLayout's, for the room the view hands
## in and the ladder of cells set in the scene (`cells`); the layout is made
## again, and its text shaped again, only when the map's shape, words or the
## room change. Which zone each caption stands for is read from every model: a
## map with the same shape and words (another machine's, or a workspace
## replaced by one with its number and label) has its own sections. It is drawn
## again only when what it shows changes: the model's signature, the waits it
## writes, the pointer or the layout.
##
## A left press and release on the same square, CLICK_SLOP apart at most, say
## picked(); a drag, or a click between squares, says nothing. The wheel is
## left to the scroll around it. The tooltip over a square names the agent, its
## state in the pack's words, its wait and where it sits.

## A square was clicked: the office picks pane `key`.
signal picked(key: String)

## What a caption repeated at the top of a further column ends with.
const CONTINUED := " …"

## The cell sizes to try, largest first (units). Set in the scene.
@export var cells := PackedInt32Array()

## How many times it was drawn, for tests.
var draws := 0

var _art: ArtPack
var _model: StrategicModel
var _layout: StrategicLayout
## What the layout was made for: the tables' capacities and the room.
var _laid_for := ""
## What the last queued drawing showed (see _show()).
var _shown := ""
## Pane key -> its square, in this control's units; tab key -> its box.
var _squares: Dictionary[String, Rect2] = {}
var _boxes: Dictionary[String, Rect2] = {}
## Seat keys in draw order: table by table, far seats then near, left to right.
var _order := PackedStringArray()
## Pane key -> the wait written in its square.
var _waits: Dictionary[String, String] = {}
## Tab key -> its caption, shaped once per layout.
var _captions: Dictionary[String, TextLine] = {}
## Every section caption of the layout, in reading order (StrategicLayout.headings):
## what it says, its shaped line and its band in this control's units, and
## whether the band is too narrow for the words (the line is cut).
var _heading_words := PackedStringArray()
var _heading_lines: Array[TextLine] = []
var _heading_rects: Array[Rect2] = []
var _heading_cut: Array[bool] = []
## The zone each of those captions names, in the model shown now (_bind_headings()).
var _heading_keys := PackedStringArray()
var _pointed := ""
## The square a left press came down on, and where; empty while none is down.
var _pressed := ""
var _press_at := Vector2.ZERO
## The room and bar the last model was laid out for, for a theme switch.
var _last_room := Vector2.ZERO
var _last_bar := 0.0


## The pack, for the states' words in the tooltip. A theme switch calls it again.
func dress(art: ArtPack) -> void:
	_art = art
	_laid_for = ""
	if _model != null:
		_relayout(_last_room, _last_bar)
		_show()


## Draw `model` in a room `room` units big; `bar` is how wide the scroll's bar
## is when it shows, which a schematic too tall for the room must leave free.
func show_model(model: StrategicModel, room: Vector2, bar: float) -> void:
	_model = model
	_relayout(room, bar)
	_show()


## Dash pane `key`'s square (a HUD line about it is under the mouse); empty, or
## a pane with no square here, for none.
func point(key: String) -> void:
	_pointed = key if _squares.has(key) else ""
	_show()


## The measures StrategicLayout.fit() is given: the scene's ladder, the theme's rest.
func rules() -> StrategicLayout.Rules:
	var made := StrategicLayout.Rules.new()
	made.cells = cells
	made.pad = get_theme_constant(&"pad", &"Strategic")
	made.gap = get_theme_constant(&"gap", &"Strategic")
	made.caption = get_theme_constant(&"caption_height", &"Strategic")
	made.divider = get_theme_constant(&"divider", &"Strategic")
	made.ring = get_theme_constant(&"ring", &"Strategic")
	made.section = get_theme_constant(&"section_caption", &"Strategic")
	return made


## The cell every seat has now, and the newspaper columns (0 before a layout).
func cell() -> int:
	return 0 if _layout == null else _layout.cell


func columns() -> int:
	return 0 if _layout == null else _layout.columns


## Whether the schematic is taller than its room (it scrolls).
func scrolls() -> bool:
	return _layout != null and _layout.scrolls


## The smallest cell that writes a wait in its square (the theme's `wait_from`).
func wait_from() -> int:
	return get_theme_constant(&"wait_from", &"Strategic")


## Pane `key`'s square in this control's units; empty for none.
func seat_rect(key: String) -> Rect2:
	return _squares.get(key, Rect2())


## Tab `key`'s box in this control's units; empty for none.
func table_rect(key: String) -> Rect2:
	return _boxes.get(key, Rect2())


## The zones that have a section, in the order drawn.
func section_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	if _model != null:
		for section in _model.sections:
			keys.append(section.key)
	return keys


## Every caption band of zone `key`'s section, in reading order, in this
## control's units: one, and one more per further column it runs on into.
func section_rects(key: String) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for index in _heading_keys.size():
		if _heading_keys[index] == key:
			found.append(_heading_rects[index])
	return found


## What every caption says, in reading order: `3 INFRA`, and `3 INFRA …` where
## a section runs on into another column.
func captions_drawn() -> PackedStringArray:
	return _heading_words


## Every square's pane, in draw order.
func seat_keys() -> PackedStringArray:
	return _order


## Pane key -> the look its square wears (HudTheme.SECTION_PANELS key).
func looks() -> Dictionary[String, StringName]:
	var found: Dictionary[String, StringName] = {}
	if _model != null:
		for table in _model.tables:
			for seat in table.seats:
				found[seat.key] = seat.look
	return found


## The colour pane `key`'s square is filled with.
func color_of(key: String) -> Color:
	var seat := _model.seat_of(key) if _model != null else null
	return Color.TRANSPARENT if seat == null else get_theme_color(seat.look, &"Strategic")


## The wait written in pane `key`'s square; empty where none is.
func wait_drawn(key: String) -> String:
	return _waits.get(key, "")


## The pane the corners go round, and the one dashed; empty for none.
func picked_key() -> String:
	if _model != null:
		for table in _model.tables:
			for seat in table.seats:
				if seat.picked:
					return seat.key
	return ""


func pointed_key() -> String:
	return _pointed


## What the tooltip says at `at` (this control's units): over a square, the
## agent (`shell` for none), its state in the pack's words (`OFFLINE` on a
## machine that is not answering, `STARTING` while herdr launches it) and its
## wait, then where it sits; over a section's caption, what its zone's sign
## tooltip says (repository, checkout, whose worktree), under the caption's
## whole words when it is cut; nothing elsewhere.
func tooltip_at(at: Vector2) -> String:
	var seat := _model.seat_of(_seat_at(at)) if _model != null else null
	if seat == null:
		for index in _heading_rects.size():
			if _heading_rects[index].has_point(at):
				var section := _model.section_of(_heading_keys[index])
				if section == null:
					return ""
				return section.caption + "\n" + section.tip if _heading_cut[index] else section.tip
		return ""
	var words := PackedStringArray()
	if seat.provider.is_empty():
		words.append("shell")
	else:
		words.append(seat.provider.to_upper())
		if _model.stale:
			words.append("OFFLINE")
		elif seat.starting:
			words.append("STARTING")
		else:
			var drawn: ArtState = null if _art == null else _art.state(seat.state_word_key)
			words.append(str(seat.state_word_key).to_upper() if drawn == null else drawn.label)
	if not seat.wait.is_empty():
		words.append(seat.wait)
	return " · ".join(words) + "\n" + seat.place


func _get_tooltip(at_position: Vector2) -> String:
	return tooltip_at(at_position)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if button.pressed:
		_pressed = _seat_at(button.position)
		_press_at = button.position
		return
	var from := _pressed
	_pressed = ""
	if from.is_empty() or _seat_at(button.position) != from:
		return
	if (button.position - _press_at).length() < OfficeCamera.CLICK_SLOP:
		picked.emit(from)


func _seat_at(at: Vector2) -> String:
	for key in _order:
		if _squares[key].has_point(at):
			return key
	return ""


## The layout for this model's tables in `room`, made again only when either
## changed; the captions' zones are the model's own every time.
func _relayout(room: Vector2, bar: float) -> void:
	_last_room = room
	_last_bar = bar
	var rows := _model.row_capacities()
	var sections := _model.section_rows()
	var labels := PackedStringArray()
	for table in _model.tables:
		labels.append(table.label)
	var named := PackedStringArray()
	for section in _model.sections:
		named.append(section.caption)
	var laid_for := JSON.stringify([var_to_str(rows), labels, sections, named, room, bar, cells])
	if laid_for != _laid_for or _layout == null:
		_laid_for = laid_for
		var made := rules()
		var wide := _caption_widths()
		_layout = StrategicLayout.fit(rows, room, made, sections, wide)
		if _layout.scrolls:
			_layout = StrategicLayout.fit(rows, room - Vector2(bar, 0), made, sections, wide)
		_captions.clear()
		_shape_headings()
	_bind_headings()
	custom_minimum_size = _layout.size
	_squares.clear()
	_boxes.clear()
	_order = PackedStringArray()
	var in_row: Dictionary[int, int] = {}
	var caption_font := get_theme_font(&"caption_font", &"Strategic")
	var caption_size := get_theme_constant(&"caption_size", &"Strategic")
	for table in _model.tables:
		var index: int = in_row.get(table.row, 0)
		in_row[table.row] = index + 1
		var framed := _layout.box(table.row, index)
		_boxes[table.key] = framed
		if not _captions.has(table.key):
			var line := TextLine.new()
			line.add_string(table.label, caption_font, caption_size)
			line.width = framed.size.x
			line.alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_captions[table.key] = line
		for seat in table.seats:
			_squares[seat.key] = _layout.seat_rect(table.row, index, seat.column, seat.side)
			_order.append(seat.key)
	if not _squares.has(_pointed):
		_pointed = ""


## How wide each section's caption is drawn at its widest (repeated, with
## CONTINUED): StrategicLayout widens a caption's column to it as far as the
## desks leave width over, and no further.
func _caption_widths() -> PackedFloat32Array:
	var font := get_theme_font(&"section_font", &"Strategic")
	var pixels := get_theme_constant(&"section_size", &"Strategic")
	var wide := PackedFloat32Array()
	for section in _model.sections:
		wide.append(ceilf(font.get_string_size(section.caption + CONTINUED, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x))
	return wide


## The layout's section captions, shaped once per layout: each in its band, cut
## with an ellipsis where its column is narrower than its words.
func _shape_headings() -> void:
	_heading_words = PackedStringArray()
	_heading_lines.clear()
	_heading_rects.clear()
	_heading_cut.clear()
	var font := get_theme_font(&"section_font", &"Strategic")
	var pixels := get_theme_constant(&"section_size", &"Strategic")
	for heading in _layout.headings:
		var said := _model.sections[heading.section].caption + (CONTINUED if heading.continued else "")
		var line := TextLine.new()
		line.add_string(said, font, pixels)
		_heading_cut.append(line.get_size().x > heading.rect.size.x)
		line.width = heading.rect.size.x
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_heading_words.append(said)
		_heading_lines.append(line)
		_heading_rects.append(heading.rect)


## Which zone each caption stands for, from the model shown now. Every model,
## not once per layout: a model with the same rows and words keeps the shaped
## text and still names its own zones.
func _bind_headings() -> void:
	_heading_keys = PackedStringArray()
	for heading in _layout.headings:
		_heading_keys.append(_model.sections[heading.section].key)


## Queue a drawing when what it would show differs from the last one queued.
func _show() -> void:
	_waits.clear()
	if _model != null and _layout != null and _layout.cell >= wait_from():
		var font := get_theme_font(&"wait_font", &"Strategic")
		var pixels := get_theme_constant(&"wait_size", &"Strategic")
		for table in _model.tables:
			for seat in table.seats:
				if seat.wait.is_empty():
					continue
				var width := font.get_string_size(seat.wait, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
				if width <= _squares[seat.key].size.x - 2:
					_waits[seat.key] = seat.wait
	var shown := (
		JSON
		. stringify(
			[
				"" if _model == null else _model.signature(),
				_waits,
				_pointed,
				_laid_for,
			]
		)
	)
	if shown != _shown:
		_shown = shown
		queue_redraw()


## In passes, so the canvas batches by texture: every frame, divider, square
## and section rule (untextured), then every caption (the fonts' atlases), then
## the waits, then the dash and the corners. Drawn table by table, each caption between
## rects broke the batch twice a table (173 draw calls at 400 panes, 75 in
## passes). Captions stand above their boxes and cover no square, so the
## picture is the same.
func _draw() -> void:
	draws += 1
	if _model == null or _layout == null:
		return
	var frame := get_theme_color(&"frame", &"Strategic")
	var divider := get_theme_color(&"divider", &"Strategic")
	var caption := get_theme_color(&"caption", &"Strategic")
	var rule := float(get_theme_constant(&"rule", &"Strategic"))
	var in_row: Dictionary[int, int] = {}
	var lines: Array[TextLine] = []
	var tops: Array[Vector2] = []
	for table in _model.tables:
		var index: int = in_row.get(table.row, 0)
		in_row[table.row] = index + 1
		var framed: Rect2 = _boxes[table.key]
		draw_rect(framed, frame)
		var band := _layout.divider_rect(table.row, index)
		var line_at := band.position + Vector2(0, floorf((band.size.y - rule) / 2.0))
		draw_rect(Rect2(line_at, Vector2(band.size.x, rule)), divider)
		for seat in table.seats:
			draw_rect(_squares[seat.key], get_theme_color(seat.look, &"Strategic"))
		var line: TextLine = _captions.get(table.key)
		if line != null:
			var over := _layout.caption_rect(table.row, index)
			lines.append(line)
			tops.append(Vector2(over.position.x, over.end.y - rule - roundf(line.get_size().y)))
	# A section's rule runs on from its caption to its column's edge, mid-band.
	var gap := float(get_theme_constant(&"pad", &"Strategic"))
	for index in _heading_rects.size():
		var band := _heading_rects[index]
		var from := band.position.x + ceilf(_heading_lines[index].get_size().x) + gap
		if from < band.end.x:
			draw_rect(
				Rect2(from, band.position.y + floorf((band.size.y - rule) / 2.0), band.end.x - from, rule), divider
			)
	for index in lines.size():
		lines[index].draw(get_canvas_item(), tops[index], caption)
	var section_ink := get_theme_color(&"section_caption", &"Strategic")
	for index in _heading_lines.size():
		var band := _heading_rects[index]
		var line := _heading_lines[index]
		var down := floorf((band.size.y - line.get_size().y) / 2.0)
		line.draw(get_canvas_item(), band.position + Vector2(0, down), section_ink)
	_draw_waits()
	# The pointer's dash and the selection's corners both stand on the cell's
	# outer edge, a unit of the box's ink from the square, so that they read
	# on a square of any colour (a paper stroke would run into a cream square).
	# The corners go over the dash when both mark the same pane.
	var ring := get_theme_constant(&"ring", &"Strategic")
	if _squares.has(_pointed):
		_draw_dash(_squares[_pointed].grow(ring), rule)
	var chosen := picked_key()
	if _squares.has(chosen):
		_draw_corners(_squares[chosen].grow(ring), rule)


func _draw_waits() -> void:
	if _waits.is_empty():
		return
	var font := get_theme_font(&"wait_font", &"Strategic")
	var pixels := get_theme_constant(&"wait_size", &"Strategic")
	var ink := get_theme_color(&"wait", &"Strategic")
	var ascent := font.get_ascent(pixels)
	var descent := font.get_descent(pixels)
	for key: String in _waits:
		var square := _squares[key]
		var text := _waits[key]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
		var x := square.position.x + floorf((square.size.x - width) / 2.0)
		var baseline := square.position.y + roundf((square.size.y + ascent - descent) / 2.0)
		draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, ink)


## Four corners on the edge of `cell`, `rule` thick, each arm a
## `corner_part`th of the cell long.
func _draw_corners(cell_rect: Rect2, rule: float) -> void:
	var colour := get_theme_color(&"corner", &"Strategic")
	var arm := maxf(2.0 * rule, floorf(cell_rect.size.x / maxi(get_theme_constant(&"corner_part", &"Strategic"), 1)))
	var left := cell_rect.position.x
	var top := cell_rect.position.y
	var right := cell_rect.end.x - rule
	var bottom := cell_rect.end.y - rule
	for x: float in [left, cell_rect.end.x - arm]:
		draw_rect(Rect2(x, top, arm, rule), colour)
		draw_rect(Rect2(x, bottom, arm, rule), colour)
	for y: float in [top, cell_rect.end.y - arm]:
		draw_rect(Rect2(left, y, rule, arm), colour)
		draw_rect(Rect2(right, y, rule, arm), colour)


## The pointer's dash (OfficePointer._draw()) round `rect`: strokes of `dash`
## units alternating ink and paper, `rule` thick, on whole units.
func _draw_dash(rect: Rect2, rule: float) -> void:
	var ink := get_theme_color(&"pointer_a", &"Strategic")
	var paper := get_theme_color(&"pointer_b", &"Strategic")
	var dash := float(maxi(get_theme_constant(&"dash", &"Strategic"), 1))
	var right := rect.end.x - rule
	var bottom := rect.end.y - rule
	var stroke := 0
	var x := rect.position.x
	while x < rect.end.x:
		var across := minf(dash, rect.end.x - x)
		var colour := ink if stroke % 2 == 0 else paper
		draw_rect(Rect2(x, rect.position.y, across, rule), colour)
		draw_rect(Rect2(x, bottom, across, rule), colour)
		x += dash
		stroke += 1
	stroke = 1
	var y := rect.position.y + rule
	while y < bottom:
		var down := minf(dash, bottom - y)
		var colour := ink if stroke % 2 == 0 else paper
		draw_rect(Rect2(rect.position.x, y, rule, down), colour)
		draw_rect(Rect2(right, y, rule, down), colour)
		y += dash
		stroke += 1
