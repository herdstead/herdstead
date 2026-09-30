class_name MapModel
extends RefCounted
## What one office map draws: its zones, and their rooms read as one floor.
## The floor view, the presentation, the rests and the plan cache take a map,
## and the map planner (OfficeFloorLayout) lays every zone of it out at once.
##
## The office draws one map per machine (OfficeProjection.building() makes it
## with of_zones() under the machine's key): the plan cache, FloorPlan.floor_key,
## the world, the pans and the cold path are all the machine's. A machine with
## no workspace is an empty map: no zone, nothing laid out but the shell.

## The map's key: the machine's for the office's maps (of_zones()), the wrapped
## zone's for of(), which the planner's own tests use.
var key := ""
var zones: Array[ZoneModel] = []
## Every zone's rooms, in zone order, each zone's in its own order.
var rooms: Array[RoomModel] = []


## The map of the one zone `zone`, under its key: a planner's test fixture;
## the office's maps are the machines' (of_zones()).
static func of(zone: ZoneModel) -> MapModel:
	var map := MapModel.new()
	map.key = zone.key
	map.zones.append(zone)
	map.rooms.append_array(zone.rooms)
	return map


## The empty map `map_key`: a machine with no workspace.
static func empty(map_key: String) -> MapModel:
	var map := MapModel.new()
	map.key = map_key
	return map


## The map `map_key` of the zones in `list`, in the order given (the planner orders them itself).
static func of_zones(map_key: String, list: Array[ZoneModel]) -> MapModel:
	var map := MapModel.new()
	map.key = map_key
	for zone in list:
		map.zones.append(zone)
		map.rooms.append_array(zone.rooms)
	return map


## Changes that may require planning: the zones' geometry, sorted, and never
## display data such as a mezzanine grouping. A map of one zone plans exactly
## as that zone does, so its signature is that zone's.
func geometry_signature() -> String:
	if zones.size() == 1:
		return zones[0].geometry_signature()
	var signatures := PackedStringArray()
	for zone in zones:
		signatures.append(zone.geometry_signature())
	signatures.sort()
	return JSON.stringify([key, signatures])


## Panes seated on the map, every zone's together.
func pane_count() -> int:
	var total := 0
	for zone in zones:
		total += zone.pane_count()
	return total


## Pane keys the map carries more than once, as a set, across its zones: two
## desks under one key cannot be told apart in place, whichever zones hold them.
func repeated_keys() -> Dictionary:
	var seen := {}
	var repeated := {}
	for room in rooms:
		for pane in room.panes:
			if seen.has(pane.key):
				repeated[pane.key] = true
			seen[pane.key] = true
	return repeated
