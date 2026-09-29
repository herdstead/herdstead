extends Control
## The pixel people showroom (`make people`): every agent in the catalog in its
## look (the grid: the provider's default and the user's pins, each agent's
## face and hair varied by its id as a pane's are by its key), playing one track
## from one facing; every frame of every track in every facing it draws for one
## look (the frames view, the review sheet); or every option of every slot on
## that look, from the front, back and side (the options view, the contact
## sheet). Not a herdr client: nothing here opens a socket.
##
## The controls are engine controls laid out in scenes/people_showroom.tscn,
## styled by the HUD's theme; the people stand in cells from
## scenes/people/showroom_cell.tscn, made once. A choice only changes the
## properties of what is already there: the track or facing of the grid's
## people, the look of the sheets', which view is visible.
##
## Every view can be reproduced from the command line and captured:
##   godot --path . scenes/people_showroom.tscn -- --view=frames --track=walk \
##       --facing=left --look=headwear:hood,headwear_colour:teal --zoom=3 --capture=/abs/shot.png
## --view=grid|frames|options, --track= (a track name), --facing=front|back|side|left|
## right, --look=<slot>:<option>,... (the frames and options views'; slots it
## leaves out keep the pack's default), --zoom=N (the people's own
## whole magnification, one screen pixel per pixel; default 3), --manifest= (a
## people manifest, default PixelPeople.MANIFEST), --pack= (palette and font,
## default daylight). AppArgs reads them, the last of a repeated one winning.
## --capture=/abs.png and --wait= are CaptureDriver's, as in every other scene
## (a real window only, never --headless).

const DEFAULT_PACK := "res://assets/daylight/manifest.json"
const CELL_SCENE := preload("res://scenes/people/showroom_cell.tscn")
const GROUP_SCENE := preload("res://scenes/people/showroom_group.tscn")
const GRID := &"grid"
const FRAMES := &"frames"
const OPTIONS := &"options"
const VIEWS: Array[StringName] = [GRID, FRAMES, OPTIONS]
## The options view holds each option still on this frame of this track.
const OPTIONS_TRACK := &"stand_idle"
const DEFAULT_ZOOM := 3
## The showroom draws its controls at one screen pixel per pixel, so its text
## is set larger than the office HUD's 10, which is sized for a 2-3x office.
const FONT_SIZE := 15
## Gaps, in screen pixels: round the page, between cells, inside a cell.
const MARGIN := 8
const CELL_GAP := 6
const CAPTION_GAP := 2
## Palette key per panel variation: the page behind everything, and the stage
## the people stand on.
const PANELS: Dictionary[StringName, StringName] = {
	&"ShowroomBackdrop": ArtContract.DEEP,
	&"ShowroomStage": ArtContract.INK,
}

## The command line (see the header). A test may set it before the showroom
## enters the tree; otherwise it is this process's own, read in _ready().
var args: AppArgs
## The family shown; read from --manifest= (PixelPeople.MANIFEST) when nobody
## set it before the showroom entered the tree.
var people: PixelPeople
var art: ArtPack
## The people's whole magnification: one texture pixel is zoom x zoom screen
## pixels.
var zoom := DEFAULT_ZOOM
var view := GRID
## What the grid plays, and which way it faces.
var track := &""
var facing := PixelPeople.FRONT
## What the frames and options views wear: every slot set.
var look := AvatarLook.new()
## Why the showroom could not be built, in the failure's own words; empty while
## everything shows.
var failure := ""

var _grid_people: Array[PixelPerson] = []
var _frame_people: Array[PixelPerson] = []
## The options view's people, and the slot and option each one shows.
var _option_people: Array[PixelPerson] = []
var _option_of: Array[StringName] = []


