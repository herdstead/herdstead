extends "res://tools/office_test_base.gd"
## Structural changes preserve unrelated world objects and their positions.


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket", "work"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s=" % name)
			quit(2)
			return
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("reconcile-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	# These cases are about seats: every agent on api works (api:p2 is idle in
	# the shared fixture, and an agent given to api:p3 would be too), so nobody
	# rests in the pantry or the queue unless a case says so.
	fixture = _with(_with(fixture, "api:p2", {"agent_status": "working"}), "api:p3", {"agent_status": "working"})
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "RECONCILE TESTS"


## The stack of paper on `station`'s side of its table (a done agent's).
static func _papers(station: OfficeStation) -> Sprite2D:
	return station.table.papers(station.column, station.side)


func _seat_node(office: OfficeScene, pane_id: String) -> OfficeStation:
	var key := HerdrFleet.pane_key(LOCAL, pane_id)
	for node: Node in office.world.find_children("*", "OfficeStation", true, false):
		var station: OfficeStation = node
		if station.pane_key == key:
			return station
	return null


func test_renaming_keeps_world_and_seat() -> void:
	var office := await _live_office()
	var world_id := office.world.get_instance_id()
	var station := _seat_node(office, "api:p1")
	var seat_id := station.get_instance_id()
	var at := station.global_position
	var renamed: Dictionary = fixture.duplicate(true)
	for tab: Dictionary in _list(renamed, "tabs"):
		if tab.tab_id == "api:t1":
			tab.label = "renamed room"
	_feed(office, renamed)
	_eq(office.world.get_instance_id(), world_id, "renaming preserves the world")
	_eq(_seat_node(office, "api:p1").get_instance_id(), seat_id, "renaming preserves the seat")
	_eq(_seat_node(office, "api:p1").global_position, at, "renaming preserves its position")
	_done(office)


## A herdr client resize changes the size of every terminal rect. The size is
## the terminal monitor's grid, read from the typed snapshot, and nothing on the
## floor: no re-plan, no desk, seat, table or person node rebuilt, nobody walks.
func test_rect_sizes_rebuild_nothing() -> void:
	var office := await _live_office()
	await _frames(12)
	var world_id := office.world.get_instance_id()
	var model := office.world_model
	var attempts := office.plans.attempt_count()
	var plan := office.layout_plan().geometry_signature()
	var tables := _table_ids(office)
	var desks := _desk_ids(office, "")
	var actors := _all_actor_ids(office)
	var progress := _actor_progress(office, "")
	var looks := _desk_looks(office)
	var resized: Dictionary = fixture.duplicate(true)
	var sizes: Dictionary[String, Vector2i] = {}
	for layout: Dictionary in _list(resized, "layouts"):
		for slot: Dictionary in _list(layout, "panes"):
			var rect := _dict(slot, "rect")
			var size := Vector2i(int(_number(rect, "width")) * 2 + 3, int(_number(rect, "height")) + 7)
			rect.width = size.x
			rect.height = size.y
			sizes[str(slot.pane_id)] = size
	_check(sizes.size() >= 3, "every rect of the shown floor is resized (%d)" % sizes.size())
	_feed(office, resized)
	var read: Dictionary[String, Vector2i] = {}
	for layout in office.fleet.snapshot(LOCAL).layouts:
		for slot in layout.panes:
			read[slot.pane_id] = Vector2i(slot.width, slot.height)
	_eq(read, sizes, "the new sizes are in the typed snapshot")
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(office.world_model, model, "a rect size is not part of the layout model")
	_eq(office.plans.attempt_count(), attempts, "the floor is not planned again")
	_eq(office.layout_plan().geometry_signature(), plan, "and its plan is the same")
	_eq(_table_ids(office), tables, "every table keeps its node")
	_eq(_desk_ids(office, ""), desks, "every desk keeps every node")
	_eq(_desk_looks(office), looks, "and no desk is furnished again")
	_eq(_all_actor_ids(office), actors, "every person keeps their node")
	_eq(_actor_progress(office, ""), progress, "and their frame and progress")
	_eq(office.floor_view.presentation.walkers(), [], "nobody walks")
	await _same_as_rebuild(office, "after every rect was resized")
	_done(office)


## A real herdr client resize moves the rects as well as sizing them: every x and
## y scales with the window. The seat column is the rank of the x in its tab
## (OfficeProjection.layout_x()), so it is still nothing on the floor: no
## re-plan, no desk, seat, table or person node rebuilt, nobody walks.
func test_a_resize_that_moves_every_rect_rebuilds_nothing() -> void:
	var office := await _live_office()
	await _frames(12)
	var world_id := office.world.get_instance_id()
	var attempts := office.plans.attempt_count()
	var plan := office.layout_plan().geometry_signature()
	var tables := _table_ids(office)
	var desks := _desk_ids(office, "")
	var actors := _all_actor_ids(office)
	var progress := _actor_progress(office, "")
	var looks := _desk_looks(office)
	var resized: Dictionary = fixture.duplicate(true)
	var origins: Dictionary[String, Vector2i] = {}
	for layout: Dictionary in _list(resized, "layouts"):
		for slot: Dictionary in _list(layout, "panes"):
			var rect := _dict(slot, "rect")
			# A quarter wider and taller: every rect's origin and size scale.
			for side: String in ["x", "y", "width", "height"]:
				rect[side] = floori(_number(rect, side) * 1.25)
			origins[str(slot.pane_id)] = Vector2i(int(_number(rect, "x")), int(_number(rect, "y")))
	var moved := origins.values().filter(func(at: Vector2i) -> bool: return at != Vector2i.ZERO)
	_check(moved.size() >= 2, "rects of the shown floor really move (%d)" % moved.size())
	_feed(office, resized)
	var read: Dictionary[String, Vector2i] = {}
	for layout in office.fleet.snapshot(LOCAL).layouts:
		for slot in layout.panes:
			read[slot.pane_id] = Vector2i(slot.x, slot.y)
	_eq(read, origins, "the new origins are in the typed snapshot")
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(office.plans.attempt_count(), attempts, "the floor is not planned again")
	_eq(office.layout_plan().geometry_signature(), plan, "and its plan is the same")
	_eq(_table_ids(office), tables, "every table keeps its node")
	_eq(_desk_ids(office, ""), desks, "every desk keeps every node")
	_eq(_desk_looks(office), looks, "and no desk is furnished again")
	_eq(_all_actor_ids(office), actors, "every person keeps their node")
	_eq(_actor_progress(office, ""), progress, "and their frame and progress")
	_eq(office.floor_view.presentation.walkers(), [], "nobody walks")
	await _same_as_rebuild(office, "after every rect moved")
	_done(office)


## What each seat of the shown floor was last furnished with
## (PaneModel.desk_signature()), by pane key.
func _desk_looks(office: OfficeScene) -> Dictionary[String, String]:
	var looks: Dictionary[String, String] = {}
	for key: String in office.floor_view.seats:
		looks[key] = office.floor_view.seats[key].look
	return looks


func test_pane_growth_keeps_the_other_tab() -> void:
	var office := await _live_office()
	var station := _seat_node(office, "api:p4")
	var seat_id := station.get_instance_id()
	var actor_id := station.actor().get_instance_id()
	var at := station.global_position
	var shell := _seat_node(office, "api:p3")
	var laptop := shell.table.monitor(shell.column, shell.side)
	var prompt := laptop.texture
	_check(shell.actor() == null, "growth also exercises a shell on the changed tab")
	var grown: Dictionary = fixture.duplicate(true)
	var first: Dictionary = _list(grown, "panes")[0]
	var extra: Dictionary = first.duplicate(true)
	extra.pane_id = "api:new"
	_list(grown, "panes").append(extra)
	_feed(office, grown)
	var retained := _seat_node(office, "api:p4")
	_eq(retained.get_instance_id(), seat_id, "growth preserves the other tab's seat")
	_eq(retained.actor().get_instance_id(), actor_id, "growth preserves the other tab's actor")
	_eq(retained.global_position, at, "growth preserves the other tab's location")
	_check(_seat_node(office, "api:new") != null, "the added pane receives a seat")
	_eq(_seat_node(office, "api:p3"), shell, "changed tab retains its shell station")
	_eq(shell.table.monitor(shell.column, shell.side), laptop, "changed tab retains its shell laptop")
	_eq(laptop.texture, prompt, "occupancy reconciliation does not erase the shell prompt")
	_done(office)


func test_window_width_keeps_world_geometry() -> void:
	var office := await _live_office()
	var world_id := office.world.get_instance_id()
	var station := _seat_node(office, "api:p4")
	var seat_id := station.get_instance_id()
	var at := station.position
	office.test_screen = Vector2(1400, 480)
	_feed(office, fixture)
	_eq(office.world.get_instance_id(), world_id, "resize preserves the world")
	_eq(_seat_node(office, "api:p4").get_instance_id(), seat_id, "resize preserves the seat")
	_eq(_seat_node(office, "api:p4").position, at, "resize does not reflow desks")
	_done(office)


## Exercise the real Window signals, including odd sizes and either side of
## each fit threshold. The logical viewport must consume every window pixel,
## not a rounded rectangle that the integer stretcher centres in black bars.
func test_resizing_fills_the_window_at_zoom_boundaries() -> void:
	await process_frame
	root.size = Vector2i(1920, 960)
	var office := await _live_office()
	var world_id := office.world.get_instance_id()
	var station := _seat_node(office, "api:p4")
	var at := station.position
	# 4x needs a window that holds the smallest screen four times over.
	root.size = Vector2i(1920, 1280)
	await _frames(2)
	await _tap_key(KEY_EQUAL)
	_eq(office.zoom, 4, "real zoom input requests 4x")
	var scales: Dictionary[Vector2i, int] = {
		Vector2i(1920, 960): 2,
		Vector2i(1919, 959): 2,
		Vector2i(1921, 961): 2,
		Vector2i(1441, 961): 2,
		Vector2i(1439, 960): 2,
		Vector2i(1440, 959): 2,
		Vector2i(959, 641): 1,
		Vector2i(961, 639): 1,
		Vector2i(960, 640): 2,
		Vector2i(400, 280): 1,
		Vector2i(1920, 1280): 4,
		Vector2i(1919, 1280): 2,
	}
	for extent in scales:
		root.size = extent
		await _frames(2)
		_check_window_scale(scales[extent])
		_eq(_seat_node(office, "api:p4"), station, "resize retains the station")
		_eq(station.position, at, "resize never reflows the table")
	root.size = Vector2i(1920, 1280)
	await _frames(2)
	_check_window_scale(4)
	await _tap_key(KEY_MINUS)
	_check_window_scale(2)
	_eq(office.world.get_instance_id(), world_id, "resize and zoom retain the world")
	root.size = SCREEN
	await _frames(2)
	_done(office)


## The content scale is even from the smallest window that holds 480x320 at 2x
## up, so a density-2 texel always lands on whole screen pixels. A window too
## small for that drops to 1: below the supported size, not a zoom level.
func test_content_scale_is_even_from_the_minimum_window_up() -> void:
	# Window width, height and the wanted zoom -> the content scale.
	var cases: Dictionary[Vector3i, int] = {
		Vector3i(480, 320, 2): 1,
		Vector3i(960, 640, 8): 2,
		Vector3i(1920, 960, 8): 2,
		Vector3i(1920, 1280, 8): 4,
		Vector3i(1920, 1280, 2): 2,
		Vector3i(3840, 2160, 8): 6,
		Vector3i(3840, 2560, 8): 8,
		Vector3i(1920, 960, 3): 2,
	}
	for row in cases:
		var window := Vector2i(row.x, row.y)
		_eq(OfficeScene.content_scale_for(window, row.z), cases[row], "%s wanting zoom %d" % [window, row.z])


func _check_window_scale(expected: int) -> void:
	var label := "%s at %dx" % [root.size, expected]
	_check(
		root.get_visible_rect().size.is_equal_approx(Vector2(root.size) / float(expected)),
		label + ": logical size includes the fractional edge"
	)
	var transform := root.get_final_transform()
	_check(transform.get_scale().is_equal_approx(Vector2.ONE * expected), label + ": exact integer scale")
	_eq(transform.origin, Vector2.ZERO, label + ": no letterbox offset")


func _tile_layer(office: OfficeScene, node_name: String) -> TileMapLayer:
	var matches := office.world.find_children(node_name, "TileMapLayer", true, false)
	_eq(matches.size(), 1, "one %s layer serves the whole floor" % node_name)
	return matches[0] as TileMapLayer if matches.size() == 1 else null


func _check_floor_cells(office: OfficeScene) -> void:
	var plan := office.layout_plan()
	_check(plan != null, "rendered workspace has a public plan")
	if plan == null:
		return
	var floor_layer := _tile_layer(office, "Floor")
	var walls := _tile_layer(office, "Walls")
	if floor_layer == null or walls == null:
		return
	_eq(floor_layer.get_used_rect(), plan.floor_cells, "floor extents exactly match the planned rectangle")
	_eq(
		floor_layer.get_used_cells().size(),
		plan.floor_cells.size.x * plan.floor_cells.size.y,
		"floor has exactly one tile per planned cell"
	)
	for y in range(plan.floor_cells.position.y, plan.floor_cells.end.y):
		for x in range(plan.floor_cells.position.x, plan.floor_cells.end.x):
			var at := Vector2i(x, y)
			var data := floor_layer.get_cell_tile_data(at)
			_check(data != null, "base floor covers %s" % at)
			if data != null:
				_check(
					StringName(str(data.get_custom_data("semantic_id"))) in ArtContract.FLOOR_WOOD,
					"base coverage is wood, including below walls and walkways"
				)
	var wall_hits: Dictionary[Vector2i, int] = {}
	for node in office.world.find_children("*", "TileMapLayer", true, false):
		var layer: TileMapLayer = node
		for cell in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			if data == null or not str(data.get_custom_data("semantic_id")).begins_with("wall."):
				continue
			var floor_cell := floor_layer.local_to_map(floor_layer.to_local(layer.to_global(layer.map_to_local(cell))))
			wall_hits[floor_cell] = wall_hits.get(floor_cell, 0) + 1
			_check(layer == walls, "all wall tiles use the common Walls layer")
	for at in wall_hits:
		_eq(wall_hits[at], 1, "wall joins do not stack duplicate cells at %s" % at)
		_check(plan.floor_cells.has_point(at), "wall cell remains inside the floor")
	for corridor in plan.corridors:
		for y in range(corridor.position.y, corridor.end.y):
			for x in range(corridor.position.x, corridor.end.x):
				_check(not wall_hits.has(Vector2i(x, y)), "no entrance, main or cross corridor is filled by wall tiles")
	for row in plan.rows:
		for course in ArtContract.WALL_COURSES.size():
			var y := row.wall_cells.position.y + course
			for x in range(row.wall_cells.position.x, row.wall_cells.end.x):
				_eq(wall_hits.get(Vector2i(x, y), 0), 1, "every row wall cell is drawn once")
			var left := walls.get_cell_tile_data(Vector2i(row.wall_cells.position.x, y))
			var right := walls.get_cell_tile_data(Vector2i(row.wall_cells.end.x - 1, y))
			_check(left != null and right != null, "row wall has both junction pieces")
			if left != null and right != null:
				_eq(
					StringName(str(left.get_custom_data("semantic_id"))),
					ArtContract.wall_cell(ArtContract.WALL_COURSES[course], ArtContract.WALL_T_LEFT),
					"row joins the side through a T piece"
				)
				_eq(
					StringName(str(right.get_custom_data("semantic_id"))),
					ArtContract.wall_cell(ArtContract.WALL_COURSES[course], ArtContract.WALL_END_RIGHT),
					"row ends before the main corridor"
				)
	var tile_size := Vector2(floor_layer.tile_set.tile_size)
	var pixels := Rect2(Vector2(plan.floor_cells.position) * tile_size, Vector2(plan.floor_cells.size) * tile_size)
	var transform_to_world := office.world.global_transform.affine_inverse() * floor_layer.global_transform
	_check(
		office.world_bounds().encloses(transform_to_world * pixels),
		"public scroll bounds contain the actual rendered floor"
	)


func test_complete_floor_and_unique_wall_cells_follow_the_plan() -> void:
	# 628 wide: the floor is planned 488 units wide; its tables wrap to a
	# second row there.
	var office := await _live_office(fixture, Vector2(628, 480))
	_check(office.layout_plan().rows.size() > 1, "fixture exercises multiple wall rows")
	_check_floor_cells(office)
	var signature := office.layout_plan().geometry_signature()
	office.switch_theme(_second_pack())
	await _frames(2)
	_eq(office.layout_plan().geometry_signature(), signature, "another theme uses the same floor geometry")
	_check_floor_cells(office)
	office.rebuild_world()
	await _frames(2)
	_check_floor_cells(office)
	_done(office)


## A floor is planned for the world with the drawer closed (plan_width()),
## so a real click that opens the drawer plans nothing again and rebuilds
## nothing: it only takes the world's right edge in. The rightmost desk, which
## the open drawer now covers, is still reached: a real click on its row in
## the list picks it and the camera pans it into view (reveal()). And a click
## on the open drawer over a desk is the list's: it picks no desk.
func test_a_floor_planned_with_the_drawer_closed_keeps_its_plan_when_it_opens() -> void:
	# api with a dozen more agents: its tables reach across the whole plan.
	var grown: Dictionary = fixture.duplicate(true)
	var first: Dictionary = _list(grown, "panes")[0]
	for index in 12:
		var extra: Dictionary = first.duplicate(true)
		extra.pane_id = "api:wide-%d" % index
		_list(grown, "panes").append(extra)
	var office := await _live_office(grown)
	await _frames(4)
	var hud := office.hud
	_check(not hud.drawer_open(), "the drawer starts closed")
	_eq(
		office.layout_plan().initial_width_cells,
		floori(hud.plan_width() / FloorLayoutPolicy.GRID),
		"the floor is planned for the drawer closed"
	)
	_eq(hud.plan_width(), 660.0, "660 wide at 800x480")
	var world_id := office.world.get_instance_id()
	var attempts := office.plans.attempt_count()
	var plan := office.layout_plan().geometry_signature()
	var desks := _desk_ids(office, "")
	var rightmost: OfficeStation = null
	for station in _seats(office):
		if rightmost == null or station.target_rect().end.x > rightmost.target_rect().end.x:
			rightmost = station
	var tab: Control = hud.get_node("%DrawerTab")
	await _click(tab.get_global_rect().get_center())
	await _frames(2)
	_check(hud.drawer_open(), "a real click on the tab opens the drawer")
	_eq(office.camera.free_rect(), hud.world_rect(), "the world's room stops at the open drawer")
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(office.plans.attempt_count(), attempts, "the floor is not planned again")
	_eq(office.layout_plan().geometry_signature(), plan, "its plan is the same")
	_eq(_desk_ids(office, ""), desks, "every desk keeps every node")
	var on_screen := func(station: OfficeStation) -> Rect2:
		return Rect2(station.target_rect().position - office.camera.position, station.target_rect().size)
	var covered: Rect2 = on_screen.call(rightmost)
	_check(covered.end.x > hud.world_rect().end.x, "the open drawer covers the rightmost desk: %s" % covered)
	# Its row in the list: a real click picks it, and the camera reveals it.
	var list := hud.agent_list
	var row := list.row_for(rightmost.pane_key)
	_check(row != null, "the list has a row for it")
	if row != null:
		(list.get_node("%Scroll") as ScrollContainer).ensure_control_visible(row)
		await _frames(2)
		await _click(row.get_global_rect().get_center())
		await _frames(3)
		_eq(office.picked_key, rightmost.pane_key, "a click on its row picks it")
		var revealed: Rect2 = on_screen.call(rightmost)
		_check(
			hud.world_rect().encloses(revealed),
			"and the camera pans it into view: %s in %s" % [revealed, hud.world_rect()]
		)
	# Another pick (api:p1, by a real click on its desk), and back to the
	# floor's left edge: the desks right of the world's room are under the open
	# drawer. A click there is the list's: its row's pane, or nothing where no
	# row is; never the desk under it.
	office.camera.pan = Vector2.ZERO
	await _frames(2)
	await _click_desk(office, HerdrFleet.pane_key(LOCAL, "api:p1"))
	await _frames(2)
	_eq(office.picked_key, HerdrFleet.pane_key(LOCAL, "api:p1"), "api:p1 picked")
	(list.get_node("%Scroll") as ScrollContainer).scroll_vertical = 0
	var drawer := hud.placed(hud.right_column)
	var box := (list.get_node("%Scroll") as Control).get_global_rect()
	var under: OfficeStation = null
	var row_key := ""
	var at := Vector2.ZERO
	# At the floor's left edge, panned down as far as it takes for a desk to
	# stand under the drawer (the card leaves the drawer short of the lowest ones).
	for down: float in [0.0, 48.0, 96.0, 144.0]:
		if under != null:
			break
		office.camera.pan = Vector2(0.0, down)
		await _frames(2)
		for station in _seats(office):
			var point := station.target_rect().get_center() - office.camera.position
			if station.pane_key == office.picked_key or not drawer.has_point(point):
				continue
			var over := ""
			for key: String in list.shown_keys():
				var line := list.row_for(key)
				if line != null and box.has_point(point) and line.get_global_rect().has_point(point):
					over = key
			if over != station.pane_key:
				under = station
				row_key = over
				at = point
				break
	_check(under != null, "a desk really is under the open drawer")
	if under != null:
		var before := office.picked_key
		await _click(at)
		await _frames(2)
		_check(office.picked_key != under.pane_key, "a click on the drawer over a desk picks no desk")
		_eq(office.picked_key, before if row_key.is_empty() else row_key, "it is the list's: its row, or nothing")
		_check(not office.camera.dragging, "the office never saw the press")
	_done(office)


## On a screen tall enough the compact panel is a card at the bottom-left and
## NEXT stands at the right end; the office shows between them but takes no
## click and no wheel there (the user's choice: a dead gap). A real click on a
## desk seen through the gap picks nothing; a wheel notch there pans nothing.
func test_the_gap_between_the_card_and_next_takes_no_click() -> void:
	var office := await _live_office()
	await _frames(4)
	var hud := office.hud
	_check(hud.inspector.card(), "800x480 is tall enough for the card")
	var gap: Control = hud.inspector.get_node("%CardGap")
	_check(gap.is_visible_in_tree(), "the gap stands between the card and NEXT")
	var hole := gap.get_global_rect()
	var seen: OfficeStation = null
	var at := Vector2.ZERO
	for down: float in [0.0, 48.0, 96.0, 144.0, 192.0]:
		office.camera.pan = Vector2(0.0, down)
		await _frames(2)
		for station in _seats(office):
			var point := station.target_rect().get_center() - office.camera.position
			if hole.has_point(point) and station.pane_key != office.picked_key:
				seen = station
				at = point
				break
		if seen != null:
			break
	_check(seen != null, "a desk shows through the gap")
	if seen == null:
		_done(office)
		return
	var before := office.picked_key
	await _click(at)
	await _frames(2)
	_eq(office.picked_key, before, "a click on it through the gap picks nothing")
	_check(not office.camera.dragging, "the office never saw the press")
	var pan := office.camera.pan
	root.push_input(_mouse_button(at, MOUSE_BUTTON_WHEEL_DOWN, true), true)
	root.push_input(_mouse_button(at, MOUSE_BUTTON_WHEEL_DOWN, false), true)
	await _frames(2)
	_eq(office.camera.pan, pan, "and a wheel there pans nothing")
	_done(office)


func _shadow_holder(office: OfficeScene, table: OfficeTable) -> Node2D:
	var matches: Array[Node2D] = []
	for node in office.world.find_children("SeatContacts", "Node2D", true, false):
		var holder: Node2D = node
		if holder.global_position.is_equal_approx(table.global_position):
			matches.append(holder)
	_eq(matches.size(), 1, "one live Ground contact holder belongs to this table")
	return matches[0] if matches.size() == 1 else null


func test_capacity_growth_keeps_contact_shadows_alive_after_two_frames() -> void:
	var office := await _live_office()
	var station := _seat_node(office, "api:p1")
	var table := station.table
	var previous_columns := table.columns.size()
	var original := _shadow_holder(office, table)
	var grown: Dictionary = fixture.duplicate(true)
	var first: Dictionary = _list(grown, "panes")[0]
	for index in 5:
		var extra: Dictionary = first.duplicate(true)
		extra.pane_id = "api:contact-%d" % index
		_list(grown, "panes").append(extra)
	_feed(office, grown)
	await _frames(2)
	_check(table.columns.size() > previous_columns, "fixture really expands table capacity")
	_check(is_instance_valid(original), "the original contact holder survives deferred deletion")
	var retained := _shadow_holder(office, table)
	if retained != null:
		_eq(retained, original, "background replacement moves the owned holder")
		_check(not retained.is_queued_for_deletion(), "reattached contact holder is not queued to die")
		_eq(retained.get_child_count(), table.columns.size(), "one near-chair contact per capacity column")
		for index in table.columns.size():
			var shadow := retained.get_child(index) as Polygon2D
			_check(shadow != null and shadow.is_inside_tree(), "each contact is a live rendered polygon")
			if shadow == null:
				continue
			var center := Vector2.ZERO
			for point in shadow.polygon:
				center += shadow.to_global(point)
			center /= shadow.polygon.size()
			var near_offset: float = OfficeTable.CHAIR_OFFSET["near"]
			_check(
				center.is_equal_approx(table.seat(index, "near").global_position + Vector2(0, near_offset)),
				"contact stays under its actual chair after growth and relocation"
			)
	_eq(_seat_node(office, "api:p1"), station, "growing shadows does not replace the existing station")
	_done(office)


func test_column_and_side_swaps_preserve_people_and_final_equipment() -> void:
	var snapshot := _both_sides()
	var office := await _live_office(snapshot)
	var old_stations: Dictionary[String, OfficeStation] = {}
	var actor_ids: Dictionary[String, int] = {}
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		var station := _seat_node(office, pane_id)
		old_stations[pane_id] = station
		actor_ids[pane_id] = station.actor().get_instance_id()
	var swapped: Dictionary = snapshot.duplicate(true)
	var columns: Dictionary[String, int] = {"api:p1": 1, "api:p2": 0, "api:p3": 1}
	var sides: Dictionary[String, String] = {"api:p1": "near", "api:p2": "far", "api:p3": "far"}
	for layout: Dictionary in _list(swapped, "layouts"):
		if layout.tab_id != "api:t1":
			continue
		for slot: Dictionary in _list(layout, "panes"):
			var pane_id := str(slot.pane_id)
			var rect := _dict(slot, "rect")
			rect.x = columns[pane_id] * 80
			rect.y = 40 if sides[pane_id] == "near" else 0
	_feed(office, swapped)
	await _frames(2)
	_walked(office, "as the swapped workers change seats")
	var occupied: Dictionary[String, bool] = {}
	for pane_id in columns:
		var station := _seat_node(office, pane_id)
		_eq(station, old_stations[pane_id], "a swapped pane retains its station")
		_eq(station.actor().get_instance_id(), actor_ids[pane_id], "a swapped pane retains its actor")
		_eq(station.column, columns[pane_id], "explicit column swap reaches the intended column")
		_eq(station.side, sides[pane_id], "explicit side swap reaches the intended side")
		_eq(
			station.actor().look.orientation,
			AvatarLook.FRONT if station.side == "far" else AvatarLook.BACK,
			"worker faces the correct side after rebinding"
		)
		_eq(
			station.actor().global_position,
			station.table.seat(station.column, station.side).global_position,
			"worker remains seated on the new native marker"
		)
		var planned := office.layout_plan().seat(station.pane_key)
		_eq(planned.column, station.column, "public plan and rendered column agree")
		_eq(planned.side, station.side, "public plan and rendered side agree")
		occupied["%d:%s" % [station.column, station.side]] = true
	var table := _seat_node(office, "api:p1").table
	for column in table.columns.size():
		for side: String in OfficeTable.SIDES:
			_eq(
				table.monitor(column, side).visible,
				occupied.has("%d:%s" % [column, side]),
				"the final occupant alone determines monitor visibility"
			)
	_done(office)


func _check_last_valid_people(office: OfficeScene, signature: String) -> void:
	_check(not office.layout_problems().is_empty(), "invalid input remains visibly diagnosed")
	_check(office.layout_plan().geometry_signature() == signature, "the last valid plan survives rebuilding")
	var keys: Dictionary[String, bool] = {}
	for node in office.world.find_children("*", "OfficeStation", true, false):
		var station: OfficeStation = node
		if station.pane_key.is_empty():
			continue
		_check(not keys.has(station.pane_key), "last-valid drawing contains no duplicate pane")
		keys[station.pane_key] = true
	_eq(keys.size(), 4, "last-valid floor still has exactly its four panes")
	var first := _seat_node(office, "api:p1")
	_check(first != null and first.actor() != null, "last-valid worker is reconstructed")
	if first != null and first.actor() != null:
		_eq(first.actor().provider, "claude", "invalid input cannot change the last-valid provider")
		_check(not _papers(first).visible, "invalid done state cannot put paper on the last-valid desk")
		var badge: StatusBadge = first.get_node("Overlay/Badge")
		_eq(badge.state, ArtContract.STATE_WORKING, "last-valid badge agrees with last-valid worker")
	var texts := PackedStringArray()
	for node in office.world.find_children("*", "Label", true, false):
		var label: Label = node
		texts.append(label.text)
	_check(texts.has("MAIN"), "last-valid table title is reconstructed")
	_check(not texts.has("INVALID TITLE"), "invalid model title never leaks into rebuilt desks")


func _tap_key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		await _parsed(event)


func test_invalid_input_keeps_last_valid_people_across_theme_and_floor_changes() -> void:
	var office := await _live_office()
	var signature := office.layout_plan().geometry_signature()
	var attempts := office.layout_attempt_count()
	var invalid := _with(fixture, "api:p1", {"agent": "codex", "agent_status": "done"})
	var repeated: Dictionary = _list(invalid, "panes")[1]
	_list(invalid, "panes").append(repeated.duplicate(true))
	for tab: Dictionary in _list(invalid, "tabs"):
		if tab.tab_id == "api:t1":
			tab.label = "invalid title"
	_feed(office, invalid)
	_eq(office.layout_attempt_count(), attempts + 1, "a new invalid input is attempted only once")
	var problems := office.layout_problems()
	for repeat in 3:
		_feed(office, _with(invalid, "api:p4", {"agent_status": "done", "task": str(repeat)}))
	_eq(office.layout_attempt_count(), attempts + 1, "status-only invalid refreshes reuse the failed attempt")
	_eq(office.layout_problems(), problems, "a failed cache hit retains its diagnostic")
	_check_last_valid_people(office, signature)
	office.switch_theme(_second_pack())
	await _frames(2)
	_eq(office.art.id, SECOND_PACK, "theme really switches while the snapshot is invalid")
	_eq(office.layout_attempt_count(), attempts + 2, "a new theme retries the input once")
	_check_last_valid_people(office, signature)
	await _tap_key(KEY_PAGEUP)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "real key input leaves the invalid floor")
	_check(office.layout_problems().is_empty(), "the other valid floor is not poisoned")
	attempts = office.layout_attempt_count()
	await _tap_key(KEY_PAGEDOWN)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "api"), "real key input returns to the cached floor")
	_eq(office.layout_attempt_count(), attempts, "returning to a failed floor does not replan")
	_eq(office.layout_problems(), problems, "returning restores the failed floor's own diagnostic")
	_check_last_valid_people(office, signature)
	office.rebuild_world()
	await _frames(2)
	_eq(office.layout_attempt_count(), attempts, "rebuilding a failed floor uses the retained plan")
	_check_last_valid_people(office, signature)
	_feed(office, _with(fixture, "api:p1", {"agent": "codex", "agent_status": "done"}))
	_check(office.layout_problems().is_empty(), "corrected input clears the diagnostic")
	_eq(_seat_node(office, "api:p1").actor().provider, "codex", "valid recovery applies the newer provider")
	_check(_papers(_seat_node(office, "api:p1")).visible, "valid recovery applies the newer paper")
	_eq(office.layout_attempt_count(), attempts + 1, "corrected geometry is attempted once")
	_feed(office, _with(fixture, "api:p1", {"agent": "codex", "agent_status": "working"}))
	_eq(office.layout_attempt_count(), attempts + 1, "valid status changes still hit the successful cache")
	office.rebuild_world()
	_check(not _papers(_seat_node(office, "api:p1")).visible, "successful cache hits update the retained display model")
	_done(office)


