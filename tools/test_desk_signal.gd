extends "res://tools/office_test_base.gd"
## Pure: "where is this desk's signal" and "where does this zone open" as
## OfficeFloorView answers them (signal_extent(), arrow_target(), pod_extent(),
## zone_opening()), on a bare floor view built through its public setup() /
## reconcile() / update_desks() with no office, HUD or fleet; and the camera's
## two pan rules as plain arithmetic (OfficeCamera.revealed() / framing() /
## fits() / opened()). The live office's use of them, against the same numbers
## through the paths it always had, is tools/test_desk_signal_wiring.gd's.
##
## godot --headless --path . --script tools/test_desk_signal.gd
##
## The rectangles and pans are what 6413cec drew and panned to on this fixture
## (its own formulas, then in three places, printed before they moved here).
## When a desk's rows (OfficeStation), a pod's measure or the map's plan change
## on purpose, these numbers change with them: a failure prints the new one.

## Where the bare world stands, as the HUD's free corner would put it, and the
## floor's root in it, as the office puts it under the plate.
const ORIGIN := Vector2(148, 26)
const UNDER_PLATE := Vector2(0, 32)
## The width the fixture's map is planned for: two lanes of zones.
const PLAN_WIDTH := 800.0
## A view the size the 800x480 window leaves the world, 148 narrower.
const VIEW := Vector2(512, 308)

