extends Node2D
## A small, local avatar composer. It deliberately shares ArtPack and
## PixelPerson with the live office, so the preview is the same pixel person a
## pane will use, at the same kind of table. The choices are the family's own
## slots and options (skin, hair style and colour, top, legs, headwear and its
## colour, glasses), not a list of this studio's. No network request is made
## here.
##
## Each slot is a row: `‹ value ›`. A row cycles through VARIES (not pinned: a
## pane's own variation, or the provider's default, shows there) and every
## option the family draws. The preview shows what the office would draw for a
## pane of this agent with these pins. SAVE writes the pinned rows for the agent
## through AgentCatalog (schema 2, atomic; a file it could not read is kept aside
## and the status line says where). Per-colour picking waits for the runtime
## colour lookup: only the baked swatches are offered.
##
## Keys: ↑/↓ agent, [ / ] slot row, ←/→ its value, 0 unpins the row, Enter saves,
## D/S desk or standing, F/B front or back, 1–4 idle / working / blocked /
## starting. --avatars=<path> saves somewhere other than user://herdstead_avatars.json.

const DESIGN_SIZE := Vector2i(960, 480)
const BADGE_ROOT := "res://assets/agent_badges/"
## The office's own table at twice its size, with a vacant station on both
## sides of its one column. The person sits at the far seat (front view) or the
## near seat (back view) at a desk, or stands in front of the table. Twice, not
## anything between: the pixel people are only ever magnified by a whole number.
const STAGE_AT := Vector2(300, 270)
const STAGE_ZOOM := 2
## The pane key the preview's VARIES rows are picked by: one sample pane.
const PREVIEW_KEY := "studio"
## What a row shows while its slot is not pinned.
const VARIES := "VARIES"
## A row holding a saved value this build cannot draw; not an id (ids never
## start with "@"), so the preview's resolve() skips it and the slot varies.
const KEPT := &"@kept"
## The slot rows, in design pixels: where the first starts and how far apart.
const ROWS_AT := Vector2(696, 70)
const ROW_STEP := 40.0

## The command line; a test may set it before the studio enters the tree,
## otherwise it is this process's own.
var args: AppArgs
var manifest_path := "res://assets/daylight/manifest.json"
var art: ArtPack
var pen: OfficeDraw
var catalog: AgentCatalog
var content: Node2D
var status_line: Label
var agent_ids := PackedStringArray()
var agent_index := 0
## The agent's pinned slots as edited here, sparse: an empty slot varies, and
## KEPT stands for a saved value this build cannot draw (see `kept`).
var pins := AvatarLook.new()
## Slot -> the row's text for what the file holds there that this build cannot
## draw: an option id of a newer pack or a colour picked by value ("#rrggbb")
## "(not in this build)", or a value it cannot read at all "(not readable
## here)". Kept, and written back untouched, unless the user changes the row.
var kept: Dictionary[StringName, String] = {}
## The rows the user changed since the agent was loaded or saved: the only
## slots a save writes.
var touched: Array[StringName] = []
## The slot row the keyboard edits.
var slot_index := 0
## The person the preview shows, as last dressed.
var preview: PixelPerson
var preview_context := AvatarLook.DESK
var preview_orientation := AvatarLook.FRONT
var preview_animation := ArtContract.ANIMATION_WORKING
var agent_rows: Array[Rect2] = []
## Per slot row: the row itself, and its step-back and step-on click targets.
var slot_rects: Array[Rect2] = []
var back_rects: Array[Rect2] = []
var next_rects: Array[Rect2] = []
var save_rect := Rect2()


func _ready() -> void:
	if args == null:
		args = AppArgs.current()
	manifest_path = args.text("pack", manifest_path)
	art = ArtPack.from_manifest(manifest_path)
	if art == null:
		push_error("The Avatar Studio has no art pack to draw with: " + manifest_path)
		get_tree().quit(1)
		return
	# The studio is a 960x480 design of its own, wider than the office's logical
	# viewport, shown at the project's wide desktop window size.
	get_window().content_scale_size = DESIGN_SIZE
	pen = OfficeDraw.new(art)
	catalog = AgentCatalog.new(args.text("avatars", AgentCatalog.USER_PATH))
	# One catalog for the preview and the save: what is saved is what is shown.
	art.people.agent_catalog = catalog
	agent_ids = catalog.ids()
	if agent_ids.is_empty():
		push_error("Avatar Studio needs at least one agent in agent_catalog.json")
		return
	var preferred := agent_ids.find("claude")
	agent_index = preferred if preferred >= 0 else 0
	_load_agent_selection()
	_build_frame()
	_rebuild_content()
	print("AVATAR_STUDIO_OK: %d agents, %d slots" % [agent_ids.size(), AvatarLook.SLOTS.size()])
	if args.has("capture"):
		await CaptureDriver.run(self, args, "Avatar Studio")


