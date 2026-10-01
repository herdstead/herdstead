class_name OfficeStation
extends Node2D
## One seat at a pod of desks: scenes/world/station.tscn.
##
## The origin is the seat. The station is y-sorted and merges into the floor's
## sort group, so its chair and worker sort against everything else by their
## own feet: the far chair just behind its worker, the near chair just in
## front. The Overlay floats above the world (OVERLAY_Z) and holds the name
## plate, the lens line, the selection mark, herdr's state badge and, while the
## agent is blocked, the chip on the badge's row (OfficeChip). A done agent's
## stack of paper is on the desk, which is the pod's (OfficeTable.show_papers()).
##
## Rows, 30 units wide and centred on the column, stacked away from the pod:
## the tag row (the badge, or the chip), the lens row (only while `L` is held)
## and the plate row (the provider, only while the seat is hovered, selected or
## `L` is held). Far workers face the viewer, so theirs rise above the head;
## near workers show their back, so theirs hang below the chair.
##
## A seat with no pane is vacant: a chair and nothing else. A pane with no
## agent is a SHELL: a laptop with a prompt and nobody in the chair. furnish()
## and select() change the station in place; a new state for the same worker
## only changes what that worker plays, so their animation carries on.
##
## On a floor, its people walk (OfficePresentation): a worker coming in, going
## to the pantry or back, or changing seats is still this seat's Actor, but while
## `walking` the seat leaves their place and pose to the presentation and only
## remembers what to seat them with; land() hands them back. The plate, the
## badge, the chip, the paper and the click target never wait for the walk:
## they are the signal.
##
## The seat answers a click itself: `Target` is an Area2D on OfficeWorld.PICKABLE
## holding both sides' rectangles, the chip's and the pantry's, and the
## viewport picks it. A click on the seat's rectangle picks the pane (`picked`),
## one on the chip asks to answer it (`asked`). A vacant seat is not pickable
## at all. The pointer over the seat's or the chip's rectangle shows the plate.
##
## A worker rests where their state says (OfficeRests, set by the presentation
## with rest_at()): at the seat — blocked with a hand up and the chip, done
## with the paper beside the laptop — or, idle, away from it in the floor's
## pantry. What hangs over them hangs where they rest. While they are away the
## seat itself still answers a click for the same pane (its empty chair and
## laptop stay), and so does the place they rest at: the `Away` rectangle, a
## second live target.

## A left click was released over this seat, at `at` in viewport pixels. Only a
## release can be a pick at all — a press is a drag that has not moved yet —
## and whether it stayed still enough is the office's to decide: it saw the
## same event one step earlier (see OfficeCamera.still_click()).
signal picked(key: String, at: Vector2)
## The same, released over this seat's chip: pick the pane and answer it.
## Only ever while the chip is shown (its rectangle is disabled otherwise).
signal asked(key: String, at: Vector2)
## The pointer came onto this seat's chip (`inside`) or left it: the office
## shows the question's excerpt in a HUD tooltip meanwhile.
signal chip_hovered(key: String, inside: bool)

