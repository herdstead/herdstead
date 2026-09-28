class_name FloorModel
extends RefCounted
## One herdr workspace as the office draws it: a floor of rooms, or the lobby of
## a building that has no workspaces at all.

## Machine key and workspace id together; a lobby's key carries a second
## separator, so no real floor can collide with it.
var key := ""
## Herdr's own workspace number, which is the floor number; 0 for a lobby.
var number := 0
var label := ""
## Repository of the workspace's worktree; empty when it has none. The API
## carries no branch name, so there is none here either.
var repo := ""
## Last component of the checkout path, for a workspace standing in a linked
## worktree of that repository; empty for every other workspace. The plate shows
## it after the repo name.
var worktree := ""
## The floor's number as the minimap and the plate write it: herdr's number
## ("3"), or, for a mezzanine, its source floor's number and a letter ("3A").
## Empty for a lobby. See OfficeProjection.group_worktrees().
var level_label := ""
## Key of the floor this one is a mezzanine of: the workspace herdr made this
## linked worktree from, when it is open on the same machine. Empty for every
## floor that is not a mezzanine. Display, not geometry: never in
## geometry_signature(), so a group forming or breaking up re-plans nothing.
var mezzanine_of := ""
## 0-based among its source floor's mezzanines, in herdr's workspace order; -1
## when this is no mezzanine.
var mezzanine_index := -1
## This is a building's lobby, not a workspace: no rooms, a note instead.
var lobby := false
## Agents seated on this floor, one still launching included.
var agents := 0
## Panes whose agent needs a human (see OfficeAttention.count). A stale machine
## reports none: a lost connection is not a live signal.
var blocked := 0
var done := 0
var rooms: Array[RoomModel] = []


## Changes that may require planning. Display data never invalidates a plan.
func geometry_signature() -> String:
	var groups := PackedStringArray()
	for room in rooms:
		groups.append(room.geometry_signature())
	groups.sort()
	return JSON.stringify([key, lobby, groups])


## Panes seated on this floor, for the plate's counts.
func pane_count() -> int:
	var total := 0
	for room in rooms:
		total += room.panes.size()
	return total


## Pane keys this floor carries more than once, as a set. A remote snapshot may
## repeat a pane id, and two desks under one key cannot be told apart in place.
func repeated_keys() -> Dictionary:
	var seen := {}
	var repeated := {}
	for room in rooms:
		for pane in room.panes:
			if seen.has(pane.key):
				repeated[pane.key] = true
			seen[pane.key] = true
	return repeated
