"""Build the pixel people: art/pixel_people/people.json -> assets/pixel_people/.

The pixel people are small frame-animated figures drawn at density 1: one texture
pixel is one world unit, sampled NEAREST and only ever magnified by a whole
number. A figure is six layers, bottom to top ``legs``, ``top``, ``body`` (skin,
eyes and whatever the hands hold), ``glasses``, ``hair`` and ``headwear``, and
every layer is one horizontal strip per facing (``front``, ``back``, ``side``)
holding every frame of every track, tracks in contract order. A facing a track
does not draw leaves that track's columns transparent, so one frame index means
the same moment in every strip and one AnimationPlayer key drives them all.

What a figure wears is chosen per *slot* (people.json ``slots``). A shape slot
picks which source strip a layer draws (``hair_style``, ``headwear``,
``glasses``; they may be ``none``); a colour slot picks the target ramp of one
key role (``skin``, ``hair_colour``, ``top``, ``legs``, ``headwear_colour``).
Each layer has at most one of each, so the sheets add up instead of
multiplying: per facing, one product strip per (shape, swatch) of every layer.

Sources are drawn in *key colours*: a three-tone ramp per role (skin, top,
legs, hair, hat) and a few fixed colours (ink, eyes, shoes, paper, cup, lens)
that pass through unchanged. The build recolours every source into one strip
per swatch of its layer's colour slot, by exact colour substitution with the
ambiguity and unmapped-colour checks of ``tools/recolour.py``
(``remap_table`` and ``repaint``, imported, not copied):

* ``<facing>/legs.png``, ``top.png``, ``body.png`` -> ``legs_<swatch>``, ``top_<swatch>``, ``body_<skin>``
* ``<facing>/glasses_<shape>.png``                 -> ``glasses_<shape>`` (fixed colours only)
* ``<facing>/hair_<shape>.png``                    -> ``hair_<shape>_<colour>``
* ``<facing>/headwear_<shape>.png``                -> ``headwear_<shape>_<colour>``

The product strips of one facing ship packed into one sheet,
``<facing>.png``, stacked in the product manifest's ``strips`` order with no
gutter. Packing is a build step (invariant 6 forbids repacking at runtime, not
here): every layer of every person then draws from one texture, so a person's
six layers batch into one draw call instead of six (measured, docs/ASSET_SPEC.md).

When ``art/pixel_people/<facing>/<source>.png`` exists it is checked and used.
When it does not, a placeholder is drawn from the contract in the key colours,
the same picture a painter would hand in, and listed in the product manifest's
``mock_files``: that list is the artist's to-do. Either way the source goes
through the same check and the same recolour.

The product manifest is ``people_manifest.json``, never ``manifest.json``: every
``assets/*/manifest.json`` is a theme to the Makefile, tools/check_packs.gd and
the office's theme list.

Run from the repository root::

    .venv/bin/python tools/build_pixel_people.py
    .venv/bin/python tools/build_pixel_people.py --source DIR --output DIR

A broken contract or source stops the build with ``PEOPLE_BUILD_FAILED:`` naming
the file and the rule, and a nonzero exit.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from build_assets import prune_unreferenced, report_pruned, save_if_pixels_moved
from recolour import remap_table, repaint


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art" / "pixel_people"
OUTPUT = ROOT / "assets" / "pixel_people"
SPEC_NAME = "people.json"
# Not manifest.json: every assets/*/manifest.json is a theme to the Makefile,
# tools/check_packs.gd and the office's theme list.
PRODUCT_NAME = "people_manifest.json"
SCHEMA_VERSION = 2
# Texture pixels (texels) per unit the family may be drawn at. Geometry is in
# units at every density; a cell of the rig is a density x density block.
DENSITIES = (1, 2)
# The layers the prefab draws, bottom to top: scenes/people/pixel_person.tscn has
# one Sprite2D for each.
LAYERS = ("legs", "top", "body", "glasses", "hair", "headwear")
# The layers every frame of a facing a track draws must show: the figure itself.
BASE_LAYERS = ("legs", "top", "body")
# The slots a look is made of, in the order PixelPeople.SLOTS and AvatarLook keep.
SLOTS = ("skin", "hair_style", "hair_colour", "top", "legs", "headwear", "headwear_colour", "glasses")
NONE = "none"
CONTEXTS = ("stand", "desk")
STATES = ("idle", "done", "unknown", "working", "blocked", "starting")
ROLES = ("skin", "top", "legs", "hair", "hat")
TONES = 3
# A figure never needs more frames than this in one track and facing.
MAX_FRAMES = 8
SPEC_KEYS = {"schema_version", "density", "ring_texels", "raised_hand", "frame_size", "pivot", "facings", "side_faces",
             "layers", "tracks", "state_tracks", "keys", "fixed", "slots", "default_look", "variation"}
TRACK_KEYS = {"facings", "durations", "loop"}
COLOUR_SLOT_KEYS = {"layer", "role", "swatches"}
SHAPE_SLOT_KEYS = {"layer", "shapes", "none"}
SHAPE_KEYS = {"hides_hair"}
# The raised hands the rig can draw (people.json's optional `raised_hand`, read
# only here): the straight arm, a stick up past the head; and the bent one,
# the upper arm out from the shoulder, the forearm straight up, a sleeve cuff
# and a mitten with its thumb.
RAISED_HANDS = ("straight", "bent")
STRAIGHT_HAND = "straight"
# The optional fixed colour of each eye's catchlight (Painter).
CATCHLIGHT = "catchlight"
# The fixed colours only the rig paints, in its own eye cells: never in a skin.
EYE_COLOURS = ("eye", CATCHLIGHT)
# Fixed colours the placeholder paints with.
PLACEHOLDER_FIXED = ("ink", "eye", "shoe", "shoe_light", "paper", "paper_line", "cup", "cup_shade", "coffee", "frame")
# The facing every track draws and every other falls back to.
FRONT = "front"
SIDE = "side"


class PeopleError(ValueError):
    """The contract or a source sheet is broken; the message names the file and the rule."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PeopleError(message)


# --- the contract -----------------------------------------------------------------


def safe_name(value, label: str) -> None:
    require(isinstance(value, str) and value and value.isascii()
            and all(c.isalnum() or c == "_" for c in value), f"{label}: {value!r} must be a safe name")


def names(value, label: str) -> None:
    require(isinstance(value, list) and value, f"{label} must be a non-empty list of names")
    for item in value:
        safe_name(item, label)
    require(len(value) == len(set(value)), f"{label} must not repeat a name")


def known_keys(value, allowed, label: str) -> None:
    require(isinstance(value, dict), f"{label} must be an object")
    unknown = set(value) - set(allowed)
    require(not unknown, f"{label}: unknown field(s) {sorted(unknown)}")


def whole_pair(value, label: str) -> tuple[int, int]:
    require(isinstance(value, list) and len(value) == 2 and all(type(v) is int and v >= 0 for v in value),
            f"{label} must be an [x, y] pair of whole, non-negative numbers; found {value!r}")
    return (value[0], value[1])


def hex_colour(value, label: str) -> str:
    require(isinstance(value, str) and len(value) == 6 and all(c in "0123456789abcdef" for c in value),
            f"{label} must be six lowercase hex digits; found {value!r}")
    return value


def ramp(value, label: str) -> list[str]:
    require(isinstance(value, list) and len(value) == TONES, f"{label} must be a ramp of {TONES} colours, light to dark")
    return [hex_colour(colour, f"{label}[{index}]") for index, colour in enumerate(value)]


def finite_duration(value) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def load_spec(source: Path) -> dict:
    path = source / SPEC_NAME
    require(path.is_file(), f"{path}: no people contract")
    try:
        spec = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        raise PeopleError(f"{path}: not JSON ({error})") from error
    require(isinstance(spec, dict), f"{path}: not a JSON object")
    validate(spec, path)
    return spec


def validate(spec: dict, where: Path) -> None:
    """Everything about people.json that can be known without a picture."""
    known_keys(spec, SPEC_KEYS, str(where))
    require(type(spec.get("schema_version")) is int and spec["schema_version"] == SCHEMA_VERSION,
            f"{where}: schema_version must be {SCHEMA_VERSION}")
    require(type(spec.get("density")) is int and spec["density"] in DENSITIES,
            f"{where}: density must be one of {list(DENSITIES)}: texture pixels per unit, the same in x and y")
    # Optional, and only the rig reads it (the product manifest does not carry
    # it): how many texels of each ring cell are ink. Absent is the whole cell.
    if "ring_texels" in spec:
        require(type(spec["ring_texels"]) is int and 1 <= spec["ring_texels"] <= spec["density"],
                f"{where}: ring_texels must be a whole number from 1 to the density ({spec['density']}): how many "
                f"texels of each ring cell are ink; found {spec['ring_texels']!r}")
    # Optional, and only the rig reads it too: which raised hand a blocked
    # figure draws. Absent is the straight arm.
    if "raised_hand" in spec:
        require(isinstance(spec["raised_hand"], str) and spec["raised_hand"] in RAISED_HANDS,
                f"{where}: raised_hand must be one of {list(RAISED_HANDS)}: the arm a blocked figure raises; "
                f"found {spec['raised_hand']!r}")
    width, height = whole_pair(spec.get("frame_size"), f"{where}: frame_size")
    require(width > 0 and height > 0, f"{where}: frame_size must be positive")
    pivot_x, pivot_y = whole_pair(spec.get("pivot"), f"{where}: pivot")
    require(pivot_y <= height, f"{where}: pivot must lie on the frame")
    # flip_h mirrors a frame about its centre, so a left-facing figure keeps its
    # feet on the origin only when the origin is that centre.
    require(pivot_x * 2 == width, f"{where}: pivot x must be the frame's centre ({width / 2:g}), or a mirrored figure moves")
    facings = spec.get("facings")
    names(facings, f"{where}: facings")
    require(FRONT in facings, f"{where}: facings must include {FRONT}, the facing every track falls back to")
    require(spec.get("side_faces") in ("right", "left") and SIDE in facings,
            f"{where}: side_faces must say which way the {SIDE} facing is drawn (right or left)")
    require(spec.get("layers") == list(LAYERS), f"{where}: layers must be {list(LAYERS)}, the prefab's sprites")
    validate_tracks(spec, where)
    validate_colours(spec, where)
    validate_slots(spec, where)
    validate_looks(spec, where)


