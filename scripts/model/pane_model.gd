class_name PaneModel
extends RefCounted
## One herdr pane as the office draws it: a seat at a tab's shared table.
##
## Built by OfficeProjection out of a HerdrSnapshot and nothing else. The pane
## inspector reads one of these too, so it also carries what that panel shows,
## and no drawing code ever goes back to the snapshot for a pane.

## Herdr's own pane id, exactly as the snapshot spells it.
var pane_id := ""
## A pane can keep its id while the underlying terminal or session is replaced.
## Like `provider` and `session`, a new value forgets identity_key()'s memo.
var terminal_id := "":
	set(value):
		terminal_id = value
		_identity = ""
var workspace_id := ""
var tab_id := ""
var label := ""
var session: AgentSessionIdentity:
	set(value):
		session = value
		_identity = ""
## Machine key and pane id together (see HerdrFleet.pane_key). Pane ids repeat
## across machines, so this, never `pane_id`, is what names a desk.
var key := ""
## The agent working here; empty is a plain shell.
var provider := "":
	set(value):
		provider = value
		_identity = ""
## Agent status as the art pack knows it: a state it has no badge for is "unknown".
var state := "unknown"
## Herdr is still launching the agent (`launch_pending` as herdr sends it), so
## its status says nothing about it yet, unless it is blocked: see asks() and
## launching(), which every "needs a human" and "still starting" channel reads.
var starting := false
## Matched AgentInfo has a boolean flag, or omits its documented false default.
var starting_known := false
## The name herdr lists for the agent in this pane (`claude-2`); what a seat and
## the card say while a start is launching and no kind is detected yet. Empty
## with none.
var agent_name := ""
## Herdr's own session focus is on this pane: the terminal the user is looking
## at. Only one pane of a machine has it, and a machine may have none. It is not
## Herdstead's selection, which is the viewer's own (see OfficeNavigator.picked_key).
var focused := false
## Which long edge of the table this seat is on: "near" or "far".
var side := "far"
## The seat column's rank in its tab (OfficeProjection.layout_x()); -1 for a pane
## herdr never placed.
var table_x := -1
## A missing terminal layout is a hint to retain the previous seat, not a side.
var explicit_layout := false
## Reading order inside this tab's explicit terminal layout.
var layout_order := -1
## The pane's working directory as the snapshot carries it.
var cwd := ""
## The foreground process may work somewhere else than the pane's shell.
var foreground_cwd := ""
## The terminal title with its escape sequences stripped: free text of any length.
var terminal_title := ""
## Label of the workspace this pane names; empty when the snapshot has no such workspace.
var workspace_label := ""
## Label of the tab this pane names; empty when the snapshot has no such tab.
var tab_label := ""
## Unix time this pane's state began, as the fleet counted it (HerdrFleet.state_since);
## -1 when unknown: first seen already in it, after a reconnect, or a new session.
## Filled by the office's frame builder on the panes seated on a floor (the
## frame's list of every pane leaves it -1), never by the projection, and never part
## of desk_signature(): who waits longest orders the queue and the pantry
## (OfficeRests) and the `N` key (OfficeProjection.attention_queue()).
var state_since := -1.0

## identity_key()'s memo; empty until it is first asked for, and again whenever
## `terminal_id`, `provider` or `session` is assigned. A key is never empty (a JSON array).
var _identity := ""
## The session's own key the memo was worked out with: a session changed in
## place (AgentSessionIdentity keeps its own memo) is another identity.
var _identity_session := ""


## The machine this desk stands on, as the fleet keys it.
func machine() -> String:
	return HerdrFleet.split_key(key)[0]


## The terminal, agent and session this seat holds (AgentSessionIdentity.runtime_key()):
## worked out on the first call and kept until one of the three is assigned
## again or the session's own key changes. Every refresh asks it of every pane
## several times (the start stamps, the sightings, attention, the agent list),
## and each was a JSON.stringify.
func identity_key() -> String:
	var session_key := "" if session == null else session.identity_key()
	if _identity.is_empty() or session_key != _identity_session:
		_identity = AgentSessionIdentity.runtime_key(terminal_id, provider, session)
		_identity_session = session_key
	return _identity


## The pane needs a human: an agent there and herdr says blocked, whether or
## not it is still launching (blocked comes first: a start that asks at once).
func asks() -> bool:
	return not provider.is_empty() and state == str(ArtContract.STATE_BLOCKED)


## herdr is still launching the pane's agent and it has not asked anything yet.
func launching() -> bool:
	return starting and not asks()


## The last path component of `cwd`, which is all the inspector has room for.
func cwd_name() -> String:
	return cwd.trim_suffix("/").get_file()


## What this desk shows, apart from whether it is selected. A change here
## redraws that one desk (see OfficeStation.furnish). `focused` is deliberately
## not part of it: herdr's focus only moves a lamp, which has its own channel
## (OfficeFloorView.Seat.lit), and seating the worker again for it would restart
## their badge's pulse and blank a blocked agent's wait until the next beat.
func desk_signature() -> String:
	return JSON.stringify([provider, state, launching(), agent_name, side, table_x])
