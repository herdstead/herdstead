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


func _table() -> OfficeTable:
	world = Node2D.new()
	ground = Node2D.new()
	sorted = Node2D.new()
	world.add_child(ground)
	world.add_child(sorted)
	root.add_child(world)
	return pen.table(sorted, ground, "Measured", Vector2(160, 240), 160, [48.0, 112.0])


func test_repeated_table_setup_is_idempotent() -> void:
	var table := _table()
	var count := table.find_children("*", "", true, false).size()
	var first := table.seat(0, "far")
	table.equip(0, "far", true)
	table.light(0, "far", OfficeTable.Lamp.FOCUS)
	_check(table.setup(art, 160, [48.0, 112.0]), "same setup succeeds")
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
	var minimum := OfficeTable.measure(0)
	_eq(minimum.capacity, 2, "even an empty tab reserves two columns")
	_eq(minimum.table_width, 160.0, "minimum table width")
	for capacity in range(2, 17):
		var measured := OfficeTable.measure(capacity)
		_eq(measured.columns.size(), capacity, "one x coordinate per column")
		_eq(measured.table_width, capacity * 64.0 + 32.0, "whole module table capacity")
		_eq(measured.physical_rect, Rect2(0, -80, measured.table_width, 80), "physical table only")
		_eq(measured.reserved_rect, Rect2(-32, -192, measured.table_width + 64, 288), "walk and drawing reserve")
		_check(measured.reserved_rect.encloses(measured.render_rect), "all stationary drawing fits reservation")
		for index in capacity:
			_eq(measured.columns[index], 48.0 + 64.0 * index, "growth never recenters an existing column")
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
	var legs := 0
	for child in table.get_node("Supports").get_children():
		var support := child as Sprite2D
		if support.texture != art.table.module_texture(&"leg"):
			continue
		legs += 1
		_eq(support.position.y, -2.0, "leg meets apron without a gap")
		var painted := support.texture.get_image().get_used_rect()
		_eq(support.position.y + painted.end.y * support.scale.y, 37.0, "foot stays on its original floor")
	_eq(legs, 3, "all three supports keep their ground contact")
	for index in table.columns.size():
		for point in table.task_light(index, "near").polygon:
			_check(point.y <= -8.0, "near light stops on the working top, not below the thin edge")


func test_desktop_decor_survives_growth_state_updates_and_theme_rebuilds() -> void:
	var table := _table()
	var dusk := ArtPack.from_manifest("res://assets/dusk/manifest.json")
	for sample in 12:
		var identity := "machine-a/workspace-a/tab-%d" % sample
		_check(table.setup(art, 160, [48.0, 112.0]), "start with two columns")
		table.decorate(identity)
		var holder: Node2D = table.get_node("%Decorations")
		var original := holder.get_children()
		var rebuilt := pen.table(sorted, ground, identity, Vector2(400, 240), 160, [48.0, 112.0])
		var copy_holder: Node2D = rebuilt.get_node("%Decorations")
		_eq(original.size(), copy_holder.get_child_count(), "same identity recreates the same sparse layout")
		_check(table.resize(6), "grow the real table, not the reference")
		for child in original:
			var image := child as Sprite2D
			var reference := copy_holder.get_node(NodePath(image.name)) as Sprite2D
			_eq(holder.get_node(NodePath(image.name)), image, "growth retains decoration nodes")
			_eq(image.position, reference.position, "growth keeps old positions")
			_eq(image.texture, reference.texture, "growth keeps old variants")
		for side: String in OfficeTable.SIDES:
			table.equip(0, side, true, true)
			table.light(0, side, OfficeTable.Lamp.FOCUS)
			table.equip(0, side, false)
			table.light(0, side, OfficeTable.Lamp.OFF)
		table.set_selected(true)
		_check(table.resize(2), "shrink back to the original columns")
		table.decorate(identity)
		_eq(holder.get_children(), original, "shrink removes only additions; refresh never replaces old objects")
		_check(table.setup(dusk, 160, [48.0, 112.0]), "switch theme in place")
		for child in original:
			var image := child as Sprite2D
			var reference := copy_holder.get_node(NodePath(image.name)) as Sprite2D
			_eq(image.position, reference.position, "theme, state and focus never shift decor")
			var matched := false
			for id in ArtContract.DESK_ITEMS + ArtContract.DESK_CATS:
				if reference.texture == art.sprite_texture(art.prop_sprite(id)):
					matched = true
					_eq(
						image.texture, dusk.sprite_texture(dusk.prop_sprite(id)), "theme keeps the chosen semantic item"
					)
			_check(matched, "every decoration comes from the reusable library")
		rebuilt.free()


