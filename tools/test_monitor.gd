extends "res://tools/command_test_base.gd"
## The terminal monitor (docs/WRITE_BOUNDARY.md §3): its grid against the recorded dumps
## (tools/fixtures/monitor), and the monitor in a live office as an operator,
## against two fake herdrs of this suite's own. Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_monitor.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Every interaction is real input: clicks, keys, the wheel. The write gates of
## raw mode (order, queue, pace, refusals, audit) are in tools/test_raw_input.gd;
## these are the monitor's own. The last case sums up both fakes.

const DUMPS: Array[String] = ["claude", "codex", "less", "sh", "torture", "vim", "clock"]
## The pane every live case watches: bee's codex agent, 80x40 in the fixture.
const PANE := "alpha:p3"
## What one parse and draw of a hostile screen may take. Generous for a loaded
## machine: the hangs this guards against took more than 45 s (measured).
const FRAME_BUDGET_MSEC := 100
## The monitor on its own, for the cases that drive it against a scripted fleet.
const MONITOR_SCENE := preload("res://scenes/ui/terminal_monitor.tscn")


func _marker() -> String:
	return "MONITOR TESTS"


# --- the grid ---------------------------------------------------------------------


## Every recorded dump parses to exactly the rows herdr's own `text` read of the
## same screen gave, on a 120x40 grid.
func test_the_grid_parses_the_recorded_dumps() -> void:
	for name in DUMPS:
		var screen := TerminalScreen.new(120, 40)
		_check(screen.set_text(_dump(name, "ansi")), "%s: the first text changes the screen" % name)
		var rows := _dump(name, "txt").split("\n")
		for row in 40:
			var wanted := rows[row].strip_edges(false, true) if row < rows.size() else ""
			_eq(screen.row_text(row), wanted, "%s row %d" % [name, row])
		_check(not screen.set_text(_dump(name, "ansi")), "%s: the same text changes nothing" % name)


## The SGR subset lands on the cells: 16, 256 and true colour, bold, dim,
## italic, underline, reverse, strike and a combination, and every row starts
## again from the attributes the one before ended with.
func test_the_grid_reads_the_sgr_subset() -> void:
	var screen := TerminalScreen.new(120, 40)
	screen.set_text(_dump("torture", "ansi"))
	_eq(Array(screen.fg[2].slice(4, 8)), [0, 1, 2, 3], "16 colours by index")
	_eq(screen.fg[3][5], 16, "256 colours")
	_eq(screen.fg[4][6], TerminalScreen.RGB_FLAG | (0 << 16) | (255 << 8) | 128, "true colour")
	var marks := screen.flags[5]
	var at := func(word: String) -> int: return marks[screen.row_text(5).find(word)]
	_eq(at.call("bold"), TerminalScreen.BOLD, "bold")
	_eq(at.call("dim"), TerminalScreen.DIM, "dim")
	_eq(at.call("italic"), TerminalScreen.ITALIC, "italic")
	_eq(at.call("under"), TerminalScreen.UNDERLINE, "underline")
	_eq(at.call("reverse"), TerminalScreen.REVERSE, "reverse")
	_eq(at.call("strike"), TerminalScreen.STRIKE, "strike")
	_eq(at.call("combo"), TerminalScreen.BOLD | TerminalScreen.UNDERLINE, "combined")
	_eq(screen.fg[5][screen.row_text(5).find("combo")], 208, "with its colour")
	var carried := TerminalScreen.new(10, 3)
	carried.set_text("\u001b[31mred\r\nstill red\u001b[0m\r\nplain")
	_eq(
		[carried.fg[0][0], carried.fg[1][0], carried.fg[2][0]],
		[1, 1, TerminalScreen.DEFAULT],
		"attributes carry across rows"
	)
	carried.set_text("\u001b[32mred\r\nstill red\u001b[0m\r\nplain")
	_eq(carried.reparsed, 2, "a row whose starting attributes changed is parsed again")
	_eq(carried.fg[1][0], 2, "and takes them")
	var odd := TerminalScreen.new(20, 1)
	odd.set_text("a\u001b]0;title\u0007b\u001b[2Jc\u001b[38;5mz\u001b")
	_eq(odd.row_text(0), "a0;titlebcz", "only SGR is read: another CSI is skipped whole, an OSC's ESC and BEL dropped")


## Wide characters take two columns and graphemes one cell: CJK, emoji with
## skin tones, ZWJ families and flags, combining marks. A wide character that
## would cross the last column is not drawn half.
func test_wide_characters_and_graphemes_sit_on_the_grid() -> void:
	var screen := TerminalScreen.new(120, 40)
	screen.set_text(_dump("torture", "ansi"))
	_eq(
		[screen.column_of(6, "中"), screen.column_of(6, "文"), screen.column_of(6, "한")],
		[5, 7, 33],
		"CJK every 2 columns, the fullwidth bar too"
	)
	_eq(screen.flags[6][5] & TerminalScreen.WIDE, TerminalScreen.WIDE, "a wide cell")
	_eq(screen.flags[6][6] & TerminalScreen.CONTINUATION, TerminalScreen.CONTINUATION, "and its continuation")
	_eq(screen.glyphs[6][6], "", "which draws nothing")
	_eq(screen.row_text(6).find("end"), 23, "the row reads on after them")
	_eq(screen.column_of(6, "e"), 40, "'end' sits at column 40, after 17 wide characters")
	var emoji := ["😀", "👍🏽", "👨\u200d👩\u200d👧", "🇨🇳"]
	_eq(emoji.map(func(cluster: String) -> int: return screen.column_of(7, cluster)), [7, 10, 13, 16], "one cell each")
	for cluster: String in emoji:
		_eq(TerminalScreen.width_of(cluster), 2, "two columns: " + cluster)
	_eq(screen.column_of(8, "e\u0301"), 11, "a combining mark stays with its letter, in one cell")
	_eq(screen.column_of(8, "a\u0308"), 13, "every one of them")
	_eq(TerminalScreen.width_of("e\u0301"), 1, "one column")
	var edge := TerminalScreen.new(5, 1)
	edge.set_text("abcd中")
	_eq(edge.row_text(0), "abcd", "a wide character past the edge is not drawn half")
	_eq(
		[TerminalScreen.width_of("\u200b"), TerminalScreen.width_of("a"), TerminalScreen.width_of("✔")],
		[0, 1, 1],
		"widths"
	)


## Only rows whose text changed are parsed again.
func test_only_changed_rows_are_parsed_again() -> void:
	var screen := TerminalScreen.new(120, 40)
	var text := _dump("clock", "ansi")
	screen.set_text(text)
	var rows := text.split("\n")
	rows[5] = "\u001b[0m\u001b[38;5;3mchanged\u001b[0m\r"
	_check(screen.set_text("\n".join(rows)), "a change shows")
	_eq(screen.reparsed, 1, "one row parsed again")
	_eq(screen.row_text(5), "changed", "the new row")
	rows[5] = "\u001b[0m\u001b[38;5;3mchanged, colour left on\r"
	screen.set_text("\n".join(rows))
	_eq(screen.reparsed, 2, "a row that leaves its colour on also parses the next again")


