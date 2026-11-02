extends "res://tools/workstation_test_base.gd"
## Whole-image workstations on the real office: state clips, immediate
## arrival/removal, retained identity, stale pictures, chips, real input and
## rebuild equivalence. No walking, ghost, rig or separate desk-item API.

var whole: Dictionary = {}


func _marker() -> String:
	return "RESTS TESTS"


func _run() -> void:
	whole = fixture
	fixture = _only(fixture, "api")
	await super()


func test_a_blocked_agent_keeps_its_workstation_and_shows_its_chip() -> void:
	var office := await _live_office()
	var station := _station(office, _pane("api:p2"))
	var actor := station.actor()
	OS.delay_msec(5)
	_feed(office, _with(fixture, "api:p2", {"agent_status": "blocked"}))
	_eq(station.actor(), actor, "blocking retains the whole workstation")
	_eq(
		[actor.position, actor.animation, actor.track], [Vector2.ZERO, &"blocked", &"blocked_enter"], "starts reclining"
	)
	_finish_workstation_clips(office)
	_eq(actor.track, &"blocked", "then holds the blocked loop")
	_eq(_plate(station).text, "main", "the plate names the pane")
	_check(OfficeFloorView.few_seats(office.frame.building_of(LOCAL).map), "api alone: few seats")
	_check(_plate(station).visible, "the plate shows at rest")
	var bubble := station.chip()
	_check(bubble.visible, "the chip shows immediately")
	_eq(bubble.position, Vector2(-15, 12), "below the complete image, on either row")
	_check(station.get_node_or_null("Overlay/Wait") == null, "no separate wait outside the lens")
	_check(not _label(station, "Overlay/Lens").visible, "no lens without L")
	_check(bubble.get_node_or_null("%Question") == null, "the question belongs to the tooltip")
	await _text_tick()
	_check(not _wait_text(office, station.pane_key).is_empty(), "the observed wait is in the chip")
	var start := _with(fixture, "api:p1", {"agent": null})
	_feed(office, start)
	_feed(office, _with(start, "api:p1", {"agent": "claude", "launch_pending": true}))
	var launching := _station(office, _pane("api:p1"))
	_check(not launching.chip().visible, "starting alone is not blocked")
	var asking := _with(start, "api:p1", {"agent": "claude", "agent_status": "blocked", "launch_pending": true})
	_feed(office, asking)
	_check(office.frame.pane(_pane("api:p1")).starting, "herdr still launches it")
	_check(launching.chip().visible, "blocked beats starting")
	_eq(launching.actor().animation, &"blocked", "the real blocked state, never a starting substitute")
	var badge := _badge(launching)
	_eq(badge.state, ArtContract.STATE_BLOCKED, "the blocked badge")
	_check(badge.is_in_group(StatusBadge.GROUP), "with the pulse group")
	var hourglass := office.art.sprite_texture(office.art.ui_sprite(ArtContract.UI_STARTING))
	_check(badge.texture != hourglass, "not the hourglass")
	_feed(office, _with(asking, "api:p1", {"launch_pending": false}))
	_eq(launching.actor().position, Vector2.ZERO, "finishing launch never relocates it")
	_check(launching.chip().visible, "the chip stays")
	await _same_as_rebuild(office, "blocked at the workstation")
	_done(office)


func test_every_blocked_agent_has_its_own_workstation_and_chip() -> void:
	var crowd := _crowded(12)
	var office := await _live_office(crowd)
	for pane: Dictionary in _list(crowd, "panes"):
		pane.agent_status = "blocked"
	_feed(office, crowd)
	_finish_workstation_clips(office)
	for index in 12:
		var station := _station(office, _pane("crowd:p%02d" % index))
		_eq([station.actor().position, station.actor().track], [Vector2.ZERO, &"blocked"], "blocked in place")
		_check(station.chip().visible, "each has its own chip")
	_eq(_shown_state(office, &"blocked").size(), 12, "all twelve, no display cap")
	_eq(office.floor_view.sorted.get_node_or_null("Fixture_reception"), null, "no reception counter")
	for node: Node in office.world.find_children("*", "Label", true, false):
		_check(not (node as Label).text.begins_with("+"), "no overflow queue")
	_done(office)


func test_a_done_agent_plays_one_completion_and_keeps_its_last_frame() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p1", {"agent_status": "done"}))
	var station := _station(office, _pane("api:p1"))
	var actor := station.actor()
	_eq([actor.position, actor.animation, actor.track], [Vector2.ZERO, &"done", &"done"], "one completion clip")
	_check(actor.is_playing(), "it starts playing")
	_finish_workstation_clips(office)
	_check(not actor.is_playing(), "completion is a one-shot")
	var last := _actor_state(actor)
	office.refresh()
	_eq(_actor_state(actor), last, "refresh does not replay completion")
	_check(not actor.is_playing(), "it remains completed after refresh")
	_set_online(office, false)
	_set_online(office, true)
	_eq(_actor_state(actor), last, "nor does a reconnect replay a completed clip")
	_check(not actor.is_playing(), "recovery does not resume a finished one-shot")
	_check(not station.chip().visible, "done is not a question")
	_feed(office, fixture)
	_eq(actor.animation, &"working", "back at work")
	_feed(office, _with(fixture, "api:p1", {"agent_status": "done", "launch_pending": true}))
	_eq(actor.animation, &"starting", "starting does not fake a completion")
	_feed(office, _with(fixture, "api:p1", {"agent": null, "agent_status": "done"}))
	_eq(station.actor(), null, "a shell has no agent completion")
	_done(office)


