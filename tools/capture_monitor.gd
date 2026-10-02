extends "res://tools/command_test_base.gd"
## Pictures and timings of the terminal monitor: a real office in a real
## window, against a fake herdr this script scripts, opened and typed into by
## real input the way tools/test_monitor.gd drives it. Every screen it shows is
## one of the recorded dumps (tools/fixtures/monitor/*.ansi) handed to the fake,
## never a terminal's; every write goes to the fake. Windowed only.
##
## godot --path . --script tools/capture_monitor.gd -- --socket-a=<fake> \
##     --control-a=<its control> --pack=res://assets/<id>/manifest.json \
##     --zoom=<n> --out=<dir> --tag=<name> [--perf] [--fps=<n>]
##
## Writes <out>/monitor-<state>-<tag>.png for each of STATES, then quits 0; a
## state that never comes about quits 1 naming it. With `--perf` it takes no
## pictures: it times frames with the monitor open on the torture dump and on
## a screen that changes on every read, and prints MONITOR_PERF lines.

const STATES: Array[String] = ["claude", "codex", "vim", "torture", "unknown", "offline", "view-only"]
const FIXTURE := "snapshot_floors"
## The idle codex agent on the api floor, given a 120x40 terminal.
const PANE := "api:p2"
const COLUMNS := 120
const ROWS := 40
## `--perf --dense`: the pane's grid, at the monitor's clamp.
const DENSE := Vector2i(400, 200)
## Seconds each perf phase runs.
const PERF_SECONDS := 6.0

var _problems := PackedStringArray()


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
		elif argument == "--perf":
			args["perf"] = "1"
		elif argument == "--dense":
			args["dense"] = "1"
	for name: String in ["socket-a", "control-a", "pack", "zoom", "out", "tag"]:
		if not args.has(name) and not (name in ["out", "tag"] and args.has("perf")):
			print("CAPTURE_MONITOR: missing --%s=" % name)
			quit(2)
			return
	_capture.call_deferred()


func _marker() -> String:
	return "MONITOR CAPTURE"


func _capture() -> void:
	await process_frame
	# A window the OS made smaller than --resolution asked shows less, and
	# maybe at a lower even scale: not the picture this run is for.
	var clamped := CaptureDriver.window_problem(root, str(args.get("window", "")))
	if not clamped.is_empty():
		print("CAPTURE_MONITOR_FAILED: " + clamped)
		quit(1)
		return
	var zoom := int(args.zoom)
	var shown := OfficeScene.content_scale_for(root.size, zoom)
	if shown != zoom:
		print(
			(
				"CAPTURE_MONITOR_FAILED: the %dx%d window shows %dx, --zoom asked for %dx (did the OS shrink the window?)"
				% [root.size.x, root.size.y, shown, zoom]
			)
		)
		quit(1)
		return
	_ctl("control-a", "reset", {"fixture": FIXTURE})
	_ctl("control-a", "set_snapshot", {"snapshot": _sized()})
	_ctl("control-a", "allow", {"methods": OPERABLE})
	var office := _office_here(false)
	await _until(func() -> bool: return office.fleet.live_count() == 1, "the fake herdr is live")
	await _open(office)
	var monitor := office.hud.monitor
	if args.has("perf"):
		await _perf(office)
		quit(0)
		return
	for dump: String in ["claude", "codex", "vim", "torture"]:
		_ctl("control-a", "set_screen", {"pane_id": PANE, "source": "visible", "ansi": _dump(dump)})
		var first := TerminalScreen.new(COLUMNS, ROWS)
		first.set_text(_dump(dump))
		var wanted := first.row_text(2)
		await _shoot(dump, func() -> bool: return monitor.grid_node().screen.row_text(2) == wanted)
	# A key whose answer never comes back: unknown, said, not resent.
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "pane.send_text"})
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live input")
	await _type("x")
	await _shoot("unknown", func() -> bool: return monitor.message_text().begins_with("Unknown result"))
	# herdr goes away: the last screen stays, dimmed, OFFLINE.
	_ctl("control-a", "vanish")
	await _shoot("offline", func() -> bool: return monitor.live_text() == "○ OFFLINE")
	_ctl("control-a", "appear")
	_after_office(office)
	# `--read-only`: the monitor opens, reads nothing and says so.
	var viewer := _office_here(true)
	await _until(func() -> bool: return viewer.fleet.live_count() == 1, "the read-only office is live")
	await _open(viewer)
	await _shoot("view-only", func() -> bool: return viewer.hud.monitor.mode() == TerminalMonitor.Mode.VIEW_ONLY)
	if not _problems.is_empty():
		for problem in _problems:
			print("CAPTURE_MONITOR_FAILED: " + problem)
		quit(1)
		return
	print("CAPTURE_MONITOR_OK: %s" % args.tag)
	quit(0)


