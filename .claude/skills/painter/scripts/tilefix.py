#!/usr/bin/env python3
"""Hold a repainted tile or module to the pixels its neighbours join on.

    tilefix.py NEW.png --out DIR [--name N] [fixes]
    tilefix.py NEW.png --check-band OLD.png --band 6
    tilefix.py NEW.png --check-ports OLD.png --boxes "x0,y0,x1,y1;..."
    tilefix.py SHEET.png --slice 3x3 --size 64x64 --names a,b,... --out DIR

A painted tile only joins its neighbours when the pixels on the join are exactly the
ones the build compares (tools/build_assets.py `check_tile_connections`): the wood
floor's outer band, the wall's cap/face line and seam columns, the T and end ports.
While only some tiles of a family are repainted, those join pixels must stay the old
ones scaled up exactly; this copies them in, or checks that they are there.

OLD is the tile the new one replaces, at any whole fraction of its size (a 32x32
density-1 source under a 64x64 repaint is scaled x2 with NEAREST first; an OLD of the
same size is used as is). Both images must be RGBA. Comparisons are exact RGBA.

Fixes, applied in this order whatever the order on the command line:
  --uniform-center N   the nine-patch middle (N pixels in from every side) becomes its
                       most common colour: the part a panel stretches must be one colour.
  --columns-uniform N  on every row, columns 0..N-1 take the colour of column N and the
                       last N columns the colour of column W-1-N (a long-table module's
                       outer band). Modules must still agree with each other at the join:
                       paint the strip whole and --slice it.
  --tileable           the last column becomes the first and the last row the first, so
                       the tile repeats against itself (walkway, the rug's middles).
  --edges-from OLD --band N   the four outer bands, N pixels wide in NEW's pixels,
                       become OLD's (scaled).
  --ports-from OLD --boxes "x0,y0,x1,y1;..."   each box (in OLD's own pixels, so units
                       for a density-1 source; x1,y1 exclusive) becomes OLD's, scaled.

Checks (no output file; exit 1 and one FAIL line per side or box that differs):
  --check-band OLD --band N    --check-ports OLD --boxes ...

--slice CxR --size WxH --names n1,...  cuts a C*W x R*H sheet into C*R pieces, row by
row, into DIR/<name>.png (e.g. the rug's 192x192 into rug.top_left ... rug.bottom_right,
or a long-table strip into surface_left, surface_mid_a, ...). It takes no fixes: run
them on the pieces.

Never overwrites a file: DIR/<name>.png must not exist. Pillow only, deterministic.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

SIDES = ("top", "bottom", "left", "right")


def fail(message: str) -> None:
    print(f"tilefix: {message}", file=sys.stderr)
    raise SystemExit(2)


def pair(text: str, sep: str) -> tuple[int, int]:
    try:
        a, b = (int(v) for v in text.split(sep))
    except ValueError:
        fail(f"expected two integers separated by '{sep}', got {text!r}")
    return a, b


def load(path: str | Path) -> Image.Image:
    with Image.open(path) as image:
        if image.mode != "RGBA":
            fail(f"{path} is {image.mode}, not RGBA")
        return image.copy()


def factor(old: Image.Image, new: Image.Image) -> int:
    """The whole number OLD scales by to NEW's size; refuses anything else."""
    k, rest_w = divmod(new.width, old.width)
    k_h, rest_h = divmod(new.height, old.height)
    if rest_w or rest_h or k != k_h or k < 1:
        fail(f"OLD {old.width}x{old.height} is not a whole fraction of NEW {new.width}x{new.height}")
    return k


def scaled(old: Image.Image, new: Image.Image) -> Image.Image:
    """OLD at NEW's size, NEAREST: every old pixel a k x k block."""
    k = factor(old, new)
    return old if k == 1 else old.resize((old.width * k, old.height * k), Image.Resampling.NEAREST)


def band_boxes(size: tuple[int, int], band: int) -> dict[str, tuple[int, int, int, int]]:
    w, h = size
    if band < 1 or 2 * band > min(w, h):
        fail(f"--band {band} does not fit a {w}x{h} tile")
    return {
        "top": (0, 0, w, band),
        "bottom": (0, h - band, w, h),
        "left": (0, 0, band, h),
        "right": (w - band, 0, w, h),
    }


