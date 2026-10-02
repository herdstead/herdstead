class_name BuildingModel
extends RefCounted
## One herdr machine as the office draws it: one open-plan map of zones, one
## zone per workspace, Local first.

## The machine key the fleet knows this machine by.
var key := ""
var label := ""
## Its client is not connected. Its zones then report nobody waiting, and its
## map, while on screen, dims and freezes instead of being redrawn.
var stale := false
## Workspaces, tabs and panes the whole snapshot carries, for the top bar's
## counts. The zones below only cover what could actually be placed.
var spaces := 0
var tabs := 0
var panes := 0
## Every pane the snapshot carries, in snapshot order, whether or not a zone
## could seat it: who needs a human is about the machine, not about its zones.
var all_panes: Array[PaneModel] = []
## Ascending by herdr's workspace number; empty for a machine without
## workspaces (offline, never loaded, or an empty session), whose map is empty.
var zones: Array[ZoneModel] = []
## The same zones in tree order (OfficeProjection.floor_tree()): each zone that
## is no mezzanine by number, its mezzanines right after it.
var zone_tree: Array[ZoneModel] = []
## The machine's one map: every zone above, under the machine's key
## (MapModel.of_zones()). What the office plans, draws and pans as one world.
var map: MapModel
