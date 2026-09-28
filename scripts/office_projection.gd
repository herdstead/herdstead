class_name OfficeProjection
extends RefCounted
## Snapshot in, typed models out: the office's whole projection, as static
## functions with no node, no art pack, no fleet and no viewer state of their
## own. Whatever a function needs to know about the viewer (the picked desk, the
## picked floor, the selection) or about the art pack (the states it has badges
## for) arrives as an argument.
##
## It reads HerdrSnapshot's typed fields, never herdr's raw dictionary: that has
## been read once, by HerdrSnapshot.from_wire(). Everything that draws the office
## reads the models below, and a refresh reads them through one OfficeFrame.

# --- the frame ----------------------------------------------------------------


## One refresh's whole projection: every machine as a building, Local first, and
## the lookups the office, the minimap, the inspector, attention and the `N`
## queue make, so nothing is projected twice. `states` are the states the art
## pack has a badge for.
static func frame(machines: Array[MachineView], states: PackedStringArray) -> OfficeFrame:
	var buildings: Array[BuildingModel] = []
	for machine in machines:
		buildings.append(building(machine.key, machine.label, machine.snapshot, states, machine.stale))
	var result := frame_of(buildings)
	for building_model in buildings:
		for pane in building_model.all_panes:
			if not result.pane_by_key.has(pane.key):
				result.pane_by_key[pane.key] = pane
		if not building_model.stale:
			result.live_panes.append_array(building_model.all_panes)
	for machine in machines:
		result.herdr_focus = focus_key(machine.snapshot, machine.key)
		if not result.herdr_focus.is_empty():
			break
	return result


## The buildings with their floors and seated panes indexed: a frame without
## panes or focus, which is all the floor lookups below need.
static func frame_of(buildings: Array[BuildingModel]) -> OfficeFrame:
	var result := OfficeFrame.new()
	result.buildings = buildings
	for building_model in buildings:
		for floor_model in building_model.floors:
			if not result.floor_by_key.has(floor_model.key):
				result.floor_by_key[floor_model.key] = FloorRef.new(building_model, floor_model)
			result.floor_order.append(floor_model.key)
			for room in floor_model.rooms:
				for pane in room.panes:
					if not result.floor_of_pane.has(pane.key):
						result.floor_of_pane[pane.key] = floor_model.key
	return result


# --- buildings ----------------------------------------------------------------


## A machine as a building: its key, label, counts and floors. A building
## without floors (offline, never loaded, or an empty session) gets a lobby, so
## its state and SSH complaint stay readable.
static func building(
	key: String, label: String, snapshot: HerdrSnapshot, states: PackedStringArray, is_stale: bool
) -> BuildingModel:
	var model := BuildingModel.new()
	model.key = key
	model.label = label
	model.stale = is_stale
	model.spaces = snapshot.workspaces.size()
	model.tabs = snapshot.tabs.size()
	model.panes = snapshot.panes.size()
	model.all_panes = panes_of(snapshot, states, key)
	model.floors = project(snapshot, states, key, is_stale)
	if model.floors.is_empty():
		model.floors.append(lobby(key))
	model.floor_tree = floor_tree(model.floors)
	return model


## The lobby's key has a second separator after the machine key: a cleaned
## workspace id holds no control character, so no real floor can be the lobby,
## not even a workspace whose id reads as empty.
static func lobby(machine: String) -> FloorModel:
	var model := FloorModel.new()
	model.key = HerdrFleet.pane_key(machine, "") + HerdrFleet.KEY_SEPARATOR
	model.label = "LOBBY"
	model.lobby = true
	return model


