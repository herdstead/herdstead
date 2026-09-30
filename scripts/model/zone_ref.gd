class_name ZoneRef
extends RefCounted
## A floor together with the building it stands in, as OfficeProjection.find_floor
## answers. A floor key alone says nothing about whose machine it is, and both
## halves are needed to draw the plate, so they travel together.

var building: BuildingModel
var zone_model: ZoneModel


func _init(in_building: BuildingModel, at_zone: ZoneModel) -> void:
	building = in_building
	zone_model = at_zone
