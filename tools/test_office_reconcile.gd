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


## bee's connection drops, as _set_online(office, false) drops Local's; a
## fresh snapshot (_feed_bee()) brings it back.
func _bee_drops(office: OfficeDouble) -> void:
	_bee(office)._go_offline()
	office.fleet.liveness_changed.emit()


func _seat_node(office: OfficeScene, pane_id: String, machine := LOCAL) -> OfficeStation:
	var key := HerdrFleet.pane_key(machine, pane_id)
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
	# No row walls: every wall tile is the top wall's two courses or a side
	# wall, and no row wall's joint (t_left, end_right) is laid at all.
	for at in wall_hits:
		_check(
			at.y < ArtContract.WALL_COURSES.size() or at.x == 0 or at.x == plan.floor_cells.size.x - 1,
			"wall tile %s is the top wall's or a side wall's" % at
		)
	for cell in walls.get_used_cells():
		var id := str(walls.get_cell_tile_data(cell).get_custom_data("semantic_id"))
		_check(not ("t_left" in id or "end_right" in id), "no row wall's joint is laid: %s" % id)
	for x in plan.floor_cells.size.x:
		for course in ArtContract.WALL_COURSES.size():
			_eq(wall_hits.get(Vector2i(x, course), 0), 1, "every top wall cell is drawn once")
	var tile_size := Vector2(floor_layer.tile_set.tile_size)
	var pixels := Rect2(Vector2(plan.floor_cells.position) * tile_size, Vector2(plan.floor_cells.size) * tile_size)
	var transform_to_world := office.world.global_transform.affine_inverse() * floor_layer.global_transform
	_check(
		office.world_bounds().encloses(transform_to_world * pixels),
		"public scroll bounds contain the actual rendered floor"
	)


func test_complete_floor_and_unique_wall_cells_follow_the_plan() -> void:
	# 628 wide: the floor is planned 488 units wide, one lane (8 inner cells);
	# with nine more agents api:t1 is a pod of 7 cells, and api:t2's (3) wraps
	# to a second pod row (the fixture's own two pods share one row).
	var office := await _live_office(_wide_api(9), Vector2(628, 480))
	_check(office.layout_plan().zones[0].rows.size() > 1, "fixture exercises multiple pod rows")
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
	# api with 33 more agents: its pod of 18 desks reaches across the whole
	# plan (a dozen more agents did with the long tables; a desk is 32 wide).
	var office := await _live_office(_wide_api(33))
	await _frames(4)
	var hud := office.hud
	_check(not hud.drawer_open(), "the drawer starts closed")
	# The map's first width is the lanes that width holds: 10L + 3 cells.
	var policy := FloorLayoutPolicy.new()
	_eq(
		office.layout_plan().initial_width_cells,
		policy.map_width(policy.lanes_for(floori(hud.plan_width() / FloorLayoutPolicy.GRID))),
		"the floor is planned for the drawer closed"
	)
	_eq(hud.plan_width(), 660.0, "660 wide at 800x480")
	var world_id := office.world.get_instance_id()
	var attempts := office.plans.attempt_count()
	var plan := office.layout_plan().geometry_signature()
	var desks := _desk_ids(office, "")
	var rightmost: OfficeStation = null
	for station in _seats(office):
		# api's pod: the other zones of the map hold shells the list does not show.
		if not station.pane_key.begins_with(HerdrFleet.pane_key(LOCAL, "api:")):
			continue
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
	# api with 27 more agents, so a pod reaches the middle of the screen,
	# where the gap is (the fixture's own pods stand in its left third).
	var office := await _live_office(_wide_api(27))
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


