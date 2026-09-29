class_name OfficeFixturePlanner
extends RefCounted
## The entry band's two service fixtures for a candidate floor plan: the
## reception counter left of the lift door with its queue running leftwards
## from it, and the pantry at the band's left end with its spots. Both stand
## against the top wall; their people stand on the fixture row below them and
## step up into it from the walking lane (OfficeShell.FIXTURE_ROW, WALKING_LANE).
##
## Not decor: the entry band is a walkway for the decor rules, and these stand
## in it on purpose. Every position is a pure function of the plan's geometry:
## the counter and its queue follow the main corridor when the floor widens,
## like the lift door, and nothing here reads who is on the floor.
##
## Only a floor with at least one row gets them (the lobby and an empty
## workspace have no tables, so nobody to queue). A band that cannot hold the
## counter, the door's clearance and MIN_QUEUE slots has neither; one that cannot
## also hold the pantry's counter and one spot has no pantry. When both fit,
## the row between the two counters is shared: the queue takes half of what it
## holds (rounded up, at least MIN_QUEUE, at most MAX_QUEUE), the pantry the
## rest (at most MAX_PANTRY), with FIXTURE_GAP at least between them.
##
## Nobody queues at the reception (blocked agents sit at their seats):
## its slots are still reserved here, and still validated and walked by the
## floor's checks, only so that no floor is laid out differently. They are the
## empty space in front of the counter.
##
## This only proposes. OfficeFloorLayout.plan() furnishes its candidate before
## the validation that plan gets, and leaves a fixture out when the furnished
## floor would not validate (the pantry first, then the reception).

var _pen: OfficeDraw


## `pen` measures the counters' drawings.
func _init(pen: OfficeDraw) -> void:
	_pen = pen


## Place the fixtures `next` has room for. A new candidate plan can be
## furnished; a retained previous plan is immutable and never comes here.
func furnish(next: FloorPlan) -> void:
	next.reception = null
	next.pantry = null
	var grid := float(FloorLayoutPolicy.GRID)
	# A band without a fixture row and a walking lane under the wall has no room.
	if next.rows.is_empty() or next.entry_cells.size.y * grid < OfficeShell.WALKING_LANE + grid / 2.0:
		return
	var band_top := next.entry_cells.position.y * grid
	var inner_left := next.entry_cells.position.x * grid
	var row_y := band_top + OfficeShell.FIXTURE_ROW
	var lane_y := band_top + OfficeShell.WALKING_LANE
	var foot_y := band_top + OfficeShell.COUNTER_FOOT
	var pitch := OfficeShell.SPOT_PITCH
	var counter_width := OfficeDecor.footprint_of(_pen.art, ArtContract.PROP_RECEPTION).x
	var counter_right := next.main_corridor_cells.position.x * grid - OfficeShell.DOOR_CLEARANCE
	var counter_left := counter_right - counter_width
	var length := counter_left - inner_left
	if length < OfficeShell.MIN_QUEUE * pitch:
		return
	var queue := mini(OfficeShell.MAX_QUEUE, floori(length / pitch))
	var spots := 0
	var shared := floori((length - OfficeShell.FIXTURE_GAP) / pitch)
	var pantry_width := OfficeDecor.footprint_of(_pen.art, ArtContract.PROP_PANTRY).x
	if shared >= OfficeShell.MIN_QUEUE + 1:
		var halved := clampi(ceili(shared / 2.0), OfficeShell.MIN_QUEUE, OfficeShell.MAX_QUEUE)
		# The pantry's counter stays clear of where the queue's tail stands.
		if inner_left + pantry_width <= counter_left - halved * pitch:
			queue = halved
			spots = mini(OfficeShell.MAX_PANTRY, shared - halved)
	var reception := _fixture(
		FixturePlacement.Kind.RECEPTION, ArtContract.PROP_RECEPTION, Vector2(counter_left + counter_width / 2.0, foot_y)
	)
	for index in queue:
		var x := counter_left - pitch * (index + 0.5)
		reception.spots.append(Vector2(x, row_y))
		reception.approaches.append(Vector2(x, lane_y))
	next.reception = reception
	if spots <= 0:
		return
	var pantry := _fixture(
		FixturePlacement.Kind.PANTRY, ArtContract.PROP_PANTRY, Vector2(inner_left + pantry_width / 2.0, foot_y)
	)
	for index in spots:
		var x := inner_left + pitch * (index + 0.5)
		pantry.spots.append(Vector2(x, row_y))
		pantry.approaches.append(Vector2(x, lane_y))
	next.pantry = pantry


func _fixture(kind: FixturePlacement.Kind, piece: StringName, at: Vector2) -> FixturePlacement:
	var result := FixturePlacement.new()
	result.kind = kind
	result.key = "reception" if kind == FixturePlacement.Kind.RECEPTION else "pantry"
	result.piece = piece
	result.position = at
	var footprint := OfficeDecor.footprint_of(_pen.art, piece)
	result.footprint = Rect2(at - Vector2(footprint.x / 2.0, footprint.y), footprint)
	var sprite := _pen.art.prop_sprite(piece)
	result.draw_rect = Rect2(at - sprite.pivot, Vector2(sprite.size))
	return result
