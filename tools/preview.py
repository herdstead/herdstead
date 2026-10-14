"""Open the real office against an owned fake herdr, never the operator's session.

`make preview` is interactive and read-only; FIXTURE selects an existing snapshot.
Settings and sockets are private to this run, including during asset import.
Python owns the process groups so Ctrl-C can stop the importer and its engine,
or the office and an Avatar Studio it opened, before removing their private HOME.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
READ_METHODS = {"ping", "session.snapshot", "events.subscribe"}


@contextlib.contextmanager
def process(command: list[str], log: Path, env: dict[str, str]):
    with log.open("w") as output:
        child = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        try:
            yield child
        finally:
            # The parent may have exited while a descendant still holds the
            # private HOME. Stop only this launcher's own process group.
            try:
                os.killpg(child.pid, signal.SIGTERM)
                child.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
            finally:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGKILL)
                child.wait()


def checked_log(log: Path) -> str:
    text = log.read_text(errors="replace")
    if "SCRIPT ERROR" in text or "Parse Error" in text:
        raise RuntimeError(f"{log.name}: Godot reported a script error (even if it exited 0)")
    return text


def stats(work: Path) -> dict:
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(0.5)
        connection.connect(str(work / "control.sock"))
        connection.sendall(b'{"cmd":"stats"}\n')
        with connection.makefile() as response:
            answer = json.loads(response.readline())
    if not answer.get("ok"):
        raise RuntimeError(f"fake herdr refused stats: {answer}")
    return answer["result"]


def run_preview(work: Path, env: dict[str, str], fixture: str) -> None:
    # --force exposes the importer log, including exit-0 script errors which
    # import_if_stale.sh's quiet path would otherwise discard. Check freshness
    # first so a warm preview still does no import work.
    importer = ["bash", str(ROOT / "tools/import_if_stale.sh")]
    with process([*importer, "--check"], work / "import-check.log", env) as check:
        stale = check.wait(timeout=10)
    if stale not in (0, 1):
        raise RuntimeError(f"import freshness check exited {stale}")
    if stale:
        print("PREVIEW: importing project", flush=True)
        with process([*importer, "--force"], work / "import.log", env) as importing:
            status = importing.wait(timeout=300)
        checked_log(work / "import.log")
        if status:
            raise RuntimeError(f"project import exited {status}")

    fake = [sys.executable, str(ROOT / "tools/fake_herdr.py"),
            f"--socket={work}/herdr.sock", f"--control={work}/control.sock",
            f"--fixtures={ROOT}/tools/fixtures", f"--fixture={fixture}"]
    with process(fake, work / "fake.log", env) as server:
        deadline = time.monotonic() + 5
        while True:
            if server.poll() is not None:
                raise RuntimeError(f"fake herdr exited {server.returncode} during startup")
            try:
                if (work / "herdr.sock").is_socket():
                    stats(work)  # The control socket must answer, not just exist.
                    break
            except OSError:
                pass
            if time.monotonic() >= deadline:
                raise RuntimeError("fake herdr was not ready within 5s")
            time.sleep(0.05)

        command = [env["GODOT"], "--path", str(ROOT), "--",
                   f"--socket={work}/herdr.sock", "--read-only", "--no-bounce", "--plain-window",
                   "--pack=res://assets/daylight/manifest.json", "--light=day"]
        print(f"PREVIEW: {fixture}; read-only fake herdr; settings are discarded on exit. "
              "Close the window or press Ctrl-C to stop.", flush=True)
        log = work / "office.log"
        marker = f"OFFICE_START: read-only herdr client on {work}/herdr.sock"
        with process(command, log, env) as office:
            ready = False
            deadline = time.monotonic() + 30
            while office.poll() is None:
                if server.poll() is not None:
                    raise RuntimeError("fake herdr stopped while the office was running")
                text = checked_log(log)
                if not ready:
                    ready = marker in text and "session.snapshot" in stats(work)["lifetime_methods"]
                    if ready:
                        print(f"PREVIEW_READY: {fixture} connected to fake herdr", flush=True)
                    elif time.monotonic() >= deadline:
                        raise RuntimeError("office did not connect to fake herdr within 30s")
                time.sleep(0.1)
            text = checked_log(log)
            if office.returncode:
                raise RuntimeError(f"Godot exited {office.returncode}")
            if marker not in text:
                raise RuntimeError("missing read-only OFFICE_START marker")
            audit = stats(work)
            (work / "stats.json").write_text(json.dumps(audit, indent=2) + "\n")
            methods = set(audit["lifetime_methods"])
            if audit["violations"] or methods - READ_METHODS:
                raise RuntimeError("preview sent a request outside the read-only three")
            if "session.snapshot" not in methods:
                raise RuntimeError("office closed before requesting the fixture snapshot")


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


def main() -> int:
    fixtures = sorted(path.stem for path in (ROOT / "tools/fixtures").glob("snapshot_*.json"))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", choices=fixtures, default="snapshot_floors")
    parser.add_argument("--list-fixtures", action="store_true", help="list snapshots without starting anything")
    args = parser.parse_args()
    if args.list_fixtures:
        print("\n".join(fixtures))
        return 0
    if sys.platform.startswith("linux") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        print("PREVIEW_FAILED: needs a display; open it from a desktop terminal", file=sys.stderr)
        return 2

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    # macOS Unix socket paths stop at ~104 bytes; its default TMPDIR can be too long.
    with tempfile.TemporaryDirectory(prefix="hs-preview.", dir="/tmp") as temporary:
        work = Path(temporary)
        env = dict(os.environ, GODOT=os.environ.get("GODOT", "godot"), HERDSTEAD_ROOT=str(ROOT),
                   HOME=str(work / "home"), XDG_DATA_HOME=str(work / "data"),
                   XDG_CONFIG_HOME=str(work / "config"), XDG_CACHE_HOME=str(work / "cache"),
                   HERDR_SOCKET_PATH=str(work / "herdr.sock"), HERDR_BIN_PATH=str(work / "no-herdr"),
                   HERDSTEAD_SOCKET_DIR=str(work / "socks"), HERDSTEAD_SSH=str(work / "no-ssh"),
                   __GODOT_SHELL_ENV_SET="1")
        # Preserve X11 authentication without leaving HOME pointed at personal
        # settings. Explicit XAUTHORITY and Wayland's runtime dir stay unchanged.
        authority = Path.home() / ".Xauthority"
        if "XAUTHORITY" not in env and authority.is_file():
            env["XAUTHORITY"] = str(authority)
        for name in ("home", "data", "config", "cache"):
            (work / name).mkdir()
        try:
            run_preview(work, env, args.fixture)
        except KeyboardInterrupt:
            print("PREVIEW: stopped", flush=True)
            return 130
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            print(f"PREVIEW_FAILED: {error}", file=sys.stderr)
            results = ROOT / "build/preview-results"
            results.mkdir(parents=True, exist_ok=True)
            (ROOT / "build/.gdignore").touch()
            saved = Path(tempfile.mkdtemp(prefix="preview-", dir=results))
            for log in sorted(work.glob("*.log")) + list(work.glob("stats.json")):
                shutil.copyfile(log, saved / log.name)
                if log.suffix == ".log":
                    print(f"== {log.name} (last 40 lines)", file=sys.stderr)
                    print("\n".join(log.read_text(errors="replace").splitlines()[-40:]), file=sys.stderr)
            print(f"PREVIEW: logs retained in {saved}", file=sys.stderr)
            return 1
    print("PREVIEW_OK: fake herdr stopped; temporary settings and sockets removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
