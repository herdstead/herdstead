extends "res://tools/office_test_base.gd"
## The top bar: the portrait strip's agents from the live machines only, their
## cards' and folds' hovers, a card click picking (the list's path), a fold
## opening the OVERVIEW on its state, each blocked card's wait ticking on
## attention's beat, the status line's hover, `13 panes` and the chime switch,
## the title gap, and the showroom's bar. Hovers and clicks go through real
## input. Run through run_tests.sh. (S3 BAR-a, 2026-10-27: the portrait strip
## replaces the counters; the strip's own model, ladder and cards are
## tools/test_portrait_bar.gd's.)
##
## godot --headless --path . --script tools/test_top_bar.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## What tools/fixtures/snapshot_floors.json shows: Local live; blocked web:p1
## and infra:p1; UNREAD web:p2 and infra:p2; working api:p1, api:p4 and
## data:p1; idle api:p2 and infra:p3 (data:p2 is idle but still launching, so
## it has no card); thirteen panes with the three shells.
const FIXTURE_COUNTS: Array[int] = [2, 2, 3, 2]
## S3 TILES (2026-10-28): the count says the machines first, as B2 does
## (OfficeTotals.count_words()).
const FIXTURE_PANES := "1 machine · 13 panes"
## The asset showroom, whose top bar shows a mock of its own.
const SHOWROOM_SCENE := "res://scenes/preview.tscn"
## The existing 1920x960 capture's logical canvas at its integer 2x scale.
const SHOWROOM_SCREEN := Vector2i(960, 480)


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


## The live machine's agents have cards (or are counted in a fold); a dropped
## machine has none, the status line says so in the blocked colour, and
## `13 panes` counts nothing of it; back again, the same agents. The pack's
## line is not the machines' business.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_cards_come_from_live_machines_only() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var everyone := _everyone(bar)
	_eq(_counts(bar), FIXTURE_COUNTS, "blocked, done, working, idle")
	_eq(_panes_text(bar), FIXTURE_PANES, "and the panes")
	_check(everyone.all(func(key: String) -> bool: return key.begins_with(LOCAL)), "all Local's: %s" % [everyone])
	_check(not bar.alarmed(), "every machine answers")
	_eq(_status_label(bar).theme_type_variation, &"LabelCream", "the status line is quiet")
	var theme := bar.theme_line()
	_set_online(office, false)
	await _frames(1)
	_eq(_counts(bar), [0, 0, 0, 0], "a dropped machine is nobody working, waiting or idle")
	_check(bar.cards().is_empty(), "no card")
	_check(not bar.folds().any(func(fold: PortraitFold) -> bool: return fold.visible), "and no fold")
	# S3 TILES (2026-10-28): the count names the machines; the dropped one is still in the fleet.
	_eq(_panes_text(bar), "1 machine · 0 panes", "no panes")
	_check(bar.alarmed(), "the bar says a machine is down")
	_eq(_status_label(bar).theme_type_variation, &"LabelBlocked", "in the blocked colour")
	_eq(bar.status_line(), "OFFLINE / RECONNECTING", "the status line says so")
	_eq(bar.theme_line(), theme, "the pack's line stays")
	_set_online(office, true)
	await _frames(1)
	_eq(_everyone(bar), everyone, "back: the same agents, in the same order")
	_eq(_counts(bar), FIXTURE_COUNTS, "the same counts")
	_check(not bar.alarmed(), "and nothing is down")
	_done(office)


## The fixture's strip at every width the office supports: at 480, 640, 800
## and 1920 every card and fold stands inside the strip, none over another,
## clear of the wordmark and left of `13 panes`, the chime and the lines; what
## the rung needs fits the strip's room.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_the_strip_fits_every_width_and_nothing_overlaps() -> void:
	var office := await _live_office()
	await _known_blocked(office)
	await _text_tick()
	var bar := office.hud.bar
	var widths: Array[float] = [480.0, office.hud.bar_titles_from, 800.0, 1920.0]
	var rungs: Array[int] = []
	for width in widths:
		var screen := Vector2(width, 480.0 if width > 480.0 else 320.0)
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var strip: Control = bar.get_node("%Strip")
		_check(bar.fitted().needed <= strip.size.x, "rung %d fits at %s" % [bar.fitted().rung, screen])
		rungs.append(bar.fitted().rung)
		_fits(bar, "at %s" % screen)
	# S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens: at 800×480 the 364-unit
	# room takes the blocked and the done as tiles (rung 2, 290) where it took the cards' rung 3.
	_eq(rungs, [4, 4, 2, 1], "faces at 480 and 640, the blocked and the done named at 800, every card at 1920")
	_done(office)


## Twelve blocked, 34 done, 56 working, 78 idle and 999 panes: on the
## narrowest bar the strip folds them down to the last rung and every agent is
## still counted, as a face or in a fold's number, inside the strip; on the
## widest the same, with more of them as faces.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_a_crowded_bar_keeps_every_agent_counted() -> void:
	var hud := await _bare_hud(Vector2(480, 320))
	var model := _crowd(
		{
			PortraitBarModel.Group.BLOCKED: 12,
			PortraitBarModel.Group.DONE: 34,
			PortraitBarModel.Group.WORKING: 56,
			PortraitBarModel.Group.IDLE: 78
		}
	)
	hud.bar.show_portraits(model, _totals(1, 999))
	hud.bar.show_waits({_crowd_key(PortraitBarModel.Group.BLOCKED, 0): "1h 05m+"})
	await _frames(2)
	var bar := hud.bar
	_eq(bar.fitted().rung, PortraitBarModel.LAST_RUNG, "the last rung at 480")
	_eq(_shown_and_folded(bar), [12, 34, 56, 78], "every agent counted at 480")
	_eq(bar.fold_of(PortraitBarModel.Group.IDLE).count_text(), "+78", "the idle tally says all of them")
	_fits(bar, "crowded at 480")
	var faces := bar.cards().size()
	hud.fit(Vector2(1920, 480))
	await _frames(2)
	_eq(_shown_and_folded(bar), [12, 34, 56, 78], "every agent counted at 1920")
	_check(bar.cards().size() > faces, "more of them shown at 1920: %d" % bar.cards().size())
	# S3 TILES (2026-10-28): the count names the machines first.
	_eq(_panes_text(bar), "1 machine · 999 panes", "and the panes")
	var panes: Button = bar.get_node("%Panes")
	_check(_fits_label_button(panes), "whole")
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
	for manifest: String in [MANIFESTS[0], _second_pack()]:
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


