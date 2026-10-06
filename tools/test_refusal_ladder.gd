extends "res://tools/command_test_base.gd"
## "May pane P take kind K now, and why not", as tables. The fleet's half:
## for every kind of command (a read, a switch, an answer key, a line, a
## start, a split, a close, a new space, a new worktree) and every state a
## pane or its machine can be in, the first refusal, through the names the
## card and the suites ask by (can_operate() and the five can_*()), then
## through the one question they all come from (HerdrFleet.command_refusal())
## and the values the card reads (HerdrFleet.answers(), CommandAnswers). The
## card's half, with no scene and no fleet: the ladder's order when several
## steps refuse at once (CardActions.ladder()), which kinds are checked
## against which preview, what each press aims from the answers alone, and
## the two confirms (arm, hold, lapse, a change of binding, text or scope).
##
## The fleet's tables run a bare HerdrFleet (no office, no HUD) against this
## suite's own two fake herdrs: Local on A, the debug machine "bee" on B. Every
## case resets both fakes and opens only what it needs; the one deliberate
## write is the pair of switches (`pane.focus`) that an open write and an owed
## look are told by. The last case sums up both fakes. Run through
## tools/run_tests.sh.
##
## godot --headless --path . --script tools/test_refusal_ladder.gd -- \
##     --socket-a=<fake herdr> --control-a=<its control> \
##     --socket-b=<second fake herdr> --control-b=<its control> --work=<short tmp dir>

const K := CommandContext.Kind
const R := CommandRefusal.Reason

## Every kind the ladder answers for, in the order a row lists them.
const KINDS: Array[CommandContext.Kind] = [
	CommandContext.Kind.READ,
	CommandContext.Kind.FOCUS,
	CommandContext.Kind.KEYS,
	CommandContext.Kind.LINE,
	CommandContext.Kind.START,
	CommandContext.Kind.SPLIT,
	CommandContext.Kind.CLOSE,
	CommandContext.Kind.SPACE,
	CommandContext.Kind.WORKTREE,
]
## The seven the card presses.
const PRESSED: Array[CommandContext.Kind] = [
	CommandContext.Kind.KEYS,
	CommandContext.Kind.LINE,
	CommandContext.Kind.START,
	CommandContext.Kind.SPLIT,
	CommandContext.Kind.CLOSE,
	CommandContext.Kind.SPACE,
	CommandContext.Kind.WORKTREE,
]

## The bare fleets a case started; freed after it.
var _fleets: Array[HerdrFleet] = []


func _marker() -> String:
	return "REFUSAL LADDER TESTS"


func _after_case() -> void:
	for started in _fleets:
		if is_instance_valid(started):
			if started.is_inside_tree():
				root.remove_child(started)
			started.free()
	_fleets.clear()
	super()


# --- the fleet's answer, by the names the card asks by --------------------------------


## Every pane of the basic picture, on Local and on bee (the same pane ids on
## both), kind by kind: a working agent takes neither a key nor a line, a
## shell takes a start of a kind seen here, an idle agent a line, a blocked
## one a key. A pane that is not there and a machine that is not shown are
## refused by what the command would carry first: a close has no scope and a
## new space no directory before anything is asked of the machine. A blank
## line is the press's refusal, not the pane's: asked of a working agent the
## answer is its state, and only a line really sent is judged by its text.
func test_each_kind_is_answered_for_each_pane_by_its_state() -> void:
	await _in_the_basic_picture(_named)


## An agent's state decides keys and a line: a done agent takes a line like an
## idle one; one herdr is still launching takes no line, but its keys while it
## asks; a state nobody knows is busy; a shell being launched in takes no
## second start.
func test_an_agents_state_decides_keys_and_a_line() -> void:
	await _in_other_states(_named)


## A fleet that does not write refuses every kind before anything else; a
## machine whose snapshot was refused, that dropped, or that speaks a protocol
## this office was not verified against refuses every kind for that reason,
## and the other machine goes on.
func test_a_machine_that_cannot_take_a_command_refuses_every_kind() -> void:
	await _in_machine_states(_named)


## What a command carries is judged with it: the side a pane's shape gives
## (too small, no size), what a close takes with it (never the repo's own
## space while its mezzanines are open), the shell's directory (absolute, and
## spelled as herdr sent it), the workspace a worktree is made of (never a
## linked one) and the kind of a start (seen here, well spelled).
func test_the_values_a_command_carries_are_judged() -> void:
	await _in_the_worktrees_picture(_named)


## One write at a time per pane, and a look after it: while a switch to a pane
## is open every write to that pane waits (IN_FLIGHT), once it ended they wait
## for a look (LOOK_FIRST), and a preview shown after it turns them on again.
## What the pane's own state refuses is said first; a read never waits; other
## panes go on.
func test_an_open_write_and_a_look_owed_stand_against_every_write() -> void:
	await _in_a_write(_named)


# --- helpers every case above stands on (no name from this lane) ----------------------


## A fleet on real frames with no office: Local on fake A and, with `bee`, the
## debug machine "bee" on fake B, by the office's own command line. The
## machine list comes from nowhere (command_test_base's environment), so no
## other machine is shown.
func _bare_fleet(read_only := false, bee := true) -> HerdrFleet:
	var line := PackedStringArray(["--socket=" + args["socket-a"]])
	if bee:
		line.append("--machine-socket=bee=" + args["socket-b"])
	var started := HerdrFleet.new()
	_fleets.append(started)
	root.add_child(started)
	started.start(line, read_only)
	var machines := 2 if bee else 1
	await _until(
		func() -> bool: return started.size() == machines and started.live_count() == machines,
		"%d machines live and current" % machines
	)
	return started


func _on(machine: String, pane_id: String) -> String:
	return HerdrFleet.pane_key(machine, pane_id)


## One row of a table: pane `key`, `kind` (a START: of `agent_kind`), the answer.
func _row(key: String, kind: CommandContext.Kind, reason: CommandRefusal.Reason, agent_kind := "claude") -> Array:
	return [key, kind, agent_kind if kind == K.START else "", reason]


## Rows for pane `key`: `reasons` in KINDS' order (a START of claude).
func _rows(key: String, reasons: Array) -> Array:
	var rows: Array = []
	for index in KINDS.size():
		var reason: CommandRefusal.Reason = reasons[index]
		rows.append(_row(key, KINDS[index], reason))
	return rows


## Rows for pane `key` saying `reason` for every kind.
func _all(key: String, reason: CommandRefusal.Reason) -> Array:
	var reasons: Array = []
	reasons.resize(KINDS.size())
	reasons.fill(reason)
	return _rows(key, reasons)


## Ask every row through `ask` (key, kind, agent kind in; a reason out) and
## compare by name.
func _rows_hold(rows: Array, ask: Callable, what: String) -> void:
	for row: Array in rows:
		var key: String = row[0]
		var kind: CommandContext.Kind = row[1]
		var agent_kind: String = row[2]
		var expected: CommandRefusal.Reason = row[3]
		var said: CommandRefusal.Reason = ask.call(key, kind, agent_kind)
		var where := (
			"%s %s%s" % [HerdrFleet.split_key(key)[1], _kind(kind), " " + agent_kind if kind == K.START else ""]
		)
		_eq(_reason(said), _reason(expected), "%s: %s" % [what, where])


func _reason(reason: CommandRefusal.Reason) -> String:
	return str(CommandRefusal.Reason.keys()[reason])


func _kind(kind: CommandContext.Kind) -> String:
	return str(CommandContext.Kind.keys()[kind])


## The name each kind is asked by on a fleet: can_operate() for a read, a
## switch, a key and a line; the kind's own can_*() for the rest.
func _by_name(key: String, kind: CommandContext.Kind, agent_kind: String, asked: HerdrFleet) -> CommandRefusal.Reason:
	match kind:
		K.START:
			return asked.can_start(key, agent_kind)
		K.SPLIT:
			return asked.can_split(key)
		K.CLOSE:
			return asked.can_close(key)
		K.SPACE:
			return asked.can_space(key)
		K.WORKTREE:
			return asked.can_worktree(key)
	return asked.can_operate(key, kind)


func _named(asked: HerdrFleet) -> Callable:
	return _by_name.bind(asked)


## Fake `which` serves `raw` from now on, and says a pane changed.
func _serve(which: String, raw: Dictionary) -> void:
	_ctl(which, "set_snapshot", {"snapshot": raw})
	_ctl(which, "emit", {"fixture_event": "pane_updated"})


## `raw` with pane `pane_id` (a shell) being launched in: herdr lists the
## start under `agent_name`, still pending, with no agent detected yet.
func _launching(raw: Dictionary, pane_id: String, agent_name: String) -> Dictionary:
	var result := raw.duplicate(true)
	var record := {"name": agent_name, "launch_pending": true}
	for pane: Dictionary in _list(result, "panes"):
		if pane.get("pane_id") == pane_id:
			for field: String in ["terminal_id", "pane_id", "workspace_id", "tab_id"]:
				record[field] = pane.get(field)
	var agents := _list(result, "agents")
	agents.append(record)
	result["agents"] = agents
	return result


