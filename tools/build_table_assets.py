"""Validate and copy the shared-table source art without repainting it.

Normal builds only read art/<theme>/table and write assets/<theme>/table.
daylight is editable; derive_theme.py recolours it into dusk using its recipe.
The module geometry is in density-1 units; the PNGs hold DENSITY texture pixels
per unit, sampled nearest, so every canvas is its size in units times DENSITY.

The procedural drawings are authoring templates, available only through
--templates into an empty directory (`make table-templates`, and inside
`make pixel-sources`). Review and copy selected templates into
art/daylight/table explicitly; normal builds never invoke the drawing code.

The drawing code works in units on a density-1 canvas and each template is
blown up by DENSITY, nearest, as it is written. A shell view is derived from its
monitor view by shell_mark() at DENSITY, so a repainted monitor gets its shell
the same way.

What every drawing keeps, because OfficeTable and the tests stand on it (all
numbers are world units; a probe in the PNG is the unit times DENSITY):

- surface_* 32x80: opaque rows 0..74, transparent 75..79. Rows 0..71 are the
  working top, 72..74 the lip the three-row apron continues; rows 28..51 lie
  under the divider. The three outer columns on each side of a module are one
  uniform column, so any module meets any other without a seam.
- apron_* 32x3 and divider_* 32x24: fully opaque.
- leg 20x40: last opaque row 38, so the foot stands on y 37 below its mount at
  y -2; every row is attached; ankle and glide are narrower than the shoulder.
- chair_front / chair_back 32x48: nothing above row 22 (at most 24 units
  tall), centred on x 16 and at most 18 wide, feet on row 45 over the pivot
  [16, 46], a backrest over (16, 26), a seat over (16, 35), a gas-lift column
  at row 39 (opaque at x 16, clear at x 12 and 20), and the two views differ.
- monitor_* / shell_* 32x32, drawn texel by texel: at most 14 wide (columns
  9..22, centred on x 16), feet on row 29 over the pivot [16, 30]; the rear
  starts at row 22 or lower, the front at row 19 or lower. A shell view is its
  normal view plus a `$_` mark with the same silhouette: ink on the rear lid,
  paper on the front screen, its cursor at CURSOR_AT (texels).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from build_assets import copy_if_changed, prune_unreferenced, report_pruned, require, upscale


ROOT = Path(__file__).resolve().parents[1]
PACKS = (ROOT / "art/daylight", ROOT / "art/dusk")
DENSITY = 2

MODULES: dict[str, tuple[int, int]] = {
    "surface_left": (32, 80),
    "surface_mid_a": (32, 80),
    "surface_mid_b": (32, 80),
    "surface_right": (32, 80),
    "apron_left": (32, 3),
    "apron_mid": (32, 3),
    "apron_right": (32, 3),
    "divider_left": (32, 24),
    "divider_mid": (32, 24),
    "divider_right": (32, 24),
    "leg": (20, 40),
    "bracket": (12, 10),
}

FURNITURE: dict[str, tuple[int, int]] = {
    "chair_front": (32, 48),
    "chair_back": (32, 48),
    "monitor_rear": (32, 32),
    "monitor_front": (32, 32),
    "shell_rear": (32, 32),
    "shell_front": (32, 32),
}


def rgba(palette: dict[str, str], name: str, alpha: int = 255) -> tuple[int, int, int, int]:
    return (*bytes.fromhex(palette[name]), alpha)


def image(size: tuple[int, int]) -> Image.Image:
    """A transparent density-1 canvas: the drawings work in units."""
    return Image.new("RGBA", size, (0, 0, 0, 0))


def rect(target: Image.Image, bounds: tuple[int, int, int, int], fill: tuple[int, int, int, int]) -> None:
    """Fill (x, y, width, height) with one colour; an empty rectangle draws nothing."""
    x, y, width, height = bounds
    if width <= 0 or height <= 0:
        return
    target.paste(fill, (x, y, x + width, y + height))


def pixel_map(target: Image.Image, rows: tuple[str, ...], legend: dict[str, str], palette: dict[str, str],
              at: tuple[int, int] = (0, 0)) -> Image.Image:
    """Paint rows of legend letters onto `target` from `at`; a '.' leaves the pixel as it is.

    Every letter names a palette key through `legend`, so a drawing can only
    ever hold the pack's own colours and dusk stays an exact substitution.
    """
    left, top = at
    width = len(rows[0])
    for y, row in enumerate(rows):
        require(len(row) == width, f"pixel map row {y} is {len(row)} wide, not {width}")
        require(left >= 0 and top >= 0 and left + width <= target.width and top + y < target.height,
                f"pixel map row {y} leaves the {target.width}x{target.height} canvas")
        for x, letter in enumerate(row):
            if letter != ".":
                target.putpixel((left + x, top + y), rgba(palette, legend[letter]))
    return target


## Plank seams across both working planes (the divider hides rows 28..51), and
## each grain variant's light flecks as (row, first column, length). Flecks keep
## to columns 3..28, so the three edge columns of every module stay uniform.
SURFACE_SEAMS = (10, 19, 58, 65)
SURFACE_GRAIN = {
    "a": ((5, 6, 7), (14, 17, 9), (23, 4, 6), (55, 12, 8), (62, 20, 6), (69, 5, 9)),
    "b": ((6, 15, 9), (15, 4, 6), (24, 18, 8), (54, 5, 7), (61, 9, 10), (68, 17, 8)),
}


def surface(palette: dict[str, str], variant: str, cap: str | None) -> Image.Image:
    """Oak boards along the table, seen from above and lit from the top-left.

    The far edge is outlined and catches the light, seams are single dark rows
    and the grain a few calm light flecks: a large surface, so no dithering.
    The near edge is a highlight over the lip's two shaded rows.
    """
    result = image(MODULES["surface_mid_a"])
    deep, light, wood, shadow = (rgba(palette, key) for key in ("deep", "wood_light", "wood", "wood_shadow"))
    rect(result, (0, 0, 32, 72), wood)
    rect(result, (0, 0, 32, 1), deep)
    rect(result, (0, 1, 32, 1), light)
    for y in SURFACE_SEAMS:
        rect(result, (0, y, 32, 1), shadow)
    # The raised divider stands on rows 28..51 and shades the row below it.
    rect(result, (0, 52, 32, 1), shadow)
    grain = rgba(palette, "floor")
    for y, x, length in SURFACE_GRAIN[variant]:
        rect(result, (x, y, length, 1), grain)
    rect(result, (0, 72, 32, 1), light)
    rect(result, (0, 73, 32, 2), shadow)
    if cap == "left":
        rect(result, (0, 0, 1, 75), deep)
        rect(result, (1, 1, 1, 72), light)
    elif cap == "right":
        rect(result, (31, 0, 1, 75), deep)
        rect(result, (30, 2, 1, 70), shadow)
    return result


def apron(palette: dict[str, str], cap: str | None) -> Image.Image:
    """The rest of the table's front face under the lip, closed by an outline."""
    result = image(MODULES["apron_mid"])
    rect(result, (0, 0, 32, 1), rgba(palette, "wood_shadow"))
    rect(result, (0, 1, 32, 1), rgba(palette, "wood_dark"))
    rect(result, (0, 2, 32, 1), rgba(palette, "deep"))
    if cap == "left":
        rect(result, (0, 0, 1, 3), rgba(palette, "deep"))
    elif cap == "right":
        rect(result, (31, 0, 1, 3), rgba(palette, "deep"))
    return result


