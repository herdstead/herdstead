extends SceneTree
## Headless read-only check of the herdr socket API. Sends ping/snapshot/subscribe
## and nothing else; it never mutates a session.
##
## godot --headless --path . --script tools/probe_herdr.gd -- --socket=<path> --wait=8
##
## `--machines` also lists herdr machines (`herdr machine list --json` plus any
## `--machine-socket=<label>=<path>`), connects to each the way the office does
## and prints one MACHINE line apiece. Informational: the exit code still says
## only whether Local answered.


func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	var wait := 8.0
	var timeout := 10.0
	for argument in user_args:
		if argument.begins_with("--wait="):
			wait = argument.trim_prefix("--wait=").to_float()
		if argument.begins_with("--timeout="):
			timeout = argument.trim_prefix("--timeout=").to_float()
	var path := HerdrClient.resolve_socket_path(user_args)
	print("PROBE socket: " + path)
	var client := HerdrClient.new()
	root.add_child(client)
	var events := [0]
	var snapshots := [0]
	client.connected.connect(func() -> void: print("CONNECTED"))
	client.disconnected.connect(func() -> void: print("DISCONNECTED"))
	client.event_received.connect(
		func(name: String, data: Dictionary) -> void:
			events[0] += 1
			print("EVENT %s %s" % [name, JSON.stringify(data)])
	)
	client.snapshot_changed.connect(
		func(snapshot: HerdrSnapshot) -> void:
			snapshots[0] += 1
			print("SNAPSHOT %s" % _digest(snapshot))
	)
	client.start(path)
	var waited := 0.0
	while not client.online and waited < timeout:
		await create_timer(0.1).timeout
		waited += 0.1
	if not client.online:
		print("PROBE_FAIL: no subscription after %.1fs" % waited)
		client.stop()
		if user_args.has("--machines"):
			await _probe_machines(user_args, timeout)
		quit(1)
		return
	# Stay on the stream so a driver can mutate the session and be observed.
	waited = 0.0
	while waited < wait:
		await create_timer(0.1).timeout
		waited += 0.1
	var snapshot := client.snapshot
	print(
		(
			"PROBE_OK workspaces=%d tabs=%d panes=%d snapshots=%d events=%d online=%s"
			% [
				snapshot.workspaces.size(),
				snapshot.tabs.size(),
				snapshot.panes.size(),
				snapshots[0],
				events[0],
				client.online,
			]
		)
	)
	client.stop()
	if user_args.has("--machines"):
		await _probe_machines(user_args, timeout)
	quit(0)


## One MACHINE line per machine: reachable or not, and what it holds.
func _probe_machines(user_args: PackedStringArray, timeout: float) -> void:
	for leftover in MachineLink.clean_leftovers():
		print("PROBE removed a stale machine forward: " + leftover)
	var roster := MachineRoster.new()
	root.add_child(roster)
	roster.start(user_args)
	var waited := 0.0
	while roster.attempts == 0 and waited < timeout:
		await create_timer(0.1).timeout
		waited += 0.1
	roster.stop()
	if roster.attempts == 0 or roster._failing:
		print("PROBE machine list unavailable from %s; debug sockets only" % MachineRoster.herdr_binary())
	var probes: Array = []
	for entry in roster.sockets:
		probes.append(
			{"label": entry.label, "kind": "socket", "target": entry.socket, "socket": entry.socket, "link": null}
		)
	for machine in roster.machines:
		if not machine.enabled:
			print("MACHINE label=%s kind=ssh target=%s enabled=false" % [machine.label, machine.target])
			continue
		var link := MachineLink.new()
		root.add_child(link)
		link.start(machine.target, machine.session)
		probes.append({"label": machine.label, "kind": "ssh", "target": machine.target, "socket": "", "link": link})
	for probe: Dictionary in probes:
		var herdr := HerdrClient.new()
		probe.client = herdr
		root.add_child(herdr)
		var socket := str(probe.socket)
		if not socket.is_empty():
			herdr.start(socket)
	waited = 0.0
	while waited < timeout and not probes.all(_is_loaded):
		# Like the office: a client follows its forward only once ssh holds it.
		for probe: Dictionary in probes:
			var link: MachineLink = probe.link
			var herdr: HerdrClient = probe.client
			if link != null and link.state == MachineLink.State.FORWARDING and herdr.socket_path.is_empty():
				herdr.start(link.local_socket)
		await create_timer(0.1).timeout
		waited += 0.1
	var online := 0
	for probe: Dictionary in probes:
		var herdr: HerdrClient = probe.client
		var snapshot := herdr.snapshot
		online += 1 if herdr.online else 0
		var link: MachineLink = probe.link
		print(
			(
				"MACHINE label=%s kind=%s target=%s online=%s workspaces=%d tabs=%d panes=%d%s"
				% [
					probe.label,
					probe.kind,
					probe.target,
					herdr.online,
					snapshot.workspaces.size(),
					snapshot.tabs.size(),
					snapshot.panes.size(),
					"" if link == null or link.last_error.is_empty() else " error=" + link.last_error,
				]
			)
		)
		herdr.stop()
		if link != null:
			link.stop()
	print("PROBE_MACHINES machines=%d online=%d" % [probes.size(), online])


## Whether a probe's client is connected and has a snapshot to show.
func _is_loaded(probe: Dictionary) -> bool:
	var herdr: HerdrClient = probe.client
	return herdr.online and not herdr.snapshot.is_empty()


## The snapshot as the office reads it, after HerdrSnapshot.from_wire(): what
## herdr sent raw is on the EVENT lines.
func _digest(snapshot: HerdrSnapshot) -> String:
	var focus := snapshot.focused_pane_id
	var parts: Array = [
		(
			"ws=%d tabs=%d panes=%d focus=%s"
			% [
				snapshot.workspaces.size(),
				snapshot.tabs.size(),
				snapshot.panes.size(),
				"-" if focus.is_empty() else focus,
			]
		)
	]
	for pane in snapshot.panes:
		parts.append("%s %s/%s" % [pane.pane_id, "shell" if pane.agent.is_empty() else pane.agent, pane.status()])
	return " | ".join(parts)
