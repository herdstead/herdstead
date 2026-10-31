extends "res://tools/office_test_base.gd"
## What every surface calls a pane (DisplayName): the name chain as a table,
## a workspace's lone default tab left unsaid, the cluster-safe cut, and the
## live office's plate, seat tooltip, pod label and card saying it. Clicks,
## hovers and keys go through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_names.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## The suite's fixture, tools/fixtures/snapshot_names.json: `solo` (1) has one
## tab herdr still calls `1`; `pair` (2) two, `1` and `2`; `named` (3) one
## called `main`. solo:p1 is a blocked claude titled `✳ Add retry to fetch`,
## solo:p2 a claude titled `Claude Code`, solo:p3 a shell titled `zsh`, both in
## /home/tester/fetcher; pair:p1 a codex titled `codex` with the pane label
## `reviewer`; pair:p2 a codex titled `⠋ Review the diff`; named:p1 a pi titled `pi`.
const FIXTURE := "res://tools/fixtures/snapshot_names.json"


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("names-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_names.json")
		quit(2)
		return
	var file: Dictionary = parsed
	fixture = _dict(file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "NAMES TESTS"


# --- the rule -------------------------------------------------------------------


## The chain, first that says something wins: the title (unless it is only a
## provider word, `<provider> code`, the agent's name, a shell's name or a
## spinner); the pane's label; its tab's label unless herdr's default; the
## directory's last component; herdr's agent name; `pane <id>`. Never the
## provider word alone, but a directory may be called anything.
func test_the_name_chain() -> void:
	# [title, pane label, tab label, tab number, tab id, cwd, agent name, pane id, provider] -> name
	var table: Array[Array] = [
		[["Add retry to fetch", "", "main", 1, "w:t1", "/home/a", "", "w:p1", "claude"], "Add retry to fetch"],
		[["✳ Add retry to fetch", "", "main", 1, "w:t1", "/home/a", "", "w:p1", "claude"], "Add retry to fetch"],
		[["  ⠂ ✻ fix the flake  ", "", "", 1, "w:t1", "", "", "w:p1", "claude"], "fix the flake"],
		[["codex", "", "main", 1, "w:t1", "/home/a", "", "w:p1", "codex"], "main"],
		[["Claude Code", "", "main", 1, "w:t1", "/home/a", "", "w:p1", "claude"], "main"],
		[["zsh", "", "", 1, "w:t1", "/home/notes/", "", "w:p1", ""], "notes"],
		[["-zsh", "", "", 1, "w:t1", "/home/notes", "", "w:p1", ""], "notes"],
		[["⠂ ", "", "", 1, "w:t1", "/home/notes", "", "w:p1", ""], "notes"],
		[["claude-2", "", "", 1, "w:t1", "", "claude-2", "w:p1", ""], "claude-2"],
		[["codex", "reviewer", "main", 1, "w:t1", "/home/a", "", "w:p1", "codex"], "reviewer"],
		[["", "", "2", 2, "w:t2", "/srv/api", "", "w:p1", "pi"], "api"],
		[["", "", "w:t3", 3, "w:t3", "/srv/api", "", "w:p1", "pi"], "api"],
		[["", "", "", 1, "w:t1", "", "pi-3", "w:p1", "pi"], "pi-3"],
		[["", "", "", 1, "w:t1", "/", "", "w:p9", "pi"], "pane w:p9"],
		# The provider word alone is no name, wherever it comes from…
		[["", "claude", "", 1, "w:t1", "", "claude", "w:p1", "claude"], "pane w:p1"],
		# …but a directory is called what it is called.
		[["", "", "", 1, "w:t1", "/home/claude", "", "w:p1", "claude"], "claude"],
	]
	for row in table:
		var given: Array = row[0]
		var number: int = given[3]
		var tab_name := DisplayName.tab_named(str(given[2]), number, str(given[4]))
		var said := DisplayName.of(
			str(given[0]), str(given[1]), tab_name, str(given[5]), str(given[6]), str(given[7]), str(given[8])
		)
		_eq(said, str(row[1]), "%s is called" % [given])
	_check(DisplayName.generic("Codex Code", "codex", ""), "`<provider> code` says nothing")
	_check(not DisplayName.generic("codex review", "codex", ""), "a provider word in a task is a task")
	var long := "x".repeat(DisplayName.MAX_CLUSTERS + 20)
	var cut := DisplayName.of(long, "", "", "", "", "w:p1", "claude")
	_eq(cut.length(), DisplayName.MAX_CLUSTERS, "a name keeps MAX_CLUSTERS clusters")
	_check(cut.ends_with("…"), "and says it was cut")


## A place says the workspace, and the tab when there is one to tell apart:
## the lone tab of a workspace herdr still calls by its number (or by its id,
## its label when it sent none) is not said; two numeric tabs are; a named one is.
func test_a_lone_default_tab_is_not_said() -> void:
	var snapshot := HerdrSnapshot.from_wire(fixture.duplicate(true))
	var places := {}
	for pane in OfficeProjection.panes_of(snapshot, PackedStringArray(["working", "blocked", "done", "idle"])):
		places[pane.pane_id] = pane.place()
	_eq(places["solo:p1"], "solo", "one tab called `1`: only the workspace")
	_eq(places["pair:p1"], "pair / 1", "the first of two numeric tabs is said")
	_eq(places["pair:p2"], "pair / 2", "and the second")
	_eq(places["named:p1"], "named / main", "a named tab is said")
	_eq(DisplayName.tab_shown("solo:t1", 1, "solo:t1", 1), "", "a label that is the tab id is herdr's default")
	_eq(DisplayName.tab_shown("", 1, "solo:t1", 1), "", "and so is none")
	_eq(DisplayName.tab_shown("1", 1, "solo:t1", 2), "1", "with two tabs, even a number tells them apart")
	var nowhere := PaneModel.new()
	_eq(nowhere.place(), "?", "a pane whose workspace the snapshot lacks")
	# The projection's rooms say the same on the floor.
	for zone in OfficeProjection.project(snapshot, PackedStringArray(["working", "blocked", "done", "idle"])):
		for room in zone.rooms:
			var lone := zone.key.ends_with("solo")
			_eq(room.label_shown, "" if lone else room.label, "the room of %s says" % room.tab_id)


## TerminalText.clip() keeps whole grapheme clusters: never half a CJK glyph,
## an accent or a ZWJ family, and the ellipsis is one of the clusters it keeps.
func test_a_name_is_cut_by_whole_clusters() -> void:
	_eq(TerminalText.clip("abcdef", 6), "abcdef", "exactly at the cap: as it is")
	_eq(TerminalText.clip("abcdefg", 6), "abcde…", "one over: cut, the ellipsis counted")
	_eq(TerminalText.clip("修复登录重定向", 4), "修复登…", "CJK, whole glyphs")
	var accents := "éééé"
	_eq(TerminalText.clip(accents, 3), "éé…", "an accent stays on its letter")
	var family := "\U01F468‍\U01F469‍\U01F467"
	_eq(TerminalText.clip(family + family + "ab", 3), family + family + "…", "a ZWJ family is one cluster")
	_eq(TerminalText.clip(family + family + family, 3), family + family + family, "three families fit three")
	_eq(TerminalText.clip("word ends here", 6), "word…", "no space left before the ellipsis")
	_eq(TerminalText.clip("", 4), "", "nothing stays nothing")
	_eq(TerminalText.clip("ab", 1), "…", "a cap of one is the ellipsis alone")


# --- the office -------------------------------------------------------------------


## The plate over a seat says the pane's name as it is (not upper case); the
## selected seat's shows it, and under `L` every seat's does, with the same words.
func test_the_plate_says_the_name() -> void:
	var office := await _live_office()
	var names := {
		"solo:p1": "Add retry to fetch",
		"solo:p2": "fetcher",
		"solo:p3": "fetcher",
		"pair:p1": "reviewer",
		"pair:p2": "Review the diff",
		"named:p1": "main",
	}
	for pane_id: String in names:
		var station := _station(office, _pk(pane_id))
		_eq(_plate(station).text, names[pane_id], "the plate of %s" % pane_id)
		_eq(station.name_shown(), names[pane_id], "and what it says it shows")
		_eq(office.frame.pane(_pk(pane_id)).name, names[pane_id], "the model's name for %s" % pane_id)
	var selected := _station(office, _pk("solo:p1"))
	_check(_plate(selected).visible, "herdr's focus is followed: its plate shows")
	_eq(_plate(selected).text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE, "a long name is cut")
	# The native workstation's wider row fits this full name (76 units plus
	# one unit of padding on each side); the tag still hugs, not fills, it.
	_eq(_plate(selected).size, Vector2(78, 10), "the complete name hugs its text inside the wider row")
	_eq(_plate(selected).position, Vector2(-39, 32), "the shorter tag stays centered on its workstation")
	await _parsed(_l_key(true))
	await _frames(2)
	for pane_id: String in names:
		var station := _station(office, _pk(pane_id))
		# Every complete-image actor stays at its desk, including idle.
		_check(_plate(station).visible, "under L the plate of %s shows at its desk" % pane_id)
		_eq(_plate(station).text, names[pane_id], "and says the same name")
	await _parsed(_l_key(false))
	await _frames(2)
	_done(office)


## A new title renames the pane on the next refresh, and that is all it does:
## the same worker stays in the chair, their animation running on, and a
## blocked seat's chip keeps its wait (nothing is furnished again).
func test_a_title_change_renames_without_reseating() -> void:
	var working := _with(fixture, "solo:p1", {"agent_status": "working"})
	var office := await _live_office(working)
	var key := _pk("solo:p1")
	# Seen going blocked, so the chip has a wait to show.
	var blocked := _with(working, "solo:p1", {"agent_status": "blocked"})
	_feed(office, blocked)
	_set_wait(office, "solo:p1", 742.0)
	await _text_tick()
	var station := _station(office, key)
	_eq(_wait_text(office, key), "12m", "the blocked seat shows its wait")
	var worker := _worker(station)
	var before := _actor_state(worker)
	await _frames(6)
	var renamed := _with(blocked, "solo:p1", {"terminal_title_stripped": "✳ Retry with backoff"})
	_feed(office, renamed)
	_eq(_plate(station).text, "Retry with backoff", "the plate follows the new title")
	_eq(office.frame.pane(key).name, "Retry with backoff", "and so does the model")
	_check(_station(office, key) == station, "the same seat")
	_check(_worker(station) == worker, "the same worker in the chair")
	var after := _actor_state(worker)
	_eq(after[1], before[1], "playing the same track")
	var was: float = before[2]
	var now: float = after[2]
	_check(now != 0.0 and now != was, "which ran on: %s then %s" % [was, now])
	_eq(_wait_text(office, key), "12m", "the chip's wait is not blanked")
	_done(office)


## Over a seat, the tooltip says the whole name, who sits there and in what
## state, and where; off the seat it goes; over the blocked seat's chip the
## chip's own tooltip wins, whichever way the pointer came; under `L`, none.
func test_hovering_a_seat_shows_its_whole_name() -> void:
	var long_title := "✳ Add retry to fetch and backoff to every call"
	var office := await _live_office(_with(fixture, "pair:p2", {"terminal_title_stripped": long_title}))
	var key := _pk("pair:p2")
	office.reveal(key)
	await _frames(3)
	var seat := _seat_point(office, key)
	await _pointer_to(seat)
	_check(office.hud.world_tip_shown(), "the tooltip comes up over the seat")
	_eq(
		office.hud.world_tip_text(),
		"Add retry to fetch and backoff to every call\nCODEX · WORKING\npair / 2",
		"the whole name, who and in what state, and where"
	)
	_check(_plate(_station(office, key)).text.length() > 30, "the plate holds the whole name; it draws its start")
	await _pointer_to(Vector2(2, office.hud.world_rect().end.y - 2))
	_check(not office.hud.world_tip_shown(), "off the seat it goes")
	# The blocked seat: its chip's tooltip is the question's, never the name.
	var asking := _pk("solo:p1")
	office.reveal(asking)
	await _frames(3)
	var chip := _station(office, asking).chip_rect().get_center() - office.camera.position
	await _pointer_to(_seat_point(office, asking))
	_check(office.hud.world_tip_text().begins_with("Add retry to fetch\nCLAUDE · "), "over the seat: the name")
	await _pointer_to(chip)
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "seat to chip: the chip's tooltip wins")
	await _pointer_to(_seat_point(office, asking))
	_check(office.hud.world_tip_text().begins_with("Add retry to fetch\n"), "chip to seat: the name again")
	await _pointer_to(chip)
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "and the chip's once more")
	await _pointer_to(Vector2(2, office.hud.world_rect().end.y - 2))
	await _parsed(_l_key(true))
	await _frames(2)
	await _pointer_to(_seat_point(office, asking))
	_check(not office.hud.world_tip_shown(), "under L no tooltip comes up over a seat")
	await _parsed(_l_key(false))
	await _frames(2)
	_done(office)


