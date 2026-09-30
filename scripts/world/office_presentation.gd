class_name OfficePresentation
extends RefCounted
## What the shown floor's people do between one observation of it and the next:
## who walks in at the lift door, who walks out, who goes to the pantry or back
## to the seat, and who walks to a new seat. An observation (a ZoneModel laid out on a
## FloorPlan) says where everyone belongs, at once: the plate, the badge and the
## click target of a seat follow it the moment it arrives (OfficeStation). This
## only brings the bodies there, by the routes the floor's walk graph allows
## (OfficeWalkGraph), which is the graph the layout was validated on. A route
## enters an obstacle only along the graph's entries: the seat legs at a
## table's current place and the door's threshold leg.
##
## Where everyone belongs is where their state rests them (OfficeRests): the
## seat, or the floor's pantry in the entry band. The seats and the pantry are
## joined by the walking lane: every seat reaches the entry band through the
## main corridor, so a walk to or from the pantry is the door's field read down
## to the lane (OfficeWalkGraph.to_lane() and from_lane()), a straight run along
## the lane and the pantry's leg. No route is searched for.
##
## One floor-level model, keyed by pane key and the terminal's identity
## (PaneModel.identity_key()). Before the floor view reconciles a new
## observation, before() compares it with the one presented last and takes
## every departing body out of its seat first, into the sorted root as a
## ghost, so nothing the reconcile does to a seat (vacate, rebind, reuse, free)
## can reach it. A body that stays with its seat (seated, arriving, going to the
## pantry or back, changing seats) remains that seat's `Actor` and walks in the seat's own
## coordinates; the seat leaves it alone while `walking` (OfficeStation). A
## ghost has no plate, no badge, no card and nothing to click.
##
## Every change to a body's target bumps its generation, and a walk carries the
## generation and identity it was started for: one that no longer matches is
## never finished; the body is placed where it belongs. A departure while
## arriving turns the same body round; an arrival for a pane and identity whose
## ghost is still walking out takes that ghost back. A provider that changes
## (both known) is a departure and an arrival; a new terminal or session of the
## same provider walks nobody.
##
## When the floor's plan changes under people walking, a walk whose way on is
## still clear and whose end did not move is kept; every other walker is routed
## again from where it stands, with one search from its goal that serves both
## of its ways onto the graph. That routing is budgeted per observation
## (routing_budget, in OfficeWalkGraph.expanded) and done cheapest first:
## arrivals, read off the door's field, then ghosts, oldest first, then everyone
## else, as first seen. Once the budget is spent, whoever is left to route is
## placed where they belong.
##
## Placed, not walked (everyone is where they belong at once, and ghosts are
## gone): every observation of a new floor view (a new floor, a theme), the
## first one after the shown machine was stale, the first after a refresh whose
## input could not be laid out (lose_track()); and one person at a time,
## whoever has no clear way there, stands inside an obstacle when the floor
## changes, would need longer than LONGEST_WALK at TOP_SPEED, or is left over
## when the routing budget is spent. While the machine is stale every walker
## freezes where it is, walk animation, remaining route and time alike, and
## there are no ghosts; what an observation changes meanwhile is placed, not
## walked. The walkers stay frozen after the machine is back until an
## observation is presented, which is placed like any after an outage.
##
## Bodies are placed along their route each frame, never moved by physics: the
## validator's routes may touch an obstacle's edge, and a walker's feet would
## catch on it. The leftover distance of a frame carries over the waypoints, so
## a minimized window's 8 frames a second stay on the route.

## At this speed, in units a second, the walk track's own pace matches the
## ground it covers; nobody walks slower.
const WALK_SPEED := 96.0
## Nobody walks faster: five times the walk track's own pace.
const TOP_SPEED := 5.0 * WALK_SPEED
## No walk takes longer than this many seconds: a longer route is walked
## faster, up to TOP_SPEED; one too long even for that is not walked at all.
const LONGEST_WALK := 6.0
## How many ghosts may be on their way out at once; beyond it the oldest is gone.
## They are not in OfficeDeskView.node_budget(): 6 nodes each, outside the desks.
const MAX_GHOSTS := 32
## Graph work (OfficeWalkGraph.expanded) one observation may spend routing. At
## about half a microsecond a node on the development machine, the worst
## stress-fixture pass (a table grows and widens the floor under 47 walkers)
## routes in under 10 ms with it.
const ROUTING_BUDGET := 12000
## How near a corner a walker has to get to have turned it.
const AT_CORNER := 0.001


## Where the worker of a pane seated on a plan belongs, in the floor's own
## coordinates (the sorted root's): worked out once for each plan, which never
## changes once it is drawn.
class Place:
	extends RefCounted
	var tab_key := ""
	var approach := Vector2.ZERO
	var seat := Vector2.ZERO
	## The corner a near seat's leg turns round the chair at (the table's
	## standing spot; nobody stands there).
	var spot := Vector2.ZERO
	## On the near side of the table, whose legs go round the chair.
	var near := false