func test_a_click_on_a_bubble_picks_its_pane() -> void:
	var snapshot := _with(fixture, "api:p3", {"agent": "codex"})
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		snapshot = _with(snapshot, pane_id, {"agent_status": "blocked"})
	var office := await _live_office(snapshot)
	var sides: Dictionary[String, OfficeStation] = {}
	for pane_id: String in ["api:p1", "api:p2", "api:p3"]:
		var station := _station(office, _pane(pane_id))
		if not sides.has(station.side):
			sides[station.side] = station
	_eq(sides.size(), 2, "blocked agents on both rows")
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
		_eq(office.picked_key, other, side + ": another desk picked first")
		heard.clear()
		office.reveal(station.pane_key)
		await _frames(2)
		await _click(station.chip_rect().get_center() - office.camera.position)
		_eq(heard, ["asked " + station.pane_key], side + ": the public chip rectangle answered")
		_eq(office.picked_key, station.pane_key, side + ": chip picks its pane")
		_check(not office.hud.inspector.answering(), "read-only cannot enter answer mode")
		await _click_desk(office, other)
		heard.clear()
		await _click_desk(office, station.pane_key)
		_eq(heard, ["picked " + station.pane_key], side + ": image target only picks")
		station.asked.disconnect(on_ask)
		station.picked.disconnect(on_pick)
	_done(office)


func test_a_bubble_follows_its_agent_and_its_machine() -> void:
	var office := await _live_office()
	var blocked := _with(fixture, "api:p2", {"agent_status": "blocked"})
	_feed(office, blocked)
	var station := _station(office, _pane("api:p2"))
	var target: CollisionShape2D = station.get_node("Target/Chip")
	_check(station.chip().visible and not target.disabled, "blocked: chip shows and answers")
	_feed(office, fixture)
	_check(not station.chip().visible and not target.disabled, "working: the chip goes, the badge stays pickable")
	_check(_badge(station).visible, "the shared target belongs to the visible working badge")
	_eq(station.chip_rect(), Rect2(), "no question chip to reveal")
	OS.delay_msec(5)
	_feed(office, blocked)
	await _text_tick()
	var frame: NinePatchRect = station.chip().get_node("%Frame")
	var badge := _badge(station)
	_check(station.chip().visible and not target.disabled, "blocked again: back")
	_check(not _wait_text(office, station.pane_key).is_empty() and frame.visible, "live: wait in a frame")
	_eq(badge.position, Vector2(0, 28) + OfficeStation.CHIP_BADGE_SHIFT, "badge in the chip's left half")
	_set_online(office, false)
	await _text_tick()
	_check(station.chip().is_visible_in_tree(), "dropped: chip stays")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "with the stale tint")
	_eq(_wait_text(office, station.pane_key), "", "no growing wait on an outage")
	_check(not frame.visible, "no empty frame")
	_eq(badge.position, Vector2(0, 28), "badge centred again")
	_check(not target.disabled, "the chip target still answers")
	_done(office)


func test_chips_and_state_images_match_a_rebuild() -> void:
	var office := await _live_office()
	OS.delay_msec(5)
	var snapshot := _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p4", {"agent_status": "done"})
	_feed(office, snapshot)
	await _text_tick()
	await _same_as_rebuild(office, "blocked and done")
	_feed(office, _with(snapshot, "api:p2", {"agent_status": "blocked"}))
	await _same_as_rebuild(office, "a second chip")
	_feed(office, fixture)
	await _same_as_rebuild(office, "back at work")
	_done(office)


## The old whole-pod/24-tiny-seat density promise is retired. The selected
## complete workstation and its chip, not a cropped person, must fit.
func test_the_first_framing_shows_the_whole_workstation_and_chip() -> void:
	for pane_id: String in ["api:p2", "api:p3"]:
		var snapshot := _with(fixture, pane_id, {"agent": "codex", "agent_status": "blocked"})
		var office := await _live_office(_focused_on(snapshot, pane_id))
		await _frames(2)
		_check_revealed(office, _station(office, _pane(pane_id)))
		_done(office)


func test_the_question_excerpt_is_the_asking_line() -> void:
	var framed := "╭────────────╮\n│ Edit file src/a.rs │\n│ Do you want to proceed? │\n│ ❯ 1. Yes │\n│ 2. No │\n╰────────────╯\n"
	_eq(OfficeQuestionReader.excerpt(framed), "Do you want to proceed?", "last asking line, unframed")
	_eq(OfficeQuestionReader.excerpt("Is it?\nReally?\n  \n"), "Really?", "last of several")
	_eq(OfficeQuestionReader.excerpt("building\n▌ step 2 of 3 ▐\n\n"), "step 2 of 3", "no question: last nonblank")
	_eq(OfficeQuestionReader.excerpt("── ──\n\n   \n"), "", "only frames and blanks")
	_eq(OfficeQuestionReader.excerpt(""), "", "no text")
	_eq(OfficeQuestionReader.excerpt("x".repeat(300) + "?").length(), OfficeQuestionReader.EXCERPT_MAX, "bounded")
	_eq(OfficeQuestionReader.excerpt("a\r\nwhy?\r\n"), "why?", "carriage returns are blanks")


