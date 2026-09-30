class_name AgentListModel
extends RefCounted
## What the right-hand agent list shows, as pure static functions: one refresh's
## OfficeFrame, the live attention records and the History lines in, the
## list's entries out, in the order they are drawn. No node, no fleet, no art:
## AgentList draws these.
##
## Two views of the same panes. Flat groups every pane by how urgently it wants
## a human: blocked (who waited longest first, an unknown start first, the order
## of the reception queue and `N`), UNREAD, working, idle, then what is snoozed
## or hidden locally, what stands on a machine that dropped, the shells, and
## History: the panes that needed a human this run and wait no more
## (AgentHistory, from the StateLog). Tree nests them the way herdr does:
## machine, floor, the floor's worktree mezzanines (OfficeProjection.group_worktrees()), tab,
## agent; the shells and panes no floor could seat get groups of their own.
##
## A pane is keyed by its composite key (HerdrFleet.pane_key) in both views, so
## the same row node serves both; a group by its view and what it stands for.

enum Kind { GROUP, PANE, HISTORY }
enum View { FLAT, TREE }
## What a pane's row says about it at a glance. A dropped machine's panes are
## OFFLINE whatever their last state was: a lost connection is never idle.
enum Presence { BLOCKED, UNREAD, WORKING, STARTING, IDLE, UNKNOWN, OFFLINE, SHELL }

## Flat view's groups, top to bottom, with their titles.
const FLAT_WAITING := "flat:waiting"
const FLAT_UNREAD := "flat:unread"
const FLAT_WORKING := "flat:working"
const FLAT_IDLE := "flat:idle"
const FLAT_MUTED := "flat:muted"
const FLAT_OFFLINE := "flat:offline"
const FLAT_SHELLS := "flat:shells"
const FLAT_HISTORY := "flat:history"
const FLAT_GROUPS: Dictionary[String, String] = {
	FLAT_WAITING: "Waiting",
	FLAT_UNREAD: "Unread",
	FLAT_WORKING: "Working",
	FLAT_IDLE: "Idle",
	FLAT_MUTED: "Snoozed / hidden",
	FLAT_OFFLINE: "Offline",
	FLAT_SHELLS: "Shells",
	FLAT_HISTORY: "History",
}
## Groups that start collapsed: plain terminals and the record of the past.
const COLLAPSED_BY_DEFAULT: Array[String] = [FLAT_SHELLS, FLAT_HISTORY, "tree:shells"]
## Deepest indent a row draws; the tree never goes deeper than an agent under a
## tab under a mezzanine under its floor under its machine.
const MAX_DEPTH := 4
## A History line's last state as its badge shows it.
const HISTORY_PRESENCE: Dictionary[String, Presence] = {"blocked": Presence.BLOCKED, "done": Presence.UNREAD}


## One line of the list: a group header, a pane, or a History line.
class Entry:
	extends RefCounted
	var kind := Kind.PANE
	## Composite pane key, `history:<pane key>`, or the group's key.
	var key := ""
	## Key of the group this line sits in; empty at the top.
	var parent := ""
	var depth := 0
	## A group's title; a pane's provider in capitals (`SHELL` for none).
	var title := ""
	## A pane's label, else its tab's; a History line's tab (else its space).
	var detail := ""
	var presence := Presence.UNKNOWN
	## Machine key and herdr's pane id, for the badge's clock.
	var machine := ""
	var pane_id := ""
	var pane: PaneModel
	## The pane's live attention record; null for none (and for a History line).
	var item: AttentionItem
	## A History line: what the StateLog says became of a pane; null otherwise.
	var history: AgentHistory.Line
	## Blocked or UNREAD, but snoozed or hidden locally.
	var muted := false
	## Where the pane stands, for search(): its machine's label and its floor.
	var building_label := ""
	var floor_ref: ZoneRef
	## A group standing for a machine that dropped: no counts, never a state.
	var offline := false
	## A group's lines that build() did not make (a folded History), counted.
	var unbuilt := 0
	## A line's word on the right: UNREAD, OFFLINE, SNOOZED, GONE … (note_of()).
	var note := ""
	# --- filled by apply() -------------------------------------------------------
	## Drawn now: it matches the filter and nothing above it is collapsed.
	var shown := false
	## For a group: the lines under it that match, and of those how many wait.
	var matched := 0
	var waiting := 0
	var unread := 0
	var _search := ""
	var _searched := false

	## Lower-case text the filter box matches: provider, labels, floor, repo,
	## worktree, machine. Made the first time a filter asks, not per refresh.
	func search() -> String:
		if _searched:
			return _search
		_searched = true
		var words := PackedStringArray()
		if pane != null:
			words.append_array([pane.provider, pane.label, pane.tab_label, pane.workspace_label, building_label])
			if floor_ref != null:
				var at := floor_ref.zone_model
				words.append_array([at.label, at.repo, at.worktree])
		elif history != null:
			words.append_array([history.provider, history.space, history.tab, history.machine_label])
		_search = "\n".join(words).to_lower()
		return _search


