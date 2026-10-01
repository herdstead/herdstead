class_name OfficeViewMarks
extends RefCounted
## What the HUD says about where the view is on the shown map, worked out again
## whenever the view moves: which zones are in view (the SPACES rail marks their
## rows), and the arrows on the world's edges, one per zone with blocked desks
## off screen (EdgeArrowModel).
##
## The office hands it each refresh's frame and the map it drew, and asks it to
## follow the view every frame; it reads the camera, the HUD's room and the
## state log, and hands the HUD plain lists. It never refreshes the office,
## picks nothing, and reads or writes nothing of herdr.
##
## What it remembers having handed over (`_marked`, `_handed`) is written only
## where the HUD is handed it, so the HUD is handed a list exactly when it
## differs from the one it holds, an empty one too. Whether the arrows show at
## all (not under the OVERVIEW, the strategic view or the monitor) is the HUD's
## own (OfficeHud._fit_edge_arrows()): an overlay hides them and forgets nothing.

## The map drawn now; the office sets it when it builds a world.
var floor_view: OfficeFloorView

var _hud: OfficeHud
var _camera: OfficeCamera
var _fleet: HerdrFleet
## The part of the world on screen, in global coordinates (-> Rect2): the office's.
var _view: Callable
## The camera position and world room the marks were last worked out for.
var _viewed_at := Vector2.INF
var _viewed_room := Rect2()
## What the rail's in-view marks and the arrows the HUD was last handed say.
var _marked := ""
var _handed := ""


func _init(hud: OfficeHud, camera: OfficeCamera, fleet: HerdrFleet, view: Callable) -> void:
	_hud = hud
	_camera = camera
	_fleet = fleet
	_view = view


## The view moved without a refresh (a drag, the wheel, the arrow keys, a panel
## giving the world more or less room): the marks are worked out again. Only
## when the camera or the world's room really moved; never a refresh.
func follow(frame: OfficeFrame, machine: String) -> void:
	if floor_view == null or (_camera.position == _viewed_at and _hud.world_rect() == _viewed_room):
		return
	show(frame, machine)


## A second has gone by: an arrow's tooltip says how long its desk has waited,
## so the arrows shown are worked out again. Nothing while there are none.
func tick(frame: OfficeFrame, machine: String) -> void:
	if floor_view != null and not _handed.is_empty():
		show(frame, machine)


## The marks for the view now on machine `machine`'s map, each handed to the
## HUD only when it changed. A refresh, follow() and tick() call this.
func show(frame: OfficeFrame, machine: String) -> void:
	_viewed_at = _camera.position
	_viewed_room = _hud.world_rect()
	var view: Rect2 = _view.call()
	var keys := _zones_in_view(view)
	var marked := "\n".join(keys)
	if marked != _marked:
		_marked = marked
		_hud.spaces.set_in_view(keys)
	var arrows := EdgeArrowModel.of(view, _targets(frame, machine))
	var said := PackedStringArray()
	for arrow in arrows:
		said.append(arrow.signature())
	var handed := "\n".join(said)
	if handed != _handed:
		_handed = handed
		_hud.show_edge_arrows(arrows)


## The zones of the drawn map whose rectangle (ZonePlacement.bounds(),
## partitions and all) meets `view`, in the plan's order.
func _zones_in_view(view: Rect2) -> PackedStringArray:
	var keys := PackedStringArray()
	if floor_view == null or floor_view.plan == null:
		return keys
	for placed in floor_view.plan.zones:
		var area := placed.bounds()
		if Rect2(floor_view.root.to_global(area.position), area.size).intersects(view):
			keys.append(placed.zone_key)
	return keys


## Every blocked desk of machine `machine`'s map as drawn: an agent that asks
## (one blocked while herdr still starts it included), with its chip's
## rectangle, or where its seat answers a click while it draws no chip, and how
## long it has waited by the state log. None for a machine that is not
## answering: a lost connection counts nobody waiting (invariant 4).
func _targets(frame: OfficeFrame, machine: String) -> Array[EdgeArrowModel.Target]:
	var targets: Array[EdgeArrowModel.Target] = []
	var building := frame.building_of(machine)
	if floor_view == null or building == null or building.stale:
		return targets
	var ledger := _fleet.state_log()
	var now := Time.get_ticks_msec()
	for zone in OfficeNavigator.section(building.zones):
		for room in zone.rooms:
			for pane in room.panes:
				if not pane.asks() or pane.launching() or pane.provider.is_empty():
					continue
				var seat := floor_view.seat(pane.key)
				if seat == null:
					continue
				var target := EdgeArrowModel.Target.new()
				target.zone_key = zone.key
				target.number = OfficeZoneSign.number_text(zone)
				target.words = OfficeZoneSign.words(zone)
				target.machine = building.key
				target.pane_key = pane.key
				var chip := seat.node.bubble_rect()
				target.rect = chip if chip.has_area() else seat.node.target_rect()
				target.wait = StateLog.wait_of(ledger.track(pane.key), now)
				targets.append(target)
	return targets
