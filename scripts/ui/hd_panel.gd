class_name HdPanel
extends PanelContainer
## A panel drawn from the art pack's nine-patch at the texture's own density.
##
## A StyleBoxTexture cannot be scaled, and the pack's panel is `density` pixels
## per unit, so drawing it through a plain theme stylebox would stretch a 4x
## texture over 1x margins and give a 4x-thick border. Instead the theme's
## stylebox for this type is a StyleBoxEmpty that carries nothing but the
## content margins (in units, so children sit where the art's frame ends), and
## the frame itself is drawn under a 1/density transform. No image is ever
## resized: the GPU minifies through the texture's mipmaps.
##
## The frame is drawn by a Node2D of its own, not by this Control: the pack's
## sampling is the frame's business, and a panel that imposed it on its whole
## subtree would have every label in it resampled too.


## Draws the pack's nine-patch over its parent panel. A Node2D, so the
## PanelContainer above never lays it out, and it draws behind the content.
class Frame:
	extends Node2D

	var panel: Control
	var density := 1
	var box: StyleBoxTexture

	func _draw() -> void:
		if box == null:
			return
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / float(density))
		draw_style_box(box, Rect2(Vector2.ZERO, panel.size * float(density)))


## The pack whose panel texture is drawn; null until dress() is called.
var art: ArtPack

var _frame: Frame


## MOUSE_FILTER_STOP stops a click over the panel, but Godot lets a mouse wheel
## keep travelling past it on purpose; a HUD panel has to accept the wheel, or
## the office pans under the viewer's cursor while they scroll a list.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()


func _init() -> void:
	# Theme items for this panel live under its own type, never PanelContainer's.
	theme_type_variation = &"HdPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = Frame.new()
	_frame.name = "PanelFrame"
	_frame.panel = self
	add_child(_frame)
	resized.connect(_frame.queue_redraw)


## Take the pack's panel texture, its nine-patch margins and its sampling.
## Called again on a theme switch; nothing in the tree is rebuilt for it.
func dress(pack: ArtPack) -> void:
	art = pack
	_frame.texture_filter = pack.filter
	_frame.density = pack.density
	var spec := pack.panel()
	var box := StyleBoxTexture.new()
	box.texture = pack.sprite_texture(spec)
	# Texture margins are texture pixels; the manifest names them in units.
	box.texture_margin_left = spec.patch_left * pack.density
	box.texture_margin_top = spec.patch_top * pack.density
	box.texture_margin_right = spec.patch_right * pack.density
	box.texture_margin_bottom = spec.patch_bottom * pack.density
	_frame.box = box
	_frame.queue_redraw()
