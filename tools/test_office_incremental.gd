extends "res://tools/office_test_base.gd"
## Headless tests for in-place desk updates on the shown floor: a status, worker
## or selection change redraws only that desk, a change on another floor draws
## nothing, and what an in-place update leaves on screen is node for node what a
## full rebuild from the same data would draw. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_office_incremental.gd -- \
##     --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly. Exits 0 when every check passes, 1 on any failure, 2 on a
## harness error.

## Seat columns of a shared table stand one double-sided workstation apart.
const SEAT_SPACING := OfficeTable.MODULE * 2


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("incremental-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	fixture = parsed.snapshot
	# These cases are about seats: every agent on api works (api:p2 is idle in
	# the shared fixture, and an agent given to api:p3 would be too), so nobody
	# rests in the pantry unless a case says so.
	fixture = _with(_with(fixture, "api:p2", {"agent_status": "working"}), "api:p3", {"agent_status": "working"})
	_run()


func _run() -> void:
	# Let the root settle, so the office's _ready runs inside add_child. The
	# window only takes a size once the main loop is running, and the viewport
	# only picks what its visible rect holds, so a click on a desk needs the
	# window the offices here pretend to have.
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "INCREMENTAL TESTS"


# --- cases --------------------------------------------------------------------


func test_status_change_redraws_one_desk() -> void:
	var office := await _live_office()
	await _frames(12)
	var target := HerdrFleet.pane_key(LOCAL, "api:p4")
	var world_id: int = office.world.get_instance_id()
	var model: String = office.world_model
	var ids := _desk_ids(office, target)
	var progress := _actor_progress(office, target)
	_check(
		progress.values().any(func(p: Array) -> bool: return p[2] > 0.0),
		"workers have been animating before the change"
	)
	_feed(office, _with(fixture, "api:p4", {"agent_status": "blocked"}))
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(office.world_model, model, "a status is not part of the layout model")
	_eq(_desk_ids(office, target), ids, "every other desk keeps every node")
	_eq(_actor_progress(office, target), progress, "every other worker keeps its frame and progress")
	var desk: Node2D = office.floor_view.seats[target].node
	_eq(_badge(desk).state, ArtContract.STATE_BLOCKED, "the changed desk shows the new badge at once")
	_eq(_badge_state(LOCAL, "api:p4"), "blocked", "attention sees exactly one badge for the pane")
	# A blocked agent stays at its seat, under its bubble: nobody walks.
	_eq(office.floor_view.presentation.walkers(), [], "nobody walks: a blocked agent stays seated")
	_eq(_worker(desk).animation, &"blocked", "and the worker shows the new animation at once")
	await _same_as_rebuild(office, "after a status change")
	_done(office)


func test_same_look_keeps_the_worker() -> void:
	# Three idle agents on api, all first seen idle (so in projection order),
	# and the pantry of this narrow floor has room for two: api:p4 sits. 628
	# wide: the floor is planned 488 units wide.
	var idle := _with(_with(fixture, "api:p1", {"agent_status": "idle"}), "api:p2", {"agent_status": "idle"})
	idle = _with(idle, "api:p4", {"agent_status": "idle"})
	var office := await _live_office(idle, Vector2(628, 480))
	_eq(office.hud.plan_width(), 488.0, "planned 488 wide")
	var pantry := office.layout_plan().pantry
	_eq(pantry.spots.size() if pantry != null else -1, 2, "the pantry here holds two")
	var desk: OfficeStation = office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "api:p4")].node
	_eq([desk.rest, desk.actor().position], [OfficeRests.Rest.SEAT, Vector2.ZERO], "api:p4 finds it full and sits")
	await _frames(12)
	var actor: PixelPerson = desk.get_node("Actor")
	var before := _actor_state(actor)
	# idle -> unknown, seated: a new badge, but the worker's animation is idle
	# either way. (Not an idle agent the pantry has room for: they rest there.)
	_feed(office, _with(idle, "api:p4", {"agent_status": "unknown"}))
	actor = desk.get_node("Actor")
	_eq(_actor_state(actor), before, "the worker keeps its node and its place in the animation")
	_check(actor.is_playing(), "and keeps playing")
	_eq(_badge(desk).state, ArtContract.STATE_UNKNOWN, "the badge turns UNKNOWN")
	_eq(office.floor_view.presentation.walkers(), [], "and nobody walks")
	await _same_as_rebuild(office, "after a same-animation change")
	_done(office)


## Nobody stands at their seat: OfficeRests.rest_of() only ever
## answers the seat or the pantry, and only idle, not still launching, is the
## pantry. A pane still launching with a done status sits and plays starting,
## with no paper; a done agent sits at the desk with its paper; a done shell
## has nobody at all.
func test_nobody_stands_at_their_seat() -> void:
	for state: StringName in ArtContract.STATES:
		var away := state == ArtContract.STATE_IDLE
		var wanted := OfficeRests.Rest.PANTRY if away else OfficeRests.Rest.SEAT
		_eq(OfficeRests.rest_of(state, false), wanted, "%s rests at the %s" % [state, "pantry" if away else "seat"])
		_eq(OfficeRests.rest_of(state, true), OfficeRests.Rest.SEAT, "%s while starting sits" % state)
	var office := await _live_office()
	var launching := HerdrFleet.pane_key(LOCAL, "api:p2")
	var shell := HerdrFleet.pane_key(LOCAL, "api:p3")
	var done := HerdrFleet.pane_key(LOCAL, "api:p1")
	var snapshot := _with(fixture, "api:p2", {"agent_status": "done", "launch_pending": true})
	snapshot = _with(snapshot, "api:p3", {"agent_status": "done"})
	snapshot = _with(snapshot, "api:p1", {"agent_status": "done"})
	_feed(office, snapshot)
	var station := _station(office, launching)
	_eq(station.actor().animation, &"starting", "a launching pane plays starting")
	_eq(str(station.actor().look.context), "desk", "seated")
	_eq(station.actor().global_position, station.seat.global_position, "on its seat")
	_check(not station.table.papers(station.column, station.side).visible, "with no paper")
	_eq(_worker(_station(office, shell)), null, "a done shell has nobody")
	var sitter := _station(office, done)
	_eq(str(sitter.actor().look.context), "desk", "a done agent sits at the desk")
	_eq(sitter.actor().global_position, sitter.seat.global_position, "on its seat")
	_check(sitter.table.papers(sitter.column, sitter.side).visible, "with its paper")
	_eq(office.floor_view.presentation.walkers(), [], "and nobody walks")
	await _same_as_rebuild(office, "with a launching done pane and a done shell")
	_done(office)


## The table's standing spots, where a near seat's leg turns round the chair
## (nobody stands there), are on nobody's furniture: off every
## table's footprint, narrowest and wider, every column, both sides, and off
## every standing piece on the floor; the far one behind the far edge.
func test_standing_spots_are_clear() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var pen := OfficeDraw.new(art)
	var holder := Node2D.new()
	root.add_child(holder)
	var feet := _feet_size()
	for width: float in [160.0, 224.0, 288.0, 416.0]:
		for count: int in [1, maxi(1, int((width - 32.0) / SEAT_SPACING))]:
			var columns: Array = []
			for slot in count:
				columns.append(width / 2.0 - (count - 1) * SEAT_SPACING / 2.0 + slot * 64.0)
			var table := pen.table(holder, holder, "Table", Vector2(100, 300), width, columns)
			for column in columns.size():
				for side: String in OfficeTable.SIDES:
					var spot := table.standing(column, side).global_position
					var where := "%s-wide table, %d columns, column %d %s" % [width, count, column, side]
					var stands := Rect2(spot - Vector2(feet.x / 2.0, feet.y), feet)
					_check(not stands.intersects(_table_rect(table)), where + ": off the table's footprint")
					if side == "far":
						_check(
							spot.y < table.global_position.y - OfficeTable.SURFACE_DEPTH,
							where + ": behind the far edge, so the table hides none of them"
						)
			holder.remove_child(table)
			table.free()
	root.remove_child(holder)
	holder.free()
	for workspace: String in ["api", "web", "infra"]:
		var office := await _live_office()
		await _visit_floor(office, HerdrFleet.pane_key(LOCAL, workspace))
		var standing := _decor(office)
		_check(not standing.is_empty(), "%s really has furniture to stand clear of" % workspace)
		var checked := 0
		for node: Node in office.world.find_children("*", "", true, false):
			if not node is OfficeStation:
				continue
			var station: OfficeStation = node
			var spot := _spot(station)
			var stands := Rect2(spot - Vector2(feet.x / 2.0, feet.y), feet)
			for piece in standing:
				_check(
					not stands.intersects(piece.footprint_rect()),
					"%s %s: clear of the %s" % [workspace, station.name, piece.piece]
				)
			for table: OfficeTable in office.floor_view.tables:
				_check(
					not stands.intersects(_table_rect(table)),
					"%s %s: clear of %s" % [workspace, station.name, table.name]
				)
			checked += 1
		_check(checked > 0, "%s has seats to check" % workspace)
		_done(office)


## The plate, the badge and the selection mark hang off the seat whatever its
## agent is doing: done and blocked sit, so nothing moves; blocked only shows
## the bubble over the head, on this side's spot, and done only the paper on the
## table. The Overlay keeps the same nodes throughout.
func test_labels_follow_the_pose() -> void:
	var both_sides := _both_sides()
	var office := await _live_office(both_sides)
	for key: String in [HerdrFleet.pane_key(LOCAL, "api:p1"), HerdrFleet.pane_key(LOCAL, "api:p3")]:
		var station := _station(office, key)
		var side := station.side
		var overlay := station.get_node("Overlay")
		var nodes := _child_ids(overlay)
		var seated := [
			_plate(station).global_position,
			_badge(station).global_position,
			_sprite(station, "Overlay/Selection").global_position
		]
		_eq(
			seated,
			[
				station.seat.global_position + OfficeStation.PLATE_AT[side],
				station.seat.global_position + OfficeStation.BADGE_AT[side],
				station.seat.global_position + OfficeStation.SELECTION_AT
			],
			"%s: seated, the labels hang off the seat" % key
		)
		_check(not station.bubble().visible, "%s: working, no bubble" % key)
		for state: String in ["done", "blocked"]:
			_feed(office, _with(both_sides, HerdrFleet.split_key(key)[1], {"agent_status": state}))
			_eq(
				[
					_plate(station).global_position,
					_badge(station).global_position,
					_sprite(station, "Overlay/Selection").global_position
				],
				seated,
				"%s %s: the labels stay where they were" % [key, state]
			)
			_eq(station.bubble().visible, state == "blocked", "%s %s: a bubble only while blocked" % [key, state])
			_eq(
				station.bubble().global_position,
				station.seat.global_position + OfficeStation.BUBBLE_AT[side],
				"%s %s: the bubble hangs off this side's seat" % [key, state]
			)
			_eq(_child_ids(overlay), nodes, "%s %s: the overlay keeps every node" % [key, state])
		_feed(office, both_sides)
		_eq(
			[
				_plate(station).global_position,
				_badge(station).global_position,
				_sprite(station, "Overlay/Selection").global_position
			],
			seated,
			"%s: and back" % key
		)
	_done(office)


## A dropped machine freezes whoever sits: a done worker keeps their seat and
## their paper, stops moving and dims with the floor, and one that turns done
## while the machine is away sits down with paper, frozen.
func test_a_dropped_machine_keeps_done_seated_with_papers() -> void:
	var both_sides := _both_sides()
	var done := HerdrFleet.pane_key(LOCAL, "api:p1")
	var office := await _live_office(_with(both_sides, "api:p1", {"agent_status": "done"}))
	var station := _station(office, done)
	var actor := station.actor()
	_check(actor.is_playing(), "a live done worker moves")
	_check(station.table.papers(station.column, station.side).visible, "with paper beside the laptop")
	_set_online(office, false)
	actor = _station(office, done).actor()
	_eq(str(actor.look.context), "desk", "a lost machine gets nobody up")
	_eq(actor.global_position, station.seat.global_position, "or moves them")
	_check(not actor.is_playing(), "it freezes them")
	_check(station.table.papers(station.column, station.side).visible, "and keeps their paper")
	var later := HerdrFleet.pane_key(LOCAL, "api:p3")
	var both_done := _with(_with(both_sides, "api:p1", {"agent_status": "done"}), "api:p3", {"agent_status": "done"})
	_feed(office, both_done, false)
	var sitter := _station(office, later)
	var up := sitter.actor()
	_eq(str(up.look.context), "desk", "a worker done while stale sits")
	_check(sitter.table.papers(sitter.column, sitter.side).visible, "with paper")
	_check(not up.is_playing(), "frozen like the rest of the floor")
	await _same_as_rebuild(office, "with done workers while stale")
	_done(office)


