extends "res://tools/office_test_base.gd"
## The strategic view: `S` swaps the world for a flat
## schematic of the shown machine's map, a captioned section per zone in the
## SPACES rail's order, one square per seated pane in the SPACES windows'
## colours, a blocked one saying how long it has waited where there is
## room. A click on a square picks that pane, closes the view and pans its desk
## into sight; `S` and Escape leave. Only the world rect is covered: SPACES, the
## drawer, the staff panel and NEWS stay usable. Keys, clicks, drags, the wheel
## and the pointer go through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_strategic.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the lens suite does. The 80-pane floor is built here from
## snapshot_floors.json's own records (10 tabs of 8, tools/gen_stress_fixture.py's
## state cycle), so this suite needs no generated fixture.

## tools/gen_stress_fixture.py's STATES, in turn over every pane.
const STRESS_STATES: Array[String] = ["working", "idle", "blocked", "done", "working", "working"]
## The default window's content at 2x (1920x960), and the 4x / minimum one.
const WIDE := Vector2(960, 480)
const SMALL := Vector2(480, 320)
const STRATEGIC_LINE := "STRATEGIC · S"

## tools/fixtures/snapshot_worktrees.json: a repository with two linked worktrees.
var worktrees: Dictionary = {}


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("strategic-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	for fixture_name: String in ["snapshot_floors", "snapshot_worktrees"]:
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://tools/fixtures/%s.json" % fixture_name)
		)
		if parsed is not Dictionary:
			print("TEST_HARNESS_ERROR: cannot read %s.json" % fixture_name)
			quit(2)
			return
		var file: Dictionary = parsed
		if fixture_name == "snapshot_floors":
			fixture = _dict(file, "snapshot")
		else:
			worktrees = _dict(file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(WIDE)
	await process_frame
	await run_cases()


func _marker() -> String:
	return "STRATEGIC TESTS"


## A case that failed with a key down must not leave it held for the next.
func _after_case() -> void:
	for code: Key in [KEY_L, KEY_RIGHT, KEY_DOWN]:
		var up := InputEventKey.new()
		up.keycode = code
		up.physical_keycode = code
		up.pressed = false
		Input.parse_input_event(up)
	Input.flush_buffered_events()
	super()


# --- opening and closing ------------------------------------------------------


## `S` covers the world rect and nothing else: the world hides (the people keep
## walking under it), the edge arrows and the bubble tooltip go, and SPACES, the
## drawer's tab, the staff panel and NEWS stay where they were, shown. The top
## bar's theme line says the view is on.
func test_s_opens_it_over_the_world_only() -> void:
	var office := await _live_office(fixture, WIDE)
	var hud := office.hud
	var others := {}
	for panel: Control in [hud.spaces, hud.right_column, hud.staff, hud.news]:
		others[panel.name] = [panel.visible, hud.placed(panel)]
	await _frames(2)
	_check(hud.edge_arrows.visible, "web and infra wait off screen: edge arrows before")
	await _office_key(office, KEY_S)
	_check(hud.strategic_open(), "S opens the strategic view")
	_check(not office.world.visible, "the world hides")
	_check(not hud.edge_arrows.visible, "the edge arrows hide")
	_check(not hud.bubble_tip_shown(), "no bubble tooltip")
	_check(not hud.overview_open(), "the overview stays shut")
	var view := hud.strategic
	_eq(view.get_global_rect(), hud.world_rect(), "it covers the world rect exactly")
	_eq(view.mouse_filter, Control.MOUSE_FILTER_STOP, "and takes the mouse there")
	for panel: Control in [hud.spaces, hud.right_column, hud.staff, hud.news]:
		_eq([panel.visible, hud.placed(panel)], others[panel.name], "left as it was: " + str(panel.name))
	_eq(hud.bar.theme_line(), STRATEGIC_LINE, "the top bar says so")
	_done(office)


## `S` again or Escape closes it, and the world under it is the very same nodes.
## Escape peels one layer at a time: an opened staff panel folds first, then
## the view closes. (Answer mode, the first layer, needs an operator office;
## inspector.take_key() runs before any of this in OfficeScene._act_on().)
func test_s_and_esc_close_it_and_the_world_is_the_same_nodes() -> void:
	var office := await _live_office(fixture, WIDE)
	var theme := office.hud.bar.theme_line()
	var world_id := office.world.get_instance_id()
	var ids := _world_ids(office)
	await _office_key(office, KEY_S)
	_check(office.hud.strategic_open(), "open")
	await _office_key(office, KEY_S)
	_check(not office.hud.strategic_open(), "S again closes it")
	_check(office.world.visible, "the world is back")
	_eq(office.world.get_instance_id(), world_id, "the same world")
	_eq(_world_ids(office), ids, "the same nodes")
	_eq(office.hud.bar.theme_line(), theme, "the theme line is the pack's again")
	await _office_key(office, KEY_S)
	await _tap(KEY_ENTER)
	_check(not office.hud.card_compact(), "Enter opens the staff panel under it")
	await _tap(KEY_ESCAPE)
	_check(office.hud.card_compact(), "the first Escape folds the panel")
	_check(office.hud.strategic_open(), "and leaves the view open")
	await _tap(KEY_ESCAPE)
	_check(not office.hud.strategic_open(), "the second closes the view")
	_check(office.world.visible, "and the world is back")
	_eq(_world_ids(office), ids, "still the same nodes")
	await _tap(KEY_ESCAPE)
	_check(not office.hud.strategic_open(), "a third Escape opens nothing")
	_done(office)


# --- what it draws --------------------------------------------------------------


## One square per seated pane, and none for a vacant seat: the plan's rows top
## to bottom (wrapped into columns, newspaper style), each row's tables left to
## right, far seats over near ones, columns left to right, in the table's box.
func test_one_square_per_seated_pane_in_plan_order() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	var layout := office.layout_plan()
	var seated := office.floor_view.seats.keys()
	seated.sort()
	var drawn := Array(plan.seat_keys())
	var sorted := drawn.duplicate()
	sorted.sort()
	_eq(sorted, seated, "one square per seated pane")
	_eq(drawn.size(), 80, "all eighty")
	var expected: Array = []
	var rows := layout.zones[0].rows.duplicate()
	rows.sort_custom(func(a: RowPlan, b: RowPlan) -> bool: return a.index < b.index)
	# A plan row's tables run left to right along one line (a row holds several
	# pods of 32-unit desks); the next row starts under it, at its newspaper
	# column's left edge, or at the top of the next column, right of all so far.
	var previous := Rect2()
	var column_left := -1.0
	var all_right := -INF
	var band_bottom := -INF
	for band: RowPlan in rows:
		var desks := band.desks.duplicate()
		desks.sort_custom(func(a: DeskPlacement, b: DeskPlacement) -> bool: return a.origin.x < b.origin.x)
		var first_in_band := true
		var this_bottom := -INF
		for desk: DeskPlacement in desks:
			var box := plan.table_rect(desk.tab_key)
			_check(box.has_area(), "a box for " + desk.tab_key)
			if previous.has_area():
				if not first_in_band:
					_check(
						box.position.x > previous.end.x and is_equal_approx(box.position.y, previous.position.y),
						"along its row, right of the last: " + desk.tab_key
					)
				elif is_equal_approx(box.position.x, column_left):
					_check(box.position.y > band_bottom, "down the column: " + desk.tab_key)
				else:
					_check(box.position.x > all_right, "the next column, right of the last: " + desk.tab_key)
			if first_in_band:
				if not is_equal_approx(box.position.x, column_left):
					column_left = box.position.x
			first_in_band = false
			all_right = maxf(all_right, box.end.x)
			this_bottom = maxf(this_bottom, box.end.y)
			previous = box
			for side: String in OfficeTable.SIDES:
				var columns: Array[SeatPlacement] = []
				for seat in desk.seats:
					if seat.side == side:
						columns.append(seat)
				columns.sort_custom(func(a: SeatPlacement, b: SeatPlacement) -> bool: return a.column < b.column)
				for seat in columns:
					expected.append(seat.pane_key)
					var square := plan.seat_rect(seat.pane_key)
					_check(box.encloses(square), "%s inside its table's box" % seat.pane_key)
					_eq(square.size, Vector2.ONE * (plan.cell() - 4), "a square of cell - 4: " + seat.pane_key)
			for seat in desk.seats:
				for other in desk.seats:
					var here := plan.seat_rect(seat.pane_key)
					var there := plan.seat_rect(other.pane_key)
					if other.column == seat.column and seat.side == "far" and other.side == "near":
						_check(here.end.y < there.position.y, "far over near: " + seat.pane_key)
					elif other.side == seat.side and other.column > seat.column:
						_check(here.end.x < there.position.x, "left to right: " + seat.pane_key)
		if not desks.is_empty():
			band_bottom = this_bottom
	_eq(drawn, expected, "in plan order")
	_done(office)
	# api's second table seats api:p4 alone: its three vacant seats draw nothing.
	var small := await _live_office(fixture, WIDE)
	await _office_key(small, KEY_S)
	var keys := Array(_plan(small).seat_keys())
	# Five zones, five sections: the squares run section by section in the
	# rail's order (ascending), each section's pod rows in the plan's order.
	_eq(keys, _section_order(small), "section by section, in the rail's order")
	keys.sort()
	var seats := small.floor_view.seats.keys()
	seats.sort()
	_eq(keys, seats, "the fixture's map: a square for each seated pane only")
	var alone := _plan(small).table_rect(_room_of(small, _pk("api:p4")))
	var inside := 0
	for key: String in keys:
		if alone.encloses(_plan(small).seat_rect(key)):
			inside += 1
	_eq(inside, 1, "one square at the table of one")
	_done(small)


## Every square wears the FLOORS window's look for its pane
## (OfficeSpaceRow.window_look()): working, blocked, done, idle, unknown, a
## start (idle), a start that already asks (blocked), a shell (dark). The same
## look as that floor's FLOORS window, the same palette colour
## (HudTheme.SECTION_PANELS), and the lens's wash of a room with only that pane.
func test_squares_wear_the_floors_window_scale() -> void:
	var raw := _with(fixture, "api:p1", {"agent_status": "blocked"})
	raw = _with(raw, "api:p2", {"agent_status": "idle", "launch_pending": true})
	raw = _with(raw, "api:p4", {"agent_status": "blocked", "launch_pending": true})
	var office := await _live_office(raw, WIDE)
	var extra := _with(raw, "api:p1", {"agent_status": "done"})
	_feed(office, extra)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	var looks := plan.looks()
	var wanted := {
		"api:p1": &"WindowDone", "api:p2": &"WindowIdle", "api:p3": &"WindowDark", "api:p4": &"WindowBlocked"
	}
	for pane_id: String in wanted:
		_eq(looks.get(_pk(pane_id), &""), wanted[pane_id], "the look of " + pane_id)
	var zone := office.navigator.current_zone(office.frame)
	var floor_row := office.hud.spaces.row_for(zone)
	var windows: Control = floor_row.get_node("%Windows")
	var index := 0
	var found := office.frame.find_zone(zone)
	for room in found.zone_model.rooms:
		for pane in room.panes:
			var look := OfficeSpaceRow.window_look(pane, true)
			_eq(looks.get(pane.key, &""), look, "window_look(): " + pane.key)
			var window: Control = windows.get_child(index)
			_eq(window.theme_type_variation, look, "the FLOORS window's look: " + pane.key)
			_eq(plan.color_of(pane.key), office.art.color(HudTheme.SECTION_PANELS[look]), "its colour: " + pane.key)
			var alone := RoomModel.new()
			alone.panes.append(pane)
			_eq(OfficeLens.tone_for(alone, false), HudTheme.SECTION_PANELS[look], "the lens agrees: " + pane.key)
			index += 1
	# herdr's states the office does not draw on this floor yet: working and unknown.
	var states := _with(_with(raw, "api:p1", {"agent_status": "working"}), "api:p4", {"agent_status": "thinking"})
	_feed(office, _with(states, "api:p4", {"launch_pending": null}))
	await _frames(2)
	looks = plan.looks()
	_eq(looks.get(_pk("api:p1"), &""), &"WindowWorking", "working")
	_eq(looks.get(_pk("api:p4"), &""), &"WindowUnknown", "a state the office does not know")
	_done(office)


## A blocked square says how long it has waited: the OVERVIEW's FOR for that
## pane at the same moment (StateLog.wait_of() in OfficeAttention.wait_text()),
## `+` where it began before this office watched. Nobody else writes a wait.
func test_a_blocked_square_writes_the_overviews_for() -> void:
	var office := await _live_office(_stress(), WIDE)
	var fresh := _with(_stress(), "w0:t0:p0", {"agent_status": "blocked"})
	_feed(office, fresh)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	_check(plan.cell() >= plan.wait_from(), "a cell with room for a wait: %d" % plan.cell())
	var now := office.hud.strategic.model().now_msec
	var model := OverviewModel.of(
		office.frame, office.fleet.state_log(), "", OverviewModel.Sort.STATE, false, OverviewModel.Filter.ALL, now
	)
	var blocked := 0
	for row in model.rows:
		var pane := office.frame.pane(row.key)
		if pane == null or not plan.seat_keys().has(row.key):
			continue
		if pane.asks():
			_eq(plan.wait_drawn(row.key), OverviewLine.for_text(row), "the OVERVIEW's FOR: " + row.key)
			blocked += 1
		else:
			_eq(plan.wait_drawn(row.key), "", "only a blocked square writes: " + row.key)
	_eq(blocked, 14, "thirteen blocked from the start and w0:t0:p0 since")
	_check(plan.wait_drawn(_spk("w0:t0:p2")).ends_with("+"), "blocked before this office watched")
	_check(not plan.wait_drawn(_spk("w0:t0:p0")).ends_with("+"), "seen going blocked")
	_done(office)


# --- clicks, drags, the wheel -------------------------------------------------------


## A click on a square picks that pane, closes the view and pans its desk into
## sight, even one the camera was nowhere near.
func test_clicking_a_square_picks_closes_and_reveals() -> void:
	var office := await _live_office(_stress(), WIDE)
	var key := _spk("w0:t9:p7")
	_check(not _desk_on_screen(office, key), "w0:t9:p7's desk starts out of sight")
	await _office_key(office, KEY_S)
	await _click_square(office, key)
	_check(not office.hud.strategic_open(), "the click closes the view")
	_check(office.world.visible, "the world is back")
	_eq(office.picked_key, key, "and the pane is picked")
	await _frames(3)
	_check(_desk_on_screen(office, key), "its desk is panned into sight")
	_done(office)


## A drag across the squares, or a click between them, picks nothing and pans nothing.
func test_a_drag_or_a_click_between_squares_picks_nothing() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	var picked := office.picked_key
	var pan := office.camera.pan
	var from := _square_point(office, _spk("w0:t0:p0"))
	var to := _square_point(office, _spk("w0:t1:p3"))
	await _drag(from, to)
	_check(office.hud.strategic_open(), "a drag leaves it open")
	_eq(office.picked_key, picked, "and picks nothing")
	# Press on one square, let go on its neighbour: not a click on either.
	await _parsed(_mouse_button(from, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(_square_point(office, _spk("w0:t0:p2")), MOUSE_BUTTON_LEFT, false))
	_check(office.hud.strategic_open(), "press on one, release on another: still open")
	_eq(office.picked_key, picked, "nothing picked")
	# Between two squares of a row, and in the gap between two tables.
	var left := plan.seat_rect(_spk("w0:t0:p0"))
	var gap := plan.get_global_rect().position + Vector2(left.end.x + 1, left.get_center().y)
	await _click(gap)
	var box := plan.table_rect("w0:t0")
	var outside := plan.get_global_rect().position + Vector2(box.end.x + 2, box.get_center().y)
	await _click(outside)
	_check(office.hud.strategic_open(), "clicks between squares leave it open")
	_eq(office.picked_key, picked, "and pick nothing")
	_eq(office.camera.pan, pan, "and nothing panned the world")
	_done(office)


## Hovering a square names it: provider, state in the pack's words, the wait
## (always, even where the square has no room for it), and where it sits.
func test_the_tooltip_names_provider_state_wait_and_place() -> void:
	var raw := _with(_stress(), "w0:t0:p1", {"agent_status": "idle", "launch_pending": true})
	var office := await _live_office(raw, SMALL)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	_check(plan.cell() < plan.wait_from(), "a small room: the squares write no wait")
	var blocked := _spk("w0:t0:p2")
	var now := office.hud.strategic.model().now_msec
	var wait := OfficeAttention.wait_text(StateLog.wait_of(office.fleet.state_log().track(blocked), now))
	_eq(plan.wait_drawn(blocked), "", "none drawn")
	var pane := office.frame.pane(blocked)
	var place := "%s / %s · %s" % [pane.workspace_label, pane.tab_label, _pane_label(pane)]
	var asks := office.art.state(ArtContract.STATE_BLOCKED).label
	var tip := "CLAUDE · %s · %s\n%s" % [asks, wait, place]
	_eq(plan.tooltip_at(plan.seat_rect(blocked).get_center()), tip, "blocked, in the pack's word")
	var done := _spk("w0:t0:p3")
	_check(plan.tooltip_at(plan.seat_rect(done).get_center()).begins_with("CLAUDE · UNREAD\n"), "done is UNREAD")
	var starting := _spk("w0:t0:p1")
	_check(plan.tooltip_at(plan.seat_rect(starting).get_center()).begins_with("CLAUDE · STARTING\n"), "a start")
	var square := plan.seat_rect(blocked)
	_eq(plan.tooltip_at(square.position - Vector2(1, 1)), "", "nothing between squares")
	# Through the real pointer: the viewport asks the plan for it.
	_eq(plan.get_tooltip(square.get_center()), plan.tooltip_at(square.get_center()), "the Control's own tooltip")
	_done(office)


## A dropped machine's floor keeps its squares, all dark, no wait on any of
## them (nobody is receiving that clock, invariant 4), the whole plan tinted
## like the frozen world; the header stays readable and names the state. A
## click still picks.
func test_a_stale_floor_is_dark_and_says_no_wait() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	_set_online(office, false)
	await _frames(2)
	_check(office.fleet.is_stale(LOCAL), "Local dropped")
	var plan := _plan(office)
	for key: String in plan.seat_keys():
		_eq(plan.looks().get(key, &""), &"WindowDark", "dark: " + key)
		_eq(plan.wait_drawn(key), "", "no wait: " + key)
	_check(plan.tooltip_at(plan.seat_rect(_spk("w0:t0:p2")).get_center()).begins_with("CLAUDE · OFFLINE\n"), "OFFLINE")
	_eq(plan.modulate, office.art.stale_tint, "tinted like the frozen world")
	var header: Control = office.hud.strategic.get_node("%Header")
	_eq(header.modulate, Color.WHITE, "the header is not")
	_check(office.hud.strategic.title_text().ends_with("OFFLINE"), "and says it: " + office.hud.strategic.title_text())
	await _click_square(office, _spk("w0:t3:p1"))
	_eq(office.picked_key, _spk("w0:t3:p1"), "a click still picks")
	_check(not office.hud.strategic_open(), "and closes it")
	_done(office)


# --- floors, machines, other panels ----------------------------------------------------


## PageDown and a FLOORS row with the view open: it stays open over the hidden
## world; a zone of this machine (PageDown, a row) pans the map under it and
## keeps it as it is, titled for the machine; a row of another machine's zone
## redraws it for that machine. (Zone captions and sections are the SPACES
## rail's step; a mezzanine was titled as its plate named it when a floor was
## a map of its own.)
func test_pgdn_and_a_floors_row_redraw_it_for_that_floor() -> void:
	var on_notes := _focused_on(worktrees, "notes:p1")
	on_notes.focused_workspace_id = "notes"
	on_notes.focused_tab_id = "notes:t1"
	var office := await _two_machine_office(on_notes, WIDE)
	await _office_key(office, KEY_S)
	var first := office.navigator.current_zone(office.frame)
	var title := office.hud.strategic.title_text()
	_eq(title, "@ LOCAL", "titled for the machine, among several")
	var squares := _plan(office).seat_keys()
	await _office_key(office, KEY_PAGEDOWN)
	_check(office.navigator.current_zone(office.frame) != first, "PageDown pans to another zone")
	_check(office.hud.strategic_open(), "the view stays open")
	_check(not office.world.visible, "over a world still hidden")
	_eq(office.hud.strategic.title_text(), title, "the same machine, the same title")
	_eq(_plan(office).seat_keys(), squares, "and the same squares")
	_same_squares(office, "after PageDown")
	var mezzanine := ""
	for key: Variant in office.hud.spaces.row_keys():
		var ref := office.frame.find_zone(str(key))
		if ref != null and not ref.zone_model.mezzanine_of.is_empty():
			mezzanine = str(key)
			break
	_check(not mezzanine.is_empty(), "the fixture has a mezzanine to click")
	await _visit_floor(office, mezzanine)
	await _frames(2)
	_eq(office.navigator.current_zone(office.frame), mezzanine, "its FLOORS row pans to it")
	_check(office.hud.strategic_open(), "still open")
	_eq(office.hud.strategic.title_text(), title, "a row of this machine keeps the title")
	_same_squares(office, "on the mezzanine")
	await _visit_floor(office, HerdrFleet.pane_key(BEE, "hive"))
	await _frames(2)
	_eq(office.navigator.shown_key, BEE, "a row of bee's shows bee's map")
	_check(office.hud.strategic_open(), "still open")
	_eq(office.hud.strategic.title_text(), "@ BEE", "titled for that machine")
	_eq(Array(_plan(office).seat_keys()), [HerdrFleet.pane_key(BEE, "hive:p1")], "its squares")
	_same_squares(office, "on bee's map")
	_done(office)


## With more than one machine the title names whose floor it is, and a machine
## that is not answering says how it is; its squares are dark. (The model, as
## the office builds it from a frame of two machines.)
func test_several_machines_title_names_the_machine() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var machines: Array[MachineView] = [
		MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(fixture), false),
		MachineView.new("socket:bee", "bee", HerdrSnapshot.from_wire(fixture), false),
	]
	var frame := OfficeProjection.frame(machines, art.state_names())
	_check(frame.several_machines(), "two machines")
	var found := frame.building_of("socket:bee")
	var rules := FloorLayoutPolicy.new()
	rules.actor_footprint = PixelPerson.footprint()
	rules.actor_draw_rect = PixelPerson.drawing_rect(art.people)
	var plan := OfficeFloorLayout.plan(found.map, null, rules).plan
	var live := StrategicModel.of(plan, found, true, MachineLiveness.State.LIVE, StateLog.new(), "", 0)
	_eq(live.title, "@ BEE", "the machine's own label, among several")
	_eq(
		live.sections.map(func(section: StrategicModel.Section) -> String: return section.key),
		OfficeNavigator.section(found.zones).map(func(zone: ZoneModel) -> String: return zone.key),
		"a section per zone of that machine, in the rail's order"
	)
	_eq(
		live.sections.map(func(section: StrategicModel.Section) -> String: return section.caption),
		found.zones.map(func(zone: ZoneModel) -> String: return OfficeZoneSign.words(zone)),
		"captioned with the words on each zone's sign"
	)
	_eq(
		Array(live.section_rows()).reduce(func(sum: int, rows: int) -> int: return sum + rows, 0),
		live.row_capacities().size(),
		"every row in a section"
	)
	_eq(live.state_text, "", "a live machine says nothing more")
	_check(not live.stale, "and is not stale")
	var alone := StrategicModel.of(plan, found, false, MachineLiveness.State.LIVE, StateLog.new(), "", 0)
	_eq(alone.title, "BEE", "one machine: its label, no `@`")
	var gone := StrategicModel.of(plan, found, true, MachineLiveness.State.OFFLINE, StateLog.new(), "", 0)
	_eq(gone.state_text, "OFFLINE", "a dropped machine says so")
	_check(gone.stale, "and is stale")
	for table in gone.tables:
		for seat in table.seats:
			_eq(seat.look, &"WindowDark", "dark: " + seat.key)
			_eq(seat.wait, "", "no wait: " + seat.key)
	var coming := StrategicModel.of(plan, found, true, MachineLiveness.State.CONNECTING, StateLog.new(), "", 0)
	_eq(coming.state_text, "CONNECTING", "one still connecting says so")


## The OVERVIEW opens over it (`O`, and PANES), and closing the overview goes
## back to the view, the world still hidden; only `S` then shows the world.
func test_the_overview_over_it_leaves_the_world_hidden() -> void:
	var office := await _live_office(fixture, WIDE)
	await _office_key(office, KEY_S)
	await _office_key(office, KEY_O)
	_check(office.hud.overview_open(), "O opens the overview over it")
	_check(office.hud.strategic_open(), "the view is still there under it")
	office.refresh()
	_check(not office.world.visible, "a refresh keeps the world hidden")
	await _office_key(office, KEY_O)
	_check(not office.hud.overview_open(), "O closes the overview")
	_check(office.hud.strategic_open(), "back to the view")
	_check(not office.world.visible, "and the world stays hidden")
	await _office_key(office, KEY_S)
	_check(office.world.visible, "S shows the world")
	_done(office)


## No `S` under the terminal monitor (it takes every key), the OVERVIEW (it
## takes the office's keys), or while a text field has the keyboard (typing).
func test_no_s_under_the_monitor_the_overview_or_a_text_field() -> void:
	var office := await _live_office(fixture, WIDE)
	await _office_key(office, KEY_O)
	await _office_key(office, KEY_S)
	_check(not office.hud.strategic_open(), "S under the overview does nothing")
	await _office_key(office, KEY_O)
	await _office_key(office, KEY_M)
	_check(office.hud.monitor_open(), "M opens the monitor")
	await _office_key(office, KEY_S)
	_check(not office.hud.strategic_open(), "S under the monitor does nothing")
	var close: Control = office.hud.monitor.get_node("%CloseButton")
	await _press(close)
	await _frames(2)
	_check(not office.hud.monitor_open(), "the monitor closes")
	var strip: Control = office.hud.get_node("%DrawerTab")
	await _press(strip)
	await _frames(2)
	var filter: LineEdit = office.hud.agent_list.get_node("%Filter")
	await _press(filter)
	_check(filter.has_focus(), "the filter has the keyboard")
	var typed := InputEventKey.new()
	typed.keycode = KEY_S
	typed.unicode = "s".unicode_at(0)
	typed.pressed = true
	await _parsed(typed)
	typed.pressed = false
	await _parsed(typed)
	_check(not office.hud.strategic_open(), "S in the filter is typing")
	_eq(filter.text, "s", "typed there")
	_done(office)


## The lens never comes on while the view is open, and `S` taken while `L` is
## held turns the lens off and says STRATEGIC; closing the view says the pack.
func test_no_lens_while_open() -> void:
	var office := await _live_office(fixture, WIDE)
	var theme := office.hud.bar.theme_line()
	await _office_key(office, KEY_S)
	await _hold_l(true)
	_check(not office.lens.held, "no lens under the strategic view")
	_eq(office.hud.bar.theme_line(), STRATEGIC_LINE, "the bar still says STRATEGIC")
	await _hold_l(false)
	await _office_key(office, KEY_S)
	await _hold_l(true)
	_check(office.lens.held, "the lens, the view closed")
	await _office_key(office, KEY_S)
	await _frames(2)
	_check(not office.lens.held, "S turns the lens off")
	_check(office.hud.strategic_open(), "and opens the view")
	_eq(office.hud.bar.theme_line(), STRATEGIC_LINE, "the bar says STRATEGIC, not the lens")
	await _office_key(office, KEY_S)
	await _frames(2)
	_check(not office.lens.held, "L still down since then does not count")
	_eq(office.hud.bar.theme_line(), theme, "the pack's name again")
	await _hold_l(false)
	_done(office)


## `N`, `‹ ›` and a list row move the selection with the view open: it stays
## open, and the corners move to the pane picked.
func test_n_keeps_it_open_and_moves_the_corners() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	_eq(plan.picked_key(), office.navigator.active_key, "the corners on the selected pane")
	await _office_key(office, KEY_N)
	_check(office.hud.strategic_open(), "N leaves it open")
	_eq(office.frame.pane(office.picked_key).state, "blocked", "N picks somebody blocked")
	_eq(plan.picked_key(), office.picked_key, "the corners follow")
	var after_n := office.picked_key
	var card := office.hud.inspector
	if not office.hud.card_compact():
		await _tap(KEY_ESCAPE)
	var on: Button = card.get_node("%StepOn")
	await _press(on)
	await _frames(2)
	_check(office.picked_key != after_n, "› picks the next in NEXT's queue")
	_check(office.hud.strategic_open(), "still open")
	_eq(plan.picked_key(), office.picked_key, "the corners follow ›")
	var strip: Control = office.hud.get_node("%DrawerTab")
	await _press(strip)
	await _frames(3)
	var target := _spk("w0:t4:p4")
	var row := office.hud.agent_list.row_for(target)
	_check(row != null, "a row for w0:t4:p4")
	if row != null:
		var list_scroll: ScrollContainer = office.hud.agent_list.get_node("%Scroll")
		list_scroll.ensure_control_visible(row)
		await _frames(2)
		await _press(row)
		await _frames(2)
		_eq(office.picked_key, target, "a list row picks")
		_check(office.hud.strategic_open(), "and the view stays open")
		_eq(plan.picked_key(), target, "the corners on it")
	_done(office)


## Hovering a list row about a pane on the shown map dashes its square, in
## whichever zone it sits.
func test_hovering_a_list_row_dashes_its_square() -> void:
	var office := await _live_office(fixture, WIDE)
	var strip: Control = office.hud.get_node("%DrawerTab")
	await _press(strip)
	await _frames(3)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	var draws := plan.draws
	var row := office.hud.agent_list.row_for(_pk("api:p1"))
	await _hover(row.get_global_rect().get_center())
	_eq(plan.pointed_key(), _pk("api:p1"), "its square is dashed")
	_check(plan.draws > draws, "drawn again for it")
	var other := office.hud.agent_list.row_for(_pk("web:p1"))
	await _hover(other.get_global_rect().get_center())
	_eq(plan.pointed_key(), _pk("web:p1"), "a pane in another zone of this map dashes its own square")
	var web := office.hud.spaces.row_for(office.frame.zone_of(_pk("web:p1")))
	_eq(web.theme_type_variation, &"SpaceRow", "and marks no FLOORS row")
	await _hover(office.hud.world_rect().get_center())
	_eq(plan.pointed_key(), "", "leaving takes the dash away")
	_done(office)


## A zoom with the view open rebuilds no node, HUD or world; a smaller room
## (the window shrinking) refits the squares, still covering the world rect.
func test_zoom_while_open_rebuilds_nothing_and_refits() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	var hud_ids := _hud_nodes(office)
	var world_ids := _world_ids(office)
	var zoom := office.zoom
	await _office_key(office, KEY_EQUAL)
	await _frames(2)
	_eq(office.zoom, zoom + OfficeScene.ZOOM_STEP, "= zoomed in")
	_check(office.hud.strategic_open(), "still open")
	_eq(_hud_nodes(office), hud_ids, "not one HUD node rebuilt")
	_eq(_world_ids(office), world_ids, "nor a world node")
	var plan := _plan(office)
	var cell := plan.cell()
	office.test_screen = SMALL
	office.refresh()
	await _frames(2)
	_check(plan.cell() < cell, "a smaller room, smaller cells: %d from %d" % [plan.cell(), cell])
	_eq(office.hud.strategic.get_global_rect(), office.hud.world_rect(), "still over the world rect")
	_eq(_hud_nodes(office), hud_ids, "and still no node rebuilt")
	_done(office)


## With the view open the arrows and the wheel never pan the hidden world; the
## wheel scrolls the schematic when it is taller than its room.
func test_arrows_and_wheel_never_pan_the_hidden_world() -> void:
	var office := await _live_office(_stress(50), SMALL)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	var scroll: ScrollContainer = office.hud.strategic.get_node("%Scroll")
	var pan := office.camera.pan
	await _hold_key(KEY_RIGHT, 0.4)
	await _hold_key(KEY_DOWN, 0.4)
	_eq(office.camera.pan, pan, "the arrows pan nothing")
	_check(plan.scrolls(), "four hundred panes in the small room scroll")
	var at := _square_point(office, _spk("w0:t0:p0"))
	var before := scroll.scroll_vertical
	await _wheel_at(at, MOUSE_BUTTON_WHEEL_DOWN)
	_check(scroll.scroll_vertical > before, "the wheel scrolls the schematic")
	_eq(office.camera.pan, pan, "and never the camera")
	var header: Control = office.hud.strategic.get_node("%Header")
	await _wheel_at(header.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	_eq(office.camera.pan, pan, "over the header neither")
	_done(office)
	var wide := await _live_office(_stress(), WIDE)
	await _office_key(wide, KEY_S)
	_check(not _plan(wide).scrolls(), "eighty in the wide room: no scroll")
	var still := wide.camera.pan
	await _wheel_at(_square_point(wide, _spk("w0:t0:p0")), MOUSE_BUTTON_WHEEL_DOWN)
	var box := _plan(wide).table_rect("w0:t0")
	await _wheel_at(_plan(wide).get_global_rect().position + box.end + Vector2(3, 3), MOUSE_BUTTON_WHEEL_UP)
	_eq(wide.camera.pan, still, "a wheel with nothing to scroll pans nothing either")
	_done(wide)


## The fit, pure (StrategicLayout.fit()): the largest cell of the scene's
## ladder at which the plan's rows fit the room, and at that cell the fewest
## newspaper columns; eight and a scroll when nothing fits. Pinned for the
## stress floors (80 and 400 panes) in the room the view has at 2x (1920x960,
## where the compact panel is an 80-high card) and at 4x / the minimum
## (480x320 logical either way, its one line). The stress map is one zone: one
## captioned section, its caption repeated at the top of every further column.
## The caption band is 9 units, which is what keeps every cell and column count
## the rows had without one (two of the four rooms have exactly 9 to spare).
func test_the_stress_fit_at_2x_4x_and_min() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var hud: OfficeHud = OfficeScene.HUD_SCENE.instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	var plan: OfficeStrategicPlan = hud.strategic.get_node("%Plan")
	_eq(Array(plan.cells), [32, 24, 16, 12, 8], "the scene's ladder")
	var rules := plan.rules()
	_eq([rules.pad, rules.gap, rules.caption, rules.divider, rules.ring], [4, 8, 12, 2, 2], "the theme's measures")
	_eq(rules.section, 9, "and its section caption band")
	var rooms := {}
	for screen: Vector2 in [WIDE, SMALL]:
		hud.fit(screen)
		rooms[screen] = hud.strategic.room_for(hud.world_rect().size)
	_eq(rooms[WIDE], Vector2(804, 271), "the room at 2x, above the card")
	_eq(rooms[SMALL], Vector2(324, 163), "the room at 4x and the minimum")
	var eighty := _rows_of(10)
	var four_hundred := _rows_of(50)
	var cases := [
		[eighty, WIDE, 32, 5, false],
		[eighty, SMALL, 12, 4, false],
		[four_hundred, WIDE, 12, 10, false],
		[four_hundred, SMALL, 8, 6, true],
	]
	for each: Array in cases:
		var rows: Array[PackedInt32Array] = each[0]
		var room: Vector2 = rooms[each[1]]
		var fit := StrategicLayout.fit(rows, room, rules, PackedInt32Array([rows.size()]))
		var what := "%d rows in %s" % [rows.size(), room]
		_eq([fit.cell, fit.columns, fit.scrolls], [each[2], each[3], each[4]], what)
		_eq(fit.headings.size(), fit.columns, what + ": the section's caption at the top of each column")
		for index in fit.headings.size():
			_eq(fit.headings[index].continued, index > 0, what + ": repeated, with its mark, after the first")
			_eq(fit.headings[index].rect.position.y, 0.0, what + ": at its column's top")
		var bare := StrategicLayout.fit(rows, room, rules)
		_eq(
			[bare.cell, bare.columns, bare.scrolls],
			[fit.cell, fit.columns, fit.scrolls],
			what + ": as without captions"
		)
		_eq(bare.headings.size(), 0, what + ": rows given without sections have no caption band")
		if not fit.scrolls:
			_check(fit.size.x <= room.x and fit.size.y <= room.y, "fits: %s in %s" % [fit.size, room])
		else:
			_check(fit.size.x <= room.x and fit.size.y > room.y, "as wide as fits and taller: " + str(fit.size))
	# The stress map as the office plans it at 2x: two lanes, its zone as wide
	# as both (18 inner cells), three pods of four desks (5 cells) to a row, four
	# rows (the long tables took a row each, ten rows: the pure fits above keep
	# that shape of input).
	var office := await _live_office(_stress(), WIDE)
	var laid := office.layout_plan()
	_eq([laid.lanes, laid.zones[0].lanes], [2, 2], "a zone of the map's two lanes")
	var per_row: Array[int] = []
	for band in laid.zones[0].rows:
		per_row.append(band.desks.size())
	_eq(per_row, [3, 3, 3, 1], "four rows of pods")
	print("STRATEGIC stress render_bounds %s" % laid.render_bounds)
	_done(office)
	hud.queue_free()


## An empty map (a machine with no workspace) says so and draws no square.
func test_a_lobby_says_no_desks() -> void:
	var empty: Dictionary = fixture.duplicate(true)
	for field: String in ["workspaces", "tabs", "panes", "layouts", "agents"]:
		empty[field] = []
	for field: String in ["focused_workspace_id", "focused_tab_id", "focused_pane_id"]:
		empty.erase(field)
	var office := await _live_office(empty, WIDE)
	await _office_key(office, KEY_S)
	_check(office.hud.strategic_open(), "S opens it on an empty map too")
	var said: Label = office.hud.strategic.get_node("%Empty")
	_check(said.visible, "it says there are no desks")
	_eq(said.text, "No desks on this machine", "in these words")
	var scroll: Control = office.hud.strategic.get_node("%Scroll")
	_check(not scroll.visible, "and draws no plan")
	_eq(_plan(office).seat_keys().size(), 0, "no square")
	_feed(office, fixture)
	await _frames(2)
	_check(not said.visible, "a map with desks draws them")
	_check(scroll.visible, "its plan")
	_done(office)


## Drawn again only when what it shows changes: a pick, the pointer, a state,
## and once a second while a wait is written in a square; never for a refresh
## that changes nothing, and never on the tick when no square writes a wait.
func test_it_redraws_only_on_change_and_each_second_while_a_wait_shows() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	await _frames(3)
	var plan := _plan(office)
	var draws := plan.draws
	office.refresh()
	office.refresh()
	await _frames(3)
	_eq(plan.draws, draws, "a refresh that changes nothing draws nothing")
	await _seconds(2.2)
	var ticked := plan.draws - draws
	_check(ticked >= 1 and ticked <= 3, "about once a second while waits show: %d" % ticked)
	var quiet := _stress(10, 8, ["working", "idle", "done", "working"])
	_feed(office, quiet)
	await _frames(3)
	_check(plan.draws > draws + ticked, "a change of state draws")
	var settled := plan.draws
	await _seconds(2.2)
	_eq(plan.draws, settled, "no wait written: the tick draws nothing")
	await _office_key(office, KEY_N)
	await _frames(2)
	_check(plan.draws > settled, "a new pick draws")
	_done(office)


## The world's desks are never clicked through a square: the view takes the
## click, picks the square's pane, and the desk under it is not picked.
func test_a_desk_under_a_square_is_never_picked_through_it() -> void:
	var office := await _live_office(_stress(), WIDE)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	# Pan the hidden world until some desk answers a click right under a square
	# of another pane: only the pan's height moves, the floor being as wide as
	# its room.
	var room := office.camera.free_rect()
	var reach := (office.camera.world_size - room.size).max(Vector2.ZERO)
	var square := ""
	var desk := ""
	var at := Vector2.ZERO
	for key: String in office.floor_view.seats:
		var target := _desk_target(office, key).get_center() - office.camera.position
		for other: String in plan.seat_keys():
			var drawn := plan.seat_rect(other)
			drawn.position += plan.get_global_rect().position
			var lift := _desk_target(office, key).get_center().y - drawn.get_center().y
			var span := Vector2(drawn.position.x, drawn.end.x)
			if other != key and target.x > span.x + 2 and target.x < span.y - 2 and lift > 0 and lift < reach.y:
				square = other
				desk = key
				at = Vector2(target.x, drawn.get_center().y)
				office.camera.pan = Vector2(office.camera.pan.x, lift)
				break
		if not square.is_empty():
			break
	_check(not square.is_empty(), "a desk that can be panned under a square")
	if square.is_empty():
		_done(office)
		return
	await _frames(3)
	_check(_desk_target(office, desk).has_point(at + office.camera.position), desk + "'s desk is right under the click")
	_check(plan.seat_rect(square).has_point(at - plan.get_global_rect().position), "and so is %s's square" % square)
	await _click(at)
	await _frames(3)
	_eq(office.picked_key, square, "the square's pane is picked")
	_check(not office.hud.strategic_open(), "and the view closed")
	await _frames(3)
	_eq(office.picked_key, square, desk + "'s desk heard nothing")
	_done(office)


# --- sections -------------------------------------------------------------------


## Every zone of the map is a section: a caption with the words on its sign
## (`2 WEB`), in the SPACES rail's order, over that zone's pods and no other's.
## A caption is plain paper text, not the zone's accent; hovering it, by a real
## pointer, says what the sign's tooltip says; and a real click on one picks
## nothing and leaves the view open.
func test_each_zone_is_a_captioned_section() -> void:
	var office := await _live_office(fixture, WIDE)
	await _office_key(office, KEY_S)
	var plan := _plan(office)
	var rail := office.hud.spaces.row_keys()
	_eq(Array(plan.section_keys()), rail, "a section per zone, in the rail's order")
	_eq(
		Array(plan.captions_drawn()),
		["1 API", "2 WEB", "3 INFRA", "4 NOTES", "5 数据 PIPELINE"],
		"captioned with the words on each zone's sign"
	)
	_eq(plan.get_theme_color(&"section_caption", &"Strategic"), office.art.color(ArtContract.PAPER), "in plain paper")
	for accent: StringName in ArtContract.ACCENTS:
		var hue := office.art.color(accent)
		_check(plan.get_theme_color(&"section_caption", &"Strategic") != hue, "never an accent: %s" % accent)
	var model := office.hud.strategic.model()
	var bands: Array[Rect2] = []
	for section in model.sections:
		var found := office.frame.find_zone(section.key)
		var caption := plan.section_rects(section.key)
		_eq(caption.size(), 1, "%s: one caption, the room holding its section whole" % section.caption)
		var band := caption[0]
		bands.append(band)
		_eq(band.size.y, 9.0, "%s: the caption band" % section.caption)
		_check(not section.tables.is_empty(), "%s: with its pods" % section.caption)
		for table in section.tables:
			var box := plan.table_rect(table.key)
			_check(box.position.y >= band.end.y, "%s: %s under its caption" % [section.caption, table.label])
			var across := box.position.x >= band.position.x and box.end.x <= band.end.x
			_check(across, "%s: %s in its caption's column" % [section.caption, table.label])
			for seat in table.seats:
				_eq(office.frame.zone_of(seat.key), section.key, "%s: only its own panes" % section.caption)
		var tip := OfficeQuestionTips.sign_text(found)
		_eq(
			plan.tooltip_at(band.get_center()),
			tip,
			"%s: hovering its caption says its sign's tooltip" % section.caption
		)
		_eq(plan.get_tooltip(band.get_center()), tip, "%s: the Control's own tooltip" % section.caption)
	for index in bands.size():
		for other in range(index + 1, bands.size()):
			_check(not bands[index].intersects(bands[other]), "captions apart: %s, %s" % [bands[index], bands[other]])
	var picked := office.picked_key
	await _click(plan.get_global_rect().position + bands[1].position + Vector2(8, 4))
	await _frames(2)
	_check(office.hud.strategic_open(), "a click on a caption leaves the view open")
	_eq(office.picked_key, picked, "and picks nothing")
	_done(office)


## Pure (StrategicLayout.fit()): a section that fits a column is kept whole, in
## the column it starts in when what is left of that holds it, else in the next;
## only one taller than the room is split, at a row boundary, its caption
## repeated (`continued`) at the top of every column it runs on into. A column
## is never narrower than a caption in it.
func test_a_section_splits_only_when_taller_than_the_room() -> void:
	var rules := StrategicLayout.Rules.new()
	rules.cells = PackedInt32Array([8])
	rules.pad = 4
	rules.gap = 8
	rules.caption = 12
	rules.divider = 2
	rules.ring = 2
	rules.section = 9
	# One row: a 12 caption over a 26 box. A section of n rows: 9 + 38n + 8(n - 1).
	var two := PackedInt32Array([2, 2])
	var whole := StrategicLayout.fit(_rows_of(4), Vector2(400, 200), rules, two)
	_eq(
		[whole.columns, whole.per_column, whole.scrolls],
		[1, 4, false],
		"two sections of two rows in a tall room: one column"
	)
	_eq(
		whole.headings.map(func(h: StrategicLayout.Heading) -> Array: return [h.section, h.continued]),
		[[0, false], [1, false]],
		""
	)
	_eq(
		[whole.headings[0].rect.position.y, whole.headings[1].rect.position.y],
		[0.0, 101.0],
		"the second 8 under the first"
	)
	_eq(whole.box(0, 0).position.y, 21.0, "a row: its caption band under the section's, then its box")
	_eq(whole.box(2, 0).position.y, 122.0, "the second section's first row under its own caption")
	# 150 high: a section (93) fits, both (194) do not: the second moves whole.
	var kept := StrategicLayout.fit(_rows_of(4), Vector2(400, 150), rules, two)
	_eq(
		[kept.columns, kept.per_column, kept.scrolls],
		[2, 2, false],
		"a room for one section and a row more: two columns"
	)
	_eq(
		kept.headings.map(func(h: StrategicLayout.Heading) -> Array: return [h.section, h.continued]),
		[[0, false], [1, false]],
		"neither split"
	)
	_eq(kept.box(2, 0).position, Vector2(48, 21), "the second section starts the next column, whole")
	_eq(kept.headings[1].rect.position, Vector2(48, 0), "under its caption at that column's top")
	_eq(
		[kept.box(1, 0).position, kept.box(3, 0).position],
		[Vector2(0, 67), Vector2(48, 67)],
		"its rows down their column"
	)
	# One section of five rows, a room that holds two under a caption: split.
	var split := StrategicLayout.fit(_rows_of(5), Vector2(400, 100), rules, PackedInt32Array([5]))
	_eq([split.columns, split.per_column, split.scrolls], [3, 2, false], "five rows, two to a column")
	_eq(
		split.headings.map(func(h: StrategicLayout.Heading) -> Array: return [h.section, h.continued]),
		[[0, false], [0, true], [0, true]],
		"its caption repeated, marked, on each further column"
	)
	_eq(
		[split.box(0, 0).position, split.box(2, 0).position, split.box(4, 0).position],
		[Vector2(0, 21), Vector2(48, 21), Vector2(96, 21)],
		"split at row boundaries"
	)
	# A short section after a split one shares the last column when it fits there.
	var mixed := StrategicLayout.fit(_rows_of(4), Vector2(400, 150), rules, PackedInt32Array([3, 1]))
	_eq(
		mixed.headings.map(func(h: StrategicLayout.Heading) -> Array: return [h.section, h.continued]),
		[[0, false], [1, false]],
		"three rows fit a 150 room whole"
	)
	_eq(mixed.columns, 2, "and the next section, which no longer fits under it, takes the next column")
	var tight := StrategicLayout.fit(_rows_of(4), Vector2(400, 102), rules, PackedInt32Array([3, 1]))
	_eq(
		tight.headings.map(func(h: StrategicLayout.Heading) -> Array: return [h.section, h.continued]),
		[[0, false], [0, true], [1, false]],
		"three rows in a 102 room: split, its last row and the next section share a column"
	)
	_eq(
		[tight.columns, tight.box(2, 0).position, tight.box(3, 0).position],
		[2, Vector2(48, 21), Vector2(48, 76)],
		"the next section under the run-on row"
	)
	# A caption wider than its rows widens the column, and the next one starts past it.
	var wide := StrategicLayout.fit(_rows_of(4), Vector2(400, 150), rules, two, PackedFloat32Array([90.0, 10.0]))
	_eq(wide.headings[0].rect.size.x, 90.0, "the column is as wide as its caption")
	_eq(wide.box(2, 0).position.x, 98.0, "and the next column starts a gap past it")
	_eq(wide.size.x, 138.0, "the whole schematic: 90, the gap, a 40 box")


## A SPACES row of the shown machine picked while the view is open scrolls the
## schematic to that zone's section: its caption comes into sight, the same
## machine's squares stay as they are, and the view stays open.
func test_a_rail_click_while_open_scrolls_to_its_section() -> void:
	var office := await _live_office(_many_zones(40), SMALL)
	await _office_key(office, KEY_S)
	await _frames(3)
	var plan := _plan(office)
	_check(plan.scrolls(), "forty zones in the small room: the schematic scrolls")
	var scroll: ScrollContainer = office.hud.strategic.get_node("%Scroll")
	var last := _pk("z39")
	_eq(scroll.scroll_vertical, 0, "it opens at the top")
	_check(not _caption_seen(office, last), "the last zone's caption is out of sight below")
	var title := office.hud.strategic.title_text()
	var squares := plan.seat_keys()
	var draws := plan.draws
	await _visit_floor(office, last)
	await _frames(3)
	_check(office.hud.strategic_open(), "a SPACES row click leaves the view open")
	_check(scroll.scroll_vertical > 0, "and scrolls the schematic: %d" % scroll.scroll_vertical)
	_check(_caption_seen(office, last), "that zone's caption is in sight")
	_eq([office.hud.strategic.title_text(), plan.seat_keys()], [title, squares], "the same machine, the same squares")
	_eq(plan.draws, draws, "nothing drawn again for it")
	await _visit_floor(office, _pk("z0"))
	await _frames(3)
	_check(_caption_seen(office, _pk("z0")), "the first zone's row scrolls back to its caption")
	_eq(scroll.scroll_vertical, 0, "at the top")
	# PageDown, the same navigation by key, scrolls to its zone's section too.
	for step in 39:
		await _office_key(office, KEY_PAGEDOWN)
	await _frames(3)
	_eq(office.navigator.current_zone(office.frame), last, "PageDown to the last zone")
	_check(_caption_seen(office, last), "its caption in sight")
	_done(office)


# --- helpers ------------------------------------------------------------------


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## A stress pane's key: Local's, as the stress floor has only Local.
func _spk(pane_id: String) -> String:
	return _pk(pane_id)


func _plan(office: OfficeDouble) -> OfficeStrategicPlan:
	return office.hud.strategic.get_node("%Plan")


## The stress floor from snapshot_floors.json's own records: one workspace
## `stress 0` of `tabs` tabs `tab N` of `per_tab` claude agents in the
## generator's state cycle, two to a layout column (far, near), as
## tools/gen_stress_fixture.py writes snapshot_stress80 (`tabs` 50: the 400).
func _stress(tabs := 10, per_tab := 8, states: Array[String] = STRESS_STATES) -> Dictionary:
	var workspace: Dictionary = _record(fixture, "workspaces", "workspace_id", "api").duplicate(true)
	workspace.erase("worktree")
	workspace.merge({"workspace_id": "w0", "number": 1, "label": "stress 0", "active_tab_id": "w0:t0"}, true)
	var tab_record := _record(fixture, "tabs", "tab_id", "api:t1")
	var pane_record := _record(fixture, "panes", "pane_id", "api:p1")
	var agent_record := _record(fixture, "agents", "pane_id", "api:p1")
	var tab_list: Array = []
	var pane_list: Array = []
	var layout_list: Array = []
	var agent_list: Array = []
	var result := {
		"version": fixture.version,
		"protocol": fixture.protocol,
		"focused_workspace_id": "w0",
		"focused_tab_id": "w0:t0",
		"focused_pane_id": "w0:t0:p0",
		"workspaces": [workspace],
		"tabs": tab_list,
		"panes": pane_list,
		"layouts": layout_list,
		"agents": agent_list,
	}
	var count := 0
	for t in tabs:
		var tab_id := "w0:t%d" % t
		var tab: Dictionary = tab_record.duplicate(true)
		tab.merge({"tab_id": tab_id, "workspace_id": "w0", "number": t + 1, "label": "tab %d" % t}, true)
		tab_list.append(tab)
		var slots: Array = []
		for p in per_tab:
			var pane_id := "%s:p%d" % [tab_id, p]
			var fields := {
				"pane_id": pane_id,
				"workspace_id": "w0",
				"tab_id": tab_id,
				"terminal_id": "term-" + pane_id,
				"agent": "claude",
				"agent_status": states[count % states.size()],
				"terminal_title_stripped": "x",
			}
			count += 1
			var pane: Dictionary = pane_record.duplicate(true)
			pane.merge(fields, true)
			pane_list.append(pane)
			var agent: Dictionary = agent_record.duplicate(true)
			agent.merge(fields, true)
			agent_list.append(agent)
			var rect := {"x": floori(p / 2.0) * 80, "y": 0 if p % 2 == 0 else 40, "width": 80, "height": 40}
			slots.append({"pane_id": pane_id, "rect": rect})
		layout_list.append({"workspace_id": "w0", "tab_id": tab_id, "panes": slots})
	return result


## The record of `snapshot[list]` whose `field` is `value`.
func _record(snapshot: Dictionary, list: String, field: String, value: String) -> Dictionary:
	for each: Dictionary in _list(snapshot, list):
		if str(each.get(field, "")) == value:
			return each
	_fail("no %s with %s %s" % [list, field, value])
	return {}


## Whether the caption of zone `key`'s section is inside the schematic's
## scrolled room.
func _caption_seen(office: OfficeDouble, key: String) -> bool:
	var scroll: ScrollContainer = office.hud.strategic.get_node("%Scroll")
	var band := _plan(office).section_rects(key)[0]
	return band.position.y >= scroll.scroll_vertical and band.end.y <= scroll.scroll_vertical + scroll.size.y


## `count` workspaces `z0`.. of one tab of two working agents each, herdr's
## focus in the first: a map of many small zones.
func _many_zones(count: int) -> Dictionary:
	var raw := {"workspaces": [], "tabs": [], "panes": [], "layouts": [], "focused_pane_id": "z0:t:p0"}
	for zone in count:
		var workspace := "z%d" % zone
		var tab := workspace + ":t"
		_list(raw, "workspaces").append({"workspace_id": workspace, "number": zone + 1, "label": workspace})
		_list(raw, "tabs").append({"workspace_id": workspace, "tab_id": tab, "number": 1, "label": "t"})
		for index in 2:
			var pane := "%s:p%d" % [tab, index]
			var record := {"workspace_id": workspace, "tab_id": tab, "pane_id": pane, "terminal_id": "terminal-" + pane}
			record.merge({"agent": "claude", "agent_status": "working"})
			_list(raw, "panes").append(record)
	return raw


## The seated panes of the shown map section by section: the rail's order of
## zones, each zone's pod rows by index, a row's pods left to right, far seats
## then near ones, columns left to right.
func _section_order(office: OfficeDouble) -> Array:
	var expected: Array = []
	var layout := office.layout_plan()
	for zone_key: String in office.hud.spaces.row_keys():
		var placed := layout.zone(zone_key)
		if placed == null:
			continue
		var rows := placed.rows.duplicate()
		rows.sort_custom(func(a: RowPlan, b: RowPlan) -> bool: return a.index < b.index)
		for band: RowPlan in rows:
			var desks := band.desks.duplicate()
			desks.sort_custom(func(a: DeskPlacement, b: DeskPlacement) -> bool: return a.origin.x < b.origin.x)
			for desk: DeskPlacement in desks:
				for side: String in OfficeTable.SIDES:
					var seats: Array[SeatPlacement] = []
					for seat in desk.seats:
						if seat.side == side and office.frame.pane(seat.pane_key) != null:
							seats.append(seat)
					seats.sort_custom(func(a: SeatPlacement, b: SeatPlacement) -> bool: return a.column < b.column)
					for seat in seats:
						expected.append(seat.pane_key)
	return expected


## `count` plan rows of one table of four columns, the stress floors' shape.
func _rows_of(count: int) -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	for _row in count:
		rows.append(PackedInt32Array([4]))
	return rows


## The viewport point in the middle of pane `key`'s square.
func _square_point(office: OfficeDouble, key: String) -> Vector2:
	var plan := _plan(office)
	return plan.get_global_rect().position + plan.seat_rect(key).get_center()


## A real click on pane `key`'s square, through the window's input.
func _click_square(office: OfficeDouble, key: String) -> void:
	var at := _square_point(office, key)
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	await _frames(2)


## Whether the desk of `key` answers a click inside the world rect now.
func _desk_on_screen(office: OfficeDouble, key: String) -> bool:
	var seat := office.floor_view.seat(key)
	if seat == null:
		return false
	var target := seat.node.target_rect()
	var shown := Rect2(target.position - office.camera.position, target.size)
	return office.hud.world_rect().encloses(shown)


## The shown floor's squares are its seated panes, no more, no less.
func _same_squares(office: OfficeDouble, when: String) -> void:
	var keys := Array(_plan(office).seat_keys())
	keys.sort()
	var seats := office.floor_view.seats.keys()
	seats.sort()
	_eq(keys, seats, "a square per seated pane " + when)


## The tab key of the room pane `key` sits in on the shown map.
func _room_of(office: OfficeDouble, key: String) -> String:
	var found := office.frame.map_of(office.navigator.shown_key)
	for room in found.rooms:
		for pane in room.panes:
			if pane.key == key:
				return room.key
	_fail("no room holds " + key)
	return ""


## What the tooltip calls a pane: its label, or herdr's id without one.
func _pane_label(pane: PaneModel) -> String:
	return pane.label if not pane.label.is_empty() else pane.pane_id


## A key by position and code, pressed and let go, as the window delivers it:
## the card's actions (`card_*`) match physical keys.
func _tap(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		await _parsed(event)
	await _frames(1)


func _hold_l(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_L
	event.pressed = down
	await _parsed(event)
	await _frames(2)


## Hold `code` for `seconds` of frames, then let go.
func _hold_key(code: Key, seconds: float) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	await _parsed(event)
	await _seconds(seconds)
	event.pressed = false
	await _parsed(event)


## One wheel notch at `at`, as the window delivers it.
func _wheel_at(at: Vector2, button: MouseButton) -> void:
	for down: bool in [true, false]:
		var notch := _mouse_button(at, button, down)
		notch.factor = 1.0
		await _parsed(notch)
	await _frames(2)


## The pointer moved to `at` (viewport pixels), as the window reports it.
func _hover(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame
	await _frames(1)


## A real left click on the middle of `control`.
func _press(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


func _seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
