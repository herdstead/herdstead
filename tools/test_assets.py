"""Contract regressions for artist replacement, bad exports and atlas repacking.

What is checked here is that a pack's PNGs agree with its own pack.json: sizes,
pivots, atlas cells, palette discipline, referential integrity. Which semantic
IDs a pack has to carry is NOT checked here — pack.json is the list, and a pack
that grows a prop is a pack that grew a prop, not a contract violation. Which of
them the scenes draw with is scripts/art/art_contract.gd's half, held by
`make check-packs`.

Runs against any compliant pack source, not just Daylight:

    python tools/test_assets.py -v                        # art/daylight
    python tools/test_assets.py --source /path/to/pack -v
    HERDSTEAD_PACK_SOURCE=/path/to/pack python tools/test_assets.py -v
"""
import contextlib
import copy
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from PIL import Image

import check_build_clean
import draw_pixel_sources
from build_assets import ROOT, build, contract_size, packs, people_animations, save_if_pixels_moved, validate
from build_table_assets import build_pack as build_table
from recolour import remap_table, repaint
from upscale_pack import upgrade
from wall_templates import generate as wall_templates, wall_image

# The painter's scripts live with its skill, not in tools/; tilefix is tested here
# because `make check` runs this file.
PAINTER = ROOT / ".claude/skills/painter/scripts"
sys.path.insert(0, str(PAINTER))
import tilefix  # noqa: E402

## `--source` beats HERDSTEAD_PACK_SOURCE beats the Daylight source pack.
SOURCE = Path(os.environ.get("HERDSTEAD_PACK_SOURCE") or ROOT / "art/daylight")


def take_source_argument():
    """Take `--source <path>` out of argv before unittest tries to read it as a test name."""
    for index, argument in enumerate(sys.argv):
        if argument.startswith("--source="):
            return Path(sys.argv.pop(index).split("=", 1)[1])
        if argument == "--source" and index + 1 < len(sys.argv):
            value = sys.argv[index + 1]
            del sys.argv[index:index + 2]
            return Path(value)
    return None


class ArtContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        print(f"PACK UNDER TEST: {SOURCE}")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        shutil.copytree(SOURCE, self.source)
        self.pack = json.loads((self.source / "pack.json").read_text())

    ## Themes bring their own colours, so an edit has to be made in the pack's
    ## own palette or the palette check would reject it for the wrong reason.
    def paint(self, avoid=None, alpha=255):
        for value in self.pack["palette"].values():
            colour = tuple(bytes.fromhex(value)) + (alpha,)
            if colour != avoid:
                return colour
        raise AssertionError("pack palette holds no usable second colour")

    def test_repacked_atlas_preserves_logical_tiles_and_artist_edit(self):
        # Swap two cells and alter one interior pixel: a hard-coded atlas or seed
        # regeneration would produce the wrong tile or overwrite the artist's edit.
        a, b = self.pack["tiles"]["floor.wood_a"], self.pack["tiles"]["floor.wood_b"]
        moved_to = list(b["cell"])
        a["cell"], b["cell"] = b["cell"], a["cell"]
        path = self.source / a["path"]
        edited = Image.open(path)
        mark = self.paint(edited.getpixel((17, 9)))
        edited.putpixel((17, 9), mark)
        edited.save(path)
        before = path.read_bytes()
        (self.source / "pack.json").write_text(json.dumps(self.pack))
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = build(self.source, self.root / "out")
        atlas = Image.open(self.root / "out/terrain.png")
        self.assertEqual(manifest["tiles"]["floor.wood_a"]["cell"], moved_to)
        density = manifest.get("density", 1)
        x, y = (value * 32 * density for value in moved_to)
        # The source may be drawn at any whole fraction of the pack's density
        # (a 1x tile the build fills in, or one already painted at density):
        # the cell holds it brought up to 32 x density, NEAREST.
        factor = 32 * density // edited.width
        expected = edited.resize((edited.width * factor, edited.height * factor), Image.Resampling.NEAREST)
        self.assertEqual(expected.size, (32 * density, 32 * density))
        self.assertEqual(atlas.crop((x, y, x + expected.width, y + expected.height)).tobytes(), expected.tobytes())
        self.assertEqual(atlas.getpixel((x + 17 * factor, y + 9 * factor)), mark)
        self.assertEqual(path.read_bytes(), before)

    def test_rejects_wrong_export_dimensions(self):
        path = self.source / self.pack["props"]["cabinet"]["path"]
        Image.open(path).crop((0, 0, 47, 64)).save(path)
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            validate(self.source, self.pack)

    def test_rejects_soft_alpha(self):
        path = self.source / self.pack["props"]["plant"]["path"]
        image = Image.open(path)
        image.putpixel((0, 0), self.paint(alpha=128))
        image.save(path)
        changed = copy.deepcopy(self.pack)
        # Density 2/4/8 linear packs intentionally accept antialiased edges;
        # force the strict filter here so this test still exercises the rule.
        if changed.get("schema_version") == 2:
            changed["filter"] = "nearest"
        with self.assertRaisesRegex(ValueError, "Soft alpha"):
            validate(self.source, changed)

    def test_rejects_duplicate_tile_cell(self):
        self.pack["tiles"]["floor.wood_b"]["cell"] = self.pack["tiles"]["floor.wood_a"]["cell"]
        with self.assertRaisesRegex(ValueError, "Duplicate atlas cell"):
            validate(self.source, self.pack)

    def test_linear_wood_variants_keep_the_same_connection_edges(self):
        self.pack.update(schema_version=2, density=4, filter="linear")
        path = self.source / self.pack["tiles"]["floor.wood_b"]["path"]
        with Image.open(path) as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((0, 12), self.paint(changed.getpixel((0, 12))))
        changed.save(path)
        with self.assertRaisesRegex(ValueError, "Wood variants have mismatched edge pixels"):
            validate(self.source, self.pack)

    def test_cap_and_face_must_join_at_the_course_boundary(self):
        path = self.source / self.pack["tiles"]["wall.face_center"]["path"]
        with Image.open(path) as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((16, 0), self.paint(changed.getpixel((16, 0))))
        changed.save(path)
        with self.assertRaisesRegex(ValueError, "Wall course seam"):
            validate(self.source, self.pack)

    def test_t_junction_preserves_its_side_connection_above(self):
        path = self.source / self.pack["tiles"]["wall.cap_t_left"]["path"]
        with Image.open(path) as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((4, 0), self.paint(changed.getpixel((4, 0))))
        changed.save(path)
        with self.assertRaisesRegex(ValueError, "Wall T top port seam"):
            validate(self.source, self.pack)

    def test_t_junction_preserves_its_side_connection_below(self):
        path = self.source / self.pack["tiles"]["wall.face_t_left"]["path"]
        with Image.open(path) as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((4, changed.height - 1), self.paint(changed.getpixel((4, changed.height - 1))))
        changed.save(path)
        with self.assertRaisesRegex(ValueError, "Wall T bottom port seam"):
            validate(self.source, self.pack)

    def test_side_wall_does_not_bleed_outside_its_declared_strip(self):
        path = self.source / self.pack["tiles"]["wall.side_right"]["path"]
        with Image.open(path) as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((12, 16), self.paint())
        changed.save(path)
        with self.assertRaisesRegex(ValueError, "six-unit profile"):
            validate(self.source, self.pack)

    def test_open_end_keeps_its_horizontal_connection_to_the_wall(self):
        path = self.source / self.pack["tiles"]["wall.cap_end_right"]["path"]
        with Image.open(path) as opened:
            changed = opened.convert("RGBA")
        changed.putpixel((0, 16), self.paint(changed.getpixel((0, 16))))
        changed.save(path)
        with self.assertRaisesRegex(ValueError, "Wall horizontal seam"):
            validate(self.source, self.pack)

    def test_wall_templates_use_the_pack_ids_without_touching_source_art(self):
        source_bytes = {path: path.read_bytes() for path in self.source.rglob("*.png")}
        expected = {name + ".png" for name in self.pack["tiles"]
                    if name.startswith(("wall.cap_", "wall.face_", "wall.side_"))}
        for density in (1, 4):
            output = self.root / f"walls-{density}"
            paths = wall_templates(self.source / "pack.json", output, density)
            self.assertEqual({path.name for path in paths}, expected)
            for path in paths:
                with Image.open(path) as image:
                    self.assertEqual(image.size, (32 * density, 32 * density))
                    self.assertEqual(image.mode, "RGBA")
        self.assertEqual(source_bytes, {path: path.read_bytes() for path in source_bytes})

    def test_wall_templates_refuse_occupied_or_invalid_exports_without_partial_write(self):
        output = self.root / "occupied"
        output.mkdir()
        occupied = output / "artist.png"
        occupied.write_bytes(b"artist work")
        with self.assertRaisesRegex(ValueError, "empty directory"):
            wall_templates(self.source / "pack.json", output)
        self.assertEqual(occupied.read_bytes(), b"artist work")
        for density in (True, 1.0, 3, 16):
            target = self.root / "invalid-density"
            with self.subTest(density=density), self.assertRaisesRegex(ValueError, "density"):
                wall_templates(self.source / "pack.json", target, density)
            self.assertFalse(target.exists())
        self.pack["tiles"]["wall.cap_cross"] = {"path": "never-read.png", "cell": [7, 3]}
        (self.source / "pack.json").write_text(json.dumps(self.pack))
        with self.assertRaisesRegex(ValueError, "Unsupported wall module"):
            wall_templates(self.source / "pack.json", self.root / "unsupported")
        self.assertFalse((self.root / "unsupported").exists())

    def test_wall_template_end_closes_where_an_outer_corner_continues(self):
        palette = self.pack["palette"]
        ink = tuple(bytes.fromhex(palette["ink"])) + (255,)
        shade = tuple(bytes.fromhex(palette["cream_shadow"])) + (255,)
        end = wall_image("wall.face_end_right", palette)
        corner = wall_image("wall.face_right", palette)
        self.assertEqual(end.getpixel((26, 31)), ink)
        self.assertEqual(corner.getpixel((26, 31)), shade)
        self.assertEqual(end.crop((0, 0, 1, 32)).tobytes(), corner.crop((0, 0, 1, 32)).tobytes())

    def test_rejects_an_anchor_outside_its_canvas_and_fake_success_mapping(self):
        # The pivot is the manifest's to choose; what it may not do is point off
        # the picture, because then nothing can be placed by its footing.
        changed = copy.deepcopy(self.pack)
        width, height = changed["props"]["cabinet"]["size"]
        changed["props"]["cabinet"]["pivot"] = [width // 2, height + 1]
        with self.assertRaisesRegex(ValueError, "Pivot outside the canvas: props/cabinet"):
            validate(self.source, changed)
        changed = copy.deepcopy(self.pack)
        changed["props"]["cabinet"]["pivot"] = [-1, 0]
        with self.assertRaisesRegex(ValueError, "Pivot outside the canvas: props/cabinet"):
            validate(self.source, changed)
        changed = copy.deepcopy(self.pack)
        changed["states"]["done"]["badge"] = "working"
        with self.assertRaisesRegex(ValueError, "done must remain unread"):
            validate(self.source, changed)

    def test_rejects_a_state_pointing_at_art_or_an_animation_that_is_not_there(self):
        # Referential integrity inside one pack. Which states exist is the
        # scenes' list, not this build's; what a declared state names has to be
        # real: a badge this pack ships, and a move the pixel people can make.
        changed = copy.deepcopy(self.pack)
        changed["states"]["idle"]["badge"] = "no_such_icon"
        with self.assertRaisesRegex(ValueError, 'State idle wears "no_such_icon"'):
            validate(self.source, changed)
        changed = copy.deepcopy(self.pack)
        changed["states"]["idle"]["animation"] = "cartwheel"
        with self.assertRaisesRegex(ValueError, 'State idle plays "cartwheel"'):
            validate(self.source, changed)

    ## --- pack.json is the list ------------------------------------------------

    def test_a_new_well_formed_prop_needs_no_python_change(self):
        # The whole point of the manifest being the list: an artist adds a PNG
        # and a pack.json entry, and `make art` accepts it. Nothing here names
        # the eight props the pack happens to ship today.
        donor = self.pack["props"]["sign"]
        with Image.open(self.source / donor["path"]) as opened:
            opened.copy().save(self.source / "props/notice.png")
        self.pack["props"]["notice"] = {"path": "props/notice.png",
                                        "size": list(donor["size"]), "pivot": list(donor["pivot"])}
        (self.source / "pack.json").write_text(json.dumps(self.pack))
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = build(self.source, self.root / "out")
        self.assertIn("notice", manifest["props"])
        self.assertTrue((self.root / "out/props/notice.png").is_file())

    def test_a_manifest_entry_whose_png_is_the_wrong_size_is_refused(self):
        # The other half of the same rule: the manifest is believed, so the PNG
        # behind every entry has to be what the entry promises.
        donor = self.pack["props"]["sign"]
        with Image.open(self.source / donor["path"]) as opened:
            opened.copy().save(self.source / "props/notice.png")
        self.pack["props"]["notice"] = {"path": "props/notice.png",
                                        "size": [donor["size"][0] + 1, donor["size"][1]], "pivot": [0, 0]}
        with self.assertRaisesRegex(ValueError, "size mismatch: props/notice"):
            validate(self.source, self.pack)

    def test_every_state_points_at_art_the_pack_really_has(self):
        animations = people_animations()
        for state, info in self.pack["states"].items():
            self.assertIn(info["animation"], animations, state)
            self.assertIn(info["badge"], self.pack["ui"], state)

    def test_nine_patch_margins_have_to_leave_a_middle(self):
        changed = copy.deepcopy(self.pack)
        width, height = changed["ui"]["panel"]["size"]
        changed["ui"]["panel"]["nine_patch"] = [width, 4, 4, 4]
        with self.assertRaisesRegex(ValueError, "leave no stretchable middle"):
            validate(self.source, changed)
        changed["ui"]["panel"]["nine_patch"] = [4, 4, 4]
        with self.assertRaisesRegex(ValueError, "four whole margins"):
            validate(self.source, changed)
        self.assertLess(4 + 4, height)  # the shipped margins really do leave one

    def test_a_generated_tree_loses_the_picture_its_manifest_stopped_naming(self):
        # The ghost-file case. Without pruning, dropping an entry would leave
        # the built PNG on disk, byte for byte what the commit holds, so
        # check_build_clean could not see it either and the art would go
        # quietly unused.
        output = self.root / "out"
        with contextlib.redirect_stdout(io.StringIO()):
            build(self.source, output)
        ghost = output / self.pack["props"]["cabinet"]["path"]
        sidecar = ghost.with_name(ghost.name + ".import")
        sidecar.write_text("[remap]\n")  # Godot keeps one beside every shipped PNG
        self.assertTrue(ghost.is_file())
        del self.pack["props"]["cabinet"]
        (self.source / "pack.json").write_text(json.dumps(self.pack))
        with contextlib.redirect_stdout(io.StringIO()) as said:
            build(self.source, output)
        self.assertFalse(ghost.exists(), "the built PNG outlived its manifest entry")
        self.assertFalse(sidecar.exists(), "the Godot import outlived its image")
        self.assertIn("PRUNED:", said.getvalue())
        self.assertIn("props/cabinet.png", said.getvalue())
        # Everything still declared is untouched, and a rerun prunes nothing.
        kept = output / self.pack["props"]["sign"]["path"]
        self.assertTrue(kept.is_file())
        with contextlib.redirect_stdout(io.StringIO()) as quiet:
            build(self.source, output)
        self.assertNotIn("PRUNED:", quiet.getvalue())

    def test_pruning_never_reaches_a_companion_family_or_anything_but_pictures(self):
        # The shared table sits inside the pack's runtime tree but carries its
        # own manifest and its own builder, so this builder leaves it alone --
        # otherwise `make art` would delete the table on every run.
        output = self.root / "out"
        with contextlib.redirect_stdout(io.StringIO()):
            build(self.source, output)
        companion = output / "table"
        companion.mkdir()
        (companion / "manifest.json").write_text("{}")
        (companion / "surface_left.png").write_bytes(b"not this builder's")
        stray = output / "fonts/NOTES.txt"
        stray.write_text("not a picture")
        with contextlib.redirect_stdout(io.StringIO()):
            build(self.source, output)
        self.assertTrue((companion / "surface_left.png").is_file(), "the shared table was pruned by the wrong builder")
        self.assertTrue(stray.is_file(), "pruning removed something that is not a picture")

    def test_every_editable_pack_in_the_tree_is_found_by_its_manifest(self):
        # `make art` builds what it finds, not a list written down twice.
        found = packs()
        self.assertIn(ROOT / "art/daylight", found)
        self.assertTrue(all((path / "pack.json").is_file() for path in found))
        self.assertEqual(found, sorted(found))

    def test_rejects_a_pack_without_an_id_or_name(self):
        for key in ("id", "name"):
            changed = copy.deepcopy(self.pack)
            del changed[key]
            with self.assertRaisesRegex(ValueError, f"Pack needs a non-empty {key}"):
                validate(self.source, changed)

    def test_rejects_a_pack_whose_listed_file_is_absent(self):
        (self.source / self.pack["ui"]["selection"]["path"]).unlink()
        with self.assertRaisesRegex(ValueError, "lists a file that is not in the pack: ui/selection.png"):
            validate(self.source, self.pack)
        shutil.copytree(SOURCE, self.source, dirs_exist_ok=True)
        (self.source / self.pack["font"]["license"]).unlink()
        with self.assertRaisesRegex(ValueError, "lists a file that is not in the pack: fonts/"):
            validate(self.source, self.pack)

    def test_rejects_an_empty_category_or_a_palette_entry_that_is_not_a_colour(self):
        # A pack may carry any set of IDs, but not none of them, and every
        # colour it does carry has to be one the runtime can parse.
        for category in ("tiles", "props", "ui", "palette", "states"):
            changed = copy.deepcopy(self.pack)
            changed[category] = {}
            with self.subTest(category=category), self.assertRaisesRegex(ValueError, f'"{category}" must be a non-empty'):
                validate(self.source, changed)
        changed = copy.deepcopy(self.pack)
        changed["palette"]["sage_dark"] = "#82947A"
        with self.assertRaisesRegex(ValueError, "Palette entry must be six lowercase hex digits: sage_dark"):
            validate(self.source, changed)

    ## --- optional keys --------------------------------------------------------

    def test_stale_modulate_is_optional_hex_checked_and_passed_through(self):
        changed = copy.deepcopy(self.pack)
        # Absent is legal: the scenes fall back to ArtPack.STALE_DEFAULT.
        changed.pop("stale_modulate", None)
        validate(self.source, changed)
        changed["stale_modulate"] = "8f96b8"
        validate(self.source, changed)
        (self.source / "pack.json").write_text(json.dumps(changed))
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = build(self.source, self.root / "out")
        self.assertEqual(manifest["stale_modulate"], "8f96b8")
        changed["stale_modulate"] = "#8F96B8"
        with self.assertRaisesRegex(ValueError, "stale_modulate must be six lowercase hex"):
            validate(self.source, changed)

    def test_task_lights_is_optional_checked_and_passed_through(self):
        changed = copy.deepcopy(self.pack)
        # Absent is legal: a pack that says nothing gets the daylight strength.
        changed.pop("task_lights", None)
        validate(self.source, changed)
        changed["task_lights"] = "strong"
        validate(self.source, changed)
        (self.source / "pack.json").write_text(json.dumps(changed))
        with contextlib.redirect_stdout(io.StringIO()):
            manifest = build(self.source, self.root / "out")
        self.assertEqual(manifest["task_lights"], "strong")
        changed["task_lights"] = "bright"
        with self.assertRaisesRegex(ValueError, '"task_lights" must be'):
            validate(self.source, changed)


class DensityContractTests(unittest.TestCase):
    """schema v2: one density per pack, lower-density sources filled in by the build.

    Every fixture is derived from the pack under test, so these run against any
    theme. Nothing is ever built into `assets/`.
    """

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        # The shipped packs are schema 2 at density 1 (nearest). Keep a private
        # schema-1 copy for tests that exercise the upgrade path from an original
        # 1x pack; the product source and runtime assets remain untouched.
        self.base_source = self.root / "base"
        shutil.copytree(SOURCE, self.base_source)
        base_pack = json.loads((self.base_source / "pack.json").read_text())
        # A schema-1 fixture needs actual 1x PNGs, not just a changed manifest
        # declaration: a denser pack under test (--source) is brought down to 1x.
        for category in ("tiles", "props", "ui"):
            for info in base_pack[category].values():
                path = self.base_source / info["path"]
                with Image.open(path) as opened:
                    size = contract_size(base_pack, category, info)
                    if opened.size != size:
                        opened.resize(size, Image.Resampling.NEAREST).save(path)
        base_pack["schema_version"] = 1
        base_pack.pop("density", None)
        base_pack.pop("filter", None)
        (self.base_source / "pack.json").write_text(json.dumps(base_pack, indent=2) + "\n")

    ## --- fixtures -------------------------------------------------------------

    def quiet(self, function, *args, **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return function(*args, **kwargs)

    def upgraded(self, density, name, manifest_only=False, filter_name=None) -> Path:
        """A schema 2 source copy of the pack under test, at `density`."""
        source = self.root / name
        self.quiet(upgrade, self.base_source, source, density, manifest_only=manifest_only)
        if filter_name is not None:
            self.patch(source, filter=filter_name)
        return source

    def patch(self, source: Path, **changes) -> dict:
        pack = json.loads((source / "pack.json").read_text())
        pack.update(changes)
        (source / "pack.json").write_text(json.dumps(pack, indent=2) + "\n")
        return pack

    def read_pack(self, source: Path) -> dict:
        return json.loads((source / "pack.json").read_text())

    def opaque(self, pack, alpha=255, avoid=None):
        for value in pack["palette"].values():
            colour = tuple(bytes.fromhex(value)) + (alpha,)
            if colour != avoid:
                return colour
        raise AssertionError("pack palette holds no usable second colour")

    def rescale(self, path: Path, factor: int):
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
        image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST).save(path)

    ## --- assertions -----------------------------------------------------------

    def assert_built_at(self, source: Path, output: Path, density: int):
        """Every runtime PNG is exactly its density-1 contract times the pack density."""
        pack = self.read_pack(source)
        with Image.open(output / "terrain.png") as atlas:
            self.assertEqual(atlas.size, tuple(value * density for value in pack["atlas_size"]))
        for category in ("props", "ui"):
            for name, info in pack[category].items():
                width, height = contract_size(pack, category, info)
                with Image.open(output / info["path"]) as built:
                    self.assertEqual(built.size, (width * density, height * density), f"{category}/{name}")

    def assert_same_pixels(self, left: Path, right: Path):
        names = sorted(path.relative_to(left) for path in left.rglob("*.png"))
        self.assertTrue(names)
        for relative in names:
            with Image.open(left / relative) as a, Image.open(right / relative) as b:
                self.assertEqual((a.size, a.convert("RGBA").tobytes()),
                                 (b.size, b.convert("RGBA").tobytes()), relative)

    ## --- schema 1 is untouched ------------------------------------------------

    def test_the_committed_source_builds_to_the_committed_runtime_pack(self):
        # The committed source and runtime pack must agree at its declared
        # density; CI diffs assets/ against this build.
        pack = self.read_pack(SOURCE)
        committed = ROOT / "assets" / pack["id"]
        if not committed.is_dir():
            self.skipTest(f"no committed runtime pack at {committed}")
        output = self.root / "out"
        self.quiet(build, SOURCE, output)
        produced = sorted(path for path in output.rglob("*") if path.is_file())
        self.assertTrue(produced)
        for path in produced:
            relative = path.relative_to(output)
            mirror = committed / relative
            self.assertTrue(mirror.is_file(), f"build produced a file the commit lacks: {relative}")
            if path.suffix == ".png":
                with Image.open(path) as built, Image.open(mirror) as shipped:
                    self.assertEqual((built.size, built.convert("RGBA").tobytes()),
                                     (shipped.size, shipped.convert("RGBA").tobytes()), relative)
            else:
                self.assertEqual(path.read_bytes(), mirror.read_bytes(), relative)
        manifest = json.loads((output / "manifest.json").read_text())
        self.assertEqual(list(manifest), list(pack) + ["atlas"], "the runtime manifest preserves the source contract")

    def test_schema_one_may_not_declare_density_or_filter(self):
        pack = self.read_pack(self.base_source)
        for key, value in (("density", 2), ("filter", "linear")):
            changed = dict(pack)
            changed[key] = value
            with self.assertRaisesRegex(ValueError, f"may not declare {key}"):
                validate(self.base_source, changed)

    ## --- density --------------------------------------------------------------

    def test_upgraded_packs_build_every_png_at_contract_times_density(self):
        for density in (2, 8):
            with self.subTest(density=density):
                source = self.upgraded(density, f"src{density}")
                output = self.root / f"out{density}"
                manifest = self.quiet(build, source, output)
                self.assertEqual((manifest["density"], manifest["filter"]), (density, "linear"))
                # Geometry in the manifest stays in density-1 units at every density.
                self.assertEqual(manifest["tile_size"], 32)
                self.assertEqual(manifest["atlas_size"], self.read_pack(SOURCE)["atlas_size"])
                self.assertEqual(manifest["props"]["cabinet"]["size"], self.read_pack(SOURCE)["props"]["cabinet"]["size"])
                self.assert_built_at(source, output, density)

    def test_manifest_only_pack_is_filled_in_to_the_same_pixels(self):
        # The upgrade path: declare the density, repaint later. Until then the
        # build blows the 1x sources up itself, byte for byte as if pre-upscaled.
        lazy = self.upgraded(4, "lazy", manifest_only=True)
        painted = self.upgraded(4, "painted")
        for name, info in self.read_pack(lazy)["props"].items():
            with Image.open(lazy / info["path"]) as opened:
                self.assertEqual(opened.size, tuple(info["size"]), f"{name} should still be 1x in the source")
        lazy_out, painted_out = self.root / "lazy-out", self.root / "painted-out"
        self.quiet(build, lazy, lazy_out)
        self.quiet(build, painted, painted_out)
        self.assert_built_at(lazy, lazy_out, 4)
        self.assert_same_pixels(lazy_out, painted_out)

    def test_mixed_source_densities_build_to_one_density(self):
        mixed = self.upgraded(4, "mixed", manifest_only=True, filter_name="nearest")
        painted = self.upgraded(4, "painted")
        pack = self.read_pack(mixed)
        # One tile, one prop and one icon repainted at 2x inside a 4x pack; the
        # wood seam check has to compare floor.wood_a (1x) with wood_b (2x).
        for relative in (pack["tiles"]["floor.wood_b"]["path"], pack["props"]["cabinet"]["path"],
                         pack["ui"]["panel"]["path"]):
            self.rescale(mixed / relative, 2)
        mixed_out, painted_out = self.root / "mixed-out", self.root / "painted-out"
        self.quiet(build, mixed, mixed_out)
        self.quiet(build, painted, painted_out)
        self.assert_built_at(mixed, mixed_out, 4)
        self.assert_same_pixels(mixed_out, painted_out)

    def test_rejects_a_source_png_denser_than_the_pack(self):
        source = self.upgraded(2, "two")
        pack = self.read_pack(source)
        self.rescale(source / pack["props"]["cabinet"]["path"], 2)
        with self.assertRaisesRegex(ValueError, "Raise the pack density to 4"):
            validate(source, pack)

    def test_rejects_a_source_png_at_a_factor_the_contract_has_no_room_for(self):
        source = self.upgraded(4, "four", manifest_only=True)
        pack = self.read_pack(source)
        self.rescale(source / pack["props"]["plant"]["path"], 3)
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            validate(source, pack)
        with self.assertRaises(ValueError) as caught:
            validate(source, pack)
        # The plant is declared 32x48, so these are its sizes at factors 1, 2 and 4.
        self.assertIn("32x48, 64x96, 128x192", str(caught.exception))

    def test_rejects_an_invalid_density_or_schema_version(self):
        source = self.upgraded(2, "two")
        pack = self.read_pack(source)
        for value in (3, 16, "2", 2.0, True, None):
            changed = dict(pack)
            changed["density"] = value
            with self.subTest(density=value), self.assertRaisesRegex(ValueError, 'needs "density" to be one of'):
                validate(source, changed)
        changed = dict(pack)
        del changed["density"]
        with self.assertRaisesRegex(ValueError, 'needs "density" to be one of'):
            validate(source, changed)
        changed = dict(pack)
        changed["schema_version"] = 3
        with self.assertRaisesRegex(ValueError, "Unsupported schema version"):
            validate(source, changed)

    ## --- filter ---------------------------------------------------------------

    def test_rejects_linear_at_density_one(self):
        source = self.upgraded(1, "one", manifest_only=True)
        pack = self.patch(source, filter="linear")
        with self.assertRaisesRegex(ValueError, "needs density 2 or more"):
            validate(source, pack)

    def test_default_filter_follows_the_density_and_an_explicit_one_wins(self):
        one = self.upgraded(1, "one", manifest_only=True)
        self.assertNotIn("filter", self.read_pack(one))
        manifest = self.quiet(build, one, self.root / "one-out")
        self.assertEqual((manifest["density"], manifest["filter"]), (1, "nearest"))
        two = self.upgraded(2, "two")
        self.assertNotIn("filter", self.read_pack(two))
        manifest = self.quiet(build, two, self.root / "two-out")
        self.assertEqual((manifest["density"], manifest["filter"]), (2, "linear"))
        self.patch(two, filter="nearest")
        manifest = self.quiet(build, two, self.root / "two-strict")
        self.assertEqual((manifest["density"], manifest["filter"]), (2, "nearest"))
        self.patch(two, filter="smooth")
        with self.assertRaisesRegex(ValueError, '"filter" must be'):
            validate(two, self.read_pack(two))

    def test_strict_density_two_rejects_what_the_relaxed_filter_allows(self):
        source = self.upgraded(2, "strict", filter_name="nearest")
        strict = self.read_pack(source)
        relaxed = dict(strict, filter="linear")
        path = source / strict["props"]["plant"]["path"]
        with Image.open(path) as opened:
            original = opened.convert("RGBA")
        soft = original.copy()
        soft.putpixel((0, 0), self.opaque(strict, alpha=128))
        soft.save(path)
        with self.assertRaisesRegex(ValueError, "Soft alpha"):
            validate(source, strict)
        validate(source, relaxed)  # painted art is allowed its soft edges
        foreign = original.copy()
        foreign.putpixel((0, 0), (1, 2, 3, 255))
        foreign.save(path)
        with self.assertRaisesRegex(ValueError, "Color outside palette"):
            validate(source, strict)
        validate(source, relaxed)  # ... and its off-palette shading

    def test_an_item_block_is_held_to_its_rules(self):
        # docs/ITEMS.md: the block's own keys and values, the same rules
        # ArtPack._read_item() holds at run time, each refused by name.
        source = self.base_source
        broken = {
            "has keys it does not know": lambda item: item.update(colour="red"),
            "place is 'roof'": lambda item: item.update(place="roof"),
            "a desk item needs a footprint": lambda item: item.pop("footprint"),
            "is empty or wider than its": lambda item: item.update(footprint=[30, 3]),
            "blocks is only true, on a floor item": lambda item: item.update(blocks=True),
            "is not \\[a-z0-9_\\]\\+": lambda item: item.update(group="Desk!"),
            "weight is a whole number": lambda item: item.update(weight=-1),
        }
        for message, change in broken.items():
            with self.subTest(message=message):
                pack = self.read_pack(source)
                change(pack["props"]["desk_mug"]["item"])
                with self.assertRaisesRegex(ValueError, "props/desk_mug item.*" + message):
                    validate(source, pack)

    def test_a_desk_item_keeps_to_the_desk_plane(self):
        # Measured on the pixels: a desk item is opaque only in unit rows 3..21
        # of its canvas, or the build refuses it.
        source = self.base_source
        pack = self.read_pack(source)
        path = source / pack["props"]["desk_mug"]["path"]
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
        ink = tuple(bytes.fromhex(pack["palette"]["ink"])) + (255,)
        # The pixels of one unit, whatever density this source is painted at.
        unit = image.height // pack["props"]["desk_mug"]["size"][1]
        tall = image.copy()
        tall.putpixel((image.width // 2, 2 * unit), ink)
        tall.save(path)
        with self.assertRaisesRegex(ValueError, "props/desk_mug item: a desk item is opaque only in rows 3..21"):
            validate(source, pack)
        image.save(path)
        validate(source, pack)

    def test_relaxed_filter_still_checks_the_geometry_it_is_given(self):
        # A painted pack buys freedom in its pixels, not in its manifest: the
        # canvas and the anchor are still held to what pack.json declares.
        source = self.upgraded(2, "relaxed")
        pack = self.read_pack(source)
        pack["ui"]["panel"]["pivot"] = [0, pack["ui"]["panel"]["size"][1] + 3]
        with self.assertRaisesRegex(ValueError, "Pivot outside the canvas: ui/panel"):
            validate(source, pack)

    ## --- the other tools ------------------------------------------------------

    def test_recolour_refuses_an_ambiguous_palette_and_names_an_off_palette_pixel(self):
        # What is left of the retired theme derivation, used by the pixel
        # people build: a palette whose colours repeat cannot be remapped, and
        # an off-palette pixel is named by file and coordinate, never guessed.
        with self.assertRaisesRegex(SystemExit, "ambiguous: a and b are both #123456"):
            remap_table({"a": "123456", "b": "123456"}, {})
        table = remap_table({"a": "123456", "b": "654321"}, {"a": "abcdef"})
        image = Image.new("RGBA", (4, 4), (0x12, 0x34, 0x56, 255))
        image.putpixel((0, 0), (0, 0, 0, 0))
        painted, foreign = repaint(image, table, "probe.png", False)
        self.assertEqual(painted.getpixel((1, 1)), (0xab, 0xcd, 0xef, 255))
        self.assertEqual(painted.getpixel((0, 0)), (0, 0, 0, 0), "transparency carries no colour")
        self.assertEqual(foreign, set())
        image.putpixel((3, 2), (1, 2, 3, 255))
        with self.assertRaises(SystemExit) as caught:
            repaint(image, table, "probe.png", False)
        self.assertIn("probe.png holds colours outside the source palette: #010203 at (3, 2)", str(caught.exception))
        _, kept = repaint(image, table, "probe.png", True)
        self.assertEqual(kept, {(1, 2, 3)})

    def test_a_generated_png_is_only_rewritten_when_its_pixels_move(self):
        # Every builder writes through this, so a rerun of `make art` puts no
        # byte-only churn in the commit and a real change still lands.
        target = self.root / "probe.png"
        image = Image.new("RGBA", (4, 4), (10, 20, 30, 255))
        self.assertTrue(save_if_pixels_moved(image, target))
        before = target.read_bytes()
        self.assertFalse(save_if_pixels_moved(image, target))
        self.assertEqual(target.read_bytes(), before)
        moved = image.copy()
        moved.putpixel((1, 1), (40, 50, 60, 255))
        self.assertTrue(save_if_pixels_moved(moved, target))
        with Image.open(target) as written:
            self.assertEqual(written.convert("RGBA").getpixel((1, 1)), (40, 50, 60, 255))

    def test_upscale_pack_refuses_the_source_directory_a_full_output_and_a_downgrade(self):
        with self.assertRaisesRegex(SystemExit, "outside --source"):
            self.quiet(upgrade, self.base_source, self.base_source, 2)
        with self.assertRaisesRegex(SystemExit, "outside --source"):
            self.quiet(upgrade, self.base_source, self.base_source / "tiles", 2)
        occupied = self.root / "occupied"
        occupied.mkdir()
        (occupied / "sketch.png").write_bytes(b"")
        with self.assertRaisesRegex(SystemExit, "already holds files"):
            self.quiet(upgrade, self.base_source, occupied, 2)
        four = self.upgraded(4, "four", manifest_only=True)
        with self.assertRaisesRegex(SystemExit, "never downscales"):
            self.quiet(upgrade, four, self.root / "down", 2)


class PixelSourceTests(unittest.TestCase):
    """tools/draw_pixel_sources.py (`make pixel-sources`): the density-1 drawings.

    It is an authoring tool, never run by `make art`, so what is checked is that
    its output is something `make art` accepts as it is: every piece at its
    contract size in the pack's palette with hard alpha, desk pieces on the rows
    the table keeps free, the table family valid at its own density, the whole
    tree a pack at the shipped pack's density with the pieces filled in from
    1x. It never overwrites anything, and the same palette always draws the
    same bytes.
    """

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def draw(self, name):
        with contextlib.redirect_stdout(io.StringIO()):
            draw_pixel_sources.draw(ROOT / "art/daylight", self.root / name)
        return self.root / name

    def test_the_drawings_are_density_one_pieces_make_art_accepts(self):
        drawn = self.draw("drawn")
        pack = self.root / "pack"
        shutil.copytree(ROOT / "art/daylight", pack)
        shutil.copytree(drawn, pack, dirs_exist_ok=True)
        manifest = json.loads((pack / "pack.json").read_text())
        self.assertEqual(manifest["filter"], "nearest")
        # The strict filter: hard alpha and every opaque pixel a palette colour.
        compiled = validate(pack, manifest)
        self.assertEqual((compiled.density, compiled.filter), (manifest["density"], "nearest"))
        for name in draw_pixel_sources.DESK_PIECES:
            self.assertEqual(compiled.factors[("props", name)], 1, f"{name} is drawn at density 1")
            with Image.open(drawn / f"props/{name}.png") as piece:
                box = piece.getchannel("A").getbbox()
            self.assertGreaterEqual(box[1], 3, f"{name} stays clear of the divider")
            self.assertLessEqual(box[3], 22, f"{name} keeps the two rows under its foot clear")
        with contextlib.redirect_stdout(io.StringIO()):
            build_table(pack, self.root / "runtime")
        self.assertTrue((self.root / "runtime/table/chair_front.png").is_file())

    def test_the_same_palette_draws_the_same_bytes(self):
        first, second = self.draw("first"), self.draw("second")
        files = sorted(path.relative_to(first) for path in first.rglob("*") if path.is_file())
        self.assertEqual(
            len(files),
            len(draw_pixel_sources.DESK_PIECES) + len(draw_pixel_sources.FIXTURE_SIZES)
            + len(draw_pixel_sources.DENSE_SIZES) + 27,
            "8 desk props, 2 fixture props, 2 density-2 pieces, 26 modules (legacy and pod), 1 manifest",
        )
        self.assertEqual(files, sorted(path.relative_to(second) for path in second.rglob("*") if path.is_file()))
        for relative in files:
            self.assertEqual((first / relative).read_bytes(), (second / relative).read_bytes(), relative)

    def test_the_fixtures_are_drawn_as_the_pack_declares_them(self):
        drawn = self.draw("drawn")
        manifest = json.loads((ROOT / "art/daylight/pack.json").read_text())
        for name, size in draw_pixel_sources.FIXTURE_SIZES.items():
            declared = manifest["props"][name]
            self.assertEqual(tuple(declared["size"]), size, f"{name}: the size pack.json declares")
            self.assertEqual(tuple(declared["pivot"]), draw_pixel_sources.FIXTURE_PIVOTS[name], f"{name}: its foot")
            with Image.open(drawn / f"props/{name}.png") as piece:
                self.assertEqual(piece.size, size, f"{name}: drawn at its size")
                box = piece.getchannel("A").getbbox()
                # Nothing on or below the foot, the bottom outline right above it.
                self.assertEqual(box[3], declared["pivot"][1], f"{name}: stands on its foot")
                if name in ("reception", "pantry"):
                    self.assertEqual((box[0], box[2]), (0, size[0]), f"{name}: stands on its whole width")
            # What ships in art/daylight is painted (the drawing here was its
            # first draft), so it is held to the same footprint at its own
            # density k, not to these bytes: the canvas is the declared size
            # times k, the bottom outline sits on the row above the foot
            # (pivot y times k) with nothing on or below it, and a counter
            # stands on its whole width.
            with Image.open(ROOT / f"art/daylight/props/{name}.png") as shipped:
                k, rest = divmod(shipped.width, size[0])
                self.assertEqual((rest, shipped.height), (0, size[1] * k), f"{name}: shipped at a whole density")
                box = shipped.getchannel("A").getbbox()
                self.assertIsNotNone(box, f"{name}: shipped empty")
                self.assertEqual(box[3], declared["pivot"][1] * k, f"{name}: the shipped piece stands on its foot")
                self.assertEqual((box[0], box[2]), (0, shipped.width), f"{name}: the shipped piece stands on its whole width")

    def test_the_density_two_pieces_keep_their_contract_and_make_art_accepts_them(self):
        drawn = self.draw("drawn")
        pack = self.root / "pack"
        shutil.copytree(ROOT / "art/daylight", pack)
        shutil.copytree(drawn, pack, dirs_exist_ok=True)
        manifest = json.loads((pack / "pack.json").read_text())
        # Declared the way art/daylight/pack.json declares them (or will).
        manifest["props"]["done_stack_small"] = {
            "path": "props/done_stack_small.png", "size": [24, 24], "pivot": [12, 22],
            "item": {"place": "desk", "footprint": [6, 3]},
        }
        manifest["ui"]["selection_seat"] = {"path": "ui/selection_seat.png", "size": [32, 48], "pivot": [16, 46]}
        compiled = validate(pack, manifest)
        self.assertEqual(compiled.factors[("props", "done_stack_small")], 2, "drawn at the pack's density")
        self.assertEqual(compiled.factors[("ui", "selection_seat")], 2, "drawn at the pack's density")
        d = draw_pixel_sources.DENSE
        with Image.open(drawn / "props/done_stack_small.png") as stack:
            self.assertEqual(stack.size, (24 * d, 24 * d))
            alpha = stack.getchannel("A")
            self.assertEqual({value for _, value in alpha.getcolors()}, {0, 255}, "hard alpha")
            # 6 wide by 9 tall, x -3..3 and y -9..0 about the pivot [12, 22].
            self.assertEqual(alpha.getbbox(), (9 * d, 13 * d, 15 * d, 22 * d))
        with Image.open(ROOT / "art/daylight/props/done_stack.png") as big, \
                Image.open(drawn / "props/done_stack_small.png") as small:
            self.assertLessEqual({colour for _, colour in small.getcolors()} - {(0, 0, 0, 0)},
                                 {colour for _, colour in big.getcolors()},
                                 "the painted done_stack's colours, nothing new")
        with Image.open(drawn / "ui/selection_seat.png") as mark, \
                Image.open(ROOT / "art/daylight/ui/selection.png") as selection:
            self.assertEqual(mark.size, (32 * d, 48 * d))
            colours = {colour for _, colour in mark.getcolors()}
            self.assertEqual(colours - {(0, 0, 0, 0)}, {colour for _, colour in selection.getcolors()} - {(0, 0, 0, 0)},
                             "ui.selection's one colour")
            alpha = mark.getchannel("A")
            line, arm = draw_pixel_sources.SEAT_LINE * d, draw_pixel_sources.SEAT_ARM * d
            self.assertEqual(alpha.getbbox(), (0, 0, mark.width, mark.height), "the corners reach the canvas edges")
            self.assertEqual(alpha.crop((line, line, mark.width - line, mark.height - line)).getextrema(), (0, 0),
                             "the middle stays clear for the seated person")
            for x0, y0 in ((0, 0), (mark.width - arm, 0), (0, mark.height - line), (mark.width - arm, mark.height - line)):
                self.assertEqual(alpha.crop((x0, y0, x0 + arm, y0 + line)).getextrema(), (255, 255), "a corner's arm")
            self.assertEqual(alpha.crop((arm, 0, mark.width - arm, mark.height)).getbbox(), None,
                             "nothing between the corners along the top and bottom")
            self.assertEqual(alpha.crop((0, arm, mark.width, mark.height - arm)).getbbox(), None,
                             "nothing between the corners along the sides")
            # ui.selection's line weight: the left stroke, a row under the top
            # stroke, is as wide on both marks.
            def weight(image):
                row = image.getchannel("A").crop((0, 3 * d, image.width // 2, 3 * d + 1))
                return row.getbbox()
            self.assertEqual(weight(mark), (0, 0, line, 1))
            self.assertEqual(weight(selection), (0, 0, line, 1), "the same weight as ui.selection")

    def test_refuses_an_occupied_output_and_writes_nothing(self):
        occupied = self.root / "occupied"
        occupied.mkdir()
        (occupied / "artist.png").write_bytes(b"artist work")
        with self.assertRaisesRegex(ValueError, "empty directory"):
            draw_pixel_sources.draw(ROOT / "art/daylight", occupied)
        self.assertEqual([path.name for path in occupied.iterdir()], ["artist.png"])
        self.assertEqual((occupied / "artist.png").read_bytes(), b"artist work")

    def test_a_desk_piece_on_the_rows_the_table_keeps_free_is_refused(self):
        palette = draw_pixel_sources.palette_of(ROOT / "art/daylight/pack.json")
        rows = list(draw_pixel_sources.DESK_PIECES["desk_mug"])
        rows[22] = "..........KK............"  # under the foot, where the lip is
        original = draw_pixel_sources.DESK_PIECES["desk_mug"]
        self.addCleanup(draw_pixel_sources.DESK_PIECES.__setitem__, "desk_mug", original)
        draw_pixel_sources.DESK_PIECES["desk_mug"] = tuple(rows)
        with self.assertRaisesRegex(ValueError, "desk_mug: paints rows 13..22"):
            draw_pixel_sources.desk_piece("desk_mug", palette)


class BuildCleanTests(unittest.TestCase):
    """`make art`'s last step, tools/check_build_clean.py, against a throwaway repository.

    Every kind of drift is a named line and exit 1, never a traceback, including
    a product the build wrote, staged, that HEAD has never held (`git show
    HEAD:<path>` has nothing to show).
    """

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git("init", "-q", ".")
        (self.root / "assets").mkdir()
        self.png("assets/a.png", (1, 2, 3, 255))
        self.git("add", "assets")
        self.git("-c", "user.name=test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                 "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "base")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def png(self, relative, colour, **options):
        Image.new("RGBA", (4, 4), colour).save(self.root / relative, **options)

    def check(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = check_build_clean.main(["assets"], root=self.root)
        return status, out.getvalue(), err.getvalue()

    def test_a_staged_new_product_is_named_drift_not_a_traceback(self):
        self.png("assets/b.png", (9, 9, 9, 255))
        self.git("add", "assets/b.png")
        status, _, err = self.check()
        self.assertEqual(status, 1)
        self.assertIn("new product (not in HEAD), commit it: assets/b.png", err)
        self.assertIn("rerun `make art` and commit the result", err)

    def test_every_other_drift_is_named_and_a_re_encode_is_not_drift(self):
        status, out, _ = self.check()
        self.assertEqual((status, out.strip()), (0, "CLEAN: assets/ matches the commit"))
        # Same pixels, other bytes: Pillow on another platform. Not drift.
        self.png("assets/a.png", (1, 2, 3, 255), compress_level=0)
        status, out, _ = self.check()
        self.assertEqual(status, 0)
        self.assertIn("same pixels, different PNG encoding: assets/a.png", out)
        self.png("assets/c.png", (4, 5, 6, 255))
        self.png("assets/a.png", (7, 8, 9, 255))
        status, _, err = self.check()
        self.assertEqual(status, 1)
        self.assertIn("untracked: assets/c.png", err)
        self.assertIn("modified: assets/a.png", err)
        (self.root / "assets/a.png").unlink()
        status, _, err = self.check()
        self.assertEqual(status, 1)
        self.assertIn("deleted: assets/a.png", err)


class ImportIfStaleTests(unittest.TestCase):
    """tools/import_if_stale.sh: Godot's import cache is brought up to date
    before a local Godot run reads the project, so a PNG `make art` rewrote is
    drawn without a manual `make import`.

    Run against a small tree (HERDSTEAD_ROOT) and a fake Godot that only
    records that it was asked to import: stale when the class cache or the
    import stamp is missing, a script is newer than the class cache, or a file
    under assets/, a scene or project.godot is newer than the stamp; fresh
    otherwise. One import stamps the tree, so the next run imports nothing; a
    failed import is tried once more and then fails loudly.
    """

    SCRIPT = ROOT / "tools/import_if_stale.sh"
    OLD = time.time() - 10000
    IMPORTED = time.time() - 5000
    CHANGED = time.time() - 1000

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for folder in ("scripts", "tools", "scenes", "assets/daylight/props", ".godot"):
            (self.root / folder).mkdir(parents=True)
        self.png = self.root / "assets/daylight/props/door.png"
        for path in (self.root / "scripts/a.gd", self.root / "scenes/a.tscn", self.root / "project.godot", self.png):
            path.write_text("x")
        # Everything, folders too (a file added to a folder changes the folder),
        # is old; `fresh()` stamps an import after that, and a change comes
        # after the import but before now (a real import stamps now).
        self.at(*self.root.rglob("*"), when=self.OLD)
        self.cache = self.root / ".godot/global_script_class_cache.cfg"
        self.stamp = self.root / ".godot/herdstead-import.stamp"
        self.calls = self.root / "calls"
        self.godot = self.root / "fake-godot"
        self.godot.write_text(f'#!/bin/sh\necho import >> "{self.calls}"\nexit "${{FAKE_STATUS:-0}}"\n')
        self.godot.chmod(0o755)

    @staticmethod
    def at(*paths, when):
        for path in paths:
            os.utime(path, (when, when))

    def run_script(self, *arguments, status=0):
        environment = dict(os.environ, HERDSTEAD_ROOT=str(self.root), GODOT=str(self.godot), FAKE_STATUS=str(status))
        return subprocess.run(["bash", str(self.SCRIPT), *arguments], capture_output=True, text=True, env=environment)

    def imports(self):
        return len(self.calls.read_text().splitlines()) if self.calls.exists() else 0

    def fresh(self):
        self.at(*self.root.rglob("*"), when=self.OLD)
        self.cache.write_text("x")
        self.stamp.write_text("")
        self.at(self.cache, self.stamp, when=self.IMPORTED)

    def test_a_fresh_tree_is_fresh_and_imports_nothing(self):
        self.fresh()
        check = self.run_script("--check")
        self.assertEqual((check.returncode, check.stdout.strip()), (0, "IMPORT_FRESH"))
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.imports(), 0)

    def test_every_reason_to_import_is_seen(self):
        self.fresh()
        self.at(self.png, when=self.CHANGED)  # `make art` rewrote a texture after the last import
        self.assertIn("assets/daylight/props/door.png is newer than the last import", self.run_script("--check").stdout)
        self.fresh()
        self.at(self.root / "scenes/a.tscn", when=self.CHANGED)
        self.assertIn("scenes/a.tscn is newer than the last import", self.run_script("--check").stdout)
        self.fresh()
        self.at(self.root / "project.godot", when=self.CHANGED)
        self.assertIn("project.godot is newer than the last import", self.run_script("--check").stdout)
        self.fresh()
        self.at(self.root / "scripts/a.gd", when=self.CHANGED)
        self.assertIn("scripts/a.gd is newer than the class cache", self.run_script("--check").stdout)
        self.fresh()
        self.stamp.unlink()
        self.assertIn("no import stamp", self.run_script("--check").stdout)
        self.fresh()
        self.cache.unlink()
        check = self.run_script("--check")
        self.assertEqual((check.returncode, check.stdout.strip()), (1, "IMPORT_STALE: no class cache"))
        self.assertEqual(self.imports(), 0, "--check never imports")

    def test_a_changed_png_is_imported_once_and_then_the_tree_is_fresh(self):
        self.fresh()
        self.at(self.png, when=self.CHANGED)
        first = self.run_script()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertIn("== importing project (assets/daylight/props/door.png is newer than the last import)", first.stdout)
        self.assertEqual(self.imports(), 1)
        self.assertEqual(self.run_script("--check").stdout.strip(), "IMPORT_FRESH")
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.imports(), 1, "a fresh tree is not imported again")

    def test_force_always_imports_and_a_failed_import_is_tried_once_more(self):
        self.fresh()
        self.assertEqual(self.run_script("--force").returncode, 0)
        self.assertEqual(self.imports(), 1)
        self.fresh()
        self.at(self.png, when=self.CHANGED)
        failed = self.run_script(status=1)
        self.assertEqual(failed.returncode, 2)
        self.assertIn("IMPORT_FAILED", failed.stdout)
        self.assertEqual(self.imports(), 3, "tried twice")
        self.assertIn("is newer than the last import", self.run_script("--check").stdout, "a failed import leaves it stale")


class TileFixTests(unittest.TestCase):
    """.claude/skills/painter/scripts/tilefix.py: the join pixels of a repainted tile.

    A repainted tile joins its neighbours only when the pixels the build
    compares are the old ones scaled up exactly; tilefix copies them in or
    checks them, and the few shape fixes (tileable, a one-colour panel middle,
    uniform table columns, slicing a sheet) do exactly what they say and
    nothing else. It never overwrites a file.
    """

    RED, BLUE, INK = (200, 40, 40, 255), (40, 40, 200, 255), (30, 30, 30, 255)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    @staticmethod
    def pattern(size, seed):
        """Every pixel different from its neighbours, so a copy is never a coincidence."""
        image = Image.new("RGBA", size)
        image.putdata([((x * 37 + seed) % 256, (y * 53 + seed) % 256, (x * y + seed) % 256, 255)
                       for y in range(size[1]) for x in range(size[0])])
        return image

    def save(self, image, name):
        path = self.root / name
        image.save(path)
        return path

    def tilefix(self, *arguments):
        return subprocess.run([sys.executable, str(PAINTER / "tilefix.py"), *map(str, arguments)],
                              capture_output=True, text=True)

    def test_edges_from_copies_the_old_bands_scaled_and_keeps_the_inside(self):
        old, new = self.pattern((8, 8), 1), self.pattern((16, 16), 99)
        inside = new.crop((4, 4, 12, 12)).tobytes()
        tilefix.edges_from(new, old, 4)
        big = old.resize((16, 16), Image.Resampling.NEAREST)
        self.assertEqual(tilefix.band_mismatches(new, old, 4), {"top": 0, "bottom": 0, "left": 0, "right": 0})
        for box in ((0, 0, 16, 4), (0, 12, 16, 16), (0, 0, 4, 16), (12, 0, 16, 16)):
            self.assertEqual(new.crop(box).tobytes(), big.crop(box).tobytes())
        self.assertEqual(new.crop((4, 4, 12, 12)).tobytes(), inside)

    def test_check_band_passes_the_fixed_tile_and_names_every_side_that_differs(self):
        old = self.save(self.pattern((8, 8), 1), "old.png")
        painted = self.pattern((16, 16), 99)
        raw = self.save(painted, "raw.png")
        failed = self.tilefix(raw, "--check-band", old, "--band", 4)
        self.assertEqual(failed.returncode, 1)
        for side in ("top", "bottom", "left", "right"):
            self.assertIn(f"{side}:", failed.stdout)
        tilefix.edges_from(painted, tilefix.load(old), 4)
        fixed = self.save(painted, "fixed.png")
        passed = self.tilefix(fixed, "--check-band", old, "--band", 4)
        self.assertEqual((passed.returncode, passed.stdout.strip()), (0, "OK"))
        # One changed pixel inside the band is caught, on the side it is on.
        painted.putpixel((15, 8), self.RED)
        one = self.tilefix(self.save(painted, "one.png"), "--check-band", old, "--band", 4)
        self.assertEqual(one.returncode, 1)
        self.assertIn("right: 1 px differ", one.stdout)
        self.assertNotIn("left:", one.stdout)

    def test_ports_are_boxes_in_old_pixels_copied_and_checked_scaled(self):
        old = self.save(self.pattern((8, 8), 7), "old.png")
        new = self.pattern((16, 16), 50)
        before = new.copy()
        tilefix.ports_from(new, tilefix.load(old), "0,3,1,5;7,0,8,8")
        big = tilefix.load(old).resize((16, 16), Image.Resampling.NEAREST)
        for box in ((0, 6, 2, 10), (14, 0, 16, 16)):
            self.assertEqual(new.crop(box).tobytes(), big.crop(box).tobytes())
        self.assertEqual(new.crop((2, 0, 14, 16)).tobytes(), before.crop((2, 0, 14, 16)).tobytes())
        ok = self.tilefix(self.save(new, "new.png"), "--check-ports", old, "--boxes", "0,3,1,5;7,0,8,8")
        self.assertEqual((ok.returncode, ok.stdout.strip()), (0, "OK"))
        bad = self.tilefix(self.save(before, "before.png"), "--check-ports", old, "--boxes", "0,3,1,5")
        self.assertEqual(bad.returncode, 1)
        self.assertIn("0,6,2,10:", bad.stdout)
        outside = self.tilefix(self.save(before, "b2.png"), "--check-ports", old, "--boxes", "7,0,9,8")
        self.assertEqual(outside.returncode, 2)

    def test_tileable_makes_opposite_edges_equal_and_touches_nothing_else(self):
        new = self.pattern((12, 10), 3)
        before = new.copy()
        tilefix.tileable(new)
        self.assertEqual(new.crop((11, 0, 12, 10)).tobytes(), new.crop((0, 0, 1, 10)).tobytes())
        self.assertEqual(new.crop((0, 9, 12, 10)).tobytes(), new.crop((0, 0, 12, 1)).tobytes())
        self.assertEqual(new.crop((0, 0, 11, 9)).tobytes(), before.crop((0, 0, 11, 9)).tobytes())

    def test_uniform_center_fills_the_stretched_middle_with_its_most_common_colour(self):
        new = Image.new("RGBA", (16, 16), self.INK)
        new.paste(Image.new("RGBA", (12, 12), self.BLUE), (2, 2))
        new.putpixel((8, 8), self.RED)
        new.putpixel((1, 1), self.RED)
        tilefix.uniform_center(new, 4)
        self.assertEqual(set(tilefix.pixels(new.crop((4, 4, 12, 12)))), {bytes(self.BLUE)})
        self.assertEqual(new.getpixel((1, 1)), self.RED)
        self.assertEqual(new.getpixel((0, 0)), self.INK)

    def test_columns_uniform_gives_each_row_one_colour_across_its_outer_columns(self):
        new = self.pattern((20, 6), 11)
        inner = new.crop((3, 0, 17, 6)).tobytes()
        tilefix.columns_uniform(new, 3)
        for y in range(6):
            self.assertEqual({new.getpixel((x, y)) for x in range(4)}, {new.getpixel((3, y))})
            self.assertEqual({new.getpixel((x, y)) for x in range(16, 20)}, {new.getpixel((16, y))})
        self.assertEqual(new.crop((3, 0, 17, 6)).tobytes(), inner)

    def test_slice_cuts_a_sheet_row_by_row_into_named_pieces(self):
        sheet = Image.new("RGBA", (6, 4))
        colours = [(i * 40, 0, 0, 255) for i in range(6)]
        for index, colour in enumerate(colours):
            sheet.paste(Image.new("RGBA", (2, 2), colour), (index % 3 * 2, index // 3 * 2))
        names = ["top_left", "top_center", "top_right", "bottom_left", "bottom_center", "bottom_right"]
        result = self.tilefix(self.save(sheet, "sheet.png"), "--slice", "3x2", "--size", "2x2",
                              "--names", ",".join(names), "--out", self.root / "pieces")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, colour in zip(names, colours):
            with Image.open(self.root / "pieces" / f"{name}.png") as piece:
                self.assertEqual((piece.size, set(tilefix.pixels(piece))), ((2, 2), {bytes(colour)}))
        wrong = self.tilefix(self.root / "sheet.png", "--slice", "3x3", "--size", "2x2",
                             "--names", ",".join(names + ["a", "b", "c"]), "--out", self.root / "other")
        self.assertEqual(wrong.returncode, 2)
        self.assertFalse((self.root / "other").exists())

    def test_it_refuses_a_size_that_is_no_whole_multiple_and_never_overwrites(self):
        old = self.save(self.pattern((8, 8), 1), "old.png")
        odd = self.save(self.pattern((12, 12), 2), "odd.png")
        refused = self.tilefix(odd, "--edges-from", old, "--band", 2, "--out", self.root / "out")
        self.assertEqual(refused.returncode, 2)
        self.assertIn("whole fraction", refused.stderr)
        new = self.save(self.pattern((16, 16), 2), "new.png")
        first = self.tilefix(new, "--edges-from", old, "--band", 2, "--out", self.root / "out")
        self.assertEqual(first.returncode, 0, first.stderr)
        written = (self.root / "out/new.png").read_bytes()
        again = self.tilefix(new, "--tileable", "--out", self.root / "out")
        self.assertEqual(again.returncode, 2)
        self.assertIn("exists", again.stderr)
        self.assertEqual((self.root / "out/new.png").read_bytes(), written)


if __name__ == "__main__":
    SOURCE = take_source_argument() or SOURCE
    unittest.main()
