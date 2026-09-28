extends Node2D
## Asset showroom with explicit mock data. Not a Herdr client.
##
## A fixed 800x480 logical showroom: the project's canvas_items stretch scales it
## to whatever window it is opened in, and the pack's textures are the same at
## every window size, so a resize has nothing to rebuild.

## A table's near edge, from the top of its room; the same as the live office.
const TABLE_NEAR_Y := 232
const TABLE_RUG_Y := 84
const TABLE_RUG_ROWS := 5
const TABLE_WIDTH := 256.0
const ROOM_WIDTH := 288.0
## The showroom's own size.
const SHOWROOM := Vector2(800, 480)
## The HUD is laid out on a shorter screen than the showroom, so the staff
## panel ends a gap above the state strip instead of touching or covering it.
## The panel is its one line there, as at every size until it is opened:
## at full height it would cover the rooms. (The screen is also under the HUD's
## `staff_tall_from`, which only decides where an opened panel leaves the NEWS
## strip, and the showroom has none.)
const HUD_SCREEN := Vector2(800, 392)
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
## `--overview=open`: the mock overview's span, and its panes. Each pane is
## [machine, pane id, agent, space, tab, minute it appears, [minute, state]…]:
## its state from that minute on (the first one at minute 0 is the baseline,
## whose start this office never saw). bee drops at BEE_GONE_AT.
const MOCK_MINUTES := 120
const BEE_GONE_AT := 80
const MOCK_PANES: Array[Array] = [
	[
		"local",
		"api:p1",
		"claude",
		"api",
		"main",
		0,
		[
			[0, "blocked"],
			[10, "working"],
			[25, "blocked"],
			[35, "idle"],
			[50, "blocked"],
			[60, "working"],
			[80, "blocked"],
			[90, "done"],
			[108, "blocked"]
		]
	],
	["local", "hud:p1", "pi", "hud", "deploy", 0, [[0, "idle"], [30, "working"], [98, "blocked"]]],
	["local", "web:p1", "codex", "web", "ui", 0, [[0, "working"], [100, "done"]]],
	["local", "web:p2", "codex", "web", "rev", 0, [[0, "idle"], [60, "working"], [118, "done"]]],
	["local", "api:p2", "claude", "api", "tests", 0, [[0, "idle"], [5, "blocked"], [15, "working"]]],
	["local", "api:p3", "pi", "api", "tests", 0, [[0, "idle"], [111, "working"]]],
	["local", "infra:p1", "codex", "infra", "main", 0, [[0, "working"], [55, "idle"]]],
	["local", "ops:p1", "claude", "ops", "monitor", 0, [[0, "working"], [72, "idle"]]],
	["local", "lab:p1", "codex", "research", "lab", 30, [[30, "idle"], [70, "working"], [90, "idle"]]],
	["bee", "etl:p1", "claude", "data", "etl", 0, [[0, "working"], [20, "blocked"], [30, "working"]]],
]


## The mock office the top bar counts and the OVERVIEW draws: one state log,
## the frame of what it leaves each pane in, and its clock.
class MockOffice:
	extends RefCounted
	var ledger := StateLog.new()
	var frame := OfficeFrame.new()
	## The end of the mock's span on the log's own clock (msec), and when it began (unix).
	var now_msec := 0
	var start_unix := 0.0


@export_file("*.json") var manifest_path := "res://assets/daylight/manifest.json"

var art: ArtPack
var pen: OfficeDraw
var world: Node2D
var stale := false
## The floor's two parts: what lies on it, and what stands on it (y-sorted).
var ground: Node2D
var sorted: Node2D