## A done agent's paper is the table's own node from the start: done and back
## only shows and hides it. The table keeps every node, and so does every seat.
func test_papers_change_in_place() -> void:
	var office := await _live_office()
	var key := HerdrFleet.pane_key(LOCAL, "api:p1")
	var station := _station(office, key)
	var table := station.table
	var stack := table.papers(station.column, station.side)
	var nodes := _subtree_ids(table)
	var desks := _desk_ids(office, "")
	_check(not stack.visible, "working: no paper")
	for state: String in ["done", "working", "done"]:
		_feed(office, _with(fixture, "api:p1", {"agent_status": state}))
		_eq(stack.visible, state == "done", "%s: the paper %s" % [state, "shows" if state == "done" else "is hidden"])
		_eq(_subtree_ids(table), nodes, "%s: the table keeps every node" % state)
		_eq(_desk_ids(office, ""), desks, "%s: and every seat its nodes" % state)
	_done(office)


## A blocked agent's bubble is the seat's own node from the start: blocked and
## back only shows and hides it, and the Overlay keeps the same nodes.
func test_the_bubble_changes_in_place() -> void:
	var office := await _live_office()
	var key := HerdrFleet.pane_key(LOCAL, "api:p2")
	var station := _station(office, key)
	var overlay := station.get_node("Overlay")
	var nodes := _subtree_ids(overlay)
	var bubble := station.bubble()
	_check(not bubble.visible, "working: no bubble")
	for state: String in ["blocked", "working", "blocked"]:
		_feed(office, _with(fixture, "api:p2", {"agent_status": state}))
		_eq(
			bubble.visible,
			state == "blocked",
			"%s: the bubble %s" % [state, "shows" if state == "blocked" else "is hidden"]
		)
		_eq(station.bubble(), bubble, "%s: the same bubble" % state)
		_eq(_subtree_ids(overlay), nodes, "%s: the overlay keeps every node" % state)
	_done(office)


## A drag pans the office and only a still click picks a desk, which is one rule
## in one place: the viewport hands a mouse button to _unhandled_input first, so
## the press a pick belongs to is already recorded when the seat's Area2D
## reports it on the next physics frame.
func test_a_still_click_picks_and_a_drag_does_not() -> void:
	var office := await _live_office()
	var first := HerdrFleet.pane_key(LOCAL, "api:p2")
	var second := HerdrFleet.pane_key(LOCAL, "api:p3")
	await _frame_table(office, first)
	await _click_desk(office, first)
	_eq(office.picked_key, first, "a still click picks the desk under it")
	# The press goes on the desk that is NOT selected, so a press that picked
	# would move the selection and this would say so.
	var from := _desk_point(office, second)
	var to := _desk_point(office, first)
	_check(office.hud.world_rect().has_point(from), "the other desk is on screen, so a press really lands on it")
	await _button(from, true)
	await _button(to, false)
	_eq(office.picked_key, first, "a drag from one desk to another picks neither")
	var empty := _vacant_seat(office)
	_check(empty != null, "the shown floor really has a vacant seat on screen to try")
	if empty != null:
		var target: Area2D = empty.get_node("Target")
		_check(not target.input_pickable, "a seat nobody's pane uses is not pickable at all")
		await _click(empty.target_rect().get_center() - office.camera.position)
		_eq(office.picked_key, first, "so a click on one picks nothing")
	# 64 units further down the floor from where the table was framed: the
	# framing already panned to keep it above the staff panel.
	var panned := office.camera.pan + Vector2(0, 64)
	office.camera.pan = panned
	await _frames(2)
	_eq(office.camera.position, panned, "the office really panned")
	_check(office.hud.world_rect().has_point(_desk_point(office, second)), "the desk is still on screen")
	await _click(_desk_point(office, second))
	_eq(office.picked_key, second, "a click after a pan still picks the desk under it")
	_done(office)


## Only the release of a still left click picks a desk. A press is a drag that
## has not moved yet, a drag pans and picks nothing wherever it starts or ends,
## and no other button is a pick at all — even sitting exactly where the last
## left press did, which is the only thing CLICK_SLOP looks at.
func test_only_a_still_left_release_picks() -> void:
	var office := await _live_office()
	var first := HerdrFleet.pane_key(LOCAL, "api:p1")
	var second := HerdrFleet.pane_key(LOCAL, "api:p2")
	await _click_desk(office, first)
	_eq(office.picked_key, first, "a still left click picks the desk under it")
	var on_second := _desk_point(office, second)
	await _button(on_second, true)
	_check(office.camera.dragging, "a press over a desk starts a drag")
	_eq(office.picked_key, first, "and selects nothing on its own")
	await _button(on_second, false)
	_eq(office.picked_key, second, "the still release is what picks")
	# A drag that starts on a desk pans and leaves the selection alone.
	var on_first := _desk_point(office, first)
	var before: Vector2 = office.camera.pan
	await _drag(on_first, on_first - Vector2(0, 96))
	_check(office.camera.pan != before, "a drag that starts on a desk pans: %s -> %s" % [before, office.camera.pan])
	_eq(office.picked_key, second, "and picks nothing")
	# Nor does one that ends on a desk.
	await _drag(office.hud.world_rect().position + Vector2(4, 4), _desk_point(office, first))
	_eq(office.picked_key, second, "a drag that ends on a desk picks nothing either")
	# Every other button, sitting exactly where the last left press sat.
	for button: MouseButton in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var at := _desk_point(office, first)
		await _button(at, true)
		await _button(at + Vector2(0, -96), false)
		_eq(office.picked_key, second, "the drag that put the press on the desk picked nothing")
		await _button_of(at, button, true)
		await _button_of(at, button, false)
		_eq(office.picked_key, second, "button %d over a desk picks nothing" % button)
	_done(office)


## A click over a HUD panel never reaches a desk, with one right under the
## panel: a Control takes the event in the viewport's GUI pass, which runs
## before both _unhandled_input and physics picking.
func test_a_click_over_a_panel_picks_nothing() -> void:
	var office := await _live_office()
	# Pan an actual seat beneath each panel. Floor geometry does not
	# reflow on resize, so neither zero nor maximum pan implies an overlap.
	office.test_screen = Vector2(480, 320)
	office.refresh()
	# The drawer open (a real click on its tab), so the right column is the list.
	var tab: Control = office.hud.get_node("%DrawerTab")
	await _click(tab.get_global_rect().get_center())
	await _frames(2)
	_check(office.hud.drawer_open(), "the tab opens the drawer")
	var target := _station(office, HerdrFleet.pane_key(LOCAL, "api:p2"))
	# The right column is the agent list's drawer; the card is the staff panel along the bottom.
	for panel: Control in [office.hud.right_column, office.hud.floors, office.hud.inspector, office.hud.news]:
		var bounds := office.hud.placed(panel)
		# The seat goes under a spot of the panel with no button on it: a click
		# on a minimap row or a list row is that panel's own gesture, not a desk's.
		var station: OfficeStation = null
		for aim: Vector2 in [bounds.get_center(), bounds.position + Vector2(bounds.size.x / 4.0, 12)]:
			office.camera.pan = target.target_rect().get_center() - aim
			await _frames(2)
			station = _seat_under(office, bounds)
			if (
				station != null
				and not _over_a_button(panel, station.target_rect().get_center() - office.camera.position)
			):
				break
			station = null
		_check(station != null, "%s: a desk really is under the panel, clear of its buttons" % panel.name)
		if station == null:
			continue
		var picked: String = office.picked_key
		var panned: Vector2 = office.camera.pan
		await _click(station.target_rect().get_center() - office.camera.position)
		_eq(office.picked_key, picked, "%s: a click over the panel picks no desk" % panel.name)
		_eq(office.camera.pan, panned, "%s: and starts no pan" % panel.name)
		_check(not office.camera.dragging, "%s: the office never saw the press" % panel.name)
	_done(office)


## Whether `at` (viewport units) is on a button shown inside `panel`.
func _over_a_button(panel: Control, at: Vector2) -> bool:
	for node: Node in panel.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node
		if button.is_visible_in_tree() and button.get_global_rect().has_point(at):
			return true
	return false


## Picking is the viewport's, so it follows the window's content scale for
## free: the office turns no screen point into a world point itself.
## At a scale of 4 the same desk is picked by a click twice as far into the
## window as at 2, which is the case a hand-written conversion gets wrong.
func test_picking_follows_the_window_scale() -> void:
	var office := await _live_office()
	var target := HerdrFleet.pane_key(LOCAL, "api:p2")
	for scale: int in [2, 4]:
		root.size = SCREEN * scale + Vector2i.ONE
		for step in absi(scale - office.zoom) / OfficeScene.ZOOM_STEP:
			var event := _key(KEY_EQUAL if office.zoom < scale else KEY_MINUS)
			await _parsed(event)
			event.pressed = false
			await _parsed(event)
		await _frames(2)
		_check(
			root.get_visible_rect().size.is_equal_approx(Vector2(root.size) / float(scale)),
			"zoom %d fills an odd-sized window without rounding its logical edges" % scale
		)
		office.picked_key = ""
		office.refresh()
		await _frames(2)
		var at := _desk_point(office, target)
		await _parsed(_mouse_button(at * scale, MOUSE_BUTTON_LEFT, true))
		await _parsed(_mouse_button(at * scale, MOUSE_BUTTON_LEFT, false))
		_eq(office.picked_key, target, "a click in window pixels picks the desk at zoom %d" % scale)
	root.size = SCREEN
	await _frames(2)
	_done(office)


