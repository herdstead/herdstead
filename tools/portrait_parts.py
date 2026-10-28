"""Paint, cut and review the portraits' parts (`make portrait-parts`, `make portrait-sheet`).

A portrait part (docs/ASSET_SPEC.md, "Portraits") is one 80x80 key-colour picture
under art/portraits/parts/. A painter does not paint parts one by one: it paints
the base (a bald head on shoulders) first and, once that is approved, every other
part *on* the base, and this tool cuts the part out by what the picture changed:

    reference  the base (head + top; with --with, other parts over it) in key
               colours on a neutral ground, with a 2x2 ink registration tick in
               each top corner, x8 NEAREST; a guide image beside it (a 1-unit
               grid, face_box, the tile's corner mark); and the pixelize.py
               arguments that bring an answer back onto its texels
    cut        a pixelized picture -> art/portraits/parts/<part>.png
    --check    every part under art/portraits/parts, by the builder's rules
    sheet      a review contact sheet (never an asset): sheet2's twelve people,
               every part on the default look and 24 sample panes, each in a
               42x42 window of the HUD's cream with a state's frame

The cut's rules (the tests pin each one):

1. Registration: the picture is 80x80 with hard alpha, and every texel opaque in
   the base (the registration ticks included) is opaque in the picture: a part
   adds, it never erases.
2. The part is every texel where the picture differs from the base (a new colour
   on a base texel, or an opaque texel where the base is transparent) whose
   colour the part allows. Ink in that set is the part's (an outline it painted);
   ink identical to the base stays the base's.
3. Drift is every texel that differs in a colour the part does not allow (the
   model repainted a cheek or a collar): refused, or with --drop-drift dropped
   and printed one per line (PORTRAIT_DRIFT).
4. One picture can be two parts: an expression's texels in its brows' role keys
   (the hair's) are ``brows_<shape>``, the rest ``face_<shape>``.
5. The base itself (--part base; its ticks must be there, and are dropped): skin
   keys and the ink touching them (8-way)
   are ``head``, top keys and the ink touching only them ``top``; ink touching
   both is the head's (the upper layer); ink touching neither belongs to the ink
   it touches, the head first; any other colour is refused.
6. Every part is checked by the builder's own rules (its colours, face_box) and
   written only when every rule passed; an existing part is never overwritten
   (delete it first). The builder checks again, with the cross-part rules.

Run from the repository root::

    .venv/bin/python tools/portrait_parts.py reference --part hair --out DIR [--with hair_long]
    .venv/bin/python tools/portrait_parts.py cut picture.png --part expression --shape smile [--drop-drift]
    .venv/bin/python tools/portrait_parts.py --check
    .venv/bin/python tools/portrait_parts.py sheet --out DIR
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw

import build_pixel_people as people_build
from build_portraits import (
    FACE_LAYERS,
    LAYERS,
    NONE,
    PARTS_DIR,
    SOURCE,
    PortraitError,
    allowed_colours,
    canvas_texels,
    cells,
    check_source,
    face_box_texels,
    from_source,
    hats,
    layer_palette,
    load_parts,
    load_spec,
    placeholder,
    recolour,
    require,
    rgb,
    role_of,
    shapes_of,
    source_name,
)

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "art" / "daylight" / "pack.json"
CATALOG = ROOT / "data" / "agent_catalog.json"
REFERENCE_SCALE = 8
# The reference's ground: a mid grey no key or fixed colour is near.
NEUTRAL = (0x9a, 0x9a, 0x9a)
BASE = "base"
EXPRESSION = "expression"
# The tile's corner mark covers this many units from the window's top-left corner.
CORNER_MARK = 8
# The registration ticks' side, in texels.
TICK = 2
# What the HUD's frame says per state: the palette key of its edge (HudTheme's
# PortraitFrame<State>: blocked, done is unread, working, idle is muted).
STATE_EDGES = (("blocked", "blocked"), ("done", "unread"), ("working", "working"), ("idle", "muted"))
# The people's per-pane variation (PixelPeople.pick, VARIATION_SCHEME).
VARIATION_SCHEME = "herdstead.look/1"
PICK_PREFIX = "portrait."
SAMPLE_PANE = "local\x1fw0:t9:p{}"
SAMPLE_PROVIDER = "claude"
SAMPLES = 24
# The twelve people of the approved style sheet (build/paint/portrait-20261027/sheet2),
# read off the picture: skin, hair style and colour, top, hat and its colour,
# glasses, then the extras.
SHEET2 = (
    ("tan", "long", "brown", "slate", "none", "slate", "none", "smile", "none", "none"),
    ("porcelain", "long", "grey", "cream", "none", "slate", "square", "smile", "none", "none"),
    ("brown", "short", "blonde", "slate", "none", "slate", "none", "smirk", "none", "none"),
    ("tan", "short", "brown", "terra", "hood", "terra", "none", "smile", "none", "none"),
    ("fair", "long", "blonde", "slate", "none", "slate", "none", "smile", "freckles", "none"),
    ("porcelain", "curl", "grey", "cream", "none", "slate", "none", "smile", "none", "none"),
    ("tan", "curl", "brown", "teal", "cap", "teal", "none", "smile", "none", "headphones"),
    ("brown", "curl", "blonde", "cream", "none", "slate", "none", "smirk", "none", "none"),
    ("porcelain", "long", "black", "lilac", "cap", "cream", "round", "smile", "none", "none"),
    ("tan", "short", "black", "lilac", "cap", "cream", "none", "focus", "none", "none"),
    ("deep", "short", "black", "teal", "cap", "terra", "none", "smile", "none", "none"),
    ("fair", "short", "brown", "cream", "hood", "sea", "none", "focus", "none", "none"),
)
LOOK_SLOTS = ("skin", "hair_style", "hair_colour", "top", "headwear", "headwear_colour", "glasses")
EXTRA_SLOTS = ("expression", "marks", "neckwear")


# --- parts --------------------------------------------------------------------------


def load_part(source: Path, spec: dict, layer: str, shape: str | None) -> Image.Image:
    """One part as it stands: painted, or the builder's placeholder; checked on its
    own (the cross-part rules wait for the builder: a new base may need new hats)."""
    name = source_name(layer, shape)
    painted = source / PARTS_DIR / f"{name}.png"
    image = from_source(painted) if painted.is_file() else placeholder(spec, layer, shape)
    check_source(image, spec, layer, f"{PARTS_DIR}/{name}.png")
    return image


def parse_with(spec: dict, names: list[str]) -> list[tuple[str, str | None]]:
    """--with hair_long,face_smile -> [(layer, shape)]: parts drawn over the base."""
    found = []
    for name in names:
        layer = next((layer for layer in LAYERS if name == layer or name.startswith(layer + "_")), None)
        shape = None if layer is None or name == layer else name.removeprefix(layer + "_")
        require(layer is not None and shape in shapes_of(spec, layer),
                f"--with {name}: not a part the contract draws (e.g. hair_long, face_smile, headwear_cap)")
        found.append((layer, shape))
    return found


def compose(spec: dict, layered: dict[str, Image.Image]) -> Image.Image:
    """Parts stacked in the runtime's order (the manifest's layers, bottom to top)."""
    picture = Image.new("RGBA", canvas_texels(spec), (0, 0, 0, 0))
    for layer in LAYERS:
        if layer in layered:
            picture = Image.alpha_composite(picture, layered[layer])
    return picture


def ticks(spec: dict) -> set[tuple[int, int]]:
    """The registration ticks: a 2x2 ink square in each top corner of the canvas.
    The shoulders already run edge to edge on the bottom row, so with the ticks
    a picture's opaque box is the whole canvas, whatever height its hair or hat
    reaches, and pixelize.py's --fit lands it texel for texel."""
    width, _height = canvas_texels(spec)
    return {(x, y) for y in range(TICK) for x in (*range(TICK), *range(width - TICK, width))}


