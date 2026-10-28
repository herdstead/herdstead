extends "res://tools/walking_test_base.gd"
## What each state looks like at the seat on the live office: every state sits
## at its own seat (D2, 2026-10-27: idle sits with a mug; the pantry is a nook
## nobody walks to). A blocked agent sits with a hand up and a chip on the
## badge's row (its question's excerpt in the tooltip, how long it has waited),
## a done one with a stack of paper beside the laptop, an idle one with a mug
## there; going from one to another walks nobody. Cold passes place everyone; a
## stale floor freezes its desks; clicks by real input, on the chip too; depth
## by the feet; the framing a floor opens on. The office and its helpers are
## tools/walking_test_base.gd's.
##
## godot --headless --path . --script tools/test_office_rests.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>

## The shared fixture with every zone, for the cases that page between zones.
var whole: Dictionary = {}


func _marker() -> String:
	return "RESTS TESTS"


## These cases are about one zone's people: api's, on a map of api alone, as
## its floor was before one map per machine (the fixture's other zones would
## put their own mugs and papers on the map). Every zone's idle agents together
## are test_idle_agents_of_every_zone_sit_and_n_follows_the_wait_order.
func _run() -> void:
	whole = fixture
	fixture = _only(fixture, "api")
	await super()


# --- blocked and done at the seat -------------------------------------------------


## A working agent that goes blocked stays in the chair: nobody walks, the hand
## goes up at the desk, and the chip appears over the head at once, with the
## wait inside it (the seat has no wait label of its own) and, on an
## office that reads nothing, `read-only` where the question would be. A freshly
## launched agent that comes up blocked stays seated too.
func test_a_blocked_agent_stays_seated_with_a_hand_up_and_a_bubble() -> void:
	var office := await _live_office()
	OS.delay_msec(5)
	_feed(office, _with(fixture, "api:p2", {"agent_status": "blocked"}))
	var station := _station(office, _pane("api:p2"))
	var body := station.actor()
	_eq(station.actor().position, Vector2.ZERO, "api:p2 rests at its seat")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks")
	_eq(_floor_point(office, body), _seat_of(office, "api:p2"), "still in the chair")
	_eq([str(body.look.context), body.track], ["desk", &"desk_blocked"], "hand up at the desk")
	# The plate names the seat only while it is hovered, selected or under the
	# lens (it used to show always; a 30-wide plate row is transient now).
	_eq(_plate(station).text, "main", "the plate still names the seat: the pane's name (its tab)")
	# S3 SEATTAGS (2026-10-27): plates always show on a map with few occupied
	# seats (api alone: four); the hover / selection / lens rule is a crowded
	# map's (test_lens.gd, test_a_map_with_few_seats_shows_every_plate).
	_check(OfficeFloorView.few_seats(office.frame.building_of(office.navigator.shown_key).map), "api alone: few seats")
	_check(_plate(station).visible, "and, on a map with few seats, it shows at rest")
	var bubble := station.chip()
	_check(bubble.visible, "the bubble shows at once")
	_eq(bubble.position, OfficeStation.CHIP_AT[station.side], "over this side's head")
	_check(station.get_node_or_null("Overlay/Wait") == null, "no wait label outside the lens")
	var lens: Label = station.get_node("Overlay/Lens")
	_check(not lens.visible, "and the lens line is hidden while L is not held")
	_check(bubble.get_node_or_null("%Question") == null, "the bubble writes no question: that is the tooltip's")
	await _text_tick()
	_check(
		not _wait_text(office, _pane("api:p2")).is_empty(),
		"the wait is in the bubble: " + _wait_text(office, _pane("api:p2"))
	)
	var start := _with(fixture, "api:p1", {"agent": null})
	_feed(office, start)
	office.settle()
	_feed(office, _with(_with(start, "api:p1", {"agent": "claude"}), "api:p1", {"launch_pending": true}))
	office.settle()
	var launching := _station(office, _pane("api:p1"))
	_check(not launching.chip().visible, "a pane still launching has no bubble")
	# Blocked comes first: the launch above is at work; one that asks while herdr
	# still launches it is a blocked agent, hand up, chip, blocked badge.
	var asking := _with(start, "api:p1", {"agent": "claude", "agent_status": "blocked"})
	_feed(office, _with(asking, "api:p1", {"launch_pending": true}))
	office.settle()
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches it")
	_check(launching.chip().visible, "launching but blocked: the bubble shows")
	_eq(launching.actor().track, &"desk_blocked", "the hand is up at the desk")
	var badge: StatusBadge = launching.get_node("Overlay/Badge")
	_eq(badge.state, ArtContract.STATE_BLOCKED, "its badge pulses for blocked")
	_check(badge.is_in_group(StatusBadge.GROUP), "with the others")
	var hourglass := office.art.sprite_texture(office.art.ui_sprite(ArtContract.UI_STARTING))
	_check(badge.texture != hourglass, "the blocked badge, not the hourglass")
	_feed(
		office,
		_with(
			_with(start, "api:p1", {"agent": "claude", "agent_status": "blocked"}), "api:p1", {"launch_pending": false}
		)
	)
	_eq(launching.actor().position, Vector2.ZERO, "launched straight into blocked: it stays seated")
	_check(not office.floor_view.presentation.is_walking(_pane("api:p1")), "and does not walk")
	_check(launching.chip().visible, "with its bubble")
	await _same_as_rebuild(office, "with a blocked agent seated")
	_done(office)


## However many are blocked, every one sits with their hand up and their own
## chip: there is no queue to fill and no `+N` anywhere; there is no
## reception counter at all.
func test_every_blocked_agent_sits_however_many() -> void:
	var crowd := _crowded(12)
	var office := await _live_office(crowd)
	for pane: Dictionary in _list(crowd, "panes"):
		pane.agent_status = "blocked"
	_feed(office, crowd)
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks")
	var seated := 0
	for index in 12:
		var key := HerdrFleet.pane_key(LOCAL, "crowd:p%02d" % index)
		var station := _station(office, key)
		_eq(station.actor().position, Vector2.ZERO, key + " sits")
		_eq(station.actor().track, &"desk_blocked", key + ": hand up at the desk")
		_check(station.chip().visible, key + ": with a bubble")
		seated += 1
	_eq(seated, 12, "all twelve at their seats")
	_eq(office.floor_view.sorted.get_node_or_null("Fixture_reception"), null, "no reception counter")
	for label: Node in office.world.find_children("*", "Label", true, false):
		_check(not (label as Label).text.begins_with("+"), "no +N anywhere: " + (label as Label).text)
	_done(office)


