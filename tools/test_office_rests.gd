extends "res://tools/walking_test_base.gd"
## Who rests where by state (OfficeRests) on the live office, and how they get
## there. Every state but idle rests at its own seat: a blocked agent
## sits with a hand up and a bubble over the head (its question's excerpt, how
## long it has waited, a patience bar), a done one sits with a stack of paper
## beside the laptop, and an idle one takes a pantry spot with a cup while the
## pantry has one; the full pantry seats the rest. A newcomer never displaces
## anyone; cold passes place everyone; a stale floor never re-ranks; clicks by
## real input, on the bubble too; depth by the feet; the framing a floor opens
## on. The office and its helpers are tools/walking_test_base.gd's.
##
## godot --headless --path . --script tools/test_office_rests.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>


func _marker() -> String:
	return "RESTS TESTS"


# --- blocked and done at the seat -------------------------------------------------


## A working agent that goes blocked stays in the chair: nobody walks, the hand
## goes up at the desk, and the bubble appears over the head at once, with the
## wait inside it (the seat has no wait label of its own) and, on an
## office that reads nothing, `read-only` where the question would be. A freshly
## launched agent that comes up blocked stays seated too.
func test_a_blocked_agent_stays_seated_with_a_hand_up_and_a_bubble() -> void:
	var office := await _live_office()
	OS.delay_msec(5)
	_feed(office, _with(fixture, "api:p2", {"agent_status": "blocked"}))
	var station := _station(office, _pane("api:p2"))
	var body := station.actor()
	_eq(station.rest, OfficeRests.Rest.SEAT, "api:p2 rests at its seat")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks")
	_eq(_floor_point(office, body), _seat_of(office, "api:p2"), "still in the chair")
	_eq([str(body.look.context), body.track], ["desk", &"desk_blocked"], "hand up at the desk")
	_check(_plate(station).visible, "the plate stays on the seat")
	var bubble := station.bubble()
	_check(bubble.visible, "the bubble shows at once")
	_eq(bubble.position, OfficeStation.BUBBLE_AT[station.side], "over this side's head")
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
	_check(not launching.bubble().visible, "a pane still launching has no bubble")
	# Blocked comes first: the launch above is at work; one that asks while herdr
	# still launches it is a blocked agent, hand up, bubble, blocked badge.
	var asking := _with(start, "api:p1", {"agent": "claude", "agent_status": "blocked"})
	_feed(office, _with(asking, "api:p1", {"launch_pending": true}))
	office.settle()
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches it")
	_check(launching.bubble().visible, "launching but blocked: the bubble shows")
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
	_eq(launching.rest, OfficeRests.Rest.SEAT, "launched straight into blocked: it stays seated")
	_check(not office.floor_view.presentation.is_walking(_pane("api:p1")), "and does not walk")
	_check(launching.bubble().visible, "with its bubble")
	await _same_as_rebuild(office, "with a blocked agent seated")
	_done(office)


## However many are blocked, every one sits with their hand up and their own
## bubble: there is no queue to fill and no `+N` anywhere; the reception is a
## plain counter.
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
		_eq(station.rest, OfficeRests.Rest.SEAT, key + " sits")
		_eq(station.actor().track, &"desk_blocked", key + ": hand up at the desk")
		_check(station.bubble().visible, key + ": with a bubble")
		seated += 1
	_eq(seated, 12, "all twelve at their seats")
	var reception := office.floor_view.sorted.get_node_or_null("Fixture_reception")
	_check(reception is OfficeDecor, "the reception is a plain counter")
	if reception != null:
		_check(reception.get_node_or_null("Overlay") == null, "with nothing written over it")
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
	_eq(station.rest, OfficeRests.Rest.SEAT, "api:p1 rests at its seat")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "nobody walks")
	_eq(_floor_point(office, station.actor()), _seat_of(office, "api:p1"), "still in the chair")
	_eq(_shown_papers(office), [_pane("api:p1")], "only its seat has paper")
	var stack := station.table.papers(station.column, station.side)
	var decor := OfficeTable.DECOR_FAR if station.side == "far" else OfficeTable.DECOR_NEAR
	_eq(
		stack.position,
		Vector2(station.table.columns[station.column] + OfficeTable.PAPERS_ASIDE, decor),
		"beside the laptop, on its side's working plane"
	)
	_check(station.bubble().visible == false, "and no bubble")
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


## A click on a bubble, by real input, picks its pane: once over a far seat's
## bubble and once over a near one's. It is the bubble's rectangle that answers
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
		var bubble := station.bubble_rect()
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


