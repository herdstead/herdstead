class_name StateLog
extends RefCounted
## What this office saw of every pane since it opened: each pane's state as
## segments on one track, and one bounded ring of events (a state changed, a
## pane appeared, went or got another terminal, agent or session, herdr began
## launching an agent in a shell, a machine came or went). The
## NEWS strip, the EVENTS tab and the OVERVIEW read it; nothing here is saved,
## and none of it is terminal text.
##
## It keeps no clock of its own. When a state began is HerdrClient's StateClock
## (the one the top bar's `max`, the card and the chips read too); the fleet
## hands it in with every pane as a Sighting, and a segment whose start that
## clock knows starts there. One whose start it does not know (the first
## snapshot of a connection) starts when this log first saw it and reads `+`:
## at least that long. Durations are HerdrFleet's monotonic milliseconds,
## handed in. Wall-clock time labels a segment or an event, stamped once; the
## one subtraction is _start_of(), which turns StateClock.since (unix seconds)
## into this log's milliseconds once, when a segment opens, and _open() clamps
## the result between the end of the segment before it (or the log's first
## observation) and now, so a wall clock that jumps moves a start at most to
## one of those edges.
##
## Pane ids repeat across machines: a track is keyed by HerdrFleet.pane_key.
## Bounded: EVENTS_MAX events, SEGMENTS_MAX segments per track (the oldest two
## fold into one unobserved, `elided` segment; a track's totals are kept apart
## and survive it), GONE_TRACKS_MAX tracks of panes that went. Live tracks are
## bounded by HerdrSnapshot.MAX_PANES per machine.

enum Kind { STATE, APPEARED, GONE, REPLACED, MACHINE_ONLINE, MACHINE_OFFLINE, LAUNCH }
## What a REPLACED event's pane got: another terminal, another agent in the
## same terminal, or another session of the same agent. NONE for every other event.
enum Changed { NONE, TERMINAL, AGENT, SESSION }

const EVENTS_MAX := 512
const SEGMENTS_MAX := 256
const GONE_TRACKS_MAX := 1024
## herdr's four words; anything else (a shell's absent status, launch pending) reads as UNKNOWN.
const STATES: Array[String] = ["blocked", "done", "working", "idle"]
const UNKNOWN := "unknown"


## One pane as the fleet sees it in one observation; built by HerdrFleet, never by the log.
class Sighting:
	## HerdrFleet.pane_key.
	var pane_key := ""
	## What StateClock.identity holds: AgentSessionIdentity.runtime_key() of the
	## terminal, agent and session, empty for a pane without a terminal id.
	var identity := ""
	## Pane.status(), before the STATES check.
	var status := ""
	var starting := false
	## HerdrClient.StateClock.since: the one clock. -1 when its start is unknown.
	var since_unix := -1.0
	## StateClock.missing: absent from this one snapshot, its clock kept.
	var missing := false
	## Copies of from_wire()'s bounded strings, taken here.
	var agent := ""
	var space := ""
	var tab := ""
	## The pane's terminal id, and the name herdr gave its agent (empty for none).
	var terminal_id := ""
	var agent_name := ""


## A stretch of one pane's time in one state, or a stretch nobody watched.
class Segment:
	## One of STATES, UNKNOWN, or "" for an unobserved stretch.
	var state := ""
	## False: an unobserved stretch (before the pane appeared, machine offline, after it went).
	var observed := true
	## The state began while this office watched (since_unix >= 0); false reads `+`.
	var observed_start := true
	## SEGMENTS_MAX folded older segments into this one.
	var elided := false
	var start_msec := 0
	## -1 while open.
	var end_msec := -1
	## Wall-clock label, stamped once at record time; never used for arithmetic.
	var start_unix := 0.0


