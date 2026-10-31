extends "res://tools/test_base.gd"
## Geometry-suite helpers for complete-image workstations. Every measurement
## uses public scene nodes/properties, never the retired layered-person rig.
## No cases here; animations use the real AnimationPlayer on a manual clock,
## while interaction always enters through Input.parse_input_event().

const LONG_NAME := "a pane name longer than two complete workstation columns and their name plates"
## The approved question bubble's isolated region within a 160x160 cell.
const QUESTION_REGION := Rect2i(108, 12, 28, 24)

## Measured once from the authored pixels by the concrete suite's _run().
var frame_ink: Array[Rect2] = []
var empty_ink := Rect2()


func _body(station: OfficeStation) -> Sprite2D:
	return station.get_node("Actor/Body")


func _badge(station: OfficeStation) -> StatusBadge:
	return station.get_node("Overlay/Badge")


func _selection(station: OfficeStation) -> Line2D:
	return station.get_node("Overlay/Selection")


func _plate_of(station: OfficeStation) -> Label:
	return station.get_node("Overlay/Plate")


func _manual_player(station: OfficeStation) -> AnimationPlayer:
	var player: AnimationPlayer = station.get_node("Actor/AnimationPlayer")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return player


func _sheet_cell(index: int, family: WorkstationArt) -> Rect2i:
	var size := family.frame_size * family.density
	var cell := Vector2i(index % family.columns, floori(float(index) / family.columns))
	return Rect2i(cell * size, size)


## Whole-image ink in global coordinates, including any actual Body offset
## or transform. The cached used rectangles avoid reading back the 24-frame
## texture thousands of times during pairwise row-clearance checks.
func _drawing(station: OfficeStation) -> Rect2:
	var family := station.art.workstation
	var body := _body(station)
	var used := frame_ink[body.frame] if body.texture == family.sheet_texture() else empty_ink
	var local := Rect2((used.position + family.pivot) * family.density, used.size * family.density)
	local.position += body.get_rect().position
	return body.get_global_transform() * local


func _has_question(station: OfficeStation) -> bool:
	var body := _body(station)
	var family := station.art.workstation
	if body.texture != family.sheet_texture():
		return false
	var region := QUESTION_REGION
	region.position += _sheet_cell(body.frame, family).position
	return body.texture.get_image().get_region(region).get_used_rect().has_area()


## A Line2D's envelope, stroke included, in global coordinates.
func _line_bounds(line: Line2D) -> Rect2:
	var bounds := Rect2(line.points[0], Vector2.ZERO)
	for point in line.points:
		bounds = bounds.expand(point)
	return line.get_global_transform() * bounds.grow(line.width / 2.0)


## The pod's four selection-frame bars in global coordinates.
func _frame_bars(table: OfficeTable) -> Array[Rect2]:
	var bars: Array[Rect2] = []
	for node in table.get_node("Overlay/Frame").get_children():
		var control: Control = node
		bars.append(control.get_global_rect())
	return bars


## Same-seat intentional overlaps: the pick rectangle and selection surround
## the image, and the badge sits over the chip's left half. Nothing else may
## cover the image or collide with the plate/lens/badge rows. Different seats
## have no exceptions, including the old opposite-facing selection overlap.
static func _same_seat_clash(a: String, b: String) -> bool:
	var rows := ["plate", "lens", "badge", "chip"]
	if a in rows and b in rows:
		return not ((a == "badge" and b == "chip") or (a == "chip" and b == "badge"))
	if a == "image" and b in rows or b == "image" and a in rows:
		return true
	return (a == "seat" and b == "chip rect") or (a == "chip rect" and b == "seat")


