class_name OfficeSpaces
extends HdPanel
## The left column: the SPACES rail, one section per machine, each machine's
## zones in ascending number with a worktree's mezzanines right after the zone
## they were made from (OfficeNavigator.section()). A section's heading (shown
## once there is more than Local) names its machine and how it answers, and is
## highlighted for the machine whose map is shown; a click on it shows that
## machine's map. Each zone is a row with the words on its sign, who needs a
## human in it and a window per pane lit by its state; a click on a row pans to
## its zone at once (showing its machine's map first when that is another
## machine's). Rows whose zone is in view wear a mark at their left edge, which
## follows panning (set_in_view()). The office draws one machine's map at a
## time, so this panel is what keeps a blocked agent on another machine in
## sight.
##
## Plain model data in, a picked zone or machine key out. It knows no herdr and
## no client; the office decides what a pick means.
##
## Rows are kept by zone key and updated in place. A row is added or removed
## only when a zone comes or goes, so a refresh with the same zones touches no
## node's existence and the icons keep their pulse.

## A row was pressed; `key` is that zone's key as the office gave it.
signal zone_picked(key: String)
## A heading was pressed; `key` is that machine's key.
signal machine_picked(key: String)

## Row height, which the wheel step is measured in.
const ROW := 26

@export var row_scene: PackedScene
@export var heading_scene: PackedScene

## Zone key -> its row, for as long as that zone exists.
var _rows: Dictionary[String, OfficeSpaceRow] = {}
## Machine key -> its heading.
var _headings: Dictionary[String, OfficeBuildingHeading] = {}
## Row order as drawn, top to bottom.
var _order: PackedStringArray = PackedStringArray()
## The zones in view (set_in_view()), as a set.
var _in_view: Dictionary[String, bool] = {}
## The first row in view as last revealed: the list follows it when it changes.
var _followed := ""
## A reveal waits for the rows to be laid out; their rects mean nothing before.
var _reveal_pending := false
## Whether the rows say their zones' names, or the column is the narrow rail
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


## Draw `machines`, the heading of machine `shown` highlighted. Headings appear
## only `with_headings`: when there is more than one machine. Each machine's
## zones come in ascending number; the rail draws them as
## OfficeNavigator.section() orders them. A machine that is not live is dimmed,
## with no count and no lit window.
func show_machines(machines: Array[SpaceRows], shown: String, with_headings: bool) -> void:
	var wanted: Array[Node] = []
	var keys := PackedStringArray()
	var listed := PackedStringArray()
	for index in machines.size():
		var machine := machines[index]
		var live := machine.state == MachineLiveness.State.LIVE
		listed.append(machine.key)
		if with_headings:
			wanted.append(_heading(machine, index > 0, machine.key == shown))
		for zone: ZoneModel in OfficeNavigator.section(machine.zones):
			var row := _row(zone.key)
			var tip: String = machine.tips.get(zone.key, "")
			row.show_zone(zone, machine.key, live, tip)
			wanted.append(row)
			keys.append(zone.key)
	_keep(wanted, keys, listed if with_headings else PackedStringArray())
	_order = keys
	_follow()


## Mark the rows of the zones `keys` as in view, and no other
## (OfficeSpaceRow.set_in_view()); the list follows the first of them into
## view when it is another row than before. Only the rows whose mark changes
## are touched: nothing is drawn again and no row is made.
func set_in_view(keys: PackedStringArray) -> void:
	_in_view.clear()
	for key in keys:
		_in_view[key] = true
	for key: String in _rows:
		_rows[key].set_in_view(_in_view.has(key))
	_follow()


## The zones whose rows are marked as in view, top to bottom as drawn.
func in_view() -> PackedStringArray:
	var found := PackedStringArray()
	for key in _order:
		if _rows[key].in_view():
			found.append(key)
	return found


## Every row says its zone's name and UNREAD count (`named`), or is the narrow
## rail's: number, windows and blocked count, the rest in its tooltip. The HUD
## decides by the screen's width (OfficeHud._fit_spaces()); rows keep their nodes.
func set_named(named: bool) -> void:
	_named = named
	for key: String in _rows:
		_rows[key].set_named(named)


## Outline zone `key`'s row as pointed at (OfficeSpaceRow.set_pointed()), and no
## other; empty outlines none.
func point(key: String) -> void:
	for each: String in _rows:
		_rows[each].set_pointed(not key.is_empty() and each == key)


## Zone keys top to bottom, as drawn.
func row_keys() -> Array:
	return Array(_order)


## The row drawn for `key`, or null when no zone has it.
func row_for(key: String) -> OfficeSpaceRow:
	return _rows[key] if _rows.has(key) else null


## Every machine heading drawn now, top to bottom.
func headings() -> Array[OfficeBuildingHeading]:
	var found: Array[OfficeBuildingHeading] = []
	for child in _row_box().get_children():
		if child is OfficeBuildingHeading:
			found.append(child)
	return found


## The heading drawn for machine `key`, or null while headings are off or no
## machine has it.
func heading_for(key: String) -> OfficeBuildingHeading:
	return _headings.get(key)


## How tall the scrolling list is: the panel less its title.
func list_height() -> float:
	return _scroll().size.y


## Scroll the list in place; never a rebuild.
func scroll_by(pixels: float) -> void:
	_scroll().scroll_vertical += int(pixels)


func scroll_offset() -> float:
	return float(_scroll().scroll_vertical)


## Drop the rows of zones and the headings of machines that are gone, and put
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


func _row(key: String) -> OfficeSpaceRow:
	if _rows.has(key):
		return _rows[key]
	var row: OfficeSpaceRow = row_scene.instantiate()
	row.name = "Row" + str(_rows.size())
	row.picked.connect(func(picked: String) -> void: zone_picked.emit(picked))
	%Rows.add_child(row)
	row.dress(art)
	row.set_named(_named)
	row.set_in_view(_in_view.has(key))
	_rows[key] = row
	return row


func _heading(machine: SpaceRows, gap: bool, current: bool) -> OfficeBuildingHeading:
	var heading: OfficeBuildingHeading = _headings.get(machine.key)
	if heading == null:
		heading = heading_scene.instantiate()
		heading.name = "Heading" + str(_headings.size())
		heading.picked.connect(func(picked: String) -> void: machine_picked.emit(picked))
		%Rows.add_child(heading)
		heading.dress(art)
		_headings[machine.key] = heading
	heading.show_machine(machine.key, machine.label, machine.state, gap, current)
	return heading


## The first row in view, top to bottom as drawn; empty when none is.
func _first_in_view() -> String:
	for key in _order:
		if _in_view.has(key):
			return key
	return ""


## The list follows the first row in view when that is another row than
## before; otherwise the viewer's own scrolling is left alone.
func _follow() -> void:
	var first := _first_in_view()
	if first != _followed:
		_followed = first
		_reveal_pending = true
		_row_box().queue_sort()


## Follow the first row in view when it moves or the panel resizes. The rows
## have just been placed, but the list's own scroll range settles after this
## pass, so the reveal waits for it.
func _on_rows_sorted() -> void:
	if _reveal_pending:
		_reveal_pending = false
		_reveal.call_deferred()


func _reveal() -> void:
	var row := row_for(_followed)
	if row != null:
		_scroll().ensure_control_visible(row)


## The list every row and heading is a child of.
func _row_box() -> VBoxContainer:
	return %Rows


## The scroller around that list.
func _scroll() -> ScrollContainer:
	return %Scroll
