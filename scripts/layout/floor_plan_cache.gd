class_name FloorPlanCache
extends RefCounted
## Every map's last valid plan, and what was last tried for it, for as long as
## the map exists. A map is kept under its key (the office hands in one per
## machine, under the machine's key), with its plan and history: a refresh plans a map again only
## when its geometry, the art pack or the clearance policy changed. Status,
## labels, focus and liveness never invalidate a plan. Not persisted: this is
## the run's memory.
##
## Planning is atomic per map: every zone of it is laid out at once, and while
## any zone's input cannot be planned (failing_zones()) the whole previous
## plan and the model it was made for stay. The last attempted input and its
## failure are kept apart from the valid plan. The same failing input is not
## planned again: its problems come back from here and the map stays drawn
## from its last valid plan. A map that never had one gets a bounded empty
## fallback (no zone at all), labelled by its problems.
##
## A machine with no workspace is an empty map (no zone: walls, door, windows,
## walkways, decor, no pantry). It is planned like any other, so it is in the
## layout diagnostics too: layout_plan(), problems(), notes() and attempt_count().

var _plans: Dictionary[String, FloorPlan] = {}
## The model each valid plan was drawn from: what a floor whose current input
## cannot be planned keeps showing.
var _planned_models: Dictionary[String, MapModel] = {}
var _attempt_inputs: Dictionary[String, String] = {}
var _attempt_problems: Dictionary[String, PackedStringArray] = {}
var _notes: Dictionary[String, PackedStringArray] = {}
## The zones the last attempt of each map failed on; empty once it planned.
var _failing: Dictionary[String, PackedStringArray] = {}
## The problems of the map prepare() was last asked for.
var _problems := PackedStringArray()
var _attempts := 0
## The person prefab's feet, read once: PixelPerson.footprint() instantiates it.
var _footprint := Rect2()
var _footprint_read := false


## The plan to draw `map` with, `visible_width` units wide if it is planned for
## the first time. That is its valid plan for the current input;
## while the input cannot be planned, its last valid plan (see problems() and
## planned_model()); and a bounded empty floor when it never had one. `pen`
## measures the furniture the plan is furnished with. The whole map goes to
## the map planner at once.
func prepare(map: MapModel, pen: OfficeDraw, visible_width: float) -> FloorPlan:
	var policy := FloorLayoutPolicy.new()
	policy.width_cells = maxi(1, floori(visible_width / FloorLayoutPolicy.GRID))
	policy.actor_draw_rect = PixelPerson.drawing_rect(pen.art.people)
	policy.actor_footprint = _actor_footprint()
	var previous: FloorPlan = _plans.get(map.key)
	# Budgets can change acceptance without changing the retained row geometry.
	var input := JSON.stringify(
		[
			map.geometry_signature(),
			pen.art.id,
			policy.geometry_signature(),
			policy.max_width_cells,
			policy.max_height_cells,
			policy.max_floor_cells,
			policy.max_panes,
			policy.max_tables
		]
	)
	# Width is fixed once there is a compatible plan (even an empty fallback).
	# A policy reset discards incompatible rows, so a failed reset still depends
	# on the viewport width used to seed its replacement.
	var attempted_input := input
	if previous != null and previous.policy_signature != policy.geometry_signature():
		attempted_input = JSON.stringify([input, policy.width_cells])
	if previous != null and _attempt_inputs.get(map.key, "") == attempted_input:
		_problems = _attempt_problems[map.key].duplicate()
		if _problems.is_empty():
			_planned_models[map.key] = map
		return previous
	_attempts += 1
	var result := OfficeFloorLayout.plan(
		map, previous, policy, OfficeDecorPlanner.new(pen), OfficeFixturePlanner.new(pen)
	)
	_problems = result.problems
	_attempt_inputs[map.key] = input if result.plan != null else attempted_input
	_attempt_problems[map.key] = result.problems.duplicate()
	_failing[map.key] = result.failing_zones.duplicate()
	if result.plan != null:
		_plans[map.key] = result.plan
		_planned_models[map.key] = map
		_notes[map.key] = result.diagnostics
		return result.plan
	if previous != null:
		return previous
	# A bad first snapshot still gets a bounded, empty, explicitly labelled map:
	# no zone at all, like a machine's without workspaces.
	var empty := MapModel.empty(map.key)
	_attempts += 1
	var fallback := OfficeFloorLayout.plan(empty, null, policy)
	_plans[map.key] = fallback.plan
	_planned_models[map.key] = empty
	return fallback.plan


## Why the map prepare() was last asked for cannot be drawn from its current
## input; empty while it can.
func problems() -> PackedStringArray:
	return _problems.duplicate()


## A map's plan as the cache holds it (by machine key for the office's maps); null for an unknown map.
func plan(key: String) -> FloorPlan:
	return _plans.get(key)


## The model the plan of `key` was made for, which is what to draw while the
## map's current input cannot be planned.
func planned_model(key: String) -> MapModel:
	return _planned_models.get(key)


## The zones (ZoneModel.key) whose input the last attempt of map `key` failed
## on; empty while it plans. The whole map keeps its previous plan meanwhile.
func failing_zones(key: String) -> PackedStringArray:
	var found: PackedStringArray = _failing.get(key, PackedStringArray())
	return found.duplicate()


## Non-fatal explanations, such as folding a complex terminal grid into seats.
func notes(key: String) -> PackedStringArray:
	var found: PackedStringArray = _notes.get(key, PackedStringArray())
	return found.duplicate()


## Actual planner calls, empty maps and empty fallbacks included. Cache hits
## do not count.
func attempt_count() -> int:
	return _attempts


## Keep only the maps in `map_keys` (every machine that exists now): a machine
## that went away releases its history, and a map that is merely not shown
## keeps it. A workspace coming or going is a zone of its machine's map, never
## a map of its own: it releases nothing here.
func prune(map_keys: Array[String]) -> void:
	var present: Dictionary[String, bool] = {}
	for key in map_keys:
		present[key] = true
	for key: String in _plans.keys():
		if not present.has(key):
			_plans.erase(key)
			_planned_models.erase(key)
			_attempt_inputs.erase(key)
			_attempt_problems.erase(key)
			_notes.erase(key)
			_failing.erase(key)


func _actor_footprint() -> Rect2:
	if not _footprint_read:
		_footprint = PixelPerson.footprint()
		_footprint_read = true
	return _footprint
