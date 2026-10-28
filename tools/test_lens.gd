extends "res://tools/office_test_base.gd"
## The info lens and the hover mark.
## Holding `L` adds one time line per agent (the OVERVIEW's FOR, from
## StateLog.wait_of(), in the in-world compact form), shows every seat's name
## plate, hides the blocked chip's parts, washes every pod's floor in its most
## urgent state on the FLOORS windows' scale and dims the furnishing; letting
## go puts everything back. Hovering a NEWS item, an EVENTS or HISTORY row or
## an edge arrow points at the desk it names (a dashed frame of its own) or, on
## another machine or for an arrow, at that zone's blocked cards, and never
## selects, pans, reads or writes. Keys and the pointer go through real input.
## Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_lens.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the NEWS / EVENTS suite does.

const BUBBLE_PARTS: Array[String] = ["%Frame", "%Wait"]
## The HUD on its own, for the cases about the edge arrows' pointing.
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")


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
	# S3 SEATTAGS round 2: a map one seat over FloorLayoutPolicy.FEW_SEATS (the floors
	# fixture's 13 seats show every plate at rest now), padded with shells, so before L
	# only the selected seat's plate shows and the fixture's ten agents are the agents.
	var crowded := _sized(fixture, FloorLayoutPolicy.FEW_SEATS + 1, "api:p3")
	var office := await _live_office(crowded)
	var one := _with(crowded, "api:p1", {"agent_status": "blocked"})
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
	# D2 (2026-10-27): idle sits with a mug; the pantry is a nook nobody walks to:
	# every plate shows at its desk under the lens, api:p2's (idle) too.
	for station in _seats(office):
		_check(_plate(station).visible, "held, the plate shows at the desk: " + station.pane_key)
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
## chip (its click and hover rectangle, and the question reader's
## `visible`), but nothing of it is drawn, and no question tooltip comes up
## over it. An agent blocked in the first snapshot began before this office
## watched: the chip has no wait to tell, but its line says `Ns+`.
func test_the_lens_hides_the_bubble_parts_but_not_the_blocked_seat() -> void:
	var first := _with(fixture, "api:p1", {"agent_status": "blocked"})
	var office := await _live_office(first)
	# api:p4 is seen going blocked, so its chip has a wait to draw.
	_feed(office, _with(first, "api:p4", {"agent_status": "blocked"}))
	var key := _pk("api:p4")
	office.settle()
	await _text_tick()
	var station := _station(office, key)
	var bubble := station.chip()
	for part in BUBBLE_PARTS:
		_check(_part(bubble, part).is_visible_in_tree(), "without the lens the bubble draws " + part)
	var at := await _bubble_at(office, key)
	await _hover(at)
	_check(office.hud.world_tip_shown(), "without the lens its tooltip comes up")
	await _hold()
	_check(not office.hud.world_tip_shown(), "the lens takes the tooltip down")
	_check(bubble.visible, "the seat is still a blocked one")
	_check(station.chip_rect().has_area(), "and its bubble rectangle is where it was")
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
	_check(not office.hud.world_tip_shown(), "no tooltip over the bubble while L is held")
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
## StrategicModel.WINDOW_LOOKS): blocked, then done (UNREAD), working, idle or
## starting (cream), unknown (muted); a table of shells only is slate. The wash
## covers the cells under the pod's drawing and its title and lies first in its
## background, under the shadows, the sign and the title. (It used to lie over a rug; the
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
	# The pod's drawing and the tab's name right under it: the near row sits at
	# the desk, so the drawing ends on a cell's edge (y 32) and the name is the
	# next cell's.
	var visual := desk.placement.measure.render_rect.grow_side(SIDE_BOTTOM, OfficeDraw.TAB_LABEL_HEIGHT)
	var start := (visual.position / grid).floor() * grid
	var end := (visual.end / grid).ceil() * grid
	var cells := Rect2(desk.placement.origin + start, end - start)
	_eq(Rect2(desk.wash.position, desk.wash.size), cells, "the wash covers the cells under the pod's drawing and title")
	_eq(cells.size.y, 160.0, "five cell rows: the far tags' row down to the near approach row")
	var title_box := Rect2(desk.title.position, desk.title.size)
	_check(cells.encloses(title_box), "the tab's name %s is on the wash %s" % [title_box, cells])
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
	# Six lanes (a first plan 33 cells wide): the top wall's run and the free
	# lanes' gap stand plants. Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new
	# zone takes lanes until it stands one row; the map replans: at 880 (four
	# lanes, 23 cells) the zones stand two even rows and leave no lane gap.
	var office := await _live_office(fixture, Vector2(1280, 720))
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


