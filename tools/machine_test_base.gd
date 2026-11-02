extends "res://tools/test_base.gd"
## What tools/test_machines.gd stands on: the fake herdr servers and ssh it
## drives, the office it builds on real frames, real input events, the fixtures,
## and the typed reads of the fleet and the office. Moved out of that suite so it
## stays under gdlint's max-file-lines, the way tools/office_test_base.gd was;
## it holds no cases of its own.

const FIXTURES := "res://tools/fixtures/"
const MANIFESTS := ["res://assets/daylight/manifest.json"]
## The live office with a viewport size this suite decides; see the file.
const OfficeDouble := preload("res://tools/office_double.gd")
## Real seconds any single wait may take before the check fails.
const WAIT := 8.0
## The screen every office here is laid out for, and the root window's size, so
## real mouse input lands on the HUD the way it does in a window.
const SCREEN := Vector2i(800, 480)

var args: Dictionary[String, String] = {}

# --- harness --------------------------------------------------------------------


## One raw workspace after HerdrSnapshot.from_wire().
func _cleaned_space(raw: Dictionary) -> HerdrSnapshot.Workspace:
	return HerdrSnapshot.from_wire({"workspaces": [raw]}).workspaces[0]


## The cleaned `worktree` of a workspace that carries this raw one; null for none.
func _cleaned_worktree(raw: Variant) -> HerdrSnapshot.Worktree:
	return _cleaned_space({"workspace_id": "w", "worktree": raw}).worktree


## Every field of a pane as from_wire() read it, in declaration order.
func _pane_fields(pane: HerdrSnapshot.Pane) -> Array:
	return [
		pane.pane_id,
		pane.terminal_id,
		pane.tab_id,
		pane.workspace_id,
		pane.label,
		pane.agent,
		pane.agent_session,
		pane.launch_pending,
		pane.launch_pending_known,
		pane.cwd,
		pane.foreground_cwd,
		pane.terminal_title_stripped,
		pane.agent_status,
	]


## Every field of a saved machine as normalize() read it.
func _machine_fields(machine: MachineRoster.Machine) -> Array:
	return [machine.key, machine.id, machine.label, machine.target, machine.session, machine.enabled]


## The roster's debug sockets as `--machine-socket=<label>=<path>` gives them.
func _debug_socket(label: String, path: String) -> Array[MachineRoster.DebugSocket]:
	return MachineRoster.parse_socket_args(PackedStringArray(["--machine-socket=%s=%s" % [label, path]]))


## Every way a remote snapshot can be the wrong shape while its panes are still
## objects, which is all HerdrClient checks.
func _malformed() -> Dictionary:
	return {
		"focused_pane_id": {"x": 1},
		"workspaces":
		[1, {"workspace_id": ["x"], "label": {"a": 1}, "number": "3"}, {"workspace_id": "w2", "number": 3.0}],
		"tabs": ["junk", {"tab_id": "w2:t1", "workspace_id": "w2", "label": 9, "number": "x"}],
		"panes":
		[
			{
				"pane_id": "5",
				"tab_id": null,
				"workspace_id": "w2",
				"agent": 3,
				"agent_status": ["x"],
				"launch_pending": "yes"
			},
			{"pane_id": "w1:p9", "tab_id": "w2:t1", "workspace_id": "w2", "agent_status": "idle"},
		],
		"layouts": [{"tab_id": 1, "panes": [7, {"pane_id": "5", "rect": "x"}]}, "junk"],
	}


func _sidecar(path: String, pid: int) -> void:
	_write(path, JSON.stringify({"ssh_pid": pid}))


## A socket file nobody listens on, as a SIGKILLed ssh leaves behind.
func _bind(path: String) -> void:
	_python("import socket; s = socket.socket(socket.AF_UNIX); s.bind('%s'); s.close()" % path)


func _output(command: String, arguments: PackedStringArray) -> String:
	var output: Array = []
	OS.execute(command, arguments, output)
	return "" if output.is_empty() else str(output[0])


