class_name MapModel
extends RefCounted
## What one office map draws: its zones, and their rooms read as one floor.
## The floor view, the presentation, the rests and the plan cache take a map,
## and the map planner (OfficeFloorLayout) lays every zone of it out at once.
##
## The office still builds a map of exactly one zone (one workspace, or a
## lobby) under that zone's key, never the machine's: the plan cache,
## FloorPlan.floor_key, the world, the pans and the cold path all stay per
## workspace. A map of several zones (of_zones()) is what the planner and its
## tests lay out; the office moves to one map per machine later.

## The map's key: the wrapped zone's (see ZoneModel.key), or whatever of_zones() was given.
var key := ""
var zones: Array[ZoneModel] = []
## Every zone's rooms, in zone order, each zone's in its own order.
var rooms: Array[RoomModel] = []


## The map of the one zone `zone`, under its key.
static func of(zone: ZoneModel) -> MapModel:
	var map := MapModel.new()
	map.key = zone.key
	map.zones.append(zone)
	map.rooms.append_array(zone.rooms)
	return map


## The map `map_key` of the zones in `list`, in the order given (the planner orders them itself).
static func of_zones(map_key: String, list: Array[ZoneModel]) -> MapModel:
	var map := MapModel.new()
	map.key = map_key
	for zone in list:
		map.zones.append(zone)
		map.rooms.append_array(zone.rooms)
	return map


## A map of one lobby: no workspace to lay out, only an empty floor.
func lobby() -> bool:
	return zones.size() == 1 and zones[0].lobby


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
