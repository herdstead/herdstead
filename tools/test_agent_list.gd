extends "res://tools/test_base.gd"
## The right-hand agent list: its model (AgentListModel, pure) and its scene,
## driven through the HUD with real mouse and keyboard input.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const FLOORS := "res://tools/fixtures/snapshot_floors.json"
const WORKTREES := "res://tools/fixtures/snapshot_worktrees.json"
const LOCAL := HerdrFleet.LOCAL

var art: ArtPack
var second: ArtPack
var pen: OfficeDraw
var hud: OfficeHud
## What the HUD said, in order: ["pick", key] and ["open", key].
var said: Array[Array] = []
var recorder: Recorder


## Whatever input nothing in the GUI took: what the office would be handed.
class Recorder:
	extends Node
	var keys: Array[Key] = []
	var wheels := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.is_pressed():
			keys.append((event as InputEventKey).keycode)
		elif event is InputEventMouseButton and event.is_pressed():
			wheels += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.gui_embed_subwindows = true
	root.size = Vector2i(800, 480)
	art = ArtPack.from_manifest("res://assets/daylight/manifest.json")
	second = ArtPack.from_manifest(_second_pack_at(_work_dir().path_join("list-pack-second")))
	pen = OfficeDraw.new(art)
	await run_cases()


func _marker() -> String:
	return "AGENT LIST TESTS"


func _after_case() -> void:
	if is_instance_valid(hud):
		hud.free()
	if is_instance_valid(recorder):
		recorder.free()
	said.clear()


# --- the model ------------------------------------------------------------------


func test_flat_view_orders_by_urgency() -> void:
	var raw := _snapshot(FLOORS)
	# Three waiting: a known long wait, a known short one and an unknown start.
	raw = _with(raw, "api:p2", {"agent_status": "blocked"})
	var frame := _frame([_machine(LOCAL, raw)])
	_stamp(frame, {"web:p1": 200.0, "infra:p1": 100.0, "api:p2": -1.0, "web:p2": 50.0, "infra:p2": 10.0})
	var entries := AgentListModel.build(frame, [], [], AgentListModel.View.FLAT, 0)
	AgentListModel.apply(entries, {}, "")
	_eq(
		_children(entries, AgentListModel.FLAT_WAITING),
		["api:p2", "infra:p1", "web:p1"].map(_local),
		"blocked: unknown start first, then who waited longest (the reception queue's order)"
	)
	_eq(
		_children(entries, AgentListModel.FLAT_UNREAD), ["infra:p2", "web:p2"].map(_local), "then UNREAD, longest first"
	)
	_eq(
		_children(entries, AgentListModel.FLAT_WORKING),
		["api:p1", "api:p4", "data:p1", "data:p2"].map(_local),
		"then working, in the floors' order, one still launching included"
	)
	_eq(_entry(entries, _local("data:p2")).presence, AgentListModel.Presence.STARTING, "that one says so")
	_eq(_children(entries, AgentListModel.FLAT_IDLE), ["infra:p3"].map(_local), "then idle")
	_eq(
		_children(entries, AgentListModel.FLAT_SHELLS),
		["api:p3", "web:p3", "notes:p1"].map(_local),
		"shells in a group of their own"
	)
	var groups := PackedStringArray()
	for entry in entries:
		if entry.kind == AgentListModel.Kind.GROUP:
			groups.append(entry.key)
	_eq(groups, PackedStringArray(AgentListModel.FLAT_GROUPS.keys()), "the groups in urgency order")
	var shells := _entry(entries, AgentListModel.FLAT_SHELLS)
	_check(shells.shown, "the shells' header is drawn")
	_check(not _entry(entries, _local("api:p3")).shown, "but the group starts collapsed")
	_eq(_entry(entries, AgentListModel.FLAT_WAITING).matched, 3, "the waiting group counts its lines")


## Blocked comes first: an agent asking while herdr still launches it is
## BLOCKED, not STARTING. data:p2, launching in the fixture, blocks: it waits
## in the Waiting group with the others, its row wears the pulsing blocked
## badge (whose label the attention clock writes the wait into) and no word of
## STARTING, and the attention the drawer's tab counts takes it in.
func test_a_blocked_agent_still_launching_waits_in_the_list() -> void:
	var raw := _with(_snapshot(FLOORS), "data:p2", {"agent_status": "blocked"})
	var frame := _frame([_machine(LOCAL, raw)])
	var pane := frame.pane(_local("data:p2"))
	_check(pane.starting, "herdr still launches data:p2")
	_eq(AgentListModel.presence_of(pane, false), AgentListModel.Presence.BLOCKED, "blocked comes first")
	var entries := AgentListModel.build(frame, [], [], AgentListModel.View.FLAT, 0)
	AgentListModel.apply(entries, {}, "")
	_check(_children(entries, AgentListModel.FLAT_WAITING).has(_local("data:p2")), "it waits with the blocked")
	_eq(AgentListModel.note_of(_entry(entries, _local("data:p2")), 0), "", "and says no STARTING")
	await _hud()
	hud.show_agents(frame, [], [], "", 0)
	await _frames(2)
	var row := hud.agent_list.row_for(_local("data:p2"))
	await _scroll_to(row)
	_eq(row.mark(), ArtContract.STATE_BLOCKED, "its row wears the blocked badge, not the hourglass")
	_eq(row.icon_badge().state, ArtContract.STATE_BLOCKED, "which pulses")
	_check(row.icon_badge().wait != null, "and has its wait written beside it")
	_check(not row.get_tooltip(Vector2.ZERO).contains("STARTING"), "the hover says no STARTING either")
	var store := AttentionStore.new()
	for building in frame.buildings:
		store.observe(building.key, building.label, building.all_panes, true, 1000, 1000.0)
	hud.show_attention(store.current(1000))
	_eq(hud.attention_count(), 5, "attention: the two blocked, the two UNREAD and data:p2")


func test_tree_view_nests_machine_floor_mezzanine_tab_agent() -> void:
	var frame := _frame([_machine(LOCAL, _snapshot(WORKTREES))])
	var entries := AgentListModel.build(frame, [], [], AgentListModel.View.TREE, 0)
	AgentListModel.apply(entries, {}, "")
	var machine := _entry(entries, "tree:m:" + LOCAL)
	var parent := _entry(entries, "tree:f:" + _local("hs"))
	var lane := _entry(entries, "tree:f:" + _local("hud"))
	_check(machine != null and parent != null and lane != null, "machine and floors are groups")
	if machine == null or parent == null or lane == null:
		return
	_eq(parent.parent, machine.key, "a floor sits in its machine")
	_eq(lane.parent, parent.key, "a worktree mezzanine sits under its source floor")
	_eq([machine.depth, parent.depth, lane.depth], [0, 1, 2], "and is indented one step further")
	_check(lane.title.begins_with("1A"), "it carries its mezzanine label: " + lane.title)
	var agent := _first(entries, AgentListModel.Kind.PANE)
	_check(agent != null and _entry(entries, agent.parent).key.begins_with("tree:t:"), "an agent sits in its tab")
	var order := PackedStringArray()
	for entry in entries:
		if entry.key.begins_with("tree:f:"):
			order.append(entry.key)
	var tree := PackedStringArray()
	for floor_model in frame.buildings[0].zone_tree:
		tree.append("tree:f:" + floor_model.key)
	_eq(order, tree, "floors come in the building's tree order")
	var shells := 0
	for entry in entries:
		if entry.kind == AgentListModel.Kind.PANE and entry.presence == AgentListModel.Presence.SHELL:
			shells += 1
			_eq(entry.parent, "tree:shells", "a shell is not in its floor's groups but in the shells'")
	_check(shells > 0, "the fixture has shells")


func test_offline_machine_is_grey_frozen_and_never_idle() -> void:
	var raw := _snapshot(FLOORS)
	var frame := _frame([_machine(LOCAL, raw), _machine("far", raw, true)])
	for view: AgentListModel.View in [AgentListModel.View.FLAT, AgentListModel.View.TREE]:
		var entries := AgentListModel.build(frame, [], [], view, 0)
		AgentListModel.apply(entries, {}, "")
		for entry in entries:
			if entry.kind == AgentListModel.Kind.PANE and entry.machine == "far" and not entry.pane.provider.is_empty():
				_eq(
					entry.presence,
					AgentListModel.Presence.OFFLINE,
					"a dropped machine's agent is offline, not its last state"
				)
				_check(entry.parent != AgentListModel.FLAT_IDLE, "and never counted idle")
	var tree := AgentListModel.build(frame, [], [], AgentListModel.View.TREE, 0)
	AgentListModel.apply(tree, {}, "")
	var far := _entry(tree, "tree:m:far")
	_check(far.offline and far.waiting == 0 and far.unread == 0, "its groups count nobody waiting")
	_eq(AgentListGroup.count_text(far), "offline", "they say offline")
	_eq(AgentListGroup.count_text(_entry(tree, "tree:m:" + LOCAL)), "2 waiting", "the live one counts")
	await _hud()
	hud.show_agents(frame, [], [], "", 0)
	hud.agent_list.set_view(AgentListModel.View.FLAT)
	await _frames(2)
	var row := hud.agent_list.row_for(HerdrFleet.pane_key("far", "web:p1"))
	_check(row != null, "the offline machine's blocked agent has a row")
	if row == null:
		return
	var badge := row.icon_badge()
	_eq(badge.state, &"", "its badge does not pulse")
	_eq(row.mark(), ArtContract.UI_OFFLINE, "it wears the offline mark")
	await _scroll_to(row)
	_check(badge.visible and badge.texture != null, "which is drawn")
	var wait: Label = row.get_node("%Tail")
	_eq(wait.text, "OFFLINE", "and shows no wait, it says OFFLINE")
	_check(badge.wait == null, "the attention clock writes nothing into it")
	var label: Label = row.get_node("%Name")
	_eq(label.theme_type_variation, &"LabelMuted", "its text is greyed")


func test_filter_matches_provider_tab_floor_and_repo() -> void:
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	var cases := {
		"codex": ["api:p2", "web:p2", "infra:p2", "data:p2"],
		"deploy": ["infra:p1"],
		"数据": ["data:p1", "data:p2"],
		"ops-tools": ["infra:p1", "infra:p2", "infra:p3"],
	}
	for query: String in cases:
		var entries := AgentListModel.build(frame, [], [], AgentListModel.View.FLAT, 0)
		AgentListModel.apply(entries, {}, query)
		var shown := PackedStringArray()
		for entry in entries:
			if entry.shown and entry.kind == AgentListModel.Kind.PANE:
				shown.append(entry.key)
		shown.sort()
		var names: Array = cases[query]
		var wanted := PackedStringArray(names.map(_local))
		wanted.sort()
		_eq(shown, wanted, "the filter '%s'" % query)
	await _hud()
	hud.show_agents(frame, [], [], "", 0)
	await _frames(2)
	var filter: LineEdit = hud.agent_list.get_node("%Filter")
	await _click(filter)
	await _type("deploy")
	_eq(filter.text, "deploy", "typed into the filter box")
	var drawn := _drawn_panes()
	_eq(drawn, PackedStringArray([_local("infra:p1")]), "the list shows what matches, by real typing")
	_eq(hud.agent_list.shown_keys()[0], AgentListModel.FLAT_WAITING, "with its group's header")


