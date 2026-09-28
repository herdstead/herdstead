class_name AvatarLook
extends Resource
## One worker's avatar: what they wear in every slot, which way they face,
## whether they are standing or at a desk, and which agent they are.
##
## The slots are the customization's parts (docs/VISUAL_LANGUAGE.md, "Looks"):
## skin, hair style, hair colour, top, legs, headwear and its colour, glasses.
## Each is the id of one option the pixel people family draws (a swatch or a
## shape, or `none` where the slot allows it); the family's manifest says which.
##
## An empty field means "not chosen here". That is what lets a caller ask for
## one change (sit down, turn around, a different top) without restating the
## whole look: PixelPeople.look_for() fills every empty slot from the pack's
## default, the provider's default, the user's saved choice and the pane's
## variation, in that order.

const STAND := &"stand"
const DESK := &"desk"
const FRONT := &"front"
const BACK := &"back"
const CONTEXTS: Array[StringName] = [STAND, DESK]
const ORIENTATIONS: Array[StringName] = [FRONT, BACK]

const SKIN := &"skin"
const HAIR_STYLE := &"hair_style"
const HAIR_COLOUR := &"hair_colour"
const TOP := &"top"
const LEGS := &"legs"
const HEADWEAR := &"headwear"
const HEADWEAR_COLOUR := &"headwear_colour"
const GLASSES := &"glasses"
## Every slot, in the order the family's manifest lists them.
const SLOTS: Array[StringName] = [SKIN, HAIR_STYLE, HAIR_COLOUR, TOP, LEGS, HEADWEAR, HEADWEAR_COLOUR, GLASSES]
## The option of a shape slot that draws nothing.
const NONE := &"none"

var skin := &""
var hair_style := &""
var hair_colour := &""
var top := &""
var legs := &""
var headwear := &""
var headwear_colour := &""
var glasses := &""
var context := &""
var orientation := &""
## The agent this look belongs to; not always the pane's provider, because an
## unknown provider is the generic one. Nobody wears it as a logo: a pixel
## person has no room for one, so the name plate says who sits there.
var badge := &""
## The slots a resolved look took from the user's saved choice (the rest came
## from defaults or the pane's variation); empty on a look nobody resolved.
var pinned: Array[StringName] = []


## A look that asks only for a context and an orientation, which is what seating
## a worker or turning a portrait around comes down to.
static func facing(wanted_context: StringName, wanted_orientation: StringName) -> AvatarLook:
	var result := AvatarLook.new()
	result.context = wanted_context
	result.orientation = wanted_orientation
	return result


## A look that asks only for these slots, leaving the rest and the pose to
## whoever draws it. An unknown slot id is refused (push_error) and skipped.
static func with_slots(chosen: Dictionary[StringName, StringName]) -> AvatarLook:
	var result := AvatarLook.new()
	for id in chosen:
		result.set_slot(id, chosen[id])
	return result


## The option this look names for slot `id`; empty when it names none, or when
## `id` is not a slot.
func slot(id: StringName) -> StringName:
	if not SLOTS.has(id):
		return &""
	var value: StringName = get(id)
	return value


## Name `value` for slot `id`; false (and nothing changes) when `id` is not a slot.
func set_slot(id: StringName, value: StringName) -> bool:
	if not SLOTS.has(id):
		push_error("AvatarLook: no slot %s" % id)
		return false
	set(id, value)
	return true


func copy() -> AvatarLook:
	var result := AvatarLook.new()
	for id in SLOTS:
		result.set_slot(id, slot(id))
	result.context = context
	result.orientation = orientation
	result.badge = badge
	result.pinned = pinned.duplicate()
	return result


## Take every field `wanted` names, leaving the rest alone.
func override_with(wanted: AvatarLook) -> void:
	if wanted == null:
		return
	for id in SLOTS:
		if not wanted.slot(id).is_empty():
			set_slot(id, wanted.slot(id))
	if not wanted.context.is_empty():
		context = wanted.context
	if not wanted.orientation.is_empty():
		orientation = wanted.orientation
	if not wanted.badge.is_empty():
		badge = wanted.badge


## Only the slots: the clothes and looks of this person, without the pose.
func clothes() -> AvatarLook:
	var result := AvatarLook.new()
	for id in SLOTS:
		result.set_slot(id, slot(id))
	return result


## A stable identity for this look, so textures or materials composed for it
## can be cached.
func key() -> String:
	var parts := PackedStringArray()
	for id in SLOTS:
		parts.append(str(slot(id)))
	parts.append_array([str(context), str(orientation), str(badge)])
	return "/".join(parts)
