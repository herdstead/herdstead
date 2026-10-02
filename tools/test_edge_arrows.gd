extends "res://tools/office_test_base.gd"
## The arrows on the world's edges (OfficeEdgeArrows, EdgeArrowModel in) toward
## the zones of the shown map whose blocked desks are off screen: where each
## stands, the pool of eight and its `+N` note, what a crowded edge folds, the
## compact form on a narrow world, a click panning to the desk and selecting
## nothing, the hover outlining the zone's SPACES row, and no arrow under an
## overlay or left standing after one. Clicks, hovers, drags and keys go through
## real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_edge_arrows.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## (Split out of tools/test_space_rail.gd, which keeps the rail's own cases, so
## that both files stay under gdlint's max-file-lines. The cases moved as they
## were: `the same way` in the arrow's focus-race case is the heading's, there.)

## The most of the world's width an arrow may cover, in any window. A full
## arrow is about 56 units of the narrowest world that shows one in full
## (OfficeHud.edge_arrows_compact_from, 360); below that it is compact.
const MAX_ARROW_COVER := 1.0 / 4.0


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("edge-arrow-socks"))
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
	return "EDGE ARROW TESTS"


# --- where the arrows stand -----------------------------------------------------


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


## However many zones wait beyond one edge, the arrows there never meet: an
## edge shows as many as it has room for (its run between the corners' rows,
## the theme's inset and gap, the arrows' own sizes, compact or not), longest
## wait first, and folds the rest into a `+N` note on that edge whose tooltip
## names each of them. At the 480x320 minimum, there with the drawer open, and
## at 2x with the drawer open, on each of the four edges, with a full pool and
## with more zones than the pool holds: every arrow inside the world, the side
## edges' clear of the corners' rows, and arrows and notes counting every zone.
func test_a_crowded_edge_folds_what_it_has_no_room_for() -> void:
	var hud := await _hud()
	# Each window, and whether its drawer is open.
	var screens: Dictionary[String, Vector2] = {
		"480x320": Vector2(480, 320),
		"480x320, the drawer open": Vector2(480, 320),
		"960x480, the drawer open": Vector2(960, 480),
	}
	for screen: String in screens:
		hud.fit(screens[screen])
		if screen.ends_with("open"):
			hud.open_drawer()
		else:
			hud.close_drawer()
		await _frames(2)
		var view := Rect2(Vector2.ZERO, hud.world_rect().size)
		for edge: EdgeArrowModel.Edge in EdgeArrowModel.GLYPHS:
			for zones: int in [EdgeArrowModel.POOL, EdgeArrowModel.POOL + 4]:
				var where := "%s, %s, %d zones" % [screen, EdgeArrowModel.GLYPHS[edge], zones]
				hud.show_edge_arrows(EdgeArrowModel.of(view, _beyond(view, edge, zones)))
				await _frames(2)
				var stood := _standing(hud, where)
				print("EDGE_FOLD: %s in %s: %s" % [where, hud.world_rect().size, stood.said()])
				_check(not stood.ways.is_empty(), where + ": at least one arrow is a way to its zone")
				_eq(stood.ways.size() + stood.folded, zones, where + ": the arrows and the notes count every zone")
				_eq(stood.lines.size(), stood.folded, where + ": a note's tooltip has a line for each zone it counts")
				for index in zones:
					var zone := "z%d" % index
					# The zones that keep an arrow are the ones that waited longest.
					_eq(stood.ways.has(zone), index < stood.ways.size(), "%s: %s by its wait" % [where, zone])
					if index >= stood.ways.size():
						var line := (
							"%s %d %s · 1 blocked · " % [EdgeArrowModel.GLYPHS[edge], index + 1, zone.to_upper()]
						)
						var named := Array(stood.lines).any(func(said: String) -> bool: return said.begins_with(line))
						_check(named, "%s: a note names %s: %s" % [where, zone, stood.lines])
	hud.free()


