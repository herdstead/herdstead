extends "res://tools/test_base.gd"
## PickFollowsWrite as pure functions: where the viewer's pick goes after a
## start, a split, a new space or a worktree the office sent, decided from
## frames made straight from the fixture snapshot, launches and tickets built
## by hand, and clock values written out. Two tables, kept apart: the start
## (started()) and the new pane waited for (new_pane_made(), new_pane(),
## overdue()). No office, no scene, no herdr, no clock. Run through run_tests.sh.
##
## godot --headless --path . --script tools/test_pick_follows_write.gd

const LOCAL := HerdrFleet.LOCAL
const BEE := "socket:bee"
## When every wait in this suite is queued, how long it lasts, and so when it
## runs out: the module is handed these numbers and no clock.
const MADE_MSEC := 1000
const WAIT_MSEC := 10000
const UNTIL_MSEC := 11000
## The connection and the navigation revision every wait here is queued on.
const GENERATION := 2
const NAV := 5

## tools/fixtures/snapshot_basic.json, which Local serves, and bee too where a
## case wants pane ids that collide: alpha:p2 a shell on term-alpha-2,
## alpha:p3 an idle codex.
var basic: Dictionary = {}


func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_basic.json"))
	if parsed is Dictionary:
		var file: Dictionary = parsed
		basic = _dict(file, "snapshot")
	if basic.is_empty():
		print("TEST_HARNESS_ERROR: cannot read the office fixtures")
		quit(2)
		return
	run_cases()


func _marker() -> String:
	return "PICK FOLLOWS WRITE TESTS"


# --- frames -------------------------------------------------------------------


## Local serving `local`, and bee serving `bee` when there is one.
func _frame(local: Dictionary, bee: Dictionary = {}) -> OfficeFrame:
	var machines: Array[MachineView] = [MachineView.new(LOCAL, "Local", HerdrSnapshot.from_wire(local), false)]
	if not bee.is_empty():
		machines.append(MachineView.new(BEE, "bee", HerdrSnapshot.from_wire(bee), false))
	return OfficeProjection.frame(machines, PackedStringArray(["working", "blocked", "done", "idle", "unknown"]))


func _local(id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, id)


func _bee(id: String) -> String:
	return HerdrFleet.pane_key(BEE, id)


## The fixture with alpha:p2 as a start leaves it: an agent of kind `agent`
## there (a shell with none), listed under `name` (not listed with none), in
## session `session` (none yet when empty), on terminal `terminal`.
func _p2(agent := "", name := "", session := "", terminal := "term-alpha-2") -> Dictionary:
	var raw: Dictionary = basic.duplicate(true)
	for pane: Dictionary in _list(raw, "panes"):
		if pane.get("pane_id") != "alpha:p2":
			continue
		pane["terminal_id"] = terminal
		if not agent.is_empty():
			pane["agent"] = agent
			pane["agent_status"] = "idle"
		if not session.is_empty():
			pane["agent_session"] = {"source": "fixture", "agent": agent, "kind": "session_id", "value": session}
	if not name.is_empty():
		var agents := _list(raw, "agents")
		(
			agents
			. append(
				{
					"terminal_id": terminal,
					"pane_id": "alpha:p2",
					"workspace_id": "alpha",
					"tab_id": "alpha:t1",
					"agent": agent,
					"name": name,
				}
			)
		)
		raw["agents"] = agents
	return raw


## Local's alpha:p2 as `raw` shows it.
func _pane(raw: Dictionary) -> PaneModel:
	return _frame(raw).pane(_local("alpha:p2"))


## The fixture with one more shell `pane_id` on terminal `terminal`, in
## workspace `workspace`: the pane a split, a new space or a worktree made.
func _grown(pane_id := "alpha:p4", terminal := "term-alpha-4", workspace := "alpha") -> Dictionary:
	var raw: Dictionary = basic.duplicate(true)
	var panes := _list(raw, "panes")
	var tab := "alpha:t1" if workspace == "alpha" else "bravo:t1"
	(
		panes
		. append(
			{
				"pane_id": pane_id,
				"terminal_id": terminal,
				"workspace_id": workspace,
				"tab_id": tab,
				"focused": false,
				"cwd": "/home/tester/alpha",
				"agent_status": "unknown",
				"revision": 1,
			}
		)
	)
	raw["panes"] = panes
	return raw


# --- the facts ----------------------------------------------------------------


