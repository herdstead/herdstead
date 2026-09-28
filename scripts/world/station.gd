class_name OfficeStation
extends Node2D
## One seat at a shared table: scenes/world/station.tscn.
##
## The origin is the seat. The station is y-sorted and merges into the floor's
## sort group, so its chair and worker sort against everything else by their
## own feet: the far chair just behind its worker, the near chair just in
## front. The Overlay floats above the world (OVERLAY_Z) and holds the name
## plate, the selection mark, herdr's state badge and, while the agent is
## blocked, the bubble over the head (OfficeBubble). A done agent's stack of
## paper is on the table, which is the table's (OfficeTable.show_papers()).
##
## A seat with no pane is vacant: a chair and nothing else. A pane with no
## agent is a SHELL: a plate but nobody sitting there. furnish() and select()
## change the station in place; a new state for the same worker only changes
## what that worker plays, so their animation carries on.
##
## On a floor, its people walk (OfficePresentation): a worker coming in, going
## to the pantry or back, or changing seats is still this seat's Actor, but while
## `walking` the seat leaves their place and pose to the presentation and only
## remembers what to seat them with; land() hands them back. The plate, the
## badge, the bubble, the paper and the click target never wait for the walk:
## they are the signal.
##
## The seat answers a click itself: `Target` is an Area2D on OfficeWorld.PICKABLE
## holding both sides' rectangles, the bubble's and the pantry's, and the
## viewport picks it. A click on the seat's rectangle picks the pane (`picked`),
## one on the bubble asks to answer it (`asked`). A vacant seat is not pickable
## at all.
##
## A worker rests where their state says (OfficeRests, set by the presentation
## with rest_at()): at the seat — blocked with a hand up and the bubble, done
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
## The same, released over this seat's bubble: pick the pane and answer it.
## Only ever while the bubble is shown (its rectangle is disabled otherwise).
signal asked(key: String, at: Vector2)
## The pointer came onto this seat's bubble (`inside`) or left it: the office
## shows the question's excerpt in a HUD tooltip meanwhile.
signal bubble_hovered(key: String, inside: bool)

