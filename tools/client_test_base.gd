extends "res://tools/test_base.gd"
## What tools/test_client.gd stands on: the client it drives and records, the
## fake herdr it talks to, synthetic time, the fixtures, and the typed lookups
## into the HUD and the projection. Moved out of that suite so the suite stays
## under gdlint's max-file-lines, the way tools/office_test_base.gd was; it holds
## no cases of its own.
##
## The client is never added to the tree: the tests call its `_process(delta)`
## by hand, so every clock it keeps (debounce, interval, timeouts, backoff) runs
## on synthetic time. `pump` moves bytes without moving time; `step` moves time.

const FIXTURES := "res://tools/fixtures/"
const MANIFEST := "res://assets/daylight/manifest.json"
const READ_ONLY := ["ping", "session.snapshot", "events.subscribe"]
## Real time any single wait may take before the case fails.
const WAIT := 3.0
## One `_process` call must never block; the transport is meant to be non-blocking.
## Wall-clock, so a loaded machine counts too: measured, the slowest step was
## at most 9.5 ms at a 1-minute load of 8, and 45-68 ms at 43-77 (four of ten
## runs over 50 ms, the whole process pre-empted).
## A real block (reading or parsing the 32 MiB line at once) takes far longer.
const MAX_STEP_MSEC := 200.0
## Real time a flood of megabytes may take to drain through the socket.
const FLOOD_WAIT := 20.0

var socket_path := ""
var control_path := ""
var client: HerdrClient
var rec: Recorder
var max_step_usec := 0
var _known_states := PackedStringArray()


class Recorder:
	var order: Array = []
	var connected := 0
	var disconnected := 0
	var snapshots := 0
	var readiness := 0
	var events: Array = []

	func on_connected() -> void:
		connected += 1
		order.append("connected")

	func on_disconnected() -> void:
		disconnected += 1
		order.append("disconnected")

	func on_snapshot(_snapshot: HerdrSnapshot) -> void:
		snapshots += 1
		order.append("snapshot")

	func on_readiness() -> void:
		readiness += 1

	func on_event(name: String, data: Dictionary) -> void:
		events.append([name, data])

	## What the `index`-th event carried, empty when there is no such event.
	func event_data(index: int) -> Dictionary:
		if index >= events.size():
			return {}
		var entry: Array = events[index]
		return entry[1]


# --- the client -----------------------------------------------------------------


func _start_client() -> void:
	_new_client()
	client.start(socket_path)


func _new_client() -> void:
	client = HerdrClient.new()
	rec = Recorder.new()
	client.connected.connect(rec.on_connected)
	client.disconnected.connect(rec.on_disconnected)
	client.snapshot_changed.connect(rec.on_snapshot)
	client.snapshot_readiness_changed.connect(rec.on_readiness)
	client.event_received.connect(rec.on_event)


func _finish_client() -> void:
	if client == null:
		return
	client.stop()
	client.free()
	client = null


## Fresh server state, a fresh client, live and quiet.
func _connect_settled() -> bool:
	_ctl("reset", {"fixture": "snapshot_basic"})
	_start_client()
	if not _settle():
		return false
	_server_until(func(s: Dictionary) -> bool: return s.streams_live == 1, "one live stream")
	rec.events.clear()
	return true


## Pump bytes until the client is live, holds a snapshot, streams status for
## exactly the panes it knows, and has nothing in flight.
func _settle() -> bool:
	return _pump(
		func() -> bool:
			return (
				client.online
				and client._sub_started
				and not client.snapshot.is_empty()
				and client._sub_panes == client._pane_ids()
				and client._requests.is_empty()
				and not client._want_snapshot
				and not client._snapshot_inflight
				and client._debounce_left <= 0.0
			),
		"client settled"
	)


## Move synthetic time. Bytes that already arrived are handled in the same call.
func _step(seconds: float) -> void:
	var before := Time.get_ticks_usec()
	client._process(seconds)
	max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - before)


## Move bytes, not time, until `condition` holds or WAIT real seconds pass.
func _pump(condition: Callable, what: String, must := true) -> bool:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	while Time.get_ticks_msec() < deadline:
		if client != null:
			_step(0.0)
		if condition.call():
			return true
		OS.delay_usec(500)
	if must:
		_fail("timed out waiting for " + what)
	return false