## The lens never turns on under the OVERVIEW or the terminal monitor. A press
## that began under the monitor stays spoiled after a click closes it: the
## lens waits for `L` to be let go and pressed again.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the list's filter, the text field this case
## held `L` in, is gone, and a read-only office has no text field; "L in a text field is typing, not the lens" is
## pinned by SPACES' test_the_branch_box_lets_the_page_keys_through_and_lets_go_outside, and the spoiled press is
## kept here with the monitor's gate (was test_no_lens_under_the_overview_the_monitor_or_a_text_field).
func test_no_lens_under_the_overview_or_the_monitor_and_a_spoiled_press_waits() -> void:
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
	await _office_key(office, KEY_M)
	_check(office.hud.monitor_open(), "M opens the monitor again")
	await _hold()
	_check(not office.lens.held, "L under the monitor is not the lens")
	await _press(close)
	await _frames(2)
	_check(not office.hud.monitor_open(), "a click on its close button closes it, L still down")
	_check(not office.lens.held, "the press that began under the monitor stays spoiled")
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


## An idle agent sits at their seat: the line is on that seat's lens row,
## centred on the seat's column and above its badge, as anyone's. D2
## (2026-10-27): idle sits with a mug; the pantry is a nook nobody walks to (the
## line hung over them in the pantry, away from the empty seat).
func test_an_idle_worker_gets_the_line_at_the_seat() -> void:
	var office := await _live_office()
	office.settle()
	await _frames(2)
	var station := _station(office, _pk("api:p2"))
	_eq(office.frame.pane(_pk("api:p2")).state, "idle", "api:p2 idles")
	_eq(station.actor().position, Vector2.ZERO, "at its seat")
	await _hold()
	var line := _lens(station)
	_check(line.visible, "the idle worker has a line")
	_check(not line.text.is_empty(), "saying how long: " + line.text)
	# S3 item 7 (2026-10-27): the line's paper tag hugs its text (CARPET-B1): centred in the seat's lens row.
	var lens_at: Vector2 = OfficeStation.LENS_AT[station.side]
	var row := Rect2(lens_at, OfficeStation.LENS_SIZE)
	var tag := Rect2(line.position, line.size)
	_check(row.encloses(tag), "on the seat's lens row: %s in %s" % [tag, row])
	_eq([tag.position.y, tag.get_center().x], [row.position.y, row.get_center().x], "centred in it")
	var drawn := _line_text(line)
	_check(absf(drawn.get_center().x - station.global_position.x) <= 1.0, "centred on the seat's column")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	var mark := badge.global_transform * badge.get_rect()
	if station.side == "far":
		_check(drawn.end.y <= mark.position.y, "above its badge: %s over %s" % [drawn, mark])
	else:
		_check(drawn.position.y >= mark.end.y, "below its badge: %s under %s" % [drawn, mark])
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


## An EVENTS row for a pane on another machine outlines that pane's card in
## the top bar (a 1-unit ring, PortraitPointed or PortraitPointedTile) and draws nothing in the
## world; leaving puts the card back. A row for a pane in another zone of the
## shown map points at its desk, as for any desk of the map. (S3 BAR-b,
## 2026-10-27: it outlined the zone's SPACES row, whose in-view marks are gone.)
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the rows were the agent list's; they are the
## EVENTS page's now, which point the same way (was test_hovering_a_row_for_another_machine_outlines_its_card).
func test_hovering_an_events_row_for_another_machine_outlines_its_card() -> void:
	var office := await _two_machine_office()
	var key := HerdrFleet.pane_key(BEE, "hive:p1")
	await _fresh_waits(office)
	var row := _event_row(office, key)
	_check(row != null and row.is_visible_in_tree(), "hive:p1 has a row on the EVENTS page")
	if row == null:
		_done(office)
		return
	var hive := office.frame.zone_of(key)
	_check(office.frame.find_zone(hive).building.key != office.navigator.shown_key, "hive is on another machine")
	var card := office.hud.bar.card_for(key)
	_check(card != null, "hive:p1 has a card in the bar")
	var ring: Control = card.get_node("%Pointed")
	_eq(_outlined(office), [], "no card outlined")
	await _hover(row.get_global_rect().get_center())
	_eq(_outlined(office), [key], "hive:p1's card is outlined, alone")
	_check(ring.visible, "by its ring")
	_check(not office.floor_view.pointer.visible, "nothing is pointed at in the world")
	_eq(office.navigator.shown_key, LOCAL, "no map change")
	await _hover(office.hud.world_rect().position + Vector2(4, 4))
	_eq(_outlined(office), [], "leaving restores it")
	var web := _event_row(office, _pk("web:p1"))
	_check(web != null and web.is_visible_in_tree(), "web:p1 has a row on the EVENTS page")
	if web == null:
		_done(office)
		return
	await _hover(web.get_global_rect().get_center())
	_check(office.floor_view.pointer.visible, "a row for web:p1, another zone of this map: its desk is pointed at")
	_eq(office.floor_view.pointer.key, _pk("web:p1"), "that desk")
	_eq(_outlined(office), [], "and no card is outlined")
	_done(office)


