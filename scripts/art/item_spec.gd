class_name ItemSpec
extends RefCounted
## An item's own facts, from its pack entry's optional `item` block (docs/ITEMS.md):
## what it stands on, how much of it, whether people walk round it, and which
## pool a place draws it from. Read once by ArtPack.from_manifest(); a prop
## without the block is placed by code by its id (door, window, sign...).
##
## Size is not here: an item's size is its drawing (the canvas and what
## tools/build_assets.py measures of its pixels), never scaled (invariant 6).

## A table's working plane, the floor, a row's back wall.
const PLACE_DESK := &"desk"
const PLACE_FLOOR := &"floor"
const PLACE_WALL := &"wall"
const PLACES: Array[StringName] = [PLACE_DESK, PLACE_FLOOR, PLACE_WALL]
## The keys an `item` block may hold; any other is refused (a misspelling must
## not read as an absent key).
const KEYS: Array[String] = ["place", "footprint", "blocks", "group", "weight"]

var place := &""
## Units at the foot point: `x` centred on the pivot, `y` back from it. Zero
## for a wall item.
var footprint := Vector2.ZERO
## People walk round it: a floor item's collider and walk obstacle. Every floor
## item blocks for now (`"blocks": false` is refused until the walk graph can
## let a person over one).
var blocks := false
## The pool a place draws it from (ArtPack.items_in()); empty = placed by code
## by id only, never drawn at random (a signal, a fixture).
var group := &""
## Whole-number odds within its group; 0 = never drawn.
var weight := 1
