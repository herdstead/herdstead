extends "res://tools/office_test_base.gd"
## The top bar's portrait strip (S3 BAR-a): who gets a card and in what order
## (PortraitBarModel.of(): the blocked in `N`'s order, the done oldest first,
## the working and the idle in place order), the fold ladder
## (PortraitBarModel.fit()), and the cards themselves: words within their
## width, a pool that keeps its nodes, the zone tag in its group's carpet
## family, the seat's person standing still, the state's frame and the
## selection's ring, no key reaching a card, and a hover pointing at the desk.
## Hovers, clicks and keys go through real input. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_portrait_bar.gd -- \
##     --read-only --socket=<a socket nobody listens on> --work=<short tmp dir>
##
## No herdr at all: the fleet's Local client is stopped and snapshots are handed
## to it directly, as the incremental suite does.

## The pack's states, as the projection is told them.
const STATES := ["working", "blocked", "done", "idle", "unknown"]
## The widths the ladder's table in the spec is worked out with (A.2): a card,
## a face, a fold, a tally, the gap. A short bar's horizontal cards.
const METRICS := [86.0, 20.0, 40.0, 24.0, 2.0]
## The same on a tall bar, B2's tiles (S3 TILES, T.3b): a tile, a tile's face,
## a fold, a tally, the gap.
const TILE_METRICS := [50.0, 26.0, 40.0, 24.0, 2.0]
## The strip's room at 960, 800 and 640 units on a tall bar with
## `1 machine · 13 panes`, and at 480 on a short untitled one, plain window
## (S3 TILES, 2026-10-28: measured; `%Panes` 95 wide where it was 46).
const ROOMS: Array[float] = [524.0, 364.0, 204.0, 208.0]
## Which of ROOMS are a tall bar's.
const TALL_ROOMS := 3
## How far apart (8-bit RGB, summed) a tile's ring stays from what it lies on
## or beside: more than twice `paper` on `cream`'s 41, the measured miss (S3
## PORTRAIT P3 round 2, 2026-10-28).
const RING_APART := 100


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("portrait-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	fixture = _snapshot_of("res://tools/fixtures/snapshot_floors.json")
	if fixture.is_empty():
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _marker() -> String:
	return "PORTRAIT BAR TESTS"


# --- cases --------------------------------------------------------------------


## snapshot_floors on one machine: the blocked stand in exactly the order `N`
## walks them (OfficeNavigator.waiting()), infra:p1 first, blocked longer; the
## done after them, the oldest UNREAD first; then the working and the idle in
## place order (api's zone, web's, infra's, data's: herdr's numbers). On two
## machines the blocked interleave by their waits, and with nobody's start
## known the projection's order (Local's zones, then bee's) breaks the tie.
func test_the_cards_stand_in_n_order_then_done_working_idle() -> void:
	var frame := _frame_of([_view(LOCAL, "Local", fixture, false)])
	_since(frame, LOCAL, "infra:p1", 100.0)
	_since(frame, LOCAL, "web:p1", 200.0)
	_since(frame, LOCAL, "web:p2", 300.0)
	_since(frame, LOCAL, "infra:p2", 50.0)
	var model := PortraitBarModel.of(frame, "")
	_eq(_keys(model, PortraitBarModel.Group.BLOCKED), _waiting(frame, "blocked"), "the blocked in N's order")
	_eq(
		_keys(model, PortraitBarModel.Group.BLOCKED),
		[_pane("infra:p1"), _pane("web:p1")],
		"infra:p1 first: it has waited longer"
	)
	_eq(
		_keys(model, PortraitBarModel.Group.DONE),
		_waiting(frame, "done"),
		"the done in N's order once nobody is blocked"
	)
	_eq(_keys(model, PortraitBarModel.Group.DONE), [_pane("infra:p2"), _pane("web:p2")], "the oldest UNREAD first")
	_eq(
		_keys(model, PortraitBarModel.Group.WORKING),
		[_pane("api:p1"), _pane("api:p4"), _pane("data:p1")],
		"working in place order"
	)
	_eq(_keys(model, PortraitBarModel.Group.IDLE), [_pane("api:p2"), _pane("infra:p3")], "idle in place order")
	var groups: Array[int] = []
	for card in model.cards:
		groups.append(card.group)
	var sorted := groups.duplicate()
	sorted.sort()
	_eq(groups, sorted, "blocked, then done, then working, then idle: %s" % [groups])
	_eq(
		[
			model.counts[PortraitBarModel.Group.BLOCKED],
			model.counts[PortraitBarModel.Group.DONE],
			model.counts[PortraitBarModel.Group.WORKING],
			model.counts[PortraitBarModel.Group.IDLE]
		],
		[2, 2, 3, 2],
		"two, two, three, two"
	)
	_check(
		model.cards.all(func(card: PortraitBarModel.Card) -> bool: return card.machine_label.is_empty()),
		"one machine: none named"
	)
	var two := _frame_of([_view(LOCAL, "Local", fixture, false), _view(BEE, "bee", fixture, false)])
	_since(two, BEE, "infra:p1", 50.0)
	_since(two, LOCAL, "web:p1", 100.0)
	_since(two, BEE, "web:p1", 150.0)
	var both := PortraitBarModel.of(two, "")
	var blocked := [
		_pane("infra:p1"), HerdrFleet.pane_key(BEE, "infra:p1"), _pane("web:p1"), HerdrFleet.pane_key(BEE, "web:p1")
	]
	_eq(_keys(both, PortraitBarModel.Group.BLOCKED), _waiting(two, "blocked"), "two machines: still N's order")
	_eq(
		_keys(both, PortraitBarModel.Group.BLOCKED),
		blocked,
		"Local's unknown start first, then by wait across the machines"
	)
	var done := [
		_pane("web:p2"), _pane("infra:p2"), HerdrFleet.pane_key(BEE, "web:p2"), HerdrFleet.pane_key(BEE, "infra:p2")
	]
	_eq(_keys(both, PortraitBarModel.Group.DONE), done, "no start known: the projection's order breaks the tie")
	var working := [_pane("api:p1"), _pane("api:p4"), _pane("data:p1")]
	for pane_id: String in ["api:p1", "api:p4", "data:p1"]:
		working.append(HerdrFleet.pane_key(BEE, pane_id))
	_eq(_keys(both, PortraitBarModel.Group.WORKING), working, "working: Local's places, then bee's")
	_eq(both.cards[1].machine_label, "bee", "among several machines a card names its machine")


## Who gets no card: a shell, an agent herdr is still launching that does not
## ask (api:p2 idle, data:p2), and every pane of a machine that is not
## answering (bee). A blocked agent still starting is BLOCKED; a state the
## pack does not draw is IDLE; a pane no zone seats has a card with an
## unnamed space and no group.
func test_only_agents_of_live_machines_get_cards() -> void:
	var loose := _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	loose = _with(loose, "api:p1", {"agent_status": "blocked", "launch_pending": true})
	loose = _with(loose, "api:p2", {"launch_pending": true})
	loose = _with(loose, "infra:p3", {"agent_status": "unknown"})
	var frame := _frame_of([_view(LOCAL, "Local", loose, false), _view(BEE, "bee", fixture, true)])
	var model := PortraitBarModel.of(frame, "")
	var keys: Array[String] = []
	for card in model.cards:
		keys.append(card.key)
	_check(keys.all(func(key: String) -> bool: return key.begins_with(LOCAL)), "nothing of bee's: %s" % [keys])
	for shell: String in ["api:p3", "web:p3", "notes:p1"]:
		if shell != "notes:p1":
			_check(not keys.has(_pane(shell)), "%s is a shell: no card" % shell)
	_check(not keys.has(_pane("api:p2")), "an idle agent herdr still launches: no card")
	_check(not keys.has(_pane("data:p2")), "nor data:p2")
	var starting := _card(model, _pane("api:p1"))
	_check(
		starting != null and starting.group == PortraitBarModel.Group.BLOCKED,
		"a blocked agent still starting is blocked"
	)
	if starting != null:
		_check(not starting.starting, "and drawn as it is at its seat: blocked, not starting")
	var unknown := _card(model, _pane("infra:p3"))
	_check(unknown != null and unknown.group == PortraitBarModel.Group.IDLE, "a state the pack does not draw is idle")
	if unknown != null:
		_eq(unknown.state, "unknown", "herdr's word kept")
	var unseated := _card(model, _pane("notes:p1"))
	_check(unseated != null and unseated.group == PortraitBarModel.Group.BLOCKED, "a pane no zone seats has its card")
	if unseated != null:
		_eq([unseated.place, unseated.zone_key, unseated.group_key], ["?", "", ""], "no space, no zone, no group")
	_eq(model.counts[PortraitBarModel.Group.BLOCKED], 4, "web:p1, infra:p1, api:p1 and notes:p1")
	_eq(keys.size(), 4 + 2 + 2 + 1, "four blocked, two done, two working, one idle")


## The spec's table (A.2, re-measured for the tiles in T.3b): four fleets at
## the strip's room at 960, 800 and 640 units (a tall bar: tiles) and 480 (a
## short one: cards) take exactly these rungs, forms, blocked shown and widths;
## and the scene measures those rooms and those widths, per form.
## S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens. The
## three tall rooms are worked out with the tile's widths at the rooms the scene
## measures beside `1 machine · 13 panes`; the 480 row is BAR-a's, unchanged.
func test_the_fold_ladder_takes_the_first_rung_that_fits() -> void:
	# fleet (b/d/w/i) -> per room: [rung, faces_shown, needed]
	var table: Dictionary[String, Array] = {
		"2/2/3/2": [[1, 2, 466.0], [2, 2, 290.0], [4, 2, 194.0], [4, 2, 170.0]],
		"1/1/2/2": [[1, 1, 310.0], [1, 1, 310.0], [2, 1, 186.0], [3, 1, 192.0]],
		"3/6/22/18": [[3, 3, 406.0], [4, 3, 334.0], [6, 3, 160.0], [5, 3, 190.0]],
		"12/10/20/11": [[5, 12, 460.0], [7, 9, 354.0], [7, 3, 186.0], [7, 4, 190.0]],
	}
	var forms: Dictionary[int, Array] = {
		1:
		[
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD
		],
		2:
		[
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		3:
		[
			PortraitBarModel.Form.CARD,
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		4:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		5:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD,
			PortraitBarModel.Form.FOLD
		],
		6:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY
		],
		7:
		[
			PortraitBarModel.Form.FACE,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY,
			PortraitBarModel.Form.TALLY
		],
	}
	for fleet: String in table:
		var counts := _counts(fleet)
		for index in ROOMS.size():
			var wanted: Array = table[fleet][index]
			var metrics := _metrics(TILE_METRICS if index < TALL_ROOMS else METRICS)
			var made := PortraitBarModel.fit(counts, metrics, ROOMS[index])
			var where := "%s at %d" % [fleet, ROOMS[index]]
			_eq([made.rung, made.faces_shown, made.needed], wanted, where)
			var rung: int = wanted[0]
			_eq(_forms(made), forms[rung], "%s: rung %d's forms" % [where, rung])
	# The scene: its widths per form, and the room it leaves the strip.
	var hud := await _bare_hud(Vector2(960, 480))
	hud.bar.show_portraits(PortraitBarModel.new(), _totals(1, 13))
	var strip: Control = hud.bar.get_node("%Strip")
	var widths: Array[float] = [960.0, 800.0, 640.0, 480.0]
	for index in widths.size():
		hud.fit(Vector2(widths[index], 480.0 if widths[index] > 480.0 else 320.0))
		await _frames(2)
		_eq(strip.size.x, ROOMS[index], "the strip's room at %d" % widths[index])
		var scene := hud.bar.metrics()
		_eq(
			[scene.card, scene.face, scene.fold, scene.tally, scene.gap],
			TILE_METRICS if index < TALL_ROOMS else METRICS,
			(
				"at %d the scene measures the table's widths: %s"
				% [widths[index], "tiles" if index < TALL_ROOMS else "cards"]
			)
		)
	hud.free()


## For every room from the four tallies' 102 to 1200, on the four fleets and a
## fleet of blocked alone, with the cards' widths and with the tiles': what the
## rung needs fits; every agent is shown or folded, once; on the last rung the
## faces are the first k blocked and the rest are the blocked tally; and a
## wider room never shows fewer agents. On a short bar and on a tall one, the
## bar gives the first k blocked the faces.
## S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens, so
## the ladder is walked with both forms' widths and the bar on both bands.
func test_the_ladder_never_hides_the_longest_waiting_blocked() -> void:
	for widths: Array in [METRICS, TILE_METRICS]:
		_never_hides(_metrics(widths))
	# The bar gives the first k blocked the faces, in N's order: the longest waits.
	var office := await _live_office(_many_blocked(12))
	for screen: Vector2 in [Vector2(480, 320), Vector2(640, 480)]:
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var bar := office.hud.bar
		var order := _waiting(office.frame, "blocked")
		var faces: Array[String] = []
		for card in bar.cards():
			faces.append(card.key)
		_eq(bar.is_tall(), screen.y >= office.hud.staff_tall_from, "%s: the form its band gives" % screen)
		_eq(bar.fitted().rung, PortraitBarModel.LAST_RUNG, "fourteen blocked at %s take the last rung" % screen)
		_eq(faces, order.slice(0, faces.size()), "the faces are the first of N's order at %s" % screen)
		_check(bar.fold_of(PortraitBarModel.Group.BLOCKED).tallied(), "and the rest a tally")
		_eq(
			bar.fold_of(PortraitBarModel.Group.BLOCKED).count_text(),
			"+%d" % (order.size() - faces.size()),
			"counting the blocked who have no face"
		)
	_done(office)


## The ladder's laws on every room from 102 to 1200 with `metrics`.
func _never_hides(metrics: PortraitBarModel.Metrics) -> void:
	for fleet: String in ["2/2/3/2", "1/1/2/2", "3/6/22/18", "12/10/20/11", "40/0/0/0", "0/3/50/50"]:
		var counts := _counts(fleet)
		var agents := 0
		for group: PortraitBarModel.Group in counts:
			agents += counts[group]
		var shown_before := -1
		var broken := 0
		for room in range(102, 1201):
			var made := PortraitBarModel.fit(counts, metrics, float(room))
			var shown := 0
			var folded := 0
			for group in PortraitBarModel.GROUPS:
				var on := made.shown_of(group, counts[group])
				shown += on
				folded += counts[group] - on
			var ok := made.needed <= float(room) and shown + folded == agents and shown >= shown_before
			if made.rung == PortraitBarModel.LAST_RUNG and counts[PortraitBarModel.Group.BLOCKED] > 0:
				ok = ok and made.forms[PortraitBarModel.Group.BLOCKED] == PortraitBarModel.Form.FACE
				ok = (
					ok
					and (
						made.shown_of(PortraitBarModel.Group.BLOCKED, counts[PortraitBarModel.Group.BLOCKED])
						== made.faces_shown
					)
				)
			if not ok and broken < 3:
				broken += 1
				_fail(
					"%s at %d: rung %d needs %s, shows %d of %d" % [fleet, room, made.rung, made.needed, shown, agents]
				)
			shown_before = shown
		_check(broken == 0, "%s holds at every room from 102 to 1200 with a card %s wide" % [fleet, metrics.card])


## A card at 2x in the shipped pack: a seven-glyph CJK name whole, a long
## English task cut with an ellipsis and whole in the tooltip, a blocked
## card's place and its hour-long wait (`api`, `1h 05m+`) both whole, a done
## card with no wait; every label inside its card. A tile (a tall bar) has a
## 48-unit name row: six CJK glyphs whole, the seventh cut, the long task cut,
## each whole in the tooltip; the wait always whole, the place whole beside a
## minutes wait (`12m`) and cut beside the hour-long one; every label inside
## its tile.
## S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens. The
## card's words are checked on a short bar (960×320: the same 60-unit text
## column as before); the tile's on a tall one (960×480): its name row is the
## tile's 48 units, so a seven-glyph CJK name (56 at 8 px, measured) cuts there,
## and `▮api 1h 05m+` needs 53 of 48, so the place gives way to the wait.
func test_a_card_says_name_place_and_wait_within_its_width() -> void:
	var hud := await _bare_hud(Vector2(960, 320))
	var model := PortraitBarModel.new()
	model.counts = {
		PortraitBarModel.Group.BLOCKED: 2,
		PortraitBarModel.Group.DONE: 2,
		PortraitBarModel.Group.WORKING: 0,
		PortraitBarModel.Group.IDLE: 0
	}
	model.cards = [
		_made("Local:a", PortraitBarModel.Group.BLOCKED, "整理舰队的日志", "api"),
		_made("Local:b", PortraitBarModel.Group.BLOCKED, "refactor the fleet", "api"),
		_made("Local:c", PortraitBarModel.Group.DONE, "tests", "web"),
		_made("Local:d", PortraitBarModel.Group.DONE, "整理舰队的日", "web"),
	]
	hud.bar.show_portraits(model, _totals(1, 4))
	hud.bar.show_waits({"Local:a": "12m", "Local:b": "1h 05m+"})
	await _frames(2)
	_check(not hud.bar.is_tall(), "960×320 is a short bar: cards")
	_eq(hud.bar.fitted().rung, 1, "four cards fit at 960")
	var cjk := hud.bar.card_for("Local:a")
	var long := hud.bar.card_for("Local:b")
	var done := hud.bar.card_for("Local:c")
	_check(cjk != null and long != null and done != null, "each has its card")
	if cjk == null or long == null or done == null:
		hud.free()
		return
	_check(_fits_label(_label(cjk, "%Name")), "a seven-glyph CJK name is whole")
	var name_label := _label(long, "%Name")
	_check(not _fits_label(name_label), "`refactor the fleet` does not fit its 60 units")
	_eq(name_label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "so it ends in an ellipsis")
	_eq(name_label.text, "refactor the fleet", "the label keeps the whole text")
	_check(long.get_tooltip(Vector2.ZERO).begins_with("refactor the fleet\n"), "and the tooltip says it whole")
	_check(_fits_label(_label(long, "%Place")), "`api` is whole")
	var wait := _label(long, "%Wait")
	_check(wait.visible and wait.text == "1h 05m+", "the hour-long wait shows: `%s`" % wait.text)
	_check(_fits_label(wait), "and whole")
	_check(not _label(done, "%Wait").visible, "a done card says no wait")
	_inside(hud.bar, "card")
	# The same agents on a tall bar: tiles.
	hud.fit(Vector2(960, 480))
	await _frames(2)
	_check(hud.bar.is_tall(), "960×480 is a tall bar: tiles")
	_eq(hud.bar.fitted().rung, 1, "four tiles fit at 960")
	var six := hud.bar.card_for("Local:d")
	_eq(_label(cjk, "%Name").size.x, 48.0, "a tile's name row is 48 units")
	_check(_fits_label(_label(six, "%Name")), "six CJK glyphs are whole on a tile")
	_check(not _fits_label(_label(cjk, "%Name")), "the seventh does not fit")
	_eq(_label(cjk, "%Name").text, "整理舰队的日志", "the label keeps the whole text")
	_check(cjk.get_tooltip(Vector2.ZERO).begins_with("整理舰队的日志\n"), "and the tooltip says it whole")
	_check(not _fits_label(_label(long, "%Name")), "`refactor the fleet` is cut on a tile too")
	_eq(_label(cjk, "%Name").horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "a tile's name is centred")
	_check(_fits_label(_label(cjk, "%Wait")) and _label(cjk, "%Wait").visible, "`12m` is whole")
	_check(_fits_label(_label(cjk, "%Place")), "and `api` beside it")
	_check(_fits_label(_label(long, "%Wait")) and _label(long, "%Wait").visible, "`1h 05m+` is whole")
	_check(not _fits_label(_label(long, "%Place")), "and the place gives way to it")
	_check(long.get_tooltip(Vector2.ZERO).ends_with("api"), "the tooltip says the place whole")
	_check(not _label(done, "%Wait").visible, "a done tile says no wait")
	_inside(hud.bar, "tile")
	hud.free()


## Every shown label, tag and face of `bar`'s cards stands inside its card.
func _inside(bar: OfficeBar, form: String) -> void:
	for card in bar.cards():
		var rect := card.get_global_rect()
		for path: String in ["%Name", "%Place", "%Wait"]:
			var label := _label(card, path)
			if label.is_visible_in_tree():
				_check(rect.encloses(label.get_global_rect()), "%s %s inside its %s" % [card.key, path, form])
		for path: String in ["%Tag", "%FaceBox"]:
			var node: Control = card.get_node(path)
			_check(rect.encloses(node.get_global_rect()), "%s: its %s too" % [card.key, path])


## A refresh keeps every card's node; a new order moves them; a pane that
## folds gives its node back to the pool, hidden, never freed, and the next
## pane shown takes it; the pool never holds more cards than were ever shown.
func test_cards_are_pooled_and_a_refresh_keeps_them() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var ids := _card_ids(bar)
	var most := ids.size()
	_check(most >= 4, "the fixture shows cards at 800: %s" % [ids.keys()])
	_feed(office, fixture)
	await _frames(1)
	_eq(_card_ids(bar), ids, "a refresh keeps every node")
	# infra:p1 blocks again from now: web:p1 has waited longer.
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	_feed(office, fixture)
	await _frames(1)
	var keys: Array[String] = []
	for card in bar.cards():
		keys.append(card.key)
	_eq(keys.slice(0, 2), [_pane("web:p1"), _pane("infra:p1")], "web:p1 now first")
	_eq(_card_ids(bar), ids, "the same nodes, moved")
	office.test_screen = Vector2(480, 320)
	office.refresh()
	await _frames(2)
	var kept := _card_ids(bar)
	for key: String in ids:
		if not kept.has(key):
			var node := instance_from_id(ids[key])
			_check(is_instance_valid(node), "%s's node is kept" % key)
			if is_instance_valid(node):
				var card := node as PortraitCard
				_check(not card.visible and card.key.is_empty(), "%s's node is pooled, hidden" % key)
	_eq(bar.cards().size() + bar.cards_pooled().size(), most, "no node made or freed")
	office.test_screen = Vector2(1920, 480)
	office.refresh()
	await _frames(2)
	most = maxi(most, bar.cards().size())
	_eq(bar.cards().size(), 9, "every agent has a card at 1920")
	_check(bar.cards_pooled().is_empty(), "the pool gave its nodes back")
	_check(bar.cards().size() + bar.cards_pooled().size() <= most, "never more nodes than were ever shown")
	_done(office)


## A card's tag wears its worktree group's carpet family (the sign's and the
## carpet's index, OfficeZoneSign.accent_of()): a mezzanine's tag is its
## source zone's; a pane no zone seats shows no tag.
func test_the_zone_tag_wears_its_groups_carpet_family() -> void:
	var worktrees := _snapshot_of("res://tools/fixtures/snapshot_worktrees.json")
	var office := await _live_office(worktrees, Vector2(1920, 480))
	var bar := office.hud.bar
	var source := ""
	var mezzanines := 0
	for card in bar.cards():
		var shown := card.shown_card()
		var tag: Panel = card.get_node("%Tag")
		_check(not shown.group_key.is_empty() and tag.visible, "%s is seated: a tag" % card.key)
		_eq(tag.theme_type_variation, StringName("CarpetTag%d" % OfficeZoneSign.accent_of(shown.group_key)), card.key)
		var zone := office.frame.find_zone(shown.zone_key)
		if zone != null and not zone.zone_model.mezzanine_of.is_empty():
			mezzanines += 1
			_eq(shown.group_key, zone.zone_model.mezzanine_of, "%s: a mezzanine's group is its source" % card.key)
			source = zone.zone_model.mezzanine_of
	_check(mezzanines >= 2, "the fixture's two lanes sit on mezzanines")
	var hs := bar.card_for(HerdrFleet.pane_key(LOCAL, "hs:p1"))
	var lane := bar.card_for(HerdrFleet.pane_key(LOCAL, "hud:p1"))
	_check(hs != null and lane != null, "the repo's own space and its lane both have cards")
	if hs != null and lane != null:
		_eq(source, hs.shown_card().zone_key, "the lanes hang under the repo's own space")
		_eq(
			(lane.get_node("%Tag") as Panel).theme_type_variation,
			(hs.get_node("%Tag") as Panel).theme_type_variation,
			"so a lane's tag is its source's"
		)
	_done(office)
	var loose := _with(fixture, "notes:p1", {"workspace_id": "gone", "agent": "pi", "agent_status": "blocked"})
	var other := await _live_office(loose, Vector2(1920, 480))
	var unseated := other.hud.bar.card_for(_pane("notes:p1"))
	_check(unseated != null, "the unseated pane has a card")
	if unseated != null:
		_check(not (unseated.get_node("%Tag") as Panel).visible, "and no tag")
	_done(other)


## A card's face is the seat's person: the same look (every slot) for the same
## pane and provider, standing and facing front, and it stands still. On a
## tile it is the portrait (PixelPortrait: a still, no AnimationPlayer), its
## bottom centre at the clip's bottom centre, so the 40×40 portrait is the
## clip, whole; on a card the small person, its foot at the clip's middle, 37
## under its top (the BAR-a measure).
## S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens: the
## holder is checked per form.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42
## portrait: on a tile the face is the portrait (was the small person, its
## foot 37 under a 46×22 clip's top), so the look is the portrait's
## (`portrait().look.look`), it is placed by its bottom centre, and the clip is
## 40×40, the portrait's own size (measured: Rect2(5, 1, 40, 40) of the tile).
func test_the_face_is_the_seats_person_and_stands_still() -> void:
	var office := await _live_office(fixture, Vector2(1920, 480))
	for screen: Vector2 in [Vector2(1920, 480), Vector2(1920, 320)]:
		office.test_screen = screen
		office.refresh()
		await _frames(2)
		var tall := office.hud.bar.is_tall()
		var form := "tile" if tall else "card"
		_eq(tall, screen.y >= office.hud.staff_tall_from, "%s: its band's form" % screen)
		var checked := 0
		for card in office.hud.bar.cards():
			if not office.floor_view.seats.has(card.key):
				continue
			var seated := _worker(office.floor_view.seats[card.key].node)
			var face: Node2D = card.portrait() if tall else card.person()
			_check(face != null and seated != null, "%s: a %s face and a person at the seat" % [card.key, form])
			if face == null or seated == null:
				continue
			checked += 1
			var look: AvatarLook = card.portrait().look.look if tall else card.person().look
			for slot in AvatarLook.SLOTS:
				_eq(look.slot(slot), seated.look.slot(slot), "%s's %s: the same %s" % [card.key, form, slot])
			_eq(look.context, AvatarLook.STAND, "%s's %s stands" % [card.key, form])
			_eq(look.orientation, AvatarLook.FRONT, "%s's %s faces front" % [card.key, form])
			var clip := (card.get_node("%Face") as Control).get_global_rect()
			var at := face.get_global_transform().origin
			if tall:
				_eq(
					at,
					Vector2(clip.get_center().x, clip.end.y),
					"%s's portrait: at the clip's bottom centre" % card.key
				)
				var top := card.portrait().sprite_of(&"top")
				_eq(top.get_global_transform() * top.get_rect(), clip, "%s's portrait: the clip, whole" % card.key)
				_eq(face.find_children("*", "AnimationPlayer", true, false).size(), 0, "%s: a still" % card.key)
			else:
				_eq(
					at, Vector2(clip.get_center().x, clip.position.y + 37.0), "%s's person: 37 under the top" % card.key
				)
				var player: AnimationPlayer = face.get_node("AnimationPlayer")
				_check(not player.is_playing(), "%s's person stands still" % card.key)
		_eq(checked, 9, "every agent of the fixture as a %s" % form)
		var first: Control = office.hud.bar.cards()[0].get_node("%Face")
		_eq(first.size, Vector2(40, 40) if tall else Vector2(18, 26), "the %s's face window" % form)
	await _frames(10)
	var still := office.hud.bar.cards()[0].person().get_node("AnimationPlayer") as AnimationPlayer
	_check(not still.is_playing(), "and stays still")
	_done(office)


## Each group's frame is its own: on a tile the frame over the portrait wears
## it (`%FaceFrame`, PortraitFrame<State>) on the cream window (PortraitWindow)
## and the tile none (PortraitTile), a card wears it itself
## (PortraitCard<State>) round a bare window; only the selected pane's card
## wears the paper ring, 1 in from the frame, and it follows the selection;
## the pointed ring 2 in, on either form: under the face on a card, over the
## portrait on a tile.
## S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens: on
## a tile the frame and the rings are the face window's (B2: the words stand on
## the bar's ground), so the looks and the ring rects are checked per form.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42
## portrait: the portrait fills the window, so the state's frame is an overlay
## of its own over it (`%FaceFrame`, P2's PortraitFrame<State>; the window's
## PortraitFace<State> is retired) and the pointed ring lies over the portrait
## (D-RINGS: under it, the shoulders and long hair would hide it).
func test_a_card_frame_says_the_state_and_the_selected_one_its_ring() -> void:
	var office := await _live_office(fixture, Vector2(1920, 480))
	var bar := office.hud.bar
	var looks: Dictionary[String, String] = {
		"web:p1": "Blocked",
		"web:p2": "Done",
		"api:p1": "Working",
		"api:p2": "Idle",
	}
	_check(bar.is_tall(), "1920×480: tiles")
	for pane_id: String in looks:
		var card := bar.card_for(_pane(pane_id))
		_check(card != null, "%s has a card" % pane_id)
		if card != null:
			_eq(card.theme_type_variation, &"PortraitTile", "%s: the tile wears no frame" % pane_id)
			var window := card.get_node("%FaceBox") as Control
			var frame := card.get_node("%FaceFrame") as Control
			_eq(window.theme_type_variation, &"PortraitWindow", "%s: its window is the cream ground" % pane_id)
			_check(frame.visible, "%s: a frame over the portrait" % pane_id)
			_eq(
				frame.theme_type_variation,
				StringName("PortraitFrame" + looks[pane_id]),
				"%s: the frame over its portrait wears the state" % pane_id
			)
	# Before any pick the office's selection is herdr's focus (the list's highlight).
	var active := office.navigator.active_key
	var at_first: Array[String] = []
	if bar.card_for(active) != null:
		at_first.append(active)
	_eq(_ringed(bar), at_first, "the ring is on the office's selection alone: %s" % active)
	await _click_desk(office, _pane("api:p1"))
	await _frames(2)
	_eq(office.navigator.active_key, _pane("api:p1"), "a click on the desk selects api:p1")
	_eq(_ringed(bar), [_pane("api:p1")], "its card alone wears the ring")
	var picked := bar.card_for(_pane("api:p1"))
	await _rings_nest(bar, picked, (picked.get_node("%FaceBox") as Control).get_global_rect(), "tile")
	office.test_screen = Vector2(1920, 320)
	office.refresh()
	await _frames(2)
	_check(not bar.is_tall(), "1920×320: cards")
	_eq(bar.card_for(_pane("api:p1")), picked, "the same node")
	for pane_id: String in looks:
		var card := bar.card_for(_pane(pane_id))
		_eq(card.theme_type_variation, StringName("PortraitCard" + looks[pane_id]), "%s: the card wears it" % pane_id)
		_eq((card.get_node("%FaceBox") as Control).theme_type_variation, &"PortraitFaceBare", "round a bare window")
		_check(not (card.get_node("%FaceFrame") as Control).visible, "%s: no frame over the small person" % pane_id)
	await _rings_nest(bar, picked, picked.get_global_rect(), "card")
	office.test_screen = Vector2(1920, 480)
	office.refresh()
	await _frames(2)
	await _click_desk(office, _pane("web:p2"))
	await _frames(2)
	_eq(_ringed(bar), [_pane("web:p2")], "and the ring follows")
	_done(office)


## On `card`, whose frame is `frame`: the selection's ring 1 in, the pointed
## ring 2 in, both showing at once (S3 BAR-b ruling 1, 2026-10-27: the state's
## edge, the selection and the pointing all show); the pointed ring under the
## face on a card, over the portrait on a tile (S3 PORTRAIT P3, 2026-10-28:
## D-RINGS, the portrait fills the tile's window).
func _rings_nest(bar: OfficeBar, card: PortraitCard, frame: Rect2, form: String) -> void:
	var ring := card.get_node("%Selected") as Control
	_check(ring.visible, "%s: selected" % form)
	_eq(ring.get_global_rect(), frame.grow(-1.0), "%s: inside the state's edge, which still shows" % form)
	bar.point(PackedStringArray([card.key]))
	await _frames(1)
	var pointed := card.get_node("%Pointed") as Control
	_check(pointed.visible and ring.visible, "%s: pointed at and selected together" % form)
	_eq(pointed.get_global_rect(), frame.grow(-2.0), "%s: the pointed ring inside the selection's" % form)
	# S3 PORTRAIT P3 round 2 (2026-10-28): on a tile the rings lie on the cream window: `paper` on cream did not
	# read (9, 12, 20 apart), so a tile's selection is `ink` and its pointed ring `slate`; a card keeps `paper` on its
	# dark ground.
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var tall := card.is_tall()
	var looks: Array[StringName] = [&"PortraitSelected", &"PortraitPointed"]
	var colours: Array[StringName] = [ArtContract.PAPER, ArtContract.PAPER]
	if tall:
		looks = [&"PortraitSelectedTile", &"PortraitPointedTile"]
		colours = [ArtContract.INK, ArtContract.SLATE]
	var drawn_rings: Array[Control] = [ring, pointed]
	for index in drawn_rings.size():
		var drawn := drawn_rings[index]
		_eq(drawn.theme_type_variation, looks[index], "%s: %s in its own look" % [form, drawn.name])
		var line := drawn.get_theme_stylebox("panel") as StyleBoxFlat
		_eq(line.border_color, art.color(colours[index]), "%s: %s in %s" % [form, drawn.name, colours[index]])
	var face := card.get_node("%Face") as Control
	var under := face if pointed.get_parent() == face.get_parent() else card.get_node("%Body") as Control
	_eq(pointed.get_parent(), under.get_parent(), "%s: the ring and the face's box are siblings" % form)
	if card.is_tall():
		_check(pointed.get_index() > face.get_index(), "tile: drawn over the portrait")
	else:
		_check(pointed.get_index() < under.get_index(), "card: drawn under the face: the head's top stays whole")
	bar.point(PackedStringArray())
	await _frames(1)


## Answer mode owns the number keys: outside it, real presses of 1 to 9 pick
## no card, and no card ever holds the focus.
func test_number_keys_pick_no_card() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	_check(not office.hud.inspector.answering(), "not answering")
	for card in bar.cards():
		_eq(card.focus_mode, Control.FOCUS_NONE, "%s takes no focus" % card.key)
	var picked := office.picked_key
	for code: Key in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]:
		await _office_key(office, code)
	_eq(office.picked_key, picked, "1 to 9 pick nobody")
	await _press(bar.cards()[0])
	await _frames(2)
	_check(not office.picked_key.is_empty(), "a click picks")
	_check(not (root.gui_get_focus_owner() is PortraitCard), "and leaves no card with the focus")
	_done(office)


