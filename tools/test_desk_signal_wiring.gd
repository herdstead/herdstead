extends "res://tools/office_test_base.gd"
## The live office's reveal(), reveal_zone(), pointer and HUD arrows against
## independently measured workstation coordinates. The bare floor's answers
## and the camera's pure rules are covered by test_desk_signal.gd.
##
## godot --headless --path . --script tools/test_desk_signal_wiring.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## Policy 6: a two-column pod reserves 7x10 cells. Two pods side by side
## need four lanes (19 cells); otherwise they occupy two 10-cell rows.
## Manual plans, with one aisle row above each zone:
## 800: 23x46 cells. api/web/infra at (1,3)/(1,14)/(1,25), each 19x10;
##      notes/data at (1,36)/(11,36), each 9x10.
## 480: 13x87 cells. api/web/infra at (1,3)/(1,24)/(1,45), each 9x20;
##      notes/data at (1,66)/(1,77), each 9x10.
## 1280: 38x35 cells. api/web/infra as at 800; notes/data at (21,3)/(21,14).
## A pod starts one cell inside its zone and 224 units below the reservation's
## top. Feet are (48 + 96*column, -128 or 0); the canvas is (-37.5,-70,80,80),
## the chip (-15,12,30,16), the stable full signal (-47,-70,94,124).
## World y adds the 32-unit machine plate.
## Pans use the closest containment interval, not the production camera's
## answer. Pods need 288 vertical units with headroom: only the wide window
## below can frame one. Pointers grow two units then round outward: 98x128.

