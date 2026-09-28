class_name RowPlan
extends RefCounted
## A retained row can be empty. An oversized desk owns its entire row.

var index := 0
var band_cells := Rect2i()
var wall_cells := Rect2i()
var corridor_cells := Rect2i()
var exclusive_tab_key := ""
var desks: Array[DeskPlacement] = []