## What each pane of the fixture is, so a changed fixture says so first:
## its seat's side, its state as the map draws it, and where it rests.
const SEATED: Dictionary[String, String] = {
	"api:p1": "far working seat",
	"api:p2": "far idle pantry",
	"api:p3": "near shell seat",
	"api:p4": "far working seat",
	"data:p1": "far working seat",
	"data:p2": "near working seat",
	"infra:p1": "far blocked seat chip",
	"infra:p2": "far done seat",
	"infra:p3": "near idle pantry",
	"notes:p1": "far shell seat",
	"web:p1": "far blocked seat chip",
	"web:p2": "near blocked seat chip",
	"web:p3": "far shell seat",
}
## signal_extent(): the click area and, while it shows, the chip.
const EXTENT: Dictionary[String, Rect2] = {
	"api:p1": Rect2(65, 230, 30, 58),
	"api:p2": Rect2(277, 58, 38, 56),
	"api:p3": Rect2(97, 296, 30, 56),
	"api:p4": Rect2(161, 230, 30, 58),
	"data:p1": Rect2(65, 678, 30, 58),
	"data:p2": Rect2(65, 744, 30, 56),
	"infra:p1": Rect2(65, 456, 30, 56),
	"infra:p2": Rect2(161, 454, 30, 58),
	"infra:p3": Rect2(421, 58, 38, 56),
	"notes:p1": Rect2(385, 454, 30, 58),
	"web:p1": Rect2(385, 232, 30, 56),
	"web:p2": Rect2(385, 296, 30, 56),
	"web:p3": Rect2(481, 230, 30, 58),
}
## arrow_target(): the chip alone while it shows, else the click area.
const TARGET: Dictionary[String, Rect2] = {
	"api:p1": Rect2(65, 230, 30, 58),
	"api:p2": Rect2(277, 58, 38, 56),
	"api:p3": Rect2(97, 296, 30, 56),
	"api:p4": Rect2(161, 230, 30, 58),
	"data:p1": Rect2(65, 678, 30, 58),
	"data:p2": Rect2(65, 744, 30, 56),
	"infra:p1": Rect2(65, 456, 30, 16),
	"infra:p2": Rect2(161, 454, 30, 58),
	"infra:p3": Rect2(421, 58, 38, 56),
	"notes:p1": Rect2(385, 454, 30, 58),
	"web:p1": Rect2(385, 232, 30, 16),
	"web:p2": Rect2(385, 336, 30, 16),
	"web:p3": Rect2(481, 230, 30, 58),
}
## pod_extent(): the whole pod the desk stands at.
const POD: Dictionary[String, Rect2] = {
	"api:p1": Rect2(64, 230, 64, 122),
	"api:p2": Rect2(64, 230, 64, 122),
	"api:p3": Rect2(64, 230, 64, 122),
	"api:p4": Rect2(160, 230, 64, 122),
	"data:p1": Rect2(64, 678, 64, 122),
	"data:p2": Rect2(64, 678, 64, 122),
	"infra:p1": Rect2(64, 454, 64, 122),
	"infra:p2": Rect2(160, 454, 64, 122),
	"infra:p3": Rect2(160, 454, 64, 122),
	"notes:p1": Rect2(384, 454, 64, 122),
	"web:p1": Rect2(384, 230, 64, 122),
	"web:p2": Rect2(384, 230, 64, 122),
	"web:p3": Rect2(480, 230, 64, 122),
}
## zone_opening(): as wide as the zone's cells, from its sign's top to the
## bottom of its cells.
const OPENING: Dictionary[String, Rect2] = {
	"api": Rect2(32, 174, 288, 210),
	"web": Rect2(352, 174, 288, 210),
	"infra": Rect2(32, 398, 288, 210),
	"notes": Rect2(352, 398, 288, 210),
	"data": Rect2(32, 622, 288, 210),
}
## Where 6413cec's reveal(key) and reveal(key, true) left the pan of a VIEW-sized
## view of this floor, in the world's coordinates, from each of FROM.
const FROM: Array[Vector2] = [Vector2(0, 0), Vector2(400, 600), Vector2(137.5, 211.25)]
const REVEALED: Dictionary[String, Array] = {
	"api:p1":
	[Vector2(0, 12), Vector2(0, 76), Vector2(65, 230), Vector2(64, 230), Vector2(65, 211.25), Vector2(64, 211.25)],
	"api:p2":
	[Vector2(0, 0), Vector2(0, 0), Vector2(277, 58), Vector2(277, 58), Vector2(137.5, 58), Vector2(137.5, 58)],
	"api:p3":
	[Vector2(0, 76), Vector2(0, 76), Vector2(97, 296), Vector2(64, 230), Vector2(97, 211.25), Vector2(64, 211.25)],
	"api:p4":
	[
		Vector2(0, 12),
		Vector2(0, 76),
		Vector2(161, 230),
		Vector2(160, 230),
		Vector2(137.5, 211.25),
		Vector2(137.5, 211.25)
	],
	"data:p1":
	[Vector2(0, 460), Vector2(0, 524), Vector2(65, 600), Vector2(64, 600), Vector2(65, 460), Vector2(64, 524)],
	"data:p2":
	[Vector2(0, 524), Vector2(0, 524), Vector2(65, 600), Vector2(64, 600), Vector2(65, 524), Vector2(64, 524)],
	"infra:p1":
	[Vector2(0, 236), Vector2(0, 300), Vector2(65, 456), Vector2(64, 454), Vector2(65, 236), Vector2(64, 300)],
	"infra:p2":
	[Vector2(0, 236), Vector2(0, 300), Vector2(161, 454), Vector2(160, 454), Vector2(137.5, 236), Vector2(137.5, 300)],
	"infra:p3":
	[Vector2(0, 0), Vector2(0, 0), Vector2(400, 58), Vector2(400, 58), Vector2(137.5, 58), Vector2(137.5, 58)],
	"notes:p1":
	[Vector2(0, 236), Vector2(0, 300), Vector2(385, 454), Vector2(384, 454), Vector2(137.5, 236), Vector2(137.5, 300)],
	"web:p1":
	[
		Vector2(0, 12),
		Vector2(0, 76),
		Vector2(385, 232),
		Vector2(384, 230),
		Vector2(137.5, 211.25),
		Vector2(137.5, 211.25)
	],
	"web:p2":
	[
		Vector2(0, 76),
		Vector2(0, 76),
		Vector2(385, 296),
		Vector2(384, 230),
		Vector2(137.5, 211.25),
		Vector2(137.5, 211.25)
	],
	"web:p3":
	[
		Vector2(0, 12),
		Vector2(32, 76),
		Vector2(400, 230),
		Vector2(400, 230),
		Vector2(137.5, 211.25),
		Vector2(137.5, 211.25)
	],
}
## Where 6413cec's reveal_zone(zone) left that pan, from each of FROM: the
## zones are 288 wide, narrower than VIEW.
const OPENED: Dictionary[String, Array] = {
	"api": [Vector2(0, 206), Vector2(32, 206), Vector2(32, 206)],
	"web": [Vector2(128, 206), Vector2(352, 206), Vector2(137.5, 206)],
	"infra": [Vector2(0, 430), Vector2(32, 430), Vector2(32, 430)],
	"notes": [Vector2(128, 430), Vector2(352, 430), Vector2(137.5, 430)],
	"data": [Vector2(0, 654), Vector2(32, 654), Vector2(32, 654)],
}
## And of a view 160 wide, narrower than a zone: its left edge, whatever the pan was.
const OPENED_NARROW: Dictionary[String, Vector2] = {
	"api": Vector2(32, 206),
	"web": Vector2(352, 206),
	"infra": Vector2(32, 430),
	"notes": Vector2(352, 430),
	"data": Vector2(32, 654),
}

