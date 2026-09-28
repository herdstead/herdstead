extends "res://tools/office_test_base.gd"
## The top bar's counters: MACHINES, BLOCKED, DONE, WORKING, IDLE and
## PANES from the live machines only, their hover breakdown by machine and
## space, BLOCKED and DONE walking their agents, WORKING and IDLE filtering the
## agent list, and the longest wait ticking on attention's beat. Hovers and
## clicks go through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_top_bar.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## What tools/fixtures/snapshot_floors.json counts, left to right: Local live;
## blocked web:p1 and infra:p1; UNREAD web:p2 and infra:p2; working api:p1,
## api:p4 and data:p1; idle api:p2 and infra:p3 (data:p2 is idle but still
## launching, so in no count); thirteen panes with the three shells.
const FIXTURE_VALUES: Array[String] = ["1/1", "2", "2", "3", "2", "13"]
## The asset showroom, whose top bar counts a mock of its own.
const SHOWROOM_SCENE := "res://scenes/preview.tscn"


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("top-bar-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var text := FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
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
	return "TOP BAR TESTS"


# --- cases --------------------------------------------------------------------


## Six numbers from the live machine; a dropped one counts nobody and says so
## on MACHINES, in the blocked colour; back again, the same six. The pack's
## line is not the machines' business.
func test_counters_add_up_live_machines_only() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_eq(_values(bar), FIXTURE_VALUES, "machines, blocked, done, working, idle, panes")
	_eq(_titles(bar), ["MACHINES", "BLOCKED", "DONE", "WORKING", "IDLE", "PANES"], "in herdr's words")
	_check(not bar.alarmed(), "every machine answers")
	_eq(bar.counter(&"blocked").theme_type_variation, &"CounterHot", "somebody waits: BLOCKED is the loud one")
	_eq(bar.counter(&"machines").theme_type_variation, &"Counter", "MACHINES is quiet")
	var theme := bar.theme_line()
	_set_online(office, false)
	await _frames(1)
	_eq(_values(bar), ["0/1", "0", "0", "0", "0", "0"], "a dropped machine is nobody working, waiting or idle")
	_check(bar.alarmed(), "MACHINES says a machine is down")
	_eq(bar.counter(&"machines").theme_type_variation, &"CounterHot", "as loud as BLOCKED")
	_eq(bar.counter(&"blocked").theme_type_variation, &"Counter", "and BLOCKED is quiet: nobody live waits")
	_eq(bar.status_line(), "OFFLINE / RECONNECTING", "the status line says the same")
	_eq(bar.theme_line(), theme, "the pack's line stays")
	_set_online(office, true)
	await _frames(1)
	_eq(_values(bar), FIXTURE_VALUES, "back: the same six")
	_check(not bar.alarmed(), "and nothing is down")
	_done(office)


## The fixture's counters at every width the office supports: titles on a
## screen wide enough for them (800 up), icon and number on the narrowest
## (480), and at 640, where titles are allowed, whichever fits. Wherever,
## each one holds everything it shows, none overlaps another, and all stand
## inside the bar, clear of the wordmark and left of the right-hand lines.
func test_titles_hide_on_a_narrow_bar_and_every_chip_fits() -> void:
	var office := await _live_office()
	await _known_blocked(office)
	await _text_tick()
	var bar := office.hud.bar
	var widths: Array[float] = [480.0, office.hud.bar_titles_from, 800.0, 1920.0]
	for width in widths:
		var screen := Vector2(width, 480.0 if width > 480.0 else 320.0)
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		_eq(
			bar.counter(&"blocked").extra_text().begins_with("max "), true, "the longest wait is written at %s" % screen
		)
		if width < office.hud.bar_titles_from:
			_check(bar.counters().all(_untitled), "no titles and no `max` below %s" % office.hud.bar_titles_from)
			_check(bar.counters().all(_iconic), "the fixture's numbers leave room for the icons at %s" % screen)
		elif width >= 800.0:
			_check(bar.counters().all(_titled), "titles and `max` at %s" % screen)
		_fits(bar, "at %s" % screen)
	_done(office)


## Two- and three-digit counts, ten of twelve machines and an hour's wait: on
## the narrowest bar the counters give up titles and then icons, and the
## numbers still all show, inside their chips; on the widest they show all.
func test_a_crowded_bar_keeps_every_number() -> void:
	var hud := await _bare_hud(Vector2(480, 320))
	var totals := OfficeTotals.new()
	totals.machines_live = 10
	totals.machines_total = 12
	totals.blocked = 12
	totals.done = 34
	totals.working = 56
	totals.idle = 78
	totals.panes = 999
	hud.show_totals(totals)
	hud.show_longest_wait("1h 05m+")
	await _frames(2)
	var bar := hud.bar
	_eq(_values(bar), ["10/12", "12", "34", "56", "78", "999"], "every number")
	_check(bar.counters().all(_untitled), "no titles at 480")
	_check(not bar.counters().any(_icon_shown), "and, crowded, no icons: the numbers come first")
	_fits(bar, "crowded at 480")
	hud.fit(Vector2(1920, 480))
	await _frames(2)
	_check(bar.counters().all(_titled) and bar.counters().all(_iconic), "at 1920 titles and icons are back")
	_eq(bar.counter(&"blocked").extra_text(), "max 1h 05m+", "with the whole longest wait")
	_check(_node(bar.counter(&"blocked"), "%Extra").visible, "shown")
	_fits(bar, "crowded at 1920")
	hud.free()


## Every status the office can write, in both packs, fits the right-hand
## lines without an ellipsis on the narrowest and the widest bar, and so does
## each pack's name with its `[T]`.
func test_every_status_fits_the_lines_at_every_width() -> void:
	var statuses := PackedStringArray()
	for read_only: bool in [true, false]:
		for machines: Vector2i in [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 10), Vector2i(1, 100)]:
			statuses.append(OfficeScene.bar_status(read_only, machines.x, machines.y))
	_check(statuses.has("OFFLINE / RECONNECTING"), "the longest one is among them")
	_check(statuses.has("99 OFFLINE / READ ONLY"), "and a two-digit outage")
	for manifest: String in MANIFESTS:
		var hud := await _bare_hud(Vector2(480, 320), manifest)
		var name := ArtPack.from_manifest(manifest).display_name.to_upper() + "  [T]"
		var status_line: Label = hud.bar.get_node("%StatusLine")
		var theme_line: Label = hud.bar.get_node("%ThemeLine")
		for screen: Vector2 in [Vector2(480, 320), Vector2(1920, 960)]:
			hud.fit(screen)
			await _frames(2)
			for status in statuses:
				for alarmed: bool in [false, true]:
					hud.show_bar(name, status, alarmed)
					_check(_fits_label(status_line), "`%s` fits at %s (%s)" % [status, screen, manifest])
			_check(_fits_label(theme_line), "`%s` fits at %s" % [name, screen])
		hud.free()


