"""Validate and copy the shared-table source art without repainting it.

Normal builds only read art/<theme>/table and write assets/<theme>/table
(one theme today, daylight; night is a light over it, not a second pack).
The module geometry is in density-1 units; the PNGs hold DENSITY texture pixels
per unit, sampled nearest, so every canvas is its size in units times DENSITY.

The procedural drawings are authoring templates, available only through
--templates into an empty directory (`make table-templates`, and inside
`make pixel-sources`). Review and copy selected templates into
art/daylight/table explicitly; normal builds never invoke the drawing code.

The apron, the bracket and the chairs are drawn in units on a density-1
canvas and blown up by DENSITY, nearest, as they are written; the desks, the
screens, the short leg and the laptop are drawn texel by texel at DENSITY. A
shell view is derived from its monitor view by shell_mark() at DENSITY, so a
repainted monitor gets its shell the same way.

One source module set is accepted (SOURCE_SETS), the pod: what the office
draws and nothing else (POD_ONLY, 18 images). The pod's own 8 modules
(POD_MODULES), the near edge every desk hangs (POD_SHARED: the apron's three
and the bracket) and the 6 furniture views (FURNITURE), which is exactly the
runtime's ArtContract.TABLE_MODULES plus the furniture (a test holds the two
together). A source manifest declares exactly these names; one that declares
fewer, more or others is refused with what is missing and what is unknown.
The native manifest is built for the set, every image of it is required, and
the templates draw it.

What every drawing keeps, because OfficeTable and the tests stand on it (all
numbers are world units; a probe in the PNG is the unit times DENSITY):

- apron_* 32x3: fully opaque, the three rows that continue a desk's lip.
- bracket 12x10: the corbel under each seat's stretch of edge.
- chair_front / chair_back 32x48: nothing above row 22 (at most 24 units
  tall), centred on x 16 and at most 18 wide, feet on row 45 over the pivot
  [16, 46], a backrest over (16, 26), a seat over (16, 35), a gas-lift column
  at row 39 (opaque at x 16, clear at x 12 and 20), and the two views differ.
- monitor_* / shell_* 32x32, drawn texel by texel: at most 14 wide (columns
  9..22, centred on x 16), feet on row 29 over the pivot [16, 30]; the rear
  starts at row 22 or lower, the front at row 19 or lower. A shell view is its
  normal view plus a `$_` mark with the same silhouette: ink on the rear lid,
  paper on the front screen, its cursor at CURSOR_AT (texels).

What the pod's own drawings keep. They are drawn texel by texel at DENSITY in
the painted table's hand (unit-thick outlines and bands, one-texel grain and
panel lines); rows and columns below are units, pod-local y in brackets, the
far edge at y -48:

- desk_* 32x48: opaque rows 0..42, transparent 43..47. Rows 0..39 are the
  working top (-48..-8, ending at the near working edge -8), 40..42 the lip
  (-8..-5) the three-row apron continues; rows 16..21 (-32..-26) lie under the
  low screen, row 22 is its shadow. The far plane is rows 2..15, the near
  plane 23..39. The three outer columns on each side are one uniform column,
  so any desk module meets any other without a seam.
- screen_* 32x6: fully opaque, a wooden rail over a sage panel; its panel
  lines repeat every 8 units, which divides 32, so modules in any order
  continue them.
- leg_short 6x7: the pod's end leg, hung at LEG_DROP -2 (its mount right
  under the apron). Every row is opaque, so the foot ends at pod y 5: the
  near chair (chair_back, pushed in under the desk, its pivot at pod y 14)
  is opaque across x -5.5..+5.5 of its column over y -7..5.5 (below that only
  its gas-lift column and then its base), so a leg centred under an end
  column's near chair is wholly behind the chair's back, glide included,
  somebody in the chair or not. It is 6 wide (x -3..+3 of its centre), every
  row attached; the shaft steps in once and the ankle and glide are narrower
  than the shoulder.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from build_assets import copy_if_changed, prune_unreferenced, report_pruned, require, upscale


ROOT = Path(__file__).resolve().parents[1]
PACKS = (ROOT / "art/daylight",)
DENSITY = 2

FURNITURE: dict[str, tuple[int, int]] = {
    "chair_front": (32, 48),
    "chair_back": (32, 48),
    "monitor_rear": (32, 32),
    "monitor_front": (32, 32),
    "shell_rear": (32, 32),
    "shell_front": (32, 32),
}

## The small-desk pod's own modules (see the contract above).
POD_MODULES: dict[str, tuple[int, int]] = {
    "desk_left": (32, 48),
    "desk_mid_a": (32, 48),
    "desk_mid_b": (32, 48),
    "desk_right": (32, 48),
    "screen_left": (32, 6),
    "screen_mid": (32, 6),
    "screen_right": (32, 6),
    "leg_short": (6, 7),
}

## The near edge every desk hangs: the apron's three modules and a bracket per desk.
POD_SHARED: dict[str, tuple[int, int]] = {
    "apron_left": (32, 3),
    "apron_mid": (32, 3),
    "apron_right": (32, 3),
    "bracket": (12, 10),
}

## The one source module set a pack may declare, by name. POD_ONLY is what the
## office draws: ArtContract.TABLE_MODULES and the furniture views.
POD_ONLY: dict[str, tuple[int, int]] = {**POD_MODULES, **POD_SHARED, **FURNITURE}
SOURCE_SETS: dict[str, dict[str, tuple[int, int]]] = {"pod": POD_ONLY}


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
    ever hold the pack's own colours.
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


def apron(palette: dict[str, str], cap: str | None) -> Image.Image:
    """The rest of the desk's front face under the lip, closed by an outline."""
    result = image(POD_SHARED["apron_mid"])
    rect(result, (0, 0, 32, 1), rgba(palette, "wood_shadow"))
    rect(result, (0, 1, 32, 1), rgba(palette, "wood_dark"))
    rect(result, (0, 2, 32, 1), rgba(palette, "deep"))
    if cap == "left":
        rect(result, (0, 0, 1, 3), rgba(palette, "deep"))
    elif cap == "right":
        rect(result, (31, 0, 1, 3), rgba(palette, "deep"))
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
    return pixel_map(image(POD_SHARED["bracket"]), BRACKET, {"K": "deep", "d": "wood_dark", "s": "wood_shadow"}, palette)


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


