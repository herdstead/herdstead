class_name TablePack
extends ArtFamily
## <pack>/table/manifest.json: the shared table's modules, at its own density.
##
## A tab of herdr is one of these tables. The modules repeat at their painted
## size and are never stretched, so the assembly numbers below are what the
## table is built out of, not a scale.

var id := &""
var display_name := ""
var modules: Dictionary[StringName, ArtSprite] = {}
var furniture: Dictionary[StringName, TableFurniture] = {}
var module_width := 32
var surface_depth := 80
var divider_height := 24
var apron_height := 3


## Read a pack's table manifest. Null, with a push_error naming the file and the
## problem, when it cannot be drawn from; a pack with no table file at all is
## not an error here, and ArtPack reports that one.
static func from_manifest(path: String) -> TablePack:
	var data := read_json(path)
	if data.is_empty():
		push_error("Shared table %s: not a JSON object" % path)
		return null
	var result := TablePack.new()
	result.base_path = path.get_base_dir()
	result.density = read_density(data)
	result.filter = read_filter(data)
	result.id = read_name(data.get("id"))
	result.display_name = str(data.get("name", result.id))
	var listed: Dictionary = data.get("modules", {})
	for module: String in listed:
		if not listed[module] is Dictionary:
			push_error('Shared table %s: module "%s" is not a JSON object' % [path, module])
			return null
		var spec: Dictionary = listed[module]
		var sprite := ArtSprite.new()
		sprite.id = StringName(module)
		sprite.path = str(spec.get("path", ""))
		sprite.size = Vector2i(read_pair(spec.get("size")))
		if sprite.path.is_empty():
			push_error('Shared table %s: module "%s" names no image' % [path, module])
			return null
		result.modules[sprite.id] = sprite
	var pieces: Dictionary = data.get("furniture", {})
	for name: String in pieces:
		if not pieces[name] is Dictionary:
			push_error('Shared table %s: furniture "%s" is not a JSON object' % [path, name])
			return null
		var spec: Dictionary = pieces[name]
		var made := TableFurniture.new()
		made.id = StringName(name)
		made.size = Vector2i(read_pair(spec.get("size")))
		made.pivot = read_pair(spec.get("pivot"))
		var views: Dictionary = spec.get("views", {})
		for view: String in views:
			made.views[StringName(view)] = read_name(views[view])
		result.furniture[made.id] = made
	var assembly: Dictionary = data.get("assembly", {})
	result.module_width = maxi(1, whole(assembly.get("module_width", 32)))
	result.surface_depth = maxi(1, whole(assembly.get("surface_depth", 80)))
	result.divider_height = maxi(0, whole(assembly.get("divider_height", 24)))
	result.apron_height = maxi(0, whole(assembly.get("apron_height", 3)))
	return result


## One module as built, or null when this table has no such module.
func module_texture(module: StringName) -> Texture2D:
	if not modules.has(module):
		return null
	return texture(modules[module].path)


## A module as a Sprite2D with the family's convention. Furniture passes the
## foot pivot its view is drawn on.
func module_sprite(module: StringName, pivot := Vector2.ZERO) -> Sprite2D:
	var result := Sprite2D.new()
	result.name = str(module)
	dress(result, module_texture(module), pivot)
	return result


## The furniture `name`, or null when this table has none.
func piece(name: StringName) -> TableFurniture:
	return furniture[name] if furniture.has(name) else null
