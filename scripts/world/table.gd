class_name OfficeTable
extends StaticBody2D
## One shared table: scenes/world/table.tscn. A tab of herdr is one of these.
##
## The origin is the LEFT END OF THE NEAR EDGE, so the table y-sorts as one
## piece at the edge nearest the viewer and x runs 0..width along it. The table
## itself is not y-sorted: what stands on it is its children, drawn in tree
## order (supports, surface, apron, grommets, task lights, far monitors,
## divider, near monitors, decorations, papers), so nothing on the table needs
## a depth rule.
##
## Every seat gets its monitor, its grommet, its task lamp and its stack of
## paper when the table is built, and what a seat carries afterwards is only
## which of them are shown and how hard the lamp burns: equip(), light() and
## show_papers() never add or drop a node.
##
## Every number about the table's cross-section lives here and nowhere else.
## y is table-local: the near edge is 0, the far edge is -SURFACE_DEPTH.

## How hard one seat's task lamp burns. A seat with no pane is OFF; the other
## three say what herdr is doing with the terminal on it, and who gets which is
## OfficeFloorView.lamp_of()'s to decide.
enum Lamp { OFF, DIM, ON, FOCUS }

const MODULE := 32
const MIN_WIDTH := 160
const SURFACE_DEPTH := 80
## The painted surface ends at -5; its three-unit lip joins this three-unit
## apron. The working top still ends at -8, so equipment need not move.
const NEAR_SURFACE_EDGE := -8
const APRON_HEIGHT := 3
const APRON_DROP := -5
## Below the far edge: a far worker's feet are inside the table's footprint,
## so the table (sorted at its near edge, drawn later) hides their legs.
const FAR_SEAT := 12
## Below the near edge: a near worker is wholly in front of the apron.
const NEAR_SEAT := 22
## The cell beside a seat that the near seat's leg turns round the chair at
## (OfficeWalkGraph.leg_to_seat(); DeskMeasure calls it the standing spot).
## Nobody stands there: done agents sit with their paper, and these numbers
## stay so no floor is planned differently. Beside
## the seat column, clear of the chair; the far one FAR_STAND above the far
## edge, off the table's footprint; the near one at the seat's depth.
const STAND_ASIDE := 24
const FAR_STAND := 6
const NEAR_STAND := NEAR_SEAT
## A laptop belongs at the sitter's edge, not by the divider like a monitor.
## The rear view ends at its hinge; the front view ends at its palmrest, just
## inside the near working edge. Both stay on the seat's x.
const FAR_LAPTOP_INSET := 8
const NEAR_LAPTOP_INSET := 10
## Divider's top below the far edge, and its height.
const DIVIDER_TOP := 28
const DIVIDER_HEIGHT := 24
## A task-light wedge: narrow at the lamp, wide where it spreads.
const LAMP_HALF_WIDTH := 9.0
const LIGHT_HALF_WIDTH := 28.0
## The alpha of that wedge at each Lamp level, on a daylight pack, in enum
## order. Picked by looking at both packs at zoom 2 and 3: FOCUS reads as a lit
## lamp across the floor, ON and DIM are a step apart on the wood, and DIM is
## still plainly a lamp rather than the whole-floor dimming of a lost machine.
## How much the selection frame darkens under the lens (set_lensed()).
const LENS_FRAME := Color(0.3, 0.3, 0.3)
const LAMP_ALPHA: Array[float] = [0.0, 0.10, 0.22, 0.52]
## A lamp-lit studio pack draws all four this much harder, the same way it
## draws the contact shadows harder. The pack says which it is; nothing here
## knows a theme's name.
const LAMP_STRONG := 1.4
## A station's chair relative to its seat: the far chair (front view) sorts
## just behind its worker, the near chair (back view) in front. The painted
## office chair is 22 units tall; a small offset leaves the upper back clear.
const CHAIR_OFFSET := {"far": -4, "near": 6}
## The selection frame encloses the whole workstation island (both rows of
## workers with their plates and badges), so it never crosses a seated worker.
const FRAME_ABOVE_FAR := 70
const FRAME_BELOW_NEAR := 70
## Where the three legs stand and where a bracket hangs, below the near edge.
## The taller native leg reaches the same floor y=37 from its lifted mount.
const LEG_DROP := -2
const BRACKET_DROP := -11
const SIDES := ["far", "near"]
## Static objects sit left of a laptop, entirely on one working plane. The
## occasional cat uses the first near slot, independent of table capacity.
const DECOR_OFFSET := -28
const DECOR_FAR := -55
const DECOR_NEAR := -9
## A done seat's stack of paper (ArtContract.PROP_DONE_STACK) stands this far
## right of the seat column, on the same working plane as the decorations
## (DECOR_FAR or DECOR_NEAR). Measured: the laptop is opaque over x-7..x+6
## and the stack, 11 wide, over x+10.5..x+21.5, so it stands just right of the
## laptop, clear of the worker (x±10; the figure itself is x±8) and of the next
## column's decoration, whose leftmost opaque pixel is at x+27. The left of the
## laptop is the decoration slot, which never changes with state.
const PAPERS_ASIDE := 16

