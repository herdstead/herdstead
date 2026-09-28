class_name HerdrClient
extends Node
## Read-only, non-blocking transport for the herdr socket API. Knows no rendering.
##
## One herdr connection answers exactly one request and then closes, so every
## call opens its own StreamPeerUDS. Only `events.subscribe` keeps its socket
## open and streams bare envelopes without an id.
##
## This client never sends a mutating request; HerdrCommands, with its own
## connections, is the only thing that does. It re-fetches whole snapshots
## instead of applying incremental events, which keeps the state machine small
## at the price of a ~15KB read per change. Each one is read into a
## HerdrSnapshot once, and one that changes nothing is not announced.
##
## Remote input is untrusted: no NDJSON line longer than LINE_MAX is ever
## decoded, and a snapshot over HerdrSnapshot's record caps is refused whole,
## which leaves the snapshot held stale until one is read again. A line that
## is not JSON is dropped without echoing any of it (parse_line()), and every
## request goes out through request_line(), whose JSON any strict parser takes.

## The subscription stream is live. snapshot_current gates snapshot freshness.
signal connected
## The socket went away. The last snapshot stays readable but is stale.
signal disconnected
## A fresh `session.snapshot` that differs from the one held, or an in-place
## agent status update that changed something the office draws.
signal snapshot_changed(snapshot: HerdrSnapshot)
## A fresh `session.snapshot` that reads the same as the one held, so
## snapshot_changed stays quiet. The state clocks still moved on: a pane missing
## from two snapshots in a row has dropped out of them (see carry_states()).
signal snapshot_repeated
## A complete snapshot becomes current, or a stop, a disconnect or a refused
## snapshot invalidates it.
signal snapshot_readiness_changed
## Raw stream envelope, for probes and logs. Not needed to render.
signal event_received(name: String, data: Dictionary)

## Wire protocol this client was verified against (herdr 0.9.0).
const PROTOCOL := 22
const REQUEST_TIMEOUT := 5.0
const SUBSCRIBE_TIMEOUT := 5.0
## Topology events arrive in bursts; collapse them into one re-fetch.
const SNAPSHOT_DEBOUNCE := 0.1
## Backstop for anything the subscriptions do not cover.
const SNAPSHOT_INTERVAL := 5.0
const BACKOFF_MIN := 0.5
const BACKOFF_MAX := 5.0
## Longest NDJSON line read from herdr, in bytes: 32 MiB. A real session's
## snapshot is tens of KB, but HerdrSnapshot's record caps do not keep one under
## this: 16384 panes with long titles and paths pass it. A channel whose line
## grows past it, finished or not, fails: a request as if it had died, a
## subscription as a lost stream. A machine whose every snapshot is that long
## stays offline and retries every BACKOFF_MAX (see _overflowed).
const LINE_MAX := 33554432
## A stale pane id kills the whole subscribe call; retry a few times, fast.
const PROBE_RETRIES := 3
## Global subscriptions take no parameters. Agent status is per pane, and a
## status change is confirmed to fire no `pane.updated`, so it needs its own
## subscription for every known pane.
const TOPOLOGY := [
	"workspace.created",
	"workspace.updated",
	"workspace.metadata_updated",
	"workspace.renamed",
	"workspace.moved",
	"workspace.reordered",
	"workspace.closed",
	"workspace.focused",
	"worktree.created",
	"worktree.opened",
	"worktree.removed",
	"tab.created",
	"tab.closed",
	"tab.focused",
	"tab.renamed",
	"tab.moved",
	"pane.created",
	"pane.closed",
	"pane.updated",
	"pane.focused",
	"pane.moved",
	"pane.exited",
	"pane.agent_detected",
	"layout.updated",
]

var socket_path := ""
## True between `connected` and `disconnected`.
var online := false
## Subscription liveness alone cannot make a cached snapshot fresh after a gap.
var snapshot_current: bool:
	get:
		return _snapshot_current
## The last `session.snapshot` as the office reads it; empty (is_empty()) before
## the first one arrives. Status events patch it in place.
var snapshot: HerdrSnapshot:
	get:
		return _snapshot