## The office in this window, as an operator (or read-only) on the fake.
func _office_here(read_only: bool) -> OfficeDouble:
	var zoom := int(args.zoom)
	var window := Vector2(root.size)
	var fit := OfficeScene.content_scale_for(root.size, zoom)
	var office := OfficeDouble.new()
	office.test_screen = window / fit
	var line := PackedStringArray(["--socket=" + args["socket-a"], "--pack=" + args.pack, "--zoom=%d" % zoom])
	if read_only:
		line.append("--read-only")
	if args.has("fps"):
		line.append("--fps=" + str(args.fps))
	office.test_args = AppArgs.parse(line)
	office.manifest_path = args.pack
	office.remember_theme = false
	_offices.append(office)
	root.add_child(office)
	return office


func _after_office(office: OfficeDouble) -> void:
	_offices.erase(office)
	root.remove_child(office)
	office.free()


## Pick the pane with a real click, then press Monitor on the staff panel's
## one line (the line keeps Monitor, `Monitor ⤢` or `⤢` by the width).
func _open(office: OfficeDouble) -> void:
	await _frames(4)
	var key := HerdrFleet.pane_key(HerdrFleet.LOCAL, PANE)
	await _until(func() -> bool: return not office.frame.zone_of(key).is_empty(), "the pane's zone is known")
	var zone_key := office.frame.zone_of(key)
	if office.navigator.shown_key != HerdrFleet.split_key(zone_key)[0]:
		await _zone_pick(office, zone_key)
	await _click_visible_pane(office, key)
	var name := "%CompactMonitor" if office.hud.card_compact() else "%MonitorButton"
	var button: Button = office.hud.inspector.get_node(name)
	await _until(button.is_visible_in_tree, "the card offers the monitor")
	await _click_control(button)
	await _until(office.hud.monitor_open, "the monitor is open")


## The fixture with PANE's terminal 120x40.
func _sized() -> Dictionary:
	var snapshot := _fixture(FIXTURE).duplicate(true)
	for layout: Dictionary in _list(snapshot, "layouts"):
		for slot: Dictionary in _list(layout, "panes"):
			if slot.get("pane_id") == PANE:
				var cells := DENSE if args.has("dense") else Vector2i(COLUMNS, ROWS)
				slot["rect"] = {"x": 80, "y": 0, "width": cells.x, "height": cells.y}
	return snapshot


## The densest screen measured: 400x200 cells of ASCII
## in 8 colours, a colour change every 5 cells, under ScreenReadResult.TEXT_MAX.
static func _dense() -> String:
	var rows := PackedStringArray()
	for row in DENSE.y:
		var cells := PackedStringArray()
		for column in range(0, DENSE.x, 5):
			cells.append("\u001b[3%dm%s" % [(row + floori(column / 5.0)) % 8, "abcde"])
		rows.append("".join(cells))
	return "\r\n".join(rows)


static func _dump(name: String) -> String:
	return FileAccess.get_file_as_string("res://tools/fixtures/monitor/%s.ansi" % name)


func _shoot(state: String, ready: Callable) -> void:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	while not ready.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not ready.call():
		_problems.append("%s never came about" % state)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var path: String = args.out.path_join("monitor-%s-%s.png" % [state, args.tag])
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_problems.append("cannot save %s: %s" % [path, error_string(error)])
	else:
		print("CAPTURE_OK: " + path)


## Frame times with the monitor open: the torture dump standing still, then a
## screen whose first row changes on every read (5 Hz).
func _perf(office: OfficeDouble) -> void:
	var grid := office.hud.monitor.grid_node()
	var phases := PackedStringArray(["dense"] if args.has("dense") else ["torture", "changing"])
	for phase: String in phases:
		var text := _dense() if phase == "dense" else _dump("torture")
		var screen := {"pane_id": PANE, "source": "visible", "ansi": text, "animate": phase != "torture"}
		_ctl("control-a", "set_screen", screen)
		await create_timer(1.0).timeout
		grid.parse_usec.clear()
		grid.draw_usec.clear()
		var reads := office.hud.monitor.reads_shown
		var frames := PackedFloat64Array()
		var last := Time.get_ticks_usec()
		var until := Time.get_ticks_msec() + int(PERF_SECONDS * 1000)
		while Time.get_ticks_msec() < until:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			last = now
		print(
			(
				"MONITOR_PERF %s %s: frame %s | parse %s | draw %s | reads shown %d in %.0f s | font %d units"
				% [
					args.get("tag", "-"),
					phase,
					_stats(frames),
					_stats(_ms(grid.parse_usec)),
					_stats(_ms(grid.draw_usec)),
					office.hud.monitor.reads_shown - reads,
					PERF_SECONDS,
					grid.font_size_now(),
				]
			)
		)


static func _ms(usec: PackedInt32Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for value in usec:
		result.append(value / 1000.0)
	return result


static func _stats(values: PackedFloat64Array) -> String:
	if values.is_empty():
		return "n=0"
	var sorted := values.duplicate()
	sorted.sort()
	var p50 := sorted[floori(sorted.size() * 0.5)]
	var p95 := sorted[mini(sorted.size() - 1, floori(sorted.size() * 0.95))]
	return "n=%d p50=%.2fms p95=%.2fms max=%.2fms" % [sorted.size(), p50, p95, sorted[sorted.size() - 1]]