## Resting the pointer on MACHINES says how each machine answers and how long
## ago it was last heard from; a dropped one says OFFLINE, and when.
func test_hovering_machines_says_how_each_answers() -> void:
	var office := await _live_office()
	var counter := office.hud.bar.counter(&"machines")
	await _hover(counter)
	_eq(root.gui_get_hovered_control(), counter, "the pointer is over the counter itself")
	var tip := counter.get_tooltip(counter.get_local_mouse_position())
	_check(tip.begins_with("Local · LIVE · last snapshot "), "live, heard from: " + tip)
	_check(tip.ends_with(" ago"), "and how long ago: " + tip)
	# The counter's tooltip_text is empty: what shows is what _get_tooltip() writes.
	var delay: float = ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)
	await _wait_seconds(delay + 0.7)
	var popups := _tooltips_shown()
	var shown := false
	for text in popups:
		shown = shown or text.begins_with("Local · LIVE · last snapshot ")
	_check(shown, "the tooltip really shows it: " + str(popups))
	_set_online(office, false)
	await _frames(1)
	tip = counter.get_tooltip(counter.get_local_mouse_position())
	_check(tip.begins_with("Local · OFFLINE · last snapshot "), "dropped, still when it was last heard: " + tip)
	_check(tip.ends_with(" ago"), "a time, not never: " + tip)
	_done(office)


## BLOCKED and IDLE break down by machine and space, by workspace number, with
## each pane's time in that state (a start never seen: the time the state log
## saw, with `+`, as the OVERVIEW's FOR says it); DONE and WORKING count
## without times; PANES has nothing to break down.
func test_hovering_blocked_and_idle_breaks_down_by_machine_and_space() -> void:
	var office := await _live_office()
	# web:p1 blocked and api:p2 idle from now; infra's were so from the first snapshot.
	var warmed := _with(_with(fixture, "web:p1", {"agent_status": "working"}), "api:p2", {"agent_status": "working"})
	_feed(office, warmed)
	_feed(office, fixture)
	await _frames(1)
	var bar := office.hud.bar
	var blocked := await _tip_of(bar.counter(&"blocked"))
	_eq(blocked.size(), 2, "one line per space: " + str(blocked))
	_check(
		blocked[0].begins_with("Local · web  1  (") and blocked[0].ends_with("s)"), "web first, timed: " + blocked[0]
	)
	_check(
		blocked[1].begins_with("Local · infra  1  (") and blocked[1].ends_with("s+)"),
		"infra after it, its start never seen: at least as long as watched: " + blocked[1]
	)
	var idle := await _tip_of(bar.counter(&"idle"))
	_eq(idle.size(), 2, "the launching data:p2 is not idle yet: " + str(idle))
	_check(idle[0].begins_with("Local · api  1  (") and idle[0].ends_with("s)"), "api idle, timed: " + idle[0])
	_check(idle[1].begins_with("Local · infra  1  (") and idle[1].ends_with("s+)"), "infra idle, at least: " + idle[1])
	var done := await _tip_of(bar.counter(&"done"))
	_eq(done, PackedStringArray(["Local · web  1", "Local · infra  1"]), "UNREAD, no times")
	var working := await _tip_of(bar.counter(&"working"))
	_eq(working, PackedStringArray(["Local · api  2", "Local · 数据 pipeline  1"]), "working, no times")
	_eq(await _tip_of(bar.counter(&"panes")), PackedStringArray(["PANES 13"]), "PANES only has its number")
	_done(office)


## A real click on BLOCKED picks the agent that has waited longest, shows its
## floor and brings its desk on screen; the next click the next one, then round
## again: the order `N` walks the blocked in.
func test_clicking_blocked_walks_the_longest_waits_like_n() -> void:
	var office := await _live_office()
	# infra:p1 blocks first, web:p1 later: the reverse of floor order.
	var both_working := _with(
		_with(fixture, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "working"}
	)
	_feed(office, both_working)
	_feed(office, _with(fixture, "web:p1", {"agent_status": "working"}))
	OS.delay_msec(20)
	_feed(office, fixture)
	await _frames(1)
	var counter := office.hud.bar.counter(&"blocked")
	var walked: Array[String] = []
	for press in 3:
		await _press(counter)
		await _frames(3)
		var key := office.picked_key
		walked.append(key)
		_eq(office.navigator.shown_key, office.frame.floor_of(key), "press %d shows the floor of %s" % [press, key])
		_check(office.hud.world_rect().has_point(_desk_point(office, key)), "and brings its desk on screen")
	_eq(walked, [_pane("infra:p1"), _pane("web:p1"), _pane("infra:p1")], "longest wait first, then round again")
	office.picked_key = ""
	var by_n: Array[String] = []
	for press in 2:
		await _office_key(office, KEY_N)
		by_n.append(office.picked_key)
	_eq(by_n, walked.slice(0, 2), "`N` walks the blocked in the same order")
	_done(office)


