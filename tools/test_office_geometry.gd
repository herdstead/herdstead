extends "res://tools/test_base.gd"
## Public workstation geometry and identity across repeated placement.

## How much of a near task lamp's wedge stays in sight on each side of whoever
## sits at it, in half-unit texels (four to a square unit). Measured: 248 on
## each side of a sitter (of the wedge's 650 a side; the laptop alone, with
## nobody over the desk, leaves 342), 146 on the right of one with a hand up.
const NEAR_LAMP_IN_SIGHT := 140

var art: ArtPack
var pen: OfficeDraw
var world: Node2D
var ground: Node2D
var sorted: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 960)
	root.physics_object_picking = true
	art = ArtPack.from_manifest("res://assets/daylight/manifest.json")
	if art == null:
		print("TEST_HARNESS_ERROR: office geometry has no art pack")
		quit(2)
		return
	pen = OfficeDraw.new(art)
	await run_cases()


func _marker() -> String:
	return "OFFICE GEOMETRY TESTS"


func _after_case() -> void:
	if is_instance_valid(world):
		world.free()


## The smallest pod, measured the way the office measures it (two desks).
func _table() -> OfficeTable:
	world = Node2D.new()
	ground = Node2D.new()
	sorted = Node2D.new()
	world.add_child(ground)
	world.add_child(sorted)
	root.add_child(world)
	var measured := OfficeTable.measure(2)
	return pen.table(sorted, ground, "Measured", Vector2(160, 240), measured.table_width, measured.columns)


func test_repeated_table_setup_is_idempotent() -> void:
	var table := _table()
	var count := table.find_children("*", "", true, false).size()
	var first := table.seat(0, "far")
	table.equip(0, "far", true)
	table.light(0, "far", OfficeTable.Lamp.FOCUS)
	_check(table.setup(art, 64, [16.0, 48.0]), "same setup succeeds")
	_eq(table.find_children("*", "", true, false).size(), count, "same setup adds no nodes")
	_eq(table.seat(0, "far"), first, "existing seat marker remains valid")
	_check(table.monitor(0, "far").visible, "same setup keeps the occupied monitor")
	_eq(table.task_light(0, "far").color, table.lamp_color(OfficeTable.Lamp.FOCUS), "same setup keeps lamp")


func test_repeated_station_setup_does_not_drift_the_click_targets() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "far")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	var target := station.target_rect()
	var bubble := station.chip_rect()
	var bubble_shape: CollisionShape2D = station.get_node(OfficeStation.CHIP_TARGET)
	var shape_at := bubble_shape.global_position
	var worker := station.actor()
	_check(bubble.has_area(), "a blocked seat has a bubble")
	station.setup(pen, table, 0, "far")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	_eq(station.target_rect(), target, "same setup keeps the seat's click target")
	_eq(station.chip_rect(), bubble, "and the bubble")
	_eq(bubble_shape.global_position, shape_at, "and the bubble's click target")
	_eq(station.actor(), worker, "same setup keeps worker node")


func test_measure_is_the_capacity_and_clearance_contract() -> void:
	# A pod of single desks (docs/WORLD_MODEL.md): one 32-unit desk per column,
	# a 48-deep desktop, six reserved cells from the far approach row to the
	# near one with a passage cell on the right, and the stationary drawing from
	# the far tag row's pulse envelope (-90) to the near one's foot (32: the near
	# seat is 8 below the near edge, at the near working plane).
	var minimum := OfficeTable.measure(0)
	_eq(minimum.capacity, 2, "even an empty tab reserves two columns")
	_eq(minimum.table_width, 64.0, "minimum pod width: two desks")
	for capacity in range(2, 17):
		var measured := OfficeTable.measure(capacity)
		_eq(measured.columns.size(), capacity, "one x coordinate per column")
		_eq(measured.table_width, capacity * 32.0, "one 32-unit desk per column")
		_eq(measured.physical_rect, Rect2(0, -48, measured.table_width, 48), "physical desktop only")
		_eq(measured.reserved_rect, Rect2(0, -128, measured.table_width + 32, 192), "walk and drawing reserve")
		_eq(measured.render_rect, Rect2(0, -90, measured.table_width, 122), "the stationary drawing")
		_check(measured.reserved_rect.encloses(measured.render_rect), "all stationary drawing fits reservation")
		for index in capacity:
			_eq(measured.columns[index], 16.0 + 32.0 * index, "growth never recenters an existing column")
			_eq(measured.seat_position(index, "far"), Vector2(16.0 + 32.0 * index, -36), "far seat")
			_eq(measured.seat_position(index, "near"), Vector2(16.0 + 32.0 * index, 8), "near seat")
			_eq(measured.approach_position(index, "far"), Vector2(16.0 + 32.0 * index, -80), "far approach")
			_eq(measured.approach_position(index, "near"), Vector2(16.0 + 32.0 * index, 48), "near approach")
			for side: String in OfficeTable.SIDES:
				_check(measured.has_seat(index, side), "both sides of a measured column exist")
				_check(measured.reserved_rect.has_point(measured.standing_position(index, side)), "standing fits")
				var approach := measured.approach_position(index, side)
				_check(measured.reserved_rect.has_point(approach), "approach is inside the reserved island")
				_check(not measured.physical_rect.has_point(approach), "approach is outside the physical table")
	_check(not minimum.has_seat(2, "far") and not minimum.has_seat(0, "other"), "invalid seats are absent")
	_eq(minimum.seat_position(-1, "far"), Vector2.INF, "invalid position has an explicit sentinel")


func test_thin_front_joins_supports_without_moving_the_floor() -> void:
	var table := _table()
	_eq(art.table.apron_height, 3, "three-unit apron complements the three-unit lip")
	for child in table.get_node("Apron").get_children():
		var apron := child as Sprite2D
		_eq(apron.position.y, -5.0, "apron directly follows the painted surface")
		_eq(apron.position.y + apron.get_rect().size.y * apron.scale.y, -2.0, "thin front ends at -2")
	# No legs: the supports are one bracket under each desk and nothing else.
	_check(table.resize(4), "a pod with middle columns")
	var brackets: Array[float] = []
	for child in table.get_node("Supports").get_children():
		var support := child as Sprite2D
		_eq(support.texture, art.table.module_texture(&"bracket"), "every support is a bracket")
		brackets.append(support.position.x + 6.0)
		_eq(support.position.y, -11.0, "hung under the apron")
	brackets.sort()
	_eq(brackets, table.columns, "one bracket under each column")
	for index in table.columns.size():
		for point in table.task_light(index, "near").polygon:
			_check(point.y <= -8.0, "near light stops on the working top, not below the thin edge")


## The desk decor's pools stand on side tables now (the pod carries none): a
## lane gap's side table carries one piece picked by its placement key, and
## that piece survives growth elsewhere (the pod in the lane above it growing
## wider, the zone in the next lane growing down and deepening the map: the
## same node, the same piece, where it stood), state updates at every seat, and
## a rebuild in another theme (the same semantic piece, drawn from that pack).
## It replaces test_desktop_decor_survives_growth_state_updates_and_theme_rebuilds;
## lane B1 stood it in a row's spare bay, lane B2a moves it into the lane gaps.
func test_side_table_items_survive_growth_state_updates_and_theme_rebuilds() -> void:
	world = Node2D.new()
	root.add_child(world)
	var policy := FloorLayoutPolicy.new()
	policy.width_cells = 32
	policy.actor_footprint = PixelPerson.footprint()
	policy.actor_draw_rect = PixelPerson.drawing_rect(art.people)
	# Zone 1 (lane 0) is one pod row; zone 2 (lane 1) three rows of twelve-pane
	# pods, so the map is deeper than zone 1 and lane 0 has a gap under it.
	var room := _side_room("tab-a", 0, 0, 2)
	var first_zone := _side_zone("side/1", 1, [room])
	var second_zone := _side_zone(
		"side/2", 2, [_side_room("tab-b", 0, 100, 12), _side_room("tab-c", 1, 200, 12), _side_room("tab-d", 2, 300, 12)]
	)
	var zones: Array[ZoneModel] = [first_zone, second_zone]
	var decor := OfficeDecorPlanner.new(pen)
	var first := OfficeFloorLayout.plan(MapModel.of_zones("side", zones), null, policy, decor).plan
	_check(first != null, "the map is planned")
	if first == null:
		return
	_eq(first.lanes, 2, "two lanes")
	var bay := _gap_table_of(first)
	_check(bay != null, "lane 0's gap stands a side table")
	if bay == null:
		return
	_eq(bay.piece, ArtContract.PROP_SIDE_TABLE, "the lane gap stands a side table")
	_eq(bay.item, OfficeDecorPlanner.side_table_item(art, bay.key), "carrying its key's piece")
	_check(art.prop_sprite(bay.item) != null, "a piece of the pack: " + bay.item)
	var floor_root := Node2D.new()
	world.add_child(floor_root)
	var view := OfficeFloorView.new()
	view.setup(pen, floor_root)
	view.reconcile(first, MapModel.of_zones("side", zones))
	view.update_desks(MapModel.of_zones("side", zones), "", false)
	var node := _decor_node(floor_root, bay.key)
	_check(node != null, "the side table is drawn")
	if node == null:
		return
	var held := node.held()
	_eq(node.held_item, bay.item, "it holds the plan's piece")
	_eq(held.texture, art.sprite_texture(art.prop_sprite(bay.item)), "drawn from the pack")
	_eq((node.get_node("%Top") as Node2D).position, Vector2(0, OfficeDecor.TOP_Y), "on its top")
	for index in range(2, 6):
		room.panes.append(_side_pane(index))
	second_zone.rooms.append(_side_room("tab-e", 3, 400, 12))
	var grown := OfficeFloorLayout.plan(MapModel.of_zones("side", zones), first, policy, decor).plan
	_check(grown != null, "the grown map is planned")
	if grown == null:
		return
	var moved := _gap_table_of(grown, bay.key)
	_check(moved != null, "the grown map keeps the side table's key")
	if moved == null:
		return
	_check(grown.desk(room.key).capacity > first.desk(room.key).capacity, "the pod above it really grew")
	_check(grown.floor_cells.size.y > first.floor_cells.size.y, "and the next lane's zone deepened the map")
	_eq([moved.item, moved.position], [bay.item, bay.position], "the same piece where it stood")
	view.reconcile(grown, MapModel.of_zones("side", zones))
	view.update_desks(MapModel.of_zones("side", zones), "", false)
	_eq(_decor_node(floor_root, bay.key), node, "the same side table node")
	_eq(node.held(), held, "holding the same sprite")
	_eq(node.position, moved.position, "standing where the plan stands it")
	for state: String in ["blocked", "done", "idle", "working"]:
		for zone in zones:
			for tab in zone.rooms:
				for pane in tab.panes:
					pane.state = state
		view.update_desks(MapModel.of_zones("side", zones), room.key, false)
		_eq(
			[node.held_item, held.texture],
			[bay.item, art.sprite_texture(art.prop_sprite(bay.item))],
			state + ": unchanged"
		)
	var other := ArtPack.from_manifest(_second_pack_at(_work_dir().path_join("geometry-pack-second")))
	var themed := OfficeDraw.new(other)
	var rebuilt_root := Node2D.new()
	world.add_child(rebuilt_root)
	var rebuilt := OfficeFloorView.new()
	rebuilt.setup(themed, rebuilt_root)
	rebuilt.reconcile(grown, MapModel.of_zones("side", zones))
	var again := _decor_node(rebuilt_root, bay.key)
	_check(again != null, "the rebuild in another theme draws it")
	if again != null:
		_eq(again.held_item, bay.item, "the same semantic piece")
		_eq(again.held().texture, other.sprite_texture(other.prop_sprite(bay.item)), "from the other pack")


