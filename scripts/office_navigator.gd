class_name OfficeNavigator
extends RefCounted
## What the viewer is looking at and has asked for, and every decision about
## it: the picked desk and the one selected, the picked machine, the machine
## whose map is shown, the zone the viewer picked, a desk or a zone to pan to
## once the map is drawn, and where each map was last panned to.
##
## Pure: no node, no fleet, no HUD. The office hands it each refresh's
## OfficeFrame and carries out what it decides: the camera and the world, which
## switch maps at once. Herdr never learns about any of this; which map is
## shown and where it is panned is the viewer's state.

## Composite pane key (see HerdrFleet.pane_key) the viewer picked. Empty means
## "follow what herdr has focused", and so does a pick whose pane is gone, for
## as long as it is gone (it is remembered: see settle()).
var picked_key := ""
## PaneModel.identity_key() of the pane when it was picked: which terminal the
## viewer chose. A pane id herdr later gives another terminal still selects its
## desk, but it is not that pick (see is_picked()); empty with no pick.
var picked_identity := ""
## The desk selected by the last settle(): the picked one while herdr still has
## it, else herdr's focus.
var active_key := ""
## Machine key the viewer chose (its SPACES heading, a zone picked on it,
## PageUp/PageDown, `N`, a list pick), or the machine herdr's focus moved to
## while it is followed.
## Empty means "the machine holding the selection". Forgotten once it is gone.
var picked_machine := ""
## Machine key whose map is drawn now.
var shown_key := ""
## Explicit attention navigation reveals this pane after its map is drawn.
var reveal_on_arrival := ""
## Counts the navigations the viewer asked for: a zone picked (pick_zone(): a
## SPACES row), a machine picked (pick_machine(): its SPACES heading), an edge
## arrow (pan_to_desk()), PageUp/PageDown (step_zone()), and every locate:
## `N`, `‹ ›`, a top-bar counter, the agent list, NEWS, EVENTS, the overview and
## the strategic view (next_human(), step(), next_of(), locate()). Never panning
## (a drag, the wheel, the arrow keys), never a desk click, never herdr's focus
## moving, never `--space`, and never the office's own pick of a new pane
## (follow_to()). A pick waiting for a new pane records it
## (OfficeNewPaneFollow.PendingPick): the viewer navigating meanwhile cancels it.
var nav_revision := 0
## One-shot: the pane whose desk the office pans to after it next draws the
## shown map, framing its whole pod with `pan_whole_table`; empty for none. Set
## per request: on the first arrival at a map this run, for the selection seated
## there (its whole pod); when herdr's focus moves while it is followed (only
## as far as it takes, see settle()); for an edge arrow's desk (pan_to_desk(),
## as far as it takes too); for a new pane the office picks. The office takes
## it (take_pan_to()) whether or not it is drawn.
var pan_to := ""
var pan_whole_table := false
## One-shot: the zone the office pans to after it next draws the shown map,
## its aisle row at the top of the world (OfficeScene.reveal_zone()); empty for
## none. Set by a zone picked, and on the first arrival at a map this run when
## the selection is not seated there (its first zone as the rail draws them).
var pan_zone := ""
## `--space=<number>`: a Local zone to pick once Local has it; -1 when done.
var wanted_space := -1
## Machine key -> where the viewer left its map panned, for the maps left this run.
var _map_pans: Dictionary[String, Vector2] = {}
## Machines whose map has been opened this run (see _open()): shown with a zone
## at least once. A map first shown empty (a machine before its first snapshot)
## is opened when its first zone arrives.
var _opened: Dictionary[String, bool] = {}
## The zone the viewer last picked (pick_zone()); empty once they navigate to a
## pane, pick a desk, herdr's focus moves them, or it is gone. See current_zone().
var _picked_zone := ""
## Herdr's focus at the last settle(), and whether there was one: a change of
## it between two settles is revealed (settle()).
var _last_focus := ""
var _settled := false
## A machine picked or a desk asked for (pick_machine(), pan_to_desk()) that no
## settle() has carried out yet: the next one does, and herdr's focus moving
## meanwhile does not take the map or the pan from it.
var _asked := false

