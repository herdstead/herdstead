class_name OfficeDecorPlanner
extends RefCounted
## Standing furniture for a candidate map, on grids of the map itself, never
## placed by the tables, the zones or anything herdr says:
## - the top-wall run: plants at the top wall's foot, in the entry band's
##   drawing-clearance row, OfficeShell.TOP_RUN_PITCH apart from
##   TOP_RUN_FROM, keyed by their grid step ("top/%03d"), the plant of the step
##   (plant_at()); a step whose plant would come within WALL_RUN_GAP of the
##   lift door, a window, a picture or the pantry counter stands empty;
## - lane gaps (lane_gaps()): in every run of at least LANE_GAP_MIN_CELLS free
##   cell rows inside a lane, outside every zone's slot and down to the map's
##   bottom, a piece every LANE_GAP_STEP_CELLS rows from the run's second row,
##   in the lane's middle column, keyed by the lane and the row
##   ("%02d/gap/%04d"): plants and side tables take turns along the run
##   (piece j: a side table when j is odd, else the plant plant_at(j / 2), so
##   the plants of one run take turns too); a side table carries one piece from the
##   `desk` pool or, now and then, the `cat` one (side_table_item(), seeded by
##   its key).
## A piece is kept only where its drawing stays on the map and, grown by
## WALL_RUN_GAP, clear of every zone's slot (its pods, partitions, posts and
## sign), the door, the windows, the pictures, the pantry counter and the
## pieces kept before it, and its footprint stays off every walkway and aisle
## (OfficeFloorValidation.walkways()). Furniture is optional: a piece that does
## not fit is left out, never a desk moved for it. Where a piece stands follows
## from the map's geometry alone, so a zone growing elsewhere moves none of it.
##
## This only proposes. OfficeFloorLayout.plan() furnishes its candidate, after
## its pantry, before the one validation that plan gets, and leaves the whole
## batch out when the furnished map would close a path to any seat. Drawing it
## is OfficeFloorView's business.

## The pool the plants are drawn from (ItemSpec.group).
const PLANT_GROUP := &"plant"
## The pools a side table's one piece is drawn from: a trinket, or now and
## then (SIDE_TABLE_CAT of the tables) the white cat.
const DESK_GROUP := &"desk"
const CAT_GROUP := &"cat"
const SIDE_TABLE_CAT := 0.28

## The lanes' geometry the candidate was planned with: OfficeFloorLayout.plan()
## hands its policy in before it furnishes.
var policy := FloorLayoutPolicy.new()
var _pen: OfficeDraw


## A run of free cell rows inside one lane: rows `top` to `end` (exclusive).
class LaneGap:
	extends RefCounted
	var lane := 0
	var top := 0
	var end := 0


## `pen` measures the pack's prop sprites.
func _init(pen: OfficeDraw) -> void:
	_pen = pen


## Which plant stands at place `index` of a run (the top-wall run's grid step,
## a lane gap's piece number): the pack's plants (PLANT_GROUP, in the order it
## lists them) take turns by the place, so a run reads as kinds, not a stamp.
## Only the place: never a state, a tab or the time. Empty when the pack has no plant.
static func plant_at(art: ArtPack, index: int) -> StringName:
	var plants := art.items_in(PLANT_GROUP)
	if plants.is_empty():
		return &""
	return plants[posmod(index, plants.size())].id


## What stands on the side table placed at `key`: a cat (SIDE_TABLE_CAT of the
## keys) or a trinket, by weight (ArtPack.pick()), from a stream seeded by the
## placement key alone: never a tab, a zone, a state or the time, so the same
## place always carries the same piece. Empty when the pack has no pool.
static func side_table_item(art: ArtPack, key: String) -> StringName:
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	var cats := art.items_in(CAT_GROUP)
	var trinkets := art.items_in(DESK_GROUP)
	var pool := cats if rng.randf() < SIDE_TABLE_CAT and not cats.is_empty() else trinkets
	var chosen := ArtPack.pick(pool, rng)
	return chosen.id if chosen != null else &""


## Every run of free cell rows inside a lane of `plan`, lane by lane, top down:
## from under the entry band to the map's bottom, outside every zone's slot,
## at least LANE_GAP_MIN_CELLS rows deep.
static func lane_gaps(plan: FloorPlan, rules: FloorLayoutPolicy) -> Array[LaneGap]:
	var found: Array[LaneGap] = []
	var first := rules.wall_cells + rules.entry_cells
	for lane in plan.lanes:
		var columns := Vector2i(rules.lane_x(lane), rules.lane_x(lane) + rules.zone_width_cells)
		var taken: Array[Vector2i] = []
		for zone in plan.zones:
			var slot := zone.slot()
			if slot.position.x < columns.y and slot.end.x > columns.x:
				taken.append(Vector2i(slot.position.y, slot.end.y))
		taken.sort()
		taken.append(Vector2i(plan.floor_cells.size.y, plan.floor_cells.size.y))
		var y := first
		for span in taken:
			if span.x - y >= OfficeShell.LANE_GAP_MIN_CELLS:
				var gap := LaneGap.new()
				gap.lane = lane
				gap.top = y
				gap.end = span.x
				found.append(gap)
			y = maxi(y, span.y)
	return found