## The bubble follows its agent: back at work it goes, and its rectangle stops
## answering; blocked again it comes back, in its frame. When the machine drops,
## the bubble stays where it was, dimmed with the floor, with no wait, no bar and
## no frame: a number that would go on growing off a snapshot nobody receives is
## not drawn, and an empty frame would read as a blank speech bubble. Its
## rectangle still answers.
func test_a_bubble_follows_its_agent_and_its_machine() -> void:
	var office := await _live_office()
	var blocked := _with(fixture, "api:p2", {"agent_status": "blocked"})
	_feed(office, blocked)
	var station := _station(office, _pane("api:p2"))
	var target: CollisionShape2D = station.get_node(OfficeStation.BUBBLE_TARGET)
	_check(station.bubble().visible and not target.disabled, "blocked: the bubble shows and answers")
	_feed(office, fixture)
	_check(not station.bubble().visible, "working: the bubble goes")
	_check(target.disabled, "and its rectangle answers nothing")
	_eq(station.bubble_rect(), Rect2(), "nor is there a rectangle to reveal")
	OS.delay_msec(5)
	_feed(office, blocked)
	await _text_tick()
	_check(station.bubble().visible and not target.disabled, "blocked again: back")
	var track: ColorRect = station.bubble().get_node("%Track")
	var fill: ColorRect = station.bubble().get_node("%Fill")
	var frame: NinePatchRect = station.bubble().get_node("%Frame")
	_check(not _wait_text(office, _pane("api:p2")).is_empty(), "live: a wait")
	_check(track.visible and fill.visible, "and a bar")
	_check(frame.visible, "in the bubble's frame")
	_set_online(office, false)
	await _text_tick()
	_check(station.bubble().is_visible_in_tree(), "dropped: the bubble stays")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "dimmed with the floor")
	_eq(_wait_text(office, _pane("api:p2")), "", "no wait")
	_check(not track.visible and not fill.visible, "and no bar")
	_check(not frame.visible, "nor an empty frame")
	_check(not target.disabled, "its rectangle stays where it was")
	_done(office)


## A floor with bubbles and paper updated in place is the floor a rebuild draws.
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
## table and, the desk's agent being blocked, the bubble over it.
func test_the_first_framing_shows_the_desk_its_table_and_its_bubble() -> void:
	var office := await _live_office(_focused_on(_with(fixture, "api:p2", {"agent_status": "blocked"}), "api:p2"))
	office.settle()
	await _frames(2)
	var station := _station(office, _pane("api:p2"))
	var room := office.camera.free_rect().size
	var visible := Rect2(office.camera.pan, room)
	var table := station.table.geometry.render_rect
	table.position += station.table.global_position
	for box: Rect2 in [station.target_rect(), station.bubble_rect(), table]:
		var shown := Rect2(office.world.to_local(box.position), box.size)
		_check(visible.encloses(shown), "in view: %s in %s" % [shown, visible])
	_done(office)


## The excerpt a bubble says is the line of the detection text that asks: the
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


## The patience bar is full when the wait starts and empties over ten minutes,
## always in the pack's `blocked` colour: only its length says anything. The
## fill never goes below two units. Without a known wait there is no bar.
func test_the_patience_bar_shortens_with_the_wait() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var bubble := _station(office, _pane("api:p2")).bubble()
	var track: ColorRect = bubble.get_node("%Track")
	var fill: ColorRect = bubble.get_node("%Fill")
	var wait: Label = bubble.get_node("%Wait")
	var widths := {0.0: 40.0, 60.0: 36.0, 300.0: 20.0, 600.0: 2.0, 900.0: 2.0}
	for seconds: float in widths:
		bubble.show_wait(seconds)
		_eq(fill.size.x, widths[seconds], "%d s: the fill's width" % seconds)
		_eq(fill.color, office.art.color(ArtContract.BLOCKED), "%d s: always the blocked colour" % seconds)
		_check(track.visible and fill.visible, "%d s: a bar" % seconds)
		_eq(wait.text, OfficeBubble.wait_text(seconds), "%d s: the wait, in the bubble's short form" % seconds)
	_eq(OfficeBubble.patience(0.0), 1.0, "full at the start")
	_eq(OfficeBubble.patience(300.0), 0.5, "half after five minutes")
	_eq(OfficeBubble.patience(900.0), 0.0, "empty after ten")
	_eq(track.color, office.art.color(ArtContract.MUTED), "the track is muted")
	bubble.show_wait(-1.0)
	_check(not track.visible and not fill.visible, "no known wait: no bar")
	_eq(wait.text, "", "and no number")
	_done(office)


## The bubble's wait is at most three characters, so it fits beside the badge
## at its larger size: seconds under a minute, minutes under 100, then whole
## hours; nothing below 0. Every form, at the bubble's own font, fits its label.
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
	}
	for seconds: float in forms:
		_eq(OfficeBubble.wait_text(seconds), forms[seconds], "%d s" % seconds)
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var wait: Label = _station(office, _pane("api:p2")).bubble().get_node("%Wait")
	_eq(wait.get_theme_font_size("font_size"), OfficeBubble.WAIT_PIXELS, "larger than a plate's 10")
	var font := wait.get_theme_font("font")
	for text: String in ["59s", "99m", "99h"]:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, OfficeBubble.WAIT_PIXELS).x
		_check(width <= wait.size.x, "%s is %s wide, within the label's %s" % [text, width, wait.size.x])
	_done(office)


