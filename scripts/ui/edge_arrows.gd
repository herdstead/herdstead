class_name OfficeEdgeArrows
extends Control
## The arrows on the world's edges (scenes/ui/edge_arrows.tscn): one per zone of
## the shown map with blocked desks off screen (the office's EdgeArrowModel
## list, longest wait first), standing on the edge those desks lie beyond. A
## click on one pans to its desk and selects nothing; hovering one outlines its
## zone's SPACES row. Another machine's blocked agents are not here: the rail
## counts them.
##
## The HUD lays this control over world_rect() and shows it while there are
## arrows and nothing covers the world (OfficeHud._fit_edge_arrows()). It takes
## no mouse itself: only the arrows do, so the world under the rest of it is
## panned and clicked as ever.
##
## A fixed set of EdgeArrowModel.POOL nodes in the scene: a refresh or a pan
## only writes text, visibility and where each stands. An arrow stands at
## `along` of its edge, kept inside by the theme's `inset` and clear of its
## neighbours by its `gap`; the corners belong to the top and bottom edges.
##
## No two arrows ever meet, and none leaves this control: an edge shows as many
## as it has room for between its ends, by the arrows' own sizes, and folds the
## rest, the ones that waited least, into a `+N` note on that edge
## (EdgeArrowModel.fit()). What was handed is kept whole, so the fold follows
## the room: a wider world or full arrows after compact ones bring them back.

## An arrow was pressed: pan to the desk of pane `pane_key`.
signal arrow_picked(pane_key: String)
## The mouse came onto an arrow for zone `zone_key` (`""` for the `+N` note),
## or left it (`""`); or what stands under a resting mouse changed: the arrow
## there was handed another zone, another arrow took its place, it went
## (`""`), or one came (back) under it.
signal zone_pointed(zone_key: String)

## What the office handed last (show_arrows()), all of it.
var _handed: Array[EdgeArrowModel] = []
## What the arrows shown now were drawn from, in the nodes' order: `_handed`,
## folded for the room each edge has (_arrange()).
var _models: Array[EdgeArrowModel] = []
var _compact := false
## The zone said last (zone_pointed): what stands under the mouse is said
## again only when it is another.
var _said := ""
## The viewport is being asked what the mouse is on (_on_an_arrow()): its
## answer may arrange the arrows again, and is not asked for twice at once.
var _asking := false


func _ready() -> void:
	for arrow in _nodes():
		arrow.picked.connect(_on_picked)
		arrow.mouse_entered.connect(_on_entered.bind(arrow))
		arrow.mouse_exited.connect(_on_exited)
	resized.connect(_arrange)
	visibility_changed.connect(_say_pointed)


## Take the pack's art in every arrow; a theme switch rebuilds nothing.
func dress(art: ArtPack) -> void:
	for arrow in _nodes():
		arrow.dress(art)
	_arrange()


## Draw `arrows`, in order, one node each (the office never hands more than the
## scene holds: EdgeArrowModel.of() folds the rest into its last one), as far
## as their edges have room (_arrange()), and hide the nodes past them. Whether
## the control shows at all is the HUD's.
func show_arrows(arrows: Array[EdgeArrowModel]) -> void:
	_handed.assign(arrows.slice(0, _nodes().size()))
	_arrange()


## Leave each zone's number to its arrow's tooltip (`on`): a narrow world's arrows.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	for arrow in _nodes():
		arrow.set_compact(on)
	_arrange()


## The arrows shown now, longest wait first.
func shown() -> Array[OfficeEdgeArrow]:
	var found: Array[OfficeEdgeArrow] = []
	for arrow in _nodes():
		if arrow.visible:
			found.append(arrow)
	return found


## The models the arrows shown were drawn from, in the same order.
func models() -> Array[EdgeArrowModel]:
	return _models


## Draw what was handed in the room there is now, and stand each arrow on its
## edge. Measured, not reckoned: the arrows are written into the nodes, each
## edge's are added up along its run, and an edge they overflow is given one
## fewer (EdgeArrowModel.fit() folds the rest into its note, whose own width
## counts) until every edge holds its own. Then the zone under a resting mouse
## is said again if it is another now (_say_pointed()).
func _arrange() -> void:
	var nodes := _nodes()
	var room: Dictionary[EdgeArrowModel.Edge, int] = {}
	# An edge loses one each time round, so the pool bounds the tries.
	for _attempt in nodes.size() + 1:
		_models = EdgeArrowModel.fit(_handed, room)
		for index in nodes.size():
			if index < _models.size():
				nodes[index].show_arrow(_models[index])
			elif nodes[index].visible:
				nodes[index].hide_arrow()
		var short := _overflowing(nodes)
		if short.is_empty():
			break
		room.merge(short, true)
	_place(nodes)
	_say_pointed()


## The edges whose arrows, with the gaps between them, are longer than the
## edge's run: each with one fewer than it holds now.
func _overflowing(nodes: Array[OfficeEdgeArrow]) -> Dictionary[EdgeArrowModel.Edge, int]:
	var gap := float(get_theme_constant(&"gap", &"EdgeArrows"))
	var short: Dictionary[EdgeArrowModel.Edge, int] = {}
	for edge: EdgeArrowModel.Edge in EdgeArrowModel.GLYPHS:
		var on_edge := _on_edge(edge)
		if on_edge.is_empty():
			continue
		var run := _run(edge, nodes[on_edge[0]])
		var taken := -gap
		for index in on_edge:
			taken += _long(edge, nodes[index]) + gap
		if taken > run.y - run.x:
			short[edge] = on_edge.size() - 1
	return short