const PERSON_SCENE := preload("res://scenes/people/pixel_person.tscn")
## The rows over a seat, relative to it (the far seat is at pod y -36, the near
## one at 22), measured on the pixel people: seated, the head reaches y -31
## over the seat and a blocked worker's raised hand -36 (pod -72 on the far
## side); the near chair is opaque down to seat + 6 (pod 28). Every row is
## 30 wide, so two neighbours' rows (32 apart) keep 2 units between them.
##
## The tag row is 16 tall: the badge (opaque 15 wide, 16 tall over its foot)
## stands on BADGE_AT, centred, at pod [-88, -72) far and [30, 46) near. Its
## pulse (OfficeAttention.PULSES) lifts it up to 2: [-90, -72) touches the
## raised hand and [28, 46) the chair, overlapping neither.
const BADGE_AT := {"far": Vector2(0, -36), "near": Vector2(0, 24)}
## The chip (OfficeChip, 30 by 16) is on the tag row, by its top-left corner;
## while its frame is drawn the badge moves CHIP_BADGE_SHIFT left, into the
## chip's left half and one unit over its left edge (x [-16, -1)), so the wait
## has daylight on both sides (OfficeChip.WAIT_RECT); the left neighbour's
## rows still end a unit short of it.
const CHIP_SIZE := OfficeChip.SIZE
const CHIP_AT := {"far": Vector2(-15, -52), "near": Vector2(-15, 8)}
const CHIP_BADGE_SHIFT := Vector2(-8.5, 0)
## The lens row (OfficeLens, while `L` is held), 30 by 12, next out from the
## tag row: pod [-102, -90) far and [46, 58) near. It holds the compact wait
## (OfficeAttention.compact_duration(): 18 wide at most).
const LENS_AT := {"far": Vector2(-15, -66), "near": Vector2(-15, 24)}
const LENS_SIZE := Vector2(30, 12)
## The plate, 30 by 12: the provider in upper case, in the display face at 8,
## cut with a forced ellipsis when it is wider (the card and the list say the
## whole name). While the lens is not held its row is empty, so the plate
## takes the lens row's slot, next to the tag row (LENS_AT: pod [-102, -90)
## far, [46, 58) near); while the lens is held it moves out to the outermost
## row, PLATE_AT: pod [-114, -102) far and [58, 70) near.
const PLATE_SIZE := Vector2(30, 12)
const PLATE_AT := {"far": Vector2(-15, -78), "near": Vector2(-15, 36)}
## The seat mark (ui `selection_seat`, 32 by 48 over its foot) frames the seated
## figure: pod [-72, -24) far, [-20, 28) near.
const SELECTION_AT := {"far": Vector2(0, 10), "near": Vector2(0, 4)}
## The lens row and the plate row are transient: they show only while `L` is
## held or the seat is hovered or selected, and are exempt from the pod's
## render_rect (the stationary drawing).
##
## The click target of each side, as scenes/world/station.tscn places it, 30
## wide: far pod [-90, -32) (the tag row's pulse envelope down to the desk's far
## plane), near pod [-21, 46) (the near laptop down to the tag row). While the
## chip shows, the seat's rectangle gives the tag row to the chip's
## (CHIP_TARGET): far [-72, -32), near [-21, 28). Never both under a point.
const TARGET_OF := {"far": ^"Target/Far", "near": ^"Target/Near"}
const SEAT_TARGET_AT := {"far": Vector2(0, -25), "near": Vector2(0, -9.5)}
const UNDER_CHIP_AT := {"far": Vector2(0, -16), "near": Vector2(0, -18.5)}
const UNDER_CHIP_SIZE := {"far": Vector2(30, 40), "near": Vector2(30, 49)}
## The chip's click rectangle (scenes/world/station.tscn), 30 by 18: the tag
## row with the badge's pulse envelope, far pod [-90, -72), near [28, 46).
## _place() lays it over the chip, CHIP_TARGET_AT from the chip's corner.
const CHIP_TARGET := ^"Target/Chip"
const CHIP_TARGET_AT := Vector2(15, 7)
## Over a worker resting away (the pantry), relative to where they stand: the
## badge right over the head; no plate: who is who is their coat, and a click on
## them opens their card (the Away rectangle, scenes/world/station.tscn, 38
## wide). The seat mark frames the standing figure (head -37), the lens row
## hangs above the badge.
const AWAY_BADGE_AT := Vector2(0, -47)
const AWAY_SELECTION_AT := Vector2(0, 4)
const AWAY_LENS_AT := Vector2(-15, -75)
const AWAY_TARGET := ^"Target/Away"
## The Away rectangle's centre over the feet: its foot 2 below them.
const AWAY_TARGET_AT := Vector2(0, -26)

## Each side's rectangle while the chip shows (UNDER_CHIP_SIZE), made once and
## shared: a shape resource of the scene is shared by every station.
static var _under_chip: Dictionary[String, RectangleShape2D] = {}

