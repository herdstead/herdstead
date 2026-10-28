class_name PortraitCard
extends Button
## One agent in the top bar's portrait strip (scenes/ui/portrait_card.tscn):
## the seat's person, still, with the pane's name over its place (a
## tag in its worktree group's carpet family and its space) and, for a blocked
## agent, how long it has waited. Its frame wears the state's colour; the
## selected one a ring just inside it, and one a hovered HUD line points at a
## ring inside that (set_pointed()): the three nest and all show (paper on a
## card, ink and slate on a tile's cream window). Face-only, the words go and the
## card is as wide as the face.
##
## Two forms of the same node, by the bar's height (set_tall()). On a tall bar
## it is B2's tile (`tile_size`): the seat's person as a portrait (PixelPortrait,
## OfficeDraw.seat_portrait(), whole in a 42×42 window on the cream ground;
## cropped to its middle on a face-only tile), the state's frame over the
## portrait's edge (`%FaceFrame`), the rings over that, the state's small mark
## in the window's top-left corner (`%Badge`, the pack's `badge_<badge>_small`:
## a plain Sprite2D, not a StatusBadge, so the attention clock never bobs it;
## and the scene names no StatusBadge script, which would load in a cycle under
## the bar's preload), and the name and the place under it on the bar's
## ground. On a short bar it is the horizontal card (`card_size`): the small
## person at the left, the words beside it, the frame round the whole card,
## and no mark. The rings (`%Selected`, `%Pointed`) move to whichever node
## wears the frame; every node is kept, and only the form's own face is shown
## and dressed.
##
## The place is a button of its own (`%PlaceButton`): a click there pans to the
## zone (place_picked) and selects nothing; its
## tooltip is the zone's sign. An unseated pane's place is only words, and a
## click anywhere else on the card picks the pane.
##
## Its nodes are permanent: a card shown for another pane is the same node
## with new text (the bar pools them). A press is the bar's to say
## (OfficeBar.portrait_picked, OfficeBar.zone_picked); the card takes no focus,
## so no key reaches it. The card's tooltip is written only when the pointer
## asks, as a list row's is.

## The place (`%PlaceButton`) was pressed: pan to zone `zone_key`.
signal place_picked(zone_key: String)
## The pointer came onto the place (`on`) or left it. The place takes the
## mouse, so the card itself does not hear the pointer there; the bar points
## at the card's desk all the same.
signal place_hovered(on: bool)

## The frame each group wears (HudTheme._portraits()).
const LOOKS: Dictionary[PortraitBarModel.Group, StringName] = {
	PortraitBarModel.Group.BLOCKED: &"PortraitCardBlocked",
	PortraitBarModel.Group.DONE: &"PortraitCardDone",
	PortraitBarModel.Group.WORKING: &"PortraitCardWorking",
	PortraitBarModel.Group.IDLE: &"PortraitCardIdle",
}

## The frameless tile; its window's frame wears the state (FRAME_LOOKS).
const TILE_LOOK := &"PortraitTile"
## The portrait's frame on a tile (`%FaceFrame`), by group; `Lit` added under
## the pointer.
const FRAME_LOOKS: Dictionary[PortraitBarModel.Group, String] = {
	PortraitBarModel.Group.BLOCKED: "PortraitFrameBlocked",
	PortraitBarModel.Group.DONE: "PortraitFrameDone",
	PortraitBarModel.Group.WORKING: "PortraitFrameWorking",
	PortraitBarModel.Group.IDLE: "PortraitFrameIdle",
}
## A tile's window: the cream ground the portrait stands on.
const WINDOW_LOOK := &"PortraitWindow"
## The face window on a card: the card's own frame shows round it.
const FACE_BARE := &"PortraitFaceBare"
## The selection's and the pointed ring's looks on a card (`paper` on its dark
## ground) and on a tile (`ink` and `slate` on the cream window).
const SELECTED_LOOKS: Dictionary[bool, StringName] = {false: &"PortraitSelected", true: &"PortraitSelectedTile"}
const POINTED_LOOKS: Dictionary[bool, StringName] = {false: &"PortraitPointed", true: &"PortraitPointedTile"}
## The face and the words side by side (a card), or one over the other (a tile).
const BODY_LOOKS: Dictionary[bool, StringName] = {false: &"PortraitBody", true: &"PortraitBodyTall"}

