"""Download agent badge sources and render them to the runtime's 64px badges.

The catalog deliberately distinguishes an external source from a generated
monogram. External SVGs are kept beside the generated PNGs for attribution;
the game only loads the normalized PNGs. This script needs ImageMagick (`magick`)
for SVG rasterization and never runs during a normal offline game build.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BADGE_SIZE = 64
MONOGRAM_COLORS = ["4b8e90", "9183a6", "bf7052", "535e66", "637b43", "9d6546"]


def read_catalog(path: Path) -> list[dict]:
    data = json.loads(path.read_text())
    return data["agents"]


def monogram(entry: dict, index: int) -> Image.Image:
    image = Image.new("RGBA", (BADGE_SIZE, BADGE_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    ink = (38, 54, 59, 255)
    paper = (246, 232, 200, 255)
    fill = tuple(bytes.fromhex(MONOGRAM_COLORS[index % len(MONOGRAM_COLORS)])) + (255,)
    draw.rounded_rectangle((2, 2, 61, 61), radius=12, fill=ink)
    draw.rounded_rectangle((6, 6, 57, 57), radius=9, fill=paper)
    draw.rounded_rectangle((10, 10, 53, 53), radius=7, fill=fill)
    letters = "".join(part[0] for part in str(entry["name"]).replace("-", " ").split()[:2]).upper()
    if len(letters) == 1:
        letters += letters
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    font = ImageFont.truetype(font_path, 20)
    box = draw.textbbox((0, 0), letters[:2], font=font)
    draw.text(((64 - (box[2] - box[0])) / 2, (64 - (box[3] - box[1])) / 2 - 3), letters[:2], fill=ink, font=font)
    return image


def normalize_badge(source: Path, target: Path) -> None:
    with Image.open(source).convert("RGBA") as logo:
        logo.thumbnail((40, 40), Image.Resampling.LANCZOS)
        badge = Image.new("RGBA", (BADGE_SIZE, BADGE_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(badge)
        draw.ellipse((1, 1, 62, 62), fill=(38, 54, 59, 255))
        draw.ellipse((5, 5, 58, 58), fill=(246, 232, 200, 255))
        badge.alpha_composite(logo, ((BADGE_SIZE - logo.width) // 2, (BADGE_SIZE - logo.height) // 2))
    target.parent.mkdir(parents=True, exist_ok=True)
    badge.save(target)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=ROOT / "data/agent_catalog.json")
    parser.add_argument("--source", type=Path, default=ROOT / "art/agent_badges")
    parser.add_argument("--output", type=Path, default=ROOT / "assets/agent_badges")
    args = parser.parse_args()
    if shutil.which("magick") is None:
        raise SystemExit("fetch_agent_logos: ImageMagick `magick` is required")
    entries = read_catalog(args.catalog)
    args.source.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    attribution: list[str] = [
        "# Agent badge sources",
        "",
        "These normalized 64x64 PNG badges are used only as small chest markers.",
        "Canonical IDs come from Herdr 0.9.1; branding remains owned by each agent vendor.",
        "",
    ]
    with tempfile.TemporaryDirectory(prefix="herdstead-agent-logos-") as temp:
        temp_dir = Path(temp)
        for index, entry in enumerate(entries):
            agent_id = entry["id"]
            svg_target = args.source / "source" / f"{agent_id}.svg"
            raw_png = temp_dir / f"{agent_id}.png"
            if entry["logo_url"]:
                request = urllib.request.Request(entry["logo_url"], headers={"User-Agent": "Herdstead asset builder"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    svg_target.parent.mkdir(parents=True, exist_ok=True)
                    svg_target.write_bytes(response.read())
                try:
                    subprocess.run([
                        "magick", "-background", "none", str(svg_target),
                        "-resize", "40x40", "-gravity", "center", "-extent", "40x40", str(raw_png),
                    ], check=True, capture_output=True)
                    normalize_badge(raw_png, args.source / f"{agent_id}.png")
                except subprocess.CalledProcessError:
                    # A vendor SVG may use a path/gradient feature that the
                    # sandbox's ImageMagick build cannot rasterize. Keep the
                    # downloaded source for attribution and use a deterministic
                    # monogram instead of silently dropping the agent badge.
                    monogram(entry, index).save(args.source / f"{agent_id}.png")
                shutil.copyfile(args.source / f"{agent_id}.png", args.output / f"{agent_id}.png")
            else:
                image = monogram(entry, index)
                image.save(args.source / f"{agent_id}.png")
                image.save(args.output / f"{agent_id}.png")
            attribution.append(f"- `{agent_id}` — {entry['logo_source']}; {entry['logo_license']}; {entry['logo_url'] or 'generated in tools/fetch_agent_logos.py'}")
    (args.source / "ATTRIBUTIONS.md").write_text("\n".join(attribution) + "\n")
    (args.output / "ATTRIBUTIONS.md").write_text("\n".join(attribution) + "\n")
    print(f"AGENT_LOGOS_OK: {len(entries)} badges in {args.output}")


if __name__ == "__main__":
    main()