var art: ArtPack
var width := 0.0
## Seat columns, x along the near edge.
var columns: Array[float] = []
## Current measured geometry; setup() also supports the legacy preview columns.
var geometry: DeskMeasure
## How many times a lamp was drawn (_apply_light()): a diagnostic, never a
## decision, so a test can prove a quiet refresh redraws no lamp.
var lamps_drawn := 0
var _lamp_levels: Dictionary[String, Lamp] = {}
var _shell_seats: Dictionary[String, bool] = {}
var _shadow_holder: Node2D
var _decoration_identity := ""


## The planner and renderer share these dimensions. Capacity is columns, with
## one seat on each side. Growth appends columns without shifting old seats.
static func measure(capacity: int) -> DeskMeasure:
	var count := maxi(2, capacity)
	var seat_columns: Array[float] = []
	for index in count:
		seat_columns.append(MODULE * 1.5 + MODULE * 2.0 * index)
	return _measure_columns(maxf(MIN_WIDTH, count * MODULE * 2.0 + MODULE), seat_columns)


static func _measure_columns(table_width: float, seat_columns: Array[float]) -> DeskMeasure:
	var result := DeskMeasure.new()
	result.capacity = seat_columns.size()
	result.table_width = table_width
	result.columns.assign(seat_columns)
	result.physical_rect = Rect2(0, -SURFACE_DEPTH, table_width, SURFACE_DEPTH)
	# Includes side passages and full-body clearance behind the far approaches.
	result.reserved_rect = Rect2(-MODULE, -6 * MODULE, table_width + 2 * MODULE, 9 * MODULE)
	result.render_rect = Rect2(
		-8, -SURFACE_DEPTH - FRAME_ABOVE_FAR, table_width + 16, FRAME_ABOVE_FAR + SURFACE_DEPTH + FRAME_BELOW_NEAR + 2
	)
	for x in seat_columns:
		result.far_seats.append(Vector2(x, -SURFACE_DEPTH + FAR_SEAT))
		result.near_seats.append(Vector2(x, NEAR_SEAT))
		result.far_standing.append(Vector2(x + STAND_ASIDE, -SURFACE_DEPTH - FAR_STAND))
		result.near_standing.append(Vector2(x + STAND_ASIDE, NEAR_STAND))
		result.far_approaches.append(Vector2(x, -SURFACE_DEPTH - MODULE))
		result.near_approaches.append(Vector2(x, MODULE * 1.5))
	return result


## Why a table this wide cannot be built; empty when it can. The surface is
## made of whole 32-unit modules and needs both end caps plus a middle.
static func width_error(value: float) -> String:
	if not is_finite(value):
		return "table width must be finite"
	if value < MIN_WIDTH:
		return "table width %s is under %d" % [value, MIN_WIDTH]
	if fmod(value, MODULE) != 0.0:
		return "table width %s is not a multiple of %d" % [value, MODULE]
	return ""