func test_the_chip_says_the_wait_and_takes_the_badge() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "blocked"}))
	var station := _station(office, _pane("api:p2"))
	var bubble := station.chip()
	var frame: NinePatchRect = bubble.get_node("%Frame")
	var wait: Label = bubble.get_node("%Wait")
	var badge := _badge(station)
	var middle := Vector2(0, 28)
	var forms := {0.0: "0s", 60.0: "1m", 300.0: "5m", 5999.0: "99m", 7200.0: "2h", 400000.0: "4d"}
	for seconds: float in forms:
		bubble.show_wait(seconds)
		_eq(wait.text, forms[seconds], "%d s: compact wait" % seconds)
		_check(frame.visible and wait.visible, "in its frame")
		_eq(badge.position, middle + OfficeStation.CHIP_BADGE_SHIFT, "badge in the chip")
	_check(bubble.get_node_or_null("%Track") == null and bubble.get_node_or_null("%Fill") == null, "no bar")
	bubble.show_wait(-1.0)
	_check(not frame.visible and not wait.visible, "no known wait: no frame")
	_eq(wait.text, "", "no number")
	_eq(badge.position, middle, "badge in the middle of its row")
	_done(office)


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
	_eq(wait.get_theme_font_size("font_size"), OfficeChip.WAIT_PIXELS, "native figures size")
	_eq(wait.get_theme_font("font"), office.pen.figures, "figures face")
	var font := wait.get_theme_font("font")
	for text: String in ["59s", "99m", "99h", "99d"]:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, OfficeChip.WAIT_PIXELS).x
		_check(width <= wait.size.x, "%s fits the label" % text)
	_done(office)


func test_hovering_a_bubble_shows_a_tooltip() -> void:
	var office := await _live_office(_with(whole, "api:p2", {"agent_status": "blocked"}))
	var key := _pane("api:p2")
	var station := _station(office, key)
	office.reveal(key)
	await _text_tick()
	_eq(_wait_text(office, key), "", "first snapshot: start not observed")
	_check(station.chip().visible, "chip still exists")
	_check(not (station.chip().get_node("%Frame") as CanvasItem).visible, "without an empty frame")
	_eq(station.actor().animation, &"blocked", "real blocked state")
	var badge := _badge(station)
	_check(badge.visible, "badge shows")
	var over := station.chip_rect().intersection(badge.global_transform * badge.get_rect())
	_check(over.has_area(), "the badge is inside the chip target")
	await _pointer_to(Vector2(2, 2))
	_check(not office.hud.world_tip_shown(), "no tooltip before entering")
	await _pointer_to(over.get_center() - office.camera.position)
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "badge hover shows question tooltip")
	var at := station.chip_rect().get_center() - office.camera.position
	var seat_at := station.target_rect().get_center() - office.camera.position
	await _pointer_to(seat_at)
	_eq(
		office.hud.world_tip_text(),
		"main\nCODEX · NEEDS INPUT\napi / main",
		"the image's own tooltip, not the question"
	)
	await _pointer_to(at)
	_eq(office.hud.world_tip_text(), OfficeQuestionReader.READ_ONLY_TEXT, "back to the question")
	var tip: Control = office.hud.get_node("%WorldTip")
	_check(office.hud.world_rect().encloses(tip.get_global_rect()), "tooltip inside the world's room")
	await _parsed(_mouse_button(seat_at, MOUSE_BUTTON_LEFT, true))
	var drag := InputEventMouseMotion.new()
	drag.position = at
	drag.global_position = at
	drag.relative = at - seat_at
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	await _parsed(drag)
	_check(not office.hud.world_tip_shown(), "no tooltip during a drag")
	await _parsed(_mouse_button(at, MOUSE_BUTTON_LEFT, false))
	office.reveal(key)
	await _frames(2)
	await _pointer_to(Vector2(2, 2))
	await _pointer_to(station.chip_rect().get_center() - office.camera.position)
	_check(office.hud.world_tip_shown(), "tooltip returns")
	await _office_key(office, KEY_PAGEDOWN)
	await _physics_frames(2)
	_eq(office.navigator.current_zone(office.frame), _pane("web"), "PageDown pans to web")
	_check(not office.hud.world_tip_shown(), "the old chip moved out from under the pointer")
	_done(office)


func test_an_idle_agent_plays_idle_at_its_seat() -> void:
	var office := await _live_office()
	_feed(office, _with(fixture, "api:p2", {"agent_status": "idle"}))
	var station := _station(office, _pane("api:p2"))
	_eq([station.actor().position, station.actor().track], [Vector2.ZERO, &"idle"], "idle in place")
	_eq(_shown_state(office, &"idle"), [_pane("api:p2")], "only this pane is idle")
	_check(not station.chip().visible, "no question chip")
	_eq(_plate(station).text, "main", "the pane's name")
	await _same_as_rebuild(office, "idle at the workstation")
	_done(office)


func test_every_idle_agent_has_its_own_workstation() -> void:
	var snapshot := _with(_with_residents(fixture), "api:p3", {"agent": "codex"})
	var office := await _live_office(snapshot)
	var panes: Array[String] = ["api:r0", "api:r1", "api:r2", "api:p1", "api:p2", "api:p3", "api:p4"]
	for pane_id in panes:
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
	_feed(office, snapshot)
	for pane_id in panes:
		var station := _station(office, _pane(pane_id))
		_eq([station.actor().position, station.actor().track], [Vector2.ZERO, &"idle"], pane_id + ": idle at its seat")
	_eq(_shown_state(office, &"idle").size(), 7, "seven idle images, no pantry capacity limit")
	await _same_as_rebuild(office, "seven idle workstations")
	_done(office)


