class_name CloseScope
extends RefCounted
## What closing one pane takes with it, read off a typed snapshot and nothing
## else (pure): herdr closes a tab with its last pane and a workspace with its
## last tab (measured on 0.9.0, no confirmation), and refuses the last pane of a
## workspace whose linked worktrees are open (`confirmation_required`). The
## card's two-click confirm says these words, the boundary carries the
## signature and refuses a close whose scope changed since the first click.
## Counted from the lists: the typed snapshot has no pane or tab counts, and
## none is added for this.

## Herdr's own word for the pane's agent state, or `shell` for no agent, or
## `starting` while herdr is still launching it and it does not ask yet
## (blocked comes first, as everywhere: a start that asks at once).
const SHELL := "shell"
const STARTING := "starting"

## The pane's terminal: another terminal under the same pane id between the
## two clicks is another close (the boundary refuses it by identity too).
var terminal_id := ""
## The pane's tab and workspace ids, as the office spells them.
var tab_id := ""
var workspace_id := ""
## How many panes the tab lists, and how many tabs the workspace lists (this
## one included).
var panes_in_tab := 0
var tabs_in_space := 0
## The workspace's number and label, for the words.
var space_number := 0
var space_label := ""
## The mezzanine's level label (`3A`) when the workspace is a linked worktree
## hung under an open parent, as the FLOORS column names it; the workspace's
## own number as text otherwise.
var level_label := ""
## Closing this pane closes its tab; closing it closes its workspace.
var last_of_tab := false
var last_of_space := false
## The workspace is a linked worktree (a mezzanine): its checkout stays on disk.
var mezzanine := false
## The workspace is the repository's own checkout and another workspace on the
## machine shares its repository: herdr would take the whole group. Never sent.
var group_parent := false
## The agent this pane runs (its kind, `codex`), or empty for a shell.
var agent := ""
## The name herdr gave the pane's agent (`claude-2`); what names a launch
## herdr has not recognised yet. Empty for a plain shell.
var agent_name := ""
## The pane's state word: `shell`, `starting`, or herdr's status.
var state := ""
## The pane was not in the snapshot at all.
var missing := true


## The scope of closing pane `pane_id` (the office's cleaned id) of `snapshot`.
## A pane the snapshot does not list reads as missing, with nothing counted.
static func of(snapshot: HerdrSnapshot, pane_id: String) -> CloseScope:
	var scope := CloseScope.new()
	if snapshot == null:
		return scope
	var pane: HerdrSnapshot.Pane = null
	for listed in snapshot.panes:
		if listed.pane_id == pane_id:
			pane = listed
			break
	if pane == null:
		return scope
	scope.missing = false
	scope.terminal_id = pane.terminal_id
	scope.tab_id = pane.tab_id
	scope.workspace_id = pane.workspace_id
	scope.agent = pane.agent
	scope.agent_name = pane.agent_name
	# A launch herdr has not recognised yet has no agent and is still a start
	# to kill; blocked comes before starting, as everywhere.
	if pane.launch_pending and pane.status() != str(ArtContract.STATE_BLOCKED):
		scope.state = STARTING
	elif pane.agent.is_empty():
		scope.state = SHELL
	else:
		scope.state = pane.status()
	for listed in snapshot.panes:
		if listed.tab_id == pane.tab_id:
			scope.panes_in_tab += 1
	for tab in snapshot.tabs:
		if tab.workspace_id == pane.workspace_id:
			scope.tabs_in_space += 1
	scope.last_of_tab = scope.panes_in_tab <= 1
	scope.last_of_space = scope.last_of_tab and scope.tabs_in_space <= 1
	var workspace: HerdrSnapshot.Workspace = null
	for listed in snapshot.workspaces:
		if listed.workspace_id == pane.workspace_id:
			workspace = listed
			break
	if workspace == null:
		return scope
	scope.space_number = workspace.number
	scope.space_label = workspace.label
	scope.level_label = str(workspace.number)
	var tree := workspace.worktree
	if tree == null:
		return scope
	scope.mezzanine = tree.is_linked_worktree
	if tree.repo_key.is_empty():
		return scope
	if tree.is_linked_worktree:
		scope.level_label = _mezzanine_label(snapshot, workspace)
	elif scope.last_of_space:
		# Another checkout of the same repository open here: herdr takes the
		# group with the parent (0.7.4 source; 0.9.0 answers confirmation_required).
		for other in snapshot.workspaces:
			if other != workspace and other.worktree != null and other.worktree.repo_key == tree.repo_key:
				scope.group_parent = true
				break
	return scope


## `3A`: the parent's number and the mezzanine's letter, the way
## OfficeProjection.group_worktrees() hangs it (the parent is the lowest
## numbered non-linked checkout of the repository; the letters follow herdr's
## workspace order). The workspace's own number when no parent is open.
static func _mezzanine_label(snapshot: HerdrSnapshot, workspace: HerdrSnapshot.Workspace) -> String:
	var repo_key := workspace.worktree.repo_key
	var ordered := snapshot.workspaces.duplicate()
	ordered.sort_custom(
		func(a: HerdrSnapshot.Workspace, b: HerdrSnapshot.Workspace) -> bool: return a.number < b.number
	)
	var parent: HerdrSnapshot.Workspace = null
	for listed: HerdrSnapshot.Workspace in ordered:
		var tree := listed.worktree
		if tree != null and tree.repo_key == repo_key and not tree.is_linked_worktree:
			parent = listed
			break
	if parent == null:
		return str(workspace.number)
	var index := 0
	for listed: HerdrSnapshot.Workspace in ordered:
		var tree := listed.worktree
		if tree == null or tree.repo_key != repo_key or not tree.is_linked_worktree:
			continue
		if listed == workspace:
			return str(parent.number) + OfficeProjection.mezzanine_letters(index)
		index += 1
	return str(workspace.number)


## Who the close kills, for the words: the agent's kind in capitals, else the
## name herdr gave a launch it has not recognised yet; empty for a plain shell.
func who() -> String:
	if not agent.is_empty():
		return agent.to_upper()
	return agent_name.to_upper() if state == STARTING else ""


## The scope's kind for the audit: `pane`, `tab`, `space` or `mezzanine`.
func kind() -> String:
	if last_of_space:
		return "mezzanine" if mezzanine else "space"
	return "tab" if last_of_tab else "pane"


## Every field, as one string: two scopes that would close the same things
## the same way have the same signature. The pane's state is part of it: a
## close confirmed for an idle agent is not one for a working one.
func signature() -> String:
	return (
		JSON
		. stringify(
			[
				missing,
				terminal_id,
				tab_id,
				workspace_id,
				panes_in_tab,
				tabs_in_space,
				space_number,
				space_label,
				level_label,
				last_of_tab,
				last_of_space,
				mezzanine,
				group_parent,
				agent,
				agent_name,
				state,
			]
		)
	)
