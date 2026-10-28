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
import signal
import subprocess
import sys
import tempfile
import time
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
        shutil.copyfile(ROOT / "Makefile", self.root / "Makefile")
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
if script in ("check_scripts", "check_packs"):
    print(script.removeprefix("check_").upper() + "_OK")
    sys.exit(0)
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
    "test_card_picture": ("CARD PICTURE TESTS", 36),
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

    def run_suites(self, suites, mode="ok", case="", tier="", shard="", args=()):
        self.calls.unlink(missing_ok=True)
        self.fakes.unlink(missing_ok=True)
        environment = dict(os.environ, GODOT=str(self.engine), PYTHON=sys.executable,
                           SUITES=suites, CASE=case, TIER=tier, SHARD=shard, HERDSTEAD_SKIP_LOAD_CHECKS="1",
                           ENGINE_CALLS=str(self.calls), FAKE_PIDS=str(self.fakes), ENGINE_RESULT=mode,
                           RUN_TIMEOUT="1" if mode == "timeout" else "10")
        return subprocess.run(["bash", str(self.root / "tools/run_tests.sh"), *args],
                              capture_output=True, text=True, env=environment, timeout=30)

    def engine_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def fake_pids(self):
        return [int(line) for line in self.fakes.read_text().splitlines()] if self.fakes.exists() else []

    def test_shard_plans_partition_every_suite_once_without_starting_anything(self):
        # A stale import must not make listing launch the engine either.
        stamp = self.root / ".godot/herdstead-import.stamp"
        stamp.unlink()
        result = self.run_suites("", args=("--list",))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        suites = result.stdout.splitlines()
        self.assertIn("test_client", suites)
        self.assertIn("test_card_picture", suites)
        self.assertEqual(len(suites), len(set(suites)))
        for count in (1, 4, len(suites)):
            seen = []
            for index in range(1, count + 1):
                with self.subTest(shard=f"{index}/{count}"):
                    result = self.run_suites("", shard=f"{index}/{count}", args=("--list",))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    names = result.stdout.splitlines()
                    self.assertEqual(names, suites[index - 1::count])
                    self.assertTrue(names, "empty shards must not silently run everything")
                    seen.extend(names)
                    self.assertEqual(self.engine_calls(), [])
                    self.assertEqual(self.fake_pids(), [])
                    self.assertFalse(stamp.exists())
            self.assertCountEqual(seen, suites)
        repeated = self.run_suites("", args=("--list",))
        self.assertEqual(repeated.stdout.splitlines(), suites)
        self.assertFalse((self.root / "build").exists(), "listing must not create a work or log directory")

    def test_invalid_or_conflicting_shards_fail_before_side_effects(self):
        for shard in ("1", " ", "0/4", "1/0", "5/4", "-1/4", "1/-4", "01/4", "1/04",
                      "1/4/2", "1/4\n", "1/99999999999999999999", "18446744073709551617/4"):
            with self.subTest(shard=shard):
                result = self.run_suites("", shard=shard)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("SHARD", result.stdout)
                self.assertEqual(self.engine_calls(), [])
                self.assertEqual(self.fake_pids(), [])
        for suites, case, tier in (("test_card_picture", "", ""), ("", "test_selected", ""),
                                   ("", "", "quick")):
            with self.subTest(suites=suites, case=case, tier=tier):
                result = self.run_suites(suites, case=case, tier=tier, shard="1/4", args=("--list",))
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("SHARD", result.stdout)
                self.assertEqual(self.engine_calls(), [])
                self.assertEqual(self.fake_pids(), [])
        result = self.run_suites("", args=("--list",))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        count = len(result.stdout.splitlines())
        for index in (1, count + 1):
            result = self.run_suites("", shard=f"{index}/{count + 1}", args=("--list",))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertEqual(self.engine_calls(), [])
            self.assertEqual(self.fake_pids(), [])

    def test_make_shards_keep_whole_suites_load_checks_and_isolation_despite_exported_filters(self):
        environment = dict(os.environ, GODOT=str(self.engine), PYTHON=sys.executable,
                           SUITES="test_wrong", CASE="test_wrong", TIER="quick", SHARD="",
                           HERDSTEAD_SKIP_LOAD_CHECKS="", ENGINE_CALLS=str(self.calls),
                           FAKE_PIDS=str(self.fakes), ENGINE_RESULT="ok")
        listed = subprocess.run(["make", "-s", "test-list"], cwd=self.root, capture_output=True,
                                text=True, env=environment, timeout=30)
        self.assertEqual(listed.returncode, 0, listed.stdout + listed.stderr)
        suites = listed.stdout.splitlines()
        for suite, fakes, cases in (("test_card_picture", 0, 36), ("test_launch_news", 2, 5)):
            with self.subTest(suite=suite):
                shard = f"SHARD={suites.index(suite) + 1}/{len(suites)}"
                plan = subprocess.run(["make", "-s", "test-list", shard], cwd=self.root,
                                      capture_output=True, text=True, env=environment, timeout=30)
                self.assertEqual(plan.returncode, 0, plan.stdout + plan.stderr)
                self.assertEqual(plan.stdout.splitlines(), [suite])
                self.assertEqual(self.engine_calls(), [])
                self.assertEqual(self.fake_pids(), [])
                result = subprocess.run(["make", "-s", "test-shard", shard], cwd=self.root,
                                        capture_output=True, text=True, env=environment, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertCountEqual([call["suite"] for call in self.engine_calls()],
                                      ["check_scripts", "check_packs", suite])
                self.assertIn(f"TESTS OK: {cases} cases", result.stdout)
                self.assertNotIn("FILTERED", result.stdout)
                self.assertNotIn("UNRELATED_PYTHON_TESTS", result.stdout)
                self.assertEqual(len(self.fake_pids()), fakes)
                for pid in self.fake_pids():
                    with self.assertRaises(ProcessLookupError, msg=f"fake {pid} was not reaped"):
                        os.kill(pid, 0)
                self.calls.unlink()
                self.fakes.unlink(missing_ok=True)
        result = subprocess.run(["make", "-s", "test-shard"], cwd=self.root, capture_output=True,
                                text=True, env=environment, timeout=30)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SHARD", result.stdout + result.stderr)
        self.assertEqual(self.engine_calls(), [])
        self.assertEqual(self.fake_pids(), [])

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
        result = self.run_suites("test_card_picture", "script-error", case="test_selected")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        prefix = "RUN_TESTS: rerun with "
        commands = [line.removeprefix(prefix) for line in result.stdout.splitlines() if line.startswith(prefix)]
        self.assertEqual(len(commands), 2, result.stdout)
        environment = dict(os.environ, CASE="test_leaked", SUITES="test_wrong", TIER="quick", SHARD="1/4",
                           ENGINE_CALLS=str(self.calls), FAKE_PIDS=str(self.fakes), ENGINE_RESULT="ok")
        for command, summary in zip(commands, ("TESTS OK: 36 cases", "TESTS FILTERED OK: 1 cases")):
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
        listed = self.run_suites("", args=("--list",))
        self.assertEqual(listed.returncode, 0, listed.stdout + listed.stderr)
        suites = listed.stdout.splitlines()
        shard = f"{suites.index('test_card_picture') + 1}/{len(suites)}"
        for selection, part in (("test_card_picture", ""), ("", shard)):
            for mode in ("script-error", "parse-error", "missing-marker", "too-few", "nonzero", "timeout"):
                with self.subTest(mode=mode, shard=part):
                    result = self.run_suites(selection, mode, shard=part)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("test-suite", result.stdout)
                    self.assertIn("S=test_card_picture", result.stdout)
                    logs = list((self.root / "build/test-results").glob("*/test_card_picture.log"))
                    self.assertEqual(len(logs), 1, result.stdout)
                    self.assertTrue(logs[0].read_text(), "the failed engine output survives cleanup")
                    if mode == "timeout":
                        self.assertIn("killed after 1s", logs[0].read_text())
                    shutil.rmtree(logs[0].parent)


class PreviewTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        tools = self.root / "tools"
        tools.mkdir()
        for name in ("preview.py", "import_if_stale.sh"):
            if (ROOT / "tools" / name).exists():
                shutil.copyfile(ROOT / "tools" / name, tools / name)
        shutil.copytree(ROOT / "tools/fixtures", tools / "fixtures")
        shutil.copyfile(ROOT / "tools/fake_herdr.py", tools / "server.py")
        shutil.copyfile(ROOT / "Makefile", self.root / "Makefile")
        for folder in ("scripts", "scenes", "assets"):
            (self.root / folder).mkdir()
        self.calls = self.root / "engine-calls.jsonl"
        self.fakes = self.root / "fake-pids"
        (tools / "fake_herdr.py").write_text(
            'import os, runpy, sys\n'
            'with open(os.environ["FAKE_PIDS"], "a") as out: out.write(str(os.getpid()) + "\\n")\n'
            'if os.environ["ENGINE_RESULT"] == "fake-start-failure":\n'
            '    sys.exit("deliberate fake startup failure")\n'
            f'runpy.run_path({str(tools / "server.py")!r}, run_name="__main__")\n'
        )
        self.engine = self.root / "engine with spaces"
        self.engine.write_text(f"#!{sys.executable}\n" + '''import json, os, signal, socket, subprocess, sys, time
from pathlib import Path
args = sys.argv[1:]
mode = os.environ["ENGINE_RESULT"]
stage = "import" if "--editor" in args else "office"
keys = ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "HERDR_SOCKET_PATH",
        "HERDR_BIN_PATH", "HERDSTEAD_SOCKET_DIR", "HERDSTEAD_SSH", "__GODOT_SHELL_ENV_SET")
record = {"stage": stage, "args": args, "pid": os.getpid(), "env": {key: os.getenv(key) for key in keys}}
if mode == "hold-" + stage:
    # An importer (or Avatar Studio) can spawn a child; stopping only the
    # immediate process would leave it writing into a deleted private HOME.
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    record["child"] = child.pid
    def stop(*_):
        child.terminate()
        child.wait()
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
if stage == "office":
    user = args[args.index("--") + 1:]
    path = next(arg.removeprefix("--socket=") for arg in user if arg.startswith("--socket="))
    with socket.socket(socket.AF_UNIX) as conn:
        conn.settimeout(2)
        conn.connect(path)
        method = "pane.focus" if mode == "write" else "ping" if mode == "no-snapshot" else "session.snapshot"
        conn.sendall((json.dumps({"id": "preview", "method": method, "params": {}}) + "\\n").encode())
        response = json.loads(conn.makefile().readline())
        if method == "session.snapshot":
            record["snapshot"] = response["result"]["snapshot"]
    saved = Path(os.environ["XDG_DATA_HOME"]) / "godot/app_userdata/Herdstead/herdstead.cfg"
    saved.parent.mkdir(parents=True, exist_ok=True)
    saved.write_text("preview preference")
    if mode != "missing-marker":
        print("OFFICE_START: read-only herdr client on " + path, flush=True)
with open(os.environ["ENGINE_CALLS"], "a") as out:
    out.write(json.dumps(record) + "\\n")
if mode == "fake-died" and stage == "office":
    os.kill(int(Path(os.environ["FAKE_PIDS"]).read_text().splitlines()[-1]), signal.SIGTERM)
    time.sleep(60)
if mode == "hold-" + stage:
    time.sleep(60)
if mode == "import-error" and stage == "import":
    print("SCRIPT ERROR: deliberate import error")
if stage == "office":
    if mode == "script-error":
        print("SCRIPT ERROR: deliberate office error")
    if mode == "parse-error":
        print("Parse Error: deliberate office error")
    sys.exit(7 if mode == "nonzero" else 0)
''')
        self.engine.chmod(0o755)
        # These must be untouched even when inherited explicitly. No real
        # service or user directory participates in this test.
        self.original = self.root / "operator"
        self.original.mkdir()
        (self.original / "herdstead.cfg").write_text("keep my preference")
        self.env = dict(os.environ, GODOT=str(self.engine), PYTHON=sys.executable,
                        ENGINE_CALLS=str(self.calls), FAKE_PIDS=str(self.fakes), ENGINE_RESULT="ok",
                        DISPLAY=":fixture", HOME=str(self.original), XDG_DATA_HOME=str(self.original),
                        XDG_CONFIG_HOME=str(self.original), XDG_CACHE_HOME=str(self.original),
                        HERDR_SOCKET_PATH=str(self.original / "herdr.sock"),
                        HERDR_BIN_PATH=str(self.original / "herdr"),
                        HERDSTEAD_SOCKET_DIR=str(self.original), HERDSTEAD_SSH=str(self.original / "ssh"),
                        HERDSTEAD_ROOT=str(self.original), __GODOT_SHELL_ENV_SET="0")

    def preview(self, *args, mode="ok"):
        self.calls.unlink(missing_ok=True)
        self.fakes.unlink(missing_ok=True)
        return subprocess.run([sys.executable, str(self.root / "tools/preview.py"), *args],
                              cwd=self.root, capture_output=True, text=True,
                              env=dict(self.env, ENGINE_RESULT=mode), timeout=20)

    def records(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def assert_cleaned(self):
        pids = [int(pid) for pid in self.fakes.read_text().splitlines()] if self.fakes.exists() else []
        for record in self.records():
            pids.append(record["pid"])
            if "child" in record:
                pids.append(record["child"])
            self.assertNotEqual(record["env"]["HOME"], str(self.original))
            self.assertFalse(Path(record["env"]["HOME"]).exists(), "private settings must be discarded")
            self.assertFalse(Path(record["env"]["HERDR_SOCKET_PATH"]).exists(), "socket must be removed")
        for pid in pids:
            with self.assertRaises(ProcessLookupError, msg=f"preview child {pid} survived"):
                os.kill(pid, 0)
        self.assertEqual(list(self.original.iterdir()), [self.original / "herdstead.cfg"])
        self.assertEqual((self.original / "herdstead.cfg").read_text(), "keep my preference")

    def test_make_preview_uses_the_real_office_with_private_settings_and_selected_fixture(self):
        result = subprocess.run(["make", "preview", "FIXTURE=snapshot_worktrees"], cwd=self.root,
                                capture_output=True, text=True, env=self.env, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        records = self.records()
        self.assertEqual([record["stage"] for record in records], ["import", "office"])
        office = records[-1]
        self.assertIn("--read-only", office["args"][office["args"].index("--") + 1:])
        expected = json.loads((ROOT / "tools/fixtures/snapshot_worktrees.json").read_text())["snapshot"]
        self.assertEqual(office["snapshot"], expected)
        for record in records:
            env = record["env"]
            for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                        "HERDR_SOCKET_PATH", "HERDR_BIN_PATH", "HERDSTEAD_SOCKET_DIR", "HERDSTEAD_SSH"):
                self.assertTrue(env[key], key)
                self.assertNotEqual(env[key], self.env[key], key + " leaked from operator")
            self.assertEqual(env["__GODOT_SHELL_ENV_SET"], "1")
        self.assertIn("PREVIEW_OK", result.stdout)
        self.assert_cleaned()
        # A warm start must not invoke the importer again, and omitting
        # FIXTURE must actually serve the documented default, not the prior run.
        (self.root / ".godot/global_script_class_cache.cfg").touch()
        result = self.preview()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual([record["stage"] for record in self.records()], ["office"])
        expected = json.loads((ROOT / "tools/fixtures/snapshot_floors.json").read_text())["snapshot"]
        self.assertEqual(self.records()[0]["snapshot"], expected)
        self.assert_cleaned()

    def test_fixture_listing_and_invalid_options_start_nothing(self):
        result = self.preview("--list-fixtures")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("snapshot_floors", result.stdout)
        self.assertIn("snapshot_worktrees", result.stdout)
        for args in (("--fixture=no_such_fixture",), ("--fixture=../snapshot_basic",), ("--socket=/somewhere",)):
            with self.subTest(args=args):
                result = self.preview(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(self.records(), [])
        self.assertFalse(self.fakes.exists())

    def test_import_office_and_fake_failures_keep_logs_and_stop_every_child(self):
        for mode, detail in (("import-error", "deliberate import error"),
                             ("fake-start-failure", "deliberate fake startup failure"),
                             ("script-error", "deliberate office error"),
                             ("parse-error", "deliberate office error"),
                             ("missing-marker", "OFFICE_START"), ("nonzero", "7"),
                             ("no-snapshot", "before requesting the fixture snapshot"),
                             ("write", "outside the read-only three"),
                             ("fake-died", "fake herdr stopped")):
            with self.subTest(mode=mode):
                result = self.preview(mode=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(detail, result.stdout + result.stderr)
                self.assertIn("PREVIEW_FAILED", result.stdout + result.stderr)
                self.assertNotIn("PREVIEW_OK", result.stdout)
                logs = list((self.root / "build/preview-results").glob("*/*.log"))
                self.assertTrue(logs, "a diagnostic log must survive cleanup")
                self.assert_cleaned()
                shutil.rmtree(self.root / "build/preview-results")

    def test_interrupting_import_or_office_reaps_children_and_discards_private_settings(self):
        for stage, stop in (("import", signal.SIGTERM), ("office", signal.SIGTERM),
                            ("office", signal.SIGINT)):
            with self.subTest(stage=stage, signal=stop):
                self.calls.unlink(missing_ok=True)
                self.fakes.unlink(missing_ok=True)
                process = subprocess.Popen([sys.executable, str(self.root / "tools/preview.py")],
                                           cwd=self.root, env=dict(self.env, ENGINE_RESULT="hold-" + stage),
                                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                try:
                    deadline = time.monotonic() + 10
                    while process.poll() is None and time.monotonic() < deadline:
                        if any(record["stage"] == stage for record in self.records()):
                            break
                        time.sleep(0.05)
                    process.send_signal(stop)
                    output, _ = process.communicate(timeout=10)
                    self.assertTrue(any("child" in record for record in self.records()), output)
                    self.assertNotEqual(process.returncode, 0, output)
                    self.assertNotIn("PREVIEW_OK", output)
                    self.assert_cleaned()
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate()


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