## What one observation says about one pane's worker: who they are and where
## they belong.
class Sighting:
	extends RefCounted
	var key := ""
	var identity := ""
	var provider := ""
	## Their seat, which is theirs wherever they rest.
	var place: Place
	## Where they rest (OfficeRests.Rest): the seat, or away in the pantry, at
	## `at`, stepped up to from `approach`.
	var rest := OfficeRests.Rest.SEAT
	var at := Vector2.ZERO
	var approach := Vector2.ZERO

	func target() -> Vector2:
		if rest == OfficeRests.Rest.PANTRY:
			return at
		return place.seat

	func tab_key() -> String:
		return place.tab_key

	## Resting in the entry band, at the pantry.
	func in_band() -> bool:
		return rest == OfficeRests.Rest.PANTRY

	## From the approach's node to where they belong (see OfficeWalkGraph).
	func leg() -> PackedVector2Array:
		if rest == OfficeRests.Rest.PANTRY:
			return OfficeWalkGraph.leg_to_fixture(approach, at)
		return OfficeWalkGraph.leg_to_seat(place.approach, place.seat, place.spot, place.near)

	func same_place(other: Sighting) -> bool:
		return tab_key() == other.tab_key() and rest == other.rest and target() == other.target()

	## Another agent in the same pane: both providers known and different.
	func replaced_by(other: Sighting) -> bool:
		return not provider.is_empty() and not other.provider.is_empty() and provider != other.provider


## One body the presentation moves: a seat's worker, or a ghost on its way out.
class Walker:
	extends RefCounted
	var key := ""
	var identity := ""
	var provider := ""
	var generation := 0
	var body: PixelPerson
	## The seat this worker belongs to; null for a ghost.
	var station: OfficeStation
	var walk: Walk
	## Set by before() for after(): where the body is, and whether it needs a
	## route (`pending`: by its `ways`, each from `from` toward the graph, or in
	## at the door) or only a look at whether its walk still goes (`recheck`).
	var pending := false
	var recheck := false
	var from := Vector2.ZERO
	var ways: Array[PackedVector2Array] = []
	var at_door := false


## One route being walked, for the generation and identity it was started for.
class Walk:
	extends RefCounted
	var generation := 0
	var identity := ""
	var points := PackedVector2Array()
	var segment := 0
	var along := 0.0
	var speed := WALK_SPEED
	## How to get back onto the graph from either end of the route when a new
	## observation turns the walker round: from its start, the way it left
	## (empty from the door, whose threshold is on the route); from its end, out
	## along the leg it walks in by (a seat's or spot's to the approach, the
	## door's to its threshold). Neither end point is repeated.
	var head := PackedVector2Array()
	var tail := PackedVector2Array()
	## The leg it ends with (its target's, or the threshold and the door), to
	## tell whether a new plan moved where it goes.
	var end := PackedVector2Array()


static var _footprint := Rect2()
static var _footprint_read := false

## Graph work one observation may spend routing (see ROUTING_BUDGET); a test
## may lower it.
var routing_budget := ROUTING_BUDGET
## What the last observation that changed anything on the floor did with its
## people, for tools and tests: walks it started, walks the floor changed under
## that it kept, people it placed instead of walking (see the class comment),
## the graph work its routing spent and how long all that took, in µs.
var pass_walked := 0
var pass_kept := 0
var pass_placed := 0
var pass_expanded := 0
var pass_usec := 0
## Where the last observation rests everyone (OfficeRests.assign()).
var service := OfficeRests.Service.new()

## What was presented last.
var _seen: Dictionary[String, Sighting] = {}
var _frozen := false
## The machine is back, but no observation has been presented since.
var _thawing := false
## The machine was stale since the last live observation: the next is cold.
var _outage := false
## The next pass is cold (see the class comment).
var _cold := true
## The seats' walkers, by pane key, and the ghosts, oldest first.
var _walkers: Dictionary[String, Walker] = {}
var _ghosts: Array[Walker] = []
var _serial := 0
var _sorted: Node2D
var _canvas := Rect2()
var _plan: FloorPlan
## Every seated pane's place on _places_plan (see places()).
var _places: Dictionary[String, Place] = {}
var _places_plan: FloorPlan
## One pass, from before() to after().
var _in_pass := false
var _now: Dictionary[String, Sighting] = {}
var _pass_cold := false
var _plan_changed := false
var _arrivals := PackedStringArray()
var _moving_seat: Dictionary[String, Walker] = {}
var _landing: Array[OfficeStation] = []
## sightings() found every pane just as it was seen last, and no other.
var _unchanged := false
## OfficeWalkGraph.expanded when this pass began routing.
var _pass_start := 0
## This pass changes nothing on the floor: everyone where they were seen, on
## the same plan. It leaves the pass counters as they were.
var _quiet := false


## `sorted` is the floor's y-sorted root, where ghosts walk; `people` the family
## the floor's people are drawn from, whose canvas the walls keep clear of.
func setup(sorted: Node2D, people: PixelPeople) -> void:
	_sorted = sorted
	_canvas = PixelPerson.drawing_rect(people)
	if not _footprint_read:
		_footprint = PixelPerson.footprint()
		_footprint_read = true


