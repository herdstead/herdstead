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
##
## The HUD is dark (2026-09-30): its panels are the pack's `ink` nine-patch
## with a `slate` ring, the bar, NEWS and screens the darker `deep`, text
## `paper`, and a raised or chosen thing `slate`. A Label variation keeps the
## name it had on the light HUD (LabelSlate, LabelWoodDark, …): the role, now
## drawn in the colour that plays it on the dark ground (LABEL_COLORS).

## Palette key per Label variation. Plain `Label` is `paper`. Secondary text
## (LabelSlate) is `muted`, fainter text (LabelMuted) `jacket_light`, and the
## warm accents (LabelWoodDark, LabelWoodShadow) `wood_light`.
const LABEL_COLORS: Dictionary[StringName, StringName] = {
	&"LabelSlate": ArtContract.MUTED,
	&"LabelMuted": ArtContract.JACKET_LIGHT,
	&"LabelPaper": ArtContract.PAPER,
	&"LabelInk": ArtContract.INK,
	&"LabelWoodDark": ArtContract.WOOD_LIGHT,
	&"LabelWoodShadow": ArtContract.WOOD_LIGHT,
	&"LabelBlocked": ArtContract.BLOCKED,
	&"LabelWorking": ArtContract.WORKING,
	&"LabelCream": ArtContract.CREAM,
}
## Label variations that also change the size, and the palette key they take.
## Every size is one of a cut's own (OfficeDraw.cut_for()), and each wears the
## cut drawn at it (build()): the headings the heading cut at 12, the small
## rows (the portrait cards' and folds' words) the
## display cut at 8. A heading's
## variation keeps the name of the size it had before the pixel faces
## (Heading13, Heading16): the scenes name them.
const LABEL_SIZES: Dictionary[StringName, int] = {
	&"Heading13": 12,
	&"Heading16": 12,
	&"Heading16Paper": 12,
	&"Heading16Slate": 12,
	&"Heading13Blocked": 12,
	&"PortraitName": 8,
	&"PortraitPlace": 8,
	&"PortraitWait": 8,
	&"PortraitCount": 8,
}
const LABEL_HEADINGS: Dictionary[StringName, StringName] = {
	&"Heading13": ArtContract.PAPER,
	&"Heading16": ArtContract.PAPER,
	&"Heading16Paper": ArtContract.PAPER,
	&"Heading16Slate": ArtContract.MUTED,
	&"Heading13Blocked": ArtContract.BLOCKED,
	# The top bar's portrait cards: the name in paper over its space in muted,
	# a blocked agent's wait in the blocked colour; a fold's number in paper
	# over its word in muted (PortraitPlace).
	&"PortraitName": ArtContract.PAPER,
	&"PortraitPlace": ArtContract.MUTED,
	&"PortraitWait": ArtContract.BLOCKED,
	&"PortraitCount": ArtContract.PAPER,
}
## The fixed ASCII headings: the wordmark in the display cut at twice its 8,
## and NEWS and NEXT in the heading cut at its 12 (OfficeDraw.cut_for()).
## A pack without the cut writes them in the text cut at its 10.
const DISPLAY_SIZES: Dictionary[StringName, int] = {
	&"Wordmark": 16,
	&"DisplayHeading": 12,
	&"DisplayHeadingMuted": 12,
}
const DISPLAY_COLORS: Dictionary[StringName, StringName] = {
	&"Wordmark": ArtContract.PAPER,
	&"DisplayHeading": ArtContract.PAPER,
	&"DisplayHeadingMuted": ArtContract.MUTED,
}
## Panel variations that are a flat fill of one palette colour: the bar's ground.
const FLAT_PANELS: Dictionary[StringName, StringName] = {
	&"BarBackground": ArtContract.DEEP,
}
## The one colour scale of a pane's state (StrategicModel.window_look() picks
## one per pane): a state's own colour, idle
## lit plainly, and dark for a shell or a machine that is not answering. The
## strategic view's squares and the lens's washes wear it.
const SECTION_PANELS: Dictionary[StringName, StringName] = {
	&"WindowWorking": ArtContract.WORKING,
	&"WindowBlocked": ArtContract.BLOCKED,
	&"WindowDone": ArtContract.UNREAD,
	&"WindowIdle": ArtContract.CREAM,
	&"WindowUnknown": ArtContract.MUTED,
	&"WindowDark": ArtContract.SLATE,
}
## How much of the office shows through the dim under the answer-mode panel
## (`ModalDim`, `deep` at this opacity): enough to see which desk it is about.
const MODAL_DIM := 0.55
## The frames HdPanel draws, by the theme variation that carries each one's
## content margins: the HUD's dark panel, and the bottom panel's wood with
## brass corners (OfficeBottomPanel; S3 SKIN).
const PANEL_FRAMES: Dictionary[StringName, StringName] = {
	&"HdPanel": ArtContract.UI_HUD_PANEL,
	&"HdPanelWood": ArtContract.UI_PANEL_WOOD,
}
## The agent card's state pill (CardDetails.pill_of()): a state's own colour,
## the quiet one `slate`.
const STATE_PILLS: Dictionary[StringName, StringName] = {
	&"StatePillWorking": ArtContract.WORKING,
	&"StatePillBlocked": ArtContract.BLOCKED,
	&"StatePillDone": ArtContract.UNREAD,
	&"StatePillIdle": ArtContract.CREAM,
	&"StatePillQuiet": ArtContract.SLATE,
}
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
## The bottom panel's key-hint icons (ArtContract.UI_KEY_ENTER / UI_EXPAND), in units.
const KEY_HINT_ICON := 10
const PREVIEW_SIZE := 7
const PREVIEW_LINE_SPACING := -1
## The OVERVIEW's scroll bar, and the gap between it and the timelines, in
## units. overview.tscn's `%BarRoom` is their sum less the heads' separation.
const OVERVIEW_BAR := 4
const OVERVIEW_BAR_GAP := 4
## The bottom panel's pages' scroll bar and its gap, in units: together the 4
## units their Frame does not pad on the right (event_list.tscn,
## history_list.tscn), so a row's right edge never moves.
const PAGE_BAR := 2
const PAGE_BAR_GAP := 2


