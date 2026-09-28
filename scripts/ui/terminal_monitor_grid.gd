class_name TerminalMonitorGrid
extends Control
## The terminal monitor's screen: exactly `columns` x `rows` cells of a
## TerminalScreen, drawn in a custom _draw() because no engine control keeps a
## wide character on a two-cell grid (RichTextLabel was measured slower and
## misaligned). It is HUD, so its text is vector text like the
## rest of the HUD, not 1x pixel art.
##
## Every cell is a whole number of screen pixels: the font size is the largest
## whole HUD unit at which the grid fits this control, the cell is that font's
## advance and height rounded up to whole pixels at the window's scale, and the
## grid is centred in what is left (letterboxed). Box-drawing and block
## characters are drawn as rectangles, so vertical lines meet across rows.
##
## Fonts and colours come from HudTheme's `MonitorGrid` type variation; the
## 256-colour palette is xterm's. Nothing is redrawn unless the text changed,
## the size changed or the monitor dimmed.

## xterm's first 16 colours.
const PALETTE_16: Array[Color] = [
	Color8(0, 0, 0),
	Color8(205, 49, 49),
	Color8(13, 188, 121),
	Color8(229, 229, 16),
	Color8(36, 114, 200),
	Color8(188, 63, 188),
	Color8(17, 168, 205),
	Color8(229, 229, 229),
	Color8(102, 102, 102),
	Color8(241, 76, 76),
	Color8(35, 209, 139),
	Color8(245, 245, 67),
	Color8(59, 142, 234),
	Color8(214, 112, 214),
	Color8(41, 184, 219),
	Color8(255, 255, 255),
]
const CUBE_STEPS: Array[int] = [0, 95, 135, 175, 215, 255]
## Font sizes tried, in HUD units, largest first.
const FONT_LARGEST := 16
const FONT_SMALLEST := 4
## How many parse and draw timings are kept for the perf probe.
const TIMINGS_MAX := 512
## A box-drawing character's arms: up, right, down, left, two bits each
## (1 light, 2 heavy, 3 double).
const BOX: Dictionary[int, int] = {
	0x2500: 0x44,
	0x2501: 0x88,
	0x2502: 0x11,
	0x2503: 0x22,
	0x2504: 0x44,
	0x2505: 0x88,
	0x2506: 0x11,
	0x2507: 0x22,
	0x2508: 0x44,
	0x2509: 0x88,
	0x250A: 0x11,
	0x250B: 0x22,
	0x250C: 0x14,
	0x250F: 0x28,
	0x2510: 0x50,
	0x2513: 0xA0,
	0x2514: 0x05,
	0x2517: 0x0A,
	0x2518: 0x41,
	0x251B: 0x82,
	0x251C: 0x15,
	0x2523: 0x2A,
	0x2524: 0x51,
	0x252B: 0xA2,
	0x252C: 0x54,
	0x2533: 0xA8,
	0x2534: 0x45,
	0x253B: 0x8A,
	0x253C: 0x55,
	0x254B: 0xAA,
	0x254C: 0x44,
	0x254D: 0x88,
	0x254E: 0x11,
	0x254F: 0x22,
	0x2550: 0xCC,
	0x2551: 0x33,
	0x2554: 0x3C,
	0x2557: 0xF0,
	0x255A: 0x0F,
	0x255D: 0xC3,
	0x2560: 0x3F,
	0x2563: 0xF3,
	0x2566: 0xFC,
	0x2569: 0xCF,
	0x256C: 0xFF,
	0x256D: 0x14,
	0x256E: 0x50,
	0x256F: 0x41,
	0x2570: 0x05,
	0x2574: 0x40,
	0x2575: 0x01,
	0x2576: 0x04,
	0x2577: 0x10,
}

## Whether the machine dropped: the last screen stays, dimmed and frozen.
var dimmed := false:
	set(value):
		if dimmed != value:
			dimmed = value
			queue_redraw()

var screen := TerminalScreen.new(80, 24)
## Microseconds each show_text() / show_lines() and each _draw() took, newest last.
var parse_usec := PackedInt32Array()
var draw_usec := PackedInt32Array()
## Microseconds every _draw() also waits: 0, except for a test that scripts a
## slow draw (tools/test_monitor.gd). Nothing in the office sets it.
var draw_delay_usec := 0

