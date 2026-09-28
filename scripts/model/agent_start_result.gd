class_name AgentStartResult
extends RefCounted
## What herdr answered a start with, at once (herdr 0.9.0 answers within a
## millisecond, measured): the agent's name and pane and whether it is still
## launching. It says herdr began typing the kind's command into the shell,
## never that an agent came up: that shows in later snapshots only
## (LaunchWatch). `from_wire()` is the one place that reads herdr's raw
## `agent_started` result.

## The name herdr holds for the agent (remote text: grapheme clusters bounded,
## TerminalText.bound()), and the pane id it answered for, as it spelled it.
var name := ""
var pane_id := ""
## herdr's `launch_pending`: true right after a start.
var launch_pending := false
## How many words herdr typed (`argv`); what they are is remote text and is
## not read.
var argv_count := 0


## An `agent_started` result as the office reads it; null when it is not one,
## it names another pane than `wire_pane_id`, or its name is not a clean string.
static func from_wire(result: Variant, wire_pane_id: String) -> AgentStartResult:
	if not result is Dictionary:
		return null
	var envelope: Dictionary = result
	if envelope.get("type") != "agent_started" or not envelope.get("agent") is Dictionary:
		return null
	var record: Dictionary = envelope.get("agent")
	if not record.get("pane_id") is String or record.get("pane_id") != wire_pane_id:
		return null
	if not record.get("name") is String:
		return null
	var named: String = record.get("name")
	if named.is_empty() or named != MachineRoster.clean_text(named):
		return null
	var started := AgentStartResult.new()
	started.name = TerminalText.bound(named)
	started.pane_id = wire_pane_id
	var flag: Variant = record.get("launch_pending")
	started.launch_pending = flag is bool and flag == true
	var argv: Variant = envelope.get("argv")
	if argv is Array:
		var words: Array = argv
		started.argv_count = words.size()
	return started