# --- the scene ------------------------------------------------------------------


func test_rows_are_kept_and_updated_in_place() -> void:
	await _hud()
	var raw := _snapshot(FLOORS)
	hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", 0)
	await _frames(2)
	var row := hud.agent_list.row_for(_local("api:p1"))
	var group := hud.agent_list.group_for(AgentListModel.FLAT_WORKING)
	var id := row.get_instance_id()
	var drawn := {}
	for key in hud.agent_list.shown_keys():
		if hud.agent_list.row_for(key) != null:
			drawn[key] = hud.agent_list.row_for(key).draws
	for index in 5:
		hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", index)
	await _frames(2)
	var redrawn := []
	for key: String in drawn:
		if hud.agent_list.row_for(key).draws != drawn[key]:
			redrawn.append(key)
	_eq(redrawn, [], "a refresh with the same data writes no row")
	_eq(hud.agent_list.row_for(_local("api:p1")).get_instance_id(), id, "a refresh keeps the row")
	_eq(hud.agent_list.group_for(AgentListModel.FLAT_WORKING), group, "and the header")
	hud.show_agents(_frame([_machine(LOCAL, _with(raw, "api:p1", {"agent_status": "blocked"}))]), [], [], "", 0)
	await _frames(2)
	_eq(hud.agent_list.row_for(_local("api:p1")).get_instance_id(), id, "a new state moves the same row")
	var changed := []
	for key: String in drawn:
		if hud.agent_list.row_for(key).draws != drawn[key]:
			changed.append(key)
	_eq(changed, [_local("api:p1")], "a status change writes that row alone")
	_eq(hud.agent_list.entry_for(_local("api:p1")).parent, AgentListModel.FLAT_WAITING, "into the waiting group")
	_eq(row.icon_badge().state, ArtContract.STATE_BLOCKED, "and its badge pulses for it")
	await _click(hud.agent_list.get_node("%Tree"))
	_eq(hud.agent_list.view, AgentListModel.View.TREE, "a real click switches to the tree")
	_eq(hud.agent_list.row_for(_local("api:p1")).get_instance_id(), id, "which reuses the pane's row")
	_check(hud.agent_list.group_for(AgentListModel.FLAT_WORKING) == null, "and drops the flat headers")
	var daylight_texture := row.icon_badge().texture
	hud.dress(second, OfficeDraw.new(second).font)
	await _frames(1)
	_eq(hud.agent_list.row_for(_local("api:p1")).get_instance_id(), id, "a theme switch rebuilds no row")
	_check(row.icon_badge().texture != daylight_texture, "it re-dresses the badge")
	_eq(row.mark(), ArtContract.STATE_BLOCKED, "with the same mark")
	hud.show_agents(_frame([_machine(LOCAL, _without(raw, "api:p1"))]), [], [], "", 0)
	await _frames(2)
	_check(hud.agent_list.row_for(_local("api:p1")) == null, "a closed pane's row goes")


func test_groups_fold_by_click_and_keep_their_fold_per_view() -> void:
	await _hud()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	var shells := hud.agent_list.group_for(AgentListModel.FLAT_SHELLS)
	var chevron: Label = shells.get_node("%Chevron")
	_check(hud.agent_list.collapsed(AgentListModel.FLAT_SHELLS), "shells start folded")
	_eq(chevron.text, "▶", "with a closed chevron")
	_check(hud.agent_list.row_for(_local("api:p3")) == null, "and no row made for them yet")
	var count: Label = shells.get_node("%Count")
	_eq(count.text, "3", "the folded group still counts")
	await _scroll_to(shells)
	await _click(shells)
	_check(not hud.agent_list.collapsed(AgentListModel.FLAT_SHELLS), "a click unfolds it")
	_eq(chevron.text, "▼", "the chevron opens")
	var shell := hud.agent_list.row_for(_local("api:p3"))
	_check(shell != null and shell.visible, "its rows are drawn")
	var working := hud.agent_list.group_for(AgentListModel.FLAT_WORKING)
	await _scroll_to(working)
	await _click(working)
	_check(not hud.agent_list.row_for(_local("api:p1")).visible, "folding hides the rows, keeps the nodes")
	await _click(hud.agent_list.get_node("%Tree"))
	var machine := hud.agent_list.group_for("tree:m:" + LOCAL)
	await _scroll_to(machine)
	await _click(machine)
	_check(hud.agent_list.collapsed("tree:m:" + LOCAL), "the tree folds on its own")
	await _click(hud.agent_list.get_node("%Flat"))
	_check(hud.agent_list.collapsed(AgentListModel.FLAT_WORKING), "the flat view's fold is still there")
	_eq(hud.agent_list.flat_folds().get(AgentListModel.FLAT_WORKING), true, "and is what is remembered")
	_check(not hud.agent_list.flat_folds().has("tree:m:" + LOCAL), "a session's tree folds are not")


func test_click_picks_and_double_click_opens() -> void:
	await _hud()
	_listen()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	var row := hud.agent_list.row_for(_local("web:p1"))
	await _click(row)
	_eq(said, [["pick", _local("web:p1")]], "a click picks that pane")
	said.clear()
	await _double_click(row)
	_check(said.has(["open", _local("web:p1")]), "a double-click opens it: " + str(said))
	_eq(said.count(["open", _local("web:p1")]), 1, "once")
	said.clear()
	var group := hud.agent_list.group_for(AgentListModel.FLAT_WAITING)
	await _double_click(group)
	_eq(said, [], "a header's clicks pick and open nothing")


func test_keyboard_moves_folds_opens_and_lets_go() -> void:
	await _hud()
	_listen()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], _local("api:p1"), 0)
	await _frames(2)
	_check(not hud.agent_list.has_keyboard(), "the list does not take the keyboard by itself")
	await _key(KEY_DOWN)
	_eq(said, [], "so a key reaches it only once it has focus")
	_eq(recorder.keys, [KEY_DOWN], "the office gets it")
	# `A`'s path: the bar has no Attention button; the HUD has no office to hear the key.
	hud.toggle_agent_list()
	await _frames(2)
	_check(hud.agent_list.has_keyboard(), "toggle_agent_list() gives it the keyboard")
	_eq(hud.agent_list.cursor(), _local("api:p1"), "the cursor starts on the selected pane")
	await _key(KEY_UP)
	_eq(hud.agent_list.cursor(), AgentListModel.FLAT_WORKING, "Up goes to its header")
	_eq(said, [], "which picks nothing")
	await _key(KEY_UP)
	_eq(said, [["pick", _local("infra:p2")]], "on to the pane above it, which is picked")
	await _key(KEY_LEFT)
	_eq(hud.agent_list.cursor(), AgentListModel.FLAT_UNREAD, "Left on a row goes to its group")
	_check(hud.agent_list.collapsed(AgentListModel.FLAT_UNREAD), "and folds it")
	await _key(KEY_RIGHT)
	_check(not hud.agent_list.collapsed(AgentListModel.FLAT_UNREAD), "Right unfolds it")
	said.clear()
	await _key(KEY_DOWN)
	_eq(said, [["pick", _local("web:p2")]], "Down picks the first pane in it")
	said.clear()
	await _key(KEY_ENTER)
	_eq(said, [["open", _local("web:p2")]], "Enter opens the pane under the cursor")
	said.clear()
	recorder.keys.clear()
	for code: Key in [KEY_N, KEY_T, KEY_PAGEUP]:
		await _key(code)
	_eq(recorder.keys, [KEY_N, KEY_T, KEY_PAGEUP], "N, T and PageUp go on to the office")
	_check(hud.agent_list.has_keyboard(), "while the list keeps the keyboard")
	_eq(said, [], "and the list does nothing with them")
	recorder.keys.clear()
	await _key(KEY_ESCAPE)
	_check(not hud.agent_list.has_keyboard(), "Escape lets go")
	_eq(recorder.keys, [], "and is the list's")
	await _key(KEY_DOWN)
	_eq(said, [], "then the arrows do nothing here")
	_eq(recorder.keys, [KEY_DOWN], "they are the office's again")


