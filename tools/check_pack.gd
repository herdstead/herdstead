extends SceneTree
## Checks an exported PCK carries a drawable art pack. Run it from outside the
## project, by absolute path, so res:// is the PCK and not the source tree:
##   godot --headless --main-pack Herdstead.pck --script /abs/tools/check_pack.gd
##
## The contract itself is ArtContract's, the same one tools/check_packs.gd runs
## in the source tree: this adds what only a package can answer — every PNG
## survived the import and the export filter, the font licence shipped, and a
## worker can actually be seated at a table built from the pack.


func _initialize() -> void:
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
	# Presence is not enough in a PCK: a PNG is a remapped import, and a pack
	# denser than the screen is resampled from get_image() at load, so every
	# texture the office draws is loaded and asked for its image.
	for sprite_id in art.props:
		_drawable(art.sprite_texture(art.props[sprite_id]), "props/" + sprite_id, missing)
	for sprite_id in art.ui:
		_drawable(art.sprite_texture(art.ui[sprite_id]), "ui/" + sprite_id, missing)
	_drawable(art.texture(art.atlas_path), "atlas", missing)
	for module in art.table.modules:
		_drawable(art.table.module_texture(module), "table/" + module, missing)
	for strip in art.people.files:
		_drawable(art.people.texture(strip), "pixel_people/" + strip, missing)
	for provider in art.agent_catalog.ids():
		if art.agent_badge(StringName(provider)) == null:
			missing.append("agent logo loader: " + provider)
	if missing.is_empty():
		_check_office_loaders(art, missing)
	_finish(missing)


## Build what a populated floor builds, through the same loaders, and seat a
## worker on both sides: a layer that failed to import shows up here and
## nowhere else.
func _check_office_loaders(art: ArtPack, missing: Array[String]) -> void:
	var pen := OfficeDraw.new(art)
	var ground := Node2D.new()
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
		var person := station.actor()
		for layer in PixelPeople.LAYERS:
			var sprite: Sprite2D = person.get_node(PixelPeople.SPRITES[layer]) if person != null else null
			# A layer the look leaves empty (no glasses) has no texture on purpose.
			var wanted := (
				art.people.layer_texture(layer, person.look, person.shown_facing()) if person != null else null
			)
			if sprite == null or (wanted != null and sprite.texture == null):
				missing.append("%s desk worker has no %s layer" % [side, layer])
	# And one person wearing something on every layer, so each layer's sheet
	# region is proven to load from the PCK.
	var dressed: PixelPerson = OfficeDraw.PERSON_SCENE.instantiate()
	ground.add_child(dressed)
	var every := AvatarLook.with_slots({AvatarLook.GLASSES: &"round", AvatarLook.HEADWEAR: &"cap"})
	dressed.configure(art.people, "codex", every)
	for layer in PixelPeople.LAYERS:
		var sprite: Sprite2D = dressed.get_node(PixelPeople.SPRITES[layer])
		if sprite.texture == null or sprite.texture.get_image() == null:
			missing.append("a fully dressed person has no %s layer" % layer)
	ground.free()


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
			"PACK_OK: art contract, font licence, table modules, pixel people strips, agent logos and runtime loaders"
		)
	quit(1 if missing else 0)