## Pure (EdgeArrowModel.fit()): given how many arrows each edge has room for,
## an edge with more than that keeps its first ones and gives its last place
## to a `+N` note for the rest, where the first of them stood in the list and
## on the edge; an edge that is not short is left alone, one with room for
## none shows none, and the pool's own note is counted in like any arrow, for
## the zones it stands for.
func test_an_edge_keeps_what_it_has_room_for_and_notes_the_rest() -> void:
	var view := Rect2(0, 0, 400, 300)
	var targets: Array[EdgeArrowModel.Target] = []
	# z0..z4 below the view and y0, y1 to its right; z0 has waited longest, y1 least.
	for index in 5:
		targets.append(_target("z%d" % index, str(index + 1), Rect2(40 * index, 400, 16, 16), (9 - index) * 60000))
	for index in 2:
		targets.append(
			_target("y%d" % index, str(index + 6), Rect2(600, 100 + 40 * index, 16, 16), (2 - index) * 60000)
		)
	var all := EdgeArrowModel.of(view, targets)
	var keys := func(arrows: Array[EdgeArrowModel]) -> Array:
		return arrows.map(func(arrow: EdgeArrowModel) -> String: return arrow.zone_key)
	_eq(keys.call(all), ["z0", "z1", "z2", "z3", "z4", "y0", "y1"], "seven zones: five below, two to the right")
	var room: Dictionary[EdgeArrowModel.Edge, int] = {}
	_eq(EdgeArrowModel.fit(all, room), all, "no edge named: every arrow as handed")
	room = {EdgeArrowModel.Edge.BOTTOM: 5, EdgeArrowModel.Edge.RIGHT: 2}
	_eq(EdgeArrowModel.fit(all, room), all, "room for all of them: the same")
	room = {EdgeArrowModel.Edge.BOTTOM: 3}
	var short := EdgeArrowModel.fit(all, room)
	_eq(keys.call(short), ["z0", "z1", "", "y0", "y1"], "the bottom holds three: two arrows, then a note")
	var note := short[2]
	_eq([note.number, note.more, note.blocked], ["+3", 3, 3], "which counts the other three zones and their desks")
	_eq([note.edge, note.along, note.pane_key], [EdgeArrowModel.Edge.BOTTOM, all[2].along, ""], "where the first stood")
	_eq(note.wait.msec, all[2].wait.msec, "with its wait")
	var lines := note.tip.split("\n")
	_eq(lines.size(), 3, "its tooltip has their three lines: " + note.tip)
	for index in 3:
		_check(lines[index].begins_with("↓ %d Z%d · 1 blocked · longest " % [index + 3, index + 2]), lines[index])
	_eq([short[3], short[4]], [all[5], all[6]], "the right edge is left alone")
	room = {EdgeArrowModel.Edge.BOTTOM: 1, EdgeArrowModel.Edge.RIGHT: 1}
	var notes := EdgeArrowModel.fit(all, room)
	_eq(
		notes.map(func(arrow: EdgeArrowModel) -> Array: return [arrow.number, arrow.edge, arrow.zone_key]),
		[["+5", EdgeArrowModel.Edge.BOTTOM, ""], ["+2", EdgeArrowModel.Edge.RIGHT, ""]],
		"one place each: a note per edge, for all of its zones"
	)
	_check(
		notes[1].tip.begins_with("→ 6 Y0 · ") and notes[1].tip.contains("\n→ 7 Y1 · "),
		"each with its own: " + notes[1].tip
	)
	room = {EdgeArrowModel.Edge.BOTTOM: 0}
	_eq(keys.call(EdgeArrowModel.fit(all, room)), ["y0", "y1"], "an edge with room for none shows none")
	# Ten zones below: of() keeps seven and notes three; a bottom edge that holds
	# four keeps three of the seven and counts the other four in with that note.
	var many: Array[EdgeArrowModel.Target] = []
	for index in 10:
		many.append(_target("f%d" % index, str(index + 1), Rect2(40 * index, 400, 16, 16), (20 - index) * 60000))
	many.append(_target("f8", "9", Rect2(0, 440, 16, 16), 1000))
	var pooled := EdgeArrowModel.of(view, many)
	_eq(
		[pooled.size(), pooled[7].number, pooled[7].blocked], [8, "+3", 4], "the pool: seven and a note for three zones"
	)
	room = {EdgeArrowModel.Edge.BOTTOM: 4}
	var both := EdgeArrowModel.fit(pooled, room)
	_eq(keys.call(both), ["f0", "f1", "f2", ""], "three arrows and one note")
	_eq([both[3].number, both[3].more, both[3].blocked], ["+7", 7, 8], "for seven zones and their eight desks")
	_eq(both[3].tip.split("\n").size(), 7, "a line each: " + both[3].tip)
	_check(both[3].tip.ends_with(pooled[7].tip), "the pool's own lines last")
	_eq([pooled[7].number, pooled[7].tip.split("\n").size()], ["+3", 3], "and the list handed in is not changed")


