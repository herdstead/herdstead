extends "res://tools/test_base.gd"
## What tools/test_office_incremental.gd stands on: the live office it drives,
## the snapshots it feeds, the rebuild it compares with, real input events, and
## the typed lookups into the world. Moved out of that suite unchanged so the
## suite stays under gdlint's max-file-lines; it holds no cases of its own.

## What herdr 0.9.0 sends in a pane's AgentInfo record and never in its PaneInfo.
const AGENT_RECORD_ONLY: Array[String] = ["launch_pending", "name", "interactive_ready"]
const MANIFESTS := ["res://assets/daylight/manifest.json"]
const LOCAL := HerdrFleet.LOCAL
## The second machine of the cases that need one (_two_machine_office()).
const BEE := "socket:bee"
## The live office with a viewport size this suite decides; see the file.
const OfficeDouble := preload("res://tools/office_double.gd")
## The window every case gives the office, and the one _live_office() tells it
## to lay out for. The headless root is 64x64, and the viewport only picks what
## its visible rect holds, so a click on a desk needs a window that big.
const SCREEN := Vector2i(800, 480)

var args: Dictionary[String, String] = {}
## tools/fixtures/snapshot_floors.json: Local focus on floor 1 (`api`), with
## blocked and UNREAD agents on floors 2 (`web`) and 3 (`infra`).
var fixture: Dictionary = {}
var _live_offices: Array[OfficeDouble] = []
## Office instance id -> the raw snapshot last fed to it. The client keeps only
## the typed HerdrSnapshot, so a recovery that re-sends the same response
## (_set_online) takes it from here.
var _fed: Dictionary[int, Dictionary] = {}


## Every node the HUD holds, by instance: a rebuild anywhere in it shows up as
## a different list. Sorted, because the agent list moves a kept row to its new
## group on a status change: an order is not a new node.
func _hud_nodes(office: OfficeDouble) -> Array:
	var found: Array = []
	for node: Node in office.hud.find_children("*", "", true, false):
		found.append(node.get_instance_id())
	found.sort()
	return found


## The node under the y-sorted root through which `node` is sorted: the first
## one on the way down that does not merge its children into the sort.
func _entity_of(sorted: Node, node: Node) -> Node:
	var chain: Array = []
	var at := node
	while at != sorted:
		chain.push_front(at)
		at = at.get_parent()
	for step: Node in chain:
		if not (step is Node2D and (step as Node2D).y_sort_enabled):
			return step
	return node


# --- office -------------------------------------------------------------------


## An office in the tree with its Local client stopped, showing `snapshot` as live.
func _live_office(snapshot: Dictionary = fixture, screen := Vector2(SCREEN)) -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = screen
	office.manifest_path = MANIFESTS[0]
	# Never write the user's theme choice from a test.
	office.remember_theme = false
	root.add_child(office)
	# Nothing should reconnect, poll herdr or rewrite the snapshot behind the test.
	_local(office).stop()
	office.fleet._roster.stop()
	_feed(office, snapshot)
	await _frames(2)
	return office


func _local(office: OfficeDouble) -> HerdrClient:
	return office.fleet._sites[0].client


func _feed(office: OfficeDouble, snapshot: Dictionary, online := true) -> void:
	# This fixture injection represents a complete fresh snapshot response.
	_fed[office.get_instance_id()] = snapshot.duplicate(true)
	# Online first, as a real connection is before its first snapshot: whoever
	# hears that snapshot become current (the fleet's state log) hears it live.
	var client := _local(office)
	var went_online := online and not client.online
	if went_online:
		client.online = true
	client._apply_snapshot(snapshot.duplicate(true))
	if went_online:
		# Setting `online` by hand announces nothing: say what a real connect would.
		office.fleet.liveness_changed.emit()
	office.refresh()


## A snapshot reaches Local as its stream delivers one: the fleet queues its
## refresh for the end of the frame and nothing is drawn yet (_feed() draws it
## at once).
func _arrive(office: OfficeDouble, snapshot: Dictionary) -> void:
	_fed[office.get_instance_id()] = snapshot.duplicate(true)
	_local(office)._apply_snapshot(snapshot.duplicate(true))


func _set_online(office: OfficeDouble, online: bool) -> void:
	if online:
		_local(office).online = true
		# Manual fixture recovery explicitly supplies a new, possibly identical response.
		var last: Dictionary = _fed.get(office.get_instance_id(), {})
		_local(office)._apply_snapshot(last.duplicate(true))
	else:
		_local(office)._go_offline()
	# Setting `online` by hand announces nothing, and a snapshot that was
	# already current does not either: say what a real reconnect would.
	office.fleet.liveness_changed.emit()


