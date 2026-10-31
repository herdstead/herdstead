extends "res://tools/seat_test_base.gd"
## Complete-image stations: public geometry, retained identity and real picking.
##
## Retirement ledger (34 old cases -> 24 migrated + 5 new = 29): the ten
## separate-component cases for thin_front, contact_shadows, paper_stack,
## near_chair, far_laptop, agents_mark, near_sitter, no_legs, near_paper and
## mug are retired. There is no runtime apron/support/shadow, provider mark,
## paper/mug, chair/monitor occlusion or walk-to-seat composition to test.
## Complete-frame bounds and annotation clearance replace their surviving
## visibility concern. laptops_align becomes native whole-image playback;
## shell_laptop becomes permanent empty/person reuse; near_lamp becomes the
## independent focus underline. Five new cases cover enter/exit interruption,
## completion, frozen state changes and quiet starting/unknown states.

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
	if art == null or art.workstation == null:
		print("TEST_HARNESS_ERROR: office geometry has no workstation art")
		quit(2)
		return
	pen = OfficeDraw.new(art)
	var family := art.workstation
	var image := family.sheet_texture().get_image()
	for index in family.columns * family.rows:
		var used := image.get_region(_sheet_cell(index, family)).get_used_rect()
		frame_ink.append(
			Rect2(Vector2(used.position) / family.density - family.pivot, Vector2(used.size) / family.density)
		)
	var empty := family.empty_texture().get_image().get_used_rect()
	empty_ink = Rect2(Vector2(empty.position) / family.density - family.pivot, Vector2(empty.size) / family.density)
	await run_cases()


func _marker() -> String:
	return "OFFICE GEOMETRY TESTS"


func _after_case() -> void:
	if is_instance_valid(world):
		world.free()


func _world() -> void:
	world = Node2D.new()
	ground = Node2D.new()
	sorted = Node2D.new()
	world.add_child(ground)
	world.add_child(sorted)
	root.add_child(world)


func _table() -> OfficeTable:
	_world()
	var measured := OfficeTable.measure(2)
	return pen.table(sorted, ground, "Measured", Vector2(160, 240), measured.table_width, measured.columns)


func test_repeated_table_setup_is_idempotent() -> void:
	var table := _table()
	var count := table.find_children("*", "", true, false).size()
	var first := table.seat(0, "far")
	table.set_selected(true)
	_check(table.setup(art, 192, [48.0, 144.0]), "same setup succeeds")
	_eq(table.find_children("*", "", true, false).size(), count, "same setup adds no nodes")
	_eq(table.seat(0, "far"), first, "existing seat marker remains valid")
	_check((table.get_node("Overlay/Frame") as Node2D).visible, "same setup keeps the selection")
	_eq(table.find_children("*", "Sprite2D", true, false).size(), 0, "the pod never duplicates workstation art")
	_eq(ground.get_child_count(), 0, "no separate contact shadows are drawn")


func test_repeated_station_setup_does_not_drift_the_click_targets() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "far")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	var target := station.target_rect()
	var bubble := station.chip_rect()
	var bubble_shape: CollisionShape2D = station.get_node("Target/Chip")
	var shape_at := bubble_shape.global_position
	var worker := station.actor()
	var player := _manual_player(station)
	player.advance(0.3)
	var elapsed := player.current_animation_position
	var frame := _body(station).frame
	_check(bubble.has_area(), "a blocked seat has a chip")
	for _repeat in 12:
		station.setup(pen, table, 0, "far")
		station.furnish("claude", ArtContract.STATE_BLOCKED)
		_eq(station.target_rect(), target, "same setup keeps the seat's click target")
		_eq(station.chip_rect(), bubble, "and the chip")
		_eq(bubble_shape.global_position, shape_at, "and the chip's click target")
		_eq(station.actor(), worker, "same setup keeps the whole-image actor")
		_eq(player.current_animation_position, elapsed, "setup/refresh cannot restart blocked enter")
		_eq(_body(station).frame, frame, "nor change the shown frame")


func test_measure_is_the_capacity_and_clearance_contract() -> void:
	var minimum := OfficeTable.measure(0)
	_eq(minimum.capacity, 2, "even an empty tab reserves two columns")
	_eq(minimum.table_width, 192.0, "minimum pod width: two 96-unit columns")
	for capacity in range(2, 17):
		var measured := OfficeTable.measure(capacity)
		_eq(measured.columns.size(), capacity, "one x coordinate per column")
		_eq(measured.table_width, capacity * 96.0, "one whole workstation column per 96 units")
		_eq(measured.physical_rect, Rect2(0, -198, measured.table_width, 208), "both complete-image rows")
		_eq(measured.render_rect, Rect2(0, -200, measured.table_width, 256), "images and annotation rows")
		_eq(measured.reserved_rect, Rect2(0, -224, measured.table_width + 32, 320), "drawing and passage reserve")
		_check(measured.reserved_rect.encloses(measured.render_rect), "drawing fits the reservation")
		for index in capacity:
			_eq(measured.columns[index], 48.0 + 96.0 * index, "growth never recenters an existing column")
			_eq(measured.seat_position(index, "far"), Vector2(48.0 + 96.0 * index, -128), "upper row's feet")
			_eq(measured.seat_position(index, "near"), Vector2(48.0 + 96.0 * index, 0), "lower row's feet")
			for side: String in OfficeTable.SIDES:
				_check(measured.has_seat(index, side), "both rows of a measured column exist")
				var canvas := Rect2(
					measured.seat_position(index, side) + OfficeStation.CANVAS.position, Vector2(80, 80)
				)
				_check(measured.physical_rect.encloses(canvas), "the whole image fits, not merely the person's feet")
	_check(not minimum.has_seat(2, "far") and not minimum.has_seat(0, "other"), "invalid seats are absent")
	_eq(minimum.seat_position(-1, "far"), Vector2.INF, "invalid position has an explicit sentinel")