## Over 64 lane-gap placement keys, in both packs, the side tables' pieces
## vary: every piece of the `desk` pool and a cat occur, cats on some tables
## and not most, each key always the same piece. Stood on a real side table, a
## piece's foot is on the top's solid wood (rows -23.5..-19 over the foot,
## OfficeDecor.TOP_Y -20) and its pixels keep to the top's middle 16 units. It
## replaces test_desktop_library_varies_without_covering_equipment_or_leaving_the_top.
func test_side_table_items_vary_and_stay_on_the_top() -> void:
	world = Node2D.new()
	root.add_child(world)
	for manifest: String in [
		"res://assets/daylight/manifest.json", _second_pack_at(_work_dir().path_join("geometry-pack-second"))
	]:
		var pack := ArtPack.from_manifest(manifest)
		var drawing := OfficeDraw.new(pack)
		var seen: Dictionary[StringName, bool] = {}
		var cats := 0
		var cat_ids: Array[StringName] = []
		for sprite in pack.items_in(OfficeDecorPlanner.CAT_GROUP):
			cat_ids.append(sprite.id)
		for sample in 64:
			# The planner's own key shape: lane, then row.
			var key := "%02d/gap/%04d" % [sample % 4, 7 + 2 * (sample >> 2)]
			var id := OfficeDecorPlanner.side_table_item(pack, key)
			_eq(OfficeDecorPlanner.side_table_item(pack, key), id, "%s: the same piece every time" % key)
			seen[id] = true
			cats += int(id in cat_ids)
			var table := drawing.decor(world, ArtContract.PROP_SIDE_TABLE, Vector2(200, 200))
			table.hold(pack, id)
			var item := table.held()
			var drawn := (
				table.get_global_transform().affine_inverse() * item.get_global_transform() * _opaque_local(item)
			)
			_eq(item.scale, pack.unit_scale(), "%s: the piece uses its family's density" % id)
			_check(drawn.end.y >= -23.5 and drawn.end.y <= -19.0, "%s %s: its foot on the top's wood" % [pack.id, id])
			_check(
				drawn.position.x >= -8.0 and drawn.end.x <= 8.0,
				"%s %s: inside the top's middle, %s" % [pack.id, id, drawn]
			)
			table.free()
		for sprite in pack.items_in(OfficeDecorPlanner.DESK_GROUP):
			_check(seen.has(sprite.id), "%s: the keys exercise %s" % [pack.id, sprite.id])
		_check(cats > 0 and cats < 32, "%s: cats occur, on most tables not: %d of 64" % [pack.id, cats])


## A pane of the side-table map, working.
func _side_pane(index: int) -> PaneModel:
	var pane := PaneModel.new()
	pane.pane_id = "p%d" % index
	pane.key = "side:p%d" % index
	pane.terminal_id = "term-p%d" % index
	pane.provider = "claude"
	pane.state = "working"
	return pane


## A tab `key` numbered `number` of `count` working panes, their indices from `first`.
func _side_room(key: String, number: int, first: int, count: int) -> RoomModel:
	var room := RoomModel.new()
	room.key = key
	room.number = number
	room.label = key.to_upper()
	for index in count:
		room.panes.append(_side_pane(first + index))
	return room


## A workspace `key` numbered `number` holding `rooms`: one zone of the map.
func _side_zone(key: String, number: int, rooms: Array[RoomModel]) -> ZoneModel:
	var zone := ZoneModel.new()
	zone.key = key
	zone.number = number
	zone.label = key
	zone.rooms = rooms
	return zone


## Lane 0's first gap side table of `plan` (or the one keyed `key`), or null.
func _gap_table_of(plan: FloorPlan, key := "") -> DecorPlacement:
	for placed in plan.decorations:
		if key.is_empty() and placed.key.begins_with("00/gap/") and placed.piece == ArtContract.PROP_SIDE_TABLE:
			return placed
		if not key.is_empty() and placed.key == key:
			return placed
	return null


## The drawn standing piece keyed `key` under `floor_root` (OfficeFloorView names
## it after its plan key), or null.
func _decor_node(floor_root: Node, key: String) -> OfficeDecor:
	return floor_root.find_child("Decor_" + key.replace("/", "_"), true, false) as OfficeDecor


func test_laptops_align_with_workers_on_both_sides_after_growth() -> void:
	var table := _table()
	_check(table.resize(4), "include appended columns")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			station.furnish("codex", ArtContract.STATE_WORKING)
			var laptop := table.monitor(column, side)
			_eq(laptop.global_position.x, station.actor().global_position.x, "laptop is centered on its worker")
			_eq(laptop.position.y, -40.0 if side == "far" else -10.0, "laptop is at its sitter's edge, not the screen")
			_eq(laptop.scale, art.table.unit_scale(), "alignment never rescales the native art")
			var at := laptop.global_position
			station.furnish("", ArtContract.STATE_IDLE)
			_eq(laptop.global_position, at, "empty shell chair keeps the same edge-aligned laptop")
			station.free()


func test_shell_laptop_changes_in_place_and_survives_growth() -> void:
	var table := _table()
	for manifest: String in [
		"res://assets/daylight/manifest.json", _second_pack_at(_work_dir().path_join("geometry-pack-second"))
	]:
		var pack := ArtPack.from_manifest(manifest)
		_check(table.setup(pack, table.width, table.columns), "dress table in each theme")
		var drawing := OfficeDraw.new(pack)
		var piece := pack.table.piece(ArtContract.FURNITURE_MONITOR)
		for side: String in OfficeTable.SIDES:
			var station := drawing.station(sorted, table, 1, side)
			var laptop := table.monitor(1, side)
			var normal := pack.table.module_texture(piece.view(&"rear_shell" if side == "far" else &"front_privacy"))
			var prompt := pack.table.module_texture(piece.view(&"shell_rear" if side == "far" else &"shell_front"))
			_check(prompt != null and prompt != normal, "shell has its own prompt on both views")
			station.furnish("codex", ArtContract.STATE_WORKING)
			_eq(laptop.texture, normal, "agent uses the plain laptop")
			station.furnish("", ArtContract.STATE_IDLE)
			_eq(laptop.texture, prompt, "shell shows the terminal prompt")
			_check(laptop.visible and station.actor() == null, "shell is an equipped seat without a person")
			_check(table.resize(table.columns.size() + 2), "grow while shell is present")
			_eq(table.monitor(1, side), laptop, "growth retains the same laptop node")
			_eq(laptop.texture, prompt, "growth retains the shell prompt")
			station.furnish("", ArtContract.STATE_IDLE, false, true)
			_eq(laptop.texture, normal, "launch pending is not a shell, even without a provider yet")
			_check(station.actor() != null, "launch pending has a starting worker")
			station.furnish("", ArtContract.STATE_IDLE)
			station.vacate()
			_check(not laptop.visible, "vacant seat hides all equipment")
			station.furnish("pi", ArtContract.STATE_DONE)
			_eq(table.monitor(1, side), laptop, "occupant changes do not replace equipment")
			_eq(laptop.texture, normal, "standing agent with an empty chair is not a shell")
			station.free()


func test_resize_preserves_seats_equipment_and_selection() -> void:
	var table := _table()
	var marker := table.seat(1, "near")
	var monitor := table.monitor(1, "near")
	var lamp := table.task_light(1, "near")
	table.equip(1, "near", true)
	table.light(1, "near", OfficeTable.Lamp.FOCUS)
	table.set_selected(true)
	_check(table.resize(6), "grow capacity")
	var measured := OfficeTable.measure(6)
	_eq(table.width, measured.table_width, "runtime width comes from measure")
	_eq(table.columns, measured.columns, "runtime columns come from measure")
	_eq(table.seat(1, "near"), marker, "marker identity survives growth")
	_eq(table.monitor(1, "near"), monitor, "monitor identity survives growth")
	_eq(table.task_light(1, "near"), lamp, "lamp identity survives growth")
	_check(monitor.visible and lamp.visible, "occupied seat remains equipped")
	_eq(lamp.color, table.lamp_color(OfficeTable.Lamp.FOCUS), "lamp level survives growth")
	var frame: Node2D = table.get_node("Overlay/Frame")
	_check(frame.visible, "selection survives growth")
	for index in 6:
		for side: String in OfficeTable.SIDES:
			_eq(table.seat(index, side).position, measured.seat_position(index, side), "rendered seat agrees")
			_eq(table.standing(index, side).position, measured.standing_position(index, side), "standing agrees")
			if index >= 2:
				_check(not table.monitor(index, side).visible, "new column starts empty")
	var shape: CollisionShape2D = table.get_node("Footprint")
	var footprint: RectangleShape2D = shape.shape
	_eq(Rect2(shape.position - footprint.size / 2, footprint.size), measured.physical_rect, "collision agrees")
	var count := table.find_children("*", "", true, false).size()
	_check(table.resize(6), "same capacity is accepted")
	_eq(table.find_children("*", "", true, false).size(), count, "repeated growth adds no nodes")