## The pan after reveal(key) and reveal(key, true) from no pan, then the same
## two from the far corner of the map, before the camera's next frame clamps
## it: a 776x254 view of a 736x1504 world, far pan (0,1250).
const REVEAL_800: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 24), Vector2(0, 24), Vector2(0, 122), Vector2(0, 122)],
	"api:p2": [Vector2(0, 24), Vector2(0, 24), Vector2(0, 122), Vector2(0, 122)],
	"api:p3": [Vector2(0, 152), Vector2(0, 152), Vector2(0, 250), Vector2(0, 250)],
	"api:p4": [Vector2(0, 24), Vector2(0, 24), Vector2(0, 122), Vector2(0, 122)],
	"data:p1": [Vector2(0, 1080), Vector2(0, 1080), Vector2(0, 1178), Vector2(0, 1178)],
	"data:p2": [Vector2(0, 1208), Vector2(0, 1208), Vector2(0, 1250), Vector2(0, 1250)],
	"infra:p1": [Vector2(0, 728), Vector2(0, 728), Vector2(0, 826), Vector2(0, 826)],
	"infra:p2": [Vector2(0, 728), Vector2(0, 728), Vector2(0, 826), Vector2(0, 826)],
	"infra:p3": [Vector2(0, 856), Vector2(0, 856), Vector2(0, 954), Vector2(0, 954)],
	"notes:p1": [Vector2(0, 1080), Vector2(0, 1080), Vector2(0, 1178), Vector2(0, 1178)],
	"web:p1": [Vector2(0, 376), Vector2(0, 376), Vector2(0, 474), Vector2(0, 474)],
	"web:p2": [Vector2(0, 504), Vector2(0, 504), Vector2(0, 602), Vector2(0, 602)],
	"web:p3": [Vector2(0, 376), Vector2(0, 376), Vector2(0, 474), Vector2(0, 474)],
}
## A 456x198 view of the two-lane 416x2816 world; far pan (0,2618).
const REVEAL_480: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 80), Vector2(0, 80), Vector2(0, 122), Vector2(0, 122)],
	"api:p2": [Vector2(0, 80), Vector2(0, 80), Vector2(0, 122), Vector2(0, 122)],
	"api:p3": [Vector2(0, 208), Vector2(0, 208), Vector2(0, 250), Vector2(0, 250)],
	"api:p4": [Vector2(0, 400), Vector2(0, 400), Vector2(0, 442), Vector2(0, 442)],
	"data:p1": [Vector2(0, 2448), Vector2(0, 2448), Vector2(0, 2490), Vector2(0, 2490)],
	"data:p2": [Vector2(0, 2576), Vector2(0, 2576), Vector2(0, 2618), Vector2(0, 2618)],
	"infra:p1": [Vector2(0, 1424), Vector2(0, 1424), Vector2(0, 1466), Vector2(0, 1466)],
	"infra:p2": [Vector2(0, 1744), Vector2(0, 1744), Vector2(0, 1786), Vector2(0, 1786)],
	"infra:p3": [Vector2(0, 1872), Vector2(0, 1872), Vector2(0, 1914), Vector2(0, 1914)],
	"notes:p1": [Vector2(0, 2096), Vector2(0, 2096), Vector2(0, 2138), Vector2(0, 2138)],
	"web:p1": [Vector2(0, 752), Vector2(0, 752), Vector2(0, 794), Vector2(0, 794)],
	"web:p2": [Vector2(0, 880), Vector2(0, 880), Vector2(0, 922), Vector2(0, 922)],
	"web:p3": [Vector2(0, 1072), Vector2(0, 1072), Vector2(0, 1114), Vector2(0, 1114)],
}
## A 1256x494 view of the seven-lane 1216x1152 world; far pan (0,658).
const REVEAL_1280: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 122), Vector2(0, 120)],
	"api:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 122), Vector2(0, 120)],
	"api:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 250), Vector2(0, 120)],
	"api:p4": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 122), Vector2(0, 120)],
	"data:p1": [Vector2(0, 136), Vector2(0, 266), Vector2(0, 474), Vector2(0, 472)],
	"data:p2": [Vector2(0, 264), Vector2(0, 266), Vector2(0, 602), Vector2(0, 472)],
	"infra:p1": [Vector2(0, 488), Vector2(0, 618), Vector2(0, 658), Vector2(0, 658)],
	"infra:p2": [Vector2(0, 488), Vector2(0, 618), Vector2(0, 658), Vector2(0, 658)],
	"infra:p3": [Vector2(0, 616), Vector2(0, 618), Vector2(0, 658), Vector2(0, 658)],
	"notes:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 122), Vector2(0, 120)],
	"web:p1": [Vector2(0, 136), Vector2(0, 266), Vector2(0, 474), Vector2(0, 472)],
	"web:p2": [Vector2(0, 264), Vector2(0, 266), Vector2(0, 602), Vector2(0, 472)],
	"web:p3": [Vector2(0, 136), Vector2(0, 266), Vector2(0, 474), Vector2(0, 472)],
}
## The pointer's frame around each desk, in the floor's own coordinates, on the
## 800x480 window's four-lane map.
const POINTER_800: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 120, 98, 128),
	"api:p2": Rect2(159, 120, 98, 128),
	"api:p3": Rect2(159, 248, 98, 128),
	"api:p4": Rect2(287, 120, 98, 128),
	"data:p1": Rect2(383, 1176, 98, 128),
	"data:p2": Rect2(383, 1304, 98, 128),
	"infra:p1": Rect2(63, 824, 98, 128),
	"infra:p2": Rect2(287, 824, 98, 128),
	"infra:p3": Rect2(287, 952, 98, 128),
	"notes:p1": Rect2(63, 1176, 98, 128),
	"web:p1": Rect2(63, 472, 98, 128),
	"web:p2": Rect2(63, 600, 98, 128),
	"web:p3": Rect2(287, 472, 98, 128),
}
## And on the 480x320 window's two-lane map (13 cells).
const POINTER_480: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 120, 98, 128),
	"api:p2": Rect2(159, 120, 98, 128),
	"api:p3": Rect2(159, 248, 98, 128),
	"api:p4": Rect2(63, 440, 98, 128),
	"data:p1": Rect2(63, 2488, 98, 128),
	"data:p2": Rect2(63, 2616, 98, 128),
	"infra:p1": Rect2(63, 1464, 98, 128),
	"infra:p2": Rect2(63, 1784, 98, 128),
	"infra:p3": Rect2(63, 1912, 98, 128),
	"notes:p1": Rect2(63, 2136, 98, 128),
	"web:p1": Rect2(63, 792, 98, 128),
	"web:p2": Rect2(63, 920, 98, 128),
	"web:p3": Rect2(63, 1112, 98, 128),
}
## And on the 1280x720 window's seven-lane map.
const POINTER_1280: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 120, 98, 128),
	"api:p2": Rect2(159, 120, 98, 128),
	"api:p3": Rect2(159, 248, 98, 128),
	"api:p4": Rect2(287, 120, 98, 128),
	"data:p1": Rect2(703, 472, 98, 128),
	"data:p2": Rect2(703, 600, 98, 128),
	"infra:p1": Rect2(63, 824, 98, 128),
	"infra:p2": Rect2(287, 824, 98, 128),
	"infra:p3": Rect2(287, 952, 98, 128),
	"notes:p1": Rect2(703, 120, 98, 128),
	"web:p1": Rect2(63, 472, 98, 128),
	"web:p2": Rect2(63, 600, 98, 128),
	"web:p3": Rect2(287, 472, 98, 128),
}
## The pan after reveal_zone(zone) from no pan, and where the camera's next
## frame leaves it; then the same two from the far corner of the map.
const ZONES_800: Dictionary[String, Array] = {
	"api": [Vector2(0, 114), Vector2(0, 114), Vector2(0, 114), Vector2(0, 114)],
	"web": [Vector2(0, 466), Vector2(0, 466), Vector2(0, 466), Vector2(0, 466)],
	"infra": [Vector2(0, 818), Vector2(0, 818), Vector2(0, 818), Vector2(0, 818)],
	"notes": [Vector2(0, 1170), Vector2(0, 1170), Vector2(0, 1170), Vector2(0, 1170)],
	"data": [Vector2(0, 1170), Vector2(0, 1170), Vector2(0, 1170), Vector2(0, 1170)],
}
const ZONES_480: Dictionary[String, Array] = {
	"api": [Vector2(0, 114), Vector2(0, 114), Vector2(0, 114), Vector2(0, 114)],
	"web": [Vector2(0, 786), Vector2(0, 786), Vector2(0, 786), Vector2(0, 786)],
	"infra": [Vector2(0, 1458), Vector2(0, 1458), Vector2(0, 1458), Vector2(0, 1458)],
	"notes": [Vector2(0, 2130), Vector2(0, 2130), Vector2(0, 2130), Vector2(0, 2130)],
	"data": [Vector2(0, 2482), Vector2(0, 2482), Vector2(0, 2482), Vector2(0, 2482)],
}
const ZONES_1280: Dictionary[String, Array] = {
	"api": [Vector2(0, 114), Vector2(0, 114), Vector2(0, 114), Vector2(0, 114)],
	"web": [Vector2(0, 466), Vector2(0, 466), Vector2(0, 466), Vector2(0, 466)],
	"infra": [Vector2(0, 818), Vector2(0, 658), Vector2(0, 818), Vector2(0, 658)],
	"notes": [Vector2(0, 114), Vector2(0, 114), Vector2(0, 114), Vector2(0, 114)],
	"data": [Vector2(0, 466), Vector2(0, 466), Vector2(0, 466), Vector2(0, 466)],
}
## The original four-lane map after narrowing to 640x480: view 616x254,
## far pan (120,1250). No workstation moves or exceeds that view's right edge
## from zero pan, but the zones ending at x=640 need 24 units of horizontal pan.
const REVEAL_NARROW: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 24), Vector2(0, 24), Vector2(65, 122), Vector2(65, 122)],
	"api:p2": [Vector2(0, 24), Vector2(0, 24), Vector2(120, 122), Vector2(120, 122)],
	"api:p3": [Vector2(0, 152), Vector2(0, 152), Vector2(120, 250), Vector2(120, 250)],
	"api:p4": [Vector2(0, 24), Vector2(0, 24), Vector2(120, 122), Vector2(120, 122)],
	"data:p1": [Vector2(0, 1080), Vector2(0, 1080), Vector2(120, 1178), Vector2(120, 1178)],
	"data:p2": [Vector2(0, 1208), Vector2(0, 1208), Vector2(120, 1250), Vector2(120, 1250)],
	"infra:p1": [Vector2(0, 728), Vector2(0, 728), Vector2(65, 826), Vector2(65, 826)],
	"infra:p2": [Vector2(0, 728), Vector2(0, 728), Vector2(120, 826), Vector2(120, 826)],
	"infra:p3": [Vector2(0, 856), Vector2(0, 856), Vector2(120, 954), Vector2(120, 954)],
	"notes:p1": [Vector2(0, 1080), Vector2(0, 1080), Vector2(65, 1178), Vector2(65, 1178)],
	"web:p1": [Vector2(0, 376), Vector2(0, 376), Vector2(65, 474), Vector2(65, 474)],
	"web:p2": [Vector2(0, 504), Vector2(0, 504), Vector2(65, 602), Vector2(65, 602)],
	"web:p3": [Vector2(0, 376), Vector2(0, 376), Vector2(120, 474), Vector2(120, 474)],
}
const ZONES_NARROW: Dictionary[String, Array] = {
	"api": [Vector2(24, 114), Vector2(24, 114), Vector2(32, 114), Vector2(32, 114)],
	"web": [Vector2(24, 466), Vector2(24, 466), Vector2(32, 466), Vector2(32, 466)],
	"infra": [Vector2(24, 818), Vector2(24, 818), Vector2(32, 818), Vector2(32, 818)],
	"notes": [Vector2(0, 1170), Vector2(0, 1170), Vector2(32, 1170), Vector2(32, 1170)],
	"data": [Vector2(24, 1170), Vector2(24, 1170), Vector2(120, 1170), Vector2(120, 1170)],
}