## The floor's ground runs on past its side walls, under the HUD's side
## panels, which float over it (the shell's apron): from the screen's left
## edge to its right one, as deep as the floor, and nowhere on the floor
## itself. Only drawn: the plan's cells, and so the walk graph, stay the
## floor's, and the camera's reach does not grow with it.
func test_the_floor_runs_on_under_the_side_panels() -> void:
	var office := await _live_office()
	await _frames(4)
	var apron: TileMapLayer = office.floor_view.ground.find_child("Apron", true, false)
	_check(apron != null, "the shell has an apron")
	if apron == null:
		_done(office)
		return
	var plan := office.floor_view.plan
	var cells := plan.floor_cells
	var used := apron.get_used_rect()
	var room := office.camera.free_rect()
	var grid := float(FloorLayoutPolicy.GRID)
	var screen := Vector2(office.test_screen)
	_check(used.position.x * grid <= -room.position.x, "from the screen's left edge: %s" % used)
	_check(used.end.x * grid >= screen.x - room.position.x, "to its right edge: %s" % used)
	_eq([used.position.y, used.size.y], [0, cells.size.y], "as deep as the floor")
	for x in cells.size.x:
		_eq(apron.get_cell_source_id(Vector2i(x, cells.size.y - 1)), -1, "none on the floor's own column %d" % x)
	_eq(cells.position, Vector2i.ZERO, "the plan's floor still starts at its own origin")
	var reach := Vector2(maxf(plan.render_bounds.end.x, room.size.x), office.camera.world_size.y)
	_eq(office.camera.world_size, reach, "and the camera reaches no further than the floor and its plate")
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
	_eq(keys.size(), 13, "the last-valid map still has exactly its 13 panes, every zone's")
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
	# Planning is atomic per machine (docs/WORLD_MODEL.md, "Caching"): web is
	# a zone of the same map, drawn from the same last valid plan, so paging
	# to it pans and neither replans nor clears the diagnostic, which used to
	# be api's floor's alone.
	attempts = office.layout_attempt_count()
	await _tap_key(KEY_PAGEDOWN)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(LOCAL, "web"), "real key input pans to web")
	_eq(office.layout_problems(), problems, "on the same map, which keeps its diagnostic")
	_check_last_valid_people(office, signature)
	await _tap_key(KEY_PAGEUP)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(LOCAL, "api"), "and back to api")
	_eq(office.layout_attempt_count(), attempts, "paging between zones of a failed map does not replan")
	_eq(office.layout_problems(), problems, "and the diagnostic stays the map's")
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


## The fixture with `count` more agents on api's first tab, so its pod grows
## that many seats wider.
func _wide_api(count: int) -> Dictionary:
	var grown: Dictionary = fixture.duplicate(true)
	var first: Dictionary = _list(grown, "panes")[0]
	for index in count:
		var extra: Dictionary = first.duplicate(true)
		extra.pane_id = "api:wide-%d" % index
		_list(grown, "panes").append(extra)
	return grown


