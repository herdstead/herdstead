class_name OfficeQuestionTips
extends RefCounted
## What the question reader (OfficeQuestionReader) is told about the shown
## map, and the tooltip over a blocked agent's bubble that says what the
## reader found. Reads nothing itself and never writes: the reader's own gates
## decide every read (docs/WRITE_BOUNDARY.md, "Reads that are not gestures").

## The office's lens, once it exists: nothing comes up over a bubble while it is held.
var lens: OfficeLens
var _fleet: HerdrFleet
var _hud: OfficeHud
var _camera: OfficeCamera
var _questions: OfficeQuestionReader
## The office's frame now (-> OfficeFrame): a read can come back between refreshes.
var _frame: Callable
## The pointer in viewport pixels now (-> Vector2).
var _mouse: Callable
## The pane whose bubble the pointer is over, its tooltip shown; empty for none.
var _tip_key := ""
## Where the pointer came onto it, in viewport pixels.
var _tip_at := Vector2.ZERO
## The zone whose sign the pointer is over, its tooltip shown; empty for none.
var _sign_key := ""


func _init(hud: OfficeHud, camera: OfficeCamera, frame: Callable, mouse: Callable) -> void:
	_hud = hud
	_camera = camera
	_frame = frame
	_mouse = mouse


## The fleet and the question reader, once the office has made them: until
## then nothing is watched and only hide_tip() does anything.
func attach(fleet: HerdrFleet, questions: OfficeQuestionReader) -> void:
	_fleet = fleet
	_questions = questions


## Tell the question reader which blocked agents the shown machine's map
## (`machine`'s, every zone of it, drawn by `floor_view`) has, which of their bubbles are inside the world on
## screen (`view` -> Rect2, global; in wait order, longest first) and whether their
## machine may be read; nothing is on screen while the terminal monitor, the
## overview or the strategic view covers the world. A refresh and a timer call
## this: a pan moves bubbles on and off screen without a refresh. The tooltip
## over a bubble is written afresh from the reader here, and goes with the bubble.
func watch(floor_view: OfficeFloorView, machine: String, view: Callable) -> void:
	if floor_view == null or _questions == null:
		return
	var frame: OfficeFrame = _frame.call()
	var blocked: Dictionary[String, String] = {}
	var seen: Array[PaneModel] = []
	var found := frame.map_of(machine)
	var live := false
	if found != null:
		live = (
			_fleet.has(machine)
			and _fleet.snapshot_is_current(machine)
			and not _hud.monitor_open()
			and not _hud.overview_open()
			and not _hud.strategic_open()
		)
		var on_screen_rect: Rect2 = view.call()
		for room in found.rooms:
			for pane in room.panes:
				var seat := floor_view.seat(pane.key)
				if seat == null or not _asking(pane):
					continue
				blocked[pane.key] = pane.identity_key()
				var bubble := seat.node.bubble_rect()
				if bubble.has_area() and bubble.intersects(on_screen_rect):
					seen.append(pane)
	var on_screen := PackedStringArray()
	for pane in OfficeProjection.wait_order(seen):
		on_screen.append(pane.key)
	_questions.watch(blocked, on_screen, live)
	# The tooltip says what the reader keeps now, so a terminal it just dropped
	# (another session, still blocked) is never shown; a bubble gone takes it.
	if not _tip_key.is_empty():
		if blocked.has(_tip_key):
			_show_tip(_tip_key)
		else:
			hide_tip()


## A read came back for pane `key`: the tooltip over its bubble says it now.
func show_question(key: String) -> void:
	if key == _tip_key:
		_show_tip(key)


## The pointer came onto the bubble of pane `key` (`inside`), or left it. No
## tooltip while the monitor covers the world or a drag is under way.
func on_bubble_hovered(key: String, inside: bool) -> void:
	if not inside:
		if key == _tip_key:
			hide_tip()
		return
	if _hud.monitor_open() or _camera.dragging or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# Under the lens the bubble draws nothing, and nothing comes up over it.
	if lens != null and lens.held:
		return
	_sign_key = ""
	_tip_key = key
	_tip_at = _mouse.call()
	_show_tip(key)


## The pointer came onto the sign of zone `zone_key` (`inside`), or left it:
## the tooltip names the zone's repository and checkout, and whose worktree a
## mezzanine is (sign_text()). Read from the frame the office holds: nothing is
## read from herdr and nothing written. Not while the monitor covers the world,
## during a drag, or under the lens.
func on_sign_hovered(zone_key: String, inside: bool) -> void:
	if not inside:
		if zone_key == _sign_key:
			hide_tip()
		return
	if _hud.monitor_open() or _camera.dragging or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if lens != null and lens.held:
		return
	var frame: OfficeFrame = _frame.call()
	var found := frame.find_zone(zone_key)
	if found == null:
		return
	_tip_key = ""
	_sign_key = zone_key
	_tip_at = _mouse.call()
	_hud.show_bubble_tip(sign_text(found), _tip_at)


## What a zone's sign tooltip says: `repo · checkout · worktree of 3`, each
## part only when it has one; a zone with none of them says so. The SPACES
## rail's row and the strategic view's caption say it too.
static func sign_text(found: ZoneRef) -> String:
	var zone := found.zone_model
	var parts := PackedStringArray()
	if not zone.repo.is_empty():
		parts.append(zone.repo)
	if not zone.worktree.is_empty():
		parts.append(zone.worktree)
	if not zone.mezzanine_of.is_empty():
		for other in found.building.zones:
			if other.key == zone.mezzanine_of:
				parts.append("worktree of " + OfficeZoneSign.number_text(other))
	return "No repository" if parts.is_empty() else " · ".join(parts)


## Take the tooltip away (a drag, another map, the overview, the lens, ...).
func hide_tip() -> void:
	_tip_key = ""
	_sign_key = ""
	_hud.hide_bubble_tip()


func _show_tip(key: String) -> void:
	var frame: OfficeFrame = _frame.call()
	var pane := frame.pane(key)
	if pane == null:
		hide_tip()
		return
	_hud.show_bubble_tip(_question_text(key, pane.identity_key()), _tip_at)


## What the tooltip over the bubble of pane `key` (terminal `identity`) says:
## that this office reads nothing, the excerpt read for that terminal (an empty
## one says so), or plainly that there is none: never a placeholder promising a
## read, which a dropped machine would never bring.
func _question_text(key: String, identity: String) -> String:
	if _fleet.read_only():
		return OfficeQuestionReader.READ_ONLY_TEXT
	var asked := _questions.question(key, identity)
	if asked == null:
		return OfficeQuestionReader.NOT_READ_TEXT
	return OfficeQuestionReader.EMPTY_TEXT if asked.text.is_empty() else asked.text


## Whether `pane`'s seat shows a bubble: a blocked agent, launching or not
## (PaneModel.asks(): blocked comes first).
static func _asking(pane: PaneModel) -> bool:
	return pane.asks()
