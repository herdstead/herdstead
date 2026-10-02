class_name FloorLayoutResult
extends RefCounted
## On failure plan is null. The caller retains its previous valid world.

var plan: FloorPlan
var problems := PackedStringArray()
var diagnostics := PackedStringArray()
## The zones whose input or layout failed the map (ZoneModel.key), in the
## order found: the whole map fails with them, and the plan cache keeps the
## previous one.
var failing_zones := PackedStringArray()
