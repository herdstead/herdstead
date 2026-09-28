extends "res://tools/office_test_base.gd"
## `make walk-strips OUT=<dir>`: frame strips of people walking on the live
## office, one frame every STEP seconds, at zoom 2 in the default 1920x960
## window and at zoom 4 in a 1920x1280 one (the smallest that holds the 480x320
## screen four times over). Windowed only: a headless viewport draws nothing.
##
## The office is the real one, fed tools/fixtures/snapshot_floors.json and its
## changes the way the office suites feed it: its client stopped, `--read-only`,
## a socket nobody listens on and no herdr binary, so nothing reaches a herdr.
## Real time is stopped while filming (Engine.time_scale 0): every frame, the
## floor's walks and every person's animation go exactly STEP further, so a
## strip shows what the office draws STEP seconds apart, whatever the frame rate.
##
## For each scenario and zoom, OUT gets <scenario>-zoom<z>/NN.png (crops around
## what walks, in window pixels) and <scenario>-zoom<z>.png (all of them in
## reading order, COLUMNS a row).
##
##   godot --path . --script tools/capture_walks.gd -- --out=<empty dir> --work=<short tmp dir>

const STEP := 0.25
## The step of the strips of the shortest walks, the legs in and out of a seat.
const FINE_STEP := 0.0625
const ZOOMS: Array[int] = [2, 4]
## The window each zoom is filmed in.
const WINDOWS: Dictionary[int, Vector2i] = {2: Vector2i(1920, 960), 4: Vector2i(1920, 1280)}
const COLUMNS := 4
## Room around what walks, in world units: heads are 46 above the feet.
const MARGIN := Vector2(40, 64)
## Gaps between the frames of a sheet, in pixels.
const GAP := 6
const LONGEST := 40

