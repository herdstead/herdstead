class_name OfficeHud
extends CanvasLayer
## The office's screen-space furniture: the top bar, the SPACES rail on the
## left with the arrows on the world's edges toward blocked desks off screen,
## the agent list in a drawer on the right, and the staff panel along the bottom
## (the agent card, `inspector`, with NEXT at its right end) over the NEWS
## strip, the strategic view over the world rect and the OVERVIEW over the
## world when they are open; laid out by the scene and styled by one Theme.
## In answer mode the staff panel stands in the middle of the screen over a
## dimmed office, as a modal (_fit_staff()).
##
## The office hands it models and asks it back for the room it left over; it
## never tells a panel where to stand. Moving a panel in `hud.tscn` moves the
## world with it.

## A row of the SPACES rail was pressed; `key` is that zone's key. The office
## pans to that zone at once: there is no transition.
signal zone_picked(key: String)
## A heading of the SPACES rail was pressed; `key` is that machine's key. The
## office shows that machine's map.
signal machine_picked(key: String)
## An edge arrow was pressed: the office pans to the desk of pane `pane_key`,
## and selects nothing.
signal arrow_picked(pane_key: String)
## A pane was chosen in the agent list: pick it, as a click on its desk does.
signal agent_picked(key: String)
## The viewer asked for the terminal monitor on pane `pane_key`: a pane opened
## in the agent list (double-click, Enter, Open) or the card's "Monitor ⤢".
## The office decides and opens it.
signal monitor_requested(pane_key: String)
signal history_locate_requested(key: String)
signal attention_snooze_requested(id: String, seconds: int)
signal attention_hidden_changed(id: String, hidden: bool)
## The list's view or a fold changed; the office may remember it.
signal agent_list_changed
## The terminal monitor closed.
signal monitor_closed
## NEXT on the staff panel was pressed: the office does what `N` does.
signal next_requested
## `‹` (-1) or `›` (+1) on the staff panel's line was pressed: the office picks
## the one before or after the pick in NEXT's queue, and only picks.
signal step_requested(direction: int)
## A split from the staff panel of pane `target_key` made pane `pane_id` (see
## OfficePaneInspector.pane_split): the office picks it once it shows.
signal pane_split(target_key: String, pane_id: String, terminal_id: String, generation: int)
## The card made a new space or worktree from pane `from_key` (OfficePaneInspector.space_created):
## the office picks its root pane, in its new zone, once it shows.
signal space_created(from_key: String, workspace_id: String, pane_id: String, terminal_id: String, generation: int)
## A panel's placement changed without the window changing: the office lays the
## world out again (see _fit_room()).
signal room_changed
## A top-bar counter was pressed; `id` is what it counts (OfficeCounter.id).
## The office decides what that does.
signal counter_pressed(id: StringName)
## The top bar's chime switch was clicked: `on` is what it asks for (OfficeBar.chime_toggled).
signal chime_toggled(on: bool)
## An entry of the NEWS strip was clicked: pick pane `key`, as the list does.
signal news_picked(key: String)
## A row of the EVENTS page was clicked: pick pane `key`, as the list does.
signal event_picked(key: String)
## The mouse came onto a NEWS item, a row of the agent list or of EVENTS about
## pane `key`, or left it (`""`): the office points at that desk, and only points.
signal pane_pointed(key: String)
## The same for an edge arrow and its zone `key`: the office outlines that
## zone's SPACES row.
signal zone_pointed(key: String)
## The EVENTS page has just come into sight by its tab: the office lays it
## out now rather than on its next refresh. (The drawer opening on it moves
## the world's room, which refreshes the office anyway.)
signal events_shown

## The overview closed (its `X  Esc`, Esc or `O`): the office shows the world again.
signal overview_closed
## A row of the overview was pressed: pick pane `key`, as a click on its desk does.
signal overview_picked(key: String)
## The overview's sort or filter changed: the office draws it again at once.
signal overview_changed
## The strategic view closed (`S`, Escape, or a square clicked): the office
## shows the world again, unless the overview covers it.
signal strategic_closed
## A square of the strategic view was clicked: pick pane `key` (the view has
## closed first).
signal strategic_picked(key: String)

## The drawer's two pages, in the order of their tabs.
enum DrawerTab { AGENTS, EVENTS }