## Where the worker of every pane `plan` seats belongs, by pane key.
static func places(plan: FloorPlan) -> Dictionary[String, Place]:
	var found: Dictionary[String, Place] = {}
	for desk in plan.desks:
		for seat in desk.seats:
			var place := Place.new()
			place.tab_key = desk.tab_key
			place.near = seat.side == "near"
			place.approach = desk.origin + desk.measure.approach_position(seat.column, seat.side)
			place.seat = desk.origin + desk.measure.seat_position(seat.column, seat.side)
			place.spot = desk.origin + desk.measure.standing_position(seat.column, seat.side)
			found[seat.pane_key] = place
	return found


## Every pane with a worker on `plan`'s floor and where they belong. A shell has
## nobody; a pane the model carries twice is the rebuild's to draw. A pane seen
## the same as last time keeps its sighting, so a refresh that changes nothing
## on the floor makes nothing new.
func sightings(plan: FloorPlan, model: ZoneModel) -> Dictionary[String, Sighting]:
	if plan != _places_plan:
		_places = places(plan)
		_places_plan = plan
	var found: Dictionary[String, Sighting] = {}
	var repeated: Dictionary[String, bool] = {}
	var reused := 0
	service = OfficeRests.assign(plan, model)
	for room in model.rooms:
		for pane in room.panes:
			if pane.provider.is_empty() and not pane.starting:
				continue
			var place: Place = _places.get(pane.key)
			if place == null:
				continue
			if found.has(pane.key):
				repeated[pane.key] = true
				continue
			var rest: OfficeRests.Place = service.places.get(pane.key, OfficeRests.Place.new())
			var at := Vector2.ZERO
			var approach := Vector2.ZERO
			var fixture := plan.pantry
			if rest.away() and fixture != null:
				at = fixture.spots[rest.index]
				approach = fixture.approaches[rest.index]
			var identity := pane.identity_key()
			var seen: Sighting = _seen.get(pane.key)
			if (
				seen != null
				and seen.place == place
				and seen.rest == rest.rest
				and seen.at == at
				and seen.identity == identity
				and seen.provider == pane.provider
			):
				found[pane.key] = seen
				reused += 1
				continue
			var sighting := Sighting.new()
			sighting.key = pane.key
			sighting.identity = identity
			sighting.provider = pane.provider
			sighting.rest = rest.rest
			sighting.at = at
			sighting.approach = approach
			sighting.place = place
			found[pane.key] = sighting
	for key in repeated:
		found.erase(key)
	_unchanged = repeated.is_empty() and reused == found.size() and found.size() == _seen.size()
	return found


## The shown machine went stale (`stale`) or came back. Stale: every ghost is
## gone and every walker stops where it is; the floor view pauses their
## animation. Back: the walkers stay where they stopped, animation and all,
## until the next observation is presented, which places everyone.
func freeze(stale: bool) -> void:
	if stale:
		if not _frozen:
			_drop_ghosts()
		_frozen = true
		_thawing = false
		_outage = true
	elif _frozen:
		_frozen = false
		_thawing = true


## Whether the walkers are held still: the machine is stale, or has come back
## and nothing has been presented since.
func holding() -> bool:
	return _frozen or _thawing


## A refresh could not lay out its input, so the floor was not updated: the
## next observation brings everything that changed meanwhile at once, cold.
func lose_track() -> void:
	_cold = true


## Walk everyone `delta` seconds further. Nothing moves while the walkers are
## held (see holding()).
func walk(delta: float) -> void:
	if holding() or delta <= 0.0:
		return
	for walker in _moving():
		if walker.walk != null:
			_advance(walker, walker.walk.speed * delta)


## Walk every walk to its end, through the same steps as walk() and the same
## landing: a seat's worker sits at their seat or stands in the pantry, a ghost
## leaves by the door. For tools and tests that compare the floor with a
## rebuild, which never walks anyone. Unlike walk(), it ends the walks of a
## stale machine's frozen walkers too.
func settle() -> void:
	for attempt in 8:
		var moving := _moving()
		if moving.is_empty():
			return
		for walker in moving:
			_advance(walker, INF)


## Every body on its way somewhere now: seats' workers first, then ghosts.
func walkers() -> Array[PixelPerson]:
	var found: Array[PixelPerson] = []
	for walker in _moving():
		found.append(walker.body)
	return found


## The departing workers still on their way out, oldest first.
func ghosts() -> Array[PixelPerson]:
	var found: Array[PixelPerson] = []
	for ghost in _ghosts:
		if is_instance_valid(ghost.body):
			found.append(ghost.body)
	return found


## Whether the worker of pane `key` is on their way somewhere.
func is_walking(key: String) -> bool:
	var walker: Walker = _walkers.get(key)
	return walker != null and walker.walk != null


## The route `body` walks now, in the floor's coordinates; empty at rest.
func route_of(body: PixelPerson) -> PackedVector2Array:
	var walker := _walker_of(body)
	return walker.walk.points if walker != null and walker.walk != null else PackedVector2Array()


## How fast `body` walks now, in units a second; 0 at rest.
func speed_of(body: PixelPerson) -> float:
	var walker := _walker_of(body)
	return walker.walk.speed if walker != null and walker.walk != null else 0.0


