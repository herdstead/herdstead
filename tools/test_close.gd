extends "res://tools/command_test_base.gd"
## Close pane on the agent card: two real clicks on Close send one
## `pane.close` with herdr's pane id and nothing else; the first click only
## says what the close takes with it (CloseScope: the pane, its table, its
## floor or its mezzanine, and that a working or blocked agent is killed),
## and anything that changes in between cancels it. Every gate of the write
## boundary, by real input: the repo's own floor never closed while its
## mezzanines are open, the pick or machine changing between press and
## release, a lost answer judged by the next snapshot only, herdr's own
## refusals said and never retried, the keyboard, no gesture, `--read-only`.
## An operator office against two fake herdrs of this suite's own (Local on
## A, bee on B, whose pane ids collide). Run through tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_close.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>
##
## Every case first resets both fakes and opens only what it needs (_fakes()),
## and asserts the exact requests each fake received. The last case sums up
## both fakes: nothing reached them that no case opened.

## Local's shell (alpha:p2), claude working (alpha:p1) and idle codex
## (alpha:p3), all at one table; bee's blocked pi (bravo:p1), alone on its floor.
var p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p1")
var p2 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p2")
var p3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha:p3")
var bee_p1 := HerdrFleet.pane_key(BEE, "bravo:p1")


func _marker() -> String:
	return "CLOSE TESTS"


# --- the scope, pure ------------------------------------------------------------------


## What closing each pane of the worktrees fixture takes with it, read off the
## typed snapshot alone: a pane among others; the last of its tab (a second
## tab added); the last of a plain floor; the last of a mezzanine, named as
## the FLOORS column hangs it (1A); the last of the repo's own floor while its
## mezzanines are open, which is never sent; a shell, an agent's state, a launch.
func test_close_scope_reads_each_scope_off_the_snapshot() -> void:
	var raw := _raw("snapshot_worktrees")
	var snapshot := HerdrSnapshot.from_wire(raw)
	var plain := CloseScope.of(snapshot, "hs:p3")
	_eq(
		[plain.missing, plain.last_of_tab, plain.last_of_space, plain.mezzanine, plain.group_parent, plain.kind()],
		[false, false, false, false, false, "pane"],
		"hs:p3: one of three panes at its table"
	)
	_eq([plain.state, plain.agent, plain.tab_id, plain.workspace_id], ["shell", "", "hs:t1", "hs"], "a shell")
	_eq([plain.panes_in_tab, plain.tabs_in_space, plain.level_label], [3, 1, "1"], "counted from the lists")
	var agent := CloseScope.of(snapshot, "hs:p1")
	_eq([agent.state, agent.agent], ["working", "claude"], "an agent's state word and kind")
	var notes := CloseScope.of(snapshot, "notes:p1")
	_eq(
		[notes.last_of_tab, notes.last_of_space, notes.mezzanine, notes.group_parent, notes.kind()],
		[true, true, false, false, "space"],
		""
	)
	_eq([notes.space_number, notes.space_label, notes.level_label], [4, "notes", "4"], "the floor's number and label")
	var mezzanine := CloseScope.of(snapshot, "data:p1")
	_eq(
		[mezzanine.last_of_tab, mezzanine.last_of_space, mezzanine.mezzanine],
		[false, false, true],
		"data:p1: one of two"
	)
	var alone := CloseScope.of(snapshot, "hud:p1")
	_eq(
		[alone.last_of_space, alone.mezzanine, alone.group_parent, alone.level_label, alone.space_label, alone.kind()],
		[true, true, false, "1A", "hud lane", "mezzanine"],
		"hud:p1: the last pane of mezzanine 1A"
	)
	var second := CloseScope.of(snapshot, "data:p2")
	_eq(second.level_label, "1B", "data lane hangs as 1B")
	var orphan := CloseScope.of(snapshot, "ops:p1")
	_eq(
		[orphan.mezzanine, orphan.level_label],
		[true, "5"],
		"a linked worktree without its parent open keeps its number"
	)
	# The repo's own floor down to one pane: the group's parent.
	var parent_raw := _without(_without(raw, "hs:p1"), "hs:p2")
	var parent := CloseScope.of(HerdrSnapshot.from_wire(parent_raw), "hs:p3")
	_eq(
		[parent.last_of_space, parent.mezzanine, parent.group_parent],
		[true, false, true],
		"hs:p3 alone: the group's parent"
	)
	_check(parent.signature() != plain.signature(), "another scope than with its siblings")
	# A second tab: its only pane is the last of the tab, not of the floor.
	var tabbed := raw.duplicate(true)
	_list(tabbed, "tabs").append({"tab_id": "hs:t2", "workspace_id": "hs", "number": 2, "label": "side"})
	_list(tabbed, "panes").append(
		{
			"pane_id": "hs:p4",
			"terminal_id": "term-hs-4",
			"workspace_id": "hs",
			"tab_id": "hs:t2",
			"cwd": "/home/tester/herdstead"
		}
	)
	var tab := CloseScope.of(HerdrSnapshot.from_wire(tabbed), "hs:p4")
	_eq(
		[tab.last_of_tab, tab.last_of_space, tab.kind(), tab.tab_id],
		[true, false, "tab", "hs:t2"],
		"the last pane of a tab"
	)
	# A launch, and a launch already blocked.
	var launching := _changed(raw, "hs:p3", {"agent": null})
	_list(launching, "agents").append(
		{
			"pane_id": "hs:p3",
			"terminal_id": "term-hs-3",
			"name": "claude-2",
			"launch_pending": true,
			"agent_status": "unknown"
		}
	)
	var starting := CloseScope.of(HerdrSnapshot.from_wire(launching), "hs:p3")
	_eq(
		[starting.state, starting.agent, starting.who()],
		["starting", "", "CLAUDE-2"],
		"a launch not recognised yet: starting, by herdr's name"
	)
	_eq(LaunchBlock.close_note(starting), "Kills CLAUDE-2's launch.", "closing it kills the launch")
	_eq(LaunchBlock.close_line(starting, "hs:p3"), "Closes CLAUDE-2's pane hs:p3.", "the line names it")
	var asked := _changed(launching, "hs:p3", {"agent": "claude", "agent_status": "blocked"})
	_eq(CloseScope.of(HerdrSnapshot.from_wire(asked), "hs:p3").state, "blocked", "blocked comes before starting")
	var recognised := _changed(launching, "hs:p3", {"agent": "claude", "agent_status": "unknown"})
	var recognised_scope := CloseScope.of(HerdrSnapshot.from_wire(recognised), "hs:p3")
	_eq(
		[recognised_scope.state, recognised_scope.who()],
		["starting", "CLAUDE"],
		"a recognised launch: starting, by its kind"
	)
	var swapped := CloseScope.of(HerdrSnapshot.from_wire(_changed(raw, "hs:p3", {"terminal_id": "term-hs-9"})), "hs:p3")
	_check(swapped.signature() != plain.signature(), "another terminal under the same id: another scope")
	var muted := CloseScope.of(HerdrSnapshot.from_wire(_changed(raw, "hs:p2", {"agent_status": "unknown"})), "hs:p2")
	_eq(
		[muted.state, LaunchBlock.close_note(muted)],
		["unknown", "Kills CODEX, state unknown."],
		"an agent in no known state is killed too"
	)
	_check(CloseScope.of(snapshot, "nowhere:p9").missing, "a pane not listed is missing")
	_check(CloseScope.of(null, "hs:p1").missing, "and so is every pane of no snapshot")