func test_relocation_rebind_keeps_actor_clock_and_pose() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_WORKING, true)
	station.pane_key = "machine:pane"
	var worker := station.actor()
	var player: AnimationPlayer = worker.get_node("AnimationPlayer")
	worker.pause()
	player.seek(0.37, true)
	var elapsed := player.current_animation_position
	var relative_target := station.target_rect().position - station.global_position
	_check(table.resize(4), "grow around the current worker")
	for step in 12:
		_check(table.relocate(Vector2(192 + step * 32, 320)), "absolute table placement")
		_check(station.rebind(table, 0, "near"), "absolute station binding")
		_eq(station.actor(), worker, "same worker object")
		_eq(worker.get_node("AnimationPlayer"), player, "same native animation player")
		_eq(player.current_animation_position, elapsed, "pause and clock survive binding")
		_check(not worker.is_playing(), "paused worker stays paused")
		_eq(worker.global_position, table.seat(0, "near").global_position, "worker follows its actual marker")
		_eq(station.target_rect().position - station.global_position, relative_target, "target never drifts")
		_eq(station.pane_key, "machine:pane", "pane identity stays attached")
	_check(station.rebind(table, 2, "far"), "move to another column and side")
	_eq(station.actor(), worker, "turning does not replace the worker")
	_eq(worker.look.orientation, AvatarLook.FRONT, "far-side sitting refreshes orientation")
	_eq(station.chair_view, ArtContract.CHAIR_FRONT, "chair follows new side")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	var blocked_target := station.target_rect().position - station.global_position
	var bubble := station.chip_rect().position - station.global_position
	for step in 12:
		_check(station.rebind(table, 2, "far"), "repeat blocked binding")
		_eq(station.target_rect().position - station.global_position, blocked_target, "the seat's target stays put")
		_eq(station.chip_rect().position - station.global_position, bubble, "and so does the bubble")
		_eq(worker.global_position, table.seat(2, "far").global_position, "the blocked worker stays on the seat")
		_eq(worker.track, &"desk_blocked", "hand up at the desk")


func test_contact_shadows_follow_relocation_and_replacement_ground() -> void:
	var table := _table()
	var original := ground.find_children("*", "Polygon2D", true, false)
	_eq(original.size(), 2, "one contact per near chair")
	table.contact_shadows(ground)
	_eq(ground.find_children("*", "Polygon2D", true, false), original, "repeat reuses shadows")
	var replacement := Node2D.new()
	replacement.position = Vector2(64, 32)
	world.add_child(replacement)
	table.contact_shadows(replacement)
	_eq(ground.find_children("*", "Polygon2D", true, false).size(), 0, "former ground keeps no stale shadow")
	_eq(replacement.find_children("*", "Polygon2D", true, false), original, "replacement adopts existing shadows")
	_check(table.relocate(Vector2(352, 384)), "move after replacing ground")
	var shadow: Polygon2D = original[0]
	var center := Vector2.ZERO
	for point in shadow.polygon:
		center += shadow.to_global(point)
	center /= shadow.polygon.size()
	_check(center.is_equal_approx(table.seat(0, "near").global_position + Vector2(0, 6)), "shadow stays under chair")
	_check(table.resize(4), "expanded table adds contact coverage")
	_eq(replacement.find_children("*", "Polygon2D", true, false).size(), 4, "one shadow per new column")
	replacement.free()
	_check(table.relocate(Vector2(384, 384)), "freed old ground is harmless")
	table.contact_shadows(ground)
	_eq(ground.find_children("*", "Polygon2D", true, false).size(), 4, "replacement after free recreates coverage")
	table.free()
	_eq(ground.get_child_count(), 0, "deleting table cleans up its Ground holder")


func test_invalid_updates_leave_existing_geometry_unchanged() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_WORKING)
	var worker := station.actor()
	var where := station.position
	var table_at := table.position
	var marker := table.seat(0, "near")
	for invalid: float in [NAN, INF, 32.0, 80.0]:
		_check(not table.setup(art, invalid, [16.0, 48.0]), "bad width is rejected")
	_check(not table.setup(art, 64, [NAN]), "non-finite seat is rejected")
	_check(not table.setup(art, 64, [16.0, 16.0]), "duplicate seat is rejected")
	_check(not table.relocate(Vector2.INF), "non-finite position is rejected")
	_check(not station.rebind(table, 50, "near"), "missing column is rejected")
	_check(not station.rebind(table, 0, "other"), "unknown side is rejected")
	_eq(table.width, 64.0, "bad update keeps old width")
	_eq(table.columns, [16.0, 48.0], "bad update keeps old columns")
	_eq(table.position, table_at, "bad position keeps old placement")
	_eq(table.seat(0, "near"), marker, "bad update keeps old marker")
	_eq(station.position, where, "bad rebind keeps old placement")
	_eq(station.actor(), worker, "bad rebind keeps worker")


## Everything a station draws that is not transient stays inside the pod's
## render_rect: the badge at the top of its pulse, the chip, the selection mark,
## the chair and the worker's own canvas. The name plate and the lens line are
## transient rows (shown while hovered, selected or while `L` is held, and
## pinned by test_rows_at_the_pod_pitch_never_meet()): a 30-wide plate row
## above the tag row cannot stay inside the stationary envelope, so they are
## left out here (they were inside the old 222-tall envelope; docs/WORLD_MODEL.md).
func test_supported_station_drawing_stays_inside_measure() -> void:
	var table := _table()
	_check(table.resize(4), "measure four columns")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			# Once as the world is, once with the lens held: the chip draws
			# nothing then, and the badge is back in the middle of its row.
			for held: bool in [false, true]:
				for lift: int in [0, -1, -2]:
					_check_inside_measure(table, station, held, lift)
			station.free()


## One pass of test_supported_station_drawing_stays_inside_measure(): every
## state, the lens `held` or not, the badge lifted by `lift`.
func _check_inside_measure(table: OfficeTable, station: OfficeStation, held: bool, lift: int) -> void:
	var side := station.side
	for state: StringName in [ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_DONE]:
		station.furnish("claude", state, true)
		if state == ArtContract.STATE_BLOCKED:
			# A wait to tell draws the whole chip: frame and number.
			station.chip().show_wait(5999.0)
		station.show_lens(held, "99m+")
		var line: Label = station.get_node("Overlay/Lens")
		_eq(line.is_visible_in_tree(), held, "%s %s: the lens line shows only while held" % [side, state])
		var badge: StatusBadge = station.get_node("Overlay/Badge")
		badge.lift(lift)
		for child in station.find_children("*", "CanvasItem", true, false):
			var canvas := child as CanvasItem
			if not canvas.is_visible_in_tree() or child.name in [&"Plate", &"Lens"]:
				continue
			var bounds := Rect2()
			if child is Sprite2D:
				var sprite: Sprite2D = child
				if sprite.texture == null:
					continue
				bounds = sprite.get_rect()
				# The badge's 16-unit canvas has half a unit of clear margin each
				# side; in the chip its ink starts on the pod's edge at column 0.
				if child == badge:
					bounds = _opaque_local(sprite)
			elif child is Control:
				var control: Control = child
				bounds = Rect2(Vector2.ZERO, control.size)
			else:
				continue
			var relative := table.global_transform.affine_inverse() * canvas.get_global_transform()
			_check(
				table.geometry.render_rect.encloses(relative * bounds),
				(
					"render envelope contains %s %s %s %s in %s (lift %d)"
					% [side, state, child.name, relative * bounds, table.geometry.render_rect, lift]
				)
			)
		badge.lift(0)


