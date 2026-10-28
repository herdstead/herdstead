class_name OfficeDraw
extends RefCounted
## Drawing primitives shared by the mock showroom and the live office.
## Everything here speaks semantic IDs; nothing here knows about herdr.

const TABLE_SCENE := preload("res://scenes/world/table.tscn")
const DECOR_SCENE := preload("res://scenes/world/decor.tscn")
const STATION_SCENE := preload("res://scenes/world/station.tscn")
const PERSON_SCENE := preload("res://scenes/people/pixel_person.tscn")
const PORTRAIT_SCENE := preload("res://scenes/people/pixel_portrait.tscn")
## A tab's name on the floor under its table (tab_label()): the display face's
## own size, and the band it stands in.
const TAB_LABEL_PIXELS := 8
const TAB_LABEL_HEIGHT := 8.0
## The native sizes of the pack's three cuts (ArtPack.display_font, font,
## heading_font): a pixel font is drawn at its own size or a whole multiple of
## it, never between (cut_for()). The world's small labels are the display cut
## at its own size (style_display()).
const DISPLAY_PIXELS := 8
const TEXT_PIXELS := 10
const HEADING_PIXELS := 12
## The native size of the pack's figures face (ArtPack.figures_font, style_figures()).
const FIGURES_PIXELS := 8
## What tab_cut() measures a face's capitals by: upper case and digits, the
## letters a tab's name is written in.
const CAPITALS := "ABCXYZ09"
## How far a seat's tag (back_label()) reaches past its text on either side, in units.
const TAG_PAD := 1.0
## A seat's name plate's row, in units (plate_cut()): the display face's 12
## less two rows its glyphs never ink, so a near plate stands 2 clear of its
## pod's tab label and of a zone's lower partition (S3 SEATTAGS round 2).
const PLATE_HEIGHT := 10.0
## What plate_cut() measures a face's ink by: capitals, digits, the letters
## that reach down, and the brackets a pane's name may hold.
const PLATE_INKS := "ABCXYZ09bdfghjklpqy[]|"

var art: ArtPack
## The pack's text cut (ArtPack.font, a pixel font at its native 10) over its
## fallbacks: a glyph the text cut lacks comes from the pack's own small cut
## first (its `‹ ›`, at that cut's smaller row), and only then from a platform
## font (CJK the cuts lack, emoji), whose own row height would come with it.
## The chain every face is made from (face_for(), HudTheme.build()); a label
## wears it cut (face_at()): the small cut is 16 tall at 10, where the text
## cut is 14, and Godot sizes a row by the tallest font in the chain.
var font: Font
## The pack's display face (ArtPack.display_font, a pixel font drawn at its
## native 8) for the small world labels: the name plates and the zone signs
## (the chip's wait and the lens line wear `figures`). The same system fallbacks fill glyphs it lacks
## (an agent's name may be anything), and never make a row taller than the
## pixel face's own (no_taller()). A pack without one uses `font`.
var display: Font
## The pack's heading cut (ArtPack.heading_font, at its native 12) over the
## same fallbacks, its row no taller than its own; a pack without one uses `font`.
var heading: Font
## The pack's figures face (ArtPack.figures_font, Tiny5 at its native 8) for the
## compact durations alone: the chip's wait and the lens line (`99m`, `99m+`,
## `4s+`, OfficeAttention.compact_duration()). Its digits are 4 wide, the
## display cut's 5: `99m` is 14 units in it and 16 in the display cut, and a
## chip at the 32-unit seat pitch has 14 (WORLD_MODEL, "Rows over a seat").
## The same platform fallbacks behind it, its row no taller than its own. A
## pack without one uses `display`.
var figures: Font
## `display` for the tab labels: its line cut to TAB_LABEL_HEIGHT at
## TAB_LABEL_PIXELS (tab_cut()), so a label's box ends where its band says
## and its capitals stand at the band's foot.
var tab_face: Font
## `display` for the seats' name plates: its line cut to PLATE_HEIGHT
## (plate_cut()), the rows it gives up being rows no glyph inks.
var plate_face: Font
## `font` at TEXT_PIXELS, its row no taller than the text cut's own.
var _body: Font
## The `paper` tag behind a seat's plate and lens line (back_label()), shared,
## and what an empty one wears instead (hug()), so no sliver of paper shows.
var _tag: StyleBoxFlat
var _no_tag := StyleBoxEmpty.new()


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
	readable.fallbacks = [art.display_font, system] if art.display_font != null else [system]
	font = readable
	_body = face_for(art, TEXT_PIXELS, readable)
	display = face_for(art, DISPLAY_PIXELS, readable) if art.display_font != null else readable
	heading = face_for(art, HEADING_PIXELS, readable) if art.heading_font != null else readable
	figures = display
	if art.figures_font != null:
		var numbers := FontVariation.new()
		numbers.base_font = art.figures_font
		numbers.fallbacks = [system]
		figures = no_taller(numbers, art.figures_font, FIGURES_PIXELS)
	var chain: Font = readable
	if art.display_font != null:
		var small := FontVariation.new()
		small.base_font = art.display_font
		small.fallbacks = [system]
		chain = small
	tab_face = tab_cut(chain, art.display_font if art.display_font != null else art.font)
	plate_face = plate_cut(display, art.display_font if art.display_font != null else art.font)