## Every key and wheel button the office answers is an InputMap action, and each
## one still does what its keycode did. A held key repeats; the office does not.
## All of it through real input events, as the window delivers them.
func test_office_actions_answer_their_keys() -> void:
	var office := await _live_office()
	# The office ships one pack; T cycles packs when it has more than one.
	office.themes = PackedStringArray([office.manifest_path, _second_pack()])
	# An [input] section of our own does not take the engine's built-ins away,
	# and arrow-key panning is still Input.get_vector() over them.
	for action: StringName in [&"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		_check(InputMap.has_action(action), "arrow panning keeps the engine's own %s" % action)
	office.zoom = 2
	await _office_key(office, KEY_MINUS)
	_eq(office.zoom, 2, "`-` stops at the smallest even zoom")
	await _office_key(office, KEY_EQUAL)
	_eq(office.zoom, 4, "`=` zooms in one even step")
	await _office_key(office, KEY_EQUAL)
	_eq(office.zoom, 6, "and another")
	var held := _key(KEY_EQUAL, true)
	await _parsed(held)
	_eq(office.zoom, 6, "and an echo of a held key does nothing")
	held.pressed = false
	held.echo = false
	await _parsed(held)
	var pack: String = office.manifest_path
	await _office_key(office, KEY_T)
	_check(office.manifest_path != pack, "`T` switches the theme")
	var shown := office.layout_plan().floor_key
	await _office_key(office, KEY_PAGEUP)
	_check(office.layout_plan().floor_key != shown, "PageUp shows another floor")
	await _office_key(office, KEY_PAGEDOWN)
	_eq(office.layout_plan().floor_key, shown, "and PageDown comes back")
	office.picked_key = ""
	await _office_key(office, KEY_N)
	_check(not office.picked_key.is_empty(), "`N` jumps to somebody who needs a human")
	var steps := {
		MOUSE_BUTTON_WHEEL_UP: Vector2(0, -OfficeCamera.SCROLL_STEP),
		MOUSE_BUTTON_WHEEL_DOWN: Vector2(0, OfficeCamera.SCROLL_STEP),
		MOUSE_BUTTON_WHEEL_LEFT: Vector2(-OfficeCamera.SCROLL_STEP, 0),
		MOUSE_BUTTON_WHEEL_RIGHT: Vector2(OfficeCamera.SCROLL_STEP, 0),
	}
	# A window small enough that the floor reaches past a notch in every
	# direction, so what the wheel does is not taken back by the pan's clamp.
	office.test_screen = Vector2(480, 320)
	office.refresh()
	var over_world := office.hud.world_rect().get_center()
	for button: MouseButton in steps:
		var step: Vector2 = steps[button]
		office.camera.pan = Vector2(128, 128)
		await _frames(1)
		_eq(office.camera.pan, Vector2(128, 128), "the floor reaches a notch past the pan the wheel starts from")
		var notch := _wheel(button)
		notch.position = over_world
		notch.global_position = over_world
		await _parsed(notch)
		_eq(office.camera.pan, Vector2(128, 128) + step, "the wheel pans one notch: %s" % step)
		notch.pressed = false
		await _parsed(notch)
	_done(office)


func test_selection_only_moves_the_mark() -> void:
	var office := await _live_office()
	var from: String = office.navigator.active_key
	var to := HerdrFleet.pane_key(LOCAL, "api:p4")
	_eq(from, HerdrFleet.pane_key(LOCAL, "api:p1"), "herdr's focus is selected first")
	var world_id: int = office.world.get_instance_id()
	var actors := _all_actor_ids(office)
	var from_ids := _child_ids(office.floor_view.seats[from].node)
	var to_ids := _child_ids(office.floor_view.seats[to].node)
	var others := _desk_ids(office, from, to)
	await _click_desk(office, to)
	_eq(office.navigator.active_key, to, "the click selects the desk")
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(_all_actor_ids(office), actors, "no worker anywhere is rebuilt")
	_eq(_desk_ids(office, from, to), others, "no other desk is touched")
	var old_desk: Node2D = office.floor_view.seats[from].node
	var new_desk: Node2D = office.floor_view.seats[to].node
	_check(not _sprite(old_desk, "Overlay/Selection").visible, "the old desk loses its mark")
	_eq(_child_ids(old_desk), from_ids, "and nothing else")
	_check(_sprite(new_desk, "Overlay/Selection").visible, "the new desk gets a mark")
	_eq(_child_ids(new_desk), to_ids, "and nothing else changes there")
	_eq(
		_names(new_desk),
		["Chair", "Actor", "Overlay", "Target"],
		"a seat is its chair, its worker, what floats over them and where it answers a click"
	)
	_eq(
		_names(new_desk.get_node("Overlay")),
		["Plate", "Lens", "Selection", "Bubble", "Badge"],
		(
			"the lens line goes right after the plate, the mark under the badge, and so does the bubble"
			+ " over a blocked agent: the badge is drawn over it"
		)
	)
	await _same_as_rebuild(office, "after a selection change")
	_done(office)


## A monitor is a terminal, so a seat has one exactly when herdr has a pane
## there. A shell (a pane with nobody in the chair) keeps its screen; a seat no
## pane uses has neither a screen nor a lamp.
func test_monitors_follow_panes() -> void:
	var office := await _live_office()
	var sides := {}
	for station in _seats(office):
		_check(
			station.table.monitor(station.column, station.side).visible,
			"%s (%s) has a terminal" % [station.pane_key, station.side]
		)
		sides[station.side] = true
	_eq(sides.keys().size(), 2, "the fixture seats panes on both sides of a table")
	var shell: OfficeStation = office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "api:p3")].node
	await _frame_table(office, shell.pane_key)
	_check(shell.actor() == null, "api:p3 really is a shell: nobody in the chair")
	_check(shell.table.monitor(shell.column, shell.side).visible, "and its screen is still on")
	var empty := _vacant_seat(office)
	_check(empty != null, "the shown floor has a seat no pane uses")
	_check(not empty.table.monitor(empty.column, empty.side).visible, "a seat with no pane has no terminal")
	_eq(_lamp_level(empty.table, empty.column, empty.side), OfficeTable.Lamp.OFF, "and its lamp is off")
	await _same_as_rebuild(office, "with terminals on the seats that have panes")
	_done(office)


## Herdr's focus is the brightest lamp on the floor, a tab its workspace does
## not have open is dimmed, and everything else burns normally.
func test_task_lamps_follow_focus_and_open_tab() -> void:
	var office := await _live_office()
	# The fixture: focus on api:p1, api:t1 open, so api:t2 (api:p4) is dimmed.
	_eq(
		_lamps(office),
		{
			"api:p1": OfficeTable.Lamp.FOCUS,
			"api:p2": OfficeTable.Lamp.ON,
			"api:p3": OfficeTable.Lamp.ON,
			"api:p4": OfficeTable.Lamp.DIM,
		},
		"the focused seat, its neighbours, and a tab nobody has open"
	)
	# web names no open tab at all, and not saying is not a no: nothing dims.
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "web"))
	_eq(
		_lamps(office).values(),
		[OfficeTable.Lamp.ON, OfficeTable.Lamp.ON, OfficeTable.Lamp.ON],
		"a workspace that names no open tab dims nothing"
	)
	_done(office)


## Herdr's focus moving relights the two seats it left and arrived at, and
## nothing else: no table, no worker and no desk node is rebuilt.
func test_focus_move_only_relights_two_seats() -> void:
	var office := await _live_office()
	await _frames(12)
	var was := HerdrFleet.pane_key(LOCAL, "api:p1")
	var now := HerdrFleet.pane_key(LOCAL, "api:p2")
	var world_id: int = office.world.get_instance_id()
	var model: String = office.world_model
	var tables := _table_ids(office)
	var others := _desk_ids(office, was, now)
	var progress := _actor_progress(office, "")
	_feed(office, _focused_on(fixture, "api:p2"))
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(office.world_model, model, "herdr's focus is not part of the layout model")
	_eq(_table_ids(office), tables, "every table keeps its node")
	_eq(_desk_ids(office, was, now), others, "every other desk keeps every node")
	_eq(_actor_progress(office, ""), progress, "and every worker keeps its frame and progress")
	_eq(
		_lamps(office),
		{
			"api:p1": OfficeTable.Lamp.ON,
			"api:p2": OfficeTable.Lamp.FOCUS,
			"api:p3": OfficeTable.Lamp.ON,
			"api:p4": OfficeTable.Lamp.DIM,
		},
		"the light moved from one seat to the other"
	)
	await _same_as_rebuild(office, "after herdr's focus moved")
	_done(office)


## Herdr's focus landing on a seat only relights it. The seat is not seated
## again: a blocked agent's wait stays on screen instead of blinking out until
## the attention clock's next beat, which is what a whole furnish() would do.
func test_focus_move_does_not_reseat_a_blocked_desk() -> void:
	var blocked_floor := _with(fixture, "api:p2", {"agent_status": "blocked"})
	var office := await _live_office(blocked_floor)
	var blocked := HerdrFleet.pane_key(LOCAL, "api:p2")
	_set_wait(office, "api:p2", 742.0)
	await _text_tick()
	_eq(_wait_text(office, blocked), "12m", "the blocked seat shows its wait before the focus moves")
	_feed(office, _focused_on(blocked_floor, "api:p2"))
	_eq(_wait_text(office, blocked), "12m", "and still shows it the moment herdr's focus lands on it")
	_eq(_lamps(office)["api:p2"], OfficeTable.Lamp.FOCUS, "while its lamp is the bright one")
	_feed(office, _focused_on(blocked_floor, "api:p1"))
	_eq(_wait_text(office, blocked), "12m", "and the moment the focus leaves again")
	_eq(_lamps(office)["api:p2"], OfficeTable.Lamp.ON, "with its lamp back to normal")
	# A rebuilt office has not had a beat of the attention clock yet, so the
	# comparison is made once nobody is waiting (as in the wait's own case).
	# api:p2 never left its seat: nobody walks.
	_feed(office, _focused_on(fixture, "api:p1"))
	_eq(office.floor_view.presentation.walkers(), [], "api:p2 was blocked at its seat: nobody walks")
	await _same_as_rebuild(office, "after the focus visited a blocked desk")
	_done(office)


## The tab a workspace has open changing dims or lights a whole table, without
## rebuilding the floor it stands on.
func test_open_tab_change_does_not_rebuild() -> void:
	var office := await _live_office()
	var world_id: int = office.world.get_instance_id()
	var model: String = office.world_model
	var tables := _table_ids(office)
	_feed(office, _open_tab_of(fixture, "api", "api:t2"))
	_eq(office.world.get_instance_id(), world_id, "the world is not rebuilt")
	_eq(office.world_model, model, "which tab is open is not part of the layout model")
	_eq(_table_ids(office), tables, "every table keeps its node")
	_eq(
		_lamps(office),
		{
			"api:p1": OfficeTable.Lamp.FOCUS,
			"api:p2": OfficeTable.Lamp.DIM,
			"api:p3": OfficeTable.Lamp.DIM,
			"api:p4": OfficeTable.Lamp.ON,
		},
		"the other table lit, this one dimmed, herdr's focus still the brightest"
	)
	await _same_as_rebuild(office, "after the open tab moved")
	_done(office)


## The floor plate names the repository, and after it the checkout directory of
## a workspace standing in a linked worktree.
func test_the_plate_names_a_linked_worktree() -> void:
	var office := await _live_office()
	_eq(_plate_lines(office).has("herdstead"), true, "floor 1 stands in its repository's own checkout")
	# infra (floor 3) is the fixture's linked worktree: ops-tools @ lane-a.
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "infra"))
	_eq(
		_plate_lines(office).has("ops-tools / lane-a"),
		true,
		"a linked worktree says which checkout, after the repository"
	)
	_eq(_plate_lines(office).has("ops-tools"), false, "and never the repository on its own")
	_done(office)


## The plate is furniture on the floor for the mouse too: a drag that starts on
## it pans the office, and the wheel over it scrolls, as anywhere on the floor.
func test_the_plate_pans_like_the_floor() -> void:
	var office := await _live_office()
	# A window narrow enough that the floor reaches past the view sideways, so a
	# drag along the plate, which stays on it, has somewhere to pan to.
	office.test_screen = Vector2(480, 320)
	office.refresh()
	office.camera.pan = Vector2.ZERO
	await _frames(2)
	_check(office.world_bounds().size.x - office.camera.free_rect().size.x >= 48.0, "the floor is wider than the view")
	var plate: Control = office.world.get_node("FloorPlate")
	# The signposts stand over the world's top-right corner and take a click
	# there; on a narrow world they are compact and leave this point clear.
	var on_plate := plate.get_global_rect().position + Vector2(100, 12) - office.camera.position
	var along := on_plate - Vector2(48, 0)
	_check(office.hud.world_rect().has_point(on_plate), "the plate is on screen")
	_check(plate.get_global_rect().has_point(along + office.camera.position), "and the drag stays on it")
	var posts := office.hud.signposts.get_global_rect()
	_check(
		not office.hud.signposts.visible or not (posts.has_point(on_plate) or posts.has_point(along)),
		"clear of the signposts: %s, %s, %s" % [posts, on_plate, along]
	)
	await _drag(on_plate, along)
	_eq(office.camera.pan, Vector2(48, 0), "a drag that starts on the plate pans the office")
	office.camera.pan = Vector2.ZERO
	await _frames(2)
	var notch := _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	notch.position = on_plate
	notch.global_position = on_plate
	await _parsed(notch)
	_eq(office.camera.pan, Vector2(0, OfficeCamera.SCROLL_STEP), "and the wheel over it scrolls")
	notch.pressed = false
	await _parsed(notch)
	_done(office)