func test_row_menu_snoozes_hides_and_restores_by_real_input() -> void:
	await _hud()
	var snoozed: Array[Array] = []
	hud.attention_snooze_requested.connect(func(id: String, seconds: int) -> void: snoozed.append([id, seconds]))
	hud.attention_hidden_changed.connect(func(id: String, hidden: bool) -> void: snoozed.append([id, hidden]))
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	var item := _item(frame, "web:p1")
	var key := _local("web:p1")
	hud.show_agents(frame, [item], [], "", 0)
	await _frames(2)
	var row := hud.agent_list.row_for(key)
	var more: Button = row.get_node("%More")
	_check(not more.visible, "an unselected row keeps its label's room: no `⋯`")
	var working := hud.agent_list.row_for(_local("api:p1"))
	await _click_at(working.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	_check(not hud.agent_list.actions_menu().visible, "a working row has no actions: a right-click opens nothing")
	await _choose(row, "Snooze 5 min", true)
	_eq(snoozed, [[item.id, AgentList.SNOOZE_SECONDS]], "Snooze names the record, five minutes")
	item.snoozed_until_msec = 10_000
	hud.show_agents(frame, [item], [], key, 0)
	await _frames(2)
	_check(more.visible, "the selected row shows its `⋯`")
	_eq(
		more.get_theme_color("font_color"), art.color(ArtContract.PAPER), "in paper, readable on the selected row's ink"
	)
	_eq(hud.agent_list.entry_for(_local("web:p1")).parent, AgentListModel.FLAT_MUTED, "a snoozed row steps down")
	var note: Label = row.get_node("%Tail")
	_eq(note.text, "SNOOZED", "and says so")
	_eq(row.icon_badge().state, &"", "its badge rests")
	snoozed.clear()
	await _choose(row, "Resume reminder", false)
	_eq(snoozed, [[item.id, 0]], "Resume takes the snooze back")
	snoozed.clear()
	await _choose(row, "Hide", true)
	_eq(snoozed, [[item.id, true]], "Hide, from a right-click")
	item.hidden = true
	item.snoozed_until_msec = 0
	hud.show_agents(frame, [item], [], key, 0)
	await _frames(2)
	_eq(note.text, "HIDDEN", "a hidden row says so")
	snoozed.clear()
	await _choose(row, "Restore", false)
	_eq(snoozed, [[item.id, false]], "Restore brings it back")


## History reads the StateLog: a line per pane that was blocked or done this
## run and no longer is, newest first. ENDED while its pane is there, GONE once
## it closed, OFFLINE while its machine is away; a pane still waiting has no
## line; an ENDED row writes no word (the group says it), its tooltip does.
## The tooltip says what it does now and how often it was blocked; only
## an ENDED line whose pane is still that terminal can be located, by View.
func test_history_lines_show_what_became_of_each_record() -> void:
	await _hud()
	var located: Array[String] = []
	hud.history_locate_requested.connect(func(key: String) -> void: located.append(key))
	var raw := _snapshot(FLOORS)
	var bee_raw := _only(raw, "web:p1")
	var ledger := StateLog.new()
	var start := _frame([_machine(LOCAL, raw), _machine("bee", bee_raw)])
	_log(ledger, start, LOCAL, true, 1000)
	_log(ledger, start, "bee", true, 1000)
	# Bee drops with its agent blocked; infra:p2 (done) closes; infra:p1 stops waiting.
	_log(ledger, start, "bee", false, 1500)
	var closed := _without(raw, "infra:p2")
	_log(ledger, _frame([_machine(LOCAL, closed)]), LOCAL, true, 2500)
	var now := _with(closed, "infra:p1", {"agent_status": "idle"})
	var frame := _frame([_machine(LOCAL, now), _machine("bee", bee_raw, true)])
	_log(ledger, frame, LOCAL, true, 3500)
	var live: Dictionary[String, bool] = {LOCAL: true, "bee": false}
	hud.show_agents(frame, [], AgentHistory.of(ledger, frame, live, 4000), "", 4000)
	await _frames(2)
	var ended := "history:" + _local("infra:p1")
	var gone := "history:" + _local("infra:p2")
	var offline := "history:" + HerdrFleet.pane_key("bee", "web:p1")
	_check(hud.agent_list.row_for(ended) == null, "history starts folded, with no rows made")
	var group := hud.agent_list.group_for(AgentListModel.FLAT_HISTORY)
	await _scroll_to(group)
	await _click(group)
	await _frames(2)
	var lines := PackedStringArray()
	var notes := []
	for key in hud.agent_list.shown_keys():
		var entry := hud.agent_list.entry_for(key)
		if entry.kind == AgentListModel.Kind.HISTORY:
			lines.append(key)
			var note: Label = hud.agent_list.row_for(key).get_node("%Tail")
			notes.append(note.text)
	_eq(lines, PackedStringArray([ended, gone, offline]), "a line per pane that needed a human, newest first")
	_eq(notes, ["", "GONE", "OFFLINE"], "each line says what became of its pane; an ENDED one needs no word")
	_check(hud.agent_list.entry_for("history:" + _local("web:p1")) == null, "a pane still waiting is no History")
	_eq(hud.agent_list.entry_for(ended).title, "PI", "the provider, in capitals")
	_eq(hud.agent_list.entry_for(ended).detail, "deploy", "its tab: the space is its floor")
	_eq(hud.agent_list.entry_for(ended).presence, AgentListModel.Presence.BLOCKED, "its badge: it was blocked")
	_eq(hud.agent_list.entry_for(gone).presence, AgentListModel.Presence.UNREAD, "this one's: it was done")
	var ended_row := hud.agent_list.row_for(ended)
	var tip := ended_row.get_tooltip(Vector2.ZERO)
	_check(
		tip.contains("ENDED · No longer waiting: idle since"), "the tooltip names it ENDED and what it does now: " + tip
	)
	_check(tip.contains("blocked 1×"), "and how often it was blocked")
	_check(hud.agent_list.row_for(gone).get_tooltip(Vector2.ZERO).contains("Pane gone"), "a gone pane says so")
	_check(
		hud.agent_list.row_for(offline).get_tooltip(Vector2.ZERO).contains("Machine offline"),
		"an offline machine's line says its state is unknown"
	)
	await _choose(hud.agent_list.row_for(gone), "Details", true, true)
	await _choose(hud.agent_list.row_for(offline), "Details", true, true)
	_eq(located, [], "a gone pane and an offline machine's cannot be located")
	await _choose(ended_row, "View", true)
	_eq(located, [_local("infra:p1")], "the same terminal's View locates its pane")


## At the 480x320 minimum (and any 320-high window at 3x) the staff panel is
## one compact line along the bottom: who, state and seat, the wait, and NEXT;
## the drawer's list keeps the whole right column. Opening the panel up (Enter,
## answer mode) gives it its full height with the preview and leaves the list
## where it is; folding it back gives the world its room again. At 800x480 the
## panel stands at full height.
func test_the_staff_panel_is_one_row_at_the_smallest_screen() -> void:
	await _hud(Vector2i(480, 320))
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	hud.show_agents(frame, [], [], _local("api:p1"), 0)
	hud.inspector.show_pane(frame.pane(_local("api:p1")), "", false)
	await _frames(3)
	var holder: Control = hud.get_node("%ListHolder")
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	var line: Control = hud.inspector.get_node("%CompactRow")
	var detail: Control = hud.inspector.get_node("%Detail")
	var next: Control = hud.inspector.get_node("%NextButton")
	var preview: Control = hud.inspector.get_node("%Preview")
	_eq(hud.placed(hud.right_column), Rect2(320, 40, 144, 208), "the right column at 480x320, the drawer opened")
	_check(holder.visible and hud.card_compact(), "the list is there, and the panel is compact")
	_eq(hud.inspector.size, Vector2(448, 28), "the panel is one line along the bottom")
	_check(line.is_visible_in_tree() and not detail.is_visible_in_tree(), "its compact line, not its details")
	_eq(hud.inspector.get_node("%CompactLine").get("text"), "CLAUDE · WORKING · api / main", "who, state and seat")
	_check(next.is_visible_in_tree(), "NEXT is on it")
	_check(hud.inspector.get_global_rect().encloses(next.get_global_rect()), "inside the panel")
	_check(not preview.is_visible_in_tree(), "the preview is out of it")
	_eq(hud.world_rect(), Rect2(96, 48, 216, 200), "the world stops above the line, beside the rail and the drawer")
	_eq(holder.size.y, 208.0, "the drawer takes the whole column")
	_eq(hud.agent_list.size.y, 188.0, "the list the whole of it under the drawer's tabs")
	# Six rows: the Waiting and Unread headers and four agents under them, who
	# needs a human first, without scrolling.
	_check(scroll.size.y >= 6 * 18, "the list shows at least six rows: %.0f units" % scroll.size.y)
	hud.toggle_agent_list()
	await _frames(2)
	_check(hud.agent_list.has_keyboard() and holder.visible, "`A` gives the list the keyboard")
	_check(hud.card_compact(), "and changes nothing else")
	await _key(KEY_ESCAPE)
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	hud.expand_card()
	await _frames(2)
	_check(not hud.card_compact(), "opened up")
	_eq(hud.inspector.size, Vector2(448, 128), "the panel stands at full height")
	_check(detail.is_visible_in_tree() and not line.is_visible_in_tree(), "with its details")
	_check(hud.inspector.get_global_rect().encloses(preview.get_global_rect()), "the preview inside it")
	_check(holder.visible, "and the list where it was")
	_eq(hud.world_rect(), Rect2(96, 48, 216, 112), "the world gives it the room")
	_eq(rooms.size(), 1, "said once")
	hud.compact_card()
	await _frames(2)
	_check(hud.card_compact() and line.is_visible_in_tree(), "folded back to its line")
	_eq(hud.inspector.size, Vector2(448, 28), "one line again")
	_eq(hud.world_rect(), Rect2(96, 48, 216, 200), "and the world has its room back")
	_eq(rooms.size(), 2, "said once more")
	# Taking the keyboard shows the flat view but keeps the viewer's own choice.
	hud.agent_list.set_view(AgentListModel.View.TREE)
	var remembered: Array[bool] = []
	hud.agent_list_changed.connect(func() -> void: remembered.append(true))
	hud.toggle_agent_list()
	_eq(hud.agent_list.view, AgentListModel.View.FLAT, "`A` shows the flat view")
	_eq(remembered, [], "without telling the office to remember it")
	await _key(KEY_ESCAPE)
	hud.fit(Vector2(800, 480))
	await _frames(3)
	# Room does not open the panel; it stays one line until opened.
	_check(holder.visible and hud.card_compact(), "with room, both are there, the panel still one line")
	_eq(hud.inspector.size, Vector2(768, 80), "the panel one line along the bottom")
	_eq(holder.size, Vector2(144, 316), "the drawer above it")
	_eq(hud.agent_list.size.y, 296.0, "the list under the drawer's tabs")
	_eq(hud.world_rect(), Rect2(96, 48, 536, 308), "the world between them")


## The staff panel is compact at every size until it is opened: a card at
## 800x480 (tall enough: its header over the line's buttons, the line's words
## hidden), one line at 480x320. At both, only `Open ⏎` (a real click) opens
## it, and only `▾ Esc` folds it again; the room and the world's rect are the
## scene's. Each move is said once through room_changed. Enter and Escape are
## the office's (tools/test_answers.gd, tools/test_commands.gd).
func test_the_staff_panel_is_compact_at_every_size_until_opened() -> void:
	await _hud(Vector2i(800, 480), false)
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	hud.inspector.show_pane(frame.pane(_local("api:p1")), "", false)
	await _frames(3)
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	var line: Control = hud.inspector.get_node("%CompactRow")
	var detail: Control = hud.inspector.get_node("%Detail")
	var open: Button = hud.inspector.get_node("%CompactOpen")
	var fold: Button = hud.inspector.get_node("%FoldButton")
	var words: Control = hud.inspector.get_node("%CompactLine")
	var sizes := {
		Vector2i(800, 480): [Vector2(768, 80), Rect2(96, 48, 660, 308), Vector2(768, 128), Rect2(96, 48, 660, 260)]
	}
	sizes[Vector2i(480, 320)] = [Vector2(448, 28), Rect2(96, 48, 340, 200), Vector2(448, 128), Rect2(96, 48, 340, 112)]
	for screen: Vector2i in sizes:
		var wanted: Array = sizes[screen]
		root.size = screen
		hud.fit(Vector2(screen))
		await _frames(3)
		rooms.clear()
		_check(hud.card_compact(), "%s: compact to start with" % screen)
		_eq(hud.inspector.size, wanted[0], "%s: compact along the bottom" % screen)
		if screen.y >= 400:
			_check(hud.inspector.card(), "%s: a card" % screen)
			_check(
				detail.is_visible_in_tree() and line.is_visible_in_tree() and not words.is_visible_in_tree(),
				"%s: the header over the line's buttons, not its words" % screen
			)
		else:
			_check(not hud.inspector.card(), "%s: one line" % screen)
			_check(
				line.is_visible_in_tree() and not detail.is_visible_in_tree(), "%s: the line, not the details" % screen
			)
		_eq(hud.world_rect(), wanted[1], "%s: the world above it" % screen)
		_check(open.is_visible_in_tree(), "%s: `Open` is on the line" % screen)
		_eq(open.text, "Open ⏎" if screen.x >= 640 else "⏎", "%s: in the line's words" % screen)
		await _click(open)
		await _frames(2)
		_check(not hud.card_compact(), "%s: a click on `Open` opens the panel" % screen)
		_check(not hud.inspector.answering(), "%s: and only opens it" % screen)
		_eq(hud.inspector.size, wanted[2], "%s: at full height" % screen)
		_check(detail.is_visible_in_tree() and not line.is_visible_in_tree(), "%s: its details" % screen)
		_eq(hud.world_rect(), wanted[3], "%s: the world gives it the room" % screen)
		_check(fold.is_visible_in_tree(), "%s: `▾ Esc` is in the actions" % screen)
		_check(hud.inspector.get_global_rect().encloses(fold.get_global_rect()), "%s: inside the panel" % screen)
		_eq(rooms.size(), 1, "%s: said once" % screen)
		await _click(fold)
		await _frames(2)
		_check(hud.card_compact(), "%s: `▾ Esc` folds it back" % screen)
		_eq(hud.inspector.size, wanted[0], "%s: compact again" % screen)
		_eq(hud.world_rect(), wanted[1], "%s: and the world has its room back" % screen)
		_eq(rooms.size(), 2, "%s: said once more" % screen)
	_eq(recorder.keys, [], "nothing went past the HUD")


## The card is the header over the line's buttons and nothing more: the note
## that explains a state (UNREAD's under a done agent, a dropped machine's)
## has no row there, so the card holds everything it shows and the note waits
## for the opened panel. Seen on a real fleet: with the note in the card the
## name was cut off above the frame and the note stood under the buttons.
## The header's last row and the buttons are not compared box to box: they
## touch on macOS and share a unit on Linux, where `Open ⏎` is a unit taller
## (its glyph comes from a fallback), with or without a note.
func test_the_card_holds_all_it_shows_for_a_state_with_a_note() -> void:
	await _hud(Vector2i(800, 480), false)
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	var card: Control = hud.inspector.get_node("%CardFrame")
	var footnote: Label = hud.inspector.get_node("%Footnote")
	var seat: Control = hud.inspector.get_node("%Seat")
	var open: Button = hud.inspector.get_node("%CompactOpen")
	var fold: Button = hud.inspector.get_node("%FoldButton")
	var shown: Array[Control] = [seat, open]
	for unique: String in ["%Provider", "%CaptionPill"]:
		var part: Control = hud.inspector.get_node(unique)
		shown.append(part)
	for step: Array in [["web:p2", false, "done"], ["api:p1", true, "a dropped machine's"]]:
		var what: String = step[2]
		var dropped: bool = step[1]
		hud.inspector.show_pane(frame.pane(_local(str(step[0]))), "", dropped)
		await _frames(3)
		_check(hud.card_compact() and hud.inspector.card(), "%s: the compact panel is a card" % what)
		for part: Control in shown:
			_check(part.is_visible_in_tree(), "%s: %s shows" % [what, part.name])
			_check(
				card.get_global_rect().encloses(part.get_global_rect()),
				(
					"%s: %s is inside the card: %s in %s"
					% [what, part.name, part.get_global_rect(), card.get_global_rect()]
				)
			)
		_check(not footnote.is_visible_in_tree(), "%s: the card has no row for the note" % what)
		await _click(open)
		await _frames(2)
		_check(not hud.card_compact(), "%s: `Open` opens the panel" % what)
		_check(footnote.is_visible_in_tree(), "%s: the opened panel says the note" % what)
		_check(hud.inspector.get_global_rect().encloses(footnote.get_global_rect()), "%s: inside the panel" % what)
		await _click(fold)
		await _frames(2)
		_check(hud.inspector.card() and not footnote.is_visible_in_tree(), "%s: folded, the card again" % what)
	_eq(recorder.keys, [], "nothing went past the HUD")


## Every run starts with the drawer closed to its tab, whatever an earlier
## run left: the scene says so, and the HUD does too. A floor's first plan is
## made for the world with the drawer closed, and stays that width with it open,
## which gives the world less room (the camera pans to what the drawer covers).
func test_the_drawer_starts_closed_and_floors_are_planned_for_its_tab() -> void:
	await _hud(Vector2i(800, 480), false)
	var holder: Control = hud.get_node("%ListHolder")
	var tab: Button = hud.get_node("%DrawerTab")
	_check(not hud.drawer_open(), "the drawer starts closed")
	_check(tab.is_visible_in_tree() and not holder.is_visible_in_tree(), "to its tab")
	_eq(hud.placed(hud.right_column), Rect2(764, 40, 20, 316), "a strip at the screen's right edge")
	_eq(hud.world_rect(), Rect2(96, 48, 660, 308), "the world takes the room")
	_eq(hud.plan_width(), 660.0, "a first plan is made for it")
	var scene: Control = HUD_SCENE.instantiate().get_node("Screen/RightColumn")
	_eq(scene.offset_left, hud.drawer_closed_left, "the scene's drawer is closed")
	_check(not (scene.get_node("ListHolder") as Control).visible, "with no list")
	_check((scene.get_node("DrawerTab") as Control).visible, "and its tab")
	scene.get_parent().get_parent().free()
	await _click(tab)
	await _frames(2)
	_check(hud.drawer_open() and holder.is_visible_in_tree(), "a click on the tab opens it")
	_eq(hud.world_rect(), Rect2(96, 48, 536, 308), "the world stops at the open drawer")
	_eq(hud.plan_width(), 660.0, "and a first plan is still made for the drawer closed")
	hud.fit(Vector2(480, 320))
	_eq(hud.world_rect(), Rect2(96, 48, 216, 200), "480x320, open: the world")
	_eq(hud.plan_width(), 340.0, "and the plan for the drawer closed")


## The one-line row keeps Monitor: offered exactly when the full panel's
## Monitor is (a pane shown, with a fleet), `Monitor ⤢` or `⤢` by the width,
## and a real click on it asks for that pane's monitor, as the full panel's does.
func test_the_one_line_monitor_button_asks_for_the_monitor() -> void:
	await _hud(Vector2i(800, 480), false)
	_listen()
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	hud.inspector.show_pane(frame.pane(_local("api:p1")), "", false)
	await _frames(2)
	var button: Button = hud.inspector.get_node("%CompactMonitor")
	_check(hud.card_compact(), "one line")
	_check(not button.is_visible_in_tree(), "no fleet, no monitor: the full panel's rule")
	var fleet := HerdrFleet.new()
	root.add_child(fleet)
	hud.inspector.connect_fleet(fleet, func() -> bool: return false)
	hud.inspector.show_pane(frame.pane(_local("api:p1")), "", false)
	await _frames(2)
	_check(button.is_visible_in_tree(), "with a fleet it is on the line")
	_eq(button.text, "Monitor ⤢", "in its long words from 640 wide")
	_check(button.tooltip_text.begins_with("M: "), "its tooltip names its key: " + button.tooltip_text)
	var full: Button = hud.inspector.get_node("%MonitorButton")
	_check(full.tooltip_text.begins_with("M: "), "and so does the full panel's: " + full.tooltip_text)
	await _click(button)
	_eq(said, [["open", _local("api:p1")]], "a click asks for that pane's monitor")
	hud.fit(Vector2(480, 320))
	await _frames(2)
	_eq(button.text, "⤢", "narrower, its short word")
	await _click(button)
	_eq(said.size(), 2, "and it still asks")
	hud.inspector.show_pane(null, "", false)
	await _frames(1)
	_check(not button.is_visible_in_tree(), "no pane, no Monitor")
	fleet.free()


## The drawer closes to a tab by the ▶ beside its tabs and opens again by a click on the
## tab, which gives the list no keyboard, or by `A`, which does. Each move gives
## the world its room (124 units) or takes it back, said once, and each is one
## the office hears of; a floor's first plan is made for the drawer closed.
func test_the_drawer_closes_to_a_tab_and_opens_again_by_click_and_by_a() -> void:
	await _hud()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	var remembered: Array[bool] = []
	hud.agent_list_changed.connect(func() -> void: remembered.append(true))
	var holder: Control = hud.get_node("%ListHolder")
	var tab: Button = hud.get_node("%DrawerTab")
	var collapse: Control = hud.get_node("%Collapse")
	_check(hud.drawer_open() and holder.is_visible_in_tree() and not tab.is_visible_in_tree(), "opened by its tab")
	await _click(collapse)
	await _frames(2)
	_check(not hud.drawer_open(), "the drawer's ▶ closes the drawer")
	_check(tab.is_visible_in_tree() and not holder.is_visible_in_tree(), "to its tab")
	_check(tab.text.replace("\n", "").begins_with("◀AGENTS"), "which says AGENTS: %s" % tab.text.c_escape())
	_eq(tab.get_global_rect(), Rect2(764, 40, 20, 316), "a strip at the screen's right edge")
	_eq(hud.world_rect(), Rect2(96, 48, 660, 308), "the world takes the room")
	_eq(hud.plan_width(), 660.0, "a first plan is made for the drawer closed")
	_eq([rooms.size(), remembered.size()], [1, 1], "said once, and remembered")
	await _click(tab)
	await _frames(2)
	_check(hud.drawer_open() and holder.is_visible_in_tree() and not tab.is_visible_in_tree(), "the tab opens it")
	_check(not hud.agent_list.has_keyboard(), "and gives the list no keyboard")
	_eq(hud.world_rect(), Rect2(96, 48, 536, 308), "the world gives the room back")
	_eq(hud.plan_width(), 660.0, "and a first plan is still made for the drawer closed")
	_eq([rooms.size(), remembered.size()], [2, 2], "said once more, and remembered")
	await _click(collapse)
	await _frames(2)
	hud.toggle_agent_list()
	await _frames(2)
	_check(hud.drawer_open() and hud.agent_list.has_keyboard(), "`A` opens it and the list takes the keyboard")
	_eq([rooms.size(), remembered.size()], [4, 4], "closed and opened: each said and remembered")
	await _click(collapse)
	await _frames(2)
	_check(not hud.drawer_open() and not hud.agent_list.has_keyboard(), "closing it lets the keyboard go")
	# Closed by the HUD's own call, not by a click that takes focus: the list
	# still lets the keyboard go.
	hud.toggle_agent_list()
	await _frames(2)
	_check(hud.agent_list.has_keyboard(), "`A` again: the list holds the keyboard")
	hud.close_drawer()
	await _frames(2)
	_check(not hud.drawer_open() and not hud.agent_list.has_keyboard(), "a list out of sight holds no keys")
	# The tab's number is the agents who need a human (show_attention()), kept
	# up to date while the drawer stays closed.
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	var waiting: Array[AttentionItem] = [_item(frame, "web:p1"), _item(frame, "api:p1")]
	hud.show_attention(waiting)
	_check(tab.text.ends_with("\n2"), "the closed tab counts two agents: %s" % tab.text.c_escape())
	hud.show_attention([])
	_check(tab.text.ends_with("\n0"), "and none again: %s" % tab.text.c_escape())
	# A WORKING / IDLE counter's filter opens the drawer: a filtered list out of sight says nothing.
	hud.toggle_list_filter([AgentListModel.Presence.WORKING])
	await _frames(2)
	_check(hud.drawer_open() and holder.is_visible_in_tree(), "the list's filter opens the drawer")
	_check(not hud.agent_list.has_keyboard(), "and takes no keyboard")
	hud.toggle_list_filter([AgentListModel.Presence.WORKING])


## Closed, the drawer's tab spells AGENTS and, a whole line below the S, the
## number of agents who need a human: the number never reads as a letter. The
## tab still fits the right column at its shortest (the 480x320 minimum with the
## staff panel opened), clear of the panel.
func test_the_closed_tab_sets_its_number_a_line_apart() -> void:
	await _hud()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	await _click(hud.get_node("%Collapse"))
	await _frames(2)
	var tab: Button = hud.get_node("%DrawerTab")
	_check(tab.is_visible_in_tree(), "closed to its tab")
	var lines := tab.text.split("\n")
	var s_at := lines.find("S")
	_check(s_at > 0, "the tab spells AGENTS: %s" % tab.text.c_escape())
	_eq(lines[lines.size() - 1], "0", "and ends with the number")
	var letters := "\n".join(lines.slice(0, s_at + 1))
	var number := lines[lines.size() - 1]
	# The same button, off to the side, measures what a line costs in the tab.
	var probe := Button.new()
	probe.theme_type_variation = tab.theme_type_variation
	tab.get_parent().add_child(probe)
	var heights: Array[float] = []
	for text: String in [tab.text, letters + "\n" + number, letters]:
		probe.text = text
		await _frames(1)
		heights.append(probe.get_minimum_size().y)
	probe.free()
	_eq(heights[0], tab.get_minimum_size().y, "the probe measures as the tab does")
	var line := heights[1] - heights[2]
	_check(line > 0.0, "a line takes room: %s" % [heights])
	_check(heights[0] - heights[1] >= line, "a whole line stands between the S and the number: %s" % [heights])
	hud.fit(Vector2(480, 320))
	hud.expand_card()
	await _frames(2)
	var column := hud.right_column.get_global_rect()
	_eq(column.size.y, 120.0, "the column at its shortest")
	_check(column.encloses(tab.get_global_rect()), "the tab fits it: %s in %s" % [tab.get_global_rect(), column])
	_check(not tab.get_global_rect().intersects(hud.inspector.get_global_rect()), "clear of the staff panel")


## NEXT says what a press does and to whom, and a press asks for exactly
## that; on the one line from 640 wide `NEXT:`, the verb and whom, and the wait
## in a row. An office that cannot write says no verb, only whom and herdr's
## state. With nobody next it says so and is off, and a press asks for nothing.
func test_the_next_button_says_who_n_would_pick() -> void:
	await _hud()
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	hud.show_agents(frame, [], [], "", 0)
	var blocked := frame.pane(_local("web:p1"))
	hud.inspector.show_next(NextModel.of(blocked, "", true))
	hud.inspector.set_next_wait("12m (N)")
	await _frames(2)
	var button: Button = hud.inspector.get_node("%NextButton")
	var line: Label = hud.inspector.get_node("%NextLine")
	var wait: Label = hud.inspector.get_node("%NextWait")
	_eq(line.text, "Answer CLAUDE web", "what a press does, to whom, where")
	_eq(wait.text, "12m (N)", "how long, and the key")
	_check(hud.card_compact() and wait.is_visible_in_tree(), "on the one line, the wait in the row")
	var title: Control = hud.inspector.get_node("%NextTitle")
	_check(title.is_visible_in_tree(), "after `NEXT:`")
	_check(
		(
			title.get_global_rect().end.x <= line.get_global_rect().position.x
			and line.get_global_rect().end.x <= wait.get_global_rect().position.x
		),
		"`NEXT:`, whom and the wait in a row"
	)
	_check(button.is_visible_in_tree() and not button.disabled, "on")
	_check(hud.inspector.get_global_rect().encloses(button.get_global_rect()), "at the panel's right end")
	for label: Control in [title, line, wait]:
		var across := label.get_global_rect()
		var room := button.get_global_rect()
		_check(
			across.position.x >= room.position.x and across.end.x <= room.end.x,
			"%s across the button on the line: %s in %s" % [label.name, across, room]
		)
	var needed := (
		wait
		. get_theme_font("font")
		. get_string_size(wait.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wait.get_theme_font_size("font_size"))
		. x
	)
	_check(needed <= wait.size.x + 0.5, "the wait whole in the row: %.1f of %.1f" % [needed, wait.size.x])
	await _open_staff()
	_eq(line.text, "Answer CLAUDE web", "at full height the same words")
	for label: Control in [line, wait]:
		_check(button.get_global_rect().encloses(label.get_global_rect()), "%s inside the button" % label.name)
	var asked: Array[bool] = []
	hud.next_requested.connect(func() -> void: asked.append(true))
	await _click(button)
	_eq(asked.size(), 1, "a press asks for N")
	hud.inspector.show_next(NextModel.of(blocked, "bee", true))
	_eq(line.text, "Answer CLAUDE web @ bee", "with more than one machine, which one")
	var unread := frame.pane(_local("web:p2"))
	hud.inspector.show_next(NextModel.of(unread, "", true))
	_eq(line.text, "Read %s web" % unread.provider.to_upper(), "a done one is read")
	hud.inspector.show_next(NextModel.of(blocked, ""))
	_eq(line.text, "CLAUDE web · blocked", "no verb where the office cannot write: whom and why")
	hud.inspector.show_next(null)
	await _frames(1)
	_eq(line.text, "All clear", "nobody next")
	_eq(wait.text, "", "waiting for nothing")
	_check(button.disabled, "and off")
	await _click(button)
	_eq(asked.size(), 1, "an off NEXT asks for nothing")


func test_world_rect_keeps_clear_of_the_column_and_the_list_takes_the_wheel() -> void:
	await _hud()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	_eq(hud.world_rect(), Rect2(96, 48, 536, 308), "the world stops where the column starts")
	# The panel opened, as while a card is read: the list is shorter than its rows.
	await _open_staff()
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	var at := scroll.get_global_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = at
	wheel.global_position = at
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	await process_frame
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "the list is taller than its box")
	_check(scroll.scroll_vertical > 0, "the wheel scrolls it")
	_eq(recorder.wheels, 0, "and goes no further")


