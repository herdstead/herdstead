extends "res://tools/office_test_base.gd"
## Framed pictures on the top wall: furnishing hung in every second gap
## between two windows, clear of the windows, the lift door and the pantry,
## drawn in the shell, and moved only by the map's geometry. Pure plans and
## bare map views first, then the live office (office_test_base), which is why
## the suite runs --read-only with its own --socket and --work.

## The widths a floor is first planned at in the shipped windows, narrowest to
## widest (the layout suite's FURNISHED_WIDTHS).
const WIDTHS: Array[int] = [11, 20, 32, 60]
## Where the cream of the top wall's face starts and ends, from the map's top
## (the cap's ink, wood and plaster above it, the skirting below: the wall tiles).
const FACE_TOP := 12.0
const FACE_FOOT := 57.0

var people: PixelPeople
var art: ArtPack
var pen: OfficeDraw
var world: Node2D


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket", "work"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s= (use tools/run_tests.sh)" % name)
			quit(2)
			return
	# Nothing here may reach the user's herdr, machines or forwards.
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("frames-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	people = PixelPeople.from_manifest(PixelPeople.MANIFEST)
	art = ArtPack.from_manifest("res://assets/daylight/manifest.json")
	if art == null:
		print("TEST_HARNESS_ERROR: office frames has no art pack")
		quit(2)
		return
	pen = OfficeDraw.new(art)
	await run_cases()


func _marker() -> String:
	return "OFFICE FRAMES TESTS"


func _after_case() -> void:
	if is_instance_valid(world):
		world.free()
	super()


func _pane(key: String, x := -1, side := "far", order := -1) -> PaneModel:
	var pane := PaneModel.new()
	pane.key = key
	pane.pane_id = key
	pane.explicit_layout = x >= 0
	pane.table_x = x
	pane.side = side
	pane.layout_order = order
	return pane


func _room(key: String, count := 0, number := 0, label := "") -> RoomModel:
	var room := RoomModel.new()
	room.key = key
	room.tab_id = key
	room.number = number
	room.label = label
	for index in count:
		room.panes.append(_pane("%s-%03d" % [key, index]))
	return room


func _floor(rooms: Array[RoomModel]) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = "machine/workspace"
	floor_model.rooms = rooms
	return floor_model


## The floor of tools/gen_stress_fixture.py's snapshot_stress80: ten tabs of
## eight agents, two to a column, far and near.
func _stress_floor() -> ZoneModel:
	var rooms: Array[RoomModel] = []
	for tab in 10:
		var room := _room("stress-%d" % tab, 0, tab + 1)
		for index in 8:
			var side := "far" if index % 2 == 0 else "near"
			room.panes.append(_pane("stress-%d-p%d" % [tab, index], floori(index / 2.0), side, index))
		rooms.append(room)
	return _floor(rooms)


func _rules(width: int) -> FloorLayoutPolicy:
	var rules := FloorLayoutPolicy.new()
	rules.width_cells = width
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(people)
	return rules


## `floor_model` planned `width` cells wide with its counters and, `furnished`,
## its standing pieces, as the office plans it; `previous` is the plan it grows from.
func _planned(floor_model: ZoneModel, width: int, previous: FloorPlan = null, furnished := true) -> FloorPlan:
	var decor := OfficeDecorPlanner.new(pen) if furnished else null
	var result := OfficeFloorLayout.plan(
		MapModel.of(floor_model), previous, _rules(width), decor, OfficeFixturePlanner.new(pen)
	)
	_eq(result.problems, PackedStringArray(), "%d cells: a valid floor: %s" % [width, "; ".join(result.problems)])
	return result.plan


## Where the picture hung at `foot` is drawn: its whole canvas.
func _drawn(foot: Vector2) -> Rect2:
	var picture := art.prop_sprite(ArtContract.PROP_WALL_FRAME)
	return Rect2(foot - picture.pivot, Vector2(picture.size))


## Every picture of `plan` hangs centred in a gap between two neighbouring
## windows, every second gap (the second, the fourth, ...) and only those, on
## the cream of the top wall's face, off its end cells, and grown by FRAME_GAP
## it clears every window, the lift door and the pantry counter. Returns how
## many hang.
func _check_frames(plan: FloorPlan, what: String) -> int:
	var grid := float(FloorLayoutPolicy.GRID)
	var every := OfficeShell.frames(plan, pen)
	var windows := OfficeShell.window_xs(plan, pen)
	var covers := OfficeShell.wall_covers(plan, pen)
	var gaps: Array[float] = []
	for gap in range(1, windows.size() - 1, 2):
		gaps.append((windows[gap] + windows[gap + 1]) / 2.0)
	for foot in every:
		_check(foot.x in gaps, "%s: %s hangs centred in a second gap between windows: %s" % [what, foot, gaps])
		_eq(foot.y, OfficeShell.FRAME_FOOT, "%s: at the frame's foot" % what)
		var drawn := _drawn(foot)
		_check(
			drawn.position.y >= FACE_TOP and drawn.end.y <= FACE_FOOT,
			"%s: the picture at %s hangs on the cream face: %s" % [what, foot, drawn]
		)
		var near := drawn.grow(OfficeShell.FRAME_GAP)
		_check(
			near.position.x >= grid and near.end.x <= float(plan.floor_cells.size.x - 1) * grid,
			"%s: %s keeps off the wall's ends" % [what, foot]
		)
		for cover in covers:
			_check(not near.intersects(cover), "%s: %s clears %s" % [what, foot, cover])
	for x in gaps:
		var near := _drawn(Vector2(x, OfficeShell.FRAME_FOOT)).grow(OfficeShell.FRAME_GAP)
		var clear := true
		for cover in covers:
			clear = clear and not near.intersects(cover)
		_eq(
			Vector2(x, OfficeShell.FRAME_FOOT) in every,
			clear,
			"%s: the gap at %d hangs one exactly when it is clear" % [what, x]
		)
	return every.size()


## Pictures hang on the top wall at every shipped width and on the stress map,
## each centred in a second gap between two windows, on the cream face, off the
## end cells, and never within FRAME_GAP of a window, the lift door or the
## pantry. 13 cells (the narrowest map) has two windows, one gap: no second
## gap, so its wall hangs none.
func test_frames_hang_between_the_windows_clear_of_the_door_and_the_pantry() -> void:
	var cases: Array[Array] = []
	for width in WIDTHS:
		cases.append(["one table", _floor([_room("a", 2)]), width])
	cases.append(["three tables", _floor([_room("a", 4), _room("b", 2, 1), _room("c", 6, 2)]), 32])
	cases.append(["stress", _stress_floor(), 20])
	cases.append(["stress", _stress_floor(), 32])
	cases.append(["empty", _floor([]), 32])
	var hung_wide := 0
	for each in cases:
		var what: String = each[0]
		var model: ZoneModel = each[1]
		var width: int = each[2]
		var plan := _planned(model, width)
		if plan == null:
			continue
		var label := "%s, %d cells asked, %d wide" % [what, width, plan.floor_cells.size.x]
		var count := _check_frames(plan, label)
		print("FRAMES %s: %d %s" % [label, count, OfficeShell.frames(plan, pen)])
		if plan.floor_cells.size.x >= 23:
			_check(count > 0, "%s: the top wall hangs a picture" % label)
			hung_wide += count
	_check(hung_wide > 0, "the wide maps hang pictures: %d" % hung_wide)


## The same plan hangs the same pictures however often it is asked and in
## either pack, and a floor whose agents are blocked, done, focused or named
## otherwise, planned from the same geometry, hangs them in the same places:
## nothing about herdr reaches them (VISUAL_LANGUAGE rule 1).
func test_the_same_plan_hangs_the_same_frames_whatever_herdr_says() -> void:
	var quiet := _floor([_room("a", 3), _room("b", 2, 1)])
	var busy := _floor([_room("a", 3), _room("b", 2, 1)])
	var states: Array[String] = ["blocked", "done", "working", "idle", "unknown"]
	var index := 0
	for room in busy.rooms:
		room.label = "busy tab %d" % index
		room.active = RoomModel.Active.NO if index == 0 else RoomModel.Active.YES
		for pane in room.panes:
			pane.state = states[index % states.size()]
			pane.focused = index == 1
			pane.agent_name = "agent-%d" % index
			pane.provider = "claude"
			index += 1
	var second_pen := OfficeDraw.new(ArtPack.from_manifest(_second_pack()))
	var hung := 0
	for width: int in [20, 32, 60]:
		var plan := _planned(quiet, width)
		var other := _planned(busy, width)
		if plan == null or other == null:
			continue
		var frames := OfficeShell.frames(plan, pen)
		hung += frames.size()
		_eq(OfficeShell.frames(plan, pen), frames, "%d cells: asked again, the same pictures" % width)
		_eq(OfficeShell.frames(plan, second_pen), frames, "%d cells: in another pack too" % width)
		_eq(OfficeShell.frames(other, pen), frames, "%d cells: herdr's states and focus move none" % width)
	_check(hung > 0, "the floors hang pictures: %d" % hung)


## The feet of the pictures drawn in `view`'s shell, in the order drawn, each
## checked to be the pack's picture on the ground, not a standing piece.
func _hung(view: OfficeFloorView) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var shell := view.ground.get_node_or_null("Shell")
	if shell == null:
		return found
	var texture := art.sprite_texture(art.prop_sprite(ArtContract.PROP_WALL_FRAME))
	for child in shell.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture != texture:
			continue
		_check(sprite.name.begins_with("WallFrame"), "a picture is named as one: %s" % sprite.name)
		found.append(sprite.position)
	return found


## A floor view on its own root, for `model` planned as `plan`.
func _view(plan: FloorPlan, model: ZoneModel) -> OfficeFloorView:
	if not is_instance_valid(world):
		world = Node2D.new()
		root.add_child(world)
	var floor_root := Node2D.new()
	world.add_child(floor_root)
	var view := OfficeFloorView.new()
	view.setup(pen, floor_root)
	view.reconcile(plan, MapModel.of(model))
	return view


## The map draws exactly the planned pictures, in its shell on the ground and
## nowhere in the sorted root, and none within FRAME_GAP of a window or the
## lift door as they are drawn, at the shipped widths.
func test_the_floor_draws_the_planned_frames_clear_of_the_windows() -> void:
	var drawn_any := 0
	for width: int in [32, 60]:
		var model := _floor([_room("a", 2), _room("b", 2, 1)])
		var plan := _planned(model, width)
		if plan == null:
			continue
		var view := _view(plan, model)
		await process_frame
		var hung := _hung(view)
		_eq(hung, OfficeShell.frames(plan, pen), "%d cells: the shell draws exactly the planned pictures" % width)
		drawn_any += hung.size()
		var texture := art.sprite_texture(art.prop_sprite(ArtContract.PROP_WALL_FRAME))
		for node: Node in view.sorted.find_children("*", "Sprite2D", true, false):
			_check((node as Sprite2D).texture != texture, "%d cells: no picture stands in the sorted root" % width)
		var covers: Array[Rect2] = []
		var shell := view.ground.get_node("Shell")
		for child in shell.get_children():
			var sprite := child as Sprite2D
			if sprite != null and sprite.texture != texture:
				covers.append(sprite.transform * sprite.get_rect())
		_check(covers.size() >= 1 + view.windows().size(), "%d cells: the door and every window are drawn" % width)
		for foot in hung:
			var near := _drawn(foot).grow(OfficeShell.FRAME_GAP)
			for cover in covers:
				_check(not near.intersects(cover), "%d cells: the picture at %s clears %s" % [width, foot, cover])
	_check(drawn_any > 0, "the maps hang pictures: %d" % drawn_any)


## Only the map's geometry moves a picture: a zone growing down, the map as
## wide as it was, moves none and draws no new shell pictures; the map
## widening (the lift door moves right, the windows centre again between the
## pantry and it) moves them, and the map updated in place draws the new
## plan's pictures, not the old ones.
func test_a_widened_map_moves_the_frames_with_its_door() -> void:
	var width := 32
	var first_model := _floor([_room("a", 2)])
	var first := _planned(first_model, width, null, false)
	# A twelve-pane pod (7 cells) cannot share a's pod row: a new row.
	var taller_model := _floor([_room("a", 2), _room("b", 12, 1)])
	var taller := _planned(taller_model, width, first, false)
	var wide_model := _floor([_room("a", 2), _room("b", 12, 1), _room("c", 40, 2)])
	var wide := _planned(wide_model, width, taller, false)
	if first == null or taller == null or wide == null:
		return
	var before := OfficeShell.frames(first, pen)
	_check(taller.zones[0].cells.size.y > first.zones[0].cells.size.y, "the zone grew down")
	_eq(taller.floor_cells.size.x, first.floor_cells.size.x, "the map is as wide as it was")
	_eq(OfficeShell.frames(taller, pen), before, "so the pictures hang where they hung")
	var after := OfficeShell.frames(wide, pen)
	print("FRAMES_MOVED %s -> %s" % [before, after])
	_check(wide.lanes > taller.lanes, "a wide table widened the map: %d -> %d lanes" % [taller.lanes, wide.lanes])
	_check(before != after, "and moved the pictures: %s -> %s" % [before, after])
	_eq(wide.pantry.position, first.pantry.position, "the pantry stays")
	_check_frames(wide, "widened")
	var view := _view(first, first_model)
	await process_frame
	_eq(_hung(view), before, "the first map draws its pictures")
	view.reconcile(taller, MapModel.of(taller_model))
	await process_frame
	_eq(_hung(view), before, "a taller zone draws the same")
	view.reconcile(wide, MapModel.of(wide_model))
	await process_frame
	_eq(_hung(view), after, "updated in place, the widened map draws its own pictures")


## The framed pictures on the top wall are furniture: the shell on the
## ground hangs them and nothing that stands in the sorted root is one (that it
## draws exactly the plan's is the frames suite's), and neither a status, herdr's focus, a
## click that selects another desk nor a dropped machine draws the shell again
## or moves a picture. A dropped machine dims them with the whole floor.
func test_the_wall_frames_are_furniture() -> void:
	# Wide enough that the top wall has room for pictures between its windows.
	var office := await _live_office(fixture, Vector2(1600, 800))
	var shell := office.floor_view.ground.get_node_or_null("Shell")
	_check(shell != null, "the floor has its shell")
	if shell == null:
		_done(office)
		return
	var shell_id := shell.get_instance_id()
	var hung := _wall_frames(office)
	print("WALL_FRAMES live office 1600x800: %s" % [hung])
	_check(not hung.is_empty(), "the shown floor hangs pictures")
	var texture := office.art.sprite_texture(office.art.prop_sprite(ArtContract.PROP_WALL_FRAME))
	for node: Node in office.floor_view.sorted.find_children("*", "Sprite2D", true, false):
		_check((node as Sprite2D).texture != texture, "no picture stands in the sorted root: %s" % node.name)
	_feed(office, _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p2", {"agent_status": "done"}))
	await _frames(2)
	_feed(office, _focused_on(_with(fixture, "api:p4", {"agent_status": "idle"}), "api:p4"))
	await _frames(2)
	var other := HerdrFleet.pane_key(LOCAL, "api:p1")
	_check(office.navigator.active_key != other, "herdr's focus moved off the desk about to be clicked")
	await _click_desk(office, other)
	_eq(office.navigator.active_key, other, "the click selected another desk")
	_eq(office.floor_view.ground.get_node("Shell").get_instance_id(), shell_id, "the shell is not drawn again")
	_eq(_wall_frames(office), hung, "every picture hangs where it hung, whatever herdr says or is picked")
	_set_online(office, false)
	await _frames(2)
	_eq(office.floor_view.ground.get_node("Shell").get_instance_id(), shell_id, "a dropped machine redraws no shell")
	_eq(_wall_frames(office), hung, "and moves no picture")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "the pictures dim with the whole floor")
	_done(office)


## The feet of the framed pictures drawn in the shown floor's shell, as drawn.
func _wall_frames(office: OfficeDouble) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var shell := office.floor_view.ground.get_node_or_null("Shell")
	if shell == null:
		return found
	var texture := office.art.sprite_texture(office.art.prop_sprite(ArtContract.PROP_WALL_FRAME))
	for child in shell.get_children():
		var sprite := child as Sprite2D
		if sprite != null and sprite.texture == texture:
			found.append(sprite.position)
	return found