## How long a blocked agent has been kept waiting, in the bubble over them, in
## the same words as the inspector's. Nobody else shows a number.
func test_blocked_seats_show_the_wait_in_the_bubble() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var blocked := HerdrFleet.pane_key(LOCAL, "api:p2")
	var working := HerdrFleet.pane_key(LOCAL, "api:p1")
	var shell := HerdrFleet.pane_key(LOCAL, "api:p3")
	# Snapshots are fed straight in here, so the status start is set here too.
	_set_wait(office, "api:p2", 742.0)
	await _text_tick()
	_eq(_wait_text(office, blocked), "12m", "the blocked seat says how long it has been waiting")
	_eq(_wait_text(office, blocked), OfficeBubble.wait_text(742.0), "in the bubble's short form of the same clock")
	_eq(_wait_text(office, working), "", "a working seat shows no number")
	_eq(_wait_text(office, shell), "", "and neither does a shell nobody is waiting on")
	await _frame_table(office, shell)
	var empty := _vacant_seat(office)
	_eq(_label(empty.bubble(), "%Wait").text, "", "nor a seat with no pane at all")
	_check(_station(office, blocked).bubble().visible, "the wait is in the blocked seat's bubble")
	# Leaving blocked takes the number away at once, not on the next beat.
	_feed(office, fixture)
	_eq(_wait_text(office, blocked), "", "a seat that stopped being blocked shows no wait")
	_eq(office.floor_view.presentation.walkers(), [], "api:p2 stays at its seat: nobody walks")
	await _same_as_rebuild(office, "after a wait in a bubble")
	_done(office)


## A machine that dropped shows no wait: it would go on growing off a snapshot
## nobody is receiving any more (invariant 4).
func test_a_dropped_machine_hides_the_wait() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var blocked := HerdrFleet.pane_key(LOCAL, "api:p2")
	_set_wait(office, "api:p2", 61.0)
	await _text_tick()
	_eq(_wait_text(office, blocked), "1m", "the wait is on screen while the machine is live")
	_set_online(office, false)
	await _text_tick()
	_eq(_wait_text(office, blocked), "", "and gone once the machine drops")
	_set_online(office, true)
	await _text_tick()
	_eq(_wait_text(office, blocked), "", "recovery cannot restore a start time lost during the gap")
	_feed(office, _with(fixture, "api:p2", {"agent_status": "working"}))
	_feed(office, _with(fixture, "api:p2", {"agent_status": "blocked"}))
	await _text_tick()
	_check(not _wait_text(office, blocked).is_empty(), "a newly observed transition starts a new wait")
	_done(office)


func test_worker_and_starting_flip() -> void:
	var office := await _live_office()
	var shell := HerdrFleet.pane_key(LOCAL, "api:p3")
	var starting := HerdrFleet.pane_key(LOCAL, "api:p2")
	var world_id: int = office.world.get_instance_id()
	var desk: Node2D = office.floor_view.seats[shell].node
	_eq(_names(desk), ["Chair", "Overlay", "Target"], "a shell desk has nobody")
	_check(not _sprite(desk, "Overlay/Badge").visible, "and no badge")
	var snapshot := _with(fixture, "api:p3", {"agent": "codex"})
	_feed(office, snapshot)
	_eq(_names(desk), ["Chair", "Actor", "Overlay", "Target"], "a worker comes to the seat")
	_check(_sprite(desk, "Overlay/Badge").visible, "with a badge")
	_eq(_plate(desk).text, "CODEX", "the name plate follows")
	_check(desk.get_node("Actor").is_in_group("office_actors"), "the new worker is an office actor")
	_walked(office, "as the worker comes in")
	_check(_feet(desk).disabled, "and sits: a seated worker does not collide")
	await _same_as_rebuild(office, "after a worker arrives")
	snapshot = _with(snapshot, "api:p3", {"agent": null})
	_feed(office, snapshot)
	desk = office.floor_view.seats[shell].node
	_eq(_names(desk), ["Chair", "Overlay", "Target"], "the worker leaves")
	_check(not _badge(desk).visible and not _badge(desk).is_in_group(StatusBadge.GROUP), "with the badge")
	_eq(_plate(desk).text, "SHELL", "the plate says shell again")
	world_id = office.world.get_instance_id()
	snapshot = _with(snapshot, "api:p2", {"launch_pending": true})
	_feed(office, snapshot)
	var starting_desk: Node2D = office.floor_view.seats[starting].node
	_eq(office.world.get_instance_id(), world_id, "starting begins in place")
	_eq(_worker(starting_desk).animation, &"starting", "a launching pane shows the starting pose")
	_check(not _badge(starting_desk).is_in_group(StatusBadge.GROUP), "and a starting badge that does not pulse")
	_walked(office, "as the worker who left walks out")
	await _same_as_rebuild(office, "while starting")
	world_id = office.world.get_instance_id()
	_feed(office, _with(snapshot, "api:p2", {"launch_pending": false}))
	starting_desk = office.floor_view.seats[starting].node
	_eq(office.world.get_instance_id(), world_id, "starting ends in place")
	# api:p2 works in this suite's fixture (see _initialize()).
	_eq(_worker(starting_desk).animation, &"working", "the worker settles into its state")
	var badge := _badge(starting_desk)
	_eq(
		[badge.state, badge.pane_id, badge.machine],
		[ArtContract.STATE_WORKING, "api:p2", LOCAL],
		"the state badge says what it pulses for"
	)
	await _same_as_rebuild(office, "after starting ends")
	_done(office)


func test_stale_desks_stay_frozen() -> void:
	var office := await _live_office()
	_set_online(office, false)
	var world_id: int = office.world.get_instance_id()
	var arriving := HerdrFleet.pane_key(LOCAL, "api:p3")
	var keeping := HerdrFleet.pane_key(LOCAL, "api:p2")
	var snapshot := _with(
		_with(fixture, "api:p3", {"agent": "pi", "agent_status": "blocked"}), "api:p2", {"agent_status": "done"}
	)
	_feed(office, snapshot, false)
	_eq(office.world.get_instance_id(), world_id, "a stale floor still updates in place")
	_check(not _worker(office.floor_view.seats[arriving].node).is_playing(), "a worker drawn while stale starts frozen")
	_check(not _worker(office.floor_view.seats[keeping].node).is_playing(), "a kept worker stays frozen")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "the rooms stay dimmed")
	var badge := _badge(office.floor_view.seats[arriving].node)
	_check(badge.is_in_group(StatusBadge.GROUP), "the new badge joins the pulse group")
	_eq(
		[badge.pane_id, badge.machine, badge.state],
		["api:p3", LOCAL, ArtContract.STATE_BLOCKED],
		"with its pane, machine and state"
	)
	office.attention._pulse()
	_eq(badge.offset, badge.rest_offset, "a stale badge rests on its pivot")
	await _same_as_rebuild(office, "while stale")
	_set_online(office, true)
	_eq(_playing(office), [true], "every worker plays again on reconnect")
	badge = _badge(office.floor_view.seats[arriving].node)
	var lifts := {}
	for step in 12:
		office.attention._pulse()
		# Offset is applied before scale, so the lift is in the pack's own
		# pixels; what the viewer sees is that many density-1 units.
		lifts[(badge.offset.y - badge.rest_offset.y) * badge.scale.y] = true
		OS.delay_msec(60)
	_check(
		lifts.keys().all(func(y: float) -> bool: return y in [0.0, -1.0, -2.0]) and lifts.size() > 1,
		"the new blocked badge pulses once live: %s" % [lifts.keys()]
	)
	_done(office)


## Badges rest exactly on the pivot the art pack declares and pulse from it,
## never over it: writing the bare lift into `offset` once dropped every badge
## by the pivot's whole height. Each rhythm is its own: a still state does not
## move at all, UNREAD and blocked nudge one pixel, and a pane blocked for
## longer than LONG_WAIT gets the harder two-pixel hop.
func test_badges_pulse_from_the_pack_pivot() -> void:
	var waiting := _with(_with(fixture, "api:p4", {"agent_status": "blocked"}), "api:p2", {"agent_status": "done"})
	var office := await _live_office(waiting)
	await _frames(2)
	var art: ArtPack = office.art
	var badges := {}
	for key: String in office.floor_view.seats:
		var badge := _badge(office.floor_view.seats[key].node)
		if badge.is_in_group(StatusBadge.GROUP):
			badges[badge.pane_id] = badge
	_eq(badges.keys(), ["api:p1", "api:p2", "api:p4"], "one badge per agent desk; the shell pane has none")
	for pane_id: String in badges:
		var badge: StatusBadge = badges[pane_id]
		var pivot := art.ui_sprite(art.state(badge.state).badge).pivot
		# Offset is in texture pixels, so the pack's pivot scales with density.
		var rest := -pivot * art.density
		_eq(badge.rest_offset, rest, "%s rests on the pack's pivot for %s" % [pane_id, badge.state])
	# This pane has been blocked longer than a human should have to wait. The
	# office feeds snapshots straight in, so its start time is set here.
	_set_wait(office, "api:p4", OfficeAttention.LONG_WAIT + 1.0)
	var seen := {}
	for pane_id: String in badges:
		seen[pane_id] = {}
	for step in 24:
		office.attention._pulse()
		for pane_id: String in badges:
			var badge: StatusBadge = badges[pane_id]
			# Offset is applied before scale, so the lift is in the pack's own pixels.
			seen[pane_id][(badge.offset.y - badge.rest_offset.y) * badge.scale.y] = true
		OS.delay_msec(40)
	var at_rest: Dictionary = seen["api:p1"]
	_eq(at_rest.keys(), [0.0], "a working badge never leaves its pivot")
	var unread: Dictionary = seen["api:p2"]
	var long_wait: Dictionary = seen["api:p4"]
	_eq(_sorted_lifts(unread), [-1.0, 0.0], "the UNREAD badge nudges one pixel")
	_eq(_sorted_lifts(long_wait), [-2.0, 0.0], "the long wait hops two")
	# A machine that drops freezes its badges; every one settles back exactly.
	_set_online(office, false)
	office.attention._pulse()
	for pane_id: String in badges:
		var badge := _badge(office.floor_view.seats[HerdrFleet.pane_key(LOCAL, pane_id)].node)
		_eq(badge.offset, badge.rest_offset, pane_id + " settles back on the pivot when the machine drops")
	_done(office)