## What the world keeps clear of the panels: to the side of the SPACES rail and
## the right column, and above the staff panel and below the bar. The rest of
## the geometry is the scene's.
@export var world_gap := Vector2(8, 16)
## Where the world tooltip (over a blocked agent's chip, over a zone's sign) stands from the pointer. Set in the scene.
@export var tip_gap := Vector2.ZERO
## The right-hand drawer's left edge, open and closed, from the screen's right
## (see _fit_drawer()). Set in the scene.
@export var drawer_open_left := 0.0
@export var drawer_closed_left := 0.0
## The bottom staff panel's top edge, full height and one line, from the
## screen's bottom (see _fit_staff()). Set in the scene.
@export var staff_full_top := 0.0
@export var staff_compact_top := 0.0
## Its top edge on a screen at least `staff_tall_from` high, where the compact
## panel is a card (OfficePaneInspector.set_card()). Set in the scene.
@export var staff_card_top := 0.0
## The staff panel's inset from the screen's sides along the bottom, and its
## widest and tallest in answer mode, where it stands in the middle under the
## bar, at least `staff_modal_gap` clear of the bar and of the screen's bottom
## (see _fit_staff()). Set in the scene.
@export var staff_inset := 0.0
@export var staff_modal_width := 0.0
@export var staff_modal_height := 0.0
@export var staff_modal_gap := 0.0
## The logical screen height from which the NEWS strip stays under the staff
## panel opened to full height; below it, the opened panel takes the strip's
## room (see _fit_news()). Set in the scene.
@export var staff_tall_from := 0.0
## The logical screen width from which NEXT stays beside the panel at full
## height, and the one-line row says its long words (`Monitor ⤢`, `Open ⏎`,
## NEXT's whole line); below it, the full panel needs NEXT's room for its
## preview and the row says its short ones. Set in the scene.
@export var staff_next_from := 0.0
## NEXT's width, and its width on the one-line row from `staff_next_from`,
## where it says `NEXT:`, whom and the wait in a row (see _fit_staff()). Set in the scene.
@export var next_width := 0.0
@export var next_wide_width := 0.0
## The SPACES column's right edge as a narrow rail (number, windows, blocked)
## and with the zones' names, and the logical screen width from which it has
## the names (see _fit_spaces()). Set in the scene.
@export var spaces_rail_right := 0.0
@export var spaces_named_right := 0.0
@export var spaces_named_from := 0.0
## The world width below which the edge arrows leave their zone's number to the
## tooltip (see _fit_edge_arrows()). Set in the scene.
@export var edge_arrows_compact_from := 0.0
## The logical screen width from which the bar shows its counters' titles. Set in the scene.
@export var bar_titles_from := 0.0
## The NEWS strip's top edge from the screen's bottom, and the gap the staff
## panel keeps above it (see _fit_staff()). Set in the scene.
@export var news_top := 0.0
@export var news_gap := 0.0
## The logical screen width from which the overview shows every column. Set in the scene.
@export var overview_full_from := 0.0
## Whether this HUD has a NEWS strip at all: the showroom has none (preview.gd),
## the office always does. Where it shows is _fit_news()'s.
var news_wanted := true

## The parts, resolved on first use: the office reaches the HUD before any of
## them is in the tree, so `@onready` would be too late.
var bar: OfficeBar:
	get:
		if _bar == null:
			_bar = $Screen/Bar
		return _bar

var spaces: OfficeSpaces:
	get:
		if _spaces == null:
			_spaces = %Spaces
		return _spaces

## The agent card, which is the staff panel along the bottom (card = the staff panel).
var inspector: OfficePaneInspector:
	get:
		if _inspector == null:
			_inspector = %Staff
		return _inspector

var agent_list: AgentList:
	get:
		if _agent_list == null:
			_agent_list = $Screen/RightColumn/ListHolder/Pages/AgentList
		return _agent_list

## The right-hand drawer: the agent list when open, a tab when closed; where it
## stands is what the world keeps clear of.
var right_column: Control:
	get:
		return $Screen/RightColumn

## The bottom staff panel (the same node as `inspector`): it takes room from the
## world's bottom while it is visible.
var staff: Control:
	get:
		return %Staff

## The arrows on the world's edges; they stand over the world and take no room.
var edge_arrows: OfficeEdgeArrows:
	get:
		return %EdgeArrows

## The NEWS strip along the screen's bottom: it takes room from the world's
## bottom while it is visible (the showroom hides it).
var news: OfficeNews:
	get:
		return %News

## The OVERVIEW, over the world and both side columns while it is open. It
## covers them and takes no room: nothing is laid out again for it.
var overview: OfficeOverview:
	get:
		return %Overview

## The strategic view (`S`) over the world rect while it is open; it covers
## the world, as the OVERVIEW does, and takes no room.
var strategic: OfficeStrategic:
	get:
		return %Strategic

## The drawer's AGENTS / EVENTS tabs.
var drawer_tabs: TabBar:
	get:
		return %DrawerTabs

## The drawer's EVENTS page.
var event_list: EventList:
	get:
		return %EventList

## The terminal monitor, over everything else when it is open.
var monitor: TerminalMonitor:
	get:
		if _monitor == null:
			_monitor = $Screen/Monitor
		return _monitor