## The boundary itself: a close carries `pane_id` alone, is refused for the
## group's parent and for a scope that changed since it was aimed, and its
## audit keeps the scope's kind and the state word, never more.
func test_the_boundary_sends_pane_id_only_and_refuses_a_changed_scope() -> void:
	_fakes("snapshot_worktrees", ["pane.close"])
	var facts := _facts(args["socket-a"], _raw("snapshot_worktrees"))
	var commands := _boundary()
	var aimed := _aim(facts, "hs:p3").closing(CloseScope.of(facts.snapshot, "hs:p3"))
	_eq(HerdrCommands.refusal(aimed, facts), CommandRefusal.Reason.NONE, "a plain close may go")
	var busy := _aim(facts, "hs:p2").closing(CloseScope.of(facts.snapshot, "hs:p2"))
	_eq(HerdrCommands.refusal(busy, facts), CommandRefusal.Reason.NONE, "the idle codex may go")
	var moved := HerdrSnapshot.from_wire(_changed(_raw("snapshot_worktrees"), "hs:p2", {"agent_status": "working"}))
	var later := _facts(args["socket-a"], _raw("snapshot_worktrees"))
	later.snapshot = moved
	_eq(HerdrCommands.refusal(busy, later), CommandRefusal.Reason.SCOPE_CHANGED, "working since: refused")
	var replaced := HerdrSnapshot.from_wire(
		_changed(_raw("snapshot_worktrees"), "hs:p3", {"agent": "codex", "agent_status": "working"})
	)
	later.snapshot = replaced
	_eq(HerdrCommands.refusal(aimed, later), CommandRefusal.Reason.IDENTITY_CHANGED, "an agent in the shell since")
	var parent := _facts(args["socket-a"], _without(_without(_raw("snapshot_worktrees"), "hs:p1"), "hs:p2"))
	var alone := _aim(parent, "hs:p3").closing(CloseScope.of(parent.snapshot, "hs:p3"))
	_eq(HerdrCommands.refusal(alone, parent), CommandRefusal.Reason.GROUP_PARENT, "the group's parent: never")
	_eq(
		HerdrCommands.refusal(_aim(facts, "hs:p3").closing(null), facts),
		CommandRefusal.Reason.SCOPE_CHANGED,
		"no scope"
	)
	var ticket := commands.submit(aimed, facts)
	_settle(commands, ticket, "the close")
	_eq(ticket.state, CommandTicket.State.ACCEPTED, "herdr took it")
	_eq(_asked("control-a", "pane.close"), [{"pane_id": "hs:p3"}], "pane_id, and nothing else")
	var entry: CommandAuditEntry = commands.write_log().back()
	_eq(
		[entry.method, entry.scope, entry.summary],
		["pane.close", "pane", "pane.close hs:p3 pane shell"],
		"audited by scope and state"
	)
	_check(not "/home" in _entry_text(entry) and not "hud lane" in _entry_text(entry), "no path, no label")
	var refused := commands.submit(alone, parent)
	_eq(
		[refused.state, refused.refusal],
		[CommandTicket.State.REFUSED, CommandRefusal.Reason.GROUP_PARENT],
		"refused before any socket"
	)
	_eq(_count("control-a", "pane.close"), 1, "one close reached the fake")
	commands.free()


