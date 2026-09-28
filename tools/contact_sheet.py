"""Render an inventory, seam sample, and light/dark transparency proof from source PNGs."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_assets import contract_size

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "art/daylight")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source
    pack = json.loads((source / "pack.json").read_text())
    # The sheet dresses itself in the pack under review, so a dark theme stays legible.
    paper, ink = "#" + pack["palette"]["paper"], "#" + pack["palette"]["ink"]
    image = Image.new("RGBA", (1600, 1280), paper)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(source / pack["font"]["path"]), 20)
    title_font = ImageFont.truetype(str(source / pack["font"]["path"]), 30)

    def title(text, at, fill=ink):
        draw.text(at, text, fill=fill, font=font)

    def put(category, info, at, scale=2):
        # `scale` sheet pixels per unit, whatever density the PNG was painted
        # at: a pack mixes 1x and 2x sources, and the build fills the 1x ones
        # in with nearest, so the sheet does too. At a scale below the pack's
        # density (the selection overview) this skips texels.
        sprite = Image.open(source / info["path"]).convert("RGBA")
        width, height = contract_size(pack, category, info)
        image.alpha_composite(sprite.resize((width * scale, height * scale), Image.Resampling.NEAREST), at)

    draw.rectangle((0, 0, 1599, 59), fill=ink)
    draw.text((24, 12), f"{pack['name'].upper()} / REPLACEABLE GODOT ART KIT", font=title_font, fill=paper)
    title(f"{len(pack['tiles'])} TILES / {pack['tile_size']}px grid", (24, 76))
    for index, (name, info) in enumerate(pack["tiles"].items()):
        x, y = 24 + index % 13 * 118, 112 + index // 13 * 94
        draw.rectangle((x, y, x + 63, y + 63), fill="#d9d2bf")
        put("tiles", info, (x, y))
        title(str(index).zfill(2), (x + 68, y + 22))
    title(f"{len(pack['props'])} PROPS / identical sprites on LIGHT and DARK backgrounds / 2x nearest", (24, 312))
    for row, background in enumerate((paper, ink)):
        top = 350 + row * 184
        draw.rectangle((16, top, 1583, top + 175), fill=background)
        for index, (name, info) in enumerate(pack["props"].items()):
            x = 28 + index * 194
            width, height = info["size"]
            put("props", info, (x + (160 - width * 2) // 2, top + 156 - height * 2))
            title(name.upper(), (x + 12, top + 156), ink if row == 0 else paper)
    # The people on a floor are the shared pixel people, not the pack's; the
    # people showroom (`make people`) is their inventory.
    title(f"{len(pack['ui'])} UI ASSETS", (880, 776))
    for index, (name, info) in enumerate(pack["ui"].items()):
        x, y = 880 + index % 4 * 172, 817 + index // 4 * 118
        put("ui", info, (x, y), 1 if name == "selection" else 2)
        title(name, (x, y + 72))
    title(f"{len(pack['palette'])}-COLOR SHARED PALETTE", (880, 1170))
    for index, value in enumerate(pack["palette"].values()):
        x, y = 880 + index % 22 * 28, 1208 + index // 22 * 24
        draw.rectangle((x, y, x + 23, y + 19), fill="#" + value)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(args.output)
    print(f"CONTACT_SHEET_OK: {args.output}")


if __name__ == "__main__":
    main()