## First arrival, on api:p1 then on api's sign. The wall begins at world y=44;
## api:p1's signal ends at y=278. The 198-high minimum view cannot keep both:
## the selected desk wins, at pan 80. A zone's sign still fits with the wall.
const OPENED: Dictionary[Vector2, Array] = {
	Vector2(960, 480): [Vector2(0, 44), Vector2(0, 44)],
	Vector2(800, 480): [Vector2(0, 44), Vector2(0, 44)],
	Vector2(1280, 720): [Vector2(0, 44), Vector2(0, 44)],
	Vector2(960, 640): [Vector2(0, 44), Vector2(0, 44)],
	Vector2(480, 320): [Vector2(0, 80), Vector2(0, 44)],
}


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("desk-signal-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	# Both logical rows: blocked web:p1/p2, idle api:p2 and infra:p3,
	# working data:p2 (no longer launch_pending), plus far and near shells.
	fixture = _dict(fixture_file, "snapshot")
	fixture = _with(
		_with(fixture, "web:p2", {"agent_status": "blocked"}),
		"data:p2",
		{"agent_status": "working", "launch_pending": false}
	)
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "DESK SIGNAL WIRING TESTS"


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The fixture drawn in a window of `screen`; image stations need no settling.
func _office(screen := Vector2(SCREEN)) -> OfficeDouble:
	var office := await _live_office(fixture, screen)
	await _frames(2)
	return office


## The furthest the pan goes on the shown map.
func _far(office: OfficeDouble) -> Vector2:
	return (office.camera.world_size - office.camera.free_rect().size).max(Vector2.ZERO)


## reveal() for every desk of `wanted`, plainly and with its pod, from no pan
## and from the far corner, against the independent coordinate tables.
func _reveals(office: OfficeDouble, wanted: Dictionary[String, Array], where: String) -> void:
	_eq(office.floor_view.seats.size(), wanted.size(), "%s: every desk of the fixture is seated" % where)
	for pane_id: String in wanted:
		var pans := []
		for from: Vector2 in [Vector2.ZERO, _far(office)]:
			for whole: bool in [false, true]:
				office.camera.pan = from
				office.reveal(_pk(pane_id), whole)
				pans.append(office.camera.pan)
		_eq(
			pans,
			wanted[pane_id],
			"%s: %s revealed alone and with its pod, from the top and from the far corner" % [where, pane_id]
		)


## reveal_zone() for every zone of `wanted`, from no pan and from the far
## corner, each time as the call leaves the pan and as the next frame clamps it.
func _openings(office: OfficeDouble, wanted: Dictionary[String, Array], where: String) -> void:
	_eq(office.floor_view.plan.zones.size(), wanted.size(), "%s: every zone of the fixture is placed" % where)
	for zone_id: String in wanted:
		var pans := []
		for from: Vector2 in [Vector2.ZERO, _far(office)]:
			office.camera.pan = from
			office.reveal_zone(_pk(zone_id))
			pans.append(office.camera.pan)
			await _frames(1)
			pans.append(office.camera.pan)
		_eq(pans, wanted[zone_id], "%s: %s opened from the top and from the far corner" % [where, zone_id])


## point() at every desk of `wanted`, against the independently rounded frames.
func _pointed(office: OfficeDouble, wanted: Dictionary[String, Rect2], where: String) -> void:
	var pointer := office.floor_view.pointer
	for pane_id: String in wanted:
		office.floor_view.point(_pk(pane_id))
		_eq([pointer.key, pointer.visible], [_pk(pane_id), true], "%s: the pointer is at %s" % [where, pane_id])
		_eq(pointer.rect, wanted[pane_id], "%s: and frames %s's signal" % [where, pane_id])
	office.floor_view.point("")
	_eq([pointer.key, pointer.visible, pointer.rect], ["", false, Rect2()], "%s: pointing at nothing clears it" % where)
	var first: String = wanted.keys()[0]
	office.floor_view.point(_pk(first))
	office.floor_view.point(_pk("nobody:p9"))
	_eq([pointer.key, pointer.visible], ["", false], "%s: and so does a pane with no seat here" % where)


## The arrows the HUD shows once the view is at `pan`: each one's zone, the
## desk a click pans to, how many are blocked there, its edge, and where along
## the edge to the four decimals the arrows' own signature keeps
## (EdgeArrowModel.signature()).
func _arrows_at(office: OfficeDouble, pan: Vector2) -> Array:
	office.camera.pan = pan
	await _frames(3)
	var said := []
	for arrow in office.hud.edge_arrows.models():
		said.append([arrow.zone_key, arrow.pane_key, arrow.blocked, arrow.edge, "%.4f" % arrow.along])
	return said


## One arrow as _arrows_at() says it.
func _arrow(zone_id: String, pane_id: String, blocked: int, edge: EdgeArrowModel.Edge, along: String) -> Array:
	return [_pk(zone_id), _pk(pane_id), blocked, edge, along]


# --- a desk brought into view -----------------------------------------------------


## Every workstation state and both logical rows are revealed with headroom.
## The pod is too tall for this view, so asking for it still frames the signal.
func test_a_desk_is_revealed_where_it_was_at_800x480() -> void:
	var office := await _office()
	_eq(office.world.position, Vector2(16, 86), "the world stands at the HUD's free corner")
	_eq(office.camera.free_rect(), Rect2(16, 86, 776, 254), "with 776x254 of it in view")
	_eq(office.floor_view.root.position, Vector2(0, 32), "and the floor under the plate")
	_eq(office.camera.world_size, Vector2(776, 1504), "the four-lane plan plus the view-wide machine plate")
	_eq(_far(office), Vector2(0, 1250), "the whole vertical pan range")
	_reveals(office, REVEAL_800, "800x480")
	_done(office)


## The smallest window's 416-wide map fits across its 456-wide view. Two-tab
## zones need two pod rows here; fractional pans stay fractional until drawn.
func test_a_desk_is_revealed_where_it_was_in_the_smallest_window() -> void:
	var office := await _office(Vector2(480, 320))
	_eq(office.camera.free_rect(), Rect2(16, 48, 456, 198), "456x198 of the world in view")
	_eq(office.camera.world_size, Vector2(456, 2816), "the two-lane plan plus the view-wide machine plate")
	_eq(_far(office), Vector2(0, 2618), "the pan goes nowhere sideways")
	_reveals(office, REVEAL_480, "480x320")
	# A reveal starts from the pan as it is and leaves it between units when
	# nothing has to move; only the camera's next frame rounds, and only its
	# position.
	office.camera.pan = Vector2(0, 110.75)
	office.reveal(_pk("api:p1"))
	_eq(office.camera.pan, Vector2(0, 110.75), "api:p1 already in view from a pan between units: no move")
	await _frames(1)
	_eq(office.camera.pan, Vector2(0, 110.75), "the next frame keeps the pan")
	_eq(office.camera.position, Vector2(0, 111), "and rounds the camera's position")
	office.camera.pan = Vector2(0, 300.75)
	office.reveal(_pk("api:p1"))
	_eq(office.camera.pan, Vector2(0, 122), "from below: up to its headroom")
	_done(office)


## Seven lanes let notes and data stand beside api and web. A whole pod fits
## with headroom here, so the whole-table request differs from the signal's.
func test_a_desk_is_revealed_where_it_was_in_a_wide_window() -> void:
	var office := await _office(Vector2(1280, 720))
	_eq(office.world.position, Vector2(16, 86), "the world stands where it does in every tall window")
	_eq(office.camera.free_rect(), Rect2(16, 86, 1256, 494), "with 1256x494 of it in view")
	_eq(office.camera.world_size, Vector2(1256, 1152), "the seven-lane plan plus the view-wide machine plate")
	_eq(_far(office), Vector2(0, 658), "the whole vertical pan range")
	_reveals(office, REVEAL_1280, "1280x720")
	_done(office)


## A pane with no seat on the shown map and a zone the plan does not place
## move nothing.
func test_no_seat_and_no_zone_pan_nothing() -> void:
	var office := await _office()
	office.camera.pan = Vector2(77, 55)
	office.reveal(_pk("nobody:p9"))
	office.reveal(_pk("nobody:p9"), true)
	office.reveal("")
	office.reveal_zone(_pk("nowhere"))
	office.reveal_zone("")
	_eq(office.camera.pan, Vector2(77, 55), "the pan is where it was")
	_done(office)


## A nine-lane plan puts api/web in its first band and infra/notes/data in
## its second: 48x24 cells plus the plate. Use a window that actually fits
## the larger workstations; real drag and held keys must still pan nothing.
func test_a_map_that_fits_the_view_cannot_be_panned() -> void:
	var office := await _office(Vector2(1600, 1120))
	var room := office.camera.free_rect()
	var world := office.camera.world_size
	_eq(world, Vector2(1576, 800), "the nine-lane plan plus the view-wide machine plate")
	_check(
		world.x <= room.size.x and world.y <= room.size.y,
		"the map and its plate fit the room: %s in %s" % [world, room]
	)
	_eq(office.camera.position, Vector2.ZERO, "the first refresh leaves the view unpanned")
	var seen := Rect2(office.camera.position + room.position, room.size)
	await _drag(Vector2(400, 300), Vector2(320, 220))
	await _frames(2)
	_eq(office.camera.position, Vector2.ZERO, "a real drag 80 units up and left pans nothing")
	_eq(Rect2(office.camera.position + room.position, room.size), seen, "the world on screen is the same")
	for keycode: Key in [KEY_DOWN, KEY_RIGHT]:
		await _parsed(_key(keycode))
		_check(Input.is_action_pressed("ui_down" if keycode == KEY_DOWN else "ui_right"), "the key is held")
		await _frames(2)
		var release := _key(keycode)
		release.pressed = false
		await _parsed(release)
		_eq(office.camera.position, Vector2.ZERO, "%s held for frames pans nothing" % OS.get_keycode_string(keycode))
	_eq(Rect2(office.camera.position + room.position, room.size), seen, "and the world on screen stays")
	_done(office)


# --- a zone opened ----------------------------------------------------------------


## reveal_zone() puts the top of the zone's sign at the top of the world, with
## no headroom, and pans sideways only as far as the zone's width needs; the
## camera's next frame clamps the pan to the map (infra at 1280x720 reaches
## the map's end before its sign can reach the view's top).
func test_a_zone_is_opened_where_it_was() -> void:
	var office := await _office()
	await _openings(office, ZONES_800, "800x480")
	_done(office)
	office = await _office(Vector2(480, 320))
	await _openings(office, ZONES_480, "480x320")
	_done(office)
	office = await _office(Vector2(1280, 720))
	await _openings(office, ZONES_1280, "1280x720")
	_done(office)


# --- the pointer ------------------------------------------------------------------


## point() frames the full signal, including every annotation row, grown two
## units and rounded outward, in the floor's own coordinates
## whatever the world's origin; nothing and an unseated pane clear it.
func test_the_pointer_frames_what_it_framed() -> void:
	var office := await _office()
	_pointed(office, POINTER_800, "800x480")
	_done(office)
	office = await _office(Vector2(480, 320))
	_pointed(office, POINTER_480, "480x320")
	_done(office)
	office = await _office(Vector2(1280, 720))
	_pointed(office, POINTER_1280, "1280x720")
	_done(office)


# --- the edge arrows --------------------------------------------------------------


## The arrows at the corners and the middle of the map: which zones, the desk
## each leads to, how many blocked desks it counts, its edge and its place
## along it. Four-lane chip centres in world coordinates are (112,596),
## (112,724), (112,948); two-lane centres are (112,916), (112,1044),
## (112,1588). Intersect the ray from the view's centre with its boundary.
func test_the_arrows_stand_where_they_stood() -> void:
	var office := await _office()
	var below := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.4037"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4450")
	]
	_eq(await _arrows_at(office, Vector2.ZERO), below, "800x480, at the top: both of web's chips and infra's below")
	_eq(
		await _arrows_at(office, _far(office)),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4422"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.3947")
		],
		"800x480, at the bottom: both of web's chips and infra's above"
	)
	_eq(
		await _arrows_at(office, Vector2(0, 560)),
		[_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.3269")],
		"800x480, in the middle: web's chips in view, infra's below"
	)
	_done(office)
	office = await _office(Vector2(480, 320))
	below = [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.4692"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4831")
	]
	var above := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4860"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.4777")
	]
	_eq(await _arrows_at(office, Vector2.ZERO), below, "480x320, at the top")
	_eq(await _arrows_at(office, _far(office)), above, "480x320, at the bottom")
	_eq(
		await _arrows_at(office, Vector2(0, 924)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2646"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4554")
		],
		"480x320, in the middle: web's far chip above, its near chip in view, infra below"
	)
	_done(office)


