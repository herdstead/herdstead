class_name FloorPlan
extends RefCounted
## A validated layout snapshot of one map: its zones in lanes, their desks, the
## entry band, the main corridor and the keep-outs between them. Planners never
## mutate the previous snapshot.

## The map's key: the machine's, for the office's maps (MapModel.key).
var floor_key := ""
var policy_signature := ""
## The map's width in cells when it was first planned (FloorLayoutPolicy.map_width()).
var initial_width_cells := 0
var floor_cells := Rect2i()
## How many lanes the map has: fixed at the first plan, raised only when a zone
## needs more (OfficeFloorLayout).
var lanes := 0
## The zones laid out on this map, in (number, key) order (ZonePlacement).
var zones: Array[ZonePlacement] = []
## Every desk of every zone, in map cells.
var desks: Array[DeskPlacement] = []
var decorations: Array[DecorPlacement] = []
## The walkways drawn as such: the entry band and the main corridor.
var corridors: Array[Rect2i] = []
## Keep-outs drawn as plain floor: every zone's aisle row and the aisle columns
## between lanes a zone does not span (OfficeFloorLayout.aisles_of()).
var aisles: Array[Rect2i] = []
var entry_cells := Rect2i()
var main_corridor_cells := Rect2i()
var render_bounds := Rect2()
## The entry band's one service fixture (OfficeFixturePlanner): the pantry and
## its spots. Null where the map has none: no desks, or a band too narrow (see
## docs/VISUAL_LANGUAGE.md).
var pantry: FixturePlacement


func desk(tab_key: String) -> DeskPlacement:
	for placed in desks:
		if placed.tab_key == tab_key:
			return placed
	return null


## The zone placed under ZoneModel.key `key`; null for none.
func zone(key: String) -> ZonePlacement:
	for placed in zones:
		if placed.zone_key == key:
			return placed
	return null


func seat(pane_key: String) -> SeatPlacement:
	for placed in desks:
		var found := placed.seat(pane_key)
		if found != null:
			return found
	return null


## The fixtures this map has: the pantry, or none.
func fixtures() -> Array[FixturePlacement]:
	var found: Array[FixturePlacement] = []
	if pantry != null:
		found.append(pantry)
	return found


func geometry_signature() -> String:
	var groups := PackedStringArray()
	for placed in desks:
		groups.append(placed.geometry_signature())
	groups.sort()
	var props := PackedStringArray()
	for decoration in decorations:
		props.append(decoration.geometry_signature())
	props.sort()
	var service := PackedStringArray()
	for fixture in fixtures():
		service.append(fixture.geometry_signature())
	var areas := PackedStringArray()
	for placed in zones:
		areas.append(placed.geometry_signature())
	return JSON.stringify(
		[floor_key, policy_signature, initial_width_cells, floor_cells, lanes, groups, areas, aisles, props, service]
	)