## Add every candidate that fits `next`. A new candidate plan can be
## furnished; a retained previous plan is immutable and never comes here.
func furnish(next: FloorPlan) -> void:
	var rules := policy
	var grid := float(FloorLayoutPolicy.GRID)
	var covers := OfficeShell.wall_covers(next, _pen)
	for frame in OfficeShell.frames(next, _pen):
		covers.append(OfficeShell.drawn(_pen, ArtContract.PROP_WALL_FRAME, frame))
	for zone in next.zones:
		var slot := zone.slot()
		covers.append(Rect2(slot.position * grid, slot.size * grid))
	var walkways := OfficeFloorValidation.walkways(next)
	var placed: Array[DecorPlacement] = []
	var bay_end := next.main_corridor_cells.position.x * grid
	var step := 0
	while OfficeShell.TOP_RUN_FROM + step * OfficeShell.TOP_RUN_PITCH < bay_end:
		var at := Vector2(OfficeShell.TOP_RUN_FROM + step * OfficeShell.TOP_RUN_PITCH, OfficeShell.TOP_RUN_FOOT)
		var candidate := _candidate("top/%03d" % step, plant_at(_pen.art, step), at)
		if _fits(next, covers, walkways, placed, candidate):
			placed.append(candidate)
		step += 1
	for gap in lane_gaps(next, rules):
		var middle := (rules.lane_x(gap.lane) + floorf(rules.zone_width_cells / 2.0) + 0.5) * grid
		var index := 0
		for row in range(gap.top + 1, gap.end - 1, OfficeShell.LANE_GAP_STEP_CELLS):
			var key := "%02d/gap/%04d" % [gap.lane, row]
			var at := Vector2(middle, (row + 1) * grid - OfficeShell.LANE_GAP_FOOT)
			var table := index % 2 == 1
			var piece := ArtContract.PROP_SIDE_TABLE if table else plant_at(_pen.art, index >> 1)
			var candidate := _candidate(key, piece, at, side_table_item(_pen.art, key) if table else &"")
			if _fits(next, covers, walkways, placed, candidate):
				placed.append(candidate)
			index += 1
	# In key order, the order the floor view keeps them in in its sorted root,
	# so what is drawn lines up with the plan one for one.
	placed.sort_custom(_by_key)
	next.decorations.append_array(placed)


static func _by_key(a: DecorPlacement, b: DecorPlacement) -> bool:
	return a.key < b.key


## A piece `piece` standing at `at`, carrying `item` on its top (OfficeDecor.TOP_Y)
## when that is not empty: its drawing covers both.
func _candidate(key: String, piece: StringName, at: Vector2, item := &"") -> DecorPlacement:
	var result := DecorPlacement.new()
	result.key = key
	result.piece = piece
	result.position = at
	result.item = item
	var footprint := OfficeDecor.footprint_of(_pen.art, piece)
	result.footprint = Rect2(at - Vector2(footprint.x / 2.0, footprint.y), footprint)
	var sprite := _pen.art.prop_sprite(piece)
	result.draw_rect = Rect2(at - sprite.pivot, Vector2(sprite.size))
	var carried := _pen.art.prop_sprite(item) if not item.is_empty() else null
	if carried != null:
		var on_top := at + Vector2(0, OfficeDecor.TOP_Y)
		result.draw_rect = result.draw_rect.merge(Rect2(on_top - carried.pivot, Vector2(carried.size)))
	return result


## Whether `candidate` fits `next` beside the pieces `placed` so far: a piece
## the pack has, its drawing on the map, its footprint off every walkway and
## aisle, and its drawing, grown by WALL_RUN_GAP, clear of `covers` (the top
## wall's pieces, the pictures and every zone's slot) and of those pieces.
func _fits(
	next: FloorPlan,
	covers: Array[Rect2],
	walkways: Array[Rect2],
	placed: Array[DecorPlacement],
	candidate: DecorPlacement
) -> bool:
	if candidate.piece == &"" or not candidate.footprint.has_area():
		return false
	if not next.render_bounds.encloses(candidate.draw_rect):
		return false
	for walkway in walkways:
		if candidate.footprint.intersects(walkway):
			return false
	var drawn := candidate.draw_rect.grow(OfficeShell.WALL_RUN_GAP)
	for cover in covers:
		if drawn.intersects(cover):
			return false
	for other in placed:
		if drawn.intersects(other.draw_rect):
			return false
	return true
