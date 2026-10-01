extends "res://tools/test_base.gd"
## OfficeNavigator and OfficeFrame as pure objects: which desk is selected,
## which machine's map is shown and where it pans, decided from frames made straight from the fixture
## snapshots, and the command line the office starts from. No office, no scene,
## no herdr. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_office_navigator.gd

const LOCAL := HerdrFleet.LOCAL
const BEE := "socket:bee"

## tools/fixtures/snapshot_floors.json, which Local serves: focus on api:p1,
## blocked agents on web and infra, UNREAD ones on web and infra.
var floors: Dictionary = {}
## tools/fixtures/snapshot_basic.json, which bee serves: a blocked pi on bravo.
var basic: Dictionary = {}


func _initialize() -> void:
	floors = _fixture("snapshot_floors")
	basic = _fixture("snapshot_basic")
	if floors.is_empty() or basic.is_empty():
		print("TEST_HARNESS_ERROR: cannot read the office fixtures")
		quit(2)
		return
	run_cases()


func _marker() -> String:
	return "OFFICE NAVIGATOR TESTS"


func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/%s.json" % name))
	if parsed is not Dictionary:
		return {}
	var file: Dictionary = parsed
	return _dict(file, "snapshot")


## Local serving `local`, and bee serving `bee` when there is one.
func _frame(local: Dictionary, bee: Dictionary = {}, bee_stale := false) -> OfficeFrame:
	var machines: Array[MachineView] = [MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(local), false)]
	if not bee.is_empty():
		machines.append(MachineView.new(BEE, "bee", HerdrSnapshot.from_wire(bee), bee_stale))
	return OfficeProjection.frame(machines, PackedStringArray(["working", "blocked", "done", "idle", "unknown"]))


func _local(id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, id)


func _bee(id: String) -> String:
	return HerdrFleet.pane_key(BEE, id)


## `raw` with one pane's fields changed.
func _with(raw: Dictionary, pane_id: String, changes: Dictionary) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	for pane: Dictionary in _list(result, "panes"):
		if str(pane.get("pane_id", "")) == pane_id:
			pane.merge(changes, true)
	return result


## `raw` without one workspace, so the zone it was goes away.
func _without(raw: Dictionary, workspace_id: String) -> Dictionary:
	var result: Dictionary = raw.duplicate(true)
	result.workspaces = _list(result, "workspaces").filter(
		func(space: Dictionary) -> bool: return str(space.get("workspace_id", "")) != workspace_id
	)
	return result


## A navigator showing zone `key` of `frame` (picked, its machine's map shown,
## the pans asked for taken), as the office leaves one after a refresh.
func _showing(frame: OfficeFrame, key: String) -> OfficeNavigator:
	var navigator := OfficeNavigator.new()
	navigator.settle(frame)
	navigator.pick_zone(key)
	_show(navigator, frame)
	return navigator


## One refresh's navigation, as the office does it: settle, show the machine
## it answers, take the pans; the machine shown.
func _show(navigator: OfficeNavigator, frame: OfficeFrame, pan := Vector2.ZERO) -> String:
	var wanted := navigator.settle(frame)
	if wanted != navigator.shown_key:
		navigator.show_machine(frame, wanted, pan)
	navigator.take_pan_to()
	navigator.take_pan_zone()
	return wanted


# --- the frame ----------------------------------------------------------------


## One projection answers every lookup a refresh makes: each pane once by key,
## the zone it sits in, every machine's map, the zones in the rail's order
## (what PageUp/PageDown step through), the live panes and herdr's focus,
## Local's first. A dropped machine's panes are not live, but the inspector
## still knows them.
func test_the_frame_indexes_one_projection() -> void:
	var frame := _frame(floors, basic)
	_eq(
		frame.buildings.map(func(building: BuildingModel) -> String: return building.key),
		[LOCAL, BEE],
		"one building per machine, Local first"
	)
	_eq(frame.pane_by_key.size(), 17, "every pane of both machines, by key")
	_eq(frame.pane(_local("web:p1")).workspace_label, "web", "each with its workspace's label")
	_eq(frame.pane(_local("web:p1")).tab_label, "ui", "and its tab's")
	_eq(frame.zone_of(_local("infra:p2")), _local("infra"), "the zone a desk sits in")
	_eq(frame.zone_of(_bee("bravo:p1")), _bee("bravo"), "on either machine")
	_eq(
		frame.zone_order,
		[_local("api"), _local("web"), _local("infra"), _local("notes"), _local("data"), _bee("alpha"), _bee("bravo")],
		"five Local zones and bee's two, as the rail draws them: ascending, Local first"
	)
	var map := frame.map_of(LOCAL)
	_eq([map.key, map.zones.size()], [LOCAL, 5], "one map per machine, under the machine's key, with every zone")
	_eq(frame.map_of(BEE).key, BEE, "bee's own")
	_eq(frame.map_of("nobody"), null, "no map for a machine the frame does not have")
	_eq(frame.herdr_focus, _local("api:p1"), "Local's focus first")
	_eq(frame.live_panes.size(), 17, "both machines are live")
	_check(frame.several_machines() and not _frame(floors).several_machines(), "several machines only past Local")
	var dropped := _frame(floors, basic, true)
	_eq(dropped.live_panes.size(), 13, "a dropped machine's panes are not live")
	_check(dropped.pane(_bee("bravo:p1")) != null, "but the inspector still knows them")