## Snapshot into the smallest description a floor can be drawn from: one floor
## per workspace by herdr's number, one room per tab by its number, desks by
## terminal rect, linked worktrees as mezzanines (group_worktrees()).
## `blocked`/`done` follow OfficeAttention.count() on the floor's own panes, and
## a stale machine reports none: a lost connection is not a live signal.
## `states` are the states the art pack has a badge for.
static func project(
	snapshot: HerdrSnapshot, states: PackedStringArray, machine := HerdrFleet.LOCAL, is_stale := false
) -> Array[FloorModel]:
	var ranks := layout_ranks(snapshot)
	var sides := layout_sides(snapshot)
	var table_x := layout_x(snapshot)
	var focused_pane := snapshot.focused_pane_id
	var panes_by_tab := {}
	var sequence := 0
	for pane in snapshot.panes:
		if not panes_by_tab.has(pane.tab_id):
			panes_by_tab[pane.tab_id] = []
		# Panes without a layout slot keep snapshot order, after the placed ones.
		var placed_ranks: Dictionary = ranks.get(pane.tab_id, {})
		var rank: int = placed_ranks.get(pane.pane_id, 1000 + sequence)
		sequence += 1
		var listed: Array = panes_by_tab[pane.tab_id]
		listed.append([rank, pane])
	for tab_id: String in panes_by_tab:
		var listed: Array = panes_by_tab[tab_id]
		listed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var tabs_by_workspace := {}
	for tab in snapshot.tabs:
		if not tabs_by_workspace.has(tab.workspace_id):
			tabs_by_workspace[tab.workspace_id] = []
		var listed: Array = tabs_by_workspace[tab.workspace_id]
		listed.append([tab.number, tab.tab_id, tab])
	for workspace_id: String in tabs_by_workspace:
		var listed: Array = tabs_by_workspace[workspace_id]
		listed.sort_custom(by_number)
	var workspaces: Array = []
	for workspace in snapshot.workspaces:
		workspaces.append([workspace.number, workspace.workspace_id, workspace])
	workspaces.sort_custom(by_number)
	var floors: Array[FloorModel] = []
	var trees: Dictionary[String, HerdrSnapshot.Worktree] = {}
	var seen := {}
	for entry: Array in workspaces:
		var workspace: HerdrSnapshot.Workspace = entry[2]
		var workspace_id := workspace.workspace_id
		var key := HerdrFleet.pane_key(machine, workspace_id)
		# Two workspaces claiming one id would be one floor twice; the first wins.
		if seen.has(key):
			continue
		seen[key] = true
		var floor_model := FloorModel.new()
		floor_model.key = key
		floor_model.number = workspace.number
		floor_model.level_label = str(workspace.number)
		floor_model.label = workspace.label
		# worktree is optional, and the API carries no branch name: never invent one.
		if workspace.worktree != null:
			trees[key] = workspace.worktree
			floor_model.repo = workspace.worktree.repo_name
			# Only a linked worktree stands somewhere other than the repository, so
			# only a linked one is worth naming; a main checkout is the repo itself.
			if workspace.worktree.is_linked_worktree:
				floor_model.worktree = workspace.worktree.checkout_path.trim_suffix("/").get_file()
		# Which tab herdr has open, or empty when this workspace does not say.
		var open_tab := workspace.active_tab_id
		for tab_entry: Array in tabs_by_workspace.get(workspace_id, []):
			var tab: HerdrSnapshot.Tab = tab_entry[2]
			var room := RoomModel.new()
			room.key = JSON.stringify([machine, workspace_id, tab.tab_id])
			room.tab_id = tab.tab_id
			room.number = tab.number
			room.label = tab.label
			# Absent stays absent: a workspace that names no open tab leaves
			# every one of its tabs unknown, which is not the same as closed.
			if not open_tab.is_empty():
				room.active = RoomModel.Active.YES if tab.tab_id == open_tab else RoomModel.Active.NO
			for pane_entry: Array in panes_by_tab.get(tab.tab_id, []):
				var source: HerdrSnapshot.Pane = pane_entry[1]
				var pane := pane_model(source, states, machine)
				# Neither ownership claim overrides the other. An inconsistent pane
				# remains in panes_of/inspector_pane, but has no proven world seat.
				if pane.workspace_id != workspace_id:
					continue
				pane.focused = not focused_pane.is_empty() and pane.pane_id == focused_pane
				var placed_sides: Dictionary = sides.get(tab.tab_id, {})
				var placed_columns: Dictionary = table_x.get(tab.tab_id, {})
				var placed_side: String = placed_sides.get(pane.pane_id, "")
				pane.table_x = placed_columns.get(pane.pane_id, -1)
				pane.explicit_layout = (placed_columns.has(pane.pane_id) and not placed_side.is_empty())
				var layout_order: int = pane_entry[0]
				pane.layout_order = layout_order if pane.explicit_layout else -1
				# An absent layout does not choose a side. SeatPlanner resolves it
				# from this tab's previous plan or stable pane-key order.
				pane.side = placed_side if pane.explicit_layout else "far"
				pane.workspace_label = floor_model.label
				pane.tab_label = room.label
				if not pane.provider.is_empty() or pane.starting:
					floor_model.agents += 1
				room.panes.append(pane)
			floor_model.rooms.append(room)
		var counts := {"blocked": 0, "done": 0} if is_stale else floor_counts(floor_model)
		floor_model.blocked = counts.blocked
		floor_model.done = counts.done
		floors.append(floor_model)
	group_worktrees(floors, trees)
	return floors