## Build or update a table, retaining existing seats and their equipment.
## A failed validation leaves the previous table unchanged. Calling this again
## with the same arguments is a no-op, including lamp and selection state.
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
		if not is_finite(x) or x < 0 or x > table_width or x in typed_columns:
			problem = "seat columns must be finite, unique and inside the table"
			break
		typed_columns.append(x)
	if not problem.is_empty():
		push_error("OfficeTable: " + problem)
		return false
	if art == pack and width == table_width and columns == typed_columns:
		_sync_shadows()
		return true
	art = pack
	width = table_width
	columns.assign(typed_columns)
	geometry = _measure_columns(width, columns)
	_rebuild_modules()
	var retained: Dictionary[String, bool] = {}
	for index in columns.size():
		for side: String in SIDES:
			retained[_seat_name(index, side)] = true
			_sync_seat(index, side)
	for holder: Node in [$Grommets, $TaskLights, $FarMonitors, $NearMonitors, $Papers, $Seats, $Standing]:
		for child in holder.get_children():
			if not retained.has(String(child.name)):
				_lamp_levels.erase(String(child.name))
				_shell_seats.erase(String(child.name))
				holder.remove_child(child)
				child.free()
	var shape: CollisionShape2D = $Footprint
	var footprint := shape.shape as RectangleShape2D
	if footprint == null:
		footprint = RectangleShape2D.new()
		shape.shape = footprint
	footprint.size = geometry.physical_rect.size
	shape.position = geometry.physical_rect.get_center()
	_sync_decorations()
	_sync_shadows()
	return true


## Choose a static arrangement after setup(), using the table's stable identity
## (including machine in live floors). No pane, status, focus or clock is read.
func decorate(identity: String) -> void:
	_decoration_identity = identity
	_sync_decorations()


func _sync_decorations() -> void:
	if _decoration_identity.is_empty():
		return
	var holder: Node2D = %Decorations
	var retained: Array[StringName] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _decoration_identity.hash()
	var has_cat := not columns.is_empty() and rng.randf() < 0.28
	if has_cat:
		var cat := ArtContract.DESK_CATS[rng.randi_range(0, ArtContract.DESK_CATS.size() - 1)]
		_decoration(&"Cat", cat, Vector2(columns[0] + DECOR_OFFSET, DECOR_NEAR))
		retained.append(&"Cat")
	for index in columns.size():
		# A separate stream per column keeps all old choices when a desk grows.
		rng.seed = ("%s:%d" % [_decoration_identity, index]).hash()
		if rng.randf() >= 0.75:
			continue
		var item := ArtContract.DESK_ITEMS[rng.randi_range(0, ArtContract.DESK_ITEMS.size() - 1)]
		var far := rng.randi_range(0, 1) == 0 or (has_cat and index == 0)
		var id := StringName("Item%d" % index)
		_decoration(id, item, Vector2(columns[index] + DECOR_OFFSET, DECOR_FAR if far else DECOR_NEAR))
		retained.append(id)
	for child in holder.get_children():
		if child.name not in retained:
			holder.remove_child(child)
			child.free()


func _decoration(id: StringName, prop_id: StringName, at: Vector2) -> void:
	var holder: Node2D = %Decorations
	var spec := art.prop_sprite(prop_id)
	var image := holder.get_node_or_null(NodePath(id)) as Sprite2D
	if image == null:
		image = art.sprite(spec)
		image.name = id
		holder.add_child(image)
	else:
		art.dress(image, art.sprite_texture(spec), spec.pivot)
	image.position = at


## Change capacity without replacing this table or any retained seat marker.
## Callers must move/remove stations bound to discarded columns before shrinking.
func resize(capacity: int) -> bool:
	if art == null:
		push_error("OfficeTable: resize requires setup first")
		return false
	var measured := measure(capacity)
	return setup(art, measured.table_width, measured.columns)


## Absolute placement in the shared Sorted parent. Ground shadows move with it;
## sibling stations follow when their owner calls rebind() in the same update.
func relocate(at: Vector2) -> bool:
	if not at.is_finite():
		push_error("OfficeTable: position must be finite")
		return false
	position = at
	_sync_shadows()
	return true


func has_seat(column: int, side: String) -> bool:
	return column >= 0 and column < columns.size() and side in SIDES


