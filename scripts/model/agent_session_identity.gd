class_name AgentSessionIdentity
extends RefCounted
## An observed agent session, not a task or a claim that its work succeeded.
## The boundary constructs this from strings; consumers never parse raw JSON.

var source := ""
## Like `kind` and `value`, a new value forgets identity_key()'s memo.
var provider := "":
	set(next):
		provider = next
		_key = ""
var kind := "":
	set(next):
		kind = next
		_key = ""
var value := "":
	set(next):
		value = next
		_key = ""

## identity_key()'s memo; empty until it is first asked for, and again whenever
## `provider`, `kind` or `value` is assigned. A key is never empty (a JSON array).
var _key := ""


## Detection provenance can change while the actual session stays the same.
## Worked out once and kept until the session itself changes: every refresh
## asks it of every pane (PaneModel.identity_key()).
func identity_key() -> String:
	if _key.is_empty():
		_key = JSON.stringify([provider, kind, value])
	return _key


## A pane may outlive its terminal or agent. Machine scope belongs to PaneModel.key.
static func runtime_key(terminal: String, agent: String, session: AgentSessionIdentity) -> String:
	return JSON.stringify([terminal, agent, "" if session == null else session.identity_key()])
