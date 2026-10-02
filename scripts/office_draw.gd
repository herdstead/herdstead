class_name OfficeDraw
extends RefCounted
## Drawing primitives shared by the mock showroom and the live office.
## Everything here speaks semantic IDs; nothing here knows about herdr.

const TABLE_SCENE := preload("res://scenes/world/table.tscn")
const DECOR_SCENE := preload("res://scenes/world/decor.tscn")
const STATION_SCENE := preload("res://scenes/world/station.tscn")
const PERSON_SCENE := preload("res://scenes/people/pixel_person.tscn")
## A tab's name on the floor under its table (tab_label()): the display face's
## own size, and the band it stands in.
const TAB_LABEL_PIXELS := 8
const TAB_LABEL_HEIGHT := 8.0
## The size the world's small labels draw the display face at (style_display()).
const DISPLAY_PIXELS := 8

var art: ArtPack
## The bundled face keeps Latin text consistent across platforms. System CJK
## fonts fill missing glyphs without replacing the pack's Latin typography.
var font: Font
## The pack's display face (ArtPack.display_font, a pixel font drawn at its
## native 8) for the small world labels: the name plates, the chip's wait, the
## lens line and the zone signs. The same system fallbacks fill glyphs it lacks
## (an agent's name may be anything), and never make a row taller than the
## pixel face's own (no_taller()). A pack without one uses `font`.
var display: Font
## `display` for the tab labels: its line cut to TAB_LABEL_HEIGHT at
## TAB_LABEL_PIXELS by giving up descent rows below it (Tiny5 at 8 is 9 tall:
## ascent 7, descent 2), so a label's box ends where its band says. A tab label
## is upper case: the rows given up are empty.
var tab_face: Font


func _init(pack: ArtPack) -> void:
	art = pack
	var system := SystemFont.new()
	# Family candidates, not file paths, for Chinese and other missing glyphs.
	system.font_names = PackedStringArray(
		[
			"Noto Sans CJK SC",
			"Hiragino Sans GB",
			"Microsoft YaHei",
			"Arial",
			"DejaVu Sans",
			"sans-serif",
		]
	)
	var readable := FontVariation.new()
	readable.base_font = art.font
	var text_server := TextServerManager.get_primary_interface()
	readable.variation_opentype = {text_server.name_to_tag("wght"): 500.0, text_server.name_to_tag("opsz"): 10.0}
	readable.fallbacks = [system]
	font = readable
	display = readable
	var chain: Font = readable
	if art.display_font != null:
		var small := FontVariation.new()
		small.base_font = art.display_font
		small.fallbacks = [system]
		chain = small
		display = no_taller(small, art.display_font, DISPLAY_PIXELS)
	var cut := FontVariation.new()
	cut.base_font = chain
	cut.spacing_bottom = mini(0, int(TAB_LABEL_HEIGHT) - ceili(chain.get_height(TAB_LABEL_PIXELS)))
	tab_face = cut


## `face` (a face and its fallbacks) at `pixels`, its row no taller than `own`'s
## (the face without its fallbacks). Godot sizes a row by the tallest font in
## the chain, used or not: Linux's Noto Sans CJK is 13 tall at 8 where the pixel
## face is 9 (macOS's Hiragino is not taller, so it never shows there), and a
## name plate or a zone sign grew out of its box. The rows given up are below
## the baseline, so the baseline stays where the face's own puts it; a top
## spacing would lift the text by as much.
static func no_taller(face: FontVariation, own: Font, pixels: int) -> FontVariation:
	var extra := ceili(face.get_height(pixels)) - ceili(own.get_height(pixels))
	if extra <= 0:
		return face
	var fitted: FontVariation = face.duplicate()
	fitted.spacing_bottom -= extra
	return fitted


func box(parent: Node, bounds: Rect2, color_key: StringName) -> ColorRect:
	var rectangle := ColorRect.new()
	rectangle.position = bounds.position
	rectangle.size = bounds.size
	rectangle.color = art.color(color_key)
	rectangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rectangle)
	return rectangle