## The labels hang on the pixel people as they are really drawn: every opaque
## pixel of every frame the worker plays, on both layers. No plate text and no
## badge ever covers the figure, and the selection mark frames the whole
## figure. The rows stack away from the pod: on the far side the plate is the
## top row, over the lens row and the tag row (the badge), which sits over the
## head or the raised hand; on the near side the tag row hangs below the
## chair, then the lens row, then the plate. (The plate used to sit just over
## the head, the badge beside it; a 30-wide plate row cannot share a row with
## the badge at the 32-unit pitch, so it is the outermost row now, shown only
## on hover, selection or under the lens.) A blocked worker's chip covers
## none of the figure, raised hand included, nor the plate's text, and the
## badge is drawn over it, in its left half, clear of the wait.
func test_labels_clear_the_heads_they_hang_on() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		for state: StringName in [
			ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_IDLE, ArtContract.STATE_DONE
		]:
			station.furnish("claude", state, true)
			if state == ArtContract.STATE_BLOCKED:
				station.chip().show_wait(5999.0)
			var where := "%s %s" % [side, state]
			var figure := _drawn_figure(station)
			var text := _plate_text(station)
			var badge_node: Sprite2D = station.get_node("Overlay/Badge")
			var badge := _in_station(station, badge_node, _opaque_local(badge_node))
			var mark_node: Sprite2D = station.get_node("Overlay/Selection")
			var mark := _in_station(station, mark_node, mark_node.get_rect())
			_check(figure.size.y > 30, "%s: the worker is really drawn: %s" % [where, figure])
			_check(_plate_of(station).is_visible_in_tree(), "%s: selected, the plate shows" % where)
			_check(not text.intersects(figure), "%s: the plate's text %s clears the figure %s" % [where, text, figure])
			_check(not badge.intersects(figure), "%s: the badge %s clears the figure %s" % [where, badge, figure])
			_check(mark.encloses(figure), "%s: the selection mark %s frames the figure %s" % [where, mark, figure])
			# Without the lens the plate takes the lens row's slot, next to the tag
			# row; with it, the lens line takes that slot and the plate moves out.
			var slot: Vector2 = station.rest_position() + OfficeStation.LENS_AT[side]
			_eq(_plate_of(station).position, slot, "%s: unheld, the plate in the lens row's slot" % where)
			# The lens line clears the figure and the badge as the plate does.
			station.show_lens(true, "99m+")
			_eq(_plate_of(station).position, OfficeStation.PLATE_AT[side], "%s: held, the plate moves out" % where)
			text = _plate_text(station)
			_check(not text.intersects(figure), "%s: held, the plate's text %s clears the figure" % [where, text])
			var lens := _lens_text(station)
			_check(not lens.intersects(figure), "%s: the lens line %s clears the figure %s" % [where, lens, figure])
			_check(not lens.intersects(badge), "%s: the lens line %s clears the badge %s" % [where, lens, badge])
			_check(not lens.intersects(text), "%s: and the plate's text %s" % [where, text])
			station.show_lens(false, "")
			if side == "far":
				_check(
					text.end.y <= lens.position.y and lens.end.y <= badge.position.y,
					"%s: plate over lens over badge" % where
				)
				_check(
					badge.end.y <= figure.position.y, "%s: the badge %s sits over the head %s" % [where, badge, figure]
				)
			else:
				_check(badge.position.y >= figure.end.y, "%s: the badge hangs below the feet" % where)
				_check(
					badge.end.y <= lens.position.y and lens.end.y <= text.position.y,
					"%s: badge over lens over plate" % where
				)
			if state == ArtContract.STATE_BLOCKED:
				var bubble := Rect2(station.chip().position, OfficeStation.CHIP_SIZE)
				_check(not bubble.intersects(figure), "%s: the chip %s clears the figure %s" % [where, bubble, figure])
				_check(not bubble.intersects(text), "%s: and the plate's text %s" % [where, text])
				# One unit over the chip's left edge, so the wait has daylight on both sides.
				_eq(badge.position.x, bubble.position.x - 1.0, "%s: the badge over the chip's left edge" % where)
				_check(
					bubble.grow_side(SIDE_LEFT, 1.0).encloses(badge),
					"%s: the badge %s on the chip %s" % [where, badge, bubble]
				)
				_check(badge.end.x <= bubble.position.x + OfficeChip.BADGE_SLOT, "%s: in its left half" % where)
				var overlay := station.get_node("Overlay")
				_check(
					badge_node.get_index() > station.chip().get_index() and badge_node.get_parent() == overlay,
					"%s: the badge is drawn over the chip" % where
				)
				var wait: Label = station.chip().get_node("%Wait")
				_eq(wait.text, "99m", "%s: the chip says the wait, compactly" % where)
				var inside := Rect2(Vector2.ZERO, OfficeChip.SIZE).encloses(Rect2(wait.position, wait.size))
				_check(inside, "%s: the chip's wait stays inside its frame" % where)
				var drawn := _in_station(station, wait, Rect2(Vector2.ZERO, wait.size))
				_check(not drawn.intersects(badge), "%s: the wait %s clears the badge %s" % [where, drawn, badge])
		station.free()


## The lens line on each side and over a worker resting away: its row is the
## one between the tag row and the plate row (far pod [-102, -90), near
## [32, 44)), its text clears the badge at the top of its pulse and the
## plate's text, and away it is centred over the worker, above their badge.
## While it shows the chip draws nothing and the badge is back in the middle of
## its row; let go, the line is gone and the chip is drawn again. (The line
## used to be inside the pod's render_rect, beside the badge; at the 32-unit
## pitch it is a transient row of its own, outside the stationary drawing, see
## test_rows_at_the_pod_pitch_never_meet().)
func test_the_lens_line_stays_inside_the_desk_and_off_the_badge() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		station.furnish("claude", ArtContract.STATE_BLOCKED, false)
		station.chip().show_wait(240.0)
		var badge_node: StatusBadge = station.get_node("Overlay/Badge")
		var chipped := badge_node.position
		station.show_lens(true, "99m+")
		var line: Label = station.get_node("Overlay/Lens")
		_check(line.is_visible_in_tree(), "%s: the line shows" % side)
		var in_table := table.global_transform.affine_inverse() * line.get_global_transform()
		var drawn := in_table * Rect2(Vector2.ZERO, line.size)
		var row := Rect2(1, -102, 30, 12) if side == "far" else Rect2(1, 32, 30, 12)
		_eq(drawn, row, "%s: the lens row" % side)
		_eq(badge_node.position, OfficeStation.BADGE_AT[side], "%s: the badge is back in the middle" % side)
		_check(badge_node.position != chipped, "%s: it was in the chip before" % side)
		badge_node.lift(-2)
		var lens := _lens_text(station)
		var badge := _in_station(station, badge_node, _opaque_local(badge_node))
		_check(not lens.intersects(badge), "%s: the text %s clears the badge %s" % [side, lens, badge])
		station.select(true)
		_check(not lens.intersects(_plate_text(station)), "%s: and the plate's text" % side)
		for part: String in ["%Frame", "%Wait"]:
			var drawn_part: CanvasItem = station.chip().get_node(part)
			_check(not drawn_part.is_visible_in_tree(), "%s: the chip draws no %s meanwhile" % [side, part])
		station.show_lens(false, "")
		_check(not line.visible, "%s: let go, no line" % side)
		_eq(badge_node.position, chipped, "%s: and the badge is in the chip again" % side)
		station.free()
	var away := pen.station(sorted, table, 1, "far")
	away.furnish("codex", ArtContract.STATE_IDLE, false)
	away.rest_at(OfficeRests.Rest.PANTRY, away.position + Vector2(40, 180))
	away.show_lens(true, "12m")
	var lens := _lens_text(away)
	var badge_node: Sprite2D = away.get_node("Overlay/Badge")
	var badge := _in_station(away, badge_node, badge_node.get_rect())
	_eq(lens.get_center().x, away.away_at.x, "away: centred over the worker")
	_check(lens.end.y <= badge.position.y, "away: the text %s above the badge %s" % [lens, badge])
	var figure := _drawn_figure(away)
	_check(not lens.intersects(figure), "away: it clears the figure %s" % figure)
	_check(not _plate_of(away).visible, "away: no plate even under the lens")
	var mark_node: Sprite2D = away.get_node("Overlay/Selection")
	away.select(true)
	_check(
		_in_station(away, mark_node, mark_node.get_rect()).encloses(figure), "away: the mark frames the standing figure"
	)
	away.free()


## Where the lens line's text is drawn, in the station's coordinates: centred,
## from the label's top to its font's baseline (digits, `s m h`, `+`, `?`).
func _lens_text(station: OfficeStation) -> Rect2:
	var overlay: Node2D = station.get_node("Overlay")
	var line: Label = overlay.get_node("Lens")
	var font := line.get_theme_font("font")
	var pixels := line.get_theme_font_size("font_size")
	var width := font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var top_left := line.position + Vector2((line.size.x - width) / 2.0, 0)
	return _in_station(station, overlay, Rect2(top_left, Vector2(width, font.get_ascent(pixels))))


func test_shrink_removes_only_discarded_columns() -> void:
	var table := _table()
	_check(table.resize(6), "grow before compact")
	var kept := table.seat(1, "far")
	var removed := table.seat(5, "near")
	_check(table.resize(2), "explicit caller can compact vacant columns")
	_eq(table.columns.size(), 2, "compacted capacity")
	_eq(table.seat(1, "far"), kept, "retained marker stays valid")
	_check(not is_instance_valid(removed), "discarded marker is released")
	_eq(ground.find_children("*", "Polygon2D", true, false).size(), 2, "discarded shadows are released")


## A station bound again and again, then moved to another table place and
## seat, still answers real clicks where it is now: its seat's rectangle picks
## (`picked`) and its chip's asks (`asked`), each through the viewport's own
## physics picking, and only on the release.
func test_a_rebound_station_picks_by_seat_and_bubble_through_real_input() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "far")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	station.pane_key = "machine:pane"
	var heard := PackedStringArray()
	station.picked.connect(func(key: String, _at: Vector2) -> void: heard.append("picked " + key))
	station.asked.connect(func(key: String, _at: Vector2) -> void: heard.append("asked " + key))
	for step in 12:
		_check(station.rebind(table, 0, "far"), "repeat bind before clicking")
	_check(table.relocate(Vector2(320, 320)), "relocate before real click")
	_check(station.rebind(table, 1, "near"), "rebind onto a new near seat")
	await physics_frame
	await physics_frame
	for target: String in ["seat", "bubble"]:
		heard.clear()
		var at := station.target_rect().get_center() if target == "seat" else station.chip_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await physics_frame
		for pressed: bool in [true, false]:
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
			if pressed:
				_check(heard.is_empty(), "%s: a press remains a potential drag" % target)
		var said := "picked" if target == "seat" else "asked"
		_eq(heard, PackedStringArray([said + " machine:pane"]), "one release on the %s: %s" % [target, said])


