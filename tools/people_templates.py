"""Export the pixel people's artist templates (`make people-templates OUT=<empty dir>`).

Everything an artist needs to paint the sources tools/build_pixel_people.py
reads from art/pixel_people/, taken from people.json and the builder's own
functions (never from the product manifest):

* canvases/<facing>/<source>.png  every source strip the contract names, empty,
                                   at exactly the size the builder checks
* guides/<facing>/<source>.png     the same size, a layer of its own: frame
                                   edges, the pivot cross and the foot line in
                                   every frame, grey over the frames a track does
                                   not draw from this facing, a faint ghost of the
                                   current placeholder, and on hair and headwear
                                   the brim of every hat worn over the hair
* canvases/skins/<facing>/<part>.png  every skin a part can wear (head, torso,
                                   each hair style and hat), empty, at its part's
                                   cell envelope times the density
* guides/skins/<facing>/<part>.png the same size: the rig's flat tones where the
                                   skin may paint, grey where it may not (the
                                   corners, the neckline, which are not its
                                   cells), and the eyes the rig paints over it
* sheets/<facing>.png              an overview at --scale per texel: every
                                   track's frames of the whole placeholder
                                   figure, labelled
* swatches.png                     the key-colour legend: each role's three keys,
                                   the layer that owns it, and the fixed colours
* files.tsv                        every source: size, frame, pivot, the columns
                                   it draws, the colours it may hold, mock or painted
* skins.tsv                        every skin: canvas, layer, colours, painted or not
* README.txt                       the rules the builder enforces

The output directory must be empty (or missing): painted work is never
overwritten. The guide colours are deliberately outside every palette.

    .venv/bin/python tools/people_templates.py --output /abs/empty-dir [--scale 4]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_pixel_people import (
    BASE_LAYERS,
    DETAILS,
    SOURCE,
    Painter,
    PeopleError,
    cells_of,
    colour_slot,
    column_count,
    draw_figure,
    draw_placeholder,
    frame_texels,
    layer_of,
    load_spec,
    skin_files,
    skin_layer,
    skin_mask,
    skin_rows,
    skin_size,
    source_files,
    starts,
    strip_size,
)

# Guide furniture: off-palette, never part of the artwork.
EDGE = (141, 153, 166, 255)
PIVOT = (215, 68, 62, 255)
FOOT = (57, 116, 69, 255)
UNDRAWN = (120, 120, 120, 110)
BRIM = (224, 138, 30, 255)
GHOST_ALPHA = 60
PAPER = (247, 244, 238, 255)
INK = (29, 34, 38, 255)


def guide(spec: dict, facing: str, sheet: str) -> Image.Image:
    """The guide layer of one source strip, in texels: the foot line is the
    lowest texel row of the unit above the pivot."""
    d = spec["density"]
    width, height = frame_texels(spec)
    pivot_x, pivot_y = (value * d for value in spec["pivot"])
    size = strip_size(spec)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ghost = draw_placeholder(spec, facing, sheet)
    faded = ghost.copy()
    faded.putalpha(ghost.getchannel("A").point(lambda a: GHOST_ALPHA if a else 0))
    layer.alpha_composite(faded)
    draw = ImageDraw.Draw(layer)
    first = starts(spec)
    brims = hat_brims(spec, facing) if layer_of(sheet) in ("hair", "headwear") else {}
    for track, info in spec["tracks"].items():
        for index in range(len(info["durations"])):
            column = first[track] + index
            left = column * width
            if facing not in info["facings"]:
                draw.rectangle((left, 0, left + width - 1, height - 1), fill=UNDRAWN)
                continue
            draw.line((left, 0, left, height - 1), fill=EDGE)
            draw.line((left, pivot_y - 1, left + width - 1, pivot_y - 1), fill=FOOT)
            draw.line((left + pivot_x - 2 * d, pivot_y, left + pivot_x + 2 * d, pivot_y), fill=PIVOT)
            draw.line((left + pivot_x, pivot_y - 2 * d, left + pivot_x, min(height - 1, pivot_y + 2 * d)), fill=PIVOT)
            for row in brims.get(column, []):
                draw.line((left + 1, row, left + width - 2, row), fill=BRIM)
    return layer


def hat_brims(spec: dict, facing: str) -> dict[int, list[int]]:
    """Column -> the top texel row of the lowest unit row of every hat worn
    over the hair in that frame: the hair above it must be under the hat."""
    d = spec["density"]
    width, height = frame_texels(spec)
    found: dict[int, list[int]] = {}
    for shape, flags in spec["slots"]["headwear"]["shapes"].items():
        if flags.get("hides_hair", False):
            continue
        strip = draw_placeholder(spec, facing, f"headwear_{shape}")
        for column in range(column_count(spec)):
            box = strip.crop((column * width, 0, (column + 1) * width, height)).getchannel("A").getbbox()
            if box is not None:
                found.setdefault(column, []).append((box[3] - 1) // d * d)
    return found


def overview(spec: dict, facing: str, scale: int, font) -> Image.Image:
    """Every drawn frame of the whole placeholder figure, a row per track;
    `scale` screen pixels per texel."""
    width, height = frame_texels(spec)
    figure = draw_figure(spec, facing)
    tracks = [(track, info) for track, info in spec["tracks"].items() if facing in info["facings"]]
    label = 150
    most = max(len(info["durations"]) for _track, info in tracks)
    sheet = Image.new("RGBA", (label + most * width * scale, len(tracks) * height * scale), PAPER)
    draw = ImageDraw.Draw(sheet)
    first = starts(spec)
    for row, (track, info) in enumerate(tracks):
        top = row * height * scale
        draw.text((6, top + 6), f"{track}\n{len(info['durations'])} frames\ncolumns {first[track]}-"
                  f"{first[track] + len(info['durations']) - 1}", fill=INK, font=font)
        for index in range(len(info["durations"])):
            column = first[track] + index
            frame = figure.crop((column * width, 0, (column + 1) * width, height))
            frame = frame.resize((width * scale, height * scale), Image.Resampling.NEAREST)
            sheet.alpha_composite(frame, (label + index * width * scale, top))
    return sheet


def legend(spec: dict, font) -> Image.Image:
    """Each role's key ramp and the layer that owns it, then the fixed colours."""
    rows = [(f"{info['role']} keys: {slot} on the {info['layer']} layer", spec["keys"][info["role"]])
            for slot, info in spec["slots"].items() if "role" in info]
    rows += [(f"fixed {name} (any layer)", [colour]) for name, colour in spec["fixed"].items()]
    sheet = Image.new("RGBA", (760, 30 * len(rows) + 12), PAPER)
    draw = ImageDraw.Draw(sheet)
    for index, (name, colours) in enumerate(rows):
        top = 6 + index * 30
        for tone, colour in enumerate(colours):
            draw.rectangle((8 + tone * 90, top, 32 + tone * 90, top + 24), fill="#" + colour, outline=INK)
            draw.text((36 + tone * 90, top + 6), colour, fill=INK, font=font)
        draw.text((290, top + 6), name + ("  (light, mid, dark)" if len(colours) == 3 else ""), fill=INK, font=font)
    return sheet


