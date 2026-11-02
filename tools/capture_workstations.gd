extends "res://tools/office_test_base.gd"
## `make workstation-strips OUT=<empty dir>`: a real OfficeDouble station at
## 2x in the 960x640 minimum window, and 4x in a 1920x1280 window. Feed working,
## idle, blocked, done and shell snapshots through the office's data path.
## Nothing is drawn by a standalone substitute or assembled from sprite parts.
##
## Real time is stopped while filming. Advance the station's own AnimationPlayer
## to the middle of every authored frame hold, including the brief blink keys.
## The actor itself chains blocked_enter -> blocked and blocked_exit -> done.
## Each strip keeps the full workstation canvas, chip and plate in view, with
## no image resizing. OUT gets <state>-zoom<z>/NN.png and a matching contact sheet.
##
## Read-only and offline: the client and roster are stopped, the socket has no
## listener, and private environment paths prevent herdr/SSH discovery.
##   godot --path . --script tools/capture_workstations.gd -- --out=<empty dir> --work=<short tmp dir>

const PANE := "api:p2"
const ZOOMS: Array[int] = [2, 4]
const WINDOWS: Dictionary[int, Vector2i] = {2: Vector2i(960, 640), 4: Vector2i(1920, 1280)}
const STATES: Array[StringName] = [&"working", &"idle", &"blocked", &"done"]
const COLUMNS := 4
## World units around the complete station and its annotations.
const MARGIN := 8.0
## Pixels between frames in the contact sheet.
const GAP := 6
## Advance just beyond a one-shot's end so its real completion signal fires.
const PAST_END := 0.001