func test_state_changes_keep_the_image_and_use_the_latest_requested_state() -> void:
	var start := _with(fixture, "api:p3", {"agent": "codex"})
	var office := await _live_office(start)
	for pane_id: String in ["api:p2", "api:p3"]:
		var station := _station(office, _pane(pane_id))
		var actor := station.actor()
		var nodes := _subtree_ids(station)
		var snapshot := start
		for state: String in ["idle", "blocked", "done", "idle", "working"]:
			snapshot = _with(snapshot, pane_id, {"agent_status": state})
			_feed(office, snapshot)
			_eq(station.actor(), actor, state + ": same image actor")
			_eq(actor.position, Vector2.ZERO, "anchored to the seat")
			_eq(actor.animation, StringName(state), "the latest real state is recorded immediately")
			_eq(station.chip().visible, state == "blocked", "chip follows real state, not transitional clip")
			_eq(_subtree_ids(station), nodes, "state changes replace no node")
		_finish_workstation_clips(office)
		_eq(actor.track, &"working", "blocked exit resolves to the latest request, not the earlier done or idle")
	_done(office)


func test_an_idle_panes_closed_tab_removes_its_workstation_immediately() -> void:
	var snapshot := _with(fixture, "api:p4", {"agent_status": "idle"})
	var office := await _live_office(snapshot)
	var station := _station(office, _pane("api:p4"))
	var actor := station.actor()
	var table := station.table
	var closed := _without(snapshot, "api:p4")
	closed.tabs = _list(closed, "tabs").filter(func(each: Dictionary) -> bool: return each.tab_id != "api:t2")
	_feed(office, closed)
	_check(not office.floor_view.seats.has(_pane("api:p4")), "pane gone immediately")
	_check(not is_instance_valid(table) or not table.is_inside_tree(), "last pane's table gone immediately")
	_check(not is_instance_valid(actor) or not actor.is_inside_tree(), "no departing image left on the floor")
	await _same_as_rebuild(office, "after a tab closes")
	_done(office)


func test_another_provider_updates_the_permanent_idle_image() -> void:
	var snapshot := _with(fixture, "api:p2", {"agent_status": "idle"})
	var office := await _live_office(snapshot)
	var station := _station(office, _pane("api:p2"))
	var actor := station.actor()
	var image := _sprite(actor, "Body")
	var texture := image.texture
	var nodes := _subtree_ids(station)
	_feed(office, _with(snapshot, "api:p2", {"agent": "claude"}))
	_eq(station.actor(), actor, "provider swap uses the permanent actor")
	_eq(
		[actor.provider, actor.animation, actor.position],
		["claude", &"idle", Vector2.ZERO],
		"new provider, idle in place"
	)
	_eq(image.texture, texture, "the image is generic, not provider-specific")
	_eq(_subtree_ids(station), nodes, "no extra body on provider swap")
	await _same_as_rebuild(office, "provider swap while idle")
	_done(office)


func test_a_new_session_keeps_the_idle_image_and_restarts_the_observed_wait() -> void:
	var snapshot := _with(_with_residents(fixture), "api:p1", {"agent_status": "idle"})
	var office := await _live_office(snapshot)
	var station := _station(office, _pane("api:p1"))
	var actor := station.actor()
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	player.advance(0.17)
	var before := _actor_state(actor)
	OS.delay_msec(5)
	_feed(office, _with(snapshot, "api:p1", {"terminal_id": "term-api-p1-again"}))
	_eq(station.actor(), actor, "same actor on a new terminal")
	_eq(_actor_state(actor), before, "same clip clock, not restarted")
	_eq([actor.position, actor.track], [Vector2.ZERO, &"idle"], "idle at the same seat")
	_check(office.fleet.state_since(LOCAL, "api:p1") > 0.0, "the newly observed session has a known idle start")
	_done(office)


func test_a_cold_pass_places_every_workstation_in_its_real_state() -> void:
	var snapshot := _with(_with(fixture, "api:p1", {"agent_status": "blocked"}), "api:p2", {"agent_status": "idle"})
	snapshot = _with(snapshot, "api:p4", {"agent_status": "done"})
	var office := await _live_office(snapshot)
	var check := func(when: String) -> void:
		_check_invariants(office, when, false)
		_eq(_station(office, _pane("api:p1")).actor().animation, &"blocked", when + ": blocked")
		_check(_station(office, _pane("api:p1")).chip().visible, when + ": chip")
		_eq(_station(office, _pane("api:p2")).actor().animation, &"idle", when + ": idle")
		_eq(_station(office, _pane("api:p4")).actor().animation, &"done", when + ": done")
	check.call("first draw")
	office.switch_theme(_second_pack())
	check.call("theme rebuild")
	_set_online(office, false)
	_set_online(office, true)
	check.call("reconnected")
	_done(office)