## DONE picks the oldest UNREAD agent and only picks: no answer mode, no card
## opened up. The next click the next one.
func test_clicking_done_picks_the_oldest_unread() -> void:
	var office := await _live_office()
	var both_working := _with(
		_with(fixture, "web:p2", {"agent_status": "working"}), "infra:p2", {"agent_status": "working"}
	)
	_feed(office, both_working)
	_feed(office, _with(fixture, "web:p2", {"agent_status": "working"}))
	OS.delay_msec(20)
	_feed(office, fixture)
	await _frames(1)
	var counter := office.hud.bar.counter(&"done")
	await _press(counter)
	await _frames(3)
	_eq(office.picked_key, _pane("infra:p2"), "the one UNREAD longest")
	_eq(office.navigator.shown_key, _floor("infra"), "on its floor")
	_check(not office.hud.inspector.answering(), "not answering")
	_check(not office.hud.card_expanded(), "and no card opened up for it")
	await _press(counter)
	await _frames(3)
	_eq(office.picked_key, _pane("web:p2"), "then the next")
	_done(office)


## WORKING shows only the working agents in the list and reads pressed; again,
## every pane is back. IDLE the idle ones, never one still launching.
func test_clicking_working_filters_the_list_and_again_clears_it() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var list := office.hud.agent_list
	var everyone := list.shown_keys()
	await _press(bar.counter(&"working"))
	_eq(_panes_shown(office), _sorted([_pane("api:p1"), _pane("api:p4"), _pane("data:p1")]), "only who is working")
	_eq(bar.counter(&"working").theme_type_variation, &"CounterOn", "WORKING reads pressed")
	_eq(_node(bar.counter(&"working"), "%Value").theme_type_variation, &"CounterValuePaper", "its number in paper")
	await _press(bar.counter(&"working"))
	_eq(list.shown_keys(), everyone, "again: everyone")
	_eq(bar.counter(&"working").theme_type_variation, &"Counter", "and it lets go")
	await _press(bar.counter(&"idle"))
	_eq(_panes_shown(office), _sorted([_pane("api:p2"), _pane("infra:p3")]), "only who is idle")
	_check(not list.shown_keys().has(_pane("data:p2")), "not the one still launching")
	_eq(bar.counter(&"idle").theme_type_variation, &"CounterOn", "IDLE reads pressed")
	await _press(bar.counter(&"working"))
	_eq(_panes_shown(office), _sorted([_pane("api:p1"), _pane("api:p4"), _pane("data:p1")]), "WORKING takes over")
	_eq(bar.counter(&"idle").theme_type_variation, &"Counter", "and IDLE lets go")
	_done(office)


## A filter opens a closed drawer, or its list is out of sight; clearing it
## asks for nothing to be shown, so a drawer closed since stays closed and the
## world keeps its room. Another filter opens it again.
func test_clearing_a_filter_leaves_a_closed_drawer_closed() -> void:
	var office := await _live_office()
	var hud := office.hud
	var bar := hud.bar
	var list := hud.agent_list
	var everyone := list.shown_keys()
	var collapse: Control = hud.get_node("%Collapse")
	_check(not hud.drawer_open(), "every run starts with the drawer closed")
	await _press(bar.counter(&"working"))
	await _frames(2)
	_check(hud.drawer_open(), "WORKING opens it")
	_eq(_panes_shown(office), _sorted([_pane("api:p1"), _pane("api:p4"), _pane("data:p1")]), "on the working ones")
	await _press(collapse)
	await _frames(2)
	_check(not hud.drawer_open(), "closed again, the filter still on")
	var room := hud.world_rect()
	await _press(bar.counter(&"working"))
	await _frames(2)
	_eq(bar.counter(&"working").theme_type_variation, &"Counter", "WORKING again clears the filter")
	_eq(list.shown_keys(), everyone, "for everyone")
	_check(not hud.drawer_open(), "and leaves the drawer closed")
	_eq(hud.world_rect(), room, "the world keeps its room")
	await _press(bar.counter(&"idle"))
	await _frames(2)
	_check(hud.drawer_open(), "IDLE opens it")
	_eq(_panes_shown(office), _sorted([_pane("api:p2"), _pane("infra:p3")]), "on the idle ones")
	await _press(bar.counter(&"idle"))
	await _frames(2)
	_check(hud.drawer_open(), "clearing with the drawer open leaves it open")
	_eq(list.shown_keys(), everyone, "for everyone")
	_done(office)


## The showroom's top bar is the office's own: its pack name and its status
## fit the right-hand lines in both packs, with no ellipsis.
func test_the_showroom_status_fits_the_lines() -> void:
	for manifest: String in MANIFESTS:
		var showroom: Node = (load("res://scenes/preview.tscn") as PackedScene).instantiate()
		showroom.set("manifest_path", manifest)
		root.add_child(showroom)
		await _frames(2)
		var hud: OfficeHud = null
		for child in showroom.get_children():
			if child is OfficeHud:
				hud = child as OfficeHud
		_check(hud != null, "the showroom has the office's HUD (%s)" % manifest)
		if hud != null:
			var status_line: Label = hud.bar.get_node("%StatusLine")
			var theme_line: Label = hud.bar.get_node("%ThemeLine")
			_check(status_line.text != "", "it says something (%s)" % manifest)
			_check(_fits_label(status_line), "`%s` fits (%s)" % [status_line.text, manifest])
			_check(_fits_label(theme_line), "`%s` fits (%s)" % [theme_line.text, manifest])
		showroom.free()


