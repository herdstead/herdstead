class_name AgentInfoResult
extends RefCounted
## What herdr answered a launch check with: the agent in a pane as it
## describes it, field for field its snapshot record (herdr 0.9.0, measured).
## `from_wire()` is the one place that reads herdr's raw `agent_info` result.
## A launch herdr gave up answers no result at all (`agent_not_found`).

## herdr's name for the agent and the kind it recognised (remote text:
## grapheme clusters bounded, TerminalText.bound()); its status word.
var name := ""
var agent := ""
var agent_status := ""
## herdr is still launching it, and whether it is ready for input.
var launch_pending := false
var interactive_ready := false


## An `agent_info` result as the office reads it; null when it is not one or
## names another pane than `wire_pane_id`.
static func from_wire(result: Variant, wire_pane_id: String) -> AgentInfoResult:
	if not result is Dictionary:
		return null
	var envelope: Dictionary = result
	if envelope.get("type") != "agent_info" or not envelope.get("agent") is Dictionary:
		return null
	var record: Dictionary = envelope.get("agent")
	if not record.get("pane_id") is String or record.get("pane_id") != wire_pane_id:
		return null
	var info := AgentInfoResult.new()
	info.name = TerminalText.bound(MachineRoster.clean_text(record.get("name")))
	info.agent = TerminalText.bound(MachineRoster.clean_text(record.get("agent")))
	info.agent_status = MachineRoster.clean_text(record.get("agent_status"))
	var pending: Variant = record.get("launch_pending")
	info.launch_pending = pending is bool and pending == true
	var ready: Variant = record.get("interactive_ready")
	info.interactive_ready = ready is bool and ready == true
	return info