## `raw` with pane `pane_id`'s place in its tab's layout `width` x `height`
## cells; no place at all for a width of 0.
func _sized(raw: Dictionary, pane_id: String, width: int, height: int) -> Dictionary:
	var result := raw.duplicate(true)
	for layout: Dictionary in _list(result, "layouts"):
		var kept: Array = []
		for slot: Dictionary in _list(layout, "panes"):
			if slot.get("pane_id") == pane_id:
				if width <= 0:
					continue
				var rect := _dict(slot, "rect")
				rect["width"] = width
				rect["height"] = height
			kept.append(slot)
		layout["panes"] = kept
	return result


## Wait `msec` on the monotonic clock, frames running.
func _pass_msec(msec: int) -> void:
	var after := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < after:
		await process_frame


## Look at pane `key` the way the card does after a write: a read asked for
## LOOK_DELAY_MSEC after the write ended, shown.
func _look_at(asked: HerdrFleet, key: String) -> void:
	var read := asked.read_pane(asked.context_for(key, 1).reading(CommandContext.SOURCE_RECENT, 12))
	await _until(read.is_finished, "the look")
	_eq(read.state, CommandTicket.State.ACCEPTED, "the look came back")
	asked.preview_shown(read)


# --- the tables -----------------------------------------------------------------------


