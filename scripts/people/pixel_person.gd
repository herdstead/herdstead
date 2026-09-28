class_name PixelPerson
extends CharacterBody2D
## One pixel person: scenes/people/pixel_person.tscn, everyone the office draws:
## the worker at a station (OfficeStation), the agent card's portrait, the
## showroom's bystanders and the Avatar Studio's preview.
##
## The origin is the feet. Six layer sprites (Legs, Top, Body, Glasses, Hair,
## Headwear, bottom to top) each show a whole strip of the PixelPeople family,
## or nothing when the look's slot is `none` (a null texture: no draw call);
## the one AnimationPlayer keys every `frame` from the library the family builds
## once, so the layers cannot drift apart and nothing about them runs per frame.
## A new look, a new facing or a new state only changes properties of the same
## nodes: textures, flip_h and the playing track.
##
## What the person wears is resolved once per configure() (PixelPeople.look_for):
## the pack's and the provider's defaults, the user's pins, and — for a worker
## at a seat — the pane's own variation, keyed by vary_by(). Never by state: a
## new state only changes the track.
##
## Facing is front, back, left or right. A strip is drawn for front, back and
## one side; the other side is that strip mirrored with flip_h on every layer.
## A track that does not draw the facing asked for shows its front (desk tracks
## have no side, stand_blocked and drink no back), and turning mid-track keeps
## the track's clock: one frame index is the same moment in every strip.
##
## Standing, the Feet shape collides with furniture, so move_and_slide() works
## as soon as someone walks. Seated, the person is snapped to a seat and its
## Feet are off: a chair is not an obstacle to the person in it.

var people: PixelPeople
## The herdr provider as asked for (may be unknown to the catalog).
var provider := ""
## The look in effect: clothes, pose (stand/desk) and front/back orientation.
var look := AvatarLook.new()
## The way the person faces: front, back, left or right.
var facing := PixelPeople.FRONT
## The semantic animation asked for with play_state(); empty while a track was
## asked for by name.
var animation := &""
## The track playing or held, whoever asked for it.
var track := &""
## The stable key this person's variation is picked by (a pane's
## HerdrFleet.pane_key); empty: no variation, the defaults and pins only.
var variation_key := ""

@onready var _player: AnimationPlayer = $AnimationPlayer


## Every frame stays inside this canvas, placed on the feet, whichever way the
## person faces: the pivot is the frame's centre, so the mirror of a frame
## covers the same rectangle. There are no runtime layer transforms.
static func drawing_rect(family: PixelPeople) -> Rect2:
	return Rect2(-family.pivot, Vector2(family.frame_size))


## Read the collider from the prefab, including its offset from the feet.
## Layout validation must not keep a second copy of its dimensions.
static func footprint() -> Rect2:
	var scene: PackedScene = load("res://scenes/people/pixel_person.tscn")
	var instance: PixelPerson = scene.instantiate()
	var shape: CollisionShape2D = instance.get_node("Feet")
	var rectangle: RectangleShape2D = shape.shape
	var result := Rect2(shape.position - rectangle.size / 2.0, rectangle.size)
	instance.free()
	return result


## Dress the person for `who` from `family`. `choices` may name a pose
## (context, orientation), hair and outfit; a pose it leaves empty keeps the
## person's own, clothes it leaves empty come from the catalog and the user's
## saved look. An orientation it names is also the way the person faces.
## Swaps textures on the existing layers.
func configure(family: PixelPeople, who: String, choices: AvatarLook = null) -> void:
	people = family
	provider = who
	# The pose is the person's own state: a new provider at the same seat stays
	# seated and facing the same way unless the caller says otherwise.
	var wanted := AvatarLook.facing(look.context, look.orientation)
	wanted.override_with(choices)
	look = people.look_for(who, wanted, variation_key)
	if choices != null and not choices.orientation.is_empty():
		facing = look.orientation
	var player := _animation_player()
	var library := people.animation_library()
	if not player.has_animation_library(&"") or player.get_animation_library(&"") != library:
		if player.has_animation_library(&""):
			player.remove_animation_library(&"")
		player.add_animation_library(&"", library)
	if not animation.is_empty():
		play_state(animation)
	else:
		_dress()


## Pick this person's variation by `key` (the pane they stand for), from the
## next configure() on. Setting the same key again changes nothing.
func vary_by(key: String) -> void:
	variation_key = key


## Show a semantic animation (idle, working, blocked, starting, done, unknown)
## through the family's state_tracks for the current pose.
func play_state(semantic: StringName) -> void:
	animation = semantic
	_play(people.track(look.context, semantic))


## Show a track by its own name (walk, carry_walk, drink ...), whatever the
## state. The same track keeps playing from where it is; a paused person stays
## paused and shows the new track's first frame.
func play_track(id: StringName) -> void:
	animation = &""
	_play(id)