var art: ArtPack
var pen: OfficeDraw
## The bare world of the case under way; freed after it.
var world: Node2D
## The frame the bare floor was drawn from.
var frame: OfficeFrame


func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	# Both seat sides in every rest (SEATED): web:p2 (near) asks beside web:p1
	# (far), data:p2 (near) works.
	fixture = _dict(fixture_file, "snapshot")
	fixture = _with(_with(fixture, "web:p2", {"agent_status": "blocked"}), "data:p2", {"agent_status": "working"})
	art = ArtPack.from_manifest(MANIFESTS[0])
	if art == null:
		print("TEST_HARNESS_ERROR: the desk signal suite has no art pack")
		quit(2)
		return
	pen = OfficeDraw.new(art)
	_run.call_deferred()


func _run() -> void:
	await run_cases()


func _marker() -> String:
	return "DESK SIGNAL TESTS"


func _after_case() -> void:
	super()
	if is_instance_valid(world):
		world.free()


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The fixture's map on a bare floor view: a world node at `origin` in the
## tree, the floor's root under it at UNDER_PLATE, every desk furnished and
## every worker where they rest.
func _floor_view(origin := ORIGIN) -> OfficeFloorView:
	var machines: Array[MachineView] = [MachineView.new(LOCAL, "LOCAL", HerdrSnapshot.from_wire(fixture), false)]
	frame = OfficeProjection.frame(machines, art.state_names())
	var map := frame.buildings[0].map
	var cache := FloorPlanCache.new()
	var plan := cache.prepare(map, pen, PLAN_WIDTH)
	_eq(cache.problems(), PackedStringArray(), "the fixture's map is planned")
	world = Node2D.new()
	world.position = origin
	root.add_child(world)
	var rooms := Node2D.new()
	rooms.position = UNDER_PLATE
	world.add_child(rooms)
	var view := OfficeFloorView.new()
	view.setup(pen, rooms)
	view.reconcile(plan, map)
	view.update_desks(map, "", false)
	view.settle()
	return view


## What the floor draws for pane `pane_id`, as SEATED says it.
func _seated(view: OfficeFloorView, pane_id: String) -> String:
	var station := view.seat(_pk(pane_id)).node
	var pane := frame.pane(_pk(pane_id))
	var words := PackedStringArray([station.side, "shell" if pane.provider.is_empty() else pane.state])
	words.append("pantry" if station.away() else "seat")
	if station.chip().visible:
		words.append("chip")
	return " ".join(words)


## A floor rectangle in the world's coordinates, as the office hands the camera
## one: by where the floor's root stands in the world.
func _in_world(view: OfficeFloorView, bounds: Rect2) -> Rect2:
	return Rect2(view.root.position + bounds.position, bounds.size)


## All three desk answers for every pane of the fixture, against the tables.
func _answers(view: OfficeFloorView, where: String) -> void:
	for pane_id: String in EXTENT:
		var key := _pk(pane_id)
		_eq(view.signal_extent(key), EXTENT[pane_id], "%s: %s's signal extent" % [where, pane_id])
		_eq(view.arrow_target(key), TARGET[pane_id], "%s: %s's arrow target" % [where, pane_id])
		_eq(view.pod_extent(key), POD[pane_id], "%s: %s's pod extent" % [where, pane_id])
	for zone_id: String in OPENING:
		_eq(view.zone_opening(_pk(zone_id)), OPENING[zone_id], "%s: %s's opening" % [where, zone_id])


# --- where a desk's signal is ---------------------------------------------------