func test_side_table_items_survive_growth_state_updates_and_theme_rebuilds() -> void:
	_world()
	var policy := FloorLayoutPolicy.new()
	# Start with three small pods, then close the last: the retained zone has
	# room for tab-a to grow in place. The adjacent zone grows down, leaving a
	# lane-zero gap whose furniture must keep both its position and identity.
	policy.width_cells = 64
	var room := _side_room("tab-a", 1, 0, 2)
	var first_zone := _side_zone(
		"side/1", 1, [_side_room("tab-f", 0, 500, 2), room, _side_room("tab-closed", 2, 600, 2)]
	)
	var second_zone := _side_zone("side/2", 2, [_side_room("tab-b", 0, 100, 12)])
	var zones: Array[ZoneModel] = [first_zone, second_zone]
	var decor := OfficeDecorPlanner.new(pen)
	var start := OfficeFloorLayout.plan(MapModel.of_zones("side", zones), null, policy, decor).plan
	_check(start != null, "the initial side-by-side zones are planned")
	if start == null:
		return
	first_zone.rooms.remove_at(2)
	second_zone.rooms.append_array([_side_room("tab-c", 1, 200, 12), _side_room("tab-d", 2, 300, 12)])
	var first := OfficeFloorLayout.plan(MapModel.of_zones("side", zones), start, policy, decor).plan
	_check(first != null, "the map is planned")
	if first == null:
		return
	_eq(first.zones[0].rows.size(), 1, "the left zone is one pod row")
	_eq(first.zones[1].rows.size(), 3, "the adjacent zone grew down three rows")
	var bay := _gap_table_of(first)
	_check(bay != null, "lane zero's gap stands a side table")
	if bay == null:
		return
	_eq(bay.item, OfficeDecorPlanner.side_table_item(art, bay.key), "carrying its key's piece")
	_check(art.prop_sprite(bay.item) != null, "a piece of the pack")
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
	_check(grown.floor_cells.size.y > first.floor_cells.size.y, "and the adjacent zone deepened the map")
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
	var rebuilt_root := Node2D.new()
	world.add_child(rebuilt_root)
	var rebuilt := OfficeFloorView.new()
	rebuilt.setup(OfficeDraw.new(other), rebuilt_root)
	rebuilt.reconcile(grown, MapModel.of_zones("side", zones))
	var again := _decor_node(rebuilt_root, bay.key)
	_check(again != null, "the rebuild in another theme draws it")
	if again != null:
		_eq(again.held_item, bay.item, "the same semantic piece")
		_eq(again.held().texture, other.sprite_texture(other.prop_sprite(bay.item)), "from the other pack")


func test_side_table_items_vary_and_stay_on_the_top() -> void:
	_world()
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
			_eq(item.scale, pack.unit_scale(), "%s: its family's density" % id)
			_check(drawn.end.y >= -23.5 and drawn.end.y <= -19.0, "%s: its foot on the top's wood" % id)
			_check(drawn.position.x >= -8.0 and drawn.end.x <= 8.0, "%s: inside the top's middle" % id)
			table.free()
		for sprite in pack.items_in(OfficeDecorPlanner.DESK_GROUP):
			_check(seen.has(sprite.id), "%s: the keys exercise %s" % [pack.id, sprite.id])
		_check(cats > 0 and cats < 32, "%s: cats occur, on most tables not: %d of 64" % [pack.id, cats])


func test_native_whole_image_playback_uses_one_sprite_on_both_rows() -> void:
	var table := _table()
	_check(table.resize(4), "include appended columns")
	var family := art.workstation
	_eq(family.frame_size, Vector2i(80, 80), "native world canvas")
	_eq(family.pivot, Vector2(37.5, 70), "approved foot point")
	_eq(family.density, 2, "two source pixels per unit")
	_eq(family.sheet_texture().get_size(), Vector2(640, 960), "the approved 4 by 6 sheet")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			station.furnish("codex", ArtContract.STATE_WORKING)
			var actor := station.actor()
			var body := _body(station)
			var player := _manual_player(station)
			_eq(actor.find_children("*", "Sprite2D", true, false), [body], "one indivisible image, not a layered rig")
			_eq(body.texture, family.sheet_texture(), "the native sheet, not a composited texture")
			_eq(body.scale, Vector2(0.5, 0.5), "density only scales texels back to units")
			_eq(body.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "hard pixel edges")
			_check(not body.centered and not body.flip_h and not body.flip_v, "both rows face front without mirroring")
			_eq([body.hframes, body.vframes], [4, 6], "native atlas cells")
			_eq(body.offset, Vector2(-75, -140), "pivot in source pixels")
			_eq(body.transform * body.get_rect(), OfficeStation.CANVAS, "whole native canvas about the foot")
			_eq(actor.global_position, table.seat(column, side).global_position, "the image follows its measured foot")
			_eq(player.get_animation_library(&""), family.library, "the family library is shared, not rebuilt per seat")
			for clip in family.tracks:
				var entry := family.tracks[clip]
				var animation := player.get_animation(clip)
				_eq(animation.get_track_count(), 1, "%s: only the complete frame changes" % clip)
				_eq(animation.track_get_path(0), ^"Body:frame", "%s: public scene property" % clip)
				_eq(
					animation.value_track_get_update_mode(0),
					Animation.UPDATE_DISCRETE,
					"%s: no interpolated images" % clip
				)
				player.play(clip)
				var at := 0.0
				for index in entry.frames.size():
					player.seek(at + entry.seconds[index] / 2.0, true)
					_eq(body.frame, entry.frames[index], "%s: approved frame %d at its authored hold" % [clip, index])
					at += entry.seconds[index]
			station.free()


func test_shell_person_vacancy_and_reuse_keep_the_permanent_workstation() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		var permanent: WorkstationActor = station.get_node("Actor")
		var body := _body(station)
		var player := _manual_player(station)
		var nodes := station.find_children("*", "", true, false)
		var heard := PackedStringArray()
		station.picked.connect(func(key: String, _at: Vector2) -> void: heard.append(key))
		station.furnish("", ArtContract.STATE_IDLE, true)
		station.pane_key = "machine:shell"
		station.show_name("shell")
		_eq(station.actor(), null, "shell has no person")
		_eq(body.texture, art.workstation.empty_texture(), "shell draws the authored empty workstation")
		_eq([body.hframes, body.vframes], [1, 1], "the empty picture is a complete single cell")
		_check(not player.is_playing(), "no hidden person's animation at a shell")
		_check(station.plate_shown() and _selection(station).visible, "a shell still has its normal name and pick")
		_check(not station.chip().visible and not _badge(station).visible, "no agent badge or chip at a shell")
		await _click(station.target_rect().get_center(), true)
		_check(heard.is_empty(), "shell press does not select")
		await _click(station.target_rect().get_center(), false)
		_eq(heard, PackedStringArray(["machine:shell"]), "shell release picks the shell")
		station.furnish("claude", ArtContract.STATE_WORKING)
		_eq(station.actor(), permanent, "shell to person reuses the permanent actor")
		_eq(body.texture, art.workstation.sheet_texture(), "the person appears in the complete image")
		_check(table.resize(4), "grow around the occupied station")
		_check(station.rebind(table, 2, side), "move into an appended column")
		station.vacate()
		_eq(station.actor(), null, "vacant has no person")
		_eq(body.texture, art.workstation.empty_texture(), "vacancy keeps the desk, chair and monitors")
		_eq([station.pane_key, station.name_shown()], ["", ""], "vacancy keeps no pane or name")
		_check(not station.plate_shown() and not _selection(station).visible, "vacancy has no name or selection")
		_check(not _badge(station).visible and not station.chip().visible, "vacancy has no badge or chip")
		heard.clear()
		await _click(station.target_rect().get_center(), true)
		await _click(station.target_rect().get_center(), false)
		_check(heard.is_empty(), "a vacant workstation cannot be picked")
		station.furnish("pi", ArtContract.STATE_DONE)
		station.pane_key = "machine:replacement"
		station.show_name("replacement")
		_eq(station.actor(), permanent, "a new occupant reuses the same actor")
		_eq(permanent.provider, "pi", "public provider metadata follows the new occupant")
		_eq(permanent.track, &"done", "the new occupant gets its own one-shot")
		_eq(station.find_children("*", "", true, false), nodes, "no node was replaced through the cycle")
		await _click(station.target_rect().get_center(), true)
		await _click(station.target_rect().get_center(), false)
		_eq(heard, PackedStringArray(["machine:replacement"]), "reused input wiring names only the new pane")
		station.free()