## Stand every arrow shown on its edge. Along an edge they go in `along` order,
## each at its own place when that is free, pushed on by the one before it and
## back by the edge's end; _arrange() has seen to it that they fit. The side
## edges leave the top and bottom rows to the arrows there, so no two ever
## share a corner.
func _place(nodes: Array[OfficeEdgeArrow]) -> void:
	var inset := float(get_theme_constant(&"inset", &"EdgeArrows"))
	var gap := float(get_theme_constant(&"gap", &"EdgeArrows"))
	for edge: EdgeArrowModel.Edge in EdgeArrowModel.GLYPHS:
		var on_edge := _on_edge(edge)
		if on_edge.is_empty():
			continue
		var across := _across(edge)
		var span := size.x if across else size.y
		var run := _run(edge, nodes[on_edge[0]])
		var starts := PackedFloat32Array()
		var from := run.x
		for index in on_edge:
			var start := maxf(_models[index].along * span - _long(edge, nodes[index]) / 2.0, from)
			starts.append(start)
			from = start + _long(edge, nodes[index]) + gap
		var limit := run.y
		for at in range(on_edge.size() - 1, -1, -1):
			var node := nodes[on_edge[at]]
			starts[at] = maxf(minf(starts[at], limit - _long(edge, node)), run.x)
			limit = starts[at] - gap
			var along := roundf(starts[at])
			match edge:
				EdgeArrowModel.Edge.TOP:
					node.position = Vector2(along, inset)
				EdgeArrowModel.Edge.BOTTOM:
					node.position = Vector2(along, size.y - inset - node.size.y)
				EdgeArrowModel.Edge.LEFT:
					node.position = Vector2(inset, along)
				EdgeArrowModel.Edge.RIGHT:
					node.position = Vector2(size.x - inset - node.size.x, along)


## The models' places in `_models` (and so the nodes') that stand on `edge`, in
## `along` order.
func _on_edge(edge: EdgeArrowModel.Edge) -> Array[int]:
	var on_edge: Array[int] = []
	for index in _models.size():
		if _models[index].edge == edge:
			on_edge.append(index)
	on_edge.sort_custom(func(a: int, b: int) -> bool: return _models[a].along < _models[b].along)
	return on_edge


## Where the arrows on `edge` may stand along it, from `x` to `y`: the theme's
## inset in from both ends, and on a side edge the rows along the top and the
## bottom, which are the arrows' there (a row is as high as `arrow`, one of its
## own, and the gap).
func _run(edge: EdgeArrowModel.Edge, arrow: OfficeEdgeArrow) -> Vector2:
	var inset := float(get_theme_constant(&"inset", &"EdgeArrows"))
	if _across(edge):
		return Vector2(inset, size.x - inset)
	var corner := inset + arrow.size.y + float(get_theme_constant(&"gap", &"EdgeArrows"))
	return Vector2(corner, size.y - corner)


## How much of `edge` `arrow` takes along it.
func _long(edge: EdgeArrowModel.Edge, arrow: OfficeEdgeArrow) -> float:
	return arrow.size.x if _across(edge) else arrow.size.y


## Whether `edge` runs across the world (top, bottom) rather than down it.
static func _across(edge: EdgeArrowModel.Edge) -> bool:
	return edge == EdgeArrowModel.Edge.TOP or edge == EdgeArrowModel.Edge.BOTTOM


## The zone of the arrow the mouse is on now; empty for none, and for the note.
## By where the mouse is and where the arrows shown stand, never by a node's
## hover flag: the pool's nodes are moved and handed other zones under a
## resting mouse, and the flag stays with the node that had it until the mouse
## moves. Nothing while the arrows are hidden (an overlay covers the world), and
## nothing where something over the arrow takes the mouse (_on_an_arrow()).
func _pointed() -> String:
	if not is_visible_in_tree():
		return ""
	var at := get_global_mouse_position()
	for arrow in _nodes():
		if arrow.visible and arrow.get_global_rect().has_point(at):
			return arrow.zone_key() if _on_an_arrow() else ""
	return ""


## Whether what the mouse is really on is one of these arrows, and not a
## control that covers the arrow there and takes the mouse itself (the staff
## panel floating in answer mode, the drawer, any other part of the HUD). The
## viewport is asked afresh (Viewport.update_mouse_cursor_state(): the engine's
## own look at what is under the mouse, where everything stands now), and only
## this is asked of it: which arrow it is comes from the rectangles.
func _on_an_arrow() -> bool:
	if _asking:
		return false
	_asking = true
	var viewport := get_viewport()
	viewport.update_mouse_cursor_state()
	var over := viewport.gui_get_hovered_control()
	_asking = false
	return over is OfficeEdgeArrow and over.get_parent() == self


## Say the zone under the mouse when it is not the one said last: after the
## arrows were arranged, when they come back or go as a whole, and once the
## mouse has left an arrow.
func _say_pointed() -> void:
	_say(_pointed())


## Say `zone` is the one pointed at, unless it was the one said last.
func _say(zone: String) -> void:
	if zone != _said:
		_said = zone
		zone_pointed.emit(zone)


func _on_picked(pane_key: String) -> void:
	arrow_picked.emit(pane_key)


func _on_entered(arrow: OfficeEdgeArrow) -> void:
	_say(arrow.zone_key())


## The mouse left an arrow's node. What it is on now is said once the viewport
## has finished with this motion: another node of the pool may be entered at
## once (the same zone still under the mouse says nothing twice).
func _on_exited() -> void:
	_say_pointed.call_deferred()


func _nodes() -> Array[OfficeEdgeArrow]:
	var found: Array[OfficeEdgeArrow] = []
	for child in get_children():
		if child is OfficeEdgeArrow:
			found.append(child)
	return found
