#!/usr/bin/env python3
"""Scripted stand-in for the herdr socket API, for headless client tests.

Standard library only. Mirrors what herdr 0.9.0 (protocol 22) does on the wire,
as checked against a real socket with read-only requests:

- NDJSON. A request is {"id": str, "method": str, "params": dict} plus "\\n".
- One connection answers exactly one request, then the server closes it.
  Only `events.subscribe` keeps its connection open.
- A subscribe first answers {"result": {"type": "subscription_started"}}, then
  streams bare {"event", "data"} envelopes without an id. Global events arrive
  with underscores (`pane_updated`) and repeat that name in data.type; the per
  pane status event keeps its dotted method name (`pane.agent_status_changed`)
  and only reaches streams that subscribed to that pane.
- A malformed request gets {"id": "", "error": {"code": "invalid_request"}}.
  A subscription naming an unknown pane gets `pane_not_found` with the id
  suffixed `:sub:<index>:probe`. Both close the connection.

A second socket (--control) takes one JSON command per connection and answers
one JSON line, so a test can script the server: swap snapshots, emit events,
drop streams, make the socket vanish, hang or garble the next reply, and read
back what the client asked for. See `Control` for the commands.

By default this server only answers the read-only methods. Anything else is
refused with the request's own id and recorded as a violation, which the
read-only suites assert never happens. A test that exercises Herdstead's write
boundary opens exactly what it needs with `allow`, which `reset` closes again:
`pane.read` answers herdr 0.9.0's nested `{"type": "pane_read", "read": {...}}`
with text scripted per pane and source, and `pane.focus` moves the session
focus and marks every pane of that tab seen, as herdr 0.9.0 does:
each `done` on the tab turns `idle`. `pane.send_keys`, `pane.send_input` and
`pane.send_text` record what they were given (`stats` lists it under `inputs`,
with whether herdr would have bracketed it as a paste) and answer
`{"type": "ok"}`, like herdr 0.9.0, with no effect on seen state or focus.
They take herdr's own, much wider key set (`C-c`, `ctrl+c`, `tab`, arrows,
capitals ...): only the office's allowlist keeps those out, so a leak shows up
here as a recorded write, not as a rejection. Home, End, PageUp, PageDown,
Insert and Delete are `invalid_key`, as every spelling of them is on 0.9.0.
`pane.send_input`'s text is bracketed (`ESC[200~ ... ESC[201~`) when the pane's
program asked for bracketed paste (`set_paste_mode`); `pane.send_text` never is.

`pane.read` with `format: "ansi"` answers the terminal monitor: the screen a
test scripted with `set_screen` (SGR and CRLF, as herdr 0.9.0 normalises it),
or the plain preview text when none was.

The reply, start and split methods, as herdr 0.9.0 answers them:

- `agent.prompt {target, text}` finds the pane by agent name, then by pane id
  (`agent_not_found` for neither, and for a pane with no agent), refuses a
  blocked agent with `agent_blocked` and records nothing, one still launching
  with `agent_not_ready`, empty text with `empty_agent_prompt`, and otherwise
  records the text with the Enter herdr types after it (`keys: ["enter"]`,
  bracketed as `set_paste_mode` says) and answers `agent_prompted` with the
  agent's state before it. `set_prompt_delay` holds the answer that long.
- `agent.start {name, kind, pane_id}` checks in herdr's order (name, name free,
  kind, pane, pane free, timeout, args), adds the pane's agent record with
  its name and `launch_pending: true` and no `agent` (the next snapshot shows
  it at once), answers `agent_started`, and sends no event. Then, as
  `set_launch` says for that pane (or `*`): recognised `detect` seconds on
  (`pane_agent_detected`, no name or launch fields), then `ready` (idle,
  `interactive_ready`, no longer pending, with the per pane status event) or
  `blocked` (still pending) `delay` seconds after the start; or `never`. A
  pane still launching, recognised or not, answers `agent_pane_busy` like a
  pane with an agent or one `set_busy` marks: herdr types one start only.
- `agent.get {target}` answers `agent_info` (the pane's agent record) until
  herdr's own launch timeout (`set_launch_timeout`, 30.4 s by default) has
  run out on a launch nothing recognised; the first ask after that settles
  it: the record goes, name and pane are free, one `pane_updated` goes out,
  and the answer is `agent_not_found` (measured).
- `pane.split {target_pane_id, direction, focus?, cwd?}` makes a new pane
  beside the target, never reusing an id, with a new terminal, in the
  target's `foreground_cwd` (or `cwd`), halving the target's layout slot with
  no minimum size, moving the focus only for `focus: true`, and emits
  `pane_created` and `layout_updated`.

The close, space and worktree methods, as herdr 0.9.0 answers them
(docs/WRITE_BOUNDARY.md §6):

- `pane.close {pane_id}` answers `ok` and drops the pane, its agent record
  and its layout slot at once (no confirmation, no prompt: a working or
  blocked agent gets SIGHUP); the tab's last pane takes the tab (the only
  event is `pane_closed`, no `tab_closed`), the workspace's last pane takes
  the workspace (`workspace_closed` with the WorkspaceInfo, then
  `pane_closed`; a linked worktree's checkout stays on disk), any other pane
  emits `pane_closed` then `layout_updated`. The last pane of a workspace
  that is the repo's own checkout while another workspace here shares its
  `repo_key` answers `confirmation_required` and changes nothing. herdr's
  focus moves to a sibling, or to another workspace, with no focus event.
  An unknown id is `pane_not_found` with the id echoed verbatim. Frees the
  agent name the pane held. `stats` lists every close under `closes`.
- `workspace.create {cwd?, label?, focus?, env?, source_workspace_id?}`
  answers `workspace_created` with the new `workspace`, its `tab` and its
  `root_pane` (fresh ids `w<n>`, `w<n>:t1`, `w<n>:p1`), and emits
  `workspace_created`, [`workspace_focused`], `tab_created`, [`tab_focused`],
  `pane_created`, [`pane_focused`], `layout_updated`: the bracketed ones when
  it becomes focused, which the first workspace of an empty server does
  whatever `focus` says. A `cwd` that is not absolute, or (once `set_dirs`
  scripted what exists) not one of those, lands in `$HOME` with label `~`,
  silently; `label` is taken verbatim, unbounded; omitted, the directory's
  basename. `stats` lists them under `spaces`.
- `worktree.create {workspace_id?, cwd?, branch?, base?, path?, label?, focus?,
  trust_repository?}` runs "git" for the workspace: `not_git_worktree` unless
  its snapshot record has a `worktree` (or `set_repo` said it is a repo),
  `linked_worktree_source` for a linked one, `workspace_not_found` for an
  unknown id, `invalid_request` "branch is required" for a blank branch or
  "worktree path must be absolute" for a relative path (`~` is expanded, as
  measured); `set_worktree_result {code, message}` scripts the next call's
  git failure (a measured multi-line message). Otherwise a new workspace
  whose `worktree` is linked, `checkout_path` the `path` or
  `~/.herdr/worktrees/<repo>/<branch>`, the answer `worktree_created` with
  `workspace`, `tab`, `root_pane` and `worktree`; the parent gains its
  `worktree` field the first time (`workspace_updated`); events in the
  measured order. `stats` lists them under `worktrees`.

    python3 tools/fake_herdr.py --socket=/tmp/x/herdr.sock --control=/tmp/x/ctl.sock
"""

import argparse
import copy
import json
import os
import re
import signal
import socket
import sys
import threading
import time

PROTOCOL = 22
VERSION = "0.9.0"
READ_ONLY = ("ping", "session.snapshot", "events.subscribe")
# What `allow` may open. Nothing else is implemented, so nothing else can be allowed.
OPERABLE = (
    "pane.read", "pane.focus", "pane.send_keys", "pane.send_input", "pane.send_text",
    "agent.prompt", "agent.start", "pane.split", "agent.get",
    "pane.close", "workspace.create", "worktree.create",
)
# Where a bad `cwd` lands, and where herdr's own worktree directory is.
HOME = "/home/tester"
WORKTREES_DIR = HOME + "/.herdr/worktrees"
# A new workspace's tab label and terminal rect: not measured; the fixtures' shapes.
NEW_TAB_LABEL = "main"
NEW_RECT = {"x": 0, "y": 0, "width": 200, "height": 50}
# Seconds after a close's, a space's or a worktree's reply its events go out (measured: 30 to 120 ms).
EVENTS_AFTER = 0.05
# What `stats` lists under `inputs`: every one of these carried out.
INPUTS = ("pane.send_keys", "pane.send_input", "pane.send_text", "agent.prompt")
# herdr 0.9.0's fixed table of kinds `agent.start` takes (case-insensitive, measured).
KINDS = (
    "pi", "claude", "codex", "gemini", "cursor", "devin", "agy", "cline", "omp", "mastracode",
    "opencode", "copilot", "kimi", "kiro", "droid", "amp", "grok", "hermes", "kilo", "qodercli",
    "qwen", "maki", "muse",
)
AGENT_NAME = re.compile(r"[a-z][a-z0-9_-]{0,31}")
# How a start turns out by default, as measured: recognised after 0.3 s, ready
# 3.6 s after the start. herdr's own launch timeout is 30.4 s by default.
LAUNCH_DEFAULT = {"outcome": "ready", "detect": 0.3, "delay": 3.6}
LAUNCH_TIMEOUT = 30.4
# Named keys herdr 0.9.0 accepts (measured, case-insensitive), beyond single
# characters and modifier chords: far more than Herdstead may ever send. Home,
# End, PageUp, PageDown, Insert and Delete are not among them: every spelling
# tried against herdr 0.9.0 was `invalid_key`.
NAMED_KEYS = {
    "enter", "return", "esc", "escape", "tab", "space", "backspace", "bs", "plus",
    "up", "down", "left", "right",
} | {"f%d" % n for n in range(1, 13)}
BRACKET_OPEN = "\x1b[200~"
BRACKET_CLOSE = "\x1b[201~"
# herdr 0.9.0's ReadSource enum (`herdr api schema --json`).
READ_SOURCES = ("visible", "recent", "recent_unwrapped", "detection")
# The subscription variants herdr 0.9.0 accepts, in its own order.
EVENT_TYPES = (
    "workspace.created", "workspace.updated", "workspace.metadata_updated",
    "workspace.renamed", "workspace.moved", "workspace.reordered",
    "workspace.closed", "workspace.focused",
    "worktree.created", "worktree.opened", "worktree.removed",
    "tab.created", "tab.closed", "tab.focused", "tab.renamed", "tab.moved",
    "pane.created", "pane.closed", "pane.updated", "pane.focused",
    "pane.moved", "pane.exited", "pane.agent_detected", "pane.output_matched",
    "pane.agent_status_changed", "pane.scroll_changed", "layout.updated",
)
PER_PANE = "pane.agent_status_changed"


