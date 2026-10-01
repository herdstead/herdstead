# The write boundary

Herdstead is an **operator** by default: it can act on herdr, but only through one write boundary,
`HerdrCommands` (`scripts/herdr_commands.gd`). Every other part of the office talks to herdr with the three
read-only requests `ping`, `session.snapshot` and `events.subscribe`. Started with `--read-only`, the office never
constructs `HerdrCommands` at all, so nothing in it can send more than those three.
This document is the contract of that boundary: what it may send, when, and how each write is checked.

Every fact about herdr below was measured against herdr 0.9.0 (protocol 22) unless it says otherwise.
Section 6 collects those measurements.

## 1. The write boundary

`HerdrCommands` is the only file under `scripts/` that may name a herdr method outside the read-only three.
`tools/test_commands.gd` checks this statically against the `allowlist` in `tools/fixtures/herdr_methods.json`,
which also records every method herdr 0.9.0 lists in its schema. The office talks to the rest of the system only
through `HerdrFleet`'s typed calls: a `CommandContext` in, a `CommandTicket` out (invariant 1 in `AGENTS.md`).

### Method allowlist

Twelve methods. "Reply cap" is the longest reply line the boundary reads before it gives up on the command;
"timeout" runs from queueing to a whole answer.

| Method | Used for | Payload and limits |
|---|---|---|
| `pane.read` | The agent card's terminal preview (not a write). | `{pane_id, source, format: "text", strip_ansi: true, lines}`. `source` is `detection` (a blocked agent: 200 lines, the whole question) or `recent_unwrapped` (anything else: 12 lines), `lines` 1–200. Reply cap 1 MiB, 5 s. `result.read.pane_id` must be the pane asked for. The decoded text keeps at most its last 64 KiB (`PaneReadResult`). |
| `pane.read` | The tooltip over a blocked seat's chip: the question excerpt (not a write, not a gesture). | As the card's `detection` read, 200 lines. When it runs: section 2. Never counts as a look. |
| `pane.read` | The terminal monitor's screen and local scrollback (not a write). | `{pane_id, source, format: "ansi", strip_ansi: false}`, `source` `visible` (no `lines`) or `recent` (`lines` 1–999). Reply cap 1 MiB, 5 s. `format` in the result must be `ansi`. The result (`ScreenReadResult`) keeps ESC, CR, LF and TAB, drops every other control and the bidi controls, and keeps at most its last 256 KiB. |
| `pane.focus` | **Switch herdr here** (on the card and in the monitor's title bar). | `{pane_id}` only. Any result object counts as accepted. Reply cap 4 KiB, 5 s. |
| `pane.send_keys` | Answer mode's approval keys (section 2). | `{pane_id, keys: [one key]}`. The key is compared exactly against `1`–`9`, `y`, `n`, `enter`, `esc`; `esc` only from the named **Send Esc** button. Only to a blocked agent. Reply cap 4 KiB, 5 s. |
| `pane.send_keys` | Raw mode's keys (section 3). | `{pane_id, keys: [...]}`, every name from the raw key table (`HerdrCommands.raw_key_refusal()`), at most 256 per request. Reply cap 4 KiB, 5 s. |
| `pane.send_text` | Raw mode's typed text and input-method commits. | `{pane_id, text}`, never bracketed; at most 4096 UTF-8 bytes, no control or broken character (section 3). Reply cap 4 KiB, 5 s. |
| `pane.send_input` | Raw mode's paste, and nothing else. | `{pane_id, text}`, no `keys`; at most 64 KiB, refused whole, never cut (section 3). Reply cap 4 KiB, 5 s. |
| `agent.prompt` | Answer mode's one-line reply. | `{target: <herdr's spelling of the pane id>, text}` only: no `wait`, no `keys` (herdr types Enter itself). Only to an idle or done agent not launching; the line as rule 6 says. Reply cap 4 KiB, 5 s. |
| `agent.start` | **Start agent** in a shell (section 4). | `{name, kind, pane_id}` only: no `args`, no `timeout_ms`. Kind seen on the snapshot, name `<kind>-<n>` made by the office, both `^[a-z][a-z0-9_-]{0,31}$`. Only after a re-read that ends at a prompt. Reply cap 4 KiB, 5 s. |
| `pane.split` | **New pane** beside an agent (section 4). | `{target_pane_id, direction: right \| down, focus: false}`, all three always; no `cwd`, `ratio`, `env`, `workspace_id`. At least 40 columns or 10 rows a side. Reply cap 4 KiB, 5 s. |
| `agent.get` | Settling a start this run sent, at its deadline (a read). | `{target: <herdr's spelling of the pane id>}` only. At most once per start, only from the start's own watch (rule 2). Reply cap 4 KiB, 5 s. |
| `pane.close` | **Close** (section 5). | `{pane_id}` only, after two real clicks. Any result object counts as accepted. Reply cap 4 KiB, 5 s. |
| `workspace.create` | **New space** (section 5). | `{cwd, focus: false}` only; `cwd` is the pane's directory exactly as the snapshot carries it, absolute. Reply cap 16 KiB, 5 s. |
| `worktree.create` | **Worktree** (section 5). | `{workspace_id, branch, label: <branch>, focus: false}`, all four always; no `path`, `base`, `cwd`, `trust_repository`. The branch as `branch_refusal()` passes it, never rewritten. Reply cap 16 KiB, **30 s** (herdr runs git first). |

Not on the list: creating, renaming or closing tabs; renaming or closing workspaces; `worktree.remove`; plugins,
server, layout, notification and graphics methods. Of `agent.*`, only `prompt`, `start` and the read `get`.
`pane.send_input` is never used to send a line and Enter, and never as a fallback when `agent.prompt` is refused:
a second write after a refusal would be a write with no gesture of its own (rule 2) and a retry (rule 4).

**What `pane.focus` does.** It changes herdr's *shared* selection: every attached client follows it to that
workspace, tab and pane, and so does herdr with no client attached. On a remote machine it moves that machine's
view. It activates no local window. It also marks the **whole tab** seen: every `done` pane of that tab turns
`idle`, not just the one on the card. So the button is called **Switch herdr here** (**Switch herdr on
<machine>** with several machines), says `Clears tab's UNREAD` under it, and its tooltip spells out both side
effects. It is never called "mark read" or "open in terminal". `tools/fake_herdr.py` models the whole-tab effect.

### Rules

1. **Every write goes through `HerdrCommands`.** It speaks herdr's socket API, one connection per request, to
   the machine the command names; an SSH machine is reached through its forwarded socket. herdr's CLI is never
   used to write (the only CLI call the office makes is `herdr machine list --json`). The HUD and the world never
   hold a client, link, roster or command object. A command never goes through `HerdrClient`'s request list:
   a failed command ends its own ticket and never takes the machine offline.

2. **Only a present user gesture writes.** Refreshes, timers, snapshot changes, status events and the event
   stream never produce a write, and nothing sent is ever derived from remote text: there is no auto-approval.
   Every card write comes from a mouse click on the staff panel (aimed at the press, sent at the release) or,
   for answer keys, a key press in answer mode (section 2). One gesture is one write: **New pane** and **Start
   agent** are two gestures with two tickets, never a chained write.
   The one exception is a read: when a start this run sent reaches its deadline (`LaunchWatch.TIMEOUT_MSEC`,
   31 s) and the current snapshot still shows that launch pending in the same terminal under the same name, the
   boundary sends **one** `agent.get`. It writes nothing to the terminal, marks nothing seen, moves no focus and
   changes no state, but it makes herdr settle its own expired launch timeout (herdr settles it only when asked;
   section 6), which frees the pane and the name. At most once per start, never asked again, and its answer only
   feeds the card's footer: no write ever follows from it. A launch another client started is never asked about.
   After an accepted start, an accepted close, space or worktree, and when that check ends, the boundary asks
   the machine's client for a `session.snapshot` at once (`snapshot_wanted`): one of the three reads, not an
   exception.
   Raw mode (section 3): every key event and paste the monitor takes while it has the keyboard is itself a gesture.

3. **The command context is immutable.** The gesture creates one typed `CommandContext` and every later stage
   checks that same object; nothing re-reads "what is selected now" to find the target. It fixes:
   the machine key and its **generation**; the composite pane key (`HerdrFleet.pane_key`); the pane id as herdr
   spelled it and as the office cleaned it; `PaneModel.identity_key()` (terminal, agent and session); the
   terminal id; the card's binding version; and the payload. The generation comes from one fleet-wide increasing
   counter, renewed when a machine opens and on each `connected` of its own client, so a replaced, re-enabled or
   reconnected machine never matches a context aimed before. If the two spellings of the pane id differ, or
   either is listed twice, the command is refused (`WIRE_ID_MISMATCH`, `WIRE_ID_DUPLICATE`).
   A machine that is replaced, drops, has no current snapshot yet (`online` is not the same as fresh), or a pane
   whose terminal id is unknown, refuses every unsent command and cancels every open confirm; nothing queued is
   restored after a reconnect.
   The card's pick carries identity too: when a new terminal takes the pane id, the buttons stay off and the card
   says `New terminal: pick again` until the viewer picks the station again.
   **Switch herdr here**, answer keys, a line, **Start agent**, **New pane**, **Close**, **New space** and
   **Worktree** bind the whole identity. The monitor's raw input and screen reads, and the launch check, bind the
   **terminal id** only: another agent or session in the same terminal (`/clear`, an agent started in a shell)
   is still the same target. In raw mode this means typeahead queued behind a hung request can land in a program
   that took the terminal over meanwhile, exactly as in a real terminal; that is accepted by design (section 3).
   Section 4 covers the two places the office extends a pick on its own: after its own start, and onto a pane its
   split made. Both only select; neither writes.

4. **Command states.** `UNSENT` (queued, no byte written), `SENT` (from the first byte of the write), `ACCEPTED`
   (herdr answered with a result), `REJECTED` (herdr answered with an error), `UNKNOWN` (sent, then timed out,
   dropped, cut mid-reply, over its reply cap, unreadable, or its machine went away: herdr may have acted),
   `CANCELLED` (not one byte written: the socket was not there, or the machine closed, dropped or was replaced
   first) and `REFUSED` (refused before anything was written, with a typed `CommandRefusal` reason). Cancelled and
   rejected are kept apart: the first means nothing happened and clicking again is safe, the second is herdr's
   answer. herdr's error code is compared exactly against the codes `CommandRejection` knows (anything else is
   `OTHER`); its message is remote text, cleaned, every grapheme cluster bounded, at most 200 characters.
   **A write is never retried**, whatever state it ends in. Each pane has at most one write open (single-flight);
   a second press meanwhile is refused `IN_FLIGHT`. A lost answer reads "result unknown" on screen, and the viewer
   has to look at the new state and gesture again.
   An accepted `agent.start` only means herdr began typing into the shell; how the start goes is read from
   snapshots alone (section 4).
   Raw mode (section 3): input behind an open request waits in its pane's queue instead of being refused, and a
   lost answer does not stop the keys after it.

