#!/usr/bin/env bash
# Bring Godot's import cache (.godot/) up to date before a local Godot run
# reads the project. Godot draws textures from .godot/imported, not from
# assets/: after `make art` rewrites a PNG, every Godot run keeps drawing the
# old one until the project is imported again, and a class_name script is
# unknown until the class cache has it. Nothing else notices, so everything
# that starts Godot on the project asks here first: tools/run_tests.sh,
# tools/capture.sh, tools/perf.sh and the Makefile's check-scripts,
# check-packs, smoke and walk-strips (through its `imported` target).
#
#   tools/import_if_stale.sh           import only when stale, quietly (the log only on failure)
#   tools/import_if_stale.sh --force   always import, the log on stdout (`make import`, CI)
#   tools/import_if_stale.sh --check   say whether it is stale; exit 1 if so, import nothing
#
# Stale when the class cache is missing, when a .gd under scripts/ or tools/ is
# newer than it (a merge that adds a class), when this script has never
# stamped an import (.godot/herdstead-import.stamp), or when anything under
# assets/ (its PNGs, manifests, fonts and their .import files), a scene, or
# project.godot is newer than that stamp. The stamp takes the time the import
# finished: Godot rewrites .import files while it imports, and those must not
# make the next run import again (a file someone edits during an import is
# the one case this misses).
# A fresh clone's first import can crash Godot; a failed import is tried once more.
#
# HERDSTEAD_ROOT points it at another tree (its tests do).
set -u

GODOT="${GODOT:-godot}"
ROOT="${HERDSTEAD_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="${1:-}"
case "$MODE" in
	'' | --force | --check) ;;
	*)
		echo "IMPORT: unknown argument $MODE" >&2
		exit 2
		;;
esac
CLASS_CACHE="$ROOT/.godot/global_script_class_cache.cfg"
STAMP="$ROOT/.godot/herdstead-import.stamp"

# Why the cache is stale, or nothing when it is not.
stale_reason() {
	if [ ! -f "$CLASS_CACHE" ]; then
		echo "no class cache"
		return
	fi
	local newer
	newer="$(find "$ROOT/scripts" "$ROOT/tools" -name '*.gd' -newer "$CLASS_CACHE" -print -quit 2>/dev/null)"
	if [ -n "$newer" ]; then
		echo "${newer#"$ROOT"/} is newer than the class cache"
		return
	fi
	if [ ! -f "$STAMP" ]; then
		echo "no import stamp"
		return
	fi
	local watched=()
	for path in "$ROOT/assets" "$ROOT/scenes" "$ROOT/project.godot"; do
		[ -e "$path" ] && watched+=("$path")
	done
	newer="$(find "${watched[@]}" -newer "$STAMP" -print -quit 2>/dev/null)"
	if [ -n "$newer" ]; then
		echo "${newer#"$ROOT"/} is newer than the last import"
	fi
}

reason="$(stale_reason)"
if [ "$MODE" = "--check" ]; then
	if [ -n "$reason" ]; then
		echo "IMPORT_STALE: $reason"
		exit 1
	fi
	echo "IMPORT_FRESH"
	exit 0
fi
if [ "$MODE" != "--force" ] && [ -z "$reason" ]; then
	exit 0
fi

mkdir -p "$ROOT/.godot"
[ -n "$reason" ] && echo "== importing project ($reason)"
log="$(mktemp "${TMPDIR:-/tmp}/herdstead-import.XXXXXX")"
trap 'rm -f "$log"' EXIT
for attempt in 1 2; do
	if [ "$MODE" = "--force" ]; then
		"$GODOT" --headless --path "$ROOT" --editor --import --quit 2>&1 | tee "$log"
		status="${PIPESTATUS[0]}"
	else
		"$GODOT" --headless --path "$ROOT" --editor --import --quit >"$log" 2>&1
		status=$?
	fi
	if [ "$status" -eq 0 ]; then
		: >"$STAMP"
		exit 0
	fi
	echo "IMPORT: attempt $attempt exited $status"
done
[ "$MODE" = "--force" ] || cat "$log"
echo "IMPORT_FAILED: Godot could not import the project"
exit 2
