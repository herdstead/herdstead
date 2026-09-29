class_name HudTheme
extends RefCounted
## The one Theme the office HUD is styled by, built from an art pack.
##
## Every colour the HUD uses is a palette key, and every palette key the HUD
## uses is a Label type variation named after it, so a scene picks its look with
## `theme_type_variation` and no HUD node carries an `add_theme_*_override`.
## Sizes other than the default 10 get their own variation, because a variation
## cannot be combined with another one.
##
## The Theme is built in code because its colours come from whichever pack is
## loaded; the layout it styles lives in the scenes, which is what matters.

## Palette key per Label variation. Plain `Label` is `ink`.
const LABEL_COLORS: Dictionary[StringName, StringName] = {
	&"LabelSlate": ArtContract.SLATE,
	&"LabelMuted": ArtContract.MUTED,
	&"LabelPaper": ArtContract.PAPER,
	&"LabelWoodDark": ArtContract.WOOD_DARK,
	&"LabelWoodShadow": ArtContract.WOOD_SHADOW,
	&"LabelBlocked": ArtContract.BLOCKED,
	&"LabelWorking": ArtContract.WORKING,
	&"LabelCream": ArtContract.CREAM,
}
## Label variations that also change the size, and the palette key they take.
const LABEL_SIZES: Dictionary[StringName, int] = {
	&"Heading13": 13,
	&"Heading16": 16,
	&"Heading16Paper": 16,
	&"Heading16Slate": 16,
	&"RowNumber": 9,
	&"RowNumberCurrent": 9,
	&"Heading13Blocked": 13,
	&"ListChevron": 8,
	&"ListChevronCurrent": 8,
	&"CounterTitle": 9,
	&"CounterTitlePaper": 9,
	&"CounterValue": 13,
	&"CounterValuePaper": 13,
}
const LABEL_HEADINGS: Dictionary[StringName, StringName] = {
	&"Heading13": ArtContract.INK,
	&"Heading16": ArtContract.INK,
	&"Heading16Paper": ArtContract.PAPER,
	&"Heading16Slate": ArtContract.SLATE,
	&"RowNumber": ArtContract.PAPER,
	&"RowNumberCurrent": ArtContract.INK,
	&"Heading13Blocked": ArtContract.BLOCKED,
	&"ListChevron": ArtContract.SLATE,
	&"ListChevronCurrent": ArtContract.PAPER,
	# The top bar's counters: INK rather than SLATE for the small titles, which
	# SLATE on CREAM leaves at 2.8:1 in the retired dusk pack (measured); PAPER on a pressed one.
	&"CounterTitle": ArtContract.INK,
	&"CounterTitlePaper": ArtContract.PAPER,
	&"CounterValue": ArtContract.INK,
	&"CounterValuePaper": ArtContract.PAPER,
}
## Panel variations that are a flat fill of one palette colour: the bar's
## ground and the minimap's floor chips. A building's heading wears the pack's
## own icon rather than a coloured square, so it needs none of these.
const FLAT_PANELS: Dictionary[StringName, StringName] = {
	&"BarBackground": ArtContract.INK,
	&"RowChip": ArtContract.SLATE,
	&"RowChipCurrent": ArtContract.PAPER,
}
## The minimap's window looks (scenes/ui/floor_row.tscn picks one
## per pane): a state's own colour, idle lit plainly, and dark for a shell or a
## machine that is not answering.
const SECTION_PANELS: Dictionary[StringName, StringName] = {
	&"WindowWorking": ArtContract.WORKING,
	&"WindowBlocked": ArtContract.BLOCKED,
	&"WindowDone": ArtContract.UNREAD,
	&"WindowIdle": ArtContract.CREAM,
	&"WindowUnknown": ArtContract.MUTED,
	&"WindowDark": ArtContract.SLATE,
}
## How much of the office shows through the dim under the answer-mode panel
## (`ModalDim`, INK at this opacity): enough to see which desk it is about.
const MODAL_DIM := 0.55
## Every state a Button stylebox has to cover. A flat button looks the same in
## all of them: a press changes the office, not the button. The agent card's
## action (CardAction) is the exception, see _card().
const BUTTON_STATES := ["normal", "hover", "pressed", "focus", "disabled"]
## The agent card's terminal preview: the first system monospace face found,
## then the HUD font's own CJK fallback (OfficeDraw). Not the HUD font itself:
## Godot sizes a row by the tallest font in the chain, and the HUD's Latin face
## would make every row 2 px taller (measured: 11 px instead of 9 at size 7).
const MONO_FACES := ["Menlo", "SF Mono", "Monaco", "DejaVu Sans Mono", "monospace"]
## Pixels per preview row's glyphs, and the pitch from one row to the next:
## twelve rows of it, and the card around them, fit a 640x320 screen (3x).
const PREVIEW_SIZE := 7
const PREVIEW_LINE_SPACING := -1
## Units taken off the top and bottom of a counter's title and number line
## boxes (FontVariation spacing_top, spacing_bottom); see _counters().
const COUNTER_TITLE_TRIM := Vector2i(-2, -3)
const COUNTER_VALUE_TRIM := Vector2i(-3, -3)
## The OVERVIEW's scroll bar, and the gap between it and the timelines, in
## units. overview.tscn's `%BarRoom` is their sum less the heads' separation.
const OVERVIEW_BAR := 4
const OVERVIEW_BAR_GAP := 4
## The drawer's scroll bar and its gap, in units: together the 4 units its
## pages' Frame no longer pads on the right (agent_list.tscn, event_list.tscn),
## so the rows are as wide as they were before the drawer had a bar.
const DRAWER_BAR := 2
const DRAWER_BAR_GAP := 2
## Units the agent list indents a line per depth.
const LIST_INDENT := 4