func test_first_budget_failure_is_cached_until_geometry_changes_or_floor_closes() -> void:
	var invalid := {
		"workspaces": [{"workspace_id": "oversized", "number": 1}],
		"tabs": [{"workspace_id": "oversized", "tab_id": "wide", "number": 1}],
		"panes": [],
		"layouts": []
	}
	# 506 panes need 254 paired-growth columns: their measured reserved width
	# plus the outer walls and corridor exceeds the 512-cell production budget.
	for index in 506:
		_list(invalid, "panes").append({"pane_id": "wide-%d" % index, "tab_id": "wide", "workspace_id": "oversized"})
	var office := await _live_office(invalid)
	_eq(office.layout_attempt_count(), 2, "first failure plans once and constructs one bounded fallback")
	var fallback := office.layout_plan()
	var problems := office.layout_problems()
	_check("; ".join(problems).contains("tab exceeds measured width budget"), "the real width budget rejects input")
	_check(fallback != null and fallback.desks.is_empty(), "first failure has an empty floor, not invalid desks")
	_eq(OfficeFloorLayout.validate(fallback), PackedStringArray(), "fallback obeys the real floor budget")
	for repeat in 3:
		_feed(office, invalid)
	_eq(office.layout_attempt_count(), 2, "unchanged over-budget snapshots do not run the planner again")
	_eq(office.layout_plan(), fallback, "unchanged failure retains the fallback object")
	_eq(office.layout_problems(), problems, "unchanged failure remains diagnosed")
	office.test_screen = Vector2(1400, 480)
	_feed(office, invalid, false)
	_set_online(office, false)
	_set_online(office, true)
	_eq(office.layout_attempt_count(), 2, "viewport and liveness changes do not retry fixed-row geometry")
	office.rebuild_world()
	_eq(office.layout_attempt_count(), 2, "rebuilding an initial failure also hits its failed cache")
	_eq(office.world.find_children("*", "OfficeStation", true, false).size(), 0, "fallback never adopts invalid people")
	# A different invalid structure must be tried; it is not a sticky failure flag.
	_list(invalid, "panes").append({"pane_id": "wide-extra", "tab_id": "wide", "workspace_id": "oversized"})
	_feed(office, invalid)
	_eq(office.layout_attempt_count(), 3, "changed invalid geometry is retried once")
	_eq(office.layout_plan(), fallback, "a second failure does not replace the bounded fallback")
	_feed(office, {})
	_check(
		office.layout_plan() == null and office.layout_problems().is_empty(), "closing the floor shows a clean lobby"
	)
	_feed(office, invalid)
	_eq(office.layout_attempt_count(), 5, "reopening forgets the failed attempt and builds a new fallback")
	_check(office.layout_plan() != fallback, "closed floors release their retained geometry")
	_eq(office.layout_problems(), problems, "reopened invalid floor is diagnosed again")
	var corrected: Dictionary = invalid.duplicate(true)
	corrected.panes = [{"pane_id": "wide-0", "tab_id": "wide", "workspace_id": "oversized"}]
	_feed(office, corrected)
	_eq(office.layout_attempt_count(), 6, "legal geometry retries once after the first-failure fallback")
	_check(office.layout_problems().is_empty(), "legal geometry clears the cached failure")
	_check(_seat_node(office, "wide-0") != null, "the recovered floor draws the valid pane")
	_done(office)