func test_resize_preserves_seats_stations_and_selection() -> void:
	var table := _table()
	var marker := table.seat(1, "near")
	var station := pen.station(sorted, table, 1, "near")
	station.furnish("claude", ArtContract.STATE_WORKING, true)
	var actor := station.actor()
	var body := _body(station)
	table.set_selected(true)
	_check(table.resize(6), "grow capacity")
	var measured := OfficeTable.measure(6)
	_eq(table.width, measured.table_width, "runtime width comes from measure")
	_eq(table.columns, measured.columns, "runtime columns come from measure")
	_eq(table.seat(1, "near"), marker, "marker identity survives growth")
	_eq(station.actor(), actor, "the station owns its actor across pod growth")
	_eq(_body(station), body, "and its complete-image sprite")
	_check(_selection(station).visible, "station selection survives growth")
	_check((table.get_node("Overlay/Frame") as Node2D).visible, "pod selection survives growth")
	for index in 6:
		for side: String in OfficeTable.SIDES:
			_eq(table.seat(index, side).position, measured.seat_position(index, side), "rendered seat agrees")
	var count := table.find_children("*", "", true, false).size()
	_check(table.resize(6), "same capacity is accepted")
	_eq(table.find_children("*", "", true, false).size(), count, "repeated growth adds no nodes")


func test_relocation_rebind_keeps_actor_clock_and_pose() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_WORKING, true)
	station.pane_key = "machine:pane"
	var actor := station.actor()
	var player := _manual_player(station)
	var body := _body(station)
	_check(table.resize(4), "grow around the current worker")
	for state: StringName in [&"working", &"idle", &"blocked"]:
		station.furnish("claude", state, true)
		if state == &"blocked":
			player.advance(0.5)
		player.advance(0.37)
		for frozen: bool in [false, true]:
			station.freeze(frozen)
			var elapsed := player.current_animation_position
			var frame := body.frame
			for step in 12:
				var side: String = OfficeTable.SIDES[step % 2]
				_check(table.relocate(Vector2(192 + step * 32, 320)), "absolute table placement")
				_check(station.rebind(table, step % 4, side), "rebind across both front-facing rows")
				station.furnish("claude", state, true)
				_eq(station.actor(), actor, "same actor object")
				_eq(station.get_node("Actor/AnimationPlayer"), player, "same native player")
				_eq(player.current_animation_position, elapsed, "refresh/rebind cannot restart the clock")
				_eq(body.frame, frame, "refresh/rebind keeps the frame")
				_eq(actor.is_playing(), not frozen, "freeze survives a rebind and refresh")
				_eq(actor.global_position, table.seat(step % 4, side).global_position, "whole image follows its marker")
				_eq(
					station.target_rect().position - station.global_position, Vector2(-37.5, -70), "target never drifts"
				)
				_eq(station.pane_key, "machine:pane", "pane identity stays attached")
				_check(not body.flip_h and not body.flip_v, "row changes do not turn the artwork")
		station.freeze(false)


func test_invalid_updates_leave_existing_geometry_unchanged() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_WORKING)
	var actor := station.actor()
	var where := station.position
	var table_at := table.position
	var marker := table.seat(0, "near")
	for invalid: float in [NAN, INF, 32.0, 80.0, 193.0]:
		_check(not table.setup(art, invalid, [48.0, 144.0]), "bad width is rejected")
	_check(not table.setup(art, 192, [NAN, 144.0]), "non-finite seat is rejected")
	_check(not table.setup(art, 192, [48.0, 48.0]), "duplicate seat is rejected")
	_check(not table.setup(art, 192, [49.0, 144.0]), "noncanonical column is rejected")
	_check(not table.relocate(Vector2.INF), "non-finite position is rejected")
	_check(not station.rebind(table, 50, "near"), "missing column is rejected")
	_check(not station.rebind(table, 0, "other"), "unknown side is rejected")
	_eq(table.width, 192.0, "bad update keeps old width")
	_eq(table.columns, [48.0, 144.0], "bad update keeps old columns")
	_eq(table.position, table_at, "bad position keeps old placement")
	_eq(table.seat(0, "near"), marker, "bad update keeps old marker")
	_eq(station.position, where, "bad rebind keeps old placement")
	_eq(station.actor(), actor, "bad rebind keeps actor")


func test_latest_state_during_blocked_enter_wins_without_a_stale_loop() -> void:
	var table := _table()
	for wanted: StringName in [&"working", &"idle", &"done", &"starting", &"unknown"]:
		var station := pen.station(sorted, table, 0, "near")
		station.furnish("claude", ArtContract.STATE_BLOCKED)
		var actor := station.actor()
		var player := _manual_player(station)
		player.advance(0.3)
		_eq(actor.track, &"blocked_enter", "the request changes during enter, not after it")
		_check(_has_question(station), "blocked enter really draws the approved question bubble")
		station.furnish("claude", wanted, false, wanted == &"starting")
		_eq(actor.animation, wanted, "the latest semantic state is public immediately")
		_eq(actor.track, &"blocked_exit", "leaving blocked finishes through the authored exit")
		_check(not _has_question(station), "the baked question bubble is gone on the first exit frame")
		_check(
			not station.chip().visible and station.chip_rect() == Rect2(), "the duration chip is gone immediately too"
		)
		_check(
			not (station.get_node("Target/Chip") as CollisionShape2D).disabled,
			"the visible state badge keeps the tag row pickable; it is no longer a question"
		)
		player.advance(0.25)
		_eq(actor.track, wanted, "the obsolete enter cannot resurrect blocked")
		station.free()


func test_latest_state_during_blocked_exit_wins_without_restarting_exit() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	var actor := station.actor()
	var player := _manual_player(station)
	player.advance(0.5)
	_eq(actor.track, &"blocked", "enter reaches the blocked loop")
	station.furnish("claude", ArtContract.STATE_WORKING)
	player.advance(0.06)
	var elapsed := player.current_animation_position
	var frame := _body(station).frame
	for wanted: StringName in [&"idle", &"done", &"working", &"done"]:
		station.furnish("claude", wanted)
		_eq(actor.animation, wanted, "remember the latest request while exiting")
		_eq(actor.track, &"blocked_exit", "an ordinary update does not skip the exit")
		_eq(player.current_animation_position, elapsed, "nor restart its clock")
		_eq(_body(station).frame, frame, "nor change its frame")
		_check(not _has_question(station) and not station.chip().visible, "neither question signal returns")
	player.advance(0.2)
	_eq(actor.track, &"done", "the last requested state wins, not the first exit request")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	player.advance(0.1)
	station.furnish("claude", ArtContract.STATE_IDLE)
	player.advance(0.06)
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	_eq(actor.animation, &"blocked", "blocked can be requested again during exit")
	player.advance(0.6)
	_eq(actor.track, &"blocked", "the renewed request reaches blocked, never the obsolete idle")
	_check(station.chip().visible and _has_question(station), "both question signals return for the new block")