func _ready() -> void:
	# One screen pixel per pixel: --zoom is the only magnification.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if args == null:
		args = AppArgs.current()
	art = ArtPack.from_manifest(args.text("pack", DEFAULT_PACK))
	if people == null:
		people = PixelPeople.from_manifest(args.text("manifest", PixelPeople.MANIFEST))
	if art == null or people == null:
		failure = "no art pack or no pixel people to show (see the error above)"
		push_error("The people showroom: " + failure)
		get_tree().quit(1)
		return
	theme = _theme(art)
	_choose()
	_fill_controls()
	_build_grid()
	_build_frames()
	_build_options()
	_connect()
	_show()
	if args.has("capture"):
		await CaptureDriver.run(self, args, "people showroom")


## The view, track, facing, look and zoom the command line asks for, each
## checked against what the family draws; anything it does not know keeps the
## default.
func _choose() -> void:
	zoom = maxi(1, args.number("zoom", DEFAULT_ZOOM))
	var wanted_view := StringName(args.text("view", str(GRID)))
	view = wanted_view if VIEWS.has(wanted_view) else GRID
	var first: StringName = people.tracks.keys()[0]
	var wanted_track := StringName(args.text("track", str(first)))
	track = wanted_track if people.tracks.has(wanted_track) else first
	facing = _facing(StringName(args.text("facing", str(PixelPeople.FRONT))))
	look = people.default_look.clothes()
	for pair in args.text("look", "").split(",", false):
		var parts := pair.split(":")
		if parts.size() == 2 and people.slots.has(StringName(parts[0])):
			if people.slots[StringName(parts[0])].has_option(StringName(parts[1])):
				look.set_slot(StringName(parts[0]), StringName(parts[1]))


## A facing as the Facing control lists it: front, back, side (the way the
## side strip is drawn) or its mirror.
func _facing(wanted: StringName) -> StringName:
	if wanted == PixelPeople.SIDE or wanted == people.side_faces:
		return PixelPeople.SIDE
	if wanted == PixelPeople.LEFT or wanted == PixelPeople.RIGHT:
		return _mirror()
	return wanted if wanted == PixelPeople.BACK else PixelPeople.FRONT


## The side the side strip is not drawn for: its mirror.
func _mirror() -> StringName:
	return PixelPeople.LEFT if people.side_faces == PixelPeople.RIGHT else PixelPeople.RIGHT


func _facings() -> Array[StringName]:
	return [PixelPeople.FRONT, PixelPeople.BACK, PixelPeople.SIDE, _mirror()]


func _fill_controls() -> void:
	var choices: Dictionary[String, Array] = {
		"View": VIEWS,
		"Track": people.tracks.keys(),
		"Facing": _facings(),
	}
	var chosen: Dictionary[String, StringName] = {"View": view, "Track": track, "Facing": facing}
	for slot_id in AvatarLook.SLOTS:
		choices[_control_of(slot_id)] = people.slots[slot_id].options()
		chosen[_control_of(slot_id)] = look.slot(slot_id)
	for unique in choices:
		var button := _choice(unique)
		for value: StringName in choices[unique]:
			button.add_item(str(value))
		button.select(choices[unique].find(chosen[unique]))


## The OptionButton that picks slot `slot_id` ("HairColour" for hair_colour).
static func _control_of(slot_id: StringName) -> String:
	return str(slot_id).to_pascal_case()


## One cell per catalog agent, each wearing that agent's look: the provider's
## default and the user's pins, the face and hair varied by the agent's id the
## way a worker's are by their pane's key.
func _build_grid() -> void:
	var grid := %Grid as GridContainer
	var catalog := people.catalog()
	for id in catalog.ids():
		var person := _cell(grid, id)
		person.vary_by(id)
		person.configure(people, id)
		person.face(facing)
		person.play_track(track)
		_grid_people.append(person)


## Every frame of every track, in every facing that track draws, held still:
## a group per track and facing, a cell per frame.
func _build_frames() -> void:
	var sheet := %Frames as HFlowContainer
	for id in people.tracks:
		var entry := people.tracks[id]
		for strip in entry.facings:
			var group: VBoxContainer = GROUP_SCENE.instantiate()
			sheet.add_child(group)
			(group.get_node("Title") as Label).text = "%s · %s" % [id, strip]
			var row := group.get_node("Row") as HBoxContainer
			for index in entry.frame_count():
				var person := _cell(row, str(index))
				person.configure(people, "", _worn(strip))
				person.face(people.side_faces if strip == PixelPeople.SIDE else strip)
				person.hold(id, index)
				_frame_people.append(person)