var _out := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	if not args.has("out") or not args.has("work"):
		_problem("use --out=<empty dir> --work=<short tmp dir>")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		_problem("a headless run draws nothing")
		quit(2)
		return
	_out = args.out
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("strip-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		_problem("cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	_run.call_deferred()


func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_problem("cannot create " + _out)
		quit(1)
		return
	if not DirAccess.get_files_at(_out).is_empty() or not DirAccess.get_directories_at(_out).is_empty():
		_problem("--out must be empty: " + _out)
		quit(1)
		return
	for zoom in ZOOMS:
		# Free the previous office before the window's size_changed signal fires.
		await _frames(2)
		root.size = WINDOWS[zoom]
		await _frames(3)
		if root.size != WINDOWS[zoom] or OfficeScene.content_scale_for(root.size, zoom) != zoom:
			_problem("the display cannot hold the %s window at %dx" % [WINDOWS[zoom], zoom])
			quit(1)
			return
		Engine.time_scale = 0.0
		var office := await _strip_office(zoom)
		var captured := await _sequence(office, zoom)
		_done(office)
		Engine.time_scale = 1.0
		if not captured:
			quit(1)
			return
	print("WORKSTATION_STRIPS_OK: " + _out)
	quit(0)


func _strip_office(zoom: int) -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_args = AppArgs.parse(
		PackedStringArray(
			["--read-only", "--no-bounce", "--zoom=%d" % zoom, "--socket=" + args.work.path_join("nowhere.sock")]
		)
	)
	office.test_screen = Vector2(WINDOWS[zoom]) / float(zoom)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	office.set_process(false)
	_feed(office, _state_snapshot(&"shell"))
	await _frames(3)
	return office


## The same station and retained body throughout; only real snapshot states
## choose clips. In particular, neither blocked transition is played by hand.
func _sequence(office: OfficeDouble, zoom: int) -> bool:
	var key := HerdrFleet.pane_key(LOCAL, PANE)
	var seat := office.floor_view.seat(key)
	if seat == null or not office.layout_problems().is_empty():
		_problem("the office did not seat " + PANE)
		return false
	var station := seat.node
	var actor: WorkstationActor = station.get_node("Actor")
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var area := OfficeStation.CANVAS.merge(station.plate_row())
	area = area.merge(Rect2(OfficeStation.CHIP_AT, OfficeStation.CHIP_SIZE)).grow(MARGIN)
	for state in STATES:
		_feed(office, _state_snapshot(state))
		if office.floor_view.seat(key).node != station or station.actor() != actor or actor.animation != state:
			_problem("the snapshot did not update the retained station to " + str(state))
			return false
		var clips: Array[StringName] = [state]
		if state == &"blocked":
			clips = [&"blocked_enter", &"blocked"]
		elif state == &"done":
			clips = [&"blocked_exit", &"done"]
		for clip in clips:
			if not await _film_track(office, station, area, clip, zoom):
				return false
	_feed(office, _state_snapshot(&"shell"))
	var body: Sprite2D = actor.get_node("Body")
	if station.actor() != null or actor.is_playing() or body.texture != actor.art.empty_texture():
		_problem("the shell snapshot did not leave the empty workstation")
		return false
	var shot := await _shot(office, station, area, zoom)
	if shot == null:
		return false
	var frames: Array[Image] = [shot]
	return _save_strip(frames, "shell", zoom)


## Sample every authored hold, not fixed time intervals that skip the short
## gestures. Advancing a one-shot beyond its end exercises the actor's real
## animation_finished handler before the next strip begins.
func _film_track(office: OfficeDouble, station: OfficeStation, area: Rect2, clip: StringName, zoom: int) -> bool:
	var actor := station.actor()
	if actor == null or actor.track != clip:
		_problem("the station did not enter " + str(clip))
		return false
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	var body: Sprite2D = actor.get_node("Body")
	var track := actor.art.tracks[clip]
	var frames: Array[Image] = []
	var at := 0.0
	for index in track.frames.size():
		var sample := at + track.seconds[index] / 2.0
		player.advance(sample - player.current_animation_position)
		if actor.track != clip or body.frame != track.frames[index]:
			_problem("%s did not draw authored frame %d" % [clip, index])
			return false
		var shot := await _shot(office, station, area, zoom)
		if shot == null:
			return false
		frames.append(shot)
		at += track.seconds[index]
	if not track.loop:
		player.advance(track.duration - player.current_animation_position + PAST_END)
		if clip == &"done":
			if actor.is_playing():
				_problem("the done one-shot did not stop")
				return false
			var held := await _shot(office, station, area, zoom)
			if held == null:
				return false
			frames.append(held)
	var name := "blocked-recline" if clip == &"blocked" else str(clip).replace("_", "-")
	return _save_strip(frames, name, zoom)


## Keep the crop wholly inside the world, not behind a HUD panel. Reject any
## clipping or unexpected zoom instead of quietly producing a smaller image.
func _shot(office: OfficeDouble, station: OfficeStation, area: Rect2, zoom: int) -> Image:
	var world_area: Rect2 = office.world.global_transform.affine_inverse() * station.global_transform * area
	office.camera.reveal(world_area)
	await _frames(2)
	await RenderingServer.frame_post_draw
	var shown: Rect2 = station.get_global_transform_with_canvas() * area
	if not office.hud.world_rect().encloses(shown) or not is_equal_approx(root.content_scale_factor, float(zoom)):
		_problem("the complete station crop is not visible at %dx" % zoom)
		return null
	var pixels := Rect2i(Vector2i((shown.position * zoom).floor()), Vector2i((shown.size * zoom).ceil()))
	var image := root.get_texture().get_image()
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(pixels):
		_problem("the complete station crop is outside the rendered image")
		return null
	return image.get_region(pixels)


func _save_strip(frames: Array[Image], name: String, zoom: int) -> bool:
	var tag := "%s-zoom%d" % [name, zoom]
	var directory := _out.path_join(tag)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_problem("cannot create " + directory)
		return false
	for index in frames.size():
		var path := directory.path_join("%02d.png" % index)
		if frames[index].save_png(path) != OK:
			_problem("cannot save " + path)
			return false
	var path := _out.path_join(tag + ".png")
	if _sheet(frames).save_png(path) != OK:
		_problem("cannot save " + path)
		return false
	print("WORKSTATION_STRIP: %s, %d frames" % [tag, frames.size()])
	return true


## Frames in reading order, COLUMNS a row, GAP apart; no resampling.
func _sheet(frames: Array[Image]) -> Image:
	var cell := Vector2i.ZERO
	for frame in frames:
		cell = cell.max(frame.get_size())
	var columns := mini(COLUMNS, frames.size())
	var rows := ceili(frames.size() / float(columns))
	var size := Vector2i(columns * (cell.x + GAP) + GAP, rows * (cell.y + GAP) + GAP)
	var sheet := Image.create_empty(size.x, size.y, false, frames[0].get_format())
	sheet.fill(Color(0.1, 0.1, 0.12))
	for index in frames.size():
		var at := Vector2i(
			GAP + (index % columns) * (cell.x + GAP), GAP + floori(index / float(columns)) * (cell.y + GAP)
		)
		sheet.blit_rect(frames[index], Rect2i(Vector2i.ZERO, frames[index].get_size()), at)
	return sheet


func _state_snapshot(state: StringName) -> Dictionary:
	var shell := state == &"shell"
	var next := _with(
		fixture, PANE, {"agent": null if shell else "codex", "agent_status": "idle" if shell else str(state)}
	)
	if shell:
		next.agents = _list(next, "agents").filter(func(record: Dictionary) -> bool: return record.pane_id != PANE)
	else:
		for record: Dictionary in _list(next, "agents"):
			if record.pane_id == PANE:
				record.agent_status = str(state)
	return next


func _problem(message: String) -> void:
	printerr("WORKSTATION_STRIPS_FAILED: " + message)
