class_name OverviewTimeline
extends Control
## One pane's state since this office opened, as a band of flat colours along
## the OVERVIEW's TIMELINE column: time runs left to right from the log's first
## observation to now, one run of colour per observed segment, and a hatch
## where nobody watched (before the pane appeared, after it went, while its
## machine was away, and the oldest segments folded together past
## StateLog.SEGMENTS_MAX). A pane that was there when the office opened starts
## in its state at the left edge: its start is unknown, not unobserved.
##
## Colours and the two measures (`inset`, `hatch_step`) are the theme's
## `Timeline` type (HudTheme._overview()); the geometry is this control's own
## size. Drawn again only when told (show_track()), never every frame.

## The state_index a span has when nobody watched it.
const UNOBSERVED := -1

## The legend's swatch for "not observed": the whole control is one hatch.
@export var legend := false

var _track: StateLog.Track
var _opened := 0
var _now := 0


## Draw `track` over `[opened_msec, now_msec]` on the next frame.
func show_track(track: StateLog.Track, opened_msec: int, now_msec: int) -> void:
	_track = track
	_opened = opened_msec
	_now = now_msec
	queue_redraw()


## What is drawn now, left to right: `[state_index, x0, x1]` per span, in
## this control's units; state_index is StateLog.STATES' index, 4 for
## unknown, UNOBSERVED for a hatch.
func segments_drawn() -> Array[PackedFloat64Array]:
	return spans(_track, _opened, _now, size.x, get_theme_constant(&"inset", &"Timeline"))


func _draw() -> void:
	if legend:
		var whole := Rect2(Vector2.ZERO, size)
		draw_rect(whole, get_theme_color(&"unobserved_fill", &"Timeline"))
		_hatch(whole)
		return
	var inset := get_theme_constant(&"inset", &"Timeline")
	var top := float(inset)
	var bottom := size.y - inset
	if bottom <= top:
		return
	for span in spans(_track, _opened, _now, size.x, inset):
		var box := Rect2(span[1], top, span[2] - span[1], bottom - top)
		if int(span[0]) == UNOBSERVED:
			draw_rect(box, get_theme_color(&"unobserved_fill", &"Timeline"))
			_hatch(box)
		else:
			draw_rect(box, get_theme_color(_colour_name(int(span[0])), &"Timeline"))
	if _now > _opened:
		# Now: the right edge, a rule as wide as the theme says.
		var rule := float(get_theme_constant(&"rule", &"Timeline"))
		var edge := size.x - inset
		draw_rect(Rect2(edge - rule, top, rule, bottom - top), get_theme_color(&"axis", &"Timeline"))


## Diagonal lines a rule wide (the theme's `rule`), one every `hatch_step`
## units, rising left to right, cut to `box`.
func _hatch(box: Rect2) -> void:
	var step := maxi(get_theme_constant(&"hatch_step", &"Timeline"), 1)
	# A unit wide, like every other edge here: a hairline (-1) would stay one
	# screen pixel at every zoom while the band around it grows. The lines run
	# half their width inside the box, so no stroke pokes out of the band.
	var rule := float(get_theme_constant(&"rule", &"Timeline"))
	var inner := box.grow(-rule / 2.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var height := inner.size.y
	var points := PackedVector2Array()
	# Every line starts on a multiple of the step from the control's left, so
	# the hatch of two neighbouring spans lines up.
	var foot := floorf((inner.position.x - height) / step) * step
	while foot < inner.end.x:
		var start := maxf(foot, inner.position.x)
		var finish := minf(foot + height, inner.end.x)
		if finish > start:
			points.append(Vector2(start, inner.end.y - (start - foot)))
			points.append(Vector2(finish, inner.end.y - (finish - foot)))
		foot += step
	if not points.is_empty():
		draw_multiline(points, get_theme_color(&"unobserved_line", &"Timeline"), rule)


static func _colour_name(index: int) -> StringName:
	if index >= 0 and index < StateLog.STATES.size():
		return StringName(StateLog.STATES[index])
	return &"unknown"


## The spans of `track` over `[opened, now]` on a band `width` units wide,
## `inset` in from both ends; whole units, so every edge falls on a whole
## screen pixel at an even zoom. Spans narrower than a unit are left out.
static func spans(track: StateLog.Track, opened: int, now: int, width: float, inset: int) -> Array[PackedFloat64Array]:
	var drawn: Array[PackedFloat64Array] = []
	if track == null or now <= opened or width <= 2.0 * inset:
		return drawn
	var reach := width - 2.0 * inset
	var cursor := opened
	for segment in track.segments:
		var start := maxi(segment.start_msec, opened)
		var finish := now if segment.end_msec < 0 else mini(segment.end_msec, now)
		if start > cursor:
			_add(drawn, UNOBSERVED, _x(cursor, opened, now, inset, reach), _x(start, opened, now, inset, reach))
		var index := UNOBSERVED
		if segment.observed and not segment.elided:
			index = StateLog.STATES.find(segment.state)
			if index < 0:
				index = StateLog.STATES.size()
		_add(drawn, index, _x(start, opened, now, inset, reach), _x(finish, opened, now, inset, reach))
		cursor = maxi(cursor, finish)
	if cursor < now:
		_add(drawn, UNOBSERVED, _x(cursor, opened, now, inset, reach), _x(now, opened, now, inset, reach))
	return drawn


## Where `msec` falls on a band `reach` units wide from `inset`: a whole unit.
static func _x(msec: int, opened: int, now: int, inset: int, reach: float) -> float:
	return inset + roundf(clampf(float(msec - opened) / float(now - opened), 0.0, 1.0) * reach)


## One span, merged into the one before when it is the same kind and they meet.
static func _add(drawn: Array[PackedFloat64Array], index: int, x0: float, x1: float) -> void:
	if x1 <= x0:
		return
	if not drawn.is_empty():
		var last := drawn[drawn.size() - 1]
		if int(last[0]) == index and last[2] >= x0:
			last[2] = maxf(last[2], x1)
			drawn[drawn.size() - 1] = last
			return
		# Rounding can leave the previous span reaching past this one's start.
		x0 = maxf(x0, last[2])
		if x1 <= x0:
			return
	drawn.append(PackedFloat64Array([index, x0, x1]))
