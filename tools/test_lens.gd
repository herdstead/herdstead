extends "res://tools/office_test_base.gd"
## The info lens and the hover mark.
## Holding `L` adds one time line per agent (the OVERVIEW's FOR, from
## StateLog.wait_of(), in the in-world compact form), shows every seat's name
## plate, hides the blocked chip's parts, washes every pod's floor in its most
## urgent state on the FLOORS windows' scale and dims the furnishing; letting
## go puts everything back. Hovering a NEWS item, a list
## row, an EVENTS row or an edge arrow points at the desk it names (a dashed frame
## of its own) or, on another machine or for an arrow, at that zone's SPACES row, and never
## selects, pans, reads or writes. Keys and the pointer go through real input.
## Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_lens.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the NEWS / EVENTS suite does.

const BUBBLE_PARTS: Array[String] = ["%Frame", "%Wait"]


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("lens-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "LENS TESTS"


## A case that failed while `L` was down must not leave it held for the next.
func _after_case() -> void:
	Input.parse_input_event(_l_key(false))
	Input.flush_buffered_events()
	super()


# --- the lens -----------------------------------------------------------------


## Held, every agent's desk says how long it has been in its state, the
## OVERVIEW's own wait at the same moment in the in-world compact form; a shell
## says nothing. Every seat at its desk shows its name plate (which, without
## the lens, only a hovered or selected seat does); the plates' words and the
## badges do not change, and the top bar's theme line says the lens is on.
## Let go, every line and plate hides, the furnishing is as bright as before,
## the pods' floors plain again and the theme line the pack's.
func test_holding_l_adds_the_wait_line_and_letting_go_restores_everything() -> void:
	var office := await _live_office()
	var one := _with(fixture, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	_feed(office, _with(one, "api:p4", {"agent_status": "done"}))
	office.settle()
	await _frames(2)
	var signals := _signals(office)
	var theme := office.hud.bar.theme_line()
	var plates := {}
	for station in _seats(office):
		_check(not _lens(station).visible, "no lens line before L: " + station.pane_key)
		# Only the selected seat's plate shows before L (nothing is hovered).
		plates[station.pane_key] = _plate(station).visible
	_check(plates.values().count(false) > 1, "most plates are hidden before L")
	await _hold()
	_check(office.lens.held, "L held is the lens")
	# One read of the clock and the lines, with no frame between them.
	var now := office.lens.now_msec
	var texts := _lens_texts(office)
	var model := OverviewModel.of(
		office.frame, office.fleet.state_log(), "", OverviewModel.Sort.STATE, false, OverviewModel.Filter.ALL, now
	)
	var agents := 0
	for row in model.rows:
		if not texts.has(row.key):
			continue
		var pane := office.frame.pane(row.key)
		if pane.provider.is_empty() and not pane.launching():
			_eq(texts[row.key], "", "a shell has no line: " + row.key)
			continue
		var wait := StateLog.wait_of(office.fleet.state_log().track(row.key), now)
		_eq(texts[row.key], OfficeAttention.compact_duration(wait.msec / 1000.0, wait.plus), "compact: " + row.key)
		_eq(OverviewLine.for_text(row), OfficeAttention.wait_text(wait), "the OVERVIEW's FOR, same wait: " + row.key)
		agents += 1
	# Every agent of the map says how long: api's three (p1, p2, p4), web's two,
	# infra's three and data's two, every zone being drawn now.
	_eq(agents, 10, "every agent of the map says how long")
	_eq(_signals(office), signals, "the plates' words and the badges are as they were")
	for station in _seats(office):
		_eq(_plate(station).visible, not station.away(), "held, the plate shows at the desk: " + station.pane_key)
	_eq(office.hud.bar.theme_line(), "LENS · hold L", "the top bar says the lens is on")
	await _let_go()
	_check(not office.lens.held, "let go: no lens")
	for station in _seats(office):
		_check(not _lens(station).visible, "no lens line after L: " + station.pane_key)
		_eq(_plate(station).visible, plates[station.pane_key], "let go, the plate as before: " + station.pane_key)
	for node in _furnishing(office):
		_eq(node.modulate, Color.WHITE, "furnishing as bright as before: " + str(node.name))
	for tab: String in office.floor_view.desks:
		_check(not office.floor_view.desks[tab].wash.visible, "the pod's floor is plain again: " + tab)
	_eq(_signals(office), signals, "the plates' words and the badges still as they were")
	_eq(office.hud.bar.theme_line(), theme, "the theme line is the pack's again")
	_done(office)


## Under the lens the wait is the lens line's: the blocked seat keeps its
## bubble (its click and hover rectangle, and the question reader's
## `visible`), but nothing of it is drawn, and no question tooltip comes up
## over it. An agent blocked in the first snapshot began before this office
## watched: the bubble has no wait to tell, but its line says `Ns+`.
func test_the_lens_hides_the_bubble_parts_but_not_the_blocked_seat() -> void:
	var first := _with(fixture, "api:p1", {"agent_status": "blocked"})
	var office := await _live_office(first)
	# api:p4 is seen going blocked, so its bubble has a wait to draw.
	_feed(office, _with(first, "api:p4", {"agent_status": "blocked"}))
	var key := _pk("api:p4")
	office.settle()
	await _text_tick()
	var station := _station(office, key)
	var bubble := station.bubble()
	for part in BUBBLE_PARTS:
		_check(_part(bubble, part).is_visible_in_tree(), "without the lens the bubble draws " + part)
	var at := await _bubble_at(office, key)
	await _hover(at)
	_check(office.hud.bubble_tip_shown(), "without the lens its tooltip comes up")
	await _hold()
	_check(not office.hud.bubble_tip_shown(), "the lens takes the tooltip down")
	_check(bubble.visible, "the seat is still a blocked one")
	_check(station.bubble_rect().has_area(), "and its bubble rectangle is where it was")
	for part in BUBBLE_PARTS:
		_check(not _part(bubble, part).is_visible_in_tree(), "under the lens the bubble draws no " + part)
	var line := _lens(station)
	_check(line.visible, "the lens line says the wait")
	_check(not line.text.ends_with("+"), "seen going blocked: " + line.text)
	var early := _lens(_station(office, _pk("api:p1")))
	var plus := RegEx.create_from_string("^\\d+s\\+$")
	_check(early.visible, "the agent blocked from the first snapshot has a line too")
	_check(plus.search(early.text) != null, "blocked since before this office watched: " + early.text)
	await _hover(office.hud.world_rect().position + Vector2(4, 4))
	await _hover(at)
	_check(not office.hud.bubble_tip_shown(), "no tooltip over the bubble while L is held")
	await _let_go()
	await _text_tick()
	for part in BUBBLE_PARTS:
		_check(_part(bubble, part).is_visible_in_tree(), "let go, the bubble draws %s again" % part)
	_done(office)


## A shell has nobody to time: no line, held or not. A pane the state log has
## no track of says `?`; a machine that dropped says nothing (invariant 4); an
## agent says StateLog.wait_of() in OfficeAttention.compact_duration(), the
## in-world form of the wait the OVERVIEW's FOR writes in wait_text(): one wait,
## two spellings. (The line used to be wait_text() itself; `1h 05m+` does not
## fit a 30-unit lens row, and `99h 59m+` would not either.)
func test_shells_have_no_wait_line_and_unknown_tracks_say_question_mark() -> void:
	var office := await _live_office()
	await _hold()
	var shell := _station(office, _pk("api:p3"))
	_check(shell.actor() == null, "api:p3 is a shell")
	_check(not _lens(shell).visible, "a shell has no lens line")
	_check(_lens(_station(office, _pk("api:p1"))).visible, "an agent at the same table has one")
	var agent := office.frame.pane(_pk("api:p1"))
	var track := office.fleet.state_log().track(agent.key)
	var now := office.lens.now_msec
	_eq(OfficeLens.text_for(agent, null, false, now), "?", "no track: ?")
	_eq(OfficeLens.text_for(agent, track, true, now), "", "a dropped machine: nothing")
	_eq(OfficeLens.text_for(office.frame.pane(_pk("api:p3")), track, false, now), "", "a shell: nothing")
	var wait := StateLog.wait_of(track, now)
	_eq(
		OfficeLens.text_for(agent, track, false, now),
		OfficeAttention.compact_duration(wait.msec / 1000.0, wait.plus),
		"the in-world form"
	)
	_eq(OverviewLine.duration_text(wait.msec, wait.plus), OfficeAttention.wait_text(wait), "FOR says the same")
	var unwatched := StateLog.Wait.new()
	unwatched.msec = 65000
	unwatched.plus = true
	_eq(OfficeAttention.wait_text(unwatched), "1m+", "at least a minute")
	_eq(OfficeAttention.compact_duration(unwatched.msec / 1000.0, unwatched.plus), "1m+", "in the world too")
	unwatched.msec = 3900000
	_eq(OfficeAttention.wait_text(unwatched), "1h 05m+", "the HUD's hours and minutes")
	_eq(OfficeAttention.compact_duration(unwatched.msec / 1000.0, unwatched.plus), "65m+", "the world's minutes")
	await _let_go()
	_done(office)


## Held, each pod's floor is washed in its most urgent pane's state, on the
## FLOORS windows' own scale (HudTheme.SECTION_PANELS through
## OfficeSpaceRow.WINDOW_LOOKS): blocked, then done (UNREAD), working, idle or
## starting (cream), unknown (muted); a table of shells only is slate. The wash
## covers the cells under the pod's drawing and lies first in its background,
## under the shadows, the sign and the title. (It used to lie over a rug; the
## pods stand on the floor itself.)
func test_each_rug_washes_in_its_tables_most_urgent_state_on_the_floors_scale() -> void:
	var scale := {
		&"WindowBlocked": ArtContract.BLOCKED,
		&"WindowDone": ArtContract.UNREAD,
		&"WindowWorking": ArtContract.WORKING,
		&"WindowIdle": ArtContract.CREAM,
		&"WindowUnknown": ArtContract.MUTED,
		&"WindowDark": ArtContract.SLATE,
	}
	for look: StringName in scale:
		_eq(HudTheme.SECTION_PANELS[look], scale[look], "the FLOORS window scale: " + look)
	var office := await _live_office()
	var main := _room_of(office, _pk("api:p1"))
	var tests := _room_of(office, _pk("api:p4"))
	await _hold()
	_eq(_wash_tone(office, main), ArtContract.WORKING, "main: api:p1 works, p2 idles, p3 is a shell")
	_eq(_wash_tone(office, tests), ArtContract.WORKING, "tests: api:p4 works")
	var desk := office.floor_view.desks[main]
	_eq(desk.background.find_children("*", "TileMapLayer", true, false), [], "no rug")
	var grid := float(FloorLayoutPolicy.GRID)
	var visual := desk.placement.measure.render_rect
	var start := (visual.position / grid).floor() * grid
	var end := (visual.end / grid).ceil() * grid
	var cells := Rect2(desk.placement.origin + start, end - start)
	_eq(Rect2(desk.wash.position, desk.wash.size), cells, "the wash covers the cells under the pod's drawing")
	_eq(desk.wash.get_index(), 0, "first, under the shadows, sign and title")
	var steps: Array = [
		[_with(fixture, "api:p2", {"agent_status": "blocked"}), main, ArtContract.BLOCKED, "blocked beats working"],
		[_with(fixture, "api:p4", {"agent_status": "done"}), tests, ArtContract.UNREAD, "done"],
		[_with(fixture, "api:p4", {"agent_status": "idle"}), tests, ArtContract.CREAM, "idle"],
		[_with(fixture, "api:p4", {"agent_status": "unknown"}), tests, ArtContract.MUTED, "unknown"],
		[_with(fixture, "api:p4", {"agent": null}), tests, ArtContract.SLATE, "shells only"],
		[
			_with(
				_with(fixture, "api:p4", {"agent": "pi", "agent_status": "done"}), "api:p4", {"launch_pending": true}
			),
			tests,
			ArtContract.CREAM,
			"starting, as FLOORS lights it"
		],
		[
			_with(_with(fixture, "api:p1", {"agent_status": "done"}), "api:p2", {"agent_status": "blocked"}),
			main,
			ArtContract.BLOCKED,
			"blocked beats done"
		],
	]
	for step: Array in steps:
		var snapshot: Dictionary = step[0]
		_feed(office, snapshot)
		office.settle()
		await _frames(2)
		_eq(_wash_tone(office, str(step[1])), step[2], str(step[3]))
	var working := _with(fixture, "api:p4", {"agent_status": "working"})
	_feed(office, _with(working, "api:p1", {"agent_status": "done"}))
	await _frames(2)
	_eq(_wash_tone(office, main), ArtContract.UNREAD, "done beats working and idle")
	var washed := office.floor_view.desks[main].wash.color
	var expected := office.art.color(ArtContract.UNREAD)
	expected.a = OfficeFloorView.LENS_WASH_ALPHA
	_eq(washed, expected, "the pack's colour at the wash's alpha")
	await _let_go()
	_done(office)


## Held, only the furnishing steps back: the floor, walkways, walls, door,
## windows and framed pictures (the shell), every plant and side table (and
## what it carries), the pantry counter, the zones' partitions and signs, all
## by LENS_DIM. The pods, their laptops, lamps and paper, the people, what
## floats over them, the washes and the tab labels stay as bright as they were.
func test_only_furnishing_dims_while_held() -> void:
	# Wide enough that the top wall hangs framed pictures between its windows.
	var office := await _live_office(_with(fixture, "api:p4", {"agent_status": "done"}), Vector2(1600, 800))
	office.settle()
	await _frames(2)
	var furnishing := _furnishing(office)
	_check(furnishing.size() > 3, "the shell, decor and partitions are there: %d" % furnishing.size())
	_check(not _decor(office).is_empty(), "the floor has plants or side tables")
	# The top-wall run and the lane gaps' pieces are among them: every
	# planned piece is drawn, and every drawn one is in what dims.
	var planned := office.layout_plan().decorations
	var new_pieces := planned.filter(
		func(piece: DecorPlacement) -> bool: return piece.key.begins_with("top/") or "/gap/" in piece.key
	)
	_check(not new_pieces.is_empty(), "the floor stands a top-wall run or a lane gap's pieces")
	_eq(_decor(office).size(), planned.size(), "every planned piece is drawn")
	var dimmed_at: Array[Vector2] = []
	for piece in _decor(office):
		dimmed_at.append(piece.position)
	for piece: DecorPlacement in new_pieces:
		_check(piece.position in dimmed_at, "%s is drawn among what dims" % piece.key)
	# The framed pictures on the top wall hang in the shell, so they dim
	# with it: each is the shell's own child and adds no tint of its own.
	var shell := office.floor_view.ground.get_node_or_null("Shell") as CanvasItem
	var picture := office.art.sprite_texture(office.art.prop_sprite(ArtContract.PROP_WALL_FRAME))
	var frames: Array[Sprite2D] = []
	if shell != null:
		for child in shell.get_children():
			var sprite := child as Sprite2D
			if sprite != null and sprite.texture == picture:
				frames.append(sprite)
	_check(not frames.is_empty(), "the floor hangs framed pictures in its shell")
	await _hold()
	for node in furnishing:
		_eq(node.modulate, OfficeFloorView.LENS_DIM, "furnishing dims: " + str(node.name))
	for frame in frames:
		_check(shell in furnishing, "%s's shell is among what dims" % frame.name)
		_eq(frame.modulate, Color.WHITE, "%s takes the shell's dimming as it is" % frame.name)
		_eq(frame.self_modulate, Color.WHITE, "and brightens nothing of its own: %s" % frame.name)
	for node in _signal_nodes(office):
		_eq(node.modulate, Color.WHITE, "a signal stays bright: " + str(node.name))
	_eq(office.floor_view.root.modulate, Color.WHITE, "the floor itself is not dimmed")
	await _let_go()
	for node in furnishing:
		_eq(node.modulate, Color.WHITE, "let go, back exactly: " + str(node.name))
	_done(office)


## The two plants are furnishing like every piece: each drawn piece is the
## one the plan put at its place, the floor shows both kinds, and nothing about
## herdr moves them. Panes going blocked, done and idle and the focus moving
## keep every piece's key, kind, place and picture; and under the lens both
## kinds dim as every piece does.
func test_both_plants_are_drawn_where_planned_and_ignore_herdr() -> void:
	# Two lanes (a first plan 23 cells wide): the top wall's run and the free
	# lane's gap stand plants; one lane has room for none.
	var office := await _live_office(fixture, Vector2(880, 480))
	office.settle()
	await _frames(2)
	var planned: Dictionary[Vector2, StringName] = {}
	var keys: Dictionary[String, StringName] = {}
	for placed: DecorPlacement in office.layout_plan().decorations:
		planned[placed.position] = placed.piece
		keys[placed.key] = placed.piece
	var drawn := _drawn_pieces(office)
	_eq(drawn.size(), planned.size(), "every planned piece is drawn")
	var kinds: Dictionary[StringName, Texture2D] = {}
	for at: Vector2 in drawn:
		var piece: OfficeDecor = drawn[at]
		_eq(piece.piece, planned.get(at, &""), "the piece drawn at %s is the planned one" % at)
		if piece.piece != ArtContract.PROP_SIDE_TABLE:
			_check(piece.piece in [&"plant", &"plant_b"], "a plant is one of the two: %s" % piece.piece)
			kinds[piece.piece] = (piece.get_node("Body") as Sprite2D).texture
	_eq(kinds.size(), 2, "the floor shows both plants: %s" % [kinds.keys()])
	if kinds.size() == 2:
		_check(kinds[&"plant"] != kinds[&"plant_b"], "each with its own picture")
	var pictures: Dictionary[Vector2, Texture2D] = {}
	for at: Vector2 in drawn:
		pictures[at] = ((drawn[at] as OfficeDecor).get_node("Body") as Sprite2D).texture
	var changed := _with(fixture, "api:p1", {"agent_status": "blocked"})
	changed = _with(changed, "api:p2", {"agent_status": "done"})
	changed = _with(changed, "api:p4", {"agent_status": "idle"})
	changed.focused_pane_id = "api:p4"
	changed.focused_tab_id = "api:t2"
	for snapshot: Dictionary in [changed, fixture]:
		_feed(office, snapshot)
		await _frames(2)
		office.settle()
		await _frames(2)
		var again: Dictionary[String, StringName] = {}
		for placed: DecorPlacement in office.layout_plan().decorations:
			again[placed.key] = placed.piece
		_eq(again, keys, "the plan's keys and kinds do not follow herdr")
		var now := _drawn_pieces(office)
		_eq(now.keys(), drawn.keys(), "every piece stands where it stood")
		for at: Vector2 in now:
			var piece: OfficeDecor = now[at]
			_eq(piece.piece, planned[at], "the same kind at %s" % at)
			_eq((piece.get_node("Body") as Sprite2D).texture, pictures[at], "the same picture at %s" % at)
	await _hold()
	for at: Vector2 in drawn:
		_eq((drawn[at] as OfficeDecor).modulate, OfficeFloorView.LENS_DIM, "%s dims under the lens" % planned[at])
	await _let_go()
	_done(office)


## The drawn standing pieces (plants and cabinets) by where they stand.
func _drawn_pieces(office: OfficeDouble) -> Dictionary[Vector2, OfficeDecor]:
	var found: Dictionary[Vector2, OfficeDecor] = {}
	for piece in _decor(office):
		found[piece.position] = piece
	return found


## The picked table's frame is drawn in the blocked colour, the very colour of
## a blocked table's wash: under the lens it darkens (OfficeTable.LENS_FRAME)
## so the pick still reads, and let go it is exactly as before.
func test_the_picked_tables_frame_darkens_on_its_wash() -> void:
	var office := await _live_office(_with(fixture, "api:p1", {"agent_status": "blocked"}))
	office.settle()
	await _frames(2)
	var key := _pk("api:p1")
	await _click_desk(office, key)
	await _frames(2)
	_eq(office.picked_key, key, "a click picks the blocked desk")
	var frame: Node2D = null
	for table in office.floor_view.tables:
		var bars: Node2D = table.get_node("Overlay/Frame")
		if bars.visible:
			frame = bars
	_check(frame != null, "its table shows the selection frame")
	if frame == null:
		_done(office)
		return
	_eq(frame.modulate, Color.WHITE, "unlensed, the frame is as it always was")
	await _hold()
	_eq(frame.modulate, OfficeTable.LENS_FRAME, "held, it darkens on the blocked wash")
	await _let_go()
	_eq(frame.modulate, Color.WHITE, "let go, back exactly")
	_done(office)


## The lens never turns on under the OVERVIEW, the terminal monitor or while
## a text field has the keyboard (`L` is typing there). A press that began in
## the list's filter stays spoiled after a click elsewhere takes the focus: the
## lens waits for `L` to be let go and pressed again.
func test_no_lens_under_the_overview_the_monitor_or_a_text_field() -> void:
	var office := await _live_office()
	await _office_key(office, KEY_O)
	_check(office.hud.overview_open(), "O opens the overview")
	await _hold()
	_check(not office.lens.held, "no lens under the overview")
	await _let_go()
	await _office_key(office, KEY_O)
	_check(not office.hud.overview_open(), "O closes it")
	await _office_key(office, KEY_M)
	_check(office.hud.monitor_open(), "M opens the monitor")
	await _hold()
	_check(not office.lens.held, "no lens under the monitor")
	for station in _seats(office):
		_check(not _lens(station).visible, "and no line: " + station.pane_key)
	await _let_go()
	var close: Control = office.hud.monitor.get_node("%CloseButton")
	await _press(close)
	await _frames(2)
	_check(not office.hud.monitor_open(), "its close button closes the monitor")
	var strip: Control = office.hud.get_node("%DrawerTab")
	await _press(strip)
	await _frames(2)
	var filter: LineEdit = office.hud.agent_list.get_node("%Filter")
	await _press(filter)
	_check(filter.has_focus(), "a click puts the keyboard in the filter")
	await _hold()
	_check(not office.lens.held, "L in the filter is typing, not the lens")
	var collapse: Control = office.hud.get_node("%Collapse")
	await _press(collapse)
	await _frames(2)
	_check(not filter.has_focus(), "a click elsewhere takes the keyboard from the filter")
	_check(not office.lens.held, "the press that began in the filter stays spoiled")
	await _let_go()
	await _hold()
	_check(office.lens.held, "a fresh press is the lens")
	await _let_go()
	_done(office)


## A dropped machine's floor keeps its last picture, dimmed: the lens says no
## wait anywhere on it (nobody is receiving those clocks, invariant 4) and
## washes every rug slate, as FLOORS draws its windows dark.
func test_a_stale_floor_says_no_wait_and_washes_slate() -> void:
	var office := await _live_office(_with(fixture, "api:p1", {"agent_status": "blocked"}))
	_set_online(office, false)
	await _frames(2)
	_check(office.fleet.is_stale(LOCAL), "Local dropped")
	await _hold()
	_check(office.lens.held, "the lens is held over a dropped floor too")
	for station in _seats(office):
		_check(not _lens(station).visible, "no wait on a dropped floor: " + station.pane_key)
		if not station.away():
			_check(_plate(station).visible, "its plate is still there: " + station.pane_key)
	for tab: String in office.floor_view.desks:
		_eq(_wash_tone(office, tab), ArtContract.SLATE, "every rug slate: " + tab)
	await _let_go()
	_done(office)


## Zooming while `L` is held rebuilds none of it: the same lines, washes,
## pointer and world, still shown.
func test_zooming_while_held_rebuilds_nothing() -> void:
	var office := await _live_office()
	await _hold()
	var ids := _lens_ids(office)
	var texts := _lens_texts(office)
	var zoom := office.zoom
	await _office_key(office, KEY_EQUAL)
	await _frames(2)
	_eq(office.zoom, zoom + OfficeScene.ZOOM_STEP, "= zoomed in")
	_check(office.lens.held, "the lens is still held")
	_eq(_lens_ids(office), ids, "not one node rebuilt")
	_eq(_lens_texts(office).keys(), texts.keys(), "the same lines")
	for station in _seats(office):
		if not str(texts.get(station.pane_key, "")).is_empty():
			_check(_lens(station).visible, "still shown: " + station.pane_key)
	await _let_go()
	_done(office)


## The lines move on the top bar's beat (OfficeAttention.TEXT_INTERVAL) while
## `L` is held, and nothing at all is counted while it is not.
func test_the_lens_ticks_with_the_top_bar_and_not_at_all_released() -> void:
	var office := await _live_office()
	_eq(OfficeLens.TICK, OfficeAttention.TEXT_INTERVAL, "the top bar's beat")
	var released := office.lens.updates
	await _wait_seconds(1.0)
	_eq(office.lens.updates, released, "released: not one update in a second")
	await _hold()
	var from := office.lens.updates
	await _wait_seconds(1.0)
	var ticks := office.lens.updates - from
	_check(ticks >= 3 and ticks <= 5, "held: about four updates a second, %d" % ticks)
	await _let_go()
	var after := office.lens.updates
	await _wait_seconds(0.6)
	_eq(office.lens.updates, after, "let go: none again")
	_done(office)


## An idle agent rests in the pantry: the line hangs over them there, centred
## on them and above their badge, not at the empty seat.
func test_a_pantry_worker_gets_the_line_over_them() -> void:
	var office := await _live_office()
	office.settle()
	await _frames(2)
	var station := _station(office, _pk("api:p2"))
	_eq(station.rest, OfficeRests.Rest.PANTRY, "api:p2 idles in the pantry")
	await _hold()
	var line := _lens(station)
	_check(line.visible, "the pantry worker has a line")
	_check(not line.text.is_empty(), "saying how long: " + line.text)
	var drawn := _line_text(line)
	var worker := station.global_position + station.away_at
	_eq(drawn.get_center().x, worker.x, "centred over them")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	var mark := badge.global_transform * badge.get_rect()
	_check(drawn.end.y <= mark.position.y, "above their badge: %s over %s" % [drawn, mark])
	_check(absf(drawn.get_center().x - station.global_position.x) > 1.0, "not at the empty seat")
	await _let_go()
	_done(office)


# --- the hover mark -----------------------------------------------------------


## Hovering a NEWS item about a pane on the shown floor frames its desk with
## the pointer, and nothing else: no selection, no pan, the same floor. The
## pointer leaves with the mouse; a click still picks.
func test_hovering_a_news_item_points_at_its_desk_without_selecting() -> void:
	var office := await _live_office()
	var key := _pk("api:p4")
	_feed(office, _with(fixture, "api:p4", {"agent_status": "done"}))
	office.settle()
	await _frames(2)
	var item := office.hud.news.item(0)
	_check(item.visible and not item.disabled, "the newest entry is about api:p4")
	var active := office.navigator.active_key
	var shown := office.navigator.shown_key
	var pan := office.camera.pan
	var marks := _marks(office)
	var world := office.world.get_instance_id()
	var pointer := office.floor_view.pointer
	_check(not pointer.visible, "nothing pointed at yet")
	await _hover(item.get_global_rect().get_center())
	_check(pointer.visible, "hovering the item points")
	_eq(pointer.key, key, "at api:p4")
	var seat := office.floor_view.seats[key].node
	var target := _in_floor(office, seat.target_rect())
	_check(pointer.rect.encloses(target), "around its click area: %s holds %s" % [pointer.rect, target])
	_eq(office.navigator.active_key, active, "nothing selected")
	_eq(office.picked_key, "", "nothing picked")
	_eq(office.navigator.shown_key, shown, "the same map")
	_eq(office.camera.pan, pan, "no pan")
	_eq(_marks(office), marks, "no selection mark moved")
	_eq(office.world.get_instance_id(), world, "nothing rebuilt")
	await _hover(office.hud.world_rect().get_center())
	_check(not pointer.visible, "leaving the item takes the mark away")
	await _press(item)
	await _frames(2)
	_eq(office.picked_key, key, "a click still picks it")
	_done(office)


## A list row for a pane on another machine outlines its zone's SPACES row (a
## 1-unit paper edge, SpaceRowPointed) and draws nothing in the world; the rows
## marked as in view keep their marks, and leaving puts the row back. A row for
## a pane in another zone of the shown map points at its desk, as for any desk
## of the map.
func test_hovering_a_row_for_another_floor_marks_its_floors_row() -> void:
	var office := await _two_machine_office()
	var key := HerdrFleet.pane_key(BEE, "hive:p1")
	var strip: Control = office.hud.get_node("%DrawerTab")
	await _press(strip)
	await _frames(3)
	var row := office.hud.agent_list.row_for(key)
	_check(row != null and row.is_visible_in_tree(), "hive:p1 has a row in the open list")
	if row == null:
		_done(office)
		return
	var hive := office.frame.zone_of(key)
	_check(office.frame.find_zone(hive).building.key != office.navigator.shown_key, "hive is on another machine")
	var floor_row := office.hud.spaces.row_for(hive)
	var in_view := Array(office.hud.spaces.in_view())
	_check(not in_view.is_empty() and not in_view.has(hive), "Local's zones in view are marked, hive is not")
	_eq(floor_row.theme_type_variation, &"SpaceRow", "hive's row as usual")
	await _hover(row.get_global_rect().get_center())
	_eq(floor_row.theme_type_variation, &"SpaceRowPointed", "hive's SPACES row is outlined")
	_eq(Array(office.hud.spaces.in_view()), in_view, "the rows in view keep their marks")
	_check(not office.floor_view.pointer.visible, "nothing is pointed at in the world")
	_eq(office.navigator.shown_key, LOCAL, "no map change")
	await _hover(office.hud.world_rect().position + Vector2(4, 4))
	_eq(floor_row.theme_type_variation, &"SpaceRow", "leaving restores it")
	var web := office.hud.agent_list.row_for(_pk("web:p1"))
	var web_row := office.hud.spaces.row_for(office.frame.zone_of(_pk("web:p1")))
	await _hover(web.get_global_rect().get_center())
	_check(office.floor_view.pointer.visible, "a row for web:p1, another zone of this map: its desk is pointed at")
	_eq(office.floor_view.pointer.key, _pk("web:p1"), "that desk")
	_eq(web_row.theme_type_variation, &"SpaceRow", "and web's SPACES row is not outlined")
	_done(office)


## An EVENTS row points like a NEWS item, and an edge arrow outlines its
## zone's SPACES row.
func test_events_rows_and_signposts_point_too() -> void:
	var office := await _live_office()
	await _frames(2)
	var arrows := office.hud.edge_arrows.shown()
	_check(not arrows.is_empty(), "web and infra wait off screen: edge arrows")
	if not arrows.is_empty():
		var arrow := arrows[0]
		var floor_row := office.hud.spaces.row_for(arrow.zone_key())
		await _hover(arrow.get_global_rect().get_center())
		_eq(floor_row.theme_type_variation, &"SpaceRowPointed", "the arrow outlines its zone's row")
		_check(not office.floor_view.pointer.visible, "and nothing in the world")
		await _hover(office.hud.world_rect().get_center())
		_eq(floor_row.theme_type_variation, &"SpaceRow", "leaving restores it")
	var key := _pk("api:p4")
	_feed(office, _with(fixture, "api:p4", {"agent_status": "done"}))
	await _press_tab(office, OfficeHud.DrawerTab.EVENTS)
	var events := office.fleet.state_log().events()
	var row := office.hud.event_list.row_for(events[events.size() - 1].id)
	_check(row != null and row.pane_key == key, "the newest EVENTS row is about api:p4")
	if row != null:
		await _hover(row.get_global_rect().get_center())
		_check(office.floor_view.pointer.visible, "the row points at the desk")
		_eq(office.floor_view.pointer.key, key, "api:p4's")
		await _hover(office.hud.world_rect().position + Vector2(4, 4))
		_check(not office.floor_view.pointer.visible, "and stops when left")
	_done(office)


## The pointer is a channel of its own: one node on the floor, drawn (not a
## pack sprite), over the world like the labels, and a zoom keeps it as it is.
func test_the_pointer_is_its_own_channel() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p4", {"agent_status": "done"}))
	await _frames(2)
	var pointers := 0
	for node in office.world.find_children("*", "", true, false):
		if node is OfficePointer:
			pointers += 1
	_eq(pointers, 1, "one pointer on the floor")
	var pointer := office.floor_view.pointer
	var drawn: Node = pointer
	_check(drawn is not Sprite2D, "drawn, not a sprite")
	_eq(pointer.get_child_count(), 0, "with nothing inside it")
	_eq(pointer.z_index, OfficeWorld.OVERLAY_Z, "over the world, like the labels")
	_eq(pointer.get_parent(), office.floor_view.root, "on the floor")
	_eq(pointer.get_index(), office.floor_view.root.get_child_count() - 1, "its last child")
	await _hover(office.hud.news.item(0).get_global_rect().get_center())
	_check(pointer.visible, "pointing")
	var rect := pointer.rect
	var id := pointer.get_instance_id()
	await _office_key(office, KEY_EQUAL)
	await _frames(2)
	_eq(office.floor_view.pointer.get_instance_id(), id, "a zoom keeps the node")
	_check(pointer.visible, "and it still points")
	_eq(pointer.rect, rect, "at the same place on the floor")
	_done(office)


## A pane pointed at that goes takes the mark with it, and a disabled item for
## it (pane gone) points at nothing.
func test_a_pointed_pane_that_goes_drops_the_mark() -> void:
	var office := await _live_office()
	var done := _with(fixture, "api:p4", {"agent_status": "done"})
	_feed(office, done)
	await _frames(2)
	var item := office.hud.news.item(0)
	await _hover(item.get_global_rect().get_center())
	_check(office.floor_view.pointer.visible, "api:p4 pointed at")
	_feed(office, _without(done, "api:p4"))
	_feed(office, _without(done, "api:p4"))
	await _frames(2)
	_check(not office.floor_view.pointer.visible, "the pane went, and the mark with it")
	for key: Variant in office.hud.spaces.row_keys():
		var row := office.hud.spaces.row_for(str(key))
		_check(row.theme_type_variation != &"SpaceRowPointed", "no SPACES row outlined: " + str(key))
	await _hover(office.hud.world_rect().get_center())
	for index in OfficeNews.ITEMS:
		var gone := office.hud.news.item(index)
		if gone.visible and gone.disabled:
			await _hover(gone.get_global_rect().get_center())
			_check(not office.floor_view.pointer.visible, "a gone pane's item points at nothing")
			break
	_done(office)


# --- helpers ------------------------------------------------------------------


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _l_key(down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_L
	event.pressed = down
	return event


## `L` down (or up) through the window's input, then the frames the lens needs
## to see it.
func _hold() -> void:
	await _parsed(_l_key(true))
	await _frames(2)


func _let_go() -> void:
	await _parsed(_l_key(false))
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


## A real click on the drawer's tab for `tab`, the drawer opened first.
func _press_tab(office: OfficeDouble, tab: OfficeHud.DrawerTab) -> void:
	if not office.hud.drawer_open():
		var strip: Control = office.hud.get_node("%DrawerTab")
		await _press(strip)
		await _frames(2)
	var tabs := office.hud.drawer_tabs
	var rect := tabs.get_tab_rect(tab)
	var at := tabs.get_global_rect().position + rect.get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	await _frames(2)


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _part(bubble: OfficeBubble, part: String) -> CanvasItem:
	return bubble.get_node(part)


## Where `line`'s text is drawn, in global coordinates: centred, from the
## label's top to its font's baseline (the lens says digits, `s m h`, `+` and
## `?`, none of them below it), as the geometry suite measures a plate.
func _line_text(line: Label) -> Rect2:
	var font := line.get_theme_font("font")
	var pixels := line.get_theme_font_size("font_size")
	var width := font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var top_left := line.global_position + Vector2((line.size.x - width) / 2.0, 0)
	return Rect2(top_left, Vector2(width, font.get_ascent(pixels)))


func _lens(station: OfficeStation) -> Label:
	return station.get_node("Overlay/Lens")


## Pane key -> what its lens line says, `""` while hidden, for every seat.
func _lens_texts(office: OfficeDouble) -> Dictionary:
	var texts := {}
	for station in _seats(office):
		var line := _lens(station)
		texts[station.pane_key] = line.text if line.visible else ""
	return texts


## Everything the lens shows, by instance id: each line, each wash, the pointer.
func _lens_ids(office: OfficeDouble) -> Array:
	var ids: Array = [office.world.get_instance_id(), office.floor_view.pointer.get_instance_id()]
	for station in _seats(office):
		ids.append(_lens(station).get_instance_id())
	var tabs := office.floor_view.desks.keys()
	tabs.sort()
	for tab: String in tabs:
		ids.append(office.floor_view.desks[tab].wash.get_instance_id())
	return ids


## What each seat signals besides the lens: its plate's words and its badge.
## (Whether the plate shows is the lens's too: held, every seat's does.)
func _signals(office: OfficeDouble) -> Dictionary:
	var shown := {}
	for station in _seats(office):
		var plate := _plate(station)
		var badge: Sprite2D = station.get_node("Overlay/Badge")
		shown[station.pane_key] = [plate.text, badge.visible, badge.texture]
	return shown


## Pane key -> whether its selection mark shows.
func _marks(office: OfficeDouble) -> Dictionary:
	var shown := {}
	for station in _seats(office):
		shown[station.pane_key] = _sprite(station, "Overlay/Selection").visible
	return shown


## The furnishing the lens dims: the shell, the decor and the counters.
func _furnishing(office: OfficeDouble) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	var shell := office.floor_view.ground.get_node_or_null("Shell") as CanvasItem
	if shell != null:
		found.append(shell)
	for decor in _decor(office):
		found.append(decor)
	for fixture_node in _fixtures(office):
		found.append(fixture_node)
	for node: Node in office.floor_view.sorted.get_children():
		if node is OfficeZoneSign or node.name.begins_with("Partitions_"):
			found.append(node as CanvasItem)
	return found


## What the lens leaves as bright as it was: pods and everything on them, the
## seats, the people, the backgrounds (washes, shadows, tab labels) and the
## pointer.
func _signal_nodes(office: OfficeDouble) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = [office.floor_view.pointer]
	for table in office.floor_view.tables:
		found.append(table)
		for child in table.get_children():
			if child is CanvasItem:
				found.append(child as CanvasItem)
	for station in _seats(office):
		found.append(station)
		for child in station.find_children("*", "CanvasItem", true, false):
			found.append(child as CanvasItem)
	for tab: String in office.floor_view.desks:
		var desk := office.floor_view.desks[tab]
		found.append(desk.background)
		for child in desk.background.get_children():
			if child is CanvasItem:
				found.append(child as CanvasItem)
	return found


## The tab key of the room pane `key` sits in on the shown map.
func _room_of(office: OfficeDouble, key: String) -> String:
	var found := office.frame.map_of(office.navigator.shown_key)
	for room in found.rooms:
		for pane in room.panes:
			if pane.key == key:
				return room.key
	_fail("no room holds " + key)
	return ""


## The palette key the wash over `tab`'s rug is drawn in while shown; empty
## while hidden or in a colour of no tone.
func _wash_tone(office: OfficeDouble, tab: String) -> StringName:
	var desk: OfficeDeskView = office.floor_view.desks.get(tab)
	if desk == null or not desk.wash.visible:
		return &""
	for tone: StringName in HudTheme.SECTION_PANELS.values():
		var wanted := office.art.color(tone)
		wanted.a = OfficeFloorView.LENS_WASH_ALPHA
		if desk.wash.color.is_equal_approx(wanted):
			return tone
	return &""


## A global rectangle in the floor root's coordinates, where the pointer draws.
func _in_floor(office: OfficeDouble, rect: Rect2) -> Rect2:
	return office.floor_view.root.get_global_transform().affine_inverse() * rect


## The bubble over pane `key` on screen, its middle, once revealed.
func _bubble_at(office: OfficeDouble, key: String) -> Vector2:
	office.reveal(key)
	await _frames(2)
	return _station(office, key).bubble_rect().get_center() - office.camera.position


## `snapshot` without pane `pane_id`, in its panes, agents and layouts.
func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result