## The buildings-only lookups OfficeProjection keeps are the frame's own answers.
func test_the_projection_lookups_are_the_frames() -> void:
	var frame := _frame(floors, basic)
	var buildings := frame.buildings
	for key: String in [_local("web:p1"), _bee("alpha:p1"), _local("nobody"), ""]:
		_eq(OfficeProjection.zone_of(buildings, key), frame.zone_of(key), "zone_of %s" % key)
	_eq(OfficeProjection.zone_order(buildings), frame.zone_order, "zone_order")
	_eq(
		OfficeProjection.find_zone(buildings, _bee("bravo")).building.key,
		frame.find_zone(_bee("bravo")).building.key,
		"find_zone"
	)
	for picked: String in ["", LOCAL, BEE, "gone"]:
		_eq(
			OfficeProjection.choose_machine(buildings, picked, _bee("bravo:p1")),
			frame.choose_machine(picked, _bee("bravo:p1")),
			"choose_machine from %s" % picked
		)
	_eq(
		OfficeProjection.effective_selection(buildings, _bee("alpha:p2"), frame.herdr_focus),
		frame.effective_selection(_bee("alpha:p2")),
		"effective_selection"
	)


## The machine shown: the one picked, else the selection's, else the first
## with a zone, else the first; a machine without workspaces has an empty map.
func test_the_machine_shown_is_the_picked_then_the_selections_then_the_first_with_a_zone() -> void:
	var frame := _frame(floors, basic)
	_eq(frame.choose_machine(BEE, _local("api:p1")), BEE, "the picked machine wins")
	_eq(frame.choose_machine("", _bee("bravo:p1")), BEE, "else the selection's")
	_eq(frame.choose_machine("gone", _local("api:p1")), LOCAL, "a picked machine that is gone is not")
	_eq(frame.choose_machine("", ""), LOCAL, "else the first with a zone")
	var empty_local := _frame({}, basic)
	_eq(empty_local.map_of(LOCAL).zones.size(), 0, "a machine without workspaces is an empty map")
	_eq(empty_local.map_of(LOCAL).key, LOCAL, "still its own")
	_eq(empty_local.choose_machine("", ""), BEE, "nothing selected: the first machine with a zone")
	_eq(_frame({}).choose_machine("", ""), LOCAL, "nothing anywhere: the first machine, its empty map")


# --- the selection and the map ------------------------------------------------


## Herdr's focus is followed until the viewer picks a desk. A picked desk pulls
## its machine's map into view; once it is gone the selection goes back to the focus.
func test_the_selection_follows_focus_until_a_desk_is_picked() -> void:
	var navigator := OfficeNavigator.new()
	var frame := _frame(floors, basic)
	_eq(navigator.settle(frame), LOCAL, "herdr's focus is on api, Local's")
	_eq(navigator.active_key, _local("api:p1"), "and is the selection")
	navigator.pick_desk(_bee("bravo:p1"))
	_eq(navigator.settle(frame), BEE, "a picked desk pulls its machine's map into view")
	_eq(navigator.active_key, _bee("bravo:p1"), "and is selected")
	var gone: Dictionary = basic.duplicate(true)
	gone.panes = _list(gone, "panes").filter(
		func(pane: Dictionary) -> bool: return str(pane.get("pane_id", "")) != "bravo:p1"
	)
	_eq(navigator.settle(_frame(floors, gone)), LOCAL, "once it is gone, herdr's focus wins again")
	_eq(navigator.active_key, _local("api:p1"), "and is selected")
	_eq(navigator.picked_key, _bee("bravo:p1"), "while the pick itself is remembered")


## A pane herdr knows but no zone can seat stays selected when picked: the
## inspector keeps its details, and the map shown is the first machine's with a zone.
func test_an_unplaced_pick_stays_selected() -> void:
	var frame := _frame(_with(floors, "notes:p1", {"workspace_id": "web"}))
	_eq(frame.zone_of(_local("notes:p1")), "", "the pane claims a workspace its tab is not in")
	var navigator := OfficeNavigator.new()
	navigator.pick_desk(_local("notes:p1"))
	_eq(navigator.settle(frame), LOCAL, "its zone is unknown, so the first machine's map is shown")
	_eq(navigator.active_key, _local("notes:p1"), "but it stays the selection")


## A zone the viewer picked shows its machine's map, which wins over the
## selection's until that machine goes away; a zone that goes away is
## forgotten (the map stays), not waited for.
func test_a_picked_zone_shows_its_machine_until_it_goes_away() -> void:
	var navigator := OfficeNavigator.new()
	navigator.pick_zone(_bee("alpha"))
	_eq(navigator.settle(_frame(floors, basic)), BEE, "the picked zone's machine is shown")
	_eq(navigator.current_zone(_frame(floors, basic)), "", "not yet: nothing is shown")
	navigator.show_machine(_frame(floors, basic), BEE, Vector2.ZERO)
	_eq(navigator.current_zone(_frame(floors, basic)), _bee("alpha"), "then it is the current zone")
	_eq(navigator.settle(_frame(floors, _without(basic, "alpha"))), BEE, "its zone gone, the map stays")
	_eq(navigator.current_zone(_frame(floors, basic)), "", "and the zone is forgotten, not waited for")
	_eq(navigator.settle(_frame(floors)), LOCAL, "the machine gone, the selection's machine is shown")
	_eq(navigator.picked_machine, "", "and the pick is forgotten")
	_eq(navigator.settle(_frame(floors, basic)), LOCAL, "so it does not come back with the machine")


## `--space=<number>` names a Local zone by herdr's number, which only means
## something once Local has workspaces; it is picked then, once, like a FLOORS
## row, and it counts as no navigation (the viewer did not move).
func test_a_floor_number_waits_for_local() -> void:
	var navigator := OfficeNavigator.new()
	navigator.wanted_space = AppArgs.parse(PackedStringArray(["--space=3"])).number("space", -1)
	_eq(navigator.settle(_frame({})), LOCAL, "before Local has workspaces, its empty map")
	_eq(navigator.wanted_space, 3, "and the number waits")
	_eq(navigator.settle(_frame(floors)), LOCAL, "Local once it has the third zone")
	_eq([navigator.pan_zone, navigator.nav_revision], [_local("infra"), 0], "panned to, counting no navigation")
	_eq(navigator.wanted_space, -1, "and only once")
	navigator.pick_zone(_local("web"))
	_eq(navigator.pan_zone, _local("web"), "a later pick is the viewer's own")
	_eq(AppArgs.parse(PackedStringArray(["--floor=3"])).number("space", -1), -1, "`--floor` is no alias")


