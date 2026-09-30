class_name ZonePlacement
extends RefCounted
## Where one zone (a workspace) stands on its map (FloorPlan.zones), in map
## cells: `lanes` adjacent lanes from `first_lane`, under an aisle row of its
## own, its pod rows one under another. Low partitions stand inside its left,
## right and bottom edges (partitions()); its top is open, with a post at each
## corner, and its sign hangs from the left post over the aisle row.

## ZoneModel.key of the zone placed.
var zone_key := ""
## The zone's rectangle, its pod rows' bands together, without the aisle row.
var cells := Rect2i()
## How deep the aisle row above it is (FloorLayoutPolicy.zone_aisle_cells).
var aisle_cells := 1
## The first lane it stands in, and how many lanes it spans.
var first_lane := 0
var lanes := 1
## Its pod rows, top to bottom (RowPlan.index), each band in map cells.
var rows: Array[RowPlan] = []
## The zone's width in cells when it was first laid out: a table wider than
## that (less the pad) owns a row of its own (OfficeZoneLayout).
var initial_width_cells := 0
## Where its sign hangs, in map units: the foot of the top-left post.
var sign_at := Vector2.ZERO


## What the zone holds on the map: its aisle row and its rectangle.
func slot() -> Rect2i:
	return Rect2i(cells.position.x, cells.position.y - aisle_cells, cells.size.x, cells.size.y + aisle_cells)


## The zone's rectangle in map units.
func bounds() -> Rect2:
	return Rect2(cells.position * FloorLayoutPolicy.GRID, cells.size * FloorLayoutPolicy.GRID)


## The partitions' three bands in map units, OfficeShell.PARTITION_THICKNESS
## thick inside the zone's edges: left and right the zone's whole height, the
## bottom its whole width. What the walk graph stops the feet at.
func partitions() -> Array[Rect2]:
	var area := bounds()
	var thick := OfficeShell.PARTITION_THICKNESS
	return [
		Rect2(area.position, Vector2(thick, area.size.y)),
		Rect2(area.end.x - thick, area.position.y, thick, area.size.y),
		Rect2(area.position.x, area.end.y - thick, area.size.x, thick),
	]


## The zone's footprint on the map. Its rows add only their bands: the desks in
## them have signatures of their own (FloorPlan.geometry_signature()).
func geometry_signature() -> String:
	var bands := PackedStringArray()
	for row in rows:
		bands.append(JSON.stringify([row.index, row.band_cells, row.exclusive_tab_key]))
	return JSON.stringify([zone_key, cells, aisle_cells, first_lane, lanes, initial_width_cells, sign_at, bands])
