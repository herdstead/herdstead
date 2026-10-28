extends "res://tools/office_test_base.gd"
## How the mouse and the keys move between machines and zones once the SPACES
## rail is gone (S3 BAR-b, 2026-10-27): the zones' order (ascending, each
## worktree's mezzanine right after its source) that PageUp and PageDown step
## through, a portrait card's place (its zone tag and space) panning to its
## zone, a machine chip in the top bar showing its machine's map, a dropped
## machine's chip dimmed with none of its agents as cards, the world starting
## 16 in where the rail stood, a HUD line about another machine's pane
## outlining its card; each zone's sign; and the machine plate's problem line.
## Clicks, hovers, drags and keys go through real input. Run through
## run_tests.sh.
##
## godot --headless --path . --script tools/test_map_navigation.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## (This suite was tools/test_space_rail.gd, the SPACES rail's, which took over
## from the FLOORS suite when the FLOORS minimap became the rail. The rail's
## windows, its narrow form, its names and its in-view marks retired with it;
## the arrows' own cases are tools/test_edge_arrows.gd, the bar's
## tools/test_portrait_bar.gd and tools/test_top_bar.gd; a case here still
## clicks an arrow where its subject is the navigation count.
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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("map-navigation-socks"))
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
	return "MAP NAVIGATION TESTS"


# --- the zones' order and the page keys ------------------------------------------


## Zones ascending, and a worktree's mezzanine right after the zone it was
## made from, its sign naming its checkout; a worktree whose source is not
## open stands by its own number. PageUp and PageDown step through this order
## (OfficeFrame.zone_order), so PageDown from a source goes into its
## mezzanines first. (S3 BAR-b, 2026-10-27: the SPACES rail drew this order;
## its rows, indents and names are gone, the signs say the same words.)
func test_mezzanines_hang_under_their_source_in_ascending_order() -> void:
	var office := await _live_office()
	var order: Array = office.frame.zone_order
	_eq(order, [_zone("hs"), _zone("hud"), _zone("data"), _zone("notes"), _zone("ops")], "the page keys' order")
	_eq(_chips(office), ["1", "1A", "1B", "4", "5"], "the sign's number: a mezzanine's is its source's and a letter")
	_eq(
		order.map(func(key: String) -> String: return _label(office.floor_view.zone_sign(key), "%Title").text),
		["HERDSTEAD", "HUD-LANE", "DATA-LANE", "NOTES", "OPS LANE"],
		"a mezzanine's sign reads as its checkout, a zone and an orphan worktree as their workspace"
	)
	_eq(office.navigator.current_zone(office.frame), _zone("hs"), "herdr's focus is on 1")
	await _office_key(office, KEY_PAGEDOWN)
	_eq(office.navigator.current_zone(office.frame), _zone("hud"), "PageDown from 1 goes into 1A, its mezzanine")
	_done(office)


## PageUp and PageDown walk the zones in that order: down from a source zone
## into its mezzanines and on to the higher numbers, up out of them back to it.
## The order is ascending, so PageUp goes to the lower number. Each step pans
## to its zone at once, on the same map: nothing rebuilt.
func test_page_keys_step_through_the_zones_in_order() -> void:
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


# --- a card's place --------------------------------------------------------------