## Hovering a blocked agent's bubble, by real pointer motion, shows a HUD
## tooltip near the pointer, inside the world's part of the screen; on this
## read-only office it says read-only. Blocked in the first snapshot, its start
## was never seen: nothing of the bubble is drawn, frame included, only the
## raised hand and the badge, and the bubble's rectangle is where it always is,
## over the far badge, so the pointer on the badge shows the tooltip. The
## pointer leaving takes it away; a drag over the bubble shows none; switching
## floors takes it away.
func test_hovering_a_bubble_shows_a_tooltip() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var key := _pane("api:p2")
	var station := _station(office, key)
	office.reveal(key)
	await _text_tick()
	var bubble := station.bubble()
	_eq(station.side, "far", "api:p2 sits on the far side, under its badge")
	_eq(_wait_text(office, key), "", "blocked in the first snapshot: no wait to tell")
	_check(bubble.visible, "the bubble is there")
	var frame: NinePatchRect = bubble.get_node("%Frame")
	var track: ColorRect = bubble.get_node("%Track")
	_check(not frame.visible, "but draws no frame")
	_check(not track.visible, "nor a bar")
	_eq(station.actor().track, &"desk_blocked", "the hand is up")
	var badge: Sprite2D = station.get_node("Overlay/Badge")
	_check(badge.visible, "and the badge shows")
	var target: CollisionShape2D = station.get_node(OfficeStation.BUBBLE_TARGET)
	_check(not target.disabled, "the bubble's rectangle answers")
	var over := station.bubble_rect().intersection(badge.get_global_transform() * badge.get_rect())
	_check(over.has_area(), "over the badge: %s" % over)
	_check(not office.hud.bubble_tip_shown(), "no tooltip before the pointer comes")
	await _parsed(_motion(over.get_center() - office.camera.position))
	_check(office.hud.bubble_tip_shown(), "the pointer on the badge: the bubble's tooltip")
	_eq(office.hud.bubble_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "saying read-only")
	var at := station.bubble_rect().get_center() - office.camera.position
	await _parsed(_motion(at + Vector2(0, 70)))
	_check(not office.hud.bubble_tip_shown(), "off it: none")
	await _parsed(_motion(at))
	_check(office.hud.bubble_tip_shown(), "the pointer on the bubble: a tooltip")
	_eq(office.hud.bubble_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "read-only says so")
	var tip: Control = office.hud.get_node("%BubbleTip")
	_check(office.hud.world_rect().encloses(tip.get_global_rect()), "inside the world's part of the screen")
	await _parsed(_motion(at + Vector2(0, 70)))
	_check(not office.hud.bubble_tip_shown(), "the pointer leaves: no tooltip")
	await _parsed(_mouse_button(at + Vector2(0, 70), MOUSE_BUTTON_LEFT, true))
	await _parsed(_motion(at, true))
	_check(not office.hud.bubble_tip_shown(), "a drag over the bubble shows none")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	office.camera.pan = Vector2.ZERO
	office.reveal(key)
	await _frames(2)
	at = _station(office, key).bubble_rect().get_center() - office.camera.position
	await _parsed(_motion(at + Vector2(0, 70)))
	await _parsed(_motion(at))
	_check(office.hud.bubble_tip_shown(), "back on the bubble: the tooltip again")
	# PageUp, the pointer staying where it is: the floor it pointed at is gone.
	await _office_key(office, KEY_PAGEUP)
	_eq(office.navigator.shown_key, HerdrFleet.pane_key(LOCAL, "web"), "PageUp shows web")
	_check(not office.hud.bubble_tip_shown(), "another floor: no tooltip")
	_done(office)


## A pointer motion to `at` (viewport pixels), the left button held with `held`.
static func _motion(at: Vector2, held := false) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	return motion


# --- the pantry, and moving between the seat and it ------------------------------


## An idle agent walks to the pantry and stands there facing the viewer with a
## cup: the drink track, by name. Their badge goes there with them, no plate.
func test_an_idle_agent_rests_in_the_pantry_with_a_cup() -> void:
	var office := await _live_office()
	var spots := office.layout_plan().pantry.spots
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle"}))
	var station := _station(office, _pane("api:p2"))
	var body := station.actor()
	var spot := station.position + station.rest_position()
	_eq(station.rest, OfficeRests.Rest.PANTRY, "api:p2 rests in the pantry")
	_check(spots.has(spot), "on one of its spots: %s" % spot)
	_check(not _plate(station).visible, "with no plate")
	var route := _route(office, body)
	_eq(_last(route), spot, "walking to the spot")
	_eq(route[route.size() - 2], Vector2(spot.x, 144), "up from the walking lane")
	_walk_along(office, body, route, 1.0 / FPS)
	_eq(_floor_point(office, body), spot, "where they stand")
	_eq([body.track, body.facing, str(body.look.context)], [&"drink", &"front", "stand"], "facing the viewer, a cup")
	await _same_as_rebuild(office, "with somebody in the pantry")
	_done(office)