## Logical screen the panels are laid out on; the office sets it with fit().
var _screen := Vector2(800, 480)
var _bar: OfficeBar
var _spaces: OfficeSpaces
var _inspector: OfficePaneInspector
var _agent_list: AgentList
## The staff panel is down to its compact line; see _fit_staff().
var _compact := false
## The drawer shows the agent list (open) or only its tab; see _fit_drawer().
## Every run starts with it closed, whatever an earlier run left.
var _drawer_open := false
## The staff panel was opened up from its line (expand_card(), or answer mode).
var _expanded := false
## The SPACES column says the zones' names (see _fit_spaces()).
var _spaces_named := false
## Whether the edge arrows were last handed any (show_edge_arrows()): an
## overlay closing shows the same arrows again without a refresh.
var _arrows_shown := false
## What _process() last saw of the card: answering, and the pane it shows
## (the panel was opened for that pane; another one folds it).
var _was_answering := false
var _expanded_pane := ""
## In answer mode the panel floats in the middle of the screen, and its slot
## along the bottom, which the world keeps clear of, is kept here: its top and
## bottom edges from the screen's bottom (see _fit_staff()).
var _floating := false
var _slot_top := 0.0
var _slot_bottom := 0.0
var _monitor: TerminalMonitor
## Agents that need a human now (AttentionStore.current()), for whatever shows the number.
var _attention_count := 0


func _ready() -> void:
	spaces.zone_picked.connect(func(key: String) -> void: zone_picked.emit(key))
	spaces.machine_picked.connect(func(key: String) -> void: machine_picked.emit(key))
	edge_arrows.arrow_picked.connect(func(key: String) -> void: arrow_picked.emit(key))
	edge_arrows.zone_pointed.connect(func(key: String) -> void: zone_pointed.emit(key))
	bar.counter_pressed.connect(func(id: StringName) -> void: counter_pressed.emit(id))
	bar.chime_toggled.connect(func(on: bool) -> void: chime_toggled.emit(on))
	agent_list.pane_picked.connect(_on_list_pick)
	agent_list.pane_activated.connect(_on_list_open)
	agent_list.history_locate_requested.connect(func(key: String) -> void: history_locate_requested.emit(key))
	agent_list.snooze_requested.connect(
		func(id: String, seconds: int) -> void: attention_snooze_requested.emit(id, seconds)
	)
	agent_list.hidden_changed.connect(
		func(id: String, is_hidden: bool) -> void: attention_hidden_changed.emit(id, is_hidden)
	)
	agent_list.layout_changed.connect(func() -> void: agent_list_changed.emit())
	agent_list.keyboard_changed.connect(_fit_room)
	agent_list.keyboard_changed.connect(_show_keyboard_cue)
	var tab: Button = %DrawerTab
	tab.pressed.connect(open_drawer)
	var collapse: Button = %Collapse
	collapse.pressed.connect(close_drawer)
	drawer_tabs.tab_changed.connect(func(index: int) -> void: select_drawer_tab(index as DrawerTab))
	event_list.picked.connect(func(key: String) -> void: event_picked.emit(key))
	inspector.monitor_requested.connect(func(key: String) -> void: monitor_requested.emit(key))
	inspector.next_requested.connect(func() -> void: next_requested.emit())
	inspector.step_requested.connect(func(direction: int) -> void: step_requested.emit(direction))
	# The line's `Open ⏎` and the panel's `▾ Esc` are the HUD's own: they only
	# open the panel or fold it, which is the HUD's layout, not the office's.
	inspector.open_requested.connect(expand_card)
	inspector.fold_requested.connect(compact_card)
	inspector.pane_split.connect(pane_split.emit)
	inspector.space_created.connect(space_created.emit)
	monitor.closed.connect(_on_monitor_closed)
	news.picked.connect(func(key: String) -> void: news_picked.emit(key))
	news.pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	agent_list.pane_pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	event_list.pointed.connect(func(key: String) -> void: pane_pointed.emit(key))
	overview.closed.connect(_on_overview_closed)
	overview.picked.connect(func(key: String) -> void: overview_picked.emit(key))
	overview.sort_changed.connect(func(_by: OverviewModel.Sort, _reversed: bool) -> void: overview_changed.emit())
	overview.filter_changed.connect(_on_overview_filter)
	strategic.closed.connect(_on_strategic_closed)
	strategic.picked.connect(_on_strategic_picked)


## Build the Theme from `art` and hand every part the pack's own textures.
## Called once at startup and again on a theme switch, which rebuilds no node.
func dress(art: ArtPack, font: Font) -> void:
	var screen: Control = $Screen
	screen.theme = HudTheme.build(art, font)
	bar.dress(art)
	spaces.dress(art)
	edge_arrows.dress(art)
	inspector.dress(art)
	agent_list.dress(art)
	monitor.dress(art)
	news.dress(art)
	event_list.dress(art)
	overview.dress(art)
	strategic.dress(art)
	var tip: HdPanel = %WorldTip
	tip.dress(art)


