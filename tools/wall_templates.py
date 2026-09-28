"""Author the office's finite wall modules into a new, empty directory.

These are new geometric drawings, not edits or composites of existing PNGs.
pack.json supplies the semantic IDs and palette. The exported PNGs become
editable source art; make art never runs this authoring tool or overwrites them.
The same profile can be exported at 1/2/4/8 pixels per world unit for a painter.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from build_assets import DENSITIES, ROOT

TILE = 32
WALL_HEIGHT = TILE * 2
EDGE_INK = 4
EDGE_SHADE = 2
EDGE = EDGE_INK + EDGE_SHADE


def wall_image(name: str, palette: dict[str, str], density: int = 1) -> Image.Image:
    """One cap/face/side cell, with geometry expressed in world units.

    cap + face occupy [0,32) x [0,64). Outer corners connect to a 6-unit
    side strip below; t_left also connects above. end_right closes at y=64
    and has no side continuation. Every module connects horizontally on its
    full 32-unit course edge. These are the only supported topology variants.
    """
    if type(density) is not int or density not in DENSITIES:
        raise ValueError(f"density must be one of {DENSITIES}")
    if not name.startswith("wall."):
        raise ValueError(f"Not a wall semantic ID: {name}")
    form = name.removeprefix("wall.")
    side = form.removeprefix("side_") if form.startswith("side_") else ""
    if side:
        if side not in ("left", "right"):
            raise ValueError(f"Unsupported wall side: {name}")
        course, end = "side", side
    else:
        course, _, end = form.partition("_")
        if course not in ("cap", "face") or end not in ("left", "center", "right", "t_left", "end_right"):
            raise ValueError(f"Unsupported wall module: {name}")
    image = Image.new("RGBA", (TILE * density, (TILE if side else WALL_HEIGHT) * density))
    pen = ImageDraw.Draw(image)

    def fill(box: tuple[int, int, int, int], color: str) -> None:
        x0, y0, x1, y1 = box
        rgb = tuple(bytes.fromhex(palette[color])) + (255,)
        pen.rectangle((x0 * density, y0 * density, x1 * density - 1, y1 * density - 1), fill=rgb)

    def strip(which: str, y0: int, y1: int) -> None:
        if which == "left":
            fill((0, y0, EDGE_INK, y1), "ink")
            fill((EDGE_INK, y0, EDGE, y1), "cream_shadow")
        else:
            fill((TILE - EDGE, y0, TILE - EDGE_INK, y1), "cream_shadow")
            fill((TILE - EDGE_INK, y0, TILE, y1), "ink")

    if side:
        strip(side, 0, TILE)
        return image

    # Preserve the established horizontal wall silhouette, sign/window face
    # and baseboard. Only the six-unit connection strips differ by topology.
    for y0, y1, color in (
        (0, 4, "ink"), (4, 8, "wood_shadow"), (8, 10, "wood_light"),
        (10, 12, "plaster"), (12, 57, "cream"), (57, 58, "cream_shadow"),
        (58, 60, "wood_light"), (60, WALL_HEIGHT, "wood_shadow"),
    ):
        fill((0, y0, TILE, y1), color)
    if end in ("left", "right"):
        # The outer corner starts at the top cap, then exposes exactly the
        # same 4+2 cross-section as the side wall at its lower connection.
        if end == "left":
            fill((0, 0, EDGE_INK, WALL_HEIGHT), "ink")
        else:
            fill((TILE - EDGE_INK, 0, TILE, WALL_HEIGHT), "ink")
        strip(end, 10, WALL_HEIGHT)
    elif end == "t_left":
        strip("left", 0, WALL_HEIGHT)
    elif end == "end_right":
        fill((TILE - EDGE_INK, 0, TILE, WALL_HEIGHT), "ink")
        strip("right", 10, WALL_HEIGHT - EDGE_INK)
        # A closed end has a bottom outline, not the side port of an outer
        # corner. Keep the adjoining center tile's full left edge untouched.
        fill((TILE - EDGE, WALL_HEIGHT - EDGE_INK, TILE, WALL_HEIGHT), "ink")
    top = 0 if course == "cap" else TILE * density
    return image.crop((0, top, TILE * density, top + TILE * density))


def generate(pack_path: Path, output: Path, density: int = 1) -> list[Path]:
    """Validate every drawing before creating files; refuse occupied outputs."""
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError(f"Output must be an empty directory: {output}")
    pack = json.loads(pack_path.read_text())
    drawings = {
        name: wall_image(name, pack["palette"], density)
        for name in pack["tiles"]
        if name.startswith(("wall.cap_", "wall.face_", "wall.side_"))
    }
    if not drawings:
        raise ValueError("The pack declares no supported wall modules")
    output.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for name, picture in drawings.items():
        target = output / f"{name}.png"
        picture.save(target)
        written.append(target)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, default=ROOT / "art/daylight/pack.json")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--density", type=int, choices=DENSITIES, default=1)
    args = parser.parse_args()
    try:
        written = generate(args.pack, args.output, args.density)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"wall_templates: {error}\n")
    print(f"WALL TEMPLATES: {len(written)} editable PNGs at {args.density}x in {args.output}")


if __name__ == "__main__":
    main()
