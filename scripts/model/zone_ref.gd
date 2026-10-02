class_name ZoneRef
extends RefCounted
## A zone together with the building (machine) it stands in, as
## OfficeFrame.find_zone() answers: the machine is what a zone pick shows, and
## the sign's tooltip reads its siblings, so they travel together.

var building: BuildingModel
var zone_model: ZoneModel


func _init(in_building: BuildingModel, at_zone: ZoneModel) -> void:
	building = in_building
	zone_model = at_zone
