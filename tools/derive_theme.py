"""Derive an art pack from another one by remapping its palette, from a recipe.

A theme that only recolours is not a second set of source art: it is one recipe
plus the pack it comes from. `art/dusk` is that, and it is a build product —
nobody edits it by hand. To change how dusk looks, change its recipe; to add a
picture, add it to `art/daylight` and rerun `make art`.

A recipe is one JSON file under `tools/palettes/`, holding everything the
derived pack does not inherit::

    {"schema_version": 1, "from": "daylight", "id": "dusk", "name": "Dusk Shift",
     "stale_modulate": "8f96b8", "task_lights": "strong",
     "palette": {"ink": "13171f", ...}}

`from` names a directory under `art/`, the output is `art/<id>`, and `palette`
lists the colours the derived pack carries for the keys it overrides. Nothing
else moves: geometry, pivots, atlas cells and state mappings are carried over
untouched, which is what makes the derivation safe.

The substitution is per pixel and exact, so every opaque pixel of the source has
to be one of the source pack's own palette colours. That is checked here, on the
pixels, and not inferred from the pack's `filter`: `art/daylight` is density 2
`nearest`, which build_assets.py already holds to the palette, but a `linear`
pack (which it does not) derives just as well while it still paints in palette
colours, and only the pixels can say so.

    python tools/derive_theme.py                                  # every recipe
    python tools/derive_theme.py --recipe tools/palettes/dusk.json --output /tmp/probe
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path
from typing import NamedTuple

from PIL import Image

from build_assets import (
    CATEGORIES,
    ROOT,
    TASK_LIGHTS,
    prune_unreferenced,
    report_pruned,
    resolve_density_filter,
    save_if_pixels_moved,
)
from build_table_assets import table_manifest, validate_source as validate_table_source

HEX_COLOR = re.compile(r"[0-9a-f]{6}")
RECIPES = ROOT / "tools/palettes"
## Why an off-palette pixel is fatal rather than something to work around. This
## is the failure to expect the day daylight becomes hand-drawn HD art.
NO_LONGER_DERIVABLE = (
    "A derived theme is an exact colour substitution, so it needs a source whose "
    "every opaque pixel is one of its own palette colours. Once the source pack is "
    "repainted as hand-drawn art it stops being one, and this is the loud failure "
    "that says so: the theme then needs its own method (its own art, or a runtime "
    "recolour), not a relaxed rule here. Pass --keep-foreign to look at the result "
    "anyway; the build will still reject it."
)


class Recipe(NamedTuple):
    """One derived pack: where it comes from, what it is called, which colours move."""

    path: Path
    source_name: str      # a directory under art/
    pack_id: str
    name: str
    palette: dict         # palette key -> the derived pack's colour
    stale_modulate: str | None
    task_lights: str | None


def fail(message):
    raise SystemExit(f"derive_theme: {message}")


def recipes() -> list[Path]:
    """Every derived pack's recipe, in a stable order."""
    return sorted(RECIPES.glob("*.json"))


def hex_colour(value, what: str) -> str:
    if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
        fail(f"{what} must be six lowercase hex digits; found {value!r}")
    return value


def read_recipe(path: Path) -> Recipe:
    """Read and check one recipe, without opening the pack it names."""
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        fail(f"{path} is not a JSON object")
    version = data.get("schema_version")
    if version != 1:
        fail(f"{path}: unsupported recipe schema_version {version!r}; this tool understands 1")
    for key in ("from", "id", "name"):
        if not isinstance(data.get(key), str) or not data[key]:
            fail(f'{path} needs a non-empty "{key}"')
    for key in ("from", "id"):
        if "/" in data[key] or data[key] in (".", ".."):
            fail(f'{path}: "{key}" names a directory under art/, not a path: {data[key]!r}')
    palette = data.get("palette")
    if not isinstance(palette, dict) or not palette:
        fail(f'{path} needs a non-empty "palette" of the colours this theme carries')
    for key, value in palette.items():
        hex_colour(value, f"{path}: palette entry {key}")
    stale = data.get("stale_modulate")
    if stale is not None:
        hex_colour(stale, f"{path}: stale_modulate")
    lights = data.get("task_lights")
    if lights is not None and lights not in TASK_LIGHTS:
        fail(f"{path}: \"task_lights\" must be {' or '.join(map(repr, TASK_LIGHTS))}; found {lights!r}")
    return Recipe(path, data["from"], data["id"], data["name"], palette, stale, lights)


def check_overrides(recipe: Recipe, palette: dict) -> dict:
    """The recipe may only recolour keys the source pack actually has."""
    unknown = sorted(set(recipe.palette) - set(palette))
    if unknown:
        fail(f"{recipe.path} names keys the source pack has no colour for: {', '.join(unknown)}")
    return recipe.palette


def remap_table(palette: dict, overrides: dict) -> dict:
    """Old RGB to new RGB. An ambiguous source palette cannot be remapped at all."""
    seen = {}
    for key, value in palette.items():
        colour = tuple(bytes.fromhex(value))
        if colour in seen:
            fail(f"source palette is ambiguous: {seen[colour]} and {key} are both #{value}")
        seen[colour] = key
    return {colour: tuple(bytes.fromhex(overrides.get(key, palette[key]))) for colour, key in seen.items()}