## The basic picture's rows for `machine`: claude working (alpha:p1), a shell
## (alpha:p2), codex idle (alpha:p3), pi blocked (bravo:p1).
func _basic_rows(machine: String) -> Array:
	var rows: Array = []
	# READ, FOCUS, KEYS, LINE, START claude, SPLIT, CLOSE, SPACE, WORKTREE
	rows.append_array(
		_rows(
			_on(machine, "alpha:p1"),
			[R.NONE, R.NONE, R.NOT_ASKING, R.AGENT_BUSY, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	rows.append_array(
		_rows(
			_on(machine, "alpha:p2"),
			[R.NONE, R.NONE, R.NOT_AN_AGENT, R.NOT_AN_AGENT, R.NONE, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	rows.append_array(
		_rows(
			_on(machine, "alpha:p3"),
			[R.NONE, R.NONE, R.NOT_ASKING, R.NONE, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	rows.append_array(
		_rows(
			_on(machine, "bravo:p1"),
			[R.NONE, R.NONE, R.NONE, R.AGENT_ASKING, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	# The kind of a start: another kind seen here, one not seen, one misspelled
	# (its spelling is the payload's, judged before the pane).
	rows.append(_row(_on(machine, "alpha:p2"), K.START, R.NONE, "codex"))
	rows.append(_row(_on(machine, "alpha:p2"), K.START, R.KIND_UNKNOWN, "gemini"))
	rows.append(_row(_on(machine, "alpha:p2"), K.START, R.KIND_INVALID, "Claude"))
	rows.append(_row(_on(machine, "alpha:p1"), K.START, R.KIND_INVALID, "Claude"))
	# No such pane on a live machine: a close has no scope and a space no
	# directory to carry, which is said before the pane is looked for.
	rows.append_array(
		_rows(
			_on(machine, "alpha:p9"),
			[
				R.PANE_GONE,
				R.PANE_GONE,
				R.PANE_GONE,
				R.PANE_GONE,
				R.PANE_GONE,
				R.PANE_GONE,
				R.SCOPE_CHANGED,
				R.CWD_UNKNOWN,
				R.PANE_GONE
			]
		)
	)
	return rows


func _in_the_basic_picture(how: Callable) -> void:
	_fakes("snapshot_basic", [])
	var asked := await _bare_fleet()
	var ask: Callable = how.call(asked)
	_rows_hold(_basic_rows(HerdrFleet.LOCAL), ask, "Local")
	_rows_hold(_basic_rows(BEE), ask, "bee")
	# No machine by that key: the same two say what they lack first.
	var nowhere := _on("socket:nowhere", "alpha:p1")
	_rows_hold(
		_rows(
			nowhere,
			[
				R.MACHINE_GONE,
				R.MACHINE_GONE,
				R.MACHINE_GONE,
				R.MACHINE_GONE,
				R.MACHINE_GONE,
				R.MACHINE_GONE,
				R.SCOPE_CHANGED,
				R.CWD_UNKNOWN,
				R.MACHINE_GONE
			]
		),
		ask,
		"a machine not shown"
	)
	# can_operate() knows a switch, a key and a line by name; asked about any
	# other kind it answers as for a read.
	var shell := _on(BEE, "alpha:p2")
	_eq(_reason(asked.can_operate(shell)), _reason(R.NONE), "a switch is what can_operate() asks by default")
	for other: CommandContext.Kind in [K.START, K.CLOSE, K.SCREEN, K.TYPE_KEYS]:
		_eq(
			_reason(asked.can_operate(_on(BEE, "alpha:p9"), other)),
			_reason(R.PANE_GONE),
			"can_operate(%s) answers as for a read" % _kind(other)
		)
	# A blank line to a working agent: its state when asked, its text when sent.
	var working := _on(BEE, "alpha:p1")
	_eq(_reason(asked.can_operate(working, K.LINE)), _reason(R.AGENT_BUSY), "asked: the pane's state")
	var blank := asked.send_line(asked.context_for(working, 1).replying("", null))
	_eq(_reason(_refusal(blank)), _reason(R.LINE_BLANK), "sent: the line's own text first")
	await _frames(3)
	for which: String in ["control-a", "control-b"]:
		_eq(_sequence(which), PackedStringArray(), "%s: asking sends nothing" % which)


func _in_other_states(how: Callable) -> void:
	_fakes("snapshot_basic", [])
	var asked := await _bare_fleet()
	var ask: Callable = how.call(asked)
	var raw := _changed(_raw(), "alpha:p1", {"agent_status": "done"})
	raw = _changed(raw, "alpha:p3", {"launch_pending": true})
	raw = _changed(raw, "bravo:p1", {"launch_pending": true})
	raw = _launching(raw, "alpha:p2", "claude-7")
	_serve("control-b", raw)
	_serve("control-a", _changed(_raw(), "alpha:p3", {"agent_status": "unknown"}))
	await _until(
		func() -> bool: return asked.can_operate(_on(BEE, "alpha:p1"), K.LINE) == R.NONE, "bee's claude is done"
	)
	await _until(
		func() -> bool: return asked.can_start(_on(BEE, "alpha:p2"), "claude") == R.AGENT_STARTING,
		"bee's shell is being launched in"
	)
	await _until(
		func() -> bool: return asked.can_operate(_on(HerdrFleet.LOCAL, "alpha:p3"), K.LINE) == R.AGENT_BUSY,
		"Local's codex is unknown"
	)
	var rows: Array = []
	# READ, FOCUS, KEYS, LINE, START claude, SPLIT, CLOSE, SPACE, WORKTREE
	rows.append_array(
		_rows(
			_on(BEE, "alpha:p1"), [R.NONE, R.NONE, R.NOT_ASKING, R.NONE, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	rows.append_array(
		_rows(
			_on(BEE, "alpha:p3"),
			[R.NONE, R.NONE, R.NOT_ASKING, R.AGENT_STARTING, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	# Blocked while herdr still launches it: its keys go, a line does not.
	rows.append_array(
		_rows(
			_on(BEE, "bravo:p1"),
			[R.NONE, R.NONE, R.NONE, R.AGENT_STARTING, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	rows.append_array(
		_rows(
			_on(BEE, "alpha:p2"),
			[R.NONE, R.NONE, R.NOT_AN_AGENT, R.NOT_AN_AGENT, R.AGENT_STARTING, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	rows.append_array(
		_rows(
			_on(HerdrFleet.LOCAL, "alpha:p3"),
			[R.NONE, R.NONE, R.NOT_ASKING, R.AGENT_BUSY, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE]
		)
	)
	_rows_hold(rows, ask, "states")


func _in_machine_states(how: Callable) -> void:
	_fakes("snapshot_basic", [])
	var quiet := await _bare_fleet(true)
	_check(quiet.read_only(), "a fleet started without writes")
	var quiet_ask: Callable = how.call(quiet)
	for pane_id: String in ["alpha:p1", "alpha:p2", "alpha:p9"]:
		_rows_hold(_all(_on(BEE, pane_id), R.READ_ONLY), quiet_ask, "read-only")
	_rows_hold(_all(_on("socket:nowhere", "alpha:p1"), R.READ_ONLY), quiet_ask, "read-only, no such machine")
	var asked := await _bare_fleet()
	var ask: Callable = how.call(asked)
	var key := _on(BEE, "alpha:p3")
	var raw := _raw()
	# A snapshot over the caps is refused whole: the last picture stays, the
	# machine is online and not current.
	var huge := _raw()
	var records: Array = []
	for index in HerdrSnapshot.MAX_PANES + 1:
		records.append({})
	huge.panes = records
	_serve("control-b", huge)
	await _until(func() -> bool: return asked.can_operate(key) == R.SNAPSHOT_NOT_CURRENT, "a refused snapshot")
	for pane_id: String in ["alpha:p1", "alpha:p2", "alpha:p3", "bravo:p1"]:
		_rows_hold(_all(_on(BEE, pane_id), R.SNAPSHOT_NOT_CURRENT), ask, "online, not current")
	_rows_hold(_basic_rows(HerdrFleet.LOCAL), ask, "Local goes on")
	_ctl("control-b", "set_snapshot", {"snapshot": raw})
	_ctl("control-b", "set_protocol", {"protocol": 23})
	_ctl("control-b", "vanish")
	# Not current already (is_stale() says nothing new): wait for the drop itself.
	await _until(func() -> bool: return asked.can_operate(key) == R.MACHINE_OFFLINE, "bee dropped")
	for pane_id: String in ["alpha:p1", "alpha:p2", "alpha:p3", "bravo:p1"]:
		_rows_hold(_all(_on(BEE, pane_id), R.MACHINE_OFFLINE), ask, "offline")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return asked.snapshot_is_current(BEE), "bee back on protocol 23")
	for pane_id: String in ["alpha:p1", "alpha:p2", "alpha:p3", "bravo:p1"]:
		_rows_hold(_all(_on(BEE, pane_id), R.UNKNOWN_PROTOCOL), ask, "a protocol not verified")
	_rows_hold(_basic_rows(HerdrFleet.LOCAL), ask, "Local still goes on")


func _in_the_worktrees_picture(how: Callable) -> void:
	_fakes("snapshot_worktrees", [])
	var asked := await _bare_fleet(false, false)
	var ask: Callable = how.call(asked)
	var local := HerdrFleet.LOCAL
	var rows: Array = []
	# The repo's own space, among other panes, its mezzanines open.
	for kind: CommandContext.Kind in [K.SPLIT, K.CLOSE, K.SPACE, K.WORKTREE]:
		rows.append(_row(_on(local, "hs:p1"), kind, R.NONE))
	rows.append(_row(_on(local, "hs:p1"), K.START, R.NOT_A_SHELL))
	# A linked worktree is never the source of another.
	rows.append(_row(_on(local, "hud:p1"), K.WORKTREE, R.MEZZANINE_SOURCE))
	rows.append(_row(_on(local, "ops:p1"), K.WORKTREE, R.MEZZANINE_SOURCE))
	rows.append(_row(_on(local, "hud:p1"), K.CLOSE, R.NONE))
	rows.append(_row(_on(local, "hud:p1"), K.KEYS, R.NONE))
	# A space with no repository the office knows of: herdr and git decide.
	rows.append(_row(_on(local, "notes:p1"), K.WORKTREE, R.NONE))
	rows.append(_row(_on(local, "notes:p1"), K.START, R.NONE))
	rows.append(_row(_on(local, "notes:p1"), K.START, R.NONE, "pi"))
	rows.append(_row(_on(local, "notes:p1"), K.START, R.KIND_UNKNOWN, "gemini"))
	rows.append(_row(_on(local, "notes:p1"), K.START, R.KIND_INVALID, "Claude"))
	rows.append(_row(_on(local, "notes:p1"), K.SPACE, R.NONE))
	rows.append(_row(_on(local, "data:p1"), K.LINE, R.NONE))
	rows.append(_row(_on(local, "data:p2"), K.SPLIT, R.NONE))
	rows.append(_row(_on(local, "ops:p1"), K.SPLIT, R.NONE))
	_rows_hold(rows, ask, "the worktrees picture")
	_eq(asked.split_direction(_on(local, "hud:p1")), "right", "a wide pane splits to the right")
	# The same picture, changed where each value is read.
	var raw := _without(_without(_raw("snapshot_worktrees"), "hs:p2"), "hs:p3")
	raw = _changed(raw, "notes:p1", {"cwd": "notes"})
	raw = _changed(raw, "data:p1", {"cwd": "/home/tester/da" + char(0x202e) + "ta"})
	raw = _sized(raw, "data:p2", 30, 8)
	raw = _sized(raw, "ops:p1", 0, 0)
	raw = _sized(raw, "hud:p1", 60, 50)
	_serve("control-a", raw)
	await _until(
		func() -> bool: return asked.can_close(_on(local, "hs:p1")) == R.GROUP_PARENT,
		"the repo's own space is down to its last pane"
	)
	rows = []
	rows.append(_row(_on(local, "hs:p1"), K.CLOSE, R.GROUP_PARENT))
	rows.append(_row(_on(local, "hs:p1"), K.SPACE, R.NONE))
	rows.append(_row(_on(local, "hs:p1"), K.WORKTREE, R.NONE))
	rows.append(_row(_on(local, "hud:p1"), K.CLOSE, R.NONE))
	rows.append(_row(_on(local, "notes:p1"), K.SPACE, R.CWD_UNKNOWN))
	rows.append(_row(_on(local, "notes:p1"), K.CLOSE, R.NONE))
	rows.append(_row(_on(local, "data:p1"), K.SPACE, R.CWD_UNCLEAN))
	rows.append(_row(_on(local, "data:p1"), K.CLOSE, R.NONE))
	rows.append(_row(_on(local, "data:p2"), K.SPLIT, R.PANE_TOO_SMALL))
	rows.append(_row(_on(local, "data:p2"), K.CLOSE, R.NONE))
	rows.append(_row(_on(local, "ops:p1"), K.SPLIT, R.SIZE_UNKNOWN))
	rows.append(_row(_on(local, "hud:p1"), K.SPLIT, R.NONE))
	_rows_hold(rows, ask, "the worktrees picture, changed")
	_eq(asked.split_direction(_on(local, "hud:p1")), "down", "a narrow, tall pane splits down")
	_eq(asked.split_direction(_on(local, "data:p2")), "", "a pane too small splits to no side")
	_eq(_sequence("control-a"), PackedStringArray(), "asking sends nothing")


## The rows an open write (`blocked` IN_FLIGHT), an owed look (LOOK_FIRST) or
## neither (NONE) gives for a switched agent, a switched shell and a pane
## nobody wrote to.
func _write_rows(agent: String, shell: String, other: String, blocked: CommandRefusal.Reason) -> Array:
	var rows: Array = []
	# READ, FOCUS, KEYS, LINE, START claude, SPLIT, CLOSE, SPACE, WORKTREE
	rows.append_array(
		_rows(agent, [R.NONE, blocked, R.NOT_ASKING, blocked, R.NOT_A_SHELL, blocked, blocked, blocked, blocked])
	)
	rows.append_array(
		_rows(shell, [R.NONE, blocked, R.NOT_AN_AGENT, R.NOT_AN_AGENT, blocked, blocked, blocked, blocked, blocked])
	)
	rows.append_array(
		_rows(other, [R.NONE, R.NONE, R.NOT_ASKING, R.AGENT_BUSY, R.NOT_A_SHELL, R.NONE, R.NONE, R.NONE, R.NONE])
	)
	return rows


func _in_a_write(how: Callable) -> void:
	_fakes("snapshot_basic", ["pane.read", "pane.focus"])
	var asked := await _bare_fleet()
	var ask: Callable = how.call(asked)
	var agent := _on(BEE, "alpha:p3")
	var shell := _on(BEE, "alpha:p2")
	var other := _on(BEE, "alpha:p1")
	_rows_hold(_write_rows(agent, shell, other, R.NONE), ask, "before any write")
	var first := asked.focus_pane(asked.context_for(agent, 1).focusing())
	var second := asked.focus_pane(asked.context_for(shell, 1).focusing())
	_rows_hold(_write_rows(agent, shell, other, R.IN_FLIGHT), ask, "a write open")
	await _until(func() -> bool: return first.is_finished() and second.is_finished(), "both switches")
	_eq([first.state, second.state], [CommandTicket.State.ACCEPTED, CommandTicket.State.ACCEPTED], "herdr took both")
	_rows_hold(_write_rows(agent, shell, other, R.LOOK_FIRST), ask, "a look owed")
	await _pass_msec(HerdrCommands.LOOK_DELAY_MSEC + 50)
	await _look_at(asked, agent)
	await _look_at(asked, shell)
	_rows_hold(_write_rows(agent, shell, other, R.NONE), ask, "looked")
	_eq(
		_writes_seen("control-b"),
		PackedStringArray(["pane.focus", "pane.focus"]),
		"the two switches and no other write"
	)
	_eq(_writes_seen("control-a"), PackedStringArray(), "nothing to Local")


# === BELOW: CASES THAT NAME THIS LANE'S INTERFACE (command_refusal, answers, CardActions.ladder) ===

# --- the fleet's answer, by the one question and by the values the card reads --------


## The one question for a fleet, and the same asked through the answers the
## card reads: both must say the same, row by row.
func _by_both(key: String, kind: CommandContext.Kind, agent_kind: String, asked: HerdrFleet) -> CommandRefusal.Reason:
	var one := asked.command_refusal(key, kind, agent_kind)
	var kinds: Array[CommandContext.Kind] = [kind]
	var said := asked.answers(key, 1, kinds, PackedStringArray([agent_kind]))
	_eq(_reason(said.refusal(kind, agent_kind)), _reason(one), "answers() says what command_refusal() says")
	return one


func _both(asked: HerdrFleet) -> Callable:
	return _by_both.bind(asked)


## The same table as the names give, from the one question and from the
## answers. A kind nobody asks this way is not allowed.
func test_the_one_question_answers_each_kind_for_each_pane() -> void:
	await _in_the_basic_picture(_both)
	var asked := _fleets[0]
	for other: CommandContext.Kind in [K.TARGET, K.SCREEN, K.TYPE_KEYS, K.TYPE_TEXT, K.PASTE, K.LAUNCH_CHECK]:
		_eq(
			_reason(asked.command_refusal(_on(BEE, "alpha:p3"), other)),
			_reason(R.NOT_ALLOWED),
			"%s is not asked this way" % _kind(other)
		)


func test_the_one_question_reads_an_agents_state() -> void:
	await _in_other_states(_both)


func test_the_one_question_says_what_a_machine_cannot_take() -> void:
	await _in_machine_states(_both)


func test_the_one_question_judges_the_values_a_command_carries() -> void:
	await _in_the_worktrees_picture(_both)


func test_the_one_question_waits_for_an_open_write_and_a_look() -> void:
	await _in_a_write(_both)


## What the answers carry besides refusals: the target on the binding asked
## for, the values the block's commands are made of, a name per kind of start,
## and an answer only for what was asked. Each command built from them is the
## one the fleet's own readings give.
func test_the_answers_carry_what_the_blocks_commands_are_made_of() -> void:
	_fakes("snapshot_basic", [])
	var asked := await _bare_fleet()
	var local := HerdrFleet.LOCAL
	var shell := _on(local, "alpha:p2")
	var block: Array[CommandContext.Kind] = [K.START, K.SPLIT, K.CLOSE, K.SPACE, K.WORKTREE]
	var said := asked.answers(shell, 7, block, PackedStringArray(["gemini"]))
	var aimed := asked.context_for(shell, 7)
	_eq(
		[said.target.kind, said.target.binding, said.target.pane_key, said.target.generation],
		[K.TARGET, 7, shell, asked.generation(local)],
		"the target, on the binding asked for"
	)
	_eq(
		[said.target.identity_key, said.target.wire_pane_id, said.target.terminal_id],
		[aimed.identity_key, "alpha:p2", "term-alpha-2"],
		"aimed as context_for() aims"
	)
	_eq(said.scope.signature(), asked.close_scope(shell).signature(), "what a close takes with it")
	_eq([said.direction, said.cwd], ["right", "/home/tester/alpha"], "the side and the directory")
	_eq([said.direction, said.cwd], [asked.split_direction(shell), asked.pane_cwd(shell)], "as the fleet reads them")
	_eq([said.workspace_id, said.wire_workspace_id], ["alpha", "alpha"], "the workspace, both spellings")
	var kinds := asked.agent_kinds(local)
	_eq(kinds, PackedStringArray(["claude", "codex", "pi"]), "the kinds Local shows")
	for agent_kind in kinds:
		_eq(said.names.get(agent_kind), asked.next_agent_name(local, agent_kind), "the next %s" % agent_kind)
		_eq(_reason(said.refusal(K.START, agent_kind)), _reason(R.NONE), "a start of %s may go" % agent_kind)
	_eq(said.names.get("gemini"), "gemini-1", "a kind the card still offers gets a name too")
	_eq(_reason(said.refusal(K.START, "gemini")), _reason(R.KIND_UNKNOWN), "and its own answer")
	_eq(_reason(said.refusal(K.START, "aider")), _reason(CommandAnswers.UNASKED), "a kind nobody offered: not asked")
	_eq(_reason(said.refusal(K.KEYS)), _reason(CommandAnswers.UNASKED), "a kind not asked about")
	_eq([said.launch, said.last_write, said.must_look], [null, null, false], "no start, no write, no look owed")
	_eq(said.launch_outcome, LaunchWatch.Outcome.GONE, "no start to judge")
	var start := said.starting("claude", null)
	_eq([start.kind, start.agent_kind, start.agent_name, start.binding], [K.START, "claude", "claude-1", 7], "a start")
	_eq([said.splitting().kind, said.splitting().direction], [K.SPLIT, "right"], "a split")
	_check(said.closing().scope == said.scope, "a close carries the scope read")
	_eq([said.spacing().kind, said.spacing().cwd], [K.SPACE, "/home/tester/alpha"], "a new space")
	var tree := said.branching("lane/x")
	_eq([tree.workspace_id, tree.wire_workspace_id, tree.branch], ["alpha", "alpha", "lane/x"], "a worktree")
	# Asked for less, less is answered: no start, no names.
	var few: Array[CommandContext.Kind] = [K.SPLIT]
	var less := asked.answers(shell, 1, few)
	_eq(less.names.size(), 0, "no start asked, no name made")
	_eq(_reason(less.refusal(K.START, "claude")), _reason(CommandAnswers.UNASKED), "and none answered")
	_eq(_reason(less.refusal(K.SPLIT)), _reason(R.NONE), "the one asked is")
	_eq(less.scope.signature(), said.scope.signature(), "the values are read all the same")
	# Answers no fleet gave: nothing may go and nothing can be aimed.
	var none := CommandAnswers.new()
	for kind in PRESSED:
		_eq(_reason(none.refusal(kind, "claude")), _reason(R.NOT_CONNECTED), "%s: no fleet asked" % _kind(kind))
	_check(none.scope.missing, "no scope")
	_eq(
		[none.starting("claude", null), none.splitting(), none.closing(), none.spacing(), none.branching("x")],
		[null, null, null, null, null],
		"no target, no command"
	)
	# A read-only fleet says so for every kind and still reads the values.
	var quiet := await _bare_fleet(true)
	var silent := quiet.answers(shell, 1, block)
	for kind in block:
		_eq(_reason(silent.refusal(kind, "claude")), _reason(R.READ_ONLY), "read-only: %s" % _kind(kind))
	_eq([silent.direction, silent.cwd, silent.scope.missing], ["right", "/home/tester/alpha", false], "the values")


## An answer is how things stand now, never the gesture's target: after a
## machine is replaced a fresh answer passes on the new generation, and a
## command built from answers taken before is refused, whatever a fresh one says.
func test_a_fresh_answer_passes_after_a_replacement_and_a_held_one_is_refused() -> void:
	_fakes("snapshot_basic", [])
	var asked := await _bare_fleet()
	var key := _on(BEE, "alpha:p3")
	var block: Array[CommandContext.Kind] = [K.SPLIT, K.CLOSE, K.SPACE, K.WORKTREE]
	var held := asked.answers(key, 4, block)
	for kind in block:
		_eq(_reason(held.refusal(kind)), _reason(R.NONE), "before: %s may go" % _kind(kind))
	_ctl("control-b", "vanish")
	await _until(func() -> bool: return asked.is_stale(BEE), "bee dropped")
	_ctl("control-b", "appear")
	await _until(func() -> bool: return asked.snapshot_is_current(BEE), "bee is back")
	_check(asked.generation(BEE) > held.target.generation, "a new connection is a new generation")
	var fresh := asked.answers(key, 4, block)
	_eq(fresh.target.generation, asked.generation(BEE), "a fresh answer is aimed at the machine as it is now")
	for kind in block:
		_eq(_reason(fresh.refusal(kind)), _reason(R.NONE), "after: a fresh %s may go" % _kind(kind))
		_eq(_reason(asked.command_refusal(key, kind)), _reason(R.NONE), "and the one question says so")
	_eq(_reason(held.refusal(K.SPLIT)), _reason(R.NONE), "the held answer still reads as it was asked")
	var sent: Array[CommandTicket] = [
		asked.split_pane(held.splitting()),
		asked.close_pane(held.closing()),
		asked.create_space(held.spacing()),
		asked.create_worktree(held.branching("lane/x")),
		asked.focus_pane(held.target.focusing()),
	]
	for ticket in sent:
		_eq(_reason(_refusal(ticket)), _reason(R.MACHINE_REPLACED), "%s aimed before" % _kind(ticket.context.kind))
	await _frames(3)
	_eq(_sequence("control-b"), PackedStringArray(), "nothing reached bee")


## Between the press and the release: the command aimed at the press carries
## the side, the scope, the directory and the terminal read then, and the
## boundary refuses it when the fleet's facts at the release say otherwise. A
## fresh answer says the changed pane may take the command; it is another
## command, with other values.
func test_a_change_between_press_and_release_refuses_the_aimed_command() -> void:
	_fakes("snapshot_basic", [])
	var asked := await _bare_fleet()
	var key := _on(BEE, "alpha:p3")
	var block: Array[CommandContext.Kind] = [K.SPLIT, K.CLOSE, K.SPACE, K.WORKTREE]
	var pressed := asked.answers(key, 2, block)
	var raw := _changed(_without(_raw(), "alpha:p2"), "alpha:p3", {"cwd": "/home/tester/elsewhere"})
	raw = _sized(raw, "alpha:p3", 60, 40)
	_serve("control-b", raw)
	await _until(func() -> bool: return asked.pane_cwd(key) == "/home/tester/elsewhere", "the shell moved")
	_eq(_reason(_refusal(asked.split_pane(pressed.splitting()))), _reason(R.DIRECTION_INVALID), "another side now")
	_eq(_reason(_refusal(asked.close_pane(pressed.closing()))), _reason(R.SCOPE_CHANGED), "another close now")
	_eq(_reason(_refusal(asked.create_space(pressed.spacing()))), _reason(R.CWD_CHANGED), "another directory now")
	var now := asked.answers(key, 2, block)
	for kind in block:
		_eq(_reason(now.refusal(kind)), _reason(R.NONE), "a fresh %s may go" % _kind(kind))
	_eq([pressed.direction, now.direction], ["right", "down"], "the side read at each look")
	_eq([pressed.cwd, now.cwd], ["/home/tester/alpha", "/home/tester/elsewhere"], "the directory likewise")
	_check(pressed.scope.signature() != now.scope.signature(), "and the scope")
	# Another terminal under the same pane id: everything aimed before is refused.
	_serve("control-b", _changed(raw, "alpha:p3", {"terminal_id": "term-other"}))
	await _until(
		func() -> bool: return asked.context_for(key, 2).identity_key != now.target.identity_key, "a new terminal"
	)
	var sent: Array[CommandTicket] = [
		asked.split_pane(now.splitting()),
		asked.close_pane(now.closing()),
		asked.create_space(now.spacing()),
		asked.create_worktree(now.branching("lane/x")),
	]
	for ticket in sent:
		_eq(
			_reason(_refusal(ticket)),
			_reason(R.IDENTITY_CHANGED),
			"%s aimed at the old one" % _kind(ticket.context.kind)
		)
	for kind in block:
		_eq(_reason(asked.command_refusal(key, kind)), _reason(R.NONE), "asked now, %s may go" % _kind(kind))
	await _frames(3)
	_eq(_sequence("control-b"), PackedStringArray(), "nothing reached bee")


## During the re-read: an answer key aimed with the preview frozen at the
## press keeps that context to the end. The screen reading otherwise when the
## re-read comes back, or the agent no longer asking by then, refuses it
## there; nothing is typed, and the pane owes a look.
func test_a_change_during_the_reread_refuses_the_aimed_answer() -> void:
	_fakes("snapshot_basic", ["pane.read", "pane.send_keys"])
	_ctl("control-b", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
	var asked := await _bare_fleet()
	var key := _on(BEE, "bravo:p1")
	var check := HerdrCommands.CHECK_SUFFIX
	var other := {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION + "really?\n"}
	var stages: Array = [
		[{"preview": other}, R.SCREEN_CHANGED, "the screen reads otherwise"],
		[
			{"status": {"pane_id": "bravo:p1", "agent_status": "working"}, "seconds": 0.4},
			R.NOT_ASKING,
			"no longer asking"
		],
	]
	for stage: Array in stages:
		var what: String = stage[2]
		var expected: CommandRefusal.Reason = stage[1]
		_ctl("control-b", "set_preview", {"pane_id": "bravo:p1", "source": "detection", "text": QUESTION})
		var said := asked.answers(key, 3)
		var read := asked.read_pane(said.target.reading(CommandContext.SOURCE_DETECTION, HerdrCommands.READ_LINES_MAX))
		await _until(read.is_finished, "the preview")
		asked.preview_shown(read)
		var seen := CommandPreview.of(read, 1)
		_eq(_reason(asked.command_refusal(key, K.KEYS)), _reason(R.NONE), what + ": a key may go at the press")
		var hook: Dictionary = stage[0]
		hook = hook.duplicate(true)
		hook["action"] = "stage"
		hook["method"] = "pane.read"
		hook["id_suffix"] = check
		_ctl("control-b", "next", hook)
		var aimed := said.target.keying("1", seen)
		var ticket := asked.send_keys(aimed)
		_eq(ticket.state, CommandTicket.State.UNSENT, what + ": passed at the press")
		_eq(_reason(asked.command_refusal(key, K.KEYS)), _reason(R.IN_FLIGHT), what + ": the pane's one write")
		await _until(ticket.is_finished, what)
		_eq(_reason(_refusal(ticket)), _reason(expected), what + ": refused when the re-read came back")
		_check(ticket.context == aimed and ticket.context.seen == seen, what + ": the press's own context to the end")
		_eq(_inputs("control-b"), [], what + ": nothing typed")
		_eq(_reason(asked.command_refusal(key, K.SPLIT)), _reason(R.LOOK_FIRST), what + ": a look is owed")
		await _pass_msec(HerdrCommands.LOOK_DELAY_MSEC + 50)
		await _look_at(asked, key)
	_eq(_count("control-b", "pane.send_keys"), 0, "no key reached bee")


# --- the card's ladder, with no scene and no fleet -----------------------------------


## A preview as a press would freeze it: `text` read from `source`.
func _frozen(source: String, text: String, cut := false) -> CommandPreview:
	var aimed := CommandContext.aimed("local", 1, _on("local", "p"), "p", "p", "identity", 1, "term")
	var ticket := CommandTicket.new(aimed.reading(source, 12))
	var read := PaneReadResult.new()
	read.text = text
	read.bytes = text.to_utf8_buffer().size()
	read.cut = cut
	ticket.read = read
	ticket.state = CommandTicket.State.ACCEPTED
	return CommandPreview.of(ticket, 1)


func _scope_of(terminal_id: String, panes_in_tab := 2) -> CloseScope:
	var scope := CloseScope.new()
	scope.missing = false
	scope.terminal_id = terminal_id
	scope.tab_id = "t"
	scope.workspace_id = "w"
	scope.panes_in_tab = panes_in_tab
	scope.tabs_in_space = 1
	scope.state = CloseScope.SHELL
	scope.space_number = 2
	scope.level_label = "2"
	return scope


## Answers as a fleet would give them for a pane where everything may go.
func _answered() -> CommandAnswers:
	var said := CommandAnswers.new()
	said.target = CommandContext.aimed("local", 5, _on("local", "p"), "p", "p", "identity", 1, "term")
	said.scope = _scope_of("term")
	said.direction = "right"
	said.cwd = "/work/repo"
	said.workspace_id = "w"
	said.wire_workspace_id = "w"
	said.names["claude"] = "claude-3"
	said.names["codex"] = "codex-1"
	for kind in PRESSED:
		if kind != K.START:
			said.answer(kind, R.NONE)
	said.answer(K.START, R.NONE, "claude")
	said.answer(K.START, R.NONE, "codex")
	return said


func _shown_pane() -> PaneModel:
	var pane := PaneModel.new()
	pane.key = _on("local", "p")
	pane.pane_id = "p"
	pane.terminal_id = "term"
	return pane


## What a card on binding 1 shows of that pane, a prompt on its preview.
func _card_view(form: OfficePaneInspector.Form, said: CommandAnswers = null) -> CardActions.View:
	var view := CardActions.View.new()
	view.pane = _shown_pane()
	view.binding = 1
	view.form = form
	view.text = "$ \n"
	view.frozen = _frozen(CommandContext.SOURCE_RECENT, view.text)
	view.shown = true
	view.now_msec = 1000
	view.answers = _answered() if said == null else said
	return view


## The first refusal, in the card's order: its own state, the fleet's word,
## the preview, what was typed. Rows where several steps refuse at once, and
## the kinds that are checked against no preview at all.
func test_the_ladder_answers_with_its_first_refusal() -> void:
	var recent := _frozen(CommandContext.SOURCE_RECENT, "$ \n")
	var cut := _frozen(CommandContext.SOURCE_RECENT, "$ \n", true)
	# [kind, card, seam, shown, frozen, typed, the answer, what]
	var rows: Array = [
		[
			K.LINE,
			R.UNSEEN,
			R.MACHINE_OFFLINE,
			true,
			recent,
			R.NONE,
			R.UNSEEN,
			"a pane not picked, on a machine that dropped"
		],
		[K.LINE, R.NONE, R.LOOK_FIRST, true, cut, R.NONE, R.LOOK_FIRST, "a look owed, and the preview cut"],
		[K.LINE, R.NONE, R.AGENT_BUSY, true, recent, R.LINE_BLANK, R.AGENT_BUSY, "a working agent, a blank reply"],
		[
			K.WORKTREE,
			R.NONE,
			R.MACHINE_OFFLINE,
			false,
			null,
			R.BRANCH_BLANK,
			R.MACHINE_OFFLINE,
			"offline, no branch typed"
		],
		[K.START, R.IN_FLIGHT, R.KIND_UNKNOWN, false, null, R.NO_PROMPT, R.IN_FLIGHT, "a write of the card on its way"],
		[K.START, R.READ_ONLY, R.READ_ONLY, true, recent, R.NONE, R.READ_ONLY, "read-only"],
		[K.START, R.NONE, R.NONE, false, recent, R.PROMPT_UNSURE, R.UNSEEN, "nothing shown, an unsure prompt"],
		[K.START, R.NONE, R.NONE, true, cut, R.NO_PROMPT, R.UNSEEN, "a cut preview before its prompt"],
		[K.START, R.NONE, R.NONE, true, recent, R.PROMPT_UNSURE, R.PROMPT_UNSURE, "only the prompt"],
		[K.WORKTREE, R.NONE, R.NONE, false, null, R.BRANCH_SHAPE, R.BRANCH_SHAPE, "only the branch"],
		[K.KEYS, R.NONE, R.NOT_ASKING, false, null, R.NONE, R.NOT_ASKING, "not asking, nothing shown"],
		[K.KEYS, R.NONE, R.NONE, true, recent, R.NONE, R.UNSEEN, "keys against the recent output"],
		[K.LINE, R.NONE, R.NONE, true, recent, R.NONE, R.NONE, "everything in order"],
	]
	for kind: CommandContext.Kind in [K.SPLIT, K.CLOSE, K.SPACE, K.WORKTREE]:
		rows.append([kind, R.NONE, R.NONE, false, null, R.NONE, R.NONE, "%s reads no screen: no preview" % _kind(kind)])
		rows.append([kind, R.NONE, R.NONE, true, cut, R.NONE, R.NONE, "%s reads no screen: a cut one" % _kind(kind)])
		rows.append(
			[kind, R.NONE, R.LOOK_FIRST, false, null, R.NONE, R.LOOK_FIRST, "%s waits for a look" % _kind(kind)]
		)
		rows.append(
			[
				kind,
				R.IDENTITY_CHANGED,
				R.NONE,
				true,
				recent,
				R.NONE,
				R.IDENTITY_CHANGED,
				"%s on a taken pane" % _kind(kind)
			]
		)
	for row: Array in rows:
		var kind: CommandContext.Kind = row[0]
		var card: CommandRefusal.Reason = row[1]
		var seam: CommandRefusal.Reason = row[2]
		var shown: bool = row[3]
		var frozen: CommandPreview = row[4]
		var typed: CommandRefusal.Reason = row[5]
		var expected: CommandRefusal.Reason = row[6]
		var what: String = row[7]
		_eq(_reason(CardActions.ladder(kind, card, seam, shown, frozen, typed)), _reason(expected), what)


## Which preview each kind is checked against: the whole `detection` text for
## answer keys, the recent output for a line and a start, none for the rest;
## not shown, none frozen, cut and the other source all say UNSEEN.
func test_the_preview_step_asks_each_kind_for_its_own_source() -> void:
	var recent := _frozen(CommandContext.SOURCE_RECENT, "$ \n")
	var detection := _frozen(CommandContext.SOURCE_DETECTION, QUESTION)
	var wanted: Dictionary[CommandContext.Kind, CommandPreview] = {K.KEYS: detection, K.LINE: recent, K.START: recent}
	var wrong: Dictionary[CommandContext.Kind, CommandPreview] = {K.KEYS: recent, K.LINE: detection, K.START: detection}
	for kind in PRESSED:
		var named := _kind(kind)
		if not wanted.has(kind):
			for frozen: CommandPreview in [null, recent, detection, _frozen(CommandContext.SOURCE_RECENT, "x", true)]:
				for shown: bool in [false, true]:
					_eq(
						_reason(CardActions.shown_refusal(kind, shown, frozen)),
						_reason(R.NONE),
						named + " reads no screen"
					)
			continue
		var right := wanted[kind]
		_eq(_reason(CardActions.shown_refusal(kind, true, right)), _reason(R.NONE), named + ": its source, shown")
		_eq(_reason(CardActions.shown_refusal(kind, false, right)), _reason(R.UNSEEN), named + ": not shown")
		_eq(_reason(CardActions.shown_refusal(kind, true, null)), _reason(R.UNSEEN), named + ": none frozen")
		_eq(
			_reason(CardActions.shown_refusal(kind, true, wrong[kind])), _reason(R.UNSEEN), named + ": the other source"
		)
		var cut := _frozen(right.source, right.text, true)
		_eq(_reason(CardActions.shown_refusal(kind, true, cut)), _reason(R.UNSEEN), named + ": cut")


## The five refusals of the launch block are the ladder over a View: the
## card's own refusal, the View's answer for the kind, the preview for a
## start only, then the prompt or the branch. A View whose answers no fleet
## gave refuses everything; a block's form names the kinds it asks about.
func test_a_views_refusals_come_through_the_ladder() -> void:
	var actions := CardActions.new()
	var plain := PromptState.of_text("$ \n")
	var unsure := PromptState.of_text("still thinking\n")
	var none := PromptState.new()
	var view := _card_view(OfficePaneInspector.Form.START)
	_eq(_reason(actions.launch_refusal(view, "claude", plain, false)), _reason(R.NONE), "a start at a prompt")
	_eq(_reason(actions.launch_refusal(view, "claude", unsure, false)), _reason(R.PROMPT_UNSURE), "an unsure prompt")
	_eq(_reason(actions.launch_refusal(view, "claude", unsure, true)), _reason(R.NONE), "confirmed")
	_eq(_reason(actions.launch_refusal(view, "claude", none, true)), _reason(R.NO_PROMPT), "no prompt, even confirmed")
	_eq(_reason(actions.launch_refusal(view, "aider", plain, false)), _reason(R.NOT_CONNECTED), "a kind never answered")
	view.answers.answer(K.START, R.KIND_UNKNOWN, "codex")
	_eq(
		_reason(actions.launch_refusal(view, "codex", unsure, false)),
		_reason(R.KIND_UNKNOWN),
		"the fleet before the prompt"
	)
	_eq(_reason(actions.launch_refusal(view, "claude", plain, false)), _reason(R.NONE), "each kind its own answer")
	view.shown = false
	_eq(
		_reason(actions.launch_refusal(view, "claude", unsure, false)),
		_reason(R.UNSEEN),
		"the preview before the prompt"
	)
	_eq(
		_reason(actions.launch_refusal(view, "codex", plain, false)),
		_reason(R.KIND_UNKNOWN),
		"the fleet before the preview"
	)
	_eq(_reason(actions.split_refusal(view)), _reason(R.NONE), "a split reads no screen")
	_eq(_reason(actions.close_refusal(view)), _reason(R.NONE), "nor a close")
	_eq(_reason(actions.space_refusal(view)), _reason(R.NONE), "nor a new space")
	view.branch = "lane/x"
	_eq(_reason(actions.worktree_refusal(view)), _reason(R.NONE), "nor a worktree, on a branch that may go")
	view.branch = ""
	_eq(_reason(actions.worktree_refusal(view)), _reason(R.BRANCH_BLANK), "no branch typed")
	view.branch = "two words"
	_eq(_reason(actions.worktree_refusal(view)), _reason(R.BRANCH_BLANK), "whitespace in it")
	view.branch = ".hidden"
	_eq(_reason(actions.worktree_refusal(view)), _reason(R.BRANCH_SHAPE), "a shape git refuses")
	view.answers.answer(K.WORKTREE, R.MACHINE_OFFLINE)
	_eq(_reason(actions.worktree_refusal(view)), _reason(R.MACHINE_OFFLINE), "the fleet before the branch")
	view.answers.answer(K.CLOSE, R.GROUP_PARENT)
	view.answers.answer(K.SPACE, R.CWD_UNCLEAN)
	view.answers.answer(K.SPLIT, R.PANE_TOO_SMALL)
	_eq(
		[
			_reason(actions.close_refusal(view)),
			_reason(actions.space_refusal(view)),
			_reason(actions.split_refusal(view))
		],
		[_reason(R.GROUP_PARENT), _reason(R.CWD_UNCLEAN), _reason(R.PANE_TOO_SMALL)],
		"each kind reads its own answer"
	)
	view.card_refusal = R.IN_FLIGHT
	for said: CommandRefusal.Reason in [
		actions.launch_refusal(view, "claude", plain, false),
		actions.split_refusal(view),
		actions.close_refusal(view),
		actions.space_refusal(view),
		actions.worktree_refusal(view),
	]:
		_eq(_reason(said), _reason(R.IN_FLIGHT), "the card's own refusal first")
	_eq(_reason(CardActions.refusal(view, K.KEYS)), _reason(R.IN_FLIGHT), "for an answer key as well")
	# Answers no fleet gave: a card with no fleet says so itself, and a View
	# that forgot to would still let nothing through.
	var bare := CardActions.View.new()
	for kind in PRESSED:
		_eq(
			_reason(CardActions.refusal(bare, kind, "claude")), _reason(R.NOT_CONNECTED), "%s: no answers" % _kind(kind)
		)
	# What each form asks the fleet about.
	var manage: Array[CommandContext.Kind] = [K.CLOSE, K.SPACE, K.WORKTREE]
	var start: Array[CommandContext.Kind] = [K.START, K.CLOSE, K.SPACE, K.WORKTREE]
	var split: Array[CommandContext.Kind] = [K.SPLIT, K.CLOSE, K.SPACE, K.WORKTREE]
	var nothing: Array[CommandContext.Kind] = []
	_eq(CardActions.asked(OfficePaneInspector.Form.NONE), nothing, "no block asks nothing")
	_eq(CardActions.asked(OfficePaneInspector.Form.START), start, "a shell's block")
	_eq(CardActions.asked(OfficePaneInspector.Form.SPLIT), split, "an agent's block")
	_eq(CardActions.asked(OfficePaneInspector.Form.MANAGE_ONLY), manage, "the manage rows alone")


## A press aims the command from the View's answers alone: the target the
## fleet aimed at that look, the side, the scope, the directory, the
## workspace and the name read with it. Nothing is aimed when the ladder
## refuses, or from another form's block.
func test_a_press_aims_from_the_answers_alone() -> void:
	var actions := CardActions.new()
	actions.launch_kinds = PackedStringArray(["claude", "codex"])
	# A split.
	var split_view := _card_view(OfficePaneInspector.Form.SPLIT)
	var split := actions.aim_split(split_view, null)
	_eq(
		[split.context.kind, split.context.direction, split.context.generation, split.context.pane_key],
		[K.SPLIT, "right", 5, _on("local", "p")],
		"the split, to the side read"
	)
	split_view.answers.direction = ""
	_check(actions.aim_split(split_view, null) == null, "no side, no split")
	split_view.answers.direction = "down"
	split_view.answers.answer(K.SPLIT, R.LOOK_FIRST)
	_check(actions.aim_split(split_view, null) == null, "a look owed, no split")
	_check(actions.aim_split(_card_view(OfficePaneInspector.Form.START), null) == null, "no split from a shell's block")
	# A start.
	var view := _card_view(OfficePaneInspector.Form.START)
	var start := actions.aim_start(view, null, 1)
	_eq(
		[start.context.kind, start.context.agent_kind, start.context.agent_name, start.context.confirmed],
		[K.START, "codex", "codex-1", false],
		"the start of the kind pressed, under the name read"
	)
	_check(start.context.seen == view.frozen, "aimed at the preview shown")
	_check(actions.aim_start(view, null, 2) == null and actions.aim_start(view, null, -1) == null, "no such button")
	_check(actions.aim_start(_card_view(OfficePaneInspector.Form.SPLIT), null, 0) == null, "no start beside an agent")
	view.answers.answer(K.START, R.NAME_TAKEN, "claude")
	_check(actions.aim_start(view, null, 0) == null, "the fleet's refusal aims nothing")
	_check(actions.aim_start(view, null, 1) != null, "the other kind still goes")
	# A close: the first press only arms, the second aims.
	var close_view := _card_view(OfficePaneInspector.Form.MANAGE_ONLY)
	var first := actions.aim_close(close_view, null)
	_eq([first.arms_close, first.context, first.binding], [true, null, 1], "a first click sends nothing")
	_check(first.scope == close_view.answers.scope, "it keeps the scope it read")
	actions.arm_close(close_view, first)
	var second := actions.aim_close(close_view, null)
	_eq([second.arms_close, second.context.kind], [false, K.CLOSE], "armed, the close")
	_check(second.context.scope == close_view.answers.scope, "taking the scope read with it")
	var parent := _card_view(OfficePaneInspector.Form.SPLIT)
	parent.answers.scope.group_parent = true
	_check(actions.aim_close(parent, null) == null, "never the repo's own space with mezzanines open")
	var gone := _card_view(OfficePaneInspector.Form.SPLIT)
	gone.answers.scope = CloseScope.new()
	_check(actions.aim_close(gone, null) == null, "no scope, no close")
	_check(actions.aim_close(_card_view(OfficePaneInspector.Form.NONE), null) == null, "no block, no close")
	# A new space and a new worktree.
	var manage := _card_view(OfficePaneInspector.Form.SPLIT)
	manage.branch = "lane/x"
	var space := actions.aim_space(manage, null)
	_eq([space.context.kind, space.context.cwd], [K.SPACE, "/work/repo"], "the space, in the directory read")
	var tree := actions.aim_worktree(manage, null)
	_eq(
		[tree.context.kind, tree.context.workspace_id, tree.context.wire_workspace_id, tree.context.branch],
		[K.WORKTREE, "w", "w", "lane/x"],
		"the worktree, of the workspace read, on the branch typed"
	)
	manage.branch = "HEAD"
	_check(actions.aim_worktree(manage, null) == null, "a branch that cannot go aims nothing")
	_check(actions.aim_space(manage, null) != null, "the space does not read the branch")
	manage.card_refusal = R.UNSEEN
	_check(actions.aim_space(manage, null) == null and actions.aim_close(manage, null) == null, "a pane not picked")
	var none := _card_view(OfficePaneInspector.Form.NONE)
	none.branch = "lane/x"
	_check(actions.aim_space(none, null) == null and actions.aim_worktree(none, null) == null, "no block, no press")


## The start's confirm: a first click on an unsure prompt arms it at the
## release, if the card still shows what it showed at the press; a second on
## that kind then aims the start as confirmed. It holds for that kind, that
## binding, that text, while shown and offered, for ten seconds.
func test_a_start_confirm_arms_holds_and_lapses() -> void:
	var actions := CardActions.new()
	actions.launch_kinds = PackedStringArray(["claude", "codex"])
	var view := _card_view(OfficePaneInspector.Form.START)
	view.text = "still thinking\n"
	view.frozen = _frozen(CommandContext.SOURCE_RECENT, view.text)
	var first := actions.aim_start(view, null, 0)
	_eq([first.arms, first.context, first.text, first.binding], ["claude", null, view.text, 1], "an unsure prompt arms")
	# What the release must still show, one change at a time: nothing arms.
	var later := _card_view(OfficePaneInspector.Form.START)
	later.text = view.text
	later.frozen = view.frozen
	var changes: Array = [["binding", 2], ["form", OfficePaneInspector.Form.SPLIT], ["shown", false], ["text", "$ \n"]]
	for change: Array in changes:
		var field: String = change[0]
		var before: Variant = later.get(field)
		later.set(field, change[1])
		actions.arm(later, first)
		_check(actions.confirm == null, "the %s changed by the release: not armed" % field)
		later.set(field, before)
	actions.arm(later, first)
	_check(actions.confirm != null, "the same card at the release: armed")
	_eq(
		[actions.confirm.kind, actions.confirm.binding, actions.confirm.text, actions.confirm.last_line],
		["claude", 1, view.text, "still thinking"],
		"for that kind, binding and screen"
	)
	_eq(actions.confirm.until_msec, 1000 + int(LaunchBlock.CONFIRM_SECONDS * 1000), "for ten seconds")
	_check(actions.confirm_holds(view, "claude"), "it holds")
	_check(not actions.confirm_holds(view, "codex"), "for its kind only")
	var second := actions.aim_start(view, null, 0)
	_eq(
		[second.arms, second.context.confirmed, second.context.agent_kind],
		["", true, "claude"],
		"a second click sends, confirmed"
	)
	_eq(actions.aim_start(view, null, 1).arms, "codex", "another kind is another first click")
	for change: Array in changes:
		var field: String = change[0]
		var before: Variant = view.get(field)
		view.set(field, change[1])
		_check(not actions.confirm_holds(view, "claude"), "the %s changed: it no longer holds" % field)
		view.set(field, before)
	view.now_msec = actions.confirm.until_msec - 1
	_check(actions.confirm_holds(view, "claude"), "a millisecond short of ten seconds")
	_check(not actions.expire(view.now_msec), "nothing lapsed yet")
	view.now_msec = actions.confirm.until_msec
	_check(not actions.confirm_holds(view, "claude"), "at ten seconds it does not hold")
	_check(actions.expire(view.now_msec) and actions.confirm == null, "and lapses")
	_check(not actions.expire(view.now_msec), "once")
	actions.arm(later, first)
	actions.clear()
	_check(actions.confirm == null, "a new binding clears it")


## The close's confirm: the first click's release arms it if the card is on
## the same binding and the close still takes the same with it; it holds for
## that binding, that terminal and agent, that scope, while the block shows,
## for ten seconds. Only one confirm is armed at a time.
func test_a_close_confirm_arms_holds_and_lapses() -> void:
	var actions := CardActions.new()
	actions.launch_kinds = PackedStringArray(["claude"])
	var view := _card_view(OfficePaneInspector.Form.START)
	var first := actions.aim_close(view, null)
	var moved := _card_view(OfficePaneInspector.Form.START)
	moved.binding = 2
	actions.arm_close(moved, first)
	_check(actions.close_confirm == null, "another binding by the release: not armed")
	var grown := _card_view(OfficePaneInspector.Form.START)
	grown.answers.scope = _scope_of("term", 3)
	actions.arm_close(grown, first)
	_check(actions.close_confirm == null, "another scope by the release: not armed")
	var unbound := _card_view(OfficePaneInspector.Form.START)
	unbound.pane = null
	actions.arm_close(unbound, first)
	_check(actions.close_confirm == null, "no pane by the release: not armed")
	actions.arm_close(view, first)
	_check(actions.close_confirm != null, "the same card and scope: armed")
	_eq(
		[actions.close_confirm.binding, actions.close_confirm.identity_key, actions.close_confirm.scope_signature],
		[1, view.pane.identity_key(), view.answers.scope.signature()],
		"for that binding, identity and scope"
	)
	_eq(actions.close_confirm.until_msec, 1000 + int(LaunchBlock.CONFIRM_SECONDS * 1000), "for ten seconds")
	_check(actions.close_confirm_holds(view), "it holds")
	_check(not actions.close_confirm_holds(moved), "not on another binding")
	_check(not actions.close_confirm_holds(grown), "not for another scope")
	_check(not actions.close_confirm_holds(unbound), "not without a pane")
	_check(not actions.close_confirm_holds(_card_view(OfficePaneInspector.Form.NONE)), "not without the block")
	_check(actions.close_confirm_holds(_card_view(OfficePaneInspector.Form.MANAGE_ONLY)), "under any block")
	var taken := _card_view(OfficePaneInspector.Form.START)
	taken.pane.terminal_id = "term-other"
	_check(not actions.close_confirm_holds(taken), "not for another terminal under the pane id")
	view.now_msec = actions.close_confirm.until_msec - 1
	_check(actions.close_confirm_holds(view), "a millisecond short of ten seconds")
	view.now_msec = actions.close_confirm.until_msec
	_check(not actions.close_confirm_holds(view), "at ten seconds it does not hold")
	_check(actions.aim_close(view, null).arms_close, "so a click is a first click again")
	_check(actions.expire(view.now_msec) and actions.close_confirm == null, "and it lapses")
	# One confirm at a time.
	view.now_msec = 1000
	actions.arm_close(view, first)
	var unsure := _card_view(OfficePaneInspector.Form.START)
	unsure.text = "still thinking\n"
	unsure.frozen = _frozen(CommandContext.SOURCE_RECENT, unsure.text)
	actions.arm(unsure, actions.aim_start(unsure, null, 0))
	_check(actions.confirm != null and actions.close_confirm == null, "arming a start drops the close's")
	actions.arm_close(view, first)
	_check(actions.confirm == null and actions.close_confirm != null, "and the other way round")
	actions.clear()
	_check(actions.close_confirm == null, "a new binding clears it")


## What a launch line says; `(none)` for no line.
func _said(line: CardActions.Said) -> String:
	return "(none)" if line == null else line.text


## The footer's launch line reads the answers: the pane's last start while it
## is still its last write, how it is going, and whether a look is owed.
func test_the_launch_line_reads_the_answers() -> void:
	var actions := CardActions.new()
	var view := _card_view(OfficePaneInspector.Form.NONE)
	_check(actions.launch_line(view) == null, "no start, no line")
	var aimed := view.answers.starting("claude", view.frozen)
	var watch := LaunchWatch.new()
	watch.name = "claude-3"
	watch.started_msec = 400
	watch.ticket = CommandTicket.new(aimed)
	watch.ticket.state = CommandTicket.State.ACCEPTED
	view.answers.launch = watch
	view.answers.last_write = CommandTicket.new(aimed)
	_check(actions.launch_line(view) == null, "another write since: no line")
	view.answers.last_write = watch.ticket
	view.answers.launch_outcome = LaunchWatch.Outcome.PENDING
	var going := actions.launch_line(view)
	_eq(_said(going), LaunchWatch.text(LaunchWatch.Outcome.PENDING, watch, 1000), "launching, with its seconds")
	_check(going != null and going.detail.begins_with(going.text + ": "), "and why, for the tooltip")
	view.answers.launch_outcome = LaunchWatch.Outcome.READY
	_eq(_said(actions.launch_line(view)), "claude-3 started", "over: said on the binding that first saw it")
	view.binding = 2
	_check(actions.launch_line(view) == null, "not on a later binding")
	view.answers.must_look = true
	_eq(_said(actions.launch_line(view)), "claude-3 started", "but while a look is owed")
	view.answers.launch_outcome = LaunchWatch.Outcome.PENDING
	watch.ticket.state = CommandTicket.State.UNKNOWN
	_eq(_said(actions.launch_line(view)), CardWords.write_outcome(watch.ticket), "a lost answer nothing shows yet")
	view.pane = null
	_check(actions.launch_line(view) == null, "no pane, no line")


## The manage rows' words read the answers: the close's scope, the shell's
## directory, each button's reason, the armed confirm.
func test_the_manage_words_read_the_answers() -> void:
	var actions := CardActions.new()
	var view := _card_view(OfficePaneInspector.Form.SPLIT)
	var words := actions.manage_words(view, " on bee", "bee")
	_eq(
		[_reason(words.close_reason), _reason(words.space_reason), _reason(words.worktree_reason)],
		[_reason(R.NONE), _reason(R.NONE), _reason(R.BRANCH_BLANK)],
		"close and space may go; no branch typed"
	)
	_eq(words.close_text, LaunchBlock.close_text(view.answers.scope, false), "the close button, not armed")
	_check(words.space_tip.contains("a space with one shell in /work/repo."), "the space names the directory read")
	_eq([words.confirm_note, words.note], ["", ""], "no confirm, nothing typed")
	view.answers.cwd = ""
	_check(actions.manage_words(view, "", "bee").space_tip.contains("in this pane's directory."), "no directory read")
	view.branch = "lane/x"
	words = actions.manage_words(view, "", "bee")
	_eq(_reason(words.worktree_reason), _reason(R.NONE), "a branch that may go")
	_eq(words.note, LaunchBlock.WORKTREE_NOTE % "lane/x", "and the note says it")
	view.answers.answer(K.WORKTREE, R.MACHINE_OFFLINE)
	view.branch = ""
	_eq(
		_reason(actions.manage_words(view, "", "bee").worktree_reason),
		_reason(R.MACHINE_OFFLINE),
		"offline with no branch typed: the machine is said"
	)
	view.answers.scope.group_parent = true
	words = actions.manage_words(view, "", "bee")
	_eq(_reason(words.close_reason), _reason(R.GROUP_PARENT), "the repo's own space, by the scope read")
	_check(words.close_tip.ends_with("\nLast pane of the repo's own space 2."), "named in the tooltip")
	view.answers.answer(K.CLOSE, R.LOOK_FIRST)
	_eq(_reason(actions.manage_words(view, "", "bee").close_reason), _reason(R.LOOK_FIRST), "the ladder's word first")
	var armed := _card_view(OfficePaneInspector.Form.SPLIT)
	actions.arm_close(armed, actions.aim_close(armed, null))
	words = actions.manage_words(armed, "", "bee")
	_eq(words.close_text, LaunchBlock.close_text(armed.answers.scope, true), "armed: the button says click again")
	_eq(words.confirm_note, LaunchBlock.close_note(armed.answers.scope), "and the note what closes")
	_eq(words.confirm_line, LaunchBlock.close_line(armed.answers.scope, "p"), "and the line")


# === ABOVE: CASES THAT NAME THIS LANE'S INTERFACE ===

# --- the closing sum ------------------------------------------------------------------


## Sums up both fakes over the whole run, so it has to be the last `test_`
## function in this file: cases run in source order. Nothing reached them that
## no case opened, and no violation.
func test_only_the_requests_this_suite_allowed() -> void:
	var opened := ["pane.read", "pane.focus", "pane.send_keys"]
	for which: String in ["control-a", "control-b"]:
		var stats := _ctl(which, "stats")
		for method: String in _list(stats, "lifetime_methods"):
			_check(method in READ_ONLY_METHODS or method in opened, "%s heard %s" % [which, method])
		_eq(_list(stats, "violations"), provoked[which], "%s: only the violations a case provoked" % which)