func test_actor_clearance_changes_invalidate_failed_planning() -> void:
	var office := await _live_office()
	var retained := office.layout_plan()
	var attempts := office.layout_attempt_count()
	var pivot := office.art.people.pivot
	# Keep the theme ID and snapshot unchanged, but change a real policy input.
	# A canvas this tall cannot clear the back wall; it must not hit the cache.
	office.art.people.pivot = Vector2(pivot.x, 300)
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 1, "changed actor clearance is planned once")
	_check(not office.layout_problems().is_empty(), "the new actor clearance is actually rejected")
	_eq(office.layout_plan(), retained, "clearance failure retains the valid plan")
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 1, "unchanged failed clearance is cached")
	office.test_screen = Vector2(1400, 480)
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 2, "failed policy reset retries with a new initial width")
	_check(not office.layout_problems().is_empty(), "a wider floor still cannot clear the tall canvas")
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 2, "the failed reset is cached at its new width")
	office.art.people.pivot = pivot
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 3, "restored policy measurements retry the same snapshot")
	_check(office.layout_problems().is_empty(), "valid policy recovery clears the failure")
	_eq(
		office.layout_plan().initial_width_cells,
		retained.initial_width_cells,
		"compatible recovery keeps the fixed rows"
	)
	office.art.people.pivot = pivot + Vector2(0, 1)
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 4, "a compatible new canvas triggers one successful policy reset")
	_check(office.layout_problems().is_empty(), "a one-pixel taller canvas still clears the walls")
	_check(
		office.layout_plan().initial_width_cells > retained.initial_width_cells,
		"policy reset uses the new viewport width"
	)
	_feed(office, fixture)
	_eq(office.layout_attempt_count(), attempts + 4, "a successful policy reset is immediately cached")
	_done(office)