## The chip never lands on a click target it does not own: on pods from the
## narrowest to a wide one, every column and both sides blocked at once, no
## chip meets any seat's rectangle, its own included, nor another chip, and no
## chip's click rectangle meets any seat's. The far tag row's middle is the
## chip's while it shows and the seat's again once it goes.
func test_the_bubble_clears_every_click_target_and_its_neighbours() -> void:
	for capacity: int in [2, 4, 6, 12]:
		var table := _table()
		var measured := OfficeTable.measure(capacity)
		_check(table.setup(art, measured.table_width, measured.columns), "a %s-wide pod" % measured.table_width)
		var bubbles: Array[Rect2] = []
		var chips: Array[Rect2] = []
		var seats: Array[Rect2] = []
		var names: Array[String] = []
		var stations: Array[OfficeStation] = []
		for column in measured.columns.size():
			for side: String in OfficeTable.SIDES:
				var station := pen.station(sorted, table, column, side)
				station.furnish("claude", ArtContract.STATE_BLOCKED)
				station.chip().show_wait(60.0 * column)
				stations.append(station)
				bubbles.append(station.chip_rect())
				chips.append(_shape_rect(station.get_node(OfficeStation.CHIP_TARGET)))
				seats.append(station.target_rect())
				names.append("%d columns, column %d %s" % [capacity, column, side])
		for index in bubbles.size():
			_check(bubbles[index].has_area(), names[index] + ": a chip")
			_check(chips[index].encloses(bubbles[index]), names[index] + ": its click rectangle covers it")
			# The far tag row, the chip's while it shows, is the chip's to answer.
			if names[index].ends_with("far"):
				var badge_at := stations[index].global_position + OfficeStation.BADGE_AT["far"] + Vector2(0, -8)
				_check(bubbles[index].has_point(badge_at), names[index] + ": the tag row's middle is in the chip")
				_check(not seats[index].has_point(badge_at), names[index] + ": and not in the seat's rectangle")
				stations[index].furnish("claude", ArtContract.STATE_WORKING)
				_check(
					stations[index].target_rect().has_point(badge_at),
					names[index] + ": working, the seat covers the badge"
				)
				_eq(stations[index].chip_rect(), Rect2(), names[index] + ": with no chip")
				stations[index].furnish("claude", ArtContract.STATE_BLOCKED)
				stations[index].chip().show_wait(60.0)
			for other in seats.size():
				_check(
					not bubbles[index].intersects(seats[other]),
					"%s: the chip %s clears %s's seat %s" % [names[index], bubbles[index], names[other], seats[other]]
				)
				_check(
					not chips[index].intersects(seats[other]),
					"%s: its click rectangle %s clears %s's seat" % [names[index], chips[index], names[other]]
				)
			for other in bubbles.size():
				if other != index:
					_check(
						not bubbles[index].intersects(bubbles[other]),
						"%s: the chip clears %s's chip" % [names[index], names[other]]
					)
					_check(
						not chips[index].intersects(chips[other]),
						"%s: its click rectangle clears %s's" % [names[index], names[other]]
					)
		world.free()


## A done seat's paper (the small stack) stands on its own side's working plane
## (far -48..-32, near -26..-8, from the pod's constants), inside the desktop on
## every column including the last one, right of the laptop and clear of it,
## clear of every opaque pixel its own worker draws as a done agent sits (the
## only state the paper shows in), and clear of what the workers of the
## columns on either side draw while blocked (the raised hand is on the
## right). A seat's own raised hand is not held against its paper: a seat
## shows one or the other, never both, and on the near side, where the worker
## sits over the near plane, the hand's column (x+7..x+12, pod -28..-11) does
## pass over the paper's left 2 units
## (test_the_near_paper_shows_beside_whoever_sits_there holds that the two
## never show together, and the paper's texels against the sitters'). On the
## far side only what shows above the far edge counts: the desk hides the rest
## of the far worker. Pods of two, four and six desks.
func test_the_paper_stack_sits_beside_the_laptop_and_off_the_neighbours() -> void:
	var table := _table()
	for capacity: int in [2, 4, 6]:
		_check(table.resize(capacity), "%d columns" % capacity)
		var w := table.width
		var screen := -OfficeTable.SURFACE_DEPTH + OfficeTable.SCREEN_TOP
		var planes := {
			"far": Rect2(0, -OfficeTable.SURFACE_DEPTH, w, OfficeTable.SCREEN_TOP),
			"near":
			Rect2(
				0,
				screen + OfficeTable.SCREEN_HEIGHT,
				w,
				OfficeTable.NEAR_SURFACE_EDGE - screen - OfficeTable.SCREEN_HEIGHT
			),
		}
		_eq(planes["far"], Rect2(0, -48, w, 16), "the far plane")
		_eq(planes["near"], Rect2(0, -26, w, 18), "the near plane")
		var blocked: Dictionary[String, Rect2] = {}
		var done: Dictionary[String, Rect2] = {}
		for column in table.columns.size():
			for side: String in OfficeTable.SIDES:
				var station := pen.station(sorted, table, column, side)
				for state: StringName in [ArtContract.STATE_BLOCKED, ArtContract.STATE_DONE]:
					station.furnish("claude", state)
					var figure := _drawn_figure(station)
					figure.position += station.position - table.position
					if side == "far":
						figure = figure.intersection(Rect2(-1000, -1000, 3000, 1000 - OfficeTable.SURFACE_DEPTH))
					var into := blocked if state == ArtContract.STATE_BLOCKED else done
					into["%d/%s" % [column, side]] = figure
				station.free()
		for column in table.columns.size():
			for side: String in OfficeTable.SIDES:
				var where := "%d columns, column %d %s" % [capacity, column, side]
				table.show_papers(column, side, true)
				var paper := _opaque(table.papers(column, side))
				var laptop := _opaque(table.monitor(column, side))
				var plane: Rect2 = planes[side]
				_check(plane.encloses(paper), "%s: the paper %s is on its plane %s" % [where, paper, plane])
				_check(paper.position.x >= laptop.end.x, "%s: right of the laptop %s, clear of it" % [where, laptop])
				# The pod's selection frame stands outside its desks: no bar on the paper.
				table.set_selected(true)
				for bar in _frame_bars(table):
					var local := table.global_transform.affine_inverse() * bar
					_check(not local.intersects(paper), "%s: the frame's bar %s clears the paper" % [where, local])
				table.set_selected(false)
				var own := "%d/%s" % [column, side]
				_check(
					not paper.intersects(done[own]), "%s: clear of its done worker %s: %s" % [where, done[own], paper]
				)
				for other: String in ["%d/%s" % [column - 1, side], "%d/%s" % [column + 1, side]]:
					if blocked.has(other):
						_check(
							not paper.intersects(blocked[other]),
							"%s: clear of blocked worker %s %s: %s" % [where, other, blocked[other], paper]
						)
				table.show_papers(column, side, false)


## The opaque pixels of `sprite`, a child of the table, in the table's coordinates.
func _opaque(sprite: Sprite2D) -> Rect2:
	var pixels := Rect2(sprite.texture.get_image().get_used_rect())
	pixels.position += sprite.offset
	return sprite.transform * pixels


func test_desk_node_budget_bounds_real_prefabs_and_retained_empty_slots() -> void:
	world = Node2D.new()
	ground = Node2D.new()
	sorted = Node2D.new()
	world.add_child(ground)
	world.add_child(sorted)
	root.add_child(world)
	var room := RoomModel.new()
	room.key = "budget-table"
	var view := OfficeDeskView.new()
	view.setup(pen, ground, sorted, room.key)
	for capacity: int in [2, 4, 18, 250]:
		var placed := DeskPlacement.new()
		placed.tab_key = room.key
		placed.capacity = capacity
		placed.measure = OfficeTable.measure(capacity)
		view.reconcile(room, placed)
		_eq(view.stations.size(), capacity * 2, "every retained column allocates two real stations")
		_check(view.table.find_children("*", "", true, false).size() > 0, "a pod carries no decoration to count")
		for provider: String in ["", "claude"]:
			for station in view.stations:
				station.furnish(provider, ArtContract.STATE_WORKING)
			await process_frame
			var nodes := world.find_children("*", "", true, false).size() - 2
			_check(
				nodes <= OfficeDeskView.node_budget(capacity),
				(
					"%d columns, %s: the actual group including all actors, %d nodes, fits the bound %d"
					% [
						capacity,
						"people" if not provider.is_empty() else "shells",
						nodes,
						OfficeDeskView.node_budget(capacity)
					]
				)
			)
			if not provider.is_empty():
				_eq(
					world.find_children("*", "PixelPerson", true, false).size(),
					capacity * 2,
					"both sides are furnished"
				)
		for station in view.stations:
			station.vacate()
		await process_frame
		_eq(view.stations.size(), capacity * 2, "vacating retains the budgeted empty capacity")
		var empty_nodes := world.find_children("*", "", true, false).size() - 2
		_check(empty_nodes <= OfficeDeskView.node_budget(capacity), "empty retained table remains bounded")


