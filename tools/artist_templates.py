"""Render drawing guides from a pack.json: canvas box, pivot cross, semantic ID.

Every plate is the exact canvas the build checks, blown up so the artist can see
the pixel grid, with the reference art composited underneath. `--blank` leaves
the canvases empty for drawing from scratch. The plates are whatever pack.json
lists, so a new tile, prop or icon gets its guide without a change here; the
people who work on a floor are the shared pixel people, which have their
own showroom (`make people`).

pack.json states every size in density-1 pixels, so `--density` multiplies the
canvases (and the pivots, and the 8px guide grid) to the size actually painted
at a schema-2 density. Labels keep quoting the real canvas.

    python tools/artist_templates.py --source art/daylight --output docs/templates --density 2
    python tools/artist_templates.py --source art/daylight --output /tmp/templates --scale 6 --blank
    python tools/artist_templates.py --source art/daylight --output /tmp/x4 --density 4 --scale 1
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
## Guide furniture is deliberately off-palette: it is never part of the artwork.
PAPER, INK, GUIDE, PIVOT, GRID = "#f7f4ee", "#1d2226", "#8d99a6", "#d7443e", "#e2e6ea"
CHECKER = ("#ffffff", "#e9edf1")


class Sheet:
    """A plate grid that grows downward; every plate carries the same guides."""

    def __init__(self, source: Path, scale: int, blank: bool, font_path: Path, density: int = 1):
        self.source = source
        self.scale = scale
        ## Sizes arrive in density-1 units; every plate is drawn at
        ## size * density art pixels, then blown up by scale.
        self.density = density
        self.blank = blank
        self.font = ImageFont.truetype(str(font_path), 20)
        self.small = ImageFont.truetype(str(font_path), 15)
        self.title_font = ImageFont.truetype(str(font_path), 30)

    def plate(self, draw, image, at, size, pivot, label, note, art=None, splits=0):
        """One canvas: checkerboard, 8px grid, outline, optional pivot cross and frame splits."""
        width, height = (round(value * self.density * self.scale) for value in size)
        x, y = at
        step = 8 * self.density * self.scale
        for row in range(0, height, step):
            for column in range(0, width, step):
                fill = CHECKER[((row // step) + (column // step)) % 2]
                draw.rectangle((x + column, y + row, x + min(column + step, width) - 1, y + min(row + step, height) - 1), fill=fill)
        if art is not None and not self.blank:
            image.alpha_composite(art.resize((width, height), Image.Resampling.NEAREST), (x, y))
        for row in range(step, height, step):
            draw.line((x, y + row, x + width - 1, y + row), fill=GRID)
        for column in range(step, width, step):
            draw.line((x + column, y, x + column, y + height - 1), fill=GRID)
        for index in range(1, splits):
            # Frame boundaries are hard cuts: art may never bleed across one.
            cut = x + index * width // splits
            draw.line((cut, y, cut, y + height - 1), fill=PIVOT, width=2)
        draw.rectangle((x, y, x + width - 1, y + height - 1), outline=GUIDE, width=2)
        if pivot is not None:
            px, py = (value * self.density * self.scale for value in pivot)
            draw.line((x + px, y, x + px, y + height - 1), fill=PIVOT)
            draw.line((x, y + py, x + width - 1, y + py), fill=PIVOT)
            draw.ellipse((x + px - 4, y + py - 4, x + px + 4, y + py + 4), outline=PIVOT, width=2)
        draw.text((x, y - 24), label, font=self.font, fill=INK)
        draw.text((x, y + height + 4), note, font=self.small, fill=GUIDE)

    def render(self, title, entries, columns, output: Path):
        """entries: (label, note, size, pivot, art, splits)."""
        cell_w = max(size[0] for _, _, size, _, _, _ in entries) * self.density * self.scale + 40
        # Rows take the height of their own tallest plate: a 16px badge row must
        # not inherit the 64px selection frame's whitespace.
        rows = [entries[index:index + columns] for index in range(0, len(entries), columns)]
        heights = [max(size[1] for _, _, size, _, _, _ in row) * self.density * self.scale + 64 for row in rows]
        image = Image.new("RGBA", (24 + columns * cell_w, 108 + sum(heights)), PAPER)
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, image.width - 1, 59), fill=INK)
        draw.text((24, 12), title, font=self.title_font, fill=PAPER)
        top = 108
        for row, height in zip(rows, heights):
            for index, (label, note, size, pivot, art, splits) in enumerate(row):
                self.plate(draw, image, (24 + index * cell_w, top), size, pivot, label, note, art, splits)
            top += height
        output.parent.mkdir(parents=True, exist_ok=True)
        image.convert("RGB").save(output)
        print(f"TEMPLATE_OK: {output}")

    def art(self, relative):
        with Image.open(self.source / relative) as opened:
            return opened.convert("RGBA")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=ROOT / "art/daylight")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scale", type=int, default=4, help="pixels per art pixel; use more to see the grid")
    parser.add_argument("--blank", action="store_true", help="omit the reference art, leaving empty canvases")
    parser.add_argument("--density", type=int, default=1, choices=(1, 2, 4, 8), help="draw the canvases at this schema-2 density")
    args = parser.parse_args()
    if args.scale < 1:
        parser.error("--scale must be positive")
    pack = json.loads((args.source / "pack.json").read_text())
    sheet = Sheet(args.source, args.scale, args.blank, args.source / pack["font"]["path"], args.density)
    name = pack["name"].upper()
    tile = pack["tile_size"]
    density = args.density
    ## pack.json numbers are density-1 pixels; the plates show what is painted.
    def px(*values):
        return "x".join(str(value * density) for value in values)

    def at(*values):
        return ",".join(str(value * density) for value in values)
    ## The plates show the painted canvas; the density rides in the heading so a
    ## long title still fits, and every note below quotes the real size.
    heading = name if density == 1 else f"{name} @ {density}x"

    sheet.render(
        f"{heading} / TILES / {px(tile, tile)} / no pivot, the grid is the anchor",
        [(key, f"atlas cell {info['cell'][0]},{info['cell'][1]}", (tile, tile), None, sheet.art(info["path"]), 0)
         for key, info in pack["tiles"].items()],
        7, args.output / "tiles.png")

    sheet.render(
        f"{heading} / PROPS / red cross = pivot, placed at the object's footing",
        [(key, f"{px(*info['size'])} / pivot {at(*info['pivot'])}",
          tuple(info["size"]), tuple(info["pivot"]), sheet.art(info["path"]), 0)
         for key, info in pack["props"].items()],
        4, args.output / "props.png")

    sheet.render(
        f"{heading} / UI / badge meaning is fixed, the drawing is not",
        [(key, f"{px(*info['size'])} / pivot {at(*info['pivot'])}"
          + (f" / 9-patch {[margin * density for margin in info['nine_patch']]}" if "nine_patch" in info else ""),
          tuple(info["size"]), tuple(info["pivot"]), sheet.art(info["path"]), 0)
         for key, info in pack["ui"].items()],
        4, args.output / "ui.png")


if __name__ == "__main__":
    main()