## The pack's look for a label: font, size, colour, alignment. Used for new
## labels and for the fixed ones inside the world prefabs.
func style(
	target: Label,
	pixels: int = 10,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	target.horizontal_alignment = align
	target.add_theme_font_override("font", font)
	target.add_theme_font_size_override("font_size", pixels)
	target.add_theme_color_override("font_color", art.color(color_key))
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The same, in the display face (`display`): the world's small labels.
func style_display(
	target: Label,
	pixels: int = DISPLAY_PIXELS,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	style(target, pixels, color_key, align)
	target.add_theme_font_override("font", display)


func label(
	parent: Node,
	text: String,
	at: Vector2,
	size: Vector2,
	pixels: int = 10,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.size = size
	style(result, pixels, color_key, align)
	parent.add_child(result)
	return result


## Same as label(), but a long name is cut with an ellipsis instead of spilling
## past the sign or the inspector panel.
func clipped(
	parent: Node,
	text: String,
	at: Vector2,
	size: Vector2,
	pixels: int = 10,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var result := label(parent, text, at, size, pixels, color_key, align)
	result.clip_text = true
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Control.size clamps to the minimum size, which only drops to zero once
	# clipping is on, so the requested box has to be applied again here.
	result.size = size
	return result


## A tab's name under its table: the pack's display face (a pixel font) at
## TAB_LABEL_PIXELS, its line cut to TAB_LABEL_HEIGHT (tab_face), centred in `width` from `at` (the left end of the line it
## stands on, on the floor), TAB_LABEL_HEIGHT deep, cut with a forced ellipsis:
## even a narrow table signals truncation (Godot's ordinary ellipsis mode
## suppresses the mark when fewer than six characters fit).
func tab_label(parent: Node, at: Vector2, width: float) -> Label:
	var result := clipped(
		parent, "", at, Vector2(width, TAB_LABEL_HEIGHT), TAB_LABEL_PIXELS, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER
	)
	result.add_theme_font_override("font", tab_face)
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE
	result.size = Vector2(width, TAB_LABEL_HEIGHT)
	return result


## A prop of the pack, placed by its own foot.
func prop(parent: Node, id: StringName, at: Vector2) -> Sprite2D:
	return _place(parent, art.prop_sprite(id), at)


## A UI image of the pack drawn in the world: a state badge, a branch mark.
func icon(parent: Node, id: StringName, at: Vector2) -> Sprite2D:
	return _place(parent, art.ui_sprite(id), at)


func _place(parent: Node, spec: ArtSprite, at: Vector2) -> Sprite2D:
	var result := art.sprite(spec)
	result.position = at
	parent.add_child(result)
	return result


## Laid out in texture pixels and scaled back, so the corners keep the art's
## own pixels instead of stretching a finer texture over density-1 margins.
func panel(parent: Node, bounds: Rect2) -> void:
	var result := NinePatchRect.new()
	dress_panel(result, bounds.size)
	result.position = bounds.position
	parent.add_child(result)


## Dress `target` as the pack's panel, `size` units big, the same way panel()
## draws a new one: for a panel a scene already has (the chip's frame).
func dress_panel(target: NinePatchRect, size: Vector2) -> void:
	var spec := art.panel()
	target.texture = art.sprite_texture(spec)
	target.texture_filter = art.filter
	target.size = size * art.density
	target.scale = art.unit_scale()
	target.patch_margin_left = spec.patch_left * art.density
	target.patch_margin_top = spec.patch_top * art.density
	target.patch_margin_right = spec.patch_right * art.density
	target.patch_margin_bottom = spec.patch_bottom * art.density


func layer(parent: Node, at: Vector2) -> TileMapLayer:
	var result := TileMapLayer.new()
	result.tile_set = art.tileset()
	# TileMap's cell centers are at +16,+16; at is the top-left of cell 0.
	result.position = at
	# The tile set is `density` pixels per unit; cells land on the unit grid again.
	result.scale = art.unit_scale()
	result.texture_filter = art.filter
	parent.add_child(result)
	return result


## A pod of desks (OfficeTable) in `sorted` (a floor's y-sorted root) with the
## left end of its near edge at `near_left`, seat columns at `columns` along that edge, and
## its seats' contact shadows in `ground`. Null when the width is refused.
## `id` names the table node, and its stations after it.
func table(sorted: Node2D, ground: Node2D, id: String, near_left: Vector2, width: float, columns: Array) -> OfficeTable:
	var result: OfficeTable = TABLE_SCENE.instantiate()
	if not result.setup(art, width, columns):
		result.free()
		return null
	result.name = id
	result.position = near_left
	sorted.add_child(result)
	result.contact_shadows(ground)
	return result


## A piece of standing furniture in `sorted` (a floor's y-sorted root), with
## `at` the point where it meets the floor. Null when the prefab refuses it.
func decor(sorted: Node2D, id: StringName, at: Vector2) -> OfficeDecor:
	var result: OfficeDecor = DECOR_SCENE.instantiate()
	if not result.setup(art, id):
		result.free()
		return null
	result.position = at
	sorted.add_child(result, true)
	return result


## A vacant station on `at_table`'s seat for `column` on `side`, in the same
## sorted root. Seat it with furnish().
func station(sorted: Node2D, at_table: OfficeTable, column: int, side: String) -> OfficeStation:
	var result: OfficeStation = STATION_SCENE.instantiate()
	result.setup(self, at_table, column, side)
	result.name = "%s%s%d" % [at_table.name, side.capitalize(), column]
	sorted.add_child(result)
	result.vacate()
	return result


## A standing, front-facing person shown as a portrait at `at`, `zoom` times
## their world size, inside a holder node that carries the zoom (a physics body
## is never scaled itself). `zoom` is a whole number: the pixel people are one
## texture pixel per unit and are never sampled at a fraction of that. Not part
## of any floor: their feet do not collide.
func portrait(
	parent: Node, provider: String, animation: StringName, at: Vector2, zoom := 1, look: AvatarLook = null
) -> PixelPerson:
	var holder := Node2D.new()
	holder.position = at
	holder.scale = Vector2.ONE * zoom
	parent.add_child(holder)
	var person: PixelPerson = PERSON_SCENE.instantiate()
	var wanted := AvatarLook.facing(AvatarLook.STAND, AvatarLook.FRONT)
	wanted.override_with(look)
	person.configure(art.people, provider, wanted)
	var feet: CollisionShape2D = person.get_node("Feet")
	feet.disabled = true
	holder.add_child(person)
	person.play_state(animation)
	return person