## Hold frame `index` of track `id`, paused: a still for a review sheet or a
## portrait.
func hold(id: StringName, index: int) -> void:
	play_track(id)
	var player := _animation_player()
	if not people.tracks.has(id):
		return
	player.pause()
	player.seek(people.tracks[id].starts_at(index), true)


func pause() -> void:
	_animation_player().pause()


func play() -> void:
	var player := _animation_player()
	if player.assigned_animation != &"":
		player.play()


func is_playing() -> bool:
	return _animation_player().is_playing()


## Play every track `rate` times as fast as the family times it: a walker's
## feet keep time with how fast they cross the floor. 1 is the family's own.
func pace(rate: float) -> void:
	_animation_player().speed_scale = rate


## How many times its own speed the playing track runs (see pace()).
func paced() -> float:
	return _animation_player().speed_scale


## Turn to front, back, left or right; side is the way the side strip is drawn.
## Front and back are also the look's orientation. Only textures and flip_h
## change: the track and its clock carry on.
func face(wanted: StringName) -> void:
	if not [PixelPeople.FRONT, PixelPeople.BACK, PixelPeople.SIDE, PixelPeople.LEFT, PixelPeople.RIGHT].has(wanted):
		push_error("PixelPerson %s: no facing %s" % [provider, wanted])
		return
	facing = wanted
	if wanted == PixelPeople.SIDE:
		facing = people.side_faces if people != null else PixelPeople.RIGHT
	if wanted == PixelPeople.FRONT or wanted == PixelPeople.BACK:
		look.orientation = wanted
	_dress()


## The strip facing shown now: the one asked for, unless the playing track does
## not draw it (then its front).
func shown_facing() -> StringName:
	var drawn := PixelPeople.SIDE if facing == PixelPeople.LEFT or facing == PixelPeople.RIGHT else facing
	if people == null or not people.tracks.has(track):
		return drawn
	return people.tracks[track].shown(drawn)


## Whether the shown strip is mirrored: the side, facing the other way from how
## it is drawn.
func mirrored() -> bool:
	return people != null and shown_facing() == PixelPeople.SIDE and facing != people.side_faces


## Sit on `seat`: snap to it, stop colliding, take the desk pose facing the way
## the look says (a seated person faces the desk, never sideways).
func sit(seat: Marker2D = null) -> void:
	var feet: CollisionShape2D = $Feet
	feet.disabled = true
	if seat != null and is_inside_tree() and seat.is_inside_tree():
		global_position = seat.global_position
	facing = look.orientation if look.orientation == AvatarLook.BACK else PixelPeople.FRONT
	if look.context != AvatarLook.DESK:
		configure(people, provider, AvatarLook.facing(AvatarLook.DESK, &""))
	else:
		_dress()


## Stand up where the seat was: collide again, take the standing pose.
func stand_up() -> void:
	var feet: CollisionShape2D = $Feet
	feet.disabled = false
	if look.context != AvatarLook.STAND:
		configure(people, provider, AvatarLook.facing(AvatarLook.STAND, &""))


## Play `id`, then dress for it: a track that does not draw the facing shows
## its front. A paused player stays paused on the new track's first frame.
func _play(id: StringName) -> void:
	if not people.tracks.has(id):
		push_error("PixelPerson %s: the family has no track %s" % [provider, id])
		return
	track = id
	_dress()
	var player := _animation_player()
	if player.assigned_animation == id:
		return
	var was_paused := player.assigned_animation != &"" and not player.is_playing()
	player.play(id)
	if was_paused:
		# A frozen floor stays frozen, whatever its people were last told; the
		# seek applies the new track's first frame, which a paused player won't.
		player.pause()
		player.seek(0.0, true)


## Put the strip of the shown facing on every layer, mirrored or not. Only
## properties of the existing sprites change.
func _dress() -> void:
	if people == null:
		return
	var strip := shown_facing()
	var flip := mirrored()
	for layer in PixelPeople.LAYERS:
		var sprite: Sprite2D = get_node(PixelPeople.SPRITES[layer])
		var image := people.layer_texture(layer, look, strip)
		# Every layer goes through the family's dress(), an empty one too, so a
		# layer a later look fills is already sampled the family's way.
		if sprite.texture != image or sprite.texture_filter != people.filter:
			people.dress(sprite, image, people.pivot)
		sprite.hframes = people.columns
		sprite.vframes = 1
		sprite.flip_h = flip


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		collision_layer = OfficeWorld.ACTORS
		collision_mask = OfficeWorld.FURNITURE


## Callable before the person enters the tree, when @onready has not run.
func _animation_player() -> AnimationPlayer:
	return _player if _player != null else $AnimationPlayer