def repaint(image: Image.Image, table: dict, label: str, keep_foreign: bool) -> tuple[Image.Image, set]:
    """Substitute colours pixel for pixel; alpha is never touched.

    Every opaque pixel has to be a colour the table knows. One that is not is
    reported with the file it is in and where in that file it first appears, so
    the picture can be opened at that spot.
    """
    raw = bytearray(image.convert("RGBA").tobytes())
    foreign = {}
    for index in range(0, len(raw), 4):
        if raw[index + 3] == 0:
            # Hard transparency carries no colour; leave the zeroes as they are.
            continue
        colour = (raw[index], raw[index + 1], raw[index + 2])
        mapped = table.get(colour)
        if mapped is None:
            pixel = index // 4
            foreign.setdefault(colour, (pixel % image.width, pixel // image.width))
            continue
        raw[index], raw[index + 1], raw[index + 2] = mapped
    if foreign and not keep_foreign:
        listing = ", ".join("#%02x%02x%02x at (%d, %d)" % (*colour, *at) for colour, at in sorted(foreign.items()))
        fail(f"{label} holds colours outside the source palette: {listing}. {NO_LONGER_DERIVABLE}")
    return Image.frombytes("RGBA", image.size, bytes(raw)), set(foreign)


def derive(source: Path, output: Path, recipe: Recipe, keep_foreign: bool = False) -> dict:
    """Write `output` as `source` recoloured by `recipe`, and return its pack.json."""
    if output.resolve() == source.resolve():
        fail("source and output must be different directories")
    pack = json.loads((source / "pack.json").read_text())
    # Size never enters the remap, so any density works, and so does any filter:
    # what matters is whether the pixels are palette colours, checked below.
    try:
        density, _ = resolve_density_filter(pack)
    except ValueError as error:
        fail(f"{source} is not a pack this tool can read: {error}")
    overrides = check_overrides(recipe, pack["palette"])
    table = remap_table(pack["palette"], overrides)
    derived = dict(pack)
    derived["id"] = recipe.pack_id
    derived["name"] = recipe.name
    derived["palette"] = {key: overrides.get(key, value) for key, value in pack["palette"].items()}
    if recipe.stale_modulate is not None:
        derived["stale_modulate"] = recipe.stale_modulate
    if recipe.task_lights is not None:
        derived["task_lights"] = recipe.task_lights
    warned, written, produced = set(), 0, set()
    # The companion's PNGs are editable source too, not fresh procedural
    # drawings. Validate and recolour them before writing any derived files.
    table_images = {}
    if (source / "table").exists():
        try:
            companion = validate_table_source(source)
        except ValueError as error:
            fail(str(error))
        for info in companion["modules"].values():
            relative = Path("table") / info["path"]
            with Image.open(source / relative) as image:
                painted, foreign = repaint(image, table, f"{source.name}/{relative}", keep_foreign)
            table_images[relative] = painted
            warned |= foreign
    for category in CATEGORIES:
        for asset, info in pack[category].items():
            with Image.open(source / info["path"]) as opened:
                image = opened.copy()
            painted, foreign = repaint(image, table, f"{source.name}/{info['path']}", keep_foreign)
            warned |= foreign
            produced.add(output / info["path"])
            written += save_if_pixels_moved(painted, output / info["path"])
    if table_images:
        for relative, painted in table_images.items():
            written += save_if_pixels_moved(painted, output / relative)
        manifest_path = output / "table/manifest.json"
        manifest_text = json.dumps(table_manifest(derived), indent=2) + "\n"
        if not manifest_path.exists() or manifest_path.read_text() != manifest_text:
            manifest_path.write_text(manifest_text)
        table_output = output / "table"
        report_pruned(table_output, prune_unreferenced(table_output, [output / path for path in table_images]))
    for relative in (pack["font"]["path"], pack["font"]["license"]):
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, target)
    (output / "pack.json").write_text(json.dumps(derived, indent=2) + "\n")
    # A derived pack is as much a product as assets/ is, so it holds exactly
    # what the recipe's source pack declares and nothing that has been dropped.
    report_pruned(output, prune_unreferenced(output, produced))
    moved = sum(1 for key, value in pack["palette"].items() if overrides.get(key, value) != value)
    if warned:
        print(f"WARNING: kept {len(warned)} colour(s) outside the source palette; the build will reject them")
    dense = f" / density {density}x" if pack["schema_version"] >= 2 else ""
    print(f"DERIVED: {output} / id={recipe.pack_id}{dense} / {moved} of {len(pack['palette'])} palette colours moved"
          f" / {written} PNG(s) rewritten")
    return derived


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--recipe", type=Path, help="one recipe to derive; default is every file in tools/palettes")
    parser.add_argument("--output", type=Path, help="where to write it; default is art/<the recipe's id>")
    parser.add_argument("--keep-foreign", action="store_true", help="warn about non-palette pixels instead of failing")
    args = parser.parse_args()
    if args.output is not None and args.recipe is None:
        parser.error("--output needs --recipe: it names where one derived pack goes")
    chosen = [args.recipe] if args.recipe is not None else recipes()
    if not chosen:
        fail(f"no recipes under {RECIPES}")
    for path in chosen:
        recipe = read_recipe(path)
        derive(ROOT / "art" / recipe.source_name, args.output or ROOT / "art" / recipe.pack_id,
               recipe, args.keep_foreign)


if __name__ == "__main__":
    main()