## The grid draws every dump inside its control, integer-scaled and centred,
## and redraws only when the text changed.
func test_the_grid_draws_every_dump() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var holder := Control.new()
	holder.theme = HudTheme.build(art, OfficeDraw.new(art).font)
	holder.size = Vector2(700, 440)
	root.add_child(holder)
	var grid := TerminalMonitorGrid.new()
	grid.theme_type_variation = &"MonitorGrid"
	grid.size = holder.size
	holder.add_child(grid)
	grid.set_grid(120, 40)
	for name in DUMPS:
		var before := grid.draw_usec.size()
		_check(grid.show_text(_dump(name, "ansi")), name + " changes the grid")
		await _frames(2)
		_eq(grid.draw_usec.size(), before + 1, name + " is drawn once")
		var rect := grid.grid_rect()
		_check(Rect2(Vector2.ZERO, grid.size).encloses(rect), "%s fits: %s in %s" % [name, rect, grid.size])
		_check(grid.font_size_now() >= TerminalMonitorGrid.FONT_SMALLEST, "a whole font size")
	var drawn := grid.draw_usec.size()
	grid.show_text(_dump("clock", "ansi"))
	await _frames(2)
	_eq(grid.draw_usec.size(), drawn, "the same text is not drawn again")
	holder.free()


# --- the monitor, live -----------------------------------------------------------------


## The card's "Monitor ⤢" opens it on the pane; it reads the screen and shows
## herdr's rows; Ctrl+] closes it and is never sent; the reads stop.
func test_ctrl_bracket_closes_and_reads_stop() -> void:
	var office := await _live(_dump("codex", "ansi"))
	var monitor := office.hud.monitor
	await _until(
		func() -> bool: return monitor.grid_node().screen.row_text(5) == "› 1. Yes, continue", "codex's screen"
	)
	_eq(monitor.live_text(), "● LIVE INPUT", "live input, said")
	await _press_key(KEY_BRACKETRIGHT, 0, KEY_MASK_CTRL)
	_check(not office.hud.monitor_open(), "Ctrl+] closed it")
	await _until(func() -> bool: return not monitor.reading(), "the last read settles")
	var reads := _screen_reads()
	await _wait(1.0)
	_eq(_screen_reads(), reads, "no screen read after it closed")
	_eq(_all_inputs(), 0, "and nothing was sent")


## Esc and every other key go to the terminal, in the key map's names; typed
## characters and an input method's commit as text; Home and its kind are
## refused with the reason in the status line.
func test_esc_and_the_key_map_go_to_the_terminal() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	await _press_key(KEY_ESCAPE)
	await _press_key(KEY_C, 0, KEY_MASK_CTRL)
	await _press_key(KEY_UP)
	await _press_key(KEY_TAB, 0, KEY_MASK_SHIFT)
	await _press_key(KEY_F5)
	await _press_key(KEY_UP, 0, KEY_MASK_ALT)
	await _press_key(KEY_ENTER, 0, KEY_MASK_SHIFT)
	await _press_key(KEY_A, 0x41, KEY_MASK_SHIFT)
	await _press_key(KEY_NONE, 0x4E2D)
	await _press_key(KEY_BACKSPACE)
	await _until(func() -> bool: return _inputs("control-b").size() == 10, "ten requests")
	_eq(
		_inputs("control-b").map(_described),
		[
			"keys esc",
			"keys ctrl+c",
			"keys up",
			"keys shift+tab",
			"keys f5",
			"keys alt+up",
			"keys shift+enter",
			"text A",
			"text 中",
			"keys backspace",
		],
		"each in herdr's names, in order"
	)
	await _press_key(KEY_HOME)
	_check(monitor.message_text().contains("Home/End/PgUp/PgDn/Insert/Delete can't be sent"), monitor.message_text())
	await _press_key(KEY_V, 0x76, KEY_MASK_CTRL | KEY_MASK_SHIFT)
	await _press_key(KEY_S, 0x73, KEY_MASK_META)
	await _wait(0.4)
	_eq(_inputs("control-b").size(), 10, "nothing more was sent")
	_eq(office.fleet.write_log().size(), 10, "ten writes audited")


## One frame's keys are one request per run of the same kind, in order.
func test_one_frame_is_one_request_per_run() -> void:
	var office := await _live()
	_check(office.hud.monitor_open(), "open")
	_burst([[KEY_L, 0x6C, 0], [KEY_S, 0x73, 0], [KEY_C, 0, KEY_MASK_CTRL], [KEY_A, 0x61, 0], [KEY_B, 0x62, 0]])
	await _frames(2)
	await _until(func() -> bool: return _inputs("control-b").size() == 3, "three requests")
	_eq(_inputs("control-b").map(_described), ["text ls", "keys ctrl+c", "text ab"], "text, keys, text")


## While the monitor has the keyboard no office key fires: not the theme, the
## zoom, the floor, the attention overlay, "next", nor the card's Enter. They
## are the terminal's.
func test_office_keys_do_not_fire_while_it_is_open() -> void:
	var office := await _live()
	var theme := office.art.id
	var zoom := office.zoom
	var shown := office.navigator.shown_key
	var picked := office.picked_key
	await _press_key(KEY_T, 0x74)
	await _press_key(KEY_EQUAL, 0x3D)
	await _press_key(KEY_MINUS, 0x2D)
	await _press_key(KEY_A, 0x61)
	await _press_key(KEY_N, 0x6E)
	await _press_key(KEY_PAGEDOWN)
	await _press_key(KEY_ENTER)
	await _until(func() -> bool: return _inputs("control-b").size() == 6, "six sent to the terminal")
	_eq(
		[office.art.id, office.zoom, office.navigator.shown_key, office.picked_key],
		[theme, zoom, shown, picked],
		"unchanged"
	)
	_check(not office.hud.holds_keyboard(), "the list did not take the keyboard (A)")
	_check(not office.hud.inspector.answering(), "no answer mode")
	_eq(
		_inputs("control-b").map(_described),
		["text t", "text =", "text -", "text a", "text n", "keys enter"],
		"the terminal's"
	)
	# A click on a desk behind the monitor picks nothing.
	var other := HerdrFleet.pane_key(BEE, "alpha:p1")
	var point := _desk_point(office, other)
	await _click(point)
	await _frames(3)
	_eq(office.picked_key, picked, "the office under it takes no click")
	_eq(office.hud.monitor.pane_key(), HerdrFleet.pane_key(BEE, PANE), "and the monitor is not retargeted")


## One monitor at a time: asking for another pane while it is open changes nothing.
func test_one_monitor_at_a_time() -> void:
	var office := await _live()
	var aimed := office.hud.monitor.target()
	office.hud.monitor_requested.emit(HerdrFleet.pane_key(BEE, "alpha:p1"))
	await _frames(2)
	_check(office.hud.monitor.target() == aimed, "still aimed at the same terminal")
	_eq(office.hud.monitor.pane_key(), HerdrFleet.pane_key(BEE, PANE), "on the same pane")


