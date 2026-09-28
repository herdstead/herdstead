class_name FramePacer
extends Node
## Caps the live office's frame rate at what it needs right now. Uncapped, the
## office draws at the display's refresh rate (120 Hz on a ProMotion screen)
## while nothing on it moves faster than a worker's sprite frames, and it is
## meant to sit in a corner of the screen all day (`--always-on-top`).
##
## Someone using the office gets INTERACTING_FPS: an input event within
## INTERACTION_MSEC. At rest a
## focused window gets IDLE_FPS, one in the background UNFOCUSED_FPS, and a
## minimized one MINIMIZED_FPS; see choose(). Input is only watched, never
## consumed. Engine.max_fps is written only when the choice changes.
## `OS.low_processor_usage_mode` is no substitute: it only saves anything while
## nothing redraws, and the workers animate all the time.
##
## `--fps=<n>` pins the rate and `--fps=0` leaves the engine's alone
## (uncapped); a Godot `--max-fps` given without `--fps=` is
## left alone too. Under `--headless` there is no window: the pacer keeps its
## bookkeeping, which tests read through wanted_fps(), but never writes
## Engine.max_fps and never asks for the window mode, which a headless display
## reports as minimized. Nor does it ever lose focus there: a test says the
## window is minimized or in the background through note_minimized() and
## note_focused(), the same seams the window's own poll and notifications use.

const INTERACTING_FPS := 60
const IDLE_FPS := 30
const UNFOCUSED_FPS := 12
## The lowest rate that keeps time real. Below 7.5 fps the engine's at most 8
## physics steps a frame (at 60 Hz) cannot keep up, and it slows the process
## delta to match: at 2 fps every timer counted in delta (request timeouts, the
## snapshot interval, the machine list poll, reconnect backoffs) ran about 3.75
## times slower than the clock (measured: a 5 s timer took 19 s). 8 keeps them
## on time while nothing is on screen.
const MINIMIZED_FPS := 8
## How long after its last input event the office still counts as in use.
const INTERACTION_MSEC := 1500
## How often the window mode is asked for. A minimized window asks on every one
## of its few frames, so it comes back to speed as soon as it is restored.
const POLL_SECONDS := 1.0
## What requested() answers when the pacer is to choose the rate itself.
const ADAPTIVE := -1
## What requested() answers when the pacer is to leave Engine.max_fps alone.
const HANDS_OFF := 0

## ADAPTIVE, HANDS_OFF or the rate `--fps=` pinned.
var _requested := ADAPTIVE
var _headless := false
var _focused := true
var _minimized := false
## Time.get_ticks_msec() of the last input event, -1 before the first.
var _last_input_msec := -1
var _poll_left := 0.0
## What was last written to Engine.max_fps, -1 before the first write.
var _applied := -1


func _init(user_args: PackedStringArray) -> void:
	name = "FramePacer"
	_requested = requested(user_args, Engine.max_fps)


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	# Whatever the rate, OfficeAlerts asks whether the window has focus.
	if not _headless:
		note_focused(DisplayServer.window_is_focused())
	if _requested != ADAPTIVE:
		set_process(false)
		set_process_input(false)
		if _requested != HANDS_OFF:
			_apply(_requested)
		return
	if not _headless:
		_poll_window()


## What the command line asks of the pacer: a pinned rate, HANDS_OFF or
## ADAPTIVE. `--fps=<n>` decides when it is given, a malformed one is warned
## about and ignored, and without one a cap the engine already has (Godot's
## `--max-fps`, `engine_cap` here) is kept.
static func requested(user_args: PackedStringArray, engine_cap: int) -> int:
	for argument in user_args:
		if not argument.begins_with("--fps="):
			continue
		var value := argument.trim_prefix("--fps=")
		if value.is_valid_int() and value.to_int() >= 0:
			return value.to_int()
		push_warning("Ignoring %s: --fps= takes whole frames per second, or 0 for no pacing" % argument)
	return HANDS_OFF if engine_cap > 0 else ADAPTIVE


## The rate for a window in this state. Minimized beats everything, since none
## of it is on screen. Someone using the office gets the full rate even while
## the window is in the background: a wheel or trackpad scroll reaches a window
## that is not focused.
static func choose(minimized: bool, focused: bool, interacting: bool) -> int:
	if minimized:
		return MINIMIZED_FPS
	if interacting:
		return INTERACTING_FPS
	return IDLE_FPS if focused else UNFOCUSED_FPS


## Whether the office is in use at `now_msec`: the last input event (-1 for
## none yet) came at most INTERACTION_MSEC before.
static func is_interacting(last_input_msec: int, now_msec: int) -> bool:
	return last_input_msec >= 0 and now_msec - last_input_msec <= INTERACTION_MSEC


## Whether the window is minimized, as the pacer last saw it. The agent card's
## terminal preview stops reading while it is, and asks here rather than
## polling the window a second time.
func is_minimized() -> bool:
	return _minimized


## What the window mode says, minimized or not: the pacer's own poll reports
## through this, and so can a headless run, which has no window to poll.
func note_minimized(minimized: bool) -> void:
	_minimized = minimized


## Whether the viewer has the office in front of them: the app has focus and
## its window is not minimized. OfficeAlerts asks this before it rings, and
## rings for nothing while it is true.
func is_focused() -> bool:
	return _focused and not _minimized


## What the app focus says: the engine's focus notifications and the first look
## at the window report through this. A headless run is always focused (it has
## no window to lose focus), so a test says otherwise here.
func note_focused(focused: bool) -> void:
	_focused = focused


## The rate the pacer asks for now: the pinned one, 0 when it keeps its hands
## off, and otherwise what choose() makes of the window and its input.
func wanted_fps() -> int:
	if _requested != ADAPTIVE:
		return _requested
	return choose(_minimized, _focused, is_interacting(_last_input_msec, Time.get_ticks_msec()))


func _process(delta: float) -> void:
	if _headless:
		return
	_poll_left -= delta
	if _minimized or _poll_left <= 0.0:
		_poll_window()
	var fps := wanted_fps()
	if fps != _applied:
		_apply(fps)


## Buttons, wheel notches, keys, drags and trackpad gestures. A pointer merely
## passing over the window is nobody using it.
func _input(event: InputEvent) -> void:
	var hovering := event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask == 0
	if hovering:
		return
	if (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventMouseMotion
		or event is InputEventGesture
	):
		_last_input_msec = Time.get_ticks_msec()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		note_focused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		note_focused(false)


func _poll_window() -> void:
	_poll_left = POLL_SECONDS
	note_minimized(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)


func _apply(fps: int) -> void:
	_applied = fps
	if not _headless:
		Engine.max_fps = fps
