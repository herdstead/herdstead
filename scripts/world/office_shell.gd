class_name OfficeShell
extends RefCounted
## Where a map's shell meets its walls and its zones: the lift door, the
## windows and the framed pictures on the top wall, the entry band's rows, the
## zones' low partitions and the posts their signs hang from, and where the
## standing furniture of the top-wall run and the lane gaps stands.
## Furniture, never a signal (see docs/VISUAL_LANGUAGE.md): every number here is
## a place on a wall or on the floor, and none of them reads herdr.
##
## The planner, the decor planner, the floor view and the showroom all read
## these, so the shell a map is planned with is the shell it is drawn with.

## Where the top wall's pieces meet it, measured from the map's top. The wall
## is two 32-unit courses, its painted face runs from y 12 to y 56; the window
## is centred on that face, and the lift door comes down onto the floor in
## front of it.
const WINDOW_FOOT := 56.0
const DOOR_FOOT := 84.0
## How far a window keeps from the lift door (see door()), and how far apart the
## evenly spaced windows are.
const WINDOW_CLEARANCE := 64.0
const WINDOW_SPACING := 128.0
## The top-wall run: plants at the top wall's foot (their foot TOP_RUN_FOOT
## down, in the entry band's first row, the wall's drawing clearance), on a
## grid of the wall itself: TOP_RUN_PITCH apart from TOP_RUN_FROM (a cell and
## 40 in from the left wall), keyed by the step, never placed by anything the
## map holds. A step whose plant would come within WALL_RUN_GAP of the lift
## door, a window, a picture or the pantry counter stands empty.
const TOP_RUN_FROM := 72.0
const TOP_RUN_FOOT := 76.0
const TOP_RUN_PITCH := 160.0
const WALL_RUN_GAP := 8.0
## Lane gaps: a run of at least LANE_GAP_MIN_CELLS free cell rows inside a lane
## stands a piece every LANE_GAP_STEP_CELLS rows from its second row, in the
## lane's middle column, its foot LANE_GAP_FOOT above the bottom of its row.
const LANE_GAP_MIN_CELLS := 3
const LANE_GAP_STEP_CELLS := 2
const LANE_GAP_FOOT := 8.0
## Framed pictures on the top wall: furnishing hung between the windows, never
## a signal. A picture hangs centred in every second gap between two windows
## (the second, the fourth, ...), so the run reads window, gap, window,
## picture; placed by the windows alone, never by the zones, so no count or
## place of them follows a workspace. A picture that, grown by FRAME_GAP, would
## meet a window, the lift door, the pantry counter or the wall's end cells is
## not hung. FRAME_FOOT hangs it on the wall's cream face (y 12..57).
const FRAME_FOOT := 48.0
const FRAME_GAP := 8.0

## The entry band, measured from its top. Its first cell row is inside the top
## wall's drawing clearance (a person's whole canvas stays off the wall), the
## second is the fixture row, where the pantry's people stand, and the third is
## the walking lane everyone steps up into it from: the centres of those two rows.
const FIXTURE_ROW := 48.0
const WALKING_LANE := 80.0
## Where the pantry counter meets the floor, under the top wall: its footprint
## ends 6 units short of the fixture row, which a person's feet (4 deep) keep clear of.
const COUNTER_FOOT := 42.0
## How far apart the pantry's people stand: a wait label 40 wide over the
## badge and 8 between neighbours, 48.
const SPOT_PITCH := 48.0
const MAX_PANTRY := 24
## Between the pantry's last spot and the main corridor, at the least.
const FIXTURE_GAP := 16.0

## A zone's low partitions: bands PARTITION_THICKNESS thick inside its left,
## right and bottom edges (ZonePlacement.partitions()), drawn no taller than
## PARTITION_DRAW above their foot (partition_h, partition_corner_*), and a
## post at each open top corner whose foot is POST_FOOT below the zone's top:
## where the art's post covers the side run's top end (the art lane's mock,
## docs/WORLD_MODEL.md). The zone's sign hangs from the left post.
const PARTITION_THICKNESS := 6.0
const PARTITION_DRAW := 10.0
const POST_FOOT := 6.0


## One partition piece: the prop drawn and where its foot stands, in map units.
class Piece:
	extends RefCounted
	var id: StringName
	var foot: Vector2

	func _init(piece: StringName, at: Vector2) -> void:
		id = piece
		foot = at


## Where the lift door meets the floor: on the top wall, over the left lane of
## the main corridor, so whoever comes in walks straight down the corridor and
## along the walking lane to their lane, and whoever leaves walks straight up
## it. Its x is a cell centre: the threshold leg runs straight down from its
## foot (OfficeWalkGraph). Windows keep WINDOW_CLEARANCE from it. The door
## moves with the main corridor when the map widens.
static func door(plan: FloorPlan) -> Vector2:
	return Vector2((plan.main_corridor_cells.position.x + 0.5) * FloorLayoutPolicy.GRID, DOOR_FOOT)