## What the grid measured last: font size in units, cell size and origin in units.
var _font_size := 0
var _cell := Vector2.ZERO
var _origin := Vector2.ZERO
var _ascent := 0.0
var _measured_for := ""


func _ready() -> void:
	resized.connect(_remeasure)
	theme_changed.connect(_remeasure)


## Draw a `width` x `height` grid from now on; the screen is blank until the next text.
func set_grid(width: int, height: int) -> void:
	if width == screen.columns and height == screen.rows:
		return
	screen.resize(width, height)
	_remeasure()


## Show herdr's `visible` text: whether anything changed (and is redrawn).
func show_text(ansi: String) -> bool:
	var started := Time.get_ticks_usec()
	var changed := screen.set_text(ansi)
	_note_parse(Time.get_ticks_usec() - started)
	if changed:
		queue_redraw()
	return changed


## Show `lines` of scrollback from the top row down.
func show_lines(lines: PackedStringArray) -> bool:
	var started := Time.get_ticks_usec()
	var changed := screen.set_lines(lines)
	_note_parse(Time.get_ticks_usec() - started)
	if changed:
		queue_redraw()
	return changed


## What the last change cost: the last parse and the last draw, in microseconds.
func last_cost_usec() -> int:
	var parse := 0 if parse_usec.is_empty() else parse_usec[parse_usec.size() - 1]
	var drawn := 0 if draw_usec.is_empty() else draw_usec[draw_usec.size() - 1]
	return parse + drawn


## The font size in HUD units the grid is drawn at now; 0 before the first measure.
func font_size_now() -> int:
	_measure()
	return _font_size


## Where the grid is drawn inside this control, in its own units.
func grid_rect() -> Rect2:
	_measure()
	return Rect2(_origin, _cell * Vector2(screen.columns, screen.rows))


func _remeasure() -> void:
	_measured_for = ""
	queue_redraw()


## Pick the font size and cell for this size and screen scale, once per change.
func _measure() -> void:
	var density := _pixels_per_unit()
	var key := "%s|%s|%d|%d|%f" % [size, get_theme_font("font"), screen.columns, screen.rows, density]
	if key == _measured_for:
		return
	_measured_for = key
	var font := get_theme_font("font")
	_font_size = FONT_SMALLEST
	for candidate in range(FONT_LARGEST, FONT_SMALLEST - 1, -1):
		var cell := _cell_of(font, candidate, density)
		if cell.x * screen.columns <= size.x and cell.y * screen.rows <= size.y:
			_font_size = candidate
			break
	_cell = _cell_of(font, _font_size, density)
	_ascent = ceilf(_own(font, _font_size, true) * density) / density
	var spare := (size - _cell * Vector2(screen.columns, screen.rows)).maxf(0.0)
	_origin = (spare / 2.0 * density).floor() / density


## A cell at font size `font_size`: the advance of "M" and the line height,
## each rounded up to whole screen pixels at `density` pixels per unit. The
## height is the monospace face's own: a Font's height is the tallest of its
## fallbacks, and the colour emoji and CJK faces made every row taller than a
## terminal's (seen in captures: a 120x40 grid fitted only at font 6
## at 2x, and at 8 without them). A taller glyph may reach into the next row, as in a terminal.
static func _cell_of(font: Font, font_size: int, density: float) -> Vector2:
	var advance := font.get_char_size("M".unicode_at(0), font_size).x
	var height := _own(font, font_size, true) + _own(font, font_size, false)
	return Vector2(ceilf(advance * density - 0.01), ceilf(height * density - 0.01)) / density


## The first face's own ascent (or descent) at `font_size`, without its
## fallbacks; the Font's, fallbacks and all, when it has no face of its own.
static func _own(font: Font, font_size: int, ascent: bool) -> float:
	var faces := font.get_rids()
	if faces.is_empty():
		return font.get_ascent(font_size) if ascent else font.get_descent(font_size)
	var server := TextServerManager.get_primary_interface()
	if ascent:
		return server.font_get_ascent(faces[0], font_size)
	return server.font_get_descent(faces[0], font_size)