## A start this run sent to the shell `shell`: of kind `kind`, named `name`,
## its ticket in `state` (ACCEPTED, or UNKNOWN for an answer that was lost).
func _start(
	shell: PaneModel, kind := "claude", name := "claude-1", state := CommandTicket.State.ACCEPTED
) -> LaunchWatch:
	var context := CommandContext.aimed(
		shell.machine(), GENERATION, shell.key, shell.pane_id, shell.pane_id, shell.identity_key(), 1, shell.terminal_id
	)
	var watch := LaunchWatch.new()
	watch.pane_key = shell.key
	watch.machine = shell.machine()
	watch.name = name
	watch.kind = kind
	watch.terminal_id = shell.terminal_id
	watch.ticket = CommandTicket.new(context.starting(kind, name, null))
	watch.ticket.state = state
	return watch


## started() about `pane`, the desk the viewer picked when it was
## `picked_identity`, with `watch` still the pane's last write.
func _carry(
	memory: PickFollowsWrite.Memory, pane: PaneModel, picked_identity: String, watch: LaunchWatch
) -> PickFollowsWrite.Answer:
	return PickFollowsWrite.started(memory, pane, pane.key, picked_identity, watch, watch.ticket)


## A memory that waits for `pane_id` (terminal `terminal`), made from pane
## `from_key` at MADE_MSEC on GENERATION and NAV, for WAIT_MSEC.
func _awaiting(
	from_key: String, pane_id := "alpha:p4", terminal := "term-alpha-4", memory: PickFollowsWrite.Memory = null
) -> PickFollowsWrite.Memory:
	var before := PickFollowsWrite.Memory.new() if memory == null else memory
	return PickFollowsWrite.new_pane_made(before, from_key, pane_id, terminal, GENERATION, NAV, MADE_MSEC, WAIT_MSEC)


## new_pane() just after the write, with the viewer where it left them: the
## pick still alpha:p3 of Local, no navigation, the same connection, out of
## answer mode.
func _seen(memory: PickFollowsWrite.Memory, frame: OfficeFrame, now_msec := MADE_MSEC + 1) -> PickFollowsWrite.Answer:
	return PickFollowsWrite.new_pane(memory, frame, _local("alpha:p3"), NAV, GENERATION, false, now_msec)


func _why(answer: PickFollowsWrite.Answer) -> String:
	return str(PickFollowsWrite.Why.find_key(answer.why))


## The key of the pane `answer` picks; empty when the pick does not change.
func _picked(answer: PickFollowsWrite.Answer) -> String:
	return "" if answer.pane == null else answer.pane.key


## `answer` changes nothing: the pick stays, the card hears nothing, and the
## memory is the very one it was asked with.
func _unchanged(answer: PickFollowsWrite.Answer, memory: PickFollowsWrite.Memory, why: String, message: String) -> void:
	_eq(_why(answer), why, message)
	_check(answer.memory == memory, message + ": the memory it was asked with")
	_check(answer.pane == null, message + ": no pick")
	_eq([answer.left_from, answer.left_pane_id], ["", ""], message + ": nothing for the card")


## `answer` ended the wait for alpha:p4 without picking it: `said` when the
## card hears of it (from alpha:p3 of machine `machine`), and nothing is
## waited for after.
func _ended(answer: PickFollowsWrite.Answer, why: String, said: bool, message: String, machine := LOCAL) -> void:
	_eq(_why(answer), why, message)
	_check(answer.pane == null, message + ": no pick")
	var from := HerdrFleet.pane_key(machine, "alpha:p3") if said else ""
	_eq([answer.left_from, answer.left_pane_id], [from, "alpha:p4" if said else ""], message + ": what the card hears")
	_eq(answer.memory.machine(), "", message + ": nothing waited for after")
	_unchanged(_seen(answer.memory, _frame(_grown())), answer.memory, "NOTHING_AWAITED", message + ", asked again")


# --- the start ----------------------------------------------------------------