# --- moving between zones and machines ----------------------------------------


## A zone the viewer picks on the machine shown only pans: the map stays, a
## one-shot pan to that zone is asked for, and it counts one navigation. A zone
## on another machine switches maps. A newer pick simply wins.
func test_a_zone_on_the_shown_machine_pans_and_another_machine_switches() -> void:
	var frame := _frame(floors, basic)
	var navigator := OfficeNavigator.new()
	_eq(_show(navigator, frame), LOCAL, "the selection's machine first")
	var revision := navigator.nav_revision
	navigator.pick_zone(_local("web"))
	_eq([navigator.settle(frame), navigator.shown_key], [LOCAL, LOCAL], "a zone on this machine keeps the map")
	_eq([navigator.pan_zone, navigator.nav_revision], [_local("web"), revision + 1], "pans to it, one navigation")
	_eq(navigator.take_pan_zone(), _local("web"), "taken once")
	_eq(navigator.take_pan_zone(), "", "then forgotten")
	_eq(navigator.current_zone(frame), _local("web"), "it is the current zone")
	navigator.pick_zone(_bee("bravo"))
	_eq(navigator.settle(frame), BEE, "a zone on another machine switches maps")
	navigator.pick_zone(_local("notes"))
	_eq(navigator.settle(frame), LOCAL, "and a newer pick wins at once")
	_eq(navigator.pan_zone, _local("notes"), "panning to that one")


## PageUp (-1) and PageDown (+1) walk every zone as the rail draws them, from
## the current one, from a machine's last zone into the next machine's first,
## and stop at either end, where they pick and count nothing. (The SPACES rail
## is ascending, so PageUp goes to the lower number and PageDown to the higher,
## the other way round from the FLOORS minimap, which drew the highest on top;
## across machines Local's last zone leads down into bee's first.)
func test_page_up_and_down_walk_the_buildings_and_stop_at_the_ends() -> void:
	var frame := _frame(floors, basic)
	var navigator := _showing(frame, _local("data"))
	_eq(navigator.next_zone(frame, 1), _bee("alpha"), "Local's last zone leads into bee's first")
	_eq(navigator.next_zone(frame, -1), _local("notes"), "one up, the lower number")
	var revision := navigator.nav_revision
	_check(navigator.step_zone(frame, 1), "PageDown crosses machines")
	_eq([_show(navigator, frame), navigator.current_zone(frame)], [BEE, _bee("alpha")], "onto bee's map")
	_check(navigator.step_zone(frame, 1), "and on down")
	_eq(_show(navigator, frame), BEE, "")
	_eq(navigator.next_zone(frame, 1), "", "nothing below the bottom")
	_check(not navigator.step_zone(frame, 1), "PageDown at the bottom")
	_eq(
		[navigator.current_zone(frame), navigator.nav_revision],
		[_bee("bravo"), revision + 2],
		"picks and counts nothing"
	)
	_check(navigator.step_zone(frame, -1) and navigator.step_zone(frame, -1), "back up across")
	_eq([_show(navigator, frame), navigator.current_zone(frame)], [LOCAL, _local("data")], "onto Local's last")
	navigator = _showing(frame, _local("api"))
	_eq(navigator.next_zone(frame, -1), "", "nothing above the top")
	_check(not navigator.step_zone(frame, -1), "PageUp at the top does nothing")


## A machine's section of the rail draws its zones ascending and hangs each
## worktree's mezzanines right after the zone they were made from, in letter
## order (OfficeNavigator.section()); PageUp/PageDown follow that same picture.
func test_steps_follow_the_section_with_its_mezzanines() -> void:
	var worktrees := _fixture("snapshot_worktrees")
	var frame := _frame(worktrees, basic)
	_eq(
		OfficeNavigator.section(frame.building_of(LOCAL).zones).map(func(zone: ZoneModel) -> String: return zone.key),
		[_local("hs"), _local("hud"), _local("data"), _local("notes"), _local("ops")],
		"1, its mezzanines 1A and 1B, then 4 and the orphan worktree 5"
	)
	var navigator := _showing(frame, _local("hs"))
	_eq(navigator.next_zone(frame, 1), _local("hud"), "down from a source zone into its first mezzanine")
	_eq(navigator.next_zone(frame, -1), "", "the source is Local's first row: nothing above it")
	navigator = _showing(frame, _local("data"))
	_eq(navigator.next_zone(frame, 1), _local("notes"), "past its last mezzanine, the next zone by number")
	_eq(navigator.next_zone(frame, -1), _local("hud"), "up the mezzanines")
	navigator = _showing(frame, _local("hud"))
	_eq(navigator.next_zone(frame, -1), _local("hs"), "back to their source")
	navigator = _showing(frame, _local("ops"))
	_eq(navigator.next_zone(frame, 1), _bee("alpha"), "Local's last zone leads into bee's first")


## Each machine's map keeps where the viewer left it panned; a map seen for the
## first time opens on the selection's pod instead; a machine that goes away
## forgets. A workspace going away takes no pan with it: its map stays.
func test_each_floor_keeps_its_pan_until_it_goes_away() -> void:
	var frame := _frame(floors, basic)
	var navigator := OfficeNavigator.new()
	_show(navigator, frame)
	navigator.pick_zone(_bee("alpha"))
	_eq(_show(navigator, frame, Vector2(10, 20)), BEE, "bee's map, leaving Local's panned at (10, 20)")
	_eq(navigator.pan_of(LOCAL), Vector2(10, 20), "Local is where it was left")
	navigator.pick_zone(_local("web"))
	_eq(_show(navigator, frame, Vector2(30, 40)), LOCAL, "back on Local")
	_eq(navigator.pan_of(BEE), Vector2(30, 40), "bee remembers its own")
	navigator.pick_zone(_local("api"))
	_eq(_show(navigator, _frame(_without(floors, "web"), basic)), LOCAL, "a zone of Local's going away")
	_eq(navigator.pan_of(BEE), Vector2(30, 40), "takes no pan with it")
	_show(navigator, _frame(floors))
	_eq(navigator.pan_of(BEE), Vector2.ZERO, "the machine going away does")