func test_structural_changes_reconcile() -> void:
	var office := await _live_office()
	var world_id: int = office.world.get_instance_id()
	# The plate says how many panes the floor has; a new count is new text.
	var plate_id := office.world.get_node("FloorPlate").get_instance_id()
	_check(_plate_lines(office).has("2 TABS / 4 PANES"), "the plate counts api's panes")
	# A new pane in api's first room.
	var grown: Dictionary = fixture.duplicate(true)
	var grown_panes := _list(grown, "panes")
	var first: Dictionary = grown_panes[1]
	var extra := first.duplicate(true)
	extra.pane_id = "api:p9"
	grown_panes.append(extra)
	_feed(office, grown)
	_check(office.world.get_instance_id() == world_id, "a new pane reconciles within the world")
	_check(office.floor_view.seats.has(HerdrFleet.pane_key(LOCAL, "api:p9")), "and gets a desk")
	_check(_plate_lines(office).has("2 TABS / 5 PANES"), "the plate counts it")
	_eq(office.world.get_node("FloorPlate").get_instance_id(), plate_id, "in the plate it already had")
	world_id = office.world.get_instance_id()
	var renamed: Dictionary = grown.duplicate(true)
	for tab: Dictionary in renamed.tabs:
		if tab.tab_id == "api:t1":
			tab.label = "renamed room"
	_feed(office, renamed)
	_check(office.world.get_instance_id() == world_id, "a room label updates in place")
	world_id = office.world.get_instance_id()
	var shrunk: Dictionary = renamed.duplicate(true)
	_list(shrunk, "panes").pop_back()
	_feed(office, shrunk)
	_check(office.world.get_instance_id() == world_id, "a closed pane vacates its seat")
	_check(not office.floor_view.seats.has(HerdrFleet.pane_key(LOCAL, "api:p9")), "and loses its desk")
	_eq(office.world.get_node("FloorPlate").get_instance_id(), plate_id, "and the plate keeps its nodes throughout")
	renamed = shrunk
	office.test_screen = Vector2(1600, 480)
	office.refresh()
	world_id = office.world.get_instance_id()
	var rows := _row_count(office)
	office.test_screen = Vector2(480, 320)
	office.refresh()
	_check(office.world.get_instance_id() == world_id, "a narrower window preserves the world")
	_check(_row_count(office) == rows, "and retains the same table rows")
	world_id = office.world.get_instance_id()
	office.fleet._roster.sockets = MachineRoster.parse_socket_args(
		PackedStringArray(["--machine-socket=ghost=" + args.work.path_join("ghost.sock")])
	)
	office.fleet._sync_sites()
	_check(office.world.get_instance_id() == world_id, "a second machine changes only the plate and HUD")
	_eq(office.shown_machine(), LOCAL, "the shown floor stays on Local")
	world_id = office.world.get_instance_id()
	office.fleet._roster.sockets = MachineRoster.parse_socket_args(PackedStringArray())
	office.fleet._sync_sites()
	_check(office.world.get_instance_id() == world_id, "back to Local alone preserves the world")
	world_id = office.world.get_instance_id()
	office.switch_theme(_second_pack())
	_check(office.world.get_instance_id() != world_id, "a theme switch rebuilds")
	_eq(office.art.id, SECOND_PACK, "in the new pack")
	# Hit boxes still land on the desk they draw after in-place updates.
	_feed(office, _with(renamed, "api:p4", {"agent_status": "done"}))
	var target := HerdrFleet.pane_key(LOCAL, "api:p4")
	await _click_desk(office, target)
	_eq(office.picked_key, target, "a click after an in-place update still picks the right desk")
	_eq(office.floor_view.presentation.walkers(), [], "the done worker stays seated: nobody walks")
	await _same_as_rebuild(office, "after all of it")
	_done(office)


## Ambiguous identities cannot be placed safely. Keep the last valid model and
## geometry, surface the problem, and recover when an unambiguous snapshot arrives.
func test_repeated_pane_id_retains_valid_plan() -> void:
	var office := await _live_office()
	var original := office.layout_plan().geometry_signature()
	var world_id := office.world.get_instance_id()
	var seats := _seats(office).size()
	var twice: Dictionary = fixture.duplicate(true)
	var second: Dictionary = _list(twice, "panes")[1]
	_list(twice, "panes").append(second.duplicate(true))
	_feed(office, twice)
	_check(not office.layout_problems().is_empty(), "duplicate identity has an explicit diagnostic")
	_eq(office.layout_plan().geometry_signature(), original, "the last valid plan is retained")
	_eq(office.world.get_instance_id(), world_id, "no partially rebuilt world replaces the valid one")
	_eq(_seats(office).size(), seats, "the duplicate does not invent an ambiguous second seat")
	_feed(office, _with(twice, "api:p4", {"agent_status": "done"}))
	_eq(office.world.get_instance_id(), world_id, "another invalid snapshot still keeps the valid world")
	_eq(office.layout_plan().geometry_signature(), original, "invalid input never mutates the retained plan")
	_feed(office, _with(fixture, "api:p4", {"agent_status": "done"}))
	_check(office.layout_problems().is_empty(), "a corrected snapshot clears the diagnostic")
	_eq(office.world.get_instance_id(), world_id, "recovery updates in place")
	var target := HerdrFleet.pane_key(LOCAL, "api:p4")
	_eq(_badge(_station(office, target)).state, ArtContract.STATE_DONE, "recovery applies the current agent state")
	_done(office)


## A real click on a floor's row in the minimap shows that floor at once: by
## the time the button is up the world is the new floor's, the plate says so
## and that row is the one highlighted, alone. There is no transition over the
## world at all. PageDown, a real key, comes back as fast.
func test_a_floor_call_switches_at_once() -> void:
	var office := await _live_office()
	var origin := office.layout_plan().floor_key
	var destination := HerdrFleet.pane_key(LOCAL, "web")
	var minimap := office.hud.floors
	# The plate is the world's, and a new floor is a new world: read it each time.
	var title := func() -> String:
		var label: Label = office.plate.get_node("%Title")
		return label.text
	var highlighted := func() -> Array:
		return minimap.row_keys().filter(
			func(key: String) -> bool: return minimap.row_for(key).theme_type_variation == &"FloorRowCurrent"
		)
	_eq(highlighted.call(), [origin], "the shown floor's row is highlighted")
	var world_id := office.world.get_instance_id()
	var row := minimap.row_for(destination)
	var at := row.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(office.layout_plan().floor_key, destination, "released: the new floor is shown")
	_check(office.world.get_instance_id() != world_id, "and drawn")
	_check(str(title.call()).begins_with("2F"), "the plate says where we are: " + str(title.call()))
	_eq(highlighted.call(), [destination], "that row is highlighted alone")
	_check(office.hud.find_child("Transit", true, false) == null, "nothing covers the world on the way")
	var key := _key(KEY_PAGEDOWN)
	await _parsed(key)
	key.pressed = false
	await _parsed(key)
	_eq(office.layout_plan().floor_key, origin, "PageDown is back on the original floor at once")
	_check(str(title.call()).begins_with("1F"), "the plate follows: " + str(title.call()))
	_eq(highlighted.call(), [origin], "and so does the highlight")
	_done(office)


## Floor calls in quick succession each switch one floor, and nothing locks the
## world meanwhile: the next click on a desk picks it, a snapshot updates the
## floor in place, and a theme switch and a resize keep the floor buttons.
func test_rapid_floor_calls_each_switch_and_the_world_stays_clickable() -> void:
	var office := await _live_office()
	for wanted: String in ["web", "infra"]:
		var key := _key(KEY_PAGEUP)
		await _parsed(key)
		key.pressed = false
		await _parsed(key)
		_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, wanted), "PageUp: %s at once" % wanted)
	var row := office.hud.floors.row_for(HerdrFleet.pane_key(LOCAL, "web"))
	_check(not row.disabled, "the floor buttons stay enabled")
	var desk := HerdrFleet.pane_key(LOCAL, "infra:p1")
	await _click_desk(office, desk)
	_eq(office.picked_key, desk, "a click on a desk picks it right away")
	var world_id := office.world.get_instance_id()
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	_eq(office.world.get_instance_id(), world_id, "a snapshot updates the floor in place")
	_eq(_badge(_station(office, desk)).state, &"working", "with its live data")
	office.test_screen = Vector2(640, 320)
	office.switch_theme(_second_pack())
	_eq(office.hud.floors.row_for(row.key), row, "theme and resize keep the floor buttons")
	_check(not row.disabled, "still enabled")
	_done(office)


## The floor the viewer picked going away while it is shown falls back at once
## to one that exists (the selection's), and so does the shown floor when the
## one it came from goes: nothing is waited for, and nothing comes back later.
func test_a_picked_floor_that_disappears_falls_back_at_once() -> void:
	for removed: String in ["web", "api"]:
		var office := await _live_office()
		var key := _key(KEY_PAGEUP)
		await _parsed(key)
		key.pressed = false
		await _parsed(key)
		_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), removed + ": PageUp shows web")
		var changed := fixture.duplicate(true)
		changed.workspaces = _list(changed, "workspaces").filter(
			func(space: Dictionary) -> bool: return str(space.get("workspace_id", "")) != removed
		)
		_feed(office, changed)
		var expected := HerdrFleet.pane_key(LOCAL, "api" if removed == "web" else "web")
		_eq(office.layout_plan().floor_key, expected, "only a surviving floor is displayed")
		await create_timer(1.1).timeout
		_eq(office.layout_plan().floor_key, expected, "nothing later brings a removed floor back")
		await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "infra"))
		_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "infra"), "the next floor call still works")
		_done(office)


## A floor of a machine that has dropped is still there to look at, dimmed and
## frozen: switching to it turns nobody live and counts nobody blocked.
func test_switching_to_an_offline_floor_invents_no_activity() -> void:
	var office := await _live_office()
	_set_online(office, false)
	var key := _key(KEY_PAGEUP)
	await _parsed(key)
	key.pressed = false
	await _parsed(key)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "a retained offline floor is reachable")
	_check(office.stale, "switching does not turn a disconnected machine live")
	_eq(_playing(office), [false], "all its workers remain frozen")
	var row := office.hud.floors.row_for(HerdrFleet.pane_key(LOCAL, "web"))
	var blocked: Control = row.get_node("%BlockedIcon")
	_check(not blocked.visible, "an offline floor has no live blocked count")
	_done(office)


## herdr's own focus moving to another floor shows that floor the moment the
## snapshot says so, and the latest focus is the one shown.
func test_herdrs_focus_moving_floors_switches_at_once() -> void:
	var office := await _live_office()
	_feed(office, _focused_on(fixture, "web:p1"))
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "remote focus shows its floor at once")
	_feed(office, _focused_on(fixture, "notes:p1"))
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "notes"), "and the latest focus wins")
	_done(office)


## A HUD panel taking room without the window changing size moves the world at
## once: room_changed has the camera ask the HUD again and the office refresh,
## so the camera's room, the world's origin and the plate follow the new
## world_rect() before the next snapshot or resize.
func test_a_room_change_moves_the_world_at_once() -> void:
	var office := await _live_office()
	office.test_screen = Vector2(800, 480)
	office.refresh()
	_eq(office.camera.free_rect().size, Vector2(660, 360), "the room with the drawer closed to its tab")
	office.hud.open_drawer()
	await _frames(1)
	_eq(office.camera.free_rect(), office.hud.world_rect(), "the camera's room is the HUD's new one")
	_eq(office.camera.free_rect().size.x, 536.0, "up to the open drawer")
	_eq(office.world.position, office.camera.free_rect().position, "the world stands in it")
	_eq(office.plate.size.x, office.camera.free_rect().size.x, "and the plate spans it")
	_done(office)


## A window resize that crosses the FLOORS rail's line (`floors_named_from`,
## 1280) moves the column's edge inside the refresh the resize causes
## (camera.free_rect() fits the HUD, and the HUD says room_changed). That
## refresh lays the new room out itself: one refresh per resize, never one
## nested in another. (A resize does not move the staff panel: it is one
## line at every size until opened.)
func test_a_resize_across_the_rail_line_refreshes_once() -> void:
	var office := await _live_office()
	var rooms: Array[bool] = []
	office.hud.room_changed.connect(func() -> void: rooms.append(true))
	for step: Array in [[Vector2(1280, 480), true, 144.0], [Vector2(800, 480), false, 96.0]]:
		var screen: Vector2 = step[0]
		office.refreshes = 0
		office.deepest_refresh = 0
		var said := rooms.size()
		office.test_screen = screen
		office.refresh()
		_check(rooms.size() > said, "%s: the column moved inside the refresh" % screen)
		_eq(office.refreshes, 1, "%s: one refresh" % screen)
		_eq(office.deepest_refresh, 1, "%s: never nested" % screen)
		_eq(office.hud.floors_named(), step[1], "%s: the floors named or the rail" % screen)
		_eq(office.camera.free_rect().position.x, step[2], "%s: the world's room right of it" % screen)
		_check(office.hud.card_compact(), "%s: the staff panel one line throughout" % screen)
		_eq(office.world.position, office.camera.free_rect().position, "%s: the world stands in it" % screen)
		await _frames(2)
		_eq(office.refreshes, 1, "%s: and no refresh after it" % screen)
	_done(office)