## The first failure of a map that has no plan at all: the cache builds a
## bounded, empty fallback for it. Only a map never planned before gets there,
## and Local's never is one: an office plans Local's map, empty, in _ready(),
## before any snapshot, so a first snapshot that cannot be laid out keeps that
## plan (test_render_budget_failure_keeps_old_nodes_and_first_failure_is_empty).
## A second machine's map is first planned when it is first shown. So the first
## failure here is bee's: fed a workspace no map can hold while Local's map is
## shown, then shown by a real click on its row.
func test_first_budget_failure_is_cached_until_geometry_changes_or_floor_closes() -> void:
	var invalid := {
		"workspaces": [{"workspace_id": "oversized", "number": 1}],
		"tabs": [{"workspace_id": "oversized", "tab_id": "wide", "number": 1}],
		"panes": [],
		"layouts": []
	}
	# 1014 panes need 508 paired-growth columns: their measured reserved width
	# (a pod packs a column into one cell) plus the outer walls and corridor
	# exceeds the 512-cell production budget.
	for index in 1014:
		_list(invalid, "panes").append({"pane_id": "wide-%d" % index, "tab_id": "wide", "workspace_id": "oversized"})
	var oversized := HerdrFleet.pane_key(BEE, "oversized")
	var office := await _two_machine_office()
	var local := office.plans.plan(LOCAL)
	_check(local != null and not local.desks.is_empty(), "Local's map is planned and shown")
	_check(office.plans.plan(BEE) == null, "bee's map, never shown, has no plan")
	_feed_bee(office, invalid)
	await _frames(2)
	_check(office.plans.plan(BEE) == null, "and none is made for input it is not shown for")
	# Counted from here: what showing bee's map for the first time plans. (A
	# refresh that shows Local keeps the model it last drew Local from.)
	var local_model := office.plans.planned_model(LOCAL)
	var attempts := office.layout_attempt_count()
	await _visit_floor(office, oversized)
	_eq(office.navigator.shown_key, BEE, "a real click on its row shows bee's map")
	_eq(office.layout_attempt_count(), attempts + 2, "first failure plans once and constructs one bounded fallback")
	var fallback := office.layout_plan()
	var problems := office.layout_problems()
	_check("; ".join(problems).contains("tab exceeds measured width budget"), "the real width budget rejects input")
	_check(fallback != null and fallback.desks.is_empty(), "first failure has an empty floor, not invalid desks")
	_eq(OfficeFloorLayout.validate(fallback), PackedStringArray(), "fallback obeys the real floor budget")
	_eq([fallback.floor_key, fallback.zones.size()], [BEE, 0], "the fallback is bee's own map, with no zone at all")
	_eq(office.plans.plan(BEE), fallback, "and is what the cache now holds for bee")
	var kept := office.plans.planned_model(BEE)
	_check(kept != null and kept.key == BEE and kept.zones.is_empty(), "with the empty model it was planned from")
	_eq(office.plans.failing_zones(BEE), PackedStringArray([oversized]), "the zone that cannot be laid out is named")
	_eq(office.plans.plan(LOCAL), local, "bee's failure leaves Local's plan alone")
	_eq(office.plans.planned_model(LOCAL), local_model, "and the model it was planned from")
	for repeat in 3:
		_feed_bee(office, invalid)
	_eq(office.layout_attempt_count(), attempts + 2, "unchanged over-budget snapshots do not run the planner again")
	_eq(office.layout_plan(), fallback, "unchanged failure retains the fallback object")
	_eq(office.layout_problems(), problems, "unchanged failure remains diagnosed")
	office.test_screen = Vector2(1400, 480)
	office.refresh()
	_bee_drops(office)
	_feed_bee(office, invalid)
	_set_online(office, false)
	_set_online(office, true)
	_eq(office.layout_attempt_count(), attempts + 2, "viewport and liveness changes do not retry fixed-row geometry")
	_eq(office.navigator.shown_key, BEE, "bee's map is still the one shown")
	office.rebuild_world()
	_eq(office.layout_attempt_count(), attempts + 2, "rebuilding an initial failure also hits its failed cache")
	_eq(office.world.find_children("*", "OfficeStation", true, false).size(), 0, "fallback never adopts invalid people")
	# A different invalid structure must be tried; it is not a sticky failure flag.
	_list(invalid, "panes").append({"pane_id": "wide-extra", "tab_id": "wide", "workspace_id": "oversized"})
	_feed_bee(office, invalid)
	_eq(office.layout_attempt_count(), attempts + 3, "changed invalid geometry is retried once")
	_eq(office.layout_plan(), fallback, "a second failure does not replace the bounded fallback")
	_feed_bee(office, {})
	_check(
		office.layout_plan().zones.is_empty() and office.layout_problems().is_empty(),
		"closing the workspace plans a clean empty map (an empty map is planned and counted like any other)"
	)
	_eq(office.navigator.shown_key, BEE, "which is still bee's")
	_feed_bee(office, invalid)
	_eq(office.layout_attempt_count(), attempts + 5, "reopening forgets the failed attempt and tries again")
	_check(office.layout_plan() != fallback, "the empty map's plan replaced the retained fallback")
	_eq(office.layout_problems(), problems, "reopened invalid workspace is diagnosed again")
	var corrected: Dictionary = invalid.duplicate(true)
	corrected.panes = [{"pane_id": "wide-0", "tab_id": "wide", "workspace_id": "oversized"}]
	_feed_bee(office, corrected)
	_eq(office.layout_attempt_count(), attempts + 6, "legal geometry retries once after the first-failure fallback")
	_check(office.layout_problems().is_empty(), "legal geometry clears the cached failure")
	_check(_seat_node(office, "wide-0", BEE) != null, "the recovered floor draws the valid pane")
	var recovered := office.layout_plan()
	_eq(recovered.floor_key, BEE, "on bee's map")
	_check(recovered.seat(HerdrFleet.pane_key(BEE, "wide-0")) != null, "whose plan seats it under bee's key")
	_eq(recovered.seat(HerdrFleet.pane_key(LOCAL, "wide-0")), null, "and never under Local's")
	_eq(office.plans.failing_zones(BEE), PackedStringArray(), "no zone of bee's fails any more")
	_eq(office.plans.plan(LOCAL), local, "Local's plan is the one it had throughout")
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
	# Two hundred empty tabs: 200 minimum pods at 168 nodes each, over 32768.
	var excessive: Dictionary = fixture.duplicate(true)
	for index in 200:
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
	# Local's first snapshot: refused, over the empty map _ready() planned.
	var initial := await _live_office(excessive)
	_check(initial.layout_problems().has("floor exceeds desk node budget"), "first snapshot is also refused")
	_eq(initial.layout_plan().desks.size(), 0, "Local keeps the empty map it started with")
	_eq(initial.world.find_children("*", "OfficeStation", true, false).size(), 0, "first failure allocates no stations")
	_done(initial)
	# A map with no plan at all (bee's, never shown): the same refusal builds
	# the fallback itself, on a real click on one of its rows.
	var remote := await _two_machine_office()
	_feed_bee(remote, excessive)
	await _frames(2)
	_check(remote.plans.plan(BEE) == null, "bee's map, never shown, has no plan")
	var attempts := remote.layout_attempt_count()
	await _visit_floor(remote, HerdrFleet.pane_key(BEE, "api"))
	_eq(remote.navigator.shown_key, BEE, "a real click on its row shows bee's map")
	_eq(remote.layout_attempt_count(), attempts + 2, "the refused input, then the bounded fallback")
	_check(remote.layout_problems().has("floor exceeds desk node budget"), "bee's first show is refused too")
	_eq([remote.layout_plan().floor_key, remote.layout_plan().zones.size()], [BEE, 0], "an empty fallback of its own")
	_eq(remote.layout_plan().desks.size(), 0, "with no desk")
	_eq(remote.world.find_children("*", "OfficeStation", true, false).size(), 0, "and no station allocated")
	_done(remote)


