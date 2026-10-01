# herdr machines

A herdr machine is a saved SSH target (managed with `herdr machine add/list/...`; Herdstead only reads `list`).
Every machine is **a separate herdr server** with its own socket. Nothing remote is visible on the local socket, and
pane IDs are unique only within one server (two machines can both have `w1:p1`). So Herdstead aggregates them itself:

- Every 10 seconds it runs `herdr machine list --json` without blocking (`HERDR_BIN_PATH` first, otherwise `herdr`
  from PATH). Adding, removing, enabling / disabling, or changing a target or session takes effect in place; disabled
  machines are not shown. When `herdr` is missing or the command fails, only Local is shown and nothing floods the log.
  A list that succeeded before is kept, so an occasional failure does not drop every forward; but after the `herdr`
  binary is not found 3 times in a row, the list is dropped and only Local is shown. JSON numbers are read as numbers
  (`enabled: 1` means enabled, id `7` does not become `7.0`), and control characters are stripped from id / label.
  Output that is not JSON counts as one failure, and no fragment of it is written to the log
  (`HerdrClient.parse_line()`, never `JSON.parse_string`).
- Each enabled machine gets one `MachineLink` and one `HerdrClient`. First the remote shell runs
  `printf '\nHS_HOME=%s\nHS_END\n' "$HOME"` once to learn the remote home directory (`ssh -L` does not expand `~` on
  the remote side). Only the value between the **last** pair of `HS_HOME=` / `HS_END` markers is used, so motd, nvm
  and similar login-shell output does not matter. The home directory must be a single line of printable ASCII,
  start with `/`, be at most 256 characters, and contain neither `:` nor `$` (ssh splits `-L` on `:` and expands
  `${VAR}` in it **locally**; neither can be escaped). If it does not qualify, the machine stops and its name plate
  says why; it is not retried. `%` is escaped as `%%` (ssh also expands `%` tokens locally). From it the remote socket
  path is built (default session `$HOME/.config/herdr/herdr.sock`, named session
  `$HOME/.config/herdr/sessions/<name>/herdr.sock`; **the remote `XDG_CONFIG_HOME` is not consulted**), and then
  this runs for as long as the machine is enabled:
  `ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o StreamLocalBindUnlink=yes -L <local socket>:<remote socket> -- <target>`.
- The local socket is `hs-<Godot pid>-<n>.sock`, in a directory only this user can enter: `$TMPDIR` (per-user and
  0700 on macOS). If that is not private or the path is too long (macOS AF_UNIX allows about 104 bytes),
  `/tmp/hs-<uid>/` is used, created 0700; if it already exists its owner and mode are checked, and a mismatch is
  refused. An SSH machine's client connects only after its own ssh is forwarding, so it never connects to some other
  socket that happens to exist at that path.
- When ssh exits it is restarted with exponential backoff from 1 s to 60 s. When the scene exits or a machine is
  removed or disabled, ssh is killed and the local socket deleted. Each forward has an `hs-<pid>-<n>.pid` sidecar
  recording the ssh pid. If Godot is killed by SIGTERM / SIGKILL / Force Quit or crashes, there is no time to clean up,
  so the next start checks each set of files' owner pid. When that process is gone (or is this process's previous
  life, the pid reused), it first confirms with `ps` that the sidecar's pid really is an `-L` forward carrying this
  socket, only then sends it SIGTERM, and deletes the socket and sidecar. A live owner is left alone. A sidecar that is
  not JSON is deleted without reading a pid, and its content never reaches the log either.
- The target is passed to ssh as its own argv element after `--`, never spliced into a shell string. Targets that
  start with `-` or contain whitespace, control characters or invisible characters (NBSP, U+2028/2029, zero-width
  characters, etc.) are refused. The remote session follows herdr's own rule: only ASCII letters, digits, `.`, `_`,
  `-`, and never `.` or `..`. `ControlPath=none` disables shared-connection reuse, so killing this ssh really does end
  the forward.