func _pump_frames(count: int) -> void:
	for i in count:
		_step(0.0)
		OS.delay_usec(500)


## Move bytes as fast as they come, not time, until `condition` holds: a flood
## of megabytes through an 8 KiB socket buffer takes thousands of reads.
func _drain_until(condition: Callable, what: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(FLOOD_WAIT * 1000)
	while Time.get_ticks_msec() < deadline:
		_step(0.0)
		if condition.call():
			return true
	_fail("timed out waiting for " + what)
	return false


## After a disconnect, the client asks again `wait` seconds later and not sooner:
## judged by the pings the fake server saw, while synthetic time moves.
func _retry_after(wait: float, why: String) -> void:
	var pings := _pings()
	_step(wait - 0.01)
	_pump_frames(5)
	_eq(_pings(), pings, "no retry sooner than %.1fs after %s" % [wait, why])
	_step(0.02)
	_server_until(
		func(s: Dictionary) -> bool: return _count(_list(s, "methods"), "ping") == pings + 1,
		"one retry %.1fs after %s" % [wait, why]
	)


## How many pings the fake server has seen.
func _pings() -> int:
	return _count(_list(_ctl("stats"), "methods"), "ping")


## Poll the fake server's stats, pumping the client meanwhile.
func _server_until(condition: Callable, what: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	var stats := {}
	while Time.get_ticks_msec() < deadline:
		stats = _ctl("stats")
		if condition.call(stats):
			return stats
		if client != null:
			_pump_frames(2)
		else:
			OS.delay_usec(1000)
	_fail("timed out waiting for server: %s (last stats %s)" % [what, JSON.stringify(stats)])
	return stats


## One command on the fake server's control socket; returns its result.
func _ctl(command: String, args := {}) -> Dictionary:
	var peer := StreamPeerUDS.new()
	if peer.connect_to_host(control_path) != OK:
		_fail("control socket unreachable for " + command)
		return {}
	var payload := (JSON.stringify({"cmd": command, "args": args}) + "\n").to_utf8_buffer()
	var sent := false
	var buffer := PackedByteArray()
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
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


# --- snapshots ------------------------------------------------------------------


## A fixture as the office reads it.
func _view_fixture(name: String) -> HerdrSnapshot:
	return HerdrSnapshot.from_wire(_fixture(name))


## A snapshot herdr might send, as the office reads it: through the one boundary.
func _view(raw: Dictionary) -> HerdrSnapshot:
	return HerdrSnapshot.from_wire(raw)


func _fixture(name: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + name + ".json"))
	return data.snapshot


## One workspace, one tab, two panes, with `focused` as herdr's session focus.
func _two_panes(focused: String) -> Dictionary:
	return {
		"focused_pane_id": focused,
		"workspaces": [{"workspace_id": "w", "number": 1}],
		"tabs": [{"tab_id": "t", "workspace_id": "w", "number": 1}],
		"panes":
		[
			{"pane_id": "p1", "tab_id": "t", "workspace_id": "w"},
			{"pane_id": "p2", "tab_id": "t", "workspace_id": "w"},
		],
	}


## One workspace with two tabs; `active` is its `active_tab_id`, and null leaves
## the field out altogether.
func _two_tabs(active: Variant) -> Dictionary:
	var workspace := {"workspace_id": "w", "number": 1}
	if active != null:
		workspace.active_tab_id = active
	return {
		"workspaces": [workspace],
		"tabs":
		[{"tab_id": "w:t1", "workspace_id": "w", "number": 1}, {"tab_id": "w:t2", "workspace_id": "w", "number": 2}],
	}


## Whether each room of _two_tabs(active) is the open one, in tab order.
func _open_tabs(active: Variant) -> Array:
	var rooms := OfficeProjection.project(_view(_two_tabs(active)), _states())[0].rooms
	return rooms.map(func(room: RoomModel) -> int: return room.active)


## The floor of a single workspace whose `worktree` field is this.
func _worktree_floor(worktree: Variant) -> ZoneModel:
	var snapshot := {"workspaces": [{"workspace_id": "w", "number": 1, "worktree": worktree}]}
	return OfficeProjection.project(_view(snapshot), _states())[0]


## The states the shipped pack has a badge for, as the office hands them to the
## projection. Anything else is drawn as unknown.
func _states() -> PackedStringArray:
	if _known_states.is_empty():
		_known_states = ArtPack.from_manifest(MANIFEST).state_names()
	return _known_states


## The pane ids of a snapshot as herdr sends it, sorted.
func _pane_ids(snapshot: Dictionary) -> Array:
	var ids: Array = _list(snapshot, "panes").map(func(p: Dictionary) -> String: return p.pane_id)
	ids.sort()
	return ids


## The pane ids of the snapshot the client holds, sorted.
func _held_pane_ids() -> Array:
	var ids: Array = client.snapshot.panes.map(func(p: HerdrSnapshot.Pane) -> String: return p.pane_id)
	ids.sort()
	return ids


## The client's pane with this id, or null.
func _pane(pane_id: String) -> HerdrSnapshot.Pane:
	for pane in client.snapshot.panes:
		if pane.pane_id == pane_id:
			return pane
	return null


## Panes of a snapshot as herdr sends it, as the client's clock reads them.
func _clock_panes(raw: Dictionary) -> Array[HerdrSnapshot.Pane]:
	return HerdrSnapshot.from_wire(raw).panes


## A list of panes as herdr sends them, as the client's clock reads them.
func _typed(raw_panes: Array) -> Array[HerdrSnapshot.Pane]:
	return _clock_panes({"panes": raw_panes})


func _status_pane(pane_id: String, status: String) -> Dictionary:
	return {"pane_id": pane_id, "terminal_id": "term-" + pane_id, "agent_status": status}


func _pane_status(pane_id: String) -> String:
	var pane := _pane(pane_id)
	return "" if pane == null else pane.agent_status


func _pane_agent(pane_id: String) -> String:
	var pane := _pane(pane_id)
	return "" if pane == null else pane.agent


func _count(items: Array, value: Variant) -> int:
	return items.count(value)


## When a pane's status started, as HerdrClient.carry_states() records it.
func _started_at(states: Dictionary[String, HerdrClient.StateClock], pane_id: String) -> float:
	return states[pane_id].since


# --- the HUD --------------------------------------------------------------------


## A dressed HUD in the tree, laid out for a `screen`-sized viewport. Caller frees it.
func _hud(screen: Vector2) -> OfficeHud:
	var art := ArtPack.from_manifest(MANIFEST)
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: OfficeHud = scene.instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(screen)
	await _frames(2)
	return hud


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


## The number chips of every minimap row, top to bottom.
func _row_numbers(minimap: OfficeSpaces) -> Array:
	return minimap.row_keys().map(func(key: String) -> String: return _label_text(minimap.row_for(key), "%Number"))


## The text of a Label inside a HUD part, by its unique name.
func _label_text(holder: Node, unique_name: String) -> String:
	var label: Label = holder.get_node(unique_name)
	return label.text


## A floor row's name label, which carries the variation that dims a quiet floor.
func _row_label(minimap: OfficeSpaces, key: String) -> Label:
	return minimap.row_for(key).get_node("%SpaceLabel")


## Every icon the minimap shows now, in row order. A floor without a count
## keeps its icon node hidden and out of the badge group.
func _floor_icons(minimap: OfficeSpaces) -> Array:
	# A building heading's mark is a plain sprite, not a badge: it stands for a
	# machine answering, which nobody is waiting on, so it never pulses.
	return minimap.find_children("*", "StatusBadge", true, false).filter(
		func(badge: StatusBadge) -> bool: return badge.is_visible_in_tree()
	)


## One floor for the minimap, which draws a row per floor and nothing else.
func _floor_row(key: String, number: int, agents: int, blocked: int, done: int) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = key
	floor_model.number = number
	floor_model.label = key
	floor_model.agents = agents
	floor_model.blocked = blocked
	floor_model.done = done
	return floor_model


func _building_rows(key: String, label: String, state: MachineLiveness.State, floors: Array[ZoneModel]) -> SpaceRows:
	var building := SpaceRows.new()
	building.key = key
	building.label = label
	building.state = state
	building.zones = floors
	return building
