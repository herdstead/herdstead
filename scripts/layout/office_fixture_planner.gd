class_name OfficeFixturePlanner
extends RefCounted
## The entry band's one service fixture for a candidate map: the pantry at the
## band's left end, against the top wall, with its spots on the fixture row
## below it, from the left wall on, SPOT_PITCH apart, ending FIXTURE_GAP at
## least before the main corridor, at most MAX_PANTRY of them (12 at 23 cells).
## Its people step up into the fixture row from the walking lane
## (OfficeShell.FIXTURE_ROW, WALKING_LANE). There is no reception.
##
## Not decor: the entry band is a walkway for the decor rules, and the pantry
## stands in it on purpose. Every position is a pure function of the map's
## geometry: the pantry stays at the left end when the map widens (the lift
## door moves with the main corridor), and nothing here reads who is on it.
##
## Only a map with at least one desk gets it (a lobby and an empty workspace
## have nobody to idle); a band that cannot hold the counter and one spot has
## none. The fixture row stays a barrier on every map with desks, pantry or not
## (OfficeWalkGraph).
##
## This only proposes. OfficeFloorLayout.plan() furnishes its candidate before
## the validation that plan gets, and leaves the pantry out when the furnished
## map would not validate without the furniture either.

var _pen: OfficeDraw


## `pen` measures the counter's drawing.
func _init(pen: OfficeDraw) -> void:
	_pen = pen


## Place the pantry `next` has room for. A new candidate plan can be
## furnished; a retained previous plan is immutable and never comes here.
func furnish(next: FloorPlan) -> void:
	next.pantry = null
	var grid := float(FloorLayoutPolicy.GRID)
	# A band without a fixture row and a walking lane under the wall has no room.
	if next.desks.is_empty() or next.entry_cells.size.y * grid < OfficeShell.WALKING_LANE + grid / 2.0:
		return
	var band_top := next.entry_cells.position.y * grid
	var inner_left := next.entry_cells.position.x * grid
	var row_y := band_top + OfficeShell.FIXTURE_ROW
	var lane_y := band_top + OfficeShell.WALKING_LANE
	var foot_y := band_top + OfficeShell.COUNTER_FOOT
	var pitch := OfficeShell.SPOT_PITCH
	var end := next.main_corridor_cells.position.x * grid - OfficeShell.FIXTURE_GAP
	var counter_width := OfficeDecor.footprint_of(_pen.art, ArtContract.PROP_PANTRY).x
	var spots := mini(OfficeShell.MAX_PANTRY, floori((end - inner_left) / pitch))
	if spots < 1 or inner_left + counter_width > end:
		return
	var pantry := FixturePlacement.new()
	pantry.kind = FixturePlacement.Kind.PANTRY
	pantry.key = "pantry"
	pantry.piece = ArtContract.PROP_PANTRY
	pantry.position = Vector2(inner_left + counter_width / 2.0, foot_y)
	var footprint := OfficeDecor.footprint_of(_pen.art, pantry.piece)
	pantry.footprint = Rect2(pantry.position - Vector2(footprint.x / 2.0, footprint.y), footprint)
	var sprite := _pen.art.prop_sprite(pantry.piece)
	pantry.draw_rect = Rect2(pantry.position - sprite.pivot, Vector2(sprite.size))
	for index in spots:
		var x := inner_left + pitch * (index + 0.5)
		pantry.spots.append(Vector2(x, row_y))
		pantry.approaches.append(Vector2(x, lane_y))
	next.pantry = pantry