## The world tooltip, over a blocked agent's chip or a zone's sign: `text` (the question's excerpt
## or why there is none; the sign's repository and checkout), near the pointer at `at` (viewport pixels), kept
## inside world_rect(). The office says what and where; nothing here reads herdr.
func show_world_tip(text: String, at: Vector2) -> void:
	var tip: Control = %WorldTip
	var label: Label = %WorldTipText
	if label.text != text:
		label.text = text
	tip.reset_size()
	var room := world_rect()
	var corner := (room.end - tip.size).max(room.position)
	tip.position = (at + tip_gap).clamp(room.position, corner)
	tip.visible = true


func hide_world_tip() -> void:
	var tip: Control = %WorldTip
	tip.visible = false


## Whether the world tooltip is up, and what it says.
func world_tip_shown() -> bool:
	var tip: Control = %WorldTip
	return tip.visible


func world_tip_text() -> String:
	var label: Label = %WorldTipText
	return label.text


## The Theme dress() built, for furniture in the world that reads like the HUD
## (the machine plate): the same pack, the same variations, built once.
func screen_theme() -> Theme:
	var screen: Control = $Screen
	return screen.theme


## How many agents need a human now: current attention, snoozed and hidden
## records left out. The drawer's tab says it (attention_count()).
func show_attention(current_items: Array[AttentionItem]) -> void:
	_attention_count = current_items.size()
	_label_tab()


func attention_count() -> int:
	return _attention_count


## The NEWS strip's entries, newest first (NewsItem, the office's); see OfficeNews.
func show_news(items: Array[NewsItem]) -> void:
	news.show_news(items)


## The EVENTS page's rows: the log's `events`, newest on top; `pickable` says
## whether a pane key is still there to pick. See EventList.
func show_events(
	events: Array[StateLog.Event], pickable: Callable, selected: String, opened_unix: float, several: bool
) -> void:
	event_list.show_events(events, pickable, selected, opened_unix, several)


## Show the drawer's page `tab`. The drawer stays as it is (open or closed),
## and nothing is remembered: every run starts on AGENTS. Leaving AGENTS lets
## the keyboard go, as closing the drawer does; EVENTS coming into sight says
## events_shown. Its tab's click comes through here too.
func select_drawer_tab(tab: DrawerTab) -> void:
	if drawer_tabs.current_tab != tab:
		# Says tab_changed, which comes back here with the page already current.
		drawer_tabs.current_tab = tab
		return
	if tab != DrawerTab.AGENTS and agent_list.has_keyboard():
		agent_list.release_keyboard()
	var appears := tab == DrawerTab.EVENTS and not event_list.visible
	agent_list.visible = tab == DrawerTab.AGENTS
	event_list.visible = tab == DrawerTab.EVENTS
	if appears and _drawer_open:
		events_shown.emit()


## The drawer's page shown (see select_drawer_tab()).
func drawer_tab() -> DrawerTab:
	return drawer_tabs.current_tab as DrawerTab


## The AGENTS tab's word in the blocked colour while the list holds the
## keyboard.
func _show_keyboard_cue() -> void:
	var look := &"DrawerTabsHeld" if agent_list.has_keyboard() else &"DrawerTabs"
	if drawer_tabs.theme_type_variation != look:
		drawer_tabs.theme_type_variation = look


## Every pane in the agent list, `selected` highlighted; see AgentList.
func show_agents(
	frame: OfficeFrame, active: Array[AttentionItem], history: Array[AgentHistory.Line], selected: String, now_msec: int
) -> void:
	agent_list.show_agents(frame, active, history, selected, now_msec)


## `A` (and nothing else: the drawer's tab only opens the drawer): the drawer
## opens on its AGENTS page and the list takes the keyboard in its flat view,
## or lets it go when it has it. Taking it ends the card's answer mode, so no
## key the list lets through can answer an agent behind the viewer's back.
func toggle_agent_list() -> void:
	open_drawer()
	select_drawer_tab(DrawerTab.AGENTS)
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
		return
	inspector.leave_answer()
	_fit_room()
	agent_list.take_keyboard()


## The top bar's WORKING or IDLE counter: the agent list shows only the panes
## in `presences`, and that counter reads pressed; the same again shows every
## pane. Applying a filter opens the drawer on its AGENTS page, or the
## filtered list is out of sight; clearing one leaves the drawer as it is.
## Nothing is picked and the keyboard stays where it is.
func toggle_list_filter(presences: Array[AgentListModel.Presence]) -> void:
	if agent_list.presence_filter() == presences:
		agent_list.set_presence_filter([])
		bar.set_filter(&"")
		return
	open_drawer()
	select_drawer_tab(DrawerTab.AGENTS)
	agent_list.set_presence_filter(presences)
	var id := &""
	if presences == [AgentListModel.Presence.WORKING]:
		id = &"working"
	elif presences == [AgentListModel.Presence.IDLE]:
		id = &"idle"
	bar.set_filter(id)


