extends "res://tools/office_test_base.gd"
## Attention through the agent list, by real GUI input against the office: the
## bar's entry and `A`, picking and locating from rows, the rows' local actions
## (snooze, hide, restore) and the history lines. The list replaced the
## attention overlay; these are the overlay's cases, carried over to it.


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for required: String in ["socket", "work"]:
		if not args.has(required):
			print("TEST_HARNESS_ERROR: missing --%s=" % required)
			quit(2)
			return
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("attention-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if not parsed is Dictionary:
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	root.gui_embed_subwindows = true
	await process_frame
	await run_cases()


func _marker() -> String:
	return "ATTENTION INTEGRATION TESTS"


## `A` is the attention entry, as the bar has no Attention button:
## the HUD still counts who needs a human, for the drawer's tab to show.
func test_attention_entry_gives_the_list_the_keyboard() -> void:
	var office := await _listed_office()
	_eq(office.hud.attention_count(), 4, "counting the current attention")
	office.hud.agent_list.set_view(AgentListModel.View.TREE)
	var before := office.hud.world_rect()
	await _key_cycle(KEY_A)
	var list := office.hud.agent_list
	_check(list.has_keyboard(), "a real `A` gives the list the keyboard")
	_eq(list.view, AgentListModel.View.FLAT, "in its flat view, who waits first")
	_eq(list.shown_keys()[0], AgentListModel.FLAT_WAITING, "which opens on the waiting group")
	_eq(office.hud.world_rect(), before, "and moves no office boundary")
	await _key_cycle(KEY_A)
	_check(not list.has_keyboard(), "a second `A` lets it go")
	_done(office)


func test_a_takes_and_gives_back_the_keyboard() -> void:
	var office := await _listed_office()
	var list := office.hud.agent_list
	await _key_cycle(KEY_A)
	_check(list.has_keyboard(), "A gives the list the keyboard")
	await _key_cycle(KEY_A)
	_check(not list.has_keyboard(), "A again lets it go")
	await _key_cycle(KEY_A)
	await _key_cycle(KEY_ESCAPE)
	_check(not list.has_keyboard(), "so does Escape")
	var filter: LineEdit = list.get_node("%Filter")
	await _tap(filter)
	await _key_cycle(KEY_A)
	_eq(filter.text, "a", "in the filter box, A is a letter")
	_check(list.has_keyboard(), "and the list keeps the keyboard")
	await _key_cycle(KEY_ESCAPE)
	_done(office)


func test_list_keeps_the_keyboard_across_a_floor_switch() -> void:
	var office := await _listed_office()
	await _key_cycle(KEY_PAGEUP)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "PageUp switches floor at once")
	await _key_cycle(KEY_A)
	var list := office.hud.agent_list
	_check(list.has_keyboard(), "A reaches the list on the new floor")
	var cursor := list.cursor()
	await _key_cycle(KEY_PAGEUP)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "infra"), "PageUp switches again, list or not")
	_check(list.has_keyboard(), "the switch and its refresh keep the list's keyboard")
	_eq(list.cursor(), cursor, "and its cursor")
	var row := office.hud.floors.row_for(HerdrFleet.pane_key(LOCAL, "infra"))
	_check(not row.disabled, "the floor rows stay enabled")
	_done(office)


func test_list_arrows_move_the_cursor_not_the_camera() -> void:
	var office := await _listed_office()
	var list := office.hud.agent_list
	var top := office.camera.position
	await _key_hold(KEY_DOWN)
	var pan := office.camera.position
	_check(pan.y > top.y, "without the list, a held arrow pans the world down")
	await _key_cycle(KEY_A)
	_check(list.has_keyboard(), "A gives the list the keyboard")
	var cursor := list.cursor()
	var picked := office.picked_key
	await _key_hold(KEY_UP)
	_eq(office.camera.position, pan, "with it, the held arrow leaves the world where it was")
	_check(list.cursor() != cursor, "and moves the list's cursor instead")
	_eq(office.picked_key, picked, "onto its group's header, which picks nothing")
	await _key_cycle(KEY_ESCAPE)
	await _key_hold(KEY_UP)
	_check(office.camera.position.y < pan.y, "once the list lets go, the arrow pans again")
	_done(office)