func _build_frame() -> void:
	var background := ColorRect.new()
	background.color = art.color(ArtContract.CREAM_SHADOW)
	background.position = Vector2.ZERO
	background.size = DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	pen.panel(self, Rect2(0, 0, DESIGN_SIZE.x, 32))
	pen.label(self, "HERDSTEAD / AVATAR STUDIO", Vector2(16, 8), Vector2(300, 18), 14, ArtContract.INK)
	pen.clipped(
		self,
		"%d AGENTS / LOCAL ONLY" % agent_ids.size(),
		Vector2(630, 8),
		Vector2(310, 14),
		10,
		ArtContract.SLATE,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _rebuild_content() -> void:
	if is_instance_valid(content):
		remove_child(content)
		content.free()
	content = Node2D.new()
	content.name = "StudioContent"
	add_child(content)
	agent_rows.clear()
	slot_rects.clear()
	back_rects.clear()
	next_rects.clear()
	_draw_agents()
	_draw_preview()
	_draw_composer()


func _draw_agents() -> void:
	pen.panel(content, Rect2(16, 42, 224, 422))
	pen.label(content, "HERDR AGENTS", Vector2(28, 52), Vector2(190, 14), 10, ArtContract.SLATE)
	var first_y := 72.0
	for index in agent_ids.size():
		var id: String = agent_ids[index]
		var rect := Rect2(24, first_y + index * 15, 208, 15)
		agent_rows.append(rect)
		if index == agent_index:
			pen.box(content, rect, ArtContract.BLOCKED)
		var badge := _badge(content, id, Vector2(rect.position.x + 12, rect.position.y + 7.5), 12.0)
		badge.modulate = Color.WHITE if index == agent_index else Color(0.78, 0.78, 0.78)
		pen.clipped(
			content,
			catalog.display_name(id),
			Vector2(rect.position.x + 25, rect.position.y + 2),
			Vector2(176, 12),
			9,
			ArtContract.PAPER if index == agent_index else ArtContract.INK
		)
	pen.label(content, "↑/↓ choose  •  click a row", Vector2(28, 447), Vector2(196, 12), 8, ArtContract.MUTED)


func _draw_preview() -> void:
	pen.panel(content, Rect2(252, 42, 416, 422))
	pen.label(content, "COMPOSED PORTRAIT", Vector2(268, 52), Vector2(190, 14), 10, ArtContract.SLATE)
	var id := _agent_id()
	var stage := Node2D.new()
	stage.name = "Stage"
	stage.position = STAGE_AT
	stage.scale = Vector2.ONE * STAGE_ZOOM
	content.add_child(stage)
	var ground := Node2D.new()
	stage.add_child(ground)
	var sorted := Node2D.new()
	sorted.y_sort_enabled = true
	stage.add_child(sorted)
	var table := pen.table(sorted, ground, "Table0", Vector2.ZERO, 160.0, [80.0])
	for side: String in OfficeTable.SIDES:
		pen.station(sorted, table, 0, side)
	preview = OfficeDraw.PERSON_SCENE.instantiate()
	preview.name = "Preview"
	preview.configure(art.people, id, _selection())
	sorted.add_child(preview)
	if preview_context == AvatarLook.DESK:
		var seat := table.seat(0, "far" if preview_orientation == AvatarLook.FRONT else "near")
		preview.position = seat.position
		preview.sit(seat)
	else:
		preview.position = Vector2(80, 34)
	preview.play_state(preview_animation)
	pen.clipped(
		content,
		catalog.display_name(id).to_upper(),
		Vector2(284, 346),
		Vector2(352, 20),
		16,
		ArtContract.INK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	pen.label(
		content,
		"NAME PLATE  /  " + id.to_upper(),
		Vector2(284, 370),
		Vector2(352, 14),
		9,
		ArtContract.WOOD_DARK,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	pen.label(
		content,
		(
			"%s / %s / %s"
			% [str(preview_context).to_upper(), str(preview_orientation).to_upper(), str(preview_animation).to_upper()]
		),
		Vector2(284, 388),
		Vector2(352, 14),
		10,
		ArtContract.WORKING,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var pinned := 0
	for slot_id in AvatarLook.SLOTS:
		if art.people.slots[slot_id].has_option(pins.slot(slot_id)):
			pinned += 1
	var shown := "%d of %d pinned  •  VARIES: each pane its own" % [pinned, AvatarLook.SLOTS.size()]
	if not kept.is_empty():
		shown = (
			"%d of %d pinned, %d kept  •  VARIES: each pane its own" % [pinned, AvatarLook.SLOTS.size(), kept.size()]
		)
	pen.label(content, shown, Vector2(284, 406), Vector2(352, 14), 9, ArtContract.SLATE, HORIZONTAL_ALIGNMENT_CENTER)
	pen.label(
		content,
		"D/S context  •  F/B facing  •  1–4 action track",
		Vector2(284, 426),
		Vector2(352, 14),
		8,
		ArtContract.MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	pen.label(
		content,
		"This is the same PixelPerson a pane uses.",
		Vector2(284, 442),
		Vector2(352, 12),
		8,
		ArtContract.MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_composer() -> void:
	pen.panel(content, Rect2(684, 42, 260, 422))
	pen.label(content, "CUSTOMIZE", Vector2(700, 52), Vector2(180, 14), 10, ArtContract.SLATE)
	for index in AvatarLook.SLOTS.size():
		var slot_id := AvatarLook.SLOTS[index]
		var top := ROWS_AT.y + index * ROW_STEP
		var row := Rect2(ROWS_AT.x, top, 244, ROW_STEP - 6)
		slot_rects.append(row)
		if index == slot_index:
			pen.box(content, row, ArtContract.CREAM)
		pen.label(
			content,
			str(slot_id).replace("_", " ").to_upper(),
			Vector2(704, top + 2),
			Vector2(120, 12),
			8,
			ArtContract.SLATE
		)
		var back := Rect2(704, top + 15, 18, 16)
		var next := Rect2(918, top + 15, 18, 16)
		back_rects.append(back)
		next_rects.append(next)
		for arrow: Rect2 in [back, next]:
			pen.box(content, arrow, ArtContract.WORKING)
		pen.label(content, "‹", back.position + Vector2(5, 1), Vector2(10, 12), 10, ArtContract.PAPER)
		pen.label(content, "›", next.position + Vector2(5, 1), Vector2(10, 12), 10, ArtContract.PAPER)
		var value := pins.slot(slot_id)
		var slot := art.people.slots[slot_id]
		if slot.is_colour() and slot.has_option(value):
			var chip := ColorRect.new()
			chip.position = Vector2(728, top + 17)
			chip.size = Vector2(12, 12)
			chip.color = slot.ramps[value][1]
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(chip)
		var text := str(value).to_upper()
		if value.is_empty():
			text = VARIES
		elif value == KEPT:
			text = kept[slot_id]
		pen.clipped(
			content,
			text,
			Vector2(746, top + 16),
			Vector2(166, 14),
			10,
			ArtContract.INK if slot.has_option(value) else ArtContract.MUTED
		)
	save_rect = Rect2(700, 402, 228, 28)
	pen.box(content, save_rect, ArtContract.WORKING)
	pen.label(
		content,
		"SAVE FOR THIS AGENT  /  ENTER",
		Vector2(708, 410),
		Vector2(212, 12),
		9,
		ArtContract.PAPER,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	status_line = pen.clipped(
		content,
		"[ / ] row  •  ←/→ value  •  0 varies",
		Vector2(696, 442),
		Vector2(236, 12),
		8,
		ArtContract.MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _badge(parent: Node, id: String, center: Vector2, size: float) -> Sprite2D:
	var result := Sprite2D.new()
	result.texture = art.agent_badge(StringName(id))
	result.centered = true
	result.position = center
	result.scale = Vector2.ONE * size / 64.0
	result.texture_filter = art.filter
	parent.add_child(result)
	return result


func _agent_id() -> String:
	return agent_ids[agent_index]


## What the preview person is dressed with: the office's look for a pane of this
## agent with the pins as edited here (not as saved), plus the pose the
## keyboard is showing.
func _selection() -> AvatarLook:
	var result := art.people.resolve(_agent_id(), pins, null, PREVIEW_KEY)
	result.context = preview_context
	result.orientation = preview_orientation
	return result


## The agent's saved pins: what this build draws, and what it cannot (kept).
func _load_agent_selection() -> void:
	pins = AvatarLook.new()
	kept.clear()
	touched.clear()
	var saved := catalog.pins(_agent_id())
	var colours := catalog.saved_colours(_agent_id())
	var unreadable := catalog.unreadable(_agent_id())
	for slot_id in AvatarLook.SLOTS:
		var value := saved.slot(slot_id)
		if art.people.slots[slot_id].has_option(value):
			pins.set_slot(slot_id, value)
		elif not value.is_empty():
			kept[slot_id] = "%s (not in this build)" % value
			pins.set_slot(slot_id, KEPT)
		elif colours.has(slot_id):
			kept[slot_id] = "#%s (not in this build)" % colours[slot_id]
			pins.set_slot(slot_id, KEPT)
		elif unreadable.has(slot_id):
			kept[slot_id] = "%s (not readable here)" % unreadable[slot_id]
			pins.set_slot(slot_id, KEPT)


## Row `slot_id` now holds `value`, by the user's own action. Back on its kept
## value, the row is no longer changed: a save leaves it as it is.
func _set_row(slot_id: StringName, value: StringName) -> void:
	pins.set_slot(slot_id, value)
	if value == KEPT:
		touched.erase(slot_id)
	elif not touched.has(slot_id):
		touched.append(slot_id)


func _select_agent(index: int) -> void:
	agent_index = posmod(index, agent_ids.size())
	_load_agent_selection()
	_rebuild_content()


## Step slot row `index` `direction` places through its kept value (when the
## file holds one this build cannot draw), VARIES and its options.
func _step(index: int, direction: int) -> void:
	slot_index = index
	var slot_id := AvatarLook.SLOTS[index]
	var choices: Array[StringName] = []
	if kept.has(slot_id):
		choices.append(KEPT)
	choices.append(&"")
	choices.append_array(art.people.slots[slot_id].options())
	var at := choices.find(pins.slot(slot_id))
	_set_row(slot_id, choices[posmod(maxi(at, 0) + direction, choices.size())])
	_rebuild_content()


## Save the rows the user changed; every other row, and everything else in the
## file, is kept. A kept value the user changed away from is named as removed.
## When the catalog refuses, its note is shown instead of SAVED.
func _save() -> void:
	var chosen := pins.clothes()
	var removed := PackedStringArray()
	for slot_id in AvatarLook.SLOTS:
		if chosen.slot(slot_id) == KEPT:
			chosen.set_slot(slot_id, &"")
		elif kept.has(slot_id) and touched.has(slot_id):
			removed.append("%s %s removed" % [str(slot_id).replace("_", " "), kept[slot_id]])
	var error := catalog.save_look(_agent_id(), chosen, touched.duplicate())
	var said := catalog.note
	if error == OK and not removed.is_empty():
		var parts := PackedStringArray()
		if not said.is_empty():
			parts.append(said)
		parts.append_array(removed)
		said = "  •  ".join(parts)
	if error == OK:
		_load_agent_selection()
		_rebuild_content()
		status_line.text = (
			"SAVED  /  %s%s" % [catalog.display_name(_agent_id()), "  •  " + said if not said.is_empty() else ""]
		)
		status_line.add_theme_color_override("font_color", art.color(ArtContract.WORKING))
	else:
		status_line.text = said if not said.is_empty() else "SAVE FAILED  /  error %d" % error
		status_line.add_theme_color_override("font_color", art.color(ArtContract.BLOCKED))
	status_line.tooltip_text = status_line.text


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_save()
			return
		match key.keycode:
			KEY_UP:
				_select_agent(agent_index - 1)
			KEY_DOWN:
				_select_agent(agent_index + 1)
			KEY_BRACKETLEFT:
				slot_index = posmod(slot_index - 1, AvatarLook.SLOTS.size())
				_rebuild_content()
			KEY_BRACKETRIGHT:
				slot_index = posmod(slot_index + 1, AvatarLook.SLOTS.size())
				_rebuild_content()
			KEY_LEFT:
				_step(slot_index, -1)
			KEY_RIGHT:
				_step(slot_index, 1)
			KEY_0:
				_set_row(AvatarLook.SLOTS[slot_index], &"")
				_rebuild_content()
			KEY_D:
				preview_context = AvatarLook.DESK
				_rebuild_content()
			KEY_S:
				preview_context = AvatarLook.STAND
				_rebuild_content()
			KEY_F:
				preview_orientation = AvatarLook.FRONT
				_rebuild_content()
			KEY_B:
				preview_orientation = AvatarLook.BACK
				_rebuild_content()
			KEY_1:
				preview_animation = ArtContract.ANIMATION_IDLE
				_rebuild_content()
			KEY_2:
				preview_animation = ArtContract.ANIMATION_WORKING
				_rebuild_content()
			KEY_3:
				preview_animation = ArtContract.ANIMATION_BLOCKED
				_rebuild_content()
			KEY_4:
				preview_animation = ArtContract.ANIMATION_STARTING
				_rebuild_content()
			KEY_ESCAPE:
				get_tree().quit()
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_on_click(click.position)


## A left click anywhere in the studio: an agent row, a slot's arrows or the
## row itself (it becomes the keyboard's), or the save button. The first rect
## that contains the point wins.
func _on_click(point: Vector2) -> void:
	for index in agent_rows.size():
		if agent_rows[index].has_point(point):
			_select_agent(index)
			return
	for index in slot_rects.size():
		if back_rects[index].has_point(point):
			_step(index, -1)
			return
		if next_rects[index].has_point(point):
			_step(index, 1)
			return
		if slot_rects[index].has_point(point):
			slot_index = index
			_rebuild_content()
			return
	if save_rect.has_point(point):
		_save()
