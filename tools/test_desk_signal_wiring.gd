extends "res://tools/office_test_base.gd"
## The live office brings a desk into view, opens a zone, frames a pointed desk
## and stands its edge arrows exactly where it did before "where is this desk's
## signal" became OfficeFloorView's to answer (lane RECT, off 6413cec): every
## number here was printed by 6413cec on this fixture, and the cases go only
## through what the office offered then (OfficeScene.reveal() and
## reveal_zone(), OfficeFloorView.point() and its pointer, the HUD's arrows), so
## the same file passes on that commit. The answers themselves, on a bare floor
## view, are tools/test_desk_signal.gd's. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_desk_signal_wiring.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.
##
## When a desk's rows (OfficeStation), a pod's measure or the map's plan change
## on purpose, these numbers change with them: a failure prints the new one.
## D2 (2026-10-27): idle sits with a mug; the pantry is a nook nobody walks to;
## the band is two cells (SEATED-Q2). Every y below the band is 32 less (the
## map one row shorter: 800x480 18x25, 480x320 13x32, 1280x720 33x18), x is
## unchanged; api:p2 and infra:p3, idle, are revealed and framed at their own
## seats (their pods' answers), no longer in the pantry. Re-pinned from the
## run's print and checked by hand: api:p2 frames one column right of api:p1
## (95 = 63 + 32), infra:p3 at its near seat.
## Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new zone takes lanes until it
## stands one row; the map replans. Re-pinned from the office's own answers
## (printed by a throwaway dump case) and checked against the plans: 800x480
## plans 20 cells, three lanes, 18x26 (api, web, infra two lanes each down the
## left, notes and data one lane each beside api and web); 480x320 plans 10
## cells, the narrowest plan's two lanes (FRAME-Q2), 13x33 (api, web, infra
## stacked, notes and data side by side under them); 1280x720 plans 34 cells,
## six lanes, 33x19, as deep as before.
## S3 BAR-b (2026-10-27): the SPACES rail is gone; the world starts 16 in and
## first plans take its width. Re-pinned from the office's own answers (printed
## by a throwaway dump case) and checked against the plans: 800x480 plans 23
## cells, four lanes, 23x18 (api and web side by side in the first row, infra,
## notes and data in the second: every y of web is api's, infra stands where web
## did, notes 224 lower and data at x 543 = 16 * 32 + 31); 480x320 plans the
## same 13x32 map, now 416 wide in a 420-wide world, so no pan goes sideways;
## 1280x720 plans 38 cells, seven lanes, 38x18 (api, web, infra and notes in the
## first row, data under api); the world stands at (16, 48) in every window.
## S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab. The world
## stands at (16, 68) on a tall window (the bar
## 52, not 32) and runs to the right edge; the docked panel leaves it 241 deep
## at 480 high (308 before), 481 at 720 (548): re-pinned from the run's print
## and checked against that: a pan that brings a desk down into view grows by
## as much as the desk's frame no longer fit, at most the 67 the view lost (a
## pod reveal by all 67), every pan from the far corner up to a desk is the
## same, and the far corner is 67 further down (367 = 608 - 241,
## 127 = 608 - 481). 800x480 plans 24 cells now, still four lanes and the same
## 23x18 map, so every pointer frame is unchanged; 480x320's world is 456x202
## (420x200), the same 13x32 map, every pan 2 less. The arrows' places along
## their edges come from the print.
## S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the
## world 35 taller: 276 deep at 480 high, 516 at 720. Re-pinned from the run's
## print and checked against that: every pan that brought a desk down into view
## is 35 less (data:p1 at 1280x720 31 -> 0, it no longer has to move), every
## pan from the far corner up to a desk the same, and the far corner 35 less
## (332 = 608 - 276, 92 = 608 - 516); every pointer frame and the 480x320
## window (not docked) are unchanged. The arrows' places along their edges come
## from the print; at the 800x480 bottom web:p2's near chip is in view now.
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: 120 tall docked, 54 in two
## rows, the world 4 shorter everywhere (272 at 480 high, 512 at 720, 198 at
## 480x320). Re-pinned from the run's print: every pan that brings a desk down
## into view is 4 more, the far corner 4 lower (336 = 608 - 272, 96 = 608 - 512,
## 858 at 480x320), headroom pans unchanged; every pointer frame unchanged; every
## arrow keeps its chips, count and edge, only its place along the edge moves.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the bar 18 taller on a
## tall window, so the world stands at (16, 86) and is 18 shorter (254 at 480
## high, 494 at 720); 480x320 (the short band) is unchanged. Re-pinned from the
## run's print: every pan that brings a desk down into view is 18 more, the far
## corner 18 lower (354 = 608 - 254, 114 = 608 - 494), headroom pans unchanged;
## every pointer frame unchanged. The arrows' places along their edges from the
## print; at the 800x480 bottom web:p2's near chip is no longer in view, so the
## arrow above counts both of web's chips (2, was 1): the meaning moved back to
## what it was before S3 PANEL-a1 round 2 (reported, not only re-pinned).
## S3 CAMERA (2026-10-28): a map opens with its back wall in view; the opening's own cases and
## OPENED added below; no existing number here moved.

