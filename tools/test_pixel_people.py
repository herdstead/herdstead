"""Contract checks for the pixel people (tools/build_pixel_people.py).

The shipped product is checked against the hand-written contract, pixel by
pixel: geometry, the track table, the slots, the sheet count, the exact recolour
of every strip, hard alpha, the feet on the ground in every frame, a continuous
ink outline, the raised hand above the head, the lossless split of the figure
into legs, top and body, and every hat covering the hair above its brim. The
expected strips and colours are derived again here from people.json rather than
asked of the builder, so a builder that maps the wrong thing cannot also be the
test that agrees with it.

The "a hand-drawn source replaces a placeholder" path, which is the point of
the family, runs in a temporary directory: placeholder -> painted -> deleted
again, and a painted source that breaks each rule is refused. Nothing here
writes to art/ or assets/.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from build_pixel_people import (
    EYE_CONTRAST_MIN,
    HEAD_FRONT,
    OUTPUT,
    PRODUCT_NAME,
    SOURCE,
    SPEC_NAME,
    Figure,
    Painter,
    PeopleError,
    SkinAt,
    build,
    cells_of,
    draw_figure,
    draw_placeholder,
    eye_contrast,
    load_skins,
    poses,
    skin_mask,
    skin_parts,
    skin_size,
    validate,
)
from people_skins import cut, white_model


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_pixel_people.py"
SKIN_CUTTER = ROOT / "tools" / "people_skins.py"
CONTEXTS = ("stand", "desk")
STATES = ("idle", "done", "unknown", "working", "blocked", "starting")
# The track table the family was asked for: facings and frame counts.
TRACKS = {
    "stand_idle": (("front", "back", "side"), 2),
    "walk": (("front", "back", "side"), 4),
    "desk_idle": (("front", "back"), 2),
    "desk_work": (("front", "back"), 4),
    "desk_blocked": (("front", "back"), 2),
    "stand_blocked": (("front", "side"), 2),
    "desk_start": (("front", "back"), 2),
    "stand_start": (("front", "back"), 2),
    "carry_walk": (("front", "back", "side"), 4),
    "drink": (("front", "side"), 3),
}
LAYERS = ("legs", "top", "body", "glasses", "hair", "headwear")
BASE = ("legs", "top", "body")
SLOTS = ("skin", "hair_style", "hair_colour", "top", "legs", "headwear", "headwear_colour", "glasses")
# What v1 saved looks and the agent catalog translate into (AgentCatalog's
# v1 table): every one of these has to stay drawable.
V1_TARGETS = {
    "hair_style": ("short", "curl"), "hair_colour": ("brown", "auburn", "umber"),
    "top": ("slate", "cream", "terra", "teal", "lilac"), "legs": ("charcoal", "brown", "taupe", "denim", "plum"),
    "headwear": ("cap", "hood"), "headwear_colour": ("sea", "slate", "cream", "terra", "teal", "lilac"),
}
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
# A catchlight colour for fixtures of a contract that names none yet; the
# shipped people.json's own, when it has one, is used instead.
FIXTURE_CATCHLIGHT = "f0f4fa"
# How far (RGB distance) a fill keeps from the outline so the two never merge.
MIN_INK_DISTANCE = 40


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def rgb(colour: str) -> tuple[int, int, int]:
    return tuple(bytes.fromhex(colour))


def layer_slots(spec: dict, layer: str) -> tuple[str | None, str | None]:
    """(shape slot, colour slot) of a layer, read off people.json."""
    shape = next((slot for slot, info in spec["slots"].items() if info["layer"] == layer and "shapes" in info), None)
    colour = next((slot for slot, info in spec["slots"].items() if info["layer"] == layer and "role" in info), None)
    return shape, colour


def expected_strips(spec: dict) -> list[tuple[str, str, dict]]:
    """(strip, source sheet, role -> target ramp) of every strip, in packing order."""
    found = []
    for layer in LAYERS:
        shape, colour = layer_slots(spec, layer)
        sheets = [layer] if shape is None else [f"{layer}_{name}" for name in spec["slots"][shape]["shapes"]]
        for sheet in sheets:
            if colour is None:
                found.append((sheet, sheet, {}))
                continue
            info = spec["slots"][colour]
            for swatch, ramp in info["swatches"].items():
                found.append((f"{sheet}_{swatch}", sheet, {info["role"]: ramp}))
    return found


def colour_map(spec: dict, targets: dict) -> dict:
    """Key RGB -> the RGB a strip shows it as, from people.json alone; fixed
    colours map to themselves."""
    mapped = {rgb(colour): rgb(colour) for colour in spec["fixed"].values()}
    for role, ramp in targets.items():
        for key, target in zip(spec["keys"][role], ramp):
            mapped[rgb(key)] = rgb(target)
    return mapped


def frames(spec: dict):
    """(track, frame index, column) for every frame of every track."""
    column = 0
    for track, info in spec["tracks"].items():
        for index in range(len(info["durations"])):
            yield track, index, column
            column += 1


def opaque(image: Image.Image) -> list[tuple[int, int]]:
    pixels = image.load()
    return [(x, y) for y in range(image.height) for x in range(image.width) if pixels[x, y][3]]


def source_of(spec: dict, facing: str, sheet: str) -> Image.Image:
    """A source strip as the build takes it: hand-drawn, or the white model
    wearing whatever skins art/pixel_people/skins holds."""
    painted = SOURCE / facing / f"{sheet}.png"
    if painted.is_file():
        with Image.open(painted) as opened:
            return opened.convert("RGBA")
    return draw_placeholder(spec, facing, sheet, load_skins(SOURCE, spec))


class ShippedPixelPeopleTests(unittest.TestCase):
    def setUp(self):
        self.spec = load(SOURCE / SPEC_NAME)
        self.product = load(OUTPUT / PRODUCT_NAME)
        # Pixel tests read texels: a unit is `d` of them, a frame is its units times d.
        self.d = self.spec["density"]
        self.width, self.height = (value * self.d for value in self.spec["frame_size"])
        self.columns = sum(len(info["durations"]) for info in self.spec["tracks"].values())
        self._sheets = {}

    def sheet(self, facing: str) -> Image.Image:
        if facing not in self._sheets:
            with Image.open(OUTPUT / f"{facing}.png") as opened:
                self._sheets[facing] = opened.convert("RGBA")
        return self._sheets[facing]

    def strip(self, facing: str, name: str) -> Image.Image:
        row = self.product["strips"].index(name)
        return self.sheet(facing).crop((0, row * self.height, self.columns * self.width, (row + 1) * self.height))

    def frame(self, image: Image.Image, column: int) -> Image.Image:
        return image.crop((column * self.width, 0, (column + 1) * self.width, self.height))

    def look(self, facing: str, hair: str = "short", headwear: str = "none", glasses: str = "none") -> Image.Image:
        """A whole figure in the default colours, composited bottom to top as the prefab draws it."""
        default = self.spec["default_look"]
        names = [f"legs_{default['legs']}", f"top_{default['top']}", f"body_{default['skin']}"]
        if glasses != "none":
            names.append(f"glasses_{glasses}")
        hides = self.spec["slots"]["headwear"]["shapes"].get(headwear, {}).get("hides_hair", False)
        if hair != "none" and not hides:
            names.append(f"hair_{hair}_{default['hair_colour']}")
        if headwear != "none":
            names.append(f"headwear_{headwear}_{default['headwear_colour']}")
        result = Image.new("RGBA", (self.columns * self.width, self.height), (0, 0, 0, 0))
        for name in names:
            result = Image.alpha_composite(result, self.strip(facing, name))
        return result

    def combinations(self):
        """Every hair style (and none) x headwear (and none) x glasses (and none)."""
        slots = self.spec["slots"]
        for hair in [*slots["hair_style"]["shapes"], "none"]:
            for headwear in [*slots["headwear"]["shapes"], "none"]:
                for glasses in [*slots["glasses"]["shapes"], "none"]:
                    yield hair, headwear, glasses

    def drawn(self):
        """(track, index, column, facing) of every frame some facing draws."""
        for track, index, column in frames(self.spec):
            for facing in self.spec["tracks"][track]["facings"]:
                yield track, index, column, facing

    # --- the contract

    def test_geometry_is_the_avatar_canvas(self):
        self.assertIn(self.spec["density"], (1, 2), "texels per unit: the family draws at density 1 or 2")
        self.assertEqual(self.spec["density"], 2, "shipped at density 2: a unit is 2x2 texels")
        self.assertEqual(self.spec.get("ring_texels"), 1, "the thin outline: one ink texel")
        self.assertIn("catchlight", self.spec["fixed"], "every eye carries a catchlight (the answer to the deep skin)")
        self.assertEqual(self.spec["frame_size"], [32, 48], "the canvas every table and label is laid out for")
        self.assertEqual(self.spec["pivot"], [16, 46], "the feet, where every station offset was measured")
        self.assertEqual(self.spec["facings"], ["front", "back", "side"])
        self.assertEqual(self.spec["side_faces"], "right", "left is the side mirrored, never a drawing of its own")
        self.assertEqual(self.spec["layers"], list(LAYERS))

    def test_tracks_are_the_table_asked_for(self):
        found = {track: (tuple(info["facings"]), len(info["durations"])) for track, info in self.spec["tracks"].items()}
        self.assertEqual(found, TRACKS)
        for track, info in self.spec["tracks"].items():
            self.assertEqual(info["facings"][0], "front", f"{track} falls back to its front")
            self.assertIsInstance(info["loop"], bool)
            self.assertTrue(all(value > 0 for value in info["durations"]), track)

    def test_state_tracks_map_every_state_in_both_contexts(self):
        for context in CONTEXTS:
            mapped = self.spec["state_tracks"][context]
            self.assertEqual(set(mapped), set(STATES), context)
            for state, track in mapped.items():
                self.assertIn(track, self.spec["tracks"], f"{context}/{state}")
        desk = self.spec["state_tracks"]["desk"]
        self.assertEqual((desk["working"], desk["blocked"], desk["starting"]), ("desk_work", "desk_blocked", "desk_start"))
        stand = self.spec["state_tracks"]["stand"]
        self.assertEqual((stand["blocked"], stand["starting"]), ("stand_blocked", "stand_start"))
        for state in ("idle", "done", "unknown"):
            self.assertEqual((stand[state], desk[state]), ("stand_idle", "desk_idle"), state)

    def test_slots_are_the_ones_looks_are_made_of(self):
        slots = self.spec["slots"]
        self.assertEqual(tuple(slots), SLOTS)
        self.assertGreaterEqual(len(slots["skin"]["swatches"]), 4, "at least four skin ramps")
        self.assertEqual([slot for slot, info in slots.items() if info.get("none")], ["hair_style", "headwear", "glasses"])
        self.assertTrue(slots["headwear"]["shapes"]["hood"].get("hides_hair"), "a hood hides the hair")
        self.assertFalse(slots["headwear"]["shapes"]["cap"].get("hides_hair", False), "a cap is worn over the hair")
        for slot, wanted in V1_TARGETS.items():
            drawn = slots[slot].get("swatches", slots[slot].get("shapes"))
            for value in wanted:
                self.assertIn(value, drawn, f"{slot} {value}: a saved v1 look translates to it")

    def test_every_role_is_coloured_by_one_slot_of_one_layer(self):
        roles = [info["role"] for info in self.spec["slots"].values() if "role" in info]
        self.assertEqual(sorted(roles), sorted(self.spec["keys"]), "one colour slot per key role")
        for layer in LAYERS:
            shape, colour = layer_slots(self.spec, layer)
            owners = [slot for slot, info in self.spec["slots"].items() if info["layer"] == layer]
            self.assertEqual(sorted(owners), sorted(slot for slot in (shape, colour) if slot), f"{layer}: one of each")

    def test_glasses_are_one_in_six(self):
        pool = self.spec["variation"]["glasses"]
        self.assertEqual(sum(1 for value in pool if value != "none") / len(pool), 1 / 6, "a pair of glasses on 1 pane in 6")

    def test_the_eye_against_every_skin(self):
        """The fixed eye colour against every skin swatch's mid tone (WCAG 2.1 contrast). Every swatch but
        the deepest clears EYE_CONTRAST_MIN; the deepest does not, and the answer (the rig's catchlight in
        every eye's top-left texel) is written where the painter reads (docs/ASSET_SPEC.md, the templates' README)."""
        ratios = dict(eye_contrast(self.spec))
        expected = {"porcelain": 11.23, "fair": 8.98, "tan": 6.23, "brown": 3.34, "deep": 2.06}
        self.assertEqual(sorted(ratios), sorted(expected))
        for swatch, ratio in expected.items():
            self.assertAlmostEqual(ratios[swatch], ratio, places=2, msg=swatch)
        self.assertEqual([s for s, r in ratios.items() if r < EYE_CONTRAST_MIN], ["deep"])
        spec_text = (ROOT / "docs" / "ASSET_SPEC.md").read_text()
        self.assertIn("The answer is a catchlight", spec_text, "ASSET_SPEC gives the catchlight as the answer")
        self.assertIn("the top-left texel of the upper cell", spec_text, "and where it goes")
        with tempfile.TemporaryDirectory() as work:
            subprocess.run([sys.executable, str(ROOT / "tools" / "people_templates.py"), "--output", str(Path(work) / "t")],
                           check=True, capture_output=True, cwd=ROOT)
            readme = (Path(work) / "t" / "README.txt").read_text()
            self.assertIn("The answer is a catchlight", readme, "and so does the templates' README")
            self.assertIn("paints it on the top-left texel of the upper cell", readme, "with where it goes")

    def test_every_eye_shows_through_every_pair_of_glasses(self):
        """Composited as the prefab draws them, each eye pixel of the body is still the eye colour under
        every pair of glasses: a thin frame round the eye, nothing over it."""
        eye = rgb(self.spec["fixed"]["eye"])
        rim = rgb(self.spec["fixed"]["frame"])
        for facing in self.spec["facings"]:
            for shape in self.spec["slots"]["glasses"]["shapes"]:
                colours = {colour[:3] for _count, colour in self.strip(facing, f"glasses_{shape}").getcolors() if colour[3]}
                self.assertLessEqual(colours, {rim}, f"{facing} {shape}: a thin frame in the frame colour, no lens fill")
                face = self.look(facing, glasses=shape)
                body = self.strip(facing, f"body_{self.spec['default_look']['skin']}").load()
                pixels = face.load()
                for y in range(face.height):
                    for x in range(face.width):
                        if body[x, y][3] and body[x, y][:3] == eye:
                            self.assertEqual(pixels[x, y][:3], eye, f"{facing} {shape}: the eye at ({x},{y}) shows")

    def test_default_look_and_variation_name_drawn_options(self):
        slots = self.spec["slots"]
        for slot in SLOTS:
            allowed = list(slots[slot].get("swatches", slots[slot].get("shapes"))) + (["none"] if slots[slot].get("none") else [])
            self.assertIn(self.spec["default_look"][slot], allowed, slot)
            for value in self.spec["variation"].get(slot, []):
                self.assertIn(value, allowed, f"variation.{slot}")
        self.assertEqual(sorted(self.spec["variation"]), sorted(["skin", "hair_style", "hair_colour", "glasses"]),
                         "the face and head vary; clothes are the provider's or the user's")

    def test_key_and_fixed_colours_are_all_distinct(self):
        colours = [colour for ramp in self.spec["keys"].values() for colour in ramp] + list(self.spec["fixed"].values())
        self.assertEqual(len(colours), len(set(colours)), "one colour, one meaning: the recolour is a lookup")
        for role, ramp in self.spec["keys"].items():
            self.assertEqual(len(ramp), 3, f"{role} is a three-tone ramp")

    # --- the product manifest and the files

    def test_product_manifest_is_the_contract_laid_out(self):
        product = self.product
        self.assertEqual(product["columns"], self.columns)
        column = 0
        for track, info in self.spec["tracks"].items():
            self.assertEqual(product["tracks"][track]["start"], column, track)
            self.assertEqual(product["tracks"][track]["durations"], info["durations"], track)
            self.assertEqual(product["tracks"][track]["facings"], info["facings"], track)
            self.assertEqual(product["tracks"][track]["loop"], info["loop"], track)
            column += len(info["durations"])
        for key in ("state_tracks", "slots", "default_look", "variation", "keys", "fixed", "frame_size", "pivot",
                    "facings", "side_faces", "layers", "density"):
            self.assertEqual(product[key], self.spec[key], key)
        self.assertEqual(product["schema_version"], 2)
        self.assertEqual(product["filter"], "nearest")
        self.assertFalse((OUTPUT / "manifest.json").exists(), "a manifest.json here would be taken for a theme")

    def test_the_sheet_count_is_the_formula(self):
        """Per facing S + L + T + G + Hs*Hc + W*Wc: every layer coloured by one slot, so the counts add."""
        slots = self.spec["slots"]
        count = (len(slots["skin"]["swatches"]) + len(slots["legs"]["swatches"]) + len(slots["top"]["swatches"])
                 + len(slots["glasses"]["shapes"])
                 + len(slots["hair_style"]["shapes"]) * len(slots["hair_colour"]["swatches"])
                 + len(slots["headwear"]["shapes"]) * len(slots["headwear_colour"]["swatches"]))
        self.assertEqual(len(self.product["strips"]), count)
        self.assertEqual(count, 47, "the memo's number for the shipped options")
        self.assertEqual(self.product["strips"], [name for name, _sheet, _targets in expected_strips(self.spec)])

    def test_every_facing_is_one_packed_sheet(self):
        self.assertEqual(self.product["files"], [f"{facing}.png" for facing in self.spec["facings"]])
        for facing in self.spec["facings"]:
            self.assertEqual(self.sheet(facing).size, (self.columns * self.width, len(self.product["strips"]) * self.height),
                             f"{facing}: every strip, one under the other, no gutter")

    def test_manifest_and_disk_name_the_same_files(self):
        on_disk = sorted(str(path.relative_to(OUTPUT)) for path in OUTPUT.rglob("*.png"))
        self.assertEqual(on_disk, sorted(self.product["files"]))
        for relative in self.product["files"]:
            self.assertTrue((OUTPUT / (relative + ".import")).is_file(), f"{relative} ships with its .import")

    def test_mock_files_are_every_source_nobody_drew(self):
        sheets = sorted({sheet for _name, sheet, _targets in expected_strips(self.spec)},
                        key=lambda sheet: [s for _n, s, _t in expected_strips(self.spec)].index(sheet))
        sources = [f"{facing}/{sheet}.png" for facing in self.spec["facings"] for sheet in sheets]
        self.assertEqual(len(sources), 30, "10 sources per facing")
        painted = [relative for relative in sources if (SOURCE / relative).is_file()]
        # A skin paints into one strip of its facing: the head the body's, the
        # torso the top's, a hair style or hat its own.
        worn = {f"{path.parent.name}/{ {'head': 'body', 'torso': 'top'}.get(path.stem, path.stem)}.png"
                for path in (SOURCE / "skins").glob("*/*.png")}
        self.assertEqual(self.product["mock_files"], sorted(set(sources) - set(painted) - worn))

    # --- the pixels

    def test_every_strip_is_its_source_recoloured_exactly(self):
        """Each product pixel is the source pixel's target; alpha is untouched."""
        for facing in self.spec["facings"]:
            for name, sheet, targets in expected_strips(self.spec):
                source = source_of(self.spec, facing, sheet)
                mapped = colour_map(self.spec, targets)
                product = self.strip(facing, name)
                self.assertEqual(product.size, source.size)
                src, out = source.load(), product.load()
                for y in range(source.height):
                    for x in range(source.width):
                        r, g, b, a = src[x, y]
                        self.assertEqual(out[x, y][3], a, f"{facing} {name} ({x},{y}) alpha")
                        if a == 0:
                            continue
                        self.assertIn((r, g, b), mapped, f"{facing} {name} ({x},{y}) is an unmapped key")
                        self.assertEqual(out[x, y][:3], mapped[(r, g, b)], f"{facing} {name} ({x},{y})")

    def test_hard_alpha_and_only_palette_colours(self):
        palette = {rgb(colour) for colour in self.spec["fixed"].values()}
        for info in self.spec["slots"].values():
            for ramp in info.get("swatches", {}).values():
                palette |= {rgb(colour) for colour in ramp}
        keys = {rgb(colour) for ramp in self.spec["keys"].values() for colour in ramp}
        for facing in self.spec["facings"]:
            for _count, (r, g, b, a) in self.sheet(facing).getcolors(maxcolors=65536):
                self.assertIn(a, (0, 255), f"{facing}.png: soft alpha {a}")
                if a:
                    self.assertIn((r, g, b), palette, f"{facing}.png: #{r:02x}{g:02x}{b:02x} is no palette colour")
                    self.assertNotIn((r, g, b), keys - palette, f"{facing}.png: a key colour survived")

    def test_every_fill_stands_apart_from_the_ink(self):
        """A fill as dark as the outline merges with it: dark trousers, deep skin
        and black hair read as one blob. Every colour a product fills with (all
        but the ink and the eyes, which are meant to be dark) keeps its distance."""
        ink = rgb(self.spec["fixed"]["ink"])
        exempt = {ink, rgb(self.spec["fixed"]["eye"])}
        for facing in self.spec["facings"]:
            for _count, colour in self.sheet(facing).getcolors(maxcolors=65536):
                if colour[3] and colour[:3] not in exempt:
                    distance = sum((a - b) ** 2 for a, b in zip(colour[:3], ink)) ** 0.5
                    self.assertGreaterEqual(distance, MIN_INK_DISTANCE, f"{facing}.png: #{colour[0]:02x}{colour[1]:02x}"
                                            f"{colour[2]:02x} is {distance:.1f} from the ink")

    def test_columns_of_a_track_that_does_not_face_this_way_are_empty(self):
        for track, _index, column in frames(self.spec):
            for facing in self.spec["facings"]:
                if facing in self.spec["tracks"][track]["facings"]:
                    continue
                for name in self.product["strips"]:
                    box = self.frame(self.strip(facing, name), column).getchannel("A").getbbox()
                    self.assertIsNone(box, f"{facing} {name}: {track} does not face {facing}")

    def test_feet_are_on_the_ground_in_every_frame(self):
        """The lowest opaque row of every figure frame is the last texel row of
        the unit above the pivot: a walk bobs the body, never the ground foot."""
        ground = self.spec["pivot"][1] * self.d - 1
        for facing in self.spec["facings"]:
            figure = self.look(facing)
            for track, index, column in frames(self.spec):
                if facing not in self.spec["tracks"][track]["facings"]:
                    continue
                box = self.frame(figure, column).getchannel("A").getbbox()
                self.assertIsNotNone(box, f"{track}/{facing} frame {index} is drawn")
                self.assertEqual(box[3] - 1, ground, f"{track}/{facing} frame {index}: feet off the ground")

    def test_legs_top_and_body_are_the_one_figure_split(self):
        """The three figure layers never overlap and together are the whole
        placeholder figure, pixel for pixel, whatever order they are drawn in."""
        for facing in self.spec["facings"]:
            parts = [source_of(self.spec, facing, layer) for layer in BASE]
            alphas = [part.getchannel("A").load() for part in parts]
            width, height = parts[0].size
            overlap = [(x, y) for y in range(height) for x in range(width) if sum(1 for a in alphas if a[x, y]) > 1]
            self.assertEqual(overlap[:3], [], f"{facing}: a pixel on two figure layers")
            if not any((SOURCE / facing / f"{layer}.png").is_file() for layer in BASE):
                whole = Image.new("RGBA", (width, height), (0, 0, 0, 0))
                for part in reversed(parts):
                    whole = Image.alpha_composite(whole, part)
                figure = draw_figure(self.spec, facing, load_skins(SOURCE, self.spec))
                self.assertEqual(whole.tobytes(), figure.tobytes(), f"{facing}: the split loses nothing")

    def test_a_hat_covers_the_hair_above_its_brim(self):
        """Recomputed from the shipped strips: under every hat that does not hide
        the hair, no hair pixel shows above the hat's lowest row."""
        default = self.spec["default_look"]
        for facing in self.spec["facings"]:
            for hat, flags in self.spec["slots"]["headwear"]["shapes"].items():
                if flags.get("hides_hair"):
                    continue
                cap = self.strip(facing, f"headwear_{hat}_{default['headwear_colour']}")
                for style in self.spec["slots"]["hair_style"]["shapes"]:
                    hair = self.strip(facing, f"hair_{style}_{default['hair_colour']}")
                    for _track, _index, column in frames(self.spec):
                        top = self.frame(cap, column).getchannel("A")
                        box = top.getbbox()
                        if box is None:
                            continue
                        covered, strands = top.load(), self.frame(hair, column).getchannel("A").load()
                        # The brim is the hat's lowest unit row; the hair above it is covered.
                        brim = (box[3] - 1) // self.d * self.d
                        shown = [(x, y) for y in range(brim) for x in range(self.width) if strands[x, y] and not covered[x, y]]
                        self.assertEqual(shown, [], f"{facing} {style} under {hat}, column {column}")

    def test_outline_is_continuous_ink(self):
        """Every opaque pixel with a transparent 4-neighbour, of every layer of
        every shape combination together, is the ink outline: no fill colour
        touches the air."""
        ink = rgb(self.spec["fixed"]["ink"])
        for facing in self.spec["facings"]:
            for hair, headwear, glasses in self.combinations():
                look = self.look(facing, hair, headwear, glasses)
                pixels = look.load()
                for x, y in opaque(look):
                    edge = any(not (0 <= x + dx < look.width and 0 <= y + dy < look.height)
                               or pixels[x + dx, y + dy][3] == 0 for dx, dy in N4)
                    if edge:
                        self.assertEqual(pixels[x, y][:3], ink, f"{facing} {hair}/{headwear}/{glasses} ({x},{y})")

    def test_frames_stay_inside_the_canvas_with_a_clear_edge(self):
        """Nothing is cut by the frame edge: a column's outermost pixels are
        empty, so a mirrored or neighbouring frame never bleeds."""
        for facing in self.spec["facings"]:
            for name in self.product["strips"]:
                image = self.strip(facing, name)
                for track, index, column in frames(self.spec):
                    box = self.frame(image, column).getchannel("A").getbbox()
                    if box is None:
                        continue
                    self.assertGreater(box[0], 0, f"{facing} {name} {track} {index} touches the left edge")
                    self.assertLess(box[2], self.width, f"{facing} {name} {track} {index} touches the right edge")
                    self.assertGreater(box[1], 0, f"{facing} {name} {track} {index} touches the top edge")

    def test_eyes_show_from_the_front_and_the_side_only(self):
        """Two 1x2-unit eyes from the front, one from the side, none from
        behind; each with its catchlight texel when people.json names one."""
        eye = rgb(self.spec["fixed"]["eye"])
        catch = self.spec["fixed"].get("catchlight")
        lights = rgb(catch) if catch is not None and self.d >= 2 else None
        expected = {"front": 4, "back": 0, "side": 2}
        body = f"body_{self.spec['default_look']['skin']}"
        for track, index, column, facing in self.drawn():
            frame = self.frame(self.strip(facing, body), column)
            colours = {colour[:3]: number for number, colour in frame.getcolors() if colour[3]}
            count = colours.get(eye, 0) + (colours.get(lights, 0) if lights else 0)
            self.assertEqual(count, expected[facing] * self.d * self.d, f"{track}/{facing} frame {index}: 1x2 eyes")
            if lights:
                self.assertEqual(colours.get(lights, 0), expected[facing] // 2, f"{track}/{facing} {index}: a catchlight an eye")

    def test_glasses_never_cover_an_eye(self):
        eye = {rgb(self.spec["fixed"][name]) for name in ("eye", "catchlight") if name in self.spec["fixed"]}
        body = f"body_{self.spec['default_look']['skin']}"
        for facing in self.spec["facings"]:
            eyes = self.strip(facing, body).load()
            for shape in self.spec["slots"]["glasses"]["shapes"]:
                glasses = self.strip(facing, f"glasses_{shape}").load()
                for track, index, column, drawn in self.drawn():
                    if drawn != facing:
                        continue
                    for y in range(self.height):
                        for x in range(column * self.width, (column + 1) * self.width):
                            if eyes[x, y][3] and eyes[x, y][:3] in eye:
                                self.assertEqual(glasses[x, y][3], 0, f"{facing} {shape} {track} {index}: an eye at ({x},{y})")

    def test_a_raised_hand_is_above_the_head(self):
        default = self.spec["default_look"]
        skin = {rgb(colour) for colour in self.spec["slots"]["skin"]["swatches"][default["skin"]]}
        for track in ("desk_blocked", "stand_blocked"):
            start = self.product["tracks"][track]["start"]
            for facing in self.spec["tracks"][track]["facings"]:
                body = self.strip(facing, f"body_{default['skin']}")
                for index in range(len(self.spec["tracks"][track]["durations"])):
                    frame = self.frame(body, start + index)
                    pixels = frame.load()
                    hand = min(y for x, y in opaque(frame) if pixels[x, y][:3] in skin)
                    for hair, headwear, _glasses in self.combinations():
                        head = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 0))
                        if hair != "none":
                            head = Image.alpha_composite(head, self.frame(self.strip(facing, f"hair_{hair}_{default['hair_colour']}"), start + index))
                        if headwear != "none":
                            head = Image.alpha_composite(head, self.frame(self.strip(facing, f"headwear_{headwear}_{default['headwear_colour']}"), start + index))
                        box = head.getchannel("A").getbbox()
                        if box is None:
                            continue
                        self.assertLess(hand, box[1] - self.d, f"{track}/{facing} {index} {hair}/{headwear}: the hand clears the head")

    def test_walk_bobs_one_pixel_on_the_passing_frames(self):
        hair_strip = f"hair_short_{self.spec['default_look']['hair_colour']}"
        for track in ("walk", "carry_walk"):
            start = self.product["tracks"][track]["start"]
            for facing in self.spec["tracks"][track]["facings"]:
                hair = self.strip(facing, hair_strip)
                tops = [self.frame(hair, start + index).getchannel("A").getbbox()[1] for index in range(4)]
                self.assertEqual(tops[0], tops[2], f"{track}/{facing}: the two contacts stand as high")
                self.assertEqual(tops[1], tops[3], f"{track}/{facing}: the two passings stand as high")
                self.assertEqual(tops[0] - tops[1], self.d, f"{track}/{facing}: a passing frame is one unit up")

    def test_typing_hands_alternate_by_one_pixel(self):
        default = self.spec["default_look"]
        skin = {rgb(colour) for colour in self.spec["slots"]["skin"]["swatches"][default["skin"]]}
        start = self.product["tracks"]["desk_work"]["start"]
        body = self.strip("front", f"body_{default['skin']}")
        centre = self.width // 2

        def hands(index: int) -> tuple[int, int]:
            frame = self.frame(body, start + index)
            pixels = frame.load()
            rows = [(x, y) for x, y in opaque(frame) if pixels[x, y][:3] in skin and y > 24 * self.d]
            left = max(y for x, y in rows if x < centre)
            right = max(y for x, y in rows if x >= centre)
            return left, right

        left_up, right_down = hands(0)
        left_down, right_up = hands(2)
        self.assertEqual((left_down - left_up, right_down - right_up), (self.d, self.d), "each hand lifts one unit in turn")
        self.assertEqual(hands(1), hands(3), "the two rests are the same pose")

    def test_left_is_the_side_mirrored_about_the_feet(self):
        """flip_h mirrors a frame about its centre; the pivot is that centre, so a
        mirrored figure keeps its feet on the same spot."""
        self.assertEqual(self.spec["pivot"][0] * 2, self.spec["frame_size"][0])

    # --- the build

    def test_a_second_build_changes_nothing(self):
        with tempfile.TemporaryDirectory() as work:
            copy_dir = Path(work) / "pixel_people"
            shutil.copytree(OUTPUT, copy_dir)
            before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in copy_dir.rglob("*") if path.is_file()}
            build(SOURCE, copy_dir)
            after = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in copy_dir.rglob("*") if path.is_file()}
            self.assertEqual(after, before)

    def test_two_fresh_builds_write_the_same_bytes(self):
        with tempfile.TemporaryDirectory() as work:
            first, second = Path(work) / "a", Path(work) / "b"
            build(SOURCE, first)
            build(SOURCE, second)
            files = sorted(path.relative_to(first) for path in first.rglob("*") if path.is_file())
            self.assertEqual(files, sorted(path.relative_to(second) for path in second.rglob("*") if path.is_file()))
            for relative in files:
                self.assertEqual((first / relative).read_bytes(), (second / relative).read_bytes(), str(relative))

    def test_a_sheet_the_manifest_no_longer_names_is_pruned(self):
        with tempfile.TemporaryDirectory() as work:
            copy_dir = Path(work) / "pixel_people"
            shutil.copytree(OUTPUT, copy_dir)
            stray = copy_dir / "front" / "hair_mohawk.png"
            stray.parent.mkdir(parents=True, exist_ok=True)
            Image.new("RGBA", (4, 4)).save(stray)
            (copy_dir / "front" / "hair_mohawk.png.import").write_text("[remap]\n")
            result = subprocess.run([sys.executable, str(BUILDER), "--output", str(copy_dir)],
                                    capture_output=True, text=True, cwd=ROOT)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PRUNED:", result.stdout)
            self.assertIn("front/hair_mohawk.png", result.stdout)
            self.assertFalse(stray.exists())
            self.assertFalse((copy_dir / "front" / "hair_mohawk.png.import").exists())
            self.assertTrue((copy_dir / "front.png.import").exists(), "a named sheet keeps its .import")