## The wheel scrolls a local view of `recent`, fetched when it first turns,
## without writing and without touching herdr's scroll; any key goes back to
## the live screen (and is sent).
func test_the_wheel_scrolls_back_without_writing() -> void:
	var lines := PackedStringArray()
	for index in 100:
		lines.append("\u001b[0mhistory line %d" % index)
	_fakes()
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "recent", "ansi": "\r\n".join(lines)})
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "visible", "ansi": "$ live screen\r\n"})
	var office := await _open_live()
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.grid_node().screen.row_text(0) == "$ live screen", "the live screen")
	await _wheel(monitor.grid_node(), MOUSE_BUTTON_WHEEL_UP)
	await _until(
		func() -> bool: return monitor.grid_node().screen.row_text(0).begins_with("history line"), "scrollback"
	)
	var recent := _asked("control-b", "pane.read").filter(
		func(p: Dictionary) -> bool: return p.get("source") == "recent"
	)
	_eq(recent.size(), 1, "fetched once, on demand")
	var asked: Dictionary = recent[0] if not recent.is_empty() else {}
	_eq(asked.get("lines"), HerdrCommands.SCROLLBACK_LINES_MAX, "at most 999 lines")
	_check(monitor.scrolled_back(), "the view is back in time")
	_eq(monitor.grid_node().screen.row_text(0), "history line 57", "40 rows ending 3 rows up from the bottom")
	await _wheel(monitor.grid_node(), MOUSE_BUTTON_WHEEL_UP)
	_eq(monitor.grid_node().screen.row_text(0), "history line 54", "three more")
	_eq(_all_inputs(), 0, "scrolling wrote nothing")
	await _press_key(KEY_Q, 0x71)
	_check(not monitor.scrolled_back(), "a key returns to live")
	_eq(monitor.grid_node().screen.row_text(0), "$ live screen", "the live screen again")
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "and the key is sent")
	for method: String in _list(_ctl("control-b", "stats"), "methods"):
		_check(method != "pane.scroll", "herdr's own scroll is never touched")


## Five reads a second while the window has focus; once a second without it.
func test_losing_window_focus_drops_reads_to_one_a_second() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	var focused := await _reads_over(2.0)
	_check(focused >= 7, "focused: %d reads in 2 s" % focused)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_eq(monitor.read_interval(), TerminalMonitor.READ_UNFOCUSED, "one a second")
	await _wait(1.2)
	var unfocused := await _reads_over(3.0)
	_check(unfocused >= 2 and unfocused <= 4, "unfocused: %d reads in 3 s" % unfocused)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var again := await _reads_over(2.0)
	_check(again >= 7, "focused again: %d reads in 2 s" % again)
	_eq(_all_inputs(), 0, "reading never writes")


## Offline: the last screen stays, dimmed, the monitor says OFFLINE and sends
## nothing; back with the same terminal, it is live again after a fresh read.
func test_offline_freezes_the_screen_and_sends_nothing() -> void:
	var office := await _live(_dump("sh", "ansi"))
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.grid_node().screen.row_text(1) == "hello from sh", "the screen")
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.OFFLINE, "offline")
	_eq(monitor.live_text(), "○ OFFLINE", "says so")
	_check(monitor.grid_node().dimmed, "dimmed")
	_eq(monitor.grid_node().screen.row_text(1), "hello from sh", "the last screen stays")
	await _press_key(KEY_X, 0x78)
	await _press_key(KEY_ENTER)
	await _wait(0.5)
	_ctl("control-b", "appear")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live again after reconnecting")
	_check(not monitor.grid_node().dimmed, "no longer dimmed")
	_eq(_all_inputs(), 0, "nothing typed while offline was sent later")
	await _press_key(KEY_Y, 0x79)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "a key after it is back goes")


## The paste chord pastes the clipboard through the paste path; ESC in it
## refuses it whole and says so.
func test_the_paste_chord_pastes_and_refuses_escape() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	var board: Array[String] = ["echo pasted\n"]
	monitor.clipboard = func() -> String: return board[0]
	var chord := KEY_MASK_META if OS.get_name() == "macOS" else KEY_MASK_CTRL | KEY_MASK_SHIFT
	await _press_key(KEY_V, 0x76, chord)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "the paste")
	_eq(_inputs("control-b").map(_described), ["paste echo pasted\n"], "through pane.send_input, whole")
	board[0] = "rm -rf x\u001b[201~"
	await _press_key(KEY_V, 0x76, chord)
	await _until(func() -> bool: return monitor.message_text().contains("paste holds ESC"), "refused, said")
	_eq(_inputs("control-b").size(), 1, "nothing of it sent")


## Input still queued when the pane's terminal changes is refused at its turn,
## never sent, and the monitor keeps saying why and keeps offering to follow.
func test_input_queued_across_a_new_terminal_keeps_follow() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	_ctl("control-b", "next", {"action": "hold", "method": "pane.send_text"})
	await _press_key(KEY_A, 0x61)
	await _until(func() -> bool: return _number(_ctl("control-b", "stats"), "held_replies") == 1, "a is out, held")
	await _press_key(KEY_B, 0x62)
	await _until(func() -> bool: return office.fleet.queued_input(monitor.pane_key()) == 1, "b waits behind it")
	var replaced := _changed(_raw(), PANE, {"terminal_id": "term-alpha-3-next"})
	_ctl("control-b", "set_snapshot", {"snapshot": replaced})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.STOPPED, "input stopped")
	_ctl("control-b", "release_held")
	await _until(func() -> bool: return office.fleet.write_log().back().refusal == "IDENTITY_CHANGED", "b refused")
	await _frames(3)
	var follow: Button = monitor.get_node("%FollowButton")
	_check(follow.is_visible_in_tree(), "Follow is still offered")
	_check(monitor.message_text().begins_with("New terminal"), "and the stop is still said: " + monitor.message_text())
	await _click_control(follow)
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live on the new terminal")
	await _press_key(KEY_C, 0x63)
	await _until(func() -> bool: return _inputs("control-b").size() == 2, "c went")
	_eq(_inputs("control-b").map(_described), ["text a", "text c"], "a and c; b never")


## An agent starting, or a new session (`/clear`), in the watched terminal
## keeps input flowing: raw mode is bound to the terminal, and the viewer is
## watching it.
func test_a_new_agent_or_session_in_the_terminal_keeps_input() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	var key := monitor.pane_key()
	await _press_key(KEY_A, 0x61)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "a went")
	var aimed := monitor.target().identity_key
	var cleared := {"source": "fixture", "agent": "claude", "kind": "session_id", "value": "after-clear"}
	_ctl(
		"control-b", "set_snapshot", {"snapshot": _changed(_raw(), PANE, {"agent": "claude", "agent_session": cleared})}
	)
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(
		func() -> bool: return office.frame.pane(key) != null and office.frame.pane(key).identity_key() != aimed,
		"the office sees the new agent"
	)
	await _frames(5)
	_eq(monitor.mode(), TerminalMonitor.Mode.LIVE, "still live")
	await _press_key(KEY_B, 0x62)
	await _until(func() -> bool: return _inputs("control-b").size() == 2, "b went too")
	_eq(_inputs("control-b").map(_described), ["text a", "text b"], "both, to the same terminal")