## A done agent sits where it worked and the table puts a stack of paper beside
## its laptop, on its side: only that seat's. Back at work, the paper goes. A
## pane still launching with a done status has none, nor has a done shell.
func test_a_done_agent_sits_with_papers_on_the_desk() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p1", {"agent_status": "done"}))
	var station := _station(office, _pane("api:p1"))
	_eq(station.actor().position, Vector2.ZERO, "api:p1 rests at its seat")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks")
	_eq(_floor_point(office, station.actor()), _seat_of(office, "api:p1"), "still in the chair")
	_eq(_shown_papers(office), [_pane("api:p1")], "only its seat has paper")
	var stack := station.table.item(station.column, station.side)
	_eq(stack.texture, _texture(office, ArtContract.PROP_DONE_STACK_SMALL), "the small stack's picture")
	var plane := OfficeTable.ITEM_FAR if station.side == "far" else OfficeTable.ITEM_NEAR
	_eq(
		stack.position,
		Vector2(station.table.columns[station.column] + OfficeTable.ITEM_ASIDE, plane),
		"beside the laptop, on its side's working plane"
	)
	_check(station.chip().visible == false, "and no bubble")
	_feed(office, fixture)
	_eq(_shown_papers(office), [], "back at work: no paper")
	var start := _with(fixture, "api:p1", {"agent": null})
	_feed(
		office,
		_with(_with(start, "api:p1", {"agent": "claude", "agent_status": "done"}), "api:p1", {"launch_pending": true})
	)
	_eq(_shown_papers(office), [], "a pane still launching has none")
	_feed(office, _with(start, "api:p1", {"agent_status": "done"}))
	_eq(_shown_papers(office), [], "nor has a shell")
	_done(office)


## A click on a chip, by real input, picks its pane: once over a far seat's
## chip and once over a near one's. It is the chip's rectangle that answers
## (the station says `asked`, not `picked`), and a click on the seat below it
## still only picks. A read-only office has no answer mode to open.
func test_a_click_on_a_bubble_picks_its_pane() -> void:
	var snapshot := _with(fixture, "api:p3", {"agent": "codex"})
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		snapshot = _with(snapshot, pane_id, {"agent_status": "blocked"})
	var office := await _live_office(snapshot)
	office.settle()
	var sides: Dictionary[String, OfficeStation] = {}
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		var station := _station(office, _pane(pane_id))
		if not sides.has(station.side):
			sides[station.side] = station
	_eq(sides.keys().size(), 2, "blocked agents on both sides of a table")
	var other := _pane("api:p4")
	for side: String in ["far", "near"]:
		var station: OfficeStation = sides.get(side)
		if station == null:
			continue
		var heard: Array[String] = []
		var on_ask := func(key: String, _at: Vector2) -> void: heard.append("asked " + key)
		var on_pick := func(key: String, _at: Vector2) -> void: heard.append("picked " + key)
		station.asked.connect(on_ask)
		station.picked.connect(on_pick)
		await _click_desk(office, other)
		_eq(office.picked_key, other, side + ": another desk is picked first")
		heard.clear()
		var bubble := station.chip_rect()
		office.camera.reveal(
			Rect2(office.world.to_local(bubble.position - Vector2(8, 8)), bubble.size + Vector2(16, 16))
		)
		await _frames(2)
		await _click(bubble.get_center() - office.camera.position)
		_eq(heard, ["asked " + station.pane_key], side + ": the bubble's rectangle answered")
		_eq(office.picked_key, station.pane_key, side + ": a click on the bubble picks its pane")
		_check(not office.hud.inspector.answering(), side + ": read-only, so no answer mode")
		await _click_desk(office, other)
		heard.clear()
		await _click_desk(office, station.pane_key)
		_eq(heard, ["picked " + station.pane_key], side + ": a click on the seat still only picks")
		station.asked.disconnect(on_ask)
		station.picked.disconnect(on_pick)
	_done(office)


## The chip follows its agent: back at work it goes, and its rectangle stops
## answering; blocked again it comes back, in its frame. When the machine drops,
## the chip stays where it was, dimmed with the floor, with no wait, no bar and
## no frame: a number that would go on growing off a snapshot nobody receives is
## not drawn, and an empty frame would read as a blank speech bubble. Its
## rectangle still answers.
func test_a_bubble_follows_its_agent_and_its_machine() -> void:
	var office := await _live_office()
	var blocked := _with(fixture, "api:p2", {"agent_status": "blocked"})
	_feed(office, blocked)
	var station := _station(office, _pane("api:p2"))
	var target: CollisionShape2D = station.get_node(OfficeStation.CHIP_TARGET)
	_check(station.chip().visible and not target.disabled, "blocked: the bubble shows and answers")
	_feed(office, fixture)
	_check(not station.chip().visible, "working: the bubble goes")
	_check(target.disabled, "and its rectangle answers nothing")
	_eq(station.chip_rect(), Rect2(), "nor is there a rectangle to reveal")
	OS.delay_msec(5)
	_feed(office, blocked)
	await _text_tick()
	_check(station.chip().visible and not target.disabled, "blocked again: back")
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	_check(not _wait_text(office, _pane("api:p2")).is_empty(), "live: a wait")
	_check(frame.visible, "in the chip's frame")
	_eq(
		badge.position,
		OfficeStation.BADGE_AT[station.side] + OfficeStation.CHIP_BADGE_SHIFT,
		"and the badge in the chip's left half"
	)
	_set_online(office, false)
	await _text_tick()
	_check(station.chip().is_visible_in_tree(), "dropped: the chip stays")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "dimmed with the floor")
	_eq(_wait_text(office, _pane("api:p2")), "", "no wait")
	_check(not frame.visible, "nor an empty frame")
	_eq(badge.position, OfficeStation.BADGE_AT[station.side], "the badge back in the middle of its row")
	_check(not target.disabled, "its rectangle stays where it was")
	_done(office)


## A floor with chips and paper updated in place is the floor a rebuild draws.
func test_bubbles_and_papers_match_a_rebuild() -> void:
	var office := await _live_office()
	OS.delay_msec(5)
	var snapshot := _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p4", {"agent_status": "done"})
	_feed(office, snapshot)
	await _text_tick()
	await _same_as_rebuild(office, "with a bubble and paper")
	_feed(office, _with(snapshot, "api:p2", {"agent_status": "blocked"}))
	await _same_as_rebuild(office, "with a second bubble")
	_feed(office, fixture)
	await _same_as_rebuild(office, "with both gone")
	_done(office)