## A floor's first plan is made for the window of the refresh that shows it,
## even when that refresh is the resize itself and the camera has not run a
## frame since: the office lays the HUD out for the new window before it asks
## for the width, and that width stays the floor's for good.
func test_the_first_plan_uses_the_window_the_refresh_is_for() -> void:
	var office := await _live_office()
	var web := HerdrFleet.pane_key(LOCAL, "web")
	_check(office.layout_plan().floor_key != web, "web has not been shown yet")
	_eq(office.hud.world_rect().size.x, 660.0, "the HUD is laid out for the 800-wide window")
	# 720 wide leaves the world 580 units with the drawer closed, 18 cells:
	# wider than the floor's own minimum, so the plan's width is the window's,
	# and not the 20 cells the 800-wide window leaves.
	office.test_screen = Vector2(720, 480)
	_feed(office, _focused_on(fixture, "web:p1"))
	_eq(office.layout_plan().floor_key, web, "herdr's focus shows web, planned for the first time")
	_eq(office.hud.world_rect().size.x, 580.0, "the HUD is laid out for the 720-wide window")
	_eq(office.hud.plan_width(), 580.0, "which is the width a first plan asks for")
	_eq(office.layout_plan().initial_width_cells, 18, "and the plan is made for it")
	_done(office)


## Calling the floor already shown, or PageDown on the bottom floor, changes
## nothing: the world is not rebuilt.
func test_the_current_floor_and_the_bottom_rebuild_nothing() -> void:
	var office := await _live_office()
	var before := office.world.get_instance_id()
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "api"))
	_eq(office.world.get_instance_id(), before, "the current floor's call does not rebuild the office")
	await _office_key(office, KEY_PAGEDOWN)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "api"), "the bottom floor stays")
	_eq(office.world.get_instance_id(), before, "and PageDown there does not rebuild it either")
	_done(office)


## Another floor is another world: the minimap, PageDown and herdr's focus
## moving floors all rebuild, and the new floor matches a rebuild from scratch.
func test_floor_change_rebuilds() -> void:
	var office := await _live_office()
	var world_id: int = office.world.get_instance_id()
	var web := HerdrFleet.pane_key(LOCAL, "web")
	await _visit_floor(office, web)
	_eq(office.layout_plan().floor_key, web, "the minimap shows web")
	_check(office.world.get_instance_id() != world_id, "and the floor is rebuilt")
	_check(
		(
			office.floor_view.seats.has(HerdrFleet.pane_key(LOCAL, "web:p1"))
			and not office.floor_view.seats.has(HerdrFleet.pane_key(LOCAL, "api:p1"))
		),
		"with web's desks only"
	)
	await _same_as_rebuild(office, "after the minimap")
	world_id = office.world.get_instance_id()
	await _office_key(office, KEY_PAGEUP)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "infra"), "PageUp goes one floor on")
	_check(office.world.get_instance_id() != world_id, "and rebuilds")
	world_id = office.world.get_instance_id()
	office.navigator.picked_floor = ""
	var focused: Dictionary = fixture.duplicate(true)
	focused.focused_pane_id = "notes:p1"
	_feed(office, focused)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "notes"), "the shown floor follows herdr's focus")
	_check(office.world.get_instance_id() != world_id, "and rebuilds")
	# A status change on the floor the viewer moved to is in place again.
	world_id = office.world.get_instance_id()
	await _visit_floor(office, web)
	world_id = office.world.get_instance_id()
	_feed(office, _with(focused, "web:p1", {"agent_status": "working"}))
	_eq(office.world.get_instance_id(), world_id, "on the new floor a status change is in place")
	# web:p1 was blocked at its seat: it goes back to work where it sits.
	_eq(office.floor_view.presentation.walkers(), [], "web:p1 was blocked at its seat: nobody walks")
	_eq(_worker(office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "web:p1")].node).animation, &"working", "and shows")
	await _same_as_rebuild(office, "on another floor")
	_done(office)


## Floors not drawn are the minimap's business: a change there neither rebuilds
## nor redraws a single node of the shown floor.
func test_other_floor_draws_nothing() -> void:
	var office := await _live_office()
	var world_id: int = office.world.get_instance_id()
	var model: String = office.world_model
	var nodes := _world_ids(office)
	var snapshot := _with(
		_with(_with(fixture, "web:p1", {"agent_status": "working"}), "infra:p2", {"agent_status": "idle"}),
		"data:p2",
		{"launch_pending": false, "agent": null}
	)
	_feed(office, snapshot)
	_eq(office.world.get_instance_id(), world_id, "no rebuild")
	_eq(office.world_model, model, "the layout model is untouched: floor counts stay out of it")
	_eq(_world_ids(office), nodes, "not one node of the shown floor is replaced")
	var web := office.frame.find_floor(HerdrFleet.pane_key(LOCAL, "web")).floor_model
	_eq([web.blocked, web.done], [0, 1], "the minimap's counts moved all the same")
	_done(office)


## A building without floors is a lobby: no desks, nothing to update in place,
## and a machine going stale only relabels it.
func test_lobby_has_no_desks() -> void:
	var office := await _live_office({"workspaces": [], "tabs": [], "panes": [], "layouts": []})
	_check(office.navigator.shown_key.ends_with(HerdrFleet.KEY_SEPARATOR), "an empty session shows the lobby")
	_eq([office.floor_view.seats.size(), _seats(office).size()], [0, 0], "with no desks")
	var world_id: int = office.world.get_instance_id()
	office.refresh()
	_eq(office.world.get_instance_id(), world_id, "a refresh leaves it alone")
	_set_online(office, false)
	_eq(office.world.get_instance_id(), world_id, "going stale only relabels it")
	_eq(office.plate.note_text(), "Waiting for herdr.", "the note says why")
	await _same_as_rebuild(office, "in the lobby")
	_set_online(office, true)
	_feed(office, fixture)
	_check(office.world.get_instance_id() != world_id, "floors arriving rebuild")
	_eq(office.navigator.shown_key, HerdrFleet.pane_key(LOCAL, "api"), "onto the focused floor")
	_done(office)


## A denser pack hands out nodes pre-scaled by 1/density, whatever the screen
## shows; an in-place desk must be the same nodes, scales and offsets a rebuild
## draws. Each family is scaled *and sampled* on its own terms: the pack's props
## and UI, the shared table's chairs, the pixel people's layers. This fixture
## pack declares `nearest` at density 4, so the pack and the table disagree on
## purpose, and its linear twin at the end disagrees with the people: a node
## that took the wrong family's density or filter shows up here.
func test_dense_pack_matches_rebuild() -> void:
	var office := await _live_office()
	office.switch_theme(_dense_pack(4))
	_eq(office.art.density, 4, "the dense pack holds 4px per unit")
	_eq(office.art.filter, CanvasItem.TEXTURE_FILTER_NEAREST, "and asks for nearest on its own art")
	var seat: Node2D = office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "api:p1")].node
	_eq(
		_sprite(seat, "Chair").scale, office.art.table.unit_scale(), "the chair is scaled by the shared table's density"
	)
	_eq(
		_sprite(seat, "Actor/Layers/Body").scale,
		office.art.people.unit_scale(),
		"a worker's layers by the pixel people's density"
	)
	_check(office.art.people.unit_scale() != office.art.unit_scale(), "which is the family's own, not the pack's")
	_eq(
		_sprite(seat, "Overlay/Selection").texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"the pack's own UI samples the way the pack asked"
	)
	_eq(
		_sprite(seat, "Chair").texture_filter,
		office.art.table.filter,
		"the shared table samples the way its own manifest says (nearest), not the pack"
	)
	_eq(
		_sprite(seat, "Actor/Layers/Body").texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"and the pixel people sample nearest: at the even zooms they are never minified"
	)
	var world_id: int = office.world.get_instance_id()
	var snapshot := _with(fixture, "api:p4", {"agent_status": "blocked"})
	_feed(office, snapshot)
	snapshot = _with(snapshot, "api:p3", {"agent": "claude", "agent_status": "done"})
	_feed(office, snapshot)
	await _click_desk(office, HerdrFleet.pane_key(LOCAL, "api:p3"))
	_eq(office.world.get_instance_id(), world_id, "all of it in place")
	var badge := _badge(office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "api:p3")].node)
	_eq(badge.scale, Vector2.ONE / float(office.art.density), "the new badge is scaled back from the pack's density")
	_walked(office, "as the new done worker comes in")
	await _same_as_rebuild(office, "with a dense pack")
	office.switch_theme(_dense_pack(4, "linear"))
	seat = office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "api:p1")].node
	_eq(
		_sprite(seat, "Overlay/Selection").texture_filter,
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		"a linear pack's own UI samples through mipmaps"
	)
	_eq(
		_sprite(seat, "Chair").texture_filter,
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"while its nearest chair stays nearest"
	)
	for layer in PixelPeople.LAYERS:
		var sprite := _sprite(seat, "Actor/" + PixelPeople.SPRITES[layer])
		_eq(
			[sprite.texture_filter, sprite.scale],
			[CanvasItem.TEXTURE_FILTER_NEAREST, Vector2.ONE / float(office.art.people.density)],
			"while a worker's %s keeps the pixel people's nearest and their own density" % layer
		)
	_done(office)


## Zoom is only the window's content scale now: the pack hands out the same
## textures at every zoom, so a zoom change rebuilds nothing by itself. No
## cached model is dropped, no world, station or worker is replaced, and the
## workers keep playing from where they were. The plan retains its original
## row geometry when the visible width changes.
func test_zoom_change_keeps_the_world() -> void:
	var office := await _live_office()
	await _frames(12)
	var world_id: int = office.world.get_instance_id()
	var desks := _desk_ids(office, "")
	var progress := _actor_progress(office, "")
	var model: String = office.world_model
	var hud_nodes := _hud_nodes(office)
	var desk_texture: Texture2D = office.art.sprite_texture(office.art.prop_sprite(&"cabinet"))
	_check(
		progress.values().any(func(p: Array) -> bool: return p[2] > 0.0), "workers have been animating before the zoom"
	)
	for wanted: int in [2, 4, 8, 2]:
		office.zoom = wanted
		office.fit_window()
		_check(
			office.art.sprite_texture(office.art.prop_sprite(&"cabinet")) == desk_texture,
			"zoom %d hands out the same texture" % wanted
		)
	_eq(office.world.get_instance_id(), world_id, "the world was never rebuilt")
	_eq(office.world_model, model, "no cached model was dropped")
	_eq(_hud_nodes(office), hud_nodes, "and the HUD keeps every node it had")
	_eq(_desk_ids(office, ""), desks, "every desk keeps every node")
	_eq(_actor_progress(office, ""), progress, "and every worker its frame and progress")
	await _frames(2)
	_eq(office.world.get_instance_id(), world_id, "still the same world a frame later")
	_eq(_desk_ids(office, ""), desks, "and still every desk")
	office.switch_theme(_second_pack())
	_check(office.world.get_instance_id() != world_id, "a theme switch still rebuilds: its textures are new ones")
	_done(office)


## The HUD is never torn down: the same snapshot twice writes the same text into
## the same labels and creates no node at all, and a change writes text only.
func test_hud_updates_in_place() -> void:
	var office := await _live_office()
	# The agent list builds a group's rows lazily, once, the first time that group
	# exists: a machine's first drop builds its offline group. Drop once before
	# counting, so the count holds it.
	_set_online(office, false)
	_set_online(office, true)
	await _frames(2)
	var hud: OfficeHud = office.hud
	var nodes := _hud_nodes(office)
	_check(nodes.size() > 40, "the HUD is a real scene, not a handful of nodes: %d" % nodes.size())
	_eq(_label(hud.inspector, "%Provider").text, "CLAUDE", "the inspector names the selected pane's agent")
	var portrait: PixelPerson = hud.inspector.portrait()
	_check(portrait != null and portrait.is_playing(), "and its portrait is animating")
	_feed(office, fixture)
	office.refresh()
	_eq(_hud_nodes(office), nodes, "a refresh with the same data creates and frees nothing")
	_eq(hud.inspector.portrait(), portrait, "and the portrait keeps playing across it")
	# A status change is new text in the same labels, never a new node.
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	_eq(_label(hud.inspector, "%Caption").text, "NEEDS INPUT", "a status change reaches the inspector")
	_eq(_hud_nodes(office), nodes, "and still creates no node")
	_eq(hud.inspector.portrait(), portrait, "and reuses the portrait it had")
	# The duration ticks into the inspector's own label, not into a new one.
	_eq(office.attention.inspector, hud.inspector, "attention writes into the inspector's own label")
	var duration: Label = hud.inspector.duration_label()
	office.attention._update_duration()
	_eq(hud.inspector.duration_label(), duration, "the time-in-state never makes a label of its own")
	_eq(_hud_nodes(office), nodes, "which is still no new node")
	# The portrait freezes with its machine and moves again when it is back:
	# the same person throughout, only paused and played.
	_set_online(office, false)
	_check(not portrait.is_playing(), "a dropped machine freezes the card's portrait")
	_eq(hud.inspector.portrait(), portrait, "the same portrait, frozen")
	_set_online(office, true)
	_check(portrait.is_playing(), "and it moves again when the machine is back")
	_eq(_hud_nodes(office), nodes, "freezing and thawing it create no node")
	_set_online(office, false)
	_set_online(office, true)
	_check(portrait.is_playing(), "a second drop and return leave it moving")
	_eq(_hud_nodes(office), nodes, "and create no node either")
	_done(office)