## Closing the monitor drops what it queued: the request out stays out and
## ends as it ends; everything behind it is CANCELLED and never sent.
func test_closing_drops_queued_input() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	var key := monitor.pane_key()
	_ctl("control-b", "next", {"action": "hold", "method": "pane.send_text"})
	await _press_key(KEY_A, 0x61)
	await _until(func() -> bool: return _number(_ctl("control-b", "stats"), "held_replies") == 1, "a is out, held")
	await _press_key(KEY_B, 0x62)
	await _press_key(KEY_C, 0x63)
	await _press_key(KEY_D, 0x64)
	await _until(func() -> bool: return office.fleet.queued_input(key) == 3, "b, c and d wait")
	await _press_key(KEY_BRACKETRIGHT, 0, KEY_MASK_CTRL)
	_check(not office.hud.monitor_open(), "closed")
	_eq(office.fleet.queued_input(key), 0, "nothing left queued")
	_ctl("control-b", "release_held")
	var settled := func() -> bool:
		var writes := office.fleet.write_log()
		return not writes.is_empty() and writes[0].last_state() == "ACCEPTED"
	await _until(settled, "a settles")
	await _wait(0.5)
	_eq(_inputs("control-b").map(_described), ["text a"], "only the one in flight reached herdr")
	var states := office.fleet.write_log().map(func(e: CommandAuditEntry) -> String: return e.last_state())
	_eq(states, ["ACCEPTED", "CANCELLED", "CANCELLED", "CANCELLED"], "a accepted, the queued ones cancelled")


# --- remote text bounds, reconnects, keys ----------------------------------------------


## A reconnect that brings another terminal into the same pane id (a herdr
## restart) stops input: nothing typed goes to the new terminal until Follow.
## A pane gone after the reconnect stops it with no Follow.
func test_a_reconnect_with_another_terminal_stops_input() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.OFFLINE, "offline")
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), PANE, {"terminal_id": "term-after-restart"})})
	_ctl("control-b", "appear")
	await _until(func() -> bool: return office.fleet.snapshot_is_current(BEE), "back and current")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.STOPPED, "input stopped")
	await _frames(5)
	_eq(monitor.mode(), TerminalMonitor.Mode.STOPPED, "still stopped")
	var follow: Button = monitor.get_node("%FollowButton")
	_check(follow.is_visible_in_tree(), "Follow is offered")
	await _press_key(KEY_X, 0x78)
	await _press_key(KEY_ENTER)
	await _wait(0.6)
	_eq(_all_inputs(), 0, "nothing reached the new terminal")
	monitor.close_monitor()
	# The pane gone after a reconnect. The staff panel is its one line: Monitor is on it.
	var button: Button = office.hud.inspector.get_node("%CompactMonitor")
	await _click_control(button)
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live on the new terminal")
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.OFFLINE, "offline again")
	_ctl("control-b", "set_snapshot", {"snapshot": _without(_raw(), PANE)})
	_ctl("control-b", "appear")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.STOPPED, "stopped: the pane is gone")
	_check(not follow.is_visible_in_tree(), "no Follow for a closed pane")
	_eq(_all_inputs(), 0, "and nothing sent")


## On a Mac, Option types the character the layout makes (as Terminal.app and
## iTerm2 do by default); `alt+` goes only when no character comes. Elsewhere
## Alt stays `alt+`. German Option+L is @, Option+7 is |; French
## Option+Shift+L is |; US Option+E is a dead key with no character.
func test_option_types_characters_on_a_mac() -> void:
	var events: Array[Array] = [
		[KEY_L, 0x40, KEY_MASK_ALT, "text @", "keys alt+l"],
		[KEY_7, 0x7C, KEY_MASK_ALT, "text |", "keys alt+7"],
		[KEY_5, 0x5B, KEY_MASK_ALT, "text [", "keys alt+5"],
		[KEY_L, 0x7C, KEY_MASK_ALT | KEY_MASK_SHIFT, "text |", "keys alt+shift+l"],
		[KEY_F, 0x192, KEY_MASK_ALT, "text ƒ", "keys alt+f"],
		[KEY_E, 0, KEY_MASK_ALT, "none", "keys alt+e"],
		[KEY_X, 0, KEY_MASK_ALT, "none", "keys alt+x"],
	]
	for row: Array in events:
		var code: int = row[0]
		var typed: int = row[1]
		var mask: int = row[2]
		var event := _event(code, typed, mask, true)
		_eq(_mapped(TerminalKeys.of(event, true)), row[3], "Option on a Mac: %s" % row[3])
		_eq(_mapped(TerminalKeys.of(event, false)), row[4], "Alt elsewhere: %s" % row[4])
	# Through the monitor, by real input, as this system maps it.
	var office := await _live()
	_check(office.hud.monitor_open(), "open")
	await _press_key(KEY_L, 0x40, KEY_MASK_ALT)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "sent")
	var wanted := "text @" if OS.get_name() == "macOS" else "keys alt+l"
	_eq(_inputs("control-b").map(_described), [wanted], "German Option+L on this system")


## A declared grid past 400 x 200 cells is drawn as 400 x 200 at most, and the
## status says so: a hostile layout rect cannot stall every read.
func test_a_huge_grid_is_clamped() -> void:
	_fakes()
	var raw := _raw()
	for layout: Dictionary in _list(raw, "layouts"):
		for slot: Dictionary in _list(layout, "panes"):
			if slot.get("pane_id") == PANE:
				slot["rect"] = {"x": 80, "y": 0, "width": 4096, "height": 4096}
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "visible", "ansi": "big\r\n", "animate": true})
	var office := await _open_live()
	var grid := office.hud.monitor.grid_node()
	_eq([grid.screen.columns, grid.screen.rows], [TerminalMonitor.GRID_MAX.x, TerminalMonitor.GRID_MAX.y], "clamped")
	_check(office.hud.monitor.grid_note().contains("4096×4096"), "said: " + office.hud.monitor.grid_note())
	await _wait(1.0)
	var slowest := 0
	for usec in grid.draw_usec:
		slowest = maxi(slowest, usec)
	_check(slowest < FRAME_BUDGET_MSEC * 1000, "every draw in budget: %d us" % slowest)


## One screen read at a time, also across a reopen and a Follow: a read still
## out keeps the next from starting.
func test_one_read_at_a_time_across_reopen_and_follow() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	var button: Button = office.hud.inspector.get_node("%CompactMonitor")
	_ctl("control-b", "next", {"action": "hold", "method": "pane.read"})
	await _until(func() -> bool: return _number(_ctl("control-b", "stats"), "held_replies") == 1, "a read is held")
	monitor.close_monitor()
	await _click_control(button)
	var before := _screen_reads()
	await _wait(0.8)
	_eq(_screen_reads(), before, "no second read while one is out, after a reopen")
	_ctl("control-b", "release_held")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live")
	# Follow.
	_ctl("control-b", "next", {"action": "hold", "method": "pane.read"})
	await _until(
		func() -> bool: return _number(_ctl("control-b", "stats"), "held_replies") == 1, "a read is held again"
	)
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), PANE, {"terminal_id": "term-followed"})})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.STOPPED, "stopped")
	var follow: Button = monitor.get_node("%FollowButton")
	await _click_control(follow)
	before = _screen_reads()
	await _wait(0.8)
	_eq(_screen_reads(), before, "no second read while one is out, after Follow")
	_ctl("control-b", "release_held")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live on the followed terminal")


