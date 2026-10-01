"""Contract and seam checks for the modular shared-table art pack."""
from __future__ import annotations

import contextlib
import copy
import io
import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from build_table_assets import (CURSOR_AT, DENSITY, FURNITURE, LEGACY, LEGACY_POD, MODULES, POD_MODULES, POD_ONLY,
                                POD_SHARED, ROOT, SOURCE_SETS, build_pack, generate_templates)


THEMES = ("daylight",)


class SharedTableBuildTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "art"
        self.output = self.root / "assets"
        shutil.copytree(ROOT / "art/daylight", self.source)

    @staticmethod
    def tree_state(root):
        return {
            path.relative_to(root): (path.read_bytes(), path.stat().st_mtime_ns)
            for path in root.rglob("*") if path.is_file()
        }

    def test_build_preserves_artist_pixels_and_unlisted_source_files(self):
        # Asymmetric interior pixels distinguish copying from procedural redraws,
        # including the chair and laptop paths, not only wood modules. The
        # points are units of the 32-unit canvases, times DENSITY: the wood
        # under the divider, the chair's seat, the laptop's palmrest.
        ink = tuple(bytes.fromhex(json.loads((self.source / "pack.json").read_text())["palette"]["ink"])) + (255,)
        for name, (x, y) in (("surface_mid_a", (9, 41)), ("chair_front", (13, 35)), ("shell_front", (11, 28))):
            point = (x * DENSITY, y * DENSITY)
            path = self.source / "table" / f"{name}.png"
            with Image.open(path) as original:
                edited = original.copy()
            self.assertNotEqual(edited.getpixel(point), ink)
            edited.putpixel(point, ink)
            edited.save(path)
        (self.source / "table/artist-draft.png").write_bytes(b"unlisted work in progress")
        (self.source / "table/artist-draft.png.import").write_text("artist sidecar")
        manifest = self.source / "table/manifest.json"
        manifest.write_text(manifest.read_text() + "\n")
        before = self.tree_state(self.source)
        build_pack(self.source, self.output)
        self.assertEqual(self.tree_state(self.source), before, "normal builds must never write or prune source files")
        for name in ("surface_mid_a", "chair_front", "shell_front", "manifest"):
            filename = f"{name}.json" if name == "manifest" else f"{name}.png"
            self.assertEqual((self.output / "table" / filename).read_bytes(), before[Path("table") / filename][0])
        self.assertFalse((self.output / "table/artist-draft.png").exists())

    def test_invalid_sources_fail_before_writing_or_pruning(self):
        # A late module catches a builder that validates while copying. The
        # canvas is 32x32 units, DENSITY pixels each, so every bad image but the
        # one of the wrong size is drawn at the right size and is refused for
        # its own fault.
        side = 32 * DENSITY
        target = self.source / "table/shell_front.png"
        original = target.read_bytes()
        manifest = self.source / "table/manifest.json"
        original_manifest = manifest.read_bytes()
        reasons = {"missing": "shell_front", "corrupt": "shell_front", "size": f"expected \\({side}, {side}\\)",
                   "mode": "must be an RGBA PNG", "empty": "image is empty", "manifest": "native table contract"}
        for invalid, reason in reasons.items():
            with self.subTest(invalid=invalid):
                target.write_bytes(original)
                manifest.write_bytes(original_manifest)
                if invalid == "missing":
                    target.unlink()
                elif invalid == "corrupt":
                    target.write_bytes(b"not a PNG")
                elif invalid == "manifest":
                    data = json.loads(original_manifest)
                    data["modules"]["shell_front"]["size"] = [31, 32]
                    manifest.write_text(json.dumps(data))
                else:
                    Image.new("RGB" if invalid == "mode" else "RGBA",
                              (side - 1, side) if invalid == "size" else (side, side),
                              0 if invalid == "empty" else "red").save(target)
                self.output.mkdir(exist_ok=True)
                (self.output / "keep.png").write_bytes(b"prior build")
                before_source = self.tree_state(self.source)
                before_output = self.tree_state(self.output)
                with self.assertRaisesRegex(ValueError, reason):
                    build_pack(self.source, self.output)
                self.assertEqual(self.tree_state(self.source), before_source)
                self.assertEqual(self.tree_state(self.output), before_output)

    def test_repeated_builds_are_byte_and_mtime_stable_and_only_prune_output(self):
        before = self.tree_state(self.source)
        build_pack(self.source, self.output)
        first = self.tree_state(self.output)
        ghost = self.output / "table/obsolete.png"
        ghost.write_bytes(b"obsolete runtime art")
        ghost.with_suffix(".png.import").write_text("obsolete import")
        build_pack(self.source, self.output)
        self.assertEqual(self.tree_state(self.output), first)
        build_pack(self.source, self.output)
        self.assertEqual(self.tree_state(self.output), first)
        self.assertEqual(self.tree_state(self.source), before)

    def test_build_rejects_overlapping_source_and_output(self):
        before = self.tree_state(self.source)
        for output in (self.source, self.source / "nested", self.root):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "must not overlap"):
                build_pack(self.source, output)
        self.assertEqual(self.tree_state(self.source), before)

    def test_templates_are_explicit_repeatable_and_refuse_occupied_outputs(self):
        before = self.tree_state(self.source)
        for name in ("first", "second"):
            pack = self.root / name
            pack.mkdir()
            shutil.copyfile(self.source / "pack.json", pack / "pack.json")
            generate_templates(self.source, pack / "table")
            build_pack(pack, self.root / f"{name}-runtime")
        first = {path: data for path, (data, _) in self.tree_state(self.root / "first").items()}
        second = {path: data for path, (data, _) in self.tree_state(self.root / "second").items()}
        self.assertEqual(first, second)
        for occupied in (self.source / "table", self.source / "pack.json", self.root / "first/table"):
            with self.subTest(occupied=occupied), self.assertRaisesRegex(ValueError, "empty directory"):
                generate_templates(self.source, occupied)
        self.assertEqual(self.tree_state(self.source), before)
        self.assertEqual({path: data for path, (data, _) in self.tree_state(self.root / "first").items()}, first)