## The pan after reveal(key) and reveal(key, true) from no pan, then the same
## two from the far corner of the map, before the camera's next frame clamps
## it: an 800x480 window (the world at (16, 86), 776x254 of it in view, a
## four-lane map 736 wide, 608 deep with its plate; 776x241 before S3 PANEL-a1 round 2,
## 776x272 at (16, 68) before S3 PORTRAIT P3).
const REVEAL_800: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 34), Vector2(0, 98), Vector2(0, 198), Vector2(0, 198)],
	"api:p2": [Vector2(0, 34), Vector2(0, 98), Vector2(0, 198), Vector2(0, 198)],
	"api:p3": [Vector2(0, 98), Vector2(0, 98), Vector2(0, 264), Vector2(0, 198)],
	"api:p4": [Vector2(0, 34), Vector2(0, 98), Vector2(0, 198), Vector2(0, 198)],
	"data:p1": [Vector2(0, 258), Vector2(0, 322), Vector2(0, 354), Vector2(0, 354)],
	"data:p2": [Vector2(0, 322), Vector2(0, 322), Vector2(0, 354), Vector2(0, 354)],
	"infra:p1": [Vector2(0, 258), Vector2(0, 322), Vector2(0, 354), Vector2(0, 354)],
	"infra:p2": [Vector2(0, 258), Vector2(0, 322), Vector2(0, 354), Vector2(0, 354)],
	"infra:p3": [Vector2(0, 322), Vector2(0, 322), Vector2(0, 354), Vector2(0, 354)],
	"notes:p1": [Vector2(0, 258), Vector2(0, 322), Vector2(0, 354), Vector2(0, 354)],
	"web:p1": [Vector2(0, 34), Vector2(0, 98), Vector2(0, 200), Vector2(0, 198)],
	"web:p2": [Vector2(0, 98), Vector2(0, 98), Vector2(0, 264), Vector2(0, 198)],
	"web:p3": [Vector2(0, 34), Vector2(0, 98), Vector2(0, 198), Vector2(0, 198)],
}
## The same in the smallest window, 480x320: 456x202 in view, and the 416-wide
## map fits across, so a reveal pans only up and down (S3 BAR-b, 2026-10-27:
## 340 wide with the rail, it panned sideways too). Z1 (2026-10-27): the
## narrowest plan stays two lanes (13 cells, FRAME-Q2); its 33 rows (40 with one
## 9-cell lane) move every zone under api and web up.
const REVEAL_480: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 90), Vector2(0, 154), Vector2(0, 198), Vector2(0, 198)],
	"api:p2": [Vector2(0, 90), Vector2(0, 154), Vector2(0, 198), Vector2(0, 198)],
	"api:p3": [Vector2(0, 154), Vector2(0, 154), Vector2(0, 264), Vector2(0, 198)],
	"api:p4": [Vector2(0, 90), Vector2(0, 154), Vector2(0, 198), Vector2(0, 198)],
	"data:p1": [Vector2(0, 762), Vector2(0, 826), Vector2(0, 858), Vector2(0, 858)],
	"data:p2": [Vector2(0, 826), Vector2(0, 826), Vector2(0, 858), Vector2(0, 858)],
	"infra:p1": [Vector2(0, 538), Vector2(0, 602), Vector2(0, 648), Vector2(0, 646)],
	"infra:p2": [Vector2(0, 538), Vector2(0, 602), Vector2(0, 646), Vector2(0, 646)],
	"infra:p3": [Vector2(0, 602), Vector2(0, 602), Vector2(0, 712), Vector2(0, 646)],
	"notes:p1": [Vector2(0, 762), Vector2(0, 826), Vector2(0, 858), Vector2(0, 858)],
	"web:p1": [Vector2(0, 314), Vector2(0, 378), Vector2(0, 424), Vector2(0, 422)],
	"web:p2": [Vector2(0, 378), Vector2(0, 378), Vector2(0, 488), Vector2(0, 422)],
	"web:p3": [Vector2(0, 314), Vector2(0, 378), Vector2(0, 422), Vector2(0, 422)],
}
## The same in a 1280x720 window: the world at (16, 86), 1256x494 of a
## seven-lane map 608 deep in view, so the pan only ever reaches 114 down
## (1256x481 and 127 before S3 PANEL-a1 round 2; 1256x512 and 96 at (16, 68)
## before S3 PORTRAIT P3).
const REVEAL_1280: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"api:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"api:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"api:p4": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"data:p1": [Vector2(0, 18), Vector2(0, 82), Vector2(0, 114), Vector2(0, 114)],
	"data:p2": [Vector2(0, 82), Vector2(0, 82), Vector2(0, 114), Vector2(0, 114)],
	"infra:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"infra:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"infra:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"notes:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"web:p1": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"web:p2": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
	"web:p3": [Vector2(0, 0), Vector2(0, 0), Vector2(0, 114), Vector2(0, 114)],
}
## The pointer's frame around each desk, in the floor's own coordinates, on the
## 800x480 window's four-lane map (the 480x320 window planned the same one
## before Z1; it plans its own two-lane map now).
const POINTER_800: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 196, 34, 62),
	"api:p2": Rect2(95, 196, 34, 62),
	"api:p3": Rect2(95, 262, 34, 60),
	"api:p4": Rect2(159, 196, 34, 62),
	"data:p1": Rect2(543, 420, 34, 62),
	"data:p2": Rect2(543, 486, 34, 60),
	"infra:p1": Rect2(63, 422, 34, 60),
	"infra:p2": Rect2(159, 420, 34, 62),
	"infra:p3": Rect2(159, 486, 34, 60),
	"notes:p1": Rect2(383, 420, 34, 62),
	"web:p1": Rect2(383, 198, 34, 60),
	"web:p2": Rect2(383, 262, 34, 60),
	"web:p3": Rect2(479, 196, 34, 62),
}
## And on the 480x320 window's two-lane map (13 cells).
const POINTER_480: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 196, 34, 62),
	"api:p2": Rect2(95, 196, 34, 62),
	"api:p3": Rect2(95, 262, 34, 60),
	"api:p4": Rect2(159, 196, 34, 62),
	"data:p1": Rect2(223, 868, 34, 62),
	"data:p2": Rect2(223, 934, 34, 60),
	"infra:p1": Rect2(63, 646, 34, 60),
	"infra:p2": Rect2(159, 644, 34, 62),
	"infra:p3": Rect2(159, 710, 34, 60),
	"notes:p1": Rect2(63, 868, 34, 62),
	"web:p1": Rect2(63, 422, 34, 60),
	"web:p2": Rect2(63, 486, 34, 60),
	"web:p3": Rect2(159, 420, 34, 62),
}
## And on the 1280x720 window's seven-lane map.
const POINTER_1280: Dictionary[String, Rect2] = {
	"api:p1": Rect2(63, 196, 34, 62),
	"api:p2": Rect2(95, 196, 34, 62),
	"api:p3": Rect2(95, 262, 34, 60),
	"api:p4": Rect2(159, 196, 34, 62),
	"data:p1": Rect2(63, 420, 34, 62),
	"data:p2": Rect2(63, 486, 34, 60),
	"infra:p1": Rect2(703, 198, 34, 60),
	"infra:p2": Rect2(799, 196, 34, 62),
	"infra:p3": Rect2(799, 262, 34, 60),
	"notes:p1": Rect2(1023, 196, 34, 62),
	"web:p1": Rect2(383, 198, 34, 60),
	"web:p2": Rect2(383, 262, 34, 60),
	"web:p3": Rect2(479, 196, 34, 62),
}
## The pan after reveal_zone(zone) from no pan, and where the camera's next
## frame leaves it; then the same two from the far corner of the map.
const ZONES_800: Dictionary[String, Array] = {
	"api": [Vector2(0, 174), Vector2(0, 174), Vector2(0, 174), Vector2(0, 174)],
	"web": [Vector2(0, 174), Vector2(0, 174), Vector2(0, 174), Vector2(0, 174)],
	"infra": [Vector2(0, 398), Vector2(0, 354), Vector2(0, 398), Vector2(0, 354)],
	"notes": [Vector2(0, 398), Vector2(0, 354), Vector2(0, 398), Vector2(0, 354)],
	"data": [Vector2(0, 398), Vector2(0, 354), Vector2(0, 398), Vector2(0, 354)],
}
const ZONES_480: Dictionary[String, Array] = {
	"api": [Vector2(0, 174), Vector2(0, 174), Vector2(0, 174), Vector2(0, 174)],
	"web": [Vector2(0, 398), Vector2(0, 398), Vector2(0, 398), Vector2(0, 398)],
	"infra": [Vector2(0, 622), Vector2(0, 622), Vector2(0, 622), Vector2(0, 622)],
	"notes": [Vector2(0, 846), Vector2(0, 846), Vector2(0, 846), Vector2(0, 846)],
	"data": [Vector2(0, 846), Vector2(0, 846), Vector2(0, 846), Vector2(0, 846)],
}
const ZONES_1280: Dictionary[String, Array] = {
	"api": [Vector2(0, 174), Vector2(0, 114), Vector2(0, 174), Vector2(0, 114)],
	"web": [Vector2(0, 174), Vector2(0, 114), Vector2(0, 174), Vector2(0, 114)],
	"infra": [Vector2(0, 174), Vector2(0, 114), Vector2(0, 174), Vector2(0, 114)],
	"notes": [Vector2(0, 174), Vector2(0, 114), Vector2(0, 174), Vector2(0, 114)],
	"data": [Vector2(0, 398), Vector2(0, 114), Vector2(0, 398), Vector2(0, 114)],
}
## REVEAL_800 and ZONES_800 in a window narrowed to 640x480 after the map was planned at 800 (616x254 of the map in
## view, as with the retired drawer open; 616x241 before S3 PANEL-a1 round 2, 616x272 before S3 PORTRAIT P3): see
## test_a_relayout_moves_no_answer.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: these were REVEAL_DRAWER and ZONES_DRAWER, the same numbers.
const REVEAL_NARROW: Dictionary[String, Array] = {
	"api:p1": [Vector2(0, 34), Vector2(0, 98), Vector2(65, 198), Vector2(64, 198)],
	"api:p2": [Vector2(0, 34), Vector2(0, 98), Vector2(97, 198), Vector2(64, 198)],
	"api:p3": [Vector2(0, 98), Vector2(0, 98), Vector2(97, 264), Vector2(64, 198)],
	"api:p4": [Vector2(0, 34), Vector2(0, 98), Vector2(120, 198), Vector2(120, 198)],
	"data:p1": [Vector2(0, 258), Vector2(0, 322), Vector2(120, 354), Vector2(120, 354)],
	"data:p2": [Vector2(0, 322), Vector2(0, 322), Vector2(120, 354), Vector2(120, 354)],
	"infra:p1": [Vector2(0, 258), Vector2(0, 322), Vector2(65, 354), Vector2(64, 354)],
	"infra:p2": [Vector2(0, 258), Vector2(0, 322), Vector2(120, 354), Vector2(120, 354)],
	"infra:p3": [Vector2(0, 322), Vector2(0, 322), Vector2(120, 354), Vector2(120, 354)],
	"notes:p1": [Vector2(0, 258), Vector2(0, 322), Vector2(120, 354), Vector2(120, 354)],
	"web:p1": [Vector2(0, 34), Vector2(0, 98), Vector2(120, 200), Vector2(120, 198)],
	"web:p2": [Vector2(0, 98), Vector2(0, 98), Vector2(120, 264), Vector2(120, 198)],
	"web:p3": [Vector2(0, 34), Vector2(0, 98), Vector2(120, 198), Vector2(120, 198)],
}
const ZONES_NARROW: Dictionary[String, Array] = {
	"api": [Vector2(0, 174), Vector2(0, 174), Vector2(32, 174), Vector2(32, 174)],
	"web": [Vector2(24, 174), Vector2(24, 174), Vector2(120, 174), Vector2(120, 174)],
	"infra": [Vector2(0, 398), Vector2(0, 354), Vector2(32, 398), Vector2(32, 354)],
	"notes": [Vector2(0, 398), Vector2(0, 354), Vector2(120, 398), Vector2(120, 354)],
	"data": [Vector2(24, 398), Vector2(24, 354), Vector2(120, 398), Vector2(120, 354)],
}