## Only a screen on view is a look (the write-then-look rule): reads while
## the view shows scrollback, and the scrollback read itself, never are.
func test_only_a_screen_on_view_counts_as_a_look() -> void:
	var office := await _live()
	var monitor := office.hud.monitor
	var key := monitor.pane_key()
	var history := PackedStringArray()
	for index in 100:
		history.append("line %d" % index)
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "recent", "ansi": "\r\n".join(history)})
	await _press_key(KEY_A, 0x61)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "a went")
	await _wheel(monitor.grid_node(), MOUSE_BUTTON_WHEEL_UP)
	_check(monitor.scrolled_back(), "scrolled back")
	await _wait(1.2)
	_check(office.fleet.must_look(key), "no look while the live screen is not on view")
	while monitor.scrolled_back():
		await _wheel(monitor.grid_node(), MOUSE_BUTTON_WHEEL_DOWN)
	await _until(func() -> bool: return not office.fleet.must_look(key), "a read shown on the live screen is the look")


## A read of the old connection that lands after the monitor re-aimed is not
## shown and does not open input: only a read of the new one does.
func test_a_late_read_of_the_old_connection_is_dropped() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var holder := Control.new()
	holder.theme = HudTheme.build(art, OfficeDraw.new(art).font)
	holder.size = Vector2(800, 480)
	root.add_child(holder)
	var monitor: TerminalMonitor = MONITOR_SCENE.instantiate()
	holder.add_child(monitor)
	var fleet := ScriptedFleet.new()
	holder.add_child(fleet)
	monitor.connect_fleet(fleet, Callable())
	monitor.open_monitor(fleet.context_for("p", 0))
	await _until(func() -> bool: return fleet.reads.size() == 1, "the first read")
	fleet.answer(0, "first screen")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live")
	await _until(func() -> bool: return fleet.reads.size() == 2, "a second read, left out")
	fleet.scripted_generation = 2
	monitor.show_pane(null, "", false)
	_eq(monitor.mode(), TerminalMonitor.Mode.ARMING, "re-aimed at the new connection, waiting for its screen")
	fleet.answer(1, "old connection")
	await _frames(3)
	_check(monitor.grid_node().screen.row_text(0) != "old connection", "the late read is not shown")
	_eq(monitor.mode(), TerminalMonitor.Mode.ARMING, "and input stays closed")
	await _until(func() -> bool: return fleet.reads.size() == 3, "a read of the new connection")
	fleet.answer(2, "new screen")
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live on the new connection")
	_eq(monitor.grid_node().screen.row_text(0), "new screen", "its screen")
	holder.free()


## Ctrl+] closes the monitor by key position, whatever the layout makes of it
## (on a German Mac `]` needs Option): the key at the US `]` position does.
func test_ctrl_bracket_closes_by_position_on_any_layout() -> void:
	var office := await _live()
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_PLUS
		event.physical_keycode = KEY_BRACKETRIGHT
		event.unicode = 0
		event.ctrl_pressed = true
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await _frames(2)
	_check(not office.hud.monitor_open(), "closed")
	_eq(_all_inputs(), 0, "nothing sent")


## A long grapheme cluster is remote input (invariant 9): 300 combining marks,
## a 250-long ZWJ family and a 120-column row of ZWJ-joined hearts each shaped
## as one cluster, and the engine takes seconds to minutes to shape one
## (measured). Entry cleaning and the grid cap every cluster at
## TerminalText.CLUSTER_MAX code points, drawn as its base: each draws in a frame.
func test_long_clusters_are_capped_on_the_grid() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var holder := Control.new()
	holder.theme = HudTheme.build(art, OfficeDraw.new(art).font)
	holder.size = Vector2(700, 440)
	root.add_child(holder)
	var grid := TerminalMonitorGrid.new()
	grid.theme_type_variation = &"MonitorGrid"
	grid.size = holder.size
	holder.add_child(grid)
	grid.set_grid(120, 40)
	var probes := _cluster_probes()
	# The SGR-separated row the entry cleaning cannot see as one cluster: the
	# parser strips SGR and would join it again.
	var coloured := PackedStringArray()
	for index in 120:
		coloured.append("\u001b[3%dm❤\ufe0f\u200d" % (index % 8))
	probes["coloured hearts"] = "".join(coloured)
	for name: String in probes:
		var wire := {"read": {"pane_id": "p", "source": "visible", "format": "ansi", "text": probes[name]}}
		var read := ScreenReadResult.from_wire(wire, "p")
		var started := Time.get_ticks_msec()
		grid.show_text(read.text)
		await _frames(2)
		var took := Time.get_ticks_msec() - started
		_check(took < FRAME_BUDGET_MSEC, "%s: parsed and drawn in %d ms" % [name, took])
		var longest := 0
		for glyph in grid.screen.glyphs[0]:
			longest = maxi(longest, glyph.length())
		_check(longest <= TerminalText.CLUSTER_MAX, "%s: no cell holds more than the cap: %d" % [name, longest])
	_eq(grid.screen.glyphs[0][0], "❤", "a capped cluster draws as its base")
	holder.free()


## The card's preview takes the same bound, through PaneReadResult.
func test_long_clusters_are_capped_in_the_card_preview() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var holder := Control.new()
	holder.theme = HudTheme.build(art, OfficeDraw.new(art).font)
	root.add_child(holder)
	var label := Label.new()
	label.theme_type_variation = &"PreviewText"
	holder.add_child(label)
	var probes := _cluster_probes()
	for name: String in probes:
		var read := PaneReadResult.from_wire({"read": {"pane_id": "p", "text": probes[name]}}, "p")
		var started := Time.get_ticks_msec()
		label.text = read.text
		label.get_minimum_size()
		await _frames(2)
		var took := Time.get_ticks_msec() - started
		_check(took < FRAME_BUDGET_MSEC, "%s: shaped and drawn in %d ms" % [name, took])
		_check(
			read.text.length() <= 4 * TerminalText.CLUSTER_MAX, "%s: cut to its base: %d" % [name, read.text.length()]
		)
	holder.free()


## A paste is refused whole when it holds what a terminal would act on or what
## would reorder what the viewer sees: C0 but tab, newline and carriage return,
## DEL, and the direction controls. Tabs, newlines and emoji joiners pass.
func test_a_paste_refuses_controls_and_direction_marks() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var target := _aim(facts, "alpha:p2")
	var refused: Dictionary[String, CommandRefusal.Reason] = {
		"stop \u0003 now": CommandRefusal.Reason.PASTE_CONTROL,
		"kill line \u0015": CommandRefusal.Reason.PASTE_CONTROL,
		"suspend \u001a": CommandRefusal.Reason.PASTE_CONTROL,
		"bell \u0007": CommandRefusal.Reason.PASTE_CONTROL,
		"del \u007f": CommandRefusal.Reason.PASTE_CONTROL,
		"line\u2028sep": CommandRefusal.Reason.PASTE_CONTROL,
		"rm -rf \u202e/ tpm\u202c": CommandRefusal.Reason.PASTE_INVISIBLE,
		"isolate \u2066x\u2069": CommandRefusal.Reason.PASTE_INVISIBLE,
		"mark \u200f": CommandRefusal.Reason.PASTE_INVISIBLE,
	}
	for pasted: String in refused:
		_eq(HerdrCommands.paste_refusal(pasted), refused[pasted], "refused: " + pasted.c_escape())
	var passing: Array[String] = ["a\tb\nc\r\nd", "👨\u200d👩\u200d👧 family", "中文 ✓"]
	for pasted in passing:
		_eq(HerdrCommands.paste_refusal(pasted), CommandRefusal.Reason.NONE, "pasted: " + pasted.c_escape())
	var commands := _boundary()
	var ticket := commands.submit(target.pasting("stop \u0003"), facts, _facts_now(facts))
	_eq(ticket.state, CommandTicket.State.REFUSED, "refused at the send port")
	await _frames(2)
	_eq(_all_inputs(), 0, "nothing reached herdr")
	commands.free()