## A pantry with no free spot seats whoever comes after it, idle at the desk.
func test_a_full_pantry_seats_the_rest() -> void:
	var office := await _live_office()
	var spots := office.layout_plan().pantry.spots.size()
	var snapshot := _with(fixture, "api:p3", {"agent": "codex"})
	var panes: Array[String] = ["api:p1", "api:p2", "api:p3", "api:p4"]
	_check(spots < panes.size(), "a pantry of %d for %d idle" % [spots, panes.size()])
	for pane_id in panes:
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
	_feed(office, snapshot)
	office.settle()
	var resting := 0
	for pane_id in panes:
		var station := _station(office, _pane(pane_id))
		if station.rest == OfficeRests.Rest.PANTRY:
			resting += 1
			continue
		_eq(station.rest, OfficeRests.Rest.SEAT, pane_id + ": the pantry is full, so the seat")
		_eq(station.actor().track, &"desk_idle", pane_id + ": idle at the desk")
	_eq(resting, spots, "the pantry full")
	await _same_as_rebuild(office, "with the pantry full")
	_done(office)


## Leaving one resting place for another walks from where they rest: from the
## seat to the pantry going idle, from the pantry back to the seat going
## blocked (hand up there) or done, and from the seat to the pantry again.
func test_resting_places_walk_from_one_to_another() -> void:
	var office := await _live_office()
	var station := _station(office, _pane("api:p2"))
	var body := station.actor()
	var steps: Array[String] = ["idle", "blocked", "idle", "done"]
	var tracks: Array[StringName] = [&"drink", &"desk_blocked", &"drink", &"desk_idle"]
	var snapshot := fixture
	var was := station.position
	for index in steps.size():
		var state := steps[index]
		snapshot = _with(snapshot, "api:p2", {"agent_status": state})
		_feed(office, snapshot)
		var route := _route(office, body)
		var goal := station.position + station.rest_position()
		_check(route.size() >= 2 and route[0].is_equal_approx(was), "%s: from where they rested, %s" % [state, was])
		_eq(_last(route), goal, "%s: to where they rest now" % state)
		_check_routes(office.floor_view, office.art.people, "to " + state)
		office.settle()
		_eq(_floor_point(office, body), goal, "%s: and rest there" % state)
		_eq(body.track, tracks[index], "%s: playing %s" % [state, tracks[index]])
		was = goal
	_done(office)


## The last pane of a tab closed while its agent is in the pantry: the tab and
## its table are gone at once and the worker walks out from the pantry, down to
## the lane and to the lift door, as a ghost.
func test_a_pantry_worker_whose_tab_closes_leaves_from_the_pantry() -> void:
	var office := await _live_office()
	var snapshot := _with(fixture, "api:p4", {"agent_status": "idle"})
	_feed(office, snapshot)
	office.settle()
	var station := _station(office, _pane("api:p4"))
	var body := station.actor()
	var spot := station.position + station.rest_position()
	_eq(station.rest, OfficeRests.Rest.PANTRY, "api:p4 rests in the pantry")
	_eq(_floor_point(office, body), spot, "on its spot")
	var closed := _without(snapshot, "api:p4")
	closed.tabs = _list(closed, "tabs").filter(func(each: Dictionary) -> bool: return each.tab_id != "api:t2")
	_feed(office, closed)
	_eq(_ids(_ghosts(office)), _ids([body]), "its worker leaves as a ghost")
	var route := _route(office, body)
	_eq(route[0], spot, "from the spot")
	_eq(route[1], Vector2(spot.x, 144), "down to the walking lane first")
	_eq(_last(route), _door(office), "to the lift door")
	_check_routes(office.floor_view, office.art.people, "the pantry's worker leaving")
	_done(office)


## Another agent in a pane whose idle agent is in the pantry: the one in the
## pantry walks out from there as a ghost, the new one walks in at the door and,
## idle too, to the pantry.
func test_another_agent_in_the_pantry_walks_out_and_in() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "idle"}))
	var station := _station(office, _pane("api:p2"))
	var codex := station.actor()
	var spot := station.position + station.rest_position()
	_eq(_floor_point(office, codex), spot, "codex is in the pantry")
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle", "agent": "claude"}))
	_eq(_ids(_ghosts(office)), _ids([codex]), "codex leaves")
	_eq(_route(office, codex)[0], spot, "from the pantry")
	var claude := station.actor()
	_eq(_floor_point(office, claude), _door(office), "claude comes in at the door")
	_eq(_last(_route(office, claude)), station.position + station.rest_position(), "to the pantry")
	_check_routes(office.floor_view, office.art.people, "one agent for another in the pantry")
	office.settle()
	await _same_as_rebuild(office, "after the pantry changed hands")
	_done(office)


