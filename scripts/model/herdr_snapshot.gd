class_name HerdrSnapshot
extends RefCounted
## One herdr `session.snapshot` reduced to what the office draws, every field of
## the type it is drawn as. `from_wire()` is the one place that reads herdr's raw
## snapshot dictionary; everything after it reads these typed fields.
##
## A machine is a remote server nobody here controls: a list item that is not an
## object is dropped and a field of the wrong type reads as absent, so one odd
## machine cannot throw halfway through a refresh and blank every other. Text is
## lenient: a number or a boolean where text belongs reads as its text (7 as
## "7"), and only an object or a list reads as absent. Opaque identifiers (a
## terminal id, a session's fields) are not: anything but a clean string is
## absent. Ids and labels lose control characters, the same way
## HerdrFleet.pane_key() does. A snapshot listing more records than the caps
## below is refused whole. A pane's AgentInfo record (`agents[]`) adds three
## things, and only while it describes the pane's agent beyond doubt: whether
## herdr is still launching it, the name herdr gave it, and whether it is ready
## for input (`launch_pending`, `name`, `interactive_ready`).

## Record caps, comfortably above what FloorLayoutPolicy lets the office lay out
## (4096 panes and 1024 tables a floor): a snapshot beyond any of them is refused
## before anything in it is cleaned. Layouts count against MAX_TABS (one per
## tab), agent records against MAX_PANES (one per pane).
const MAX_WORKSPACES := 4096
const MAX_TABS := 16384
const MAX_PANES := 16384
const MAX_LAYOUT_SLOTS := 16384
## The largest terminal rect side, in cells, a layout slot keeps. A side past it,
## or below one cell, or not a whole number, makes the slot's size unknown (0x0).
const MAX_RECT_CELLS := 4096

## Herdr's own session focus; empty when it has none.
var focused_pane_id := ""
var workspaces: Array[Workspace] = []
var tabs: Array[Tab] = []
var panes: Array[Pane] = []
var layouts: Array[Layout] = []

# Transport, not model: what the client needs from the wire besides what the
# office draws. Nothing draws them, so signature() leaves them out.
## Herdr's own pane ids, exactly as sent, one per entry of `panes` at the same
## index. Status subscriptions and events name panes by these, and an id cleaned
## for the office need not be one herdr knows.
var wire_pane_ids := PackedStringArray()
## Herdr's own workspace ids, exactly as sent, one per entry of `workspaces`
## at the same index: what a `worktree.create` names its source by.
var wire_workspace_ids := PackedStringArray()
## Items of herdr's pane list that were not objects, and so were dropped.
var unreadable_panes := 0

## True until a snapshot object with anything in it is read (see is_empty()).
var _empty := true


class Workspace:
	var workspace_id := ""
	## The workspace's label, or its id when herdr sent none.
	var label := ""
	var number := 0
	## Which tab herdr has open. Empty when it did not say, which is not the same
	## as "no tab is open": absent, empty, an object and a list all read as herdr
	## not saying. A number or a boolean reads as its text (7 as "7"), the same
	## way a tab id does, so a numeric open tab still names its numeric tab.
	var active_tab_id := ""
	## Null for a workspace without a worktree.
	var worktree: Worktree


class Worktree:
	## The same for every checkout of one repository on one machine: herdr's own
	## key for grouping a linked worktree with the space it was made from. Remote
	## text like any other, so it groups nothing across machines.
	var repo_key := ""
	var repo_name := ""
	## Where the repository's main checkout stands.
	var repo_root := ""
	## Only a linked worktree stands anywhere but in the repository.
	var checkout_path := ""
	var is_linked_worktree := false


class Tab:
	var tab_id := ""
	var workspace_id := ""
	## The tab's label, or its id when herdr sent none.
	var label := ""
	var number := 0