func test_done_one_shot_survives_refresh_and_freeze_thaw_without_replaying() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_DONE)
	var actor := station.actor()
	var player := _manual_player(station)
	var body := _body(station)
	var finished: Array[StringName] = []
	player.animation_finished.connect(func(clip: StringName) -> void: finished.append(clip))
	_eq(player.get_animation(&"done").loop_mode, Animation.LOOP_NONE, "the approved done is a one-shot")
	player.advance(0.35)
	_eq(body.frame, 22, "the approved nod is shown, not idle activity")
	station.freeze(true)
	var elapsed := player.current_animation_position
	station.furnish("claude", ArtContract.STATE_DONE, true)
	_eq(player.current_animation_position, elapsed, "refresh cannot rewind a frozen nod")
	_check(not actor.is_playing(), "refresh cannot thaw it")
	station.freeze(false)
	_check(actor.is_playing(), "an unfinished nod resumes")
	player.advance(0.7)
	_eq(finished, [&"done"], "one completion")
	_eq(body.frame, 0, "the one-shot ends on the approved neutral frame")
	_check(not actor.is_playing(), "the completed nod is stopped")
	for _repeat in 6:
		station.furnish("claude", ArtContract.STATE_DONE, true)
		station.setup(pen, table, 0, "near")
		_check(station.rebind(table, 1, "far"), "rebind after completing")
		station.freeze(true)
		station.freeze(false)
		_check(not actor.is_playing(), "neither refresh, rebind nor reconnect replays completed done")
		player.advance(2.0)
		_eq(body.frame, 0, "completed done stays neutral")
	_eq(finished, [&"done"], "the same state never completed twice")
	station.furnish("claude", ArtContract.STATE_WORKING)
	station.furnish("claude", ArtContract.STATE_DONE)
	_check(actor.is_playing(), "a genuinely new done transition plays again")
	player.advance(1.1)
	_eq(finished, [&"done", &"done"], "only a new completion state earns another nod")


func test_frozen_new_states_stay_still_then_resume_the_latest_request() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "near")
	station.furnish("claude", ArtContract.STATE_WORKING)
	var actor := station.actor()
	var player := _manual_player(station)
	station.freeze(true)
	station.furnish("claude", ArtContract.STATE_IDLE)
	_eq(actor.track, &"idle", "a frozen new state is installed")
	_eq(_body(station).frame, 0, "its first frame is shown immediately")
	_check(not actor.is_playing(), "installing a new state does not thaw it")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	_eq(actor.track, &"blocked_enter", "a block while frozen installs the enter")
	_eq(_body(station).frame, 18, "the new enter's first frame")
	_check(not actor.is_playing(), "the enter also remains frozen")
	station.furnish("claude", ArtContract.STATE_WORKING)
	_eq(actor.track, &"blocked_exit", "a newer request replaces the frozen enter")
	_eq(_body(station).frame, 23, "its exit frame is installed without time advancing")
	station.furnish("claude", ArtContract.STATE_DONE)
	_check(not actor.is_playing(), "latest requested done still cannot unfreeze the exit")
	station.freeze(false)
	_check(actor.is_playing(), "thaw resumes the pending exit")
	player.advance(0.25)
	_eq(actor.track, &"done", "thaw ends at the latest request, not working or blocked")
	player.advance(1.1)
	_check(not actor.is_playing(), "the new done finishes once")
	station.freeze(true)
	station.vacate()
	station.furnish("", ArtContract.STATE_IDLE)
	_check(station.actor() == null and not player.is_playing(), "a frozen reused shell has no hidden animation")
	station.furnish("pi", ArtContract.STATE_WORKING)
	_eq(station.actor(), actor, "reuse keeps the actor even while frozen")
	_check(not actor.is_playing(), "reuse cannot bypass an existing freeze")
	station.freeze(false)
	_check(actor.is_playing(), "the newly occupied workstation resumes only on thaw")
	_eq(actor.track, &"working", "the new occupant's requested state resumes")


func test_starting_and_unknown_hold_frame_zero_without_activity() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "far")
	for state: StringName in [&"starting", &"unknown"]:
		station.furnish("claude", ArtContract.STATE_WORKING)
		station.furnish("claude", state, false, state == &"starting")
		var actor := station.actor()
		var player := _manual_player(station)
		var expected := &"starting" if state == &"starting" else &"unknown"
		_eq(actor.animation, expected, "unresolved states use a still alias")
		_eq(actor.track, expected, "not the working or idle animation")
		for delta: float in [0.0, 0.1, 0.6, 0.4, 2.0]:
			player.advance(delta)
			_eq(_body(station).frame, 0, "%s stays on frame zero throughout" % state)
		_check(not actor.is_playing(), "the still alias does not loop")
		_check(not station.chip().visible, "a still alias has no blocked duration chip")
	station.actor().play_state(&"working")
	station.actor().play_state(&"future-state")
	_eq(station.actor().track, &"unknown", "an unsupported actor state also chooses the still alias")
	_eq(_body(station).frame, 0, "not invented activity")
	station.furnish("", ArtContract.STATE_IDLE, false, true)
	_check(station.actor() != null, "a launch with no provider yet still has a person")
	_eq(station.actor().track, &"starting", "but no invented working activity")


## Every authored cell, including cells unused by today's animation sequence,
## fits every column of both rows. Annotations are included, not a smaller
## person-only approximation of the complete workstation's canvas.
func test_supported_station_drawing_stays_inside_measure() -> void:
	var table := _table()
	_check(table.resize(4), "measure four columns")
	_eq(frame_ink.size(), 24, "all approved cells are checked")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			station.furnish("claude", ArtContract.STATE_BLOCKED, true)
			station.freeze(true)
			station.show_name(LONG_NAME)
			station.chip().show_wait(5999.0)
			for frame in 24:
				_body(station).frame = frame
				for held: bool in [false, true]:
					station.show_lens(held, "99m+")
					for lift: int in [0, -1, -2]:
						_badge(station).lift(lift)
						_check_inside_measure(
							table, station, "%d/%s frame %d lens %s lift %d" % [column, side, frame, held, lift]
						)
			for state: StringName in [&"working", &"idle", &"done", &"unknown", &"starting"]:
				station.furnish("claude", state, true, state == &"starting")
				for held: bool in [false, true]:
					station.show_lens(held, "99m+")
					_check_inside_measure(table, station, "%d/%s %s lens %s" % [column, side, state, held])
			station.vacate()
			_check_inside_measure(table, station, "%d/%s empty" % [column, side])
			station.free()


