class_name OfficePointer
extends Node2D
## Herdstead's pointing: while the mouse rests on a HUD line about a pane
## (a NEWS item, a row of the agent list or of EVENTS), a dashed frame around
## that pane's desk on the shown floor: its click area and, while it shows, its
## chip. A third thing beside herdr's focus (the lamp) and the selection (the
## corners, the table's frame), drawn its own way: a static dash of the pack's
## `ink` and `paper`, 1 unit thick, DASH units a stroke, on whole units. No
## texture and no new art; it points only, and never selects, pans, reads or writes.
##
## One per floor, the floor root's last child (OfficeFloorView.setup()), over
## the world like the labels (OfficeWorld.OVERLAY_Z). A zoom changes nothing
## here: the frame is in the floor's own units.

## Units per stroke; strokes alternate ink and paper.
const DASH := 3
## How far the frame stands off what it frames, in units, all round.
const GROW := 2

## The frame, in the floor root's coordinates, whole units; empty while hidden.
var rect := Rect2()
## The pane key pointed at; empty while hidden.
var key := ""
var _ink := Color.BLACK
var _paper := Color.WHITE


func _init() -> void:
	name = "Pointer"
	visible = false
	z_index = OfficeWorld.OVERLAY_Z


## Take the pack's ink and paper; a theme switch builds a new floor anyway.
func dress(art: ArtPack) -> void:
	_ink = art.color(ArtContract.INK)
	_paper = art.color(ArtContract.PAPER)
	queue_redraw()


## Frame `bounds` (floor-root coordinates) for pane `pane_key`: grown by GROW
## and rounded out to whole units, so every stroke lands on whole texels.
func point_at(pane_key: String, bounds: Rect2) -> void:
	var grown := bounds.grow(GROW)
	var from := grown.position.floor()
	var framed := Rect2(from, grown.end.ceil() - from)
	if pane_key == key and framed == rect and visible:
		return
	key = pane_key
	rect = framed
	visible = true
	queue_redraw()


## Point at nothing.
func clear() -> void:
	if not visible and key.is_empty():
		return
	key = ""
	rect = Rect2()
	visible = false


func _draw() -> void:
	if not rect.has_area():
		return
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x - 1.0
	var bottom := rect.end.y - 1.0
	var stroke := 0
	var x := left
	while x < rect.end.x:
		var across := minf(DASH, rect.end.x - x)
		var color := _ink if stroke % 2 == 0 else _paper
		draw_rect(Rect2(x, top, across, 1), color)
		draw_rect(Rect2(x, bottom, across, 1), color)
		x += DASH
		stroke += 1
	stroke = 1
	var y := top + 1.0
	while y < bottom:
		var down := minf(DASH, bottom - y)
		var color := _ink if stroke % 2 == 0 else _paper
		draw_rect(Rect2(left, y, 1, down), color)
		draw_rect(Rect2(right, y, 1, down), color)
		y += DASH
		stroke += 1
