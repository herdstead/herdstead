class_name OfficeFrame
extends RefCounted
## One refresh's whole projection, made once by OfficeProjection.frame() and
## read by everything that refresh draws: the navigator, the map, the plate,
## the SPACES rail, the inspector, attention and the `N` queue. Nothing in a
## refresh projects a snapshot a second time or scans the machines for a key.

## One BuildingModel per machine, Local first; each is one map (BuildingModel.map).
var buildings: Array[BuildingModel] = []
## Every pane of every machine by composite key, seated in a zone or not, with
## the labels of the workspace and tab it names: what the inspector and
## attention show. The first pane a snapshot carries under a key wins.
var pane_by_key: Dictionary[String, PaneModel] = {}
## Composite pane key -> the zone it is seated in. A pane no zone could seat
## is absent: its location is unknown.
var zone_of_pane: Dictionary[String, String] = {}
## Zone key -> the zone and the building (machine) it stands in.
var zone_by_key: Dictionary[String, ZoneRef] = {}
## Machine key -> its building.
var building_by_key: Dictionary[String, BuildingModel] = {}
## Every zone as the SPACES rail draws it, top to bottom, machine after machine
## in fleet order (OfficeNavigator.section() per machine: ascending, mezzanines
## after their source): what PageUp (one back) and PageDown (one on) step
## through, across machines.
var zone_order: Array[String] = []
## Panes of every live machine, seated or not, for the attention counts. A
## dropped machine's last snapshot is not a live signal.
var live_panes: Array[PaneModel] = []
## Herdr's own focus as a composite key: Local's first; without one, the first
## machine that has one; empty when none has.
var herdr_focus := ""


## The zone with this key and the building it stands in, or null.
func find_zone(key: String) -> ZoneRef:
	return zone_by_key.get(key)


## Key of the zone a desk sits in, or empty.
func zone_of(pane_key: String) -> String:
	return zone_of_pane.get(pane_key, "")


## The pane with this composite key, seated or not; null when no machine has it.
func pane(key: String) -> PaneModel:
	return pane_by_key.get(key)


## The building of machine `machine`, or null.
func building_of(machine: String) -> BuildingModel:
	return building_by_key.get(machine)


## The map of machine `machine`: every zone of it, under its key; null for a
## machine the frame does not have.
func map_of(machine: String) -> MapModel:
	var found := building_of(machine)
	return null if found == null else found.map


## Machine headings, the plate's machine line and the inspector's `@ machine`
## only appear once there is more than Local.
func several_machines() -> bool:
	return buildings.size() > 1


## The desk selected: `picked_key` while it sits in some zone, a picked desk on
## a machine not shown included (it is what pulls its map back into view), else
## herdr's focus.
func effective_selection(picked_key: String) -> String:
	return picked_key if not zone_of(picked_key).is_empty() else herdr_focus


## The machine whose map to show: the one the viewer picked, else the one
## holding the selection (a picked desk, else herdr's focus), else the first
## machine with a zone, else the first machine; empty with no machine at all.
func choose_machine(picked_machine: String, active_key: String) -> String:
	if building_by_key.has(picked_machine):
		return picked_machine
	var holding := zone_of(active_key)
	if not holding.is_empty():
		return find_zone(holding).building.key
	for building_model in buildings:
		if not building_model.zones.is_empty():
			return building_model.key
	return "" if buildings.is_empty() else buildings[0].key