# --- the card ------------------------------------------------------------------------


## Two real clicks close a shell: the first arms the confirm and sends nothing
## (`Closes alpha:p2 (shell).`, the button `Close · click again`), the second
## sends one `pane.close {pane_id}` and the footer says `Closed alpha:p2`
## while the held snapshot keeps the pane; once it comes, the seat is gone,
## NEWS says the pane closed, and the card moved on to another pane with a
## clean footer. Then an idle agent, two clicks: the same request, and the
## worker walks out as a ghost.
func test_two_clicks_close_a_shell_and_an_idle_agent_walks_out() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	_eq(closer.text, "Close", "the button, plain")
	_check(
		"Only by click" in closer.tooltip_text and not "pane.close" in closer.tooltip_text,
		"the tooltip: " + closer.tooltip_text
	)
	await _click_control(closer)
	await _frames(2)
	_eq(_line(office), "Closes alpha:p2 (shell).", "the first click says what closes")
	_eq(_note(office), "Click Close again within 10 s; anything else cancels.", "and asks for the second")
	_eq(closer.text, "Close · click again", "the button asks too")
	_eq(_writes_seen("control-a"), PackedStringArray(), "and sent nothing")
	# The footer says `Closed` from the frame the answer lands in until the
	# snapshot it asks for shows the pane gone (as herdr's does, measured).
	await _click_control(closer)
	await _until(func() -> bool: return card.outcome_text() == "Closed alpha:p2", "the footer: closed")
	_eq(_writes_seen("control-a"), PackedStringArray(["pane.close alpha:p2"]), "one close, no re-read")
	_eq(_asked("control-a", "pane.close"), [{"pane_id": "alpha:p2"}], "pane_id, and nothing else")
	_eq(_last_write(office), "ACCEPTED", "accepted")
	_check(
		closer.disabled and not _control(office, "LaunchScreen").is_visible_in_tree(), "spent: no confirm, no button"
	)
	await _until(func() -> bool: return office.frame.pane(p2) == null, "the next snapshot shows it gone")
	await _frames(3)
	_eq(office.floor_view.seat(p2), null, "the seat is gone")
	# Missing from one snapshot is not gone for the log; from a second, it is:
	# the next poll, five seconds on. A repeated snapshot refreshes no office,
	# so NEWS says it at the next change: a status event here.
	var gone := func() -> bool:
		for event in office.fleet.state_log().events():
			if event.kind == StateLog.Kind.GONE and event.pane_key == p2:
				return true
		return false
	var deadline := Time.get_ticks_msec() + 15000
	while not gone.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var went: bool = gone.call()
	_check(went, "the log says the pane went")
	_ctl("control-a", "status", {"pane_id": "alpha:p1", "agent_status": "idle"})
	var told := func() -> bool:
		for text in office.hud.news.item_texts():
			if "SHELL alpha lab pane closed" in text:
				return true
		return false
	await _until(told, "NEWS says the shell's pane closed: %s" % [office.hud.news.item_texts()])
	_check(office.navigator.active_key != p2, "the card moved on")
	_check(not card.outcome_text().begins_with("Closed"), "with a footer of its own: " + card.outcome_text())
	_eq(_writes_seen("control-b"), PackedStringArray(), "bee heard nothing")
	await _pick_local(office, "alpha:p3")
	await _until(
		func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "the idle codex: Close offered"
	)
	var body := _station_of(office, p3).actor()
	_check(body != null, "a worker sits there")
	await _click_control(closer)
	await _frames(2)
	_eq(_line(office), "Closes CODEX's pane alpha:p3.", "an agent's pane")
	await _click_control(closer)
	await _until(func() -> bool: return _count("control-a", "pane.close") == 2, "the second close")
	_eq(_asked("control-a", "pane.close")[1], {"pane_id": "alpha:p3"}, "its id")
	await _until(func() -> bool: return office.frame.pane(p3) == null, "gone from the snapshot")
	await _frames(3)
	var ghosts := office.floor_view.presentation.ghosts()
	_check(ghosts.size() == 1 and ghosts[0] == body, "the same worker walks out as a ghost")
	_eq(_list(_ctl("control-a", "stats"), "closes").size(), 2, "the fake closed both")