class SharedTableAssetTests(unittest.TestCase):
    def test_each_theme_has_the_same_native_module_contract(self):
        for theme in THEMES:
            source = ROOT / "art" / theme / "table"
            runtime = ROOT / "assets" / theme / "table"
            manifest = json.loads((source / "manifest.json").read_text())
            self.assertEqual(manifest["density"], DENSITY, theme)
            self.assertEqual((manifest["density"], manifest["filter"]), (2, "nearest"), f"{theme}: the shipped table is 2x, nearest")
            # Either accepted source set (build_table_assets.SOURCE_SETS), and
            # every module of the set it declares is checked below.
            declared = next((sizes for sizes in SOURCE_SETS.values() if set(manifest["modules"]) == set(sizes)), None)
            self.assertIsNotNone(declared, f"{theme}: modules are none of the accepted sets {sorted(SOURCE_SETS)}")
            self.assertEqual(manifest["assembly"], {
                "module_width": 32,
                "surface_depth": 80,
                "divider_height": 24,
                "apron_height": 3,
            })
            for name, logical_size in declared.items():
                info = manifest["modules"][name]
                self.assertEqual(info["size"], list(logical_size), f"{theme}/{name} manifest size")
                source_path = source / info["path"]
                runtime_path = runtime / info["path"]
                with Image.open(source_path) as image:
                    self.assertEqual(image.mode, "RGBA")
                    self.assertEqual(image.size, tuple(value * DENSITY for value in logical_size), f"{theme}/{name} size")
                    self.assertIsNotNone(image.getchannel("A").getbbox(), f"{theme}/{name} is empty")
                self.assertEqual(source_path.read_bytes(), runtime_path.read_bytes(), f"runtime copy drifted: {theme}/{name}")

            for furniture_id, info in manifest["furniture"].items():
                self.assertEqual(info["size"], list(FURNITURE[info["views"].get("front", info["views"].get("rear_shell"))]), theme)
                self.assertEqual(info["pivot"], [16, 46] if furniture_id == "chair" else [16, 30], theme)
                expected_views = {"front", "back"} if furniture_id == "chair" else {"rear_shell", "front_privacy", "shell_rear", "shell_front"}
                self.assertEqual(set(info["views"]), expected_views, theme)
                view_ids = list(info["views"].values())
                self.assertNotEqual(view_ids[0], view_ids[1], f"{theme}/{furniture_id} aliases one view")
                self.assertNotEqual(
                    (source / manifest["modules"][view_ids[0]]["path"]).read_bytes(),
                    (source / manifest["modules"][view_ids[1]]["path"]).read_bytes(),
                    f"{theme}/{furniture_id} views are identical",
                )

    def test_surface_and_divider_modules_join_without_transparent_seams(self):
        for theme in THEMES:
            root = ROOT / "art" / theme / "table"
            for prefix in ("surface", "divider"):
                mid_names = ["mid_a", "mid_b"] if prefix == "surface" else ["mid"]
                names = [f"{prefix}_left", *(f"{prefix}_{name}" for name in mid_names), f"{prefix}_right"]
                images = [Image.open(root / f"{name}.png") for name in names]
                try:
                    height = 75 * DENSITY if prefix == "surface" else images[0].height
                    # Compose an intentionally wide strip. Every internal join
                    # must have opaque pixels at the same rows; otherwise a
                    # repeated native module creates a visible vertical hole.
                    for left, right in zip(images, images[1:]):
                        self.assertEqual(left.getchannel("A").getbbox()[3], height, "thin surface has no old fascia below its lip")
                        self.assertEqual(left.getchannel("A").crop((left.width - 1, 0, left.width, height)).getbbox(), (0, 0, 1, height), f"{theme}/{prefix} right edge has a hole")
                        self.assertEqual(right.getchannel("A").crop((0, 0, 1, height)).getbbox(), (0, 0, 1, height), f"{theme}/{prefix} left edge has a hole")
                finally:
                    for image in images:
                        image.close()

    def test_wood_edges_match_in_colour_not_only_alpha(self):
        for prefix, mids in (("surface", ("mid_a", "mid_b")), ("apron", ("mid",))):
            for theme in THEMES:
                root = ROOT / "art" / theme / "table"
                for left in ("left", *mids):
                    for right in (*mids, "right"):
                        with Image.open(root / f"{prefix}_{left}.png") as a, \
                                Image.open(root / f"{prefix}_{right}.png") as b:
                            edge = a.crop((a.width - 1, 0, a.width, a.height)).tobytes()
                            self.assertEqual(edge, b.crop((0, 0, 1, b.height)).tobytes(),
                                             f"{theme}/{prefix}/{left}->{right} has a colour seam")
                            # Nearest sampling never reads past the seam, so one
                            # column is the structural contract; the three outer
                            # units (3 x DENSITY columns) are still one uniform
                            # band, the templates' rule, so no board detail is
                            # cut off at a module line wherever the planner
                            # repeats a module.
                            for offset in range(2, 3 * DENSITY + 1):
                                self.assertEqual(edge, a.crop((a.width - offset, 0, a.width - offset + 1, a.height)).tobytes())
                                self.assertEqual(edge, b.crop((offset - 1, 0, offset, b.height)).tobytes())

    def test_chairs_are_a_persons_scale_with_a_column_under_the_seat(self):
        for view in ("front", "back"):
            with Image.open(ROOT / f"art/daylight/table/chair_{view}.png") as daylight:
                alpha = daylight.getchannel("A")
                bounds = alpha.getbbox()
                # Every probe is a unit of the 32x48 canvas, times DENSITY.
                d = DENSITY
                self.assertEqual(daylight.size, (32 * d, 48 * d), "DENSITY texture pixels per unit")
                self.assertGreaterEqual(bounds[1], 22 * d, "the chair is at most 24 units tall")
                self.assertEqual(bounds[3], 46 * d, "chair feet left the common pivot")
                self.assertEqual(bounds[0] + bounds[2], 32 * d, "the chair centres on x=16")
                self.assertLessEqual(bounds[2] - bounds[0], 18 * d, "no wider than a seated worker and a unit a side")
                self.assertEqual(alpha.getpixel((16 * d, 26 * d)), 255, "missing backrest")
                self.assertEqual(alpha.getpixel((16 * d, 35 * d)), 255, "missing seat")
                self.assertEqual((alpha.getpixel((12 * d, 39 * d)), alpha.getpixel((16 * d, 39 * d)), alpha.getpixel((20 * d, 39 * d))),
                                 (0, 255, 0), "a gas-lift column, not a box, between the seat and the base")
                self.assertEqual(set(alpha.getdata()), {0, 255}, "chair has a translucent background")

    def test_laptops_are_low_centered_and_shell_marks_do_not_change_the_silhouette(self):
        for view in ("rear", "front"):
            for theme in THEMES:
                with Image.open(ROOT / f"art/{theme}/table/monitor_{view}.png") as normal, \
                        Image.open(ROOT / f"art/{theme}/table/shell_{view}.png") as shell:
                    alpha = normal.getchannel("A")
                    left, top, right, bottom = alpha.getbbox()
                    self.assertEqual(left + right, 32 * DENSITY, "silhouette must center on x=16")
                    self.assertGreaterEqual(top, (22 if view == "rear" else 19) * DENSITY,
                                            "rear lid must stay below the face when placed at the sitter's edge")
                    self.assertLessEqual(right - left, 14 * DENSITY, "narrower than the seated worker's shoulders")
                    self.assertEqual(bottom, 30 * DENSITY, "deck must reach the common foot pivot")
                    self.assertEqual(alpha.tobytes(), shell.getchannel("A").tobytes(), "shell is a marking, not a new shape")
                    self.assertEqual(set(alpha.getdata()), {0, 255}, "no translucent canvas or halo")
                    self.assertNotEqual(normal.tobytes(), shell.tobytes(), "shell prompt is actually painted")
                    palette = json.loads((ROOT / "art" / theme / "pack.json").read_text())["palette"]
                    mark = tuple(bytes.fromhex(palette["ink" if view == "rear" else "paper"])) + (255,)
                    cursor = CURSOR_AT[view]
                    self.assertEqual(shell.getpixel(cursor), mark, "shell cursor contrasts with silver lid or dark screen")
                    self.assertNotEqual(normal.getpixel(cursor), mark, "agent laptop has no shell cursor")
                    silver = tuple(bytes.fromhex(palette["muted"])) + (255,)
                    # Texel probes: the laptop is drawn texel by texel. The
                    # trackpad is a flat 6x2-texel pad, told from the silver
                    # palmrest by colour and centred by its two ends.
                    def at(x, y):
                        return normal.getpixel((x, y))
                    if view == "rear":
                        self.assertEqual(at(24, 48), silver, "lid is aluminum, not a dark monitor bezel")
                        self.assertEqual(at(32, 50), mark, "lid carries a dark centered logo")
                    else:
                        pad = at(32, 56)
                        self.assertEqual(at(22, 56), silver, "the palmrest is silver")
                        self.assertNotEqual(pad, silver, "the trackpad is distinct from the palmrest")
                        self.assertEqual((at(29, 56), at(34, 56)), (pad, pad),
                                         "trackpad is centered below the keyboard")
                        self.assertEqual((at(28, 56), at(35, 56)), (silver, silver),
                                         "and no wider than its six texels")
                        self.assertNotEqual(at(32, 52), silver, "keyboard is distinct from the palmrest")

    def test_tapered_legs_keep_floor_contact(self):
        for theme in THEMES:
            with Image.open(ROOT / f"art/{theme}/table/leg.png") as leg:
                alpha = leg.getchannel("A")
                # Unit rows, times DENSITY. Hung at y -2, a last unit row of 38
                # puts the foot on the floor at y 37.
                d = DENSITY
                self.assertEqual(alpha.getbbox()[3], 39 * d, "raised mount plus extended shaft preserves floor contact")
                shoulder = alpha.crop((0, 5 * d, alpha.width, 5 * d + 1)).getbbox()
                ankle = alpha.crop((0, 35 * d, alpha.width, 35 * d + 1)).getbbox()
                glide = alpha.crop((0, 37 * d, alpha.width, 37 * d + 1)).getbbox()
                self.assertLess(ankle[2] - ankle[0], shoulder[2] - shoulder[0], "shaft tapers towards the floor")
                self.assertLess(glide[2] - glide[0], shoulder[2] - shoulder[0], "no broad pedestal beneath the shaft")
                for y in range(39 * d):
                    self.assertIsNotNone(alpha.crop((0, y, alpha.width, y + 1)).getbbox(), "joint and glide stay attached")

    def test_builder_reproduces_runtime_modules(self):
        for theme in THEMES:
            source = ROOT / "art" / theme
            with tempfile.TemporaryDirectory() as temporary:
                temporary_root = Path(temporary)
                copied_source = temporary_root / "art"
                copied_output = temporary_root / "assets"
                shutil.copytree(source, copied_source)
                build_pack(copied_source, copied_output)
                declared = json.loads((source / "table/manifest.json").read_text())["modules"]
                for name in declared:
                    # Pixels, not bytes: Pillow's zlib output differs across
                    # platforms, so a rebuilt PNG need not match byte for byte.
                    with Image.open(ROOT / "assets" / theme / "table" / f"{name}.png") as expected, \
                            Image.open(copied_output / "table" / f"{name}.png") as actual:
                        self.assertEqual(actual.size, expected.size, f"builder drifted: {theme}/{name} size")
                        self.assertEqual(
                            actual.convert("RGBA").tobytes(),
                            expected.convert("RGBA").tobytes(),
                            f"builder drifted: {theme}/{name} pixels",
                        )


