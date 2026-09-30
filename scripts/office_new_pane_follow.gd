class_name OfficeNewPaneFollow
extends RefCounted
## The new pane a split (or a new space or worktree) from the agent card made,
## waited for until a snapshot shows it, then picked: a selection only, later,
## never a write. The office hands every refresh's frame to follow() before its
## navigator settles, and give_up() every frame; the card says why a pane it
## made was not picked (OfficePaneInspector.new_pane_not_picked()).


## A pane a split made (HerdrFleet.pane_key) with its terminal, on its
## machine's `generation`: picked when a snapshot shows it, while the viewer's
## pick is still `from_key`, the pane split, on the floor shown then (`floor_key`),
## out of answer mode, and until `until_msec`.
class PendingPick:
	var key := ""
	var pane_id := ""
	var terminal_id := ""
	var from_key := ""
	var floor_key := ""
	## OfficeNavigator.nav_revision then: recorded, not yet checked.
	var nav_revision := 0
	var generation := 0
	var until_msec := 0
	## The pane is a new floor's shell (a space or a worktree the card made):
	## picking it moves floors. Said for the record; the wait is the same.
	var cross_floor := false


var _navigator: OfficeNavigator
var _fleet: HerdrFleet
var _hud: OfficeHud
var _camera: OfficeCamera
## How long to wait for the new pane, in msec, read when a pick is queued (the
## office's pending_pick_msec, which a test lowers after the office is ready).
var _wait_msec: Callable
## The new pane waited for; null for none.
var _pending: PendingPick


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
	var pending := PendingPick.new()
	var machine := HerdrFleet.split_key(target_key)[0]
	pending.key = HerdrFleet.pane_key(machine, pane_id)
	pending.pane_id = pane_id
	pending.terminal_id = terminal_id
	pending.from_key = target_key
	pending.floor_key = _navigator.shown_key
	pending.nav_revision = _navigator.nav_revision
	pending.generation = generation
	var wait: int = _wait_msec.call()
	pending.until_msec = Time.get_ticks_msec() + wait
	_pending = pending


## The card made a new space or worktree from pane `from_key`, whose root
## pane `pane_id` (herdr's spelling) has terminal `terminal_id`, at the
## machine's `generation`: wait for a snapshot to show it, on its new floor
## (follow() with `cross_floor`). A selection only, later.
func later_space(
	from_key: String, _workspace_id: String, pane_id: String, terminal_id: String, generation: int
) -> void:
	later(from_key, pane_id, terminal_id, generation)
	_pending.cross_floor = true


## In a refresh, before the navigator settles: the new pane a split made is in
## `frame`, with the terminal herdr named, on the same connection, and the
## viewer is still where the split left them (the pane split picked, the same
## floor shown, out of answer mode): pick it, as a list pick does, and stop
## waiting. The card then shows that shell; nothing is sent to it. Another pick
## or connection: stop waiting. Another floor, answer mode, or the pane with
## another terminal: stop waiting, and the card says why it was not picked.
## A new floor's shell (`cross_floor`: a space or a worktree) is picked the
## same way: locate() takes the pick to its floor, which the navigator then
## shows; the viewer changing floor meanwhile still counts as moving on.
func follow(frame: OfficeFrame) -> void:
	var pending := _pending
	if pending == null or give_up():
		return
	var machine := HerdrFleet.split_key(pending.key)[0]
	if _navigator.picked_key != pending.from_key or _fleet.generation(machine) != pending.generation:
		_pending = null
		return
	if _navigator.shown_key != pending.floor_key or _hud.inspector.answering():
		_leave(OfficePaneInspector.Unpicked.MOVED_ON)
		return
	var pane := frame.pane(pending.key)
	if pane == null:
		return
	if pane.terminal_id != pending.terminal_id:
		_leave(OfficePaneInspector.Unpicked.OTHER_TERMINAL)
		return
	_pending = null
	_camera.cancel_press()
	_hud.inspector.leave_answer()
	_navigator.locate(frame, pane)
	# The split came from the opened panel: it stays open on the new pane, so
	# its card offers START AGENT (a click of its own).
	if not _hud.card_compact():
		_hud.expand_card(pane.key)


## Stop waiting for the new pane once its wait ran out: the card says no
## snapshot showed it. True when it just gave up.
func give_up() -> bool:
	if _pending == null or Time.get_ticks_msec() < _pending.until_msec:
		return false
	_leave(OfficePaneInspector.Unpicked.UNSEEN)
	return true


## Stop waiting for the new pane without picking it; the card says `why`.
func _leave(why: OfficePaneInspector.Unpicked) -> void:
	var left := _pending
	_pending = null
	_hud.inspector.new_pane_not_picked(left.from_key, left.pane_id, why)