## Before the floor view reconciles `next` for `model`: take every departing
## worker out as a ghost, and hold every worker who will walk where they are.
func before(view: OfficeFloorView, next: FloorPlan, model: ZoneModel, frozen: bool) -> void:
	if frozen:
		freeze(true)
	else:
		_frozen = false
		_thawing = false
	_in_pass = true
	_now = sightings(next, model)
	_pass_cold = _cold or (_outage and not frozen)
	_plan_changed = next != _plan
	_quiet = not _pass_cold and _unchanged and not _plan_changed
	_arrivals.clear()
	_moving_seat.clear()
	_landing.clear()
	if _quiet:
		# Everyone where they were seen, on the same floor: walks go on.
		return
	pass_walked = 0
	pass_kept = 0
	pass_placed = 0
	pass_expanded = 0
	pass_usec = 0
	if _pass_cold:
		_drop_ghosts()
		for key in _walkers:
			var station := _walkers[key].station
			if is_instance_valid(station):
				# The seat poses them again; land() below catches the rest.
				station.walking = false
				_landing.append(station)
		_walkers.clear()
		return
	for key in _seen:
		var gone: Sighting = _now.get(key)
		if gone == null or _seen[key].replaced_by(gone):
			_depart(view, key, _seen[key])
	for key in _now:
		var was: Sighting = _seen.get(key)
		if was == null or was.replaced_by(_now[key]):
			if not _frozen:
				_arrivals.append(key)
		else:
			_stay(view, key, was, _now[key])
	if _plan_changed and not _frozen:
		for ghost in _ghosts:
			if not ghost.pending:
				ghost.recheck = true
				ghost.from = ghost.body.position


## After the floor view reconciled: every seat is where the new observation
## puts it. Hand workers changing tables to their new seats, take ghosts back
## for panes that came back, and keep every held worker where they were.
func placed(view: OfficeFloorView) -> void:
	if not _in_pass or _pass_cold:
		return
	for key in _moving_seat:
		var walker := _moving_seat[key]
		var station := _station(view, key)
		if station == null:
			_free(walker.body)
			continue
		station.adopt_worker(walker.body)
		walker.station = station
		_walkers[key] = walker
	for key in _arrivals:
		var station := _station(view, key)
		if station == null:
			continue
		var ghost := _ghost_of(key, _now[key].identity)
		if ghost != null:
			_ghosts.erase(ghost)
			if not ghost.pending:
				_hold(ghost, ghost.body.position)
			station.adopt_worker(ghost.body)
			ghost.station = station
			ghost.generation += 1
			_walkers[key] = ghost
		else:
			# furnish() makes the worker; after() walks them in from the door.
			station.walking = true
	for key: String in _walkers:
		var walker := _walkers[key]
		if (walker.pending or walker.recheck) and is_instance_valid(walker.station):
			walker.body.position = walker.from - walker.station.position


## After the floor view furnished every seat: keep, route or place everyone the
## observation moved, and remember it as the one presented.
func after(view: OfficeFloorView, frozen: bool) -> void:
	if not _in_pass:
		return
	_in_pass = false
	# What hangs over everyone hangs where they rest, from this observation on;
	# whoever is not walking is put there too.
	for key in _now:
		var resting := _station(view, key)
		if resting != null:
			resting.rest_at(_now[key].rest, _now[key].target())
	if _quiet:
		_commit(view, frozen)
		return
	var began := Time.get_ticks_usec()
	if _pass_cold:
		for station in _landing:
			if is_instance_valid(station) and station.actor() != null:
				station.land()
				pass_placed += 1
				if not frozen:
					# A walker the outage stopped stood paused; the seat plays on.
					station.actor().play()
		pass_usec = Time.get_ticks_usec() - began
		_commit(view, frozen)
		return
	if _frozen:
		# Held only to stay where they stood: nobody sets off while stale.
		for key in _walkers:
			_walkers[key].pending = false
			_walkers[key].recheck = false
		_commit(view, frozen)
		return
	var graph: OfficeWalkGraph = null
	if view.plan != null and (not _arrivals.is_empty() or not _walkers.is_empty() or not _ghosts.is_empty()):
		graph = _graph(view.plan)
		_pass_start = graph.expanded
	for key: String in _walkers.keys():
		if _walkers[key].recheck:
			var still: Sighting = _now.get(key)
			_recheck(_walkers[key], graph, still)
	for ghost: Walker in _ghosts.duplicate():
		if ghost.recheck:
			_recheck(ghost, graph, null)
	for key in _arrivals:
		var station := _station(view, key)
		if station == null or _walkers.has(key):
			continue
		if station.actor() == null:
			station.walking = false
			continue
		var walker := Walker.new()
		walker.key = key
		walker.identity = _now[key].identity
		walker.provider = _now[key].provider
		walker.body = station.actor()
		walker.station = station
		walker.pending = true
		walker.at_door = true
		_walkers[key] = walker
	# Off the door's field first, which costs a route read and no search; the
	# searches after, while the budget lasts.
	for key: String in _walkers.keys():
		if _walkers[key].pending and _walkers[key].at_door:
			var arriving: Sighting = _now.get(key)
			_route(_walkers[key], graph, arriving)
	for ghost: Walker in _ghosts.duplicate():
		if ghost.pending:
			_route(ghost, graph, null)
	for key: String in _walkers.keys():
		if _walkers[key].pending:
			var now: Sighting = _now.get(key)
			_route(_walkers[key], graph, now)
	if graph != null:
		pass_expanded = graph.expanded - _pass_start
	pass_usec = Time.get_ticks_usec() - began
	_commit(view, frozen)