def base_picture(source: Path, spec: dict, wear: list[tuple[str, str | None]]) -> Image.Image:
    """The approved base (or its placeholder) in key colours, with `wear` over it
    and the registration ticks in the top corners where nothing is drawn."""
    layered = {"head": load_part(source, spec, "head", None), "top": load_part(source, spec, "top", None)}
    for layer, shape in wear:
        layered[layer] = load_part(source, spec, layer, shape)
    picture = compose(spec, layered)
    ink = (*rgb(spec["_people"]["fixed"]["ink"]), 255)
    for texel in ticks(spec):
        if not picture.getpixel(texel)[3]:
            picture.putpixel(texel, ink)
    return picture


def targets(spec: dict, part: str, shape: str | None) -> list[tuple[str, str | None]]:
    """(layer, shape) of every file one picture of `part` yields."""
    if part == BASE:
        return [("head", None), ("top", None)]
    if part == EXPRESSION:
        bound = [layer for layer in LAYERS if spec["layers"][layer]["shape"] == EXPRESSION]
        require(shape in spec["extras"][EXPRESSION]["options"],
                f"--part {EXPRESSION} needs --shape, one of {spec['extras'][EXPRESSION]['options']}")
        return [(layer, shape) for layer in bound]
    if part in LAYERS and spec["layers"][part]["shape"] is not None:
        require(shape in shapes_of(spec, part), f"--part {part} needs --shape, one of {shapes_of(spec, part)}")
        return [(part, shape)]
    # An option drawn by exactly one layer names itself: freckles, headphones.
    owners = [layer for layer in LAYERS if spec["layers"][layer]["shape"] is not None
              and part in shapes_of(spec, layer)]
    require(len(owners) == 1, f"--part {part}: one of {BASE}, {EXPRESSION}, a shaped layer "
            f"({', '.join(layer for layer in LAYERS if spec['layers'][layer]['shape'])}) or an option only one draws")
    require(shape in (None, part), f"--part {part} is itself the shape; --shape {shape} contradicts it")
    return [(owners[0], part)]