## The viewer picked a shell and started an agent there: when herdr detects
## the agent in that terminal the pane is another identity, and the pick goes
## on to it, whether herdr lists the start's name already or not yet.
func test_a_start_carries_the_pick_from_its_shell_to_the_agent() -> void:
	var shell := _pane(_p2())
	_eq([shell.provider, shell.agent_name, shell.session], ["", "", null], "the fixture: a shell")
	var watch := _start(shell)
	var memory := PickFollowsWrite.Memory.new()
	var unnamed := _pane(_p2("claude"))
	_eq([unnamed.provider, unnamed.agent_name, unnamed.session], ["claude", "", null], "the fixture: detected")
	_check(unnamed.identity_key() != shell.identity_key(), "another identity than the shell picked")
	var answer := _carry(memory, unnamed, shell.identity_key(), watch)
	_eq(_why(answer), "STARTED", "detected, not listed yet: carried")
	_check(answer.pane == unnamed, "the pick becomes that pane")
	_eq(answer.identity, unnamed.identity_key(), "as the identity it has now")
	_eq([answer.left_from, answer.left_pane_id], ["", ""], "nothing for the card")
	_check(answer.memory != memory, "and it is remembered")
	var named := _pane(_p2("claude", "claude-1"))
	_eq(named.agent_name, "claude-1", "the fixture: listed under the start's name")
	answer = _carry(memory, named, shell.identity_key(), watch)
	_eq([_why(answer), answer.pane, answer.identity], ["STARTED", named, named.identity_key()], "listed: carried")


## The memory across two refreshes: the agent shows first with no session,
## then with its first one. The pick was carried to the first, so it goes on
## to the second; a refresh that shows the same again changes nothing.
func test_the_pick_follows_into_the_first_session_on_a_later_snapshot() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var first := _carry(PickFollowsWrite.Memory.new(), _pane(_p2("claude", "claude-1")), shell.identity_key(), watch)
	_eq(_why(first), "STARTED", "the first snapshot: the agent, no session yet")
	var in_session := _pane(_p2("claude", "claude-1", "first"))
	_check(in_session.session != null, "the fixture: a session")
	_check(in_session.identity_key() != first.identity, "another identity again")
	var second := _carry(first.memory, in_session, first.identity, watch)
	_eq([_why(second), second.pane, second.identity], ["STARTED", in_session, in_session.identity_key()], "carried on")
	_unchanged(_carry(second.memory, in_session, second.identity, watch), second.memory, "STILL_PICKED", "the same")
	# Without the first answer's memory the second snapshot is nobody's pick.
	var forgotten := _carry(PickFollowsWrite.Memory.new(), in_session, first.identity, watch)
	_eq(_why(forgotten), "NOT_FROM_START", "the memory is what carries it on")


## Not past the first session: once the pick was carried to an agent in its
## session, a later one (`/clear`) is a new identity to pick again.
func test_a_session_after_the_first_is_picked_again() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var first := _carry(PickFollowsWrite.Memory.new(), _pane(_p2("claude", "claude-1")), shell.identity_key(), watch)
	var second := _carry(first.memory, _pane(_p2("claude", "claude-1", "first")), first.identity, watch)
	var cleared := _pane(_p2("claude", "claude-1", "cleared"))
	_unchanged(_carry(second.memory, cleared, second.identity, watch), second.memory, "LATER_SESSION", "/clear")
	# The agent seen first already in its session: carried once, straight from
	# the shell, and that was its first session.
	var direct := _carry(PickFollowsWrite.Memory.new(), _pane(_p2("claude", "", "first")), shell.identity_key(), watch)
	_eq(_why(direct), "STARTED", "seen first with its session: carried from the shell")
	_unchanged(_carry(direct.memory, cleared, direct.identity, watch), direct.memory, "LATER_SESSION", "then /clear")


## "No session yet" is no session at all: an agent that shows with a session
## record that says nothing is in a session, and the one after it is a later one.
func test_an_empty_session_is_a_session() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var empty := _pane(_p2("claude", "claude-1"))
	empty.session = AgentSessionIdentity.new()
	_check(not empty.session.identity_key().is_empty(), "an empty session still has a key")
	var first := _carry(PickFollowsWrite.Memory.new(), empty, shell.identity_key(), watch)
	_eq([_why(first), first.identity], ["STARTED", empty.identity_key()], "carried from the shell")
	var next := _pane(_p2("claude", "claude-1", "first"))
	_unchanged(_carry(first.memory, next, first.identity, watch), first.memory, "LATER_SESSION", "a session after it")