def skin_guide(spec: dict, facing: str, part: str) -> Image.Image:
    """The guide of one skin canvas: the rig's own flat tones on the texels the
    skin may paint, grey on the ones it may not, and the eyes marked."""
    d = spec["density"]
    size = skin_size(spec, facing, part)
    cells = cells_of(skin_rows(facing, part), 0, 0)
    painter = Painter(spec)
    painter.stamp(cells, ring=False)
    ghost = painter.image().crop((0, 0, *size))
    ghost.putalpha(ghost.getchannel("A").point(lambda a: GHOST_ALPHA * 2 if a else 0))
    layer, mask = ghost, skin_mask(spec, facing, part)
    for y in range(size[1]):
        for x in range(size[0]):
            if (x, y) not in mask:
                layer.putpixel((x, y), UNDRAWN)
    for (x, y), letter in cells.items():
        if letter in DETAILS and (x * d, y * d) in mask:
            for j in range(d):
                for i in range(d):
                    layer.putpixel((x * d + i, y * d + j), PIVOT)
    return layer


def allowed(spec: dict, sheet: str) -> str:
    slot = colour_slot(spec, layer_of(sheet))
    roles = [spec["slots"][slot]["role"]] if slot else []
    return ",".join([f"{role} keys" for role in roles] + ["fixed"])