def port_boxes(text: str, old: Image.Image, k: int) -> list[tuple[int, int, int, int]]:
    """`x0,y0,x1,y1;...` in OLD's pixels, scaled to NEW's; each box inside OLD."""
    boxes = []
    for part in filter(None, (p.strip() for p in text.split(";"))):
        try:
            x0, y0, x1, y1 = (int(v) for v in part.split(","))
        except ValueError:
            fail(f"a box is x0,y0,x1,y1, got {part!r}")
        if not (0 <= x0 < x1 <= old.width and 0 <= y0 < y1 <= old.height):
            fail(f"box {part!r} is not inside OLD's {old.width}x{old.height}")
        boxes.append((x0 * k, y0 * k, x1 * k, y1 * k))
    if not boxes:
        fail("--boxes names no box")
    return boxes


def pixels(image: Image.Image) -> list[bytes]:
    """An RGBA image's pixels, row by row, four bytes each."""
    data = image.tobytes()
    return [data[i : i + 4] for i in range(0, len(data), 4)]


def differing(a: Image.Image, b: Image.Image, box: tuple[int, int, int, int]) -> int:
    """How many pixels of `box` differ between a and b (exact RGBA)."""
    return sum(1 for p, q in zip(pixels(a.crop(box)), pixels(b.crop(box))) if p != q)


def copy_boxes(new: Image.Image, source: Image.Image, boxes) -> int:
    changed = 0
    for box in boxes:
        changed += differing(new, source, box)
        new.paste(source.crop(box), box[:2])
    return changed


def edges_from(new: Image.Image, old: Image.Image, band: int) -> int:
    return copy_boxes(new, scaled(old, new), band_boxes(new.size, band).values())


def ports_from(new: Image.Image, old: Image.Image, boxes_text: str) -> int:
    return copy_boxes(new, scaled(old, new), port_boxes(boxes_text, old, factor(old, new)))


def band_mismatches(new: Image.Image, old: Image.Image, band: int) -> dict[str, int]:
    source = scaled(old, new)
    return {side: differing(new, source, box) for side, box in band_boxes(new.size, band).items()}


def port_mismatches(new: Image.Image, old: Image.Image, boxes_text: str) -> dict[str, int]:
    source = scaled(old, new)
    boxes = port_boxes(boxes_text, old, factor(old, new))
    return {",".join(map(str, box)): differing(new, source, box) for box in boxes}


def tileable(new: Image.Image) -> int:
    w, h = new.size
    before = new.copy()
    new.paste(new.crop((0, 0, 1, h)), (w - 1, 0))
    new.paste(new.crop((0, 0, w, 1)), (0, h - 1))
    return differing(before, new, (0, 0, w, h))


def uniform_center(new: Image.Image, margin: int) -> int:
    w, h = new.size
    if margin < 0 or 2 * margin >= min(w, h):
        fail(f"--uniform-center {margin} leaves no middle in a {w}x{h} image")
    box = (margin, margin, w - margin, h - margin)
    colour = tuple(Counter(pixels(new.crop(box))).most_common(1)[0][0])
    before = new.copy()
    new.paste(Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), colour), box[:2])
    return differing(before, new, box)


def columns_uniform(new: Image.Image, band: int) -> int:
    w, h = new.size
    if band < 1 or 2 * band + 2 > w:
        fail(f"--columns-uniform {band} does not fit a {w}-wide image")
    before = new.copy()
    px = new.load()
    for y in range(h):
        left, right = px[band, y], px[w - 1 - band, y]
        for x in range(band):
            px[x, y] = left
            px[w - 1 - x, y] = right
    return differing(before, new, (0, 0, w, h))


def slice_sheet(sheet: Image.Image, grid: tuple[int, int], size: tuple[int, int], names: list[str]) -> dict[str, Image.Image]:
    columns, rows = grid
    w, h = size
    if sheet.size != (columns * w, rows * h):
        fail(f"a {columns}x{rows} sheet of {w}x{h} pieces is {columns * w}x{rows * h}, not {sheet.width}x{sheet.height}")
    if len(names) != columns * rows or len(set(names)) != len(names):
        fail(f"--names needs {columns * rows} distinct names, got {len(names)}")
    pieces = {}
    for index, name in enumerate(names):
        x, y = index % columns * w, index // columns * h
        pieces[name] = sheet.crop((x, y, x + w, y + h))
    return pieces