## Only the viewer's own pick is carried: no pane selected, a pane that only
## herdr's focus selects, the pick on another desk (another machine's pane with
## the same id is another desk), or a pane that is the pick still.
func test_nothing_is_carried_to_a_pane_the_viewer_did_not_pick() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var agent := _pane(_p2("claude", "claude-1"))
	var memory := PickFollowsWrite.Memory.new()
	var none := PickFollowsWrite.started(memory, null, shell.key, shell.identity_key(), watch, watch.ticket)
	_unchanged(none, memory, "NOT_PICKED", "no pane selected")
	var focus := PickFollowsWrite.started(memory, agent, "", "", watch, watch.ticket)
	_unchanged(focus, memory, "NOT_PICKED", "nothing picked: herdr's focus selects it")
	var other := PickFollowsWrite.started(memory, agent, _local("alpha:p3"), shell.identity_key(), watch, watch.ticket)
	_unchanged(other, memory, "NOT_PICKED", "the pick is another desk")
	var far := PickFollowsWrite.started(memory, agent, _bee("alpha:p2"), shell.identity_key(), watch, watch.ticket)
	_unchanged(far, memory, "NOT_PICKED", "the pick is bee's alpha:p2, the pane Local's")
	_unchanged(_carry(memory, agent, agent.identity_key(), watch), memory, "STILL_PICKED", "already the pick")
	_unchanged(_carry(memory, shell, shell.identity_key(), watch), memory, "STILL_PICKED", "the shell, not changed yet")


## Only this run's own start, while it is the pane's last write: the very
## ticket, not one like it. A start whose answer was lost is remembered and
## carried the same.
func test_only_this_runs_start_while_it_is_the_last_write() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var agent := _pane(_p2("claude", "claude-1"))
	var memory := PickFollowsWrite.Memory.new()
	var picked := shell.identity_key()
	var none := PickFollowsWrite.started(memory, agent, agent.key, picked, null, null)
	_unchanged(none, memory, "NO_START", "no start sent to the pane")
	var ticketless := LaunchWatch.new()
	ticketless.kind = "claude"
	ticketless.name = "claude-1"
	ticketless.terminal_id = shell.terminal_id
	var bare := PickFollowsWrite.started(memory, agent, agent.key, picked, ticketless, null)
	_unchanged(bare, memory, "NO_START", "a start without its ticket")
	var twin := _start(shell)
	var later := PickFollowsWrite.started(memory, agent, agent.key, picked, watch, twin.ticket)
	_unchanged(later, memory, "WROTE_SINCE", "another ticket is the last write, however alike")
	var nothing := PickFollowsWrite.started(memory, agent, agent.key, picked, watch, null)
	_unchanged(nothing, memory, "WROTE_SINCE", "no last write known")
	var lost := _start(shell, "claude", "claude-1", CommandTicket.State.UNKNOWN)
	_eq(_why(_carry(memory, agent, picked, lost)), "STARTED", "an answer that was lost: carried all the same")


## In the same terminal, of the kind the start named, under its name: the
## shell's own pick takes an agent herdr does not list yet, a pick carried
## here takes only the start's name.
func test_another_terminal_kind_or_name_is_not_carried() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var memory := PickFollowsWrite.Memory.new()
	var picked := shell.identity_key()
	var moved := _pane(_p2("claude", "claude-1", "", "term-someone-else"))
	_unchanged(_carry(memory, moved, picked, watch), memory, "OTHER_TERMINAL", "another terminal in the pane")
	var codex := _pane(_p2("codex", "claude-1"))
	_eq([codex.provider, codex.agent_name], ["codex", "claude-1"], "the fixture: a codex under the start's name")
	_unchanged(_carry(memory, codex, picked, watch), memory, "OTHER_KIND", "another kind")
	var by_hand := _pane(_p2("claude", "claude-9"))
	_unchanged(_carry(memory, by_hand, picked, watch), memory, "OTHER_NAME", "from the shell: another name")
	var first := _carry(memory, _pane(_p2("claude")), picked, watch)
	_eq(_why(first), "STARTED", "from the shell: no name yet is carried")
	var unnamed := _pane(_p2("claude", "", "first"))
	_unchanged(_carry(first.memory, unnamed, first.identity, watch), first.memory, "OTHER_NAME", "carried: no name")
	var renamed := _pane(_p2("claude", "claude-9", "first"))
	_unchanged(_carry(first.memory, renamed, first.identity, watch), first.memory, "OTHER_NAME", "carried: another")
	var named := _pane(_p2("claude", "claude-1", "first"))
	_eq(_why(_carry(first.memory, named, first.identity, watch)), "STARTED", "carried: the start's name goes on")