## A portrait card's place (its zone tag and space) is a button of its own: the
## pointer on it still points at the card's desk, its tooltip says the zone's
## sign, and a click pans to that zone at once, one navigation, selecting
## nothing, as a SPACES row did. An unseated pane's place is only words, and a
## click there picks the pane as the rest of its card does.
func test_a_cards_place_names_its_zone_and_a_click_pans_there() -> void:
	var office := await _live_office()
	var blocked := _pane("hud:p1")
	var card := office.hud.bar.card_for(blocked)
	_check(card != null and not card.face_only(), "1A's blocked agent has a card, words and all")
	var place: Button = card.get_node("%PlaceButton")
	var at := place.get_global_rect().get_center()
	var face := (card.get_node("%Face") as Control).get_global_rect().get_center()
	var pointer := office.floor_view.pointer
	await _pointer_to(face)
	_eq([pointer.key, pointer.visible], [blocked, true], "on the card's face, its desk is framed")
	await _pointer_to(at)
	_eq(root.gui_get_hovered_control(), place, "the pointer rests on the card's place")
	_eq([pointer.key, pointer.visible], [blocked, true], "from the face onto the place, the frame stays")
	await _pointer_to(face)
	_eq([pointer.key, pointer.visible], [blocked, true], "and back onto the face")
	await _pointer_to(office.hud.world_rect().get_center())
	_eq([pointer.key, pointer.visible], ["", false], "off the card: no frame")
	await _pointer_to(at)
	_eq(
		place.get_tooltip(place.get_local_mouse_position()),
		"1A HUD-LANE\nherdstead · hud-lane · worktree of 1",
		"which says the zone's sign and what the sign's own tooltip says"
	)
	_eq([pointer.key, pointer.visible], [blocked, true], "and the card still points at its desk")
	var picked := office.picked_key
	var revision := office.navigator.nav_revision
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	_eq(office.navigator.current_zone(office.frame), _zone("hs"), "a press pans nowhere")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(office.navigator.current_zone(office.frame), _zone("hud"), "released: 1A at once")
	_eq(office.navigator.nav_revision, revision + 1, "one navigation")
	_eq(office.picked_key, picked, "and nothing selected")
	_eq(office.layout_plan().floor_key, LOCAL, "on the machine's map")
	_check(_zone_in_view(office, _zone("hud")), "its zone in view")
	# notes:p1, in a workspace no zone stands for, asks: a card with no zone.
	_feed(office, _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"}))
	await _frames(2)
	var unseated := office.hud.bar.card_for(_pane("notes:p1"))
	_check(unseated != null and not unseated.face_only(), "the unseated agent has a card")
	var words: Button = unseated.get_node("%PlaceButton")
	_eq(_label(unseated, "%Place").text, "?", "its place says it has no space")
	_eq(words.mouse_filter, Control.MOUSE_FILTER_IGNORE, "and is only words")
	_eq(words.tooltip_text, "", "with no sign to say")
	revision = office.navigator.nav_revision
	await _click_at(words.get_global_rect().get_center())
	_eq(office.picked_key, _pane("notes:p1"), "a click there picks the pane, as the rest of the card does")
	_eq(office.navigator.nav_revision, revision + 1, "one navigation, the pick's")
	_done(office)


## A dropped machine's chip says so (the blocked colour, as the MACHINES
## counter did; never the paper of a machine that answers) and none of its
## agents has a card: a lost connection is not activity (invariant 4). It
## comes back, chip and cards, when the machine is back.
func test_a_dropped_machines_chip_is_dimmed_and_it_has_no_cards() -> void:
	var office := await _two_machine_office()
	var bar := office.hud.bar
	var hive := HerdrFleet.pane_key(BEE, "hive:p1")
	var bee_cards := func() -> Array:
		return (
			bar
			. portraits()
			. cards
			. filter(func(card: PortraitBarModel.Card) -> bool: return card.machine == BEE)
			. map(func(card: PortraitBarModel.Card) -> String: return card.key)
		)
	_eq(bar.chip_for(BEE).theme_type_variation, &"MachineChip", "bee answers: its chip in paper")
	_eq(bee_cards.call(), [hive], "its blocked agent has a card")
	_check(bar.card_for(hive) != null, "shown")
	_bee(office)._go_offline()
	office.fleet.liveness_changed.emit()
	await _frames(2)
	var chip := bar.chip_for(BEE)
	_check(chip.machine_state() != MachineLiveness.State.LIVE, "bee has dropped")
	_eq(chip.theme_type_variation, StringName(MachineChip.LOOKS[chip.machine_state()]), "its chip says how it answers")
	_check(chip.theme_type_variation != &"MachineChip", "not in a live machine's paper")
	_eq(bee_cards.call(), [], "none of its agents has a card")
	_check(bar.card_for(hive) == null, "the blocked one included")
	_check(office.hud.bar.alarmed(), "the status line says a machine is down")
	_check(
		chip.get_tooltip(Vector2.ZERO).begins_with("bee · "),
		"the chip's tooltip names it: " + chip.get_tooltip(Vector2.ZERO)
	)
	_eq(bar.chip_for(LOCAL).theme_type_variation, &"MachineChipCurrent", "Local's map is still the one shown")
	_feed_bee(office, _bee_snapshot("blocked"))
	await _frames(2)
	_eq(bar.chip_for(BEE).theme_type_variation, &"MachineChip", "back: in paper again")
	_eq(bee_cards.call(), [hive], "and its agent's card is back")
	_done(office)


## A card's place says what its zone's sign says: the sign's number (never
## `3F`) and words, then what the sign's own tooltip says (repository,
## checkout, whose worktree); its tag wears its worktree group's carpet. The
## plate names the machine, not a zone; every zone of a worktree group wears
## the group's one accent on its sign, a zone in no group its own. A zone with
## no agent has no card: the page keys and `S` reach it.
func test_a_cards_place_says_the_signs_words_and_repo() -> void:
	var office := await _live_office(fixture, Vector2(1280, 480))
	var bar := office.hud.bar
	_eq(office.plate.title_text(), "LOCAL", "the plate names the machine")
	_check(not _label(office.plate, "%WorktreeOf").visible, "with no worktree line")
	_check(not _node(office.plate, "%Accent").visible, "and no group's accent")
	_eq(bar.fitted().rung, 1, "1280 wide: every agent a card")
	var places := {}
	for card in bar.cards():
		var zone: String = card.shown_card().zone_key
		var board := office.floor_view.zone_sign(zone)
		var said := "%s %s" % [_label(board, "%Number").text, _label(board, "%Title").text]
		var place: Button = card.get_node("%PlaceButton")
		var tip := place.tooltip_text.split("\n")
		_eq(tip[0], said, "%s: the place's tooltip starts with its sign's words" % card.key)
		_eq(tip[1], OfficeQuestionTips.sign_text(office.frame.find_zone(zone)), "%s: then the sign's tip" % card.key)
		_check(not _label(board, "%Number").text.ends_with("F"), "%s: no F" % card.key)
		var tag: Panel = card.get_node("%Tag")
		_eq(
			tag.theme_type_variation,
			StringName("CarpetTag%d" % OfficeZoneSign.accent_of(card.shown_card().group_key)),
			"%s: the tag wears its group's carpet" % card.key
		)
		places[zone] = place.tooltip_text
	_eq(
		places.keys(),
		[_zone("hud"), _zone("data"), _zone("hs"), _zone("ops")],
		"every zone with an agent has a place to click; 4, a shell's alone, has none"
	)
	_eq(places[_zone("hud")], "1A HUD-LANE\nherdstead · hud-lane · worktree of 1", "a mezzanine's")
	var stripes := {}
	for id: String in ["hs", "hud", "data", "notes", "ops"]:
		var accent: ColorRect = office.floor_view.zone_sign(_zone(id)).get_node("%Accent")
		stripes[id] = accent.color
	_eq([stripes.hud, stripes.data], [stripes.hs, stripes.hs], "the group's one accent on each of its signs")
	for id: String in ["notes", "ops"]:
		var own: Color = office.art.color(ArtContract.ACCENTS[OfficeZoneSign.accent_of(_zone(id))])
		_eq(stripes[id], own, "%s, in no group, wears its own" % id)
	_done(office)


## Blocked comes first: an agent asking while herdr still launches it is a
## blocked agent to the bar and the arrows. data:p2 (1B) blocks before its
## launch is over: it has a blocked card that says it asks, its zone counts
## it, and an arrow points to 1B.
## Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new zone takes lanes until it stands one row; the map replans.
## In the 480x320 window with herdr's focus on 5 (ops, the third row): 1B stands
## beside 1 in the first row of any map of two lanes or more (FRAME-Q2).
func test_a_blocked_start_has_a_blocked_card_and_an_arrow() -> void:
	var focused := _focused_on(fixture, "ops:p1")
	var office := await _live_office(focused, Vector2(480, 320))
	_feed(office, _with(focused, "data:p2", {"agent_status": "blocked", "launch_pending": true}))
	await _frames(2)
	_check(office.frame.pane(_pane("data:p2")).starting, "herdr still launches data:p2")
	var blocked := office.hud.bar.portraits().of_group(PortraitBarModel.Group.BLOCKED)
	_eq(
		blocked.map(func(card: PortraitBarModel.Card) -> String: return card.key),
		[_pane("hud:p1"), _pane("data:p2")],
		"a blocked card, after 1A's, blocked since before the office opened (an unknown start first)"
	)
	var card := office.hud.bar.card_for(_pane("data:p2"))
	_check(card != null, "shown")
	_check(card.get_tooltip(Vector2.ZERO).contains("NEEDS INPUT"), "and says it asks, in the pack's words")
	_eq(office.frame.find_zone(_zone("data")).zone_model.blocked, 1, "its zone counts it")
	var keys := office.hud.edge_arrows.shown().map(func(arrow: OfficeEdgeArrow) -> String: return arrow.zone_key())
	_check(keys.has(_zone("data")), "an arrow points at 1B, off screen: " + str(_arrow_texts(office)))
	_done(office)


## The world starts 16 in from the left, the staff panel's and NEWS's inset,
## where the rail stood, and a map planned for the first time takes the rail's
## width: at the 800-wide test window 740 units, 23 cells, four lanes (it was
## 660, 20, three); at the default window (1920x960 at 2x: 960 units) 900, 28,
## five (772, 24, four); at the 480x320 minimum 420, 13, two (340, 10, two).
func test_the_world_starts_at_the_left_inset_and_a_first_plan_takes_the_rails_width() -> void:
	# S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the
	# world runs to the right
	# edge (24, 29 and 14 cells: the same four, five and two lanes), under a 52-unit bar on a tall
	# screen and above the docked panel.
	# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: the two docked
	# rooms 241 -> 276 high; the 480x320 one (not docked) is unchanged.
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the docked panel 120 tall and the two rows 54, each
	# room 4 shorter (the cells and lanes unchanged).
	for step: Array in [
		[Vector2(800, 480), Rect2(16, 68, 776, 272), 23, 4],
		[Vector2(960, 480), Rect2(16, 68, 936, 272), 28, 5],
		[Vector2(480, 320), Rect2(16, 48, 456, 198), 13, 2],
	]:
		var screen: Vector2 = step[0]
		var office := await _live_office(fixture, screen)
		var room := office.hud.world_rect()
		_eq(room, step[1], "%s: the world's room" % screen)
		_eq(
			room.position.x,
			office.hud.placed(office.hud.staff).position.x,
			"%s: its left edge is the bottom panel's" % screen
		)
		_eq(office.hud.plan_width(), room.size.x, "%s: the plan is as wide as the room" % screen)
		var plan := office.layout_plan()
		_eq(
			[plan.initial_width_cells, plan.lanes], [step[2], step[3]], "%s: cells and lanes of the first plan" % screen
		)
		_done(office)
		await _frames(2)


# --- machines and gestures -------------------------------------------------------


## Every gesture that goes somewhere counts one navigation (what a pick waiting
## for a new pane records): an edge arrow click, a card's place click, a
## machine chip click, PageDown, PageUp. Panning counts none: a real drag, a
## wheel notch; nor does a desk click. pick_zone() pans to a zone exactly as a
## click on a card's place does.
func test_chip_place_and_arrow_gestures_count_and_panning_does_not() -> void:
	var office := await _two_machine_office()
	var navigator := office.navigator
	await _frames(2)
	var revision := navigator.nav_revision
	var zone := func() -> String: return navigator.current_zone(office.frame)
	var arrow := office.hud.edge_arrows.shown()[0]
	await _click_at(arrow.get_global_rect().get_center())
	_eq(navigator.nav_revision, revision + 1, "an edge arrow: one navigation")
	await _click_place(office, _pane("hud:p1"))
	_eq([zone.call(), navigator.nav_revision], [_zone("hud"), revision + 2], "a card's place: one")
	var clicked := [zone.call(), navigator.picked_machine, office.world_model, office.camera.pan]
	await _office_key(office, KEY_PAGEUP)
	_eq([zone.call(), navigator.nav_revision], [_zone("hs"), revision + 3], "PageUp: one, to the lower number")
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
	await _click_desk(office, _pane("hs:p2"))
	_eq(office.picked_key, _pane("hs:p2"), "a desk click picks")
	_eq([zone.call(), navigator.nav_revision], [_zone("hs"), revision + 3], "none of them navigates")
	await _office_key(office, KEY_PAGEDOWN)
	_eq([zone.call(), navigator.nav_revision], [_zone("hud"), revision + 4], "PageDown: one, to the higher number")
	await _click_heading(office, BEE)
	_eq([navigator.shown_key, navigator.nav_revision], [BEE, revision + 5], "a machine chip: one")
	await _click_heading(office, LOCAL)
	_eq([navigator.shown_key, navigator.nav_revision], [LOCAL, revision + 6], "and one back")
	await _office_key(office, KEY_PAGEDOWN)
	_eq([zone.call(), navigator.nav_revision], [_zone("hud"), revision + 7], "PageDown from the pick's zone, 1: one")
	navigator.pick_zone(_zone("hud"))
	office.refresh()
	# The camera holds a pan inside the map once it settles, as it had for the click.
	await _frames(2)
	var picked := [zone.call(), navigator.picked_machine, office.world_model, office.camera.pan]
	_eq(picked, clicked, "pick_zone() pans to the zone as a card's place did")
	_eq(navigator.nav_revision, revision + 8, "and counts one navigation")
	_done(office)


## A desk picked by a real click stops the follow only while its pane is there.
## Once herdr closes that pane the selection is herdr's focus again, and every
## move of the focus to a zone out of sight pans its desk into the world's room:
## the map is one world, so nothing else would bring it into view.
## Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new zone takes lanes until it stands one row; the map replans.
## In the 480x320 window: at 800x480 the six zones stand three abreast, w2 beside w0.
func test_focus_is_revealed_again_once_the_picked_pane_is_gone() -> void:
	var zones := _six_zones()
	var office := await _live_office(zones, Vector2(480, 320))
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


## A real click on a machine's chip shows that machine's map at once: a cold
## switch (a new world), one navigation, nothing picked, the chips as they
## were, and that machine's zone on screen.
func test_a_chip_click_switches_to_that_machine() -> void:
	var office := await _two_machine_office()
	var navigator := office.navigator
	await _frames(2)
	_eq(navigator.shown_key, LOCAL, "Local's map is shown")
	var world := office.world.get_instance_id()
	var revision := navigator.nav_revision
	var picked := office.picked_key
	var chips := office.hud.bar.chips().map(func(chip: MachineChip) -> int: return chip.get_instance_id())
	var hive := HerdrFleet.pane_key(BEE, "hive")
	var at := office.hud.bar.chip_for(BEE).get_global_rect().get_center()
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
	_eq(
		office.hud.bar.chips().map(func(chip: MachineChip) -> int: return chip.get_instance_id()),
		chips,
		"the chips are what they were"
	)
	await _frames(2)
	_check(_zone_in_view(office, hive), "and bee's zone is on screen")
	_done(office)


## A machine that never connected has no zone, so neither the page keys nor a
## card reach it: its chip is the way to it. A real click opens its map,
## empty, with the note saying why.
func test_a_chip_click_opens_a_never_connected_machine_as_an_empty_map_with_its_note() -> void:
	var office := await _far_office()
	await _frames(2)
	_eq(office.hud.bar.chips().size(), 2, "a chip per machine")
	_eq(office.frame.building_of(FAR).zones.size(), 0, "far never connected: no zone")
	_check(
		office.frame.zone_order.all(func(key: String) -> bool: return key.begins_with(LOCAL)),
		"so none of its own in the page keys' order"
	)
	var revision := office.navigator.nav_revision
	await _click_heading(office, FAR)
	_eq(office.navigator.shown_key, FAR, "a click on its chip shows its map")
	_eq(office.navigator.nav_revision, revision + 1, "one navigation")
	_eq(office.layout_plan().desks.size(), 0, "an empty map: no desk")
	_eq(office.floor_view.seats.size(), 0, "nobody seated")
	_eq(office.plate.title_text(), "@ FAR", "its plate names it")
	_check(not office.plate.note_text().is_empty(), "with a note saying why it is empty: " + office.plate.note_text())
	_check(office.plate.state_text() != "LIVE", "and that it is not answering: " + office.plate.state_text())
	_check(not office.hud.edge_arrows.visible, "and no arrows")
	await _click_heading(office, LOCAL)
	_eq(office.navigator.shown_key, LOCAL, "Local's chip goes back")
	_done(office)


## The chip of the machine whose map is shown is the current one, alone; a
## chip click moves it with the map, and so does a card's place on another
## machine; Local alone has no chip at all.
func test_the_chip_of_the_shown_machine_is_current_alone() -> void:
	var office := await _two_machine_office()
	await _frames(2)
	var bar := office.hud.bar
	_eq(_current_chips(office), [LOCAL], "Local's map is shown: its chip is the current one, alone")
	_eq(bar.chip_for(LOCAL).theme_type_variation, &"MachineChipCurrent", "by the theme's look")
	_eq(bar.chip_for(BEE).theme_type_variation, &"MachineChip", "the other plain")
	await _click_heading(office, BEE)
	_eq(_current_chips(office), [BEE], "bee's map is shown: bee's chip, alone")
	# A zone of Local's picked from bee's map takes the current back with the map.
	await _click_place(office, _pane("hud:p1"))
	_eq(_current_chips(office), [LOCAL], "a card's place on Local shows Local's map: Local's chip again")
	_done(office)
	var alone := await _live_office()
	_eq(alone.hud.bar.chips().size(), 0, "Local alone: no chip")
	_done(alone)


## A chip click wins over herdr's focus moving in a snapshot that arrived but
## is not drawn yet: a real press on bee's chip, the snapshot, the release.
## The release's own refresh takes that snapshot in, and bee's map is the one
## shown, not the map the focus moved on; the selection is herdr's new focus
## all the same, and the next move of the focus is followed as ever.
func test_a_chip_click_wins_over_a_focus_move_not_drawn_yet() -> void:
	var office := await _two_machine_office()
	await _frames(2)
	var navigator := office.navigator
	var at := office.hud.bar.chip_for(BEE).get_global_rect().get_center()
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
	_eq(navigator.nav_revision, revision + 1, "one navigation: the chip")
	_feed(office, _focused_on(fixture, "ops:p1"))
	await _frames(3)
	_eq(navigator.shown_key, LOCAL, "the next move of the focus is followed again: Local's map")
	_check(_desk_in_view(office, _pane("ops:p1")), "its desk panned into the world's room")
	_done(office)


## Four machines in the 480x320 window, which has no titles: a narrow chip
## each, the shown machine's current; together they stay inside the bar,
## between the wordmark and the strip, and leave the strip its room (the
## ladder fits it). From the titles' width on, each chip is wide again.
func test_machine_chips_go_narrow_below_titles_and_stay_inside_the_bar() -> void:
	var office := await _four_machine_office(Vector2(480, 320))
	var bar := office.hud.bar
	var clip: Control = bar.get_node("%Machines")
	var strip: Control = bar.get_node("%Strip")
	var wordmark: Control = bar.get_node("%Wordmark")
	var row: Control = bar.get_node("%Row")
	_eq(
		bar.chips().map(func(chip: MachineChip) -> String: return chip.key),
		[LOCAL, BEE, FAR, "socket:gone"],
		"a chip per machine, in the fleet's order"
	)
	_eq(_current_chips(office), [LOCAL], "Local's the current one")
	for step: Array in [[Vector2(480, 320), 20.0], [Vector2(800, 480), 40.0]]:
		var screen: Vector2 = step[0]
		if office.test_screen != screen:
			office.test_screen = screen
			office.refresh()
			await _frames(3)
		for chip in bar.chips():
			_eq(chip.size.x, step[1], "%s: %s's chip is %d wide" % [screen, chip.key, step[1]])
			_check(
				clip.get_global_rect().encloses(chip.get_global_rect()), "%s: %s's chip is whole" % [screen, chip.key]
			)
			var tip := chip.get_tooltip(Vector2.ZERO)
			_check(
				tip.begins_with(office.fleet.label(chip.key) + " · "),
				"%s: its tooltip names it whole: %s" % [screen, tip]
			)
		var cut := clip.get_global_rect()
		_check(row.get_global_rect().encloses(cut), "%s: inside the bar's row" % screen)
		_check(wordmark.get_global_rect().end.x <= cut.position.x, "%s: after the wordmark" % screen)
		_check(cut.end.x <= strip.get_global_rect().position.x, "%s: before the strip" % screen)
		_check(bar.fitted().needed <= strip.size.x, "%s: the strip's rung fits what is left" % screen)
	_done(office)


## A HUD line about a pane on another machine (a row of the EVENTS page here)
## outlines that pane's portrait card, as it once outlined the zone's SPACES
## row; one about a pane on the shown map frames its desk instead; a pane
## folded into a fold has no card, and nothing is outlined. Only points.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the lines were the agent list's rows; they are
## the EVENTS page's now, each pane given a fresh wait (a live idle then blocked) so it has a row.
func test_pointing_at_another_machines_pane_outlines_its_card() -> void:
	var office := await _two_machine_office()
	var bar := office.hud.bar
	var hive := HerdrFleet.pane_key(BEE, "hive:p1")
	_feed(office, _with(fixture, "hud:p1", {"agent_status": "idle"}))
	_feed(office, fixture)
	_bee_live(office, _bee_snapshot("idle"))
	_bee_live(office, _bee_snapshot("blocked"))
	await _frames(2)
	await _click_tab(office, OfficeBottomPanel.Page.EVENTS)
	var pointer := office.floor_view.pointer
	var picked := office.picked_key
	var hive_row := _event_row(office, hive)
	var hud_row := _event_row(office, _pane("hud:p1"))
	_check(hive_row != null and hive_row.is_visible_in_tree(), "hive:p1 has a row on the EVENTS page")
	_check(hud_row != null and hud_row.is_visible_in_tree(), "and hud:p1")
	if hive_row == null or hud_row == null:
		_done(office)
		return
	await _pointer_to(hive_row.get_global_rect().get_center())
	_eq(_pointed_cards(office), [hive], "bee's blocked agent: its card is outlined, alone")
	_check(not pointer.visible, "and no desk on Local's map is framed")
	var ring: Panel = bar.card_for(hive).get_node("%Pointed")
	_check(ring.visible, "by its ring")
	_eq(ring.theme_type_variation, &"PortraitPointed", "in the theme's look")
	await _pointer_to(hud_row.get_global_rect().get_center())
	_eq(_pointed_cards(office), [], "a line about a pane on the shown map outlines no card")
	_eq([pointer.key, pointer.visible], [_pane("hud:p1"), true], "it frames the desk")
	await _pointer_to(office.hud.world_rect().get_center())
	_eq(_pointed_cards(office), [], "off the rows: nothing outlined")
	_bee_live(office, _bee_snapshot("working"))
	await _frames(2)
	_check(bar.card_for(hive) == null, "bee's agent at work is in the working fold")
	hive_row = _event_row(office, hive)
	_check(hive_row != null and hive_row.is_visible_in_tree(), "its newest event has a row")
	if hive_row == null:
		_done(office)
		return
	await _pointer_to(hive_row.get_global_rect().get_center())
	_eq(_pointed_cards(office), [], "pointed at, it has no card to outline")
	_eq(office.picked_key, picked, "and nothing was picked")
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
		# The page keys pan the sign's aisle row to the top of the world; the
		# pointer waits on the top bar meanwhile, where a SPACES row's click left it.
		await _pointer_to(office.hud.placed(office.hud.bar).get_center())
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


## A zone whose panes are all shells has no portrait card (the bar shows
## agents) and no blocked desk (no edge arrow): the mouse reaches it through
## the OVERVIEW, which rows every pane, shells too. A real click on `13 panes`,
## then on the shell's row: the shell is picked, its zone is the current one,
## and its desk is on screen once the OVERVIEW closes. Nothing is read or
## written (BAR-b's Q3b, ruled D-SHELLZONE by S3 PANEL-a1, 2026-10-27).
func test_a_zone_of_shells_is_reached_through_the_overview() -> void:
	var raw: Dictionary = fixture.duplicate(true)
	_list(raw, "workspaces").append(
		{"workspace_id": "lab", "number": 6, "label": "lab", "pane_count": 2, "tab_count": 1}
	)
	_list(raw, "tabs").append({"tab_id": "lab:t1", "workspace_id": "lab", "number": 1, "label": "main"})
	for index in 2:
		var pane_id := "lab:p%d" % (index + 1)
		_list(raw, "panes").append(
			{
				"pane_id": pane_id,
				"terminal_id": "term-" + pane_id,
				"workspace_id": "lab",
				"tab_id": "lab:t1",
				"cwd": "/home/tester/lab",
				"agent_status": "idle"
			}
		)
	var office := await _live_office(raw)
	await _frames(2)
	var shell := _pane("lab:p2")
	_check(office.frame.pane(shell) != null and office.frame.pane(shell).provider.is_empty(), "lab:p2 is a shell")
	_check(office.hud.bar.card_for(shell) == null, "with no portrait card")
	_check(not office.navigator.current_zone(office.frame) == _zone("lab"), "lab is not the current zone")
	var panes: Button = office.hud.bar.get_node("%Panes")
	await _click_at(panes.get_global_rect().get_center())
	await _frames(2)
	_check(office.hud.overview_open(), "`13 panes` opens the OVERVIEW")
	var line := office.hud.overview.line_for(shell)
	_check(line != null, "which rows the shell")
	if line == null:
		_done(office)
		return
	var scroll: ScrollContainer = office.hud.overview.get_node("%Scroll")
	scroll.ensure_control_visible(line)
	await _frames(2)
	await _click_at(line.get_global_rect().get_center())
	await _frames(3)
	_eq(office.picked_key, shell, "a click on its row picks the shell")
	_eq(office.navigator.current_zone(office.frame), _zone("lab"), "its zone is the current one")
	await _office_key(office, KEY_O)
	await _frames(3)
	_check(not office.hud.overview_open(), "O closes the OVERVIEW")
	_check(_desk_in_view(office, shell), "and the shell's desk is on screen")
	_check(office.fleet.read_log().is_empty(), "nothing was read")
	_check(office.fleet.write_log().is_empty(), "nothing was written")
	_done(office)


# --- helpers --------------------------------------------------------------------


func _zone(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _node(holder: Node, path: String) -> Control:
	return holder.get_node(path)


## Every zone's number as its sign writes it, in the page keys' order.
func _chips(office: OfficeDouble) -> Array:
	return office.frame.zone_order.map(
		func(key: String) -> String: return OfficeZoneSign.number_text(office.frame.find_zone(key).zone_model)
	)


## The machines whose chip is the current one.
func _current_chips(office: OfficeDouble) -> Array:
	return (
		office
		. hud
		. bar
		. chips()
		. filter(func(chip: MachineChip) -> bool: return chip.is_current())
		. map(func(chip: MachineChip) -> String: return chip.key)
	)


## The panes whose portrait cards are outlined as pointed at.
func _pointed_cards(office: OfficeDouble) -> Array:
	return (
		office
		. hud
		. bar
		. cards()
		. filter(func(card: PortraitCard) -> bool: return card.pointed())
		. map(func(card: PortraitCard) -> String: return card.key)
	)


## A real click on the place of pane `pane_key`'s portrait card.
func _click_place(office: OfficeDouble, pane_key: String) -> void:
	var card := office.hud.bar.card_for(pane_key)
	if card == null:
		_fail("no portrait card for " + pane_key)
		return
	var place: Button = card.get_node("%PlaceButton")
	await _click_at(place.get_global_rect().get_center())


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


## Local and bee, live, and `far` and `gone`, two machines on sockets nobody
## listens on, which never connect.
func _four_machine_office(screen: Vector2) -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = screen
	office.test_args = (
		AppArgs
		. parse(
			PackedStringArray(
				[
					"--read-only",
					"--socket=" + args.socket,
					"--machine-socket=bee=" + args.work.path_join("bee-nowhere.sock"),
					"--machine-socket=far=" + args.work.path_join("far-nowhere.sock"),
					"--machine-socket=gone=" + args.work.path_join("gone-nowhere.sock"),
				]
			)
		)
	)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	office.fleet._sites[2].client.stop()
	office.fleet._sites[3].client.stop()
	_feed(office, fixture)
	_feed_bee(office, _bee_snapshot("blocked"))
	await _frames(2)
	return office


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