class HandDrawnSourceTests(unittest.TestCase):
    """A painted source replaces the placeholder and goes through the same checks."""

    RELATIVE = "front/top.png"

    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.source = Path(self.work.name) / "source"
        self.output = Path(self.work.name) / "output"
        self.source.mkdir()
        shutil.copyfile(SOURCE / SPEC_NAME, self.source / SPEC_NAME)
        self.spec = load(SOURCE / SPEC_NAME)
        self.d = self.spec["density"]

    def tearDown(self):
        self.work.cleanup()

    def product(self) -> dict:
        return load(self.output / PRODUCT_NAME)

    def run_builder(self) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(BUILDER), "--source", str(self.source), "--output", str(self.output)],
                              capture_output=True, text=True, cwd=ROOT)

    def top_strip(self, swatch: str) -> bytes:
        product = self.product()
        row = product["strips"].index(f"top_{swatch}")
        width = product["columns"] * self.spec["frame_size"][0] * self.d
        height = self.spec["frame_size"][1] * self.d
        with Image.open(self.output / "front.png") as image:
            return image.convert("RGBA").crop((0, row * height, width, (row + 1) * height)).tobytes()

    def painted(self) -> Image.Image:
        """The placeholder with a painter's change: every mid-tone top pixel of
        the first frame repainted in the top's light key (still key colours)."""
        image = draw_placeholder(self.spec, "front", "top")
        mid, light = rgb(self.spec["keys"]["top"][1]), rgb(self.spec["keys"]["top"][0])
        pixels = image.load()
        for y in range(image.height):
            for x in range(self.spec["frame_size"][0] * self.d):
                if pixels[x, y][:3] == mid and pixels[x, y][3] == 255:
                    pixels[x, y] = (*light, 255)
        return image

    def test_placeholder_then_painted_then_placeholder_again(self):
        build(self.source, self.output)
        self.assertIn(self.RELATIVE, self.product()["mock_files"])
        mock_pixels = self.top_strip("slate")

        target = self.source / self.RELATIVE
        target.parent.mkdir(parents=True)
        self.painted().save(target)
        build(self.source, self.output)
        self.assertNotIn(self.RELATIVE, self.product()["mock_files"])
        self.assertEqual(len(self.product()["mock_files"]), 29)
        mapped = colour_map(self.spec, {"top": self.spec["slots"]["top"]["swatches"]["slate"]})
        expected = self.painted()
        pixels = expected.load()
        for y in range(expected.height):
            for x in range(expected.width):
                r, g, b, a = pixels[x, y]
                if a:
                    pixels[x, y] = (*mapped[(r, g, b)], a)
        self.assertEqual(self.top_strip("slate"), expected.tobytes(), "the product is the painted source")
        self.assertNotEqual(self.top_strip("slate"), mock_pixels)

        target.unlink()
        build(self.source, self.output)
        self.assertIn(self.RELATIVE, self.product()["mock_files"])
        self.assertEqual(self.top_strip("slate"), mock_pixels, "the placeholder is back")

    def refuse(self, image: Image.Image, rule: str, relative: str = RELATIVE):
        target = self.source / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
        result = self.run_builder()
        self.assertNotEqual(result.returncode, 0, f"{rule}: the build should refuse it")
        self.assertIn("PEOPLE_BUILD_FAILED", result.stderr)
        self.assertIn(relative, result.stderr, "the refusal names the picture")
        self.assertIn(rule, result.stderr, "the refusal names the rule")
        target.unlink()

    def test_a_colour_that_is_no_key_is_refused(self):
        image = self.painted()
        image.putpixel((16 * self.d, 30 * self.d), (1, 2, 3, 255))
        self.refuse(image, f"({16 * self.d}, {30 * self.d}) is #010203")

    def test_soft_alpha_is_refused(self):
        image = self.painted()
        colour = image.getpixel((16 * self.d, 30 * self.d))
        image.putpixel((16 * self.d, 30 * self.d), (*colour[:3], 128))
        self.refuse(image, "semi-transparent")

    def test_a_strip_of_the_wrong_size_is_refused(self):
        self.refuse(self.painted().crop((0, 0, 64, 48)), "is not the")

    def test_a_frame_in_a_facing_the_track_does_not_draw_is_refused(self):
        image = draw_placeholder(self.spec, "side", "legs")
        column = sum(len(info["durations"]) for track, info in self.spec["tracks"].items()
                     if list(self.spec["tracks"]).index(track) < list(self.spec["tracks"]).index("desk_idle"))
        image.putpixel(((column * 32 + 16) * self.d, 40 * self.d), (*rgb(self.spec["fixed"]["ink"]), 255))
        self.refuse(image, "desk_idle does not face side", "side/legs.png")

    def test_a_hat_key_on_a_hair_is_refused(self):
        image = draw_placeholder(self.spec, "front", "hair_short")
        image.putpixel((16 * self.d, 10 * self.d), (*rgb(self.spec["keys"]["hat"][1]), 255))
        self.refuse(image, "not a key or fixed colour of hair_short", "front/hair_short.png")

    def test_a_skin_key_on_the_top_layer_is_refused(self):
        """One role per layer: skin painted on the top would make the top a
        skin x top product."""
        image = self.painted()
        image.putpixel((16 * self.d, 30 * self.d), (*rgb(self.spec["keys"]["skin"][1]), 255))
        self.refuse(image, "not a key or fixed colour of top")

    def test_hair_above_a_cap_s_brim_is_refused(self):
        image = draw_placeholder(self.spec, "front", "hair_short")
        # The first frame's head is at (11, 11); the hair starts two rows above
        # it. Two rows higher still is outside every cap.
        image.putpixel((16 * self.d, 6 * self.d), (*rgb(self.spec["keys"]["hair"][1]), 255))
        self.refuse(image, "above the brim", "front/hair_short.png")

    def test_an_empty_frame_on_a_figure_layer_is_refused(self):
        image = draw_placeholder(self.spec, "front", "body")
        pixels = image.load()
        for y in range(image.height):
            for x in range(self.spec["frame_size"][0] * self.d):
                pixels[x, y] = (0, 0, 0, 0)
        self.refuse(image, "faces front but is empty", "front/body.png")

    def test_a_png_the_contract_does_not_name_is_refused(self):
        self.refuse(self.painted(), "the contract does not name", "front/hat_tophat.png")


