class_name OfficeNewPaneFollow
extends RefCounted
## The office's side of PickFollowsWrite, which decides where the viewer's pick
## goes after a write the office sent: the new pane a split (or a new space or
## worktree) from the agent card made, waited for until a snapshot shows it,
## then picked; and the agent a start from the card became, which the pick is
## carried on to. A selection only, later, never a write.
##
## Only wiring: each call gathers the facts (the navigator's pick and
## nav_revision, the fleet's generation(), launch_of() and last_write(), the
## card's answer mode, the clock), asks PickFollowsWrite once, keeps the memory
## it answers with and carries the answer out. The office hands every refresh's
## frame to follow() before its navigator settles and the selected pane to
## follow_start() after, and calls give_up() every frame; the card says why a
## pane it made was not picked (OfficePaneInspector.new_pane_not_picked()).

## The card's words for a new pane that was not picked, by PickFollowsWrite's.
const SAID: Dictionary[PickFollowsWrite.Why, OfficePaneInspector.Unpicked] = {
	PickFollowsWrite.Why.UNSEEN: OfficePaneInspector.Unpicked.UNSEEN,
	PickFollowsWrite.Why.MOVED_ON: OfficePaneInspector.Unpicked.MOVED_ON,
	PickFollowsWrite.Why.OTHER_TERMINAL: OfficePaneInspector.Unpicked.OTHER_TERMINAL,
}

var _navigator: OfficeNavigator
var _fleet: HerdrFleet
var _hud: OfficeHud
var _camera: OfficeCamera
## How long to wait for the new pane, in msec, read when a pick is queued (the
## office's pending_pick_msec, which a test lowers after the office is ready).
var _wait_msec: Callable
## What PickFollowsWrite last answered with, handed back with the next question.
var _memory := PickFollowsWrite.Memory.new()


func _init(
	navigator: OfficeNavigator, fleet: HerdrFleet, hud: OfficeHud, camera: OfficeCamera, wait_msec: Callable
) -> void:
	_navigator = navigator
	_fleet = fleet
	_hud = hud
	_camera = camera
	_wait_msec = wait_msec


## The card split pane `target_key` into a new pane `pane_id` (herdr's
## spelling) with terminal `terminal_id` at the machine's `generation`: wait
## for a snapshot to show it (follow()). A selection only, later.
func later(target_key: String, pane_id: String, terminal_id: String, generation: int) -> void:
	var wait: int = _wait_msec.call()
	_memory = PickFollowsWrite.new_pane_made(
		_memory, target_key, pane_id, terminal_id, generation, _navigator.nav_revision, Time.get_ticks_msec(), wait
	)


## The card made a new space or worktree from pane `from_key`, whose root
## pane `pane_id` (herdr's spelling) has terminal `terminal_id`, at the
## machine's `generation`: wait for a snapshot to show it, in its new zone, as
## for a split. A selection only, later.
func later_space(
	from_key: String, _workspace_id: String, pane_id: String, terminal_id: String, generation: int
) -> void:
	later(from_key, pane_id, terminal_id, generation)


## In a refresh, before the navigator settles: when PickFollowsWrite.new_pane()
## says the new pane is picked, pick it as a list pick does. The card then
## shows that shell; nothing is sent to it. A new zone's shell (a space or a
## worktree) is picked the same way, on the same map: the pick pans to its
## zone's pod. The office's own pick (OfficeNavigator.follow_to()) does not
## count as the viewer moving.
func follow(frame: OfficeFrame) -> void:
	var answer := PickFollowsWrite.new_pane(
		_memory,
		frame,
		_navigator.picked_key,
		_navigator.nav_revision,
		_fleet.generation(_memory.machine()),
		_hud.inspector.answering(),
		Time.get_ticks_msec()
	)
	_leave(answer)
	var pane := answer.pane
	if pane == null:
		return
	_camera.cancel_press()
	_hud.inspector.leave_answer()
	_navigator.follow_to(frame, pane)
	# The split came from the opened panel: it stays open on the new pane, so
	# its card offers START AGENT (a click of its own).
	if not _hud.card_compact():
		_hud.expand_card(pane.key)


## Every frame: stop waiting for the new pane once PickFollowsWrite.overdue()
## says its wait ran out; the card says no snapshot showed it.
func give_up() -> void:
	_leave(PickFollowsWrite.overdue(_memory, Time.get_ticks_msec()))


## In a refresh, once the selection is settled on `pane` (null for none): when
## PickFollowsWrite.started() says the pick goes on to the agent this office
## started there, the navigator picks it.
func follow_start(pane: PaneModel) -> void:
	var key := "" if pane == null else pane.key
	var answer := PickFollowsWrite.started(
		_memory, pane, _navigator.picked_key, _navigator.picked_identity, _fleet.launch_of(key), _fleet.last_write(key)
	)
	_memory = answer.memory
	if answer.pane != null:
		_navigator.pick_desk(answer.pane.key, answer.identity)


## Keep what `answer` remembers, and when it ended a wait the card hears of,
## the card says why.
func _leave(answer: PickFollowsWrite.Answer) -> void:
	_memory = answer.memory
	if not answer.left_from.is_empty():
		_hud.inspector.new_pane_not_picked(answer.left_from, answer.left_pane_id, SAID[answer.why])
