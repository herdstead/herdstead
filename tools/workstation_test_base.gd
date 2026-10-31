extends "res://tools/office_test_base.gd"
## Whole-image lifecycle fixtures for test_office_rests.gd.

const PLAN_SCREEN := Vector2(592, 480)


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
	OS.set_environment("HERDSTEAD_SOCKET_DIR", args.work.path_join("workstation-socks"))
	OS.set_environment("HERDR_BIN_PATH", args.work.path_join("no-herdr"))
	MachineLink.reset_socket_directory()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/snapshot_floors.json"))
	if parsed is not Dictionary:
		print("TEST_HARNESS_ERROR: cannot read snapshot_floors.json")
		quit(2)
		return
	var fixture_file: Dictionary = parsed
	fixture = _dict(fixture_file, "snapshot")
	fixture = _with(_with(fixture, "api:p2", {"agent_status": "working"}), "api:p3", {"agent_status": "working"})
	_run()


func _run() -> void:
	await process_frame
	root.size = SCREEN
	await process_frame
	await run_cases()


func _pane(pane_id: String) -> String:
	return HerdrFleet.pane_key(LOCAL, pane_id)


func _live_office(snapshot: Dictionary = fixture, screen := PLAN_SCREEN) -> OfficeDouble:
	return await super(snapshot, screen)