## Two pods one row pitch apart (192, the planner's row: the wall's two cells,
## the pod's six, the corridor's two), the lower one shifted by whole columns
## either way, and a third pod beside the first across its passage cell: with
## every seat blocked and selected, once with the lens held (the plate and lens
## rows, the badge in the middle) and once without (the plate and the chip),
## so every row a seat can show is drawn, nothing one seat draws or answers a click with
## meets anything another seat does — its badge (at rest and at each pulse
## lift, 0, -1 and -2, centred or in the chip), its chip, its lens row, its
## plate row, its seat mark, its seat's rectangle and its chip's rectangle —
## whether the chips have a wait to tell or not. Within one seat, the plate,
## the lens and the tag rows never meet, nor do the seat's and the chip's
## rectangles. The rows are where docs/WORLD_MODEL.md says, in pod coordinates.
func test_rows_at_the_pod_pitch_never_meet() -> void:
	world = Node2D.new()
	ground = Node2D.new()
	sorted = Node2D.new()
	world.add_child(ground)
	world.add_child(sorted)
	root.add_child(world)
	var measured := OfficeTable.measure(4)
	var pitch := 192.0
	var upper := pen.table(sorted, ground, "Upper", Vector2(256, 240), measured.table_width, measured.columns)
	var beside_at := Vector2(256 + measured.reserved_rect.size.x, 240)
	var beside := pen.table(sorted, ground, "Beside", beside_at, measured.table_width, measured.columns)
	var lower := pen.table(sorted, ground, "Lower", Vector2(256, 240 + pitch), measured.table_width, measured.columns)
	var stations: Array[OfficeStation] = []
	for table: OfficeTable in [upper, beside, lower]:
		for column in measured.columns.size():
			for side: String in OfficeTable.SIDES:
				var station := pen.station(sorted, table, column, side)
				station.pane_key = "%s/%d/%s" % [table.name, column, side]
				stations.append(station)
	for shift: float in [-64.0, -32.0, 0.0, 32.0, 64.0]:
		lower.relocate(Vector2(256 + shift, 240 + pitch))
		for station in stations:
			if station.table == lower:
				station.rebind(lower, station.column, station.side)
		for mode: int in 4:
			var known := mode % 2 == 0
			var held := mode >= 2
			for lift: int in [0, -1, -2]:
				var parts: Array[Rect2] = []
				var owners: Array[OfficeStation] = []
				var names: Array[String] = []
				for station in stations:
					station.furnish("claude", ArtContract.STATE_BLOCKED, true)
					station.chip().show_wait(5999.0 if known else -1.0)
					station.show_lens(held, "99m+")
					var badge: StatusBadge = station.get_node("Overlay/Badge")
					badge.lift(lift)
					var rows := _seat_rows(station)
					for name: String in rows:
						parts.append(rows[name])
						owners.append(station)
						names.append(name)
				var clashes := PackedStringArray()
				for index in parts.size():
					for other in range(index + 1, parts.size()):
						if not parts[index].intersects(parts[other]):
							continue
						if owners[index] == owners[other] and not _same_seat_clash(names[index], names[other]):
							continue
						if _facing_marks(owners[index], names[index], owners[other], names[other]):
							continue
						clashes.append(
							(
								"%s %s %s / %s %s %s"
								% [
									owners[index].pane_key,
									names[index],
									parts[index],
									owners[other].pane_key,
									names[other],
									parts[other]
								]
							)
						)
				# Every pod selected: its frame's bars meet nothing of another pod, nor
				# its own seats' badges, chips, marks or click rectangles (its plate
				# and lens Labels may reach under a bar with no ink there).
				for table: OfficeTable in [upper, beside, lower]:
					table.set_selected(true)
					for bar in _frame_bars(table):
						for index in parts.size():
							var own := owners[index].table == table
							if own and names[index] in ["plate", "lens"]:
								continue
							if bar.intersects(parts[index]):
								clashes.append(
									(
										"%s frame %s / %s %s %s"
										% [table.name, bar, owners[index].pane_key, names[index], parts[index]]
									)
								)
						for other: OfficeTable in [upper, beside, lower]:
							if other == table:
								continue
							for far_bar in _frame_bars(other):
								if bar.intersects(far_bar):
									clashes.append("%s frame %s / %s frame %s" % [table.name, bar, other.name, far_bar])
				var where := "shift %d, wait %s, lens %s, lift %d" % [shift, known, held, lift]
				_eq(clashes, PackedStringArray(), where + ": nothing meets")
				if shift == 0.0:
					_check_row_literals(upper, stations, known, held, lift)
	for station in stations:
		station.free()


## The four bars of `table`'s selection frame, in global coordinates.
func _frame_bars(table: OfficeTable) -> Array[Rect2]:
	var bars: Array[Rect2] = []
	for bar: Node in table.get_node("Overlay/Frame").get_children():
		var control: Control = bar
		bars.append(control.get_global_transform() * Rect2(Vector2.ZERO, control.size))
	return bars


## Whether these are the seat marks of the two seats facing each other across
## one desk. Those two may meet: the near worker sits over the desk's near
## plane, a raised hand's top (pod -28) above the far mark's foot (-24), so the
## near mark [-32, 16) and the far one [-72, -24) share pod [-32, -24). Only
## one seat is ever selected, so the two are never drawn together; this case
## selects every seat only to measure each mark against everything else.
static func _facing_marks(a: OfficeStation, a_part: String, b: OfficeStation, b_part: String) -> bool:
	return a_part == "mark" and b_part == "mark" and a.table == b.table and a.column == b.column and a.side != b.side


## Whether two parts of the same seat may not meet: the three rows (plate,
## lens, tag) with each other, and the seat's rectangle with the chip's. The
## seat mark, and a click rectangle over the rows it answers for, may.
static func _same_seat_clash(a: String, b: String) -> bool:
	var rows := ["plate", "lens", "badge"]
	if a in rows and b in rows:
		return true
	if a in rows and b == "chip" or b in rows and a == "chip":
		return a != "badge" and b != "badge"
	return (a == "seat" and b == "chip rect") or (a == "chip rect" and b == "seat")


## What a seat draws or answers a click with, by name, in global coordinates:
## only what is shown now.
func _seat_rows(station: OfficeStation) -> Dictionary[String, Rect2]:
	var rows: Dictionary[String, Rect2] = {}
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	if badge.visible:
		rows["badge"] = badge.get_global_transform() * _opaque_local(badge)
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	if frame.is_visible_in_tree():
		rows["chip"] = frame.get_global_transform() * Rect2(Vector2.ZERO, frame.size)
	for label: String in ["Lens", "Plate"]:
		var control: Label = station.get_node("Overlay/" + label)
		if control.is_visible_in_tree():
			rows[label.to_lower()] = control.get_global_transform() * Rect2(Vector2.ZERO, control.size)
	var mark: Sprite2D = station.get_node("Overlay/Selection")
	if mark.is_visible_in_tree():
		rows["mark"] = mark.get_global_transform() * _opaque_local(mark)
	rows["seat"] = station.target_rect()
	var chip: CollisionShape2D = station.get_node(OfficeStation.CHIP_TARGET)
	if not chip.disabled:
		rows["chip rect"] = _shape_rect(chip)
	return rows


## The rows of `table`'s first column, in pod coordinates, where the world
## model puts them (docs/WORLD_MODEL.md, "Rows over a seat").
func _check_row_literals(
	table: OfficeTable, stations: Array[OfficeStation], known: bool, held: bool, lift: int
) -> void:
	var to_pod := table.global_transform.affine_inverse()
	for station in stations:
		if station.table != table or station.column != 0:
			continue
		var far := station.side == "far"
		var rows := _seat_rows(station)
		var where := "%s, wait %s, lens %s, lift %d" % [station.side, known, held, lift]
		var tag_top := -88.0 if far else 16.0
		var badge := to_pod * rows["badge"]
		var chipped := known and not held
		var badge_x := 0.0 if chipped else 8.5
		_eq(badge, Rect2(badge_x, tag_top + lift, 15, 16), "%s: the badge's pixels" % where)
		_eq(rows.has("chip"), chipped, "%s: a chip frame only with a wait, off the lens" % where)
		if chipped:
			_eq(to_pod * rows["chip"], Rect2(1, tag_top, 30, 16), "%s: the chip" % where)
		_eq(rows.has("lens"), held, "%s: the lens row only under the lens" % where)
		if held:
			_eq(to_pod * rows["lens"], Rect2(1, -102.0 if far else 32.0, 30, 12), "%s: the lens row" % where)
		# Held, the plate is the outermost row; unheld, it takes the lens row's slot.
		var plate_top := (-114.0 if far else 44.0) if held else (-102.0 if far else 32.0)
		_eq(to_pod * rows["plate"], Rect2(1, plate_top, 30, 12), "%s: the plate row" % where)
		_eq(
			to_pod * rows["chip rect"],
			Rect2(1, -90.0 if far else 14.0, 30, 18),
			"%s: the chip's click rectangle" % where
		)
		_eq(
			to_pod * rows["seat"],
			Rect2(1, -72.0 if far else -24.0, 30, 40 if far else 38),
			"%s: the seat's, under the chip" % where
		)
		var mark := to_pod * (station.get_node("Overlay/Selection") as Sprite2D).get_global_transform()
		var mark_canvas := mark * (station.get_node("Overlay/Selection") as Sprite2D).get_rect()
		_eq(mark_canvas, Rect2(0, -72.0 if far else -32.0, 32, 48), "%s: the seat mark's canvas" % where)


## The near badge hangs right under the near chair, on its column (the chair
## is opaque down to pod y 14, the badge's row is [16, 32)), and at every lift
## of its pulse, centred or in the chip, it never shares a texel with the
## chair: its pulse envelope [14, 32) only touches it. The badge over the head
## of a far worker likewise stands right over the raised hand (top at -72) and
## never shares a texel with it.
func test_the_near_chair_clears_the_badge_at_its_highest_lift() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		station.furnish("claude", ArtContract.STATE_BLOCKED)
		var badge: StatusBadge = station.get_node("Overlay/Badge")
		var chair: Sprite2D = station.get_node("Chair")
		var to_pod := table.global_transform.affine_inverse()
		var rest := to_pod * badge.get_global_transform() * _opaque_local(badge)
		var column := table.columns[0]
		_eq(rest, Rect2(column - 7.5, -88.0 if side == "far" else 16.0, 15, 16), side + ": the badge on its column")
		var under := to_pod * (chair.get_global_transform() * _opaque_local(chair))
		if side == "near":
			_check(
				rest.position.x < under.end.x and rest.end.x > under.position.x and rest.position.y >= under.end.y,
				"near: right under the chair %s" % under
			)
		for known: bool in [true, false]:
			station.chip().show_wait(60.0 if known else -1.0)
			for lift: int in [0, -1, -2]:
				badge.lift(lift)
				var badge_texels := _texels(badge)
				var where := "%s, wait %s, lift %d" % [side, known, lift]
				_check(not badge_texels.is_empty(), "%s: the badge is drawn" % where)
				var shared := 0
				var against := _texels(chair) if side == "near" else _figure_texels(station)
				for texel: Vector2i in badge_texels:
					shared += int(against.has(texel))
				_eq(
					shared,
					0,
					"%s: the badge shares no texel with the %s" % [where, "chair" if side == "near" else "worker"]
				)
		station.free()