## A map planned for the first time is validated once, its standing furniture
## included: the planner furnishes the candidate before its one flood fill,
## rather than validating the bare plan and then the furnished one again. A
## machine's map is first planned when it is first shown: bee's, on a real
## click on its row, in a window wide enough for two lanes (a first plan 23
## cells wide; the narrowest map, one lane, has its top wall full of windows and
## no lane beside its zone, so nothing to furnish).
func test_a_new_floor_is_validated_once_decor_included() -> void:
	var office := await _two_machine_office(fixture, Vector2(880, 480))
	var attempts := office.layout_attempt_count()
	var before := OfficeFloorValidation.validations
	await _visit_floor(office, HerdrFleet.pane_key(BEE, "hive"))
	_eq([office.navigator.shown_key, office.layout_plan().floor_key], [BEE, BEE], "bee's map is shown")
	_eq(office.layout_attempt_count(), attempts + 1, "planned once")
	_check(not office.layout_plan().decorations.is_empty(), "and furnished")
	_eq(OfficeFloorValidation.validations - before, 1, "one validation covers the plan and its furniture")
	_done(office)


## Two workspaces are two zones of one map (before maps: two floors): A (one
## tab of 40 panes, a pod of 20 columns, 21 cells: three lanes, the map widened
## for them) and B (2 panes) planned together, once. PageUp/PageDown between
## them pan: the same plan object, the same zone rectangles, the same world,
## nobody made to walk, and no replan. A drag moves the one map's pan, which
## the next zone pick replaces (its aisle row at the top).
func test_zones_on_one_map_keep_their_rectangles_and_the_world_when_paged() -> void:
	var snapshot := {
		"workspaces": [{"workspace_id": "a", "number": 1}, {"workspace_id": "b", "number": 2}],
		"tabs":
		[{"workspace_id": "a", "tab_id": "a:t", "number": 1}, {"workspace_id": "b", "tab_id": "b:t", "number": 1}],
		"panes": [],
		"layouts": []
	}
	var counts: Dictionary[String, int] = {"a": 40, "b": 2}
	for space: String in counts:
		for index in counts[space]:
			var pane := {"pane_id": "%s:p%d" % [space, index], "tab_id": space + ":t", "workspace_id": space}
			_list(snapshot, "panes").append(pane)
	# 880 wide lays the world out 740 units wide: a first plan is 23 cells.
	var office := await _live_office(snapshot, Vector2(880, 480))
	var a := HerdrFleet.pane_key(LOCAL, "a")
	var b := HerdrFleet.pane_key(LOCAL, "b")
	var plan := office.layout_plan()
	_eq([plan.floor_key, plan.lanes], [LOCAL, 3], "one map, the machine's, three lanes for A's pod")
	var rects := [plan.zone(a).cells, plan.zone(b).cells]
	_eq(rects[0].size, Vector2i(29, 6), "A spans the three lanes")
	var middle := office.hud.world_rect().get_center()
	await _drag(middle, middle + Vector2(-160, -60))
	var attempts := office.layout_attempt_count()
	var world := office.world.get_instance_id()
	# The rail is ascending. Nothing is selected or picked, so the first key
	# picks the map's first zone, A (1); PageDown then goes on to B (2), PageUp back.
	for step: Array in [[KEY_PAGEDOWN, a], [KEY_PAGEDOWN, b], [KEY_PAGEUP, a]]:
		var key: Key = step[0]
		await _tap_key(key)
		var zone: String = step[1]
		_eq(
			[office.navigator.shown_key, office.navigator.current_zone(office.frame)], [LOCAL, zone], "paged to " + zone
		)
		_eq(office.layout_plan(), plan, "the same plan object")
		_eq([plan.zone(a).cells, plan.zone(b).cells], rects, "both zones keep their rectangles")
		_eq(office.layout_attempt_count(), attempts, "nothing planned again")
		_eq(office.world.get_instance_id(), world, "the same world, not built again")
		_eq(office.floor_view.presentation.walkers(), [], "and nobody walks")
		var reach := office.camera.world_size.y - office.camera.free_rect().size.y
		_eq(office.camera.pan.y, minf(_sign_top(office, zone), reach), "panned to its sign, as far as the map goes")
	_done(office)


