class_name OfficeBuildingHeading
extends VBoxContainer
## One building's heading in the FLOORS minimap: the pack's icon for how its machine
## is answering, and its label. Kept and updated in place like the rows below
## it, and re-dressed rather than rebuilt when the theme changes.

## Building state -> the pack's UI image for it. These are display overlays,
## not herdr states: a machine is answering, still opening its forward, or gone.
const MARKS: Dictionary[MachineLiveness.State, StringName] = {
	MachineLiveness.State.LIVE: ArtContract.UI_CONNECTED,
	MachineLiveness.State.CONNECTING: ArtContract.UI_STARTING,
	MachineLiveness.State.OFFLINE: ArtContract.UI_OFFLINE,
}

var _art: ArtPack
## The state drawn now, so a theme switch can redraw the same mark.
var _state := MachineLiveness.State.CONNECTING


## Take the pack's icon art. Called again on a theme switch, which re-dresses
## the one sprite and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_art = art
	_draw_mark()


## `gap` adds the breathing room every heading but the first gets.
func show_building(label: String, state: MachineLiveness.State, gap: bool) -> void:
	_state = state
	var building_label: Label = %BuildingLabel
	var gap_row: Control = %Gap
	building_label.text = label.to_upper()
	# The label clips, most of all in the FLOORS rail: its tooltip names the machine whole.
	if building_label.tooltip_text != label:
		building_label.tooltip_text = label
	gap_row.visible = gap
	# The name dims with the building's floors; the mark keeps saying why.
	var live := state == MachineLiveness.State.LIVE
	building_label.modulate = Color.WHITE if live or _art == null else _art.stale_tint
	_draw_mark()


## The sprite showing how this building's machine is answering.
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