## A new session of the same agent while it rests in the pantry: its idle began
## when we saw the new session (a transition watched live is a known start, not
## an unknown one), so it now ranks after everyone idle longer
## (docs/VISUAL_LANGUAGE.md, "Identity"). With the pantry full it gives its spot to
## the one who waited at the desk, and sits down there itself. The same body, no
## ghost.
func test_a_new_session_in_the_pantry_ranks_from_then() -> void:
	var office := await _live_office()
	var snapshot := fixture
	for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
		_feed(office, snapshot)
	office.settle()
	_eq(office.layout_plan().pantry.spots.size(), 2, "a pantry of two")
	var rests := func() -> Array:
		var found: Array = []
		for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
			found.append(_station(office, _pane(pane_id)).rest)
		return found
	var pantry := OfficeRests.Rest.PANTRY
	var seat := OfficeRests.Rest.SEAT
	_eq(rests.call(), [pantry, pantry, seat], "p1 and p2 idle first take the pantry, p4 sits")
	var p1 := _station(office, _pane("api:p1")).actor()
	OS.delay_msec(5)
	_feed(office, _with(snapshot, "api:p1", {"terminal_id": "term-api-p1-again"}))
	_eq(_ids(_ghosts(office)), [], "nobody leaves")
	_eq(_station(office, _pane("api:p1")).actor(), p1, "the same body")
	_eq(rests.call(), [seat, pantry, pantry], "p1, its start now, sits; p4 takes the spot")
	_eq(_last(_route(office, p1)), _seat_of(office, "api:p1"), "p1 walks back to its seat")
	office.settle()
	_eq(_floor_point(office, p1), _seat_of(office, "api:p1"), "and sits there")
	_done(office)


## Drawn afresh, a floor puts everyone where they rest at once, walking nobody:
## the first draw, another theme, a reconnect. The blocked sit with their hand
## up and their bubble, the done with their paper, the idle in the pantry.
func test_a_cold_pass_places_the_pantry_and_the_seated() -> void:
	var snapshot := _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p2", {"agent_status": "idle"})
	snapshot = _with(snapshot, "api:p4", {"agent_status": "done"})
	var office := await _live_office(snapshot)
	var check := func(when: String) -> void:
		_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], when + ": nobody walks")
		for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
			var station := _station(office, _pane(pane_id))
			_eq(
				_floor_point(office, station.actor()), station.position + station.rest_position(), when + ": " + pane_id
			)
		var blocked := _station(office, _pane("api:p1"))
		_eq(blocked.rest, OfficeRests.Rest.SEAT, when + ": p1 sits")
		_eq(blocked.actor().track, &"desk_blocked", when + ": hand up")
		_check(blocked.bubble().visible, when + ": under its bubble")
		_eq(_station(office, _pane("api:p2")).rest, OfficeRests.Rest.PANTRY, when + ": p2 in the pantry")
	check.call("first drawn")
	_eq(_shown_papers(office), [_pane("api:p4")], "first drawn: p4's paper")
	office.switch_theme(MANIFESTS[1])
	check.call("another theme")
	_eq(_shown_papers(office), [_pane("api:p4")], "another theme: p4's paper")
	_set_online(office, false)
	_feed(office, _with(snapshot, "api:p4", {"agent_status": "idle"}), false)
	_set_online(office, true)
	check.call("reconnected")
	_eq(_station(office, _pane("api:p4")).rest, OfficeRests.Rest.PANTRY, "reconnected: p4 in the pantry, not walked")
	_eq(_shown_papers(office), [], "and its paper gone")
	_done(office)


## While Local is stale its pantry stands still: its client forgets every start
## the moment it drops, but the office ranks the frozen floor by the starts it
## last saw live, so a refresh never reshuffles who has a spot: a real click,
## `N` (which finds a blocked agent on a second, live machine and switches to
## its floor; the section brings us back, the floor drawn afresh) and a real
## snapshot from that other machine. The first snapshot after the reconnect is
## cold and ranks afresh: every start is unknown then, so the projection order
## decides.
func test_a_stale_pantry_is_never_reranked() -> void:
	var office := await _two_machine_office()
	var snapshot := fixture
	for pane_id: String in ["api:p4", "api:p2", "api:p1"]:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
		_feed(office, snapshot)
	office.settle()
	var pantry := OfficeRests.Rest.PANTRY
	var seat := OfficeRests.Rest.SEAT
	var rests := func() -> Array:
		var found: Array = []
		for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
			found.append(_station(office, _pane(pane_id)).rest)
		return found
	_eq(
		rests.call(),
		[seat, pantry, pantry],
		"p4 and p2 went idle first: they have the pantry, though p1 is projected first"
	)
	_set_online(office, false)
	_check(not office.stale, "the other machine is still live")
	_eq(rests.call(), [seat, pantry, pantry], "dropped: the pantry as it stood")
	await _click_desk(office, _pane("api:p4"))
	_eq(rests.call(), [seat, pantry, pantry], "after a click")
	var api := HerdrFleet.pane_key(LOCAL, "api")
	await _office_key(office, KEY_N)
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "hive:p1"), "N finds the live machine's blocked agent")
	_check(office.navigator.shown_key != api, "and switches to its floor")
	await _visit_floor(office, api)
	_eq(office.navigator.shown_key, api, "the section brings us back")
	_eq(rests.call(), [seat, pantry, pantry], "after N and back: drawn afresh, the same pantry")
	var seen := office.frame.pane(HerdrFleet.pane_key(BEE, "hive:p1"))
	_feed_bee(office, _bee_snapshot("working"))
	_check(
		seen != office.frame.pane(HerdrFleet.pane_key(BEE, "hive:p1")),
		"the other machine's snapshot refreshed the office"
	)
	_eq(rests.call(), [seat, pantry, pantry], "after another machine's snapshot")
	_eq(_ids(_walkers(office)), [], "and nobody walks")
	await _same_as_rebuild(office, "a stale pantry")
	_eq(rests.call(), [seat, pantry, pantry], "after the floor is drawn afresh")
	_set_online(office, true)
	_eq(rests.call(), [pantry, pantry, seat], "back: every start unknown, p1 first as projected")
	_eq(_ids(_walkers(office)), [], "placed, not walked")
	_done(office)