## Where the top of zone `zone`'s sign is drawn, in the world's coordinates:
## what a zone pick puts at the top of the world (OfficeScene.reveal_zone()).
func _sign_top(office: OfficeDouble, zone: String) -> float:
	var board := office.floor_view.zone_sign(zone)
	var holder := board.get_parent() as Node2D
	return office.world.to_local(holder.to_global(board.drawn_rect().position)).y


## PLAN_R2 §1.10, density: 1920×960 at 2x (the 960×480 view), the drawer
## closed, the staff card one line; a real click on the first zone's FLOORS
## row; the seats whose click rect (target_rect(), no chip) is wholly inside
## world_rect() are counted. Two workspaces, one to a lane, each of four tabs of
## 8, 4, 8 and 4 working agents (pods of 4, 2, 4 and 2 columns: two pod rows),
## and again with the first two tabs only (one pod row). The floors before one
## map per machine showed 12 in the same rect.
func test_a_zone_call_shows_the_planned_density() -> void:
	for rows: int in [2, 1]:
		var office := await _live_office(_density(rows), Vector2(960, 480))
		_check(not office.hud.drawer_open() and office.hud.card_compact(), "drawer closed, card one line")
		_eq(office.hud.world_rect(), Rect2(96, 48, 820, 308), "the world's room at 1920×960, 2x")
		var plan := office.layout_plan()
		var a := plan.zone(HerdrFleet.pane_key(LOCAL, "a"))
		var b := plan.zone(HerdrFleet.pane_key(LOCAL, "b"))
		_eq([a.first_lane, a.lanes, b.first_lane, b.lanes], [0, 1, 1, 1], "%d: one zone to a lane" % rows)
		_eq([a.rows.size(), b.rows.size()], [rows, rows], "%d pod rows each" % rows)
		await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "a"))
		await _frames(3)
		var room := office.hud.world_rect()
		var seen := 0
		for key: String in office.floor_view.seats:
			var rect := office.floor_view.seats[key].node.target_rect()
			if room.encloses(Rect2(rect.position - office.camera.position, rect.size)):
				seen += 1
		var wanted := 36 if rows == 2 else 24
		print("DENSITY %d pod row(s): %d seats wholly in %s (plan: %d)" % [rows, seen, room, wanted])
		_check(seen >= wanted, "%d pod row(s): at least %d seats wholly in view, %d" % [rows, wanted, seen])
		_done(office)