## Whether the list, the overview or the strategic view holds the keyboard:
## the arrows are theirs (or nobody's), not the camera's.
func holds_keyboard() -> bool:
	return agent_list.has_keyboard() or overview_open() or strategic_open()


## Whether the overview is open over the world.
func overview_open() -> bool:
	return overview.visible


## Open the overview over the world and both side columns (they stay where
## they are: nothing is laid out again). The list lets the keyboard go; the
## staff panel below stays as it is, answer mode included. PANES reads
## pressed, and WORKING and IDLE now say the overview's chips, not the list's filter.
func open_overview() -> void:
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
	hide_world_tip()
	overview.open()
	_fit_edge_arrows()
	bar.set_overview(true)
	bar.set_filter(_chip_counter(overview.filter()))


func close_overview() -> void:
	overview.close()


## The overview's rows, from the office's model.
func show_overview(model: OverviewModel, art: ArtPack) -> void:
	overview.show_overview(model, art)


## However it closed: PANES is released and WORKING and IDLE say the list's
## filter again.
func _on_overview_closed() -> void:
	_fit_edge_arrows()
	bar.set_overview(false)
	bar.set_filter(_list_counter())
	overview_closed.emit()


func _on_overview_filter(keep: OverviewModel.Filter) -> void:
	if overview_open():
		bar.set_filter(_chip_counter(keep))
	overview_changed.emit()


## The counter a chip stands for in the bar: WORKING and IDLE filter, the
## others do not.
static func _chip_counter(keep: OverviewModel.Filter) -> StringName:
	match keep:
		OverviewModel.Filter.WORKING:
			return &"working"
		OverviewModel.Filter.IDLE:
			return &"idle"
	return &""


## The counter the agent list's filter stands for; `&""` for none.
func _list_counter() -> StringName:
	var presences := agent_list.presence_filter()
	if presences == [AgentListModel.Presence.WORKING]:
		return &"working"
	if presences == [AgentListModel.Presence.IDLE]:
		return &"idle"
	return &""


## Whether the strategic view is open over the world rect.
func strategic_open() -> bool:
	return strategic.visible


## Open the strategic view over the world rect (the office shows it a model
## right after). The world tooltip and the edge arrows go; the list keeps the
## keyboard it has, and the staff panel stays as it is. The top bar's theme
## line says `STRATEGIC · S`.
func open_strategic() -> void:
	hide_world_tip()
	strategic.open()
	_fit_edge_arrows()
	bar.show_strategic(true)


func close_strategic() -> void:
	strategic.close()


## The strategic view's schematic, from the office's model, over the world
## rect as it is now (world_rect(), as the edge arrows stand in it).
func show_strategic(model: StrategicModel) -> void:
	var room := world_rect()
	if strategic.position != room.position:
		strategic.position = room.position
	if strategic.size != room.size:
		strategic.size = room.size
	strategic.show_model(model)


## A HUD line under the mouse names pane `key`: the strategic view dashes its
## square (empty, or a pane it has no square for: none).
func point_strategic(key: String) -> void:
	strategic.point(key)


## Scroll the open strategic view to the section of zone `key`: a SPACES row of
## the shown machine was picked under it.
func reveal_strategic_section(key: String) -> void:
	strategic.reveal_section(key)


## However it closed: the theme line says the pack again.
func _on_strategic_closed() -> void:
	_fit_edge_arrows()
	bar.show_strategic(false)
	strategic_closed.emit()


## A square was clicked: close the view first, then say which pane.
func _on_strategic_picked(key: String) -> void:
	close_strategic()
	strategic_picked.emit(key)


## Open the drawer: the agent list stands in the right column again. Only the
## drawer opens; the list takes no keyboard (that is `A`).
func open_drawer() -> void:
	if _drawer_open:
		return
	_drawer_open = true
	_fit_room()
	agent_list_changed.emit()


## Close the drawer to its strip (the ▶ beside the drawer's tabs). The list
## lets the keyboard go first: a list out of sight holds no keys.
func close_drawer() -> void:
	if not _drawer_open:
		return
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
	_drawer_open = false
	_fit_room()
	agent_list_changed.emit()


func toggle_drawer() -> void:
	if _drawer_open:
		close_drawer()
	else:
		open_drawer()


## Whether the drawer shows the agent list; the office remembers it.
func drawer_open() -> bool:
	return _drawer_open


