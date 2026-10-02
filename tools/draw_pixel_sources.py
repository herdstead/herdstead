"""Draw first-draft density-1 source PNGs for the environment.

One pixel density on screen: these are drawn at one texture pixel per unit in
the pixel people's idiom (1-unit dark outlines where a thing needs separating,
three-tone ramps lit from the top-left, hard alpha, the pack's palette and
nothing else):

- the desk library and the desk cats: eight 24x24 props on the pivot [12, 22];
- the entry band's fixtures: the reception counter and the pantry
  (a kitchenette counter with a coffee machine);
- the shared table family, through `build_table_assets.py`'s template path
  (see its docstring for what those drawings keep);
- pieces drawn texel by texel at the pack's density 2 instead: the small
  paper stack `done_stack_small` (a state signal, the done seat's paper on a
  pod desk), the seat selection mark `selection_seat` (ui) and the zone
  partition kit (`partition_*`, props).

It writes a complete tree into an empty directory: `props/`, `ui/` and `table/`, laid
out exactly as `art/daylight/` is. Nothing here ever writes into `art/`, and
`make art` never runs it (like `make table-templates`): review the output,
copy what you want into `art/daylight/` and run `make art`. An artist can
repaint any of these PNGs in place afterwards; the next `make art` builds
whatever is there. The committed desk library and the reception and pantry are
painted now (the AI painter at density 2, docs/ASSET_SPEC.md); what this
script draws was their first draft, and the tests hold the committed fixtures
to the footprint below, not to these bytes.

    make pixel-sources OUT=/abs/empty-dir
    cp OUT/props/*.png art/daylight/props/ && cp OUT/table/* art/daylight/table/
    make art

What a desk piece keeps (the table places it with its foot on a working plane,
see OfficeTable.DECOR_*): everything opaque lies in rows 3..21 and columns
0..23, so a piece on the near plane stays on the wood, clear of the divider,
the lip and every laptop, and the two rows under the foot stay clear.

What `done_stack_small` keeps: a 24x24-unit canvas (48x48 texels) on the
pivot [12, 22], opaque exactly 6 units wide by 9 tall at x -3..3 and y -9..0
about its pivot (units 9..14 by rows 13..21, inside the desk rows), with hard
alpha: the painted `done_stack`'s paper-in-a-tray look, smaller, so it fits
the 6 units between a pod laptop and its column's edge (PAPERS_ASIDE 13).

What `selection_seat` keeps: a 32x48-unit canvas (64x96 texels) on the pivot
[16, 46], four corner marks in `ui.selection`'s colour (`blocked`) and line
weight (2 units), reaching the canvas edges, each arm SEAT_ARM units long;
nothing else is opaque, so the middle (x 2..30, y 2..46) stays clear for the
seated person it encloses (x -8..12 about the foot with a raised hand, y
-36..0).

What the partition kit keeps (PARTITION_SIZES has the canvases and feet):
cream plaster under a thin honey-wood cap with a 1-texel ink outline, lit from
the top-left, in the pack's palette. A bottom-run piece is at most 10 units
tall from its foot and every column of its run is the same, so any run piece
meets any other without a seam; a side-run piece is at most 6 units wide, no
wider than its band, and every row is the same, so it tiles top-bottom and
meets a corner's side strip without a seam. Each piece stands on its foot
(its last opaque row is the one above the pivot's y) and is centred on it.

What a fixture keeps (OfficeFixturePlanner stands a counter with its foot on
the floor under the top wall): each drawing fills its canvas as
`FIXTURE_SIZES` gives it, which is what art/daylight/pack.json declares, with
its bottom outline on the row above its foot (the pivot's y) and nothing below;
a counter's opaque width is its whole canvas, which is its footprint
(OfficeDecor.FOOTPRINT).

Deterministic: the same palette always gives the same bytes.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image

from build_assets import ROOT, require
from build_table_assets import generate_templates, image, pixel_map, rgba

## Every desk piece: 24x24 canvas, foot at [12, 22], as art/daylight/pack.json declares.
DESK_SIZE = (24, 24)
## The rows a piece may paint (see the module docstring).
DESK_ROWS = range(3, 22)

## One legend for the whole library, so a letter means the same colour in every
## drawing. Every value is a palette key of the pack being drawn for.
LEGEND = {
    "K": "deep",
    "I": "ink",
    "S": "slate",
    "M": "muted",
    "J": "jacket_light",
    "P": "paper",
    "C": "cream",
    "L": "plaster",
    "c": "cream_shadow",
    "W": "wood_light",
    "w": "wood",
    "s": "wood_shadow",
    "d": "wood_dark",
    "G": "sage_light",
    "g": "sage",
    "h": "sage_dark",
    "R": "terra_light",
    "r": "terra",
    "B": "brick",
    "T": "teal_light",
    "t": "teal",
    "u": "teal_dark",
    "E": "leaf_light",
    "e": "leaf",
    "f": "leaf_dark",
    "A": "blocked",
    "a": "task_light",
}

DESK_PIECES: dict[str, tuple[str, ...]] = {
    # A sage mug of coffee, handle to the right.
    "desk_mug": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        ".........KKKKKK.........",
        "........KGGGGGGK........",
        "........KGddddgK........",
        "........KgGGGGgKKK......",
        "........KGgggghK.K......",
        "........KGgggghK.K......",
        "........KGgggghKKK......",
        "........KhhhhhhK........",
        ".........KKKKKK.........",
        "........................",
        "........................",
    ),
    # A closed notebook, spine to the left, with a pencil lying across it.
    "desk_notebook": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "......KKKKKKKKKKKK......",
        "......KBRRRRRRRRRK......",
        "......KBRrrrrrrKKrK.....",
        "......KBRrrrrrKaAKK.....",
        "......KBRrrrrKaAKrK.....",
        "......KBRrrrKaAKrrK.....",
        "......KBRrrKaAKrrrK.....",
        "......KBRrKaAKrrrrK.....",
        "......KBRKWAKrrrrrK.....",
        "......KBRKWKrrrrrBK.....",
        "......KBRrKrrrrrrBK.....",
        "......KBrrrrrrrrrBK.....",
        "......KBBBBBBBBBBBK.....",
        "......KPPPPPPPPPPcK.....",
        "......KKKKKKKKKKKKK.....",
        "........................",
        "........................",
    ),
    # A short stack of printouts under a teal binder clip.
    "desk_papers": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..........KKKK..........",
        "..........K..K..........",
        ".......KKKKttKKKK.......",
        ".......KPPKuuKPPK.......",
        ".......KPPPPPPPPKK......",
        ".......KPMMMMMPPKcK.....",
        ".......KPPPPPPPPKcK.....",
        ".......KPMMMMPPPKcK.....",
        ".......KPPPPPPPPKcK.....",
        ".......KPMMMMMMPKcK.....",
        ".......KPPPPPPPPKcK.....",
        ".......KCCCCCCCCKcK.....",
        "........KKKKKKKKKcK.....",
        ".........KKKKKKKKK......",
        "........................",
        "........................",
    ),
    # Three broad leaves out of a terracotta pot.
    "desk_plant": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..........KKK...........",
        "....KK...KEEeK..........",
        "...KEeK..KEEeK....KK....",
        "...KEeeK.KEeefK..KEeK...",
        "....KEefKKEeefK.KEeefK..",
        ".....KEffKEeffKKEeffK...",
        "......KKfKKffKKEffKK....",
        "........KKKKKKKKKKK.....",
        "........KRRRRRRRRRK.....",
        "........KBBBBBBBBBK.....",
        ".........KrRrrrrrK......",
        ".........KrRrrrrBK......",
        ".........KrRrrrrBK......",
        "..........KrrrrBK.......",
        "...........KKKKK........",
        "........................",
        "........................",
    ),
    # Headphones lying flat: a headband between two cushioned cups.
    "desk_headphones": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..........KKKKK.........",
        "........KKSSSSSKK.......",
        ".......KSKK...KKSK......",
        "......KSK.......KSK.....",
        "......KSK.......KSK.....",
        ".....KKKKK.....KKKKK....",
        "....KTtttuK...KTtttuK...",
        "....KtuuuuK...KtuuuuK...",
        "....KtuSSuK...KtuSSuK...",
        "....KtuuuuK...KtuuuuK...",
        "....KuuuuuK...KuuuuuK...",
        ".....KKKKK.....KKKKK....",
        "........................",
        "........................",
        "........................",
    ),
    # A white cat as a loaf: paws tucked in, looking at you.
    "cat_loaf": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        ".......KK......KK.......",
        "......KRPK....KPRK......",
        "......KPPPKKKKPPPK......",
        ".....KPPPPPPPPPPPPK.....",
        ".....KPPKPPPPPPKPPK.....",
        ".....KPPPPPRRPPPPPK.....",
        "....KKCPPPPPPPPPPCKK....",
        "...KPPCCCPPPPPPCCCPcK...",
        "...KPPPPPPPPPPPPPPPcK...",
        "...KPPPPPPPPPPPPPPCcK...",
        "...KCPPPPPPPPPPPPCccK...",
        "....KcCCCCCCCCCCCcccK...",
        ".....KKKKKKKKKKKKKKK....",
        "........................",
        "........................",
    ),
    # A white cat sitting up, tail curled round its feet.
    "cat_sit": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........KK......KK......",
        ".......KRPK....KPRK.....",
        ".......KPPPKKKKPPPK.....",
        "......KPPPPPPPPPPPPK....",
        "......KPPKPPPPPPKPPK....",
        "......KPPPPPRRPPPPPK....",
        ".......KCPPPPPPPPCK.....",
        "........KKPPPPPPKK......",
        ".......KPPPPPPPPPCK.....",
        "......KPPPPPPPPPPCcK....",
        "......KPPPPPPPPPPCcK....",
        "......KPPPPPPPPPPCcK....",
        "......KPPPPPPPPPCCcK....",
        "......KCPPPPPPPPCccK....",
        "......KCPKPPPKPPCccKKK..",
        "......KcCKCCCKCcccKPPcK.",
        ".......KcccccccccccccK..",
        "........KKKKKKKKKKKKK...",
        "........................",
        "........................",
    ),
    # A white cat asleep, curled nose to tail.
    "cat_sleep": (
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "......KKKKKKK...........",
        "....KKPPPPPPPKK..KK..KK.",
        "...KPPPPPPPPPPPKKRPKKPRK",
        "..KPPPPPPPPPPPPPKPPPPPPK",
        "..KPPPPPPPPPPPPKPPPPPPPK",
        "..KPPPPPPPPPPPPKPKKPPKKK",
        "..KPPPPPPPPPPPPKPPPRRPPK",
        "..KCPPPPPPPPPPPCKCPPPPK.",
        "..KcKKKKKPPPPPCCcKKKKK..",
        "..KcPPPPPKKCCCCccccccK..",
        "...KcCCCCCCKccccccccK...",
        "....KKKKKKKKKKKKKKKK....",
        "........................",
        "........................",
    ),
}


## Every fixture piece: (width, height) and its foot (the pivot), as
## art/daylight/pack.json declares them.
FIXTURE_SIZES: dict[str, tuple[int, int]] = {
    "reception": (48, 32),
    "pantry": (64, 48),
}
FIXTURE_PIVOTS: dict[str, tuple[int, int]] = {
    "reception": (24, 30),
    "pantry": (32, 46),
}


## The pack's density: the pieces below are drawn texel by texel at it.
DENSE = 2
## done_stack_small, texel by texel: 12x18 texels (6x9 units), its top-left
## texel at DENSE_AT on the 48x48 canvas, so the bottom outline sits on the
## texel row right above the foot (22 units = texel 44). The same letters as the
## painted done_stack: ink outline, a stack of cream sheets lit from the top
## left, their paper edges, in a terracotta tray.
PAPERS_SMALL = (
    "..IIIIIIII..",
    ".IPkkkkkkjI.",
    ".IkLLLLLLjI.",
    ".IkLLLLLLjI.",
    ".ILLLLLLLjI.",
    ".ILLLLLLjjI.",
    ".IjjjjjjjjI.",
    ".IPJJJJJJMI.",
    ".IPPPPPPPPI.",
    ".IMMMMMMMMI.",
    "IKMMMMMMMMKI",
    "IkKPPPPPPKrI",
    "IrKPPPPPPKrI",
    "IkrKKKKKKrsI",
    "IrrrrrrrrrrI",
    "IssssssssssI",
    "IKssssssssKI",
    ".IIIIIIIIII.",
)
PAPERS_SMALL_LEGEND = {
    "I": "ink", "K": "deep", "P": "paper", "k": "skin", "L": "floor_light", "j": "skin_shadow",
    "J": "jacket_light", "M": "muted", "r": "terra", "s": "wood_shadow",
}
DENSE_AT = {"done_stack_small": (18, 26)}
DENSE_SIZES = {"done_stack_small": (24, 24), "selection_seat": (32, 48)}
DENSE_PIVOTS = {"done_stack_small": (12, 22), "selection_seat": (16, 46)}
## selection_seat: each corner's arm length and the line weight, in units. Four,
## not ui.selection's proportion (6): a seated worker's raised fist reaches
## x +10..+12 about the foot at the top of the far mark (SELECTION_AT (0, 10)),
## so the top-right arm must start at x +12 or further out.
SEAT_ARM = 4
SEAT_LINE = 2


def done_stack_small(palette: dict[str, str]) -> Image.Image:
    """The small paper stack a done seat shows on a pod desk (see the module docstring)."""
    width, height = DENSE_SIZES["done_stack_small"]
    result = Image.new("RGBA", (width * DENSE, height * DENSE), (0, 0, 0, 0))
    pixel_map(result, PAPERS_SMALL, PAPERS_SMALL_LEGEND, palette, DENSE_AT["done_stack_small"])
    left, top, right, bottom = result.getchannel("A").getbbox()
    pivot_x, pivot_y = (value * DENSE for value in DENSE_PIVOTS["done_stack_small"])
    require((left, right) == (pivot_x - 3 * DENSE, pivot_x + 3 * DENSE),
            f"done_stack_small: opaque columns {left}..{right - 1}, not x -3..3 about the pivot")
    require((top, bottom) == (pivot_y - 9 * DENSE, pivot_y),
            f"done_stack_small: opaque rows {top}..{bottom - 1}, not y -9..0 about the pivot")
    return result


def selection_seat(palette: dict[str, str]) -> Image.Image:
    """Four corner marks round one seated person, in ui.selection's colour and weight."""
    width, height = (value * DENSE for value in DENSE_SIZES["selection_seat"])
    result = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    mark = (*bytes.fromhex(palette["blocked"]), 255)
    arm, line = SEAT_ARM * DENSE, SEAT_LINE * DENSE
    for x in (0, width - arm):
        for y in (0, height - line):
            result.paste(mark, (x, y, x + arm, y + line))
    for x in (0, width - line):
        for y in (0, height - arm):
            result.paste(mark, (x, y, x + line, y + arm))
    return result


