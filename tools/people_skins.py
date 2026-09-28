"""Cut the pixel people's part skins out of one painted frame (`make people-skins`).

A skin (docs/ASSET_SPEC.md, "Skins") is a picture of one part the white model
wears: the head, the torso, a hair style or a hat, per facing. A painter does not
paint skins one by one; it repaints a whole frame of the white model, and this
tool cuts the parts out of that frame by the rig's own geometry:

    reference  the white model's frame in key colours, magnified for the painter
               (`--wear` adds hair and hats), and the pixelize.py arguments that
               bring its answer back onto the same texels (--stretch included: a
               kept aspect ratio lands the figure a texel off)
    cut        a pixelized frame -> art/pixel_people/skins/<facing>/<part>.png
    --check    every skin under art/pixel_people/skins, by the builder's rules

The frame is the one `reference` drew (default: the first frame of
stand_idle). Registration is checked first: the frame's opaque box must be the
box of the white model wearing what the picture shows (`--wear`; by default the
hair styles and hats being cut), texel for texel, or nothing is cut: from the
side a figure is not symmetric, and hair reaches back and a cap's peak forward. Then, per part, over its canvas (the
part's cell envelope times the density, placed where the rig places the part in
that frame):

* a texel on one of the part's own cells (skin_mask) keeps its colour when that
  is a key of the part's layer or a fixed colour; transparent stays transparent
  (the rig's tone shows there); any other colour is refused, with the frame and
  skin coordinates. One exception, the plan's mechanical fix: on a hat, a hair
  key becomes the hat's dark key, so a hat covers every hair texel under it.
  The eye and catchlight colours are the rig's alone (its eyes): refused on any
  part, and a head's eye cells are left to the rig whatever the picture shows.
  And a head or torso texel another layer covers in that frame (from the side
  the near hand hangs over the torso) is left to the rig: the picture shows the
  hand there, not the part.
* a texel off the part's cells (the ring, the rounded corners, the torso's
  neckline, the face a hair style leaves open) is dropped: those belong to the
  ring or another part. If it holds one of the part's own keys where the rig
  would not paint the part's colours either (a ring thinner than a cell carries
  them out to the ink), the painted part is bigger than the rig's and the frame
  is refused (out of the envelope). `--drop-outside` drops those texels instead
  and prints each one (SKIN_DROPPED): a model misses the torso's neckline by a
  texel or two in every picture, and nothing of the part is lost by dropping
  what lies off its cells.

A skin is written only when every part passed, and an existing skin is never
overwritten (delete it first). The builder checks every skin again.

Run from the repository root::

    .venv/bin/python tools/people_skins.py reference --facing front --out ref.png [--wear hair_short]
    .venv/bin/python tools/people_skins.py cut frame.png --facing front --parts head,torso \\
        --out art/pixel_people/skins/front
    .venv/bin/python tools/people_skins.py --check
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

from build_pixel_people import (
    EYE_COLOURS,
    LAYERS,
    SKIN_DIR,
    SOURCE,
    Figure,
    Painter,
    PeopleError,
    allowed_colours,
    cells_of,
    colour_slot,
    frame_texels,
    from_source,
    layer_of,
    load_skins,
    load_spec,
    poses,
    require,
    rgb,
    shape_slot,
    skin_files,
    skin_layer,
    skin_mask,
    skin_parts,
    skin_rows,
    skin_size,
)

REFERENCE_TRACK = "stand_idle"
REFERENCE_SCALE = 8


def reference_pose(spec: dict, track: str, frame: int):
    require(track in spec["tracks"], f"no track {track!r} in people.json")
    count = len(spec["tracks"][track]["durations"])
    require(0 <= frame < count, f"{track} has frames 0 to {count - 1}; asked for {frame}")
    return poses(track, count)[frame]


def role_keys(spec: dict, layer: str) -> set[tuple[int, int, int]]:
    """The key colours of the role a layer's colour slot maps."""
    slot = colour_slot(spec, layer)
    return set() if slot is None else {rgb(colour) for colour in spec["keys"][spec["slots"][slot]["role"]]}


def white_model(spec: dict, facing: str, track: str, frame: int, wear: list[str]) -> Image.Image:
    """The white model's frame in key colours: the figure, then each shape in
    `wear` (hair_<style>, headwear_<shape>, glasses_<shape>) over it, as the
    prefab stacks them."""
    figure = Figure(spec, reference_pose(spec, track, frame), facing)
    picture = figure.figure().image()
    for shape in wear:
        layer = layer_of(shape)
        slot = shape_slot(spec, layer) if layer in LAYERS else None
        require(slot is not None and shape.removeprefix(layer + "_") in spec["slots"][slot]["shapes"],
                f"--wear {shape}: not a hair style, hat or glasses people.json draws")
        picture = Image.alpha_composite(picture, figure.shape(layer, shape.removeprefix(layer + "_")))
    return picture