func test_office_keys_still_work_while_the_list_has_the_keyboard() -> void:
	var office := await _listed_office()
	await _key_cycle(KEY_A)
	var list := office.hud.agent_list
	var selected := office.picked_key
	await _key_cycle(KEY_N)
	_check(office.picked_key != selected and not office.picked_key.is_empty(), "N still walks the queue")
	_check(list.has_keyboard(), "and the list keeps the keyboard")
	_eq(list.cursor(), office.picked_key, "its cursor follows N's pick")
	var night := office.night
	await _key_cycle(KEY_T)
	_check(office.night != night, "T still turns the light over")
	var shown := office.navigator.shown_key
	await _key_cycle(KEY_PAGEDOWN)
	_check(office.navigator.shown_key != shown, "PageDown still changes floor")
	_done(office)


func test_row_click_locates_another_floor() -> void:
	var office := await _listed_office()
	var key := HerdrFleet.pane_key(LOCAL, "web:p1")
	await _click_row(office, key)
	_eq(office.picked_key, key, "a click selects that exact machine and pane")
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "and shows its floor at once")
	var pane_id: Label = office.hud.inspector.get_node("%PaneId")
	_eq(pane_id.text, "web:p1", "the card shows it")
	_eq(office.hud.agent_list.row_for(key).theme_type_variation, &"ListRowCurrent", "and the row is highlighted")
	_done(office)


func test_list_pick_cancels_an_in_progress_world_press() -> void:
	var office := await _listed_office()
	# The desk is brought above the staff panel first, as a click on it needs.
	office.reveal(HerdrFleet.pane_key(LOCAL, "api:p2"))
	await _frames(2)
	var point := _desk_point(office, HerdrFleet.pane_key(LOCAL, "api:p2"))
	_check(office.hud.world_rect().has_point(point), "the pending press is on the exposed world")
	await _parsed(_mouse_button(point, MOUSE_BUTTON_LEFT, true))
	await _key_cycle(KEY_A)
	await _key_cycle(KEY_DOWN)
	var picked := office.picked_key
	_check(picked != HerdrFleet.pane_key(LOCAL, "api:p2"), "the list picked another pane")
	await _key_cycle(KEY_ESCAPE)
	await _parsed(_mouse_button(point, MOUSE_BUTTON_LEFT, false))
	_eq(office.picked_key, picked, "the release cannot revive the press the pick cancelled")
	_done(office)


func test_unplaced_pane_is_listed_and_can_show_details() -> void:
	var snapshot := fixture.duplicate(true)
	var orphan := {
		"pane_id": "orphan",
		"terminal_id": "terminal-orphan",
		"workspace_id": "missing-space",
		"tab_id": "missing-tab",
		"agent": "codex",
		"agent_status": "blocked",
		"label": "Unplaced task"
	}
	_list(snapshot, "panes").append(orphan)
	var office := await _listed_office(snapshot)
	var key := HerdrFleet.pane_key(LOCAL, "orphan")
	var entry := office.hud.agent_list.entry_for(key)
	_check(
		entry != null and entry.parent == AgentListModel.FLAT_WAITING, "a pane no floor seats still waits in the list"
	)
	var item := _for_pane(office, "orphan")
	_check(item != null and item.available, "with details")
	var shown := office.layout_plan().floor_key
	await _click_row(office, key)
	_eq(office.picked_key, key, "a click keeps the unplaced selection")
	_eq(office.layout_plan().floor_key, shown, "and goes nowhere: the floor stays")
	var pane_label: Label = office.hud.inspector.get_node("%PaneId")
	_eq(pane_label.text, "orphan", "the card does not fall back to the focused desk")
	office.hud.agent_list.set_view(AgentListModel.View.TREE)
	_eq(office.hud.agent_list.entry_for(key).parent, "tree:u:" + LOCAL, "the tree says it is not on a floor")
	_done(office)


