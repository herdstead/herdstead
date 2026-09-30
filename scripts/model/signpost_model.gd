class_name SignpostModel
extends RefCounted
## One signpost over the world's right edge (interim, until the edge arrows): a
## zone of the shown map with blocked desks off screen, or another machine's
## zone with agents blocked; which way it is from the view, and how many are
## waiting. The office decides these from its frame; the signpost only draws them.

## The zone's key: what a click on the post picks (OfficeNavigator.pick_zone()).
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
## Up: on the shown map, most of its blocked desks are above the view's middle;
## on another machine, that machine comes before the shown one in the rail.
var up := true