func _rebuild_modules() -> void:
	for holder: Node in [$Supports, $Surface, $Apron, $Divider, $Overlay/Frame]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.free()
	var count := int(width / MODULE)
	var far := -SURFACE_DEPTH
	for index in count:
		var end := "left" if index == 0 else "right" if index == count - 1 else "mid"
		var grain := "surface_" + end if end != "mid" else "surface_mid_b" if index % 2 == 1 else "surface_mid_a"
		_module($Surface, StringName(grain), Vector2(index * MODULE, far))
		_module($Apron, StringName("apron_" + end), Vector2(index * MODULE, APRON_DROP))
		_module($Divider, StringName("divider_" + end), Vector2(index * MODULE, far + DIVIDER_TOP))
	for leg_x: float in [10.0, width / 2 - 10, width - 30]:
		_module($Supports, &"leg", Vector2(leg_x, LEG_DROP))
	for x in columns:
		_module($Supports, &"bracket", Vector2(x - 6, BRACKET_DROP))
	var frame := geometry.render_rect
	for bounds: Rect2 in [
		Rect2(frame.position, Vector2(frame.size.x, 2)),
		Rect2(frame.position.x, frame.end.y - 2, frame.size.x, 2),
		Rect2(frame.position, Vector2(2, frame.size.y)),
		Rect2(frame.end.x - 2, frame.position.y, 2, frame.size.y),
	]:
		_rect($Overlay/Frame, bounds, art.color(ArtContract.BLOCKED))


func _sync_seat(index: int, side: String) -> void:
	var id := _seat_name(index, side)
	var is_far := side == "far"
	var x := columns[index]
	var foot := Vector2(x, -SURFACE_DEPTH + FAR_LAPTOP_INSET if is_far else -NEAR_LAPTOP_INSET)
	var monitors: Node = $FarMonitors if is_far else $NearMonitors
	var screen := monitors.get_node_or_null(NodePath(id)) as Sprite2D
	var occupied := screen != null and screen.visible
	if screen == null:
		screen = Sprite2D.new()
		screen.name = id
		monitors.add_child(screen)
	screen.position = foot
	var grommet := $Grommets.get_node_or_null(NodePath(id)) as Node2D
	if grommet == null:
		grommet = Node2D.new()
		grommet.name = id
		$Grommets.add_child(grommet)
		_rect(grommet, Rect2(-2, -2, 4, 4), art.color(ArtContract.INK))
		_rect(grommet, Rect2(-1, -1, 2, 2), art.color(ArtContract.MUTED))
	grommet.position = foot
	var outer: ColorRect = grommet.get_child(0)
	var inner: ColorRect = grommet.get_child(1)
	outer.color = art.color(ArtContract.INK)
	inner.color = art.color(ArtContract.MUTED)
	var lamp := $TaskLights.get_node_or_null(NodePath(id)) as Polygon2D
	if lamp == null:
		lamp = Polygon2D.new()
		lamp.name = id
		$TaskLights.add_child(lamp)
	var from_y := float(-SURFACE_DEPTH + DIVIDER_TOP + (0 if is_far else DIVIDER_HEIGHT))
	var to_y := float(-SURFACE_DEPTH if is_far else NEAR_SURFACE_EDGE)
	lamp.polygon = _lamp(x, from_y, to_y)
	var stack := $Papers.get_node_or_null(NodePath(id)) as Sprite2D
	var spec := art.prop_sprite(ArtContract.PROP_DONE_STACK)
	if stack == null:
		stack = art.sprite(spec)
		stack.name = id
		stack.visible = false
		$Papers.add_child(stack)
	else:
		art.dress(stack, art.sprite_texture(spec), spec.pivot)
	stack.position = Vector2(x + PAPERS_ASIDE, DECOR_FAR if is_far else DECOR_NEAR)
	_sync_marker($Seats, id, geometry.seat_position(index, side))
	_sync_marker($Standing, id, geometry.standing_position(index, side))
	var shell: bool = _shell_seats.get(id, false)
	equip(index, side, occupied, shell)
	var level: Lamp = _lamp_levels.get(id, Lamp.OFF)
	_apply_light(index, side, level)


