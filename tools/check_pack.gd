extends SceneTree
## Checks an exported PCK carries a drawable art pack. Run it from outside the
## project, by absolute path, so res:// is the PCK and not the source tree:
##   godot --headless --main-pack Herdstead.pck --script /abs/tools/check_pack.gd
##
## The contract itself is ArtContract's, the same one tools/check_packs.gd runs
## in the source tree: this adds what only a package can answer — every PNG
## survived the import and the export filter, the font licence shipped, and a
## complete workstation and its portrait load through the office's real scenes.


func _initialize() -> void:
	# The actor's AnimationPlayer needs its node paths in a live scene tree.
	_run.call_deferred()


func _run() -> void:
	var manifest_path := "res://assets/daylight/manifest.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pack="):
			manifest_path = argument.trim_prefix("--pack=")
	var missing: Array[String] = []
	var art := ArtPack.from_manifest(manifest_path)
	if art == null:
		missing.append(manifest_path + " (does not load; see the error above)")
		_finish(missing)
		return
	missing.append_array(Array(ArtContract.problems(art)))
	if not missing.is_empty():
		_finish(missing)
		return
	# Presence is not enough in a PCK: a PNG is a remapped import, so every
	# texture is loaded and asked for its image data, without resampling it.
	for sprite_id in art.props:
		_drawable(art.sprite_texture(art.props[sprite_id]), "props/" + sprite_id, missing)
	for sprite_id in art.ui:
		_drawable(art.sprite_texture(art.ui[sprite_id]), "ui/" + sprite_id, missing)
	_drawable(art.texture(art.atlas_path), "atlas", missing)
	for module in art.table.modules:
		_drawable(art.table.module_texture(module), "table/" + module, missing)
	for strip in art.people.files:
		_drawable(art.people.texture(strip), "pixel_people/" + strip, missing)
	_drawable(art.workstation.sheet_texture(), "workstation/state sheet", missing)
	_drawable(art.workstation.empty_texture(), "workstation/empty desk", missing)
	_drawable(art.workstation.portrait_texture(), "workstation/portrait", missing)
	for provider in art.agent_catalog.ids():
		if art.agent_badge(StringName(provider)) == null:
			missing.append("agent logo loader: " + provider)
	if missing.is_empty():
		_check_office_loaders(art, missing)
	_finish(missing)


## Build both logical rows through the real table/station loaders. Their
## complete-image body is retained when a worker becomes a shell. The old
## pixel-person layers are not the production office's runtime loader.
func _check_office_loaders(art: ArtPack, missing: Array[String]) -> void:
	var pen := OfficeDraw.new(art)
	var ground := Node2D.new()
	root.add_child(ground)
	# The smallest pod the office builds, measured the way the office measures it.
	var measured := OfficeTable.measure(2)
	var table := pen.table(ground, ground, "Table0", Vector2.ZERO, measured.table_width, measured.columns)
	if table == null:
		missing.append("OfficeTable refused the minimum pod, %s wide" % measured.table_width)
		ground.free()
		return
	for side: String in OfficeTable.SIDES:
		var station := pen.station(ground, table, 0, side)
		station.furnish("codex", ArtContract.STATE_WORKING)
		var actor := station.actor()
		if actor == null or actor.art != art.workstation:
			missing.append("%s station did not load its WorkstationActor" % side)
			continue
		var body: Sprite2D = actor.get_node("Body")
		_check_image(body, art.workstation, art.workstation.sheet_texture(), art.workstation.pivot, side, missing)
		if body.hframes != art.workstation.columns or body.vframes != art.workstation.rows:
			missing.append("%s workstation does not address the complete-image sheet" % side)
		var player: AnimationPlayer = actor.get_node("AnimationPlayer")
		for clip in WorkstationArt.TRACKS:
			if not player.has_animation(clip):
				missing.append("%s workstation has no %s animation" % [side, clip])
		if actor.animation != ArtContract.STATE_WORKING or body.frame != art.workstation.tracks[&"working"].frames[0]:
			missing.append("%s workstation did not draw the first working frame" % side)
		station.furnish("", ArtContract.STATE_IDLE)
		if station.actor() != null or actor.is_playing() or body.hframes != 1 or body.vframes != 1 or body.frame != 0:
			missing.append("%s shell did not stop on a complete empty desk" % side)
		_check_image(
			body, art.workstation, art.workstation.empty_texture(), art.workstation.pivot, side + " shell", missing
		)
	var portrait := OfficeDraw.seat_portrait(ground, null, art, "codex", "pack-check")
	_check_image(
		portrait,
		art.workstation,
		art.workstation.portrait_texture(),
		art.workstation.portrait_pivot,
		"portrait",
		missing
	)
	ground.free()


static func _check_image(
	sprite: Sprite2D, family: WorkstationArt, expected: Texture2D, pivot: Vector2, where: String, missing: Array[String]
) -> void:
	_drawable(sprite.texture, where, missing)
	if sprite.texture != expected:
		missing.append(where + " did not use the workstation family's image")
	if sprite.scale != family.unit_scale() or sprite.offset != -pivot * family.density or sprite.centered:
		missing.append(where + " did not keep the workstation's native density and pivot")
	if sprite.texture_filter != family.filter:
		missing.append(where + " did not keep the workstation's sampling")


static func _drawable(texture: Texture2D, where: String, missing: Array[String]) -> void:
	if texture == null:
		missing.append(where + " (did not load)")
	elif texture.get_image() == null:
		missing.append(where + " (no image data)")


func _finish(missing: Array[String]) -> void:
	for problem in missing:
		printerr("PACK_MISSING: " + problem)
	if missing.is_empty():
		print(
			"PACK_OK: art contract, font licence, companion art, workstation sheet/empty desk/portrait, agent logos and runtime loaders"
		)
	quit(1 if missing else 0)