## Both chips are below their image. At the view's bottom edge the canvas can
## be wholly visible while the chip still needs an arrow. At its top edge the
## canvas has gone but annotation rows remain: they must not suppress it.
## One unit of chip intersection, not signal intersection, decides the count.
func test_an_arrow_follows_its_chip_to_the_unit() -> void:
	var office := await _office(Vector2(480, 320))
	var room := office.camera.free_rect()
	var far_chip := office.floor_view.seat(_pk("web:p1")).node.chip_rect()
	var far_seat := office.floor_view.seat(_pk("web:p1")).node.target_rect()
	_eq([far_chip, far_seat], [Rect2(113, 956, 30, 16), Rect2(90.5, 874, 80, 80)], "web:p1's chip below its canvas")
	var edge := far_chip.position.y - room.position.y - room.size.y
	_eq(edge, 710.0, "the pan that puts the view's bottom at the chip's top")
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.2646"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4677")
		],
		"the chip just below the view: both web desks count"
	)
	_check(Rect2(Vector2(0, edge) + room.position, room.size).encloses(far_seat), "the entire canvas is in view then")
	_eq(
		await _arrows_at(office, Vector2(0, edge + 1)),
		[
			_arrow("web", "web:p2", 1, EdgeArrowModel.Edge.BOTTOM, "0.3924"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4676")
		],
		"one unit of the far chip in view: only web's near desk counts"
	)
	edge = far_chip.end.y - room.position.y
	_eq(edge, 924.0, "the pan that puts the view's top at the far chip's bottom")
	var infra_below := _arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4555")
	_eq(await _arrows_at(office, Vector2(0, edge - 1)), [infra_below], "one unit of web:p1's chip in view: no arrow")
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2646"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4554")
		],
		"the far chip just above the view: its arrow"
	)
	var on_screen := Rect2(Vector2(0, edge) + room.position, room.size)
	_check(not far_seat.intersects(on_screen), "the canvas is already above the view")
	var far_signal := office.floor_view.seat(_pk("web:p1")).node.signal_rect()
	_check(far_signal.intersects(on_screen), "remaining annotation rows do not suppress its arrow")
	_eq(
		await _arrows_at(office, Vector2(0, edge + 1)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2668"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4553")
		],
		"a unit further: the arrow, a little along"
	)
	var near_chip := office.floor_view.seat(_pk("web:p2")).node.chip_rect()
	var near_seat := office.floor_view.seat(_pk("web:p2")).node.target_rect()
	_eq([near_chip, near_seat], [Rect2(113, 1084, 30, 16), Rect2(90.5, 1002, 80, 80)], "web:p2's chip below its canvas")
	edge = near_chip.end.y - room.position.y
	_eq(edge, 1052.0, "the near chip leaves the top 128 units after the far chip")
	_eq(
		await _arrows_at(office, Vector2(0, edge - 1)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.3924"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4425")
		],
		"one unit of web:p2's chip in view: only web:p1 counts"
	)
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.3928"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4424")
		],
		"web:p2's chip just out of view: both count"
	)
	var infra_chip := office.floor_view.seat(_pk("infra:p1")).node.chip_rect()
	edge = infra_chip.end.y - room.position.y
	_eq(edge, 1596.0, "infra's chip leaves the top in the third zone")
	_eq(
		await _arrows_at(office, Vector2(0, edge - 1)),
		[_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4676")],
		"one unit of infra:p1's chip in view: web's arrow alone"
	)
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4677"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.2646")
		],
		"infra:p1's chip just out of view: its arrow too"
	)
	_done(office)