func test_conflicting_workspace_keeps_details_without_false_navigation() -> void:
	var office := await _listed_office(_with(fixture, "web:p1", {"workspace_id": "infra"}))
	var key := HerdrFleet.pane_key(LOCAL, "web:p1")
	var item := _for_pane(office, "web:p1")
	_check(item != null and item.available, "conflicting ownership keeps its details")
	_eq(office.attention_store.current(Time.get_ticks_msec()).size(), 4, "conflict is counted once with live attention")
	_eq(office.hud.bar.counter(&"blocked").value_text(), "2", "global blocked count still includes the conflict")
	var shown_floor := office.layout_plan().floor_key
	await _click_row(office, key)
	_eq(
		office.layout_plan().floor_key,
		shown_floor,
		"a click goes to neither contradictory workspace: the viewed floor stays"
	)
	_eq(office.picked_key, key, "the unplaced pane is selected")
	var seat: Label = office.hud.inspector.get_node("%Seat")
	_eq(seat.text, "infra / ui", "the card keeps both declared names")
	# While anyone is blocked, N walks the blocked only: the conflict and
	# infra:p1, not the done.
	var visited: Array[String] = []
	for step in 2:
		await _key_cycle(KEY_N)
		_check(not visited.has(office.picked_key), "N visits each blocked pane once")
		visited.append(office.picked_key)
	_eq(office.picked_key, key, "N still reaches the conflict")
	_eq(visited[0], HerdrFleet.pane_key(LOCAL, "infra:p1"), "the other blocked one first")
	await _key_cycle(KEY_N)
	_eq(office.picked_key, visited[0], "and round again among them")
	_feed(office, fixture)
	await _frames(2)
	await _click_row(office, HerdrFleet.pane_key(LOCAL, "api:p1"))
	await _click_row(office, key)
	_eq(office.layout_plan().floor_key, HerdrFleet.pane_key(LOCAL, "web"), "once repaired, a click reaches its floor")
	_eq(seat.text, "web / ui", "world, list and card agree")
	_done(office)


func test_local_hide_and_restore_leave_remote_counts_unchanged() -> void:
	var office := await _listed_office()
	var key := HerdrFleet.pane_key(LOCAL, "web:p1")
	var item := _for_pane(office, "web:p1")
	var bar_before := [office.hud.bar.counter(&"blocked").value_text(), office.hud.bar.counter(&"done").value_text()]
	var counts_before := office.attention_store.current(Time.get_ticks_msec()).size()
	await _row_action(office, key, "Hide")
	_check(item.hidden, "Hide acts on the pane's own record")
	_eq(office.attention_store.current(Time.get_ticks_msec()).size(), counts_before - 1, "hidden locally")
	_eq(office.hud.attention_count(), counts_before - 1, "the HUD's attention count drops")
	var bar_after := [office.hud.bar.counter(&"blocked").value_text(), office.hud.bar.counter(&"done").value_text()]
	_eq(bar_after, bar_before, "herdr's own counts on the bar do not")
	_eq(office.hud.agent_list.entry_for(key).parent, AgentListModel.FLAT_MUTED, "the row steps down")
	await _row_action(office, key, "Restore")
	_check(not item.hidden, "Restore brings the same record back")
	_eq(office.attention_store.current(Time.get_ticks_msec()).size(), counts_before, "without a new event")
	_eq(office.hud.agent_list.entry_for(key).parent, AgentListModel.FLAT_WAITING, "and the row back up")
	_done(office)


func test_snooze_and_resume_from_the_row() -> void:
	var office := await _listed_office()
	var key := HerdrFleet.pane_key(LOCAL, "web:p1")
	var item := _for_pane(office, "web:p1")
	await _row_action(office, key, "Snooze 5 min")
	_check(item.is_snoozed(Time.get_ticks_msec()), "snooze sets a local deadline")
	var note: Label = office.hud.agent_list.row_for(key).get_node("%Tail")
	_eq(note.text, "SNOOZED", "the row says so")
	await _row_action(office, key, "Resume reminder")
	_check(not item.is_snoozed(Time.get_ticks_msec()), "Resume cancels it")
	_done(office)


## History reads the StateLog: a terminal that stopped waiting has a line
## whose View picks its pane; another terminal in the pane inherits no line
## to locate it by.
func test_history_cannot_locate_a_replacement_terminal() -> void:
	var snapshot := _with(fixture, "api:p1", {"agent_status": "blocked"})
	var office := await _listed_office(snapshot)
	var key := HerdrFleet.pane_key(LOCAL, "api:p1")
	var line := "history:" + key
	var idle := _with(snapshot, "api:p1", {"agent_status": "idle"})
	_feed(office, idle)
	await _frames(2)
	await _open_history(office)
	_check(office.hud.agent_list.row_for(line) != null, "the terminal that stopped waiting has a History line")
	await _click_row(office, HerdrFleet.pane_key(LOCAL, "web:p1"))
	_eq(office.picked_key, HerdrFleet.pane_key(LOCAL, "web:p1"), "another pane is picked")
	await _row_action(office, line, "View")
	_eq(office.picked_key, key, "the line's View picks its pane while it is that terminal")
	await _click_row(office, HerdrFleet.pane_key(LOCAL, "web:p1"))
	_feed(office, _with(idle, "api:p1", {"terminal_id": "replacement-terminal"}))
	await _frames(2)
	_check(office.hud.agent_list.entry_for(line) == null, "the replacement terminal inherits no History line")
	_eq(office.picked_key, HerdrFleet.pane_key(LOCAL, "web:p1"), "and nothing selected it")
	_done(office)


