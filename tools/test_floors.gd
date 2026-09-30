extends "res://tools/office_test_base.gd"
## The left column's FLOORS minimap:
## highest floor on top with each worktree's mezzanine hung just below its
## source floor, a strip of windows per floor lit by its panes' states, the
## shown floor's row highlighted alone, a stale building dimmed with no lit
## window, and the floor plate of a mezzanine; and the signposts over the
## world's right edge to the other floors with agents blocked on them. Clicks,
## hovers and keys go through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_floors.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## The most of the world's width the signposts may cover, in any window they
## show in. A third: a post is 108 of the narrowest world that shows them
## (OfficeHud.signposts_from, 360); below that they step aside for the rail.
const MAX_SIGNPOST_COVER := 1.0 / 3.0


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("floors-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var text := FileAccess.get_file_as_string("res://tools/fixtures/snapshot_worktrees.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_worktrees.json")
		quit(2)
		return
	var file: Dictionary = parsed
	# herdstead (1F) is the source of hud lane (1A) and data lane (1B); notes
	# (4F) has no worktree; ops lane (5F) is a worktree whose source is closed.
	fixture = _dict(file, "snapshot")
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "FLOORS TESTS"


# --- cases --------------------------------------------------------------------


## Highest floor on top, and a worktree's mezzanine hung just below the floor
## it was made from, with its checkout for a name (indented where the column
## says names; in the narrow rail its chip, `1A`, says it); a worktree whose
## source is not open stays a floor of its own.
func test_mezzanines_hang_below_their_source_floor() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_eq(
		minimap.row_keys(), [_floor("ops"), _floor("notes"), _floor("hs"), _floor("hud"), _floor("data")], "drawn order"
	)
	_eq(_chips(office), ["5F", "4F", "1F", "1A", "1B"], "a mezzanine's chip is its source's number and a letter")
	var indents := func() -> Array:
		return minimap.row_keys().map(func(key: String) -> bool: return _node(minimap.row_for(key), "%Indent").visible)
	_eq(indents.call(), [false, false, false, false, false], "the 800-wide rail indents nothing")
	office.test_screen = Vector2(1280, 480)
	office.refresh()
	await _frames(2)
	_eq(indents.call(), [false, false, false, true, true], "with the names, only the mezzanines are indented")
	_eq(_label(minimap.row_for(_floor("hud")), "%FloorLabel").text, "hud-lane", "a mezzanine reads as its checkout")
	_eq(_label(minimap.row_for(_floor("hs")), "%FloorLabel").text, "herdstead", "a floor reads as its workspace")
	_eq(_label(minimap.row_for(_floor("ops")), "%FloorLabel").text, "ops lane", "and so does an orphan worktree")
	_done(office)


## PageUp and PageDown walk the rows as drawn: down from a source floor into its
## mezzanines, up out of them back to it and on to the floor above. Each step
## shows its floor at once: the floor drawn, and the row highlighted.
func test_page_keys_step_through_the_rows_as_drawn() -> void:
	var office := await _live_office()
	_eq(office.navigator.shown_key, _floor("hs"), "herdr's focus is on 1F")
	var visited: Array[String] = []
	var drawn: Array[String] = []
	var highlighted: Array = []
	for code: Key in [KEY_PAGEDOWN, KEY_PAGEDOWN, KEY_PAGEDOWN, KEY_PAGEUP, KEY_PAGEUP, KEY_PAGEUP, KEY_PAGEUP]:
		var event := _key(code)
		await _parsed(event)
		event.pressed = false
		await _parsed(event)
		visited.append(office.navigator.shown_key)
		drawn.append(office.layout_plan().floor_key)
		highlighted.append_array(_current(office))
	var wanted: Array[String] = [
		_floor("hud"), _floor("data"), _floor("data"), _floor("hud"), _floor("hs"), _floor("notes"), _floor("ops")
	]
	_eq(visited, wanted, "1F, down into 1A and 1B, stops at the bottom, then back up past 1F to 4F and 5F")
	_eq(drawn, wanted, "each floor drawn the moment its key is up")
	_eq(highlighted, Array(wanted), "and each row highlighted in turn, alone")
	_done(office)


## One window per pane seated on the floor, lit by what its agent is doing: the
## state's own colour, idle lit plainly, a shell dark. Its tooltip names the
## agent and the state. A floor's counts stay beside it.
func test_windows_light_up_by_state_one_per_pane() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_eq(
		_looks(minimap.row_for(_floor("hs"))),
		[&"WindowWorking", &"WindowIdle", &"WindowDark"],
		"claude at work, codex idle, a shell"
	)
	_eq(_looks(minimap.row_for(_floor("hud"))), [&"WindowBlocked"], "a blocked agent's window")
	_eq(_looks(minimap.row_for(_floor("data"))), [&"WindowDone", &"WindowWorking"], "an UNREAD one, and one at work")
	_eq(
		_tips(minimap.row_for(_floor("hs"))),
		["claude · WORKING", "codex · IDLE", "shell"],
		"tooltips name agent and state"
	)
	_eq(_tips(minimap.row_for(_floor("hud"))), ["claude · NEEDS INPUT"], "in the pack's words")
	_check(_node(minimap.row_for(_floor("hud")), "%BlockedIcon").visible, "the blocked count stays beside it")
	# The 800-wide rail leaves the UNREAD count to the row's tooltip.
	_check(not _node(minimap.row_for(_floor("data")), "%DoneIcon").visible, "the rail shows no UNREAD icon")
	_check(minimap.row_for(_floor("data")).tooltip_text.contains("1 UNREAD"), "its tooltip counts the UNREAD one")
	var before := _window_ids(office)
	_feed(office, _with(fixture, "hs:p2", {"agent_status": "working"}))
	_eq(
		_looks(minimap.row_for(_floor("hs"))),
		[&"WindowWorking", &"WindowWorking", &"WindowDark"],
		"a state change relights the window"
	)
	_eq(_window_ids(office), before, "in place: no window is made or dropped for it")
	_done(office)


## Hovering a window shows its pane, and clicking one switches to its floor
## exactly as a click anywhere else on the row does.
func test_a_window_names_its_pane_and_a_click_on_it_switches_to_its_floor() -> void:
	var office := await _live_office()
	var row := office.hud.floors.row_for(_floor("data"))
	# The column stops above the staff panel: scroll the row into it first.
	var scroll: ScrollContainer = office.hud.floors.get_node("%Scroll")
	scroll.ensure_control_visible(row)
	await _frames(2)
	var window := _windows(row)[0]
	var at := window.get_global_rect().get_center()
	_check(scroll.get_global_rect().has_point(at), "the window is in the column's view")
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	_eq(root.gui_get_hovered_control(), window, "the pointer is over the window itself")
	_eq(window.get_tooltip(window.get_local_mouse_position()), "codex · UNREAD", "which names its agent and state")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(office.navigator.shown_key, _floor("data"), "a click on a window shows that window's floor at once")
	_eq(office.layout_plan().floor_key, _floor("data"), "drawn")
	_done(office)


## Eight windows, then `+N` for the rest. More panes or fewer relight the same
## eight nodes; none is made or dropped.
func test_windows_stop_at_eight_and_count_the_rest() -> void:
	var hud := await _hud()
	var minimap := hud.floors
	var busy := _floor_of("w1", 3, 11, "working")
	minimap.show_buildings(_one_building([busy]), "w1", false)
	await _frames(2)
	var row := minimap.row_for("w1")
	_eq(_windows(row).filter(func(w: Control) -> bool: return w.visible).size(), 8, "eight windows at most")
	_eq(_label(row, "%More").text, "+3", "and the rest counted")
	_check(_label(row, "%More").visible, "shown")
	_eq(row.size.y, float(OfficeFloors.ROW), "and the row keeps the one row height the list scrolls by")
	var nodes := _windows(row).map(func(w: Control) -> int: return w.get_instance_id())
	minimap.show_buildings(_one_building([_floor_of("w1", 3, 2, "idle")]), "w1", false)
	await _frames(1)
	_eq(_looks(row), [&"WindowIdle", &"WindowIdle"], "two panes, two windows")
	_check(not _label(row, "%More").visible, "and nothing over the cap")
	_eq(_windows(row).map(func(w: Control) -> int: return w.get_instance_id()), nodes, "the same window nodes")
	hud.free()


## A dropped machine's building keeps its floors, dimmed and frozen: no count,
## no lit window, nothing pulsing. It lights again when the machine is back.
func test_a_stale_building_is_dimmed_with_every_window_dark() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_set_online(office, false)
	await _frames(1)
	var tint := office.art.stale_tint
	for key: String in minimap.row_keys():
		var row := minimap.row_for(key)
		_eq(row.modulate, tint, key + ": dimmed")
		_check(_looks(row).all(func(look: StringName) -> bool: return look == &"WindowDark"), key + ": no lit window")
		_check(not _node(row, "%BlockedIcon").visible and not _node(row, "%DoneIcon").visible, key + ": no count")
	_eq(_tips(minimap.row_for(_floor("hs")))[0], "claude · OFFLINE", "a dark window says why")
	_set_online(office, true)
	await _frames(1)
	_eq(minimap.row_for(_floor("hs")).modulate, Color.WHITE, "back online, back to full colour")
	_eq(_looks(minimap.row_for(_floor("hud"))), [&"WindowBlocked"], "and lit again")
	_done(office)


## The shown floor's row is the one highlighted, alone. A floor call moves the
## highlight there in the same frame the floor is shown: no row in between ever
## has it, and there is no car, no shaft and no ride left to show.
func test_the_shown_floor_is_highlighted_alone() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_eq(_current(office), [_floor("hs")], "the shown floor's row is highlighted, and only it")
	var row := minimap.row_for(_floor("ops"))
	var at := row.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	_eq(_current(office), [_floor("hs")], "a press moves nothing")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(office.navigator.shown_key, _floor("ops"), "released: 5F is shown")
	_eq(_current(office), [_floor("ops")], "and its row is highlighted alone, 4F passed over")
	await _frames(12)
	_eq(_current(office), [_floor("ops")], "and stays so")
	_check(row.get_node_or_null("%CarMark") == null, "a row has no car mark")
	_check(minimap.get_node_or_null("%FloorIndicator") == null, "and the panel no lift display")
	_done(office)


## A mezzanine's plate says which checkout it is and whose worktree; every
## floor of the group wears one accent picked by the group, and a floor in no
## group wears none.
func test_a_mezzanine_plate_names_its_checkout_and_source() -> void:
	var office := await _live_office()
	_eq(_label(office.plate, "%Title").text, "1F  HERDSTEAD", "a source floor as before")
	_check(not _label(office.plate, "%WorktreeOf").visible, "with no worktree line")
	var accent: Control = office.plate.get_node("%Accent")
	_check(accent.visible, "a source floor wears its group's accent")
	var look := accent.theme_type_variation
	_check(str(look).begins_with("PlateAccent"), "one of the plate accents: " + str(look))
	var row := office.hud.floors.row_for(_floor("hud"))
	var at := row.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	accent = office.plate.get_node("%Accent")
	_eq(_label(office.plate, "%Title").text, "1A · HUD-LANE", "a mezzanine's number and checkout")
	_check(_label(office.plate, "%WorktreeOf").visible, "and a line saying whose worktree it is")
	_eq(_label(office.plate, "%WorktreeOf").text, "worktree of 1F", "its source floor")
	_eq(accent.theme_type_variation, look, "the group's one accent")
	await _visit_floor(office, _floor("notes"))
	accent = office.plate.get_node("%Accent")
	_check(not accent.visible, "a floor in no group wears no accent")
	_check(not _label(office.plate, "%WorktreeOf").visible, "and no worktree line")
	await _visit_floor(office, _floor("ops"))
	accent = office.plate.get_node("%Accent")
	_check(not accent.visible, "nor does a worktree whose source is closed")
	_done(office)


## Every other floor with an agent blocked on it gets a signpost over the
## world's right edge, pointing up or down the building from the floor shown,
## with the floor's number and name as its row writes them and a pulsing
## blocked badge with the count. A real click on one shows that floor; a floor
## that starts waiting gets its own; a machine that drops takes them all away.
func test_signposts_point_at_other_floors_with_blocked_agents() -> void:
	var office := await _live_office()
	var posts := office.hud.signposts
	_eq(office.navigator.shown_key, _floor("hs"), "herdr's focus is on 1F")
	await _frames(2)
	_check(posts.visible, "a blocked agent on another floor puts the signposts up")
	_eq(_post_texts(office), ["↓ 1A hud-lane 1"], "one post: down to the mezzanine, its checkout, one blocked")
	var post := posts.shown()[0]
	_eq(post.key(), _floor("hud"), "it points at 1A")
	var badge := post.badge()
	_eq([badge.machine, str(badge.state)], [LOCAL, "blocked"], "its badge stands for the floor's machine, blocked")
	_check(badge.is_in_group(StatusBadge.GROUP), "and pulses with the others")
	_check(post.tooltip_text.contains("1 blocked"), "its tooltip says so: " + post.tooltip_text)
	var at := post.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(office.navigator.shown_key, _floor("hud"), "a click on it shows 1A at once")
	_eq(office.layout_plan().floor_key, _floor("hud"), "drawn")
	_check(not posts.visible, "and with no other floor waiting, the signposts go")
	_check(not badge.is_in_group(StatusBadge.GROUP), "the hidden post's badge stops pulsing")
	_feed(office, _with(fixture, "hs:p1", {"agent_status": "blocked"}))
	await _frames(2)
	_eq(_post_texts(office), ["↑ 1F herdstead 1"], "1F starts waiting: up to it from the mezzanine")
	_set_online(office, false)
	await _frames(1)
	_check(not posts.visible, "a machine that drops counts nobody waiting: no signpost")
	_done(office)


## Six posts, always the same six nodes: more floors waiting than that, and
## five of them get a post while the sixth, disabled, counts the rest and names
## them in its tooltip. Fewer, and the posts past them hide.
func test_signposts_keep_six_nodes_and_say_plus_n() -> void:
	var hud := await _hud()
	var nodes := hud.signposts.find_children("*", "OfficeSignpost", true, false)
	_eq(nodes.size(), OfficeSignposts.POSTS, "six posts in the scene")
	var many: Array[SignpostModel] = []
	for index in 8:
		many.append(_post_of("f%d" % index, "%dF f%d" % [index + 2, index], index + 1))
	hud.show_signposts(many)
	await _frames(2)
	var shown := hud.signposts.shown()
	_eq(shown.size(), 6, "six shown")
	_eq(
		shown.slice(0, 5).map(func(post: OfficeSignpost) -> String: return post.key()),
		["f0", "f1", "f2", "f3", "f4"],
		"the first five point at their floors"
	)
	_check(shown.slice(0, 5).all(func(post: OfficeSignpost) -> bool: return not post.disabled), "and can be clicked")
	var more := shown[5]
	_eq(_label(more, "%Floor").text, "+3 floors", "the sixth counts the rest")
	_check(more.disabled, "and is a note, not a way there")
	_eq(more.key(), "", "with no floor of its own")
	_eq(more.tooltip_text.split("\n").size(), 3, "its tooltip names the three: " + more.tooltip_text)
	_check(more.tooltip_text.contains("7F f5") and more.tooltip_text.contains("9F f7"), "by number and name")
	_check(not more.badge().is_in_group(StatusBadge.GROUP), "its badge does not pulse")
	var few: Array[SignpostModel] = [_post_of("a", "3F a", 1), _post_of("b", "2F b", 2)]
	hud.show_signposts(few)
	await _frames(1)
	_eq(
		hud.signposts.shown().map(func(post: OfficeSignpost) -> String: return post.key()),
		["a", "b"],
		"two floors, two posts"
	)
	_check(not hud.signposts.shown()[1].disabled, "the second is a way there again")
	_eq(hud.signposts.find_children("*", "OfficeSignpost", true, false), nodes, "the same six nodes throughout")
	var none: Array[SignpostModel] = []
	hud.show_signposts(none)
	_check(not hud.signposts.visible, "no floor waiting, no signposts")
	hud.free()


## The signposts stand inside the world, `signpost_inset` in from its top-right
## corner, in every window that shows them: they cover the world, never a
## panel. Below `signposts_from` (the 480x320 minimum) they are not shown.
func test_signposts_stand_inside_the_world_at_its_right_edge() -> void:
	var office := await _live_office()
	for screen: Vector2 in [Vector2(SCREEN), Vector2(960, 480), Vector2(480, 320)]:
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var room := office.hud.world_rect()
		if room.size.x < office.hud.signposts_from:
			_check(not office.hud.signposts.visible, "%s: a world %d wide shows none" % [screen, room.size.x])
			continue
		var rect := office.hud.signposts.get_global_rect()
		var inset := office.hud.signpost_inset
		_check(office.hud.signposts.visible, "%s: shown" % screen)
		_check(rect.size.x > 0.0 and rect.size.y > 0.0, "%s: with a size: %s" % [screen, rect])
		_check(room.encloses(rect), "%s: inside the world %s: %s" % [screen, room, rect])
		_eq(rect.end.x, room.end.x - inset.x, "%s: its right edge the inset in from the world's" % screen)
		_eq(rect.position.y, room.position.y + inset.y, "%s: its top the inset below the world's" % screen)
	_done(office)


## Below `signposts_from` the signposts step aside for the FLOORS rail: at the
## minimum they are hidden, the rail's row for the waiting floor is the same
## click, with its blocked badge and count, and nothing covers the plate's
## name or the tables' signs. Where they show (a 640x320 world is
## 500 wide, 960x480 is 820), they are in their one form, name and all, and
## cover at most a third of the world's width.
func test_signposts_step_aside_for_the_rail_on_a_narrow_world() -> void:
	var office := await _live_office()
	var wanted := {Vector2(480, 320): false, Vector2(640, 320): true, Vector2(960, 480): true}
	for screen: Vector2 in wanted:
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var room := office.hud.world_rect()
		_eq(office.hud.signposts_yield(), not wanted[screen], "%s: step aside when the world is narrow" % screen)
		_eq(office.hud.signposts.visible, wanted[screen], "%s: shown only when it is not" % screen)
		if not wanted[screen]:
			var row := office.hud.floors.row_for(_floor("hud"))
			_check(row.is_visible_in_tree(), "%s: the rail's row for 1A is there" % screen)
			_check(_node(row, "%BlockedIcon").visible, "%s: with its blocked badge" % screen)
			_eq(_label(row, "%BlockedCount").text, "1", "%s: and its count" % screen)
			_check(row.tooltip_text.contains("1 blocked"), "%s: its tooltip says so: %s" % [screen, row.tooltip_text])
			continue
		var rect := office.hud.signposts.get_global_rect()
		var cover := rect.size.x / room.size.x
		print(
			(
				"SIGNPOST_COVER: %dx%d world %d wide, posts %d wide = %.1f%%"
				% [screen.x, screen.y, room.size.x, rect.size.x, cover * 100.0]
			)
		)
		_check(cover <= MAX_SIGNPOST_COVER, "%s: the posts cover %.1f%% of the world's width" % [screen, cover * 100.0])
		var post := office.hud.signposts.shown()[0]
		var line: Control = post.get_node("%Line")
		# A Control never shrinks below its minimum: words that do not fit push
		# the line out of the post rather than shrink it.
		_check(
			post.get_global_rect().encloses(line.get_global_rect()),
			"%s: the post's words fit it: %s in %s" % [screen, line.get_global_rect(), post.get_global_rect()]
		)
		var floor_label := _label(post, "%Floor")
		var font := floor_label.get_theme_font("font")
		var needed := font.get_string_size(
			floor_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, floor_label.get_theme_font_size("font_size")
		)
		_check(needed.x <= floor_label.size.x, "%s: '%s' is drawn whole, not clipped" % [screen, floor_label.text])
		_eq(_post_texts(office), ["↓ 1A hud-lane 1"], "%s: the post's words" % screen)
		_check(post.tooltip_text.contains("1A hud-lane"), "%s: the tooltip names the floor" % screen)
	# At the minimum nothing stands over the plate's name or a table's sign.
	office.test_screen = Vector2(480, 320)
	office.refresh()
	office.camera.pan = Vector2.ZERO
	await _frames(2)
	var title: Label = office.plate.get_node("%Title")
	var name_rect := Rect2(title.get_global_rect().position - office.camera.position, title.size)
	_check(office.hud.world_rect().encloses(name_rect), "the plate's name is on screen: %s" % name_rect)
	_check(not office.hud.signposts.is_visible_in_tree(), "and no post stands over it or a table's sign")
	# A real click on the rail's row is the way to that floor the post was.
	var row := office.hud.floors.row_for(_floor("hud"))
	var at := row.get_global_rect().get_center()
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	_eq(office.navigator.shown_key, _floor("hud"), "a click on the rail's row shows 1A")
	_done(office)


## The HUD keeps the posts it was last handed: a change of the world's width
## (a window, the drawer) shows or hides the same posts at once, with no refresh
## and no new node. Five floors waiting get five posts, each with its name.
func test_the_hud_keeps_the_posts_and_shows_them_as_the_world_widens() -> void:
	var hud := await _hud()
	var nodes := hud.signposts.find_children("*", "OfficeSignpost", true, false)
	hud.fit(Vector2(480, 320))
	var five: Array[SignpostModel] = []
	for index in 5:
		five.append(_post_of("f%d" % index, "%dA f%d" % [index + 2, index], 1))
	hud.show_signposts(five)
	await _frames(2)
	_check(hud.signposts_yield(), "a 480x320 world is narrow")
	_check(not hud.signposts.visible, "so the posts step aside")
	hud.fit(Vector2(SCREEN))
	await _frames(2)
	_check(not hud.signposts_yield() and hud.signposts.visible, "an 800x480 world shows them, no new models")
	var shown := hud.signposts.shown()
	_eq(shown.size(), 5, "five floors, five posts")
	_eq(_label(shown[0], "%Floor").text, "2A f0", "each with its name")
	# 560x320: 420 wide with the drawer closed, 296 with it open.
	hud.fit(Vector2(560, 320))
	await _frames(2)
	_check(hud.signposts.visible, "560x320, the drawer closed: shown")
	hud.open_drawer()
	await _frames(1)
	_check(not hud.signposts.visible, "the drawer opened narrows the world: they step aside at once")
	hud.close_drawer()
	await _frames(1)
	_check(hud.signposts.visible, "closed again: back, the same five")
	_eq(hud.signposts.shown().size(), 5, "all five")
	hud.open_overview()
	_check(not hud.signposts.visible, "the OVERVIEW hides them")
	hud.close_overview()
	_eq(hud.signposts.find_children("*", "OfficeSignpost", true, false), nodes, "the same six nodes")
	hud.free()


## A post is tall enough for its badge's pulse: at every lift the pulse takes
## (OfficeAttention.PULSES, up to 2 units), in every window that shows posts,
## the badge's drawn pixels stay inside the post's frame.
func test_the_signpost_badge_has_room_for_its_pulse() -> void:
	var hud := await _hud()
	var one: Array[SignpostModel] = [_post_of("f0", "3F infra", 1)]
	for screen: Vector2 in [Vector2(SCREEN), Vector2(640, 320)]:
		hud.fit(screen)
		hud.show_signposts(one)
		await _frames(2)
		var post := hud.signposts.shown()[0]
		var badge := post.badge()
		var used := badge.texture.get_image().get_used_rect()
		var inner := post.get_global_rect().grow(-1.0)
		for units: float in [0.0, -1.0, -2.0]:
			badge.lift(units)
			var local := Rect2(badge.get_rect().position + Vector2(used.position), Vector2(used.size))
			var drawn := badge.get_global_transform() * local
			_check(
				inner.encloses(drawn), "%s lift %d: the badge %s inside the frame %s" % [screen, units, drawn, inner]
			)
		badge.lift(0.0)
	hud.free()


## Blocked comes first: an agent asking while herdr still launches it is a
## blocked agent to the minimap and the signposts. data:p2 (1B) blocks before
## its launch is over: its window is lit blocked and names it so, its row
## counts it beside the blocked icon, and a signpost points down to 1B.
func test_a_blocked_start_lights_its_window_blocked_and_posts_a_signpost() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_feed(office, _with(fixture, "data:p2", {"agent_status": "blocked", "launch_pending": true}))
	await _frames(2)
	_check(office.frame.pane(HerdrFleet.pane_key(LOCAL, "data:p2")).starting, "herdr still launches data:p2")
	var row := minimap.row_for(_floor("data"))
	_eq(_looks(row), [&"WindowDone", &"WindowBlocked"], "its window is lit blocked, not plainly")
	_eq(_tips(row).slice(1), ["pi · NEEDS INPUT"], "and names it so, in the pack's words")
	_eq(office.frame.find_floor(_floor("data")).zone_model.blocked, 1, "the row counts it")
	_check(_node(row, "%BlockedIcon").visible, "beside the blocked icon")
	var keys := office.hud.signposts.shown().map(func(post: OfficeSignpost) -> String: return post.key())
	_check(keys.has(_floor("data")), "a signpost points at 1B: " + str(_post_texts(office)))
	_done(office)


## The FLOORS column is a narrow rail below 1280 wide: each
## row keeps its number chip, its blocked badge and count, and the windows
## directly under the chip; its name, indent and UNREAD count step out, and the
## row's tooltip, under a real pointer, says them. Every row fits the rail's
## 72 units, and a building's heading clips there with the machine's name in
## its tooltip.
func test_the_rail_says_number_windows_and_blocked_with_the_name_in_its_tooltip() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_eq(office.hud.placed(minimap).size.x, 72.0, "the rail is 72 wide")
	_check(not office.hud.floors_named(), "800 wide: no names")
	for key: String in minimap.row_keys():
		var row := minimap.row_for(key)
		_check(not _node(row, "%FloorLabel").visible, "%s: no name" % key)
		_check(not _node(row, "%DoneIcon").visible and not _node(row, "%DoneCount").visible, "%s: no UNREAD" % key)
		_check(not _node(row, "%Pad").visible, "%s: nothing before the windows" % key)
		var inner := row.get_global_rect()
		for part: String in ["Body/Stack/Line", "Body/Stack/Lights"]:
			var needed := (row.get_node(part) as Control).get_combined_minimum_size().x
			_check(
				needed <= inner.size.x - 4.0, "%s: %s fits the rail: %.0f of %.0f" % [key, part, needed, inner.size.x]
			)
	var hud_row := minimap.row_for(_floor("hud"))
	_check(_node(hud_row, "%BlockedIcon").visible, "1A: its blocked badge")
	_eq(_label(hud_row, "%BlockedCount").text, "1", "and its count")
	var chip := _node(hud_row, "%Chip").get_global_rect()
	var facade := _node(hud_row, "%Facade").get_global_rect()
	_eq(facade.position.x, chip.position.x, "the windows stand directly under the chip")
	_check(facade.position.y >= chip.end.y, "below it")
	var data_row := minimap.row_for(_floor("data"))
	var at := _node(data_row, "%Chip").get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	_eq(root.gui_get_hovered_control(), data_row, "the pointer rests on 1B's row")
	var tip := data_row.get_tooltip(data_row.get_local_mouse_position())
	_check(tip.begins_with("1B  "), "the tooltip names the floor: " + tip)
	_check(tip.contains("1 UNREAD"), "and counts its UNREAD: " + tip)
	_check(hud_row.tooltip_text.contains("1 blocked"), "1A's counts its blocked: " + hud_row.tooltip_text)
	_check(hud_row.tooltip_text.contains("hud-lane"), "and names its checkout: " + hud_row.tooltip_text)
	_done(office)
	# A building's heading: the rail clips its name; its tooltip has it whole.
	var hud := await _hud()
	var building := _one_building([_floor_of("w1", 3, 2, "working")])
	building[0].label = "a-machine-with-a-long-name"
	building[0].state = MachineLiveness.State.LIVE
	hud.floors.show_buildings(building, "w1", true)
	await _frames(2)
	var heading := hud.floors.headings()[0]
	var label: Label = heading.get_node("%BuildingLabel")
	_eq(label.tooltip_text, "a-machine-with-a-long-name", "the heading's tooltip names the machine")
	_check(label.mouse_filter != Control.MOUSE_FILTER_IGNORE, "and the pointer can rest on it")
	_check(hud.floors.get_global_rect().encloses(label.get_global_rect()), "its name clipped inside the rail")
	hud.free()


## The floors' names come back from the scene's `floors_named_from` (1280) on:
## at 1279 wide the column is the 72-wide rail, at 1280 it is 120 wide with each
## floor's name and UNREAD count and the mezzanines indented, and the world
## starts right of it. The same row nodes throughout.
func test_floor_names_show_from_the_scenes_width() -> void:
	var office := await _live_office()
	var minimap := office.hud.floors
	_eq(office.hud.floors_named_from, 1280.0, "the scene's line")
	var ids := minimap.row_keys().map(func(key: String) -> int: return minimap.row_for(key).get_instance_id())
	var data := func() -> OfficeFloorRow: return minimap.row_for(_floor("data"))
	for step: Array in [[1279.0, false, 72.0, 96.0], [1280.0, true, 120.0, 144.0], [1279.0, false, 72.0, 96.0]]:
		var width: float = step[0]
		var screen := Vector2(width, 480)
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var named: bool = step[1]
		_eq(office.hud.floors_named(), named, "%s: names or the rail" % screen)
		_eq(office.hud.placed(minimap).size.x, step[2], "%s: the column's width" % screen)
		_eq(office.hud.world_rect().position.x, step[3], "%s: the world starts right of it" % screen)
		var row: OfficeFloorRow = data.call()
		_eq(_node(row, "%FloorLabel").visible, named, "%s: 1B's name" % screen)
		_eq(_label(row, "%FloorLabel").text, "data-lane", "%s: which is its checkout" % screen)
		_eq(_node(row, "%DoneIcon").visible, named, "%s: its UNREAD icon" % screen)
		_eq(_node(row, "%Indent").visible, named, "%s: its indent" % screen)
		_eq(row.tooltip_text.contains("UNREAD"), not named, "%s: the tooltip counts what the row does not" % screen)
	var after := minimap.row_keys().map(func(key: String) -> int: return minimap.row_for(key).get_instance_id())
	_eq(after, ids, "the same rows")
	_done(office)


## Every gesture that picks a floor counts one navigation (what a pick waiting
## for a new pane records): a signpost click, a FLOORS row click, PageDown,
## PageUp. Panning counts none: a real drag, a wheel notch; nor does a desk
## click. pick_zone() shows a floor exactly as a click on its FLOORS row does.
func test_floor_gestures_count_as_navigation_and_panning_does_not() -> void:
	var office := await _live_office()
	var navigator := office.navigator
	await _frames(2)
	var revision := navigator.nav_revision
	var post := office.hud.signposts.shown()[0]
	await _click_at(post.get_global_rect().get_center())
	_eq([navigator.shown_key, navigator.nav_revision], [_floor("hud"), revision + 1], "a signpost: one navigation")
	await _visit_floor(office, _floor("notes"))
	_eq([navigator.shown_key, navigator.nav_revision], [_floor("notes"), revision + 2], "a FLOORS row: one")
	var clicked := [navigator.shown_key, navigator.picked_floor, office.world_model, office.layout_plan().floor_key]
	await _office_key(office, KEY_PAGEDOWN)
	_eq([navigator.shown_key, navigator.nav_revision], [_floor("hs"), revision + 3], "PageDown: one")
	var middle := office.hud.world_rect().get_center()
	var pan := office.camera.pan
	await _drag(middle, middle + Vector2(-80, -60))
	_check(office.camera.pan != pan, "a real drag pans the floor")
	pan = office.camera.pan
	var wheel := _wheel(MOUSE_BUTTON_WHEEL_UP)
	wheel.position = middle
	wheel.global_position = middle
	await _parsed(wheel)
	_check(office.camera.pan != pan, "so does a wheel notch")
	await _click_desk(office, HerdrFleet.pane_key(LOCAL, "hs:p1"))
	_eq(office.picked_key, HerdrFleet.pane_key(LOCAL, "hs:p1"), "a desk click picks")
	_eq([navigator.shown_key, navigator.nav_revision], [_floor("hs"), revision + 3], "none of them navigates")
	await _office_key(office, KEY_PAGEUP)
	_eq([navigator.shown_key, navigator.nav_revision], [_floor("notes"), revision + 4], "PageUp: one")
	await _office_key(office, KEY_PAGEDOWN)
	navigator.pick_zone(_floor("notes"))
	office.refresh()
	var picked := [navigator.shown_key, navigator.picked_floor, office.world_model, office.layout_plan().floor_key]
	_eq(picked, clicked, "pick_zone() shows the floor as its FLOORS row did")
	_eq(navigator.nav_revision, revision + 6, "and counts one navigation")
	_done(office)


## A real left click at `at`, in viewport pixels.
func _click_at(at: Vector2) -> void:
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, true))
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))


