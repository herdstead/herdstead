class_name BuildingModel
extends RefCounted
## One herdr machine as the office draws it: a building of floors, Local first.

## The machine key the fleet knows this machine by.
var key := ""
var label := ""
## Its client is not connected. Its floors then report nobody waiting, and the
## floor on screen dims and freezes instead of being redrawn.
var stale := false
## Workspaces, tabs and panes the whole snapshot carries, for the top bar's
## counts. The floors below only cover what could actually be placed.
var spaces := 0
var tabs := 0
var panes := 0
## Every pane the snapshot carries, in snapshot order, whether or not a floor
## could seat it: who needs a human is about the machine, not about its floors.
var all_panes: Array[PaneModel] = []
## Ascending by herdr's workspace number; a building without workspaces has one
## lobby floor instead.
var floors: Array[FloorModel] = []
## The same floors in tree order (OfficeProjection.floor_tree()): each floor that
## is no mezzanine by number, its mezzanines right after it.
var floor_tree: Array[FloorModel] = []