# The density-1 white model the texel painter must keep drawing byte for byte:
# sha256 of each packed sheet's RGBA pixels, built from people.json at density 1
# with the whole-cell ring, one set per raised hand the builder can draw
# (people.json's `raised_hand`). A change to what
# people.json draws (a key, a swatch, a track) re-pins these, and says so in its commit.
DENSITY_ONE_SHEETS = {
    "straight": {
        "front": "9963f7e6ee7b1f4ae3f9593b1ddc35272497837de4c03b9bde1eeaa838e804c4",
        "back": "57b93962fa943159df01041fd09d3b559304cd9739d28cacd2ec935d218aebc2",
        "side": "2979db078cd9a5207b4e0ba34ff5d35ea27752ce86a6f243196fd4c108b57303",
    },
    "bent": {
        "front": "22149f6dc00f8a77721d67fdba63849305a748d02ec6c0fc781cad3371b7d040",
        "back": "09cf04c68ddae99638399819dc982af85ba04cb896ea659fa780105befae616c",
        "side": "9ac40e0773b446dbd86798d5ff066cfb86ac2b0d700a1bd89c4de2dbe89bd1a3",
    },
}
RAISED_HANDS = ("straight", "bent")


def shipped_hand() -> str:
    """The raised hand the shipped people.json draws (absent: the straight arm)."""
    return load(SOURCE / SPEC_NAME).get("raised_hand", "straight")


