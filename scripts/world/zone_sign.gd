class_name OfficeZoneSign
extends Node2D
## A zone's sign (scenes/world/zone_sign.tscn): hung from the zone's top-left
## partition post, whose foot is its origin (ZonePlacement.sign_at), so it
## sorts with the post; it draws over the aisle row above the zone. It says the
## workspace's number (`3`, a mezzanine's `3A`) and its label, beside an accent
## stripe that a worktree group shares (accent_of()). Hovering it asks for the
## repository and the checkout (`hovered`); the office shows them in the bubble
## tooltip (OfficeQuestionTips.on_sign_hovered()).
##
## Display only: the text is written again on every reconcile from the zone's
## model, the plan only positions it, and nothing here reads or writes herdr.
## Its nodes are permanent: new text goes into the same Labels.
##
## The panel is as wide as what it says: PAD, the stripe, GAP, the number, GAP,
## the label, PAD; at most MAX_WIDTH and never past the limit it is given (the
## zone's right partition), the label cut with a forced ellipsis to fit. The
## hover area is the drawn panel.

## The pointer came onto the sign of zone `zone_key` (`inside`), or left it.
signal hovered(zone_key: String, inside: bool)

## Room inside the panel's ends, and between the stripe, the number and the label.
const PAD := 4.0
const GAP := 3.0
## The widest the panel is drawn, a long label cut to fit.
const MAX_WIDTH := 160.0

## The zone this sign names (ZoneModel.key).
var zone_key := ""
var _pen: OfficeDraw


## Which of the pack's accent colours (ArtContract.ACCENTS) a worktree group
## wears: picked from its source workspace's key alone, never from a state. The
## floor plate and the zone sign both ask here.
static func accent_of(group: String) -> int:
	return posmod(group.hash(), ArtContract.ACCENTS.size())


## Take the pack's panel, display face and colours.
func dress(pen: OfficeDraw) -> void:
	var panel: NinePatchRect = %Panel
	pen.dress_panel(panel, panel.size)
	var labels: Array[Label] = [%Number as Label, %Title as Label]
	for label in labels:
		pen.style(label, 8, ArtContract.INK)
		if pen.art.display_font != null:
			label.add_theme_font_override("font", pen.art.display_font)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE
	_pen = pen


## What the sign says about `zone`: its number, its label (a mezzanine its
## checkout), and its group's accent: the source workspace's key for a
## mezzanine, the zone's own otherwise. The panel's right end stays at or left
## of `limit` (in the sign's own coordinates).
func show_zone(zone: ZoneModel, limit := INF) -> void:
	zone_key = zone.key
	var mezzanine := not zone.mezzanine_of.is_empty()
	var number: Label = %Number
	number.text = zone.level_label if mezzanine and not zone.level_label.is_empty() else str(zone.number)
	var title: Label = %Title
	title.text = (zone.worktree if mezzanine and not zone.worktree.is_empty() else zone.label).to_upper()
	# As tall as the display face's line (9), once it applies: a Label sized
	# before its font is set keeps the default face's height.
	for label: Label in [number, title] as Array[Label]:
		var tall := label.get_minimum_size().y
		if label.size.y != tall:
			label.size = Vector2(label.size.x, tall)
	var accent: ColorRect = %Accent
	var key := ArtContract.ACCENTS[accent_of(zone.mezzanine_of if mezzanine else zone.key)]
	if _pen != null:
		accent.color = _pen.art.color(key)
	_fit(limit)


## Lay the stripe, the number and the label out from the panel's left end and
## end the panel (and the hover area) after what it says.
func _fit(limit: float) -> void:
	var panel: NinePatchRect = %Panel
	var accent: ColorRect = %Accent
	var number: Label = %Number
	var title: Label = %Title
	var left := panel.position.x
	var right := minf(left + MAX_WIDTH, limit)
	accent.position.x = left + PAD
	number.position.x = accent.position.x + accent.size.x + GAP
	number.size.x = _text_width(number)
	title.position.x = number.position.x + number.size.x + GAP
	var room := maxf(0.0, right - PAD - title.position.x)
	title.size.x = minf(_text_width(title), room)
	var end := title.position.x + title.size.x if title.size.x > 0.0 else number.position.x + number.size.x
	var width := end + PAD - left
	if _pen != null:
		_pen.dress_panel(panel, Vector2(width, panel.size.y * panel.scale.y))
	var shape: CollisionShape2D = %Shape
	var box := shape.shape as RectangleShape2D
	box.size = panel.size * panel.scale
	shape.position = panel.position + box.size / 2.0


## How wide `label`'s text is drawn in its own face and size.
static func _text_width(label: Label) -> float:
	if label.text.is_empty():
		return 0.0
	var face := label.get_theme_font("font")
	var pixels := label.get_theme_font_size("font_size")
	return ceilf(face.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x)


## The sign's drawing, in its parent's coordinates: what it covers over the aisle row.
func drawn_rect() -> Rect2:
	var panel: NinePatchRect = %Panel
	return Rect2(position + panel.position, panel.size * panel.scale)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		var hover: Area2D = %Hover
		hover.collision_layer = OfficeWorld.PICKABLE


func _on_hover_mouse_entered() -> void:
	hovered.emit(zone_key, true)


func _on_hover_mouse_exited() -> void:
	hovered.emit(zone_key, false)