## `T` swaps the art pack: the HUD is re-dressed, never rebuilt.
func test_theme_switch_keeps_the_hud() -> void:
	var office := await _live_office()
	await _frames(2)
	var hud: OfficeHud = office.hud
	var nodes := _hud_nodes(office)
	var before := _screen_of(hud).theme
	var panel: Texture2D = office.art.sprite_texture(office.art.panel())
	# The remembered theme decides what the office starts on; switch to the other.
	var other: String = _second_pack() if office.manifest_path == MANIFESTS[0] else MANIFESTS[0]
	office.switch_theme(other)
	await _frames(2)
	var after := _screen_of(hud).theme
	_check(after != before, "a theme switch builds a new Theme")
	_check(after.get_color("font_color", "Label") != before.get_color("font_color", "Label"), "with the new pack's ink")
	_eq(_hud_nodes(office), nodes, "and keeps every HUD node")
	_check(office.art.sprite_texture(office.art.panel()) != panel, "the panels are dressed from the new pack")
	_eq(hud.floors.art, office.art, "and so is the minimap")
	_done(office)


## Why the tile atlas is padded, and what it costs. Without padding, a content
## scale that is not a whole factor of the cell -- scale 3 on a 128px cell,
## which is what `--zoom=4` gives on the default 1920x960 window -- lets a
## bilinear tap at the cell edge read the neighbouring tile, and a faint seam
## runs down the whole tile -- faint enough that it only shows once you raise
## the contrast. Cell alignment only
## protects how mips are generated, never how they are sampled.
## The cost is that the padded copy carries no mipmaps; that is acceptable while
## the tiles are 32px art upscaled to 128 and transforms snap to whole pixels.
## docs/ASSET_SPEC.md records the way out: extrude the cells in the builder.
func test_tile_atlas_is_padded() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var source: TileSetAtlasSource = art.tileset().get_source(0)
	_check(source.use_texture_padding, "the atlas is padded, so no tap can cross a cell edge")
	# The padded copy is built deferred, on the next frame.
	await _frames(2)
	var runtime := source.get_runtime_texture()
	var cells := source.texture.get_size() / Vector2(art.tileset().tile_size)
	_eq(runtime.get_size(), source.texture.get_size() + cells * 2.0, "one pixel of extrusion around every cell")
	_check(not runtime.get_image().has_mipmaps(), "and no mipmaps on that copy: the known cost")