## A real motion onto a card points at its desk (OfficePointer's frame there,
## as a list row does); moving off clears it. Nothing is picked.
func test_hovering_a_card_points_at_its_desk() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var card := bar.cards()[0]
	var pointer := office.floor_view.pointer
	await _hover(card)
	await _frames(1)
	_eq(root.gui_get_hovered_control(), card, "the pointer is over the card")
	_eq([pointer.key, pointer.visible], [card.key, true], "its desk is framed")
	var extent := office.floor_view.signal_extent(card.key)
	_check(
		pointer.rect.encloses(extent) and pointer.rect.get_center().is_equal_approx(extent.get_center()),
		"round the desk's signal"
	)
	_eq(office.picked_key, "", "and nothing is picked")
	await _pointer_to(office.hud.world_rect().get_center())
	await _frames(1)
	_eq([pointer.key, pointer.visible], ["", false], "off the card: no frame")
	_done(office)


## A refresh that would show the strip it shows already lays nothing out and
## writes nothing (S3 BAR-a ruling 1): the same snapshot again, the same model
## handed to the bar again, and attention's beat (which writes only the waits)
## leave the lay-out count and every card's and fold's words, look, size and
## place as they were. A real change lays it out once. Among several machines
## (S3 BAR-b, 2026-10-27), the chips and a card's pointed ring are written apart,
## each on its own change: the same snapshots leave the chips as they were, and
## pointing at a card writes its ring alone and lays nothing out. A tall bar
## turned short, and back, lays the strip out once each way and keeps every
## card, pooled card and fold on the same node (S3 TILES, 2026-10-28: the
## strip's cards are B2's tiles on tall screens; a form change is the only
## change a refit makes to the strip).
func test_an_unchanged_strip_lays_nothing_out() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	await _text_tick()
	var count := bar.layouts()
	var before := _strip_picture(bar)
	_feed(office, fixture)
	await _frames(2)
	_eq(bar.layouts(), count, "the same snapshot again: no lay-out")
	bar.show_portraits(PortraitBarModel.of(office.frame, office.navigator.active_key), _totals(1, 13))
	await _frames(2)
	_eq(bar.layouts(), count, "the same model handed again: none either")
	_eq(_strip_picture(bar), before, "and nothing on the strip changed")
	await _wait_ticks(2)
	_eq(bar.layouts(), count, "attention's beat writes the waits, and lays nothing out")
	var nodes := _strip_nodes(bar)
	_check(bar.is_tall(), "the suite's 800×480: tiles")
	var tiles := _faces(bar)
	office.test_screen = Vector2(800, 320)
	office.refresh()
	await _frames(2)
	_check(not bar.is_tall(), "800×320: cards")
	_eq(bar.layouts(), count + 1, "a tall bar turned short: laid out once")
	_eq(_strip_nodes(bar), nodes, "every card, pooled card and fold on the same node")
	var cards := _faces(bar)
	for key: String in cards:
		var person: int = cards[key][2]
		_check(person != 0, "%s: its card's person is dressed" % key)
		if tiles.has(key):
			_eq(cards[key].slice(0, 2), tiles[key].slice(0, 2), "%s: its hidden portrait as it was" % key)
	office.test_screen = Vector2(SCREEN)
	office.refresh()
	await _frames(2)
	_check(bar.is_tall(), "back to tiles")
	_eq(bar.layouts(), count + 2, "and back: once more")
	_eq(_strip_nodes(bar), nodes, "still the same nodes")
	_eq(_strip_picture(bar), before, "showing what they showed")
	var back := _faces(bar)
	for key: String in back:
		if cards.has(key):
			_eq(back[key], cards[key], "%s: no face dressed again: the same nodes in the same looks" % key)
	count = bar.layouts()
	_feed(office, _with(fixture, "infra:p1", {"agent_status": "working"}))
	await _frames(2)
	_eq(bar.layouts(), count + 1, "a real change: laid out once")
	_check(bar.card_for(_pane("infra:p1")) == null, "infra:p1 is no longer a blocked card")
	_done(office)
	var two := await _two_machine_office()
	bar = two.hud.bar
	await _text_tick()
	count = bar.layouts()
	before = _strip_picture(bar)
	var chips := _chip_picture(bar)
	_eq(chips.size(), 2, "two machines: a chip each")
	_feed(two, fixture)
	# bee's client is stopped and online already (_two_machine_office()): the
	# same snapshot applied again, as a reply would be.
	_bee(two)._apply_snapshot(_bee_snapshot("blocked"))
	await _frames(2)
	_eq(bar.layouts(), count, "the same two snapshots again: no lay-out")
	_eq(_chip_picture(bar), chips, "the chips as they were, on the same nodes")
	_eq(_strip_picture(bar), before, "and the strip too")
	var hive := HerdrFleet.pane_key(BEE, "hive:p1")
	bar.point(PackedStringArray([hive]))
	await _frames(2)
	_eq(bar.layouts(), count, "pointing at a card lays nothing out")
	_check(bar.card_for(hive).pointed(), "it writes that card's ring")
	before[before.find(before.filter(func(row: Array) -> bool: return row[0] == hive)[0])][8] = true
	_eq(_strip_picture(bar), before, "and nothing else on the strip")
	bar.point(PackedStringArray())
	await _frames(2)
	_check(not bar.card_for(hive).pointed(), "pointing at nothing takes the ring away")
	_eq(bar.layouts(), count, "and lays nothing out either")
	_eq(_chip_picture(bar), chips, "the chips untouched throughout")
	_done(two)