## Where the top wall's windows are centred, left to right, WINDOW_SPACING
## apart. On a map with a pantry the run is centred in the free stretch of the
## top wall between the pantry's drawing and WINDOW_CLEARANCE short of the
## door: as many as fit there, the same gap at both ends. A map without one (an
## empty map, an empty workspace) keeps the run it always had: from 64 on, off the
## side walls and WINDOW_CLEARANCE from the door. Pure: the floor view draws
## exactly these, and the tests read them.
static func window_xs(plan: FloorPlan, pen: OfficeDraw) -> Array[float]:
	var found: Array[float] = []
	var grid := float(FloorLayoutPolicy.GRID)
	var width := float(plan.floor_cells.size.x) * grid
	var door_x := door(plan).x
	var window := pen.art.prop_sprite(ArtContract.PROP_WINDOW)
	if plan.pantry == null:
		for step in int(width / WINDOW_SPACING):
			var at := WINDOW_SPACING * (step + 0.5)
			if at >= grid * 2 and at <= width - grid * 2 and absf(at - door_x) >= WINDOW_CLEARANCE:
				found.append(at)
		return found
	# The free stretch, as the window's left edge may use it: off the pantry,
	# and short of the door's clearance.
	var from := plan.pantry.draw_rect.end.x
	var to := door_x - WINDOW_CLEARANCE + window.size.x - window.pivot.x
	var span := to - from
	if span < window.size.x:
		return found
	var count := floori((span - window.size.x) / WINDOW_SPACING) + 1
	var run := (count - 1) * WINDOW_SPACING + window.size.x
	var first := from + floorf((span - run) / 2.0) + window.pivot.x
	for index in count:
		found.append(first + index * WINDOW_SPACING)
	return found


## Where the top wall's framed pictures hang, left to right: the foot of each,
## FRAME_FOOT below the map's top, centred in every second gap between two
## neighbouring windows (window_xs()), where the picture, grown by FRAME_GAP,
## stays off the wall's two end cells and clear of every window, the lift door
## and the pantry counter. Reads the plan's geometry and the pack's sprite
## sizes only: never herdr. Pure: the floor view draws exactly these, and the
## tests read them.
static func frames(plan: FloorPlan, pen: OfficeDraw) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var picture := pen.art.prop_sprite(ArtContract.PROP_WALL_FRAME)
	if picture == null:
		return found
	var grid := float(FloorLayoutPolicy.GRID)
	var from := grid
	var to := float(plan.floor_cells.size.x - 1) * grid
	var covers := wall_covers(plan, pen)
	var windows := window_xs(plan, pen)
	var size := Vector2(picture.size)
	for gap in range(1, windows.size() - 1, 2):
		var at := Vector2((windows[gap] + windows[gap + 1]) / 2.0, FRAME_FOOT)
		var near := Rect2(at - picture.pivot, size).grow(FRAME_GAP)
		var clear := near.position.x >= from and near.end.x <= to
		for cover in covers:
			clear = clear and not near.intersects(cover)
		if clear:
			found.append(at)
	return found


## What stands on or against the top wall before any picture or plant: the
## lift door's drawing, every window's and the pantry counter's.
static func wall_covers(plan: FloorPlan, pen: OfficeDraw) -> Array[Rect2]:
	var covers: Array[Rect2] = [drawn(pen, ArtContract.PROP_DOOR, door(plan))]
	for x in window_xs(plan, pen):
		covers.append(drawn(pen, ArtContract.PROP_WINDOW, Vector2(x, WINDOW_FOOT)))
	for fixture in plan.fixtures():
		covers.append(fixture.draw_rect)
	return covers


## Where prop `id` draws with its foot at `at`.
static func drawn(pen: OfficeDraw, id: StringName, at: Vector2) -> Rect2:
	var sprite := pen.art.prop_sprite(id)
	return Rect2(at - sprite.pivot, Vector2(sprite.size))


## The foot of `zone`'s top-right post (the zone sign stops short of its drawing).
static func right_post(zone: ZonePlacement) -> Vector2:
	var area := zone.bounds()
	return Vector2(area.end.x - PARTITION_THICKNESS / 2.0, area.position.y + POST_FOOT)


## Every partition piece of `zone`, in map units, in the order the floor view
## makes them: the side runs row by row (partition_v, the left then the right,
## every cell row but the last), the posts, the bottom corners and the bottom
## run between them (partition_h at each cell centre). Drawn only: the walk
## graph's partitions (ZonePlacement.partitions()) are the obstacle.
static func partition_pieces(zone: ZonePlacement) -> Array[Piece]:
	var found: Array[Piece] = []
	var area := zone.bounds()
	var grid := float(FloorLayoutPolicy.GRID)
	var left := area.position.x + PARTITION_THICKNESS / 2.0
	var right := area.end.x - PARTITION_THICKNESS / 2.0
	for row in zone.cells.size.y - 1:
		var foot := area.position.y + (row + 1) * grid
		found.append(Piece.new(ArtContract.PROP_PARTITION_V, Vector2(left, foot)))
		found.append(Piece.new(ArtContract.PROP_PARTITION_V, Vector2(right, foot)))
	found.append(Piece.new(ArtContract.PROP_PARTITION_POST, Vector2(left, area.position.y + POST_FOOT)))
	found.append(Piece.new(ArtContract.PROP_PARTITION_POST, right_post(zone)))
	found.append(Piece.new(ArtContract.PROP_PARTITION_CORNER_BL, Vector2(area.position.x + grid / 2.0, area.end.y)))
	for cell in range(1, zone.cells.size.x - 1):
		found.append(
			Piece.new(ArtContract.PROP_PARTITION_H, Vector2(area.position.x + (cell + 0.5) * grid, area.end.y))
		)
	found.append(Piece.new(ArtContract.PROP_PARTITION_CORNER_BR, Vector2(area.end.x - grid / 2.0, area.end.y)))
	return found