## The whole HUD's look. OfficeDraw supplies the bundled face with CJK fallback;
## headings use its heavier weight while metadata keeps the readable text cut.
static func build(art: ArtPack, font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 10
	theme.set_color("font_color", "Label", art.color(ArtContract.INK))
	var heading := FontVariation.new()
	heading.base_font = font
	var text_server := TextServerManager.get_primary_interface()
	heading.variation_opentype = {text_server.name_to_tag("wght"): 700.0, text_server.name_to_tag("opsz"): 12.0}
	for name in LABEL_COLORS:
		_label(theme, name, 10, art.color(LABEL_COLORS[name]))
	for name in LABEL_HEADINGS:
		_label(theme, name, LABEL_SIZES[name], art.color(LABEL_HEADINGS[name]))
		if LABEL_SIZES[name] >= 13:
			theme.set_font("font", name, heading)
		theme.set_font("font", name, _fit(theme.get_font("font", name), art.font, LABEL_SIZES[name]))
	for name in FLAT_PANELS:
		theme.set_type_variation(name, "Panel")
		theme.set_stylebox("panel", name, _flat(art.color(FLAT_PANELS[name])))
	theme.set_type_variation(&"ModalDim", "Panel")
	theme.set_stylebox("panel", &"ModalDim", _flat(Color(art.color(ArtContract.INK), MODAL_DIM)))
	_panel(theme, art)
	_buttons(theme, art)
	_attention(theme, art)
	_counters(theme, art)
	_chime_switch(theme, art)
	_tooltips(theme, art)
	_agent_list(theme, art)
	_signpost(theme, art)
	_plate(theme, art)
	_card(theme, art, font)
	_section(theme, art)
	_monitor(theme, art, font)
	_news(theme, art)
	_overview(theme, art)
	_strategic(theme, art, heading)
	return theme


## The strategic view (`S`, scenes/ui/strategic.tscn), drawn by
## OfficeStrategicPlan._draw() on the pack's panel: one colour per FLOORS
## window look (SECTION_PANELS, the one scale), the tables' `frame` in ink with
## a slate `divider` between their far and near seats, the tab's `caption` and
## a blocked square's `wait` in ink, the selection's `corner`s in the blocked
## colour (the world's selection, as vector corners) and the pointer's dash in
## ink and paper (`pointer_a`, `pointer_b`, OfficePointer's). The measures, in
## units: `pad` inside a table's box, `gap` between boxes, `caption_height`
## above one, `divider` between its two rows of seats, `ring` round a square
## (the square is its cell less the ring on both sides), `rule` the width of
## every line, `dash` a pointer stroke, `corner_part` the share of a cell a
## corner's arm takes (a cell / corner_part), and `wait_from` the smallest cell
## that writes a wait in its square. The cell ladder is the scene's (%Plan).
static func _strategic(theme: Theme, art: ArtPack, heading: Font) -> void:
	theme.add_type("Strategic")
	for name: StringName in SECTION_PANELS:
		theme.set_color(name, "Strategic", art.color(SECTION_PANELS[name]))
	var colours: Dictionary[StringName, StringName] = {
		&"frame": ArtContract.INK,
		&"divider": ArtContract.SLATE,
		&"caption": ArtContract.INK,
		&"wait": ArtContract.INK,
		&"corner": ArtContract.BLOCKED,
		&"pointer_a": ArtContract.INK,
		&"pointer_b": ArtContract.PAPER,
	}
	for name: StringName in colours:
		theme.set_color(name, "Strategic", art.color(colours[name]))
	var measures: Dictionary[StringName, int] = {
		&"pad": 4,
		&"gap": 8,
		&"caption_height": 12,
		&"divider": 2,
		&"ring": 2,
		&"rule": 1,
		&"dash": OfficePointer.DASH,
		&"corner_part": 4,
		&"wait_from": 24,
		&"caption_size": 10,
		&"wait_size": 9,
	}
	for name: StringName in measures:
		theme.set_constant(name, "Strategic", measures[name])
	theme.set_font("caption_font", "Strategic", heading)
	theme.set_font("wait_font", "Strategic", heading)


## The OVERVIEW (scenes/ui/overview*.tscn): rows that light up under the
## pointer like the agent list's (CREAM, not CREAM_SHADOW, which is dark in
## the retired dusk pack), the selected row in ink, an offline row muted; column heads on a
## cream band with an ink rule under it; and the `Timeline` type every
## timeline, the axis and the legend draw with: one palette colour per state,
## the hatch where nobody watched, the axis and now rule in ink, and the two
## measures of the band. The swatches are flat panels of the same colours.
## Rows that overflow show a thin scroll bar (`OverviewScroll`: an ink grabber
## on a cream track, OVERVIEW_BAR wide) a gap (`OverviewRowsGap`,
## OVERVIEW_BAR_GAP) right of the timelines, so it never meets their ink `now`
## rule; the table's scroll reserves that room whether the bar shows or not,
## and the heads' `%BarRoom` (overview.tscn) leaves the same, so the axis ends
## where the timelines do.
static func _overview(theme: Theme, art: ArtPack) -> void:
	for name: String in ["OverviewRow", "OverviewRowCurrent", "OverviewRowDim", "OverviewHead"]:
		theme.set_type_variation(name, "Button")
		theme.set_constant("outline_size", name, 0)
	for state: String in BUTTON_STATES:
		var lit := state == "hover" or state == "pressed"
		var row: StyleBox = _flat(art.color(ArtContract.CREAM)) if lit else StyleBoxEmpty.new()
		theme.set_stylebox(state, "OverviewRow", row)
		theme.set_stylebox(state, "OverviewRowDim", row)
		theme.set_stylebox(state, "OverviewRowCurrent", _flat(art.color(ArtContract.INK)))
		var head := _flat(art.color(ArtContract.CREAM))
		head.border_width_bottom = 2 if lit else 1
		head.border_color = art.color(ArtContract.INK)
		head.content_margin_left = 2
		head.content_margin_right = 2
		head.content_margin_top = 1
		head.content_margin_bottom = 1
		theme.set_stylebox(state, "OverviewHead", head)
	var tones: Dictionary[String, StringName] = {
		"OverviewRow": ArtContract.INK,
		"OverviewRowCurrent": ArtContract.PAPER,
		"OverviewRowDim": ArtContract.MUTED,
		# INK, not SLATE: SLATE on CREAM is 2.8:1 in the retired dusk pack (the counters' titles, measured).
		"OverviewHead": ArtContract.INK,
	}
	for name: String in tones:
		for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(role, name, art.color(tones[name]))
	theme.set_font_size("font_size", "OverviewHead", 9)
	# A row's agent name stands clear of the badge drawn at its left (the badge
	# is the label's child, which keeps a row to ten nodes).
	var agents: Dictionary[StringName, StringName] = {
		&"OverviewAgent": ArtContract.INK,
		&"OverviewAgentPaper": ArtContract.PAPER,
		&"OverviewAgentMuted": ArtContract.MUTED,
	}
	for name: StringName in agents:
		_label(theme, name, 10, art.color(agents[name]))
		var room := StyleBoxEmpty.new()
		room.content_margin_left = 18
		theme.set_stylebox("normal", name, room)
	var colours: Dictionary[StringName, StringName] = {
		&"blocked": ArtContract.BLOCKED,
		&"done": ArtContract.UNREAD,
		&"working": ArtContract.WORKING,
		&"idle": ArtContract.WOOD_SHADOW,
		&"unknown": ArtContract.MUTED,
		# CREAM under SLATE lines: CREAM_SHADOW was near INK in the retired dusk pack, where the
		# SLATE hatch on it all but vanished (1.7:1, seen in its capture).
		&"unobserved_fill": ArtContract.CREAM,
		&"unobserved_line": ArtContract.SLATE,
		&"axis": ArtContract.INK,
	}
	theme.add_type("Timeline")
	for name: StringName in colours:
		theme.set_color(name, "Timeline", art.color(colours[name]))
	theme.set_constant("inset", "Timeline", 2)
	theme.set_constant("hatch_step", "Timeline", 4)
	theme.set_constant("rule", "Timeline", 1)
	var swatches: Dictionary[StringName, StringName] = {
		&"TimelineSwatchBlocked": &"blocked",
		&"TimelineSwatchDone": &"done",
		&"TimelineSwatchWorking": &"working",
		&"TimelineSwatchIdle": &"idle",
		&"TimelineSwatchUnknown": &"unknown",
		&"TimelineSwatchUnobserved": &"unobserved_fill",
	}
	for name: StringName in swatches:
		theme.set_type_variation(name, "Panel")
		theme.set_stylebox("panel", name, _flat(art.color(colours[swatches[name]])))
	theme.set_type_variation("OverviewScroll", "VScrollBar")
	var track := _flat(art.color(ArtContract.CREAM))
	var grabber := _flat(art.color(ArtContract.INK))
	for box: StyleBoxFlat in [track, grabber]:
		box.content_margin_left = OVERVIEW_BAR / 2.0
		box.content_margin_right = OVERVIEW_BAR / 2.0
	grabber.content_margin_top = OVERVIEW_BAR / 2.0
	grabber.content_margin_bottom = OVERVIEW_BAR / 2.0
	theme.set_stylebox("scroll", "OverviewScroll", track)
	theme.set_stylebox("scroll_focus", "OverviewScroll", track)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "OverviewScroll", grabber)
	theme.set_type_variation("OverviewRowsGap", "MarginContainer")
	theme.set_constant("margin_right", "OverviewRowsGap", OVERVIEW_BAR_GAP)