## Unix time a snapshot was last read or a status event last applied to it;
## −1 before either. Kept across a drop: it is when this machine was last heard.
var heard_at := -1.0
## The protocol this connection's `ping` announced; 0 before one answers and
## again once the connection drops. HerdrCommands sends nothing to a protocol
## it does not know.
var protocol: int:
	get:
		return _protocol

var _requests: Array = []
var _sub: Dictionary = {}
var _sub_started := false
var _sub_panes: PackedStringArray = PackedStringArray()
var _next_id := 0
var _probe_retries := 0
var _resubscribe_pending := false
var _snapshot_inflight := false
var _want_snapshot := false
var _debounce_left := 0.0
var _interval_left := SNAPSHOT_INTERVAL
var _retry_left := 0.0
var _backoff := BACKOFF_MIN
var _offline_announced := false
## Pane ids survive terminal/session replacement, so status alone is not identity.
var _states: Dictionary[String, StateClock] = {}
var _snapshot_current := false
var _snapshot := HerdrSnapshot.new()
## _snapshot.signature(), or empty until it is asked for again.
var _signature := ""
## A refused snapshot warns once, until one is read again.
var _refusing := false
## A line past LINE_MAX has failed a channel since a snapshot was last read. A
## stream going live proves nothing then, so the backoff is not reset until a
## snapshot is read: a herdr whose every reply is too long would otherwise make
## the client reconnect, and read 32 MiB, twice a second.
var _overflowed := false
var _protocol := 0


## Cuts whole NDJSON lines off whatever one connection delivers. Never decodes
## a partial line (terminal titles carry multi-byte UTF-8), nor a line past
## `cap` bytes, finished or not: that drops the buffer and sets `overflow`, and
## the connection's owner fails it. HerdrClient reads with LINE_MAX; each
## command in HerdrCommands with its own, much smaller, cap.
class LineReader:
	var cap := LINE_MAX
	var overflow := false
	var _buffer := PackedByteArray()

	func _init(limit: int) -> void:
		cap = limit

	## Pull what `peer` has and return the whole lines it completed, oldest first.
	func pull(peer: StreamPeerUDS) -> PackedStringArray:
		# What the last read left over holds no newline, so only new bytes are searched.
		var searched := _buffer.size()
		# A closed peer has nothing left: poll() keeps it connected until every
		# byte that arrived before the close has been read, and only then drops it.
		var available := peer.get_available_bytes() if peer.get_status() == StreamPeerSocket.STATUS_CONNECTED else 0
		if available > 0:
			var chunk: Array = peer.get_partial_data(available)
			if chunk[0] == OK:
				var read: PackedByteArray = chunk[1]
				_buffer.append_array(read)
		var lines := PackedStringArray()
		var cut := _buffer.find(10, searched)
		while cut >= 0 and cut <= cap:
			lines.append(_buffer.slice(0, cut).get_string_from_utf8())
			_buffer = _buffer.slice(cut + 1)
			cut = _buffer.find(10)
		if cut > cap or (cut < 0 and _buffer.size() > cap):
			overflow = true
			_buffer = PackedByteArray()
		return lines


class StateClock:
	var identity := ""
	var status := "unknown"
	var since := -1.0
	var starting := false
	## The pane was missing from the last snapshot: kept for one snapshot only,
	## so one that drops out of a single snapshot and comes back keeps its
	## clock (see carry_states()); nobody reads its start meanwhile.
	var missing := false


## `--socket=` beats HERDR_SOCKET_PATH beats the default session socket.
static func resolve_socket_path(user_args: PackedStringArray) -> String:
	for argument in user_args:
		if argument.begins_with("--socket="):
			return argument.trim_prefix("--socket=")
	var from_environment := OS.get_environment("HERDR_SOCKET_PATH")
	if not from_environment.is_empty():
		return from_environment
	# Godot does not expand `~`.
	return OS.get_environment("HOME").path_join(".config/herdr/herdr.sock")


## Unix time the pane's current `agent_status` began, or -1 when unknown: a
## state we never saw begin (the first snapshot of a connection, and the first
## after every gap) has no real start.
func state_since(pane_id: String) -> float:
	var entry: StateClock = _states.get(pane_id)
	return -1.0 if entry == null or entry.missing else entry.since


