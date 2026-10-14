"""The shared case runner's public CLI contract, through the real Godot engine.

The tiny suites live in a throwaway project, so deliberate assertion and script
errors cannot corrupt the project's import cache or contact a real herdr.
Developer-tool tests remain engine-free; this target requires Godot.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROBE = '''extends "res://test_base.gd"

func _initialize() -> void:
	call_deferred("run_cases")

func _marker() -> String:
	return "HARNESS TESTS"

func _after_case() -> void:
	print("TEARDOWN " + current)
	if OS.get_cmdline_user_args().has("--slow-teardown"):
		OS.delay_msec(40)
	if current == "test_alpha" and OS.get_cmdline_user_args().has("--teardown-error"):
		var missing := root.get_node_or_null("missing")
		missing.get_child_count()

func test_zebra() -> void:
	print("BODY zebra")
	_check(true, "first case")

func test_alpha() -> void:
	print("BODY alpha")
	_check(true, "second case")
	await process_frame
	_eq(3, 3, "after yielding")
	if OS.get_cmdline_user_args().has("--assertion-failure"):
		_check(false, "deliberate assertion failure")
	if OS.get_cmdline_user_args().has("--runtime-error"):
		var missing := root.get_node_or_null("missing")
		missing.get_child_count()
		_check(false, "must not reach the rest of an aborted case")
'''


class HarnessTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        # The real warning-as-error settings apply to these probes too.
        shutil.copyfile(ROOT / "project.godot", self.root / "project.godot")
        shutil.copyfile(ROOT / "tools/test_base.gd", self.root / "test_base.gd")
        (self.root / "probe.gd").write_text(PROBE)

    def run_probe(self, *args):
        result = subprocess.run(
            [os.environ.get("GODOT", "godot"), "--headless", "--path", str(self.root),
             "--script", "probe.gd", "--", *args],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15,
        )
        self.assertNotIn("Parse Error", result.stdout)
        return result

    def test_full_discovery_keeps_source_order_and_times_teardown(self):
        result = self.run_probe("--slow-teardown")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("SCRIPT ERROR", result.stdout)
        self.assertEqual(re.findall(r"^CASE_START (\w+)$", result.stdout, re.M),
                         ["test_zebra", "test_alpha"])
        ends = re.findall(r"^PASS (\w+) \((\d+)ms, (\d+) checks\)$", result.stdout, re.M)
        self.assertEqual([(name, int(checks)) for name, _, checks in ends],
                         [("test_zebra", 1), ("test_alpha", 2)])
        for name, duration, _ in ends:
            self.assertGreaterEqual(int(duration), 35, "timing includes the 40ms teardown")
            self.assertLess(result.stdout.index("TEARDOWN " + name), result.stdout.index("PASS " + name))
        self.assertIn("HARNESS TESTS OK: 2 cases, 3 checks, 0 failures", result.stdout)

    def test_selection_runs_exactly_the_named_case_with_a_distinct_summary(self):
        result = self.run_probe("--case=test_alpha")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("SCRIPT ERROR", result.stdout)
        self.assertNotIn("BODY zebra", result.stdout)
        self.assertEqual(re.findall(r"^CASE_START (\w+)$", result.stdout, re.M), ["test_alpha"])
        self.assertIn("BODY alpha", result.stdout)
        self.assertIn("TEARDOWN test_alpha", result.stdout)
        self.assertIn("HARNESS TESTS FILTERED OK: 1 cases, 2 checks, 0 failures", result.stdout)
        self.assertNotIn("HARNESS TESTS OK:", result.stdout, "a focused run cannot satisfy a full gate")

    def test_invalid_or_repeated_selections_are_errors_without_running_any_case(self):
        for args in (("--case=test_missing",), ("--case=test_alph",), ("--case=test_*",),
                     ("--case=_marker",), ("--case=",), ("--case",),
                     ("--case=test_alpha", "--case=test_zebra")):
            with self.subTest(args=args):
                result = self.run_probe(*args)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn("TEST_HARNESS_ERROR:", result.stdout)
                self.assertNotIn("BODY ", result.stdout)
                self.assertNotIn("TEARDOWN ", result.stdout)
                self.assertNotIn("TESTS OK:", result.stdout)
                self.assertNotIn("FILTERED OK:", result.stdout)

    def test_assertion_runtime_and_teardown_errors_fail_the_responsible_case(self):
        for flag, checks in (("--assertion-failure", 3), ("--runtime-error", 2), ("--teardown-error", 2)):
            for focused in (False, True):
                with self.subTest(flag=flag, focused=focused):
                    args = (flag, "--case=test_alpha") if focused else (flag,)
                    result = self.run_probe(*args)
                    self.assertEqual(result.returncode, 1, result.stdout)
                    self.assertIn("TEARDOWN test_alpha", result.stdout)
                    self.assertRegex(result.stdout, r"(?m)^FAIL test_alpha \(\d+ms, \d+ checks\)$")
                    if not focused:
                        self.assertRegex(result.stdout, r"(?m)^PASS test_zebra ")
                    marker = "HARNESS TESTS FILTERED" if focused else "HARNESS TESTS"
                    self.assertIn(f"{marker} FAILED: {1 if focused else 2} cases, "
                                  f"{checks if focused else checks + 1} checks, 1 failures", result.stdout)
                    self.assertNotIn("must not reach the rest", result.stdout)
                    if flag != "--assertion-failure":
                        self.assertIn("script error:", result.stdout)

    def test_no_discovered_cases_is_a_harness_error(self):
        (self.root / "probe.gd").write_text(PROBE[:PROBE.index("func test_zebra")])
        result = self.run_probe()
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("TEST_HARNESS_ERROR: no test_ case found", result.stdout)
        self.assertNotIn("TESTS OK:", result.stdout)


if __name__ == "__main__":
    unittest.main()
