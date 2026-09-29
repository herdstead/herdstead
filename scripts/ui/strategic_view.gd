class_name OfficeStrategic
extends HdPanel
## The strategic view (scenes/ui/strategic.tscn): press
## `S` and the world rect shows a flat schematic of the shown floor instead of
## the world: every table a box with its tab's name, every seated pane a square
## in its FLOORS window's colour, a blocked one saying how long it has waited
## (OfficeStrategicPlan). A click on a square picks that pane, and the office
## closes the view and pans its desk into sight; `S` and Escape close it too.
##
## It covers only the world rect (OfficeHud.show_strategic() places it there),
## over the hidden world and under the OVERVIEW, the bubble tooltip and the
## monitor: FLOORS, the drawer, the staff panel and NEWS stay usable beside it.
## On the pack's panel, like the OVERVIEW, so its ink reads in every pack (the
## bare backdrop was near ink in the retired dusk pack). A view mode, not a layer: while it is
## open the world's nameplates, badges and bubbles are hidden with the world,
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
## this floor` when the floor has no table. A stale floor's schematic is
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
