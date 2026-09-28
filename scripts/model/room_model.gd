class_name RoomModel
extends RefCounted
## One herdr tab as the office draws it: a shared table with its rug, and the
## panes seated around it in reading order.

## Whether this tab is the one its workspace has open. Herdr need not say —
## a snapshot without `active_tab_id` says nothing about any of its tabs — and
## not saying is not a no: UNKNOWN is drawn like YES, never like NO.
enum Active { UNKNOWN, NO, YES }

## Stable identity; display numbers and labels never name a placement.
var key := ""
var tab_id := ""
var number := 0

## The tab's label, on the room's sign.
var label := ""
## Whether this table is the open one (see Active). What the desk lamps of this
## room are dimmed by, and deliberately not part of its geometry signature: a
## tab opening must not re-plan the floor.
var active := Active.UNKNOWN
## Seats left to right, as herdr's layout rects order them.
var panes: Array[PaneModel] = []


func geometry_signature() -> String:
	var hints := PackedStringArray()
	for pane in panes:
		hints.append(JSON.stringify([pane.key, pane.explicit_layout, pane.table_x, pane.side, pane.layout_order]))
	hints.sort()
	return JSON.stringify([key, number, hints])