## Two workspaces `a` and `b`, each with tabs of 8, 4, 8 and 4 working claude
## agents (`rows` 2), or of 8 and 4 (`rows` 1); focus on a's first pane.
func _density(rows: int) -> Dictionary:
	var snapshot := {"workspaces": [], "tabs": [], "panes": [], "layouts": [], "focused_pane_id": "a:t0:p0"}
	for space: String in ["a", "b"]:
		_list(snapshot, "workspaces").append({"workspace_id": space, "number": 1 if space == "a" else 2})
		var sizes: Array[int] = [8, 4, 8, 4]
		sizes.resize(2 * rows)
		for tab in sizes.size():
			var tab_id := "%s:t%d" % [space, tab]
			_list(snapshot, "tabs").append({"workspace_id": space, "tab_id": tab_id, "number": tab + 1})
			for index in sizes[tab]:
				var pane := {"pane_id": "%s:p%d" % [tab_id, index], "tab_id": tab_id, "workspace_id": space}
				pane.merge({"agent": "claude", "agent_status": "working", "terminal_id": "t-%s-%d" % [tab_id, index]})
				_list(snapshot, "panes").append(pane)
	return snapshot


## A zone whose input cannot be laid out is named on the machine's plate, and
## the whole map stays drawn from its previous plan (planning is atomic per
## machine): the same world, the same desks, their nodes kept.
func test_a_failing_zone_is_named_on_the_plate_and_the_map_stays() -> void:
	var office := await _live_office()
	var world := office.world.get_instance_id()
	var desks := _desk_ids(office, "")
	var plan := office.layout_plan()
	var broken := fixture.duplicate(true)
	var repeated: Dictionary = {}
	for pane: Dictionary in _list(broken, "panes"):
		if pane.pane_id == "web:p2":
			repeated = pane.duplicate(true)
	_list(broken, "panes").append(repeated)
	_feed(office, broken)
	_check(not office.layout_problems().is_empty(), "web's input cannot be laid out")
	_eq(office.plans.failing_zones(LOCAL), PackedStringArray([HerdrFleet.pane_key(LOCAL, "web")]), "web is at fault")
	var said := office.plate.problem_text()
	print("PLATE_PROBLEM: " + said)
	_check(said.begins_with("Layout unavailable: 2 WEB"), "the plate names the zone: " + said)
	_eq(office.layout_plan(), plan, "the previous plan stays")
	_eq(office.world.get_instance_id(), world, "the same world")
	_eq(_desk_ids(office, ""), desks, "every desk of every zone keeps its nodes")
	_feed(office, fixture)
	_eq(office.plate.problem_text(), "", "valid again: no problem line")
	_done(office)