## The pack's own cut drawn at `pixels`, or null when it has none for that
## size: the one place a size picks its face. A multiple of DISPLAY_PIXELS
## (8, 16, 24) is the display cut, of TEXT_PIXELS (10, 20) the text cut, of
## HEADING_PIXELS (12) the heading cut. Any other size (9, 13) is no size of
## the pack's: it is an error, and the answer is the text cut.
static func cut_for(pack: ArtPack, pixels: int) -> Font:
	if pixels > 0 and pixels % DISPLAY_PIXELS == 0:
		return pack.display_font
	if pixels > 0 and pixels % TEXT_PIXELS == 0:
		return pack.font
	if pixels > 0 and pixels % HEADING_PIXELS == 0:
		return pack.heading_font
	push_error("No cut of pack %s is drawn at %d: sizes are whole multiples of 8, 10 or 12" % [pack.id, pixels])
	return pack.font


## The size a label asked to be `pixels` is written at: that size when the pack
## has a cut for it (cut_for()), the text cut's own TEXT_PIXELS otherwise (a
## pack without a heading cut writes its headings at the body's size).
static func size_for(pack: ArtPack, pixels: int) -> int:
	return pixels if cut_for(pack, pixels) != null else TEXT_PIXELS


## The face a label at `pixels` wears: the cut for that size (cut_for()) in
## front of `chain`'s fallbacks (`chain` is the text cut over its fallbacks,
## `font`) less the pack's own cuts, its row no taller than the cut's own
## (no_taller()). The text cut, or a size the pack has no cut for, is `chain`
## itself, cut the same way. Only the text chain falls back to another cut
## (the small cut's `‹ ›`, which the HUD's buttons write at 10): a cut drawn
## off its own size is taller than the cut in front of it (the small cut is 19
## at 12, three rows over the heading cut's 16), and an odd surplus cannot be
## cut without moving the text half a unit (no_taller()).
static func face_for(pack: ArtPack, pixels: int, chain: Font) -> Font:
	var cut := cut_for(pack, pixels)
	var base: Font = (chain as FontVariation).base_font if chain is FontVariation else chain
	if cut == null or cut == base:
		return no_taller(chain, base, pixels)
	var worn := FontVariation.new()
	worn.base_font = cut
	var cuts: Array[Font] = [pack.font, pack.display_font, pack.heading_font]
	var fallbacks: Array[Font] = []
	for fallback: Font in chain.fallbacks:
		if fallback not in cuts:
			fallbacks.append(fallback)
	worn.fallbacks = fallbacks
	return no_taller(worn, cut, pixels)