## Eight zones blocked below the view at the 480x320 minimum, in a live office:
## the arrows stand apart inside the world and count all eight between them,
## and a real click at the centre of the first, the zone that has waited
## longest, is that arrow's: the map pans to its desk and to no other zone's.
func test_a_click_on_the_first_of_a_crowd_of_arrows_pans_to_its_desk() -> void:
	var office := await _live_office(_blocked_zones(9), Vector2(480, 320))
	await _frames(3)
	var stood := _standing(office.hud, "nine zones at 480x320")
	_eq(stood.ways.size() + stood.folded, 8, "the arrows and the note count the eight blocked zones")
	var first := office.hud.edge_arrows.shown()[0]
	var wanted := _pane("w1:p0")
	_eq([first.pane_key(), first.disabled], [wanted, false], "the first arrow is the way to the longest wait")
	_check(not _desk_in_view(office, wanted), "whose desk is out of the world's room")
	var picked: Array = []
	office.hud.arrow_picked.connect(func(key: String) -> void: picked.append(key))
	var revision := office.navigator.nav_revision
	var selected := office.navigator.active_key
	await _click_at(first.get_global_rect().get_center())
	await _frames(2)
	_eq(picked, [wanted], "a real click at its centre is that arrow's")
	_check(_desk_in_view(office, wanted), "and the map pans to its desk")
	_eq(
		[office.navigator.nav_revision, office.navigator.active_key],
		[revision + 1, selected],
		"one navigation, no pick"
	)
	var after := _standing(office.hud, "after the pan")
	_check(not after.ways.has(_zone("w1")), "its desk in view, that zone's arrow is gone: " + after.said())
	_done(office)


## What the arrows were handed is kept whole: zones folded for a narrow world
## get their arrows back the moment it widens, and are folded again when it
## narrows or goes compact, with no new list from the office and no new node.
func test_arrows_folded_for_a_narrow_world_come_back_as_it_widens() -> void:
	var hud := await _hud()
	var nodes := hud.edge_arrows.find_children("*", "OfficeEdgeArrow", true, false)
	hud.fit(Vector2(480, 320))
	await _frames(2)
	var view := Rect2(Vector2.ZERO, hud.world_rect().size)
	hud.show_edge_arrows(EdgeArrowModel.of(view, _beyond(view, EdgeArrowModel.Edge.BOTTOM, 8)))
	await _frames(2)
	var narrow := _standing(hud, "480x320")
	_check(narrow.ways.size() < 8 and narrow.folded > 0, "a 340-wide world folds some: " + narrow.said())
	_eq(narrow.ways.size() + narrow.folded, 8, "counting all eight")
	hud.fit(Vector2(960, 480))
	await _frames(2)
	var wide := _standing(hud, "960x480")
	_eq([wide.ways.size(), wide.folded], [8, 0], "an 820-wide world has room for all eight: every zone its own arrow")
	_eq(wide.ways, ["z0", "z1", "z2", "z3", "z4", "z5", "z6", "z7"], "in the order handed, longest wait first")
	_check(
		hud.edge_arrows.shown().all(
			func(arrow: OfficeEdgeArrow) -> bool: return not arrow.disabled and not arrow.compact()
		),
		"each a way there, in full"
	)
	# 560x320: 420 wide with the drawer closed (full arrows), 296 and compact with it open.
	hud.fit(Vector2(560, 320))
	await _frames(2)
	var closed := _standing(hud, "560x320")
	_eq(closed.ways.size() + closed.folded, 8, "560x320: all eight counted")
	_check(closed.folded > 0, "560x320: folded again: " + closed.said())
	hud.open_drawer()
	await _frames(2)
	_check(hud.edge_arrows_compact(), "the drawer open narrows the world: compact")
	var opened := _standing(hud, "560x320, the drawer open")
	_eq(opened.ways.size() + opened.folded, 8, "the drawer open: all eight counted")
	_check(opened.ways.size() < closed.ways.size(), "with fewer arrows of their own: " + opened.said())
	hud.close_drawer()
	hud.fit(Vector2(480, 320))
	await _frames(2)
	var again := _standing(hud, "480x320 again")
	_eq([again.ways, again.folded], [narrow.ways, narrow.folded], "back at 480x320: folded as at first")
	_eq(hud.edge_arrows.find_children("*", "OfficeEdgeArrow", true, false), nodes, "the same eight nodes throughout")
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