## The framing a floor opens on shows the selected desk, the whole of its
## table and, the desk's agent being blocked, the chip over it.
## S3 CAMERA (2026-10-28): a map opens with its back wall in view: at 800x480
## the wall's face and the far desk fit the 254-deep view together, so the
## view is lifted to the wall (pan 40) and the table's near half gives way
## under the bottom panel. The desk and its chip stay whole in view, and the
## table's top edge; the whole table is no longer.
## S3 BAND (2026-10-28): the band is one row: the wall's face and the whole
## first pod row fit the view together, so the opening shows the face from its
## top and the whole table again.
func test_the_first_framing_shows_the_desk_its_table_and_its_bubble() -> void:
	var office := await _live_office(_focused_on(_with(fixture, "api:p2", {"agent_status": "blocked"}), "api:p2"))
	office.settle()
	await _frames(2)
	var station := _station(office, _pane("api:p2"))
	var room := office.camera.free_rect().size
	var visible := Rect2(office.camera.pan, room)
	var table := station.table.geometry.render_rect
	table.position += station.table.global_position
	var table_top := Rect2(table.position, Vector2(table.size.x, 1))
	for box: Rect2 in [station.target_rect(), station.chip_rect(), table_top]:
		var shown := Rect2(office.world.to_local(box.position), box.size)
		_check(visible.encloses(shown), "in view: %s in %s" % [shown, visible])
	var drawn := Rect2(office.world.to_local(table.position), table.size)
	_check(visible.encloses(drawn), "the whole table in view: %s in %s" % [drawn, visible])
	var face := office.floor_view.wall_face()
	face.position += office.floor_view.root.position
	_check(visible.encloses(face), "with the wall's face whole: %s in %s" % [face, visible])
	_eq(visible.position.y, face.position.y, "from the face's top")
	_done(office)


## The excerpt a chip says is the line of the detection text that asks: the
## last one with a `?`, trimmed of blanks and of the box and block characters a
## TUI frames it with; without one, the last line with anything on it; never
## more than OfficeQuestionReader.EXCERPT_MAX characters.
func test_the_question_excerpt_is_the_asking_line() -> void:
	var framed := "╭────────────╮\n│ Edit file src/a.rs │\n│ Do you want to proceed? │\n│ ❯ 1. Yes │\n│ 2. No │\n╰────────────╯\n"
	_eq(OfficeQuestionReader.excerpt(framed), "Do you want to proceed?", "the last asking line, unframed")
	_eq(OfficeQuestionReader.excerpt("Is it?\nReally?\n  \n"), "Really?", "the last of several")
	_eq(OfficeQuestionReader.excerpt("building\n▌ step 2 of 3 ▐\n\n"), "step 2 of 3", "no question: the last line left")
	_eq(OfficeQuestionReader.excerpt("── ──\n\n   \n"), "", "nothing but frames and blanks")
	_eq(OfficeQuestionReader.excerpt(""), "", "no text")
	var long := "x".repeat(300) + "?"
	_eq(OfficeQuestionReader.excerpt(long).length(), OfficeQuestionReader.EXCERPT_MAX, "at most 120 characters")
	_eq(OfficeQuestionReader.excerpt("a\r\nwhy?\r\n"), "why?", "carriage returns are blanks")


## The chip says a known wait in its right half, compactly
## (OfficeAttention.compact_duration(), never `+`), in its frame, and the
## badge moves into its left half; without a known wait there is no number
## and no frame, and the badge is back in the middle of the tag row. (It
## replaces the patience bar's case, test_the_patience_bar_shortens_with_the_wait:
## the bar is gone, the chip keeps only the number.)
func test_the_chip_says_the_wait_and_takes_the_badge() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var station := _station(office, _pane("api:p2"))
	var bubble := station.chip()
	var frame: NinePatchRect = bubble.get_node("%Frame")
	var wait: Label = bubble.get_node("%Wait")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	var middle: Vector2 = OfficeStation.BADGE_AT[station.side]
	var forms := {0.0: "0s", 60.0: "1m", 300.0: "5m", 5999.0: "99m", 7200.0: "2h", 400000.0: "4d"}
	for seconds: float in forms:
		bubble.show_wait(seconds)
		_eq(wait.text, forms[seconds], "%d s: the wait, compactly" % seconds)
		_check(frame.visible and wait.visible, "%d s: in its frame" % seconds)
		_eq(badge.position, middle + OfficeStation.CHIP_BADGE_SHIFT, "%d s: the badge in the chip" % seconds)
	_check(bubble.get_node_or_null("%Track") == null and bubble.get_node_or_null("%Fill") == null, "no bar")
	bubble.show_wait(-1.0)
	_check(not frame.visible and not wait.visible, "no known wait: no frame")
	_eq(wait.text, "", "and no number")
	_eq(badge.position, middle, "and the badge in the middle of its row")
	_done(office)


## The chip's wait is at most three characters (compact_duration() without its
## `+`): seconds under a minute, minutes under 100, hours under 100, then whole
## days up to 99; nothing below 0. Every form, in the chip's own face, fits its
## label: the pack's display face at 8, in a 14-unit slot.
func test_the_bubble_wait_is_short_enough_to_read() -> void:
	var forms := {
		-1.0: "",
		0.0: "0s",
		59.0: "59s",
		60.0: "1m",
		5999.0: "99m",
		6000.0: "1h",
		7199.0: "1h",
		7200.0: "2h",
		359999.0: "99h",
		360000.0: "4d",
		1.0e9: "99d",
	}
	for seconds: float in forms:
		_eq(OfficeAttention.compact_duration(seconds, false), forms[seconds], "%d s" % seconds)
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var wait: Label = _station(office, _pane("api:p2")).chip().get_node("%Wait")
	# F1 (2026-10-27): the wait is written in the pack's figures face (Tiny5), not
	# the display cut (Fusion Pixel's 8px, whose `99m` is 16 wide in a 14-wide slot).
	_eq(wait.get_theme_font_size("font_size"), OfficeChip.WAIT_PIXELS, "the figures face's native 8")
	_eq(wait.get_theme_font("font"), office.pen.figures, "in the figures face")
	var font := wait.get_theme_font("font")
	for text: String in ["59s", "99m", "99h", "99d"]:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, OfficeChip.WAIT_PIXELS).x
		_check(width <= wait.size.x, "%s is %s wide, within the label's %s" % [text, width, wait.size.x])
	_done(office)


