class_name PixelPortrait
extends Node2D
## One portrait: scenes/people/pixel_portrait.tscn, the seat's person as a
## head-and-shoulders picture for the HUD (the agent card's and the tall top
## bar's tiles'). The origin is the portrait's bottom centre.
##
## Nine layer sprites (Top, Head, Face, Brows, Marks, Neckwear, Glasses, Hair,
## Headwear, bottom to top; PixelPortraits.SPRITES) each show one cell of the
## PixelPortraits sheet, or nothing when the look draws nothing there (a null
## texture: no draw call). All nine are regions of the one sheet, so they batch
## into one draw call. A new look only swaps textures on the same nodes; none is
## made or freed after the scene loads. A still: no AnimationPlayer, and state
## never takes part (the HUD's frame round it says the state).

## The herdr provider as asked for (may be unknown to the catalog).
var provider := ""
## The look shown: the seat's person and the portrait's extras; null before the
## first show_look().
var look: PortraitLook


## Show `wanted` from `family`: every layer's cell through the family's dress()
## (its pivot, scaled back by its density, sampled as it is), on the same
## sprites.
func show_look(family: PixelPortraits, wanted: PortraitLook) -> void:
	look = wanted
	for layer in PixelPortraits.LAYERS:
		family.dress(sprite_of(layer), family.part_texture(layer, wanted), family.pivot)


## The sprite that shows `layer` (one of PixelPortraits.LAYERS).
func sprite_of(layer: StringName) -> Sprite2D:
	return get_node(PixelPortraits.SPRITES[layer])
