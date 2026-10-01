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

## An arrow was pressed: pan to the desk of pane `pane_key`.
signal arrow_picked(pane_key: String)
## The mouse came onto an arrow for zone `zone_key` (`""` for the `+N` note),
## or left it (`""`).
signal zone_pointed(zone_key: String)

## What the arrows shown now were drawn from, in the nodes' order.
var _models: Array[EdgeArrowModel] = []
var _compact := false


func _ready() -> void:
	for arrow in _nodes():
		arrow.picked.connect(_on_picked)
		arrow.mouse_entered.connect(_on_entered.bind(arrow))
		arrow.mouse_exited.connect(_on_exited)
	resized.connect(_place)


## Take the pack's art in every arrow; a theme switch rebuilds nothing.
func dress(art: ArtPack) -> void:
	for arrow in _nodes():
		arrow.dress(art)
	_place()


## Draw `arrows`, in order, one node each (the office never hands more than the
## scene holds: EdgeArrowModel.of() folds the rest into its last one), and hide
## the nodes past them. Whether the control shows at all is the HUD's.
func show_arrows(arrows: Array[EdgeArrowModel]) -> void:
	var nodes := _nodes()
	_models.assign(arrows.slice(0, nodes.size()))
	for index in nodes.size():
		var arrow := nodes[index]
		if index < _models.size():
			arrow.show_arrow(_models[index])
		elif arrow.visible:
			arrow.hide_arrow()
	_place()


## Leave each zone's number to its arrow's tooltip (`on`): a narrow world's arrows.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	for arrow in _nodes():
		arrow.set_compact(on)
	_place()


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


## Stand every arrow shown on its edge. Along an edge they go in `along` order,
## each at its own place when that is free, pushed on by the one before it and
## back by the edge's end. The side edges leave the top and bottom rows to the
## arrows there, so no two ever share a corner.
func _place() -> void:
	var nodes := _nodes()
	var inset := float(get_theme_constant(&"inset", &"EdgeArrows"))
	var gap := float(get_theme_constant(&"gap", &"EdgeArrows"))
	for edge: EdgeArrowModel.Edge in EdgeArrowModel.GLYPHS:
		var across := edge == EdgeArrowModel.Edge.TOP or edge == EdgeArrowModel.Edge.BOTTOM
		var on_edge: Array[int] = []
		for index in _models.size():
			if _models[index].edge == edge:
				on_edge.append(index)
		on_edge.sort_custom(func(a: int, b: int) -> bool: return _models[a].along < _models[b].along)
		var span := size.x if across else size.y
		var starts := PackedFloat32Array()
		var first := inset
		var limit := span - inset
		if not across and not on_edge.is_empty():
			# The rows along the top and the bottom are the arrows' there.
			var corner := nodes[on_edge[0]].size.y + gap
			first += corner
			limit -= corner
		var from := first
		for index in on_edge:
			var long := nodes[index].size.x if across else nodes[index].size.y
			var start := maxf(_models[index].along * span - long / 2.0, from)
			starts.append(start)
			from = start + long + gap
		for at in range(on_edge.size() - 1, -1, -1):
			var node := nodes[on_edge[at]]
			var long := node.size.x if across else node.size.y
			starts[at] = maxf(minf(starts[at], limit - long), first)
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


func _on_picked(pane_key: String) -> void:
	arrow_picked.emit(pane_key)


func _on_entered(arrow: OfficeEdgeArrow) -> void:
	zone_pointed.emit(arrow.zone_key())


func _on_exited() -> void:
	zone_pointed.emit("")


func _nodes() -> Array[OfficeEdgeArrow]:
	var found: Array[OfficeEdgeArrow] = []
	for child in get_children():
		if child is OfficeEdgeArrow:
			found.append(child)
	return found