def dense(size: tuple[int, int]) -> Image.Image:
    """A transparent canvas of `size` units at DENSITY: a pod drawing works in texels."""
    return Image.new("RGBA", (size[0] * DENSITY, size[1] * DENSITY), (0, 0, 0, 0))


def band(target: Image.Image, bounds: tuple[int, int, int, int], fill: tuple[int, int, int, int]) -> None:
    """rect() in units on a DENSITY canvas: the painted table's unit-thick outlines and bands."""
    rect(target, tuple(value * DENSITY for value in bounds), fill)


## The pod desk's plank seams (unit rows) and each grain variant's light flecks
## as (texel row, first texel column, length in texels), one texel tall like the
## painted surfaces'. Flecks keep to texel columns 6..57 (units 3..28), so the
## three edge columns of every module stay uniform.
DESK_SEAMS = (8, 29, 35)
DESK_GRAIN = {
    "a": ((9, 10, 16), (25, 32, 16), (51, 24, 14), (63, 8, 14), (75, 30, 16)),
    "b": ((7, 28, 16), (27, 8, 14), (53, 36, 14), (65, 12, 16), (77, 26, 14)),
}


def desk(palette: dict[str, str], variant: str, cap: str | None) -> Image.Image:
    """One pod desk module: oak boards seen from above and lit from the top-left,
    the painted surface's hand on a 48-unit depth.

    The far edge is outlined and catches the light, seams are unit-thick dark
    rows, the low screen (rows 16..21) shades the row below it, and the near
    edge is a highlight over the lip's two shaded rows.
    """
    result = dense(POD_MODULES["desk_mid_a"])
    deep, light, wood, shadow = (rgba(palette, key) for key in ("deep", "wood_light", "wood", "wood_shadow"))
    band(result, (0, 0, 32, 40), wood)
    band(result, (0, 0, 32, 1), deep)
    band(result, (0, 1, 32, 1), light)
    for y in DESK_SEAMS:
        band(result, (0, y, 32, 1), shadow)
    band(result, (0, 22, 32, 1), shadow)
    grain = rgba(palette, "floor")
    for y, x, length in DESK_GRAIN[variant]:
        rect(result, (x, y, length, 1), grain)
    band(result, (0, 40, 32, 1), light)
    band(result, (0, 41, 32, 2), shadow)
    if cap == "left":
        band(result, (0, 0, 1, 43), deep)
        band(result, (1, 1, 1, 40), light)
    elif cap == "right":
        band(result, (31, 0, 1, 43), deep)
        band(result, (30, 2, 1, 38), shadow)
    return result


def screen(palette: dict[str, str], cap: str | None) -> Image.Image:
    """The pod's low privacy screen, six units tall: a wooden rail over a sage
    panel, with its panel line (a dark and a lit texel) every eight units."""
    result = dense(POD_MODULES["screen_mid"])
    deep, light, wood, dark = (rgba(palette, key) for key in ("deep", "wood_light", "wood", "wood_dark"))
    sage, sage_light, sage_dark = (rgba(palette, key) for key in ("sage", "sage_light", "sage_dark"))
    band(result, (0, 0, 32, 1), deep)
    rect(result, (0, 2, 64, 1), light)
    rect(result, (0, 3, 64, 1), wood)
    rect(result, (0, 4, 64, 1), sage_dark)
    rect(result, (0, 5, 64, 1), sage_light)
    rect(result, (0, 6, 64, 3), sage)
    for x in range(14, 64, 16):
        rect(result, (x, 5, 1, 4), sage_dark)
        rect(result, (x + 1, 6, 1, 3), sage_light)
    rect(result, (0, 9, 64, 1), sage_dark)
    band(result, (0, 5, 32, 1), deep)
    if cap == "left":
        band(result, (0, 0, 1, 6), deep)
        rect(result, (2, 2, 2, 8), light)
        rect(result, (4, 2, 2, 8), wood)
    elif cap == "right":
        band(result, (31, 0, 1, 6), deep)
        rect(result, (60, 2, 2, 8), dark)
        rect(result, (58, 2, 2, 8), wood)
    return result