## The signal's extent is where the desk answers a click (the seat's rectangle
## on its side, 30x58 far and 30x56 near; a pantry worker's own 38x56 where
## they stand, away from the pod) together with the chip while it shows: a far
## chip stands on the shortened seat rectangle and a near one hangs under it,
## 30x56 either way. A shell's is its seat's.
func test_a_signal_extent_is_where_the_desk_answers_and_its_chip() -> void:
	var view := _floor_view()
	_eq(view.seats.size(), EXTENT.size(), "every pane of the fixture is seated")
	for pane_id: String in SEATED:
		_eq(_seated(view, pane_id), SEATED[pane_id], "%s is drawn as the tables expect" % pane_id)
		_eq(view.signal_extent(_pk(pane_id)), EXTENT[pane_id], "%s's signal extent" % pane_id)
	for pane_id: String in ["infra:p1", "web:p1", "web:p2"]:
		var station := view.seat(_pk(pane_id)).node
		var extent := view.signal_extent(_pk(pane_id))
		var seat := Rect2(view.root.to_local(station.target_rect().position), station.target_rect().size)
		var chip := Rect2(view.root.to_local(station.chip_rect().position), station.chip_rect().size)
		_check(extent.encloses(seat) and extent.encloses(chip), "%s: the seat and the chip are both in it" % pane_id)
		_check(extent != seat and extent != chip, "%s: and it is neither alone" % pane_id)


## An arrow's target is another answer, and meant to be: the chip alone while
## it shows (30x16, over a far sitter's head, under a near one), and only for a
## desk that shows none where the desk answers a click.
func test_an_arrow_target_is_the_chip_alone_or_where_the_desk_answers() -> void:
	var view := _floor_view()
	for pane_id: String in TARGET:
		_eq(view.arrow_target(_pk(pane_id)), TARGET[pane_id], "%s's arrow target" % pane_id)
	for pane_id: String in SEATED:
		var same := view.arrow_target(_pk(pane_id)) == view.signal_extent(_pk(pane_id))
		_eq(
			same,
			not SEATED[pane_id].ends_with("chip"),
			"%s: the two answers differ exactly while a chip shows" % pane_id
		)
	_eq(view.arrow_target(_pk("web:p1")).size, OfficeStation.CHIP_SIZE, "a chip's own size")


## The pod's extent is the whole pod as drawn, the same for both sides of a
## column and for a worker of it who rests in the pantry.
func test_a_pod_extent_is_the_whole_pod_the_desk_stands_at() -> void:
	var view := _floor_view()
	for pane_id: String in POD:
		_eq(view.pod_extent(_pk(pane_id)), POD[pane_id], "%s's pod extent" % pane_id)
	_eq(view.pod_extent(_pk("api:p2")), view.pod_extent(_pk("api:p1")), "a pantry worker's pod is their desk's")
	_check(not view.pod_extent(_pk("api:p2")).intersects(view.signal_extent(_pk("api:p2"))), "which they are away from")
	var table := view.seat(_pk("web:p1")).node.table
	_eq(view.pod_extent(_pk("web:p1")).size, table.geometry.render_rect.size, "as large as the pod's drawing")


## The answers are in the floor's own coordinates: the same wherever the world
## stands, after the world moves under a floor already drawn (a HUD relayout
## moves it), and with the lens held (which shows a line and hides a chip's
## parts, never the chip).
func test_the_answers_are_the_floors_own_wherever_it_stands() -> void:
	for origin: Vector2 in [Vector2.ZERO, ORIGIN, Vector2(232, 26)]:
		var view := _floor_view(origin)
		_answers(view, "the world at %s" % origin)
		world.position = Vector2(96, 48)
		_answers(view, "the world moved from %s" % origin)
		var texts: Dictionary[String, String] = {}
		for key: String in view.seats:
			texts[key] = "12m"
		var tones: Dictionary[String, StringName] = {}
		view.show_lens(true, texts, tones)
		var line: Label = view.seat(_pk("api:p1")).node.get_node("Overlay/Lens")
		_check(line.visible, "the lens line shows")
		_answers(view, "the lens held, from %s" % origin)
		view.show_lens(false, texts, tones)
		_answers(view, "the lens let go, from %s" % origin)
		world.free()