## Resting the pointer on the status line says how each machine answers and
## how long ago it was last heard from; a dropped one says OFFLINE, and when.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters; the
## MACHINES counter's hover is the status line's.
func test_hovering_the_status_line_says_how_each_machine_answers() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var status := _status_label(bar)
	await _hover(status)
	_eq(root.gui_get_hovered_control(), bar, "the pointer is over the bar's status line")
	var tip := bar.get_tooltip(bar.get_local_mouse_position())
	_check(tip.begins_with("Local · LIVE · last snapshot "), "live, heard from: " + tip)
	_check(tip.ends_with(" ago"), "and how long ago: " + tip)
	# The bar's tooltip_text is empty: what shows is what _get_tooltip() writes.
	var delay: float = ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)
	await _wait_seconds(delay + 0.7)
	var popups := _tooltips_shown()
	var shown := false
	for text in popups:
		shown = shown or text.begins_with("Local · LIVE · last snapshot ")
	_check(shown, "the tooltip really shows it: " + str(popups))
	_set_online(office, false)
	await _frames(1)
	tip = bar.get_tooltip(bar.get_local_mouse_position())
	_check(tip.begins_with("Local · OFFLINE · last snapshot "), "dropped, still when it was last heard: " + tip)
	_check(tip.ends_with(" ago"), "a time, not never: " + tip)
	var wordmark: Control = bar.get_node("%Wordmark")
	await _hover(wordmark)
	_eq(bar.get_tooltip(bar.get_local_mouse_position()), "", "elsewhere on the bar, no tooltip")
	_done(office)


## A blocked card's hover says its whole name, provider, the pack's word for
## the state and how long it has waited (a start never seen: the time the
## state log saw, with `+`, as the OVERVIEW's FOR says it), and its space and
## tab; a done face says no wait. A fold names who is in it and where; the
## agent still launching (data:p2) is in none.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_hovering_a_card_or_a_fold_says_who_and_where() -> void:
	var office := await _live_office()
	# web:p1 blocked from now; infra:p1 was so from the first snapshot.
	_feed(office, _with(fixture, "web:p1", {"agent_status": "working"}))
	_feed(office, fixture)
	await _wait_seconds(1.2)
	await _text_tick()
	var bar := office.hud.bar
	var web := await _tip_of_card(office, "web:p1")
	var infra := await _tip_of_card(office, "infra:p1")
	var web_pane := office.frame.pane(_pane("web:p1"))
	_eq(web.size(), 3, "three lines: " + str(web))
	if web.size() == 3:
		_eq(web[0], web_pane.name, "its whole name")
		var blocked := CardDetails.caption_of(office.art, ArtContract.STATE_BLOCKED)
		_check(web[1].begins_with("CLAUDE · %s · " % blocked) and web[1].ends_with("s"), "timed: " + web[1])
		_check(not web[1].ends_with("s+"), "its start seen: " + web[1])
		_eq(web[2], "web / ui", "its space and tab")
	_check(infra.size() == 3 and infra[1].ends_with("s+"), "infra's start never seen: at least: " + str(infra))
	var done := await _tip_of_card(office, "web:p2")
	_check(
		done.size() == 3 and done[1] == "CODEX · " + CardDetails.caption_of(office.art, &"done"), "no wait: %s" % [done]
	)
	await _hover(bar.fold_of(PortraitBarModel.Group.WORKING))
	var working := bar.fold_of(PortraitBarModel.Group.WORKING).get_tooltip(Vector2.ZERO).split("\n")
	var names := PackedStringArray()
	for pane_id: String in ["api:p1", "api:p4", "data:p1"]:
		var pane := office.frame.pane(_pane(pane_id))
		names.append("%s · %s" % [pane.name, pane.workspace_label])
	_eq(working, names, "the working fold names who and where")
	await _hover(bar.fold_of(PortraitBarModel.Group.IDLE))
	var idle := bar.fold_of(PortraitBarModel.Group.IDLE).get_tooltip(Vector2.ZERO).split("\n")
	_eq(idle.size(), 2, "the launching data:p2 is not idle yet: " + str(idle))
	_check(not idle[0].contains("数据"), "api's and infra's idle only: " + str(idle))
	_done(office)


## A real click on a blocked card picks it, shows its floor and brings its
## desk on screen, as a row of the list does; the leftmost card is whom `N`
## picks first: the cards stand in the order `N` walks the blocked in.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters; a card
## click selects (the list's path), it does not walk.
func test_a_click_on_a_blocked_card_picks_it_and_the_first_is_ns() -> void:
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
	var bar := office.hud.bar
	var order: Array[String] = []
	for index in 2:
		order.append(bar.cards()[index].key)
	_eq(order, [_pane("infra:p1"), _pane("web:p1")], "longest wait first")
	for key in order:
		await _press(bar.card_for(key))
		await _frames(3)
		_eq(office.picked_key, key, "a click picks %s" % key)
		var at := [office.navigator.shown_key, office.navigator.current_zone(office.frame)]
		_eq(at, [LOCAL, office.frame.zone_of(key)], "the map of %s, its zone current" % key)
		_check(office.hud.world_rect().has_point(_desk_point(office, key)), "and brings its desk on screen")
		_check(not office.hud.inspector.answering(), "and only picks")
	office.picked_key = ""
	await _office_key(office, KEY_N)
	_eq(office.picked_key, order[0], "`N` goes first to the leftmost card")
	_done(office)


## A done face picks its agent and only picks: no answer mode, no card opened
## up. The oldest UNREAD stands first.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_a_click_on_a_done_card_only_picks() -> void:
	var office := await _live_office()
	var both_working := _with(
		_with(fixture, "web:p2", {"agent_status": "working"}), "infra:p2", {"agent_status": "working"}
	)
	_feed(office, both_working)
	_feed(office, _with(fixture, "web:p2", {"agent_status": "working"}))
	OS.delay_msec(20)
	_feed(office, fixture)
	await _frames(1)
	var bar := office.hud.bar
	var done := bar.portraits().of_group(PortraitBarModel.Group.DONE)
	_eq(
		done.map(func(card: PortraitBarModel.Card) -> String: return card.key),
		[_pane("infra:p2"), _pane("web:p2")],
		"the one UNREAD longest first"
	)
	await _press(bar.card_for(_pane("infra:p2")))
	await _frames(3)
	_eq(office.picked_key, _pane("infra:p2"), "a click picks it")
	var at := [office.navigator.shown_key, office.navigator.current_zone(office.frame)]
	_eq(at, [LOCAL, _floor("infra")], "on its machine's map, its zone current")
	_check(not office.hud.inspector.answering(), "not answering")
	_check(not office.hud.card_expanded(), "and no card opened up for it")
	await _press(bar.card_for(_pane("web:p2")))
	await _frames(3)
	_eq(office.picked_key, _pane("web:p2"), "the other face the other")
	_done(office)