## A tile wears its state's small mark (S3 TILES, Q-U4: B2's dots) in its face
## window's top-left corner, 8 units square at the pack's density: blocked's
## `!`, done's envelope (unread's), working's and idle's dots; a card on a
## short bar wears none. The mark is never pulsed: a plain sprite, not a
## StatusBadge, out of the attention clock's group, at rest beat after beat, while the
## blocked seat's badge in the world, which keeps the pack's 16-unit badge,
## bobs on the same clock.
func test_a_tile_wears_its_states_dot_and_it_never_bobs() -> void:
	var office := await _live_office(fixture, Vector2(1920, 480))
	var bar := office.hud.bar
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var dots: Dictionary[String, StringName] = {
		"web:p1": &"badge_blocked_small",
		"web:p2": &"badge_unread_small",
		"api:p1": &"badge_working_small",
		"api:p2": &"badge_idle_small",
	}
	var marks: Array[Sprite2D] = []
	for pane_id: String in dots:
		var card := bar.card_for(_pane(pane_id))
		_check(card != null and card.is_tall(), "%s has a tile" % pane_id)
		if card == null:
			continue
		var mark := card.badge()
		var window: Control = card.get_node("%FaceBox")
		_check(mark.visible, "%s wears a mark" % pane_id)
		_eq(PortraitCard.dot_of(art, card.shown_card().group), dots[pane_id], "%s: the mark for its state" % pane_id)
		_eq(mark.texture.get_size(), Vector2(16, 16), "%s: 16 texels square" % pane_id)
		var drawn := mark.get_global_transform() * mark.get_rect()
		_eq(
			drawn,
			Rect2(window.get_global_rect().position, Vector2(8, 8)),
			"%s: 8 units, in the window's corner" % pane_id
		)
		_check(
			not mark is StatusBadge and not mark.is_in_group(StatusBadge.GROUP),
			"%s: a plain sprite, never in the attention clock's group" % pane_id
		)
		marks.append(mark)
	var seat := _world_badge(office, "web:p1")
	_check(seat != null, "web:p1's seat has its badge in the world")
	if seat == null:
		_done(office)
		return
	_check(seat.texture.get_size() != marks[0].texture.get_size(), "the world keeps the pack's badge, not the mark")
	var rests: Array[Vector2] = []
	for mark in marks:
		rests.append(mark.offset)
	var lifts: Dictionary[Vector2, bool] = {}
	var still := true
	# Over a second and a half of real time: blocked's rhythm steps every 0.3 s.
	var until := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < until:
		await process_frame
		lifts[seat.offset] = true
		for index in marks.size():
			still = still and marks[index].offset == rests[index]
	_check(lifts.size() >= 2, "the seat's badge bobs on the clock: %s" % [lifts.keys()])
	_check(still, "the tiles' marks never move")
	office.test_screen = Vector2(1920, 320)
	office.refresh()
	await _frames(2)
	for pane_id: String in dots:
		var card := bar.card_for(_pane(pane_id))
		_check(card != null and not card.is_tall() and not card.badge().visible, "%s: a card wears no mark" % pane_id)
	_done(office)


