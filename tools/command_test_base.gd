extends "res://tools/machine_test_base.gd"
## What tools/test_commands.gd, tools/test_raw_input.gd, tools/test_answers.gd,
## tools/test_bubbles.gd and the other write-boundary suites stand on (and
## tools/capture_card.gd's pictures): offices run as an operator (or
## `--read-only`) against the suite's own two fake herdrs, the write boundary
## driven on synthetic time, real clicks on the agent card, and reads of what
## each fake was asked. Built on tools/machine_test_base.gd for its fake
## control, its waits and its real-input desk and minimap picks; holds no cases.

const MANIFEST := "res://assets/daylight/manifest.json"
const READ_ONLY_METHODS := ["ping", "session.snapshot", "events.subscribe"]
const OPERABLE := [
	"pane.read",
	"pane.focus",
	"pane.send_keys",
	"pane.send_input",
	"pane.send_text",
	"agent.prompt",
	"agent.start",
	"pane.split",
	"agent.get",
	"pane.close",
	"workspace.create",
	"worktree.create",
]
## The input methods: answer mode sends keys and prompts, the terminal monitor
## keys, text and pastes.
const INPUTS := ["pane.send_keys", "pane.send_input", "pane.send_text", "agent.prompt"]
## A blocked agent's question as its terminal shows it: scripted, never a real one.
const QUESTION := "Bash command\n\n  make capture OUT=/tmp/shots\n\nDo you want to proceed?\n> 1. Yes\n  2. No\n"
## The debug machine every operator office here shows next to Local.
const BEE := "socket:bee"
## What a case's own terminal text carries so the privacy case can look for it.
const SENTINEL := "SENTINEL-7f3e-terminal-secret"
## The same, as one word: where a malformed reply puts it, JSON.parse_string()
## would quote it into the log, and it quotes letters only (measured on 4.7.2).
const SENTINEL_WORD := "sentinelsecretword"

## Violations a case provoked on purpose, per control socket: the closing case
## expects exactly these and nothing else.
var provoked: Dictionary[String, Array] = {"control-a": [], "control-b": []}
var _offices: Array[OfficeDouble] = []


## The suites' own command line (tools/run_tests.sh): two fakes, a short work
## directory and fake_ssh; nothing here reaches anything else.
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var cut := argument.find("=")
			args[argument.substr(2, cut - 2)] = argument.substr(cut + 1)
	for name: String in ["socket-a", "control-a", "socket-b", "control-b", "work"]:
		if not args.has(name):
			print("TEST_HARNESS_ERROR: missing --%s= (use tools/run_tests.sh)" % name)
			quit(2)
			return
	# No machine list, no forward and no default socket outside this run: every
	# office here names its sockets itself and reaches nothing else. The one SSH
	# case lists its own machine and forwards through fake_ssh (`--ssh=`).
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("command-socks"))
	# Made here: an office's startup sweep takes an overridden directory as it
	# is and never creates it, so the first forward would have nowhere to listen.
	DirAccess.make_dir_recursive_absolute(args.work.path_join("command-socks"))
	OS.set_environment("HERDR_BIN_PATH", _no_herdr())
	OS.set_environment("HERDR_SOCKET_PATH", args.work.path_join("no-default-herdr.sock"))
	if args.has("ssh"):
		OS.set_environment("HERDSTEAD_SSH", args.ssh)
	MachineLink.reset_socket_directory()
	_run()


## Where the machine list would come from: nowhere, so no office here lists a machine.
func _no_herdr() -> String:
	return args.work.path_join("no-herdr-commands")


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


## Every office a case left behind goes, and with it every connection. What each
## fake was asked during the case goes into the log (method names and focus
## targets only, never text), and both start the next case empty.
func _after_case() -> void:
	for office in _offices:
		if is_instance_valid(office):
			if office.is_inside_tree():
				root.remove_child(office)
			office.free()
	_offices.clear()
	print("REQUESTS %s: A %s | B %s" % [current, _requests_seen("control-a"), _requests_seen("control-b")])
	for which: String in ["control-a", "control-b"]:
		_ctl(which, "reset", {})