# --- clicks, drags and the pointer ----------------------------------------------


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


## An edge arrow wins the same way: a real press on 1A's arrow, a snapshot with
## the focus moved to a desk out of sight, the release. The map pans to the
## arrow's desk, not to the newly focused one; the next move is followed again.
func test_an_arrow_click_wins_over_a_focus_move_not_drawn_yet() -> void:
	var office := await _live_office()
	await _frames(2)
	var navigator := office.navigator
	var arrow := office.hud.edge_arrows.shown()[0]
	var wanted := arrow.pane_key()
	var focused := _pane("notes:p1")
	var at := arrow.get_global_rect().get_center()
	var revision := navigator.nav_revision
	_eq(wanted, _pane("hud:p1"), "the arrow is for 1A's blocked desk")
	_check(not _desk_in_view(office, wanted) and not _desk_in_view(office, focused), "it and 4's desk are out of sight")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	var drawn := office.refreshes
	_arrive(office, _focused_on(fixture, "notes:p1"))
	_eq([office.refreshes, navigator.active_key], [drawn, _pane("hs:p1")], "a snapshot with the focus moved is waiting")
	_release_now(at)
	await _frames(3)
	_check(_desk_in_view(office, wanted), "released: the arrow's desk is inside the world's room")
	_check(not _desk_in_view(office, focused), "and not the newly focused one")
	_eq(navigator.active_key, focused, "which is the selection all the same")
	_eq(navigator.nav_revision, revision + 1, "one navigation: the arrow")
	_check(not _desk_in_view(office, _pane("data:p2")), "1B's desk is out of sight too")
	_feed(office, _focused_on(fixture, "data:p2"))
	await _frames(3)
	_check(_desk_in_view(office, _pane("data:p2")), "the next move of the focus is followed again")
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
	# In view and pointed at once: the mark and the outline are apart. Pan down
	# until 1A's zone comes into view; its blocked desk is still below it.
	_check(not row.in_view(), "1A's zone starts out of view")
	var steps := 0
	while not row.in_view() and steps < 40:
		office.camera.pan += Vector2(0, 4)
		await _frames(2)
		steps += 1
	_check(row.in_view(), "panned down, 1A's zone is in view and its row marked")
	var shown := office.hud.edge_arrows.shown()
	_eq(
		shown.map(func(each: OfficeEdgeArrow) -> String: return each.zone_key()),
		[_zone("hud")],
		"while its blocked desk is still off screen: its arrow stands"
	)
	_eq(row.theme_type_variation, &"SpaceRow", "not outlined yet")
	await _pointer_to(shown[0].get_global_rect().get_center())
	_check(row.pointed() and row.in_view(), "a row in view is outlined too, and keeps its mark")
	_eq(row.theme_type_variation, &"SpaceRowPointed", "by the theme's look")
	_done(office)


## An arrow's node is handed another zone while the pointer rests on it (the
## zone it stood for stopped waiting, another one waits): the row outlined is
## the zone the arrow stands for now, with no move of the pointer; and when
## nobody waits any more and the arrow goes, no row is outlined.
func test_an_arrow_handed_another_zone_under_the_pointer_outlines_that_zones_row() -> void:
	var first := _six_zones()
	_record_of(first, "w4:t0:p0").agent_status = "blocked"
	var office := await _live_office(first)
	await _frames(2)
	var arrow := office.hud.edge_arrows.shown()[0]
	var rail := office.hud.spaces
	_eq(arrow.zone_key(), _zone("w4"), "an arrow for 5, whose blocked desk is below the view")
	var at := arrow.get_global_rect().get_center()
	await _pointer_to(at)
	_check(rail.row_for(_zone("w4")).pointed(), "the pointer on it outlines 5's row")
	var second := _six_zones()
	_record_of(second, "w5:t0:p0").agent_status = "blocked"
	_feed(office, second)
	await _frames(3)
	var still := office.hud.edge_arrows.shown()
	_check(still.size() == 1 and still[0] == arrow, "the same node is the one arrow still")
	_eq(arrow.zone_key(), _zone("w5"), "handed 6, which waits now")
	_check(arrow.get_global_rect().has_point(at), "and still under the pointer, which has not moved")
	_check(rail.row_for(_zone("w5")).pointed(), "6's row is the one outlined")
	_check(not rail.row_for(_zone("w4")).pointed(), "5's no more")
	_feed(office, _six_zones())
	await _frames(3)
	_eq(office.hud.edge_arrows.shown().size(), 0, "nobody waits: the arrow goes")
	_eq(_rows_pointed(office), [], "and no row is outlined")
	_done(office)


