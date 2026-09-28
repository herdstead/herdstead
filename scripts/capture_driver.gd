class_name CaptureDriver
extends RefCounted
## `--capture=<png>` for the office, the showroom, the pixel people showroom
## and the Avatar Studio: wait until the scene has what it waits
## for, then `--wait=` seconds more, save the next frame the viewport draws, and
## quit. Exit 0 and a `CAPTURE_OK: <path>` line when the picture was written; an
## error and exit 1 when it was not, so tools/capture.sh never collects a
## picture that does not exist. A window the OS made smaller than the run
## asked for is an error too (`window_problem()`), never a smaller picture. Windowed only: a headless viewport draws nothing worth saving.

## How long a scene may take to have what it waits for before the capture takes
## whatever is on screen, so a dead socket cannot hang a capture forever.
const READY_TIMEOUT := 8.0
const READY_POLL := 0.1
## One last pause before the frame that is saved.
const SETTLE := 0.2


## Capture `scene` to `--capture=`. `what` names it in an error ("office",
## "preview", "people showroom", "Avatar Studio"). `ready`, when given,
## answers whether the scene has what it waits for yet; `problem`, when given,
## answers why there is nothing worth capturing, and empty while there is.
static func run(scene: Node, args: AppArgs, what: String, ready := Callable(), problem := Callable()) -> void:
	var tree := scene.get_tree()
	var target := args.text("capture")
	if ready.is_valid():
		var waited := 0.0
		var done := false
		while not done and waited < READY_TIMEOUT:
			await tree.create_timer(READY_POLL).timeout
			waited += READY_POLL
			done = ready.call()
	var dwell := args.decimal("wait", 0.0)
	if dwell > 0.0:
		await tree.create_timer(dwell).timeout
	await tree.create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var clamped := window_problem(scene.get_window(), args.text("window"))
	if not clamped.is_empty():
		# A smaller window than the run asked for shows less, or a lower scale.
		push_error("No %s capture: %s" % [what, clamped])
		tree.quit(1)
		return
	if problem.is_valid():
		var why: String = problem.call()
		if not why.is_empty():
			# A picture of something that was never built is not a capture.
			push_error("No %s capture: %s" % [what, why])
			tree.quit(1)
			return
	var error := scene.get_viewport().get_texture().get_image().save_png(target)
	if error != OK:
		# Not an assert: --export-release strips those, and a capture that was
		# never written must not report success to whoever is collecting it.
		push_error("Cannot save the %s capture to %s: %s" % [what, target, error_string(error)])
		tree.quit(1)
		return
	print("CAPTURE_OK: " + target)
	tree.quit()


## The window size a run asked for: `--window=WxH`, which tools/capture.sh
## copies from the engine's `--resolution` (the engine keeps that one to
## itself), or the project's own window size when there is none. ZERO when
## `--window=` is not a size.
static func asked_window(text: String) -> Vector2i:
	if text.is_empty():
		var width: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
		var height: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
		if width <= 0 or height <= 0:
			width = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
			height = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
		return Vector2i(width, height)
	var parts := text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


## Why `window` is not the window the run asked for (`asked_window(text)`),
## empty when it is: a display smaller than the window asked makes the OS
## shrink it, and a capture of the smaller one shows less, maybe at a lower
## scale: not the picture the run is for.
static func window_problem(window: Window, text: String) -> String:
	var asked := asked_window(text)
	if asked == Vector2i.ZERO:
		return "--window=%s is not a size" % text
	if window.size == asked:
		return ""
	return "asked for a %dx%d window, the OS made it %dx%d" % [asked.x, asked.y, window.size.x, window.size.y]
