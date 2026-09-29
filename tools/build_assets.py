"""Validate editable PNGs and compile an art pack without modifying its sources.

Schema 1 is the original contract: 32px tiles, hard alpha, strict palette.
Schema 2 adds one pack-wide `density` (1/2/4/8 pixels per density-1 pixel) and a
`filter` that picks the style rules. Every geometry number in pack.json stays in
density-1 units at every density; density is the single multiplier, so a pack is
upgraded by declaring it once and repainting PNGs one at a time. Sources still
painted at a lower factor are nearest-upscaled here, visibly blocky on purpose.

**pack.json is the only list of what a pack holds.** Which semantic IDs exist,
what each one's canvas and pivot are, which palette keys a theme carries: the
manifest says, and this build checks that the PNGs agree with it. Which of those
IDs the scenes actually draw with is the other half of the contract and lives
next to the code that draws, in `scripts/art/art_contract.gd`, where
`make check-packs` holds every pack to it. Adding a prop is therefore a PNG, a
pack.json entry and `make art` — no Python changes.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
from pathlib import Path
from typing import NamedTuple

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
HEX_COLOR = re.compile(r"[0-9a-f]{6}")
## One pack-wide density, and the per-PNG factors an author may deliver inside it.
DENSITIES = (1, 2, 4, 8)
FILTERS = ("nearest", "linear")
## How strongly a pack lights its desks: a lamp-lit studio theme wants a
## brighter task-light wedge and a darker contact shadow than daylight does.
TASK_LIGHTS = ("soft", "strong")
CATEGORIES = ("tiles", "props", "ui")
## Tiles laid edge to edge as ground or wall surface: a hole in one of them is a
## hole in the floor. Matched by prefix, so a new `floor.stone` is covered and a
## new cut-out (`wall.front_*`, `wall.side_*` and `wall.threshold` are painted
## silhouettes with transparency around them) is not wrongly caught.
SOLID_TILE_PREFIXES = ("floor.", "wall.cap_", "wall.face_")
## Interchangeable variants of one surface: the office picks between them per
## cell, so their outer 3px have to match or the seam moves. Again a prefix.
VARIANT_TILE_PREFIX = "floor.wood_"
## The pixel people every theme animates through. A pack's states may only name
## a semantic animation the people play in every pose they take, and their
## hand-written contract's state_tracks is where those names live. The scenes'
## own list (ArtContract.ANIMATIONS) is stricter, and `make check-packs` holds
## every pack to it.
PEOPLE_CONTRACT = ROOT / "art/pixel_people/people.json"


class Compiled(NamedTuple):
    """What validate() learned: art already lifted to the pack density, plus how it got there."""

    images: dict      # (category, name) -> Image at contract size x density
    factors: dict     # (category, name) -> the factor the source PNG was painted at
    density: int
    filter: str


def require(condition, message):
    if not condition:
        raise ValueError(message)


def packs() -> list[Path]:
    """Every editable art pack in the tree, found by its pack.json, in a stable order."""
    return sorted(path.parent for path in (ROOT / "art").glob("*/pack.json"))


def people_animations() -> set:
    """The semantic animations the pixel people map to a track in every pose."""
    poses = json.loads(PEOPLE_CONTRACT.read_text())["state_tracks"].values()
    return set.intersection(*(set(mapped) for mapped in poses))


def save_if_pixels_moved(image: Image.Image, target: Path, **options) -> bool:
    """Save a generated PNG only when its pixels really changed.

    A PNG is compared by its decoded pixels everywhere in this pipeline
    (`check_build_clean.py` says so in as many words: zlib output differs across
    platforms while the picture does not). Re-encoding a file that already holds
    the right picture would therefore put hundreds of byte-only changes into
    every art commit and hide the one file that did move. A hand edit changes
    pixels and is overwritten; a different encoder is left alone.
    """
    if target.is_file():
        with Image.open(target) as existing:
            if existing.size == image.size and existing.convert("RGBA").tobytes() == image.convert("RGBA").tobytes():
                return False
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, **options)
    return True


def copy_if_changed(origin: Path, target: Path) -> bool:
    """Mirror a built file byte for byte, but only when it is not already there."""
    if target.is_file() and target.read_bytes() == origin.read_bytes():
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(origin, target)
    return True


def mirror_png(origin: Path, target: Path) -> bool:
    """Put the artist's own bytes in the runtime tree, unless the picture is already there.

    The copy is the source file byte for byte, so nothing is re-encoded; it is
    just not made at all when the two already hold the same picture in different
    encodings, for the reason in save_if_pixels_moved().
    """
    if target.is_file():
        with Image.open(origin) as left, Image.open(target) as right:
            if left.size == right.size and left.convert("RGBA").tobytes() == right.convert("RGBA").tobytes():
                return False
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(origin, target)
    return True


def prune_unreferenced(directory: Path, keep) -> list[str]:
    """Take out of a generated tree the pictures its manifest stopped naming.

    A generated tree is a product: what is in it is exactly what its manifest
    says is in it. Without pruning, the second half would not hold: drop an
    entry from pack.json and the picture stays on disk, still byte for byte
    what the commit holds, so `check_build_clean.py` cannot see it either — the
    art goes quietly unused, which is the pipeline's version of the very
    problem `ArtContract.unused()` surfaces. Deleting it here turns
    it into drift against the commit, which is visible and which a person then
    commits, instead of a `git rm` somebody has to think to run.

    Deleting is deliberately preferred over refusing: refusing would stop
    `make art` until a human does by hand what the builder already knows how to
    do, and would be the one place in this pipeline where the builder declines
    to make its own output match its own manifest.

    Two limits keep this from reaching anything it does not own. Only `.png`
    files (and the `.import` sidecar Godot keeps beside one) are ever removed,
    so manifests, fonts and licences are safe whatever happens. And a
    subdirectory carrying a manifest of its own is a companion family — the
    shared table — built and pruned by its own builder, so it is skipped.
    """
    wanted = {Path(path).resolve() for path in keep}
    companions = {path.parent for path in directory.rglob("manifest.json")} - {directory}

    def owned(path: Path) -> bool:
        return not any(path.is_relative_to(root) for root in companions)

    removed = []
    for picture in sorted(directory.rglob("*.png")):
        if not owned(picture) or picture.resolve() in wanted:
            continue
        picture.unlink()
        removed.append(str(picture.relative_to(directory)))
    for sidecar in sorted(directory.rglob("*.png.import")):
        # An import that has lost its image imports nothing; it goes with it.
        if owned(sidecar) and not sidecar.with_suffix("").exists():
            sidecar.unlink()
            removed.append(str(sidecar.relative_to(directory)))
    return removed


def report_pruned(directory: Path, removed: list[str]) -> None:
    """Say what was taken out, so `make art` never removes anything silently."""
    if removed:
        print(f"PRUNED: {directory}: {len(removed)} file(s) the manifest no longer names: {', '.join(removed)}")


def whole_pair(value, label: str) -> tuple[int, int]:
    """A [width, height] or [x, y] pair, the only geometry shape pack.json uses."""
    require(isinstance(value, list) and len(value) == 2 and all(type(item) is int for item in value),
            f"{label} must be a [x, y] pair of whole numbers; found {value!r}")
    return (value[0], value[1])


def resolve_density_filter(pack: dict) -> tuple[int, str]:
    """The pack-wide density and style rules, defaulted per schema version.

    Schema 1 means exactly the original rules and carries no new keys at all.
    Schema 2 declares `density`; `filter` defaults to the look that density
    implies, and the strict v1 look is the only one allowed at density 1.
    """
    version = pack.get("schema_version")
    require(type(version) is int and version in (1, 2), f"Unsupported schema version: {version!r}; this build understands 1 and 2")
    if version == 1:
        stray = sorted({"density", "filter"} & set(pack))
        require(not stray, f"schema 1 is density 1 / nearest and may not declare {', '.join(stray)}; set schema_version to 2 to use it")
        return 1, "nearest"
    density = pack.get("density")
    require(type(density) is int and density in DENSITIES, f"schema 2 needs \"density\" to be one of {', '.join(map(str, DENSITIES))}; found {density!r}")
    name = pack.get("filter", "nearest" if density == 1 else "linear")
    require(name in FILTERS, f"\"filter\" must be {' or '.join(map(repr, FILTERS))}; found {name!r}")
    # Density 1 is the shipped pixel look, and it stays guaranteed: soft edges
    # need a denser canvas to be painted on, not a relaxed rule at 32px.
    require(not (name == "linear" and density == 1), "\"linear\" needs density 2 or more; density 1 keeps the strict v1 pixel rules")
    return density, name


def contract_size(pack: dict, category: str, info: dict) -> tuple[int, int]:
    """The density-1 pixel size pack.json promises for one asset."""
    if category == "tiles":
        return (pack["tile_size"], pack["tile_size"])
    return whole_pair(info.get("size"), "size")


def source_factor(image: Image.Image, expected: tuple[int, int], label: str, density: int) -> int:
    """How many pixels this PNG spends per density-1 pixel; anything else is rejected by name."""
    width, height = expected
    factor = image.width // width if width else 0
    if factor in DENSITIES and (image.width, image.height) == (width * factor, height * factor):
        # Denser than the pack is a decision for the pack, not a silent downscale.
        require(factor <= density, f"Source denser than the pack: {label} is {image.width}x{image.height} = {factor}x the {width}x{height} contract, but the pack is density {density}. Raise the pack density to {factor}, or repaint it at {width * density}x{height * density} or smaller")
        return factor
    allowed = ", ".join(f"{width * k}x{height * k}" for k in DENSITIES if k <= density)
    raise ValueError(f"RGBA/size mismatch: {label} is {image.width}x{image.height}; at density {density} the allowed sizes are {allowed}")


def upscale(image: Image.Image, factor: int) -> Image.Image:
    """Fill a lower-density source in at the pack density: blocky by design, never resampled."""
    if factor == 1:
        return image
    return image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST)


def source_path(source, relative):
    path = (source / relative).resolve()
    require(path.is_relative_to(source.resolve()), f"Path escapes art pack: {relative}")
    require(path.is_file(), f"pack.json lists a file that is not in the pack: {relative}")
    return path


def check_sprite_geometry(category: str, name: str, info: dict, size: tuple[int, int]):
    """A prop or UI image declares a canvas, an anchor inside it, and maybe slice margins."""
    width, height = size
    require(width > 0 and height > 0, f"{category}/{name} declares an empty canvas: {list(size)}")
    x, y = whole_pair(info.get("pivot"), f"{category}/{name} pivot")
    # Inclusive: a foot anchor sits on the bottom edge, which is y == height.
    require(0 <= x <= width and 0 <= y <= height,
            f"Pivot outside the canvas: {category}/{name} anchors at ({x}, {y}) on a {width}x{height} image")
    if "nine_patch" in info:
        margins = info["nine_patch"]
        require(isinstance(margins, list) and len(margins) == 4 and all(type(m) is int and m >= 0 for m in margins),
                f"{category}/{name} nine_patch must be four whole margins [left, top, right, bottom]; found {margins!r}")
        require(margins[0] + margins[2] < width and margins[1] + margins[3] < height,
                f"{category}/{name} nine_patch margins {margins} leave no stretchable middle in {width}x{height}")


ITEM_KEYS = {"place", "footprint", "blocks", "group", "weight"}
ITEM_PLACES = ("desk", "floor", "wall")
GROUP_NAME = re.compile(r"[a-z0-9_]+")
## A desk item stands on a table's working plane (docs/ITEMS.md): its opaque
## pixels only in unit rows DESK_ROWS of its canvas (under the divider, above
## the lip, two rows under the foot). Its width needs no rule: its 24-unit
## canvas, 28 left of its column, already clears the laptop and the paper stack.
DESK_ROWS = (3, 21)


def check_item(name: str, item, size: tuple[int, int], image: Image.Image, factor: int) -> None:
    """A prop's `item` block (docs/ITEMS.md), the rules ArtPack._read_item() holds
    at run time, and a desk item's measured pixels against the desk plane."""
    where = f"props/{name} item"
    require(isinstance(item, dict), f"{where} is not a JSON object")
    unknown = sorted(set(item) - ITEM_KEYS)
    require(not unknown, f"{where} has keys it does not know: {unknown}")
    place = item.get("place")
    require(place in ITEM_PLACES, f"{where} place is {place!r}, not one of {list(ITEM_PLACES)}")
    if "footprint" in item:
        w, d = whole_pair(item["footprint"], f"{where} footprint")
        require(1 <= w <= size[0] and d >= 1, f"{where} footprint {[w, d]} is empty or wider than its {size[0]}-unit canvas")
    else:
        require(place == "wall", f"{where}: a {place} item needs a footprint [w, d]")
    if "blocks" in item:
        # Only true for now: the walk graph takes every floor footprint as an obstacle.
        require(item["blocks"] is True and place == "floor", f"{where} blocks is only true, on a floor item, for now")
    if "group" in item:
        require(isinstance(item["group"], str) and GROUP_NAME.fullmatch(item["group"]) is not None,
                f"{where} group {item['group']!r} is not [a-z0-9_]+")
    if "weight" in item:
        require(type(item["weight"]) is int and item["weight"] >= 0 and "group" in item,
                f"{where} weight is a whole number >= 0 for an item in a group")
    if place == "desk":
        _left, top, _right, bottom = image.getchannel("A").getbbox()
        rows = (top // factor, (bottom - 1) // factor)
        require(DESK_ROWS[0] <= rows[0] and rows[1] <= DESK_ROWS[1],
                f"{where}: a desk item is opaque only in rows {DESK_ROWS[0]}..{DESK_ROWS[1]}; this one spans {rows[0]}..{rows[1]}")


def validate(source: Path, pack: dict) -> Compiled:
    density, filter_name = resolve_density_filter(pack)
    ## `nearest` is the v1 pixel discipline; `linear` relaxes only the rules a
    ## painted, anti-aliased style cannot keep. Everything structural is shared.
    strict = filter_name == "nearest"
    # The office names the pack in its top bar and finds it by directory, so both
    # have to be there before anything else is worth checking.
    for key in ("id", "name"):
        require(isinstance(pack.get(key), str) and pack[key], f"Pack needs a non-empty {key}")
    require(pack["tile_size"] == 32, "tile_size stays 32 at every density: pack.json geometry is in density-1 pixels")
    for category in CATEGORIES:
        require(isinstance(pack.get(category), dict) and pack[category], f'"{category}" must be a non-empty JSON object')
    require(isinstance(pack.get("palette"), dict) and pack["palette"], '"palette" must be a non-empty JSON object')
    for key, value in pack["palette"].items():
        require(isinstance(value, str) and HEX_COLOR.fullmatch(value), f"Palette entry must be six lowercase hex digits: {key}")
    ## Referential integrity inside the pack. Which states have to exist is the
    ## scenes' business (ArtContract.STATES, checked by `make check-packs`); what
    ## this build checks is that the ones declared here point at art that is
    ## here, and the one mapping nobody may quietly change.
    animations = people_animations()
    require(isinstance(pack.get("states"), dict) and pack["states"], '"states" must be a non-empty JSON object')
    for state, info in pack["states"].items():
        require(info.get("animation") in animations,
                f"State {state} plays \"{info.get('animation')}\", which the pixel people cannot animate; {PEOPLE_CONTRACT.name} maps {', '.join(sorted(animations))}")
        require(info.get("badge") in pack["ui"], f"State {state} wears \"{info.get('badge')}\", which is not one of this pack's ui images")
    require("done" not in pack["states"] or pack["states"]["done"]["badge"] == "unread", "done must remain unread, not task success")
    # Optional, additive in schema v1: packs that leave it out get the built-in dim.
    if "stale_modulate" in pack:
        require(isinstance(pack["stale_modulate"], str) and HEX_COLOR.fullmatch(pack["stale_modulate"]), "stale_modulate must be six lowercase hex digits")
    # Likewise optional and additive: absent means the daylight strength.
    if "task_lights" in pack:
        name = pack["task_lights"]
        require(name in TASK_LIGHTS, f"\"task_lights\" must be {' or '.join(map(repr, TASK_LIGHTS))}; found {name!r}")
    width, height = whole_pair(pack.get("atlas_size"), "atlas_size")
    require(width > 0 and height > 0 and width % 32 == height % 32 == 0, "Atlas must use whole cells")
    occupied = set()
    images, factors = {}, {}
    palette = {tuple(bytes.fromhex(value)) for value in pack["palette"].values()}
    for category in CATEGORIES:
        for name, info in pack[category].items():
            require(isinstance(info, dict) and isinstance(info.get("path"), str), f"{category}/{name} names no image file")
            with Image.open(source_path(source, info["path"])) as opened:
                image = opened.copy()
            require(image.mode == "RGBA", f"RGBA/size mismatch: {category}/{name} is mode {image.mode}, not RGBA")
            expected = contract_size(pack, category, info)
            ## Every pixel measure below is a v1 literal times this image's own
            ## factor, so a half-repainted pack is checked at the size it is
            ## actually painted at rather than at the pack's declared density.
            k = source_factor(image, expected, f"{category}/{name}", density)
            if strict:
                colors = image.getcolors(image.width * image.height)
                require(all(pixel[3] in (0, 255) for _, pixel in colors), f"Soft alpha: {category}/{name}")
                require(all(pixel[:3] in palette for _, pixel in colors if pixel[3]), f"Color outside palette: {category}/{name}")
            require(image.getchannel("A").getbbox() is not None, f"Empty sprite: {category}/{name}")
            if category == "tiles":
                x, y = whole_pair(info.get("cell"), f"tile {name} cell")
                require(0 <= x < width // 32 and 0 <= y < height // 32, f"Tile out of atlas: {name}")
                require((x, y) not in occupied, f"Duplicate atlas cell: {name}")
                occupied.add((x, y))
                if name.startswith(SOLID_TILE_PREFIXES):
                    require(image.getchannel("A").getextrema() == (255, 255), f"Unexpected floor/wall hole: {name}")
            else:
                check_sprite_geometry(category, name, info, expected)
                if "item" in info:
                    require(category == "props", f"{category}/{name}: only a prop has an item block")
                    check_item(name, info["item"], expected, image, k)
            images[(category, name)] = upscale(image, density // k)
            factors[(category, name)] = k
    check_tile_connections(images, density)
    for key in ("path", "license"):
        # The OFL licence ships with the font; dropping it is not an option.
        source_path(source, pack["font"][key])
    for key in ("path", "license"):
        if "display_font" in pack:
            require(isinstance(pack["display_font"], dict) and isinstance(pack["display_font"].get(key), str),
                    f"display_font needs a {key}")
            source_path(source, pack["display_font"][key])
    return Compiled(images, factors, density, filter_name)


def check_tile_connections(images: dict, density: int) -> None:
    """Shared connection pixels are structural for both sampling filters.

    Names are discovered from the pack; this does not impose a second required
    semantic-ID list. Optional wall modules are checked when declared. A port
    compares just its shared edge, not unrelated floor/baseboard pixels.
    """
    tiles = {name: image for (category, name), image in images.items() if category == "tiles"}

    def pixels(name: str, box: tuple[int, int, int, int]) -> bytes:
        return tiles[name].crop(tuple(value * density for value in box)).tobytes()

    def joins(a: str, a_box: tuple[int, int, int, int], b: str,
              b_box: tuple[int, int, int, int], label: str) -> None:
        if a in tiles and b in tiles:
            require(pixels(a, a_box) == pixels(b, b_box), f"{label}: {a} and {b}")

    variants = sorted(name for name in tiles if name.startswith(VARIANT_TILE_PREFIX))
    for name in variants[1:]:
        for edge in ((0, 0, 32, 3), (0, 29, 32, 32), (0, 0, 3, 32), (29, 0, 32, 32)):
            joins(variants[0], edge, name, edge, "Wood variants have mismatched edge pixels")
    for name in tiles:
        if name.startswith("wall.cap_"):
            face = name.replace("wall.cap_", "wall.face_", 1)
            joins(name, (0, 31, 32, 32), face, (0, 0, 32, 1), "Wall course seam")
        if name.startswith(("wall.cap_", "wall.face_")):
            course, _, end = name.removeprefix("wall.").partition("_")
            center = f"wall.{course}_center"
            if end in ("left", "t_left", "center"):
                joins(name, (31, 0, 32, 32), center, (0, 0, 1, 32), "Wall horizontal seam")
            if end in ("right", "end_right", "center"):
                joins(center, (31, 0, 32, 32), name, (0, 0, 1, 32), "Wall horizontal seam")
    # Declaring the new topology opts the wall family into the six-unit side
    # profile. Legacy rectangular families are not silently reinterpreted.
    if "wall.cap_t_left" in tiles:
        for end in ("left", "right"):
            side = f"wall.side_{end}"
            x0, x1 = (0, 6) if end == "left" else (26, 32)
            joins(f"wall.face_{end}", (x0, 31, x1, 32), side,
                  (x0, 0, x1, 1), "Wall side port seam")
            joins(side, (0, 31, 32, 32), side, (0, 0, 32, 1), "Wall side repeat seam")
            if side in tiles:
                alpha = tiles[side].getchannel("A")
                port = tuple(value * density for value in (x0, 0, x1, 32))
                outside = (6, 0, 32, 32) if end == "left" else (0, 0, 26, 32)
                outside = tuple(value * density for value in outside)
                require(alpha.crop(port).getextrema() == (255, 255)
                        and alpha.crop(outside).getextrema() == (0, 0),
                        f"Wall side must occupy its six-unit profile: {side}")
        joins("wall.cap_t_left", (0, 0, 6, 1), "wall.side_left", (0, 31, 6, 32), "Wall T top port seam")
        joins("wall.face_t_left", (0, 31, 6, 32), "wall.side_left", (0, 0, 6, 1), "Wall T bottom port seam")


def build(source: Path, output: Path):
    require(not output.resolve().is_relative_to(source.resolve()) and not source.resolve().is_relative_to(output.resolve()), "Source and output directories must be separate")
    pack = json.loads((source / "pack.json").read_text())
    compiled = validate(source, pack)  # Reject invalid packs before touching runtime files.
    density = compiled.density
    atlas = Image.new("RGBA", tuple(value * density for value in pack["atlas_size"]))
    output.mkdir(parents=True, exist_ok=True)
    manifest = copy.deepcopy(pack)
    manifest["atlas"] = "terrain.png"
    if pack["schema_version"] >= 2:
        # Geometry in the manifest stays in density-1 units too; the runtime
        # multiplies by these two, which are always present from schema 2 on.
        manifest["density"] = density
        manifest["filter"] = compiled.filter
    for name, info in pack["tiles"].items():
        x, y = info["cell"]
        atlas.paste(compiled.images[("tiles", name)], (x * 32 * density, y * 32 * density))
        manifest["tiles"][name] = {"cell": info["cell"]}
    written = {output / "terrain.png"}
    save_if_pixels_moved(atlas, output / "terrain.png")
    for category in ("props", "ui"):
        for name, info in pack[category].items():
            target = output / info["path"]
            written.add(target)
            if compiled.factors[(category, name)] == density:
                # Already at the pack density: copy the artist's bytes untouched.
                mirror_png(source_path(source, info["path"]), target)
            else:
                save_if_pixels_moved(compiled.images[(category, name)], target)
    fonts = [pack["font"]] + ([pack["display_font"]] if "display_font" in pack else [])
    for face in fonts:
        for relative in (face["path"], face["license"]):
            copy_if_changed(source_path(source, relative), output / relative)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # The pack's own tree only; the shared table beside it has its own builder.
    report_pruned(output, prune_unreferenced(output, written))
    counted = sum(len(pack[category]) for category in CATEGORIES)
    summary = f"PASS: {counted} source PNGs; {len(pack['tiles'])} tiles; anchors; atlas; binary alpha; palette"
    if compiled.filter == "linear":
        # A painted pack was never held to hard alpha or exact palette colours.
        summary = f"PASS: {counted} source PNGs; {len(pack['tiles'])} tiles; anchors; atlas"
    if pack["schema_version"] >= 2:
        summary += f"; density {density}x; filter {compiled.filter}"
    print(summary)
    print(f"Built {output}")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="one art pack source to build; default is every pack under art/")
    parser.add_argument("--output", type=Path, help="runtime output for --source")
    args = parser.parse_args()
    if (args.source is None) != (args.output is None):
        parser.error("--source and --output must be supplied together")
    if args.source is not None:
        build(args.source, args.output)
        return
    found = packs()
    if not found:
        raise SystemExit(f"build_assets: no pack.json under {ROOT / 'art'}")
    for pack in found:
        build(pack, ROOT / "assets" / pack.name)


if __name__ == "__main__":
    main()