## First arrival at a map in this run: the selection's whole pod when the
## selection is seated there, else the first zone as the rail draws them; a
## zone the viewer picked there wins; a map shown before asks nothing.
func test_a_first_arrival_opens_on_the_selections_pod_else_the_first_zone() -> void:
	var frame := _frame(floors, basic)
	var navigator := OfficeNavigator.new()
	navigator.settle(frame)
	navigator.show_machine(frame, LOCAL, Vector2.ZERO)
	_eq([navigator.pan_to, navigator.pan_whole_table, navigator.pan_zone], [_local("api:p1"), true, ""], "the pod")
	navigator.take_pan_to()
	navigator.pick_desk(_local("web:p1"))
	navigator.settle(frame)
	navigator.show_machine(frame, BEE, Vector2.ZERO)
	_eq([navigator.pan_to, navigator.pan_zone], ["", _bee("alpha")], "a map without the selection: its first zone")
	navigator.take_pan_zone()
	navigator.pick_zone(_local("infra"))
	navigator.show_machine(frame, LOCAL, Vector2.ZERO)
	_eq([navigator.pan_to, navigator.pan_zone], ["", _local("infra")], "a map shown before: the zone picked")
	var fresh := OfficeNavigator.new()
	fresh.settle(frame)
	fresh.pick_zone(_bee("alpha"))
	fresh.show_machine(frame, BEE, Vector2.ZERO)
	_eq([fresh.pan_to, fresh.pan_zone], ["", _bee("alpha")], "a first arrival for a zone picked there opens on it")
	# A map first shown empty (a machine before its first snapshot) opens when
	# its first zone arrives.
	var late := OfficeNavigator.new()
	late.settle(_frame({}))
	late.show_machine(_frame({}), LOCAL, Vector2.ZERO)
	_eq([late.pan_to, late.pan_zone], ["", ""], "an empty map opens on nothing")
	late.settle(_frame(floors))
	_eq([late.pan_to, late.pan_whole_table], [_local("api:p1"), true], "its zones arriving open it: the pod")
	late.take_pan_to()
	late.settle(_frame(floors))
	_eq([late.pan_to, late.pan_zone], ["", ""], "once")


## Herdr's focus moving is revealed while nothing is picked: a pan to the new
## desk as far as it takes (not its whole pod), only when it moved, never
## counted; on another machine it switches maps. A settle where it did not move
## asks nothing, so the viewer's own pan stays; a pick stops it.
func test_herdr_focus_moving_is_revealed_only_when_it_moves() -> void:
	var frame := _frame(floors, basic)
	var navigator := OfficeNavigator.new()
	_show(navigator, frame)
	var revision := navigator.nav_revision
	_eq(navigator.settle(frame), LOCAL, "")
	_eq(navigator.pan_to, "", "focus where it was: nothing asked")
	var moved := frame
	moved.herdr_focus = _local("web:p1")
	_eq(navigator.settle(moved), LOCAL, "focus on another zone of the map: the same map")
	_eq([navigator.pan_to, navigator.pan_whole_table], [_local("web:p1"), false], "revealed as far as it takes")
	_eq(navigator.nav_revision, revision, "never counted")
	navigator.take_pan_to()
	navigator.settle(moved)
	_eq(navigator.pan_to, "", "the next settle, focus unmoved, asks nothing: a pan the viewer makes stays")
	var away := _frame(floors, basic)
	away.herdr_focus = _bee("bravo:p1")
	_eq(navigator.settle(away), BEE, "focus on another machine switches maps")
	_eq([navigator.pan_to, navigator.pan_whole_table], [_bee("bravo:p1"), false], "and reveals it on arrival")
	navigator.show_machine(away, BEE, Vector2.ZERO)
	_eq([navigator.pan_to, navigator.pan_whole_table], [_bee("bravo:p1"), true], "a first arrival: its whole pod")
	_eq(navigator.nav_revision, revision, "still nothing counted")
	navigator.take_pan_to()
	navigator.pick_desk(_bee("alpha:p1"))
	var back := _frame(floors, basic)
	back.herdr_focus = _local("infra:p1")
	_eq(navigator.settle(back), BEE, "with a desk picked, herdr's focus moving moves nothing")
	_eq(navigator.pan_to, "", "and asks nothing")


