#!/usr/bin/env bash
# Import, then export the "macOS" preset to build/Herdstead.app plus a zip for sharing.
# Usage: tools/export_macos.sh            (GODOT=/path/to/godot to override the binary)
# Needs the matching export templates; this script never downloads them.
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

# 4.7.2.stable.official.<hash> -> 4.7.2.stable, the template directory name.
version="$("$GODOT" --version | sed -E 's/^([0-9.]+[a-z0-9]*)\..*/\1/')"
case "$(uname -s)" in
	Darwin) templates="$HOME/Library/Application Support/Godot/export_templates/$version" ;;
	*) templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$version" ;;
esac
if [[ ! -f "$templates/macos.zip" ]]; then
	release="${version%.*}-${version##*.}"   # GitHub tag, e.g. 4.7.2-stable
	cat >&2 <<EOF
Missing export template: $templates/macos.zip
Install the official Godot $release templates (the .tpz download is about 1.3 GB), then rerun:

  curl -LO https://github.com/godotengine/godot/releases/download/$release/Godot_v${release}_export_templates.tpz
  mkdir -p "$templates"
  unzip -j Godot_v${release}_export_templates.tpz templates/macos.zip templates/version.txt -d "$templates"

Or in the editor: Editor > Manage Export Templates > Download and Install.
EOF
	exit 1
fi

# build/ must never be scanned or imported by the editor.
mkdir -p build
touch build/.gdignore

"$GODOT" --headless --editor --import --quit
if [[ "$(uname -s)" == Darwin ]]; then
	rm -rf build/Herdstead.app build/Herdstead-macos.zip
	"$GODOT" --headless --export-release "macOS" build/Herdstead.app
	ditto -c -k --keepParent build/Herdstead.app build/Herdstead-macos.zip
	echo "EXPORT_OK: build/Herdstead.app, build/Herdstead-macos.zip"
else
	# Non-macOS hosts can only produce the zipped .app (built-in ad-hoc signing still applies).
	rm -f build/Herdstead-macos.zip
	"$GODOT" --headless --export-release "macOS" build/Herdstead-macos.zip
	echo "EXPORT_OK: build/Herdstead-macos.zip"
fi