## A slot takes room from the world only while it is shown: the staff panel,
## shown, stops the world and both side columns above it; hidden, it gives the
## room back (down to the NEWS strip under it), and shown again it takes it
## again. Each change is said once through room_changed, so the office can lay
## the world out again.
func test_a_hidden_slot_takes_no_room_and_a_shown_one_does() -> void:
	await _hud()
	var changes: Array[bool] = []
	hud.room_changed.connect(func() -> void: changes.append(true))
	var shown := Rect2(96, 48, 536, 308)
	_eq(hud.world_rect(), shown, "shown, the world stops above the staff panel's card")
	_eq(hud.spaces.offset_bottom, -124.0, "and so does the left column")
	_eq(hud.right_column.offset_bottom, -124.0, "and the right one")
	_eq(hud.right_column.get_global_rect().end.y, 356.0, "the column really ends there")
	var staff: Control = hud.get_node("%Staff")
	staff.visible = false
	hud.fit(Vector2(800, 480))
	# 456 - 16: the NEWS strip still stands along the bottom.
	_eq(hud.world_rect(), Rect2(96, 48, 536, 392), "hidden, the room comes back")
	_eq(hud.spaces.offset_bottom, -40.0, "to the left column")
	_eq(hud.right_column.offset_bottom, -40.0, "and the right one")
	_eq(changes.size(), 1, "said once")
	hud.fit(Vector2(800, 480))
	_eq(changes.size(), 1, "the same room again is not a change")
	staff.visible = true
	hud.fit(Vector2(800, 480))
	_eq(hud.world_rect(), shown, "shown again, the world stops above it")
	_eq(hud.right_column.offset_bottom, -124.0, "and so do the columns")
	_eq(changes.size(), 2, "said once more")
	await _frames(2)
	_eq(hud.right_column.get_global_rect().end.y, 356.0, "the column really ends there")