## One pane's segments, oldest first, and its blocked totals.
class Track:
	var key := ""
	var machine := ""
	var machine_label := ""
	var agent := ""
	var space := ""
	var tab := ""
	var identity := ""
	var terminal_id := ""
	var agent_name := ""
	## herdr was launching the pane's agent when last seen.
	var starting := false
	var segments: Array[StateLog.Segment] = []
	## Closed, observed blocked time (the open one is added by blocked_for()).
	var blocked_msec := 0
	## Some blocked segment's start was not observed.
	var blocked_plus := false
	## Blocked segments, the baseline one included.
	var times := 0
	var gone := false
	var gone_msec := -1
	## Index of the first segment of the pane's current agent run: 0 until
	## another terminal, agent or session comes up in the pane (_restart());
	## it moves with its segment when the oldest ones fold (_append()).
	var run_start := 0


## How long a pane has been in the state it is in now, as this log saw it:
## what the OVERVIEW's FOR, the top bar's `max` and the counters' hover all
## say (wait_of(), longest()), so they never disagree.
class Wait:
	## The open segment's observed length; 0 when none is open or it is unobserved.
	var msec := 0
	## That segment began before this office watched: at least `msec`.
	var plus := false


class Event:
	var id := 0
	var kind := StateLog.Kind.STATE
	var msec := 0
	var wall_unix := 0.0
	var machine := ""
	var machine_label := ""
	var pane_key := ""
	var agent := ""
	var space := ""
	var tab := ""
	var state := ""
	var previous_state := ""
	## Length of the segment this event ended (its observed part); -1 for none.
	var for_msec := -1
	var for_plus := false
	## herdr was launching the pane's agent at the event, and the name it gave it.
	var starting := false
	var agent_name := ""
	## REPLACED only: what the pane got.
	var changed := StateLog.Changed.NONE


## Moves on every change the log records, whether or not it writes an event
## (a label, a machine forgotten, a fold); an observation that changes nothing
## leaves it. What a model built from the log may be kept by (AgentHistory.Cache).
var version := 0

## The first observe(): the timeline's left edge and its label.
var opened_msec := -1
var opened_unix := -1.0

var _events: Array[Event] = []
var _next_id := 0
## Every track, live and gone, in the order they were opened.
var _tracks: Array[Track] = []
## Pane key -> its track while the pane is there.
var _live: Dictionary[String, Track] = {}
## Tracks that went, in the order they went (so by gone_msec).
var _gone: Array[Track] = []
## Machine key -> whether its last observation was online, and what it was called.
var _online: Dictionary[String, bool] = {}
var _labels: Dictionary[String, String] = {}
## The latest now_msec handed in: time never runs backwards here.
var _last_msec := -1


## One observation of machine `machine` (shown as `label`): online (a live
## connection with a current snapshot) with its panes `seen`, or not. Called
## on every snapshot, status event and liveness change, often twice for one;
## the same observation twice records nothing new.
func observe(
	machine: String, label: String, online: bool, seen: Array[Sighting], now_msec: int, now_unix: float
) -> void:
	var now := _tick(now_msec, now_unix)
	if _labels.get(machine, "") != label or not _labels.has(machine):
		_labels[machine] = label
		version += 1
	if not online:
		# The clocks may already be gone (a disconnect clears them after it says
		# the snapshot is stale, a refusal before): `seen` is not read.
		_go_offline(machine, label, now, now_unix)
		return
	if not _online.get(machine, false):
		_come_online(machine, label, seen, now, now_unix)
		return
	var present: Dictionary[String, bool] = {}
	for sighting in seen:
		present[sighting.pane_key] = true
		# Missing from one snapshot is not gone: the segment runs on.
		if sighting.missing:
			continue
		var kept: Track = _live.get(sighting.pane_key)
		if kept == null:
			kept = _open_track(machine, label, sighting)
			_open(kept, sighting, now, now_unix)
			_record(Kind.APPEARED, now, now_unix, kept, null)
			continue
		_relabel(kept, label)
		var open := _last(kept)
		var replaced := (
			not kept.identity.is_empty() and not sighting.identity.is_empty() and kept.identity != sighting.identity
		)
		var state := _state_of(sighting)
		if not replaced and state == open.state:
			# herdr began launching an agent in this shell: the state says
			# nothing yet (unknown before, unknown now), so no new segment.
			var launched := not kept.starting and sighting.starting
			_copy_labels(kept, sighting)
			if launched:
				_record(Kind.LAUNCH, now, now_unix, kept, null)
			continue
		var ended := _close(kept, _start_of(sighting, now, now_unix), now)
		var changed := _changed(kept, sighting) if replaced else Changed.NONE
		if replaced:
			_restart(kept)
		_copy_labels(kept, sighting)
		_open(kept, sighting, now, now_unix)
		_record(Kind.REPLACED if replaced else Kind.STATE, now, now_unix, kept, ended, changed)
	for key: String in _live.keys():
		var kept := _live[key]
		if kept.machine == machine and not present.has(key):
			var ended := _close(kept, now, now)
			_unobserved(kept, now, now_unix)
			_record(Kind.GONE, now, now_unix, kept, ended)
			_retire(kept, now)