func test_a_stale_floor_keeps_its_real_states_across_input_and_other_machines() -> void:
	var snapshot := _with_residents(fixture)
	var office := await _two_machine_office(snapshot, PLAN_SCREEN)
	for pane_id: String in ["api:p4", "api:p2"]:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "idle"})
		_feed(office, snapshot)
	snapshot = _with(snapshot, "api:p1", {"agent_status": "done"})
	_feed(office, snapshot)
	_finish_workstation_clips(office)
	var idle := _shown_state(office, &"idle")
	var completed := _shown_state(office, &"done")
	var standing := [idle, completed]
	_eq([idle.size(), completed.size()], [5, 1], "five idle and one done")
	_set_online(office, false)
	_check(not office.stale, "the other machine is live")
	_eq(office.floor_view.root.modulate, office.art.stale_tint, "Local dims")
	var frozen := _actor_progress(office, "")
	await _click_desk(office, _pane("api:p4"))
	_eq(_actor_progress(office, ""), frozen, "real input never unfreezes a frame")
	await _office_key(office, KEY_N)
	_eq(office.picked_key, HerdrFleet.pane_key(BEE, "hive:p1"), "N visits live blocked, not stale done")
	await _visit_zone(office, _pane("api"))
	_eq(office.navigator.shown_key, LOCAL, "back to Local")
	_eq([_shown_state(office, &"idle"), _shown_state(office, &"done")], standing, "same real states on return")
	_check_invariants(office, "stale redraw", true)
	_feed_bee(office, _bee_snapshot("working"))
	_eq([_shown_state(office, &"idle"), _shown_state(office, &"done")], standing, "other machine cannot change Local")
	_set_online(office, true)
	await _same_as_rebuild(office, "after stale map and other-machine navigation")
	_done(office)


func test_clicks_pick_idle_workstations_and_the_counter_picks_nothing() -> void:
	var office := await _live_office(_with(fixture, "api:p2", {"agent_status": "idle"}))
	var other := _pane("api:p4")
	await _click_desk(office, other)
	await _click_desk(office, _pane("api:p2"))
	_eq(office.picked_key, _pane("api:p2"), "public image target picks the idle pane")
	await _click_desk(office, other)
	var counter: Node2D = office.floor_view.sorted.get_node("Fixture_pantry")
	office.camera.reveal(Rect2(office.world.to_local(counter.global_position - Vector2(40, 60)), Vector2(80, 80)))
	await _frames(2)
	await _click(counter.global_position + Vector2(0, -12) - office.camera.position)
	_eq(office.picked_key, other, "pantry furniture selects nothing")
	_done(office)


func test_the_nook_counter_sorts_by_its_feet() -> void:
	var office := await _live_office()
	var sorted := office.floor_view.sorted
	var pantry: Node2D = sorted.get_node("Fixture_pantry")
	_eq(_entity_of(sorted, pantry), pantry, "counter sorts as itself")
	_eq(sorted.to_local(pantry.global_position).y, 78.0, "its planned foot")
	var station := _station(office, _pane("api:p1"))
	_eq(_entity_of(sorted, station.actor()), station, "whole workstation sorts at its station's foot")
	_check(station.actor().global_position.y > pantry.global_position.y, "workstation stands in front of the counter")
	_done(office)


func test_a_launch_holds_frame_zero_until_its_idle_state_is_current() -> void:
	var start := _with(fixture, "api:p1", {"agent": null})
	var office := await _live_office(start)
	var launching := _with(start, "api:p1", {"agent": "claude", "agent_status": "idle", "launch_pending": true})
	_feed(office, launching)
	var station := _station(office, _pane("api:p1"))
	_eq(station.actor().animation, &"starting", "not yet idle")
	_eq(_sprite(station.actor(), "Body").frame, 0, "starting still frame")
	_check(not station.chip().visible, "no invented question")
	_feed(office, _with(launching, "api:p1", {"launch_pending": false}))
	_check(office.fleet.state_since(LOCAL, "api:p1") > 0.0, "idle begins when observed")
	_eq([station.actor().position, station.actor().track], [Vector2.ZERO, &"idle"], "idle immediately at its seat")
	_done(office)


func test_a_floor_switch_places_every_workstation() -> void:
	var office := await _two_machine_office(fixture, PLAN_SCREEN)
	var snapshot := _with(fixture, "api:p2", {"agent_status": "idle"})
	snapshot = _with(_with(snapshot, "api:p1", {"agent_status": "blocked"}), "api:p3", {"agent": "codex"})
	_feed(office, snapshot)
	await _visit_zone(office, HerdrFleet.pane_key(BEE, "hive"))
	_eq(office.navigator.shown_key, BEE, "another machine")
	await _visit_zone(office, _pane("api"))
	_eq(office.navigator.shown_key, LOCAL, "and back")
	_check_invariants(office, "map return", false)
	_eq(_station(office, _pane("api:p2")).actor().animation, &"idle", "idle survives")
	_eq(_station(office, _pane("api:p1")).actor().animation, &"blocked", "blocked survives")
	_eq(_station(office, _pane("api:p3")).actor().provider, "codex", "the arrival survives")
	_done(office)


func test_invalid_layout_keeps_old_data_until_valid_recovery() -> void:
	var office := await _live_office()
	var idle := _with(_with(fixture, "api:p1", {"agent_status": "idle"}), "api:p2", {"agent_status": "idle"})
	idle = _with(idle, "api:p3", {"agent": "codex"})
	var twice := idle.duplicate(true)
	var repeated: Dictionary = _list(twice, "panes")[1]
	_list(twice, "panes").append(repeated.duplicate(true))
	var geometry := office.layout_plan()
	_feed(office, twice)
	_check(not office.layout_problems().is_empty(), "duplicate cannot be laid out")
	_eq(office.layout_plan(), geometry, "previous geometry kept")
	_eq(_station(office, _pane("api:p1")).actor().animation, &"working", "invalid state never leaks")
	_eq(_station(office, _pane("api:p3")).actor(), null, "invalid arrival never leaks")
	_feed(office, idle)
	_check(office.layout_problems().is_empty(), "corrected input is valid")
	_eq(_shown_state(office, &"idle"), [_pane("api:p1"), _pane("api:p2")], "both states applied together")
	_check_invariants(office, "valid recovery", false)
	await _same_as_rebuild(office, "after invalid-layout recovery")
	_done(office)