## The floor's shell lies on the ground, its standing furniture stands in the
## sorted root, and both are furniture: the same floor draws the same shell
## whatever herdr reports, and nothing in it moves when a status does.
func test_the_shell_is_furniture() -> void:
	var office := await _live_office()
	var rooms: Node2D = office.floor_view.root
	var ground: Node2D = rooms.get_node("Ground")
	var sorted: Node2D = rooms.get_node("Sorted")
	var walls := _wall_cells(ground)
	_check(walls.has(ArtContract.wall_cell(ArtContract.WALL_CAP, &"left")), "the wall's left end is on the ground")
	_check(walls.has(ArtContract.wall_cell(ArtContract.WALL_FACE, &"center")), "and its face runs across the floor")
	_check(walls.has(ArtContract.WALL_SIDE_LEFT) and walls.has(ArtContract.WALL_SIDE_RIGHT), "so are both side walls")
	_eq(
		ground.find_children("*", "OfficeDecor", true, false),
		[],
		"nothing that stands on the floor is laid on it instead"
	)
	var standing := _decor(office)
	# Decoration is optional when it would cover a tab's title or obstruct a
	# route. Draw every accepted candidate, and no rejected candidate.
	_eq(
		standing.map(func(piece: OfficeDecor) -> StringName: return piece.piece),
		office.layout_plan().decorations.map(func(piece: DecorPlacement) -> StringName: return piece.piece),
		"the sorted root draws exactly the validated furnishing plan"
	)
	_check(sorted.is_ancestor_of(standing[0]), "and really is a child of it")
	# Where each piece stands, before and after two status changes and a whole
	# machine dropping: a plant does not wilt and a cabinet does not move.
	var placed := standing.map(func(piece: OfficeDecor) -> Array: return [piece.piece, piece.position])
	# The entry band's counters are furniture too, drawn as the plan has them.
	var plan := office.layout_plan()
	var planned: Array = plan.fixtures().map(func(each: FixturePlacement) -> Array: return [each.piece, each.position])
	var counters := _fixtures(office).map(func(piece: OfficeDecor) -> Array: return [piece.piece, piece.position])
	planned.sort()
	counters.sort()
	_eq(counters, planned, "the sorted root draws exactly the planned counters")
	_eq(planned.size(), 2, "a reception and a pantry")
	_feed(office, _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p2", {"agent_status": "done"}))
	_set_online(office, false)
	await _frames(2)
	_eq(
		_decor(office).map(func(piece: OfficeDecor) -> Array: return [piece.piece, piece.position]),
		placed,
		"the same pieces in the same places, whatever herdr says"
	)
	var after := _fixtures(office).map(func(piece: OfficeDecor) -> Array: return [piece.piece, piece.position])
	after.sort()
	_eq(after, counters, "and the counters, whoever is blocked or done")
	_done(office)


## The wall-foot run is planned furniture like the plant and the
## cabinet: the sorted root draws exactly the plan, each piece
## where the plan put it, and neither the plan's pieces, their keys nor where
## they are drawn change when an agent's status or herdr's focus does.
func test_the_new_furniture_keeps_its_keys_through_status_and_focus() -> void:
	var office := await _live_office()
	var planned := _decor_signatures(office.layout_plan())
	var keys := "; ".join(planned)
	# Its tables fill the bay, so it has no spare bay's plant (see the layout
	# and geometry suites for that one).
	_check("/wall/" in keys, "the shown floor has a wall-foot run: " + keys)
	var drawn := _decor_places(office)
	_eq(drawn, _planned_places(office.layout_plan()), "every planned piece is drawn where the plan put it")
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	await _frames(2)
	_feed(office, _focused_on(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p2"))
	await _frames(2)
	_eq(_decor_signatures(office.layout_plan()), planned, "the same pieces under the same keys, whatever herdr says")
	_eq(_decor_places(office), drawn, "drawn in the same places")
	_done(office)


## A floor wide enough for a spare bay draws its standing pieces in the
## plan's own order, the bay's plant included: the sorted root keeps them by
## key, and so does the plan.
func test_a_spare_bay_is_drawn_in_the_plans_order() -> void:
	var office := await _live_office(fixture, Vector2(1600, 800))
	var plan := office.layout_plan()
	var keys := plan.decorations.map(func(piece: DecorPlacement) -> String: return piece.key)
	_check(keys.any(func(key: String) -> bool: return key.ends_with("/bay")), "a floor with a spare bay: %s" % [keys])
	_eq(
		_decor(office).map(func(piece: OfficeDecor) -> String: return "%s@%s" % [piece.piece, piece.position]),
		plan.decorations.map(func(piece: DecorPlacement) -> String: return "%s@%s" % [piece.piece, piece.position]),
		"drawn one for one in the plan's order"
	)
	_done(office)


func _decor_signatures(plan: FloorPlan) -> PackedStringArray:
	var found := PackedStringArray()
	for placed in plan.decorations:
		found.append(placed.geometry_signature())
	found.sort()
	return found


func _decor_places(office: OfficeDouble) -> Array:
	var found := _decor(office).map(func(piece: OfficeDecor) -> String: return "%s@%s" % [piece.piece, piece.position])
	found.sort()
	return found


func _planned_places(plan: FloorPlan) -> Array:
	var found := plan.decorations.map(
		func(piece: DecorPlacement) -> String: return "%s@%s" % [piece.piece, piece.position]
	)
	found.sort()
	return found


## Standing furniture never stands in the way: not on a seat's click target, not
## inside a table's footprint, and not on the walkway people cross the floor by.
func test_standing_furniture_blocks_nothing() -> void:
	var office := await _live_office()
	var standing := _decor(office)
	_check(not standing.is_empty(), "the shown floor really has furniture to check")
	for piece in standing:
		var stands := piece.footprint_rect()
		_check(stands.size.x > 0.0 and stands.size.y > 0.0, "%s stands on something" % piece.piece)
		for station in _seats(office):
			_check(
				not stands.intersects(station.target_rect()),
				"%s is clear of the seat of %s" % [piece.piece, station.pane_key]
			)
		for table: OfficeTable in office.floor_view.tables:
			_check(not stands.intersects(_table_rect(table)), "%s is clear of %s" % [piece.piece, table.name])
		for corridor in office.layout_plan().corridors:
			var walkway := Rect2(
				(
					Vector2(corridor.position * FloorLayoutPolicy.GRID)
					+ office.world.global_position
					+ Vector2(0, OfficeScene.PLATE_HEIGHT)
				),
				Vector2(corridor.size * FloorLayoutPolicy.GRID)
			)
			_check(not stands.intersects(walkway), "%s is clear of every planned walkway" % piece.piece)
	_done(office)


## World rules 2 and 3, for both packs: the floor is ground first, then one
## y-sorted root; every node between that root and a drawn entity is y-sorted
## too (only a table, a worker and an overlay group their own drawing); and
## the only z_index anywhere in the world is OVERLAY_Z.
func test_world_rules() -> void:
	for manifest: String in [MANIFESTS[0], _second_pack()]:
		# A done worker's paper and a blocked worker's bubble, on both sides, so the
		# rules hold for them too.
		var office := await _live_office(
			_with(_with(_both_sides(), "api:p1", {"agent_status": "done"}), "api:p3", {"agent_status": "blocked"})
		)
		office.switch_theme(manifest)
		var rooms: Node2D = office.floor_view.root
		_eq(
			_names(rooms),
			["Ground", "Sorted", "Pointer"],
			"%s: the floor is its ground, then what stands on it, then the hover mark" % manifest
		)
		var sorted: Node2D = rooms.get_node("Sorted")
		var ground: Node2D = rooms.get_node("Ground")
		_check(
			sorted.y_sort_enabled and not ground.y_sort_enabled,
			"%s: only what stands on the floor is sorted" % manifest
		)
		var sprites := sorted.find_children("*", "Sprite2D", true, false)
		_check(
			sprites.size() > 20,
			"%s: the floor has furniture and workers to check (%d sprites)" % [manifest, sprites.size()]
		)
		var loose: Array = []
		for sprite: Node in sprites:
			var entity := _entity_of(sorted, sprite)
			var grouped: bool = (
				# A piece of standing furniture is one entity the same way a table
				# is: its body sorts by the foot its own origin stands on.
				entity == sprite
				or entity is OfficeTable
				or entity is PixelPerson
				or entity is OfficeDecor
				or entity.name == &"Overlay"
			)
			if not grouped:
				loose.append(str(sorted.get_path_to(sprite)))
		_eq(
			loose,
			[],
			"%s: every sprite sorts by its own feet or as part of a table, worker, prop or overlay" % manifest
		)
		for table: OfficeTable in sorted.find_children("*", "OfficeTable", false, false):
			_check(not table.y_sort_enabled, "%s: a table is one entity, drawn in tree order" % manifest)
			# Table children draw over the far workers: task lights stay on the wood.
			var surface := Rect2(0, -OfficeTable.SURFACE_DEPTH, table.width, OfficeTable.SURFACE_DEPTH).grow(0.001)
			var lights: Array = table.get_node("TaskLights").get_children()
			_eq(
				lights.size(),
				table.columns.size() * 2,
				"%s: %s has a far and a near task light per column" % [manifest, table.name]
			)
			for light: Polygon2D in lights:
				for point: Vector2 in light.polygon:
					_check(
						surface.has_point(light.position + point),
						"%s: %s/%s vertex %s lies on the surface" % [manifest, table.name, light.name, point]
					)
		var z_values := {}
		var behind: Array = []
		for item: CanvasItem in office.world.find_children("*", "CanvasItem", true, false):
			if item.z_index != 0:
				z_values[item.z_index] = true
			if item.show_behind_parent:
				behind.append(item.name)
		_eq(z_values.keys(), [OfficeWorld.OVERLAY_Z], "%s: the only z_index in the world is OVERLAY_Z" % manifest)
		_eq(behind, [], "%s: nothing draws behind its parent" % manifest)
		for overlay: Node2D in sorted.find_children("Overlay", "Node2D", true, false):
			_eq(
				overlay.z_index,
				OfficeWorld.OVERLAY_Z,
				"%s: %s floats over the world" % [manifest, sorted.get_path_to(overlay)]
			)
		_done(office)


## Depth follows position, for both packs and every occupied seat: a far
## worker sits between their chair and the table's near edge, a near worker
## between that edge and their chair. Seats come from the table.
func test_sorting_by_position() -> void:
	for manifest: String in [MANIFESTS[0], _second_pack()]:
		var office := await _live_office(_with(fixture, "api:p3", {"agent": "pi"}))
		office.switch_theme(manifest)
		var seen := {}
		for key: String in office.floor_view.seats:
			var station: OfficeStation = office.floor_view.seats[key].node
			var actor := station.actor()
			if actor == null:
				continue
			var table: OfficeTable = station.seat.get_parent().get_parent()
			var chair := _sprite(station, "Chair")
			var ys := [chair.global_position.y, actor.global_position.y, table.global_position.y]
			var where := "%s %s (%s)" % [manifest, key, station.side]
			_eq(actor.global_position, station.seat.global_position, where + ": the worker sits on the table's seat")
			if station.side == "far":
				_check(_rising(ys), where + ": far chair < far worker < table: %s" % [ys])
				_eq(
					[str(actor.look.orientation), str(station.chair_view), str(actor.shown_facing())],
					["front", "front", "front"],
					where + ": faces the viewer"
				)
			else:
				_check(_falling(ys), where + ": table < near worker < near chair: %s" % [ys])
				_eq(
					[str(actor.look.orientation), str(station.chair_view), str(actor.shown_facing())],
					["back", "back", "back"],
					where + ": shows their back"
				)
			seen[station.side] = true
		_eq(seen.keys().size(), 2, manifest + ": the fixture seats workers on both sides")
		# Done and blocked workers sit, and the same seated rule orders them.
		var both := _with(
			_with(_both_sides(), "api:p1", {"agent_status": "done"}), "api:p3", {"agent_status": "blocked"}
		)
		_feed(office, both)
		_eq(office.floor_view.presentation.walkers(), [], manifest + ": nobody gets up")
		var sat := {}
		for key: String in [HerdrFleet.pane_key(LOCAL, "api:p1"), HerdrFleet.pane_key(LOCAL, "api:p3")]:
			var station := _station(office, key)
			var actor := station.actor()
			var chair := _sprite(station, "Chair")
			var ys := [chair.global_position.y, actor.global_position.y, station.table.global_position.y]
			var where := "%s %s done or blocked (%s)" % [manifest, key, station.side]
			_eq(actor.global_position, station.seat.global_position, where + ": on the table's seat")
			_eq(str(actor.look.context), "desk", where + ": at the desk")
			_check(_rising(ys) if station.side == "far" else _falling(ys), where + ": seated depth order: %s" % [ys])
			sat[station.side] = true
		_eq(sat.keys().size(), 2, manifest + ": a done or blocked worker sits on each side")
		_done(office)


## One shape for every worker: the family's layers and nothing else (no chest
## badge: at one texture pixel per unit a person has no room for a logo, so the
## plate says who sits there), one AnimationPlayer that keeps every layer on the
## same frame, and a new state, pose or look that changes what plays and what
## is shown without replacing a node.
func test_actor_rig() -> void:
	var office := await _live_office()
	await _frames(3)
	var station: OfficeStation = office.floor_view.seats[HerdrFleet.pane_key(LOCAL, "api:p1")].node
	var actor := station.actor()
	var people := office.art.people
	var layers := actor.get_node("Layers")
	var drawn: Array = PixelPeople.LAYERS.map(
		func(layer: StringName) -> String: return PixelPeople.SPRITES[layer].get_file()
	)
	_eq(_names(layers), drawn, "the family's layers, bottom to top, and no badge among them")
	_eq(actor.find_children("*", "AnimationPlayer", true, false).size(), 1, "one AnimationPlayer")
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	var ids := _subtree_ids(actor)
	_eq(player.assigned_animation, people.track(AvatarLook.DESK, &"working"), "a working far worker types at the desk")
	for step: float in [0.37, 0.05, 1.21]:
		player.advance(step)
		var frames := _layer_frames(actor)
		_check(_all_same(frames), "every layer shows the same frame after %ss: %s" % [step, frames])
	actor.play_state("blocked")
	_eq(player.assigned_animation, &"desk_blocked", "a new state plays its desk track")
	player.advance(0.6)
	var blocked := _layer_frames(actor)
	_check(
		_all_same(blocked) and _within(people.tracks[&"desk_blocked"], blocked[0]),
		"all layers on a desk_blocked frame: %s" % [blocked]
	)
	var at := player.current_animation_position
	actor.play_state("blocked")
	_eq(player.current_animation_position, at, "the same state again does not restart it")
	_eq(_subtree_ids(actor), ids, "play_state replaces no node")
	for layer in PixelPeople.LAYERS:
		_eq(
			_sprite(actor, PixelPeople.SPRITES[layer]).texture,
			people.layer_texture(layer, actor.look, PixelPeople.FRONT),
			"a far worker faces the viewer: the front strip on %s" % layer
		)
	actor.stand_up()
	_check(not _shape_of(actor).disabled, "standing up collides again")
	_eq(str(actor.look.context), "stand", "in the standing pose")
	_eq(player.assigned_animation, &"stand_blocked", "and plays the standing track")
	player.advance(0.2)
	var standing := _layer_frames(actor)
	_check(
		_all_same(standing) and _within(people.tracks[&"stand_blocked"], standing[0]),
		"all layers on a stand_blocked frame of the same strips: %s" % [standing]
	)
	actor.sit(station.seat)
	_check(_shape_of(actor).disabled, "sitting again takes the feet off")
	_eq(player.assigned_animation, &"desk_blocked", "and plays the desk track again")
	_eq(_subtree_ids(actor), ids, "standing and sitting replace no node")
	var turned := AvatarLook.with_slots({AvatarLook.HAIR_STYLE: &"long", AvatarLook.TOP: &"terra"})
	turned.orientation = AvatarLook.BACK
	actor.configure(people, actor.provider, turned)
	_eq([actor.look.hair_style, actor.look.top], [&"long", &"terra"], "a new look is worn")
	for layer in PixelPeople.LAYERS:
		_eq(
			_sprite(actor, PixelPeople.SPRITES[layer]).texture,
			people.layer_texture(layer, actor.look, PixelPeople.BACK),
			"turned round, %s shows its back strip" % layer
		)
	_eq(player.assigned_animation, &"desk_blocked", "still seated, still blocked")
	_eq(_subtree_ids(actor), ids, "a new look replaces no node")
	_done(office)


## A standing worker walked at a table with move_and_slide() stops at its
## footprint; a seated one does not collide at all.
func test_actor_collision() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var pen := OfficeDraw.new(art)
	var floor_model := Node2D.new()
	root.add_child(floor_model)
	var ground := Node2D.new()
	floor_model.add_child(ground)
	var sorted := Node2D.new()
	sorted.y_sort_enabled = true
	floor_model.add_child(sorted)
	var table := pen.table(sorted, ground, "Table0", Vector2(100, 300), 160, [80.0])
	var far_edge := table.global_position.y - OfficeTable.SURFACE_DEPTH
	var walker: PixelPerson = OfficeDraw.PERSON_SCENE.instantiate()
	walker.configure(art.people, "codex", AvatarLook.facing(AvatarLook.STAND, &""))
	walker.position = Vector2(180, far_edge - 70)
	sorted.add_child(walker)
	_eq(
		[walker.collision_layer, walker.collision_mask, table.collision_layer],
		[OfficeWorld.ACTORS, OfficeWorld.FURNITURE, OfficeWorld.FURNITURE],
		"actors collide with furniture"
	)
	_check(not _shape_of(walker).disabled, "a standing worker has feet")
	await physics_frame
	for step in 90:
		walker.velocity = Vector2(0, 120)
		walker.move_and_slide()
		await physics_frame
	_check(walker.position.y > far_edge - 20, "the worker walked (y %s)" % walker.position.y)
	_check(
		absf(walker.position.y - far_edge) < 1.0,
		"and stopped at the table's far edge %s (y %s)" % [far_edge, walker.position.y]
	)
	var sitter: PixelPerson = OfficeDraw.PERSON_SCENE.instantiate()
	sitter.configure(art.people, "claude")
	sorted.add_child(sitter)
	sitter.sit(table.seat(0, "far"))
	_check(_shape_of(sitter).disabled, "a seated worker's feet are off")
	_eq(sitter.global_position, table.seat(0, "far").global_position, "snapped to the seat")
	root.remove_child(floor_model)
	floor_model.queue_free()


## The table refuses a width it cannot build out of whole modules.
func test_table_width_is_validated() -> void:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	for width: float in [240.0, 128.0, 150.0, 0.0]:
		_check(not OfficeTable.width_error(width).is_empty(), "width %s is refused" % width)
	for width: float in [160.0, 256.0, 512.0]:
		_eq(OfficeTable.width_error(width), "", "width %s is fine" % width)
	var table: OfficeTable = OfficeDraw.TABLE_SCENE.instantiate()
	_check(not table.setup(art, 240.0, [80.0]), "setup() refuses a 240-wide table")
	_eq(
		[table.get_node("Surface").get_child_count(), table.get_node("Seats").get_child_count()],
		[0, 0],
		"and builds none of it"
	)
	table.free()
	var pen := OfficeDraw.new(art)
	var holder := Node2D.new()
	_check(
		pen.table(holder, holder, "Table0", Vector2.ZERO, 240.0, []) == null and holder.get_child_count() == 0,
		"a refused table is never added"
	)
	holder.free()


## A synthetic observation time for duration UI, without an array-shaped clock.
func _set_wait(office: OfficeDouble, pane_id: String, elapsed: float) -> void:
	var now := Time.get_unix_time_from_system()
	var clocks := HerdrClient.carry_states({}, _local(office).snapshot.panes, now)
	clocks[pane_id].since = now - elapsed
	_local(office)._states = clocks


## The instance id of `node` and of everything under it, in tree order.
func _subtree_ids(node: Node) -> Array:
	return (
		[node.get_instance_id()]
		+ node.find_children("*", "", true, false).map(func(each: Node) -> int: return each.get_instance_id())
	)


## Whether strip column `frame` is one of `track`'s frames.
func _within(track: PixelPeople.Track, frame: Variant) -> bool:
	var column: int = frame
	return column >= track.start and column < track.start + track.frame_count()