# --- a relayout -------------------------------------------------------------------


## Narrowing the window after the map was planned (800x480 to 640x480) takes
## the world's right edge in (616 of it in view where 776 are) and moves
## nothing on the floor: the plan is the one it had, every reveal from no pan
## is where it was, and so is every zone's opening but those that now end past
## the narrower view, every pointed desk too, and the arrows stand along the
## narrower view. The four-lane map is 736 wide, so the far corner moves 120
## right. api, web, infra and data end at x=640 and open 24 in from no pan.
func test_a_relayout_moves_no_answer() -> void:
	var office := await _office()
	var plan := office.floor_view.plan
	office.test_screen = Vector2(640, 480)
	office.refresh()
	await _frames(2)
	_check(office.floor_view.plan == plan, "the narrower window plans nothing again")
	_eq(office.camera.free_rect(), Rect2(16, 86, 616, 254), "the world's room stops 8 short of the narrower edge")
	_eq(_far(office), Vector2(120, 1250), "the far corner is 120 further right")
	for key: String in REVEAL_800:
		_eq(REVEAL_NARROW[key].slice(0, 2), REVEAL_800[key].slice(0, 2), "%s: from no pan, as at 800" % key)
	for key: String in ZONES_800:
		var shut: Array = ZONES_800[key].slice(0, 2)
		var past := Vector2.ZERO if key == "notes" else Vector2(24, 0)
		_eq(
			ZONES_NARROW[key].slice(0, 2),
			shut.map(func(pan: Vector2) -> Vector2: return pan + past),
			"%s: opened from no pan as at 800, and as far in as its width needs" % key
		)
	_reveals(office, REVEAL_NARROW, "640 wide")
	await _openings(office, ZONES_NARROW, "640 wide")
	_pointed(office, POINTER_800, "640 wide")
	_eq(
		await _arrows_at(office, Vector2.ZERO),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.4138"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4508")
		],
		"640 wide, at the top: both of web's chips and infra's below, along the narrower view"
	)
	_eq(
		await _arrows_at(office, Vector2(0, 620)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2324"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2990")
		],
		"640 wide, 620 down: web's far chip above, its near chip in view, infra below"
	)
	_done(office)