func test_revealing_an_idle_workstation_frames_the_whole_image() -> void:
	var office := await _live_office(_with(fixture, "api:p4", {"agent_status": "idle"}), Vector2(1600, 480))
	office.test_screen = Vector2(SCREEN)
	office.refresh()
	office.camera.pan = Vector2.ZERO
	office.reveal(_pane("api:p4"), true)
	await _frames(2)
	_check_revealed(office, _station(office, _pane("api:p4")))
	_done(office)


func test_idle_agents_of_every_zone_keep_their_seats_and_n_follows_wait_order() -> void:
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
	_eq(_shown_state(office, &"idle").size(), 6, "six idle images across four zones")
	_check_invariants(office, "all idle", false)
	var finished: Array[String] = ["data:p1", "api:p2", "web:p1", "infra:p1", "web:p2", "api:p1"]
	for pane_id in finished:
		OS.delay_msec(5)
		snapshot = _with(snapshot, pane_id, {"agent_status": "done"})
		_feed(office, snapshot)
	_eq(_shown_state(office, &"idle"), [], "none still idle")
	_eq(_shown_state(office, &"done").size(), 6, "six done states")
	var visited: Array[String] = []
	for index in finished.size():
		await _office_key(office, KEY_N)
		visited.append(office.picked_key)
	_eq(visited, finished.map(func(pane_id: String) -> String: return _pane(pane_id)), "N visits in wait order")
	_done(office)


func test_done_workstations_and_zone_totals_count_unread_alike() -> void:
	var office := await _live_office()
	var done := _with(fixture, "api:p1", {"agent_status": "done"})
	_feed(office, done)
	var row := office.frame.find_zone(_pane("api")).zone_model
	_eq(row.done, 1, "one UNREAD in the zone")
	_eq(_shown_state(office, &"done").size(), row.done, "and one done image")
	var malformed := _with(done, "api:p2", {"agent_status": "done"})
	var repeated: Dictionary = _list(malformed, "panes")[1]
	_list(malformed, "panes").append(repeated.duplicate(true))
	_feed(office, malformed)
	_check(not office.layout_problems().is_empty(), "duplicate refused")
	_eq(office.frame.find_zone(_pane("api")).zone_model.done, 1, "ambiguous identity not counted")
	_eq(_shown_state(office, &"done"), [_pane("api:p1")], "last valid state image retained")
	_done(office)


func test_a_start_that_asks_at_once_matches_a_rebuild() -> void:
	var start := _with(fixture, "api:p1", {"agent": null})
	var office := await _live_office(start)
	_feed(office, _with(start, "api:p1", {"agent": "claude", "launch_pending": true}))
	var asking := _with(start, "api:p1", {"agent": "claude", "agent_status": "blocked"})
	_feed(office, _with(asking, "api:p1", {"launch_pending": true}))
	_check(office.frame.pane(_pane("api:p1")).starting, "launch still pending")
	var station := _station(office, _pane("api:p1"))
	_eq([station.actor().position, station.actor().animation], [Vector2.ZERO, &"blocked"], "blocked at once")
	_check(station.chip().visible, "with the chip")
	_eq(_plate(station).text, "refactor the fleet", "pane's name")
	await _text_tick()
	_check(not _wait_text(office, station.pane_key).is_empty(), "observed wait shown")
	var clock := _actor_state(station.actor())
	_feed(office, asking)
	_check(not office.frame.pane(station.pane_key).starting, "launch is over")
	_eq(_actor_state(station.actor()), clock, "the blocked clip does not restart")
	_check(not _wait_text(office, station.pane_key).is_empty(), "the chip never blinks out")
	await _same_as_rebuild(office, "a start that asks immediately")
	_done(office)


## Migrated from WALKING: arrival, departure, reversal and arrival clicks.
func test_arrivals_and_removals_are_immediate_and_keep_the_permanent_image() -> void:
	var office := await _live_office()
	var station := _station(office, _pane("api:p3"))
	var permanent: WorkstationActor = station.get_node("Actor")
	var nodes := _subtree_ids(station)
	_eq(station.actor(), null, "a shell has no actor")
	for provider: String in ["codex", "", "claude", ""]:
		_feed(office, _with(fixture, "api:p3", {"agent": null if provider.is_empty() else provider}))
		_eq(_subtree_ids(station), nodes, "arrival and loss replace no node")
		_eq(station.get_node("Actor"), permanent, "same permanent image")
		_eq(_plate(station).text, "main", "the pane's plate is immediate")
		_eq(_badge(station).visible, not provider.is_empty(), "badge follows occupancy immediately")
		if provider.is_empty():
			_eq(station.actor(), null, "no departing actor left over")
			_check(not permanent.is_playing(), "the empty image has no running clip")
			_eq(_sprite(permanent, "Body").texture, office.art.workstation.empty_texture(), "empty image immediately")
		else:
			_eq(station.actor(), permanent, "arrived immediately at its own workstation")
			_eq([permanent.provider, permanent.position], [provider, Vector2.ZERO], "right provider at the seat")
			await _click_desk(office, station.pane_key)
			_eq(office.picked_key, station.pane_key, "arrival is immediately clickable")
	await _same_as_rebuild(office, "after repeated arrivals and removals")
	_done(office)