## A pick that is neither the shell the start was aimed at nor one carried
## here from it stays what it is, whatever was carried before.
func test_a_pick_that_did_not_come_from_the_start_is_not_carried() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var agent := _pane(_p2("claude", "claude-1", "first"))
	var stray := _pane(_p2("pi")).identity_key()
	var memory := PickFollowsWrite.Memory.new()
	_unchanged(_carry(memory, agent, stray, watch), memory, "NOT_FROM_START", "nothing carried yet")
	var first := _carry(memory, _pane(_p2("claude", "claude-1")), shell.identity_key(), watch)
	_unchanged(_carry(first.memory, agent, stray, watch), first.memory, "NOT_FROM_START", "not the one carried")


## When several things are off at once, the answer is the first of: not the
## pick, the pick still, no start, written since, the terminal, the kind, the
## name.
func test_the_start_checks_come_in_one_order() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var twin := _start(shell)
	var memory := PickFollowsWrite.Memory.new()
	var picked := shell.identity_key()
	var off := _pane(_p2("codex", "claude-9", "", "term-someone-else"))
	var answer := PickFollowsWrite.started(memory, off, _local("alpha:p3"), picked, null, twin.ticket)
	_eq(_why(answer), "NOT_PICKED", "not the pick, before all")
	answer = PickFollowsWrite.started(memory, off, off.key, off.identity_key(), null, twin.ticket)
	_eq(_why(answer), "STILL_PICKED", "the pick still, before the start")
	answer = PickFollowsWrite.started(memory, off, off.key, picked, null, twin.ticket)
	_eq(_why(answer), "NO_START", "no start, before the last write")
	answer = PickFollowsWrite.started(memory, off, off.key, picked, watch, twin.ticket)
	_eq(_why(answer), "WROTE_SINCE", "written since, before the terminal")
	_eq(_why(_carry(memory, off, picked, watch)), "OTHER_TERMINAL", "the terminal, before the kind")
	var here := _pane(_p2("codex", "claude-9"))
	_eq(_why(_carry(memory, here, picked, watch)), "OTHER_KIND", "the kind, before the name")
	# A later session under another name: where the pick came from, before the name.
	var first := _carry(memory, _pane(_p2("claude", "claude-1", "first")), picked, watch)
	var cleared := _pane(_p2("claude", "claude-9", "cleared"))
	_eq(_why(_carry(first.memory, cleared, first.identity, watch)), "LATER_SESSION", "the session, before the name")


## What was carried is never forgotten: the viewer picks another desk and
## comes back to the agent before its first session shows, and the pick is
## carried on as if they had stayed.
func test_a_pick_that_comes_back_is_carried_on() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var agent := _pane(_p2("claude", "claude-1"))
	var first := _carry(PickFollowsWrite.Memory.new(), agent, shell.identity_key(), watch)
	var away := PickFollowsWrite.started(
		first.memory, _frame(_p2("claude", "claude-1")).pane(_local("alpha:p3")), _local("alpha:p3"), "", null, null
	)
	_eq(_why(away), "NO_START", "on another desk: no start there")
	_check(away.memory == first.memory, "and nothing forgotten")
	_unchanged(_carry(away.memory, agent, agent.identity_key(), watch), first.memory, "STILL_PICKED", "picked again")
	var in_session := _pane(_p2("claude", "claude-1", "first"))
	var back := _carry(away.memory, in_session, agent.identity_key(), watch)
	_eq([_why(back), back.identity], ["STARTED", in_session.identity_key()], "its first session: carried on")


## The start's table knows no clock, connection, navigation or answer mode,
## and the two memories do not touch: a new pane queued, its wait run out or
## ended otherwise, and the pick still goes on into the start's first session;
## a start carried, and the new pane is still waited for.
func test_a_wait_and_a_carry_do_not_touch_each_other() -> void:
	var shell := _pane(_p2())
	var watch := _start(shell)
	var first := _carry(PickFollowsWrite.Memory.new(), _pane(_p2("claude", "claude-1")), shell.identity_key(), watch)
	var in_session := _pane(_p2("claude", "claude-1", "first"))
	var queued := _awaiting(_local("alpha:p3"), "alpha:p4", "term-alpha-4", first.memory)
	_eq(_why(_carry(queued, in_session, first.identity, watch)), "STARTED", "a new pane queued meanwhile: carried")
	var late := PickFollowsWrite.overdue(queued, UNTIL_MSEC + 60000)
	_eq(_why(late), "UNSEEN", "that wait ran out a minute ago")
	_eq(
		_why(_carry(late.memory, in_session, first.identity, watch)), "STARTED", "and the start is carried all the same"
	)
	var moved := PickFollowsWrite.new_pane(queued, _frame(basic), _local("alpha:p3"), NAV + 1, GENERATION + 1, true, 0)
	_eq(_why(moved), "OTHER_CONNECTION", "another connection, a navigation, answer mode")
	_eq(_why(_carry(moved.memory, in_session, first.identity, watch)), "STARTED", "and the start is carried on")
	# The other way: a start carried while a new pane is waited for.
	var waiting := _awaiting(_local("alpha:p3"))
	var carried := _carry(waiting, _pane(_p2("claude", "claude-1")), shell.identity_key(), watch)
	_eq([_why(carried), carried.memory.machine()], ["STARTED", LOCAL], "carried, the wait kept")
	var shown := _seen(carried.memory, _frame(_grown()))
	_eq([_why(shown), _picked(shown)], ["NEW_PANE", _local("alpha:p4")], "and the new pane is picked when it shows")