## The zone partitions (the low half-wall round an open-plan zone), drawn texel
## by texel at DENSE. One piece per 32-unit cell; the band a piece stands in is
## PARTITION_BAND (6) units deep, inside the zone's edge. Canvases hug the
## drawing, and every foot (pivot) is the band's near edge, where the piece
## sorts, centred on the piece:
## - partition_h / _end_l / _end_r 32x10, foot (16, 10): the bottom run, seen
##   from the front, PARTITION_WALL (10) units tall from the foot;
## - partition_v 6x32, foot (3, 32): a side run going away from the viewer,
##   only its wood cap and a sliver of cream side face, the width of its band;
## - partition_corner_bl / _br 32x32, foot (16, 32): the zone's bottom corner
##   cell, where the side run turns into the bottom run;
## - partition_post 6x12, foot (3, 12): the open top corners' short pillar,
##   two units taller than the wall, the width of the band.
PARTITION_BAND = 6
PARTITION_WALL = 10
PARTITION_SIZES = {
    "partition_h": (32, 10), "partition_h_end_l": (32, 10), "partition_h_end_r": (32, 10),
    "partition_v": (6, 32), "partition_corner_bl": (32, 32), "partition_corner_br": (32, 32),
    "partition_post": (6, 12),
}
PARTITION_PIVOTS = {
    "partition_h": (16, 10), "partition_h_end_l": (16, 10), "partition_h_end_r": (16, 10),
    "partition_v": (3, 32), "partition_corner_bl": (16, 32), "partition_corner_br": (16, 32),
    "partition_post": (3, 12),
}
## The bottom run's texel rows from its top (20 = PARTITION_WALL x DENSE): an ink
## outline, the honey-wood cap lit on top and dark at its lip, the cap's shadow,
## the cream plaster face, a slightly darker base line, the ink outline on the
## floor. The same in every column, so a run tiles left-right.
PARTITION_H_ROWS = ("ink", "wood_light", "wood", "wood", "wood_dark", "plaster",
                    *(("cream",) * 10), "plaster", "plaster", "cream_shadow", "ink")