## The floor under a pod says its tab's label, unless the workspace has that
## tab alone and herdr still calls it by its number.
func test_a_lone_default_tab_has_no_label_under_its_pod() -> void:
	var office := await _live_office()
	var titles := {}
	for zone in office.frame.building_by_key[LOCAL].zones:
		for room in zone.rooms:
			var view: OfficeDeskView = office.floor_view.desks.get(room.key)
			_check(view != null, "the pod of %s is drawn" % room.tab_id)
			if view != null:
				titles[room.tab_id] = view.title.text
	_eq(
		titles,
		{"solo:t1": "", "pair:t1": "1", "pair:t2": "2", "named:t1": "MAIN"},
		"no label for solo's lone `1`; the others as before"
	)
	_done(office)


## The card's title is the pane's name, the seat line who sits there and
## where, and the compact line the name, the state and the place.
func test_the_card_says_the_name_and_the_seat_line_the_kind() -> void:
	var office := await _live_office()
	var card := office.hud.inspector
	_eq(_label(card, "%CardName").text, "Add retry to fetch", "the title is the name")
	_eq(_label(card, "%CardName").tooltip_text, "Add retry to fetch", "and its tooltip the whole of it")
	_eq(_label(card, "%Seat").text, "CLAUDE · solo", "the seat line: the kind, then the place")
	var line := _label(card, "%CompactLine").text
	_check(line.begins_with("Add retry to fetch · "), "the compact line starts with the name: " + line)
	_check(line.ends_with(" · solo"), "and ends with the place: " + line)
	office.reveal(_pk("solo:p3"))
	await _frames(3)
	await _click_at(_seat_point(office, _pk("solo:p3")))
	await _frames(2)
	_eq(_label(card, "%CardName").text, "fetcher", "a shell is called by its directory")
	_eq(_label(card, "%Seat").text, "SHELL · solo", "and its seat line says SHELL")
	office.reveal(_pk("pair:p2"))
	await _frames(3)
	await _click_at(_seat_point(office, _pk("pair:p2")))
	await _frames(2)
	_eq(_label(card, "%Seat").text, "CODEX · pair / 2", "two tabs: the tab is said")
	_done(office)


# --- helpers ----------------------------------------------------------------------


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## The middle of the seat's own click rectangle on screen, the seat revealed.
func _seat_point(office: OfficeDouble, key: String) -> Vector2:
	return _station(office, key).target_rect().get_center() - office.camera.position


func _l_key(down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_L
	event.pressed = down
	return event


## Pane `pane_id` has been in its state for `elapsed` seconds, as its client's
## clock says (tools/test_office_incremental.gd does the same).
func _set_wait(office: OfficeDouble, pane_id: String, elapsed: float) -> void:
	var now := Time.get_unix_time_from_system()
	var clocks := HerdrClient.carry_states({}, _local(office).snapshot.panes, now)
	clocks[pane_id].since = now - elapsed
	_local(office)._states = clocks