def divider(palette: dict[str, str], cap: str | None) -> Image.Image:
    """A raised privacy screen: a wooden rail over upholstered panels, one every eight units.

    The panel rhythm repeats every 8 columns, which divides 32, so modules in
    any order continue it; only the end posts differ.
    """
    result = image(MODULES["divider_mid"])
    deep, light, wood, dark = (rgba(palette, key) for key in ("deep", "wood_light", "wood", "wood_dark"))
    sage, sage_light, sage_dark = (rgba(palette, key) for key in ("sage", "sage_light", "sage_dark"))
    rect(result, (0, 0, 32, 1), deep)
    rect(result, (0, 1, 32, 1), light)
    rect(result, (0, 2, 32, 1), wood)
    rect(result, (0, 3, 32, 1), dark)
    rect(result, (0, 4, 32, 16), sage)
    rect(result, (0, 4, 32, 1), sage_dark)
    rect(result, (0, 5, 32, 1), sage_light)
    for x in range(7, 32, 8):
        rect(result, (x, 5, 1, 15), sage_dark)
    rect(result, (0, 20, 32, 2), sage_dark)
    rect(result, (0, 22, 32, 1), dark)
    rect(result, (0, 23, 32, 1), deep)
    if cap == "left":
        rect(result, (0, 0, 1, 24), deep)
        rect(result, (1, 1, 1, 22), light)
        rect(result, (2, 1, 1, 22), wood)
    elif cap == "right":
        rect(result, (31, 0, 1, 24), deep)
        rect(result, (30, 1, 1, 22), dark)
        rect(result, (29, 1, 1, 22), wood)
    return result


