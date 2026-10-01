extends SceneTree
## One measured run for tools/perf.sh (`make perf`): builds a scene in a real
## window, lets it settle, holds still while perf.sh reads the process's CPU
## time from outside, then reads the engine's own monitors and prints one
## `PERF_RESULT` line.
##
##   godot --path . --script tools/perf_probe.gd -- --mode=office --socket=... [--fps=0]
##   godot --path . --script tools/perf_probe.gd -- --mode=office --socket=... --control=... --walk=arrivals
##   godot --path . --script tools/perf_probe.gd -- --mode=actors --count=80
##
## --mode=office   the live office (scenes/office.tscn) against whatever herdr
##                 --socket= names; it paces itself, and `--fps=` reaches it.
## --walk=         with --mode=office, walk the stress floor's people
##                 (`make perf WALKS=1`): the fake herdr behind --control=
##                 serves the floor it starts from (tools/gen_stress_fixture.py)
##                 and the probe changes it right after PERF_HOLD, then times
##                 every frame of the hold. `arrivals`: 80 agents walk in at once
##                 onto the floor drawn live with shells. `done40`: 40 of 80
##                 seated agents are done at once (they stay seated and 40
##                 stacks of paper show; nobody walks). `growth`: 80
##                 walk in, and 1.5 s later tab 0 grows by 12 under them.
##                 `minimize`: 80 walk in, and 1.5 s later the window is
##                 minimized for 2 s. From 80 at work: `blocked40`:
##                 40 go blocked at once (all raise a hand at their
##                 desks under 40 chips; nobody walks); `idle40`: 40 go idle
##                 at once (to the pantry); `approve`: once those 40 are
##                 blocked, one of them is answered every APPROVE_EVERY
##                 seconds, 8 times (a chip goes each time); `queuegrow`: 40
##                 go blocked, and 1.5 s later tab 0 grows by 12 under them.
##                 The names stay fixed so runs stay comparable.
## --overview=open with --mode=office, the OVERVIEW open over the office
##                 (office.open_overview() after the warmup; the office's own
##                 command line opens it at start too): PERF_RESULT says
##                 `overview=open`, and its refresh_ms includes drawing it.
## --mode=actors   --count= pixel people (scenes/people/pixel_person.tscn),
##                 seated and working, as the office seats its workers, every
##                 one of them on screen (checked person by person: a run with
##                 anyone off screen fails, since off screen draws nothing). It
##                 gets a FramePacer of its own, so the paced and `--fps=0`
##                 columns mean the same as the office's.
## window=        in PERF_RESULT: the window's real size, which a display too
##                 small for the one asked (perf.sh's overview asks 3200x1600)
##                 makes smaller than asked.
## on_screen=      in PERF_RESULT: how many people stood inside the window when
##                 the hold began (actors: all of them; the office: whoever
##                 its camera shows at its --zoom).
## --warmup=6      seconds to settle first (the office waits for its data).
## --hold=9        seconds to hold still after `PERF_HOLD`: the CPU window.
##
## Never --headless: a headless run draws nothing, so it measures nothing.

const OFFICE_SCENE := "res://scenes/office.tscn"
const PERSON_SCENE := "res://scenes/people/pixel_person.tscn"
const PACK := "res://assets/daylight/manifest.json"
## Frames the draw-call and node monitors are averaged over.
const SAMPLE_FRAMES := 30
## `refresh()` calls timed for the mean.
const REFRESHES := 50
const WALKS: Array[String] = ["arrivals", "done40", "growth", "minimize", "blocked40", "idle40", "approve", "queuegrow"]
## What each --walk= but `minimize` changes the fake herdr's snapshot to.
const WALK_TO: Dictionary[String, String] = {
	"arrivals": "snapshot_stress80_working",
	"done40": "snapshot_stress80_done40",
	"growth": "snapshot_stress92_grown",
	"blocked40": "snapshot_stress80_blocked40",
	"idle40": "snapshot_stress80_idle40",
	"queuegrow": "snapshot_stress92_blocked40",
}
## What `approve` and `queuegrow` start from: 40 blocked.
const QUEUE_START := "snapshot_stress80_blocked40"
## `approve`: how many times the head is answered, and how often.
const APPROVALS := 8
const APPROVE_EVERY := 0.75
const WALK_START := "snapshot_stress80_working"
## A pane that is an agent at work in every snapshot a walk goes to: a status
## event for it makes the client read the new snapshot at once.
const WALK_EVENT_PANE := "w0:t9:p7"
## Seconds between the arrivals and the growth or the minimizing.
const WALK_LEAD := 1.5
## Seconds the window stays minimized.
const MINIMIZED_FOR := 2.0