def spec_at(density: int, ring_texels: int | None = None, raised_hand: str | None = None) -> dict:
    """The shipped contract at `density`, with a ring of `ring_texels` (none
    given: no ring_texels, so the whole cell) and the raised hand `raised_hand`
    (none given: the one people.json ships)."""
    spec = load(SOURCE / SPEC_NAME)
    spec["density"] = density
    spec.pop("ring_texels", None)
    if ring_texels is not None:
        spec["ring_texels"] = ring_texels
    if raised_hand is not None:
        spec["raised_hand"] = raised_hand
    return spec


def sheets_of(output: Path, spec: dict) -> dict[str, Image.Image]:
    found = {}
    for facing in spec["facings"]:
        with Image.open(output / f"{facing}.png") as opened:
            found[facing] = opened.convert("RGBA")
    return found


class DensityTests(unittest.TestCase):
    """The rig paints cells as density x density texel blocks: the white model is
    the same figure at every density, only finer texels."""

    def build_at(self, work: Path, density: int, raised_hand: str | None = None) -> dict[str, Image.Image]:
        source, output = work / f"source{density}{raised_hand or ''}", work / f"output{density}{raised_hand or ''}"
        source.mkdir()
        spec = spec_at(density, raised_hand=raised_hand)
        (source / SPEC_NAME).write_text(json.dumps(spec))
        build(source, output)
        return sheets_of(output, spec)

    def test_density_one_output_is_unchanged_by_the_texel_painter(self):
        """Both raised hands, each against its own pinned sheets."""
        for hand in RAISED_HANDS:
            with self.subTest(raised_hand=hand), tempfile.TemporaryDirectory() as work:
                sheets = self.build_at(Path(work), 1, hand)
                for facing, digest in DENSITY_ONE_SHEETS[hand].items():
                    self.assertEqual(hashlib.sha256(sheets[facing].tobytes()).hexdigest(), digest, f"{hand} {facing}")

    def test_the_ring_is_a_whole_cell_unless_asked(self):
        """The white model's ink ring is density texels thick unless people.json's
        ring_texels (or the caller) asks for fewer: the whole cell is what keeps
        the density-2 figure the density-1 one doubled. A ring is 1 to density texels."""
        self.assertEqual(Painter(spec_at(2)).ring_texels, 2)
        self.assertEqual(Painter(spec_at(1)).ring_texels, 1)
        self.assertEqual(Painter(spec_at(2, 1)).ring_texels, 1, "people.json's ring_texels")
        self.assertEqual(Painter(spec_at(2), ring_texels=1).ring_texels, 1)
        self.assertEqual(Painter(spec_at(2, 1), ring_texels=2).ring_texels, 2, "the caller over people.json")
        for value in (0, 3, 1.0, "1"):
            with self.subTest(ring_texels=value), self.assertRaisesRegex(PeopleError, "a ring is 1 to 2 texels"):
                Painter(spec_at(2), ring_texels=value)

    def test_a_thinner_ring_is_the_ring_cell_s_outer_texel(self):
        """ring_texels below the density inks the texels of each ring cell on
        its outer side; the texels nearer the part take the part's colour and
        layer (a skin's, where one is worn), and the texel between two of those
        round a convex corner is ink, so the fill never touches the air. One
        cell at density 2: a 1-texel ring round a 4x4 fill with its corners cut,
        on exactly the outline the whole-cell ring draws, plus those corners."""
        spec = spec_at(2)
        ink = rgb(spec["fixed"]["ink"])
        block = {(10, 10), (11, 10), (10, 11), (11, 11)}
        whole = {(x, y) for x in range(8, 14) for y in range(8, 14) if (x in (10, 11)) != (y in (10, 11))}
        outer = {(8, 10), (8, 11), (13, 10), (13, 11), (10, 8), (11, 8), (10, 13), (11, 13)}
        corners = {(9, 9), (12, 9), (9, 12), (12, 12)}
        inner = {(9, 10), (9, 11), (12, 10), (12, 11), (10, 9), (11, 9), (10, 12), (11, 12)}
        skin = Image.new("RGBA", (2, 2), (*rgb(spec["keys"]["top"][2]), 255))
        for thickness, worn, inked, grown in ((2, None, whole, set()), (1, None, outer | corners, inner),
                                              (1, SkinAt(skin, (5, 5), "top"), outer | corners, inner)):
            with self.subTest(ring_texels=thickness, skin=worn is not None):
                painter = Painter(spec, ring_texels=thickness)
                painter.stamp({(5, 5): "t"}, skin=worn)
                self.assertEqual({texel for texel, colour in painter.pixels.items() if colour == ink}, inked)
                self.assertEqual(set(painter.pixels) - inked, block | grown, "the fill is the cell and the inner texels")
                fill = {painter.pixels[texel] for texel in block}
                self.assertEqual(len(fill), 1)
                self.assertEqual({painter.pixels[texel] for texel in grown} - fill, set(), "an inner texel is the fill's")
                if worn is not None:
                    self.assertEqual(fill, {rgb(spec["keys"]["top"][2])}, "the skin's colour, out to the ink")
                self.assertEqual({painter.owners[texel] for texel in painter.pixels}, {"top"}, "all the part's layer's")

    def test_a_thin_ring_s_corner_never_covers_an_eye(self):
        """The corner texel lies in a cell the whole ring never paints, so it
        may land on a part drawn before: there it is ink, except on an eye,
        which always shows (the cup at the mouth sits diagonally next to one)."""
        spec = spec_at(2, 1)
        ink, eye = rgb(spec["fixed"]["ink"]), rgb(spec["fixed"]["eye"])
        # A skin that paints the eye colour on the head is no eye: the ink goes on it.
        painted = Image.new("RGBA", (4, 4), (*eye, 255))
        for letter, skin, expected in (("s", None, ink), ("e", None, eye), ("s", SkinAt(painted, (6, 3), "body"), ink)):
            with self.subTest(under=letter, skin=skin is not None):
                painter = Painter(spec)
                painter.stamp({(6, 4): letter, (7, 4): "s", (6, 3): "s", (7, 3): "s"}, ring=False, skin=skin)
                if skin is not None:
                    self.assertEqual(painter.pixels[(12, 9)], eye, "the skin painted the eye colour there")
                painter.stamp({(5, 5): "t"})
                self.assertEqual(painter.pixels[(12, 9)], expected)

    def test_a_thin_ring_keeps_every_frame_s_envelope(self):
        """What the office measured on the figure does not move with the ring:
        built with a 1-texel ring, every frame of the whole figure (legs, top
        and body together) and of every hair, hat and glasses strip has the
        bounding box it has with the whole cell (so the feet row too), covers
        every texel it covered, and what it adds is ink (the corners). One
        figure layer alone may gain a corner texel the whole ring left to a
        part drawn over it (a shoulder beside a nodding chin)."""
        with tempfile.TemporaryDirectory() as work:
            sheets, product = {}, {}
            for ring in (2, 1):
                source, output = Path(work) / f"source{ring}", Path(work) / f"output{ring}"
                source.mkdir()
                spec = spec_at(2, ring)
                (source / SPEC_NAME).write_text(json.dumps(spec))
                product = build(source, output)
                sheets[ring] = sheets_of(output, spec)
        ink = rgb(spec["fixed"]["ink"])
        width, height = (value * 2 for value in spec["frame_size"])
        strips = product["strips"]
        # One swatch of each figure layer is the figure; every swatch has its alpha.
        figure = [next(name for name in strips if name.startswith(f"{layer}_")) for layer in BASE]
        shapes = [name for name in strips if name.split("_", 1)[0] not in BASE]

        def row(sheet: Image.Image, name: str) -> Image.Image:
            top = strips.index(name) * height
            return sheet.crop((0, top, sheet.width, top + height))

        for facing in spec["facings"]:
            pictures = {}
            for ring in (2, 1):
                whole = Image.new("RGBA", (sheets[ring][facing].width, height), (0, 0, 0, 0))
                for name in figure:
                    whole = Image.alpha_composite(whole, row(sheets[ring][facing], name))
                pictures[ring] = {"figure": whole, **{name: row(sheets[ring][facing], name) for name in shapes}}
            for name, before in pictures[2].items():
                after = pictures[1][name]
                for left in range(0, before.width, width):
                    box = (left, 0, left + width, height)
                    self.assertEqual(after.crop(box).getchannel("A").getbbox(), before.crop(box).getchannel("A").getbbox(),
                                     f"{facing} {name} frame {left // width}")
                was, now = before.getchannel("A").load(), after.load()
                added = [(x, y) for y in range(height) for x in range(before.width) if now[x, y][3] and not was[x, y]]
                lost = [(x, y) for y in range(height) for x in range(before.width) if was[x, y] and not now[x, y][3]]
                self.assertEqual(lost[:3], [], f"{facing} {name}: the thin ring covers what the whole one did")
                self.assertEqual([texel for texel in added if now[texel][:3] != ink][:3], [],
                                 f"{facing} {name}: an added texel is ink")
            self.assertTrue(any(pictures[1]["figure"].getchannel("A").load()[x, y] and not
                                pictures[2]["figure"].getchannel("A").load()[x, y]
                                for y in range(height) for x in range(pictures[1]["figure"].width)), f"{facing}: the corners")

    def test_density_two_without_skins_is_density_one_scaled_by_nearest(self):
        """With the whole-cell ring the white model at 2x is 1x doubled, but for
        the catchlights (drawn at density 2 only, when people.json names the
        colour): a texel that differs is a catchlight over a doubled eye."""
        with tempfile.TemporaryDirectory() as work:
            one, two = self.build_at(Path(work), 1), self.build_at(Path(work), 2)
        fixed = load(SOURCE / SPEC_NAME)["fixed"]
        eye = (*rgb(fixed["eye"]), 255)
        catch = (*rgb(fixed["catchlight"]), 255) if "catchlight" in fixed else None
        for facing, sheet in one.items():
            scaled = sheet.resize((sheet.width * 2, sheet.height * 2), Image.Resampling.NEAREST)
            self.assertEqual(two[facing].size, scaled.size, facing)
            if catch is None:
                self.assertEqual(two[facing].tobytes(), scaled.tobytes(), f"{facing}: the white model at 2x is 1x doubled")
                continue
            got, want = two[facing].load(), scaled.load()
            differ = [(x, y) for y in range(scaled.height) for x in range(scaled.width) if got[x, y] != want[x, y]]
            self.assertEqual([t for t in differ if (got[t], want[t]) != (catch, eye)][:3], [],
                             f"{facing}: the white model at 2x is 1x doubled but for the catchlights")
            self.assertEqual(bool(differ), facing != "back", f"{facing}: catchlights where eyes show")