## Whether the staff panel is down to its one line (see _fit_staff()). The
## card is told this covers it: its preview is out of sight, so it reads nothing.
func card_compact() -> bool:
	return _compact


## Whether the panel was opened up from its line and is not answering (Escape
## folds it then; in answer mode Escape only leaves answer mode).
func card_expanded() -> bool:
	return _expanded and not inspector.answering()


## Open the staff panel up from its line to full height: Enter on a shown pane,
## the line's `Open ⏎`, or answer mode. It folds again on Escape out of answer
## mode, the panel's `▾ Esc`, the card aimed at another pane, or compact_card();
## answer mode ending by itself leaves it open, so what a sent key did stays in
## sight, and so does a new terminal, agent or connection in the same pane (a
## start's progress, a reconnect). `for_key` is the pane the office is about to
## aim the card at (a split's new pane), when that is not the one shown yet.
func expand_card(for_key := "") -> void:
	_expanded = true
	_expanded_pane = for_key if not for_key.is_empty() else inspector.shown_pane_key()
	_fit_room()


func compact_card() -> void:
	_expanded = false
	_fit_room()


## Answer mode opening, and the card being aimed at another pane, change what
## the column shows; the card says neither, so the HUD looks each frame. Answer
## mode opening opens the panel for good: its end folds nothing.
func _process(_delta: float) -> void:
	var answering := inspector.answering()
	var pane := inspector.shown_pane_key()
	if answering == _was_answering and pane == _expanded_pane:
		return
	if answering:
		_expanded = true
	elif pane != _expanded_pane:
		_expanded = false
	_was_answering = answering
	_expanded_pane = pane
	_fit_room()


## Every entry that can move a panel (fit(), the card opening or folding, the
## list taking the keyboard, answer mode, the drawer) comes through here, so the
## office hears room_changed whenever the world's room moved without the window.
## Each panel's own fit is called from here: the drawer and the SPACES column's
## width (rail or named) first, then the NEWS strip and the staff panel above
## it, then the side columns, which stop above the staff panel while it is
## shown (above the strip while only that is, at the screen's bottom gap while
## neither is), the overview on that same bottom edge, and the edge arrows last
## (they stand over world_rect(), which reads all of those). Every edge is one of
## the scene's values. The order is final: no panel adds a step of its own.
func _fit_room() -> void:
	var moved := _fit_drawer()
	moved = _fit_spaces() or moved
	moved = _fit_news() or moved
	moved = _fit_staff() or moved
	var bottom := _column_bottom()
	for column: Control in [spaces, right_column]:
		if column.offset_bottom != bottom:
			column.offset_bottom = bottom
			moved = true
	moved = _fit_overview() or moved
	_fit_edge_arrows()
	if moved:
		room_changed.emit()


## Where the side columns (and the overview) stop, from the screen's bottom.
func _column_bottom() -> float:
	if staff.visible:
		return _staff_top() - world_gap.y
	if news.visible:
		return news_top - world_gap.y
	return -world_gap.y


## The NEWS strip shows, except (besides the showroom, `news_wanted`) while
## the staff panel is opened to full height on a screen short of
## `staff_tall_from` (answer mode, or the panel opened, at 480x320): there its
## 12 units are the world's and the drawer tab's, so answer mode keeps a 112
## high world and the closed drawer's tab (112 high) fits its column.
## Folded back to its line, the panel has the strip under it again.
## True when an edge moved; it moves none (the staff panel above it does, in
## _fit_staff()).
func _fit_news() -> bool:
	var short := _screen.y < staff_tall_from
	var opened := inspector.answering() or _expanded
	news.visible = news_wanted and not (short and opened)
	return false


## The drawer open is the agent list, `drawer_open_left` from the screen's
## right; closed, it is a tab `drawer_closed_left` from it, which says how many
## agents need a human. True when its edge moved.
func _fit_drawer() -> bool:
	var holder: Control = %ListHolder
	var tab: Button = %DrawerTab
	holder.visible = _drawer_open
	tab.visible = not _drawer_open
	_label_tab()
	var left := drawer_open_left if _drawer_open else drawer_closed_left
	if right_column.offset_left == left:
		return false
	right_column.offset_left = left
	return true


## The SPACES column is a narrow rail (`spaces_rail_right`: each zone's number,
## its windows under it and its blocked count, the rest in the row's tooltip)
## on a screen narrower than `spaces_named_from`, and says the zones' names
## from there (`spaces_named_right`). Only the rows' `visible` and tooltips
## change with it. True when its edge moved.
func _fit_spaces() -> bool:
	var named := _screen.x >= spaces_named_from
	if named != _spaces_named:
		_spaces_named = named
		spaces.set_named(named)
	var right := spaces_named_right if named else spaces_rail_right
	if spaces.offset_right == right:
		return false
	spaces.offset_right = right
	return true