## Two arrows change places in the pool while neither moves on screen (the
## bottom zone's pane takes a new terminal, its wait starts over, the top zone
## is the longest wait now): the row outlined stays the zone of the arrow under
## the resting pointer. And an arrow that comes back under the resting pointer,
## an overlay closed, outlines its row again with no move of the pointer.
func test_arrows_changing_pool_places_keep_the_row_under_the_pointer_outlined() -> void:
	var raw := _six_zones()
	_record_of(raw, "w5:t0:p0").agent_status = "blocked"
	var office := await _live_office(raw)
	await _frames(4)
	_record_of(raw, "w0:t0:p1").agent_status = "blocked"
	_feed(office, raw)
	await _frames(3)
	await _visit_zone(office, _zone("w2"))
	await _frames(3)
	var bottom := _zone("w5")
	_eq(_arrow_zones(office), [bottom, _zone("w0")], "6 below and 1 above the view; 6 has waited longer")
	var at := office.hud.edge_arrows.shown()[0].get_global_rect().get_center()
	await _pointer_to(at)
	_eq(_rows_pointed(office), [bottom], "the pointer on 6's arrow outlines 6's row")
	_record_of(raw, "w5:t0:p0").terminal_id = "another-terminal"
	_feed(office, raw)
	await _frames(4)
	_eq(_arrow_zones(office), [_zone("w0"), bottom], "6's wait started over: the two changed pool places")
	var under: Array[String] = []
	for arrow in office.hud.edge_arrows.shown():
		if arrow.get_global_rect().has_point(at):
			under.append(arrow.zone_key())
	_eq(under, [bottom] as Array[String], "6's arrow is where it was, under the pointer")
	_eq(_rows_pointed(office), [bottom], "and 6's row is still the one outlined")
	await _office_key(office, KEY_O)
	_eq(_rows_pointed(office), [], "the overview over the world: no arrow, no row outlined")
	await _office_key(office, KEY_O)
	await _frames(2)
	_eq(_rows_pointed(office), [bottom], "closed: the arrow is back under the pointer, and its row outlined")
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


# --- helpers --------------------------------------------------------------------