def subscription_type(wire_name):
    """`pane_updated` -> `pane.updated`; the per-pane name is already dotted."""
    return wire_name if "." in wire_name else wire_name.replace("_", ".", 1)


def line(payload):
    # herdr writes compact JSON.
    return (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


class Stream:
    def __init__(self, conn, request_id, types, panes):
        self.conn = conn
        self.request_id = request_id
        self.types = types
        self.panes = panes
        self.started = False
        self.lock = threading.Lock()

    def send(self, data):
        with self.lock:
            try:
                self.conn.sendall(data)
                return True
            except OSError:
                return False

    def wants(self, wire_name, data):
        kind = subscription_type(wire_name)
        if kind == PER_PANE:
            return str(data.get("pane_id", "")) in self.panes
        return kind in self.types


class FakeHerdr:
    def __init__(self, socket_path, fixtures):
        self.socket_path = socket_path
        self.fixtures = fixtures
        self.lock = threading.RLock()
        self.listener = None
        self.snapshot = {}
        self.streams = []
        self.hung = []
        self.held_snapshots = []
        self.actions = []
        self.hold_ack = False
        self.log = []
        self.lifetime_methods = set()
        self.violations = []
        self.stream_errors = []
        # Methods beyond READ_ONLY a test opened with `allow`; `reset` closes them.
        self.allowed = set()
        # (pane_id, source or None) -> {"text", "truncated"}; see `set_preview`.
        self.previews = {}
        # What `ping` announces; `set_protocol` changes it, `reset` restores it.
        self.protocol = PROTOCOL
        # Every pane.send_keys / pane.send_input carried out, in order.
        self.inputs = []
        # Replies an action `hold` withholds until `release_held`: (conn, payload).
        self.held_replies = []
        # (pane_id, source or None) -> {"ansi", "truncated", "revision", "animate"}; see `set_screen`.
        self.screens = {}
        # Panes whose program asked for bracketed paste; see `set_paste_mode`.
        self.paste_mode = set()
        # How many ansi reads each animated screen answered.
        self.frames = {}
        self._fresh_writes()

    def _fresh_writes(self):
        """The launch, split, close, space and worktree state, as `reset` leaves it. Callers hold the lock
        or run before any thread does."""
        # Agent name -> its pane id, launching or not: herdr holds a name
        # until its agent exits or its pane closes.
        self.names = {}
        # Pane id -> the start herdr is still launching there: {name, kind}.
        self.launches = {}
        # How each pane's start turns out (`*`: any pane); see `set_launch`.
        self.launch_plans = {}
        # Panes with another program in front of their shell (`set_busy`).
        self.busy = set()
        # Seconds agent.prompt takes to answer (herdr: about 0.3).
        self.prompt_delay = 0.0
        # Every split carried out: {target, direction, pane_id, focus, id}.
        self.splits = []
        # Every start carried out: {pane_id, name, kind, argv, id}.
        self.starts = []
        # Every agent.get asked: {target, id}.
        self.gets = []
        # Seconds after which herdr gives a launch nothing recognised up, once asked.
        self.launch_timeout = LAUNCH_TIMEOUT
        # Workspace id -> the last pane number handed out there.
        self.pane_counter = {}
        # Every close, workspace and worktree carried out, in order.
        self.closes = []
        self.spaces = []
        self.worktrees = []
        # Directories that exist for `workspace.create`; None: every absolute one.
        self.dirs = None
        # Workspace id -> {repo_key, repo_name, repo_root} `set_repo` declared.
        self.repos = {}
        # Scripted git failures for the next worktree.create calls: {code, message}.
        self.worktree_results = []
        # The last workspace number handed out (`w<n>`).
        self.space_counter = 0
        # Bumped by every reset: a launch thread of an earlier case changes nothing.
        self.epoch = getattr(self, "epoch", 0) + 1

    # --- lifecycle ------------------------------------------------------------

    def appear(self):
        with self.lock:
            if self.listener is not None:
                return
            if os.path.exists(self.socket_path):
                os.unlink(self.socket_path)
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.bind(self.socket_path)
            listener.listen(64)
            self.listener = listener
        threading.Thread(target=self._accept, args=(listener,), daemon=True).start()

    def vanish(self):
        """herdr exiting: the socket file goes away and every connection drops."""
        with self.lock:
            listener, self.listener = self.listener, None
            if listener is not None:
                listener.close()
            if os.path.exists(self.socket_path):
                os.unlink(self.socket_path)
        self.close_streams()
        self.close_hung()

    def close_streams(self):
        with self.lock:
            streams, self.streams = self.streams, []
        for stream in streams:
            _hang_up(stream.conn)

    def close_hung(self):
        with self.lock:
            hung, self.hung = self.hung, []
            held, self.held_snapshots = self.held_snapshots, []
            replies, self.held_replies = self.held_replies, []
        for conn in hung:
            _hang_up(conn)
        for conn, _payload in held + replies:
            _hang_up(conn)

    def _accept(self, listener):
        while True:
            try:
                conn, _ = listener.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    # --- data plane -----------------------------------------------------------

    def _serve(self, conn):
        raw = _read_line(conn)
        if raw is None:
            # Closed before a full line; herdr answers nothing either.
            conn.close()
            return
        try:
            request = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            request = None
        problem = _envelope_problem(request)
        if problem:
            self._violation("malformed request: %s: %r" % (problem, raw[:200]))
            _reply_and_close(conn, {"id": "", "error": {"code": "invalid_request", "message": "invalid request: " + problem}})
            return
        method = request["method"]
        request_id = request["id"]
        with self.lock:
            self.log.append({"method": method, "id": request_id, "params": request["params"], "at": time.monotonic()})
            self.lifetime_methods.add(method)
            allowed = method in READ_ONLY or method in self.allowed
            action = self._take_action(method, request_id) if allowed else None
        if not allowed:
            self._violation("non read-only method: " + method)
            _reply_and_close(conn, {"id": request_id, "error": {"code": "invalid_request", "message": "refused by fake_herdr: " + method}})
            return
        if action is not None:
            kind = action.get("action")
            if kind == "delay":
                # Answer as usual, only later, from this connection's own thread.
                time.sleep(float(action.get("seconds", 1.0)))
            elif kind == "refuse":
                _reply_and_close(conn, {"id": request_id, "error": {
                    "code": action.get("code", "invalid_request"), "message": action.get("message", "refused")}})
                return
            elif kind == "stage":
                # Change what the next read shows, and the pane's status, right
                # before answering it: "the re-read differs", "the state flipped
                # before the send". The status event goes out first, and the read
                # waits `seconds` so the client has taken it in.
                self._stage(action)
                time.sleep(float(action.get("seconds", 0.0)))
            elif kind == "hold" and method in OPERABLE:
                # Carry it out now, answer only on `release_held`: answers out of order.
                reply = self._execute(method, request["params"], request_id)
                with self.lock:
                    self.held_replies.append((conn, reply))
                return
            elif kind == "execute_then_drop":
                # herdr did it; the answer never arrives.
                self._execute(method, request["params"])
                conn.close()
                return
            elif kind == "close_midreply":
                # herdr did it and started to answer, then the connection went.
                reply = line(self._execute(method, request["params"], request_id))
                _send_raw_and_close(conn, reply[: max(1, len(reply) // 2)])
                return
            if kind == "hang":
                # Accept, read, never answer.
                with self.lock:
                    self.hung.append(conn)
                return
            if kind == "hold_snapshot" and method == "session.snapshot":
                # Freeze this complete reply, then release it on the same
                # connection after intervening subscription events.
                with self.lock:
                    payload = {"id": request_id, "result": {
                        "type": "session_snapshot", "snapshot": copy.deepcopy(self.snapshot),
                    }}
                    self.held_snapshots.append((conn, payload))
                return
            if kind == "drop":
                conn.close()
                return
            if kind == "reply":
                _send_raw_and_close(conn, action["line"].replace("$ID", request_id).encode("utf-8") + b"\n")
                return
            if kind == "flood":
                # A reply that never ends: bytes without a newline, and the
                # connection held open, so only the client's own cap can stop it.
                with self.lock:
                    self.hung.append(conn)
                _flood(conn, int(action.get("bytes", 0)))
                return
        if method == "ping":
            with self.lock:
                protocol = self.protocol
            _reply_and_close(conn, {"id": request_id, "result": {
                "type": "pong", "version": VERSION, "protocol": protocol,
                "capabilities": {"live_handoff": True, "detached_server_daemon": True,
                                 "endpoint_protocol_generation": 1, "surface_interest": True, "health_check": True},
            }})
        elif method == "session.snapshot":
            with self.lock:
                snapshot = copy.deepcopy(self.snapshot)
            _reply_and_close(conn, {"id": request_id, "result": {"type": "session_snapshot", "snapshot": snapshot}})
        elif method in OPERABLE:
            _reply_and_close(conn, self._execute(method, request["params"], request_id))
        else:
            self._subscribe(conn, request_id, request["params"])

    # --- the operable methods ---------------------------------------------------

    def _execute(self, method, params, request_id=""):
        """Carry out an allowed operable method and answer what herdr 0.9.0
        would: a result, or an error for a pane it does not know."""
        if method == "agent.prompt":
            return self._prompt(params, request_id)
        if method == "agent.start":
            return self._start_agent(params, request_id)
        if method == "pane.split":
            return self._split(params, request_id)
        if method == "agent.get":
            return self._agent_get(params, request_id)
        if method == "pane.close":
            return self._close(params, request_id)
        if method == "workspace.create":
            return self._create_space(params, request_id)
        if method == "worktree.create":
            return self._create_worktree(params, request_id)
        pane_id = params.get("pane_id")
        if method in INPUTS:
            problem = _input_problem(method, params)
            if problem:
                return {"id": request_id, "error": problem}
        with self.lock:
            pane = next((p for p in self.snapshot.get("panes", [])
                         if isinstance(p, dict) and isinstance(pane_id, str) and p.get("pane_id") == pane_id), None)
        if pane is None:
            return {"id": request_id, "error": {"code": "pane_not_found", "message": "pane %s not found" % pane_id}}
        if method == "pane.read":
            source = params.get("source")
            if source not in READ_SOURCES:
                return {"id": request_id, "error": {"code": "invalid_request", "message": "unknown variant `%s`" % source}}
            if params.get("format") == "ansi":
                return {"id": request_id, "result": {"type": "pane_read", "read": self._screen(pane, source, params.get("lines"))}}
            return {"id": request_id, "result": {"type": "pane_read", "read": self._read(pane, source, params.get("lines"))}}
        if method in INPUTS:
            with self.lock:
                text = params.get("text")
                bracketed = method == "pane.send_input" and isinstance(text, str) and bool(text) and pane_id in self.paste_mode
                self.inputs.append({
                    "method": method, "pane_id": pane_id, "keys": list(params.get("keys") or []),
                    "text": text, "id": request_id, "bracketed": bracketed,
                    "bytes": (BRACKET_OPEN + text + BRACKET_CLOSE if bracketed else text or "").encode("utf-8").hex()
                    if isinstance(text, str) else ""})
            # herdr 0.9.0: sending changes no seen state, focus or active tab.
            return {"id": request_id, "result": {"type": "ok"}}
        self._focus(pane)
        return {"id": request_id, "result": {"type": "ok"}}

    # --- the launch methods -----------------------------------------------------

    def _pane(self, pane_id):
        """The snapshot's pane dict `pane_id`, or None. Caller holds the lock."""
        return next((p for p in self.snapshot.get("panes", [])
                     if isinstance(p, dict) and isinstance(pane_id, str) and p.get("pane_id") == pane_id), None)

    def _record(self, pane_id):
        """The pane's agent record in `agents[]`, or None. Caller holds the lock."""
        return next((a for a in self.snapshot.get("agents", [])
                     if isinstance(a, dict) and a.get("pane_id") == pane_id), None)

    def _agent_info(self, pane, record):
        """An AgentInfo as herdr answers it: the record when there is one,
        otherwise what the pane says."""
        source = record if record is not None else pane
        info = {"terminal_id": pane.get("terminal_id", "")}
        for key in ("name", "agent", "agent_status", "workspace_id", "tab_id", "pane_id", "focused",
                    "interactive_ready", "launch_pending", "state_change_seq", "cwd", "foreground_cwd", "revision"):
            if key in source:
                info[key] = copy.deepcopy(source[key])
        info["pane_id"] = pane["pane_id"]
        if "agent_status" not in info:
            info["agent_status"] = pane.get("agent_status", "unknown")
        return info

    def _prompt(self, params, request_id):
        target = params.get("target")
        if not isinstance(target, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `target` at line 1 column 40"}}
        text = params.get("text")
        if not isinstance(text, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `text` at line 1 column 62"}}
        with self.lock:
            pane_id = self.names.get(target, target)
            pane = self._pane(pane_id)
            record = self._record(pane_id) if pane is not None else None
            launching = pane_id in self.launches or (record is not None and record.get("launch_pending") is True)
            if pane is None or (not pane.get("agent") and not launching):
                return {"id": request_id, "error": {"code": "agent_not_found", "message": "agent target %s not found" % target}}
            status = (record or pane).get("agent_status", pane.get("agent_status"))
        if status == "blocked":
            # herdr writes nothing to a blocked agent (measured).
            return {"id": request_id, "error": {"code": "agent_blocked", "message": "agent %s is blocked and requires interactive input" % target}}
        if launching:
            return {"id": request_id, "error": {"code": "agent_not_ready", "message": "agent %s is not an active named agent" % target}}
        if text == "":
            return {"id": request_id, "error": {"code": "empty_agent_prompt", "message": "agent prompt must not be empty"}}
        with self.lock:
            delay = self.prompt_delay
        if delay > 0:
            time.sleep(delay)
        with self.lock:
            bracketed = pane_id in self.paste_mode
            self.inputs.append({
                "method": "agent.prompt", "pane_id": pane_id, "keys": ["enter"], "text": text, "id": request_id,
                "bracketed": bracketed,
                "bytes": ((BRACKET_OPEN + text + BRACKET_CLOSE if bracketed else text) + "\r").encode("utf-8").hex()})
            info = self._agent_info(pane, record)
        return {"id": request_id, "result": {"type": "agent_prompted", "agent": info}}

    def _start_agent(self, params, request_id):
        name = params.get("name")
        kind = params.get("kind")
        if not isinstance(name, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `name`"}}
        if not isinstance(kind, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `kind`"}}
        pane_id = params.get("pane_id")
        if not AGENT_NAME.fullmatch(name):
            return {"id": request_id, "error": {"code": "invalid_agent_name", "message": (
                "agent name must start with a lowercase letter and contain only lowercase letters, digits, '-' or '_'"
                " (1-32 characters)")}}
        with self.lock:
            holder = self._pane(self.names.get(name))
            if name in self.names:
                where = holder or {}
                return {"id": request_id, "error": {"code": "agent_name_taken", "message": (
                    "agent name %s is already used; candidates: terminal_id=%s pane_id=%s workspace_id=%s tab_id=%s"
                    " cwd=%s status=Idle" % (name, where.get("terminal_id", ""), self.names[name],
                                             where.get("workspace_id", ""), where.get("tab_id", ""),
                                             where.get("foreground_cwd", "")))}}
        if kind.lower() not in KINDS:
            return {"id": request_id, "error": {"code": "unsupported_agent_kind", "message": "unsupported interactive agent kind %s" % kind}}
        with self.lock:
            pane = self._pane(pane_id)
            if pane is None:
                return {"id": request_id, "error": {"code": "agent_pane_not_found", "message": "agent target pane %s not found" % pane_id}}
            # A pane herdr is still launching an agent in is busy, recognised or
            # not, until herdr settles the launch (measured: one start is typed).
            record = self._record(pane_id)
            pending = pane_id in self.launches or (record is not None and record.get("launch_pending") is True)
            if pane.get("agent") or pane_id in self.busy or pending:
                return {"id": request_id, "error": {"code": "agent_pane_busy", "message": "agent target pane %s is not an available shell" % pane_id}}
        timeout = params.get("timeout_ms")
        if timeout is not None and not (isinstance(timeout, int) and 3000 < timeout <= 300000):
            return {"id": request_id, "error": {"code": "invalid_agent_timeout", "message": "agent start timeout must be greater than 3000ms and at most 300000ms"}}
        args = params.get("args") or []
        if any(isinstance(a, str) and ("\n" in a or "\r" in a) for a in args):
            return {"id": request_id, "error": {"code": "invalid_agent_argument", "message": "agent arguments cannot be encoded safely for the target shell"}}
        with self.lock:
            record = {
                "terminal_id": pane.get("terminal_id", ""), "name": name, "agent_status": "unknown",
                "workspace_id": pane.get("workspace_id", ""), "tab_id": pane.get("tab_id", ""), "pane_id": pane_id,
                "focused": bool(pane.get("focused", False)), "launch_pending": True, "state_change_seq": 0,
                "cwd": pane.get("cwd", ""), "foreground_cwd": pane.get("foreground_cwd", ""), "revision": 0,
            }
            agents = [a for a in self.snapshot.get("agents", []) if not (isinstance(a, dict) and a.get("pane_id") == pane_id)]
            agents.append(record)
            self.snapshot["agents"] = agents
            self.names[name] = pane_id
            self.starts.append({"pane_id": pane_id, "name": name, "kind": kind.lower(), "argv": [kind.lower()], "id": request_id})
            self.launches[pane_id] = {"name": name, "kind": kind.lower(), "at": time.monotonic()}
            plan = dict(LAUNCH_DEFAULT)
            plan.update(self.launch_plans.get(pane_id) or self.launch_plans.get("*") or {})
            epoch = self.epoch
            answer = {"id": request_id, "result": {"type": "agent_started", "agent": copy.deepcopy(record), "argv": [kind.lower()]}}
        # No event: herdr sends none until it recognises the agent (measured);
        # the snapshot shows the launch at once.
        if plan.get("outcome") in ("ready", "blocked"):
            threading.Thread(target=self._land, args=(epoch, pane_id, record, plan, kind.lower()), daemon=True).start()
        return answer

    def _land(self, epoch, pane_id, record, plan, kind):
        """A start herdr is launching comes up as `plan` says: recognised
        `detect` seconds on (`pane_agent_detected`, no name or launch fields),
        then ready or blocked `delay` seconds after the start (the per pane
        status event), as measured."""
        agent = str(plan.get("agent") or kind)
        detect = float(plan.get("detect", LAUNCH_DEFAULT["detect"]))
        time.sleep(detect)
        with self.lock:
            pane = self._pane(pane_id)
            if self.epoch != epoch or pane is None or self._record(pane_id) is not record:
                return
            record["agent"] = agent
            pane["agent"] = agent
            workspace = pane.get("workspace_id", "")
        self.emit({"event": "pane_agent_detected", "data": {
            "agent": agent, "pane_id": pane_id, "type": "pane_agent_detected", "workspace_id": workspace}})
        time.sleep(max(0.0, float(plan.get("delay", LAUNCH_DEFAULT["delay"])) - detect))
        status = "idle" if plan.get("outcome") == "ready" else "blocked"
        with self.lock:
            pane = self._pane(pane_id)
            if self.epoch != epoch or pane is None or self._record(pane_id) is not record:
                return
            record["agent_status"] = status
            pane["agent_status"] = status
            if status == "idle":
                record["interactive_ready"] = True
                record.pop("launch_pending", None)
                self.launches.pop(pane_id, None)
            data = {"pane_id": pane_id, "workspace_id": workspace, "agent": agent, "agent_status": status}
        self.emit({"event": PER_PANE, "data": data})

    def _agent_get(self, params, request_id):
        """agent.get: the agent in a pane (or by name) as herdr describes it.
        A launch nothing recognised whose timeout ran out is settled by this
        very ask, and only by it (measured): its record goes, its name and
        pane are free, one `pane_updated` goes out, and the answer is
        `agent_not_found`. Before that it answers the record, unchanged."""
        target = params.get("target")
        if not isinstance(target, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `target`"}}
        with self.lock:
            self.gets.append({"target": target, "id": request_id})
            pane_id = self.names.get(target, target)
            pane = self._pane(pane_id)
            record = self._record(pane_id) if pane is not None else None
            missing = {"id": request_id, "error": {"code": "agent_not_found", "message": "agent target %s not found" % target}}
            if pane is None or (record is None and not pane.get("agent")):
                return missing
            launch = self.launches.get(pane_id)
            timed_out = launch is not None and time.monotonic() - launch["at"] >= self.launch_timeout
            if record is not None and record.get("launch_pending") is True and not record.get("agent") and timed_out:
                self.snapshot["agents"] = [a for a in self.snapshot.get("agents", []) if a is not record]
                for held in [n for n, p in self.names.items() if p == pane_id]:
                    del self.names[held]
                self.launches.pop(pane_id, None)
                updated = {key: copy.deepcopy(value) for key, value in pane.items() if key != "agent"}
                updated["type"] = "pane_updated"
                settled = True
            else:
                settled = False
                info = self._agent_info(pane, record)
        if settled:
            self.emit({"event": "pane_updated", "data": updated})
            return missing
        return {"id": request_id, "result": {"type": "agent_info", "agent": info}}

    def _split(self, params, request_id):
        direction = params.get("direction")
        if direction not in ("right", "down"):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: unknown variant `%s`" % direction}}
        target_id = params.get("target_pane_id")
        focus = params.get("focus") is True
        with self.lock:
            target = self._pane(target_id)
            if target is None:
                return {"id": request_id, "error": {"code": "pane_not_found", "message": "pane not found"}}
            workspace = target.get("workspace_id", "")
            if workspace not in self.pane_counter:
                numbers = [0]
                for p in self.snapshot.get("panes", []):
                    pid = str(p.get("pane_id", "")) if isinstance(p, dict) else ""
                    if pid.startswith(workspace + ":p") and pid[len(workspace) + 2:].isdigit():
                        numbers.append(int(pid[len(workspace) + 2:]))
                self.pane_counter[workspace] = max(numbers)
            self.pane_counter[workspace] += 1
            number = self.pane_counter[workspace]
            new_id = "%s:p%d" % (workspace, number)
            cwd = params.get("cwd") if isinstance(params.get("cwd"), str) else target.get("foreground_cwd", "")
            height = 0
            for layout in self.snapshot.get("layouts", []):
                slots = layout.get("panes", []) if isinstance(layout, dict) else []
                for index, slot in enumerate(slots):
                    if not (isinstance(slot, dict) and slot.get("pane_id") == target_id):
                        continue
                    rect = dict(slot.get("rect") or {})
                    new_rect = dict(rect)
                    # Halved, with no minimum: herdr makes 0x0 panes (measured).
                    if direction == "right":
                        half = int(rect.get("width", 0)) // 2
                        rect["width"] = half
                        new_rect["width"] = half
                        new_rect["x"] = int(rect.get("x", 0)) + half
                    else:
                        half = int(rect.get("height", 0)) // 2
                        rect["height"] = half
                        new_rect["height"] = half
                        new_rect["y"] = int(rect.get("y", 0)) + half
                    height = int(new_rect.get("height", 0))
                    slot["rect"] = rect
                    slots.insert(index + 1, {"pane_id": new_id, "focused": focus, "rect": new_rect})
                    break
            pane = {
                "pane_id": new_id, "terminal_id": "term-%s-%d-split" % (workspace, number),
                "workspace_id": workspace, "tab_id": target.get("tab_id", ""), "focused": focus,
                "cwd": cwd, "foreground_cwd": cwd, "agent_status": "unknown",
                "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": height},
                "revision": 0,
            }
            self.snapshot.setdefault("panes", []).append(pane)
            if focus:
                self.snapshot["focused_pane_id"] = new_id
                self.snapshot["focused_tab_id"] = target.get("tab_id")
                self.snapshot["focused_workspace_id"] = workspace
            self.splits.append({"target": target_id, "direction": direction, "pane_id": new_id, "focus": focus, "id": request_id})
            created = copy.deepcopy(pane)
        if focus:
            self.emit({"event": "pane_focused", "data": {"type": "pane_focused", "pane_id": new_id, "workspace_id": workspace}})
        self.emit({"event": "pane_created", "data": {"type": "pane_created", "pane": created}})
        self.emit({"event": "layout_updated", "data": {"type": "layout_updated", "workspace_id": workspace,
                                                        "tab_id": created.get("tab_id", "")}})
        return {"id": request_id, "result": {"type": "pane_info", "pane": created}}

    # --- the close, space and worktree methods ----------------------------------

    def _close(self, params, request_id):
        pane_id = params.get("pane_id")
        if not isinstance(pane_id, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `pane_id`"}}
        with self.lock:
            pane = self._pane(pane_id)
            if pane is None:
                return {"id": request_id, "error": {"code": "pane_not_found", "message": "pane %s not found" % pane_id}}
            workspace_id = pane.get("workspace_id", "")
            tab_id = pane.get("tab_id", "")
            panes = [p for p in self.snapshot.get("panes", []) if isinstance(p, dict)]
            tabs = [t for t in self.snapshot.get("tabs", []) if isinstance(t, dict)]
            workspaces = [w for w in self.snapshot.get("workspaces", []) if isinstance(w, dict)]
            last_of_tab = len([p for p in panes if p.get("tab_id") == tab_id]) <= 1
            last_of_space = last_of_tab and len([t for t in tabs if t.get("workspace_id") == workspace_id]) <= 1
            workspace = next((w for w in workspaces if w.get("workspace_id") == workspace_id), None)
            if last_of_space and workspace is not None:
                tree = workspace.get("worktree") or {}
                if tree and not tree.get("is_linked_worktree") and tree.get("repo_key"):
                    grouped = [w for w in workspaces if w is not workspace
                               and (w.get("worktree") or {}).get("repo_key") == tree.get("repo_key")]
                    if grouped:
                        return {"id": request_id, "error": {
                            "code": "confirmation_required", "message": "closing this pane would close a worktree group"}}
            self.snapshot["panes"] = [p for p in self.snapshot.get("panes", []) if p is not pane]
            self.snapshot["agents"] = [a for a in self.snapshot.get("agents", [])
                                       if not (isinstance(a, dict) and a.get("pane_id") == pane_id)]
            for layout in self.snapshot.get("layouts", []):
                if isinstance(layout, dict):
                    layout["panes"] = [slot for slot in layout.get("panes", [])
                                       if not (isinstance(slot, dict) and slot.get("pane_id") == pane_id)]
            events = []
            if last_of_tab:
                self.snapshot["tabs"] = [t for t in self.snapshot.get("tabs", [])
                                         if not (isinstance(t, dict) and t.get("tab_id") == tab_id)]
                self.snapshot["layouts"] = [l for l in self.snapshot.get("layouts", [])
                                            if not (isinstance(l, dict) and l.get("tab_id") == tab_id)]
            else:
                for tab in tabs:
                    if tab.get("tab_id") == tab_id and "pane_count" in tab:
                        tab["pane_count"] = max(0, int(tab["pane_count"]) - 1)
            if last_of_space and workspace is not None:
                self.snapshot["workspaces"] = [w for w in self.snapshot.get("workspaces", []) if w is not workspace]
                closed = copy.deepcopy(workspace)
                events.append({"event": "workspace_closed", "data": {
                    "type": "workspace_closed", "workspace_id": workspace_id, "workspace": closed}})
            elif workspace is not None:
                if "pane_count" in workspace:
                    workspace["pane_count"] = max(0, int(workspace["pane_count"]) - 1)
                if last_of_tab and "tab_count" in workspace:
                    workspace["tab_count"] = max(0, int(workspace["tab_count"]) - 1)
            events.append({"event": "pane_closed", "data": {
                "type": "pane_closed", "pane_id": pane_id, "workspace_id": workspace_id}})
            if not last_of_tab:
                events.append({"event": "layout_updated", "data": {
                    "type": "layout_updated", "workspace_id": workspace_id, "tab_id": tab_id}})
            for held in [n for n, p in self.names.items() if p == pane_id]:
                del self.names[held]
            self.launches.pop(pane_id, None)
            self.busy.discard(pane_id)
            if self.snapshot.get("focused_pane_id") == pane_id:
                # herdr's focus moves to a sibling of the tab, else to another
                # workspace (the one before it), with no focus event (measured).
                left = [p for p in self.snapshot.get("panes", []) if isinstance(p, dict)]
                sibling = next((p for p in left if p.get("tab_id") == tab_id), None)
                if sibling is None:
                    sibling = next((p for p in left if p.get("workspace_id") == workspace_id), None)
                if sibling is None:
                    order = [w.get("workspace_id") for w in workspaces]
                    at = order.index(workspace_id) if workspace_id in order else 0
                    for candidate in order[at - 1::-1] + order[at + 1:] if at > 0 else order[at + 1:]:
                        sibling = next((p for p in left if p.get("workspace_id") == candidate), None)
                        if sibling is not None:
                            break
                if sibling is None:
                    self.snapshot["focused_pane_id"] = None
                    self.snapshot["focused_tab_id"] = None
                    self.snapshot["focused_workspace_id"] = None
                else:
                    self.snapshot["focused_pane_id"] = sibling.get("pane_id")
                    self.snapshot["focused_tab_id"] = sibling.get("tab_id")
                    self.snapshot["focused_workspace_id"] = sibling.get("workspace_id")
                    for p in left:
                        p["focused"] = p is sibling
            self.closes.append({"pane_id": pane_id, "last_of_tab": last_of_tab, "last_of_space": last_of_space,
                                "id": request_id})
        self._emit_later(events)
        return {"id": request_id, "result": {"type": "ok"}}

    def _emit_later(self, events):
        """The events of a close, a space or a worktree go out EVENTS_AFTER
        seconds after the reply, in order, as measured (30 to 120 ms after)."""
        def send():
            for envelope in events:
                self.emit(envelope)
        threading.Timer(EVENTS_AFTER, send).start()

    def _new_space(self, label, directory, focus, worktree):
        """A fresh workspace with one tab and one shell in `directory`, added
        to the snapshot (caller holds the lock): the workspace, tab and pane
        records, focused when `focus` or when the server was empty."""
        workspaces = [w for w in self.snapshot.get("workspaces", []) if isinstance(w, dict)]
        numbers = [int(w.get("number", 0)) for w in workspaces if isinstance(w.get("number"), (int, float))]
        if self.space_counter == 0:
            self.space_counter = max(numbers + [len(workspaces)])
        self.space_counter += 1
        workspace_id = "w%d" % self.space_counter
        while any(w.get("workspace_id") == workspace_id for w in workspaces):
            self.space_counter += 1
            workspace_id = "w%d" % self.space_counter
        focused = bool(focus) or not workspaces
        tab_id = workspace_id + ":t1"
        pane_id = workspace_id + ":p1"
        workspace = {
            "workspace_id": workspace_id, "number": max(numbers + [0]) + 1, "label": label, "focused": focused,
            "pane_count": 1, "tab_count": 1, "active_tab_id": tab_id, "agent_status": "idle", "worktree": worktree,
        }
        tab = {"tab_id": tab_id, "workspace_id": workspace_id, "number": 1, "label": NEW_TAB_LABEL,
               "focused": focused, "pane_count": 1, "agent_status": "idle"}
        pane = {
            "pane_id": pane_id, "terminal_id": "term-%s-1" % workspace_id, "workspace_id": workspace_id,
            "tab_id": tab_id, "focused": focused, "cwd": directory, "foreground_cwd": directory,
            "agent_status": "unknown",
            "scroll": {"offset_from_bottom": 0, "max_offset_from_bottom": 0, "viewport_rows": NEW_RECT["height"]},
            "revision": 0,
        }
        self.snapshot.setdefault("workspaces", []).append(workspace)
        self.snapshot.setdefault("tabs", []).append(tab)
        self.snapshot.setdefault("panes", []).append(pane)
        self.snapshot.setdefault("layouts", []).append({
            "tab_id": tab_id, "panes": [{"pane_id": pane_id, "focused": focused, "rect": dict(NEW_RECT)}]})
        if focused:
            for w in workspaces:
                w["focused"] = False
            for p in self.snapshot.get("panes", []):
                if isinstance(p, dict) and p is not pane:
                    p["focused"] = False
            self.snapshot["focused_pane_id"] = pane_id
            self.snapshot["focused_tab_id"] = tab_id
            self.snapshot["focused_workspace_id"] = workspace_id
        return workspace, tab, pane

    @staticmethod
    def _space_events(workspace, tab, pane, extra=()):
        """The events a new workspace sends, in the measured order; `extra`
        goes right after `workspace_created` (a parent's update, the worktree)."""
        focused = bool(workspace.get("focused"))
        workspace_id = workspace["workspace_id"]
        events = [{"event": "workspace_created", "data": {"type": "workspace_created", "workspace": copy.deepcopy(workspace)}}]
        if focused:
            events.append({"event": "workspace_focused", "data": {"type": "workspace_focused", "workspace_id": workspace_id}})
        events.extend(extra)
        events.append({"event": "tab_created", "data": {"type": "tab_created", "tab": copy.deepcopy(tab)}})
        if focused:
            events.append({"event": "tab_focused", "data": {"type": "tab_focused", "tab_id": tab["tab_id"], "workspace_id": workspace_id}})
        events.append({"event": "pane_created", "data": {"type": "pane_created", "pane": copy.deepcopy(pane)}})
        if focused:
            events.append({"event": "pane_focused", "data": {"type": "pane_focused", "pane_id": pane["pane_id"], "workspace_id": workspace_id}})
        events.append({"event": "layout_updated", "data": {"type": "layout_updated", "workspace_id": workspace_id, "tab_id": tab["tab_id"]}})
        return events

    def _create_space(self, params, request_id):
        cwd = params.get("cwd")
        if cwd is not None and not isinstance(cwd, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: invalid type: expected a string for `cwd`"}}
        label = params.get("label")
        if label is not None and not isinstance(label, str):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: invalid type: expected a string for `label`"}}
        focus = params.get("focus")
        if focus is not None and not isinstance(focus, bool):
            return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: invalid type: expected a boolean for `focus`"}}
        env = params.get("env")
        if env is not None:
            if not isinstance(env, dict) or any(not isinstance(v, str) for v in env.values()):
                return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: invalid type for `env`"}}
            bad = next((k for k in env if "=" in k), None)
            if bad is not None:
                return {"id": request_id, "error": {"code": "invalid_env", "message": "env key %s must not contain '='" % bad}}
        with self.lock:
            source = params.get("source_workspace_id")
            if source is not None and not any(isinstance(w, dict) and w.get("workspace_id") == source
                                              for w in self.snapshot.get("workspaces", [])):
                return {"id": request_id, "error": {"code": "workspace_not_found", "message": "workspace %s not found" % source}}
            if cwd is None:
                # {}: the focused pane's cwd (measured, ambiguous with the server's own).
                focused = self._pane(self.snapshot.get("focused_pane_id"))
                directory = (focused or {}).get("cwd") or HOME
            elif cwd.startswith("/") and (self.dirs is None or cwd in self.dirs):
                directory = cwd
            else:
                # A bad cwd never fails: it lands in $HOME (measured).
                directory = HOME
            if label is None:
                label = "~" if directory == HOME else os.path.basename(directory.rstrip("/")) or "~"
            workspace, tab, pane = self._new_space(label, directory, focus is True, None)
            events = self._space_events(workspace, tab, pane)
            self.spaces.append({"cwd": cwd, "directory": directory, "label": label, "focus": focus is True,
                                "workspace_id": workspace["workspace_id"], "id": request_id})
            answer = {"id": request_id, "result": {
                "type": "workspace_created", "workspace": copy.deepcopy(workspace), "tab": copy.deepcopy(tab),
                "root_pane": copy.deepcopy(pane)}}
        self._emit_later(events)
        return answer

    def _create_worktree(self, params, request_id):
        for field in ("workspace_id", "cwd", "branch", "base", "path", "label"):
            if params.get(field) is not None and not isinstance(params.get(field), str):
                return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: invalid type: expected a string for `%s`" % field}}
        for field in ("focus", "trust_repository"):
            if params.get(field) is not None and not isinstance(params.get(field), bool):
                return {"id": "", "error": {"code": "invalid_request", "message": "invalid request: invalid type: expected a boolean for `%s`" % field}}
        branch = params.get("branch")
        if branch is None:
            branch = "worktree/rapid-river-%d" % (4206 + len(self.worktrees))
        if not branch.strip():
            return {"id": request_id, "error": {"code": "invalid_request", "message": "branch is required"}}
        branch = branch.strip()
        path = params.get("path")
        if path is not None:
            if path.startswith("~"):
                path = HOME + path[1:]
            if not path.startswith("/"):
                return {"id": request_id, "error": {"code": "invalid_request", "message": "worktree path must be absolute"}}
        focus = params.get("focus") is True
        with self.lock:
            workspaces = [w for w in self.snapshot.get("workspaces", []) if isinstance(w, dict)]
            workspace_id = params.get("workspace_id")
            cwd = params.get("cwd")
            if workspace_id is not None:
                workspace = next((w for w in workspaces if w.get("workspace_id") == workspace_id), None)
                if workspace is None:
                    # Not measured: herdr's message for an unknown workspace is unknown.
                    return {"id": request_id, "error": {"code": "workspace_not_found", "message": "workspace %s not found" % workspace_id}}
            elif cwd is not None:
                workspace = next((w for w in workspaces if (w.get("worktree") or {}).get("checkout_path")
                                  and cwd.startswith((w.get("worktree") or {}).get("checkout_path"))), None)
                if workspace is None:
                    return {"id": request_id, "error": {"code": "not_git_worktree",
                                                        "message": "Herdr worktree actions require a path inside a Git work tree"}}
            else:
                focused_id = self.snapshot.get("focused_workspace_id")
                workspace = next((w for w in workspaces if w.get("workspace_id") == focused_id), None)
            tree = (workspace or {}).get("worktree") or None
            declared = self.repos.get((workspace or {}).get("workspace_id"))
            if workspace is None or (tree is None and declared is None):
                return {"id": request_id, "error": {"code": "not_git_worktree",
                                                    "message": "Herdr worktree actions require a workspace inside a Git work tree"}}
            if tree is not None and tree.get("is_linked_worktree"):
                return {"id": request_id, "error": {"code": "linked_worktree_source",
                                                    "message": "New and open worktree actions start from the repo parent workspace."}}
            if self.worktree_results:
                failure = self.worktree_results.pop(0)
                return {"id": request_id, "error": {"code": failure.get("code", "worktree_create_failed"),
                                                    "message": failure.get("message", "")}}
            if tree is None:
                repo_key = declared.get("repo_key", "%s/.git" % declared.get("repo_root", HOME))
                repo_name = declared.get("repo_name", os.path.basename(declared.get("repo_root", "repo")))
                repo_root = declared.get("repo_root", HOME + "/" + repo_name)
            else:
                repo_key = tree.get("repo_key", "")
                repo_name = tree.get("repo_name", "")
                repo_root = tree.get("repo_root", "")
            checkout = path if path is not None else "%s/%s/%s" % (WORKTREES_DIR, repo_name, branch)
            label = params.get("label")
            if label is None:
                label = os.path.basename(checkout.rstrip("/"))
            linked = {"repo_key": repo_key, "repo_name": repo_name, "repo_root": repo_root,
                      "checkout_path": checkout, "is_linked_worktree": True}
            extra = []
            if tree is None:
                # The parent gains its worktree field the first time (measured).
                workspace["worktree"] = {"repo_key": repo_key, "repo_name": repo_name, "repo_root": repo_root,
                                         "checkout_path": repo_root, "is_linked_worktree": False}
                extra.append({"event": "workspace_updated", "data": {
                    "type": "workspace_updated", "workspace": copy.deepcopy(workspace)}})
            new_space, tab, pane = self._new_space(label, checkout, focus, linked)
            info = {"path": checkout, "branch": branch, "is_bare": False, "is_detached": False, "is_prunable": False,
                    "is_linked_worktree": True, "open_workspace_id": new_space["workspace_id"], "label": repo_name}
            extra.append({"event": "worktree_created", "data": {
                "type": "worktree_created", "workspace": copy.deepcopy(new_space), "worktree": dict(info)}})
            events = self._space_events(new_space, tab, pane, extra)
            self.worktrees.append({"workspace_id": workspace.get("workspace_id"), "branch": branch, "path": checkout,
                                   "label": label, "focus": focus, "new_workspace_id": new_space["workspace_id"],
                                   "id": request_id})
            answer = {"id": request_id, "result": {
                "type": "worktree_created", "workspace": copy.deepcopy(new_space), "tab": copy.deepcopy(tab),
                "root_pane": copy.deepcopy(pane), "worktree": dict(info)}}
        self._emit_later(events)
        return answer

    def _read(self, pane, source, lines):
        pane_id = pane["pane_id"]
        with self.lock:
            scripted = self.previews.get((pane_id, source)) or self.previews.get((pane_id, None))
        if scripted is None:
            scripted = {"text": "%s %s\n$ herdr pane read %s\n" % (pane_id, source, pane_id), "truncated": False}
        text = scripted["text"]
        # `lines` keeps the last so many; herdr counts lines, not bytes.
        if isinstance(lines, int) and lines > 0:
            text = "\n".join(text.split("\n")[-lines:])
        return {
            "pane_id": pane_id, "workspace_id": pane.get("workspace_id", ""), "tab_id": pane.get("tab_id", ""),
            "source": source, "format": "text", "text": text, "revision": 0, "truncated": bool(scripted["truncated"]),
        }

    def _screen(self, pane, source, lines):
        """A read in `ansi`: the scripted screen, or the preview text as plain
        rows. `lines` keeps the last so many, as herdr does for `recent`. An
        animated screen changes its first row on every read."""
        pane_id = pane["pane_id"]
        with self.lock:
            scripted = self.screens.get((pane_id, source)) or self.screens.get((pane_id, None))
            if scripted is not None and scripted.get("animate"):
                self.frames[pane_id] = self.frames.get(pane_id, 0) + 1
                frame = self.frames[pane_id]
            else:
                frame = 0
        if scripted is None:
            plain = self._read(pane, source, None)["text"]
            text, truncated, revision = plain.replace("\n", "\r\n"), False, 0
        else:
            text, truncated, revision = scripted["ansi"], scripted["truncated"], scripted["revision"]
            if frame:
                rows = text.split("\r\n")
                rows[0] = "\x1b[0m\x1b[38;5;%dmframe %06d\x1b[0m" % (frame % 256, frame)
                text = "\r\n".join(rows)
        if isinstance(lines, int) and lines > 0:
            text = "\r\n".join(text.split("\r\n")[-lines:])
        return {
            "pane_id": pane_id, "workspace_id": pane.get("workspace_id", ""), "tab_id": pane.get("tab_id", ""),
            "source": source, "format": "ansi", "text": text, "revision": revision, "truncated": bool(truncated),
        }

    def _focus(self, pane):
        """herdr's focus is shared by every attached client, and it marks the
        whole tab seen: every `done` there turns `idle` (measured on 0.9.0)."""
        tab_id = pane.get("tab_id")
        workspace_id = pane.get("workspace_id")
        with self.lock:
            snapshot = self.snapshot
            snapshot["focused_pane_id"] = pane["pane_id"]
            snapshot["focused_tab_id"] = tab_id
            snapshot["focused_workspace_id"] = workspace_id
            for workspace in snapshot.get("workspaces", []):
                if isinstance(workspace, dict) and workspace.get("workspace_id") == workspace_id:
                    workspace["active_tab_id"] = tab_id
            seen = []
            for key in ("panes", "agents"):
                for record in snapshot.get(key, []):
                    if isinstance(record, dict) and record.get("tab_id") == tab_id and record.get("agent_status") == "done":
                        record["agent_status"] = "idle"
                        if key == "panes":
                            seen.append(record)
        for record in seen:
            self.emit({"event": PER_PANE, "data": {
                "pane_id": record["pane_id"], "workspace_id": record.get("workspace_id", ""), "agent_status": "idle"}})
        self.emit({"event": "pane_focused", "data": {
            "type": "pane_focused", "pane_id": pane["pane_id"], "workspace_id": workspace_id or ""}})

    def _take_action(self, method, request_id=""):
        for index, action in enumerate(self.actions):
            if action.get("method") not in (None, method):
                continue
            # `id_suffix` picks one request of a kind: Herdstead's re-read before
            # an input carries its ticket's id plus `:check`.
            suffix = action.get("id_suffix")
            if suffix is not None and not str(request_id).endswith(suffix):
                continue
            return self.actions.pop(index)
        return None

    def _stage(self, action):
        preview = action.get("preview")
        if isinstance(preview, dict):
            with self.lock:
                self.previews[(preview["pane_id"], preview.get("source"))] = {
                    "text": str(preview.get("text", "")), "truncated": bool(preview.get("truncated", False))}
        status = action.get("status")
        if isinstance(status, dict):
            self.set_status(status["pane_id"], status["agent_status"], status.get("agent"))

    def set_status(self, pane_id, agent_status, agent=None):
        """Change a pane's status in the snapshot and emit the per-pane event."""
        with self.lock:
            pane = next(p for p in self.snapshot.get("panes", []) if isinstance(p, dict) and p.get("pane_id") == pane_id)
            pane["agent_status"] = agent_status
            data = {"pane_id": pane["pane_id"], "workspace_id": pane.get("workspace_id", ""), "agent_status": agent_status}
            if agent is not None:
                pane["agent"] = agent
                data["agent"] = agent
            # A normal server snapshot agrees with the event. Tests can use
            # `emit` alone to exercise the window before a fresh snapshot.
            for record in self.snapshot.get("agents", []):
                if (isinstance(record, dict) and record.get("pane_id") == pane["pane_id"]
                        and record.get("terminal_id") == pane.get("terminal_id")):
                    # The fake does not model herdr's global AgentState sequence;
                    # keep the fixture value rather than invent its rules.
                    record["agent_status"] = agent_status
                    if agent is not None:
                        record["agent"] = agent
        return self.emit({"event": PER_PANE, "data": data})

    def _subscribe(self, conn, request_id, params):
        subscriptions = params.get("subscriptions")
        if not isinstance(subscriptions, list):
            _reply_and_close(conn, {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `subscriptions`"}})
            return
        types = set()
        panes = set()
        with self.lock:
            known = {str(p.get("pane_id", "")) for p in self.snapshot.get("panes", []) if isinstance(p, dict)}
        for index, entry in enumerate(subscriptions):
            kind = entry.get("type") if isinstance(entry, dict) else None
            if kind not in EVENT_TYPES:
                self._stream_error("unknown variant %r" % (kind,))
                _reply_and_close(conn, {"id": "", "error": {"code": "invalid_request", "message": "invalid request: unknown variant `%s`" % kind}})
                return
            if kind == PER_PANE:
                if not isinstance(entry.get("pane_id"), str):
                    self._stream_error("missing pane_id")
                    _reply_and_close(conn, {"id": "", "error": {"code": "invalid_request", "message": "invalid request: missing field `pane_id`"}})
                    return
                if entry["pane_id"] not in known:
                    self._stream_error("pane_not_found " + entry["pane_id"])
                    _reply_and_close(conn, {"id": "%s:sub:%d:probe" % (request_id, index), "error": {
                        "code": "pane_not_found", "message": "pane %s not found" % entry["pane_id"]}})
                    return
                panes.add(entry["pane_id"])
            else:
                types.add(kind)
        stream = Stream(conn, request_id, types, panes)
        with self.lock:
            self.streams.append(stream)
            hold = self.hold_ack
        if not hold:
            self._start(stream)
        # Watch for the client hanging up; it never sends anything else.
        threading.Thread(target=self._watch, args=(stream,), daemon=True).start()

    def _start(self, stream):
        stream.started = True
        stream.send(line({"id": stream.request_id, "result": {"type": "subscription_started"}}))

    def _watch(self, stream):
        try:
            while stream.conn.recv(4096):
                pass
        except OSError:
            pass
        with self.lock:
            if stream in self.streams:
                self.streams.remove(stream)
        _hang_up(stream.conn)

    def emit(self, envelope):
        name = str(envelope.get("event", ""))
        data = envelope.get("data", {})
        payload = line(envelope)
        sent = 0
        for stream in self._live_streams():
            if stream.wants(name, data if isinstance(data, dict) else {}) and stream.send(payload):
                sent += 1
        return sent

    def raw(self, chunks, pause):
        sent = 0
        for stream in self._live_streams():
            for index, chunk in enumerate(chunks):
                if index:
                    time.sleep(pause)
                stream.send(chunk)
            sent += 1
        return sent

    def flood(self, size):
        """`size` bytes without a newline to every live stream, from a thread of
        its own: the client has to be pumped to drain them, and the control
        connection must answer before that."""
        streams = self._live_streams()
        for stream in streams:
            threading.Thread(target=_flood, args=(stream.conn, size, stream.lock), daemon=True).start()
        return len(streams)

    def _live_streams(self):
        with self.lock:
            return [s for s in self.streams if s.started]

    def _violation(self, text):
        with self.lock:
            self.violations.append(text)
        print("fake_herdr: VIOLATION " + text, file=sys.stderr, flush=True)

    def _stream_error(self, text):
        with self.lock:
            self.stream_errors.append(text)


class Control:
    """One JSON command per connection on the control socket:

    reset {fixture}          drop every connection, clear logs and scripted
                             actions, close what `allow` opened, forget scripted
                             previews and protocol, load a snapshot fixture,
                             be reachable
    allow {methods: [str]}   answer these methods too (only OPERABLE exist);
                             anything else stays a violation
    set_preview {pane_id, source?, text?, fill?, truncated?}
                             what pane.read answers for that pane (and source;
                             without one, for every source); `fill` appends that
                             many bytes of one long line, for a reply over a cap
    set_screen {pane_id, source?, ansi, truncated?, revision?, fill?, animate?}
                             what pane.read answers in `ansi` for that pane
                             (and source; without one, for every source); an
                             animated screen's first row changes on every read
    set_paste_mode {pane_id, on?}
                             whether that pane's program asked for bracketed
                             paste: pane.send_input's text is then recorded as
                             bracketed
    set_protocol {protocol}  what ping announces
    set_launch {pane_id?: str | "*", outcome: ready|blocked|never, detect?, delay?, agent?}
                             how the next agent.start in that pane (or any,
                             `*`) turns out: recognised after `detect` seconds
                             (default 0.3), then `ready` or `blocked` (still
                             launching) `delay` seconds after the start
                             (default 3.6), or `never`; `agent` is the kind
                             herdr recognises
    set_busy {pane_id, on?}  another program is in front of that pane's shell:
                             agent.start answers agent_pane_busy
    set_prompt_delay {seconds}
                             how long agent.prompt takes to answer
    set_launch_timeout {seconds}
                             herdr's own launch timeout (default 30.4): after
                             it, the first agent.get settles a launch nothing
                             recognised
    set_snapshot {fixture | snapshot}
    status {pane_id, agent_status, agent?}
                             change a pane in the snapshot and emit the per
                             pane event to the streams covering that pane
    emit {envelope | fixture_event}
    raw {chunks: [str], hex?: bool, pause?}
                             write bytes verbatim to every live stream
    flood {bytes}            write that many bytes without a newline to every
                             live stream, in the background
    close_streams            server-side hangup of every subscription
    vanish / appear          unlink the socket and drop everything / come back
    next {action: hang|drop|reply|hold_snapshot|flood|delay|refuse|
                  execute_then_drop|close_midreply|hold|stage, method?,
                  id_suffix?, line?, bytes?, seconds?, code?, message?,
                  preview?, status?}
                             script the answer to the next matching request
                             (of `method`, and whose id ends in `id_suffix`);
                             `$ID` in a reply line becomes the request id, and a
                             flood answers `bytes` bytes without a newline and
                             then holds the connection open. `delay` answers as
                             usual `seconds` later; `refuse` answers an error
                             with `code`; `execute_then_drop` carries an operable
                             method out and closes without answering, and
                             `close_midreply` sends half of its answer first.
                             `hold` carries an operable method out and keeps its
                             answer until `release_held` (answers out of order).
                             `stage` first applies `preview` ({pane_id, source?,
                             text, truncated?}, as set_preview) and `status`
                             ({pane_id, agent_status, agent?}, as status, event
                             included), waits `seconds`, then answers as usual
    release_held             send every answer `hold` kept, oldest first
    hold_ack {hold}          withhold subscription_started until released
    release                  send the withheld subscription_started
    release_snapshots        send complete withheld snapshot replies
    stats                    what the client asked for so far, and for the launch
                             methods `names`, `launches`, `splits`, `starts`,
                             `gets`; for close / space / worktree `closes`, `spaces`, `worktrees`
    set_dirs {existing}      the directories workspace.create finds (any other
                             lands in $HOME); unset, every absolute one exists
    set_repo {workspace_id, repo_key?, repo_name?, repo_root?}
                             the workspace is a git checkout though its snapshot
                             record has no `worktree` yet (measured: a parent's
                             appears with its first worktree)
    set_worktree_result {code, message}
                             the next worktree.create fails so (git's message)
    """

    def __init__(self, herdr, path):
        self.herdr = herdr
        self.path = path

    def serve(self):
        if os.path.exists(self.path):
            os.unlink(self.path)
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(self.path)
        listener.listen(16)
        while True:
            conn, _ = listener.accept()
            raw = _read_line(conn)
            try:
                # Godot's JSON.stringify leaves control characters raw; tests use them.
                command = json.loads(raw.decode("utf-8"), strict=False) if raw else {}
                answer = {"ok": True, "result": self.run(command.get("cmd", ""), command.get("args", {}))}
            except Exception as error:  # noqa: BLE001 - report every failure to the test
                answer = {"ok": False, "error": "%s: %s" % (type(error).__name__, error)}
            _reply_and_close(conn, answer)

    def fixture(self, name):
        with open(os.path.join(self.herdr.fixtures, name + ".json"), encoding="utf-8") as source:
            return json.load(source)

    def run(self, cmd, args):
        herdr = self.herdr
        if cmd == "reset":
            herdr.close_streams()
            herdr.close_hung()
            with herdr.lock:
                herdr.actions = []
                herdr.hold_ack = False
                herdr.log = []
                herdr.stream_errors = []
                herdr.allowed = set()
                herdr.previews = {}
                herdr.protocol = PROTOCOL
                herdr.inputs = []
                herdr.screens = {}
                herdr.paste_mode = set()
                herdr.frames = {}
                herdr._fresh_writes()
                herdr.snapshot = self.fixture(args.get("fixture", "snapshot_basic"))["snapshot"]
            herdr.appear()
            return {}
        if cmd == "allow":
            methods = args.get("methods", [])
            unknown = [m for m in methods if m not in OPERABLE]
            if unknown:
                raise ValueError("fake_herdr cannot answer %r" % unknown)
            with herdr.lock:
                herdr.allowed = set(methods)
            return {"allowed": sorted(methods)}
        if cmd == "set_preview":
            text = str(args.get("text", "")) + "x" * int(args.get("fill", 0))
            with herdr.lock:
                herdr.previews[(args["pane_id"], args.get("source"))] = {
                    "text": text, "truncated": bool(args.get("truncated", False))}
            return {"bytes": len(text.encode("utf-8"))}
        if cmd == "set_screen":
            ansi = str(args.get("ansi", "")) + "x" * int(args.get("fill", 0))
            with herdr.lock:
                herdr.screens[(args["pane_id"], args.get("source"))] = {
                    "ansi": ansi, "truncated": bool(args.get("truncated", False)),
                    "revision": args.get("revision", 0), "animate": bool(args.get("animate", False))}
            return {"bytes": len(ansi.encode("utf-8"))}
        if cmd == "set_paste_mode":
            with herdr.lock:
                if args.get("on", True):
                    herdr.paste_mode.add(args["pane_id"])
                else:
                    herdr.paste_mode.discard(args["pane_id"])
            return {}
        if cmd == "set_launch":
            outcome = args.get("outcome", "ready")
            if outcome not in ("ready", "blocked", "never"):
                raise ValueError("unknown launch outcome %r" % outcome)
            with herdr.lock:
                herdr.launch_plans[str(args.get("pane_id", "*"))] = {
                    "outcome": outcome, "detect": float(args.get("detect", LAUNCH_DEFAULT["detect"])),
                    "delay": float(args.get("delay", LAUNCH_DEFAULT["delay"])), "agent": args.get("agent")}
            return {}
        if cmd == "set_busy":
            with herdr.lock:
                if args.get("on", True):
                    herdr.busy.add(args["pane_id"])
                else:
                    herdr.busy.discard(args["pane_id"])
            return {}
        if cmd == "set_launch_timeout":
            with herdr.lock:
                herdr.launch_timeout = float(args.get("seconds", LAUNCH_TIMEOUT))
            return {}
        if cmd == "set_dirs":
            with herdr.lock:
                herdr.dirs = set(str(d) for d in args.get("existing", []))
            return {}
        if cmd == "set_repo":
            with herdr.lock:
                herdr.repos[str(args["workspace_id"])] = {k: str(v) for k, v in args.items() if k != "workspace_id"}
            return {}
        if cmd == "set_worktree_result":
            with herdr.lock:
                herdr.worktree_results.append({"code": str(args.get("code", "worktree_create_failed")),
                                               "message": str(args.get("message", ""))})
            return {}
        if cmd == "set_prompt_delay":
            with herdr.lock:
                herdr.prompt_delay = float(args.get("seconds", 0.0))
            return {}
        if cmd == "set_protocol":
            with herdr.lock:
                herdr.protocol = args["protocol"]
            return {}
        if cmd == "set_snapshot":
            snapshot = args["snapshot"] if "snapshot" in args else self.fixture(args["fixture"])["snapshot"]
            with herdr.lock:
                herdr.snapshot = snapshot
            return {}
        if cmd == "status":
            return {"sent": herdr.set_status(args["pane_id"], args["agent_status"], args.get("agent"))}
        if cmd == "emit":
            envelope = args["envelope"] if "envelope" in args else self.fixture("events")[args["fixture_event"]]["envelope"]
            return {"sent": herdr.emit(envelope)}
        if cmd == "raw":
            chunks = [bytes.fromhex(c) if args.get("hex") else c.encode("utf-8") for c in args["chunks"]]
            return {"sent": herdr.raw(chunks, float(args.get("pause", 0.05)))}
        if cmd == "flood":
            return {"sent": herdr.flood(int(args["bytes"]))}
        if cmd == "close_streams":
            herdr.close_streams()
            return {}
        if cmd == "vanish":
            herdr.vanish()
            return {}
        if cmd == "appear":
            herdr.appear()
            return {}
        if cmd == "next":
            with herdr.lock:
                herdr.actions.append(dict(args))
            return {}
        if cmd == "hold_ack":
            with herdr.lock:
                herdr.hold_ack = bool(args.get("hold", True))
            return {}
        if cmd == "release":
            with herdr.lock:
                herdr.hold_ack = False
                waiting = [s for s in herdr.streams if not s.started]
            for stream in waiting:
                herdr._start(stream)
            return {"released": len(waiting)}
        if cmd == "release_held":
            with herdr.lock:
                waiting, herdr.held_replies = herdr.held_replies, []
            for conn, payload in waiting:
                _reply_and_close(conn, payload)
            return {"released": len(waiting)}
        if cmd == "release_snapshots":
            with herdr.lock:
                waiting, herdr.held_snapshots = herdr.held_snapshots, []
            for conn, payload in waiting:
                _reply_and_close(conn, payload)
            return {"released": len(waiting)}
        if cmd == "stats":
            with herdr.lock:
                subscribes = [r for r in herdr.log if r["method"] == "events.subscribe"]
                last_panes = []
                last_types = []
                if subscribes:
                    for entry in subscribes[-1]["params"].get("subscriptions", []):
                        if entry.get("type") == PER_PANE:
                            last_panes.append(entry.get("pane_id"))
                        else:
                            last_types.append(entry.get("type"))
                return {
                    "methods": [r["method"] for r in herdr.log],
                    "ids": [r["id"] for r in herdr.log],
                    # When each request arrived, in this server's monotonic seconds.
                    "times": [r["at"] for r in herdr.log],
                    "params": [r["params"] for r in herdr.log],
                    "snapshot_count": sum(1 for r in herdr.log if r["method"] == "session.snapshot"),
                    "subscribe_count": len(subscribes),
                    "last_subscribe_panes": sorted(last_panes),
                    "last_subscribe_types": last_types,
                    "streams_live": sum(1 for s in herdr.streams if s.started),
                    "streams_pending": sum(1 for s in herdr.streams if not s.started),
                    "stream_panes": [sorted(s.panes) for s in herdr.streams],
                    "hung": len(herdr.hung),
                    "held_snapshots": len(herdr.held_snapshots),
                    "held_replies": len(herdr.held_replies),
                    "inputs": [dict(record) for record in herdr.inputs],
                    "stream_errors": list(herdr.stream_errors),
                    "lifetime_methods": sorted(herdr.lifetime_methods),
                    "violations": list(herdr.violations),
                    "socket_present": os.path.exists(herdr.socket_path),
                    "allowed": sorted(herdr.allowed),
                    "focused_pane_id": herdr.snapshot.get("focused_pane_id"),
                    "statuses": {str(p.get("pane_id")): p.get("agent_status")
                                 for p in herdr.snapshot.get("panes", []) if isinstance(p, dict)},
                    "names": dict(herdr.names),
                    "launches": {k: dict(v) for k, v in herdr.launches.items()},
                    "splits": [dict(record) for record in herdr.splits],
                    "starts": [dict(record) for record in herdr.starts],
                    "gets": [dict(record) for record in herdr.gets],
                    "closes": [dict(record) for record in herdr.closes],
                    "spaces": [dict(record) for record in herdr.spaces],
                    "worktrees": [dict(record) for record in herdr.worktrees],
                    "snapshot": copy.deepcopy(herdr.snapshot),
                }
        raise ValueError("unknown control command %r" % cmd)


def _input_problem(method, params):
    """What herdr 0.9.0 answers a malformed pane.send_keys / pane.send_input
    with, or None: `keys` is required for send_keys, every key must be one it
    knows (`invalid_key`), and `text`, when given, must be a string."""
    if not isinstance(params.get("pane_id"), str):
        return {"code": "invalid_request", "message": "invalid request: missing field `pane_id`"}
    keys = params.get("keys")
    if method == "pane.send_keys" and keys is None:
        return {"code": "invalid_request", "message": "invalid request: missing field `keys`"}
    if keys is not None and not (isinstance(keys, list) and all(isinstance(k, str) for k in keys)):
        return {"code": "invalid_request", "message": "invalid request: `keys` is not a list of strings"}
    for key in keys or []:
        if not _herdr_knows_key(key):
            return {"code": "invalid_key", "message": "unknown key `%s`" % key}
    text = params.get("text")
    if method == "pane.send_text" and text is None:
        return {"code": "invalid_request", "message": "invalid request: missing field `text`"}
    if text is not None and not isinstance(text, str):
        return {"code": "invalid_request", "message": "invalid request: `text` is not a string"}
    return None


def _herdr_knows_key(key):
    """herdr's key parser, as far as herdr 0.9.0 shows it: one character, a named
    key (any case), or a modifier chord like `C-c` or `ctrl+c`."""
    if len(key) == 1:
        return True
    lowered = key.lower()
    if lowered in NAMED_KEYS:
        return True
    for prefix in ("c-", "m-", "s-", "ctrl+", "alt+", "shift+", "meta+"):
        if lowered.startswith(prefix) and _herdr_knows_key(key[len(prefix):]):
            return True
    return False


def _envelope_problem(request):
    if not isinstance(request, dict):
        return "expected a JSON object"
    if not isinstance(request.get("id"), str):
        return "missing or non-string field `id`"
    if not isinstance(request.get("method"), str):
        return "missing field `method`"
    if not isinstance(request.get("params"), dict):
        return "missing field `params`"
    return None


def _read_line(conn):
    buffer = b""
    while b"\n" not in buffer:
        try:
            chunk = conn.recv(65536)
        except OSError:
            return None
        if not chunk:
            return None
        buffer += chunk
    return buffer.split(b"\n", 1)[0]


def _reply_and_close(conn, payload):
    _send_raw_and_close(conn, line(payload))


def _send_raw_and_close(conn, data):
    try:
        conn.sendall(data)
    except OSError:
        pass
    conn.close()


def _hang_up(conn):
    try:
        conn.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    conn.close()


def _flood(conn, size, lock=None):
    """Write `size` filler bytes, no newline, a chunk at a time; stop quietly
    once the client has hung up. The connection stays open either way."""
    chunk = b"x" * 1048576
    left = size
    while left > 0:
        piece = chunk[:min(left, len(chunk))]
        try:
            if lock is None:
                conn.sendall(piece)
            else:
                with lock:
                    conn.sendall(piece)
        except OSError:
            return
        left -= len(piece)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--socket", required=True)
    parser.add_argument("--control", required=True)
    parser.add_argument("--fixtures", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures"))
    parser.add_argument("--fixture", default="snapshot_basic")
    options = parser.parse_args()
    herdr = FakeHerdr(options.socket, options.fixtures)
    control = Control(herdr, options.control)
    # run_tests.sh stops the server with SIGTERM; still clean up the sockets.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    control.run("reset", {"fixture": options.fixture})
    try:
        control.serve()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        herdr.vanish()
        if os.path.exists(options.control):
            os.unlink(options.control)


if __name__ == "__main__":
    main()
