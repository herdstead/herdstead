extends "res://tools/office_test_base.gd"
## The left column's SPACES rail: one section per machine, its zones ascending
## with each worktree's mezzanine right after its source, the words on each
## zone's sign, a strip of windows per zone lit by its panes' states, a mark on
## the rows whose zone is in view (it follows panning), a row click panning to
## its zone, a heading click showing its machine's map, a stale machine dimmed
## with no lit window; each zone's sign; and the machine plate's problem line.
## Clicks, hovers, drags and keys go through real input. Run through
## run_tests.sh.
##
## godot --headless --path . --script tools/test_space_rail.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## (This suite took over from the FLOORS suite, tools/test_floors.gd, when the
## FLOORS minimap and its signposts became the SPACES rail and the edge arrows.
## The arrows' own cases are tools/test_edge_arrows.gd; a case here still
## clicks one where its subject is the rail or the navigation count.
## Never tools/test_spaces.gd: that is the New space / Worktree write suite.)

## A machine that never connects: a socket nobody listens on.
const FAR := "socket:far"


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("space-rail-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var text := FileAccess.get_file_as_string("res://tools/fixtures/snapshot_worktrees.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_worktrees.json")
		quit(2)
		return
	var file: Dictionary = parsed
	# herdstead (1) is the source of hud lane (1A) and data lane (1B); notes
	# (4) has no worktree; ops lane (5) is a worktree whose source is closed.
	fixture = _dict(file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "SPACE RAIL TESTS"


# --- the rail's rows ------------------------------------------------------------


## Zones ascending, and a worktree's mezzanine right after the zone it was
## made from, with its checkout for a name (indented where the column says
## names; in the narrow rail its chip, `1A`, says it); a worktree whose source
## is not open stands by its own number.
func test_mezzanines_hang_under_their_source_in_ascending_order() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	_eq(rail.row_keys(), [_zone("hs"), _zone("hud"), _zone("data"), _zone("notes"), _zone("ops")], "drawn order")
	_eq(_chips(office), ["1", "1A", "1B", "4", "5"], "the sign's number: a mezzanine's is its source's and a letter")
	_eq(office.frame.zone_order, Array(rail.row_keys()), "PageUp and PageDown step through the same order")
	var indents := func() -> Array:
		return rail.row_keys().map(func(key: String) -> bool: return _node(rail.row_for(key), "%Indent").visible)
	_eq(indents.call(), [false, false, false, false, false], "the 800-wide rail indents nothing")
	office.test_screen = Vector2(1280, 480)
	office.refresh()
	await _frames(2)
	_eq(indents.call(), [false, true, true, false, false], "with the names, only the mezzanines are indented")
	_eq(_label(rail.row_for(_zone("hud")), "%SpaceLabel").text, "HUD-LANE", "a mezzanine reads as its checkout")
	_eq(_label(rail.row_for(_zone("hs")), "%SpaceLabel").text, "HERDSTEAD", "a zone reads as its workspace")
	_eq(_label(rail.row_for(_zone("ops")), "%SpaceLabel").text, "OPS LANE", "and so does an orphan worktree")
	_done(office)


## PageUp and PageDown walk the rows as drawn: down from a source zone into its
## mezzanines and on to the higher numbers, up out of them back to it. The rail
## is ascending, so PageUp goes to the lower number. Each step pans to its zone
## at once, on the same map: nothing rebuilt.
func test_page_keys_step_through_the_rows_as_drawn() -> void:
	var office := await _live_office()
	_eq(office.navigator.current_zone(office.frame), _zone("hs"), "herdr's focus is on 1")
	var world := office.world.get_instance_id()
	var visited: Array[String] = []
	var drawn: Array = []
	var keys: Array[Key] = [
		KEY_PAGEDOWN, KEY_PAGEDOWN, KEY_PAGEDOWN, KEY_PAGEDOWN, KEY_PAGEDOWN, KEY_PAGEUP, KEY_PAGEUP, KEY_PAGEUP
	]
	for code in keys:
		await _office_key(office, code)
		visited.append(office.navigator.current_zone(office.frame))
		drawn.append([office.layout_plan().floor_key, office.world.get_instance_id()])
		_check(_zone_in_view(office, visited[-1]), "%s: panned into view" % visited[-1])
		_check(Array(office.hud.spaces.in_view()).has(visited[-1]), "%s: and its row is marked" % visited[-1])
	var wanted: Array[String] = [
		_zone("hud"),
		_zone("data"),
		_zone("notes"),
		_zone("ops"),
		_zone("ops"),
		_zone("notes"),
		_zone("data"),
		_zone("hud")
	]
	_eq(visited, wanted, "1, down into 1A and 1B, on to 4 and 5, stops at the bottom, then back up")
	var same: Array = []
	for step in wanted.size():
		same.append([LOCAL, world])
	_eq(drawn, same, "each a pan of the one map, nothing rebuilt")
	_done(office)


## One window per pane seated in the zone, lit by what its agent is doing: the
## state's own colour, idle lit plainly, a shell dark. Its tooltip names the
## agent and the state. A zone's counts stay beside it.
func test_windows_light_up_by_state_one_per_pane() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	_eq(
		_looks(rail.row_for(_zone("hs"))),
		[&"WindowWorking", &"WindowIdle", &"WindowDark"],
		"claude at work, codex idle, a shell"
	)
	_eq(_looks(rail.row_for(_zone("hud"))), [&"WindowBlocked"], "a blocked agent's window")
	_eq(_looks(rail.row_for(_zone("data"))), [&"WindowDone", &"WindowWorking"], "an UNREAD one, and one at work")
	_eq(
		_tips(rail.row_for(_zone("hs"))), ["claude · WORKING", "codex · IDLE", "shell"], "tooltips name agent and state"
	)
	_eq(_tips(rail.row_for(_zone("hud"))), ["claude · NEEDS INPUT"], "in the pack's words")
	_check(_node(rail.row_for(_zone("hud")), "%BlockedIcon").visible, "the blocked count stays beside it")
	# The 800-wide rail leaves the UNREAD count to the row's tooltip.
	_check(not _node(rail.row_for(_zone("data")), "%DoneIcon").visible, "the rail shows no UNREAD icon")
	_check(rail.row_for(_zone("data")).tooltip_text.contains("1 UNREAD"), "its tooltip counts the UNREAD one")
	var before := _window_ids(office)
	_feed(office, _with(fixture, "hs:p2", {"agent_status": "working"}))
	_eq(
		_looks(rail.row_for(_zone("hs"))),
		[&"WindowWorking", &"WindowWorking", &"WindowDark"],
		"a state change relights the window"
	)
	_eq(_window_ids(office), before, "in place: no window is made or dropped for it")
	_done(office)


## Hovering a window shows its pane, and clicking one pans to its zone
## exactly as a click anywhere else on the row does.
func test_a_window_names_its_pane_and_a_click_on_it_pans_to_its_zone() -> void:
	var office := await _live_office()
	var row := office.hud.spaces.row_for(_zone("data"))
	# The column stops above the staff panel: scroll the row into it first.
	var scroll: ScrollContainer = office.hud.spaces.get_node("%Scroll")
	scroll.ensure_control_visible(row)
	await _frames(2)
	var window := _windows(row)[0]
	var at := window.get_global_rect().get_center()
	_check(scroll.get_global_rect().has_point(at), "the window is in the column's view")
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	_eq(root.gui_get_hovered_control(), window, "the pointer is over the window itself")
	_eq(window.get_tooltip(window.get_local_mouse_position()), "codex · UNREAD", "which names its agent and state")
	var revision := office.navigator.nav_revision
	await _click_at(at)
	_eq(office.navigator.current_zone(office.frame), _zone("data"), "a click on a window pans to its zone at once")
	_eq(office.navigator.nav_revision, revision + 1, "one navigation")
	_eq(office.layout_plan().floor_key, LOCAL, "on the machine's map")
	_check(_zone_in_view(office, _zone("data")), "its zone in view")
	_done(office)


## Eight windows, then `+N` for the rest. More panes or fewer relight the same
## eight nodes; none is made or dropped.
func test_windows_stop_at_eight_and_count_the_rest() -> void:
	var hud := await _hud()
	var rail := hud.spaces
	var busy := _zone_of("w1", 3, 11, "working")
	rail.show_machines(_one_machine([busy]), "local", false)
	await _frames(2)
	var row := rail.row_for("w1")
	_eq(_windows(row).filter(func(w: Control) -> bool: return w.visible).size(), 8, "eight windows at most")
	_eq(_label(row, "%More").text, "+3", "and the rest counted")
	_check(_label(row, "%More").visible, "shown")
	_eq(row.size.y, float(OfficeSpaces.ROW), "and the row keeps the one row height the list scrolls by")
	var nodes := _windows(row).map(func(w: Control) -> int: return w.get_instance_id())
	rail.show_machines(_one_machine([_zone_of("w1", 3, 2, "idle")]), "local", false)
	await _frames(1)
	_eq(_looks(row), [&"WindowIdle", &"WindowIdle"], "two panes, two windows")
	_check(not _label(row, "%More").visible, "and nothing over the cap")
	_eq(_windows(row).map(func(w: Control) -> int: return w.get_instance_id()), nodes, "the same window nodes")
	hud.free()


## A dropped machine's section keeps its zones, dimmed and frozen: no count,
## no lit window, nothing pulsing. It lights again when the machine is back.
func test_a_stale_machine_section_is_dimmed_with_every_window_dark() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	_set_online(office, false)
	await _frames(1)
	var tint := office.art.stale_tint
	for key: String in rail.row_keys():
		var row := rail.row_for(key)
		_eq(row.modulate, tint, key + ": dimmed")
		_check(_looks(row).all(func(look: StringName) -> bool: return look == &"WindowDark"), key + ": no lit window")
		_check(not _node(row, "%BlockedIcon").visible and not _node(row, "%DoneIcon").visible, key + ": no count")
	_eq(_tips(rail.row_for(_zone("hs")))[0], "claude · OFFLINE", "a dark window says why")
	_set_online(office, true)
	await _frames(1)
	_eq(rail.row_for(_zone("hs")).modulate, Color.WHITE, "back online, back to full colour")
	_eq(_looks(rail.row_for(_zone("hud"))), [&"WindowBlocked"], "and lit again")
	_done(office)


## The rows whose zone is in view wear the mark at their left edge, and only
## they do: exactly the zones whose rectangle meets the world on screen. A real
## drag moves the marks with the view and refreshes nothing, and no row is
## made, dropped or redrawn for it. (The FLOORS minimap highlighted one
## "current" row; the rail marks what is in view instead.)
func test_rows_in_view_are_marked_and_a_drag_moves_the_marks() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	await _frames(2)
	var marked := Array(rail.in_view())
	_check(marked.has(_zone("hs")), "herdr's focus is in 1: its zone is in view, its row marked: %s" % [marked])
	_eq(marked, _zones_in_view(office), "the rows marked are the zones in view, and no other")
	_check(marked.size() < rail.row_keys().size(), "not every zone fits the view")
	for key: String in rail.row_keys():
		var bar := _node(rail.row_for(key), "%InView")
		_eq(bar.visible, marked.has(key), "%s: the bar at its row's left edge" % key)
		_eq(bar.theme_type_variation, &"SpaceRowInView", "%s: the theme's look" % key)
	var bar := _node(rail.row_for(_zone("hs")), "%InView").get_global_rect()
	var row := rail.row_for(_zone("hs")).get_global_rect()
	_eq([bar.position.x, bar.position.y, bar.size.y], [row.position.x, row.position.y, row.size.y], "a slim bar")
	_check(bar.size.x > 0.0 and bar.size.x <= 2.0, "at most two units wide: %s" % bar.size.x)
	office.refreshes = 0
	var rows := rail.row_keys().map(func(key: String) -> int: return rail.row_for(key).get_instance_id())
	var attempts := office.layout_attempt_count()
	var middle := office.hud.world_rect().get_center()
	var steps := 0
	while Array(rail.in_view()) == marked and steps < 8:
		await _drag(middle, middle + Vector2(0, -120))
		await _frames(2)
		steps += 1
	var after := Array(rail.in_view())
	_check(after != marked, "a real drag down the map moves the marks: %s" % [after])
	_eq(after, _zones_in_view(office), "to the zones now in view")
	_eq(office.refreshes, 0, "with no refresh at all, frame after frame")
	_eq(office.layout_attempt_count(), attempts, "nothing planned")
	_eq(
		rail.row_keys().map(func(key: String) -> int: return rail.row_for(key).get_instance_id()),
		rows,
		"and the same row nodes"
	)
	_done(office)


## A row says what its zone's sign says: the sign's number on its chip (never
## `3F`) and, where the column has names, the sign's words; its tooltip adds
## what the sign's own tooltip says (repository, checkout, whose worktree). The
## plate names the machine, not a zone; every zone of a worktree group wears
## the group's one accent on its sign, a zone in no group its own.
func test_rows_use_the_signs_words_and_tooltips() -> void:
	var office := await _live_office(fixture, Vector2(1280, 480))
	var rail := office.hud.spaces
	_eq(office.plate.title_text(), "LOCAL", "the plate names the machine")
	_check(not _label(office.plate, "%WorktreeOf").visible, "with no worktree line")
	_check(not _node(office.plate, "%Accent").visible, "and no group's accent")
	var stripes := {}
	for id: String in ["hs", "hud", "data", "notes", "ops"]:
		var board := office.floor_view.zone_sign(_zone(id))
		var row := rail.row_for(_zone(id))
		var said := "%s %s" % [_label(board, "%Number").text, _label(board, "%Title").text]
		_eq("%s %s" % [_label(row, "%Number").text, _label(row, "%SpaceLabel").text], said, "%s: the sign's words" % id)
		_eq(OfficeSpaceRow.number_text(office.frame.find_zone(_zone(id)).zone_model), _label(board, "%Number").text, id)
		_check(not _label(row, "%Number").text.ends_with("F"), "%s: no F on the chip" % id)
		var tip := row.tooltip_text.split("\n")
		_eq(tip[0], said, "%s: the tooltip's first line is the sign's words" % id)
		_eq(tip[1], OfficeQuestionTips.sign_text(office.frame.find_zone(_zone(id))), "%s: then the sign's tip" % id)
		var accent: ColorRect = board.get_node("%Accent")
		stripes[id] = accent.color
	_eq(rail.row_for(_zone("hud")).tooltip_text, "1A HUD-LANE\nherdstead · hud-lane · worktree of 1", "a mezzanine's")
	_eq(rail.row_for(_zone("notes")).tooltip_text, "4 NOTES\nNo repository", "a zone with no repository")
	_eq([stripes.hud, stripes.data], [stripes.hs, stripes.hs], "the group's one accent on each of its signs")
	for id: String in ["notes", "ops"]:
		var own: Color = office.art.color(ArtContract.ACCENTS[OfficeZoneSign.accent_of(_zone(id))])
		_eq(stripes[id], own, "%s, in no group, wears its own" % id)
	_done(office)


## Blocked comes first: an agent asking while herdr still launches it is a
## blocked agent to the rail and the arrows. data:p2 (1B) blocks before its
## launch is over: its window is lit blocked and names it so, its row counts it
## beside the blocked icon, and an arrow points to 1B.
func test_a_blocked_start_lights_its_window_blocked_and_shows_an_arrow() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	_feed(office, _with(fixture, "data:p2", {"agent_status": "blocked", "launch_pending": true}))
	await _frames(2)
	_check(office.frame.pane(_pane("data:p2")).starting, "herdr still launches data:p2")
	var row := rail.row_for(_zone("data"))
	_eq(_looks(row), [&"WindowDone", &"WindowBlocked"], "its window is lit blocked, not plainly")
	_eq(_tips(row).slice(1), ["pi · NEEDS INPUT"], "and names it so, in the pack's words")
	_eq(office.frame.find_zone(_zone("data")).zone_model.blocked, 1, "the row counts it")
	_check(_node(row, "%BlockedIcon").visible, "beside the blocked icon")
	var keys := office.hud.edge_arrows.shown().map(func(arrow: OfficeEdgeArrow) -> String: return arrow.zone_key())
	_check(keys.has(_zone("data")), "an arrow points at 1B, off screen: " + str(_arrow_texts(office)))
	_done(office)


# --- the narrow rail and its names ----------------------------------------------


## The SPACES column is a narrow rail below 1280 wide: each row keeps its
## number chip, its blocked badge and count, and the windows directly under the
## chip; its name, indent and UNREAD count step out, and the row's tooltip,
## under a real pointer, says them. Every row fits the rail's 72 units, and a
## machine's heading clips there with the machine's name in its tooltip.
func test_the_rail_says_number_windows_and_blocked_with_the_name_in_its_tooltip() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	_eq(office.hud.placed(rail).size.x, 72.0, "the rail is 72 wide")
	_check(not office.hud.spaces_named(), "800 wide: no names")
	for key: String in rail.row_keys():
		var row := rail.row_for(key)
		_check(not _node(row, "%SpaceLabel").visible, "%s: no name" % key)
		_check(not _node(row, "%DoneIcon").visible and not _node(row, "%DoneCount").visible, "%s: no UNREAD" % key)
		_check(not _node(row, "%Pad").visible, "%s: nothing before the windows" % key)
		var inner := row.get_global_rect()
		for part: String in ["Body/Stack/Line", "Body/Stack/Lights"]:
			var needed := (row.get_node(part) as Control).get_combined_minimum_size().x
			_check(
				needed <= inner.size.x - 4.0, "%s: %s fits the rail: %.0f of %.0f" % [key, part, needed, inner.size.x]
			)
	var hud_row := rail.row_for(_zone("hud"))
	_check(_node(hud_row, "%BlockedIcon").visible, "1A: its blocked badge")
	_eq(_label(hud_row, "%BlockedCount").text, "1", "and its count")
	var chip := _node(hud_row, "%Chip").get_global_rect()
	var facade := _node(hud_row, "%Facade").get_global_rect()
	_eq(facade.position.x, chip.position.x, "the windows stand directly under the chip")
	_check(facade.position.y >= chip.end.y, "below it")
	var data_row := rail.row_for(_zone("data"))
	var at := _node(data_row, "%Chip").get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	_eq(root.gui_get_hovered_control(), data_row, "the pointer rests on 1B's row")
	var tip := data_row.get_tooltip(data_row.get_local_mouse_position())
	_check(tip.begins_with("1B DATA-LANE"), "the tooltip names the zone as its sign does: " + tip)
	_check(tip.contains("1 UNREAD"), "and counts its UNREAD: " + tip)
	_check(hud_row.tooltip_text.contains("1 blocked"), "1A's counts its blocked: " + hud_row.tooltip_text)
	_check(hud_row.tooltip_text.contains("hud-lane"), "and names its checkout: " + hud_row.tooltip_text)
	_done(office)
	# A machine's heading: the rail clips its name; its tooltip has it whole.
	var hud := await _hud()
	var machine := _one_machine([_zone_of("w1", 3, 2, "working")])
	machine[0].label = "a-machine-with-a-long-name"
	machine[0].state = MachineLiveness.State.LIVE
	hud.spaces.show_machines(machine, "local", true)
	await _frames(2)
	var heading := hud.spaces.headings()[0]
	var label: Label = heading.get_node("%MachineLabel")
	_eq(heading.button().tooltip_text, "a-machine-with-a-long-name", "the heading's tooltip names the machine")
	_check(heading.button().mouse_filter != Control.MOUSE_FILTER_IGNORE, "and the pointer can rest on it")
	_check(hud.spaces.get_global_rect().encloses(label.get_global_rect()), "its name clipped inside the rail")
	hud.free()


## The zones' names come back from the scene's `spaces_named_from` (1280) on:
## at 1279 wide the column is the 72-wide rail, at 1280 it is 120 wide with each
## zone's name and UNREAD count and the mezzanines indented, and the world
## starts right of it. The same row nodes throughout.
func test_space_names_show_from_the_scenes_width() -> void:
	var office := await _live_office()
	var rail := office.hud.spaces
	_eq(office.hud.spaces_named_from, 1280.0, "the scene's line")
	var ids := rail.row_keys().map(func(key: String) -> int: return rail.row_for(key).get_instance_id())
	var data := func() -> OfficeSpaceRow: return rail.row_for(_zone("data"))
	for step: Array in [[1279.0, false, 72.0, 96.0], [1280.0, true, 120.0, 144.0], [1279.0, false, 72.0, 96.0]]:
		var width: float = step[0]
		var screen := Vector2(width, 480)
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var named: bool = step[1]
		_eq(office.hud.spaces_named(), named, "%s: names or the rail" % screen)
		_eq(office.hud.placed(rail).size.x, step[2], "%s: the column's width" % screen)
		_eq(office.hud.world_rect().position.x, step[3], "%s: the world starts right of it" % screen)
		var row: OfficeSpaceRow = data.call()
		_eq(_node(row, "%SpaceLabel").visible, named, "%s: 1B's name" % screen)
		_eq(_label(row, "%SpaceLabel").text, "DATA-LANE", "%s: which is its checkout, as its sign writes it" % screen)
		_eq(_node(row, "%DoneIcon").visible, named, "%s: its UNREAD icon" % screen)
		_eq(_node(row, "%Indent").visible, named, "%s: its indent" % screen)
		_eq(row.tooltip_text.contains("UNREAD"), not named, "%s: the tooltip counts what the row does not" % screen)
	var after := rail.row_keys().map(func(key: String) -> int: return rail.row_for(key).get_instance_id())
	_eq(after, ids, "the same rows")
	_done(office)


# --- navigation -----------------------------------------------------------------


## Every gesture that goes somewhere counts one navigation (what a pick waiting
## for a new pane records): an edge arrow click, a SPACES row click, a heading
## click, PageDown, PageUp. Panning counts none: a real drag, a wheel notch;
## nor does a desk click. pick_zone() pans to a zone exactly as a click on its
## SPACES row does.
func test_rail_heading_and_arrow_gestures_count_and_panning_does_not() -> void:
	var office := await _two_machine_office()
	var navigator := office.navigator
	await _frames(2)
	var revision := navigator.nav_revision
	var zone := func() -> String: return navigator.current_zone(office.frame)
	var arrow := office.hud.edge_arrows.shown()[0]
	await _click_at(arrow.get_global_rect().get_center())
	_eq(navigator.nav_revision, revision + 1, "an edge arrow: one navigation")
	await _visit_zone(office, _zone("notes"))
	_eq([zone.call(), navigator.nav_revision], [_zone("notes"), revision + 2], "a SPACES row: one")
	var clicked := [zone.call(), navigator.picked_machine, office.world_model, office.camera.pan]
	await _office_key(office, KEY_PAGEUP)
	_eq([zone.call(), navigator.nav_revision], [_zone("data"), revision + 3], "PageUp: one, to the lower number")
	var middle := office.hud.world_rect().get_center()
	var pan := office.camera.pan
	await _drag(middle, middle + Vector2(-80, 60))
	_check(office.camera.pan != pan, "a real drag pans the map")
	pan = office.camera.pan
	var wheel := _wheel(MOUSE_BUTTON_WHEEL_UP)
	wheel.position = middle
	wheel.global_position = middle
	await _parsed(wheel)
	_check(office.camera.pan != pan, "so does a wheel notch")
	await _click_desk(office, _pane("data:p1"))
	_eq(office.picked_key, _pane("data:p1"), "a desk click picks")
	_eq([zone.call(), navigator.nav_revision], [_zone("data"), revision + 3], "none of them navigates")
	await _office_key(office, KEY_PAGEDOWN)
	_eq([zone.call(), navigator.nav_revision], [_zone("notes"), revision + 4], "PageDown: one, to the higher number")
	await _click_heading(office, BEE)
	_eq([navigator.shown_key, navigator.nav_revision], [BEE, revision + 5], "a heading: one")
	await _click_heading(office, LOCAL)
	_eq([navigator.shown_key, navigator.nav_revision], [LOCAL, revision + 6], "and one back")
	await _office_key(office, KEY_PAGEUP)
	navigator.pick_zone(_zone("notes"))
	office.refresh()
	var picked := [zone.call(), navigator.picked_machine, office.world_model, office.camera.pan]
	_eq(picked, clicked, "pick_zone() pans to the zone as its SPACES row did")
	_eq(navigator.nav_revision, revision + 8, "and counts one navigation")
	_done(office)


## A desk picked by a real click stops the follow only while its pane is there.
## Once herdr closes that pane the selection is herdr's focus again, and every
## move of the focus to a zone out of sight pans its desk into the world's room:
## the map is one world, so nothing else would bring it into view.
func test_focus_is_revealed_again_once_the_picked_pane_is_gone() -> void:
	var zones := _six_zones()
	var office := await _live_office(zones)
	var picked := _pane("w0:t0:p1")
	await _click_desk(office, picked)
	_eq(office.picked_key, picked, "a real click picks the desk")
	var world_id := office.world.get_instance_id()
	var closed: Dictionary = zones.duplicate(true)
	closed.panes = _list(closed, "panes").filter(
		func(pane: Dictionary) -> bool: return str(pane.get("pane_id", "")) != "w0:t0:p1"
	)
	_feed(office, closed)
	await _frames(3)
	_eq(office.navigator.active_key, _pane("w0:t0:p0"), "its pane closed: herdr's focus")
	for pane_id: String in ["w5:t0:p0", "w2:t0:p0"]:
		var key := _pane(pane_id)
		_check(not _desk_in_view(office, key), "%s is out of sight before herdr's focus goes there" % pane_id)
		_feed(office, _focused_on(closed, pane_id))
		await _frames(3)
		_eq(office.navigator.active_key, key, "herdr's focus on %s is the selection" % pane_id)
		_check(_desk_in_view(office, key), "and %s is panned into the world's room" % pane_id)
	_eq(office.picked_key, picked, "the pick itself is remembered")
	_eq(office.world.get_instance_id(), world_id, "the same world throughout")
	_done(office)


## A real click on a machine's heading shows that machine's map at once: a cold
## switch (a new world), one navigation, nothing picked, the rail's rows as
## they were, and the marks now on that machine's zones.
func test_a_heading_click_switches_to_that_machine() -> void:
	var office := await _two_machine_office()
	var navigator := office.navigator
	await _frames(2)
	_eq(navigator.shown_key, LOCAL, "Local's map is shown")
	var world := office.world.get_instance_id()
	var revision := navigator.nav_revision
	var picked := office.picked_key
	var rows := office.hud.spaces.row_keys()
	var hive := HerdrFleet.pane_key(BEE, "hive")
	_check(not Array(office.hud.spaces.in_view()).has(hive), "bee's zone is not in view from Local's map")
	var heading := office.hud.spaces.heading_for(BEE)
	var at := heading.button().get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	_eq(navigator.shown_key, LOCAL, "a press switches nothing")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(navigator.shown_key, BEE, "released: bee's map is shown")
	_eq(office.shown_machine(), BEE, "the world is built for it")
	_check(office.world.get_instance_id() != world, "cold: a new world")
	_eq(office.floor_view.presentation.walkers(), [], "nobody walks")
	_eq(navigator.nav_revision, revision + 1, "one navigation")
	_eq(office.picked_key, picked, "nothing is picked")
	_eq(office.plate.title_text(), "@ BEE", "the plate names bee")
	_eq(office.hud.spaces.row_keys(), rows, "the rail's rows are what they were")
	await _frames(2)
	_eq(Array(office.hud.spaces.in_view()), [hive], "and the marks are on bee's zone, in view")
	_check(_zone_in_view(office, hive), "which is on screen")
	_done(office)


## A machine that never connected has no zone and so no row: its heading is the
## way to it. A real click opens its map, empty, with the note saying why.
func test_a_heading_click_opens_a_never_connected_machine_as_an_empty_map_with_its_note() -> void:
	var office := await _far_office()
	await _frames(2)
	var rail := office.hud.spaces
	_eq(rail.headings().size(), 2, "a heading per machine")
	_eq(office.frame.building_of(FAR).zones.size(), 0, "far never connected: no zone")
	_check(rail.row_keys().all(func(key: String) -> bool: return key.begins_with(LOCAL)), "so no row of its own")
	var revision := office.navigator.nav_revision
	await _click_heading(office, FAR)
	_eq(office.navigator.shown_key, FAR, "a click on its heading shows its map")
	_eq(office.navigator.nav_revision, revision + 1, "one navigation")
	_eq(office.layout_plan().desks.size(), 0, "an empty map: no desk")
	_eq(office.floor_view.seats.size(), 0, "nobody seated")
	_eq(office.plate.title_text(), "@ FAR", "its plate names it")
	_check(not office.plate.note_text().is_empty(), "with a note saying why it is empty: " + office.plate.note_text())
	_check(office.plate.state_text() != "LIVE", "and that it is not answering: " + office.plate.state_text())
	_eq(Array(rail.in_view()), [], "no zone in view on an empty map")
	_check(not office.hud.edge_arrows.visible, "and no arrows")
	await _click_heading(office, LOCAL)
	_eq(office.navigator.shown_key, LOCAL, "Local's heading goes back")
	_done(office)


## The heading of the machine whose map is shown is highlighted, alone; a
## heading click moves the highlight with the map, and Local alone has no
## heading at all.
func test_the_heading_of_the_shown_machine_is_highlighted_alone() -> void:
	var office := await _two_machine_office()
	await _frames(2)
	var rail := office.hud.spaces
	_eq(_current_headings(office), [LOCAL], "Local's map is shown: its heading is highlighted, alone")
	_eq(rail.heading_for(LOCAL).button().theme_type_variation, &"SpaceHeadingCurrent", "by the theme's look")
	_eq(rail.heading_for(BEE).button().theme_type_variation, &"SpaceHeading", "the other plain")
	await _click_heading(office, BEE)
	_eq(_current_headings(office), [BEE], "bee's map is shown: bee's heading, alone")
	# A zone of Local's picked from bee's map takes the highlight back with the map.
	await _visit_zone(office, _zone("notes"))
	_eq(_current_headings(office), [LOCAL], "a row of Local's shows Local's map: Local's heading again")
	_done(office)
	var alone := await _live_office()
	_eq(alone.hud.spaces.headings().size(), 0, "Local alone: no heading")
	_done(alone)


## A heading click wins over herdr's focus moving in a snapshot that arrived
## but is not drawn yet: a real press on bee's heading, the snapshot, the
## release. The release's own refresh takes that snapshot in, and bee's map is
## the one shown, not the map the focus moved on; the selection is herdr's new
## focus all the same, and the next move of the focus is followed as ever.
func test_a_heading_click_wins_over_a_focus_move_not_drawn_yet() -> void:
	var office := await _two_machine_office()
	await _frames(2)
	var navigator := office.navigator
	var at := office.hud.spaces.heading_for(BEE).button().get_global_rect().get_center()
	var revision := navigator.nav_revision
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	var drawn := office.refreshes
	_arrive(office, _focused_on(fixture, "hs:p2"))
	_eq(
		[office.refreshes, navigator.active_key, navigator.shown_key],
		[drawn, _pane("hs:p1"), LOCAL],
		"a snapshot with the focus moved is waiting, not drawn"
	)
	_release_now(at)
	_eq(navigator.shown_key, BEE, "released: bee's map is shown, though the focus moved on Local's")
	await _frames(3)
	_eq([navigator.shown_key, office.shown_machine()], [BEE, BEE], "and it stays shown once the frame's queue has run")
	_eq(navigator.active_key, _pane("hs:p2"), "the selection is herdr's new focus")
	_eq(navigator.nav_revision, revision + 1, "one navigation: the heading")
	_feed(office, _focused_on(fixture, "ops:p1"))
	await _frames(3)
	_eq(navigator.shown_key, LOCAL, "the next move of the focus is followed again: Local's map")
	_check(_desk_in_view(office, _pane("ops:p1")), "its desk panned into the world's room")
	_done(office)


# --- the plate and the signs ----------------------------------------------------


## Why a map cannot be laid out is said inside the plate's band: one line in
## the blocked colour between the machine's name and its counts, right-aligned,
## cut with an ellipsis where the band is short, whole in its tooltip. Nothing
## of the plate is drawn below its band, and a real drag that starts on the
## line still pans the office.
func test_the_plate_problem_stays_inside_the_band() -> void:
	for screen: Vector2 in [Vector2(SCREEN), Vector2(480, 320)]:
		var office := await _live_office(fixture, screen)
		var broken: Dictionary = fixture.duplicate(true)
		var twice: Dictionary = {}
		for pane: Dictionary in _list(broken, "panes"):
			if pane.pane_id == "data:p1":
				twice = pane.duplicate(true)
		_list(broken, "panes").append(twice)
		_feed(office, broken)
		office.camera.pan = Vector2.ZERO
		await _frames(3)
		_check(not office.layout_problems().is_empty(), "%s: 1B's input cannot be laid out" % screen)
		var plate := office.plate
		var problem: Label = plate.get_node("%Problem")
		var band: Control = plate.get_node("%Band")
		var said := plate.problem_text()
		_check(
			said.begins_with("Layout unavailable: 1B DATA-LANE: "), "%s: the plate names the zone: %s" % [screen, said]
		)
		_check(problem.is_visible_in_tree(), "%s: the line shows" % screen)
		_check(
			band.get_global_rect().encloses(problem.get_global_rect()),
			"%s: inside the band: %s in %s" % [screen, problem.get_global_rect(), band.get_global_rect()]
		)
		for label: Label in plate.find_children("*", "Label", true, false):
			if label.is_visible_in_tree():
				_check(
					label.get_global_rect().end.y <= band.get_global_rect().end.y,
					"%s: nothing below the band: %s" % [screen, label.name]
				)
		_eq(problem.theme_type_variation, &"PlateProblem", "%s: the theme's look" % screen)
		_eq(
			problem.get_theme_color("font_color"),
			office.art.color(ArtContract.BLOCKED),
			"%s: the blocked colour" % screen
		)
		_eq(problem.get_line_count(), 1, "%s: one line" % screen)
		_eq(problem.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "%s: right-aligned" % screen)
		_eq(problem.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE, "%s: cut with an ellipsis" % screen)
		_eq(problem.tooltip_text, said, "%s: the whole line in its tooltip" % screen)
		var title: Label = plate.get_node("%Title")
		var counts: Label = plate.get_node("%Counts")
		_check(title.get_global_rect().end.x <= problem.get_global_rect().position.x, "%s: right of the name" % screen)
		_check(
			problem.get_global_rect().end.x <= counts.get_global_rect().position.x, "%s: left of the counts" % screen
		)
		_check(
			band.get_global_rect().encloses(counts.get_global_rect()),
			"%s: the counts keep their place in the band" % screen
		)
		var needed := (
			problem
			. get_theme_font("font")
			. get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1, problem.get_theme_font_size("font_size"))
			. x
		)
		print("PLATE_PROBLEM: %s: %d of %d units for: %s" % [screen, problem.size.x, needed, said])
		_check(problem.size.x >= 48.0, "%s: with room to say something: %s" % [screen, problem.size.x])
		# A real drag from the line pans the office: the plate is world furniture.
		var on_line := problem.get_global_rect().get_center() - office.camera.position
		if office.camera.world_size.y > office.camera.free_rect().size.y:
			await _drag(on_line, on_line + Vector2(0, -24))
			_check(office.camera.pan.y > 0.0, "%s: a drag that starts on the line pans the office" % screen)
		_feed(office, fixture)
		await _frames(2)
		_eq(plate.problem_text(), "", "%s: valid again: no problem line" % screen)
		_check(not problem.visible, "%s: hidden" % screen)
		_done(office)
		await _frames(2)


## A SPACES row click marks that zone, and the zones that share the view with
## it, and no other: the marks follow the pick in the same frame as the pan.
func test_in_view_marks_follow_a_zone_pick() -> void:
	var office := await _live_office(_six_zones())
	var rail := office.hud.spaces
	await _frames(2)
	var first := _zone("w0")
	var last := _zone("w5")
	_check(Array(rail.in_view()).has(first), "opening on herdr's focus, 1 is in view")
	_check(not Array(rail.in_view()).has(last), "and 6, a map away, is not")
	var row := rail.row_for(last)
	var scroll: ScrollContainer = rail.get_node("%Scroll")
	scroll.ensure_control_visible(row)
	await _frames(2)
	var at := row.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	_check(not Array(rail.in_view()).has(last), "a press marks nothing")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	var marked := Array(rail.in_view())
	_check(marked.has(last), "released: 6 is in view and its row marked: %s" % [marked])
	_check(not marked.has(first), "and 1 is out of view, unmarked")
	_eq(marked, _zones_in_view(office), "only the zones that share the view with it are marked")
	for key: String in marked:
		_check(_zone_in_view(office, key), "%s meets the world on screen" % key)
	await _frames(3)
	_eq(Array(rail.in_view()), marked, "and stays so")
	var leading := rail.row_for(str(marked[0])).get_global_rect()
	_check(scroll.get_global_rect().intersects(leading), "the list keeps the first row in view in sight")
	_done(office)


## Hovering a zone's sign, by real mouse motion over its area and physics
## frames, brings up the world tooltip naming the workspace's repository and
## checkout, and for a mezzanine whose worktree it is; moving off hides it, and
## so does moving just past the panel's right end (the hover area is the drawn
## panel, as wide as what the sign says). It
## reads nothing and writes nothing (this suite's office is read-only and never
## reaches herdr).
func test_hovering_a_zone_sign_names_its_repo_and_checkout() -> void:
	var office := await _live_office()
	var cases := {
		_zone("hs"): "herdstead",
		_zone("hud"): "herdstead · hud-lane · worktree of 1",
		_zone("notes"): "No repository",
	}
	for key: String in cases:
		# A row click pans the sign's aisle row to the top of the world.
		await _visit_zone(office, key)
		await _frames(3)
		var board := office.floor_view.zone_sign(key)
		_check(board != null, key + ": the zone has its sign")
		if board == null:
			continue
		var panel: NinePatchRect = board.get_node("%Panel")
		var drawn := Rect2(board.to_global(panel.position), panel.size * panel.scale)
		var on := drawn.get_center() - office.camera.position
		_check(office.hud.world_rect().has_point(on), "%s: the sign is on screen at %s" % [key, on])
		_check(not _under_arrow(office, on), "%s: and no arrow stands over it" % key)
		_check(not office.hud.world_tip_shown(), key + ": no tooltip before the pointer comes")
		await _pointer_to(on)
		_check(office.hud.world_tip_shown(), key + ": hovering the sign shows the tooltip")
		_eq(office.hud.world_tip_text(), cases[key], key + ": naming its repository and checkout")
		await _pointer_to(on + Vector2(0, 120))
		_check(not office.hud.world_tip_shown(), key + ": moving off hides it")
		# The hover area is the drawn panel, sized to what the sign says: just
		# inside its right end the tooltip shows, just past it it does not.
		var middle := on.y
		var end := drawn.end.x - office.camera.position.x
		await _pointer_to(Vector2(end - 2.0, middle))
		_check(office.hud.world_tip_shown(), key + ": just inside the panel's right end, the tooltip")
		await _pointer_to(Vector2(end + 3.0, middle))
		_check(not office.hud.world_tip_shown(), key + ": just past it, none")
	_done(office)


# --- helpers --------------------------------------------------------------------


func _zone(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _node(holder: Node, path: String) -> Control:
	return holder.get_node(path)


func _chips(office: OfficeDouble) -> Array:
	var rail := office.hud.spaces
	return rail.row_keys().map(func(key: String) -> String: return _label(rail.row_for(key), "%Number").text)


## A row's eight window nodes, lit or not.
func _windows(row: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in row.get_node("%Windows").get_children():
		found.append(child)
	return found


## The look of each window a row shows, left to right.
func _looks(row: Node) -> Array:
	return (
		_windows(row)
		. filter(func(w: Control) -> bool: return w.visible)
		. map(func(w: Control) -> StringName: return w.theme_type_variation)
	)


func _tips(row: Node) -> Array:
	return (
		_windows(row)
		. filter(func(w: Control) -> bool: return w.visible)
		. map(func(w: Control) -> String: return w.tooltip_text)
	)


func _window_ids(office: OfficeDouble) -> Array:
	var ids: Array = []
	for key: String in office.hud.spaces.row_keys():
		ids.append_array(
			_windows(office.hud.spaces.row_for(key)).map(func(w: Control) -> int: return w.get_instance_id())
		)
	return ids


## The machines whose heading is the highlighted one.
func _current_headings(office: OfficeDouble) -> Array:
	return (
		office
		. hud
		. spaces
		. headings()
		. filter(func(heading: OfficeMachineHeading) -> bool: return heading.is_current())
		. map(func(heading: OfficeMachineHeading) -> String: return heading.key)
	)


## The part of the world on screen, in global coordinates.
func _view(office: OfficeDouble) -> Rect2:
	return Rect2(office.camera.position + office.hud.world_rect().position, office.hud.world_rect().size)


## Whether zone `key`'s rectangle on the shown map meets the world on screen.
func _zone_in_view(office: OfficeDouble, key: String) -> bool:
	var placed := office.layout_plan().zone(key)
	if placed == null or office.floor_view.plan.zone(key) == null:
		return false
	var area := placed.bounds()
	return Rect2(office.floor_view.root.to_global(area.position), area.size).intersects(_view(office))


## The zones of the shown map whose rectangle meets the world on screen, in
## the rail's order.
func _zones_in_view(office: OfficeDouble) -> Array:
	return office.hud.spaces.row_keys().filter(func(key: String) -> bool: return _zone_in_view(office, key))


## Zone `key` numbered `number`, one room of `panes` claude agents in `state`.
func _zone_of(key: String, number: int, panes: int, state: String) -> ZoneModel:
	var zone := ZoneModel.new()
	zone.key = key
	zone.number = number
	zone.label = key
	zone.agents = panes
	var room := RoomModel.new()
	for index in panes:
		var pane := PaneModel.new()
		pane.key = "%s:p%d" % [key, index]
		pane.provider = "claude"
		pane.state = state
		room.panes.append(pane)
	zone.rooms.append(room)
	return zone


func _one_machine(zones: Array[ZoneModel]) -> Array[SpaceRows]:
	var machine := SpaceRows.new()
	machine.key = "local"
	machine.label = "Local"
	machine.zones = zones
	return [machine]


## Local, live with the fixture, and `far`: a machine on a socket nobody
## listens on, which never connects and so never has a zone.
func _far_office() -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = Vector2(SCREEN)
	office.test_args = AppArgs.parse(
		PackedStringArray(
			[
				"--read-only",
				"--socket=" + args.socket,
				"--machine-socket=far=" + args.work.path_join("far-nowhere.sock")
			]
		)
	)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	office.fleet._sites[1].client.stop()
	_feed(office, fixture)
	await _frames(2)
	return office
