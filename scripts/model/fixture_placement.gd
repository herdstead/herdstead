class_name FixturePlacement
extends RefCounted
## A map's service fixture in its entry band, as the plan placed it: the
## pantry with its spots. Planned by OfficeFixturePlanner, drawn by
## OfficeFloorView, walked to by OfficePresentation. The counter itself is
## furniture; who stands at the pantry's spots, and in which order, is the
## presentation's (OfficeRests). There is no reception any more.

enum Kind { PANTRY }

var kind := Kind.PANTRY
## Stable within the plan: "pantry".
var key := ""
## The counter's semantic prop.
var piece: StringName = &""
## Where the counter meets the floor, against the top wall.
var position := Vector2.ZERO
## What the counter stands on, and what it draws, in floor units.
var footprint := Rect2()
var draw_rect := Rect2()
## Where people stand at it, on the fixture row: the pantry's spots from the
## left wall on.
var spots: Array[Vector2] = []
## Straight below each spot on the walking lane: where its leg begins.
var approaches: Array[Vector2] = []


func capacity() -> int:
	return spots.size()


func geometry_signature() -> String:
	return JSON.stringify([kind, key, piece, position, footprint, draw_rect, spots, approaches])