func _commit(view: OfficeFloorView, frozen: bool) -> void:
	_seen = _now
	_now = {}
	_cold = false
	if not frozen:
		_outage = false
	_plan = view.plan


## Pane `key`'s worker, seen as `was`, is leaving: out of the seat as a ghost,
## off to the door from wherever they are. While the machine is stale there
## are no ghosts: the seat lets them go as it always did.
func _depart(view: OfficeFloorView, key: String, was: Sighting) -> void:
	var walker: Walker = _walkers.get(key)
	_walkers.erase(key)
	var station := _station(view, key)
	if station == null or station.actor() == null:
		return
	if _frozen:
		station.walking = false
		return
	var body := station.actor()
	var from := station.position + body.position
	if walker == null:
		walker = _walker_for(key, was, body)
	_hold(walker, from, was)
	station.release_worker()
	_serial += 1
	body.name = "Ghost%d" % _serial
	_sorted.add_child(body)
	body.position = from
	walker.station = null
	walker.identity = was.identity
	walker.provider = was.provider
	walker.generation += 1
	_ghosts.append(walker)
	while _ghosts.size() > MAX_GHOSTS:
		var oldest: Walker = _ghosts.pop_front()
		_free(oldest.body)


## Pane `key`'s worker stays on the floor, seen as `was` then and `now` now:
## walk them if where they belong moved, and look again at a walk the floor
## changed under.
func _stay(view: OfficeFloorView, key: String, was: Sighting, now: Sighting) -> void:
	var walker: Walker = _walkers.get(key)
	if was == now and (walker == null or not _plan_changed):
		return
	if walker != null and walker.identity != now.identity:
		# A new terminal or session of the same agent: nothing to see.
		walker.identity = now.identity
		walker.generation += 1
		if walker.walk != null:
			walker.walk.identity = walker.identity
			walker.walk.generation = walker.generation
	var moved := not was.same_place(now)
	if not moved and (walker == null or not _plan_changed):
		return
	var station := _station(view, key)
	if station == null or station.actor() == null:
		return
	var body := station.actor()
	var from := station.position + body.position
	if _frozen:
		if walker != null and was.tab_key() == now.tab_key():
			# A frozen walker stays where they stood, wherever their seat went.
			walker.from = from
			walker.pending = true
		elif walker != null:
			station.walking = false
			_walkers.erase(key)
		return
	if not moved:
		# Same place, a new floor under the walk: after() keeps it if it still goes.
		walker.recheck = true
		walker.from = from
		return
	if walker == null:
		walker = _walker_for(key, now, body)
		walker.station = station
		_walkers[key] = walker
	walker.generation += 1
	_hold(walker, from, was)
	station.walking = true
	if was.tab_key() != now.tab_key():
		# Another table's seat: out of this one before the reconcile vacates it.
		station.release_worker()
		_sorted.add_child(body)
		body.position = from
		walker.station = null
		_walkers.erase(key)
		_moving_seat[key] = walker


## Remember where `walker` is and every way it can leave from there, for
## after() to route on the new plan: along its route in either direction while
## it walks, back along its leg (`was`) while it rests.
func _hold(walker: Walker, from: Vector2, was: Sighting = null) -> void:
	walker.pending = true
	walker.recheck = false
	walker.at_door = false
	walker.from = from
	walker.ways.clear()
	if walker.walk != null:
		var trip := walker.walk
		var back := PackedVector2Array([from])
		for index in range(trip.segment, -1, -1):
			back.append(trip.points[index])
		back.append_array(trip.head)
		var on := PackedVector2Array([from])
		for index in range(trip.segment + 1, trip.points.size()):
			on.append(trip.points[index])
		on.append_array(trip.tail)
		walker.ways.append(back)
		walker.ways.append(on)
	elif was != null:
		var leg := was.leg()
		leg.reverse()
		var out := PackedVector2Array([from])
		out.append_array(leg)
		walker.ways.append(out)


## The floor changed under `walker`'s walk, which still goes where it belongs
## (`now`; a ghost's, with `now` null, to the door): keep the walk, from where
## the walker stands, when its end is where it was and all it has left to walk
## is still clear; route it again otherwise.
func _recheck(walker: Walker, graph: OfficeWalkGraph, now: Sighting) -> void:
	walker.recheck = false
	var trip := walker.walk
	if trip == null:
		return
	var rest := PackedVector2Array([walker.from])
	for index in range(trip.segment + 1, trip.points.size()):
		rest.append(trip.points[index])
	var end := now.leg() if now != null else PackedVector2Array()
	if now == null and graph != null:
		end = PackedVector2Array([graph.threshold, graph.door])
	if graph == null or trip.end != end or not graph.clear_route(rest):
		_hold(walker, walker.from)
		return
	var walked := PackedVector2Array()
	for index in range(trip.segment, -1, -1):
		walked.append(trip.points[index])
	walked.append_array(trip.head)
	trip.points = OfficeWalkGraph.straighten(rest)
	trip.head = walked
	trip.segment = 0
	trip.along = 0.0
	pass_kept += 1