## A machine left the roster, or its key now names another connection: it goes
## offline here, and every pane it had goes with it.
func forget_machine(machine: String, now_msec: int, now_unix: float) -> void:
	var now := _tick(now_msec, now_unix)
	_go_offline(machine, _labels[machine] if _labels.has(machine) else "", now, now_unix)
	var forgot := _online.erase(machine)
	if _labels.erase(machine) or forgot:
		version += 1
	for key: String in _live.keys():
		var kept := _live[key]
		if kept.machine == machine:
			_retire(kept, now)


## Every event kept, oldest first.
func events() -> Array[Event]:
	return _events.duplicate()


## The track pane `key` has now (live, or the last one that went); null when none.
func track(key: String) -> Track:
	var live: Track = _live.get(key)
	if live != null:
		return live
	for index in range(_tracks.size() - 1, -1, -1):
		if _tracks[index].key == key:
			return _tracks[index]
	return null


## Every track kept, live and gone, in the order they were opened.
func tracks() -> Array[Track]:
	return _tracks.duplicate()


## How long the track's open segment has been observed; 0 when none is open or
## its stretch is unobserved. wait_of()'s `msec`.
func state_for(of: Track, now_msec: int) -> int:
	return StateLog.wait_of(of, now_msec).msec


## The one rule for "how long in this state": the track's open, observed
## segment up to `now_msec`, with `plus` when its start came before this log
## watched (the first snapshot of a connection). 0 and no `plus` for a null
## track, a closed one, or an unobserved stretch (its machine is away).
static func wait_of(of: Track, now_msec: int) -> Wait:
	var wait := Wait.new()
	if of == null or of.segments.is_empty():
		return wait
	var open := _last(of)
	if open.end_msec >= 0 or not open.observed:
		return wait
	wait.msec = maxi(now_msec - open.start_msec, 0)
	wait.plus = not open.observed_start
	return wait


## The longest wait_of() among `of`, `plus` when any of them began unwatched
## (a null track, one the log never saw, counts as that): a longer one may hide
## behind it, so the longest is only a lower bound. The top bar's `max`.
static func longest(of: Array[Track], now_msec: int) -> Wait:
	var result := Wait.new()
	for kept in of:
		if kept == null:
			result.plus = true
			continue
		var wait := StateLog.wait_of(kept, now_msec)
		result.msec = maxi(result.msec, wait.msec)
		result.plus = result.plus or wait.plus
	return result


## Observed blocked time on the track: its closed blocked segments and the open one.
func blocked_for(of: Track, now_msec: int) -> int:
	if of == null:
		return 0
	var result := of.blocked_msec
	if not of.segments.is_empty():
		var open := _last(of)
		if open.end_msec < 0 and open.observed and open.state == "blocked":
			result += maxi(now_msec - open.start_msec, 0)
	return result


## How long since the first observe(); 0 before it.
func since_opened(now_msec: int) -> int:
	return 0 if opened_msec < 0 else maxi(now_msec - opened_msec, 0)


## The newest event's id; -1 before any.
func last_id() -> int:
	return _next_id - 1


# --- recording ----------------------------------------------------------------


func _tick(now_msec: int, now_unix: float) -> int:
	var now := maxi(now_msec, _last_msec)
	_last_msec = now
	if opened_msec < 0:
		opened_msec = now
		opened_unix = now_unix
	return now


