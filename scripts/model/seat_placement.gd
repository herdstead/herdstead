class_name SeatPlacement
extends RefCounted
## One pane's resolved seat. Terminal coordinates never reach the renderer.

var pane_key := ""
var tab_key := ""
var column := 0
var side := "far"


func geometry_signature() -> String:
	return JSON.stringify([pane_key, tab_key, column, side])