## Route a held `walker` on `graph` to where `now` says it belongs (a ghost,
## with `now` null, to the door) and start walking; or place it there at once
## (see the class comment).
func _route(walker: Walker, graph: OfficeWalkGraph, now: Sighting) -> void:
	walker.pending = false
	var budget := routing_budget - (graph.expanded - _pass_start) if graph != null else 0
	if graph == null or budget <= 0 or (now == null and walker.at_door):
		_place_now(walker)
		return
	var target := now.leg() if now != null else PackedVector2Array()
	var end := target if now != null else PackedVector2Array([graph.threshold, graph.door])
	# Out of the end: back along the leg walked in by.
	var tail := PackedVector2Array()
	if now != null:
		tail = target.duplicate()
		tail.reverse()
		tail.remove_at(0)
	else:
		tail.append(graph.threshold)
	var route := PackedVector2Array()
	var head := PackedVector2Array()
	if now != null and not walker.at_door and _lane_bound(walker, graph, now):
		var lane := _lane_route(walker, graph, now, target, budget)
		route = lane[0]
		head = lane[1]
	elif walker.at_door:
		# In at the door: read back off the door's field, which the validator
		# built (or, missing, is built now and charged); the read is charged too,
		# and not made for a route the field already says is too long.
		var goal := OfficeWalkGraph.cell_of(target[0])
		var steps := graph.door_distance(goal)
		var shortest := _field_route(graph, steps) - OfficeWalkGraph.length(target)
		if steps >= 0 and _may_walk(shortest) and steps + 1 <= routing_budget - (graph.expanded - _pass_start):
			route = graph.from_door(goal)
			route.append_array(target)
	elif not graph.inside(walker.from):
		var outs: Array[PackedVector2Array] = []
		var owners := PackedInt32Array()
		var ends: Array[Vector2i] = []
		var leads := PackedFloat32Array()
		var headings := PackedInt32Array()
		for index in walker.ways.size():
			var out := _to_node(walker.ways[index], graph)
			if out.is_empty() or not graph.clear_route(out):
				continue
			outs.append(out)
			owners.append(index)
			ends.append(OfficeWalkGraph.cell_of(out[out.size() - 1]))
			leads.append(OfficeWalkGraph.length(out))
			headings.append(OfficeWalkGraph.heading(out[out.size() - 2], out[out.size() - 1]) if out.size() > 1 else -1)
		var chosen := -1
		var middle := PackedVector2Array()
		if now == null:
			chosen = _nearest_to_door(graph, ends, leads)
			if chosen >= 0:
				var steps := graph.door_distance(ends[chosen])
				var shortest := _field_route(graph, steps) - leads[chosen]
				if not _may_walk(shortest) or steps + 1 > routing_budget - (graph.expanded - _pass_start):
					chosen = -1
			if chosen >= 0:
				middle = graph.to_door(ends[chosen], headings[chosen])
		elif not outs.is_empty():
			var reach := ceili((TOP_SPEED * LONGEST_WALK - OfficeWalkGraph.length(target)) / OfficeWalkGraph.GRID)
			var found := graph.route_between(OfficeWalkGraph.cell_of(target[0]), ends, leads, headings, budget, reach)
			chosen = found.end
			middle = found.points
		if chosen >= 0:
			route = outs[chosen].duplicate()
			route.append_array(middle)
			route.append_array(target)
			# Out of the start: the other way, or this one when there is no
			# other (from a seat or a spot, the only way out is its leg).
			var owner := owners[chosen]
			var other := walker.ways[1 - owner] if walker.ways.size() == 2 else walker.ways[owner]
			head = other.slice(1)
	walker.ways.clear()
	route = OfficeWalkGraph.straighten(route)
	if route.is_empty() or OfficeWalkGraph.length(route) > TOP_SPEED * LONGEST_WALK or not graph.clear_route(route):
		_place_now(walker)
		return
	_start(walker, route, head, tail, end)


## Whether `walker`'s walk to `now` goes by the walking lane instead of a
## search: when where they go is in the entry band (the pantry), or
## where they set off from is (every way they have ends on the lane).
static func _lane_bound(walker: Walker, graph: OfficeWalkGraph, now: Sighting) -> bool:
	if not is_finite(graph.walking_lane):
		return false
	if now.in_band():
		return true
	if walker.ways.is_empty():
		return false
	for way in walker.ways:
		var out := _to_node(way, graph)
		if out.is_empty() or out[out.size() - 1].y != graph.walking_lane:
			return false
	return true