## `chain` (a face and its fallbacks) for the tab labels: its line cut to
## TAB_LABEL_HEIGHT at TAB_LABEL_PIXELS from the rows of `own` (the face
## without its fallbacks) that no capital or digit inks: the empty rows under
## the capitals go first (ink_rows() of CAPITALS), then rows over them, so the
## capitals stand at the band's foot and its spare rows are on top, where a
## selected station's frame lies over the band (its bottom edge covers the
## band's top two rows). Every capital's row stays in the band; a descender,
## or a Chinese glyph's row at the baseline, may fall under it. No taller for
## the fallbacks either (no_taller()): the text stands where `own`, cut the
## same, puts it.
static func tab_cut(chain: Font, own: Font) -> Font:
	var surplus := maxi(0, ceili(own.get_height(TAB_LABEL_PIXELS)) - int(TAB_LABEL_HEIGHT))
	var inked := ink_rows(own, CAPITALS, TAB_LABEL_PIXELS)
	var empty := maxi(0, ceili(own.get_descent(TAB_LABEL_PIXELS)) - inked.y - 1)
	var below := mini(surplus, empty)
	var cut := FontVariation.new()
	cut.base_font = chain
	cut.spacing_top = below - surplus
	cut.spacing_bottom = -below
	var alone := FontVariation.new()
	alone.base_font = own
	alone.spacing_top = cut.spacing_top
	alone.spacing_bottom = cut.spacing_bottom
	return no_taller(cut, alone, TAB_LABEL_PIXELS)


## `face` (`display`) for the seats' name plates: its line at DISPLAY_PIXELS
## cut to PLATE_HEIGHT from the rows of `own` (the face without its fallbacks)
## that none of PLATE_INKS inks, one at a time from whichever side has more of
## them left, so the ink keeps as many empty rows over it as under it. The
## display face at 8 (12 rows, ink from 6 over the baseline to 1 under it)
## gives up two of its three empty rows over the capitals and keeps one either
## side. No taller for the fallbacks either (no_taller()).
static func plate_cut(face: Font, own: Font) -> Font:
	var surplus := maxi(0, ceili(own.get_height(DISPLAY_PIXELS)) - int(PLATE_HEIGHT))
	var inked := ink_rows(own, PLATE_INKS, DISPLAY_PIXELS)
	var empty_above := maxi(0, ceili(own.get_ascent(DISPLAY_PIXELS)) + inked.x)
	var empty_below := maxi(0, ceili(own.get_descent(DISPLAY_PIXELS)) - inked.y - 1)
	var above := 0
	var below := 0
	for _row in surplus:
		if empty_above - above >= empty_below - below:
			above += 1
		else:
			below += 1
	var cut: FontVariation = face.duplicate() if face is FontVariation else FontVariation.new()
	if face is not FontVariation:
		cut.base_font = face
	cut.spacing_top -= above
	cut.spacing_bottom -= below
	var alone := FontVariation.new()
	alone.base_font = own
	alone.spacing_top = -above
	alone.spacing_bottom = -below
	return no_taller(cut, alone, DISPLAY_PIXELS)


## The first and last rows `text` inks in `own` at `pixels`, relative to the
## baseline (a row above it is negative; Vector2i(0, -1) when nothing inks):
## read from the glyphs the text server rasterised, as they will be drawn.
static func ink_rows(own: Font, text: String, pixels: int) -> Vector2i:
	var server := TextServerManager.get_primary_interface()
	var line := TextLine.new()
	line.add_string(text, own, pixels)
	var size := Vector2i(pixels, 0)
	var top := 0
	var bottom := -1
	var inked := false
	for glyph: Dictionary in server.shaped_text_get_glyphs(line.get_rid()):
		var rid: RID = glyph["font_rid"]
		var index: int = glyph["index"]
		var page := server.font_get_glyph_texture_idx(rid, size, index)
		if page < 0:
			continue
		var image := server.font_get_texture_image(rid, size, page)
		var uv := Rect2i(server.font_get_glyph_uv_rect(rid, size, index))
		var offset := int(server.font_get_glyph_offset(rid, size, index).y)
		for y in uv.size.y:
			for x in uv.size.x:
				if image.get_pixel(uv.position.x + x, uv.position.y + y).a < 0.5:
					continue
				top = mini(top, offset + y) if inked else offset + y
				bottom = maxi(bottom, offset + y) if inked else offset + y
				inked = true
	return Vector2i(top, bottom)