## A far laptop sits on the far plane (-48..-40 for the rear view, -48 up for
## a shell's): it never reaches above the far edge, where the far worker shows
## over the desk, so it covers none of the worker's visible pixels.
func test_the_far_laptop_never_covers_the_far_worker() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	for column in table.columns.size():
		var station := pen.station(sorted, table, column, "far")
		for provider: String in ["claude", ""]:
			station.furnish(provider, ArtContract.STATE_WORKING)
			var laptop := _opaque(table.monitor(column, "far"))
			_check(
				laptop.position.y >= -48.0, "column %d %s: the laptop %s stays on the desk" % [column, provider, laptop]
			)
			_check(laptop.end.y <= -32.0, "column %d %s: and on the far plane" % [column, provider])
		station.furnish("claude", ArtContract.STATE_BLOCKED)
		var visible := 0
		var covered := 0
		var to_pod := table.global_transform.affine_inverse()
		var laptop_texels := _texels(table.monitor(column, "far"), to_pod)
		for texel: Vector2i in _figure_texels(station, to_pod):
			if texel.y < -48 * 2:
				visible += 1
				covered += int(laptop_texels.has(texel))
		_check(visible > 0, "column %d: the far worker shows over the desk" % column)
		_eq(covered, 0, "column %d: and the laptop covers none of it" % column)
		station.free()


## A near worker sits at the desk, not below it: the shoulders (the topmost
## row the seated figure is at its full width on) are above the near working
## edge, and the figure draws over part of its own laptop, in every state. The
## back-view chair is pushed in under the desk: its top is under the working
## top's near edge and above the apron's foot, so it covers none of the working
## top, and a shell's laptop with nobody in the chair shares no texel with it.
## Sorting is still by feet alone: the pod, then the sitter, then the chair.
## The leg of a walk into the seat (OfficeWalkGraph.leg_to_seat()) still goes
## round the chair: at every knee of it the walker's feet are off the desktop's
## footprint, and at the knee beside the seat they are clear of the chair.
func test_a_near_sitter_sits_at_the_near_working_plane() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	var to_pod := table.global_transform.affine_inverse()
	var edge := OfficeTable.NEAR_SURFACE_EDGE * 2
	var apron_foot := (OfficeTable.APRON_DROP + OfficeTable.APRON_HEIGHT) * 2
	for column in table.columns.size():
		var station := pen.station(sorted, table, column, "near")
		for state: StringName in [
			ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_IDLE, ArtContract.STATE_DONE
		]:
			station.furnish("claude", state)
			var where := "column %d %s" % [column, state]
			var figure := _figure_texels(station, to_pod)
			var laptop := _texels(table.monitor(column, "near"), to_pod)
			var shared := 0
			for texel: Vector2i in laptop:
				shared += int(figure.has(texel))
			_check(shared > 0, "%s: the sitter is at the laptop, over part of it" % where)
			if state == ArtContract.STATE_BLOCKED:
				continue
			# Half units: the widest row is the shoulders (the raised arm aside).
			var spans: Dictionary[int, Vector2i] = {}
			for texel: Vector2i in figure:
				var span: Vector2i = spans.get(texel.y, Vector2i(texel.x, texel.x))
				spans[texel.y] = Vector2i(mini(span.x, texel.x), maxi(span.y, texel.x))
			var widest := 0
			var shoulders := 0
			var rows := spans.keys()
			rows.sort()
			for row: int in rows:
				var wide := spans[row].y - spans[row].x + 1
				if wide > widest:
					widest = wide
					shoulders = row
			_check(shoulders < edge, "%s: the shoulders (pod y %s) are above the near edge" % [where, shoulders / 2.0])
		var chair: Sprite2D = station.get_node("Chair")
		var chair_texels := _texels(chair, to_pod)
		var top := 1 << 20
		for texel: Vector2i in chair_texels:
			top = mini(top, texel.y)
		_check(top >= edge, "column %d: the chair (top %s) covers none of the working top" % [column, top / 2.0])
		_check(top < apron_foot, "column %d: and is pushed in under the desk's edge" % column)
		_check(
			table.position.y < station.position.y and station.position.y < station.position.y + chair.position.y,
			"column %d: the pod sorts before the sitter, the sitter before the chair" % column
		)
		var feet := PixelPerson.footprint()
		var seat := table.geometry.seat_position(column, "near")
		var spot := table.geometry.standing_position(column, "near")
		var leg := OfficeWalkGraph.leg_to_seat(table.geometry.approach_position(column, "near"), seat, spot, true)
		_eq(leg[leg.size() - 1], seat, "column %d: the leg ends on the seat" % column)
		_eq(leg[leg.size() - 2], spot, "column %d: after the knee beside it" % column)
		for knee in leg:
			var stood := Rect2(knee + feet.position, feet.size)
			_check(
				not stood.intersects(table.geometry.physical_rect),
				"column %d: at %s the feet %s are off the desktop" % [column, knee, stood]
			)
		var beside := Rect2(spot + feet.position, feet.size)
		var chair_box := to_pod * (chair.get_global_transform() * _opaque_local(chair))
		_check(
			beside.position.x >= chair_box.end.x,
			"column %d: the knee %s is clear of the chair %s" % [column, beside, chair_box]
		)
		# A shell: a laptop with a prompt and nobody in the chair. The chair hides none of it.
		station.furnish("", ArtContract.STATE_WORKING)
		_check(station.actor() == null, "column %d: nobody sits at a shell" % column)
		var shell := _texels(table.monitor(column, "near"), to_pod)
		var hidden := 0
		for texel: Vector2i in shell:
			hidden += int(chair_texels.has(texel))
		_check(not shell.is_empty(), "column %d: the shell's laptop is drawn" % column)
		_eq(hidden, 0, "column %d: the empty chair covers none of the shell's laptop" % column)
		station.free()


## The pod stands on no legs: its two short end legs were retired once the
## near chairs, pushed in under the desk, hid them at every column, somebody
## in the chair or not. Nothing under the apron but the brackets, no module of
## the table family named for a leg, and the fixed node cost two lower.
func test_the_pod_stands_on_no_legs() -> void:
	var table := _table()
	_check(table.resize(4), "a pod with middle columns")
	_eq(table.get_node("Supports").get_child_count(), 4, "one bracket a column, nothing else")
	for child in table.get_node("Supports").get_children():
		var support := child as Sprite2D
		_eq(support.texture, art.table.module_texture(&"bracket"), "a bracket")
	for module: StringName in art.table.modules:
		_check(not String(module).begins_with("leg"), "no leg module in the pack: %s" % module)
	_check(not ArtContract.TABLE_MODULES.has(&"leg_short"), "none in the contract")
	_eq(OfficeDeskView.node_budget(0), 24, "24 fixed nodes, two fewer than with the legs")


## A near done seat's paper stays in sight now that the sitter leans over the
## near plane: no texel of it is behind its own sitter (who plays what a done
## agent plays), behind either neighbour, blocked with a hand up, or behind
## any of their chairs. A seat shows the paper or the raised hand, never both:
## the paper is a done agent's, the hand a blocked one's.
func test_the_near_paper_shows_beside_whoever_sits_there() -> void:
	var table := _table()
	for capacity: int in [2, 4, 6]:
		_check(table.resize(capacity), "%d columns" % capacity)
		var to_pod := table.global_transform.affine_inverse()
		var stations: Array[OfficeStation] = []
		for column in table.columns.size():
			stations.append(pen.station(sorted, table, column, "near"))
		for column in table.columns.size():
			for other in stations.size():
				stations[other].furnish(
					"claude", ArtContract.STATE_DONE if other == column else ArtContract.STATE_BLOCKED
				)
				_eq(
					table.papers(other, "near").visible,
					other == column,
					"%d columns, column %d: paper only at the done seat (%d)" % [capacity, column, other]
				)
				_eq(
					stations[other].chip().visible,
					other != column,
					"%d columns, column %d: the chip only at the blocked seats (%d)" % [capacity, column, other]
				)
			var paper := _texels(table.papers(column, "near"), to_pod)
			_check(not paper.is_empty(), "%d columns, column %d: the paper is drawn" % [capacity, column])
			for other: int in [column - 1, column, column + 1]:
				if other < 0 or other >= stations.size():
					continue
				var covers := _figure_texels(stations[other], to_pod)
				covers.merge(_chair_texels(stations[other], to_pod))
				var hidden := 0
				for texel: Vector2i in paper:
					hidden += int(covers.has(texel))
				_eq(
					hidden,
					0,
					(
						"%d columns, column %d: the sitter and chair of column %d cover none of it"
						% [capacity, column, other]
					)
				)
		for station in stations:
			station.free()


## The near task lamp's wedge still reads with somebody at the desk: the sitter
## covers its middle (as the laptop always did), and on each side of them at
## least NEAR_LAMP_IN_SIGHT half-unit texels of it stay in sight, whatever the
## agent plays, a raised hand and a done seat's paper included.
func test_the_near_lamp_shows_on_both_sides_of_its_sitter() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	var to_pod := table.global_transform.affine_inverse()
	for column in table.columns.size():
		var station := pen.station(sorted, table, column, "near")
		table.light(column, "near", OfficeTable.Lamp.FOCUS)
		var lamp := table.task_light(column, "near")
		var wedge := to_pod * lamp.get_global_transform() * lamp.polygon
		var bounds := Rect2(wedge[0], Vector2.ZERO)
		for point in wedge:
			bounds = bounds.expand(point)
		for state: StringName in [
			ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_IDLE, ArtContract.STATE_DONE
		]:
			station.furnish("claude", state)
			var covers := _figure_texels(station, to_pod)
			covers.merge(_chair_texels(station, to_pod))
			covers.merge(_texels(table.monitor(column, "near"), to_pod))
			if table.papers(column, "near").visible:
				covers.merge(_texels(table.papers(column, "near"), to_pod))
			var sides: Dictionary[String, int] = {"left": 0, "right": 0}
			for y in range(floori(bounds.position.y * 2.0), ceili(bounds.end.y * 2.0)):
				for x in range(floori(bounds.position.x * 2.0), ceili(bounds.end.x * 2.0)):
					var middle := Vector2(x + 0.5, y + 0.5) / 2.0
					if not Geometry2D.is_point_in_polygon(middle, wedge) or covers.has(Vector2i(x, y)):
						continue
					sides["left" if middle.x < table.columns[column] else "right"] += 1
			for side: String in sides:
				_check(
					sides[side] >= NEAR_LAMP_IN_SIGHT,
					(
						"column %d %s: %d texels of the lamp in sight on the %s, at least %d"
						% [column, state, sides[side], side, NEAR_LAMP_IN_SIGHT]
					)
				)
		station.free()