## Input queued for the pane's new terminal behind input for its old one is not
## refused with the old one's reason: the old one's is refused, the new one's goes.
func test_input_for_a_new_terminal_is_not_refused_for_the_old_one() -> void:
	_fakes()
	var facts := _facts(args["socket-a"], _raw())
	var old := _aim(facts, "alpha:p2")
	var holder: Array[HerdrCommands.Machine] = [facts]
	var known := func() -> HerdrCommands.Machine: return holder[0]
	var commands := _boundary()
	_ctl("control-a", "next", {"action": "hold", "method": "pane.send_text"})
	var first := commands.submit(old.typing_text("a"), facts, known)
	var deadline := Time.get_ticks_msec() + 1500
	while first.state == CommandTicket.State.UNSENT and Time.get_ticks_msec() < deadline:
		commands.pump(0.0)
		OS.delay_usec(1000)
	var stale := commands.submit(old.typing_text("b"), facts, known)
	var moved := _facts(args["socket-a"], _changed(_raw(), "alpha:p2", {"terminal_id": "term-alpha-2-new"}))
	holder[0] = moved
	var fresh := commands.submit(_aim(moved, "alpha:p2").typing_text("c"), moved, known)
	_eq(fresh.state, CommandTicket.State.UNSENT, "c waits behind b")
	_ctl("control-a", "release_held")
	_settle(commands, fresh, "c")
	_eq(
		[stale.state, stale.refusal, fresh.state],
		[CommandTicket.State.REFUSED, CommandRefusal.Reason.IDENTITY_CHANGED, CommandTicket.State.ACCEPTED],
		"b refused for the old terminal, c sent to the new one"
	)
	_eq(_inputs("control-a").map(func(r: Dictionary) -> Variant: return r.get("text")), ["a", "c"], "a and c")
	commands.free()


## A double-click on a pane's row in the agent list opens the monitor on that
## pane, by real input: the list's way in (HB's `monitor_requested`).
func test_a_double_click_in_the_list_opens_the_monitor() -> void:
	_fakes()
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "visible", "ansi": "$ from the list\r\n"})
	var office := await _office_with()
	var key := HerdrFleet.pane_key(BEE, PANE)
	var list := office.hud.agent_list
	# Every run starts with the drawer closed: a real click on its tab opens it.
	var tab: Control = office.hud.get_node("%DrawerTab")
	await _click_control(tab)
	await _until(office.hud.drawer_open, "the drawer is open")
	await _until(func() -> bool: return list.row_for(key) != null, "the list has the pane")
	var entry := list.entry_for(key)
	if entry != null and not entry.parent.is_empty():
		list.set_collapsed(entry.parent, false)
	var row := list.row_for(key)
	var scroll: ScrollContainer = list.get_node("%Scroll")
	scroll.ensure_control_visible(row)
	await _frames(2)
	var at := row.get_global_rect().get_center()
	for press: Array in [[true, false], [false, false], [true, true], [false, false]]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = press[0]
		event.double_click = press[1]
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame
	await _until(office.hud.monitor_open, "the monitor is open")
	_eq(office.hud.monitor.pane_key(), key, "on that pane")
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.grid_node().screen.row_text(0) == "$ from the list", "its screen")
	_eq(monitor.mode(), TerminalMonitor.Mode.LIVE, "live")


## At the 480x320 minimum the staff panel is one compact line, which says
## Monitor as `⤢` and has no room for the full panel's "Monitor ⤢" chip;
## Enter opens the panel up, and there the chip is on screen, inside the panel.
## The open monitor covers the whole screen, the right column and the staff
## panel included, and gives them back on close.
func test_the_monitor_chip_fits_the_opened_panel_and_the_monitor_covers_the_column_and_the_panel() -> void:
	_fakes()
	var office := await _office_with(false, true, true, Vector2(480, 320))
	await _pick_bee(office, PANE, false)
	var card := office.hud.inspector
	var chip: Button = card.get_node("%MonitorButton")
	var line_chip: Button = card.get_node("%CompactMonitor")
	_check(office.hud.card_compact(), "the card is a compact line at 480x320")
	_check(not chip.is_visible_in_tree(), "with no room for the full panel's chip")
	_check(line_chip.is_visible_in_tree() and line_chip.text == "⤢", "the line has its own, short")
	_check(card.get_global_rect().encloses(line_chip.get_global_rect()), "inside the line")
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return not office.hud.card_compact(), "Enter opens the panel up")
	await _until(chip.is_visible_in_tree, "the chip is offered")
	var screen := Rect2(Vector2.ZERO, Vector2(480, 320))
	_check(
		card.get_global_rect().encloses(chip.get_global_rect()),
		"the chip is inside the card: %s" % chip.get_global_rect()
	)
	_check(screen.encloses(chip.get_global_rect()), "and on screen")
	await _click_control(chip)
	await _until(office.hud.monitor_open, "open")
	var monitor := office.hud.monitor
	_check(monitor.get_global_rect().encloses(office.hud.right_column.get_global_rect()), "it covers the right column")
	_check(monitor.get_global_rect().encloses(card.get_global_rect()), "and the staff panel")
	_check(monitor.get_global_rect().encloses(screen), "and the whole screen")
	await _press_key(KEY_BRACKETRIGHT, 0, KEY_MASK_CTRL)
	_check(not monitor.visible, "closed")
	_check(office.hud.right_column.is_visible_in_tree(), "the column is back")
	_check(card.is_visible_in_tree(), "and the panel")
	await _frames(3)
	_check(chip.is_visible_in_tree(), "and the chip with it")


## `M` opens the monitor on the pane the staff panel shows, as its
## Monitor button does, and types nothing into it; while the monitor is open it
## takes every key, `M` included (typed, as `m`); under the OVERVIEW the table
## swallows `M` and nothing opens.
func test_m_opens_the_monitor_on_the_selection_and_types_nothing() -> void:
	_fakes()
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "visible", "ansi": "$ \r\n"})
	var office := await _office_with()
	await _pick_bee(office, PANE, false)
	var key := HerdrFleet.pane_key(BEE, PANE)
	_check(not office.hud.monitor_open(), "no monitor yet")
	await _press_key(KEY_M, 0x6D)
	await _until(office.hud.monitor_open, "M opens the monitor")
	_eq(office.hud.monitor.pane_key(), key, "on the pane the panel shows")
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live")
	await _wait(0.4)
	_eq(_all_inputs(), 0, "the M that opened it typed nothing")
	await _press_key(KEY_M, 0x6D)
	await _until(func() -> bool: return _inputs("control-b").size() == 1, "an M in the monitor is the terminal's")
	_eq(_inputs("control-b").map(_described), ["text m"], "typed as m")
	_check(office.hud.monitor_open(), "and the monitor stays open")
	await _press_key(KEY_BRACKETRIGHT, 0, KEY_MASK_CTRL)
	_check(not office.hud.monitor_open(), "closed")
	await _press_key(KEY_O, 0x6F)
	_check(office.hud.overview_open(), "O opens the overview")
	await _press_key(KEY_M, 0x6D)
	await _frames(3)
	_check(not office.hud.monitor_open(), "under the overview M opens nothing")
	await _press_key(KEY_O, 0x6F)
	_check(not office.hud.overview_open(), "O closes it")
	_eq(_inputs("control-b").size(), 1, "the one m, nothing more")
	_eq(_inputs("control-a").size(), 0, "and nothing to Local")