# --- helpers ------------------------------------------------------------------


func _floor(workspace_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, workspace_id)


func _node(holder: Node, path: String) -> Control:
	return holder.get_node(path)


func _chips(office: OfficeDouble) -> Array:
	var minimap := office.hud.floors
	return minimap.row_keys().map(func(key: String) -> String: return _label(minimap.row_for(key), "%Number").text)


## A row's eight window nodes, lit or not.
func _windows(row: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in row.get_node("%Windows").get_children():
		found.append(child)
	return found


## The look of each window a row shows, left to right.
func _looks(row: Node) -> Array:
	return (
		_windows(row)
		. filter(func(w: Control) -> bool: return w.visible)
		. map(func(w: Control) -> StringName: return w.theme_type_variation)
	)


func _tips(row: Node) -> Array:
	return (
		_windows(row)
		. filter(func(w: Control) -> bool: return w.visible)
		. map(func(w: Control) -> String: return w.tooltip_text)
	)


func _window_ids(office: OfficeDouble) -> Array:
	var ids: Array = []
	for key: String in office.hud.floors.row_keys():
		ids.append_array(
			_windows(office.hud.floors.row_for(key)).map(func(w: Control) -> int: return w.get_instance_id())
		)
	return ids


## The keys of the rows drawn as the shown floor.
func _current(office: OfficeDouble) -> Array:
	var minimap := office.hud.floors
	return minimap.row_keys().filter(
		func(key: String) -> bool: return minimap.row_for(key).theme_type_variation == &"FloorRowCurrent"
	)


## A HUD on its own, laid out for the suite's screen.
func _hud() -> OfficeHud:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: OfficeHud = scene.instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(Vector2(SCREEN))
	await _frames(2)
	return hud


## Floor `key` numbered `number`, one room of `panes` claude agents in `state`.
func _floor_of(key: String, number: int, panes: int, state: String) -> ZoneModel:
	var floor_model := ZoneModel.new()
	floor_model.key = key
	floor_model.number = number
	floor_model.label = key
	floor_model.agents = panes
	var room := RoomModel.new()
	for index in panes:
		var pane := PaneModel.new()
		pane.key = "%s:p%d" % [key, index]
		pane.provider = "claude"
		pane.state = state
		room.panes.append(pane)
	floor_model.rooms.append(room)
	return floor_model


func _one_building(floors: Array[ZoneModel]) -> Array[BuildingRows]:
	var building := BuildingRows.new()
	building.key = "local"
	building.label = "Local"
	building.floors = floors
	return [building]


## Each shown signpost's words, arrow to count, as one string.
func _post_texts(office: OfficeDouble) -> Array:
	return office.hud.signposts.shown().map(
		func(post: OfficeSignpost) -> String:
			var words := PackedStringArray()
			for part: String in ["%Arrow", "%Floor", "%Count"]:
				var label: Label = post.get_node(part)
				if label.visible:
					words.append(label.text)
			return " ".join(words)
	)


func _post_of(key: String, floor_text: String, blocked: int) -> SignpostModel:
	var post := SignpostModel.new()
	post.key = key
	post.floor_text = floor_text
	post.number_text = floor_text.get_slice(" ", 0)
	post.machine_key = LOCAL
	post.blocked = blocked
	return post


## Hovering a zone's sign, by real mouse motion over its area and physics
## frames, brings up the bubble tooltip naming the workspace's repository and
## checkout, and for a mezzanine whose worktree it is; moving off hides it, and
## so does moving just past the panel's right end (the hover area is the drawn
## panel, as wide as what the sign says). It
## reads nothing and writes nothing (this suite's office is read-only and never
## reaches herdr).
func test_hovering_a_zone_sign_names_its_repo_and_checkout() -> void:
	var office := await _live_office()
	var cases := {
		_floor("hs"): "herdstead",
		_floor("hud"): "herdstead · hud-lane · worktree of 1F",
		_floor("notes"): "No repository",
	}
	for key: String in cases:
		if office.navigator.shown_key != key:
			await _visit_floor(office, key)
		office.camera.pan = Vector2.ZERO
		await _frames(3)
		var board := office.floor_view.zone_sign(key)
		_check(board != null, key + ": the zone has its sign")
		if board == null:
			continue
		var panel: NinePatchRect = board.get_node("%Panel")
		var drawn := Rect2(board.to_global(panel.position), panel.size * panel.scale)
		var on := drawn.get_center() - office.camera.position
		_check(office.hud.world_rect().has_point(on), "%s: the sign is on screen at %s" % [key, on])
		_check(not office.hud.bubble_tip_shown(), key + ": no tooltip before the pointer comes")
		await _pointer_to(on)
		_check(office.hud.bubble_tip_shown(), key + ": hovering the sign shows the tooltip")
		_eq(office.hud.bubble_tip_text(), cases[key], key + ": naming its repository and checkout")
		await _pointer_to(on + Vector2(0, 120))
		_check(not office.hud.bubble_tip_shown(), key + ": moving off hides it")
		# The hover area is the drawn panel, sized to what the sign says: just
		# inside its right end the tooltip shows, just past it it does not.
		var middle := on.y
		var end := drawn.end.x - office.camera.position.x
		await _pointer_to(Vector2(end - 2.0, middle))
		_check(office.hud.bubble_tip_shown(), key + ": just inside the panel's right end, the tooltip")
		await _pointer_to(Vector2(end + 3.0, middle))
		_check(not office.hud.bubble_tip_shown(), key + ": just past it, none")
	_done(office)


## A real pointer move to `at` (viewport pixels), then physics frames for the
## picking to answer.
func _pointer_to(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	await _parsed(motion)
	await _frames(1)