class Pane:
	var pane_id := ""
	## Opaque, so never cleaned into another id: empty when herdr's was not a clean string.
	var terminal_id := ""
	var tab_id := ""
	var workspace_id := ""
	var label := ""
	## The agent herdr detected here; empty for a plain shell.
	var agent := ""
	## Null unless the session herdr reported names this very agent.
	var agent_session: AgentSessionIdentity
	## Herdr is still launching the agent. Only an AgentInfo record says so, and
	## only one that describes this pane beyond doubt (see from_wire()).
	var launch_pending := false
	## Such a record exists and its flag is a JSON boolean or its documented
	## default of false, left out.
	var launch_pending_known := false
	## The name herdr gave this agent (a start names every agent it
	## launches); empty when it has none, or no record describes this pane's
	## agent beyond doubt. Remote text, grapheme clusters bounded.
	var agent_name := ""
	## herdr reports the agent ready for input: only a record that describes
	## this pane's agent says so. Launching ends with it (or with a question).
	var interactive_ready := false
	var cwd := ""
	## herdr's `cwd` was a string that cleaning and bounding left as it is: what
	## the office shows is what herdr sent, so a request may carry it back
	## (`workspace.create`). False for an absent, odd or unclean one.
	var cwd_clean := false
	var foreground_cwd := ""
	var terminal_title_stripped := ""
	## Empty when herdr sent no agent_status at all; "unknown" when what it sent
	## reads as nothing. See status().
	var agent_status := ""

	# What from_wire() read of this pane's AgentInfo record and of the session it
	# claims, before either was held against the pane's agent. A status event may
	# name another agent; these let it apply the same join rules to it without the
	# raw snapshot. Nothing draws them, so signature() leaves them out.
	var _record: AgentRecord
	var _claimed: AgentSessionIdentity

	## The status as the office reads it: "unknown" when herdr sent none.
	func status() -> String:
		return "unknown" if agent_status.is_empty() else agent_status

	## A `pane.agent_status_changed` event: its status, and its agent when it names
	## one, read by the rules from_wire() reads a pane by. True when anything the
	## office draws changed.
	func apply_status(data: Dictionary) -> bool:
		var was_status := agent_status
		var was_agent := agent
		var was_session := agent_session
		var was_pending := launch_pending
		var was_known := launch_pending_known
		var was_name := agent_name
		var was_ready := interactive_ready
		if data.has("agent_status"):
			agent_status = HerdrSnapshot._text(data, "agent_status", "unknown")
		elif agent_status.is_empty():
			agent_status = "unknown"
		if data.has("agent"):
			_set_agent(HerdrSnapshot._shown(data, "agent"))
		return (
			agent_status != was_status
			or agent != was_agent
			or agent_session != was_session
			or launch_pending != was_pending
			or launch_pending_known != was_known
			or agent_name != was_name
			or interactive_ready != was_ready
		)

	## The pane's agent, and with it which session, launch flag, name and
	## readiness still describe it: a record or a session that names another
	## agent describes another run.
	func _set_agent(provider: String) -> void:
		agent = provider
		var matched := (
			_record != null and (provider.is_empty() or _record.agent.is_empty() or provider == _record.agent)
		)
		launch_pending_known = matched and _record.launch_known
		launch_pending = launch_pending_known and _record.launch_pending
		agent_name = _record.name if matched else ""
		interactive_ready = matched and _record.interactive_ready
		agent_session = _claimed if _claimed != null and _claimed.provider == provider else null


## The one AgentInfo record that may describe a pane: same pane, same terminal,
## the same workspace and tab where both say, and each listed exactly once.
## Whether it describes the pane's current agent is decided per agent.
class AgentRecord:
	var agent := ""
	## `launch_pending` is a JSON boolean, or left out as its default false.
	var launch_known := false
	var launch_pending := false
	## herdr's name for the agent (bounded, like every name shown), and its
	## `interactive_ready` flag (a JSON boolean; anything else reads as false).
	var name := ""
	var interactive_ready := false


class Layout:
	var tab_id := ""
	var panes: Array[LayoutSlot] = []


class LayoutSlot:
	var pane_id := ""
	## The origin of the pane's terminal rect: where the desk sits.
	var x := 0
	var y := 0
	## The terminal rect's size in cells, the grid the terminal monitor draws;
	## 0x0 when herdr's was not a whole 1..MAX_RECT_CELLS on both sides. Nothing on
	## the floor reads it: a size change alone re-plans and re-seats nothing.
	var width := 0
	var height := 0


