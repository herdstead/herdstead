extends "res://tools/test_base.gd"
## Public workstation geometry and identity across repeated placement.

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
	var bubble := station.bubble_rect()
	var bubble_shape: CollisionShape2D = station.get_node(OfficeStation.BUBBLE_TARGET)
	var shape_at := bubble_shape.global_position
	var worker := station.actor()
	_check(bubble.has_area(), "a blocked seat has a bubble")
	station.setup(pen, table, 0, "far")
	station.furnish("claude", ArtContract.STATE_BLOCKED)
	_eq(station.target_rect(), target, "same setup keeps the seat's click target")
	_eq(station.bubble_rect(), bubble, "and the bubble")
	_eq(bubble_shape.global_position, shape_at, "and the bubble's click target")
	_eq(station.actor(), worker, "same setup keeps worker node")


func test_measure_is_the_capacity_and_clearance_contract() -> void:
	# A pod of single desks (docs/WORLD_MODEL.md): one 32-unit desk per column,
	# a 48-deep desktop, six reserved cells from the far approach row to the
	# near one with a passage cell on the right, and the stationary drawing from
	# the far tag row's pulse envelope (-90) to the near one's foot (46).
	var minimum := OfficeTable.measure(0)
	_eq(minimum.capacity, 2, "even an empty tab reserves two columns")
	_eq(minimum.table_width, 64.0, "minimum pod width: two desks")
	for capacity in range(2, 17):
		var measured := OfficeTable.measure(capacity)
		_eq(measured.columns.size(), capacity, "one x coordinate per column")
		_eq(measured.table_width, capacity * 32.0, "one 32-unit desk per column")
		_eq(measured.physical_rect, Rect2(0, -48, measured.table_width, 48), "physical desktop only")
		_eq(measured.reserved_rect, Rect2(0, -128, measured.table_width + 32, 192), "walk and drawing reserve")
		_eq(measured.render_rect, Rect2(0, -90, measured.table_width, 136), "the stationary drawing")
		_check(measured.reserved_rect.encloses(measured.render_rect), "all stationary drawing fits reservation")
		for index in capacity:
			_eq(measured.columns[index], 16.0 + 32.0 * index, "growth never recenters an existing column")
			_eq(measured.seat_position(index, "far"), Vector2(16.0 + 32.0 * index, -36), "far seat")
			_eq(measured.seat_position(index, "near"), Vector2(16.0 + 32.0 * index, 22), "near seat")
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
	# Two short legs, one under each end column's near chair (which hides it
	# whenever somebody sits there), their foot above the chair's gas lift.
	_check(table.resize(4), "a pod with middle columns")
	var legs: Array[float] = []
	for child in table.get_node("Supports").get_children():
		var support := child as Sprite2D
		if support.texture != art.table.module_texture(&"leg_short"):
			continue
		var painted := support.texture.get_image().get_used_rect()
		legs.append(support.position.x + painted.get_center().x * support.scale.x)
		_eq(support.position.y, -2.0, "leg meets apron without a gap")
		_eq(support.position.y + painted.end.y * support.scale.y, 19.0, "its foot stands at pod y 19")
	legs.sort()
	_eq(legs, [table.columns[0], table.columns[3]], "the two legs are centred under the end columns")
	for index in table.columns.size():
		for point in table.task_light(index, "near").polygon:
			_check(point.y <= -8.0, "near light stops on the working top, not below the thin edge")


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
	var bubble := station.bubble_rect().position - station.global_position
	for step in 12:
		_check(station.rebind(table, 2, "far"), "repeat blocked binding")
		_eq(station.target_rect().position - station.global_position, blocked_target, "the seat's target stays put")
		_eq(station.bubble_rect().position - station.global_position, bubble, "and so does the bubble")
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
			station.bubble().show_wait(5999.0)
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
				station.bubble().show_wait(5999.0)
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
			# The lens line clears the figure and the badge as the plate does.
			station.show_lens(true, "99m+")
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
				var bubble := Rect2(station.bubble().position, OfficeStation.BUBBLE_SIZE)
				_check(not bubble.intersects(figure), "%s: the chip %s clears the figure %s" % [where, bubble, figure])
				_check(not bubble.intersects(text), "%s: and the plate's text %s" % [where, text])
				# One unit over the chip's left edge, so the wait has daylight on both sides.
				_eq(badge.position.x, bubble.position.x - 1.0, "%s: the badge over the chip's left edge" % where)
				_check(
					bubble.grow_side(SIDE_LEFT, 1.0).encloses(badge),
					"%s: the badge %s on the chip %s" % [where, badge, bubble]
				)
				_check(badge.end.x <= bubble.position.x + OfficeBubble.BADGE_SLOT, "%s: in its left half" % where)
				var overlay := station.get_node("Overlay")
				_check(
					badge_node.get_index() > station.bubble().get_index() and badge_node.get_parent() == overlay,
					"%s: the badge is drawn over the chip" % where
				)
				var wait: Label = station.bubble().get_node("%Wait")
				_eq(wait.text, "99m", "%s: the chip says the wait, compactly" % where)
				var inside := Rect2(Vector2.ZERO, OfficeBubble.SIZE).encloses(Rect2(wait.position, wait.size))
				_check(inside, "%s: the chip's wait stays inside its frame" % where)
				var drawn := _in_station(station, wait, Rect2(Vector2.ZERO, wait.size))
				_check(not drawn.intersects(badge), "%s: the wait %s clears the badge %s" % [where, drawn, badge])
		station.free()