## The working fold opens the OVERVIEW on WORKING, and reads pressed, as
## `13 panes` does; under it the idle fold sets IDLE and takes the press; the
## same fold again is ALL and nobody reads pressed; `13 panes` closes it. The
## agent list's filter is left as it was.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters; a fold
## opens the OVERVIEW on its state instead of filtering the list.
func test_a_click_on_a_fold_opens_the_overview_on_its_state() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var hud := office.hud
	await _press(bar.fold_of(PortraitBarModel.Group.WORKING))
	await _frames(2)
	_check(hud.overview_open(), "the working fold opens the OVERVIEW")
	_eq(hud.overview.filter(), OverviewModel.Filter.WORKING, "on WORKING")
	_eq(
		bar.fold_of(PortraitBarModel.Group.WORKING).theme_type_variation,
		&"PortraitFoldWorkingOn",
		"the fold reads pressed"
	)
	_eq((bar.get_node("%Panes") as Button).theme_type_variation, &"BarLineOn", "and so does `13 panes`")
	await _press(bar.fold_of(PortraitBarModel.Group.IDLE))
	await _frames(2)
	_eq(hud.overview.filter(), OverviewModel.Filter.IDLE, "the idle fold sets IDLE")
	_eq(bar.fold_of(PortraitBarModel.Group.IDLE).theme_type_variation, &"PortraitFoldIdleOn", "and takes the press")
	_eq(bar.fold_of(PortraitBarModel.Group.WORKING).theme_type_variation, &"PortraitFoldWorking", "working lets go")
	await _press(bar.fold_of(PortraitBarModel.Group.IDLE))
	await _frames(2)
	_eq(hud.overview.filter(), OverviewModel.Filter.ALL, "again: ALL")
	_check(not bar.folds().any(func(fold: PortraitFold) -> bool: return fold.is_on()), "no fold pressed")
	_check(hud.overview_open(), "and the OVERVIEW stays")
	await _press(_panes_button(bar))
	await _frames(2)
	_check(not hud.overview_open(), "`13 panes` closes it")
	_eq((bar.get_node("%Panes") as Button).theme_type_variation, &"BarLine", "and lets go")
	# S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: "the list was never filtered" went with the list.
	_done(office)


## A fold click opens no panel: the world keeps its room and the bottom panel
## its form and page; once the OVERVIEW closes the floor is the one it was, not
## planned again.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the drawer and the list's filter and keyboard
## went with it; that the bottom panel keeps its page (the one other panel a fold could have moved) is checked instead.
func test_a_fold_click_moves_no_panel_and_plans_nothing() -> void:
	var office := await _live_office()
	var hud := office.hud
	var bar := hud.bar
	var page := hud.page()
	var room := hud.world_rect()
	var plan := office.floor_view.plan
	var ids := _world_ids(office)
	var compact := hud.card_compact()
	await _press(bar.fold_of(PortraitBarModel.Group.IDLE))
	await _frames(2)
	_check(hud.overview_open(), "the OVERVIEW opens")
	_eq(hud.world_rect(), room, "the world keeps its room")
	_eq(hud.card_compact(), compact, "the bottom panel stays as it was")
	_eq(hud.page(), page, "on its page")
	await _press(_panes_button(bar))
	await _frames(2)
	_check(not hud.overview_open(), "closed again")
	_check(office.floor_view.plan == plan, "the floor's plan is the one it had")
	_eq(_world_ids(office), ids, "and the world the nodes it had")
	_done(office)


## The showroom's top bar is the office's own: its pack name and its status
## fit the right-hand lines in both packs (the shipped one and a second), with no ellipsis.
func test_the_showroom_status_fits_the_lines() -> void:
	root.size = SHOWROOM_SCREEN
	for manifest: String in [MANIFESTS[0], _second_pack()]:
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
	root.size = SCREEN


## Each blocked card writes its wait and grows on attention's beat, with `+`
## while its start is unknown (it may be longer than watched); the leftmost
## card's is the longest. Nobody blocked, no wait anywhere.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters; each
## blocked card says its own wait where BLOCKED said the `max`.
func test_a_blocked_cards_wait_ticks_on_the_attention_beat() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	await _text_tick()
	# Both blocked since before the first snapshot: the stretch watched, `+`.
	for pane_id: String in ["web:p1", "infra:p1"]:
		var first := _wait_of(bar, pane_id)
		_check(first.ends_with("s+"), "%s since before the office looked: `%s`" % [pane_id, first])
	await _known_blocked(office)
	await _text_tick()
	var web := _wait_of(bar, "web:p1")
	_check(web.ends_with("s") and not web.ends_with("+"), "web:p1's start is known: `%s`" % web)
	_check(_wait_of(bar, "infra:p1").ends_with("s+"), "infra:p1's still unknown")
	_eq(bar.cards()[0].key, _pane("infra:p1"), "the unknown start leftmost: the old `max`")
	_check(_label(bar.card_for(_pane("web:p1")), "%Wait").visible, "shown beside the space")
	var before := int(web.trim_suffix("s"))
	await _wait_seconds(1.2)
	await _text_tick()
	_check(int(_wait_of(bar, "web:p1").trim_suffix("s")) > before, "and grows: `%s`" % _wait_of(bar, "web:p1"))
	var nobody := _with(_with(fixture, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "working"})
	_feed(office, nobody)
	await _text_tick()
	_eq(bar.count(PortraitBarModel.Group.BLOCKED), 0, "nobody blocked")
	for card in bar.cards():
		_check(not _label(card, "%Wait").visible, "%s says no wait" % card.key)
	_done(office)


## A blocked card, its tooltip and the OVERVIEW's FOR say one number for the
## same pane: web:p1 and infra:p1 were blocked before the first snapshot, so
## all three say the stretch this office watched, with `+`. On d48c61e the
## `max` said nothing and the hover `?` while the overview said `Ns+`.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_a_card_its_tooltip_and_the_overview_say_the_same_wait() -> void:
	var office := await _live_office()
	await _wait_seconds(1.2)
	office.open_overview()
	await _text_tick()
	office.refresh()
	await _frames(1)
	var bar := office.hud.bar
	for pane_id: String in ["web:p1", "infra:p1"]:
		var key := _pane(pane_id)
		var line := office.hud.overview.line_for(key)
		_check(line != null, "%s has an overview row" % key)
		if line == null:
			continue
		var said := (line.get_node("%For") as Label).text
		_check(said.ends_with("s+"), "%s: FOR `%s`, at least" % [key, said])
		var card := _wait_of(bar, pane_id)
		_check(card.ends_with("s+") and int(card.trim_suffix("s+")) >= 1, "the card says a time too: `%s`" % card)
		_check(
			absi(int(card.trim_suffix("s+")) - int(said.trim_suffix("s+"))) <= 1, "`%s` is FOR's `%s`" % [card, said]
		)
		var tip := bar.card_for(key).get_tooltip(Vector2.ZERO).split("\n")
		_check(tip.size() > 1 and tip[1].ends_with(" · " + card), "the hover says the same: %s" % [tip])
		_check(not "?" in tip[1], "and times it")
	office.close_overview()
	_done(office)