## The side run's texel columns from its left (12 = PARTITION_BAND x DENSE):
## ink, the cap lit on its left edge, the dark cap edge, a sliver of cream side
## face in shade, ink. The same in every row, so a run tiles top-bottom.
PARTITION_V_COLUMNS = ("ink", "wood_light", "wood", "wood", "wood", "wood", "wood", "wood_dark",
                       "cream", "cream", "plaster", "ink")
## The post's texel rows (24): a cap a texel proud of the pillar on each side,
## then the pillar with ink sides.
PARTITION_POST_CAP = ("ink", "wood_light", "wood", "wood", "wood_dark", "ink")
PARTITION_POST_FACE = ("plaster", *(("cream",) * 13), "plaster", "plaster", "cream_shadow")


def _partition_canvas(name: str) -> Image.Image:
    width, height = PARTITION_SIZES[name]
    return Image.new("RGBA", (width * DENSE, height * DENSE), (0, 0, 0, 0))


def _run(target: Image.Image, palette: dict[str, str], top: int, end: str | None) -> None:
    """The bottom run across the whole of `target`, its first texel row at `top`;
    `end` closes its left or right end (lit on the left, shaded on the right)."""
    for y, key in enumerate(PARTITION_H_ROWS):
        target.paste(rgba(palette, key), (0, top + y, target.width, top + y + 1))
    last = top + len(PARTITION_H_ROWS)
    if end == "left":
        target.paste(rgba(palette, "ink"), (0, top, 1, last))
        target.paste(rgba(palette, "wood_light"), (1, top + 1, 2, top + 4))
    elif end == "right":
        target.paste(rgba(palette, "ink"), (target.width - 1, top, target.width, last))
        target.paste(rgba(palette, "wood_dark"), (target.width - 2, top + 1, target.width - 1, top + 5))
        target.paste(rgba(palette, "plaster"), (target.width - 2, top + 5, target.width - 1, last - 1))