## One click sends nothing, and ten seconds later still nothing: the confirm
## lapsed (the line went, the button reads Close again), and the next click
## only arms it again.
func test_one_click_sends_nothing_and_the_confirm_lapses() -> void:
	var office := await _shell_local()
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_check(_control(office, "LaunchScreen").is_visible_in_tree(), "armed: the line shows")
	_check(not _space_button(office).is_visible_in_tree(), "the other rows step aside")
	await _wait(1.0)
	_eq(_writes_seen("control-a"), PackedStringArray(), "one click sent nothing")
	await _wait(9.8)
	await _until(func() -> bool: return closer.text == "Close", "ten seconds: the confirm lapsed")
	_check(not _control(office, "LaunchScreen").is_visible_in_tree(), "the line went")
	_check(_space_button(office).is_visible_in_tree(), "the other rows are back")
	await _click_control(closer)
	await _frames(2)
	_eq(closer.text, "Close · click again", "a click now only arms again")
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## The line names what goes with the pane, exactly, and the fake cascades as
## herdr does: the last pane of a tab takes its table, the last pane of a
## floor takes the floor, the last pane of a mezzanine takes the mezzanine
## and says the checkout stays; a blocked agent's close says it kills it.
func test_the_line_names_the_table_floor_or_mezzanine_and_they_go() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "pane.close"])
	var tabbed := _raw("snapshot_worktrees")
	_list(tabbed, "tabs").append(
		{"tab_id": "hs:t2", "workspace_id": "hs", "number": 2, "label": "side", "pane_count": 1}
	)
	(
		_list(tabbed, "panes")
		. append(
			{
				"pane_id": "hs:p4",
				"terminal_id": "term-hs-4",
				"workspace_id": "hs",
				"tab_id": "hs:t2",
				"cwd": "/home/tester/herdstead",
				"foreground_cwd": "/home/tester/herdstead",
				"agent_status": "unknown",
			}
		)
	)
	_list(tabbed, "layouts").append(
		{"tab_id": "hs:t2", "panes": [{"pane_id": "hs:p4", "rect": {"x": 0, "y": 0, "width": 200, "height": 50}}]}
	)
	_ctl("control-a", "set_snapshot", {"snapshot": tabbed})
	_ctl("control-b", "set_snapshot", {"snapshot": tabbed})
	var office := await _office_with(false, false)
	var card := _card(office)
	var closer := _close_button(office)
	var hs := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hs")
	var p4 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hs:p4")
	await _floor_pick(office, hs)
	await _click_visible_pane(office, p4)
	await _open_panel(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "hs:p4: Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(_line(office), "Closes hs:p4 (shell) and its tab hs:t2 (last pane of the tab).", "the last pane of a tab")
	await _click_control(closer)
	await _until(func() -> bool: return office.frame.pane(p4) == null, "closed")
	await _until(
		func() -> bool: return office.frame.find_zone(hs) != null and _tables_of(office, hs) == 1, "its table went"
	)
	# The last pane of a plain floor.
	var notes := HerdrFleet.pane_key(HerdrFleet.LOCAL, "notes")
	var notes_p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "notes:p1")
	await _floor_pick(office, notes)
	await _click_visible_pane(office, notes_p1)
	await _open_panel(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "notes:p1: Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(
		_line(office),
		'Closes notes:p1 (shell) and space 4 "notes" (last pane of the space).',
		"the last pane of a floor"
	)
	await _click_control(closer)
	await _until(func() -> bool: return office.frame.find_zone(notes) == null, "the floor went")
	# The last pane of a mezzanine, its agent blocked: heavier words.
	var hud := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hud")
	var hud_p1 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hud:p1")
	await _floor_pick(office, hud)
	await _click_visible_pane(office, hud_p1)
	await _open_panel(office)
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "hud:p1: Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(
		_line(office),
		'Closes CLAUDE\'s pane hud:p1 and mezzanine 1A "hud lane". The checkout stays on disk.',
		"the last pane of a mezzanine"
	)
	_eq(_note(office), "Kills CLAUDE mid-question.", "a blocked agent dies with its question")
	_eq(closer.text, "Close · kills", "the button says so")
	await _click_control(closer)
	await _until(func() -> bool: return office.frame.find_zone(hud) == null, "the mezzanine went")
	_eq(
		_writes_seen("control-a"),
		PackedStringArray(["pane.close hs:p4", "pane.close notes:p1", "pane.close hud:p1"]),
		"three closes"
	)
	var closes := _list(_ctl("control-a", "stats"), "closes")
	var cascade := func(record: Dictionary) -> Array: return [record.get("last_of_tab"), record.get("last_of_space")]
	_eq(closes.map(cascade), [[true, false], [true, true], [true, true]], "as the fake cascaded")
	_check(office.frame.find_zone(hs) != null, "the repo's own floor stays")


