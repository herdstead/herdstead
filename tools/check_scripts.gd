extends SceneTree
## Loads every GDScript under scripts/ and tools/ and every scene under scenes/,
## and fails naming the ones that do not. Nothing else proves that a file which
## no scene and no test references still parses: tools/check_state_since.gd sat
## broken for weeks because nothing ever loaded it.
##
## This is also where the `[debug] gdscript/warnings/*` gate in project.godot
## bites: a warning set to Error makes the script fail to compile, so it lands
## here as "did not compile" plus the engine's own SCRIPT ERROR line.
##
##   godot --headless --path . --script tools/check_scripts.gd

const SCRIPT_DIRS := ["res://scripts", "res://tools"]
const SCENE_DIRS := ["res://scenes"]

var _broken: Array[String] = []


func _initialize() -> void:
	var scripts := _walk(SCRIPT_DIRS, ".gd")
	var scenes := _walk(SCENE_DIRS, ".tscn")
	for path in scripts:
		_load_script(path)
	for path in scenes:
		_load_scene(path)
	if not _broken.is_empty():
		print("SCRIPTS_FAILED: %d of %d files" % [_broken.size(), scripts.size() + scenes.size()])
		for line in _broken:
			print("  " + line)
		quit(1)
		return
	print("SCRIPTS_OK: %d scripts, %d scenes" % [scripts.size(), scenes.size()])
	quit(0)


## Every file under `roots` ending in `suffix`, depth first, sorted so the
## report reads the same on every machine.
func _walk(roots: Array, suffix: String) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = []
	pending.assign(roots)
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			_broken.append("%s: cannot be opened (%s)" % [dir_path, error_string(DirAccess.get_open_error())])
			continue
		for name in dir.get_directories():
			pending.append(dir_path.path_join(name))
		for name in dir.get_files():
			if name.ends_with(suffix):
				found.append(dir_path.path_join(name))
	found.sort()
	return found


func _load_script(path: String) -> void:
	# Cached, not CACHE_MODE_IGNORE: a second copy of this very script crashes
	# the engine (4.7.2, signal 11), and a fresh process has nothing stale anyway.
	var resource: Resource = ResourceLoader.load(path, "GDScript")
	if resource == null:
		_broken.append(path + ": did not load")
		return
	var script := resource as GDScript
	if script == null:
		_broken.append(path + ": is not a GDScript")
		return
	if not script.can_instantiate():
		_broken.append(path + ": did not compile")


func _load_scene(path: String) -> void:
	var resource: Resource = ResourceLoader.load(path, "PackedScene")
	if resource == null:
		_broken.append(path + ": did not load")
		return
	var scene := resource as PackedScene
	if scene == null:
		_broken.append(path + ": is not a PackedScene")
		return
	if not scene.can_instantiate():
		_broken.append(path + ": cannot be instantiated")