## The lens line on each side and over a worker resting away: its row is the
## one between the tag row and the plate row (far pod [-102, -90), near
## [46, 58)), its text clears the badge at the top of its pulse and the
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
		station.bubble().show_wait(240.0)
		var badge_node: StatusBadge = station.get_node("Overlay/Badge")
		var chipped := badge_node.position
		station.show_lens(true, "99m+")
		var line: Label = station.get_node("Overlay/Lens")
		_check(line.is_visible_in_tree(), "%s: the line shows" % side)
		var in_table := table.global_transform.affine_inverse() * line.get_global_transform()
		var drawn := in_table * Rect2(Vector2.ZERO, line.size)
		var row := Rect2(1, -102, 30, 12) if side == "far" else Rect2(1, 46, 30, 12)
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
			var drawn_part: CanvasItem = station.bubble().get_node(part)
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


func test_optional_decor_cannot_cover_wall_title_or_sign() -> void:
	world = Node2D.new()
	root.add_child(world)
	for width: int in [1, 12, 20]:
		var policy := FloorLayoutPolicy.new()
		# Width 1 asks the planner for its measured minimum, without copying the
		# table's dimensions. Wider floors also exercise retained decoration: at
		# the measured minimum (7 cells since the pod of desks; it was 11) the
		# planner retains no optional piece (measured), so the rule is only
		# checked there, not exercised.
		policy.width_cells = width
		policy.actor_footprint = PixelPerson.footprint()
		policy.actor_draw_rect = PixelPerson.drawing_rect(art.people)
		var model := ZoneModel.new()
		model.key = "minimum-title-floor"
		var room := RoomModel.new()
		room.key = "long-title-tab"
		room.label = "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
		model.rooms.append(room)
		var result := OfficeFloorLayout.plan(model, null, policy, OfficeDecorPlanner.new(pen))
		_eq(result.problems, PackedStringArray(), "base floor is valid")
		_check(result.plan != null, "base floor can be decorated")
		if result.plan == null:
			continue
		_eq(OfficeFloorLayout.validate(result.plan, policy), PackedStringArray(), "decorated plan keeps clear paths")
		if width > 1:
			_check(not result.plan.decorations.is_empty(), "safe optional furniture is retained at %d cells" % width)
		var floor_root := Node2D.new()
		floor_root.position = Vector2(17, 23)
		world.add_child(floor_root)
		var view := OfficeFloorView.new()
		view.setup(pen, floor_root)
		view.reconcile(result.plan, MapModel.of(model))
		await process_frame
		var desk := view.desks[room.key]
		_eq(desk.title.text, room.label, "the real label contains the long title")
		var label_transform := floor_root.global_transform.affine_inverse() * desk.title.get_global_transform()
		var label_bounds := label_transform * Rect2(Vector2.ZERO, desk.title.size)
		var signs: Array[Rect2] = []
		for child in desk.background.get_children():
			if child is Sprite2D:
				var sign_sprite: Sprite2D = child
				var sign_transform := floor_root.global_transform.affine_inverse() * sign_sprite.global_transform
				signs.append(sign_transform * sign_sprite.get_rect())
		_eq(signs.size(), 1, "the actual wall sign is present")
		for sign_bounds in signs:
			_check(
				(
					label_bounds.position.x >= sign_bounds.position.x + 6.0
					and label_bounds.end.x <= sign_bounds.end.x - 6.0
				),
				"long title stays inside the native sign with room for its frame"
			)
		for decoration in result.plan.decorations:
			_check(not decoration.draw_rect.intersects(label_bounds), "decor leaves the actual font-sized label clear")
			for sign_bounds in signs:
				_check(not decoration.draw_rect.intersects(sign_bounds), "decor leaves the dressed sign clear")
		floor_root.free()