func test_a_closed_panes_old_target_does_not_pick_and_its_replacement_does() -> void:
	var office := await _live_office()
	await _click_desk(office, _pane("api:p1"))
	var station := _station(office, _pane("api:p2"))
	var target := station.target_rect()
	_feed(office, _without(fixture, "api:p2"))
	_check(not office.floor_view.seats.has(_pane("api:p2")), "the removed key cannot be picked")
	office.camera.reveal(Rect2(office.world.to_local(target.position), target.size))
	await _frames(2)
	await _click(target.get_center() - office.camera.position)
	_eq(office.picked_key, _pane("api:p1"), "clicking its vacant target picks nothing")
	_feed(office, fixture)
	await _click_desk(office, _pane("api:p2"))
	_eq(office.picked_key, _pane("api:p2"), "a later arrival is clickable")
	_done(office)


func test_cross_tab_and_cross_zone_moves_retain_the_station_actor_and_clock() -> void:
	var office := await _live_office(whole)
	var station := _station(office, _pane("api:p4"))
	var actor := station.actor()
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	player.advance(0.17)
	for destination: Array in [["api", "api:t1"], ["web", "web:t1"], ["api", "api:t2"]]:
		var before := _actor_state(actor)
		var at := station.position
		_feed(office, _with(whole, "api:p4", {"workspace_id": destination[0], "tab_id": destination[1]}))
		_eq(_station(office, station.pane_key), station, "the composite pane key owns the station across tabs")
		_eq(station.actor(), actor, "and its actor")
		_eq(_actor_state(actor), before, "moving seats never restarts the clip")
		_check(station.position != at, "the fixture really moved the seat")
		_eq(actor.global_position, station.seat.global_position, "immediately on the new marker")
	await _same_as_rebuild(office, "after cross-tab and cross-zone moves")
	_done(office)


func test_a_new_workspace_adds_immediate_workstations_without_rebuilding() -> void:
	var office := await _live_office(whole)
	var world := office.world.get_instance_id()
	var kept := _desk_ids(office, "")
	var zones := {}
	for zone in office.layout_plan().zones:
		zones[zone.zone_key] = zone.cells
	var grown := whole.duplicate(true)
	_list(grown, "workspaces").append({"workspace_id": "ops", "number": 6, "label": "ops"})
	_list(grown, "tabs").append({"workspace_id": "ops", "tab_id": "ops:t1", "number": 1})
	for index in 2:
		(
			_list(grown, "panes")
			. append(
				{
					"workspace_id": "ops",
					"tab_id": "ops:t1",
					"pane_id": "ops:p%d" % index,
					"terminal_id": "term-ops-%d" % index,
					"agent": "claude",
					"agent_status": "working",
				}
			)
		)
	_feed(office, grown)
	_eq(office.world.get_instance_id(), world, "same world")
	for key: String in zones:
		_eq(office.layout_plan().zone(key).cells, zones[key], "existing zone stays put")
	for key: String in kept:
		_eq(_desk_ids(office, "")[key], kept[key], "existing station nodes retained")
	for index in 2:
		var station := _station(office, _pane("ops:p%d" % index))
		_eq(station.actor().global_position, station.seat.global_position, "arrival at its seat immediately")
	_check_invariants(office, "new zone", false)
	_done(office)


func test_closing_a_crowded_workspace_removes_all_its_images_immediately() -> void:
	# A closure on a populated map leaves its other zones and actors alone.
	var map_office := await _live_office(whole)
	var removed: Array[WorkstationActor] = []
	for pane_id: String in ["api:p1", "api:p2", "api:p4"]:
		removed.append(_station(map_office, _pane(pane_id)).actor())
	var survivor := _station(map_office, _pane("web:p1"))
	var survivor_clock := _actor_state(survivor.actor())
	var map_id := map_office.world.get_instance_id()
	var closed := whole.duplicate(true)
	for field: String in ["workspaces", "tabs", "panes", "agents", "layouts"]:
		closed[field] = _list(closed, field).filter(
			func(each: Dictionary) -> bool: return str(each.get("workspace_id", "")) != "api"
		)
	closed.focused_pane_id = "web:p1"
	_feed(map_office, closed)
	_eq(map_office.world.get_instance_id(), map_id, "closing one zone retains the map")
	_eq(map_office.layout_plan().zone(_pane("api")), null, "the closed zone is gone")
	_eq(_station(map_office, _pane("web:p1")), survivor, "another zone retains its station")
	_eq(_actor_state(survivor.actor()), survivor_clock, "and its exact image clock")
	for actor in removed:
		_check(not is_instance_valid(actor) or not actor.is_inside_tree(), "every removed zone image is gone")
	await _same_as_rebuild(map_office, "one zone closes on a populated map")
	_done(map_office)
	# Sixty simultaneous departures leave no bounded ghost queue behind.
	var crowd := _crowded(60)
	var office := await _live_office(crowd, Vector2(1600, 480))
	var actors: Array[WorkstationActor] = []
	for station in _seats(office):
		actors.append(station.actor())
	_eq(actors.size(), 60, "sixty live images before closure")
	var world := office.world.get_instance_id()
	_feed(office, {})
	_eq(office.world.get_instance_id(), world, "same map, no world rebuild")
	_eq(office.layout_plan().zones.size(), 0, "zone removed")
	_eq(office.floor_view.seats.size(), 0, "all keys removed immediately")
	for actor in actors:
		_check(not is_instance_valid(actor) or not actor.is_inside_tree(), "no deferred departure image")
	await _same_as_rebuild(office, "closed crowd")
	_done(office)