## Every option of every slot on the look, still on the first frame of
## OPTIONS_TRACK, from each facing it draws: a group per option, a cell per
## facing. The contact sheet of what the family can wear.
func _build_options() -> void:
	var sheet := %Options as HFlowContainer
	var entry := people.tracks[OPTIONS_TRACK]
	for slot_id in AvatarLook.SLOTS:
		for option in people.slots[slot_id].options():
			var group: VBoxContainer = GROUP_SCENE.instantiate()
			sheet.add_child(group)
			(group.get_node("Title") as Label).text = "%s · %s" % [slot_id, option]
			var row := group.get_node("Row") as HBoxContainer
			for strip in entry.facings:
				var person := _cell(row, str(strip))
				person.configure(people, "", _option_look(slot_id, option, strip))
				person.face(people.side_faces if strip == PixelPeople.SIDE else strip)
				person.hold(OPTIONS_TRACK, 0)
				_option_people.append(person)
				_option_of.append(slot_id)


## The views' look with `slot_id` set to `option`, in a pose facing `strip`.
func _option_look(slot_id: StringName, option: StringName, strip: StringName) -> AvatarLook:
	var worn := _worn(strip)
	worn.set_slot(slot_id, option)
	return worn


## The frames view's look in a pose: standing, facing the way the strip does.
func _worn(strip: StringName) -> AvatarLook:
	var worn := look.copy()
	worn.context = AvatarLook.STAND
	worn.orientation = AvatarLook.BACK if strip == PixelPeople.BACK else AvatarLook.FRONT
	return worn


## A cell under `parent` captioned `caption`, sized for one magnified frame;
## returns the person standing in it, on its feet.
func _cell(parent: Container, caption: String) -> PixelPerson:
	var cell: VBoxContainer = CELL_SCENE.instantiate()
	parent.add_child(cell)
	(cell.get_node("Figure") as Control).custom_minimum_size = Vector2(people.frame_size * zoom)
	(cell.get_node("Figure/Stage") as Node2D).scale = Vector2.ONE * zoom
	(cell.get_node("Caption") as Label).text = caption
	var person := cell.get_node("Figure/Stage/Person") as PixelPerson
	person.position = people.pivot
	return person


func _connect() -> void:
	var controls: Array[String] = ["View", "Track", "Facing"]
	for slot_id in AvatarLook.SLOTS:
		controls.append(_control_of(slot_id))
	for unique in controls:
		_choice(unique).item_selected.connect(_on_choice_selected.bind(unique))
	(%Play as Button).pressed.connect(_on_play_pressed)


## Show the chosen view and say what is on it. The controls that do not
## change this view are disabled, not hidden, so the rows never reflow.
func _show() -> void:
	var on_grid := view == GRID
	(%Grid as Control).visible = on_grid
	(%Frames as Control).visible = view == FRAMES
	(%Options as Control).visible = view == OPTIONS
	for unique: String in ["Track", "Facing"]:
		_choice(unique).disabled = not on_grid
	for slot_id in AvatarLook.SLOTS:
		_choice(_control_of(slot_id)).disabled = on_grid
	(%Play as Button).disabled = not on_grid
	var playing := not _grid_people.is_empty() and _grid_people[0].is_playing()
	(%Play as Button).text = "pause" if playing else "play"
	var mocks := people.mock_files.size()
	var sources := people.facings.size() * _source_count()
	var shown := "%d agents, their looks" % _grid_people.size()
	if view == FRAMES:
		shown = "%d frames of one look" % _frame_people.size()
	elif view == OPTIONS:
		shown = (
			"%d options, front / back / side"
			% (_option_people.size() / maxi(1, people.tracks[OPTIONS_TRACK].facings.size()))
		)
	(%Status as Label).text = (
		"zoom x%d · %s · %d of %d source strips are placeholders" % [zoom, shown, mocks, sources]
	)


