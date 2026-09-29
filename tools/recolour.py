"""Exact palette recolouring: old RGB to new RGB, pixel for pixel.

What remains of the retired theme derivation (a second pack recoloured from
daylight by a recipe; night is now a light over the one pack). The pixel people
build uses it to turn key-colour sources into one strip per swatch
(tools/build_pixel_people.py): an ambiguous source palette and a pixel outside
it are refused, never guessed.
"""
from __future__ import annotations

from PIL import Image


def fail(message):
    raise SystemExit(f"recolour: {message}")


def remap_table(palette: dict, overrides: dict) -> dict:
    """Old RGB to new RGB. An ambiguous source palette cannot be remapped at all."""
    seen = {}
    for key, value in palette.items():
        colour = tuple(bytes.fromhex(value))
        if colour in seen:
            fail(f"source palette is ambiguous: {seen[colour]} and {key} are both #{value}")
        seen[colour] = key
    return {colour: tuple(bytes.fromhex(overrides.get(key, palette[key]))) for colour, key in seen.items()}


def repaint(image: Image.Image, table: dict, label: str, keep_foreign: bool) -> tuple[Image.Image, set]:
    """Substitute colours pixel for pixel; alpha is never touched.

    Every opaque pixel has to be a colour the table knows. One that is not is
    reported with the file it is in and where in that file it first appears, so
    the picture can be opened at that spot.
    """
    raw = bytearray(image.convert("RGBA").tobytes())
    foreign = {}
    for index in range(0, len(raw), 4):
        if raw[index + 3] == 0:
            # Hard transparency carries no colour; leave the zeroes as they are.
            continue
        colour = (raw[index], raw[index + 1], raw[index + 2])
        mapped = table.get(colour)
        if mapped is None:
            pixel = index // 4
            foreign.setdefault(colour, (pixel % image.width, pixel // image.width))
            continue
        raw[index], raw[index + 1], raw[index + 2] = mapped
    if foreign and not keep_foreign:
        listing = ", ".join("#%02x%02x%02x at (%d, %d)" % (*colour, *at) for colour, at in sorted(foreign.items()))
        fail(f"{label} holds colours outside the source palette: {listing}")
    return Image.frombytes("RGBA", image.size, bytes(raw)), set(foreign)