## The longest blocked wait is written after BLOCKED's number and grows on
## attention's beat, with `+` while a blocked start is unknown (it may be
## longer than watched); nobody blocked, nothing.
func test_the_longest_wait_ticks_on_the_attention_beat() -> void:
	var office := await _live_office()
	var counter := office.hud.bar.counter(&"blocked")
	await _text_tick()
	# It says what the OVERVIEW's FOR says,
	# the stretch watched so far, `+`: at least that long.
	var first := counter.extra_text()
	_check(
		first.begins_with("max ") and first.ends_with("s+"), "both blocked since before the first snapshot: " + first
	)
	await _known_blocked(office)
	await _text_tick()
	var extra := counter.extra_text()
	_check(extra.begins_with("max ") and extra.ends_with("s+"), "web:p1's wait, and infra:p1's unknown: " + extra)
	_check(_node(counter, "%Extra").visible, "shown beside the number")
	# infra:p1 blocks again from now: every start is known, and no `+`.
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	_feed(office, fixture)
	await _text_tick()
	extra = counter.extra_text()
	_check(extra.begins_with("max ") and extra.ends_with("s"), "every start known: " + extra)
	_check(not extra.ends_with("+"), "a plain longest wait: " + extra)
	var nobody := _with(_with(fixture, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "working"})
	_feed(office, nobody)
	await _text_tick()
	_eq(counter.extra_text(), "", "nobody blocked: nothing")
	_check(not _node(counter, "%Extra").visible, "and nothing shown")
	_done(office)


## The top bar's `max`, its hover and the OVERVIEW's FOR say one number for
## the same blocked pane: web:p1 and infra:p1 were blocked before the first
## snapshot, so all three say the stretch this office watched, with `+`. On
## d48c61e the `max` said nothing and the hover `?` while the overview said `Ns+`.
func test_the_top_bar_and_the_overview_say_the_same_wait() -> void:
	var office := await _live_office()
	await _wait_seconds(1.2)
	office.open_overview()
	await _text_tick()
	office.refresh()
	await _frames(1)
	var fors: Array[int] = []
	for key: String in [_pane("web:p1"), _pane("infra:p1")]:
		var line := office.hud.overview.line_for(key)
		_check(line != null, "%s has an overview row" % key)
		if line == null:
			continue
		var for_label: Label = line.get_node("%For")
		var said := for_label.text
		_check(said.ends_with("s+"), "%s: FOR `%s`, at least" % [key, said])
		fors.append(int(said.trim_suffix("s+")))
	var extra := office.hud.bar.counter(&"blocked").extra_text()
	_check(extra.begins_with("max ") and extra.ends_with("s+"), "the top bar says a time too: `%s`" % extra)
	var longest := int(extra.trim_prefix("max ").trim_suffix("s+"))
	_check(fors.size() == 2 and longest >= 1, "a second has passed: `%s`" % extra)
	if fors.size() == 2:
		_check(absi(longest - maxi(fors[0], fors[1])) <= 1, "`%s` is the overview's longest %s" % [extra, fors])
	var tip := office.hud.bar.counter(&"blocked").tooltip_at(Time.get_unix_time_from_system(), Time.get_ticks_msec())
	_check(not tip.contains("?"), "the hover times both: " + tip)
	var tipped: Array[int] = []
	for line in tip.split("\n"):
		var said := line.get_slice("(", 1).trim_suffix(")")
		_check(said.ends_with("s+"), "`%s` at least" % line)
		tipped.append(int(said.trim_suffix("s+")))
	tipped.sort()
	fors.sort()
	_eq(tipped.size(), fors.size(), "a time per blocked pane: " + tip)
	for index in mini(tipped.size(), fors.size()):
		_check(absi(tipped[index] - fors[index]) <= 1, "hover %s is the overview's %s" % [tipped, fors])
	office.close_overview()
	_done(office)


## `--read-only` counts the same, and a click on BLOCKED only picks.
func test_read_only_shows_the_same_counts() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_check(bar.status_line().begins_with("LIVE / READ ONLY"), "read only: " + bar.status_line())
	_eq(_values(bar), FIXTURE_VALUES, "the same six numbers")
	await _press(bar.counter(&"blocked"))
	await _frames(3)
	_check(not office.picked_key.is_empty(), "the click picks somebody blocked")
	_eq(office.frame.pane(office.picked_key).state, "blocked", "blocked")
	_check(not office.hud.inspector.answering(), "and never answers")
	_done(office)


## A pane no floor seats still counts, under its machine and a space it cannot
## name, with no start to time; a dropped machine's panes never count.
func test_unseated_panes_count_and_dropped_machines_do_not() -> void:
	var loose := _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	var states := PackedStringArray(["working", "blocked", "done", "idle", "unknown"])
	var machines: Array[MachineView] = [
		MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(loose), false),
		MachineView.new("socket:bee", "bee", HerdrSnapshot.from_wire(fixture), true),
	]
	var frame := OfficeProjection.frame(machines, states)
	var totals := OfficeTotals.of(frame, [], StateLog.new())
	_eq([totals.machines_live, totals.machines_total], [1, 2], "one of two answers")
	_eq(totals.blocked, 3, "Local's two, and the pane no floor seats; nothing of bee's")
	_eq(totals.panes, 13, "bee's thirteen panes are not counted")
	var rows := totals.rows_of(&"blocked")
	_eq(
		rows.map(func(row: OfficeTotals.CounterRow) -> String: return row.space), ["web", "infra", "?"], "unseated last"
	)
	_eq(rows[2].tracks.size(), 1, "one pane there")
	_check(rows[2].tracks[0] == null, "a log that never saw it: no track, no start")
	_eq(totals.blocked_tracks.size(), 3, "the three blocked the `max` is taken over")
	_check(StateLog.longest(totals.blocked_tracks, 0).plus, "none of them seen begin: at least")