## The wall-foot run and the spare bay's plant never cover a sign or a
## title as they are drawn, the real font-sized label included: several tabs
## with long titles to a row, at the shipped widths, and every sign of the row.
func test_the_wall_run_leaves_every_drawn_sign_and_title_clear() -> void:
	world = Node2D.new()
	root.add_child(world)
	var runs := 0
	var bays := 0
	for width: int in [20, 32, 60]:
		var policy := FloorLayoutPolicy.new()
		policy.width_cells = width
		policy.actor_footprint = PixelPerson.footprint()
		policy.actor_draw_rect = PixelPerson.drawing_rect(art.people)
		var model := ZoneModel.new()
		model.key = "wall-run-floor-%d" % width
		for index in 3:
			var room := RoomModel.new()
			room.key = "tab-%d" % index
			room.number = index
			room.label = "MMMMMMMMMMMMMMMMMMMMMMMM"
			model.rooms.append(room)
		var result := OfficeFloorLayout.plan(model, null, policy, OfficeDecorPlanner.new(pen))
		_eq(result.problems, PackedStringArray(), "%d cells: the floor is valid" % width)
		if result.plan == null:
			continue
		var floor_root := Node2D.new()
		world.add_child(floor_root)
		var view := OfficeFloorView.new()
		view.setup(pen, floor_root)
		view.reconcile(result.plan, MapModel.of(model))
		await process_frame
		var covers: Array[Rect2] = []
		for tab: String in view.desks:
			var desk := view.desks[tab]
			var label_transform := floor_root.global_transform.affine_inverse() * desk.title.get_global_transform()
			covers.append(label_transform * Rect2(Vector2.ZERO, desk.title.size))
			for child in desk.background.get_children():
				if child is Sprite2D:
					var sign_sprite: Sprite2D = child
					var sign_transform := floor_root.global_transform.affine_inverse() * sign_sprite.global_transform
					covers.append(sign_transform * sign_sprite.get_rect())
		_eq(covers.size(), 2 * view.desks.size(), "%d cells: a sign and a title for every table" % width)
		for decoration in result.plan.decorations:
			if "/wall/" in decoration.key:
				runs += 1
			elif decoration.key.ends_with("/bay"):
				bays += 1
			for cover in covers:
				_check(
					not decoration.draw_rect.intersects(cover),
					"%d cells: %s clears %s" % [width, decoration.key, cover]
				)
		floor_root.free()
	_check(runs > 0 and bays > 0, "the floors stand a wall-foot run (%d) and a spare bay's plant (%d)" % [runs, bays])