## Every line of `view`, in drawing order. `active` is AttentionStore.active()
## (the live episodes a row's Snooze and Hide act on), `history` the History
## group's lines (AgentHistory.of()), `now_msec` the clock snoozes are judged by.
## `with_history` false leaves the History group's lines unmade (it is
## folded, and there is no filter): its header still counts them (`unbuilt`).
static func build(
	frame: OfficeFrame,
	active: Array[AttentionItem],
	history: Array[AgentHistory.Line],
	view: View,
	now_msec: int,
	with_history := true
) -> Array[Entry]:
	var live_items := _live_items(active)
	if view == View.TREE:
		return _tree(frame, live_items, now_msec)
	return _flat(frame, history, live_items, now_msec, with_history)


## Mark what is drawn and count every group's matching lines. `collapsed` says
## which group keys are folded (a key it lacks takes COLLAPSED_BY_DEFAULT);
## `query` is the filter box's text; `presences`, when not empty, keeps only
## the panes whose Presence is one of them (the top bar's WORKING and IDLE),
## and no history line. A group with nothing matching under it is not drawn at all.
static func apply(
	entries: Array[Entry], collapsed: Dictionary[String, bool], query: String, presences: Array[Presence] = []
) -> void:
	var needle := query.strip_edges().to_lower()
	var unfiltered := needle.is_empty() and presences.is_empty()
	var groups: Dictionary[String, Entry] = {}
	for entry in entries:
		entry.matched = entry.unbuilt if unfiltered else 0
		entry.waiting = 0
		entry.unread = 0
		if entry.kind == Kind.GROUP:
			groups[entry.key] = entry
	# Count upwards first: a group is drawn only when something under it matches.
	for entry in entries:
		if entry.kind == Kind.GROUP or not _matches(entry, needle, presences):
			continue
		var above: Entry = groups.get(entry.parent)
		while above != null:
			above.matched += 1
			if not entry.muted and entry.presence == Presence.BLOCKED:
				above.waiting += 1
			elif not entry.muted and entry.presence == Presence.UNREAD:
				above.unread += 1
			above = groups.get(above.parent)
	for entry in entries:
		var open := true
		var above: Entry = groups.get(entry.parent)
		while above != null and open:
			open = not is_collapsed(above.key, collapsed)
			above = groups.get(above.parent)
		var matches := entry.matched > 0 if entry.kind == Kind.GROUP else _matches(entry, needle, presences)
		entry.shown = open and matches


## Whether a pane or history line matches the filter box's `needle` and the
## state filter `presences` (empty: every state). A history line is no pane in
## a state, so a state filter leaves it out.
static func _matches(entry: Entry, needle: String, presences: Array[Presence]) -> bool:
	if not presences.is_empty() and (entry.kind != Kind.PANE or not presences.has(entry.presence)):
		return false
	return needle.is_empty() or entry.search().contains(needle)


## The word on the right of a line: what became of a History line's pane
## (OFFLINE, GONE; an ENDED one says nothing: the History group says it ended,
## and its tooltip names it), or a pane's UNREAD / OFFLINE / STARTING, or why
## a waiting one is quiet here.
static func note_of(entry: Entry, _now_msec: int) -> String:
	if entry.kind == Kind.HISTORY:
		return "" if entry.history.what == AgentHistory.ENDED else entry.history.what
	if entry.muted:
		return "HIDDEN" if entry.item.hidden else "SNOOZED"
	match entry.presence:
		Presence.UNREAD:
			return "UNREAD"
		Presence.OFFLINE:
			return "OFFLINE"
		Presence.STARTING:
			return "STARTING"
	return ""


