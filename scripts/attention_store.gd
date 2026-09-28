class_name AttentionStore
extends RefCounted
## Pure local attention: the live episode per pane (snooze / hide); what ended
## is the StateLog's to tell (AgentHistory). A record leaves the store the
## moment it ends, marked over first (not active, not available, retired) for
## whoever still holds it. Input is a complete typed snapshot of one machine;
## no remote acknowledgement, persistence, or connection lives here.

const MAX_SNOOZE_SECONDS := 86400.0
const MAX_CLOCK_MSEC := 9223372036854775807


class PaneObservation:
	extends RefCounted
	var identity := ""
	var can_time := false
	var attention_state := ""
	var active_id := ""


class MachineObservation:
	extends RefCounted
	var online := false
	var panes: Dictionary[String, PaneObservation] = {}


## How many live records the metadata pass has looked at, for tests: each
## observation looks at no more than its panes' own records.
var metadata_visits := 0

var _machines: Dictionary[String, MachineObservation] = {}
var _items: Dictionary[String, AttentionItem] = {}
var _ordered: Array[AttentionItem] = []
## Pane key -> its live records, in the order they began: the same records as
## _ordered, kept with it in _begin() and _retire(), so a pane's refresh looks
## at its own records, not at every live one.
var _by_pane: Dictionary[String, Array] = {}
var _next_id := 0
var _clock_msec := 0


## Invalid input invalidates this machine's live queue atomically. The caller
## must supply every pane, including panes that currently have no world seat.
func observe(
	machine_key: String, machine_label: String, panes: Array[PaneModel], online: bool, now_msec: int, wall_time: float
) -> bool:
	if machine_key.is_empty():
		return false
	if not _machines.has(machine_key):
		_machines[machine_key] = MachineObservation.new()
	var machine := _machines[machine_key]
	if now_msec < 0 or not is_finite(wall_time) or wall_time < 0.0:
		_offline(machine_key, machine, "Invalid snapshot; current state unknown")
		return false
	_tick(now_msec)
	if not online:
		_offline(machine_key, machine, "Offline; current state and wait duration unknown")
		return true
	var incoming: Dictionary[String, PaneModel] = {}
	var pane_ids: Dictionary[String, bool] = {}
	for pane: PaneModel in panes:
		if (
			pane == null
			or pane.pane_id.is_empty()
			or pane.key != HerdrFleet.pane_key(machine_key, pane.pane_id)
			or incoming.has(pane.key)
			or pane_ids.has(pane.pane_id)
		):
			_offline(machine_key, machine, "Invalid snapshot; current state unknown")
			return false
		incoming[pane.key] = pane
		pane_ids[pane.pane_id] = true
	var baseline := not machine.online
	for previous_key: String in machine.panes:
		if not incoming.has(previous_key):
			_unavailable(previous_key, machine.panes[previous_key].identity, "Pane closed")
	var next_panes: Dictionary[String, PaneObservation] = {}
	# Stable iteration makes simultaneous observations independent of JSON order.
	var pane_keys: Array[String] = incoming.keys()
	pane_keys.sort()
	for pane_key: String in pane_keys:
		var pane := incoming[pane_key]
		var identity := pane.identity_key()
		var previous: PaneObservation = machine.panes.get(pane_key)
		var first_observation := previous == null
		var replaced := previous != null and previous.identity != identity
		# Equal missing fields do not identify a runtime across a gap. The
		# boundary-validated native session can identify it without a terminal ID.
		var unknown_reconnect := baseline and pane.terminal_id.is_empty() and pane.session == null
		var can_time := not pane.terminal_id.is_empty() and not pane.launching()
		var continuous_identity := previous != null and previous.can_time and can_time
		if previous != null and (replaced or unknown_reconnect):
			var reason := "Runtime identity unknown after disconnection"
			if replaced:
				reason = "Terminal or agent session replaced"
			_unavailable(pane_key, previous.identity, reason)
			previous = null
		var attention_state := _attention_state(pane)
		var observation := PaneObservation.new()
		observation.identity = identity
		observation.can_time = can_time
		observation.attention_state = attention_state
		_refresh_metadata(pane, identity, machine_label)
		if previous != null and previous.attention_state == attention_state:
			observation.active_id = previous.active_id
			var existing := find(previous.active_id)
			if existing != null:
				existing.stale = false
				existing.available = true
				if baseline:
					existing.baseline = true
					existing.since_msec = -1
					existing.note = "Reconnect baseline; earlier observation is not a new event"
		elif not attention_state.is_empty():
			if previous != null:
				_end(previous.active_id, "Attention state changed")
			var item := _begin(
				pane,
				identity,
				machine_label,
				attention_state,
				baseline or first_observation or replaced or not continuous_identity,
				wall_time
			)
			observation.active_id = item.id
		elif previous != null:
			_end(previous.active_id, "No longer in this attention state")
		next_panes[pane_key] = observation
	machine.panes = next_panes
	machine.online = true
	return true


## A removed machine cannot retain a live queue or a usable navigation target.
func retain_machines(machine_keys: PackedStringArray) -> void:
	for machine_key: String in _machines.keys():
		if machine_keys.has(machine_key):
			continue
		retire_machine(machine_key)


