class_name OfficeWindow
## The live office's window: whether it fills the screen, and the top bar
## standing in for its title bar. The office asks once in _ready() and again on
## every resize (OfficeScene.fit_window()); nothing else touches the window's
## mode or its buttons.


## Whether this run's window fills the screen: maximized, so the menu bar and
## the Dock stay, with the top bar standing in for the title bar. A normal run
## does; `--window=plain` keeps the plain window of `window_width_override`.
## A capture, a measurement (`--window=plain` in tools/perf.sh) and a headless
## run never do: their windows are the size they asked for. Nor does
## `--always-on-top`: a corner view kept over everything must not cover it all.
static func fills_screen(args: AppArgs, headless: bool) -> bool:
	if headless or args.has("capture") or args.flag("always-on-top"):
		return false
	match args.text("window", "fill"):
		"fill":
			return true
		"plain":
			return false
		var other:
			push_warning("--window takes fill or plain, not %s; filling the screen" % other)
			return true


## Maximize `window` and, where the system can (macOS), draw the office under
## a see-through title bar: the window's own buttons stay, over the top bar's
## left end, and the bar drags the window (OfficeBar.moves_window).
static func fill(window: Window, bar: OfficeBar) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_EXTEND_TO_TITLE):
		window.extend_to_title = true
		bar.moves_window = true
	window.mode = Window.MODE_MAXIMIZED


## The room the window's own buttons take at the bar's left end, in the HUD's
## pixels (the system gives it in the window's); 0 in a plain window. The
## buttons are first centred on the bar, `bar_height` HUD pixels tall, as far
## from the left edge as from the top (the system's offset is the first
## button's centre, in the window's pixels), so they follow it through a zoom.
static func title_gap(window: Window, bar_height: float) -> float:
	if not window.extend_to_title:
		return 0.0
	var centre := roundi(bar_height * window.content_scale_factor / 2.0)
	DisplayServer.window_set_window_buttons_offset(Vector2i(centre, centre), window.get_window_id())
	var margins := DisplayServer.window_get_safe_title_margins(window.get_window_id())
	return ceilf(margins.x / window.content_scale_factor)