## Clicks, by real input: a worker in the pantry and the seat they left both
## pick that pane; the counters and the empty floor beside them pick nothing.
func test_clicks_pick_pantry_workers_and_their_seats() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle"}))
	office.settle()
	var other := _pane("api:p4")
	var station := _station(office, _pane("api:p2"))
	await _click_desk(office, other)
	_eq(office.picked_key, other, "another desk is picked first")
	office.reveal(_pane("api:p2"))
	await _frames(2)
	var on_body := station.actor().global_position + Vector2(0, -20)
	await _click(on_body - office.camera.position)
	_eq(office.picked_key, _pane("api:p2"), "a click on the worker in the pantry picks the pane")
	await _click_desk(office, other)
	var seat_path: NodePath = OfficeStation.TARGET_OF[station.side]
	var seat: CollisionShape2D = station.get_node(seat_path)
	_check(not seat.disabled, "the seat still answers")
	office.camera.reveal(Rect2(office.world.to_local(seat.global_position - Vector2(30, 40)), Vector2(60, 80)))
	await _frames(2)
	await _click(seat.global_position - office.camera.position)
	_eq(office.picked_key, _pane("api:p2"), "and a click on the seat they left picks it too")
	await _click_desk(office, other)
	for fixture_key: String in ["reception", "pantry"]:
		var counter: Node2D = office.floor_view.sorted.get_node("Fixture_" + fixture_key)
		office.camera.reveal(Rect2(office.world.to_local(counter.global_position - Vector2(40, 60)), Vector2(80, 80)))
		await _frames(2)
		await _click(counter.global_position + Vector2(0, -12) - office.camera.position)
		_eq(office.picked_key, other, "a click on the %s counter picks nothing" % fixture_key)
	_done(office)


## Depth is the feet's: a pantry worker (on the fixture row) draws in front of
## the pantry, the reception counter sorts as itself, and a walker passing on
## the walking lane draws in front of the pantry's people.
func test_the_pantry_sorts_by_feet() -> void:
	var office := await _live_office()
	var snapshot := _with(fixture, "api:p2", {"agent_status": "idle"})
	_feed(office, snapshot)
	office.settle()
	var sorted := office.floor_view.sorted
	var resting := _station(office, _pane("api:p2")).actor()
	var reception: Node2D = sorted.get_node("Fixture_reception")
	var pantry: Node2D = sorted.get_node("Fixture_pantry")
	_eq(_entity_of(sorted, resting), resting, "the pantry worker sorts as themselves")
	_eq(_entity_of(sorted, reception), reception, "and so does the reception counter")
	_check(resting.global_position.y > pantry.global_position.y, "the pantry worker in front of the pantry")
	_feed(office, _with(snapshot, "api:p4", {"agent_status": "idle"}))
	var walker := _station(office, _pane("api:p4")).actor()
	var passing := false
	for frame in 400:
		_step(office, 1.0 / FPS)
		if _floor_point(office, walker).y == 144.0:
			passing = true
			break
	_check(passing, "api:p4 walks along the walking lane")
	_check(walker.global_position.y > resting.global_position.y, "in front of the pantry's people")
	_eq(_entity_of(sorted, walker), walker, "sorted by their own feet")
	_done(office)