## Source strips per facing: one per shape of each layer, one for a layer
## without shapes.
func _source_count() -> int:
	var count := 0
	for layer in PixelPeople.LAYERS:
		var shapes := 1
		for slot_id in people.slots:
			var slot := people.slots[slot_id]
			if slot.layer == layer and not slot.is_colour():
				shapes = slot.shapes.size()
		count += shapes
	return count


func _choice(unique: String) -> OptionButton:
	return get_node("%" + unique) as OptionButton


func _on_choice_selected(index: int, unique: String) -> void:
	var value := StringName(_choice(unique).get_item_text(index))
	match unique:
		"View":
			view = value
		"Track":
			track = value
			for person in _grid_people:
				person.play_track(track)
		"Facing":
			facing = value
			for person in _grid_people:
				person.face(people.side_faces if facing == PixelPeople.SIDE else facing)
		_:
			for slot_id in AvatarLook.SLOTS:
				if _control_of(slot_id) == unique:
					look.set_slot(slot_id, value)
			# Clothes only: every held frame keeps its facing and its frame, and
			# every option cell keeps showing its own option.
			for person in _frame_people:
				person.configure(people, "", look.clothes())
			for at in _option_people.size():
				var person := _option_people[at]
				var shown := look.clothes()
				shown.set_slot(_option_of[at], person.look.slot(_option_of[at]))
				person.configure(people, "", shown)
	_show()


func _on_play_pressed() -> void:
	var playing := not _grid_people.is_empty() and _grid_people[0].is_playing()
	for person in _grid_people:
		if playing:
			person.pause()
		else:
			person.play()
	_show()


## The showroom's Theme: the office HUD's own (the same pack, the same readable
## font; its OptionButton, Button and PopupMenu looks), plus the panels, gaps
## and text size only the showroom needs. Nothing here changes scripts/ui/.
static func _theme(pack: ArtPack) -> Theme:
	var result := HudTheme.build(pack, OfficeDraw.new(pack).font)
	result.default_font_size = FONT_SIZE
	for variation in PANELS:
		var base := "PanelContainer" if variation == &"ShowroomStage" else "Panel"
		result.set_type_variation(variation, base)
		var box := StyleBoxFlat.new()
		box.bg_color = pack.color(PANELS[variation])
		result.set_stylebox("panel", variation, box)
	result.set_type_variation(&"ShowroomMargin", "MarginContainer")
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		result.set_constant(side, &"ShowroomMargin", MARGIN)
	var gaps: Dictionary[StringName, int] = {
		&"ShowroomColumn": MARGIN, &"ShowroomRow": CELL_GAP, &"ShowroomCell": CAPTION_GAP, &"ShowroomGroup": CAPTION_GAP
	}
	var bases: Dictionary[StringName, String] = {
		&"ShowroomColumn": "VBoxContainer",
		&"ShowroomRow": "HBoxContainer",
		&"ShowroomCell": "VBoxContainer",
		&"ShowroomGroup": "VBoxContainer",
	}
	for variation in gaps:
		result.set_type_variation(variation, bases[variation])
		result.set_constant("separation", variation, gaps[variation])
	# The HUD's LabelSlate is sized for a 2-3x office; notes here are read at 1x.
	result.set_type_variation(&"ShowroomNote", "Label")
	result.set_color("font_color", &"ShowroomNote", pack.color(ArtContract.MUTED))
	result.set_type_variation(&"ShowroomGrid", "GridContainer")
	result.set_type_variation(&"ShowroomFlow", "HFlowContainer")
	for variation: StringName in [&"ShowroomGrid", &"ShowroomFlow"]:
		result.set_constant("h_separation", variation, CELL_GAP * 2)
		result.set_constant("v_separation", variation, CELL_GAP * 2)
	return result
