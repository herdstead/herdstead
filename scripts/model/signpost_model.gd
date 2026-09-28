class_name SignpostModel
extends RefCounted
## One signpost over the world's right edge: another floor with agents blocked
## on it, which way it is from the floor shown, and how many are waiting. The
## office decides these from its frame; the signpost only draws them.

## The floor's key: what a click on the post shows.
var key := ""
## Its number and name as the minimap's row writes them (`3F infra`, `1A hud-lane`).
var floor_text := ""
## Its number alone (`3F`, `1A`): all a compact post has room for.
var number_text := ""
## The machine's label, only for a floor in another building than the one
## shown (it says "not this building"); empty otherwise.
var machine := ""
## The machine key its blocked badge pulses for (StatusBadge.pulse_for()).
var machine_key := ""
## Agents blocked on that floor; always more than zero.
var blocked := 0
## Whether the floor is above the shown one in OfficeNavigator.shaft_order().
var up := true