var art: ArtPack
var pen: OfficeDraw
## "far" (behind the table, facing the viewer) or "near" (in front, back turned).
var side := "far"
## The shared table this seat is at, and which of its columns. What stands on
## the table is the table's own (its monitors, its task lamps), so the station
## tells it what this seat carries and never reaches into it.
var table: OfficeTable
var column := -1
var seat: Marker2D
## Where the worker here rests (OfficeRests.Rest), and, for the pantry, where
## that is relative to the seat. The labels and the click targets
## follow it; the body walks there (OfficePresentation).
var rest := OfficeRests.Rest.SEAT
var away_at := Vector2.ZERO
var vacant := true
## Composite pane key (HerdrFleet.pane_key) of the pane seated here, as the
## office set it; empty while the seat is vacant. `picked` carries it.
var pane_key := ""
## Which way the chair faces, for the tests that hold a worker to their chair.
var chair_view := &""
## The floor's presentation (OfficePresentation) is walking this seat's worker:
## in, out of the way, to the pantry or back. Until it hands them back with land(), the
## seat leaves where the worker is and what they play alone, and only
## remembers what to seat them with; the plate, the badge and the click target
## still follow every observation at once.
var walking := false
## Each side's rectangle as the scene has it, kept when the chip swaps it out.
var _seat_shapes: Dictionary[String, Shape2D] = {}
## Which of this seat's rectangles the pointer is over now (the seat's own or
## the chip's), by shape node: the plate shows while any is.
var _hovered: Dictionary[Node, bool] = {}
## The seat is selected (select()), and the lens is held (show_lens()): the
## plate shows while either is.
var _selected := false
var _lens_held := false
## The semantic animation the last furnish() asked the worker to play.
var _animation := &""