## Hovering a blocked agent's chip, by real pointer motion, shows a HUD
## tooltip near the pointer, inside the world's part of the screen; on this
## read-only office it says read-only. Blocked in the first snapshot, its start
## was never seen: nothing of the chip is drawn, frame included, only the
## raised hand and the badge, and the chip's rectangle is where it always is,
## over the far badge, so the pointer on the badge shows the tooltip. The
## pointer leaving takes it away (onto the seat below, which says its own
## name); a drag over the chip shows none; switching
## floors takes it away.
func test_hovering_a_bubble_shows_a_tooltip() -> void:
	var office := await _live_office(_with(whole, "api:p2", {"agent_status": "blocked"}))
	var key := _pane("api:p2")
	var station := _station(office, key)
	# S3 CAMERA (2026-10-28): a map opens with its back wall in view, the near
	# seats of its first pod row under the bottom panel: the whole pod is
	# framed, so api:p3's seat below the chip is on screen.
	office.reveal(key, true)
	await _text_tick()
	var bubble := station.chip()
	_eq(station.side, "far", "api:p2 sits on the far side, under its badge")
	_eq(_wait_text(office, key), "", "blocked in the first snapshot: no wait to tell")
	_check(bubble.visible, "the bubble is there")
	var frame: NinePatchRect = bubble.get_node("%Frame")
	_check(not frame.visible, "but draws no frame")
	_eq(station.actor().track, &"desk_blocked", "the hand is up")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	_check(badge.visible, "and the badge shows")
	var target: CollisionShape2D = station.get_node(OfficeStation.CHIP_TARGET)
	_check(not target.disabled, "the bubble's rectangle answers")
	var over := station.chip_rect().intersection(badge.get_global_transform() * badge.get_rect())
	_check(over.has_area(), "over the badge: %s" % over)
	_check(not office.hud.world_tip_shown(), "no tooltip before the pointer comes")
	await _parsed(_motion(over.get_center() - office.camera.position))
	_check(office.hud.world_tip_shown(), "the pointer on the badge: the bubble's tooltip")
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "saying read-only")
	var at := station.chip_rect().get_center() - office.camera.position
	await _parsed(_motion(at + Vector2(0, 70)))
	# 70 below the chip is the shell api:p3's seat, whose own tooltip names it now.
	var shell_tip := "main\nSHELL\napi / main"
	_eq(office.hud.world_tip_text(), shell_tip, "off it: not the bubble's, the seat under the pointer's")
	await _parsed(_motion(at))
	_check(office.hud.world_tip_shown(), "the pointer on the bubble: a tooltip")
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "read-only says so")
	var tip: Control = office.hud.get_node("%WorldTip")
	_check(office.hud.world_rect().encloses(tip.get_global_rect()), "inside the world's part of the screen")
	await _parsed(_motion(at + Vector2(0, 70)))
	_eq(office.hud.world_tip_text(), shell_tip, "the pointer leaves: the bubble's tooltip goes")
	await _parsed(_mouse_button(at + Vector2(0, 70), MOUSE_BUTTON_LEFT, true))
	await _parsed(_motion(at, true))
	_check(not office.hud.world_tip_shown(), "a drag over the bubble shows none")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	office.camera.pan = Vector2.ZERO
	office.reveal(key)
	await _frames(2)
	at = _station(office, key).chip_rect().get_center() - office.camera.position
	await _parsed(_motion(at + Vector2(0, 70)))
	await _parsed(_motion(at))
	_check(office.hud.world_tip_shown(), "back on the bubble: the tooltip again")
	# PageDown, the pointer staying where it is: the camera pans to web's zone,
	# and the chip it pointed at moves away from under it.
	await _office_key(office, KEY_PAGEDOWN)
	await _physics_frames(2)
	_eq(office.navigator.current_zone(office.frame), HerdrFleet.pane_key(LOCAL, "web"), "PageDown pans to web")
	_check(not office.hud.world_tip_shown(), "another zone in view: no tooltip")
	_done(office)


## A pointer motion to `at` (viewport pixels), the left button held with `held`.
static func _motion(at: Vector2, held := false) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return motion


# --- idle at the seat, with a mug ----------------------------------------------
# D2 (2026-10-27): idle sits with a mug; the pantry is a nook nobody walks to.


## An idle agent stays in the chair, playing desk_idle, and the table puts a
## mug beside the laptop, on its side: idle's own sign, as the paper is done's.
## Nobody walks; the badge and the plate stay at the seat, as for any state.
func test_an_idle_agent_sits_with_a_mug() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle"}))
	var station := _station(office, _pane("api:p2"))
	var body := station.actor()
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks")
	_eq(body.position, Vector2.ZERO, "api:p2 sits at its seat")
	_eq(_floor_point(office, body), _seat_of(office, "api:p2"), "in the chair")
	_eq([str(body.look.context), body.track], ["desk", &"desk_idle"], "idle at the desk")
	_eq(_shown(office, ArtContract.PROP_IDLE_MUG), [_pane("api:p2")], "only its seat has a mug")
	var mug := station.table.item(station.column, station.side)
	_eq(mug.texture, _texture(office, ArtContract.PROP_IDLE_MUG), "the idle mug's picture")
	var plane := OfficeTable.ITEM_FAR if station.side == "far" else OfficeTable.ITEM_NEAR
	_eq(
		mug.position,
		Vector2(station.table.columns[station.column] + OfficeTable.MUG_ASIDE, plane),
		"beside the laptop, on its side's working plane"
	)
	_check(not station.chip().visible, "and no bubble")
	_eq(_plate(station).text, "main", "the plate names the seat, as for any state")
	await _same_as_rebuild(office, "with an idle agent at the seat")
	_done(office)