func _ready() -> void:
	var args := AppArgs.current()
	manifest_path = args.text("pack", manifest_path)
	stale = stale or args.flag("offline")
	art = ArtPack.from_manifest(manifest_path)
	if art == null:
		push_error("The showroom has no art pack to show: " + manifest_path)
		get_tree().quit(1)
		return
	pen = OfficeDraw.new(art)
	world = Node2D.new()
	add_child(world)
	ground = Node2D.new()
	ground.name = "Ground"
	world.add_child(ground)
	sorted = Node2D.new()
	sorted.name = "Sorted"
	sorted.y_sort_enabled = true
	world.add_child(sorted)
	pen.box(self, Rect2(0, 32, 800, 448), ArtContract.CREAM_SHADOW)
	# Keep the office layer over the background, below the screen-space UI.
	move_child(world, get_child_count() - 1)
	var hud := _hud()
	var api := room(Vector2(16, 48), "API", "main", true)
	var web_at := Vector2(320, 48)
	var web := room(web_at, "WEB", "feat/ui", false)
	# Two bystanders prove the sorting is positional, not a per-seat rule: one
	# stands behind the WEB table's right end (the table hides their legs), one
	# in front of the API table's left end (they hide the apron and a leg). The
	# two done workers (WEB far, API near) sit, with their paper on the desk.
	var curly := AvatarLook.with_slots(
		{
			AvatarLook.HAIR_STYLE: &"curl",
			AvatarLook.HAIR_COLOUR: &"auburn",
			AvatarLook.TOP: &"cream",
			AvatarLook.LEGS: &"brown"
		}
	)
	bystander(web.position + Vector2(TABLE_WIDTH - 18, -OfficeTable.SURFACE_DEPTH + 14), AvatarLook.FRONT, curly)
	var capped := AvatarLook.with_slots(
		{
			AvatarLook.HEADWEAR: &"cap",
			AvatarLook.HEADWEAR_COLOUR: &"sea",
			AvatarLook.TOP: &"terra",
			AvatarLook.LEGS: &"taupe"
		}
	)
	bystander(api.position + Vector2(14, 30), AvatarLook.BACK, capped)
	var hall := pen.layer(ground, Vector2(16, 336))
	for x in 19:
		hall.set_cell(Vector2i(x, 0), 0, art.cell(ArtContract.FLOOR_WALKWAY))
	legend(hud.world_rect(), web_at.x + ROOM_WIDTH + 16)
	if stale:
		world.modulate = art.stale_tint
		for person: PixelPerson in get_tree().get_nodes_in_group("office_actors"):
			person.pause()
	state_strip()
	# The top bar and the overview read a mock state log (the live office's
	# comes from the fleet): two hours, a pane that appeared, a machine that dropped.
	var mock := _mock_office()
	hud.show_totals(OfficeTotals.of(mock.frame, _mock_machines(mock), mock.ledger))
	hud.inspector.show_next(_mock_next(mock.frame))
	if args.text("overview") == "open":
		# Hidden under it, as the office hides its world: the overview stops
		# above the staff panel, and the rooms would show in the gap.
		world.visible = false
		hud.open_overview()
		hud.show_overview(_mock_overview(mock), art)
	print(
		"PREVIEW_OK: 2 shared tables, 8 seats, 5 workers (2 done), 1 shell, 2 vacant, 2 bystanders, 5 Herdr states, starting/offline, generic fallback"
	)
	if args.has("capture"):
		await CaptureDriver.run(self, args, "preview")
	elif args.has("record-dir"):
		await _record(args.text("record-dir"))


## `--record-dir=`: 28 rendered frames at six a second, for an animation strip.
func _record(target: String) -> void:
	DirAccess.make_dir_recursive_absolute(target)
	for frame in 28:
		await get_tree().create_timer(1.0 / 6.0).timeout
		await RenderingServer.frame_post_draw
		var path := target.path_join("%03d.png" % frame)
		var error := get_viewport().get_texture().get_image().save_png(path)
		if error != OK:
			push_error("Cannot save the animation frame %s: %s" % [path, error_string(error)])
			get_tree().quit(1)
			return
	print("RECORD_OK: 28 rendered frames")
	get_tree().quit()


