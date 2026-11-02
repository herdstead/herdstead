extends SceneTree
## One measured run for tools/perf.sh (`make perf`): builds a scene in a real
## window, lets it settle, holds still while perf.sh reads the process's CPU
## time from outside, then reads the engine's own monitors and prints one
## `PERF_RESULT` line.
##
##   godot --path . --script tools/perf_probe.gd -- --mode=office --socket=... [--fps=0]
##   godot --path . --script tools/perf_probe.gd -- --mode=office --socket=... --control=... --fixtures=... --change=arrivals
##   godot --path . --script tools/perf_probe.gd -- --mode=actors --count=80
##
## --mode=office   the live office (scenes/office.tscn) against whatever herdr
##                 --socket= names; it paces itself, and `--fps=` reaches it.
## --change=       with --mode=office, change the fake herdr's snapshot
##                 (`make perf CHANGES=1`). --fixtures= is the same generated
##                 directory the fake behind --control= serves. Time every
##                 frame from PERF_HOLD and each change from sending it until
##                 data_refreshed confirms the complete expected snapshot.
##                 `arrivals`: 80 shells gain agents; `done40`, `blocked40`,
##                 `idle40`: 40 of 80 working agents change state. `growth`:
##                 arrivals, then tab 0 grows by 12 after 1.5 s. `blockedgrow`:
##                 40 go blocked, then the same growth. `approve`: start with
##                 40 blocked and return one to work every 0.75 s, eight times.
##                 `minimize`: arrivals, then minimize after 1.5 s for 2 s.
##                 These are real data changes, not motion or animation counters.
## --overview=open with --mode=office, the OVERVIEW open over the office
##                 (office.open_overview() after the warmup; the office's own
##                 command line opens it at start too): PERF_RESULT says
##                 `overview=open`, and its refresh_ms includes drawing it.
## --mode=actors   --count= complete WorkstationActors, working at native 2x
##                 density (one texture pixel per window pixel), never shrunk
##                 to fit. Every full 80x80-unit canvas must fit on screen or
##                 the run fails. It gets its own FramePacer so the paced and
##                 `--fps=0` columns mean the same as the office's.
## window=        in PERF_RESULT: the window's real size, which a display too
##                 small for the one asked (perf.sh's overview asks 3200x1600)
##                 makes smaller than asked.
## on_screen=      full workstation canvases inside the visible area when the
##                 hold began, empty desks included (actors: all of them;
##                 office: inside the HUD's world rectangle at its --zoom).
## --warmup=6      seconds to settle first (the office waits for its data).
## --hold=9        seconds to hold still after `PERF_HOLD`: the CPU window.
##
## Never --headless: a headless run draws nothing, so it measures nothing.

const OFFICE_SCENE := "res://scenes/office.tscn"
const ACTOR_SCENE := "res://scenes/world/workstation_actor.tscn"
## Frames the draw-call and node monitors are averaged over.
const SAMPLE_FRAMES := 30
## `refresh()` calls timed for the mean.
const REFRESHES := 50
const CHANGES: Array[String] = [
	"arrivals", "done40", "growth", "minimize", "blocked40", "idle40", "approve", "blockedgrow"
]
const CHANGE_TO: Dictionary[String, String] = {
	"arrivals": "snapshot_stress80_working",
	"done40": "snapshot_stress80_done40",
	"growth": "snapshot_stress92_grown",
	"blocked40": "snapshot_stress80_blocked40",
	"idle40": "snapshot_stress80_idle40",
	"blockedgrow": "snapshot_stress92_blocked40",
}
const BLOCKED_START := "snapshot_stress80_blocked40"
const WORKING := "snapshot_stress80_working"
## `approve`: how many blocked panes return to work, and how often.
const APPROVALS := 8
const APPROVE_EVERY := 0.75
## A pane that is an agent at work in every destination snapshot: a status
## event for it makes the client read the new snapshot at once.
const CHANGE_EVENT_PANE := "w0:t9:p7"
## Seconds between the arrivals and the growth or the minimizing.
const CHANGE_LEAD := 1.5
## A missed snapshot is a failed run, not a latency of zero.
const CHANGE_TIMEOUT := 3.0
## Seconds the window stays minimized.
const MINIMIZED_FOR := 2.0
## World units between complete canvases and around the standalone grid.
const FIGURE_GAP := 8.0


class SnapshotChange:
	extends RefCounted
	var fixture := ""
	var signature := ""
	var due := 0.0
	var sent_at := 0
	var refreshed_at := 0