## The whole table state_since() reads, pane id -> StateClock, entries marked
## `missing` included: the table itself, not a copy (HerdrFleet reads it on
## every snapshot and status event). Read only, and only by the fleet's log: a
## caller that writes into it breaks state_since().
func state_clocks() -> Dictionary[String, StateClock]:
	return _states


## Carry status start times across a whole-snapshot refresh. An unchanged
## status keeps its old start, a changed one starts now. `watched` says the
## snapshot before this one was current on this connection, so whatever is new
## in this one began while we watched: a pane seen for the first time starts now
## then, and unknown only in the first snapshot of a connection (see _since()).
## A pane missing from this snapshot keeps its clock through it, marked
## `missing`, and comes back with it in the next; missing from two in a row, it
## drops out: a single malformed snapshot does not reset who waited longest.
static func carry_states(
	known: Dictionary[String, StateClock], panes: Array[HerdrSnapshot.Pane], now: float, watched := false
) -> Dictionary[String, StateClock]:
	var result: Dictionary[String, StateClock] = {}
	for pane in panes:
		var entry := _clock(pane)
		var previous: StateClock = known.get(pane.pane_id)
		entry.since = _since(previous, entry, now, watched)
		result[pane.pane_id] = entry
	for pane_id: String in known:
		var gone := known[pane_id]
		if not result.has(pane_id) and not gone.missing:
			gone.missing = true
			result[pane_id] = gone
	return result


## A status event is a transition we watched happen; only a real change moves
## the start time. Events are applied only on top of a current snapshot.
static func mark_status(known: Dictionary[String, StateClock], pane: HerdrSnapshot.Pane, now: float) -> void:
	var entry := _clock(pane)
	var previous: StateClock = known.get(pane.pane_id)
	entry.since = _since(previous, entry, now, true)
	known[pane.pane_id] = entry


## When the state `current` shows began, given what was seen before
## (`previous`, null for a pane not seen before). The same session in the same
## status keeps its start, a new status starts `now`. A transition watched live
## (`watched`: the snapshot before was current) starts `now` too, as a known
## start: out of a launch, or another terminal, agent or session in the pane
## (their state begins as we see it), and a pane new to the connection.
## An empty identity on either side is an identity we do not know, not a new
## one: the same status, launching on neither side, keeps its start, and a
## changed one cannot be followed (-1). Unknown (-1) also stays for a state we
## never saw begin (a first sight or a new identity without `watched`) and for
## a pane still launching (its status says nothing yet) unless herdr says it is
## blocked: blocked takes precedence over launching, so a question asked during a
## launch starts `now` as watched, and the launch ending while it is still
## blocked is no new state (_continues()). So the one waiting
## longest is always one whose start is unknown, and a newcomer ranks after
## everyone already there (OfficeProjection.wait_order()).
static func _since(previous: StateClock, current: StateClock, now: float, watched: bool) -> float:
	if current.starting and current.status != "blocked":
		return -1.0
	if previous == null:
		return now if watched and not current.identity.is_empty() else -1.0
	if current.identity.is_empty() or previous.identity.is_empty():
		var same := previous.status == current.status and (not previous.starting or previous.status == "blocked")
		return previous.since if same else -1.0
	if _continues(previous, current):
		return previous.since if previous.status == current.status else now
	return now if watched else -1.0


static func _clock(pane: HerdrSnapshot.Pane) -> StateClock:
	var result := StateClock.new()
	if not pane.terminal_id.is_empty():
		result.identity = AgentSessionIdentity.runtime_key(pane.terminal_id, pane.agent, pane.agent_session)
	result.status = pane.status()
	result.starting = pane.launch_pending
	return result


static func _continues(previous: StateClock, current: StateClock) -> bool:
	return (
		previous != null
		and not current.identity.is_empty()
		and previous.identity == current.identity
		and (not previous.starting or previous.status == "blocked")
		and (not current.starting or current.status == "blocked")
	)


func start(path: String) -> void:
	_set_snapshot_current(false)
	_states.clear()
	_protocol = 0
	socket_path = path
	_backoff = BACKOFF_MIN
	_overflowed = false
	_retry_left = 0.0
	set_process(true)
	_open_ping()


