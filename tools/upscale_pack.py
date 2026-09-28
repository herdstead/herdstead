"""Copy an art pack to a new source directory at a higher schema-2 density.

The point is a gradual repaint: the copy declares the density you intend to paint
at, and you replace PNGs one at a time. Whatever you have not repainted yet is
still valid, because `build_assets.py` fills lower-density sources in.

Geometry in pack.json is untouched — it stays in density-1 pixels at every
density, so only `schema_version`, `density`, `id` and `name` move.

    python tools/upscale_pack.py --source art/daylight --output art/daylight4 --density 4
    python tools/upscale_pack.py --source art/daylight --output /tmp/probe --density 4 --manifest-only

`--manifest-only` leaves every PNG at the size it already is, which is the
honest starting point for a repaint: the build shows you blown-up 32px
placeholders until you replace them.
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

from build_assets import CATEGORIES, DENSITIES, ROOT, contract_size, resolve_density_filter, upscale


def fail(message):
    raise SystemExit(f"upscale_pack: {message}")


def check_directories(source: Path, output: Path):
    """The source pack is an input only, and an occupied output is somebody's work."""
    source_resolved, output_resolved = source.resolve(), output.resolve()
    if output_resolved == source_resolved or output_resolved.is_relative_to(source_resolved) or source_resolved.is_relative_to(output_resolved):
        fail(f"--output must be a directory outside --source, not {output}")
    if output.exists() and any(output.iterdir()):
        fail(f"--output already holds files, refusing to overwrite: {output}")


def upgrade(source: Path, output: Path, density: int, pack_id: str | None = None,
            name: str | None = None, manifest_only: bool = False) -> dict:
    check_directories(source, output)
    if density not in DENSITIES:
        fail(f"--density must be one of {', '.join(map(str, DENSITIES))}; got {density}")
    pack = json.loads((source / "pack.json").read_text())
    try:
        current, _ = resolve_density_filter(pack)
    except ValueError as error:
        fail(f"{source} is not a pack this tool can read: {error}")
    if density < current:
        fail(f"--density {density} is below the source pack's density {current}; this tool never downscales")
    upgraded = dict(pack)
    upgraded["schema_version"] = 2
    upgraded["density"] = density
    # A different id keeps the upgraded pack from colliding with the original
    # once both are built into assets/ and the office discovers them.
    upgraded["id"] = pack_id or f"{pack['id']}-x{density}"
    upgraded["name"] = name or f"{pack['name']} {density}x"
    written = 0
    for category in CATEGORIES:
        for asset, info in pack[category].items():
            target = output / info["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            if manifest_only:
                shutil.copyfile(source / info["path"], target)
                written += 1
                continue
            with Image.open(source / info["path"]) as opened:
                image = opened.convert("RGBA")
            expected_width, expected_height = contract_size(pack, category, info)
            factor = image.width // expected_width if expected_width else 0
            if factor not in DENSITIES or (image.width, image.height) != (expected_width * factor, expected_height * factor):
                fail(f"{category}/{asset} is {image.width}x{image.height}, not an allowed multiple of the {expected_width}x{expected_height} contract")
            upscale(image, density // factor).save(target)
            written += 1
    for relative in (pack["font"]["path"], pack["font"]["license"]):
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, target)
    (output / "pack.json").write_text(json.dumps(upgraded, indent=2) + "\n")
    verb = "copied unchanged" if manifest_only else "upscaled"
    print(f"UPSCALED: {output} / id={upgraded['id']} / schema 2 density {density}x / {written} PNGs {verb}")
    return upgraded


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=ROOT / "art/daylight")
    parser.add_argument("--output", type=Path, required=True, help="new source directory; must be empty or absent")
    parser.add_argument("--density", type=int, required=True, choices=DENSITIES, help="pixels per density-1 pixel")
    parser.add_argument("--manifest-only", action="store_true", help="leave the PNGs at their current size and let the build fill them in")
    parser.add_argument("--id", help="pack id for the copy; defaults to <source id>-x<density>")
    parser.add_argument("--name", help="display name for the copy; defaults to <source name> <density>x")
    args = parser.parse_args()
    upgrade(args.source, args.output, args.density, args.id, args.name, args.manifest_only)
