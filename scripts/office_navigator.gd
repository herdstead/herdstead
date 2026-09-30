class_name OfficeNavigator
extends RefCounted
## What the viewer is looking at and has asked for, and every decision about
## it: the picked desk and the one selected, the picked floor, the floor shown,
## a desk to reveal once its floor is drawn, and where each floor was last
## panned to.
##
## Pure: no node, no fleet, no HUD. The office hands it each refresh's
## OfficeFrame and carries out what it decides: the camera and the world, which
## switch floors at once. Herdr never learns about any of this; which floor is
## shown is the viewer's state.

## Composite pane key (see HerdrFleet.pane_key) the viewer picked. Empty means
## "follow what herdr has focused".
var picked_key := ""
## PaneModel.identity_key() of the pane when it was picked: which terminal the
## viewer chose. A pane id herdr later gives another terminal still selects its
## desk, but it is not that pick (see is_picked()); empty with no pick.
var picked_identity := ""
## The desk selected by the last settle(): the picked one while herdr still has
## it, else herdr's focus.
var active_key := ""
## Floor key the viewer chose (minimap, signpost, PageUp/PageDown, `N`). Empty means
## "the floor holding the selection". Forgotten once that floor is gone.
var picked_floor := ""
## Floor key drawn now.
var shown_key := ""
## Explicit attention navigation reveals this pane after its floor is drawn.
var reveal_on_arrival := ""
## Counts the navigations the viewer asked for: a floor picked (pick_zone()),
## PageUp/PageDown (step_zone()), and every locate: `N`, `‹ ›`, a top-bar
## counter, the agent list, NEWS, EVENTS, the overview and the strategic view
## (next_human(), step(), next_of(), locate()). Never panning (a drag, the
## wheel, the arrow keys) and never a desk click. A pick waiting for a new pane
## records it (office.gd's PendingPick), for when navigating stops meaning a
## floor switch.
var nav_revision := 0
## One-shot: the pane whose desk the office pans to after it next draws the
## shown floor, framing its whole table with `pan_whole_table`; empty for none.
## Set when a floor is shown for the first time in this run (show_floor()), for
## the selection; the office takes it (take_pan_to()) whether or not it is drawn.
var pan_to := ""
var pan_whole_table := false
## `--floor=<number>`: a Local floor to pick once Local has it; -1 when done.
var wanted_floor := -1
## Floor key -> where the viewer left it panned, for the floors left this run.
var _floor_pans: Dictionary[String, Vector2] = {}
## The machine of the floor drawn now (shown_machine()).
var _shown_machine := ""

# --- a refresh ----------------------------------------------------------------


## Settle the selection and the viewer's pick against `frame`, and answer the
## floor the viewer wants to see. Floors that went away take their pan with them.
func settle(frame: OfficeFrame) -> String:
	for key: String in _floor_pans.keys():
		if frame.find_floor(key) == null:
			_floor_pans.erase(key)
	active_key = frame.effective_selection(picked_key)
	# A pane can be valid but not yet placed in a tab/floor. Keep its inspector
	# available instead of silently replacing it with herdr's focused desk.
	if frame.pane(picked_key) != null:
		active_key = picked_key
	_resolve_wanted_floor(frame)
	if frame.find_floor(picked_floor) == null:
		# A floor that went away is forgotten, not waited for.
		picked_floor = ""
	return frame.choose_floor(picked_floor, active_key)


## `floors` (one building's, ascending by number) as the building section draws
## them, top to bottom: the highest floor on top, and each floor's mezzanines
## hung just below it in letter order, as herdr's sidebar hangs a worktree
## under the space it was made from. Pure; the minimap draws this order.
static func section(floors: Array[ZoneModel]) -> Array[ZoneModel]:
	var keys: Dictionary[String, bool] = {}
	for floor_model in floors:
		keys[floor_model.key] = true
	# The tree (OfficeProjection.floor_tree()) puts every mezzanine right after
	# its source: cut it into groups there, and stack the groups highest first.
	var groups: Array[Array] = []
	for floor_model in OfficeProjection.floor_tree(floors):
		if groups.is_empty() or not keys.has(floor_model.mezzanine_of):
			groups.append([])
		groups[-1].append(floor_model)
	var drawn: Array[ZoneModel] = []
	for index in range(groups.size() - 1, -1, -1):
		for floor_model: ZoneModel in groups[index]:
			drawn.append(floor_model)
	return drawn


## Every floor key bottom to top, building after building: each building's
## section() read upwards, so one row up the minimap is one step up here. What
## PageUp/PageDown step through.
static func shaft_order(frame: OfficeFrame) -> Array[String]:
	var order: Array[String] = []
	for building in frame.buildings:
		var drawn := section(building.zones)
		for index in range(drawn.size() - 1, -1, -1):
			order.append(drawn[index].key)
	return order


## Show `key` instead of the floor shown now, remembering where that one was
## panned to (`pan`) if it still exists.
func show_floor(frame: OfficeFrame, key: String, pan: Vector2) -> void:
	if frame.find_floor(shown_key) != null:
		_floor_pans[shown_key] = pan
	shown_key = key
	var found := frame.find_floor(key)
	_shown_machine = "" if found == null else found.building.key
	if not _floor_pans.has(key):
		pan_to = active_key
		pan_whole_table = true