func stop() -> void:
	set_process(false)
	_close_subscription()
	for channel: Dictionary in _requests:
		var peer: StreamPeerUDS = channel.peer
		peer.disconnect_from_host()
	_requests.clear()
	_snapshot_inflight = false
	online = false
	_protocol = 0
	_set_snapshot_current(false)
	_states.clear()


func _process(delta: float) -> void:
	_pump_requests(delta)
	_pump_subscription(delta)
	if _debounce_left > 0.0:
		_debounce_left -= delta
		if _debounce_left <= 0.0:
			_want_snapshot = true
	# The backstop only counts while a snapshot may go out; offline it must not
	# bank a fetch that would race the next ping.
	if _interval_left > 0.0 and _snapshot_allowed():
		_interval_left -= delta
		if _interval_left <= 0.0:
			_want_snapshot = true
	if _retry_left > 0.0:
		_retry_left -= delta
		if _retry_left <= 0.0:
			_open_ping()
		return
	if _want_snapshot and not _snapshot_inflight and _snapshot_allowed():
		_want_snapshot = false
		_snapshot_inflight = true
		_interval_left = SNAPSHOT_INTERVAL
		_request("session.snapshot", {})


## Fetch a snapshot as soon as one may go out (a live stream, none in flight;
## one in flight is followed by another), not at the next poll or event. Only
## ever `session.snapshot`: HerdrFleet asks after the write boundary did
## something herdr announces no event for.
func refresh_soon() -> void:
	_want_snapshot = true


## Snapshots follow a live stream: never before `subscription_started`, except
## the refresh a `pane_not_found` asks for, which the next subscribe depends on.
func _snapshot_allowed() -> bool:
	return _sub_started or _resubscribe_pending


# --- requests -----------------------------------------------------------------


func _open_ping() -> void:
	_request("ping", {})


func _request(method: String, params: Dictionary) -> void:
	var peer := _open_peer()
	if peer == null:
		if method == "session.snapshot":
			_snapshot_inflight = false
		_go_offline()
		return
	(
		_requests
		. append(
			{
				"peer": peer,
				"method": method,
				"params": params,
				"reader": LineReader.new(LINE_MAX),
				"overflow": false,
				"sent": false,
				"left": REQUEST_TIMEOUT,
			}
		)
	)


func _pump_requests(delta: float) -> void:
	var alive: Array = []
	var responses: Array = []
	var failed := false
	for channel: Dictionary in _requests:
		var state := _pump_request(channel, delta)
		if state == "alive":
			alive.append(channel)
			continue
		var peer: StreamPeerUDS = channel.peer
		peer.disconnect_from_host()
		if channel.method == "session.snapshot":
			_snapshot_inflight = false
		if state == "failed":
			failed = true
		else:
			responses.append([channel.method, channel.line])
	# Settle the request list before any handler can touch it.
	_requests = alive
	if failed:
		_go_offline()
		return
	for response: Array in responses:
		var method: String = response[0]
		var line: String = response[1]
		_handle_response(method, line)


func _pump_request(channel: Dictionary, delta: float) -> String:
	var peer: StreamPeerUDS = channel.peer
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerSocket.STATUS_CONNECTED and not channel.sent:
		channel.sent = true
		var method: String = channel.method
		var params: Dictionary = channel.params
		if peer.put_data(_envelope(method, params)) != OK:
			return "failed"
	# Always drain before judging the status: herdr often answers and closes
	# within the same poll, and the peer stays connected until those bytes are read.
	var lines := _read_lines(channel)
	if not lines.is_empty():
		channel.line = lines[0]
		return "done"
	if channel.overflow:
		return "failed"
	channel.left -= delta
	if status == StreamPeerSocket.STATUS_ERROR or channel.left <= 0.0:
		return "failed"
	if status == StreamPeerSocket.STATUS_NONE and channel.sent:
		# Closed without answering.
		return "failed"
	return "alive"