func _go_offline(machine: String, label: String, now: int, now_unix: float) -> void:
	if not _online.get(machine, false):
		return
	_online[machine] = false
	for kept: Track in _live.values():
		if kept.machine == machine:
			var open := _last(kept)
			if open.observed:
				_close(kept, now, now)
				_unobserved(kept, now, now_unix)
	_record_machine(Kind.MACHINE_OFFLINE, now, now_unix, machine, label)


## The baseline: every pane opens a segment and none of them is an event, as
## on the first snapshot, after a gap, a refusal or a replacement. A pane seen
## before (a reconnect) keeps its track; one that went while nobody watched
## goes quietly.
func _come_online(machine: String, label: String, seen: Array[Sighting], now: int, now_unix: float) -> void:
	_online[machine] = true
	_record_machine(Kind.MACHINE_ONLINE, now, now_unix, machine, label)
	var present: Dictionary[String, bool] = {}
	for sighting in seen:
		present[sighting.pane_key] = true
		var kept: Track = _live.get(sighting.pane_key)
		if kept == null:
			kept = _open_track(machine, label, sighting)
		else:
			_relabel(kept, label)
			_close(kept, now, now)
			if not kept.identity.is_empty() and not sighting.identity.is_empty() and kept.identity != sighting.identity:
				# Another agent run came up while nobody watched: its totals start over.
				_restart(kept)
			_copy_labels(kept, sighting)
		_open(kept, sighting, now, now_unix)
	for key: String in _live.keys():
		var kept := _live[key]
		if kept.machine == machine and not present.has(key):
			_retire(kept, now)


func _open_track(machine: String, label: String, sighting: Sighting) -> Track:
	var kept := Track.new()
	kept.key = sighting.pane_key
	kept.machine = machine
	kept.machine_label = label
	_copy_labels(kept, sighting)
	_tracks.append(kept)
	version += 1
	_live[kept.key] = kept
	return kept


func _copy_labels(kept: Track, sighting: Sighting) -> void:
	if (
		kept.agent == sighting.agent
		and kept.space == sighting.space
		and kept.tab == sighting.tab
		and kept.identity == sighting.identity
		and kept.terminal_id == sighting.terminal_id
		and kept.agent_name == sighting.agent_name
		and kept.starting == sighting.starting
	):
		return
	version += 1
	kept.agent = sighting.agent
	kept.space = sighting.space
	kept.tab = sighting.tab
	kept.identity = sighting.identity
	kept.terminal_id = sighting.terminal_id
	kept.agent_name = sighting.agent_name
	kept.starting = sighting.starting


## What pane `kept` got that `sighting` shows, before its labels are copied:
## another terminal, else another agent, else another session.
static func _changed(kept: Track, sighting: Sighting) -> Changed:
	if kept.terminal_id != sighting.terminal_id:
		return Changed.TERMINAL
	if kept.agent != sighting.agent:
		return Changed.AGENT
	return Changed.SESSION


## A new agent run in the pane: its blocked totals start over, and the segment
## opened next is its first.
func _restart(kept: Track) -> void:
	kept.blocked_msec = 0
	kept.blocked_plus = false
	kept.times = 0
	kept.run_start = kept.segments.size()
	version += 1


## The machine's name on `kept`, when it changed.
func _relabel(kept: Track, label: String) -> void:
	if kept.machine_label != label:
		kept.machine_label = label
		version += 1


## Close the open segment at `at` (no earlier than it began) and give back what
## it was, for the event that ended it; null when none was open.
func _close(kept: Track, at: int, now: int) -> Segment:
	if kept.segments.is_empty():
		return null
	var open := _last(kept)
	if open.end_msec >= 0:
		return null
	open.end_msec = clampi(at, open.start_msec, now)
	version += 1
	if open.observed and open.state == "blocked":
		kept.blocked_msec += open.end_msec - open.start_msec
	return open


