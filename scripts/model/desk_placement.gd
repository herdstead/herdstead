class_name DeskPlacement
extends RefCounted

## How many geometry signatures this process has built: a diagnostic, never a
## decision, so a test can prove a refresh on an unchanged plan builds none.
static var signatures := 0

var tab_key := ""
## ZoneModel.key of the zone the desk stands in (FloorPlan.zone()).
var zone_key := ""
var row := -1
var reserved_cells := Rect2i()
var origin := Vector2.ZERO
var capacity := 2
var seats: Array[SeatPlacement] = []
var measure: DeskMeasure


func seat(pane_key: String) -> SeatPlacement:
	for placed in seats:
		if placed.pane_key == pane_key:
			return placed
	return null


func geometry_signature() -> String:
	signatures += 1
	var members := PackedStringArray()
	for placed in seats:
		members.append(placed.geometry_signature())
	members.sort()
	return JSON.stringify([tab_key, zone_key, row, reserved_cells, origin, capacity, members])