def _side(target: Image.Image, palette: dict[str, str], left: int, bottom: int) -> None:
    """The side run's strip from the top of `target` down to texel row `bottom`, at texel column `left`."""
    for x, key in enumerate(PARTITION_V_COLUMNS):
        target.paste(rgba(palette, key), (left + x, 0, left + x + 1, bottom))


def partition_piece(name: str, palette: dict[str, str]) -> Image.Image:
    """One partition piece (see PARTITION_SIZES for the kit)."""
    result = _partition_canvas(name)
    wall = len(PARTITION_H_ROWS)
    if name.startswith("partition_h"):
        _run(result, palette, 0, {"partition_h_end_l": "left", "partition_h_end_r": "right"}.get(name))
    elif name == "partition_v":
        _side(result, palette, 0, result.height)
    elif name.startswith("partition_corner"):
        # The bottom run fills the cell's last PARTITION_WALL units; the side run
        # comes down its band through the run's top outline and cap rows, so
        # the run's cap butts into the side's: the side keeps its cap and its
        # sliver down to the run's face, and only its inner outline stops, on
        # the run's top outline, where the run's cap flows in.
        left = name.endswith("_bl")
        top = result.height - wall
        _run(result, palette, top, "left" if left else "right")
        column = 0 if left else result.width - len(PARTITION_V_COLUMNS)
        _side(result, palette, column, top)
        for x, key in enumerate(PARTITION_V_COLUMNS[1:-1], start=1):
            result.paste(rgba(palette, key), (column + x, top, column + x + 1, top + 5))
    elif name == "partition_post":
        for y, key in enumerate(PARTITION_POST_CAP):
            result.paste(rgba(palette, key), (0, y, result.width, y + 1))
        result.paste(rgba(palette, "ink"), (0, 0, 1, len(PARTITION_POST_CAP)))
        result.paste(rgba(palette, "ink"), (result.width - 1, 0, result.width, len(PARTITION_POST_CAP)))
        result.paste(rgba(palette, "wood_light"), (1, 1, 2, 4))
        result.paste(rgba(palette, "wood_dark"), (result.width - 2, 1, result.width - 1, 5))
        face_top = len(PARTITION_POST_CAP)
        for y, key in enumerate(PARTITION_POST_FACE):
            result.paste(rgba(palette, key), (2, face_top + y, result.width - 2, face_top + y + 1))
        body_bottom = face_top + len(PARTITION_POST_FACE)
        result.paste(rgba(palette, "plaster"), (result.width - 3, face_top, result.width - 2, body_bottom))
        result.paste(rgba(palette, "ink"), (1, face_top, 2, body_bottom + 1))
        result.paste(rgba(palette, "ink"), (result.width - 2, face_top, result.width - 1, body_bottom + 1))
        result.paste(rgba(palette, "ink"), (1, body_bottom, result.width - 1, body_bottom + 1))
    else:
        raise ValueError(f"no partition piece named {name}")
    box = result.getchannel("A").getbbox()
    pivot_x, pivot_y = (value * DENSE for value in PARTITION_PIVOTS[name])
    require(box is not None and box[3] == pivot_y, f"{name}: does not stand on its foot")
    require(box[0] + box[2] == 2 * pivot_x, f"{name}: not centred on its foot")
    return result