const PERSON_SCENE := preload("res://scenes/people/pixel_person.tscn")
## Plate and badge, relative to the seat. Far workers face the viewer, so their
## labels float above the head; near workers show their back, so theirs sit
## below the chair, clear of the table.
##
## The lens line (OfficeLens, while `L` is held): how long this agent has been
## in its state, one line of it. Far: left of the badge, level with its top
## rows and right over the plate (x -30..18, y -65..-53; the badge is drawn at
## x 18..34), where the bubble would be and is not drawn meanwhile; table-local
## it starts at -133, inside the -150 the decor is planned around. Near: under
## the plate, as wide (y 34..46, table-local 56..68, inside the 72). Over a
## worker resting away: above their badge (y -75..-63 over the feet; the badge
## is drawn at -63..-47).
const LENS_AT := {"far": Vector2(-30, -65), "near": Vector2(-38, 34)}
const LENS_SIZE := {"far": Vector2(48, 12), "near": Vector2(76, 12)}
const AWAY_LENS_AT := Vector2(-24, -75)
const AWAY_LENS_SIZE := Vector2(48, 12)
## Measured on the pixel people (every frame of the track, both layers, x and y
## from the feet): seated, the head reaches y = -33 and a blocked worker's
## raised hand -38 (the bent arm); standing
## (in the pantry), the head spans y -38..-25; every figure is x -9..9 (12
## with a raised hand). The plate's
## text is 11 units from its top to the baseline at this font. A far plate's
## baseline sits 9 above the seated head: 4 above a raised hand, which it never
## touches. The far badge rests on the plate's row; near labels hang off the
## chair, not the head.
const PLATE_SIZE := Vector2(76, 12)
const PLATE_AT := {"far": Vector2(-38, -53), "near": Vector2(-38, 22)}
const BADGE_AT := {"far": Vector2(26, -53), "near": Vector2(30, 20)}
## The mark's top corners run level with the far plate's text, 14 above the
## seated head, as they did; its foot follows, 17 below the seat.
const SELECTION_AT := Vector2(0, 13)
## The click target of each side, as scenes/world/station.tscn places it: a far
## worker's labels float above the head, a near worker's sit below the chair.
## The far one reaches up to -70, over the badge (drawn at x 18..34, y -69..-53:
## its pivot is its foot), except while the bubble shows: then it stops at the
## plate's top row (-53), FAR_UNDER_BUBBLE, and the bubble's own rectangle,
## which the badge's area lies in, answers above it. Never both under a point.
const TARGET_OF := {"far": ^"Target/Far", "near": ^"Target/Near"}
const FAR_AT := Vector2(0, -31)
const FAR_UNDER_BUBBLE_AT := Vector2(0, -22.5)
const FAR_UNDER_BUBBLE_SIZE := Vector2(56, 61)
## The bubble over a blocked worker (OfficeBubble), by its top-left corner
## relative to the seat. 60 wide because the columns are 64 apart
## (OfficeTable.measure()), so two neighbours' bubbles never meet; 28 tall
## because everything a station draws stays inside the table's render_rect
## (table-local y -150..72), which the floor's decor is planned around. The far
## one therefore spans table-local -150..-122, right under that top edge, and
## the far seat's rectangle starts below it while it shows; the near one spans
## -58..-30, 2 clear of the near rectangle's top (-28) and of the far one's foot
## (-60), over the divider and the near laptop, above the near worker's head.
## The far badge lies over the far bubble's right end (bubble x 48..64, y
## 13..28): the badge is drawn above it (Overlay order) and the bubble keeps
## nothing there (OfficeBubble's layout).
const BUBBLE_SIZE := OfficeBubble.SIZE
const BUBBLE_AT := {"far": Vector2(-30, -82), "near": Vector2(-30, -80)}
## The bubble's click rectangle (scenes/world/station.tscn), 60 by 28: _place()
## lays it over the bubble.
const BUBBLE_TARGET := ^"Target/Bubble"
## Over a worker resting away (the pantry), relative to where they stand: the
## badge right over the head; no plate: who is who is their coat, and a click on
## them opens their card (the Away rectangle, scenes/world/station.tscn, 38 wide).
const AWAY_BADGE_AT := Vector2(0, -47)
const AWAY_SELECTION_AT := Vector2(0, 17)
const AWAY_TARGET := ^"Target/Away"
## The Away rectangle's centre over the feet: its foot 2 below them.
const AWAY_TARGET_AT := Vector2(0, -26)

