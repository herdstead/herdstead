class_name CardDetails
extends BoxContainer
## The agent card's header and details (OfficePaneInspector): the portrait and
## its badge, provider, status caption, seat, machine and the footnote, and the
## PANE list (id, label, directories, session, terminal title). It only writes
## the text, visibility and tooltips of the nodes the scene holds under it, and
## the one portrait; what they say is the picture's
## (CardPicture.header_of()). It never lays anything out and never talks to
## the fleet. The preview, the actions and the launch block beside them are
## the card's.
##
## The script sits on the card scene's own `%Detail` node, so its children stay
## the card's unique names (`%CardName`, `%MoreList`, …).

## The terminal title never takes more than this many lines, however tall the
## panel is; past that the panel would read as a log, not as a caption.
const TITLE_LINES := 5
## The variation each frame (CardPicture.Header.frame) wears (HudTheme._portraits()).
const FRAMES: Dictionary[StringName, StringName] = {
	CardPicture.FRAME_BLOCKED: &"PortraitFrameBlocked",
	CardPicture.FRAME_UNREAD: &"PortraitFrameDone",
	CardPicture.FRAME_WORKING: &"PortraitFrameWorking",
	CardPicture.FRAME_IDLE: &"PortraitFrameIdle",
	CardPicture.FRAME_STALE: &"PortraitFrameStale",
}

## What the portrait is dressed as now: provider, pack and pane, so a theme
## switch or another pane re-dresses it and nothing else does.
var _portrait_look := ""
var _portrait: PixelPortrait
## Whether the shown state has a note (a dropped machine's, or UNREAD's).
var _has_note := false


func _ready() -> void:
	var title_holder: Control = %TitleHolder
	title_holder.resized.connect(_fit_title)
	var more: Control = %More
	var more_list: Container = %MoreList
	more.resized.connect(_fit_more)
	more_list.sort_children.connect(_fit_more)


## A pack swap is a new portraits family: the portrait is dressed again on its
## next show().
func forget_look() -> void:
	_portrait_look = ""


## The portrait while there is one; null before the first.
func portrait() -> PixelPortrait:
	return _portrait


## No pane: no person and no badge.
func clear() -> void:
	_show_portrait(null, null)


## Write `header` (CardPicture.header_of(): who sits there, in what state and
## where, and the PANE list), with the portrait in `art`'s people.
func show_header(header: CardPicture.Header, art: ArtPack) -> void:
	var card_name: Label = %CardName
	var caption: Label = %Caption
	var pill: PanelContainer = %CaptionPill
	var machine_label: Label = %Machine
	var seat: Label = %Seat
	var pane_id: Label = %PaneId
	var cwd_label: Label = %Cwd
	var title: Label = %TerminalTitle
	var footnote: Label = %Footnote
	var pane_label: Label = %PaneLabel
	var foreground: Label = %ForegroundCwd
	var session_label: Label = %Session
	card_name.text = header.name
	card_name.tooltip_text = header.name
	caption.text = header.caption
	pill.theme_type_variation = header.pill
	caption.theme_type_variation = header.caption_look
	caption.tooltip_text = header.caption_tip
	machine_label.visible = header.machine_shown
	machine_label.text = header.machine
	machine_label.tooltip_text = header.machine
	seat.text = header.seat
	seat.tooltip_text = header.seat
	pane_id.text = header.pane_id
	pane_id.tooltip_text = header.pane_id_tip
	pane_label.text = header.label
	pane_label.tooltip_text = header.label
	pane_label.visible = header.label_shown
	cwd_label.text = header.cwd
	cwd_label.tooltip_text = header.cwd_tip
	foreground.visible = header.foreground_shown
	foreground.text = header.foreground
	foreground.tooltip_text = header.foreground_tip
	session_label.visible = header.session_shown
	if header.session_shown:
		session_label.text = header.session
		session_label.tooltip_text = header.session_tip
	title.text = header.title
	title.tooltip_text = header.title
	_has_note = header.has_note
	footnote.visible = _has_note
	footnote.text = header.note
	_show_portrait(art, header)


## The pill the state caption stands in (HudTheme's StatePill*): a state's
## own colour for working, blocked, done (UNREAD) and idle, with ink words;
## `slate` with paper words for a quiet one (a shell, a start, a dropped
## machine, a state the office has no colour for).
static func pill_of(state: StringName, quiet: bool) -> StringName:
	if quiet:
		return &"StatePillQuiet"
	match state:
		ArtContract.STATE_WORKING:
			return &"StatePillWorking"
		ArtContract.STATE_BLOCKED:
			return &"StatePillBlocked"
		ArtContract.STATE_DONE:
			return &"StatePillDone"
		ArtContract.STATE_IDLE:
			return &"StatePillIdle"
	return &"StatePillQuiet"


## What `art` calls this state. A state the pack does not draw has no words
## of its own, so its own name stands in rather than an empty caption.
static func caption_of(art: ArtPack, state: StringName) -> String:
	var drawn := art.state(state) if art != null else null
	return drawn.label if drawn != null else str(state).to_upper()


## The portrait `header` names: the same person as the one at the seat (the
## pane's key picks their looks and the portrait's extras), still, on the
## window's warm ground, under a frame in the state's colour; the window greyed
## on a dropped machine, under the stale frame. No person (the empty card, a
## shell): none and no badge.
func _show_portrait(art: ArtPack, header: CardPicture.Header) -> void:
	var area: Control = %PortraitArea
	var badge: StatusBadge = %Badge
	var person := header != null and header.person
	area.visible = person
	badge.visible = person
	if not person:
		return
	var holder: Node2D = %PortraitHolder
	var window: Control = %PortraitWindow
	var frame: Control = %PortraitFrame
	var look := JSON.stringify([header.person_provider, art.base_path, header.key])
	if look != _portrait_look:
		_portrait_look = look
		# A new provider, pane or pack is new textures on the same portrait.
		_portrait = OfficeDraw.seat_portrait(holder, _portrait, art, header.person_provider, header.key)
	frame.theme_type_variation = FRAMES.get(header.frame, &"PortraitFrameIdle")
	var tint := art.stale_tint if header.dimmed else Color.WHITE
	window.modulate = tint
	frame.modulate = tint
	badge.show_badge(art, header.badge)


## The details under the action take whatever height the fixed parts above
## leave. A row that does not fit whole is not drawn at all: a line sliced by
## the panel's edge reads as a glitch. Only its drawing goes; its layout and
## whether it has anything to say (`visible`) stay the data's.
func _fit_more() -> void:
	var more: Control = %More
	var more_list: Container = %MoreList
	for child in more_list.get_children():
		if child is Control:
			var row: Control = child
			var fits := row.position.y + row.size.y <= more.size.y
			row.self_modulate.a = 1.0 if fits else 0.0


## Whole lines only, and never more than the panel is meant to show.
func _fit_title() -> void:
	var title: Label = %TerminalTitle
	var holder: Control = %TitleHolder
	var line := title.get_theme_font("font").get_height(title.get_theme_font_size("font_size"))
	title.max_lines_visible = mini(TITLE_LINES, int(holder.size.y / line))


## The badge a state wears in `art`, falling back to the unknown mark for a
## state the pack does not draw.
static func badge_of(art: ArtPack, state: StringName) -> StringName:
	var drawn := art.state(state) if art != null else null
	return drawn.badge if drawn != null else ArtContract.STATE_UNKNOWN
