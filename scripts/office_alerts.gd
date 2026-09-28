class_name OfficeAlerts
extends Node
## Tells a viewer who is looking elsewhere that an agent needs them: the Dock
## icon bounces once when an agent starts waiting, and, when asked for, a short
## chime plays. The window title's `(N)` is OfficeAttention's; this is the part
## that only happens while the office is not in front of the viewer.
##
## It reads the fleet's StateLog, never a snapshot: only a new event (its id
## above the watermark, which starts at the log's newest when this is built)
## of kind STATE, APPEARED or REPLACED whose state became blocked (or done)
## rings, and only if the pane still counts as the top bar counts it when the
## event is handled (on a live machine; blocked: PaneModel.asks(); done: an
## agent there, not launching). A connection's first snapshot, a reconnect, a
## machine coming or going and a launch are never events of that kind, so they
## never ring. While the viewer has the office in front of them nothing rings,
## but the watermark moves on: going to another app never plays a backlog.
##
## The bounce is macOS's critical request: it keeps bouncing until Herdstead is
## activated, and nothing can stop it. So it asks at most once per stretch out
## of focus, only for blocked, only for a pane still blocked BOUNCE_GRACE_MSEC
## after it began waiting (one answered or back at work by then never
## bounces), and never for herdr's own focused pane: the viewer is looking at
## that one in the terminal. The chime is a redundant channel, the same news
## the top bar and NEWS carry: one per refresh at most, blocked over done, and
## once per pane per REPEAT_MSEC of the events' own clock.
##
## Time is HerdrFleet's monotonic milliseconds, the clock every event is stamped
## with; there is no wall clock here. A headless run decides everything and
## keeps its record (`fired`), but never asks the window for attention and never
## plays a sound. Nothing here is a herdr method: `--read-only` alerts too.

## At most one chime per pane in this many milliseconds of its events.
const REPEAT_MSEC := 10000
## How long a pane must stay blocked before the Dock bounces for it.
const BOUNCE_GRACE_MSEC := 3000
## The chimes' sample rate: mono, 16-bit.
const MIX_RATE := 22050
## Blocked: two rising notes, G5 then C6.
const BLOCKED_NOTES: Array[float] = [783.99, 1046.5]
const BLOCKED_NOTE_MSEC := 90
## Done: one lower note, shorter and softer.
const DONE_NOTES: Array[float] = [523.25]
const DONE_NOTE_MSEC := 120
const DONE_DB := -8.0
## Each note rises to PEAK (of full scale) in ATTACK_MSEC, then falls linearly
## to zero at its end, so every note begins and ends on a zero sample.
const ATTACK_MSEC := 5
const PEAK := 0.35
## How many decisions `fired` keeps.
const FIRED_MAX := 64
## Where a viewer turns the chime on by default: user://herdstead.cfg.
const CHIME_SECTION := "alerts"
const CHIME_KEY := "chime"

const BOUNCE := &"bounce"
const CHIME_BLOCKED := &"chime_blocked"
const CHIME_DONE := &"chime_done"


## What this run may do; the office fills it in from its command line.
class Options:
	## `--no-bounce` turns it off.
	var bounce := true
	## `--chime`, or `[alerts] chime=true` in the settings file, turns it on.
	var chime := false
	## A capture: nothing rings at all.
	var silent := false


## One thing the alerts did (or, headless, would have done).
class Fired:
	## BOUNCE, CHIME_BLOCKED or CHIME_DONE.
	var kind := &""
	## The pane it was for (HerdrFleet.pane_key); for a chime that covered
	## several, the first of them.
	var pane_key := ""
	## The StateLog event that started it.
	var event_id := -1


## A blocked pane the Dock will bounce for once its grace is over.
class Pending:
	var event_id := -1
	var due_msec := 0


## The most recent decisions, oldest first, at most FIRED_MAX.
var fired: Array[Fired] = []
## BOUNCE_GRACE_MSEC, for this run (a test waits less).
var bounce_grace_msec := BOUNCE_GRACE_MSEC
var options: Options

var _fleet: HerdrFleet
var _focused: Callable
## The newest event id already handled.
var _seen := -1
## Whether a bounce may still be asked for in this stretch out of focus.
var _armed := true
var _pending: Dictionary[String, Pending] = {}
## pane key -> msec of the event its last chime was for.
var _chimed: Dictionary[String, int] = {}
## The frame of the latest refresh: what a pending bounce checks its pane in.
var _frame: OfficeFrame
var _headless := false
var _player: AudioStreamPlayer
var _blocked_tone: AudioStreamWAV
var _done_tone: AudioStreamWAV


## `is_focused` answers whether the viewer has the office in front of them
## (FramePacer.is_focused()).
func _init(machines: HerdrFleet, is_focused: Callable, run: Options) -> void:
	name = "Alerts"
	_fleet = machines
	_focused = is_focused
	options = run
	_seen = machines.state_log().last_id()
	_blocked_tone = tone(PackedFloat32Array(BLOCKED_NOTES), BLOCKED_NOTE_MSEC)
	_done_tone = tone(PackedFloat32Array(DONE_NOTES), DONE_NOTE_MSEC)
	_player = AudioStreamPlayer.new()
	_player.name = "Chime"
	add_child(_player)


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"