func _link() -> MachineLink:
	var link := MachineLink.new()
	_eq(link.ssh_path, args.ssh, "HERDSTEAD_SSH picks the ssh")
	return link


## OfficeScene reads the viewport through `_screen()`; the test decides its size.
func _office(screen: Vector2) -> OfficeDouble:
	var office := OfficeDouble.new()
	office.test_screen = screen
	office.manifest_path = MANIFESTS[0]
	# Set before _ready for tests that never add the office to the tree.
	office.art = ArtPack.from_manifest(MANIFESTS[0])
	# Never write the user's theme choice from a test.
	office.remember_theme = false
	return office


## The state the desk's badge pulses for.
func _badge_state(machine: String, pane_id: String) -> String:
	for badge: StatusBadge in get_nodes_in_group(StatusBadge.GROUP):
		if badge.is_queued_for_deletion():
			continue
		if badge.machine == machine and badge.pane_id == pane_id:
			return str(badge.state)
	return ""


## Whether the shown floor's workers play: [true], [false] or both.
func _actors_playing(office: OfficeDouble) -> Array:
	var seen := {}
	for key in office.floor_view.seats:
		var actor := office.floor_view.seat(key).node.actor()
		if actor != null:
			seen[actor.is_playing()] = true
	return seen.keys()


## Pick zone `key` without the mouse (S3 BAR-b, 2026-10-27: the SPACES rail
## is gone): real PageDown / PageUp presses, the direction from
## OfficeFrame.zone_order, until it is the zone the page keys stand on
## (OfficeNavigator.current_zone()). Each press is the pick_zone() a SPACES row
## click took. Nothing is pressed when it is already; fails after as many
## presses as there are zones. A case that needs a click on the zone uses a
## portrait card's place instead (_place_click()).
func _zone_pick(office: OfficeDouble, key: String) -> void:
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
		await _navigate_key(office, KEY_PAGEDOWN if down else KEY_PAGEUP)
	if office.navigator.current_zone(office.frame) != key:
		_fail("the page keys never reached " + key)


