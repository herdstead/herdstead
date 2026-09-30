class_name OfficeFloorPlate
extends Control
## The machine plate over the map's zones (scenes/world/floor_plate.tscn): the
## machine's name (`@ NAME` once there is more than Local), and then its live
## state; a machine with no workspace says why it has none (its note); the
## machine's counts on the right; and under the band, why its map cannot be
## laid out, naming the zones at fault (`3 INFRA: invalid explicit seat hint`),
## for as long as it cannot. Each zone's number, name, repository and checkout
## are on its own sign (OfficeZoneSign), not here.
##
## World furniture that reads like the HUD: Labels in containers, styled by
## HudTheme's type variations, so this script places nothing. All it decides is
## how the band's width is shared out when it runs short (see _fit()). Its nodes
## are permanent: a new count, state or note is new text in the same Labels.

## How much of the band's room the machine's name may take first.
@export var title_share := 0.0
## How wide the repository line may grow, and how much more of it a linked
## worktree's checkout directory gets after the repository name (unused on a
## machine plate: the zone signs carry both).
@export var repo_width := 0.0
@export var worktree_width := 0.0
## How wide an empty map's note may grow, and a mezzanine's "worktree of" line.
@export var note_width := 0.0
@export var source_width := 0.0
@export var machine_width := 0.0

## The machine has no zone: its note says why.
var _empty := false
var _several := false


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


## What the plate says about machine `building`'s map. `several` is there being
## more than Local; `problems` are why the map cannot be laid out, and empty
## while it can; `failing_zones` are the zones at fault (FloorPlanCache.failing_zones()),
## which the problem line names. The machine's live state is show_state()'s.
func show_map(
	building: BuildingModel, several: bool, problems: PackedStringArray, failing_zones: PackedStringArray
) -> void:
	_empty = building.zones.is_empty()
	_several = several
	var title: Label = %Title
	title.text = ("@ " if several else "") + building.label.to_upper()
	var source: Label = %WorktreeOf
	source.text = ""
	_show_accent("")
	var repo_label: Label = %RepoLine
	repo_label.text = ""
	var machine_label: Label = %MachineLine
	machine_label.text = ""
	var counts: Label = %Counts
	counts.text = "%d SPACES / %d PANES" % [building.spaces, building.panes]
	var problem: Label = %Problem
	problem.visible = not problems.is_empty()
	problem.text = (
		"" if problems.is_empty() else "Layout unavailable: " + problem_line(building, problems, failing_zones)
	)
	_fit()


## The first of `problems`, the zones at fault named as their signs name them
## (`3 INFRA`): a zone's own problem (`zone <key>: …`) by that zone, a map-wide
## one (a budget) after the zones `failing_zones` names.
static func problem_line(
	building: BuildingModel, problems: PackedStringArray, failing_zones: PackedStringArray
) -> String:
	if problems.is_empty():
		return ""
	var said := problems[0]
	var names: Dictionary[String, String] = {}
	for zone in building.zones:
		names[zone.key] = "%s %s" % [zone.level_label, zone.label.to_upper()]
	for key: String in names:
		var prefix := "zone %s: " % key
		if said.begins_with(prefix):
			return names[key] + ": " + said.substr(prefix.length())
	var named := PackedStringArray()
	for key in failing_zones:
		if names.has(key):
			named.append(names[key])
	return said if named.is_empty() else ", ".join(named) + ": " + said


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


## The accent before the title: none on a machine plate (each zone's sign wears
## its worktree group's).
func _show_accent(group: String) -> void:
	var accent: Control = %Accent
	accent.visible = not group.is_empty()
	if accent.visible:
		accent.theme_type_variation = StringName("PlateAccent%d" % OfficeZoneSign.accent_of(group))


## Whether the plate names the machine and its state: once there is more than Local.
func shows_state() -> bool:
	return _several


func state_text() -> String:
	var state_label: Label = %State
	return state_label.text


## An empty map's note, in full whatever the band has room to show; empty on a
## machine with zones.
func note_text() -> String:
	var note_label: Label = %Note
	return note_label.text if _empty else ""


## What the plate names now: the machine (`@ NAME` among several).
func title_text() -> String:
	var title: Label = %Title
	return title.text


## The problem line under the band; empty while the map can be laid out.
func problem_text() -> String:
	var problem: Label = %Problem
	return problem.text if problem.visible else ""


## Share the band's width out the way the plate is read when it runs short: the
## counts keep their whole width on the right; the machine's name comes first,
## up to `title_share` of the room left of them; then an empty map's note, up to
## its width; then the
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
		left -= mark + _allot(repo_label, repo_width, left - mark) + gap
	source.visible = false
	# A map that had no zone and has some now keeps the same plate: its note
	# gives its room back, as a plate made afresh would have it.
	var note_room := _allot(note, note_width if _empty else 0.0, left if _empty else 0.0)
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