# --- a map opened -----------------------------------------------------------------


## The part of the world on screen, in the world's coordinates.
func _view(office: OfficeDouble) -> Rect2:
	return Rect2(office.camera.position, office.camera.free_rect().size)


## `bounds`, in the floor's own coordinates, in the world's.
func _floor_in_world(office: OfficeDouble, bounds: Rect2) -> Rect2:
	return Rect2(office.floor_view.root.position + bounds.position, bounds.size)


## Zone `key`'s sign as drawn, in the world's coordinates.
func _sign_in_world(office: OfficeDouble, key: String) -> Rect2:
	var board := office.floor_view.zone_sign(key)
	var holder: Node2D = board.get_parent()
	var drawn := board.drawn_rect()
	var at := office.floor_view.root.to_local(holder.to_global(drawn.position))
	return _floor_in_world(office, Rect2(at, drawn.size))


## The zones of the shown map's first row, by key.
func _first_row(office: OfficeDouble) -> Array[String]:
	var plan := office.floor_view.plan
	var top := 1 << 30
	for zone in plan.zones:
		top = mini(top, zone.cells.position.y)
	var found: Array[String] = []
	for zone in plan.zones:
		if zone.cells.position.y == top:
			found.append(zone.zone_key)
	return found


## Whether the view the office opened on shows the top wall's face (every
## window and the pantry sign whole, from the shell's own geometry), every sign
## of the first zone row, and `kept` (in the world's coordinates).
func _opens_on_the_wall(office: OfficeDouble, kept: Rect2, where: String) -> void:
	var view := _view(office)
	var plan := office.floor_view.plan
	var xs := OfficeShell.window_xs(plan, office.pen)
	_check(not xs.is_empty(), "%s: the map has windows" % where)
	for x in xs:
		var window := OfficeShell.drawn(office.pen, ArtContract.PROP_WINDOW, Vector2(x, OfficeShell.WINDOW_FOOT))
		_check(view.encloses(_floor_in_world(office, window)), "%s: the window at %d is whole in %s" % [where, x, view])
	var feet := OfficeShell.pantry_sign(plan)
	_eq(feet.size(), 1, "%s: the map has a pantry sign" % where)
	for foot in feet:
		var board := _floor_in_world(office, OfficeShell.drawn(office.pen, ArtContract.PROP_PANTRY_SIGN, foot))
		_check(view.encloses(board), "%s: the pantry sign %s is whole in %s" % [where, board, view])
	for key in _first_row(office):
		var board := _sign_in_world(office, key)
		_check(view.encloses(board), "%s: %s's sign %s is whole in %s" % [where, key, board, view])
	_check(view.encloses(kept), "%s: and %s, what it opened on, in %s" % [where, kept, view])


