extends "res://tools/office_test_base.gd"
## The bottom panel (OfficeBottomPanel): docked along a tall screen's bottom,
## always open, its card's preview six rows; two rows (the top row over the
## card's line) on a short one until it is opened; its AGENT / HISTORY /
## EVENTS tabs with NEWS beside them in the top row; NEXT and `‹ ›` at its
## right end; the HISTORY page's lines (`A` shows them); the bar's band (52
## tall on a tall screen, 32 on a short one); and the world running to the
## screen's right edge, with no drawer. The HUD cases drive a bare HUD,
## the pick cases a live office with no herdr; clicks and keys go through real
## input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_bottom_panel.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## Ten cases came from tools/test_agent_list.gd (S3 PANEL-a1, 2026-10-27),
## rewritten for the docked panel, the 52-unit bar band on tall screens and no
## drawer tab; each says where it came from.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const FLOORS := "res://tools/fixtures/snapshot_floors.json"

var art: ArtPack
var pen: OfficeDraw
var hud: OfficeHud
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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("bottom-panel-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FLOORS))
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
	art = ArtPack.from_manifest(MANIFESTS[0])
	pen = OfficeDraw.new(art)
	await process_frame
	await run_cases()


func _marker() -> String:
	return "BOTTOM PANEL TESTS"


func _after_case() -> void:
	super()
	if is_instance_valid(hud):
		hud.free()
	if is_instance_valid(recorder):
		recorder.free()
	root.size = SCREEN


# --- forms and room ---------------------------------------------------------------


## At the 480x320 minimum the panel is two rows along the bottom: the top row
## (tabs and NEWS) over the card's line (who, state and seat, the wait, and
## NEXT with `‹ ›`), 448x50, and the world keeps 456x202 above it. Opened (Enter,
## `Open`, answer mode) it stands 448x149 with the whole preview, the world
## 456x103; folded it gives the room back. Each move is said once.
## From tools/test_agent_list.gd `test_the_staff_panel_is_one_row_at_the_smallest_screen`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; the line gained the top row, the opened panel
## holds its whole 12-row column (149, was 128 with 3 units of it clipped), and
## the world runs to the right edge).
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: two rows 54 (was 50), opened 153 (was 149),
## the world 4 shorter in both.
func test_the_panel_is_two_rows_at_the_smallest_screen_and_opens_to_its_whole_preview() -> void:
	await _bare_hud(Vector2i(480, 320))
	var frame := _frame_of(fixture)
	hud.inspector.show_pane(frame.pane(_key_of("api:p1")), "", false)
	await _frames(3)
	var line: Control = hud.inspector.get_node("%CompactRow")
	var detail: Control = hud.inspector.get_node("%Detail")
	var next: Control = hud.inspector.get_node("%NextButton")
	var preview: Control = hud.inspector.get_node("%Preview")
	var top: Control = hud.staff.get_node("%TopRow")
	_check(hud.card_compact(), "the panel is folded")
	_eq(hud.placed(hud.staff), Rect2(16, 262, 448, 54), "two rows along the bottom, 4 up")
	_eq(hud.staff.size, Vector2(448, 54), "and really that size")
	_check(top.is_visible_in_tree(), "the top row")
	_check(line.is_visible_in_tree() and not detail.is_visible_in_tree(), "over its compact line, not its details")
	_eq(
		hud.inspector.get_node("%CompactLine").get("text"),
		"refactor the fleet · WORKING · api / main",
		"the pane's name, state and place"
	)
	_check(next.is_visible_in_tree(), "NEXT is on it")
	_check(hud.staff.get_global_rect().encloses(next.get_global_rect()), "inside the panel")
	_check(not preview.is_visible_in_tree(), "the preview is out of it")
	_eq(hud.world_rect(), Rect2(16, 48, 456, 198), "the world stops above it and runs to the right edge")
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	hud.expand_card()
	await _frames(2)
	_check(not hud.card_compact(), "opened up")
	_eq(hud.staff.size, Vector2(448, 153), "the panel stands at its full height")
	_check(detail.is_visible_in_tree() and not line.is_visible_in_tree(), "with its details")
	_check(hud.staff.get_global_rect().encloses(preview.get_global_rect()), "the preview inside it")
	_eq((preview as Label).text.split("\n").size(), OfficePaneInspector.PREVIEW_ROWS, "all twelve rows")
	_eq(hud.world_rect(), Rect2(16, 48, 456, 99), "the world gives it the room")
	_eq(rooms.size(), 1, "said once")
	hud.compact_card()
	await _frames(2)
	_check(hud.card_compact() and line.is_visible_in_tree(), "folded back to its line")
	_eq(hud.staff.size, Vector2(448, 54), "two rows again")
	_eq(hud.world_rect(), Rect2(16, 48, 456, 198), "and the world has its room back")
	_eq(rooms.size(), 2, "said once more")


## From 400 high the panel is docked: 768x151 at 800x480, always open, the
## card's details, its six-row preview, no `Open` and no `▾ Esc`; the world
## 776x276 above it. Below 400 it folds to two rows, and only a real click on
## `Open` opens it and on `▾ Esc` folds it. A window that crosses 400 moves
## the slot, said once.
## From tools/test_agent_list.gd `test_the_staff_panel_is_compact_at_every_size_until_opened`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; the card form is gone, a tall screen docks).
## S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151),
## the world 35 taller: the panel's rect and the world's room under it.
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: docked 120 (was 116), two rows 54 (was 50),
## opened 153 (was 149); each room 4 shorter.
func test_tall_screens_dock_the_panel_and_short_ones_fold_it() -> void:
	await _bare_hud(Vector2i(800, 480))
	var frame := _frame_of(fixture)
	hud.inspector.show_pane(frame.pane(_key_of("api:p1")), "", false)
	await _frames(3)
	var line: Control = hud.inspector.get_node("%CompactRow")
	var detail: Control = hud.inspector.get_node("%Detail")
	var open: Button = hud.inspector.get_node("%CompactOpen")
	var fold: Button = hud.inspector.get_node("%FoldButton")
	var preview: Label = hud.inspector.get_node("%Preview")
	_check(not hud.card_compact() and hud.inspector.docked(), "800x480: docked")
	_eq(hud.placed(hud.staff), Rect2(16, 356, 768, 120), "along the bottom, 4 up")
	_eq(hud.staff.get_global_rect(), Rect2(16, 356, 768, 120), "and really there")
	_check(detail.is_visible_in_tree() and not line.is_visible_in_tree(), "the details, not the line")
	_check(preview.is_visible_in_tree(), "the preview in it")
	_eq(preview.text.split("\n").size(), CardPicture.DOCKED_ROWS, "six rows of it")
	_check(not open.is_visible_in_tree(), "no `Open`")
	_check(not fold.is_visible_in_tree(), "and no `▾ Esc`: nothing to fold")
	_check(not hud.card_expanded(), "Escape has nothing to fold")
	# S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the world from the 70-unit bar,
	# 18 lower and 18 shorter (this run's print).
	_eq(hud.world_rect(), Rect2(16, 86, 776, 254), "the world above it, from the 70-unit bar")
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	root.size = Vector2i(480, 320)
	hud.fit(Vector2(480, 320))
	await _frames(3)
	_eq(rooms.size(), 1, "a short window folds it: said once")
	_check(hud.card_compact() and not hud.inspector.docked(), "480x320: folded, not docked")
	_eq(hud.staff.size, Vector2(448, 54), "two rows")
	_check(open.is_visible_in_tree() and open.icon != null, "`Open`, with the pack's Enter icon")
	_eq(open.text, "", "the icon alone below 640 wide")
	await _tap(open)
	_check(not hud.card_compact() and not hud.inspector.answering(), "a click on `Open` only opens the panel")
	_eq(hud.staff.size, Vector2(448, 153), "at its full height")
	_check(fold.is_visible_in_tree(), "`▾ Esc` is in the actions")
	_check(hud.staff.get_global_rect().encloses(fold.get_global_rect()), "inside the panel")
	_eq(rooms.size(), 2, "said once")
	await _tap(fold)
	_check(hud.card_compact(), "`▾ Esc` folds it back")
	_eq(hud.world_rect(), Rect2(16, 48, 456, 198), "and the world has its room back")
	_eq(rooms.size(), 3, "said once more")
	root.size = Vector2i(800, 480)
	hud.fit(Vector2(800, 480))
	await _frames(3)
	_check(not hud.card_compact() and hud.inspector.docked(), "tall again: docked")
	_eq(rooms.size(), 4, "said once")
	_eq(recorder.keys, [], "nothing went past the HUD")


## Both forms close without opening first (the line's `×`, the docked
## header's `×`): the AGENT page then says how to open a card again in
## `%Empty`, the world keeps its room and NEXT stays. Herdr's focus and an
## opening keep it closed; the viewer's own pick opens it again.
## From tools/test_agent_list.gd `test_both_compact_forms_close_and_reopen_on_a_pick`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; the panel keeps its height, D-EMPTY).
func test_the_card_closes_on_both_forms_and_a_pick_opens_it_again() -> void:
	await _bare_hud(Vector2i(480, 320))
	var pane := _frame_of(fixture).pane(_key_of("api:p1"))
	var card := hud.inspector
	var closed: Array[bool] = []
	card.card_closed.connect(func() -> void: closed.append(true))
	var line_close: Button = card.get_node("%CompactClose")
	var header_close: Button = card.get_node("%CardClose")
	var empty: Control = card.get_node("%Empty")
	var message: Label = card.get_node("%Message")
	var details: Control = card.get_node("%Detail")
	var next: Control = card.get_node("%NextButton")
	for screen: Vector2i in [Vector2i(480, 320), Vector2i(800, 480)]:
		root.size = screen
		hud.fit(Vector2(screen))
		card.show_pane(pane, "", false, OfficePaneInspector.Pick.PICKED)
		await _frames(3)
		var button := line_close if screen.y < 400 else header_close
		var other := header_close if screen.y < 400 else line_close
		_check(button.is_visible_in_tree() and not other.is_visible_in_tree(), "%s: exactly one close" % screen)
		_check(hud.staff.get_global_rect().encloses(button.get_global_rect()), "%s: inside the panel" % screen)
		var room := hud.world_rect()
		var slot := hud.placed(hud.staff)
		var before := closed.size()
		await _tap(button)
		_check(card.closed(), "%s: a click closes the card" % screen)
		_eq(closed.size(), before + 1, "%s: one close signal" % screen)
		_check(empty.is_visible_in_tree() and not details.is_visible_in_tree(), "%s: the empty state" % screen)
		_eq(message.text, CardPicture.CLOSED_MESSAGE, "%s: saying how to open one again" % screen)
		_check(next.is_visible_in_tree(), "%s: NEXT stays" % screen)
		_eq(hud.world_rect(), room, "%s: closing does not change the world's room" % screen)
		_eq(hud.placed(hud.staff), slot, "%s: nor the panel's" % screen)
		card.show_pane(pane, "", false)
		hud.expand_card()
		await _frames(2)
		_check(card.closed(), "%s: focus and opening do not reopen it" % screen)
		hud.compact_card()
		card.show_pane(pane, "", false, OfficePaneInspector.Pick.PICKED)
		await _frames(2)
		_check(not card.closed() and button.is_visible_in_tree(), "%s: a viewer pick reopens it" % screen)


## Docked, the note that explains a state (UNREAD's under a done agent, a
## dropped machine's) shows under the header, inside the panel, with the name,
## the state pill and the seat.
## From tools/test_agent_list.gd `test_the_card_holds_all_it_shows_for_a_state_with_a_note`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; the card form that had no row for the note is gone).
func test_the_docked_card_says_its_state_note_inside_the_panel() -> void:
	await _bare_hud(Vector2i(800, 480))
	var frame := _frame_of(fixture)
	var footnote: Label = hud.inspector.get_node("%Footnote")
	var shown: Array[Control] = [footnote]
	for unique: String in ["%CardName", "%CaptionPill", "%Seat", "%PortraitArea"]:
		var part: Control = hud.inspector.get_node(unique)
		shown.append(part)
	for step: Array in [["web:p2", false, "done"], ["api:p1", true, "a dropped machine's"]]:
		var what: String = step[2]
		var dropped: bool = step[1]
		hud.inspector.show_pane(frame.pane(_key_of(str(step[0]))), "", dropped)
		await _frames(3)
		_check(hud.inspector.docked() and not hud.card_compact(), "%s: docked" % what)
		for part: Control in shown:
			_check(part.is_visible_in_tree(), "%s: %s shows" % [what, part.name])
			_check(
				hud.staff.get_global_rect().encloses(part.get_global_rect()),
				(
					"%s: %s inside the panel: %s in %s"
					% [what, part.name, part.get_global_rect(), hud.staff.get_global_rect()]
				)
			)
	_eq(recorder.keys, [], "nothing went past the HUD")


## Monitor is offered exactly when there is a pane and a fleet: on the line
## (480x320, the icon alone) and docked (800x480, `Monitor`); each real click
## asks for that pane's monitor once.
## From tools/test_agent_list.gd `test_the_one_line_monitor_button_asks_for_the_monitor`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; at 800x480 the docked panel's own Monitor).
func test_the_lines_monitor_button_asks_for_the_monitor() -> void:
	await _bare_hud(Vector2i(480, 320))
	var asked: Array[String] = []
	hud.monitor_requested.connect(func(key: String) -> void: asked.append(key))
	var pane := _frame_of(fixture).pane(_key_of("api:p1"))
	hud.inspector.show_pane(pane, "", false)
	await _frames(2)
	var line_button: Button = hud.inspector.get_node("%CompactMonitor")
	var docked_button: Button = hud.inspector.get_node("%MonitorButton")
	_check(not line_button.is_visible_in_tree(), "no fleet, no monitor")
	var fleet := HerdrFleet.new()
	root.add_child(fleet)
	hud.inspector.connect_fleet(fleet, func() -> bool: return false)
	hud.inspector.show_pane(pane, "", false)
	await _frames(2)
	_check(line_button.is_visible_in_tree(), "with a fleet it is on the line")
	_eq(line_button.text, "", "the icon alone below 640 wide")
	_check(line_button.icon != null, "the expand hint is the pack's icon")
	_check(line_button.tooltip_text.begins_with("M: "), "its tooltip names its key: " + line_button.tooltip_text)
	await _tap(line_button)
	_eq(asked, [pane.key], "a click asks for that pane's monitor")
	root.size = Vector2i(800, 480)
	hud.fit(Vector2(800, 480))
	await _frames(3)
	_check(docked_button.is_visible_in_tree() and not line_button.is_visible_in_tree(), "docked: the panel's own")
	_eq(docked_button.text, "Monitor", "in its words")
	_check(docked_button.tooltip_text.begins_with("M: "), "its tooltip names its key too")
	await _tap(docked_button)
	_eq(asked, [pane.key, pane.key], "and it asks once")
	hud.inspector.show_pane(null, "", false)
	await _frames(1)
	_check(not docked_button.is_visible_in_tree(), "no pane, no Monitor")
	fleet.free()


## NEXT says what a press does and to whom. Docked: `NEXT:`, the verb and
## whom, and the wait in a row inside the button, `‹ ›` beside it. On the
## 480x320 line: whom alone, `‹ ›` beside it. An office that cannot write
## says whom and herdr's state; with nobody next it is off and a press asks
## for nothing.
## From tools/test_agent_list.gd `test_the_next_button_says_who_n_would_pick`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; docked NEXT says it all in a row, `‹ ›` moved
## under it). S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall
## (was 151), the world 35 taller; `‹ ›` beside the pill, the verbs under
## both, B2's one column: "under it" became "beside it, level with it".
func test_next_says_who_n_would_pick_on_both_forms() -> void:
	await _bare_hud(Vector2i(800, 480))
	var frame := _frame_of(fixture)
	var blocked := frame.pane(_key_of("web:p1"))
	hud.inspector.show_next(NextModel.of(blocked, "", true))
	hud.inspector.set_next_wait("12m (N)")
	await _frames(2)
	var button: Button = hud.inspector.get_node("%NextButton")
	var title: Control = hud.inspector.get_node("%NextTitle")
	var line: Label = hud.inspector.get_node("%NextLine")
	var wait: Label = hud.inspector.get_node("%NextWait")
	var steps: Control = hud.inspector.get_node("%StepRow")
	_eq(line.text, "Answer needs approval", "what a press does, and to whom: the pane's name")
	_eq(wait.text, "12m (N)", "how long, and the key")
	_check(title.is_visible_in_tree() and wait.is_visible_in_tree(), "docked: `NEXT:` and the wait")
	_check(
		(
			title.get_global_rect().end.x <= line.get_global_rect().position.x
			and line.get_global_rect().end.x <= wait.get_global_rect().position.x
		),
		"`NEXT:`, whom and the wait in a row"
	)
	for label: Control in [title, line, wait]:
		var across := label.get_global_rect()
		var room := button.get_global_rect()
		_check(
			across.position.x >= room.position.x and across.end.x <= room.end.x,
			"%s across the button: %s in %s" % [label.name, across, room]
		)
	_check(button.is_visible_in_tree() and not button.disabled, "on")
	_check(hud.staff.get_global_rect().encloses(button.get_global_rect()), "at the panel's right end")
	_check(steps.is_visible_in_tree(), "`‹ ›` with it")
	var pill := button.get_global_rect()
	var step_at := steps.get_global_rect()
	_check(
		step_at.position.x >= pill.end.x and step_at.position.y >= pill.position.y and step_at.end.y <= pill.end.y,
		"beside it, level with it: %s by %s" % [step_at, pill]
	)
	var asked: Array[bool] = []
	hud.next_requested.connect(func() -> void: asked.append(true))
	await _tap(button)
	_eq(asked.size(), 1, "a press asks for N")
	root.size = Vector2i(480, 320)
	hud.fit(Vector2(480, 320))
	await _frames(3)
	_check(hud.card_compact(), "480x320: the line")
	_eq(hud.inspector.next_text(), "needs approval", "the line's NEXT says whom alone")
	_check(not title.is_visible_in_tree(), "with no `NEXT:` before it")
	_check(steps.get_global_rect().position.x >= button.get_global_rect().end.x, "`‹ ›` beside it")
	_check(hud.staff.get_global_rect().encloses(steps.get_global_rect()), "inside the panel")
	hud.inspector.show_next(NextModel.of(blocked, "bee", true))
	root.size = Vector2i(800, 480)
	hud.fit(Vector2(800, 480))
	await _frames(2)
	_eq(line.text, "Answer needs approval @ bee", "with more than one machine, which one")
	var unread := frame.pane(_key_of("web:p2"))
	hud.inspector.show_next(NextModel.of(unread, "", true))
	_eq(line.text, "Read %s" % unread.name, "a done one is read")
	hud.inspector.show_next(NextModel.of(blocked, ""))
	_eq(line.text, "needs approval · blocked", "no verb where the office cannot write: whom and why")
	hud.inspector.show_next(null)
	await _frames(1)
	_eq([line.text, wait.text], ["All clear", ""], "nobody next, waiting for nothing")
	_check(button.disabled, "and off")
	await _tap(button)
	_eq(asked.size(), 1, "an off NEXT asks for nothing")


## Nobody next, the NEXT pill is off but not hollow: its fill is the pill's own
## `deep`, opaque, inside a `slate` edge; a switched-off card action stays hollow.
## From tools/test_agent_list.gd `test_nobody_next_is_an_opaque_pill`, unchanged.
func test_nobody_next_is_an_opaque_pill() -> void:
	await _bare_hud()
	hud.inspector.show_next(null)
	await _frames(1)
	var button: Button = hud.inspector.get_node("%NextButton")
	_check(button.disabled, "nobody next: the pill is off")
	var off := button.get_theme_stylebox("disabled") as StyleBoxFlat
	_check(off != null, "its box is a flat one")
	if off == null:
		return
	_eq(off.bg_color, art.color(ArtContract.DEEP), "filled deep")
	_eq(off.bg_color.a, 1.0, "opaque: the world does not show through it")
	_eq(off.border_color, art.color(ArtContract.SLATE), "inside a slate edge")
	_eq(off.get_border_width(SIDE_LEFT), 1, "one unit wide")
	_eq(off.get_corner_radius(CORNER_TOP_LEFT), 6, "with the pill's corners")
	var on := button.get_theme_stylebox("normal") as StyleBoxFlat
	_eq(off.bg_color, on.bg_color, "the same fill as the pill when somebody is next")
	var action := button.get_theme_stylebox("disabled", "CardAction") as StyleBoxFlat
	_check(action != null and action.bg_color.a == 0.0, "a switched-off card action stays hollow")


## A slot takes room from the world only while it is shown: the bottom panel,
## shown, stops the world and the OVERVIEW above it; hidden, it gives the
## room back down to the screen's bottom gap; shown again it takes it again.
## Each change is said once.
## From tools/test_agent_list.gd `test_a_hidden_slot_takes_no_room_and_a_shown_one_does`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; no NEWS strip under the panel any more).
## S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151),
## the world 35 taller: the room and the column's bottom, 35 lower.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the right column (the drawer) is gone,
## so its bottom edge is now read off the OVERVIEW, which stops at the same edge (OfficeHud._column_bottom()).
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the docked panel 120 tall, the room and the
## OVERVIEW's bottom 4 higher.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the room starts 18 lower under
## the taller bar (68 -> 86) and is 18 shorter, shown or hidden (this run's print); the bottoms do not move.
func test_a_hidden_panel_takes_no_room_and_a_shown_one_does() -> void:
	await _bare_hud()
	var changes: Array[bool] = []
	hud.room_changed.connect(func() -> void: changes.append(true))
	var shown := Rect2(16, 86, 776, 254)
	_eq(hud.world_rect(), shown, "shown, the world stops above the docked panel")
	_eq(hud.overview.offset_bottom, -140.0, "and so does the OVERVIEW")
	hud.staff.visible = false
	hud.fit(Vector2(800, 480))
	_eq(hud.world_rect(), Rect2(16, 86, 776, 378), "hidden, the room comes back to the bottom gap")
	_eq(hud.overview.offset_bottom, -16.0, "to the OVERVIEW too")
	_eq(changes.size(), 1, "said once")
	hud.fit(Vector2(800, 480))
	_eq(changes.size(), 1, "the same room again is not a change")
	hud.staff.visible = true
	hud.fit(Vector2(800, 480))
	_eq(hud.world_rect(), shown, "shown again, the world stops above it")
	_eq(hud.overview.offset_bottom, -140.0, "and so does the OVERVIEW")
	_eq(changes.size(), 2, "said once more")


## NEWS has no strip of its own any more: it stands in the bottom panel's top
## row, right of the tabs, on every page and both forms, and a click on it is
## its own.
## From tools/test_agent_list.gd `test_the_news_slot_takes_the_bottom_and_moves_the_staff_panel_up`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; NEWS moved into the panel's top row, D-NEWS).
## That it hides with the row in answer mode is pinned where answer mode is
## (tools/test_answers.gd, the modal's case).
func test_news_stands_in_the_panels_top_row_on_every_page() -> void:
	await _bare_hud()
	_check(hud.get_node_or_null("Screen/News") == null, "no NEWS strip under the screen")
	var news: Control = hud.news
	var top: Control = hud.staff.get_node("%TopRow")
	var tabs: Control = hud.staff.get_node("%PageTabs")
	_eq(news.get_parent(), top, "NEWS is in the panel's top row")
	_check(tabs.get_index() < news.get_index(), "right of the tabs")
	for screen: Vector2i in [Vector2i(800, 480), Vector2i(480, 320)]:
		root.size = screen
		hud.fit(Vector2(screen))
		for page: OfficeBottomPanel.Page in [
			OfficeBottomPanel.Page.AGENT, OfficeBottomPanel.Page.HISTORY, OfficeBottomPanel.Page.EVENTS
		]:
			await _tap_tab(page)
			_check(news.is_visible_in_tree(), "%s, page %d: NEWS shows" % [screen, page])
			_check(hud.staff.get_global_rect().encloses(news.get_global_rect()), "%s: inside the panel" % screen)
		await _tap_tab(OfficeBottomPanel.Page.AGENT)
	await _click_at(news.get_global_rect().get_center())
	await _frames(1)
	_eq(recorder.wheels, 0, "a click on NEWS goes no further")
	hud.news_wanted = false
	hud.fit(Vector2(480, 320))
	_check(not news.is_visible_in_tree(), "the showroom's HUD has none")


## Opened at the smallest screen, the card keeps every identity it shows in
## its details and tooltips.
## From tools/test_agent_list.gd `test_inspector_keeps_complete_identity_in_compact_details`;
## its checks unchanged, on the opened panel at 480x320.
func test_inspector_keeps_complete_identity_in_compact_details() -> void:
	await _bare_hud(Vector2i(480, 320))
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
	hud.expand_card()
	await _frames(2)
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


## The bottom panel wears the pack's wood frame with brass corners
## (`ui.panel_wood`, a nine-patch): it names it (`frame_id`), wears the
## `HdPanelWood` variation whose content margins are the wood's, draws the wood
## texture with the wood's margins at the pack's density, and its top row starts
## where the wood ends; the panel grew by the wood's extra margins, so its
## content is as tall as it was. Its pages draw no frame, and the HUD's other panels (the
## world tip) keep the dark one. S3 SKIN (2026-10-28).
func test_the_bottom_panel_wears_the_wood_frame() -> void:
	var wood := art.ui_sprite(ArtContract.UI_PANEL_WOOD)
	_check(wood != null and wood.nine_patched(), "the pack's wood is a nine-patch")
	var margins := [float(wood.patch_left), float(wood.patch_top), float(wood.patch_right), float(wood.patch_bottom)]
	for size: Vector2i in [Vector2i(800, 480), Vector2i(480, 320)]:
		await _bare_hud(size)
		var staff := hud.staff
		_eq(staff.frame_id, ArtContract.UI_PANEL_WOOD, "%s: the bottom panel names the wood" % size)
		_eq(staff.theme_type_variation, &"HdPanelWood", "%s: and wears its variation" % size)
		var box := staff.get_theme_stylebox("panel")
		_eq(
			[box.content_margin_left, box.content_margin_top, box.content_margin_right, box.content_margin_bottom],
			margins,
			"%s: its content inside the wood's margins" % size
		)
		var drawn := staff.get_node("PanelFrame") as HdPanel.Frame
		_eq(drawn.box.texture, art.sprite_texture(wood), "%s: the frame drawn is the wood" % size)
		_eq(drawn.density, art.density, "%s: at the pack's density" % size)
		_eq(
			[
				drawn.box.texture_margin_left,
				drawn.box.texture_margin_top,
				drawn.box.texture_margin_right,
				drawn.box.texture_margin_bottom
			],
			margins.map(func(units: float) -> float: return units * art.density),
			"%s: its patches the wood's, in texels" % size
		)
		var top: Control = staff.get_node("%TopRow")
		_eq(
			top.get_global_rect().position - staff.get_global_rect().position,
			Vector2(wood.patch_left, wood.patch_top),
			"%s: the top row starts where the wood ends" % size
		)
		# The slot grew by exactly the wood's extra margins: the content is as tall as under the dark panel
		# (108 docked: the top row, its gap and A1's 82-unit body; 42 for the two rows).
		var body: Control = staff.get_node("Body")
		_eq(body.size.y, 108.0 if size.y >= 400 else 42.0, "%s: the content as tall as before the wood" % size)
		for page: HdPanel in [hud.history_list, hud.event_list]:
			_eq(page.theme_type_variation, &"HdPanelBare", "%s: %s draws no frame of its own" % [size, page.name])
		var tip: HdPanel = hud.get_node("%WorldTip")
		_eq(tip.frame_id, ArtContract.UI_HUD_PANEL, "%s: the world tip keeps the dark panel" % size)
		_eq(tip.theme_type_variation, &"HdPanel", "%s: and its margins" % size)
		hud.free()


# --- tabs and pages ---------------------------------------------------------------


## The tabs show one page at a time, by real clicks; on a tall screen neither
## the world nor the panel moves for it, and nothing is said.
func test_the_tabs_show_one_page_and_never_move_the_world_on_a_tall_screen() -> void:
	await _bare_hud()
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	var room := hud.world_rect()
	var slot := hud.placed(hud.staff)
	var pages: Array[Control] = [hud.inspector, hud.history_list, hud.event_list]
	for page: OfficeBottomPanel.Page in [
		OfficeBottomPanel.Page.HISTORY,
		OfficeBottomPanel.Page.EVENTS,
		OfficeBottomPanel.Page.AGENT,
		OfficeBottomPanel.Page.EVENTS,
	]:
		await _tap_tab(page)
		_eq(hud.page(), page, "a click shows page %d" % page)
		var shown := pages.filter(func(node: Control) -> bool: return node.is_visible_in_tree())
		_eq(shown, [pages[page]], "page %d alone" % page)
		_eq(hud.world_rect(), room, "page %d: the world unmoved" % page)
		_eq(hud.placed(hud.staff), slot, "page %d: the panel unmoved" % page)
	_eq(rooms.size(), 0, "nothing said")
	_eq(recorder.keys, [], "nothing went past the HUD")


## On a short screen HISTORY and EVENTS open the folded panel to its full
## height (said once), switching between them moves nothing, and AGENT folds
## it back to its two rows (said once).
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the opened panel 153 tall (was 149), the two
## rows 54 (was 50), the world 4 shorter.
func test_history_and_events_open_the_folded_panel_on_a_short_screen() -> void:
	await _bare_hud(Vector2i(480, 320))
	var rooms: Array[bool] = []
	hud.room_changed.connect(func() -> void: rooms.append(true))
	_check(hud.card_compact(), "folded to start with")
	await _tap_tab(OfficeBottomPanel.Page.HISTORY)
	_eq(hud.staff.size, Vector2(448, 153), "HISTORY opens it")
	_check(hud.history_list.is_visible_in_tree(), "on its page")
	_eq(hud.world_rect(), Rect2(16, 48, 456, 99), "the world gives it the room")
	_eq(rooms.size(), 1, "said once")
	await _tap_tab(OfficeBottomPanel.Page.EVENTS)
	_eq(hud.staff.size, Vector2(448, 153), "EVENTS keeps it open")
	_eq(rooms.size(), 1, "and says nothing")
	await _tap_tab(OfficeBottomPanel.Page.AGENT)
	_check(hud.card_compact(), "AGENT folds it back")
	_eq(hud.staff.size, Vector2(448, 54), "to its two rows")
	_eq(rooms.size(), 2, "said once more")


## Every run starts on the AGENT page, whatever an earlier HUD showed: the
## scene's tab, the card shown and the other pages hidden.
func test_every_run_starts_on_the_agent_page() -> void:
	var scene: OfficeBottomPanel = (HUD_SCENE.instantiate() as OfficeHud).get_node("Screen/Staff")
	var tabs: TabBar = scene.get_node("%PageTabs")
	_eq(tabs.current_tab, OfficeBottomPanel.Page.AGENT, "the scene's tab is AGENT")
	_eq(tabs.tab_count, 3, "of three")
	_eq(
		[tabs.get_tab_title(0), tabs.get_tab_title(1), tabs.get_tab_title(2)],
		["AGENT", "HISTORY", "EVENTS"],
		"in that order"
	)
	_check(not (scene.get_node("%History") as Control).visible, "HISTORY hidden")
	_check(not (scene.get_node("%Events") as Control).visible, "EVENTS hidden")
	scene.get_parent().get_parent().free()
	await _bare_hud()
	await _tap_tab(OfficeBottomPanel.Page.EVENTS)
	hud.free()
	recorder.free()
	await _bare_hud()
	_eq(hud.page(), OfficeBottomPanel.Page.AGENT, "a new HUD starts on AGENT, whatever the last one showed")
	_check(hud.inspector.is_visible_in_tree(), "the card shown")


# --- HISTORY ----------------------------------------------------------------------


## The HISTORY page reads the StateLog: a line per pane that was blocked or
## done this run and no longer is, newest first, one line each: the badge of
## what it was, the name, the space, and OFFLINE or GONE (none for ENDED).
## A line that cannot be located is greyed and cannot be clicked; its tooltip
## says why. From tools/test_agent_list.gd `test_history_lines_show_what_became_of_each_record`
## (S3 PANEL-a1, 2026-10-27: the docked bottom panel, the 52-unit bar band on
## tall screens, no drawer tab; History is the panel's page, D-HIST).
func test_history_lines_say_what_became_of_each_pane() -> void:
	await _bare_hud()
	var picked: Array[String] = []
	hud.history_picked.connect(func(key: String) -> void: picked.append(key))
	var raw := fixture
	var bee_raw := _only(raw, "web:p1")
	var ledger := StateLog.new()
	var start := _frame_of(raw, bee_raw)
	_log(ledger, start, LOCAL, true, 1000)
	_log(ledger, start, "bee", true, 1000)
	# Bee drops with its agent blocked; infra:p2 (done) closes; infra:p1 stops waiting.
	_log(ledger, start, "bee", false, 1500)
	var closed := _without(raw, "infra:p2")
	_log(ledger, _frame_of(closed), LOCAL, true, 2500)
	var now := _with(closed, "infra:p1", {"agent_status": "idle"})
	var frame := _frame_of(now, bee_raw, true)
	_log(ledger, frame, LOCAL, true, 3500)
	var live: Dictionary[String, bool] = {LOCAL: true, "bee": false}
	await _tap_tab(OfficeBottomPanel.Page.HISTORY)
	hud.show_history(AgentHistory.of(ledger, frame, live, 4000), "", ledger.opened_unix)
	await _frames(2)
	var ended := _key_of("infra:p1")
	var gone := _key_of("infra:p2")
	var offline := HerdrFleet.pane_key("bee", "web:p1")
	var list := hud.history_list
	_eq(list.shown_keys(), PackedStringArray([ended, gone, offline]), "a line per pane, newest first")
	var tails := []
	for key in list.shown_keys():
		var tail: Label = list.row_for(key).get_node("%Tail")
		tails.append(tail.text if tail.visible else "")
	_eq(tails, ["", "GONE", "OFFLINE"], "each says what became of its pane; an ENDED one needs no word")
	_check(list.row_for(_key_of("web:p1")) == null, "a pane still waiting has no line")
	var ended_row := list.row_for(ended)
	_check(ended_row.shown_text().begins_with("deploy"), "what the office called the pane: " + ended_row.shown_text())
	_eq(ended_row.mark(), art.state(ArtContract.STATE_BLOCKED).badge, "its badge: it was blocked")
	_eq(list.row_for(gone).mark(), art.state(ArtContract.STATE_DONE).badge, "this one's: it was done")
	_eq(ended_row.size.y, 18.0, "one line, 18 tall")
	var tip := ended_row.tooltip_text
	_check(tip.contains("Local / infra / deploy"), "its place, in the tooltip: " + tip)
	_check(tip.contains("ENDED · No longer waiting: idle since"), "ENDED and what it does now")
	_check(tip.contains("blocked 1×"), "and how often it was blocked")
	_check(not ended_row.disabled, "it can be located")
	for key: String in [gone, offline]:
		var row := list.row_for(key)
		_check(row.disabled, "%s cannot be clicked" % key)
		var tone: Label = row.get_node("%Name")
		_eq(tone.theme_type_variation, &"LabelMuted", "%s is greyed" % key)
	_check(list.row_for(gone).tooltip_text.contains(HistoryRow.NOT_HERE + HistoryRow.WHY_GONE), "why: it closed")
	_check(
		list.row_for(offline).tooltip_text.contains(HistoryRow.NOT_HERE + HistoryRow.WHY_OFFLINE),
		"why: its machine is offline"
	)
	var since: Label = list.get_node("%Since")
	_eq(since.text, "since %s · 3 lines" % OfficeAttention.wall_clock(ledger.opened_unix), "since when, how many")
	await _tap(list.row_for(gone))
	await _tap(list.row_for(offline))
	_eq(picked, [], "a gone pane and an offline machine's cannot be picked")
	await _tap(ended_row)
	_eq(picked, [ended], "the ENDED one can")


## A History line picks its pane only while the pane is the terminal the
## StateLog saw: another terminal in it greys the line and says why; the same
## terminal again picks it. The office checks it again on the click
## (test_picks_show_the_agent_page_but_a_log_rows_pick_keeps_its_page).
## From tools/test_agent_list.gd `test_a_history_line_locates_only_the_same_terminal`
## and tools/test_attention_integration.gd `:290` (S3 PANEL-a1, 2026-10-27).
func test_a_history_line_locates_only_the_same_terminal() -> void:
	await _bare_hud()
	var picked: Array[String] = []
	hud.history_picked.connect(func(key: String) -> void: picked.append(key))
	var ledger := StateLog.new()
	_log(ledger, _frame_of(fixture), LOCAL, true, 1000)
	var ended := _with(fixture, "infra:p1", {"agent_status": "idle"})
	_log(ledger, _frame_of(ended), LOCAL, true, 2000)
	var other := _frame_of(_with(ended, "infra:p1", {"terminal_id": "term-other"}))
	var live: Dictionary[String, bool] = {LOCAL: true}
	await _tap_tab(OfficeBottomPanel.Page.HISTORY)
	hud.show_history(AgentHistory.of(ledger, other, live, 3000), "", ledger.opened_unix)
	await _frames(2)
	var key := _key_of("infra:p1")
	var row := hud.history_list.row_for(key)
	_check(row != null, "the pane that stopped waiting has a line")
	if row == null:
		return
	_check(row.disabled, "another terminal in the pane: greyed")
	_check(row.tooltip_text.contains(HistoryRow.NOT_HERE + HistoryRow.WHY_REPLACED), "and says why")
	await _tap(row)
	_eq(picked, [], "a click picks nothing")
	var same := _frame_of(ended)
	hud.show_history(AgentHistory.of(ledger, same, live, 3000), "", ledger.opened_unix)
	await _frames(2)
	_eq(hud.history_list.row_for(key), row, "the same row, updated in place")
	_check(not row.disabled and row.tooltip_text.ends_with(NewsItem.TIP_PICK), "the same terminal can be picked")
	await _tap(row)
	_eq(picked, [key], "and a click says so")


## A History line is about the pane's current agent run: another terminal in
## the pane inherits nothing the run before it waited for, and its own waits
## count from one again.
## From tools/test_agent_list.gd `test_a_new_agent_run_in_the_pane_starts_its_history_over`, unchanged.
func test_a_new_agent_run_starts_its_history_over() -> void:
	var live: Dictionary[String, bool] = {LOCAL: true}
	var ledger := StateLog.new()
	_log(ledger, _frame_of(fixture), LOCAL, true, 1000)
	var ended := _with(_with(fixture, "web:p2", {"agent_status": "idle"}), "infra:p1", {"agent_status": "idle"})
	ended = _with(ended, "infra:p2", {"agent_status": "idle"})
	var frame := _frame_of(ended)
	_log(ledger, frame, LOCAL, true, 2000)
	_eq(
		_line_keys(AgentHistory.of(ledger, frame, live, 2000)),
		PackedStringArray([_key_of("infra:p1"), _key_of("infra:p2"), _key_of("web:p2")]),
		"a blocked and two done that ended: three lines"
	)
	var replaced := _with(ended, "web:p2", {"terminal_id": "term-web-p2-next"})
	frame = _frame_of(replaced)
	_log(ledger, frame, LOCAL, true, 3000)
	_eq(
		_line_keys(AgentHistory.of(ledger, frame, live, 3000)),
		PackedStringArray([_key_of("infra:p1"), _key_of("infra:p2")]),
		"the new terminal inherits nothing of the done before it"
	)
	_log(ledger, frame, LOCAL, false, 4000)
	var away := _with(replaced, "infra:p1", {"terminal_id": "term-infra-p1-next"})
	away = _with(away, "infra:p2", {"terminal_id": "term-infra-p2-next"})
	frame = _frame_of(away)
	_log(ledger, frame, LOCAL, true, 5000)
	_eq(AgentHistory.of(ledger, frame, live, 5000).size(), 0, "nor ones that came up unannounced, blocked or done")
	_log(ledger, _frame_of(_with(away, "infra:p1", {"agent_status": "blocked"})), LOCAL, true, 6000)
	_log(ledger, frame, LOCAL, true, 7000)
	var lines := AgentHistory.of(ledger, frame, live, 7000)
	_eq(lines.size(), 1, "a wait of its own is a line again")
	if lines.size() == 1:
		_eq(lines[0].key, _key_of("infra:p1"), "infra:p1's")
		_eq(lines[0].times, 1, "blocked once in this run")
		_eq(lines[0].blocked_msec, 1000, "for its own second")
		_check(lines[0].locatable, "and it is this terminal")


## The History lines are built again only when something they are made of
## changed: the log (its version), the frame's panes, or a machine going away.
## The office's HISTORY page reads them through the same cache while it shows.
## From tools/test_agent_list.gd `test_history_is_built_again_only_when_the_log_or_the_panes_change`,
## with the page shown (S3 PANEL-a1, 2026-10-27).
func test_history_is_built_again_only_when_the_log_or_the_panes_change() -> void:
	var live: Dictionary[String, bool] = {LOCAL: true}
	var ledger := StateLog.new()
	_log(ledger, _frame_of(fixture), LOCAL, true, 1000)
	var ended := _with(fixture, "infra:p1", {"agent_status": "idle"})
	_log(ledger, _frame_of(ended), LOCAL, true, 2000)
	var cache := AgentHistory.Cache.new()
	var first := cache.lines(ledger, _frame_of(ended), live, 2000)
	_eq([cache.builds, first.size()], [1, 1], "built once: infra:p1's line")
	var again := cache.lines(ledger, _frame_of(ended), live, 3000)
	_eq(cache.builds, 1, "a refresh with the same log and panes builds nothing")
	_check(again == first, "and reads the same lines")
	var working := _with(ended, "infra:p1", {"agent_status": "working"})
	_log(ledger, _frame_of(working), LOCAL, true, 4000)
	cache.lines(ledger, _frame_of(working), live, 4000)
	_eq(cache.builds, 2, "a change in the log builds again")
	var other := _frame_of(_with(working, "infra:p1", {"terminal_id": "term-other"}))
	var moved := cache.lines(ledger, other, live, 4000)
	_eq(cache.builds, 3, "a pane with another terminal builds again")
	_check(not moved[0].locatable, "and the line knows it cannot be located")
	var away: Dictionary[String, bool] = {LOCAL: false}
	cache.lines(ledger, other, away, 4000)
	_eq(cache.builds, 4, "so does a machine going away")
	var office := await _live_office()
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "idle"}))
	await _tap_tab_of(office, OfficeBottomPanel.Page.HISTORY)
	var builds := office.history_cache.builds
	_check(office.hud.history_list.shown_keys().has(_key_of("infra:p1")), "the page shows the line")
	office.refresh()
	office.refresh()
	await _frames(2)
	_eq(office.history_cache.builds, builds, "refreshes with nothing new build nothing, page shown")
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	await _frames(1)
	_eq(office.history_cache.builds, builds + 1, "a new state builds once")
	_done(office)


