"""Validate and byte-copy the approved whole-image workstation family.

Sources live in art/daylight/workstation, runtime products in the matching
assets directory. This family owns its 37-colour palette; it never reads or
extends the theme palette. A frame is 80x80 world units at density 2, pivot
(37.5, 70), on a 4x6 atlas. The empty workstation has the same canvas/pivot;
the generic portrait is 40x40 world units, pivot (20, 40), at the same density.

Normal builds never redraw, repack, resample, recolour or re-encode an image.
The empty chair was derived once offline from the approved A artwork; see
the source family's PROVENANCE.md. Imports of retained images are untouched.
No Godot process, painter call or experimental build directory is needed.
"""
from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

from PIL import Image

from build_assets import copy_if_changed, prune_unreferenced, report_pruned, require


ROOT = Path(__file__).resolve().parents[1]
DENSITY = 2
FRAME_SIZE = (80, 80)
PIVOT = (37.5, 70)
COLUMNS = 4
ROWS = 6
PALETTE_SIZE = 37
SHEET = "state-workstation.png"
EMPTY = "empty-workstation.png"
PORTRAIT = "generic-portrait.png"
PORTRAIT_SIZE = (40, 40)
PORTRAIT_PIVOT = (20, 40)
IMAGE_SIZES = {
    SHEET: (FRAME_SIZE[0] * DENSITY * COLUMNS, FRAME_SIZE[1] * DENSITY * ROWS),
    EMPTY: tuple(value * DENSITY for value in FRAME_SIZE),
    PORTRAIT: tuple(value * DENSITY for value in PORTRAIT_SIZE),
}
PRODUCT_KEYS = {
    "schema_version", "id", "name", "density", "filter", "frame_size", "pivot",
    "columns", "rows", "image", "empty_image", "portrait", "palette", "animations",
}
LOOPS = {
    "idle": True, "working": True, "blocked_enter": False, "blocked": True,
    "blocked_exit": False, "done": False, "starting": False, "unknown": False,
}


def finite_number(value) -> bool:
    """JSON numbers, never booleans, strings, NaN, infinity or overflowing ints."""
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def native_pair(value, expected: tuple, label: str) -> None:
    require(isinstance(value, list) and len(value) == 2
            and all(finite_number(item) for item in value) and tuple(value) == expected,
            f"{label} must be {list(expected)}")


def validate_manifest(manifest) -> set[tuple[int, int, int]]:
    """Validate every field before indexing it; return the family's own RGB set."""
    require(isinstance(manifest, dict), "manifest must be a JSON object")
    require(set(manifest) == PRODUCT_KEYS, "manifest must declare exactly the workstation fields")
    for key, expected in (("schema_version", 1), ("density", DENSITY), ("columns", COLUMNS), ("rows", ROWS)):
        require(finite_number(manifest[key]) and manifest[key] == expected, f"{key} must be {expected}")
    for key in ("id", "name"):
        require(isinstance(manifest[key], str) and manifest[key], f"{key} must be non-empty text")
    require(manifest["filter"] == "nearest", "filter must be nearest")
    native_pair(manifest["frame_size"], FRAME_SIZE, "frame_size")
    native_pair(manifest["pivot"], PIVOT, "pivot")
    require(manifest["image"] == SHEET and manifest["empty_image"] == EMPTY,
            f"images must name {SHEET} and {EMPTY}")
    portrait = manifest["portrait"]
    require(isinstance(portrait, dict) and set(portrait) == {"image", "size", "pivot"},
            "portrait must declare image, size and pivot")
    require(portrait["image"] == PORTRAIT, f"portrait image must be {PORTRAIT}")
    native_pair(portrait["size"], PORTRAIT_SIZE, "portrait size")
    native_pair(portrait["pivot"], PORTRAIT_PIVOT, "portrait pivot")
    palette = manifest["palette"]
    require(isinstance(palette, dict) and len(palette) == PALETTE_SIZE,
            f"palette must declare the family's {PALETTE_SIZE} colours")
    for name, color in palette.items():
        require(isinstance(name, str) and name and isinstance(color, str)
                and re.fullmatch(r"[0-9a-fA-F]{6}", color),
                "palette needs non-empty names and six-digit RGB colours")
    colors = {tuple(bytes.fromhex(value)) for value in palette.values()}
    require(len(colors) == PALETTE_SIZE, "palette colours must be distinct")
    animations = manifest["animations"]
    require(isinstance(animations, dict) and set(animations) == set(LOOPS),
            f"animations must declare exactly {sorted(LOOPS)}")
    for name, loop in LOOPS.items():
        validate_track(name, animations[name], loop)
    return colors