func _sync_marker(holder: Node, id: String, at: Vector2) -> void:
	var marker := holder.get_node_or_null(NodePath(id)) as Marker2D
	if marker == null:
		marker = Marker2D.new()
		marker.name = id
		holder.add_child(marker)
	marker.position = at


## The seat of a column on one side, `side` being "far" or "near".
func seat(column: int, side: String) -> Marker2D:
	return $Seats.get_node(_seat_name(column, side))


## The cell beside that seat its near leg turns at (see STAND_ASIDE), `side`
## being "far" or "near".
func standing(column: int, side: String) -> Marker2D:
	return $Standing.get_node(_seat_name(column, side))


## The terminal on that seat. Where a monitor hangs is this table's business,
## so whoever wants to know asks here rather than walking the tree.
func monitor(column: int, side: String) -> Sprite2D:
	var monitors: Node = $FarMonitors if side == "far" else $NearMonitors
	return monitors.get_node(_seat_name(column, side))


## The patch of light that seat's task lamp throws on the wood.
func task_light(column: int, side: String) -> Polygon2D:
	return $TaskLights.get_node(_seat_name(column, side))


## Whether that seat carries a terminal: a herdr pane is one, and a seat with no
## pane has neither a laptop nor a grommet for its cable. Shells use a static
## terminal prompt on the screen/lid; starting and done agents are not shells.
## Only dresses existing equipment, so changing occupants never adds nodes.
func equip(column: int, side: String, has_pane: bool, shell := false) -> void:
	var is_shell := has_pane and shell
	_shell_seats[_seat_name(column, side)] = is_shell
	var view := ArtContract.MONITOR_REAR if side == "far" else ArtContract.MONITOR_FRONT
	if is_shell:
		view = ArtContract.SHELL_REAR if side == "far" else ArtContract.SHELL_FRONT
	var chosen := art.table.piece(ArtContract.FURNITURE_MONITOR)
	var screen := monitor(column, side)
	art.table.dress(screen, art.table.module_texture(chosen.view(view)), chosen.pivot)
	screen.visible = has_pane
	var grommet: Node2D = $Grommets.get_node(_seat_name(column, side))
	grommet.visible = has_pane


## Show that seat's stack of paper, or hide it: herdr says its agent is done
## and nobody has looked yet. Same rule as equip(): the stack is already there.
func show_papers(column: int, side: String, shown: bool) -> void:
	papers(column, side).visible = shown


## The stack of paper on that seat's side of the table (shown or not).
func papers(column: int, side: String) -> Sprite2D:
	return $Papers.get_node(_seat_name(column, side))


## Burn that seat's task lamp at `level`. Same rule as equip(): the wedge is
## already there, this only says how hard it is drawn. A lamp already at
## `level` is left as it is: every refresh asks this of every seat.
func light(column: int, side: String, level: Lamp) -> void:
	var id := _seat_name(column, side)
	if _lamp_levels.has(id) and _lamp_levels[id] == level:
		return
	_apply_light(column, side, level)


## Draw that seat's lamp at `level` whatever it was: light() for a change, and
## _sync_seat() for a seat it has just (re)built, whose wedge may be new.
func _apply_light(column: int, side: String, level: Lamp) -> void:
	lamps_drawn += 1
	_lamp_levels[_seat_name(column, side)] = level
	var lit := task_light(column, side)
	lit.visible = level != Lamp.OFF
	lit.color = lamp_color(level)


## The colour a task lamp is drawn in at `level`: the pack's own task-light
## colour, at this level's alpha, harder on a lamp-lit pack than a daylight one.
func lamp_color(level: Lamp) -> Color:
	var color := art.color(ArtContract.TASK_LIGHT)
	color.a = LAMP_ALPHA[level] * (LAMP_STRONG if _strong_lights() else 1.0)
	return color


## Show or hide the four-bar selection frame around the table.
func set_selected(selected: bool) -> void:
	var frame: Node2D = $Overlay/Frame
	frame.visible = selected