static func is_collapsed(key: String, collapsed: Dictionary[String, bool]) -> bool:
	return collapsed.get(key, COLLAPSED_BY_DEFAULT.has(key))


## A pane as its row shows it: OFFLINE on a dropped machine, SHELL without an
## agent, then launching, then its herdr state.
static func presence_of(pane: PaneModel, stale: bool) -> Presence:
	if pane.provider.is_empty():
		return Presence.SHELL
	if stale:
		return Presence.OFFLINE
	if pane.launching():
		return Presence.STARTING
	match pane.state:
		"blocked":
			return Presence.BLOCKED
		"done":
			return Presence.UNREAD
		"working":
			return Presence.WORKING
		"idle":
			return Presence.IDLE
	return Presence.UNKNOWN


# --- flat ---------------------------------------------------------------------


static func _flat(
	frame: OfficeFrame,
	history: Array[AgentHistory.Line],
	live_items: Dictionary[String, AttentionItem],
	now_msec: int,
	with_history: bool
) -> Array[Entry]:
	var buckets: Dictionary[String, Array] = {}
	for key: String in FLAT_GROUPS:
		buckets[key] = []
	# Blocked and UNREAD are ranked like the reception queue: seated panes by
	# how long they waited (their state_since is stamped), then the unplaced.
	var waiting_seated: Array[PaneModel] = []
	var unread_seated: Array[PaneModel] = []
	var waiting_loose: Array[Entry] = []
	var unread_loose: Array[Entry] = []
	var entries_by_key: Dictionary[String, Entry] = {}
	# Every pane once: seated panes first as their floors seat them (these
	# carry state_since), then the ones no floor could seat.
	for seated: bool in [true, false]:
		for building in frame.buildings:
			var panes: Array[PaneModel] = building.all_panes
			if seated:
				panes = []
				for floor_model in building.zones:
					for room in floor_model.rooms:
						panes.append_array(room.panes)
			for pane in panes:
				if entries_by_key.has(pane.key):
					continue
				var entry := _pane_entry(frame, building, pane, live_items, now_msec)
				entries_by_key[pane.key] = entry
				var group := _flat_group(entry)
				entry.parent = group
				entry.depth = 1
				if group == FLAT_WAITING:
					if seated:
						waiting_seated.append(pane)
					else:
						waiting_loose.append(entry)
				elif group == FLAT_UNREAD:
					if seated:
						unread_seated.append(pane)
					else:
						unread_loose.append(entry)
				else:
					buckets[group].append(entry)
	for pane in OfficeProjection.wait_order(waiting_seated):
		buckets[FLAT_WAITING].append(entries_by_key[pane.key])
	buckets[FLAT_WAITING].append_array(waiting_loose)
	for pane in OfficeProjection.wait_order(unread_seated):
		buckets[FLAT_UNREAD].append(entries_by_key[pane.key])
	buckets[FLAT_UNREAD].append_array(unread_loose)
	if with_history:
		for line in history:
			buckets[FLAT_HISTORY].append(_history_entry(line, now_msec))
	var result: Array[Entry] = []
	for key: String in FLAT_GROUPS:
		var header := _group(key, FLAT_GROUPS[key], "", 0)
		if key == FLAT_HISTORY and not with_history:
			header.unbuilt = history.size()
		result.append(header)
		for entry: Entry in buckets[key]:
			result.append(entry)
	return result


static func _flat_group(entry: Entry) -> String:
	if entry.muted:
		return FLAT_MUTED
	match entry.presence:
		Presence.BLOCKED:
			return FLAT_WAITING
		Presence.UNREAD:
			return FLAT_UNREAD
		Presence.WORKING, Presence.STARTING:
			return FLAT_WORKING
		Presence.OFFLINE:
			return FLAT_OFFLINE
		Presence.SHELL:
			return FLAT_SHELLS
	return FLAT_IDLE


# --- tree ---------------------------------------------------------------------