def validate_tracks(spec: dict, where: Path) -> None:
    tracks = spec.get("tracks")
    require(isinstance(tracks, dict) and tracks, f"{where}: tracks must name at least one track")
    for track, info in tracks.items():
        label = f"{where}: tracks.{track}"
        safe_name(track, label)
        known_keys(info, TRACK_KEYS, label)
        facings = info.get("facings")
        names(facings, f"{label}.facings")
        require(all(facing in spec["facings"] for facing in facings), f"{label}.facings names an unknown facing")
        require(facings[0] == FRONT, f"{label}.facings must start with {FRONT}, the facing it falls back to")
        durations = info.get("durations")
        require(isinstance(durations, list) and 0 < len(durations) <= MAX_FRAMES,
                f"{label}.durations must list 1 to {MAX_FRAMES} frames")
        require(all(finite_duration(value) for value in durations),
                f"{label}.durations must be finite, positive seconds; found {durations!r}")
        require(isinstance(info.get("loop"), bool), f"{label}.loop must be true or false")
    mapped = spec.get("state_tracks")
    known_keys(mapped, CONTEXTS, f"{where}: state_tracks")
    for context in CONTEXTS:
        states = mapped.get(context)
        label = f"{where}: state_tracks.{context}"
        known_keys(states, STATES, label)
        require(set(states) == set(STATES), f"{label} must map every state: {', '.join(STATES)}")
        for state, track in states.items():
            require(isinstance(track, str) and track in tracks, f"{label}.{state} names no track: {track!r}")


def validate_colours(spec: dict, where: Path) -> None:
    keys = spec.get("keys")
    known_keys(keys, ROLES, f"{where}: keys")
    require(set(keys) == set(ROLES), f"{where}: keys must give a ramp for every role: {', '.join(ROLES)}")
    for role in ROLES:
        ramp(keys[role], f"{where}: keys.{role}")
    fixed = spec.get("fixed")
    require(isinstance(fixed, dict), f"{where}: fixed must be an object")
    for name in PLACEHOLDER_FIXED:
        require(name in fixed, f"{where}: fixed must hold {name}, which the placeholder paints with")
    for name, colour in fixed.items():
        safe_name(name, f"{where}: fixed")
        hex_colour(colour, f"{where}: fixed.{name}")
    # One colour, one meaning: the recolour is a lookup, so a key shared by two
    # roles (or by a role and a fixed colour) cannot be told apart.
    table(source_palette(spec), {})


def validate_slots(spec: dict, where: Path) -> None:
    """Every slot of SLOTS and no other; each a shape slot (a layer's drawings) or
    a colour slot (a role's ramps); every layer at most one of each; every role
    coloured by exactly one slot."""
    slots = spec.get("slots")
    require(isinstance(slots, dict), f"{where}: slots must be an object")
    require(list(slots) == list(SLOTS), f"{where}: slots must be exactly {list(SLOTS)}, in that order")
    shaped, coloured, roles = {}, {}, {}
    for slot, info in slots.items():
        label = f"{where}: slots.{slot}"
        require(isinstance(info, dict), f"{label} must be an object")
        layer = info.get("layer")
        require(layer in LAYERS, f"{label}.layer must be one of {list(LAYERS)}; found {layer!r}")
        if "role" in info:
            known_keys(info, COLOUR_SLOT_KEYS, label)
            role = info["role"]
            require(role in ROLES, f"{label}.role must be one of {list(ROLES)}; found {role!r}")
            require(role not in roles, f"{label}: role {role} is already coloured by {roles.get(role)}")
            require(layer not in coloured, f"{label}: layer {layer} already has a colour slot ({coloured.get(layer)})")
            roles[role], coloured[layer] = slot, slot
            swatches = info.get("swatches")
            require(isinstance(swatches, dict) and swatches, f"{label}.swatches must name at least one swatch")
            for swatch, colours in swatches.items():
                safe_name(swatch, f"{label}.swatches")
                require(swatch != NONE, f"{label}: a colour slot has no {NONE}")
                ramp(colours, f"{label}.swatches.{swatch}")
        else:
            known_keys(info, SHAPE_SLOT_KEYS, label)
            require(layer not in BASE_LAYERS, f"{label}: {layer} is one drawing, not a choice of shapes")
            require(layer not in shaped, f"{label}: layer {layer} already has a shape slot ({shaped.get(layer)})")
            shaped[layer] = slot
            shapes = info.get("shapes")
            require(isinstance(shapes, dict) and shapes, f"{label}.shapes must name at least one shape")
            for shape, flags in shapes.items():
                safe_name(shape, f"{label}.shapes")
                require(shape != NONE, f"{label}: {NONE} is not a shape; say \"none\": true")
                known_keys(flags, SHAPE_KEYS, f"{label}.shapes.{shape}")
                if "hides_hair" in flags:
                    require(isinstance(flags["hides_hair"], bool), f"{label}.shapes.{shape}.hides_hair must be true or false")
                    require(layer == "headwear", f"{label}.shapes.{shape}: only headwear hides the hair")
            require(isinstance(info.get("none", False), bool), f"{label}.none must be true or false")
    missing = [role for role in ROLES if role not in roles]
    require(not missing, f"{where}: slots colour no role {missing}: every key role needs a colour slot")
    for layer in LAYERS:
        if layer not in BASE_LAYERS:
            require(layer in shaped, f"{where}: layer {layer} has no shape slot")


def options(spec: dict, slot: str) -> list[str]:
    """What a slot can be set to: its swatches or shapes, and none where allowed."""
    info = spec["slots"][slot]
    found = list(info["swatches"]) if "role" in info else list(info["shapes"])
    if info.get("none", False):
        found.append(NONE)
    return found


def validate_looks(spec: dict, where: Path) -> None:
    default = spec.get("default_look")
    require(isinstance(default, dict) and list(default) == list(SLOTS),
            f"{where}: default_look must set every slot, in the order of slots")
    for slot, value in default.items():
        require(value in options(spec, slot), f"{where}: default_look.{slot} is {value!r}, which the slot does not draw")
    variation = spec.get("variation")
    known_keys(variation, SLOTS, f"{where}: variation")
    for slot, pool in variation.items():
        label = f"{where}: variation.{slot}"
        # A repeat is a weight, so a pool may name an option twice.
        require(isinstance(pool, list) and pool, f"{label} must be a non-empty list of options")
        for value in pool:
            require(value in options(spec, slot), f"{label} names {value!r}, which the slot does not draw")


# --- palette and recolour ---------------------------------------------------------


def key_name(role: str, tone: int) -> str:
    return f"{role}.{tone}"


def source_palette(spec: dict) -> dict[str, str]:
    """Every colour a source may hold, by name: each role's key ramp, then the fixed colours."""
    palette = {key_name(role, tone): colour for role in ROLES for tone, colour in enumerate(spec["keys"][role])}
    palette.update({f"fixed.{name}": colour for name, colour in spec["fixed"].items()})
    return palette


def table(palette: dict[str, str], overrides: dict[str, str]) -> dict:
    """recolour's remap table: old RGB -> new RGB, refusing an ambiguous palette."""
    try:
        return remap_table(palette, overrides)
    except SystemExit as error:
        raise PeopleError(str(error.code).removeprefix("recolour: ")) from error


def shape_slot(spec: dict, layer: str) -> str | None:
    return next((slot for slot, info in spec["slots"].items() if info["layer"] == layer and "shapes" in info), None)


def colour_slot(spec: dict, layer: str) -> str | None:
    return next((slot for slot, info in spec["slots"].items() if info["layer"] == layer and "role" in info), None)


@dataclass(frozen=True)
class Product:
    """One shipped strip: its name, the source strip it is recoloured from, and
    the target ramp of the role it maps (a layer without a colour slot maps
    none: only fixed colours may be in it)."""

    name: str
    sheet: str
    targets: tuple[tuple[str, tuple[str, ...]], ...]


def source_sheets(spec: dict) -> list[str]:
    """Every source strip a facing has, layer by layer: one per shape."""
    result = []
    for layer in LAYERS:
        slot = shape_slot(spec, layer)
        result += [layer] if slot is None else [f"{layer}_{shape}" for shape in spec["slots"][slot]["shapes"]]
    return result


