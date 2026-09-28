class_name GitWords
extends RefCounted
## The one line of a git failure worth showing. herdr answers
## `worktree_create_failed` with git's raw stderr: several lines, absolute
## paths, `hint:` lines, once a 2757-character usage dump (measured on 0.9.0).
## headline() keeps the first line that starts with `fatal:` or `error:` (else
## the first line with anything on it), cleaned like every remote string
## (MachineRoster.clean_text(): control and direction characters out; every
## grapheme cluster bounded, TerminalText.bound()) and cut to `limit`
## characters. Pure. The rest of the message is never shown or kept.

const FATAL := "fatal:"
const ERROR := "error:"


## The headline of git's `message`, at most `limit` characters; empty for a
## message with nothing on any line.
static func headline(message: Variant, limit: int) -> String:
	if not message is String:
		return ""
	var text: String = message
	var first := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with(FATAL) or line.begins_with(ERROR):
			first = line
			break
		if first.is_empty():
			first = line
	return TerminalText.bound(MachineRoster.clean_text(first)).left(limit)