## A short bar (a screen under `staff_tall_from`) keeps BAR-a's horizontal
## card exactly: 86×28, the face window 18×26 at (1, 1), the words 60×24 at
## (22, 2), the face alone 20×28 (the same window), folds 40×28 and tallies
## 24×28, the frame on the card, no mark. A tall one shows the tiles: 50×66,
## the portrait's 40×40 clip at (5, 1) (its 42×42 window centred at (4, 0))
## over the name and the place rows (48×12 each, from y 42), the face alone
## 26×66 with the clip 22×40 at (2, 1) (the portrait cropped to its middle),
## folds 40×66 and tallies 24×66. The same nodes either way.
## S3 TILES (2026-10-28): the strip's cards are B2's tiles on tall screens.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42
## portrait: the tall row was 50×48, the clip 46×22 at (2, 1), the words at
## y 24, the face alone 26×48 and folds 48 tall (measured on this tree: the
## print of the first run); 640 wide added so a face-only tile is measured.
func test_short_screens_keep_the_horizontal_card() -> void:
	var office := await _live_office()
	var bar := office.hud.bar
	var forms: Dictionary[float, Array] = {
		320.0: [Vector2(86, 28), Vector2(20, 28), Rect2(1, 1, 18, 26), Rect2(22, 2, 60, 24), 28.0, Rect2(1, 1, 18, 26)],
		480.0: [Vector2(50, 66), Vector2(26, 66), Rect2(5, 1, 40, 40), Rect2(1, 42, 48, 24), 66.0, Rect2(2, 1, 22, 40)],
	}
	var nodes := _strip_nodes(bar)
	var alone := 0
	for height: float in [320.0, 480.0, 320.0]:
		for width: float in [640.0, 800.0, 1920.0]:
			office.test_screen = Vector2(width, height)
			office.refresh()
			await _frames(2)
			var wanted: Array = forms[height]
			var where := "%dx%d" % [width, height]
			_eq(bar.is_tall(), height >= office.hud.staff_tall_from, "%s: the band's form" % where)
			_check(not bar.cards().is_empty(), "%s: cards show" % where)
			for card in bar.cards():
				var at := card.get_global_rect().position
				var face: Control = card.get_node("%Face")
				var words: Control = card.get_node("%Text")
				_eq(card.size, wanted[1] if card.face_only() else wanted[0], "%s %s: its size" % [where, card.key])
				var window := face.get_global_rect()
				var clip: Rect2 = wanted[5] if card.face_only() else wanted[2]
				_eq(Rect2(window.position - at, window.size), clip, "%s %s: the face window" % [where, card.key])
				if card.face_only() and card.is_tall():
					alone += 1
				if not card.face_only():
					var text := words.get_global_rect()
					_eq(Rect2(text.position - at, text.size), wanted[3], "%s %s: the words" % [where, card.key])
				_eq(card.badge().visible, card.is_tall(), "%s %s: a mark on a tile only" % [where, card.key])
				_eq(
					card.theme_type_variation == &"PortraitTile",
					card.is_tall(),
					"%s %s: the frame on the card only as a card" % [where, card.key]
				)
			var tall_as: float = wanted[4]
			for fold in bar.folds():
				if fold.visible:
					_eq(fold.size, Vector2(24.0 if fold.tallied() else 40.0, tall_as), "%s %s" % [where, fold.name])
	_check(alone > 0, "a face-only tile was measured: %d" % alone)
	var kept := _strip_nodes(bar)
	_check(nodes.all(func(id: int) -> bool: return kept.has(id)), "every node the strip had is kept through every form")
	_done(office)


