class_name OfficeFloors
extends HdPanel
## The left column: the FLOORS minimap, one list per machine, highest floor on
## top with each worktree's mezzanines hung just below the floor they were made
## from (OfficeNavigator.section()). Each floor is a row with who needs a human
## on it and a window per pane lit by its state; the shown floor's row is the
## highlighted one, and a click on any row shows that floor at once. The office
## draws one floor at a time, so this panel is what keeps a blocked agent on a
## hidden floor in sight.
##
## Plain model data in, a picked floor key out. It knows no herdr, no machine
## and no client; the office decides what a pick means.
##
## Rows are kept by floor key and updated in place. A row is added or removed
## only when a floor comes or goes, so a refresh with the same floors touches no
## node's existence and the icons keep their pulse.

## A row was pressed; `key` is that floor's key as the office gave it.
signal floor_picked(key: String)

## Row height, which the wheel step is measured in.
const ROW := 26

@export var row_scene: PackedScene
@export var heading_scene: PackedScene

## Floor key of the row the office shows; the list follows it into view.
var _shown := ""
## Floor key -> its row, for as long as that floor exists.
var _rows: Dictionary[String, OfficeFloorRow] = {}
## Building key -> its heading.
var _headings: Dictionary[String, OfficeBuildingHeading] = {}
## Row order as drawn, top to bottom.
var _order: PackedStringArray = PackedStringArray()
## A reveal waits for the rows to be laid out; their rects mean nothing before.
var _reveal_pending := false
## Whether the rows say their floors' names, or the column is the narrow rail
## (set_named()).
var _named := false


func _ready() -> void:
	_row_box().sort_children.connect(_on_rows_sorted)
	_scroll().resized.connect(func() -> void: _reveal_pending = true)


## Take the pack's art, here and in every row. A theme switch calls this and
## rebuilds nothing.
func dress(pack: ArtPack) -> void:
	super(pack)
	for key: String in _rows:
		_rows[key].dress(pack)
	for key: String in _headings:
		_headings[key].dress(pack)


## Draw `buildings` with `shown` highlighted. Headings appear only when there is
## more than one machine. `buildings` carry their floors in ascending number;
## the panel draws them as OfficeNavigator.section() orders them:
## highest on top, mezzanines under their source. A building whose machine is
## not live is dimmed, with no count and no lit window.
func show_buildings(buildings: Array[BuildingRows], shown: String, with_headings: bool) -> void:
	var wanted: Array[Node] = []
	var keys := PackedStringArray()
	var machines := PackedStringArray()
	for index in buildings.size():
		var building := buildings[index]
		var live := building.state == MachineLiveness.State.LIVE
		machines.append(building.key)
		if with_headings:
			wanted.append(_heading(building, index > 0))
		for floor_model: FloorModel in OfficeNavigator.section(building.floors):
			var row := _row(floor_model.key)
			row.show_floor(floor_model, building.key, floor_model.key == shown, live)
			wanted.append(row)
			keys.append(floor_model.key)
	_keep(wanted, keys, machines if with_headings else PackedStringArray())
	_order = keys
	if shown != _shown:
		_shown = shown
		_reveal_pending = true


## Every row says its floor's name and UNREAD count (`named`), or is the narrow
## rail's: number, windows and blocked count, the rest in its tooltip. The HUD
## decides by the screen's width (OfficeHud._fit_floors()); rows keep their nodes.
func set_named(named: bool) -> void:
	_named = named
	for key: String in _rows:
		_rows[key].set_named(named)


## Mark floor `key`'s row as pointed at (OfficeFloorRow.set_pointed()), and no
## other; empty marks none. The office never asks for the current floor's row.
func point(key: String) -> void:
	for each: String in _rows:
		_rows[each].set_pointed(not key.is_empty() and each == key)


## Floor keys top to bottom, as drawn.
func row_keys() -> Array:
	return Array(_order)


## The row drawn for `key`, or null when no floor has it.
func row_for(key: String) -> OfficeFloorRow:
	return _rows[key] if _rows.has(key) else null


## Every building heading drawn now, top to bottom.
func headings() -> Array[OfficeBuildingHeading]:
	var found: Array[OfficeBuildingHeading] = []
	for child in _row_box().get_children():
		if child is OfficeBuildingHeading:
			found.append(child)
	return found


## How tall the scrolling list is: the panel less its heading.
func list_height() -> float:
	return _scroll().size.y


## Scroll the list in place; never a rebuild.
func scroll_by(pixels: float) -> void:
	_scroll().scroll_vertical += int(pixels)


func scroll_offset() -> float:
	return float(_scroll().scroll_vertical)


## Drop the rows of floors and the headings of buildings that are gone, and put
## the rest in `wanted`'s order. Nothing already in the right place is touched.
## `machines` is empty while headings are off, which drops all of them.
func _keep(wanted: Array[Node], keys: PackedStringArray, machines: PackedStringArray) -> void:
	for key: String in _rows.keys():
		if not keys.has(key):
			_drop(_rows[key])
			_rows.erase(key)
	for key: String in _headings.keys():
		if not machines.has(key):
			_drop(_headings[key])
			_headings.erase(key)
	for index in wanted.size():
		var node := wanted[index]
		if node.get_parent() == null:
			_row_box().add_child(node)
		if _row_box().get_child(index) != node:
			%Rows.move_child(node, index)


func _drop(node: Node) -> void:
	%Rows.remove_child(node)
	node.queue_free()


func _row(key: String) -> OfficeFloorRow:
	if _rows.has(key):
		return _rows[key]
	var row: OfficeFloorRow = row_scene.instantiate()
	row.name = "Row" + str(_rows.size())
	row.floor_picked.connect(func(picked: String) -> void: floor_picked.emit(picked))
	%Rows.add_child(row)
	row.dress(art)
	row.set_named(_named)
	_rows[key] = row
	return row


func _heading(building: BuildingRows, gap: bool) -> OfficeBuildingHeading:
	var heading: OfficeBuildingHeading = _headings.get(building.key)
	if heading == null:
		heading = heading_scene.instantiate()
		heading.name = "Heading" + str(_headings.size())
		%Rows.add_child(heading)
		heading.dress(art)
		_headings[building.key] = heading
	heading.show_building(building.label, building.state, gap)
	return heading


## Follow the shown floor when it moves or the panel resizes; otherwise leave
## the viewer's own scrolling alone. The rows have just been placed, but the
## list's own scroll range settles after this pass, so the reveal waits for it.
func _on_rows_sorted() -> void:
	if _reveal_pending:
		_reveal_pending = false
		_reveal.call_deferred()


func _reveal() -> void:
	var row := row_for(_shown)
	if row != null:
		_scroll().ensure_control_visible(row)


## The list every row and heading is a child of.
func _row_box() -> VBoxContainer:
	return %Rows


## The scroller around that list.
func _scroll() -> ScrollContainer:
	return %Scroll