## The last pane of the repo's own floor while its mezzanines are open is
## never closed from here: the button is off with the reason, and two clicks
## on it send nothing; herdr's own confirm is never reached.
func test_the_repos_own_floor_with_mezzanines_open_never_closes() -> void:
	_fakes("snapshot_worktrees", ["pane.read", "pane.close"])
	var alone := _without(_without(_raw("snapshot_worktrees"), "hs:p1"), "hs:p2")
	_ctl("control-a", "set_snapshot", {"snapshot": alone})
	var office := await _office_with(false, false)
	var closer := _close_button(office)
	var hs_p3 := HerdrFleet.pane_key(HerdrFleet.LOCAL, "hs:p3")
	await _floor_pick(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, "hs"))
	await _click_visible_pane(office, hs_p3)
	await _open_panel(office)
	await _until(closer.is_visible_in_tree, "the manage rows")
	await _frames(3)
	_check(closer.disabled, "Close is off")
	_check(
		"mezzanines" in closer.tooltip_text and "space 1" in closer.tooltip_text,
		"the tooltip says why: " + closer.tooltip_text
	)
	await _click_control(closer)
	await _click_control(closer)
	await _wait(0.5)
	_eq(_writes_seen("control-a"), PackedStringArray(), "two clicks sent nothing")
	_check(
		_space_button(office).is_visible_in_tree() and not _space_button(office).disabled, "New space is still on there"
	)


## A working agent's close says it kills it, and a blocked one's that its
## question goes unanswered; both still take two clicks, and the second sends.
func test_a_working_or_blocked_agent_is_said_to_be_killed() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var closer := _close_button(office)
	await _pick_local(office, "alpha:p1")
	await _until(
		func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "the working claude: Close offered"
	)
	await _click_control(closer)
	await _frames(2)
	_eq(_note(office), "Kills CLAUDE, still working.", "the heavier note")
	var heavy: Label = _control(office, "LaunchNote")
	_check("without asking it" in heavy.tooltip_text, "the whole sentence in its tooltip: " + heavy.tooltip_text)
	_eq(_line(office), "Closes CLAUDE's pane alpha:p1.", "the line")
	_eq(closer.text, "Close · kills", "the button")
	_eq(_writes_seen("control-a"), PackedStringArray(), "one click sent nothing")
	await _click_control(closer)
	await _until(func() -> bool: return _count("control-a", "pane.close") == 1, "the second click sends")
	_eq(_asked("control-a", "pane.close"), [{"pane_id": "alpha:p1"}], "")
	await _pick_bee_bravo(office)
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(
		func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "bee's blocked pi: Close offered"
	)
	await _click_control(closer)
	await _frames(2)
	_eq(_note(office), "Kills PI mid-question.", "a blocked agent")
	_eq(
		_line(office),
		'Closes PI\'s pane bravo:p1 and space 2 "bravo desk" (last pane of the space).',
		"alone on its floor"
	)
	await _click_control(closer)
	await _until(func() -> bool: return _count("control-b", "pane.close") == 1, "sent to bee")
	_eq(_asked("control-b", "pane.close"), [{"pane_id": "bravo:p1"}], "bee's pane id")
	_eq(_count("control-a", "pane.close"), 1, "Local heard no second close")