var _mode := "office"
var _change := ""
var _control := ""
var _fixtures := ""
var _pending: SnapshotChange
var _count := 80
var _warmup := 6.0
var _hold := 9.0
var _overview := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--count="):
			_count = argument.trim_prefix("--count=").to_int()
		elif argument.begins_with("--warmup="):
			_warmup = argument.trim_prefix("--warmup=").to_float()
		elif argument.begins_with("--hold="):
			_hold = argument.trim_prefix("--hold=").to_float()
		elif argument.begins_with("--change="):
			_change = argument.trim_prefix("--change=")
		elif argument.begins_with("--control="):
			_control = argument.trim_prefix("--control=")
		elif argument.begins_with("--fixtures="):
			_fixtures = argument.trim_prefix("--fixtures=")
		elif argument == "--overview=open":
			_overview = true
		elif argument.begins_with("--walk"):
			print("PERF_FAILED: --walk was removed; use --change= with --control= and --fixtures=")
			quit(2)
			return
	if DisplayServer.get_name() == "headless":
		print("PERF_FAILED: run it in a window; headless draws nothing")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var office: OfficeScene = null
	if _mode == "office":
		office = (load(OFFICE_SCENE) as PackedScene).instantiate()
		root.add_child(office)
	elif _mode == "actors":
		if not _figures():
			quit(1)
			return
		root.add_child(FramePacer.new(OS.get_cmdline_user_args()))
	else:
		print("PERF_FAILED: unknown --mode=" + _mode)
		quit(2)
		return
	var settled := Time.get_ticks_msec() + int(_warmup * 1000.0)
	while Time.get_ticks_msec() < settled:
		await process_frame
	if office != null and not office.fleet.all_loaded():
		print("PERF_FAILED: the office has no herdr data after %.0fs" % _warmup)
		quit(1)
		return
	if office != null and _overview:
		office.open_overview()
		if not office.hud.overview_open():
			print("PERF_FAILED: the overview would not open")
			quit(1)
			return
	var on_screen := _on_screen(office)
	if _mode == "actors" and on_screen != _count:
		print("PERF_FAILED: only %d of %d complete workstation canvases are on screen" % [on_screen, _count])
		quit(1)
		return
	var changed := ""
	if not _change.is_empty():
		changed = await _changes(office)
		if changed.is_empty():
			quit(1)
			return
	else:
		print("PERF_HOLD %.1f" % _hold)
		await create_timer(_hold).timeout
	# What the pacer ended up at and how fast frames really came, over the hold.
	var max_fps := Engine.max_fps
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var nodes := 0.0
	var draw_calls := 0.0
	for frame in SAMPLE_FRAMES:
		await process_frame
		nodes += Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	# Video memory the textures hold, in MiB: the cost of a denser family.
	var texture_mib := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	if _overview:
		changed += " overview=open"
	var refresh_ms := -1.0
	if office != null:
		var begin := Time.get_ticks_usec()
		for i in REFRESHES:
			office.refresh()
		refresh_ms = (Time.get_ticks_usec() - begin) / 1000.0 / REFRESHES
	print(
		(
			"PERF_RESULT mode=%s window=%dx%d on_screen=%d nodes=%.0f draw_calls=%.0f texture_mib=%.1f refresh_ms=%.3f fps=%.1f max_fps=%d%s"
			% [
				_mode,
				root.size.x,
				root.size.y,
				on_screen,
				nodes / SAMPLE_FRAMES,
				draw_calls / SAMPLE_FRAMES,
				texture_mib,
				refresh_ms,
				fps,
				max_fps,
				changed,
			]
		)
	)
	quit()


