class_name OfficeSignpost
extends Button
## One signpost over the world's right edge (OfficeSignposts): `↑ 3F infra` and
## a blocked badge with its count, for another floor with agents blocked on it.
## A click shows that floor. The last post, when more floors than posts are
## waiting, is a disabled `+N floors` note whose tooltip names them.
##
## Kept for the HUD's whole life and updated in place: a refresh only writes
## text, visibility and the badge's pulse.

## This post was pressed; `key` is the floor key the office gave it.
signal floor_picked(key: String)

var _key := ""


func _ready() -> void:
	pressed.connect(func() -> void: floor_picked.emit(_key))


## Take the pack's blocked badge. A theme switch calls this again and rebuilds nothing.
func dress(art: ArtPack) -> void:
	_badge().show_badge(art, art.state(ArtContract.STATE_BLOCKED).badge)


## Point at `post`'s floor.
func show_post(post: SignpostModel) -> void:
	_key = post.key
	var arrow: Label = %Arrow
	var floor_label: Label = %Floor
	var count: Label = %Count
	var slot: Control = %IconSlot
	arrow.text = "↑" if post.up else "↓"
	arrow.visible = true
	# One clipped line, the machine last: a long name loses the machine's
	# name before the floor's. The tooltip always has both.
	floor_label.text = _place(post)
	count.text = str(post.blocked)
	count.visible = true
	slot.visible = true
	# A floor, not a seat: the pulse asks the machine, never a pane.
	_badge().pulse_for(post.machine_key, "", ArtContract.STATE_BLOCKED)
	tooltip_text = "%s · %d blocked · click to show" % [_place(post), post.blocked]
	disabled = false


## The last post when more floors are waiting than there are posts: a note
## naming `posts`, not a way to any one of them.
func show_more(posts: Array[SignpostModel]) -> void:
	_key = ""
	var arrow: Label = %Arrow
	var floor_label: Label = %Floor
	var count: Label = %Count
	var slot: Control = %IconSlot
	arrow.visible = false
	floor_label.text = "+%d floors" % posts.size()
	count.visible = false
	slot.visible = false
	_badge().stop_pulsing()
	var lines := PackedStringArray()
	for post in posts:
		lines.append("%s %s · %d blocked" % ["↑" if post.up else "↓", _place(post), post.blocked])
	tooltip_text = "\n".join(lines)
	disabled = true


## A hidden post stops pulsing, so nothing steps a badge nobody sees.
func hide_post() -> void:
	_key = ""
	_badge().stop_pulsing()
	visible = false


## The floor key this post shows on a click; empty for the `+N floors` note.
func key() -> String:
	return _key


## The blocked badge, for the tests that follow the pulse.
func badge() -> StatusBadge:
	return _badge()


## `3F infra`, and `@ bee` after it for a floor in another building.
func _place(post: SignpostModel) -> String:
	return post.floor_text if post.machine.is_empty() else post.floor_text + " @ " + post.machine


func _badge() -> StatusBadge:
	var slot: Control = %IconSlot
	return slot.get_node("Sprite")