func test_render_budget_failure_keeps_old_nodes_and_first_failure_is_empty() -> void:
	var office := await _live_office()
	var previous := office.layout_plan()
	var station := _seat_node(office, "api:p1")
	var worker := station.actor()
	# The world also owns the layout-error label; the retained floor itself
	# must not add, remove or replace any candidate rendering nodes.
	var floor_root := office.world.get_node("FloorRooms")
	var nodes := floor_root.find_children("*", "", true, false)
	var excessive: Dictionary = fixture.duplicate(true)
	for index in 187:
		_list(excessive, "tabs").append(
			{"workspace_id": "api", "tab_id": "empty-%d" % index, "number": index + 10, "label": "empty"}
		)
	_feed(office, excessive)
	await _frames(2)
	_check(office.layout_problems().has("floor exceeds desk node budget"), "render allocation refusal is visible")
	_eq(office.layout_plan(), previous, "refusal retains the same valid plan")
	_eq(_seat_node(office, "api:p1"), station, "refusal retains the same station")
	_eq(station.actor(), worker, "refusal retains the same actor")
	_eq(office.world.get_node("FloorRooms"), floor_root, "refusal retains the same floor root")
	_check(floor_root.find_children("*", "", true, false) == nodes, "refusal leaves every rendered floor node intact")
	_feed(office, fixture)
	_check(office.layout_problems().is_empty(), "valid input recovers without sacrificing the old layout")
	_done(office)
	var initial := await _live_office(excessive)
	_check(initial.layout_problems().has("floor exceeds desk node budget"), "first snapshot is also refused")
	_eq(initial.layout_plan().desks.size(), 0, "first failure uses the bounded empty fallback")
	_eq(initial.world.find_children("*", "OfficeStation", true, false).size(), 0, "first failure allocates no stations")
	_done(initial)


## A floor planned for the first time is validated once, its standing furniture
## included: the planner furnishes the candidate before its one flood fill,
## rather than validating the bare plan and then the furnished one again.
func test_a_new_floor_is_validated_once_decor_included() -> void:
	var office := await _live_office()
	var attempts := office.layout_attempt_count()
	var before := OfficeFloorValidation.validations
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "web"))
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "the new floor is shown")
	_eq(office.layout_attempt_count(), attempts + 1, "which is planned once")
	_check(not office.layout_plan().decorations.is_empty(), "and furnished")
	_eq(OfficeFloorValidation.validations - before, 1, "one validation covers the plan and its furniture")
	_done(office)