func test_offline_items_leave_current_and_reconnect_as_baseline() -> void:
	var office := await _listed_office()
	var initial := office.attention_store.active().size()
	_set_online(office, false)
	_eq(office.attention_store.current(Time.get_ticks_msec()).size(), 0, "offline is not live attention")
	for item in office.attention_store.active():
		_check(item.stale and not item.available, "old records say current state unknown")
	_eq(office.hud.attention_count(), 0, "the HUD counts nobody")
	var list := office.hud.agent_list
	var waiting := 0
	for key in list.shown_keys():
		var line := list.entry_for(key)
		if line.kind == AgentListModel.Kind.PANE and not line.pane.provider.is_empty():
			_eq(line.presence, AgentListModel.Presence.OFFLINE, "every agent row is offline, none idle")
		if line.kind == AgentListModel.Kind.PANE and line.parent == AgentListModel.FLAT_WAITING:
			waiting += 1
	_eq(waiting, 0, "and nobody waits")
	_set_online(office, true)
	_eq(office.attention_store.active().size(), initial, "reconnect does not duplicate the records")
	for item in office.attention_store.current(Time.get_ticks_msec()):
		_check(item.baseline and item.since_msec < 0, "a reconnect does not invent a waiting start")
	_done(office)


func test_unverifiable_reconnect_keeps_old_history_navigation_disabled() -> void:
	var snapshot := _with(fixture, "api:p1", {"terminal_id": "", "agent_status": "blocked"})
	var office := await _listed_office(snapshot)
	var old := _for_pane(office, "api:p1")
	_check(old != null, "unknown identity still has current attention")
	if old == null:
		_done(office)
		return
	var key := HerdrFleet.pane_key(LOCAL, "api:p1")
	await _row_action(office, key, "Hide")
	_set_online(office, false)
	_feed(office, _with(snapshot, "api:p1", {"label": "New worker during gap"}))
	await _frames(2)
	var fresh := _for_pane(office, "api:p1")
	_check(fresh != null and fresh.id != old.id, "the replacement is visible despite the old record's Hide")
	_eq(office.hud.agent_list.entry_for(key).parent, AgentListModel.FLAT_WAITING, "and its row waits again")
	# It stops waiting: a History line, for a pane whose terminal nobody can verify.
	_feed(office, _with(snapshot, "api:p1", {"label": "New worker during gap", "agent_status": "idle"}))
	await _frames(2)
	await _open_history(office)
	var line := "history:" + key
	var row := office.hud.agent_list.row_for(line)
	_check(row != null, "the pane that stopped waiting has a History line")
	if row == null:
		_done(office)
		return
	var name_label: Label = row.get_node("%Detail")
	_check(not name_label.text.contains("New worker during gap"), "the line does not impersonate the replacement")
	var selected := office.picked_key
	await _row_action(office, line, "Details", true)
	_eq(office.picked_key, selected, "an unverifiable terminal cannot be selected from History by real input")
	_done(office)


func test_double_click_picks_and_opens_the_monitor() -> void:
	var office := await _listed_office()
	var key := HerdrFleet.pane_key(LOCAL, "infra:p1")
	var opened: Array[String] = []
	office.hud.monitor_requested.connect(func(pane_key: String) -> void: opened.append(pane_key))
	var row := await _visible_row(office, key)
	await _double(row)
	_eq(opened, [key], "a double-click asks for the monitor, once")
	_eq(office.picked_key, key, "its first click picks the pane")
	_check(office.hud.monitor_open(), "the monitor opens on it")
	_eq(office.hud.monitor.mode(), TerminalMonitor.Mode.VIEW_ONLY, "read-only: view only, it reads nothing")
	_check(not office.hud.inspector.answering(), "and a read-only card offers no answer mode")
	office.hud.close_monitor()
	_done(office)


func test_list_follows_the_office_selection() -> void:
	var office := await _listed_office()
	var key := HerdrFleet.pane_key(LOCAL, "api:p2")
	await _click_desk(office, key)
	_eq(office.picked_key, key, "a desk click picks")
	_eq(office.hud.agent_list.row_for(key).theme_type_variation, &"ListRowCurrent", "the list highlights that row")
	await _key_cycle(KEY_N)
	_eq(office.hud.agent_list.row_for(office.picked_key).theme_type_variation, &"ListRowCurrent", "and N's pick")
	_eq(office.hud.agent_list.row_for(key).theme_type_variation, &"ListRow", "not the old one")
	_done(office)


