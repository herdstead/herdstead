class_name OfficeAttention
extends Node
## Helps a human notice the office: which agent needs them and for how long,
## and, in the window title, how many are blocked (`(2) Herdstead · 2 BLOCKED`).
## What rings while the office is in the background is OfficeAlerts'.
##
## Everything here changes in place. Durations tick every second, and folding
## them into the world or inspector models would rebuild the office and restart
## every worker animation on each tick.

## A blocked agent waiting this long gets a harder pulse.
const LONG_WAIT := 300.0
const TEXT_INTERVAL := 0.25
const TITLE := "Herdstead"
## Badge bob per step, in whole art pixels so nothing smears. The rhythms read
## as calm for UNREAD, a nudge for blocked, and a double hop for a long wait.
const PULSES := {
	"done": [0.6, [0, -1]],
	"blocked": [0.3, [0, -1]],
	"long": [0.15, [-2, 0, -2, 0, 0, 0]],
}

## Where time-in-state and per-machine staleness come from. A pane id is only
## unique within one machine, so every question names the machine.
var fleet: HerdrFleet
## Whether the office as a whole is stale; badges of a machine the fleet shows
## follow that machine instead.
var stale := true
## Whether the window title leads with the blocked count, `(2) Herdstead · …`
## (`--no-title-count` turns it off).
var title_count := true

## The panel whose %Duration label this writes; the office hands it over once.
var inspector: OfficePaneInspector
## The top bar, whose BLOCKED counter says the longest wait; handed over once.
var bar: OfficeBar

var _duration_pane_id := ""
var _duration_machine := ""
## The blocked panes' StateLog tracks (watch_blocked()); the longest of them is the `max`.
var _blocked_tracks: Array[StateLog.Track] = []
## Whom the staff panel's NEXT names (watch_next()); empty for nobody.
var _next_pane := ""
var _next_machine := ""
var _text_left := 0.0
## The step every rhythm in PULSES was on when the badges were last walked.
var _pulsed_steps := PackedInt64Array()
## Set by update(): a refresh may have added a badge, changed its state or
## dropped its machine, and the next frame shows that without waiting a step.
var _pulse_due := true


func _init(machines: HerdrFleet) -> void:
	name = "Attention"
	fleet = machines


## Seconds as the inspector shows them: `45s`, `12m`, `1h 05m`. Unknown is empty.
static func format_duration(seconds: float) -> String:
	if seconds < 0.0:
		return ""
	var minutes := floori(seconds / 60.0)
	if minutes < 1:
		return "%ds" % floori(seconds)
	if minutes < 60:
		return "%dm" % minutes
	return "%dh %02dm" % [floori(minutes / 60.0), minutes % 60]


## The in-world form of a duration: whole units of the largest that fits, so it
## is never wider than a chip's slot or a lens row. Under a minute `Ns`, under
## 100 minutes `Nm`, under 100 hours `Nh`, else whole days `Nd`, capped at
## `99d`; `plus` (the state began before this office watched) adds `+`.
## Unknown (below 0) is empty. The station chip never passes `plus`: a start
## this office never saw draws no number there. The HUD keeps wait_text().
static func compact_duration(seconds: float, plus: bool) -> String:
	if seconds < 0.0:
		return ""
	var text := ""
	if seconds < 60.0:
		text = "%ds" % floori(seconds)
	elif seconds < 6000.0:
		text = "%dm" % floori(seconds / 60.0)
	elif seconds < 360000.0:
		text = "%dh" % floori(seconds / 3600.0)
	else:
		text = "%dd" % mini(99, floori(seconds / 86400.0))
	return text + ("+" if plus else "")


## How long a pane has been in its state (StateLog.wait_of()), in
## format_duration()'s words with `+` when that state began before this office
## watched: `12m`, `5s+`. The one way the HUD writes a wait: the OVERVIEW's FOR,
## the top bar's `max` and the counters' hover say this; the world (the lens
## line, the chip) says the same wait in compact_duration().
static func wait_text(wait: StateLog.Wait) -> String:
	return format_duration(wait.msec / 1000.0) + ("+" if wait.plus else "")


## A unix time as the viewer's local wall clock, `HH:MM`: the NEWS strip, the
## EVENTS tab and the overview's axis all write it this way. The system's time
## zone is read each time, so a change of zone shows on the next label.
static func wall_clock(unix: float) -> String:
	var zone := Time.get_time_zone_from_system()
	var bias: int = zone.get("bias", 0)
	return Time.get_time_string_from_unix_time(int(unix) + bias * 60).left(5)


## Panes whose desk shows a blocked or UNREAD badge.
static func count(panes: Array[PaneModel]) -> Dictionary:
	var result := {"blocked": 0, "done": 0}
	for pane in panes:
		if pane.provider.is_empty() or pane.launching():
			continue
		if result.has(pane.state):
			result[pane.state] += 1
	return result


## `2 BLOCKED / 1 UNREAD`, dropping zeros. Empty while stale: counts from a
## lost connection are not a live signal.
func summary(panes: Array[PaneModel], is_stale: bool) -> PackedStringArray:
	var parts := PackedStringArray()
	if is_stale:
		return parts
	var counts := count(panes)
	if counts.blocked > 0:
		parts.append("%d BLOCKED" % counts.blocked)
	if counts.done > 0:
		parts.append("%d UNREAD" % counts.done)
	return parts


func machine_stale(machine: String) -> bool:
	return fleet.is_stale(machine) if fleet.has(machine) else stale