class Sketch:
    """A canvas of legend letters, drawn on with rectangles: what a fixture is
    built from before pixel_map() paints it, so it keeps to the same legend."""

    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.cells = [["."] * width for _ in range(height)]

    def fill(self, x: int, y: int, width: int, height: int, letter: str) -> None:
        for row in range(max(0, y), min(self.height, y + height)):
            for column in range(max(0, x), min(self.width, x + width)):
                self.cells[row][column] = letter

    def box(self, x: int, y: int, width: int, height: int, letter: str, outline: str = "K") -> None:
        """A filled rectangle inside a 1-unit outline."""
        self.fill(x, y, width, height, outline)
        self.fill(x + 1, y + 1, width - 2, height - 2, letter)

    def rows(self) -> tuple[str, ...]:
        return tuple("".join(row) for row in self.cells)


def _counter_top(sketch: Sketch, left: int, right: int, top: int) -> None:
    """A counter's top seen from above and in front, lit from the top-left: a
    back edge a unit in from each end, the wood, a light back rim, the shadowed
    front lip and its outline, seven rows in all."""
    sketch.fill(left + 1, top, right - left - 1, 1, "K")
    sketch.fill(left, top + 1, right - left + 1, 5, "K")
    sketch.fill(left + 1, top + 1, right - left - 1, 1, "W")
    sketch.fill(left + 1, top + 2, right - left - 1, 3, "w")
    sketch.fill(left + 1, top + 5, right - left - 1, 1, "s")
    sketch.fill(left, top + 6, right - left + 1, 1, "K")
    # A few light flecks of grain on the wood.
    for column in range(left + 4, right - 2, 9):
        sketch.fill(column, top + 3, 3, 1, "W")