func test_desktop_library_varies_without_covering_equipment_or_leaving_the_top() -> void:
	var table := _table()
	_check(table.resize(6), "include new columns and both sides")
	for theme: String in ["daylight", "dusk"]:
		var pack := ArtPack.from_manifest("res://assets/%s/manifest.json" % theme)
		_check(table.setup(pack, table.width, table.columns), "check actual pixels in both themes")
		var seen: Dictionary[StringName, bool] = {}
		var cat_count := 0
		var far_count := 0
		var near_count := 0
		for sample in 64:
			table.decorate("machine-%d/workspace/desk" % sample)
			var holder: Node2D = table.get_node("%Decorations")
			cat_count += int(holder.has_node("Cat"))
			_check(holder.get_child_count() <= 7, "at most one item per column plus one cat")
			var painted: Array[Rect2] = []
			for child in holder.get_children():
				var image := child as Sprite2D
				_eq(image.scale, pack.unit_scale(), "props use native family density")
				_eq(image.texture_filter, pack.filter, "props use their family's sampling")
				# Texture pixels start at the sprite offset, not at its foot.
				var pixels := Rect2(image.texture.get_image().get_used_rect())
				pixels.position += image.offset
				var bounds := image.transform * pixels
				var far_top := Rect2(0, -80, table.width, 28)
				var near_top := Rect2(0, -28, table.width, 20)
				_check(
					far_top.encloses(bounds) or near_top.encloses(bounds),
					"paint stays on wood, clear of divider and lip"
				)
				far_count += int(far_top.encloses(bounds))
				near_count += int(near_top.encloses(bounds))
				for prior in painted:
					_check(not prior.intersects(bounds), "cat and items never overlap")
				painted.append(bounds)
				for column in table.columns.size():
					for side: String in OfficeTable.SIDES:
						var laptop := table.monitor(column, side)
						_check(
							not (laptop.transform * laptop.get_rect()).intersects(bounds),
							"even vacant laptops stay clear"
						)
				for id in ArtContract.DESK_ITEMS + ArtContract.DESK_CATS:
					if image.texture == pack.sprite_texture(pack.prop_sprite(id)):
						seen[id] = true
		for id in ArtContract.DESK_ITEMS + ArtContract.DESK_CATS:
			_check(seen.has(id), "varied identities exercise library variant " + id)
		# A done seat's paper stands on the same working planes, by the same rule.
		for column in table.columns.size():
			for side: String in OfficeTable.SIDES:
				table.show_papers(column, side, true)
				var stack := table.papers(column, side)
				_eq(stack.scale, pack.unit_scale(), "the paper uses the pack's density")
				var pixels := Rect2(stack.texture.get_image().get_used_rect())
				pixels.position += stack.offset
				var bounds := stack.transform * pixels
				var plane := Rect2(0, -80, table.width, 28) if side == "far" else Rect2(0, -28, table.width, 20)
				_check(plane.encloses(bounds), "%s %d %s: the paper stays on its side's wood" % [theme, column, side])
				table.show_papers(column, side, false)
		_check(cat_count > 0 and cat_count < 32, "cats occur, but most tables have no cat")
		_check(far_count > 0 and near_count > 0, "items are scattered on both working planes")


func test_laptops_align_with_workers_on_both_sides_after_growth() -> void:
	var table := _table()
	_check(table.resize(4), "include appended columns")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			station.furnish("codex", ArtContract.STATE_WORKING)
			var laptop := table.monitor(column, side)
			_eq(laptop.global_position.x, station.actor().global_position.x, "laptop is centered on its worker")
			_eq(laptop.position.y, -72.0 if side == "far" else -10.0, "laptop is at its sitter's edge, not the divider")
			_eq(laptop.scale, art.table.unit_scale(), "alignment never rescales the native art")
			var at := laptop.global_position
			station.furnish("", ArtContract.STATE_IDLE)
			_eq(laptop.global_position, at, "empty shell chair keeps the same edge-aligned laptop")
			station.free()


func test_shell_laptop_changes_in_place_and_survives_growth() -> void:
	var table := _table()
	for theme: String in ["daylight", "dusk"]:
		var pack := ArtPack.from_manifest("res://assets/%s/manifest.json" % theme)
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
	for invalid: float in [NAN, INF, 240.0]:
		_check(not table.setup(art, invalid, [48.0, 112.0]), "bad width is rejected")
	_check(not table.setup(art, 160, [NAN]), "non-finite seat is rejected")
	_check(not table.setup(art, 160, [48.0, 48.0]), "duplicate seat is rejected")
	_check(not table.relocate(Vector2.INF), "non-finite position is rejected")
	_check(not station.rebind(table, 50, "near"), "missing column is rejected")
	_check(not station.rebind(table, 0, "other"), "unknown side is rejected")
	_eq(table.width, 160.0, "bad update keeps old width")
	_eq(table.columns, [48.0, 112.0], "bad update keeps old columns")
	_eq(table.position, table_at, "bad position keeps old placement")
	_eq(table.seat(0, "near"), marker, "bad update keeps old marker")
	_eq(station.position, where, "bad rebind keeps old placement")
	_eq(station.actor(), worker, "bad rebind keeps worker")