# --- a refresh ----------------------------------------------------------------


## Settle the selection and the viewer's pick against `frame`, and answer the
## machine whose map the viewer wants to see. Machines that went away take
## their pan with them.
##
## Herdr's focus moving is revealed: while the frame has no picked pane (nothing
## is picked, or the pane picked is gone), so that the selection is herdr's
## focus, when that focus is another desk than at the last settle, the office
## pans to it as far as it takes (pan_to, not the whole pod; nothing moves when
## it is on screen already), and its machine's map is shown (a switch to another
## machine is cold, and it is revealed on arrival). The map is one world:
## nothing else would bring a focus that moved to another zone into view. It
## never counts as a navigation, and a settle where the focus did not move sets
## nothing, so a pan the viewer made stays; the picked pane going is not the
## focus moving either (the selection falls back to the focus where it was, and
## the map and the machine the viewer chose stay). An explicit navigation
## waiting to be carried out wins over it: a zone picked or a pane located
## (pan_zone, reveal_on_arrival), and a machine picked or a desk asked for
## (pick_machine(), pan_to_desk()) in the settle that carries it out. That
## settle still records the focus it saw, so the move it passed over is not
## revealed later; the next move is. A pick whose pane is gone is still
## remembered: the pane back, it is the selection again, and the focus is no
## longer followed.
func settle(frame: OfficeFrame) -> String:
	for key: String in _map_pans.keys():
		if frame.building_of(key) == null:
			_map_pans.erase(key)
	for key: String in _opened.keys():
		if frame.building_of(key) == null:
			_opened.erase(key)
	active_key = frame.effective_selection(picked_key)
	# A pane can be valid but not yet placed in a tab/zone. Keep its inspector
	# available instead of silently replacing it with herdr's focused desk.
	var pick_alive := frame.pane(picked_key) != null
	if pick_alive:
		active_key = picked_key
	_resolve_wanted_space(frame)
	if frame.building_of(picked_machine) == null:
		# A machine that went away is forgotten, not waited for.
		picked_machine = ""
	if frame.find_zone(_picked_zone) == null:
		_picked_zone = ""
	var moved := _settled and not pick_alive and frame.herdr_focus != _last_focus
	if moved and not _asked and pan_zone.is_empty() and reveal_on_arrival.is_empty():
		var zone := frame.find_zone(frame.zone_of(active_key))
		if zone != null:
			_ask_pan(active_key, false)
			picked_machine = zone.building.key
			_picked_zone = ""
	_last_focus = frame.herdr_focus
	_settled = true
	_asked = false
	var chosen := frame.choose_machine(picked_machine, active_key)
	if chosen == shown_key:
		_open(frame, chosen)
	return chosen


## `zones` (one machine's, ascending by number) as its section of the SPACES
## rail draws them, top to bottom: ascending, and each zone's mezzanines right
## after it in letter order, as herdr's sidebar hangs a worktree under the
## space it was made from (OfficeProjection.floor_tree()). A mezzanine whose
## source is not open stands by its own number. Pure; the rail draws this
## order, PageUp and PageDown step through it (OfficeFrame.zone_order), and the
## strategic view's sections follow it.
static func section(zones: Array[ZoneModel]) -> Array[ZoneModel]:
	return OfficeProjection.floor_tree(zones)


## Show machine `key`'s map instead of the one shown now, remembering where that
## one was panned to (`pan`) if its machine still exists, and open it if it is
## seen for the first time (_open()).
func show_machine(frame: OfficeFrame, key: String, pan: Vector2) -> void:
	if frame.building_of(shown_key) != null:
		_map_pans[shown_key] = pan
	shown_key = key
	_open(frame, key)


## The first arrival at machine `key`'s map this run, once it has a zone (a map
## first shown empty is opened when its first zone arrives, by settle()): it
## opens on the selection's whole pod when the selection is seated there, else
## on the first zone as the rail draws them (pan_zone); a zone the viewer picked
## there opens on that zone instead. Once per map per run.
func _open(frame: OfficeFrame, key: String) -> void:
	var building := frame.building_of(key)
	if _opened.has(key) or building == null or building.zones.is_empty():
		return
	_opened[key] = true
	if not pan_zone.is_empty():
		return
	var holding := frame.find_zone(frame.zone_of(active_key))
	if holding != null and holding.building.key == key:
		_ask_pan(active_key, true)
		return
	pan_zone = section(building.zones)[0].key


