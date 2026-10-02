class_name OfficeWalkGraph
extends RefCounted
## Where a person can walk on one FloorPlan: the one graph the layout validator
## checks a floor with and the office's people walk it by
## (OfficeFloorValidation, OfficePresentation).
##
## Nodes are cell centres, 32 units apart at (16, 16) offsets; edges join
## 4-neighbours. A node is blocked when its centre lies inside an obstacle and
## an edge when its segment enters one, where every obstacle is inflated by the
## real person: furniture and walls by the feet (PixelPerson.footprint()), the
## Ground walls also by the whole drawing (PixelPerson.drawing_rect()), because
## a wall always draws behind whoever walks in front of it. A segment that only
## touches an obstacle's edge passes (Rect2.intersects() leaves the edges out).
## Checking edges, not only nodes, is what keeps a thin obstacle between two
## clear centres from being walked through: the native AStarGrid2D connects
## those, even with its points moved to the centres (docs/WORLD_MODEL.md, "Collision and walking").
## Every edge costs the same, so a breadth-first search finds the shortest
## routes; a route is read off a search greedily, straight on wherever that is
## still a shortest way, so nobody zigzags down a corridor.
##
## Everyone comes in and goes out by the lift door (OfficeShell.door()). Its
## foot stands inside the wall's drawing clearance, so it is joined to the
## graph by one fixed threshold leg straight down to the first walkable cell
## centre below it; the seat and standing legs join a table's approach point to
## where its worker sits or stands (see leg_to_seat() and leg_to_standing()).
## Those legs are the only way into an obstacle: every obstacle carries the
## exact segments that may enter it (its entries: a table the far seat legs that
## run into its footprint, the top wall's drawing clearance the threshold leg,
## the entry band's fixture row the legs up to the pantry's spots), and a check
## lets a segment into an obstacle only along one of them, at that obstacle's
## place in this plan. Nothing is exempt by name.
##
## The fixture row (OfficeShell.FIXTURE_ROW) is where the pantry's people
## stand, not a way anywhere: on every map with desks, pantry or not, it is an
## obstacle from the left wall to the main corridor, so no route runs along it
## and every way in from the door crosses the walking lane at the door's
## column (to_lane(), from_lane()). People step up into it from the walking
## lane below (leg_to_fixture()), only at the pantry's spots.
##
## A zone's low partitions (ZonePlacement.partitions()) are obstacles of their
## own kind, inflated by the feet only: they draw no taller than a person, so
## the drawing rule the walls have does not apply. They block the edges across
## them and no node: the pad column inside a zone's left edge, the passage
## inside its right edge and the rows just above and below its bottom edge are
## all walked.
##
## A graph is built once per plan and kept (see of()): floors can reach 131,072
## cells, and a walk must not flood-fill one. A plan is a validated snapshot
## that nothing changes after it is drawn; the validator builds afresh every
## time it is asked, because a candidate plan it is shown may still change.
## Searches reuse scratch buffers allocated once per graph, a visit stamp
## telling this search's cells from the last one's; `expanded` counts their work.

## Why an obstacle is there.
enum Kind { WALL, WALL_DRAWING, TABLE, DECOR, FIXTURE, PARTITION }

const GRID := FloorLayoutPolicy.GRID
## The four steps a person takes; a direction is an index into this.
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const LEFT := 0
const RIGHT := 1
const UP := 2
const DOWN := 3
## The step a route takes when going straight on is not a shortest way:
## across first, as the office's lanes run.
const FALLBACK: Array[int] = [LEFT, RIGHT, UP, DOWN]
## Bits of one cell's entry in _flags.
const BLOCKED := 1
const NO_RIGHT := 2
const NO_DOWN := 4
## Graphs kept for the plans last validated or walked on.
const CACHE_SIZE := 8
## Obstacles are looked up by square buckets of this many cells a side, so a
## short segment is held against the few obstacles near it, not every one on
## a floor of hundreds of tables.
const BUCKET_CELLS := 4
## How far off an entry a point may be and still be on it.
const ON_ENTRY := 0.01