## A pick stops the follow only while its pane is on the frame. Once that pane
## is gone the selection is herdr's focus again, where it was (the pane going
## is not the focus moving: nothing is asked, the machine chosen stays), and
## from then on its moves are revealed as if nothing were picked: each one, on
## this machine or another, never counted; one that comes with the pane's going
## too. An explicit navigation still wins over it. The pick itself is
## remembered: the pane back, it is the selection again and the focus moves
## nothing.
func test_a_pick_whose_pane_is_gone_lets_the_focus_be_followed_until_it_is_back() -> void:
	var navigator := OfficeNavigator.new()
	_show(navigator, _frame(floors, basic))
	navigator.pick_desk(_local("web:p1"))
	_show(navigator, _frame(floors, basic))
	_eq(navigator.active_key, _local("web:p1"), "the picked desk is the selection")
	var revision := navigator.nav_revision
	var closed: Dictionary = floors.duplicate(true)
	closed.panes = _list(closed, "panes").filter(
		func(pane: Dictionary) -> bool: return str(pane.get("pane_id", "")) != "web:p1"
	)
	var gone := _frame(closed, basic)
	_eq(navigator.settle(gone), LOCAL, "its pane gone: the same map")
	_eq(navigator.active_key, _local("api:p1"), "the selection is herdr's focus again")
	_eq(navigator.picked_key, _local("web:p1"), "while the pick itself is remembered")
	_eq([navigator.pan_to, navigator.picked_machine], ["", ""], "the focus did not move: nothing asked or chosen")
	var moved := _frame(closed, basic)
	moved.herdr_focus = _local("infra:p1")
	_eq(navigator.settle(moved), LOCAL, "herdr's focus moves to another zone of the map")
	_eq([navigator.pan_to, navigator.pan_whole_table], [_local("infra:p1"), false], "revealed as far as it takes")
	navigator.take_pan_to()
	navigator.settle(moved)
	_eq(navigator.pan_to, "", "the next settle, focus unmoved, asks nothing")
	var again := _frame(closed, basic)
	again.herdr_focus = _local("data:p1")
	navigator.settle(again)
	_eq(navigator.pan_to, _local("data:p1"), "a later move is revealed too")
	var away := _frame(closed, basic)
	away.herdr_focus = _bee("bravo:p1")
	_eq(navigator.settle(away), BEE, "and one onto another machine switches maps")
	_eq(navigator.pan_to, _bee("bravo:p1"), "revealing it there")
	_eq(navigator.nav_revision, revision, "none of them counted")
	_show(navigator, away)
	navigator.pick_zone(_local("notes"))
	var asked := _frame(closed, basic)
	asked.herdr_focus = _local("api:p2")
	_eq(navigator.settle(asked), LOCAL, "a zone the viewer picks as the focus moves")
	_eq([navigator.pan_zone, navigator.pan_to], [_local("notes"), ""], "wins over the focus")
	_show(navigator, asked)
	var back := _frame(floors, basic)
	back.herdr_focus = _local("infra:p1")
	_eq(navigator.settle(back), LOCAL, "the picked pane is back")
	_eq(navigator.active_key, _local("web:p1"), "and is the selection again")
	_eq(navigator.pan_to, "", "herdr's focus moving moves nothing")
	# The pane goes as the focus moves, in one snapshot: that move is revealed.
	var both := _frame(closed, basic)
	both.herdr_focus = _local("data:p1")
	navigator.settle(both)
	_eq([navigator.active_key, navigator.pan_to], [_local("data:p1"), _local("data:p1")], "gone as the focus moves")
	navigator.take_pan_to()
	# A machine the viewer chose stays shown when the pane picked on it goes.
	navigator.pick_zone(_bee("alpha"))
	_show(navigator, both)
	navigator.pick_desk(_bee("bravo:p1"))
	_show(navigator, both)
	var shut: Dictionary = basic.duplicate(true)
	shut.panes = _list(shut, "panes").filter(
		func(pane: Dictionary) -> bool: return str(pane.get("pane_id", "")) != "bravo:p1"
	)
	var left := _frame(closed, shut)
	left.herdr_focus = both.herdr_focus
	_eq(navigator.settle(left), BEE, "the pane picked on bee's map gone: the map the viewer chose stays")
	_eq([navigator.active_key, navigator.pan_to], [_local("data:p1"), ""], "herdr's focus selected, nothing asked")


# --- who needs a human --------------------------------------------------------


## `N` walks everyone who needs a human across the live machines, the blocked
## only while anyone is (the UNREAD once nobody is, see
## test_the_done_join_the_queue_when_nobody_is_blocked), and wraps around. Each
## press picks the pane, its floor and a reveal.
func test_n_walks_everyone_who_needs_a_human_and_wraps() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "web", "agent": "pi", "agent_status": "blocked"})
	var frame := _frame(local, basic)
	var navigator := OfficeNavigator.new()
	var seen: Array = []
	for press in 7:
		var peeked := navigator.peek_next(frame)
		var before := navigator.picked_key
		_eq(navigator.peek_next(frame), peeked, "press %d: peeking twice names the same" % press)
		_eq(navigator.picked_key, before, "press %d: and picks nothing" % press)
		_check(navigator.next_human(frame), "press %d finds someone" % press)
		_eq(navigator.picked_key, peeked, "press %d picks whom peek_next() named" % press)
		_eq(navigator.reveal_on_arrival, navigator.picked_key, "press %d reveals whom it picked" % press)
		seen.append([navigator.picked_key, navigator.picked_machine])
	_eq(
		seen,
		[
			[_local("web:p1"), LOCAL],
			[_local("infra:p1"), LOCAL],
			[_bee("bravo:p1"), BEE],
			[_local("notes:p1"), ""],
			[_local("web:p1"), LOCAL],
			[_local("infra:p1"), LOCAL],
			[_bee("bravo:p1"), BEE],
		],
		"the blocked, the unplaced pane among them, then around again, never to the UNREAD"
	)
	# The pane no floor seats waits in the same order as the seated
	# (OfficeNavigator.waiting()): blocked, it comes after the seated whose
	# starts are as unknown as its.
	var dropped := _frame(floors, basic, true)
	navigator.picked_key = _local("infra:p2")
	navigator.next_human(dropped)
	_eq(navigator.picked_key, _local("web:p1"), "a dropped machine's agents are nobody's to answer")
	var quiet := _frame(_with(basic, "bravo:p1", {"agent_status": "working"}))
	navigator.picked_key = ""
	_eq(navigator.peek_next(quiet), "", "with nobody waiting, nobody is next")
	_check(not navigator.next_human(quiet), "with nobody waiting, `N` does nothing")
	_eq(navigator.picked_key, "", "and picks nothing")