## Sine notes one after another, each `note_msec` long: mono 16-bit samples at
## MIX_RATE, each note rising to PEAK in ATTACK_MSEC and falling linearly to a
## zero sample at its end, so nothing clicks where notes meet or the sound stops.
static func tone(notes: PackedFloat32Array, note_msec: int) -> AudioStreamWAV:
	var per_note := note_msec * MIX_RATE / 1000
	var attack := maxi(ATTACK_MSEC * MIX_RATE / 1000, 1)
	var data := PackedByteArray()
	data.resize(notes.size() * per_note * 2)
	var at := 0
	for frequency in notes:
		for index in per_note:
			var envelope := 0.0
			if index < attack:
				envelope = float(index) / attack
			else:
				envelope = float(per_note - 1 - index) / (per_note - 1 - attack)
			var value := PEAK * envelope * sin(TAU * frequency * index / MIX_RATE)
			data.encode_s16(at, roundi(value * 32767.0))
			at += 2
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## Whether the settings file at `path` turns the chime on by default.
static func remembered_chime(path: String) -> bool:
	var settings := ConfigFile.new()
	if settings.load(path) != OK:
		return false
	var chime: Variant = settings.get_value(CHIME_SECTION, CHIME_KEY, false)
	return chime is bool and chime == true


## Called on every office refresh, after the log has heard the change: handles
## the events that came since the last call.
func take(frame: OfficeFrame) -> void:
	_frame = frame
	var events := _fleet.state_log().events()
	var fresh: Array[StateLog.Event] = []
	for index in range(events.size() - 1, -1, -1):
		if events[index].id <= _seen:
			break
		fresh.push_front(events[index])
	if not fresh.is_empty():
		_seen = fresh.back().id
	if options.silent:
		return
	if _is_focused():
		_back_in_focus()
		return
	_forget_chimes(Time.get_ticks_msec())
	var blocked: Array[StateLog.Event] = []
	var done: Array[StateLog.Event] = []
	for event in fresh:
		var rings := _rings(event, frame)
		if rings.is_empty() or event.pane_key == frame.herdr_focus:
			continue
		if rings == "blocked":
			if options.bounce and _armed:
				var pending := Pending.new()
				pending.event_id = event.id
				pending.due_msec = event.msec + bounce_grace_msec
				_pending[event.pane_key] = pending
			blocked.append(event)
		else:
			done.append(event)
	if options.chime:
		if not _chime(blocked, CHIME_BLOCKED):
			_chime(done, CHIME_DONE)
	_resolve(Time.get_ticks_msec())


## The bounce is armed again, and any waiting one dropped, once the viewer is back.
func _process(_delta: float) -> void:
	if options.silent:
		return
	if _is_focused():
		_back_in_focus()
	elif not _pending.is_empty():
		_resolve(Time.get_ticks_msec())


## "blocked" or "done" when `event` is one that rings, else empty.
func _rings(event: StateLog.Event, frame: OfficeFrame) -> String:
	if not event.kind in [StateLog.Kind.STATE, StateLog.Kind.APPEARED, StateLog.Kind.REPLACED]:
		return ""
	if not event.state in ["blocked", "done"] or event.previous_state == event.state:
		return ""
	if not _live(event.machine):
		return ""
	var pane := frame.pane(event.pane_key)
	if pane == null:
		return ""
	if event.state == "blocked":
		return "blocked" if pane.asks() else ""
	var counted := not pane.provider.is_empty() and not pane.launching() and pane.state == "done"
	return "done" if counted else ""


func _live(machine: String) -> bool:
	return _fleet.has(machine) and not _fleet.is_stale(machine)


## Whether pane `key` still counts as blocked in the latest frame, on a live
## machine, and is not the pane herdr itself has in front of the viewer.
func _still_waits(key: String) -> bool:
	if _frame == null or key == _frame.herdr_focus:
		return false
	var pane := _frame.pane(key)
	return pane != null and pane.asks() and _live(pane.machine())


## Bounce for the first pending pane whose grace is over and that still waits;
## drop the ones whose grace is over and that do not.
func _resolve(now_msec: int) -> void:
	for key: String in _pending.keys():
		var pending := _pending[key]
		if now_msec < pending.due_msec:
			continue
		_pending.erase(key)
		if not _still_waits(key) or not _armed:
			continue
		_armed = false
		_pending.clear()
		_record(BOUNCE, key, pending.event_id)
		if not _headless:
			get_window().request_attention()
		return


## One chime for the panes in `events` that have not chimed within REPEAT_MSEC;
## false when none is left to chime for.
func _chime(events: Array[StateLog.Event], kind: StringName) -> bool:
	var first: StateLog.Event = null
	for event in events:
		if _chimed.has(event.pane_key) and event.msec - _chimed[event.pane_key] < REPEAT_MSEC:
			continue
		_chimed[event.pane_key] = event.msec
		if first == null:
			first = event
	if first == null:
		return false
	_record(kind, first.pane_key, first.id)
	if not _headless:
		_player.stream = _blocked_tone if kind == CHIME_BLOCKED else _done_tone
		_player.volume_db = 0.0 if kind == CHIME_BLOCKED else DONE_DB
		_player.play()
	return true


## Chimes older than REPEAT_MSEC no longer hold anything back.
func _forget_chimes(now_msec: int) -> void:
	for key: String in _chimed.keys():
		if now_msec - _chimed[key] >= REPEAT_MSEC:
			_chimed.erase(key)


func _back_in_focus() -> void:
	_armed = true
	_pending.clear()


func _record(kind: StringName, pane_key: String, event_id: int) -> void:
	var entry := Fired.new()
	entry.kind = kind
	entry.pane_key = pane_key
	entry.event_id = event_id
	fired.append(entry)
	while fired.size() > FIRED_MAX:
		fired.pop_front()


func _is_focused() -> bool:
	if not _focused.is_valid():
		return true
	var answer: bool = _focused.call()
	return answer
