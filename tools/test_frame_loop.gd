extends "res://tools/office_test_base.gd"
## The live office's frame loop: how often it runs (FramePacer) and what it
## does on the frames it runs. Headless, so the pacer never writes
## Engine.max_fps here; what it would choose is read through wanted_fps().


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for required: String in ["socket", "work"]:
		if not args.has(required):
			print("TEST_HARNESS_ERROR: missing --%s=" % required)
			quit(2)
			return
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("frame-loop-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if not parsed is Dictionary:
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "FRAME LOOP TESTS"


## The pacer the live office added for itself.
func _pacer(office: OfficeScene) -> FramePacer:
	return office.get_node("FramePacer")


## The lift a badge shows now, in the density-1 units the viewer sees.
func _lift(badge: StatusBadge) -> float:
	return (badge.offset.y - badge.rest_offset.y) * badge.scale.y


func test_policy_covers_every_window_state() -> void:
	_eq(
		[FramePacer.INTERACTING_FPS, FramePacer.IDLE_FPS, FramePacer.UNFOCUSED_FPS, FramePacer.MINIMIZED_FPS],
		[60, 30, 12, 8],
		"in use, at rest, in the background, minimized"
	)
	# minimized, focused, interacting -> frames per second
	var table := [
		[false, true, false, 30],
		[false, true, true, 60],
		[false, false, false, 12],
		[false, false, true, 60],
		[true, true, false, 8],
		[true, true, true, 8],
		[true, false, false, 8],
		[true, false, true, 8],
	]
	for row: Array in table:
		var minimized: bool = row[0]
		var focused: bool = row[1]
		var interacting: bool = row[2]
		_eq(
			FramePacer.choose(minimized, focused, interacting),
			row[3],
			"minimized %s, focused %s, in use %s" % [minimized, focused, interacting]
		)


func test_interaction_lasts_one_and_a_half_seconds() -> void:
	_eq(FramePacer.INTERACTION_MSEC, 1500, "the window after an input event")
	var now := 100000
	_check(not FramePacer.is_interacting(-1, now), "no input yet is nobody using the office")
	_check(FramePacer.is_interacting(now, now), "an event this very moment is")
	_check(FramePacer.is_interacting(now - 1499, now), "so is one 1.499 s ago")
	_check(FramePacer.is_interacting(now - 1500, now), "and one exactly 1.5 s ago")
	_check(not FramePacer.is_interacting(now - 1501, now), "but not one 1.501 s ago")


func test_command_line_pins_or_turns_off_pacing() -> void:
	var none := PackedStringArray()
	_eq(FramePacer.requested(none, 0), FramePacer.ADAPTIVE, "no flag: the pacer chooses")
	_eq(FramePacer.requested(PackedStringArray(["--fps=24"]), 0), 24, "--fps=24 pins 24")
	_eq(FramePacer.requested(PackedStringArray(["--fps=0"]), 0), FramePacer.HANDS_OFF, "--fps=0 turns pacing off")
	_eq(FramePacer.requested(none, 30), FramePacer.HANDS_OFF, "Godot's own --max-fps is kept")
	_eq(FramePacer.requested(PackedStringArray(["--fps=45"]), 30), 45, "--fps= beats it")
	_eq(FramePacer.requested(PackedStringArray(["--fps=fast"]), 0), FramePacer.ADAPTIVE, "a word is ignored")
	_eq(FramePacer.requested(PackedStringArray(["--fps=-5"]), 0), FramePacer.ADAPTIVE, "so is a negative rate")
	var before := Engine.max_fps
	var pinned := FramePacer.new(PackedStringArray(["--fps=24"]))
	root.add_child(pinned)
	await _frames(2)
	_eq(pinned.wanted_fps(), 24, "a pinned pacer asks for its pin")
	_check(not pinned.is_processing() and not pinned.is_processing_input(), "and watches nothing")
	_eq(Engine.max_fps, before, "headless, not even a pin reaches the engine")
	# Should that fail, a leftover cap would turn every later office's pacer off.
	Engine.max_fps = before
	pinned.free()


## Tests and CI run headless: whatever the pacer would choose, the engine's
## frame cap stays as it was.
func test_headless_leaves_the_frame_cap_alone() -> void:
	_eq(DisplayServer.get_name(), "headless", "this suite runs headless")
	var before := Engine.max_fps
	var office := await _live_office()
	var pacer := _pacer(office)
	_eq(pacer.wanted_fps(), FramePacer.IDLE_FPS, "at rest it would ask for the idle rate")
	await _parsed(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	_eq(pacer.wanted_fps(), FramePacer.INTERACTING_FPS, "and after a wheel notch for the full one")
	await _frames(3)
	_eq(Engine.max_fps, before, "but it never writes either")
	# Should that fail, the rest of the suite must not run at whatever it wrote.
	Engine.max_fps = before
	_done(office)


## The pacer only watches: a key it counts still reaches the office, and a
## pointer just passing over is nobody using it.
func test_input_is_watched_never_consumed() -> void:
	var office := await _live_office()
	var pacer := _pacer(office)
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(SCREEN) / 2.0
	hover.global_position = hover.position
	hover.relative = Vector2(3, 2)
	await _parsed(hover)
	_eq(pacer.wanted_fps(), FramePacer.IDLE_FPS, "a pointer passing over is not interaction")
	var zoom := office.zoom
	var key := _key(KEY_EQUAL)
	await _parsed(key)
	key.pressed = false
	await _parsed(key)
	_eq(pacer.wanted_fps(), FramePacer.INTERACTING_FPS, "a key press is")
	_eq(office.zoom, zoom + OfficeScene.ZOOM_STEP, "and it still reaches the office, which zooms in")
	_done(office)


## A window in the background drops to the unfocused rate. herdr's own focus
## moving to another floor, while nobody touches the window, shows that floor
## at once and is nobody using the office: there is no ride to run at the full
## rate. Focus changes reach the tree the way the engine delivers
## them: to the SceneTree, which hands them to every node.
func test_focus_moving_floors_switches_at_once() -> void:
	var office := await _live_office()
	var pacer := _pacer(office)
	notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_eq(pacer.wanted_fps(), FramePacer.UNFOCUSED_FPS, "in the background, at rest")
	var world := office.world.get_instance_id()
	_feed(office, _focused_on(fixture, "web:p1"))
	var zone := office.navigator.current_zone(office.frame)
	_eq(zone, HerdrFleet.pane_key(LOCAL, "web"), "herdr's focus moving zones pans to it at once")
	_eq(office.world.get_instance_id(), world, "on the same map")
	_eq(pacer.wanted_fps(), FramePacer.UNFOCUSED_FPS, "and the background rate holds: nothing rides")
	await _frames(1)
	var desk := _desk_point(office, HerdrFleet.pane_key(LOCAL, "web:p1"))
	_check(office.hud.world_rect().has_point(desk), "its desk in the world's room")
	notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_eq(pacer.wanted_fps(), FramePacer.IDLE_FPS, "and to the idle one with focus back")
	_done(office)


## Badges step on the shared clock through the frame loop itself, which walks
## them only when a rhythm steps.
func test_badges_pulse_through_the_frame_loop() -> void:
	var office := await _live_office(_with(fixture, "api:p4", {"agent_status": "blocked"}))
	var badge := _badge(_station(office, HerdrFleet.pane_key(LOCAL, "api:p4")))
	var lifts := {}
	var until := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		await process_frame
		lifts[_lift(badge)] = true
	_eq(_sorted_lifts(lifts), [-1.0, 0.0], "a blocked badge nudges one pixel, frame by frame")
	_done(office)


## A machine that drops freezes its badges at rest on the next frames, not at
## the next step of their rhythm.
func test_a_dropped_machine_settles_its_badges_at_once() -> void:
	var office := await _live_office(_with(fixture, "api:p4", {"agent_status": "blocked"}))
	var key := HerdrFleet.pane_key(LOCAL, "api:p4")
	var badge := _badge(_station(office, key))
	var until := Time.get_ticks_msec() + 2000
	while _lift(badge) == 0.0 and Time.get_ticks_msec() < until:
		await process_frame
	_eq(_lift(badge), -1.0, "the blocked badge is caught lifted")
	_set_online(office, false)
	await _frames(2)
	badge = _badge(_station(office, key))
	_eq(badge.offset, badge.rest_offset, "two frames after the drop it rests on its pivot")
	_done(office)


## Whether the window is focused, as the pacer saw it: what OfficeAlerts asks
## before it rings. Headless there is no window to lose focus, so a test says
## so through note_focused(); the engine's own notifications go the same way,
## and a minimized window counts as not focused, whatever the app focus says.
func test_focus_seam_follows_note_focused() -> void:
	var office := await _live_office()
	var pacer := _pacer(office)
	_check(pacer.is_focused(), "headless starts focused")
	pacer.note_focused(false)
	_check(not pacer.is_focused(), "note_focused(false) is out of focus")
	_eq(pacer.wanted_fps(), FramePacer.UNFOCUSED_FPS, "and the pacer drops to the background rate")
	notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(pacer.is_focused(), "the engine's focus-in goes through the same seam")
	_eq(pacer.wanted_fps(), FramePacer.IDLE_FPS, "back to the idle rate")
	pacer.note_minimized(true)
	_check(not pacer.is_focused(), "a minimized window is not focused")
	pacer.note_minimized(false)
	notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not pacer.is_focused(), "the engine's focus-out too")
	notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_done(office)
