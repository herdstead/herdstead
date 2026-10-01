extends "res://tools/office_test_base.gd"
## The left column's SPACES rail: one section per machine, its zones ascending
## with each worktree's mezzanine right after its source, the words on each
## zone's sign, a strip of windows per zone lit by its panes' states, a mark on
## the rows whose zone is in view (it follows panning), a row click panning to
## its zone, a heading click showing its machine's map, a stale machine dimmed
## with no lit window; the arrows on the world's edges toward the zones of the
## shown map whose blocked desks are off screen; each zone's sign; and the
## machine plate's problem line. Clicks, hovers, drags and keys go through real
## input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_space_rail.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## (This suite took over from the FLOORS suite, tools/test_floors.gd, when the
## FLOORS minimap and its signposts became the SPACES rail and the edge arrows.
## Never tools/test_spaces.gd: that is the New space / Worktree write suite.)

## The most of the world's width an arrow may cover, in any window. A full
## arrow is about 56 units of the narrowest world that shows one in full
## (OfficeHud.edge_arrows_compact_from, 360); below that it is compact.
const MAX_ARROW_COVER := 1.0 / 4.0
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


# --- the edge arrows ------------------------------------------------------------


## Every zone of the shown map with a blocked desk off screen gets an arrow on
## the world's edge toward it: the way there, the zone's number as its sign
## writes it, and a pulsing blocked badge with the count; its tooltip names the
## zone and the longest wait. A zone that starts waiting off screen gets its
## own; a machine that drops takes them all away.
func test_an_arrow_points_at_each_zone_with_blocked_desks_off_screen() -> void:
	var office := await _live_office()
	var arrows := office.hud.edge_arrows
	_eq(office.navigator.current_zone(office.frame), _zone("hs"), "herdr's focus is on 1")
	await _frames(2)
	_check(not _chip_on_screen(office, _pane("hud:p1")), "1A's blocked desk is off screen")
	_check(arrows.visible, "a blocked desk off screen, below, puts an arrow up")
	_eq(_arrow_texts(office), ["↓ 1A 1"], "one arrow: down to the mezzanine by its sign's number, one blocked")
	var arrow := arrows.shown()[0]
	_eq([arrow.zone_key(), arrow.pane_key()], [_zone("hud"), _pane("hud:p1")], "it points at 1A, and its blocked desk")
	_eq(arrows.models()[0].edge, EdgeArrowModel.Edge.BOTTOM, "on the bottom edge")
	var badge := arrow.badge()
	_eq([badge.machine, str(badge.state)], [LOCAL, "blocked"], "its badge stands for the zone's machine, blocked")
	_check(badge.is_in_group(StatusBadge.GROUP), "and pulses with the others")
	_check(arrow.tooltip_text.begins_with("1A HUD-LANE · 1 blocked · longest "), "its tooltip: " + arrow.tooltip_text)
	_feed(office, _with(fixture, "hud:p1", {"agent_status": "working"}))
	await _frames(2)
	_check(not arrows.visible, "nobody blocked off screen: no arrow")
	_check(not badge.is_in_group(StatusBadge.GROUP), "the hidden arrow's badge stops pulsing")
	_feed(office, _with(_with(fixture, "hud:p1", {"agent_status": "working"}), "ops:p1", {"agent_status": "blocked"}))
	await _frames(2)
	_eq(_arrow_texts(office), ["↓ 5 1"], "5 starts waiting below the view: down to it")
	_set_online(office, false)
	await _frames(1)
	_check(not arrows.visible, "a machine that drops counts nobody waiting: no arrow")
	_done(office)