## The NEWS strip takes the screen's bottom line, 20 high and 16 in, and the
## staff panel stands 4 above it (at 800x480 its card, at 480x320 its line),
## lifted whole by the 12 the strip takes; a click on the strip is its own. At
## 480x320 it stays under the line; only the panel opened to full height there
## (answer mode, or Enter on it) takes its 12 back, and folding the panel brings
## the strip back. Each change is said once through room_changed, a new window
## that turns the card into the line (or back) included.
func test_the_news_slot_takes_the_bottom_and_moves_the_staff_panel_up() -> void:
	await _hud()
	var changes: Array[bool] = []
	hud.room_changed.connect(func() -> void: changes.append(true))
	var news: Control = hud.get_node("%News")
	_check(news.visible, "the strip shows")
	_eq(hud.placed(news), Rect2(16, 456, 768, 20), "along the bottom, 16 in, 4 up")
	_eq(news.get_global_rect(), Rect2(16, 456, 768, 20), "and really stands there")
	_eq(hud.placed(hud.staff), Rect2(16, 372, 768, 80), "the staff panel's card 4 above it")
	_eq(hud.staff.get_global_rect(), Rect2(16, 372, 768, 80), "and it really does")
	_eq(hud.world_rect(), Rect2(96, 48, 536, 308), "the world 16 above that")
	await _click_at(news.get_global_rect().get_center())
	_eq(recorder.wheels, 0, "a click on the strip goes no further")
	hud.fit(Vector2(480, 320))
	_check(news.visible and hud.card_compact(), "at 480x320 the strip stays, under the compact line")
	_eq(hud.placed(news), Rect2(16, 296, 448, 20), "along that bottom")
	_eq(hud.placed(hud.staff), Rect2(16, 264, 448, 28), "the compact line 4 above it")
	_eq(hud.world_rect(), Rect2(96, 48, 216, 200), "the world 216x200, the drawer open")
	# The card became the line: its edge moved with the window, said once.
	_eq(changes.size(), 1, "the card's edge moved to the line's")
	hud.expand_card()
	_check(not news.visible, "the panel opened to full height there takes the strip's room")
	_eq(hud.placed(hud.staff), Rect2(16, 176, 448, 128), "and stands where it did without it")
	_eq(hud.world_rect(), Rect2(96, 48, 216, 112), "the world 216x112 above it")
	_eq(changes.size(), 2, "said once")
	hud.compact_card()
	_check(news.visible, "folded back, the strip is back")
	_eq(hud.placed(hud.staff), Rect2(16, 264, 448, 28), "under the line again")
	_eq(changes.size(), 3, "said once more")
	hud.fit(Vector2(800, 480))
	_check(news.visible, "and at 800x480")
	_eq(hud.placed(hud.staff), Rect2(16, 372, 768, 80), "the panel's card stands above it")
	_eq(hud.world_rect(), Rect2(96, 48, 536, 308), "and the world is 536x308")
	_eq(changes.size(), 4, "the line became the card again: said once more")


func test_selected_row_is_highlighted_and_revealed() -> void:
	await _hud()
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	hud.show_agents(frame, [], [], _local("api:p1"), 0)
	await _frames(3)
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	_eq(scroll.scroll_vertical, 0, "the list opens at its top, on who is waiting")
	var row := hud.agent_list.row_for(_local("api:p1"))
	_eq(row.theme_type_variation, &"ListRowCurrent", "the selected pane is highlighted")
	hud.agent_list.set_collapsed(AgentListModel.FLAT_SHELLS, false)
	hud.show_agents(frame, [], [], _local("notes:p1"), 0)
	await _frames(4)
	var shell := hud.agent_list.row_for(_local("notes:p1"))
	_eq(shell.theme_type_variation, &"ListRowCurrent", "a new selection moves the highlight")
	_eq(row.theme_type_variation, &"ListRow", "off the old one")
	var box := scroll.get_global_rect()
	_check(box.encloses(shell.get_global_rect()), "and scrolls it into view")


