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
## Independent workstation geometry: every two-column pod reserves 7x10
## cells; two pods need four lanes to stand side by side. On this four-lane
## map api, web and infra occupy successive 11-cell bands, then notes and data
## share the last band. Pod origins are (64, 320), (288, 320), then +352 in y.
## A foot is (48 + 96*column, -128 or 0) from its pod. Its 80x80 canvas starts
## (-37.5, -70) from the foot; a blocked chip starts (-15, 12), size 30x16.
## The stable signal is (-47, -70, 94, 124), including every annotation row.
## Tables below are measured from that contract, not sampled from the runtime.

## Where the bare world stands, as the HUD's free corner would put it, and the
## floor's root in it, as the office puts it under the plate.
const ORIGIN := Vector2(148, 26)
const UNDER_PLATE := Vector2(0, 32)
## Four lanes, 23x46 cells; the view need not show the whole planned map.
const PLAN_WIDTH := 800.0
## A view that fits a 192x256 pod with 32 units of headroom.
const VIEW := Vector2(512, 308)

## Logical row and semantic whole-image state, with no detachable desk items.
const SEATED: Dictionary[String, String] = {
	"api:p1": "far working seat",
	"api:p2": "far idle seat",
	"api:p3": "near shell seat",
	"api:p4": "far working seat",
	"data:p1": "far working seat",
	"data:p2": "near working seat",
	"infra:p1": "far blocked seat chip",
	"infra:p2": "far done seat",
	"infra:p3": "near idle seat",
	"notes:p1": "far shell seat",
	"web:p1": "far blocked seat chip",
	"web:p2": "near blocked seat chip",
	"web:p3": "far shell seat",
}
## signal_extent(): the image and all reserved annotation rows, in every state.
const EXTENT: Dictionary[String, Rect2] = {
	"api:p1": Rect2(65, 122, 94, 124),
	"api:p2": Rect2(161, 122, 94, 124),
	"api:p3": Rect2(161, 250, 94, 124),
	"api:p4": Rect2(289, 122, 94, 124),
	"data:p1": Rect2(385, 1178, 94, 124),
	"data:p2": Rect2(385, 1306, 94, 124),
	"infra:p1": Rect2(65, 826, 94, 124),
	"infra:p2": Rect2(289, 826, 94, 124),
	"infra:p3": Rect2(289, 954, 94, 124),
	"notes:p1": Rect2(65, 1178, 94, 124),
	"web:p1": Rect2(65, 474, 94, 124),
	"web:p2": Rect2(65, 602, 94, 124),
	"web:p3": Rect2(289, 474, 94, 124),
}
## arrow_target(): the chip alone while it shows, else the click area.
const TARGET: Dictionary[String, Rect2] = {
	"api:p1": Rect2(74.5, 122, 80, 80),
	"api:p2": Rect2(170.5, 122, 80, 80),
	"api:p3": Rect2(170.5, 250, 80, 80),
	"api:p4": Rect2(298.5, 122, 80, 80),
	"data:p1": Rect2(394.5, 1178, 80, 80),
	"data:p2": Rect2(394.5, 1306, 80, 80),
	"infra:p1": Rect2(97, 908, 30, 16),
	"infra:p2": Rect2(298.5, 826, 80, 80),
	"infra:p3": Rect2(298.5, 954, 80, 80),
	"notes:p1": Rect2(74.5, 1178, 80, 80),
	"web:p1": Rect2(97, 556, 30, 16),
	"web:p2": Rect2(97, 684, 30, 16),
	"web:p3": Rect2(298.5, 474, 80, 80),
}
## pod_extent(): the whole pod the desk stands at.
const POD: Dictionary[String, Rect2] = {
	"api:p1": Rect2(64, 120, 192, 256),
	"api:p2": Rect2(64, 120, 192, 256),
	"api:p3": Rect2(64, 120, 192, 256),
	"api:p4": Rect2(288, 120, 192, 256),
	"data:p1": Rect2(384, 1176, 192, 256),
	"data:p2": Rect2(384, 1176, 192, 256),
	"infra:p1": Rect2(64, 824, 192, 256),
	"infra:p2": Rect2(288, 824, 192, 256),
	"infra:p3": Rect2(288, 824, 192, 256),
	"notes:p1": Rect2(64, 1176, 192, 256),
	"web:p1": Rect2(64, 472, 192, 256),
	"web:p2": Rect2(64, 472, 192, 256),
	"web:p3": Rect2(288, 472, 192, 256),
}
## zone_opening(): as wide as the zone's cells, from its sign's top to the
## bottom of its cells.
const OPENING: Dictionary[String, Rect2] = {
	"api": Rect2(32, 82, 608, 334),
	"web": Rect2(32, 434, 608, 334),
	"infra": Rect2(32, 786, 608, 334),
	"notes": Rect2(32, 1138, 288, 334),
	"data": Rect2(352, 1138, 288, 334),
}
## The closest pan in the containment interval for the signal, then its pod,
## from each of FROM. World y adds 32 for the plate, headroom subtracts 32:
## api:p1's valid vertical pans are [-30, 122], its pod's are [100, 120].
const FROM: Array[Vector2] = [Vector2(0, 0), Vector2(400, 600), Vector2(137.5, 211.25)]
const REVEALED: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 0), Vector2(0, 100), Vector2(65, 122), Vector2(64, 120), Vector2(65, 122), Vector2(64, 120)],
	"api:p2":
	[Vector2(0, 0), Vector2(0, 100), Vector2(161, 122), Vector2(64, 120), Vector2(137.5, 122), Vector2(64, 120)],
	"api:p3":
	[Vector2(0, 98), Vector2(0, 100), Vector2(161, 250), Vector2(64, 120), Vector2(137.5, 211.25), Vector2(64, 120)],
	"api:p4":
	[Vector2(0, 0), Vector2(0, 100), Vector2(289, 122), Vector2(288, 120), Vector2(137.5, 122), Vector2(137.5, 120)],
	"data:p1":
	[
		Vector2(0, 1026),
		Vector2(64, 1156),
		Vector2(385, 1026),
		Vector2(384, 1156),
		Vector2(137.5, 1026),
		Vector2(137.5, 1156)
	],
	"data:p2":
	[
		Vector2(0, 1154),
		Vector2(64, 1156),
		Vector2(385, 1154),
		Vector2(384, 1156),
		Vector2(137.5, 1154),
		Vector2(137.5, 1156)
	],
	"infra:p1":
	[Vector2(0, 674), Vector2(0, 804), Vector2(65, 674), Vector2(64, 804), Vector2(65, 674), Vector2(64, 804)],
	"infra:p2":
	[Vector2(0, 674), Vector2(0, 804), Vector2(289, 674), Vector2(288, 804), Vector2(137.5, 674), Vector2(137.5, 804)],
	"infra:p3":
	[Vector2(0, 802), Vector2(0, 804), Vector2(289, 802), Vector2(288, 804), Vector2(137.5, 802), Vector2(137.5, 804)],
	"notes:p1":
	[Vector2(0, 1026), Vector2(0, 1156), Vector2(65, 1026), Vector2(64, 1156), Vector2(65, 1026), Vector2(64, 1156)],
	"web:p1":
	[Vector2(0, 322), Vector2(0, 452), Vector2(65, 474), Vector2(64, 472), Vector2(65, 322), Vector2(64, 452)],
	"web:p2":
	[Vector2(0, 450), Vector2(0, 452), Vector2(65, 600), Vector2(64, 472), Vector2(65, 450), Vector2(64, 452)],
	"web:p3":
	[Vector2(0, 322), Vector2(0, 452), Vector2(289, 474), Vector2(288, 472), Vector2(137.5, 322), Vector2(137.5, 452)],
}
## The three 608-wide zones exceed VIEW; the two 288-wide zones fit.
const OPENED: Dictionary[String, Array] = {
	"api": [Vector2(32, 114), Vector2(32, 114), Vector2(32, 114)],
	"web": [Vector2(32, 466), Vector2(32, 466), Vector2(32, 466)],
	"infra": [Vector2(32, 818), Vector2(32, 818), Vector2(32, 818)],
	"notes": [Vector2(0, 1170), Vector2(32, 1170), Vector2(32, 1170)],
	"data": [Vector2(128, 1170), Vector2(352, 1170), Vector2(137.5, 1170)],
}
## And of a view NARROW wide, narrower than a zone: its left edge, whatever the pan was.
const NARROW := Vector2(96, 120)
const OPENED_NARROW: Dictionary[String, Vector2] = {
	"api": Vector2(32, 114),
	"web": Vector2(32, 466),
	"infra": Vector2(32, 818),
	"notes": Vector2(32, 1170),
	"data": Vector2(352, 1170),
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
	# Both seat sides in every state (SEATED): web:p2 (near) asks beside web:p1
	# (far), data:p2 (near) works.
	fixture = _dict(fixture_file, "snapshot")
	fixture = _with(
		_with(fixture, "web:p2", {"agent_status": "blocked"}),
		"data:p2",
		{"agent_status": "working", "launch_pending": false}
	)
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
## every worker in their seat.
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
	return view


## What the floor draws for pane `pane_id`, as SEATED says it.
func _seated(view: OfficeFloorView, pane_id: String) -> String:
	var station := view.seat(_pk(pane_id)).node
	var worker := station.actor()
	var words := PackedStringArray([station.side, "shell" if worker == null else String(worker.animation)])
	words.append("seat" if worker == null or worker.position == Vector2.ZERO else "away")
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


## Every state, shells included, answers across the whole 80x80 canvas. The
## stable 94x124 signal also keeps the chip, badge, lens and complete name row;
## changing state never changes that reservation.
func test_a_signal_extent_is_where_the_desk_answers_and_its_chip() -> void:
	var view := _floor_view()
	_eq(view.seats.size(), EXTENT.size(), "every pane of the fixture is seated")
	for pane_id: String in SEATED:
		_eq(_seated(view, pane_id), SEATED[pane_id], "%s is drawn as the tables expect" % pane_id)
		_eq(view.signal_extent(_pk(pane_id)), EXTENT[pane_id], "%s's signal extent" % pane_id)
		var station := view.seat(_pk(pane_id)).node
		var seat := Rect2(view.root.to_local(station.target_rect().position), station.target_rect().size)
		var canvas := Rect2(EXTENT[pane_id].position + Vector2(9.5, 0), Vector2(80, 80))
		_eq(seat, canvas, "%s: the entire image, not its annotation rows, answers a click" % pane_id)
	for pane_id: String in ["infra:p1", "web:p1", "web:p2"]:
		var station := view.seat(_pk(pane_id)).node
		var extent := view.signal_extent(_pk(pane_id))
		var seat := Rect2(view.root.to_local(station.target_rect().position), station.target_rect().size)
		var chip := Rect2(view.root.to_local(station.chip_rect().position), station.chip_rect().size)
		_eq(chip.position.y - seat.end.y, 2.0, "%s: the chip stays two units below the image" % pane_id)
		_check(extent.encloses(seat) and extent.encloses(chip), "%s: the seat and the chip are both in it" % pane_id)
		_check(extent != seat and extent != chip, "%s: and it is neither alone" % pane_id)
	var changing := view.seat(_pk("web:p1")).node
	for state: StringName in [&"working", &"idle", &"done", &"blocked"]:
		changing.furnish("claude", state, true)
		_eq(view.signal_extent(_pk("web:p1")), Rect2(65, 474, 94, 124), "%s keeps every annotation row" % state)
	changing.furnish("claude", &"working", true, true)
	_eq(view.signal_extent(_pk("web:p1")), Rect2(65, 474, 94, 124), "starting keeps every annotation row")
	changing.furnish("", &"idle", true)
	_eq(view.signal_extent(_pk("web:p1")), Rect2(65, 474, 94, 124), "a shell keeps every annotation row")


## An arrow's target is another answer, and meant to be: the chip alone while
## it shows (30x16 below either row's workstation), and only for a
## desk that shows none where the desk answers a click.
func test_an_arrow_target_is_the_chip_alone_or_where_the_desk_answers() -> void:
	var view := _floor_view()
	for pane_id: String in TARGET:
		_eq(view.arrow_target(_pk(pane_id)), TARGET[pane_id], "%s's arrow target" % pane_id)
	for pane_id: String in SEATED:
		var target := view.arrow_target(_pk(pane_id))
		var extent := view.signal_extent(_pk(pane_id))
		_check(extent.encloses(target) and target != extent, "%s: arrows never aim at the annotation reserve" % pane_id)
		var size := Vector2(30, 16) if SEATED[pane_id].ends_with("chip") else Vector2(80, 80)
		_eq(target.size, size, "%s: only the visible chip replaces the canvas target" % pane_id)
	_eq(view.arrow_target(_pk("web:p1")).size, Vector2(30, 16), "a chip's own size")


## The pod's extent is the whole pod as drawn, the same for both sides of a
## column and for an idle worker of it.
func test_a_pod_extent_is_the_whole_pod_the_desk_stands_at() -> void:
	var view := _floor_view()
	for pane_id: String in POD:
		_eq(view.pod_extent(_pk(pane_id)), POD[pane_id], "%s's pod extent" % pane_id)
	_eq(view.pod_extent(_pk("api:p2")), view.pod_extent(_pk("api:p1")), "an idle worker's pod is their desk's")
	_check(view.pod_extent(_pk("api:p2")).encloses(view.signal_extent(_pk("api:p2"))), "and holds their signal")
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
		var wanted := Rect2(EXTENT[pane_id].position - Vector2(2, 2), Vector2(98, 128))
		_eq(pointer.rect, wanted, "around %s's extent, two units off and rounded outward" % pane_id)
	_eq(pointer.rect, Rect2(287, 472, 98, 128), "the last one, web:p3, frames its image and name row")
	view.point(_pk("web:p1"))
	_eq(pointer.rect, Rect2(63, 472, 98, 128), "a blocked desk's frame takes every annotation row in")
	pointer.point_at(_pk("web:p1"), Rect2(65.5, 474.25, 94, 124))
	_eq(pointer.rect, Rect2(63, 472, 99, 129), "fractional bounds round outward, never cutting into the margin")
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
	_eq(view.zone_opening(_pk("api")), Rect2(32, 64, 608, 352), "api without its sign drawn: from its aisle row's top")
	_eq(view.zone_opening(_pk("web")), OPENING["web"], "the others keep theirs")
	board.free()


# --- the camera's two pan rules ---------------------------------------------------


## revealed() moves the pan just enough: not at all for what is already in
## view with its headroom, to the far edge for what lies right or below, to the
## near edge for what lies left or above. A short view drops headroom first,
## then keeps the lower annotation rows over the picture's top. An oversized
## width still keeps its left edge. Each axis on its own.
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
	_eq(OfficeCamera.revealed(Vector2.ZERO, wide, room), Vector2(100, 500), "too large: left and lower rows win")
	_eq(OfficeCamera.revealed(Vector2(900, 900), wide, room), Vector2(100, 500), "from either side")
	var signal_box := Rect2(400, 300, 94, 124)
	var short_views: Dictionary[int, int] = {156: 268, 155: 269, 124: 300, 123: 301, 99: 325}
	for height: int in short_views:
		for start: Vector2 in [Vector2.ZERO, Vector2(900, 900)]:
			_eq(
				OfficeCamera.revealed(start, signal_box, Vector2(94, height)),
				Vector2(400, short_views[height]),
				"%d high from %s: headroom gives way before the chip and name" % [height, start]
			)
	_eq(
		OfficeCamera.revealed(Vector2(-50, -50), Rect2(10, 40, 30, 58), room),
		Vector2(-50, -50),
		"never clamped to a map"
	)


## The pod joins a desk's framing only when the two together fit the view with
## the headroom: exactly fitting they do, one unit short on either axis the
## desk stays alone, and the fixture's idle worker, at their desk, is framed
## with their pod.
func test_the_pod_joins_the_framing_only_when_both_fit() -> void:
	var desk := Rect2(65, 122, 94, 124)
	var pod := Rect2(64, 120, 192, 256)
	var both := Rect2(64, 120, 192, 256)
	_eq(desk.merge(pod), both, "a far desk and its pod together are the pod")
	_check(OfficeCamera.fits(both, Vector2(192, 288)), "exactly as large as the view under its headroom: fits")
	_check(not OfficeCamera.fits(both, Vector2(191, 288)), "one unit too wide: does not")
	_check(not OfficeCamera.fits(both, Vector2(192, 287)), "one unit too tall: does not")
	_check(not OfficeCamera.fits(both, Vector2(192, 256)), "the headroom counts")
	_eq(OfficeCamera.framing(desk, pod, Vector2(192, 288)), both, "fitting: the desk with its pod")
	_eq(OfficeCamera.framing(desk, pod, Vector2(191, 288)), desk, "too wide by one: the desk alone")
	_eq(OfficeCamera.framing(desk, pod, Vector2(192, 287)), desk, "too tall by one: the desk alone")
	_eq(OfficeCamera.framing(desk, Rect2(), Vector2(192, 288)), desk, "no pod asked for: the desk alone")
	_eq(OfficeCamera.framing(desk, Rect2(), Vector2(10, 10)), desk, "whatever the view")
	# A near workstation's complete name row still fits inside the pod's drawing.
	var near := Rect2(65, 602, 94, 124)
	var near_pod := Rect2(64, 472, 192, 256)
	_eq(OfficeCamera.framing(near, near_pod, VIEW), Rect2(64, 472, 192, 256), "a near desk inside its pod's drawing")
	var view := _floor_view()
	var worker := _in_world(view, view.signal_extent(_pk("api:p2")))
	var their_pod := _in_world(view, view.pod_extent(_pk("api:p2")))
	_eq(worker.merge(their_pod), their_pod, "an idle worker and their pod together are the pod")
	_check(OfficeCamera.fits(worker.merge(their_pod), VIEW), "which fits a 512x308 view under its headroom")
	_eq(OfficeCamera.framing(worker, their_pod, VIEW), their_pod, "so the worker is framed with the pod")


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


## with_wall() is the third rule, for a map's first arrival only: the wall's
## top when it and what is kept fit the view together, whether that raises or
## lowers the planned pan. Never moved sideways, and unchanged if either is
## empty or they do not fit.
func test_a_map_opens_with_the_wall_when_it_fits() -> void:
	var wall := Rect2(0, 40, 800, 80)
	var desk := Rect2(65, 230, 30, 58)
	var room := Vector2(936, 254)
	_eq(OfficeCamera.with_wall(Vector2(0, 98), wall, desk, room), Vector2(0, 40), "lifted to the wall's top")
	_eq(OfficeCamera.with_wall(Vector2(64, 98), wall, desk, room), Vector2(64, 40), "sideways as planned")
	_eq(
		OfficeCamera.with_wall(Vector2(0, 0), wall, desk, room),
		Vector2(0, 40),
		"a view standing higher comes down to it"
	)
	_eq(OfficeCamera.with_wall(Vector2(0, 40), wall, desk, room), Vector2(0, 40), "exactly at it")
	_eq(
		OfficeCamera.with_wall(Vector2(0, 98), wall, desk, Vector2(936, 248)),
		Vector2(0, 40),
		"exactly as tall as the view, the wall's top to the desk's bottom: lifted"
	)
	_eq(
		OfficeCamera.with_wall(Vector2(0, 98), wall, desk, Vector2(936, 247)),
		Vector2(0, 98),
		"a unit taller than the view: the desk wins, as planned"
	)
	_eq(
		OfficeCamera.with_wall(Vector2(0, 98), wall, Rect2(0, 60, 10, 10), Vector2(936, 79)),
		Vector2(0, 98),
		"a wall taller than the view, whatever is kept: as planned"
	)
	_eq(OfficeCamera.with_wall(Vector2(0, 98), Rect2(), desk, room), Vector2(0, 98), "no wall: as planned")
	_eq(OfficeCamera.with_wall(Vector2(0, 98), wall, Rect2(), room), Vector2(0, 98), "nothing kept: as planned")
	_check(
		OfficeCamera.with_wall(Vector2(0, 98), wall, desk, room) != OfficeCamera.revealed(Vector2(0, 98), desk, room),
		"not the rule a desk is revealed by"
	)
	_check(
		(
			OfficeCamera.with_wall(Vector2(0, 174), wall, desk, room)
			!= OfficeCamera.opened(Vector2(0, 174), Rect2(32, 174, 288, 210), room)
		),
		"nor the one a zone is opened by"
	)


## The floor's answers, handed to the camera's rules as the office hands them
## (in the world's coordinates: by where the floor's root stands in it), pan a
## 512x308 view to the independently calculated containment intervals:
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
			_eq(OfficeCamera.opened(from, opening, NARROW), OPENED_NARROW[zone_id], "%s in a narrow view" % zone_id)
		_eq(pans, OPENED[zone_id], "%s opened from each pan" % zone_id)
	var board := view.zone_sign(_pk("api"))
	board.get_parent().remove_child(board)
	var bare := _in_world(view, view.zone_opening(_pk("api")))
	_eq(
		OfficeCamera.opened(Vector2(400, 600), bare, VIEW), Vector2(32, 96), "api without its sign: its aisle row's top"
	)
	board.free()


# --- what an arrow asks -----------------------------------------------------------


## Both chips hang below their workstation. An arrow stands at the bottom
## edge while the image is visible but the chip is not; one unit of the chip
## removes it. The same strict intersection rule applies at the left and top
## edges. Its direction is the chip's, not the full signal's centre.
func test_an_arrow_stands_by_its_target_not_by_the_extent() -> void:
	var view := _floor_view()
	var chip := view.arrow_target(_pk("web:p1"))
	var extent := view.signal_extent(_pk("web:p1"))
	_eq([chip, extent], [Rect2(97, 556, 30, 16), Rect2(65, 474, 94, 124)], "web:p1's chip within its full signal")
	var target := EdgeArrowModel.Target.new()
	target.zone_key = _pk("web")
	target.pane_key = _pk("web:p1")
	target.rect = chip
	var targets: Array[EdgeArrowModel.Target] = [target]
	# The view's bottom edge against the chip's top edge.
	var over := Rect2(Vector2(0, chip.position.y - VIEW.y), VIEW)
	_check(over.encloses(Rect2(74.5, 474, 80, 80)), "the entire workstation is in view above its chip")
	var arrows := EdgeArrowModel.of(over, targets)
	_eq(arrows.size(), 1, "the chip just below the view: its arrow")
	_eq(
		[arrows[0].pane_key, arrows[0].blocked, arrows[0].edge],
		[_pk("web:p1"), 1, EdgeArrowModel.Edge.BOTTOM],
		"on the bottom edge"
	)
	# Centre (256,402) to (112,564), crossing y=556: (256 - 144*154/162)/512.
	_eq("%.4f" % arrows[0].along, "0.2326", "along it toward the chip")
	_check(
		arrows[0].along != EdgeArrowModel.along_toward(over, extent),
		"which is not where the extent's middle would put it"
	)
	_eq(
		EdgeArrowModel.of(Rect2(over.position + Vector2(0, 1), VIEW), targets).size(),
		0,
		"a unit of the chip in view: none"
	)
	# Centre (383,554) to (112,564), crossing x=127.
	var beside := Rect2(Vector2(chip.end.x, 400), VIEW)
	arrows = EdgeArrowModel.of(beside, targets)
	_eq(arrows.size(), 1, "the chip just left of the view: its arrow")
	_eq([arrows[0].blocked, arrows[0].edge], [1, EdgeArrowModel.Edge.LEFT], "on the left edge")
	_eq("%.4f" % arrows[0].along, "0.5307", "along it toward the chip")
	_eq(
		EdgeArrowModel.of(Rect2(Vector2(chip.end.x - 1, 400), VIEW), targets).size(),
		0,
		"a unit of the chip in view: none"
	)
	# At the near chip's bottom edge, its canvas has already left above.
	var near := view.arrow_target(_pk("web:p2"))
	var near_extent := view.signal_extent(_pk("web:p2"))
	target.rect = near
	var under := Rect2(Vector2(0, near.end.y), VIEW)
	_check(not Rect2(74.5, 602, 80, 80).intersects(under), "the near workstation's canvas is already above the view")
	_check(near_extent.intersects(under), "its annotation rows still intersect: they must not suppress the arrow")
	arrows = EdgeArrowModel.of(under, targets)
	_eq([arrows.size(), arrows[0].edge], [1, EdgeArrowModel.Edge.TOP], "the chip just above the view: its arrow, above")
	_eq(EdgeArrowModel.of(Rect2(under.position - Vector2(0, 1), VIEW), targets).size(), 0, "a unit of it in view: none")