class RaisedHandTests(unittest.TestCase):
    """The two raised hands the builder draws (people.json's `raised_hand`, read
    by the builder alone): the straight arm and the bent one, the upper
    arm out from the shoulder, a forearm straight up, a sleeve cuff and a mitten
    with its thumb on top (docs/ASSET_SPEC.md, "Pixel people"). Both are built here
    at the shipped density and ring, wearing the shipped skins, whichever one
    people.json ships: each must clear every head and keep the envelope the
    office's labels were measured on (OfficeStation), and the bent one must bend."""

    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory()
        shipped = load(SOURCE / SPEC_NAME)
        cls.d = shipped["density"]
        cls.width, cls.height = (value * cls.d for value in shipped["frame_size"])
        cls.pivot = shipped["pivot"]
        cls.products, cls.sheets, cls.specs = {}, {}, {}
        for hand in (*RAISED_HANDS, "absent"):
            source = Path(cls.work.name) / f"source-{hand}"
            shutil.copytree(SOURCE, source)
            spec = spec_at(shipped["density"], shipped.get("ring_texels"), None if hand == "absent" else hand)
            if hand == "absent":
                spec.pop("raised_hand", None)
            (source / SPEC_NAME).write_text(json.dumps(spec))
            output = Path(cls.work.name) / f"output-{hand}"
            cls.products[hand] = build(source, output)
            cls.sheets[hand] = sheets_of(output, spec)
            cls.specs[hand] = spec

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def strip(self, hand: str, facing: str, name: str) -> Image.Image:
        top = self.products[hand]["strips"].index(name) * self.height
        sheet = self.sheets[hand][facing]
        return sheet.crop((0, top, sheet.width, top + self.height))

    def frame(self, hand: str, facing: str, names: list[str], column: int) -> Image.Image:
        picture = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 0))
        for name in names:
            strip = self.strip(hand, facing, name)
            picture = Image.alpha_composite(picture, strip.crop((column * self.width, 0, (column + 1) * self.width, self.height)))
        return picture

    def blocked(self, hand: str):
        """(track, facing, index, column) of every raised-hand frame."""
        for track in ("desk_blocked", "stand_blocked"):
            info = self.products[hand]["tracks"][track]
            for facing in info["facings"]:
                for index in range(len(info["durations"])):
                    yield track, facing, index, info["start"] + index

    def figure_names(self, hand: str) -> list[str]:
        look = self.specs[hand]["default_look"]
        return [f"legs_{look['legs']}", f"top_{look['top']}", f"body_{look['skin']}"]

    def swatch(self, hand: str, slot: str) -> list[tuple[int, int, int]]:
        spec = self.specs[hand]
        return [rgb(colour) for colour in spec["slots"][slot]["swatches"][spec["default_look"][slot]]]

    def test_the_key_is_straight_or_bent_and_only_the_builder_reads_it(self):
        spec = load(SOURCE / SPEC_NAME)
        for value in RAISED_HANDS:
            accepted = copy.deepcopy(spec)
            accepted["raised_hand"] = value
            validate(accepted, Path("people.json"))
        for value in ("curved", "", "Bent", True, 1, None):
            refused = copy.deepcopy(spec)
            refused["raised_hand"] = value
            with self.subTest(raised_hand=value), self.assertRaisesRegex(PeopleError, "raised_hand"):
                validate(refused, Path("people.json"))
        for hand, product in self.products.items():
            self.assertNotIn("raised_hand", product, f"{hand}: the product manifest does not carry it")
        for facing in self.sheets["straight"]:
            self.assertEqual(self.sheets["absent"][facing].tobytes(), self.sheets["straight"][facing].tobytes(),
                             f"{facing}: without the key the arm is the straight one")
        self.assertNotEqual(self.sheets["bent"]["front"].tobytes(), self.sheets["straight"]["front"].tobytes(),
                            "the bent arm is another drawing")

    def test_both_raised_hands_clear_every_head(self):
        """The topmost skin texel of the hand is more than a unit above the top of
        every hair style and hat, in every raised-hand frame of both arms."""
        for hand in RAISED_HANDS:
            spec = self.specs[hand]
            look = spec["default_look"]
            skin = set(self.swatch(hand, "skin"))
            slots = spec["slots"]
            for track, facing, index, column in self.blocked(hand):
                frame = self.frame(hand, facing, [f"body_{look['skin']}"], column)
                pixels = frame.load()
                top = min(y for x, y in opaque(frame) if pixels[x, y][:3] in skin)
                for hair in [*slots["hair_style"]["shapes"], "none"]:
                    for headwear in [*slots["headwear"]["shapes"], "none"]:
                        names = []
                        if hair != "none":
                            names.append(f"hair_{hair}_{look['hair_colour']}")
                        if headwear != "none":
                            names.append(f"headwear_{headwear}_{look['headwear_colour']}")
                        box = self.frame(hand, facing, names, column).getchannel("A").getbbox()
                        if box is None:
                            continue
                        self.assertLess(top, box[1] - self.d,
                                        f"{hand} {track}/{facing} {index} {hair}/{headwear}: the hand clears the head")

    def test_both_raised_hands_keep_the_envelope_the_office_measured(self):
        """OfficeStation's plate, badge and bubble were placed round a figure
        whose seated raised hand reaches y -40 from the feet and whose drawing
        stays within x -10..12 (units from the pivot, ink included): both arms
        stay inside, and the bent hand never stands higher than the straight one."""
        tops = {}
        for hand in RAISED_HANDS:
            for track, facing, index, column in self.blocked(hand):
                box = self.frame(hand, facing, self.figure_names(hand), column).getchannel("A").getbbox()
                left, top, right = (box[0] / self.d - self.pivot[0], box[1] / self.d - self.pivot[1],
                                    box[2] / self.d - self.pivot[0])
                where = f"{hand} {track}/{facing} {index}"
                print(f"RAISED_HAND_ENVELOPE {where}: x {left:g}..{right:g}, top {top:g}")
                tops[(hand, track, facing, index)] = top
                self.assertLessEqual(right, 12, f"{where}: the hand stays within x 12")
                self.assertGreaterEqual(left, -10, f"{where}: and the other side within -10")
                if track == "desk_blocked":
                    self.assertGreaterEqual(top, -40, f"{where}: a seated hand reaches no higher than -40")
        for (hand, track, facing, index), top in tops.items():
            if hand == "bent":
                self.assertGreaterEqual(top, tops[("straight", track, facing, index)],
                                        f"{track}/{facing} {index}: the bent hand stands no higher than the straight one")

    def test_the_bent_arm_bends_at_the_elbow_under_a_cuff_and_a_mitten(self):
        """From the front and the back: right of the head and torso (x from 22
        units) the hand is a mitten at least 3 units wide and tall whose top row
        is a thumb, a unit or less wide; the row under it is the sleeve's cuff,
        all in the top's lightest tone; under the cuff the forearm stands
        straight up for at least 4 units; and the upper arm reaches it from the
        shoulder on a diagonal, its foot 2 units or more nearer the body. From
        the side (stand_blocked) the hand is the same mitten with its thumb."""
        skin = set(self.swatch("bent", "skin"))
        top_tones = self.swatch("bent", "top")
        edge = 22 * self.d
        for track, facing, index, column in self.blocked("bent"):
            where = f"{track}/{facing} {index}"
            frame = self.frame("bent", facing, self.figure_names("bent"), column)
            pixels = frame.load()
            right = range(edge, self.width) if facing != "side" else range(self.width)
            hand = [(x, y) for x in right for y in range(self.height) if pixels[x, y][3] and pixels[x, y][:3] in skin]
            if facing == "side":
                # The face is skin too: the hand is what lies above the head's
                # top row of skin, which the hair covers from the side.
                crown = min(y for x, y in opaque(self.frame("bent", facing, [f"hair_short_{self.specs['bent']['default_look']['hair_colour']}"], column)))
                hand = [(x, y) for x, y in hand if y < crown]
            rows: dict[int, list[int]] = {}
            for x, y in hand:
                rows.setdefault(y, []).append(x)
            first, last = min(rows), max(rows)
            widest = max(max(xs) - min(xs) + 1 for xs in rows.values())
            self.assertGreaterEqual(widest, 3 * self.d, f"{where}: the mitten is 3 units wide")
            self.assertGreaterEqual(last - first + 1, 3 * self.d, f"{where}: and 3 tall")
            self.assertLessEqual(len(rows[first]), self.d, f"{where}: its top row is the thumb")
            if facing == "side":
                continue
            span = range(min(x for x, _y in hand), max(x for x, _y in hand) + 1)
            cuff = [pixels[x, last + 1][:3] for x in span if pixels[x, last + 1][:3] in top_tones]
            self.assertGreaterEqual(len(cuff), self.d, f"{where}: a cuff under the hand")
            self.assertEqual(set(cuff), {top_tones[0]}, f"{where}: the cuff is the top's lightest tone")
            sleeve = {}
            for y in range(last + 1, self.height):
                xs = [x for x in range(edge, self.width) if pixels[x, y][3] and pixels[x, y][:3] in top_tones]
                if not xs:
                    break
                sleeve[y] = min(xs)
            ys = sorted(sleeve)
            straight = 0
            while straight < len(ys) and sleeve[ys[straight]] == sleeve[ys[0]]:
                straight += 1
            self.assertGreaterEqual(straight, 4 * self.d, f"{where}: the forearm stands straight up: {sleeve}")
            self.assertGreaterEqual(sleeve[ys[0]] - sleeve[ys[-1]], 2 * self.d,
                                    f"{where}: the upper arm comes out from the shoulder to the elbow: {sleeve}")