func _check_inside_measure(table: OfficeTable, station: OfficeStation, where: String) -> void:
	var to_pod := table.global_transform.affine_inverse()
	var rows := _seat_rows(station)
	rows["whole canvas"] = station.get_global_transform() * OfficeStation.CANVAS
	var extent := station.signal_rect()
	_eq(
		extent,
		Rect2(station.global_position + Vector2(-47, -70), Vector2(94, 124)),
		where + ": stable camera/pointer extent includes the reserved name and lens rows"
	)
	_eq(station.target_rect(), rows["whole canvas"], where + ": the click target stays on the 80 by 80 image")
	for part in rows:
		_check(extent.encloses(rows[part]), "%s: camera/pointer extent contains %s %s" % [where, part, rows[part]])
	rows["signal"] = extent
	for part in rows:
		_check(
			table.geometry.render_rect.encloses(to_pod * rows[part]),
			"%s: render envelope contains %s %s" % [where, part, to_pod * rows[part]]
		)


func test_labels_clear_the_heads_they_hang_on() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		station.furnish("claude", ArtContract.STATE_BLOCKED, true)
		station.freeze(true)
		station.show_name(LONG_NAME)
		station.chip().show_wait(5999.0)
		for frame in 24:
			_body(station).frame = frame
			var image := _drawing(station)
			_check(image.size.y >= 59.0, "%s frame %d: the complete image is measured" % [side, frame])
			var mark := _line_bounds(_selection(station))
			_check(mark.encloses(image), "%s frame %d: selection frames all opaque pixels" % [side, frame])
			for held: bool in [false, true]:
				station.show_lens(held, "99m+")
				_eq(
					_plate_of(station).position,
					OfficeStation.PLATE_AT if held else OfficeStation.PLATE_REST,
					"both rows put the plate below the image"
				)
				for lift: int in [0, -1, -2]:
					_badge(station).lift(lift)
					var rows := _seat_rows(station)
					for part: String in ["plate", "badge", "chip", "lens"]:
						if rows.has(part):
							_check(
								not image.intersects(rows[part]),
								"%s frame %d: %s clears all workstation pixels" % [side, frame, part]
							)
					_check(not rows["plate"].intersects(rows["badge"]), "plate clears the badge at every pulse lift")
					if held:
						_check(not rows["lens"].intersects(rows["plate"]), "lens clears the plate")
						_check(not rows["lens"].intersects(rows["badge"]), "lens clears the badge")
					else:
						var wait: Label = station.chip().get_node("%Wait")
						_eq(wait.text, "99m", "the chip says the compact wait")
						_check(not wait.get_global_rect().intersects(rows["badge"]), "wait clears the badge")
						_check(rows["chip"].encloses(wait.get_global_rect()), "wait stays inside its frame")
						_check(
							rows["badge"].end.x <= rows["chip"].position.x + OfficeChip.BADGE_SLOT,
							"badge stays in the chip's left slot"
						)
		station.free()


func test_the_lens_line_stays_inside_the_desk_and_off_the_badge() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		station.furnish("claude", ArtContract.STATE_BLOCKED)
		station.chip().show_wait(240.0)
		var badge := _badge(station)
		var chipped := badge.position
		station.show_lens(true, "99m+")
		var line: Label = station.get_node("Overlay/Lens")
		var feet := -128.0 if side == "far" else 0.0
		var to_pod := table.global_transform.affine_inverse()
		_eq(to_pod * line.get_global_rect(), Rect2(38, feet + 30, 20, 12), "the lens tag is centered below its image")
		_eq(badge.position, OfficeStation.BADGE_AT, "under the lens the badge returns to the middle")
		_check(badge.position != chipped, "it was in the chip before")
		badge.lift(-2)
		station.show_name(LONG_NAME)
		station.select(true)
		var rows := _seat_rows(station)
		_check(not rows["lens"].intersects(rows["badge"]), "lens clears the highest badge")
		_check(not rows["lens"].intersects(rows["plate"]), "and the plate")
		for part: String in ["%Frame", "%Wait"]:
			_check(not (station.chip().get_node(part) as CanvasItem).is_visible_in_tree(), "the chip draws no " + part)
		station.show_lens(false, "")
		_check(not line.visible, "let go: no lens line")
		_eq(badge.position, chipped, "and the badge returns to the chip")
		station.free()
	var idle := pen.station(sorted, table, 1, "far")
	idle.furnish("codex", ArtContract.STATE_IDLE)
	idle.show_lens(true, "12m")
	var idle_line: Label = idle.get_node("Overlay/Lens")
	_eq(
		table.global_transform.affine_inverse() * idle_line.get_global_rect(),
		Rect2(136, -98, 16, 12),
		"idle uses its own seat's same lens row"
	)
	_check(_plate_of(idle).visible, "idle's plate also shows under the lens")


func test_shrink_removes_only_discarded_columns() -> void:
	var table := _table()
	_check(table.resize(6), "grow before compact")
	var kept := table.seat(1, "far")
	var removed := table.seat(5, "near")
	var station := pen.station(sorted, table, 1, "far")
	station.furnish("claude", ArtContract.STATE_IDLE)
	var actor := station.actor()
	_check(table.resize(2), "explicit caller can compact vacant columns")
	_eq(table.columns.size(), 2, "compacted capacity")
	_eq(table.seat(1, "far"), kept, "retained marker stays valid")
	_check(not is_instance_valid(removed), "discarded marker is released")
	_eq(table.get_node("Seats").get_child_count(), 4, "only the two retained rows of markers remain")
	_eq(station.actor(), actor, "a retained occupied station keeps its actor")


func test_a_rebound_station_picks_by_seat_and_bubble_through_real_input() -> void:
	var table := _table()
	var station := pen.station(sorted, table, 0, "far")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	station.pane_key = "machine:pane"
	var heard := PackedStringArray()
	station.picked.connect(func(key: String, _at: Vector2) -> void: heard.append("picked " + key))
	station.asked.connect(func(key: String, _at: Vector2) -> void: heard.append("asked " + key))
	for _repeat in 12:
		_check(station.rebind(table, 0, "far"), "repeat bind before clicking")
	_check(table.relocate(Vector2(320, 320)), "relocate before real click")
	_check(station.rebind(table, 1, "near"), "rebind onto a new lower seat")
	for target: String in ["seat", "chip"]:
		heard.clear()
		var at := station.target_rect().get_center() if target == "seat" else station.chip_rect().get_center()
		await _click(at, true)
		_check(heard.is_empty(), "%s: a press remains a potential drag" % target)
		await _click(at, false)
		var said := "picked" if target == "seat" else "asked"
		_eq(heard, PackedStringArray([said + " machine:pane"]), "one release on the %s: %s" % [target, said])
	var former_chip := station.chip_rect().get_center()
	station.furnish("claude", ArtContract.STATE_WORKING)
	heard.clear()
	await _click(former_chip, true)
	await _click(former_chip, false)
	_eq(heard, PackedStringArray(["picked machine:pane"]), "the visible working badge only picks, never asks")
	station.furnish("", ArtContract.STATE_UNKNOWN)
	heard.clear()
	await _click(former_chip, true)
	await _click(former_chip, false)
	_check(heard.is_empty(), "a shell has no badge and leaves no invisible tag target")