def part_layers(spec: dict, part: str) -> list[str]:
    """The layers one picture of `part` paints, whatever its shape."""
    if part == BASE:
        return ["head", "top"]
    if part in LAYERS and spec["layers"][part]["shape"] is not None:
        return [part]
    bound = [layer for layer in LAYERS if spec["layers"][layer]["shape"] == part]
    if bound:
        return bound
    return [layer for layer, _shape in targets(spec, part, None)]


def part_roles(spec: dict, layers: list[str]) -> list[str]:
    return sorted({role for role in (role_of(spec, layer) for layer in layers) if role})


# --- reference ----------------------------------------------------------------------


def pixelize_names(spec: dict, layers: list[str]) -> tuple[list[str], list[str]]:
    """pixelize.py's names for every colour the picture may hold (the base's and the
    part's), and the portrait-only colours it has to be given as --colours (cN)."""
    names, extra = set(), []
    for layer in layers:
        for name in layer_palette(spec, layer):
            if name.startswith("fixed.") and name.removeprefix("fixed.") in spec["fixed"]:
                if name not in extra:
                    extra.append(name)
            elif name.startswith("fixed."):
                names.add(name)
            else:
                names.add("key." + name)
    return sorted(names) + [f"c{index}" for index in range(len(extra))], [
        spec["fixed"][name.removeprefix("fixed.")] for name in extra]


def reference(source: Path, part: str, out: Path, wear_names: list[str], scale: int = REFERENCE_SCALE) -> None:
    spec = load_spec(source)
    wear = parse_with(spec, wear_names)
    painted = part_layers(spec, part)
    require(not out.exists() or not any(out.iterdir()), f"{out} is not empty; pick another --out")
    out.mkdir(parents=True, exist_ok=True)
    picture = base_picture(source, spec, wear)
    width, height = picture.size
    ground = Image.new("RGBA", picture.size, (*NEUTRAL, 255))
    ground.alpha_composite(picture)
    shown = out / "reference.png"
    ground.resize((width * scale, height * scale), Image.Resampling.NEAREST).save(shown)
    guide = guide_image(spec, scale)
    guide.save(out / "guide.png")
    box = picture.getchannel("A").getbbox()
    pivot = (box[0] + (box[2] - box[0]) // 2, box[3])
    layers = ["head", "top"] + [layer for layer, _shape in wear] + painted
    only, extra = pixelize_names(spec, layers)
    people = os.path.relpath((source / spec["people"]).resolve(), Path.cwd())
    print(f"REFERENCE: {shown} ({width}x{height} texels x{scale}, on #{bytes(NEUTRAL).hex()}); guide {out / 'guide.png'}; "
          f"opaque box {box}" + (f"; wearing {', '.join(wear_names)}" if wear_names else ""))
    print(f"PIXELIZE: --size {width}x{height} --pivot {pivot[0]},{pivot[1]} --fit {box[2] - box[0]}x{box[3] - box[1]} "
          f"--stretch --key {bytes(NEUTRAL).hex()} --people {people} --roles {','.join(part_roles(spec, layers))}"
          + (f" --colours {','.join(extra)}" if extra else "") + f" --only {','.join(only)}")


def guide_image(spec: dict, scale: int) -> Image.Image:
    """A transparent overlay at the reference's scale: the 1-unit grid, face_box
    and the tile's corner mark."""
    width, height = canvas_texels(spec)
    unit = spec["density"] * scale
    guide = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(guide)
    for step in range(0, width * scale + 1, unit):
        draw.line([(step, 0), (step, height * scale - 1)], fill=(255, 255, 255, 70))
    for step in range(0, height * scale + 1, unit):
        draw.line([(0, step), (width * scale - 1, step)], fill=(255, 255, 255, 70))
    x0, y0, x1, y1 = (value * scale for value in face_box_texels(spec))
    draw.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(255, 40, 40, 255), width=2)
    mark = CORNER_MARK * unit
    draw.rectangle([0, 0, mark - 1, mark - 1], outline=(40, 120, 255, 255), width=2)
    return guide


