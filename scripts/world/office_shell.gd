class_name OfficeShell
extends RefCounted
## Where a floor's shell meets its walls: the lift door and the windows on the
## outer wall, a tab's sign and its lettering on a row wall, the framed pictures
## hung between the signs, and the standing furniture of a row: its plant, its
## cabinet, the wall-foot run between them and the plant of a spare bay.
## Furniture, never a signal (see docs/VISUAL_LANGUAGE.md): every number here is
## a place on a wall, and none of them reads herdr.
##
## The planner, the decor planner, the floor and desk views and the showroom all
## read these, so the shell a floor is planned with is the shell it is drawn with.

## Where the shell's furniture meets the wall, measured from the top of its
## row. The wall is two 32-unit courses, its painted face runs from y 12 to
## y 56, and the sign, the title and the window are centred on that face; the
## lift door and the two standing pieces come down onto the floor in front of it.
const SIGN_FOOT := 44.0
const TITLE_TOP := 24.0
const WINDOW_FOOT := 56.0
const DOOR_FOOT := 84.0
## The two standing pieces keep to the strip between the wall's foot and the
## rug, which is also above the top bar of a table's selection frame, so
## selecting a table never draws a line across a cabinet.
const CABINET_FOOT := 80.0
const PLANT_FOOT := 76.0
## How far a window keeps from the lift door (see door()), and how far apart the
## evenly spaced windows are.
const WINDOW_CLEARANCE := 64.0
const WINDOW_SPACING := 128.0
## How far each standing piece keeps from the end of its row.
const DECOR_FROM_END := 40.0
## The wall-foot run: more plants on the strip under a row wall, between
## its plant and its cabinet, on a grid of the wall itself: WALL_RUN_PITCH
## apart from the row's first plant (DECOR_FROM_END off the left wall), never
## placed by the tables, so no count or place of them follows a tab. A place on
## the grid whose plant would come within WALL_RUN_GAP of a sign, its title or
## another piece stands empty.
const WALL_RUN_PITCH := 160.0
const WALL_RUN_GAP := 8.0
## The spare bay: where a row's last table ends at least SPARE_BAY_CELLS
## short of the main corridor, one plant stands in the middle of the gap, its
## foot level with the tables' near edge (BAY_PLANT_FOOT from the row's top),
## on a cell centre, so a full free cell column stays on each side of it.
const SPARE_BAY_CELLS := 3
const BAY_PLANT_FOOT := 256.0
## Framed pictures on the row walls: furnishing hung on a row's back wall
## beside its signs, never a signal. They hang on a grid of the wall itself,
## never placed by the tables, so no count or place of them follows a tab. The
## wall is cut into bays FRAME_PITCH wide from FRAME_FROM, the middle of the
## second gap of the wall-foot run (the left wall's cell, DECOR_FROM_END, one
## and a half WALL_RUN_PITCH); each bay has two places, its start and the next
## gap of the run (FRAME_SECOND on), and hangs at most one picture, at the first
## of them that is clear. So a picture hangs in a gap between the run's plants,
## never more than one to a bay, and a sign that moves only moves its own bay's
## picture. The first gap of the run is no place: every row's first table starts
## at the side passage, and its sign hangs over that gap on every floor. A place
## is clear when its picture, grown by FRAME_GAP, stays off the row wall's end
## cells and away from every sign, title, table and standing piece (the cabinet
## and the plants reach up the wall). FRAME_FOOT hangs the picture's foot so its
## opaque rows (T+19..T+48) share the sign's band (T+24.5..T+42) to within a
## unit of its middle, on the wall's cream face (T+12..T+57).
const FRAME_FROM := 312.0
const FRAME_PITCH := 320.0
const FRAME_SECOND := WALL_RUN_PITCH
const FRAME_FOOT := 48.0
const FRAME_GAP := 8.0

## The entry band's two service fixtures (OfficeFixturePlanner), measured from
## the top of the band. Its first cell row is inside the top wall's drawing
## clearance (a person's whole canvas stays off the wall), the second is the
## fixture row, where the queue and the pantry stand, and the third is the
## walking lane everyone steps up into them from: the centres of those two rows.
const FIXTURE_ROW := 48.0
const WALKING_LANE := 80.0
## Where both counters meet the floor, under the top wall: their footprint ends
## 6 units short of the fixture row, which a person's feet (4 deep) keep clear of.
const COUNTER_FOOT := 42.0
## How far the reception counter keeps left of the main corridor: the 48-wide
## lift door, centred over the corridor's left lane (door()), reaches 8 units
## into the bay, and 8 more keep the counter off its frame.
const DOOR_CLEARANCE := 16.0
## How far apart the people of the pantry (and the reception's unused slots)
## stand: a wait label 40 wide over the badge and 8 between neighbours, 48.
## Nobody queues at the reception; the pitch stays so no floor is laid out
## differently.
const SPOT_PITCH := 48.0
## A band that cannot hold the reception counter, the door's clearance and this
## many slots has neither fixture; no queue is longer than MAX_QUEUE.
const MIN_QUEUE := 2
const MAX_QUEUE := 24
const MAX_PANTRY := 24
## Between the pantry's last spot and the queue's tail, at the least: the two
## are told apart by where they stand.
const FIXTURE_GAP := 16.0


## Where the lift door meets the floor: on the outer wall, over the left lane of
## the main corridor, so whoever comes in walks straight down the corridor to
## their row and whoever leaves walks straight up it (routes from a door at the
## top-left ran right, down and back left, 800 to 2016 units). Its x is a cell
## centre: the threshold leg runs straight down from its foot (OfficeWalkGraph).
## Windows keep WINDOW_CLEARANCE from it.
static func door(plan: FloorPlan) -> Vector2:
	return Vector2((plan.main_corridor_cells.position.x + 0.5) * FloorLayoutPolicy.GRID, DOOR_FOOT)


