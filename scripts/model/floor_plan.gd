class_name FloorPlan
extends RefCounted
## A validated layout snapshot. Planners never mutate the previous snapshot.

var floor_key := ""
var policy_signature := ""
var initial_width_cells := 0
var floor_cells := Rect2i()
var rows: Array[RowPlan] = []
## The zones laid out on this plan. For now there is exactly one, and its rows
## are `rows` (see ZonePlacement).
var zones: Array[ZonePlacement] = []
var desks: Array[DeskPlacement] = []
var decorations: Array[DecorPlacement] = []
var corridors: Array[Rect2i] = []
var entry_cells := Rect2i()
var main_corridor_cells := Rect2i()
var render_bounds := Rect2()
## The service fixtures in the entry band (OfficeFixturePlanner): the reception
## counter with its (unused) queue slots, and the pantry. Null where the floor has none: the
## lobby, an empty workspace, a band too narrow (see docs/VISUAL_LANGUAGE.md).
var reception: FixturePlacement
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


## The fixtures this floor has, reception first.
func fixtures() -> Array[FixturePlacement]:
	var found: Array[FixturePlacement] = []
	for fixture: FixturePlacement in [reception, pantry]:
		if fixture != null:
			found.append(fixture)
	return found


func geometry_signature() -> String:
	var groups := PackedStringArray()
	for placed in desks:
		groups.append(placed.geometry_signature())
	groups.sort()
	var bands := PackedStringArray()
	for band in rows:
		bands.append(JSON.stringify([band.index, band.band_cells, band.exclusive_tab_key]))
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
		[floor_key, policy_signature, initial_width_cells, floor_cells, groups, bands, props, service, areas]
	)