## Carried over from the retired attention UI suite, opened up (expand_card())
## since the card is a compact header at this size: the whole card, at the
## smallest screen, keeps every identity it shows.


func test_inspector_keeps_complete_identity_in_compact_details() -> void:
	await _hud(Vector2i(480, 320))
	var pane := PaneModel.new()
	pane.pane_id = "pane-1"
	pane.terminal_id = "terminal-stable-identity"
	pane.provider = "claude"
	pane.state = "blocked"
	pane.label = "一条非常长但必须完整保留的工作标签 / ".repeat(3)
	pane.cwd = "/workspace/a-very-long-repository/worktrees/task-one"
	pane.foreground_cwd = pane.cwd + "/nested/frontend"
	pane.terminal_title = "A long terminal title ".repeat(10)
	pane.session = AgentSessionIdentity.new()
	pane.session.provider = "claude"
	pane.session.source = "hook"
	pane.session.kind = "session_id"
	pane.session.value = "session-identity-that-must-never-be-lost-by-truncation"
	hud.inspector.show_pane(pane, "Remote", false)
	# The whole card, as it opens up for answering at this size.
	hud.expand_card()
	await process_frame
	await process_frame
	var label: Label = hud.inspector.get_node("%PaneLabel")
	var cwd: Label = hud.inspector.get_node("%Cwd")
	var foreground: Label = hud.inspector.get_node("%ForegroundCwd")
	var session_label: Label = hud.inspector.get_node("%Session")
	var pane_id: Label = hud.inspector.get_node("%PaneId")
	var caption: Label = hud.inspector.get_node("%Caption")
	_eq(label.tooltip_text, pane.label, "complete pane label survives clipping")
	_check(cwd.tooltip_text.contains(pane.cwd), "working-directory tooltip preserves the full path")
	_check(
		foreground.visible and foreground.tooltip_text.contains(pane.foreground_cwd), "distinct foreground cwd is shown"
	)
	_check(
		session_label.visible and session_label.tooltip_text.contains(pane.session.value),
		"complete session remains inspectable"
	)
	_check(pane_id.tooltip_text.contains(pane.terminal_id), "terminal identity is available with pane identity")
	_eq(caption.tooltip_text, "Launch status not reported", "missing launch association stays explicit")
	var footnote: Label = hud.inspector.get_node("%Footnote")
	_check(
		hud.inspector.get_global_rect().encloses(footnote.get_global_rect()),
		"small-window footnote stays inside inspector"
	)
	pane.session = null
	pane.label = ""
	pane.foreground_cwd = pane.cwd
	pane.starting_known = true
	hud.inspector.show_pane(pane, "", false)
	_eq(caption.tooltip_text, "Not launching", "known false remains distinct from an absent launch status")
	_check(
		not label.visible and not foreground.visible and not session_label.visible,
		"missing details do not leave stale fields"
	)


## Long labels at the smallest screen, with the list raised over the card: no
## row pushes the list wider, the panel stays in the window, and a theme switch
## re-dresses the same rows.
func test_long_labels_and_a_theme_switch_keep_rows_inside_the_list() -> void:
	await _hud(Vector2i(480, 320))
	var raw := _with(_snapshot(FLOORS), "web:p1", {"label": "很长的终端标题 ".repeat(50)})
	hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", 0)
	hud.toggle_agent_list()
	await _frames(2)
	await _frames(3)
	var row := hud.agent_list.row_for(_local("web:p1"))
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	_check(row.size.x <= scroll.size.x, "long content does not force horizontal overflow")
	var window := Rect2(Vector2.ZERO, Vector2(root.size))
	_check(window.encloses(hud.agent_list.get_global_rect()), "the list fits the small window")
	var filter: LineEdit = hud.agent_list.get_node("%Filter")
	_check(hud.agent_list.get_global_rect().encloses(filter.get_global_rect()), "the filter box stays inside it")
	hud.dress(second, pen.font)
	await process_frame
	_eq(hud.agent_list.row_for(_local("web:p1")), row, "a theme switch reuses rows")
	_eq(hud.agent_list.art, second, "the list's frame takes the new pack")


## Only the rows inside the scroll box draw their badge: the renderer culls a
## row's labels scrolled out of it, but not its Sprite2D (measured: 29 draw
## calls at 80 panes). A waiting row out of view keeps pulsing and its wait.
func test_badges_draw_only_inside_the_scroll_box() -> void:
	# 400 high: the list above the opened staff panel is 200 units, too short for every row.
	await _hud(Vector2i(800, 400))
	await _open_staff()
	var raw := _snapshot(FLOORS)
	for pane_id: String in ["api:p1", "api:p2", "api:p4", "infra:p2", "infra:p3", "web:p2", "data:p1", "data:p2"]:
		raw = _with(raw, pane_id, {"agent_status": "blocked", "launch_pending": false})
	hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", 0)
	await _frames(3)
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	var box := scroll.get_global_rect()
	var inside := 0
	var outside := 0
	for key in hud.agent_list.shown_keys():
		var row := hud.agent_list.row_for(key)
		if row == null:
			continue
		var seen := box.intersects(row.get_global_rect())
		_eq(row.icon_badge().visible, seen and not row.mark().is_empty(), "%s draws its badge only in view" % key)
		if seen:
			inside += 1
		else:
			outside += 1
	_check(inside > 0 and outside > 0, "the list is longer than its box: %d in, %d out" % [inside, outside])
	var waiting: Array = []
	for key in hud.agent_list.shown_keys():
		if hud.agent_list.entry_for(key).parent == AgentListModel.FLAT_WAITING:
			waiting.append(key)
	var last := hud.agent_list.row_for(str(waiting.back()))
	_check(not box.intersects(last.get_global_rect()), "a waiting row below the box")
	_eq(last.icon_badge().state, ArtContract.STATE_BLOCKED, "still pulses")
	_check(last.icon_badge().wait == last.get_node("%Tail"), "and still has its wait written")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = box.get_center()
	wheel.global_position = box.get_center()
	for step in 12:
		Input.parse_input_event(wheel)
		Input.flush_buffered_events()
		await process_frame
	await _frames(2)
	_check(scroll.scroll_vertical > 0, "the wheel scrolled the list")
	for key in hud.agent_list.shown_keys():
		var row := hud.agent_list.row_for(key)
		if row != null:
			var seen := box.intersects(row.get_global_rect())
			_eq(row.icon_badge().visible, seen and not row.mark().is_empty(), "after scrolling, %s too" % key)


## The row actions by keyboard alone: with
## the list holding the keyboard, the Menu key (or Shift+F10, or `.`) opens the
## cursor row's menu; Up/Down and Enter choose from it, Escape closes it, and
## the list keeps the keyboard. A row without actions opens nothing.
func test_row_menu_opens_from_the_keyboard() -> void:
	await _hud()
	var told: Array[Array] = []
	hud.attention_snooze_requested.connect(func(id: String, seconds: int) -> void: told.append([id, seconds]))
	hud.attention_hidden_changed.connect(func(id: String, hidden: bool) -> void: told.append([id, hidden]))
	var frame := _frame([_machine(LOCAL, _snapshot(FLOORS))])
	var item := _item(frame, "web:p1")
	hud.show_agents(frame, [item], [], _local("web:p1"), 0)
	await _frames(2)
	hud.toggle_agent_list()
	await _frames(2)
	_eq(hud.agent_list.cursor(), _local("web:p1"), "the cursor is on the waiting row")
	var menu := hud.agent_list.actions_menu()
	await _key(KEY_MENU)
	_check(menu.visible, "the Menu key opens its menu")
	for step in menu.item_count + 1:
		if menu.get_focused_item() >= 0 and menu.get_item_text(menu.get_focused_item()) == "Hide":
			break
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_eq(told, [[item.id, true]], "Down and Enter choose Hide from it")
	_check(not menu.visible, "which closes it")
	_check(hud.agent_list.has_keyboard(), "and the list keeps the keyboard")
	told.clear()
	var shift_f10 := _key_event(KEY_F10)
	shift_f10.shift_pressed = true
	Input.parse_input_event(shift_f10)
	Input.flush_buffered_events()
	await process_frame
	shift_f10.pressed = false
	Input.parse_input_event(shift_f10)
	Input.flush_buffered_events()
	await process_frame
	_check(menu.visible, "Shift+F10 opens it too")
	await _key(KEY_ESCAPE)
	_check(not menu.visible, "Escape closes it")
	_check(hud.agent_list.has_keyboard(), "and leaves the list its keyboard")
	await _key(KEY_PERIOD)
	_check(menu.visible, "so does `.`")
	await _key(KEY_ESCAPE)
	_eq(told, [], "nothing was chosen")
	await _key(KEY_DOWN)
	while hud.agent_list.entry_for(hud.agent_list.cursor()).item != null:
		await _key(KEY_DOWN)
	await _key(KEY_MENU)
	_check(not menu.visible, "a row without actions opens no menu")
	await _key(KEY_ESCAPE)


## A History line locates its pane only while the pane is the terminal the
## StateLog saw: another terminal in it greys View out (Details) and a
## double-click picks nothing; the same terminal again locates it.
func test_a_history_line_locates_only_the_same_terminal() -> void:
	await _hud()
	var located: Array[String] = []
	hud.history_locate_requested.connect(func(key: String) -> void: located.append(key))
	var raw := _snapshot(FLOORS)
	var ledger := StateLog.new()
	_log(ledger, _frame([_machine(LOCAL, raw)]), LOCAL, true, 1000)
	var ended := _with(raw, "infra:p1", {"agent_status": "idle"})
	_log(ledger, _frame([_machine(LOCAL, ended)]), LOCAL, true, 2000)
	# The frame already shows another terminal in the pane; the log saw the first.
	var other := _frame([_machine(LOCAL, _with(ended, "infra:p1", {"terminal_id": "term-other"}))])
	var live: Dictionary[String, bool] = {LOCAL: true}
	hud.show_agents(other, [], AgentHistory.of(ledger, other, live, 3000), "", 3000)
	hud.agent_list.set_collapsed(AgentListModel.FLAT_HISTORY, false)
	await _frames(2)
	var key := "history:" + _local("infra:p1")
	var row := hud.agent_list.row_for(key)
	_check(row != null, "the pane that stopped waiting has a History line")
	if row == null:
		return
	var note: Label = row.get_node("%Tail")
	_eq(note.text, "", "it ended: no word on the row")
	_check(row.get_tooltip(Vector2.ZERO).contains("ENDED"), "the tooltip says so")
	await _choose(row, "Details", true, true)
	await _scroll_to(row)
	await _double_click(row)
	_eq(located, [], "another terminal in the pane is not located, by View or a double-click")
	var same := _frame([_machine(LOCAL, ended)])
	hud.show_agents(same, [], AgentHistory.of(ledger, same, live, 3000), "", 3000)
	await _frames(2)
	await _double_click(row)
	_eq(located, [_local("infra:p1")], "the same terminal is")