## `face` (a face and its fallbacks) at `pixels`, its row no taller than `own`'s
## (the face without its fallbacks) and its text where `own` puts it: the one
## rule for the world's labels and the HUD's (HudTheme). Godot sizes a row by
## the tallest font in the chain, used or not: Linux's Noto Sans CJK is 13 tall
## at 8 where the pixel face is 9 (macOS's Hiragino is not taller, so it never
## shows there), and a name plate or a zone sign grew out of its box.
## A Label stands the shaped line in the middle of its row (measured in
## pixels): rows cut only above the baseline lift the text by half of them,
## only below lower it by as much. So the surplus is cut half above and half
## below, an odd row above (the text is then half a unit high, toward the room
## capitals leave over them, never nearer the row's lower edge). A descent
## cannot go below nothing: once the rows below would be more than `own`'s
## descent, as many rows as that descent go above and the rest below, which
## is where the text is in its place again.
## A FontVariation is copied, keeping its own axes (a heading's weight) and
## spacing; wrapping it in another one would lose them.
static func no_taller(face: Font, own: Font, pixels: int) -> Font:
	var extra := ceili(face.get_height(pixels)) - ceili(own.get_height(pixels))
	if extra <= 0:
		return face
	var fitted: FontVariation = face.duplicate() if face is FontVariation else FontVariation.new()
	if face is not FontVariation:
		fitted.base_font = face
	var above := mini(ceili(extra / 2.0), maxi(0, floori(own.get_descent(pixels))))
	fitted.spacing_top -= above
	fitted.spacing_bottom -= extra - above
	return fitted


func box(parent: Node, bounds: Rect2, color_key: StringName) -> ColorRect:
	var rectangle := ColorRect.new()
	rectangle.position = bounds.position
	rectangle.size = bounds.size
	rectangle.color = art.color(color_key)
	rectangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rectangle)
	return rectangle


## The face a label at `pixels` wears: the pen's own chains at the three
## native sizes (`display`, `font` cut to its row, `heading`), face_for() over
## `font` at any other multiple (16, 20, 24).
func face_at(pixels: int) -> Font:
	if pixels == TEXT_PIXELS:
		return _body
	if pixels == DISPLAY_PIXELS and art.display_font != null:
		return display
	if pixels == HEADING_PIXELS and art.heading_font != null:
		return heading
	return face_for(art, pixels, font)