func _handle_response(method: String, line: String) -> void:
	var message: Variant = parse_line(line)
	var envelope: Dictionary = message if typeof(message) == TYPE_DICTIONARY else {}
	var readable: bool = envelope.get("result") is Dictionary
	if envelope.has("error"):
		push_warning("herdr %s failed: %s" % [method, _error_text(envelope.error)])
	elif not readable:
		push_warning("herdr sent an unreadable %s response" % method)
	if envelope.has("error") or not readable:
		if method == "ping":
			# The handshake drives everything else; without a retry it would stall.
			_go_offline()
		return
	var result: Dictionary = envelope.get("result")
	match method:
		"ping":
			var announced: float = result.get("protocol") if result.get("protocol") is float else 0.0
			# Kept for this connection only: HerdrCommands refuses a protocol it does not know.
			_protocol = int(announced)
			if _protocol != PROTOCOL:
				push_warning("herdr protocol %d, this client speaks %d" % [_protocol, PROTOCOL])
			_open_subscription()
		"session.snapshot":
			if not result.get("snapshot") is Dictionary:
				# Dropped; the interval backstop asks again.
				push_warning("herdr sent an unreadable snapshot")
				return
			var data: Dictionary = result.get("snapshot")
			if not data.get("panes", []) is Array:
				push_warning("herdr sent an unreadable snapshot")
				return
			_apply_snapshot(data)


# --- subscription stream ------------------------------------------------------


func _open_subscription() -> void:
	_close_subscription()
	var panes := _pane_ids()
	var subscriptions: Array = []
	for type: String in TOPOLOGY:
		subscriptions.append({"type": type})
	for pane_id: String in panes:
		subscriptions.append({"type": "pane.agent_status_changed", "pane_id": pane_id})
	var peer := _open_peer()
	if peer == null:
		_go_offline()
		return
	_sub = {
		"peer": peer,
		"reader": LineReader.new(LINE_MAX),
		"overflow": false,
		"subscriptions": subscriptions,
		"panes": panes,
		"sent": false,
		"left": SUBSCRIBE_TIMEOUT,
	}


func _close_subscription() -> void:
	if _sub.is_empty():
		return
	var peer: StreamPeerUDS = _sub.peer
	peer.disconnect_from_host()
	_sub = {}
	_sub_started = false
	_sub_panes = PackedStringArray()


func _pump_subscription(delta: float) -> void:
	if _sub.is_empty():
		return
	var peer: StreamPeerUDS = _sub.peer
	peer.poll()
	var status := peer.get_status()
	if status == StreamPeerSocket.STATUS_CONNECTED and not _sub.sent:
		_sub.sent = true
		if peer.put_data(_envelope("events.subscribe", {"subscriptions": _sub.subscriptions})) != OK:
			_go_offline()
			return
	var lines := _read_lines(_sub)
	if not _sub_started:
		_sub.left -= delta
		if _sub.left <= 0.0 and lines.is_empty():
			_go_offline()
			return
	var closed := status == StreamPeerSocket.STATUS_ERROR
	closed = closed or (status == StreamPeerSocket.STATUS_NONE and _sub.sent)
	# A line past LINE_MAX loses the stream like a hangup, after the whole lines before it.
	var overflow: bool = _sub.overflow
	for line: String in lines:
		_handle_stream_line(line)
		if _sub.is_empty() or _sub.peer != peer:
			# A handler replaced or dropped this stream; the rest is stale.
			return
	if closed or overflow:
		_go_offline()


