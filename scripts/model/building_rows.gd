class_name BuildingRows
extends RefCounted
## One building's rows in the floors panel: its heading and its floors.
##
## The panel knows no herdr and no fleet, so whether the machine is live arrives
## as a plain state the office decided.

var key := ""
var label := ""
## How the building's machine is answering: the colour of the heading's mark.
var state := MachineLiveness.State.LIVE
## Ascending by floor number, the way the office projected them; the panel draws
## them the other way round, highest on top.
var floors: Array[FloorModel] = []


static func of(building: BuildingModel, live_state: MachineLiveness.State) -> BuildingRows:
	var rows := BuildingRows.new()
	rows.key = building.key
	rows.label = building.label
	rows.state = live_state
	rows.floors = building.floors
	return rows
