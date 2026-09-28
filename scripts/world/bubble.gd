class_name OfficeBubble
extends Node2D
## The bubble over a blocked agent's head: scenes/world/bubble.tscn, in the
## station's Overlay (OfficeStation.BUBBLE_AT).
##
## What reads at a glance, both about the one wait at this seat: how long it
## has waited, big enough to read (wait_text(), a compact form that fits), and a
## patience bar that shortens with the wait. Only the bar's length is a signal;
## its colour is always the pack's `blocked` (the accents are structure, never
## state, and the urgency of a long wait is the badge's `long` rhythm). With no
## wait to tell (a start this machine never saw, a machine that dropped) nothing
## of it is drawn, frame included: an empty frame reads as a blank speech
## bubble. Only the raised hand and the badge are left, and the bubble's click
## and hover rectangle (the station's) stays where it is, over the badge. What the agent
## asks is not written here: ten characters of it said nothing. Hovering the
## bubble shows the excerpt in a HUD tooltip (the office's), and the card shows
## the whole question. Nothing here answers the agent: there is no button and no
## key, and a click on the bubble is the station's (its `Target/Bubble` shape),
## which only picks the pane and opens answer mode on the card.
##
## Every node is the scene's; data only changes their properties. Nothing is
## laid out at x 48 and right of it: over a far seat the badge is drawn there,
## above the bubble (OfficeStation.BUBBLE_AT, x 48..64, y 13..28 here); the near
## side keeps the same layout so there is one bubble.

const SIZE := Vector2(60, 28)
## The wait's type size: larger than the plates' 10, the one thing to read here.
const WAIT_PIXELS := 14
## The bar is empty after this many seconds of waiting.
const PATIENCE_SECONDS := 600.0
## The bar's full width, in bubble units (the scene's %Track, x 4..44).
const TRACK_WIDTH := 40
## The fill never shrinks below this, so an old wait still shows a sliver.
const FILL_MIN := 2

## The last wait show_wait() was told, below 0 for none.
var _seconds := -1.0
## The lens is held (set_lensed()): nothing of the bubble is drawn.
var _lensed := false


## How full the patience bar is after `seconds` of waiting: 1 at the start,
## 0 at PATIENCE_SECONDS and after.
static func patience(seconds: float) -> float:
	return clampf(1.0 - seconds / PATIENCE_SECONDS, 0.0, 1.0)


## How wide the fill is after `seconds` of waiting, in bubble units.
static func fill_width(seconds: float) -> int:
	return maxi(FILL_MIN, roundi(TRACK_WIDTH * patience(seconds)))


## The wait in at most three characters, so it fits beside the badge at
## WAIT_PIXELS: under a minute `Ns`, under 100 minutes `Nm`, after that whole
## hours `Nh`. Empty below 0. The list row and the card keep
## OfficeAttention.format_duration().
static func wait_text(seconds: float) -> String:
	if seconds < 0.0:
		return ""
	if seconds < 60.0:
		return "%ds" % floori(seconds)
	if seconds < 6000.0:
		return "%dm" % floori(seconds / 60.0)
	return "%dh" % floori(seconds / 3600.0)


## Dress the frame, the wait and the bar in `pen`'s pack.
func dress(pen: OfficeDraw) -> void:
	var frame: NinePatchRect = %Frame
	pen.dress_panel(frame, SIZE)
	var wait: Label = %Wait
	pen.style(wait, WAIT_PIXELS, ArtContract.INK)
	var track: ColorRect = %Track
	var fill: ColorRect = %Fill
	track.color = pen.art.color(ArtContract.MUTED)
	fill.color = pen.art.color(ArtContract.BLOCKED)


## Say nothing: the bubble is hidden (its agent is not blocked, or the seat is
## vacant), and a bubble shown again is drawn afresh, as a rebuilt one is.
func clear() -> void:
	show_wait(-1.0)


## How long the agent has waited, `seconds`; below 0 when that is not known
## (a start this machine never saw) or not to be said (the machine dropped):
## then no number, no bar and no frame at all.
func show_wait(seconds: float) -> void:
	_seconds = seconds
	_apply()


## While the lens is held (`on`) the wait is the lens line's (OfficeStation's
## `Overlay/Lens`), said once: the bubble draws nothing, frame included. The
## bubble itself stays shown, so the seat is still a blocked one (its click and
## hover rectangle, the question reader). Let go, it is drawn as before.
func set_lensed(on: bool) -> void:
	if on == _lensed:
		return
	_lensed = on
	_apply()


## Show the parts only while there is a wait to tell and the lens is not held;
## the number and the bar's length follow the wait either way.
func _apply() -> void:
	var seconds := _seconds
	var known := seconds >= 0.0
	var drawn := known and not _lensed
	var frame: NinePatchRect = %Frame
	frame.visible = drawn
	var wait: Label = %Wait
	var text := wait_text(seconds)
	if wait.text != text:
		wait.text = text
	# The number is inside the frame; hidden with it.
	wait.visible = drawn
	var track: ColorRect = %Track
	var fill: ColorRect = %Fill
	track.visible = drawn
	fill.visible = drawn
	# Hidden, the fill is as the scene has it, so a bubble shown again is drawn
	# the way a rebuilt one is.
	var width := float(fill_width(seconds) if known else TRACK_WIDTH)
	if fill.size.x != width:
		fill.size = Vector2(width, fill.size.y)