## A freshly launched agent's state began while we watched: its start is known
## and late, so it ranks after everyone already resting. Going idle while the
## pantry is full (and so while every spot, its own hashed one included, is
## someone's), it sits at its desk: nobody in the pantry moves. The residents
## were there from the first snapshot, their starts unknown, and api:p1 is
## projected before them, which is the order that decided it before.
func test_a_launched_agent_never_takes_a_pantry_spot() -> void:
	var start := _with(_with(fixture, "api:p1", {"agent": null}), "api:p2", {"agent_status": "idle"})
	start = _with(start, "api:p4", {"agent_status": "idle"})
	var office := await _live_office(start)
	office.settle()
	var spots := office.layout_plan().pantry.spots
	_eq(spots.size(), 2, "a pantry of two")
	var residents: Dictionary[String, Vector2] = {}
	for pane_id: String in ["api:p2", "api:p4"]:
		var station := _station(office, _pane(pane_id))
		_eq(station.rest, OfficeRests.Rest.PANTRY, pane_id + " rests in the pantry")
		residents[pane_id] = station.position + station.rest_position()
	var own := posmod(_pane("api:p1").hash(), spots.size())
	_check(residents.values().has(spots[own]), "api:p1's own spot (%d) is a resident's" % own)
	var launching := _with(_with(start, "api:p1", {"agent": "claude"}), "api:p1", {"launch_pending": true})
	_feed(office, launching)
	office.settle()
	var launched := _with(
		_with(start, "api:p1", {"agent": "claude", "agent_status": "idle"}), "api:p1", {"launch_pending": false}
	)
	_feed(office, launched)
	_check(
		office.fleet.state_since(LOCAL, "api:p1") > 0.0,
		"the launched agent's idle began while we watched: a known start"
	)
	for pane_id in residents:
		var station := _station(office, _pane(pane_id))
		_eq(station.position + station.rest_position(), residents[pane_id], pane_id + " keeps its spot")
		_check(not office.floor_view.presentation.is_walking(_pane(pane_id)), pane_id + " does not move")
	var newcomer := _station(office, _pane("api:p1"))
	_eq(newcomer.rest, OfficeRests.Rest.SEAT, "the newcomer finds the pantry full and sits")
	office.settle()
	_eq(newcomer.actor().track, &"desk_idle", "idle at the desk")
	_done(office)


## A floor drawn afresh (another floor and back) puts everyone where they rest
## at once, walking nobody: the idle back in the pantry with a cup, the blocked
## at the desk with a hand up.
func test_a_floor_switch_places_everyone() -> void:
	var office := await _live_office()
	var snapshot := _with(fixture, "api:p2", {"agent_status": "idle"})
	_feed(office, snapshot)
	snapshot = _with(snapshot, "api:p1", {"agent_status": "blocked"})
	_feed(office, snapshot)
	_check(not _walkers(office).is_empty(), "api:p2 is still walking to the pantry when we leave")
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "web"))
	await _visit_floor(office, HerdrFleet.pane_key(LOCAL, "api"))
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "back: nobody walks")
	var resting := _station(office, _pane("api:p2"))
	_eq(_floor_point(office, resting.actor()), resting.position + resting.rest_position(), "p2 on its spot")
	_eq(resting.actor().track, &"drink", "with a cup")
	var blocked := _station(office, _pane("api:p1"))
	_eq(_floor_point(office, blocked.actor()), _seat_of(office, "api:p1"), "p1 in its chair")
	_eq(blocked.actor().track, &"desk_blocked", "hand up")
	_done(office)


## The first update that can be laid out after one that could not is cold:
## whoever went idle meanwhile is placed in the pantry, not walked there.
func test_a_pass_after_a_layout_problem_places_the_pantry() -> void:
	var office := await _live_office()
	var idle := _with(_with(fixture, "api:p1", {"agent_status": "idle"}), "api:p2", {"agent_status": "idle"})
	var twice := idle.duplicate(true)
	var repeated: Dictionary = _list(twice, "panes")[1]
	_list(twice, "panes").append(repeated.duplicate(true))
	_feed(office, twice)
	_check(not office.layout_problems().is_empty(), "the repeated pane cannot be laid out")
	_feed(office, idle)
	_check(office.layout_problems().is_empty(), "the corrected input can")
	_eq([_ids(_walkers(office)), _ids(_ghosts(office))], [[], []], "and walks nobody")
	var spots := office.layout_plan().pantry.spots
	var stood: Array = []
	for pane_id: String in ["api:p1", "api:p2"]:
		var station := _station(office, _pane(pane_id))
		_eq(station.rest, OfficeRests.Rest.PANTRY, pane_id + " rests in the pantry")
		stood.append(_floor_point(office, station.actor()))
	stood.sort()
	var wanted: Array = [spots[0], spots[1]]
	wanted.sort()
	_eq(stood, wanted, "both placed on the pantry's two spots")
	_done(office)