- Remote snapshots are untrusted: on entering the office they get one shape cleanup (list elements that are not
  objects are dropped, fields are read as their expected type and a wrong type counts as missing, control characters
  are stripped from id / label), so one machine returning odd data cannot break the display of the others.

On screen: each machine is one open-plan map, every workspace a zone on it. The SPACES rail lists Local first,
then each machine under a heading with a mark for how it is answering; a heading click shows that machine's map (a
machine that never connected opens as an empty map that says why), a row pans to its zone, and a zone on another
machine shows that machine's map first. The machine plate names the machine (`@ name` once there is more than Local),
LIVE / OFFLINE / CONNECTING, the ssh error, and any zone its map cannot be laid out for. A disconnected machine only
greys out and freezes its own map (the plate stays readable); in the SPACES rail its section is dimmed, with no counts
and no lit windows, and everything else carries on. A machine that has never connected has an empty map (no zone), and its plate's note shows the full error. Status text is rewritten in place; a
disconnect and reconnect does not rebuild the picture. The top bar counters are fleet-wide totals; the MACHINES
counter shows live / total, turns the alarm colour while a machine is down, and its tooltip lists each machine with
its state, when it was last heard from and its error. The window title adds `N OFFLINE`, and the agent card adds an
`@ machine` line. Selection, click picking and attention timing are keyed by the composite `(machine, pane_id)`,
zones by `(machine, workspace_id)`, maps (their plan, world and pan) by the machine. With only Local, the SPACES rail has
no machine headings and the plate names the machine without `@`.

Prerequisites:

1. Passwordless SSH (public key or agent). BatchMode never prompts for a password; hosts that need a password or a
   second factor stay OFFLINE.
2. **Run `ssh <target>` by hand in a terminal once first** to accept the host key. Herdstead never adds
   `StrictHostKeyChecking=no`; an unknown host just fails, with the reason on the name plate.
3. herdr is installed on the remote host and the server for that session is running (`herdr machine add` itself
   prepares the remote side). If the remote socket does not exist, ssh keeps running and the name plate shows
   `channel ... open failed`; once the server is up, it connects on its own.
4. A .app launched from Finder does not get the shell's PATH: set `HERDR_BIN_PATH` or launch from a terminal,
   otherwise only Local is shown.

Debug back door (no ssh: an existing local socket is treated as a machine; repeatable):

```sh
godot --path . -- --machine-socket=build=/absolute/path/other-session/herdr.sock --machine-socket=gpu=/tmp/gpu.sock
godot --headless --path . --script tools/probe_herdr.gd -- --machines --machine-socket=build=/absolute/path/herdr.sock
```

`--socket=` still means Local only. The probe's `--machines` prints one
`MACHINE ... online=... workspaces=... panes=...` line per machine; its exit code still depends only on Local. Two
more environment variables exist for debugging and tests: `HERDSTEAD_SSH` replaces the ssh executable, and
`HERDSTEAD_SOCKET_DIR` sets the local socket directory (which is also the directory the startup cleanup scans). It is
a hook for tests, `make capture`, `make perf`, `make smoke` and debugging, and is used as given: no permission, owner
or path-length checks; whoever sets it is responsible. If the directory does not exist yet, the startup cleanup
neither creates it nor remembers the miss; the first forward creates it (0700).

**What has been verified**: machine-list parsing, argv construction, target / session / HOME validation,
failure → backoff → OFFLINE (a real `ssh localhost` failing on publickey), killing ssh and deleting the socket on exit,
reclaiming orphans on the next start after SIGTERM / SIGKILL (`tools/fake_ssh.py` posing as ssh with a local
forward), aggregating two fake machines, reconnecting after a single disconnect, and malformed snapshots.
**A real SSH connection reaching a remote herdr has not been verified end to end** (no test host was available).
`herdr machine list --json` on herdr 0.9.0 prints `[]` for an empty list, so the exact field names of a record have
not been seen. Parsing lives only in `MachineRoster.normalize()` and accepts the common spellings (`profile_id` / `id`,
`ssh_target` / `target`, `remote_session` / `session`, `label`, `enabled`).
