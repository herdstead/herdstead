class_name OfficeScene
extends Node2D
## The live office: every herdr machine is one open-plan map, each workspace a
## zone on it, each tab a pod of desks, each pane a seat. One machine's map is
## drawn at a time; the SPACES rail on the left lists every zone of every
## machine and who needs a human: a heading shows its machine's map, and a row
## pans to its zone.
## This scene sends herdr nothing itself: the agent card's terminal preview and
## its one write go through HerdrFleet to HerdrCommands, which `--read-only`
## never constructs.
##
## The composition root. Every refresh the fleet's snapshots become one
## OfficeFrame (OfficeProjection); the navigator decides from it what the viewer
## sees (OfficeNavigator); the plan cache lays that machine's map out (FloorPlanCache);
## the floor view, the plate and the HUD draw it; the camera shows it. This
## scene wires them together and owns the art pack; it reads no snapshot field.
##
## Pane ids repeat across machines, so a desk is known by its machine key and
## pane id together (HerdrFleet.pane_key), and a zone by its machine key and
## workspace id. Which map is shown, and where it is panned, is the viewer's
## state; the fleet never learns about it.

## A refresh for new data from the fleet has ended: the one refresh the frame's
## events were coalesced into (_queue_refresh()), or a click, resize or other
## synchronous refresh that took them in first. tools/perf_probe.gd times it.
signal data_refreshed

## Where the world's light comes from: the local clock, or held at day or night.
enum LightMode { CLOCK, DAY, NIGHT }

## Runtime packs live at res://assets/<id>/manifest.json; `--pack=` picks one.
const PACK_ROOT := "res://assets"
## The pack this build ships, and the one the office falls back to when the
## chosen theme cannot be drawn.
const DEFAULT_MANIFEST := PACK_ROOT + "/daylight/manifest.json"
## Where the last picked theme is remembered between runs.
const SETTINGS_PATH := "user://herdstead.cfg"
## The bar, the SPACES rail and the inspector, laid out in their own scenes; where
## they stand is what leaves the world its room (see OfficeCamera.free_rect()).
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PLATE_SCENE := preload("res://scenes/world/machine_plate.tscn")
## How often, in seconds, the office tells the question reader which chips are on screen.
const QUESTION_WATCH_SECONDS := 0.25
## Smallest viewport the bar and inspector still fit in.
const MIN_SCREEN := Vector2i(480, 320)
## Zoom only takes even values from 2 up, so a density-2 texel always covers
## whole screen pixels. 8 shows a 256px-per-tile pack 1:1 on a large or hiDPI window.
const ZOOM_MIN := 2
const ZOOM_STEP := 2
const ZOOM_MAX := 8
## The machine plate's band above the map.
const PLATE_HEIGHT := 32
## How often the open overview is drawn again while nothing changes: its FOR
## and BLOCKED times and the timelines' now edge move with the clock.
const OVERVIEW_TICK_SECONDS := 1.0
## How often the open strategic view is shown again while nothing changes: a
## blocked square's wait moves with the clock (it is drawn again only when a
## wait it writes did move).
const STRATEGIC_TICK_SECONDS := 1.0
## How long after a split from the card the office waits for a snapshot to show
## the new pane and picks it; after that it stops waiting and the card says so.
const PENDING_PICK_MSEC := 10000

@export_file("*.json") var manifest_path := DEFAULT_MANIFEST
## PENDING_PICK_MSEC, for this office (a test waits less).
var pending_pick_msec := PENDING_PICK_MSEC

var art: ArtPack
var pen: OfficeDraw
## Every herdr machine shown, Local first; the only way this scene reaches herdr.
var fleet: HerdrFleet
var attention: OfficeAttention
## Rings (the Dock, and a chime when asked for) for an agent that starts
## waiting while the office is in the background.
var alerts: OfficeAlerts
## Whether `L` is held: the world as a data view (OfficeLens, _show_lens()).
var lens: OfficeLens
## Local, session-scoped records. Viewing or hiding one never changes herdr.
var attention_store := AttentionStore.new()
## The agent list's History lines, built again only when the log or the panes change.
var history_cache := AgentHistory.Cache.new()
## The screen-space HUD; built in _init(), so the world can ask it for its room
## before anything is in the tree.
var hud: OfficeHud
var world: Node2D
var camera: OfficeCamera
## Caps the frame rate; the agent card asks it whether the window is minimized.
var pacer: FramePacer
## Reads what each blocked agent on screen is asking, for the chip over them.
var questions: OfficeQuestionReader
## Every runtime pack found at startup, sorted by pack directory (the pack id).
var themes := PackedStringArray()
## True while no machine at all is live; the shown map also dims on its own.
var stale := true
## Where the light comes from: CLOCK follows the local time (DayLight), DAY and
## NIGHT hold it (`--light=day|night`; a capture holds the day unless it asks,
## and a test office starts at DAY).
var light_mode := LightMode.CLOCK
## Local minutes after midnight; a test hands in its own.
var clock: Callable = _local_minutes
## How far into night the world is drawn now: 0 by day, 1 by night (DayLight).
var night := 0.0
## Wanted screen pixels per world unit, always even; `-` and `=` step it by 2.
var zoom := 2
## Whether this office may fill the screen at all; a test double, whose window
## is the suite's or a capture's, turns it off.
var may_fill_screen := true
## The window fills the screen with the bar as its title bar (OfficeWindow).
var filled := false
## Whether a theme switch (and the list's view, and the chime switch) is
## written to the user's settings. A capture is a screenshot, not a session,
## and a test is neither: both turn this off.
var remember_theme := true
## The settings file those are kept in: SETTINGS_PATH, unless a test that turns
## remember_theme on points it into its own work directory before the office is
## in the tree.
var settings_path := SETTINGS_PATH
## What the viewer looks at and has asked for, and every decision about it.
var navigator := OfficeNavigator.new()
## Every machine's map plan and what was last tried for it, for the whole run.
var plans := FloorPlanCache.new()
## The last refresh's projection of every machine.
var frame := OfficeFrame.new()
## The shown map as drawn: its shell, zones, pods, seats and furniture.
var floor_view: OfficeFloorView
## The shown machine's plate, above its map.
var plate: OfficeMachinePlate
## What the world was built for: the shown machine and the pack. Nothing else
## replaces it (a workspace coming or going is a zone of the same world);
## everything else updates it in place.
var world_model := ""
## Composite pane key (see HerdrFleet.pane_key) the viewer picked. Empty means
## "follow what herdr has focused". The navigator's, for callers of the office;
## setting it picks whatever terminal that pane holds now, like a click.
var picked_key: String:
	get:
		return navigator.picked_key
	set(value):
		var pane := frame.pane(value)
		navigator.pick_desk(value, "" if pane == null else pane.identity_key())

var _paper: ColorRect
## The world's night tint (DayLight): a CanvasModulate on the world's canvas, so
## the HUD's own layer keeps its colours; the paper backdrop is tinted apart.
var _night_light: CanvasModulate
## T turned the light over while it follows the clock; it holds until the
## clock's own day or night turns (_flipped_at_night is which one it turned from).
var _light_flipped := false
var _flipped_at_night := false
## Until the clock is read again.
var _light_left := 0.0
## The last live-machine count the bar was written with, to write it again
## when only the light changed.
var _bar_live := 0
## The machine the world was built for.
var _world_machine := ""
## The shown map's drawing and its plate band, which the pan is clamped to.
var _content_size := Vector2.ZERO
var _inbox_left := 0.0
## Until the chips on screen are looked at again: a pan moves them without a refresh.
var _questions_left := 0.0
## The tooltip over a blocked agent's chip, and what the question reader is told.
var _tips: OfficeQuestionTips
## Machine key -> the state starts last projected while it was live, by pane key
## and terminal identity: what a stale machine's panes are ranked by, since its
## client forgets every start the moment it drops (see _stamp_starts()).
var _live_starts: Dictionary[String, Dictionary] = {}
## A refresh is under way: a HUD panel that moves inside it (the window's own
## fit) is laid out by that refresh, not by a second one nested in it.
var _refreshing := false
## The fleet has changed since the last refresh: one refresh is queued for the
## end of the frame (_queue_refresh()), and any refresh before it takes this in.
var _data_pending := false
## The identity the pick last carried to from a start's shell
## (_carry_pick_to_started()), and whether it had no session yet.
var _carried_pick := ""
var _carried_sessionless := false
## Draws the open overview again every OVERVIEW_TICK_SECONDS; stopped while it is closed.
var _overview_tick: Timer
## Shows the open strategic view again every STRATEGIC_TICK_SECONDS; stopped while it is closed.
var _strategic_tick: Timer
## The new pane a split (or a new space) from the card made, waited for and picked.
var _new_pane: OfficeNewPaneFollow
## What a HUD line under the mouse points at (_show_pointer()): a pane, or a
## zone (an edge arrow); empty for none.
var _pointed_pane := ""
var _pointed_zone := ""
## What follows the view as it moves: the rail's in-view marks and the edge
## arrows (OfficeViewMarks).
var _marks: OfficeViewMarks
## The lens was last drawn held, so letting go has something to put back.
var _lens_shown := false