## `ping x2, session.snapshot x5, pane.focus[alpha:p3]`: what fake `which` was
## asked since its last reset, methods in order of first appearance.
func _requests_seen(which: String) -> String:
	var stats := _ctl(which, "stats")
	var methods := _list(stats, "methods")
	var params := _list(stats, "params")
	var counts: Dictionary[String, int] = {}
	var focused := PackedStringArray()
	for index in methods.size():
		var method := str(methods[index])
		counts[method] = counts.get(method, 0) + 1
		if method == "pane.focus" and index < params.size() and params[index] is Dictionary:
			var focus: Dictionary = params[index]
			focused.append(str(focus.get("pane_id", "?")))
	var parts := PackedStringArray()
	for method: String in counts:
		parts.append("%s x%d" % [method, counts[method]])
	if not focused.is_empty():
		parts.append("focus targets %s" % ",".join(focused))
	# Keys by name; a line never, only that one went.
	var keys := PackedStringArray()
	for record: Variant in _list(stats, "inputs"):
		var input: Dictionary = record if record is Dictionary else {}
		if input.get("method") == "pane.send_keys":
			keys.append("%s:%s" % [input.get("pane_id"), input.get("keys")])
	if not keys.is_empty():
		parts.append("keys %s" % ",".join(keys))
	return "-" if parts.is_empty() else ", ".join(parts)


# --- fakes --------------------------------------------------------------------


## Both fakes serve `fixture` and answer `methods` beyond the read-only three.
func _fakes(fixture := "snapshot_basic", methods: Array = OPERABLE) -> void:
	for which: String in ["control-a", "control-b"]:
		_ctl(which, "reset", {"fixture": fixture})
		if not methods.is_empty():
			_ctl(which, "allow", {"methods": methods})


## The params of every `method` request fake `which` saw since its last reset, in order.
func _asked(which: String, method: String) -> Array:
	var stats := _ctl(which, "stats")
	var methods := _list(stats, "methods")
	var params := _list(stats, "params")
	var found: Array = []
	for index in methods.size():
		if methods[index] == method and index < params.size():
			found.append(params[index])
	return found


func _count(which: String, method: String) -> int:
	return _asked(which, method).size()


## Every pane.send_keys / pane.send_input fake `which` carried out since its
## last reset, in order: {method, pane_id, keys, text, id}.
func _inputs(which: String) -> Array:
	return _list(_ctl(which, "stats"), "inputs")


## Inputs both fakes carried out, together.
func _all_inputs() -> int:
	return _inputs("control-a").size() + _inputs("control-b").size()


