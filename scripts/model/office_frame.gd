class_name OfficeFrame
extends RefCounted
## One refresh's whole projection, made once by OfficeProjection.frame() and
## read by everything that refresh draws: the navigator, the floor, the plate,
## the minimap, the inspector, attention and the `N` queue. Nothing in a
## refresh projects a snapshot a second time or scans the buildings for a key.

## One building per machine, Local first.
var buildings: Array[BuildingModel] = []
## Every pane of every machine by composite key, seated on a floor or not, with
## the labels of the workspace and tab it names: what the inspector and
## attention show. The first pane a snapshot carries under a key wins.
var pane_by_key: Dictionary[String, PaneModel] = {}
## Composite pane key -> the floor it is seated on. A pane no floor could seat
## is absent: its location is unknown.
var floor_of_pane: Dictionary[String, String] = {}
## Floor key -> the floor and the building it stands in.
var floor_by_key: Dictionary[String, FloorRef] = {}
## Every floor bottom to top, building after building: the PageUp/PageDown order.
var floor_order: Array[String] = []
## Panes of every live machine, seated or not, for the attention counts. A
## dropped machine's last snapshot is not a live signal.
var live_panes: Array[PaneModel] = []
## Herdr's own focus as a composite key: Local's first; without one, the first
## machine that has one; empty when none has.
var herdr_focus := ""


## The floor with this key and the building it stands in, or null.
func find_floor(key: String) -> FloorRef:
	return floor_by_key.get(key)


## Key of the floor a desk sits on, or empty.
func floor_of(pane_key: String) -> String:
	return floor_of_pane.get(pane_key, "")


## The pane with this composite key, seated or not; null when no machine has it.
func pane(key: String) -> PaneModel:
	return pane_by_key.get(key)


## Building headings, the plate's machine line and the inspector's `@ machine`
## only appear once there is more than Local.
func several_machines() -> bool:
	return buildings.size() > 1


## The desk selected: `picked_key` while it sits on some floor, a picked desk on
## a hidden floor included (it is what pulls its floor back into view), else
## herdr's focus.
func effective_selection(picked_key: String) -> String:
	return picked_key if not floor_of(picked_key).is_empty() else herdr_focus


## The floor the viewer picked, else the one holding the selection (a picked
## desk, else herdr's focus), else the first real floor of the first building
## that has one, else the first building's lobby.
func choose_floor(picked_floor: String, active_key: String) -> String:
	if find_floor(picked_floor) != null:
		return picked_floor
	var holding := floor_of(active_key)
	if not holding.is_empty():
		return holding
	for building_model in buildings:
		for floor_model in building_model.floors:
			if not floor_model.lobby:
				return floor_model.key
	return "" if buildings.is_empty() else buildings[0].floors[0].key
