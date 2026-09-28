class_name DecorPlacement
extends RefCounted
## Resolved semantic prop and its real floor-local collision/drawing bounds.

var key := ""
var piece: StringName = &""
var position := Vector2.ZERO
var footprint := Rect2()
var draw_rect := Rect2()


func geometry_signature() -> String:
	return JSON.stringify([key, piece, position, footprint, draw_rect])
