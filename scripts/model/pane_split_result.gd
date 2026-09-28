class_name PaneSplitResult
extends RefCounted
## What herdr answered a split with: the new pane's ids, as the office uses
## them to pick the new pane once it is in a snapshot, and never to write to
## it. `from_wire()` is the one place that reads herdr's raw `pane_info`
## result (under the reply's `result`, `{"type": "pane_info", "pane": {...}}`,
## herdr 0.9.0, measured). Ids only, cleaned like the snapshot's: the card's
## footer names the new pane by `pane_id`, as PANE's details name any pane.

## The new pane's id, exactly as herdr spelled it, and its terminal's.
var pane_id := ""
var terminal_id := ""
## The workspace and tab herdr put it in; empty when it did not say.
var workspace_id := ""
var tab_id := ""


## A `pane_info` result as the office reads it; null when it is not one, an id
## is not a clean string, or the pane it names is the one that was split
## (`target_wire_id`): herdr made no new pane that this office could tell.
static func from_wire(result: Variant, target_wire_id: String) -> PaneSplitResult:
	if not result is Dictionary:
		return null
	var envelope: Dictionary = result
	if envelope.get("type") != "pane_info" or not envelope.get("pane") is Dictionary:
		return null
	var pane: Dictionary = envelope.get("pane")
	var split := PaneSplitResult.new()
	split.pane_id = _identifier(pane, "pane_id")
	split.terminal_id = _identifier(pane, "terminal_id")
	if split.pane_id.is_empty() or split.terminal_id.is_empty() or split.pane_id == target_wire_id:
		return null
	split.workspace_id = _identifier(pane, "workspace_id")
	split.tab_id = _identifier(pane, "tab_id")
	return split


## HerdrSnapshot's rule for an opaque id: a string that cleaning would not
## change, or empty.
static func _identifier(item: Dictionary, field: String) -> String:
	if not item.get(field) is String:
		return ""
	var value: String = item[field]
	return value if value == MachineRoster.clean_text(value) else ""