# --- hostile titles, dead keys, slow draws -------------------------------------------


## Every remote display string is cluster-bounded where it enters: labels,
## titles, agent names and worktree names in HerdrSnapshot.from_wire(), and a
## machine's name in MachineRoster.normalize(). Ids and keys are not touched.
func test_remote_display_strings_are_cluster_bounded() -> void:
	var probe := _title_probe()
	var raw := _raw()
	for workspace: Dictionary in _list(raw, "workspaces"):
		workspace["label"] = probe
		if workspace.get("worktree") is Dictionary:
			var tree: Dictionary = workspace.get("worktree")
			for field: String in ["repo_name", "repo_root", "checkout_path"]:
				tree[field] = probe
	for tab: Dictionary in _list(raw, "tabs"):
		tab["label"] = probe
	for pane: Dictionary in _list(raw, "panes"):
		for field: String in ["label", "terminal_title", "terminal_title_stripped", "cwd", "foreground_cwd"]:
			pane[field] = probe
	var snapshot := HerdrSnapshot.from_wire(raw)
	var shown := PackedStringArray()
	for workspace in snapshot.workspaces:
		shown.append(workspace.label)
		if workspace.worktree != null:
			shown.append_array([workspace.worktree.repo_name, workspace.worktree.repo_root])
			shown.append(workspace.worktree.checkout_path)
	for tab in snapshot.tabs:
		shown.append(tab.label)
	for pane in snapshot.panes:
		shown.append_array([pane.label, pane.terminal_title_stripped, pane.cwd, pane.foreground_cwd])
	_eq(snapshot.workspaces[0].workspace_id, "alpha", "a workspace id is untouched")
	_eq(snapshot.panes[0].pane_id, "alpha:p1", "and a pane id")
	for text in shown:
		_check(text.length() <= TerminalText.CLUSTER_MAX, "bounded: %d code points" % text.length())
	var named := {"label": probe, "ssh_target": "me@far", "profile_id": "far"}
	var machine := MachineRoster.normalize(named)
	_check(machine.label.length() <= TerminalText.CLUSTER_MAX, "a machine's name: %d" % machine.label.length())
	_eq([machine.key, machine.target], ["machine:far", "me@far"], "its id and target untouched")
	var agent := _changed(_raw(), PANE, {"agent": "claude" + "\u0301".repeat(300)})
	var joined := HerdrSnapshot.from_wire(agent)
	for pane in joined.panes:
		_check(pane.agent.length() <= 16, "an agent name: %d" % pane.agent.length())


## On a Mac an Option dead key (Option+U, which makes no character) sends
## nothing; the composed character that follows goes as text. Elsewhere Alt+U
## is `alt+u`.
func test_an_option_dead_key_sends_nothing_then_the_character() -> void:
	var dead := _event(KEY_U, 0, KEY_MASK_ALT, true)
	var composed := _event(KEY_U, 0xFC, 0, true)
	_eq(_mapped(TerminalKeys.of(dead, true)), "none", "a Mac dead key sends nothing")
	_eq(_mapped(TerminalKeys.of(composed, true)), "text ü", "the composed character is text")
	_eq(_mapped(TerminalKeys.of(dead, false)), "keys alt+u", "Alt+U elsewhere")
	var office := await _live()
	_check(office.hud.monitor_open(), "open")
	await _press_key(KEY_U, 0, KEY_MASK_ALT)
	await _press_key(KEY_U, 0xFC)
	await _until(func() -> bool: return not _inputs("control-b").is_empty(), "something went")
	await _wait(0.3)
	var wanted := ["text ü"] if OS.get_name() == "macOS" else ["keys alt+u", "text ü"]
	_eq(_inputs("control-b").map(_described), wanted, "the dead key, then the character")


## Polling backs off behind a slow draw: the next read waits at least four
## times what the last parse and draw cost, so a screen that is expensive to
## draw cannot keep the main thread busy.
func test_polling_backs_off_behind_a_slow_draw() -> void:
	var art := ArtPack.from_manifest(MANIFEST)
	var holder := Control.new()
	holder.theme = HudTheme.build(art, OfficeDraw.new(art).font)
	holder.size = Vector2(800, 480)
	root.add_child(holder)
	var monitor: TerminalMonitor = MONITOR_SCENE.instantiate()
	holder.add_child(monitor)
	var fleet := ScriptedFleet.new()
	holder.add_child(fleet)
	monitor.connect_fleet(fleet, Callable())
	monitor.open_monitor(fleet.context_for("p", 0))
	var grid := monitor.grid_node()
	grid.draw_delay_usec = 150000
	var answered := 0
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until:
		while answered < fleet.reads.size():
			fleet.answer(answered, "screen %d" % answered)
			answered += 1
		await process_frame
	var cost := grid.last_cost_usec()
	_check(cost >= 150000, "the last draw cost what it was told to: %d us" % cost)
	_check(
		monitor.next_read_delay() >= 4.0 * cost / 1000000.0,
		"the next read waits 4x that: %.2f s" % monitor.next_read_delay()
	)
	_check(fleet.reads.size() <= 5, "reads in 3 s behind a 150 ms draw: %d" % fleet.reads.size())
	_check(fleet.reads.size() >= 2, "and it still reads")
	grid.draw_delay_usec = 0
	holder.free()