func _pixels_per_unit() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(1.0, get_viewport().get_final_transform().get_scale().x)


func _draw() -> void:
	var started := Time.get_ticks_usec()
	if draw_delay_usec > 0:
		OS.delay_usec(draw_delay_usec)
	_measure()
	var back := get_theme_color("default_bg")
	var fore := get_theme_color("default_fg")
	draw_rect(Rect2(Vector2.ZERO, size), get_theme_color("letterbox"))
	draw_rect(grid_rect(), back)
	var regular := get_theme_font("font")
	var bold := get_theme_font("bold_font")
	var italic := get_theme_font("italic_font")
	var line := maxf(1.0, roundf(_cell.y / 16.0 * _pixels_per_unit())) / _pixels_per_unit()
	for row in screen.rows:
		var top := _origin.y + row * _cell.y
		var glyphs := screen.glyphs[row]
		var fgs := screen.fg[row]
		var bgs := screen.bg[row]
		var marks := screen.flags[row]
		# Backgrounds, as runs of one colour.
		var column := 0
		while column < screen.columns:
			var colour := _back_of(fgs[column], bgs[column], marks[column], fore, back)
			var start := column
			column += 1
			while column < screen.columns and _back_of(fgs[column], bgs[column], marks[column], fore, back) == colour:
				column += 1
			if colour != back:
				draw_rect(Rect2(_origin.x + start * _cell.x, top, (column - start) * _cell.x, _cell.y), colour)
		# Then every cluster at its own column.
		for at in screen.columns:
			var glyph := glyphs[at]
			var mark := marks[at]
			if glyph.is_empty() and not (mark & (TerminalScreen.UNDERLINE | TerminalScreen.STRIKE)):
				continue
			if mark & TerminalScreen.CONTINUATION:
				continue
			var ink := _fore_of(fgs[at], bgs[at], mark, fore, back)
			var width := 2 if mark & TerminalScreen.WIDE else 1
			var cell := Rect2(_origin.x + at * _cell.x, top, _cell.x * width, _cell.y)
			if not glyph.is_empty() and not _geometry(glyph, cell, ink, line):
				var font := regular
				if mark & TerminalScreen.BOLD:
					font = bold
				elif mark & TerminalScreen.ITALIC:
					font = italic
				# A colour emoji keeps its own colours.
				var tint := Color.WHITE if _emoji(glyph) else ink
				draw_string(
					font,
					Vector2(cell.position.x, top + _ascent),
					glyph,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					_font_size,
					tint
				)
			if mark & TerminalScreen.UNDERLINE:
				draw_rect(Rect2(cell.position.x, top + _ascent + line, cell.size.x, line), ink)
			if mark & TerminalScreen.STRIKE:
				draw_rect(Rect2(cell.position.x, top + floorf(_cell.y / 2.0), cell.size.x, line), ink)
	if dimmed:
		var shade := back
		shade.a = 0.6
		draw_rect(Rect2(Vector2.ZERO, size), shade)
	draw_usec.append(Time.get_ticks_usec() - started)
	if draw_usec.size() > TIMINGS_MAX:
		draw_usec.remove_at(0)


## Draw `glyph` as rectangles when it is a box-drawing or block character;
## false for anything else, which the font draws.
func _geometry(glyph: String, cell: Rect2, ink: Color, line: float) -> bool:
	if glyph.length() != 1:
		return false
	var code := glyph.unicode_at(0)
	if BOX.has(code):
		_box(BOX[code], cell, ink, line)
		return true
	if code >= 0x2591 and code <= 0x2593:
		# Light, medium and dark shade: the whole cell, a quarter to three quarters opaque.
		var shade := ink
		shade.a *= (code - 0x2590) / 4.0
		draw_rect(cell, shade)
		return true
	var block := _block(code, cell)
	if not block.has_area():
		return false
	draw_rect(block, ink)
	return true