## A pane with no seat here has no signal: every answer is a rectangle with no
## area, for a key the floor does not seat, for no key, and on a floor nothing
## was laid out on. A seated pane's always has one.
func test_a_pane_with_no_seat_has_no_signal() -> void:
	var view := _floor_view()
	for key: String in [_pk("nobody:p9"), "", "api:p1"]:
		_eq(view.signal_extent(key), Rect2(), "no extent for %s" % var_to_str(key))
		_eq(view.arrow_target(key), Rect2(), "no arrow target for %s" % var_to_str(key))
		_eq(view.pod_extent(key), Rect2(), "no pod for %s" % var_to_str(key))
	for key: String in view.seats:
		_check(view.signal_extent(key).has_area(), "%s: a seat's extent has an area" % key)
		_check(view.arrow_target(key).has_area(), "%s: and its arrow target" % key)
		_check(view.pod_extent(key).has_area(), "%s: and its pod" % key)
	var empty := OfficeFloorView.new()
	var rooms := Node2D.new()
	world.add_child(rooms)
	empty.setup(pen, rooms)
	_eq(empty.signal_extent(_pk("api:p1")), Rect2(), "a floor not laid out seats nobody")
	_eq(empty.zone_opening(_pk("api")), Rect2(), "and opens no zone")


## point() frames the signal's extent: grown by OfficePointer.GROW all round,
## on whole units, under the pane's key. Nothing, or a pane with no seat here,
## clears the pointer.
func test_pointing_frames_the_signal_extent() -> void:
	var view := _floor_view()
	var pointer := view.pointer
	_check(not pointer.visible, "nothing pointed at yet")
	for pane_id: String in EXTENT:
		view.point(_pk(pane_id))
		_eq([pointer.key, pointer.visible], [_pk(pane_id), true], "the pointer is at %s" % pane_id)
		_eq(pointer.rect, EXTENT[pane_id].grow(OfficePointer.GROW), "around %s's extent, two units off" % pane_id)
	_eq(pointer.rect, Rect2(479, 228, 34, 62), "the last one, web:p3, as 6413cec framed it")
	view.point(_pk("web:p1"))
	_eq(pointer.rect, Rect2(383, 230, 34, 60), "a blocked desk's frame takes its chip in")
	view.point("")
	_eq([pointer.key, pointer.visible, pointer.rect], ["", false, Rect2()], "pointing at nothing clears it")
	view.point(_pk("web:p1"))
	view.point(_pk("nobody:p9"))
	_eq([pointer.key, pointer.visible], ["", false], "and so does a pane with no seat here")


# --- where a zone opens -----------------------------------------------------------


## A zone opens from the top of its sign's drawing, in the aisle row above it,
## across its cells and down to their bottom; from the aisle row's own top
## when its sign is not drawn; and nowhere when the plan does not place it.
func test_a_zone_opens_at_its_signs_top_across_its_cells() -> void:
	var view := _floor_view()
	_eq(view.plan.zones.size(), OPENING.size(), "every zone of the fixture is placed")
	var grid := float(FloorLayoutPolicy.GRID)
	for zone_id: String in OPENING:
		var opening := view.zone_opening(_pk(zone_id))
		_eq(opening, OPENING[zone_id], "%s's opening" % zone_id)
		var cells := view.plan.zone(_pk(zone_id)).cells
		_eq(
			[opening.position.x, opening.end.x],
			[cells.position.x * grid, cells.end.x * grid],
			"%s: as wide as its cells" % zone_id
		)
		_eq(opening.end.y, cells.end.y * grid, "%s: down to their bottom" % zone_id)
		var aisle := (cells.position.y - 1) * grid
		_check(
			opening.position.y > aisle and opening.position.y < aisle + grid,
			"%s: its top inside its aisle row" % zone_id
		)
		var board := view.zone_sign(_pk(zone_id))
		_eq(opening.position.y, board.drawn_rect().position.y, "%s: at the top of its sign's drawing" % zone_id)
	_eq(view.zone_opening(_pk("nowhere")), Rect2(), "a zone the plan does not place opens nowhere")
	_eq(view.zone_opening(""), Rect2(), "and no key")
	var board := view.zone_sign(_pk("api"))
	board.get_parent().remove_child(board)
	_eq(view.zone_opening(_pk("api")), Rect2(32, 160, 288, 224), "api without its sign drawn: from its aisle row's top")
	_eq(view.zone_opening(_pk("web")), OPENING["web"], "the others keep theirs")
	board.free()