func test_the_bubble_clears_every_click_target_and_its_neighbours() -> void:
	for capacity: int in [2, 4, 6, 12]:
		var table := _table()
		_check(table.resize(capacity), "grow the test pod")
		var stations: Array[OfficeStation] = []
		for column in capacity:
			for side: String in OfficeTable.SIDES:
				var station := pen.station(sorted, table, column, side)
				station.furnish("claude", ArtContract.STATE_BLOCKED)
				station.chip().show_wait(60.0 * column)
				stations.append(station)
		for station in stations:
			var bubble := station.chip_rect()
			var target := _shape_rect(station.get_node("Target/Chip"))
			_check(bubble.has_area() and target.encloses(bubble), "the chip's click rectangle covers it")
			for other in stations:
				_check(not bubble.intersects(other.target_rect()), "the chip never overlaps a workstation click target")
				_check(not target.intersects(other.target_rect()), "nor does its click rectangle")
				if other != station:
					_check(not bubble.intersects(other.chip_rect()), "neighbouring chips stay separate")
					_check(
						not target.intersects(_shape_rect(other.get_node("Target/Chip"))), "and their click rectangles"
					)
			station.furnish("claude", ArtContract.STATE_WORKING)
			_eq(station.chip_rect(), Rect2(), "working has no chip rectangle")
			var badge: Sprite2D = station.get_node("Overlay/Badge")
			_check(badge.visible, "the question is replaced by a visible working badge")
			_check(
				target.encloses(badge.get_global_transform() * badge.get_rect()),
				"the same tag-row target still contains the working badge"
			)
			station.furnish("", ArtContract.STATE_UNKNOWN)
			_check(
				(station.get_node("Target/Chip") as CollisionShape2D).disabled, "a shell leaves no invisible tag target"
			)
			station.furnish("claude", ArtContract.STATE_BLOCKED)
			station.chip().show_wait(60.0)
		world.free()


func test_desk_node_budget_bounds_real_prefabs_and_retained_empty_slots() -> void:
	_world()
	var room := RoomModel.new()
	room.key = "budget-table"
	var view := OfficeDeskView.new()
	view.setup(pen, ground, sorted, room.key)
	for capacity: int in [2, 4, 18, 250]:
		_eq(
			OfficeDeskView.node_budget(capacity),
			11 + 34 * capacity,
			"eleven fixed nodes, two 16-node stations and two markers per column"
		)
		var placed := _placement(room.key, capacity)
		view.reconcile(room, placed)
		_eq(view.stations.size(), capacity * 2, "every retained column allocates two stations")
		var actors: Array[Node] = []
		for station in view.stations:
			actors.append(station.get_node("Actor"))
		for provider: String in ["", "claude"]:
			for station in view.stations:
				station.furnish(provider, ArtContract.STATE_WORKING)
			await process_frame
			var nodes := world.find_children("*", "", true, false).size() - 2
			_check(
				nodes <= OfficeDeskView.node_budget(capacity),
				(
					"%d columns, %s: actual %d nodes fit budget %d"
					% [capacity, provider, nodes, OfficeDeskView.node_budget(capacity)]
				)
			)
			for index in view.stations.size():
				_eq(
					view.stations[index].get_node("Actor"),
					actors[index],
					"a shell/person change allocates no replacement actor"
				)
		for station in view.stations:
			station.vacate()
		await process_frame
		_eq(view.stations.size(), capacity * 2, "vacating retains empty capacity")
		var empty_nodes := world.find_children("*", "", true, false).size() - 2
		_check(empty_nodes <= OfficeDeskView.node_budget(capacity), "empty retained table remains bounded")
		for station in view.stations:
			_eq(
				_body(station).texture,
				art.workstation.empty_texture(),
				"all empty slots still draw their whole workstation"
			)


## Every seat occupied or several vacancy patterns, at the planner's pod-row
## pitch and shifted by complete columns. Includes empty workstation ink:
## widening a neighbour's name plate must not cover the retained furniture.
func test_rows_at_the_pod_pitch_never_meet() -> void:
	_world()
	var measured := OfficeTable.measure(4)
	var pitch := OfficeZoneLayout.pod_row_cells() * float(FloorLayoutPolicy.GRID)
	_eq(pitch, 320.0, "the planner reserves ten cells per pod row")
	var upper := pen.table(sorted, ground, "Upper", Vector2(256, 240), measured.table_width, measured.columns)
	var beside_at := Vector2(256 + measured.reserved_rect.size.x, 240)
	var beside := pen.table(sorted, ground, "Beside", beside_at, measured.table_width, measured.columns)
	var lower := pen.table(sorted, ground, "Lower", Vector2(256, 240 + pitch), measured.table_width, measured.columns)
	var stations: Array[OfficeStation] = []
	for table: OfficeTable in [upper, beside, lower]:
		for column in measured.columns.size():
			for side: String in OfficeTable.SIDES:
				stations.append(pen.station(sorted, table, column, side))
	var fars: Array[PackedInt32Array] = [[0, 1, 2, 3], [0, 2], [0, 3], [1, 2]]
	var nears: Array[PackedInt32Array] = [[0, 1, 2, 3], [1, 3], [1], [0, 2, 3]]
	var widened := 0
	for pattern in fars.size():
		for shift: float in [-192.0, -96.0, 0.0, 96.0, 192.0]:
			_check(lower.relocate(Vector2(256 + shift, 240 + pitch)), "shift the lower pod by whole columns")
			for station in stations:
				if station.table == lower:
					_check(station.rebind(lower, station.column, station.side), "station follows the shifted pod")
			widened += _never_meet([upper, beside, lower], stations, fars[pattern], nears[pattern])
	_check(widened > 0, "the test exercised plates widened over vacant slots")


