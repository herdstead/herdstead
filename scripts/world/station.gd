class_name OfficeStation
extends Node2D
## One generic image workstation. Both logical rows face the viewer. The
## complete frame is indivisible furniture/person art; only annotations and
## input targets are separate nodes. No outfit, walking or rig is constructed.
## A permanent Actor also draws the empty desk for a shell or a vacant slot.

signal picked(key: String, at: Vector2)
signal asked(key: String, at: Vector2)
signal chip_hovered(key: String, inside: bool)
signal seat_hovered(key: String, inside: bool)

const CANVAS := OfficeTable.CANVAS
const CHIP_SIZE := OfficeChip.SIZE
const CHIP_AT := Vector2(-15, 12)
const BADGE_AT := Vector2(0, 28)
const CHIP_BADGE_SHIFT := Vector2(-8.5, 0)
const LENS_AT := Vector2(-15, 30)
const LENS_SIZE := Vector2(30, 12)
const PLATE_SIZE := Vector2(94, OfficeDraw.PLATE_HEIGHT)
const PLATE_REST := Vector2(-47, 32)
const PLATE_AT := Vector2(-47, 44)
const PLATE_REACH := float(OfficeTable.MODULE)
const CHIP_TARGET_AT := Vector2(15, 7)
const LIGHT_ALPHA: Array[float] = [0.0, 0.15, 0.35, 1.0]

var art: ArtPack
var pen: OfficeDraw
## Logical row only: never a facing or a request for different art.
var side := "far"
var table: OfficeTable
var column := -1
var seat: Marker2D
var vacant := true
var pane_key := ""
var light_level := OfficeTable.Lamp.OFF
var _person := false
## Hovered shapes remember whether they showed a question or a pane name,
## so a state change under a still pointer can replace the right tooltip.
var _hovered: Dictionary[Node, bool] = {}
var _selected := false
var _lens_held := false
var _always := false
var _wide_left := false
var _wide_right := false