func test_supported_station_drawing_stays_inside_measure() -> void:
	var table := _table()
	_check(table.resize(4), "measure four columns")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var station := pen.station(sorted, table, column, side)
			# Once as the world is, once with the lens held: its line is
			# drawn too, the widest wait the lens writes, and stays inside.
			for held: bool in [false, true]:
				_check_inside_measure(table, station, held)
			station.free()


## One pass of test_supported_station_drawing_stays_inside_measure(): every
## state, the lens `held` or not.
func _check_inside_measure(table: OfficeTable, station: OfficeStation, held: bool) -> void:
	var side := station.side
	for state: StringName in [ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_DONE]:
		station.furnish("claude", state, true)
		if state == ArtContract.STATE_BLOCKED:
			# A wait to tell draws the whole bubble: frame, number and bar.
			station.bubble().show_wait(240.0)
		station.show_lens(held, "1h 05m+")
		var line: Label = station.get_node("Overlay/Lens")
		_eq(line.is_visible_in_tree(), held, "%s %s: the lens line shows only while held" % [side, state])
		for child in station.find_children("*", "CanvasItem", true, false):
			var canvas := child as CanvasItem
			if not canvas.is_visible_in_tree():
				continue
			var bounds := Rect2()
			if child is Sprite2D:
				var sprite: Sprite2D = child
				if sprite.texture == null:
					continue
				bounds = sprite.get_rect()
			elif child is Control:
				var control: Control = child
				bounds = Rect2(Vector2.ZERO, control.size)
			else:
				continue
			var relative := table.global_transform.affine_inverse() * canvas.get_global_transform()
			_check(
				table.geometry.render_rect.encloses(relative * bounds),
				(
					"render envelope contains %s %s %s %s in %s"
					% [side, state, child.name, relative * bounds, table.geometry.render_rect]
				)
			)


## The labels hang on the pixel people as they are really drawn: every opaque
## pixel of every frame the worker plays, on both layers. No plate text and no
## badge ever covers the figure, a far plate's text sits just above the head
## (or a raised hand) instead of floating off it, a near plate hangs below the
## feet, and the selection mark frames the whole figure. A blocked worker's
## bubble covers none of it either, raised hand included, nor the plate's text
## or the badge. Plate text is upper case, so it is drawn between the label's
## top and its font's baseline.
func test_labels_clear_the_heads_they_hang_on() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		for state: StringName in [
			ArtContract.STATE_WORKING, ArtContract.STATE_BLOCKED, ArtContract.STATE_IDLE, ArtContract.STATE_DONE
		]:
			station.furnish("claude", state, true)
			var where := "%s %s" % [side, state]
			var figure := _drawn_figure(station)
			var text := _plate_text(station)
			var badge_node: Sprite2D = station.get_node("Overlay/Badge")
			var badge := _in_station(station, badge_node, badge_node.get_rect())
			var mark_node: Sprite2D = station.get_node("Overlay/Selection")
			var mark := _in_station(station, mark_node, mark_node.get_rect())
			_check(figure.size.y > 30, "%s: the worker is really drawn: %s" % [where, figure])
			_check(not text.intersects(figure), "%s: the plate's text %s clears the figure %s" % [where, text, figure])
			_check(not badge.intersects(figure), "%s: the badge %s clears the figure %s" % [where, badge, figure])
			_check(mark.encloses(figure), "%s: the selection mark %s frames the figure %s" % [where, mark, figure])
			# The lens line clears the figure and the badge as the plate does.
			station.show_lens(true, "1h 05m+")
			var lens := _lens_text(station)
			_check(not lens.intersects(figure), "%s: the lens line %s clears the figure %s" % [where, lens, figure])
			_check(not lens.intersects(badge), "%s: the lens line %s clears the badge %s" % [where, lens, badge])
			station.show_lens(false, "")
			if side == "far":
				var gap := figure.position.y - text.end.y
				_check(gap >= 1.0 and gap <= 10.0, "%s: the plate's baseline sits %s above the head" % [where, gap])
			else:
				_check(text.position.y >= figure.end.y, "%s: the plate hangs below the feet" % where)
			if state == ArtContract.STATE_BLOCKED:
				var bubble := Rect2(station.bubble().position, OfficeStation.BUBBLE_SIZE)
				_check(
					not bubble.intersects(figure), "%s: the bubble %s clears the figure %s" % [where, bubble, figure]
				)
				_check(not bubble.intersects(text), "%s: and the plate's text %s" % [where, text])
				var overlay := station.get_node("Overlay")
				_check(
					badge_node.get_index() > station.bubble().get_index() and badge_node.get_parent() == overlay,
					"%s: the badge is drawn over the bubble" % where
				)
				for part: String in ["%Wait", "%Track", "%Fill"]:
					var control: Control = station.bubble().get_node(part)
					var inside := Rect2(Vector2.ZERO, OfficeBubble.SIZE).encloses(Rect2(control.position, control.size))
					_check(inside, "%s: the bubble's %s stays inside its frame" % [where, part])
					var drawn := _in_station(station, control, Rect2(Vector2.ZERO, control.size))
					_check(
						not drawn.intersects(badge),
						"%s: the bubble's %s %s clears the badge %s" % [where, part, drawn, badge]
					)
		station.free()