def validate_track(name: str, entry, loop: bool) -> None:
    require(isinstance(entry, dict) and set(entry) == {"frames", "seconds", "loop"},
            f"animation {name}: must declare frames, seconds and loop")
    frames, seconds = entry["frames"], entry["seconds"]
    require(isinstance(frames, list) and isinstance(seconds, list) and frames and len(frames) == len(seconds),
            f"animation {name}: needs non-empty frames and one duration per frame")
    require(type(entry["loop"]) is bool and entry["loop"] == loop,
            f"animation {name}: incorrect loop flag")
    total = 0.0
    for frame, hold in zip(frames, seconds):
        require(finite_number(frame) and 0 <= frame < COLUMNS * ROWS and frame == int(frame),
                f"animation {name}: frame must be a whole index 0..{COLUMNS * ROWS - 1}")
        require(finite_number(hold) and hold > 0, f"animation {name}: duration must be finite and positive")
        end = total + hold
        require(math.isfinite(end) and end > total, f"animation {name}: duration sum must be finite and advance")
        total = end
    if name in ("starting", "unknown"):
        require(frames == [0], f"animation {name}: must hold frame 0, never show activity")


def validate_image(path: Path, size: tuple[int, int], palette: set[tuple[int, int, int]]) -> None:
    try:
        with Image.open(path) as image:
            require(image.format == "PNG" and image.mode == "RGBA", f"{path}: must be an RGBA PNG")
            require(image.size == size, f"{path}: expected {size}, found {image.size}")
            alpha = image.getchannel("A")
            require(alpha.getbbox() is not None, f"{path}: image is empty")
            require({color for _, color in alpha.getcolors()} <= {0, 255}, f"{path}: alpha must be hard (0 or 255)")
            # Native dimensions, checked above, bound this list. Ignore hidden
            # RGB under zero alpha rather than rejecting valid editor output.
            colors = image.getcolors(image.width * image.height)
            require(all(not rgba[3] or rgba[:3] in palette for _, rgba in colors),
                    f"{path}: opaque colours must belong to the workstation palette")
            if path.name == SHEET:
                width, height = IMAGE_SIZES[EMPTY]
                for index in range(COLUMNS * ROWS):
                    left, top = (index % COLUMNS) * width, (index // COLUMNS) * height
                    require(alpha.crop((left, top, left + width, top + height)).getbbox() is not None,
                            f"{path}: frame {index} is empty")
    except OSError as error:
        raise ValueError(f"{path}: {error}") from error


def validate_source(source: Path) -> dict:
    """Validate the whole family before changing any runtime file."""
    directory = source / "workstation"
    path = directory / "manifest.json"
    try:
        manifest = json.loads(path.read_text())
        palette = validate_manifest(manifest)
        for name, size in IMAGE_SIZES.items():
            validate_image(directory / name, size, palette)
    except (OSError, ValueError) as error:
        raise ValueError(f"{path}: {error}") from error
    return manifest


def build_pack(source: Path, output: Path) -> None:
    require(not (output.resolve().is_relative_to(source.resolve())
                 or source.resolve().is_relative_to(output.resolve())),
            "source and output must not overlap")
    validate_source(source)
    source_family, output_family = source / "workstation", output / "workstation"
    for name in (*IMAGE_SIZES, "manifest.json"):
        copy_if_changed(source_family / name, output_family / name)
    # Only this runtime family is ours. Source sketches/provenance and every
    # retained image's .import belong to their authors and are never rewritten.
    report_pruned(output_family, prune_unreferenced(output_family, [output_family / name for name in IMAGE_SIZES]))
    print(f"WORKSTATION_ASSETS_OK: {source} -> {output} ({COLUMNS * ROWS} frames, empty workstation, portrait)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="art pack containing workstation/ (default art/daylight)")
    parser.add_argument("--output", type=Path, help="runtime pack for --source (default assets/daylight)")
    args = parser.parse_args()
    if (args.source is None) != (args.output is None):
        parser.error("--source and --output must be supplied together")
    try:
        build_pack(args.source or ROOT / "art/daylight", args.output or ROOT / "assets/daylight")
    except (ValueError, OSError) as error:
        parser.exit(1, f"build_workstation_assets: {error}\n")


if __name__ == "__main__":
    main()