## The bar's right end says B2's words, `1 machine · 13 panes`
## (OfficeTotals.count_words(): `2 machines`, `1 pane`), whole, and keeps the
## chime switch and the two lines; a dropped machine still counts as a
## machine and carries no panes. On a tall bar the wordmark, the count, the
## switch and the lines stand in the band's middle (no box more than two
## units off it; the wordmark, the count and the switch exactly), and the
## short band keeps its places exactly. A real click on the count still opens the
## OVERVIEW; one on the switch still flips the chime.
## S3 TILES (2026-10-28): D-RIGHTEND's default; A1 centred only the strip.
func test_the_right_end_says_machines_and_panes_and_keeps_its_switches() -> void:
	_eq(OfficeTotals.count_words(1, 13), "1 machine · 13 panes", "B2's words")
	_eq(OfficeTotals.count_words(2, 40), "2 machines · 40 panes", "two machines")
	_eq(OfficeTotals.count_words(1, 1), "1 machine · 1 pane", "one pane")
	_eq(OfficeTotals.count_words(0, 0), "0 machines · 0 panes", "none")
	var office := await _live_office(fixture, Vector2(960, 480))
	var bar := office.hud.bar
	var panes: Button = bar.get_node("%Panes")
	var chime: Button = bar.get_node("%Chime")
	var lines: Control = bar.get_node("%Lines")
	var wordmark: Control = bar.get_node("%Wordmark")
	_eq(panes.text, "1 machine · 13 panes", "the fixture's machine and panes")
	var font := panes.get_theme_font("font")
	var words := font.get_string_size(panes.text, HORIZONTAL_ALIGNMENT_LEFT, -1, panes.get_theme_font_size("font_size"))
	_check(words.x <= panes.size.x, "whole: %s in %s" % [words.x, panes.size.x])
	_check(panes.visible and chime.visible and lines.visible, "the count, the switch and the lines all show")
	var band := bar.get_global_rect()
	_eq(band.size.y, office.hud.bar_tall_height, "a tall band")
	for node: Control in [wordmark, panes, chime, lines]:
		var off := node.get_global_rect().get_center().y - band.get_center().y
		_check(absf(off) <= 2.0, "%s stands in the band's middle: %s off" % [node.name, off])
	_eq(panes.get_global_rect().get_center().y, band.get_center().y, "the count exactly")
	_eq(chime.get_global_rect().get_center().y, band.get_center().y, "the switch exactly")
	_eq(
		wordmark.get_global_rect().get_center().y,
		band.get_center().y,
		"the wordmark exactly (WordmarkMarginTall: no margin over its row, its caps on the middle line)"
	)
	office.test_screen = Vector2(960, 320)
	office.refresh()
	await _frames(2)
	_eq(bar.get_global_rect().size.y, office.hud.bar_short_height, "a short band")
	_eq(
		[
			wordmark.get_global_rect().position.y,
			lines.get_global_rect().position.y,
			panes.get_global_rect().position.y,
			chime.get_global_rect().position.y
		],
		[6.5, 2.0, 2.5, 2.5],
		"the short band keeps the wordmark, the lines, the count and the switch where they stood (b0b3619, measured)"
	)
	office.test_screen = Vector2(960, 480)
	office.refresh()
	await _frames(2)
	_check(not office.hud.overview_open(), "the OVERVIEW closed")
	await _press(panes)
	await _frames(2)
	_check(office.hud.overview_open(), "a click on the count opens the OVERVIEW")
	await _press(panes)
	await _frames(2)
	_check(not office.hud.overview_open(), "and closes it")
	var was := bar.chime_shown()
	await _press(chime)
	await _frames(2)
	_eq(bar.chime_shown(), not was, "a click on the switch flips the chime")
	await _press(chime)
	await _frames(2)
	_eq(bar.chime_shown(), was, "and back")
	_set_online(office, false)
	await _frames(1)
	_eq(panes.text, "1 machine · 0 panes", "a dropped machine is still a machine, with no panes")
	_done(office)
	var two := await _two_machine_office(fixture, Vector2(960, 480))
	var both: Button = two.hud.bar.get_node("%Panes")
	_check(both.text.begins_with("2 machines · "), "two machines: %s" % both.text)
	_done(two)


