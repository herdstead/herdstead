class_name OfficeCamera
extends Camera2D
## The office's view of its world: how far it is panned, what a drag, the arrow
## keys and the wheel do to that, how far it may go, and how a desk is brought
## into view. It asks the HUD only for the room the panels leave the world (see
## free_rect()), and whether the viewer is busy with an overlay or a ride.

const PAN_SPEED := 320.0
## How far one wheel notch pans.
const SCROLL_STEP := 32.0
## How far a press may travel before its release is a drag rather than a click.
const CLICK_SLOP := 4.0
## Room kept above a desk brought into view, for the badge over it.
const REVEAL_HEADROOM := 32.0

## Where the world's top-left is scrolled to, in world units. Clamped every
## frame to how much larger the world is than the room it has.
var pan := Vector2.ZERO
## The world's extent, which the pan is clamped to.
var world_size := Vector2.ZERO
## A left button went down over the world and has not come up yet.
var dragging := false

var _hud: OfficeHud
var _screen: Callable
var _press_cancelled := false
var _press_at := Vector2.ZERO
var _drag_from := Vector2.ZERO
## What free_rect() last laid the HUD out for, and the room that left the world.
var _free_screen := Vector2(-1, -1)
var _free_rect := Rect2()


## `screen` answers the viewport's size in viewport pixels (a test decides it).
func _init(hud: OfficeHud, screen: Callable) -> void:
	name = "Camera"
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_hud = hud
	_screen = screen


func _process(delta: float) -> void:
	var move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if not _hud.holds_keyboard() and move != Vector2.ZERO:
		pan += move * PAN_SPEED * delta
	var reach := world_size - free_rect().size
	pan = pan.clamp(Vector2.ZERO, Vector2(maxf(0.0, reach.x), maxf(0.0, reach.y)))
	position = pan.round()


## The screen area the HUD leaves the world: right of the SPACES rail, left of the
## inspector, below the bar. Where those panels stand is `hud.tscn`'s business,
## so changing the window changes the visible area while the plan stays fixed.
## The panels' rectangle depends on the screen size alone and _process() asks
## for it every frame, so the HUD is laid out again only when that size moves.
func free_rect() -> Rect2:
	var screen: Vector2 = _screen.call()
	if screen != _free_screen:
		_free_screen = screen
		_hud.fit(screen)
		_free_rect = _hud.world_rect()
	return _free_rect


## The HUD moved a panel without the window changing size: the next
## free_rect() asks it again.
func relayout() -> void:
	_free_screen = Vector2(-1, -1)


## One wheel notch or scroll key: `direction` is a unit step on either axis.
func scroll(direction: Vector2) -> void:
	pan += direction * SCROLL_STEP


## A drag pans the office and only a still click picks a desk, which is one rule
## in one place: the viewport hands a mouse button to _unhandled_input first, so
## the press a pick belongs to is already recorded here when the seat's Area2D
## reports it on the next physics frame (see still_click()).
func drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragging:
		var motion: InputEventMouseMotion = event
		# Not for a release over a HUD panel: that one does arrive, because the
		# press found no control and the panels never took the button away (see
		# test_office_two_machines). This is for a release that never arrives at
		# all, which leaves the office panning under a button nobody is holding.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			dragging = false
			return
		pan = _drag_from - (motion.position - _press_at)
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if click.pressed:
			dragging = true
			_press_cancelled = false
			_press_at = click.position
			_drag_from = pan
		elif dragging:
			dragging = false


## The press under way belongs to no click and no drag any more: a ride began,
## or an overlay opened over the world.
func cancel_press() -> void:
	dragging = false
	_press_cancelled = true


## Whether a release at `at` (viewport pixels) ends a still click: its press was
## not cancelled and did not travel CLICK_SLOP or further.
func still_click(at: Vector2) -> bool:
	return not _press_cancelled and (at - _press_at).length() < CLICK_SLOP


## Pan just enough for `bounds` (in the world's own coordinates) to be on
## screen, with REVEAL_HEADROOM above it; and for `beside` too (the pod a desk
## stands at, for the framing a map opens on) when the two together fit the
## view, headroom included: else `bounds` alone (framing()). From where the pan
## is now; _process() clamps it to the map on the next frame.
func reveal(bounds: Rect2, beside := Rect2()) -> void:
	var room := free_rect().size
	pan = revealed(pan, framing(bounds, beside, room), room)


## Pan to `opening` (a zone's, OfficeFloorView.zone_opening(), in the world's
## own coordinates): its top at the top of the world, with no headroom, and as
## little sideways as brings its width in (opened()). Another rule than
## reveal()'s, and meant so: a desk is moved into view, a zone is opened at
## its sign. _process() clamps the pan to the map on the next frame.
func open_on(opening: Rect2) -> void:
	pan = opened(pan, opening, free_rect().size)


## Whether `bounds` fits a view of `room`, REVEAL_HEADROOM above it included.
static func fits(bounds: Rect2, room: Vector2) -> bool:
	return bounds.size.x <= room.x and bounds.size.y + REVEAL_HEADROOM <= room.y


## What reveal() brings into a view of `room`: `bounds` and `beside` together
## when `beside` has an area and the two fit (fits()), else `bounds` alone.
static func framing(bounds: Rect2, beside: Rect2, room: Vector2) -> Rect2:
	if not beside.has_area():
		return bounds
	var both := bounds.merge(beside)
	return both if fits(both, room) else bounds


## The pan that, from `from`, moves a view of `room` just enough to hold
## `bounds` with REVEAL_HEADROOM above it; where they cannot both fit, its
## top-left wins. Not clamped to any map.
static func revealed(from: Vector2, bounds: Rect2, room: Vector2) -> Vector2:
	var rect := bounds.grow_side(SIDE_TOP, REVEAL_HEADROOM)
	return Vector2(
		minf(maxf(from.x, rect.end.x - room.x), rect.position.x),
		minf(maxf(from.y, rect.end.y - room.y), rect.position.y)
	)


## The pan that, from `from`, opens a view of `room` on `opening`: its top at
## the view's top whatever `from` was, and as little sideways as brings its
## width in, or its left edge when it is wider than the view. Not clamped to
## any map.
static func opened(from: Vector2, opening: Rect2, room: Vector2) -> Vector2:
	var left := opening.position.x
	if opening.size.x > room.x:
		return Vector2(left, opening.position.y)
	return Vector2(minf(maxf(from.x, opening.end.x - room.x), left), opening.position.y)