def reception_rows() -> tuple[str, ...]:
    """The reception counter: a wooden top with a brass service bell on its
    right, over a teal front with a paper name band, on a dark plinth."""
    sketch = Sketch(*FIXTURE_SIZES["reception"])
    _counter_top(sketch, 0, 47, 2)
    # The front, outlined, lit from the left, shadowed under the lip.
    sketch.box(0, 8, 48, 17, "t")
    sketch.fill(1, 9, 46, 1, "u")
    sketch.fill(1, 10, 1, 14, "T")
    sketch.fill(46, 10, 1, 14, "u")
    # The name band across it: paper, outlined, its lower edge in shadow.
    sketch.box(7, 13, 34, 6, "P")
    sketch.fill(8, 17, 32, 1, "c")
    sketch.fill(9, 15, 30, 1, "C")
    # The plinth.
    sketch.fill(0, 24, 48, 6, "K")
    sketch.fill(1, 25, 46, 4, "d")
    sketch.fill(1, 25, 46, 1, "s")
    # The bell on the top's right: a brass dome on a dark foot, its button up.
    sketch.fill(37, 0, 2, 1, "K")
    sketch.fill(36, 1, 4, 1, "K")
    sketch.fill(37, 1, 2, 1, "a")
    sketch.fill(35, 2, 6, 1, "K")
    sketch.fill(36, 2, 3, 1, "a")
    sketch.fill(39, 2, 1, 1, "A")
    sketch.fill(34, 3, 8, 2, "K")
    sketch.fill(35, 3, 5, 1, "a")
    sketch.fill(40, 3, 1, 1, "A")
    sketch.fill(35, 4, 6, 1, "A")
    sketch.fill(33, 5, 10, 1, "K")
    sketch.fill(34, 5, 8, 1, "I")
    return sketch.rows()