func _handle_stream_line(line: String) -> void:
	var message: Variant = parse_line(line)
	if typeof(message) != TYPE_DICTIONARY:
		push_warning("herdr sent an unreadable stream line")
		return
	var envelope: Dictionary = message
	if envelope.has("event"):
		var event_name := str(envelope.event)
		if typeof(envelope.get("data", {})) != TYPE_DICTIONARY:
			push_warning("herdr sent an unreadable %s event" % event_name)
			return
		var data: Dictionary = envelope.get("data", {})
		event_received.emit(event_name, data)
		# Note the dot: the per-pane status event keeps its method spelling,
		# while global events arrive with underscores.
		if event_name == "pane.agent_status_changed":
			_apply_status(data)
		# Aggregated workspace/tab status also moved, so re-fetch either way.
		_debounce_left = SNAPSHOT_DEBOUNCE
		return
	if envelope.has("error"):
		# The error id carries a `:sub:<n>:probe` suffix, so judge by the code.
		var error: Variant = envelope.error
		var code := ""
		if error is Dictionary:
			var detail: Dictionary = error
			code = str(detail.get("code", ""))
		if code == "pane_not_found" and _probe_retries < PROBE_RETRIES:
			_probe_retries += 1
			# Our pane list is stale. Refresh it, then subscribe again.
			_close_subscription()
			_resubscribe_pending = true
			_want_snapshot = true
			return
		push_warning("herdr subscribe failed: %s" % _error_text(error))
		_go_offline()
		return
	if not envelope.get("result") is Dictionary:
		return
	var result: Dictionary = envelope.get("result")
	if str(result.get("type", "")) == "subscription_started":
		_on_subscription_started()


## The stream is live: the client counts as online from here, and the window
## between the last snapshot and this moment is covered by asking for one more.
## The backoff starts over, unless a line past LINE_MAX is why the connection
## was lost: then only a snapshot read again restarts it (see _overflowed).
func _on_subscription_started() -> void:
	_sub_started = true
	_sub_panes = _sub.panes
	_probe_retries = 0
	if not _overflowed:
		_backoff = BACKOFF_MIN
	_offline_announced = false
	if not online:
		online = true
		connected.emit()
	# Cover the window between the last snapshot and this stream going live.
	_want_snapshot = true


# --- state --------------------------------------------------------------------


## A complete `session.snapshot` payload: read once into a HerdrSnapshot, and
## announced only when the snapshot was stale or reads differently from the one
## held. Readiness and the pane-set bookkeeping below run either way.
func _apply_snapshot(data: Dictionary) -> void:
	var next := HerdrSnapshot.from_wire(data)
	if next == null:
		# Refused whole. The snapshot held stays on screen, but it is no longer
		# herdr's picture: stale until one is read again, so the machine dims,
		# freezes and counts nobody live, and status events wait for that
		# snapshot too. The backstop, and a pending re-subscription, ask again.
		if not _refusing:
			_refusing = true
			push_warning("herdr snapshot refused, the last one stays as stale: " + HerdrSnapshot.refusal(data))
		# Events go unapplied in the gap: no start time survives it, as after a
		# disconnect. Cleared first, so whoever hears the machine go stale reads none.
		_states.clear()
		_set_snapshot_current(false)
		return
	_refusing = false
	if _overflowed:
		# A snapshot fitted again: the next lost connection starts the backoff over.
		_overflowed = false
		_backoff = BACKOFF_MIN
	if next.unreadable_panes > 0:
		push_warning("herdr snapshot has %d unreadable panes" % next.unreadable_panes)
	_states = carry_states(_states, next.panes, Time.get_unix_time_from_system(), _snapshot_current)
	var next_signature := next.signature()
	var unchanged := _snapshot_current and next_signature == _current_signature()
	_snapshot = next
	_signature = next_signature
	heard_at = Time.get_unix_time_from_system()
	_set_snapshot_current(true)
	if unchanged:
		snapshot_repeated.emit()
	else:
		snapshot_changed.emit(_snapshot)
	if _resubscribe_pending:
		_resubscribe_pending = false
		_open_subscription()
		return
	if _sub_started and _pane_ids() != _sub_panes:
		# The pane set moved, so the per-pane status subscriptions must too.
		_open_subscription()


func _set_snapshot_current(current: bool) -> void:
	if _snapshot_current == current:
		return
	_snapshot_current = current
	snapshot_readiness_changed.emit()


func _current_signature() -> String:
	if _signature.is_empty():
		_signature = _snapshot.signature()
	return _signature


