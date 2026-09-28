class_name OverviewAxis
extends Control
## The OVERVIEW's time axis over the TIMELINE column: the wall-clock time the
## office opened at the left, a tick every 5, 10, 15, 30 or 60 minutes as the
## span grows, and `now` at the right, on the same band the rows' timelines
## are drawn on (the theme's `Timeline` inset). Labels are the viewer's local
## time (OfficeAttention.wall_clock()); the font and its size are the theme's
## `LabelSlate`, the rules its `Timeline` `axis` colour.

## Minutes between ticks for spans up to the first number of minutes; longer
## spans tick hourly.
const STEPS: Array[Vector2i] = [Vector2i(30, 5), Vector2i(60, 10), Vector2i(120, 15), Vector2i(240, 30)]
const HOURLY := 60
const NOW := "now"

var _opened_unix := 0.0
var _span_msec := 0


## The axis for a span of `span_msec` that began at `opened_unix`.
func show_span(opened_unix: float, span_msec: int) -> void:
	if opened_unix == _opened_unix and span_msec == _span_msec:
		return
	_opened_unix = opened_unix
	_span_msec = span_msec
	queue_redraw()


## The labels drawn, left to right: the opening time, the ticks that fit, `now`.
func ticks() -> PackedStringArray:
	var said := PackedStringArray()
	for mark in _marks():
		said.append(mark.text)
	return said


class Mark:
	var text := ""
	var x := 0.0
	## A tick has a rule under its label; the two ends have none.
	var rule := true


func _draw() -> void:
	var font := get_theme_font(&"font", &"LabelSlate")
	var font_size := get_theme_font_size(&"font_size", &"LabelSlate")
	var colour := get_theme_color(&"font_color", &"LabelSlate")
	var line := get_theme_color(&"axis", &"Timeline")
	var rule := float(get_theme_constant(&"rule", &"Timeline"))
	var inset := float(get_theme_constant(&"inset", &"Timeline"))
	var baseline := roundf(font.get_ascent(font_size))
	for mark in _marks():
		var width := font.get_string_size(mark.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var left := clampf(roundf(mark.x - width / 2.0), 0.0, maxf(size.x - width, 0.0))
		if not mark.rule:
			left = 0.0 if mark.x <= inset else maxf(size.x - width, 0.0)
		draw_string(font, Vector2(left, baseline), mark.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
		if mark.rule:
			draw_rect(Rect2(roundf(mark.x), baseline + rule, rule, size.y - baseline - rule), line)
	# The band's own floor, under the ticks.
	draw_rect(Rect2(inset, size.y - rule, size.x - 2.0 * inset, rule), line)


## The opening time, the ticks that keep clear of it, of `now` and of each
## other, and `now`.
func _marks() -> Array[Mark]:
	var marks: Array[Mark] = []
	var inset := float(get_theme_constant(&"inset", &"Timeline"))
	var reach := size.x - 2.0 * inset
	if _span_msec <= 0 or reach <= 0.0:
		return marks
	var font := get_theme_font(&"font", &"LabelSlate")
	var font_size := get_theme_font_size(&"font_size", &"LabelSlate")
	var gap := font.get_string_size("  ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var opened := Mark.new()
	opened.text = OfficeAttention.wall_clock(_opened_unix)
	opened.x = inset
	opened.rule = false
	var now := Mark.new()
	now.text = NOW
	now.x = inset + reach
	now.rule = false
	var left_end := font.get_string_size(opened.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + gap
	var right_end := size.x - font.get_string_size(NOW, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x - gap
	marks.append(opened)
	var step := step_minutes(_span_msec) * 60
	var tick := ceilf(_opened_unix / step) * step
	var span_seconds := _span_msec / 1000.0
	var last_right := left_end
	while tick < _opened_unix + span_seconds:
		var mark := Mark.new()
		mark.text = OfficeAttention.wall_clock(tick)
		mark.x = inset + roundf((tick - _opened_unix) / span_seconds * reach)
		var half := font.get_string_size(mark.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2.0
		if mark.x - half >= last_right and mark.x + half <= right_end:
			marks.append(mark)
			last_right = mark.x + half + gap
		tick += step
	marks.append(now)
	return marks


## Minutes between ticks for a span of `span_msec`.
static func step_minutes(span_msec: int) -> int:
	var minutes := span_msec / 60000.0
	for step in STEPS:
		if minutes <= step.x:
			return step.y
	return HOURLY