## `--read-only` shows the same cards, and a click on a blocked one only picks.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_read_only_shows_the_same_cards_and_a_click_only_picks() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_check(bar.status_line().begins_with("LIVE / READ ONLY"), "read only: " + bar.status_line())
	_eq(_counts(bar), FIXTURE_COUNTS, "the same agents")
	await _press(bar.cards()[0])
	await _frames(3)
	_check(not office.picked_key.is_empty(), "the click picks somebody blocked")
	_eq(office.frame.pane(office.picked_key).state, "blocked", "blocked")
	_check(not office.hud.inspector.answering(), "and never answers")
	_check(office.fleet.read_log().is_empty(), "nothing was read")
	_check(office.fleet.write_log().is_empty(), "nothing was written")
	_done(office)


## A pane no floor seats still has its card, last among the blocked (no start
## to time), with a space it cannot name; a dropped machine's panes have none,
## nor are its panes counted.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_an_unseated_pane_has_a_card_and_a_dropped_machine_none() -> void:
	var loose := _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	var states := PackedStringArray(["working", "blocked", "done", "idle", "unknown"])
	var machines: Array[MachineView] = [
		MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(loose), false),
		MachineView.new("socket:bee", "bee", HerdrSnapshot.from_wire(fixture), true),
	]
	var frame := OfficeProjection.frame(machines, states)
	var totals := OfficeTotals.of(frame, [])
	_eq([totals.machines_live, totals.machines_total], [1, 2], "one of two answers")
	_eq(totals.panes, 13, "bee's thirteen panes are not counted")
	var model := PortraitBarModel.of(frame, "")
	var blocked := model.of_group(PortraitBarModel.Group.BLOCKED)
	_eq(
		blocked.map(func(card: PortraitBarModel.Card) -> String: return card.key),
		[_pane("web:p1"), _pane("infra:p1"), _pane("notes:p1")],
		"Local's two, then the pane no floor seats; nothing of bee's"
	)
	_eq([blocked[2].place, blocked[2].zone_key], ["?", ""], "unseated: no space to name, no zone")
	_check(model.cards.all(func(card: PortraitBarModel.Card) -> bool: return card.machine == LOCAL), "no bee card")


## The showroom draws its mock as the office draws a map: each of its two
## workspaces a zone (partitions in a y-sorted holder, a sign saying its number
## and label), a measured pod with its tab's name under it. Every station owns one complete generic
## workstation; done workers on both logical rows use its done track, never a
## separately composed paper stack. No extra rig or bystander is constructed.
## Blocked far workers keep their chip, one with a wait and one without.
func test_the_showroom_stands_its_cast_in_zones() -> void:
	root.size = SHOWROOM_SCREEN
	var showroom: Node = (load(SHOWROOM_SCENE) as PackedScene).instantiate()
	root.add_child(showroom)
	await _frames(2)
	var pack: ArtPack = showroom.get("art")
	var sorted: Node2D = showroom.get("sorted")
	var ground: Node2D = showroom.get("ground")
	_check(sorted != null and sorted.y_sort_enabled, "what stands is under one y-sorted root")
	if pack == null or sorted == null or ground == null:
		showroom.free()
		root.size = SCREEN
		return
	var signs: Array[String] = []
	var pods: Dictionary[String, OfficeTable] = {}
	var stations: Dictionary[String, OfficeStation] = {}
	var holders := 0
	for child in sorted.get_children():
		if child is OfficeZoneSign:
			signs.append("%s %s" % [_label(child, "%Number").text, _label(child, "%Title").text])
		elif child is OfficeTable:
			pods[str(child.name)] = child
		elif child is OfficeStation:
			stations[str(child.name)] = child
		elif str(child.name).begins_with("Partitions"):
			holders += 1
			var holder := child as Node2D
			_check(holder.y_sort_enabled, "a zone's partitions sort by their own feet")
			_check(
				holder.get_child_count() > 10,
				"posts, side runs, corners and a bottom run: %d" % holder.get_child_count()
			)
	signs.sort()
	_eq(signs, ["1 API", "2 WEB"] as Array[String], "each zone's sign says its number and label")
	_eq(holders, 2, "and each stands in its partitions")
	_eq(pods.keys(), ["API", "WEB"], "a pod in each")
	var named: Array[String] = []
	for label in ground.find_children("*", "Label", true, false):
		named.append((label as Label).text)
	_check(named.has("MAIN") and named.has("FEAT/UI"), "each pod's tab is named under it: %s" % [named])
	_check(not named.has("API") and not named.has("WEB"), "no title on a row wall any more: %s" % [named])
	var api: OfficeTable = pods.get("API")
	var web: OfficeTable = pods.get("WEB")
	if api == null or web == null:
		_check(false, "two pods: %s" % [pods.keys()])
		showroom.free()
		root.size = SCREEN
		return
	var measured := OfficeTable.measure(4)
	for pod: OfficeTable in [api, web]:
		_eq(pod.width, measured.table_width, "%s: the current measured width" % pod.name)
		_eq(pod.columns, measured.columns, "%s: the canonical seat columns" % pod.name)
	_eq(stations.size(), 16, "two rows of four complete stations on each pod")
	var workers := 0
	var vacant := 0
	var shells := 0
	for station: OfficeStation in stations.values():
		var actor := station.actor()
		if station.vacant:
			vacant += 1
		elif actor == null:
			shells += 1
		else:
			workers += 1
			_eq(actor.art, pack.workstation, "%s: the generic image family" % station.name)
			_eq(actor.find_children("*", "Sprite2D", true, false).size(), 1, "%s: one complete image" % station.name)
	_eq([workers, shells, vacant], [11, 1, 4], "agents, a shell and the four empty slots")
	var rigs := showroom.find_children("*", "", true, false).filter(
		func(node: Node) -> bool: return node is PixelPerson or node is PixelPortrait
	)
	_eq(rigs.size(), 0, "no separate body, customized portrait or legacy bystander")
	for seat: String in ["WEBFar0", "APINear1", "APINear3"]:
		var station: OfficeStation = stations.get(seat)
		_check(station != null and station.actor() != null, seat + ": a done worker")
		if station != null and station.actor() != null:
			_eq(station.actor().animation, &"done", seat + ": the complete-image done track")
	var working: OfficeStation = stations.get("APIFar0")
	_check(working != null and working.actor() != null, "a working seat")
	if working != null and working.actor() != null:
		_eq(working.actor().animation, &"working", "working uses its own complete-image track")
	var waited: OfficeStation = stations.get("APIFar1")
	var unseen: OfficeStation = stations.get("WEBFar1")
	_check(waited != null and unseen != null, "the blocked far seats: %s" % [stations.keys()])
	if waited != null and unseen != null:
		_check(waited.chip().visible and waited.chip().framed(), "API's blocked far worker under a chip with its wait")
		_check(
			unseen.chip().visible and not unseen.chip().framed(),
			"WEB's under the badge alone: its start was never seen"
		)
	showroom.free()
	root.size = SCREEN


