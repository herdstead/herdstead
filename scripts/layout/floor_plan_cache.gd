class_name FloorPlanCache
extends RefCounted
## Every floor's last valid plan, and what was last tried for it, for as long as
## the floor exists. A floor is a MapModel of one zone, kept under that zone's
## key, so each workspace keeps its own plan and history: a refresh plans a floor again only when its geometry, the
## art pack or the clearance policy changed. Status, labels, focus and liveness
## never invalidate a plan. Not persisted: this is the run's memory.
##
## The last attempted input and its failure are kept apart from the valid plan.
## The same failing input is not planned again: its problems come back from
## here and the floor stays drawn from its last valid plan. A floor that never
## had one gets a bounded empty fallback, labelled by its problems.
##
## A building's lobby is planned the same way (walls, door, windows, walkways,
## decor; no fixtures, having no tables) but it lays out nothing herdr sent, so it has no place in the layout
## diagnostics: layout_plan(), problems(), notes() and attempt_count() are about
## workspaces only.

var _plans: Dictionary[String, FloorPlan] = {}
## The model each valid plan was drawn from: what a floor whose current input
## cannot be planned keeps showing.
var _planned_models: Dictionary[String, MapModel] = {}
var _attempt_inputs: Dictionary[String, String] = {}
var _attempt_problems: Dictionary[String, PackedStringArray] = {}
var _notes: Dictionary[String, PackedStringArray] = {}
var _lobbies: Dictionary[String, FloorPlan] = {}
var _lobby_inputs: Dictionary[String, String] = {}
## The problems of the floor prepare() was last asked for.
var _problems := PackedStringArray()
var _attempts := 0
## The person prefab's feet, read once: PixelPerson.footprint() instantiates it.
var _footprint := Rect2()
var _footprint_read := false


## The plan to draw `map` with, `visible_width` units wide if it is planned for
## the first time. For a workspace that is its valid plan for the current input;
## while the input cannot be planned, its last valid plan (see problems() and
## planned_model()); and a bounded empty floor when it never had one. `pen`
## measures the furniture the plan is furnished with. A map is laid out as its
## one zone; one without exactly one zone cannot be planned.
func prepare(map: MapModel, pen: OfficeDraw, visible_width: float) -> FloorPlan:
	var policy := FloorLayoutPolicy.new()
	policy.width_cells = maxi(1, floori(visible_width / FloorLayoutPolicy.GRID))
	policy.actor_draw_rect = PixelPerson.drawing_rect(pen.art.people)
	policy.actor_footprint = _actor_footprint()
	var floor_model: ZoneModel = map.zones[0] if map.zones.size() == 1 else null
	if map.lobby():
		_problems.clear()
		return _lobby(map, pen, policy)
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
		floor_model, previous, policy, OfficeDecorPlanner.new(pen), OfficeFixturePlanner.new(pen)
	)
	_problems = result.problems
	_attempt_inputs[map.key] = input if result.plan != null else attempted_input
	_attempt_problems[map.key] = result.problems.duplicate()
	if result.plan != null:
		_plans[map.key] = result.plan
		_planned_models[map.key] = map
		_notes[map.key] = result.diagnostics
		return result.plan
	if previous != null:
		return previous
	# A bad first snapshot still gets a bounded, empty, explicitly labelled floor.
	var empty := ZoneModel.new()
	empty.key = map.key
	_attempts += 1
	var fallback := OfficeFloorLayout.plan(empty, null, policy)
	_plans[map.key] = fallback.plan
	_planned_models[map.key] = MapModel.of(empty)
	return fallback.plan


## Why the floor prepare() was last asked for cannot be drawn from its current
## input; empty while it can (and always for a lobby).
func problems() -> PackedStringArray:
	return _problems.duplicate()


## A workspace's plan as the cache holds it; null for a lobby or an unknown floor.
func plan(key: String) -> FloorPlan:
	return _plans.get(key)


## The model the plan of `key` was made for, which is what to draw while the
## floor's current input cannot be planned.
func planned_model(key: String) -> MapModel:
	return _planned_models.get(key)


## Non-fatal explanations, such as folding a complex terminal grid into seats.
func notes(key: String) -> PackedStringArray:
	var found: PackedStringArray = _notes.get(key, PackedStringArray())
	return found.duplicate()


## Actual planner calls for workspaces, including empty fallbacks. Cache hits
## and lobbies do not count.
func attempt_count() -> int:
	return _attempts


## Keep only the floors in `floor_keys` (every floor that exists now): closed
## workspaces and lobbies that went away release their history, and a floor
## that is merely not shown keeps it.
func prune(floor_keys: Array[String]) -> void:
	var present: Dictionary[String, bool] = {}
	for key in floor_keys:
		present[key] = true
	for key: String in _plans.keys():
		if not present.has(key):
			_plans.erase(key)
			_planned_models.erase(key)
			_attempt_inputs.erase(key)
			_attempt_problems.erase(key)
			_notes.erase(key)
	for key: String in _lobbies.keys():
		if not present.has(key):
			_lobbies.erase(key)
			_lobby_inputs.erase(key)


## A lobby is an empty floor: planned once per pack and clearance policy, and
## kept, like any floor's, when a new policy cannot be planned.
func _lobby(map: MapModel, pen: OfficeDraw, policy: FloorLayoutPolicy) -> FloorPlan:
	var previous: FloorPlan = _lobbies.get(map.key)
	var input := JSON.stringify([map.geometry_signature(), pen.art.id, policy.geometry_signature()])
	if previous != null and _lobby_inputs.get(map.key, "") == input:
		return previous
	var result := OfficeFloorLayout.plan(
		map.zones[0], previous, policy, OfficeDecorPlanner.new(pen), OfficeFixturePlanner.new(pen)
	)
	_lobby_inputs[map.key] = input
	if result.plan == null:
		return previous
	_lobbies[map.key] = result.plan
	return result.plan


func _actor_footprint() -> Rect2:
	if not _footprint_read:
		_footprint = PixelPerson.footprint()
		_footprint_read = true
	return _footprint