## S3 CAMERA (2026-10-28): a map opens with its back wall in view. The first
## arrival at a map (OfficeNavigator._open()) frames the selection's pod, or its
## first zone at its sign, as before, and then lifts the view to the top wall's
## face (OfficeCamera.with_wall()) when the face and what the opening is for (the
## selected desk's signal, the first zone's sign) fit the view together; the
## bottom gives way. A view that already shows the face is not moved.
## Each screen: the pan with herdr's focus on api:p1 (its pod), then with no
## focus (the first zone, api). From the run's print; before this rule:
## (0, 98) and (0, 174) at 960x480 and 800x480, (0, 0) and (0, 114) at
## 1280x720, (0, 0) and (0, 174) at 960x640.
const OPENED: Dictionary[Vector2, Array] = {
	Vector2(960, 480): [Vector2(0, 40), Vector2(0, 40)],
	Vector2(800, 480): [Vector2(0, 40), Vector2(0, 40)],
	Vector2(1280, 720): [Vector2(0, 0), Vector2(0, 40)],
	Vector2(960, 640): [Vector2(0, 0), Vector2(0, 40)],
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
	# Both seat sides in every state: web:p2 (near) asks beside web:p1 (far),
	# data:p2 (near) works, api:p2 (far) and infra:p3 (near) idle at their seats
	# with a mug, api:p3 (near) and web:p3 (far) are shells.
	fixture = _dict(fixture_file, "snapshot")
	fixture = _with(_with(fixture, "web:p2", {"agent_status": "blocked"}), "data:p2", {"agent_status": "working"})
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


## The fixture drawn and settled in a window of `screen`.
func _office(screen := Vector2(SCREEN)) -> OfficeDouble:
	var office := await _live_office(fixture, screen)
	office.settle()
	await _frames(2)
	return office


## The furthest the pan goes on the shown map.
func _far(office: OfficeDouble) -> Vector2:
	return (office.camera.world_size - office.camera.free_rect().size).max(Vector2.ZERO)


## reveal() for every desk of `wanted`, plainly and with its pod, from no pan
## and from the far corner, against the pans 6413cec left.
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


## point() at every desk of `wanted`, against the frames 6413cec drew.
func _pointed(office: OfficeDouble, wanted: Dictionary[String, Rect2], where: String) -> void:
	var pointer := office.floor_view.pointer
	for pane_id: String in wanted:
		office.floor_view.point(_pk(pane_id))
		_eq([pointer.key, pointer.visible], [_pk(pane_id), true], "%s: the pointer is at %s" % [where, pane_id])
		_eq(pointer.rect, wanted[pane_id], "%s: and frames %s where it did" % [where, pane_id])
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


## reveal(key) and reveal(key, true) leave the pan where 6413cec left it, for
## every desk of the fixture: a seated worker far and near, a blocked one with
## its chip on either side, an idle one at the seat, and a shell.
func test_a_desk_is_revealed_where_it_was_at_800x480() -> void:
	var office := await _office()
	# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the world under the 70 band,
	# (16, 68) -> (16, 86), 272 -> 254 deep (this run's print).
	_eq(office.world.position, Vector2(16, 86), "the world stands at the HUD's free corner")
	# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: 241 -> 276 deep.
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: 120 tall docked, the world 4 shorter (276 -> 272).
	_eq(office.camera.free_rect(), Rect2(16, 86, 776, 254), "with 776x254 of it in view")
	_eq(office.floor_view.root.position, Vector2(0, OfficeScene.PLATE_HEIGHT), "and the floor under the plate")
	_reveals(office, REVEAL_800, "800x480")
	_done(office)


## The smallest window: the map's 416 units fit the 420 in view, so it pans
## only up and down (S3 BAR-b, 2026-10-27: 340 with the rail, so it panned 76
## sideways too). Z1 (2026-10-27): two lanes of 4 (the narrowest plan,
## FRAME-Q2), 416 wide as one lane of 9 was, 33 rows deep instead of 40.
func test_a_desk_is_revealed_where_it_was_in_the_smallest_window() -> void:
	var office := await _office(Vector2(480, 320))
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the two rows 54 tall, the world 4 shorter (202 ->
	# 198), the far corner 4 lower.
	_eq(office.camera.free_rect(), Rect2(16, 48, 456, 198), "456x198 of the world in view")
	_eq(_far(office), Vector2(0, 858), "the pan goes nowhere sideways")
	_reveals(office, REVEAL_480, "480x320")
	# A reveal starts from the pan as it is and leaves it between units when
	# nothing has to move; only the camera's next frame rounds, and only its
	# position.
	office.camera.pan = Vector2(0, 130.75)
	office.reveal(_pk("api:p1"))
	_eq(office.camera.pan, Vector2(0, 130.75), "api:p1 already in view from a pan between units: no move")
	await _frames(1)
	_eq(office.camera.pan, Vector2(0, 130.75), "the next frame keeps the pan")
	_eq(office.camera.position, Vector2(0, 131), "and rounds the camera's position")
	office.camera.pan = Vector2(0, 300.75)
	office.reveal(_pk("api:p1"))
	_eq(office.camera.pan, Vector2(0, 198), "from below: up to its headroom")
	_done(office)


## A wide window plans seven lanes (six before S3 BAR-b, 2026-10-27, and three
## of 9 before Z1): the pans are still the ones 6413cec left. (It moved the
## world's origin too while the SPACES rail was wider there; the world stands
## 16 in at every width now.)
func test_a_desk_is_revealed_where_it_was_in_a_wide_window() -> void:
	var office := await _office(Vector2(1280, 720))
	# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the world under the 70 band,
	# (16, 68) -> (16, 86), 512 -> 494 deep (this run's print).
	_eq(office.world.position, Vector2(16, 86), "the world stands where it does in every tall window")
	# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: 481 -> 516 deep.
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: 120 tall docked, the world 4 shorter (516 -> 512).
	_eq(office.camera.free_rect(), Rect2(16, 86, 1256, 494), "with 1256x494 of it in view")
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


## Z1 (2026-10-27): a 1024x960 window leaves the world 836x788 units, planned
## at 26 cells: four lanes of 4 now, so the fixture's map is 23 cells by 19
## (608 units, 640 with its plate; two lanes of 9 made it 26 deep, 864 with the
## plate, taller than the room) and fits the room: the view opens unpanned, and
## a real drag and the arrow keys pan nothing (OfficeCamera clamps the pan to
## the map). S3 BAR-b (2026-10-27): the rail gone, the world is 964 wide, 30
## cells, five lanes; the map still fits. "Every zone's row on the SPACES rail
## is marked in view" retired with the rail's in-view marks.
func test_a_map_that_fits_the_view_cannot_be_panned() -> void:
	var office := await _office(Vector2(1024, 960))
	var room := office.camera.free_rect()
	var world := office.camera.world_size
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
## camera's next frame clamps the pan to the map (infra on the 800x480
## window's map, and every zone of the shallow 1280x720 one, stop at the map's
## end).
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


## point() frames the desk's click area and its chip, grown by
## OfficePointer.GROW and on whole units, in the floor's own coordinates
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
## along it are what 6413cec showed. Z1 (2026-10-27): a lane is 4 cells, pitch
## 5, a new zone takes lanes until it stands one row; the map replans. The
## 800x480 bottom is the far pan's now (its map is 26 rows deep, so the bottom
## shows web's near chip and infra's); 480x320 (two lanes, 13x33, FRAME-Q2)
## keeps its top and middle values and its bottom is 888 down (1112 before).
## D2 (2026-10-27): the band is two cells (SEATED-Q2): every pan 32 less (the
## middles 470 and 524, the 480x320 bottom 856); the arrows' places along the
## edges move with the shorter map (from the print).
## S3 BAR-b (2026-10-27): the SPACES rail is gone; the world starts 16 in and
## first plans take its width. At 800x480 web stands beside api in the first
## row: at the top its far chip is in view and only web:p2's near one is below
## (one blocked); at the bottom web:p1's is above; 150 down every chip is in
## view. At 480x320 the map fits across, so the right-hand corners (pan 76)
## are the left-hand ones and their two clauses retire; the middle is 0 across.
## Places along the edges from the print.
func test_the_arrows_stand_where_they_stood() -> void:
	var office := await _office()
	# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: the places along
	# the taller edge from the print (0.5083 -> 0.5104, 0.3608 -> 0.3320).
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the world 4 shorter; the places along the edge from
	# the print, the same chips on the same edges.
	# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the world 18 shorter; the places
	# along the edge from the print (0.5101 -> 0.5091, 0.3354 -> 0.3504), the same chips on the same edges.
	var below := [
		_arrow("web", "web:p2", 1, EdgeArrowModel.Edge.BOTTOM, "0.5091"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.3504")
	]
	_eq(await _arrows_at(office, Vector2.ZERO), below, "800x480, at the top: web's near chip and infra's below")
	# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: the far corner is
	# 35 less (332), so the bottom's 276-unit view holds web:p2's near chip too: one blocked above, not two
	# (place 0.5075 -> 0.5093). The bottom is the bottom: no pan restores both chips above here.
	# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the far corner 18 lower (354),
	# and the bottom's 254-unit view no longer holds web:p2's near chip: both of web's blocked are above again (1 -> 2,
	# as before S3 PANEL-a1 round 2; a change of meaning, reported), place from the print (0.5091 -> 0.5081).
	_eq(
		await _arrows_at(office, _far(office)),
		[_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.5081")],
		"800x480, at the bottom: both of web's chips above, infra's in view"
	)
	# S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the
	# 241-unit view no longer holds web:p1's chip and infra:p1's at once (284 apart): in the middle, infra's below.
	_eq(
		await _arrows_at(office, Vector2(0, 150)),
		# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: the place
		# along the taller edge from the print (0.2528 -> 0.1888).
		# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the place from the print
		# (0.1967 -> 0.2304).
		[_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2304")],
		"800x480, in the middle: web's chips in view, infra's below"
	)
	_done(office)
	office = await _office(Vector2(480, 320))
	below = [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.BOTTOM, "0.4120"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.4454")
	]
	var above := [
		_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4346"),
		_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.3797")
	]
	_eq(await _arrows_at(office, Vector2.ZERO), below, "480x320, at the top")
	_eq(await _arrows_at(office, Vector2(0, 856)), above, "480x320, at the bottom")
	_eq(
		await _arrows_at(office, Vector2(0, 524)),
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2979")],
		"480x320, in the middle: one of web's two chips is above the view"
	)
	_done(office)


## An arrow stands by its desk's chip alone, to the unit: with the view's top
## edge one unit into the chip there is none, and with it at the chip's bottom
## edge there is one, although the seat under a far chip is then wholly in
## view (the chip and the seat together are what a reveal frames, not what an
## arrow aims at). A near seat's chip is below its sitter: web:p2's counts
## from the unit the view's top passes it, while its seat left the view above.
## Z1 (2026-10-27): a lane is 4 cells, pitch 5, a new zone takes lanes until it
## stands one row; the map replans. In the 480x320 window: the 800x480 map is
## 26 rows deep now and its pan stops (556) short of web:p2's and infra:p1's
## edges; the 480x320 map (13x33, the narrowest plan's two lanes) pans 888 down,
## past all three. The 200-unit view leaves infra below while web:p1's chip
## passes the top.
func test_an_arrow_follows_its_chip_to_the_unit() -> void:
	var office := await _office(Vector2(480, 320))
	var room := office.camera.free_rect()
	var far_chip := office.floor_view.seat(_pk("web:p1")).node.chip_rect()
	var far_seat := office.floor_view.seat(_pk("web:p1")).node.target_rect()
	# D2 (2026-10-27): the band is two cells (SEATED-Q2): every y 32 less.
	# S3 BAR-b (2026-10-27): the world 16 in, not 96: every x 80 less, and the
	# places along the 420-wide edges from the print.
	_eq([far_chip, far_seat], [Rect2(81, 504, 30, 16), Rect2(81, 520, 30, 40)], "web:p1's chip over its seat")
	var edge := far_chip.end.y - room.position.y
	_eq(edge, 472.0, "the pan that puts the view's top at the chip's bottom")
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the world 4 shorter (202 -> 198); the places from
	# the print, the same chips on the same edges.
	var infra_below := _arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2277")
	_eq(await _arrows_at(office, Vector2(0, edge - 1)), [infra_below], "one unit of web:p1's chip in view: no arrow")
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.1997"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2254")
		],
		"the chip just out of view, its seat still in: the arrow"
	)
	_check(far_seat.intersects(Rect2(Vector2(0, edge) + room.position, room.size)), "the seat is in view then")
	_eq(
		await _arrows_at(office, Vector2(0, edge + 1)),
		[
			_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.2025"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.2230")
		],
		"a unit further: the arrow, a little along"
	)
	var near_chip := office.floor_view.seat(_pk("web:p2")).node.chip_rect()
	var near_seat := office.floor_view.seat(_pk("web:p2")).node.target_rect()
	_eq([near_chip, near_seat], [Rect2(81, 608, 30, 16), Rect2(81, 568, 30, 38)], "web:p2's chip under its seat")
	edge = near_chip.end.y - room.position.y
	_eq(
		await _arrows_at(office, Vector2(0, edge - 1)),
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.3470")],
		"one unit of web:p2's chip in view: only web:p1 counts"
	)
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.3477")],
		"web:p2's chip just out of view: both count"
	)
	var infra_chip := office.floor_view.seat(_pk("infra:p1")).node.chip_rect()
	edge = infra_chip.end.y - room.position.y
	_eq(
		await _arrows_at(office, Vector2(0, edge - 1)),
		[_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4026")],
		"one unit of infra:p1's chip in view: web's arrow alone"
	)
	_eq(
		await _arrows_at(office, Vector2(0, edge)),
		[
			_arrow("web", "web:p1", 2, EdgeArrowModel.Edge.TOP, "0.4029"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.TOP, "0.1997")
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
## narrower view. S3 BAR-b (2026-10-27): the four-lane map is 736 wide, wider
## than 616, so the far corner moves 120 right and a reveal or an opening from
## it keeps or takes as much of it as it needs (REVEAL_NARROW, ZONES_NARROW);
## web and data, whose zones end at 640, open 24 in from no pan.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the relayout was `A`
## opening the drawer over the world's right edge; the drawer is gone, and a narrower window after the
## first plan is the relayout that leaves the same 616x276 room (the plan is fixed by its first width).
## Every number is the drawer's.
func test_a_relayout_moves_no_answer() -> void:
	var office := await _office()
	var plan := office.floor_view.plan
	office.test_screen = Vector2(640, 480)
	office.refresh()
	await _frames(2)
	_check(office.floor_view.plan == plan, "the narrower window plans nothing again")
	# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: the room
	# 241 -> 276 deep, the far corner 35 less (367 -> 332).
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the world 4 shorter, the far corner 4 lower (336 =
	# 608 - 272); places from the print.
	# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the room under the 70 band,
	# 18 lower and 18 shorter, the far corner 18 lower (354 = 608 - 254); places from the print.
	_eq(office.camera.free_rect(), Rect2(16, 86, 616, 254), "the world's room stops 8 short of the narrower edge")
	_eq(_far(office), Vector2(120, 354), "the far corner is 120 further right")
	for key: String in REVEAL_800:
		_eq(REVEAL_NARROW[key].slice(0, 2), REVEAL_800[key].slice(0, 2), "%s: from no pan, as at 800" % key)
	for key: String in ZONES_800:
		var shut: Array = ZONES_800[key].slice(0, 2)
		var past := Vector2(24, 0) if key in ["web", "data"] else Vector2.ZERO
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
		# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: places from
		# the print (0.5805 -> 0.6001, 0.3702 -> 0.3433).
		# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: places from the print
		# (0.5977 -> 0.5874, 0.3465 -> 0.3605).
		[
			_arrow("web", "web:p2", 1, EdgeArrowModel.Edge.BOTTOM, "0.5874"),
			_arrow("infra", "infra:p1", 1, EdgeArrowModel.Edge.BOTTOM, "0.3605")
		],
		"640 wide, at the top: web's near chip and infra's below, along the narrower view"
	)
	_eq(
		await _arrows_at(office, Vector2(0, 300)),
		# S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151), the world 35 taller: the place from
		# the print (0.5997 -> 0.6041).
		# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the place from the print
		# (0.6036 -> 0.6014).
		[_arrow("web", "web:p1", 1, EdgeArrowModel.Edge.TOP, "0.6014")],
		"640 wide, 300 down (the bottom before the panel docked): web's far chip above"
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
## wall's face with the first zone row's signs: opening on the selection's pod
## (the selected desk stays whole in view; its pod's near half gives way) and
## opening on the first zone.
func test_a_map_opens_with_its_back_wall_in_view() -> void:
	for screen: Vector2 in [Vector2(960, 480), Vector2(800, 480)]:
		var office := await _office(screen)
		_eq(office.navigator.active_key, _pk("api:p1"), "%s: herdr's focus is the selection" % screen)
		var desk := _floor_in_world(office, office.floor_view.signal_extent(_pk("api:p1")))
		_opens_on_the_wall(office, desk, "%s on api:p1's pod" % screen)
		_done(office)
		office = await _live_office(_focused_on(fixture, ""), screen)
		office.settle()
		await _frames(2)
		_eq(office.navigator.active_key, "", "%s: nothing is selected" % screen)
		_opens_on_the_wall(office, _sign_in_world(office, _pk("api")), "%s on its first zone" % screen)
		_done(office)


## Where each window opens, against OPENED; the view's bottom in the floor's
## coordinates is printed for the report. A desk that cannot be kept in view
## with the wall (api:p3, a near seat, at 960x480: 308 from the wall's top to
## its signal's bottom, 254 deep) wins over it: its pod is framed as before.
## A zone picked after the opening (a card's place) opens at its sign as
## before, and a map that fits the view stays unpanned (the wall already shows).
func test_a_map_opens_where_the_rule_puts_it() -> void:
	for screen: Vector2 in OPENED:
		var pans := []
		for snapshot: Dictionary in [fixture, _focused_on(fixture, "")]:
			var office := await _live_office(snapshot, screen)
			office.settle()
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
		_eq(pans, OPENED[screen], "%s: opened on api:p1's pod, then on the first zone" % screen)
	var near := await _live_office(_focused_on(fixture, "api:p3"), Vector2(960, 480))
	near.settle()
	await _frames(2)
	_eq(near.navigator.active_key, _pk("api:p3"), "api:p3 is the selection")
	_eq(near.camera.position, Vector2(0, 98), "a near desk the wall cannot share the view with: its pod as before")
	_check(
		_view(near).encloses(_floor_in_world(near, near.floor_view.signal_extent(_pk("api:p3")))),
		"and the desk is whole in view"
	)
	near.navigator.pick_zone(_pk("web"))
	near.refresh()
	await _frames(2)
	_eq(near.camera.position, Vector2(0, 174), "a zone picked afterwards opens at its sign, the wall not lifted in")
	_done(near)
