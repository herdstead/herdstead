extends "res://tools/office_test_base.gd"
## Day and night over the one pack (DayLight): the time of day as a light on
## the world, never a herdr state. The pure curve; then the live office with a
## clock the case hands in: the world's tint on its own canvas (the HUD keeps
## its colours), the lamps and contact shadows harder at night and redrawn
## when the light changes, the windows' night view as a texture swap, T turning
## the light over until the clock's own day or night turns, a held light
## (`--light=`), the bar's DAY / NIGHT, and night never passing for a lost
## connection. The live office (office_test_base) is why the suite runs
## --read-only with its own --socket and --work.


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("day-light-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "DAY LIGHT TESTS"


# --- cases --------------------------------------------------------------------


## Night is 1 before dawn's fade and after dusk's, 0 between them, and halfway
## at DAWN and DUSK themselves; minutes wrap round midnight.
func test_the_curve_follows_the_clock() -> void:
	_eq(DayLight.night_at(0.0), 1.0, "midnight is night")
	_eq(DayLight.night_at(12 * 60.0), 0.0, "noon is day")
	_eq(DayLight.night_at(DayLight.DAWN), 0.5, "halfway at dawn")
	_eq(DayLight.night_at(DayLight.DUSK), 0.5, "halfway at dusk")
	_eq(DayLight.night_at(DayLight.DAWN - DayLight.FADE / 2.0), 1.0, "night until dawn's fade begins")
	_eq(DayLight.night_at(DayLight.DAWN + DayLight.FADE / 2.0), 0.0, "day once it ends")
	_eq(DayLight.night_at(DayLight.DUSK + DayLight.FADE / 2.0), 1.0, "night once dusk's fade ends")
	_eq(DayLight.night_at(24 * 60.0 + 12 * 60.0), 0.0, "a clock past midnight wraps")
	_check(DayLight.night_at(DayLight.DUSK - 5.0) < DayLight.night_at(DayLight.DUSK + 5.0), "dusk darkens")
	_check(DayLight.is_night(0.5) and not DayLight.is_night(0.49), "night from the middle of a fade")
	_eq(DayLight.tint(0.0), Color.WHITE, "day leaves the world as painted")
	_eq(DayLight.tint(1.0), DayLight.NIGHT_TINT, "full night is the night tint")


## Following the clock, the world takes the night tint on its own canvas; the
## HUD is another canvas layer, so its colours stay as they are.
func test_the_clock_lights_the_world_and_leaves_the_hud() -> void:
	var office := await _clocked_office(23 * 60.0)
	var modulate: CanvasModulate = office.get_node("NightLight")
	_eq(office.night, 1.0, "at 23:00 the office is at night")
	_eq(modulate.color, DayLight.NIGHT_TINT, "the world takes the night tint")
	_check(office.hud.get_parent() == office and office.hud is CanvasLayer, "the HUD is its own canvas layer")
	office.clock = func() -> float: return 12 * 60.0
	await _light_tick(office)
	_eq(office.night, 0.0, "at noon it is day again")
	_eq(modulate.color, Color.WHITE, "and the world is as painted")
	_done(office)


## Night draws every lamp that burns harder, and the contact shadows too; the
## light changing redraws the lamps it touches, and the same light redraws none.
func test_night_burns_the_lamps_harder_and_redraws_them() -> void:
	var office := await _clocked_office(12 * 60.0)
	var table := office.floor_view.tables[0]
	var day_focus := table.lamp_color(OfficeTable.Lamp.FOCUS).a
	var drawn := table.lamps_drawn
	office.clock = func() -> float: return 23 * 60.0
	await _light_tick(office)
	_check(table.lamp_color(OfficeTable.Lamp.FOCUS).a > day_focus, "a focus lamp burns harder at night")
	_eq(table.night, 1.0, "the table knows it is night")
	_check(table.lamps_drawn > drawn, "the burning lamps are drawn again")
	var again := table.lamps_drawn
	await _light_tick(office)
	_eq(table.lamps_drawn, again, "the same night redraws no lamp")
	_done(office)


## The windows turn to the night view past the middle of a fade and back by
## day: the same nodes, another texture.
func test_the_windows_turn_to_night_in_place() -> void:
	var office := await _clocked_office(12 * 60.0)
	var windows := office.floor_view.windows()
	_check(not windows.is_empty(), "the floor has windows: %d" % windows.size())
	var art := office.art
	var day_view := art.sprite_texture(art.prop_sprite(ArtContract.PROP_WINDOW))
	var night_view := art.sprite_texture(art.prop_sprite(ArtContract.PROP_WINDOW_NIGHT))
	var ids: Array[int] = []
	for window in windows:
		ids.append(window.get_instance_id())
		_eq(window.texture, day_view, "by day the day view")
	office.clock = func() -> float: return 23 * 60.0
	await _light_tick(office)
	var now: Array[int] = []
	for window in office.floor_view.windows():
		now.append(window.get_instance_id())
		_eq(window.texture, night_view, "by night the night view")
	_eq(now, ids, "the same window nodes")
	_done(office)


## T turns the light over while the office follows the clock; it holds until
## the clock's own day or night turns, and then the clock leads again.
func test_t_turns_the_light_over_until_the_clock_turns() -> void:
	var office := await _clocked_office(12 * 60.0)
	_eq(office.night, 0.0, "noon")
	await _office_key(office, KEY_T)
	_eq(office.night, 1.0, "T: night at noon")
	office.clock = func() -> float: return 15 * 60.0
	await _light_tick(office)
	_eq(office.night, 1.0, "it holds through the afternoon")
	office.clock = func() -> float: return 19 * 60.0
	await _light_tick(office)
	_eq(office.night, 1.0, "night falls by itself: still night")
	await _office_key(office, KEY_T)
	_eq(office.night, 0.0, "T again: day at night")
	office.clock = func() -> float: return 8 * 60.0
	await _light_tick(office)
	_eq(office.night, 0.0, "the morning comes: day, the clock's own")
	office.clock = func() -> float: return 23 * 60.0
	await _light_tick(office)
	_eq(office.night, 1.0, "and the clock leads again")
	_done(office)


## A held light (`--light=day|night`, a capture's) ignores the clock, and T
## swaps it.
func test_a_held_light_ignores_the_clock_and_t_swaps_it() -> void:
	var office := await _clocked_office(12 * 60.0, OfficeScene.LightMode.NIGHT)
	_eq(office.night, 1.0, "held at night at noon")
	office.clock = func() -> float: return 3 * 60.0
	await _light_tick(office)
	_eq(office.night, 1.0, "still night")
	await _office_key(office, KEY_T)
	_eq(office.light_mode, OfficeScene.LightMode.DAY, "T swaps a held night for a held day")
	_eq(office.night, 0.0, "day")
	office.clock = func() -> float: return 3 * 60.0
	await _light_tick(office)
	_eq(office.night, 0.0, "held, whatever the clock says")
	_done(office)


## The bar says which light the office is in, and that T turns it.
func test_the_bar_says_day_or_night() -> void:
	var office := await _clocked_office(12 * 60.0)
	_eq(office.hud.bar.theme_line(), "STUDIO · DAY  [T]", "by day")
	await _office_key(office, KEY_T)
	_eq(office.hud.bar.theme_line(), "STUDIO · NIGHT  [T]", "by night")
	_done(office)


## Night is not a lost connection (invariant 4): a live floor at night keeps
## its people moving and is cooler, not greyer; a floor that loses its machine
## at night takes the stale tint on top, darker still.
func test_night_is_never_a_lost_connection() -> void:
	var office := await _clocked_office(23 * 60.0)
	var modulate: CanvasModulate = office.get_node("NightLight")
	var floor_view := office.floor_view
	_eq(floor_view.root.modulate, Color.WHITE, "a live floor at night is not dimmed as stale")
	_check(not floor_view.presentation.holding(), "and its people are not held still")
	var night_live := modulate.color
	var day_stale := office.art.stale_tint
	_check(night_live.b - night_live.r > 0.15, "night is cool: %s" % night_live)
	_check(absf(day_stale.b - day_stale.r) < 0.05, "a lost connection by day is grey: %s" % day_stale)
	_set_online(office, false)
	await _frames(2)
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "stale at night takes the stale tint")
	_eq(modulate.color, DayLight.NIGHT_TINT, "on top of the night's")
	var both := modulate.color * office.floor_view.root.modulate
	_check(both.v < night_live.v, "darker than a live night")
	_done(office)


# --- helpers ------------------------------------------------------------------


## A live office following a clock that says `minutes`, or held at `mode`.
func _clocked_office(minutes: float, mode := OfficeScene.LightMode.CLOCK) -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = Vector2(SCREEN)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	office.light_mode = mode
	office.clock = func() -> float: return minutes
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	_feed(office, fixture)
	await _frames(2)
	return office


## Long enough for the office to read its clock again (once a second).
func _light_tick(_office: OfficeDouble) -> void:
	await create_timer(1.2).timeout
	await _frames(1)