var _out := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	if not args.has("out") or not args.has("work"):
		print("WALK_STRIPS_ERROR: use make walk-strips OUT=<dir>")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("WALK_STRIPS_ERROR: a headless run draws nothing")
		quit(2)
		return
	_out = args.out
	# Nothing here may reach the user's herdr, machines or forwards.
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("strip-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("WALK_STRIPS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	# The seat strips are about seats: every agent on api works unless a strip
	# says otherwise (api:p2 is idle in the shared fixture, and it would rest in
	# the pantry; an agent given to api:p3 would too).
	fixture = _with(_with(fixture, "api:p2", {"agent_status": "working"}), "api:p3", {"agent_status": "working"})
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	for zoom in ZOOMS:
		# The last strip's office is only queued for deletion, still connected to
		# the window's size_changed: let it go before the resize, or it hears it
		# with no window left (the same wait _strip_office makes between strips).
		await _frames(2)
		root.size = WINDOWS[zoom]
		await _frames(3)
		await _arrival_to_a_far_seat(zoom)
		await _arrival_to_a_near_seat(zoom)
		await _departure_from_a_near_seat(zoom)
		await _leaving_and_taking_the_seat(zoom)
		await _two_crossing_near_a_table(zoom)
		await _seat_move_after_a_table_grows(zoom)
		await _blocked_raises_a_hand(zoom)
		await _idle_to_the_pantry(zoom)
		await _idle_from_a_done_seat(zoom)
	Engine.time_scale = 1.0
	print("WALK_STRIPS_OK: " + _out)
	quit(0)


# --- scenarios --------------------------------------------------------------------


## api:p2 (far, column 1) had no agent when the floor was drawn; codex comes.
func _arrival_to_a_far_seat(zoom: int) -> void:
	var office := await _strip_office(zoom, _with(fixture, "api:p2", {"agent": null}))
	_feed(office, fixture)
	await _film(office, "arrival-far", zoom)
	_done(office)


## api:p3 (near, column 1) is a shell when the floor is drawn; pi comes. The
## near leg goes round the chair: along the lane to the standing spot's column,
## up to the spot, a sidestep into the seat.
func _arrival_to_a_near_seat(zoom: int) -> void:
	var office := await _strip_office(zoom, fixture)
	_feed(office, _both_sides())
	await _film(office, "arrival-near", zoom)
	_done(office)


## api:p3 (near, column 1) works for pi; the pane closes. Out by the same leg:
## a sidestep to the spot, down its column, along the lane.
func _departure_from_a_near_seat(zoom: int) -> void:
	var office := await _strip_office(zoom, _both_sides())
	_feed(office, _without_pane(_both_sides(), "api:p3"))
	await _film(office, "departure-near", zoom)
	_done(office)


## api:p1 (far) and api:p3 (near) go idle, out of their seats by the seat legs
## (the near one round its chair) to the pantry, and back to work: twice, the
## second time a frame every FINE_STEP, for the short legs at the seats.
func _leaving_and_taking_the_seat(zoom: int) -> void:
	var both := _both_sides()
	var office := await _strip_office(zoom, both)
	var idle := _with(_with(both, "api:p1", {"agent_status": "idle"}), "api:p3", {"agent_status": "idle"})
	for step: float in [STEP, FINE_STEP]:
		var suffix := "" if step == STEP else "-fine"
		_feed(office, idle)
		await _film(office, "leaving-seat" + suffix, zoom, step)
		_feed(office, both)
		await _film(office, "taking-seat" + suffix, zoom, step)
	_done(office)


## One worker leaves api:t1's near side while another comes to it: they pass
## each other on the lane in front of the table.
func _two_crossing_near_a_table(zoom: int) -> void:
	var office := await _strip_office(zoom, _both_sides())
	var next := _without_pane(_both_sides(), "api:p3")
	var source: Dictionary = _list(next, "panes")[0]
	var extra := source.duplicate(true)
	extra.pane_id = "api:p5"
	extra.terminal_id = "term-api-p5"
	extra.agent = "codex"
	_list(next, "panes").append(extra)
	_feed(office, next)
	await _film(office, "crossing", zoom, STEP, "api:p5")
	_done(office)


## Two tables share a row on a floor laid out wide; api:t1 grows by three
## agents, no longer fits beside api:t2 and moves: its workers walk to their new
## seats while the new ones walk in.
func _seat_move_after_a_table_grows(zoom: int) -> void:
	var office := await _strip_office(zoom, fixture, Vector2(1600, 480))
	var grown: Dictionary = fixture.duplicate(true)
	var first: Dictionary = _list(grown, "panes")[0]
	for index in 3:
		var extra := first.duplicate(true)
		extra.pane_id = "api:grow-%d" % index
		extra.terminal_id = "term-grow-%d" % index
		_list(grown, "panes").append(extra)
	_feed(office, grown)
	await _film(office, "seat-move", zoom, STEP, "api:p2")
	_done(office)


## api:p2 goes blocked at work: nobody walks. The hand goes up at the desk and
## the bubble shows over the head at once (on this read-only office it says
## `read-only`); a few frames of the raised hand, STEP apart.
func _blocked_raises_a_hand(zoom: int) -> void:
	var office := await _strip_office(zoom, fixture)
	_feed(office, _with(fixture, "api:p2", {"agent_status": "blocked"}))
	await _still(office, "blocked-at-desk", zoom, "api:p2", 4)
	_done(office)


## api:p2 goes idle: out to the walking lane, along it to the pantry at the
## band's left end, up to a spot there, and a cup.
func _idle_to_the_pantry(zoom: int) -> void:
	var office := await _strip_office(zoom, fixture)
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle"}))
	await _film(office, "idle-to-pantry", zoom, STEP, "api:p2")
	_done(office)


## api:p2 is done, sitting with its paper, and goes idle: the paper goes at
## once and they walk from the seat to the pantry.
func _idle_from_a_done_seat(zoom: int) -> void:
	var done := _with(fixture, "api:p2", {"agent_status": "done"})
	var office := await _strip_office(zoom, done)
	_feed(office, _with(done, "api:p2", {"agent_status": "idle"}))
	await _film(office, "idle-from-done-seat", zoom, STEP, "api:p2")
	_done(office)


# --- filming ----------------------------------------------------------------------


## An office in the window at `zoom`, showing `snapshot`, laid out for a view
## `plan_screen` wide when one is given (a floor's width is fixed the first time
## it is laid out) and then shown in the window's own.
func _strip_office(zoom: int, snapshot: Dictionary, plan_screen := Vector2.ZERO) -> OfficeDouble:
	Engine.time_scale = 1.0
	# The office before this one is only queued for deletion; a new zoom resizes
	# the window, and it must not hear that.
	await _frames(2)
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_args = AppArgs.parse(
		PackedStringArray(["--read-only", "--zoom=%d" % zoom, "--socket=" + args.work.path_join("nowhere.sock")])
	)
	var screen := Vector2(WINDOWS[zoom]) / float(zoom)
	office.test_screen = plan_screen if plan_screen != Vector2.ZERO else screen
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	# The strip steps the walks itself.
	office.set_process(false)
	_feed(office, snapshot)
	office.test_screen = screen
	office.refresh()
	await _frames(3)
	return office


## Every `step` seconds of the walks under way, a crop around them, until
## everyone has arrived; the frames and their sheet go to OUT. The crop is the
## whole scene (every route) when the view holds it, the camera still; in a view
## too small for it, a crop as large as the view follows the walkers.
func _film(office: OfficeDouble, scenario: String, zoom: int, step := STEP, lead := "") -> void:
	Engine.time_scale = 0.0
	var presentation := office.floor_view.presentation
	var scene := _area(office)
	var size := scene.size.min(office.camera.free_rect().size - Vector2(8, 8))
	var focus := scene.get_center()
	var dir := _out.path_join("%s-zoom%d" % [scenario, zoom])
	DirAccess.make_dir_recursive_absolute(dir)
	var frames: Array[Image] = []
	for index in LONGEST:
		if not presentation.walkers().is_empty():
			focus = _centre_of(office, lead)
		var area := Rect2((focus - size / 2.0).clamp(scene.position, scene.end - size), size)
		office.camera.reveal(_in_world(office, area))
		await _frames(2)
		await RenderingServer.frame_post_draw
		var shot := _crop(office, area, zoom)
		shot.save_png(dir.path_join("%02d.png" % index))
		frames.append(shot)
		if presentation.walkers().is_empty():
			break
		office.floor_view.walk(step)
		for person: PixelPerson in get_nodes_in_group("office_actors"):
			if office.world.is_ancestor_of(person):
				var player: AnimationPlayer = person.get_node("AnimationPlayer")
				player.advance(step)
	_sheet(frames).save_png(_out.path_join("%s-zoom%d.png" % [scenario, zoom]))
	print("WALK_STRIP: %s zoom %d, %d frames" % [scenario, zoom, frames.size()])
	Engine.time_scale = 1.0


## `count` frames STEP apart of the seat of pane `lead`, nobody walking: its
## seat, its labels and its bubble, the camera still; the frames and their
## sheet go to OUT like a walk's.
func _still(office: OfficeDouble, scenario: String, zoom: int, lead: String, count: int) -> void:
	Engine.time_scale = 0.0
	var station := office.floor_view.seat(HerdrFleet.pane_key(LOCAL, lead)).node
	var sorted := office.floor_view.sorted
	var box := station.target_rect().merge(station.bubble_rect())
	var area := Rect2(sorted.to_local(box.position), box.size).grow_individual(MARGIN.x, MARGIN.x, MARGIN.x, MARGIN.x)
	var dir := _out.path_join("%s-zoom%d" % [scenario, zoom])
	DirAccess.make_dir_recursive_absolute(dir)
	var frames: Array[Image] = []
	for index in count:
		office.camera.reveal(_in_world(office, area))
		await _frames(2)
		await RenderingServer.frame_post_draw
		var shot := _crop(office, area, zoom)
		shot.save_png(dir.path_join("%02d.png" % index))
		frames.append(shot)
		for person: PixelPerson in get_nodes_in_group("office_actors"):
			if office.world.is_ancestor_of(person):
				var player: AnimationPlayer = person.get_node("AnimationPlayer")
				player.advance(STEP)
	_sheet(frames).save_png(_out.path_join("%s-zoom%d.png" % [scenario, zoom]))
	print("WALK_STRIP: %s zoom %d, %d frames" % [scenario, zoom, frames.size()])
	Engine.time_scale = 1.0


## Where the walkers are, on average, in the floor's coordinates, heads
## included; only the worker of pane `lead` while they walk, when one is named.
func _centre_of(office: OfficeDouble, lead: String) -> Vector2:
	var walkers := office.floor_view.presentation.walkers()
	var seat := office.floor_view.seat(HerdrFleet.pane_key(LOCAL, lead)) if not lead.is_empty() else null
	if seat != null and seat.node.actor() != null and walkers.has(seat.node.actor()):
		walkers = [seat.node.actor()]
	var sum := Vector2.ZERO
	for body in walkers:
		sum += office.floor_view.sorted.to_local(body.global_position)
	return sum / float(walkers.size()) - Vector2(0, MARGIN.y / 2.0)


## What the walks under way cover, in the floor's coordinates: every route and
## every walker, with room for their heads.
func _area(office: OfficeDouble) -> Rect2:
	var presentation := office.floor_view.presentation
	var area := Rect2()
	for body in presentation.walkers():
		for point in presentation.route_of(body):
			area = (
				Rect2(point, Vector2.ZERO)
				if area.size == Vector2.ZERO and area.position == Vector2.ZERO
				else area.expand(point)
			)
		area = area.expand(office.floor_view.sorted.to_local(body.global_position))
	return area.grow_individual(MARGIN.x, MARGIN.y, MARGIN.x, MARGIN.x)


## `area` of the floor in the world's own coordinates, for the camera.
func _in_world(office: OfficeDouble, area: Rect2) -> Rect2:
	var top := office.world.to_local(office.floor_view.sorted.to_global(area.position))
	return Rect2(top, area.size)


## The window's picture of `area` of the floor, at `zoom` pixels a unit.
func _crop(office: OfficeDouble, area: Rect2, zoom: int) -> Image:
	var image := root.get_texture().get_image()
	var canvas := office.floor_view.sorted.get_global_transform_with_canvas()
	var top := canvas * area.position * float(zoom)
	var bottom := canvas * area.end * float(zoom)
	var pixels := Rect2i(Vector2i(top.floor()), Vector2i((bottom - top).ceil()))
	pixels = pixels.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(pixels)


## `frames` in reading order, COLUMNS a row, GAP apart on a dark ground.
func _sheet(frames: Array[Image]) -> Image:
	var cell := Vector2i.ZERO
	for frame in frames:
		cell = cell.max(frame.get_size())
	var rows := ceili(frames.size() / float(COLUMNS))
	var size := Vector2i(COLUMNS * (cell.x + GAP) + GAP, rows * (cell.y + GAP) + GAP)
	var sheet := Image.create_empty(size.x, size.y, false, frames[0].get_format())
	sheet.fill(Color(0.1, 0.1, 0.12))
	for index in frames.size():
		var at := Vector2i(
			GAP + (index % COLUMNS) * (cell.x + GAP), GAP + floori(index / float(COLUMNS)) * (cell.y + GAP)
		)
		sheet.blit_rect(frames[index], Rect2i(Vector2i.ZERO, frames[index].get_size()), at)
	return sheet


func _without_pane(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result
