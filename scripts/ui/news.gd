class_name OfficeNews
extends PanelContainer
## The NEWS strip along the screen's bottom: the latest events of the fleet's
## StateLog (NewsItem, the office's), newest on the left. A click on one picks
## its pane, as a row of the agent list does; one whose pane is gone, and a
## machine's, cannot be clicked, and say why when hovered.
##
## Eight items stand in the scene; only their text, visibility and whether
## they can be clicked change, so the HUD's nodes are the same whatever the log
## says. Each is as wide as its words, never shrunk. They flow left to right,
## and one that does not fit whole goes to a second line the strip does not
## show: no entry is ever half there (a cut `2s+` would read `2s`). Only the
## newest, alone on its line, is cut at the strip's edge when it is wider than
## all of it. A new newest entry fades in once; nothing here moves on its own
## after that.

## A pickable entry was clicked: pick pane `pane_key`.
signal picked(pane_key: String)
## The mouse came onto an entry about pane `pane_key`, disabled ones too, or
## left it (`""`); an entry under a still mouse that now names another pane says so.
signal pointed(pane_key: String)

const ITEMS := 8
const FADE_SECONDS := 0.25

## The newest id shown, so only a new one fades in.
var _newest_id := -1
var _keys := PackedStringArray()
var _fade: Tween
## The item under the mouse, -1 for none.
var _hovered := -1


func _ready() -> void:
	_keys.resize(ITEMS)
	for index in ITEMS:
		item(index).pressed.connect(_on_pressed.bind(index))
		item(index).mouse_entered.connect(_on_entered.bind(index))
		item(index).mouse_exited.connect(_on_exited.bind(index))


## Take the pack's art; the strip has no image, and a theme switch rebuilds nothing.
func dress(_art: ArtPack) -> void:
	pass


## Show `items`, newest first, at most ITEMS of them; the rest of the items hide.
func show_news(items: Array[NewsItem]) -> void:
	var under := _keys[_hovered] if _hovered >= 0 else ""
	for index in ITEMS:
		var button := item(index)
		if index >= items.size():
			_keys[index] = ""
			if button.visible:
				button.visible = false
			continue
		var entry := items[index]
		_keys[index] = entry.pane_key
		if button.text != entry.text:
			button.text = entry.text
		button.disabled = not entry.pickable
		button.tooltip_text = entry.tip
		button.visible = true
	if _hovered >= 0 and _keys[_hovered] != under:
		pointed.emit(_keys[_hovered])
	var newest := items[0].id if not items.is_empty() else -1
	if newest > _newest_id:
		_fade_in(item(0))
	_newest_id = maxi(_newest_id, newest)


## The words of the items shown, left to right.
func item_texts() -> PackedStringArray:
	var result := PackedStringArray()
	for index in ITEMS:
		if item(index).visible:
			result.append(item(index).text)
	return result


## Item `index` (0 is the newest), for tests that click it.
func item(index: int) -> Button:
	return get_node("%%Item%d" % index)


func _fade_in(button: Button) -> void:
	if _fade != null:
		_fade.kill()
	button.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(button, "modulate:a", 1.0, FADE_SECONDS)


func _on_pressed(index: int) -> void:
	if not _keys[index].is_empty():
		picked.emit(_keys[index])


func _on_entered(index: int) -> void:
	_hovered = index
	pointed.emit(_keys[index])


func _on_exited(index: int) -> void:
	if _hovered == index:
		_hovered = -1
		pointed.emit("")