## However many go idle, every one sits at their own seat with their own mug:
## there is no pantry to fill. Three residents and the api zone's four agents.
func test_every_idle_agent_sits_however_many() -> void:
	var office := await _live_office(_with_residents(fixture))
	var snapshot := _with(_with_residents(fixture), "api:p3", {"agent": "codex"})
	_feed(office, snapshot)
	office.settle()
	var panes: Array[String] = ["api:r0", "api:r1", "api:r2", "api:p1", "api:p2", "api:p3", "api:p4"]
	for pane_id in panes:
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
	_feed(office, snapshot)
	_eq(_ids(_walkers(office)), [], "nobody walks")
	var keys: Array = []
	for pane_id in panes:
		var station := _station(office, _pane(pane_id))
		_eq(station.actor().position, Vector2.ZERO, pane_id + ": at the seat")
		_eq(station.actor().track, &"desk_idle", pane_id + ": idle at the desk")
		keys.append(_pane(pane_id))
	keys.sort()
	var mugs := _shown(office, ArtContract.PROP_IDLE_MUG)
	mugs.sort()
	_eq(mugs, keys, "seven mugs, one at each idle seat")
	await _same_as_rebuild(office, "with seven idle at their seats")
	_done(office)


## Going idle and back walks nobody, far and near: working, idle, blocked,
## done, idle again. The same body stays in the chair, its hand up only while
## blocked, and the one item beside the laptop swaps in place: the mug while
## idle, the paper while done, nothing otherwise.
func test_going_idle_and_back_walks_nobody() -> void:
	var start := _with(fixture, "api:p3", {"agent": "codex"})
	var office := await _live_office(start)
	office.settle()
	var steps: Array[String] = ["idle", "blocked", "done", "idle", "working"]
	var tracks: Array[StringName] = [&"desk_idle", &"desk_blocked", &"desk_idle", &"desk_idle", &"desk_work"]
	var items: Array[StringName] = [ArtContract.PROP_IDLE_MUG, &"", ArtContract.PROP_DONE_STACK_SMALL]
	items.append_array([ArtContract.PROP_IDLE_MUG, &""])
	for pane_id: String in ["api:p2", "api:p3"]:
		var station := _station(office, _pane(pane_id))
		var body := station.actor()
		var item := station.table.item(station.column, station.side)
		var where := "%s (%s)" % [pane_id, station.side]
		var snapshot := start
		for index in steps.size():
			snapshot = _with(snapshot, pane_id, {"agent_status": steps[index]})
			_feed(office, snapshot)
			var state := "%s %s" % [where, steps[index]]
			_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], state + ": nobody walks")
			_eq(station.actor(), body, state + ": the same body")
			_eq(body.position, Vector2.ZERO, state + ": in the chair")
			_eq(body.track, tracks[index], state + ": playing " + tracks[index])
			_eq(station.table.item(station.column, station.side), item, state + ": the same item sprite")
			_eq(station.table.item_piece(station.column, station.side), items[index], state + ": the item")
			_eq(item.visible, items[index] != &"", state + ": shown or not")
			_eq(station.chip().visible, steps[index] == "blocked", state + ": the chip only while blocked")
	_done(office)


## The last pane of a tab closed while its agent idles: the tab and its table
## are gone at once and the worker walks out from the seat to the lift door,
## as a ghost.
func test_an_idle_worker_whose_tab_closes_leaves_from_the_seat() -> void:
	var office := await _live_office()
	var snapshot := _with(fixture, "api:p4", {"agent_status": "idle"})
	_feed(office, snapshot)
	office.settle()
	var station := _station(office, _pane("api:p4"))
	var body := station.actor()
	var seat := _seat_of(office, "api:p4")
	_eq(_floor_point(office, body), seat, "api:p4 idles at its seat")
	var closed := _without(snapshot, "api:p4")
	closed.tabs = _list(closed, "tabs").filter(func(each: Dictionary) -> bool: return each.tab_id != "api:t2")
	_feed(office, closed)
	_eq(_ids(_ghosts(office)), _ids([body]), "its worker leaves as a ghost")
	var route := _route(office, body)
	_eq(route[0], seat, "from the seat")
	_eq(_last(route), _door(office), "to the lift door")
	_check_routes(office.floor_view, office.art.people, "an idle worker leaving")
	_done(office)


## Another agent in a pane whose agent idles: the one at the seat walks out as
## a ghost, the new one walks in at the door to the same seat and, idle too,
## sits there with the mug, which never left the desk.
func test_another_agent_in_an_idle_pane_walks_out_and_in() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "idle"}))
	var station := _station(office, _pane("api:p2"))
	var codex := station.actor()
	var seat := _seat_of(office, "api:p2")
	_eq(_floor_point(office, codex), seat, "codex idles at its seat")
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle", "agent": "claude"}))
	_eq(_ids(_ghosts(office)), _ids([codex]), "codex leaves")
	_eq(_route(office, codex)[0], seat, "from the seat")
	var claude := station.actor()
	_eq(_floor_point(office, claude), _door(office), "claude comes in at the door")
	_eq(_last(_route(office, claude)), seat, "to the seat")
	_eq(_shown(office, ArtContract.PROP_IDLE_MUG), [_pane("api:p2")], "the mug stays on the desk meanwhile")
	_check_routes(office.floor_view, office.art.people, "one agent for another in an idle pane")
	office.settle()
	_eq([claude.position, claude.track], [Vector2.ZERO, &"desk_idle"], "claude lands in the chair, idle")
	await _same_as_rebuild(office, "after the idle pane changed hands")
	_done(office)


## A new session of the same agent while it idles: its idle began when we saw
## the new session (docs/VISUAL_LANGUAGE.md, "Identity"), and that changes
## nothing at the desk: the same body in the chair, no ghost, nobody walking,
## and the mug where it was.
func test_a_new_session_of_an_idle_agent_walks_nobody_and_keeps_the_mug() -> void:
	var office := await _live_office(_with_residents(fixture))
	var snapshot := _with(_with_residents(fixture), "api:p1", {"agent_status": "idle"})
	_feed(office, snapshot)
	office.settle()
	var station := _station(office, _pane("api:p1"))
	var p1 := station.actor()
	var mug := station.table.item(station.column, station.side)
	OS.delay_msec(5)
	_feed(office, _with(snapshot, "api:p1", {"terminal_id": "term-api-p1-again"}))
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks, nobody leaves")
	_eq(station.actor(), p1, "the same body")
	_eq([p1.position, p1.track], [Vector2.ZERO, &"desk_idle"], "in the chair, idle")
	_eq(station.table.item(station.column, station.side), mug, "the same item sprite")
	_check(
		mug.visible and station.table.item_piece(station.column, station.side) == ArtContract.PROP_IDLE_MUG, "the mug"
	)
	_check(office.fleet.state_since(LOCAL, "api:p1") > 0.0, "its idle began when the new session was seen")
	_done(office)