## herdr hangs a linked worktree under the space it was made from, and says so
## only through the repository key both checkouts share. Among one machine's
## `floors` (in herdr's number order, as project() lists them; `trees` holds the
## worktree of each floor that has one, by floor key), a group is every floor
## with the same non-empty repository key. Its parent is the one that is not a
## linked worktree, the lowest number when there are several; its children are
## its linked worktrees, which become mezzanines in herdr's workspace order: the
## parent's number and a letter, A to Z, then AA, AB and on (mezzanine_letters()).
## Without an open parent a group has none, and its worktrees stay floors of
## their own; so do any other non-linked checkouts of the repository. Only the
## display fields change: key, number and rooms stay as they were.
static func group_worktrees(floors: Array[FloorModel], trees: Dictionary[String, HerdrSnapshot.Worktree]) -> void:
	var parents: Dictionary[String, FloorModel] = {}
	for floor_model in floors:
		var tree: HerdrSnapshot.Worktree = trees.get(floor_model.key)
		if tree != null and not tree.repo_key.is_empty() and not tree.is_linked_worktree:
			if not parents.has(tree.repo_key):
				parents[tree.repo_key] = floor_model
	var hung: Dictionary[String, int] = {}
	for floor_model in floors:
		var tree: HerdrSnapshot.Worktree = trees.get(floor_model.key)
		if tree == null or not tree.is_linked_worktree or not parents.has(tree.repo_key):
			continue
		var parent := parents[tree.repo_key]
		var index: int = hung.get(parent.key, 0)
		hung[parent.key] = index + 1
		floor_model.mezzanine_of = parent.key
		floor_model.mezzanine_index = index
		floor_model.level_label = parent.level_label + mezzanine_letters(index)


## The letters of the mezzanine at `index` (0-based) under its floor, counted the
## way spreadsheet columns are: 0 is A, 25 is Z, 26 is AA, 27 AB, 701 ZZ, 702 AAA.
static func mezzanine_letters(index: int) -> String:
	var letters := ""
	var rest := index
	while rest >= 0:
		letters = char(65 + rest % 26) + letters
		rest = floori(rest / 26.0) - 1
	return letters


## `floors` in tree order, the order the building section lists them in: every
## floor that is no mezzanine in the order given, each followed by its mezzanines
## in theirs. A mezzanine whose parent is not among `floors` stands on its own.
static func floor_tree(floors: Array[FloorModel]) -> Array[FloorModel]:
	var keys: Dictionary[String, bool] = {}
	for floor_model in floors:
		keys[floor_model.key] = true
	var hanging: Dictionary[String, Array] = {}
	for floor_model in floors:
		if keys.has(floor_model.mezzanine_of):
			if not hanging.has(floor_model.mezzanine_of):
				hanging[floor_model.mezzanine_of] = []
			hanging[floor_model.mezzanine_of].append(floor_model)
	var tree: Array[FloorModel] = []
	for floor_model in floors:
		if keys.has(floor_model.mezzanine_of):
			continue
		tree.append(floor_model)
		for child: FloorModel in hanging.get(floor_model.key, []):
			tree.append(child)
	return tree


## A floor's own counts of the agents that need a human (OfficeAttention.count()
## over its seated panes), each pane key once, and a key the floor carries twice,
## which it cannot seat, not at all. The one count the minimap's floor row
## reads; the world draws the same done panes one by one, as the paper on
## their desks.
static func floor_counts(floor_model: FloorModel) -> Dictionary:
	var repeated := floor_model.repeated_keys()
	var counted: Array[PaneModel] = []
	for room in floor_model.rooms:
		for pane in room.panes:
			if not repeated.has(pane.key):
				counted.append(pane)
	return OfficeAttention.count(counted)