## A roster key may be reused for another socket, SSH target, or Herdr session.
## End this incarnation permanently; ordinary disconnection uses observe(false).
func retire_machine(machine_key: String) -> void:
	for item: AttentionItem in _ordered.duplicate():
		if item.machine_key == machine_key:
			item.stale = true
			_retire(item, "Machine removed or connection replaced; previous target unavailable")
	_machines.erase(machine_key)


func current(now_msec: int) -> Array[AttentionItem]:
	_tick(now_msec)
	var result: Array[AttentionItem] = []
	for item: AttentionItem in _ordered:
		if item.active and not item.stale and not item.hidden and not item.is_snoozed(_clock_msec):
			result.append(item)
	result.sort_custom(_current_before)
	return result


## Every live episode, in the order they began: the hidden, snoozed and stale
## ones current() leaves out included. What a row's Snooze and Hide act on.
func active() -> Array[AttentionItem]:
	return _ordered.duplicate()


func snooze(item_id: String, seconds: float, now_msec: int) -> bool:
	var item := find(item_id)
	if (
		item == null
		or (not item.active and seconds != 0.0)
		or now_msec < 0
		or not is_finite(seconds)
		or seconds < 0.0
		or seconds > MAX_SNOOZE_SECONDS
	):
		return false
	var duration_msec := ceili(seconds * 1000.0)
	if maxi(_clock_msec, now_msec) > MAX_CLOCK_MSEC - duration_msec:
		return false
	_tick(now_msec)
	item.snoozed_until_msec = 0 if seconds == 0.0 else _clock_msec + duration_msec
	return true


func set_hidden(item_id: String, hidden: bool) -> bool:
	var item := find(item_id)
	if item == null:
		return false
	item.hidden = hidden
	return true


func find(item_id: String) -> AttentionItem:
	return _items.get(item_id)


func _tick(now_msec: int) -> void:
	_clock_msec = maxi(_clock_msec, now_msec)


func _attention_state(pane: PaneModel) -> String:
	if pane.launching() or pane.provider.is_empty():
		return ""
	return pane.state if pane.state in ["blocked", "done"] else ""


func _offline(machine_key: String, machine: MachineObservation, reason: String) -> void:
	machine.online = false
	for item: AttentionItem in _ordered:
		if item.machine_key == machine_key:
			item.stale = true
			item.available = false
			if item.active:
				item.since_msec = -1
			item.note = reason


func _unavailable(pane_key: String, identity: String, reason: String) -> void:
	var held: Array = _by_pane.get(pane_key, [])
	for item: AttentionItem in held.duplicate():
		if item.identity_key == identity:
			_retire(item, reason)


## `identity` is `pane`'s identity_key(), worked out once by observe().
func _refresh_metadata(pane: PaneModel, identity: String, machine_label: String) -> void:
	var held: Array = _by_pane.get(pane.key, [])
	for item: AttentionItem in held:
		metadata_visits += 1
		if not item.retired and item.identity_key == identity:
			_metadata(item, pane, machine_label)
			item.available = true
			item.stale = false


func _metadata(item: AttentionItem, pane: PaneModel, machine_label: String) -> void:
	item.machine_label = machine_label
	item.workspace_key = (
		"" if pane.workspace_id.is_empty() else HerdrFleet.pane_key(item.machine_key, pane.workspace_id)
	)
	item.workspace_label = pane.workspace_label
	item.tab_label = pane.tab_label
	item.provider = pane.provider
	item.title = pane.label if not pane.label.is_empty() else pane.terminal_title


func _begin(
	pane: PaneModel, identity: String, machine_label: String, state: String, baseline: bool, wall_time: float
) -> AttentionItem:
	_next_id += 1
	var item := AttentionItem.new()
	item.id = "attention:%012d" % _next_id
	item.pane_key = pane.key
	item.identity_key = identity
	item.machine_key = pane.machine()
	_metadata(item, pane, machine_label)
	item.state = state
	item.baseline = baseline
	item.observed_at = -1.0 if baseline else wall_time
	item.since_msec = -1 if baseline else _clock_msec
	item.active = true
	item.available = true
	item.note = "Baseline; start time unknown" if baseline else "Observed during this app run"
	_items[item.id] = item
	_ordered.append(item)
	if not _by_pane.has(item.pane_key):
		_by_pane[item.pane_key] = []
	_by_pane[item.pane_key].append(item)
	return item


func _end(item_id: String, reason: String) -> void:
	var item := find(item_id)
	if item != null:
		_retire(item, reason)


## The episode is over: mark it so for whoever still holds it, then drop it.
func _retire(item: AttentionItem, reason: String) -> void:
	item.active = false
	item.available = false
	item.retired = true
	item.note = reason
	_items.erase(item.id)
	_ordered.erase(item)
	var held: Array = _by_pane.get(item.pane_key, [])
	held.erase(item)
	if held.is_empty():
		_by_pane.erase(item.pane_key)


func _current_before(first: AttentionItem, second: AttentionItem) -> bool:
	if first.state != second.state:
		return first.state == "blocked"
	if (first.since_msec >= 0) != (second.since_msec >= 0):
		return first.since_msec >= 0
	if first.since_msec >= 0 and first.since_msec != second.since_msec:
		return first.since_msec < second.since_msec
	return first.id < second.id
