class_name FixturePlacement
extends RefCounted
## One of a floor's two service fixtures in its entry band, as the plan placed
## it: the reception counter with its queue's slots, or the pantry with its
## spots. Planned by OfficeFixturePlanner, drawn by OfficeFloorView, walked to by
## OfficePresentation. The counters themselves are furniture; who stands at the
## pantry's spots, and in which order, is the presentation's (OfficeRests).
## Nobody stands at the reception's slots: the plan still keeps
## them clear in front of the counter, so no floor is laid out differently.

enum Kind { RECEPTION, PANTRY }

var kind := Kind.RECEPTION
## Stable within the plan: "reception" or "pantry".
var key := ""
## The counter's semantic prop.
var piece: StringName = &""
## Where the counter meets the floor, against the top wall.
var position := Vector2.ZERO
## What the counter stands on, and what it draws, in floor units.
var footprint := Rect2()
var draw_rect := Rect2()
## Where people stand at it, on the fixture row: a queue's slots from its head,
## next to the counter, leftwards (kept clear, used by nobody); a pantry's
## spots from the left wall on.
var spots: Array[Vector2] = []
## Straight below each spot on the walking lane: where its leg begins.
var approaches: Array[Vector2] = []


func capacity() -> int:
	return spots.size()


func geometry_signature() -> String:
	return JSON.stringify([kind, key, piece, position, footprint, draw_rect, spots, approaches])