## An EVENTS row points like a NEWS item, and an edge arrow outlines its
## zone's blocked cards (S3 BAR-b, 2026-10-27: its zone's SPACES row).
func test_events_rows_and_signposts_point_too() -> void:
	var office := await _live_office()
	await _frames(2)
	var arrows := office.hud.edge_arrows.shown()
	_check(not arrows.is_empty(), "web and infra wait off screen: edge arrows")
	if not arrows.is_empty():
		var arrow := arrows[0]
		var cards := _blocked_cards_of(office, arrow.zone_key())
		_check(not cards.is_empty(), "the arrow's zone has a blocked card")
		await _hover(arrow.get_global_rect().get_center())
		_eq(_outlined(office), cards, "the arrow outlines its zone's blocked cards")
		_check(not office.floor_view.pointer.visible, "and nothing in the world")
		await _hover(office.hud.world_rect().get_center())
		_eq(_outlined(office), [], "leaving restores them")
	var key := _pk("api:p4")
	_feed(office, _with(fixture, "api:p4", {"agent_status": "done"}))
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
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
	_eq(_outlined(office), [], "no card outlined")
	await _hover(office.hud.world_rect().get_center())
	for index in OfficeNews.ITEMS:
		var gone := office.hud.news.item(index)
		if gone.visible and gone.disabled:
			await _hover(gone.get_global_rect().get_center())
			_check(not office.floor_view.pointer.visible, "a gone pane's item points at nothing")
			break
	_done(office)


## A HUD's card that says it is in answer mode: OfficeHud.fit() then floats the
## bottom panel over the world, as the office's does.
class AnsweringInspector:
	extends OfficePaneInspector

	func answering() -> bool:
		return true


## An edge arrow under the staff panel is not pointed at. In answer mode the
## panel floats over the world, here over the bottom edge's arrow, and the
## pointer rests on the panel where it covers that arrow: no zone is said when
## the pointer comes there, and none when a refresh hands the arrow under it
## another zone (the arrows are arranged again, the pointer has not moved). At
## the 480x320 minimum and at 800x480.
func test_an_arrow_under_the_answer_panel_is_not_pointed_at() -> void:
	# The case before's office is gone before the window changes size.
	await _frames(2)
	for screen: Vector2 in [Vector2(480, 320), Vector2(800, 480)]:
		var size := "%dx%d" % [screen.x, screen.y]
		root.size = Vector2i(screen)
		await _hover(Vector2(4, 4))
		var art := ArtPack.from_manifest(MANIFESTS[0])
		var hud: OfficeHud = HUD_SCENE.instantiate()
		# S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the
		# card is the
		# bottom panel's AGENT page; the panel is what floats.
		var staff: Control = hud.get_node("%Staff")
		staff.get_node("%Card").set_script(AnsweringInspector)
		root.add_child(hud)
		hud.dress(art, OfficeDraw.new(art).font)
		hud.fit(screen)
		await _frames(3)
		hud.show_edge_arrows([_arrow_below("z0")] as Array[EdgeArrowModel])
		await _frames(3)
		_check(
			hud.inspector.answering() and hud.edge_arrows.is_visible_in_tree(), size + ": answer mode, an arrow shown"
		)
		var arrow := hud.edge_arrows.shown()[0]
		var at := arrow.get_global_rect().get_center()
		_check(staff.get_global_rect().has_point(at), size + ": the floating panel covers the arrow's middle")
		var said: Array[String] = []
		hud.zone_pointed.connect(func(key: String) -> void: said.append(key))
		await _hover(at)
		var over := root.gui_get_hovered_control()
		_check(over == staff or staff.is_ancestor_of(over), size + ": the pointer is on the panel: %s" % over)
		_eq(said, [] as Array[String], size + ": coming onto the panel over the arrow points at no zone")
		hud.show_edge_arrows([_arrow_below("z1")] as Array[EdgeArrowModel])
		await _frames(3)
		_eq(hud.edge_arrows.shown()[0].zone_key(), "z1", size + ": the arrow was handed another zone")
		_check(
			hud.edge_arrows.shown()[0].get_global_rect().has_point(at), size + ": still under the pointer and the panel"
		)
		_eq(said, [] as Array[String], size + ": and no zone is pointed at through the panel")
		hud.free()
		await _frames(2)
	root.size = SCREEN