## `‹` (peek_prev(), step(-1)) walks NEXT's queue backwards: from
## a pick in it, the one before, wrapping from the first to the last; from a
## selection outside it (nobody, or a working agent), the last. While anyone is
## blocked the queue is the blocked only, so the last is the last
## blocked. step(+1) picks whom peek_next() names. Each step picks, shows the
## floor and reveals, as `N` does; with nobody waiting it picks nothing.
func test_peek_prev_walks_the_queue_backwards_and_wraps() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "web", "agent": "pi", "agent_status": "blocked"})
	var frame := _frame(local, basic)
	var navigator := OfficeNavigator.new()
	navigator.picked_key = ""
	# The end is the last blocked, not the last UNREAD (infra:p2).
	_eq(navigator.peek_prev(frame), _local("notes:p1"), "from nobody, going back starts from the end")
	navigator.picked_key = _local("api:p1")
	_eq(navigator.peek_prev(frame), _local("notes:p1"), "and from a selection outside the queue")
	var back: Array = []
	for press in 7:
		var peeked := navigator.peek_prev(frame)
		var before := navigator.picked_key
		_eq(navigator.peek_prev(frame), peeked, "back %d: peeking twice names the same" % press)
		_eq(navigator.picked_key, before, "back %d: and picks nothing" % press)
		_check(navigator.step(frame, -1), "back %d finds someone" % press)
		_eq(navigator.picked_key, peeked, "back %d picks whom peek_prev() named" % press)
		_eq(navigator.reveal_on_arrival, peeked, "back %d reveals whom it picked" % press)
		back.append([navigator.picked_key, navigator.picked_machine])
	_eq(
		back,
		[
			[_local("notes:p1"), ""],
			[_bee("bravo:p1"), BEE],
			[_local("infra:p1"), LOCAL],
			[_local("web:p1"), LOCAL],
			[_local("notes:p1"), ""],
			[_bee("bravo:p1"), BEE],
			[_local("infra:p1"), LOCAL],
		],
		"N's queue read backwards, and round again from its first to its last"
	)
	navigator.picked_key = _local("web:p1")
	var next := navigator.peek_next(frame)
	_check(navigator.step(frame, 1), "a step on finds someone")
	_eq(navigator.picked_key, next, "whom peek_next() named")
	_eq(next, _local("infra:p1"), "the one after web:p1")
	var quiet := _frame(_with(basic, "bravo:p1", {"agent_status": "working"}))
	navigator.picked_key = _local("api:p1")
	_eq(navigator.peek_prev(quiet), "", "with nobody waiting, nobody is before")
	_check(not navigator.step(quiet, -1) and not navigator.step(quiet, 1), "and neither step does anything")
	_eq(navigator.picked_key, _local("api:p1"), "the pick stays")


## While anyone is blocked, NEXT's queue is
## the blocked only, Civilization's turn blockers. Local's blocked web:p1
## (since 100) and infra:p1 (since 200), and the UNREAD web:p2 and infra:p2
## waiting longer than both: `N`, `›` and `‹` go round the two blocked and
## never reach a done one; DONE on the top bar still does.
func test_the_queue_is_the_blocked_while_anyone_is_blocked() -> void:
	var frame := _frame(floors)
	var starts: Dictionary[String, float] = {
		_local("web:p1"): 100.0, _local("infra:p1"): 200.0, _local("web:p2"): 60.0, _local("infra:p2"): 50.0
	}
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	navigator.picked_key = _local("web:p1")
	_eq(navigator.peek_next(frame), _local("infra:p1"), "after the longest blocked, the next blocked")
	_eq(navigator.peek_prev(frame), _local("infra:p1"), "and before it, round the other way, the last blocked")
	var walked: Array = []
	for press in 4:
		_check(navigator.next_human(frame), "press %d finds someone" % press)
		walked.append(navigator.picked_key)
	_eq(
		walked,
		[_local("infra:p1"), _local("web:p1"), _local("infra:p1"), _local("web:p1")],
		"N goes round the blocked, never to the done who waited longer"
	)
	var stepped: Array = []
	for direction: int in [1, 1, -1, -1]:
		_check(navigator.step(frame, direction), "a step finds someone")
		stepped.append(navigator.picked_key)
	_eq(
		stepped,
		[_local("infra:p1"), _local("web:p1"), _local("infra:p1"), _local("web:p1")],
		"‹ and › go round the blocked too"
	)
	_check(navigator.next_of(frame, "done"), "DONE still reaches a done agent while someone is blocked")
	_eq(navigator.picked_key, _local("infra:p2"), "the oldest UNREAD")


## The done come into NEXT's queue only when nobody is blocked, in wait
## order, and round again; the moment somebody blocks they drop out of it (from
## the one blocked, the next is that one again), and come back once it is
## answered.
func test_the_done_join_the_queue_when_nobody_is_blocked() -> void:
	var calm := _with(_with(floors, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "idle"})
	var starts: Dictionary[String, float] = {_local("web:p2"): 80.0, _local("infra:p2"): 50.0, _local("web:p1"): 300.0}
	var frame := _frame(calm)
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	var walked: Array = []
	for press in 3:
		_check(navigator.next_human(frame), "press %d finds a done one" % press)
		walked.append(navigator.picked_key)
	_eq(walked, [_local("infra:p2"), _local("web:p2"), _local("infra:p2")], "the done, oldest first, and round")
	_eq(navigator.peek_prev(frame), _local("web:p2"), "and back round the other way")
	var asking := _frame(_with(calm, "web:p1", {"agent_status": "blocked"}))
	_stamp(asking, starts)
	_eq(navigator.peek_next(asking), _local("web:p1"), "somebody blocks: from a done one, NEXT names them")
	_check(navigator.next_human(asking), "N picks them")
	_eq(navigator.picked_key, _local("web:p1"), "the one blocked")
	_eq(navigator.peek_next(asking), _local("web:p1"), "and from them, the next is them again, not a done one")
	_eq(navigator.peek_prev(asking), _local("web:p1"), "and so is the one before")
	_eq(navigator.peek_next(frame), _local("infra:p2"), "answered: the done are back, from the top")