## The pack's look for a label: font, size, colour, alignment. Used for new
## labels and for the fixed ones inside the world prefabs. The font is the cut
## drawn at `pixels` (face_for()).
func style(
	target: Label,
	pixels: int = 10,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	target.horizontal_alignment = align
	target.add_theme_font_override("font", face_at(pixels))
	target.add_theme_font_size_override("font_size", pixels)
	target.add_theme_color_override("font_color", art.color(color_key))
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE


## A seat's name plate: the display face at DISPLAY_PIXELS cut to its row
## (`plate_face`, plate_cut()), the size and colour as style() gives them.
func style_plate(target: Label, color_key: StringName = ArtContract.INK) -> void:
	style(target, DISPLAY_PIXELS, color_key, HORIZONTAL_ALIGNMENT_CENTER)
	target.add_theme_font_override("font", plate_face)


## The same, in the display face (`display`): the world's small labels.
func style_display(
	target: Label,
	pixels: int = DISPLAY_PIXELS,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	style(target, pixels, color_key, align)
	target.add_theme_font_override("font", display)


## A compact duration's label (the chip's wait, the lens line) in the figures
## face (`figures`), the size and colour as style() gives them.
func style_figures(
	target: Label,
	pixels: int = FIGURES_PIXELS,
	color_key: StringName = ArtContract.INK,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	style(target, pixels, color_key, align)
	target.add_theme_font_override("font", figures)


## Put a `paper` tag behind `target`'s ink words (its theme `normal`
## stylebox, so no node is added), so they read over any floor: the wood, a
## zone's carpet, a partition. Square, not anti-aliased, no margins of its
## own: hug() sizes the Label to its text. For the seat's plate and lens line
## (OfficeStation); the world's other labels keep no backing. An empty
## label wears no tag (hug()).
func back_label(target: Label) -> void:
	target.add_theme_stylebox_override("normal", _tag_for(target))


## The tag `target` wears for its text now: paper, or none when it says nothing.
func _tag_for(target: Label) -> StyleBox:
	if target.text.is_empty():
		return _no_tag
	return _paper_tag()


func _paper_tag() -> StyleBoxFlat:
	if _tag == null:
		_tag = StyleBoxFlat.new()
		_tag.bg_color = art.color(ArtContract.PAPER)
		_tag.anti_aliasing = false
	return _tag


## Lay `target` in its `row` hugging its text: centred in the row (or on x =
## `centre`, kept inside the row), as tall as the row, as wide as its text and
## TAG_PAD either side (none for no text), at most the row's width (a longer
## text is cut as the Label cuts it). Only what changed is written; the caller
## asks when the text or the row changes.
func hug(target: Label, row: Rect2, centre := NAN) -> void:
	var width := 0.0
	var tagged := _tag_for(target)
	if target.get_theme_stylebox("normal") != tagged:
		target.add_theme_stylebox_override("normal", tagged)
	if not target.text.is_empty():
		var face := target.get_theme_font("font")
		var pixels := target.get_theme_font_size("font_size")
		var wide := face.get_string_size(target.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
		width = minf(row.size.x, ceilf(wide) + 2.0 * TAG_PAD)
	var middle := row.get_center().x if is_nan(centre) else centre
	var at := Vector2(clampf(middle - width / 2.0, row.position.x, row.end.x - width), row.position.y)
	if target.position != at:
		target.position = at
	if target.size != Vector2(width, row.size.y):
		target.size = Vector2(width, row.size.y)


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


## A tab's name under its table, in `paper` on its zone's carpet: the pack's display face (a pixel font) at
## TAB_LABEL_PIXELS, its line cut to TAB_LABEL_HEIGHT (tab_face), centred in `width` from `at` (the left end of the line it
## stands on, on the floor), TAB_LABEL_HEIGHT deep, cut with a forced ellipsis:
## even a narrow table signals truncation (Godot's ordinary ellipsis mode
## suppresses the mark when fewer than six characters fit).
func tab_label(parent: Node, at: Vector2, width: float) -> Label:
	var result := clipped(
		parent,
		"",
		at,
		Vector2(width, TAB_LABEL_HEIGHT),
		TAB_LABEL_PIXELS,
		ArtContract.PAPER,
		HORIZONTAL_ALIGNMENT_CENTER
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
	dress_nine_patch(target, art.panel(), size)


## Dress `target` as the nine-patch UI image `spec`, `size` units big: laid
## out in texture pixels and scaled back, its margins the art's own pixels and
## only its middle stretched (the panel, a zone's carpet).
func dress_nine_patch(target: NinePatchRect, spec: ArtSprite, size: Vector2) -> void:
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


## The seat's person for pane `key`, standing and facing front, in `holder`:
## `actor` when there is one, else a new person, instanced once and kept (its
## feet disabled: no floor holds them). The same face and hair as at the seat
## (vary_by(key)), dressed in `pack`'s people as `provider`; re-dressing the same
## node is new textures, never a new person. The top bar's faces come from
## here.
static func seat_face(holder: Node2D, actor: PixelPerson, pack: ArtPack, provider: String, key: String) -> PixelPerson:
	var person := actor
	if person == null:
		person = PERSON_SCENE.instantiate()
		holder.add_child(person)
		var feet: CollisionShape2D = person.get_node("Feet")
		feet.disabled = true
	person.vary_by(key)
	person.configure(pack.people, provider, AvatarLook.facing(AvatarLook.STAND, AvatarLook.FRONT))
	return person


## The seat's person for pane `key` as a portrait (PixelPortrait), in `holder`
## at its bottom centre: `kept` when there is one, else a new one, instanced
## once and kept. The same person as at the seat by construction (the portraits
## resolve the look by the seat's own call, PixelPortraits.look_of()), plus the
## portrait's own extras for the pane; re-dressing the same node is new
## textures, never a new portrait. The agent card's portrait comes from here.
static func seat_portrait(
	holder: Node2D, kept: PixelPortrait, pack: ArtPack, provider: String, key: String
) -> PixelPortrait:
	var shown := kept
	if shown == null:
		shown = PORTRAIT_SCENE.instantiate()
		holder.add_child(shown)
	shown.provider = provider
	shown.show_look(pack.portraits, pack.portraits.look_of(provider, key))
	return shown


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
