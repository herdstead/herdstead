class_name OfficeMachineHeading
extends VBoxContainer
## One machine's heading in the SPACES rail: the pack's icon for how its machine
## is answering, and its label, on a button (`%Press`). A click on it shows that
## machine's map (the office decides; a machine that never connected opens as
## an empty map), and the heading of the machine whose map is shown is the
## highlighted one (SpaceHeadingCurrent). Kept and updated in place like the
## rows below it, and re-dressed rather than rebuilt when the theme changes.
##
## A container, not the button itself: every heading but the first keeps a gap
## above it (`%Gap`), which the button must not grow into.

## The heading was pressed; `key` is its machine's key.
signal picked(key: String)

## Machine state -> the pack's UI image for it. These are display overlays,
## not herdr states: a machine is answering, still opening its forward, or gone.
const MARKS: Dictionary[MachineLiveness.State, StringName] = {
	MachineLiveness.State.LIVE: ArtContract.UI_CONNECTED,
	MachineLiveness.State.CONNECTING: ArtContract.UI_STARTING,
	MachineLiveness.State.OFFLINE: ArtContract.UI_OFFLINE,
}

## The machine this heading stands for; empty until show_machine().
var key := ""

var _art: ArtPack
## The state drawn now, so a theme switch can redraw the same mark.
var _state := MachineLiveness.State.CONNECTING


func _ready() -> void:
	button().pressed.connect(func() -> void: picked.emit(key))


## Take the pack's icon art. Called again on a theme switch, which re-dresses
## the one sprite and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	_draw_mark()


## Machine `machine`, named `label`, answering as `state` says. `gap` adds the
## breathing room every heading but the first gets; `current` is its map being
## the one shown.
func show_machine(machine: String, label: String, state: MachineLiveness.State, gap: bool, current: bool) -> void:
	key = machine
	_state = state
	var machine_label: Label = %MachineLabel
	var gap_row: Control = %Gap
	var press := button()
	machine_label.text = label.to_upper()
	# The label clips, most of all in the narrow rail: the tooltip names the machine whole.
	if press.tooltip_text != label:
		press.tooltip_text = label
	gap_row.visible = gap
	var look := &"SpaceHeadingCurrent" if current else &"SpaceHeading"
	if press.theme_type_variation != look:
		press.theme_type_variation = look
	machine_label.theme_type_variation = &"LabelPaper" if current else &"LabelWoodDark"
	# The name dims with the machine's zones; the mark keeps saying why.
	var live := state == MachineLiveness.State.LIVE
	machine_label.modulate = Color.WHITE if live or _art == null else _art.stale_tint
	_draw_mark()


## The button a click lands on: the heading without its gap.
func button() -> Button:
	return %Press


## Whether this heading is the highlighted one: its machine's map is shown.
func is_current() -> bool:
	return button().theme_type_variation == &"SpaceHeadingCurrent"


## The sprite showing how this machine is answering.
func mark_icon() -> Sprite2D:
	var mark: Control = %Mark
	return mark.get_node("Icon")


func _draw_mark() -> void:
	if _art == null:
		return
	var id: StringName = MARKS.get(_state, ArtContract.UI_STARTING)
	var image := _art.ui_sprite(id)
	var icon := mark_icon()
	_art.dress(icon, _art.sprite_texture(image), image.pivot)
	# Every UI image declares its own pivot and these three do not agree on one,
	# so the sprite stands at its own pivot inside the mark's square: whatever
	# the pack says, the picture itself lands in the same place.
	icon.position = image.pivot