def rig_colours(spec: dict, facing: str, part: str) -> set[tuple[int, int]]:
    """The texels of a part's canvas the rig paints in the part's own colours:
    its cells of its layer and, with a ring thinner than a cell, the ring
    texels that carry those colours out to the ink."""
    d, layer = spec["density"], skin_layer(part)
    painter = Painter(spec)
    # One cell in from the corner, so the ring round the top and left edges lands on the canvas.
    painter.stamp(cells_of(skin_rows(facing, part), 1, 1))
    return {(x - d, y - d) for (x, y), owner in painter.owners.items() if owner == layer and painter.pixels[(x, y)] != painter.ink}


def cut_part(picture: Image.Image, spec: dict, facing: str, part: str, pose, label: str,
             drop_outside: bool = False) -> tuple[Image.Image, dict]:
    """One part's skin out of a registered frame, and what the cut did. With
    `drop_outside`, a texel out of the envelope is dropped (and listed) instead
    of refusing the frame."""
    d = spec["density"]
    left, top = (value * d for value in Figure(spec, pose, facing).skin_cell(part))
    width, height = skin_size(spec, facing, part)
    mask, layer = skin_mask(spec, facing, part), skin_layer(part)
    coloured = rig_colours(spec, facing, part)
    allowed, own = allowed_colours(spec, layer), role_keys(spec, layer)
    # The plan's mechanical fix for hats: hair under a hat is the hat's shade.
    hair = role_keys(spec, "hair") if layer == "headwear" else set()
    hat_dark = rgb(spec["keys"]["hat"][2])
    pixels = picture.load()
    # The figure's own parts (head, torso) can lie under another layer in the
    # frame the painter repainted: from the side the near hand hangs over the
    # torso. What the picture shows there is that layer, not this part, so the
    # cut leaves those texels to the rig. (Hair and hats are layers of their own.)
    owners = Figure(spec, pose, facing).figure().owners if layer in ("body", "top") else {}
    skin = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    done = {"painted": 0, "rig": 0, "dropped": 0, "brim": 0, "outside": [], "under": 0}
    # The eye cells are the rig's (it paints the eyes over any skin): left empty.
    eyes = {(cx * d + i, cy * d + j) for (cx, cy), letter in cells_of(skin_rows(facing, part), 0, 0).items()
            if letter == "e" for j in range(d) for i in range(d)}
    rigs = {rgb(spec["fixed"][name]): name for name in EYE_COLOURS if name in spec["fixed"]}
    for y in range(height):
        for x in range(width):
            fx, fy = left + x, top + y
            r, g, b, a = pixels[fx, fy] if 0 <= fx < picture.width and 0 <= fy < picture.height else (0, 0, 0, 0)
            where = f"{label}: pixel ({fx}, {fy}) (skin {part} ({x}, {y}))"
            if (x, y) not in mask:
                outside = a and (r, g, b) in own and (x, y) not in coloured
                require(not outside or drop_outside, f"{where} is #{r:02x}{g:02x}{b:02x}, a key of {part}, "
                        f"outside its cells: the painted {part} is bigger than the rig's (out of the envelope)")
                if outside:
                    done["outside"].append(f"{where} #{r:02x}{g:02x}{b:02x}")
                done["dropped"] += 1 if a else 0
            elif not a or (x, y) in eyes:
                done["rig"] += 1
            elif (r, g, b) in rigs:
                raise PeopleError(f"{where} is the {rigs[(r, g, b)]} colour, which only the rig paints (the eyes); a skin "
                                  f"never holds it: pixelize without fixed.{rigs[(r, g, b)]}")
            elif owners and owners.get((fx, fy)) != layer:
                done["under"] += 1
            elif (r, g, b) in allowed:
                skin.putpixel((x, y), (r, g, b, 255))
                done["painted"] += 1
            elif (r, g, b) in hair:
                skin.putpixel((x, y), (*hat_dark, 255))
                done["brim"] += 1
            else:
                raise PeopleError(f"{where} is #{r:02x}{g:02x}{b:02x}, which is not a key or fixed colour of the "
                                  f"{layer} layer (a foreign colour)")
    return skin, done


