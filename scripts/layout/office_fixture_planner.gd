class_name OfficeFixturePlanner
extends RefCounted
## The entry band's one service fixture for a candidate map: the pantry counter
## at the band's left end, against the top wall: its footprint from the wall's
## foot line (OfficeShell.COUNTER_FOOT), in the band's one row, the walking
## lane (OfficeShell.WALKING_LANE), whose nodes in front of it it blocks: the
## lane starts beside it. A corner nook: furniture, with no spots, and nobody
## walks to it.
## There is no reception.
##
## Not decor: the entry band is a walkway for the decor rules, and the counter
## stands in it on purpose. Every position is a pure function of the map's
## geometry: the counter stays at the left end when the map widens (the lift
## door moves with the main corridor), and nothing here reads who is on it.
##
## Only a map with at least one desk gets it (an empty map and an empty workspace
## keep the shell they always had); a band of fewer than two cells, or one whose
## bay left of the main corridor is narrower than the counter, has none.
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
	# A band too shallow to hold the walking lane has no room.
	if next.desks.is_empty() or next.entry_cells.size.y * grid < OfficeShell.WALKING_LANE + grid / 2.0:
		return
	var band_top := next.entry_cells.position.y * grid
	var inner_left := next.entry_cells.position.x * grid
	var foot_y := band_top + OfficeShell.COUNTER_FOOT
	var counter_width := OfficeDecor.footprint_of(_pen.art, ArtContract.PROP_PANTRY).x
	if inner_left + counter_width > next.main_corridor_cells.position.x * grid:
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
	next.pantry = pantry