func _done(office: OfficeDouble) -> void:
	_live_offices.erase(office)
	_fed.erase(office.get_instance_id())
	root.remove_child(office)
	# Another case may resize the root before a deferred free runs. Disconnect
	# its window/viewport callbacks now, with the rest of this owned fixture.
	office.free()


## A script error can skip a case's explicit teardown. Remove its attention
## timer before the next case, so one failure cannot rewrite another's badges.
func _after_case() -> void:
	for office: OfficeDouble in _live_offices.duplicate():
		if is_instance_valid(office):
			_done(office)
	_live_offices.clear()


## The same snapshot with herdr's session focus on another pane.
func _focused_on(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	result.focused_pane_id = pane_id
	return result


## The same snapshot with one workspace naming another of its tabs as open.
func _open_tab_of(snapshot: Dictionary, workspace_id: String, tab_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for workspace: Dictionary in _list(result, "workspaces"):
		if workspace.get("workspace_id", "") == workspace_id:
			workspace.active_tab_id = tab_id
	return result


## The focus-underline level of every seat with a pane on the shown map, by pane id;
## only workspace `zone`'s (the fixture's pane ids begin with it) when given.
func _lamps(office: OfficeDouble, zone := "") -> Dictionary:
	var result := {}
	for station in _seats(office):
		if not zone.is_empty() and not HerdrFleet.split_key(station.pane_key)[1].begins_with(zone + ":"):
			continue
		result[HerdrFleet.split_key(station.pane_key)[1]] = _lamp_level(station)
	return result


## The enum is retained, but its drawing is the station's focus underline,
## not a separate lamp or a table component.
func _lamp_level(station: OfficeStation) -> OfficeTable.Lamp:
	var underline: Polygon2D = station.get_node("Focus")
	_eq(underline.visible, station.light_level != OfficeTable.Lamp.OFF, "the focus underline agrees with its level")
	var color := station.art.color(ArtContract.TASK_LIGHT)
	var strength: Array[float] = [0.0, 0.15, 0.35, 1.0]
	color.a = strength[station.light_level]
	_eq(underline.color, color, "its drawn colour and strength agree too")
	return station.light_level


## Every table of the shown floor, by name, with the node drawing it.
func _table_ids(office: OfficeDouble) -> Dictionary:
	var result := {}
	for table: OfficeTable in office.floor_view.tables:
		result[str(table.name)] = table.get_instance_id()
	return result


## `snapshot` with pane `pane_id` changed by `changes`: the pane's own fields
## merged into its PaneInfo, the fields herdr 0.9.0 sends in AgentInfo only
## (AGENT_RECORD_ONLY) into its agent record, where a null removes one. A pane
## without a record that is given one of those gets one with its ids, as herdr
## lists a shell it launches an agent in.
func _with(snapshot: Dictionary, pane_id: String, changes: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var pane_changes := changes.duplicate()
	var record_changes := {}
	for field: String in AGENT_RECORD_ONLY:
		if changes.has(field):
			record_changes[field] = changes[field]
			pane_changes.erase(field)
	var changed_pane := {}
	for pane: Dictionary in result.panes:
		if pane.pane_id == pane_id:
			pane.merge(pane_changes, true)
			changed_pane = pane
	# Official v0.9.0 serializes launch_pending in AgentInfo, never PaneInfo.
	var records: Array[Dictionary] = []
	for agent: Dictionary in _list(result, "agents"):
		if str(agent.get("pane_id", "")) == pane_id:
			records.append(agent)
	if records.is_empty() and not record_changes.is_empty() and not changed_pane.is_empty():
		var made := {}
		for field: String in ["terminal_id", "pane_id", "workspace_id", "tab_id"]:
			made[field] = changed_pane.get(field)
		var agents := _list(result, "agents")
		agents.append(made)
		result["agents"] = agents
		records.append(made)
	for agent in records:
		for field: String in record_changes:
			if record_changes[field] == null:
				agent.erase(field)
			else:
				agent[field] = record_changes[field]
	return result


## Finish only finite image clips before comparing two independently started
## worlds. Loop clocks and frozen frames are never advanced here. Transition
## order and refresh clock retention are asserted separately, not normalized
## away by the rebuild comparison.
func _finish_workstation_clips(office: OfficeDouble) -> void:
	for station in _seats(office):
		var actor := station.actor()
		if actor == null:
			continue
		for step in 3:
			if (
				not actor.is_playing()
				or actor.track not in [&"blocked_enter", &"blocked_exit", &"done", &"starting", &"unknown"]
			):
				break
			var player: AnimationPlayer = actor.get_node("AnimationPlayer")
			player.advance(player.current_animation_length + 0.001)


## Compare the world after in-place updates with a rebuild from the same data.
func _same_as_rebuild(office: OfficeDouble, when: String) -> void:
	await _frames(2)
	# A seat under the pointer shows its plate, and physics picking finds what
	# is under a still pointer again every physics frame: sample both worlds
	# after it has run, so both are hovered alike.
	await _physics_frames(2)
	# Text normally updates on a 250ms beat. Sample both worlds after that same
	# text evaluation, not one before its first wait label tick and one after it.
	office.attention._update_waits()
	_finish_workstation_clips(office)
	var updated := _fingerprint(office.world)
	var rects := _desk_rects(office)
	var models := {}
	for key: String in office.floor_view.seats:
		models[key] = [office.floor_view.seats[key].look, office.floor_view.seats[key].selected]
	var world_id: int = office.world.get_instance_id()
	office.rebuild_world()
	_check(office.world.get_instance_id() != world_id, "the rebuild really rebuilt " + when)
	await _frames(2)
	await _physics_frames(2)
	office.attention._update_waits()
	_finish_workstation_clips(office)
	var rebuilt := _fingerprint(office.world)
	_eq(updated.size(), rebuilt.size(), "node count " + when)
	for index in mini(updated.size(), rebuilt.size()):
		if updated[index] != rebuilt[index]:
			_fail(
				"first differing node %s:\n    in place: %s\n    rebuilt:  %s" % [when, updated[index], rebuilt[index]]
			)
			break
	_eq(_desk_rects(office), rects, "click targets " + when)
	var rebuilt_models := {}
	for key: String in office.floor_view.seats:
		rebuilt_models[key] = [office.floor_view.seats[key].look, office.floor_view.seats[key].selected]
	_eq(rebuilt_models, models, "desk models " + when)


## One line per node, depth first in child order: everything that decides what
## is drawn and in which layer, and nothing that is only a node's identity or
## how far along its animation is.
func _fingerprint(node: Node, depth := 0, out: Array = []) -> Array:
	var name := str(node.name)
	# Auto names carry instance ids; only chosen names are compared.
	var parts: Array = [depth, node.get_class(), "@" if name.begins_with("@") else name]
	if node is CanvasItem:
		var item: CanvasItem = node
		parts.append_array(
			[item.visible, item.modulate, item.self_modulate, item.z_index, item.z_as_relative, item.texture_filter]
		)
	if node is Node2D:
		var placed: Node2D = node
		parts.append_array([placed.position, placed.rotation, placed.scale])
	if node is Control:
		var control: Control = node
		# Containers leave a hidden label's old allocation untouched. That
		# invisible geometry is not part of the rendered rebuild contract.
		if control.is_visible_in_tree():
			parts.append_array([control.position, control.size])
	if node is Sprite2D:
		var sprite: Sprite2D = node
		# A pulsing badge's offset follows attention's clock, like an actor's frame;
		# where it rests is what the desk decides.
		var offset := sprite.offset
		if node is StatusBadge:
			var badge: StatusBadge = node
			offset = badge.rest_offset
			parts.append_array([badge.machine, badge.pane_id, badge.state])
		# A hidden badge or an undressed layer has no texture.
		var image := sprite.texture
		var texture: Variant = [image.resource_path, image.get_size()] if image != null else null
		# The complete sheet's cell size and any mirroring change its drawing.
		parts.append_array(
			[
				texture,
				offset,
				sprite.centered,
				sprite.region_enabled,
				sprite.hframes,
				sprite.vframes,
				sprite.flip_h,
				sprite.flip_v
			]
		)
	if node is WorkstationActor:
		var actor: WorkstationActor = node
		var player: AnimationPlayer = actor.get_node("AnimationPlayer")
		# A complete image, its provider and requested state, never its clock.
		parts.append_array([actor.provider, actor.animation, actor.is_playing()])
		# A permanent empty image stops the player but has no requested agent
		# state. Its previously assigned clip is not displayed by the empty PNG.
		if not actor.animation.is_empty():
			parts.append_array([actor.track, player.assigned_animation])
	if node is CollisionShape2D:
		var shape: CollisionShape2D = node
		parts.append(shape.disabled)
	if node is CollisionObject2D:
		var body: CollisionObject2D = node
		# Whether a seat answers a click at all is part of what is drawn there.
		parts.append_array([body.input_pickable, body.collision_layer, body.collision_mask])
	if node is Polygon2D:
		var polygon: Polygon2D = node
		parts.append_array([polygon.polygon, polygon.color])
	if node is Line2D:
		var line: Line2D = node
		parts.append_array([line.points, line.width, line.default_color, line.closed])
	if node is Label:
		var label: Label = node
		parts.append_array(
			[
				label.text,
				label.horizontal_alignment,
				label.clip_text,
				label.text_overrun_behavior,
				label.get_theme_color("font_color"),
				label.get_theme_font_size("font_size")
			]
		)
	if node is TileMapLayer:
		var layer: TileMapLayer = node
		var cells: Array = []
		for cell: Vector2i in layer.get_used_cells():
			cells.append([cell, layer.get_cell_atlas_coords(cell)])
		cells.sort()
		parts.append(cells)
	var groups: Array = (
		Array(node.get_groups())
		. map(func(g: StringName) -> String: return str(g))
		. filter(func(g: String) -> bool: return not g.begins_with("_"))
	)
	groups.sort()
	parts.append(groups)
	var metas: Array = []
	for key: StringName in node.get_meta_list():
		metas.append([str(key), node.get_meta(key)])
	metas.sort()
	parts.append(metas)
	out.append(var_to_str(parts))
	for child in node.get_children():
		_fingerprint(child, depth + 1, out)
	return out


## Instance id of every node of every desk except `skip`, by pane key.
func _desk_ids(office: OfficeDouble, skip: String, skip_too := "") -> Dictionary:
	var result := {}
	for key: String in office.floor_view.seats:
		if key == skip or key == skip_too:
			continue
		var desk: Node2D = office.floor_view.seats[key].node
		result[key] = [desk.get_instance_id(), _child_ids(desk)]
	return result


## The lifts a badge was seen at, smallest first.
func _sorted_lifts(lifts: Dictionary) -> Array:
	var values := lifts.keys()
	values.sort()
	return values


func _child_ids(desk: Node) -> Dictionary:
	var result := {}
	for child in desk.get_children():
		result[str(child.name)] = child.get_instance_id()
	return result


func _names(desk: Node) -> Array:
	return desk.get_children().map(func(n: Node) -> String: return str(n.name))


func _actor_progress(office: OfficeDouble, skip: String) -> Dictionary:
	var result := {}
	for key: String in office.floor_view.seats:
		var actor := _worker(office.floor_view.seats[key].node)
		if key != skip and actor != null:
			result[key] = _actor_state(actor)
	return result


## A whole-image actor's node, clip clock and Body frame.
func _actor_state(actor: WorkstationActor) -> Array:
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	return [
		actor.get_instance_id(),
		player.assigned_animation,
		player.current_animation_position,
		_sprite(actor, "Body").frame
	]


func _all_actor_ids(office: OfficeDouble) -> Array:
	var ids: Array = []
	for station in _seats(office):
		if station.actor() != null:
			ids.append(station.actor().get_instance_id())
	ids.sort()
	return ids


func _playing(office: OfficeDouble) -> Array:
	var seen := {}
	for station in _seats(office):
		if station.actor() != null:
			seen[station.actor().is_playing()] = true
	return seen.keys()


## The state the desk's badge for `pane_id` on `machine` pulses for.
func _badge_state(machine: String, pane_id: String) -> String:
	var found: Array = []
	for badge: StatusBadge in get_nodes_in_group(StatusBadge.GROUP):
		if badge.machine == machine and badge.pane_id == pane_id:
			found.append(str(badge.state))
	return found[0] if found.size() == 1 else "%d badges" % found.size()


## The viewport point a click on the desk drawn for `key` lands on: where that
## seat answers a click, seen through the camera the office pans with.
func _desk_point(office: OfficeDouble, key: String) -> Vector2:
	for station in _seats(office):
		if station.pane_key == key:
			return station.target_rect().get_center() - office.camera.position
	_fail("no click target for " + key)
	return Vector2(-1000, -1000)


## Every seat with a pane on the shown floor, in tree order. A repeated pane key
## really is drawn twice, which office.floor_view.seats (one Desk per key) cannot show.
func _seats(office: OfficeDouble) -> Array[OfficeStation]:
	var found: Array[OfficeStation] = []
	for node: Node in office.world.find_children("*", "", true, false):
		if node is OfficeStation:
			var station: OfficeStation = node
			if not station.pane_key.is_empty():
				found.append(station)
	return found


## Where every desk of the shown floor answers a click, by pane key, in the
## world's own coordinates: what the office once kept as a hand-made table.
func _desk_rects(office: OfficeDouble) -> Dictionary:
	var rects := {}
	for station in _seats(office):
		var bounds := station.target_rect()
		rects[station.pane_key] = Rect2(office.world.to_local(bounds.position), bounds.size)
	return rects


## Where the desk drawn for `key` answers a click, in global coordinates.
func _desk_target(office: OfficeDouble, key: String) -> Rect2:
	for station in _seats(office):
		if station.pane_key == key:
			return station.target_rect()
	_fail("no click target for " + key)
	return Rect2()


## Whether the desk drawn for `key` answers a click wholly inside the world's
## room on screen.
func _desk_in_view(office: OfficeDouble, key: String) -> bool:
	var target := _desk_target(office, key)
	return office.hud.world_rect().encloses(Rect2(target.position - office.camera.position, target.size))


## A seat whose click target's middle falls inside `bounds` on screen, or null.
func _seat_under(office: OfficeDouble, bounds: Rect2) -> OfficeStation:
	for station in _seats(office):
		if bounds.has_point(station.target_rect().get_center() - office.camera.position):
			return station
	return null


## Pan the table of the desk `key` into view. The floor opens on its entry band's
## queue and the selected desk (OfficeScene.reveal()); a case about the seats of
## a whole table asks for that table first.
func _frame_table(office: OfficeDouble, key: String) -> void:
	var table := _station(office, key).table
	var group := table.geometry.render_rect
	group.position += table.global_position
	office.camera.reveal(Rect2(office.world.to_local(group.position), group.size))
	await _frames(2)


## A seat at the shown floor's tables that no pane uses and that is on screen;
## null when the floor has none, which is a case that proves nothing.
func _vacant_seat(office: OfficeDouble) -> OfficeStation:
	for node: Node in office.world.find_children("*", "", true, false):
		if not node is OfficeStation:
			continue
		var station: OfficeStation = node
		var at := station.target_rect().get_center() - office.camera.position
		if station.vacant and office.hud.world_rect().has_point(at):
			return station
	return null


## A key the office would get from the window; `held` is the repeat an action
## must not answer twice.
func _key(keycode: Key, held := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = held
	return event


## One wheel notch, as the window delivers it.
func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


## A click in window pixels rather than content pixels, the way the platform
## delivers one: the viewport's stretch transform turns it back itself.
func _click_window(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = at
		event.global_position = at
		event.pressed = down
		root.push_input(event)
		await physics_frame
		await physics_frame


## Click the desk drawn for `key`, panning it into view first. A desk below the
## fold is one no click could ever reach: the viewport picks only what its
## visible rect holds, which is the same rule the screen itself has.
func _click_desk(office: OfficeDouble, key: String) -> void:
	office.reveal(key)
	await _frames(2)
	await _click(_desk_point(office, key))


## A real click: press and release at one viewport point, each given the physics
## frames the viewport needs to hand the seat's Area2D its pick. The office sees
## the button in _unhandled_input first and the seat reports it after.
func _click(at: Vector2) -> void:
	await _button(at, true)
	await _button(at, false)


## One half of a click, for the cases that care where the release lands.
func _button(at: Vector2, down: bool) -> void:
	await _button_of(at, MOUSE_BUTTON_LEFT, down)


## One half of a press of any button, for the cases about which button picks.
func _button_of(at: Vector2, button: MouseButton, down: bool) -> void:
	root.push_input(_mouse_button(at, button, down), true)
	await physics_frame
	await physics_frame


## A real drag: press, move, release through `Input`, not straight at the
## viewport. The office asks `Input.is_mouse_button_pressed()` before it pans,
## and only this path leaves that answer true (push_input never touches it).
func _drag(from: Vector2, to: Vector2) -> void:
	await _parsed(_mouse_button(from, MOUSE_BUTTON_LEFT, true))
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	await _parsed(motion)
	await _parsed(_mouse_button(to, MOUSE_BUTTON_LEFT, false))


func _parsed(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


func _mouse_button(at: Vector2, button: MouseButton, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	event.position = at
	event.global_position = at
	event.pressed = down
	return event


## A real left click at `at`, in viewport pixels.
func _click_at(at: Vector2) -> void:
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## A real pointer move to `at` (viewport pixels), then physics frames for the
## picking to answer.
func _pointer_to(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	await _frames(1)


## The release of a left press at `at`, handed to the window with no frame
## going by: what was queued for the end of this frame is still waiting when
## the gesture's own refresh runs.
func _release_now(at: Vector2) -> void:
	Input.parse_input_event(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	Input.flush_buffered_events()


func _world_ids(office: OfficeDouble) -> Array:
	var ids: Array = []
	for node in office.world.find_children("*", "", true, false):
		ids.append(node.get_instance_id())
	return ids


## A copy of the shipped pack at `density` pixels per unit, sampled the way
## `filter` names, as test_client.gd builds one, in the test's own directory.
## Named apart from tools/test_art.gd's table-less fixtures in the same
## directory: run_tests.sh gives every suite one work directory.
func _dense_pack(density: int, filter := "nearest") -> String:
	return _copied_pack(MANIFESTS[0], args.work.path_join("office-pack-x%d-%s" % [density, filter]), density, filter)


## The second pack the pack-switching cases switch to (test_base.gd).
func _second_pack() -> String:
	return _second_pack_at(args.work.path_join("office-pack-second"))


func _row_count(office: OfficeDouble) -> int:
	var rows := {}
	for station in _seats(office):
		rows[station.target_rect().position.y] = true
	return rows.size()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await physics_frame


## Whether an edge arrow stands over viewport point `at`, where it would take a click.
func _under_arrow(office: OfficeScene, at: Vector2) -> bool:
	if not office.hud.edge_arrows.is_visible_in_tree():
		return false
	for arrow in office.hud.edge_arrows.shown():
		if arrow.get_global_rect().has_point(at):
			return true
	return false


## Visit zone `key` without the mouse (S3 BAR-b, 2026-10-27: the SPACES rail
## is gone): real PageDown / PageUp presses, the direction from
## OfficeFrame.zone_order, until it is the zone the page keys stand on
## (OfficeNavigator.current_zone()). Each press is the pick_zone() a SPACES row
## click took. Nothing is pressed when it is already; fails after as many
## presses as there are zones.
func _visit_zone(office: OfficeScene, key: String) -> void:
	# S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire; the precondition was "the agent
	# list holds the keyboard", now any text field.
	var focus := office.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		_fail("a text field holds the keyboard: the page keys would not reach the office")
		return
	var order := office.frame.zone_order
	if not order.has(key):
		_fail("no zone " + key)
		return
	for press in order.size():
		var standing := office.navigator.current_zone(office.frame)
		if standing == key:
			return
		var down := standing.is_empty() or order.find(key) > order.find(standing)
		await _office_key(office, KEY_PAGEDOWN if down else KEY_PAGEUP)
	if office.navigator.current_zone(office.frame) != key:
		_fail("the page keys never reached " + key)


## A real left click on machine `key`'s chip in the top bar (S3 BAR-b,
## 2026-10-27: the SPACES rail's headings are gone).
func _click_heading(office: OfficeDouble, key: String) -> void:
	var chip := office.hud.bar.chip_for(key)
	if chip == null:
		_fail("no machine chip for " + key)
		return
	await _click_at(chip.get_global_rect().get_center())


## Each shown arrow's words, glyph to count, as one string.
func _arrow_texts(office: OfficeDouble) -> Array:
	return office.hud.edge_arrows.shown().map(
		func(arrow: OfficeEdgeArrow) -> String:
			var words := PackedStringArray()
			for part: String in ["%Glyph", "%Zone", "%Count"]:
				var label: Label = arrow.get_node(part)
				if label.visible:
					words.append(label.text)
			return " ".join(words)
	)


func _office_key(_to: OfficeScene, code: Key) -> void:
	var event := _key(code)
	await _parsed(event)
	event.pressed = false
	await _parsed(event)


## Wait for OfficeAttention's text beat, which comes round every TEXT_INTERVAL
## seconds of real time rather than every frame.
func _text_tick() -> void:
	var deadline := Time.get_ticks_msec() + int(OfficeAttention.TEXT_INTERVAL * 1000.0) + 150
	while Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(10)


## `snapshot` with `count` more agents, idle, in a tab of the api floor of
## their own that is projected before the others (number 0): residents that
## went idle first (their starts unknown, from the first snapshot they are in):
## more idle agents, each at their own seat with a mug, ahead of anyone a case
## watches in the `N` order. (They held pantry spots before D2, 2026-10-27: idle
## sits with a mug; the pantry is a nook nobody walks to.)
func _with_residents(snapshot: Dictionary, count := 3) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	_list(result, "tabs").append({"tab_id": "api:t0", "workspace_id": "api", "number": 0, "label": "residents"})
	var source: Dictionary = _list(result, "panes")[1]
	for index in count:
		var pane := source.duplicate(true)
		pane.pane_id = "api:r%d" % index
		pane.tab_id = "api:t0"
		pane.terminal_id = "term-api-r%d" % index
		pane.agent = "claude"
		pane.agent_status = "idle"
		_list(result, "panes").append(pane)
	return result


## Six workspaces of four working agents each, herdr's focus on the first: a
## map whose zones are a window apart.
func _six_zones() -> Dictionary:
	var raw := {"workspaces": [], "tabs": [], "panes": [], "layouts": [], "focused_pane_id": "w0:t0:p0"}
	for zone in 6:
		var workspace := "w%d" % zone
		var tab := workspace + ":t0"
		_list(raw, "workspaces").append({"workspace_id": workspace, "number": zone + 1, "label": workspace})
		_list(raw, "tabs").append({"workspace_id": workspace, "tab_id": tab, "number": 1})
		for index in 4:
			var pane := "%s:p%d" % [tab, index]
			_list(raw, "panes").append(
				{
					"workspace_id": workspace,
					"tab_id": tab,
					"pane_id": pane,
					"terminal_id": "terminal-" + pane,
					"agent": "claude",
					"agent_status": "working"
				}
			)
	return raw


## Every piece of standing furniture on the shown map, in tree order: the
## top-wall run's plants and the lane gaps' plants and side tables, not the
## entry band's pantry counter (_fixtures()), which stands in its corner of the
## walkway on purpose.
func _decor(office: OfficeDouble) -> Array[OfficeDecor]:
	var found: Array[OfficeDecor] = []
	for node: Node in office.world.find_children("*", "OfficeDecor", true, false):
		var piece: OfficeDecor = node
		if piece.piece != ArtContract.PROP_PANTRY:
			found.append(piece)
	return found


## The entry band's counter (the pantry) on the shown map, in tree order.
func _fixtures(office: OfficeDouble) -> Array[OfficeDecor]:
	var found: Array[OfficeDecor] = []
	for node: Node in office.world.find_children("*", "OfficeDecor", true, false):
		var piece: OfficeDecor = node
		if piece.piece == ArtContract.PROP_PANTRY:
			found.append(piece)
	return found


## Every semantic tile id laid on the floor's ground, as a set.
func _wall_cells(ground: Node2D) -> Dictionary:
	var found := {}
	for layer: TileMapLayer in ground.find_children("*", "TileMapLayer", true, false):
		for cell: Vector2i in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			found[StringName(str(data.get_custom_data("semantic_id")))] = true
	return found


## A measured pod's physical envelope in global coordinates. There is no
## furniture collider or separately assembled table surface.
func _table_rect(table: OfficeTable) -> Rect2:
	return table.global_transform * table.geometry.physical_rect


## Every line of text on the shown floor's plate, which is built with the floor
## and sits above its rooms.
func _plate_lines(office: OfficeDouble) -> Array:
	var found: Array = []
	for label: Label in office.world.get_node("MachinePlate").find_children("*", "Label", true, false):
		found.append(label.text)
	return found


## What the chip over the seat drawn for `key` says about how long its agent
## has waited.
func _wait_text(office: OfficeDouble, key: String) -> String:
	return _label(office.floor_view.seats[key].node.chip(), "%Wait").text


## --- typed node lookups -------------------------------------------------------
## `Node.get_node()` answers `Node`, which is not enough to read a property off.
## These say what the scene really holds there, once, instead of at every site.


func _sprite(parent: Node, path: String) -> Sprite2D:
	return parent.get_node(path)


## The state badge of a desk, where scenes/world/station.tscn keeps it.
func _badge(station: Node) -> StatusBadge:
	return station.get_node("Overlay/Badge")


func _label(parent: Node, path: String) -> Label:
	return parent.get_node(path)


## The occupied workstation, or null for a shell/vacancy. Actor is a permanent
## child even when actor() is null, so node presence is not occupancy.
func _worker(station: Node) -> WorkstationActor:
	return (station as OfficeStation).actor()


## The name plate over a seat.
func _plate(station: Node) -> Label:
	return station.get_node("Overlay/Plate")


## The HUD's screen-space root, which carries the Theme the art pack built.
func _screen_of(hud: OfficeHud) -> Control:
	return hud.get_node("Screen")


## The seat drawn for `key`, found the way the tree holds it.
func _station(office: OfficeDouble, key: String) -> OfficeStation:
	for station in _seats(office):
		if station.pane_key == key:
			return station
	_fail("no seat for " + key)
	return null


## The fixture with an agent at api:p3, so floor 1 seats workers on both sides of
## its first table: api:p1 far, api:p3 near.
func _both_sides() -> Dictionary:
	return _with(fixture, "api:p3", {"agent": "pi"})


## Local and a second machine, `bee`, on a socket nobody answers: both clients
## stopped, fed by hand.
## `screen` is the window (the walking suites plan 488 wide: PLAN_SCREEN).
func _two_machine_office(first := fixture, screen := Vector2(SCREEN)) -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = screen
	office.test_args = AppArgs.parse(
		PackedStringArray(
			[
				"--read-only",
				"--socket=" + args.socket,
				"--machine-socket=bee=" + args.work.path_join("bee-nowhere.sock")
			]
		)
	)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	_feed(office, first)
	_feed_bee(office, _bee_snapshot("blocked"))
	await _frames(2)
	return office


## A HUD on its own, laid out for the suite's screen.
func _hud() -> OfficeHud:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: OfficeHud = scene.instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(Vector2(SCREEN))
	await _frames(2)
	return hud


func _bee(office: OfficeDouble) -> HerdrClient:
	return office.fleet._sites[1].client


## Feed `bee` a fresh snapshot, live.
func _feed_bee(office: OfficeDouble, snapshot: Dictionary) -> void:
	var client := _bee(office)
	client.stop()
	client.online = true
	client._apply_snapshot(snapshot.duplicate(true))
	office.fleet.liveness_changed.emit()


## `snapshot` reaches bee as its stream delivers one, live: the state log
## hears a change in it as an event (_feed_bee() reconnects bee first, a
## baseline the log keeps no pane event of). Drawn at once.
func _bee_live(office: OfficeDouble, snapshot: Dictionary) -> void:
	_bee(office)._apply_snapshot(snapshot.duplicate(true))
	office.refresh()


## The bottom panel's EVENTS row for pane `key`'s newest event; null when the
## log has none or the page has no row for it (S3 PANEL-a2, 2026-10-28: the
## log's rows stand where the agent list's rows were pointed at and clicked).
func _event_row(office: OfficeScene, key: String) -> EventRow:
	var events := office.fleet.state_log().events()
	for index in range(events.size() - 1, -1, -1):
		if events[index].pane_key == key:
			return office.hud.event_list.row_for(events[index].id)
	return null


## A real click on the bottom panel's tab for `page`, then the frames it takes.
func _click_tab(office: OfficeScene, page: OfficeBottomPanel.Page) -> void:
	var tabs := office.hud.staff.tabs
	await _click_at(tabs.get_global_rect().position + tabs.get_tab_rect(page).get_center())
	await _frames(2)


## bee's one workspace, `hive`, with one agent in `status`.
static func _bee_snapshot(status: String) -> Dictionary:
	return {
		"focused_pane_id": "hive:p1",
		"workspaces": [{"workspace_id": "hive", "number": 1, "label": "hive"}],
		"tabs": [{"tab_id": "hive:t1", "workspace_id": "hive", "number": 1, "label": "hive"}],
		"panes":
		[
			{
				"pane_id": "hive:p1",
				"workspace_id": "hive",
				"tab_id": "hive:t1",
				"agent": "claude",
				"agent_status": status,
				"terminal_id": "term-hive-p1"
			}
		],
		"agents": [],
		"layouts": []
	}


func _decor_signatures(plan: FloorPlan) -> PackedStringArray:
	var found := PackedStringArray()
	for placed in plan.decorations:
		found.append(placed.geometry_signature())
	found.sort()
	return found


func _decor_places(office: OfficeDouble) -> Array:
	var found := _decor(office).map(func(piece: OfficeDecor) -> String: return "%s@%s" % [piece.piece, piece.position])
	found.sort()
	return found


func _planned_places(plan: FloorPlan) -> Array:
	var found := plan.decorations.map(
		func(piece: DecorPlacement) -> String: return "%s@%s" % [piece.piece, piece.position]
	)
	found.sort()
	return found


## The instance id of `node` and of everything under it, in tree order.
func _subtree_ids(node: Node) -> Array:
	return (
		[node.get_instance_id()]
		+ node.find_children("*", "", true, false).map(func(each: Node) -> int: return each.get_instance_id())
	)


## Each partition sprite of `zone` on the shown map, as "texture@position".
func _partitions_drawn(office: OfficeDouble, zone: String) -> Array:
	return office.floor_view.partition_sprites(zone).map(
		func(sprite: Sprite2D) -> String: return "%s@%s" % [sprite.texture.resource_path, sprite.position]
	)