## Drawn afresh, a floor puts everyone at their seat at once, walking nobody:
## the first draw, another theme, a reconnect. The blocked sit with their hand
## up and their chip, the done with their paper, the idle with their mug.
func test_a_cold_pass_places_everyone_at_their_seat() -> void:
	var snapshot := _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p2", {"agent_status": "idle"})
	snapshot = _with(snapshot, "api:p4", {"agent_status": "done"})
	var office := await _live_office(snapshot)
	var check := func(when: String) -> void:
		_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], when + ": nobody walks")
		for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
			var station := _station(office, _pane(pane_id))
			_eq(_floor_point(office, station.actor()), _seat_of(office, pane_id), when + ": " + pane_id + " sits")
		var blocked := _station(office, _pane("api:p1"))
		_eq(blocked.actor().track, &"desk_blocked", when + ": hand up")
		_check(blocked.chip().visible, when + ": under its bubble")
		_eq(_station(office, _pane("api:p2")).actor().track, &"desk_idle", when + ": p2 idle at the desk")
	check.call("first drawn")
	_eq(
		[_shown_papers(office), _shown(office, ArtContract.PROP_IDLE_MUG)],
		[[_pane("api:p4")], [_pane("api:p2")]],
		"p4's paper, p2's mug"
	)
	office.switch_theme(_second_pack())
	check.call("another theme")
	_eq(
		[_shown_papers(office), _shown(office, ArtContract.PROP_IDLE_MUG)],
		[[_pane("api:p4")], [_pane("api:p2")]],
		"after the theme"
	)
	_set_online(office, false)
	_feed(office, _with(snapshot, "api:p4", {"agent_status": "idle"}), false)
	_set_online(office, true)
	check.call("reconnected")
	_eq(_station(office, _pane("api:p4")).actor().track, &"desk_idle", "reconnected: p4 idle at the desk")
	_eq(_shown_papers(office), [], "its paper gone")
	var mugs := _shown(office, ArtContract.PROP_IDLE_MUG)
	mugs.sort()
	_eq(mugs, [_pane("api:p2"), _pane("api:p4")], "and its mug there")
	_done(office)


## While Local is stale its floor stands still, mugs and paper included: dimmed
## with the map, frozen as they were through a real click, `N` (which finds the
## blocked agent on a second, live machine and switches to its map; the section
## brings us back, the map drawn afresh) and that machine's snapshot. `N` never
## visits the stale machine's done desk, before or after; back online, the
## first snapshot places everyone, walking nobody.
func test_a_stale_floor_keeps_its_mugs_and_papers() -> void:
	var office := await _two_machine_office(_with_residents(fixture), PLAN_SCREEN)
	var snapshot := _with_residents(fixture)
	for pane_id: String in ["api:p4", "api:p2"]:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
		_feed(office, snapshot)
	snapshot = _with(snapshot, "api:p1", {"agent_status": "done"})
	_feed(office, snapshot)
	office.settle()
	var items := func() -> Array:
		var mugs := _shown(office, ArtContract.PROP_IDLE_MUG)
		mugs.sort()
		return [mugs, _shown_papers(office)]
	var mugs_at: Array = [_pane("api:p2"), _pane("api:p4"), _pane("api:r0"), _pane("api:r1"), _pane("api:r2")]
	mugs_at.sort()
	var standing: Array = [mugs_at, [_pane("api:p1")]]
	_eq(items.call(), standing, "five mugs and one paper")
	_set_online(office, false)
	_check(not office.stale, "the other machine is still live")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "dropped: the floor dims")
	_eq(items.call(), standing, "dropped: the desks as they stood")
	await _click_desk(office, _pane("api:p4"))
	_eq(items.call(), standing, "after a click")
	var api := HerdrFleet.pane_key(LOCAL, "api")
	await _office_key(office, KEY_N)
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "hive:p1"), "N finds the live machine's blocked agent, not p1")
	_eq(office.navigator.shown_key, BEE, "and switches to its map")
	await _visit_zone(office, api)
	_eq(office.navigator.shown_key, LOCAL, "the section brings us back")
	_eq(items.call(), standing, "after N and back: drawn afresh, the same desks")
	_feed_bee(office, _bee_snapshot("working"))
	_eq(items.call(), standing, "after another machine's snapshot")
	_eq(_ids(_walkers(office)), [], "and nobody walks")
	await _same_as_rebuild(office, "a stale floor with mugs and paper")
	_eq(items.call(), standing, "after the floor is drawn afresh")
	_set_online(office, true)
	_eq(items.call(), standing, "back: the same desks")
	_eq(_ids(_walkers(office)), [], "placed, not walked")
	_done(office)


## Clicks, by real input: an idle worker at their seat picks that pane, as any
## seat does; the pantry counter picks nothing.
func test_clicks_pick_idle_workers_at_their_seats_and_the_counter_picks_nothing() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle"}))
	office.settle()
	var other := _pane("api:p4")
	var station := _station(office, _pane("api:p2"))
	await _click_desk(office, other)
	_eq(office.picked_key, other, "another desk is picked first")
	office.reveal(_pane("api:p2"))
	await _frames(2)
	_eq(station.actor().position, Vector2.ZERO, "the idle worker sits in the chair")
	var on_body := station.actor().global_position + Vector2(0, -20)
	await _click(on_body - office.camera.position)
	_eq(office.picked_key, _pane("api:p2"), "a click on the idle worker in the chair picks the pane")
	await _click_desk(office, other)
	await _click_desk(office, _pane("api:p2"))
	_eq(office.picked_key, _pane("api:p2"), "and so does one on the seat's rectangle")
	await _click_desk(office, other)
	var counter: Node2D = office.floor_view.sorted.get_node("Fixture_pantry")
	office.camera.reveal(Rect2(office.world.to_local(counter.global_position - Vector2(40, 60)), Vector2(80, 80)))
	await _frames(2)
	await _click(counter.global_position + Vector2(0, -12) - office.camera.position)
	_eq(office.picked_key, other, "a click on the pantry counter picks nothing")
	_done(office)