## Under the lens the rug is washed, a blocked one in the frame's own colour:
## the frame darkens by LENS_FRAME so the pick still reads on it (same shape,
## same meaning), and is exactly as before once the lens is let go.
func set_lensed(on: bool) -> void:
	var frame: Node2D = $Overlay/Frame
	frame.modulate = LENS_FRAME if on else Color.WHITE


## Ground-only contact shadows owned by this table. Repeated calls reuse the
## holder; a replacement ground (for a rebuilt rug/sign group) safely adopts it.
func contact_shadows(ground: Node2D) -> void:
	if not is_instance_valid(ground):
		push_error("OfficeTable: contact shadows need a ground node")
		return
	if not is_instance_valid(_shadow_holder):
		_shadow_holder = Node2D.new()
		_shadow_holder.name = "SeatContacts"
	if _shadow_holder.get_parent() != ground:
		if _shadow_holder.get_parent() != null:
			_shadow_holder.get_parent().remove_child(_shadow_holder)
		ground.add_child(_shadow_holder)
	_sync_shadows()


func _sync_shadows() -> void:
	if not is_instance_valid(_shadow_holder):
		return
	var ground := _shadow_holder.get_parent() as Node2D
	if ground == null:
		return
	# Shared floor parents may themselves be translated; no assumption that a
	# per-table Ground subgroup has an identity transform.
	if is_inside_tree() and ground.is_inside_tree():
		_shadow_holder.transform = ground.global_transform.affine_inverse() * global_transform
	else:
		_shadow_holder.position = position - ground.position
	var color := art.color(ArtContract.CONTACT_SHADOW)
	color.a = 0.26 if _strong_lights() else 0.12
	while _shadow_holder.get_child_count() > columns.size():
		var surplus := _shadow_holder.get_child(_shadow_holder.get_child_count() - 1)
		_shadow_holder.remove_child(surplus)
		surplus.free()
	for index in columns.size():
		var shadow: Polygon2D
		if index < _shadow_holder.get_child_count():
			shadow = _shadow_holder.get_child(index)
		else:
			shadow = Polygon2D.new()
			shadow.name = "SeatContact%d" % index
			_shadow_holder.add_child(shadow)
		var center := seat(index, "near").position + Vector2(0, CHAIR_OFFSET.near)
		var points := PackedVector2Array()
		for step in 16:
			var angle := TAU * step / 16.0
			points.append(center + Vector2(cos(angle) * 12.0, sin(angle) * 3.0))
		shadow.polygon = points
		shadow.color = color


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_shadow_holder):
		_shadow_holder.free()
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		collision_layer = OfficeWorld.FURNITURE
		var overlay: Node2D = $Overlay
		overlay.z_index = OfficeWorld.OVERLAY_Z


func _module(parent: Node, id: StringName, at: Vector2) -> Sprite2D:
	var result := art.table.module_sprite(id)
	result.position = at
	parent.add_child(result, true)
	return result


func _rect(parent: Node, bounds: Rect2, color: Color) -> void:
	var result := ColorRect.new()
	result.position = bounds.position
	result.size = bounds.size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)


## A wedge from the lamp end `from_y` (narrow) to `to_y` (wide) around column
## x, kept within the surface's width.
func _lamp(x: float, from_y: float, to_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: Array in [
		[-LAMP_HALF_WIDTH, from_y], [LAMP_HALF_WIDTH, from_y], [LIGHT_HALF_WIDTH, to_y], [-LIGHT_HALF_WIDTH, to_y]
	]:
		var half: float = corner[0]
		var edge: float = corner[1]
		points.append(Vector2(clampf(x + half, 0.0, width), edge))
	return points


## What every part of one seat is called inside the table: its marker, its
## monitor, its grommet, its task lamp and its paper all answer to this.
func _seat_name(column: int, side: String) -> String:
	return "%s%d" % [side.capitalize(), column]


## A lamp-lit studio pack draws its task lights and contact shadows harder than
## a daylight one. The pack says which it is; nothing here knows a theme's name.
func _strong_lights() -> bool:
	return art.task_lights == ArtPack.TASK_LIGHTS_STRONG