# --- cut ----------------------------------------------------------------------------


def split_base(picture: Image.Image, spec: dict, label: str) -> tuple[Image.Image, Image.Image]:
    """Rule 5: (head, top) of a painted base."""
    pixels = picture.load()
    skin = {rgb(colour) for colour in spec["_people"]["keys"][role_of(spec, "head")]}
    cloth = {rgb(colour) for colour in spec["_people"]["keys"][role_of(spec, "top")]}
    ink = rgb(spec["_people"]["fixed"]["ink"])
    owner: dict[tuple[int, int], str] = {}
    inks = []
    # The registration ticks are the reference's, never the base's.
    marks = ticks(spec) if picture.size == canvas_texels(spec) else set()
    for y in range(picture.height):
        for x in range(picture.width):
            r, g, b, a = pixels[x, y]
            if not a or ((x, y) in marks and (r, g, b) == ink):
                continue
            if (r, g, b) in skin:
                owner[(x, y)] = "head"
            elif (r, g, b) in cloth:
                owner[(x, y)] = "top"
            elif (r, g, b) == ink:
                inks.append((x, y))
            else:
                raise PortraitError(f"{label}: texel ({x}, {y}) is #{r:02x}{g:02x}{b:02x}; a base holds only skin "
                                    "keys, top keys and ink")
    filled = dict(owner)

    def around(x: int, y: int) -> set[str]:
        return {filled[(x + dx, y + dy)] for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                if (dx or dy) and (x + dx, y + dy) in filled}

    for x, y in inks:
        touching = {owner[(x + dx, y + dy)] for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                    if (dx or dy) and (x + dx, y + dy) in owner}
        if touching:
            filled[(x, y)] = "head" if "head" in touching else "top"
    left = [texel for texel in inks if texel not in filled]
    while left:
        settled = {texel: ("head" if "head" in around(*texel) else "top") for texel in left if around(*texel)}
        require(settled, f"{label}: ink at {', '.join(str(texel) for texel in left[:8])} touches neither the skin, "
                "the top nor ink that does")
        filled.update(settled)
        left = [texel for texel in left if texel not in filled]
    head = Image.new("RGBA", picture.size, (0, 0, 0, 0))
    top = Image.new("RGBA", picture.size, (0, 0, 0, 0))
    for texel, layer in filled.items():
        (head if layer == "head" else top).putpixel(texel, pixels[texel])
    return head, top


def route(spec: dict, made: list[tuple[str, str | None]], colour: tuple[int, int, int]) -> int:
    """Rule 4: which of `made` a texel of `colour` goes to: the one whose role keys
    hold it (brows: the hair's), else the first that allows it (face)."""
    for index, (layer, _shape) in enumerate(made):
        role = role_of(spec, layer)
        if role and colour in {rgb(key) for key in spec["_people"]["keys"][role]} and len(made) > 1:
            return index
    return next(index for index, (layer, _shape) in enumerate(made) if colour in allowed_colours(spec, layer))