## The old 224-wide zones could not enclose the new 384-wide pods. At the
## capture's logical size, each whole drawing, focus frame, chip and name row
## stays inside its own carpet; signs, tab labels, partitions, HUD and samples
## keep separate bands. Complete images and portraits use only family density.
func test_the_showroom_fits_its_measured_pods_and_samples() -> void:
	root.size = SHOWROOM_SCREEN
	var showroom: Node = (load(SHOWROOM_SCENE) as PackedScene).instantiate()
	root.add_child(showroom)
	await _frames(2)
	var pack: ArtPack = showroom.get("art")
	var sorted: Node2D = showroom.get("sorted")
	var ground: Node2D = showroom.get("ground")
	var hud: OfficeHud = null
	for child in showroom.get_children():
		if child is OfficeHud:
			hud = child as OfficeHud
	_check(pack != null and sorted != null and ground != null and hud != null, "the showroom is ready")
	if pack == null or sorted == null or ground == null or hud == null:
		showroom.free()
		root.size = SCREEN
		return
	var canvas := Rect2(Vector2.ZERO, Vector2(SHOWROOM_SCREEN))
	var staff := hud.placed(hud.staff)
	var bar := hud.placed(hud.bar)
	_check(canvas.encloses(staff) and canvas.encloses(bar), "both HUD bands fit the existing capture")
	var zones: Array[Rect2] = []
	for space: String in ["API", "WEB"]:
		var pod: OfficeTable = sorted.get_node(NodePath(space))
		var carpet: NinePatchRect = ground.get_node(NodePath("Carpet" + space))
		var title: Label = ground.get_node(NodePath("Tab" + space))
		var board: OfficeZoneSign = sorted.get_node(NodePath("Sign" + space))
		var lies := carpet.get_global_rect()
		var thick := OfficeShell.PARTITION_THICKNESS
		var zone := lies.grow_individual(thick, 0, thick, thick)
		var drawing := pod.geometry.render_rect.grow(OfficeTable.FRAME_OUTSIDE)
		drawing.position += pod.global_position
		_check(canvas.encloses(zone), "%s: its whole zone is on screen: %s" % [space, zone])
		_check(lies.encloses(drawing), "%s: its carpet encloses the measured image and frame" % space)
		_check(not zone.intersects(staff) and not zone.intersects(bar), "%s: neither HUD band covers it" % space)
		for other in zones:
			_check(not zone.intersects(other), "%s: separate zones, no overlapping pods" % space)
		zones.append(zone)
		var posted := sorted.global_transform * board.drawn_rect()
		_check(canvas.encloses(posted) and not bar.intersects(posted), "%s: the sign clears the bar" % space)
		_check(posted.end.y <= drawing.position.y, "%s: the sign is above the complete workstation" % space)
		var named := title.get_global_rect()
		_check(lies.encloses(named), "%s: the tab name stays inside its carpet" % space)
		_check(named.position.y >= drawing.end.y, "%s: the tab name is below the selection frame" % space)
		_check(
			named.end.y <= zone.end.y - OfficeShell.PARTITION_DRAW,
			"%s: the lower partition covers neither the pod nor its tab name" % space
		)
		for child in sorted.get_children():
			if not child is OfficeStation:
				continue
			var station: OfficeStation = child
			if station.table != pod:
				continue
			_check(drawing.encloses(station.target_rect()), "%s: the complete image fits" % station.name)
			var plate := station.plate_row()
			plate.position += station.global_position
			_check(drawing.encloses(plate), "%s: showing its name cannot spill out" % station.name)
			if station.chip().visible:
				_check(drawing.encloses(station.chip_rect()), "%s: its chip fits too" % station.name)
			var images := 0
			for node in station.find_children("*", "Sprite2D", true, false):
				var sprite := node as Sprite2D
				if sprite.texture not in [pack.workstation.sheet_texture(), pack.workstation.empty_texture()]:
					continue
				images += 1
				_eq(sprite.global_scale, pack.workstation.unit_scale(), "%s: native family density" % station.name)
				var pixels := sprite.get_global_transform() * sprite.get_rect()
				_check(drawing.encloses(pixels), "%s: the actual sprite fits, not just its feet" % station.name)
			_eq(images, 1, "%s: one complete workstation, occupied or empty" % station.name)
	var strip: Control = showroom.get_node("StateStrip")
	var samples := strip.get_global_rect()
	_check(canvas.encloses(samples), "the state samples and legend fit the capture")
	_check(staff.end.y < samples.position.y, "the compact staff panel stops above the samples")
	for zone in zones:
		_check(not samples.intersects(zone), "the samples never cover a zone")
	var portraits: Array[Rect2] = []
	for node in strip.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite.texture != pack.workstation.portrait_texture():
			continue
		var pixels := sprite.get_global_transform() * sprite.get_rect()
		_check(samples.encloses(pixels), "the sample portrait stays whole inside its panel")
		_eq(pixels.size, Vector2(pack.workstation.portrait_size), "the native 40x40 portrait, no extra scaling")
		_eq(sprite.global_scale, pack.workstation.unit_scale(), "the sample uses only family density")
		for other in portraits:
			_check(not pixels.intersects(other), "portrait samples do not overlap")
		portraits.append(pixels)
	_eq(portraits.size(), ArtContract.STATES.size() + 2, "every state and both overlays have a sample")
	var words: Array[Rect2] = []
	for node in strip.find_children("*", "Label", true, false):
		var label := node as Label
		var said := label.get_global_rect()
		_check(samples.encloses(said), "the sample panel holds its words: " + label.text)
		var face := label.get_theme_font("font")
		var size := label.get_theme_font_size("font_size")
		for line in label.text.split("\n"):
			_check(face.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x, line + " fits")
		for other in words + portraits:
			_check(
				not said.intersects(other), "sample words stay clear of each other and every portrait: " + label.text
			)
		words.append(said)
	showroom.free()
	root.size = SCREEN