func _never_meet(
	tables: Array[OfficeTable], stations: Array[OfficeStation], far: PackedInt32Array, near: PackedInt32Array
) -> int:
	var widened := 0
	for mode in 4:
		var known := mode % 2 == 0
		var held := mode >= 2
		for lift: int in [0, -1, -2]:
			var parts: Array[Rect2] = []
			var owners: Array[OfficeStation] = []
			var names: Array[String] = []
			for station in stations:
				if station.column in (far if station.side == "far" else near):
					station.pane_key = "%s/%d/%s" % [station.table.name, station.column, station.side]
					station.furnish("claude", ArtContract.STATE_BLOCKED, true)
					station.freeze(true)
					_body(station).frame = 19
					station.show_name(LONG_NAME)
					station.chip().show_wait(5999.0 if known else -1.0)
				else:
					station.vacate()
				station.show_lens(held, "99m+")
				_badge(station).lift(lift)
			for table in tables:
				var pod: Array[OfficeStation] = []
				for station in stations:
					if station.table == table:
						pod.append(station)
				OfficeFloorView.widen_plates(pod)
			for station in stations:
				if station.plate_row().size.x > OfficeStation.PLATE_SIZE.x and _plate_of(station).visible:
					widened += 1
				_check(not station.vacant or not _plate_of(station).visible, "a vacant seat shows no plate")
				var rows := _seat_rows(station)
				for part in rows:
					parts.append(rows[part])
					owners.append(station)
					names.append(part)
			var clashes := PackedStringArray()
			for index in parts.size():
				for other in range(index + 1, parts.size()):
					if not parts[index].intersects(parts[other]):
						continue
					if owners[index] == owners[other] and not _same_seat_clash(names[index], names[other]):
						continue
					clashes.append(
						(
							"%s %s %s / %s %s %s"
							% [
								owners[index].name,
								names[index],
								parts[index],
								owners[other].name,
								names[other],
								parts[other]
							]
						)
					)
			for table in tables:
				table.set_selected(true)
				for bar in _frame_bars(table):
					for index in parts.size():
						if bar.intersects(parts[index]):
							clashes.append(
								(
									"%s frame %s / %s %s %s"
									% [table.name, bar, owners[index].name, names[index], parts[index]]
								)
							)
					for other in tables:
						if other != table:
							for other_bar in _frame_bars(other):
								if bar.intersects(other_bar):
									clashes.append("%s frame / %s frame" % [table.name, other.name])
			_eq(
				clashes,
				PackedStringArray(),
				"far %s near %s wait %s lens %s lift %d: nothing meets" % [far, near, known, held, lift]
			)
			if far.size() == 4 and near.size() == 4:
				_check_row_literals(tables[0], stations, known, held, lift)
	return widened


func _check_row_literals(
	table: OfficeTable, stations: Array[OfficeStation], known: bool, held: bool, lift: int
) -> void:
	var to_pod := table.global_transform.affine_inverse()
	for station in stations:
		if station.table != table or station.column != 0:
			continue
		var feet := -128.0 if station.side == "far" else 0.0
		var rows := _seat_rows(station)
		var chipped := known and not held
		_eq(to_pod * rows["badge"], Rect2(32.0 if chipped else 40.5, feet + 12 + lift, 15, 16), "badge's opaque pixels")
		_eq(rows.has("chip"), chipped, "the frame draws only with a wait and no lens")
		if chipped:
			_eq(to_pod * rows["chip"], Rect2(33, feet + 12, 30, 16), "the chip below the complete image")
		_eq(rows.has("lens"), held, "lens row only while held")
		if held:
			_eq(to_pod * rows["lens"], Rect2(38, feet + 30, 20, 12), "the compact lens tag")
		_eq(to_pod * rows["plate"], Rect2(1, feet + (44 if held else 32), 94, 10), "the name plate's own row")
		_eq(to_pod * rows["chip rect"], Rect2(33, feet + 10, 30, 18), "the chip's click target")
		_eq(to_pod * rows["seat"], Rect2(10.5, feet - 70, 80, 80), "the complete workstation's click target")
		_eq(to_pod * rows["mark"], Rect2(11.5, feet - 69.5, 78, 79), "selection line including its half-unit stroke")


func test_the_near_rows_stand_clear_of_the_tab_label() -> void:
	_world()
	var room := RoomModel.new()
	room.key = "label-table"
	room.label = "critics"
	var view := OfficeDeskView.new()
	view.setup(pen, ground, sorted, room.key)
	var placed := _placement(room.key, 4)
	view.reconcile(room, placed)
	await process_frame
	var label := view.title.get_global_rect()
	_eq(
		view.table.global_transform.affine_inverse() * label,
		Rect2(0, 60, placed.measure.table_width, 8),
		"tab title below the image and annotation envelope"
	)
	for station in view.stations:
		station.furnish("claude", ArtContract.STATE_WORKING)
		station.show_name(LONG_NAME)
	for held: bool in [false, true]:
		for station in view.stations:
			station.show_lens(held, "4s+")
			station.select(true)
		await process_frame
		for station in view.stations:
			var rows := _seat_rows(station)
			_check(rows.has("plate"), "selected plate shows")
			_eq(rows.has("lens"), held, "lens shows only while held")
			for part: String in ["plate", "lens"]:
				if rows.has(part):
					_check(
						not rows[part].grow(2.0).intersects(label),
						"%s: the %s stays at least two units off the title" % [station.name, part]
					)


func test_herdr_focus_underline_is_independent_of_selection_and_animation() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		station.furnish("claude", ArtContract.STATE_WORKING)
		var player := _manual_player(station)
		player.advance(0.37)
		var frame := _body(station).frame
		var elapsed := player.current_animation_position
		var focus: Polygon2D = station.get_node("Focus")
		var underline := Rect2(focus.polygon[0], Vector2.ZERO)
		for point in focus.polygon:
			underline = underline.expand(point)
		_eq(underline, Rect2(-28, 4, 62, 1), "herdr focus is a narrow floor underline, not a desk lamp")
		_check(OfficeStation.CANVAS.encloses(focus.transform * underline), "the focus signal stays within its station")
		for ink in frame_ink:
			_check(
				not (focus.transform * underline).intersects(ink), "the underline covers none of the 24 approved images"
			)
		var nodes := station.find_children("*", "", true, false)
		for level: OfficeTable.Lamp in [
			OfficeTable.Lamp.OFF, OfficeTable.Lamp.DIM, OfficeTable.Lamp.ON, OfficeTable.Lamp.FOCUS
		]:
			station.light(level)
			_eq(station.light_level, level, "public focus level follows herdr")
			_eq(focus.visible, level != OfficeTable.Lamp.OFF, "only a nonzero focus level draws its underline")
			_check(is_equal_approx(focus.color.a, OfficeStation.LIGHT_ALPHA[level]), "focus uses the prescribed alpha")
			for picked: bool in [true, false]:
				station.select(picked)
				_eq(_selection(station).visible, picked, "selection controls its own frame")
				_eq(station.light_level, level, "selection cannot replace herdr focus")
				_eq(focus.visible, level != OfficeTable.Lamp.OFF, "selection cannot hide/show the focus underline")
				_eq(_body(station).frame, frame, "focus/selection never change the image frame")
				_eq(player.current_animation_position, elapsed, "or restart its clock")
				_eq(_body(station).modulate, Color.WHITE, "focus does not make the person look disconnected")
		_eq(station.find_children("*", "", true, false), nodes, "focus and selection add no nodes")
		station.vacate()
		_check(not focus.visible and not _selection(station).visible, "vacancy clears both channels")
		station.free()


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
		1.0e9: "99d"
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
	pen.style_figures(probe, OfficeChip.WAIT_PIXELS)
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
	_check(chip_widest <= wait.size.x, "the chip's slot fits every form")
	_eq(
		[OfficeStation.LENS_SIZE, OfficeStation.PLATE_SIZE],
		[Vector2(30, 12), Vector2(94, 10)],
		"compact lens and workstation-width name row"
	)
	_eq(wait.size, Vector2(14, 12), "the chip's slot after its face is on")
	station.show_lens(true, "99m+")
	_eq(lens.size, Vector2(lens_widest + 2.0 * OfficeDraw.TAG_PAD, 12), "the widest lens tag fits its row")
	station.show_name(LONG_NAME)
	var plate := _plate_of(station)
	_eq(plate.size, Vector2(94, 10), "a long name fills its new name row")
	_eq(plate.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE, "long names still end with an ellipsis")
	_eq(plate.get_theme_font_size("font_size"), 8, "native display face")


