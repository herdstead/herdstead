class_name NewsItem
extends RefCounted
## One entry of the NEWS strip: a StateLog event in herdr's words, and the pane
## a click on it picks. Built by the office from the log and the frame it just
## drew; the strip only shows it. The EVENTS tab's rows say the same event in
## the same words (subject() and what()), on two lines.
##
## Only herdr's words: blocked, done, working, idle, offline, online, pane,
## terminal, agent, session, starting. A duration is always the length of the segment the event ended,
## so it is written after the state that ended and before an arrow to the one
## that began (`working 38m → done`): `done · 38m` read as done for 38m. It is
## OfficeAttention's form (`38m`), with `+` when that segment began before this
## office watched (at least that long).
const TIP_PICK := "Show this pane"
const TIP_GONE := "Pane gone"
## What a REPLACED pane got (StateLog.Changed); `new terminal` when the log did not say.
const _REPLACED: Dictionary[StateLog.Changed, String] = {
	StateLog.Changed.NONE: "new terminal",
	StateLog.Changed.TERMINAL: "new terminal",
	StateLog.Changed.AGENT: "new agent",
	StateLog.Changed.SESSION: "new session",
}

## StateLog.Event.id: the newer entry has the larger id.
var id := -1
var text := ""
## HerdrFleet.pane_key of the pane the event is about; empty for a machine's.
var pane_key := ""
## A click picks the pane: it is still in the frame the entry was built from.
var pickable := false
var tip := ""


## `event` as the strip says it, against `frame` (the office's latest):
## `11:40 CODEX ui working 38m → done`, `11:31 bee offline`, `@ bee` after a pane's
## when there is more than one machine.
static func of(event: StateLog.Event, frame: OfficeFrame) -> NewsItem:
	var item := NewsItem.new()
	item.id = event.id
	item.pane_key = event.pane_key
	item.text = (
		"%s %s %s%s" % [OfficeAttention.wall_clock(event.wall_unix), subject(event), what(event), where(event, frame)]
	)
	if is_machine(event):
		item.tip = "%s · %s" % [event.machine_label, what(event)]
	else:
		item.pickable = frame.pane(event.pane_key) != null
		item.tip = TIP_PICK if item.pickable else TIP_GONE
	return item


## Whether `event` is about a machine rather than one of its panes.
static func is_machine(event: StateLog.Event) -> bool:
	return event.kind == StateLog.Kind.MACHINE_ONLINE or event.kind == StateLog.Kind.MACHINE_OFFLINE


## Who the event is about: `CODEX ui` (the provider, as the agent list writes
## it, and the workspace), `CLAUDE-2 web` for an agent herdr named and has not
## recognised yet (the seconds after a start), `SHELL notes` for a pane without
## an agent, or the machine's name.
static func subject(event: StateLog.Event) -> String:
	if is_machine(event):
		return event.machine_label
	var agent := event.agent.to_upper()
	if event.agent.is_empty():
		agent = "SHELL" if event.agent_name.is_empty() else event.agent_name.to_upper()
	var space := OfficeTotals.UNNAMED_SPACE if event.space.is_empty() else event.space
	return "%s %s" % [agent, space]


## What happened, in herdr's words: `working 38m → done`, `idle 2s+ →
## blocked`, `working · new pane`, `pane closed`, `idle · new terminal`,
## `new agent · starting`, `starting` (herdr began launching an agent in a
## shell), `offline`. A change whose ended segment is not a watched state of herdr's
## (the log's first sight of it, unknown, not observed) says only the state it
## went to (`blocked`). A pane with no state of herdr's (a shell, an agent
## still launching) says only what happened to the pane.
static func what(event: StateLog.Event) -> String:
	match event.kind:
		StateLog.Kind.MACHINE_ONLINE:
			return "online"
		StateLog.Kind.MACHINE_OFFLINE:
			return "offline"
		StateLog.Kind.GONE:
			return "pane closed"
		StateLog.Kind.APPEARED:
			return _starting(event, _with_state(event.state, "new pane"))
		StateLog.Kind.REPLACED:
			return _starting(event, _with_state(event.state, _REPLACED[event.changed]))
		StateLog.Kind.LAUNCH:
			return "starting"
	var before := ended(event)
	if before.is_empty():
		return event.state
	return "%s → %s" % [before, event.state]


## The state a change ended and how long it lasted (`working 38m`), for what()
## and the EVENTS row's second line; empty when the change ended no watched
## state of herdr's, or `event` is not a change of state.
static func ended(event: StateLog.Event) -> String:
	if event.kind != StateLog.Kind.STATE or event.for_msec < 0:
		return ""
	if not StateLog.STATES.has(event.previous_state) or not StateLog.STATES.has(event.state):
		return ""
	return "%s %s" % [event.previous_state, lasted(event)]


## How long the segment `event` ended lasted: `38m`, `12s+`; empty for none.
static func lasted(event: StateLog.Event) -> String:
	if event.for_msec < 0:
		return ""
	return OfficeAttention.format_duration(event.for_msec / 1000.0) + ("+" if event.for_plus else "")


## ` @ bee` after a pane's event once the office shows more than one machine.
static func where(event: StateLog.Event, frame: OfficeFrame) -> String:
	if is_machine(event) or not frame.several_machines():
		return ""
	return " @ " + event.machine_label


## `happened`, and ` · starting` after it while herdr is launching the pane's agent.
static func _starting(event: StateLog.Event, happened: String) -> String:
	return happened + " · starting" if event.starting else happened


static func _with_state(state: String, happened: String) -> String:
	if state.is_empty() or state == StateLog.UNKNOWN:
		return happened
	return "%s · %s" % [state, happened]