## The card and the tile, whole. Set in the scene.
@export var card_size := Vector2.ZERO
@export var tile_size := Vector2.ZERO
## The width of the face-only form, as a card and as a tile. Set in the scene.
@export var face_width := 0.0
@export var tile_face_width := 0.0
## The face window's least size, as a card and as a tile, and as a face-only
## tile (the portrait cropped to its middle). Set in the scene.
@export var card_face := Vector2.ZERO
@export var tile_face := Vector2.ZERO
@export var tile_face_alone := Vector2.ZERO
## How far in from the card's edges the face and the words stand (left, top,
## right, bottom), as a card and as a tile. Set in the scene.
@export var card_body := Vector4.ZERO
@export var tile_body := Vector4.ZERO

## The pane this card shows (HerdrFleet.pane_key); empty while pooled.
var key := ""

var _card: PortraitBarModel.Card
var _art: ArtPack
var _actor: PixelPerson
var _portrait: PixelPortrait
## What the person and the portrait are dressed as now: provider, pack and
## pane; each holder's own, so the hidden one is not dressed again until it
## shows.
var _look := ""
var _portrait_look := ""
var _face_only := false
## The tile form (set_tall()), or the card.
var _tall := false
## The pointer is on the card: a tile's window frame thickens, as a card's edge does.
var _lit := false
## The small mark the tile wears now; empty for none.
var _dot := &""
## A hovered HUD line names this pane (set_pointed()).
var _pointed := false


func _ready() -> void:
	var button: Button = %PlaceButton
	button.pressed.connect(func() -> void: place_picked.emit(_card.zone_key))
	button.mouse_entered.connect(func() -> void: place_hovered.emit(true))
	button.mouse_exited.connect(func() -> void: place_hovered.emit(false))
	mouse_entered.connect(_light.bind(true))
	mouse_exited.connect(_light.bind(false))


## Show `card` dressed from `art`; `selected` rings it.
func show_card(card: PortraitBarModel.Card, art: ArtPack, selected: bool) -> void:
	if art != _art:
		_dot = &""
	_card = card
	_art = art
	key = card.key
	var name_label: Label = %Name
	var place: Label = %Place
	var tag: Panel = %Tag
	var ring: Panel = %Selected
	var button: Button = %PlaceButton
	name_label.text = card.name
	place.text = card.place
	# A seated pane's place is a button to its zone; an unseated one's is only
	# words, and its click falls through to the card, which picks the pane.
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE if card.zone == null else Control.MOUSE_FILTER_STOP
	button.tooltip_text = place_tip_of(card)
	tag.visible = not card.group_key.is_empty()
	if tag.visible:
		tag.theme_type_variation = StringName("CarpetTag%d" % OfficeZoneSign.accent_of(card.group_key))
	ring.visible = selected
	_restyle()
	_show_face()
	_show_wait_label()


## The seat's person, still: a strip of bobbing heads would compete with the
## seats. On a tile the portrait (a still by itself; the frame and the mark say
## the state), on a card the small person paused in the state's pose. Both are
## made, and dressed, with the card's first pane, so a flip of the form makes
## no node; after that only the shown face follows the pane, its provider and
## the pack, and the hidden one catches up when it shows again.
func _show_face() -> void:
	if _card == null:
		return
	var look := JSON.stringify([_card.provider, _art.base_path, _card.key])
	if _portrait == null or (_tall and look != _portrait_look):
		_portrait_look = look
		var frame: Node2D = %PortraitHolder
		_portrait = OfficeDraw.seat_portrait(frame, _portrait, _art, _card.provider, _card.key)
	if _actor == null or (not _tall and look != _look):
		_look = look
		var holder: Node2D = %FaceHolder
		_actor = OfficeDraw.seat_face(holder, _actor, _art, _card.provider, _card.key)
		_actor.animation = &""
	if _tall:
		return
	var animation := _art.animation_for_state(StringName(_card.state), _card.starting)
	if _actor.animation != animation:
		_actor.play_state(animation)
	_actor.pause()


