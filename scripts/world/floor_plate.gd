class_name OfficeFloorPlate
extends Control
## The plate over the shown floor's rooms (scenes/world/floor_plate.tscn):
## `3F  LABEL`, or a mezzanine's `3A · CHECKOUT` with "worktree of 3F" after
## it; a worktree group's accent before the title, one colour for the source
## floor and all its mezzanines; the repository by its branch mark, with the
## checkout a linked worktree stands in, or a lobby's note saying why its
## building has no floors;
## the machine and its live state once there is more than Local; the floor's
## counts on the right; and under the band, why the floor cannot be laid out,
## for as long as it cannot.
##
## World furniture that reads like the HUD: Labels in containers, styled by
## HudTheme's type variations, so this script places nothing. All it decides is
## how the band's width is shared out when it runs short (see _fit()). Its nodes
## are permanent: a new count, state or note is new text in the same Labels.

## How much of the band's room the floor's own name may take first.
@export var title_share := 0.0
## How wide the repository line may grow, and how much more of it a linked
## worktree's checkout directory gets after the repository name.
@export var repo_width := 0.0
@export var worktree_width := 0.0
## How wide a lobby's note may grow, and a mezzanine's "worktree of" line.
@export var note_width := 0.0
@export var source_width := 0.0
@export var machine_width := 0.0

var _lobby := false
var _several := false
var _worktree := false
var _mezzanine := false


func _ready() -> void:
	# HdPanel._init() gives a panel the HUD's own look and takes the mouse, when
	# the scene sets its script, after the scene's other properties. The plate's
	# band keeps its text further in from the frame than a HUD panel does, and
	# it is world furniture: a press, a drag or the wheel over it moves the
	# office like anywhere else on the floor.
	var band: Control = %Band
	band.theme_type_variation = &"PlateBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Take the pack's branch mark and the Theme the HUD is dressed in.
func dress(art: ArtPack, look: Theme) -> void:
	theme = look
	var band: HdPanel = %Band
	band.dress(art)
	var mark: Sprite2D = %Mark
	var spec := art.ui_sprite(ArtContract.UI_BRANCH)
	art.dress(mark, art.sprite_texture(spec), spec.pivot)


## What the plate says about `floor_model` of `building`. `several` is there
## being more than Local; `problems` are why the floor cannot be laid out, and
## empty while it can. The machine's live state is show_state()'s.
func show_floor(building: BuildingModel, floor_model: FloorModel, several: bool, problems: PackedStringArray) -> void:
	_lobby = floor_model.lobby
	_several = several
	_worktree = not floor_model.worktree.is_empty()
	_mezzanine = not floor_model.mezzanine_of.is_empty()
	var title: Label = %Title
	var number := OfficeFloorRow.number_text(floor_model)
	title.text = "%s  %s" % [number, floor_model.label.to_upper()]
	if _lobby:
		title.text = "LOBBY"
	elif _mezzanine:
		# A mezzanine is named by its checkout, which says which branch it is.
		title.text = "%s · %s" % [number, (floor_model.worktree if _worktree else floor_model.label).to_upper()]
	var source: Label = %WorktreeOf
	source.text = ""
	var group := floor_model.mezzanine_of
	for other in building.floors:
		if _mezzanine and other.key == floor_model.mezzanine_of:
			source.text = "worktree of " + OfficeFloorRow.number_text(other)
		elif not _mezzanine and other.mezzanine_of == floor_model.key:
			group = floor_model.key
	_show_accent(group)
	# The repository, and after it the checkout directory a linked worktree
	# stands in. Both go in one clipped label, so a narrow window trims the
	# checkout first and the floor's own name, before it, never. A mezzanine's
	# title already carries its checkout.
	var repo_line := floor_model.repo
	if _worktree and not _mezzanine:
		repo_line = floor_model.worktree if repo_line.is_empty() else repo_line + " / " + floor_model.worktree
	var repo_label: Label = %RepoLine
	repo_label.text = repo_line
	var machine_label: Label = %MachineLine
	machine_label.text = "@ " + building.label.to_upper() if several else ""
	var counts: Label = %Counts
	counts.text = "%d SPACES / %d PANES" % [building.spaces, building.panes]
	if not _lobby:
		var tabs := floor_model.rooms.size()
		var panes := floor_model.pane_count()
		counts.text = "%d TAB%s / %d PANE%s" % [tabs, "" if tabs == 1 else "S", panes, "" if panes == 1 else "S"]
	var problem: Label = %Problem
	problem.visible = not problems.is_empty()
	problem.text = "" if problems.is_empty() else "Layout unavailable: " + problems[0]
	_fit()