## One workspace is drawn as one zone of the map: its partition pieces stand at
## the feet OfficeShell.partition_pieces() plans, each a sprite of its own in a
## y-sorted holder under the sorted root; no row wall's joint is laid; its sign
## hangs at its post, over the aisle row, and names it; each tab's name is
## small text right under its table, no wider than the table, TAB_LABEL_HEIGHT
## deep and clear of every partition piece; and a walker
## inside the zone, above its bottom partition, sorts before that partition.
func test_one_workspace_is_drawn_as_a_zone() -> void:
	var office := await _live_office()
	var plan := office.layout_plan()
	var view := office.floor_view
	_eq(plan.zones.size(), 5, "the machine's five workspaces, five zones of its one map")
	var zone := plan.zone(HerdrFleet.pane_key(LOCAL, "api"))
	for each in plan.zones:
		_check(not view.partition_sprites(each.zone_key).is_empty(), "%s has its partitions drawn" % each.zone_key)
	var sprites := view.partition_sprites(zone.zone_key)
	var planned := OfficeShell.partition_pieces(zone)
	_eq(sprites.size(), planned.size(), "every planned partition piece is drawn")
	for index in mini(sprites.size(), planned.size()):
		var sprite := sprites[index]
		var piece := planned[index]
		_eq(sprite.position, piece.foot, "%s stands at its planned foot" % piece.id)
		_eq(sprite.texture, office.art.sprite_texture(office.art.prop_sprite(piece.id)), "as " + piece.id)
		_eq(_entity_of(view.sorted, sprite), sprite, "%s sorts by its own foot" % piece.id)
	# The post's foot is POST_FOOT (6) below the zone's top, measured on the art
	# lane's mock: drawn 12 tall, it covers the top end of the side run below it.
	_eq(OfficeShell.POST_FOOT, 6.0, "the post's foot is 6 below the zone's top")
	var posts := sprites.filter(func(each: Sprite2D) -> bool: return each.position.y == zone.bounds().position.y + 6.0)
	var sides := sprites.filter(func(each: Sprite2D) -> bool: return each.position.y == zone.bounds().position.y + 32.0)
	_eq([posts.size(), sides.size()], [2, 2], "two posts, and the side runs' first pieces under them")
	for index in mini(posts.size(), sides.size()):
		var post: Sprite2D = posts[index]
		var side: Sprite2D = sides[index]
		var drawn := post.transform * post.get_rect()
		var run := side.transform * side.get_rect()
		_eq(
			[drawn.position.y, drawn.end.y],
			[zone.bounds().position.y - 6.0, zone.bounds().position.y + 6.0],
			"post drawn"
		)
		_check(drawn.intersects(run) and drawn.position.y < run.position.y, "the post covers the side run's top end")
	var holder := sprites[0].get_parent() as Node2D if not sprites.is_empty() else null
	_check(holder != null and holder.y_sort_enabled and holder.get_parent() == view.sorted, "in a y-sorted holder")
	var walls: TileMapLayer = view.ground.get_node("Shell/Walls")
	for cell in walls.get_used_cells():
		var id := str(walls.get_cell_tile_data(cell).get_custom_data("semantic_id"))
		_check(not ("t_left" in id or "end_right" in id), "no row wall's joint: %s" % id)
	var board := view.zone_sign(zone.zone_key)
	_check(board != null, "the zone has its sign")
	if board != null:
		_eq(board.position, zone.sign_at, "hung at its post")
		var aisle := Rect2(Vector2(zone.slot().position) * 32.0, Vector2(zone.cells.size.x * 32.0, 32.0))
		_check(aisle.encloses(board.drawn_rect()), "over the aisle row: %s in %s" % [board.drawn_rect(), aisle])
		var number: Label = board.get_node("%Number")
		var title: Label = board.get_node("%Title")
		_eq([number.text, title.text], ["1", "API"], "naming the workspace by its number and its label")
	for tab: String in view.desks:
		var desk := view.desks[tab]
		var placed := desk.placement
		var under := placed.origin + Vector2(0, placed.measure.render_rect.end.y)
		_eq(desk.title.position, under, "%s's name stands right under its table" % tab)
		_eq(desk.title.size.x, placed.measure.table_width, "no wider than the table")
		# TAB_LABEL_HEIGHT deep, so a last pod row's name ends where the bottom
		# run's drawing starts (46 + 8 = 54 = 64 - 10 under the pod's origin).
		_eq(desk.title.size.y, OfficeDraw.TAB_LABEL_HEIGHT, "%s's name is TAB_LABEL_HEIGHT deep" % tab)
		var box := Rect2(desk.title.position, desk.title.size)
		for sprite in sprites:
			var piece := sprite.transform * sprite.get_rect()
			_check(not box.intersects(piece), "%s's name %s clears the partition drawn at %s" % [tab, box, piece])
		_check(desk.title.get_parent() == desk.background, "on the ground")
	var bottom := zone.bounds().end.y
	var run := sprites.filter(func(each: Sprite2D) -> bool: return is_equal_approx(each.position.y, bottom))
	_check(not run.is_empty(), "the bottom partition stands at the zone's bottom")
	var arriving: Dictionary = fixture.duplicate(true)
	var source: Dictionary = {}
	for pane: Dictionary in _list(arriving, "panes"):
		if pane.pane_id == "api:p4":
			source = pane
	var extra := source.duplicate(true)
	extra.pane_id = "api:p9"
	extra.terminal_id = "term-api-p9"
	extra.agent = "claude"
	extra.agent_status = "working"
	_list(arriving, "panes").append(extra)
	_feed(office, arriving)
	var body := _station(office, HerdrFleet.pane_key(LOCAL, "api:p9")).actor()
	var inside := false
	for frame in 600:
		view.walk(1.0 / 30.0)
		var at := view.sorted.to_local(body.global_position)
		if zone.bounds().has_point(at) and at.y > bottom - 64.0:
			inside = true
			break
	_check(inside, "a walker comes down inside the zone, above its bottom partition")
	if inside and not run.is_empty():
		var piece: Sprite2D = run[0]
		_eq(_entity_of(view.sorted, body), body, "the walker sorts by their own feet")
		_check(body.global_position.y < piece.global_position.y, "above the partition's foot: drawn before it")
	_done(office)
