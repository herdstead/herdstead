class_name OfficeStrategic
extends HdPanel
## The strategic view (scenes/ui/strategic.tscn): press
## `S` and the world rect shows a flat schematic of the shown machine's map
## instead of the world: a captioned section per zone, in the SPACES rail's
## order, every pod a box with its tab's name, every seated pane a square
## in its SPACES window's colour, a blocked one saying how long it has waited
## (OfficeStrategicPlan). A click on a square picks that pane, and the office
## closes the view and pans its desk into sight; `S` and Escape close it too.
## A SPACES row picked while it is open scrolls it to that zone's section
## (reveal_section()), or draws it again for that row's machine.
##
## It covers only the world rect (OfficeHud.show_strategic() places it there),
## over the hidden world and under the OVERVIEW, the world tooltip and the
## monitor: SPACES, the drawer, the staff panel and NEWS stay usable beside it.
## On the pack's panel, like the OVERVIEW, so its ink reads in every pack (the
## bare backdrop was near ink in the retired dusk pack). A view mode, not a layer: while it is
## open the world's nameplates, badges and chips are hidden with the world,
## so every field is still drawn once. It draws a StrategicModel and nothing
## else; every node is the scene's and is kept.

## A square was clicked: the office picks pane `key` (after closing the view).
signal picked(key: String)
## The view closed (close()).
signal closed

var _model: StrategicModel
var _stale_tint := Color.WHITE


func _ready() -> void:
	plan().picked.connect(func(key: String) -> void: picked.emit(key))
	# The drawer's thin bar, shown only when the schematic is taller than its
	# room, never focused: the arrow keys are nobody's while the view is open.
	var scroll: ScrollContainer = %Scroll
	var bar := scroll.get_v_scroll_bar()
	bar.theme_type_variation = &"DrawerScroll"
	bar.focus_mode = Control.FOCUS_NONE


## The pack's panel, its stale tint and the states' words. A theme switch calls
## this again; nothing is rebuilt.
func dress(pack: ArtPack) -> void:
	super(pack)
	_stale_tint = pack.stale_tint
	plan().dress(pack)
	if _model != null:
		show_model(_model)


func plan() -> OfficeStrategicPlan:
	return %Plan


func open() -> void:
	visible = true


## Hide, and say so once.
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Draw `model` in the room this view has at its size now: the title (and the
## machine's state when it is not answering), the schematic, or `No desks on
## this machine` when its map has no table. A stale map's schematic is
## tinted like the frozen world; the header is not.
func show_model(shown: StrategicModel) -> void:
	_model = shown
	var title: Label = %Title
	var said := shown.title if shown.state_text.is_empty() else "%s · %s" % [shown.title, shown.state_text]
	if title.text != said:
		title.text = said
	var nothing := shown.tables.is_empty()
	var empty: Control = %Empty
	var scroll: Control = %Scroll
	empty.visible = nothing
	scroll.visible = not nothing
	var drawn := plan()
	drawn.modulate = _stale_tint if shown.stale else Color.WHITE
	drawn.show_model(shown, room_for(size), _bar_width())


## The model shown last; null before any.
func model() -> StrategicModel:
	return _model


## What the title says now.
func title_text() -> String:
	var title: Label = %Title
	return title.text


## Dash pane `key`'s square; empty for none.
func point(key: String) -> void:
	plan().point(key)


## Scroll the schematic so that the caption of zone `key`'s section is in
## sight, at the top of the room when it was out of it; nothing for a zone with
## no section, or a schematic that does not scroll. After the layout settles:
## the scroll's range is only right once the schematic has its new size.
func reveal_section(key: String) -> void:
	_reveal_section.call_deferred(key)


func _reveal_section(key: String) -> void:
	var bands := plan().section_rects(key)
	if bands.is_empty():
		return
	var scroll: ScrollContainer = %Scroll
	var top := bands[0].position.y
	if top < scroll.scroll_vertical or bands[0].end.y > scroll.scroll_vertical + scroll.size.y:
		scroll.scroll_vertical = int(top)


## The room the schematic has in a view `outer` units big: the panel's frame,
## the margin inside it and the header (with the column's separation under
## it) taken off. All of them the scene's and the theme's; worked out without
## waiting for the containers to sort, as OfficeHud.placed() does.
func room_for(outer: Vector2) -> Vector2:
	var frame := get_theme_stylebox(&"panel").get_minimum_size()
	var margin: MarginContainer = %Margin
	var inside := Vector2(
		margin.get_theme_constant(&"margin_left") + margin.get_theme_constant(&"margin_right"),
		margin.get_theme_constant(&"margin_top") + margin.get_theme_constant(&"margin_bottom")
	)
	var header: Control = %Header
	var column: VBoxContainer = %Column
	var above := header.get_combined_minimum_size().y + column.get_theme_constant(&"separation")
	return (outer - frame - inside - Vector2(0, above)).max(Vector2.ZERO)


## How wide the scroll's bar is, with the gap it keeps from the schematic.
func _bar_width() -> float:
	var scroll: ScrollContainer = %Scroll
	return scroll.get_v_scroll_bar().get_combined_minimum_size().x