## From a pick outside the queue (nobody, a working agent, or a done one
## while somebody is blocked), NEXT names the blocked who has waited longest and
## `‹` the newest blocked, whoever else waited longer.
func test_from_outside_the_queue_next_is_the_longest_waiting_blocked() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "web", "agent": "pi", "agent_status": "blocked"})
	var frame := _frame(local, basic)
	var starts: Dictionary[String, float] = {
		_local("web:p1"): 300.0,
		_local("infra:p1"): 100.0,
		_local("notes:p1"): 200.0,
		_bee("bravo:p1"): 400.0,
		_local("web:p2"): 20.0,
		_local("infra:p2"): 10.0,
	}
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	for outside: String in ["", _local("api:p1"), _local("infra:p2"), _local("web:p2")]:
		navigator.picked_key = outside
		_eq(navigator.peek_next(frame), _local("infra:p1"), "from '%s', the longest-waiting blocked" % outside)
		_eq(navigator.peek_prev(frame), _bee("bravo:p1"), "from '%s', back is the newest blocked" % outside)
	navigator.picked_key = _local("infra:p2")
	_check(navigator.next_human(frame), "N from the oldest done")
	_eq(navigator.picked_key, _local("infra:p1"), "picks the longest-waiting blocked")
	_eq(navigator.picked_machine, LOCAL, "shows its machine's map")
	_eq(navigator.reveal_on_arrival, _local("infra:p1"), "and reveals it")