## A History line is about the pane's current agent run: another terminal in
## the pane (herdr's REPLACED, or one that came up while the machine was away)
## inherits nothing the run before it waited for, and its own waits count from
## one again.
func test_a_new_agent_run_in_the_pane_starts_its_history_over() -> void:
	var raw := _snapshot(FLOORS)
	var live: Dictionary[String, bool] = {LOCAL: true}
	var ledger := StateLog.new()
	_log(ledger, _frame([_machine(LOCAL, raw)]), LOCAL, true, 1000)
	var ended := _with(_with(raw, "web:p2", {"agent_status": "idle"}), "infra:p1", {"agent_status": "idle"})
	ended = _with(ended, "infra:p2", {"agent_status": "idle"})
	var frame := _frame([_machine(LOCAL, ended)])
	_log(ledger, frame, LOCAL, true, 2000)
	var keys := PackedStringArray()
	for line in AgentHistory.of(ledger, frame, live, 2000):
		keys.append(line.key)
	_eq(
		keys,
		PackedStringArray([_local("infra:p1"), _local("infra:p2"), _local("web:p2")]),
		"a blocked and two done that ended: three lines"
	)
	# web:p2 gets another terminal (herdr says REPLACED), idle.
	var replaced := _with(ended, "web:p2", {"terminal_id": "term-web-p2-next"})
	frame = _frame([_machine(LOCAL, replaced)])
	_log(ledger, frame, LOCAL, true, 3000)
	keys.clear()
	for line in AgentHistory.of(ledger, frame, live, 3000):
		keys.append(line.key)
	_eq(
		keys,
		PackedStringArray([_local("infra:p1"), _local("infra:p2")]),
		"the new terminal inherits nothing of the done before it"
	)
	# infra:p1 (was blocked) and infra:p2 (was done) get other terminals while
	# Local is away: nobody announced them.
	_log(ledger, frame, LOCAL, false, 4000)
	var away := _with(replaced, "infra:p1", {"terminal_id": "term-infra-p1-next"})
	away = _with(away, "infra:p2", {"terminal_id": "term-infra-p2-next"})
	frame = _frame([_machine(LOCAL, away)])
	_log(ledger, frame, LOCAL, true, 5000)
	_eq(AgentHistory.of(ledger, frame, live, 5000).size(), 0, "nor ones that came up unannounced, blocked or done")
	# The new run waits once and stops: its line counts one wait, not two.
	_log(ledger, _frame([_machine(LOCAL, _with(away, "infra:p1", {"agent_status": "blocked"}))]), LOCAL, true, 6000)
	_log(ledger, frame, LOCAL, true, 7000)
	var lines := AgentHistory.of(ledger, frame, live, 7000)
	_eq(lines.size(), 1, "a wait of its own is a line again")
	if lines.size() == 1:
		_eq(lines[0].key, _local("infra:p1"), "infra:p1's")
		_eq(lines[0].times, 1, "blocked once in this run")
		_eq(lines[0].blocked_msec, 1000, "for its own second")
		_check(lines[0].locatable, "and it is this terminal")


## The History lines are built again only when something they are made of
## changed: the log (its version), the frame's panes, or a machine going away;
## a refresh with none of those reads the lines it has.
func test_history_is_built_again_only_when_the_log_or_the_panes_change() -> void:
	var raw := _snapshot(FLOORS)
	var live: Dictionary[String, bool] = {LOCAL: true}
	var ledger := StateLog.new()
	_log(ledger, _frame([_machine(LOCAL, raw)]), LOCAL, true, 1000)
	var ended := _with(raw, "infra:p1", {"agent_status": "idle"})
	_log(ledger, _frame([_machine(LOCAL, ended)]), LOCAL, true, 2000)
	var cache := AgentHistory.Cache.new()
	var first := cache.lines(ledger, _frame([_machine(LOCAL, ended)]), live, 2000)
	_eq(cache.builds, 1, "built once")
	_eq(first.size(), 1, "infra:p1's line")
	var again := cache.lines(ledger, _frame([_machine(LOCAL, ended)]), live, 3000)
	_eq(cache.builds, 1, "a refresh with the same log and panes builds nothing")
	_check(again == first, "and reads the same lines")
	_log(ledger, _frame([_machine(LOCAL, ended)]), LOCAL, true, 3500)
	cache.lines(ledger, _frame([_machine(LOCAL, ended)]), live, 3500)
	_eq(cache.builds, 1, "nor does an observation that changed nothing in the log")
	var working := _with(ended, "infra:p1", {"agent_status": "working"})
	_log(ledger, _frame([_machine(LOCAL, working)]), LOCAL, true, 4000)
	cache.lines(ledger, _frame([_machine(LOCAL, working)]), live, 4000)
	_eq(cache.builds, 2, "a change in the log builds again")
	var other := _frame([_machine(LOCAL, _with(working, "infra:p1", {"terminal_id": "term-other"}))])
	var moved := cache.lines(ledger, other, live, 4000)
	_eq(cache.builds, 3, "a pane with another terminal builds again")
	_check(not moved[0].locatable, "and the line knows it cannot be located")
	var away: Dictionary[String, bool] = {LOCAL: false}
	cache.lines(ledger, other, away, 4000)
	_eq(cache.builds, 4, "so does a machine going away")


## More rows than the list's box show the drawer's thin scroll bar (the
## theme's DrawerScroll, never focused) inside the list, the rows ending 4
## units left of it, and the wheel scrolls them.
func test_rows_past_the_bottom_show_the_drawer_scroll_bar() -> void:
	await _hud()
	# The panel opened, as while a card is read: the list is shorter than its rows.
	await _open_staff()
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	var bar := scroll.get_v_scroll_bar()
	_check(bar.max_value > scroll.size.y, "the rows are taller than the box")
	_check(bar.visible, "so the scroll bar shows")
	_eq(bar.theme_type_variation, &"DrawerScroll", "the theme's thin one")
	_eq(bar.focus_mode, Control.FOCUS_NONE, "never focused: the arrows stay the list's cursor")
	var edge := bar.get_global_rect()
	_check(edge.end.x <= hud.agent_list.get_global_rect().end.x, "inside the list")
	var rows := 0
	for key in hud.agent_list.shown_keys():
		var line: Control = hud.agent_list.row_for(key)
		if line == null:
			line = hud.agent_list.group_for(key)
		if line != null and line.get_global_rect().intersects(scroll.get_global_rect()):
			rows += 1
			_check(
				line.get_global_rect().end.x <= edge.position.x - HudTheme.DRAWER_BAR_GAP,
				"%s ends the gap left of the bar (%s, bar at %s)" % [key, line.get_global_rect().end.x, edge.position.x]
			)
	_check(rows > 0, "rows were measured")
	var at := scroll.get_global_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = at
	wheel.global_position = at
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	await _frames(2)
	_check(scroll.scroll_vertical > 0, "the wheel scrolls the rows")


## Rows that fit show no bar, but keep its room: they end where they end when
## a bar shows, so a row's right edge never moves as the list grows.
func test_rows_that_fit_leave_the_bars_room_and_no_bar() -> void:
	await _hud()
	# The panel opened, so that many panes are more than the list's box holds.
	await _open_staff()
	var few := _only(_snapshot(FLOORS), "web:p1")
	hud.show_agents(_frame([_machine(LOCAL, few)]), [], [], "", 0)
	await _frames(2)
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	var bar := scroll.get_v_scroll_bar()
	_check(not bar.visible, "one pane fits: no bar")
	var row := hud.agent_list.row_for(_local("web:p1"))
	var fit := row.get_global_rect().end.x
	var room := bar.get_combined_minimum_size().x + HudTheme.DRAWER_BAR_GAP
	_check(fit <= scroll.get_global_rect().end.x - room, "the row leaves the bar's room and the gap (%s)" % fit)
	hud.show_agents(_frame([_machine(LOCAL, _snapshot(FLOORS))]), [], [], "", 0)
	await _frames(2)
	_check(bar.visible, "many panes: the bar shows")
	_eq(row.get_global_rect().end.x, fit, "and the row's right edge has not moved")


## The bar's room comes out of the drawer's right padding, not out of the
## rows. A row keeps its width (126 units at every screen size, the tab 52
## units on a blocked row and 16 on an UNREAD one, where `CODEX ui` / `CODEX rev`
## fit whole), with the bar showing or not, at 800x480, 960x480 and 480x320.
func test_the_bars_room_leaves_the_rows_their_width() -> void:
	var widths: Dictionary[String, float] = {"web:p1": 52.0, "web:p2": 16.0, "infra:p2": 16.0}
	for size: Vector2i in [Vector2i(800, 480), Vector2i(960, 480), Vector2i(480, 320)]:
		for many: bool in [true, false]:
			await _hud(size)
			# The panel opened, so that many panes are more than the list's box holds.
			await _open_staff()
			var snapshot := _snapshot(FLOORS) if many else _only(_snapshot(FLOORS), "web:p1")
			hud.show_agents(_frame([_machine(LOCAL, snapshot)]), [], [], "", 0)
			await _frames(2)
			var bar := (hud.agent_list.get_node("%Scroll") as ScrollContainer).get_v_scroll_bar()
			_eq(bar.visible, many, "%s: the bar shows only with many rows" % size)
			if many:
				_eq(bar.size.x, float(HudTheme.DRAWER_BAR), "%s: as wide as the theme says" % size)
			for id: String in widths:
				var row := hud.agent_list.row_for(_local(id))
				if row == null:
					continue
				var detail: Label = row.get_node("%Detail")
				var when := "%s %s, bar %s" % [size, id, "shown" if many else "hidden"]
				_check(row.size.x >= 126.0, "%s: the row is 126 wide: %.1f" % [when, row.size.x])
				_check(detail.size.x >= widths[id], "%s: its tab has %.0f: %.1f" % [when, widths[id], detail.size.x])
			hud.queue_free()
			await _frames(1)


# --- helpers --------------------------------------------------------------------