## leg_short, texel by texel: (first texel row, last texel row + 1, first
## texel column, texel columns of deep, wood_light, wood, wood_shadow, deep).
## The shoulder is 10 texels wide and steps in once to 8; the glide below is 6.
## One unit of each under the three-unit mount, then a two-unit glide: the foot
## ends 7 units under the mount's top, behind the pushed-in chair's back.
LEG_SHORT_SHAFT = ((6, 8, 1, (2, 2, 2, 2, 2)), (8, 10, 2, (2, 2, 0, 2, 2)))


def leg_short(palette: dict[str, str]) -> Image.Image:
    """The pod's small end leg under a dark mount, on a small glide (see the contract above)."""
    result = dense(POD_MODULES["leg_short"])
    deep, dark = rgba(palette, "deep"), rgba(palette, "wood_dark")
    rect(result, (0, 0, 12, 6), deep)
    rect(result, (2, 2, 8, 2), dark)
    keys = ("deep", "wood_light", "wood", "wood_shadow", "deep")
    for top, bottom, left, widths in LEG_SHORT_SHAFT:
        x = left
        for key, width in zip(keys, widths):
            rect(result, (x, top, width, bottom - top), rgba(palette, key))
            x += width
    rect(result, (3, 10, 6, 4), deep)
    rect(result, (4, 11, 4, 2), rgba(palette, "slate"))
    return result


def generate_templates(source: Path, output: Path) -> None:
    """Draw fresh artist canvases, never overwrite an existing source tree."""
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError(f"Output must be an empty directory: {output}")
    pack = json.loads((source / "pack.json").read_text())
    palette = pack["palette"]

    makers: dict[str, Image.Image] = {
        "apron_left": apron(palette, "left"),
        "apron_mid": apron(palette, None),
        "apron_right": apron(palette, "right"),
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
    # The pod's own modules, drawn texel by texel at DENSITY already.
    for end, variant in (("left", "a"), ("mid_a", "a"), ("mid_b", "b"), ("right", "b")):
        sprites[f"desk_{end}"] = desk(palette, variant, end if end in ("left", "right") else None)
    for end in ("left", "mid", "right"):
        sprites[f"screen_{end}"] = screen(palette, None if end == "mid" else end)
    sprites["leg_short"] = leg_short(palette)
    require(set(sprites) == set(POD_ONLY), f"the templates draw {sorted(set(sprites) ^ set(POD_ONLY))} out of the pod set")
    for name, sprite in sprites.items():
        expected = tuple(value * DENSITY for value in POD_ONLY[name])
        require(sprite.size == expected, f"template {name} is {sprite.size}, not {expected}")
    manifest = table_manifest(pack, POD_ONLY)
    output.mkdir(parents=True, exist_ok=True)
    for name, sprite in sprites.items():
        sprite.save(output / f"{name}.png")
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"TABLE_TEMPLATES_OK: {output} ({len(sprites)} editable modules at {DENSITY}x)")


def table_manifest(pack: dict, sizes: dict[str, tuple[int, int]]) -> dict:
    """The fixed native furniture contract for the accepted module set
    (SOURCE_SETS), shared by templates and validation."""
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


def source_set(manifest: dict, path: Path) -> dict[str, tuple[int, int]]:
    """The accepted module set (SOURCE_SETS) when the manifest declares its names, exactly."""
    modules = manifest.get("modules") if isinstance(manifest, dict) else None
    require(isinstance(modules, dict), f"{path}: manifest declares no modules")
    declared = set(modules)
    for sizes in SOURCE_SETS.values():
        if declared == set(sizes):
            return sizes
    closest = min(SOURCE_SETS, key=lambda name: len(declared ^ set(SOURCE_SETS[name])))
    missing = sorted(set(SOURCE_SETS[closest]) - declared)
    extra = sorted(declared - set(SOURCE_SETS[closest]))
    raise ValueError(f"{path}: the modules are not the accepted set ({closest}): "
                     f"missing {missing}, unknown {extra}")


def validate_source(source: Path) -> dict:
    """Validate the entire companion before any build output is changed."""
    path = source / "table/manifest.json"
    try:
        pack = json.loads((source / "pack.json").read_text())
        manifest = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ValueError(f"{path}: {error}") from error
    sizes = source_set(manifest, path)
    require(manifest == table_manifest(pack, sizes), f"{path}: manifest does not match the native table contract")
    for name, size in sizes.items():
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
