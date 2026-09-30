class_name OfficeRests
extends RefCounted
## Where each worker of a floor rests, as a pure function of the floor's model
## on its plan: the one place docs/VISUAL_LANGUAGE.md, "Where people rest", lives.
##
## An agent's state decides the kind of place: idle rests in the floor's pantry,
## everything else sits at its own seat — working, starting and unknown, done
## (UNREAD, with a stack of paper on the desk) and blocked (hand up, with a
## bubble over the head). What a state looks like at the seat is the station's.
## The floor's capacity and the order they have waited
## (OfficeProjection.wait_order(), the `N` key's order) decide the exact place
## of the idle: every idle one has a spot of their own (a hash of their pane
## key) and whoever finds it taken, in order, takes the next free one, and when
## none is free sits down. A floor without the pantry seats them all. Nobody
## rests at the reception. Nothing here remembers anything: a cold pass and a
## live pass that settles see the same places.
##
## The population is the one the floor's people and counts are: panes with an
## agent (or one still launching), seated on the plan, and not repeated.

enum Rest { SEAT, PANTRY }


## Where one pane's worker rests: the kind of place, and which spot of the
## pantry (-1 for a seat).
class Place:
	extends RefCounted
	var rest := Rest.SEAT
	var index := -1

	func _init(kind := Rest.SEAT, at := -1) -> void:
		rest = kind
		index = at

	func away() -> bool:
		return rest == Rest.PANTRY


## One floor's rests: every worker's place, by pane key.
class Service:
	extends RefCounted
	var places: Dictionary[String, Place] = {}


## The kind of place an agent in `state` rests at, before any capacity: a pane
## still launching says nothing about its agent yet, so it sits.
static func rest_of(state: StringName, starting: bool) -> Rest:
	if starting:
		return Rest.SEAT
	if state == ArtContract.STATE_IDLE:
		return Rest.PANTRY
	return Rest.SEAT


## Where every worker of `model` on `plan` rests (see the class comment).
static func assign(plan: FloorPlan, model: ZoneModel) -> Service:
	var result := Service.new()
	var seated: Dictionary[String, bool] = {}
	for desk in plan.desks:
		for seat in desk.seats:
			seated[seat.pane_key] = true
	var repeated := model.repeated_keys()
	var idle: Array[PaneModel] = []
	for room in model.rooms:
		for pane in room.panes:
			if (pane.provider.is_empty() and not pane.starting) or not seated.has(pane.key) or repeated.has(pane.key):
				continue
			var rest := rest_of(StringName(pane.state), pane.launching())
			if rest == Rest.PANTRY:
				idle.append(pane)
			else:
				result.places[pane.key] = Place.new(rest)
	var spots := 0 if plan.pantry == null else plan.pantry.spots.size()
	var taken: Dictionary[int, bool] = {}
	for pane in OfficeProjection.wait_order(idle):
		var spot := _free_spot(pane.key, spots, taken)
		if spot < 0:
			result.places[pane.key] = Place.new(Rest.SEAT)
			continue
		taken[spot] = true
		result.places[pane.key] = Place.new(Rest.PANTRY, spot)
	return result


## The pantry spot of pane `key` among `count`: its own (a hash of the key), or
## the next one on from it that is not `taken`; -1 when every one is.
static func _free_spot(key: String, count: int, taken: Dictionary[int, bool]) -> int:
	if count <= 0 or taken.size() >= count:
		return -1
	var start := posmod(key.hash(), count)
	for step in count:
		var spot := (start + step) % count
		if not taken.has(spot):
			return spot
	return -1