## A station bound again and again, then moved to another table place and
## seat, still answers real clicks where it is now: its seat's rectangle picks
## (`picked`) and its bubble's asks (`asked`), each through the viewport's own
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
		var at := station.target_rect().get_center() if target == "seat" else station.bubble_rect().get_center()
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
				station.bubble().show_wait(60.0 * column)
				stations.append(station)
				bubbles.append(station.bubble_rect())
				chips.append(_shape_rect(station.get_node(OfficeStation.BUBBLE_TARGET)))
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
				_eq(stations[index].bubble_rect(), Rect2(), names[index] + ": with no chip")
				stations[index].furnish("claude", ArtContract.STATE_BLOCKED)
				stations[index].bubble().show_wait(60.0)
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
## and clear of every opaque pixel its own worker and the next column's worker
## draw while blocked (the raised hand is on the right). On the far side only
## what shows above the far edge counts: the desk hides the rest of the far
## worker. Pods of two, four and six desks.
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
		var workers: Dictionary[String, Rect2] = {}
		for column in table.columns.size():
			for side: String in OfficeTable.SIDES:
				var station := pen.station(sorted, table, column, side)
				station.furnish("claude", ArtContract.STATE_BLOCKED)
				var figure := _drawn_figure(station)
				figure.position += station.position - table.position
				if side == "far":
					figure = figure.intersection(Rect2(-1000, -1000, 3000, 1000 - OfficeTable.SURFACE_DEPTH))
				workers["%d/%s" % [column, side]] = figure
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
				for other: String in ["%d/%s" % [column, side], "%d/%s" % [column + 1, side]]:
					if workers.has(other):
						_check(
							not paper.intersects(workers[other]),
							"%s: clear of worker %s %s: %s" % [where, other, workers[other], paper]
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
		view.reconcile(room, placed, 0)
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
					station.bubble().show_wait(5999.0 if known else -1.0)
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
				var where := "shift %d, wait %s, lens %s, lift %d" % [shift, known, held, lift]
				_eq(clashes, PackedStringArray(), where + ": nothing meets")
				if shift == 0.0:
					_check_row_literals(upper, stations, known, held, lift)
	for station in stations:
		station.free()


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
	var frame: NinePatchRect = station.bubble().get_node("%Frame")
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
	var chip: CollisionShape2D = station.get_node(OfficeStation.BUBBLE_TARGET)
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
		var tag_top := -88.0 if far else 30.0
		var badge := to_pod * rows["badge"]
		var chipped := known and not held
		var badge_x := 0.0 if chipped else 8.5
		_eq(badge, Rect2(badge_x, tag_top + lift, 15, 16), "%s: the badge's pixels" % where)
		_eq(rows.has("chip"), chipped, "%s: a chip frame only with a wait, off the lens" % where)
		if chipped:
			_eq(to_pod * rows["chip"], Rect2(1, tag_top, 30, 16), "%s: the chip" % where)
		_eq(rows.has("lens"), held, "%s: the lens row only under the lens" % where)
		if held:
			_eq(to_pod * rows["lens"], Rect2(1, -102.0 if far else 46.0, 30, 12), "%s: the lens row" % where)
		_eq(to_pod * rows["plate"], Rect2(1, -114.0 if far else 58.0, 30, 12), "%s: the plate row" % where)
		_eq(
			to_pod * rows["chip rect"],
			Rect2(1, -90.0 if far else 28.0, 30, 18),
			"%s: the chip's click rectangle" % where
		)
		_eq(
			to_pod * rows["seat"],
			Rect2(1, -72.0 if far else -21.0, 30, 40 if far else 49),
			"%s: the seat's, under the chip" % where
		)
		var mark := to_pod * (station.get_node("Overlay/Selection") as Sprite2D).get_global_transform()
		var mark_canvas := mark * (station.get_node("Overlay/Selection") as Sprite2D).get_rect()
		_eq(mark_canvas, Rect2(0, -72.0 if far else -20.0, 32, 48), "%s: the seat mark's canvas" % where)


## The near badge hangs right under the near chair, on its column (the chair
## is opaque down to pod y 28, the badge's row is [30, 46)), and at every lift
## of its pulse, centred or in the chip, it never shares a texel with the
## chair: its pulse envelope [28, 46) only touches it. The badge over the head
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
		_eq(rest, Rect2(column - 7.5, -88.0 if side == "far" else 30.0, 15, 16), side + ": the badge on its column")
		var under := to_pod * (chair.get_global_transform() * _opaque_local(chair))
		if side == "near":
			_check(
				rest.position.x < under.end.x and rest.end.x > under.position.x and rest.position.y >= under.end.y,
				"near: right under the chair %s" % under
			)
		for known: bool in [true, false]:
			station.bubble().show_wait(60.0 if known else -1.0)
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
	var wait: Label = station.bubble().get_node("%Wait")
	var lens: Label = station.get_node("Overlay/Lens")
	var probe := Label.new()
	pen.style_display(probe, OfficeBubble.WAIT_PIXELS)
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
	blocked.bubble().show_wait(60.0)
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
	await _point(blocked.bubble_rect().get_center())
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