## The zone under a resting pointer is said once. Two arrows change places in
## the pool without moving on screen: nothing is said (the same zone is still
## under the pointer); and when the pointer then moves a pixel within that
## arrow, the viewport's exit from the node that was hovered and its enter of
## the node that stands there now say nothing again.
func test_arrows_changing_pool_places_say_the_zone_under_the_pointer_once() -> void:
	await _frames(2)
	await _hover(Vector2(4, 4))
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var hud: OfficeHud = HUD_SCENE.instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(Vector2(SCREEN))
	var below := _arrow_below("z0")
	var above := _arrow_below("z1")
	above.edge = EdgeArrowModel.Edge.TOP
	hud.show_edge_arrows([below, above] as Array[EdgeArrowModel])
	await _frames(2)
	var at := hud.edge_arrows.shown()[0].get_global_rect().get_center()
	var said: Array[String] = []
	hud.zone_pointed.connect(func(key: String) -> void: said.append(key))
	await _hover(at)
	_eq(said, ["z0"] as Array[String], "the pointer on the bottom arrow points at its zone")
	hud.show_edge_arrows([above, below] as Array[EdgeArrowModel])
	await _frames(2)
	var shown := hud.edge_arrows.shown()
	_eq([shown[0].zone_key(), shown[1].zone_key()], ["z1", "z0"], "the two changed pool places")
	_check(shown[1].get_global_rect().has_point(at), "z0's arrow is where it was, under the pointer")
	_eq(said, ["z0"] as Array[String], "nothing more is said: the same zone is under the pointer")
	await _hover(at + Vector2(1, 0))
	_eq(said, ["z0"] as Array[String], "nor when the pointer moves a pixel within that arrow")
	await _hover(Vector2(4, 4))
	_eq(said, ["z0", ""] as Array[String], "off the arrows: no zone, said once")
	hud.free()
	await _frames(2)


## Leaving an arrow straight for another HUD row leaves that row's mark
## standing. The arrows say "no zone any more" a frame after the pointer left
## one (another arrow may be entered in the same motion), by when the row has
## already pointed at its pane: that late word takes back only what an arrow
## pointed at. So a row for a pane on another machine keeps its card
## outlined, and a row for a pane of the shown map keeps its desk's dashed
## frame, through the frames after and through a refresh. The reverse, from a
## row straight onto an arrow, outlines the arrow's zone's blocked cards and
## nothing else; one arrow to the next says the next zone and never "none"
## between; and off everything, nothing is pointed at. (S3 BAR-b, 2026-10-27:
## the outlines were the zones' SPACES rows.)
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the rows were the agent list's, beside the
## open drawer; they are the EVENTS page's now (was test_leaving_an_arrow_for_a_list_row_keeps_the_rows_mark).
func test_leaving_an_arrow_for_an_events_row_keeps_the_rows_mark() -> void:
	var office := await _two_machine_office()
	# S3 BAR-b (2026-10-27): the SPACES rail is gone; the world starts 16 in and first plans take its width.
	# web's blocked desk is on screen: data:p1 waits off screen below, beside
	# infra:p1, for the two arrows.
	await _fresh_waits(office, _with(fixture, "data:p1", {"agent_status": "blocked"}))
	var key := HerdrFleet.pane_key(BEE, "hive:p1")
	var row := _event_row(office, key)
	var near := _event_row(office, _pk("web:p1"))
	var arrows := office.hud.edge_arrows.shown()
	_check(row != null and row.is_visible_in_tree(), "hive:p1 has a row on the EVENTS page")
	_check(near != null and near.is_visible_in_tree(), "and web:p1, on the shown map")
	_check(not arrows.is_empty(), "blocked desks wait off screen: edge arrows")
	if row == null or near == null or arrows.is_empty():
		_done(office)
		return
	var hive := office.frame.zone_of(key)
	var zone := arrows[0].zone_key()
	_check(zone != hive, "the arrow is for a zone of the shown map, the row for hive")
	var zone_cards := _blocked_cards_of(office, zone)
	_check(not zone_cards.is_empty(), "the arrow's zone has blocked cards")
	var on_arrow := arrows[0].get_global_rect().get_center()
	var on_row := row.get_global_rect().get_center()
	var off := office.hud.world_rect().position + Vector2(4, 4)
	await _hover(off)
	var active := office.navigator.active_key
	var said: Array[String] = []
	office.hud.zone_pointed.connect(func(zone_key: String) -> void: said.append(zone_key))
	await _hover(on_arrow)
	_eq(_outlined(office), zone_cards, "on the arrow: its zone's blocked cards are outlined")
	# Arrow, then straight onto the row of another zone.
	await _hover(on_row)
	_eq(said, [zone, ""] as Array[String], "the arrows said their zone, then none, once each")
	_eq(_outlined(office), [key], "straight onto hive's row: hive:p1's card is outlined")
	await _frames(3)
	_eq(_outlined(office), [key], "and stays outlined once the arrow's late word has come")
	office.refresh()
	await _frames(2)
	_eq(_outlined(office), [key], "and through a refresh")
	# The reverse: the row, then straight onto the arrow.
	await _hover(on_arrow)
	_eq(_outlined(office), zone_cards, "from the row straight onto the arrow: the arrow's zone's, and only they")
	_check(not office.floor_view.pointer.visible, "and nothing in the world")
	# Arrow, then straight onto a row for a desk of the shown map.
	await _hover(near.get_global_rect().get_center())
	await _frames(3)
	_check(office.floor_view.pointer.visible, "straight onto web:p1's row: its desk keeps the dashed frame")
	_eq(office.floor_view.pointer.key, _pk("web:p1"), "that desk")
	_eq(_outlined(office), [], "and no card is outlined")
	await _hover(on_arrow)
	_eq(_outlined(office), zone_cards, "back on the arrow: its zone's")
	_check(not office.floor_view.pointer.visible, "and the desk's frame is gone")
	# One arrow to the next: the next zone, never "none" between.
	_check(arrows.size() > 1 and arrows[1].zone_key() != zone, "infra and data both wait off screen: two arrows")
	if arrows.size() > 1:
		said.clear()
		await _hover(arrows[1].get_global_rect().get_center())
		_eq(said, [arrows[1].zone_key()] as Array[String], "arrow to arrow: one word, the next zone")
		_eq(
			_outlined(office),
			_blocked_cards_of(office, arrows[1].zone_key()),
			"and that zone's cards are the ones outlined"
		)
	await _hover(off)
	_eq(_outlined(office), [], "off everything: nothing is outlined")
	_check(not office.floor_view.pointer.visible, "and nothing is pointed at in the world")
	_eq(office.navigator.active_key, active, "nothing was selected on the way")
	_eq(office.navigator.shown_key, LOCAL, "and the map is the same")
	_done(office)


