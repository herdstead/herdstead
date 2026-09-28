class_name ArtFamily
extends Resource
## One family of textures, and the single owner of its pixel density.
##
## Three families are drawn side by side: a theme's own pack, the pixel people
## every theme shares, and a pack's shared table. Each is built at its own
## density and sampled on its own terms, so a texture is never scaled by one
## family's density and sampled with another's filter.
##
## `density` means one thing only: how many pixels per density-1 unit the built
## PNGs hold. Textures are handed out exactly as built and every node is scaled
## by 1/density, so a denser family lays out like a density-1 one and only draws
## finer. Nothing here knows about the screen: the GPU minifies with mipmaps, so
## a zoom rebuilds nothing.

const DENSITIES: Array[int] = [1, 2, 4, 8]
## A linear family is drawn at any zoom, so it is minified through its mipmaps;
## a density-1 nearest family is only ever magnified by a whole number.
const FILTERS := {
	"nearest": CanvasItem.TEXTURE_FILTER_NEAREST,
	"linear": CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
}

## The directory the family's manifest was read from; every path it names is
## relative to this.
var base_path := ""
## Pixels per density-1 unit in this family's built PNGs.
var density := 1
var filter := CanvasItem.TEXTURE_FILTER_NEAREST

## Textures read from outside res://, by path; see texture().
var _loose: Dictionary[String, Texture2D] = {}


## Node scale that turns this family's texture pixels back into density-1 units.
func unit_scale() -> Vector2:
	return Vector2.ONE / float(density)


## The image at `relative` (to base_path), as the import would hand it out, or
## null when the family has no such file. A family under res:// is a set of
## imported resources and the import carries their mipmaps. A family anywhere
## else (a fixture, a pack being painted) has no import, so a linear family's PNG
## gets here what its import would do: the colour of barely transparent edge
## pixels fixed and mipmaps built (size, alpha and opaque pixels untouched).
func texture(relative: String) -> Texture2D:
	var path := base_path.path_join(relative)
	if path.begins_with("res://"):
		return load(path) as Texture2D if ResourceLoader.exists(path) else null
	if _loose.has(path):
		return _loose[path]
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	if filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		# What an import's fix_alpha_border does: a transparent pixel takes its
		# neighbour's colour, so filtering a hard edge does not blend in black.
		image.fix_alpha_edges()
		image.generate_mipmaps()
	var loaded := ImageTexture.create_from_image(image)
	_loose[path] = loaded
	return loaded


## Whether this family really ships `relative`. Inside an exported PCK a PNG is
## a remapped import that FileAccess cannot see, so res:// is asked through
## ResourceLoader and only a loose family through the filesystem.
func has_file(relative: String) -> bool:
	var path := base_path.path_join(relative)
	if path.begins_with("res://"):
		return ResourceLoader.exists(path)
	return FileAccess.file_exists(path)


## Give a Sprite2D a texture as built, the way every sprite here is set up: its
## origin at `pivot` (density-1 units), scaled back to density-1 units, sampled
## the way this family is sampled. Used on the fixed sprites of the world
## prefabs, which keep their nodes.
func dress(target: Sprite2D, image: Texture2D, pivot := Vector2.ZERO) -> void:
	target.texture = image
	target.centered = false
	# Offset is applied before scale, so it is in texture pixels.
	target.offset = -pivot * density
	target.scale = unit_scale()
	target.texture_filter = filter


## Pixels per unit a companion family declares. Never below 1, whatever the
## manifest says.
static func read_density(manifest: Dictionary) -> int:
	return maxi(1, whole(manifest.get("density", 1)))


## How a companion family's textures are sampled: art at density 1 is only ever
## magnified by a whole number, so NEAREST; denser art is minified whenever the
## screen shows fewer pixels per unit than the art holds, so the family's own
## `filter`, and LINEAR_WITH_MIPMAPS when it names none. A companion family
## never borrows the pack's `filter`: a density-1 nearest pack still shows a
## denser shared family smoothly minified, not aliased.
static func read_filter(manifest: Dictionary) -> CanvasItem.TextureFilter:
	if read_density(manifest) == 1:
		return CanvasItem.TEXTURE_FILTER_NEAREST
	var kind: Variant = manifest.get("filter")
	if kind is String and FILTERS.has(kind):
		return FILTERS[kind]
	return CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## JSON numbers arrive as floats, and `1.0 in [1]` is false; -1 for anything
## that is not a whole number.
static func whole(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = value
	return int(number) if number == floorf(number) else -1


## A manifest value as a semantic ID: `fallback` when the key was absent or the
## JSON holds something that is not text there.
static func read_name(value: Variant, fallback := &"") -> StringName:
	if not value is String:
		return fallback
	var text: String = value
	return StringName(text)


## A manifest value as a flag; anything that is not a JSON boolean is `fallback`.
static func read_flag(value: Variant, fallback := false) -> bool:
	if not value is bool:
		return fallback
	var flag: bool = value
	return flag


## A manifest value as a number; anything that is not a JSON number is `fallback`.
static func read_number(value: Variant, fallback := 0.0) -> float:
	if not (value is int or value is float):
		return fallback
	var number: float = value
	return number


## A manifest value as a list; anything that is not a JSON array is empty.
static func read_list(value: Variant) -> Array:
	if not value is Array:
		return []
	var listed: Array = value
	return listed


## The parsed contents of a JSON object at `path`, or an empty Dictionary when
## there is no such file or it does not hold an object.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## A JSON `[x, y]` pair as a Vector2, or `fallback` when it is not one.
static func read_pair(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	var pair := read_list(value)
	if pair.size() != 2:
		return fallback
	if not (pair[0] is float or pair[0] is int) or not (pair[1] is float or pair[1] is int):
		return fallback
	return Vector2(read_number(pair[0]), read_number(pair[1]))