## The whole HUD's look. `font` is the pack's text cut over its fallbacks
## (OfficeDraw.font): the body at its native 10. Every other size wears the
## pack's cut drawn at it in front of the same fallbacks (_sized(),
## OfficeDraw.face_for()): headings are the heading cut, not a bolder weight.
static func build(art: ArtPack, font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = OfficeDraw.face_for(art, OfficeDraw.TEXT_PIXELS, font)
	theme.default_font_size = OfficeDraw.TEXT_PIXELS
	theme.set_color("font_color", "Label", art.color(ArtContract.PAPER))
	for name in LABEL_COLORS:
		_label(theme, name, OfficeDraw.TEXT_PIXELS, art.color(LABEL_COLORS[name]))
		# The face too, not only the size: the overview's time axis draws its
		# marks with LabelSlate's font by name, and without one it drew Godot's own.
		_sized(theme, art, font, name, OfficeDraw.TEXT_PIXELS)
	for name in LABEL_HEADINGS:
		_label(theme, name, LABEL_SIZES[name], art.color(LABEL_HEADINGS[name]))
		_sized(theme, art, font, name, LABEL_SIZES[name])
	for name: StringName in DISPLAY_SIZES:
		_label(theme, name, DISPLAY_SIZES[name], art.color(DISPLAY_COLORS[name]))
		_sized(theme, art, font, name, DISPLAY_SIZES[name])
	for name in FLAT_PANELS:
		theme.set_type_variation(name, "Panel")
		theme.set_stylebox("panel", name, _flat(art.color(FLAT_PANELS[name])))
	for name: StringName in STATE_PILLS:
		theme.set_type_variation(name, "PanelContainer")
		var pill := _flat(art.color(STATE_PILLS[name]))
		pill.set_corner_radius_all(2)
		pill.anti_aliasing = false
		pill.content_margin_left = 4
		pill.content_margin_right = 4
		theme.set_stylebox("panel", name, pill)
	theme.set_type_variation(&"ModalDim", "Panel")
	theme.set_stylebox("panel", &"ModalDim", _flat(Color(art.color(ArtContract.DEEP), MODAL_DIM)))
	_panel(theme, art)
	_buttons(theme, art)
	_attention(theme, art)
	_portraits(theme, art)
	_chime_switch(theme, art)
	_bar_line(theme, art, font)
	_machine_chips(theme, art, font)
	_tooltips(theme, art)
	_pages(theme, art)
	_edge_arrows(theme, art)
	_plate(theme, art, font)
	_card(theme, art, font)
	_section(theme, art)
	_monitor(theme, art, font)
	_news(theme, art)
	_overview(theme, art, font)
	_strategic(theme, art, font)
	return theme


## `name` at `pixels` in the cut drawn at that size, in front of `font`'s
## fallbacks, its row no taller than the cut's own (OfficeDraw.face_for(): the
## one place a size picks its face). A size the pack has no cut for (no
## heading cut) is written at the text cut's own size (OfficeDraw.size_for()).
static func _sized(theme: Theme, art: ArtPack, font: Font, name: StringName, pixels: int) -> void:
	var size := OfficeDraw.size_for(art, pixels)
	theme.set_font_size("font_size", name, size)
	theme.set_font("font", name, OfficeDraw.face_for(art, size, font))


## The strategic view (`S`, scenes/ui/strategic.tscn), drawn by
## OfficeStrategicPlan._draw() on the pack's (dark) panel: one colour per state
## look (SECTION_PANELS, the one scale), the tables' `frame` in muted with
## a slate `divider` between their far and near seats, the tab's `caption` in
## paper and a blocked square's `wait` in ink on it, the selection's `corner`s in
## the blocked colour (the world's selection, as vector corners) and the
## pointer's dash in ink and paper (`pointer_a`, `pointer_b`, OfficePointer's).
## A zone's section caption (`section_caption`) is plain text too: paper, the
## panel's own text colour, in the face and size of the zone's sign in the
## world (the pack's display face at `section_size`), never the zone's accent,
## with a slate rule (`divider`) on from it to its column's edge.
## The measures, in units: `pad` inside a table's box, `gap` between boxes,
## `caption_height` above one, `section_caption` the band above a section's
## first row, `divider` between its two rows of seats, `ring`
## round a square (the square is its cell less the ring on both sides), `rule`
## the width of every line, `dash` a pointer stroke, `corner_part` the share of
## a cell a corner's arm takes (a cell / corner_part), and `wait_from` the
## smallest cell that writes a wait in its square. The cell ladder is the
## scene's (%Plan).
static func _strategic(theme: Theme, art: ArtPack, font: Font) -> void:
	theme.add_type("Strategic")
	for name: StringName in SECTION_PANELS:
		theme.set_color(name, "Strategic", art.color(SECTION_PANELS[name]))
	var colours: Dictionary[StringName, StringName] = {
		&"frame": ArtContract.MUTED,
		&"divider": ArtContract.SLATE,
		&"caption": ArtContract.PAPER,
		&"section_caption": ArtContract.PAPER,
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
		&"section_caption": 9,
		&"section_size": OfficeDraw.size_for(art, 8),
		&"divider": 2,
		&"ring": 2,
		&"rule": 1,
		&"dash": OfficePointer.DASH,
		&"corner_part": 4,
		&"wait_from": 24,
		&"caption_size": OfficeDraw.TEXT_PIXELS,
		&"wait_size": OfficeDraw.size_for(art, 8),
	}
	for name: StringName in measures:
		theme.set_constant(name, "Strategic", measures[name])
	# A tab's caption in the text cut; a zone's in the sign's face, the display
	# cut, and a wait in it too; each over the HUD font's own fallbacks for the
	# glyphs it lacks (a workspace's label may be anything).
	theme.set_font("caption_font", "Strategic", OfficeDraw.face_for(art, measures[&"caption_size"], font))
	theme.set_font("section_font", "Strategic", OfficeDraw.face_for(art, measures[&"section_size"], font))
	theme.set_font("wait_font", "Strategic", OfficeDraw.face_for(art, measures[&"wait_size"], font))


## The OVERVIEW (scenes/ui/overview*.tscn): rows that light `deep` under the
## pointer like the HISTORY and EVENTS rows, the selected row `slate`, an offline row
## faint; column heads on a `deep` band with a slate rule under it; and the
## `Timeline` type every timeline, the axis and the legend draw with: one
## palette colour per state, `deep` hatched in slate where nobody watched, the
## axis and now rule in muted, and the two measures of the band. The swatches
## are flat panels of the same colours. Rows that overflow show a thin scroll
## bar (`OverviewScroll`: a muted grabber on a deep track, OVERVIEW_BAR wide) a
## gap (`OverviewRowsGap`, OVERVIEW_BAR_GAP) right of the timelines, so it never
## meets their `now` rule; the table's scroll reserves that room whether the bar
## shows or not, and the heads' `%BarRoom` (overview.tscn) leaves the same, so
## the axis ends where the timelines do.
static func _overview(theme: Theme, art: ArtPack, font: Font) -> void:
	for name: String in ["OverviewRow", "OverviewRowCurrent", "OverviewRowDim", "OverviewHead"]:
		theme.set_type_variation(name, "Button")
		theme.set_constant("outline_size", name, 0)
	for state: String in BUTTON_STATES:
		var lit := state == "hover" or state == "pressed"
		var row: StyleBox = _flat(art.color(ArtContract.DEEP)) if lit else StyleBoxEmpty.new()
		theme.set_stylebox(state, "OverviewRow", row)
		theme.set_stylebox(state, "OverviewRowDim", row)
		theme.set_stylebox(state, "OverviewRowCurrent", _flat(art.color(ArtContract.SLATE)))
		var head := _flat(art.color(ArtContract.DEEP))
		head.border_width_bottom = 2 if lit else 1
		head.border_color = art.color(ArtContract.SLATE)
		head.content_margin_left = 2
		head.content_margin_right = 2
		head.content_margin_top = 1
		head.content_margin_bottom = 1
		theme.set_stylebox(state, "OverviewHead", head)
	var tones: Dictionary[String, StringName] = {
		"OverviewRow": ArtContract.PAPER,
		"OverviewRowCurrent": ArtContract.PAPER,
		"OverviewRowDim": ArtContract.JACKET_LIGHT,
		"OverviewHead": ArtContract.PAPER,
	}
	for name: String in tones:
		for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(role, name, art.color(tones[name]))
	_sized(theme, art, font, &"OverviewHead", 8)
	# A row's agent name stands clear of the badge drawn at its left (the badge
	# is the label's child, which keeps a row to ten nodes).
	var agents: Dictionary[StringName, StringName] = {
		&"OverviewAgent": ArtContract.PAPER,
		&"OverviewAgentPaper": ArtContract.PAPER,
		&"OverviewAgentMuted": ArtContract.JACKET_LIGHT,
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
		# Where nobody watched: `deep` hatched in `slate`, quieter than any state.
		&"unobserved_fill": ArtContract.DEEP,
		&"unobserved_line": ArtContract.SLATE,
		&"axis": ArtContract.MUTED,
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
	_dark_scroll(theme, art, "OverviewScroll", OVERVIEW_BAR)
	theme.set_type_variation("OverviewRowsGap", "MarginContainer")
	theme.set_constant("margin_right", "OverviewRowsGap", OVERVIEW_BAR_GAP)


## The NEWS line in the bottom panel's top row (scenes/ui/news.tscn): a flat
## `deep` band, like the top bar's ground, whose items are words on it with no
## box of their own (the pointer lightens them; one that cannot be clicked is
## muted); the bottom panel's AGENT / HISTORY / EVENTS tabs (TabBar,
## `PanelTabs`), the page shown `slate` like the OVERVIEW's pressed switch, the
## other `deep`.
static func _news(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("NewsBar", "PanelContainer")
	var band := _flat(art.color(ArtContract.DEEP))
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
	for name: String in ["PanelTabs"]:
		theme.set_type_variation(name, "TabBar")
		var fills: Dictionary[String, StringName] = {
			"tab_selected": ArtContract.SLATE,
			"tab_unselected": ArtContract.DEEP,
			"tab_hovered": ArtContract.SLATE,
			"tab_disabled": ArtContract.DEEP,
		}
		# Drawn over a focused tab; the tabs take no focus, and it must hide nothing.
		theme.set_stylebox("tab_focus", name, StyleBoxEmpty.new())
		for style: String in fills:
			var tab := _flat(art.color(fills[style]))
			tab.set_border_width_all(1)
			tab.border_color = art.color(ArtContract.MUTED if style == "tab_selected" else ArtContract.SLATE)
			tab.content_margin_left = 5
			tab.content_margin_right = 5
			tab.content_margin_top = 1
			tab.content_margin_bottom = 1
			theme.set_stylebox(style, name, tab)
		theme.set_color("font_unselected_color", name, art.color(ArtContract.MUTED))
		theme.set_color("font_hovered_color", name, art.color(ArtContract.PAPER))
		theme.set_color("font_disabled_color", name, art.color(ArtContract.JACKET_LIGHT))
		theme.set_constant("outline_size", name, 0)
		theme.set_constant("h_separation", name, 2)
		theme.set_font_size("font_size", name, 10)
	theme.set_color("font_selected_color", "PanelTabs", art.color(ArtContract.PAPER))


## The agent card (scenes/ui/inspector.tscn): its terminal preview on a `deep`
## screen, and its one action, a dark button (_dark_button()) whose disabled
## look is unmistakable. The button is disabled while the card follows herdr's
## focus, while its write is in flight and whenever the write would be
## refused, so it must not look pressable.
static func _card(theme: Theme, art: ArtPack, font: Font) -> void:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(MONO_FACES)
	mono.fallbacks = font.fallbacks
	var bare := SystemFont.new()
	bare.font_names = PackedStringArray(MONO_FACES)
	_label(theme, &"PreviewText", PREVIEW_SIZE, art.color(ArtContract.PAPER))
	theme.set_font("font", "PreviewText", OfficeDraw.no_taller(mono, bare, PREVIEW_SIZE))
	# Terminal rows sit edge to edge: twelve of them are a fixed block. A Latin
	# descender still clears the next row's capitals at this pitch.
	theme.set_constant("line_spacing", "PreviewText", PREVIEW_LINE_SPACING)
	theme.set_type_variation("PreviewScreen", "PanelContainer")
	# `deep`, a step darker than the `ink` panel it sits in, with a `slate` edge.
	var screen := _flat(art.color(ArtContract.DEEP))
	screen.set_border_width_all(1)
	screen.border_color = art.color(ArtContract.SLATE)
	screen.content_margin_left = 2
	screen.content_margin_right = 2
	screen.content_margin_top = 2
	screen.content_margin_bottom = 2
	theme.set_stylebox("panel", "PreviewScreen", screen)
	theme.set_type_variation("CardAction", "Button")
	for state: String in BUTTON_STATES:
		var box := _dark_button(art, state)
		box.content_margin_left = 6
		box.content_margin_right = 6
		box.content_margin_top = 2
		box.content_margin_bottom = 2
		theme.set_stylebox(state, "CardAction", box)
	_dark_button_text(theme, art, "CardAction")
	_answer(theme, art)
	_staff(theme, art)


## The bottom panel's NEXT button, a dark button. NEXT's words are labels of
## their own, which keep their colours: a hover thickens its edge instead of
## changing the fill under them. Off (nobody next), it keeps its `deep` fill
## with a `slate` edge, never a hollow pill.
static func _staff(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("NextAction", "Button")
	for state: String in BUTTON_STATES:
		var next := _dark_button(art, state, true)
		if state == "disabled":
			next.bg_color = art.color(ArtContract.DEEP)
		next.set_corner_radius_all(6)
		next.anti_aliasing = false
		theme.set_stylebox(state, "NextAction", next)
	# NEXT's play mark: a round `working` button with a `deep` ring, the ink ▶ on it.
	theme.set_type_variation("NextPlay", "PanelContainer")
	var play := _flat(art.color(ArtContract.WORKING))
	play.set_corner_radius_all(10)
	play.anti_aliasing = false
	play.set_border_width_all(1)
	play.border_color = art.color(ArtContract.DEEP)
	play.content_margin_left = 1
	theme.set_stylebox("panel", "NextPlay", play)


## The card's answer mode: key buttons as small as a key label allows, dark
## buttons with the same unmistakable disabled look as the card's action, the
## heading's "Answer" chip drawn like a key, and the reply box a dark field.
static func _answer(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("CardKey", "Button")
	theme.set_type_variation("CardHint", "Button")
	for state: String in BUTTON_STATES:
		var key := _dark_button(art, state)
		key.content_margin_left = 3
		key.content_margin_right = 3
		key.content_margin_top = 0
		key.content_margin_bottom = 0
		theme.set_stylebox(state, "CardKey", key)
		theme.set_stylebox(state, "CardHint", key)
	for name: String in ["CardKey", "CardHint"]:
		_dark_button_text(theme, art, name)
		# The key hints (`ui.key_enter`, `ui.expand`) are 10 units: drawn at
		# that, texel for texel at zoom 2, never stretched to the row.
		theme.set_constant("icon_max_width", name, KEY_HINT_ICON)
		theme.set_constant("h_separation", name, 3)
	# The best-effort line and the result line may take two lines in answer
	# mode; without the default 3 units between them both fit at 480x320.
	for name: StringName in [&"CardNote", &"CardOutcome"]:
		_label(theme, name, 10, art.color(ArtContract.MUTED if name == &"CardNote" else ArtContract.WOOD_LIGHT))
		theme.set_constant("line_spacing", name, 0)
	theme.set_type_variation("CardReply", "LineEdit")
	_dark_field(theme, art, "CardReply", 2)


## The machine plate in the world (scenes/world/machine_plate.tscn): a band of the
## pack's panel whose text keeps clear of its frame, a title in the heading
## cut at its native 12, and the line
## that says why the map cannot be laid out (`PlateProblem`), in the blocked
## colour, which reads on the band's dark panel.
static func _plate(theme: Theme, art: ArtPack, font: Font) -> void:
	theme.set_type_variation("PlateBand", "PanelContainer")
	var band := StyleBoxEmpty.new()
	band.content_margin_left = 8
	band.content_margin_right = 8
	band.content_margin_top = 4
	band.content_margin_bottom = 1
	theme.set_stylebox("panel", "PlateBand", band)
	_label(theme, &"PlateTitle", 12, art.color(ArtContract.PAPER))
	_sized(theme, art, font, &"PlateTitle", 12)
	_label(theme, &"PlateProblem", 10, art.color(ArtContract.BLOCKED))


## The arrows on the world's edges (scenes/ui/edge_arrow.tscn): a small dark
## button, and the spacing of an arrow's line. The `+N` note is a disabled one
## (a count, not a way there) in the same filled box: it stands on the floor,
## where the hollow frame other switched-off dark buttons take left its count
## unreadable; it has no glyph and no badge, and does not light under the
## pointer. The `EdgeArrows` type is what OfficeEdgeArrows places them by, in
## units: `inset` from the world's edge, `gap` between two arrows on one edge.
static func _edge_arrows(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("EdgeArrow", "Button")
	for state: String in BUTTON_STATES:
		var box := _dark_button(art, "normal" if state == "disabled" else state)
		box.content_margin_left = 3
		box.content_margin_right = 3
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		theme.set_stylebox(state, "EdgeArrow", box)
	theme.set_type_variation(&"EdgeArrowLine", "HBoxContainer")
	theme.set_constant("separation", &"EdgeArrowLine", 3)
	theme.add_type("EdgeArrows")
	theme.set_constant("inset", "EdgeArrows", 4)
	theme.set_constant("gap", "EdgeArrows", 4)


## The theme variation that carries the content margins of HdPanel frame
## `frame`: `HdPanelWood` for the bottom panel's wood, `HdPanel` for the
## HUD's dark panel and anything else.
static func panel_variation(frame: StringName) -> StringName:
	for variation: StringName in PANEL_FRAMES:
		if PANEL_FRAMES[variation] == frame:
			return variation
	return &"HdPanel"


## The panel types HdPanel draws itself (PANEL_FRAMES): each stylebox is empty
## on purpose and carries only its frame's nine-patch margins, in units, so
## children start where the drawn frame ends. A pack without the wood keeps the
## dark panel's margins there, as HdPanel.dress() then draws the dark panel.
static func _panel(theme: Theme, art: ArtPack) -> void:
	for variation: StringName in PANEL_FRAMES:
		theme.set_type_variation(variation, "PanelContainer")
		var spec := art.ui_sprite(PANEL_FRAMES[variation])
		if spec == null or not spec.nine_patched():
			spec = art.hud_panel()
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = spec.patch_left
		empty.content_margin_top = spec.patch_top
		empty.content_margin_right = spec.patch_right
		empty.content_margin_bottom = spec.patch_bottom
		theme.set_stylebox("panel", variation, empty)
	theme.set_type_variation("HdPanelBare", "PanelContainer")
	theme.set_stylebox("panel", "HdPanelBare", StyleBoxEmpty.new())


## Godot's default Button draws grey chrome and a focus ring; every button in
## the HUD is drawn by this theme instead.
static func _buttons(theme: Theme, art: ArtPack) -> void:
	for state: String in BUTTON_STATES:
		theme.set_stylebox(state, "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", art.color(ArtContract.PAPER))


## The flat buttons and pickers the Avatar Studio borrows (AttentionAction,
## AttentionFilter); the native PopupMenu (an OptionButton's) in the HUD palette.
static func _attention(theme: Theme, art: ArtPack) -> void:
	for name: String in ["AttentionAction", "AttentionFilter"]:
		theme.set_type_variation(name, "OptionButton" if name == "AttentionFilter" else "Button")
		for state: String in BUTTON_STATES:
			var box := _dark_button(art, state)
			box.content_margin_left = 6
			box.content_margin_right = 6
			box.content_margin_top = 3
			box.content_margin_bottom = 3
			if state == "focus":
				box.bg_color = Color.TRANSPARENT
				box.border_color = art.color(ArtContract.PAPER)
			theme.set_stylebox(state, name, box)
		_dark_button_text(theme, art, name)
	# Native popups (an OptionButton's) share the HUD palette.
	var menu := _flat(art.color(ArtContract.DEEP))
	menu.set_border_width_all(1)
	menu.border_color = art.color(ArtContract.SLATE)
	theme.set_stylebox("panel", "PopupMenu", menu)
	theme.set_stylebox("hover", "PopupMenu", _flat(art.color(ArtContract.SLATE)))
	theme.set_color("font_color", "PopupMenu", art.color(ArtContract.PAPER))
	theme.set_color("font_hover_color", "PopupMenu", art.color(ArtContract.PAPER))


## The top bar's portrait strip (OfficeBar): a card (PortraitCard<State>) and
## a fold (PortraitFold<State>) are an `ink` chip with a 1-unit edge in their
## state's colour (blocked, unread for done, working, muted for idle), 2 units
## under the pointer, as the counters were; the fold of the state the OVERVIEW
## keeps reads pressed, `slate` with a `paper` edge (PortraitFold<State>On). The
## selected card wears a 1-unit `paper` ring just inside its edge, so the
## state's colour still shows (PortraitSelected).
## A card a hovered HUD line points at wears a 1-unit `paper` ring 2 units in,
## inside the selection's, so the state's edge always shows (PortraitPointed).
## On a tile the rings lie on the cream window, where `paper` does not read: the
## selection is `ink` (PortraitSelectedTile) and the pointed ring `slate`
## (PortraitPointedTile), both far from cream and from every state's edge, and
## from each other. A card's place is a flat button
## (PortraitPlaceButton): nothing until the pointer is on it, then a 1-unit
## `paper` line under it, as a link.
## A card's words are labels of their own (LABEL_HEADINGS), not the button's
## text, so they keep their colour under the pointer.
static func _portraits(theme: Theme, art: ArtPack) -> void:
	var edges: Dictionary[String, StringName] = {
		"Blocked": ArtContract.BLOCKED,
		"Done": ArtContract.UNREAD,
		"Working": ArtContract.WORKING,
		"Idle": ArtContract.MUTED,
	}
	for state: String in edges:
		for kind: String in ["PortraitCard" + state, "PortraitFold" + state, "PortraitFold%sOn" % state]:
			var name := StringName(kind)
			var pressed := kind.ends_with("On")
			theme.set_type_variation(name, "Button")
			theme.set_constant("outline_size", name, 0)
			for look: String in BUTTON_STATES + ["hover_pressed"]:
				var box := _flat(art.color(ArtContract.SLATE if pressed else ArtContract.INK))
				var lit := look.begins_with("hover") or look == "pressed"
				box.set_border_width_all(2 if lit else 1)
				box.border_color = art.color(ArtContract.PAPER if pressed else edges[state])
				box.set_content_margin_all(0)
				theme.set_stylebox(look, name, box)
	# A tile (a tall bar's card) wears no frame of its own: its words stand on
	# the bar's ground, and its face window is a portrait's (PortraitWindow and
	# PortraitFrame<State>[Lit] below, over the portrait's edge), as B2 draws
	# it. On a card the window draws nothing (PortraitFaceBare): the card's own
	# frame is round it.
	theme.set_type_variation(&"PortraitTile", "Button")
	theme.set_constant("outline_size", &"PortraitTile", 0)
	for look: String in BUTTON_STATES + ["hover_pressed"]:
		var bare := _flat(Color.TRANSPARENT)
		bare.draw_center = false
		bare.set_content_margin_all(0)
		theme.set_stylebox(look, &"PortraitTile", bare)
	theme.set_type_variation(&"PortraitFaceBare", "Panel")
	theme.set_stylebox("panel", &"PortraitFaceBare", StyleBoxEmpty.new())
	# A portrait's window (PixelPortrait: a tile's, the agent card's): the warm
	# ground the portrait stands on (PortraitWindow, `cream`, no edge), and over
	# the portrait's edge a frame in the state's colour (PortraitFrame<State>:
	# 1 unit, 2 under a tile's pointer, …Lit), or `ink` on a dropped machine's
	# card (PortraitFrameStale). The frame draws no centre: the portrait shows
	# through it.
	theme.set_type_variation(&"PortraitWindow", "Panel")
	theme.set_stylebox("panel", &"PortraitWindow", _flat(art.color(ArtContract.CREAM)))
	var frames: Dictionary[String, StringName] = {"Stale": ArtContract.INK}
	frames.merge(edges)
	for state: String in frames:
		for lit: bool in [false, true]:
			if lit and state == "Stale":
				continue
			var frame := StringName("PortraitFrame%s%s" % [state, "Lit" if lit else ""])
			theme.set_type_variation(frame, "Panel")
			var edge := _flat(Color.TRANSPARENT)
			edge.draw_center = false
			edge.set_border_width_all(2 if lit else 1)
			edge.border_color = art.color(frames[state])
			theme.set_stylebox("panel", frame, edge)
	# The face and the words: side by side on a card, a 2-unit gap between;
	# one over the other on a tile, none (PortraitCard.set_tall()).
	var gaps: Dictionary[StringName, int] = {&"PortraitBody": 2, &"PortraitBodyTall": 0}
	for body: StringName in gaps:
		theme.set_type_variation(body, "BoxContainer")
		theme.set_constant("separation", body, gaps[body])
	theme.set_type_variation(&"PortraitSelected", "Panel")
	var ring := _flat(Color.TRANSPARENT)
	ring.draw_center = false
	ring.set_border_width_all(1)
	ring.border_color = art.color(ArtContract.PAPER)
	theme.set_stylebox("panel", &"PortraitSelected", ring)
	theme.set_type_variation(&"PortraitPointed", "Panel")
	theme.set_stylebox("panel", &"PortraitPointed", ring)
	var tile_rings: Dictionary[StringName, StringName] = {
		&"PortraitSelectedTile": ArtContract.INK,
		&"PortraitPointedTile": ArtContract.SLATE,
	}
	for look: StringName in tile_rings:
		theme.set_type_variation(look, "Panel")
		var line := _flat(Color.TRANSPARENT)
		line.draw_center = false
		line.set_border_width_all(1)
		line.border_color = art.color(tile_rings[look])
		theme.set_stylebox("panel", look, line)
	theme.set_type_variation(&"PortraitPlaceButton", "Button")
	for look: String in BUTTON_STATES + ["hover_pressed"]:
		var line := _flat(Color.TRANSPARENT)
		line.draw_center = false
		var lit := look.begins_with("hover") or look == "pressed"
		line.border_width_bottom = 1 if lit else 0
		line.border_color = art.color(ArtContract.PAPER)
		line.set_content_margin_all(0)
		theme.set_stylebox(look, &"PortraitPlaceButton", line)
	# A card's zone tag: its worktree group's carpet, flat, so it reads as the
	# room's colour beside the space's name; the index the zone's sign and
	# carpet use (OfficeZoneSign.accent_of()). It never shows state.
	for index in ArtContract.CARPETS.size():
		var tag := StringName("CarpetTag%d" % index)
		theme.set_type_variation(tag, "Panel")
		theme.set_stylebox("panel", tag, _flat(art.color(ArtContract.CARPETS[index])))


## The top bar's chime switch (OfficeBar, `%Chime`): an outline, not a chip, so
## it never reads as a portrait card. Off (BarSwitch) it is the right-hand
## lines' muted colour; on (BarSwitchOn), their cream. The pointer thickens the
## edge, as on a card.
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


## The top bar's `1 machine · 13 panes` (OfficeBar, `%Panes`): words alone at 8, in the
## right-hand lines' muted colour (BarLine), with a muted edge under the
## pointer; cream with a cream edge while the OVERVIEW is open (BarLineOn).
## And the wordmark's top margin per band (WordmarkMargin, WordmarkMarginTall).
static func _bar_line(theme: Theme, art: ArtPack, font: Font) -> void:
	# The wordmark's room over its 24-unit row (OfficeBar, `%WordmarkMargin`, centred in the band): on the
	# short band 5 above, where it has always stood; on the tall one none, which puts its caps (rows 6..18 of
	# the row, measured at 2x) on the band's middle line.
	var lifts: Dictionary[StringName, int] = {&"WordmarkMargin": 5, &"WordmarkMarginTall": 0}
	for margin: StringName in lifts:
		theme.set_type_variation(margin, "MarginContainer")
		theme.set_constant("margin_top", margin, lifts[margin])
	var inks: Dictionary[StringName, StringName] = {&"BarLine": ArtContract.MUTED, &"BarLineOn": ArtContract.CREAM}
	for name: StringName in inks:
		theme.set_type_variation(name, "Button")
		theme.set_constant("outline_size", name, 0)
		_sized(theme, art, font, name, 8)
		var ink := art.color(inks[name])
		for state: String in BUTTON_STATES + ["hover_pressed"]:
			var box := _flat(Color.TRANSPARENT)
			box.draw_center = false
			var lit := state.begins_with("hover") or state == "pressed"
			box.set_border_width_all(1 if lit or name == &"BarLineOn" else 0)
			box.border_color = ink
			box.content_margin_left = 3
			box.content_margin_right = 3
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


## The top bar's machine chips (MachineChip): the machine's label alone at 8,
## in `paper` while it answers (MachineChip), `muted` while it connects
## (MachineChipConnecting) and the blocked colour while it is offline
## (MachineChipOffline: the alarm the MACHINES counter wore); a 1-unit edge in
## the same colour under the pointer, as `13 panes`; the chip of the machine
## whose map is drawn stands on `slate` (…Current).
static func _machine_chips(theme: Theme, art: ArtPack, font: Font) -> void:
	var inks: Dictionary[String, StringName] = {
		"MachineChip": ArtContract.PAPER,
		"MachineChipConnecting": ArtContract.MUTED,
		"MachineChipOffline": ArtContract.BLOCKED,
	}
	for base: String in inks:
		for kind: String in [base, base + "Current"]:
			var name := StringName(kind)
			theme.set_type_variation(name, "Button")
			theme.set_constant("outline_size", name, 0)
			_sized(theme, art, font, name, 8)
			var ink := art.color(inks[base])
			for state: String in BUTTON_STATES + ["hover_pressed"]:
				var box := _flat(art.color(ArtContract.SLATE) if kind.ends_with("Current") else Color.TRANSPARENT)
				box.draw_center = kind.ends_with("Current")
				var lit := state.begins_with("hover") or state == "pressed"
				box.set_border_width_all(1 if lit else 0)
				box.border_color = ink
				box.content_margin_left = 3
				box.content_margin_right = 3
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


## Every HUD tooltip (the portrait cards' and folds' names, a list row's details, a
## button's hint): paper on `deep` with a muted edge. Godot's own tooltip panel
## is see-through, which the office under it would show through.
static func _tooltips(theme: Theme, art: ArtPack) -> void:
	var box := _flat(art.color(ArtContract.DEEP))
	box.set_border_width_all(1)
	box.border_color = art.color(ArtContract.MUTED)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	theme.set_stylebox("panel", "TooltipPanel", box)
	theme.set_font_size("font_size", "TooltipLabel", 10)
	theme.set_color("font_color", "TooltipLabel", art.color(ArtContract.PAPER))
	theme.set_color("font_shadow_color", "TooltipLabel", Color.TRANSPARENT)
	theme.set_constant("outline_size", "TooltipLabel", 0)


## The bottom panel's HISTORY and EVENTS rows (HistoryRow, EventRow): a row
## lights `deep` under the pointer, the selected row is `slate` like the top
## bar's current machine chip. The OVERVIEW's sort and filter switches
## (ListSegment). The pages scroll with a thin bar (`PageScroll`, the
## OVERVIEW's look at PAGE_BAR wide) a gap (`PageRowsGap`) right of their rows;
## their scrolls reserve that room whether the bar shows or not, so a row's
## right edge never moves, and the room is the pages' right padding, not the
## rows'. The strategic view's scroll wears the same bar.
static func _pages(theme: Theme, art: ArtPack) -> void:
	theme.set_type_variation("ListRow", "Button")
	theme.set_type_variation("ListRowCurrent", "Button")
	for state: String in BUTTON_STATES:
		var hover := state == "hover" or state == "pressed"
		var lit: StyleBox = _flat(art.color(ArtContract.DEEP)) if hover else StyleBoxEmpty.new()
		theme.set_stylebox(state, "ListRow", lit)
		theme.set_stylebox(state, "ListRowCurrent", _flat(art.color(ArtContract.SLATE)))
	for name: String in ["ListRow", "ListRowCurrent"]:
		theme.set_constant("outline_size", name, 0)
		for role: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(role, name, art.color(ArtContract.PAPER))
	theme.set_type_variation("ListSegment", "Button")
	for state: String in BUTTON_STATES + ["hover_pressed"]:
		var on := state == "pressed" or state == "hover_pressed"
		var box := _flat(art.color(ArtContract.SLATE if on else ArtContract.DEEP))
		if state == "hover":
			box.bg_color = art.color(ArtContract.INK)
		box.set_border_width_all(1)
		box.border_color = art.color(ArtContract.MUTED if on else ArtContract.SLATE)
		box.content_margin_left = 3
		box.content_margin_right = 3
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		theme.set_stylebox(state, "ListSegment", box)
	for role: String in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(role, "ListSegment", art.color(ArtContract.MUTED))
	for role: String in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(role, "ListSegment", art.color(ArtContract.PAPER))
	# The pages draw the OVERVIEW's bar, narrower.
	_dark_scroll(theme, art, "PageScroll", PAGE_BAR)
	theme.set_type_variation("PageRowsGap", "MarginContainer")
	theme.set_constant("margin_right", "PageRowsGap", PAGE_BAR_GAP)


static func _label(theme: Theme, name: StringName, pixels: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, pixels)
	theme.set_color("font_color", name, color)


static func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


## A dark HUD button in `state`: `deep` with a `muted` edge, `slate` under the
## pointer or pressed, and switched off an edge alone, in `slate`: it reads as
## off, not as waiting for a click. `thick` hovers with a 2-unit edge instead.
static func _dark_button(art: ArtPack, state: String, thick := false) -> StyleBoxFlat:
	var lit := state == "hover" or state == "pressed" or state == "hover_pressed"
	var box := _flat(art.color(ArtContract.SLATE if lit and not thick else ArtContract.DEEP))
	box.set_border_width_all(2 if lit and thick else 1)
	box.border_color = art.color(ArtContract.MUTED)
	if state == "disabled":
		box.bg_color = Color.TRANSPARENT
		box.border_color = art.color(ArtContract.SLATE)
	return box


## A dark HUD button's text: `paper`, `jacket_light` when switched off.
static func _dark_button_text(theme: Theme, art: ArtPack, name: String) -> void:
	for role: String in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		theme.set_color(role, name, art.color(ArtContract.PAPER))
	theme.set_color("font_disabled_color", name, art.color(ArtContract.JACKET_LIGHT))


## A dark text field (the reply box, the list's filter): `deep`, a `slate`
## edge that turns `paper` with the keyboard, `paper` text.
static func _dark_field(theme: Theme, art: ArtPack, name: String, left: int) -> void:
	for state: String in ["normal", "focus", "read_only"]:
		var field := _flat(art.color(ArtContract.DEEP))
		field.set_border_width_all(1)
		field.border_color = art.color(ArtContract.PAPER if state == "focus" else ArtContract.SLATE)
		field.content_margin_left = left
		field.content_margin_right = 2
		field.content_margin_top = 1
		field.content_margin_bottom = 1
		theme.set_stylebox(state, name, field)
	theme.set_color("font_color", name, art.color(ArtContract.PAPER))
	theme.set_color("font_placeholder_color", name, art.color(ArtContract.MUTED))
	theme.set_color("caret_color", name, art.color(ArtContract.PAPER))
	theme.set_color("selection_color", name, art.color(ArtContract.SLATE))
	theme.set_color("font_selected_color", name, art.color(ArtContract.PAPER))


## A thin dark scroll bar `wide` units across: a `muted` grabber on a `deep` track.
static func _dark_scroll(theme: Theme, art: ArtPack, name: String, wide: int) -> void:
	theme.set_type_variation(name, "VScrollBar")
	var track := _flat(art.color(ArtContract.DEEP))
	var grabber := _flat(art.color(ArtContract.MUTED))
	for box: StyleBoxFlat in [track, grabber]:
		box.content_margin_left = wide / 2.0
		box.content_margin_right = wide / 2.0
	grabber.content_margin_top = wide / 2.0
	grabber.content_margin_bottom = wide / 2.0
	theme.set_stylebox("scroll", name, track)
	theme.set_stylebox("scroll_focus", name, track)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, name, grabber)


## The state scale as flat panels (SECTION_PANELS), and the plate's
## worktree-group accents, which follow structure and never state.
static func _section(theme: Theme, art: ArtPack) -> void:
	for name: StringName in SECTION_PANELS:
		theme.set_type_variation(name, "Panel")
		theme.set_stylebox("panel", name, _flat(art.color(SECTION_PANELS[name])))
	for index in ArtContract.ACCENTS.size():
		var accent := StringName("PlateAccent%d" % index)
		theme.set_type_variation(accent, "Panel")
		theme.set_stylebox("panel", accent, _flat(art.color(ArtContract.ACCENTS[index])))


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
	var screen := _flat(art.color(ArtContract.DEEP))
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
	theme.set_color("default_bg", "MonitorGrid", art.color(ArtContract.DEEP))
	theme.set_color("letterbox", "MonitorGrid", art.color(ArtContract.DEEP).darkened(0.35))


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