class CatchlightTests(unittest.TestCase):
    """Every eye the rig draws carries a catchlight: its top-left texel in the
    fixed `catchlight` colour, the answer to the eye on deep skin
    (docs/ASSET_SPEC.md). Built at density 2 from a contract that names one."""

    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.spec = spec_at(2, load(SOURCE / SPEC_NAME).get("ring_texels"))
        self.spec["fixed"].setdefault("catchlight", FIXTURE_CATCHLIGHT)
        source = Path(self.work.name) / "source"
        source.mkdir()
        (source / SPEC_NAME).write_text(json.dumps(self.spec))
        self.output = Path(self.work.name) / "output"
        self.product = build(source, self.output)
        self.sheets = sheets_of(self.output, self.spec)

    def tearDown(self):
        self.work.cleanup()

    def strip(self, facing: str, name: str) -> Image.Image:
        top = self.product["strips"].index(name) * 96
        return self.sheets[facing].crop((0, top, self.sheets[facing].width, top + 96))

    def test_every_visible_eye_has_its_catchlight_under_every_head(self):
        """In every frame, each eye is a 2x4-texel block whose top-left texel is
        the catchlight and the rest the eye; and it still shows with every hair
        style, hat and pair of glasses drawn over it."""
        eye, catch = rgb(self.spec["fixed"]["eye"]), rgb(self.spec["fixed"]["catchlight"])
        expected = {"front": 2, "back": 0, "side": 1}
        slots = self.spec["slots"]
        overs = [None] + [f"hair_{style}_brown" for style in slots["hair_style"]["shapes"]] + \
                [f"headwear_{hat}_sea" for hat in slots["headwear"]["shapes"]] + \
                [f"glasses_{shape}" for shape in slots["glasses"]["shapes"]]
        for facing in self.spec["facings"]:
            body = self.strip(facing, "body_deep")
            for column, (track, index) in enumerate((t, i) for t, info in self.spec["tracks"].items()
                                                     for i in range(len(info["durations"]))):
                if facing not in self.spec["tracks"][track]["facings"]:
                    continue
                box = (column * 64, 0, column * 64 + 64, 96)
                frame = body.crop(box)
                pixels = frame.load()
                lit = [(x, y) for x, y in opaque(frame) if pixels[x, y][:3] == catch]
                self.assertEqual(len(lit), expected[facing], f"{track}/{facing} {index}: one catchlight an eye")
                for x, y in lit:
                    block = [pixels[x + i, y + j][:3] for j in range(4) for i in range(2)]
                    self.assertEqual(block, [catch] + [eye] * 7, f"{track}/{facing} {index}: the eye's top-left texel")
                for over in overs:
                    if over is None or over.startswith(("hair_", "headwear_")) and facing == "back":
                        continue
                    top = self.strip(facing, over).crop(box).load()
                    covered = [(x, y) for x, y in lit if top[x, y][3]]
                    self.assertEqual(covered, [], f"{track}/{facing} {index}: {over} covers a catchlight")

    def test_no_catchlight_at_density_one(self):
        """At density 1 an eye is two texels: naming the colour changes nothing."""
        spec = spec_at(1)
        spec["fixed"].setdefault("catchlight", FIXTURE_CATCHLIGHT)
        source = Path(self.work.name) / "one"
        source.mkdir()
        (source / SPEC_NAME).write_text(json.dumps(spec))
        build(source, Path(self.work.name) / "one-output")
        for facing, sheet in sheets_of(Path(self.work.name) / "one-output", spec).items():
            self.assertEqual(hashlib.sha256(sheet.tobytes()).hexdigest(), DENSITY_ONE_SHEETS[shipped_hand()][facing],
                             facing)


class SkinTests(unittest.TestCase):
    """A skin paints one part's fill texels and nothing else: the rig still
    places, rings and animates it. Run at density 2, the density skins are for."""

    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.source = Path(self.work.name) / "source"
        self.output = Path(self.work.name) / "output"
        self.source.mkdir()
        # The shipped ring: a thin one carries a skin's colours out to its ink.
        self.spec = spec_at(2, load(SOURCE / SPEC_NAME).get("ring_texels"))
        self.spec["fixed"].setdefault("catchlight", FIXTURE_CATCHLIGHT)
        self.d = 2
        (self.source / SPEC_NAME).write_text(json.dumps(self.spec))

    def tearDown(self):
        self.work.cleanup()

    def solid(self, facing: str, part: str, colour: tuple[int, int, int]) -> Image.Image:
        """A skin that paints every texel it may in one colour."""
        image = Image.new("RGBA", skin_size(self.spec, facing, part), (0, 0, 0, 0))
        for texel in skin_mask(self.spec, facing, part):
            image.putpixel(texel, (*colour, 255))
        return image

    def place(self, image: Image.Image, facing: str, part: str) -> None:
        target = self.source / "skins" / facing / f"{part}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)

    def head_boxes(self, facing: str) -> list[tuple[int, int, int, int]]:
        """Every drawn frame's head envelope in the strip, in texels, and the
        texels of its ring cells a ring thinner than a cell fills with the
        head's own (so the skin's) colours."""
        width, _height = (value * self.d for value in self.spec["frame_size"])
        size = skin_size(self.spec, facing, "head")
        grown = self.d - self.spec.get("ring_texels", self.d)
        boxes, column = [], 0
        for track, info in self.spec["tracks"].items():
            for pose in poses(track, len(info["durations"])):
                if facing in info["facings"]:
                    x, y = Figure(self.spec, pose, facing).head
                    left, top = column * width + x * self.d, y * self.d
                    boxes.append((left - grown, top - grown, left + size[0] + grown, top + size[1] + grown))
                column += 1
        return boxes

    def refuse(self, image: Image.Image, facing: str, part: str, rule: str) -> None:
        self.place(image, facing, part)
        result = subprocess.run([sys.executable, str(BUILDER), "--source", str(self.source), "--output", str(self.output)],
                                capture_output=True, text=True, cwd=ROOT)
        self.assertNotEqual(result.returncode, 0, f"{rule}: the build should refuse it")
        self.assertIn("PEOPLE_BUILD_FAILED", result.stderr)
        self.assertIn(f"skins/{facing}/{part}.png", result.stderr, "the refusal names the skin")
        self.assertIn(rule, result.stderr, "the refusal names the rule")

    def test_a_skin_replaces_the_part_and_nothing_else(self):
        light = rgb(self.spec["keys"]["skin"][0])
        bare = {sheet: draw_placeholder(self.spec, "front", sheet) for sheet in ("legs", "top", "body", "hair_short")}
        self.place(self.solid("front", "head", light), "front", "head")
        skins = load_skins(self.source, self.spec)
        worn = {sheet: draw_placeholder(self.spec, "front", sheet, skins) for sheet in bare}
        for sheet in ("legs", "top", "hair_short"):
            self.assertEqual(worn[sheet].tobytes(), bare[sheet].tobytes(), f"a head skin leaves {sheet} alone")
        before, after = bare["body"].load(), worn["body"].load()
        changed = [(x, y) for y in range(bare["body"].height) for x in range(bare["body"].width) if before[x, y] != after[x, y]]
        self.assertTrue(changed, "the skin shows")
        boxes = self.head_boxes("front")
        outside = [(x, y) for x, y in changed if not any(l <= x < r and t <= y < b for l, t, r, b in boxes)]
        self.assertEqual(outside[:3], [], "only the head's envelope changes")
        self.assertTrue(all(after[x, y] == (*light, 255) for x, y in changed), "a changed texel is the skin's")
        build(self.source, self.output)
        mocked = load(self.output / PRODUCT_NAME)["mock_files"]
        self.assertNotIn("front/body.png", mocked, "a strip wearing a skin is no longer a placeholder")
        self.assertIn("back/body.png", mocked, "a skin is per facing")
        self.assertIn("front/top.png", mocked)

    def test_eyes_are_painted_over_the_head_skin(self):
        """Eyes and their catchlights are the rig's, painted over any skin."""
        eye = {rgb(self.spec["fixed"]["eye"]), rgb(self.spec["fixed"]["catchlight"])}
        # Opaque on every head cell, the eyes included: the rig paints the eyes after.
        image = Image.new("RGBA", skin_size(self.spec, "front", "head"), (0, 0, 0, 0))
        for (x, y), letter in cells_of(HEAD_FRONT, 0, 0).items():
            for j in range(self.d):
                for i in range(self.d):
                    image.putpixel((x * self.d + i, y * self.d + j), (*rgb(self.spec["keys"]["skin"][2]), 255))
        self.place(image, "front", "head")
        bare = draw_placeholder(self.spec, "front", "body")
        worn = draw_placeholder(self.spec, "front", "body", load_skins(self.source, self.spec))

        def eyes(strip: Image.Image) -> list[tuple[tuple[int, int], tuple[int, ...]]]:
            return [((x, y), strip.getpixel((x, y))) for x, y in opaque(strip) if strip.getpixel((x, y))[:3] in eye]

        self.assertTrue(eyes(bare))
        self.assertIn(rgb(self.spec["fixed"]["catchlight"]), {colour[:3] for _texel, colour in eyes(bare)})
        self.assertEqual(eyes(worn), eyes(bare), "every eye and catchlight texel shows through the skin")

    def test_a_skin_outside_its_part_is_refused(self):
        light = rgb(self.spec["keys"]["skin"][0])
        corner = self.solid("front", "head", light)
        corner.putpixel((0, 0), (*light, 255))  # the head's rounded corner is no cell of it
        self.refuse(corner, "front", "head", "outside the cells of head")
        (self.source / "skins" / "front" / "head.png").unlink()
        top = rgb(self.spec["keys"]["top"][0])
        neck = self.solid("front", "torso", top)
        neck.putpixel((4 * self.d, 0), (*top, 255))  # the neckline is the body's skin
        self.refuse(neck, "front", "torso", "outside the cells of torso")

    def test_a_skin_with_the_eye_or_catchlight_colour_is_refused(self):
        """The eyes are the rig's: their colours in a skin read as a stray eye,
        even on the eye cells (which the rig paints over anyway)."""
        for name, texel in (("eye", (8, 8)), ("catchlight", (8, 8)), ("eye", (4, 10))):
            with self.subTest(colour=name, texel=texel):
                image = self.solid("front", "head", rgb(self.spec["keys"]["skin"][1]))
                image.putpixel(texel, (*rgb(self.spec["fixed"][name]), 255))
                self.refuse(image, "front", "head", f"pixel ({texel[0]}, {texel[1]}) is the {name} colour, which only the rig paints")
                (self.source / "skins" / "front" / "head.png").unlink()

    def test_a_skin_with_a_foreign_key_is_refused(self):
        self.refuse(self.solid("front", "head", rgb(self.spec["keys"]["top"][1])), "front", "head",
                    "not a key or fixed colour of the body layer")

    def test_a_skin_with_soft_alpha_or_the_wrong_size_is_refused(self):
        soft = self.solid("side", "hair_long", rgb(self.spec["keys"]["hair"][1]))
        x, y = next(iter(skin_mask(self.spec, "side", "hair_long")))
        soft.putpixel((x, y), (*rgb(self.spec["keys"]["hair"][1]), 128))
        self.refuse(soft, "side", "hair_long", "semi-transparent")
        self.refuse(Image.new("RGBA", (20, 20), (0, 0, 0, 0)), "back", "headwear_cap", "is not the")

    def test_a_png_under_skins_the_contract_does_not_name_is_refused(self):
        self.refuse(Image.new("RGBA", (4, 4), (0, 0, 0, 0)), "front", "nose", "the contract does not name")

    def test_every_part_has_a_canvas_its_cells_times_the_density(self):
        parts = skin_parts(self.spec)
        self.assertEqual(parts, ["head", "torso", "hair_short", "hair_curl", "hair_long", "headwear_cap", "headwear_hood"])
        self.assertEqual(skin_size(self.spec, "front", "head"), (20, 20))
        self.assertEqual(skin_size(self.spec, "side", "torso"), (16, 22))
        self.assertEqual(skin_size(self.spec, "side", "headwear_cap"), (28, 8))


