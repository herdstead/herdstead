class_name CardDetails
extends BoxContainer
## The agent card's header and details (OfficePaneInspector): the portrait and
## its badge, provider, status caption, seat, machine and the footnote, and the
## PANE list (id, label, directories, session, terminal title). It only writes
## the text, visibility and tooltips of the nodes the scene holds under it, and
## the portrait's one person; it never lays anything out and never talks to the
## fleet. The preview, the actions and the launch block beside them are the
## card's.
##
## The script sits on the card scene's own `%Detail` node, so its children stay
## the card's unique names (`%Provider`, `%MoreList`, …).

## The terminal title never takes more than this many lines, however tall the
## panel is; past that the panel would read as a log, not as a caption.
const TITLE_LINES := 5

## What the portrait is dressed as now: provider and pack, so a theme switch
## re-dresses it and nothing else does.
var _portrait_look := ""
var _actor: PixelPerson


func _ready() -> void:
	var title_holder: Control = %TitleHolder
	title_holder.resized.connect(_fit_title)
	var more: Control = %More
	var more_list: Container = %MoreList
	more.resized.connect(_fit_more)
	more_list.sort_children.connect(_fit_more)


## A pack swap is a new people family and animation library: the portrait is
## dressed again on its next show().
func forget_look() -> void:
	_portrait_look = ""


## The portrait's person while there is one; null before the first.
func portrait() -> PixelPerson:
	return _actor


## No pane: no person and no badge.
func clear() -> void:
	_show_portrait(null, "", &"", false)


## The provider, the caption and the seat as the header shows them, for the
## card's compact line, which says the same three things in the same words.
func summary() -> String:
	var provider: Label = %Provider
	var caption: Label = %Caption
	var seat: Label = %Seat
	return "%s · %s · %s" % [provider.text, caption.text, seat.text]


## The header and details of `pane` (never null) on `machine` (empty with one
## machine), greyed and frozen when `dimmed`, in `art`'s words and people.
func show_pane(pane: PaneModel, machine: String, dimmed: bool, art: ArtPack) -> void:
	var state := StringName(pane.state)
	var starting := pane.launching()
	var provider: Label = %Provider
	var caption: Label = %Caption
	var machine_label: Label = %Machine
	var seat: Label = %Seat
	var pane_id: Label = %PaneId
	var cwd_label: Label = %Cwd
	var title: Label = %TerminalTitle
	var footnote: Label = %Footnote
	var pane_label: Label = %PaneLabel
	var foreground: Label = %ForegroundCwd
	var session_label: Label = %Session
	# A start herdr took but whose kind it has not detected yet: the name it gave.
	var named := starting and pane.provider.is_empty() and not pane.agent_name.is_empty()
	provider.text = (
		pane.agent_name.to_upper() if named else "SHELL" if pane.provider.is_empty() else pane.provider.to_upper()
	)
	# A shell has no agent, so no person and no agent state: herdr's idle for it is the terminal's.
	var shell := pane.provider.is_empty() and not starting
	caption.text = (
		"STALE / OFFLINE" if dimmed else "STARTING" if starting else "no agent" if shell else caption_of(art, state)
	)
	var pill: PanelContainer = %CaptionPill
	pill.theme_type_variation = pill_of(state, dimmed or starting or shell)
	caption.theme_type_variation = &"LabelPaper" if pill.theme_type_variation == &"StatePillQuiet" else &"LabelInk"
	caption.tooltip_text = "herdr reports no agent in this pane: a shell." if shell else ""
	if not pane.provider.is_empty():
		caption.tooltip_text = (
			"Launch status not reported"
			if not pane.starting_known
			else "Launching" if pane.starting else "Not launching"
		)
	machine_label.visible = not machine.is_empty()
	machine_label.text = "@ " + machine
	machine_label.tooltip_text = machine_label.text
	# A pane whose workspace or tab the snapshot does not carry still names its seat.
	var space := pane.workspace_label if not pane.workspace_label.is_empty() else "?"
	var tab := pane.tab_label if not pane.tab_label.is_empty() else "?"
	seat.text = "%s / %s" % [space, tab]
	seat.tooltip_text = seat.text
	pane_id.text = pane.pane_id
	pane_id.tooltip_text = "Pane: " + pane.pane_id + "\nTerminal: " + pane.terminal_id
	pane_label.text = pane.label
	pane_label.tooltip_text = pane.label
	pane_label.visible = not pane.label.is_empty()
	var cwd := pane.cwd_name()
	cwd_label.text = cwd if not cwd.is_empty() else "-"
	cwd_label.tooltip_text = "Working directory: " + pane.cwd
	foreground.visible = not pane.foreground_cwd.is_empty() and pane.foreground_cwd != pane.cwd
	foreground.text = "Foreground: " + pane.foreground_cwd.trim_suffix("/").get_file()
	foreground.tooltip_text = "Foreground directory: " + pane.foreground_cwd
	session_label.visible = pane.session != null
	if pane.session != null:
		session_label.text = "Session: " + pane.session.value
		session_label.tooltip_text = (
			"%s / %s / %s\n%s" % [pane.session.provider, pane.session.source, pane.session.kind, pane.session.value]
		)
	title.text = pane.terminal_title
	title.tooltip_text = pane.terminal_title
	# The note under the caption explains the state it names: a dropped
	# machine's, or UNREAD's. Other states need none.
	footnote.visible = dimmed or (state == ArtContract.STATE_DONE and not starting)
	footnote.text = ("Connection lost.\nNot an idle signal." if dimmed else "UNREAD = not yet seen\nNot task success.")
	_show_portrait(art, pane.provider, &"" if shell else state, starting, dimmed, pane.key)


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


## `key` is the pane's (HerdrFleet.pane_key): the portrait is the same person as
## the one at the seat, whose face and hair vary by it. No `state` (the empty
## card, a shell): no person and no badge.
func _show_portrait(
	art: ArtPack, provider: String, state: StringName, starting: bool, dimmed := false, key := ""
) -> void:
	var area: Control = %PortraitArea
	var badge: StatusBadge = %Badge
	area.visible = not state.is_empty()
	badge.visible = area.visible
	if state.is_empty():
		return
	var look := JSON.stringify([provider, art.base_path, key])
	if look != _portrait_look:
		_portrait_look = look
		if _actor == null:
			_actor = OfficeDraw.PERSON_SCENE.instantiate()
			%PortraitHolder.add_child(_actor)
			# Not part of any floor: the portrait's feet never collide.
			var feet: CollisionShape2D = _actor.get_node("Feet")
			feet.disabled = true
		# PixelPerson.configure() re-dresses the layers it has; a new provider or
		# a new pack is new textures on the same nodes, never a new person.
		_actor.vary_by(key)
		_actor.configure(art.people, provider, AvatarLook.facing(AvatarLook.STAND, AvatarLook.FRONT))
	var animation := art.animation_for_state(state, starting)
	if _actor.animation != animation:
		_actor.play_state(animation)
	var holder: Node2D = %PortraitHolder
	holder.modulate = art.stale_tint if dimmed else Color.WHITE
	if dimmed:
		_actor.pause()
	else:
		_actor.play()
	var shown := ArtContract.UI_OFFLINE if dimmed else ArtContract.UI_STARTING if starting else _badge_id(art, state)
	badge.show_badge(art, shown)


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


## The badge a state wears here, falling back to the unknown mark for a state
## the pack does not draw.
static func _badge_id(art: ArtPack, state: StringName) -> StringName:
	var drawn := art.state(state)
	return drawn.badge if drawn != null else ArtContract.STATE_UNKNOWN
