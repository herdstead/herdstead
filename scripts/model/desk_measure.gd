class_name DeskMeasure
extends RefCounted
## Table-local geometry shared by planning and the instantiated workstation.
## OfficeTable.measure() is its sole producer; no layout constants live here.

var capacity := 0
var table_width := 0.0
var columns: Array[float] = []
var physical_rect := Rect2()
## Space reserved for furniture, labels, standing and approach clearance.
var reserved_rect := Rect2()
## The complete supported stationary workstation drawing envelope.
var render_rect := Rect2()
var far_seats: Array[Vector2] = []
var near_seats: Array[Vector2] = []
var far_standing: Array[Vector2] = []
var near_standing: Array[Vector2] = []
var far_approaches: Array[Vector2] = []
var near_approaches: Array[Vector2] = []


func has_seat(column: int, side: String) -> bool:
	return column >= 0 and column < capacity and side in ["far", "near"]


func seat_position(column: int, side: String) -> Vector2:
	if not has_seat(column, side):
		return Vector2.INF
	return far_seats[column] if side == "far" else near_seats[column]


func standing_position(column: int, side: String) -> Vector2:
	if not has_seat(column, side):
		return Vector2.INF
	return far_standing[column] if side == "far" else near_standing[column]


func approach_position(column: int, side: String) -> Vector2:
	if not has_seat(column, side):
		return Vector2.INF
	return far_approaches[column] if side == "far" else near_approaches[column]