## Frame times span the entire hold, including control requests. Latencies
## span each request through the data_refreshed signal for its full snapshot,
## including the client's debounce, transport, projection, layout and drawing
## updates. They do not claim to be CPU time or time until an animation ends.
func _changes(office: OfficeScene) -> String:
	if office == null or not CHANGES.has(_change) or _control.is_empty() or _fixtures.is_empty():
		print("PERF_FAILED: --change=%s needs --mode=office, --control= and --fixtures=" % "|".join(CHANGES))
		return ""
	var changes := _prepare_changes()
	if changes.is_empty():
		return ""
	var required := changes[-1].due + CHANGE_TIMEOUT
	if _change == "minimize":
		required = maxf(required, CHANGE_LEAD + MINIMIZED_FOR + 1.0)
	if _hold < required:
		print("PERF_FAILED: --change=%s needs --hold=%.2f or longer" % [_change, required])
		return ""
	var observed := _note_changed.bind(office)
	office.data_refreshed.connect(observed)
	print("PERF_HOLD %.1f" % _hold)
	var fired := Time.get_ticks_usec()
	var last := fired
	var next := 0
	var deltas := PackedInt64Array()
	var step := 0.0
	var minimized := 0
	var minimized_fps := -1
	var minimize_call := 0
	var restore_call := 0
	var minimized_at := 0
	var restored := false
	while last - fired < int(_hold * 1_000_000):
		var elapsed := (Time.get_ticks_usec() - fired) / 1_000_000.0
		if _pending == null and next < changes.size() and elapsed >= changes[next].due:
			_pending = changes[next]
			_pending.sent_at = Time.get_ticks_usec()
			next += 1
			if not _send(_pending.fixture):
				break
		if _change == "minimize":
			if minimized_at == 0 and elapsed >= CHANGE_LEAD:
				var asked := Time.get_ticks_usec()
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
				minimized_at = Time.get_ticks_usec()
				minimize_call = minimized_at - asked
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
				minimized += 1
				minimized_fps = Engine.max_fps
			if (
				minimized_at > 0
				and not restored
				and Time.get_ticks_usec() - minimized_at >= int(MINIMIZED_FOR * 1_000_000)
			):
				var asked := Time.get_ticks_usec()
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				restore_call = Time.get_ticks_usec() - asked
				restored = true
		await process_frame
		var now := Time.get_ticks_usec()
		deltas.append(now - last)
		last = now
		step = maxf(step, Performance.get_monitor(Performance.TIME_PROCESS))
		if _pending != null and now - _pending.sent_at > int(CHANGE_TIMEOUT * 1_000_000):
			print("PERF_FAILED: no data_refreshed for " + _pending.fixture)
			break
	if minimized_at > 0 and not restored:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	office.data_refreshed.disconnect(observed)
	_pending = null
	for change in changes:
		if change.refreshed_at == 0:
			print("PERF_FAILED: snapshot transition did not complete: " + change.fixture)
			return ""
	if (
		_change == "minimize"
		and (minimized == 0 or not restored or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)
	):
		print("PERF_FAILED: the window did not complete a measured minimize/restore")
		return ""
	var fields := _change_fields(changes, deltas, step, fired)
	if _change == "minimize":
		fields += (
			" minimized_frames=%d minimized_fps=%d minimize_call_ms=%.1f restore_call_ms=%.1f"
			% [minimized, minimized_fps, minimize_call / 1000.0, restore_call / 1000.0]
		)
	return fields