## What fake `which` was asked beyond the read-only three, in order: a read as
## `pane.read <source> <lines>` (` check` for an input's re-read), keys as
## `pane.send_keys [..]`, a paste or a line as its byte count, a start as
## `agent.start <kind> <name>`, a split as `pane.split <direction> <target>`,
## a launch check as `agent.get <target>`, a close as `pane.close <pane_id>`, a
## space as `workspace.create <cwd> focus:<focus>`, a worktree as
## `worktree.create <workspace_id> <branch> label:<label> focus:<focus>`: the
## exact request sequence.
func _sequence(which: String) -> PackedStringArray:
	var stats := _ctl(which, "stats")
	var methods := _list(stats, "methods")
	var params := _list(stats, "params")
	var ids := _list(stats, "ids")
	var seen := PackedStringArray()
	for index in methods.size():
		var method := str(methods[index])
		if method in READ_ONLY_METHODS:
			continue
		var param: Dictionary = params[index] if index < params.size() and params[index] is Dictionary else {}
		var id := str(ids[index]) if index < ids.size() else ""
		match method:
			"pane.read":
				var tag := " check" if id.ends_with(HerdrCommands.CHECK_SUFFIX) else ""
				seen.append("pane.read %s %d%s" % [param.get("source"), _number(param, "lines"), tag])
			"pane.send_keys":
				seen.append("pane.send_keys %s" % [param.get("keys")])
			"pane.send_input":
				var bytes := str(param.get("text")).to_utf8_buffer().size()
				seen.append("pane.send_input %d bytes %s" % [bytes, param.get("keys")])
			"agent.prompt":
				seen.append("agent.prompt %d bytes" % str(param.get("text")).to_utf8_buffer().size())
			"agent.start":
				seen.append("agent.start %s %s" % [param.get("kind"), param.get("name")])
			"pane.split":
				seen.append("pane.split %s %s" % [param.get("direction"), param.get("target_pane_id")])
			"agent.get":
				seen.append("agent.get %s" % param.get("target"))
			"pane.close":
				seen.append("pane.close %s" % param.get("pane_id"))
			"workspace.create":
				seen.append("workspace.create %s focus:%s" % [param.get("cwd"), param.get("focus")])
			"worktree.create":
				seen.append(
					(
						"worktree.create %s %s label:%s focus:%s"
						% [param.get("workspace_id"), param.get("branch"), param.get("label"), param.get("focus")]
					)
				)
			_:
				seen.append(method)
	return seen


## `_sequence()` without the card's own preview reads: what gestures caused.
func _writes_seen(which: String) -> PackedStringArray:
	var seen := PackedStringArray()
	for entry in _sequence(which):
		if not entry.begins_with("pane.read ") or entry.ends_with(" check"):
			seen.append(entry)
	return seen


## A snapshot fixture as herdr sends it, to change and set_snapshot.
func _raw(fixture := "snapshot_basic") -> Dictionary:
	return _fixture(fixture)


## `raw` without pane `pane_id`: its pane and agent records gone, as herdr sends a closed pane.
func _without(raw: Dictionary, pane_id: String) -> Dictionary:
	var result := raw.duplicate(true)
	for key: String in ["panes", "agents"]:
		result[key] = _list(result, key).filter(
			func(record: Dictionary) -> bool: return record.get("pane_id") != pane_id
		)
	return result


## `raw` with pane `pane_id` changed by `changes` in both its pane and agent record.
func _changed(raw: Dictionary, pane_id: String, changes: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	for key: String in ["panes", "agents"]:
		for record: Dictionary in _list(result, key):
			if record.get("pane_id") == pane_id:
				for field: String in changes:
					if changes[field] == null:
						record.erase(field)
					else:
						record[field] = changes[field]
	return result


# --- offices ------------------------------------------------------------------


## A live office on real frames: Local on fake A and, with `bee`, the debug
## machine "bee" on fake B, both through the office's own command line
## (`--socket=`, `--machine-socket=`). An operator unless `read_only`. Without
## `settle` it comes back at once, for a case that waits for its own machines.
## `screen` is the viewport the office lays itself out in.
func _office_with(
	read_only := false, bee := true, settle := true, screen := Vector2(SCREEN), questions := false
) -> OfficeDouble:
	var line := PackedStringArray(["--socket=" + args["socket-a"]])
	if bee:
		line.append("--machine-socket=bee=" + args["socket-b"])
	if read_only:
		line.append("--read-only")
	var office := OfficeDouble.new()
	office.test_screen = screen
	office.test_args = AppArgs.parse(line)
	office.manifest_path = MANIFEST
	office.remember_theme = false
	# The bubbles' reader would add its reads to every exact request sequence;
	# only the cases about the bubbles turn it on.
	office.test_question_reads = questions
	_offices.append(office)
	root.add_child(office)
	if not settle:
		return office
	var machines := 2 if bee else 1
	await _until(
		func() -> bool: return office.fleet.size() == machines and office.fleet.live_count() == machines,
		"%d machines live and current" % machines
	)
	return office


## The last state of the last write in `office`'s audit; empty with none yet.
func _last_write(office: OfficeDouble) -> String:
	var writes := office.fleet.write_log()
	return "" if writes.is_empty() else writes[writes.size() - 1].last_state()


## Show bee's map (a click on its alpha zone's row) and pick pane `pane_id` on it with a real click;
## with `open`, then open the staff panel from its line with Enter, as a viewer
## would (it reads nothing while it is one line).
func _pick_bee(office: OfficeDouble, pane_id: String, open := true) -> void:
	if office.navigator.shown_key != BEE:
		await _floor_pick(office, HerdrFleet.pane_key(BEE, "alpha"))
	await _click_visible_pane(office, HerdrFleet.pane_key(BEE, pane_id))
	if open:
		await _open_panel(office)


## Pick Local's pane `pane_id` with a real click, on Local's map (its alpha zone's row first when another machine's is shown); with
## `open`, then open the staff panel with Enter (see _pick_bee()).
func _pick_local(office: OfficeDouble, pane_id: String, open := true) -> void:
	if office.navigator.shown_key != HerdrFleet.LOCAL:
		await _floor_pick(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, "alpha"))
	await _click_visible_pane(office, HerdrFleet.pane_key(HerdrFleet.LOCAL, pane_id))
	if open:
		await _open_panel(office)