def leg(palette: dict[str, str]) -> Image.Image:
    """A tapered oak leg under a dark mount, on a small glide.

    OfficeTable hangs this canvas at y -2, so the last opaque row, 38, puts the
    foot on the floor at y 37. The shaft steps in twice on its way down.
    """
    result = image(MODULES["leg"])
    deep, light, wood, shadow = (rgba(palette, key) for key in ("deep", "wood_light", "wood", "wood_shadow"))
    rect(result, (3, 0, 14, 3), deep)
    rect(result, (4, 1, 12, 1), rgba(palette, "wood_dark"))
    for top, bottom, left, right in ((3, 13, 6, 14), (13, 25, 7, 13), (25, 35, 8, 12)):
        rect(result, (left, top, right - left, bottom - top), deep)
        rect(result, (left + 1, top, 1, bottom - top), light)
        rect(result, (left + 2, top, right - left - 4, bottom - top), wood)
        rect(result, (right - 2, top, 1, bottom - top), shadow)
    rect(result, (8, 35, 4, 4), deep)
    rect(result, (9, 36, 2, 2), rgba(palette, "slate"))
    return result


BRACKET = (
    ".KKKKKKKKKK.",
    ".KdddddddsK.",
    "..KddddddK..",
    "..KdddddsK..",
    "...KddddK...",
    "...KdddsK...",
    "....KddK....",
    "....KdsK....",
    "....KKKK....",
    ".....KK.....",
)


def bracket(palette: dict[str, str]) -> Image.Image:
    """The small corbel under each seat's stretch of edge, mostly hidden by the apron."""
    return pixel_map(image(MODULES["bracket"]), BRACKET, {"K": "deep", "d": "wood_dark", "s": "wood_shadow"}, palette)


## The first office chair, kept as an authoring template only: the shipped
## chairs are painted, 17 wide over rows 24..45 (the docstring holds their
## contract). One office chair, 22 wide (columns 5..26), feet on row 45, an
## open frame between backrest and seat. The two views differ in more than colour: a far
## chair (front view) sits four units behind its worker, so its backrest rises
## over the seated head (rows 16..27) and reads as a chair, not as two blobs
## beside the face; a near chair (back view) sits in front of its worker, so
## its backrest stays below the head (rows 21..27) and the worker stays seen.
CHAIR_BACKREST = {
    # The far chair faces the viewer: an upholstered cushion, lit on top.
    "front": (
        "...KKKKKKKKKKKKKKKK...",
        "..KTTTTTTTTTTTTTTTTK..",
        ".KTTttttttttttttttuuK.",
        ".KTtttttttttttttttuuK.",
        ".KTtttttttttttttttuuK.",
        ".KTtttttttttttttttuuK.",
        ".KTtuuuuuuuuuuuuuuuuK.",
        ".KTtttttttttttttttuuK.",
        ".KTtttttttttttttttuuK.",
        ".KTtttttttttttttttuuK.",
        "..KuuuuuuuuuuuuuuuuK..",
        "...KKKKKKKKKKKKKKKK...",
    ),
    # The near chair shows the back of its shell: a lit top edge, a handle
    # slot across the middle, a shaded foot.
    "back": (
        "...KKKKKKKKKKKKKKKK...",
        "..KTTTTTTTTTTTTTTTTK..",
        ".KTttttttttttttttttuK.",
        ".KttuuuuuuuuuuuuuttuK.",
        ".KtttttttttttttttttuK.",
        "..KuuuuuuuuuuuuuuuuK..",
        "...KKKKKKKKKKKKKKKK...",
    ),
}
CHAIR_BACKREST_TOP = {"front": 16, "back": 21}
CHAIR_SEAT = {
    "front": (
        ".....KS........KS.....",
        ".....KS........KS.....",
        ".KKKKKKKKKKKKKKKKKKKK.",
        "KTTTTTTTTTTTTTTTTTTTTK",
        "KTtttttttttttttttttuuK",
        "KSSSSSSSSSSSSSSSSSSSSK",
        ".KKKKKKKKKKKKKKKKKKKK.",
    ),
    "back": (
        ".....KS........KS.....",
        ".....KS........KS.....",
        ".KKKKKKKKKKKKKKKKKKKK.",
        "KtttttttttttttttttttuK",
        "KuuuuuuuuuuuuuuuuuuuuK",
        "KSSSSSSSSSSSSSSSSSSSSK",
        ".KKKKKKKKKKKKKKKKKKKK.",
    ),
}
CHAIR_BASE = (
    ".........KMSK.........",
    ".........KMSK.........",
    ".........KMSK.........",
    ".........KMSK.........",
    ".........KMSK.........",
    "......KKKKMSKKKK......",
    "...KKKSSSSMMSSSSKKK...",
    ".KKSSSKKKKSSKKKKSSSKK.",
    "KSKK.....KSSK.....KKSK",
    "KKK......KKKK......KKK",
    ".K........KK........K.",
)
CHAIR_LEGEND = {
    "K": "deep", "S": "slate", "M": "muted",
    "T": "jacket_light", "t": "jacket", "u": "ink",
}


