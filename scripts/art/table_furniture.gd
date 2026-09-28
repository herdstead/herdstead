class_name TableFurniture
extends Resource
## A thing that stands on the shared table and is drawn from more than one
## side: a chair seen from the front or the back, a monitor's rear shell or its
## privacy front. Every view is one of the table's modules.

var id := &""
var size := Vector2i.ZERO
## Where the view's foot is, shared by every view of this furniture.
var pivot := Vector2.ZERO
var views: Dictionary[StringName, StringName] = {}


## The module drawn for `view`, or empty when this furniture has no such side.
func view(name: StringName) -> StringName:
	return views[name] if views.has(name) else &""