class PodSourceSetTests(unittest.TestCase):
    """The builder accepts the LEGACY module set, LEGACY plus POD, or the pod
    alone (POD_ONLY, what the office draws), told apart by the modules the
    manifest declares, and requires every image of that set. Built from fresh
    templates, so the cases hold whichever set art/ ships."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "art"
        self.source.mkdir()
        shutil.copyfile(ROOT / "art/daylight/pack.json", self.source / "pack.json")
        with contextlib.redirect_stdout(io.StringIO()):
            generate_templates(self.source, self.source / "table")
        self.manifest = self.source / "table/manifest.json"

    def build(self, name="runtime"):
        with contextlib.redirect_stdout(io.StringIO()):
            build_pack(self.source, self.root / name)
        return self.root / name / "table"

    def as_legacy(self):
        """Today's shape: the manifest without the pod modules and their images gone."""
        data = json.loads(self.manifest.read_text())
        for name in POD_MODULES:
            del data["modules"][name]
            (self.source / "table" / f"{name}.png").unlink()
        self.manifest.write_text(json.dumps(data, indent=2) + "\n")

    def as_pod(self):
        """The pod alone: the manifest without the long table's own modules and their images gone."""
        data = json.loads(self.manifest.read_text())
        for name in set(LEGACY_POD) - set(POD_ONLY):
            del data["modules"][name]
            (self.source / "table" / f"{name}.png").unlink()
        self.manifest.write_text(json.dumps(data, indent=2) + "\n")

    def test_the_sets_are_legacy_legacy_with_pod_and_the_pod_alone(self):
        self.assertEqual(set(SOURCE_SETS), {"legacy", "legacy+pod", "pod"})
        self.assertEqual(LEGACY, {**MODULES, **FURNITURE})
        self.assertEqual(LEGACY_POD, {**MODULES, **FURNITURE, **POD_MODULES})
        self.assertEqual(SOURCE_SETS["pod"], POD_ONLY)
        self.assertEqual(POD_ONLY, {**POD_MODULES, **{name: MODULES[name] for name in POD_SHARED}, **FURNITURE})
        self.assertEqual(set(LEGACY_POD) - set(POD_ONLY),
                         {"surface_left", "surface_mid_a", "surface_mid_b", "surface_right",
                          "divider_left", "divider_mid", "divider_right", "leg"},
                         "the pod alone leaves out the long table's surface, divider and leg, and nothing else")
        self.assertFalse(set(POD_MODULES) & set(LEGACY), "the pod adds modules, it renames none")
        self.assertEqual(POD_MODULES, {
            "desk_left": (32, 48), "desk_mid_a": (32, 48), "desk_mid_b": (32, 48), "desk_right": (32, 48),
            "screen_left": (32, 6), "screen_mid": (32, 6), "screen_right": (32, 6), "leg_short": (6, 22),
        })

    def test_templates_declare_legacy_with_pod_and_build(self):
        self.assertEqual(set(json.loads(self.manifest.read_text())["modules"]), set(LEGACY_POD))
        runtime = self.build()
        for name in LEGACY_POD:
            self.assertEqual((runtime / f"{name}.png").read_bytes(), (self.source / "table" / f"{name}.png").read_bytes(), name)

    def test_a_legacy_only_source_is_still_valid_and_builds_only_legacy(self):
        self.as_legacy()
        runtime = self.build()
        self.assertEqual({path.stem for path in runtime.glob("*.png")}, set(LEGACY))
        self.assertEqual(set(json.loads((runtime / "manifest.json").read_text())["modules"]), set(LEGACY))

    def test_a_pod_only_source_is_valid_and_builds_only_the_pod(self):
        self.as_pod()
        self.assertEqual(set(json.loads(self.manifest.read_text())["modules"]), set(POD_ONLY))
        runtime = self.build()
        self.assertEqual({path.stem for path in runtime.glob("*.png")}, set(POD_ONLY))
        self.assertEqual(set(json.loads((runtime / "manifest.json").read_text())["modules"]), set(POD_ONLY))
        for name in POD_ONLY:
            self.assertEqual((runtime / f"{name}.png").read_bytes(), (self.source / "table" / f"{name}.png").read_bytes(), name)
        # A pod-only source missing one of its images is refused, like any set.
        (self.source / "table" / "bracket.png").unlink()
        with self.assertRaisesRegex(ValueError, "bracket"):
            self.build("pod-missing-bracket")
        self.assertFalse((self.root / "pod-missing-bracket").exists(), "nothing written")

    def test_the_pod_only_set_is_exactly_what_the_office_draws(self):
        """POD_ONLY is the runtime's ArtContract.TABLE_MODULES (what OfficeTable lays)
        plus the furniture views (the chair, the laptop and its shell marks)."""
        source = (ROOT / "scripts/art/art_contract.gd").read_text()
        listed = re.search(r"const TABLE_MODULES: Array\[StringName\] = \[(.*?)\]", source, re.S)
        self.assertIsNotNone(listed, "art_contract.gd still names TABLE_MODULES as a literal list")
        runtime = set(re.findall(r'&"(\w+)"', listed.group(1)))
        self.assertEqual(len(runtime), 12, sorted(runtime))
        self.assertFalse(runtime & set(FURNITURE), "the furniture views are not table modules")
        self.assertEqual(set(POD_ONLY), runtime | set(FURNITURE))
        self.assertEqual(len(POD_ONLY), 18)
        self.assertEqual(runtime, set(POD_MODULES) | set(POD_SHARED))

    def test_a_pod_set_missing_one_image_is_refused_before_writing(self):
        for name in POD_MODULES:
            with self.subTest(name=name):
                target = self.source / "table" / f"{name}.png"
                original = target.read_bytes()
                target.unlink()
                try:
                    with self.assertRaisesRegex(ValueError, name):
                        self.build(f"missing-{name}")
                    self.assertFalse((self.root / f"missing-{name}").exists(), "nothing written")
                finally:
                    target.write_bytes(original)

    def test_a_manifest_that_is_not_its_sets_contract_is_refused(self):
        original = self.manifest.read_text()
        cases = {
            "size": lambda data: data["modules"]["leg_short"].__setitem__("size", [6, 24]),
            "path": lambda data: data["modules"]["desk_mid_a"].__setitem__("path", "desk_mid_b.png"),
            "assembly": lambda data: data["assembly"].__setitem__("surface_depth", 48),
        }
        for label, mutate in cases.items():
            with self.subTest(label=label):
                data = json.loads(original)
                mutate(data)
                self.manifest.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError, "native table contract"):
                    self.build(f"bad-{label}")
        self.manifest.write_text(original)

    def test_a_part_of_the_pod_set_or_an_unknown_module_is_refused(self):
        original = json.loads(self.manifest.read_text())
        partial = copy.deepcopy(original)
        del partial["modules"]["screen_mid"]
        unknown = copy.deepcopy(original)
        unknown["modules"]["desk_corner"] = {"path": "desk_corner.png", "size": [32, 48]}
        # The pod alone with one of the long table's modules left in is no set either.
        leftover = copy.deepcopy(original)
        for name in set(LEGACY_POD) - set(POD_ONLY) - {"leg"}:
            del leftover["modules"][name]
        for label, data, reason in (("partial", partial, r"nearest legacy\+pod, missing \['screen_mid'\]"),
                                    ("unknown", unknown, r"nearest legacy\+pod, .*unknown \['desk_corner'\]"),
                                    ("leftover", leftover, r"nearest pod, .*unknown \['leg'\]")):
            with self.subTest(label=label):
                self.manifest.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError, "none of the accepted sets \\(legacy, legacy\\+pod, pod\\).*" + reason):
                    self.build(f"bad-{label}")