def products(spec: dict) -> list[Product]:
    """Every strip the build ships per facing, in packing order: layer by layer,
    one per shape (or the layer's one drawing) and swatch of its colour slot."""
    result = []
    for layer in LAYERS:
        shapes, colours = shape_slot(spec, layer), colour_slot(spec, layer)
        sheets = [layer] if shapes is None else [f"{layer}_{shape}" for shape in spec["slots"][shapes]["shapes"]]
        for sheet in sheets:
            if colours is None:
                result.append(Product(sheet, sheet, ()))
                continue
            info = spec["slots"][colours]
            for swatch, colour in info["swatches"].items():
                result.append(Product(f"{sheet}_{swatch}", sheet, ((info["role"], tuple(colour)),)))
    return result


def recipe(spec: dict, product: Product) -> tuple[dict[str, str], dict[str, str]]:
    """The palette a product's source may hold (its role's keys and the fixed
    colours) and the target of each key it maps."""
    fixed = {name: colour for name, colour in source_palette(spec).items() if name.startswith("fixed.")}
    palette, overrides = dict(fixed), {}
    for role, targets in product.targets:
        for tone, colour in enumerate(spec["keys"][role]):
            palette[key_name(role, tone)] = colour
            overrides[key_name(role, tone)] = targets[tone]
    return palette, overrides


def rgb(colour: str) -> tuple[int, int, int]:
    return tuple(bytes.fromhex(colour))


def recolour(image: Image.Image, spec: dict, product: Product, label: str) -> Image.Image:
    """The product: every key colour substituted by its target, pixel for pixel."""
    palette, overrides = recipe(spec, product)
    painted, foreign = repaint(image, table(palette, overrides), label, keep_foreign=True)
    require(not foreign, f"{label}: {product.name} maps no colour for "
            + ", ".join("#%02x%02x%02x" % colour for colour in sorted(foreign)))
    return painted


# --- the layout -------------------------------------------------------------------


def starts(spec: dict) -> dict[str, int]:
    """Each track's first column; every facing's strip shares the layout."""
    result, column = {}, 0
    for track, info in spec["tracks"].items():
        result[track] = column
        column += len(info["durations"])
    return result


def column_count(spec: dict) -> int:
    return sum(len(info["durations"]) for info in spec["tracks"].values())


def frame_texels(spec: dict) -> tuple[int, int]:
    """One frame's size in texels: the frame in units times the density."""
    width, height = spec["frame_size"]
    return (width * spec["density"], height * spec["density"])


def strip_size(spec: dict) -> tuple[int, int]:
    """One strip's size in texels: every frame of every track, side by side."""
    width, height = frame_texels(spec)
    return (width * column_count(spec), height)


def source_files(spec: dict) -> list[tuple[str, str, str]]:
    """(relative path, facing, sheet) of every source a complete family has."""
    return [(f"{facing}/{sheet}.png", facing, sheet) for facing in spec["facings"] for sheet in source_sheets(spec)]


def sheet_files(spec: dict) -> list[str]:
    """The packed sheets the family ships, one per facing."""
    return [f"{facing}.png" for facing in spec["facings"]]


def layer_of(sheet: str) -> str:
    return sheet.split("_", 1)[0]


def allowed_colours(spec: dict, sheet: str) -> set[tuple[int, int, int]]:
    """What a source strip may hold: its layer's role keys and the fixed colours."""
    slot = colour_slot(spec, layer_of(sheet))
    allowed = {rgb(colour) for colour in spec["fixed"].values()}
    if slot is not None:
        allowed |= {rgb(colour) for colour in spec["keys"][spec["slots"][slot]["role"]]}
    return allowed


def check_source(image: Image.Image, spec: dict, facing: str, sheet: str, relative: str) -> None:
    """The pixel contract of one source strip: its size, hard alpha, only its own
    key and fixed colours, a drawn frame for every track in this facing (the
    figure's own layers) and nothing in the columns of a track that does not
    face this way."""
    expected = strip_size(spec)
    width, height = frame_texels(spec)
    require(image.size == expected, f"{relative}: {image.size} is not the {expected[0]}x{expected[1]} strip "
            f"({column_count(spec)} frames of {width}x{height})")
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    allowed = allowed_colours(spec, sheet)
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            require(a == 255, f"{relative}: pixel ({x}, {y}) is semi-transparent (alpha {a}); edges are 0 or 255")
            require((r, g, b) in allowed, f"{relative}: pixel ({x}, {y}) is #{r:02x}{g:02x}{b:02x}, which is not a key "
                    f"or fixed colour of {sheet}")
    first = starts(spec)
    for track, info in spec["tracks"].items():
        for frame in range(len(info["durations"])):
            left = (first[track] + frame) * width
            drawn = rgba.crop((left, 0, left + width, height)).getchannel("A").getbbox() is not None
            if facing in info["facings"]:
                require(drawn or layer_of(sheet) not in BASE_LAYERS,
                        f"{relative}: {track} frame {frame} faces {facing} but is empty")
            else:
                require(not drawn, f"{relative}: {track} does not face {facing}, so frame {frame} must be empty")


# The eye against the skin around it: the WCAG 2.1 non-text contrast minimum
# (SC 1.4.11, graphics needed to understand the content). An eye is a 1x2 mark
# at 1x, which only gets smaller in a viewer's eye than any UI graphic, so the
# floor for "can the face be read" is at least this. A skin swatch below it is
# not refused (the swatch is the palette's choice); the build reports it. The
# answer is the rig's catchlight, a light texel in every eye (docs/ASSET_SPEC.md).
EYE_CONTRAST_MIN = 3.0


def luminance(colour: str) -> float:
    """WCAG 2.1 relative luminance of a six-digit hex colour."""
    def linear(channel: int) -> float:
        value = channel / 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    red, green, blue = rgb(colour)
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)


