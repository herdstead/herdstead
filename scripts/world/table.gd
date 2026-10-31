class_name OfficeTable
extends Node2D
## One tab's measured pod and selection outline: scenes/world/table.tscn.
## Each station draws its complete workstation. The pod owns only its seat
## markers and outline, never a second desk, chair, monitor or person.
##
## The origin is the left end of the lower row's feet. "far" and "near" are
## logical upper/lower rows; both workstations face the viewer. All pod
## geometry lives here, shared by the planner and the rendered seat markers.

## Retained focus-strength type for the fleet-to-station path. The station
## renders an underline; this pod has no lamps or equipment at any level.
enum Lamp { OFF, DIM, ON, FOCUS }

const MODULE := 96
const MIN_WIDTH := 2 * MODULE
const FAR_SEAT := -128
const NEAR_SEAT := 0
const CANVAS := Rect2(-37.5, -70, 80, 80)
const SIDES := ["far", "near"]
const FRAME_OUTSIDE := 2.0
const LENS_FRAME := Color(0.3, 0.3, 0.3)

var art: ArtPack
var width := 0.0
var columns: Array[float] = []
var geometry: DeskMeasure


## Capacity is logical columns, each with two front-facing workstations.
## Growth appends columns without shifting existing feet. One 32-unit passage
## remains on the right; the column pitch is not the floor's cell size.
static func measure(capacity: int) -> DeskMeasure:
	var count := maxi(2, capacity)
	var result := DeskMeasure.new()
	result.capacity = count
	result.table_width = float(count * MODULE)
	result.physical_rect = Rect2(0, FAR_SEAT + CANVAS.position.y, result.table_width, 208)
	result.reserved_rect = Rect2(0, -224, result.table_width + FloorLayoutPolicy.GRID, 320)
	result.render_rect = Rect2(0, -200, result.table_width, 256)
	for index in count:
		var x := MODULE * 0.5 + MODULE * index
		result.columns.append(x)
		result.far_seats.append(Vector2(x, FAR_SEAT))
		result.near_seats.append(Vector2(x, NEAR_SEAT))
	return result


static func width_error(value: float) -> String:
	if not is_finite(value):
		return "table width must be finite"
	if value < MIN_WIDTH:
		return "table width %s is under %d" % [value, MIN_WIDTH]
	if fmod(value, MODULE) != 0.0:
		return "table width %s is not a multiple of %d" % [value, MODULE]
	return ""


## Build/update the measured pod, retaining every surviving seat marker and
## the selection state. Only canonical columns from measure() are accepted:
## previews and the office use the same geometry, with no alternate layout.
## A refused update leaves the previous pod untouched.
func setup(pack: ArtPack, table_width: float, seat_columns: Array) -> bool:
	var problem := width_error(table_width)
	if pack == null:
		problem = "an art pack is required"
	var typed_columns: Array[float] = []
	for value: Variant in seat_columns:
		if not (value is float or value is int):
			problem = "seat columns must be numbers"
			break
		var x: float = value
		if not is_finite(x):
			problem = "seat columns must be finite"
			break
		typed_columns.append(x)
	var measured := measure(typed_columns.size())
	if problem.is_empty() and (table_width != measured.table_width or typed_columns != measured.columns):
		problem = "width and seat columns must match measured capacity"
	if not problem.is_empty():
		push_error("OfficeTable: " + problem)
		return false
	if art == pack and width == table_width and columns == typed_columns:
		return true
	art = pack
	width = table_width
	columns.assign(typed_columns)
	geometry = measured
	var retained: Dictionary[String, bool] = {}
	for index in columns.size():
		for side: String in SIDES:
			var id := _seat_name(index, side)
			retained[id] = true
			var marker := $Seats.get_node_or_null(NodePath(id)) as Marker2D
			if marker == null:
				marker = Marker2D.new()
				marker.name = id
				$Seats.add_child(marker)
			marker.position = geometry.seat_position(index, side)
	for child in $Seats.get_children():
		if not retained.has(String(child.name)):
			$Seats.remove_child(child)
			child.free()
	_place_frame()
	return true


## Move/remove stations bound to discarded columns before shrinking.
func resize(capacity: int) -> bool:
	if art == null:
		push_error("OfficeTable: resize requires setup first")
		return false
	var measured := measure(capacity)
	return setup(art, measured.table_width, measured.columns)


## Sibling stations follow via rebind() in the same structural update.
func relocate(at: Vector2) -> bool:
	if not at.is_finite():
		push_error("OfficeTable: position must be finite")
		return false
	position = at
	return true


func has_seat(column: int, side: String) -> bool:
	return column >= 0 and column < columns.size() and side in SIDES


func seat(column: int, side: String) -> Marker2D:
	return $Seats.get_node(_seat_name(column, side))


## The semantic provider mark, if the pack supplies one. Its placement belongs
## to the station, not a separately drawn laptop or chair.
static func mark_of(pack: ArtPack, provider: String) -> ArtSprite:
	if pack == null or provider.is_empty():
		return null
	return pack.ui_sprite(ArtContract.lid_mark(provider))


func set_selected(selected: bool) -> void:
	var frame: Node2D = $Overlay/Frame
	frame.visible = selected


func set_lensed(on: bool) -> void:
	var frame: Node2D = $Overlay/Frame
	frame.modulate = LENS_FRAME if on else Color.WHITE


func _place_frame() -> void:
	var frame := geometry.render_rect.grow(FRAME_OUTSIDE)
	var bounds: Array[Rect2] = [
		Rect2(frame.position, Vector2(frame.size.x, 2)),
		Rect2(frame.position.x, frame.end.y - 2, frame.size.x, 2),
		Rect2(frame.position, Vector2(2, frame.size.y)),
		Rect2(frame.end.x - 2, frame.position.y, 2, frame.size.y),
	]
	for index in bounds.size():
		var bar: ColorRect = $Overlay/Frame.get_child(index)
		bar.position = bounds[index].position
		bar.size = bounds[index].size
		bar.color = art.color(ArtContract.BLOCKED)


func _seat_name(column: int, side: String) -> String:
	return "%s%d" % [side.capitalize(), column]


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		var overlay: Node2D = $Overlay
		overlay.z_index = OfficeWorld.OVERLAY_Z