## The showroom's top bar shows its own mock: Local's agents in the state the
## mock ledger leaves each in, bee (dropped) with none, its panes not counted;
## the blocked cards name Local's spaces, and the status line's hover says
## Local is live and bee offline. The same numbers the live office's rule
## gives, worked out here from the showroom's own table.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_the_showroom_bar_shows_its_mock_agents() -> void:
	root.size = SHOWROOM_SCREEN
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
	root.add_child(showroom)
	await _frames(2)
	var hud: OfficeHud = null
	for child in showroom.get_children():
		if child is OfficeHud:
			hud = child as OfficeHud
	_check(hud != null, "the showroom has the office's HUD")
	if hud == null:
		showroom.free()
		root.size = SCREEN
		return
	_check(counts.blocked > 0 and counts.idle > 0, "the mock has something to show: %s" % counts)
	var bar := hud.bar
	_eq(_counts(bar), [counts.blocked, counts.done, counts.working, counts.idle], "Local's mock agents, bee dropped")
	# S3 TILES (2026-10-28): the count names the machines first: the showroom's two, bee dropped.
	_eq(_panes_text(bar), "2 machines · %d panes" % panes, "Local's panes")
	for card in bar.portraits().cards:
		_check(card.machine == "local", "%s is Local's" % card.key)
		if card.group == PortraitBarModel.Group.BLOCKED:
			_check(card.place in blocked_spaces, "%s waits in %s" % [card.key, card.place])
	await _hover(_status_label(bar))
	var tip := bar.get_tooltip(bar.get_local_mouse_position()).split("\n")
	_check(_opens_a_line(tip, "Local · LIVE · "), "Local answers: %s" % tip)
	_check(_opens_a_line(tip, "bee · OFFLINE · "), "bee does not: %s" % tip)
	showroom.free()
	root.size = SCREEN


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
	var said := "%s · %s" % [next.name, next.state]
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
	# S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: 800x480
	# docks the panel; it
	# stays as it is, nothing opened.
	_check(office.hud.inspector.docked() and not office.hud.card_expanded(), "and the panel stays as it was")
	_check(not card.answering(), "no answer mode")
	var again := office.navigator.peek_next(office.frame)
	await _office_key(office, KEY_N)
	await _frames(3)
	_eq(office.picked_key, again, "N picks the next")
	_check(not office.hud.card_expanded() and not card.answering(), "and opens nothing either")
	_check(office.fleet.read_log().is_empty(), "nothing was read")
	_check(office.fleet.write_log().is_empty(), "nothing was written")
	_done(office)


## The showroom's NEXT follows the mock its top bar counts, by the office's
## own rule (OfficeNavigator.peek_next()): the blocked before the done, whoever
## has waited longest first (a start at minute 0 is the baseline, never seen,
## so the longest of all); bee dropped, so none of its. `All clear` only when
## the mock has nobody to go to.
func test_the_showroom_next_names_a_mock_pane_that_waits() -> void:
	root.size = SHOWROOM_SCREEN
	var showroom: Node = (load(SHOWROOM_SCENE) as PackedScene).instantiate()
	var source: Script = showroom.get_script()
	var table: Array = source.get_script_constant_map()["MOCK_PANES"]
	var who := ""
	var space := ""
	var state := ""
	var since := 0
	for wanted: String in ["blocked", "done"]:
		for pane: Array in table:
			var steps: Array = pane[6]
			var last: Array = steps.back()
			var minute: int = last[0]
			var began := -1 if minute == 0 else minute
			if pane[0] == "local" and str(last[1]) == wanted and (who.is_empty() or began < since):
				# A mock pane has no title: it is called by its tab (DisplayName).
				who = str(pane[4])
				space = str(pane[3])
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
		root.size = SCREEN
		return
	var card := hud.inspector
	var button: Button = card.get_node("%NextButton")
	_check(card.compact(), "the showroom's staff panel is the compact line")
	# 960 wide: the line has room for the whole sentence; the showroom
	# writes nothing, so it says no verb, only whom and herdr's state.
	_check(
		card.next_text().begins_with("%s · %s @ Local" % [who, state]), "NEXT names the mock's first pane that waits"
	)
	_check(not button.disabled, "and can be pressed")
	_check(
		("\nNext: %s · %s @ Local · %s" % [who, state, space]) in button.tooltip_text,
		"its tooltip says the whole sentence: %s" % button.tooltip_text
	)
	showroom.free()
	root.size = SCREEN


## Panes no floor seats wait in the same order as seated ones
## (OfficeProjection.wait_order()): NEXT, `N` and the blocked cards go to
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
	_check(office.frame.zone_of(_pane("api:p1")).is_empty(), "no floor seats api:p1")
	_check(office.frame.zone_of(_pane("api:p4")).is_empty(), "nor api:p4")
	var first := _with(quiet, "api:p4", {"agent_status": "blocked"})
	_feed(office, first)
	await _wait_seconds(1.2)
	_feed(office, _with(first, "api:p1", {"agent_status": "blocked"}))
	await _frames(2)
	_check(
		office.hud.inspector.next_text().begins_with("tests · "),
		"NEXT names api:p4, blocked longer: " + office.hud.inspector.next_text()
	)
	# S3 BAR-a (2026-10-27): the portrait strip replaces the counters; a
	# click on BLOCKED walked, the blocked cards stand in that order.
	var cards := office.hud.bar.portraits().of_group(PortraitBarModel.Group.BLOCKED)
	_eq(
		cards.map(func(card: PortraitBarModel.Card) -> String: return card.key),
		[_pane("api:p4"), _pane("api:p1")],
		"the blocked cards stand in that order"
	)
	await _press(office.hud.bar.card_for(_pane("api:p4")))
	_eq(office.picked_key, _pane("api:p4"), "and the first card is api:p4")
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
## launches it is a blocked agent. It has a blocked card and WORKING lets it
## go; its card is timed from when the office saw it block, with no `+`; it
## stands after the two whose starts were never seen, and with nobody else
## blocked NEXT names it. herdr finishing the launch while it still asks keeps
## its card, and its wait runs on; herdr launching it again while it asks
## restarts nothing.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_a_blocked_agent_still_launching_has_a_blocked_card_and_is_next() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var asking := _with(fixture, "api:p1", {"agent_status": "blocked", "launch_pending": true})
	_feed(office, asking)
	await _frames(1)
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches api:p1")
	_eq(_counts(bar), [3, 2, 2, 2], "a blocked card for it, WORKING lets it go, IDLE as it was")
	await _wait_seconds(1.2)
	await _text_tick()
	var api := _wait_of(bar, "api:p1")
	_check(api.ends_with("s") and not api.ends_with("s+"), "its own wait, timed from its block, no `+`: " + api)
	var waited := int(api.trim_suffix("s"))
	_check(waited >= 1, "a second has passed: " + api)
	var blocked := bar.portraits().of_group(PortraitBarModel.Group.BLOCKED)
	_eq(blocked[2].key, _pane("api:p1"), "it stands after the two blocked since before the office looked")
	var alone := _with(_with(asking, "web:p1", {"agent_status": "working"}), "infra:p1", {"agent_status": "working"})
	office.picked_key = ""
	_feed(office, alone)
	await _frames(1)
	_check(
		office.hud.inspector.next_text().begins_with("refactor the fleet · blocked"),
		"NEXT names it: " + office.hud.inspector.next_text()
	)
	var since := office.fleet.state_since(LOCAL, "api:p1")
	_check(since > 0.0, "the client times it from its block")
	_feed(office, _with(alone, "api:p1", {"launch_pending": false}))
	await _frames(1)
	_check(not office.frame.pane(_pane("api:p1")).starting, "herdr finished the launch")
	_eq(bar.count(PortraitBarModel.Group.BLOCKED), 1, "still asking: still its card")
	_eq(
		office.fleet.state_since(LOCAL, "api:p1"),
		since,
		"the client's clock runs on: the launch ending is no new state"
	)
	await _text_tick()
	var later := _wait_of(bar, "api:p1")
	_check(int(later.trim_suffix("s")) >= waited, "the wait goes on, not over: %s, %s" % [api, later])
	_feed(office, _with(alone, "api:p1", {"launch_pending": true}))
	await _frames(1)
	_eq(office.fleet.state_since(LOCAL, "api:p1"), since, "herdr launching it again while it asks restarts nothing")
	_eq(bar.count(PortraitBarModel.Group.BLOCKED), 1, "and it still has its card")
	_done(office)