## The machine's live state as the minimap shows it, and `reason`, its SSH
## forward's last complaint. Only text changes: a flapping machine relabels.
func show_state(state: MachineLiveness.State, reason: String) -> void:
	var text := "LIVE"
	var note := "No workspaces in this herdr session."
	if state == MachineLiveness.State.CONNECTING:
		text = "CONNECTING"
		note = "Connecting."
	elif state == MachineLiveness.State.OFFLINE:
		text = "OFFLINE"
		note = "Waiting for herdr."
		if not reason.is_empty():
			text += " / " + reason
			note = text
	var state_label: Label = %State
	state_label.text = text
	state_label.theme_type_variation = &"LabelWorking" if state == MachineLiveness.State.LIVE else &"LabelBlocked"
	var note_label: Label = %Note
	note_label.text = note
	_fit()


## A worktree group (`group`, its source floor's key) wears one accent on every
## plate of it, picked from the pack's accent colours by that key alone: decor
## that follows the structure, never the state. A floor in no group wears none.
func _show_accent(group: String) -> void:
	var accent: Control = %Accent
	accent.visible = not group.is_empty()
	if accent.visible:
		accent.theme_type_variation = StringName("PlateAccent%d" % posmod(group.hash(), ArtContract.ACCENTS.size()))


## Whether the plate names the machine and its state: once there is more than Local.
func shows_state() -> bool:
	return _several


func state_text() -> String:
	var state_label: Label = %State
	return state_label.text


## A lobby's note, in full whatever the band has room to show; empty on a floor.
func note_text() -> String:
	var note_label: Label = %Note
	return note_label.text if _lobby else ""


## Share the band's width out the way the plate is read when it runs short: the
## counts keep their whole width on the right; the floor's own name comes first,
## up to `title_share` of the room left of them; then the repository line (the
## checkout, last in the same label, trims first), a mezzanine's "worktree of"
## line (whole or hidden) or a lobby's note, each up to its width; then the
## machine; the state gets what is left. A label left with no room is hidden,
## so the containers never lay out more than the band holds.
func _fit() -> void:
	var band: Control = %Band
	var line: HBoxContainer = %Line
	var row: HBoxContainer = %Row
	var items: HBoxContainer = %Items
	var repo: HBoxContainer = %Repo
	var branch: Control = %Branch
	var machine: HBoxContainer = %Machine
	var title: Label = %Title
	var heading: HBoxContainer = %Heading
	var accent: Control = %Accent
	var source: Label = %WorktreeOf
	var repo_label: Label = %RepoLine
	var note: Label = %Note
	var machine_label: Label = %MachineLine
	var state_label: Label = %State
	var counts: Label = %Counts
	var frame := band.get_theme_stylebox("panel")
	var gap := float(items.get_theme_constant("separation"))
	# The room left of the counts and their gap, measured from the plate's edge.
	var room := size.x - frame.get_margin(SIDE_RIGHT) - row.get_theme_constant("separation") - _text_width(counts)
	var accent_room := (
		accent.custom_minimum_size.x + heading.get_theme_constant("separation") if accent.visible else 0.0
	)
	var title_width := (
		accent_room + _allot(title, room * title_share - accent_room, room - frame.get_margin(SIDE_LEFT) - accent_room)
	)
	var left := room - frame.get_margin(SIDE_LEFT) - title_width - line.get_theme_constant("separation")
	repo.visible = not repo_label.text.is_empty()
	if repo.visible:
		var mark := branch.custom_minimum_size.x + repo.get_theme_constant("separation")
		left -= mark + _allot(repo_label, repo_width + (worktree_width if _worktree else 0.0), left - mark) + gap
	source.visible = false
	if _mezzanine and not source.text.is_empty():
		# After the repository, which the title does not already say; and whole
		# or not at all: "wo…" says nothing.
		var source_room := _allot(source, source_width, left)
		if source_room < _text_width(source):
			source_room = _allot(source, 0.0, 0.0)
		left -= source_room + (gap if source_room > 0.0 else 0.0)
	note.visible = false
	if _lobby:
		var note_room := _allot(note, note_width, left)
		left -= note_room + (gap if note_room > 0.0 else 0.0)
	machine.visible = _several
	if _several:
		left -= _allot(machine_label, machine_width, left) + machine.get_theme_constant("separation")
		_allot(state_label, INF, left)


## Give `label` its text's width, no more than `cap` or `available`, and hide it
## when that is nothing at all.
func _allot(label: Label, cap: float, available: float) -> float:
	var width := maxf(0.0, minf(minf(_text_width(label), cap), available))
	label.custom_minimum_size.x = width
	label.visible = width > 0.0
	return width


func _text_width(label: Label) -> float:
	var font := label.get_theme_font("font")
	var pixels := label.get_theme_font_size("font_size")
	return ceilf(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x)
