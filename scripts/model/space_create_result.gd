class_name SpaceCreateResult
extends RefCounted
## What herdr answered a `workspace.create` or a `worktree.create` with: the
## new workspace, its tab and its root pane, as the office uses them to name
## the new space and pick its shell once a snapshot shows it, and never to
## write to it. `from_wire()` is the one place that reads herdr's raw
## `workspace_created` / `worktree_created` result (herdr 0.9.0, measured:
## `{type, workspace: WorkspaceInfo, tab: TabInfo, root_pane: PaneInfo}`, the
## worktree one with a `worktree` object too). Ids only, cleaned like the
## snapshot's; the worktree's path and branch are remote text, bounded.

## The new workspace's id, exactly as herdr spelled it, and its tab's.
var workspace_id := ""
var tab_id := ""
## The root pane's id and its terminal's.
var pane_id := ""
var terminal_id := ""
## A worktree result's checkout path and branch (remote text, grapheme
## clusters bounded); empty for a workspace result.
var worktree_path := ""
var worktree_branch := ""
## Whether herdr answered `worktree_created`.
var linked := false


## A `workspace_created` or `worktree_created` result as the office reads it;
## null when it is neither, or any id is not a clean string.
static func from_wire(result: Variant) -> SpaceCreateResult:
	if not result is Dictionary:
		return null
	var envelope: Dictionary = result
	var type: Variant = envelope.get("type")
	if type != "workspace_created" and type != "worktree_created":
		return null
	if not envelope.get("workspace") is Dictionary or not envelope.get("root_pane") is Dictionary:
		return null
	var workspace: Dictionary = envelope.get("workspace")
	var pane: Dictionary = envelope.get("root_pane")
	var tab: Dictionary = envelope.get("tab") if envelope.get("tab") is Dictionary else {}
	var created := SpaceCreateResult.new()
	created.workspace_id = _identifier(workspace, "workspace_id")
	created.tab_id = _identifier(tab, "tab_id")
	created.pane_id = _identifier(pane, "pane_id")
	created.terminal_id = _identifier(pane, "terminal_id")
	if created.workspace_id.is_empty() or created.pane_id.is_empty() or created.terminal_id.is_empty():
		return null
	created.linked = type == "worktree_created"
	if envelope.get("worktree") is Dictionary:
		var tree: Dictionary = envelope.get("worktree")
		created.worktree_path = TerminalText.bound(MachineRoster.clean_text(tree.get("path")))
		created.worktree_branch = TerminalText.bound(MachineRoster.clean_text(tree.get("branch")))
	return created


## HerdrSnapshot's rule for an opaque id: a string that cleaning would not
## change, or empty.
static func _identifier(item: Dictionary, field: String) -> String:
	if not item.get(field) is String:
		return ""
	var value: String = item[field]
	return value if value == MachineRoster.clean_text(value) else ""
