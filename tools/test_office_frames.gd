extends "res://tools/office_test_base.gd"
## Framed pictures on the row walls: furnishing hung on a grid of the
## wall, clear of every sign, title, table and standing piece, drawn in the
## shell, and moved only by the floor's geometry. Pure plans and bare floor
## views first, then the live office (office_test_base), which is why the suite
## runs --read-only with its own --socket and --work.

## The widths a floor is first planned at in the shipped windows, narrowest to
## widest (the layout suite's FURNISHED_WIDTHS).
const WIDTHS: Array[int] = [11, 20, 32, 60]
## Where the cream of a row wall's face starts and ends, from the row's top
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
	var result := OfficeFloorLayout.plan(floor_model, previous, _rules(width), decor, OfficeFixturePlanner.new(pen))
	_eq(result.problems, PackedStringArray(), "%d cells: a valid floor: %s" % [width, "; ".join(result.problems)])
	return result.plan


## Where the picture hung at `foot` is drawn: its whole canvas.
func _drawn(foot: Vector2) -> Rect2:
	var picture := art.prop_sprite(ArtContract.PROP_WALL_FRAME)
	return Rect2(foot - picture.pivot, Vector2(picture.size))


## Whether a picture drawn over `near` (already grown by FRAME_GAP) is clear on
## `row`'s wall: off its end cells, and away from every sign, title and table of
## the row and every standing piece and counter of the floor.
func _clear_at(plan: FloorPlan, row: RowPlan, near: Rect2) -> bool:
	var grid := float(FloorLayoutPolicy.GRID)
	var wall_y := float(row.wall_cells.position.y) * grid
	if near.position.x < float(row.wall_cells.position.x + 1) * grid:
		return false
	if near.end.x > float(row.wall_cells.end.x - 1) * grid:
		return false
	for desk in row.desks:
		var table := desk.measure.render_rect
		table.position += desk.origin
		if near.intersects(OfficeShell.wall_display_bounds(desk, wall_y, pen)) or near.intersects(table):
			return false
	for placed in plan.decorations:
		if near.intersects(placed.draw_rect):
			return false
	for counter in plan.fixtures():
		if near.intersects(counter.draw_rect):
			return false
	return true


