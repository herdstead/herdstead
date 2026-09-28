extends SceneTree
## Every art pack in the source tree, loaded and checked against the contract
## the scenes draw with (scripts/art/art_contract.gd). Part of `make check`: a
## pack that would crash a floor is refused here, at build time, instead of on
## screen.
##
##   godot --headless --path . --script tools/check_packs.gd
##
## The exported PCK gets the same treatment from tools/check_pack.gd, which runs
## from inside the package and additionally proves a worker can be seated.

const PACK_ROOT := "res://assets"

var _failures := 0


func _initialize() -> void:
	var manifests := _manifests()
	if manifests.is_empty():
		printerr("PACKS_MISSING: no art pack under " + PACK_ROOT)
		quit(1)
		return
	for path in manifests:
		_check(path)
	if _failures > 0:
		print("PACKS_FAILED: %d of %d packs" % [_failures, manifests.size()])
		quit(1)
		return
	print("PACKS_OK: %d packs" % manifests.size())
	quit(0)


func _check(path: String) -> void:
	var pack := ArtPack.from_manifest(path)
	_report_unused(path, pack)
	var problems := ArtContract.problems(pack)
	if problems.is_empty():
		return
	_failures += 1
	for problem in problems:
		printerr("PACK_PROBLEM: %s: %s" % [path, problem])


## Art the pack ships that no scene asks for. It never fails the check — a pack
## is allowed to carry more than this build of the office draws — but it prints,
## so nobody has to grep the scenes to find out what has gone cold.
func _report_unused(path: String, pack: ArtPack) -> void:
	var unused := ArtContract.unused(pack)
	for category in unused:
		if not unused[category].is_empty():
			print("PACK_UNUSED: %s: %s: %s" % [path, category, ", ".join(unused[category])])


func _manifests() -> PackedStringArray:
	var found := PackedStringArray()
	var packs := DirAccess.open(PACK_ROOT)
	if packs == null:
		return found
	var names := packs.get_directories()
	names.sort()
	for name in names:
		var candidate := PACK_ROOT.path_join(name).path_join("manifest.json")
		if FileAccess.file_exists(candidate):
			found.append(candidate)
	return found
