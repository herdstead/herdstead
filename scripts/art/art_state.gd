class_name ArtState
extends Resource
## What one herdr state looks like in a pack: the animation its worker plays,
## the UI badge that floats over the seat, and the words the inspector prints.

var id := &""
## A semantic animation name (idle, working, blocked, starting).
var animation := &"idle"
## The id of a UI image in the same pack.
var badge := &""
var label := ""