func test_reconnect_requires_a_current_snapshot_and_a_valid_layout_to_unfreeze() -> void:
	var office := await _live_office()
	var station := _station(office, _pane("api:p1"))
	var actor := station.actor()
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	player.advance(0.17)
	_set_online(office, false)
	var frozen := _actor_state(actor)
	var plan := office.layout_plan()
	_local(office).online = true
	office.fleet.liveness_changed.emit()
	office.refresh()
	await _frames(3)
	_check(not actor.is_playing(), "transport alone is not a fresh snapshot")
	_eq(_actor_state(actor), frozen, "same last frame while awaiting the snapshot")
	var invalid := _with(fixture, "api:p1", {"agent": "codex", "agent_status": "idle"})
	var repeated: Dictionary = _list(invalid, "panes")[1]
	_list(invalid, "panes").append(repeated.duplicate(true))
	_feed(office, invalid)
	_check(not office.layout_problems().is_empty(), "fresh but invalid layout")
	_eq(office.layout_plan(), plan, "old geometry retained")
	for index in 6:
		await _frames(1)
		_eq(_actor_state(actor), frozen, "invalid reconnect keeps last clock and frame")
	_eq([actor.provider, actor.animation], ["claude", &"working"], "old data retained too")
	_feed(office, _with(fixture, "api:p1", {"agent": "codex", "agent_status": "idle"}))
	_check(office.layout_problems().is_empty(), "valid snapshot releases the freeze")
	_eq(station.actor(), actor, "permanent actor retained through recovery")
	_eq([actor.provider, actor.animation, actor.track], ["codex", &"idle", &"idle"], "latest valid data applied")
	_check(actor.is_playing(), "playing again")
	await _same_as_rebuild(office, "valid reconnect")
	_done(office)


func test_a_seeded_lifecycle_keeps_workstation_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_value: int in [71, 151, 168, 5, 42]:
		rng.seed = 1000 + seed_value
		var office := await _live_office()
		var frozen := false
		for step in 25:
			var roll := rng.randf()
			var when := "seed %d step %d" % [seed_value, step]
			if roll < 0.12:
				frozen = not frozen
				_set_online(office, not frozen)
			elif roll < 0.16:
				var theme: String = [MANIFESTS[0], _second_pack()][rng.randi() % 2]
				office.switch_theme(theme)
			else:
				var state := _random_state(rng)
				if not frozen:
					_feed(office, _variant(state))
			_check_invariants(office, when, frozen)
			var before := _actor_progress(office, "")
			var ticks := rng.randi() % 40
			await _frames(ticks)
			if frozen:
				_eq(_actor_progress(office, ""), before, when + ": no stale frame or clock moves")
			_check_invariants(office, when + " after frames", frozen)
		if frozen:
			_set_online(office, true)
		await _same_as_rebuild(office, "seed %d" % seed_value)
		_done(office)


func test_the_card_uses_the_same_generic_portrait_for_two_provider_peers() -> void:
	var two := _with(fixture, "api:p2", {"agent": "claude", "agent_status": "working"})
	var office := await _live_office(two)
	var texture: Texture2D = null
	for pane_id: String in ["api:p2", "api:p1"]:
		var key := _pane(pane_id)
		await _click_desk(office, key)
		_eq(office.picked_key, key, "real click selects " + pane_id)
		var pane := office.frame.pane(key)
		_eq(pane.provider, _station(office, key).actor().provider, "selected model keeps its provider identity")
		_eq(_label(office.hud.inspector, "%CardName").text, pane.name, "card names the selected pane")
		var portrait := office.hud.inspector.portrait()
		_check(portrait != null, "card portrait exists")
		if portrait == null:
			continue
		_eq(portrait.texture, office.art.workstation.portrait_texture(), "one whole-image portrait")
		if texture == null:
			texture = portrait.texture
		else:
			_eq(portrait.texture, texture, "generic portrait, no per-pane look variation")
	_done(office)


func _shown_state(office: OfficeDouble, state: StringName) -> Array:
	var shown: Array = []
	for station in _seats(office):
		if station.actor() != null and station.actor().animation == state:
			shown.append(station.pane_key)
	shown.sort()
	return shown


func _check_revealed(office: OfficeDouble, station: OfficeStation) -> void:
	var room := office.hud.world_rect()
	var body := _sprite(station, "Actor/Body")
	var image := body.global_transform * body.get_rect()
	_eq(image, station.global_transform * Rect2(-37.5, -70, 80, 80), "the rendered image uses the native full canvas")
	for box: Rect2 in [image, station.target_rect(), station.chip_rect()]:
		if box.has_area():
			var shown := Rect2(box.position - office.camera.position, box.size)
			_check(room.encloses(shown), "whole selected image/target/chip: %s in %s" % [shown, room])