## Pick pane `key` with a real click on its row in the agent list, opening the
## drawer by its tab first; with `open`, then open the staff panel with Enter.
## The way to another agent while answer mode's panel stands over the world's
## middle, where a desk under it takes no click; it picks as a desk click does.
func _pick_in_list(office: OfficeDouble, key: String, open := true) -> void:
	if not office.hud.drawer_open():
		var tab: Control = office.hud.get_node("%DrawerTab")
		await _click_control(tab)
		await _frames(2)
	var row := office.hud.agent_list.row_for(key)
	_check(row != null and row.is_visible_in_tree(), "the agent list shows a row for " + key)
	if row == null:
		return
	# Where the row shows: its middle, or its right end past the panel over it.
	var rect := row.get_global_rect()
	var at := rect.get_center()
	var panel := office.hud.staff.get_global_rect()
	if panel.has_point(at):
		at.x = rect.end.x - 4.0
	_check(not panel.has_point(at), "the row for %s shows beside the panel" % key)
	for down: bool in [true, false]:
		_button(at, MOUSE_BUTTON_LEFT, down)
		await process_frame
	await _frames(2)
	_eq(office.hud.inspector.shown_pane_key(), key, "the row picked " + key)
	if open:
		await _open_panel(office)


## The staff panel is one line until it is opened: Enter opens it, as a viewer
## would (capture_card.gd's _open_up()).
func _open_panel(office: OfficeDouble) -> void:
	if office.hud.card_compact():
		await _tap(KEY_ENTER)
		await _until(func() -> bool: return not office.hud.card_compact(), "the panel opened")


## The station drawn for pane `key` on the shown floor.
func _station_of(office: OfficeDouble, key: String) -> OfficeStation:
	var seat := office.floor_view.seat(key)
	if seat == null:
		_fail("no seat for " + key)
		return null
	return seat.node


## A real click on the bubble over pane `key`'s seat: brought on screen the way
## any reveal does, then a press and a release through Input at its centre.
func _click_bubble(office: OfficeDouble, key: String) -> void:
	office.reveal(key)
	await process_frame
	await process_frame
	var station := _station_of(office, key)
	var at := station.bubble_rect().get_center() - office.camera.position
	_check(office.hud.world_rect().has_point(at), "the bubble over %s is on screen at %s" % [key, at])
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = at
		event.global_position = at
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await physics_frame


## What the question reader keeps for pane `key` (its terminal now); empty for nothing.
func _question_of(office: OfficeDouble, key: String) -> String:
	var pane := office.frame.pane(key)
	if pane == null:
		return ""
	var kept := office.questions.question(key, pane.identity_key())
	return "" if kept == null else kept.text