## The top bar's BLOCKED and DONE (next_of()): only that state, longest wait
## first by state_since, the pane no floor seats ranked with the seated,
## then round again; a
## selection outside the queue starts from the top. A dropped machine and a
## shell are never in it; an agent still launching is, once it asks.
func test_next_of_walks_one_state_and_done_starts_from_the_oldest() -> void:
	var local := _with(floors, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	local = _with(_with(local, "data:p2", {"agent_status": "blocked"}), "api:p3", {"agent_status": "blocked"})
	var frame := _frame(local, basic, true)
	var starts: Dictionary[String, float] = {
		_local("web:p1"): 200.0,
		_local("infra:p1"): 100.0,
		_local("notes:p1"): 150.0,
		_local("web:p2"): 80.0,
		_local("infra:p2"): 50.0
	}
	_stamp(frame, starts)
	var navigator := OfficeNavigator.new()
	var walked: Array = []
	for press in 5:
		_check(navigator.next_of(frame, "blocked"), "press %d finds somebody blocked" % press)
		walked.append([navigator.picked_key, navigator.picked_machine, navigator.reveal_on_arrival])
	# Blocked comes first: data:p2, blocked while still launching, is in the
	# queue, its start unknown, so first.
	_eq(
		walked,
		[
			[_local("data:p2"), LOCAL, _local("data:p2")],
			[_local("infra:p1"), LOCAL, _local("infra:p1")],
			[_local("notes:p1"), "", _local("notes:p1")],
			[_local("web:p1"), LOCAL, _local("web:p1")],
			[_local("data:p2"), LOCAL, _local("data:p2")],
		],
		"unknown start first, then longest wait, the unseated pane by its wait too, then round; no shell or dropped bee"
	)
	# notes:p1, which no floor seats, ranks by its wait like the seated:
	# blocked since 150, it comes between infra:p1 (100) and web:p1 (200).
	navigator.picked_key = _local("api:p1")
	navigator.next_of(frame, "blocked")
	_eq(navigator.picked_key, _local("data:p2"), "a selection outside the queue starts from the top")
	navigator.picked_key = ""
	_check(navigator.next_of(frame, "done"), "somebody is UNREAD")
	_eq(navigator.picked_key, _local("infra:p2"), "DONE starts from the oldest")
	navigator.next_of(frame, "done")
	_eq(navigator.picked_key, _local("web:p2"), "then the next")
	var quiet := _frame(_with(basic, "bravo:p1", {"agent_status": "working"}))
	navigator.picked_key = ""
	_check(not navigator.next_of(quiet, "blocked"), "nobody blocked: nothing to walk")
	_eq(navigator.picked_key, "", "and nothing picked")


## Give the panes of `frame`, seated or not, the state starts in `starts` (pane
## key -> unix seconds), as the office's frame builder does from the fleet.
func _stamp(frame: OfficeFrame, starts: Dictionary[String, float]) -> void:
	for building_model in frame.buildings:
		for floor_model in building_model.zones:
			for room in floor_model.rooms:
				for pane in room.panes:
					pane.state_since = starts.get(pane.key, -1.0)
		for pane in building_model.all_panes:
			pane.state_since = starts.get(pane.key, -1.0)


## Attention's "View" selects the pane, shows its machine's map when it is
## seated and asks for it to be revealed; a zone picked drops that pending reveal.
func test_locating_a_pane_selects_it_and_reveals_it_on_arrival() -> void:
	var frame := _frame(_with(floors, "notes:p1", {"workspace_id": "web"}), basic)
	var navigator := OfficeNavigator.new()
	navigator.locate(frame, frame.pane(_bee("bravo:p1")))
	_eq(
		[navigator.picked_key, navigator.picked_machine, navigator.reveal_on_arrival],
		[_bee("bravo:p1"), BEE, _bee("bravo:p1")],
		"the pane, its machine and a reveal"
	)
	navigator.revealed()
	_eq(navigator.reveal_on_arrival, "", "once revealed, no more")
	navigator.locate(frame, frame.pane(_local("notes:p1")))
	_eq(navigator.picked_machine, BEE, "a pane no zone seats leaves the machine as it was")
	_eq(navigator.picked_key, _local("notes:p1"), "but is selected")
	navigator.pick_zone(_local("web"))
	_eq(navigator.reveal_on_arrival, "", "picking a zone drops the pending reveal")
	navigator.locate(frame, frame.pane(_local("api:p1")))
	_eq([navigator.pan_zone, navigator.current_zone(frame)], ["", ""], "and a locate drops the zone's pan and pick")


## Every navigation the viewer asks for counts one (nav_revision): a zone
## picked, PageUp/PageDown (step_zone(), which past either end picks and counts
## nothing) and every locate: `N`, `‹ ›`, a counter, a list pick. A desk pick,
## herdr's focus moving and the office's own pick of a new pane (follow_to())
## count none.
func test_navigations_count_and_a_zone_is_picked_like_a_floor() -> void:
	var frame := _frame(floors)
	var navigator := _showing(frame, _local("api"))
	var revision := navigator.nav_revision
	_check(not navigator.step_zone(frame, -1), "nothing above the first zone")
	_eq([navigator.pan_zone, navigator.nav_revision], ["", revision], "pans and counts nothing")
	_check(navigator.step_zone(frame, 1), "one down")
	_eq([navigator.pan_zone, navigator.nav_revision], [_local("web"), revision + 1], "pans to it, one navigation")
	_check(navigator.next_human(frame), "`N`")
	_eq(navigator.nav_revision, revision + 2, "one more")
	_check(navigator.step(frame, 1) and navigator.step(frame, -1), "`›` then `‹`")
	_eq(navigator.nav_revision, revision + 4, "one each")
	_check(navigator.next_of(frame, "blocked"), "BLOCKED")
	_eq(navigator.nav_revision, revision + 5, "one")
	navigator.locate(frame, frame.pane(_local("api:p1")))
	_eq(navigator.nav_revision, revision + 6, "a list pick: one")
	navigator.pick_zone(_local("infra"))
	_eq(navigator.nav_revision, revision + 7, "a zone picked: one")
	navigator.pick_desk(_local("api:p2"))
	_eq(navigator.nav_revision, revision + 7, "a desk pick: none")
	navigator.follow_to(frame, frame.pane(_local("web:p2")))
	_eq(navigator.nav_revision, revision + 7, "the office's own pick of a new pane: none")
	_eq(
		[navigator.picked_key, navigator.pan_to, navigator.pan_whole_table, navigator.reveal_on_arrival],
		[_local("web:p2"), _local("web:p2"), true, _local("web:p2")],
		"which selects it and frames its pod"
	)


## A machine picked (pick_machine(): its SPACES heading) shows that machine's
## map and counts one navigation; it picks no desk and no zone, drops a zone
## pan still pending, and leaves where the map opens to the map (its first
## arrival, or where the viewer left it); a machine that is gone is forgotten.
## A desk asked for (pan_to_desk(): an edge arrow) is one minimal pan, one
## navigation, and no selection.
func test_a_machine_pick_and_a_desk_pan_count_one_and_select_nothing() -> void:
	var frame := _frame(floors, basic)
	var navigator := OfficeNavigator.new()
	_eq(_show(navigator, frame), LOCAL, "Local's map, holding herdr's focus")
	var revision := navigator.nav_revision
	navigator.pick_zone(_local("infra"))
	navigator.pick_machine(BEE)
	_eq(
		[navigator.picked_machine, navigator.pan_zone, navigator.nav_revision],
		[BEE, "", revision + 2],
		"the machine picked, the zone pan it replaces dropped, one navigation each"
	)
	_eq(navigator.settle(frame), BEE, "bee's map is the one wanted")
	navigator.show_machine(frame, BEE, Vector2(10, 20))
	_eq([navigator.pan_to, navigator.pan_zone], ["", _bee("alpha")], "a first arrival: bee's first zone")
	_eq(navigator.pan_of(LOCAL), Vector2(10, 20), "Local's map remembers where it was left")
	_eq([navigator.picked_key, navigator.active_key], ["", _local("api:p1")], "no desk is picked: herdr's focus still")
	_eq(navigator.current_zone(frame), "", "and no zone of bee's is current")
	navigator.take_pan_zone()
	navigator.pick_machine(LOCAL)
	_eq(navigator.settle(frame), LOCAL, "back to Local")
	navigator.show_machine(frame, LOCAL, Vector2.ZERO)
	_eq([navigator.pan_to, navigator.pan_zone], ["", ""], "a map shown before asks for no pan")
	_eq(navigator.pan_of(LOCAL), Vector2(10, 20), "it opens where it was left")
	_eq(navigator.nav_revision, revision + 3, "one more navigation")
	navigator.pick_machine("nobody")
	_eq([navigator.settle(frame), navigator.picked_machine], [LOCAL, ""], "a machine that is gone is forgotten")
	revision = navigator.nav_revision
	navigator.pick_zone(_local("web"))
	navigator.pan_to_desk(_local("infra:p1"))
	_eq(
		[navigator.pan_to, navigator.pan_whole_table, navigator.pan_zone, navigator.reveal_on_arrival],
		[_local("infra:p1"), false, "", ""],
		"one pan, as far as it takes, replacing the zone pan pending"
	)
	_eq(navigator.nav_revision, revision + 2, "one navigation for the zone, one for the desk")
	_eq([navigator.picked_key, navigator.active_key], ["", _local("api:p1")], "and nothing is selected")
	_eq([navigator.take_pan_to(), navigator.take_pan_to()], [_local("infra:p1"), ""], "taken once")


# --- the command line ---------------------------------------------------------


## The office, the showrooms and the studio read one parser: options with
## their values, bare flags, the last of a repeated option, and every argument
## kept for the parsers that read their own.
func test_the_command_line_reads_options_and_flags() -> void:
	var raw := PackedStringArray(
		["--zoom=3", "--attention", "--pack=a.json", "--pack=b.json", "--capture=", "stray", "--wait=1.5", "--space=x"]
	)
	var args := AppArgs.parse(raw)
	_eq(args.number("zoom", 2), 3, "a whole number")
	_check(args.flag("attention") and not args.has("attention"), "a bare flag is a flag, not an option")
	_eq(args.text("pack"), "b.json", "a repeated option takes its last value")
	_check(args.has("capture") and args.text("capture", "fallback").is_empty(), "an empty value is still given")
	_eq(args.decimal("wait", 0.0), 1.5, "a fraction")
	_eq(args.number("space", -1), 0, "a word reads as 0, as String.to_int() does")
	_eq(args.number("missing", 7), 7, "an option not given takes its fallback")
	_check(not args.flag("stray") and not args.has("stray"), "an argument without -- is neither")
	_eq(args.raw, raw, "every argument is kept for the parsers that read their own")
