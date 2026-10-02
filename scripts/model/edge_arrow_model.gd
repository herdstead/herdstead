class_name EdgeArrowModel
extends RefCounted
## One arrow on an edge of the world (OfficeEdgeArrows): a zone of the shown map
## with blocked desks off screen, which edge they lie beyond and where along
## it, and how many are waiting there. A click pans to its longest-waiting
## desk; it selects nothing. The office works the list out from the view and
## the map it drew (OfficeViewMarks); the arrows only draw it, folding what an
## edge has no room for (fit()).
##
## Pure: of() takes the view and the blocked desks as rectangles and waits, and
## fit() how many arrows each edge holds as numbers; neither asks a clock or a
## node.

## The edge of the view an arrow stands on.
enum Edge { TOP, RIGHT, BOTTOM, LEFT }

## How many arrows the HUD holds: past that many zones the last one is a `+N`
## note naming the rest (see of()).
const POOL := 8
## The arrow's glyph per edge: which way the desks are.
const GLYPHS: Dictionary[Edge, String] = {Edge.TOP: "↑", Edge.RIGHT: "→", Edge.BOTTOM: "↓", Edge.LEFT: "←"}


## One blocked desk on the shown, live machine's map.
class Target:
	extends RefCounted
	## The zone it sits in, that zone's number as its sign writes it (`3`, `3A`)
	## and the sign's words (`3 INFRA`).
	var zone_key := ""
	var number := ""
	var words := ""
	## The machine key its blocked badge pulses for (StatusBadge.pulse_for()).
	var machine := ""
	## The composite pane key (HerdrFleet.pane_key).
	var pane_key := ""
	## Its chip, or where the seat answers a click while it draws none, in the
	## view's coordinates.
	var rect := Rect2()
	## How long it has waited (StateLog.wait_of()).
	var wait := StateLog.Wait.new()


## The zone's key: the SPACES row a hover outlines.
var zone_key := ""
## The desk a click pans to: the zone's longest-waiting one off screen. Empty
## on the `+N` note, which is no way to any one of them.
var pane_key := ""
var machine := ""
## The zone's number as its sign writes it; `+N` on the note.
var number := ""
## Blocked desks of that zone that are off screen; always more than zero.
var blocked := 0
## The edge its longest-waiting off-screen desk lies beyond, and where along
## that edge: 0 at its left or top end, 1 at its right or bottom end.
var edge := Edge.RIGHT
var along := 0.5
## `3 INFRA · 2 blocked · longest 12m`; on the note, one such line per zone it stands for.
var tip := ""
## Zones this arrow stands for beyond its own: more than zero only on the `+N` note.
var more := 0
## The longest wait among its off-screen desks, which the list is sorted by.
var wait := StateLog.Wait.new()


## The arrows for `targets` seen through `view`: a zone gets one when at least
## one of its blocked desks' rectangles does not meet the view, on the edge
## crossed by the line from the view's centre to its longest-waiting such desk.
## Longest wait first (a tie keeps the targets' order); past POOL zones, the
## last arrow is a note counting the rest, standing where the first of them would.
static func of(view: Rect2, targets: Array[Target]) -> Array[EdgeArrowModel]:
	var by_zone: Dictionary[String, EdgeArrowModel] = {}
	var found: Array[EdgeArrowModel] = []
	var words: Dictionary[String, String] = {}
	for target in targets:
		if target.rect.intersects(view):
			continue
		var arrow: EdgeArrowModel = by_zone.get(target.zone_key)
		if arrow == null:
			arrow = EdgeArrowModel.new()
			arrow.zone_key = target.zone_key
			arrow.machine = target.machine
			arrow.number = target.number
			words[target.zone_key] = target.words
			by_zone[target.zone_key] = arrow
			found.append(arrow)
		arrow.blocked += 1
		if arrow.pane_key.is_empty() or target.wait.msec > arrow.wait.msec:
			arrow.pane_key = target.pane_key
			arrow.wait = target.wait
			arrow.edge = edge_toward(view, target.rect)
			arrow.along = along_toward(view, target.rect)
	var order: Dictionary[EdgeArrowModel, int] = {}
	for index in found.size():
		order[found[index]] = index
	found.sort_custom(
		func(a: EdgeArrowModel, b: EdgeArrowModel) -> bool:
			if a.wait.msec != b.wait.msec:
				return a.wait.msec > b.wait.msec
			return order[a] < order[b]
	)
	for arrow in found:
		arrow.tip = "%s · %d blocked · longest %s" % [words[arrow.zone_key], arrow.blocked, _wait_words(arrow.wait)]
	if found.size() <= POOL:
		return found
	var note := EdgeArrowModel.new()
	for arrow: EdgeArrowModel in found.slice(POOL - 1):
		note._count(arrow)
	var shown: Array[EdgeArrowModel] = []
	shown.assign(found.slice(0, POOL - 1))
	shown.append(note)
	return shown