def check_cut(spec: dict, layer: str, image: Image.Image, relative: str) -> None:
    """The builder's single-part rules on a cut part: its colours, and face_box."""
    check_source(image, spec, layer, relative)
    if layer in FACE_LAYERS:
        x0, y0, x1, y1 = face_box_texels(spec)
        alpha = image.getchannel("A").load()
        for y in range(image.height):
            for x in range(image.width):
                require(not alpha[x, y] or (x0 <= x < x1 and y0 <= y < y1),
                        f"{relative}: texel ({x}, {y}) is outside face_box (texels x {x0}..{x1 - 1}, "
                        f"y {y0}..{y1 - 1})")


def cut(picture_path: Path, source: Path, part: str, shape: str | None, drop_drift: bool = False,
        wear_names: list[str] | None = None) -> list[Path]:
    spec = load_spec(source)
    label = str(picture_path)
    made = targets(spec, part, shape)
    picture = from_source(picture_path)
    require(picture.size == canvas_texels(spec), f"{label}: {picture.size} is not the {canvas_texels(spec)} canvas")
    pixels = picture.load()
    for y in range(picture.height):
        for x in range(picture.width):
            require(pixels[x, y][3] in (0, 255), f"{label}: texel ({x}, {y}) is semi-transparent (alpha "
                    f"{pixels[x, y][3]})")
    width, height = picture.size
    outputs = [Image.new("RGBA", picture.size, (0, 0, 0, 0)) for _ in made]
    notes = []
    if part == BASE:
        lost = sorted(texel for texel in ticks(spec) if not pixels[texel][3])
        require(not lost, f"{label}: the registration ticks are gone at {lost[:4]}; pixelize with the --pivot, --fit "
                "and --stretch `reference` printed, from a picture that keeps them")
        outputs = list(split_base(picture, spec, label))
    else:
        base = base_picture(source, spec, parse_with(spec, wear_names or [])).load()
        erased = [(x, y) for y in range(height) for x in range(width) if base[x, y][3] and not pixels[x, y][3]]
        require(not erased, f"{label}: the base is opaque but the picture is not at {len(erased)} texel(s), "
                f"e.g. {', '.join(str(texel) for texel in erased[:8])}; a part adds, it never erases (pixelize with "
                "the --pivot, --fit and --stretch `reference` printed)")
        allowed = set().union(*(allowed_colours(spec, layer) for layer, _shape in made))
        drift = []
        for y in range(height):
            for x in range(width):
                r, g, b, a = pixels[x, y]
                if not a or (base[x, y][3] and base[x, y][:3] == (r, g, b)):
                    continue
                if (r, g, b) not in allowed:
                    drift.append(f"texel ({x}, {y}) #{r:02x}{g:02x}{b:02x}")
                    continue
                outputs[route(spec, made, (r, g, b))].putpixel((x, y), (r, g, b, 255))
        require(not drift or drop_drift, f"{label}: {len(drift)} texel(s) changed in colours {part} does not hold "
                f"(drift), e.g. {'; '.join(drift[:8])}; repaint, or cut with --drop-drift to drop each")
        notes = [f"PORTRAIT_DRIFT: {label}: {where}: not a colour of {part}, dropped (--drop-drift)" for where in drift]
    files = []
    for (layer, layer_shape), image in zip(made, outputs):
        relative = f"{PARTS_DIR}/{source_name(layer, layer_shape)}.png"
        check_cut(spec, layer, image, relative)
        files.append(source / relative)
    for target in files:
        require(not target.exists(), f"{target} exists; a part is never overwritten (delete it first)")
    for note in notes:
        print(note)
    for target, image in zip(files, outputs):
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
        drawn = image.width * image.height - image.getchannel("A").histogram()[0]
        print(f"PORTRAIT_CUT: {target}: {drawn} texels")
    return files


def check(source: Path) -> None:
    spec = load_spec(source)
    _parts, mocked = load_parts(source, spec)
    painted = len(spec_sources(spec)) - len(mocked)
    print(f"PORTRAIT_PARTS_OK: {painted} painted, {len(mocked)} placeholder" + (
        f" ({', '.join(mocked)})" if mocked else ""))


def spec_sources(spec: dict) -> list[str]:
    return [source_name(layer, shape) for layer in LAYERS for shape in shapes_of(spec, layer)]


# --- the review sheet -----------------------------------------------------------------


