class_name ArtSprite
extends Resource
## One built image a scene reaches by semantic ID: a prop or a UI element.
##
## Every number here is in density-1 units, whatever density the family that
## holds it was built at; that family is the only multiplier.

var id := &""
## Where the image lives, relative to the family's base_path.
var path := ""
var size := Vector2i.ZERO
## The point the image is placed by: its foot, or its top-left corner.
var pivot := Vector2.ZERO
## Nine-patch margins in units, for the UI images that are stretched (the
## panel). All four are zero for an image that is drawn whole.
var patch_left := 0
var patch_top := 0
var patch_right := 0
var patch_bottom := 0


## Whether this image is stretched as a nine-patch rather than drawn whole.
func nine_patched() -> bool:
	return patch_left > 0 or patch_top > 0 or patch_right > 0 or patch_bottom > 0