## The HISTORY and EVENTS pages have no rows until they first show, and say
## page_shown once each time they come into sight; hidden again, refreshes
## lay nothing out on them.
## Replaces tools/test_agent_list.gd `test_the_events_page_renders_the_list_once_when_agents_is_back`
## (S3 PANEL-a1, 2026-10-27: the drawer's EVENTS page moved into the panel).
func test_the_history_and_events_pages_render_only_while_they_show() -> void:
	var office := await _live_office()
	var shown: Array[OfficeBottomPanel.Page] = []
	office.hud.page_shown.connect(func(page: OfficeBottomPanel.Page) -> void: shown.append(page))
	var one := _with(fixture, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	_feed(office, _with(one, "api:p1", {"agent_status": "idle"}))
	await _frames(2)
	var hud_now := office.hud
	_check(hud_now.event_list.shown_ids().is_empty(), "EVENTS hidden: no rows yet")
	_check(hud_now.history_list.shown_keys().is_empty(), "HISTORY hidden: no rows yet")
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	_eq(shown, [OfficeBottomPanel.Page.EVENTS], "EVENTS said once")
	_eq(hud_now.event_list.shown_ids(), _event_ids(office), "a row per event, at once")
	await _tap_tab_of(office, OfficeBottomPanel.Page.HISTORY)
	_eq(shown, [OfficeBottomPanel.Page.EVENTS, OfficeBottomPanel.Page.HISTORY], "HISTORY said once")
	_eq(hud_now.history_list.shown_keys(), PackedStringArray([_key_of("api:p1")]), "its line, at once")
	var events_before := hud_now.event_list.shown_ids()
	_feed(office, _with(fixture, "api:p2", {"agent_status": "blocked"}))
	await _frames(2)
	_eq(hud_now.event_list.shown_ids(), events_before, "EVENTS hidden: a new event lays nothing out there")
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	_eq(shown.size(), 3, "EVENTS said again as it comes back")
	_eq(hud_now.event_list.shown_ids(), _event_ids(office), "with the new event")
	_done(office)


# --- the bar's band, picks and the right edge --------------------------------------


## The top bar is 70 tall from 400 high and 32 below: the world starts 16 under
## it (86 / 48), the OVERVIEW 8 under it (78 / 40), and the portrait strip
## stands centred in the band.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the right column (the drawer) is gone,
## and with it its line here; the OVERVIEW's, the same `panel_top_gap` under the bar, stays.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the tall band 52 -> 70
## (the tile 66 tall: a 42 window over two 12 rows, 2 + 2 margins); the world and the OVERVIEW follow it, the strip
## still centred (35, this run's print). Renamed from `test_the_bar_band_is_52_on_tall_screens_and_32_on_short_ones`.
func test_the_bar_band_is_70_on_tall_screens_and_32_on_short_ones() -> void:
	await _bare_hud()
	for row: Array in [[Vector2i(800, 480), 70.0], [Vector2i(960, 480), 70.0], [Vector2i(480, 320), 32.0]]:
		var screen: Vector2i = row[0]
		var band: float = row[1]
		root.size = screen
		hud.fit(Vector2(screen))
		await _frames(2)
		_eq(hud.placed(hud.bar), Rect2(0, 0, screen.x, band), "%s: the bar" % screen)
		_eq(hud.bar.get_global_rect().size.y, band, "%s: really that tall" % screen)
		_eq(hud.world_rect().position.y, band + 16.0, "%s: the world under it" % screen)
		_eq(hud.overview.offset_top, band + 8.0, "%s: the OVERVIEW under it" % screen)
		var cards: Control = hud.bar.get_node("%Cards")
		var middle := cards.get_global_rect().get_center().y
		_check(absf(middle - band / 2.0) <= 0.5, "%s: the strip centred in the band: %.1f" % [screen, middle])


## Every pick shows the AGENT page, but a click on a HISTORY or EVENTS line
## keeps its page (browsing the log): a desk, a portrait card, `N` and Enter
## bring the card back; an EVENTS row and a HISTORY line pick their pane and
## stay where they are. Nothing is read or written: the office is read-only.
func test_picks_show_the_agent_page_but_a_log_rows_pick_keeps_its_page() -> void:
	var office := await _live_office()
	var one := _with(fixture, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	_feed(office, _with(one, "api:p1", {"agent_status": "idle"}))
	await _frames(2)
	var hud_now := office.hud
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	await _click_desk(office, _key_of("api:p2"))
	await _frames(2)
	_eq(hud_now.page(), OfficeBottomPanel.Page.AGENT, "a desk click shows the card")
	_eq(office.navigator.active_key, _key_of("api:p2"), "of that desk")
	await _tap_tab_of(office, OfficeBottomPanel.Page.HISTORY)
	var portrait := hud_now.bar.card_for(_key_of("web:p1"))
	_check(portrait != null, "the blocked agent has a portrait card")
	if portrait != null:
		await _tap(portrait.get_node("%Face") as Control)
		_eq(hud_now.page(), OfficeBottomPanel.Page.AGENT, "a portrait card's click shows the card")
		_eq(office.navigator.active_key, _key_of("web:p1"), "of its pane")
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	await _office_key(office, KEY_N)
	await _frames(2)
	_eq(hud_now.page(), OfficeBottomPanel.Page.AGENT, "`N` shows the card")
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	# Enter is bound by its position (card_answer), as the window delivers it.
	var enter := _key(KEY_ENTER)
	enter.physical_keycode = KEY_ENTER
	await _parsed(enter)
	enter.pressed = false
	await _parsed(enter)
	await _frames(2)
	_eq(hud_now.page(), OfficeBottomPanel.Page.AGENT, "Enter shows the card")
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	var events := office.fleet.state_log().events()
	var row: EventRow = null
	for index in range(events.size() - 1, -1, -1):
		if events[index].pane_key == _key_of("api:p1"):
			row = hud_now.event_list.row_for(events[index].id)
			break
	_check(row != null and not row.disabled, "api:p1's newest event has a row that picks")
	if row != null:
		await _tap(row)
		_eq(hud_now.page(), OfficeBottomPanel.Page.EVENTS, "an EVENTS row keeps its page")
		_eq(office.navigator.active_key, _key_of("api:p1"), "and picks its pane")
	await _click_desk(office, _key_of("api:p2"))
	await _tap_tab_of(office, OfficeBottomPanel.Page.HISTORY)
	var line := hud_now.history_list.row_for(_key_of("api:p1"))
	_check(line != null and not line.disabled, "api:p1 stopped waiting: a line that picks")
	if line != null:
		await _tap(line)
		_eq(hud_now.page(), OfficeBottomPanel.Page.HISTORY, "a HISTORY line keeps its page")
		_eq(office.navigator.active_key, _key_of("api:p1"), "and picks its pane, checked again by the office")
	_done(office)


## There is no drawer: no right column and no `%DrawerTab` in the HUD, the
## world runs to the screen's right edge and a floor's first plan is that wide.
## `A` (a real key) shows the HISTORY page and `A` again the AGENT page: on a
## tall screen the world never moves; on a short one HISTORY opens the folded
## panel and AGENT folds it back. Under the OVERVIEW `A` is the table's and
## shows nothing.
## Replaces tools/test_agent_list.gd `:731` and `:797` (S3 PANEL-a1, 2026-10-27).
## S3 PANEL-a1 round 2 (2026-10-28): the docked panel 116 tall (was 151),
## the world 35 taller: each room 35 taller.
## S3 PANEL-a2 (2026-10-28): the agent list and the attention records retire: the drawer and its ▶ are gone, and `A`
## shows the HISTORY page (D-AKEY's alternative, the lane's brief) where it opened the drawer, so this case drives a
## live office (the key is the office's) instead of a bare HUD.
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: the docked panel 120 tall, each room 4 shorter.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the room from under the 70
## band, 18 lower and 18 shorter (this run's print).
func test_there_is_no_drawer_and_a_shows_the_history_page() -> void:
	var office := await _live_office()
	var hud_now := office.hud
	_check(hud_now.get_node_or_null("%DrawerTab") == null, "no `%DrawerTab` in the HUD")
	_check(hud_now.get_node_or_null("Screen/RightColumn") == null, "no right column (the drawer) in the HUD")
	_eq(hud_now.world_rect(), Rect2(16, 86, 776, 254), "the world runs to the right edge")
	_eq(hud_now.plan_width(), 776.0, "a first plan is made for it")
	var rooms: Array[bool] = []
	hud_now.room_changed.connect(func() -> void: rooms.append(true))
	await _office_key(office, KEY_A)
	await _frames(2)
	_eq(hud_now.page(), OfficeBottomPanel.Page.HISTORY, "`A` shows the HISTORY page")
	_check(hud_now.history_list.is_visible_in_tree(), "and it is in sight")
	_eq(hud_now.world_rect(), Rect2(16, 86, 776, 254), "the docked panel stays where it is")
	await _office_key(office, KEY_A)
	await _frames(2)
	_eq(hud_now.page(), OfficeBottomPanel.Page.AGENT, "`A` again shows the AGENT page")
	_check(hud_now.inspector.is_visible_in_tree(), "the card in sight again")
	_eq(rooms.size(), 0, "on a tall screen the world never moved")
	await _office_key(office, KEY_O)
	await _frames(2)
	_check(hud_now.overview_open(), "`O` opens the OVERVIEW")
	await _office_key(office, KEY_A)
	await _frames(2)
	_eq(hud_now.page(), OfficeBottomPanel.Page.AGENT, "under the OVERVIEW `A` shows nothing")
	_done(office)
	var short := await _live_office(fixture, Vector2(480, 320))
	var short_hud := short.hud
	_check(short_hud.card_compact(), "480x320: the panel folded to its two rows")
	var world := short_hud.world_rect()
	await _office_key(short, KEY_A)
	await _frames(2)
	_eq(short_hud.page(), OfficeBottomPanel.Page.HISTORY, "480x320: `A` shows HISTORY")
	_check(not short_hud.card_compact(), "and opens the panel for it")
	_eq(short_hud.world_rect(), Rect2(16, 48, 456, 99), "the world gives it the room")
	await _office_key(short, KEY_A)
	await _frames(2)
	_check(short_hud.card_compact(), "`A` again folds it back to the card's line")
	_eq(short_hud.world_rect(), world, "and the world has its room back")
	_done(short)


## The wheel over the EVENTS page scrolls its rows and goes no further: the
## office under the panel does not pan.
## From tools/test_agent_list.gd `:992`'s wheel clause, on the EVENTS page
## (S3 PANEL-a1, 2026-10-27).
func test_the_wheel_over_a_page_scrolls_it_and_goes_no_further() -> void:
	await _bare_hud()
	await _tap_tab(OfficeBottomPanel.Page.EVENTS)
	var events: Array[StateLog.Event] = []
	for index in 30:
		var event := StateLog.Event.new()
		event.id = index + 1
		event.wall_unix = 1000.0 + index
		event.machine = LOCAL
		event.machine_label = "Local"
		event.pane_key = _key_of("api:p1")
		event.agent = "claude"
		event.space = "api"
		event.name = "refactor the fleet"
		event.state = "working" if index % 2 == 0 else "idle"
		event.previous_state = "idle" if index % 2 == 0 else "working"
		events.append(event)
	hud.show_events(events, func(_pane: String) -> bool: return true, "", 1000.0, false)
	await _frames(3)
	var scroll: ScrollContainer = hud.event_list.get_node("%Scroll")
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "the rows are taller than the page")
	var at := scroll.get_global_rect().get_center()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = at
	wheel.global_position = at
	Input.parse_input_event(wheel)
	Input.flush_buffered_events()
	await process_frame
	_check(scroll.scroll_vertical > 0, "the wheel scrolls them")
	_eq(recorder.wheels, 0, "and goes no further")


# --- helpers ----------------------------------------------------------------------


## A HUD on a `size` screen, as the office lays one out; nothing opened.
## The docked card's left column says the floors fixture's names whole at
## 960x480, the launch block beside the preview as an operator sees it: every
## pane's title and place are as wide as their words. S3 PANEL-a1 round 2
## (2026-10-28, R2): on round 1 `refactor the fleet` read `refactor t···` and
## `CLAUDE · api / main` `CLAUDE · api ···`.
func test_the_docked_card_says_the_fixtures_names_whole_at_960() -> void:
	await _bare_hud(Vector2i(960, 480))
	var frame := _frame_of(fixture)
	var block: LaunchBlock = hud.inspector.get_node("%Launch")
	var seen := 0
	for pane: PaneModel in frame.live_panes:
		hud.inspector.show_pane(pane, "", false)
		if pane.provider.is_empty():
			block.show_start(_offers(3), "", "Local")
		else:
			block.show_split(pane.provider, pane.pane_id, "down", CommandRefusal.Reason.NONE, "")
		block.show_manage(LaunchBlock.Manage.new())
		await _frames(2)
		_check(hud.inspector.docked() and block.is_visible_in_tree(), "%s: docked, the block shown" % pane.pane_id)
		for unique: String in ["%CardName", "%Seat"]:
			var label: Label = hud.inspector.get_node(unique)
			var words := (
				label
				. get_theme_font("font")
				. get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
				. x
			)
			_check(
				label.is_visible_in_tree() and not label.text.is_empty() and words <= label.size.x,
				"%s: %s `%s` whole: %s of it in %s" % [pane.pane_id, unique, label.text, words, label.size.x]
			)
		seen += 1
	_eq(seen, 13, "every pane of the fixture")


## Docked at 960x480, NEXT says its words whole beside `‹ ›` for every agent
## of the fixture it can name (the two blocked, the two done; as an operator
## and read-only), with a twelve-minute wait and an hour-long one: `NEXT:`,
## whom and the wait each inside the pill, whom no wider than its label. The
## pill is `next_docked_wide_width` there; on a screen narrower than
## `next_docked_wide_from` (800x480 is the one tested) it keeps `next_wide_width`
## and the preview its room.
## Q-A1-4 (S3 PANEL-a2, 2026-10-28): A1 round 2 put `‹ ›` beside the pill, which then cut
## `NEXT: Answer needs appro··· (N)` at 960.
func test_the_docked_next_says_the_fixtures_words_whole_at_960() -> void:
	await _bare_hud(Vector2i(960, 480))
	var frame := _frame_of(fixture)
	var button: Button = hud.inspector.get_node("%NextButton")
	var title: Label = hud.inspector.get_node("%NextTitle")
	var line: Label = hud.inspector.get_node("%NextLine")
	var wait: Label = hud.inspector.get_node("%NextWait")
	var steps: Control = hud.inspector.get_node("%StepRow")
	var slot: Control = hud.inspector.get_node("%NextSlot")
	hud.inspector.show_pane(frame.pane(_key_of("api:p1")), "", false)
	var said := 0
	for pane_id: String in ["web:p1", "infra:p1", "web:p2", "infra:p2"]:
		for may_write: bool in [true, false]:
			for long: String in ["12m (N)", "1h 05m+ (N)"]:
				hud.inspector.show_next(NextModel.of(frame.pane(_key_of(pane_id)), "", may_write))
				hud.inspector.set_next_wait(long)
				await _frames(2)
				var where := "%s %s %s" % [pane_id, "operator" if may_write else "read-only", long]
				var words := (
					line
					. get_theme_font("font")
					. get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size"))
					. x
				)
				_check(words <= line.size.x, "%s: `%s` whole: %s of it in %s" % [where, line.text, words, line.size.x])
				var pill := button.get_global_rect()
				for label: Label in [title, line, wait]:
					_check(
						label.is_visible_in_tree() and pill.encloses(label.get_global_rect()),
						"%s: %s inside the pill: %s in %s" % [where, label.name, label.get_global_rect(), pill]
					)
				_check(steps.get_global_rect().position.x >= pill.end.x, "%s: `‹ ›` beside it" % where)
				_check(hud.staff.get_global_rect().encloses(steps.get_global_rect()), "%s: inside the panel" % where)
				said += 1
	_eq(said, 16, "every NEXT the fixture can say")
	_eq(slot.size.x, hud.next_docked_wide_width, "960 wide: the docked pill's own width")
	root.size = Vector2i(800, 480)
	hud.fit(Vector2(800, 480))
	await _frames(2)
	_eq(slot.size.x, hud.next_wide_width, "800 wide: the narrower one, the preview keeps its room")


## Docked on a wide card (960x480, 1280x720) the left column is exactly
## `left_wide_width`, the room the fixture's longest name and seat line take
## whole, read-only and as an operator, and the preview takes everything else:
## with a shell's START block shown it is at least 120 units at 960x480 and 346
## at 1280x720. A narrower card (800x480) keeps the left column's share.
## S3 PANEL-a2 round 2 (2026-10-28, R1): A1's `left_wide_ratio` 0.64 left the column 230 at 960 (318 at 1280)
## and the operator preview 110 (248) once NEXT took 308; read-only, the column was 193 and `CLAUDE · 数据
## pipeline / etl` was cut.
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: its 6-unit margins leave the card 4 narrower,
## so the preview's rest is 4 less (124 -> 120, 350 -> 346) and the 800-wide column's share 1 less (133 -> 132).
func test_the_docked_left_column_holds_the_names_and_the_preview_takes_the_rest() -> void:
	var preview_least: Dictionary[Vector2i, float] = {Vector2i(960, 480): 120.0, Vector2i(1280, 720): 346.0}
	var frame := _frame_of(fixture)
	for screen: Vector2i in preview_least:
		await _bare_hud(screen)
		var left: Control = hud.inspector.get_node("%Left")
		var preview: Control = hud.inspector.get_node("%Preview")
		var block: LaunchBlock = hud.inspector.get_node("%Launch")
		for operator: bool in [false, true]:
			var form := "%s %s" % [screen, "operator" if operator else "read-only"]
			for pane: PaneModel in frame.live_panes:
				hud.inspector.show_pane(pane, "", false)
				if operator:
					if pane.provider.is_empty():
						block.show_start(_offers(3), "", "Local")
					else:
						block.show_split(pane.provider, pane.pane_id, "down", CommandRefusal.Reason.NONE, "")
					block.show_manage(LaunchBlock.Manage.new())
				await _frames(2)
				_check(
					hud.inspector.docked() and block.is_visible_in_tree() == operator,
					"%s: the block as the form has it" % form
				)
				_eq(left.size.x, hud.inspector.left_wide_width, "%s %s: the left column's width" % [form, pane.pane_id])
				for unique: String in ["%CardName", "%Seat"]:
					var label: Label = hud.inspector.get_node(unique)
					var words := (
						label
						. get_theme_font("font")
						. get_string_size(
							label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")
						)
						. x
					)
					_check(
						words <= label.size.x,
						(
							"%s %s: %s `%s` whole: %s of it in %s"
							% [form, pane.pane_id, unique, label.text, words, label.size.x]
						)
					)
				if operator and pane.provider.is_empty():
					_check(
						preview.size.x >= preview_least[screen],
						"%s %s: the preview beside START takes the rest: %s" % [form, pane.pane_id, preview.size.x]
					)
		hud.free()
	await _bare_hud(Vector2i(800, 480))
	var narrow: Control = hud.inspector.get_node("%Left")
	hud.inspector.show_pane(frame.pane(_key_of("api:p1")), "", false)
	await _frames(2)
	_eq(narrow.size.x, 132.0, "800 wide, read-only: the left column keeps its share, as before")


## The docked panel is 120 tall at 640x480, 700x480 and 760x480 (where NEXT
## gives the card its room below `staff_docked_next_from` and comes back), at
## 800x480 and at 960x480, and no state of the card puts a write control outside it: START
## with three kinds and with eight (the title gives way), its confirm armed
## with a branch note typed, no kind seen, NEW PANE with a branch note, Close
## armed on an agent with a long scope line, and the manage rows alone. Every
## shown button and the branch box stand inside the card's columns, and the
## launch block needs no more height than the body has. S3 PANEL-a1 round 2
## (2026-10-28, R1): round 1's panel was 151 tall.
## S3 SKIN (2026-10-28): the bottom panel wears the wood frame: 6-unit margins, 4 taller (116 -> 120), the
## body still 82; the world 4 shorter (276 -> 272). Renamed from `..._in_the_116_panel`.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42 portrait: the world 18 shorter under the
## 70 band (272 -> 254, this run's print); the panel and its controls unchanged.
func test_every_docked_state_keeps_its_write_controls_in_the_120_panel() -> void:
	var writes := [
		"%Kind0",
		"%Kind1",
		"%Kind2",
		"%Kind3",
		"%Kind4",
		"%Kind5",
		"%Kind6",
		"%Kind7",
		"%SplitButton",
		"%CloseButton",
		"%SpaceButton",
		"%BranchBox",
		"%WorktreeButton",
		"%FocusButton",
		"%MonitorButton",
		"%AnswerButton",
		"%NextButton",
		"%StepBack",
		"%StepOn",
		"%CardClose"
	]
	for size: Vector2i in [
		Vector2i(640, 480), Vector2i(700, 480), Vector2i(760, 480), Vector2i(800, 480), Vector2i(960, 480)
	]:
		await _bare_hud(size)
		_eq(hud.placed(hud.staff).size.y, 120.0, "%s: the docked panel 120 tall" % size)
		var next_button: Control = hud.inspector.get_node("%NextButton")
		_eq(next_button.is_visible_in_tree(), size.x >= 760, "%s: NEXT beside the card from 760" % size)
		_eq(hud.world_rect().size.y, 254.0, "%s: the world 254 tall over it" % size)
		var frame := _frame_of(fixture)
		var card := hud.inspector
		var block: LaunchBlock = card.get_node("%Launch")
		var stack: Control = card.get_node("%Stack")
		for state: String in ["start3", "start8", "confirm8", "none", "split", "close", "manage"]:
			var pane := frame.pane(_key_of("api:p3" if state in ["start3", "start8", "confirm8", "none"] else "api:p1"))
			card.show_pane(pane, "", false)
			var manage := LaunchBlock.Manage.new()
			manage.note = LaunchBlock.BRANCH_NOTE % "needs a name"
			match state:
				"start3":
					block.show_start(_offers(3), "", "Local")
				"start8":
					block.show_start(_offers(8), "", "Local")
				"confirm8":
					block.show_start(_offers(8), "", "Local", "claude", "➜  api git:(main) ✗ ")
				"none":
					block.show_start(_offers(0), "", "Local")
				"split":
					block.show_split("claude", "api:p1", "down", CommandRefusal.Reason.NONE, "")
				"close":
					block.show_split("claude", "api:p1", "down", CommandRefusal.Reason.NONE, "")
					manage.close_text = LaunchBlock.CLOSE_KILLS
					manage.confirm_note = LaunchBlock.CLOSE_NOTE % 10
					manage.confirm_line = (
						(LaunchBlock.CLOSE_LINE_AGENT % ["claude", "api:p1"])
						+ (LaunchBlock.CLOSE_LINE_MEZZANINE % ["w3", "feature-x-with-a-long-branch-name"])
					)
				"manage":
					block.show_manage_only()
			block.show_manage(manage)
			await _frames(2)
			var room := stack.get_global_rect()
			var said := "%s %s" % [size, state]
			var detail: Control = card.get_node("%Detail")
			_check(
				room.encloses(detail.get_global_rect()),
				"%s: the card's columns fit its width: %s in %s" % [said, detail.get_global_rect(), room]
			)
			_check(
				block.get_combined_minimum_size().y <= room.size.y,
				"%s: the block needs %s of the body's %s" % [said, block.get_combined_minimum_size().y, room.size.y]
			)
			var shown := 0
			for unique: String in writes:
				var control: Control = card.get_node(unique)
				if not control.is_visible_in_tree():
					continue
				shown += 1
				var within := room if stack.is_ancestor_of(control) else hud.staff.get_global_rect()
				_check(
					within.encloses(control.get_global_rect()),
					"%s: %s %s inside %s" % [said, unique, control.get_global_rect(), within]
				)
			# At least the block's own button, Close and the card's ×: the ladder above checks each that shows.
			_check(shown >= 3, "%s: %d write controls shown" % [said, shown])
		hud.free()


# --- moved from ATTENTION INTEGRATION (S3 PANEL-a2, 2026-10-28) ---------------------


## A pick from a row of the EVENTS page cancels a press the world is still
## holding: the release that follows, over a desk, picks nothing.
## From tools/test_attention_integration.gd `test_list_pick_cancels_an_in_progress_world_press`
## (S3 PANEL-a2, 2026-10-28: the agent list and the attention records retire; the pick came from the list's keyboard
## cursor, now from a real click on an EVENTS row, which picks through the same OfficeScene._pick_pane()).
func test_a_log_rows_pick_cancels_a_press_in_the_world() -> void:
	var office := await _live_office()
	var one := _with(fixture, "api:p1", {"agent_status": "blocked"})
	_feed(office, one)
	_feed(office, _with(one, "api:p1", {"agent_status": "idle"}))
	await _frames(2)
	await _tap_tab_of(office, OfficeBottomPanel.Page.EVENTS)
	var desk := _key_of("api:p2")
	# The desk is brought above the bottom panel first, as a click on it needs.
	office.reveal(desk)
	await _frames(2)
	var point := _desk_point(office, desk)
	_check(office.hud.world_rect().has_point(point), "the pending press is on the world in sight")
	var events := office.fleet.state_log().events()
	var row: EventRow = null
	for index in range(events.size() - 1, -1, -1):
		if events[index].pane_key == _key_of("api:p1"):
			row = office.hud.event_list.row_for(events[index].id)
			break
	_check(row != null and not row.disabled, "api:p1's newest event has a row that picks")
	if row == null:
		_done(office)
		return
	await _parsed(_mouse_button(point, MOUSE_BUTTON_LEFT, true))
	await _tap(row)
	_eq(office.navigator.active_key, _key_of("api:p1"), "the EVENTS row picked its pane")
	await _parsed(_mouse_button(point, MOUSE_BUTTON_LEFT, false))
	await _frames(2)
	_eq(office.navigator.active_key, _key_of("api:p1"), "the release cannot revive the press the pick cancelled")
	_eq(office.hud.page(), OfficeBottomPanel.Page.EVENTS, "and the page stays")
	_done(office)


## A blocked pane no zone seats (its workspace and tab are not in the
## snapshot) still has a portrait card; a real click on its face picks it and
## the card shows its own details, not the focused desk's, and goes nowhere:
## the map and its pan stay.
## From tools/test_attention_integration.gd `test_unplaced_pane_is_listed_and_can_show_details`
## (S3 PANEL-a2, 2026-10-28: the agent list and the attention records retire: picked by its portrait card instead of
## its list row; the record's "with details" is the card's own details now; the tree view's "not on a floor" group
## went with the list).
func test_a_card_pick_of_an_unseated_pane_shows_its_details() -> void:
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
	var office := await _live_office(snapshot)
	var key := _key_of("orphan")
	_check(office.floor_view.seat(key) == null, "no zone seats it")
	var card := office.hud.bar.card_for(key)
	_check(card != null, "it still has a portrait card")
	if card == null:
		_done(office)
		return
	var shown := [office.layout_plan().floor_key, office.camera.pan]
	await _tap(card.get_node("%Face") as Control)
	_eq(office.navigator.active_key, key, "a click on its face picks it")
	_eq([office.layout_plan().floor_key, office.camera.pan], shown, "and goes nowhere: the map and its pan stay")
	var pane_label: Label = office.hud.inspector.get_node("%PaneId")
	_eq(pane_label.text, "orphan", "the card does not fall back to the focused desk")
	var name_label: Label = office.hud.inspector.get_node("%CardName")
	_eq(name_label.text, "Unplaced task", "and says the pane's own name")
	_done(office)


## A pane whose workspace contradicts its tab is picked by its card's face and
## shows its details, but goes to neither workspace: the map and its pan stay
## and no zone is current; the bar still counts it blocked, and `N` still
## reaches it among the blocked. Repaired, a click reaches its zone.
## From tools/test_attention_integration.gd `test_conflicting_workspace_keeps_details_without_false_navigation`
## (S3 PANEL-a2, 2026-10-28: the agent list and the attention records retire: picked by its portrait card instead of
## its list row; "counted once with live attention" was the records' count, gone with them; the bar's count stays).
func test_a_conflicting_workspace_shows_its_details_and_goes_nowhere() -> void:
	var office := await _live_office(_with(fixture, "web:p1", {"workspace_id": "infra"}))
	var key := _key_of("web:p1")
	_eq(office.hud.bar.count(PortraitBarModel.Group.BLOCKED), 2, "the bar still counts the conflict blocked")
	var card := office.hud.bar.card_for(key)
	_check(card != null, "and gives it a card")
	if card == null:
		_done(office)
		return
	var pan := office.camera.pan
	await _tap(card.get_node("%Face") as Control)
	_eq(
		[office.navigator.shown_key, office.navigator.current_zone(office.frame), office.camera.pan],
		[LOCAL, "", pan],
		"a click goes to neither contradictory workspace: the map and its pan stay, no zone current"
	)
	_eq(office.navigator.active_key, key, "the unplaced pane is selected")
	var seat: Label = office.hud.inspector.get_node("%Seat")
	_eq(seat.text, "CLAUDE · infra / ui", "the card's seat line keeps both declared names")
	# While anyone is blocked, N walks the blocked only: the conflict and
	# infra:p1, not the done.
	var visited: Array[String] = []
	for step in 2:
		await _office_key(office, KEY_N)
		await _frames(2)
		_check(not visited.has(office.navigator.active_key), "N visits each blocked pane once")
		visited.append(office.navigator.active_key)
	_eq(office.navigator.active_key, key, "N still reaches the conflict")
	_eq(visited[0], _key_of("infra:p1"), "the other blocked one first")
	await _office_key(office, KEY_N)
	await _frames(2)
	_eq(office.navigator.active_key, visited[0], "and round again among them")
	_feed(office, fixture)
	await _frames(2)
	await _click_desk(office, _key_of("api:p2"))
	card = office.hud.bar.card_for(key)
	_check(card != null, "repaired, it keeps its card")
	if card != null:
		await _tap(card.get_node("%Face") as Control)
	_eq(office.navigator.current_zone(office.frame), _key_of("web"), "once repaired, a click reaches its zone")
	_eq(seat.text, "CLAUDE · web / ui", "world, bar and card agree")
	_done(office)


## A pane whose terminal nobody can verify (no terminal id) that stops waiting
## across a reconnect has a HISTORY line, but the line neither takes the new
## worker's name nor picks the pane: it is greyed, and a real click on it
## selects nothing.
## From tools/test_attention_integration.gd `test_unverifiable_reconnect_keeps_old_history_navigation_disabled`
## (S3 PANEL-a2, 2026-10-28: the agent list and the attention records retire: the History line is the HISTORY page's
## row; the record's Hide surviving the gap, and the list's Waiting group, went with them: the blocked card stands
## for "it waits again").
func test_an_unverifiable_reconnect_keeps_old_history_lines_off() -> void:
	var snapshot := _with(fixture, "api:p1", {"terminal_id": "", "agent_status": "blocked"})
	var office := await _live_office(snapshot)
	var key := _key_of("api:p1")
	_check(office.hud.bar.card_for(key) != null, "unknown identity still waits: a blocked card")
	_set_online(office, false)
	_feed(office, _with(snapshot, "api:p1", {"label": "New worker during gap"}))
	await _frames(2)
	_check(office.hud.bar.card_for(key) != null, "the replacement waits again after the gap")
	# It stops waiting: a History line, for a pane whose terminal nobody can verify.
	_feed(office, _with(snapshot, "api:p1", {"label": "New worker during gap", "agent_status": "idle"}))
	await _frames(2)
	await _tap_tab_of(office, OfficeBottomPanel.Page.HISTORY)
	var row := office.hud.history_list.row_for(key)
	_check(row != null, "the pane that stopped waiting has a History line")
	if row == null:
		_done(office)
		return
	var name_label: Label = row.get_node("%Name")
	_check(not name_label.text.contains("New worker during gap"), "the line does not impersonate the replacement")
	_check(row.disabled, "and it is greyed")
	await _click_desk(office, _key_of("api:p2"))
	await _tap_tab_of(office, OfficeBottomPanel.Page.HISTORY)
	var selected := office.navigator.active_key
	await _tap(row)
	_eq(office.navigator.active_key, selected, "an unverifiable terminal cannot be selected from History by real input")
	_done(office)


## The card's `UNREAD = not yet seen / Not task success.` explains the UNREAD
## state, so it stands only under a done agent's caption: picked by a real
## click on its portrait card (a desk for one with no card), it is there; a
## blocked or a working one has none. The pane's own lines (id, directory,
## title) stand under a PANE heading of their own, apart from the note.
## From tools/test_attention_integration.gd `test_the_unread_note_shows_only_for_a_done_agent`
## (S3 PANEL-a2, 2026-10-28: the agent list and the attention records retire: picked by its portrait card instead of
## its list row; docked at 800x480 the panel is open, so the `Open` click is gone and the case checks it is open).
func test_the_unread_note_shows_only_for_a_done_agent() -> void:
	var office := await _live_office()
	var card := office.hud.inspector
	var footnote: Label = card.get_node("%Footnote")
	var heading := card.get_node_or_null("%PaneHeading") as Label
	var pane_id: Label = card.get_node("%PaneId")
	for step: Array in [["web:p2", true], ["web:p1", false], ["api:p1", false], ["infra:p2", true]]:
		var key := _key_of(str(step[0]))
		var done: bool = step[1]
		var portrait := office.hud.bar.card_for(key)
		if portrait != null:
			await _tap(portrait.get_node("%Face") as Control)
		else:
			await _click_desk(office, key)
		await _frames(2)
		_eq(office.navigator.active_key, key, "a click picks " + key)
		_check(not office.hud.card_compact(), "docked, the panel is open for " + key)
		_eq(footnote.is_visible_in_tree(), done, "the UNREAD note under %s: %s" % [key, done])
		if done:
			_eq(footnote.text, "UNREAD = not yet seen\nNot task success.", "in its words")
			_check(office.hud.staff.get_global_rect().encloses(footnote.get_global_rect()), "inside the panel")
		_check(heading != null and heading.is_visible_in_tree(), "the pane's lines have their heading")
		if heading != null:
			_eq(heading.text, "PANE", "in herdr's word")
			_check(heading.get_global_rect().end.y <= pane_id.get_global_rect().position.y, "above the pane's id")
			_check(
				not heading.get_parent().is_ancestor_of(footnote) and heading.get_parent() != footnote.get_parent(),
				"and the note is not among the pane's lines"
			)
	_check(office.hud.bar.card_for(_key_of("web:p2")) != null, "a done agent was picked by its card")
	_done(office)


## The card's portrait (S3 PORTRAIT P2, 2026-10-28: the card shows the seat's
## person as a portrait): the 48x48 slot holds a 42x42 window at (3, 3) on the
## warm ground, a 40x40 clip 1 in, the portrait's bottom centre on the clip's,
## and the frame over the window's edge.
func test_the_card_portrait_stands_in_a_42_window_in_its_48_slot() -> void:
	await _bare_hud(Vector2i(800, 480))
	var frame := _frame_of(fixture)
	hud.inspector.show_pane(frame.pane(_key_of("api:p1")), "", false)
	await _frames(3)
	var area: Control = hud.inspector.get_node("%PortraitArea")
	var window: Panel = hud.inspector.get_node("%PortraitWindow")
	var clip: Control = hud.inspector.get_node("%PortraitClip")
	var edge: Panel = hud.inspector.get_node("%PortraitFrame")
	_check(area.is_visible_in_tree(), "the slot shows")
	_eq(area.size, Vector2(48, 48), "48x48 as before")
	_eq(
		Rect2(window.get_global_rect().position - area.get_global_rect().position, window.size),
		Rect2(3, 3, 42, 42),
		"the window 42x42 at (3, 3)"
	)
	_eq(window.theme_type_variation, &"PortraitWindow", "on the warm ground")
	_eq(
		Rect2(clip.get_global_rect().position - window.get_global_rect().position, clip.size),
		Rect2(1, 1, 40, 40),
		"the clip 40x40, 1 in"
	)
	_check(clip.clip_contents, "and it clips")
	_eq(edge.get_global_rect(), window.get_global_rect(), "the frame over the window")
	_check(edge.get_index() > window.get_index(), "drawn after it, over the portrait")
	var portrait := hud.inspector.portrait()
	_check(portrait != null and portrait.is_visible_in_tree(), "a portrait shows")
	if portrait == null:
		return
	var rect := clip.get_global_rect()
	_eq(
		portrait.get_global_transform().origin,
		Vector2(rect.get_center().x, rect.end.y),
		"its bottom centre on the clip's"
	)
	_check(clip.is_ancestor_of(portrait), "inside the clip")
	_eq(portrait.look.key(), art.portraits.look_of("claude", _key_of("api:p1")).key(), "the pane's portrait")
	_eq(recorder.keys, [], "nothing went past the HUD")


## The frame says the state in the tile's colours: blocked, done (unread),
## working and idle picks each wear theirs; a dropped machine's card wears the
## stale frame and the window is greyed; back online, neither. Every pick
## re-dresses the same portrait, and the small person is gone from the card.
func test_the_card_portrait_frame_says_the_state_and_greys_when_dropped() -> void:
	await _bare_hud(Vector2i(800, 480))
	var frame := _frame_of(fixture)
	var window: Panel = hud.inspector.get_node("%PortraitWindow")
	var edge: Panel = hud.inspector.get_node("%PortraitFrame")
	var holder: Node2D = hud.inspector.get_node("%PortraitHolder")
	var portrait: PixelPortrait = null
	var keys: Array[String] = []
	for step: Array in [
		["web:p1", false, &"PortraitFrameBlocked"],
		["web:p2", false, &"PortraitFrameDone"],
		["api:p1", false, &"PortraitFrameWorking"],
		["api:p2", false, &"PortraitFrameIdle"],
		["api:p1", true, &"PortraitFrameStale"],
		["api:p1", false, &"PortraitFrameWorking"],
	]:
		var pane_id: String = step[0]
		var dropped: bool = step[1]
		hud.inspector.show_pane(frame.pane(_key_of(pane_id)), "", dropped)
		await _frames(2)
		var what := "%s%s" % [pane_id, " dropped" if dropped else ""]
		_eq(edge.theme_type_variation, step[2], "%s: the frame" % what)
		var tint := art.stale_tint if dropped else Color.WHITE
		_eq([window.modulate, edge.modulate], [tint, tint], "%s: the window and frame tinted" % what)
		if portrait == null:
			portrait = hud.inspector.portrait()
		_eq(hud.inspector.portrait(), portrait, "%s: the same portrait" % what)
		_eq(holder.get_child_count(), 1, "%s: one portrait in the holder" % what)
		var provider := frame.pane(_key_of(pane_id)).provider
		_eq(portrait.look.key(), art.portraits.look_of(provider, _key_of(pane_id)).key(), "%s: dressed for it" % what)
		keys.append(portrait.look.key())
	_check(keys[0] != keys[1] and keys[1] != keys[2], "another pane, another portrait on the same node")
	var people := hud.inspector.find_children("*", "", true, false).filter(
		func(node: Node) -> bool: return node is PixelPerson
	)
	_eq(people.size(), 0, "no small person on the card")


func _offers(count: int) -> Array[LaunchBlock.Offer]:
	var kinds := ["claude", "codex", "pi", "qodercli", "opencode", "copilot", "hermes", "gemini"]
	var offers: Array[LaunchBlock.Offer] = []
	for index in count:
		var offer := LaunchBlock.Offer.new()
		offer.kind = kinds[index]
		offer.agent_name = "%s-1" % kinds[index]
		offers.append(offer)
	return offers


func _bare_hud(size := Vector2i(800, 480)) -> void:
	root.size = size
	hud = HUD_SCENE.instantiate()
	hud.dress(art, pen.font)
	root.add_child(hud)
	hud.fit(Vector2(size))
	recorder = Recorder.new()
	root.add_child(recorder)
	await _frames(2)


## A real click on the middle of `control`, then the frames it takes.
func _tap(control: Control) -> void:
	await _click_at(control.get_global_rect().get_center())
	await _frames(2)


## A real click on the bottom panel's tab for `page`.
func _tap_tab(page: OfficeBottomPanel.Page) -> void:
	var tabs := hud.staff.tabs
	await _click_at(tabs.get_global_rect().position + tabs.get_tab_rect(page).get_center())
	await _frames(2)


func _tap_tab_of(office: OfficeDouble, page: OfficeBottomPanel.Page) -> void:
	var tabs := office.hud.staff.tabs
	await _click_at(tabs.get_global_rect().position + tabs.get_tab_rect(page).get_center())
	await _frames(2)


## Local's snapshot `raw`, and bee's `bee_raw` (`bee_stale`: dropped) beside it.
func _frame_of(raw: Dictionary, bee_raw: Dictionary = {}, bee_stale := false) -> OfficeFrame:
	var machines: Array[MachineView] = [MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(raw), false)]
	if not bee_raw.is_empty():
		machines.append(MachineView.new("bee", "Bee", HerdrSnapshot.from_wire(bee_raw), bee_stale))
	return OfficeProjection.frame(machines, art.state_names())


