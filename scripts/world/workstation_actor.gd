class_name WorkstationActor
extends Node2D
## One complete authored image at a time: person, chair, desk and monitors.
## AnimationPlayer changes only Body:frame; no rig, outfit or runtime cutting.
## A state refresh is idempotent, including a completed one-shot. Pausing is a
## separate channel so reconnecting cannot replay a completion nod.

var art: WorkstationArt
var provider := ""
var animation := &""
var track: StringName:
	get:
		return _player().assigned_animation
var _paused := false
var _resume := false


func configure(family: WorkstationArt, who: String) -> void:
	provider = who
	if family == art:
		return
	art = family
	var player := _player()
	player.stop(true)
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", art.library)
	animation = &""
	show_empty()


func show_empty() -> void:
	# A repeated empty refresh must not apply an old atlas key to a 1x1 grid.
	_player().stop(true)
	animation = &""
	_resume = false
	var body: Sprite2D = $Body
	body.frame = 0
	body.hframes = 1
	body.vframes = 1
	art.dress(body, art.empty_texture(), art.pivot)


## Semantic state, not the old rig's animation mapping (done really nods).
func play_state(state: StringName) -> void:
	var wanted := state if state in [&"working", &"idle", &"blocked", &"done", &"starting"] else &"unknown"
	if animation == wanted:
		return
	var previous := animation
	animation = wanted
	var body: Sprite2D = $Body
	art.dress(body, art.sheet_texture(), art.pivot)
	body.hframes = art.columns
	body.vframes = art.rows
	if wanted == &"blocked":
		_start(&"blocked_enter")
	elif previous == &"blocked":
		_start(&"blocked_exit")
	elif previous.is_empty() or track != &"blocked_exit":
		_start(wanted)


func pause() -> void:
	if _paused:
		return
	_paused = true
	_resume = _player().is_playing()
	_player().pause()


func play() -> void:
	if not _paused:
		return
	_paused = false
	if _resume:
		_player().play()
	_resume = false


func is_playing() -> bool:
	return _player().is_playing()


func _start(clip: StringName) -> void:
	var player := _player()
	player.play(clip)
	player.advance(0.0)
	if _paused:
		_resume = true
		player.pause()


func _finished(clip: StringName) -> void:
	if clip == &"blocked_enter" and animation == &"blocked":
		_start(&"blocked")
	elif clip == &"blocked_exit":
		_start(&"blocked_enter" if animation == &"blocked" else animation)


func _player() -> AnimationPlayer:
	return $AnimationPlayer