## `raw` as the office reads it. Anything that is not a snapshot object reads as
## an empty snapshot, the way today's `{}` did; null when it is refused (see
## refusal()), so the snapshot held before it stays.
static func from_wire(raw: Variant) -> HerdrSnapshot:
	var result := HerdrSnapshot.new()
	if not raw is Dictionary:
		return result
	if not refusal(raw).is_empty():
		return null
	var data: Dictionary = raw
	result._empty = data.is_empty()
	result.focused_pane_id = _text(data, "focused_pane_id")
	for item: Dictionary in _objects(data.get("workspaces")):
		result.workspaces.append(_workspace(item))
		result.wire_workspace_ids.append(str(item.get("workspace_id", "")))
	for item: Dictionary in _objects(data.get("tabs")):
		result.tabs.append(_tab(item))
	_read_panes(data, result)
	for item: Dictionary in _objects(data.get("layouts")):
		result.layouts.append(_layout(item))
	return result


## Why `raw` is refused whole, or empty when it is within the record caps. Counts
## whatever the lists hold, objects or not: the caps bound the work of reading.
static func refusal(raw: Variant) -> String:
	if not raw is Dictionary:
		return ""
	var data: Dictionary = raw
	var caps: Dictionary[String, int] = {
		"workspaces": MAX_WORKSPACES, "tabs": MAX_TABS, "layouts": MAX_TABS, "panes": MAX_PANES, "agents": MAX_PANES
	}
	for key: String in caps:
		var count := _size(data.get(key))
		if count > caps[key]:
			return "%d %s, more than the %d this office reads" % [count, key, caps[key]]
	var slots := 0
	for layout: Dictionary in _objects(data.get("layouts")):
		slots += _size(layout.get("panes"))
	if slots > MAX_LAYOUT_SLOTS:
		return "%d layout slots, more than the %d this office reads" % [slots, MAX_LAYOUT_SLOTS]
	return ""


## Nothing has been read into this snapshot: none arrived yet, or what arrived
## was no snapshot object, or an empty one. Like the `{}` it stands for, it
## projects to no floors at all.
func is_empty() -> bool:
	return _empty


## Every field this snapshot holds, as one string: two snapshots that draw the
## same office have the same signature. A session is an object, so it is written
## out field by field (its identity_key() and its source), never compared by
## reference. That includes what the floor does not read, a worktree's repository
## key and a terminal rect's size: the client only announces a snapshot whose
## signature changed, and the worktree groups and the monitor's grid follow them.
## So is whether a pane's directory came clean (`cwd_clean`): a new space is
## judged by it.
func signature() -> String:
	var spaces: Array = []
	for workspace in workspaces:
		var tree: Variant = null
		if workspace.worktree != null:
			var held := workspace.worktree
			tree = [held.repo_key, held.repo_name, held.repo_root, held.checkout_path, held.is_linked_worktree]
		spaces.append([workspace.workspace_id, workspace.label, workspace.number, workspace.active_tab_id, tree])
	var listed_tabs: Array = []
	for tab in tabs:
		listed_tabs.append([tab.tab_id, tab.workspace_id, tab.label, tab.number])
	var listed_panes: Array = []
	for pane in panes:
		var session: Variant = null
		if pane.agent_session != null:
			var identity := pane.agent_session
			session = [identity.source, identity.provider, identity.kind, identity.value]
		(
			listed_panes
			. append(
				[
					pane.pane_id,
					pane.terminal_id,
					pane.tab_id,
					pane.workspace_id,
					pane.label,
					pane.agent,
					session,
					pane.launch_pending,
					pane.launch_pending_known,
					pane.agent_name,
					pane.interactive_ready,
					pane.cwd,
					pane.cwd_clean,
					pane.foreground_cwd,
					pane.terminal_title_stripped,
					pane.agent_status,
				]
			)
		)
	var listed_layouts: Array = []
	for layout in layouts:
		var slots: Array = []
		for slot in layout.panes:
			slots.append([slot.pane_id, slot.x, slot.y, slot.width, slot.height])
		listed_layouts.append([layout.tab_id, slots])
	return JSON.stringify([_empty, focused_pane_id, spaces, listed_tabs, listed_panes, listed_layouts])