## What changes between the two clicks cancels the confirm: the agent's state
## moving, or a pane joining the tab (the last pane of a floor is no longer
## the last). The words are redrawn, and nothing is sent.
func test_a_scope_change_between_the_clicks_cancels_the_confirm() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var closer := _close_button(office)
	await _pick_local(office, "alpha:p3")
	await _until(
		func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "the idle codex: Close offered"
	)
	await _click_control(closer)
	await _frames(2)
	_eq(closer.text, "Close · click again", "armed")
	_ctl("control-a", "status", {"pane_id": "alpha:p3", "agent_status": "working"})
	await _until(func() -> bool: return closer.text == "Close", "its state moved: the confirm went")
	_check(not _control(office, "LaunchScreen").is_visible_in_tree(), "and the line")
	await _click_control(closer)
	await _frames(2)
	_eq(_note(office), "Kills CODEX, still working.", "a click arms again, with the new words")
	await _wait(0.5)
	_eq(_writes_seen("control-a"), PackedStringArray(), "nothing was sent")
	await _pick_bee_bravo(office)
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "bee's pi: Close offered")
	await _click_control(closer)
	await _frames(2)
	_check("last pane of the space" in _line(office), "alone on its floor: " + _line(office))
	var joined := _raw()
	(
		_list(joined, "panes")
		. append(
			{
				"pane_id": "bravo:p2",
				"terminal_id": "term-bravo-2",
				"workspace_id": "bravo",
				"tab_id": "bravo:t1",
				"cwd": "/home/tester/bravo",
				"foreground_cwd": "/home/tester/bravo",
				"agent_status": "unknown",
			}
		)
	)
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(joined, "bravo:p1", {"agent_status": "blocked"})})
	_ctl("control-b", "emit", {"fixture_event": "pane_updated"})
	await _until(func() -> bool: return closer.text == "Close", "a pane joined: the confirm went")
	await _click_control(closer)
	await _frames(2)
	_eq(_line(office), "Closes PI's pane bravo:p1.", "armed again: no longer the last")
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## A close aimed at one pane is not sent to another: the pick moves between
## press and release, or the machine drops. Nothing is sent, and the footer says so.
func test_a_close_is_refused_when_the_pick_or_machine_changes_before_the_release() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(closer.text, "Close · click again", "armed")
	_half_click(closer, true)
	await _frames(2)
	await _tap(KEY_N)
	await _until(func() -> bool: return office.picked_key != p2, "N picks the next agent")
	await _until(func() -> bool: return card.answering() or closer.is_visible_in_tree(), "its panel open")
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(closer.is_visible_in_tree, "whose card offers Close too")
	_half_click(closer, false)
	await _frames(3)
	_eq(card.outcome_text(), "Not sent: target changed", "released on another pane: not sent")
	_eq(closer.text, "Close", "and the other pane's confirm is not armed")
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "back: offered")
	await _click_control(closer)
	await _frames(2)
	_half_click(closer, true)
	await _frames(2)
	_ctl("control-a", "vanish")
	await _until(func() -> bool: return office.fleet.is_stale(HerdrFleet.LOCAL), "Local drops")
	await _until(func() -> bool: return not _control(office, "Launch").is_visible_in_tree(), "the block goes with it")
	_half_click(closer, false)
	await _frames(5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## A close herdr carried out but whose answer was lost: the footer says the
## next snapshot decides, and it does (the pane goes); no second close, ever.
func test_a_lost_close_answer_is_judged_by_the_next_snapshot_only() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_ctl("control-a", "next", {"action": "execute_then_drop", "method": "pane.close"})
	await _click_control(closer)
	await _until(
		func() -> bool:
			return (
				card.outcome_text() == "Close: no answer from herdr. The next snapshot shows whether alpha:p2 closed."
			),
		"the footer: no answer"
	)
	_eq(_last_write(office), "UNKNOWN", "unknown")
	await _until(func() -> bool: return office.frame.pane(p2) == null, "the next snapshot shows it gone")
	await _wait(1.0)
	_eq(_count("control-a", "pane.close"), 1, "never closed again")
	_eq(_list(_ctl("control-a", "stats"), "closes").size(), 1, "the fake closed it once")


## herdr's own refusals are said in its words and never retried: a close it
## wants its own confirm for, and a stale id it does not know.
func test_herdrs_refusals_are_said_and_never_retried() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_ctl(
		"control-a",
		"next",
		{
			"action": "refuse",
			"method": "pane.close",
			"code": "confirmation_required",
			"message": "closing this pane would close a worktree group",
		}
	)
	await _click_control(closer)
	await _until(func() -> bool: return card.outcome_text() == "herdr refused: needs herdr's own confirm", "said")
	var outcome: Label = card.get_node("%Outcome")
	_check("worktree group" in outcome.tooltip_text, "herdr's words in the tooltip: " + outcome.tooltip_text)
	_check(closer.disabled, "a look owed: off")
	await _until(func() -> bool: return not closer.disabled, "looked at: offered again")
	await _click_control(closer)
	await _frames(2)
	_ctl(
		"control-a",
		"next",
		{"action": "refuse", "method": "pane.close", "code": "pane_not_found", "message": "pane alpha:p2 not found"}
	)
	await _click_control(closer)
	await _until(func() -> bool: return card.outcome_text() == "herdr refused: pane gone", "a stale id")
	_check("pane alpha:p2 not found" in outcome.tooltip_text, "echoed in the tooltip: " + outcome.tooltip_text)
	await _wait(1.0)
	_eq(_count("control-a", "pane.close"), 2, "two clicks' worth, nothing retried")
	_eq(office.frame.pane(p2) != null, true, "the pane is still there")


## Every key the card knows, over an armed Close: nothing closes. Delete and
## Backspace too; the buttons take no focus.
func test_the_keyboard_never_closes() -> void:
	var office := await _shell_local()
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(closer.text, "Close · click again", "armed")
	_eq(closer.focus_mode, Control.FOCUS_NONE, "the button takes no focus")
	for code: Key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_DELETE, KEY_BACKSPACE, KEY_1, KEY_Y, KEY_TAB]:
		await _tap(code)
	await _hold(KEY_ENTER, 5)
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "no key closed anything")


