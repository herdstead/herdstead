class_name OfficeWorld
extends RefCounted
## The office world's depth and physics vocabulary, in one place.
##
## Depth comes only from y-sort: a world object's origin is where it touches the
## ground, and a larger y is nearer the viewer. Ground art is an earlier sibling
## of the sorted root, never a z value. The one exception is UI that floats over
## the world (name plates, state badges, selection marks, the table frame).

## The one draw layer above the y-sorted world; no other value is allowed.
const OVERLAY_Z := 10
## Physics layer bits (project.godot names them). Furniture blocks actors;
## actors do not block each other. PICKABLE is nobody's obstacle: it carries the
## click targets the viewport picks a desk with, so a target can never stand in
## a walking actor's way.
const FURNITURE := 1
const ACTORS := 2
const PICKABLE := 4