var _mode := "office"
var _walk := ""
var _control := ""
## When the office last finished a refresh for new herdr data, in µs.
var _changed_at := 0
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
		elif argument.begins_with("--walk="):
			_walk = argument.trim_prefix("--walk=")
		elif argument.begins_with("--control="):
			_control = argument.trim_prefix("--control=")
		elif argument == "--overview=open":
			_overview = true
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
	var on_screen := _on_screen()
	if _mode == "actors" and on_screen != _count:
		print("PERF_FAILED: only %d of %d people are on screen" % [on_screen, _count])
		quit(1)
		return
	var walked := ""
	if not _walk.is_empty():
		walked = await _walks(office)
		if walked.is_empty():
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
		walked += " overview=open"
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
				walked,
			]
		)
	)
	quit()


## Walk the stress floor's people as --walk= says, timing every frame of the
## hold, which starts as the snapshot changes. The fields it adds to
## PERF_RESULT, or empty after printing PERF_FAILED: the frame times over the
## hold (p50_ms, p95_ms, max_ms, frames); the longest process step in it
## (step_ms) and the longest time from a frame's start to the end of the
## office's refresh for new data in it (walk_refresh_ms: reading the snapshot,
## projecting, laying out, reconciling and the presentation's pass; -1 when no
## new data came, as when minimizing); what the
## observation did (pass_ms, walked, kept, placed, expanded: OfficePresentation's
## counters); how many were walking when it came (live) and when the last walk
## ended (settle_s, -1 past the hold); for `minimize`, the frames the window
## reported minimized, the pacer's rate then, and how long the two window-mode
## calls themselves blocked (they run inside a process step).
func _walks(office: OfficeScene) -> String:
	if not (_walk in WALKS) or _control.is_empty():
		print("PERF_FAILED: --walk=arrivals|done40|growth|minimize needs --control=")
		return ""
	# The office's refresh for new data (the one a frame's events are coalesced
	# into, OfficeScene._queue_refresh()) says when it is done.
	office.data_refreshed.connect(_note_changed)
	var presentation := office.floor_view.presentation
	if _walk == "growth" or _walk == "minimize" or _walk == "queuegrow" or _walk == "approve":
		if not _send(QUEUE_START if _walk == "queuegrow" or _walk == "approve" else WALK_START):
			return ""
		var began := Time.get_ticks_msec()
		while presentation.walkers().is_empty() and Time.get_ticks_msec() - began < 3000:
			await process_frame
		if _walk == "approve":
			# Everyone in the queue, the rest at their desks, before the head is answered.
			while not presentation.walkers().is_empty() and Time.get_ticks_msec() - began < 10000:
				await process_frame
		else:
			await create_timer(WALK_LEAD).timeout
	var live := presentation.walkers().size()
	var before := _counters(presentation)
	print("PERF_HOLD %.1f" % _hold)
	var fired := Time.get_ticks_usec()
	var minimize_call := 0
	var restore_call := 0
	var approvals := 0
	if _walk == "minimize":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		minimize_call = Time.get_ticks_usec() - fired
	elif _walk == "approve":
		approvals = 1
		if not _send("%s_a1" % QUEUE_START):
			return ""
	elif not _send(WALK_TO[_walk]):
		return ""
	var deltas := PackedInt64Array()
	var step := 0.0
	var refresh := 0
	var seen := before
	var settled := -1.0
	var minimized := 0
	var minimized_fps := -1
	var restored := false
	var last := fired
	while last - fired < int(_hold * 1_000_000):
		await process_frame
		var now := Time.get_ticks_usec()
		if _changed_at >= last:
			# A refresh for new data ended in the frame that just ended.
			refresh = maxi(refresh, _changed_at - last)
		deltas.append(now - last)
		last = now
		step = maxf(step, Performance.get_monitor(Performance.TIME_PROCESS))
		if _counters(presentation) != before:
			seen = _counters(presentation)
		if _walk == "approve" and approvals < APPROVALS and now - fired >= int(approvals * APPROVE_EVERY * 1_000_000):
			approvals += 1
			if not _send("%s_a%d" % [QUEUE_START, approvals]):
				return ""
		var passed := seen != before or _walk == "minimize"
		if (
			passed
			and settled < 0.0
			and presentation.walkers().is_empty()
			and approvals >= (APPROVALS if _walk == "approve" else 0)
		):
			settled = (now - fired) / 1_000_000.0
		if _walk == "minimize":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
				minimized += 1
				minimized_fps = Engine.max_fps
			if not restored and now - fired >= int(MINIMIZED_FOR * 1_000_000):
				restored = true
				var asked := Time.get_ticks_usec()
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				restore_call = Time.get_ticks_usec() - asked
	var sorted := deltas.duplicate()
	sorted.sort()
	var fields := (
		" walk=%s frames=%d p50_ms=%.2f p95_ms=%.2f max_ms=%.2f step_ms=%.2f live=%d settle_s=%.2f"
		% [
			_walk,
			sorted.size(),
			_quantile(sorted, 0.5) / 1000.0,
			_quantile(sorted, 0.95) / 1000.0,
			sorted[sorted.size() - 1] / 1000.0,
			step * 1000.0,
			live,
			settled,
		]
	)
	fields += (
		" walk_refresh_ms=%.2f pass_ms=%.2f walked=%d kept=%d placed=%d expanded=%d"
		% [refresh / 1000.0 if refresh > 0 else -1.0, seen[4] / 1000.0, seen[0], seen[1], seen[2], seen[3]]
	)
	if _walk == "minimize":
		fields += (
			" minimized_frames=%d minimized_fps=%d minimize_call_ms=%.1f restore_call_ms=%.1f"
			% [minimized, minimized_fps, minimize_call / 1000.0, restore_call / 1000.0]
		)
	return fields