def fresh(path: Path) -> Path:
    if path.exists():
        fail(f"{path} exists; pick another --name or --out")
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("new", help="the repainted tile (or, with --slice, the sheet)")
    parser.add_argument("--out", help="output directory (created; files are never overwritten)")
    parser.add_argument("--name", help="output base name (default: NEW's stem)")
    parser.add_argument("--edges-from", help="OLD tile whose outer bands to copy")
    parser.add_argument("--ports-from", help="OLD tile whose --boxes to copy")
    parser.add_argument("--band", type=int, help="band width in NEW's pixels (edges)")
    parser.add_argument("--boxes", help="x0,y0,x1,y1;... in OLD's pixels, x1/y1 exclusive (ports)")
    parser.add_argument("--tileable", action="store_true", help="last column/row := first column/row")
    parser.add_argument("--uniform-center", type=int, metavar="N", help="middle N px in becomes one colour")
    parser.add_argument("--columns-uniform", type=int, metavar="N", help="outer N columns take column N's colour per row")
    parser.add_argument("--slice", help="CxR: cut NEW, a sheet, into C*R pieces")
    parser.add_argument("--size", help="WxH of one --slice piece")
    parser.add_argument("--names", help="comma separated names of the --slice pieces, row by row")
    parser.add_argument("--check-band", metavar="OLD", help="only check NEW's outer --band against OLD")
    parser.add_argument("--check-ports", metavar="OLD", help="only check NEW's --boxes against OLD")
    args = parser.parse_args()

    new = load(args.new)
    fixes = [args.edges_from, args.ports_from, args.tileable, args.uniform_center is not None, args.columns_uniform is not None]

    if args.check_band or args.check_ports:
        if any(fixes) or args.slice or args.out:
            fail("a check writes nothing: no fixes, --slice or --out with --check-band / --check-ports")
        found: dict[str, int] = {}
        if args.check_band:
            if args.band is None:
                fail("--check-band needs --band")
            found.update(band_mismatches(new, load(args.check_band), args.band))
        if args.check_ports:
            if not args.boxes:
                fail("--check-ports needs --boxes")
            found.update(port_mismatches(new, load(args.check_ports), args.boxes))
        bad = {where: count for where, count in found.items() if count}
        for where, count in bad.items():
            print(f"FAIL {args.new}: {where}: {count} px differ from OLD")
        print("OK" if not bad else f"{len(bad)} problem(s)")
        raise SystemExit(1 if bad else 0)

    if not args.out:
        fail("fixing or slicing needs --out")
    out = Path(args.out)

    if args.slice:
        if any(fixes):
            fail("--slice takes no fixes; run them on the pieces")
        if not (args.size and args.names):
            fail("--slice needs --size and --names")
        pieces = slice_sheet(new, pair(args.slice, "x"), pair(args.size, "x"), args.names.split(","))
        targets = {name: fresh(out / f"{name}.png") for name in pieces}
        out.mkdir(parents=True, exist_ok=True)
        for name, piece in pieces.items():
            piece.save(targets[name])
        print(json.dumps({"pieces": [str(t) for t in targets.values()]}))
        return

    if not any(fixes):
        fail("nothing to do: name a fix, --slice or a check")
    if args.edges_from and args.band is None:
        fail("--edges-from needs --band")
    if args.ports_from and not args.boxes:
        fail("--ports-from needs --boxes")
    target = fresh(out / f"{args.name or Path(args.new).stem}.png")
    changed: dict[str, int] = {}
    if args.uniform_center is not None:
        changed["uniform_center"] = uniform_center(new, args.uniform_center)
    if args.columns_uniform is not None:
        changed["columns_uniform"] = columns_uniform(new, args.columns_uniform)
    if args.tileable:
        changed["tileable"] = tileable(new)
    if args.edges_from:
        changed["edges_from"] = edges_from(new, load(args.edges_from), args.band)
    if args.ports_from:
        changed["ports_from"] = ports_from(new, load(args.ports_from), args.boxes)
    out.mkdir(parents=True, exist_ok=True)
    new.save(target)
    print(json.dumps({"tile": str(target), "changed_px": changed}))


if __name__ == "__main__":
    main()