static func _tree(frame: OfficeFrame, live_items: Dictionary[String, AttentionItem], now_msec: int) -> Array[Entry]:
	var result: Array[Entry] = []
	var shells: Array[Entry] = []
	var seen: Dictionary[String, bool] = {}
	for building in frame.buildings:
		var machine := _group("tree:m:" + building.key, building.label, "", 0)
		machine.offline = building.stale
		result.append(machine)
		var floor_groups: Dictionary[String, Entry] = {}
		for floor_model in building.zone_tree:
			if floor_model.lobby:
				continue
			var parent: Entry = floor_groups.get(floor_model.mezzanine_of, machine)
			var name := "%s  %s" % [floor_model.level_label, floor_model.label]
			var floor_group := _group("tree:f:" + floor_model.key, name.strip_edges(), parent.key, parent.depth + 1)
			floor_group.offline = building.stale
			floor_groups[floor_model.key] = floor_group
			result.append(floor_group)
			for room in floor_model.rooms:
				var title := room.label if not room.label.is_empty() else "Tab %d" % room.number
				var tab := _group("tree:t:" + room.key, title, floor_group.key, floor_group.depth + 1)
				tab.offline = building.stale
				result.append(tab)
				for pane in room.panes:
					if seen.has(pane.key):
						continue
					seen[pane.key] = true
					var entry := _pane_entry(frame, building, pane, live_items, now_msec)
					if entry.presence == Presence.SHELL:
						shells.append(entry)
						continue
					entry.parent = tab.key
					entry.depth = mini(tab.depth + 1, MAX_DEPTH)
					result.append(entry)
		var loose := _group("tree:u:" + building.key, "Not on a floor", machine.key, 1)
		loose.offline = building.stale
		result.append(loose)
		for pane in building.all_panes:
			if seen.has(pane.key):
				continue
			seen[pane.key] = true
			var entry := _pane_entry(frame, building, pane, live_items, now_msec)
			if entry.presence == Presence.SHELL:
				shells.append(entry)
				continue
			entry.parent = loose.key
			entry.depth = 2
			result.append(entry)
	result.append(_group("tree:shells", "Shells", "", 0))
	for entry in shells:
		entry.parent = "tree:shells"
		entry.depth = 1
		result.append(entry)
	return result


# --- lines --------------------------------------------------------------------


static func _pane_entry(
	frame: OfficeFrame,
	building: BuildingModel,
	pane: PaneModel,
	live_items: Dictionary[String, AttentionItem],
	now_msec: int
) -> Entry:
	var entry := Entry.new()
	entry.kind = Kind.PANE
	entry.key = pane.key
	entry.pane = pane
	entry.machine = building.key
	entry.pane_id = pane.pane_id
	entry.presence = presence_of(pane, building.stale)
	entry.title = pane.provider.to_upper() if not pane.provider.is_empty() else "SHELL"
	entry.detail = pane.label if not pane.label.is_empty() else pane.tab_label
	var item: AttentionItem = live_items.get(pane.key)
	if item != null and item.identity_key == pane.identity_key():
		entry.item = item
		entry.muted = (
			entry.presence in [Presence.BLOCKED, Presence.UNREAD] and (item.hidden or item.is_snoozed(now_msec))
		)
	entry.building_label = building.label
	entry.floor_ref = frame.find_floor(frame.floor_of(pane.key))
	entry.note = note_of(entry, now_msec)
	return entry


static func _history_entry(line: AgentHistory.Line, now_msec: int) -> Entry:
	var entry := Entry.new()
	entry.kind = Kind.HISTORY
	entry.key = "history:" + line.key
	entry.parent = FLAT_HISTORY
	entry.depth = 1
	entry.history = line
	entry.machine = line.machine
	entry.presence = HISTORY_PRESENCE.get(line.was, Presence.UNREAD)
	entry.title = line.provider.to_upper() if not line.provider.is_empty() else "AGENT"
	entry.detail = line.tab if not line.tab.is_empty() else line.space
	entry.note = note_of(entry, now_msec)
	return entry


static func _group(key: String, title: String, parent: String, depth: int) -> Entry:
	var entry := Entry.new()
	entry.kind = Kind.GROUP
	entry.key = key
	entry.title = title
	entry.parent = parent
	entry.depth = mini(depth, MAX_DEPTH - 1)
	return entry


## The episode each pane is in now, whether or not it is snoozed or hidden:
## the one record a row's actions act on. Retired records never name a pane;
## of two for one pane (never expected) the newer wins.
static func _live_items(active: Array[AttentionItem]) -> Dictionary[String, AttentionItem]:
	var result: Dictionary[String, AttentionItem] = {}
	for item in active:
		if item.active and not item.retired:
			result[item.pane_key] = item
	return result