# --- reading ------------------------------------------------------------------


static func _workspace(item: Dictionary) -> Workspace:
	var workspace := Workspace.new()
	workspace.workspace_id = _text(item, "workspace_id")
	workspace.label = _shown(item, "label", workspace.workspace_id)
	workspace.number = _number(item, "number")
	workspace.active_tab_id = _text(item, "active_tab_id")
	var tree: Dictionary = item.get("worktree") if item.get("worktree") is Dictionary else {}
	if not tree.is_empty():
		workspace.worktree = Worktree.new()
		workspace.worktree.repo_key = _text(tree, "repo_key")
		workspace.worktree.repo_name = _shown(tree, "repo_name")
		workspace.worktree.repo_root = _shown(tree, "repo_root")
		workspace.worktree.checkout_path = _shown(tree, "checkout_path")
		workspace.worktree.is_linked_worktree = _flag(tree, "is_linked_worktree")
	return workspace


static func _tab(item: Dictionary) -> Tab:
	var tab := Tab.new()
	tab.tab_id = _text(item, "tab_id")
	tab.workspace_id = _text(item, "workspace_id")
	tab.label = _shown(item, "label", tab.tab_id)
	tab.number = _number(item, "number")
	return tab


## The client's clock and the projection share the same identity/launch boundary.
## AgentInfo supplements PaneInfo; it never replaces the pane's immediate status.
## Fills `into.panes`, and beside each its id as herdr spelled it.
static func _read_panes(data: Dictionary, into: HerdrSnapshot) -> void:
	var source_panes := _objects(data.get("panes"))
	into.unreadable_panes = _size(data.get("panes")) - source_panes.size()
	var source_agents := _objects(data.get("agents"))
	var pane_counts: Dictionary[String, int] = {}
	var agent_counts: Dictionary[String, int] = {}
	var agents: Dictionary[String, Dictionary] = {}
	for item: Dictionary in source_panes:
		var id := _text(item, "pane_id")
		pane_counts[id] = pane_counts.get(id, 0) + 1
	for item: Dictionary in source_agents:
		var id := _text(item, "pane_id")
		agent_counts[id] = agent_counts.get(id, 0) + 1
		agents[id] = item
	for item: Dictionary in source_panes:
		var pane := Pane.new()
		var id := _text(item, "pane_id")
		into.wire_pane_ids.append(str(item.get("pane_id", "")))
		pane.pane_id = id
		pane.terminal_id = _identifier(item, "terminal_id")
		pane.tab_id = _text(item, "tab_id")
		pane.workspace_id = _text(item, "workspace_id")
		pane.label = _shown(item, "label")
		pane.cwd = _shown(item, "cwd")
		pane.cwd_clean = item.get("cwd") is String and item.get("cwd") == pane.cwd
		pane.foreground_cwd = _shown(item, "foreground_cwd")
		pane.terminal_title_stripped = _shown(item, "terminal_title_stripped")
		if item.has("agent_status"):
			pane.agent_status = _text(item, "agent_status", "unknown")
		var joined: Dictionary = agents.get(id, {})
		# Every condition but the agent's: that one is held against the pane's
		# agent, which a status event may still change.
		var joinable: bool = (
			not id.is_empty()
			and _identifier(item, "pane_id") == id
			and _identifier(joined, "pane_id") == id
			and not pane.terminal_id.is_empty()
			and pane_counts.get(id, 0) == 1
			and agent_counts.get(id, 0) == 1
			and _identifier(joined, "terminal_id") == pane.terminal_id
			and _same_owner(item, joined, "workspace_id")
			and _same_owner(item, joined, "tab_id")
		)
		if joinable:
			pane._record = AgentRecord.new()
			pane._record.agent = _shown(joined, "agent")
			pane._record.launch_known = not joined.has("launch_pending") or joined.launch_pending is bool
			pane._record.launch_pending = _flag(joined, "launch_pending")
			pane._record.name = _shown(joined, "name")
			pane._record.interactive_ready = _flag(joined, "interactive_ready")
		pane._claimed = _claimed_session(item.get("agent_session"))
		pane._set_agent(_shown(item, "agent"))
		into.panes.append(pane)