## The machine whose floor is shown; empty before the first.
func shown_machine() -> String:
	return _shown_machine


## pan_to, forgotten: the office asks once, after drawing the shown floor.
func take_pan_to() -> String:
	var key := pan_to
	pan_to = ""
	return key


## Where the viewer left `key`; zero for a floor not left before in this run.
func pan_of(key: String) -> Vector2:
	return _floor_pans.get(key, Vector2.ZERO)


## A floor seen for the first time in this run opens on the selection's whole
## table, when the selection is drawn there.
func reveals_table(changed_floor: bool) -> bool:
	return changed_floor and not _floor_pans.has(shown_key)


## The pane an explicit navigation asked to see has been brought into view.
func revealed() -> void:
	reveal_on_arrival = ""


# --- what the viewer asks for -------------------------------------------------


## A floor from the minimap, a signpost or PageUp/PageDown: it wins over the selection's
## floor until it goes away. A reveal still pending belongs to the navigation
## this one replaces.
func pick_floor(key: String) -> void:
	picked_floor = key
	reveal_on_arrival = ""


## The viewer picks zone `key` (a FLOORS row, a signpost): for now its floor is
## shown, as pick_floor() does, and it counts as a navigation (nav_revision).
func pick_zone(key: String) -> void:
	pick_floor(key)
	nav_revision += 1


## PageUp/PageDown: pick the zone one row up or down (step_floor()), as
## pick_zone() does; false at either end, where nothing is picked or counted.
func step_zone(frame: OfficeFrame, direction: int) -> bool:
	var next := step_floor(frame, direction)
	if next.is_empty():
		return false
	pick_zone(next)
	return true


## PageUp/PageDown: one row up or down the building section from the shown
## floor, from a building's top floor into the next building's lowest; empty at
## either end. See shaft_order().
func step_floor(frame: OfficeFrame, direction: int) -> String:
	var order := shaft_order(frame)
	if order.is_empty():
		return ""
	var at := order.find(shown_key)
	var next: String = order[0 if at < 0 else clampi(at + direction, 0, order.size() - 1)]
	return "" if next == shown_key else next


## `N`: select the next agent that needs a human, show its floor and reveal its
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
## reaches a done agent meanwhile), in waiting() order: panes no floor seats
## wait in it as the seated do (the top-bar counts include them too).
func _queue(frame: OfficeFrame) -> Array[String]:
	var found := waiting(frame, "blocked")
	if found.is_empty():
		found = waiting(frame, "done")
	var queue: Array[String] = []
	for pane in found:
		queue.append(pane.key)
	return queue


## Select `key`, show its floor and reveal its desk; false for none.
func _pick_in_queue(frame: OfficeFrame, key: String) -> bool:
	if key.is_empty():
		return false
	nav_revision += 1
	picked_key = key
	var picked := frame.pane(key)
	picked_identity = "" if picked == null else picked.identity_key()
	picked_floor = frame.floor_of(key)
	reveal_on_arrival = key
	return true


## A top-bar counter (BLOCKED, DONE): select the next agent in `state`, show
## its floor and reveal its desk, like `N` but only within that state, in
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
	picked_key = next
	var picked := frame.pane(next)
	picked_identity = "" if picked == null else picked.identity_key()
	picked_floor = frame.floor_of(next)
	reveal_on_arrival = next
	return true


## Every agent in `state` on a live building, not still launching, who waited
## longest first (OfficeProjection.wait_order(): an unknown start first): the
## seated in building, floor and room order, then the ones no floor seats, so a
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


## Every seated agent in `state` on a live building, in building, floor and
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


## Attention's "View": select `pane`, show its floor when it has one, and
## reveal its desk once that floor is drawn.
func locate(frame: OfficeFrame, pane: PaneModel) -> void:
	nav_revision += 1
	picked_key = pane.key
	picked_identity = pane.identity_key()
	var floor_key := frame.floor_of(pane.key)
	if not floor_key.is_empty():
		picked_floor = floor_key
	reveal_on_arrival = pane.key


## A still click on a desk picks it, and with it the terminal it holds now
## (`identity`, PaneModel.identity_key()). Picking never changes the floor.
func pick_desk(key: String, identity := "") -> void:
	picked_key = key
	picked_identity = identity


## Whether `pane` is the viewer's pick: its desk, and still the terminal that
## was picked there. False for a pane only herdr's focus selects, and for one
## whose id another terminal has taken since.
func is_picked(pane: PaneModel) -> bool:
	return (
		pane != null and not picked_key.is_empty() and pane.key == picked_key and pane.identity_key() == picked_identity
	)


## `--floor=<number>` names a Local floor by herdr's number, which only means
## something once Local has sent its floors.
func _resolve_wanted_floor(frame: OfficeFrame) -> void:
	if wanted_floor < 0 or frame.buildings.is_empty():
		return
	for floor_model in frame.buildings[0].zones:
		if not floor_model.lobby and floor_model.number == wanted_floor:
			picked_floor = floor_model.key
			wanted_floor = -1
			return