## The HUD is a child from the start: the world reads its free area, and a test
## that never puts the office in the tree still gets a laid-out HUD.
func _init() -> void:
	hud = HUD_SCENE.instantiate()
	add_child(hud)


func _ready() -> void:
	var args := _app_args()
	var problems := args.problems()
	if not problems.is_empty():
		# A switch that decides whether this office may write to herdr is never guessed at.
		for problem in problems:
			print("ARGS_ERROR: " + problem)
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(2)
		return
	if args.has("capture"):
		remember_theme = false
	navigator.wanted_space = args.number("space", navigator.wanted_space)
	# An odd `--zoom` rounds down to the even level below it.
	zoom = clampi(args.number("zoom", zoom) / ZOOM_STEP * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	themes = _discover_themes()
	manifest_path = _chosen_pack(args)
	art = _load_pack(manifest_path)
	if art == null:
		# Nothing here can be drawn without a pack, and the office has already
		# fallen back to the packaged one: say so and stay empty rather than
		# crash on the first missing texture.
		push_error("Herdstead has no art pack it can draw: " + manifest_path)
		# The camera and world below never exist, so nothing may tick against them.
		set_process(false)
		set_process_unhandled_input(false)
		return
	pen = OfficeDraw.new(art)
	# The backdrop stays put while the office scrolls under the camera: the
	# dark HUD's `deep`, so the world reads as lit inside a dark frame.
	var backdrop := CanvasLayer.new()
	backdrop.layer = -1
	add_child(backdrop)
	_paper = ColorRect.new()
	_paper.color = art.color(ArtContract.DEEP)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The paper starts where the bar ends; the bar's own height is the scene's.
	_paper.offset_top = hud.placed(hud.bar).size.y
	backdrop.add_child(_paper)
	light_mode = _chosen_light(args)
	_night_light = CanvasModulate.new()
	_night_light.name = "NightLight"
	add_child(_night_light)
	_update_light(true)
	camera = OfficeCamera.new(hud, _screen)
	_tips = OfficeQuestionTips.new(hud, camera, func() -> OfficeFrame: return frame, get_viewport().get_mouse_position)
	world = Node2D.new()
	world.position = camera.free_rect().position
	add_child(world)
	add_child(camera)
	camera.make_current()
	hud.dress(art, pen.font)
	hud.zone_picked.connect(_pick_zone)
	hud.machine_picked.connect(_pick_machine)
	hud.arrow_picked.connect(_pan_to_desk)
	hud.room_changed.connect(_on_room_changed)
	hud.counter_pressed.connect(_on_counter)
	hud.history_locate_requested.connect(_locate_history)
	hud.attention_snooze_requested.connect(_snooze_attention)
	hud.attention_hidden_changed.connect(_hide_attention)
	hud.agent_picked.connect(_pick_from_list)
	# NEWS and EVENTS pick the pane an event is about, as a row of the list does.
	hud.news_picked.connect(_pick_from_list)
	hud.event_picked.connect(_pick_from_list)
	# Hovering those, a list row or an edge arrow points at what it names; only points.
	hud.pane_pointed.connect(_point_at_pane)
	hud.zone_pointed.connect(_point_at_zone)
	# The EVENTS page is laid out only while it shows: the moment it does, too.
	hud.events_shown.connect(_show_events)
	# The list's double-click, Enter or Open, and the card's "Monitor ⤢".
	hud.monitor_requested.connect(_open_monitor)
	hud.agent_list_changed.connect(_remember_list)
	# NEXT on the staff panel is `N`; its line's `‹ ›` walk the same queue.
	hud.next_requested.connect(_jump_to_next_human)
	hud.step_requested.connect(_step_queue)
	# The overview: a row picks its pane; `X  Esc` closes it; a sort or a chip redraws it.
	hud.overview_picked.connect(_pick_from_list)
	hud.overview_closed.connect(_on_overview_closed)
	hud.overview_changed.connect(_show_overview)
	_overview_tick = Timer.new()
	_overview_tick.name = "OverviewTick"
	_overview_tick.wait_time = OVERVIEW_TICK_SECONDS
	_overview_tick.timeout.connect(_show_overview)
	add_child(_overview_tick)
	# The strategic view (`S`): a square picks its pane; `S`, Escape or that pick close it.
	hud.strategic_picked.connect(_on_strategic_picked)
	hud.strategic_closed.connect(_on_strategic_closed)
	_strategic_tick = Timer.new()
	_strategic_tick.name = "StrategicTick"
	_strategic_tick.wait_time = STRATEGIC_TICK_SECONDS
	_strategic_tick.timeout.connect(_show_strategic)
	add_child(_strategic_tick)
	_restore_list()
	fleet = HerdrFleet.new()
	add_child(fleet)
	_marks = OfficeViewMarks.new(hud, camera, fleet, _visible_world)
	_new_pane = OfficeNewPaneFollow.new(navigator, fleet, hud, camera, func() -> int: return pending_pick_msec)
	hud.pane_split.connect(_new_pane.later)
	hud.space_created.connect(_new_pane.later_space)
	# Every stream line can change the fleet; the frame's changes are drawn once.
	fleet.changed.connect(_queue_refresh)
	fleet.machine_replaced.connect(attention_store.retire_machine)
	fleet.liveness_changed.connect(_on_liveness_changed)
	# Everything that helps a human notice the office lives in OfficeAttention;
	# `--always-on-top` keeps the window as a small always-visible corner view.
	attention = OfficeAttention.new(fleet)
	attention.inspector = hud.inspector
	attention.bar = hud.bar
	# `(N) ` before the title counts who is blocked; `--no-title-count` leaves it out.
	attention.title_count = not args.flag("no-title-count")
	add_child(attention)
	if args.flag("always-on-top"):
		get_window().always_on_top = true
	# Only the live office paces itself; the showrooms and studio do not.
	pacer = FramePacer.new(args.raw)
	add_child(pacer)
	# The Dock bounce is on unless `--no-bounce`; the chime is off unless `--chime`
	# or the settings file's `[alerts] chime=true` (the top bar's switch writes
	# it), which a capture or a test never reads; a capture rings nothing at all.
	# `--chime` turns it on for this run whatever the file says; the switch
	# still turns it off again, and says so.
	var ring := OfficeAlerts.Options.new()
	ring.bounce = not args.flag("no-bounce")
	ring.chime = args.flag("chime") or (remember_theme and OfficeAlerts.remembered_chime(settings_path))
	ring.silent = args.has("capture")
	alerts = OfficeAlerts.new(fleet, pacer.is_focused, ring)
	add_child(alerts)
	hud.show_chime(ring.chime)
	hud.chime_toggled.connect(_switch_chime)
	# The card reads nothing while it is a compact header or the monitor covers it.
	hud.inspector.connect_fleet(fleet, pacer.is_minimized, _card_covered)
	# The terminal monitor reads and types through the same fleet; it opens only on request.
	hud.monitor.connect_fleet(fleet, pacer.is_minimized)
	# The chips over blocked agents say what they ask: read, never written.
	questions = OfficeQuestionReader.new(fleet, pacer.is_minimized)
	questions.enabled = _question_reads()
	_tips.attach(fleet, questions)
	questions.question_changed.connect(_tips.show_question)
	add_child(questions)
	filled = may_fill_screen and OfficeWindow.fills_screen(args, DisplayServer.get_name() == "headless")
	if filled:
		OfficeWindow.fill(get_window(), hud.bar)
	get_window().size_changed.connect(fit_window)
	get_viewport().size_changed.connect(_refresh)
	fit_window()
	_refresh()
	fleet.start(args.raw, args.read_only())
	if args.flag("attention"):
		hud.toggle_agent_list()
	# `--list=tree` opens the agent list in its tree view (a capture's second shot).
	if args.text("list") == "tree":
		hud.agent_list.set_view(AgentListModel.View.TREE)
	# `--list=history` folds every flat group but History (a capture's shot).
	elif args.text("list") == "history":
		for key: String in AgentListModel.FLAT_GROUPS:
			hud.agent_list.set_collapsed(key, key != AgentListModel.FLAT_HISTORY)
	# `--drawer=open` starts with the agent list's drawer open, which every run
	# otherwise starts closed (a capture's shot).
	if args.text("drawer") == "open":
		hud.open_drawer()
	# `--drawer=events` starts with the drawer open on its EVENTS page (a capture's shot).
	elif args.text("drawer") == "events":
		hud.open_drawer()
		hud.select_drawer_tab(OfficeHud.DrawerTab.EVENTS)
	# `--overview=open` starts with the overview open (a capture's shot).
	if args.text("overview") == "open":
		_open_overview()
	# `--strategic=open` starts with the strategic view open (a capture's shot, perf).
	if args.text("strategic") == "open":
		_open_strategic()
	# Holding `L` is the lens; `--lens=held` holds it (a capture's shot, perf).
	lens = OfficeLens.new(_may_lens)
	lens.forced = args.text("lens") == "held"
	lens.changed.connect(_on_lens)
	lens.ticked.connect(_show_lens)
	add_child(lens)
	_tips.lens = lens
	# `--point=<pane key>` points at a pane as a hovered line would (a capture's
	# shot); a bare pane id, as a command line can spell it, is Local's.
	if args.has("point"):
		var pointed := HerdrFleet.split_key(args.text("point"))
		_point_at_pane(HerdrFleet.pane_key(pointed[0], pointed[1]))
	if args.has("capture"):
		# The first real frame of herdr data, or the OFFLINE state if the socket
		# never answers: every machine drawn, or the timeout.
		await CaptureDriver.run(self, args, "office", fleet.all_loaded, _capture_problem)


# --- themes -------------------------------------------------------------------


## Every runtime pack, sorted by its directory, which is named after the pack id.
## DirAccess reads res:// out of the PCK in an exported game, and only the files
## the export include filter kept, so `*.json` has to be in that filter there.
## Editor and source runs always see the whole tree.
func _discover_themes() -> PackedStringArray:
	var found := PackedStringArray()
	var packs := DirAccess.open(PACK_ROOT)
	if packs == null:
		return found
	var names := packs.get_directories()
	names.sort()
	for pack_name in names:
		var candidate := PACK_ROOT.path_join(pack_name).path_join("manifest.json")
		if FileAccess.file_exists(candidate):
			found.append(candidate)
	return found


## The chosen pack, falling back to the one this build ships when it cannot be
## drawn: a theme that broke since the last run must not take the office down.
## Null only when the packaged pack is broken too, which callers have to handle.
func _load_pack(path: String) -> ArtPack:
	var chosen := ArtPack.from_manifest(path)
	if chosen != null:
		return chosen
	if path == DEFAULT_MANIFEST:
		return null
	push_warning("Art pack cannot be drawn, falling back to the default: " + path)
	manifest_path = DEFAULT_MANIFEST
	return ArtPack.from_manifest(DEFAULT_MANIFEST)


## `--pack=` beats the remembered choice beats whatever the scene was saved with.
func _chosen_pack(args: AppArgs) -> String:
	if args.has("pack"):
		return args.text("pack")
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return manifest_path
	var remembered := str(settings.get_value("theme", "manifest_path", ""))
	if remembered.is_empty():
		return manifest_path
	if not FileAccess.file_exists(remembered):
		# A pack removed since the last run must not take the office down with it.
		push_warning("Remembered art pack is gone, falling back: " + remembered)
		return manifest_path
	return remembered


## Swap the whole art pack in place. The herdr fleet is deliberately untouched:
## a repaint is not a reconnect, and the camera, selection and zoom are the
## viewer's state, not the pack's.
func switch_theme(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("No art pack at " + path)
		return
	var chosen := ArtPack.from_manifest(path)
	if chosen == null:
		# A pack that cannot be drawn is not worth losing the office over: the
		# one on screen keeps every texture it already has.
		push_warning("Art pack cannot be drawn, keeping the current one: " + path)
		return
	manifest_path = path
	art = chosen
	pen = OfficeDraw.new(art)
	hud.dress(art, pen.font)
	_update_light(true)
	_redraw()
	_remember_theme(path)


## The world's nodes hold the old pack's textures, so drop them and redraw. The
## HUD is re-dressed in place and keeps every node it has.
func _redraw() -> void:
	world_model = ""
	_refresh()


## `T`: turn the light over. Following the clock, the other of day and night
## holds until the clock's own turns; held (`--light=`), it swaps. Never a
## write, never a state: the time of day binds no herdr field.
func toggle_light() -> void:
	if light_mode == LightMode.CLOCK:
		_light_flipped = not _light_flipped
		_flipped_at_night = DayLight.is_night(DayLight.night_at(_now_minutes()))
	else:
		light_mode = LightMode.NIGHT if light_mode == LightMode.DAY else LightMode.DAY
	_update_light(true)


## Read the clock and light the world for it: the world's tint, the paper
## backdrop, every lamp and window of the shown floor, and the bar's DAY /
## NIGHT. Nothing is redrawn while the light stays as it was, unless `force`.
func _update_light(force := false) -> void:
	var natural := DayLight.night_at(_now_minutes())
	if _light_flipped and DayLight.is_night(natural) != _flipped_at_night:
		# The clock's own day or night turned: follow it again.
		_light_flipped = false
	var amount := natural
	if light_mode == LightMode.DAY:
		amount = 0.0
	elif light_mode == LightMode.NIGHT:
		amount = 1.0
	if _light_flipped:
		amount = 1.0 - amount
	if not force and is_equal_approx(amount, night):
		return
	var was_night := DayLight.is_night(night)
	night = amount
	var tint := DayLight.tint(night)
	if _night_light != null:
		_night_light.color = tint
	if _paper != null and art != null:
		_paper.color = art.color(ArtContract.DEEP) * tint
	if floor_view != null:
		floor_view.set_night(night)
	if (force or was_night != DayLight.is_night(night)) and fleet != null and art != null:
		_show_bar(_bar_live)


## `--light=day|night|clock`; a capture holds the day unless it asks.
func _chosen_light(args: AppArgs) -> LightMode:
	match args.text("light", "day" if args.has("capture") else ""):
		"day":
			return LightMode.DAY
		"night":
			return LightMode.NIGHT
		"clock", "":
			return light_mode
		var other:
			push_warning("--light takes day, night or clock, not %s; following the clock" % other)
			return LightMode.CLOCK


## The clock's minutes after midnight.
func _now_minutes() -> float:
	var minutes: float = clock.call()
	return minutes


## Local minutes after midnight, from the system clock.
static func _local_minutes() -> float:
	var now := Time.get_time_dict_from_system()
	var hour: int = now.get("hour", 0)
	var minute: int = now.get("minute", 0)
	var second: int = now.get("second", 0)
	return hour * 60.0 + minute + second / 60.0


func _remember_theme(path: String) -> void:
	if not remember_theme:
		return
	var settings := ConfigFile.new()
	# Loading first keeps anything else the config file holds.
	settings.load(settings_path)
	settings.set_value("theme", "manifest_path", path)
	settings.save(settings_path)


# --- input --------------------------------------------------------------------


func _process(delta: float) -> void:
	if floor_view != null:
		floor_view.walk(delta)
	_light_left -= delta
	if _light_left <= 0.0:
		_light_left = 1.0
		_update_light()
	_inbox_left -= delta
	if _inbox_left <= 0.0:
		_inbox_left = 1.0
		_show_attention()
		_marks.tick(frame, navigator.shown_key)
	_questions_left -= delta
	if _questions_left <= 0.0:
		_questions_left = QUESTION_WATCH_SECONDS
		_watch_questions()
	# The view moved without a refresh (a drag, the wheel, a panel): what marks it follows.
	_marks.follow(frame, navigator.shown_key)
	_new_pane.give_up()


## Everything the office answers with a key or the wheel: zoom, theme, zone,
## "next human" and scrolling. The bindings are project.godot's `[input]`, not
## keycodes, and no action repeats while a key is held. True when the event was
## one of them.
func _act_on(event: InputEvent) -> bool:
	# The terminal monitor takes every key while it is open; none of the office's
	# fires. Under the overview `A` is the table's (it takes it and does nothing).
	if not hud.monitor_open() and not hud.overview_open() and event.is_action_pressed(&"office_attention_panel"):
		hud.toggle_agent_list()
		return true
	if hud.monitor_open():
		return true
	# The staff panel is one line that reads nothing until it is opened: Enter
	# on any pane shown opens it (read-only and followed panes too), and the
	# card then takes that Enter if it is a picked agent's.
	if hud.card_compact() and event.is_action_pressed(&"card_answer", false, true):
		if frame.pane(navigator.active_key) != null:
			hud.expand_card()
	# The agent card first: its answer mode, and the Enter that opens it. It
	# takes no office key, and `N` in answer mode comes back here as "next".
	# Escape in answer mode only leaves answer mode.
	if hud.inspector.take_key(event):
		return true
	# Escape out of answer mode folds an opened panel back to its line.
	var folded := hud.card_expanded() and event.is_action_pressed(&"card_leave", false, true)
	if folded:
		hud.compact_card()
	# Then the overview (_overview_key()): Escape reaches it only once answer
	# mode and an opened panel have let it go; then the strategic view.
	if folded or _overview_key(event) or _strategic_key(event):
		return true
	var zoom_in := event.is_action_pressed(&"office_zoom_in")
	var floor_up := event.is_action_pressed(&"office_floor_up")
	if zoom_in or event.is_action_pressed(&"office_zoom_out"):
		zoom = clampi(zoom + (ZOOM_STEP if zoom_in else -ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		fit_window()
	elif event.is_action_pressed(&"office_toggle_light"):
		toggle_light()
	elif floor_up or event.is_action_pressed(&"office_floor_down"):
		_step_zone(-1 if floor_up else 1)
	elif event.is_action_pressed(&"office_next_attention"):
		_jump_to_next_human()
	elif event.is_action_pressed(&"office_monitor"):
		# `M`: the monitor on the pane shown, as its Monitor button asks.
		_open_monitor(navigator.active_key)
	elif event.is_action_pressed(&"office_scroll_up"):
		camera.scroll(Vector2.UP)
	elif event.is_action_pressed(&"office_scroll_down"):
		camera.scroll(Vector2.DOWN)
	elif event.is_action_pressed(&"office_scroll_left"):
		camera.scroll(Vector2.LEFT)
	elif event.is_action_pressed(&"office_scroll_right"):
		camera.scroll(Vector2.RIGHT)
	else:
		return false
	return true


## `O` opens the overview; while it is open, Escape or `O` closes it, `N` (and
## NEXT) walk the queue under it, the arrows scroll its table, the zoom and
## `T` still work (false: _act_on() does them), and every other key of the
## office (`A`, PageUp, PageDown, the wheel's) is the table's, which takes it
## and does nothing. True when the overview took the key.
func _overview_key(event: InputEvent) -> bool:
	if not hud.overview_open():
		if not event.is_action_pressed(&"office_overview"):
			return false
		_open_overview()
	elif event.is_action_pressed(&"card_leave", false, true) or event.is_action_pressed(&"office_overview"):
		_close_overview()
	elif event.is_action_pressed(&"office_next_attention"):
		_jump_to_next_human()
	elif event.is_action_pressed(&"ui_up", true) or event.is_action_pressed(&"ui_down", true):
		hud.overview.scroll_rows(-1 if event.is_action(&"ui_up") else 1)
	else:
		var zoom_key := event.is_action_pressed(&"office_zoom_in") or event.is_action_pressed(&"office_zoom_out")
		return not (zoom_key or event.is_action_pressed(&"office_toggle_light"))
	return true


## `S` opens the strategic view; while it is open, `S` or Escape closes it (the
## Escape answer mode, an opened panel and the overview left alone), and no
## mouse event reaches the hidden world: the wheel does not scroll it, a drag
## in a gap between the panels does not pan it. Every other key is the
## office's as always (false): N, PageUp, PageDown, the zoom, `T`, `M`, `O`.
func _strategic_key(event: InputEvent) -> bool:
	if not hud.strategic_open():
		if not event.is_action_pressed(&"office_strategic"):
			return false
		_open_strategic()
		return true
	if event.is_action_pressed(&"office_strategic") or event.is_action_pressed(&"card_leave", false, true):
		_close_strategic()
		return true
	return event is InputEventMouse


func _unhandled_input(event: InputEvent) -> void:
	# A drag takes the tooltip away: it is about where the pointer rests.
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_tips.hide_tip()
	if not _act_on(event):
		camera.drag(event)


## A left click released over a seat, at `at` in viewport pixels. A drag pans
## the office; only a still click picks a desk, and the press this release
## belongs to is already recorded: the viewport hands a mouse button to
## _unhandled_input first and only queues the physics pick when nothing marked
## it handled, so the seat reports the release on the next physics frame
## (verified against 4.7.2). That also means a click over a HUD panel never
## gets here at all: the panel takes it in the GUI pass, before either step.
func _on_desk_picked(key: String, at: Vector2) -> void:
	if hud.monitor_open() or not camera.still_click(at):
		return
	# A pick, even of the same desk, ends the card's answer mode.
	hud.inspector.leave_answer()
	# The terminal at that desk now is the one picked: a later one reusing its id is not.
	var pane := frame.pane(key)
	navigator.pick_desk(key, "" if pane == null else pane.identity_key())
	_refresh()


## A left click released over a blocked agent's chip: the same rules as a
## desk, then the pane is picked the way the agent list picks one, and the card
## (opened up first on a short screen) goes into answer mode once it shows the
## question (OfficePaneInspector.arm_answer()). Nothing is sent: answering is
## still the viewer's own button or key, and an office that may not write only
## picks.
func _on_chip_picked(key: String, at: Vector2) -> void:
	if hud.monitor_open() or not camera.still_click(at):
		return
	var pane := frame.pane(key)
	if pane == null:
		return
	_pick_pane(pane)
	# Open for this pane, even when it was open for another one (which folds
	# only on the HUD's next look).
	if _card_may_open():
		hud.expand_card()
	hud.inspector.arm_answer()


## A row of the SPACES rail: its zone panned to at once, on its machine's map
## (another machine's is shown first). Under the strategic view, the schematic
## scrolls to that zone's section.
func _pick_zone(key: String) -> void:
	navigator.pick_zone(key)
	_refresh()
	_reveal_section(key)


## A heading of the SPACES rail: that machine's map, at once (a machine that
## never connected is an empty map saying why). Nothing for a machine gone since.
func _pick_machine(key: String) -> void:
	if frame.building_of(key) == null:
		return
	camera.cancel_press()
	navigator.pick_machine(key)
	_refresh()


## An edge arrow: pan as far as it takes for the desk of pane `key` to be on
## screen. Nothing is selected, and nothing is read or written.
func _pan_to_desk(key: String) -> void:
	camera.cancel_press()
	navigator.pan_to_desk(key)
	_refresh()


## PageUp (-1) / PageDown (+1): the zone one row up or down the rail, from a
## machine's last zone into the next machine's first. Stops at either end.
func _step_zone(direction: int) -> void:
	if navigator.step_zone(frame, direction):
		_refresh()
		_reveal_section(navigator.current_zone(frame))


## While the strategic view is open, scroll it to zone `key`'s section.
func _reveal_section(key: String) -> void:
	if hud.strategic_open():
		hud.reveal_strategic_section(key)


## `N` and NEXT: select the next agent that needs a human, show its map and
## pan its desk into view, and do what NEXT's verb says (_open_card_for()): a
## blocked one's answer mode, a done one's panel. Repeated presses walk the
## queue and wrap around; `N` in answer mode leaves it first, and opens it
## again on the next blocked agent. Nothing is sent. Not while the monitor is open.
func _jump_to_next_human() -> void:
	if hud.monitor_open() or not navigator.next_human(frame):
		return
	camera.cancel_press()
	# The card's new binding leaves answer mode itself, and keeps a button still
	# held down so that its release says "target changed" (OfficePaneInspector._bind()).
	_refresh()
	_open_card_for(frame.pane(navigator.picked_key))


## `‹` (-1) or `›` (+1) on the staff panel's line: the one before or after the
## pick in NEXT's queue, picked, its map shown and its desk revealed. Only a
## selection: no answer mode (the new binding leaves it), and an open panel
## folds because the card is aimed at another pane. Not while the monitor is open.
func _step_queue(direction: int) -> void:
	if hud.monitor_open() or not navigator.step(frame, direction):
		return
	camera.cancel_press()
	_refresh()


## What NEXT's verb promises for `pane`, just picked (NextModel.verb): an agent
## that asks gets its panel opened and answer mode once its question shows
## (OfficePaneInspector.arm_answer()); a done one gets its panel opened. Only
## where the card could act (_card_may_open()): an office that may not write
## only picks. Nothing is sent: answering is still the viewer's own key.
func _open_card_for(pane: PaneModel) -> void:
	if pane == null:
		return
	if pane.asks():
		if _card_may_open():
			hud.expand_card()
		hud.inspector.arm_answer()
	elif pane.state == str(ArtContract.STATE_DONE) and _card_may_open():
		hud.expand_card()


## A top-bar counter pressed: BLOCKED walks the blocked agents, longest wait
## first, and opens answer mode once the question is shown, as a click on a
## chip does; DONE walks the UNREAD ones from the oldest, and only picks;
## WORKING and IDLE filter the agent list, and the same press again clears it
## (while the overview is open they set its chips instead, and leave the list
## alone); PANES opens the overview, or closes it. MACHINES only has its hover.
func _on_counter(id: StringName) -> void:
	match id:
		&"blocked":
			_jump_to_state(str(ArtContract.STATE_BLOCKED))
		&"done":
			_jump_to_state(str(ArtContract.STATE_DONE))
		&"working":
			if hud.overview_open():
				_toggle_chip(OverviewModel.Filter.WORKING)
			else:
				hud.toggle_list_filter([AgentListModel.Presence.WORKING])
		&"idle":
			if hud.overview_open():
				_toggle_chip(OverviewModel.Filter.IDLE)
			else:
				hud.toggle_list_filter([AgentListModel.Presence.IDLE])
		&"panes":
			if hud.overview_open():
				_close_overview()
			else:
				_open_overview()


## WORKING or IDLE pressed under the overview: its chip, or ALL again.
func _toggle_chip(keep: OverviewModel.Filter) -> void:
	hud.overview.set_filter(OverviewModel.Filter.ALL if hud.overview.filter() == keep else keep)


## Select the next agent in `state` (OfficeNavigator.next_of()), show its floor
## and reveal its desk, then as NEXT does (_open_card_for()): a blocked one's
## panel opens and answer mode once it shows the question, a done one's panel
## opens; an office that may not write only picks. Nothing is sent. Not while
## the monitor is open.
func _jump_to_state(state: String) -> void:
	if hud.monitor_open() or not navigator.next_of(frame, state):
		return
	camera.cancel_press()
	hud.inspector.leave_answer()
	_refresh()
	_open_card_for(frame.pane(navigator.picked_key))


func _on_liveness_changed() -> void:
	_apply_stale()
	_refresh()


# --- refresh ------------------------------------------------------------------


## Project every machine once and bring what shows them up to date: the shown
## machine's map by stable tab and pane identity (status and label changes keep
## its geometry, structural changes keep the nodes they do not touch, a
## workspace coming or going is a zone arriving or leaving), the plate, the
## SPACES rail and the edge arrows, the bar, the inspector and attention.
func _refresh() -> void:
	_refreshing = true
	# Whatever the fleet said before this point is drawn by this refresh.
	var for_data := _data_pending
	_data_pending = false
	frame = OfficeProjection.frame(_machines(), art.state_names())
	_stamp_starts()
	_new_pane.follow(frame)
	plans.prune(frame.building_by_key.keys())
	var wanted := navigator.settle(frame)
	# Another machine's map is shown at once: no ride, nothing held back.
	if wanted != navigator.shown_key:
		camera.cancel_press()
		_tips.hide_tip()
		navigator.show_machine(frame, wanted, camera.pan)
		camera.pan = navigator.pan_of(wanted)
	var building := frame.building_of(wanted)
	var live := fleet.live_count()
	stale = live == 0
	# free_rect() first: it lays the HUD out for this refresh's window (a resize
	# refreshes before the camera's next frame), and a map's first plan fixes
	# its width for good.
	var room := camera.free_rect()
	# The shown machine's map: every zone of it, under the machine's key.
	var map := building.map
	var planned := plans.prepare(map, pen, hud.plan_width())
	var problems := plans.problems()
	var model := JSON.stringify([map.key, art.id])
	if model != world_model:
		world_model = model
		_build(building, map, planned, problems)
	elif problems.is_empty():
		floor_view.reconcile(planned, map, _frozen())
	if problems.is_empty():
		floor_view.update_desks(map, navigator.active_key, _frozen())
	else:
		# Nothing on the map followed this input: the next update that can be
		# laid out brings all of it at once, with nobody walking.
		floor_view.lose_track()
	_content_size = floor_view.plan.render_bounds.end + Vector2(0, PLATE_HEIGHT)
	world.position = room.position
	_show_plate(building, problems)
	# Where the navigator asked to look: a zone (its aisle row at the top), a
	# desk (a map seen for the first time: its whole pod; herdr's focus moving:
	# as far as it takes), and an explicit navigation's desk once it is drawn.
	var zone := navigator.take_pan_zone()
	if not zone.is_empty():
		reveal_zone(zone)
	var whole := navigator.pan_whole_table
	var pan_to := navigator.take_pan_to()
	if not pan_to.is_empty() and floor_view.seats.has(pan_to):
		reveal(pan_to, whole)
	var arriving := navigator.reveal_on_arrival
	if not arriving.is_empty() and floor_view.seats.has(arriving):
		reveal(arriving)
		navigator.revealed()
	# After the camera is placed for this map: which chips are on screen.
	_watch_questions()
	_show_spaces()
	_marks.show(frame, navigator.shown_key)
	_show_bar(live)
	_show_totals()
	_show_staff()
	_show_news()
	_show_events()
	_show_monitor()
	attention.update(frame.live_panes, stale, fleet.size() - live)
	alerts.take(frame)
	_observe_attention()
	_show_overview()
	_show_strategic()
	_show_lens()
	_show_pointer()
	_refreshing = false
	if for_data:
		data_refreshed.emit()


## The fleet changed (HerdrFleet.changed: a snapshot, a status event, the
## roster, a link): one refresh at the end of this frame draws every change the
## frame brought, however many stream lines it read. The fleet's state log has
## already heard each of them (HerdrFleet._note()), so nothing a refresh reads
## from the ledger — NEWS, EVENTS, the alerts — misses one. A click, a resize or
## a zone picked still refreshes at once, and takes the queued changes in with it.
func _queue_refresh() -> void:
	if _data_pending:
		return
	_data_pending = true
	_flush_refresh.call_deferred()


## The queued refresh, unless one since has drawn the changes; an office taken
## out of the tree meanwhile draws nothing (and queues afresh on the next change).
func _flush_refresh() -> void:
	if not _data_pending:
		return
	if not is_inside_tree():
		_data_pending = false
		return
	_refresh()


## A HUD panel moved (drawer, staff panel): the world's room changed without the window doing so.
## Inside a refresh it only drops the camera's room: the one move a refresh can
## cause is the window's own fit in camera.free_rect(), which the refresh reads
## right after, so a second refresh nested in it would redo the same work on a
## half-updated office. Before the fleet exists (the drawer restored in
## _ready()) there is nothing to lay out yet: _ready() refreshes once it is.
func _on_room_changed() -> void:
	if camera == null:
		return
	camera.relayout()
	if _refreshing or fleet == null:
		return
	_refresh()


## What the office runs for every new snapshot, resize or change of map, at
## once, for tools and tests (tools/perf_probe.gd times it); it also draws any
## change the fleet queued for the end of the frame (_queue_refresh()).
func refresh() -> void:
	_refresh()


## The shown machine's map plan: every zone of it.
func layout_plan() -> FloorPlan:
	return plans.plan(navigator.shown_key)


## Why the shown map cannot be laid out from its current input; empty while it can.
func layout_problems() -> PackedStringArray:
	return plans.problems()


## Actual planner calls during this office's lifetime, empty maps and empty
## fallbacks included. Cache hits do not increment this diagnostic counter.
func layout_attempt_count() -> int:
	return plans.attempt_count()


## Non-fatal explanations, such as folding a complex terminal grid into seats.
func layout_notes() -> PackedStringArray:
	return plans.notes(navigator.shown_key)


func world_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, camera.world_size)


## Rebuild from the retained plan, including its history-dependent free spaces.
func rebuild_world() -> void:
	_redraw()


## The machine the world on screen was built for.
func shown_machine() -> String:
	return _world_machine


## Pan just enough for the desk of `key`, its badge included, to be on screen:
## where it answers a click, which is where its worker rests (a pantry worker's
## own rectangle), and the chip over a blocked one. With `whole_table`, the
## framing a map opens on: the desk and its whole pod when that fits, else
## the desk alone. The world is what the pan is measured in.
func reveal(key: String, whole_table := false) -> void:
	var seat := floor_view.seat(key)
	if seat == null:
		return
	var bounds := seat.node.target_rect()
	var chip := seat.node.chip_rect()
	if chip.has_area():
		bounds = bounds.merge(chip)
	if whole_table:
		var table := seat.node.table
		var group := table.geometry.render_rect
		group.position += table.global_position
		if _fits(bounds.merge(group)):
			bounds = bounds.merge(group)
	camera.reveal(Rect2(world.to_local(bounds.position), bounds.size))


## Pan to zone `key` of the shown map: the top of its sign's drawing (in the
## aisle row above the zone) at the top of the world, or the aisle row's top
## for a zone with no sign drawn yet; and as little sideways as brings the
## zone's width in (its left edge when it is wider than the view). The camera
## clamps the pan to the map. Nothing for a zone the plan does not place.
## (The sign's top, not the aisle row's, is the 14 units that let a two-pod-row
## zone's second far row fit a 308-tall view: PLAN_R2 §1.10.)
func reveal_zone(key: String) -> void:
	var placed: ZonePlacement = null if floor_view.plan == null else floor_view.plan.zone(key)
	if placed == null:
		return
	var grid := float(FloorLayoutPolicy.GRID)
	var shown := camera.free_rect().size
	var left := placed.cells.position.x * grid
	var right := placed.cells.end.x * grid
	camera.pan.y = (placed.cells.position.y - 1) * grid + PLATE_HEIGHT
	var board := floor_view.zone_sign(key)
	var holder := null if board == null else board.get_parent() as Node2D
	if holder != null:
		camera.pan.y = world.to_local(holder.to_global(board.drawn_rect().position)).y
	camera.pan.x = left if right - left > shown.x else minf(maxf(camera.pan.x, right - shown.x), left)


## Whether `bounds` (global) fits the view, the camera's headroom included.
func _fits(bounds: Rect2) -> bool:
	var room := camera.free_rect().size
	return bounds.size.x <= room.x and bounds.size.y + OfficeCamera.REVEAL_HEADROOM <= room.y


## Give every pane of the frame when its state began (PaneModel.state_since),
## seated or not: it orders the pantry and the `N` key (OfficeNavigator.waiting(),
## which ranks the panes no zone seats as it ranks the seated), and the
## terminal monitor's title reads it from frame.pane(). A live machine's come
## from the fleet, and are kept; a stale machine's are the ones kept from when
## it was last live, because its client forgets every start when it drops (and
## when a snapshot is refused), and ranking its frozen map by those would
## reshuffle it on the next click, `N` or another machine's snapshot. The first
## refresh after it is back is cold anyway and ranks it afresh.
func _stamp_starts() -> void:
	for building_model in frame.buildings:
		var kept: Dictionary = _live_starts.get(building_model.key, {})
		var fresh := {}
		var panes: Array[PaneModel] = []
		for floor_model in building_model.zones:
			for room in floor_model.rooms:
				panes.append_array(room.panes)
		var seated: Dictionary[String, float] = {}
		for pane in panes:
			_stamp_start(pane, building_model, kept, fresh)
			seated[pane.key] = pane.state_since
		# The frame's own list (frame.pane(), the unseated) holds other models of
		# the same panes: a seated one's start is copied, which is what keeps this
		# cheap (an identity key is a JSON string); only the unseated are stamped.
		for pane in building_model.all_panes:
			if seated.has(pane.key):
				pane.state_since = seated[pane.key]
			else:
				_stamp_start(pane, building_model, kept, fresh)
		if not building_model.stale:
			_live_starts[building_model.key] = fresh
	for key: String in _live_starts.keys():
		if not fleet.has(key):
			_live_starts.erase(key)


## One pane's start for _stamp_starts(): kept from when its machine was last
## live while it is stale, else the fleet's, noted in `fresh` for that day.
func _stamp_start(pane: PaneModel, building_model: BuildingModel, kept: Dictionary, fresh: Dictionary) -> void:
	# The pane and who is in it (PaneModel.identity_key()); a cleaned key holds
	# no control character, so the line break cannot be part of it.
	var identity := pane.key + "\n" + pane.identity_key()
	if building_model.stale:
		var since: float = kept.get(identity, -1.0)
		pane.state_since = since
	else:
		pane.state_since = fleet.state_since(building_model.key, pane.pane_id)
		fresh[identity] = pane.state_since


## Every machine as the fleet holds it now, Local first: all a frame is made of.
func _machines() -> Array[MachineView]:
	var views := fleet.views()
	var machines: Array[MachineView] = []
	for key in fleet.keys():
		var held: HerdrSnapshot = views.get(key)
		machines.append(MachineView.new(key, fleet.label(key), held, fleet.is_stale(key)))
	return machines


# --- world --------------------------------------------------------------------


## Only changing machines or packs replaces the world (the cold path: nobody
## walks); everything else, a workspace coming or going included, goes through
## OfficeFloorView, which retains the other desks and their animations.
func _build(building: BuildingModel, map: MapModel, planned: FloorPlan, problems: PackedStringArray) -> void:
	remove_child(world)
	world.queue_free()
	world = Node2D.new()
	world.position = camera.free_rect().position
	add_child(world)
	_world_machine = building.key
	var rooms := Node2D.new()
	rooms.name = "FloorRooms"
	rooms.position = Vector2(0, PLATE_HEIGHT)
	world.add_child(rooms)
	floor_view = OfficeFloorView.new()
	floor_view.setup(pen, rooms, _on_desk_picked, _on_chip_picked, _tips.on_chip_hovered, _tips.on_sign_hovered)
	_marks.floor_view = floor_view
	floor_view.set_night(night)
	# A map whose current input cannot be planned keeps drawing the model its
	# last valid plan was made for.
	var drawn := map if problems.is_empty() else plans.planned_model(map.key)
	floor_view.reconcile(planned, drawn, _frozen())
	floor_view.update_desks(drawn, navigator.active_key, _frozen())
	plate = PLATE_SCENE.instantiate()
	world.add_child(plate)
	plate.dress(art, hud.screen_theme())
	_apply_stale()


## The plate names the shown machine over the width the world has, and the
## zones its map cannot be laid out for; the pan's reach is the wider of the
## map and the plate.
func _show_plate(building: BuildingModel, problems: PackedStringArray) -> void:
	plate.size = Vector2(camera.free_rect().size.x, plate.size.y)
	plate.show_map(building, frame.several_machines(), problems, plans.failing_zones(building.key))
	_show_plate_state()
	camera.world_size = Vector2(maxf(_content_size.x, plate.size.x), _content_size.y)
	var floor_width := (
		float(floor_view.plan.floor_cells.size.x * FloorLayoutPolicy.GRID) if floor_view.plan != null else 0.0
	)
	floor_view.set_apron(OfficeFloorView.apron_cells(camera.free_rect(), _screen(), floor_width))


## The plate's state line, and an empty map's note, from the shown machine's
## liveness and SSH status. Never a rebuild: a flapping machine relabels.
func _show_plate_state() -> void:
	if plate == null or not fleet.has(_world_machine):
		return
	plate.show_state(_building_state(_world_machine), fleet.link_error(_world_machine))


## A dropped connection keeps that machine's last map on screen, all of it dimmed and
## frozen; its plate stays readable. Never dress a lost connection up as idle.
func _apply_stale() -> void:
	if floor_view != null and fleet.has(_world_machine):
		floor_view.freeze(fleet.is_stale(_world_machine), art.stale_tint)
	_show_plate_state()


## A worker drawn for a dropped machine starts frozen, like the rest of its map.
func _frozen() -> bool:
	return fleet.has(_world_machine) and fleet.is_stale(_world_machine)


func _building_state(key: String) -> MachineLiveness.State:
	if not fleet.is_stale(key):
		return MachineLiveness.State.LIVE
	if fleet.link_error(key).is_empty() and fleet.link_state(key) == MachineLink.State.RESOLVING:
		return MachineLiveness.State.CONNECTING
	return MachineLiveness.State.OFFLINE


## Tell the question reader what the shown map asks and which chips are on
## screen (OfficeQuestionTips.watch()): a refresh, and a timer for a pan.
func _watch_questions() -> void:
	if floor_view != null:
		_tips.watch(floor_view, navigator.shown_key, _visible_world)


## The part of the world on screen, in global coordinates, from where the
## camera is panned now: a refresh that just placed it for a new map is
## counted before the camera's own frame moves there (OfficeCamera._process()
## clamps and rounds the pan the same way).
func _visible_world() -> Rect2:
	var room := camera.free_rect()
	var reach := (camera.world_size - room.size).max(Vector2.ZERO)
	return Rect2(camera.pan.clamp(Vector2.ZERO, reach).round() + room.position, room.size)


## Whether the chips' reader reads at all; a test double turns it off.
func _question_reads() -> bool:
	return true


# --- window -------------------------------------------------------------------


## The content scale a window of this size shows at this zoom: the largest even
## scale up to `zoom` that still fits MIN_SCREEN, so a density-2 texel lands on
## whole screen pixels. A window that cannot hold MIN_SCREEN at ZOOM_MIN is
## below the supported size and drops to 1, which is not sharp. The one place
## this rule lives; the capture tools ask it too.
static func content_scale_for(window: Vector2i, wanted: int) -> int:
	var fit := mini(window.x / MIN_SCREEN.x, window.y / MIN_SCREEN.y)
	if fit < ZOOM_MIN:
		return 1
	return clampi(mini(fit, wanted) / ZOOM_STEP * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


## Pin the pixel scale and let the viewport grow instead: a bigger window shows
## more office, not bigger pixels. The scale drops when the window gets too small.
## Zoom is the whole window's content scale, HUD included. Textures are handed
## out as built. The viewport changes how much of the stable floor is visible;
## neither the plan nor the world nodes are rebuilt.
func fit_window() -> void:
	var window := get_window()
	var scale_now := content_scale_for(window.size, zoom)
	# No fixed base size: keep the render target attached to the entire window,
	# including fractional logical pixels at its edges. Recomputing a rounded
	# base size inside size_changed leaves the outer resize attaching its old
	# letterboxed rectangle after this callback, even when the canvas is correct.
	window.content_scale_size = Vector2i.ZERO
	window.content_scale_factor = scale_now
	hud.bar.set_title_gap(OfficeWindow.title_gap(window, hud.placed(hud.bar).size.y))


## Why a capture would not show what `--zoom` asked for, empty when it does.
## The window's real content scale is the judge: a window the OS made smaller
## than `--resolution` asked (a small display) drops to a lower even scale, and
## a picture at that scale is not the picture the run is for.
func _capture_problem() -> String:
	var window := get_window()
	if is_equal_approx(window.content_scale_factor, float(zoom)):
		return ""
	return (
		"the %dx%d window shows %sx, --zoom asked for %dx (did the OS shrink the window?)"
		% [window.size.x, window.size.y, window.content_scale_factor, zoom]
	)


## Window size in viewport pixels; grows with the window at integer scale.
func _screen() -> Vector2:
	return get_viewport_rect().size


## This run's command line, read once in _ready(); a test double hands in its own.
func _app_args() -> AppArgs:
	return AppArgs.current()


# --- screen-space UI ----------------------------------------------------------


## Each machine for the SPACES rail: label, live state, and its zones' rows;
## the heading of the machine whose map is shown is the highlighted one. Which
## rows are in view is OfficeViewMarks's, after this.
func _show_spaces() -> void:
	var rows: Array[SpaceRows] = []
	for building in frame.buildings:
		rows.append(SpaceRows.of(building, _building_state(building.key)))
	hud.spaces.show_machines(rows, navigator.shown_key, frame.several_machines())


## The right-hand lines: the pack, and how the office runs. The bar's labels
## are permanent: this writes text into them, it never rebuilds them.
func _show_bar(live: int) -> void:
	_bar_live = live
	var status := bar_status(fleet.read_only(), live, fleet.size())
	var theme := "%s · %s  [T]" % [art.display_name.to_upper(), "NIGHT" if DayLight.is_night(night) else "DAY"]
	hud.fit(_screen())
	hud.show_bar(theme, status, live < fleet.size())


## The bar's status line for `live` machines answering out of `total`: which
## mode the office is in, said as plainly as whether it is live. Every string
## it can make has to fit the bar's right-hand lines (tools/test_top_bar.gd).
static func bar_status(read_only: bool, live: int, total: int) -> String:
	var mode := "READ ONLY" if read_only else "OPERATOR"
	if live == 0:
		return "OFFLINE / RECONNECTING"
	if live < total:
		return "%d OFFLINE / %s" % [total - live, mode]
	return "LIVE / " + mode


## The top bar's counters, from the machines answering now (OfficeTotals), and
## the blocked panes whose longest wait attention ticks in the BLOCKED counter.
func _show_totals() -> void:
	var totals := OfficeTotals.of(frame, _machine_rows(), fleet.state_log())
	hud.show_totals(totals)
	attention.watch_blocked(totals.blocked_tracks)


## Every machine in the fleet, Local first, as the MACHINES counter's hover
## tells it: how it answers, when it was last heard from, and why not.
func _machine_rows() -> Array[OfficeTotals.MachineRow]:
	var rows: Array[OfficeTotals.MachineRow] = []
	for key in fleet.keys():
		var row := OfficeTotals.MachineRow.new()
		row.label = fleet.label(key)
		row.state = _building_state(key)
		row.heard_since = fleet.heard_since(key)
		row.error = fleet.link_error(key)
		rows.append(row)
	return rows


## The staff panel: the selected pane, judged by its own machine (another
## machine dropping does not make this pane stale), and NEXT. The panel keeps
## its nodes and its portrait's animation; only the text and the pose change.
## Its writes are offered only for a pane the viewer picked, never for one it
## merely follows herdr's focus to.
func _show_staff() -> void:
	var parts := HerdrFleet.split_key(navigator.active_key)
	var known := fleet.has(parts[0])
	var dimmed := fleet.is_stale(parts[0]) if known else stale
	var machine := fleet.label(parts[0]) if known and frame.several_machines() else ""
	var pane: PaneModel = frame.pane(navigator.active_key) if known else null
	_carry_pick_to_started(pane)
	var pick := OfficePaneInspector.Pick.FOLLOWING
	if pane != null and not navigator.picked_key.is_empty() and navigator.picked_key == pane.key:
		pick = OfficePaneInspector.Pick.PICKED if navigator.is_picked(pane) else OfficePaneInspector.Pick.REPLACED
	hud.inspector.show_pane(pane, machine, dimmed, pick)
	# Time-in-state ticks four times a second; only OfficeAttention writes it. A
	# shell has no agent state to time.
	var ticking := pane != null and not dimmed and not pane.launching() and not pane.provider.is_empty()
	attention.watch(parts[0], "" if pane == null else pane.pane_id, ticking)
	# NEXT names whom `N` picks next, and OfficeAttention ticks how long they have waited.
	var next := frame.pane(navigator.peek_next(frame))
	var next_machine := "" if next == null else next.machine()
	var label := fleet.label(next_machine) if next != null and frame.several_machines() else ""
	hud.inspector.show_next(null if next == null else NextModel.of(next, label, not fleet.read_only()))
	attention.watch_next(next_machine, "" if next == null else next.pane_id)


## The NEWS strip: the log's latest events, newest first, each clickable while
## its pane is still in this frame. A handful of lines, rebuilt every refresh.
func _show_news() -> void:
	var events := fleet.state_log().events()
	var items: Array[NewsItem] = []
	for index in range(events.size() - 1, maxi(events.size() - OfficeNews.ITEMS, 0) - 1, -1):
		items.append(NewsItem.of(events[index], frame))
	hud.show_news(items)


## The drawer's EVENTS page, only while it is the page shown: a hidden list is
## not laid out, and has no rows until it is first shown.
func _show_events() -> void:
	if hud.drawer_tab() != OfficeHud.DrawerTab.EVENTS or not hud.drawer_open():
		return
	var ledger := fleet.state_log()
	var shown := frame
	var pickable := func(key: String) -> bool: return shown.pane(key) != null
	hud.show_events(ledger.events(), pickable, navigator.active_key, ledger.opened_unix, frame.several_machines())


# --- the overview ----------------------------------------------------------------


## Open the overview over the world (PANES, `O`, `--overview=open`). It covers
## the world and both side columns without taking their room: nothing is laid
## out again, no map is planned for it, and the people keep walking under it.
## Hidden meanwhile: the world, the edge arrows and the world tooltip; the
## chips' reader stops at once (it reads nothing the overview covers). Not
## while the terminal monitor is open; answer mode on the staff panel stays.
func _open_overview() -> void:
	if hud.monitor_open() or hud.overview_open():
		return
	camera.cancel_press()
	_tips.hide_tip()
	hud.open_overview()
	world.visible = false
	_overview_tick.start()
	_show_overview()
	_watch_questions()
	_show_pointer()


## Close it: the chain comes back through _on_overview_closed(), as the
## overview's own `X  Esc` does.
func _close_overview() -> void:
	hud.close_overview()


## The overview closed, however: the world, its edge arrows and the chips'
## reader come back with a refresh.
func _on_overview_closed() -> void:
	_overview_tick.stop()
	world.visible = _world_shown()
	_refresh()


## The one predicate for whether the world shows: neither the overview nor the
## strategic view covers it. (The monitor covers it too, over everything, and
## the world keeps drawing under its backdrop.)
func _world_shown() -> bool:
	return not hud.overview_open() and not hud.strategic_open()


## For tools and tests (tools/perf_probe.gd), as refresh() is.
func open_overview() -> void:
	_open_overview()


func close_overview() -> void:
	_close_overview()


## The open overview, from this refresh's frame and the fleet's state log, at
## the log's clock now; nothing while it is closed. A refresh, the tick, a
## sort and a chip call this; it projects nothing. A refresh that built a new
## world (a pick on another machine) built it visible: it goes out of sight again.
func _show_overview() -> void:
	if not hud.overview_open():
		return
	world.visible = _world_shown()
	var model := OverviewModel.of(
		frame,
		fleet.state_log(),
		navigator.active_key,
		hud.overview.sort(),
		hud.overview.descending(),
		hud.overview.filter(),
		Time.get_ticks_msec()
	)
	hud.show_overview(model, art)


# --- the strategic view -----------------------------------------------------------


## Open the strategic view over the world rect (`S`, `--strategic=open`): the
## world hides (the people keep walking under it), and so do the edge arrows and
## the world tooltip; the chips' reader stops (it reads nothing the view
## covers) and the lens cannot come on (_may_lens()). SPACES, the drawer, the
## staff panel and NEWS stay where they are and keep working. Not under the
## terminal monitor.
func _open_strategic() -> void:
	if hud.monitor_open() or hud.strategic_open():
		return
	camera.cancel_press()
	_tips.hide_tip()
	hud.open_strategic()
	world.visible = _world_shown()
	_strategic_tick.start()
	_show_strategic()
	_watch_questions()
	_show_pointer()


## Close it: the chain comes back through _on_strategic_closed().
func _close_strategic() -> void:
	hud.close_strategic()


## The strategic view closed, however (`S`, Escape, a square clicked): the
## tick stops, the world comes back (unless the overview covers it) with a
## refresh, and the selected desk is panned into sight when the floor seats it.
## A square's pick comes after this (_on_strategic_picked()).
func _on_strategic_closed() -> void:
	_strategic_tick.stop()
	world.visible = _world_shown()
	_refresh()
	if floor_view != null and floor_view.seats.has(navigator.active_key):
		reveal(navigator.active_key, true)


## A square was clicked (the view closed already): pick that pane as a list
## row does, which shows its map and reveals its desk once drawn.
func _on_strategic_picked(key: String) -> void:
	_pick_from_list(key)


## The open strategic view, from this refresh's plan of the shown machine's
## map, its state and the state log at the clock now; nothing while it is
## closed. A refresh and the tick call this. A refresh that built a new world
## (another machine) built it visible: it goes out of sight again.
func _show_strategic() -> void:
	if not hud.strategic_open():
		return
	world.visible = _world_shown()
	var machine := navigator.shown_key
	var state := _building_state(machine) if fleet.has(machine) else MachineLiveness.State.OFFLINE
	var model := StrategicModel.of(
		plans.plan(machine),
		frame.building_of(machine),
		frame.several_machines(),
		state,
		fleet.state_log(),
		navigator.active_key,
		Time.get_ticks_msec()
	)
	hud.show_strategic(model)


## For tools and tests (tools/perf_probe.gd), as open_overview() is.
func open_strategic() -> void:
	_open_strategic()


func close_strategic() -> void:
	_close_strategic()


# --- the terminal monitor -------------------------------------------------------


## Open the terminal monitor on pane `key`, aimed at the terminal it holds now.
## One at a time: a request while one is open (another pane picked, another
## double-click) changes nothing.
func _open_monitor(key: String) -> void:
	if hud.monitor_open() or frame.pane(key) == null:
		return
	camera.cancel_press()
	_tips.hide_tip()
	hud.open_monitor(fleet.context_for(key, 0))
	_show_monitor()
	_show_pointer()


## Whether something is drawn over the agent card: its preview stops reading.
## The one-line panel counts: at every size, a pane's card is opened (Enter,
## `Open ⏎`) to be read.
func _card_covered() -> bool:
	return hud.card_compact() or hud.monitor_open()


## The monitor's pane as this refresh sees it, judged by its own machine.
func _show_monitor() -> void:
	if not hud.monitor_open():
		return
	var key := hud.monitor.pane_key()
	var machine := HerdrFleet.split_key(key)[0]
	var label := fleet.label(machine) if fleet.has(machine) and frame.several_machines() else ""
	var dimmed := fleet.is_stale(machine) if fleet.has(machine) else true
	hud.monitor.show_pane(frame.pane(key), label, dimmed)


# --- attention ----------------------------------------------------------------


func _observe_attention() -> void:
	attention_store.retain_machines(fleet.keys())
	var now := Time.get_ticks_msec()
	var wall_time := Time.get_unix_time_from_system()
	for building in frame.buildings:
		attention_store.observe(building.key, building.label, building.all_panes, not building.stale, now, wall_time)
	_show_attention()


func _show_attention() -> void:
	var now := Time.get_ticks_msec()
	var lines := history_cache.lines(fleet.state_log(), frame, _live_machines(), now)
	hud.show_attention(attention_store.current(now))
	hud.show_agents(frame, attention_store.active(), lines, navigator.active_key, now)


## Machine key -> online (not stale), for what the History lines may locate.
func _live_machines() -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for building in frame.buildings:
		result[building.key] = not building.stale
	return result


## A History line's View: pane `key`, if it is still the terminal the StateLog
## saw needing a human.
func _locate_history(key: String) -> void:
	var pane := frame.pane(key)
	if pane == null or fleet.is_stale(pane.machine()):
		return
	# Validate against the current model again at activation, not only when the
	# row was rendered: a pane id can now belong to a different terminal/session,
	# a run whose History is not the line that was clicked.
	for line in AgentHistory.of(fleet.state_log(), frame, _live_machines(), Time.get_ticks_msec()):
		if line.key == key and line.locatable:
			_pick_pane(pane)
			return
	_refresh()


## A row of the agent list: the pane it names now, picked as its desk would be.
func _pick_from_list(key: String) -> void:
	var pane := frame.pane(key)
	if pane != null:
		_pick_pane(pane)


## The one way a list or an attention record picks a pane: select that
## terminal, show its map and reveal its desk once drawn, like `N`. A pick,
## as on a desk, ends the card's answer mode first.
func _pick_pane(pane: PaneModel) -> void:
	camera.cancel_press()
	hud.inspector.leave_answer()
	navigator.locate(frame, pane)
	_refresh()


## A start from the card changes the picked pane's identity when herdr
## detects the agent, and again when the agent reports its first session: the
## same terminal, now with that agent in it. The viewer picked that shell and
## started this agent there, so the pick carries over to it, which keeps the
## card's answers to the agent open. Only this run's own start
## (HerdrFleet.launch_of()) while it is the pane's last write, in the same
## terminal, of the kind it named: from the shell the start was aimed at (herdr
## may not list the name yet), or on from a pick carried here before that has
## no session yet, to the agent under the start's own name. A session after
## the first (`/clear`), another kind, an agent herdr lists without that name,
## anything after another write: a new identity to pick again, as always.
func _carry_pick_to_started(pane: PaneModel) -> void:
	if pane == null or navigator.picked_key != pane.key or navigator.is_picked(pane):
		return
	var watch := fleet.launch_of(pane.key)
	if watch == null or fleet.last_write(pane.key) != watch.ticket or pane.terminal_id != watch.terminal_id:
		return
	if pane.provider != watch.kind:
		return
	if navigator.picked_identity == watch.ticket.context.identity_key:
		if not pane.agent_name in ["", watch.name]:
			return
	elif _carried_pick.is_empty() or navigator.picked_identity != _carried_pick or not _carried_sessionless:
		return
	elif pane.agent_name != watch.name:
		return
	_carried_pick = pane.identity_key()
	_carried_sessionless = pane.session == null or pane.session.identity_key().is_empty()
	navigator.pick_desk(pane.key, _carried_pick)


## Whether the card could answer or start something in the selected pane, as
## far as the office knows: a pane the viewer picked, on an office that may
## write, with an agent in it, or a shell with a kind to start there.
func _card_may_open() -> bool:
	var pane := frame.pane(navigator.active_key)
	if pane == null or not navigator.is_picked(pane) or fleet.read_only():
		return false
	return not pane.provider.is_empty() or (not pane.starting and not fleet.agent_kinds(pane.machine()).is_empty())


func _snooze_attention(id: String, seconds: int) -> void:
	attention_store.snooze(id, seconds, Time.get_ticks_msec())
	_show_attention()


func _hide_attention(id: String, is_hidden: bool) -> void:
	attention_store.set_hidden(id, is_hidden)
	_show_attention()


## The list's view and the flat view's folds, kept with the theme in the
## settings file, and like it never written by a capture or a test. Whether the
## drawer is open is not kept: every run starts with it closed.
func _remember_list() -> void:
	if not remember_theme:
		return
	var settings := ConfigFile.new()
	# Loading first keeps anything else the config file holds.
	settings.load(settings_path)
	settings.set_value("agent_list", "flat", hud.agent_list.view == AgentListModel.View.FLAT)
	settings.set_value("agent_list", "folds", hud.agent_list.flat_folds())
	settings.save(settings_path)


## The top bar's chime switch was clicked: the chime is `on` from now on, the
## switch says so, and the choice is kept in the settings file for the next
## run (never by a capture or a test, like the theme).
func _switch_chime(on: bool) -> void:
	alerts.options.chime = on
	hud.show_chime(on)
	if not remember_theme:
		return
	var settings := ConfigFile.new()
	# Loading first keeps anything else the config file holds.
	settings.load(settings_path)
	settings.set_value(OfficeAlerts.CHIME_SECTION, OfficeAlerts.CHIME_KEY, on)
	settings.save(settings_path)


func _restore_list() -> void:
	if not remember_theme:
		return
	var settings := ConfigFile.new()
	if settings.load(settings_path) != OK:
		return
	var flat: Variant = settings.get_value("agent_list", "flat", true)
	var saved: Variant = settings.get_value("agent_list", "folds", {})
	var folds: Dictionary[String, bool] = {}
	if saved is Dictionary:
		var entries: Dictionary = saved
		for key: Variant in entries:
			var folded: Variant = entries[key]
			if key is String and folded is bool:
				folds[str(key)] = folded == true
	var flat_view: bool = flat is not bool or flat == true
	hud.agent_list.restore(flat_view, folds)
	# The drawer starts closed on every run: an `agent_list/open` an earlier
	# version saved is not read, nor written any more.


# --- the lens and the hover mark ----------------------------------------------


## Whether the lens may be on: not under the monitor, the OVERVIEW or the
## strategic view, and not while a text field has the keyboard (`L` is typing there).
func _may_lens() -> bool:
	if hud.monitor_open() or hud.overview_open() or hud.strategic_open():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)


## The lens came on or went off: the top bar says so, the chip's tooltip goes
## away while it is on, and the world shows it or puts everything back.
func _on_lens(held: bool) -> void:
	if held:
		_tips.hide_tip()
	hud.bar.show_lens(held)
	_show_lens()


## Draw the lens on the shown map while it is held: each seat's line
## (OfficeLens.text_for(), the state log's wait at the lens's clock) and each
## table's wash (OfficeLens.tone_for()). A refresh and the lens's tick call it;
## let go, the first call puts everything back and the next ones do nothing.
func _show_lens() -> void:
	if floor_view == null or lens == null:
		return
	if not lens.held:
		if _lens_shown:
			_lens_shown = false
			var none: Dictionary[String, String] = {}
			var plain: Dictionary[String, StringName] = {}
			floor_view.show_lens(false, none, plain)
		return
	_lens_shown = true
	var now := lens.stamp()
	var dropped := _frozen()
	var ledger := fleet.state_log()
	var texts: Dictionary[String, String] = {}
	for key: String in floor_view.seats:
		var pane := frame.pane(key)
		if pane != null:
			texts[key] = OfficeLens.text_for(pane, ledger.track(key), dropped, now)
	var tones: Dictionary[String, StringName] = {}
	var map := frame.map_of(navigator.shown_key)
	if map != null:
		for room in map.rooms:
			tones[room.key] = OfficeLens.tone_for(room, dropped)
	floor_view.show_lens(true, texts, tones)


## A HUD line about pane `key` is under the mouse (empty: none any more).
func _point_at_pane(key: String) -> void:
	_pointed_pane = key
	_pointed_zone = ""
	_show_pointer()


## An edge arrow for zone `key` is under the mouse (empty: none any more).
func _point_at_zone(key: String) -> void:
	_pointed_zone = key
	_pointed_pane = ""
	_show_pointer()


## Show what the hovered HUD line names: a pane seated on the shown map gets
## the dashed frame (OfficeFloorView.point()); one on another machine, or a
## zone (an edge arrow's), outlines that zone's SPACES row; the strategic
## view dashes the same pane's square. Nothing under the monitor or the
## OVERVIEW, and nothing for a pane that has gone. Only points: no selection,
## no map change, no pan, nothing read or written.
func _show_pointer() -> void:
	if floor_view == null:
		return
	var desk := ""
	var zone_key := ""
	if not hud.monitor_open() and not hud.overview_open():
		if not _pointed_pane.is_empty() and frame.pane(_pointed_pane) != null:
			var on := frame.find_zone(frame.zone_of(_pointed_pane))
			if on != null and on.building.key == navigator.shown_key:
				desk = _pointed_pane if floor_view.seats.has(_pointed_pane) else ""
			elif on != null:
				zone_key = on.zone_model.key
		elif not _pointed_zone.is_empty() and frame.find_zone(_pointed_zone) != null:
			zone_key = _pointed_zone
	floor_view.point(desk)
	hud.point_strategic(desk)
	hud.spaces.point(zone_key)