## A blocked row's wait is the desk badge's: the same clock writes both, in the
## same words, and neither says anything once the machine drops. A done row
## says UNREAD.
func test_blocked_row_shows_the_desks_wait_and_done_says_unread() -> void:
	var blocked_floor := _with(fixture, "api:p2", {"agent_status": "blocked"})
	var office := await _listed_office(blocked_floor)
	var key := HerdrFleet.pane_key(LOCAL, "api:p2")
	_set_wait(office, "api:p2", 742.0)
	await _text_tick()
	var row := await _visible_row(office, key)
	var wait: Label = row.get_node("%Tail")
	_eq(_wait_text(office, key), "12m", "the desk shows its wait")
	_eq(wait.text, "12m", "and the row the same, on the same beat")
	await _tap(row)
	await _frames(2)
	var more: Button = row.get_node("%More")
	_check(more.visible, "the selected waiting row shows its `⋯`")
	var unread := await _visible_row(office, HerdrFleet.pane_key(LOCAL, "web:p2"))
	var note: Label = unread.get_node("%Tail")
	_eq(note.text, "UNREAD", "a done row says UNREAD")
	_set_online(office, false)
	await _text_tick()
	_eq(wait.text, "OFFLINE", "a dropped machine's row shows no wait, it says OFFLINE")
	_check(row.icon_badge().wait == null, "and the attention clock no longer writes into it")
	_eq(row.icon_badge().state, &"", "and its badge rests")
	_eq(office.hud.agent_list.entry_for(key).presence, AgentListModel.Presence.OFFLINE, "it is offline, not blocked")
	_done(office)


## The staff panel's `UNREAD = not yet seen / Not task success.` explains the
## UNREAD state, so it stands only under a done agent's caption: picked by a
## real click on its row, it is there; a blocked or a working one has none. The
## pane's own lines (id, directory, title) stand under a PANE heading of their
## own, apart from the note.
func test_the_unread_note_shows_only_for_a_done_agent() -> void:
	var office := await _listed_office()
	var card := office.hud.inspector
	var footnote: Label = card.get_node("%Footnote")
	var heading := card.get_node_or_null("%PaneHeading") as Label
	var pane_id: Label = card.get_node("%PaneId")
	for step: Array in [["web:p2", true], ["web:p1", false], ["api:p1", false], ["infra:p2", true]]:
		var key := HerdrFleet.pane_key(LOCAL, str(step[0]))
		var done: bool = step[1]
		await _click_row(office, key)
		await _frames(2)
		_eq(office.picked_key, key, "a row click picks " + key)
		# The panel is one line until opened: a real click on its `Open`.
		var open: Control = card.get_node("%CompactOpen")
		await _tap(open)
		await _frames(2)
		_check(not office.hud.card_compact(), "`Open` opens the panel for " + key)
		_eq(footnote.is_visible_in_tree(), done, "the UNREAD note under %s: %s" % [key, done])
		if done:
			_eq(footnote.text, "UNREAD = not yet seen\nNot task success.", "in its words")
			_check(card.get_global_rect().encloses(footnote.get_global_rect()), "inside the panel")
		_check(heading != null and heading.is_visible_in_tree(), "the pane's lines have their heading")
		if heading != null:
			_eq(heading.text, "PANE", "in herdr's word")
			_check(heading.get_global_rect().end.y <= pane_id.get_global_rect().position.y, "above the pane's id")
			_check(
				not heading.get_parent().is_ancestor_of(footnote) and heading.get_parent() != footnote.get_parent(),
				"and the note is not among the pane's lines"
			)
	_done(office)


## Every run starts with the drawer closed: the office's refreshes render no
## list rows then, and a real `A` renders them before the list takes the
## keyboard, on the waiting group as when the drawer was open.
func test_a_closed_drawer_renders_no_rows_until_a_opens_it() -> void:
	var office := await _live_office()
	var list := office.hud.agent_list
	_check(not office.hud.drawer_open(), "the drawer starts closed")
	var before := list.renders
	for index in 4:
		office.refresh()
		await _frames(1)
	_eq(list.renders - before, 0, "office refreshes with the drawer closed render no rows")
	_eq(office.hud.attention_count(), 4, "while the drawer's tab still counts who waits")
	await _key_cycle(KEY_A)
	_check(office.hud.drawer_open() and list.has_keyboard(), "a real `A` opens the drawer to the list")
	_eq(list.shown_keys()[0], AgentListModel.FLAT_WAITING, "on the waiting group")
	_check(list.row_for(HerdrFleet.pane_key(LOCAL, "api:p1")) != null, "with every pane's row")
	_done(office)