## The machine whose map is shown; empty before the first.
func shown_machine() -> String:
	return shown_key


## pan_to, forgotten: the office asks once, after drawing the shown map.
func take_pan_to() -> String:
	var key := pan_to
	pan_to = ""
	return key


## pan_zone, forgotten: the office asks once, after drawing the shown map.
func take_pan_zone() -> String:
	var key := pan_zone
	pan_zone = ""
	return key


## Where the viewer left machine `key`'s map; zero for a map not left before in this run.
func pan_of(key: String) -> Vector2:
	return _map_pans.get(key, Vector2.ZERO)


## The pane an explicit navigation asked to see has been brought into view.
func revealed() -> void:
	reveal_on_arrival = ""


## The zone PageUp and PageDown step from: the one the viewer last picked, else
## the zone of the selection; empty when neither is on the shown map. (The
## rail marks the zones in view, not this one.)
func current_zone(frame: OfficeFrame) -> String:
	var picked := frame.find_zone(_picked_zone)
	if picked != null and picked.building.key == shown_key:
		return _picked_zone
	var holding := frame.find_zone(frame.zone_of(active_key))
	if holding != null and holding.building.key == shown_key:
		return holding.zone_model.key
	return ""


# --- what the viewer asks for -------------------------------------------------


## The viewer picks zone `key` (a SPACES row): the office pans to it, its aisle
## row at the top of the world (pan_zone), and shows its machine's map first
## only when that is another machine's. It counts as a navigation
## (nav_revision). A pan or reveal still pending belongs to the navigation this
## one replaces.
func pick_zone(key: String) -> void:
	_pick_zone(key)
	nav_revision += 1


## The viewer picks machine `key` (its SPACES heading): its map is shown, a
## machine without a zone as an empty map. Where it opens is the map's own: its
## first arrival (_open()) or where the viewer left it (pan_of()); no zone is
## picked, and a pan or reveal still pending belongs to the navigation this
## one replaces. It counts as a navigation (nav_revision), and it wins over
## herdr's focus moving before the settle that carries it out (settle()).
func pick_machine(key: String) -> void:
	picked_machine = key
	_picked_zone = ""
	pan_zone = ""
	pan_to = ""
	reveal_on_arrival = ""
	_asked = true
	nav_revision += 1


## The viewer asks to see the desk of pane `key` on the shown map (an edge
## arrow): the office pans as far as it takes for that desk to be on screen
## (pan_to, not its whole pod). Nothing is selected and no zone is picked; a
## pan or reveal still pending belongs to the navigation this one replaces. It
## counts as a navigation (nav_revision), and it wins over herdr's focus moving
## before the settle that carries it out (settle()): its desk's machine is the
## one the viewer chose, as a zone picked there would make it, so a focus that
## moved onto another machine does not take the map either.
func pan_to_desk(key: String) -> void:
	picked_machine = HerdrFleet.split_key(key)[0]
	_ask_pan(key, false)
	reveal_on_arrival = ""
	_asked = true
	nav_revision += 1


## PageUp (-1) / PageDown (+1): pick the zone one row up or down the rail from
## the current one (next_zone()), as pick_zone() does, crossing machines; false
## at either end, where nothing is picked or counted. The rail is ascending, so
## PageUp goes to the lower-numbered zone and PageDown to the higher.
func step_zone(frame: OfficeFrame, direction: int) -> bool:
	var next := next_zone(frame, direction)
	if next.is_empty():
		return false
	pick_zone(next)
	return true