5. **The re-read before a send is best effort.** herdr has no "send only if the screen still reads so", and
   `revision` in a read is always 0. So an input command (answer key, line, start) is one ticket for two
   requests. At the press the card freezes the preview it shows (`CommandPreview`: cleaned text, source, line
   count, byte count, cut flag, read sequence, binding, pane key and identity); if the card shows another read by
   the release, nothing is sent. The same ticket takes the pane's single-flight slot at the gesture, then reads
   the same source with the same line count again. In the frame that re-read returns, every check runs once more
   against what the fleet knows then (`refusal()`), the slot must still be this ticket's, the re-read must not be
   cut, and its cleaned text and byte count must equal the frozen ones; only then is the write opened and started
   in that same frame. Otherwise it ends `REFUSED` (`SCREEN_CHANGED`, `SCREEN_CUT`, `RECHECK_FAILED`, or the
   reason found) and nothing is written.
   Answer keys are checked against the whole `detection` text (200 lines; herdr keeps at least 24), though the
   card shows only its last 12 rows and says how many it shows and whether any were cut. A line and a start are
   checked against `recent_unwrapped`.
   This narrows the window between seeing and sending to about two round trips; it never closes it. After the
   re-read and before delivery the question can still change into another one that ends the same way. Neither the
   interface nor any document may claim "only approves the question you saw". Likewise, when an agent has exited
   and herdr has not yet reported the pane as a shell, the re-read and every check still treat it as an agent, and
   a line could land in the shell: a known limit.
   **Write-then-look.** When a write that got past the gesture's checks ends, whatever its outcome (accepted,
   rejected, unknown, cancelled, or refused after its re-read), every write to that pane stays off
   (`LOOK_FIRST`) until a preview read *asked for* at least 0.5 s (`LOOK_DELAY_MSEC`) after that end has come back
   and been shown. A write refused at the gesture touched nothing and owes no look. The owed look is kept per
   **pane key**, not per identity: the write may be what changed the agent session (`/clear`), and it is owed all
   the same; leaving and coming back does not clear it. The last 256 panes are remembered. This applies to every
   write except raw input: **Switch herdr here**, **New pane**, **Close**, **New space** and **Worktree** wait for
   the look too. A read shown by the terminal monitor counts as a look; a chip's question read never does.
   Writes that do not type into a terminal (switch, split, close, space, worktree) have no re-read: they are
   checked at the release against the latest fleet facts and written on the next frame.
   Raw mode (section 3) does no re-read and no write-then-look between its own writes; section 3 revises this
   rule for that path. The start's own prompt check is in section 4.