## How long a blocked agent has waited (OfficeAttention.wait_text()); empty
## for none. Only a blocked card says it.
func show_wait(said: String) -> void:
	var wait: Label = %Wait
	wait.text = said
	_show_wait_label()


func _show_wait_label() -> void:
	var wait: Label = %Wait
	var blocked := _card != null and _card.group == PortraitBarModel.Group.BLOCKED
	wait.visible = blocked and not wait.text.is_empty() and not _face_only


## The face alone (`on`), or the whole card.
func set_face_only(on: bool) -> void:
	_face_only = on
	var words: Control = %Text
	words.visible = not on
	_size_window()
	_size()
	_show_wait_label()


func face_only() -> bool:
	return _face_only


## The tile (`on`, a tall bar) or the horizontal card (a short one). Only the
## nodes' properties change: the box turns, the sizes are the scene's, the
## rings move to the node that wears the frame, the portrait shows on a tile
## and the small person on a card, and the mark shows on a tile alone.
## Nothing is made or freed.
func set_tall(on: bool) -> void:
	if on == _tall:
		return
	_tall = on
	var body: BoxContainer = %Body
	var name_label: Label = %Name
	var small: Node2D = %FaceHolder
	var still: Node2D = %PortraitHolder
	var inset := tile_body if on else card_body
	body.vertical = on
	body.theme_type_variation = BODY_LOOKS[on]
	body.offset_left = inset.x
	body.offset_top = inset.y
	body.offset_right = -inset.z
	body.offset_bottom = -inset.w
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if on else HORIZONTAL_ALIGNMENT_LEFT
	small.visible = not on
	still.visible = on
	_size_window()
	_wear_rings()
	_size()
	_restyle()
	_show_face()


func is_tall() -> bool:
	return _tall


## The width this card needs as a face alone or as a whole card, in its form
## now, from the scene's sizes (what OfficeBar fits the strip by).
func needed_width(face_alone: bool) -> float:
	if _tall:
		return tile_face_width if face_alone else tile_size.x
	return face_width if face_alone else card_size.x


## The face window's least size and how it sits: on a whole tile the 42×42
## window centred over the words, on a face-only tile filling it (the
## portrait cropped to its middle), on a card the scene's card face.
func _size_window() -> void:
	var face_box: Control = %FaceBox
	var alone := _tall and _face_only
	face_box.custom_minimum_size = (tile_face_alone if alone else tile_face) if _tall else card_face
	var centred := _tall and not _face_only
	face_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centred else Control.SIZE_FILL


func _size() -> void:
	var height := tile_size.y if _tall else card_size.y
	var wanted := Vector2(needed_width(_face_only), height)
	if custom_minimum_size != wanted:
		custom_minimum_size = wanted


## The rings go where the frame is: round the whole card, or inside a tile's
## face window. On a card `%Pointed` stays under the face (the head's top, at
## its row, stays whole) and `%Selected` over everything. On a tile every ring
## lies over the portrait, which fills the window (S3 PORTRAIT D-RINGS): the
## portrait, its frame, `%Pointed`, `%Selected`, then the mark, so the frame's
## edge, the selection and the pointing nest and all read over hair and hats;
## there the rings wear the tile's colours, which read on the cream window.
func _wear_rings() -> void:
	var under: Control = %Pointed
	var over: Control = %Selected
	var frame: Control = %FaceFrame
	var holder: Control = %FaceBox if _tall else self
	for ring: Control in [under, over]:
		if ring.get_parent() != holder:
			# Moved, never made again: the owner is let go for the move and
			# taken back, so `%Selected` / `%Pointed` still find it.
			ring.owner = null
			ring.get_parent().remove_child(ring)
			holder.add_child(ring)
			ring.owner = self
	under.theme_type_variation = POINTED_LOOKS[_tall]
	over.theme_type_variation = SELECTED_LOOKS[_tall]
	if _tall:
		holder.move_child(under, frame.get_index() + 1)
		holder.move_child(over, under.get_index() + 1)
	else:
		holder.move_child(under, 0)
		holder.move_child(over, holder.get_child_count() - 1)