# --- panes --------------------------------------------------------------------


## One pane as a desk. `states` are the states the art pack has a badge for.
static func pane_model(pane: HerdrSnapshot.Pane, states: PackedStringArray, machine := HerdrFleet.LOCAL) -> PaneModel:
	var status := pane.status()
	if not states.has(status):
		# herdr may grow states this art pack has no badge for.
		status = "unknown"
	var model := PaneModel.new()
	model.pane_id = pane.pane_id
	model.terminal_id = pane.terminal_id
	model.workspace_id = pane.workspace_id
	model.tab_id = pane.tab_id
	model.label = pane.label
	model.session = pane.agent_session
	model.key = HerdrFleet.pane_key(machine, model.pane_id)
	model.provider = pane.agent
	model.state = status
	model.starting = pane.launch_pending
	model.starting_known = pane.launch_pending_known
	model.agent_name = pane.agent_name
	model.cwd = pane.cwd
	model.foreground_cwd = pane.foreground_cwd
	model.terminal_title = pane.terminal_title_stripped
	return model


## Every pane of one machine, in snapshot order, whether or not its tab and
## workspace are there to seat it: how many panes a machine has and who needs a
## human are about the machine, not about what could be placed on a floor. Each
## carries the label of the first workspace and tab with the ids it names, the
## same first-wins rule project() seats a floor by.
static func panes_of(
	snapshot: HerdrSnapshot, states: PackedStringArray, machine := HerdrFleet.LOCAL
) -> Array[PaneModel]:
	var panes: Array[PaneModel] = []
	var workspace_labels: Dictionary[String, String] = {}
	var tab_labels: Dictionary[String, String] = {}
	for workspace in snapshot.workspaces:
		if not workspace_labels.has(workspace.workspace_id):
			workspace_labels[workspace.workspace_id] = workspace.label
	for tab in snapshot.tabs:
		if not tab_labels.has(tab.tab_id):
			tab_labels[tab.tab_id] = tab.label
	for pane in snapshot.panes:
		var model := pane_model(pane, states, machine)
		model.workspace_label = workspace_labels.get(model.workspace_id, "")
		model.tab_label = tab_labels.get(model.tab_id, "")
		panes.append(model)
	return panes


## The pane the inspector shows, carrying the labels of the workspace and tab it
## names, or null when the snapshot has no such pane. Like the panel itself this
## never asks whether the pane could be seated: a pane herdr knows is a pane the
## inspector describes. The office reads it from OfficeFrame.pane(); this is the
## same answer for one snapshot.
static func inspector_pane(
	snapshot: HerdrSnapshot, states: PackedStringArray, machine: String, pane_id: String
) -> PaneModel:
	if pane_id.is_empty():
		return null
	for pane in panes_of(snapshot, states, machine):
		if pane.pane_id == pane_id:
			return pane
	return null


## Herdr's own focused pane on this machine, as a composite key; empty when it
## has none.
static func focus_key(snapshot: HerdrSnapshot, machine: String) -> String:
	var focused := snapshot.focused_pane_id
	return "" if focused.is_empty() else HerdrFleet.pane_key(machine, focused)


# --- layout -------------------------------------------------------------------


## Desks read left to right, so panes follow their terminal rect, not snapshot order.
static func layout_ranks(snapshot: HerdrSnapshot) -> Dictionary:
	var ranks := {}
	for layout in snapshot.layouts:
		var slots: Array = []
		for slot in layout.panes:
			slots.append([slot.x, slot.y, slot.pane_id])
		slots.sort_custom(_by_layout)
		var placed := {}
		for index in slots.size():
			placed[slots[index][2]] = index
		ranks[layout.tab_id] = placed
	return ranks