## At 960x480 (the default window) and 800x480 the opening view shows the back
## wall's face with the first zone row's signs and the selected far desk's full
## signal (not the taller pod); likewise when opening on the first zone.
func test_a_map_opens_with_its_back_wall_in_view() -> void:
	for screen: Vector2 in [Vector2(960, 480), Vector2(800, 480)]:
		var office := await _office(screen)
		_eq(office.navigator.active_key, _pk("api:p1"), "%s: herdr's focus is the selection" % screen)
		var desk := _floor_in_world(office, office.floor_view.signal_extent(_pk("api:p1")))
		_opens_on_the_wall(office, desk, "%s on api:p1's full signal" % screen)
		_done(office)
		office = await _live_office(_focused_on(fixture, ""), screen)
		await _frames(2)
		_eq(office.navigator.active_key, "", "%s: nothing is selected" % screen)
		_opens_on_the_wall(office, _sign_in_world(office, _pk("api")), "%s on its first zone" % screen)
		_done(office)


## Where each window opens, against OPENED; the view's bottom in the floor's
## coordinates is printed for the report. A zone picked after the opening (a
## card's place) opens at its sign. api:p3's signal ends at world y=406: 362
## below the wall's top, too much for the 254-high view but within 414.
## At minimum even a far desk's name row takes priority over the wall.
func test_a_map_opens_where_the_rule_puts_it() -> void:
	for screen: Vector2 in OPENED:
		var pans := []
		for snapshot: Dictionary in [fixture, _focused_on(fixture, "")]:
			var office := await _live_office(snapshot, screen)
			await _frames(2)
			pans.append(office.camera.position)
			var view := _view(office)
			print(
				(
					"OPENED %s on %s: pan %s, the floor from %d to %d in view"
					% [
						screen,
						office.navigator.active_key if not office.navigator.active_key.is_empty() else "api",
						office.camera.position,
						view.position.y - office.floor_view.root.position.y,
						view.end.y - office.floor_view.root.position.y
					]
				)
			)
			_done(office)
		_eq(pans, OPENED[screen], "%s: opened on api:p1, then on the first zone" % screen)
	var near := await _live_office(_focused_on(fixture, "api:p3"), Vector2(960, 480))
	await _frames(2)
	_eq(near.navigator.active_key, _pk("api:p3"), "api:p3 is the selection")
	_eq(near.camera.position, Vector2(0, 152), "the near desk and its complete name row take priority over the wall")
	var near_signal := _floor_in_world(near, near.floor_view.signal_extent(_pk("api:p3")))
	_eq(near_signal, Rect2(161, 282, 94, 124), "api:p3's full signal in world coordinates")
	_check(_view(near).encloses(near_signal), "960x480: the near desk's full signal is whole")
	_check(not _view(near).encloses(_floor_in_world(near, near.floor_view.wall_face())), "960x480: the wall gives way")
	near.navigator.pick_zone(_pk("web"))
	near.refresh()
	await _frames(2)
	_eq(near.camera.position, Vector2(0, 466), "a zone picked afterwards opens at its sign, the wall not lifted in")
	_done(near)
	near = await _live_office(_focused_on(fixture, "api:p3"), Vector2(960, 640))
	await _frames(2)
	_eq(near.camera.position, Vector2(0, 44), "a taller view can keep both the near desk and the wall")
	_opens_on_the_wall(near, _floor_in_world(near, near.floor_view.signal_extent(_pk("api:p3"))), "api:p3 at 960x640")
	_done(near)
	var small := await _live_office(fixture, Vector2(480, 320))
	await _frames(2)
	_eq(small.navigator.active_key, _pk("api:p1"), "480x320: herdr's focus is the selection")
	var face := _floor_in_world(small, small.floor_view.wall_face())
	_eq(small.camera.position, Vector2(0, 80), "480x320: the signal's bottom at the view's bottom")
	var desk := _floor_in_world(small, small.floor_view.signal_extent(_pk("api:p1")))
	_eq(desk, Rect2(65, 154, 94, 124), "480x320: api:p1's full signal in world coordinates")
	_check(_view(small).encloses(desk), "480x320: the complete selected signal is visible")
	_check(not _view(small).encloses(face), "480x320: the wall gives way, never the selected name row")
	var pod := _floor_in_world(small, small.floor_view.pod_extent(_pk("api:p1")))
	_check(not _view(small).encloses(pod), "480x320: the pod's near half gives way: %s in %s" % [pod, _view(small)])
	_done(small)