def pantry_rows() -> tuple[str, ...]:
    """The pantry: a kitchenette counter with two cabinet doors, two mugs on
    the left of its top and a coffee machine on the right, a pot under its
    spout and a teal light on its front."""
    sketch = Sketch(*FIXTURE_SIZES["pantry"])
    _counter_top(sketch, 0, 63, 24)
    # The cupboard under the top: two cream doors in a wooden frame.
    sketch.box(0, 30, 64, 16, "w")
    sketch.fill(1, 31, 62, 1, "s")
    for left in (3, 34):
        sketch.box(left, 32, 27, 11, "C")
        sketch.fill(left + 1, 33, 25, 1, "P")
        sketch.fill(left + 1, 41, 25, 1, "c")
        knob = left + 22 if left == 3 else left + 3
        sketch.fill(knob, 35, 2, 4, "K")
        sketch.fill(knob, 35, 1, 3, "S")
    sketch.fill(1, 43, 62, 2, "d")
    # Two mugs on the top, handles to the right.
    for left, body, shade in ((6, "g", "h"), (15, "R", "r")):
        sketch.box(left, 21, 6, 7, body)
        sketch.fill(left + 1, 22, 4, 1, "d")
        sketch.fill(left + 4, 23, 1, 4, shade)
        sketch.fill(left + 6, 23, 1, 3, "K")
    # The coffee machine: a dark body, a slate front with its light, a recess
    # with the pot under the spout, standing on the top.
    sketch.box(38, 3, 20, 26, "I")
    sketch.fill(39, 4, 18, 1, "S")
    sketch.box(40, 6, 16, 6, "S")
    sketch.fill(41, 7, 14, 1, "M")
    sketch.fill(52, 9, 2, 1, "T")
    sketch.fill(42, 9, 6, 1, "K")
    sketch.box(40, 13, 16, 13, "K")
    sketch.fill(46, 14, 4, 2, "S")
    sketch.box(43, 18, 10, 7, "T")
    sketch.fill(44, 19, 8, 1, "P")
    sketch.fill(44, 21, 8, 3, "d")
    sketch.fill(53, 20, 2, 3, "K")
    sketch.fill(39, 27, 18, 1, "S")
    return sketch.rows()