## The showroom's top bar counts its own mock: Local's panes in the state the
## mock ledger leaves each in, bee (dropped) in no count, one of two machines
## answering. The same six numbers the live office's rule gives, worked out
## here from the showroom's own table; BLOCKED's hover names Local's spaces.
func test_the_showroom_counts_its_mock_panes() -> void:
	var showroom: Node = (load(SHOWROOM_SCENE) as PackedScene).instantiate()
	var source: Script = showroom.get_script()
	var table: Array = source.get_script_constant_map()["MOCK_PANES"]
	var counts: Dictionary[String, int] = {"blocked": 0, "done": 0, "working": 0, "idle": 0}
	var blocked_spaces := PackedStringArray()
	var panes := 0
	for pane: Array in table:
		if pane[0] != "local":
			continue
		panes += 1
		var steps: Array = pane[6]
		var last: Array = steps.back()
		var state: String = last[1]
		counts[state] += 1
		if state == "blocked" and not str(pane[3]) in blocked_spaces:
			blocked_spaces.append(str(pane[3]))
	var expected: Array[String] = ["1/2"]
	for state: String in ["blocked", "done", "working", "idle"]:
		expected.append(str(counts[state]))
	expected.append(str(panes))
	root.add_child(showroom)
	await _frames(2)
	var hud: OfficeHud = null
	for child in showroom.get_children():
		if child is OfficeHud:
			hud = child as OfficeHud
	_check(hud != null, "the showroom has the office's HUD")
	if hud == null:
		showroom.free()
		return
	_check(counts.blocked > 0 and counts.idle > 0, "the mock has something to count: %s" % counts)
	_eq(_values(hud.bar), expected, "Local's mock panes, bee dropped")
	var tip := await _tip_of(hud.bar.counter(&"blocked"))
	for space in blocked_spaces:
		_check(_opens_a_line(tip, "Local · %s  " % space), "%s: %s" % [space, tip])
	_check(not _opens_a_line(tip, "bee"), "nothing of bee's: %s" % tip)
	showroom.free()


## Read-only: NEXT says no verb, only whom and herdr's state, and a
## real click on it, like `N`, only picks: the panel stays one line, no answer
## mode, and nothing is read or written.
func test_read_only_next_says_no_verb_and_only_picks() -> void:
	var office := await _live_office(_with(fixture, "api:p1", {"agent_status": "blocked"}))
	var card := office.hud.inspector
	var button: Button = card.get_node("%NextButton")
	await _frames(2)
	_check(office.fleet.read_only(), "this suite runs read-only")
	var named := office.navigator.peek_next(office.frame)
	var next := office.frame.pane(named)
	_check(next != null, "somebody is next")
	if next == null:
		_done(office)
		return
	var said := "%s %s · %s" % [next.provider.to_upper(), next.workspace_label, next.state]
	_check(card.next_text().begins_with(said), "NEXT names whom and why, no verb: " + card.next_text())
	_check(not card.next_text().begins_with("Answer") and not card.next_text().begins_with("Read"), "no verb")
	_check(
		button.tooltip_text.begins_with(OfficePaneInspector.NEXT_PICKS_TIP),
		"its tooltip says it only picks: " + button.tooltip_text
	)
	_check(not "answer keys" in button.tooltip_text, "and promises no answer keys")
	await _press(button)
	await _frames(3)
	_eq(office.picked_key, named, "a click picks whom it named")
	_check(office.hud.card_compact(), "and the panel stays one line")
	_check(not card.answering(), "no answer mode")
	var again := office.navigator.peek_next(office.frame)
	await _office_key(office, KEY_N)
	await _frames(3)
	_eq(office.picked_key, again, "N picks the next")
	_check(office.hud.card_compact() and not card.answering(), "and opens nothing either")
	_check(office.fleet.read_log().is_empty(), "nothing was read")
	_check(office.fleet.write_log().is_empty(), "nothing was written")
	_done(office)


## The showroom's NEXT follows the mock its top bar counts, by the office's
## own rule (OfficeNavigator.peek_next()): the blocked before the done, whoever
## has waited longest first (a start at minute 0 is the baseline, never seen,
## so the longest of all); bee dropped, so none of its. `All clear` only when
## the mock has nobody to go to.
func test_the_showroom_next_names_a_mock_pane_that_waits() -> void:
	var showroom: Node = (load(SHOWROOM_SCENE) as PackedScene).instantiate()
	var source: Script = showroom.get_script()
	var table: Array = source.get_script_constant_map()["MOCK_PANES"]
	var who := ""
	var state := ""
	var since := 0
	for wanted: String in ["blocked", "done"]:
		for pane: Array in table:
			var steps: Array = pane[6]
			var last: Array = steps.back()
			var minute: int = last[0]
			var began := -1 if minute == 0 else minute
			if pane[0] == "local" and str(last[1]) == wanted and (who.is_empty() or began < since):
				who = "%s %s" % [str(pane[2]).to_upper(), str(pane[3])]
				state = wanted
				since = began
		if not who.is_empty():
			break
	_check(state == "blocked", "the mock has a blocked pane to go to first: %s" % who)
	root.add_child(showroom)
	await _frames(2)
	var hud: OfficeHud = null
	for child in showroom.get_children():
		if child is OfficeHud:
			hud = child as OfficeHud
	_check(hud != null, "the showroom has the office's HUD")
	if hud == null:
		showroom.free()
		return
	var card := hud.inspector
	var button: Button = card.get_node("%NextButton")
	_check(card.compact(), "the showroom's staff panel is the compact line")
	# 800 wide: the line has room for the whole sentence; the showroom
	# writes nothing, so it says no verb, only whom and herdr's state.
	_check(
		card.next_text().begins_with("%s · %s @ Local" % [who, state]), "NEXT names the mock's first pane that waits"
	)
	_check(not button.disabled, "and can be pressed")
	_check(
		("\nNext: %s · %s @ Local" % [who, state]) in button.tooltip_text,
		"its tooltip says the whole sentence: %s" % button.tooltip_text
	)
	showroom.free()