def chair(palette: dict[str, str], view: str) -> Image.Image:
    """The chair from the front (the far seat's, facing the viewer) or from the back (the near seat's)."""
    result = image(FURNITURE["chair_front"])
    pixel_map(result, CHAIR_BACKREST[view], CHAIR_LEGEND, palette, (5, CHAIR_BACKREST_TOP[view]))
    pixel_map(result, CHAIR_SEAT[view], CHAIR_LEGEND, palette, (5, 28))
    pixel_map(result, CHAIR_BASE, CHAIR_LEGEND, palette, (5, 35))
    return result


## A silver laptop, 14 units wide (columns 9..22), drawn texel by texel at the
## family's density: at 14 units a unit-thick outline would leave no room
## inside, so its outline is one texel, like the chairs and the people. From
## behind: the lid with its dark mark over the hinge and the base (texel rows
## 44..59, units 22..29). From the front: the screen over the keyboard deck and
## its centred trackpad (texel rows 38..59, units 19..29). Top-left texel of
## each map, on the 64x64 canvas:
LAPTOP_AT = {"rear": (18, 44), "front": (18, 38)}
LAPTOP_REAR = (
    ".KKKKKKKKKKKKKKKKKKKKKKKKKK.",
    "KYYYYYYYYYYYYYYYYYYYYYYYYYYK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMIIMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMIIMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMJK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMJK",
    "KJJJJJJJJJJJJJJJJJJJJJJJJJJK",
    "KKKKKKKKKKKKKKKKKKKKKKKKKKKK",
    "KSMMMMMMMMMMMMMMMMMMMMMMMMSK",
    "KSMMMMMMMMMMMMMMMMMMMMMMMMSK",
    "KSSSSSSSSSSSSSSSSSSSSSSSSSSK",
    ".KKKKKKKKKKKKKKKKKKKKKKKKKK.",
)
LAPTOP_FRONT = (
    ".KKKKKKKKKKKKKKKKKKKKKKKKKK.",
    "KJJJJJJJJJJJJJJJJJJJJJJJJJJK",
    *(("KJDDDDDDDDDDDDDDDDDDDDDDDDSK",) * 9),
    "KSSSSSSSSSSSSSSSSSSSSSSSSSSK",
    "KKKKKKKKKKKKKKKKKKKKKKKKKKKK",
    "KMSSSSSSSSSSSSSSSSSSSSSSSSMK",
    "KMS" + "DS" * 11 + "SMK",
    "KMSSSSSSSSSSSSSSSSSSSSSSSSMK",
    "KMSS" + "DS" * 11 + "MK",
    "KMSSSSSSSSSSSSSSSSSSSSSSSSMK",
    "KMMMMMMMMMMJJJJJJMMMMMMMMMMK",
    "KMMMMMMMMMMJJJJJJMMMMMMMMMMK",
    "KMMMMMMMMMMMMMMMMMMMMMMMMMMK",
    ".KKKKKKKKKKKKKKKKKKKKKKKKKK.",
)
LAPTOP_LEGEND = {
    "K": "deep", "D": "deep", "S": "slate", "M": "muted", "J": "jacket_light",
    "Y": "sky_light", "I": "ink",
}
## An agent's screen shows two lines of output, a shell's its prompt (texels:
## x, y, width, key).
SCREEN_LINES = ((21, 42, 12, "sky_dark"), (21, 44, 8, "slate"))
## The rear lid's mark (texels: x, y, width, height), silver on a shell's lid.
LID_MARK = (31, 49, 2, 2)
## Deliberately $_, not the >_ speech badge used by working agents: a texel
## glyph, its top-left texel and the cursor after it, per view. The rear's is
## centred on the lid, the front's starts at the screen's left like a prompt.
PROMPT = ("..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#..")
PROMPT_AT = {"rear": (27, 46), "front": (21, 41)}
## The cursor's first texel; tools/test_table_assets.py probes it.
CURSOR_AT = {"rear": (33, 52), "front": (27, 47)}
CURSOR_WIDTH = 4


