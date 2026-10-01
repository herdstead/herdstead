class_name OfficeEdgeArrow
extends Button
## One arrow on an edge of the world (OfficeEdgeArrows): which way a zone's
## off-screen blocked desks are (`→`), the zone's number as its sign writes it,
## and a blocked badge with their count. A click pans to the longest-waiting of
## them and selects nothing. On a narrow world (set_compact()) the number steps
## out: glyph, badge and count, the zone in the tooltip. The last arrow, when
## more zones wait than there are arrows, is a disabled `+N` note whose tooltip
## names them.
##
## Kept for the HUD's whole life and updated in place: a refresh or a pan only
## writes text, visibility and the badge's pulse. It is as wide as what it says
## (the scene's line and its insets), so the edge can place it.

## This arrow was pressed; `pane_key` is the desk to pan to.
signal picked(pane_key: String)

var _zone := ""
var _pane := ""
var _compact := false
## The `+N` note: a count of zones, not a way to one.
var _note := false


func _ready() -> void:
	pressed.connect(func() -> void: picked.emit(_pane))


## Take the pack's blocked badge. A theme switch calls this again and rebuilds nothing.
func dress(art: ArtPack) -> void:
	badge().show_badge(art, art.state(ArtContract.STATE_BLOCKED).badge)


## Point at `arrow`'s zone.
func show_arrow(arrow: EdgeArrowModel) -> void:
	_zone = arrow.zone_key
	_pane = arrow.pane_key
	_note = arrow.more > 0
	var glyph: Label = %Glyph
	var zone: Label = %Zone
	var count: Label = %Count
	var slot: Control = %IconSlot
	glyph.text = EdgeArrowModel.GLYPHS[arrow.edge]
	glyph.visible = not _note
	zone.text = arrow.number
	count.text = str(arrow.blocked)
	count.visible = not _note
	slot.visible = not _note
	if _note:
		badge().stop_pulsing()
	else:
		# A zone, not a seat: the pulse asks the machine, never a pane.
		badge().pulse_for(arrow.machine, "", ArtContract.STATE_BLOCKED)
	if tooltip_text != arrow.tip:
		tooltip_text = arrow.tip
	disabled = _note
	visible = true
	_fit()


## A hidden arrow stops pulsing, so nothing steps a badge nobody sees.
func hide_arrow() -> void:
	_zone = ""
	_pane = ""
	badge().stop_pulsing()
	visible = false


## Leave the zone's number to the tooltip (`on`), as a narrow world's arrows do.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	_fit()


## Whether the number is left to the tooltip (set_compact()).
func compact() -> bool:
	return _compact


## The zone this arrow points at; empty for the `+N` note and a hidden arrow.
func zone_key() -> String:
	return _zone


## The desk a click pans to; empty for the `+N` note and a hidden arrow.
func pane_key() -> String:
	return _pane


## The blocked badge, for the tests that follow the pulse.
func badge() -> StatusBadge:
	var slot: Control = %IconSlot
	return slot.get_node("Sprite")


## As wide as its line says now, with the scene's insets either side.
func _fit() -> void:
	var zone: Label = %Zone
	zone.visible = _note or not _compact
	var line: Control = %Line
	var wide := line.get_combined_minimum_size().x + line.offset_left - line.offset_right
	if custom_minimum_size.x != wide:
		custom_minimum_size = Vector2(wide, custom_minimum_size.y)
	reset_size()
