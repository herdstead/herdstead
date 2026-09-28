class_name FloorRef
extends RefCounted
## A floor together with the building it stands in, as OfficeProjection.find_floor
## answers. A floor key alone says nothing about whose machine it is, and both
## halves are needed to draw the plate, so they travel together.

var building: BuildingModel
var floor_model: FloorModel


func _init(in_building: BuildingModel, at_floor: FloorModel) -> void:
	building = in_building
	floor_model = at_floor
