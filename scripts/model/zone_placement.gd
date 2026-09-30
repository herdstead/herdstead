class_name ZonePlacement
extends RefCounted
## Where one zone of a map lies on its plan (FloorPlan.zones), in grid cells.
##
## For now a plan holds exactly one zone: the whole floor below its entry band.
## Its rows are the plan's own rows (FloorPlan.rows, the same objects), it spans
## one lane from the first, and nothing draws its sign yet.

## ZoneModel.key of the zone placed.
var zone_key := ""
## The zone's rectangle: its rows' bands together; an empty rectangle where the
## rows start when it has none.
var cells := Rect2i()
## The first lane it stands in, and how many lanes it spans.
var first_lane := 0
var lanes := 1
## Its rows of desks, top to bottom (RowPlan.index).
var rows: Array[RowPlan] = []
## The width in cells the zone was first planned at.
var initial_width_cells := 0
## Where its sign hangs, in map units: the zone's top-left corner.
var sign_at := Vector2.ZERO


## The zone's footprint on the map. Its rows add only their bands: the desks in
## them have signatures of their own (FloorPlan.geometry_signature()).
func geometry_signature() -> String:
	var bands := PackedStringArray()
	for row in rows:
		bands.append(JSON.stringify([row.index, row.band_cells]))
	return JSON.stringify([zone_key, cells, first_lane, lanes, initial_width_cells, sign_at, bands])