def pick(provider: str, pane: str, slot: str) -> int:
    """PixelPeople.pick(): the first four bytes, big-endian, of SHA-256 over
    "herdstead.look/1␟provider␟pane␟slot"."""
    text = "\x1f".join((VARIATION_SCHEME, provider, pane, slot))
    return int.from_bytes(hashlib.sha256(text.encode()).digest()[:4], "big")


def look_of(spec: dict, provider: str, pane: str) -> dict[str, str]:
    """PixelPortraits.look_of() with nobody's saved looks: the pack's default, the
    provider's catalog look, the pane's variation, then the extras."""
    people = spec["_people"]
    look = dict(people["default_look"])
    catalog = json.loads(CATALOG.read_text())
    for agent in catalog.get("agents", []):
        if agent.get("id") == provider:
            for slot, value in agent.get("look", {}).items():
                if slot in look and value in people_build.options(people, slot):
                    look[slot] = value
    for slot, pool in people["variation"].items():
        if pane:
            look[slot] = pool[pick(provider, pane, slot) % len(pool)]
    for extra, info in spec["extras"].items():
        look[extra] = info["pool"][pick(provider, pane, PICK_PREFIX + extra) % len(info["pool"])] if pane else info[
            "default"]
    return look


def picture_of(spec: dict, parts: dict[str, Image.Image], look: dict[str, str], cache: dict) -> Image.Image:
    """A look composed from its cells, in the manifest's layer order."""
    by_name = {cell.name: cell for cell in cells(spec)}
    hidden = look.get("headwear") in hats(spec)[1]
    layered = {}
    for layer in LAYERS:
        info = spec["layers"][layer]
        name = layer
        if info["shape"] is not None:
            shape = look.get(info["shape"], NONE)
            if shape == NONE or shape not in shapes_of(spec, layer):
                continue
            name += f"_{shape}"
        if layer == "hair" and hidden:
            continue
        if info["colour"] is not None:
            name += f"_{look[info['colour']]}"
        if name not in cache:
            cell = by_name[name]
            cache[name] = recolour(parts[cell.source], spec, cell, f"{PARTS_DIR}/{cell.source}.png")
        layered[layer] = cache[name]
    return compose(spec, layered)


def window(spec: dict, portrait: Image.Image, edge: tuple[int, int, int], ground: tuple[int, int, int],
           ink: tuple[int, int, int]) -> Image.Image:
    """The HUD's window round a portrait: the cream ground, the portrait, a 1-unit
    frame in the state's colour over its edge, the corner mark's box outlined."""
    d = spec["density"]
    width, height = portrait.size
    framed = Image.new("RGBA", (width + 2 * d, height + 2 * d), (*ground, 255))
    framed.alpha_composite(portrait, (d, d))
    draw = ImageDraw.Draw(framed)
    for step in range(d):
        draw.rectangle([step, step, framed.width - 1 - step, framed.height - 1 - step], outline=(*edge, 255))
    mark = CORNER_MARK * d
    draw.rectangle([d, d, d + mark - 1, d + mark - 1], outline=(*ink, 255))
    return framed