## The zone one row up (-1) or down (+1) the rail (OfficeFrame.zone_order) from
## the current one (current_zone()), from a machine's last zone into the next
## machine's first; empty at either end. With no current zone, the shown map's
## first zone (or the rail's first). Pure: it picks nothing.
func next_zone(frame: OfficeFrame, direction: int) -> String:
	var order := frame.zone_order
	if order.is_empty():
		return ""
	var current := current_zone(frame)
	var at := order.find(current)
	if at < 0:
		for key in order:
			if frame.find_zone(key).building.key == shown_key:
				return key
		return order[0]
	var next: String = order[clampi(at + direction, 0, order.size() - 1)]
	return "" if next == current else next


## `N`: select the next agent that needs a human, show its map and reveal its
## desk. Repeated presses walk the queue and wrap around: the blocked while
## anyone is, else the done (see _queue()); false when nobody needs a human.
## The order is who waited longest first (OfficeProjection.wait_order(), by
## each pane's state_since).
func next_human(frame: OfficeFrame) -> bool:
	return _pick_in_queue(frame, peek_next(frame))


## `‹` (-1) or `›` (+1) on the staff panel's line: select the one before or
## after the pick in NEXT's queue and show its desk, as next_human() does; false
## when nobody needs a human. Only a selection: the office opens nothing for it.
func step(frame: OfficeFrame, direction: int) -> bool:
	return _pick_in_queue(frame, peek_next(frame) if direction > 0 else peek_prev(frame))


## Whom the next `N` picks, changing nothing: the key after the pick in the
## queue (the blocked while anyone is, else the done), wrapping around; from a
## selection outside it (a done agent while someone is blocked, too), its first:
## the one who has waited longest. Empty when nobody needs a human. The staff
## panel's NEXT button says it (office.gd), and pressing it is `N`.
func peek_next(frame: OfficeFrame) -> String:
	var queue := _queue(frame)
	if queue.is_empty():
		return ""
	return queue[(queue.find(picked_key) + 1) % queue.size()]


## Whom `‹` picks, changing nothing: the key before the pick in the queue,
## wrapping around; from a selection outside the queue, its last one. Empty
## when nobody needs a human.
func peek_prev(frame: OfficeFrame) -> String:
	var queue := _queue(frame)
	if queue.is_empty():
		return ""
	var at := queue.find(picked_key)
	return queue[queue.size() - 1] if at < 0 else queue[(at - 1 + queue.size()) % queue.size()]


## NEXT's queue: while anyone is blocked, the blocked only, and the done only
## once nobody is (like Civilization's turn blockers; the top bar's DONE still
## reaches a done agent meanwhile), in waiting() order: panes no zone seats
## wait in it as the seated do (the top-bar counts include them too).
func _queue(frame: OfficeFrame) -> Array[String]:
	var found := waiting(frame, "blocked")
	if found.is_empty():
		found = waiting(frame, "done")
	var queue: Array[String] = []
	for pane in found:
		queue.append(pane.key)
	return queue


## Select `key`, show its map and reveal its desk; false for none.
func _pick_in_queue(frame: OfficeFrame, key: String) -> bool:
	if key.is_empty():
		return false
	nav_revision += 1
	_select(frame, key)
	return true


## A top-bar counter (BLOCKED, DONE): select the next agent in `state`, show
## its map and reveal its desk, like `N` but only within that state, in
## waiting() order (so DONE starts from the oldest UNREAD). Repeated presses
## walk the queue and wrap; a selection outside it starts from the top. False
## when nobody is in `state`.
func next_of(frame: OfficeFrame, state: String) -> bool:
	var queue: Array[String] = []
	for pane in waiting(frame, state):
		queue.append(pane.key)
	if queue.is_empty():
		return false
	var next := queue[(queue.find(picked_key) + 1) % queue.size()]
	nav_revision += 1
	_select(frame, next)
	return true


## Every agent in `state` on a live machine, not still launching, who waited
## longest first (OfficeProjection.wait_order(): an unknown start first): the
## seated in machine, zone and room order, then the ones no zone seats, so a
## tie keeps a seated pane first. The one order of `N`, NEXT and the counters.
static func waiting(frame: OfficeFrame, state: String) -> Array[PaneModel]:
	var found := _seated_in_state(frame, state)
	var seated: Dictionary[String, bool] = {}
	for pane in found:
		seated[pane.key] = true
	for pane in frame.live_panes:
		if not pane.provider.is_empty() and not pane.launching() and pane.state == state and not seated.has(pane.key):
			found.append(pane)
	return OfficeProjection.wait_order(found)


