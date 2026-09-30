class_name OfficeLens
extends Node
## The info lens: while `L` is held (the `office_lens`
## action), the world is a data view. Every agent's desk gets one line saying how
## long it has been in its state (text_for(): the OVERVIEW's FOR, from
## StateLog.wait_of(), in the in-world form OfficeAttention.compact_duration()),
## every seat's name plate shows, the blocked chip draws nothing meanwhile (the
## wait is said once), every pod's floor is washed in its
## most urgent state (tone_for(), on the FLOORS windows' scale) and the
## furnishing dims. Let go, all of it is as it was. The office draws it
## (OfficeScene._show_lens()); this node only knows whether the lens is held and
## when its lines are due again.
##
## Held is polled, not an input event: the key's state, gated by `may_hold` (the
## office's: no monitor, no OVERVIEW, no text field with the keyboard). A press
## that meets a closed gate is spoiled until `L` is let go, so a key typed into
## the list's filter never turns into the lens when the focus leaves. While held
## the lines move every TICK, the top bar's beat; let go, one poll a frame and
## nothing else. `forced` (`--lens=held`, captures and perf only) holds it
## without the key; the gate still applies.

## The lens came on (`held`) or went off.
signal changed(held: bool)
## The lens is held and its lines are due again (every TICK).
signal ticked

## The top bar's beat: the lens's lines move with the `max`.
const TICK := OfficeAttention.TEXT_INTERVAL
const ACTION := &"office_lens"
## How urgent each window look is, most first: what tone_for() keeps.
const RANKS: Dictionary[StringName, int] = {
	&"WindowBlocked": 0,
	&"WindowDone": 1,
	&"WindowWorking": 2,
	&"WindowIdle": 3,
	&"WindowUnknown": 4,
}

## Whether the lens is on now.
var held := false
## Held without the key (`--lens=held`).
var forced := false
## How many times the lines were due (ticked), for tests.
var updates := 0
## The clock (Time.get_ticks_msec(), the state log's) the lines last said.
var now_msec := 0
## Whether the lens may be on now; true when unset.
var may_hold: Callable
## A press that met a closed gate: it does not count until `L` is let go.
var _spoiled := false
var _left := 0.0


func _init(allowed := Callable()) -> void:
	name = "Lens"
	may_hold = allowed


## What the lens line over `pane` says: nothing for a shell (nobody to time)
## and on a machine that dropped (`stale`: that clock is nobody's, invariant 4);
## `?` when the state log has no `track` of it; else how long it has been in its
## state at `now` (the OVERVIEW's FOR: StateLog.wait_of() with its `+`).
static func text_for(pane: PaneModel, track: StateLog.Track, stale: bool, now: int) -> String:
	if pane == null or stale or (pane.provider.is_empty() and not pane.launching()):
		return ""
	if track == null:
		return "?"
	return OfficeAttention.wait_text(StateLog.wait_of(track, now))


## The palette key `room`'s pod floor is washed in: its most urgent pane's, on the
## FLOORS windows' own scale (OfficeFloorRow.window_look(), HudTheme.SECTION_PANELS):
## an agent that asks (blocked, even while starting), then done, working, idle
## or starting, unknown; a table of shells only, and every table of a machine
## that dropped (`stale`), dark.
static func tone_for(room: RoomModel, stale: bool) -> StringName:
	var look := &"WindowDark"
	var best := 5
	if not stale:
		for pane in room.panes:
			# The FLOORS window's own look: a shell's is dark, and never wins.
			var pane_look := OfficeFloorRow.window_look(pane, true)
			if pane_look == &"WindowDark":
				continue
			var rank: int = RANKS.get(pane_look, 4)
			if rank < best:
				best = rank
				look = pane_look
	return HudTheme.SECTION_PANELS[look]


## Stamp the clock the lines are about to say and return it.
func stamp() -> int:
	now_msec = Time.get_ticks_msec()
	return now_msec


func _process(delta: float) -> void:
	var pressed := Input.is_action_pressed(ACTION)
	if not pressed and not forced and not held:
		# Released: this one poll and nothing else.
		_spoiled = false
		return
	var answer: Variant = may_hold.call() if may_hold.is_valid() else true
	var allowed: bool = answer is bool and answer == true
	if not pressed:
		_spoiled = false
	elif not allowed:
		_spoiled = true
	var now_held: bool = allowed and (forced or (pressed and not _spoiled))
	if now_held != held:
		held = now_held
		_left = TICK
		changed.emit(held)
		return
	if not held:
		return
	_left -= delta
	if _left <= 0.0:
		_left = TICK
		updates += 1
		ticked.emit()