## The route by the walking lane for a held `walker` to `target` (the leg of
## where `now` rests), and the way back out of its start, as [route, head]:
## out to the graph by whichever of its ways is shorter in all, then along the
## door's field to the lane, the lane, and the field from the lane in to a
## table. Empty when there is no such way or it would cost more than `budget`
## graph work.
func _lane_route(
	walker: Walker, graph: OfficeWalkGraph, now: Sighting, target: PackedVector2Array, budget: int
) -> Array[PackedVector2Array]:
	var none: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	var goal := OfficeWalkGraph.cell_of(target[0])
	var inward := PackedVector2Array()
	if not now.in_band():
		if graph.door_distance(goal) + 1 > budget:
			return none
		inward = graph.from_lane(goal)
		if inward.is_empty():
			return none
	var best := PackedVector2Array()
	var best_length := INF
	var chosen := -1
	for index in walker.ways.size():
		var out := _to_node(walker.ways[index], graph)
		if out.is_empty() or not graph.clear_route(out):
			continue
		var end := out[out.size() - 1]
		var route := out.duplicate()
		if now.in_band():
			if end.y != graph.walking_lane:
				var cell := OfficeWalkGraph.cell_of(end)
				if graph.door_distance(cell) + 1 > routing_budget - (graph.expanded - _pass_start):
					continue
				route.append_array(graph.to_lane(cell))
			route.append_array(target)
		else:
			if end.y != graph.walking_lane:
				continue
			route.append_array(inward)
			route.append_array(target)
		route = OfficeWalkGraph.straighten(route)
		var length := OfficeWalkGraph.length(route)
		if length < best_length:
			best = route
			best_length = length
			chosen = index
	if chosen < 0:
		return none
	var other := walker.ways[1 - chosen] if walker.ways.size() == 2 else walker.ways[chosen]
	return [best, other.slice(1)]


## How long the part of a route on the door's field is, between the door and
## a node `steps` from the threshold.
static func _field_route(graph: OfficeWalkGraph, steps: int) -> float:
	return graph.door.distance_to(graph.threshold) + steps * OfficeWalkGraph.GRID


## Whether a route no shorter than `shortest` units may be walked at all, told
## before it is read: straightened, a route only loses the steps it takes back
## along the same line, never more than twice the leg it joins the field by, so
## the field's part less that leg is a floor. The route read is checked exactly.
static func _may_walk(shortest: float) -> bool:
	return shortest <= TOP_SPEED * LONGEST_WALK


## Which of `ends` is the cheaper to walk out by, reaching it having walked
## `leads[i]` already; -1 when the door reaches none.
static func _nearest_to_door(graph: OfficeWalkGraph, ends: Array[Vector2i], leads: PackedFloat32Array) -> int:
	var chosen := -1
	var cost := INF
	for index in ends.size():
		var steps := graph.door_distance(ends[index])
		if steps >= 0 and steps * OfficeWalkGraph.GRID + leads[index] < cost:
			chosen = index
			cost = steps * OfficeWalkGraph.GRID + leads[index]
	return chosen


## `way` from its first point up to the first walkable node on it, the node
## included; empty when it passes none.
static func _to_node(way: PackedVector2Array, graph: OfficeWalkGraph) -> PackedVector2Array:
	var result := PackedVector2Array([way[0]])
	if _is_node(way[0], graph):
		return result
	for index in range(1, way.size()):
		for point in _centres_between(way[index - 1], way[index]):
			if _is_node(point, graph):
				result.append(point)
				return result
		result.append(way[index])
	return PackedVector2Array()


static func _is_node(point: Vector2, graph: OfficeWalkGraph) -> bool:
	var cell := OfficeWalkGraph.cell_of(point)
	return OfficeWalkGraph.centre(cell) == point and graph.walkable(cell)


## The node centres on the segment from `from` to `to`, in the order it passes
## them, `from` left out and `to` included when it is one.
static func _centres_between(from: Vector2, to: Vector2) -> PackedVector2Array:
	var found := PackedVector2Array()
	var grid := float(OfficeWalkGraph.GRID)
	var half := grid / 2.0
	if from.x == to.x and is_zero_approx(fposmod(from.x - half, grid)):
		var step := signf(to.y - from.y) * grid
		var at := (floorf((from.y - half) / grid) + (1.0 if step > 0 else 0.0)) * grid + half
		if step < 0 and at >= from.y:
			at -= grid
		while step != 0.0 and (at <= to.y if step > 0 else at >= to.y):
			found.append(Vector2(from.x, at))
			at += step
	elif from.y == to.y and is_zero_approx(fposmod(from.y - half, grid)):
		var step := signf(to.x - from.x) * grid
		var at := (floorf((from.x - half) / grid) + (1.0 if step > 0 else 0.0)) * grid + half
		if step < 0 and at >= from.x:
			at -= grid
		while step != 0.0 and (at <= to.x if step > 0 else at >= to.x):
			found.append(Vector2(at, from.y))
			at += step
	elif OfficeWalkGraph.centre(OfficeWalkGraph.cell_of(to)) == to:
		found.append(to)
	return found