## The part of `cell` a block element (U+2580–U+2595, shades aside) fills;
## an empty Rect2 for any other code point.
func _block(code: int, cell: Rect2) -> Rect2:
	var filled := Rect2()
	if code == 0x2588:
		filled = cell
	elif code >= 0x2581 and code <= 0x2587:
		var high := _snap(cell.size.y * (code - 0x2580) / 8.0)
		filled = Rect2(cell.position.x, cell.end.y - high, cell.size.x, high)
	elif code >= 0x2589 and code <= 0x258F:
		filled = Rect2(cell.position, Vector2(_snap(cell.size.x * (0x2590 - code) / 8.0), cell.size.y))
	elif code == 0x2580:
		filled = Rect2(cell.position, Vector2(cell.size.x, _snap(cell.size.y / 2.0)))
	elif code == 0x2590:
		var half := _snap(cell.size.x / 2.0)
		filled = Rect2(cell.position.x + half, cell.position.y, cell.size.x - half, cell.size.y)
	elif code == 0x2594:
		filled = Rect2(cell.position, Vector2(cell.size.x, _snap(cell.size.y / 8.0)))
	elif code == 0x2595:
		var eighth := _snap(cell.size.x / 8.0)
		filled = Rect2(cell.end.x - eighth, cell.position.y, eighth, cell.size.y)
	return filled


## A box-drawing character's arms from the cell's centre to its edges.
func _box(arms: int, cell: Rect2, ink: Color, line: float) -> void:
	var centre := Vector2(_snap(cell.size.x / 2.0), _snap(cell.size.y / 2.0)) + cell.position
	for side in 4:
		var weight := (arms >> (side * 2)) & 3
		if weight == 0:
			continue
		var thick := line * (2.0 if weight == 2 else 1.0)
		var offsets := PackedFloat32Array([0.0]) if weight != 3 else PackedFloat32Array([-line, line])
		for offset in offsets:
			match side:
				0:
					draw_rect(
						Rect2(
							centre.x - thick / 2.0 + offset,
							cell.position.y,
							thick,
							centre.y - cell.position.y + thick / 2.0
						),
						ink
					)
				1:
					draw_rect(
						Rect2(
							centre.x - thick / 2.0,
							centre.y - thick / 2.0 + offset,
							cell.end.x - centre.x + thick / 2.0,
							thick
						),
						ink
					)
				2:
					draw_rect(
						Rect2(
							centre.x - thick / 2.0 + offset,
							centre.y - thick / 2.0,
							thick,
							cell.end.y - centre.y + thick / 2.0
						),
						ink
					)
				3:
					draw_rect(
						Rect2(
							cell.position.x,
							centre.y - thick / 2.0 + offset,
							centre.x - cell.position.x + thick / 2.0,
							thick
						),
						ink
					)


## `units` rounded to whole screen pixels.
func _snap(units: float) -> float:
	var density := _pixels_per_unit()
	return roundf(units * density) / density


func _fore_of(colour: int, other: int, mark: int, fore: Color, back: Color) -> Color:
	var ink := _colour(other, back) if mark & TerminalScreen.REVERSE else _colour(colour, fore)
	if mark & TerminalScreen.DIM:
		ink = ink.lerp(_back_of(colour, other, mark, fore, back), 0.45)
	return ink


func _back_of(colour: int, other: int, mark: int, fore: Color, back: Color) -> Color:
	return _colour(colour, fore) if mark & TerminalScreen.REVERSE else _colour(other, back)


## A TerminalScreen colour as a Color; `fallback` for DEFAULT.
static func _colour(value: int, fallback: Color) -> Color:
	if value == TerminalScreen.DEFAULT:
		return fallback
	if value & TerminalScreen.RGB_FLAG:
		return Color8((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
	if value < 16:
		return PALETTE_16[value]
	if value < 232:
		var index := value - 16
		return Color8(CUBE_STEPS[floori(index / 36.0)], CUBE_STEPS[floori(index / 6.0) % 6], CUBE_STEPS[index % 6])
	var grey := 8 + (value - 232) * 10
	return Color8(grey, grey, grey)


## Whether `glyph` is a colour emoji, drawn in its own colours.
static func _emoji(glyph: String) -> bool:
	var first := glyph.unicode_at(0)
	return first >= 0x1F000 or glyph.contains("\ufe0f")


func _note_parse(usec: int) -> void:
	parse_usec.append(usec)
	if parse_usec.size() > TIMINGS_MAX:
		parse_usec.remove_at(0)