func setup(drawing: OfficeDraw, at_table: OfficeTable, at_column: int, seat_side: String) -> void:
	if drawing == null or drawing.art == null or not _valid_binding(at_table, at_column, seat_side):
		push_error("OfficeStation: setup needs an art pack and a valid table seat")
		return
	var first := pen == null
	pen = drawing
	art = drawing.art
	var body: WorkstationActor = $Actor
	var state := body.animation
	body.configure(art.workstation, body.provider)
	if _person:
		body.play_state(state)
	var plate: Label = $Overlay/Plate
	pen.style_plate(plate)
	plate.size = PLATE_SIZE
	pen.back_label(plate)
	var lens: Label = $Overlay/Lens
	pen.style_figures(lens, 8, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	lens.size = LENS_SIZE
	pen.back_label(lens)
	chip().dress(pen)
	var badge: StatusBadge = $Overlay/Badge
	badge.chip = chip()
	if first:
		badge.clear(art)
	var selection: Line2D = $Overlay/Selection
	selection.default_color = art.color(ArtContract.INK)
	rebind(at_table, at_column, seat_side)
	light(light_level)


## Moving the whole station retains its body, frame, clock and input wiring.
func rebind(at_table: OfficeTable, at_column: int, seat_side: String) -> bool:
	if art == null or not _valid_binding(at_table, at_column, seat_side):
		push_error("OfficeStation: rebind needs setup and a valid table seat")
		return false
	if get_parent() != null and at_table.get_parent() != null and get_parent() != at_table.get_parent():
		push_error("OfficeStation: table and station must share the Sorted parent")
		return false
	side = seat_side
	table = at_table
	column = at_column
	seat = table.seat(column, side)
	position = table.position + seat.position
	_place()
	return true


func _valid_binding(at_table: OfficeTable, at_column: int, seat_side: String) -> bool:
	return is_instance_valid(at_table) and at_table.has_seat(at_column, seat_side)


func furnish(
	provider: String, state: StringName, selected := false, starting := false, pane_id := "", machine := ""
) -> void:
	vacant = false
	_person = starting or not provider.is_empty()
	var body: WorkstationActor = $Actor
	body.configure(art.workstation, provider)
	if _person:
		body.play_state(&"starting" if starting else state)
	else:
		body.show_empty()
	# launch_pending + blocked is already resolved by PaneModel.launching().
	chip().visible = _person and not starting and state == ArtContract.STATE_BLOCKED
	if not chip().visible:
		chip().clear()
	var badge: StatusBadge = $Overlay/Badge
	badge.stop_pulsing()
	if _person:
		badge.show_badge(art, ArtContract.UI_STARTING if starting else art.state(state).badge)
		badge.visible = true
		if not starting:
			badge.pulse_for(machine, pane_id, state)
	else:
		badge.clear(art)
	_place()
	_pickable(true)
	select(selected)


func actor() -> WorkstationActor:
	return $Actor if _person else null


func freeze(held: bool) -> void:
	var body: WorkstationActor = $Actor
	if held:
		body.pause()
	else:
		body.play()


func show_name(text: String) -> void:
	var plate: Label = $Overlay/Plate
	if plate.text != text:
		plate.text = text
		_lay_plate()


func name_shown() -> String:
	var plate: Label = $Overlay/Plate
	return plate.text


func vacate() -> void:
	_unhover_seat()
	if chip().visible and not pane_key.is_empty():
		chip_hovered.emit(pane_key, false)
	vacant = true
	pane_key = ""
	_person = false
	var body: WorkstationActor = $Actor
	body.provider = ""
	body.show_empty()
	light(OfficeTable.Lamp.OFF)
	chip().visible = false
	chip().clear()
	var plate: Label = $Overlay/Plate
	plate.text = ""
	_hovered.clear()
	var lens: Label = $Overlay/Lens
	lens.visible = false
	var badge: StatusBadge = $Overlay/Badge
	badge.clear(art)
	_place()
	_pickable(false)
	select(false)


func show_lens(held: bool, text: String) -> void:
	var line: Label = $Overlay/Lens
	if held and line.text != text:
		line.text = text
		_lay_lens()
	line.visible = held and not vacant and not text.is_empty()
	_lens_held = held
	chip().set_lensed(held)
	_lay_plate()
	_show_plate()


func select(selected: bool) -> void:
	var mark: Line2D = $Overlay/Selection
	mark.visible = selected and not vacant
	_selected = selected
	_show_plate()


func plate_shown() -> bool:
	return not vacant and (_always or not _hovered.is_empty() or _selected or _lens_held)


func show_plates_always(always: bool) -> void:
	if _always == always:
		return
	_always = always
	_show_plate()


func widen_plate(left: bool, right: bool) -> void:
	if _wide_left == left and _wide_right == right:
		return
	_wide_left = left
	_wide_right = right
	_lay_plate()


func plate_row() -> Rect2:
	var row := Rect2(_plate_at(), PLATE_SIZE)
	if _wide_left and _wide_right:
		return row.grow_individual(PLATE_REACH / 2.0, 0, PLATE_REACH / 2.0, 0)
	if _wide_left:
		return row.grow_side(SIDE_LEFT, PLATE_REACH)
	if _wide_right:
		return row.grow_side(SIDE_RIGHT, PLATE_REACH)
	return row


func _plate_at() -> Vector2:
	return PLATE_AT if _lens_held else PLATE_REST


func _lay_plate() -> void:
	var plate: Label = $Overlay/Plate
	if pen != null:
		pen.hug(plate, plate_row(), _plate_at().x + PLATE_SIZE.x / 2.0)


func _lay_lens() -> void:
	var lens: Label = $Overlay/Lens
	if pen != null:
		pen.hug(lens, Rect2(LENS_AT, LENS_SIZE))


func _show_plate() -> void:
	var plate: Label = $Overlay/Plate
	plate.visible = plate_shown()


## Herdr focus, independent of Herdstead selection. A narrow floor underline
## replaces the old lamp wedge; it never dims the person like an outage.
func light(level: OfficeTable.Lamp) -> void:
	light_level = level
	var line: Polygon2D = $Focus
	line.visible = level != OfficeTable.Lamp.OFF
	var color := art.color(ArtContract.TASK_LIGHT)
	color.a = LIGHT_ALPHA[level]
	line.color = color


func chip() -> OfficeChip:
	return $Overlay/Chip


func chip_rect() -> Rect2:
	var shown := chip()
	return Rect2(shown.global_position, CHIP_SIZE) if shown.visible else Rect2()


func target_rect() -> Rect2:
	return Rect2(global_position + CANVAS.position, CANVAS.size)


## The camera and pointer keep the name, badge and lens row with the image.
## Reserve the same rows in every state so the view does not jump on a refresh.
func signal_rect() -> Rect2:
	var top := Vector2(PLATE_REST.x, CANVAS.position.y)
	var size := Vector2(PLATE_SIZE.x, PLATE_AT.y + PLATE_SIZE.y - top.y)
	return Rect2(global_position + top, size)


func _on_target_input_event(_viewport: Node, event: InputEvent, shape_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var click: InputEventMouseButton = event
	if click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var hit := _shape_at(shape_index)
	if hit == get_node(^"Target/Chip") and chip().visible:
		asked.emit(pane_key, click.position)
	else:
		picked.emit(pane_key, click.position)


func _on_target_mouse_shape_entered(shape_index: int) -> void:
	var shape := _shape_at(shape_index)
	var question := shape == get_node(^"Target/Chip") and chip().visible
	_hovered[shape] = question
	_show_plate()
	_hover(question, true)


func _on_target_mouse_shape_exited(shape_index: int) -> void:
	var shape := _shape_at(shape_index)
	if not _hovered.has(shape):
		return
	var question := _hovered[shape]
	_hovered.erase(shape)
	_show_plate()
	_hover(question, false)


func _hover(question: bool, inside: bool) -> void:
	if pane_key.is_empty():
		return
	if question:
		chip_hovered.emit(pane_key, inside)
	else:
		seat_hovered.emit(pane_key, inside)


func _unhover_seat() -> void:
	if _hovered.values().has(false):
		_hover(false, false)


func _shape_at(shape_index: int) -> Node:
	var target: Area2D = $Target
	return target.shape_owner_get_owner(target.shape_find_owner(shape_index))


func _pickable(can_pick: bool) -> void:
	var target: Area2D = $Target
	target.input_pickable = can_pick
	var body: CollisionShape2D = $Target/Seat
	body.disabled = not can_pick
	if not can_pick:
		_unhover_seat()
		_hovered.clear()
		_show_plate()


func _place() -> void:
	_lay_plate()
	_lay_lens()
	chip().position = CHIP_AT
	var target: CollisionShape2D = $Target/Chip
	target.position = CHIP_AT + CHIP_TARGET_AT
	# The same tag-row target also picks a non-blocked agent's badge; only
	# a visible question chip asks to enter answer mode. Shells have no tag.
	var badge: StatusBadge = $Overlay/Badge
	target.disabled = vacant or not badge.visible
	if _hovered.has(target) and (target.disabled or _hovered[target] != chip().visible):
		_hover(_hovered[target], false)
		_hovered.erase(target)
		if not target.disabled:
			_hovered[target] = chip().visible
			_hover(chip().visible, true)
	_place_badge()
	_show_plate()


func _place_badge() -> void:
	var badge: StatusBadge = $Overlay/Badge
	badge.position = BADGE_AT + (CHIP_BADGE_SHIFT if chip().visible and chip().framed() else Vector2.ZERO)


func _on_chip_framed(_framed: bool) -> void:
	_place_badge()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		var overlay: Node2D = $Overlay
		overlay.z_index = OfficeWorld.OVERLAY_Z
		var target: Area2D = $Target
		target.collision_layer = OfficeWorld.PICKABLE