## Zero gestures, zero writes: an armed confirm through status changes
## elsewhere, events, a new screen, a resize and seconds.
func test_nothing_closes_without_a_gesture() -> void:
	var office := await _shell_local()
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	for index in 20:
		_ctl("control-a", "status", {"pane_id": "alpha:p1", "agent_status": "idle" if index % 2 == 0 else "working"})
		_ctl("control-a", "emit", {"fixture_event": "pane_updated"})
		await _frames(2)
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": "$ ls\n$ \n"})
	for screen: Vector2 in [Vector2(640, 400), Vector2(800, 480)]:
		office.test_screen = screen
		office.refresh()
		await _frames(3)
	await _wait(3.0)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing written")


## The confirm goes with the block: answer mode (Enter on an idle agent), the
## panel folding to its line, and back. After either the button reads Close
## again and one click sends nothing.
func test_answer_mode_and_folding_cancel_the_confirm() -> void:
	_fakes()
	var office := await _office_with()
	var card := _card(office)
	var closer := _close_button(office)
	await _pick_local(office, "alpha:p3")
	await _until(
		func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "the idle codex: Close offered"
	)
	await _click_control(closer)
	await _frames(2)
	_eq(closer.text, "Close · click again", "armed")
	await _tap(KEY_ENTER)
	await _until(card.answering, "Enter: answer mode")
	_check(not closer.is_visible_in_tree(), "the block is hidden")
	await _tap(KEY_ESCAPE)
	await _until(
		func() -> bool: return not card.answering() and closer.is_visible_in_tree(), "Escape: the block is back"
	)
	await _frames(2)
	_eq(closer.text, "Close", "the confirm went with the block")
	await _click_control(closer)
	await _wait(0.5)
	_eq(_writes_seen("control-a"), PackedStringArray(), "one click sends nothing")
	_eq(closer.text, "Close · click again", "it only armed again")
	await _tap(KEY_ESCAPE)
	await _until(office.hud.card_compact, "Escape again folds the panel")
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return not office.hud.card_compact(), "opened again")
	# Enter on a picked idle agent opens answer mode too: Escape leaves it.
	if card.answering():
		await _tap(KEY_ESCAPE)
	await _until(closer.is_visible_in_tree, "the block is back")
	await _frames(2)
	_eq(closer.text, "Close", "folding cancelled it too")
	await _click_control(closer)
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## One confirm at a time: arming the close drops an armed start confirm, and
## arming a start drops the close's; the note and the line always belong to
## the button armed last. Nothing is sent by either.
func test_arming_one_confirm_clears_the_other() -> void:
	var office := await _shell_local("➜  repo git:(main) ✗\n")
	var card := _card(office)
	var closer := _close_button(office)
	var kind: Button = office.hud.inspector.get_node("%Kind0")
	await _until(
		func() -> bool: return card.preview_text().begins_with("➜") and not kind.disabled, "an unsure prompt shown"
	)
	await _click_control(kind)
	await _frames(2)
	_check(_note(office).begins_with("Start anyway?"), "the start confirm: " + _note(office))
	_eq(_line(office), "➜  repo git:(main) ✗", "its row")
	await _click_control(closer)
	await _frames(2)
	_eq(_note(office), "Click Close again within 10 s; anything else cancels.", "the close confirm took over")
	_eq(_line(office), "Closes alpha:p2 (shell).", "and the line")
	_eq(closer.text, "Close · click again", "armed")
	await _click_control(kind)
	await _frames(2)
	_check(_note(office).begins_with("Start anyway?"), "a kind click arms the start again: " + _note(office))
	_eq(closer.text, "Close", "and the close confirm went")
	await _click_control(closer)
	await _frames(2)
	_eq(_line(office), "Closes alpha:p2 (shell).", "a click on Close only arms it again")
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## The ten seconds are checked at the release too: a press taken before the
## deadline and released after it sends nothing, and the footer says so.
func test_a_press_held_across_the_deadline_sends_nothing() -> void:
	var office := await _shell_local()
	var card := _card(office)
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(closer.text, "Close · click again", "armed")
	await _wait(9.4)
	_half_click(closer, true)
	await _frames(2)
	await _wait(1.2)
	_half_click(closer, false)
	await _frames(3)
	_eq(card.outcome_text(), "Not sent: click again to close", "released after the deadline: not sent")
	_eq(closer.text, "Close", "the confirm lapsed")
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "nothing was sent")


## An agent herdr reports in no known state is killed like a working one:
## the heavier note and button.
func test_an_agent_in_an_unknown_state_is_said_to_be_killed() -> void:
	_fakes()
	_ctl("control-a", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "unknown"})})
	var office := await _office_with()
	var closer := _close_button(office)
	await _pick_local(office, "alpha:p3")
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	await _click_control(closer)
	await _frames(2)
	_eq(_note(office), "Kills CODEX, state unknown.", "the heavier note")
	_eq(closer.text, "Close · kills", "the button")
	await _wait(0.5)
	_eq(_writes_seen("control-a"), PackedStringArray(), "one click sent nothing")