func _zone(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _node(holder: Node, path: String) -> Control:
	return holder.get_node(path)


## The part of the world on screen, in global coordinates.
func _view(office: OfficeDouble) -> Rect2:
	return Rect2(office.camera.position + office.hud.world_rect().position, office.hud.world_rect().size)


## Whether the chip over the desk of `key` is on screen: what the arrows ask.
func _chip_on_screen(office: OfficeDouble, key: String) -> bool:
	var seat := office.floor_view.seat(key)
	if seat == null:
		return false
	var chip := seat.node.chip_rect()
	var rect := chip if chip.has_area() else seat.node.target_rect()
	return rect.intersects(_view(office))


## The zones of the arrows shown, in pool order (longest wait first).
func _arrow_zones(office: OfficeDouble) -> Array:
	return office.hud.edge_arrows.shown().map(func(arrow: OfficeEdgeArrow) -> String: return arrow.zone_key())


## The rows the rail outlines as pointed at.
func _rows_pointed(office: OfficeDouble) -> Array:
	var rail := office.hud.spaces
	return rail.row_keys().filter(func(key: String) -> bool: return rail.row_for(key).pointed())


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


## What _standing() read off the arrows a HUD shows.
class Standing:
	extends RefCounted
	## The zones with an arrow of their own, in the arrows' order.
	var ways: Array = []
	## How many zones the `+N` notes count between them, and their tooltips' lines.
	var folded := 0
	var lines := PackedStringArray()

	func said() -> String:
		return "%d arrows, +%d folded" % [ways.size(), folded]


## The arrows `hud` shows now, read off its nodes. Checks, wherever they stand,
## that no two meet, that each is inside the world's rectangle, and that an
## arrow on a side edge is clear of the rows along the top and the bottom.
func _standing(hud: OfficeHud, where: String) -> Standing:
	var stood := Standing.new()
	var room := hud.world_rect()
	var inset := float(hud.edge_arrows.get_theme_constant(&"inset", &"EdgeArrows"))
	var gap := float(hud.edge_arrows.get_theme_constant(&"gap", &"EdgeArrows"))
	var shown := hud.edge_arrows.shown()
	var models := hud.edge_arrows.models()
	for index in shown.size():
		var arrow := shown[index]
		var rect := arrow.get_global_rect()
		_check(room.encloses(rect), "%s: arrow %d inside the world %s: %s" % [where, index, room, rect])
		for other in range(index + 1, shown.size()):
			var beside := shown[other].get_global_rect()
			_check(
				not rect.intersects(beside), "%s: arrows %d and %d apart: %s, %s" % [where, index, other, rect, beside]
			)
		var edge := models[index].edge
		if edge == EdgeArrowModel.Edge.LEFT or edge == EdgeArrowModel.Edge.RIGHT:
			var row := inset + rect.size.y + gap
			var clear := rect.position.y >= room.position.y + row and rect.end.y <= room.end.y - row
			_check(clear, "%s: arrow %d clear of the corners' rows: %s in %s" % [where, index, rect, room])
		if arrow.disabled:
			stood.folded += _label(arrow, "%Zone").text.trim_prefix("+").to_int()
			stood.lines.append_array(arrow.tooltip_text.split("\n"))
		else:
			stood.ways.append(arrow.zone_key())
	return stood


## `count` blocked desks of as many zones `z0`.., all at one place 1000 units
## beyond `edge` of `view`; `z0` has waited longest.
func _beyond(view: Rect2, edge: EdgeArrowModel.Edge, count: int) -> Array[EdgeArrowModel.Target]:
	var at := view.get_center()
	match edge:
		EdgeArrowModel.Edge.TOP:
			at.y = view.position.y - 1000.0
		EdgeArrowModel.Edge.BOTTOM:
			at.y = view.end.y + 1000.0
		EdgeArrowModel.Edge.LEFT:
			at.x = view.position.x - 1000.0
		EdgeArrowModel.Edge.RIGHT:
			at.x = view.end.x + 1000.0
	var targets: Array[EdgeArrowModel.Target] = []
	for index in count:
		targets.append(
			_target("z%d" % index, str(index + 1), Rect2(at - Vector2(8, 8), Vector2(16, 16)), 1000 * (count - index))
		)
	return targets


## `count` workspaces `w0`.. of one tab and one claude agent each, herdr's
## focus in the first, which works; every other one is blocked.
func _blocked_zones(count: int) -> Dictionary:
	var raw := {"workspaces": [], "tabs": [], "panes": [], "layouts": [], "focused_pane_id": "w0:p0"}
	for index in count:
		var workspace := "w%d" % index
		var tab := workspace + ":t"
		_list(raw, "workspaces").append({"workspace_id": workspace, "number": index + 1, "label": workspace})
		_list(raw, "tabs").append({"workspace_id": workspace, "tab_id": tab, "number": 1, "label": "main"})
		var pane := {"workspace_id": workspace, "tab_id": tab, "pane_id": workspace + ":p0"}
		pane.merge({"terminal_id": "terminal-" + workspace, "agent": "claude"})
		pane.agent_status = "working" if index == 0 else "blocked"
		_list(raw, "panes").append(pane)
	return raw


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


## The record of pane `pane_id` in `snapshot`, to change in place.
func _record_of(snapshot: Dictionary, pane_id: String) -> Dictionary:
	for pane: Dictionary in _list(snapshot, "panes"):
		if str(pane.get("pane_id", "")) == pane_id:
			return pane
	_fail("no pane " + pane_id)
	return {}