## Depth is the feet's: the counter sorts as itself, its foot at map y 78, and
## a worker walking in along the walking lane (y 80) in front of it draws in
## front of it, sorted by their own feet. S3 BAND (2026-10-28): the band is one
## row (the foot was at 106, the lane at 112).
func test_the_nook_counter_sorts_by_its_feet() -> void:
	var office := await _live_office()
	office.settle()
	var sorted := office.floor_view.sorted
	var pantry: Node2D = sorted.get_node("Fixture_pantry")
	_eq(_entity_of(sorted, pantry), pantry, "the pantry counter sorts as itself")
	_eq(sorted.to_local(pantry.global_position).y, 78.0, "its foot at 78")
	_feed(office, _with(fixture, "api:p3", {"agent": "codex"}))
	var walker := _station(office, _pane("api:p3")).actor()
	var route := _route(office, walker)
	var lane := 0
	for point in route:
		lane += int(point.y == 80.0)
	_check(lane >= 1, "api:p3 walks in over the walking lane: %s" % route)
	var passing := false
	for frame in 400:
		_step(office, 1.0 / FPS)
		if _floor_point(office, walker).y == 80.0:
			passing = true
			break
	_check(passing, "on the lane")
	_check(walker.global_position.y > pantry.global_position.y, "in front of the counter")
	_eq(_entity_of(sorted, walker), walker, "sorted by their own feet")
	_done(office)


## A freshly launched agent shows no mug while herdr still launches it: a pane
## still launching says nothing about its agent yet, so its desk shows nothing
## and its badge is the hourglass; launched idle, the mug is on the desk at
## once and the worker, walked in at the door, sits down idle.
func test_a_launched_agent_sits_without_a_mug_until_idle() -> void:
	var start := _with(fixture, "api:p1", {"agent": null})
	var office := await _live_office(start)
	office.settle()
	var launching := _with(
		_with(start, "api:p1", {"agent": "claude", "agent_status": "idle"}), "api:p1", {"launch_pending": true}
	)
	_feed(office, launching)
	var station := _station(office, _pane("api:p1"))
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches it")
	_eq(station.table.item_piece(station.column, station.side), &"", "launching: no mug")
	_check(not station.table.item(station.column, station.side).visible, "nothing beside the laptop")
	office.settle()
	_eq(station.actor().position, Vector2.ZERO, "launching: seated")
	var launched := _with(launching, "api:p1", {"launch_pending": false})
	_feed(office, launched)
	_check(
		office.fleet.state_since(LOCAL, "api:p1") > 0.0,
		"the launched agent's idle began while we watched: a known start"
	)
	_eq(_shown(office, ArtContract.PROP_IDLE_MUG), [_pane("api:p1")], "launched idle: the mug at once")
	_eq(_ids(_walkers(office)), [], "nobody walks for it")
	office.settle()
	_eq([station.actor().position, station.actor().track], [Vector2.ZERO, &"desk_idle"], "idle at the desk")
	_done(office)


## A map drawn afresh (another machine's and back) puts everyone at their seat
## at once, walking nobody: an arriving worker who was still walking in, the
## idle with their mug, the blocked with a hand up. (Another zone of the same
## map pans and walks on: WALKING's test_a_pageup_pans_without_rebuilding.)
func test_a_floor_switch_places_everyone() -> void:
	var office := await _two_machine_office(fixture, PLAN_SCREEN)
	var snapshot := _with(fixture, "api:p2", {"agent_status": "idle"})
	_feed(office, snapshot)
	snapshot = _with(_with(snapshot, "api:p1", {"agent_status": "blocked"}), "api:p3", {"agent": "codex"})
	_feed(office, snapshot)
	_check(not _walkers(office).is_empty(), "api:p3 is still walking in when we leave")
	await _visit_zone(office, HerdrFleet.pane_key(BEE, "hive"))
	_eq(office.navigator.shown_key, BEE, "bee's map")
	await _visit_zone(office, HerdrFleet.pane_key(LOCAL, "api"))
	_eq(office.navigator.shown_key, LOCAL, "and back")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "back: nobody walks")
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		var station := _station(office, _pane(pane_id))
		_eq(_floor_point(office, station.actor()), _seat_of(office, pane_id), pane_id + " in its chair")
	_eq(_station(office, _pane("api:p2")).actor().track, &"desk_idle", "p2 idle at the desk")
	_eq(_shown(office, ArtContract.PROP_IDLE_MUG), [_pane("api:p2")], "with its mug")
	_eq(_station(office, _pane("api:p1")).actor().track, &"desk_blocked", "p1's hand up")
	_done(office)


## The first update that can be laid out after one that could not is cold:
## whatever changed meanwhile is placed, not walked: a worker arriving in a
## shell sits down at once, and whoever went idle sits with a mug.
func test_a_pass_after_a_layout_problem_places_the_idle_at_their_seats() -> void:
	var office := await _live_office()
	var idle := _with(_with(fixture, "api:p1", {"agent_status": "idle"}), "api:p2", {"agent_status": "idle"})
	idle = _with(idle, "api:p3", {"agent": "codex"})
	var twice := idle.duplicate(true)
	var repeated: Dictionary = _list(twice, "panes")[1]
	_list(twice, "panes").append(repeated.duplicate(true))
	_feed(office, twice)
	_check(not office.layout_problems().is_empty(), "the repeated pane cannot be laid out")
	_feed(office, idle)
	_check(office.layout_problems().is_empty(), "the corrected input can")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "and walks nobody")
	_eq(_floor_point(office, _station(office, _pane("api:p3")).actor()), _seat_of(office, "api:p3"), "p3 placed")
	for pane_id: String in ["api:p1", "api:p2"]:
		var station := _station(office, _pane(pane_id))
		_eq(_floor_point(office, station.actor()), _seat_of(office, pane_id), pane_id + " at the seat")
	var mugs := _shown(office, ArtContract.PROP_IDLE_MUG)
	mugs.sort()
	_eq(mugs, [_pane("api:p1"), _pane("api:p2")], "each with a mug")
	_done(office)


## A selected idle worker sits at their desk, so revealing it with its table
## frames both, the desk and the whole pod, in one view.
func test_revealing_an_idle_worker_frames_their_desk_and_pod() -> void:
	var office := await _wide_office(_with(fixture, "api:p4", {"agent_status": "idle"}))
	office.test_screen = Vector2(SCREEN)
	office.refresh()
	office.settle()
	await _frames(2)
	var station := _station(office, _pane("api:p4"))
	_eq(station.actor().position, Vector2.ZERO, "api:p4 idles at its seat")
	var room := office.camera.free_rect().size
	var table := station.table.geometry.render_rect
	table.position += station.table.global_position
	var both := station.target_rect().merge(table)
	_check(OfficeCamera.fits(both, room), "desk and pod fit the view together: %s in %s" % [both.size, room])
	office.camera.pan = Vector2.ZERO
	office.reveal(_pane("api:p4"), true)
	await _frames(2)
	var visible := Rect2(office.camera.pan, room)
	for box: Rect2 in [station.target_rect(), table]:
		var shown := Rect2(office.world.to_local(box.position), box.size)
		_check(visible.encloses(shown), "in view: %s in %s" % [shown, visible])
	_done(office)