# --- the new pane ---------------------------------------------------------------


## With no new pane waited for, a refresh and a frame change nothing.
func test_nothing_awaited_changes_nothing() -> void:
	var memory := PickFollowsWrite.Memory.new()
	_eq(memory.machine(), "", "no machine to ask about")
	_unchanged(_seen(memory, _frame(_grown())), memory, "NOTHING_AWAITED", "a refresh")
	_unchanged(PickFollowsWrite.overdue(memory, UNTIL_MSEC * 100), memory, "NOTHING_AWAITED", "a frame")


## A split made alpha:p4: until a snapshot shows it the wait goes on; when one
## does, with the terminal herdr named, the pick becomes it, once. A new
## space's or a worktree's shell, in another zone, is waited for and picked
## the same way.
func test_the_new_pane_is_picked_when_a_snapshot_shows_it() -> void:
	var memory := _awaiting(_local("alpha:p3"))
	_eq(memory.machine(), LOCAL, "the machine whose connection is asked about")
	_unchanged(_seen(memory, _frame(basic)), memory, "WAITING", "no snapshot shows it yet")
	var frame := _frame(_grown())
	var answer := _seen(memory, frame)
	_eq(_why(answer), "NEW_PANE", "a snapshot shows it")
	_check(answer.pane == frame.pane(_local("alpha:p4")), "the pick becomes the frame's pane")
	_eq([answer.left_from, answer.left_pane_id, answer.identity], ["", "", ""], "nothing for the card")
	_eq(answer.memory.machine(), "", "the wait is over")
	_unchanged(_seen(answer.memory, frame), answer.memory, "NOTHING_AWAITED", "the next refresh")
	_unchanged(PickFollowsWrite.overdue(answer.memory, UNTIL_MSEC), answer.memory, "NOTHING_AWAITED", "its deadline")
	var space := _awaiting(_local("alpha:p3"), "bravo:p7", "term-bravo-7")
	var zone := _seen(space, _frame(_grown("bravo:p7", "term-bravo-7", "bravo")))
	_eq([_why(zone), _picked(zone)], ["NEW_PANE", _local("bravo:p7")], "a new zone's shell")


## The wait runs out at its deadline, with or without a refresh: not a
## millisecond before, at it, and after; and the card hears it once.
func test_the_wait_runs_out_at_its_deadline() -> void:
	var memory := _awaiting(_local("alpha:p3"))
	var absent := _frame(basic)
	_unchanged(PickFollowsWrite.overdue(memory, MADE_MSEC), memory, "WAITING", "a frame at once")
	_unchanged(PickFollowsWrite.overdue(memory, UNTIL_MSEC - 1), memory, "WAITING", "a frame just before")
	_unchanged(_seen(memory, absent, UNTIL_MSEC - 1), memory, "WAITING", "a refresh just before")
	_ended(PickFollowsWrite.overdue(memory, UNTIL_MSEC), "UNSEEN", true, "a frame at the deadline")
	_ended(PickFollowsWrite.overdue(memory, UNTIL_MSEC + 1), "UNSEEN", true, "a frame after")
	_ended(_seen(memory, absent, UNTIL_MSEC), "UNSEEN", true, "a refresh at the deadline")
	_ended(_seen(memory, absent, UNTIL_MSEC + 5000), "UNSEEN", true, "a refresh after")
	var answer := _seen(memory, _frame(_grown()), UNTIL_MSEC - 1)
	_eq(_why(answer), "NEW_PANE", "shown just before the deadline: picked")
	var gone := PickFollowsWrite.overdue(memory, UNTIL_MSEC)
	_unchanged(PickFollowsWrite.overdue(gone.memory, UNTIL_MSEC + 1), gone.memory, "NOTHING_AWAITED", "heard once")