## The NEWS strip along the bottom (scenes/ui/news.tscn): a flat INK band,
## like the top bar's ground, whose items are words on it with no box of their
## own (the pointer lightens them; one that cannot be clicked is muted); and
## the drawer's AGENTS / EVENTS tabs (TabBar), the page shown in ink like the
## Flat / Tree switch's pressed half, the other on cream. While the agent list
## holds the keyboard, its tab's word is in the blocked colour, as its heading was.
static func _news(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("NewsBar", "PanelContainer")
	var band := _flat(art.color(ArtContract.INK))
	band.content_margin_left = 4
	band.content_margin_top = 2
	band.content_margin_right = 4
	band.content_margin_bottom = 2
	theme.set_stylebox("panel", "NewsBar", band)
	theme.set_type_variation("NewsItem", "Button")
	for state: String in BUTTON_STATES:
		theme.set_stylebox(state, "NewsItem", StyleBoxEmpty.new())
	theme.set_color("font_color", "NewsItem", art.color(ArtContract.PAPER))
	theme.set_color("font_focus_color", "NewsItem", art.color(ArtContract.PAPER))
	theme.set_color("font_hover_color", "NewsItem", art.color(ArtContract.CREAM))
	theme.set_color("font_pressed_color", "NewsItem", art.color(ArtContract.CREAM))
	theme.set_color("font_disabled_color", "NewsItem", art.color(ArtContract.MUTED))
	theme.set_constant("outline_size", "NewsItem", 0)
	for name: String in ["DrawerTabs", "DrawerTabsHeld"]:
		theme.set_type_variation(name, "TabBar")
		var fills: Dictionary[String, StringName] = {
			"tab_selected": ArtContract.INK,
			"tab_unselected": ArtContract.CREAM,
			"tab_hovered": ArtContract.CREAM_SHADOW,
			"tab_disabled": ArtContract.CREAM,
		}
		# Drawn over a focused tab; the tabs take no focus, and it must hide nothing.
		theme.set_stylebox("tab_focus", name, StyleBoxEmpty.new())
		for style: String in fills:
			var tab := _flat(art.color(fills[style]))
			tab.set_border_width_all(1)
			tab.border_color = art.color(ArtContract.INK)
			tab.content_margin_left = 5
			tab.content_margin_right = 5
			tab.content_margin_top = 1
			tab.content_margin_bottom = 1
			theme.set_stylebox(style, name, tab)
		theme.set_color("font_unselected_color", name, art.color(ArtContract.INK))
		theme.set_color("font_hovered_color", name, art.color(ArtContract.INK))
		theme.set_color("font_disabled_color", name, art.color(ArtContract.MUTED))
		theme.set_constant("outline_size", name, 0)
		theme.set_constant("h_separation", name, 2)
		theme.set_font_size("font_size", name, 10)
	theme.set_color("font_selected_color", "DrawerTabs", art.color(ArtContract.PAPER))
	theme.set_color("font_selected_color", "DrawerTabsHeld", art.color(ArtContract.BLOCKED))


## The agent card (scenes/ui/inspector.tscn): its terminal preview on a dark
## screen, and its one action, whose disabled look is unmistakable. The button
## is disabled while the card follows herdr's focus, while its write is in
## flight and whenever the write would be refused, so it must not look pressable.
static func _card(theme: Theme, art: ArtPack, font: Font) -> void:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(MONO_FACES)
	mono.fallbacks = font.fallbacks
	var bare := SystemFont.new()
	bare.font_names = PackedStringArray(MONO_FACES)
	_label(theme, &"PreviewText", PREVIEW_SIZE, art.color(ArtContract.PAPER))
	theme.set_font("font", "PreviewText", _fit(mono, bare, PREVIEW_SIZE))
	# Terminal rows sit edge to edge: twelve of them are a fixed block. A Latin
	# descender still clears the next row's capitals at this pitch.
	theme.set_constant("line_spacing", "PreviewText", PREVIEW_LINE_SPACING)
	theme.set_type_variation("PreviewScreen", "PanelContainer")
	var screen := _flat(art.color(ArtContract.INK))
	screen.content_margin_left = 2
	screen.content_margin_right = 2
	screen.content_margin_top = 2
	screen.content_margin_bottom = 2
	theme.set_stylebox("panel", "PreviewScreen", screen)
	theme.set_type_variation("CardAction", "Button")
	for state: String in BUTTON_STATES:
		var fill := ArtContract.CREAM
		if state == "hover" or state == "pressed":
			fill = ArtContract.WOOD_SHADOW
		var box := _flat(art.color(fill))
		box.set_border_width_all(1)
		box.border_color = art.color(ArtContract.INK)
		if state == "disabled":
			# No fill and a muted edge: it reads as switched off, not as waiting for a click.
			box.bg_color = Color.TRANSPARENT
			box.border_color = art.color(ArtContract.MUTED)
		box.content_margin_left = 6
		box.content_margin_right = 6
		box.content_margin_top = 2
		box.content_margin_bottom = 2
		theme.set_stylebox(state, "CardAction", box)
	theme.set_color("font_color", "CardAction", art.color(ArtContract.INK))
	theme.set_color("font_focus_color", "CardAction", art.color(ArtContract.INK))
	theme.set_color("font_hover_color", "CardAction", art.color(ArtContract.PAPER))
	theme.set_color("font_pressed_color", "CardAction", art.color(ArtContract.PAPER))
	theme.set_color("font_disabled_color", "CardAction", art.color(ArtContract.MUTED))
	_answer(theme, art)
	_staff(theme, art)


## The staff panel's NEXT button and the closed drawer's tab. NEXT is drawn like
## the card's action, but its words are labels of their own, which keep their
## colours: a hover thickens its ink edge instead of darkening the fill under
## them. Off (nobody next), it has no fill and a muted edge, like the action.
## The tab is a light strip with an ink edge; its letters stand one per line.
static func _staff(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("NextAction", "Button")
	theme.set_type_variation("DrawerTab", "Button")
	for state: String in BUTTON_STATES:
		var next := _flat(art.color(ArtContract.CREAM))
		next.set_border_width_all(2 if state == "hover" or state == "pressed" else 1)
		next.border_color = art.color(ArtContract.INK)
		if state == "disabled":
			next.bg_color = Color.TRANSPARENT
			next.border_color = art.color(ArtContract.MUTED)
		theme.set_stylebox(state, "NextAction", next)
		var tab := _flat(
			art.color(ArtContract.WOOD_SHADOW if state == "hover" or state == "pressed" else ArtContract.CREAM)
		)
		tab.set_border_width_all(1)
		tab.border_color = art.color(ArtContract.INK)
		tab.content_margin_top = 4
		theme.set_stylebox(state, "DrawerTab", tab)
	theme.set_color("font_color", "DrawerTab", art.color(ArtContract.INK))
	theme.set_color("font_focus_color", "DrawerTab", art.color(ArtContract.INK))
	theme.set_color("font_hover_color", "DrawerTab", art.color(ArtContract.PAPER))
	theme.set_color("font_pressed_color", "DrawerTab", art.color(ArtContract.PAPER))
	# Nine lines of one letter each stand in a column as short as 120 units.
	theme.set_constant("line_spacing", "DrawerTab", -3)


## The card's answer mode: key buttons as small as a key label allows (nine
## digits side by side in the card's 124 units), the same unmistakable disabled
## look as the card's action, the heading's "Answer" chip drawn like a key, and
## the reply box as a light field with a dark edge.
static func _answer(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("CardKey", "Button")
	theme.set_type_variation("CardHint", "Button")
	for state: String in BUTTON_STATES:
		var key := _flat(
			art.color(ArtContract.WOOD_SHADOW if state == "hover" or state == "pressed" else ArtContract.CREAM)
		)
		key.set_border_width_all(1)
		key.border_color = art.color(ArtContract.INK)
		if state == "disabled":
			key.bg_color = Color.TRANSPARENT
			key.border_color = art.color(ArtContract.MUTED)
		key.content_margin_left = 3
		key.content_margin_right = 3
		key.content_margin_top = 0
		key.content_margin_bottom = 0
		theme.set_stylebox(state, "CardKey", key)
		# The heading chip looks like a key: CREAM_SHADOW was dark in the retired dusk pack, and INK
		# on it could not be read (seen in its capture).
		theme.set_stylebox(state, "CardHint", key)
	for name: String in ["CardKey", "CardHint"]:
		theme.set_color("font_color", name, art.color(ArtContract.INK))
		theme.set_color("font_focus_color", name, art.color(ArtContract.INK))
		theme.set_color("font_hover_color", name, art.color(ArtContract.PAPER))
		theme.set_color("font_pressed_color", name, art.color(ArtContract.PAPER))
		theme.set_color("font_disabled_color", name, art.color(ArtContract.MUTED))
	# The best-effort line and the result line may take two lines in answer
	# mode; without the default 3 units between them both fit at 480x320.
	for name: StringName in [&"CardNote", &"CardOutcome"]:
		_label(theme, name, 10, art.color(ArtContract.SLATE if name == &"CardNote" else ArtContract.WOOD_SHADOW))
		theme.set_constant("line_spacing", name, 0)
	theme.set_type_variation("CardReply", "LineEdit")
	for state: String in ["normal", "focus", "read_only"]:
		var field := _flat(art.color(ArtContract.PAPER if state == "focus" else ArtContract.CREAM))
		field.set_border_width_all(1)
		field.border_color = art.color(ArtContract.INK if state == "focus" else ArtContract.WOOD_SHADOW)
		field.content_margin_left = 2
		field.content_margin_right = 2
		field.content_margin_top = 1
		field.content_margin_bottom = 1
		theme.set_stylebox(state, "CardReply", field)
	theme.set_color("font_color", "CardReply", art.color(ArtContract.INK))
	theme.set_color("font_placeholder_color", "CardReply", art.color(ArtContract.SLATE))
	theme.set_color("caret_color", "CardReply", art.color(ArtContract.INK))
	theme.set_color("selection_color", "CardReply", art.color(ArtContract.WOOD_SHADOW))
	theme.set_color("font_selected_color", "CardReply", art.color(ArtContract.PAPER))


## The floor plate in the world (scenes/world/floor_plate.tscn): a band of the
## pack's panel whose text keeps clear of its frame, and a title in the world's
## own 13-unit lettering rather than a HUD heading's heavier cut.
static func _plate(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("PlateBand", "PanelContainer")
	var band := StyleBoxEmpty.new()
	band.content_margin_left = 8
	band.content_margin_right = 8
	band.content_margin_top = 4
	band.content_margin_bottom = 1
	theme.set_stylebox("panel", "PlateBand", band)
	_label(theme, &"PlateTitle", 13, art.color(ArtContract.INK))


## The signposts over the world's right edge (scenes/ui/signpost.tscn): a
## small framed button in the card action's look, the same unmistakable
## disabled look for the `+N floors` post, which is a note, not a way there,
## and the spacing of a post's line in its full and its compact form.
## The post's words are its own Labels, which keep their colour on hover, so
## the hover fill is the light one a minimap row takes, where they still read.
static func _signpost(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("Signpost", "Button")
	for state: String in BUTTON_STATES:
		var fill := ArtContract.CREAM
		if state == "hover" or state == "pressed":
			fill = ArtContract.CREAM_SHADOW
		var box := _flat(art.color(fill))
		box.set_border_width_all(1)
		box.border_color = art.color(ArtContract.INK)
		if state == "disabled":
			box.bg_color = Color.TRANSPARENT
			box.border_color = art.color(ArtContract.MUTED)
		box.content_margin_left = 2
		box.content_margin_right = 2
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		theme.set_stylebox(state, "Signpost", box)
	# A post's line: its words spaced as a card's.
	theme.set_type_variation(&"SignpostLine", "HBoxContainer")
	theme.set_constant("separation", &"SignpostLine", 3)


## The panel type HdPanel draws itself: the stylebox is empty on purpose and
## carries only the pack's nine-patch margins, in units, so children start
## where the drawn frame ends.
static func _panel(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("HdPanel", "PanelContainer")
	var spec := art.panel()
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = spec.patch_left
	empty.content_margin_top = spec.patch_top
	empty.content_margin_right = spec.patch_right
	empty.content_margin_bottom = spec.patch_bottom
	theme.set_stylebox("panel", "HdPanel", empty)


## The minimap's rows. Godot's default Button draws grey chrome and a focus
## ring; every button here is drawn by the art pack instead.
static func _buttons(theme: Theme, art: ArtPack) -> void:
	for state: String in BUTTON_STATES:
		theme.set_stylebox(state, "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", art.color(ArtContract.INK))
	for name: String in ["FloorRow", "FloorRowCurrent", "FloorRowPointed"]:
		theme.set_type_variation(name, "Button")
		theme.set_constant("outline_size", name, 0)
	# The shown floor is the only broad highlight in the minimap.
	for state: String in BUTTON_STATES:
		theme.set_stylebox(state, "FloorRow", StyleBoxEmpty.new())
		theme.set_stylebox(state, "FloorRowCurrent", _flat(art.color(ArtContract.INK)))
	theme.set_stylebox("hover", "FloorRow", _flat(art.color(ArtContract.CREAM_SHADOW)))
	theme.set_stylebox("pressed", "FloorRow", _flat(art.color(ArtContract.WOOD_SHADOW)))
	# A floor a hovered HUD line names: a 1-unit ink edge and no fill, in
	# every state, beside the current floor's filled row.
	for state: String in BUTTON_STATES:
		var edge := _flat(Color.TRANSPARENT)
		edge.draw_center = false
		edge.set_border_width_all(1)
		edge.border_color = art.color(ArtContract.INK)
		theme.set_stylebox(state, "FloorRowPointed", edge)
	for name: String in ["FloorRow", "FloorRowCurrent", "FloorRowPointed"]:
		for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(role, name, art.color(ArtContract.INK))


## The bar's Attention button (AttentionEntry), and the flat buttons and
## pickers the Avatar Studio borrows (AttentionAction, AttentionFilter); the
## native PopupMenu, which the agent list's row menu is, in the HUD palette.
static func _attention(theme: Theme, art: ArtPack) -> void:
	for name: String in ["AttentionAction", "AttentionEntry", "AttentionFilter"]:
		theme.set_type_variation(name, "OptionButton" if name == "AttentionFilter" else "Button")
		for state: String in BUTTON_STATES:
			var color := ArtContract.WOOD_SHADOW if state == "hover" or state == "pressed" else ArtContract.CREAM
			var box := _flat(art.color(color))
			box.content_margin_left = 6
			box.content_margin_right = 6
			box.content_margin_top = 3
			box.content_margin_bottom = 3
			if state == "focus":
				box.bg_color = Color.TRANSPARENT
				box.set_border_width_all(1)
				box.border_color = art.color(ArtContract.INK)
			theme.set_stylebox(state, name, box)
		for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			var ink := ArtContract.PAPER if role in ["font_hover_color", "font_pressed_color"] else ArtContract.INK
			theme.set_color(role, name, art.color(ink))
		theme.set_color("font_disabled_color", name, art.color(ArtContract.SLATE))
	# Native popups (an OptionButton's, the row menu) share the HUD palette.
	theme.set_stylebox("panel", "PopupMenu", _flat(art.color(ArtContract.PAPER)))
	theme.set_stylebox("hover", "PopupMenu", _flat(art.color(ArtContract.WOOD_SHADOW)))
	theme.set_color("font_color", "PopupMenu", art.color(ArtContract.INK))
	theme.set_color("font_hover_color", "PopupMenu", art.color(ArtContract.PAPER))


## The top bar's counters (scenes/ui/counter.tscn): cream chips with an ink
## edge on the dark bar. BLOCKED above zero, and MACHINES while a machine is
## down, wear the blocked colour (CounterHot); a counter whose filter the agent
## list shows reads pressed, in ink (CounterOn). The pointer thickens the edge
## rather than darkening the fill: INK on WOOD_SHADOW is 2.4:1 (measured), and
## the labels are the counter's own, not the button's text, so they cannot
## change colour with it.
static func _counters(theme: Theme, art: ArtPack) -> void:
	var fills: Dictionary[StringName, StringName] = {
		&"Counter": ArtContract.CREAM,
		&"CounterHot": ArtContract.BLOCKED,
		&"CounterOn": ArtContract.INK,
	}
	for name: StringName in fills:
		theme.set_type_variation(name, "Button")
		theme.set_constant("outline_size", name, 0)
		for state: String in BUTTON_STATES:
			var box := _flat(art.color(fills[name]))
			box.set_border_width_all(2 if state == "hover" or state == "pressed" else 1)
			box.border_color = art.color(ArtContract.PAPER if name == &"CounterOn" else ArtContract.INK)
			box.content_margin_left = 2
			box.content_margin_right = 2
			box.content_margin_top = 1
			box.content_margin_bottom = 1
			theme.set_stylebox(state, name, box)
	# A title over a number is 33 units of line box (14 + 19, measured) in a
	# 26-unit counter, and neither line has a descender or an accent: capitals,
	# digits, `/`, `max 12m`. Trimming each face's line box, not overlapping
	# the labels, keeps the pair inside the counter.
	for name: StringName in [&"CounterTitle", &"CounterTitlePaper", &"CounterValue", &"CounterValuePaper"]:
		# A copy of the face the variation already has, so the numbers keep the
		# heading's weight: a FontVariation wrapped in another one loses its
		# own variation axes (seen in the capture: regular-weight numbers).
		var face := theme.get_font("font", name)
		var trimmed: FontVariation = face.duplicate() if face is FontVariation else FontVariation.new()
		if face is not FontVariation:
			trimmed.base_font = face
		var value := name.begins_with("CounterValue")
		trimmed.spacing_top = COUNTER_VALUE_TRIM.x if value else COUNTER_TITLE_TRIM.x
		trimmed.spacing_bottom = COUNTER_VALUE_TRIM.y if value else COUNTER_TITLE_TRIM.y
		theme.set_font("font", name, trimmed)


## The top bar's chime switch (OfficeBar, `%Chime`): an outline, not a chip, so
## it never reads as a seventh counter. Off (BarSwitch) it is the right-hand
## lines' muted colour; on (BarSwitchOn), their cream. The pointer thickens the
## edge, as on a counter.
static func _chime_switch(theme: Theme, art: ArtPack) -> void:
	var inks: Dictionary[StringName, StringName] = {&"BarSwitch": ArtContract.MUTED, &"BarSwitchOn": ArtContract.CREAM}
	for name: StringName in inks:
		theme.set_type_variation(name, "Button")
		theme.set_constant("outline_size", name, 0)
		var ink := art.color(inks[name])
		for state: String in BUTTON_STATES + ["hover_pressed"]:
			var box := _flat(Color.TRANSPARENT)
			box.draw_center = false
			box.set_border_width_all(2 if state.begins_with("hover") or state == "pressed" else 1)
			box.border_color = ink
			box.content_margin_left = 4
			box.content_margin_right = 4
			box.content_margin_top = 0
			box.content_margin_bottom = 0
			theme.set_stylebox(state, name, box)
		for role: String in [
			"font_color",
			"font_hover_color",
			"font_pressed_color",
			"font_hover_pressed_color",
			"font_focus_color",
			"font_disabled_color"
		]:
			theme.set_color(role, name, ink)


## Every HUD tooltip (the counters' breakdowns, a list row's details, a
## button's hint): ink on paper with an ink edge. Godot's own tooltip panel is
## dark and see-through, and the tooltip's text takes this theme's ink Label
## colour, so without these the two were near one colour (seen in hover
## captures).
static func _tooltips(theme: Theme, art: ArtPack) -> void:
	var box := _flat(art.color(ArtContract.PAPER))
	box.set_border_width_all(1)
	box.border_color = art.color(ArtContract.INK)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	theme.set_stylebox("panel", "TooltipPanel", box)
	theme.set_font_size("font_size", "TooltipLabel", 10)
	theme.set_color("font_color", "TooltipLabel", art.color(ArtContract.INK))
	theme.set_color("font_shadow_color", "TooltipLabel", Color.TRANSPARENT)
	theme.set_constant("outline_size", "TooltipLabel", 0)


## The agent list (scenes/ui/agent_list*.tscn): rows that light up under the
## pointer, the selected row in ink like the minimap's shown floor, group
## headers on a cream band with a rule under it, the Flat / Tree switch, the rows' `⋯` and the
## filter box, drawn like the card's reply box. The drawer's two pages (this
## list and EVENTS) scroll with a thin bar (`DrawerScroll`, the OVERVIEW's look
## at DRAWER_BAR wide) a gap (`DrawerRowsGap`) right of their rows; their
## scrolls reserve that room whether the bar shows or not, so a row's right edge
## never moves, and the room is the pages' right padding, not the rows'.
static func _agent_list(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("ListRow", "Button")
	theme.set_type_variation("ListRowCurrent", "Button")
	theme.set_type_variation("ListGroup", "Button")
	theme.set_type_variation("ListMore", "Button")
	# CREAM, not CREAM_SHADOW: the shadow was dark in the retired dusk pack, and the rows' dark
	# text on it could not be read (seen in its capture).
	for state: String in BUTTON_STATES:
		var hover := state == "hover" or state == "pressed"
		var lit: StyleBox = _flat(art.color(ArtContract.CREAM)) if hover else StyleBoxEmpty.new()
		theme.set_stylebox(state, "ListRow", lit)
		theme.set_stylebox(state, "ListRowCurrent", _flat(art.color(ArtContract.INK)))
		var band := _flat(art.color(ArtContract.CREAM))
		band.border_width_bottom = 1
		band.border_color = art.color(ArtContract.WOOD_SHADOW)
		theme.set_stylebox(state, "ListGroup", band)
		# The `⋯` only shows on the selected row, which is ink: paper on it.
		var more: StyleBox = _flat(art.color(ArtContract.WOOD_SHADOW)) if hover else StyleBoxEmpty.new()
		theme.set_stylebox(state, "ListMore", more)
	for name: String in ["ListRow", "ListRowCurrent", "ListGroup", "ListMore"]:
		theme.set_constant("outline_size", name, 0)
		var on_ink := name == "ListRowCurrent" or name == "ListMore"
		for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(role, name, art.color(ArtContract.PAPER if on_ink else ArtContract.INK))
	# One indent per depth: an empty panel whose margin is the indent, so a row
	# needs a single node for it whatever its depth.
	for depth in AgentListModel.MAX_DEPTH + 1:
		var name := StringName("ListIndent%d" % depth)
		theme.set_type_variation(name, "PanelContainer")
		var indent := StyleBoxEmpty.new()
		indent.content_margin_left = LIST_INDENT * depth
		theme.set_stylebox("panel", name, indent)
	theme.set_type_variation("ListSegment", "Button")
	for state: String in BUTTON_STATES + ["hover_pressed"]:
		var on := state == "pressed" or state == "hover_pressed"
		var box := _flat(art.color(ArtContract.INK if on else ArtContract.CREAM))
		if state == "hover":
			box.bg_color = art.color(ArtContract.CREAM_SHADOW)
		box.set_border_width_all(1)
		box.border_color = art.color(ArtContract.INK)
		box.content_margin_left = 3
		box.content_margin_right = 3
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		theme.set_stylebox(state, "ListSegment", box)
	for role: String in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(role, "ListSegment", art.color(ArtContract.INK))
	for role: String in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(role, "ListSegment", art.color(ArtContract.PAPER))
	theme.set_type_variation("ListFilter", "LineEdit")
	for state: String in ["normal", "focus", "read_only"]:
		var field := _flat(art.color(ArtContract.PAPER if state == "focus" else ArtContract.CREAM))
		field.set_border_width_all(1)
		field.border_color = art.color(ArtContract.INK if state == "focus" else ArtContract.WOOD_SHADOW)
		field.content_margin_left = 3
		field.content_margin_right = 2
		field.content_margin_top = 1
		field.content_margin_bottom = 1
		theme.set_stylebox(state, "ListFilter", field)
	theme.set_color("font_color", "ListFilter", art.color(ArtContract.INK))
	theme.set_color("font_placeholder_color", "ListFilter", art.color(ArtContract.SLATE))
	theme.set_color("caret_color", "ListFilter", art.color(ArtContract.INK))
	theme.set_color("selection_color", "ListFilter", art.color(ArtContract.WOOD_SHADOW))
	theme.set_color("font_selected_color", "ListFilter", art.color(ArtContract.PAPER))
	theme.set_color("clear_button_color", "ListFilter", art.color(ArtContract.SLATE))
	theme.set_color("clear_button_color_pressed", "ListFilter", art.color(ArtContract.INK))
	# The drawer's two pages draw the OVERVIEW's bar, narrower.
	theme.set_type_variation("DrawerScroll", "VScrollBar")
	var track := _flat(art.color(ArtContract.CREAM))
	var grabber := _flat(art.color(ArtContract.INK))
	for box: StyleBoxFlat in [track, grabber]:
		box.content_margin_left = DRAWER_BAR / 2.0
		box.content_margin_right = DRAWER_BAR / 2.0
	grabber.content_margin_top = DRAWER_BAR / 2.0
	grabber.content_margin_bottom = DRAWER_BAR / 2.0
	theme.set_stylebox("scroll", "DrawerScroll", track)
	theme.set_stylebox("scroll_focus", "DrawerScroll", track)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "DrawerScroll", grabber)
	theme.set_type_variation("DrawerRowsGap", "MarginContainer")
	theme.set_constant("margin_right", "DrawerRowsGap", DRAWER_BAR_GAP)


## `face` at `pixels`, never taller than `own` (the face without its fallbacks):
## Godot sizes a row by the tallest font in the chain.
static func _fit(face: Font, own: Font, pixels: int) -> Font:
	var extra := face.get_height(pixels) - own.get_height(pixels)
	if extra <= 0.0:
		return face
	var fitted: FontVariation = face.duplicate() if face is FontVariation else FontVariation.new()
	if face is not FontVariation:
		fitted.base_font = face
	fitted.spacing_top -= int(extra)
	return fitted


static func _label(theme: Theme, name: StringName, pixels: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, pixels)
	theme.set_color("font_color", name, color)


static func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


## The minimap's windows (scenes/ui/floor_row.tscn): one flat palette colour
## per state a window can show, on a dark facade; the `+N` after the eighth
## window; and the plate's worktree-group accents, which follow structure and
## never state.
static func _section(theme: Theme, art: ArtPack) -> void:
	for name: StringName in SECTION_PANELS:
		theme.set_type_variation(name, "Panel")
		theme.set_stylebox("panel", name, _flat(art.color(SECTION_PANELS[name])))
	for index in ArtContract.ACCENTS.size():
		var accent := StringName("PlateAccent%d" % index)
		theme.set_type_variation(accent, "Panel")
		theme.set_stylebox("panel", accent, _flat(art.color(ArtContract.ACCENTS[index])))
	theme.set_type_variation("SectionFacade", "PanelContainer")
	var facade := _flat(art.color(ArtContract.INK))
	facade.set_content_margin_all(1)
	theme.set_stylebox("panel", "SectionFacade", facade)
	_label(theme, &"WindowMore", 9, art.color(ArtContract.SLATE))
	_label(theme, &"WindowMoreCurrent", 9, art.color(ArtContract.PAPER))


## The terminal monitor (scenes/ui/terminal_monitor.tscn): herdr's own screen on
## a dark field inside the pack's panel, a backdrop over the office, and the
## grid's fonts: an explicit stack per system (monitor_faces()), bold and
## italic cuts of it, and the terminal's default colours.
static func _monitor(theme: Theme, art: ArtPack, font: Font) -> void:
	theme.set_type_variation("MonitorBackdrop", "Panel")
	var shade := art.color(ArtContract.INK)
	shade.a = 0.7
	theme.set_stylebox("panel", "MonitorBackdrop", _flat(shade))
	theme.set_type_variation("MonitorScreen", "PanelContainer")
	var screen := _flat(art.color(ArtContract.INK))
	screen.set_border_width_all(1)
	screen.border_color = art.color(ArtContract.SLATE)
	screen.set_content_margin_all(2)
	theme.set_stylebox("panel", "MonitorScreen", screen)
	theme.set_type_variation("MonitorGrid", "Control")
	var faces := monitor_faces(OS.get_name())
	for role: String in ["font", "bold_font", "italic_font"]:
		var face := SystemFont.new()
		face.font_names = faces[0]
		face.font_weight = 700 if role == "bold_font" else 400
		face.font_italic = role == "italic_font"
		var fallbacks: Array[Font] = []
		for names: PackedStringArray in faces.slice(1):
			var fallback := SystemFont.new()
			fallback.font_names = names
			fallbacks.append(fallback)
		# The HUD's own face last: whatever the system lacks, it still has a glyph for.
		fallbacks.append(font)
		face.fallbacks = fallbacks
		theme.set_font(role, "MonitorGrid", face)
	theme.set_color("default_fg", "MonitorGrid", art.color(ArtContract.PAPER))
	theme.set_color("default_bg", "MonitorGrid", art.color(ArtContract.INK))
	theme.set_color("letterbox", "MonitorGrid", art.color(ArtContract.INK).darkened(0.35))


## The terminal monitor's font stack for system `os_name` (OS.get_name()): the
## monospace face first, then CJK, then colour emoji, each its own SystemFont.
## Measured on macOS: SystemFont cannot load PingFang SC (FreeType
## "Error loading font ''"), while Hiragino Sans GB renders Han with no error.
## Linux gets the Noto family and DejaVu. Anything else tries both.
static func monitor_faces(os_name: String) -> Array[PackedStringArray]:
	if os_name == "macOS":
		return [
			PackedStringArray(["Menlo", "SF Mono", "Monaco"]),
			PackedStringArray(["Hiragino Sans GB"]),
			PackedStringArray(["Apple Color Emoji"]),
		]
	if os_name == "Linux" or os_name == "FreeBSD":
		return [
			PackedStringArray(["DejaVu Sans Mono", "Noto Sans Mono", "monospace"]),
			PackedStringArray(["Noto Sans Mono CJK SC", "Noto Sans CJK SC"]),
			PackedStringArray(["Noto Color Emoji"]),
		]
	return [
		PackedStringArray(["Menlo", "DejaVu Sans Mono", "Consolas", "monospace"]),
		PackedStringArray(["Hiragino Sans GB", "Noto Sans CJK SC", "Microsoft YaHei"]),
		PackedStringArray(["Apple Color Emoji", "Noto Color Emoji", "Segoe UI Emoji"]),
	]