## One obstacle, already inflated by the person it stands in the way of.
class Obstacle:
	extends RefCounted
	var rect := Rect2()
	var kind := Kind.WALL
	## The tab of a TABLE; empty for everything else.
	var tab_key := ""
	## The only segments along which a route may enter this obstacle, as pairs
	## of points: the seat legs that run into a table (its far seats are inside
	## it), the threshold leg through the top wall's drawing clearance and the
	## legs up to the pantry's spots on the fixture row.
	var entries := PackedVector2Array()


## What route_between() found: which of the ends it walks from, and the node
## centres from that end to the goal; `end` is -1 when it found none, and
## `over_budget` says it stopped at its limit rather than for want of a way.
class Found:
	extends RefCounted
	var end := -1
	var points := PackedVector2Array()
	var over_budget := false


## How many graphs this process has built: a diagnostic, never a decision, so a
## test can prove the people walk the graph the validator built.
static var builds := 0
static var _cache: Array[OfficeWalkGraph] = []

## The floor in cells.
var size := Vector2i.ZERO
## The rectangles every obstacle was inflated by.
var footprint := Rect2()
var drawing := Rect2()
var obstacles: Array[Obstacle] = []
## Where the lift door meets the floor, and the end of its threshold leg: the
## first walkable cell centre straight below it; INF when there is none.
var door := Vector2.ZERO
var threshold := Vector2.INF
## The fixture row and the walking lane of a map with desks, as y (INF without,
## or where the band cannot hold both): where the pantry's people stand, and
## where everyone walks along the entry band.
var fixture_row := INF
var walking_lane := INF
## Graph work done on this graph so far: every node a search expanded and every
## node a route was read along. OfficePresentation budgets its routing in it.
var expanded := 0
## Searches run from a goal (route_between()), for tests.
var searches := 0
var _plan: WeakRef
var _flags := PackedByteArray()
## Bucket -> index of every obstacle whose rectangle reaches into it.
var _buckets: Dictionary[Vector2i, PackedInt32Array] = {}
var _threshold_index := -1
## Every cell's distance from the threshold (-1: unreached), built on first use.
var _door_dist := PackedInt32Array()
var _door_ready := false
## Scratch for route_between(), allocated on its first use: a cell's distance
## and queue slot belong to the current search when its stamp is `_mark`.
var _stamp := PackedInt32Array()
var _dist := PackedInt32Array()
var _queue := PackedInt32Array()
var _mark := 0


## The graph of `plan` for a person with these feet and this drawing, built
## once and then kept.
static func of(plan: FloorPlan, feet: Rect2, canvas: Rect2) -> OfficeWalkGraph:
	for kept in _cache:
		if kept._plan.get_ref() == plan and kept.footprint == feet and kept.drawing == canvas:
			return kept
	return build(plan, feet, canvas)


## A new graph of `plan`, replacing whatever was kept for it. The validator
## calls this: a candidate plan may change between two validations.
static func build(plan: FloorPlan, feet: Rect2, canvas: Rect2) -> OfficeWalkGraph:
	builds += 1
	var graph := OfficeWalkGraph.new()
	graph._plan = weakref(plan)
	graph.footprint = feet
	graph.drawing = canvas
	graph._build(plan)
	for index in range(_cache.size() - 1, -1, -1):
		if _cache[index]._plan.get_ref() == plan or _cache[index]._plan.get_ref() == null:
			_cache.remove_at(index)
	_cache.push_front(graph)
	if _cache.size() > CACHE_SIZE:
		_cache.resize(CACHE_SIZE)
	return graph


## The cell a floor point lies in.
static func cell_of(point: Vector2) -> Vector2i:
	return Vector2i((point / GRID).floor())


## The centre of a cell, which is its node.
static func centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID


## The leg into a seat from its table's approach point, starting on the
## approach's node. On the far side it is straight, into the table's own
## footprint, where the table hides the sitter's legs (docs/WORLD_MODEL.md,
## rule 5). On the near side the chair stands in line with the approach, so the
## leg goes round it: across to the standing spot's column, up to the spot, and
## a sidestep into the seat.
static func leg_to_seat(approach: Vector2, seat: Vector2, spot: Vector2, near: bool) -> PackedVector2Array:
	if near:
		return _deduplicated([centre(cell_of(approach)), approach, Vector2(spot.x, approach.y), spot, seat])
	return _deduplicated([centre(cell_of(approach)), approach, seat])


