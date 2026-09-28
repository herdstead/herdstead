class_name MachineView
extends RefCounted
## One machine as a refresh sees it: what HerdrFleet holds for it, handed to
## OfficeProjection.frame() so the projection never touches the fleet.

## The machine key the fleet knows this machine by.
var key := ""
var label := ""
## Its client is not connected, or has no current snapshot (HerdrFleet.is_stale).
var stale := false
## The snapshot its client holds; an empty one for a machine that has none yet.
var snapshot: HerdrSnapshot


func _init(machine_key: String, machine_label: String, held: HerdrSnapshot, is_stale: bool) -> void:
	key = machine_key
	label = machine_label
	snapshot = held if held != null else HerdrSnapshot.new()
	stale = is_stale