class SkinCutTests(unittest.TestCase):
    """tools/people_skins.py cuts a painted frame into skins by the rig's own
    geometry, refusing what the rig cannot wear. The frames here are the white
    model's own, in key colours, as `reference` draws them and a painter would
    hand them back after pixelize.py. With the whole-cell ring; the subclass
    below runs every case again with a 1-texel one."""

    RING: int | None = None

    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.source = Path(self.work.name) / "source"
        self.source.mkdir()
        self.spec = spec_at(2, self.RING)
        (self.source / SPEC_NAME).write_text(json.dumps(self.spec))
        self.skins = self.source / "skins" / "front"
        self.width = self.spec["frame_size"][0] * 2

    def tearDown(self):
        self.work.cleanup()

    def frame(self, *wear: str) -> Path:
        picture = white_model(self.spec, "front", "stand_idle", 0, list(wear))
        return self.save(picture)

    def save(self, picture: Image.Image) -> Path:
        path = Path(self.work.name) / f"frame{len(list(Path(self.work.name).glob('frame*.png')))}.png"
        picture.save(path)
        return path

    def cut(self, picture: Path, parts: str) -> None:
        cut(picture, self.source, "front", parts.split(","), self.skins, "stand_idle", 0)

    def refused(self, picture: Path, parts: str, rule: str) -> None:
        with self.assertRaisesRegex(PeopleError, rule):
            self.cut(picture, parts)
        self.assertFalse(self.skins.exists() and any(self.skins.iterdir()), "nothing is written when a part is refused")

    def test_a_cut_skin_is_one_the_builder_takes(self):
        """The white model's own frame, cut into head and torso and worn, passes
        the builder's skin check and draws that frame exactly as before."""
        self.cut(self.frame(), "head,torso")
        skins = load_skins(self.source, self.spec)
        self.assertEqual(sorted(skins), [("front", "head"), ("front", "torso")])
        for sheet in ("top", "body"):
            bare = draw_placeholder(self.spec, "front", sheet).crop((0, 0, self.width, 96))
            worn = draw_placeholder(self.spec, "front", sheet, skins).crop((0, 0, self.width, 96))
            self.assertEqual(worn.tobytes(), bare.tobytes(), f"{sheet}: stand_idle frame 0 redrawn from its own skins")
        build(self.source, Path(self.work.name) / "output")
        result = subprocess.run([sys.executable, str(SKIN_CUTTER), "--check", "--source", str(self.source)],
                                capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PEOPLE_SKINS_OK: 2 skin(s)", result.stdout)

    def test_a_part_bigger_than_the_rig_s_is_refused(self):
        """A key of the part off its cells (the head's rounded corner) means the
        painted part does not fit the rig: refused, with the coordinates."""
        picture = white_model(self.spec, "front", "stand_idle", 0, [])
        x, y = (value * 2 for value in Figure(self.spec, poses("stand_idle", 2)[0], "front").head)
        picture.putpixel((x, y), (*rgb(self.spec["keys"]["skin"][1]), 255))
        self.refused(self.save(picture), "head", rf"pixel \({x}, {y}\) \(skin head \(0, 0\)\).*out of the envelope")

    def test_drop_outside_drops_and_lists_what_a_part_paints_off_its_cells(self):
        """--drop-outside: the texel a strict cut refuses is dropped and printed
        with its coordinates; the skin is the one the frame without it gives."""
        clean = white_model(self.spec, "front", "stand_idle", 0, [])
        picture = clean.copy()
        x, y = (value * 2 for value in Figure(self.spec, poses("stand_idle", 2)[0], "front").head)
        picture.putpixel((x, y), (*rgb(self.spec["keys"]["skin"][1]), 255))
        with contextlib.redirect_stdout(io.StringIO()) as printed:
            cut(self.save(picture), self.source, "front", ["head"], self.skins, "stand_idle", 0, drop_outside=True)
        self.assertIn(f"SKIN_DROPPED: {self.work.name}", printed.getvalue())
        self.assertIn(f"pixel ({x}, {y}) (skin head (0, 0))", printed.getvalue())
        with Image.open(self.skins / "head.png") as opened:
            dropped = opened.convert("RGBA")
        other = Path(self.work.name) / "strict"
        cut(self.save(clean), self.source, "front", ["head"], other, "stand_idle", 0)
        with Image.open(other / "head.png") as opened:
            self.assertEqual(dropped.tobytes(), opened.convert("RGBA").tobytes())

    def test_the_eyes_stay_the_rig_s(self):
        """A picture's eye colours: on the head's eye cells they are left to the
        rig (the white model's own frame has its eyes there and cuts clean); on
        any other texel of a part they are refused, never cut into a skin."""
        eyes = {rgb(self.spec["fixed"][name]) for name in ("eye", "catchlight") if name in self.spec["fixed"]}
        self.cut(self.frame(), "head")
        with Image.open(self.skins / "head.png") as opened:
            self.assertEqual({colour[:3] for _n, colour in opened.convert("RGBA").getcolors() if colour[3]} & eyes, set())
        (self.skins / "head.png").unlink()
        picture = white_model(self.spec, "front", "stand_idle", 0, [])
        x, y = (value * 2 for value in Figure(self.spec, poses("stand_idle", 2)[0], "front").skin_cell("torso"))
        picture.putpixel((x + 6, y + 6), (*rgb(self.spec["fixed"]["eye"]), 255))
        self.refused(self.save(picture), "head,torso", rf"pixel \({x + 6}, {y + 6}\) .* is the eye colour, which only the rig paints")

    def test_a_foreign_colour_on_a_part_is_refused(self):
        picture = white_model(self.spec, "front", "stand_idle", 0, [])
        x, y = (value * 2 for value in Figure(self.spec, poses("stand_idle", 2)[0], "front").head)
        picture.putpixel((x + 8, y + 8), (*rgb(self.spec["keys"]["top"][0]), 255))
        self.refused(self.save(picture), "head,torso", rf"pixel \({x + 8}, {y + 8}\) \(skin head \(8, 8\)\).*foreign")

    def test_the_hat_covers_the_hair_above_the_brim(self):
        """Hair painted inside the cap's cells becomes the cap's dark key: the
        cap skin covers every hair texel under it, and the build (whose brim
        check this is) takes it."""
        picture = white_model(self.spec, "front", "stand_idle", 0, ["hair_short", "headwear_cap"])
        x, y = (value * 2 for value in Figure(self.spec, poses("stand_idle", 2)[0], "front").skin_cell("headwear_cap"))
        hair = rgb(self.spec["keys"]["hair"][0])
        strands = [(x + 6, y + 2), (x + 7, y + 3), (x + 12, y + 6)]
        for texel in strands:
            picture.putpixel(texel, (*hair, 255))
        self.cut(self.save(picture), "headwear_cap")
        with Image.open(self.skins / "headwear_cap.png") as opened:
            skin = opened.convert("RGBA")
        dark = (*rgb(self.spec["keys"]["hat"][2]), 255)
        self.assertEqual([skin.getpixel((fx - x, fy - y)) for fx, fy in strands], [dark] * 3)
        self.assertNotIn(hair, {colour[:3] for _count, colour in skin.getcolors()})
        build(self.source, Path(self.work.name) / "output")

    def test_a_frame_off_the_rig_is_refused(self):
        picture = white_model(self.spec, "front", "stand_idle", 0, [])
        shifted = Image.new("RGBA", picture.size, (0, 0, 0, 0))
        shifted.alpha_composite(picture, (1, 0))
        self.refused(self.save(shifted), "head", r"is not the white model's .* \(left \+1, right \+1, top \+0, bottom \+0 texels\)")

    def test_a_side_frame_registers_against_the_look_it_shows(self):
        """From the side the figure is off the frame's centre and hair reaches
        back past it: a frame showing hair is registered against the white
        model wearing that hair (the default for a hair part), and refused
        against the bare figure."""
        picture = self.save(white_model(self.spec, "side", "stand_idle", 0, ["hair_short"]))
        with self.assertRaisesRegex(PeopleError, r"is not the white model's .* wearing no hair or hat \(left \-2"):
            cut(picture, self.source, "side", ["hair_short"], self.source / "skins" / "side", "stand_idle", 0, wear=[])
        cut(picture, self.source, "side", ["hair_short"], self.source / "skins" / "side", "stand_idle", 0)
        self.assertEqual(sorted(load_skins(self.source, self.spec)), [("side", "hair_short")])

    def test_the_hand_over_the_torso_from_the_side_is_left_to_the_rig(self):
        """From the side the near hand hangs over the torso's cells: in the
        white model's own side frame those texels are skin, the body layer's.
        The cut leaves them to the rig instead of calling them foreign, and the
        skins it makes redraw that frame unchanged."""
        picture = self.save(white_model(self.spec, "side", "stand_idle", 0, []))
        side = self.source / "skins" / "side"
        with contextlib.redirect_stdout(io.StringIO()) as printed:
            cut(picture, self.source, "side", ["head", "torso"], side, "stand_idle", 0)
        self.assertRegex(printed.getvalue(), r"torso\.png: .* [1-9][0-9]* under another layer in this frame left to the rig")
        skins = load_skins(self.source, self.spec)
        for sheet in ("top", "body"):
            bare = draw_placeholder(self.spec, "side", sheet).crop((0, 0, self.width, 96))
            worn = draw_placeholder(self.spec, "side", sheet, skins).crop((0, 0, self.width, 96))
            self.assertEqual(worn.tobytes(), bare.tobytes(), f"{sheet}: the side frame redrawn from its own skins")

    def test_reference_s_pixelize_arguments_land_on_the_white_model(self):
        """`reference` prints the pixelize.py arguments for its picture: fed its
        own x8 picture, pixelize puts back exactly the white model's texels,
        also from the side, where the figure is not centred on the frame."""
        pixelize = ROOT / ".claude" / "skills" / "painter" / "scripts" / "pixelize.py"
        for facing, wear in (("front", ""), ("side", ""), ("side", "hair_short,headwear_cap")):
            with self.subTest(facing=facing, wear=wear):
                work = Path(self.work.name) / f"ref-{facing}-{len(wear)}"
                work.mkdir()
                result = subprocess.run([sys.executable, str(SKIN_CUTTER), "--source", str(self.source), "reference",
                                         "--facing", facing, "--out", str(work / "ref.png"), "--wear", wear],
                                        capture_output=True, text=True, cwd=ROOT, check=True)
                args = next(line for line in result.stdout.splitlines() if line.startswith("PIXELIZE: "))
                subprocess.run([sys.executable, str(pixelize), str(work / "ref.png"), "--out", str(work / "px"), "--name", "p",
                                "--people", str(self.source / SPEC_NAME), *args.removeprefix("PIXELIZE: ").split()],
                               capture_output=True, text=True, cwd=ROOT, check=True)
                with Image.open(work / "px" / "p.png") as opened:
                    back = opened.convert("RGBA")
                expected = white_model(self.spec, facing, "stand_idle", 0, [w for w in wear.split(",") if w])
                self.assertEqual(back.getchannel("A").tobytes(), expected.getchannel("A").tobytes())
                self.assertEqual(back.tobytes(), expected.tobytes(), "and every colour: the key colours are the palette")

    def test_a_skin_is_never_overwritten(self):
        picture = self.frame()
        self.cut(picture, "head")
        with self.assertRaisesRegex(PeopleError, "never overwritten"):
            self.cut(picture, "head")


class ThinRingSkinCutTests(SkinCutTests):
    """The same cuts with a 1-texel ring, which carries a part's colours into
    its ring cells: the rig's own frame still cuts clean."""

    RING = 1


class ContractTests(unittest.TestCase):
    """A broken people.json fails at the boundary, before any PNG is written."""

    def refuses(self, mutate, rule):
        spec = load(SOURCE / SPEC_NAME)
        mutate(spec)
        with self.assertRaisesRegex(PeopleError, rule):
            validate(spec, Path("fixture/people.json"))

    def test_the_shipped_contract_is_valid(self):
        validate(load(SOURCE / SPEC_NAME), Path("people.json"))

    def test_schema_and_density(self):
        for value in (1, 3, "2", None, True):
            with self.subTest(value=value):
                self.refuses(lambda spec: spec.__setitem__("schema_version", value), "schema_version")
        for value in (0, 3, 4, "2", None, True):
            with self.subTest(density=value):
                self.refuses(lambda spec: spec.__setitem__("density", value), "density must be one of")

    def test_ring_texels_is_a_whole_number_up_to_the_density(self):
        for value in (0, 3, 1.0, "1", None, True):
            with self.subTest(ring_texels=value):
                self.refuses(lambda spec: spec.__setitem__("ring_texels", value), "ring_texels must be a whole number")
        self.refuses(lambda spec: spec.update(density=1, ring_texels=2), r"ring_texels must be .* \(1\)")
        for value in (1, 2):
            spec = load(SOURCE / SPEC_NAME)
            spec.update(density=2, ring_texels=value)
            validate(spec, Path("fixture/people.json"))
        spec = load(SOURCE / SPEC_NAME)
        spec.pop("ring_texels", None)
        validate(spec, Path("fixture/people.json"))

    def test_an_unknown_field_is_refused(self):
        self.refuses(lambda spec: spec.__setitem__("shadow", True), "unknown field")
        self.refuses(lambda spec: spec["tracks"]["walk"].__setitem__("fps", 8), "unknown field")
        self.refuses(lambda spec: spec.__setitem__("wear", {}), "unknown field")

    def test_a_pivot_off_the_centre_is_refused(self):
        self.refuses(lambda spec: spec.__setitem__("pivot", [15, 46]), "pivot x must be the frame's centre")

    def test_layers_must_be_the_prefab_s(self):
        self.refuses(lambda spec: spec.__setitem__("layers", ["body", "hair"]), "layers must be")
        self.refuses(lambda spec: spec.__setitem__("layers", list(reversed(LAYERS))), "layers must be")

    def test_a_track_facing_nowhere_known_is_refused(self):
        self.refuses(lambda spec: spec["tracks"]["walk"].__setitem__("facings", ["front", "up"]), "unknown facing")

    def test_a_track_must_draw_its_front_first(self):
        self.refuses(lambda spec: spec["tracks"]["walk"].__setitem__("facings", ["side", "front"]), "must start with front")

    def test_durations_must_be_finite_and_positive(self):
        for value in ([0.1, 0], [0.1, -1], [0.1, "0.2"], [], [1e309]):
            with self.subTest(value=value):
                self.refuses(lambda spec: spec["tracks"]["walk"].__setitem__("durations", value), "durations")

    def test_state_tracks_must_name_real_tracks_for_every_state(self):
        self.refuses(lambda spec: spec["state_tracks"]["desk"].__setitem__("working", "desk_typo"), "names no track")
        self.refuses(lambda spec: spec["state_tracks"]["stand"].pop("starting"), "must map every state")
        self.refuses(lambda spec: spec["state_tracks"].pop("desk"), "state_tracks.desk")

    def test_an_ambiguous_key_is_refused(self):
        def clash(spec):
            spec["keys"]["hat"][0] = spec["fixed"]["paper"]
        self.refuses(clash, "ambiguous")

    def test_ramps_are_three_lowercase_colours(self):
        self.refuses(lambda spec: spec["keys"]["skin"].pop(), "ramp of 3")
        self.refuses(lambda spec: spec["slots"]["top"]["swatches"]["teal"].pop(), "ramp of 3")
        self.refuses(lambda spec: spec["slots"]["top"]["swatches"].__setitem__("teal", ["FFFFFF", "000000", "111111"]),
                     "lowercase hex")

    def test_a_missing_or_unknown_slot_is_refused(self):
        self.refuses(lambda spec: spec["slots"].pop("glasses"), "slots must be exactly")
        self.refuses(lambda spec: spec["slots"].__setitem__("beard", {"layer": "hair", "shapes": {"full": {}}}),
                     "slots must be exactly")

    def test_slots_out_of_order_are_refused(self):
        def swap(spec):
            spec["slots"] = dict(reversed(list(spec["slots"].items())))
        self.refuses(swap, "in that order")

    def test_a_role_coloured_twice_is_refused(self):
        self.refuses(lambda spec: spec["slots"]["headwear_colour"].__setitem__("role", "top"), "already coloured")

    def test_a_layer_with_two_shape_slots_is_refused(self):
        self.refuses(lambda spec: spec["slots"]["glasses"].__setitem__("layer", "hair"), "already has a shape slot")

    def test_a_figure_layer_has_no_shapes(self):
        self.refuses(lambda spec: spec["slots"]["glasses"].__setitem__("layer", "top"), "is one drawing")

    def test_only_headwear_hides_the_hair(self):
        self.refuses(lambda spec: spec["slots"]["glasses"]["shapes"]["round"].__setitem__("hides_hair", True),
                     "only headwear hides the hair")
        self.refuses(lambda spec: spec["slots"]["headwear"]["shapes"]["hood"].__setitem__("hides_hair", "yes"),
                     "hides_hair must be true or false")

    def test_none_is_a_flag_not_an_option(self):
        self.refuses(lambda spec: spec["slots"]["glasses"]["shapes"].__setitem__("none", {}), "is not a shape")
        self.refuses(lambda spec: spec["slots"]["glasses"].__setitem__("none", "yes"), "none must be true or false")
        self.refuses(lambda spec: spec["slots"]["top"]["swatches"].__setitem__("none", ["ffffff", "eeeeee", "dddddd"]),
                     "a colour slot has no none")

    def test_looks_name_only_drawn_options(self):
        self.refuses(lambda spec: spec["default_look"].__setitem__("top", "sequins"), "default_look.top")
        self.refuses(lambda spec: spec["default_look"].__setitem__("skin", "none"), "default_look.skin")
        self.refuses(lambda spec: spec["default_look"].pop("glasses"), "default_look must set every slot")
        self.refuses(lambda spec: spec["variation"].__setitem__("hair_style", ["mohawk"]), "variation.hair_style")
        self.refuses(lambda spec: spec["variation"].__setitem__("skin", []), "variation.skin")
        self.refuses(lambda spec: spec["variation"].__setitem__("beard", ["none"]), "unknown field")

    def test_the_placeholder_s_fixed_colours_are_required(self):
        self.refuses(lambda spec: spec["fixed"].pop("eye"), "fixed must hold eye")

    def test_the_builder_exits_nonzero_on_a_broken_contract(self):
        with tempfile.TemporaryDirectory() as work:
            spec = copy.deepcopy(load(SOURCE / SPEC_NAME))
            spec["pivot"] = [10, 46]
            (Path(work) / SPEC_NAME).write_text(json.dumps(spec))
            result = subprocess.run([sys.executable, str(BUILDER), "--source", work, "--output", str(Path(work) / "out")],
                                    capture_output=True, text=True, cwd=ROOT)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PEOPLE_BUILD_FAILED", result.stderr)
            self.assertFalse((Path(work) / "out").exists(), "nothing is written before the contract holds")


class ArtistTemplateTests(unittest.TestCase):
    """`make people-templates`: a canvas and a guide per source, at the size the builder checks."""

    TOOL = ROOT / "tools" / "people_templates.py"

    def export(self, output: Path) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(self.TOOL), "--output", str(output)],
                              capture_output=True, text=True, cwd=ROOT)

    def test_every_source_has_a_canvas_and_a_guide(self):
        spec = load(SOURCE / SPEC_NAME)
        d = spec["density"]
        width = sum(len(info["durations"]) for info in spec["tracks"].values()) * spec["frame_size"][0] * d
        with tempfile.TemporaryDirectory() as work:
            output = Path(work) / "templates"
            result = self.export(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PEOPLE_TEMPLATES_OK: 30 canvases", result.stdout)
            canvases = sorted(path.relative_to(output / "canvases") for path in (output / "canvases").rglob("*.png"))
            guides = sorted(path.relative_to(output / "guides") for path in (output / "guides").rglob("*.png"))
            self.assertEqual(canvases, guides, "a guide for every canvas, of the same name")
            skins = [relative for relative in canvases if relative.parts[0] == "skins"]
            canvases = [relative for relative in canvases if relative.parts[0] != "skins"]
            self.assertEqual(len(canvases), 30)
            self.assertEqual(len(skins), 21, "a skin canvas per facing for the head, the torso, 3 hair styles, 2 hats")
            for relative in skins:
                _skins, facing, name = relative.parts
                expected = skin_size(spec, facing, Path(name).stem)
                for folder in ("canvases", "guides"):
                    with Image.open(output / folder / relative) as picture:
                        self.assertEqual(picture.size, expected, f"{folder}/{relative}")
            self.assertEqual(len((output / "skins.tsv").read_text().splitlines()), 22, "a header and a row per skin")
            for relative in canvases:
                with Image.open(output / "canvases" / relative) as canvas:
                    self.assertEqual(canvas.size, (width, spec["frame_size"][1] * d), str(relative))
                    self.assertIsNone(canvas.getchannel("A").getbbox(), f"{relative}: a canvas is empty")
                with Image.open(output / "guides" / relative) as layer:
                    self.assertEqual(layer.size, (width, spec["frame_size"][1] * d), str(relative))
            rows = (output / "files.tsv").read_text().splitlines()
            self.assertEqual(len(rows), 31, "a header and a row per source")
            self.assertIn("front/top.png\t", "\n".join(rows))
            for name in ("README.txt", "swatches.png", ".gdignore", "sheets/front.png", "sheets/back.png", "sheets/side.png"):
                self.assertTrue((output / name).is_file(), name)
            readme = (output / "README.txt").read_text()
            for rule in ("alpha", "brim", "40", "files.tsv", "skins.tsv", f"density {spec['density']}"):
                self.assertIn(rule, readme, f"the README names the rule: {rule}")

    def test_a_directory_with_work_in_it_is_refused(self):
        with tempfile.TemporaryDirectory() as work:
            painted = Path(work) / "front" / "top.png"
            painted.parent.mkdir()
            painted.write_bytes(b"work in progress")
            result = self.export(Path(work))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("empty output directory", result.stderr)
            self.assertEqual(painted.read_bytes(), b"work in progress", "nothing is overwritten")


if __name__ == "__main__":
    unittest.main()