## The pointer moved to `at` (viewport pixels), as a mouse sends it; `held`
## with the left button down, as in a drag.
func _move_pointer(at: Vector2, held := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await physics_frame
	await physics_frame


## Where the bubble over pane `key` is on screen, its middle, once revealed.
func _bubble_point(office: OfficeDouble, key: String) -> Vector2:
	office.reveal(key)
	await process_frame
	await process_frame
	return _station_of(office, key).bubble_rect().get_center() - office.camera.position


## The panes fake `which` was asked to read `source` from, in order.
func _read_panes(which: String, source := CommandContext.SOURCE_DETECTION) -> Array:
	var panes: Array = []
	for param: Variant in _asked(which, "pane.read"):
		var read: Dictionary = param if param is Dictionary else {}
		if read.get("source") == source:
			panes.append(str(read.get("pane_id")))
	return panes


func _card(office: OfficeDouble) -> OfficePaneInspector:
	return office.hud.inspector


func _switch(office: OfficeDouble) -> Button:
	return office.hud.inspector.get_node("%FocusButton")


## One of the card's answer-mode controls by unique name: `Key1`, `KeyY`,
## `KeyN`, `KeyEnter`, `SendEsc`, `SendLine`, `ReplyBox`, `AnswerButton`,
## `BestEffort`, `Answer`.
func _control(office: OfficeDouble, unique: String) -> Control:
	return office.hud.inspector.get_node("%" + unique)


func _key_button(office: OfficeDouble, unique: String) -> Button:
	return office.hud.inspector.get_node("%" + unique)


func _reply_box(office: OfficeDouble) -> LineEdit:
	return office.hud.inspector.get_node("%ReplyBox")


## A picked, blocked agent on bee whose card shows its whole question, ready
## for answer mode: bee's alpha:p3 (codex), blocked, `question` in detection.
func _blocked_bee(question := QUESTION, screen := Vector2(SCREEN)) -> OfficeDouble:
	_fakes()
	_ctl("control-b", "set_snapshot", {"snapshot": _changed(_raw(), "alpha:p3", {"agent_status": "blocked"})})
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "detection", "text": question})
	var office := await _office_with(false, true, true, screen)
	await _pick_bee(office, "alpha:p3")
	var card := _card(office)
	await _until(
		func() -> bool: return card.preview_text() == question and card.answer_offered(), "the question is shown"
	)
	return office


## Local's shell (alpha:p2, no agent) picked, `recent` scripted as its
## recent output (what a start's prompt check reads).
func _shell_local(recent := "$ \n") -> OfficeDouble:
	_fakes()
	_ctl("control-a", "set_preview", {"pane_id": "alpha:p2", "source": "recent_unwrapped", "text": recent})
	var office := await _office_with()
	await _pick_local(office, "alpha:p2")
	return office


## An idle agent on bee (alpha:p3, codex) picked, `recent` shown.
func _idle_bee(recent := "done.\n$ \n") -> OfficeDouble:
	_fakes()
	_ctl("control-b", "set_preview", {"pane_id": "alpha:p3", "source": "recent_unwrapped", "text": recent})
	var office := await _office_with()
	await _pick_bee(office, "alpha:p3")
	var card := _card(office)
	await _until(func() -> bool: return card.preview_text() == recent and card.answer_offered(), "idle, shown")
	return office


## Enter, as a keyboard sends it, into answer mode.
func _open_answer(office: OfficeDouble) -> void:
	await _tap(KEY_ENTER)
	await _until(_card(office).answering, "answer mode")


## Real typing into whatever has keyboard focus: one key event per character.
## `positions` places a character's key elsewhere than on a US layout (its
## physical_keycode); the layout's key (keycode) stays the character's own.
func _type(text: String, positions: Dictionary[String, Key] = {}) -> void:
	for index in text.length():
		var code := text.unicode_at(index)
		var upper := char(code).to_upper().unicode_at(0)
		var at: Key = positions.get(char(code), upper as Key)
		for down: bool in [true, false]:
			var event := InputEventKey.new()
			event.keycode = upper as Key
			event.physical_keycode = at
			event.unicode = code
			event.pressed = down
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await process_frame