## A tile shows the seat's person as a portrait (PixelPortrait, the pane's
## PixelPortraits.look_of()), and the small person's holder is hidden; a card
## shows the small person, and the portrait's holder is hidden. One card node
## makes both faces with its first pane and keeps them through every flip (a
## flip makes no node); after that it dresses only the face its form shows,
## and the hidden one only when it shows again: a pane change on a tile leaves
## the hidden person as it was, and a flip back dresses nothing.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42
## portrait (Part P3.2: the tile shows the portrait, the card keeps the person).
func test_a_tile_shows_the_seats_portrait_and_a_card_its_person() -> void:
	var hud := await _bare_hud(Vector2(960, 320))
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var model := PortraitBarModel.new()
	model.counts = {
		PortraitBarModel.Group.BLOCKED: 1,
		PortraitBarModel.Group.DONE: 0,
		PortraitBarModel.Group.WORKING: 0,
		PortraitBarModel.Group.IDLE: 0
	}
	model.cards = [_made("Local:a", PortraitBarModel.Group.BLOCKED, "a", "api")]
	hud.bar.show_portraits(model, _totals(1, 1))
	await _frames(2)
	var card := hud.bar.card_for("Local:a")
	_check(card != null and not card.is_tall(), "960×320: a card")
	if card == null:
		hud.free()
		return
	var small: Node2D = card.get_node("%FaceHolder")
	var still: Node2D = card.get_node("%PortraitHolder")
	_check(card.person() != null and card.person().is_visible_in_tree(), "a card shows the small person")
	_check(not still.visible, "the portrait's holder hidden")
	var portrait := card.portrait()
	_check(portrait != null and not portrait.is_visible_in_tree(), "the portrait made with the card, hidden")
	var person := card.person()
	var person_look := person.look
	var portrait_look := portrait.look
	hud.fit(Vector2(960, 480))
	await _frames(2)
	_check(card.is_tall() and hud.bar.card_for("Local:a") == card, "960×480: the same node as a tile")
	_check(card.portrait() == portrait and portrait.is_visible_in_tree(), "a tile shows the same portrait")
	_check(portrait.look == portrait_look, "dressed once, with the card: the flip dresses nothing")
	_check(not small.visible and not person.is_visible_in_tree(), "the small person's holder hidden")
	_eq(portrait.get_parent(), still, "in the portrait's holder")
	_eq(still.get_child_count(), 1, "one portrait")
	_eq(portrait.look.key(), art.portraits.look_of("claude", "Local:a").key(), "the pane's portrait")
	_check(card.person() == person and person.look == person_look, "the hidden person kept, not dressed again")
	model.cards = [_made("Local:b", PortraitBarModel.Group.BLOCKED, "b", "api")]
	hud.bar.show_portraits(model, _totals(1, 1))
	await _frames(2)
	_eq(hud.bar.card_for("Local:b"), card, "another pane on the same tile")
	_check(card.portrait() == portrait, "on the same portrait")
	_eq(portrait.look.key(), art.portraits.look_of("claude", "Local:b").key(), "dressed as that pane")
	_check(portrait.look != portrait_look, "dressed once more")
	_check(person.look == person_look, "the hidden person still Local:a's: not dressed while hidden")
	portrait_look = portrait.look
	hud.fit(Vector2(960, 320))
	await _frames(2)
	_check(not card.is_tall() and card.person() == person, "a card again, the same person")
	_check(person.is_visible_in_tree() and not still.visible, "shown, the portrait hidden")
	_check(person.look != person_look, "the person dressed as the pane it shows now")
	var wanted := AvatarLook.facing(AvatarLook.STAND, AvatarLook.FRONT)
	_eq(person.look.key(), art.people.look_for("claude", wanted, "Local:b").key(), "Local:b's person")
	_check(portrait.look == portrait_look, "the hidden portrait not dressed again")
	person_look = person.look
	hud.fit(Vector2(960, 480))
	await _frames(2)
	_check(card.portrait() == portrait and portrait.look == portrait_look, "a tile again: not dressed again")
	_check(person.look == person_look, "nor the person")
	_eq(still.get_child_count(), 1, "still one portrait")
	_eq(small.get_child_count(), 1, "and one person")
	hud.free()