func test_hovering_a_seat_shows_only_its_plate() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	var stations: Array[OfficeStation] = []
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			if column < 3:
				station.furnish("claude", ArtContract.STATE_WORKING)
				station.show_name("pane %d %s" % [column, side])
			stations.append(station)
	var blocked := stations[2]
	blocked.furnish("codex", ArtContract.STATE_BLOCKED)
	blocked.chip().show_wait(60.0)
	await _point(Vector2(20, 20))
	for station in stations:
		_check(not _plate_of(station).visible, "no plate at rest")
	for index: int in [0, 1, 3, 2]:
		var target := stations[index]
		await _point(target.target_rect().get_center())
		for station in stations:
			_eq(_plate_of(station).visible, station == target, "only the genuinely hovered seat's plate shows")
	await _point(blocked.chip_rect().get_center())
	_check(_plate_of(blocked).visible, "hovering the chip shows its plate too")
	await _point(Vector2(20, 20))
	for station in stations:
		_check(not _plate_of(station).visible, "moving off hides the plate")
	await _point(stations[7].target_rect().get_center())
	_check(not _plate_of(stations[7]).visible, "vacant furniture has no plate")
	await _point(Vector2(20, 20))
	stations[1].select(true)
	_check(_plate_of(stations[1]).visible, "selected, the plate shows without hovering")
	stations[1].select(false)
	_check(not _plate_of(stations[1]).visible, "unselected, it goes")
	for station in stations:
		station.show_lens(true, "12m")
	for station in stations:
		var plate := _plate_of(station)
		_eq(plate.visible, not station.vacant, "under the lens only occupied plates show")
		if plate.visible:
			for other in stations:
				_check(
					not plate.get_global_rect().intersects(_drawing(other)),
					"no plate covers even an empty workstation's pixels"
				)
	for station in stations:
		station.show_lens(false, "")
		_check(not _plate_of(station).visible, "letting go hides the plate")


func test_a_long_name_takes_a_vacant_neighbours_slot() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	var stations: Array[OfficeStation] = []
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			stations.append(pen.station(sorted, table, column, side))
	_seat_far(stations, [0, 2])
	await process_frame
	for station in stations:
		_eq(_plate_of(station).visible, not station.vacant, "few seats: every occupied plate, no vacant plate")
	_eq(_pod_plate(stations[0]), Rect2(1, -96, 190, 10), "far 0 takes vacant 1's slot")
	_eq(_pod_plate(stations[4]), Rect2(193, -96, 190, 10), "far 2 takes vacant 3's slot, not 1's")
	_eq(_pod_plate(stations[1]), Rect2(1, 32, 94, 10), "near 0 has an occupied neighbour")
	for far: OfficeStation in [stations[0], stations[4]]:
		for station in stations:
			_check(
				not _plate_of(far).get_global_rect().intersects(_drawing(station)),
				"widened plate covers no complete workstation"
			)
	stations[0].show_name("ab")
	_eq(_pod_plate(stations[0]).get_center().x, 48.0, "short name stays centered on its own column")
	_check(_pod_plate(stations[0]).size.x < 94.0, "short name hugs its text")
	stations[0].show_name(LONG_NAME)
	stations[0].show_lens(true, "")
	_eq(_pod_plate(stations[0]), Rect2(1, -84, 190, 10), "held lens moves the widened name to the outer row")
	stations[0].show_lens(false, "")
	_seat_far(stations, [0, 1, 2])
	_eq(_pod_plate(stations[0]), Rect2(1, -96, 94, 10), "taking seat 1 returns its slot")
	_seat_far(stations, [1])
	_eq(_pod_plate(stations[2]), Rect2(49, -96, 190, 10), "a lone middle seat borrows half from both neighbours")
	_seat_far(stations, [3])
	_eq(_pod_plate(stations[6]), Rect2(193, -96, 190, 10), "the last column borrows left")
	_seat_far(stations, [1, 3])
	_eq(_pod_plate(stations[2]), Rect2(49, -96, 190, 10), "vacant 2 goes to its left neighbour first")
	_eq(_pod_plate(stations[6]), Rect2(289, -96, 94, 10), "not to seat 3 as well")
	for station in stations:
		station.show_plates_always(false)
		_check(not _plate_of(station).visible, "larger maps hide unselected unhovered plates")


func test_a_plate_at_rest_stands_clear_of_its_label_and_partition() -> void:
	_world()
	var zone := _side_zone("tags/1", 1, [_side_room("tab-t", 1, 0, 8)])
	var map := MapModel.of_zones("tags", [zone] as Array[ZoneModel])
	var plan := OfficeFloorLayout.plan(map, null, FloorLayoutPolicy.new(), OfficeDecorPlanner.new(pen)).plan
	_check(plan != null and plan.zones.size() == 1, "one zone planned")
	if plan == null or plan.zones.size() != 1:
		return
	var floor_root := Node2D.new()
	world.add_child(floor_root)
	var view := OfficeFloorView.new()
	view.setup(pen, floor_root)
	view.reconcile(plan, map)
	view.update_desks(map, "", false)
	await process_frame
	var pod: OfficeDeskView = view.desks["tab-t"]
	var to_floor := floor_root.get_global_transform().affine_inverse()
	var label := to_floor * pod.title.get_global_rect()
	var ink: Array[Vector2] = []
	for piece in view.partition_sprites(plan.zones[0].zone_key):
		for cell: Vector2i in _texels(piece, to_floor):
			ink.append((Vector2(cell) + Vector2(0.5, 0.5)) / 2.0)
	_check(ink.size() > 100, "the zone's partition is really drawn")
	var fars: Array[PackedInt32Array] = [[0, 1, 2, 3], [0, 2], [0, 3], [1, 2]]
	var nears: Array[PackedInt32Array] = [[0, 1, 2, 3], [1, 3], [1], [0, 2, 3]]
	for pattern in fars.size():
		for station in pod.stations:
			if station.column in (fars[pattern] if station.side == "far" else nears[pattern]):
				station.furnish("claude", ArtContract.STATE_WORKING)
				station.show_name(LONG_NAME)
			else:
				station.vacate()
			station.show_plates_always(true)
		OfficeFloorView.widen_plates(pod.stations)
		for station in pod.stations:
			var plate := _plate_of(station)
			if not plate.visible:
				continue
			var row := to_floor * plate.get_global_rect()
			_check(not row.grow(2.0).intersects(label), "%s: two units clear of the title" % station.name)
			var near := ink.filter(func(at: Vector2) -> bool: return row.grow(2.0).has_point(at))
			_eq(near, [], "%s: two units clear of the partition's ink" % station.name)
