class_name CommandAuditEntry
extends RefCounted
## One command in this run's audit (HerdrCommands keeps writes and reads in
## separate bounded rings, in memory only). Known by machine, generation and
## request id together.
##
## Never any terminal text, and nothing herdr said in free text: a read keeps
## its source, line count, byte count and truncation flags, a rejection its
## error code. An input command keeps the key's name, or a line's byte count
## and never its text, and its re-read's byte count and whether it matched.
## The monitor's raw input keeps its category, event count and byte count
## only: never a key's name, never a character.

## Unix time the command was asked for.
var at := 0.0
var machine := ""
var generation := -1
var request_id := ""
## Composite pane key (HerdrFleet.pane_key).
var pane_key := ""
## The herdr method, or empty for a payload the allowlist refused.
var method := ""
## One line: the method and its target, and for a read what came back.
var summary := ""
## Every state the command passed through, oldest first (CommandTicket.State
## names), and the unix time of each.
var states := PackedStringArray()
var times := PackedFloat64Array()
## REFUSED only: CommandRefusal.name_of() of the reason.
var refusal := ""
## REJECTED only: herdr's error code.
var error_code := ""
## Reads only.
var source := ""
var lines := 0
var bytes := 0
var truncated := false
var cut := false
## KEYS only: the key's name (`y`, `1`, `enter`, `esc`).
var key_name := ""
## LINE only: the line's UTF-8 byte count; -1 for everything else.
var line_bytes := -1
## KEYS, LINE and START: the re-read's byte count (-1 when none came back) and whether
## it matched what was seen at the press.
var recheck_bytes := -1
var recheck_matched := false
## The monitor's raw input only: `keys`, `text` or `paste`, never which keys or
## what text; how many input events it carried; and for text and a paste its
## UTF-8 byte count (-1 for keys and everything else).
var category := ""
var events := 0
var text_bytes := -1
## START only: the kind and the name this office made for the agent, both its
## own words (the kind as the snapshot spells a detected agent, cleaned).
var agent_kind := ""
var agent_name := ""
## SPLIT only: `right` or `down`.
var direction := ""
## CLOSE only: what the close takes with it, `pane`, `tab`, `space` or
## `mezzanine` (CloseScope.kind()); the pane's state word is in the summary.
var scope := ""
## SPACE only: the UTF-8 byte count of the directory sent; never the path.
var cwd_bytes := -1
## WORKTREE only: the branch, the office's own validated word (a refused one
## too, cleaned and short); never a label, a path or git's text.
var branch := ""


## Record a state change at `when`.
func record(state_name: String, when: float) -> void:
	states.append(state_name)
	times.append(when)


## The last state recorded; empty before the first.
func last_state() -> String:
	return "" if states.is_empty() else states[states.size() - 1]