## On a tile everything the HUD draws lies over the portrait, which fills the
## window (D-RINGS): the cream ground (`%FaceBox`, PortraitWindow), the clip
## with the portrait, the state's frame (`%FaceFrame`), the pointed ring, the
## selection's ring, the mark, in that order. With the pointer on a selected,
## pointed-at tile whose portrait's long hair falls to its bottom row (and
## whose shoulders fill the foot of its sides, as every portrait's do), the
## frame is the state's 2-unit edge round the window (…Lit), the selection's
## 1-unit ring lies on its inner unit, the pointed ring 1 unit inside that,
## all over the hair and the shoulders: none is hidden by the portrait. On the
## cream window the selection is `ink` and the pointed ring `slate`: each at
## least RING_APART from cream, from every state's frame colour and from the
## other ring.
## S3 PORTRAIT P3 round 2 (2026-10-28): on a tile the rings lie on the cream window: the rings were `paper`, 41
## apart from cream (9 + 12 + 20, measured on the capture): the selected tile did not look selected.
## S3 PORTRAIT P3 (2026-10-28): the tall band 70, the tile's window a 42×42
## portrait (Part P3.2, D-RINGS: a frame drawn last would cover the selection;
## rings under the portrait would hide under the shoulders and long hair).
func test_the_frame_and_rings_draw_over_the_portrait() -> void:
	var hud := await _bare_hud(Vector2(960, 480))
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var key := ""
	for index in 200:
		var look := art.portraits.look_of("claude", "Local:p%d" % index)
		var hatless := art.portraits.part_texture(&"headwear", look) == null
		if look.look.slot(&"hair_style") == &"long" and hatless:
			key = "Local:p%d" % index
			break
	_check(not key.is_empty(), "a pane with long hair and no hat: %s" % key)
	var model := PortraitBarModel.new()
	model.counts = {
		PortraitBarModel.Group.BLOCKED: 0,
		PortraitBarModel.Group.DONE: 0,
		PortraitBarModel.Group.WORKING: 1,
		PortraitBarModel.Group.IDLE: 0
	}
	model.cards = [_made(key, PortraitBarModel.Group.WORKING, "long", "api")]
	model.selected = key
	hud.bar.show_portraits(model, _totals(1, 1))
	await _frames(2)
	var card := hud.bar.card_for(key)
	_check(card != null and card.is_tall(), "a tile")
	if card == null:
		hud.free()
		return
	var window := card.get_node("%FaceBox") as Control
	var clip := card.get_node("%Face") as Control
	var frame := card.get_node("%FaceFrame") as Control
	var pointed := card.get_node("%Pointed") as Control
	var ring := card.get_node("%Selected") as Control
	var mark := card.badge()
	var order: Array[Node] = [clip, frame, pointed, ring, mark]
	for node in order:
		_eq(node.get_parent(), window, "%s lies in the window" % node.name)
	for index in order.size() - 1:
		_check(
			order[index].get_index() < order[index + 1].get_index(),
			"%s drawn under %s" % [order[index].name, order[index + 1].name]
		)
	_eq(window.theme_type_variation, &"PortraitWindow", "the cream ground under the portrait")
	_eq(window.size, Vector2(42, 42), "the window 42×42")
	var hair := card.portrait().sprite_of(&"hair")
	var top := card.portrait().sprite_of(&"top")
	_check(hair.texture != null and top.texture != null, "the long hair and the shoulders are drawn")
	var falls := hair.texture.get_image().get_used_rect()
	var shoulders := top.texture.get_image().get_used_rect()
	_eq(falls.end.y, 80, "the hair falls to the portrait's bottom row, under the rings' bottom lines: %s" % falls)
	_eq([shoulders.position.x, shoulders.end.x, shoulders.end.y], [0, 80, 80], "the shoulders fill the sides' foot")
	hud.bar.point(PackedStringArray([key]))
	await _hover(card)
	await _frames(1)
	_check(pointed.visible and ring.visible and frame.visible, "pointed, selected and framed at once")
	_eq(frame.theme_type_variation, &"PortraitFrameWorkingLit", "under the pointer the frame is the lit one")
	var edge := frame.get_theme_stylebox("panel") as StyleBoxFlat
	_eq(frame.get_global_rect(), window.get_global_rect(), "the frame round the whole window")
	_eq(edge.border_width_left, 2, "a 2-unit edge")
	_eq(edge.border_color, art.color(ArtContract.WORKING), "in the state's colour")
	_check(not edge.draw_center, "the portrait shows through it")
	_eq(ring.get_global_rect(), window.get_global_rect().grow(-1.0), "the selection on the edge's inner unit")
	_eq(pointed.get_global_rect(), window.get_global_rect().grow(-2.0), "the pointed ring inside it")
	var against: Array[StringName] = [
		ArtContract.CREAM, ArtContract.BLOCKED, ArtContract.UNREAD, ArtContract.WORKING, ArtContract.MUTED
	]
	var lines: Array[Color] = []
	for drawn: Control in [ring, pointed]:
		var line := drawn.get_theme_stylebox("panel") as StyleBoxFlat
		_eq(line.border_width_left, 1, "%s: 1 unit" % drawn.name)
		lines.append(line.border_color)
		for key_name: StringName in against:
			var apart := _apart(line.border_color, art.color(key_name))
			_check(apart >= RING_APART, "%s reads on %s: %d apart" % [drawn.name, key_name, apart])
	_check(_apart(lines[0], lines[1]) >= RING_APART, "the two rings apart: %d" % _apart(lines[0], lines[1]))
	var portrait := clip.get_global_rect()
	_check(portrait.encloses(pointed.get_global_rect()), "the pointed ring lies over the portrait itself")
	_eq(ring.get_global_rect(), portrait, "the selection on the portrait's outermost unit")
	hud.bar.point(PackedStringArray())
	await _pointer_to(Vector2(480, 300))
	await _frames(1)
	_eq(frame.theme_type_variation, &"PortraitFrameWorking", "the pointer gone: the 1-unit frame")
	hud.free()


