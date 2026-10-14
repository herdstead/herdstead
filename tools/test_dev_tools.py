"""Developer command contracts, exercised through their CLI in throwaway trees.

The runner uses the real fake herdr and a small engine stand-in: these cases
check selection, process isolation and failure reporting, not Godot behaviour.
The real suites still run, unchanged, in `make check`.
"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import lint_changed


ROOT = Path(__file__).resolve().parents[1]


class RunnerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        tools = self.root / "tools"
        tools.mkdir()
        for name in ("run_tests.sh", "import_if_stale.sh", "fake_ssh.py"):
            shutil.copyfile(ROOT / "tools" / name, tools / name)
        shutil.copyfile(ROOT / "tools/fake_herdr.py", tools / "server.py")
        shutil.copytree(ROOT / "tools/fixtures", tools / "fixtures")
        # Existing files are not necessarily runnable suites (test_base.gd).
        for source in (ROOT / "tools").glob("*.gd"):
            (tools / source.name).touch()
        (self.root / "scripts").mkdir()
        (self.root / "scenes").mkdir()
        (self.root / "assets").mkdir()
        (self.root / ".godot").mkdir()
        (self.root / ".godot/global_script_class_cache.cfg").touch()
        (self.root / ".godot/herdstead-import.stamp").touch()
        self.calls = self.root / "engine-calls.jsonl"
        self.fakes = self.root / "fake-pids"
        (tools / "fake_herdr.py").write_text(
            'import os, runpy, sys\n'
            'with open(os.environ["FAKE_PIDS"], "a") as out: out.write(str(os.getpid()) + "\\n")\n'
            'if os.environ["ENGINE_RESULT"] == "fake-start-failure" and any(\n'
            '    arg.startswith("--socket=") and arg.endswith("-b.sock") for arg in sys.argv):\n'
            '    sys.exit("deliberate fake startup failure")\n'
            f'runpy.run_path({str(tools / "server.py")!r}, run_name="__main__")\n'
        )
        (tools / "test_table_assets.py").write_text('print("UNRELATED_PYTHON_TESTS")\n')
        self.engine = self.root / "engine"
        self.engine.write_text(f"#!{sys.executable}\n" + '''import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
script = Path(args[args.index("--script") + 1]).stem
alive = []
pids = Path(os.environ["FAKE_PIDS"])
for pid in pids.read_text().splitlines() if pids.exists() else []:
    try:
        os.kill(int(pid), 0)
        alive.append(int(pid))
    except ProcessLookupError:
        pass
with open(os.environ["ENGINE_CALLS"], "a") as out:
    out.write(json.dumps({"suite": script, "args": args, "fakes": alive}) + "\\n")
mode = os.environ.get("ENGINE_RESULT", "ok")
print("engine running " + script, flush=True)
if mode == "timeout":
    print("CASE_START test_finished")
    print("PASS test_finished (0ms, 1 checks)")
    print("CASE_START test_waiting", flush=True)
    print("waiting in " + script, flush=True)
    time.sleep(30)
if mode == "script-error":
    print("SCRIPT ERROR: deliberate engine error")
if mode == "parse-error":
    print("Parse Error: deliberate engine error")
marker, count = {
    "test_card_picture": ("CARD PICTURE TESTS", 27),
    "test_pick_follows_write": ("PICK FOLLOWS WRITE TESTS", 20),
    "test_launch_news": ("LAUNCH NEWS TESTS", 5),
    "test_refusal_ladder": ("REFUSAL LADDER TESTS", 23),
}[script]
selected = [arg.removeprefix("--case=") for arg in args if arg.startswith("--case=")]
if selected and mode != "ignore-case":
    marker += " FILTERED"
    count = 0 if mode == "zero-cases" else 2 if mode == "extra-cases" else 1
    name = "test_wrong" if mode == "wrong-case" else selected[0]
    print("CASE_START " + name)
    print(f"PASS {name} (0ms, 1 checks)")
if mode == "failed-cases":
    for name in ("test_first_failure", "test_second_failure"):
        print("CASE_START " + name)
        print(f"FAIL {name} (2ms, 1 checks)")
    print("CASE_START test_finished")
    print("PASS test_finished (0ms, 1 checks)")
    print(f"{marker} FAILED: {count} cases, 3 checks, 2 failures, 0.0s")
    sys.exit(1)
if mode != "missing-marker":
    print(f"{marker} OK: {count - (mode == 'too-few')} cases, 1 checks, 0 failures, 0.0s")
sys.exit(7 if mode == "nonzero" else 0)
''')
        self.engine.chmod(0o755)

    def run_suites(self, suites, mode="ok", case="", tier=""):
        self.calls.unlink(missing_ok=True)
        self.fakes.unlink(missing_ok=True)
        environment = dict(os.environ, GODOT=str(self.engine), PYTHON=sys.executable,
                           SUITES=suites, CASE=case, TIER=tier, HERDSTEAD_SKIP_LOAD_CHECKS="1",
                           ENGINE_CALLS=str(self.calls), FAKE_PIDS=str(self.fakes), ENGINE_RESULT=mode,
                           RUN_TIMEOUT="1" if mode == "timeout" else "10")
        return subprocess.run(["bash", str(self.root / "tools/run_tests.sh")],
                              capture_output=True, text=True, env=environment, timeout=30)

    def engine_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def fake_pids(self):
        return [int(line) for line in self.fakes.read_text().splitlines()] if self.fakes.exists() else []

    def test_a_pure_selection_runs_only_its_suites_without_python_or_servers(self):
        result = self.run_suites("test_card_picture\t test_pick_follows_write\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([call["suite"] for call in self.engine_calls()],
                         ["test_card_picture", "test_pick_follows_write"])
        self.assertEqual(self.fake_pids(), [], "pure suites must not start fake servers")
        self.assertNotIn("UNRELATED_PYTHON_TESTS", result.stdout)

    def test_unknown_or_empty_selections_fail_before_any_suite_starts(self):
        for selection in ("test_base", "test_no_such_suite", "test_card_picture test_base", " \t\n "):
            with self.subTest(selection=selection):
                result = self.run_suites(selection)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(self.engine_calls(), [])
                self.assertEqual(self.fake_pids(), [])

    def test_case_selection_reaches_pure_and_connected_suites_as_a_user_argument(self):
        for suite, fakes in (("test_card_picture", 0), ("test_launch_news", 2)):
            with self.subTest(suite=suite):
                result = self.run_suites(suite, case="test_selected")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = self.engine_calls()
                self.assertEqual(len(calls), 1)
                args = calls[0]["args"]
                self.assertEqual(args.count("--"), 1)
                self.assertIn("--case=test_selected", args[args.index("--") + 1:])
                self.assertEqual(len(self.fake_pids()), fakes)
                self.assertIn("FILTERED OK: 1 cases", result.stdout)
                self.assertNotIn("UNRELATED_PYTHON_TESTS", result.stdout)

    def test_case_selection_requires_one_explicit_suite_before_starting_anything(self):
        for suites, tier in (("", ""), ("test_card_picture test_launch_news", ""),
                             ("test_card_picture", "quick")):
            with self.subTest(suites=suites, tier=tier):
                result = self.run_suites(suites, case="test_selected", tier=tier)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(self.engine_calls(), [])
                self.assertEqual(self.fake_pids(), [])

    def test_filtered_success_must_report_exactly_the_requested_case(self):
        for mode in ("ignore-case", "zero-cases", "extra-cases", "wrong-case",
                     "script-error", "parse-error", "missing-marker", "nonzero"):
            with self.subTest(mode=mode):
                result = self.run_suites("test_card_picture", mode, case="test_selected")
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("S=test_card_picture CASE=test_selected", result.stdout)

    def test_printed_reruns_override_exported_filters_for_full_and_exact_runs(self):
        shutil.copyfile(ROOT / "Makefile", self.root / "Makefile")
        result = self.run_suites("test_card_picture", "script-error", case="test_selected")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        prefix = "RUN_TESTS: rerun with "
        commands = [line.removeprefix(prefix) for line in result.stdout.splitlines() if line.startswith(prefix)]
        self.assertEqual(len(commands), 2, result.stdout)
        environment = dict(os.environ, CASE="test_leaked", SUITES="test_wrong", TIER="quick",
                           ENGINE_CALLS=str(self.calls), FAKE_PIDS=str(self.fakes), ENGINE_RESULT="ok")
        for command, summary in zip(commands, ("TESTS OK: 27 cases", "TESTS FILTERED OK: 1 cases")):
            with self.subTest(command=command):
                rerun = subprocess.run(["bash", "-c", command], capture_output=True, text=True,
                                       env=environment, timeout=30)
                self.assertEqual(rerun.returncode, 0, rerun.stdout + rerun.stderr)
                self.assertIn(summary, rerun.stdout)
                self.assertNotIn("test_leaked", rerun.stdout)

    def test_failed_cases_and_the_unfinished_case_have_exact_rerun_commands(self):
        result = self.run_suites("test_card_picture", "failed-cases")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("S=test_card_picture CASE=test_first_failure", result.stdout)
        self.assertIn("S=test_card_picture CASE=test_second_failure", result.stdout)
        self.assertNotIn("CASE=test_finished", result.stdout)
        self.assertNotIn("last unfinished case:", result.stdout)
        result = self.run_suites("test_card_picture", "timeout")
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
        self.assertIn("last unfinished case: test_waiting", result.stdout)
        self.assertIn("S=test_card_picture CASE=test_waiting", result.stdout)
        self.assertNotIn("CASE=test_finished", result.stdout)

    def test_connected_suites_have_their_own_pair_and_leave_no_processes(self):
        for mode in ("ok", "nonzero"):
            with self.subTest(mode=mode):
                result = self.run_suites("test_launch_news test_refusal_ladder", mode)
                self.assertEqual(result.returncode, 0 if mode == "ok" else 7, result.stdout + result.stderr)
                calls = self.engine_calls()
                self.assertEqual([call["suite"] for call in calls], ["test_launch_news", "test_refusal_ladder"])
                self.assertEqual(len(self.fake_pids()), 4, "only the two selected pairs start")
                self.assertEqual([call["fakes"] for call in calls], [self.fake_pids()[:2], self.fake_pids()[2:]],
                                 "each pair is reaped before the next suite, even after failure")
                sockets = [{arg for arg in call["args"] if arg.startswith("--socket-")} for call in calls]
                self.assertEqual([len(pair) for pair in sockets], [2, 2])
                self.assertTrue(sockets[0].isdisjoint(sockets[1]))
                for pid in self.fake_pids():
                    with self.assertRaises(ProcessLookupError, msg=f"fake {pid} was not reaped"):
                        os.kill(pid, 0)

    def test_a_failed_second_server_cleans_up_the_first_and_keeps_its_error(self):
        result = self.run_suites("test_launch_news", "fake-start-failure")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(self.engine_calls(), [])
        self.assertEqual(len(self.fake_pids()), 2)
        for pid in self.fake_pids():
            with self.assertRaises(ProcessLookupError, msg=f"fake {pid} was not reaped"):
                os.kill(pid, 0)
        logs = list((self.root / "build/test-results").glob("*/news-b.log"))
        self.assertEqual(len(logs), 1, result.stdout)
        self.assertIn("deliberate fake startup failure", logs[0].read_text())

    def test_every_failure_gate_keeps_logs_and_a_rerun_command(self):
        for mode in ("script-error", "parse-error", "missing-marker", "too-few", "nonzero", "timeout"):
            with self.subTest(mode=mode):
                result = self.run_suites("test_card_picture", mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("test-suite", result.stdout)
                self.assertIn("S=test_card_picture", result.stdout)
                logs = list((self.root / "build/test-results").glob("*/test_card_picture.log"))
                self.assertEqual(len(logs), 1, result.stdout)
                self.assertTrue(logs[0].read_text(), "the failed engine output survives cleanup")
                if mode == "timeout":
                    self.assertIn("killed after 1s", logs[0].read_text())
                shutil.rmtree(logs[0].parent)


class LintChangedTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.git("init", "-q", ".")
        (self.root / "scripts").mkdir()
        (self.root / "tools").mkdir()
        for path in ("scripts/kept.gd", "scripts/edited.gd", "scripts/staged.gd", "tools/removed.gd"):
            (self.root / path).write_text("extends RefCounted\n")
        (self.root / "gdlintrc").write_text("{}\n")
        self.git("add", ".")
        self.commit()
        self.calls = self.root / "lint-calls.jsonl"
        self.linter = self.root / "lint tool"
        self.linter.write_text(f"#!{sys.executable}\n" + f'''import json, sys
from pathlib import Path
with open({str(self.calls)!r}, "a") as out:
    out.write(json.dumps(sys.argv[1:]) + "\\n")
invalid = "BAD_FORMAT" if "--check" in sys.argv else "BAD_LINT"
if any(invalid in Path(path).read_text() for path in sys.argv[1:] if path.endswith(".gd")):
    sys.exit(23)
''')
        self.linter.chmod(0o755)

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True, text=True).stdout.strip()

    def commit(self):
        self.git("-c", "user.name=test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                 "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "fixture")

    def check(self, base="HEAD"):
        self.calls.unlink(missing_ok=True)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = lint_changed.main(["--base", base, "--gdlint", str(self.linter),
                                        "--gdformat", str(self.linter)], root=self.root)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        return result, calls, out.getvalue() + err.getvalue()

    def test_staged_unstaged_and_untracked_names_are_checked_without_deleted_files(self):
        (self.root / "scripts/edited.gd").write_text("# unstaged\n")
        (self.root / "scripts/staged.gd").write_text("# staged\n")
        self.git("add", "scripts/staged.gd")
        # Even when working contents are restored, this staged name is selected.
        (self.root / "scripts/staged.gd").write_text("extends RefCounted\n")
        (self.root / "scripts/new 人.gd").write_text("# untracked\n")
        (self.root / "tools/removed.gd").unlink()
        self.git("mv", "scripts/kept.gd", "scripts/moved name.gd")
        result, calls, output = self.check()
        self.assertEqual(result, 0, output)
        expected = {"scripts/edited.gd", "scripts/staged.gd", "scripts/new 人.gd", "scripts/moved name.gd"}
        self.assertEqual(len(calls), 2, "lint and format checks both run")
        for call in calls:
            self.assertEqual({name for name in call if name.endswith(".gd")}, expected)
        self.assertIn("--check", calls[1], "formatting is checked, never rewritten")

    def test_configuration_changes_check_unchanged_scripts_too(self):
        (self.root / "gdlintrc").write_text("# changed\n")
        result, calls, output = self.check()
        self.assertEqual(result, 0, output)
        self.assertIn("configuration changed", output)
        expected = {"scripts/kept.gd", "scripts/edited.gd", "scripts/staged.gd", "tools/removed.gd"}
        self.assertEqual(set(calls[0]), expected)

    def test_a_base_includes_committed_changes_but_an_unknown_base_is_an_error(self):
        base = self.git("rev-parse", "HEAD")
        (self.root / "scripts/edited.gd").write_text("# committed\n")
        self.git("add", "scripts/edited.gd")
        self.commit()
        result, calls, output = self.check(base)
        self.assertEqual(result, 0, output)
        self.assertEqual(calls[0], ["scripts/edited.gd"])
        result, calls, output = self.check("no-such-ref")
        self.assertEqual(result, 2, output)
        self.assertEqual(calls, [])

    def test_no_changes_are_a_noop_and_lint_or_format_failures_still_fail(self):
        result, calls, output = self.check()
        self.assertEqual(result, 0, output)
        self.assertEqual(calls, [])
        for invalid in ("BAD_LINT", "BAD_FORMAT"):
            with self.subTest(invalid=invalid):
                (self.root / "scripts/edited.gd").write_text(invalid + "\n")
                result, _, output = self.check()
                self.assertEqual(result, 23, output)
                self.assertNotIn("LINT_CHANGED_OK", output)


if __name__ == "__main__":
    unittest.main()