## Panes no floor seats wait in the same order as seated ones
## (OfficeProjection.wait_order()): NEXT, `N` and a click on BLOCKED go to
## whoever has waited longest first, the blocked only while anyone is,
## the done once nobody is. api:p1 and api:p4 claim web while their tab is
## api's, so no floor seats them; api:p4 blocks first, api:p1 a second later,
## while web:p2 and infra:p2 sit done from before the office looked. Nothing
## else is blocked.
func test_panes_no_floor_seats_wait_in_the_same_order() -> void:
	var quiet := _with(fixture, "web:p1", {"agent_status": "working"})
	quiet = _with(quiet, "infra:p1", {"agent_status": "working"})
	quiet = _with(quiet, "api:p1", {"workspace_id": "web"})
	quiet = _with(quiet, "api:p4", {"workspace_id": "web"})
	var office := await _live_office(quiet)
	_check(office.frame.floor_of(_pane("api:p1")).is_empty(), "no floor seats api:p1")
	_check(office.frame.floor_of(_pane("api:p4")).is_empty(), "nor api:p4")
	var first := _with(quiet, "api:p4", {"agent_status": "blocked"})
	_feed(office, first)
	await _wait_seconds(1.2)
	_feed(office, _with(first, "api:p1", {"agent_status": "blocked"}))
	await _frames(2)
	_check(
		office.hud.inspector.next_text().begins_with("PI "),
		"NEXT names api:p4, blocked longer: " + office.hud.inspector.next_text()
	)
	await _press(office.hud.bar.counter(&"blocked"))
	_eq(office.picked_key, _pane("api:p4"), "BLOCKED goes to api:p4 first")
	var walked: Array[String] = []
	for press in 3:
		await _office_key(office, KEY_N)
		walked.append(office.picked_key)
	_eq(walked.slice(0, 1), [_pane("api:p1")], "then `N` goes to api:p1")
	# While they are blocked `N` goes round the two, not on to the done.
	_eq(walked.slice(1), [_pane("api:p4"), _pane("api:p1")], "and round the blocked again, never to the done")
	_feed(office, quiet)
	await _frames(2)
	var done: Array[String] = []
	for press in 2:
		await _office_key(office, KEY_N)
		done.append(office.picked_key)
	_eq(_sorted(done), _sorted([_pane("infra:p2"), _pane("web:p2")]), "and only once nobody is blocked to the done")


## Whether a line of `lines` begins with `start`.
static func _opens_a_line(lines: PackedStringArray, start: String) -> bool:
	for line in lines:
		if line.begins_with(start):
			return true
	return false


## Blocked comes first: api:p1 asking while herdr still
## launches it is a blocked agent. BLOCKED counts it and WORKING does
## not; its line in BLOCKED's hover is timed from when the office saw it
## block, with no `+`; a click on BLOCKED reaches it after the two whose starts
## were never seen, and with nobody else blocked NEXT names it. herdr finishing
## the launch while it still asks changes no count, and its wait runs on; herdr
## launching it again while it asks restarts nothing.
func test_a_blocked_agent_still_launching_is_counted_and_next() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var asking := _with(fixture, "api:p1", {"agent_status": "blocked", "launch_pending": true})
	_feed(office, asking)
	await _frames(1)
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches api:p1")
	_eq(_values(bar), ["1/1", "3", "2", "2", "2", "13"], "BLOCKED counts it, WORKING lets it go, IDLE as it was")
	await _wait_seconds(1.2)
	var api := _api_line(await _tip_of(bar.counter(&"blocked")))
	_check(api.ends_with("s)") and not api.ends_with("s+)"), "its own line, timed from its block, no `+`: " + api)
	var waited := int(api.get_slice("(", 1).trim_suffix("s)"))
	_check(waited >= 1, "a second has passed: " + api)
	var walked: Array[String] = []
	for press in 3:
		await _press(bar.counter(&"blocked"))
		await _frames(3)
		walked.append(office.picked_key)
	_eq(walked[2], _pane("api:p1"), "BLOCKED reaches it, after the two blocked since before the office looked")
	var three: Array[String] = [_pane("api:p1"), _pane("infra:p1"), _pane("web:p1")]
	_eq(_sorted(walked), _sorted(three), "one press each: " + str(walked))
	var alone := _with(_with(asking, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "working"})
	office.picked_key = ""
	_feed(office, alone)
	await _frames(1)
	_check(
		office.hud.inspector.next_text().begins_with("CLAUDE api · blocked"),
		"NEXT names it: " + office.hud.inspector.next_text()
	)
	var since := office.fleet.state_since(LOCAL, "api:p1")
	_check(since > 0.0, "the client times it from its block")
	_feed(office, _with(alone, "api:p1", {"launch_pending": false}))
	await _frames(1)
	_check(not office.frame.pane(_pane("api:p1")).starting, "herdr finished the launch")
	_eq(_values(bar)[1], "1", "still asking: still counted")
	_eq(
		office.fleet.state_since(LOCAL, "api:p1"),
		since,
		"the client's clock runs on: the launch ending is no new state"
	)
	var later := _api_line(await _tip_of(bar.counter(&"blocked")))
	_check(
		int(later.get_slice("(", 1).trim_suffix("s)")) >= waited, "the wait goes on, not over: %s, %s" % [api, later]
	)
	_feed(office, _with(alone, "api:p1", {"launch_pending": true}))
	await _frames(1)
	_eq(office.fleet.state_since(LOCAL, "api:p1"), since, "herdr launching it again while it asks restarts nothing")
	_eq(_values(bar)[1], "1", "and it is still counted")
	_done(office)