## Eight arrows, always the same eight nodes: more zones waiting than that, and
## seven of them get an arrow while the eighth, disabled, counts the rest and
## names them in its tooltip. Fewer, and the arrows past them hide. Pure too:
## EdgeArrowModel.of() sorts by the longest wait and counts only desks off screen.
func test_arrows_keep_eight_nodes_and_say_plus_n() -> void:
	var hud := await _hud()
	var nodes := hud.edge_arrows.find_children("*", "OfficeEdgeArrow", true, false)
	_eq(nodes.size(), EdgeArrowModel.POOL, "eight arrows in the scene")
	var view := Rect2(0, 0, 400, 300)
	var targets: Array[EdgeArrowModel.Target] = []
	for index in 10:
		# Zone f0 has waited longest; every desk is below the view.
		targets.append(_target("f%d" % index, str(index + 2), Rect2(40 * index, 400, 16, 16), (20 - index) * 60000))
	# A second desk of f0, and one of f1 that is on screen: not counted.
	targets.append(_target("f0", "2", Rect2(0, 440, 16, 16), 1000))
	targets.append(_target("f1", "3", Rect2(100, 100, 16, 16), 99 * 60000))
	var many := EdgeArrowModel.of(view, targets)
	_eq(many.size(), EdgeArrowModel.POOL, "eight models for ten zones")
	_eq(many[0].zone_key, "f0", "the longest wait first")
	_eq([many[0].blocked, many[1].blocked], [2, 1], "counting the desks off screen only")
	_eq(many[1].pane_key, "f1:p", "and pointing at one that is off screen")
	hud.show_edge_arrows(many)
	await _frames(2)
	var shown := hud.edge_arrows.shown()
	_eq(shown.size(), 8, "eight shown")
	_eq(
		shown.slice(0, 7).map(func(arrow: OfficeEdgeArrow) -> String: return arrow.zone_key()),
		["f0", "f1", "f2", "f3", "f4", "f5", "f6"],
		"the first seven point at their zones"
	)
	_check(shown.slice(0, 7).all(func(arrow: OfficeEdgeArrow) -> bool: return not arrow.disabled), "and can be clicked")
	var more := shown[7]
	_eq(_label(more, "%Zone").text, "+3", "the eighth counts the rest")
	_check(more.disabled, "and is a note, not a way there")
	_eq([more.zone_key(), more.pane_key()], ["", ""], "with no zone or desk of its own")
	_eq(more.tooltip_text.split("\n").size(), 3, "its tooltip names the three: " + more.tooltip_text)
	_check(more.tooltip_text.contains("9 F7") and more.tooltip_text.contains("11 F9"), "by number and name")
	_check(not more.badge().is_in_group(StatusBadge.GROUP), "its badge does not pulse")
	var few: Array[EdgeArrowModel.Target] = [targets[3], targets[5]]
	hud.show_edge_arrows(EdgeArrowModel.of(view, few))
	await _frames(1)
	_eq(
		hud.edge_arrows.shown().map(func(arrow: OfficeEdgeArrow) -> String: return arrow.zone_key()),
		["f3", "f5"],
		"two zones, two arrows"
	)
	_check(not hud.edge_arrows.shown()[1].disabled, "the second is a way there again")
	_eq(hud.edge_arrows.find_children("*", "OfficeEdgeArrow", true, false), nodes, "the same eight nodes throughout")
	var none: Array[EdgeArrowModel.Target] = []
	hud.show_edge_arrows(EdgeArrowModel.of(view, none))
	_check(not hud.edge_arrows.visible, "no zone waiting, no arrows")
	hud.free()