# --- the camera's two pan rules ---------------------------------------------------


## revealed() moves the pan just enough: not at all for what is already in
## view with its headroom, to the far edge for what lies right or below, to the
## near edge (the headroom's top) for what lies left or above, and to the
## top-left of what is larger than the view. Each axis on its own.
func test_revealing_pans_just_enough_with_headroom() -> void:
	var room := Vector2(300, 200)
	var head := OfficeCamera.REVEAL_HEADROOM
	_eq(head, 32.0, "32 units kept above a revealed desk")
	var desk := Rect2(400, 300, 30, 58)
	_eq(OfficeCamera.revealed(Vector2(200, 250), desk, room), Vector2(200, 250), "already in view: no move")
	_eq(
		OfficeCamera.revealed(Vector2(400, 268), desk, room),
		Vector2(400, 268),
		"exactly at the left and under the headroom"
	)
	_eq(OfficeCamera.revealed(Vector2(401, 269), desk, room), Vector2(400, 268), "a unit past either: back to them")
	_eq(OfficeCamera.revealed(Vector2(130, 158), desk, room), Vector2(130, 158), "exactly at the right and the bottom")
	_eq(OfficeCamera.revealed(Vector2(129, 157), desk, room), Vector2(130, 158), "a unit short of either: on to them")
	_eq(OfficeCamera.revealed(Vector2.ZERO, desk, room), Vector2(130, 158), "from the top left: its far edges come in")
	_eq(
		OfficeCamera.revealed(Vector2(900, 900), desk, room),
		Vector2(400, 268),
		"from beyond: its near edges, headroom above"
	)
	_eq(OfficeCamera.revealed(Vector2(0, 280), desk, room), Vector2(130, 268), "each axis moves on its own")
	_eq(
		OfficeCamera.revealed(Vector2(137.5, 211.25), desk, room),
		Vector2(137.5, 211.25),
		"a pan between units stays there"
	)
	var wide := Rect2(100, 300, 500, 400)
	_eq(OfficeCamera.revealed(Vector2.ZERO, wide, room), Vector2(100, 268), "larger than the view: its top-left wins")
	_eq(OfficeCamera.revealed(Vector2(900, 900), wide, room), Vector2(100, 268), "from either side")
	_eq(
		OfficeCamera.revealed(Vector2(-50, -50), Rect2(10, 40, 30, 58), room),
		Vector2(-50, -50),
		"never clamped to a map"
	)


## The pod joins a desk's framing only when the two together fit the view with
## the headroom: exactly fitting they do, one unit short on either axis the
## desk stays alone, and a pantry worker far above their pod is framed alone.
func test_the_pod_joins_the_framing_only_when_both_fit() -> void:
	var desk := Rect2(65, 262, 30, 58)
	var pod := Rect2(64, 262, 64, 122)
	var both := Rect2(64, 262, 64, 122)
	_eq(desk.merge(pod), both, "a far desk and its pod together are the pod")
	var head := OfficeCamera.REVEAL_HEADROOM
	_check(OfficeCamera.fits(both, Vector2(64, 122 + head)), "exactly as large as the view under its headroom: fits")
	_check(not OfficeCamera.fits(both, Vector2(63, 122 + head)), "one unit too wide: does not")
	_check(not OfficeCamera.fits(both, Vector2(64, 121 + head)), "one unit too tall: does not")
	_check(not OfficeCamera.fits(both, Vector2(64, 122)), "the headroom counts")
	_eq(OfficeCamera.framing(desk, pod, Vector2(64, 154)), both, "fitting: the desk with its pod")
	_eq(OfficeCamera.framing(desk, pod, Vector2(63, 154)), desk, "too wide by one: the desk alone")
	_eq(OfficeCamera.framing(desk, pod, Vector2(64, 153)), desk, "too tall by one: the desk alone")
	_eq(OfficeCamera.framing(desk, Rect2(), Vector2(64, 154)), desk, "no pod asked for: the desk alone")
	_eq(OfficeCamera.framing(desk, Rect2(), Vector2(10, 10)), desk, "whatever the view")
	# A near desk's chip hangs under the sitter, still inside the pod's drawing.
	var near := Rect2(385, 328, 30, 56)
	var near_pod := Rect2(384, 262, 64, 122)
	_eq(OfficeCamera.framing(near, near_pod, VIEW), Rect2(384, 262, 64, 122), "a near desk inside its pod's drawing")
	# The fixture's pantry worker, 172 units above their pod.
	var view := _floor_view()
	var worker := _in_world(view, view.signal_extent(_pk("api:p2")))
	var their_pod := _in_world(view, view.pod_extent(_pk("api:p2")))
	_eq(worker.merge(their_pod), Rect2(64, 90, 251, 294), "a pantry worker and their pod together")
	_check(not OfficeCamera.fits(worker.merge(their_pod), VIEW), "do not fit a 512x308 view under its headroom")
	_eq(OfficeCamera.framing(worker, their_pod, VIEW), worker, "so the worker is framed alone")
	_eq(
		OfficeCamera.framing(worker, their_pod, Vector2(512, 326)),
		worker.merge(their_pod),
		"and with the pod where both fit"
	)