## The leg from a table's approach point to the spot its worker stands on when
## done, starting on the approach's node. The spot is beside the seat and a step
## toward the table from the approach, so the leg is L-shaped, never diagonal:
## on the far side first in line with the seat, then across (its corner lies on
## the seat leg); on the near side across first, clear of the chair, which makes
## it the near seat leg less its last step. Getting up and sitting down walk
## only parts of these two legs.
static func leg_to_standing(approach: Vector2, spot: Vector2, near: bool) -> PackedVector2Array:
	if near:
		return _deduplicated([centre(cell_of(approach)), approach, Vector2(spot.x, approach.y), spot])
	return _deduplicated([centre(cell_of(approach)), approach, Vector2(approach.x, spot.y), spot])


## The leg up to a spot on the fixture row (a queue's slot or a pantry's
## spot) from the approach straight below it on the walking lane, starting on
## the approach's node.
static func leg_to_fixture(approach: Vector2, spot: Vector2) -> PackedVector2Array:
	return _deduplicated([centre(cell_of(approach)), approach, spot])


## Whether the segment from `from` to `to` stays out of every rectangle in
## `rects`: an endpoint inside one, or a segment entering one, fails; touching
## an edge does not. The validator's segment rule since the floor had one.
static func clear_link(from: Vector2, to: Vector2, rects: Array[Rect2]) -> bool:
	for obstacle in rects:
		if not _clear_of(from, to, obstacle):
			return false
	return true