## One tab: a shared table with two seat columns and a station on both sides
## of each. `split` (API) seats three workers and a shell and is selected; the
## other (WEB) seats two workers and leaves its near seats vacant.
func room(at: Vector2, title: String, branch: String, split: bool) -> OfficeTable:
	var floor_layer := pen.layer(ground, at)
	for y in 9:
		for x in 9:
			floor_layer.set_cell(Vector2i(x, y), 0, art.cell(ArtContract.FLOOR_WOOD[(x + y * 2) % 3]))
	# The same shell the live office lays: two courses of brick behind the row
	# of tables, and a side wall down each edge. Furniture, bound to nothing.
	var shell := pen.layer(ground, at)
	for y in 9:
		shell.set_cell(Vector2i(0, y), 0, art.cell(ArtContract.WALL_SIDE_LEFT))
		shell.set_cell(Vector2i(8, y), 0, art.cell(ArtContract.WALL_SIDE_RIGHT))
	for x in 9:
		var end: StringName = ArtContract.WALL_ENDS[0 if x == 0 else 2 if x == 8 else 1]
		for course in ArtContract.WALL_COURSES.size():
			shell.set_cell(
				Vector2i(x, course), 0, art.cell(ArtContract.wall_cell(ArtContract.WALL_COURSES[course], end))
			)
	# One room stands in for the outer wall, with the lift door on it, the other
	# for an inner one with a window. A 288-unit room cannot hold every piece
	# without one standing in front of another, so the two share them out.
	if split:
		pen.prop(ground, ArtContract.PROP_DOOR, at + Vector2(56, OfficeShell.DOOR_FOOT))
		pen.decor(sorted, ArtContract.PROP_PLANT, at + Vector2(ROOM_WIDTH - 56, OfficeShell.PLANT_FOOT))
	else:
		pen.prop(ground, ArtContract.PROP_WINDOW, at + Vector2(80, OfficeShell.WINDOW_FOOT))
		pen.decor(sorted, ArtContract.PROP_CABINET, at + Vector2(ROOM_WIDTH - 56, OfficeShell.CABINET_FOOT))
	var left := (ROOM_WIDTH - TABLE_WIDTH) / 2.0
	pen.rug(ground, at + Vector2(left, TABLE_RUG_Y), int(TABLE_WIDTH / 32.0), TABLE_RUG_ROWS)
	var columns: Array = [TABLE_WIDTH / 2.0 - 32.0, TABLE_WIDTH / 2.0 + 32.0]
	var table := pen.table(sorted, ground, title, at + Vector2(left, TABLE_NEAR_Y), TABLE_WIDTH, columns)
	table.set_selected(split)
	pen.prop(ground, ArtContract.PROP_SIGN, at + Vector2(ROOM_WIDTH / 2.0, OfficeShell.SIGN_FOOT))
	pen.clipped(
		ground,
		title,
		at + Vector2(104, OfficeShell.TITLE_TOP),
		Vector2(80, 17),
		13,
		ArtContract.INK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	pen.label(
		ground, branch, at + Vector2(96, 70), Vector2(96, 12), 10, ArtContract.WOOD_DARK, HORIZONTAL_ALIGNMENT_CENTER
	)
	var seats: Dictionary[String, OfficeStation] = {}
	for column in columns.size():
		for side: String in OfficeTable.SIDES:
			seats["%d/%s" % [column, side]] = pen.station(sorted, table, column, side)
	# WEB's first far worker is done: they sit with paper on the desk, as API's
	# near done worker does. Both far-2 workers are blocked, under a bubble; the
	# bubble shows the wait and the patience bar; the showroom has no clock, so
	# they show one sample wait.
	var first := ArtContract.STATE_WORKING if split else ArtContract.STATE_DONE
	seats["0/far"].furnish("claude" if split else "pi", first, false, false, "far-1")
	seats["1/far"].furnish("codex" if split else "claude", ArtContract.STATE_BLOCKED, split, false, "far-2")
	seats["1/far"].bubble().show_wait(240.0)
	if split:
		seats["0/near"].furnish("", ArtContract.STATE_IDLE, false, false, "near-1")
		seats["1/near"].furnish("pi", ArtContract.STATE_DONE, false, false, "near-2")
	# API is the tab its workspace has open, with herdr's focus on its first
	# seat; WEB is a tab nobody has open, so every lamp on it is dimmed. The two
	# near seats of WEB carry no pane at all: a chair, no screen, no lamp.
	for spot: String in seats:
		var level := OfficeTable.Lamp.ON if split else OfficeTable.Lamp.DIM
		if not seats[spot].vacant:
			seats[spot].light(OfficeTable.Lamp.FOCUS if split and spot == "0/far" else level)
	return table


## Someone standing on the floor at `at`, facing `orientation`.
func bystander(at: Vector2, orientation: StringName, wearing: AvatarLook) -> void:
	var person: PixelPerson = OfficeDraw.PERSON_SCENE.instantiate()
	person.name = "Bystander"
	var look := wearing.copy()
	look.context = AvatarLook.STAND
	look.orientation = orientation
	person.configure(art.people, "generic", look)
	person.position = at
	sorted.add_child(person, true)
	person.play_state(ArtContract.ANIMATION_IDLE)
	person.add_to_group("office_actors")


## The legend: what the showroom's pieces stand for, on a panel of its own in
## the world's room (`area`, the HUD's world_rect()) right of the rooms from
## `left` on, where no HUD panel covers it. Ink on the pack's panel reads in
## every pack, as the state strip does.
func legend(area: Rect2, left: float) -> void:
	var lines := PackedStringArray(
		[
			"SPACES ARE FLOORS",
			"TABS ARE SHARED TABLES",
			"PANES ARE SEATS",
			"",
			"LAPTOPS ARE TERMINALS",
			"$_ = SHELL",
			"THE LIT LAMP IS HERDR'S FOCUS",
			"",
			"PAPER = DONE, NOT YET SEEN",
			"BUBBLE = BLOCKED (WAIT + PATIENCE)",
			"THE TWO BYSTANDERS ARE NOBODY'S AGENT",
		]
	)
	# Its right edge lines up with the state strip's and the staff panel's.
	var corner := Vector2(minf(area.end.x, SHOWROOM.x - 16), area.end.y)
	var bounds := Rect2(Vector2(left, area.position.y), corner - Vector2(left, area.position.y))
	pen.panel(self, bounds)
	var text := Label.new()
	# Wrapped before it is sized: a line is only as wide as the panel.
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = "\n".join(lines)
	pen.style(text, 9, ArtContract.INK)
	text.position = bounds.position + Vector2(8, 6)
	text.size = bounds.size - Vector2(16, 12)
	add_child(text)


## The showroom shows the office's own bar and staff panel, fed mock data, so a
## HUD change is visible here without a herdr session. The minimap and the
## agent list's drawer need a fleet to say anything, so they stay out, and the
## world's room keeps their place.
func _hud() -> OfficeHud:
	var hud: OfficeHud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.dress(art, pen.font)
	# No NEWS strip: it would stand on the status line under the room. Said
	# before fit(), so the staff panel is laid out without it.
	hud.news_wanted = false
	hud.fit(HUD_SCREEN)
	hud.floors.visible = false
	hud.right_column.visible = false
	hud.show_bar(art.display_name.to_upper(), "PREVIEW / MOCK DATA", false)
	var pane := PaneModel.new()
	pane.pane_id = "w1:p2"
	pane.key = "local:w1:p2"
	pane.provider = "codex"
	pane.state = "idle" if stale else "blocked"
	pane.workspace_label = "API"
	pane.tab_label = "DEV"
	pane.cwd = "/home/mock/herdstead"
	pane.terminal_title = "Source: mock fixture"
	hud.inspector.show_pane(pane, "", stale)
	hud.inspector.set_duration("12m")
	return hud


func state_strip() -> void:
	pen.panel(self, Rect2(16, 384, 768, 84))
	pen.label(self, "STATE SAMPLES", Vector2(26, 390), Vector2(90, 12), 10, ArtContract.SLATE)
	# Herdr's five states, then the two display overlays that are not herdr's.
	var states: Array[StringName] = ArtContract.STATES.duplicate()
	states.append_array([ArtContract.UI_STARTING, ArtContract.UI_OFFLINE])
	for index in states.size():
		var state := states[index]
		var at := Vector2(152 + index * 84, 448)
		var drawn := art.state(state)
		var starting := state == ArtContract.UI_STARTING
		var animation := art.animation_for_state(state, starting)
		var who := "unrecognized-provider" if starting else "codex"
		var sample := pen.portrait(self, who, animation, at)
		if state == ArtContract.UI_OFFLINE:
			var holder: Node2D = sample.get_parent()
			holder.modulate = art.stale_tint
			sample.pause()
		pen.icon(self, drawn.badge if drawn != null else state, at + Vector2(24, -26))
		pen.label(
			self,
			"UNREAD" if state == ArtContract.STATE_DONE else str(state).to_upper(),
			at + Vector2(-32, 4),
			Vector2(64, 12),
			10,
			ArtContract.INK,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	# What this pack actually holds, in its own pixels: geometry stays in
	# density-1 units, so only these numbers move with the density. The tiles are
	# the pack's own art; the frames belong to the shared pixel people and carry
	# that family's density (one pixel per unit), not this pack's.
	var frame := art.people.frame_size * art.people.density
	var sampling := "Nearest" if art.filter == CanvasItem.TEXTURE_FILTER_NEAREST else "Linear + mips"
	var built := "%dpx tiles\n%dx%d frames\n%s" % [art.tile_size * art.density, frame.x, frame.y, sampling]
	pen.label(self, built, Vector2(26, 411), Vector2(92, 42), 10, ArtContract.SLATE)


## A state log of MOCK_PANES on a clock of its own, replayed in time order,
## and the frame of the panes as it leaves them two hours in: Local live, bee
## dropped at BEE_GONE_AT.
func _mock_office() -> MockOffice:
	var mock := MockOffice.new()
	var ledger := mock.ledger
	var start_msec := 1000
	# A round half hour, two hours ago, so the axis reads like a working morning.
	var start_unix := floorf(Time.get_unix_time_from_system() / 1800.0) * 1800.0 - MOCK_MINUTES * 60.0
	var machines: Dictionary[String, Dictionary] = {"local": {}, "bee": {}}
	var changes: Dictionary[int, Array] = {}
	for pane: Array in MOCK_PANES:
		var steps: Array = pane[6]
		for step: Array in steps:
			var minute: int = step[0]
			if not changes.has(minute):
				changes[minute] = []
			changes[minute].append([pane, step[1]])
	if not changes.has(BEE_GONE_AT):
		changes[BEE_GONE_AT] = []
	var minutes: Array[int] = []
	minutes.assign(changes.keys())
	minutes.sort()
	# In time order: the log's clock never runs backwards.
	for minute in minutes:
		if minute == BEE_GONE_AT:
			ledger.observe("bee", "bee", false, [], start_msec + minute * 60000, start_unix + minute * 60.0)
		var touched: Dictionary[String, bool] = {}
		for change: Array in changes[minute]:
			var pane: Array = change[0]
			var machine: String = pane[0]
			var kept: Dictionary = machines[machine]
			var key := HerdrFleet.pane_key(machine, str(pane[1]))
			var sighting: StateLog.Sighting = kept.get(key)
			if sighting == null:
				sighting = StateLog.Sighting.new()
				sighting.pane_key = key
				sighting.identity = "term-" + key
				sighting.agent = pane[2]
				sighting.space = pane[3]
				sighting.tab = pane[4]
				kept[key] = sighting
			sighting.status = change[1]
			# The baseline's start is unknown; every later one is seen.
			sighting.since_unix = -1.0 if minute == 0 else start_unix + minute * 60.0
			touched[machine] = true
		for machine: String in touched:
			if machine == "bee" and minute >= BEE_GONE_AT:
				continue
			_observe_mock(ledger, machine, machines[machine], start_msec + minute * 60000, start_unix + minute * 60.0)
	var frame := mock.frame
	for machine: String in machines:
		var building := BuildingModel.new()
		building.key = machine
		building.label = "Local" if machine == "local" else machine
		building.stale = machine == "bee"
		var kept: Dictionary = machines[machine]
		building.panes = kept.size()
		for key: String in kept:
			var sighting: StateLog.Sighting = kept[key]
			var model := PaneModel.new()
			model.key = key
			model.pane_id = HerdrFleet.split_key(key)[1]
			model.provider = sighting.agent
			model.state = sighting.status
			# When that state began, as the office stamps it: NEXT's order.
			model.state_since = sighting.since_unix
			model.workspace_id = model.pane_id.get_slice(":", 0)
			model.workspace_label = sighting.space
			model.tab_label = sighting.tab
			building.all_panes.append(model)
			frame.pane_by_key[key] = model
		# As OfficeProjection.frame(): a dropped machine's panes are not live.
		if not building.stale:
			frame.live_panes.append_array(building.all_panes)
		frame.buildings.append(building)
	mock.now_msec = start_msec + MOCK_MINUTES * 60000
	mock.start_unix = start_unix
	return mock


## The mock's machines as the top bar's MACHINES says them: Local answering
## now, bee last heard from when it dropped.
func _mock_machines(mock: MockOffice) -> Array[OfficeTotals.MachineRow]:
	var local := OfficeTotals.MachineRow.new()
	local.label = "Local"
	local.state = MachineLiveness.State.LIVE
	local.heard_since = Time.get_unix_time_from_system()
	var bee := OfficeTotals.MachineRow.new()
	bee.label = "bee"
	bee.state = MachineLiveness.State.OFFLINE
	bee.heard_since = mock.start_unix + BEE_GONE_AT * 60.0
	return [local, bee]


## Whom NEXT names in the mock, by the office's own rule
## (OfficeNavigator.peek_next(), nothing picked yet); null when nobody waits.
## The machine is named as the office names it: only when there are several.
func _mock_next(frame: OfficeFrame) -> NextModel:
	var next := frame.pane(OfficeNavigator.new().peek_next(frame))
	if next == null:
		return null
	var label := ""
	if frame.several_machines():
		for building in frame.buildings:
			if building.key == next.machine():
				label = building.label
	return NextModel.of(next, label)


## The overview model of the mock two hours in, the first blocked pane selected.
func _mock_overview(mock: MockOffice) -> OverviewModel:
	var selected := HerdrFleet.pane_key("local", "api:p1")
	return OverviewModel.of(
		mock.frame, mock.ledger, selected, OverviewModel.Sort.STATE, false, OverviewModel.Filter.ALL, mock.now_msec
	)


func _observe_mock(ledger: StateLog, machine: String, kept: Dictionary, now_msec: int, now_unix: float) -> void:
	var seen: Array[StateLog.Sighting] = []
	for sighting: StateLog.Sighting in kept.values():
		seen.append(sighting)
	ledger.observe(machine, "Local" if machine == "local" else machine, true, seen, now_msec, now_unix)