## Every picture of `plan` hangs on the wall's grid, one to a bay at most, in
## the bay's second place only when its start is taken, at the foot of the row
## it is on, on the cream of that row's face and off its end cells, and grown by
## FRAME_GAP it clears every sign, title and table of the row and every standing
## piece and counter of the floor. Returns the number hung on each row.
func _check_frames(plan: FloorPlan, what: String) -> Array[int]:
	var counts: Array[int] = []
	var grid := float(FloorLayoutPolicy.GRID)
	var first := OfficeShell.FRAME_FROM
	var every := OfficeShell.frames(plan, pen)
	var hung := 0
	for row in plan.rows:
		var xs := OfficeShell.frame_xs(plan, row, pen)
		counts.append(xs.size())
		var wall_y := float(row.wall_cells.position.y) * grid
		var bays: Dictionary[float, bool] = {}
		for x in xs:
			var foot := Vector2(x, wall_y + OfficeShell.FRAME_FOOT)
			_check(foot in every, "%s: frames() carries row %d's %s" % [what, row.index, foot])
			hung += 1
			# A bay's start or its second place, and one picture to a bay at most.
			var bay := floorf((x - first) / OfficeShell.FRAME_PITCH)
			var into := x - first - bay * OfficeShell.FRAME_PITCH
			_check(
				bay >= 0.0 and (is_zero_approx(into) or is_equal_approx(into, OfficeShell.FRAME_SECOND)),
				"%s: %d is a place of the grid" % [what, x]
			)
			_check(not bays.has(bay), "%s: row %d hangs one picture in bay %d at most" % [what, row.index, bay])
			bays[bay] = true
			if not is_zero_approx(into):
				var start := Vector2(x - OfficeShell.FRAME_SECOND, wall_y + OfficeShell.FRAME_FOOT)
				_check(
					not _clear_at(plan, row, _drawn(start).grow(OfficeShell.FRAME_GAP)),
					"%s: %d hangs in the bay's second place only because its start is taken" % [what, x]
				)
			var drawn := _drawn(foot)
			_check(
				drawn.position.y >= wall_y + FACE_TOP and drawn.end.y <= wall_y + FACE_FOOT,
				"%s: row %d's picture at %d hangs on the cream face: %s" % [what, row.index, x, drawn]
			)
			var near := drawn.grow(OfficeShell.FRAME_GAP)
			_check(
				near.position.x >= float(row.wall_cells.position.x + 1) * grid,
				"%s: %d keeps off the tee at the left wall" % [what, x]
			)
			_check(
				near.end.x <= float(row.wall_cells.end.x - 1) * grid, "%s: %d keeps off the row wall's end" % [what, x]
			)
			for desk in row.desks:
				var shown := OfficeShell.wall_display_bounds(desk, wall_y, pen)
				_check(
					not near.intersects(shown), "%s: %d clears %s's sign and title %s" % [what, x, desk.tab_key, shown]
				)
				var table := desk.measure.render_rect
				table.position += desk.origin
				_check(not near.intersects(table), "%s: %d clears %s's table" % [what, x, desk.tab_key])
			for placed in plan.decorations:
				_check(not near.intersects(placed.draw_rect), "%s: %d clears %s" % [what, x, placed.key])
			for counter in plan.fixtures():
				_check(not near.intersects(counter.draw_rect), "%s: %d clears the %s" % [what, x, counter.key])
	_eq(every.size(), hung, "%s: frames() is every row's frame_xs() and nothing else" % what)
	return counts


## Pictures hang on every row wall that has room at every shipped width and on
## the stress floor, each on the wall's grid, on the cream face, off the end
## cells, and never within FRAME_GAP of a sign, a title (long ones included), a
## table, a standing piece (the cabinet and the plants reach up the wall) or a
## counter. 11 cells is the exception the geometry leaves: its table's sign sits
## over the only places, so its wall stays bare, as its wall-foot run does.
func test_frames_hang_on_the_wall_grid_clear_of_signs_and_pieces() -> void:
	var cases: Array[Array] = []
	for width in WIDTHS:
		cases.append(["one table", _floor([_room("a", 2)]), width])
	var titled: Array[RoomModel] = []
	for index in 3:
		titled.append(_room("tab-%d" % index, 2, index, "MMMMMMMMMMMMMMMMMMMMMMMM"))
	for width: int in [20, 32, 60]:
		cases.append(["three long titles", _floor(titled), width])
	cases.append(["three tables", _floor([_room("a", 4), _room("b", 2, 1), _room("c", 6, 2)]), 32])
	cases.append(["stress", _stress_floor(), 20])
	cases.append(["stress", _stress_floor(), 32])
	var stress_hung := 0
	for each in cases:
		var what: String = each[0]
		var model: ZoneModel = each[1]
		var width: int = each[2]
		var plan := _planned(model, width)
		if plan == null:
			continue
		var label := "%s, %d cells" % [what, width]
		var counts := _check_frames(plan, label)
		print("FRAMES_PER_ROW %s: %s" % [label, counts])
		for count in counts:
			if what == "one table" and width > 11:
				_check(count > 0, "%s: every row hangs a picture: %s" % [label, counts])
			if what == "stress":
				stress_hung += count
	_check(stress_hung > 0, "the stress floor hangs pictures somewhere: %d" % stress_hung)


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