## The in-world duration (OfficeAttention.compact_duration()) at its unit
## boundaries, capped at 99 days, with `+` only when asked; and every form it
## can take fits its slot as the label draws it, once the display face is on:
## 14 units in the chip (never `+`) and 30 in the lens row (with `+`).
func test_the_compact_duration_is_bounded_and_fits_its_rows() -> void:
	var forms := {
		0.0: "0s",
		59.0: "59s",
		59.9: "59s",
		60.0: "1m",
		5999.0: "99m",
		6000.0: "1h",
		359999.0: "99h",
		360000.0: "4d",
		8553599.0: "98d",
		8553600.0: "99d",
		1.0e9: "99d",
	}
	for seconds: float in forms:
		_eq(OfficeAttention.compact_duration(seconds, false), forms[seconds], "%s s" % seconds)
		_eq(
			OfficeAttention.compact_duration(seconds, true), str(forms[seconds]) + "+", "%s s, start not seen" % seconds
		)
	_eq(OfficeAttention.compact_duration(-1.0, false), "", "unknown says nothing")
	_eq(OfficeAttention.compact_duration(-1.0, true), "", "even unobserved")
	var table := _table()
	var station := pen.station(sorted, table, 0, "far")
	var wait: Label = station.chip().get_node("%Wait")
	var lens: Label = station.get_node("Overlay/Lens")
	var probe := Label.new()
	pen.style_display(probe, OfficeChip.WAIT_PIXELS)
	root.add_child(probe)
	await process_frame
	var chip_widest := 0.0
	var lens_widest := 0.0
	for seconds: float in [0.0, 9.0, 59.0, 60.0, 599.0, 5999.0, 6000.0, 35999.0, 359999.0, 360000.0, 1.0e9]:
		for plus: bool in [false, true]:
			probe.text = OfficeAttention.compact_duration(seconds, plus)
			await process_frame
			var width := probe.get_minimum_size().x
			if plus:
				lens_widest = maxf(lens_widest, width)
			else:
				chip_widest = maxf(chip_widest, width)
	probe.free()
	_eq(chip_widest, 14.0, "the widest chip form (`99m`) is 14 wide")
	_eq(lens_widest, 18.0, "the widest lens form (`99m+`) is 18 wide")
	_check(chip_widest <= wait.size.x, "it fits the chip's slot, %s" % wait.size.x)
	_check(lens_widest <= lens.size.x, "and the lens row, %s" % lens.size.x)
	_eq(wait.size, Vector2(14, 12), "the chip's slot, measured after the face is on")
	_eq(lens.size, Vector2(30, 12), "the lens row")
	var plate: Label = station.get_node("Overlay/Plate")
	_eq(plate.size, Vector2(30, 12), "the plate row")
	_eq(plate.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE, "a long name ends in an ellipsis")
	_eq(plate.get_theme_font_size("font_size"), 8, "the display face at its native 8")
	station.free()


## A real pointer over a seat shows that seat's plate and no other; moving off
## hides it; over the chip it shows too. Selected, or under the held lens, the
## plate shows without the pointer. No plate covers a worker's pixels. A vacant
## seat has no plate to show.
func test_hovering_a_seat_shows_only_its_plate() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	var stations: Array[OfficeStation] = []
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			if column < 3:
				station.furnish("claude", ArtContract.STATE_WORKING)
			stations.append(station)
	var blocked := stations[2]
	blocked.furnish("codex", ArtContract.STATE_BLOCKED)
	blocked.chip().show_wait(60.0)
	await physics_frame
	for station in stations:
		_check(not _plate_of(station).visible, "%d %s: no plate at rest" % [station.column, station.side])
	for index: int in [0, 1, 3, 2]:
		var target := stations[index]
		await _point(target.target_rect().get_center())
		for station in stations:
			_eq(
				_plate_of(station).visible,
				station == target,
				"over %d %s: %d %s's plate" % [target.column, target.side, station.column, station.side]
			)
	await _point(blocked.chip_rect().get_center())
	_check(_plate_of(blocked).visible, "over the chip, its seat's plate shows")
	await _point(Vector2(20, 20))
	for station in stations:
		_check(not _plate_of(station).visible, "pointer off: no plate")
	await _point(stations[7].target_rect().get_center())
	_check(not _plate_of(stations[7]).visible, "a vacant seat shows no plate")
	await _point(Vector2(20, 20))
	stations[1].select(true)
	_check(_plate_of(stations[1]).visible, "selected, the plate shows")
	stations[1].select(false)
	_check(not _plate_of(stations[1]).visible, "unselected, it goes")
	var figures: Array[Rect2] = []
	for station in stations:
		if station.actor() != null:
			figures.append(station.get_global_transform() * _drawn_figure(station))
	for station in stations:
		station.show_lens(true, "12m")
	for station in stations:
		var plate := _plate_of(station)
		_eq(plate.visible, not station.vacant, "%d %s: under the lens the plate shows" % [station.column, station.side])
		if plate.visible:
			var box := plate.get_global_transform() * Rect2(Vector2.ZERO, plate.size)
			for figure in figures:
				_check(
					not box.intersects(figure),
					"%d %s: the plate %s covers no worker %s" % [station.column, station.side, box, figure]
				)
	for station in stations:
		station.show_lens(false, "")
		_check(not _plate_of(station).visible, "let go: no plate")


func _plate_of(station: OfficeStation) -> Label:
	return station.get_node("Overlay/Plate")


## Move the real pointer to `at` (viewport pixels) and let physics picking see it.
func _point(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


## Every opaque texel `sprite` draws, as texel cells (half a unit each at
## density 2) in global coordinates, or in `into`'s.
func _texels(sprite: Sprite2D, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	var image := sprite.texture.get_image()
	var used := image.get_used_rect()
	var to_world := into * sprite.get_global_transform()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var middle := to_world * (sprite.offset + Vector2(x + 0.5, y + 0.5))
			found[Vector2i(floori(middle.x * 2.0), floori(middle.y * 2.0))] = true
	return found


## Every opaque texel of the station's chair, as texel cells (see _texels()).
func _chair_texels(station: OfficeStation, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var chair: Sprite2D = station.get_node("Chair")
	return _texels(chair, into)


## Every opaque texel the station's worker draws in the track it plays, over
## all of its frames and both layers, as texel cells (see _texels()).
func _figure_texels(station: OfficeStation, into: Transform2D = Transform2D.IDENTITY) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	var person := station.actor()
	var people := person.people
	var track := people.tracks[person.track]
	for layer in PixelPeople.LAYERS:
		var sprite: Sprite2D = person.get_node(PixelPeople.SPRITES[layer])
		if sprite.texture == null:
			continue
		var image := sprite.texture.get_image()
		for index in track.frame_count():
			var frame := people.frame_rect(track.frame(index))
			for y in frame.size.y:
				for x in frame.size.x:
					if image.get_pixel(frame.position.x + x, frame.position.y + y).a <= 0.0:
						continue
					var local := Vector2(x + 0.5, y + 0.5) / people.density - people.pivot
					if sprite.flip_h:
						local.x = -local.x
					var middle := into * person.get_global_transform() * local
					found[Vector2i(floori(middle.x * 2.0), floori(middle.y * 2.0))] = true
	return found


## Every opaque pixel the station's worker draws in the track it plays, over
## all of its frames and both layers (mirrored where a layer is), in the
## station's coordinates.
func _drawn_figure(station: OfficeStation) -> Rect2:
	var person := station.actor()
	var people := person.people
	var track := people.tracks[person.track]
	var drawn := Rect2()
	for layer in PixelPeople.LAYERS:
		var sprite: Sprite2D = person.get_node(PixelPeople.SPRITES[layer])
		# A layer the look leaves empty (no glasses, the hair under a hood) draws nothing.
		if sprite.texture == null:
			continue
		var image := sprite.texture.get_image()
		for index in track.frame_count():
			var used := image.get_region(people.frame_rect(track.frame(index))).get_used_rect()
			if used.size == Vector2i.ZERO:
				continue
			# Texels back to units.
			var local := Rect2(
				Vector2(used.position) / people.density - people.pivot, Vector2(used.size) / people.density
			)
			if sprite.flip_h:
				local = Rect2(Vector2(-local.end.x, local.position.y), local.size)
			var placed := Rect2(person.position + local.position, local.size)
			drawn = placed if drawn.size == Vector2.ZERO else drawn.merge(placed)
	return drawn


## Where the plate's upper-case text is drawn, in the station's coordinates:
## centred in the plate, from its top down to the font's baseline.
func _plate_text(station: OfficeStation) -> Rect2:
	var overlay: Node2D = station.get_node("Overlay")
	var plate: Label = overlay.get_node("Plate")
	var font := plate.get_theme_font("font")
	var pixels := plate.get_theme_font_size("font_size")
	var width := font.get_string_size(plate.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var top_left := plate.position + Vector2((plate.size.x - width) / 2.0, 0)
	return _in_station(station, overlay, Rect2(top_left, Vector2(width, font.get_ascent(pixels))))


## The opaque pixels of `sprite` in its own coordinates (before its transform):
## what get_rect() is for the pixels that are drawn.
func _opaque_local(sprite: Sprite2D) -> Rect2:
	var used := Rect2(sprite.texture.get_image().get_used_rect())
	used.position += sprite.offset
	return used


## A collision shape's rectangle, in global coordinates.
func _shape_rect(node: Node) -> Rect2:
	var shape: CollisionShape2D = node
	var box: RectangleShape2D = shape.shape
	return Rect2(shape.global_position - box.size / 2.0, box.size)


## `bounds`, given in `node`'s own coordinates, in the station's.
func _in_station(station: OfficeStation, node: CanvasItem, bounds: Rect2) -> Rect2:
	return station.get_global_transform().affine_inverse() * node.get_global_transform() * bounds
