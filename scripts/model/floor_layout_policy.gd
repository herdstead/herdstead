class_name FloorLayoutPolicy
extends RefCounted
## Bounds are in 32-unit cells; all table geometry remains in OfficeTable.
##
## The map (OfficeFloorLayout): the top wall (wall_cells), the entry band
## (entry_cells: one row, the walking lane, which is also the first zones'
## aisle row), then the zones in lanes, the main corridor on the right and
## a side wall at each end. Across: a side wall, `lanes` lanes of
## zone_width_cells with an aisle column (lane_aisle_cells) between two of
## them, the main corridor and the other side wall; 5L + 3 cells for L lanes
## at the shipped values. A lane holds the narrowest pod (2 columns, 3 cells)
## right of its zone's pad. A zone stands in one or more adjacent lanes, one
## aisle row (zone_aisle_cells) above it, and is 5k - 1 cells wide for k lanes:
## the aisle columns between its lanes are its own. A new zone takes as many
## lanes as its pods need to stand in one row (zone_tall_rows). Its pod rows
## are as deep as a table's measured reservation
## (OfficeZoneLayout.pod_row_cells()).

const GRID := 32
## A map with at most this many occupied seats (agents and shells: every pane
## on it, MapModel.pane_count()) shows every seat's name plate at all times;
## above it, a plate shows only while its seat is hovered or selected or the
## lens is held (OfficeFloorView.few_seats(), S3 SEATTAGS, the user's Q-U2):
## thirty-unit plates over fifty seats crowd each other and the chips. 16,
## not the first 12 (S3 SEATTAGS round 2): B2 tags every seat of a 14-pane map,
## and the floors fixture's 13 seats read clear with every plate shown. What
## the map shows, not where anything stands, so it is in no plan's signature.
const FEW_SEATS := 16
var version := 5
var width_cells := 32
var wall_cells := 2
## One: the walking lane (OfficeShell.WALKING_LANE), right under the top wall;
## the pantry counter stands at the band's left end against the wall, and
## nobody stands at it. D2 (2026-10-27): idle sits with a mug; the pantry is a
## nook nobody walks to, so its fixture row went with its people (SEATED-Q2).
## S3 BAND (2026-10-28): the top wall draws behind a person in front of it, so
## its drawing clearance row went too (a walker's canvas reaches over its face;
## OfficeWalkGraph), and the map opens with the wall and the first pod row whole.
var entry_cells := 1
var main_corridor_cells := 2
var outer_side_cells := 1
## One lane of zones, the partition's pad inside a zone's left edge, and the
## aisle column between two lanes. Four: a pod of c columns reserves c + 1
## cells (OfficeTable.measure()), so the narrowest (2 columns) and the pad.
var zone_width_cells := 4
var zone_pad_left_cells := 1
var lane_aisle_cells := 1
## The aisle row above each zone, where its sign hangs. The first zones' aisle
## row is the entry band's walking lane (S3 BAND: map_top_aisle_cells 0, zones
## from row 3, their signs over the lane; the row was a top aisle of its own).
var zone_aisle_cells := 1
var map_top_aisle_cells := 0
## A new zone takes more lanes, up to the map's, rather than stand taller than
## this many pod rows (never fewer lanes than its widest table needs).
var zone_tall_rows := 1
var min_height_cells := 9
var max_width_cells := 512
var max_height_cells := 1024
var max_floor_cells := 131072
## Input limits bound the work of resolving identities and seat hints.
var max_panes := 4096
var max_tables := 1024
## Separate, cumulative Node upper bound for live desk groups, including empty
## historical columns. OfficeDeskView.node_budget owns the prefab accounting.
## 32768 bounds roughly 920 fully furnished seats, or 195 minimum-size pods;
## this is an allocation ceiling, not a frame-time or memory guarantee. It is
## charged on the whole map, every zone's tables together.
## Floor tiles, shell and optional decor remain bounded by the grid limits.
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
			wall_cells,
			entry_cells,
			main_corridor_cells,
			outer_side_cells,
			zone_width_cells,
			zone_pad_left_cells,
			lane_aisle_cells,
			zone_aisle_cells,
			map_top_aisle_cells,
			zone_tall_rows,
			min_height_cells,
			actor_footprint,
			actor_draw_rect
		]
	)


func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if version < 1 or width_cells < 1 or outer_side_cells < 1:
		found.append("invalid layout version, width or outer wall band")
	if wall_cells < 2 or entry_cells < 1 or main_corridor_cells < 2:
		found.append("wall and corridor bands must be at least two cells, the entry band one")
	if zone_width_cells <= zone_pad_left_cells or zone_pad_left_cells < 1 or lane_aisle_cells < 1:
		found.append("a lane cannot contain its zone's pad and an aisle")
	if zone_aisle_cells < 1 or map_top_aisle_cells < 0 or zone_tall_rows < 1:
		found.append("zone aisles and height preference must be positive")
	if entry_cells + map_top_aisle_cells < zone_aisle_cells:
		found.append("the first zones' aisle row must fit under the wall")
	if min_height_cells < wall_cells + entry_cells:
		found.append("row or minimum floor height cannot contain its bands")
	if max_width_cells < 1 or max_width_cells > 32767 or max_height_cells < 1 or max_height_cells > 32767:
		found.append("floor dimensions exceed supported TileMap coordinates")
	if max_floor_cells < 1 or max_panes < 1 or max_tables < 1 or max_desk_nodes < 1:
		found.append("floor, input and desk node budgets must be positive")
	for bounds: Rect2 in [actor_footprint, actor_draw_rect]:
		if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x < 0 or bounds.size.y < 0:
			found.append("invalid actor measurement")
	return found


## One lane and the aisle column after it: 5 cells.
func lane_pitch() -> int:
	return zone_width_cells + lane_aisle_cells


## The first cell column of lane `lane` (0 is the leftmost).
func lane_x(lane: int) -> int:
	return outer_side_cells + lane * lane_pitch()


## The lane whose first column is `column`; the lane a column lies in otherwise.
func lane_of(column: int) -> int:
	return floori(float(column - outer_side_cells) / lane_pitch())


## A zone `lanes` lanes wide, in cells: 5k - 1.
func zone_width(lanes: int) -> int:
	return lanes * lane_pitch() - lane_aisle_cells


## The fewest lanes (at least one) a zone `width` cells wide needs.
func lanes_for_width(width: int) -> int:
	return maxi(1, ceili(float(width + lane_aisle_cells) / lane_pitch()))


## The fewest lanes (at least one) whose zone holds a table `width` cells wide
## right of its pad: for a pod of c columns, ceil((c + 3) / 5).
func lanes_for_inner(width: int) -> int:
	return lanes_for_width(width + zone_pad_left_cells)


## A map of `lanes` lanes, in cells: 5L + 3.
func map_width(lanes: int) -> int:
	return 2 * outer_side_cells + zone_width(lanes) + main_corridor_cells


## How many lanes a first plan `width` cells wide gets: as many as fit, at least
## two. Z1 (2026-10-27): the narrowest plan stays two lanes, so the smallest
## window keeps a window and a picture; FRAME-Q2.
func lanes_for(width: int) -> int:
	return maxi(2, floori(float(width - 2 * outer_side_cells - main_corridor_cells + lane_aisle_cells) / lane_pitch()))


## The widest zone the width budget allows.
func max_zone_width_cells() -> int:
	return zone_width(lanes_for(max_width_cells))


## The first cell row a zone may start at: under the entry band and the top
## aisle (none: the first zones' aisle row is the band's walking lane).
func zones_top_cells() -> int:
	return wall_cells + entry_cells + map_top_aisle_cells