## The other half of the rule: an
## agent herdr is still launching that does not ask counts nowhere, idle or at
## work.
func test_a_launching_agent_that_is_not_blocked_is_still_not_counted() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_feed(office, _with(fixture, "api:p2", {"launch_pending": true}))
	await _frames(1)
	_eq(_values(bar), ["1/1", "2", "2", "3", "1", "13"], "an idle agent still launching is not idle yet")
	_feed(office, _with(fixture, "api:p1", {"launch_pending": true}))
	await _frames(1)
	_eq(_values(bar), ["1/1", "2", "2", "2", "2", "13"], "nor is a working one at work")
	_done(office)


## The chime switch at the right end of the counters' row, against the lines:
## a click turns the chime on, the switch says `CHIME ON` in the lines' cream,
## and again off; its tooltip says what it is for. A test office keeps nothing:
## its settings file (here one in the case's own work directory, never
## user://) is not written.
func test_the_chime_switch_flips_the_chime_and_what_it_says() -> void:
	var path: String = args.work.path_join("chime-switch.cfg")
	DirAccess.remove_absolute(path)
	var office := await _chime_office(path, false, [])
	var switch := _chime_switch(office)
	_check(not office.alerts.options.chime, "the chime starts off")
	_eq(switch.text, OfficeBar.CHIME_OFF, "and the switch says so")
	_eq(switch.theme_type_variation, &"BarSwitch", "in the lines' muted colour")
	_eq(
		switch.tooltip_text,
		"Chime when an agent needs you while Herdstead is in the background",
		"the tooltip says what it is for"
	)
	await _press(switch)
	_check(office.alerts.options.chime, "a click turns the chime on")
	_eq(switch.text, OfficeBar.CHIME_ON, "the switch says CHIME ON")
	_eq(switch.theme_type_variation, &"BarSwitchOn", "in cream")
	_check(office.hud.bar.chime_shown(), "and the bar reads it on")
	await _press(switch)
	_check(not office.alerts.options.chime, "a second click turns it off")
	_eq(switch.text, OfficeBar.CHIME_OFF, "and the switch says so")
	_check(not FileAccess.file_exists(path), "a test office writes no settings file")
	_done(office)


## An office that keeps its settings (remember_theme, as a real run) writes the
## switch's choice as `[alerts] chime` into its settings file, keeping what else
## the file holds; the next office starts from it. `--chime` turns the chime on
## for the run whatever the file says, and the switch still turns it off.
func test_the_chime_switch_is_kept_for_the_next_run() -> void:
	var path: String = args.work.path_join("chime-kept.cfg")
	var first := ConfigFile.new()
	first.set_value("theme", "manifest_path", MANIFESTS[0])
	_eq(first.save(path), OK, "a settings file with a theme in it")
	var office := await _chime_office(path, true, [])
	var switch := _chime_switch(office)
	_eq(switch.text, OfficeBar.CHIME_OFF, "no [alerts] section: off")
	await _press(switch)
	_check(office.alerts.options.chime, "a click turns the chime on")
	_check(OfficeAlerts.remembered_chime(path), "and the file says chime=true")
	var kept := ConfigFile.new()
	_eq(kept.load(path), OK, "the file reads back")
	_eq(str(kept.get_value("theme", "manifest_path", "")), MANIFESTS[0], "with the theme it held")
	_done(office)
	var next := await _chime_office(path, true, [])
	_check(next.alerts.options.chime, "the next office starts with the chime on")
	_eq(_chime_switch(next).text, OfficeBar.CHIME_ON, "and says so")
	await _press(_chime_switch(next))
	_check(not OfficeAlerts.remembered_chime(path), "off again, the file says chime=false")
	_done(next)
	var flagged := await _chime_office(path, true, ["--chime"])
	_check(flagged.alerts.options.chime, "--chime turns it on whatever the file says")
	_eq(_chime_switch(flagged).text, OfficeBar.CHIME_ON, "and the switch says so")
	await _press(_chime_switch(flagged))
	_check(not flagged.alerts.options.chime, "the switch still turns it off")
	_done(flagged)
	DirAccess.remove_absolute(path)


## Where titles are allowed the switch stands in the counters' row, after
## PANES and left of the lines, inside the bar, and every counter still holds
## what it shows; on a bar too narrow for titles it steps aside, and the
## counters keep the room they had (the fixture's icons at 480).
func test_the_chime_switch_fits_and_steps_aside_on_a_narrow_bar() -> void:
	var office := await _live_office()
	await _known_blocked(office)
	var bar := office.hud.bar
	var switch := _chime_switch(office)
	var lines: Control = bar.get_node("%Lines")
	for width: float in [480.0, office.hud.bar_titles_from, 800.0, 960.0, 1920.0]:
		var screen := Vector2(width, 480.0 if width > 480.0 else 320.0)
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var where := "at %s" % screen
		_fits(bar, where)
		if width < office.hud.bar_titles_from:
			_check(not switch.visible, "no switch below %s" % office.hud.bar_titles_from)
			_check(bar.counters().all(_iconic), "the counters keep their icons " + where)
			continue
		_check(switch.visible, "the switch shows " + where)
		var rect := switch.get_global_rect()
		_check(bar.get_global_rect().encloses(rect), "inside the bar " + where)
		_check(rect.end.x <= lines.get_global_rect().position.x, "left of the lines " + where)
		var panes := bar.counter(&"panes").get_global_rect()
		_check(rect.position.x >= panes.end.x, "right of PANES " + where)
		_check(rect.size.x >= switch.get_combined_minimum_size().x, "as wide as its words " + where)
		if width >= 800.0:
			_check(bar.counters().all(_titled), "the counters keep their titles " + where)
	_done(office)