## Idle agents of every zone sit at their own seats, each with a mug, nobody
## walking; then they finish, one after another in another order, and `N`
## visits their desks in the order they waited (OfficeProjection.wait_order(),
## the one ranking it has), across the zones, each done desk with its paper.
func test_idle_agents_of_every_zone_sit_and_n_follows_the_wait_order() -> void:
	var working: Dictionary = whole.duplicate(true)
	for pane: Dictionary in _list(working, "panes"):
		if pane.get("agent") != null:
			pane.agent_status = "working"
	var office := await _live_office(working)
	var order: Array[String] = ["web:p1", "api:p1", "infra:p1", "api:p2", "web:p2", "data:p1"]
	var snapshot := working
	for pane_id in order:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
		_feed(office, snapshot)
		_eq(_ids(_walkers(office)), [], pane_id + " goes idle: nobody walks")
	var keys: Array = order.map(func(pane_id: String) -> String: return _pane(pane_id))
	keys.sort()
	var mugs := _shown(office, ArtContract.PROP_IDLE_MUG)
	mugs.sort()
	_eq(mugs, keys, "six mugs, at four zones' seats")
	for pane_id in order:
		_eq(_station(office, _pane(pane_id)).actor().position, Vector2.ZERO, pane_id + " at the seat")
	var finished: Array[String] = ["data:p1", "api:p2", "web:p1", "infra:p1", "web:p2", "api:p1"]
	for pane_id in finished:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "done"})
		_feed(office, snapshot)
	_eq(_shown(office, ArtContract.PROP_IDLE_MUG), [], "done: every mug gone")
	_eq(_shown_papers(office).size(), finished.size(), "and a paper at each")
	var visited: Array[String] = []
	for index in finished.size():
		await _office_key(office, KEY_N)
		visited.append(office.picked_key)
	_eq(visited, finished.map(func(pane_id: String) -> String: return _pane(pane_id)), "N visits them as they finished")
	_done(office)


## The pane key of every seat whose stack of paper shows, in seat order.
func _shown_papers(office: OfficeDouble) -> Array:
	return _shown(office, ArtContract.PROP_DONE_STACK_SMALL)


## The pane key of every seat whose desk item shows `piece`, in seat order.
func _shown(office: OfficeDouble, piece: StringName) -> Array:
	var shown: Array = []
	for station in _seats(office):
		var item := station.table.item(station.column, station.side)
		if item.visible and station.table.item_piece(station.column, station.side) == piece:
			shown.append(station.pane_key)
	return shown


## The texture the pack draws `piece` with.
func _texture(office: OfficeDouble, piece: StringName) -> Texture2D:
	return office.art.sprite_texture(office.art.prop_sprite(piece))


## The stacks of paper and the minimap's floor row say how many are UNREAD
## with one count (OfficeProjection.floor_counts()), which counts a pane key the
## floor carries twice not at all. A malformed snapshot repeating a done pane
## cannot be laid out: the floor keeps its last valid picture, paper included,
## and the minimap's row does not count the repeated pane either.
func test_the_papers_and_the_minimap_count_unread_alike() -> void:
	var office := await _live_office()
	var api := HerdrFleet.pane_key(LOCAL, "api")
	var done := _with(fixture, "api:p1", {"agent_status": "done"})
	_feed(office, done)
	var row := office.frame.find_zone(api).zone_model
	_eq(row.done, 1, "one UNREAD on the minimap's row")
	_eq(_shown_papers(office).size(), row.done, "and one stack of paper")
	var malformed := _with(done, "api:p2", {"agent_status": "done"})
	var repeated: Dictionary = _list(malformed, "panes")[1]
	_list(malformed, "panes").append(repeated.duplicate(true))
	_feed(office, malformed)
	_check(not office.layout_problems().is_empty(), "the repeated pane cannot be laid out")
	row = office.frame.find_zone(api).zone_model
	_eq(row.done, 1, "the minimap's row counts the repeated pane not at all")
	_eq(_shown_papers(office), [_pane("api:p1")], "the floor keeps its last valid paper")
	_done(office)


## Blocked comes first: a shell whose start asks at once. herdr launches claude
## in api:p1 and it blocks before the launch is over: the desk drawn in place
## is the one a rebuild draws (hand up, chip, pulsing blocked badge), the
## plate says the pane's name, and the chip says how long it has waited, from the
## moment the office saw it block, and keeps it when the launch is over.
func test_a_start_that_asks_at_once_matches_a_rebuild() -> void:
	var start := _with(fixture, "api:p1", {"agent": null})
	var office := await _live_office(start)
	office.settle()
	_feed(office, _with(_with(start, "api:p1", {"agent": "claude"}), "api:p1", {"launch_pending": true}))
	office.settle()
	var asking := _with(start, "api:p1", {"agent": "claude", "agent_status": "blocked"})
	_feed(office, _with(asking, "api:p1", {"launch_pending": true}))
	office.settle()
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches it")
	var station := _station(office, _pane("api:p1"))
	_eq(station.actor().position, Vector2.ZERO, "at its seat")
	_check(station.chip().visible, "with the bubble over its head")
	_eq(station.actor().track, &"desk_blocked", "and its hand up")
	_eq(_plate(station).text, "refactor the fleet", "the plate says the pane's name")
	await _text_tick()
	_check(
		not _wait_text(office, _pane("api:p1")).is_empty(),
		"the bubble says how long: " + _wait_text(office, _pane("api:p1"))
	)
	# herdr finishing the launch while it still asks is no change at the desk: it
	# is not seated again, which would blank the chip's wait until the next beat.
	_feed(office, asking)
	_check(not office.frame.pane(_pane("api:p1")).starting, "the launch is over")
	_check(not _wait_text(office, _pane("api:p1")).is_empty(), "the bubble keeps its wait: the desk is not redrawn")
	await _same_as_rebuild(office, "with a start that asks at once")
	_done(office)