## An arrow stands inside the world, on the edge its desk lies beyond: above,
## right, below or left of the view, where the line from the view's middle to
## the desk crosses that edge. Two arrows never overlap, and none leaves the world.
func test_an_arrow_stands_inside_the_world_on_the_edge_toward_its_desk() -> void:
	var hud := await _hud()
	var room := hud.world_rect()
	var view := Rect2(Vector2.ZERO, room.size)
	var middle := view.get_center()
	var cases := {
		"up": [Vector2(middle.x, -200), EdgeArrowModel.Edge.TOP, "↑"],
		"right": [Vector2(view.end.x + 300, middle.y), EdgeArrowModel.Edge.RIGHT, "→"],
		"down": [Vector2(middle.x, view.end.y + 200), EdgeArrowModel.Edge.BOTTOM, "↓"],
		"left": [Vector2(-300, middle.y), EdgeArrowModel.Edge.LEFT, "←"],
	}
	var targets: Array[EdgeArrowModel.Target] = []
	for way: String in cases:
		var at: Vector2 = cases[way][0]
		targets.append(_target(way, "7", Rect2(at - Vector2(8, 8), Vector2(16, 16)), 1000))
	var models := EdgeArrowModel.of(view, targets)
	hud.show_edge_arrows(models)
	await _frames(2)
	_check(hud.edge_arrows.visible, "shown")
	_eq(hud.edge_arrows.get_global_rect(), room, "the arrows' control lies over the world rect exactly")
	_eq(hud.edge_arrows.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and takes no mouse itself: the world is under it")
	var rects: Array[Rect2] = []
	for arrow in hud.edge_arrows.shown():
		var wanted: Array = cases[arrow.zone_key()]
		var model := models[hud.edge_arrows.shown().find(arrow)]
		var rect := arrow.get_global_rect()
		rects.append(rect)
		_eq(model.edge, wanted[1], "%s: its edge" % arrow.zone_key())
		_eq(_label(arrow, "%Glyph").text, wanted[2], "%s: its glyph" % arrow.zone_key())
		_check(is_equal_approx(model.along, 0.5), "%s: half way along it: %s" % [arrow.zone_key(), model.along])
		_check(room.encloses(rect), "%s: inside the world %s: %s" % [arrow.zone_key(), room, rect])
		var from_edge := {
			EdgeArrowModel.Edge.TOP: rect.position.y - room.position.y,
			EdgeArrowModel.Edge.RIGHT: room.end.x - rect.end.x,
			EdgeArrowModel.Edge.BOTTOM: room.end.y - rect.end.y,
			EdgeArrowModel.Edge.LEFT: rect.position.x - room.position.x,
		}
		_eq(from_edge[model.edge], 4.0, "%s: the theme's inset from its edge" % arrow.zone_key())
		var across := model.edge == EdgeArrowModel.Edge.TOP or model.edge == EdgeArrowModel.Edge.BOTTOM
		var centre := rect.get_center() - room.get_center()
		_check(
			absf(centre.x if across else centre.y) <= 1.0,
			"%s: in the middle of its edge: %s" % [arrow.zone_key(), rect]
		)
	# Toward a corner: the edge the line crosses first, and where along it.
	var corner := _target("corner", "9", Rect2(view.end + Vector2(100, 400), Vector2(16, 16)), 1000)
	var toward := EdgeArrowModel.of(view, [corner] as Array[EdgeArrowModel.Target])[0]
	_eq(toward.edge, EdgeArrowModel.Edge.BOTTOM, "a desk far below and a little right: the bottom edge")
	_check(toward.along > 0.5 and toward.along < 1.0, "right of its middle: %s" % toward.along)
	# Six on one edge at the same place: side by side, none over another, all inside.
	var crowd: Array[EdgeArrowModel.Target] = []
	for index in 6:
		crowd.append(_target("c%d" % index, str(index), Rect2(view.end.x - 8, view.end.y + 100, 16, 16), 1000))
	hud.show_edge_arrows(EdgeArrowModel.of(view, crowd))
	await _frames(2)
	rects.clear()
	for arrow in hud.edge_arrows.shown():
		rects.append(arrow.get_global_rect())
		_check(room.encloses(arrow.get_global_rect()), "crowded: inside the world: %s" % arrow.get_global_rect())
	_eq(rects.size(), 6, "six arrows on the bottom edge")
	for index in rects.size():
		for other in range(index + 1, rects.size()):
			_check(not rects[index].intersects(rects[other]), "crowded: %s and %s apart" % [rects[index], rects[other]])
	# Four toward the bottom-right corner along the right edge and four along
	# the bottom one: the corner is the bottom edge's, and none meets another.
	var corners: Array[EdgeArrowModel.Target] = []
	for index in 4:
		corners.append(_target("r%d" % index, str(index), Rect2(view.end.x + 900, view.end.y - 8, 16, 16), 1000))
		corners.append(_target("b%d" % index, str(index), Rect2(view.end.x - 8, view.end.y + 900, 16, 16), 1000))
	var cornered := EdgeArrowModel.of(view, corners)
	hud.show_edge_arrows(cornered)
	await _frames(2)
	rects.clear()
	var edges: Array = []
	for index in hud.edge_arrows.shown().size():
		var rect := hud.edge_arrows.shown()[index].get_global_rect()
		rects.append(rect)
		edges.append(cornered[index].edge)
		_check(room.encloses(rect), "cornered: inside the world: %s" % rect)
	_eq([edges.count(EdgeArrowModel.Edge.RIGHT), edges.count(EdgeArrowModel.Edge.BOTTOM)], [4, 4], "four on each edge")
	for index in rects.size():
		for other in range(index + 1, rects.size()):
			_check(
				not rects[index].intersects(rects[other]), "cornered: %s and %s apart" % [rects[index], rects[other]]
			)
	hud.free()


## Below `edge_arrows_compact_from` (the 480x320 minimum) an arrow leaves its
## zone's number to the tooltip: glyph, badge and count. In every window the
## arrows stand in the world and never under the rail, the drawer or the staff
## panel; a full arrow covers at most a quarter of the world's width, and at
## the minimum nothing stands over the plate's name. The rail's row is the
## same count and a click on it pans there.
func test_arrows_go_compact_on_a_narrow_world_and_never_under_the_rail() -> void:
	var office := await _live_office()
	var wanted := {Vector2(480, 320): true, Vector2(640, 320): false, Vector2(960, 480): false}
	for screen: Vector2 in wanted:
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var room := office.hud.world_rect()
		_eq(office.hud.edge_arrows_compact(), wanted[screen], "%s: compact only when the world is narrow" % screen)
		_eq(room.size.x < office.hud.edge_arrows_compact_from, wanted[screen], "%s: by the scene's width" % screen)
		_check(office.hud.edge_arrows.visible, "%s: shown" % screen)
		var arrow := office.hud.edge_arrows.shown()[0]
		var rect := arrow.get_global_rect()
		_eq(arrow.compact(), wanted[screen], "%s: the arrow's form" % screen)
		_eq(_label(arrow, "%Zone").visible, not wanted[screen], "%s: its zone's number" % screen)
		_check(_label(arrow, "%Glyph").visible and _label(arrow, "%Count").visible, "%s: glyph and count" % screen)
		_eq(_arrow_texts(office), ["↓ 1" if wanted[screen] else "↓ 1A 1"], "%s: the arrow's words" % screen)
		_check(arrow.tooltip_text.begins_with("1A HUD-LANE"), "%s: the tooltip names the zone" % screen)
		_check(room.encloses(rect), "%s: inside the world %s: %s" % [screen, room, rect])
		for panel: Control in [office.hud.spaces, office.hud.right_column, office.hud.staff, office.hud.news]:
			_check(not office.hud.placed(panel).intersects(rect), "%s: not under %s" % [screen, panel.name])
		var line: Control = arrow.get_node("%Line")
		# A Control never shrinks below its minimum: words that do not fit push
		# the line out of the arrow rather than shrink it.
		_check(
			rect.encloses(line.get_global_rect()),
			"%s: its words fit it: %s in %s" % [screen, line.get_global_rect(), rect]
		)
		var cover := rect.size.x / room.size.x
		print(
			(
				"ARROW_COVER: %dx%d world %d wide, arrow %d wide = %.1f%%"
				% [screen.x, screen.y, room.size.x, rect.size.x, cover * 100.0]
			)
		)
		_check(cover <= MAX_ARROW_COVER, "%s: the arrow covers %.1f%% of the world's width" % [screen, cover * 100.0])
	# At the minimum nothing stands over the plate's name.
	office.test_screen = Vector2(480, 320)
	office.refresh()
	office.camera.pan = Vector2.ZERO
	await _frames(2)
	var title: Label = office.plate.get_node("%Title")
	var name_rect := Rect2(title.get_global_rect().position - office.camera.position, title.size)
	_check(office.hud.world_rect().encloses(name_rect), "the plate's name is on screen: %s" % name_rect)
	for arrow in office.hud.edge_arrows.shown():
		_check(not arrow.get_global_rect().intersects(name_rect), "and no arrow stands over it")
	var row := office.hud.spaces.row_for(_zone("hud"))
	_check(_node(row, "%BlockedIcon").visible, "the rail's row for 1A has its blocked badge")
	_eq(_label(row, "%BlockedCount").text, "1", "and its count")
	await _click_at(row.get_global_rect().get_center())
	_eq(office.navigator.current_zone(office.frame), _zone("hud"), "a click on the rail's row pans to 1A")
	_done(office)


## The arrows keep what they were last handed: a change of the world's room (a
## window, the drawer) places the same arrows again at once, compact or full,
## with no refresh and no new node, and the OVERVIEW hides them.
func test_the_hud_keeps_the_arrow_nodes_as_the_world_resizes() -> void:
	var hud := await _hud()
	var nodes := hud.edge_arrows.find_children("*", "OfficeEdgeArrow", true, false)
	hud.fit(Vector2(480, 320))
	var view := Rect2(0, 0, 400, 300)
	var five: Array[EdgeArrowModel.Target] = []
	for index in 5:
		five.append(_target("f%d" % index, "%dA" % (index + 2), Rect2(600, 60 * index, 16, 16), 1000 * (5 - index)))
	hud.show_edge_arrows(EdgeArrowModel.of(view, five))
	await _frames(2)
	_check(hud.edge_arrows_compact(), "a 480x320 world is narrow")
	_check(hud.edge_arrows.visible, "the arrows show, compact")
	_check(hud.edge_arrows.shown().all(func(arrow: OfficeEdgeArrow) -> bool: return arrow.compact()), "every one")
	hud.fit(Vector2(SCREEN))
	await _frames(2)
	_check(
		not hud.edge_arrows_compact() and hud.edge_arrows.visible, "an 800x480 world shows them in full, no new models"
	)
	var shown := hud.edge_arrows.shown()
	_eq(shown.size(), 5, "five zones, five arrows")
	_eq(_label(shown[0], "%Zone").text, "2A", "each with its number")
	_check(_label(shown[0], "%Zone").visible, "shown")
	for arrow in shown:
		_check(
			hud.world_rect().encloses(arrow.get_global_rect()), "inside the 800x480 world: %s" % arrow.get_global_rect()
		)
	# 560x320: 420 wide with the drawer closed, 296 with it open.
	hud.fit(Vector2(560, 320))
	await _frames(2)
	_check(not hud.edge_arrows_compact(), "560x320, the drawer closed: full")
	hud.open_drawer()
	await _frames(1)
	_check(hud.edge_arrows_compact(), "the drawer opened narrows the world: compact at once")
	for arrow in hud.edge_arrows.shown():
		_check(
			hud.world_rect().encloses(arrow.get_global_rect()),
			"inside the narrower world: %s" % arrow.get_global_rect()
		)
	hud.close_drawer()
	await _frames(1)
	_check(not hud.edge_arrows_compact(), "closed again: full, the same five")
	_eq(hud.edge_arrows.shown().size(), 5, "all five")
	hud.open_overview()
	_check(not hud.edge_arrows.visible, "the OVERVIEW hides them")
	hud.close_overview()
	_check(hud.edge_arrows.visible, "and closing it shows the same arrows again")
	_eq(hud.edge_arrows.find_children("*", "OfficeEdgeArrow", true, false), nodes, "the same eight nodes")
	hud.free()


## An arrow is tall enough for its badge's pulse: at every lift the pulse takes
## (OfficeAttention.PULSES, up to 2 units), full or compact, the badge's drawn
## pixels stay inside the arrow's frame.
func test_the_arrow_badge_has_room_for_its_pulse() -> void:
	var hud := await _hud()
	var one: Array[EdgeArrowModel.Target] = [_target("f0", "3", Rect2(600, 100, 16, 16), 1000)]
	for screen: Vector2 in [Vector2(SCREEN), Vector2(480, 320)]:
		hud.fit(screen)
		hud.show_edge_arrows(EdgeArrowModel.of(Rect2(0, 0, 400, 300), one))
		await _frames(2)
		var arrow := hud.edge_arrows.shown()[0]
		var badge := arrow.badge()
		var used := badge.texture.get_image().get_used_rect()
		var inner := arrow.get_global_rect().grow(-1.0)
		for units: float in [0.0, -1.0, -2.0]:
			badge.lift(units)
			var local := Rect2(badge.get_rect().position + Vector2(used.position), Vector2(used.size))
			var drawn := badge.get_global_transform() * local
			_check(
				inner.encloses(drawn), "%s lift %d: the badge %s inside the frame %s" % [screen, units, drawn, inner]
			)
		badge.lift(0.0)
	hud.free()


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


## The arrows standing are the ones the office last worked out, through an
## overlay too. The overview (`O`) and the strategic view (`S`) hide them, and
## closing one over an unchanged office brings the same arrow back; but the
## last blocked agent going back to work while one is open leaves no arrow
## standing once it closes. Real keys, pressed and let go.
func test_no_arrow_outlives_its_blocked_agent_under_an_overlay() -> void:
	for code: Key in [KEY_O, KEY_S]:
		var overlay := OS.get_keycode_string(code)
		var office := await _live_office()
		var arrows := office.hud.edge_arrows
		await _frames(2)
		_eq(_arrow_texts(office), ["↓ 1A 1"], "%s: one blocked desk off screen, one arrow" % overlay)
		await _office_key(office, code)
		_check(_overlay_open(office), "%s opens its overlay" % overlay)
		_check(not arrows.visible, "%s: which hides the arrows" % overlay)
		await _office_key(office, code)
		await _frames(2)
		_check(not _overlay_open(office), "%s closes it" % overlay)
		_check(arrows.visible, "%s: over an unchanged office, the arrows are back" % overlay)
		_eq(_arrow_texts(office), ["↓ 1A 1"], "%s: the same arrow" % overlay)
		await _office_key(office, code)
		_feed(office, _nobody_blocked(fixture))
		await _frames(2)
		_check(_overlay_open(office), "%s: the overlay stays open over the new snapshot" % overlay)
		await _office_key(office, code)
		await _frames(2)
		_check(not _overlay_open(office), "%s closes it again" % overlay)
		_eq(office.frame.find_zone(_zone("hud")).zone_model.blocked, 0, "%s: nobody is blocked any more" % overlay)
		_check(not arrows.visible, "%s: so no arrows" % overlay)
		_eq(arrows.shown().size(), 0, "%s: and no arrow left standing" % overlay)
		_done(office)
		await _frames(2)


## The same when the map shown changes under the overlay. Local's 1A has a
## blocked desk off screen (an arrow), and bee's one agent is blocked. `N`,
## under either overlay, picks bee's agent (the longest wait: its start is
## unknown) and shows bee's map with its desk in view, where nothing waits out
## of sight; closing the overlay leaves no arrow, though Local's 1A still waits.
func test_no_arrow_outlives_a_machine_switch_under_an_overlay() -> void:
	var hive := HerdrFleet.pane_key(BEE, "hive")
	for code: Key in [KEY_O, KEY_S]:
		var overlay := OS.get_keycode_string(code)
		var office := await _two_machine_office()
		var arrows := office.hud.edge_arrows
		await _frames(2)
		_eq(office.navigator.shown_key, LOCAL, "%s: Local's map is shown" % overlay)
		_eq(_arrow_texts(office), ["↓ 1A 1"], "%s: Local's blocked desk off screen puts an arrow up" % overlay)
		await _office_key(office, code)
		_check(_overlay_open(office), "%s opens its overlay" % overlay)
		var presses := 0
		while office.navigator.shown_key != BEE and presses < 3:
			await _office_key(office, KEY_N)
			await _frames(2)
			presses += 1
		_eq(office.navigator.shown_key, BEE, "%s: N under it shows bee's map" % overlay)
		_check(_overlay_open(office), "%s: and leaves the overlay open" % overlay)
		await _office_key(office, code)
		await _frames(2)
		_check(not _overlay_open(office), "%s closes it" % overlay)
		_eq(office.frame.find_zone(hive).zone_model.blocked, 1, "%s: bee's agent still waits" % overlay)
		_eq(office.frame.find_zone(_zone("hud")).zone_model.blocked, 1, "%s: and so does Local's 1A" % overlay)
		_check(
			_desk_in_view(office, HerdrFleet.pane_key(BEE, "hive:p1")), "%s: at a desk in view on its own map" % overlay
		)
		_check(not arrows.visible, "%s: so no arrows" % overlay)
		_eq(arrows.shown().size(), 0, "%s: and no arrow left standing" % overlay)
		_done(office)
		await _frames(2)


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
	var label: Label = heading.get_node("%BuildingLabel")
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
	await _visit_floor(office, _zone("notes"))
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
	await _visit_floor(office, _zone("notes"))
	_eq(_current_headings(office), [LOCAL], "a row of Local's shows Local's map: Local's heading again")
	_done(office)
	var alone := await _live_office()
	_eq(alone.hud.spaces.headings().size(), 0, "Local alone: no heading")
	_done(alone)


## A real click on an edge arrow pans as far as it takes for that zone's
## longest-waiting blocked desk to be on screen. It counts one navigation and
## selects nothing: the pick, the selection and the card stay where they were.
func test_an_arrow_click_pans_to_the_desk_and_selects_nothing() -> void:
	var office := await _live_office()
	await _frames(2)
	var blocked := _pane("hud:p1")
	var navigator := office.navigator
	var arrow := office.hud.edge_arrows.shown()[0]
	_eq(arrow.pane_key(), blocked, "the arrow is for 1A's blocked desk")
	_check(not _desk_in_view(office, blocked), "which is out of the world's room")
	var before := [navigator.picked_key, navigator.active_key, office.hud.inspector.shown_pane_key()]
	var revision := navigator.nav_revision
	var pan := office.camera.pan
	var world := office.world.get_instance_id()
	await _click_at(arrow.get_global_rect().get_center())
	await _frames(2)
	_eq(navigator.nav_revision, revision + 1, "one navigation")
	_check(office.camera.pan != pan, "the map panned")
	_check(_desk_in_view(office, blocked), "the desk is inside the world's room")
	_check(_chip_on_screen(office, blocked), "and so is its chip")
	_eq(
		[navigator.picked_key, navigator.active_key, office.hud.inspector.shown_pane_key()],
		before,
		"nothing is selected"
	)
	_eq(office.world.get_instance_id(), world, "the same world")
	_check(not office.hud.edge_arrows.visible, "its desk in view, the arrow goes")
	_done(office)


## An arrow goes when a real drag brings its zone's blocked desks into view,
## and comes back when another drag takes them out again: worked out from the
## view as it moves, with no refresh at all.
func test_an_arrow_goes_when_a_drag_brings_its_desks_into_view() -> void:
	var office := await _live_office()
	await _frames(2)
	var blocked := _pane("hud:p1")
	_eq(_arrow_texts(office), ["↓ 1A 1"], "1A's blocked desk is off screen below: an arrow")
	office.refreshes = 0
	var attempts := office.layout_attempt_count()
	var middle := office.hud.world_rect().get_center()
	var start := office.camera.pan
	var steps := 0
	while not _chip_on_screen(office, blocked) and steps < 8:
		await _drag(middle, middle + Vector2(0, -100))
		await _frames(2)
		steps += 1
	_check(_chip_on_screen(office, blocked), "a real drag brings its chip into view")
	_check(not office.hud.edge_arrows.visible, "and the arrow goes")
	_eq(office.hud.edge_arrows.shown().size(), 0, "none left standing")
	while office.camera.pan.y > start.y and steps < 20:
		await _drag(middle, middle + Vector2(0, 100))
		await _frames(2)
		steps += 1
	_check(not _chip_on_screen(office, blocked), "dragged back, the chip is out of view again")
	_eq(_arrow_texts(office), ["↓ 1A 1"], "and the arrow is back")
	_eq(office.refreshes, 0, "no refresh at all during the drags")
	_eq(office.layout_attempt_count(), attempts, "and nothing planned")
	_done(office)


## Arrows are for the shown, live machine's map only. Another machine's blocked
## agent shows as its SPACES row's count and gets no arrow; on its own map it
## gets one, while its desk is off screen; and a machine that drops counts
## nobody waiting, so its map shows none.
func test_no_arrows_for_another_machine_or_a_disconnected_one() -> void:
	var office := await _two_machine_office(_nobody_blocked(fixture))
	# bee: six zones a window apart, its one blocked agent in the last.
	var six := _six_zones()
	for pane: Dictionary in _list(six, "panes"):
		if pane.pane_id == "w5:t0:p0":
			pane.agent_status = "blocked"
	_feed_bee(office, six)
	await _frames(2)
	var last := HerdrFleet.pane_key(BEE, "w5")
	var blocked := HerdrFleet.pane_key(BEE, "w5:t0:p0")
	_eq(office.navigator.shown_key, LOCAL, "Local's map is shown, nobody blocked on it")
	_eq(office.frame.find_zone(last).zone_model.blocked, 1, "bee's agent is blocked")
	_check(not office.hud.edge_arrows.visible, "no arrow for another machine's zone")
	_eq(office.hud.edge_arrows.shown().size(), 0, "none at all")
	var row := office.hud.spaces.row_for(last)
	_check(_node(row, "%BlockedIcon").visible, "its rail row carries the blocked badge")
	_eq(_label(row, "%BlockedCount").text, "1", "and the count")
	await _click_heading(office, BEE)
	await _frames(2)
	_eq(office.navigator.shown_key, BEE, "bee's heading shows bee's map")
	_check(not _chip_on_screen(office, blocked), "which opens on its first zone: the blocked desk is off screen")
	_eq(_arrow_texts(office), ["↓ 6 1"], "on its own map, an arrow points down to it")
	_bee(office)._go_offline()
	office.fleet.liveness_changed.emit()
	await _frames(2)
	_check(office.fleet.is_stale(BEE), "bee drops")
	_check(not office.hud.edge_arrows.visible, "a dropped machine's map has no arrow")
	_eq(office.hud.edge_arrows.shown().size(), 0, "none left standing")
	_check(not _node(row, "%BlockedIcon").visible, "and its row counts nobody")
	_done(office)


## Hovering an edge arrow, with a real pointer, outlines its zone's SPACES row
## (SpaceRowPointed), whether or not that row is in view; leaving puts it back.
## It only points: nothing is selected, panned or picked.
func test_hovering_an_arrow_outlines_its_zones_row() -> void:
	var office := await _live_office()
	await _frames(2)
	var arrow := office.hud.edge_arrows.shown()[0]
	var row := office.hud.spaces.row_for(_zone("hud"))
	var pan := office.camera.pan
	var revision := office.navigator.nav_revision
	_eq(row.theme_type_variation, &"SpaceRow", "1A's row as usual")
	await _pointer_to(arrow.get_global_rect().get_center())
	_eq(row.theme_type_variation, &"SpaceRowPointed", "the arrow under the pointer outlines 1A's row")
	_check(row.pointed(), "pointed at")
	for key: String in office.hud.spaces.row_keys():
		if key != _zone("hud"):
			_eq(office.hud.spaces.row_for(key).theme_type_variation, &"SpaceRow", "and no other: " + key)
	_eq([office.camera.pan, office.navigator.nav_revision], [pan, revision], "nothing panned or navigated")
	await _pointer_to(office.hud.world_rect().get_center())
	_eq(row.theme_type_variation, &"SpaceRow", "leaving restores it")
	# In view and pointed at once: the mark and the outline are apart.
	await _visit_floor(office, _zone("hs"))
	office.camera.pan = Vector2(office.camera.pan.x, office.camera.pan.y + 40)
	await _frames(3)
	var shown := office.hud.edge_arrows.shown()
	if not shown.is_empty() and row.in_view():
		await _pointer_to(shown[0].get_global_rect().get_center())
		_check(row.pointed() and row.in_view(), "a row in view can be outlined too")
	_done(office)


## No arrows while something covers the world: the OVERVIEW (`O`), the
## strategic view (`S`) or the terminal monitor (`M`). Each hides them at once
## and closing it brings them back, the same ones.
func test_no_arrows_under_the_overview_strategic_view_or_monitor() -> void:
	var office := await _live_office()
	var arrows := office.hud.edge_arrows
	await _frames(2)
	_eq(_arrow_texts(office), ["↓ 1A 1"], "an arrow to start with")
	for code: Key in [KEY_O, KEY_S]:
		var overlay := OS.get_keycode_string(code)
		await _office_key(office, code)
		_check(_overlay_open(office), "%s opens" % overlay)
		_check(not arrows.is_visible_in_tree(), "%s: no arrows" % overlay)
		await _office_key(office, code)
		await _frames(2)
		_check(not _overlay_open(office), "%s closes" % overlay)
		_eq(_arrow_texts(office), ["↓ 1A 1"], "%s closed: the arrow is back" % overlay)
		_check(arrows.is_visible_in_tree(), "%s closed: shown" % overlay)
	await _office_key(office, KEY_M)
	_check(office.hud.monitor_open(), "M opens the terminal monitor")
	_check(not arrows.is_visible_in_tree(), "the monitor: no arrows")
	var close: Control = office.hud.monitor.get_node("%CloseButton")
	await _click_at(close.get_global_rect().get_center())
	await _frames(2)
	_check(not office.hud.monitor_open(), "the monitor closes")
	_check(arrows.is_visible_in_tree(), "and the arrows are back")
	_eq(_arrow_texts(office), ["↓ 1A 1"], "the same one")
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
## frames, brings up the bubble tooltip naming the workspace's repository and
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
		await _visit_floor(office, key)
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
		_check(not office.hud.bubble_tip_shown(), key + ": no tooltip before the pointer comes")
		await _pointer_to(on)
		_check(office.hud.bubble_tip_shown(), key + ": hovering the sign shows the tooltip")
		_eq(office.hud.bubble_tip_text(), cases[key], key + ": naming its repository and checkout")
		await _pointer_to(on + Vector2(0, 120))
		_check(not office.hud.bubble_tip_shown(), key + ": moving off hides it")
		# The hover area is the drawn panel, sized to what the sign says: just
		# inside its right end the tooltip shows, just past it it does not.
		var middle := on.y
		var end := drawn.end.x - office.camera.position.x
		await _pointer_to(Vector2(end - 2.0, middle))
		_check(office.hud.bubble_tip_shown(), key + ": just inside the panel's right end, the tooltip")
		await _pointer_to(Vector2(end + 3.0, middle))
		_check(not office.hud.bubble_tip_shown(), key + ": just past it, none")
	_done(office)


# --- helpers ------------------------------------------------------------------


func _zone(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _node(holder: Node, path: String) -> Control:
	return holder.get_node(path)


## A real left click at `at`, in viewport pixels.
func _click_at(at: Vector2) -> void:
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## A real left click on machine `key`'s SPACES heading.
func _click_heading(office: OfficeDouble, key: String) -> void:
	var heading := office.hud.spaces.heading_for(key)
	if heading == null:
		_fail("no heading for " + key)
		return
	var scroll: ScrollContainer = office.hud.spaces.get_node("%Scroll")
	scroll.ensure_control_visible(heading)
	await _frames(2)
	await _click_at(heading.button().get_global_rect().get_center())


## A real pointer move to `at` (viewport pixels), then physics frames for the
## picking to answer.
func _pointer_to(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	await _frames(1)


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
		. filter(func(heading: OfficeBuildingHeading) -> bool: return heading.is_current())
		. map(func(heading: OfficeBuildingHeading) -> String: return heading.key)
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


## Whether the chip over the desk of `key` is on screen: what the arrows ask.
func _chip_on_screen(office: OfficeDouble, key: String) -> bool:
	var seat := office.floor_view.seat(key)
	if seat == null:
		return false
	var chip := seat.node.bubble_rect()
	var rect := chip if chip.has_area() else seat.node.target_rect()
	return rect.intersects(_view(office))


## Each shown arrow's words, glyph to count, as one string.
func _arrow_texts(office: OfficeDouble) -> Array:
	return office.hud.edge_arrows.shown().map(
		func(arrow: OfficeEdgeArrow) -> String:
			var words := PackedStringArray()
			for part: String in ["%Glyph", "%Zone", "%Count"]:
				var label: Label = arrow.get_node(part)
				if label.visible:
					words.append(label.text)
			return " ".join(words)
	)


## A blocked desk of zone `zone` (numbered `number`, named after its key) at
## `rect`, waiting `msec`.
func _target(zone: String, number: String, rect: Rect2, msec: int) -> EdgeArrowModel.Target:
	var target := EdgeArrowModel.Target.new()
	target.zone_key = zone
	target.number = number
	target.words = "%s %s" % [number, zone.to_upper()]
	target.machine = LOCAL
	target.pane_key = zone + ":p"
	target.rect = rect
	target.wait.msec = msec
	return target


## A HUD on its own, laid out for the suite's screen.
func _hud() -> OfficeHud:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: OfficeHud = scene.instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(Vector2(SCREEN))
	await _frames(2)
	return hud


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


## Whether the overview or the strategic view covers the world.
func _overlay_open(office: OfficeDouble) -> bool:
	return office.hud.overview_open() or office.hud.strategic_open()


## `snapshot` with every blocked agent back at work.
func _nobody_blocked(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for pane: Dictionary in _list(result, "panes"):
		if str(pane.get("agent_status", "")) == "blocked":
			pane.agent_status = "working"
	return result


## Whether the desk drawn for `key` answers a click wholly inside the world's
## room on screen.
func _desk_in_view(office: OfficeDouble, key: String) -> bool:
	var target := _desk_target(office, key)
	return office.hud.world_rect().encloses(Rect2(target.position - office.camera.position, target.size))


## Six workspaces of four working agents each, herdr's focus on the first: a
## map whose zones are a window apart.
func _six_zones() -> Dictionary:
	var raw := {"workspaces": [], "tabs": [], "panes": [], "layouts": [], "focused_pane_id": "w0:t0:p0"}
	for zone in 6:
		var workspace := "w%d" % zone
		var tab := workspace + ":t0"
		_list(raw, "workspaces").append({"workspace_id": workspace, "number": zone + 1, "label": workspace})
		_list(raw, "tabs").append({"workspace_id": workspace, "tab_id": tab, "number": 1})
		for index in 4:
			var pane := "%s:p%d" % [tab, index]
			_list(raw, "panes").append(
				{
					"workspace_id": workspace,
					"tab_id": tab,
					"pane_id": pane,
					"terminal_id": "terminal-" + pane,
					"agent": "claude",
					"agent_status": "working"
				}
			)
	return raw


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