def cut(picture_path: Path, source: Path, facing: str, parts: list[str], out: Path, track: str, frame: int,
        drop_outside: bool = False, wear: list[str] | None = None) -> None:
    spec = load_spec(source)
    label = str(picture_path)
    require(facing in spec["facings"], f"--facing {facing}: people.json draws {', '.join(spec['facings'])}")
    known = skin_parts(spec)
    for part in parts:
        require(part in known, f"--parts {part}: a skin is one of {', '.join(known)}")
    require(facing in spec["tracks"][track]["facings"], f"{track} does not face {facing}")
    picture = from_source(picture_path)
    require(picture.size == frame_texels(spec), f"{label}: {picture.size} is not one {frame_texels(spec)} frame")
    for y in range(picture.height):
        for x in range(picture.width):
            alpha = picture.getpixel((x, y))[3]
            require(alpha in (0, 255), f"{label}: pixel ({x}, {y}) is semi-transparent (alpha {alpha})")
    pose = reference_pose(spec, track, frame)
    if wear is None:
        wear = [part for part in parts if layer_of(part) in ("hair", "headwear")]
    rig = white_model(spec, facing, track, frame, wear).getchannel("A").getbbox()
    box = picture.getchannel("A").getbbox()
    require(box is not None, f"{label}: nothing opaque")
    require(box == rig,
            f"{label}: the opaque box {box} is not the white model's {rig} in {track} frame {frame} wearing "
            f"{', '.join(wear) or 'no hair or hat'} (left {box[0] - rig[0]:+d}, right {box[2] - rig[2]:+d}, "
            f"top {box[1] - rig[1]:+d}, bottom {box[3] - rig[3]:+d} texels); "
            "pixelize with the --pivot, --fit and --stretch `reference` printed")
    cuts = {part: cut_part(picture, spec, facing, part, pose, label, drop_outside) for part in parts}
    for part in parts:
        target = out / f"{part}.png"
        require(not target.exists(), f"{target} exists; a skin is never overwritten (delete it first)")
    out.mkdir(parents=True, exist_ok=True)
    for part, (skin, done) in cuts.items():
        for where in done["outside"]:
            print(f"SKIN_DROPPED: {where}: out of the envelope of {part}, dropped (--drop-outside)")
        target = out / f"{part}.png"
        skin.save(target)
        print(f"SKIN_CUT: {target}: {done['painted']} texels painted, {done['rig']} left to the rig, "
              f"{done['dropped']} off its cells dropped" + (f", {done['brim']} hair texels made the hat's shade"
                                                             if done["brim"] else "")
              + (f", {done['under']} under another layer in this frame left to the rig" if done["under"] else ""))


def reference(source: Path, facing: str, track: str, frame: int, wear: list[str], scale: int, out: Path) -> None:
    spec = load_spec(source)
    require(facing in spec["tracks"][track]["facings"], f"{track} does not face {facing}")
    require(not out.exists(), f"{out} exists; pick another --out")
    picture = white_model(spec, facing, track, frame, wear)
    picture.resize((picture.width * scale, picture.height * scale), Image.Resampling.NEAREST).save(out)
    box = picture.getchannel("A").getbbox()
    width, height = frame_texels(spec)
    # pixelize.py sets the box's bottom row on the row above the pivot and its
    # left at the pivot less half its width: a pivot that puts it back on the
    # white model's box, which from the side is not centred on the frame.
    pivot = [box[0] + (box[2] - box[0]) // 2, box[3]]
    print(f"REFERENCE: {out} ({picture.width}x{picture.height} texels x{scale}); figure box {box}")
    print(f"PIXELIZE: --size {width}x{height} --pivot {pivot[0]},{pivot[1]} --fit {box[2] - box[0]}x{box[3] - box[1]} --stretch")


def check(source: Path) -> None:
    spec = load_spec(source)
    listed = {relative for relative, _facing, _part in skin_files(spec)}
    root = source / SKIN_DIR
    strays = sorted(str(path.relative_to(source)) for path in root.rglob("*.png")
                    if str(path.relative_to(source)) not in listed) if root.is_dir() else []
    require(not strays, f"{source}: PNG(s) the contract does not name: {', '.join(strays)}")
    skins = load_skins(source, spec)
    print(f"PEOPLE_SKINS_OK: {len(skins)} skin(s)" + (": " + ", ".join(f"{facing}/{part}" for facing, part in skins)
                                                     if skins else ""))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="check every skin under SOURCE/skins")
    parser.add_argument("--source", type=Path, default=SOURCE, help="the people source directory (default art/pixel_people)")
    commands = parser.add_subparsers(dest="command")
    for name in ("reference", "cut"):
        command = commands.add_parser(name)
        command.add_argument("--facing", required=True)
        command.add_argument("--track", default=REFERENCE_TRACK, help=f"the frame's track (default {REFERENCE_TRACK})")
        command.add_argument("--frame", type=int, default=0, help="the frame's index in the track (default 0)")
        command.add_argument("--out", type=Path, required=True)
    commands.choices["reference"].add_argument("--wear", default="", help="shapes over the figure, e.g. hair_short")
    commands.choices["reference"].add_argument("--scale", type=int, default=REFERENCE_SCALE)
    commands.choices["cut"].add_argument("picture", type=Path, help="the pixelized frame")
    commands.choices["cut"].add_argument("--parts", required=True, help="skins to cut, e.g. head,torso")
    commands.choices["cut"].add_argument("--wear", help="the hair and hats the picture shows (default: those in --parts)")
    commands.choices["cut"].add_argument("--drop-outside", action="store_true",
                                         help="drop a part's key painted off its cells (listing each) instead of refusing")
    args = parser.parse_args()
    try:
        if args.command == "cut":
            cut(args.picture, args.source, args.facing, [p for p in args.parts.split(",") if p], args.out, args.track,
                args.frame, args.drop_outside, None if args.wear is None else [w for w in args.wear.split(",") if w])
        elif args.command == "reference":
            reference(args.source, args.facing, args.track, args.frame, [w for w in args.wear.split(",") if w],
                      args.scale, args.out)
        elif args.check:
            check(args.source)
        else:
            parser.error("say cut, reference or --check")
    except PeopleError as error:
        print(f"PEOPLE_SKINS_FAILED: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
