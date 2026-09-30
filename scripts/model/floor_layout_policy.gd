class_name FloorLayoutPolicy
extends RefCounted
## Bounds are in 32-unit cells; all table geometry remains in OfficeTable.

const GRID := 32
var version := 1
var width_cells := 32
## A row: its wall (wall_cells), one pod's reservation (OfficeTable.measure(),
## 6 cells) and the cross corridor below it (cross_corridor_cells).
var row_height_cells := 10
var wall_cells := 2
## Three: the top wall's drawing clearance takes the first row, the fixture row
## (queue and pantry spots, OfficeFixturePlanner) the second, the walking lane the third.
var entry_cells := 3
var main_corridor_cells := 2
var cross_corridor_cells := 2
var outer_side_cells := 1
var min_height_cells := 12
var max_width_cells := 512
var max_height_cells := 1024
var max_floor_cells := 131072
## Input limits bound the work of resolving identities and seat hints.
var max_panes := 4096
var max_tables := 1024
## Separate, cumulative Node upper bound for live desk groups, including empty
## historical columns. OfficeDeskView.node_budget owns the prefab accounting.
## 32768 bounds roughly 920 fully furnished seats, or 195 minimum-size pods;
## this is an allocation ceiling, not a frame-time or memory guarantee.
## Floor tiles, shell and optional row decor remain bounded by the grid limits.
var max_desk_nodes := 32768
## Supply production measurements for body/visual clearance. Empty rectangles
## deliberately request point reachability only (useful for geometry tools).
var actor_footprint := Rect2()
var actor_draw_rect := Rect2()


## Width is selected only for the first plan. Viewport changes cannot reflow it.
func geometry_signature() -> String:
	return JSON.stringify(
		[
			version,
			GRID,
			row_height_cells,
			wall_cells,
			entry_cells,
			main_corridor_cells,
			cross_corridor_cells,
			outer_side_cells,
			min_height_cells,
			actor_footprint,
			actor_draw_rect
		]
	)


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if version < 1 or width_cells < 1 or outer_side_cells < 1:
		found.append("invalid layout version, width or outer wall band")
	if wall_cells < 2 or entry_cells < 2 or main_corridor_cells < 2 or cross_corridor_cells < 2:
		found.append("wall and corridor bands must be at least two cells")
	if row_height_cells <= wall_cells + cross_corridor_cells or min_height_cells < wall_cells + entry_cells:
		found.append("row or minimum floor height cannot contain its bands")
	if max_width_cells < 1 or max_width_cells > 32767 or max_height_cells < 1 or max_height_cells > 32767:
		found.append("floor dimensions exceed supported TileMap coordinates")
	if max_floor_cells < 1 or max_panes < 1 or max_tables < 1 or max_desk_nodes < 1:
		found.append("floor, input and desk node budgets must be positive")
	for bounds: Rect2 in [actor_footprint, actor_draw_rect]:
		if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 0 or bounds.size.y < 0:
			found.append("invalid actor measurement")
	return found