def laptop(palette: dict[str, str], rear: bool) -> Image.Image:
    """The laptop at a seat, seen from behind (far seats) or from the front
    (near seats), already at the family's density (generate_templates does
    not blow it up)."""
    view = "rear" if rear else "front"
    width, height = FURNITURE[f"monitor_{view}"]
    result = Image.new("RGBA", (width * DENSITY, height * DENSITY), (0, 0, 0, 0))
    pixel_map(result, LAPTOP_REAR if rear else LAPTOP_FRONT, LAPTOP_LEGEND, palette, LAPTOP_AT[view])
    if not rear:
        for x, y, line, key in SCREEN_LINES:
            rect(result, (x, y, line, 1), rgba(palette, key))
    return result


def shell_mark(monitor: Image.Image, view: str, palette: dict[str, str], density: int = DENSITY) -> Image.Image:
    """A shell's laptop: a copy of `monitor` (the `rear` or `front` view, at
    the family's density) with the `$_` prompt in place of what an agent's
    laptop shows, the silhouette untouched.

    The rear loses the maker's mark on its lid to silver and takes the prompt
    in ink; the front loses its two lines of output to the dark screen and
    takes the prompt in paper. Texel coordinates: the laptop is drawn texel by
    texel, so its marks are too.
    """
    require(view in ("rear", "front"), f"shell_mark: no {view!r} view")
    require(density == DENSITY, f"shell_mark: the laptop is drawn at density {DENSITY}, not {density}")
    expected = tuple(value * density for value in FURNITURE[f"monitor_{view}"])
    require(monitor.size == expected, f"shell_mark: the {view} monitor is {monitor.size}, not {expected}")
    result = monitor.copy()
    if view == "rear":
        rect(result, LID_MARK, rgba(palette, "muted"))
    else:
        for x, y, line, _ in SCREEN_LINES:
            rect(result, (x, y, line, 1), rgba(palette, "deep"))
    mark = rgba(palette, "ink" if view == "rear" else "paper")
    left, top = PROMPT_AT[view]
    for y, row in enumerate(PROMPT):
        for x, pixel in enumerate(row):
            if pixel == "#":
                result.putpixel((left + x, top + y), mark)
    rect(result, (*CURSOR_AT[view], CURSOR_WIDTH, 1), mark)
    return result


def generate_templates(source: Path, output: Path) -> None:
    """Draw fresh artist canvases, never overwrite an existing source tree."""
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError(f"Output must be an empty directory: {output}")
    pack = json.loads((source / "pack.json").read_text())
    palette = pack["palette"]

    surface_left = surface(palette, "a", "left")
    surface_mid_a = surface(palette, "a", None)
    surface_mid_b = surface(palette, "b", None)
    surface_right = surface(palette, "b", "right")
    makers: dict[str, Image.Image] = {
        "surface_left": surface_left,
        "surface_mid_a": surface_mid_a,
        "surface_mid_b": surface_mid_b,
        "surface_right": surface_right,
        "apron_left": apron(palette, "left"),
        "apron_mid": apron(palette, None),
        "apron_right": apron(palette, "right"),
        "divider_left": divider(palette, "left"),
        "divider_mid": divider(palette, None),
        "divider_right": divider(palette, "right"),
        "leg": leg(palette),
        "bracket": bracket(palette),
        "chair_front": chair(palette, "front"),
        "chair_back": chair(palette, "back"),
    }
    # Drawn in units, written at the family's density; the laptop is drawn at
    # that density already. The shells are marked on the written monitors, the
    # way a repainted monitor gets its shell.
    sprites = {name: upscale(sprite, DENSITY) for name, sprite in makers.items()}
    sprites["monitor_rear"] = laptop(palette, True)
    sprites["monitor_front"] = laptop(palette, False)
    for view in ("rear", "front"):
        sprites[f"shell_{view}"] = shell_mark(sprites[f"monitor_{view}"], view, palette, DENSITY)
    manifest = table_manifest(pack)
    output.mkdir(parents=True, exist_ok=True)
    for name, sprite in sprites.items():
        sprite.save(output / f"{name}.png")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"TABLE_TEMPLATES_OK: {output} ({len(sprites)} editable modules at {DENSITY}x)")