# --- helpers ------------------------------------------------------------------


func _for_pane(office: OfficeScene, pane_id: String) -> AttentionItem:
	var key := HerdrFleet.pane_key(LOCAL, pane_id)
	for item in office.attention_store.active():
		if item.pane_key == key and not item.retired:
			return item
	return null


func _key_cycle(keycode: Key, shift := false) -> void:
	var event := _key(keycode)
	event.physical_keycode = keycode
	event.shift_pressed = shift
	event.unicode = keycode + 32 if keycode >= KEY_A and keycode <= KEY_Z else 0
	await _parsed(event)
	event.pressed = false
	await _parsed(event)


## Hold a key for a few frames, the way the camera polls arrows.
func _key_hold(keycode: Key) -> void:
	var event := _key(keycode)
	event.physical_keycode = keycode
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(6)
	event.pressed = false
	await _parsed(event)


func _tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


func _double(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _tap(control)
	var press := _mouse_button(at, MOUSE_BUTTON_LEFT, true)
	press.double_click = true
	await _parsed(press)
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


## The row for `key`, unfolded and scrolled into the list's view.
func _visible_row(office: OfficeScene, key: String) -> AgentListRow:
	var list := office.hud.agent_list
	var entry := list.entry_for(key)
	if entry != null and not entry.parent.is_empty():
		list.set_collapsed(entry.parent, false)
	var row := list.row_for(key)
	_check(row != null, "the list has a row for " + key)
	if row == null:
		return null
	var scroll: ScrollContainer = list.get_node("%Scroll")
	scroll.ensure_control_visible(row)
	await _frames(2)
	return row


## A live office with the agent list's drawer opened by a real click on its tab:
## every run starts with it closed, and this suite is about the list.
func _listed_office(snapshot: Dictionary = fixture) -> OfficeDouble:
	var office := await _live_office(snapshot)
	var tab: Control = office.hud.get_node("%DrawerTab")
	await _tap(tab)
	await _frames(2)
	_check(office.hud.drawer_open(), "the drawer's tab opens it")
	return office


func _click_row(office: OfficeScene, key: String) -> void:
	var row := await _visible_row(office, key)
	if row != null:
		await _tap(row)
		await _frames(1)


func _open_history(office: OfficeScene) -> void:
	var list := office.hud.agent_list
	var group := list.group_for(AgentListModel.FLAT_HISTORY)
	var scroll: ScrollContainer = list.get_node("%Scroll")
	scroll.ensure_control_visible(group)
	await _frames(2)
	await _tap(group)
	await _frames(2)
	_check(not list.collapsed(AgentListModel.FLAT_HISTORY), "history unfolds with a real click")


## Right-click the row for `key` and choose `label` from its menu with the
## keyboard; `disabled` expects that entry to be greyed out instead.
func _row_action(office: OfficeScene, key: String, label: String, disabled := false) -> void:
	var row := await _visible_row(office, key)
	if row == null:
		return
	var at := row.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_RIGHT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_RIGHT, false))
	var menu := office.hud.agent_list.actions_menu()
	_check(menu.visible, "the row's menu opened for " + label)
	var index := -1
	for position in menu.item_count:
		if menu.get_item_text(position) == label:
			index = position
	_check(index >= 0, "the menu offers " + label)
	if index < 0 or disabled:
		if index >= 0:
			_check(menu.is_item_disabled(index), label + " is off")
		menu.hide()
		await _frames(2)
		return
	_check(not menu.is_item_disabled(index), label + " is on")
	for step in menu.item_count + 1:
		if menu.get_focused_item() == index:
			break
		await _key_cycle(KEY_DOWN)
	await _key_cycle(KEY_ENTER)
	await _frames(2)


## Pretend the Local client saw `pane_id` enter its state `elapsed` seconds ago.
func _set_wait(office: OfficeDouble, pane_id: String, elapsed: float) -> void:
	var now := Time.get_unix_time_from_system()
	var clocks := HerdrClient.carry_states({}, _local(office).snapshot.panes, now)
	clocks[pane_id].since = now - elapsed
	_local(office)._states = clocks