## Whether the SPACES column says the zones' names (see _fit_spaces()).
func spaces_named() -> bool:
	return _spaces_named


## The drawer's tab says how many agents need a human (attention_count()), a
## line below its letters. That line holds a dot: a Button drops a blank line
## (or one of spaces), and the count would read as a letter under the S.
func _label_tab() -> void:
	var tab: Button = %DrawerTab
	var said := "◀\nA\nG\nE\nN\nT\nS\n·\n%d" % _attention_count
	if tab.text != said:
		tab.text = said


## The staff panel is one line (`staff_compact_top`: who, state and seat, the
## wait, `‹ ›`, Monitor, Open, and NEXT) at every size until it is opened: Enter
## on a shown pane, the line's `Open ⏎` and answer mode open it to full height
## (`staff_full_top`), Escape out of answer mode and its `▾ Esc` fold it (see
## expand_card()). At full height on a screen narrower than `staff_next_from`,
## the preview takes NEXT's room; from that width the line says its long
## words, and NEXT there is `next_wide_width` wide. While the NEWS strip shows,
## the panel stands `news_gap` above it, lifted whole by as much as the strip
## takes. Only which value applies, and `visible`, change here. True when an
## edge of its slot moved.
##
## In answer mode the panel, at most `staff_modal_width` wide and
## `staff_modal_height` tall (less on a screen without the room,
## `staff_modal_gap` clear of the bar and the bottom), stands in the middle under
## the bar, over the dim (`%ModalDim`): a modal, laid out top to bottom by the
## card itself; its slot along the bottom stays where it was and the world keeps
## clear of it, so leaving answer mode drops the panel back into it and lays
## nothing out again. The dim only darkens: a click goes through it, so a click
## on another desk or chip picks that pane, which leaves answer mode as it
## always has (a new binding), and the next agent can be answered from there.
func _fit_staff() -> bool:
	var answering := inspector.answering()
	var full := answering or _expanded
	# A tall enough screen shows the compact panel as a card.
	var card := not full and _screen.y >= staff_tall_from
	inspector.set_card(card)
	var width := _screen.x - 2.0 * staff_inset
	if answering:
		width = minf(width, staff_modal_width)
	var wide := width + 2.0 * staff_inset >= staff_next_from
	_compact = not full
	inspector.set_compact(_compact)
	inspector.set_wide(wide)
	inspector.set_next_shown(not full or wide)
	inspector.set_next_width(next_wide_width if _compact and wide else next_width)
	var floor_y := -world_gap.y
	if news.visible:
		floor_y = news_top - news_gap
	var lift := floor_y + world_gap.y
	var top := (staff_full_top if full else staff_card_top if card else staff_compact_top) + lift
	var before := Vector2(_staff_top(), _slot_bottom if _floating else staff.offset_bottom)
	var dim: Control = %ModalDim
	dim.visible = answering
	_floating = answering
	_slot_top = top
	_slot_bottom = floor_y
	var side := (_screen.x - width) / 2.0
	staff.offset_left = side
	staff.offset_right = -side
	if answering:
		var below := placed(bar).end.y + staff_modal_gap
		var room := _screen.y - below - staff_modal_gap
		var height := minf(staff_modal_height, room)
		staff.offset_top = below - _screen.y + roundf((room - height) / 2.0)
		staff.offset_bottom = staff.offset_top + height
	else:
		staff.offset_top = top
		staff.offset_bottom = floor_y
	return before != Vector2(top, floor_y)


## The top of the staff panel's slot along the bottom, from the screen's
## bottom: where the panel stands, or would stand while it floats.
func _staff_top() -> float:
	return _slot_top if _floating else staff.offset_top


## The overview stops where the side columns do, so it covers them and the
## world between them exactly. It is not in world_rect(): it covers, it takes
## no room. True when its edge moved (only the window moves it).
func _fit_overview() -> bool:
	overview.set_compact(_screen.x < overview_full_from)
	var bottom := _column_bottom()
	if overview.offset_bottom == bottom:
		return false
	overview.offset_bottom = bottom
	return true


## The arrows on the world's edges toward the zones of the shown map with
## blocked desks off screen (EdgeArrowModel, the office's); none hides them.
## Kept by the arrows themselves, so an overlay closing or the world's room
## changing shows or places the same arrows without a refresh
## (_fit_edge_arrows()): an edge too short for its arrows folds the last of
## them into a `+N` note, and unfolds them when it has the room again.
func show_edge_arrows(arrows: Array[EdgeArrowModel]) -> void:
	_arrows_shown = not arrows.is_empty()
	edge_arrows.show_arrows(arrows)
	_fit_edge_arrows()