def fixture_piece(name: str, palette: dict[str, str]) -> Image.Image:
    """One fixture, checked against what its planner and view need of it."""
    size = FIXTURE_SIZES[name]
    rows = reception_rows() if name == "reception" else pantry_rows()
    require(len(rows) == size[1] and all(len(row) == size[0] for row in rows), f"{name}: not {size[0]}x{size[1]}")
    result = pixel_map(image(size), rows, LEGEND, palette)
    box = result.getchannel("A").getbbox()
    require(box is not None, f"{name}: nothing is drawn")
    foot = FIXTURE_PIVOTS[name][1]
    require(box[3] == foot, f"{name}: its bottom outline is row {box[3] - 1}, not the row above its foot {foot}")
    if name in ("reception", "pantry"):
        require(box[0] == 0 and box[2] == size[0], f"{name}: does not stand on its whole width")
    return result


def palette_of(pack_path: Path) -> dict[str, str]:
    return json.loads(pack_path.read_text())["palette"]


def desk_piece(name: str, palette: dict[str, str]) -> Image.Image:
    """One piece of the desk library, checked against what the table needs of it."""
    rows = DESK_PIECES[name]
    require(len(rows) == DESK_SIZE[1], f"{name}: {len(rows)} rows, not {DESK_SIZE[1]}")
    result = pixel_map(image(DESK_SIZE), rows, LEGEND, palette)
    box = result.getchannel("A").getbbox()
    require(box is not None, f"{name}: nothing is drawn")
    require(box[1] >= DESK_ROWS.start and box[3] <= DESK_ROWS.stop,
            f"{name}: paints rows {box[1]}..{box[3] - 1}; the table keeps a piece to rows "
            f"{DESK_ROWS.start}..{DESK_ROWS.stop - 1}")
    return result


def draw(source: Path, output: Path) -> list[Path]:
    """Write every density-1 drawing into the empty directory `output`."""
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError(f"Output must be an empty directory: {output}")
    palette = palette_of(source / "pack.json")
    pieces = {name: desk_piece(name, palette) for name in DESK_PIECES}
    pieces.update({name: fixture_piece(name, palette) for name in FIXTURE_SIZES})
    pieces["done_stack_small"] = done_stack_small(palette)
    pieces.update({name: partition_piece(name, palette) for name in PARTITION_SIZES})
    written = []
    (output / "props").mkdir(parents=True)
    for name, piece in pieces.items():
        target = output / "props" / f"{name}.png"
        piece.save(target)
        written.append(target)
    (output / "ui").mkdir()
    target = output / "ui/selection_seat.png"
    selection_seat(palette).save(target)
    written.append(target)
    generate_templates(source, output / "table")
    written.extend(sorted((output / "table").iterdir()))
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=ROOT / "art/daylight",
                        help="the pack whose palette and manifest to draw for (default art/daylight)")
    parser.add_argument("--output", type=Path, required=True, help="an empty directory to draw into")
    args = parser.parse_args()
    try:
        written = draw(args.source, args.output)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"draw_pixel_sources: {error}\n")
    print(f"PIXEL_SOURCES_OK: {args.output} ({len(written)} files: {len(DESK_PIECES)} desk props, "
          f"{len(FIXTURE_SIZES)} fixture props, {len(DENSE_SIZES) + len(PARTITION_SIZES)} density-{DENSE} pieces, the table family)")


if __name__ == "__main__":
    main()
