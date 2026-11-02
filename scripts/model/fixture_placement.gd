class_name FixturePlacement
extends RefCounted
## A map's service fixture in its entry band, as the plan placed it: the
## pantry counter in the band's corner. Planned by OfficeFixturePlanner, drawn
## by OfficeFloorView and checked against other map geometry. It is furniture,
## never an agent's state or destination. There is no reception any more.

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


func geometry_signature() -> String:
	return JSON.stringify([kind, key, piece, position, footprint, draw_rect])