def export(source: Path, output: Path, scale: int) -> int:
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise PeopleError(f"{output}: use an empty output directory; existing work is never overwritten")
    spec = load_spec(source)
    output.mkdir(parents=True, exist_ok=True)
    # Guides and unfinished canvases are not Godot resources.
    (output / ".gdignore").touch()
    font = ImageFont.load_default()
    d = spec["density"]
    width, height = frame_texels(spec)
    first = starts(spec)
    inventory = ["path\tstrip_px\tframe_px\tpivot_px_in_each_frame\tcolumns_drawn\tmay_hold\tstatus"]
    count = 0
    for relative, facing, sheet in source_files(spec):
        for folder, picture in (("canvases", Image.new("RGBA", strip_size(spec), (0, 0, 0, 0))),
                                ("guides", guide(spec, facing, sheet))):
            path = output / folder / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            picture.save(path)
        drawn = [f"{track} {first[track]}-{first[track] + len(info['durations']) - 1}"
                 for track, info in spec["tracks"].items() if facing in info["facings"]]
        inventory.append("\t".join([
            relative, "x".join(str(v) for v in strip_size(spec)), f"{width}x{height}",
            ",".join(str(v * d) for v in spec["pivot"]), "; ".join(drawn), allowed(spec, sheet),
            "painted" if (source / relative).is_file() else "mock",
        ]))
        count += 1
    skins = ["path\tcanvas_px\tlayer\tmay_hold\tstatus"]
    for relative, facing, part in skin_files(spec):
        for folder, picture in (("canvases", Image.new("RGBA", skin_size(spec, facing, part), (0, 0, 0, 0))),
                                ("guides", skin_guide(spec, facing, part))):
            path = output / folder / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            picture.save(path)
        skins.append("\t".join([
            relative, "x".join(str(v) for v in skin_size(spec, facing, part)), skin_layer(part),
            allowed(spec, skin_layer(part)), "painted" if (source / relative).is_file() else "none",
        ]))
    for facing in spec["facings"]:
        path = output / "sheets" / f"{facing}.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        overview(spec, facing, scale, font).save(path)
    legend(spec, font).save(output / "swatches.png")
    (output / "files.tsv").write_text("\n".join(inventory) + "\n", encoding="utf-8")
    (output / "skins.tsv").write_text("\n".join(skins) + "\n", encoding="utf-8")
    base = ", ".join(BASE_LAYERS)
    (output / "README.txt").write_text(
        f"Pixel people painter templates / {count} source strips, {len(skins) - 1} skins / density {d} ({d}x{d} pixels per unit) / "
        f"each frame {width}x{height} pixels ({spec['frame_size'][0]}x{spec['frame_size'][1]} units), {column_count(spec)} frames per strip\n\n"
        "canvases/ holds full-size transparent canvases; guides/ holds a separate guide layer of the same name and size: "
        "put the guide on top in your paint program, and hide it before exporting.\n"
        "Put only painted PNGs into art/pixel_people/, at the relative paths in files.tsv; never copy empty canvases, guides or overview sheets.\n"
        "Then run the Makefile's art, test-art, test and people targets to check them; the full rules are in docs/ASSET_SPEC.md, \"Pixel people\".\n"
        "The template output directory must be empty; export again into a new directory so painted work is never overwritten.\n\n"
        "Rules the builder checks one by one, refusing anything that breaks them:\n"
        f"1. The size is exactly the strip size (strip_px in files.tsv), one frame {width}x{height}, the motions in one row in people.json's order.\n"
        "2. alpha is only 0 or 255: no semi-transparent edges.\n"
        "3. Every opaque pixel is a key or fixed colour this layer may use (may_hold in files.tsv; colours in swatches.png): "
        "one layer uses one role's three key tones (light, mid, dark), plus the fixed colours (ink outline, eye, shoes, paper, cup, lens...).\n"
        f"4. In every motion this facing draws, every frame has content on the three body layers ({base}); the columns of a motion this facing "
        "does not draw (grey cells in the guide) must be empty.\n"
        f"5. Choreography is in units, 1 unit = {d} pixels: the feet are on row {spec['pivot'][1] * d - 1} (green line), the pivot at "
        f"({spec['pivot'][0] * d}, {spec['pivot'][1] * d}) (red cross): when walking the planted foot never moves and the upper body rises 1 unit ({d} pixels); "
        f"typing hands rise 1 unit in turn.\n"
        "6. A hat covers all hair above its brim (orange line): with a hat on, no hair shows above or beside it. A hood hides the whole hair layer and is exempt.\n"
        "7. Every fill colour is at least 40 RGB distance from the ink (deep skin, black hair and dark trousers too), or it blurs into the outline.\n"
        "8. The side is drawn facing people.json's side_faces (right); left is its mirror, never drawn on its own.\n"
        "9. Eye against skin: the builder prints the contrast of the fixed eye colour against each skin's mid tone (PEOPLE_EYE_CONTRAST, threshold 3:1). "
        "The deepest skin is below the threshold. The answer is a catchlight: when people.json has the fixed colour catchlight, from density 2 on the "
        "white model paints it on the top-left texel of the upper cell of each eye (skins never reach the eyes). "
        "A hand-painted body strip must paint that texel itself, in the same place.\n\n"
        "Painting the layers: legs (trousers and shoes), top (top and sleeves) and body (head, neck, hands, eyes and things held) stack bottom to top, "
        "and each layer paints only what shows: a hand in front of the top is painted on body (the top may be painted underneath, covered by the hand); "
        "a far hand behind the torso, which cannot be seen, is not painted.\n"
        "glasses, hair and headwear stack on top, one source strip per shape; colour is not in the shape, it is swapped in at build time.\n"
        "Glasses are a thin frame around the eye (the fixed colour frame, not ink: ink against the near-black eye joins into a black band): "
        "nothing is painted on the eye's two pixels, and lenses get no solid fill (the fixed colour lens is only for one texel of glint).\n\n"
        "Skins (skins/, less work than whole source strips): a part with no hand-painted source strip is drawn frame by frame by the builder's white "
        "model (each part a flat three-tone sticker with an ink outline).\n"
        "Paint one skin for the head (head), the torso (torso), each hair style (hair_<shape>) and each hat (headwear_<shape>), and put it at "
        "art/pixel_people/skins/<facing>/<part>.png; the white model wears it in every frame: position, ink and motion stay the white model's, "
        "the skin only gives the fill.\n"
        "a. The canvas is exactly the one in canvases/skins/ (canvas_px in skins.tsv): the part's cell envelope x density, the same for every frame; "
        f"seated, the torso loses its last row of cells and the skin's last {d} rows are unused.\n"
        "b. Paint only pixels that have a flat tone in the guide: grey ones are something else (outside the rounded corners, the neckline's skin, "
        "the outline) and painting them is refused. Unpainted pixels keep the white model's tones.\n"
        "c. Use only this layer's key and fixed colours (may_hold in skins.tsv); alpha is only 0 and 255.\n"
        "d. The eyes are marked red: the white model paints the eyes after the skin, so nothing painted there shows.\n"
        "e. A hand-painted whole source strip of the same name (<facing>/<strip>.png) still wins; when it exists, the matching skin is not used.\n",
        encoding="utf-8",
    )
    print(f"PEOPLE_TEMPLATES_OK: {count} canvases, {count} guides, {len(skins) - 1} skin canvases and guides, "
          f"{len(spec['facings'])} sheets: {output}")
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", type=Path, default=SOURCE, help="the source directory (default art/pixel_people)")
    parser.add_argument("--output", type=Path, required=True, help="an empty directory to write into")
    parser.add_argument("--scale", type=int, default=4, help="the overview sheets' magnification (default 4)")
    args = parser.parse_args()
    try:
        export(args.source, args.output, max(1, args.scale))
    except PeopleError as error:
        print(f"PEOPLE_TEMPLATES_FAILED: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