static func _by_layout(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[2] < b[2] if a[1] == b[1] else a[1] < b[1]


## Which side of a shared table a terminal occupies. Herdr's layout rects are
## the source of truth: y=0 is the far edge and a positive y the near edge.
## Kept apart from layout_ranks(), whose compact shape callers rely on.
static func layout_sides(snapshot: HerdrSnapshot) -> Dictionary:
	var sides := {}
	for layout in snapshot.layouts:
		var placed := {}
		for slot in layout.panes:
			placed[slot.pane_id] = "near" if slot.y > 0 else "far"
		sides[layout.tab_id] = placed
	return sides


## Each tab's seat column per pane: the rank of the pane's layout x among the
## distinct x values of that tab (0, 1, 2 …; the same x is the same column, so
## a near pane still faces the far pane across the divider). A rank, not the raw
## x: a terminal resize scales every x, and the floor must not re-plan for it.
static func layout_x(snapshot: HerdrSnapshot) -> Dictionary:
	var columns := {}
	for layout in snapshot.layouts:
		var xs: Array[int] = []
		for slot in layout.panes:
			if not xs.has(slot.x):
				xs.append(slot.x)
		xs.sort()
		var placed := {}
		for slot in layout.panes:
			placed[slot.pane_id] = xs.find(slot.x)
		columns[layout.tab_id] = placed
	return columns


## Sorts [number, id, record] rows by herdr's number, then by id.
static func by_number(a: Array, b: Array) -> bool:
	return a[1] < b[1] if a[0] == b[0] else a[0] < b[0]


# --- selection ----------------------------------------------------------------
# The office asks these of its OfficeFrame; for a bare list of buildings they
# index it first and give the frame's answer, so each rule is written once.


## Both `picked_key` and `focused` are composite pane keys, and so is the answer
## (see OfficeFrame.effective_selection).
static func effective_selection(buildings: Array[BuildingModel], picked_key: String, focused: String) -> String:
	var indexed := frame_of(buildings)
	indexed.herdr_focus = focused
	return indexed.effective_selection(picked_key)


## Key of the floor a desk sits on, or empty.
static func floor_of(buildings: Array[BuildingModel], pane_key: String) -> String:
	return frame_of(buildings).floor_of(pane_key)


## The floor with this key and the building it stands in, or null.
static func find_floor(buildings: Array[BuildingModel], key: String) -> FloorRef:
	return frame_of(buildings).find_floor(key)


## See OfficeFrame.choose_floor.
static func choose_floor(buildings: Array[BuildingModel], picked_floor: String, active_key: String) -> String:
	return frame_of(buildings).choose_floor(picked_floor, active_key)


## Every floor bottom to top, building after building: the PageUp/PageDown order.
static func floor_order(buildings: Array[BuildingModel]) -> Array[String]:
	return frame_of(buildings).floor_order


## Desks whose agent needs a human, across every live building: blocked first,
## then UNREAD, each in the order wait_order() gives, which is the order a floor's
## pantry is shared out in (OfficeRests): an unknown start first, as the one waiting
## longest, then the earliest start; the projection order breaks every tie.
static func attention_queue(buildings: Array[BuildingModel]) -> Array[String]:
	var blocked: Array[PaneModel] = []
	var unread: Array[PaneModel] = []
	for building_model in buildings:
		if building_model.stale:
			continue
		for floor_model in building_model.floors:
			for room in floor_model.rooms:
				for pane in room.panes:
					# Same rule as OfficeAttention.count: an agent, not still launching.
					if pane.provider.is_empty() or pane.launching():
						continue
					if pane.state == "blocked":
						blocked.append(pane)
					elif pane.state == "done":
						unread.append(pane)
	var queue: Array[String] = []
	for group: Array[PaneModel] in [wait_order(blocked), wait_order(unread)]:
		var ranked: Array[PaneModel] = group
		for pane in ranked:
			queue.append(pane.key)
	return queue


## `panes` in the order they have waited: whoever's state start is unknown
## (PaneModel.state_since < 0) first, as having waited longest, then the
## earliest start first; ties, and the unknown among themselves, keep the order
## `panes` lists them in, which is the projection's. The one ranking of the
## `N` key, a floor's queue and its pantry.
static func wait_order(panes: Array[PaneModel]) -> Array[PaneModel]:
	var entries: Array = []
	for index in panes.size():
		var since := panes[index].state_since
		entries.append([0 if since < 0.0 else 1, maxf(since, 0.0), index])
	# sort_custom is not stable, so the listed order breaks every tie.
	entries.sort_custom(
		func(a: Array, b: Array) -> bool:
			for part in 3:
				if a[part] != b[part]:
					return a[part] < b[part]
			return false
	)
	var result: Array[PaneModel] = []
	for entry: Array in entries:
		var index: int = entry[2]
		result.append(panes[index])
	return result