## A `pane.agent_status_changed` event, applied to the held snapshot in place and
## announced only when it changed something the office draws.
func _apply_status(data: Dictionary) -> void:
	# Keep the last complete picture frozen across a connection gap. Events
	# carry no terminal/session identity; the first fresh snapshot establishes
	# that baseline before either visible state or local clocks may change.
	if not snapshot_current:
		return
	# Herdr names the pane as it spelled it in the snapshot, not as the office cleaned it.
	var index := _snapshot.wire_pane_ids.find(str(data.get("pane_id", "")))
	if index < 0:
		return
	var pane := _snapshot.panes[index]
	var changed := pane.apply_status(data)
	# A provider change cannot carry the old session's clock forward.
	mark_status(_states, pane, Time.get_unix_time_from_system())
	heard_at = Time.get_unix_time_from_system()
	if changed:
		_signature = ""
		snapshot_changed.emit(_snapshot)


## herdr errors are objects with a message; anything else still counts as an error.
static func _error_text(error: Variant) -> String:
	if not error is Dictionary:
		return str(error)
	var detail: Dictionary = error
	return str(detail.get("message", detail.get("code", "?")))


## The ids the per-pane subscriptions name, as herdr sent them, sorted.
func _pane_ids() -> PackedStringArray:
	var ids := _snapshot.wire_pane_ids.duplicate()
	ids.sort()
	return ids


func _go_offline() -> void:
	_close_subscription()
	for channel: Dictionary in _requests:
		var peer: StreamPeerUDS = channel.peer
		peer.disconnect_from_host()
	_requests.clear()
	_snapshot_inflight = false
	_want_snapshot = false
	_debounce_left = 0.0
	_resubscribe_pending = false
	_probe_retries = 0
	online = false
	_protocol = 0
	_set_snapshot_current(false)
	# A status may have changed and changed back while we were away, so no
	# start time survives the gap; the next snapshot sees every pane afresh.
	_states.clear()
	# One notice per offline episode, including a socket that was never there.
	if not _offline_announced:
		_offline_announced = true
		disconnected.emit()
	_retry_left = _backoff
	_backoff = minf(BACKOFF_MAX, _backoff * 2.0)
	if OS.is_stdout_verbose():
		print("herdr offline, retrying in %.1fs" % _retry_left)


# --- wire ---------------------------------------------------------------------


## A connection to the herdr socket at `path`, or null when it is unreachable.
## Checks the file first: a missing herdr server is the normal case while it
## restarts, not an engine-level error. HerdrCommands opens its own with this.
static func open_peer(path: String) -> StreamPeerUDS:
	var dir := DirAccess.open(path.get_base_dir())
	# FileAccess cannot see a unix socket; DirAccess can.
	if dir == null or not dir.file_exists(path.get_file()):
		return null
	var peer := StreamPeerUDS.new()
	if peer.connect_to_host(path) != OK:
		return null
	return peer


func _open_peer() -> StreamPeerUDS:
	return open_peer(socket_path)


func _envelope(method: String, params: Dictionary) -> PackedByteArray:
	_next_id += 1
	return request_line(str(_next_id), method, params)


## One request as the NDJSON line herdr reads: the only way Herdstead encodes
## anything it sends herdr, here and in HerdrCommands.
static func request_line(id: String, method: String, params: Dictionary) -> PackedByteArray:
	var request := {"id": id, "method": method, "params": params}
	return (JsonText.encode(request) + "\n").to_utf8_buffer()


## One NDJSON line from herdr as JSON, or null when it is not JSON. Unlike
## JSON.parse_string(), a line that does not parse is not echoed into the log
## (the engine quotes the offending token): herdr's lines carry terminal titles
## and, for HerdrCommands, terminal text. MachineRoster reads the machine list
## and MachineLink a forward's sidecar with it too, for the same reason.
static func parse_line(line: String) -> Variant:
	var json := JSON.new()
	if json.parse(line) != OK:
		return null
	return json.data


## The whole NDJSON lines the channel's LineReader cut off this time. A line
## past LINE_MAX sets the channel's `overflow` and the client's `_overflowed`
## and warns once, and the channel's owner fails it.
func _read_lines(channel: Dictionary) -> PackedStringArray:
	var reader: LineReader = channel.reader
	var peer: StreamPeerUDS = channel.peer
	var lines := reader.pull(peer)
	if reader.overflow and not channel.overflow:
		push_warning("herdr sent a line longer than %d bytes; dropping that connection" % LINE_MAX)
		channel.overflow = true
		_overflowed = true
	return lines