# --- helpers ------------------------------------------------------------------


## The line for api in BLOCKED's hover; empty when there is none.
func _api_line(lines: PackedStringArray) -> String:
	for line in lines:
		if line.begins_with("Local · api  1  ("):
			return line
	_fail("no api line in " + str(lines))
	return ""


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _floor(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


func _node(holder: Node, path: String) -> Control:
	return holder.get_node(path)


## A bare HUD dressed with `manifest`'s pack and laid out for `screen`: no
## office, so nothing writes into the bar behind the case.
func _bare_hud(screen: Vector2, manifest: String = MANIFESTS[0]) -> OfficeHud:
	var art := ArtPack.from_manifest(manifest)
	var hud: OfficeHud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(screen)
	await _frames(2)
	return hud


## Every counter inside the bar, clear of the wordmark and of the lines, none
## over another, each holding what it shows.
func _fits(bar: OfficeBar, when: String) -> void:
	var lines: Control = bar.get_node("%Lines")
	var wordmark: Control = bar.get_node("%Wordmark")
	var rects: Array[Rect2] = []
	for counter in bar.counters():
		var rect := counter.get_global_rect()
		var where := "%s %s" % [counter.id, when]
		_check(bar.get_global_rect().encloses(rect), "inside the bar: " + where)
		_check(rect.end.x <= lines.get_global_rect().position.x, "left of the lines: " + where)
		_check(rect.position.x >= wordmark.get_global_rect().end.x, "right of the whole wordmark: " + where)
		# What the counter shows is its Line; a Line that needs more than the
		# counter has grows past it, and the counter clips it.
		var line := _node(counter, "%Line").get_global_rect()
		_check(rect.encloses(line), "%s holds what it shows: %s in %s" % [where, line, rect])
		for other in rects:
			_check(not rect.intersects(other), "no overlap: " + where)
		rects.append(rect)


## Whether `label`'s text fits its width in its own font, with no ellipsis.
func _fits_label(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x


func _titled(counter: OfficeCounter) -> bool:
	return counter.shows_title() and _node(counter, "%Title").visible


func _untitled(counter: OfficeCounter) -> bool:
	return not counter.shows_title() and not _node(counter, "%Title").visible and not _node(counter, "%Extra").visible


## PANES has no icon at all: it counts as showing what it has.
func _iconic(counter: OfficeCounter) -> bool:
	return counter.shows_icon() or counter.id == &"panes"


func _icon_shown(counter: OfficeCounter) -> bool:
	return counter.shows_icon()


func _values(bar: OfficeBar) -> Array[String]:
	var found: Array[String] = []
	for counter in bar.counters():
		found.append(counter.value_text())
	return found


func _titles(bar: OfficeBar) -> Array[String]:
	var found: Array[String] = []
	for counter in bar.counters():
		found.append(counter.title_text())
	return found


## web:p1 blocked from now on (it was working a snapshot ago): a wait the
## office knows the start of. infra:p1 stays blocked since before it looked.
func _known_blocked(office: OfficeDouble) -> void:
	_feed(office, _with(fixture, "web:p1", {"agent_status": "working"}))
	_feed(office, fixture)
	await _frames(1)


## A real pointer motion onto the middle of `control`.
func _hover(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)


## A real left click on the middle of `control`.
func _press(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## The tooltip `control` gives with the pointer resting on it, a line each.
func _tip_of(control: Control) -> PackedStringArray:
	await _hover(control)
	_eq(root.gui_get_hovered_control(), control, "the pointer is over %s" % control.name)
	return control.get_tooltip(control.get_local_mouse_position()).split("\n")


## The pane keys the agent list draws now, sorted.
func _panes_shown(office: OfficeDouble) -> Array[String]:
	var found: Array[String] = []
	for key in office.hud.agent_list.shown_keys():
		if office.frame.pane(key) != null:
			found.append(key)
	return _sorted(found)


func _sorted(keys: Array[String]) -> Array[String]:
	var copy: Array[String] = keys.duplicate()
	copy.sort()
	return copy


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## The text of every tooltip Godot shows now: a visible PopupPanel the viewport
## keeps as an internal child, with a Label in it.
func _tooltips_shown() -> PackedStringArray:
	var found := PackedStringArray()
	_collect_tooltips(root, found)
	return found


func _collect_tooltips(node: Node, found: PackedStringArray) -> void:
	for child in node.get_children(true):
		if child is PopupPanel and (child as Window).visible:
			for label: Node in child.find_children("*", "Label", true, false):
				found.append((label as Label).text)
		_collect_tooltips(child, found)


## An office with its own command line (`flags` after the suite's own) that
## keeps its settings in `path` when `remember` is set, as a real run keeps them
## in user://; shown at 800 wide, where the chime switch shows.
func _chime_office(path: String, remember: bool, flags: Array[String]) -> OfficeDouble:
	var line := PackedStringArray(["--read-only", "--socket=" + args.socket, "--work=" + args.work])
	line.append_array(PackedStringArray(flags))
	var office := OfficeDouble.new()
	_live_offices.append(office)
	office.test_screen = Vector2(SCREEN)
	office.test_args = AppArgs.parse(line)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = remember
	office.settings_path = path
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	_feed(office, fixture)
	await _frames(2)
	return office


func _chime_switch(office: OfficeDouble) -> Button:
	return office.hud.bar.get_node("%Chime")
