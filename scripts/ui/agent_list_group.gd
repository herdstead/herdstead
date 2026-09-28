class_name AgentListGroup
extends Button
## A group header in the agent list: a chevron, the group's name and how many
## under it need a human. A click folds or unfolds it. Kept by its key and
## updated in place, like the rows under it.

## The header was clicked: fold it if it is open, unfold it if it is folded.
signal toggled_open(key: String)

const LOOKS := {
	true: {"row": &"ListRowCurrent", "title": &"LabelPaper", "count": &"LabelPaper", "chevron": &"ListChevronCurrent"},
	false: {"row": &"ListGroup", "title": &"LabelWoodDark", "count": &"LabelSlate", "chevron": &"ListChevron"},
}

var key := ""
var collapsed := false

## What the header shows now, as one value; an equal one writes nothing.
var _signature := PackedStringArray()


func _ready() -> void:
	pressed.connect(func() -> void: toggled_open.emit(key))


## Draw `entry`, folded or not. `current` is the list's keyboard cursor.
## Nothing is written when the header already shows exactly this.
func show_group(entry: AgentListModel.Entry, is_collapsed: bool, current: bool) -> void:
	key = entry.key
	collapsed = is_collapsed
	var counted := count_text(entry)
	var next := PackedStringArray(
		[entry.title, counted, str(is_collapsed), str(current), str(entry.offline), str(entry.depth)]
	)
	if next == _signature:
		return
	_signature = next
	var look: Dictionary = LOOKS[current]
	theme_type_variation = look.row
	var chevron: Label = %Chevron
	var title: Label = %Title
	var count: Label = %Count
	chevron.text = "▶" if is_collapsed else "▼"
	chevron.theme_type_variation = look.chevron
	title.text = entry.title
	title.theme_type_variation = look.title if not entry.offline or current else &"LabelMuted"
	count.text = counted
	count.theme_type_variation = look.count if not entry.offline or current else &"LabelMuted"
	tooltip_text = "%s: %s" % [entry.title, counted] if not counted.is_empty() else entry.title
	var indent: PanelContainer = %Indent
	indent.visible = entry.depth > 0
	indent.theme_type_variation = StringName("ListIndent%d" % entry.depth)


## How many lines a flat group holds; for the tree's groups "3 waiting", else
## "1 unread", else how many. A dropped machine's groups count nobody: "offline".
static func count_text(entry: AgentListModel.Entry) -> String:
	# A flat group's name already says what its lines are.
	if AgentListModel.FLAT_GROUPS.has(entry.key):
		return str(entry.matched)
	if entry.offline:
		return "offline"
	if entry.waiting > 0:
		return "%d waiting" % entry.waiting
	if entry.unread > 0:
		return "%d unread" % entry.unread
	return str(entry.matched)