## The deadline comes first: a wait that ran out is not seen, and the card
## says so, even when the pane shows in that refresh, the pick moved, the
## machine is on another connection, the viewer navigated or the terminal is
## another.
func test_the_deadline_comes_before_every_other_ending() -> void:
	var memory := _awaiting(_local("alpha:p3"))
	var shown := _frame(_grown())
	_ended(_seen(memory, shown, UNTIL_MSEC), "UNSEEN", true, "shown at the deadline")
	var p1 := _local("alpha:p1")
	var elsewhere := PickFollowsWrite.new_pane(memory, shown, p1, NAV, GENERATION, false, UNTIL_MSEC)
	_ended(elsewhere, "UNSEEN", true, "another pick at the deadline")
	var reconnected := PickFollowsWrite.new_pane(
		memory, shown, _local("alpha:p3"), NAV, GENERATION + 1, false, UNTIL_MSEC
	)
	_ended(reconnected, "UNSEEN", true, "another connection at the deadline")
	var moved := PickFollowsWrite.new_pane(memory, shown, _local("alpha:p3"), NAV + 1, GENERATION, true, UNTIL_MSEC)
	_ended(moved, "UNSEEN", true, "navigated and answering at the deadline")
	var other := _seen(memory, _frame(_grown("alpha:p4", "term-someone-else")), UNTIL_MSEC)
	_ended(other, "UNSEEN", true, "another terminal at the deadline")


## The viewer picked another desk, or the machine is on another connection:
## the wait is over and the card hears nothing, before a navigation, answer
## mode or the terminal is looked at, and whether or not the pane shows.
func test_another_pick_or_connection_ends_the_wait_without_a_word() -> void:
	var memory := _awaiting(_local("alpha:p3"))
	var p3 := _local("alpha:p3")
	var p1 := _local("alpha:p1")
	var absent := _frame(basic)
	var shown := _frame(_grown("alpha:p4", "term-someone-else"))
	var now := MADE_MSEC + 1
	_ended(PickFollowsWrite.new_pane(memory, absent, p1, NAV, GENERATION, false, now), "OTHER_PICK", false, "a pick")
	_ended(PickFollowsWrite.new_pane(memory, absent, "", NAV, GENERATION, false, now), "OTHER_PICK", false, "no pick")
	var far := PickFollowsWrite.new_pane(memory, absent, _bee("alpha:p3"), NAV, GENERATION, false, now)
	_ended(far, "OTHER_PICK", false, "bee's alpha:p3 picked, not Local's")
	var both := PickFollowsWrite.new_pane(memory, shown, p1, NAV + 1, GENERATION + 1, true, now)
	_ended(both, "OTHER_PICK", false, "a pick, before the connection, a navigation and the terminal")
	var again := PickFollowsWrite.new_pane(memory, absent, p3, NAV, GENERATION + 1, false, now)
	_ended(again, "OTHER_CONNECTION", false, "another connection")
	var dropped := PickFollowsWrite.new_pane(memory, absent, p3, NAV, -1, false, now)
	_ended(dropped, "OTHER_CONNECTION", false, "a machine that is gone")
	var before := PickFollowsWrite.new_pane(memory, shown, p3, NAV + 1, GENERATION + 1, true, now)
	_ended(before, "OTHER_CONNECTION", false, "a connection, before a navigation and the terminal")


## The viewer navigated since the write (the revision moved, wherever the
## view ended up), or is in answer mode: the wait is over, and the card says
## the viewer moved on, whether or not the pane shows, and before its terminal
## is looked at.
func test_a_navigation_or_answer_mode_ends_the_wait_and_the_card_says_so() -> void:
	var memory := _awaiting(_local("alpha:p3"))
	var p3 := _local("alpha:p3")
	var absent := _frame(basic)
	var now := MADE_MSEC + 1
	var moved := PickFollowsWrite.new_pane(memory, absent, p3, NAV + 2, GENERATION, false, now)
	_ended(moved, "MOVED_ON", true, "two navigations, the pane not shown yet")
	var answering := PickFollowsWrite.new_pane(memory, absent, p3, NAV, GENERATION, true, now)
	_ended(answering, "MOVED_ON", true, "answer mode, the pane not shown yet")
	var shown := PickFollowsWrite.new_pane(memory, _frame(_grown()), p3, NAV, GENERATION, true, now)
	_ended(shown, "MOVED_ON", true, "answer mode as the pane shows: not picked")
	var other := _frame(_grown("alpha:p4", "term-someone-else"))
	var first := PickFollowsWrite.new_pane(memory, other, p3, NAV + 1, GENERATION, false, now)
	_ended(first, "MOVED_ON", true, "a navigation, before the terminal")