## The lens line on each side and over a worker resting away: its box
## stays inside the table's render_rect at a seat, its text clears the badge
## and the plate's text, the far one stands left of the badge, the near one
## under the plate, and away it is centred over the worker, above their badge.
## While it shows the bubble draws nothing, and let go the line is gone.
func test_the_lens_line_stays_inside_the_desk_and_off_the_badge() -> void:
	var table := _table()
	for side: String in OfficeTable.SIDES:
		var station := pen.station(sorted, table, 0, side)
		station.furnish("claude", ArtContract.STATE_BLOCKED, false)
		station.bubble().show_wait(240.0)
		station.show_lens(true, "1h 05m+")
		var line: Label = station.get_node("Overlay/Lens")
		_check(line.is_visible_in_tree(), "%s: the line shows" % side)
		var box := _in_station(station, line, Rect2(Vector2.ZERO, line.size))
		var in_table := table.global_transform.affine_inverse() * line.get_global_transform()
		var drawn := in_table * Rect2(Vector2.ZERO, line.size)
		_check(
			table.geometry.render_rect.encloses(drawn), "%s: %s inside %s" % [side, drawn, table.geometry.render_rect]
		)
		var lens := _lens_text(station)
		var badge_node: Sprite2D = station.get_node("Overlay/Badge")
		var badge := _in_station(station, badge_node, badge_node.get_rect())
		_check(not lens.intersects(badge), "%s: the text %s clears the badge %s" % [side, lens, badge])
		_check(not lens.intersects(_plate_text(station)), "%s: and the plate's text" % side)
		if side == "far":
			_check(box.end.x <= badge.position.x, "far: left of the badge, %s beside %s" % [box, badge])
		else:
			_check(box.position.y >= _plate_text(station).end.y, "near: under the plate")
		for part: String in ["%Frame", "%Wait", "%Track", "%Fill"]:
			var drawn_part: CanvasItem = station.bubble().get_node(part)
			_check(not drawn_part.is_visible_in_tree(), "%s: the bubble draws no %s meanwhile" % [side, part])
		station.show_lens(false, "")
		_check(not line.visible, "%s: let go, no line" % side)
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
	for width: int in [1, 20]:
		var policy := FloorLayoutPolicy.new()
		# Width 1 asks the planner for its measured minimum, without copying the
		# table's dimensions. A wider floor also exercises retained decoration.
		policy.width_cells = width
		policy.actor_footprint = PixelPerson.footprint()
		policy.actor_draw_rect = PixelPerson.drawing_rect(art.people)
		var model := FloorModel.new()
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
		_check(not result.plan.decorations.is_empty(), "safe optional furniture is retained at both floor widths")
		var floor_root := Node2D.new()
		floor_root.position = Vector2(17, 23)
		world.add_child(floor_root)
		var view := OfficeFloorView.new()
		view.setup(pen, floor_root)
		view.reconcile(result.plan, model)
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
		var model := FloorModel.new()
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
		view.reconcile(result.plan, model)
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