def sheet(source: Path, out: Path, scale: int = 4) -> Path:
    """The review contact sheet (for eyes only, never an asset): (a) sheet2's
    twelve people, (b) every part and swatch on the default look, (c) 24 sample
    panes of claude, `scale` screen pixels per unit (the 4x captures' size)."""
    require(not out.exists() or (out.is_dir() and not any(out.iterdir())), f"{out} is not empty; pick another --out")
    spec = load_spec(source)
    parts, mocked = load_parts(source, spec)
    palette = json.loads(PACK.read_text())["palette"]
    ground, ink = rgb(palette["cream"]), rgb(palette["ink"])
    edges = [rgb(palette[key]) for _state, key in STATE_EDGES]
    default = look_of(spec, "", "")
    rows: list[tuple[str, list[tuple[str, dict[str, str]]]]] = []
    rows.append(("sheet2's people", [(f"#{index + 1}", dict(zip(LOOK_SLOTS + EXTRA_SLOTS, person)))
                                     for index, person in enumerate(SHEET2)]))
    variants = []
    for layer in LAYERS:
        info = spec["layers"][layer]
        if info["shape"] is not None:
            for shape in shapes_of(spec, layer):
                wanted = {**default, info["shape"]: shape}
                variants.append((shape, wanted))
    for slot in ("skin", "top", "hair_colour", "headwear_colour"):
        for swatch in spec["_people"]["slots"][slot]["swatches"]:
            wanted = {**default, slot: swatch}
            if slot == "headwear_colour":
                wanted["headwear"] = "cap"
            variants.append((swatch, wanted))
    rows.append(("every part and swatch on the default look", variants))
    rows.append((f"{SAMPLES} sample panes of {SAMPLE_PROVIDER}", [
        (f"p{index}", look_of(spec, SAMPLE_PROVIDER, SAMPLE_PANE.format(index))) for index in range(1, SAMPLES + 1)]))
    cache: dict = {}
    d = spec["density"]
    tile = (spec["canvas"][0] + 2) * d
    per_row, gap, label_height = 12, 2 * d, 12
    lines = []
    for title, looks in rows:
        lines.append((title, None))
        for start in range(0, len(looks), per_row):
            lines.append((None, looks[start:start + per_row]))
    canvas_height = sum(label_height if title else tile + gap + label_height for title, _looks in lines)
    texels = Image.new("RGBA", (per_row * (tile + gap) + gap, canvas_height + gap), (0x26, 0x36, 0x3b, 255))
    draw = ImageDraw.Draw(texels)
    y = gap
    count = 0
    for title, looks in lines:
        if title:
            draw.text((gap, y), title, fill=(*ground, 255))
            y += label_height
            continue
        for index, (name, look) in enumerate(looks):
            portrait = picture_of(spec, parts, look, cache)
            framed = window(spec, portrait, edges[count % len(edges)], ground, ink)
            x = gap + index * (tile + gap)
            texels.alpha_composite(framed, (x, y))
            draw.text((x, y + tile + 1), name[:14], fill=(*ground, 255))
            count += 1
        y += tile + gap + label_height
    out.mkdir(parents=True, exist_ok=True)
    target = out / "portrait-sheet.png"
    factor = max(1, scale // d)
    texels.resize((texels.width * factor, texels.height * factor), Image.Resampling.NEAREST).save(target)
    print(f"PORTRAIT_SHEET: {target} ({count} portraits, {scale} px per unit; {len(mocked)} part(s) still placeholders)")
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true", help="check every part under SOURCE/parts")
    parser.add_argument("--source", type=Path, default=SOURCE, help="the portraits source directory (default art/portraits)")
    commands = parser.add_subparsers(dest="command")
    shown = commands.add_parser("reference")
    shown.add_argument("--part", required=True, help="base, expression, hair, headwear, glasses, freckles, headphones")
    shown.add_argument("--out", type=Path, required=True, help="a new or empty directory")
    shown.add_argument("--with", dest="wear", default="", help="parts over the base, e.g. hair_long,face_smile")
    shown.add_argument("--scale", type=int, default=REFERENCE_SCALE)
    cutting = commands.add_parser("cut")
    cutting.add_argument("picture", type=Path, help="the pixelized picture (80x80)")
    cutting.add_argument("--part", required=True)
    cutting.add_argument("--shape", help="the option the picture draws (an expression, a hair style, a hat, glasses)")
    cutting.add_argument("--with", dest="wear", default="", help="the parts the reference wore (the base they add to)")
    cutting.add_argument("--drop-drift", action="store_true", help="drop and list texels in colours the part does not hold")
    review = commands.add_parser("sheet")
    review.add_argument("--out", type=Path, required=True, help="a new or empty directory")
    review.add_argument("--scale", type=int, default=4, help="screen pixels per unit (default 4, the 4x captures)")
    args = parser.parse_args()
    try:
        if args.command == "reference":
            reference(args.source, args.part, args.out, [w for w in args.wear.split(",") if w], args.scale)
        elif args.command == "cut":
            cut(args.picture, args.source, args.part, args.shape, args.drop_drift, [w for w in args.wear.split(",") if w])
        elif args.command == "sheet":
            sheet(args.source, args.out, args.scale)
        elif args.check:
            check(args.source)
        else:
            parser.error("say reference, cut, sheet or --check")
    except (PortraitError, people_build.PeopleError) as error:
        print(f"PORTRAIT_PARTS_FAILED: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