## A double-click on Close is one click: its second press is taken as none,
## nothing is sent, and the confirm it armed waits for a real second click.
func test_a_double_click_is_one_click() -> void:
	var office := await _shell_local()
	var closer := _close_button(office)
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	_half_click(closer, true)
	await process_frame
	_half_click(closer, false)
	await process_frame
	_half_click(closer, true, true)
	await process_frame
	_half_click(closer, false)
	await _frames(3)
	await _wait(0.5)
	_eq(_writes_seen("control-a") + _writes_seen("control-b"), PackedStringArray(), "a double-click sent nothing")
	_eq(closer.text, "Close · click again", "armed by its first press only")
	await _click_control(closer)
	await _until(func() -> bool: return _count("control-a", "pane.close") == 1, "the real second click sends")
	await _wait(0.5)
	_eq(_count("control-a", "pane.close"), 1, "once")


## A shell herdr is still launching an agent in neither starts nor splits:
## the block shows the manage rows alone (THIS PANE), and Close kills the
## launch, by the name herdr gave it, in two clicks.
func test_a_launching_pane_shows_the_manage_rows_alone_and_closes() -> void:
	_fakes()
	var launching := _raw()
	(
		_list(launching, "agents")
		. append(
			{
				"pane_id": "alpha:p2",
				"terminal_id": "term-alpha-2",
				"workspace_id": "alpha",
				"tab_id": "alpha:t1",
				"name": "claude-2",
				"launch_pending": true,
				"agent_status": "unknown",
			}
		)
	)
	_ctl("control-a", "set_snapshot", {"snapshot": launching})
	var office := await _office_with()
	var closer := _close_button(office)
	await _pick_local(office, "alpha:p2")
	await _until(func() -> bool: return closer.is_visible_in_tree() and not closer.disabled, "Close offered")
	_eq((_control(office, "LaunchTitle") as Label).text, "THIS PANE", "the manage rows alone")
	_check(not _control(office, "Kind0").is_visible_in_tree(), "no kind")
	_check(not _control(office, "SplitButton").is_visible_in_tree(), "no split")
	await _click_control(closer)
	await _frames(2)
	_eq(_note(office), "Kills CLAUDE-2's launch.", "closing kills the launch")
	_eq(_line(office), "Closes CLAUDE-2's pane alpha:p2.", "by herdr's name")
	_eq(closer.text, "Close · kills", "the button")
	await _click_control(closer)
	await _until(func() -> bool: return _count("control-a", "pane.close") == 1, "the second click sends")
	_eq(_asked("control-a", "pane.close"), [{"pane_id": "alpha:p2"}], "")


## A `--read-only` office offers no manage rows, and a click where Close would
## be, Enter and the digits ask nothing but the read-only three.
func test_read_only_hides_the_rows_and_writes_nothing() -> void:
	_fakes("snapshot_basic", [])
	var office := await _office_with(true)
	await _pick_local(office, "alpha:p2")
	await _frames(10)
	_check(not _control(office, "Launch").is_visible_in_tree(), "no block")
	_check(not _close_button(office).is_visible_in_tree(), "no Close")
	_check(not _control(office, "BranchBox").is_visible_in_tree(), "no branch box")
	await _tap(KEY_ENTER)
	await _tap(KEY_1)
	await _frames(3)
	for which: String in ["control-a", "control-b"]:
		_eq(_sequence(which), PackedStringArray(), "%s: nothing beyond the read-only three" % which)


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in OPERABLE, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)


# --- helpers only these cases use ------------------------------------------------


func _close_button(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%CloseButton")


## Show bee's bravo floor, pick its blocked pi (bravo:p1) with a real click,
## open the panel with Enter (answer mode, for a blocked agent) and leave
## answer mode with Escape: the block shows.
func _pick_bee_bravo(office: OfficeDouble) -> void:
	await _floor_pick(office, HerdrFleet.pane_key(BEE, "bravo"))
	await _click_visible_pane(office, bee_p1)
	await _open_panel(office)
	if _card(office).answering():
		await _tap(KEY_ESCAPE)


func _space_button(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%SpaceButton")


## The block's note and the confirm's terminal row.
func _note(office: OfficeDouble) -> String:
	return (_control(office, "LaunchNote") as Label).text


func _line(office: OfficeDouble) -> String:
	var line: Label = _control(office, "LaunchLine")
	return line.text if line.is_visible_in_tree() else ""


## How many tables the frame lays on floor `floor_key`.
func _tables_of(office: OfficeDouble, floor_key: String) -> int:
	var found := office.frame.find_zone(floor_key)
	return 0 if found == null else found.zone_model.rooms.size()