## Drawn parts and enabled input targets only, all in global coordinates.
## Vacancies still contribute their empty image, but no name or input target.
func _seat_rows(station: OfficeStation) -> Dictionary[String, Rect2]:
	var rows: Dictionary[String, Rect2] = {"image": _drawing(station)}
	var badge := _badge(station)
	if badge.is_visible_in_tree():
		rows["badge"] = badge.get_global_transform() * _opaque_local(badge)
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	if frame.is_visible_in_tree():
		rows["chip"] = frame.get_global_rect()
	for label: String in ["Lens", "Plate"]:
		var control: Label = station.get_node("Overlay/" + label)
		if control.is_visible_in_tree():
			rows[label.to_lower()] = control.get_global_rect()
	var mark := _selection(station)
	if mark.is_visible_in_tree():
		rows["mark"] = _line_bounds(mark)
	var seat: CollisionShape2D = station.get_node("Target/Seat")
	if not seat.disabled:
		rows["seat"] = _shape_rect(seat)
	var chip: CollisionShape2D = station.get_node("Target/Chip")
	if not chip.disabled:
		rows["chip rect"] = _shape_rect(chip)
	return rows


## Move the real pointer and let physics picking observe it.
func _point(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


func _click(at: Vector2, pressed: bool) -> void:
	await _point(at)
	var click := InputEventMouseButton.new()
	click.position = at
	click.global_position = at
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	Input.parse_input_event(click)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


## Nonanimated pack sprites (badges, side-table items and partitions).
func _opaque_local(sprite: Sprite2D) -> Rect2:
	var used := Rect2(sprite.texture.get_image().get_used_rect())
	used.position += sprite.get_rect().position
	return used


## Every opaque texel of a nonanimated pack sprite in global coordinates,
## or in `into`'s, at the pack's half-unit texel resolution.
func _texels(sprite: Sprite2D, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	var image := sprite.texture.get_image()
	var used := image.get_used_rect()
	var to_world := into * sprite.get_global_transform()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var middle := to_world * (sprite.get_rect().position + Vector2(x + 0.5, y + 0.5))
			found[Vector2i(floori(middle.x * 2.0), floori(middle.y * 2.0))] = true
	return found


func _shape_rect(node: Node) -> Rect2:
	var shape: CollisionShape2D = node
	var box: RectangleShape2D = shape.shape
	return shape.get_global_transform() * Rect2(-box.size / 2.0, box.size)


func _seat_far(stations: Array[OfficeStation], far: Array[int]) -> void:
	for station in stations:
		if station.side == "near" or station.column in far:
			station.furnish("claude", ArtContract.STATE_WORKING)
			station.show_name(LONG_NAME)
		else:
			station.vacate()
		station.show_plates_always(true)
	OfficeFloorView.widen_plates(stations)


func _pod_plate(station: OfficeStation) -> Rect2:
	return station.table.global_transform.affine_inverse() * _plate_of(station).get_global_rect()


func _placement(tab_key: String, capacity: int) -> DeskPlacement:
	var placed := DeskPlacement.new()
	placed.tab_key = tab_key
	placed.capacity = capacity
	placed.measure = OfficeTable.measure(capacity)
	return placed


func _side_pane(index: int) -> PaneModel:
	var pane := PaneModel.new()
	pane.pane_id = "p%d" % index
	pane.key = "side:p%d" % index
	pane.terminal_id = "term-p%d" % index
	pane.provider = "claude"
	pane.state = "working"
	return pane


func _side_room(key: String, number: int, first: int, count: int) -> RoomModel:
	var room := RoomModel.new()
	room.key = key
	room.number = number
	room.label = key.to_upper()
	for index in count:
		room.panes.append(_side_pane(first + index))
	return room


func _side_zone(key: String, number: int, rooms: Array[RoomModel]) -> ZoneModel:
	var zone := ZoneModel.new()
	zone.key = key
	zone.number = number
	zone.label = key
	zone.rooms = rooms
	return zone


func _gap_table_of(plan: FloorPlan, key := "") -> DecorPlacement:
	for placed in plan.decorations:
		if key.is_empty() and placed.key.begins_with("00/gap/") and placed.piece == ArtContract.PROP_SIDE_TABLE:
			return placed
		if not key.is_empty() and placed.key == key:
			return placed
	return null


func _decor_node(floor_root: Node, key: String) -> OfficeDecor:
	return floor_root.find_child("Decor_" + key.replace("/", "_"), true, false) as OfficeDecor