## A selected worker resting in the pantry, too far above their table for both
## to fit the view: the table reveal shows the worker, not the table.
func test_revealing_a_pantry_worker_shows_them() -> void:
	var office := await _wide_office(_with(fixture, "api:p4", {"agent_status": "idle"}))
	office.test_screen = Vector2(SCREEN)
	office.refresh()
	office.settle()
	await _frames(2)
	var station := _station(office, _pane("api:p4"))
	_eq(station.rest, OfficeRests.Rest.PANTRY, "api:p4 rests in the pantry")
	var room := office.camera.free_rect().size
	var table := station.table.geometry.render_rect
	table.position += station.table.global_position
	var both := station.target_rect().merge(table)
	_check(
		both.size.x > room.x or both.size.y + OfficeCamera.REVEAL_HEADROOM > room.y,
		"worker and table do not fit the view together: %s in %s" % [both.size, room]
	)
	office.camera.pan = Vector2.ZERO
	office.reveal(_pane("api:p4"), true)
	await _frames(2)
	var visible := Rect2(office.camera.pan, room)
	var target := station.target_rect()
	var shown := Rect2(office.world.to_local(target.position), target.size)
	_check(visible.encloses(shown), "the pantry worker is in view: %s in %s" % [shown, visible])
	_done(office)


## Local and a second machine, `bee`, on a socket nobody answers: both clients
## stopped, fed by hand.
func _two_machine_office() -> OfficeDouble:
	var office := OfficeDouble.new()
	_live_offices.append(office)
	# The suite's floors are planned 488 wide (PLAN_SCREEN, walking_test_base.gd).
	office.test_screen = PLAN_SCREEN
	office.test_args = AppArgs.parse(
		PackedStringArray(
			[
				"--read-only",
				"--socket=" + args.socket,
				"--machine-socket=bee=" + args.work.path_join("bee-nowhere.sock")
			]
		)
	)
	office.manifest_path = MANIFESTS[0]
	office.remember_theme = false
	root.add_child(office)
	_local(office).stop()
	office.fleet._roster.stop()
	_feed(office, fixture)
	_feed_bee(office, _bee_snapshot("blocked"))
	await _frames(2)
	return office


func _bee(office: OfficeDouble) -> HerdrClient:
	return office.fleet._sites[1].client


## Feed `bee` a fresh snapshot, live.
func _feed_bee(office: OfficeDouble, snapshot: Dictionary) -> void:
	var client := _bee(office)
	client.stop()
	client.online = true
	client._apply_snapshot(snapshot.duplicate(true))
	office.fleet.liveness_changed.emit()


## bee's one floor, `hive`, with one agent in `status`.
static func _bee_snapshot(status: String) -> Dictionary:
	return {
		"focused_pane_id": "hive:p1",
		"workspaces": [{"workspace_id": "hive", "number": 1, "label": "hive"}],
		"tabs": [{"tab_id": "hive:t1", "workspace_id": "hive", "number": 1, "label": "hive"}],
		"panes":
		[
			{
				"pane_id": "hive:p1",
				"workspace_id": "hive",
				"tab_id": "hive:t1",
				"agent": "claude",
				"agent_status": status,
				"terminal_id": "term-hive-p1"
			}
		],
		"agents": [],
		"layouts": []
	}


## The pane key of every seat whose stack of paper shows, in seat order.
func _shown_papers(office: OfficeDouble) -> Array:
	var shown: Array = []
	for station in _seats(office):
		if station.table.papers(station.column, station.side).visible:
			shown.append(station.pane_key)
	return shown


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
	var row := office.frame.find_floor(api).floor_model
	_eq(row.done, 1, "one UNREAD on the minimap's row")
	_eq(_shown_papers(office).size(), row.done, "and one stack of paper")
	var malformed := _with(done, "api:p2", {"agent_status": "done"})
	var repeated: Dictionary = _list(malformed, "panes")[1]
	_list(malformed, "panes").append(repeated.duplicate(true))
	_feed(office, malformed)
	_check(not office.layout_problems().is_empty(), "the repeated pane cannot be laid out")
	row = office.frame.find_floor(api).floor_model
	_eq(row.done, 1, "the minimap's row counts the repeated pane not at all")
	_eq(_shown_papers(office), [_pane("api:p1")], "the floor keeps its last valid paper")
	_done(office)


## Blocked comes first: a shell whose start asks at once. herdr launches claude
## in api:p1 and it blocks before the launch is over: the desk drawn in place
## is the one a rebuild draws (hand up, bubble, pulsing blocked badge), the
## plate says the kind, and the bubble says how long it has waited, from the
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
	_eq(station.rest, OfficeRests.Rest.SEAT, "at its seat")
	_check(station.bubble().visible, "with the bubble over its head")
	_eq(station.actor().track, &"desk_blocked", "and its hand up")
	_eq(_plate(station).text, "CLAUDE", "the plate says the kind")
	await _text_tick()
	_check(
		not _wait_text(office, _pane("api:p1")).is_empty(),
		"the bubble says how long: " + _wait_text(office, _pane("api:p1"))
	)
	# herdr finishing the launch while it still asks is no change at the desk: it
	# is not seated again, which would blank the bubble's wait until the next beat.
	_feed(office, asking)
	_check(not office.frame.pane(_pane("api:p1")).starting, "the launch is over")
	_check(not _wait_text(office, _pane("api:p1")).is_empty(), "the bubble keeps its wait: the desk is not redrawn")
	await _same_as_rebuild(office, "with a start that asks at once")
	_done(office)