## The title probe (a letter and 300 combining marks) as a pane's
## terminal title, its workspace, tab and pane labels: the office draws the
## card, the agent list with its history rows, and the building section, and
## no frame takes longer than the budget. Unbounded, the first frame hangs.
func test_a_hostile_title_draws_in_the_card_list_and_section() -> void:
	_fakes()
	var probe := _title_probe()
	var raw := _changed(_raw(), PANE, {"agent_status": "blocked", "label": null, "terminal_title_stripped": probe})
	raw = _changed(raw, PANE, {"terminal_title": probe})
	for workspace: Dictionary in _list(raw, "workspaces"):
		workspace["label"] = probe
	for tab: Dictionary in _list(raw, "tabs"):
		tab["label"] = probe
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	var office := await _office_with(true)
	_check(await _longest_frame(1.0) < FRAME_BUDGET_MSEC, "the office with the section and the list")
	await _pick_bee(office, PANE)
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, PANE), "picked: the card shows it")
	_check(await _longest_frame(1.0) < FRAME_BUDGET_MSEC, "the card")
	var list := office.hud.agent_list
	var tab: Control = office.hud.get_node("%DrawerTab")
	await _click_control(tab)
	await _until(office.hud.drawer_open, "the drawer's tab opens the list")
	# History reads the StateLog: the pane has a line once it stops waiting.
	_ctl("control-b", "status", {"pane_id": PANE, "agent_status": "idle"})
	await _until(func() -> bool: return list.group_for(AgentListModel.FLAT_HISTORY) != null, "a History line")
	var group := list.group_for(AgentListModel.FLAT_HISTORY)
	_check(group != null, "the list has its history")
	if group != null:
		var scroll: ScrollContainer = list.get_node("%Scroll")
		scroll.ensure_control_visible(group)
		await _frames(2)
		await _click_control(group)
		await _until(func() -> bool: return not list.collapsed(AgentListModel.FLAT_HISTORY), "history open")
	_check(await _longest_frame(1.0) < FRAME_BUDGET_MSEC, "the history rows")
	var titled := office.frame.pane(HerdrFleet.pane_key(BEE, PANE))
	_check(titled != null and titled.terminal_title.length() <= TerminalText.CLUSTER_MAX, "the title is bounded")


static func _title_probe() -> String:
	return "a" + "\u0301".repeat(300)


## The longest frame, in milliseconds, over `seconds` of real frames.
func _longest_frame(seconds: float) -> float:
	var longest := 0.0
	var last := Time.get_ticks_usec()
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await process_frame
		var now := Time.get_ticks_usec()
		longest = maxf(longest, (now - last) / 1000.0)
		last = now
	return longest


## The three long-cluster probes.
static func _cluster_probes() -> Dictionary[String, String]:
	var hearts := PackedStringArray()
	for _index in 120:
		hearts.append("❤\ufe0f\u200d")
	var family := PackedStringArray()
	for _index in 250:
		family.append("👨\u200d")
	return {
		"300 combining marks": "a" + "\u0301".repeat(300),
		"250-long ZWJ family": "".join(family),
		"120 joined hearts": "".join(hearts),
	}


static func _mapped(mapped: TerminalKeys) -> String:
	match mapped.kind:
		TerminalKeys.Kind.KEY:
			return "keys " + mapped.name
		TerminalKeys.Kind.TEXT:
			return "text " + mapped.text
		TerminalKeys.Kind.REFUSED:
			return "refused " + CommandRefusal.name_of(mapped.reason)
	return "none"


## A fleet that answers the monitor from a script: one machine, one pane,
## reads held until answer(), and a generation the case moves.
class ScriptedFleet:
	extends HerdrFleet

	var scripted_generation := 1
	var reads: Array[CommandTicket] = []

	func read_only() -> bool:
		return false

	func pane_size(_key: String) -> Vector2i:
		return Vector2i(40, 10)

	func snapshot_is_current(_key: String) -> bool:
		return true

	func context_for(key: String, binding: int) -> CommandContext:
		return CommandContext.aimed("local", scripted_generation, key, "p", "p", "id", binding, "term")

	func input_refusal(target: CommandContext) -> CommandRefusal.Reason:
		if target.generation != scripted_generation:
			return CommandRefusal.Reason.MACHINE_REPLACED
		return CommandRefusal.Reason.NONE

	func screen_refusal(target: CommandContext) -> CommandRefusal.Reason:
		return input_refusal(target)

	func can_operate(_key: String, _kind := CommandContext.Kind.FOCUS) -> CommandRefusal.Reason:
		return CommandRefusal.Reason.NONE

	func read_screen(context: CommandContext) -> CommandTicket:
		var ticket := CommandTicket.new(context)
		reads.append(ticket)
		return ticket

	func preview_shown(_ticket: CommandTicket) -> void:
		pass

	func drop_input(_key: String) -> void:
		pass

	func answer(index: int, text: String) -> void:
		var screen := ScreenReadResult.new()
		screen.text = text
		reads[index].screen = screen
		reads[index].settle(CommandTicket.State.ACCEPTED)


# --- helpers ---------------------------------------------------------------------------


static func _dump(name: String, extension: String) -> String:
	return FileAccess.get_file_as_string("res://tools/fixtures/monitor/%s.%s" % [name, extension])


## Fakes that allow the monitor, `screen` scripted on bee's PANE, an operator
## office, and the monitor open on PANE by real clicks, live.
func _live(screen := "$ \r\n") -> OfficeDouble:
	_fakes()
	_ctl("control-b", "set_screen", {"pane_id": PANE, "source": "visible", "ansi": screen})
	return await _open_live()


func _open_live() -> OfficeDouble:
	var office := await _office_with()
	# The staff panel's one line keeps Monitor: no need to open the panel.
	await _pick_bee(office, PANE, false)
	var button: Button = office.hud.inspector.get_node("%CompactMonitor")
	await _until(button.is_visible_in_tree, "the card offers the monitor")
	await _click_control(button)
	await _until(office.hud.monitor_open, "the monitor is open")
	var monitor := office.hud.monitor
	await _until(func() -> bool: return monitor.mode() == TerminalMonitor.Mode.LIVE, "live input")
	return office


## One key pressed and released, as a keyboard sends it: `code` the layout's
## key, `typed` the character it makes (0: none), `mask` the modifiers held.
func _press_key(code: int, typed := 0, mask := 0) -> void:
	for down: bool in [true, false]:
		Input.parse_input_event(_event(code, typed, mask, down))
		Input.flush_buffered_events()
		await process_frame
	await process_frame


## Several key presses within one frame.
func _burst(keys: Array) -> void:
	for key: Array in keys:
		var code: int = key[0]
		var typed: int = key[1]
		var mask: int = key[2]
		Input.parse_input_event(_event(code, typed, mask, true))
	Input.flush_buffered_events()


static func _event(code: int, typed: int, mask: int, down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code as Key
	event.physical_keycode = code as Key
	event.unicode = typed
	event.pressed = down
	event.ctrl_pressed = mask & KEY_MASK_CTRL != 0
	event.shift_pressed = mask & KEY_MASK_SHIFT != 0
	event.alt_pressed = mask & KEY_MASK_ALT != 0
	event.meta_pressed = mask & KEY_MASK_META != 0
	return event


## One wheel notch over `control`, through the viewport's GUI.
func _wheel(control: Control, button: MouseButton) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await process_frame


## The monitor's screen reads (`ansi`) bee heard in `seconds` of real time.
func _reads_over(seconds: float) -> int:
	var before := _screen_reads()
	await _wait(seconds)
	return _screen_reads() - before


func _screen_reads() -> int:
	return _asked("control-b", "pane.read").filter(func(p: Dictionary) -> bool: return p.get("format") == "ansi").size()


## A fake's input record in a few words: `keys a,b`, `text …`, `paste …`.
static func _described(record: Dictionary) -> String:
	match str(record.get("method")):
		"pane.send_keys":
			var keys: Array = record.get("keys") if record.get("keys") is Array else []
			return "keys " + ",".join(PackedStringArray(keys))
		"pane.send_text":
			return "text " + str(record.get("text"))
	return "paste " + str(record.get("text"))


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: nothing reached them that no case opened.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: no violations" % which)
