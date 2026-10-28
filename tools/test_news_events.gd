extends "res://tools/office_test_base.gd"
## The NEWS line and the bottom panel's EVENTS page: the state log's events in
## herdr's words, newest first, a click on one picking its pane as the agent
## list does, the ones that cannot be picked disabled, the line's fixed nodes
## and its one fade, the page's rows kept by event id, the panel's tabs, `A`,
## the smallest screen, and none of it sending anything. Clicks and keys go
## through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_news_events.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## Nodes an EVENTS row is made of: the button, the line that holds the rest,
## the time, the icon's slot and badge, who, and what: the state that ended
## and the one that began. 10 -> 8 (S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall
## screens, no drawer tab: the
## row is one line, D-EVROW; its two line boxes went).
const ROW_NODES := 8


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("news-events-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
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
	return "NEWS EVENTS TESTS"


# --- NEWS ---------------------------------------------------------------------


## Three changes are three entries, the newest on the left, in herdr's words:
## a blocked one says no duration, a done or working one how long the state
## before it lasted (`+`: it began before this office watched). The fourth is
## Local coming online; the other four items are hidden. A pane is called by
## its name (DisplayName: here its title) and its space; no path ever shows.
func test_news_shows_the_newest_first_in_herdr_words() -> void:
	# Every pane with a title, a raw title and paths. D1/N2 2026-10-27: the
	# pane's display name, which may come from its terminal title, is how the
	# office names an agent everywhere, so the stripped title may show, as the
	# name and only there; no other terminal text and no path ever does.
	var marked: Dictionary = fixture.duplicate(true)
	for pane: Dictionary in _list(marked, "panes"):
		pane.terminal_title_stripped = "TITLE-SECRET " + str(pane.pane_id)
		pane.terminal_title = "RAW-SECRET " + str(pane.pane_id)
		pane.cwd = "/SECRET/" + str(pane.pane_id)
		pane.foreground_cwd = "/SECRET-FG/" + str(pane.pane_id)
	var office := await _live_office(marked)
	var ledger := office.fleet.state_log()
	var one := _with(marked, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	var two := _with(one, "web:p2", {"agent_status": "working"})
	_feed(office, two)
	_feed(office, _with(two, "api:p4", {"agent_status": "done"}))
	await _frames(2)
	var events := ledger.events()
	_eq(events.size(), 4, "Local online and three changes")
	if events.size() != 4:
		_done(office)
		return
	var news := office.hud.news
	_eq(
		news.item_texts(),
		PackedStringArray(
			[
				"%s TITLE-SECRET api:p4 · api working %s → done" % [_clock(events[3]), _lasted(events[3])],
				"%s TITLE-SECRET web:p2 · web done %s → working" % [_clock(events[2]), _lasted(events[2])],
				"%s TITLE-SECRET api:p1 · api working %s → blocked" % [_clock(events[1]), _lasted(events[1])],
				"%s Local online" % _clock(events[0]),
			]
		),
		"newest first, in herdr's words"
	)
	_check(_lasted(events[3]).ends_with("+"), "the segment before began unwatched: at least that long")
	for index in 4:
		_check(news.item(index).visible, "item %d shows" % index)
	for index in range(4, OfficeNews.ITEMS):
		_check(not news.item(index).visible, "item %d is hidden" % index)
	for index in 4:
		var text := news.item(index).text
		for word: String in ["back to", "went", "UNREAD", "unknown"]:
			_check(not word in text, "no %s: %s" % [word, text])
		# Outside the name it carries, an entry and its tooltip hold no terminal text and no path.
		var outside := text + "\n" + news.item(index).tooltip_text
		outside = outside.replace("TITLE-SECRET api:p4", "").replace("TITLE-SECRET web:p2", "")
		outside = outside.replace("TITLE-SECRET api:p1", "")
		_check(not "SECRET" in outside, "no other terminal text, no path: %s" % outside)
	_done(office)


## A pane's entry calls it by its name, cut to NewsItem.SUBJECT_CLUSTERS whole
## clusters (a long task summary, a CJK one), then its space; the entry's
## tooltip says the whole name. Two claudes in one space are two names.
func test_news_calls_a_pane_by_its_cut_name() -> void:
	var long_title := "✳ Add retry with exponential backoff to every fetch call"
	var titled := _with(fixture, "api:p1", {"terminal_title_stripped": long_title})
	titled = _with(titled, "web:p1", {"terminal_title_stripped": "修复登录重定向并补上回归测试用例以及文档说明和更多更多"})
	var office := await _live_office(titled)
	var one := _with(titled, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	_feed(office, _with(one, "web:p1", {"agent_status": "working"}))
	await _frames(2)
	var news := office.hud.news
	var whole := "Add retry with exponential backoff to every fetch call"
	var cut := TerminalText.clip(whole, NewsItem.SUBJECT_CLUSTERS)
	_eq(cut, "Add retry with exponent…", "cut at whole clusters, the ellipsis one of them")
	_check(
		news.item(1).text.substr(6).begins_with(cut + " · api working "),
		"the name cut, then the space: " + news.item(1).text
	)
	_check(news.item(1).tooltip_text.begins_with(whole + "\n"), "the tooltip says the whole name")
	var cjk := "修复登录重定向并补上回归测试用例以及文档说明和更多更多"
	var cjk_cut := TerminalText.clip(cjk, NewsItem.SUBJECT_CLUSTERS)
	_eq(cjk_cut.length(), NewsItem.SUBJECT_CLUSTERS, "a CJK name keeps as many glyphs")
	_check(news.item(0).text.substr(6).begins_with(cjk_cut + " · web "), "whole glyphs: " + news.item(0).text)
	_check(news.item(0).tooltip_text.begins_with(cjk + "\n"), "and its tooltip the whole of it")
	_done(office)


## A click on an entry picks its pane the way a row of the agent list does:
## the pane is selected, its machine's map shown and panned to its zone, its
## desk in the world's room, and the card is not answering anything.
func test_a_news_click_picks_the_pane_like_the_list() -> void:
	var office := await _live_office()
	var key := _pk("web:p2")
	_feed(office, _with(fixture, "web:p2", {"agent_status": "working"}))
	await _frames(2)
	var start_zone := office.navigator.current_zone(office.frame)
	var item := office.hud.news.item(0)
	_check(item.visible and not item.disabled, "the newest entry can be clicked")
	_eq(item.tooltip_text, "ui\n" + NewsItem.TIP_PICK, "and says whom, whole, and what a click does")
	await _press(item)
	await _frames(3)
	_eq(office.picked_key, key, "the click picks web:p2")
	_eq(office.navigator.shown_key, LOCAL, "its machine's map is shown")
	_eq(office.navigator.current_zone(office.frame), office.frame.zone_of(key), "its zone the current one")
	_check(office.navigator.current_zone(office.frame) != start_zone, "another zone than the one before")
	_check(office.hud.world_rect().has_point(_desk_point(office, key)), "its desk is in the world's room")
	_check(not office.hud.inspector.answering(), "and nothing is being answered")
	_done(office)


## An entry whose pane has gone is disabled and says so, and a real click on it
## picks nothing: no silent click that does nothing without a reason.
func test_a_news_item_for_a_gone_pane_is_disabled_not_silent() -> void:
	var office := await _live_office()
	var working := _with(fixture, "web:p2", {"agent_status": "working"})
	_feed(office, working)
	# Missing from one snapshot is not gone; from a second, it is.
	_feed(office, _without(working, "web:p2"))
	_feed(office, _without(working, "web:p2"))
	await _frames(2)
	var news := office.hud.news
	var closed := news.item(0)
	var changed := news.item(1)
	_eq(closed.text.substr(6), "ui · web pane closed", "the newest says the pane closed")
	var working_event := office.fleet.state_log().events()[1]
	_eq(changed.text.substr(6), "ui · web done %s → working" % _lasted(working_event), "the one before, its change")
	for item: Button in [closed, changed]:
		_check(item.disabled, "%s is disabled" % item.text)
		_eq(item.tooltip_text, "ui\n" + NewsItem.TIP_GONE, "and says why")
	var picked := office.picked_key
	await _press(changed)
	await _frames(2)
	_eq(office.picked_key, picked, "a click on it picks nothing")
	_done(office)


## A machine going offline and coming back is news too, but not a button: a
## machine has no pane to pick.
func test_machine_news_is_not_a_button() -> void:
	var office := await _live_office()
	_set_online(office, false)
	_set_online(office, true)
	await _frames(2)
	var events := office.fleet.state_log().events()
	var news := office.hud.news
	_eq(
		news.item_texts(),
		PackedStringArray(
			[
				"%s Local online" % _clock(events[2]),
				"%s Local offline" % _clock(events[1]),
				"%s Local online" % _clock(events[0]),
			]
		),
		"online, offline, online"
	)
	_eq(news.item(0).tooltip_text, "Local · online", "the machine and its state")
	_eq(news.item(1).tooltip_text, "Local · offline", "the machine and its state")
	for index in 3:
		_check(news.item(index).disabled, "item %d cannot be clicked" % index)
	var picked := office.picked_key
	await _press(news.item(1))
	await _frames(2)
	_eq(office.picked_key, picked, "a click on it picks nothing")
	_done(office)


## The strip is eight items the scene made: ten more events build no node.
## The newest fades in once, and then nothing on it moves.
func test_news_keeps_its_eight_nodes_and_fades_the_newest_once() -> void:
	var office := await _live_office()
	var blocked := _with(fixture, "api:p1", {"agent_status": "blocked"})
	# Once round first: the agent list builds a group's header the first time it shows.
	_feed(office, blocked)
	_feed(office, fixture)
	await _frames(2)
	var nodes := _hud_nodes(office)
	for flap in 5:
		_feed(office, blocked)
		_feed(office, fixture)
	await _frames(2)
	_eq(_hud_nodes(office), nodes, "ten events later, the same HUD nodes")
	_eq(office.hud.news.item_texts().size(), OfficeNews.ITEMS, "eight entries")
	var newest := office.hud.news.item(0)
	await _wait_seconds(OfficeNews.FADE_SECONDS + 0.1)
	_feed(office, blocked)
	_check(newest.modulate.a < 1.0, "a new newest entry starts faded: %.2f" % newest.modulate.a)
	_eq(office.hud.news.item(1).modulate.a, 1.0, "the one before it does not fade")
	await _wait_seconds(OfficeNews.FADE_SECONDS + 0.1)
	_eq(newest.modulate.a, 1.0, "and is whole within %.2f s" % OfficeNews.FADE_SECONDS)
	var still := [newest.position, newest.modulate]
	var moved := false
	for frame_index in 20:
		await process_frame
		moved = moved or [newest.position, newest.modulate] != still
	_check(not moved, "then nothing on it moves")
	office.refresh()
	await _frames(2)
	_eq(newest.modulate.a, 1.0, "a refresh with nothing new fades nothing")
	_done(office)


# --- EVENTS -------------------------------------------------------------------


## A real click on the EVENTS tab shows the page in place of the agent list,
## with a row for every event, newest on top. A new event adds one row and
## touches no other node; the rows before it are the same nodes.
func test_events_tab_lists_the_same_ring_and_keeps_its_rows() -> void:
	var office := await _live_office()
	var one := _with(fixture, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	var two := _with(one, "api:p4", {"agent_status": "done"})
	_feed(office, two)
	await _frames(2)
	var hud := office.hud
	# S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the page
	# is the bottom panel's.
	_eq(hud.page(), OfficeBottomPanel.Page.AGENT, "the panel starts on AGENT")
	_check(hud.event_list.shown_ids().is_empty(), "the hidden page has no rows yet")
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	_eq(hud.page(), OfficeBottomPanel.Page.EVENTS, "the click shows EVENTS")
	_check(hud.event_list.is_visible_in_tree(), "the page is shown")
	_check(not hud.inspector.is_visible_in_tree(), "the card is not")
	_eq(hud.event_list.shown_ids(), _ids_newest_first(office), "a row per event, newest on top")
	var since: Label = hud.event_list.get_node("%Since")
	var opened := office.fleet.state_log().opened_unix
	_eq(since.text, "since %s · 3 events" % OfficeAttention.wall_clock(opened), "since when, and how many")
	var nodes := _hud_nodes(office)
	var old_rows: Array[int] = []
	for id in hud.event_list.shown_ids():
		old_rows.append(hud.event_list.row_for(id).get_instance_id())
	# A change that ends nobody's wait: api:p1 going idle would also give the
	# agent list's History its first line, and its group header nodes of its own.
	_feed(office, _with(two, "api:p2", {"agent_status": "working"}))
	await _frames(2)
	var after := _hud_nodes(office)
	var added := after.filter(func(id: int) -> bool: return not nodes.has(id))
	_eq(added.size(), ROW_NODES, "one row's nodes more")
	_eq(nodes.filter(func(id: int) -> bool: return not after.has(id)), [], "and none fewer")
	var ids := hud.event_list.shown_ids()
	_eq(ids, _ids_newest_first(office), "the new event on top")
	var rows: Node = hud.event_list.get_node("%Rows")
	_eq(rows.get_child(0), hud.event_list.row_for(ids[0]), "its row is the first child")
	var kept: Array[int] = []
	for id in ids.slice(1):
		kept.append(hud.event_list.row_for(id).get_instance_id())
	_eq(kept, old_rows, "the rows before it are the same nodes")
	_done(office)


## A row reads its time, the icon of the state it went to, who and what, on
## one line; a machine's row wears the connected or offline mark.
func test_an_events_row_reads_time_icon_agent_space_and_state() -> void:
	var office := await _live_office()
	var one := _with(fixture, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	var two := _with(one, "api:p4", {"agent_status": "done"})
	_feed(office, two)
	_set_online(office, false)
	_set_online(office, true)
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	var events := office.fleet.state_log().events()
	_eq(events.size(), 5, "online, two changes, offline, online")
	if events.size() != 5:
		_done(office)
		return
	var art := office.art
	var blocked := office.hud.event_list.row_for(events[1].id)
	_eq(_row_label(blocked, "%Time").text, _clock(events[1]), "the time, HH:MM")
	_eq(
		blocked.shown_text(),
		"refactor the fleet · api\nworking %s → blocked" % _lasted(events[1]),
		"who, then the state that ended, how long, and the one that began"
	)
	_eq(blocked.mark(), art.state(ArtContract.STATE_BLOCKED).badge, "the blocked badge")
	var done := office.hud.event_list.row_for(events[2].id)
	_eq(done.shown_text(), "tests · api\nworking %s → done" % _lasted(events[2]), "how long it worked, then done")
	_check(_lasted(events[2]).ends_with("s+"), "seconds, at least: %s" % _lasted(events[2]))
	_eq(done.mark(), art.state(ArtContract.STATE_DONE).badge, "the done badge")
	var offline := office.hud.event_list.row_for(events[3].id)
	_eq(offline.shown_text(), "Local\noffline", "the machine, then offline")
	_eq(offline.mark(), ArtContract.UI_OFFLINE, "the offline mark")
	var online := office.hud.event_list.row_for(events[4].id)
	_eq(online.shown_text(), "Local\nonline", "the machine, then online")
	_eq(online.mark(), ArtContract.UI_CONNECTED, "the connected mark")
	for row: EventRow in [blocked, done, offline, online]:
		var badge := row.icon_badge()
		_check(badge.visible and badge.texture != null, "row %d wears its icon" % row.event_id)
		_eq(badge.position, art.ui_sprite(row.mark()).pivot, "at the pivot its image declares")
		var bounds := row.get_global_rect()
		for part: String in ["%Time", "%Name", "%Ended", "%Now"]:
			var label := _row_label(row, part)
			_check(bounds.encloses(label.get_global_rect()), "row %d holds its %s" % [row.event_id, part])
			_check(
				label.size.y >= label.get_combined_minimum_size().y, "row %d: %s is not squeezed" % [row.event_id, part]
			)
	# data:p2 was still launching (unknown): no state of herdr's ended, so no
	# duration and no arrow, only the state it went to.
	_feed(office, _with(two, "data:p2", {"launch_pending": false}))
	await _frames(2)
	var log_now := office.fleet.state_log().events()
	var launched := log_now[log_now.size() - 1]
	_eq([launched.previous_state, launched.state], [StateLog.UNKNOWN, "idle"], "from unknown to idle")
	_eq(office.hud.event_list.row_for(launched.id).shown_text(), "etl · 数据 pipeline\nidle", "only idle")
	_eq(office.hud.news.item(0).text.substr(6), "etl · 数据 pipeline idle", "and NEWS says the same")
	# An hour-long segment: the state the change went to is never squeezed, and
	# the tooltip keeps all of it.
	var long := StateLog.Event.new()
	long.id = events[1].id
	long.kind = StateLog.Kind.STATE
	long.wall_unix = events[1].wall_unix
	long.pane_key = events[1].pane_key
	long.agent = "claude"
	long.space = "api"
	long.previous_state = "working"
	long.state = "blocked"
	long.for_msec = 3900 * 1000
	long.for_plus = true
	blocked.show_event(long, false, true, false)
	await _frames(2)
	var now: Label = blocked.get_node("%Now")
	var ended: Label = blocked.get_node("%Ended")
	_eq(now.text, "→ blocked", "the new state has a label of its own")
	_check(now.size.x >= now.get_combined_minimum_size().x, "which is never squeezed: %s" % now.size)
	_check(blocked.get_global_rect().encloses(now.get_global_rect()), "and stays inside the row")
	_eq(ended.text, "working 1h 05m+", "the ended part keeps its words")
	var whole := ended.get_theme_font("font").get_string_size(
		ended.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ended.get_theme_font_size("font_size")
	)
	# S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the row
	# is one line across
	# the panel, 700-odd wide, not the drawer's 144: nothing needs cutting short.
	_check(ended.size.x >= whole.x, "and has room for them whole: %.0f of %.0f" % [ended.size.x, whole.x])
	_check(blocked.tooltip_text.begins_with("working 1h 05m+ → blocked\n"), "the tooltip says all of it")
	_done(office)


## A real click on a row picks its pane; a row whose pane has gone is disabled.
func test_an_events_row_click_picks_and_a_gone_one_is_disabled() -> void:
	var office := await _live_office()
	var working := _with(fixture, "web:p2", {"agent_status": "working"})
	_feed(office, working)
	var blocked := _with(working, "infra:p3", {"agent_status": "blocked"})
	_feed(office, blocked)
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	var events := office.fleet.state_log().events()
	var row := office.hud.event_list.row_for(events[events.size() - 1].id)
	_check(not row.disabled, "the newest row can be clicked")
	await _press(row)
	await _frames(3)
	_eq(office.picked_key, _pk("infra:p3"), "the click picks infra:p3")
	_eq(office.navigator.shown_key, LOCAL, "and shows its machine's map")
	_eq(office.navigator.current_zone(office.frame), office.frame.zone_of(_pk("infra:p3")), "its zone the current one")
	_eq(row.theme_type_variation, &"ListRowCurrent", "its row is the current one")
	_feed(office, _without(blocked, "web:p2"))
	_feed(office, _without(blocked, "web:p2"))
	await _frames(2)
	var gone := office.hud.event_list.row_for(events[events.size() - 2].id)
	_check(gone.disabled, "web:p2's row is disabled once its pane has gone")
	_check(gone.tooltip_text.ends_with("\n" + NewsItem.TIP_GONE), "and says why: %s" % gone.tooltip_text.c_escape())
	_check(gone.tooltip_text.begins_with("done "), "after what happened: %s" % gone.tooltip_text.c_escape())
	await _press(gone)
	await _frames(2)
	_eq(office.picked_key, _pk("infra:p3"), "a click on it picks nothing")
	_done(office)


## Every locate counts one navigation (what a pick waiting for a new pane
## records), however it is asked for: `N`, a top-bar card, `›` and `‹` on
## the staff panel's line, a NEWS entry, an EVENTS row and a HISTORY line, each
## a real click or key.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters; a blocked
## card where BLOCKED was.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: a HISTORY line where a row of the agent list
## was (infra:p1 stops waiting, so it has one).
func test_every_locate_counts_one_navigation() -> void:
	var office := await _live_office()
	var navigator := office.navigator
	_feed(office, _with(fixture, "web:p2", {"agent_status": "working"}))
	await _frames(2)
	var revision := navigator.nav_revision
	await _office_key(office, KEY_N)
	_eq(navigator.nav_revision, revision + 1, "`N`: one")
	# S3 BAR-b (2026-10-27): on the card's face; the lower half of its words is its place, which pans.
	await _press(office.hud.bar.cards()[0].get_node("%Face") as Control)
	await _frames(2)
	_eq(navigator.nav_revision, revision + 2, "a blocked card: one")
	var on: Button = office.hud.inspector.get_node("%StepOn")
	var back: Button = office.hud.inspector.get_node("%StepBack")
	_check(on.is_visible_in_tree() and not on.disabled and not back.disabled, "`‹ ›` are on the line")
	await _press(on)
	await _frames(2)
	_eq(navigator.nav_revision, revision + 3, "`›`: one")
	await _press(back)
	await _frames(2)
	_eq(navigator.nav_revision, revision + 4, "`‹`: one")
	await _press(office.hud.news.item(0))
	await _frames(2)
	_eq([office.picked_key, navigator.nav_revision], [_pk("web:p2"), revision + 5], "a NEWS entry: one")
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	var events := office.fleet.state_log().events()
	await _press(office.hud.event_list.row_for(events[events.size() - 1].id))
	await _frames(2)
	_eq(navigator.nav_revision, revision + 6, "an EVENTS row: one")
	var key := _pk("infra:p1")
	_feed(office, _with(_with(fixture, "web:p2", {"agent_status": "working"}), "infra:p1", {"agent_status": "idle"}))
	await _press_tab(office, OfficeBottomPanel.Page.HISTORY)
	var line := office.hud.history_list.row_for(key)
	_check(line != null and not line.disabled, "infra:p1 stopped waiting: a line that picks")
	if line != null:
		await _press(line)
		await _frames(2)
	_eq([office.picked_key, navigator.nav_revision], [key, revision + 7], "a HISTORY line: one")
	_done(office)


## `A` shows the HISTORY page from the EVENTS page, and `A` again the AGENT
## page: the keys take no keyboard of their own. The working fold opens the
## OVERVIEW and leaves the panel on its page.
## S3 BAR-a (2026-10-27): the portrait strip replaces the counters; the
## WORKING counter's list filter is a fold's OVERVIEW now.
## S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the EVENTS
## page is the bottom panel's.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: `A` shows the HISTORY page where it opened the
## drawer and gave the list the keyboard; the drawer's tab, its ▶ and the list's filter went with it (was
## test_a_opens_the_list_and_leaves_the_panels_page).
func test_a_shows_the_history_page_and_a_fold_keeps_the_page() -> void:
	var office := await _live_office()
	var hud := office.hud
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	_eq(hud.page(), OfficeBottomPanel.Page.EVENTS, "on EVENTS")
	await _office_key(office, KEY_A)
	await _frames(2)
	_eq(hud.page(), OfficeBottomPanel.Page.HISTORY, "`A` shows the HISTORY page")
	_check(hud.history_list.is_visible_in_tree() and not hud.event_list.is_visible_in_tree(), "in place of EVENTS")
	_check(not hud.holds_keyboard(), "and takes no keyboard")
	await _office_key(office, KEY_A)
	await _frames(2)
	_eq(hud.page(), OfficeBottomPanel.Page.AGENT, "`A` again: the card")
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	await _press(hud.bar.fold_of(PortraitBarModel.Group.WORKING))
	await _frames(2)
	_check(hud.overview_open(), "the working fold opens the OVERVIEW")
	_eq(hud.page(), OfficeBottomPanel.Page.EVENTS, "the panel stays on EVENTS")
	_done(office)


## The EVENTS page comes into sight by its tab and goes by the AGENT tab. A
## new event while it is out of sight is not laid out until the page can be
## seen, and is there as soon as it shows.
## S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the
## drawer's ▶ and closed strip gave way
## to the panel's tabs.
func test_the_events_page_comes_and_goes_by_its_tab() -> void:
	var office := await _live_office()
	var hud := office.hud
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	_check(hud.event_list.is_visible_in_tree(), "the EVENTS tab shows the page")
	await _press_tab(office, OfficeBottomPanel.Page.AGENT)
	_check(not hud.event_list.is_visible_in_tree(), "the AGENT tab hides it")
	_check(hud.inspector.is_visible_in_tree(), "for the card")
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	await _frames(2)
	var newest := office.fleet.state_log().last_id()
	_check(not hud.event_list.shown_ids().has(newest), "a page out of sight is not laid out")
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	_eq(hud.page(), OfficeBottomPanel.Page.EVENTS, "on EVENTS again")
	_eq(hud.event_list.shown_ids(), _ids_newest_first(office), "the event while it was hidden is there")
	_done(office)


## At the 480x320 minimum the bar and the bottom panel's two rows stand
## apart, and NEWS stands in the panel's top row. More
## entries than NEWS holds: each is shown whole or not at all, never cut (a
## cut `2s+` would read `2s`). Opened up, the panel keeps NEWS in its top row.
## S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: NEWS moved
## into the panel's top row, the
## drawer opens by `A` (no closed tab), the world runs to the right edge.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: no drawer stands beside them any more, so the
## world between them is the whole width (296 -> 456 units) and the drawer's clauses went with it.
func test_the_smallest_screen_keeps_news_staff_and_columns_apart() -> void:
	var office := await _live_office()
	var changes: Dictionary[String, String] = {
		"api:p1": "blocked", "web:p2": "working", "api:p4": "done", "infra:p3": "blocked"
	}
	var changed := fixture
	for pane_id: String in changes:
		changed = _with(changed, pane_id, {"agent_status": changes[pane_id]})
		_feed(office, changed)
	office.test_screen = Vector2(480, 320)
	office.refresh()
	await _frames(3)
	var hud := office.hud
	# S3 SKIN (2026-10-28): the bottom panel wears the wood frame: two rows 54 (was 50), opened 153 (was 149), each
	# world 4 shorter.
	_eq(hud.placed(hud.staff), Rect2(16, 262, 448, 54), "the panel's two rows along the bottom")
	var panels: Array[Rect2] = [hud.placed(hud.bar), hud.placed(hud.staff)]
	for i in panels.size():
		for j in range(i + 1, panels.size()):
			_check(not panels[i].intersects(panels[j]), "%s and %s stand apart" % [panels[i], panels[j]])
	_eq(hud.world_rect(), Rect2(16, 48, 456, 198), "the world between them")
	var strip := hud.news.get_global_rect()
	_check(hud.staff.get_global_rect().encloses(strip), "NEWS inside the panel")
	_check(hud.news.get_combined_minimum_size().x <= strip.size.x, "asking for no more than its width")
	var whole := 0
	var out_of_sight := 0
	for index in OfficeNews.ITEMS:
		var item := hud.news.item(index)
		if not item.visible:
			continue
		var box := item.get_global_rect()
		if strip.encloses(box):
			whole += 1
		elif not strip.intersects(box):
			out_of_sight += 1
		else:
			_fail("entry %d is cut by the line's edge: %s in %s" % [index, box, strip])
	_check(whole >= 1, "the newest entries show whole: %d" % whole)
	_check(out_of_sight >= 1, "and the ones that do not fit are out of sight: %d" % out_of_sight)
	hud.expand_card()
	await _frames(3)
	_check(hud.news.is_visible_in_tree(), "opened up, NEWS stays in the top row")
	_eq(hud.placed(hud.staff), Rect2(16, 163, 448, 153), "the panel at full height")
	_eq(hud.world_rect(), Rect2(16, 48, 456, 99), "the world above it")
	hud.compact_card()
	await _frames(2)
	_eq(hud.placed(hud.staff), Rect2(16, 262, 448, 54), "folded back to its two rows")
	_done(office)


## Read-only, and observation only: the strip has entries, the page has rows,
## and the fleet sent nothing.
func test_read_only_news_and_events_send_nothing() -> void:
	var office := await _live_office()
	_check(office.fleet.read_only(), "this suite runs read-only")
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	await _press(office.hud.news.item(0))
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	await _press(office.hud.event_list.row_for(office.fleet.state_log().last_id()))
	await _frames(2)
	_check(not office.hud.news.item_texts().is_empty(), "NEWS has entries")
	_check(not office.hud.event_list.shown_ids().is_empty(), "EVENTS has rows")
	_eq(office.picked_key, _pk("api:p1"), "the clicks picked")
	_check(office.fleet.read_log().is_empty(), "nothing was read")
	_check(office.fleet.write_log().is_empty(), "nothing was written")
	_done(office)


## A start in a shell is news in herdr's words, the pane called by its name
## throughout (`main · api starting`: its tab, its title being `zsh`), then
## the new agent, still starting, then its state; another terminal says so.
func test_news_says_starting_new_agent_and_new_session() -> void:
	var office := await _live_office()
	var ledger := office.fleet.state_log()
	var before := ledger.events().size()
	_feed(office, _with(fixture, "api:p3", {"launch_pending": true, "name": "claude-1"}))
	_feed(office, _with(fixture, "api:p3", {"agent": "claude", "launch_pending": true, "name": "claude-1"}))
	var ready := {"agent": "claude", "agent_status": "idle", "launch_pending": null, "interactive_ready": true}
	_feed(office, _with(fixture, "api:p3", ready))
	_feed(office, _with(_with(fixture, "api:p3", ready), "api:p3", {"terminal_id": "t-new"}))
	await _frames(2)
	var events: Array[StateLog.Event] = []
	events.assign(ledger.events().slice(before))
	_eq(events.size(), 4, "a launch, a new agent, idle, a new terminal")
	if events.size() != 4:
		_done(office)
		return
	var texts := office.hud.news.item_texts()
	_eq(
		texts.slice(0, 4),
		PackedStringArray(
			[
				"%s main · api idle · new terminal" % _clock(events[3]),
				"%s main · api idle" % _clock(events[2]),
				"%s main · api new agent · starting" % _clock(events[1]),
				"%s main · api starting" % _clock(events[0]),
			]
		),
		"newest first, in herdr's words"
	)
	var session := StateLog.Event.new()
	session.kind = StateLog.Kind.REPLACED
	session.agent = "claude"
	session.space = "api"
	session.state = "working"
	session.changed = StateLog.Changed.SESSION
	_eq(NewsItem.what(session), "working · new session", "another session of the same agent")
	for text in texts:
		_check(not "unknown" in text and not "SHELL" in text, "no unknown, no SHELL: " + text)
	_done(office)


## More EVENTS rows than the page's box show the panel's thin scroll bar
## (PageScroll, never focused) and the wheel scrolls them; every row's
## `→ state` ends 4 units left of the bar, and where it ends with only a few
## rows and no bar: the page keeps the bar's room either way.
## S3 PANEL-a1 (2026-10-27): the docked bottom panel, the 52-unit bar band on tall screens, no drawer tab: the page is
## the panel's,
## its rows one line, so it holds fewer of them (the 116 docked body) and the
## bar shows with as many events as before.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the thin bar's look is `PageScroll` (was
## `DrawerScroll`) and its gap HudTheme.PAGE_BAR_GAP (was DRAWER_BAR_GAP): renamed with the drawer, the same values
## (was test_the_events_page_scrolls_with_the_drawer_bar).
func test_the_events_page_scrolls_with_the_pages_bar() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p1", {"agent_status": "blocked"}))
	await _frames(2)
	await _press_tab(office, OfficeBottomPanel.Page.EVENTS)
	var page := office.hud.event_list
	var scroll: ScrollContainer = page.get_node("%Scroll")
	var bar := scroll.get_v_scroll_bar()
	_check(not bar.visible, "two events fit: no bar")
	var first := page.row_for(office.fleet.state_log().last_id())
	var now_label: Label = first.get_node("%Now")
	var fit := now_label.get_global_rect().end.x
	var room := bar.get_combined_minimum_size().x + HudTheme.PAGE_BAR_GAP
	_check(fit <= scroll.get_global_rect().end.x - room, "the row leaves the bar's room and the gap (%s)" % fit)
	var snapshot := fixture
	for step in 12:
		snapshot = _with(snapshot, "api:p1", {"agent_status": "idle" if step % 2 == 0 else "blocked"})
		_feed(office, snapshot)
	await _frames(2)
	_check(bar.max_value > scroll.size.y, "the rows are taller than the page")
	_check(bar.visible, "so the scroll bar shows")
	_eq(bar.theme_type_variation, &"PageScroll", "the theme's thin one")
	_eq(bar.focus_mode, Control.FOCUS_NONE, "never focused")
	var edge := bar.get_global_rect()
	_check(edge.end.x <= page.get_global_rect().end.x, "inside the page")
	var measured := 0
	for id in page.shown_ids():
		var row := page.row_for(id)
		if not row.get_global_rect().intersects(scroll.get_global_rect()):
			continue
		measured += 1
		var said: Label = row.get_node("%Now")
		var end := said.get_global_rect().end.x
		_check(
			end <= edge.position.x - HudTheme.PAGE_BAR_GAP,
			"row %d's state ends the gap left of the bar (%s, bar at %s)" % [id, end, edge.position.x]
		)
		_eq(end, fit, "and where it ended with no bar")
	_check(measured > 0, "rows were measured")
	var at := scroll.get_global_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = at
	wheel.global_position = at
	await _parsed(wheel)
	await _frames(2)
	_check(scroll.scroll_vertical > 0, "the wheel scrolls the page")
	_done(office)


# --- helpers ------------------------------------------------------------------


func _pk(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _clock(event: StateLog.Event) -> String:
	return OfficeAttention.wall_clock(event.wall_unix)


## How long the segment `event` ended lasted, as the spec writes it.
func _lasted(event: StateLog.Event) -> String:
	return OfficeAttention.format_duration(event.for_msec / 1000.0) + ("+" if event.for_plus else "")


func _ids_newest_first(office: OfficeDouble) -> PackedInt64Array:
	var ids := PackedInt64Array()
	var events := office.fleet.state_log().events()
	for index in range(events.size() - 1, -1, -1):
		ids.append(events[index].id)
	return ids


func _row_label(row: EventRow, path: String) -> Label:
	return row.get_node(path)


## A real left click on the middle of `control`.
func _press(control: Control) -> void:
	await _press_at(control.get_global_rect().get_center())


func _press_at(at: Vector2) -> void:
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## A real click on the bottom panel's tab for `page`.
func _press_tab(office: OfficeDouble, page: OfficeBottomPanel.Page) -> void:
	var tabs := office.hud.staff.tabs
	var rect := tabs.get_tab_rect(page)
	await _press_at(tabs.get_global_rect().position + rect.get_center())
	await _frames(2)


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


## `snapshot` without pane `pane_id`, in its panes, agents and layouts.
func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result