# --- helpers ------------------------------------------------------------------


## Every shown card's and visible fold's words, look, size and place, its
## place's tooltip and its pointed ring, but the waits, which tick on their own
## beat.
func _strip_picture(bar: OfficeBar) -> Array:
	var picture := []
	for card in bar.cards():
		(
			picture
			. append(
				[
					card.key,
					_label(card, "%Name").text,
					_label(card, "%Place").text,
					card.theme_type_variation,
					(card.get_node("%Tag") as Control).theme_type_variation,
					card.get_global_rect(),
					card.face_only(),
					(card.get_node("%PlaceButton") as Control).tooltip_text,
					card.pointed(),
				]
			)
		)
	for fold in bar.folds():
		if fold.visible:
			picture.append([fold.name, fold.count_text(), fold.theme_type_variation, fold.get_global_rect()])
	return picture


## How far apart `a` and `b` are: the summed 8-bit RGB differences.
func _apart(a: Color, b: Color) -> int:
	return absi(a.r8 - b.r8) + absi(a.g8 - b.g8) + absi(a.b8 - b.b8)


## Each shown card's faces by pane: the portrait's node and its look, the
## person's node and its look, as instance ids (0 for none yet). A face dressed
## again has a new look (PixelPortraits.look_of(), PixelPeople.look_for()).
func _faces(bar: OfficeBar) -> Dictionary[String, Array]:
	var faces: Dictionary[String, Array] = {}
	for card in bar.cards():
		var portrait := card.portrait()
		var person := card.person()
		faces[card.key] = [
			portrait.get_instance_id() if portrait != null else 0,
			portrait.look.get_instance_id() if portrait != null else 0,
			person.get_instance_id() if person != null else 0,
			person.look.get_instance_id() if person != null else 0,
		]
	return faces


## Every node in the strip, shown or pooled, cards and folds, left to right.
func _strip_nodes(bar: OfficeBar) -> Array[int]:
	var ids: Array[int] = []
	for child in (bar.get_node("%Cards") as Control).get_children():
		ids.append(child.get_instance_id())
	return ids


## Every machine chip's key, words, look, rect and node.
func _chip_picture(bar: OfficeBar) -> Array:
	return bar.chips().map(
		func(chip: MachineChip) -> Array:
			return [chip.key, chip.text, chip.theme_type_variation, chip.get_global_rect(), chip.get_instance_id()]
	)


## `count` of attention's text beats.
func _wait_ticks(count: int) -> void:
	for index in count:
		await _text_tick()


func _snapshot_of(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		return {}
	var file: Dictionary = parsed
	return _dict(file, "snapshot") if file.has("snapshot") else file


func _view(key: String, label: String, snapshot: Dictionary, stale: bool) -> MachineView:
	return MachineView.new(key, label, HerdrSnapshot.from_wire(snapshot), stale)


func _frame_of(machines: Array[MachineView]) -> OfficeFrame:
	return OfficeProjection.frame(machines, PackedStringArray(STATES))


## Pane `pane_id` of `machine` began its state at unix `since`, wherever the
## frame holds it.
func _since(frame: OfficeFrame, machine: String, pane_id: String, since: float) -> void:
	var key := HerdrFleet.pane_key(machine, pane_id)
	for building in frame.buildings:
		for zone in building.zones:
			for room in zone.rooms:
				for pane in room.panes:
					if pane.key == key:
						pane.state_since = since
		for pane in building.all_panes:
			if pane.key == key:
				pane.state_since = since
	for pane in frame.live_panes:
		if pane.key == key:
			pane.state_since = since


func _waiting(frame: OfficeFrame, state: String) -> Array[String]:
	var keys: Array[String] = []
	for pane in OfficeNavigator.waiting(frame, state):
		keys.append(pane.key)
	return keys


func _keys(model: PortraitBarModel, group: PortraitBarModel.Group) -> Array[String]:
	var keys: Array[String] = []
	for card in model.of_group(group):
		keys.append(card.key)
	return keys


func _card(model: PortraitBarModel, key: String) -> PortraitBarModel.Card:
	for card in model.cards:
		if card.key == key:
			return card
	return null


## `widths` (METRICS or TILE_METRICS) as the ladder's metrics.
func _metrics(widths: Array) -> PortraitBarModel.Metrics:
	var made := PortraitBarModel.Metrics.new()
	made.card = widths[0]
	made.face = widths[1]
	made.fold = widths[2]
	made.tally = widths[3]
	made.gap = widths[4]
	return made


## `b/d/w/i` as the four groups' counts.
func _counts(fleet: String) -> Dictionary[PortraitBarModel.Group, int]:
	var parts := fleet.split("/")
	var counts: Dictionary[PortraitBarModel.Group, int] = {}
	for index in PortraitBarModel.GROUPS.size():
		counts[PortraitBarModel.GROUPS[index]] = int(parts[index])
	return counts


func _forms(made: PortraitBarModel.Fit) -> Array:
	var forms := []
	for group in PortraitBarModel.GROUPS:
		forms.append(made.forms[group])
	return forms


## The fixture with every agent blocked and `extra` more blocked agents in
## web's ui tab.
func _many_blocked(extra: int) -> Dictionary:
	var snapshot: Dictionary = fixture.duplicate(true)
	var panes: Array = snapshot.panes
	var agents: Array = snapshot.agents
	for index in extra:
		var pane_id := "web:x%d" % index
		var template: Dictionary = panes[4]
		var pane: Dictionary = template.duplicate(true)
		pane.pane_id = pane_id
		pane.terminal_id = "term-x%d" % index
		pane.agent_status = "blocked"
		panes.append(pane)
		var record: Dictionary = agents[3]
		var agent: Dictionary = record.duplicate(true)
		agent.pane_id = pane_id
		agent.terminal_id = pane.terminal_id
		agents.append(agent)
	return snapshot


func _made(key: String, group: PortraitBarModel.Group, name: String, place: String) -> PortraitBarModel.Card:
	var card := PortraitBarModel.Card.new()
	card.key = key
	card.machine = LOCAL
	card.provider = "claude"
	card.name = name
	card.place = place
	card.group = group
	card.state = PortraitBarModel.WORDS[group]
	card.group_key = HerdrFleet.pane_key(LOCAL, place)
	return card


func _card_ids(bar: OfficeBar) -> Dictionary[String, int]:
	var ids: Dictionary[String, int] = {}
	for card in bar.cards():
		ids[card.key] = card.get_instance_id()
	return ids


func _ringed(bar: OfficeBar) -> Array[String]:
	var found: Array[String] = []
	for card in bar.cards():
		if (card.get_node("%Selected") as Control).visible:
			found.append(card.key)
	return found


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


## A bare HUD dressed with the shipped pack and laid out for `screen`: no
## office, so nothing writes into the bar behind the case.
func _bare_hud(screen: Vector2) -> OfficeHud:
	var art := ArtPack.from_manifest(MANIFESTS[0])
	var hud: OfficeHud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.dress(art, OfficeDraw.new(art).font)
	hud.fit(screen)
	await _frames(2)
	return hud


## Whether `label`'s text fits its width in its own font, with no ellipsis.
func _fits_label(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= label.size.x


## A real pointer motion onto the middle of `control`.
func _hover(control: Control) -> void:
	await _pointer_to(_aim(control))


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


## Totals for the bar's count: `machines` in the fleet, `panes` on the live ones.
func _totals(machines: int, panes: int) -> OfficeTotals:
	var totals := OfficeTotals.new()
	totals.machines_total = machines
	totals.machines_live = machines
	totals.panes = panes
	return totals


## Pane `pane_id`'s badge over its seat in the world (Local's), in the
## attention clock's group; null when it has none.
func _world_badge(office: OfficeDouble, pane_id: String) -> StatusBadge:
	for node in office.get_tree().get_nodes_in_group(StatusBadge.GROUP):
		var badge := node as StatusBadge
		if badge.machine == LOCAL and badge.pane_id == pane_id and not office.hud.is_ancestor_of(badge):
			return badge
	return null