def contrast(first: str, second: str) -> float:
    """WCAG 2.1 contrast ratio of two colours, 1 to 21."""
    lighter, darker = sorted((luminance(first), luminance(second)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def eye_contrast(spec: dict) -> list[tuple[str, float]]:
    """(skin swatch, contrast of the fixed eye colour against that swatch's mid tone), in swatch order."""
    eye = spec["fixed"]["eye"]
    return [(swatch, contrast(eye, ramp_[1])) for swatch, ramp_ in spec["slots"]["skin"]["swatches"].items()]


def check_brims(spec: dict, sources: dict) -> None:
    """A hat covers the hair above its brim: in every frame, every hair texel
    above the lowest unit row the headwear draws is under a headwear texel. A hood
    (``hides_hair``) hides the hair layer instead, so it is not held to this."""
    width, height = frame_texels(spec)
    hats = [shape for shape, flags in spec["slots"]["headwear"]["shapes"].items() if not flags.get("hides_hair", False)]
    styles = list(spec["slots"]["hair_style"]["shapes"])
    for facing in spec["facings"]:
        for column in range(column_count(spec)):
            box = (column * width, 0, (column + 1) * width, height)
            for hat in hats:
                cap = sources[(facing, f"headwear_{hat}")].crop(box).getchannel("A")
                bounds = cap.getbbox()
                if bounds is None:
                    continue
                # The brim is the lowest unit row the hat draws: its top texel row.
                brim = (bounds[3] - 1) // spec["density"] * spec["density"]
                covered = cap.load()
                for style in styles:
                    hair = sources[(facing, f"hair_{style}")].crop(box).getchannel("A").load()
                    for y in range(brim):
                        for x in range(width):
                            require(not hair[x, y] or covered[x, y],
                                    f"{facing}/hair_{style}.png: frame {column} pixel ({x}, {y}) shows above the brim "
                                    f"of {facing}/headwear_{hat}.png (row {brim}); a hat covers the hair above its brim")


def from_source(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        return opened.convert("RGBA")


# --- the placeholder ----------------------------------------------------------------
# A figure is painted as outlined stickers from back to front: each part is a set
# of cells, each cell a letter; the part is filled, then ringed in ink (every
# empty 4-neighbour of a cell; people.json's ring_texels says how many of a ring
# cell's texels, from its outer side, are ink). A later part's ring cuts into an
# earlier part, which is what draws the seams (chin, belt, an arm over the torso). Ramp letters take a
# tone lit from the top-left: a cell on the part's top or left edge is light, one
# on its bottom or right edge dark, the rest mid.
#
# The figure is painted once, whole, and each final pixel then belongs to exactly
# one layer: the layer of the part that painted it last (a ring pixel belongs to
# the part whose ring it is). The legs, top and body layers therefore never
# overlap, and together they are the one painted figure pixel for pixel, whatever
# order the prefab draws them in.

Cell = tuple[int, int]
Cells = dict[Cell, str]
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
RAMP_LETTERS = {"s": "skin", "t": "top", "l": "legs", "h": "hair", "a": "hat"}
# A sleeve's cuff: a row of the top in its lightest tone whatever its
# neighbours, on the same surface as the sleeve it ends (the bent raised hand).
CUFF = "u"
SURFACES = {CUFF: "t"}
FIXED_LETTERS = {"k": "ink", "e": "eye", "o": "shoe", "O": "shoe_light", "p": "paper", "P": "paper_line",
                 "c": "cup", "C": "cup_shade", "f": "coffee", "g": "lens", "r": "frame"}
# Details painted on a surface: they neither break its shading nor get a ring.
DETAILS = {"e", "k", "P", "f"}
# Which layer a painted letter belongs to.
LETTER_LAYERS = {"l": "legs", "o": "legs", "O": "legs", "t": "top", CUFF: "top", "s": "body", "e": "body", "k": "body",
                 "p": "body", "P": "body", "c": "body", "C": "body", "f": "body", "h": "hair", "a": "headwear",
                 "g": "glasses", "r": "glasses"}


def cells_of(rows, x: int, y: int) -> Cells:
    """An ASCII part: '.' is empty, a letter is a cell; its top-left lands on (x, y)."""
    return {(x + column, y + row): letter for row, line in enumerate(rows) for column, letter in enumerate(line)
            if letter != "."}


def block(left: int, top: int, right: int, bottom: int, letter: str) -> Cells:
    """Every cell of an inclusive rectangle."""
    return {(x, y): letter for y in range(top, bottom + 1) for x in range(left, right + 1)}


def limb(points, letter: str, width: int = 2) -> Cells:
    """A limb `width` cells thick along a polyline of top-left corners."""
    cells: Cells = {}
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for step in range(steps + 1):
            x = x0 + round((x1 - x0) * step / steps)
            y = y0 + round((y1 - y0) * step / steps)
            cells.update(block(x, y, x + width - 1, y + width - 1, letter))
    return cells


def mirrored(cells: Cells, width: int) -> Cells:
    """The same part on the other side of the frame's centre line."""
    return {(width - 1 - x, y): letter for (x, y), letter in cells.items()}


@dataclass(frozen=True)
class SkinAt:
    """A part's skin placed on a frame: its picture (texels, RGBA), the cell
    its top-left texel lands on (the top-left of the part's cell envelope) and
    the layer it colours: only the part's cells of that layer take it."""

    image: Image.Image
    cell: Cell
    layer: str


class Painter:
    """One frame, painted in key and fixed colours in texels: a cell is a
    density x density block of texels. Every texel remembers the layer of the
    part that painted it last."""

    def __init__(self, spec: dict, ring_texels: int | None = None):
        self.spec = spec
        self.density = spec["density"]
        self.width, self.height = frame_texels(spec)
        # How many texels of each ring cell, counted from its outer side, are
        # ink: asked for here, else people.json's ring_texels, else the whole
        # cell. The whole cell keeps the figure at any density the density-1
        # one scaled by NEAREST. A thinner ring (ring_cells) still ends on the
        # ring cell's outer side, so the figure keeps its envelope, its feet
        # and the offsets the office measured on it (docs/ASSET_SPEC.md, "Pixel people").
        chosen = spec.get("ring_texels", self.density) if ring_texels is None else ring_texels
        require(type(chosen) is int and 1 <= chosen <= self.density,
                f"a ring is 1 to {self.density} texels thick; asked for {chosen!r}")
        self.ring_texels = chosen
        self.pixels: dict[Cell, tuple[int, int, int]] = {}
        self.owners: dict[Cell, str] = {}
        # The texels the rig painted as an eye (its own `e` cells), which a
        # thin ring's corner ink never covers; a skin's eye-coloured texel is
        # not one of them.
        self.eyes: set[Cell] = set()
        self.ink = rgb(spec["fixed"]["ink"])
        # Each eye's catchlight: its top-left texel, lit like every other part
        # from the top left. Only when people.json names the colour, and only
        # at density 2 and up: at density 1 an eye is two texels.
        catch = spec["fixed"].get(CATCHLIGHT)
        self.catchlight = rgb(catch) if catch is not None and self.density >= 2 else None

    def fixed(self, name: str) -> tuple[int, int, int]:
        require(name in self.spec["fixed"], f"the placeholder needs a fixed colour named {name}")
        return rgb(self.spec["fixed"][name])

    def texels(self, cell: Cell) -> list[Cell]:
        """The texels of one cell, row by row."""
        d = self.density
        return [(cell[0] * d + i, cell[1] * d + j) for j in range(d) for i in range(d)]

    def edge(self, cell: Cell, toward: Cell, count: int) -> list[Cell]:
        """The `count` texels of `cell` next to its side facing the neighbour
        `toward` (one of its 4-neighbours)."""
        d, dx, dy = self.density, toward[0] - cell[0], toward[1] - cell[1]
        near = range(d - count, d) if (dx > 0 or dy > 0) else range(count)
        return [(i, j) for (i, j) in self.texels(cell)
                if (i - cell[0] * d if dx else j - cell[1] * d) in near]

    def stamp(self, cells: Cells, far: bool = False, ring: bool = True, skin: SkinAt | None = None) -> None:
        """Fill `cells`, then ring them in ink; a far part is a tone darker. A
        skin, where it is opaque, gives a fill texel its colour instead of the
        tone, on the part's cells of the skin's layer; never on a detail cell
        (the eyes), which the rig paints over it. The ring's texels are none of
        the part's, so the order only matters to a ring thinner than a cell,
        which takes the colours the fill (and the skin) left."""
        self.fill(cells, far, skin)
        if ring:
            self.ring_cells(cells)

    def ring_cells(self, cells: Cells) -> None:
        """Ring `cells`: every empty 4-neighbour of a cell is a ring cell, and
        the ink is its `ring_texels` texels on the side away from the part. The
        texels nearer the part (none when the ring is the whole cell) take the
        colour and layer of the part texel across the edge, so the part grows
        by what the ink gives up and the outline stays where it was. Where two
        such texels meet round a convex corner, the corner texel between them
        (in a cell the whole ring never paints) is ink too, or the fill would
        touch the air or run into the part below there; never over an eye,
        which always shows (a cup at the mouth sits diagonally next to one)."""
        keep = self.density - self.ring_texels
        grown: dict[Cell, Cell] = {}
        ringed: set[Cell] = set()
        for (x, y), _letter in cells.items():
            for dx, dy in N4:
                around = (x + dx, y + dy)
                if around in cells:
                    continue
                ringed.add(around)
                for texel in self.edge(around, (x, y), keep):
                    # The part texel across the edge, on the same row or column.
                    across = (x * self.density + (self.density - 1 if dx > 0 else 0) if dx else texel[0],
                              y * self.density + (self.density - 1 if dy > 0 else 0) if dy else texel[1])
                    grown.setdefault(texel, across)
        for (x, y), letter in cells.items():
            for dx, dy in N4:
                if (x + dx, y + dy) not in cells:
                    for texel in self.texels((x + dx, y + dy)):
                        if texel not in grown:
                            self.pixels[texel] = self.ink
                            self.owners[texel] = LETTER_LAYERS[letter]
        for texel, across in grown.items():
            self.pixels[texel] = self.pixels[across]
            self.owners[texel] = self.owners[across]
        d, eyes = self.density, {self.fixed("eye")} | ({self.catchlight} if self.catchlight else set())
        for texel in grown:
            for dx, dy in N4:
                corner = (texel[0] + dx, texel[1] + dy)
                cell = (corner[0] // d, corner[1] // d)
                eye = corner in self.eyes and self.pixels.get(corner) in eyes
                if cell not in cells and cell not in ringed and not eye:
                    self.pixels[corner] = self.ink
                    self.owners[corner] = self.owners[texel]

    def fill(self, cells: Cells, far: bool, skin: SkinAt | None) -> None:
        skinned = skin.image.load() if skin is not None else None
        for cell, letter in cells.items():
            colour = self.colour(cell, letter, cells, far)
            # The top cell of an eye carries its catchlight in its top-left texel.
            lit = self.catchlight is not None and letter == "e" and cells.get((cell[0], cell[1] - 1)) != "e"
            for texel in self.texels(cell):
                self.pixels[texel] = self.catchlight if lit and texel == self.texels(cell)[0] else colour
                self.owners[texel] = LETTER_LAYERS[letter]
                if letter == "e":
                    self.eyes.add(texel)
                if skinned is None or letter in DETAILS or LETTER_LAYERS[letter] != skin.layer:
                    continue
                x, y = texel[0] - skin.cell[0] * self.density, texel[1] - skin.cell[1] * self.density
                if 0 <= x < skin.image.width and 0 <= y < skin.image.height and skinned[x, y][3]:
                    self.pixels[texel] = skinned[x, y][:3]

    def colour(self, cell: Cell, letter: str, cells: Cells, far: bool) -> tuple[int, int, int]:
        if letter in FIXED_LETTERS:
            return self.fixed(FIXED_LETTERS[letter])
        if letter == CUFF:
            return rgb(self.spec["keys"]["top"][min(TONES - 1, int(far))])
        role = RAMP_LETTERS[letter]
        x, y = cell
        surface = SURFACES.get(letter, letter)
        # A shape layer is drawn on its own, so its tones never read another
        # layer's cells. A cuff is the sleeve's own surface.
        def inside(other: Cell) -> bool:
            neighbour = cells.get(other)
            return SURFACES.get(neighbour, neighbour) == surface or neighbour in DETAILS

        lit = (not inside((x, y - 1))) + (not inside((x - 1, y)))
        shade = (not inside((x, y + 1))) + (not inside((x + 1, y)))
        tone = 0 if lit > shade else 2 if shade > lit else 1
        if far:
            tone = min(TONES - 1, tone + 1)
        return rgb(self.spec["keys"][role][tone])

    def image(self, layer: str | None = None) -> Image.Image:
        """The frame, or only the pixels `layer` owns."""
        frame = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 0))
        for cell, colour in self.pixels.items():
            x, y = cell
            if (layer is None or self.owners[cell] == layer) and 0 <= x < self.width and 0 <= y < self.height:
                frame.putpixel((x, y), (*colour, 255))
        return frame


@dataclass(frozen=True)
class Pose:
    """How one frame stands: the context, the upper body's lift, the legs and
    both arms (`left` is screen-left from the front and back, the far arm from
    the side), and what the hands hold."""

    seated: bool = False
    bob: int = 0
    nod: int = 0
    legs: str = "stand"
    lead: int = 0
    left: str = "down"
    right: str = "down"
    prop: str = ""


def poses(track: str, count: int) -> list[Pose]:
    """The frames of a track, as poses; a facing turns a pose into pixels."""
    walk = [Pose(legs="contact", lead=0, left="short", right="down"), Pose(legs="passing", lead=0, bob=-1),
            Pose(legs="contact", lead=1, left="down", right="short"), Pose(legs="passing", lead=1, bob=-1)]
    table_ = {
        "stand_idle": [Pose(), Pose(nod=1, left="breath", right="breath")],
        "walk": walk,
        "desk_idle": [Pose(seated=True, left="rest", right="rest"),
                      Pose(seated=True, nod=1, left="rest", right="rest")],
        "desk_work": [Pose(seated=True, left="type", right="rest"), Pose(seated=True, left="rest", right="rest"),
                      Pose(seated=True, left="rest", right="type"), Pose(seated=True, left="rest", right="rest")],
        "desk_blocked": [Pose(seated=True, left="rest", right="raised"),
                         Pose(seated=True, left="rest", right="waved")],
        "stand_blocked": [Pose(right="raised"), Pose(right="waved")],
        "desk_start": [Pose(seated=True, left="lap", right="lap"), Pose(seated=True, nod=1, left="lap", right="lap")],
        "stand_start": [Pose(left="clasp", right="clasp"), Pose(nod=1, left="clasp", right="clasp")],
        "carry_walk": [Pose(legs=pose.legs, lead=pose.lead, bob=pose.bob, left="carry", right="carry", prop="paper")
                       for pose in walk],
        "drink": [Pose(right="cup0", prop="cup0"), Pose(right="cup1", prop="cup1"), Pose(right="cup2", prop="cup2")],
    }
    found = table_.get(track)
    if found is None:
        # A track the placeholder has no drawing for stands still.
        found = [Pose()]
    return [found[index % len(found)] for index in range(count)]


# Where the parts sit on the 32x48 frame of a standing figure (fill cells; the
# ring adds one cell round each). A seated figure's upper body is SEAT lower.
# The bent raised hand (Figure._bent_front_arm): its thumb's top this many cells
# over the head's top row (a wave one more; from the side, where only what is
# over the hair shows, the straight hand's height), its elbow's column and how
# many rows over the shoulder it bends.
BENT_THUMB_UP = 6
BENT_SIDE_THUMB_UP = 8
BENT_ELBOW_X = 25
BENT_ELBOW_UP = 3
SEAT = 5
HEAD = (12, 13)
TORSO_TOP = 22
LEGS_TOP = 34
SHOE_TOP = 42

# The eyes sit a row below every fringe's ink line, with a cell of skin on
# both sides, so no hair outline ever touches them. The head is 8 cells wide
# over a 10-wide torso: the shoulders are wider than the head, about three
# heads tall with the hair.
HEAD_FRONT = (
    ".ssssss.",
    "ssssssss",
    "ssssssss",
    "ssssssss",
    "ssessess",
    "ssessess",
    "ssssssss",
    ".ssssss.",
)
HEAD_BACK = tuple(line.replace("e", "s") for line in HEAD_FRONT)
HEAD_SIDE = (
    ".ssssss..",
    "ssssssss.",
    "ssssssss.",
    "ssssssss.",
    "sssssses.",
    "sssssses.",
    "sssssssss",
    ".sssssss.",
)
TORSO_FRONT = (".ttsstt.",) + ("tttttttt",) * 10
TORSO_BACK = (".tttttt.",) + ("tttttttt",) * 10
TORSO_SIDE = (".tttttt.",) + ("tttttttt",) * 10
SHOE_FRONT = ("OOOO", "oooo", "oooo")
# Seated, from the front: the thighs come at the viewer as a lap wider than the
# hips, the knees apart, the shins straight down to the shoes. From behind: the
# seat of the trousers, then the calves and heels under the chair.
SEATED_FRONT = (
    "llllllllllll",
    "llllllllllll",
    ".llll..llll.",
    ".lll....lll.",
    ".lll....lll.",
    "OOOO....OOOO",
    "oooo....oooo",
)
SEATED_BACK = (
    ".llllllllll.",
    ".llllllllll.",
    "..lll..lll..",
    "..lll..lll..",
    "..lll..lll..",
    "..OOO..OOO..",
    "..ooo..ooo..",
)
# The screen-left arm at a desk, from the shoulder down: resting on the desk,
# lifted a cell to type, or with the hands in the lap.
DESK_ARMS = {
    "rest": ("tt....", "tt....", "tt....", "tt....", "tt....", "ttt...", ".tttss", "....ss"),
    "type": ("tt....", "tt....", "tt....", "tt....", "ttt...", ".tttss", "....ss"),
    "lap": ("tt....", "tt....", "tt....", "tt....", "tt....", "tt....", "tt....", "ttt...", ".ttss.", "...ss."),
}
SHOE_SIDE = ("OOOOO.", "oooooo", "oooooo")

# A mug of coffee, and where it and the holding (right) hand sit from the
# front, relative to the shoulder row: at the chest, at the chin, at the mouth.
CUP = ("cfc", "ccC", "ccC")
CUPS = {"cup0": ((16, 3), (19, 4)), "cup1": ((15, 0), (18, 1)), "cup2": ((15, -3), (18, -2))}
# From the side, how far each drink frame lifts the cup (and the hand) above
# the chest.
CUP_LIFTS = {"cup0": 0, "cup1": 4, "cup2": 8}
# The sleeve of that arm (drawn on the left, mirrored), a polyline of cells
# relative to the shoulder: down and in, bent up to the chin, up to the mouth.
CUP_SLEEVES = {
    "cup0": ((9, 0), (9, 3)),
    "cup1": ((9, 0), (9, 3), (11, 2)),
    "cup2": ((9, 0), (12, -3)),
}

# Hair, by style and facing, placed with its top-left one cell left of and two
# above the head's; lowercase letters take ramps, '.' shows the face below.
HAIR = {
    ("short", "front"): (
        "..hhhhhh..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhh.hhhhh",
        "hh......hh",
    ),
    ("short", "back"): (
        "..hhhhhh..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        ".hhhhhhhh.",
    ),
    ("short", "side"): (
        "..hhhhhh..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhh......",
        "hhhh......",
        "hhh.......",
        ".hh.......",
    ),
    # A round mop: bumps on the crown inside every hat's top, the sides out
    # past the cheeks and down to the chin.
    ("curl", "front"): (
        "..h.hh.h..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hh......hh",
        "h........h",
        "h........h",
        "h........h",
        "hh......hh",
        "hh......hh",
        ".h......h.",
    ),
    ("curl", "back"): (
        "..h.hh.h..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        ".h.hhhh.h.",
    ),
    ("curl", "side"): (
        "..h.hhh...",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhh.....",
        "hhhhh.....",
        "hhhhh.....",
        "hhhhh.....",
        "hhhhh.....",
        "hhhh......",
        ".h.h......",
    ),
    # Straight past the shoulders, parted at the crown; one cell of hair on
    # each side of the face, so the whole face shows.
    ("long", "front"): (
        "..hhhhhh..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhh.hhhhh",
        "h........h",
        "h........h",
        "h........h",
        "h........h",
        "h........h",
        "h........h",
        "hh......hh",
        "hh......hh",
        ".h......h.",
    ),
    ("long", "back"): (
        "..hhhhhh..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        ".hhhhhhhh.",
    ),
    ("long", "side"): (
        "..hhhhhh..",
        ".hhhhhhhh.",
        "hhhhhhhhhh",
        "hhhhhhhhhh",
        "hhhh......",
        "hhhh......",
        "hhhh......",
        "hhhh......",
        "hhhh......",
        "hhhh......",
        "hhhh......",
        "hhh.......",
        ".hh.......",
    ),
}

# Headwear, placed like hair. A cap's crown is at least as wide as every hair
# style's top, so it covers the hair above its brim (check_brims); from the side
# its peak reaches forward. The hood frames the face (its opening shows the
# head below) and hides the hair layer.
HEADWEAR = {
    ("cap", "front"): (
        "..aaaaaa..",
        ".aaaaaaaa.",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
    ),
    ("cap", "back"): (
        "..aaaaaa..",
        ".aaaaaaaa.",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
    ),
    ("cap", "side"): (
        "..aaaaaa....",
        ".aaaaaaaa...",
        "aaaaaaaaaa..",
        "aaaaaaaaaaaa",
    ),
    ("hood", "front"): (
        "..aaaaaa..",
        ".aaaaaaaa.",
        "aaaaaaaaaa",
        "a........a",
        "a........a",
        "a........a",
        "a........a",
        "a........a",
        "aa......aa",
        "aaa....aaa",
        ".aaaaaaaa.",
    ),
    ("hood", "back"): (
        "..aaaaaa..",
        ".aaaaaaaa.",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        "aaaaaaaaaa",
        ".aaaaaaaa.",
    ),
    ("hood", "side"): (
        "..aaaaaa..",
        ".aaaaaaaa.",
        "aaaaaaaaaa",
        "aaaaa.....",
        "aaaa......",
        "aaaa......",
        "aaaa......",
        "aaaa......",
        "aaaa......",
        "aaaaa.....",
        ".aaaaaa...",
    ),
}

# Glasses, placed on the head's top-left: a thin frame (the fixed `frame`
# colour, a mid grey: an ink frame against the near-black eye read as one dark
# band) at each eye (head columns 2 and 5, rows 4 and 5), never a full ring:
# on an 8-cell face a full frame reads as a mask. Round: the bridge and a rim
# under each eye. Square: browline, a bar over each eye, the outer sides and
# the bridge. Nothing opaque sits over an eye, so each eye's own pixels show
# through; there is no lens pixel (the fixed `lens` colour is for a painter's
# glint, not the placeholder). From the side, one frame and the arm back to
# the ear; from behind, nothing shows.
GLASSES = {
    ("round", "front"): (
        "........",
        "........",
        "........",
        "........",
        "...rr...",
        "........",
        "..r..r..",
    ),
    ("square", "front"): (
        "........",
        "........",
        "........",
        "..r..r..",
        ".r.rr.r.",
        "........",
        "........",
    ),
    ("round", "side"): (
        ".........",
        ".........",
        ".........",
        "......r..",
        "..rrrr.r.",
        ".....r.r.",
        "......r..",
    ),
    ("square", "side"): (
        ".........",
        ".........",
        ".........",
        ".....rrr.",
        "..rrrr.r.",
        ".....r.r.",
        ".....rrr.",
    ),
}


# --- skins ----------------------------------------------------------------------------
# The rig above is the white model: every part a flat three-tone sticker. A skin
# is a painted picture of one part, per facing, that the rig wears: it gives the
# part's fill texels their colours, and the rig still places the part in every
# frame, rings it in ink and paints the eyes over it. So a skin never moves the
# figure's outline, its feet, its seams or its choreography; it only fills in
# what a flat tone cannot draw at density 2 (a face, a hairline, a collar).
#
# art/pixel_people/skins/<facing>/<part>.png, one per part a painter has drawn:
#   head                 the head (layer body: skin keys and fixed colours)
#   torso                the torso (layer top: top keys and fixed colours)
#   hair_<style>         a hair style (layer hair: hair keys and fixed colours)
#   headwear_<shape>     a hat (layer headwear: hat keys and fixed colours)
# The limbs, shoes, props and glasses stay the rig's: a limb is a polyline a
# picture cannot be pinned to, and at density 2 a cell's three tones already
# are its drawing.
#
# A skin's canvas is its part's cell envelope times the density, the same in
# every frame (a seated torso drops its last row of cells, so its skin's last
# `density` rows go unused). It is hard-alpha, uses only its layer's keys and the
# fixed colours, and is opaque only on the texels of its part's cells of its own
# layer (not the neckline of the torso, which is the body's; not the ring,
# which is the rig's). A texel it leaves transparent keeps the rig's tone.
Skins = dict[tuple[str, str], Image.Image]
SKIN_DIR = "skins"
# What a skin can be of, and the layer it colours; hair and headwear per shape.
SKIN_PARTS = {"head": "body", "torso": "top", "hair": "hair", "headwear": "headwear"}


def skin_parts(spec: dict) -> list[str]:
    """Every skin a facing can have, in SKIN_PARTS order: hair and headwear once per shape."""
    result = []
    for part, layer in SKIN_PARTS.items():
        slot = shape_slot(spec, layer) if layer in ("hair", "headwear") else None
        result += [part] if slot is None else [f"{part}_{shape}" for shape in spec["slots"][slot]["shapes"]]
    return result


def skin_layer(part: str) -> str:
    return SKIN_PARTS[layer_of(part)]


def skin_files(spec: dict) -> list[tuple[str, str, str]]:
    """(relative path, facing, part) of every skin the contract can take."""
    return [(f"{SKIN_DIR}/{facing}/{part}.png", facing, part) for facing in spec["facings"] for part in skin_parts(spec)]


def shape_rows(layer: str, shape: str, facing: str) -> tuple[str, ...]:
    """The cells of a hair style or a hat seen from `facing`."""
    drawings = HAIR if layer == "hair" else HEADWEAR
    rows = drawings.get((shape, facing))
    if rows is None:
        # A shape added to the contract before anybody drew it wears the
        # first drawing of its layer, in its own colours.
        first = next(key for key in drawings if key[1] == facing)
        rows = drawings[first]
    return rows


def skin_rows(facing: str, part: str) -> tuple[str, ...]:
    """The cells a skin of `part` covers from `facing`, as the rig stamps them."""
    if part == "head":
        return {FRONT: HEAD_FRONT, "back": HEAD_BACK, SIDE: HEAD_SIDE}[facing]
    if part == "torso":
        return {FRONT: TORSO_FRONT, "back": TORSO_BACK, SIDE: TORSO_SIDE}[facing]
    layer = layer_of(part)
    return shape_rows(layer, part.removeprefix(layer + "_"), facing)


def skin_size(spec: dict, facing: str, part: str) -> tuple[int, int]:
    """A skin's canvas in texels: its part's cell envelope times the density."""
    rows = skin_rows(facing, part)
    return (max(len(line) for line in rows) * spec["density"], len(rows) * spec["density"])


def skin_mask(spec: dict, facing: str, part: str) -> set[Cell]:
    """The texels of a skin's canvas it may paint: its part's cells of its own layer."""
    d, layer = spec["density"], skin_layer(part)
    return {(x * d + i, y * d + j) for (x, y), letter in cells_of(skin_rows(facing, part), 0, 0).items()
            if LETTER_LAYERS[letter] == layer for j in range(d) for i in range(d)}


def check_skin(image: Image.Image, spec: dict, facing: str, part: str, relative: str) -> None:
    """The pixel contract of one skin: its canvas, hard alpha, only its layer's
    keys and the fixed colours, and nothing outside its part's own cells."""
    expected = skin_size(spec, facing, part)
    require(image.size == expected, f"{relative}: {image.size} is not the {expected[0]}x{expected[1]} canvas of "
            f"{part} from the {facing} (its cells times density {spec['density']})")
    pixels, allowed, mask = image.load(), allowed_colours(spec, skin_layer(part)), skin_mask(spec, facing, part)
    # The eyes are the rig's, painted over every skin: their colours in a skin
    # read as a stray eye (the eye tests count them) and are refused.
    rigs = {rgb(spec["fixed"][name]): name for name in EYE_COLOURS if name in spec["fixed"]}
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            require(a == 255, f"{relative}: pixel ({x}, {y}) is semi-transparent (alpha {a}); edges are 0 or 255")
            require((r, g, b) not in rigs, f"{relative}: pixel ({x}, {y}) is the {rigs.get((r, g, b))} colour, which only "
                    "the rig paints (the eyes); a skin never holds it")
            require((r, g, b) in allowed, f"{relative}: pixel ({x}, {y}) is #{r:02x}{g:02x}{b:02x}, which is not a key "
                    f"or fixed colour of the {skin_layer(part)} layer")
            require((x, y) in mask, f"{relative}: pixel ({x}, {y}) is outside the cells of {part}; a skin paints its "
                    "part's own cells, never the ring or another layer's")


def load_skins(source: Path, spec: dict) -> Skins:
    """Every skin painted under `source`/skins, checked; (facing, part) -> picture."""
    skins = {}
    for relative, facing, part in skin_files(spec):
        path = source / relative
        if path.is_file():
            image = from_source(path)
            check_skin(image, spec, facing, part, relative)
            skins[(facing, part)] = image
    return skins


def skinned_sheet(part: str) -> str:
    """The source strip a skin of `part` paints into."""
    layer = skin_layer(part)
    return part if layer in ("hair", "headwear") else layer


class Figure:
    """The parts of one pose seen from one facing, painted onto a layer."""

    def __init__(self, spec: dict, pose: Pose, facing: str, skins: Skins | None = None):
        self.spec = spec
        self.pose = pose
        self.facing = facing
        self.skins = skins or {}
        self.width = spec["frame_size"][0]
        drop = SEAT if pose.seated else 0
        self.upper = drop + pose.bob
        self.head = (HEAD[0], HEAD[1] + self.upper + pose.nod)
        self.hand = spec.get("raised_hand", STRAIGHT_HAND)

    def skin_cell(self, part: str) -> Cell:
        """Where the top-left cell of `part`'s envelope (a skin part: head,
        torso, a hair style or a hat) lands in this frame."""
        if part == "head":
            return self.head
        if part == "torso":
            return (12, TORSO_TOP + self.upper)
        # Hair and headwear sit one cell left of and two above the head.
        return (self.head[0] - 1, self.head[1] - 2)

    def _skin(self, part: str) -> SkinAt | None:
        """The skin of `part` in this facing, placed where the part is, if one is painted."""
        image = self.skins.get((self.facing, part))
        return None if image is None else SkinAt(image, self.skin_cell(part), skin_layer(part))

    # --- the figure: legs, top and body

    def figure(self) -> Painter:
        """The whole figure, painted once; each pixel knows its layer."""
        painter = Painter(self.spec)
        if self.facing == SIDE:
            self._side_body(painter)
        else:
            self._front_body(painter)
        return painter

    def _front_body(self, painter: Painter) -> None:
        back = self.facing == "back"
        painter.stamp(self._front_legs(back))
        torso_rows = TORSO_BACK if back else TORSO_FRONT
        if self.pose.seated:
            torso_rows = torso_rows[:-1]
        painter.stamp(cells_of(torso_rows, *self.skin_cell("torso")), skin=self._skin("torso"))
        for side, pose in (("left", self.pose.left), ("right", self.pose.right)):
            arm = self._front_arm(pose, back)
            if side == "right":
                arm = mirrored(arm, self.width)
            if pose != "raised" and pose != "waved":
                painter.stamp(arm)
        painter.stamp(cells_of(HEAD_BACK if back else HEAD_FRONT, *self.head), skin=self._skin("head"))
        for side, pose in (("left", self.pose.left), ("right", self.pose.right)):
            if pose in ("raised", "waved"):
                arm = self._front_arm(pose, back)
                painter.stamp(arm if side == "right" else mirrored(arm, self.width))
        self._front_prop(painter, back)

    def _front_legs(self, back: bool) -> Cells:
        """Trousers, two lower legs and the shoes, seen from the front or back."""
        if self.pose.seated:
            return cells_of(SEATED_BACK if back else SEATED_FRONT, 10, LEGS_TOP + SEAT - 1)
        top = LEGS_TOP + self.pose.bob
        feet = {"left": SHOE_TOP, "right": SHOE_TOP}
        if self.pose.legs == "contact":
            feet["right" if self.pose.lead == 0 else "left"] = SHOE_TOP - 1
        elif self.pose.legs == "passing":
            feet["right" if self.pose.lead == 0 else "left"] = SHOE_TOP - 2
        cells = block(12, top, 19, top + 1, "l")
        for side, foot in feet.items():
            leg = block(12, top + 2, 14, foot - 1, "l")
            leg.update(cells_of(SHOE_FRONT, 11, foot))
            cells.update(leg if side == "left" else mirrored(leg, self.width))
        return cells

    def _front_arm(self, pose: str, back: bool) -> Cells:
        """The screen-left arm in `pose` (the right one is its mirror)."""
        shoulder = TORSO_TOP + 1 + self.upper
        if pose in ("down", "breath", "short"):
            reach = shoulder + (5 if pose == "short" else 6)
            arm = limb([(9, shoulder), (9, reach)], "t")
            arm.update(block(9, reach + 2, 10, reach + 3, "s"))
            return arm
        if pose in ("rest", "type", "lap"):
            rows = DESK_ARMS[pose]
            if back:
                # From behind, the forearms reach away under the shoulders:
                # only the upper arm shows, a cell shorter while it types.
                rows = tuple(line[:2] for line in rows if line.startswith("tt"))
            return cells_of(rows, 9, shoulder)
        if pose in ("raised", "waved"):
            if self.hand != STRAIGHT_HAND:
                return self._bent_front_arm(pose, back, shoulder)
            top = self.head[1] - (9 if pose == "waved" else 8)
            arm = limb([(21, shoulder), (22, shoulder - 3), (22, top + 2)], "t")
            arm.update(block(22, top, 23, top + 1, "s"))
            return arm
        if pose == "clasp":
            arm = limb([(9, shoulder), (9, shoulder + 5), (12, shoulder + 7)], "t")
            if not back:
                arm.update(block(14, shoulder + 7, 15, shoulder + 8, "s"))
            return arm
        if pose == "carry":
            arm = limb([(9, shoulder), (9, shoulder + 4), (11, shoulder + 6)], "t")
            if not back:
                arm.update(block(13, shoulder + 5, 14, shoulder + 6, "s"))
            return arm
        if pose in CUP_SLEEVES:
            # Held in the right hand: the sleeve is drawn here as the left one,
            # then mirrored; the hand goes on with the cup (_front_prop).
            return limb([(x, shoulder + y) for x, y in CUP_SLEEVES[pose]], "t")
        return limb([(9, shoulder), (9, shoulder + 6)], "t")

    def _bent_front_arm(self, pose: str, back: bool, shoulder: int) -> Cells:
        """The bent raised hand from the front or back, on the screen-right side
        (never mirrored): the upper arm out on a diagonal from the shoulder to
        an elbow level with the chin, the forearm straight up, a cuff, and a
        3x3 mitten a cell over toward the head with the thumb on top, on the
        outer corner seen from the front and the inner one from behind (the
        back of the hand). A wave lifts the forearm and hand a cell. The ring
        reaches x 27 (12 units right of the pivot); the thumb's top stays
        where the straight arm's hand was or lower, and clear of every hat."""
        thumb_top = self.head[1] - (BENT_THUMB_UP + (1 if pose == "waved" else 0))
        top = thumb_top + 1
        elbow = (BENT_ELBOW_X, shoulder - BENT_ELBOW_UP)
        arm = limb([(BENT_ELBOW_X - BENT_ELBOW_UP - 1, shoulder), elbow, (BENT_ELBOW_X, top + 4)], "t")
        arm.update(block(BENT_ELBOW_X, top + 3, BENT_ELBOW_X + 1, top + 3, CUFF))
        arm.update(block(BENT_ELBOW_X - 1, top, BENT_ELBOW_X + 1, top + 2, "s"))
        arm[(BENT_ELBOW_X - 1 if back else BENT_ELBOW_X + 1, thumb_top)] = "s"
        return arm

    def _front_prop(self, painter: Painter, back: bool) -> None:
        if back or not self.pose.prop:
            return
        shoulder = TORSO_TOP + 1 + self.upper
        if self.pose.prop == "paper":
            paper = cells_of(("pppppp", "pPPPPp", "pppppp", "pPPPpp", "pppppp", "pPPPPp"), 13, shoulder)
            painter.stamp(paper)
            for hand in (block(12, shoulder + 4, 13, shoulder + 5, "s"), block(18, shoulder + 4, 19, shoulder + 5, "s")):
                painter.stamp(hand)
        elif self.pose.prop in CUPS:
            # Over the head and inside the face's opening, so neither the
            # chin nor a hood's edge covers the cup; the hand holds its side.
            (cup_x, cup_y), (hand_x, hand_y) = CUPS[self.pose.prop]
            painter.stamp(cells_of(CUP, cup_x, shoulder + cup_y))
            painter.stamp(block(hand_x, shoulder + hand_y, hand_x + 1, shoulder + hand_y + 1, "s"))

    def _side_body(self, painter: Painter) -> None:
        near_pose, far_pose = self.pose.right, self.pose.left
        if near_pose in ("raised", "waved"):
            # From the side a raised hand is the far one, rising behind the
            # head: the near arm would cross the face.
            near_pose, far_pose = "down", near_pose
        near, far = self._side_legs()
        painter.stamp(far, far=True)
        far_arm = self._side_arm(far_pose, far=True)
        if far_arm:
            painter.stamp(far_arm, far=True)
        painter.stamp(near)
        torso = TORSO_SIDE[:-1] if self.pose.seated else TORSO_SIDE
        painter.stamp(cells_of(torso, *self.skin_cell("torso")), skin=self._skin("torso"))
        painter.stamp(cells_of(HEAD_SIDE, *self.head), skin=self._skin("head"))
        if self.pose.prop == "paper":
            shoulder = TORSO_TOP + 1 + self.upper
            painter.stamp(cells_of(("ppp", "pPp", "ppp", "pPp", "ppp", "ppp"), 21, shoulder + 1))
        painter.stamp(self._side_arm(near_pose, far=False))
        if self.pose.prop in CUP_LIFTS:
            lift = CUP_LIFTS[self.pose.prop]
            shoulder = TORSO_TOP + 1 + self.upper
            painter.stamp(cells_of(CUP, 20 + lift // 4, shoulder + 3 - lift))

    def _side_legs(self) -> tuple[Cells, Cells]:
        """The near and far legs from the side, walking to the right."""
        top = LEGS_TOP + self.pose.bob
        if self.pose.legs == "stand":
            leg = block(14, top, 17, SHOE_TOP - 1, "l")
            leg.update(cells_of(SHOE_SIDE, 14, SHOE_TOP))
            return leg, {}
        forward = limb([(15, top), (17, 38), (18, SHOE_TOP - 2)], "l", 3)
        forward.update(cells_of(SHOE_SIDE, 17, SHOE_TOP))
        backward = limb([(14, top), (12, 38), (11, SHOE_TOP - 2)], "l", 3)
        backward.update(cells_of(SHOE_SIDE, 10, SHOE_TOP))
        straight = limb([(14, top), (15, SHOE_TOP - 2)], "l", 3)
        straight.update(cells_of(SHOE_SIDE, 14, SHOE_TOP))
        lifted = limb([(14, top), (15, 37), (14, SHOE_TOP - 4)], "l", 3)
        lifted.update(cells_of(SHOE_SIDE, 13, SHOE_TOP - 2))
        if self.pose.legs == "contact":
            return (forward, backward) if self.pose.lead == 0 else (backward, forward)
        return (straight, lifted) if self.pose.lead == 0 else (lifted, straight)

    def _side_arm(self, pose: str, far: bool) -> Cells:
        """The near (or far) arm from the side, facing right."""
        shoulder = TORSO_TOP + 1 + self.upper
        lead = self.pose.lead
        if pose in ("down", "short", "breath") and self.pose.legs == "contact":
            # The arms swing against the legs: the near arm goes back when the
            # near leg leads.
            back = (lead == 0) != far
            end = (12, shoulder + 5) if back else (18, shoulder + 5)
            arm = limb([(15, shoulder), end], "t")
            arm.update(block(end[0], end[1] + 2, end[0] + 1, end[1] + 3, "s"))
            return arm
        if far and pose in ("down", "short", "breath"):
            return {}
        if pose in ("down", "short", "breath"):
            arm = limb([(15, shoulder), (15, shoulder + 5)], "t")
            arm.update(block(15, shoulder + 7, 16, shoulder + 8, "s"))
            return arm
        if pose in ("raised", "waved") and self.hand != STRAIGHT_HAND:
            # Bent: behind the head up to the crown, then up and a little
            # forward; what shows over the hair is the cuff and the mitten, its
            # thumb on top at the front (the side faces right). As high as the
            # straight arm's hand, no higher: lower, the hair would hide the cuff.
            thumb_top = self.head[1] - (BENT_SIDE_THUMB_UP + (1 if pose == "waved" else 0))
            top = thumb_top + 1
            arm = limb([(14, shoulder), (15, self.head[1] + 1), (18, top + 4)], "t")
            arm.update(block(18, top + 3, 19, top + 3, CUFF))
            arm.update(block(17, top, 19, top + 2, "s"))
            arm[(19, thumb_top)] = "s"
            return arm
        if pose in ("raised", "waved"):
            # Behind the head up to the crown, then forward: what shows above
            # the hair is a forearm reaching up and out, and the hand.
            top = self.head[1] - (9 if pose == "waved" else 8)
            arm = limb([(14, shoulder), (15, self.head[1] + 1), (19, top + 2)], "t")
            arm.update(block(19, top, 20, top + 1, "s"))
            return arm
        if pose == "carry":
            arm = limb([(15, shoulder), (15, shoulder + 4), (18, shoulder + 5)], "t")
            arm.update(block(20, shoulder + 4, 21, shoulder + 5, "s"))
            return arm
        if pose in CUP_LIFTS:
            lift = CUP_LIFTS[pose]
            hand = shoulder + 5 - lift
            arm = limb([(15, shoulder), (15, shoulder + 4), (18, max(hand, shoulder + 1))], "t")
            arm.update(block(19 + lift // 4, hand, 20 + lift // 4, hand + 1, "s"))
            return arm
        return limb([(15, shoulder), (15, shoulder + 5)], "t")

    # --- the shape layers

    def shape(self, layer: str, shape: str) -> Image.Image:
        """One shape layer's frame: hair or headwear placed like hair, glasses
        on the head; a shape the placeholder has no drawing for in this facing
        (glasses from behind) is empty."""
        painter = Painter(self.spec)
        if layer == "glasses":
            rows = GLASSES.get((shape, self.facing))
            if rows is not None:
                painter.stamp(cells_of(rows, *self.head), ring=False)
            return painter.image()
        part = f"{layer}_{shape}"
        painter.stamp(cells_of(shape_rows(layer, shape, self.facing), *self.skin_cell(part)), skin=self._skin(part))
        return painter.image()


def draw_placeholder(spec: dict, facing: str, sheet: str, skins: Skins | None = None) -> Image.Image:
    """A source strip nobody has drawn yet, in key colours, from the contract
    alone: the white model, wearing whatever skins are painted for its parts."""
    width, _height = frame_texels(spec)
    strip = Image.new("RGBA", strip_size(spec), (0, 0, 0, 0))
    first = starts(spec)
    layer = layer_of(sheet)
    for track, info in spec["tracks"].items():
        if facing not in info["facings"]:
            continue
        for index, pose in enumerate(poses(track, len(info["durations"]))):
            figure = Figure(spec, pose, facing, skins)
            if layer in BASE_LAYERS:
                frame = figure.figure().image(layer)
            else:
                frame = figure.shape(layer, sheet.removeprefix(layer + "_"))
            strip.paste(frame, ((first[track] + index) * width, 0))
    return strip


def draw_figure(spec: dict, facing: str, skins: Skins | None = None) -> Image.Image:
    """The whole placeholder figure of one facing in key colours, every part in
    one picture: what legs, top and body split, for tests and templates."""
    width, _height = frame_texels(spec)
    strip = Image.new("RGBA", strip_size(spec), (0, 0, 0, 0))
    first = starts(spec)
    for track, info in spec["tracks"].items():
        if facing not in info["facings"]:
            continue
        for index, pose in enumerate(poses(track, len(info["durations"]))):
            strip.paste(Figure(spec, pose, facing, skins).figure().image(), ((first[track] + index) * width, 0))
    return strip


# --- the build ----------------------------------------------------------------------


def product_manifest(spec: dict, mocked: list[str]) -> dict:
    """What the runtime reads (PixelPeople.from_manifest): geometry, tracks with
    their first column, state_tracks, the slots and looks, the key and fixed
    colours, the packed sheets and the row of every strip in them, and which
    sources are still placeholders."""
    first = starts(spec)
    return {
        "schema_version": SCHEMA_VERSION,
        "density": spec["density"],
        "filter": "nearest",
        "frame_size": spec["frame_size"],
        "pivot": spec["pivot"],
        "columns": column_count(spec),
        "facings": spec["facings"],
        "side_faces": spec["side_faces"],
        "layers": spec["layers"],
        "tracks": {track: {"start": first[track], "facings": info["facings"], "durations": info["durations"],
                           "loop": info["loop"]} for track, info in spec["tracks"].items()},
        "state_tracks": spec["state_tracks"],
        "slots": spec["slots"],
        "default_look": spec["default_look"],
        "variation": spec["variation"],
        "keys": spec["keys"],
        "fixed": spec["fixed"],
        "strips": [product.name for product in products(spec)],
        "files": sheet_files(spec),
        "mock_files": sorted(mocked),
    }


def build(source: Path = SOURCE, output: Path = OUTPUT) -> dict:
    """Check or draw every source, recolour it into every product strip, pack a
    facing's strips into its sheet, write the product manifest and prune what it
    no longer names; return that manifest."""
    spec = load_spec(source)
    listed = {relative for relative, _facing, _sheet in source_files(spec)}
    listed |= {relative for relative, _facing, _part in skin_files(spec)}
    strays = sorted(str(path.relative_to(source)) for path in source.rglob("*.png")
                    if str(path.relative_to(source)) not in listed)
    require(not strays, f"{source}: PNG(s) the contract does not name: {', '.join(strays)}")
    skins = load_skins(source, spec)
    # A strip the rig draws is a placeholder until one of its parts wears a skin.
    skinned = {(facing, skinned_sheet(part)) for facing, part in skins}
    sources, mocked = {}, []
    for relative, facing, sheet in source_files(spec):
        painted = source / relative
        if painted.is_file():
            image = from_source(painted)
        else:
            image = draw_placeholder(spec, facing, sheet, skins)
            if (facing, sheet) not in skinned:
                mocked.append(relative)
        check_source(image, spec, facing, sheet, relative)
        sources[(facing, sheet)] = image
    check_brims(spec, sources)
    written = []
    width, height = strip_size(spec)
    shipped = products(spec)
    for facing in spec["facings"]:
        sheet = Image.new("RGBA", (width, height * len(shipped)), (0, 0, 0, 0))
        for row, product in enumerate(shipped):
            strip = recolour(sources[(facing, product.sheet)], spec, product, f"{facing}/{product.sheet}.png")
            sheet.paste(strip, (0, row * height))
        target = output / f"{facing}.png"
        save_if_pixels_moved(sheet, target, optimize=True)
        written.append(target)
    manifest = product_manifest(spec, mocked)
    text = json.dumps(manifest, indent=2) + "\n"
    target = output / PRODUCT_NAME
    if not target.is_file() or target.read_text() != text:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    report_pruned(output, prune_unreferenced(output, written))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", type=Path, default=SOURCE, help="the source directory (default art/pixel_people)")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="the runtime directory (default assets/pixel_people)")
    args = parser.parse_args()
    try:
        manifest = build(args.source, args.output)
    except PeopleError as error:
        print(f"PEOPLE_BUILD_FAILED: {error}", file=sys.stderr)
        sys.exit(1)
    spec = load_spec(args.source)
    print(f"PEOPLE_BUILD_OK: {len(manifest['files'])} sheets of {len(manifest['strips'])} strips from "
          f"{len(source_files(spec))} sources, {len(manifest['mock_files'])} placeholder, "
          f"{manifest['columns']} frames per strip")
    ratios = eye_contrast(spec)
    low = [swatch for swatch, ratio in ratios if ratio < EYE_CONTRAST_MIN]
    print("PEOPLE_EYE_CONTRAST: " + ", ".join(f"{swatch} {ratio:.2f}:1" for swatch, ratio in ratios)
          + (f"; below {EYE_CONTRAST_MIN:g}:1: {', '.join(low)} " + (
              "(every eye carries a catchlight texel, docs/ASSET_SPEC.md)" if CATCHLIGHT in spec["fixed"]
              and spec["density"] >= 2 else "(people.json names no catchlight; docs/ASSET_SPEC.md)") if low else ""))


if __name__ == "__main__":
    main()