## Called on every office refresh; only touches the window when the title moves.
## `panes` holds the panes of every live machine; `offline` counts machines
## that dropped while others are still live. With `title_count`, the title
## leads with `(N) `, N the blocked agents (the top bar's BLOCKED), so a
## window list or the Dock's menu shows it: left out when nobody is blocked or
## no machine is live, and written the same whether or not the window has focus.
func update(panes: Array[PaneModel], is_stale: bool, offline := 0) -> void:
	stale = is_stale
	var title := TITLE + " · OFFLINE" if is_stale else TITLE
	if title_count and not is_stale:
		var blocked: int = count(panes).blocked
		if blocked > 0:
			title = "(%d) %s" % [blocked, title]
	if not is_stale and offline > 0:
		title += " · %d OFFLINE" % offline
	for part in summary(panes, is_stale):
		title += " · " + part
	if get_window().title != title:
		get_window().title = title
	_pulse_due = true


## Which pane's time-in-state the inspector shows from now on. Where that text
## lands is the inspector scene's business; only what it says is decided here.
## `shown` is false for a pane whose state carries no clock (starting, stale).
func watch(machine: String, pane_id: String, shown: bool) -> void:
	_duration_machine = machine
	_duration_pane_id = pane_id if shown else ""
	_update_duration()


## Which blocked panes the top bar's BLOCKED counter times from now on
## (OfficeTotals.blocked_tracks); empty for none.
func watch_blocked(tracks: Array[StateLog.Track]) -> void:
	_blocked_tracks = tracks


## Whom NEXT names from now on (OfficeNavigator.peek_next()), whose wait it
## shows as `12m (N)`; an empty `pane_id` is nobody, and NEXT shows no wait.
func watch_next(machine: String, pane_id: String) -> void:
	_next_machine = machine
	_next_pane = pane_id
	_update_duration()


func _process(delta: float) -> void:
	_text_left -= delta
	if _text_left <= 0.0:
		_text_left = TEXT_INTERVAL
		_update_duration()
		_update_waits()
	# A badge's lift only moves when its rhythm steps, so the badges are walked
	# on those steps (and after a refresh), not on every frame in between.
	var steps := _pulse_steps(Time.get_ticks_msec() / 1000.0)
	if _pulse_due or steps != _pulsed_steps:
		_pulse_due = false
		_pulsed_steps = steps
		_pulse()


## The step each rhythm in PULSES is on `seconds` into the shared clock, counted
## exactly as _pulse() counts it.
static func _pulse_steps(seconds: float) -> PackedInt64Array:
	var steps := PackedInt64Array()
	for rhythm: String in PULSES:
		var pulse: Array = PULSES[rhythm]
		var period: float = pulse[0]
		steps.append(int(seconds / period))
	return steps


func _update_duration() -> void:
	if not is_instance_valid(inspector):
		return
	var text := ""
	if not _duration_pane_id.is_empty():
		var since := fleet.state_since(_duration_machine, _duration_pane_id)
		text = "" if since < 0.0 else format_duration(Time.get_unix_time_from_system() - since)
	inspector.set_duration(text)
	# NEXT's wait, on the same beat and in the same words; `(N)` names the key.
	var next := ""
	if not _next_pane.is_empty():
		var since := fleet.state_since(_next_machine, _next_pane)
		next = "(N)" if since < 0.0 else format_duration(Time.get_unix_time_from_system() - since) + " (N)"
	inspector.set_next_wait(next)
	if is_instance_valid(bar):
		bar.show_longest_wait(_longest_wait())


## The longest wait among the blocked panes watch_blocked() names, as the
## OVERVIEW's FOR says it (StateLog.longest(), the same rule): `12m`, `12m+`
## when some blocked start came before this office watched, so the true
## longest is at least that. Empty for nobody blocked.
func _longest_wait() -> String:
	if _blocked_tracks.is_empty():
		return ""
	return wait_text(StateLog.longest(_blocked_tracks, Time.get_ticks_msec()))


## How long each blocked agent has been kept waiting, in their chip and on
## their list row, on the same beat as the inspector's.
## Only blocked: an agent who is working or done is not waiting on anybody. A
## machine that dropped shows no number at all — it would go on
## growing off a snapshot nobody is receiving any more — and a wait whose start
## this machine never saw shows none either, the same way the inspector shows none.
func _update_waits() -> void:
	var now := Time.get_unix_time_from_system()
	for badge: StatusBadge in get_tree().get_nodes_in_group(StatusBadge.GROUP):
		if not is_instance_valid(badge.wait) and not is_instance_valid(badge.chip):
			continue
		var seconds := -1.0
		if badge.state == ArtContract.STATE_BLOCKED and not machine_stale(badge.machine):
			var since := fleet.state_since(badge.machine, badge.pane_id)
			seconds = -1.0 if since < 0.0 else now - since
		badge.show_wait(seconds)


## Step every blocked and UNREAD badge on a shared clock, so a rebuild never
## resets the phase. A lost connection freezes that machine's badges at rest.
## How far a lift of so many units moves a badge is the badge's own business.
func _pulse() -> void:
	var seconds := Time.get_ticks_msec() / 1000.0
	var now := Time.get_unix_time_from_system()
	for badge: StatusBadge in get_tree().get_nodes_in_group(StatusBadge.GROUP):
		var rhythm := ""
		if not machine_stale(badge.machine):
			if badge.state == ArtContract.STATE_DONE:
				rhythm = "done"
			elif badge.state == ArtContract.STATE_BLOCKED:
				var since := fleet.state_since(badge.machine, badge.pane_id)
				rhythm = "long" if since >= 0.0 and now - since >= LONG_WAIT else "blocked"
		var lift := 0
		if not rhythm.is_empty():
			var pulse: Array = PULSES[rhythm]
			var period: float = pulse[0]
			var steps: Array = pulse[1]
			lift = steps[int(seconds / period) % steps.size()]
		badge.lift(lift)