## `arrows` (of()'s, longest wait first) for edges that hold only so many:
## `room` says how many arrows an edge has room for, and an edge it does not
## name holds all of its own. An edge with more than its room keeps the first
## of them, and its last place goes to a `+N` note for the rest: standing where
## the first of them would, counting them, their lines in its tooltip, in the
## list where the first of them was. An edge with room for none shows none.
## of()'s own note is folded like an arrow and counts for the zones it stands
## for. Per edge, so that a note still stands on the side its zones lie on.
static func fit(arrows: Array[EdgeArrowModel], room: Dictionary[Edge, int]) -> Array[EdgeArrowModel]:
	var wanted: Dictionary[Edge, int] = {}
	for arrow in arrows:
		wanted[arrow.edge] = wanted.get(arrow.edge, 0) + 1
	var shown: Array[EdgeArrowModel] = []
	var placed: Dictionary[Edge, int] = {}
	var notes: Dictionary[Edge, EdgeArrowModel] = {}
	for arrow in arrows:
		var holds: int = room.get(arrow.edge, wanted[arrow.edge])
		var before: int = placed.get(arrow.edge, 0)
		placed[arrow.edge] = before + 1
		if wanted[arrow.edge] <= holds or before < holds - 1:
			shown.append(arrow)
		elif holds > 0:
			if not notes.has(arrow.edge):
				notes[arrow.edge] = EdgeArrowModel.new()
				shown.append(notes[arrow.edge])
			notes[arrow.edge]._count(arrow)
	return shown


## The edge of `view` crossed by the line from its centre to `rect`'s centre.
static func edge_toward(view: Rect2, rect: Rect2) -> Edge:
	var reach := _reach(view, rect)
	var toward := rect.get_center() - view.get_center()
	if reach.x <= reach.y:
		return Edge.RIGHT if toward.x > 0.0 else Edge.LEFT
	return Edge.BOTTOM if toward.y > 0.0 else Edge.TOP


## Where along that edge the line crosses it: 0 at the edge's left or top end,
## 1 at its right or bottom end.
static func along_toward(view: Rect2, rect: Rect2) -> float:
	var reach := _reach(view, rect)
	var toward := rect.get_center() - view.get_center()
	var crossing := view.get_center() + toward * minf(reach.x, reach.y)
	if not view.has_area():
		return 0.5
	if reach.x <= reach.y:
		return clampf((crossing.y - view.position.y) / view.size.y, 0.0, 1.0)
	return clampf((crossing.x - view.position.x) / view.size.x, 0.0, 1.0)


## Everything that decides what the arrows draw: a list drawn for one
## signature is handed to the HUD again only for another.
func signature() -> String:
	return "%s|%s|%s|%d|%d|%.4f|%s" % [zone_key, pane_key, number, blocked, edge, along, tip]


## How far along the line from `view`'s centre to `rect`'s centre the view's
## vertical edges (x) and horizontal edges (y) are crossed, as a share of the
## line; INF for a line that never crosses that pair.
static func _reach(view: Rect2, rect: Rect2) -> Vector2:
	var toward := rect.get_center() - view.get_center()
	var half := view.size / 2.0
	return Vector2(
		INF if is_zero_approx(toward.x) else half.x / absf(toward.x),
		INF if is_zero_approx(toward.y) else half.y / absf(toward.y)
	)


## Count `arrow` (a zone's, or another note) in this `+N` note: the first one
## counted says where the note stands and how long it has waited.
func _count(arrow: EdgeArrowModel) -> void:
	if more == 0:
		machine = arrow.machine
		edge = arrow.edge
		along = arrow.along
		wait = arrow.wait
	var line := arrow.tip if arrow.more > 0 else "%s %s" % [GLYPHS[arrow.edge], arrow.tip]
	tip = line if more == 0 else tip + "\n" + line
	more += maxi(arrow.more, 1)
	blocked += arrow.blocked
	number = "+%d" % more


## A wait in the HUD's words (OfficeAttention.wait_text()): `12m`, `5s+`.
static func _wait_words(waited: StateLog.Wait) -> String:
	return OfficeAttention.wait_text(waited)