## opened() is another rule: the opening's top at the view's top whatever the
## pan was and with no headroom, and sideways as little as brings its width in,
## or its left edge when it is wider than the view.
func test_opening_pans_to_the_top_and_as_little_sideways() -> void:
	var zone := Rect2(352, 206, 288, 210)
	var room := Vector2(512, 308)
	_eq(OfficeCamera.opened(Vector2(200, 999), zone, room), Vector2(200, 206), "in view sideways: only the top moves")
	_eq(OfficeCamera.opened(Vector2(200, 0), zone, room), Vector2(200, 206), "from above as from below, no headroom")
	_eq(OfficeCamera.opened(Vector2(0, 0), zone, room), Vector2(128, 206), "from the left: its right edge comes in")
	_eq(OfficeCamera.opened(Vector2(127, 0), zone, room), Vector2(128, 206), "a unit short of it")
	_eq(OfficeCamera.opened(Vector2(128, 0), zone, room), Vector2(128, 206), "exactly at it")
	_eq(OfficeCamera.opened(Vector2(352, 0), zone, room), Vector2(352, 206), "exactly at its left edge")
	_eq(OfficeCamera.opened(Vector2(353, 0), zone, room), Vector2(352, 206), "a unit past it: back to its left edge")
	_eq(OfficeCamera.opened(Vector2(900, 0), zone, room), Vector2(352, 206), "from the right: its left edge")
	_eq(
		OfficeCamera.opened(Vector2(0, 0), zone, Vector2(288, 308)),
		Vector2(352, 206),
		"exactly as wide as the view: fits at its left"
	)
	_eq(
		OfficeCamera.opened(Vector2(0, 0), zone, Vector2(287, 308)),
		Vector2(352, 206),
		"a unit wider than the view: its left edge"
	)
	_eq(
		OfficeCamera.opened(Vector2(500, 0), zone, Vector2(160, 120)),
		Vector2(352, 206),
		"wider than the view: its left edge, from anywhere"
	)
	_eq(OfficeCamera.opened(Vector2(0, 0), zone, Vector2(160, 120)), Vector2(352, 206), "from either side")
	_check(
		OfficeCamera.opened(Vector2(0, 0), zone, room) != OfficeCamera.revealed(Vector2(0, 0), zone, room),
		"not the rule a desk is revealed by"
	)


## The floor's answers, handed to the camera's rules as the office hands them
## (in the world's coordinates: by where the floor's root stands in it), pan a
## 512x308 view exactly where 6413cec's reveal() and reveal_zone() panned it:
## every desk alone and with its pod, every zone, from three pans.
func test_the_floors_answers_pan_the_view_where_it_was_panned() -> void:
	var view := _floor_view()
	_eq(view.root.position, UNDER_PLATE, "the floor's root stands under the plate")
	for pane_id: String in REVEALED:
		var extent := _in_world(view, view.signal_extent(_pk(pane_id)))
		var pod := _in_world(view, view.pod_extent(_pk(pane_id)))
		var pans := []
		for from: Vector2 in FROM:
			pans.append(OfficeCamera.revealed(from, OfficeCamera.framing(extent, Rect2(), VIEW), VIEW))
			pans.append(OfficeCamera.revealed(from, OfficeCamera.framing(extent, pod, VIEW), VIEW))
		_eq(pans, REVEALED[pane_id], "%s revealed alone and with its pod, from each pan" % pane_id)
	for zone_id: String in OPENED:
		var opening := _in_world(view, view.zone_opening(_pk(zone_id)))
		var pans := []
		for from: Vector2 in FROM:
			pans.append(OfficeCamera.opened(from, opening, VIEW))
			_eq(
				OfficeCamera.opened(from, opening, Vector2(160, 120)),
				OPENED_NARROW[zone_id],
				"%s in a narrow view" % zone_id
			)
		_eq(pans, OPENED[zone_id], "%s opened from each pan" % zone_id)
	var board := view.zone_sign(_pk("api"))
	board.get_parent().remove_child(board)
	var bare := _in_world(view, view.zone_opening(_pk("api")))
	_eq(
		OfficeCamera.opened(Vector2(400, 600), bare, VIEW),
		Vector2(32, 192),
		"api without its sign: its aisle row's top"
	)
	board.free()