# --- helpers ------------------------------------------------------------------


## Fresh waits for web:p1 (Local, from `local`) and bee's hive:p1, each a
## blocked stretch that begins now, so each has an EVENTS row near the top;
## then the EVENTS page by a real click on its tab.
func _fresh_waits(office: OfficeDouble, local: Dictionary = fixture) -> void:
	_feed(office, _with(local, "web:p1", {"agent_status": "idle"}))
	_feed(office, local)
	_bee_live(office, _bee_snapshot("idle"))
	_bee_live(office, _bee_snapshot("blocked"))
	await _frames(2)
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)


## An edge arrow for zone `zone`, one blocked desk below the view's middle.
func _arrow_below(zone: String) -> EdgeArrowModel:
	var arrow := EdgeArrowModel.new()
	arrow.zone_key = zone
	arrow.pane_key = zone + ":p0"
	arrow.machine = LOCAL
	arrow.number = "3"
	arrow.blocked = 1
	arrow.edge = EdgeArrowModel.Edge.BOTTOM
	arrow.along = 0.5
	return arrow


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The panes whose portrait cards are outlined as pointed at (S3 BAR-b,
## 2026-10-27: it was the zones whose SPACES rows were).
func _outlined(office: OfficeDouble) -> Array:
	return (
		office
		. hud
		. bar
		. cards()
		. filter(func(card: PortraitCard) -> bool: return card.pointed())
		. map(func(card: PortraitCard) -> String: return card.key)
	)


## The blocked agents of zone `zone` that have a card in the bar, as an edge
## arrow for that zone outlines them.
func _blocked_cards_of(office: OfficeDouble, zone: String) -> Array:
	var found: Array = []
	for card in office.hud.bar.cards():
		var shown := card.shown_card()
		if shown.group == PortraitBarModel.Group.BLOCKED and shown.zone_key == zone:
			found.append(card.key)
	return found


func _l_key(down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_L
	event.pressed = down
	return event


## `L` down (or up) through the window's input, then the frames the lens needs
## to see it.
## S3 item 7 (2026-10-27): one carpet per zone, in its group's family. The
## carpet is furnishing: held, every carpet is LENS_DIM, and every pod's
## background, later in Ground than the carpets, still washes its floor at
## LENS_WASH_ALPHA of its tone; let go, the carpets are as painted. At night
## the carpet's own modulate stays WHITE: the night tint is the world
## canvas's (NightLight), over carpets and badges alike.
func test_the_carpet_dims_as_furnishing_and_the_wash_lies_over_it() -> void:
	var office := await _live_office()
	office.settle()
	await _frames(2)
	var holder := office.floor_view.ground.get_node_or_null("Carpets")
	_check(holder != null, "the floor lays its carpets in Ground/Carpets")
	if holder == null:
		_done(office)
		return
	var carpets := holder.get_children()
	_eq(carpets.size(), office.layout_plan().zones.size(), "one carpet per zone")
	await _hold()
	for carpet: Node in carpets:
		_eq((carpet as CanvasItem).modulate, OfficeFloorView.LENS_DIM, "held: %s dims" % carpet.name)
	var washed := 0
	for tab: String in office.floor_view.desks:
		var desk := office.floor_view.desks[tab]
		_check(desk.background.get_index() > holder.get_index(), tab + ": its background lies over the carpets")
		if desk.wash.visible:
			washed += 1
			_eq(desk.wash.color.a, OfficeFloorView.LENS_WASH_ALPHA, tab + ": its wash as opaque as ever")
			_eq(desk.wash.modulate, Color.WHITE, tab + ": and not dimmed")
	_check(washed > 0, "the pods are washed: %d" % washed)
	await _let_go()
	for carpet: Node in carpets:
		_eq((carpet as CanvasItem).modulate, Color.WHITE, "let go: %s as painted" % carpet.name)
	office.toggle_light()
	await _frames(2)
	_eq(office.night, 1.0, "the light turned over to night")
	_eq(
		(office.get_node("NightLight") as CanvasModulate).color,
		DayLight.NIGHT_TINT,
		"the world's canvas takes the tint"
	)
	for carpet: Node in carpets:
		_eq((carpet as CanvasItem).modulate, Color.WHITE, "at night: %s keeps no tint of its own" % carpet.name)
	_done(office)


## S3 item 7 (2026-10-27): one carpet per zone, in its group's family; CARPET-B1
## (ruling 1): a seat's words stand on a paper tag. Held, every shown lens line
## and plate wears the pack's `paper` as a square, unshaded tag with no margins
## of its own (OfficeDraw.back_label()), hugging its text in its row: centred,
## the row's height, its text and TAG_PAD either side (a longer text fills the
## row). The tag is the Label's own stylebox, a signal like its words: nothing
## dims it. `ink` on `paper` keeps at least 4.5:1 (WCAG). A label with no text
## wears no tag.
func test_a_seats_words_stand_on_a_paper_tag() -> void:
	var office := await _live_office()
	office.settle()
	await _frames(2)
	await _hold()
	var paper := office.art.color(ArtContract.PAPER)
	var tagged := 0
	for station in _seats(office):
		var lens_at: Vector2 = OfficeStation.LENS_AT[station.side]
		var plate_at: Vector2 = OfficeStation.PLATE_AT[station.side]
		# S3 SEATTAGS (2026-10-27): a plate next to a vacant seat on its side of the
		# pod takes that seat's slot too (web:p1 here), so its row is the station's
		# plate_row(); test_office_geometry pins that row's literals.
		var rows: Dictionary[String, Rect2] = {
			"Lens": Rect2(lens_at, OfficeStation.LENS_SIZE),
			"Plate": station.plate_row(),
		}
		var own: Dictionary[String, float] = {
			"Lens": lens_at.x + OfficeStation.LENS_SIZE.x / 2.0,
			"Plate": plate_at.x + OfficeStation.PLATE_SIZE.x / 2.0,
		}
		for row: String in rows:
			var words: Label = station.get_node("Overlay/" + row)
			if not words.is_visible_in_tree() or words.text.is_empty():
				continue
			tagged += 1
			var name := "%s %s" % [station.pane_key, row]
			var tag := words.get_theme_stylebox("normal") as StyleBoxFlat
			_check(tag != null, name + ": a flat tag")
			if tag == null:
				continue
			_eq(tag.bg_color, paper, name + ": paper")
			_check(not tag.anti_aliasing and tag.draw_center, name + ": drawn square, unshaded")
			_eq(
				[tag.corner_radius_top_left, tag.corner_radius_bottom_right, tag.border_width_top],
				[0, 0, 0],
				name + ": no corner, no border"
			)
			_eq(tag.get_minimum_size(), Vector2.ZERO, name + ": no margins of its own")
			var face := words.get_theme_font("font")
			var wide := face.get_string_size(words.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			var hugged := minf(rows[row].size.x, ceilf(wide) + 2.0 * OfficeDraw.TAG_PAD)
			var drawn := Rect2(words.position, words.size)
			_eq(drawn.size, Vector2(hugged, rows[row].size.y), name + ": hugs its text, the row's height")
			# S3 SEATTAGS: centred on its own column, as far as its row lets it (a
			# 30-wide row centres it there; a widened one keeps it inside).
			var left := clampf(own[row] - hugged / 2.0, rows[row].position.x, rows[row].end.x - hugged)
			_eq(drawn.position.x, left, name + ": centred on its column, inside its row")
			_eq(drawn.position.y, rows[row].position.y, name + ": in its row")
			_eq([words.modulate, words.self_modulate], [Color.WHITE, Color.WHITE], name + ": not dimmed")
	_check(tagged > 4, "the held lens shows tagged words: %d" % tagged)
	var ink := office.art.color(ArtContract.INK)
	_check(_contrast(ink, paper) >= 4.5, "ink on paper reads: %.2f" % _contrast(ink, paper))
	var bare := Label.new()
	office.pen.back_label(bare)
	_check(bare.get_theme_stylebox("normal") is StyleBoxEmpty, "a label with no text wears no tag")
	bare.free()
	await _let_go()
	_done(office)


## S3 SEATTAGS (2026-10-27): a map with few occupied seats
## (FloorLayoutPolicy.FEW_SEATS, agents and shells) shows every seat's plate
## with nothing hovered, selected or held, and no vacant seat's; one more
## occupied seat and only the selected seat's shows, while a real pointer over
## a seat, a real click on one and `L` still show theirs; back to the threshold,
## all of them again. Nothing is rebuilt: the same world, the same plates.
func test_a_map_with_few_seats_shows_every_plate() -> void:
	# S3 SEATTAGS round 2: the map is sized from the constant (12, then 16), not the fixture's 13.
	var few := _sized(fixture, FloorLayoutPolicy.FEW_SEATS)
	var more := _sized(fixture, FloorLayoutPolicy.FEW_SEATS + 1)
	var office := await _live_office(few)
	office.settle()
	await _frames(2)
	_check(OfficeFloorView.few_seats(office.frame.building_of(office.navigator.shown_key).map), "few seats")
	var shown := 0
	for station in _all_stations(office):
		_eq(_plate(station).visible, not station.vacant, "few seats: a plate over every taken seat: " + station.name)
		if not station.vacant and station.pane_key != office.navigator.active_key:
			shown += 1
	_check(shown >= 8, "plates shown that nothing selects: %d" % shown)
	var world := office.world.get_instance_id()
	var plates := _plate_ids(office)
	_feed(office, more)
	office.settle()
	await _frames(2)
	_check(not OfficeFloorView.few_seats(office.frame.building_of(office.navigator.shown_key).map), "one more: not few")
	_eq(office.world.get_instance_id(), world, "the same world")
	for station in _seats(office):
		var picked := station.pane_key == office.navigator.active_key
		_eq(_plate(station).visible, picked, "one more seat: only the selected plate: " + station.pane_key)
	var other := _unselected_in_view(office)
	_check(other != null, "a seat in view that is not selected")
	if other == null:
		_done(office)
		return
	await _pointer_to(other.target_rect().get_center() - office.camera.position)
	_check(_plate(other).visible, "a real pointer over a seat shows its plate")
	await _pointer_to(Vector2(2, 2))
	_check(not _plate(other).visible, "and moving off hides it")
	await _click_at(other.target_rect().get_center() - office.camera.position)
	_eq(office.navigator.active_key, other.pane_key, "a real click selects the seat")
	await _pointer_to(Vector2(2, 2))
	_check(_plate(other).visible, "selected, its plate shows")
	await _hold()
	for station in _seats(office):
		_check(_plate(station).visible, "held, every plate shows: " + station.pane_key)
	await _let_go()
	for station in _seats(office):
		_eq(_plate(station).visible, station == other, "let go, only the selected plate: " + station.pane_key)
	_feed(office, few)
	office.settle()
	await _frames(2)
	for station in _all_stations(office):
		_eq(_plate(station).visible, not station.vacant, "back to few: every taken seat's again: " + station.name)
	_eq(office.world.get_instance_id(), world, "still the same world")
	var kept := _plate_ids(office)
	for key: String in kept:
		_eq(kept[key], plates.get(key, -1), "the same plate node: " + key)
	_done(office)


## S3 SEATTAGS: each machine's map takes its own count. Local's (one seat more
## than FloorLayoutPolicy.FEW_SEATS) shows only the selected seat's plate; a real
## click on bee's chip shows bee's map (one seat, nothing selected) with its
## plate; a click on Local's chip, Local's rule again.
func test_each_machines_map_takes_its_own_count() -> void:
	var office := await _two_machine_office(_sized(fixture, FloorLayoutPolicy.FEW_SEATS + 1))
	var quiet := _bee_snapshot("working")
	quiet.erase("focused_pane_id")
	_feed_bee(office, quiet)
	office.refresh()
	await _frames(2)
	_eq(office.navigator.shown_key, LOCAL, "Local's map is shown")
	for station in _seats(office):
		var picked := station.pane_key == office.navigator.active_key
		_eq(_plate(station).visible, picked, "Local, one seat too many: only the selected plate: " + station.pane_key)
	for machine: String in [BEE, LOCAL]:
		var at := office.hud.bar.chip_for(machine).get_global_rect().get_center()
		await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
		await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
		await _frames(2)
		_eq(office.navigator.shown_key, machine, "a click on its chip shows %s's map" % machine)
		var few := machine == BEE
		_eq(
			OfficeFloorView.few_seats(office.frame.building_of(office.navigator.shown_key).map),
			few,
			"%s's map: few seats %s" % [machine, few]
		)
		_check(not _seats(office).is_empty(), "%s's map has seats" % machine)
		for station in _seats(office):
			var selected := (station.get_node("Overlay/Selection") as CanvasItem).visible
			if few:
				_check(not selected, "bee's seat is not selected: " + station.pane_key)
			_eq(_plate(station).visible, few or selected, "%s: its plate: %s" % [machine, station.pane_key])
	_done(office)


## `snapshot` with exactly `count` panes: its last ones dropped, or copies of
## its pane `like` (its first by default) added (new pane and terminal ids, in
## the same tab).
func _sized(snapshot: Dictionary, count: int, like := "") -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var panes := _list(result, "panes")
	var first: Dictionary = panes[0]
	for pane: Dictionary in panes:
		if pane.pane_id == like:
			first = pane
	while panes.size() > count:
		panes.pop_back()
	while panes.size() < count:
		var extra := first.duplicate(true)
		extra.pane_id = "%s-copy%d" % [first.pane_id, panes.size()]
		extra.terminal_id = "term-copy%d" % panes.size()
		panes.append(extra)
	_eq(panes.size(), count, "a map of %d seats" % count)
	return result


## Every station on the shown map, vacant ones too, in tree order.
func _all_stations(office: OfficeDouble) -> Array[OfficeStation]:
	var found: Array[OfficeStation] = []
	for node: Node in office.world.find_children("*", "", true, false):
		if node is OfficeStation:
			found.append(node as OfficeStation)
	return found


## Each taken seat's plate node, by pane key.
func _plate_ids(office: OfficeDouble) -> Dictionary[String, int]:
	var ids: Dictionary[String, int] = {}
	for station in _seats(office):
		ids[station.pane_key] = _plate(station).get_instance_id()
	return ids


## A taken seat whose click target is wholly in the world's room on screen and
## that is not selected; null when there is none.
func _unselected_in_view(office: OfficeDouble) -> OfficeStation:
	for station in _seats(office):
		if station.pane_key != office.navigator.active_key and _desk_in_view(office, station.pane_key):
			return station
	return null


## The WCAG contrast ratio of two opaque colours.
static func _contrast(a: Color, b: Color) -> float:
	var lighter := maxf(_luminance(a), _luminance(b))
	var darker := minf(_luminance(a), _luminance(b))
	return (lighter + 0.05) / (darker + 0.05)


## WCAG relative luminance of an sRGB colour.
static func _luminance(colour: Color) -> float:
	var linear := Vector3.ZERO
	for channel in 3:
		var value: float = colour[channel]
		linear[channel] = value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4)
	return 0.2126 * linear.x + 0.7152 * linear.y + 0.0722 * linear.z


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


## A real click on the bottom panel's tab for `page` (S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit
## bar band on tall screens, no drawer tab).
func _press_tab(office: OfficeDouble, page: OfficeBottomPanel.Page) -> void:
	var tabs := office.hud.staff.tabs
	var rect := tabs.get_tab_rect(page)
	var at := tabs.get_global_rect().position + rect.get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	await _frames(2)


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _part(bubble: OfficeChip, part: String) -> CanvasItem:
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


## The furnishing the lens dims: the shell, the zones' carpets, the decor and the counters.
func _furnishing(office: OfficeDouble) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	var shell := office.floor_view.ground.get_node_or_null("Shell") as CanvasItem
	if shell != null:
		found.append(shell)
	# S3 item 7 (2026-10-27): one carpet per zone, in its group's family.
	var carpets := office.floor_view.ground.get_node_or_null("Carpets")
	if carpets != null:
		for carpet in carpets.get_children():
			found.append(carpet as CanvasItem)
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


## The chip over pane `key` on screen, its middle, once revealed.
func _bubble_at(office: OfficeDouble, key: String) -> Vector2:
	office.reveal(key)
	await _frames(2)
	return _station(office, key).chip_rect().get_center() - office.camera.position


## `snapshot` without pane `pane_id`, in its panes, agents and layouts.
func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result