## The pane shows with another terminal than the one herdr named for it: not
## picked, the card says why, and it is not waited for any longer.
func test_a_new_pane_with_another_terminal_is_not_picked() -> void:
	var memory := _awaiting(_local("alpha:p3"))
	var other := _frame(_grown("alpha:p4", "term-someone-else"))
	_ended(_seen(memory, other), "OTHER_TERMINAL", true, "another terminal")
	# The memory asked with is not the one consumed: asked again with the
	# terminal herdr named, the same memory still picks.
	_eq(_why(_seen(memory, _frame(_grown()))), "NEW_PANE", "the memory asked with is as it was")


## A second new pane replaces the first wait, without a word: only the second
## is picked, by its own deadline and the navigation revision it was made at.
func test_a_second_new_pane_replaces_the_first_wait() -> void:
	var first := _awaiting(_local("alpha:p3"))
	var p1 := _local("alpha:p1")
	var second := PickFollowsWrite.new_pane_made(
		first, p1, "alpha:p5", "term-alpha-5", GENERATION + 1, NAV + 3, MADE_MSEC + 4000, WAIT_MSEC
	)
	_eq(_why(_seen(first, _frame(_grown()))), "NEW_PANE", "the first memory is as it was")
	var now := UNTIL_MSEC + 1
	var early := PickFollowsWrite.new_pane(second, _frame(_grown()), p1, NAV + 3, GENERATION + 1, false, now)
	_unchanged(early, second, "WAITING", "the first pane shows, past the first deadline: not waited for")
	var frame := _frame(_grown("alpha:p5", "term-alpha-5"))
	var stale := PickFollowsWrite.new_pane(second, frame, _local("alpha:p3"), NAV + 3, GENERATION + 1, false, now)
	_eq(_why(stale), "OTHER_PICK", "the pick the first was made from is not the second's")
	var answer := PickFollowsWrite.new_pane(second, frame, p1, NAV + 3, GENERATION + 1, false, now)
	_eq([_why(answer), _picked(answer)], ["NEW_PANE", _local("alpha:p5")], "the second is picked")
	var late := PickFollowsWrite.overdue(second, MADE_MSEC + 4000 + WAIT_MSEC)
	_eq([_why(late), late.left_from, late.left_pane_id], ["UNSEEN", p1, "alpha:p5"], "by its own deadline")


## Pane ids repeat across machines: a split on bee waits for bee's alpha:p4,
## asks about bee's connection, and Local's pane of the same id is not it.
func test_pane_ids_that_collide_on_two_machines_are_kept_apart() -> void:
	var from := _bee("alpha:p3")
	var memory := _awaiting(from)
	_eq(memory.machine(), BEE, "the machine whose connection is asked about")
	var local_only := _frame(_grown(), basic)
	_check(local_only.pane(_local("alpha:p4")) != null, "the fixture: Local shows an alpha:p4 of its own")
	var now := MADE_MSEC + 1
	var waiting := PickFollowsWrite.new_pane(memory, local_only, from, NAV, GENERATION, false, now)
	_unchanged(waiting, memory, "WAITING", "Local's alpha:p4 is not the pane waited for")
	var local_pick := PickFollowsWrite.new_pane(memory, local_only, _local("alpha:p3"), NAV, GENERATION, false, now)
	_ended(local_pick, "OTHER_PICK", false, "Local's alpha:p3 picked: not the pane split", BEE)
	var both := _frame(_grown(), _grown())
	var answer := PickFollowsWrite.new_pane(memory, both, from, NAV, GENERATION, false, now)
	_eq([_why(answer), _picked(answer)], ["NEW_PANE", _bee("alpha:p4")], "bee's is picked")
	var late := PickFollowsWrite.overdue(memory, UNTIL_MSEC)
	_eq([_why(late), late.left_from, late.left_pane_id], ["UNSEEN", from, "alpha:p4"], "the card hears of bee's pane")