## 480x320 world units are the 960x640 minimum window at 2x. The old canvas-
## only reveal cut off the selected name below the bottom HUD. Check the
## actual label and its complete row, on both logical rows, with real L input.
func test_the_smallest_view_keeps_the_selected_name_row() -> void:
	for pane_id: String in ["api:p1", "web:p2"]:
		var office := await _live_office(_focused_on(fixture, pane_id), Vector2(480, 320))
		var key := _pk(pane_id)
		var station := office.floor_view.seat(key).node
		var plate: Label = station.get_node("Overlay/Plate")
		var expected_pan := Vector2(0, 80 if pane_id == "api:p1" else 880)
		var rest_y := 256.0 if pane_id == "api:p1" else 1056.0
		var signal_top := 122.0 if pane_id == "api:p1" else 922.0
		_eq(office.navigator.active_key, key, "%s: this desk is selected" % pane_id)
		for held: bool in [false, true, false]:
			var event := _key(KEY_L)
			event.pressed = held
			await _parsed(event)
			await _frames(2)
			_eq(office.lens.held, held, "%s: the real L key controls the lens" % pane_id)
			_eq(office.camera.position, expected_pan, "%s: the lens never jumps the view" % pane_id)
			_eq(
				office.floor_view.signal_extent(key),
				Rect2(65, signal_top, 94, 124),
				"%s: a stable full signal" % pane_id
			)
			office.reveal(key)
			_eq(office.camera.pan, expected_pan, "%s: revealing again never jumps the view" % pane_id)
			_check(plate.is_visible_in_tree() and not plate.text.is_empty(), "%s: the selected name is drawn" % pane_id)
			var row := station.plate_row()
			var row_in_world := Rect2(office.world.to_local(station.to_global(row.position)), row.size)
			_eq(row_in_world.position.y, rest_y + (12.0 if held else 0.0), "%s: the name row's independent y" % pane_id)
			_eq(row_in_world.size.y, 10.0, "%s: all ten units of the name row" % pane_id)
			_check(_view(office).encloses(row_in_world), "%s: the complete row clears the bottom HUD" % pane_id)
			var drawn := Rect2(office.world.to_local(plate.global_position), plate.size)
			_check(_view(office).encloses(drawn), "%s: the actual selected label clears the bottom HUD" % pane_id)
		_done(office)