## Dress this station and bind it to a seat. Repeated setup is safe; existing
## workers, attention state and animation clocks survive an unchanged binding.
func setup(drawing: OfficeDraw, at_table: OfficeTable, at_column: int, seat_side: String) -> void:
	if drawing == null or drawing.art == null or not _valid_binding(at_table, at_column, seat_side):
		push_error("OfficeStation: setup needs an art pack and a valid table seat")
		return
	var first_setup := pen == null
	var changed_art := art != drawing.art
	pen = drawing
	art = drawing.art
	var plate: Label = $Overlay/Plate
	pen.style_display(plate, 8, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	# The box again once the face is on: a Label is 23 tall before it.
	plate.size = PLATE_SIZE
	var lens: Label = $Overlay/Lens
	pen.style_display(lens, 8, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	lens.size = LENS_SIZE
	var mark := art.selection_mark()
	var selection: Sprite2D = $Overlay/Selection
	art.dress(selection, art.sprite_texture(mark), mark.pivot)
	chip().dress(pen)
	var badge: StatusBadge = $Overlay/Badge
	badge.chip = chip()
	if first_setup:
		badge.clear(art)
	if changed_art and actor() != null:
		var worker := actor()
		worker.configure(art.people, worker.provider, worker.look)
	rebind(at_table, at_column, seat_side)


## Move the same station onto a measured seat without replacing its worker.
## Equipment ownership is reconciled by the office after rebinding all seats;
## this method never clears a former seat that another station may now occupy.
func rebind(at_table: OfficeTable, at_column: int, seat_side: String) -> bool:
	if art == null or not _valid_binding(at_table, at_column, seat_side):
		push_error("OfficeStation: rebind needs setup and a valid table seat")
		return false
	if get_parent() != null and at_table.get_parent() != null and get_parent() != at_table.get_parent():
		push_error("OfficeStation: table and station must share the Sorted parent")
		return false
	side = seat_side
	table = at_table
	column = at_column
	seat = table.seat(column, side)
	position = table.position + seat.position
	var view := ArtContract.CHAIR_FRONT if side == "far" else ArtContract.CHAIR_BACK
	var chosen := art.table.piece(ArtContract.FURNITURE_CHAIR)
	var chair: Sprite2D = $Chair
	art.table.dress(chair, art.table.module_texture(chosen.view(view)), chosen.pivot)
	var chair_offset: float = OfficeTable.CHAIR_OFFSET[side]
	chair.position = Vector2(0, chair_offset)
	chair_view = view
	var worker := actor()
	if worker != null and not walking:
		_pose(worker)
	_place()
	return true


func _valid_binding(at_table: OfficeTable, at_column: int, seat_side: String) -> bool:
	return is_instance_valid(at_table) and at_table.has_seat(at_column, seat_side)


## Seat a pane here. `provider` empty means a shell with nobody in the chair.
## `agent_name` is herdr's name for the agent: the plate says it while a start
## is launching and herdr has not detected the kind yet.
func furnish(
	provider: String,
	state: StringName,
	selected := false,
	starting := false,
	pane_id := "",
	machine := "",
	agent_name := ""
) -> void:
	vacant = false
	# A pane is a terminal, so a seat with one has a screen on it, whether or not
	# an agent is in the chair. How hard its lamp burns is light()'s to say.
	table.equip(column, side, true, provider.is_empty() and not starting)
	var animation := art.animation_for_state(state, starting)
	_animation = animation
	var seated := get_node_or_null("Actor") as PixelPerson
	# Until the presentation says otherwise (rest_at()), at the seat.
	rest = OfficeRests.Rest.SEAT
	away_at = Vector2.ZERO
	# What only a state draws at a seat: the chip over a blocked agent, the
	# paper beside a done one's laptop. A pane still launching says nothing about
	# its agent yet, unless herdr already says blocked: a start that asks at once
	# is a blocked agent (blocked takes precedence; the caller passes PaneModel.launching()).
	# A shell has no agent. Set before _place(), which enables
	# the chip's rectangle only while it shows.
	var agent := not starting and not provider.is_empty()
	chip().visible = agent and state == ArtContract.STATE_BLOCKED
	if not chip().visible:
		chip().clear()
	table.show_papers(column, side, agent and state == ArtContract.STATE_DONE)
	if provider.is_empty() and not starting:
		_drop_actor()
	elif seated == null:
		seated = PERSON_SCENE.instantiate()
		seated.name = "Actor"
		# The pane's own face and hair (PixelPeople.look_for), fixed by its key.
		seated.vary_by(pane_key)
		seated.configure(art.people, provider, _pose_look())
		add_child(seated)
		# Chair, Actor, Overlay: the same shape a rebuild gives.
		move_child(seated, 1)
		# A worker the presentation walks in is posed by it, from the door.
		if not walking:
			_pose(seated)
			_play(seated)
		seated.add_to_group("office_actors")
	else:
		if seated.provider != provider or seated.variation_key != pane_key:
			seated.vary_by(pane_key)
			seated.configure(art.people, provider)
		# The same worker plays something else: nothing is rebuilt. One who is
		# walking keeps walking; land() seats them with this.
		if not walking:
			_play(seated)
			_pose(seated)
	_place()
	var plate: Label = $Overlay/Plate
	var named := starting and provider.is_empty() and not agent_name.is_empty()
	plate.text = agent_name.to_upper() if named else "SHELL" if provider.is_empty() else provider.to_upper()
	_show_plate()
	var badge: StatusBadge = $Overlay/Badge
	badge.stop_pulsing()
	if starting or not provider.is_empty():
		badge.show_badge(art, ArtContract.UI_STARTING if starting else art.state(state).badge)
		badge.visible = true
		# A pane still launching is not somebody waiting on a human yet.
		if not starting:
			badge.pulse_for(machine, pane_id, state)
	else:
		badge.clear(art)
	_pickable(true)
	select(selected)


## A seat nobody's pane uses: chair only.
func vacate() -> void:
	vacant = true
	pane_key = ""
	table.equip(column, side, false)
	table.light(column, side, OfficeTable.Lamp.OFF)
	table.show_papers(column, side, false)
	chip().visible = false
	chip().clear()
	_drop_actor()
	var plate: Label = $Overlay/Plate
	plate.text = ""
	_hovered.clear()
	var lens: Label = $Overlay/Lens
	lens.visible = false
	var badge: StatusBadge = $Overlay/Badge
	badge.clear(art)
	rest = OfficeRests.Rest.SEAT
	away_at = Vector2.ZERO
	_place()
	_pickable(false)
	select(false)


## The lens (OfficeLens) is `held`, or not: the lens line says `text` while
## it is, on a seat somebody's pane has and when there is anything to say (a
## shell, a dropped machine: nothing), the plate shows, and the chip draws none
## of itself meanwhile (OfficeChip.set_lensed()). Nothing is rebuilt: the
## text only when it changes, the line's and the plate's visibility, the chip's parts.
func show_lens(held: bool, text: String) -> void:
	var line: Label = $Overlay/Lens
	if held and line.text != text:
		line.text = text
	line.visible = held and not vacant and not text.is_empty()
	_lens_held = held
	chip().set_lensed(held)
	var plate: Label = $Overlay/Plate
	plate.position = rest_position() + _plate_at()
	_show_plate()


func select(selected: bool) -> void:
	var mark: Sprite2D = $Overlay/Selection
	mark.visible = selected and not vacant
	_selected = selected
	_show_plate()


## Whether the plate shows now: a seat somebody's pane has, worked at here
## (not away), and hovered, selected or under the held lens.
func plate_shown() -> bool:
	return not vacant and not away() and (not _hovered.is_empty() or _selected or _lens_held)


## Where the plate hangs over the seat: the lens row's slot, or while the lens
## is held (and the lens line has that row) the outermost row.
func _plate_at() -> Vector2:
	return PLATE_AT[side] if _lens_held else LENS_AT[side]


func _show_plate() -> void:
	var plate: Label = $Overlay/Plate
	var shown := plate_shown()
	if plate.visible != shown:
		plate.visible = shown


## Burn this seat's task lamp at `level`. Separate from furnish() because which
## pane herdr is looking at, and which tab its workspace has open, move on their
## own: neither changes who sits here.
func light(level: OfficeTable.Lamp) -> void:
	table.light(column, side, level)


## The person at this seat, sitting or in the pantry; null while the seat is vacant
## or holds a shell. A worker the presentation walks in, out of the way or
## back is still this seat's, wherever on the floor they are.
func actor() -> PixelPerson:
	return get_node_or_null("Actor") as PixelPerson


## The presentation has walked this seat's worker to where the seat says they
## belong: take them back, seat them or stand them in the pantry, and play what the
## last furnish() asked for, at the family's own pace.
func land() -> void:
	walking = false
	var worker := actor()
	if worker == null:
		return
	_pose(worker)
	_play(worker)


## The worker here rests at `kind` of place (OfficeRests.Rest): at the seat, or
## away at `at` (in the coordinates this station is placed in, the floor's) in
## the pantry. The labels and click
## targets move there at once; a worker not walking is posed there too, and one
## walking is posed there by land(). Nothing is rebuilt, so the badge's pulse
## and the wait go on. A vacant seat or a shell rests nobody.
func rest_at(kind: OfficeRests.Rest, at := Vector2.ZERO) -> void:
	var away_kind := kind == OfficeRests.Rest.PANTRY
	var wanted := at - position if away_kind else Vector2.ZERO
	if vacant or actor() == null or (kind == rest and wanted == away_at):
		return
	rest = kind
	away_at = wanted
	_place()
	if not walking:
		_pose(actor())
		_play(actor())


## Where the worker here rests, relative to the seat: the seat, or their spot
## in the pantry.
func rest_position() -> Vector2:
	return away_at if away() else Vector2.ZERO


## Whether the worker here rests away from the seat, in the pantry.
func away() -> bool:
	return rest == OfficeRests.Rest.PANTRY


## The chip on this seat's tag row (OfficeChip), shown only while its agent is blocked.
func chip() -> OfficeChip:
	return $Overlay/Chip


## Where the chip is drawn, in global coordinates (its 30 by 16 frame, drawn
## or not); an empty rectangle while it is hidden. What reveal() and the
## question reader look at.
func chip_rect() -> Rect2:
	var shown := chip()
	if not shown.visible:
		return Rect2()
	return Rect2(shown.global_position, CHIP_SIZE)


## Take the worker out of this seat without freeing them, for the presentation
## to walk out of the floor; null when nobody is here. The seat is then as a
## shell's or a vacant one's until furnish() says otherwise.
func release_worker() -> PixelPerson:
	walking = false
	var worker := actor()
	if worker != null:
		remove_child(worker)
	return worker


## Make `worker` (one the presentation is walking, from wherever they are) the
## worker of this seat, in the place a new one would take. The seat leaves
## their place and pose to the presentation until land().
func adopt_worker(worker: PixelPerson) -> void:
	_drop_actor()
	if worker.get_parent() != null:
		worker.get_parent().remove_child(worker)
	worker.name = "Actor"
	add_child(worker)
	# Chair, Actor, Overlay: the same shape a rebuild gives.
	move_child(worker, 1)
	walking = true


## Where this seat answers a click, in global coordinates: the rectangle of the
## side it is on, as the scene placed it; while they rest away, the rectangle
## over them there. What reveal() pans a desk in by.
func target_rect() -> Rect2:
	var box := _target_of(side)
	if away():
		box = get_node(AWAY_TARGET)
	var area: RectangleShape2D = box.shape
	return Rect2(box.global_position - area.size / 2.0, area.size)


## The viewport picked this seat. Only the release of a left button can be a
## pick: a press starts a drag, and a wheel notch or another button is never a
## pick however still it is. The motion the Area2D also reports is the office's
## pan, and it already has it. Which rectangle it landed on says which signal:
## the chip's asks, any other picks.
func _on_target_input_event(_viewport: Node, event: InputEvent, shape_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var click: InputEventMouseButton = event
	if click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var target: Area2D = $Target
	var hit := target.shape_owner_get_owner(target.shape_find_owner(shape_index))
	if hit == get_node(CHIP_TARGET):
		asked.emit(pane_key, click.position)
	else:
		picked.emit(pane_key, click.position)


## The pointer entered or left one of this seat's rectangles: the seat's own
## and the chip's show the plate while it is over them; the chip's is also the
## office's business (the question's tooltip).
func _on_target_mouse_shape_entered(shape_index: int) -> void:
	var shape := _shape_at(shape_index)
	if shape == _target_of(side) or shape == get_node(CHIP_TARGET):
		_hovered[shape] = true
		_show_plate()
	if shape == get_node(CHIP_TARGET):
		chip_hovered.emit(pane_key, true)


func _on_target_mouse_shape_exited(shape_index: int) -> void:
	var shape := _shape_at(shape_index)
	if _hovered.erase(shape):
		_show_plate()
	if shape == get_node(CHIP_TARGET):
		chip_hovered.emit(pane_key, false)


func _shape_at(shape_index: int) -> Node:
	var target: Area2D = $Target
	return target.shape_owner_get_owner(target.shape_find_owner(shape_index))


func _pickable(can_pick: bool) -> void:
	var target: Area2D = $Target
	target.input_pickable = can_pick
	if not can_pick:
		_hovered.clear()
		_show_plate()


func _target_of(of_side: String) -> CollisionShape2D:
	var path: NodePath = TARGET_OF[of_side]
	return get_node(path)


## How the worker here looks in a pose: standing in the pantry, anyone faces
## the viewer; at the desk, a near worker shows their back.
func _pose_look() -> AvatarLook:
	if rest != OfficeRests.Rest.SEAT:
		return AvatarLook.facing(AvatarLook.STAND, AvatarLook.FRONT)
	return AvatarLook.facing(AvatarLook.DESK, AvatarLook.FRONT if side == "far" else AvatarLook.BACK)


## Put `worker` where they rest: sit them on the seat, or stand them in the
## pantry, facing the viewer. Only the pose and the place change: the same
## node, at the family's own pace (a walk's pace never outlasts the walk).
func _pose(worker: PixelPerson) -> void:
	worker.pace(1.0)
	var wanted := _pose_look()
	if worker.look.context != wanted.context or worker.look.orientation != wanted.orientation:
		worker.configure(art.people, worker.provider, wanted)
	if rest == OfficeRests.Rest.SEAT:
		worker.sit(seat)
		worker.position = Vector2.ZERO
		return
	worker.stand_up()
	# Whoever walked up to the spot faced the way they walked.
	if worker.facing != PixelPeople.FRONT:
		worker.face(PixelPeople.FRONT)
	worker.position = rest_position()


## Play what the worker rests with: the pantry's cup by name (its `idle` is also
## a seated worker's), anything else as the last furnish() asked, through the
## family's state tracks for the pose (a seated blocked worker's is the raised
## hand at the desk).
func _play(worker: PixelPerson) -> void:
	if rest == OfficeRests.Rest.PANTRY:
		worker.play_track(ArtContract.TRACK_DRINK)
	elif not _animation.is_empty():
		worker.play_state(_animation)


## Hang the labels and the click targets where whoever is here rests: seated,
## or away (see rest_at()). Only moves the nodes that are already there and
## switches which rectangles answer a click: this side's seat rectangle always
## (the other side's never), the chip's while it shows, and while away the
## Away one too.
func _place() -> void:
	var away_here := away()
	var at := rest_position()
	var plate: Label = $Overlay/Plate
	plate.position = at + _plate_at()
	# Out of the tree the face is not on yet and a Label keeps the default
	# font's 23-unit height; in it, the row is its own height again.
	plate.size = PLATE_SIZE
	var selection: Sprite2D = $Overlay/Selection
	var lens: Label = $Overlay/Lens
	lens.size = LENS_SIZE
	if away_here:
		selection.position = at + AWAY_SELECTION_AT
		lens.position = at + AWAY_LENS_AT
	else:
		selection.position = at + SELECTION_AT[side]
		lens.position = at + LENS_AT[side]
	var shown := chip()
	var chip_at: Vector2 = CHIP_AT[side]
	shown.position = chip_at
	var chip_target: CollisionShape2D = get_node(CHIP_TARGET)
	chip_target.position = chip_at + CHIP_TARGET_AT
	chip_target.disabled = vacant or not shown.visible
	var under := not chip_target.disabled
	for each: String in OfficeTable.SIDES:
		var box := _target_of(each)
		box.disabled = each != side
		if not _seat_shapes.has(each):
			_seat_shapes[each] = box.shape
		if not _under_chip.has(each):
			var made := RectangleShape2D.new()
			made.size = UNDER_CHIP_SIZE[each]
			_under_chip[each] = made
		# This side's rectangle gives the tag row to the chip while it shows.
		var swapped := under and each == side
		box.shape = _under_chip[each] if swapped else _seat_shapes[each]
		box.position = UNDER_CHIP_AT[each] if swapped else SEAT_TARGET_AT[each]
	var away_target: CollisionShape2D = get_node(AWAY_TARGET)
	away_target.disabled = not away_here
	away_target.position = at + AWAY_TARGET_AT
	# A rectangle that stopped answering is not hovered any more.
	for shape: Node in _hovered.keys():
		var box := shape as CollisionShape2D
		if box == null or box.disabled:
			_hovered.erase(shape)
	_place_badge()
	_show_plate()


## The badge on the tag row: centred, or in the chip's left half while the
## chip's frame is drawn; over the head of a worker resting away.
func _place_badge() -> void:
	var badge: StatusBadge = $Overlay/Badge
	if away():
		badge.position = rest_position() + AWAY_BADGE_AT
		return
	var at: Vector2 = BADGE_AT[side]
	var shown := chip()
	if shown.visible and shown.framed():
		at += CHIP_BADGE_SHIFT
	badge.position = at


## The chip's frame came or went (OfficeChip.framed_changed): move the badge.
func _on_chip_framed(_framed: bool) -> void:
	_place_badge()


func _drop_actor() -> void:
	walking = false
	var seated := get_node_or_null("Actor")
	if seated != null:
		# Out of the tree now, not at frame end, so no group sees both workers.
		remove_child(seated)
		seated.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		var overlay: Node2D = $Overlay
		overlay.z_index = OfficeWorld.OVERLAY_Z
		var target: Area2D = $Target
		target.collision_layer = OfficeWorld.PICKABLE