## Every seated agent in `state` on a live machine, in machine, zone and
## room order: the same rule as OfficeProjection.attention_queue().
static func _seated_in_state(frame: OfficeFrame, state: String) -> Array[PaneModel]:
	var found: Array[PaneModel] = []
	for building_model in frame.buildings:
		if building_model.stale:
			continue
		for floor_model in building_model.zones:
			for room in floor_model.rooms:
				for pane in room.panes:
					if not pane.provider.is_empty() and not pane.launching() and pane.state == state:
						found.append(pane)
	return found


## Attention's "View": select `pane`, show its map when it is seated, and
## reveal its desk once that map is drawn. Counts as a navigation.
func locate(frame: OfficeFrame, pane: PaneModel) -> void:
	nav_revision += 1
	_locate(frame, pane)


## The office's own pick of a new pane a split, a new space or a worktree made
## (OfficeNewPaneFollow): selected as locate() does, its whole pod framed once
## drawn (a new space's pane is in a new zone of the same map), and not counted:
## it is not the viewer moving.
func follow_to(frame: OfficeFrame, pane: PaneModel) -> void:
	_locate(frame, pane)
	_ask_pan(pane.key, true)


## A still click on a desk picks it, and with it the terminal it holds now
## (`identity`, PaneModel.identity_key()). Picking never changes the map or pans;
## the rail then highlights that desk's zone.
func pick_desk(key: String, identity := "") -> void:
	picked_key = key
	picked_identity = identity
	_picked_zone = ""


## Whether `pane` is the viewer's pick: its desk, and still the terminal that
## was picked there. False for a pane only herdr's focus selects, and for one
## whose id another terminal has taken since.
func is_picked(pane: PaneModel) -> bool:
	return (
		pane != null and not picked_key.is_empty() and pane.key == picked_key and pane.identity_key() == picked_identity
	)


## `--space=<number>` names a Local zone by herdr's number, which only means
## something once Local has sent its workspaces: then it is picked as a SPACES
## row picks it, without counting (the command line is not the viewer moving).
func _resolve_wanted_space(frame: OfficeFrame) -> void:
	if wanted_space < 0 or frame.buildings.is_empty():
		return
	for zone in frame.buildings[0].zones:
		if zone.number == wanted_space:
			_pick_zone(zone.key)
			wanted_space = -1
			return


## pick_zone() without counting it.
func _pick_zone(key: String) -> void:
	picked_machine = HerdrFleet.split_key(key)[0]
	_picked_zone = key
	pan_zone = key
	pan_to = ""
	reveal_on_arrival = ""


## Select pane `key` (N, NEXT, a counter): its terminal, its map, its desk revealed.
func _select(frame: OfficeFrame, key: String) -> void:
	picked_key = key
	var picked := frame.pane(key)
	picked_identity = "" if picked == null else picked.identity_key()
	var zone := frame.find_zone(frame.zone_of(key))
	picked_machine = "" if zone == null else zone.building.key
	_navigated_to_pane(key)


## locate() without counting it.
func _locate(frame: OfficeFrame, pane: PaneModel) -> void:
	picked_key = pane.key
	picked_identity = pane.identity_key()
	var zone := frame.find_zone(frame.zone_of(pane.key))
	if zone != null:
		picked_machine = zone.building.key
	_navigated_to_pane(pane.key)


## A navigation to pane `key`: its desk is revealed on arrival, and the zone or
## pan an earlier navigation asked for is dropped; the rail then highlights its zone.
func _navigated_to_pane(key: String) -> void:
	reveal_on_arrival = key
	pan_zone = ""
	pan_to = ""
	_picked_zone = ""


## Ask for one pan to pane `key` (pan_to), its whole pod (`whole`) or just its desk.
func _ask_pan(key: String, whole: bool) -> void:
	pan_to = key
	pan_whole_table = whole
	pan_zone = ""