## The other half of the rule: an
## agent herdr is still launching that does not ask has no card, idle or at
## work, and is in no fold.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_a_launching_agent_that_is_not_blocked_has_no_card() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_feed(office, _with(fixture, "api:p2", {"launch_pending": true}))
	await _frames(1)
	_eq(_counts(bar), [2, 2, 3, 1], "an idle agent still launching is not idle yet")
	_check(not _everyone(bar).has(_pane("api:p2")), "and has no card")
	_feed(office, _with(fixture, "api:p1", {"launch_pending": true}))
	await _frames(1)
	_eq(_counts(bar), [2, 2, 2, 2], "nor is a working one at work")
	_check(not _everyone(bar).has(_pane("api:p1")), "no card for it either")
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


## Where titles are allowed `13 panes` and the chime switch stand in the
## bar's row after the strip, left of the lines, inside the bar; on a bar too
## narrow for titles both step aside and the strip takes their room.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_the_chime_switch_and_panes_fit_and_step_aside_on_a_narrow_bar() -> void:
	var office := await _live_office()
	await _known_blocked(office)
	var bar := office.hud.bar
	var switch := _chime_switch(office)
	var panes: Button = bar.get_node("%Panes")
	var strip: Control = bar.get_node("%Strip")
	var content: Control = bar.get_node("%Content")
	var lines: Control = bar.get_node("%Lines")
	for width: float in [480.0, office.hud.bar_titles_from, 800.0, 960.0, 1920.0]:
		var screen := Vector2(width, 480.0 if width > 480.0 else 320.0)
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var where := "at %s" % screen
		_fits(bar, where)
		if width < office.hud.bar_titles_from:
			_check(not switch.visible and not panes.visible, "neither below %s" % office.hud.bar_titles_from)
			_eq(strip.get_global_rect().end.x, content.get_global_rect().end.x, "the strip takes their room " + where)
			continue
		_check(switch.visible and panes.visible, "both show " + where)
		var rect := switch.get_global_rect()
		_check(bar.get_global_rect().encloses(rect), "inside the bar " + where)
		_check(rect.end.x <= lines.get_global_rect().position.x, "left of the lines " + where)
		var count := panes.get_global_rect()
		_check(rect.position.x >= count.end.x, "the chime right of `13 panes` " + where)
		_check(count.position.x >= strip.get_global_rect().end.x, "`13 panes` right of the strip " + where)
		_check(rect.size.x >= switch.get_combined_minimum_size().x, "as wide as its words " + where)
		_check(_fits_label_button(panes), "`%s` whole %s" % [panes.text, where])
	_done(office)


## In a window that fills the screen the window's own buttons (macOS: the
## traffic lights) stand over the bar's left end: the wordmark and the strip
## start after the gap and still fit at every width, the strip that much
## narrower, and go back when it closes.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters.
func test_a_title_gap_moves_the_wordmark_and_the_strip_after_it() -> void:
	var hud := await _bare_hud(Vector2(1920, 480))
	var bar := hud.bar
	var wordmark: Control = bar.get_node("%Wordmark")
	var strip: Control = bar.get_node("%Strip")
	var home := wordmark.get_global_rect().position.x
	for width: float in [480.0, 960.0, 1920.0]:
		var screen := Vector2(width, 480.0 if width > 480.0 else 320.0)
		hud.fit(screen)
		bar.set_title_gap(0.0)
		await _frames(2)
		var room := strip.size.x
		bar.set_title_gap(67.0)
		await _frames(2)
		var where := "at %s" % screen
		_eq(bar.title_gap(), 67.0, "the gap is kept " + where)
		_eq(wordmark.get_global_rect().position.x, home + 67.0, "the wordmark starts after it " + where)
		_check(strip.get_global_rect().position.x >= wordmark.get_global_rect().end.x, "the strip after it " + where)
		_eq(strip.size.x, room - 67.0, "the strip gives the gap its room " + where)
		_fits(bar, "after the gap " + where)
	hud.fit(Vector2(1920, 480))
	bar.set_title_gap(0.0)
	await _frames(2)
	_eq(wordmark.get_global_rect().position.x, home, "a closed gap puts the wordmark back")
	_fits(bar, "with no gap at 1920")
	hud.free()


## Only a normal run fills the screen. A capture and a headless run keep the
## window they asked for, `--plain-window` keeps the plain one, an
## always-on-top corner view never covers the screen, and a test office never
## fills whatever its arguments say.
func test_only_a_normal_run_fills_the_screen() -> void:
	var cases: Dictionary[String, bool] = {
		"": true,
		"--plain-window": false,
		"--capture=/tmp/shot.png": false,
		"--window=960x640 --capture=/tmp/shot.png": false,
		"--always-on-top": false,
	}
	for line in cases:
		var given := AppArgs.parse(line.split(" ", false))
		_eq(OfficeWindow.fills_screen(given, false), cases[line], "windowed with `%s`" % line)
		_eq(OfficeWindow.fills_screen(given, true), false, "headless with `%s`" % line)
	var office := await _live_office()
	_eq(office.filled, false, "a test office never fills the screen")
	_eq(office.get_window().extend_to_title, false, "nor draws under the title bar")
	_eq(office.hud.bar.moves_window, false, "so its bar drags nothing")
	_eq(office.hud.bar.title_gap(), 0.0, "and leaves no gap")
	_done(office)