## Load the expected typed snapshots before measuring. An intermediate status
## event or an unrelated refresh cannot stand in for a complete transition.
func _prepare_changes() -> Array[SnapshotChange]:
	var names: Array[String] = []
	if _change == "approve":
		for index in APPROVALS:
			names.append("%s_a%d" % [BLOCKED_START, index + 1])
	elif _change == "minimize":
		names.append(WORKING)
	elif _change == "growth" or _change == "blockedgrow":
		names.append(WORKING if _change == "growth" else BLOCKED_START)
		names.append(CHANGE_TO[_change])
	else:
		names.append(CHANGE_TO[_change])
	var changes: Array[SnapshotChange] = []
	for index in names.size():
		var path := _fixtures.path_join(names[index] + ".json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var snapshot: HerdrSnapshot
		if parsed is Dictionary:
			var envelope: Dictionary = parsed
			snapshot = HerdrSnapshot.from_wire(envelope.get("snapshot"))
		if snapshot == null or snapshot.is_empty():
			print("PERF_FAILED: cannot read expected snapshot " + path)
			return []
		var change := SnapshotChange.new()
		change.fixture = names[index]
		change.signature = snapshot.signature()
		change.due = index * (APPROVE_EVERY if _change == "approve" else CHANGE_LEAD)
		changes.append(change)
	return changes


func _note_changed(office: OfficeScene) -> void:
	var ended := Time.get_ticks_usec()
	if _pending == null or not office.fleet.snapshot_is_current(HerdrFleet.LOCAL):
		return
	if not office.layout_problems().is_empty():
		return
	if office.fleet.snapshot(HerdrFleet.LOCAL).signature() == _pending.signature:
		_pending.refreshed_at = ended
		_pending = null


func _change_fields(changes: Array[SnapshotChange], deltas: PackedInt64Array, step: float, fired: int) -> String:
	deltas.sort()
	var longest := 0
	var total := 0
	for change in changes:
		var latency := change.refreshed_at - change.sent_at
		longest = maxi(longest, latency)
		total += latency
		print("PERF_CHANGE fixture=%s latency_ms=%.2f" % [change.fixture, latency / 1000.0])
	var fields := (
		" change=%s frames=%d p50_ms=%.2f p95_ms=%.2f max_ms=%.2f step_ms=%.2f"
		% [
			_change,
			deltas.size(),
			_quantile(deltas, 0.5) / 1000.0,
			_quantile(deltas, 0.95) / 1000.0,
			deltas[-1] / 1000.0,
			step * 1000.0,
		]
	)
	return (
		fields
		+ (
			" changes=%d change_refresh_ms=%.2f change_mean_ms=%.2f applied_s=%.2f"
			% [
				changes.size(),
				longest / 1000.0,
				total / 1000.0 / changes.size(),
				(changes[-1].refreshed_at - fired) / 1_000_000.0
			]
		)
	)


## The value at `fraction` of the way through the sorted `values`.
static func _quantile(values: PackedInt64Array, fraction: float) -> float:
	return values[mini(values.size() - 1, floori(fraction * values.size()))]


## Have the fake herdr serve the fixture `name`, and send a status event so the
## client reads it now rather than at its next periodic snapshot.
func _send(name: String) -> bool:
	if not _ctl("set_snapshot", {"fixture": name}):
		return false
	return _ctl("status", {"pane_id": CHANGE_EVENT_PANE, "agent_status": "working"})


## One command on the fake herdr's control socket (tools/fake_herdr.py), as
## tools/client_test_base.gd sends them; false, after PERF_FAILED, unless it
## answered ok within two seconds.
func _ctl(command: String, args: Dictionary) -> bool:
	var peer := StreamPeerUDS.new()
	if peer.connect_to_host(_control) != OK:
		print("PERF_FAILED: the control socket is unreachable for " + command)
		return false
	var payload := (JSON.stringify({"cmd": command, "args": args}) + "\n").to_utf8_buffer()
	var sent := false
	var buffer := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 2000
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
	var ok := false
	if answer is Dictionary:
		var reply: Dictionary = answer
		ok = reply.get("ok", false) == true
	if not ok:
		print("PERF_FAILED: control %s: %s" % [command, answer])
	return ok


## Count full authored canvases, not foot points or opaque-pixel bounds. An
## office's HUD panels are outside its visible world area; empty desks count.
func _on_screen(office: OfficeScene) -> int:
	var visible := root.get_visible_rect()
	if office != null:
		visible = visible.intersection(office.hud.world_rect())
	var count := 0
	for node in root.find_children("*", "Node2D", true, false):
		var actor := node as WorkstationActor
		if actor == null or actor.art == null or not actor.is_visible_in_tree():
			continue
		var canvas := Rect2(-actor.art.pivot, Vector2(actor.art.frame_size))
		if visible.encloses(actor.get_global_transform_with_canvas() * canvas):
			count += 1
	return count


## A native-density grid: never reduce the actors or the window scale to make
## the requested count fit. perf.sh asks for a 3200x1600 window for this case.
func _figures() -> bool:
	var art := WorkstationArt.from_manifest()
	if art == null or _count <= 0:
		print("PERF_FAILED: FIGURES needs workstation art and --count above zero")
		return false
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_factor = art.density
	var room := Vector2(root.size) / float(art.density)
	var pitch := Vector2(art.frame_size) + Vector2.ONE * FIGURE_GAP
	var columns := floori((room.x - FIGURE_GAP) / pitch.x)
	var rows := floori((room.y - FIGURE_GAP) / pitch.y)
	if columns <= 0 or rows <= 0 or columns * rows < _count:
		print("PERF_FAILED: %d native workstation canvases do not fit the %s window" % [_count, root.size])
		return false
	var actor_scene: PackedScene = load(ACTOR_SCENE)
	for index in _count:
		var actor: WorkstationActor = actor_scene.instantiate()
		var slot := Vector2(index % columns, floori(index / float(columns)))
		actor.position = Vector2.ONE * FIGURE_GAP + slot * pitch + art.pivot
		root.add_child(actor)
		actor.configure(art, "claude")
		actor.play_state(&"working")
	return true