## A real click on the place (zone tag and space) of pane `pane_key`'s
## portrait card: it pans to that pane's zone and selects nothing.
func _place_click(office: OfficeDouble, pane_key: String) -> void:
	var card := office.hud.bar.card_for(pane_key)
	if card == null:
		_fail("no portrait card for " + pane_key)
		return
	var place: Button = card.get_node("%PlaceButton")
	if not place.is_visible_in_tree():
		_fail("the card of %s shows no place" % pane_key)
		return
	_press(place.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await process_frame
	await process_frame


func _navigate_key(_to: OfficeDouble, code: Key) -> void:
	var event := _key(code)
	for down: bool in [true, false]:
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await physics_frame


## The bar's second line, which the office once kept as a model string of its own.
func _bar_text(office: OfficeDouble) -> String:
	return office.hud.bar.status_line()


## What the top bar says the old counter `id` said (S3 BAR-a, 2026-10-27: the
## portrait strip replaces the counters): `&"machines"` as `live/all` from the
## status line's hover (a LIVE line per machine answering), `&"panes"` the
## number `1 machine · 13 panes` says of the panes (S3 TILES, 2026-10-28: the
## count says the machines first, as B2 does).
func _counter(office: OfficeDouble, id: StringName) -> String:
	var bar := office.hud.bar
	if id == &"panes":
		return (bar.get_node("%Panes") as Button).text.get_slice(" · ", 1).get_slice(" ", 0)
	var status: Control = bar.get_node("%StatusLine")
	var lines := (
		bar.get_tooltip(bar.get_global_transform().affine_inverse() * status.get_global_rect().get_center()).split("\n")
	)
	var live := 0
	for line in lines:
		live += 1 if " · LIVE · " in line else 0
	return "%d/%d" % [live, lines.size()]


## Every seat with a pane on the shown floor, in tree order.
func _seats(office: OfficeDouble) -> Array[OfficeStation]:
	var found: Array[OfficeStation] = []
	for node: Node in office.world.find_children("*", "", true, false):
		if node is OfficeStation:
			var station: OfficeStation = node
			if not station.pane_key.is_empty():
				found.append(station)
	return found


## Where the desk drawn for `key` answers a click, in global coordinates.
func _desk_target(office: OfficeDouble, key: String) -> Rect2:
	for station in _seats(office):
		if station.pane_key == key:
			return station.target_rect()
	_fail("no click target for " + key)
	return Rect2()


## The same rectangle in the world's own coordinates, which is what a pan is
## measured in: what the office once kept as a hand-made table.
func _desk_rect(office: OfficeDouble, key: String) -> Rect2:
	var bounds := _desk_target(office, key)
	return Rect2(office.world.to_local(bounds.position), bounds.size)


## The viewport point a click on that desk lands on, through the office's camera.
func _desk_point(office: OfficeDouble, key: String) -> Vector2:
	return _desk_target(office, key).get_center() - office.camera.position


## Every pane key the office projected, on every floor of every building.
func _pane_keys(office: OfficeDouble) -> Array:
	var keys: Array = []
	for building: BuildingModel in office.frame.buildings:
		for floor_model in building.zones:
			for room in floor_model.rooms:
				for pane in room.panes:
					keys.append(pane.key)
	return keys


func _pane_state(office: OfficeDouble, key: String) -> String:
	for building: BuildingModel in office.frame.buildings:
		for floor_model in building.zones:
			for room in floor_model.rooms:
				for pane in room.panes:
					if pane.key == key:
						return pane.state
	return ""


## A real click on machine `key`'s chip in the top bar, through the GUI
## (S3 BAR-b, 2026-10-27: the SPACES rail's headings are gone).
func _heading_pick(office: OfficeDouble, key: String) -> void:
	var chip := office.hud.bar.chip_for(key)
	if chip == null:
		_fail("no machine chip for " + key)
		return
	_press(chip.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await process_frame
	await process_frame


## A pane's status as the fleet holds that machine's snapshot.
func _held_status(office: OfficeDouble, machine: String, pane_id: String) -> String:
	for pane in office.fleet.snapshot(machine).panes:
		if pane.pane_id == pane_id:
			return pane.agent_status
	return ""


## Press and release a mouse button at a viewport position, through the GUI.
func _press(at: Vector2, button: MouseButton) -> void:
	for down: bool in [true, false]:
		_button(at, button, down)


## One half of a click, for the cases that care where the release lands.
func _button(at: Vector2, button: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = at
	event.global_position = at
	event.pressed = down
	root.push_input(event, true)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _inspector_text(office: OfficeDouble) -> String:
	var texts := PackedStringArray()
	for label: Label in office.hud.inspector.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			texts.append(label.text)
	return " | ".join(texts)


func _until(condition: Callable, what: String) -> void:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await process_frame
	_fail("timed out waiting for " + what)


## Poll one fake server's stats a few times a second, frames running meanwhile,
## until `condition` holds; the last stats either way.
func _until_stats(which: String, condition: Callable, what: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	var stats := {}
	while Time.get_ticks_msec() < deadline:
		stats = _ctl(which, "stats")
		if condition.call(stats):
			return stats
		await create_timer(0.05).timeout
	_fail("timed out waiting for %s (last stats %s)" % [what, JSON.stringify(stats)])
	return stats


## Local and bee, both live on snapshot_basic (Local on `local` instead when it
## is given), and no saved machines, in an 800x480 window unless `screen` says
## otherwise. Caller removes and frees it, and unsets HERDR_BIN_PATH.
func _two_machine_office(screen := Vector2(800, 480), local: Dictionary = {}) -> OfficeDouble:
	_ctl("control-a", "reset", {"fixture": "snapshot_basic"})
	if not local.is_empty():
		_ctl("control-a", "set_snapshot", {"snapshot": local})
	_ctl("control-b", "reset", {"fixture": "snapshot_basic"})
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-such-herdr"))
	OS.set_environment("HERDR_SOCKET_PATH", args["socket-a"])
	var office := _office(screen)
	root.add_child(office)
	office.fleet._roster.sockets = _debug_socket("bee", args["socket-b"])
	office.fleet._sync_sites()
	await _until(
		func() -> bool: return office.fleet.size() == 2 and office.fleet.live_count() == 2, "both machines live"
	)
	return office


## A snapshot over the pane cap: snapshot_basic's, its panes a list of empty
## records. They name no pane either, so a subscription to any real pane fails.
func _over_cap() -> Dictionary:
	var huge := _fixture("snapshot_basic")
	var panes: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		panes.append({})
	huge.panes = panes
	return huge


func _socket_exists(path: String) -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	return dir != null and dir.file_exists(path.get_file())


func _alive(pid: int) -> bool:
	return OS.execute("kill", ["-0", str(pid)], [], false) == 0


func _python(code: String) -> void:
	OS.execute(OS.get_environment("PYTHON") if not OS.get_environment("PYTHON").is_empty() else "python3", ["-c", code])


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _unique(items: Array) -> Array:
	var seen := {}
	for item: Variant in items:
		seen[item] = true
	return seen.keys()


## What `action` returns, having checked that nothing the engine logged while it
## ran holds `marker`. A warning pushed while the capture listens proves it was
## listening, so a capture that heard nothing cannot pass for a clean log.
func _never_logged(marker: String, action: Callable) -> Variant:
	var listening := "the log capture is listening"
	var logs := Captured.new()
	OS.add_logger(logs)
	var result: Variant = action.call()
	push_warning(listening)
	OS.remove_logger(logs)
	var lines := logs.lines()
	_check(lines.any(func(line: String) -> bool: return line.contains(listening)), "the log capture heard a warning")
	for line in lines:
		_check(not marker in line, "a logged line quotes %s: %s" % [marker, line.left(160)])
	return result


## One command on a fake server's control socket; returns its result.
func _ctl(which: String, command: String, arguments := {}) -> Dictionary:
	var peer := StreamPeerUDS.new()
	if peer.connect_to_host(args[which]) != OK:
		_fail("control socket unreachable for " + command)
		return {}
	var payload := (JSON.stringify({"cmd": command, "args": arguments}) + "\n").to_utf8_buffer()
	var sent := false
	var buffer := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and buffer.find(10) < 0:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerSocket.STATUS_CONNECTED and not sent:
			sent = peer.put_data(payload) == OK
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_partial_data(available)
			var read: PackedByteArray = chunk[1]
			buffer.append_array(read)
		elif status == StreamPeerSocket.STATUS_ERROR:
			break
		else:
			OS.delay_usec(200)
	peer.disconnect_from_host()
	var cut := buffer.find(10)
	var answer: Variant = JSON.parse_string(buffer.slice(0, cut).get_string_from_utf8()) if cut >= 0 else null
	if not answer is Dictionary:
		_fail("control %s failed: %s" % [command, answer])
		return {}
	var reply: Dictionary = answer
	if not reply.get("ok", false):
		_fail("control %s failed: %s" % [command, answer])
		return {}
	return reply.result


## --- reads of the office's own records -----------------------------------------
## The fleet answers most questions itself; these reach its client and forward
## objects only where a case is about their identity or their inner clock.


## The client of the office's `index`-th machine, Local first.
func _client(office: OfficeDouble, index: int) -> HerdrClient:
	return office.fleet._sites[index].client


## Every machine's client, Local first.
func _clients(office: OfficeDouble) -> Array[HerdrClient]:
	var found: Array[HerdrClient] = []
	for index in office.fleet.size():
		found.append(_client(office, index))
	return found


## The SSH forward of the office's `index`-th machine, null for a local one.
func _site_link_of(office: OfficeDouble, index: int) -> MachineLink:
	return office.fleet._sites[index].link


## Whether a machine is live and current, showing exactly `count` panes.
func _has_panes(office: OfficeDouble, machine: String, count: int) -> bool:
	return office.fleet.snapshot_is_current(machine) and office.fleet.snapshot(machine).panes.size() == count


## Whether every machine is live and current, each showing exactly `count` panes.
func _all_have_panes(office: OfficeDouble, count: int) -> bool:
	for machine in office.fleet.keys():
		if not _has_panes(office, machine, count):
			return false
	return true


## What the floor plate's machine state ("state") or a lobby's note ("note")
## says now, as its labels hold it, whatever of it the band shows.
func _plate_text(office: OfficeDouble, which: String) -> String:
	return office.plate.state_text() if which == "state" else office.plate.note_text()


## A real click: press and release at one viewport point, each given the physics
## frames the viewport needs to hand a seat's Area2D its pick.
func _click(at: Vector2) -> void:
	for down: bool in [true, false]:
		_button(at, MOUSE_BUTTON_LEFT, down)
		await physics_frame
		await physics_frame


## Floor switches restore each floor's own pan. A fixture that intentionally
## panned under a panel must scroll back into view before trying to pick a seat.
func _click_visible_pane(office: OfficeDouble, key: String) -> void:
	await process_frame
	await process_frame
	var visible := office.hud.world_rect().intersection(Rect2(Vector2.ZERO, Vector2(root.size)))
	var point := _desk_point(office, key)
	var attempts := 0
	var stuck := false
	while not _clickable(office, visible, point) and attempts < 32:
		var wheel: MouseButton
		if point.y < visible.position.y:
			wheel = MOUSE_BUTTON_WHEEL_UP
		elif point.y >= visible.end.y:
			wheel = MOUSE_BUTTON_WHEEL_DOWN
		elif point.x < visible.position.x:
			wheel = MOUSE_BUTTON_WHEEL_LEFT
		elif point.x >= visible.end.x:
			wheel = MOUSE_BUTTON_WHEEL_RIGHT
		else:
			# Under an edge arrow (they stand along the world's edges): bring the
			# desk toward the middle of the room, or sideways when the pan cannot
			# go that way any further.
			var lower := point.y > visible.get_center().y
			wheel = MOUSE_BUTTON_WHEEL_DOWN if lower else MOUSE_BUTTON_WHEEL_UP
			if stuck:
				wheel = MOUSE_BUTTON_WHEEL_RIGHT if point.x > visible.get_center().x else MOUSE_BUTTON_WHEEL_LEFT
		_press(_wheel_point(office, visible), wheel)
		await process_frame
		await process_frame
		var moved := _desk_point(office, key)
		stuck = moved == point
		point = moved
		attempts += 1
	var ready := _clickable(office, visible, point)
	_check(
		ready,
		"pane target is visible and clear of the edge arrows before click: %s at %s in %s" % [key, point, visible]
	)
	if ready:
		await _click(point)


## Whether a viewer could click `at`: inside the world's visible room and not
## under an edge arrow, which stands over the world along its edge and takes
## a click there, or under the bottom panel (NEWS stands in it), which stands
## over the world's middle in answer mode.
## S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: no closed
## tab, no NEWS strip.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: no drawer to stand under.
func _clickable(office: OfficeDouble, visible: Rect2, at: Vector2) -> bool:
	if not visible.has_point(at):
		return false
	var covers: Array[Control] = [office.hud.staff]
	covers.append_array(office.hud.edge_arrows.shown())
	for cover in covers:
		if cover.is_visible_in_tree() and cover.get_global_rect().has_point(at):
			return false
	return true


## Where a wheel notch pans the world: the visible room's middle, or, while
## something covers that (the staff panel in answer mode), a corner of the room
## the viewer could still scroll at.
func _wheel_point(office: OfficeDouble, visible: Rect2) -> Vector2:
	var inner := visible.grow(-4.0)
	for at: Vector2 in [visible.get_center(), inner.position, Vector2(inner.position.x, inner.end.y)]:
		if _clickable(office, visible, at):
			return at
	_fail("no room to scroll the world at in %s" % visible)
	return visible.get_center()


## Read the actual rendered plate, not an internal world rebuild signature.
func _machine_plate_text(office: OfficeDouble) -> String:
	var plate := office.world.get_node("MachinePlate")
	var texts := PackedStringArray()
	for label: Label in plate.find_children("*", "Label", true, false):
		if label.is_visible_in_tree():
			texts.append(label.text)
	return " | ".join(texts)


# --- snapshots as herdr sends them and as the office reads them ---------------


func _fixture(name: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + name + ".json"))
	return data.snapshot


## snapshot_basic with seven more shells on bravo:t1: a pod of 5 cells, so bravo
## takes two lanes and, on the narrowest map (Z1, 2026-10-27: two lanes of 4,
## FRAME-Q2), stands under alpha as one lane of 9 stacked them.
func _wide_bravo() -> Dictionary:
	var raw := _fixture("snapshot_basic")
	var shell: Dictionary = {}
	for pane: Dictionary in _list(raw, "panes"):
		if pane.pane_id == "alpha:p2":
			shell = pane
	for index in range(2, 9):
		var pane: Dictionary = shell.duplicate(true)
		pane.merge({"pane_id": "bravo:s%d" % index, "terminal_id": "term-bravo-s%d" % index}, true)
		pane.merge({"workspace_id": "bravo", "tab_id": "bravo:t1"}, true)
		_list(raw, "panes").append(pane)
	return raw


## A snapshot herdr might send, as the office reads it: through the one boundary.
func _view(raw: Dictionary) -> HerdrSnapshot:
	return HerdrSnapshot.from_wire(raw)


## A fixture as the office reads it.
func _view_fixture(name: String) -> HerdrSnapshot:
	return _view(_fixture(name))


## What a desk draws of a pane, as HerdrSnapshot read it.
func _drawn_pane(pane: HerdrSnapshot.Pane) -> Array:
	return [
		pane.pane_id,
		pane.terminal_id,
		pane.workspace_id,
		pane.tab_id,
		pane.label,
		pane.agent,
		pane.agent_status,
		pane.cwd,
		pane.foreground_cwd,
		pane.terminal_title_stripped,
	]


## The same fields of a clean pane as herdr sent it; absent reads as empty.
func _sent_pane(pane: Dictionary) -> Array:
	var fields: Array = []
	for key: String in [
		"pane_id",
		"terminal_id",
		"workspace_id",
		"tab_id",
		"label",
		"agent",
		"agent_status",
		"cwd",
		"foreground_cwd",
		"terminal_title_stripped",
	]:
		fields.append(str(pane.get(key, "")) if pane.get(key) != null else "")
	return fields


func _drawn_slot(slot: HerdrSnapshot.LayoutSlot) -> Array:
	return [slot.pane_id, slot.x, slot.y, slot.width, slot.height]


## Every fixture rect is a whole, in-bounds size, so it reads as sent.
func _sent_slot(slot: Dictionary) -> Array:
	var rect := _dict(slot, "rect")
	return [
		str(slot.pane_id),
		int(_number(rect, "x")),
		int(_number(rect, "y")),
		int(_number(rect, "width")),
		int(_number(rect, "height")),
	]


## A workspace's worktree as from_wire() read it; null for none.
func _drawn_tree(workspace: HerdrSnapshot.Workspace) -> Variant:
	var tree := workspace.worktree
	if tree == null:
		return null
	return [tree.repo_key, tree.repo_name, tree.repo_root, tree.checkout_path, tree.is_linked_worktree]


## Every fixture worktree is null or an object of clean text and a boolean.
func _sent_tree(workspace: Dictionary) -> Variant:
	var tree := _dict(workspace, "worktree")
	if tree.is_empty():
		return null
	var fields: Array = []
	for key: String in ["repo_key", "repo_name", "repo_root", "checkout_path"]:
		fields.append(str(tree.get(key, "")))
	fields.append(_flag(tree, "is_linked_worktree"))
	return fields


## `count` records with nothing in them: the record caps count records.
func _records(count: int) -> Array:
	var records: Array = []
	for index in count:
		records.append({})
	return records


## MachineRoster.clean_text() as it read before its RegEx fast path, character
## by character: the oracle the parity case holds the new one to. It has since
## dropped the bidi embeddings, overrides and isolates as well (U+202A–U+202E,
## U+2066–U+2069), so the oracle does too; everything else is as it was.
func _loop_clean_text(value: Variant) -> String:
	var text := ""
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			text = str(value)
		TYPE_INT:
			text = str(value)
		TYPE_FLOAT:
			var number: float = value
			text = str(int(number)) if is_equal_approx(number, roundf(number)) and absf(number) < 1e15 else str(number)
		TYPE_BOOL:
			text = "true" if value else "false"
	var kept := ""
	for index in text.length():
		var code := text.unicode_at(index)
		var control := (
			code < 0x20 or code == 0x7f or (code >= 0x80 and code <= 0x9f) or code == 0x2028 or code == 0x2029
		)
		var bidi := (code >= 0x202a and code <= 0x202e) or (code >= 0x2066 and code <= 0x2069)
		if not control and not bidi:
			kept += text[index]
	return kept.strip_edges()


## The second pack the pack-switching cases switch to (test_base.gd).
func _second_pack() -> String:
	return _second_pack_at(args.work.path_join("machines-pack-second"))


## Whether the chip over pane `key`'s desk is inside the world on screen.
func _bubble_on_screen(office: OfficeDouble, key: String) -> bool:
	var seat := office.floor_view.seat(key)
	if seat == null:
		return false
	var screen := office.get_viewport().get_canvas_transform() * seat.node.chip_rect()
	return screen.has_area() and office.hud.world_rect().intersects(screen)


## A real key the staff panel reads by its position (Enter, Escape): keycode
## and physical keycode both, pressed and released.
func _card_key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame


## char(), made at run time: `char(0)` with a constant argument is folded while
## the script compiles, and loading the folded constant made the engine warn
## "Unexpected NUL character" (make check-scripts).
static func _char(code: int) -> String:
	return char(code)


## One layout slot carrying `rect` (none at all when null), as from_wire() reads
## it: [x, y, width, height].
func _rect_read(rect: Variant) -> Array:
	var slot := {"pane_id": "p"} if rect == null else {"pane_id": "p", "rect": rect}
	var read := HerdrSnapshot.from_wire({"layouts": [{"tab_id": "t", "panes": [slot]}]})
	return _drawn_slot(read.layouts[0].panes[0]).slice(1)


## A real drag in the world, from `from` by `by`, through the viewport.
func _drag_world(from: Vector2, by: Vector2) -> void:
	_button(from, MOUSE_BUTTON_LEFT, true)
	var motion := InputEventMouseMotion.new()
	motion.position = from + by
	motion.global_position = from + by
	motion.relative = by
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	_button(from + by, MOUSE_BUTTON_LEFT, false)
	await process_frame
	await process_frame


## One workspace `a` whose one tab holds `count` working claude agents, focus on the first.
func _one_tab_of(count: int) -> Dictionary:
	var big := {
		"workspaces": [{"workspace_id": "a", "number": 1}],
		"tabs": [{"workspace_id": "a", "tab_id": "a:t", "number": 1}],
		"panes": [],
		"layouts": [],
		"focused_pane_id": "a:p0"
	}
	for index in count:
		var pane := {"pane_id": "a:p%d" % index, "tab_id": "a:t", "workspace_id": "a", "agent": "claude"}
		pane.merge({"agent_status": "working", "terminal_id": "term-a-%d" % index})
		_list(big, "panes").append(pane)
	return big