## Where the outer wall's windows are centred, left to right, WINDOW_SPACING
## apart. On a floor with counters the run is centred in the free stretch of
## the top wall between the pantry's drawing and the reception's (the door is
## right of the reception): as many as fit there, the same gap at both ends. A
## floor without counters (a lobby, an empty workspace) keeps the run it always
## had: from 64 on, off the side walls and WINDOW_CLEARANCE from the door. Pure:
## the floor view draws exactly these, and the tests read them.
static func window_xs(plan: FloorPlan, pen: OfficeDraw) -> Array[float]:
	var found: Array[float] = []
	var grid := float(FloorLayoutPolicy.GRID)
	var width := float(plan.floor_cells.size.x) * grid
	var door_x := door(plan).x
	var window := pen.art.prop_sprite(ArtContract.PROP_WINDOW)
	if plan.reception == null:
		for step in int(width / WINDOW_SPACING):
			var at := WINDOW_SPACING * (step + 0.5)
			if at >= grid * 2 and at <= width - grid * 2 and absf(at - door_x) >= WINDOW_CLEARANCE:
				found.append(at)
		return found
	# The free stretch, as the window's left edge may use it: off the side wall
	# or the pantry, and short of the reception and the door's clearance.
	var from := grid if plan.pantry == null else plan.pantry.draw_rect.end.x
	var to := minf(plan.reception.draw_rect.position.x, door_x - WINDOW_CLEARANCE + window.size.x - window.pivot.x)
	var span := to - from
	if span < window.size.x:
		return found
	var count := floori((span - window.size.x) / WINDOW_SPACING) + 1
	var run := (count - 1) * WINDOW_SPACING + window.size.x
	var first := from + floorf((span - run) / 2.0) + window.pivot.x
	for index in count:
		found.append(first + index * WINDOW_SPACING)
	return found


## Where every row wall's framed pictures hang, row by row and left to right:
## the foot of each (frame_xs() at FRAME_FOOT below the row's top). Pure: the
## floor view draws exactly these, and the tests read them.
static func frames(plan: FloorPlan, pen: OfficeDraw) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for row in plan.rows:
		var foot := float(row.wall_cells.position.y * FloorLayoutPolicy.GRID) + FRAME_FOOT
		for x in frame_xs(plan, row, pen):
			found.append(Vector2(x, foot))
	return found


## Where `row`'s framed pictures are centred, left to right: in each bay of the
## wall's own grid (FRAME_FROM, then every FRAME_PITCH), its start or, when that
## is taken, the place FRAME_SECOND on, whichever first has a picture that,
## grown by FRAME_GAP, stays off the row wall's two end cells and clear of every
## sign and title of the row, every table's drawing and every standing piece and
## counter the plan has; a bay with neither stays bare.
## Reads the plan's geometry and the pack's sprite sizes only: never herdr.
static func frame_xs(plan: FloorPlan, row: RowPlan, pen: OfficeDraw) -> Array[float]:
	var found: Array[float] = []
	var picture := pen.art.prop_sprite(ArtContract.PROP_WALL_FRAME)
	if picture == null:
		return found
	var grid := float(FloorLayoutPolicy.GRID)
	var wall_y := float(row.wall_cells.position.y) * grid
	# The run of plain wall between the tee at the left wall and the end at the
	# main corridor: the end cells are corners, not a wall to hang on.
	var from := float(row.wall_cells.position.x + 1) * grid
	var to := float(row.wall_cells.end.x - 1) * grid
	var covers: Array[Rect2] = []
	for desk in row.desks:
		covers.append(wall_display_bounds(desk, wall_y, pen))
		var drawing := desk.measure.render_rect
		drawing.position += desk.origin
		covers.append(drawing)
	for placed in plan.decorations:
		covers.append(placed.draw_rect)
	for fixture in plan.fixtures():
		covers.append(fixture.draw_rect)
	var size := Vector2(picture.size)
	var bay := FRAME_FROM
	while bay - picture.pivot.x < to:
		for at: float in [bay, bay + FRAME_SECOND]:
			var near := Rect2(Vector2(at, wall_y + FRAME_FOOT) - picture.pivot, size).grow(FRAME_GAP)
			var clear := near.position.x >= from and near.end.x <= to
			for cover in covers:
				clear = clear and not near.intersects(cover)
			if clear:
				found.append(at)
				break
		bay += FRAME_PITCH
	return found


## Where a tab's title is lettered on its row wall, centred over its table and
## never wider than the sign it is painted on. `wall_y` is the top of the row wall.
static func title_bounds(placed: DeskPlacement, wall_y: float, pen: OfficeDraw) -> Rect2:
	var sign_spec := pen.art.prop_sprite(ArtContract.PROP_SIGN)
	var width := minf(placed.measure.table_width - 16.0, sign_spec.size.x - 12.0)
	var middle := placed.origin.x + placed.measure.table_width / 2.0
	return Rect2(
		Vector2(middle - width / 2.0, wall_y + TITLE_TOP), Vector2(width, maxf(18.0, ceilf(pen.font.get_height(12))))
	)


## Wall lettering and its sign are part of the visible desk group too: what no
## standing piece may cover.
static func wall_display_bounds(placed: DeskPlacement, wall_y: float, pen: OfficeDraw) -> Rect2:
	var sign_spec := pen.art.prop_sprite(ArtContract.PROP_SIGN)
	var at := Vector2(placed.origin.x + placed.measure.table_width / 2.0, wall_y + SIGN_FOOT)
	return title_bounds(placed, wall_y, pen).merge(Rect2(at - sign_spec.pivot, Vector2(sign_spec.size)))