static func _same_owner(pane: Dictionary, agent: Dictionary, field: String) -> bool:
	var expected := _text(pane, field)
	var actual := _text(agent, field)
	return expected.is_empty() or actual.is_empty() or expected == actual


## The session a pane claims, before it is held against the pane's agent: null
## unless its agent, kind and value are opaque, clean strings. Its provider is
## the agent it names.
static func _claimed_session(raw: Variant) -> AgentSessionIdentity:
	if not raw is Dictionary:
		return null
	var data: Dictionary = raw
	# Session identifiers are opaque strings, not arbitrary objects/numeric labels.
	for field: String in ["agent", "kind", "value"]:
		if _identifier(data, field).is_empty():
			return null
	var identity := AgentSessionIdentity.new()
	identity.source = _text(data, "source")
	identity.provider = _shown(data, "agent")
	identity.kind = _text(data, "kind")
	identity.value = _text(data, "value")
	return identity


static func _layout(item: Dictionary) -> Layout:
	var layout := Layout.new()
	layout.tab_id = _text(item, "tab_id")
	for slot: Dictionary in _objects(item.get("panes")):
		var rect: Dictionary = slot.get("rect") if slot.get("rect") is Dictionary else {}
		var placed := LayoutSlot.new()
		placed.pane_id = _text(slot, "pane_id")
		placed.x = _number(rect, "x")
		placed.y = _number(rect, "y")
		var width := _cells(rect, "width")
		var height := _cells(rect, "height")
		if width > 0 and height > 0:
			placed.width = width
			placed.height = height
		layout.panes.append(placed)
	return layout


## A rect side herdr sent as a whole number of cells from 1 to MAX_RECT_CELLS;
## 0 for anything else, a boolean, a fraction or a side too long to draw included.
static func _cells(rect: Dictionary, key: String) -> int:
	if not (rect.get(key) is int or rect.get(key) is float):
		return 0
	var value: float = rect.get(key)
	if value < 1 or value > MAX_RECT_CELLS or value != floorf(value):
		return 0
	return int(value)


## Joining different records must not alias ids by deleting control characters.
static func _identifier(item: Dictionary, field: String) -> String:
	if not item.get(field) is String:
		return ""
	var value: String = item[field]
	return value if value == MachineRoster.clean_text(value) else ""


## A string herdr sent that the office draws (a label, a title, an agent's or a
## repository's name, a path): _text() with every grapheme cluster bounded
## (TerminalText.bound(), invariant 9). One letter with 300 combining marks
## froze the engine's text shaping for minutes. Ids and keys never go
## through here: they keep their exact spelling and have rules of their own.
static func _shown(item: Dictionary, key: String, fallback := "") -> String:
	return TerminalText.bound(_text(item, key, fallback))


static func _text(item: Dictionary, key: String, fallback := "") -> String:
	var value := MachineRoster.clean_text(item.get(key))
	return value if not value.is_empty() else fallback


## A field herdr sent as a JSON boolean; anything else reads as false, the same
## way a missing one does.
static func _flag(item: Dictionary, key: String) -> bool:
	if not item.get(key) is bool:
		return false
	var value: bool = item.get(key)
	return value


static func _number(item: Dictionary, key: String) -> int:
	if not (item.get(key) is int or item.get(key) is float):
		return 0
	var value: float = item.get(key)
	return int(value)


static func _objects(value: Variant) -> Array:
	if not value is Array:
		return []
	var listed: Array = value
	return listed.filter(func(item: Variant) -> bool: return item is Dictionary)


static func _size(value: Variant) -> int:
	if not value is Array:
		return 0
	var listed: Array = value
	return listed.size()