## The far rectangle while the bubble shows (FAR_UNDER_BUBBLE_SIZE), made once
## and shared: a shape resource of the scene is shared by every station.
static var _far_under_bubble: RectangleShape2D

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
## The far rectangle as the scene has it, kept when the bubble swaps it out.
var _far_shape: Shape2D
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
	pen.style(plate, 10, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	plate.size = PLATE_SIZE
	var lens: Label = $Overlay/Lens
	pen.style(lens, 10, ArtContract.INK, HORIZONTAL_ALIGNMENT_CENTER)
	var mark := art.selection_mark()
	var selection: Sprite2D = $Overlay/Selection
	art.dress(selection, art.sprite_texture(mark), mark.pivot)
	bubble().dress(pen)
	var badge: StatusBadge = $Overlay/Badge
	badge.bubble = bubble()
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
	# What only a state draws at a seat: the bubble over a blocked agent, the
	# paper beside a done one's laptop. A pane still launching says nothing about
	# its agent yet, unless herdr already says blocked: a start that asks at once
	# is a blocked agent (blocked takes precedence; the caller passes PaneModel.launching()).
	# A shell has no agent. Set before _place(), which enables
	# the bubble's rectangle only while it shows.
	var agent := not starting and not provider.is_empty()
	bubble().visible = agent and state == ArtContract.STATE_BLOCKED
	if not bubble().visible:
		bubble().clear()
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
	plate.visible = true
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
	bubble().visible = false
	bubble().clear()
	_drop_actor()
	var plate: Label = $Overlay/Plate
	plate.visible = false
	plate.text = ""
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
## shell, a dropped machine: nothing), and the bubble draws none of itself
## meanwhile (OfficeBubble.set_lensed()). Nothing is rebuilt: the text only
## when it changes, the line's visibility, the bubble's parts.
func show_lens(held: bool, text: String) -> void:
	var line: Label = $Overlay/Lens
	if held and line.text != text:
		line.text = text
	line.visible = held and not vacant and not text.is_empty()
	bubble().set_lensed(held)


func select(selected: bool) -> void:
	var mark: Sprite2D = $Overlay/Selection
	mark.visible = selected and not vacant


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


## The bubble over this seat (OfficeBubble), shown only while its agent is blocked.
func bubble() -> OfficeBubble:
	return $Overlay/Bubble


## Where the bubble is drawn, in global coordinates; an empty rectangle while
## it is hidden. What reveal() and the question reader look at.
func bubble_rect() -> Rect2:
	var shown := bubble()
	if not shown.visible:
		return Rect2()
	return Rect2(shown.global_position, BUBBLE_SIZE)


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
## the bubble's asks, any other picks.
func _on_target_input_event(_viewport: Node, event: InputEvent, shape_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var click: InputEventMouseButton = event
	if click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var target: Area2D = $Target
	var hit := target.shape_owner_get_owner(target.shape_find_owner(shape_index))
	if hit == get_node(BUBBLE_TARGET):
		asked.emit(pane_key, click.position)
	else:
		picked.emit(pane_key, click.position)


## The pointer entered or left one of this seat's rectangles: only the
## bubble's is anybody's business.
func _on_target_mouse_shape_entered(shape_index: int) -> void:
	if _is_bubble_shape(shape_index):
		bubble_hovered.emit(pane_key, true)


func _on_target_mouse_shape_exited(shape_index: int) -> void:
	if _is_bubble_shape(shape_index):
		bubble_hovered.emit(pane_key, false)


func _is_bubble_shape(shape_index: int) -> bool:
	var target: Area2D = $Target
	return target.shape_owner_get_owner(target.shape_find_owner(shape_index)) == get_node(BUBBLE_TARGET)


func _pickable(can_pick: bool) -> void:
	var target: Area2D = $Target
	target.input_pickable = can_pick


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
## (the other side's never), the bubble's while it shows, and while away the
## Away one too.
func _place() -> void:
	var away_here := away()
	var at := rest_position()
	var plate: Label = $Overlay/Plate
	plate.position = at + PLATE_AT[side]
	plate.visible = not vacant and not away_here
	var badge: StatusBadge = $Overlay/Badge
	var selection: Sprite2D = $Overlay/Selection
	var lens: Label = $Overlay/Lens
	if away_here:
		badge.position = at + AWAY_BADGE_AT
		selection.position = at + AWAY_SELECTION_AT
		lens.position = at + AWAY_LENS_AT
		lens.size = AWAY_LENS_SIZE
	else:
		badge.position = at + BADGE_AT[side]
		selection.position = at + SELECTION_AT
		lens.position = at + LENS_AT[side]
		lens.size = LENS_SIZE[side]
	var shown := bubble()
	var bubble_at: Vector2 = BUBBLE_AT[side]
	shown.position = bubble_at
	var bubble_target: CollisionShape2D = get_node(BUBBLE_TARGET)
	bubble_target.position = bubble_at + BUBBLE_SIZE / 2.0
	bubble_target.disabled = vacant or not shown.visible
	for each: String in OfficeTable.SIDES:
		_target_of(each).disabled = each != side
	# The far rectangle gives the bubble the badge's rows while the bubble shows.
	var far: CollisionShape2D = _target_of("far")
	if _far_shape == null:
		_far_shape = far.shape
	var under := side == "far" and not bubble_target.disabled
	if under and _far_under_bubble == null:
		_far_under_bubble = RectangleShape2D.new()
		_far_under_bubble.size = FAR_UNDER_BUBBLE_SIZE
	far.shape = _far_under_bubble if under else _far_shape
	far.position = FAR_UNDER_BUBBLE_AT if under else FAR_AT
	var away_target: CollisionShape2D = get_node(AWAY_TARGET)
	away_target.disabled = not away_here
	away_target.position = at + AWAY_TARGET_AT


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