## `points` with repeated points dropped and every point that lies on a line
## with its two neighbours taken out: a straight run becomes one segment and a
## step back along the same line is cut short. What is left is a part of what
## was there, so a route that was clear stays clear.
static func straighten(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if not result.is_empty() and result[result.size() - 1] == point:
			continue
		result.append(point)
		while result.size() >= 3:
			var last := result.size() - 1
			var a := result[last - 2]
			var b := result[last - 1]
			var c := result[last]
			if not ((a.x == b.x and b.x == c.x) or (a.y == b.y and b.y == c.y)):
				break
			result.remove_at(last - 1)
			if result[result.size() - 1] == result[result.size() - 2]:
				result.remove_at(result.size() - 1)
	return result


## How long a route is.
static func length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


## The direction a step from `from` to `to` goes (LEFT, RIGHT, UP, DOWN); -1
## for no step or a diagonal one.
static func heading(from: Vector2, to: Vector2) -> int:
	if from == to or (from.x != to.x and from.y != to.y):
		return -1
	if from.y == to.y:
		return RIGHT if to.x > from.x else LEFT
	return DOWN if to.y > from.y else UP


## Whether a person can stand on `cell`.
func walkable(cell: Vector2i) -> bool:
	return _inside_floor(cell) and _flags[_index(cell)] & BLOCKED == 0


## Whether a person can step from `cell` in `direction` (LEFT, RIGHT, UP, DOWN).
func linked(cell: Vector2i, direction: int) -> bool:
	return _inside_floor(cell) and _step(_index(cell), direction) >= 0


## Why nobody can come in through the door; empty when they can.
func threshold_problem() -> String:
	if not threshold.is_finite() or not clear(door, threshold):
		return "the lift door has no clear threshold"
	return ""


## Whether `cell` can be walked to from the door.
func reaches(cell: Vector2i) -> bool:
	return door_distance(cell) >= 0


## How many steps `cell` is from the threshold; -1 when the door does not reach it.
func door_distance(cell: Vector2i) -> int:
	if not _inside_floor(cell) or _threshold_index < 0:
		return -1
	return _door_field()[_index(cell)]


## Whether the segment from `from` to `to` stays out of every obstacle, but for
## the obstacle's own entries: it may run into one only along them. Only the
## obstacles of the buckets the segment reaches are looked at; one in two of
## those buckets is looked at twice, which costs less than sorting them out.
func clear(from: Vector2, to: Vector2) -> bool:
	var box := Rect2(from, to - from).abs()
	var straight := from.x == to.x or from.y == to.y
	var first := _bucket_of(box.position)
	var last := _bucket_of(box.end)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var listed: PackedInt32Array = _buckets.get(Vector2i(x, y), PackedInt32Array())
			for index in listed:
				var obstacle := obstacles[index]
				# A segment along an axis enters a rectangle exactly when its box
				# does (what _clear_of() works out, without the call).
				var enters := box.intersects(obstacle.rect) if straight else not _clear_of(from, to, obstacle.rect)
				if enters and not _along_entry(from, to, obstacle):
					return false
	return true


## Whether every segment of `points` is clear (see clear()).
func clear_route(points: PackedVector2Array) -> bool:
	if points.size() == 1:
		return clear(points[0], points[0])
	for index in range(1, points.size()):
		if not clear(points[index - 1], points[index]):
			return false
	return true


## Whether `point` lies inside an obstacle other than on one of its entries.
func inside(point: Vector2) -> bool:
	return not clear(point, point)


## The route in from the door to the node of `cell`: the door, then node
## centres from the threshold on; empty when the door does not reach it. It is
## read back from the cell, so it arrives going `arrival` (a direction) where
## that is a shortest way.
func from_door(cell: Vector2i, arrival := -1) -> PackedVector2Array:
	if door_distance(cell) < 0:
		return PackedVector2Array()
	var back := _descend(_index(cell), _reverse(arrival), _door_dist, PackedInt32Array(), 0)
	back.reverse()
	var result := PackedVector2Array([door])
	result.append_array(_centres(back))
	return result


## The route out from the node of `cell` to the door, setting off `departure`
## (a direction) where that is a shortest way: node centres to the threshold,
## then the door; empty when the door does not reach it.
func to_door(cell: Vector2i, departure := -1) -> PackedVector2Array:
	if door_distance(cell) < 0:
		return PackedVector2Array()
	var result := _centres(_descend(_index(cell), departure, _door_dist, PackedInt32Array(), 0))
	result.append(door)
	return result


## The route from the node of `cell` down the door's field to the walking
## lane: node centres from the cell to the first node on the lane, which is
## where every seat reaches the entry band (the lane's node under the
## threshold, or the corridor's other lane beside it). A cell above the lane
## (the threshold) steps down onto it. Empty when the door does not reach the
## cell or the floor has no lane.
func to_lane(cell: Vector2i) -> PackedVector2Array:
	if not is_finite(walking_lane) or door_distance(cell) < 0:
		return PackedVector2Array()
	var route := _centres(_descend(_index(cell), -1, _door_dist, PackedInt32Array(), 0))
	for index in route.size():
		if route[index].y == walking_lane:
			return route.slice(0, index + 1)
	route.append(Vector2(route[route.size() - 1].x, walking_lane))
	return route


## The route from the walking lane to the node of `cell`, read off the door's
## field: node centres from the first node on the lane to the cell (see
## to_lane()). Empty when the door does not reach the cell, the floor has no
## lane, or the way in does not cross it.
func from_lane(cell: Vector2i) -> PackedVector2Array:
	if not is_finite(walking_lane) or door_distance(cell) < 0:
		return PackedVector2Array()
	var back := _centres(_descend(_index(cell), -1, _door_dist, PackedInt32Array(), 0))
	back.reverse()
	for index in back.size():
		if back[index].y == walking_lane:
			return back.slice(index)
	return PackedVector2Array()


## The shortest route to the node of `goal` from whichever of `ends` (nodes) is
## cheaper to set off from, reaching ends[i] having walked `leads[i]` units
## already: one breadth-first search from the goal, stopped once no end still
## unreached could be cheaper than the best one reached. The route is read from
## that end, setting off `headings[i]` where that is a shortest way. It gives
## up (over_budget) when the search and reading its route back would take more
## than `limit` nodes of graph work, and finds nothing once every end still
## unreached is more than `reach` steps from the goal.
func route_between(
	goal: Vector2i, ends: Array[Vector2i], leads: PackedFloat32Array, headings: PackedInt32Array, limit: int, reach: int
) -> Found:
	var found := Found.new()
	searches += 1
	if ends.is_empty() or not walkable(goal):
		return found
	var total := size.x * size.y
	if _stamp.size() != total:
		_stamp.resize(total)
		_stamp.fill(0)
		_dist.resize(total)
		_queue.resize(total)
		_mark = 0
	_mark += 1
	if _mark >= 2147483647:
		_stamp.fill(0)
		_mark = 1
	var width := size.x
	var flags := _flags
	var stamp := _stamp
	var dist := _dist
	var queue := _queue
	var mark := _mark
	# A cell this search reached is stamped `mark`, an end it has not reached yet
	# -`mark`: telling an end apart costs the loop nothing.
	var targets := PackedInt32Array()
	for end in ends:
		var at := _index(end) if walkable(end) else -1
		targets.append(at)
		if at >= 0:
			stamp[at] = -mark
	var start := _index(goal)
	stamp[start] = mark
	dist[start] = 0
	queue[0] = start
	var best := -1
	var best_cost := INF
	for target in targets.size():
		if targets[target] == start and leads[target] < best_cost:
			best = target
			best_cost = leads[target]
	# The search ends where the cells it reaches next are `stop` steps from the
	# goal: past `reach`, or where no end still unreached could be cheaper.
	var stop := reach + 1
	if best >= 0:
		stop = mini(stop, _stop_at(targets, leads, best_cost, stamp, mark))
	var count := 1
	var cursor := 0
	var spent := 0
	while cursor < count:
		var index := queue[cursor]
		var step := dist[index] + 1
		if step >= stop:
			break
		if spent >= limit:
			# Past the budget, even an end already reached is not read back.
			found.over_budget = true
			break
		cursor += 1
		spent += 1
		var here := flags[index]
		var column := index % width
		var reached := false
		# The four steps, left, right, up and down, written out: this is the
		# loop routing spends its time in, and a call or a match per step
		# doubles it.
		var next := index - 1
		if column > 0 and flags[next] & (NO_RIGHT | BLOCKED) == 0 and stamp[next] != mark:
			reached = reached or stamp[next] == -mark
			stamp[next] = mark
			dist[next] = step
			queue[count] = next
			count += 1
		next = index + 1
		if column + 1 < width and here & NO_RIGHT == 0 and flags[next] & BLOCKED == 0 and stamp[next] != mark:
			reached = reached or stamp[next] == -mark
			stamp[next] = mark
			dist[next] = step
			queue[count] = next
			count += 1
		next = index - width
		if index >= width and flags[next] & (NO_DOWN | BLOCKED) == 0 and stamp[next] != mark:
			reached = reached or stamp[next] == -mark
			stamp[next] = mark
			dist[next] = step
			queue[count] = next
			count += 1
		next = index + width
		if next < total and here & NO_DOWN == 0 and flags[next] & BLOCKED == 0 and stamp[next] != mark:
			reached = reached or stamp[next] == -mark
			stamp[next] = mark
			dist[next] = step
			queue[count] = next
			count += 1
		if reached:
			for target in targets.size():
				var at := targets[target]
				if at >= 0 and stamp[at] == mark and dist[at] == step and step * GRID + leads[target] < best_cost:
					best = target
					best_cost = step * GRID + leads[target]
			stop = mini(reach + 1, _stop_at(targets, leads, best_cost, stamp, mark))
	if best >= 0 and spent + dist[targets[best]] + 1 > limit:
		# Reading the route back is graph work too; past the budget it is not read.
		found.over_budget = true
	expanded += spent
	if best < 0 or found.over_budget:
		return found
	found.end = best
	found.points = _centres(_descend(targets[best], headings[best], dist, stamp, mark))
	return found


func _build(plan: FloorPlan) -> void:
	size = plan.floor_cells.size
	_flags.resize(size.x * size.y)
	_flags.fill(0)
	_collect(plan)
	for obstacle in obstacles:
		_mark_cells(obstacle.rect)
	door = OfficeShell.door(plan)
	var column := floori(door.x / GRID)
	for row in range(plan.entry_cells.position.y, plan.entry_cells.end.y):
		var cell := Vector2i(column, row)
		if centre(cell).y > door.y and walkable(cell):
			threshold = centre(cell)
			break
	if not threshold.is_finite():
		return
	# The threshold leg is the one way through the top wall's drawing clearance.
	for obstacle in obstacles:
		if obstacle.kind == Kind.WALL_DRAWING and not _clear_of(door, threshold, obstacle.rect):
			obstacle.entries.append_array(PackedVector2Array([door, threshold]))
	if threshold_problem().is_empty():
		_threshold_index = _index(cell_of(threshold))
	if _banded(plan):
		var band_top := float(plan.entry_cells.position.y * GRID)
		fixture_row = band_top + OfficeShell.FIXTURE_ROW
		walking_lane = band_top + OfficeShell.WALKING_LANE


## Whether `plan` has the entry band's two walked rows: a map with desks whose
## band holds the fixture row and the walking lane under the wall's clearance.
static func _banded(plan: FloorPlan) -> bool:
	return not plan.desks.is_empty() and plan.entry_cells.size.y * GRID >= OfficeShell.WALKING_LANE + GRID / 2.0


## Every obstacle of the plan, inflated: the outer walls but the cutaway front,
## every zone's partitions (by the feet only), every table's physical footprint
## (with the seat legs that run into it as its entries) and every standing
## piece. The outer walls are where the plan's entry band says they end: it
## runs between the side walls, right under the top one.
func _collect(plan: FloorPlan) -> void:
	var outline := Vector2(size) * GRID
	var entry := Rect2(plan.entry_cells.position * GRID, plan.entry_cells.size * GRID)
	var walls: Array[Rect2] = [
		Rect2(0, 0, outline.x, entry.position.y),
		Rect2(0, 0, entry.position.x, outline.y),
		Rect2(entry.end.x, 0, outline.x - entry.end.x, outline.y),
	]
	for wall in walls:
		_add(_inflate(wall, footprint), Kind.WALL)
		if drawing.has_area():
			_add(_inflate(wall, drawing), Kind.WALL_DRAWING)
	for zone in plan.zones:
		for band in zone.partitions():
			_add(_inflate(band, footprint), Kind.PARTITION)
	for placed in plan.desks:
		var physical := placed.measure.physical_rect
		physical.position += placed.origin
		var rect := _inflate(physical, footprint)
		var entries := PackedVector2Array()
		for column in placed.capacity:
			for near: bool in [false, true]:
				var side := "near" if near else "far"
				var approach := placed.origin + placed.measure.approach_position(column, side)
				var seat := placed.origin + placed.measure.seat_position(column, side)
				var spot := placed.origin + placed.measure.standing_position(column, side)
				for leg: PackedVector2Array in [
					leg_to_seat(approach, seat, spot, near), leg_to_standing(approach, spot, near)
				]:
					for index in range(1, leg.size()):
						if not _clear_of(leg[index - 1], leg[index], rect):
							entries.append(leg[index - 1])
							entries.append(leg[index])
		_add(rect, Kind.TABLE, placed.tab_key, entries)
	for decoration in plan.decorations:
		_add(_inflate(decoration.footprint, footprint), Kind.DECOR)
	_collect_fixtures(plan)


## The pantry's counter, inflated by the feet like any furniture, and on every
## map with desks the fixture row from the left wall to the main corridor: a
## band of node centres, not a body, so it is not inflated. Its entries are
## the pantry spots' legs; with no pantry it has none.
func _collect_fixtures(plan: FloorPlan) -> void:
	for fixture in plan.fixtures():
		_add(_inflate(fixture.footprint, footprint), Kind.FIXTURE)
	if not _banded(plan):
		return
	var band_top := float(plan.entry_cells.position.y * GRID)
	var left := float(plan.entry_cells.position.x * GRID)
	var row := Rect2(
		left, band_top + OfficeShell.FIXTURE_ROW - GRID / 2.0, plan.main_corridor_cells.position.x * GRID - left, GRID
	)
	var entries := PackedVector2Array()
	for fixture in plan.fixtures():
		for index in fixture.spots.size():
			entries.append(fixture.approaches[index])
			entries.append(fixture.spots[index])
	_add(row, Kind.FIXTURE, "", entries)


func _add(rect: Rect2, kind: Kind, tab_key := "", entries := PackedVector2Array()) -> void:
	var obstacle := Obstacle.new()
	obstacle.rect = rect
	obstacle.kind = kind
	obstacle.tab_key = tab_key
	obstacle.entries = entries
	var first := _bucket_of(rect.position)
	var last := _bucket_of(rect.end)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var bucket := Vector2i(x, y)
			var listed: PackedInt32Array = _buckets.get(bucket, PackedInt32Array())
			listed.append(obstacles.size())
			_buckets[bucket] = listed
	obstacles.append(obstacle)


static func _bucket_of(point: Vector2) -> Vector2i:
	return Vector2i((point / float(GRID * BUCKET_CELLS)).floor())


## Block every node whose centre is inside `inflated` and every edge that enters
## it. Only the cells around it are looked at, a cell more on every side.
func _mark_cells(inflated: Rect2) -> void:
	var start := (Vector2i((inflated.position / GRID).floor()) - Vector2i.ONE).max(Vector2i.ZERO)
	var end := (Vector2i((inflated.end / GRID).ceil()) + Vector2i.ONE).min(size)
	for y in range(start.y, end.y):
		for x in range(start.x, end.x):
			var at := centre(Vector2i(x, y))
			var index := y * size.x + x
			var flags := _flags[index]
			if Rect2(at, Vector2.ZERO).intersects(inflated):
				flags |= BLOCKED
			if not _clear_of(at, at + Vector2(GRID, 0), inflated):
				flags |= NO_RIGHT
			if not _clear_of(at, at + Vector2(0, GRID), inflated):
				flags |= NO_DOWN
			_flags[index] = flags


## The door's distance field: breadth-first from the threshold over every cell
## it reaches, once per graph (the validator asks first, so walkers seldom pay).
func _door_field() -> PackedInt32Array:
	if _door_ready:
		return _door_dist
	_door_ready = true
	var total := size.x * size.y
	_door_dist.resize(total)
	_door_dist.fill(-1)
	if _threshold_index < 0:
		return _door_dist
	var width := size.x
	var flags := _flags
	var dist := _door_dist
	var queue := PackedInt32Array()
	queue.resize(total)
	dist[_threshold_index] = 0
	queue[0] = _threshold_index
	var count := 1
	var cursor := 0
	while cursor < count:
		var index := queue[cursor]
		cursor += 1
		var step := dist[index] + 1
		var here := flags[index]
		var column := index % width
		for direction in 4:
			var next := -1
			match direction:
				LEFT:
					if column > 0 and flags[index - 1] & NO_RIGHT == 0:
						next = index - 1
				RIGHT:
					if column + 1 < width and here & NO_RIGHT == 0:
						next = index + 1
				UP:
					if index >= width and flags[index - width] & NO_DOWN == 0:
						next = index - width
				_:
					if index + width < total and here & NO_DOWN == 0:
						next = index + width
			if next < 0 or dist[next] >= 0 or flags[next] & BLOCKED != 0:
				continue
			dist[next] = step
			queue[count] = next
			count += 1
	expanded += count
	return _door_dist


## How many steps from the goal a search may stop reaching cells: from there on
## no end it has not reached (stamped other than `mark`) could be cheaper than
## `best_cost`; 0 when it reached them all.
static func _stop_at(
	targets: PackedInt32Array, leads: PackedFloat32Array, best_cost: float, stamp: PackedInt32Array, mark: int
) -> int:
	var stop := 0
	for target in targets.size():
		var at := targets[target]
		if at >= 0 and stamp[at] != mark:
			stop = maxi(stop, ceili((best_cost - leads[target]) / GRID))
	return stop


## The nodes from `start` down a distance field to its root, one step nearer
## each time: straight on (first `prefer`) while that is one, else across first. The
## field is `dist`, whose cells count only where `stamp` is `mark` when a mark is
## given. Each node read counts as work.
func _descend(start: int, prefer: int, dist: PackedInt32Array, stamp: PackedInt32Array, mark: int) -> PackedInt32Array:
	var cells := PackedInt32Array([start])
	var width := size.x
	var total := size.x * size.y
	var flags := _flags
	var at := start
	var left := dist[at]
	var going := prefer
	while left > 0:
		var next := -1
		var chosen := -1
		# `prefer`'s way first, then FALLBACK's; the step written out, as in
		# route_between(), because every node of every route is read here.
		for attempt in FALLBACK.size() + 1:
			var direction := going if attempt == 0 else FALLBACK[attempt - 1]
			var step := -1
			if direction == LEFT:
				if at % width > 0 and flags[at - 1] & NO_RIGHT == 0:
					step = at - 1
			elif direction == RIGHT:
				if at % width + 1 < width and flags[at] & NO_RIGHT == 0:
					step = at + 1
			elif direction == UP:
				if at >= width and flags[at - width] & NO_DOWN == 0:
					step = at - width
			elif direction == DOWN:
				if at + width < total and flags[at] & NO_DOWN == 0:
					step = at + width
			if (
				step >= 0
				and flags[step] & BLOCKED == 0
				and (mark == 0 or stamp[step] == mark)
				and dist[step] == left - 1
			):
				next = step
				chosen = direction
				break
		if next < 0:
			break
		cells.append(next)
		at = next
		going = chosen
		left -= 1
	expanded += cells.size()
	return cells


## The cell a step from `index` in `direction` takes to, when that step is open; else -1.
func _step(index: int, direction: int) -> int:
	var width := size.x
	var next := -1
	match direction:
		LEFT:
			if index % width > 0 and _flags[index - 1] & NO_RIGHT == 0:
				next = index - 1
		RIGHT:
			if index % width + 1 < width and _flags[index] & NO_RIGHT == 0:
				next = index + 1
		UP:
			if index >= width and _flags[index - width] & NO_DOWN == 0:
				next = index - width
		DOWN:
			if index + width < size.x * size.y and _flags[index] & NO_DOWN == 0:
				next = index + width
	if next < 0 or _flags[index] & BLOCKED != 0 or _flags[next] & BLOCKED != 0:
		return -1
	return next


## The centres of the cells `cells` lists (as indices), as centre() works them out.
func _centres(cells: PackedInt32Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(cells.size())
	var width := size.x
	for index in cells.size():
		var cell := cells[index]
		result[index] = Vector2(cell % width + 0.5, floorf(float(cell) / width) + 0.5) * GRID
	return result


func _inside_floor(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _index(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x


func _cell(index: int) -> Vector2i:
	return Vector2i(index % size.x, floori(float(index) / size.x))


static func _reverse(direction: int) -> int:
	match direction:
		LEFT:
			return RIGHT
		RIGHT:
			return LEFT
		UP:
			return DOWN
		DOWN:
			return UP
	return -1


static func _inflate(obstacle: Rect2, body: Rect2) -> Rect2:
	return Rect2(obstacle.position - body.end, obstacle.size + body.size)


## Whether the part of the axis-aligned segment from `from` to `to` that lies in
## `obstacle` lies on one of its entries: only then may the segment enter it.
static func _along_entry(from: Vector2, to: Vector2, obstacle: Obstacle) -> bool:
	var entries := obstacle.entries
	if entries.is_empty():
		return false
	var rect := obstacle.rect
	for index in range(0, entries.size() - 1, 2):
		var a := entries[index]
		var b := entries[index + 1]
		if from.x == to.x and a.x == b.x and absf(a.x - from.x) <= ON_ENTRY:
			var low := maxf(minf(from.y, to.y), rect.position.y)
			var high := minf(maxf(from.y, to.y), rect.end.y)
			if low >= minf(a.y, b.y) - ON_ENTRY and high <= maxf(a.y, b.y) + ON_ENTRY:
				return true
		if from.y == to.y and a.y == b.y and absf(a.y - from.y) <= ON_ENTRY:
			var low := maxf(minf(from.x, to.x), rect.position.x)
			var high := minf(maxf(from.x, to.x), rect.end.x)
			if low >= minf(a.x, b.x) - ON_ENTRY and high <= maxf(a.x, b.x) + ON_ENTRY:
				return true
	return false


static func _clear_of(from: Vector2, to: Vector2, obstacle: Rect2) -> bool:
	# Route endpoints are cell centres or measured points; an off-grid one is
	# checked as it is.
	if Rect2(from, Vector2.ZERO).intersects(obstacle) or Rect2(to, Vector2.ZERO).intersects(obstacle):
		return false
	if from == to:
		return true
	if from.x == to.x or from.y == to.y:
		# Native rectangle intersection also handles zero-width/height
		# segments and allows tangency without treating it as penetration.
		return not Rect2(from, to - from).abs().intersects(obstacle)
	var corners: Array[Vector2] = [
		obstacle.position,
		Vector2(obstacle.end.x, obstacle.position.y),
		obstacle.end,
		Vector2(obstacle.position.x, obstacle.end.y)
	]
	for index in corners.size():
		if (
			Geometry2D.segment_intersects_segment(from, to, corners[index], corners[(index + 1) % corners.size()])
			!= null
		):
			return false
	return true


static func _deduplicated(points: Array[Vector2]) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		if result.is_empty() or result[result.size() - 1] != point:
			result.append(point)
	return result