# --- helpers ------------------------------------------------------------------


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _floor(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


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


## Every card and every fold the strip shows inside the strip and the bar,
## right of the whole wordmark and left of `13 panes`, the chime switch and the
## lines; none over another; every card holding its words.
func _fits(bar: OfficeBar, when: String) -> void:
	var lines: Control = bar.get_node("%Lines")
	var wordmark: Control = bar.get_node("%Wordmark")
	var strip := (bar.get_node("%Strip") as Control).get_global_rect()
	var stops: Array[Control] = [bar.get_node("%Panes"), bar.get_node("%Chime"), lines]
	for stop in stops:
		if stop.visible:
			_check(strip.end.x <= stop.get_global_rect().position.x, "the strip left of %s %s" % [stop.name, when])
	_check(strip.position.x >= wordmark.get_global_rect().end.x, "the strip right of the whole wordmark " + when)
	var rects: Array[Rect2] = []
	var items: Array[Control] = []
	items.append_array(bar.cards())
	for fold in bar.folds():
		if fold.visible:
			items.append(fold)
	for item in items:
		var rect := item.get_global_rect()
		var where := "%s %s" % [item.name, when]
		_check(strip.encloses(rect), "inside the strip: %s %s in %s" % [where, rect, strip])
		_check(bar.get_global_rect().encloses(rect), "inside the bar: " + where)
		_check(rect.size.x >= item.get_combined_minimum_size().x, "as wide as it needs: " + where)
		if item is PortraitCard:
			var text: Control = item.get_node("%Text")
			if text.visible:
				_check(rect.encloses(text.get_global_rect()), "%s holds its words" % where)
		for other in rects:
			_check(not rect.intersects(other), "no overlap: " + where)
		rects.append(rect)


## Whether `label`'s text fits its width in its own font, with no ellipsis.
func _fits_label(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x


## Whether `button`'s text fits inside it, past its stylebox's margins.
func _fits_label_button(button: Button) -> bool:
	var font := button.get_theme_font("font")
	var size := button.get_theme_font_size("font_size")
	var box := button.get_theme_stylebox("normal")
	var room := button.size.x - box.get_margin(SIDE_LEFT) - box.get_margin(SIDE_RIGHT)
	return font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room


## How many agents each group holds: blocked, done, working, idle.
func _counts(bar: OfficeBar) -> Array[int]:
	var found: Array[int] = []
	for group in PortraitBarModel.GROUPS:
		found.append(bar.count(group))
	return found


## Every agent the bar was told about, in its drawing order.
func _everyone(bar: OfficeBar) -> Array[String]:
	var found: Array[String] = []
	for card in bar.portraits().cards:
		found.append(card.key)
	return found


## Each group's agents shown as a card or a face plus those its fold counts.
func _shown_and_folded(bar: OfficeBar) -> Array[int]:
	var found: Array[int] = []
	for group in PortraitBarModel.GROUPS:
		var shown := 0
		for card in bar.cards():
			if card.shown_card().group == group:
				shown += 1
		var fold := bar.fold_of(group)
		found.append(shown + (int(fold.count_text().trim_prefix("+")) if fold.visible else 0))
	return found


func _panes_text(bar: OfficeBar) -> String:
	return _panes_button(bar).text


func _panes_button(bar: OfficeBar) -> Button:
	return bar.get_node("%Panes")


func _sorted(keys: Array[String]) -> Array[String]:
	var copy: Array[String] = keys.duplicate()
	copy.sort()
	return copy


func _status_label(bar: OfficeBar) -> Label:
	return bar.get_node("%StatusLine")


## A pane `pane_id`'s card wait, as its %Wait says it; empty for none shown.
func _wait_of(bar: OfficeBar, pane_id: String) -> String:
	var card := bar.card_for(_pane(pane_id))
	if card == null:
		_fail("%s has no card" % pane_id)
		return ""
	var wait := _label(card, "%Wait")
	return wait.text if wait.visible else ""


## A crowd of made-up agents, `counts` of each group.
func _crowd(counts: Dictionary) -> PortraitBarModel:
	var model := PortraitBarModel.new()
	for group in PortraitBarModel.GROUPS:
		var many: int = counts.get(group, 0)
		model.counts[group] = many
		for index in many:
			var card := PortraitBarModel.Card.new()
			card.key = _crowd_key(group, index)
			card.machine = LOCAL
			card.provider = "claude"
			card.name = "agent %d" % index
			card.place = "api"
			card.group = group
			card.state = PortraitBarModel.WORDS[group]
			model.cards.append(card)
	return model


func _crowd_key(group: PortraitBarModel.Group, index: int) -> String:
	return HerdrFleet.pane_key(LOCAL, "%s:p%d" % [PortraitBarModel.WORDS[group], index])


## web:p1 blocked from now on (it was working a snapshot ago): a wait the
## office knows the start of. infra:p1 stays blocked since before it looked.
func _known_blocked(office: OfficeDouble) -> void:
	_feed(office, _with(fixture, "web:p1", {"agent_status": "working"}))
	_feed(office, fixture)
	await _frames(1)


## A real pointer motion onto the middle of `control`.
func _hover(control: Control) -> void:
	var at := _aim(control)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)


## A real left click on `control`, where _aim() points.
func _press(control: Control) -> void:
	var at := _aim(control)
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## Where a real pointer aims at `control`: its middle, but a portrait card's
## face (S3 BAR-b, 2026-10-27: the lower half of a card's words is its place,
## a button of its own that pans to the zone; the face is the card's own).
func _aim(control: Control) -> Vector2:
	if control is PortraitCard:
		var face: Control = control.get_node("%Face")
		return face.get_global_rect().get_center()
	return control.get_global_rect().get_center()


## The tooltip `control` gives with the pointer resting on it, a line each.
func _tip_of(control: Control) -> PackedStringArray:
	await _hover(control)
	_eq(root.gui_get_hovered_control(), control, "the pointer is over %s" % control.name)
	return control.get_tooltip(control.get_local_mouse_position()).split("\n")


## The tooltip of pane `pane_id`'s card, the pointer resting on it.
func _tip_of_card(office: OfficeDouble, pane_id: String) -> PackedStringArray:
	var card := office.hud.bar.card_for(_pane(pane_id))
	if card == null:
		_fail("%s has no card" % pane_id)
		return PackedStringArray()
	return await _tip_of(card)


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


## Totals for the bar's count: `machines` in the fleet, `panes` on the live ones.
func _totals(machines: int, panes: int) -> OfficeTotals:
	var totals := OfficeTotals.new()
	totals.machines_total = machines
	totals.machines_live = machines
	totals.panes = panes
	return totals