## The looks the form and the group give: a card's frame on the card, or a
## tile's cream window and the frame over its portrait (thicker under the
## pointer), and the tile's mark.
func _restyle() -> void:
	var face_box: Control = %FaceBox
	var frame: Control = %FaceFrame
	var mark: Sprite2D = %Badge
	if _card == null:
		return
	var group := _card.group
	theme_type_variation = TILE_LOOK if _tall else LOOKS[group]
	face_box.theme_type_variation = WINDOW_LOOK if _tall else FACE_BARE
	frame.visible = _tall
	if _tall:
		frame.theme_type_variation = StringName(FRAME_LOOKS[group] + ("Lit" if _lit else ""))
	var dot := dot_of(_art, group) if _tall else &""
	if dot != _dot:
		_dot = dot
		if dot.is_empty():
			mark.visible = false
		else:
			var image := _art.ui_sprite(dot)
			_art.dress(mark, _art.sprite_texture(image), image.pivot)
			mark.visible = true


func _light(on: bool) -> void:
	_lit = on
	_restyle()


## The small mark a tile of `group` wears: the pack's `badge_<badge>_small`
## for the badge its state wears (ArtContract.tile_dot(); done wears unread's),
## or none when the pack has no such image.
static func dot_of(art: ArtPack, group: PortraitBarModel.Group) -> StringName:
	if art == null:
		return &""
	var dot := ArtContract.tile_dot(CardDetails.badge_of(art, StringName(PortraitBarModel.WORDS[group])))
	return dot if art.ui_sprite(dot) != null else &""


## The tile's mark; hidden on a card.
func badge() -> Sprite2D:
	return %Badge


## A hovered HUD line names this card's pane (`on`): a 1-unit ring 2 units in,
## inside the selection's (PortraitPointed, PortraitPointedTile), until it does not. On a
## card it lies under the face, so the head's top, at that same row, stays
## whole; on a tile over the portrait, under the selection's ring
## (_wear_rings()). Written only when it changes.
func set_pointed(on: bool) -> void:
	if on == _pointed:
		return
	_pointed = on
	var ring: Panel = %Pointed
	ring.visible = on


## Whether the card is outlined as pointed at (set_pointed()).
func pointed() -> bool:
	return _pointed


## The small person a card shows (hidden on a tile); null before the first
## show_card().
func person() -> PixelPerson:
	return _actor


## The portrait a tile shows (hidden on a card); null before the first
## show_card().
func portrait() -> PixelPortrait:
	return _portrait


func shown_card() -> PortraitBarModel.Card:
	return _card


func _get_tooltip(_at: Vector2) -> String:
	return tooltip_of(_card, _art, (%Wait as Label).text)


## The place's tooltip: the words on its zone's sign (`3 INFRA`, a
## mezzanine's `3A CHECKOUT`) over what the sign's own tooltip says
## (ZoneRef.sign_text(): repository, checkout, whose worktree); empty for an
## unseated pane, whose place is not a button. (Not through
## OfficeQuestionTips: the bar preloads this card, and that reader's
## dependencies loading under it left the zone sign's scene empty.)
static func place_tip_of(card: PortraitBarModel.Card) -> String:
	if card == null or card.zone == null:
		return ""
	return OfficeZoneSign.words(card.zone.zone_model) + "\n" + card.zone.sign_text()


## The card's tooltip: the whole name; `PROVIDER · <the pack's word for the
## state> · <wait>` (a blocked card's wait only); `space / tab`; and
## `@ machine` among several machines.
static func tooltip_of(card: PortraitBarModel.Card, art: ArtPack, wait: String) -> String:
	if card == null:
		return ""
	var lines := PackedStringArray([card.name])
	var about := PackedStringArray([card.provider.to_upper(), CardDetails.caption_of(art, StringName(card.state))])
	if card.group == PortraitBarModel.Group.BLOCKED and not wait.is_empty():
		about.append(wait)
	lines.append(" · ".join(about))
	lines.append(card.place if card.tab.is_empty() else "%s / %s" % [card.place, card.tab])
	if not card.machine_label.is_empty():
		lines.append("@ " + card.machine_label)
	return "\n".join(lines)
