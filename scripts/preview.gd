extends Node2D
## Asset showroom with explicit mock data. Not a Herdr client.
##
## The default 1920x960 capture gives the expanded canvas 960x480 logical
## units at 2x. Two zone close-ups use that width, without the machine shell's
## entry band or extra furniture. Every workstation stays at its native size.

## Each zone's pod: four columns, eight complete workstations.
const TABLE_COLUMNS := 4
## The pod stands one floor cell from the zone's left edge, with a
## small clear band above it. The zones' sizes come from OfficeTable.measure(),
## including the tab label and the lower partition, rounded to floor cells.
const POD_PAD := Vector2(FloorLayoutPolicy.GRID, 8)
const ZONE_GAP := 16.0
## The showroom's own size.
const SHOWROOM := Vector2(960, 480)
const STRIP := Rect2(16, SHOWROOM.y - 80, SHOWROOM.x - 32, 72)
## The HUD is laid out on a shorter screen than the showroom, so the staff
## panel ends a gap above the state strip instead of touching or covering it.
## Below staff_tall_from the bar and panel use their compact forms; the
## showroom keeps both, and leaves the state samples outside the HUD.
const HUD_SCREEN := Vector2(SHOWROOM.x, STRIP.position.y - 2)
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
## The map's two parts: what lies on it, and what stands on it (y-sorted).
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
	pen.box(self, Rect2(Vector2.ZERO, SHOWROOM), ArtContract.DEEP)
	# Keep the office layer over the background, below the screen-space UI.
	move_child(world, get_child_count() - 1)
	var hud := _hud()
	var measured := OfficeTable.measure(TABLE_COLUMNS)
	var frame := measured.render_rect.grow(OfficeTable.FRAME_OUTSIDE)
	var needed := Vector2(
		POD_PAD.x + measured.reserved_rect.size.x,
		POD_PAD.y + frame.size.y + OfficeDraw.TAB_LABEL_HEIGHT + OfficeShell.PARTITION_DRAW
	)
	var cells := Vector2i((needed / FloorLayoutPolicy.GRID).ceil())
	var zone_size := Vector2(cells * FloorLayoutPolicy.GRID)
	var at := Vector2(roundf((SHOWROOM.x - zone_size.x * 2.0 - ZONE_GAP) / 2.0), hud.world_rect().position.y)
	zone(at, 1, "API", "main", true, measured, cells)
	zone(at + Vector2(zone_size.x + ZONE_GAP, 0), 2, "WEB", "feat/ui", false, measured, cells)
	if stale:
		world.modulate = art.stale_tint
		for child in sorted.get_children():
			if child is OfficeStation:
				var station: OfficeStation = child
				station.freeze(true)
	state_strip()
	# The top bar and the overview read a mock state log (the live office's
	# comes from the fleet): two hours, a pane that appeared, a machine that dropped.
	var mock := _mock_office()
	var portraits := PortraitBarModel.of(mock.frame, "")
	hud.show_portraits(portraits, OfficeTotals.of(mock.frame, _mock_machines(mock)), "local")
	var blocked := PackedStringArray()
	for card in portraits.of_group(PortraitBarModel.Group.BLOCKED):
		blocked.append(card.key)
	hud.show_waits(OfficeAttention.waits_of(mock.ledger, blocked, mock.now_msec))
	hud.inspector.show_next(_mock_next(mock.frame))
	if args.text("overview") == "open":
		# Hidden under it, as the office hides its world: the overview stops
		# above the staff panel, and the zones would show in the gap.
		world.visible = false
		hud.open_overview()
		hud.show_overview(_mock_overview(mock), art)
	print(
		(
			"PREVIEW_OK: 2 zones, 2 pods, 16 seats, 11 workers (3 done, 3 blocked), 1 shell, 4 vacant,"
			+ " 5 Herdr states, starting/offline, generic whole-image portraits"
		)
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


## One workspace close-up: its carpet, partitions and sign, and one measured
## pod with its tab's name below. Both logical rows face the viewer. `split`
## (API) seats seven workers and a shell and is selected; WEB seats four
## workers and leaves its lower row vacant. No second body or machine shell
## is fitted around these complete images.
func zone(
	at: Vector2, number: int, space: String, tab: String, split: bool, measured: DeskMeasure, cells: Vector2i
) -> OfficeTable:
	var floor_layer := pen.layer(ground, at)
	for y in cells.y:
		for x in cells.x:
			floor_layer.set_cell(Vector2i(x, y), 0, art.cell(ArtContract.FLOOR_WOOD[(x + y * 2) % 3]))
	# The zone, placed by hand where a plan would place it, and drawn by the
	# office's own helpers: its partitions in a y-sorted holder (each piece sorts
	# by its own foot), its sign at the top-left post's foot, cut short of the
	# top-right post.
	var placed := ZonePlacement.new()
	placed.zone_key = space
	placed.cells = Rect2i(Vector2i.ZERO, cells)
	# Its carpet inside the partitions, in the family its key wears, flat on
	# the floor under the pod, as the office lays it (OfficeFloorView).
	var carpet := NinePatchRect.new()
	carpet.name = "Carpet" + space
	carpet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lies := OfficeShell.carpet_rect(placed)
	pen.dress_nine_patch(carpet, art.ui_sprite(OfficeZoneSign.carpet_of(space)), lies.size)
	carpet.position = at + lies.position
	ground.add_child(carpet)
	var partitions := Node2D.new()
	partitions.name = "Partitions" + space
	partitions.y_sort_enabled = true
	partitions.position = at
	sorted.add_child(partitions)
	var post := Vector2.ZERO
	var posted := false
	for piece in OfficeShell.partition_pieces(placed):
		pen.prop(partitions, piece.id, piece.foot)
		if piece.id == ArtContract.PROP_PARTITION_POST and not posted:
			post = piece.foot
			posted = true
	var model := ZoneModel.new()
	model.key = space
	model.number = number
	model.label = space
	var board: OfficeZoneSign = OfficeFloorView.ZONE_SIGN_SCENE.instantiate()
	board.name = "Sign" + space
	board.dress(pen)
	board.position = at + post
	sorted.add_child(board)
	var right_post := OfficeShell.drawn(pen, ArtContract.PROP_PARTITION_POST, OfficeShell.right_post(placed))
	board.show_zone(model, right_post.position.x - post.x)
	# A close-up needs the whole drawing and its frame, not the live map's
	# walking reservation above and below. The tab name clears the frame, and
	# the cell-rounded zone leaves it clear of the bottom partition as well.
	var frame := measured.render_rect.grow(OfficeTable.FRAME_OUTSIDE)
	var origin := at + POD_PAD - Vector2(0, frame.position.y)
	var columns: Array = measured.columns
	var table := pen.table(sorted, ground, space, origin, measured.table_width, columns)
	table.set_selected(split)
	var title := pen.tab_label(ground, origin + Vector2(0, frame.end.y), measured.table_width)
	title.name = "Tab" + space
	title.text = tab.to_upper()
	var seats: Dictionary[String, OfficeStation] = {}
	for column in columns.size():
		for side: String in OfficeTable.SIDES:
			seats["%d/%s" % [column, side]] = pen.station(sorted, table, column, side)
	# WEB's first far worker is done, as are API's near done workers
	# (one on the pod's last desk). A far worker on each pod
	# and a near one on API are blocked, with a chip; the showroom has no clock,
	# so API's chips show one sample wait each, and WEB's blocked worker, whose
	# start this office never saw, shows the badge alone.
	var first := ArtContract.STATE_WORKING if split else ArtContract.STATE_DONE
	seats["0/far"].furnish("claude" if split else "pi", first, false, false, "far-1")
	seats["1/far"].furnish("codex" if split else "claude", ArtContract.STATE_BLOCKED, split, false, "far-2")
	if split:
		seats["1/far"].chip().show_wait(240.0)
	seats["2/far"].furnish("pi" if split else "codex", ArtContract.STATE_WORKING, false, false, "far-3")
	seats["3/far"].furnish("claude" if split else "pi", ArtContract.STATE_IDLE, false, false, "far-4")
	if split:
		seats["0/near"].furnish("", ArtContract.STATE_IDLE, false, false, "near-1")
		seats["1/near"].furnish("pi", ArtContract.STATE_DONE, false, false, "near-2")
		seats["2/near"].furnish("codex", ArtContract.STATE_BLOCKED, false, false, "near-3")
		seats["2/near"].chip().show_wait(4000.0)
		seats["3/near"].furnish("claude", ArtContract.STATE_DONE, false, false, "near-4")
	# API is the tab its workspace has open, with herdr's focus on its first
	# seat; WEB is a tab nobody has open, so its focus underlines are dimmed. The
	# four near seats of WEB carry no pane: the complete empty workstation image.
	# The mock panes have no titles: each is called by its tab (DisplayName).
	for spot: String in seats:
		var level := OfficeTable.Lamp.ON if split else OfficeTable.Lamp.DIM
		if not seats[spot].vacant:
			seats[spot].light(OfficeTable.Lamp.FOCUS if split and spot == "0/far" else level)
			seats[spot].show_name(tab)
	return table


## The legend shares the state strip's panel, beside rather than over its
## native-size portraits. Four short lines leave the full width to the pods.
func legend(parent: Node, bounds: Rect2) -> void:
	var lines := PackedStringArray(
		[
			"SPACES = ZONES / TABS = PODS / PANES = SEATS",
			"NO PERSON = SHELL OR VACANT / ONE GENERIC LOOK",
			"CHIP = BLOCKED + WAIT / UNREAD = DONE, NOT SEEN",
			"BRIGHT UNDERLINE = HERDR'S FOCUS / HOVER = NAME",
		]
	)
	var text := pen.clipped(parent, "\n".join(lines), bounds.position, bounds.size, 8, ArtContract.INK)
	text.name = "Legend"


## The showroom shows the office's own bar and bottom panel, fed mock data, so
## a HUD change is visible here without a herdr session.
func _hud() -> OfficeHud:
	var hud: OfficeHud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.dress(art, pen.font)
	# No NEWS strip: it would stand on the status line under the zones. Said
	# before fit(), so the staff panel is laid out without it.
	hud.news_wanted = false
	hud.fit(HUD_SCREEN)
	hud.show_bar(art.display_name.to_upper(), "PREVIEW / MOCK DATA", false)
	var pane := PaneModel.new()
	pane.pane_id = "w1:p2"
	pane.key = "local:w1:p2"
	pane.provider = "codex"
	pane.state = "idle" if stale else "blocked"
	pane.workspace_label = "API"
	pane.tab_label = "DEV"
	pane.tab_shown = "DEV"
	pane.cwd = "/home/mock/herdstead"
	pane.terminal_title = "Source: mock fixture"
	pane.name = DisplayName.of(pane.terminal_title, "", "DEV", pane.cwd, "", pane.pane_id, pane.provider)
	hud.inspector.show_pane(pane, "", stale)
	hud.inspector.set_duration("12m")
	return hud


func state_strip() -> void:
	var strip := Control.new()
	strip.name = "StateStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = STRIP.position
	strip.size = STRIP.size
	add_child(strip)
	pen.panel(strip, Rect2(Vector2.ZERO, strip.size))
	var stats_width := 112.0
	var pitch := 64.0
	pen.clipped(strip, "STATE SAMPLES", Vector2(10, 6), Vector2(stats_width - 10, 14), 10, ArtContract.SLATE)
	# Herdr's five states, then the two display overlays that are not herdr's.
	var states: Array[StringName] = ArtContract.STATES.duplicate()
	states.append_array([ArtContract.UI_STARTING, ArtContract.UI_OFFLINE])
	for index in states.size():
		var state := states[index]
		var at := Vector2(stats_width + (index + 0.5) * pitch, art.workstation.portrait_pivot.y + 10)
		var drawn := art.state(state)
		var holder := Node2D.new()
		holder.position = at
		strip.add_child(holder)
		OfficeDraw.seat_portrait(holder, null, art, "generic", "")
		if state == ArtContract.UI_OFFLINE:
			holder.modulate = art.stale_tint
		pen.icon(strip, drawn.badge if drawn != null else state, at + Vector2(24, -26))
		pen.clipped(
			strip,
			"UNREAD" if state == ArtContract.STATE_DONE else str(state).to_upper(),
			at + Vector2(-32, 4),
			Vector2(64, 12),
			10,
			ArtContract.INK,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	# What this pack actually holds, in its own pixels: geometry stays in
	# density-1 units, so only these numbers move with the density. The tiles are
	# the pack's own art; the frames belong to the generic workstation family
	# and carry that family's density, not this pack's.
	var frame := art.workstation.frame_size * art.workstation.density
	var sampling := "Nearest" if art.filter == CanvasItem.TEXTURE_FILTER_NEAREST else "Linear + mips"
	var built := "%dpx tiles\n%dx%d frames\n%s" % [art.tile_size * art.density, frame.x, frame.y, sampling]
	pen.clipped(strip, built, Vector2(10, 23), Vector2(stats_width - 10, 42), 10, ArtContract.SLATE)
	var legend_left := stats_width + states.size() * pitch + 16
	legend(strip, Rect2(Vector2(legend_left, 8), Vector2(strip.size.x - legend_left - 10, strip.size.y - 16)))


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
				# No titles here: each mock pane is called by its tab (DisplayName).
				sighting.name = DisplayName.of("", "", str(pane[4]), "", "", str(pane[1]), str(pane[2]))
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
			model.tab_shown = sighting.tab
			model.name = sighting.name
			building.all_panes.append(model)
			frame.pane_by_key[key] = model
		# As OfficeProjection.frame(): a dropped machine's panes are not live.
		if not building.stale:
			frame.live_panes.append_array(building.all_panes)
		frame.buildings.append(building)
	mock.now_msec = start_msec + MOCK_MINUTES * 60000
	mock.start_unix = start_unix
	return mock


## The mock's machines as the status line's hover and the machine chips say
## them: Local answering now (its chip the current one), bee last heard from
## when it dropped.
func _mock_machines(mock: MockOffice) -> Array[OfficeTotals.MachineRow]:
	var local := OfficeTotals.MachineRow.new()
	local.key = "local"
	local.label = "Local"
	local.state = MachineLiveness.State.LIVE
	local.heard_since = Time.get_unix_time_from_system()
	var bee := OfficeTotals.MachineRow.new()
	bee.key = "bee"
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