def table_manifest(pack: dict) -> dict:
    """The fixed native furniture contract, shared by templates and validation."""
    sizes = {**MODULES, **FURNITURE}
    return {
        "schema_version": 2,
        "density": DENSITY,
        "filter": "nearest",
        "id": f"{pack['id']}-shared-table",
        "name": f"{pack['name']} shared table",
        "modules": {
            name: {"path": f"{name}.png", "size": list(sizes[name])}
            for name in sizes
        },
        "furniture": {
            "chair": {
                "size": list(FURNITURE["chair_front"]),
                "pivot": [16, 46],
                "views": {"front": "chair_front", "back": "chair_back"},
            },
            "monitor": {
                "size": list(FURNITURE["monitor_front"]),
                "pivot": [16, 30],
                "views": {
                    "rear_shell": "monitor_rear", "front_privacy": "monitor_front",
                    "shell_rear": "shell_rear", "shell_front": "shell_front",
                },
            },
        },
        "assembly": {
            "module_width": 32,
            "surface_depth": 80,
            "divider_height": 24,
            "apron_height": 3,
        },
    }


def validate_source(source: Path) -> dict:
    """Validate the entire companion before any build output is changed."""
    path = source / "table/manifest.json"
    try:
        pack = json.loads((source / "pack.json").read_text())
        manifest = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ValueError(f"{path}: {error}") from error
    require(manifest == table_manifest(pack), f"{path}: manifest does not match the native table contract")
    for name, size in {**MODULES, **FURNITURE}.items():
        path = source / "table" / f"{name}.png"
        try:
            with Image.open(path) as sprite:
                require(sprite.format == "PNG" and sprite.mode == "RGBA", f"{path}: must be an RGBA PNG")
                expected = tuple(value * DENSITY for value in size)
                require(sprite.size == expected, f"{path}: expected {expected}, found {sprite.size}")
                require(sprite.getchannel("A").getbbox() is not None, f"{path}: image is empty")
        except OSError as error:
            raise ValueError(f"{path}: {error}") from error
    return manifest


def build_pack(source: Path, output: Path) -> None:
    require(not (output.resolve().is_relative_to(source.resolve())
                 or source.resolve().is_relative_to(output.resolve())),
            "source and output must not overlap")
    manifest = validate_source(source)
    source_table = source / "table"
    output_table = output / "table"
    files = [info["path"] for info in manifest["modules"].values()]
    for name in files:
        copy_if_changed(source_table / name, output_table / name)
    copy_if_changed(source_table / "manifest.json", output_table / "manifest.json")
    # Only the runtime tree belongs to this builder. Unlisted source sketches
    # and their sidecars belong to the artist and must not be pruned.
    report_pruned(output_table, prune_unreferenced(output_table, [output_table / name for name in files]))
    print(f"TABLE_ASSETS_OK: {source} -> {output} ({len(files)} modules at {DENSITY}x)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="one art pack source to build")
    parser.add_argument("--output", type=Path, help="runtime output for --source")
    parser.add_argument("--templates", type=Path, help="author fresh templates into an empty directory instead of building")
    args = parser.parse_args()
    if args.templates is not None and args.output is not None:
        parser.error("--templates and --output are mutually exclusive")
    if args.templates is None and (args.source is None) != (args.output is None):
        parser.error("--source and --output must be supplied together")
    try:
        if args.templates is not None:
            generate_templates(args.source or ROOT / "art/daylight", args.templates)
        elif args.source is not None:
            build_pack(args.source, args.output)
        else:
            for source in PACKS:
                build_pack(source, ROOT / "assets" / source.name)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"build_table_assets: {error}\n")


if __name__ == "__main__":
    main()