def pod_tables():
    """Every table tree holding the pod modules: fresh templates, and each shipped
    theme once it declares them (so the checks follow the art when it lands)."""
    temporary = tempfile.TemporaryDirectory()
    root = Path(temporary.name)
    shutil.copyfile(ROOT / "art/daylight/pack.json", root / "pack.json")
    with contextlib.redirect_stdout(io.StringIO()):
        generate_templates(root, root / "table")
    trees = [("templates", root / "table")]
    for theme in THEMES:
        table = ROOT / "art" / theme / "table"
        if set(POD_MODULES) <= set(json.loads((table / "manifest.json").read_text())["modules"]):
            trees.append((theme, table))
    return temporary, trees


class PodModuleContractTests(unittest.TestCase):
    """The POD pixel contract in build_table_assets.py's docstring, rule by rule."""

    def setUp(self):
        temporary, self.trees = pod_tables()
        self.addCleanup(temporary.cleanup)

    def test_desks_keep_the_working_top_the_lip_and_a_clear_foot(self):
        d = DENSITY
        for label, table in self.trees:
            for end in ("left", "mid_a", "mid_b", "right"):
                with self.subTest(tree=label, end=end), Image.open(table / f"desk_{end}.png") as desk:
                    self.assertEqual(desk.size, (32 * d, 48 * d))
                    alpha = desk.getchannel("A")
                    self.assertEqual({value for _, value in alpha.getcolors()}, {0, 255}, "hard alpha")
                    self.assertEqual(alpha.crop((0, 0, 32 * d, 43 * d)).getextrema(), (255, 255),
                                     "rows 0..42 (the working top and the lip) are opaque")
                    self.assertEqual(alpha.crop((0, 43 * d, 32 * d, 48 * d)).getextrema(), (0, 0),
                                     "rows 43..47 are transparent: the apron continues the lip")

    def test_desk_modules_join_without_a_seam_in_alpha_or_colour(self):
        d = DENSITY
        for label, table in self.trees:
            for left in ("left", "mid_a", "mid_b"):
                for right in ("mid_a", "mid_b", "right"):
                    with self.subTest(tree=label, join=f"{left}->{right}"), \
                            Image.open(table / f"desk_{left}.png") as a, Image.open(table / f"desk_{right}.png") as b:
                        edge = a.crop((a.width - 1, 0, a.width, a.height)).tobytes()
                        self.assertEqual(edge, b.crop((0, 0, 1, b.height)).tobytes(), "a colour seam")
                        # The three outer units on each side are one uniform
                        # column, like the surface modules'.
                        for offset in range(2, 3 * d + 1):
                            self.assertEqual(edge, a.crop((a.width - offset, 0, a.width - offset + 1, a.height)).tobytes())
                            self.assertEqual(edge, b.crop((offset - 1, 0, offset, b.height)).tobytes())

    def test_screens_are_opaque_and_continue_their_panel_lines(self):
        d = DENSITY
        for label, table in self.trees:
            images = {end: Image.open(table / f"screen_{end}.png") for end in ("left", "mid", "right")}
            try:
                for end, screen in images.items():
                    with self.subTest(tree=label, end=end):
                        self.assertEqual(screen.size, (32 * d, 6 * d))
                        self.assertEqual(screen.getchannel("A").getextrema(), (255, 255), "a screen is fully opaque")
                # The panel repeats every 8 units, so a mid module continues
                # itself: its columns x and x + 8 units match across the join.
                mid = images["mid"]
                for x in range(mid.width - 8 * d, mid.width):
                    self.assertEqual(mid.crop((x, 0, x + 1, mid.height)).tobytes(),
                                     mid.crop((x - 8 * d, 0, x - 8 * d + 1, mid.height)).tobytes(), f"{label}: column {x}")
                for x in range(8 * d):
                    self.assertEqual(mid.crop((x, 0, x + 1, mid.height)).tobytes(),
                                     mid.crop((x + 8 * d, 0, x + 8 * d + 1, mid.height)).tobytes(), f"{label}: column {x}")
            finally:
                for screen in images.values():
                    screen.close()

    def test_the_short_leg_ends_on_row_20_attached_and_tapered(self):
        d = DENSITY
        for label, table in self.trees:
            with self.subTest(tree=label), Image.open(table / "leg_short.png") as leg:
                self.assertEqual(leg.size, (6 * d, 22 * d))
                alpha = leg.getchannel("A")
                self.assertEqual({value for _, value in alpha.getcolors()}, {0, 255}, "hard alpha")
                left, top, right, bottom = alpha.getbbox()
                self.assertEqual((top, bottom), (0, 21 * d), "hung at LEG_DROP -2, the foot ends at pod y 19")
                self.assertEqual(left + right, 6 * d, "centred on its canvas")
                for y in range(21 * d):
                    self.assertIsNotNone(alpha.crop((0, y, alpha.width, y + 1)).getbbox(), f"row {y} is attached")
                def span(unit_row):
                    box = alpha.crop((0, unit_row * d, alpha.width, unit_row * d + 1)).getbbox()
                    return box[2] - box[0]
                self.assertLess(span(19), span(4), "the glide is narrower than the shoulder")
                self.assertLess(span(14), span(4), "the shaft steps in")


if __name__ == "__main__":
    unittest.main()