## The floor draws exactly the planned pictures, in its shell on the ground and
## nowhere in the sorted root, and none within FRAME_GAP of a sign or title as
## they are drawn, the real font-sized label included: long titles, several
## tables to a row, at the shipped widths.
func test_the_floor_draws_the_planned_frames_clear_of_the_drawn_signs() -> void:
	var drawn_any := 0
	for width: int in [20, 32, 60]:
		var titled: Array[RoomModel] = []
		for index in 3:
			titled.append(_room("tab-%d" % index, 2, index, "MMMMMMMMMMMMMMMMMMMMMMMM"))
		var model := _floor(titled)
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
		var floor_root := view.root
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
		for foot in hung:
			var near := _drawn(foot).grow(OfficeShell.FRAME_GAP)
			for cover in covers:
				_check(not near.intersects(cover), "%d cells: the picture at %s clears %s" % [width, foot, cover])
	_check(drawn_any > 0, "the floors hang pictures: %d" % drawn_any)


## A table that grows moves its sign along the row wall, and the pictures move
## out of its way: the floor updated in place draws the new plan's pictures, not
## the old ones, and never one under a sign. Here nothing else of the shell moves:
## the floor stands no furniture (the planner leaves the whole batch out when it
## would close a path, OfficeFloorLayout.plan()), and the floor, its walls, its
## corridors and its counters stay as they were, so only a shell keyed on the
## pictures themselves is drawn again.
func test_a_moved_sign_moves_the_frames_out_of_its_way() -> void:
	var width := 20
	var first_model := _floor([_room("a", 5)])
	var first := _planned(first_model, width, null, false)
	# Twenty-eight panes: a fourteen-desk pod, 448 wide, whose sign (centred at
	# 256) reaches the first bay's picture at 312; nine panes no longer do, now
	# that a desk is 32 wide.
	var grown_model := _floor([_room("a", 28)])
	var grown := _planned(grown_model, width, first, false)
	if first == null or grown == null:
		return
	var before := OfficeShell.frames(first, pen)
	var after := OfficeShell.frames(grown, pen)
	print("FRAMES_MOVED %s -> %s" % [before, after])
	_check(before != after, "growing table a moves the pictures: %s -> %s" % [before, after])
	_check(first.decorations.is_empty() and grown.decorations.is_empty(), "the floor stands no furniture")
	_eq(grown.floor_cells, first.floor_cells, "the floor is as big as it was")
	_eq(grown.corridors, first.corridors, "its corridors are where they were")
	_eq(grown.rows.size(), first.rows.size(), "it has the rows it had")
	for index in first.rows.size():
		_eq(grown.rows[index].wall_cells, first.rows[index].wall_cells, "row %d's wall is where it was" % index)
	var counters := func(plan: FloorPlan) -> Array:
		return plan.fixtures().map(func(each: FixturePlacement) -> String: return each.geometry_signature())
	_eq(counters.call(grown), counters.call(first), "and so are its counters")
	_check_frames(grown, "grown")
	var view := _view(first, first_model)
	await process_frame
	_eq(_hung(view), before, "the first floor draws its pictures")
	view.reconcile(grown, MapModel.of(grown_model))
	await process_frame
	_eq(_hung(view), after, "updated in place, the floor draws the grown plan's pictures")
	var grid := float(FloorLayoutPolicy.GRID)
	for foot in _hung(view):
		for desk in grown.desks:
			var wall_y := float(grown.rows[desk.row].wall_cells.position.y) * grid
			_check(
				not _drawn(foot).intersects(OfficeShell.wall_display_bounds(desk, wall_y, pen)),
				"the picture at %s is not under %s's sign" % [foot, desk.tab_key]
			)


## The framed pictures on the row walls are furniture: the shell on the
## ground hangs them and nothing that stands in the sorted root is one (that it
## draws exactly the plan's is the frames suite's), and neither a status, herdr's focus, a
## click that selects another desk nor a dropped machine draws the shell again
## or moves a picture. A dropped machine dims them with the whole floor.
func test_the_wall_frames_are_furniture() -> void:
	# Wide enough that the row wall has room beside its two signs.
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