## Walk `walker` along `points`, for its generation and identity, at least as
## fast as it already walked: at WALK_SPEED, faster when the route is longer
## than LONGEST_WALK allows, never faster than TOP_SPEED.
func _start(
	walker: Walker,
	points: PackedVector2Array,
	head: PackedVector2Array,
	tail: PackedVector2Array,
	end: PackedVector2Array
) -> void:
	var trip := Walk.new()
	trip.generation = walker.generation
	trip.identity = walker.identity
	trip.points = points
	trip.head = head
	trip.tail = tail
	trip.end = end
	trip.speed = maxf(WALK_SPEED, OfficeWalkGraph.length(points) / LONGEST_WALK)
	if walker.walk != null:
		trip.speed = maxf(trip.speed, walker.walk.speed)
	trip.speed = minf(trip.speed, TOP_SPEED)
	walker.walk = trip
	pass_walked += 1
	var body := walker.body
	body.stand_up()
	body.play_track(ArtContract.TRACK_WALK)
	body.pace(trip.speed / WALK_SPEED)
	_place(walker)
	if points.size() < 2:
		_finish(walker)


## Carry `walker` `distance` further along its route, the leftover of each
## segment into the next, and land it at the end. A walk no longer meant for
## this body (another generation or identity) is not walked on: the body is
## placed where it belongs.
func _advance(walker: Walker, distance: float) -> void:
	var trip := walker.walk
	if trip == null:
		return
	if trip.generation != walker.generation or trip.identity != walker.identity:
		_snap(walker)
		return
	if not is_instance_valid(walker.body) or (walker.station != null and not is_instance_valid(walker.station)):
		_forget(walker)
		return
	var left := distance
	while left > 0.0 and trip.segment < trip.points.size() - 1:
		var span := trip.points[trip.segment].distance_to(trip.points[trip.segment + 1])
		var rest := span - trip.along
		# Within a hair of a corner is at it, facing the next way.
		if left < rest - AT_CORNER:
			trip.along += left
			left = 0.0
		else:
			left -= rest
			trip.segment += 1
			trip.along = 0.0
	_place(walker)
	if trip.segment >= trip.points.size() - 1:
		_finish(walker)


## Put `walker`'s body where its walk has got to, facing the way it goes.
func _place(walker: Walker) -> void:
	var trip := walker.walk
	var point := trip.points[trip.segment]
	if trip.segment + 1 < trip.points.size():
		var heading := (trip.points[trip.segment + 1] - point).normalized()
		point += heading * trip.along
		_face(walker.body, heading)
	walker.body.position = point - (walker.station.position if walker.station != null else Vector2.ZERO)


static func _face(body: PixelPerson, heading: Vector2) -> void:
	var wanted := PixelPeople.FRONT
	if heading.x > 0.0:
		wanted = PixelPeople.RIGHT
	elif heading.x < 0.0:
		wanted = PixelPeople.LEFT
	elif heading.y < 0.0:
		wanted = PixelPeople.BACK
	if body.facing != wanted:
		body.face(wanted)


## The end of a walk: a seat's worker sits at their seat or stands in the
## pantry, a ghost is
## gone through the door.
func _finish(walker: Walker) -> void:
	walker.walk = null
	_snap(walker)


## Put `walker` where it belongs instead of walking it, and count it.
func _place_now(walker: Walker) -> void:
	pass_placed += 1
	_snap(walker)


## Put `walker` where it belongs without walking: its seat, or out.
func _snap(walker: Walker) -> void:
	walker.walk = null
	walker.pending = false
	walker.recheck = false
	if walker.station != null:
		if is_instance_valid(walker.station):
			walker.station.land()
		if _walkers.get(walker.key) == walker:
			_walkers.erase(walker.key)
	else:
		_ghosts.erase(walker)
		_free(walker.body)


func _forget(walker: Walker) -> void:
	walker.walk = null
	if _walkers.get(walker.key) == walker:
		_walkers.erase(walker.key)
	_ghosts.erase(walker)


func _drop_ghosts() -> void:
	for ghost in _ghosts:
		_free(ghost.body)
	_ghosts.clear()


func _walker_for(key: String, seen: Sighting, body: PixelPerson) -> Walker:
	var walker := Walker.new()
	walker.key = key
	walker.identity = seen.identity
	walker.provider = seen.provider
	walker.body = body
	return walker


## The most recent ghost of pane `key` with `identity`, or null.
func _ghost_of(key: String, identity: String) -> Walker:
	for index in range(_ghosts.size() - 1, -1, -1):
		var ghost := _ghosts[index]
		if ghost.key == key and ghost.identity == identity and is_instance_valid(ghost.body):
			return ghost
	return null


func _walker_of(body: PixelPerson) -> Walker:
	for walker in _moving():
		if walker.body == body:
			return walker
	return null


## Every walker with a walk, seats' workers first, then ghosts.
func _moving() -> Array[Walker]:
	var found: Array[Walker] = []
	for key in _walkers:
		if _walkers[key].walk != null:
			found.append(_walkers[key])
	for ghost in _ghosts:
		if ghost.walk != null:
			found.append(ghost)
	return found


func _graph(plan: FloorPlan) -> OfficeWalkGraph:
	return OfficeWalkGraph.of(plan, _footprint, _canvas)


static func _station(view: OfficeFloorView, key: String) -> OfficeStation:
	var seat := view.seat(key)
	return seat.node if seat != null else null


static func _free(body: PixelPerson) -> void:
	if not is_instance_valid(body):
		return
	if body.get_parent() != null:
		body.get_parent().remove_child(body)
	body.queue_free()
