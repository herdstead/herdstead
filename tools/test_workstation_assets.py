"""Whole-image workstation fidelity, validation and deterministic-copy contracts."""
from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

from build_workstation_assets import (COLUMNS, DENSITY, EMPTY, FRAME_SIZE, IMAGE_SIZES, LOOPS,
                                      PALETTE_SIZE, PIVOT, PORTRAIT, ROOT, ROWS, SHEET,
                                      build_pack, validate_manifest, validate_source)


SOURCE = ROOT / "art/daylight/workstation"
APPROVED_ATLAS_SHA256 = "f324aca6550213182c4e9b0b36a671b9d5fec6d4826c9a4aee1500e820cd248e"
APPROVED_PORTRAIT_SHA256 = "58e64e8b6356495a8af88a20362d281e6401ea8c9a08cac901e3576c0422e75e"


class WorkstationSourceTests(unittest.TestCase):
    def test_approved_images_palette_and_other_state_timings_are_unchanged(self):
        # Byte pins cover every one of the 24 cells, including unused working
        # poses. They do not depend on an ignored build/ directory surviving.
        self.assertEqual(hashlib.sha256((SOURCE / SHEET).read_bytes()).hexdigest(), APPROVED_ATLAS_SHA256)
        self.assertEqual(hashlib.sha256((SOURCE / PORTRAIT).read_bytes()).hexdigest(), APPROVED_PORTRAIT_SHA256)
        approved = json.loads((SOURCE / "experiment.json").read_text())
        current = validate_source(SOURCE.parent)
        self.assertEqual(current["palette"], approved["palette"])
        for name, entry in approved["animations"].items():
            # The requested quieter working motion reuses the same paintings;
            # the historical experiment stays immutable, as do all other clips.
            if name != "working":
                self.assertEqual(current["animations"][name], entry, name)
        for name in ("starting", "unknown"):
            self.assertEqual(current["animations"][name], {"frames": [0], "seconds": [1.0], "loop": False})
        self.assertEqual(len(approved["measurements"]), 24)
        self.assertEqual(FRAME_SIZE, (80, 80))
        self.assertEqual(PIVOT, (37.5, 70))
        self.assertEqual((DENSITY, COLUMNS, ROWS), (2, 4, 6))

    def test_working_keeps_typing_without_shoulder_bobbing_or_constant_head_dips(self):
        working = validate_source(SOURCE.parent)["animations"]["working"]
        frames, seconds = working["frames"], working["seconds"]
        duration = sum(seconds)
        # In the byte-pinned sheet, poses 0..3 keep the head neutral; 4..7
        # lower it one texel. Both groups keep the shoulders stationary.
        self.assertTrue(working["loop"])
        self.assertTrue(set(frames) <= set(range(8)), "no two-texel head or moving-shoulder poses")
        hands = [frame % 4 for frame in frames]  # rest, left, right, left ring
        self.assertTrue({1, 2} <= set(hands), "working still types with both hands, unlike idle")
        presses = sum(previous == 0 and current != 0 for previous, current in zip(hands[-1:] + hands[:-1], hands))
        self.assertLessEqual(presses / duration, 3.0, "not the previous four presses per second")
        self.assertGreaterEqual(presses / duration, 1.0, "still visibly working, not an idle hold")
        dips = sum(previous < 4 <= current for previous, current in zip(frames[-1:] + frames[:-1], frames))
        self.assertGreaterEqual(dips, 1, "retain an occasional small head movement")
        self.assertLessEqual(dips / duration, 0.25, "head dips at most once in four seconds")
        self.assertTrue(any(hand == 0 and hold >= 0.3 for hand, hold in zip(hands, seconds)),
                        "short hands-on-keys pauses between typing bursts")

        # Inspect two cycles so a loop boundary cannot hide a metronomic beat.
        # A head change can split a single key press or rest across two frames.
        bursts, pauses = [], []
        presses_in_burst, rest = 0, 0.0
        for index in range(len(frames) * 2):
            hand, hold = hands[index % len(hands)], seconds[index % len(seconds)]
            previous = hands[(index - 1) % len(hands)]
            if hand == 0:
                rest += hold
            else:
                if previous == 0:
                    if rest >= 0.3:
                        bursts.append(presses_in_burst)
                        pauses.append(rest)
                        presses_in_burst = 0
                    presses_in_burst += 1
                rest = 0.0
        self.assertGreaterEqual(len(bursts), 3, "several typing phrases, not one long burst")
        self.assertGreater(len(set(bursts[1:])), 1, "exclude the first partial phrase; not equal tap groups")
        self.assertGreaterEqual(max(pauses) - min(pauses), 0.16, "noticeably different pauses, not timing jitter")

    def test_all_runtime_images_are_exact_copies_at_native_size_with_hard_alpha(self):
        data = validate_source(SOURCE.parent)
        palette = {tuple(bytes.fromhex(value)) for value in data["palette"].values()}
        self.assertEqual(len(palette), 37)
        for name, size in IMAGE_SIZES.items():
            with self.subTest(image=name), Image.open(SOURCE / name) as image:
                self.assertEqual(image.size, size)
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual({value for _, value in image.getchannel("A").getcolors()}, {0, 255})
                colors = image.getcolors(PALETTE_SIZE + 1)
                self.assertIsNotNone(colors)
                self.assertTrue(all(not rgba[3] or rgba[:3] in palette for _, rgba in colors))
                self.assertEqual((ROOT / "assets/daylight/workstation" / name).read_bytes(), (SOURCE / name).read_bytes())
        self.assertEqual((ROOT / "assets/daylight/workstation/manifest.json").read_bytes(),
                         (SOURCE / "manifest.json").read_bytes())

    def test_empty_removes_person_and_hands_without_changing_the_desk_or_monitors(self):
        with Image.open(SOURCE / SHEET) as sheet, Image.open(SOURCE / EMPTY) as empty:
            original = sheet.crop((0, 0, 160, 160))
            reclined = sheet.crop((3 * 160, 4 * 160, 4 * 160, 5 * 160))  # pose 19, hands off keys
            self.assertEqual(empty.getchannel("A").crop((0, 0, 160, 54)).getextrema(), (0, 0))
            self.assertEqual(empty.getchannel("A").crop((41, 134, 111, 139)).getextrema(), (0, 0),
                             "no shoes left below the exposed chair")
            self.assertEqual(empty.getpixel((74, 117))[3], 255, "chair gas lift survives")
            self.assertEqual({rgba for _, rgba in empty.crop((50, 54, 95, 55)).getcolors()}, {(42, 34, 49, 255)},
                             "the exposed monitor rim has no neck or collar remnants")
            for x in range(50, 95):
                expected = (27, 22, 36, 255) if x == 79 else (98, 102, 122, 255)
                self.assertEqual(empty.getpixel((x, 55)), expected, "clean bevel with the centre seam retained")
            changed_regions = Image.new("L", empty.size)
            draw = ImageDraw.Draw(changed_regions)
            boxes = ((0, 0, 160, 54), (41, 102, 111, 139), (50, 54, 95, 56),
                     (64, 81, 76, 86), (81, 81, 94, 86))
            for left, top, right, bottom in boxes:
                draw.rectangle((left, top, right - 1, bottom - 1), fill=255)
            for channel in "RGBA":
                delta = ImageChops.difference(original.getchannel(channel), empty.getchannel(channel))
                self.assertIsNone(ImageChops.multiply(delta, ImageChops.invert(changed_regions)).getbbox(),
                                  "all other furniture pixels must stay exactly as approved")
            for box in boxes[-2:]:
                self.assertEqual(empty.crop(box).tobytes(), reclined.crop(box).tobytes(), "no keyboard hands")


class WorkstationBuildTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source, self.output = self.root / "art", self.root / "assets"
        self.family = self.source / "workstation"
        shutil.copytree(SOURCE, self.family)
        self.manifest_path = self.family / "manifest.json"
        self.manifest = json.loads(self.manifest_path.read_text())

    @staticmethod
    def tree_state(root):
        return {path.relative_to(root): (path.read_bytes(), path.stat().st_mtime_ns)
                for path in root.rglob("*") if path.is_file()}

    def build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            build_pack(self.source, self.output)

    def test_build_copies_authored_edits_and_manifest_bytes_without_touching_sources(self):
        color = (*bytes.fromhex(self.manifest["palette"]["cream"]), 255)
        for name, point in ((SHEET, (75, 40)), (EMPTY, (70, 95)), (PORTRAIT, (40, 40))):
            path = self.family / name
            with Image.open(path) as source:
                edited = source.copy()
            self.assertNotEqual(edited.getpixel(point), color)
            edited.putpixel(point, color)
            edited.save(path)
        self.manifest_path.write_text(self.manifest_path.read_text() + "\n")
        (self.family / "artist-draft.png").write_bytes(b"unfinished drawing, not a PNG yet")
        (self.family / "artist-draft.png.import").write_text("artist sidecar")
        before = self.tree_state(self.source)
        self.build()
        self.assertEqual(self.tree_state(self.source), before)
        for name in (*IMAGE_SIZES, "manifest.json"):
            self.assertEqual((self.output / "workstation" / name).read_bytes(), (self.family / name).read_bytes())
        self.assertEqual({path.name for path in (self.output / "workstation").iterdir()},
                         set(IMAGE_SIZES) | {"manifest.json"})

    def test_transparent_rgb_is_not_a_palette_colour_and_is_copied_verbatim(self):
        # Invisible RGB is not part of a nearest family's visible palette.
        # An editor may leave many different values under hard-zero alpha.
        target = self.family / PORTRAIT
        with Image.open(target) as source:
            image = source.copy()
        for x in range(40):
            self.assertEqual(image.getpixel((x, 0))[3], 0)
            image.putpixel((x, 0), (x + 1, 2, 3, 0))
        image.save(target)
        before = target.read_bytes()
        self.build()
        self.assertEqual(target.read_bytes(), before)
        self.assertEqual((self.output / "workstation" / PORTRAIT).read_bytes(), before)

    def test_rebuilds_are_byte_and_mtime_stable_and_preserve_retained_imports(self):
        self.build()
        target = self.output / "workstation"
        for name in IMAGE_SIZES:
            (target / f"{name}.import").write_text(f"retained import for {name}")
        before = self.tree_state(self.output)
        source_before = self.tree_state(self.source)
        self.build()
        self.assertEqual(self.tree_state(self.output), before)
        (target / "obsolete.png").write_bytes(b"old runtime image")
        (target / "obsolete.png.import").write_text("old sidecar")
        (target / "orphan.png.import").write_text("orphan sidecar")
        outside = self.output / "other-family.png"
        outside.write_bytes(b"not ours")
        outside_before = (outside.read_bytes(), outside.stat().st_mtime_ns)
        self.build()
        self.assertEqual(self.tree_state(self.output), {**before, Path(outside.name): outside_before})
        self.assertEqual(self.tree_state(self.source), source_before)

    def test_source_and_output_must_not_overlap(self):
        before = self.tree_state(self.source)
        for output in (self.source, self.source / "inside", self.root):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, "must not overlap"):
                build_pack(self.source, output)
        self.assertEqual(self.tree_state(self.source), before)

    def test_bad_late_image_fails_before_copying_or_pruning(self):
        self.build()
        target = self.family / PORTRAIT  # the last image validated
        original = target.read_bytes()
        stale = self.output / "workstation/keep-until-validation.png"
        stale.write_bytes(b"last good build")
        reasons = {"missing": PORTRAIT, "corrupt": PORTRAIT, "size": "expected",
                   "mode": "RGBA PNG", "empty": "image is empty", "format": "RGBA PNG",
                   "soft": "alpha must be hard", "palette": "workstation palette"}
        for invalid, reason in reasons.items():
            with self.subTest(invalid=invalid):
                target.write_bytes(original)
                if invalid == "missing":
                    target.unlink()
                elif invalid == "corrupt":
                    target.write_bytes(b"not an image")
                else:
                    with Image.open(target) as source:
                        image = source.copy()
                    if invalid == "size":
                        image = image.crop((0, 0, 79, 80))
                    elif invalid == "mode":
                        image = image.convert("RGB")
                    elif invalid == "empty":
                        image.paste((0, 0, 0, 0), (0, 0, 80, 80))
                    elif invalid == "soft":
                        image.putpixel((40, 40), (*image.getpixel((40, 40))[:3], 127))
                    elif invalid == "palette":
                        image.putpixel((40, 40), (1, 2, 3, 255))
                    image.save(target, format="BMP" if invalid == "format" else "PNG")
                before_source, before_output = self.tree_state(self.source), self.tree_state(self.output)
                with self.assertRaisesRegex(ValueError, reason):
                    self.build()
                self.assertEqual(self.tree_state(self.source), before_source)
                self.assertEqual(self.tree_state(self.output), before_output)

    def test_each_atlas_cell_must_contain_art(self):
        target = self.family / SHEET
        with Image.open(target) as source:
            image = source.copy()
        image.paste((0, 0, 0, 0), (3 * 160, 5 * 160, 4 * 160, 6 * 160))
        image.save(target)
        with self.assertRaisesRegex(ValueError, "frame 23 is empty"):
            self.build()
        self.assertFalse(self.output.exists())

    def test_malformed_manifest_types_geometry_paths_and_palette_are_refused(self):
        mutations = {
            "missing": lambda m: m.pop("id"),
            "unknown": lambda m: m.update(extra=True),
            "version": lambda m: m.update(schema_version=True),
            "id": lambda m: m.update(id=[]),
            "name": lambda m: m.update(name=""),
            "density": lambda m: m.update(density="2"),
            "filter": lambda m: m.update(filter="linear"),
            "frame_size": lambda m: m.update(frame_size=[80.5, 80]),
            "fractional near integer": lambda m: m.update(frame_size=[80.0000001, 80]),
            "pair type": lambda m: m.update(frame_size="80,80"),
            "pivot": lambda m: m.update(pivot=[37, 70]),
            "nonfinite": lambda m: m.update(pivot=[float("inf"), 70]),
            "columns": lambda m: m.update(columns=3),
            "rows": lambda m: m.update(rows=6.5),
            "image path": lambda m: m.update(image="../state-workstation.png"),
            "empty path": lambda m: m.update(empty_image=0),
            "portrait type": lambda m: m.update(portrait=[]),
            "portrait path": lambda m: m["portrait"].update(image="/absolute.png"),
            "portrait size": lambda m: m["portrait"].update(size=[80, 80]),
            "portrait pivot": lambda m: m["portrait"].update(pivot=[20, True]),
            "palette type": lambda m: m.update(palette=[]),
            "palette count": lambda m: m["palette"].pop("cream"),
            "palette duplicate": lambda m: m["palette"].update(cream=m["palette"]["deep"]),
            "palette RGB": lambda m: m["palette"].update(cream="nothex"),
            "palette alpha": lambda m: m["palette"].update(cream="ffeeddff"),
            "signed hex": lambda m: m["palette"].update(cream="-12345"),
            "prefixed hex": lambda m: m["palette"].update(cream="0x1234"),
        }
        for label, mutate in mutations.items():
            with self.subTest(contract=label):
                manifest = copy.deepcopy(self.manifest)
                mutate(manifest)
                self.manifest_path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    self.build()
                self.assertFalse(self.output.exists(), "a bad manifest must write nothing")
        for value in (None, [], "manifest", 12):
            with self.subTest(manifest=value), self.assertRaisesRegex(ValueError, "JSON object"):
                validate_manifest(value)

    def test_missing_unknown_and_malformed_tracks_are_refused(self):
        for name in LOOPS:
            manifest = copy.deepcopy(self.manifest)
            del manifest["animations"][name]
            with self.subTest(missing=name), self.assertRaisesRegex(ValueError, "animations must declare exactly"):
                validate_manifest(manifest)
        for value in ([], None, {"idle": {}}, {**self.manifest["animations"], "surprise": {}}):
            with self.subTest(animations=value), self.assertRaisesRegex(ValueError, "animations must declare exactly"):
                validate_manifest({**self.manifest, "animations": value})
        for value in (None, [], {}, {"frames": [], "seconds": [], "loop": True},
                      {"frames": [0, 1], "seconds": [0.1], "loop": True},
                      {"frames": "0", "seconds": [0.1], "loop": True},
                      {"frames": [0], "seconds": "0.1", "loop": True},
                      {"frames": [0], "seconds": [0.1], "loop": 1}):
            manifest = copy.deepcopy(self.manifest)
            manifest["animations"]["idle"] = value
            with self.subTest(track=value), self.assertRaisesRegex(ValueError, "animation idle"):
                validate_manifest(manifest)

    def test_frames_and_durations_are_checked_before_they_are_used(self):
        bad_frames = (-1, 24, 1.5, True, "1", None, float("nan"), float("inf"), 10 ** 400)
        bad_seconds = (0, -0.1, True, "0.1", None, float("nan"), float("inf"), 10 ** 400)
        for field, values in (("frames", bad_frames), ("seconds", bad_seconds)):
            for value in values:
                manifest = copy.deepcopy(self.manifest)
                manifest["animations"]["working"][field][0] = value
                with self.subTest(field=field, value=value), self.assertRaisesRegex(ValueError, "animation working"):
                    validate_manifest(manifest)
        for seconds in ([1e308, 1e308], [1e30, 0.01]):
            manifest = copy.deepcopy(self.manifest)
            manifest["animations"]["idle"] = {"frames": [0, 1], "seconds": seconds, "loop": True}
            with self.subTest(seconds=seconds), self.assertRaisesRegex(ValueError, "duration sum"):
                validate_manifest(manifest)

    def test_state_loops_and_static_aliases_cannot_silently_change(self):
        for name, loop in LOOPS.items():
            manifest = copy.deepcopy(self.manifest)
            manifest["animations"][name]["loop"] = not loop
            with self.subTest(loop=name), self.assertRaisesRegex(ValueError, "incorrect loop flag"):
                validate_manifest(manifest)
        for name in ("starting", "unknown"):
            manifest = copy.deepcopy(self.manifest)
            manifest["animations"][name]["frames"] = [1]
            with self.subTest(still=name), self.assertRaisesRegex(ValueError, "must hold frame 0"):
                validate_manifest(manifest)

    def test_whole_json_floats_remain_valid_and_no_theme_palette_is_needed(self):
        manifest = copy.deepcopy(self.manifest)
        for key in ("schema_version", "density", "columns", "rows"):
            manifest[key] = float(manifest[key])
        manifest["frame_size"] = [80.0, 80.0]
        for entry in manifest["animations"].values():
            entry["frames"] = [float(frame) for frame in entry["frames"]]
        self.manifest_path.write_text(json.dumps(manifest))
        self.assertFalse((self.source / "pack.json").exists(), "this is an independent companion family")
        self.build()
        self.assertEqual((self.output / "workstation/manifest.json").read_bytes(), self.manifest_path.read_bytes())


if __name__ == "__main__":
    unittest.main()