## The bubble never lands on a click target it does not own: on tables from
## the narrowest to a wide one, every column and both sides blocked at once,
## no bubble meets any seat's rectangle, its own included, nor another bubble.
## The far badge's middle is the bubble's while it shows and the seat's again
## once it goes.
func test_the_bubble_clears_every_click_target_and_its_neighbours() -> void:
	for width: float in [160.0, 224.0, 288.0, 416.0]:
		var table := _table()
		var count := maxi(1, int((width - 32.0) / 64.0))
		var columns: Array = []
		for slot in count:
			columns.append(width / 2.0 - (count - 1) * 32.0 + slot * 64.0)
		_check(table.setup(art, width, columns), "a %s-wide table" % width)
		var bubbles: Array[Rect2] = []
		var seats: Array[Rect2] = []
		var names: Array[String] = []
		var stations: Array[OfficeStation] = []
		for column in columns.size():
			for side: String in OfficeTable.SIDES:
				var station := pen.station(sorted, table, column, side)
				station.furnish("claude", ArtContract.STATE_BLOCKED)
				stations.append(station)
				bubbles.append(station.bubble_rect())
				seats.append(station.target_rect())
				names.append("%s-wide column %d %s" % [width, column, side])
		for index in bubbles.size():
			_check(bubbles[index].has_area(), names[index] + ": a bubble")
			# The far badge, drawn over the far bubble, is the bubble's to answer.
			if names[index].ends_with("far"):
				var badge_at := stations[index].global_position + OfficeStation.BADGE_AT["far"] + Vector2(0, -8)
				_check(bubbles[index].has_point(badge_at), names[index] + ": the badge's middle is in the bubble")
				_check(not seats[index].has_point(badge_at), names[index] + ": and not in the seat's rectangle")
				stations[index].furnish("claude", ArtContract.STATE_WORKING)
				_check(
					stations[index].target_rect().has_point(badge_at),
					names[index] + ": working, the seat covers the badge"
				)
				_eq(stations[index].bubble_rect(), Rect2(), names[index] + ": with no bubble")
				stations[index].furnish("claude", ArtContract.STATE_BLOCKED)
			for other in seats.size():
				_check(
					not bubbles[index].intersects(seats[other]),
					"%s: the bubble %s clears %s's seat %s" % [names[index], bubbles[index], names[other], seats[other]]
				)
			for other in bubbles.size():
				if other != index:
					_check(
						not bubbles[index].intersects(bubbles[other]),
						"%s: the bubble clears %s's bubble" % [names[index], names[other]]
					)
		world.free()


## A done seat's paper sits right of its laptop: over the laptop's right edge
## by at most three columns of pixels, clear of the worker (x±10 around the
## seat) and of whatever the next column's decoration slot may hold, on either
## side, every column.
func test_the_paper_stack_sits_beside_the_laptop_and_off_the_neighbours() -> void:
	var table := _table()
	_check(table.resize(4), "four columns")
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			var where := "column %d %s" % [column, side]
			table.show_papers(column, side, true)
			var paper := _opaque(table.papers(column, side))
			var laptop := _opaque(table.monitor(column, side))
			var overlap := paper.intersection(laptop)
			_check(overlap.size.x <= 3.0, "%s: over the laptop by %s columns at most 3" % [where, overlap.size.x])
			_check(paper.position.x > laptop.position.x, "%s: on the laptop's right" % where)
			var seat := table.seat(column, side).position
			var figure := Rect2(seat.x - 10, seat.y - 45, 20, 45)
			_check(not paper.intersects(figure), "%s: clear of the worker %s: %s" % [where, figure, paper])
			# A cat only ever takes column 0's slot (OfficeTable), which is nobody's
			# next column; any other slot holds one of the desk items.
			if column + 1 < table.columns.size():
				var y := OfficeTable.DECOR_FAR if side == "far" else OfficeTable.DECOR_NEAR
				var slot := Vector2(table.columns[column + 1] + OfficeTable.DECOR_OFFSET, y)
				for id in ArtContract.DESK_ITEMS:
					var spec := art.prop_sprite(id)
					var used := Rect2(art.sprite_texture(spec).get_image().get_used_rect())
					var drawn := Rect2(slot + used.position - spec.pivot, used.size)
					_check(not paper.intersects(drawn), "%s: clear of the next column's %s %s" % [where, id, drawn])
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
		if capacity <= 4:
			# Exercise maximum fixed/per-column decoration cost, not a lucky
			# identity with no cat or desktop objects.
			var holder: Node2D = view.table.get_node("%Decorations")
			for sample in 256:
				view.table.decorate("budget-sample-%d" % sample)
				if holder.get_child_count() == capacity + 1:
					break
			_eq(holder.get_child_count(), capacity + 1, "small tables exercise the maximum decoration count")
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


## `bounds`, given in `node`'s own coordinates, in the station's.
func _in_station(station: OfficeStation, node: CanvasItem, bounds: Rect2) -> Rect2:
	return station.get_global_transform().affine_inverse() * node.get_global_transform() * bounds