# --- what an arrow asks -----------------------------------------------------------


## An arrow stands while its desk's target does not meet the view
## (EdgeArrowModel.of()), and the target is the chip alone: with the view's top
## edge at the chip's bottom the arrow stands although the seat under the chip
## is in view, and a unit of the chip in view takes it away; the same at the
## view's left edge. Its edge and its place along it are the chip's, not the
## extent's.
func test_an_arrow_stands_by_its_target_not_by_the_extent() -> void:
	var view := _floor_view()
	var chip := view.arrow_target(_pk("web:p1"))
	var extent := view.signal_extent(_pk("web:p1"))
	_eq([chip, extent], [Rect2(385, 232, 30, 16), Rect2(385, 232, 30, 56)], "web:p1's chip, and its chip over its seat")
	var target := EdgeArrowModel.Target.new()
	target.zone_key = _pk("web")
	target.pane_key = _pk("web:p1")
	target.rect = chip
	var targets: Array[EdgeArrowModel.Target] = [target]
	# The view's top edge against the chip's bottom edge.
	var under := Rect2(Vector2(0, chip.end.y), VIEW)
	_check(extent.intersects(under), "the seat is in the view under the chip")
	var arrows := EdgeArrowModel.of(under, targets)
	_eq(arrows.size(), 1, "the chip just above the view: its arrow")
	_eq(
		[arrows[0].pane_key, arrows[0].blocked, arrows[0].edge],
		[_pk("web:p1"), 1, EdgeArrowModel.Edge.TOP],
		"on the top edge"
	)
	_eq("%.4f" % arrows[0].along, "0.7674", "along it toward the chip")
	_check(
		arrows[0].along != EdgeArrowModel.along_toward(under, extent),
		"which is not where the extent's middle would put it"
	)
	_eq(
		EdgeArrowModel.of(Rect2(Vector2(0, chip.end.y - 1), VIEW), targets).size(),
		0,
		"a unit of the chip in view: none"
	)
	# The view's left edge against the chip's right edge.
	var beside := Rect2(Vector2(chip.end.x, 100), VIEW)
	arrows = EdgeArrowModel.of(beside, targets)
	_eq(arrows.size(), 1, "the chip just left of the view: its arrow")
	_eq([arrows[0].blocked, arrows[0].edge], [1, EdgeArrowModel.Edge.LEFT], "on the left edge")
	_eq("%.4f" % arrows[0].along, "0.4571", "along it toward the chip")
	_eq(
		EdgeArrowModel.of(Rect2(Vector2(chip.end.x - 1, 100), VIEW), targets).size(),
		0,
		"a unit of the chip in view: none"
	)
	# A near seat's chip hangs under the sitter: the view's bottom edge at its top.
	var near := view.arrow_target(_pk("web:p2"))
	var near_extent := view.signal_extent(_pk("web:p2"))
	target.rect = near
	var over := Rect2(Vector2(0, near.position.y - VIEW.y), VIEW)
	_check(near_extent.intersects(over), "the near seat is in the view over its chip")
	arrows = EdgeArrowModel.of(over, targets)
	_eq(
		[arrows.size(), arrows[0].edge],
		[1, EdgeArrowModel.Edge.BOTTOM],
		"the chip just below the view: its arrow, below"
	)
	_eq(EdgeArrowModel.of(Rect2(over.position + Vector2(0, 1), VIEW), targets).size(), 0, "a unit of it in view: none")