## Whether the arrows leave their zone's number to the tooltip: a world
## narrower than `edge_arrows_compact_from` (the 480x320 minimum, 4x), where a
## full arrow would cover too much of it. The SPACES rail's row for that zone
## says the same count, and NEXT names who waits.
func edge_arrows_compact() -> bool:
	return world_rect().size.x < edge_arrows_compact_from


## The edge arrows stand over the world rect, inside its edges (OfficeEdgeArrows
## places each on its own edge). Shown while there are any and nothing covers
## the world: not under the OVERVIEW, the strategic view or the terminal
## monitor. They cover the world where they stand: a chip under one cannot be
## clicked or hovered.
func _fit_edge_arrows() -> void:
	edge_arrows.visible = _arrows_shown and not overview_open() and not strategic_open() and not monitor_open()
	edge_arrows.set_compact(edge_arrows_compact())
	var room := world_rect()
	if edge_arrows.position != room.position:
		edge_arrows.position = room.position
	if edge_arrows.size != room.size:
		edge_arrows.size = room.size


func _on_list_pick(key: String, _by_keyboard: bool) -> void:
	agent_picked.emit(key)


func _on_list_open(key: String) -> void:
	monitor_requested.emit(key)


## Open the terminal monitor on `context` (HerdrFleet.context_for() of the
## pane). One at a time: while one is open, this does nothing.
func open_monitor(context: CommandContext) -> void:
	# The card's reply box and the list let go first: the monitor takes the keyboard.
	inspector.leave_answer()
	if agent_list.has_keyboard():
		agent_list.release_keyboard()
	monitor.open_monitor(context)
	_fit_edge_arrows()


func close_monitor() -> void:
	monitor.close_monitor()


func monitor_open() -> bool:
	return monitor.is_open()


## The monitor closed, however: the edge arrows it covered are back.
func _on_monitor_closed() -> void:
	_fit_edge_arrows()
	monitor_closed.emit()


## Lay the panels out for a `screen`-sized viewport.
func fit(screen: Vector2) -> void:
	_screen = screen
	var control: Control = $Screen
	if control.size != screen:
		control.size = screen
	bar.set_titled(screen.x >= bar_titles_from)
	_fit_room()


## The screen area left over for the office, from where the panels stand.
## Each slot takes room only while it is visible: the showroom hides the left
## column and the NEWS strip (preview.gd). The edge arrows never take any: they stand over the world.
func world_rect() -> Rect2:
	var left := placed(spaces)
	var right := placed(right_column)
	var origin := Vector2(world_gap.x, placed(bar).end.y + world_gap.y)
	var corner := Vector2(_screen.x - world_gap.x, maxf(left.end.y, right.end.y))
	if spaces.visible:
		origin.x = left.end.x + world_gap.x
	if right_column.visible:
		corner.x = right.position.x - world_gap.x
	if staff.visible:
		corner.y = _screen.y + _staff_top() - world_gap.y
	elif news.visible:
		corner.y = placed(news).position.y - world_gap.y
	return Rect2(origin, (corner - origin).maxf(0.0))


## The width a floor is planned for the first time it is shown: the world's
## width with the drawer closed to its tab, whatever the viewer has opened, so
## a floor's plan does not depend on the drawer. The drawer open covers the
## plan's right-hand desks; the camera pans to them (world_rect() still stops at
## the open drawer). (The staff panel's height moves only the world's bottom.)
## Worked out from the scene's values; no node moves.
func plan_width() -> float:
	var room := world_rect()
	if not right_column.visible:
		return room.size.x
	var right := right_column.anchor_left * _screen.x + drawer_closed_left
	return maxf(right - world_gap.x - room.position.x, 0.0)


## Where a panel lands on the screen fit() was given, from the anchors and
## offsets its scene carries. Godot resolves those at the end of a frame and
## only inside the tree; the world has to know before it lays a floor out.
func placed(control: Control) -> Rect2:
	var left := control.anchor_left * _screen.x + control.offset_left
	var top := control.anchor_top * _screen.y + control.offset_top
	var right := control.anchor_right * _screen.x + control.offset_right
	var bottom := control.anchor_bottom * _screen.y + control.offset_bottom
	return Rect2(left, top, right - left, bottom - top)


## The top bar's right-hand lines. `alarmed` is a machine being offline.
func show_bar(theme_name: String, status: String, alarmed: bool) -> void:
	bar.show_bar(theme_name, status, alarmed)


## The top bar's six counters and their breakdowns.
func show_totals(totals: OfficeTotals) -> void:
	bar.show_totals(totals)


## The BLOCKED counter's longest wait, on attention's beat; empty for none.
func show_longest_wait(text: String) -> void:
	bar.show_longest_wait(text)


## Whether the chime is on, as the top bar's switch shows it (OfficeBar.show_chime()).
func show_chime(on: bool) -> void:
	bar.show_chime(on)