## Open a segment for what `sighting` says, from the clock's start when it
## knows one (labelled with that start, the one the top bar reads), else from
## now. Never before the log opened or the segment it follows ended.
func _open(kept: Track, sighting: Sighting, now: int, now_unix: float) -> void:
	var segment := Segment.new()
	segment.state = _state_of(sighting)
	segment.observed_start = sighting.since_unix >= 0.0
	var earliest := opened_msec
	if not kept.segments.is_empty():
		earliest = maxi(earliest, _last(kept).end_msec)
	segment.start_msec = clampi(_start_of(sighting, now, now_unix), earliest, now)
	segment.start_unix = sighting.since_unix if segment.observed_start else now_unix
	if segment.state == "blocked":
		kept.times += 1
		if not segment.observed_start:
			kept.blocked_plus = true
	_append(kept, segment)


func _unobserved(kept: Track, now: int, now_unix: float) -> void:
	var segment := Segment.new()
	segment.observed = false
	segment.observed_start = false
	segment.start_msec = now
	segment.start_unix = now_unix
	_append(kept, segment)


## Past SEGMENTS_MAX, the oldest two fold into one unobserved stretch; the
## run's first segment moves down with them (into the fold, once it is folded).
func _append(kept: Track, segment: Segment) -> void:
	kept.segments.append(segment)
	version += 1
	if kept.segments.size() <= SEGMENTS_MAX:
		return
	kept.run_start = maxi(kept.run_start - 1, 0)
	var first := kept.segments[0]
	var second := kept.segments[1]
	first.end_msec = second.end_msec
	first.state = ""
	first.observed = false
	first.observed_start = false
	first.elided = true
	kept.segments.remove_at(1)


## When the state `sighting` shows began, in this log's milliseconds: the
## clock's start when it knows one, else `now`.
func _start_of(sighting: Sighting, now: int, now_unix: float) -> int:
	if sighting.since_unix < 0.0:
		return now
	return now - int((now_unix - sighting.since_unix) * 1000.0)


## The pane goes out of the live set: gone, and past GONE_TRACKS_MAX the
## oldest gone track is dropped.
func _retire(kept: Track, now: int) -> void:
	version += 1
	_live.erase(kept.key)
	kept.gone = true
	kept.gone_msec = now
	_gone.append(kept)
	while _gone.size() > GONE_TRACKS_MAX:
		var oldest: Track = _gone.pop_front()
		_tracks.erase(oldest)


## The open (or last) segment of a track that has one.
static func _last(of: Track) -> Segment:
	return of.segments[of.segments.size() - 1]


static func _state_of(sighting: Sighting) -> String:
	# A shell (no agent) has no agent state, whatever its status field says.
	if sighting.agent.is_empty() or not sighting.status in STATES:
		return UNKNOWN
	# A launch says nothing of its agent yet, unless herdr already says blocked:
	# blocked takes precedence over launching: a start that asks at once.
	if sighting.starting and sighting.status != "blocked":
		return UNKNOWN
	return sighting.status


func _record(kind: Kind, now: int, now_unix: float, kept: Track, ended: Segment, changed := Changed.NONE) -> void:
	var open := _last(kept)
	var event := _new_event(kind, now, now_unix, kept.machine, kept.machine_label)
	event.pane_key = kept.key
	event.agent = kept.agent
	event.space = kept.space
	event.tab = kept.tab
	event.state = open.state
	event.starting = kept.starting
	event.agent_name = kept.agent_name
	event.changed = changed
	if ended != null:
		event.previous_state = ended.state
		if ended.observed:
			event.for_msec = ended.end_msec - ended.start_msec
			event.for_plus = not ended.observed_start
	_push(event)


func _record_machine(kind: Kind, now: int, now_unix: float, machine: String, label: String) -> void:
	_push(_new_event(kind, now, now_unix, machine, label))


func _new_event(kind: Kind, now: int, now_unix: float, machine: String, label: String) -> Event:
	var event := Event.new()
	event.id = _next_id
	_next_id += 1
	event.kind = kind
	event.msec = now
	event.wall_unix = now_unix
	event.machine = machine
	event.machine_label = label
	return event


func _push(event: Event) -> void:
	version += 1
	_events.append(event)
	if _events.size() > EVENTS_MAX:
		_events.pop_front()
