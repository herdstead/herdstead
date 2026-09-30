class_name RowPlan
extends RefCounted
## One pod row of a zone. A retained row can be empty. An oversized desk owns
## its entire row. `index` counts from the zone's top; the band is in map cells.

var index := 0
var band_cells := Rect2i()
var exclusive_tab_key := ""
var desks: Array[DeskPlacement] = []
