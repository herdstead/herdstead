#!/usr/bin/env python3
"""Turn a model-made picture into a contract sprite: exact canvas, pivot, palette, hard alpha.

    pixelize.py SRC --out DIR --size 32x48 --pivot 16,46 --pack art/daylight/pack.json [options]
    pixelize.py --check PNG --size 32x48 --pack art/daylight/pack.json

Pipeline (Pillow only, deterministic):
  1. Alpha: pixels with alpha >= --alpha-cut are opaque. Optionally key out a flat background
     (--key auto samples the four corners) for images the model returned opaque.
  2. Crop to the opaque bounding box, or to --crop x,y,w,h (one object out of a sheet).
  3. Quantize every source pixel to the nearest palette colour (no dither).
  4. Downsample cell by cell: a target pixel is opaque when more than half its cell is, and takes
     the most common palette colour among the cell's opaque pixels. Majority, not averaging:
     averaging invents colours and soft edges the contract forbids.
  5. Fit the result inside the canvas keeping the aspect ratio (--fit sets the box, default the
     canvas minus --margin), bottom row on the row above the pivot's y, centred on the pivot's x.
     --stretch fills --fit exactly instead (both axes scaled on their own): for a picture that must
     land on known texels, e.g. a repainted pixel-person frame (tools/people_skins.py reference).
  6. Optional --outline KEY: every opaque pixel with a transparent 4-neighbour becomes that
     palette colour (the house style is a native 1 px ink outline).

Writes DIR/<name>.png (the sprite), DIR/<name>.x8.png (nearest x8 preview on a light and a dark
ground) and DIR/<name>.json (what it did and what it measured). --check validates an existing PNG
against the same rules and exits 1 on any violation, printing each one.

The palette comes from --pack (a theme's pack.json `palette`), --people (people.json `keys` +
`fixed`, optionally narrowed with --roles), or --colours hex,hex,...
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image


def fail(message: str) -> None:
    print(f"pixelize: {message}", file=sys.stderr)
    raise SystemExit(2)


def pair(text: str, sep: str) -> tuple[int, int]:
    try:
        a, b = (int(v) for v in text.split(sep))
    except ValueError:
        fail(f"expected two integers separated by '{sep}', got {text!r}")
    return a, b


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.strip().lstrip("#")
    if len(value) != 6:
        fail(f"bad colour {value!r}")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def load_palette(args) -> dict[str, tuple[int, int, int]]:
    named: dict[str, tuple[int, int, int]] = {}
    if args.pack:
        pack = json.loads(Path(args.pack).read_text())
        named.update({k: hex_rgb(v) for k, v in pack["palette"].items()})
    if args.people:
        people = json.loads(Path(args.people).read_text())
        roles = set(args.roles.split(",")) if args.roles else None
        for role, shades in people.get("keys", {}).items():
            if roles is None or role in roles:
                for index, shade in enumerate(shades):
                    named[f"key.{role}.{index}"] = hex_rgb(shade)
        for name, value in people.get("fixed", {}).items():
            named[f"fixed.{name}"] = hex_rgb(value)
    if args.colours:
        for index, value in enumerate(args.colours.split(",")):
            named[f"c{index}"] = hex_rgb(value)
    if args.only:
        keep = set(args.only.split(","))
        missing = keep - set(named)
        if missing:
            fail(f"--only names not in the palette: {sorted(missing)}")
        named = {k: v for k, v in named.items() if k in keep}
    if not named:
        fail("no palette: pass --pack, --people or --colours")
    if len(named) > 256:
        fail("more than 256 palette colours")
    return named


def palette_image(colours: list[tuple[int, int, int]]) -> Image.Image:
    flat = [c for rgb in colours for c in rgb]
    flat += list(colours[0]) * (256 - len(colours))  # pad with a real colour, never a stray one
    image = Image.new("P", (1, 1))
    image.putpalette(flat)
    return image


def opaque_mask(image: Image.Image, cut: int, key: str | None, key_tolerance: int) -> Image.Image:
    alpha = image.getchannel("A").point(lambda a: 255 if a >= cut else 0)
    if key:
        rgb = image.convert("RGB")
        if key == "auto":
            w, h = rgb.size
            corners = [rgb.getpixel(p) for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
            ref = Counter(corners).most_common(1)[0][0]
        else:
            ref = hex_rgb(key)
        keyed = Image.new("L", rgb.size, 255)
        px, kx = rgb.load(), keyed.load()
        for y in range(rgb.height):
            for x in range(rgb.width):
                r, g, b = px[x, y]
                if abs(r - ref[0]) + abs(g - ref[1]) + abs(b - ref[2]) <= key_tolerance:
                    kx[x, y] = 0
        alpha = Image.composite(alpha, keyed, keyed)
    return alpha


def downsample(indices: Image.Image, mask: Image.Image, size: tuple[int, int]) -> tuple[Image.Image, Image.Image]:
    sw, sh = indices.size
    tw, th = size
    out_i = Image.new("P", size, 0)
    out_a = Image.new("L", size, 0)
    ip, ap = indices.load(), mask.load()
    oi, oa = out_i.load(), out_a.load()
    for ty in range(th):
        y0, y1 = ty * sh // th, max(ty * sh // th + 1, (ty + 1) * sh // th)
        for tx in range(tw):
            x0, x1 = tx * sw // tw, max(tx * sw // tw + 1, (tx + 1) * sw // tw)
            votes: Counter = Counter()
            solid = total = 0
            for y in range(y0, y1):
                for x in range(x0, x1):
                    total += 1
                    if ap[x, y]:
                        solid += 1
                        votes[ip[x, y]] += 1
            if solid * 2 > total:
                oi[tx, ty] = votes.most_common(1)[0][0]
                oa[tx, ty] = 255
    return out_i, out_a


def outline(indices: Image.Image, alpha: Image.Image, ink_index: int) -> None:
    ip, ap = indices.load(), alpha.load()
    w, h = alpha.size
    edge = []
    for y in range(h):
        for x in range(w):
            if not ap[x, y]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h) or not ap[nx, ny]:
                    edge.append((x, y))
                    break
    for x, y in edge:
        ip[x, y] = ink_index


def to_rgba(indices: Image.Image, alpha: Image.Image, colours: list) -> Image.Image:
    rgba = Image.new("RGBA", indices.size, (0, 0, 0, 0))
    ip, ap, op = indices.load(), alpha.load(), rgba.load()
    for y in range(indices.height):
        for x in range(indices.width):
            if ap[x, y]:
                op[x, y] = (*colours[ip[x, y]], 255)
    return rgba


def preview(sprite: Image.Image, light: tuple, dark: tuple, scale: int = 8) -> Image.Image:
    w, h = sprite.size
    sheet = Image.new("RGBA", (w * 2 + 1, h), (255, 0, 255, 255))
    for i, ground in enumerate((light, dark)):
        tile = Image.new("RGBA", (w, h), (*ground, 255))
        tile.alpha_composite(sprite)
        sheet.paste(tile, (i * (w + 1), 0))
    return sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)


def check(path: Path, size, named: dict, rows: tuple | None) -> list[str]:
    image = Image.open(path).convert("RGBA")
    problems = []
    if size and image.size != size:
        problems.append(f"size {image.size[0]}x{image.size[1]}, contract {size[0]}x{size[1]}")
    allowed = set(named.values())
    strays: Counter = Counter()
    soft = 0
    lowest = highest = None
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a not in (0, 255):
                soft += 1
            if a and (r, g, b) not in allowed:
                strays[(r, g, b)] += 1
            if a:
                lowest = y if lowest is None else lowest
                highest = y
    if soft:
        problems.append(f"{soft} pixels with alpha other than 0/255")
    for rgb, count in strays.most_common(8):
        problems.append(f"colour #{'%02x%02x%02x' % rgb} not in the palette ({count} px)")
    if lowest is None:
        problems.append("no opaque pixels")
    elif rows and (lowest < rows[0] or highest > rows[1]):
        problems.append(f"opaque rows {lowest}-{highest}, allowed {rows[0]}-{rows[1]}")
    return problems


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("src", nargs="?", help="model output to pixelize")
    parser.add_argument("--check", help="validate this PNG instead of pixelizing")
    parser.add_argument("--out", help="output directory (created; files are not overwritten)")
    parser.add_argument("--name", help="output base name (default: source stem)")
    parser.add_argument("--size", help="canvas WxH, the contract size (e.g. 32x48)")
    parser.add_argument("--pivot", help="pivot x,y (foot point); default bottom centre")
    parser.add_argument("--fit", help="content box WxH inside the canvas (default canvas minus margin)")
    parser.add_argument("--margin", type=int, default=0, help="transparent margin on each side")
    parser.add_argument("--stretch", action="store_true", help="scale to exactly --fit, not keeping the aspect ratio")
    parser.add_argument("--rows", help="allowed opaque rows a-b (e.g. desk items 3-21)")
    parser.add_argument("--crop", help="source crop x,y,w,h before anything else")
    parser.add_argument("--alpha-cut", type=int, default=160)
    parser.add_argument("--key", help="key out a flat background: 'auto' (corners) or a hex colour")
    parser.add_argument("--key-tolerance", type=int, default=48)
    parser.add_argument("--outline", help="palette name to paint the 1 px outer outline with (e.g. ink)")
    parser.add_argument("--pack", help="pack.json whose palette to use")
    parser.add_argument("--people", help="people.json whose keys + fixed colours to use")
    parser.add_argument("--roles", help="people roles to allow, comma separated (skin,top,legs,hair,hat)")
    parser.add_argument("--colours", help="extra palette colours, hex comma separated")
    parser.add_argument("--only", help="restrict to these palette names, comma separated")
    args = parser.parse_args()

    named = load_palette(args)
    size = pair(args.size, "x") if args.size else None
    rows = pair(args.rows, "-") if args.rows else None

    if args.check:
        problems = check(Path(args.check), size, named, rows)
        for problem in problems:
            print(f"FAIL {args.check}: {problem}")
        print("OK" if not problems else f"{len(problems)} problem(s)")
        raise SystemExit(1 if problems else 0)

    if not (args.src and args.out and size):
        fail("pixelizing needs SRC, --out and --size")
    src = Path(args.src)
    image = Image.open(src).convert("RGBA")
    if args.crop:
        x, y, w, h = (int(v) for v in args.crop.split(","))
        image = image.crop((x, y, x + w, y + h))

    mask = opaque_mask(image, args.alpha_cut, args.key, args.key_tolerance)
    box = mask.getbbox()
    if box is None:
        fail("nothing opaque after the alpha cut / key")
    image, mask = image.crop(box), mask.crop(box)

    names = list(named)
    colours = [named[n] for n in names]
    flat = Image.new("RGB", image.size, colours[0])
    flat.paste(image.convert("RGB"), mask=mask)
    indices = flat.quantize(palette=palette_image(colours), dither=Image.Dither.NONE)

    cw, ch = size
    px, py = pair(args.pivot, ",") if args.pivot else (cw // 2, ch)
    fw, fh = pair(args.fit, "x") if args.fit else (cw - 2 * args.margin, ch - 2 * args.margin)
    if rows:
        fh = min(fh, rows[1] - rows[0] + 1)
    else:
        # The bottom row sits on the row above the pivot, so only that much height is free.
        fh = min(fh, min(py, ch) - args.margin)
    if args.stretch:
        if not args.fit:
            fail("--stretch needs --fit, the exact box to fill")
        tw, th = fw, fh
    else:
        scale = min(fw / image.width, fh / image.height)
        tw, th = max(1, round(image.width * scale)), max(1, round(image.height * scale))
    small_i, small_a = downsample(indices, mask, (tw, th))
    if args.outline:
        if args.outline not in named:
            fail(f"--outline {args.outline!r} is not a palette name")
        outline(small_i, small_a, names.index(args.outline))

    bottom = min(py, ch) - 1 if not rows else rows[1]
    left = px - tw // 2
    top = bottom - th + 1
    if left < 0 or top < 0 or left + tw > cw:
        fail(f"content {tw}x{th} does not fit a {cw}x{ch} canvas at pivot {px},{py}; lower --fit")
    sprite = Image.new("RGBA", size, (0, 0, 0, 0))
    sprite.alpha_composite(to_rgba(small_i, small_a, colours), (left, top))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    stem = args.name or src.stem
    target = out / f"{stem}.png"
    if target.exists():
        fail(f"{target} exists; pick another --name or --out")
    sprite.save(target)
    light = named.get("paper", named.get("cream", (240, 232, 210)))
    dark = named.get("deep", named.get("ink", (30, 36, 42)))
    preview(sprite, light, dark).save(out / f"{stem}.x8.png")

    used = Counter()
    sp = sprite.load()
    for y in range(ch):
        for x in range(cw):
            r, g, b, a = sp[x, y]
            if a:
                used[names[colours.index((r, g, b))]] += 1
    problems = check(target, size, named, rows)
    report = {
        "source": str(src),
        "crop": args.crop,
        "source_bbox": list(box),
        "canvas": [cw, ch],
        "pivot": [px, py],
        "content": [tw, th],
        "placed_at": [left, top],
        "outline": args.outline,
        "colours_used": dict(used.most_common()),
        "problems": problems,
    }
    (out / f"{stem}.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"sprite": str(target), "content": [tw, th], "colours": len(used), "problems": problems}))


if __name__ == "__main__":
    main()