func _note_changed() -> void:
	_changed_at = Time.get_ticks_usec()


## The presentation's counters of the last observation that changed the floor:
## walked, kept, placed, expanded and its time in µs.
static func _counters(presentation: OfficePresentation) -> PackedInt64Array:
	return PackedInt64Array(
		[
			presentation.pass_walked,
			presentation.pass_kept,
			presentation.pass_placed,
			presentation.pass_expanded,
			presentation.pass_usec
		]
	)


## The value at `fraction` of the way through the sorted `values`.
static func _quantile(values: PackedInt64Array, fraction: float) -> float:
	return values[mini(values.size() - 1, floori(fraction * values.size()))]


## Have the fake herdr serve the fixture `name`, and send a status event so the
## client reads it now rather than at its next periodic snapshot.
func _send(name: String) -> bool:
	if not _ctl("set_snapshot", {"fixture": name}):
		return false
	return _ctl("status", {"pane_id": WALK_EVENT_PANE, "agent_status": "working"})


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


## People whose whole frame is inside the window now: every pixel person in the
## tree, the office's workers or the actors.
func _on_screen() -> int:
	var visible := root.get_visible_rect()
	var count := 0
	for node in root.find_children("*", "CharacterBody2D", true, false):
		var person := node as PixelPerson
		if person == null or not person.is_visible_in_tree():
			continue
		var feet := person.get_global_transform_with_canvas().origin
		var scale := person.get_global_transform_with_canvas().get_scale()
		var frame := PixelPerson.drawing_rect(person.people) if person.people != null else Rect2()
		if visible.encloses(Rect2(feet + frame.position * scale, frame.size * scale)):
			count += 1
	return count


## `_count` workers in rows, all animating, all on screen: at content scale 1
## the window shows 960x480 units, and sixteen to a row, five rows, fit in it.
## (At content scale 2 it would show 480x240 units and only 27 of the 80.)
func _figures() -> bool:
	root.content_scale_factor = 1
	var art := ArtPack.from_manifest(PACK)
	var person_scene: PackedScene = load(PERSON_SCENE)
	for i in _count:
		var person: PixelPerson = person_scene.instantiate()
		person.position = _slot(i)
		root.add_child(person)
		person.configure(art.people, "claude", AvatarLook.facing(AvatarLook.DESK, AvatarLook.FRONT))
		person.play_state(&"working")
	return true


## Sixteen figures to a row, far enough apart not to overlap.
func _slot(index: int) -> Vector2:
	return Vector2(30 + (index % 16) * 55, 70 + floori(index / 16.0) * 90)