## The fixture without one pane, in every wire list that refers to it.
func _without(snapshot: Dictionary, pane_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["panes", "agents"]:
		result[field] = _list(result, field).filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	for layout: Dictionary in _list(result, "layouts"):
		layout.panes = _list(layout, "panes").filter(func(each: Dictionary) -> bool: return each.pane_id != pane_id)
	return result


func _only(snapshot: Dictionary, workspace_id: String) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	for field: String in ["workspaces", "tabs", "panes", "agents", "layouts"]:
		result[field] = _list(result, field).filter(
			func(each: Dictionary) -> bool: return str(each.get("workspace_id", "")) == workspace_id
		)
	return result


func _grown(snapshot: Dictionary, count: int) -> Dictionary:
	var result: Dictionary = snapshot.duplicate(true)
	var first: Dictionary = _list(result, "panes")[0]
	for index in count:
		var extra := first.duplicate(true)
		extra.pane_id = "api:grow-%d" % index
		extra.terminal_id = "term-grow-%d" % index
		_list(result, "panes").append(extra)
	return result


func _crowded(count: int) -> Dictionary:
	var result := {
		"focused_pane_id": "crowd:p00",
		"workspaces": [{"workspace_id": "crowd", "number": 1, "label": "crowd"}],
		"tabs": [{"tab_id": "crowd:t1", "workspace_id": "crowd", "number": 1, "label": "crowd"}],
		"panes": [],
		"agents": [],
		"layouts": []
	}
	for index in count:
		var pane_id := "crowd:p%02d" % index
		_list(result, "panes").append(
			{
				"pane_id": pane_id,
				"workspace_id": "crowd",
				"tab_id": "crowd:t1",
				"agent": "claude",
				"agent_status": "working",
				"terminal_id": "term-" + pane_id
			}
		)
	return result


## Exactly one complete image per station, never an unowned body left over
## by a provider swap, removal or rebind. Frozen actors keep their real state.
func _check_invariants(office: OfficeDouble, when: String, frozen: bool) -> void:
	for key: String in office.floor_view.seats:
		var station: OfficeStation = office.floor_view.seats[key].node
		var image := station.get_node("Actor") as WorkstationActor
		_check(image != null, when + ": permanent workstation image at " + key)
		if image == null:
			continue
		_eq(image.position, Vector2.ZERO, when + ": anchored to " + key)
		_eq(_names(image), ["Body", "AnimationPlayer"], when + ": one image and one clock")
		var actor := station.actor()
		var body := _sprite(image, "Body")
		_check(not body.flip_h and not body.flip_v, when + ": both rows use the same front-facing image")
		if not frozen:
			var pane := office.frame.pane(key)
			_check(pane != null, when + ": every drawn identity exists in the current frame")
			if pane != null:
				var occupied := pane.launching() or not pane.provider.is_empty()
				_eq(actor != null, occupied, when + ": occupancy agrees with the pane")
				if actor != null:
					_eq(actor.provider, pane.provider, when + ": provider agrees with the pane")
					_eq(
						actor.animation,
						&"starting" if pane.launching() else StringName(pane.state),
						when + ": real state"
					)
		if actor != null:
			_eq(actor, image, when + ": actor() is the permanent child")
			_eq(actor.global_position, station.seat.global_position, when + ": on the measured seat")
			_eq(body.texture, office.art.workstation.sheet_texture(), when + ": complete authored sheet")
			if frozen:
				_check(not actor.is_playing(), when + ": frozen without substituting idle")
			elif actor.animation in [&"working", &"idle", &"blocked"]:
				_check(actor.is_playing(), when + ": a live loop or its entry/exit keeps playing")
		else:
			_eq(
				body.texture, office.art.workstation.empty_texture(), when + ": empty workstation, not an orphan person"
			)
	for node: Node in office.floor_view.root.find_children("*", "WorkstationActor", true, false):
		_check(node.get_parent() is OfficeStation, when + ": no orphan workstation")
	_eq(office.floor_view.root.find_children("*", "PixelPerson", true, false), [], when + ": no rig on the floor")


class FuzzState:
	extends RefCounted
	var p1 := "working"
	var p1_agent := "claude"
	var p3 := ""
	var p3_term := false
	var p2_tab := ""
	var grow := 0
	var p4_tab := false
	var p2_gone := false
	var p4_gone := false
	var p2 := "working"
	var p4 := "working"


## Keep the old lifecycle's seeded draws: its routing clauses retired, not
## the combinations of state, identity, growth, tab moves and disappearance.
static func _random_state(rng: RandomNumberGenerator) -> FuzzState:
	var statuses: Array[String] = ["working", "done", "blocked", "idle"]
	var agents: Array[String] = ["claude", "codex"]
	var shells: Array[String] = ["", "codex", "claude"]
	var grows: Array[int] = [0, 0, 1, 3, 9]
	var state := FuzzState.new()
	state.p1 = statuses[rng.randi() % 4]
	state.p1_agent = agents[rng.randi() % 2] if rng.randf() < 0.3 else "claude"
	state.p3 = shells[rng.randi() % 3]
	state.p3_term = rng.randf() < 0.2
	state.p2_tab = "api:t2" if rng.randf() < 0.25 else ""
	state.grow = grows[rng.randi() % 5]
	state.p4_tab = rng.randf() < 0.2
	rng.randf()
	state.p2_gone = rng.randf() < 0.25
	state.p4_gone = rng.randf() < 0.2
	state.p2 = statuses[rng.randi() % 4]
	state.p4 = statuses[rng.randi() % 4]
	return state


func _variant(state: FuzzState) -> Dictionary:
	var snapshot: Dictionary = fixture.duplicate(true)
	snapshot = _with(snapshot, "api:p1", {"agent_status": state.p1, "agent": state.p1_agent})
	snapshot = _with(snapshot, "api:p2", {"agent_status": state.p2})
	snapshot = _with(snapshot, "api:p4", {"agent_status": state.p4})
	snapshot = _with(snapshot, "api:p3", {"agent": null if state.p3.is_empty() else state.p3})
	if not state.p2_tab.is_empty():
		snapshot = _with(snapshot, "api:p2", {"tab_id": state.p2_tab})
	if state.p3_term:
		snapshot = _with(snapshot, "api:p3", {"terminal_id": "term-api-p3-b"})
	if state.grow > 0:
		snapshot = _grown(snapshot, state.grow)
	if state.p2_gone:
		snapshot = _without(snapshot, "api:p2")
	if state.p4_tab:
		snapshot = _with(snapshot, "api:p4", {"tab_id": "api:t1"})
	if state.p4_gone:
		snapshot = _without(snapshot, "api:p4")
		snapshot.tabs = _list(snapshot, "tabs").filter(func(each: Dictionary) -> bool: return each.tab_id != "api:t2")
	return snapshot