## A closed drawer's list renders nothing: each refresh only keeps what it was
## given, and opening the drawer renders the latest once. Closed again, it keeps
## its nodes; a reader renders what it reads.
func test_a_closed_drawer_renders_the_list_once_when_it_opens() -> void:
	await _hud(Vector2i(800, 480), false)
	var list := hud.agent_list
	var raw := _snapshot(FLOORS)
	var blocked := _with(raw, "api:p1", {"agent_status": "blocked"})
	var before := list.renders
	for index in 5:
		hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", index)
		await _frames(1)
	hud.show_agents(_frame([_machine(LOCAL, blocked)]), [], [], "", 9)
	await _frames(2)
	_eq(list.renders - before, 0, "six refreshes with the drawer closed render nothing")
	await _click(hud.get_node("%DrawerTab"))
	await _frames(2)
	_check(hud.drawer_open(), "a real click on the tab opens the drawer")
	_eq(list.renders - before, 1, "which renders the list once")
	_eq(list.entry_for(_local("api:p1")).parent, AgentListModel.FLAT_WAITING, "from the latest refresh")
	var row := list.row_for(_local("api:p1"))
	_check(row.is_visible_in_tree(), "its row on screen")
	_eq(row.mark(), ArtContract.STATE_BLOCKED, "saying blocked")
	hud.show_agents(_frame([_machine(LOCAL, blocked)]), [], [], "", 10)
	_eq(list.renders - before, 2, "open, a refresh renders at once")
	await _click(hud.get_node("%Collapse"))
	await _frames(2)
	_check(not hud.drawer_open(), "the drawer's ▶ closes it")
	var closed_at := list.renders
	for index in 3:
		hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", 20 + index)
		await _frames(1)
	_eq(list.renders, closed_at, "closed again, refreshes render nothing")
	_check(is_instance_valid(row) and row.get_parent() != null, "and the rows stay where they are")
	hud.show_agents(_frame([_machine(LOCAL, _without(raw, "api:p1"))]), [], [], "", 30)
	_check(not list.shown_keys().has(_local("api:p1")), "a reader sees the latest refresh, closed or not")
	_eq(list.renders, closed_at + 1, "rendered for it once")
	_check(list.row_for(_local("api:p1")) == null, "the closed pane's row is gone")
	_eq(list.renders, closed_at + 1, "and a second reader renders nothing more")


## The drawer's EVENTS page hides the list as a closed drawer does: refreshes
## render nothing until a real click brings AGENTS back, which renders once
## with the same row nodes.
func test_the_events_page_renders_the_list_once_when_agents_is_back() -> void:
	await _hud()
	var list := hud.agent_list
	var raw := _snapshot(FLOORS)
	hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], "", 0)
	await _frames(2)
	var id := list.row_for(_local("api:p1")).get_instance_id()
	await _click_tab(OfficeHud.DrawerTab.EVENTS)
	_eq(hud.drawer_tab(), OfficeHud.DrawerTab.EVENTS, "a real click shows EVENTS")
	_check(hud.drawer_open() and not list.is_visible_in_tree(), "the drawer open, the list out of sight")
	var before := list.renders
	for index in 3:
		hud.show_agents(_frame([_machine(LOCAL, _with(raw, "api:p1", {"agent_status": "blocked"}))]), [], [], "", index)
		await _frames(1)
	_eq(list.renders - before, 0, "three refreshes on EVENTS render nothing")
	await _click_tab(OfficeHud.DrawerTab.AGENTS)
	_eq(hud.drawer_tab(), OfficeHud.DrawerTab.AGENTS, "a real click brings AGENTS back")
	_eq(list.renders - before, 1, "which renders the list once")
	_eq(list.row_for(_local("api:p1")).get_instance_id(), id, "with the same row")
	_eq(list.entry_for(_local("api:p1")).parent, AgentListModel.FLAT_WAITING, "moved by the latest refresh")


## `A` with the drawer closed: the list is rendered before it takes the
## keyboard, so its cursor lands on the pane the office selected while it was
## out of sight, not on an empty list.
func test_a_on_a_closed_drawer_renders_before_the_list_takes_the_keyboard() -> void:
	await _hud(Vector2i(800, 480), false)
	var list := hud.agent_list
	var raw := _snapshot(FLOORS)
	hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], _local("web:p1"), 0)
	hud.show_agents(_frame([_machine(LOCAL, raw)]), [], [], _local("api:p1"), 1)
	await _frames(2)
	hud.toggle_agent_list()
	await _frames(2)
	_check(hud.drawer_open() and list.has_keyboard(), "`A` opens the drawer and gives the list the keyboard")
	_eq(list.cursor(), _local("api:p1"), "its cursor on the pane selected while it was closed")
	_eq(list.row_for(_local("api:p1")).theme_type_variation, &"ListRowCurrent", "that row highlighted")


## A real click on the drawer's tab for `tab`.
func _click_tab(tab: OfficeHud.DrawerTab) -> void:
	var tabs := hud.drawer_tabs
	await _click_at(tabs.get_global_rect().position + tabs.get_tab_rect(tab).get_center())
	await _frames(2)


## A HUD on a `size` screen. Every run starts with the drawer closed:
## with `open_drawer` a real click on its tab opens it, as a viewer would, so
## the cases about the list find it on screen.
func _hud(size := Vector2i(800, 480), open_drawer := true) -> void:
	root.size = size
	hud = HUD_SCENE.instantiate()
	hud.dress(art, pen.font)
	root.add_child(hud)
	hud.fit(Vector2(size))
	recorder = Recorder.new()
	root.add_child(recorder)
	await process_frame
	await process_frame
	if open_drawer:
		await _click(hud.get_node("%DrawerTab"))
		await _frames(2)


## Open the staff panel up from its line, as Enter or `Open ⏎` would (the
## office's and a click's; here the HUD's own call), and let it settle.
func _open_staff() -> void:
	hud.expand_card()
	await _frames(2)


func _listen() -> void:
	hud.agent_picked.connect(func(key: String) -> void: said.append(["pick", key]))
	hud.monitor_requested.connect(func(key: String) -> void: said.append(["open", key]))


func _snapshot(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var file: Dictionary = parsed if parsed is Dictionary else {}
	return _dict(file, "snapshot")


func _with(snapshot: Dictionary, pane_id: String, changes: Dictionary) -> Dictionary:
	var copy := snapshot.duplicate(true)
	for pane: Dictionary in _list(copy, "panes"):
		if pane.get("pane_id") == pane_id:
			pane.merge(changes, true)
	return copy


func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var copy := snapshot.duplicate(true)
	var panes := _list(copy, "panes").filter(func(pane: Dictionary) -> bool: return pane.get("pane_id") != pane_id)
	copy["panes"] = panes
	return copy


## `snapshot` with pane `pane_id` its only pane.
func _only(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var copy := snapshot.duplicate(true)
	var panes := _list(copy, "panes").filter(func(pane: Dictionary) -> bool: return pane.get("pane_id") == pane_id)
	copy["panes"] = panes
	return copy


## Feed `ledger` what the fleet would hand it for machine `key` of `frame` at
## `now_msec`: every pane of it as a Sighting whose state began then, or the
## machine going offline.
func _log(ledger: StateLog, frame: OfficeFrame, key: String, online: bool, now_msec: int) -> void:
	var seen: Array[StateLog.Sighting] = []
	for building in frame.buildings:
		if building.key != key:
			continue
		for pane in building.all_panes:
			var sighting := StateLog.Sighting.new()
			sighting.pane_key = pane.key
			sighting.identity = "" if pane.terminal_id.is_empty() else pane.identity_key()
			sighting.status = pane.state
			sighting.starting = pane.starting
			sighting.agent = pane.provider
			sighting.space = pane.workspace_label
			sighting.tab = pane.tab_label
			sighting.terminal_id = pane.terminal_id
			sighting.since_unix = now_msec / 1000.0
			seen.append(sighting)
	ledger.observe(key, key.capitalize(), online, seen, now_msec, now_msec / 1000.0)


func _machine(key: String, raw: Dictionary, stale := false) -> MachineView:
	return MachineView.new(key, key.capitalize(), HerdrSnapshot.from_wire(raw), stale)


func _frame(machines: Array[MachineView]) -> OfficeFrame:
	return OfficeProjection.frame(machines, art.state_names())


## Give the seated panes the state starts the office would stamp.
func _stamp(frame: OfficeFrame, starts: Dictionary) -> void:
	for building in frame.buildings:
		for floor_model in building.zones:
			for room in floor_model.rooms:
				for pane in room.panes:
					pane.state_since = _number(starts, pane.pane_id, 1000.0)


func _local(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## A live attention record for Local's pane `pane_id`, as the store makes one.
func _item(frame: OfficeFrame, pane_id: String) -> AttentionItem:
	var pane := frame.pane(_local(pane_id))
	var item := AttentionItem.new()
	item.id = "attention:" + pane_id
	item.pane_key = pane.key
	item.identity_key = pane.identity_key()
	item.machine_key = LOCAL
	item.machine_label = "Local"
	item.provider = pane.provider
	item.title = pane.label
	item.tab_label = pane.tab_label
	item.workspace_label = pane.workspace_label
	item.state = pane.state
	item.active = true
	item.available = true
	return item


func _entry(entries: Array[AgentListModel.Entry], key: String) -> AgentListModel.Entry:
	for entry in entries:
		if entry.key == key:
			return entry
	return null


func _first(entries: Array[AgentListModel.Entry], kind: AgentListModel.Kind) -> AgentListModel.Entry:
	for entry in entries:
		if entry.kind == kind:
			return entry
	return null


func _children(entries: Array[AgentListModel.Entry], group: String) -> Array:
	var keys := []
	for entry in entries:
		if entry.parent == group:
			keys.append(entry.key)
	return keys


func _drawn_panes() -> PackedStringArray:
	var result := PackedStringArray()
	for key in hud.agent_list.shown_keys():
		var entry := hud.agent_list.entry_for(key)
		if entry.kind == AgentListModel.Kind.PANE:
			result.append(key)
	return result


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _scroll_to(control: Control) -> void:
	var scroll: ScrollContainer = hud.agent_list.get_node("%Scroll")
	scroll.ensure_control_visible(control)
	await _frames(2)


## Open `row`'s menu, by right-click or by its `⋯`, and choose `label` from it
## with the keyboard; `disabled` expects that entry to be greyed out instead.
func _choose(row: AgentListRow, label: String, right_click: bool, disabled := false) -> void:
	await _scroll_to(row)
	if right_click:
		await _click_at(row.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	else:
		await _click(row.get_node("%More"))
	var menu := hud.agent_list.actions_menu()
	_check(menu.visible, "the row's menu opened for " + label)
	var index := -1
	for at in menu.item_count:
		if menu.get_item_text(at) == label:
			index = at
	_check(index >= 0, "the menu offers " + label)
	if index < 0:
		menu.hide()
		return
	_eq(menu.is_item_disabled(index), disabled, "%s is %s" % [label, "off" if disabled else "on"])
	if disabled:
		menu.hide()
		await _frames(1)
		return
	for step in menu.item_count + 1:
		if menu.get_focused_item() == index:
			break
		await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	await _frames(1)


func _click(node: Node) -> void:
	if not node is Control:
		_fail("click target must be a Control")
		return
	var control: Control = node
	await _click_at(control.get_global_rect().get_center())


func _click_at(at: Vector2, button := MOUSE_BUTTON_LEFT, double := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.button_mask = (
			(MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		)
		event.pressed = pressed
		event.double_click = double and pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await process_frame


func _double_click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _click_at(at)
	await _click_at(at, MOUSE_BUTTON_LEFT, true)


func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _key(code: Key) -> void:
	var event := _key_event(code)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func _type(text: String) -> void:
	for character in text:
		var event := InputEventKey.new()
		event.keycode = OS.find_keycode_from_string(character.to_upper())
		event.unicode = character.unicode_at(0)
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
