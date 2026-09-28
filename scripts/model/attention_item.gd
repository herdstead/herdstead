class_name AttentionItem
extends RefCounted
## One locally observed attention episode, held only for this app run.
## observed_at is a local observation time, never a server event timestamp.

var id := ""
var pane_key := ""
var identity_key := ""
var machine_key := ""
var machine_label := ""
var workspace_key := ""
var workspace_label := ""
var tab_label := ""
var provider := ""
var title := ""
## The attention state recorded for this episode, not a live pane status.
var state := ""
var observed_at: float = -1.0
## Monotonic local start of continuous observation; -1 means unknown.
var since_msec: int = -1
var baseline := false
var active := false
var stale := false
var available := false
## Ended, or its pane closed, replaced or removed: the store has let it go and
## it can never regain a navigation target. Unlike staleness, permanent.
var retired := false
var hidden := false
var snoozed_until_msec: int = 0
var note := ""


func is_snoozed(now_msec: int) -> bool:
	return snoozed_until_msec > now_msec