6. **Input is validated in the sending direction, and refused, never rewritten.** What the viewer typed is sent
   exactly or not at all; the refusal says why.
   An answer key is compared exactly against `1`–`9`, `y`, `n`, `enter`, `esc` (`Y`, `Enter`, `escape`, `C-c`,
   `ctrl+c` are all refused); herdr itself takes far more keys, so this list is the only guard. Answer keys go
   only to an agent herdr reports blocked (`NOT_ASKING` otherwise), including one still launching.
   A line (`HerdrCommands.line_refusal()`) is refused when blank or only whitespace (`LINE_BLANK`), over 1024
   UTF-8 bytes (`LINE_TOO_LONG`), holding a control character (C0 including tab, CR, LF and ESC; DEL; C1;
   U+2028; U+2029: `LINE_CONTROL`), an invisible or direction-changing character (U+00AD, U+034F, U+061C,
   U+115F, U+1160, U+17B4, U+17B5, U+180B–U+180F, U+200B–U+200F, U+202A–U+202E, U+2060–U+206F, U+3164,
   U+FEFF, U+FFA0, U+FFF9–U+FFFB, U+E0000–U+E007F: `LINE_INVISIBLE`), or a broken one (U+FFFD, a lone surrogate,
   a noncharacter, past U+10FFFF: `LINE_BROKEN`). A line goes only to an agent (`NOT_AN_AGENT` for a shell: text
   there runs as a command) that is idle or done: not launching (`AGENT_STARTING`), not blocked (`AGENT_ASKING`:
   its Enter could confirm a dialog's default), not working or unknown (`AGENT_BUSY`). herdr's own `agent.prompt`
   checks (it refuses a blocked agent, an empty text and a non-agent pane, but types into a working agent and
   passes newlines, escapes and direction overrides through) replace none of these.
   "idle" does not mean "ready for a new task" (herdr's own documentation says an unrecognised approval prompt may
   show as idle), so the reply is described as "send one line of text to this terminal" and needs a preview seen.
   Raw mode (section 3) replaces the answer-key list with its raw key table, allows any pane in any state, and
   validates typed text and pastes by its own rules. Starts, splits, closes, spaces and worktrees have their own
   payload checks (sections 4 and 5).

7. **The read-only gate is in the transport.** `--read-only` is decided in `HerdrFleet.start()` before any
   client starts; such a fleet never constructs `HerdrCommands`, and the card, the monitor and NEXT offer no
   write. The flag counts before or after `--`. Any argument that starts with a run of dashes (the ASCII hyphen,
   the Unicode hyphens and dashes including en and em dash, the minus sign, the small and full-width hyphen-minus)
   followed by `read` in any case, and is not exactly `--read-only`, stops the office with `ARGS_ERROR:` and exit
   code 2: whether the office may write is never guessed.
   At the send port the boundary checks again: the machine's announced protocol must be one it was verified
   against (`PROTOCOLS`, today `[22]`). An unknown protocol refuses commands to **that machine only**
   (`UNKNOWN_PROTOCOL`); other machines go on, and the office as a whole does not fall back to read-only.
   The test server refuses every write by default, and a separate gate checks that a read-only office ends with
   no write sent (see Gates).

8. **Replies are bounded before they are parsed.** Every command has its own connection, reply cap and timeout
   (the allowlist table). A reply over its cap fails that command as `UNKNOWN` (never as an empty result); a
   failure ends that ticket only and never changes the machine's online state. A reply must carry the request's
   own id. A preview records its source, line count, binding, read sequence and truncation flags (herdr's
   `truncated`, and the office's own cut when the decoded text is over 64 KiB and only its tail is kept); responses
   that arrive late or belong to an old binding are dropped, and a cut preview is never the basis of a send.

9. **Audit.** Every command, refused ones included, gets an entry in one of two bounded in-memory rings: 64 writes
   and 64 reads, apart, so the card's frequent reads never push a write out. An entry is keyed by machine,
   generation and request id and records the time, the method, a one-line summary and every state change with its
   time. It holds only the office's own spelling (the cleaned pane id and the composite key), never herdr's raw id,
   and never terminal text or herdr's free text. What each kind keeps: a read, its source, line count, byte count
   and the two truncation flags; an answer key, its name; a line, its byte count (never the text), and for every
   input command the re-read's byte count and whether it matched; raw input, its category (`keys`, `text` or
   `paste`), event count and byte count, never a key name or a character; a start, the kind and the name the
   office made; a split, its direction; a close, its scope kind and the pane's state word; a new space, the byte
   count of the directory; a worktree, the branch name. Never a path, a label or git's text. The audit is not
   written to disk and not shown; `HerdrFleet.write_log()` and `read_log()` expose it.

10. **Encoding and parsing.** Every request is encoded by `HerdrClient.request_line()` through `JsonText`
    (`scripts/json_text.gd`), which writes every control character and DEL as `\u00XX`. Godot's
    `JSON.stringify()` leaves them raw and writes 0x0B as `\v`, which is not JSON: a pane id holding one made
    herdr refuse the subscription, and the machine stayed offline for good. Every line from herdr is parsed by
    `HerdrClient.parse_line()`, which never echoes an unreadable line (possibly terminal text) into the log.
    `MachineRoster.clean_text()` also strips the bidi controls (U+202A–U+202E, U+2066–U+2069), so an id holding
    them no longer matches herdr's spelling and every command to it is refused.

### Gates

Every gate starts from real input events (`Input.parse_input_event` and physics frames, never a direct call to a
handler) and asserts the exact request sequence and the outcome.

- Zero gestures, zero writes: many refreshes, state changes, event streams and timers send nothing.
- `--read-only` sends nothing but the three reads, and the monitor and the card offer nothing.
- A change of target, a replaced machine, a missing identity, or a machine `online` without a current snapshot
  refuses or cancels what was aimed.
- A screen that changes between the press and the re-read writes nothing. The same text A → B → A (a question
  swapped for another that reads the same) is a regression case for the known residual risk: it asserts the
  interface still says the send is best effort.
- Key echo, a long press and a double click send at most once.
- A drop before the send cancels; a lost reply after the send is `UNKNOWN` and is not retried.
- `pane.focus` clears the whole tab's UNREAD (the fake models it).
- Keys outside the list, control bytes and over-long text are refused.
- Every write the allowlist adds has its own cases: real input, zero gestures zero writes, each refusal, a lost
  answer never retried.
- The test server (`tools/fake_herdr.py`) answers only the three reads by default and records anything else as a
  violation. A write suite runs against two fakes of its own; every case `reset`s them, `allow`s exactly the
  methods it needs, and ends by checking that each fake received only what was opened. The fake can drop the
  answer after acting, delay, reorder and disconnect mid-reply. Every suite that builds an office without opening
  a write runs `--read-only` (`tools/run_tests.sh`).
- The write suites are listed in `AGENTS.md` ("Tests"); `tools/test_commands.gd` also holds the static method check.

## 2. Answer mode

The agent card (the staff panel's `inspector`) is the one place a pane is answered from outside the monitor.

**The preview.** The card reads its pane only while the card is visible and opened (the one-line panel shows no
preview and counts as covered), not covered by the terminal monitor, the window is not minimized, and the machine is online with a current snapshot. It reads when it opens
and when the state changes, one read at a time, the next starting 1 s after the last one ended for a blocked pane
and 3 s for any other. It stops on hiding, covering, minimizing, a drop or another binding; a response that comes
late or belongs to an old binding is dropped. A blocked pane shows `detection` (200 lines asked, the last 12
shown); any other shows the last 12 rows of `recent_unwrapped`. The preview is 12 fixed monospace rows, long rows
clipped, never wrapped. Its caption says the source, the age and whether it was cut (`detection · 3s ago · cut`);
it says why it cannot read (`No preview: offline`) or that a read failed (`Read failed: …`). With `--read-only`
or with no fleet, it says so and no action is offered.

**Switch herdr here.** One click on a station the viewer picked, still holding the terminal they picked; aimed at
the press, sent at the release. Its result line says `herdr switched here`, `herdr refused (code)`,
`Not sent: <reason>` or `Unknown result: look first`; a card following herdr's own focus says
`Following herdr's focus`, and one whose pane id now holds another terminal says `New terminal: pick again`.
The same button sits in the monitor's title bar.

**Entering and leaving.** Answer mode exists only for a station the viewer picked, on an agent, on an operator
card. Enter (or keypad Enter; never `ui_accept`, which includes Space), the heading's `Answer` chip or a click on
the seat's chip opens it. That Enter is consumed and sends nothing: **Enter on the keyboard never sends**, so
pressing it twice cannot confirm a dialog's default. `Esc` is always local: it leaves answer mode and leaves the
panel open; it is never sent to the terminal. A remote Esc is only the named **Send Esc** button. Picking another
station, rebinding the card, opening the terminal monitor, or giving the keyboard to the agent list (`A`) leaves
answer mode and releases the keyboard focus. OVERVIEW does not: the staff panel answers as usual while it is open.
Every answer that reached herdr (accepted, rejected or unknown) ends answer mode; one refused before any write
leaves it open and says why.

**Answer keys.** Buttons `1`–`9`, `y`, `n`, `⏎` and **Send Esc** send those keys (`enter` and `esc` by name). The
keyboard in answer mode sends only `1`–`9` and `y`, and only when the key position (`physical_keycode`, the
InputMap action) *and* the layout's key (`keycode`) both are that key; `event.unicode` is never used. With only the
position, the AZERTY key at the US `6` (unshifted `-`, the office's zoom out) would send "6", and the QWERTZ key
labelled Z at the US `y` would send "y". So a layout with no unshifted digit sends no digit from the keyboard; the
buttons still do. `n`, `⏎` and **Send Esc** are buttons only. `N` in answer mode leaves it and jumps to the next
agent: "next" never becomes "no". Key echo is ignored and, with single-flight, a long press or a double click
sends at most once. Buttons never take keyboard focus (`focus_mode = NONE`), so Tab cannot reach them. Outside
answer mode, with the reply box unfocused, the card eats no office key. Which keys are offered never depends on
the terminal's text. Answer keys go to a blocked agent even while herdr still reports it launching (a trust
prompt on first start); a line does not.

**The one line.** While the reply box has focus every key is typing; Tab does not move on, and neither Enter
nor an input method's composing Enter sends. **Send line** is aimed at its press and sent at its release, through
`agent.prompt`. It is refused if an input method is still composing at the press or the release
(`LINE_COMPOSING`), or if the box no longer holds the line aimed at the press (`LINE_EDITED`). Drafts are kept per
pane key and identity, in memory only (at most 32), and never follow the card to another station. A sent line's
note says `herdr typed the line and Enter; not whether the agent acted.` herdr's refusals are shown in its terms
(`herdr refused: blocked: use the keys`, `no agent here`, `still starting`).

**Chip reads.** The hover tooltip over a blocked seat's chip shows an excerpt of the question
(`OfficeQuestionReader`, `scripts/question_reader.gd`). It is not a gesture and never writes. It reads only
blocked panes (a launching one that asks too) on the map shown whose chip is on screen, on a live machine
with a current snapshot, while neither the monitor nor OVERVIEW covers the world and the window is not minimized;
never in `--read-only`. One read at a time for the whole office; no pane is read again sooner than 10 s after its
last read began, and that is not reset by leaving blocked or switching maps. It never calls `preview_shown`, so
it never counts as a look and never turns writes back on.

**Clicks that only navigate.** A click on a SPACES heading (show that machine's map), on a SPACES row (pan to its
zone) and on an edge arrow (pan to its desk, selecting nothing) are navigation, like the clicks in NEWS, EVENTS and
OVERVIEW that only select a pane: none of them is a write gesture, and none sends a write. (A click that selects a
pane while the card is expanded still schedules the card's preview read of it, a read, as a list click does.)

## 3. Raw mode

The terminal monitor (`scripts/ui/terminal_monitor.gd`) shows one pane's terminal near full screen and, while it
has the keyboard, sends every key to it. This section revises section 1 for that path only: rules 3, 4, 5 and 6
apply as written here. Answer mode (section 2) and every card write are unchanged.

**Opening and aiming.** `M` or the card's `Monitor ⤢` opens it on the pane shown; one monitor at a time. What it
is aimed at is fixed when it opens (or when **Follow new terminal** is clicked): the machine and its generation,
the pane key, and the **terminal id**. It binds the terminal only, not the agent or session: starting an agent in
a shell, or `/clear`, does not stop input. Every raw input is checked against the latest fleet facts at the
gesture and again right before it is written (`refusal()`): machine, generation, online, current snapshot,
protocol, pane, wire id and terminal.

**Reading.** Only while the monitor is open, its machine online with a current snapshot, and the window not
minimized: every 0.2 s (5 Hz) while the window has focus, every 1 s without it, plus one read at once and one
50 ms later after each input request, so the echo shows without waiting for the next tick; never sooner than
4 times what the last parse and draw took. At most one read is out; a change is found by comparing text. The
mouse wheel scrolls a local view of `recent` (at most 999 lines, read once when the wheel first turns up); any
key returns to the live screen; herdr's own scroll position is never touched (no `pane.scroll`). The grid draws at
most 400 × 200 cells and says so when it clips; every grapheme cluster is bounded to 8 code points. There is no
cursor (herdr does not report one) and no mouse input. Reads and polling never write.

**What a gesture is.** Every key event and every paste the monitor takes while it has the keyboard is a gesture
of its own. There is no answer-key list (the raw key table below is the guard), any pane may receive input (a
shell too) in any state, and there is no re-read and no write-then-look between raw writes: the viewer is
watching a live screen, and the staleness window is one polling interval. Writes still come only from gestures,
still go through `HerdrCommands`, and still have their own connection, caps and timeouts.

**Keys** (`TerminalKeys` maps the event; `HerdrCommands.raw_key_refusal()` checks every name again at the send port):

| Sent as | Keys |
|---|---|
| Text (`pane.send_text`) | Any printable character, as the keyboard layout made it (an AZERTY `a` is `a`), plain or with Shift; Space; an input method's commit. |
| Named keys (`pane.send_keys`) | `enter`, `tab`, `shift+tab`, `backspace`, `esc`, `space`, `up`, `down`, `left`, `right`, `f1`–`f12`; `shift+enter`, `ctrl+enter`, `alt+enter`, `ctrl+space`. |
| Arrow chords | `ctrl+`, `alt+`, `shift+`, `ctrl+shift+` with an arrow. |
| Ctrl chords | `ctrl+<letter>`, `ctrl+[`, `ctrl+\`, `ctrl+]`, `ctrl+^`, `ctrl+_`, `ctrl+@` (Ctrl+6 and Ctrl+2 give `^` and `@`, Ctrl+- gives `_`); `ctrl+alt+<letter>`. |
| Alt chords | `alt+<printable character>` except capitals; `alt+shift+<letter>`. |
| Refused, with a reason | Home, End, PgUp, PgDn, Insert, Delete (and the keypad's with Num Lock off): `KEY_UNREACHABLE`, herdr 0.9.0 has no name for them. Cmd chords, F keys with a modifier, F13 and up, Ctrl+Shift+letter, and any other chord outside the table: `KEY_UNSUPPORTED`. |

On macOS, Option with a key that makes a character types that character (German Option+L is `@`), as Terminal.app
and iTerm2 do by default; an Option chord that makes no character yet (a dead key) sends nothing, and the composed
character follows as text. Elsewhere Alt is always `alt+`. Key repeats are sent like presses: a terminal repeats a
held key. Esc goes to the terminal. Ctrl+] closes the monitor and is never sent; the paste chord (Cmd+V on macOS,
Ctrl+Shift+V elsewhere) pastes. No office key fires while the monitor is open. The six unreachable keys are not
emulated with raw escape sequences.

**Typed text** (`HerdrCommands.text_refusal()`): sent exactly, never bracketed. Refused if empty
(`INPUT_EMPTY`), over 4096 UTF-8 bytes in one request (`TEXT_TOO_LONG`), holding a control character (C0, DEL,
C1: those go as named keys; `TEXT_CONTROL`) or a broken one (`TEXT_BROKEN`).

**Paste** (`HerdrCommands.paste_refusal()`): `pane.send_input {pane_id, text}`, which herdr brackets when the
program asked for bracketed paste. Refused whole, never cut or rewritten, if empty, over 64 KiB
(`PASTE_TOO_LONG`), holding ESC or a C1 control (either can end the bracketed paste early and run the rest as
typed input: `PASTE_ESCAPE`), a broken character, any other control a terminal acts on without bracketed paste
(C0 except tab, newline and carriage return; DEL; U+2028; U+2029: `PASTE_CONTROL`), or a direction control
(U+061C, U+200E, U+200F, U+202A–U+202E, U+2066–U+2069: `PASTE_INVISIBLE`, since what the viewer sees would not be
what the shell reads). Newlines and tabs are pasted as they are; zero-width joiners stay (emoji need them).

**Batching, order and pace.** One frame's input becomes one request per run of the same kind (keys or text), in
order. Each pane has its own queue: one request open at a time, the next only when it is over, and no sooner than
17 ms after the previous one started (about 60 requests a second). The queue holds at most 256 events (one per
key, one per typed character, one per paste) besides the request open; the newest input over that is refused
`QUEUE_FULL`, and nothing queued is dropped. A lost answer is `UNKNOWN`, never resent, and what comes after still
goes. When an input's turn comes and it can no longer be written (machine offline, stale, replaced, unknown
protocol, pane gone, terminal changed), it is refused with that reason, and so is everything queued behind it
aimed alike (same generation and terminal); input aimed at the pane's new terminal is judged on its own. A machine
that drops, closes or is replaced refuses its panes' queues with that reason; none of it is kept for a reconnect.
Closing the monitor cancels everything still queued (`CANCELLED`, never sent); the request already on the wire ends
as it ends.

**Terminal changes and drops.** When the pane's terminal id changes or the pane closes, input stops and the status
line says so; it resumes only after **Follow new terminal** or a reopen, and only once a read of the new terminal
is on screen. A machine that drops freezes the last screen, dimmed, marked OFFLINE (invariant 4); when it is back
with the same terminal, input returns once a fresh read is shown. Typeahead queued behind a hung request can land
in a program that took the same terminal over meanwhile (a shell command ended and an agent started), as in a real
terminal: accepted by design. New keys after it are gestures against what is on screen.

**With the other writes.** A raw write occupies the pane's single-flight slot like any write, so a card write
while raw input is queued or open is refused `IN_FLIGHT`. A raw write that ended leaves a look owed for the card's
writes (rule 5), and the monitor's own screen reads count as that look.

**Read-only.** With `--read-only` there is no boundary: the monitor opens, reads nothing, sends nothing, and shows
only its title and a line saying so.

**Audit.** Category, event count and byte count only; never a key name, never a character (rule 9).

## 4. Start agent and New pane

Both are mouse clicks on the staff panel's `%Launch` block (`LaunchBlock`, `scripts/ui/launch_block.gd`), aimed at
the press and sent at the release. No key ever starts an agent or splits a pane.

### Start agent

**Where.** Beside the preview of a shell station the viewer picked: the START AGENT block, one button per agent
kind this machine's current snapshot shows detected (up to 8 buttons; the label is the kind in capitals), with the
note `Types the kind + Enter in this terminal`. With no kind seen: `No agent kind seen on <machine> yet: start one
in herdr first`. Kinds come only from the snapshot (`server.agent_manifests` lists detection manifests, not what
is installed).

**What it sends.** `agent.start {name, kind, pane_id}`. herdr types the kind's command and Enter into that shell.
The name is `<kind>-<n>`, the lowest `n` from 1 that no agent on the snapshot holds and no start this run sent to
that machine used (a lost answer's name too, since herdr may hold it), except a start herdr gave up at its deadline
(`LaunchWatch.failed()`: herdr freed that name); after 999 tries there is no name. Kind and name must match
`^[a-z][a-z0-9_-]{0,31}$` whole (`KIND_INVALID`, `NAME_INVALID`).

**Refused** when the pane runs an agent (`NOT_A_SHELL`), is launching (`AGENT_STARTING`), the kind is not on the
snapshot (`KIND_UNKNOWN`), the name is on the snapshot (`NAME_TAKEN`), a start this run sent to the same pane ended
less than 5 s ago (`AGENT_STARTING`: one snapshot interval, before which no snapshot may show it; herdr would answer
`agent_pane_busy`), or the name is one this run already sent to that machine (`NAME_TAKEN`).

**Same discipline as a line** (rules 3 and 5): the whole identity, the preview frozen at the press, the slot
taken at the gesture, the `recent_unwrapped` re-read compared exactly, every check again against the latest facts,
single-flight, write-then-look.

**The prompt check** (`PromptState`). herdr types after whatever is on the shell's last line and does not clear it
(a half-typed `echo PARTIAL` ran as `echo PARTIALmaki`). So the office looks at the last non-blank line of the
frozen `recent_unwrapped` text, trailing blanks removed:

- **PLAIN**: it ends in one of `$ % > # ❯ ➜ λ »`. One click sends.
- **UNSURE**: it ends in anything else (many prompt themes do, and so does a half-typed line). The first click
  only arms a confirm that shows the line as it reads (`Start anyway? Types "claude" + Enter after:`); a second
  real click on the **same kind** within 10 s, on the same binding and the same preview text, sends. Another screen,
  another pick, another binding or the timeout cancels it. Arming it clears a close confirm, and the other way round.
- **NO_PROMPT**: no non-blank line, a cut preview, no read, or another source. Nothing is sent, confirmed or not.

The confirm is the card's gesture constraint only: the boundary cannot tell a second click from a caller passing
`confirmed`, so it re-reads, compares and judges the prompt again regardless, and never sends after NO_PROMPT.
The check is best effort: a half-typed line ending in `$ % > #` (`echo $`, `2>`, `100%`) reads PLAIN; the
cursor position is not in the read; a line of only spaces reads as nothing (herdr trims trailing spaces, and
spaces are harmless); the viewer can type between the read and the write. So the button and its note always say
the kind and Enter will be typed into this terminal.

**After it is sent.** `ACCEPTED` only means herdr began typing. Accepted or `UNKNOWN`, the start is remembered
(`LaunchWatch`, at most 64) and the machine's client fetches a snapshot at once, since herdr sends no event until
it recognises the agent. How it goes is read from snapshots only (`LaunchWatch.judge()`, pure, never writes) and
said in the card's footer:

| Outcome | When | Footer |
|---|---|---|
| PENDING | Still launching, or no snapshot shows it yet. | `Starting claude-2 · 4s` |
| READY | No longer launching, and the agent is recognised or `interactive_ready` under this name. | `claude-2 started` |
| BLOCKED_AT_START | Still launching and already blocked (a trust prompt). Answer with the keys. | `claude-2 asks: answer with the keys` |
| REPLACED | Another terminal, or another agent or name, holds the pane. | `Terminal changed` |
| GONE | The pane is gone. | `Pane gone` |
| NOT_DETECTED | Past the deadline, still launching (the check said so, or none was needed yet). | `claude-2 not detected after 31s: look at the terminal` |
| FAILED | The deadline check got `agent_not_found`: herdr gave up, the pane is a shell again. Wins over an agent started by hand afterwards. | `claude-2 did not start: look at the terminal` |
| UNKNOWN | The deadline check got no usable answer. | `claude-2: no answer from herdr` |
| NOT_CHECKED | At the deadline the machine was gone or replaced: nothing was asked. | `claude-2 not checked: the connection changed` |

The deadline is 31 s from the press, just after herdr's own launch timeout (about 30.4 s), so the one `agent.get`
(rule 2) is what makes herdr settle it. It is sent only if the snapshot at that moment still shows the same pane,
terminal and name launching; a machine that is merely offline is waited for; a gone or replaced one is not asked.
No outcome is ever retried or re-sent under another name. A launch another client left pending is drawn as
starting like any other, and never asked about.

**The pick follows the start.** A start makes the pane's identity change a few times within seconds (herdr
recognises the agent, then its first session appears). The office carries the viewer's pick across exactly that
(`_carry_pick_to_started()` in `scripts/office.gd`): while this start is still the pane's last write, in the same
terminal, of the same kind, under this start's name (the first step may still have no name), and while the step
before had no session yet. Anything after that (a `/clear`, another kind, any later write to it) is a new identity
and the card says `New terminal: pick again`. A launching agent that is blocked counts as blocked everywhere (the
counter, NEXT, its chip), and its keys are open; a line is not.

### New pane

**Where.** Beside the preview of an agent station the viewer picked (not one that is launching): the block reads
`NEW PANE BESIDE <PROVIDER>`, with one button, `New pane →` or `New pane ↓`, and the note
`Splits a new pane next to <pane>`.

**What it sends.** `pane.split {target_pane_id, direction, focus: false}`: all three always, since without a
target herdr splits its shared focus and `focus: true` would move it. No `cwd`: the new pane starts where the old
one's shell is.

**The side** (`HerdrCommands.split_choice()`), from the pane's rect in the snapshot's layout, `width` × `height`
cells: `right` when the pane is at least twice as wide as high and at least 80 columns wide, or when it is under
20 rows high but at least 80 columns wide; else `down` when it is at least 20 rows high; else refused
`PANE_TOO_SMALL`. Each side keeps at least 40 columns or 10 rows; herdr itself splits down to 0 × 0. A pane with
no size in the layout is refused `SIZE_UNKNOWN`. At the send the side is computed again from the latest snapshot,
and a different side is refused `DIRECTION_INVALID`.

**After it is sent.** The result (`PaneSplitResult`: the new pane's id and terminal id) is used only to pick the
new pane, never for a second write: starting an agent there is another gesture on its own card. The office picks
it (`navigator.locate()`, a selection only) when a current snapshot shows it with the terminal herdr named, on the
same connection generation, while the viewer's pick is still the pane that was split, the viewer has not navigated since
(`OfficeNavigator.nav_revision`), and not in answer mode. If the pick or the generation changed meanwhile, it gives
up silently; if the viewer navigated (another zone or machine picked, PageUp / PageDown, `N`, an edge arrow …), answer
mode opened, the terminal differs, or it does not show within 10 s, the footer says the new pane was not picked.
Only one new pane is waited for: a second split replaces the first wait.

## 5. Close, New space, Worktree

Three writes in the same `%Launch` block, below the start or split row: `Close` and `New space` on one row, the
branch box and `Worktree` on the next. They are offered for any pane the viewer picked; a launching pane shows
only these rows. A machine that is dimmed (offline) or has no current snapshot shows no block at all. Mouse
clicks only; the keyboard never triggers them.

All three follow the split's discipline: the context fixed at the press with the whole identity, no screen read,
every check again at the release against the latest fleet facts, single-flight, write-then-look, never retried. A
lost answer says the result is unknown and the next snapshot decides. After an accepted one the machine's client
fetches a snapshot at once. Each result's new workspace or pane id is used only to pick, never to write.

### Close

**What it sends.** `pane.close {pane_id}`. herdr has no confirm and hangs up the pane's terminal at once,
working or blocked agent included.

**What it takes with it** (`CloseScope`, a pure function of the typed snapshot): the pane; its tab, when it is
the tab's last pane (herdr sends no `tab_closed` event); its space, when it is the workspace's last pane; or a
mezzanine (a linked worktree's space, named by its level label such as `3A`), whose checkout stays on disk. The
scope also carries the pane's terminal id and its state word (`shell`, `starting`, or herdr's status; blocked
before starting), and all of it signs `CloseScope.signature()`.

**Never the parent of an open group.** The last pane of a repository's own space, while another workspace on the
machine shares its repository, is refused `GROUP_PARENT` and never sent: herdr would close the whole worktree
group. This is as far as the snapshot shows it: a parent's `worktree` field appears only after its first
`worktree.create`. A parent the snapshot cannot show is stopped by herdr's own `confirmation_required`; the card
says so and does not retry.

**Two real clicks.** The first click sends nothing (`CONFIRM_NEEDED`): it writes what closes in the note and the
terminal strip (the pane, the tab, the space or the mezzanine; a working, blocked, launching or unknown-state
agent is named as killed) and arms a 10 s confirm bound to the binding, the identity and the scope signature. The
button then reads `Close · click again` (`Close · kills` when an agent would be killed). The second click sends only
on the same binding, the same identity and the same signature. A change of pick, binding, scope or state, entering
answer mode, folding the panel, or the timeout cancels it; so does arming a start confirm. The release checks the
10 s again (a press held past the deadline sends nothing), and a double click is one click. At the send the
boundary recomputes the scope from the latest snapshot: `GROUP_PARENT` if it is now a group's parent,
`SCOPE_CHANGED` if the signature differs. A launching pane's identity usually changes within seconds, so a close
confirm on it is usually cancelled with `New terminal: pick again`. There is no undo, and nothing is ever closed
automatically.

### New space

**What it sends.** `workspace.create {cwd, focus: false}`. `cwd` is the pane's `cwd` exactly as the snapshot
carries it, because herdr silently lands any bad directory in `$HOME`. Refused if it is empty or not absolute
(`CWD_UNKNOWN`), if cleaning or bounding changed it (`Pane.cwd_clean` false, `CWD_UNCLEAN`), or if the directory
changed between the press and the send (`CWD_CHANGED`). No `label` (herdr names the space after the directory),
no `env`, no source workspace. `focus: false` holds when other workspaces exist; on an empty herdr the first
workspace is focused regardless, and the tooltip says so.

**After it is sent.** `SpaceCreateResult` (the new workspace, tab and root pane) is used only to pick the new
shell in its new zone, the way a split's new pane is picked.

### Worktree

**What it sends.** `worktree.create {workspace_id, branch, label: <branch>, focus: false}`. `workspace_id` is
herdr's own spelling (`HerdrSnapshot.wire_workspace_ids`); if it differs from the cleaned id or is listed twice,
the command is refused (`WIRE_ID_MISMATCH`, `WIRE_ID_DUPLICATE`). No `path`: the checkout goes to herdr's own
configured directory (`~/.herdr/worktrees/<repo>/<branch>` by default). No `base` (the checkout's HEAD), no
`cwd`, no `trust_repository`.

**The branch** is checked at the send port (`HerdrCommands.branch_refusal()`) and never rewritten:

- `BRANCH_BLANK`: empty, or whitespace, a control or an invisible character anywhere (nothing is trimmed).
- `BRANCH_TOO_LONG`: over 64 UTF-8 bytes.
- `BRANCH_CHARS`: a character outside `[A-Za-z0-9._/-]` (`@` included).
- `BRANCH_SHAPE`: a first character that is not a letter or digit; `..` or `//`; a segment starting with `.` or
  ending in `.lock`; ending in `/` or `.`; `HEAD`; starting with `refs/`.

herdr checks nothing but emptiness (it takes `refs/heads/x`, `@` and a direction override), so these checks are
the only guard. If the box changed between the press and the release, the send is refused (`BRANCH_EDITED`);
Enter in the box sends nothing; the box is cleared when the card is rebound, so a typed name never follows to
another pane. An existing branch that is not checked out is checked out rather than created; the note says so.

**The source.** The pane must still stand in the space aimed at (`FLOOR_CHANGED`), that space must still be listed
(`FLOOR_GONE`), and it must not itself be a linked worktree (`MEZZANINE_SOURCE`; herdr would answer
`linked_worktree_source`). A space that is not a git repository is still offered: the office cannot tell, and
herdr's `not_git_worktree` is the answer.

**The answer.** herdr runs git synchronously before answering, so the timeout is 30 s and the reply cap 16 KiB.
A `worktree_create_failed` message is git's raw multi-line stderr: only its headline is kept (`GitWords.headline()`:
the first line starting with `fatal:` or `error:`, else the first non-empty line; cleaned, grapheme clusters
bounded, at most 200 characters). The rest is never shown and never kept. The repository's hooks run on that
machine under the user's account. On a big repository or a slow disk the office's own reads of that machine may
time out while git runs; the ticket then ends `UNKNOWN` after 30 s and the footer says git may have run.

## 6. Measured herdr behaviour

Measured against herdr 0.9.0, protocol 22, in isolated named sessions whose servers were started with a clean
environment (no inherited `HERDR_*` variables: a client that inherits them gets "nested herdr is disabled"), never
against a user's session. A test agent was a scripted fake the detection manifest recognised; no real agent ran.

**Transport.**
- herdr answers one request per connection.
- A request line over about 1 MiB (1.1 MiB measured) makes the server drop that connection; the server itself is
  unaffected. The limit is between 256 KiB and 1 MiB.
- An unparseable request is answered with an error whose `id` is the empty string.
- Successive key and text requests to one pane arrive in order; herdr serialises input to a pane.
- `revision` in every `pane.read` result is 0, for every source.

**Focus.** `pane.focus` moves the shared selection for every attached client (one attached TUI client measured),
and with none attached, and switches the active tab. It marks the whole tab seen: two `done` panes of one tab
both turn `idle` when one is focused. herdr's documentation says "marks the target seen"; the target is the tab.

**Keys and input.**
- `pane.send_keys {pane_id, keys[]}` and `pane.send_input {pane_id, text?, keys?}` answer `{"type":"ok"}`. An
  unknown pane is `pane_not_found`, an unknown key name `invalid_key`, a missing `keys` `invalid_request`.
  `keys: []` and an empty `send_input` answer ok and send nothing.
- Bytes received: `1`–`9` → 0x31–0x39, `y` 0x79, `n` 0x6e, `enter` / `Enter` / `return` 0x0d, `esc` 0x1b. A key
  array is written in order, at once.
- herdr also accepts `C-c` and `ctrl+c` (0x03), `tab`, `space`, `backspace`, arrows, `f1` and many more: the
  client's key list is the only guard.
- Named keys herdr takes include `ctrl+a`, `alt+x`, `shift+tab`, `ctrl+up`, `f1`–`f12`, `shift+enter` (sent as
  xterm `CSI 27`). herdr encodes them in the application's current keyboard mode.
- Home, End, PgUp, PgDn, Insert and Delete cannot be sent: every spelling is `invalid_key`. `f13` is accepted and
  sends nothing.
- Sending keys or text has no side effect: a `done` pane on a background tab stays `done`, and focus and the
  active tab do not move, with or without an attached TUI client.

**Text and paste.**
- `pane.send_text` writes the bytes as they are and **never** brackets them (ESC and Ctrl-C pass through): typing.
- `pane.send_input {text}` delivers text as UTF-8 byte for byte. When the program has bracketed paste on, herdr
  wraps the text in `ESC[200~ … ESC[201~` (with `keys: ["enter"]`, followed by 0x0d). An ESC inside the text can
  end the paste early. 64 KiB is accepted: any length limit is the client's.
- Key-to-echo latency: p50 2–4 ms; p95 15–107 ms under a load average around 62. What the viewer feels is the
  polling interval.

**Reads.**
- `visible` with `format: ansi` is normalised to SGR sequences (`ESC[…m`) and CRLF only: no cursor movement, no
  OSC, no other control. Trailing spaces are trimmed and there are no more rows than the pane is high. A screen is
  0.1–5.4 KB and takes 0.1–4 ms locally; reading 4 panes at 10 Hz is about 150 KiB/s with herdr under 1 % CPU,
  with occasional spikes of about 110 ms.
- `recent` with `ansi` returns up to about 999 lines, about 72 KB, and does not move herdr's shared scroll
  position.
- A read has no side effect: focus, state, active pane and scroll stay.
- There is no cursor position in any read and no output stream to subscribe to (only the regex-driven
  `pane.output_matched`): reading means polling.
- In `recent_unwrapped` the last non-empty line is the prompt's last line (the second line of a two-line PS1).
  Trailing spaces are always trimmed (`$ ` reads `$`; a line of spaces reads empty). A cursor moved left does not
  show (`echo hi` then three lefts still reads `… echo hi`). Wrapped lines are joined; `visible` shows only the
  last wrapped segment and no prompt, which is why a start reads `recent_unwrapped`. `lines` 12 and 200 give the
  same last line.
- A grid's size comes from the snapshot's `layouts[].panes[].rect`.

**`agent.prompt`.**
- `target` takes an agent name or a pane id (a manually started, recognised agent with no name too), not a
  terminal id or a bare kind.
- herdr writes the text, then about 300 ms later `\r`, and answers after the `\r` (about 301 ms). It follows the
  application's bracketed-paste mode. Text plus Enter is one atomic submission with respect to other API writes.
  The answer's `agent_status` is the state *before* the prompt. Replies are 495–541 bytes, errors 75–319.
- Refusals: blocked → `agent_blocked` in 0.1 ms with **not one byte written**; a shell → `agent_not_found`;
  launching → `agent_not_ready`; `""` → `empty_agent_prompt`. Text of only spaces is sent; a working agent
  receives it.
- No validation of the text: `\n`, `\r`, escape sequences, U+202E and `ESC[201~` reach the terminal as they are
  (without bracketed paste a `\n` is two submissions; `ESC[201~` ends a paste early).
- It marks nothing seen and moves no focus. With `wait`, the connection hangs until the agent finishes, and a
  timeout or `agent_prompt_stalled` does not mean the text was not delivered.

**`agent.start`.**
- The socket API does not wait: it answers in 0.3–0.9 ms with `agent_started` and `launch_pending: true`. It types
  `<kind>` and Enter into the shell.
- The process is recognised after 0.07–0.3 s (`agent` appears, still `launch_pending`); after about 3.4 s
  (3.40–3.90 s) it is `idle` with `interactive_ready: true` and `launch_pending` gone. A start that asks a question
  at once stays `launch_pending` and turns blocked; `agent.prompt` then answers `agent_blocked`, and keys answer it.
- No event is sent between the answer and the recognition, and no event carries `name`, `launch_pending` or
  `interactive_ready`: only snapshots show them.
- Checks, in order: name; name unique (`agent_name_taken`, whose message carries the remote cwd's full path);
  kind (a fixed table, case-insensitive: `unsupported_agent_kind`); pane (`agent_pane_not_found`;
  `agent_pane_busy` when the foreground is not the shell); `timeout_ms` (over 3000 and at most 300000); `args`.
- Text already on the prompt line is not cleared: the command runs after it (`echo PARTIALmaki`).
- `server.agent_manifests` lists detection manifests, not installed agents.

**Launch timeout.**
- While a start is pending (recognised or not), another start in the same pane is `agent_pane_busy`: a double
  click cannot type twice.
- herdr's launch timeout (about 30.4 s by default) takes effect lazily. After it expires, another start in the
  pane, the same name, `agent.prompt` and `agent.list` do not settle it; only the first `agent.get` (by name or
  pane id) does. That `agent.get` answers a plain `agent_not_found` (saying neither failure nor timeout), the record
  leaves the snapshot's `agents[]` at once with a plain `pane_updated`, and the name and pane are free again.
- An `agent.get` before the timeout has no side effect. An expired, unsettled record is field for field the same
  as a launch still in progress: only the office's own ticket time tells them apart. `agent.get` marks nothing seen,
  moves no focus and changes no state.

**`pane.split`.**
- Answers in 2.9–3.6 ms, the new pane in `.result.pane` (`type: pane_info`).
- `focus: false` leaves focus alone; **without `target_pane_id` it splits the shared focused pane**; `focus: true`
  moves the shared focus.
- Without `cwd` the new pane inherits the target's `foreground_cwd`; a bad or relative `cwd` silently lands in
  `$HOME`.
- `direction` is only `right` or `down`. There is no minimum size: twelve splits in a row made panes 0 rows high
  and 0 columns wide.
- `pane_created` and `layout_updated` arrive in the same millisecond, the snapshot shows the new pane at once, and a
  `/bin/sh` prompt is readable 59 ms later. With the default login shell, a new pane still had no prompt after
  2.5 s, and a line sent then was only echoed, not run, within 1.5 s.

**`pane.close`.**
- Answers `{"type":"ok"}` (39 bytes) with no confirm, and hangs up the terminal at once (SIGHUP), a working or
  blocked agent included.
- Closing a tab's last pane closes the tab, with **no `tab_closed` event**; closing a workspace's last pane closes
  the workspace; a linked worktree's checkout stays on disk.
- herdr's own view may move, with no event.
- The last pane of a worktree group's parent answers `confirmation_required`.

**`workspace.create`.**
- Needs an explicit `cwd` (without it herdr follows its own focused pane) and `focus: false`. The first workspace
  on a server is focused whatever `focus` says.
- A bad `cwd` silently lands in `$HOME`, labelled `~`.
- A new workspace's `worktree` field appears a moment later, not in the first answer. A repository's own workspace
  gains its `worktree` field (with a `workspace_updated`) only at its first `worktree.create`.
- The answer (new workspace, tab and pane) is 0.8–1.6 KB.

**`worktree.create`.**
- Without `path`, the checkout goes to `~/.herdr/worktrees/<repo>/<branch>`.
- On the user's own repository `trust_repository` has no visible effect, and hooks run.
- herdr checks the branch for emptiness only: `refs/heads/x`, `@` and U+202E are taken.
- An existing branch that is not checked out is checked out, not created.
- git runs synchronously in the handler: 914 ms cold on a small repository.
- A failure is `worktree_create_failed` whose `message` is git's raw multi-line stderr, once a 2.9 KB usage dump.
- From a linked worktree: `linked_worktree_source`.

**Not measured.** Two attached TUI clients (herdr's documentation says each client records seen completions on
its own); latency through an SSH forward; `alt+<punctuation>`; whether other API calls wait while
`worktree.create` runs git; timings on a large repository; an unrecognised approval prompt showing as `idle`
(herdr's documentation says it can).

**What herdr 0.9.0 lacks** that would make the boundary tighter: a cursor position in `pane.read`; key names for
Home, End, PgUp, PgDn, Insert and Delete; a `revision` that changes with the screen, or an output-changed event;
a conditional send ("only if the screen still reads so"); a single-pane "mark seen"; an event when a launch times
out; a minimum pane size for `pane.split`; clearing the prompt line before `agent.start`.
