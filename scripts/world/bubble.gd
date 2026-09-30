class_name OfficeBubble
extends Node2D
## The chip over a blocked agent: scenes/world/bubble.tscn, in the station's
## Overlay (OfficeStation.BUBBLE_AT), on the tag row where the badge is.
##
## What reads at a glance about the one wait at this seat: a 30 by 16 `panel`
## frame, the seat's own badge in its left half (the station moves the same
## Badge node there while the frame is drawn, pulse and all) and how long the
## agent has waited in its right half, in the in-world compact form
## (OfficeAttention.compact_duration(): `59s`, `12m`, `3h`, `4d`; never `+`).
## With no wait to tell (a start this machine never saw, a machine that
## dropped) nothing of it is drawn, frame included: an empty frame reads as a
## blank chip. Only the raised hand and the badge, centred again, are left, and
## the chip's click and hover rectangle (the station's) stays where it is, over
## the badge. What the agent asks is not written here. Hovering the chip shows
## the excerpt in a HUD tooltip (the office's), and the card shows the whole
## question. Nothing here answers the agent: there is no button and no key, and
## a click on the chip is the station's (its `Target/Bubble` shape), which only
## picks the pane and opens answer mode on the card.
##
## Every node is the scene's; data only changes their properties. Nothing is
## laid out left of BADGE_SLOT: the badge is drawn there, above the chip.

## The frame was drawn or hidden (framed()): the station moves the badge into
## the chip's left half, or back to the middle of the tag row.
signal framed_changed(framed: bool)

const SIZE := Vector2(30, 16)
## The chip's left half, where the station draws the badge while the frame is
## drawn (a unit over the chip's left edge); the wait is written right of it.
const BADGE_SLOT := 15.0
## The wait's type size: the pack's display face at its native 8.
const WAIT_PIXELS := 8
## Where the wait is written: the chip's right half (the scene's %Wait), 14
## wide and 12 tall for the face's 9. The widest form (`99m`, a 14-unit
## advance) inks 13 units, and the frame's one-unit right border starts at 29:
## from 15 on, a unit of daylight stays before the border, and the badge,
## moved one unit past the chip's left edge (OfficeStation.CHIP_BADGE_SHIFT),
## leaves daylight before the first digit. Positions snap to whole units, and
## flush with either edge a digit merged into the badge's outline or the `m`
## into the border (seen in the captures).
const WAIT_RECT := Rect2(15, 2, 14, 12)

## The last wait show_wait() was told, below 0 for none.
var _seconds := -1.0
## The lens is held (set_lensed()): nothing of the chip is drawn.
var _lensed := false
## Whether the frame is drawn now (framed()).
var _framed := false


## Dress the frame and the wait in `pen`'s pack.
func dress(pen: OfficeDraw) -> void:
	var frame: NinePatchRect = %Frame
	pen.dress_panel(frame, SIZE)
	var wait: Label = %Wait
	pen.style_display(wait, WAIT_PIXELS, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	# The box again once the face is on: a Label is 23 tall before it.
	wait.position = WAIT_RECT.position
	wait.size = WAIT_RECT.size


## Say nothing: the chip is hidden (its agent is not blocked, or the seat is
## vacant), and a chip shown again is drawn afresh, as a rebuilt one is.
func clear() -> void:
	show_wait(-1.0)


## How long the agent has waited, `seconds`; below 0 when that is not known
## (a start this machine never saw) or not to be said (the machine dropped):
## then no number and no frame at all.
func show_wait(seconds: float) -> void:
	_seconds = seconds
	_apply()


## While the lens is held (`on`) the wait is the lens line's (OfficeStation's
## `Overlay/Lens`), said once: the chip draws nothing, frame included. The
## chip itself stays shown, so the seat is still a blocked one (its click and
## hover rectangle, the question reader). Let go, it is drawn as before.
func set_lensed(on: bool) -> void:
	if on == _lensed:
		return
	_lensed = on
	_apply()


## Whether the frame (and the wait in it) is drawn now: a wait is known, the
## lens is not held, and the chip is shown.
func framed() -> bool:
	return _framed


## Show the parts only while there is a wait to tell and the lens is not held;
## the number follows the wait either way.
func _apply() -> void:
	var drawn := _seconds >= 0.0 and not _lensed
	var frame: NinePatchRect = %Frame
	frame.visible = drawn
	var wait: Label = %Wait
	var text := OfficeAttention.compact_duration(_seconds, false)
	if wait.text != text:
		wait.text = text
	# The number is inside the frame; hidden with it.
	wait.visible = drawn
	# Out of the tree the face is not on yet and a Label keeps the default
	# font's 23-unit height; in it, the box is the slot's again.
	if wait.size != WAIT_RECT.size:
		wait.size = WAIT_RECT.size
	if drawn != _framed:
		_framed = drawn
		framed_changed.emit(drawn)