## A key held down: its press, `repeats` echoes, then the release. `at` is
## where the key sits (physical_keycode) when a layout moves it off `code`'s US
## position; KEY_NONE: at its US position.
func _hold(code: Key, repeats: int, at := KEY_NONE) -> void:
	for index in repeats + 2:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code if at == KEY_NONE else at
		event.pressed = index <= repeats
		event.echo = index > 0 and index <= repeats
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame


## One half of a click on `control`'s centre, through the viewport's GUI.
func _half_click(control: Control, down: bool, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = down
	event.double_click = double
	root.push_input(event, true)


## A real click on `control`: press, a frame, release, a frame.
func _click_control(control: Control) -> void:
	for down: bool in [true, false]:
		_half_click(control, down)
		await process_frame
	await process_frame


## A real key press and release, through Input as a keyboard delivers it:
## `code` is what the layout makes of the key (keycode), `at` where the key
## sits (physical_keycode, by its US name); KEY_NONE: at `code`'s US position.
## An AZERTY `-` is _tap(KEY_MINUS, KEY_6), a QWERTZ Z is _tap(KEY_Z, KEY_Y).
func _tap(code: Key, at := KEY_NONE) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code if at == KEY_NONE else at
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


## Real seconds on real frames.
func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


# --- the boundary on synthetic time ---------------------------------------------


## A write boundary outside the tree, pumped by hand like test_client.gd's client.
func _boundary() -> HerdrCommands:
	return HerdrCommands.new()


## What a fleet would hand the boundary for a machine on `socket` serving `raw`.
func _facts(socket: String, raw: Dictionary, generation := 1) -> HerdrCommands.Machine:
	var facts := HerdrCommands.Machine.new()
	facts.key = "socket:fake"
	facts.generation = generation
	facts.online = true
	facts.current = true
	facts.protocol = 22
	facts.socket_path = socket
	facts.snapshot = HerdrSnapshot.from_wire(raw)
	return facts


## A context aimed at pane `pane_id` of `facts`, as HerdrFleet.context_for() aims one.
func _aim(facts: HerdrCommands.Machine, pane_id: String, binding := 1) -> CommandContext:
	var snapshot := facts.snapshot
	for index in snapshot.panes.size():
		var pane := snapshot.panes[index]
		if pane.pane_id == pane_id:
			var identity := AgentSessionIdentity.runtime_key(pane.terminal_id, pane.agent, pane.agent_session)
			return CommandContext.aimed(
				facts.key,
				facts.generation,
				HerdrFleet.pane_key(facts.key, pane_id),
				snapshot.wire_pane_ids[index],
				pane.pane_id,
				identity,
				binding,
				pane.terminal_id
			)
	return CommandContext.aimed(
		facts.key, facts.generation, HerdrFleet.pane_key(facts.key, pane_id), "", pane_id, "", 1
	)


## What the fleet would answer for `facts` whenever it is asked: the same
## object, so a case changes the machine by changing it.
func _facts_now(facts: HerdrCommands.Machine) -> Callable:
	return func() -> HerdrCommands.Machine: return facts


## Read pane `pane_id` of `facts` through `commands` the way the card does, and
## freeze what it showed as sequence `seq`: the text a press is aimed at.
func _seen(
	commands: HerdrCommands, facts: HerdrCommands.Machine, pane_id: String, source: String, lines: int, seq := 1
) -> CommandPreview:
	var read := commands.submit(_aim(facts, pane_id).reading(source, lines), facts)
	_settle(commands, read, "the read a press is aimed at")
	return CommandPreview.of(read, seq)


## Look at pane `pane_id` the way the card does after a write: a read asked for
## LOOK_DELAY_MSEC after the last write ended, shown (HerdrCommands.saw()).
## Waited for on the monotonic clock, not a SceneTree timer: _settle() blocks
## the main thread, and the next frame's delta would count that time too.
func _look(commands: HerdrCommands, facts: HerdrCommands.Machine, pane_id: String) -> void:
	var after := Time.get_ticks_msec() + HerdrCommands.LOOK_DELAY_MSEC + 50
	while Time.get_ticks_msec() < after:
		await process_frame
	var read := commands.submit(_aim(facts, pane_id).reading(CommandContext.SOURCE_RECENT, 12), facts)
	_settle(commands, read, "the look")
	_eq(read.state, CommandTicket.State.ACCEPTED, "the look at %s came back" % pane_id)
	commands.saw(read)


## Pump `commands` with `step` seconds a call until `ticket` is final or
## WAIT real seconds pass.
func _settle(commands: HerdrCommands, ticket: CommandTicket, what: String, step := 0.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(WAIT * 1000)
	while Time.get_ticks_msec() < deadline:
		commands.pump(step)
		if ticket.is_finished():
			return true
		OS.delay_usec(1000)
	_fail("timed out waiting for " + what)
	return false


# --- logs ----------------------------------------------------------------------
# What the engine logs is caught by tools/test_base.gd's Captured.


## Everything an audit entry holds, as text, for the privacy case.
func _entry_text(entry: CommandAuditEntry) -> String:
	return (
		JSON
		. stringify(
			[
				entry.machine,
				entry.request_id,
				entry.pane_key,
				entry.method,
				entry.summary,
				entry.states,
				entry.refusal,
				entry.error_code,
				entry.source,
				entry.key_name,
				entry.line_bytes,
				entry.agent_kind,
				entry.agent_name,
				entry.direction,
				entry.scope,
				entry.cwd_bytes,
				entry.branch,
			]
		)
	)


## Why the boundary refused `ticket`, or NONE when it was not refused.
func _refusal(ticket: CommandTicket) -> CommandRefusal.Reason:
	return ticket.refusal if ticket.state == CommandTicket.State.REFUSED else CommandRefusal.Reason.NONE


## A Godot run of this project, headless, with `engine` before `--` and `user`
## after it; stdout and stderr together in `output`. Returns the exit code.
func _godot(engine: PackedStringArray, user: PackedStringArray, output: Array) -> int:
	var arguments := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://")])
	arguments.append_array(engine)
	arguments.append("--")
	arguments.append_array(user)
	return OS.execute(OS.get_executable_path(), arguments, output, true)


## Every HUD panel shown stays on screen and off every other one; in answer
## mode the staff panel is a modal over the others, so it only stays on screen.
func _panels_apart(office: OfficeDouble, what: String) -> void:
	var hud := office.hud
	var screen: Control = hud.get_node("Screen")
	var room := Rect2(Vector2.ZERO, screen.size).grow(0.5)
	var shown: Array[Control] = []
	for panel: Control in [
		hud.bar,
		hud.spaces,
		hud.get_node("%ListHolder"),
		hud.get_node("%DrawerTab"),
		hud.staff,
		hud.news,
	]:
		if panel.is_visible_in_tree():
			shown.append(panel)
	# The edge arrows stand over the world: each is a panel of its own here.
	if hud.edge_arrows.is_visible_in_tree():
		for arrow in hud.edge_arrows.shown():
			shown.append(arrow)
	_check(shown.size() >= 4, "%s: the bar, the minimap, the list and the staff panel are shown" % what)
	for i in shown.size():
		var rect := shown[i].get_global_rect()
		_check(room.encloses(rect), "%s: %s stays on screen: %s" % [what, shown[i].name, rect])
		if shown[i] == hud.staff and hud.inspector.answering():
			continue
		for j in range(i + 1, shown.size()):
			if shown[j] == hud.staff and hud.inspector.answering():
				continue
			var other := shown[j].get_global_rect()
			_check(
				not rect.intersects(other),
				"%s: %s %s and %s %s do not overlap" % [what, shown[i].name, rect, shown[j].name, other]
			)