func _key_of(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var copy := snapshot.duplicate(true)
	copy["panes"] = _list(copy, "panes").filter(func(pane: Dictionary) -> bool: return pane.get("pane_id") != pane_id)
	return copy


func _only(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var copy := snapshot.duplicate(true)
	copy["panes"] = _list(copy, "panes").filter(func(pane: Dictionary) -> bool: return pane.get("pane_id") == pane_id)
	return copy


func _line_keys(lines: Array[AgentHistory.Line]) -> PackedStringArray:
	var keys := PackedStringArray()
	for line in lines:
		keys.append(line.key)
	return keys


func _event_ids(office: OfficeDouble) -> PackedInt64Array:
	var ids := PackedInt64Array()
	var events := office.fleet.state_log().events()
	for index in range(events.size() - 1, -1, -1):
		ids.append(events[index].id)
	return ids


## Feed `ledger` what the fleet would hand it for machine `key` of `frame` at
## `now_msec` (tools/test_agent_list.gd's helper).
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
			sighting.tab = pane.tab_shown
			sighting.name = pane.name
			sighting.terminal_id = pane.terminal_id
			sighting.since_unix = now_msec / 1000.0
			seen.append(sighting)
	ledger.observe(key, key.capitalize(), online, seen, now_msec, now_msec / 1000.0)
