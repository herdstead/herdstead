# Herdstead manual

Herdstead draws a [herdr](https://herdr.dev) session as a pixel open-plan office. This manual covers everything
a user sees and every switch they can flip; the [README](../README.md) is the short version.
The rules for writing to herdr are in [the write boundary](WRITE_BOUNDARY.md); what each thing on screen stands for
is in [the visual language](VISUAL_LANGUAGE.md).

Contents: [Running](#running) · [The office](#the-office) · [Top bar](#top-bar) · [Machines, spaces and edge arrows](#machines-spaces-and-edge-arrows) ·
[Bottom panel](#bottom-panel-and-agent-card) · [Answer mode](#answer-mode) ·
[Start agent, New pane, Close, New space, Worktree](#start-agent-new-pane-close-new-space-worktree) ·
[Terminal monitor](#terminal-monitor) · [NEWS, EVENTS, OVERVIEW](#news-events-and-overview) · [Lens](#lens) ·
[Strategic view](#strategic-view) · [Keyboard](#keyboard) · [Window, zoom, frame rate](#window-zoom-and-frame-rate) ·
[Alerts](#alerts-when-the-window-is-in-the-background) · [herdr machines](#herdr-machines) · [Themes and art](#themes-and-art) ·
[Screenshots and performance](#screenshots-and-performance) · [Limits](#limits) · [Download](#download-and-run-the-macos-app) ·
[Export](#export-locally) · [CI](#ci) · [Repository layout](#repository-layout) · [Licence](#licence)

## Running

Godot **4.7** (verified with 4.7.2). The socket client uses `StreamPeerUDS`, which exists only from Godot 4.6.
The runtime PNGs and editor resources are committed: open `project.godot` and press F5, or `make run`. Python is only
needed to rebuild art. The main scene `scenes/office.tscn` connects to herdr; `scenes/preview.tscn` is a mock showroom
of the art packs that never connects.

Socket path, first match wins: `--socket=` > environment variable `HERDR_SOCKET_PATH` > `~/.config/herdr/herdr.sock`.
Office options go after `--`.

```sh
godot --path .                                           # the live office, default session
godot --path . -- --socket=/absolute/path/herdr.sock     # another session's socket
godot --path . -- --read-only                            # watch only (see below)
godot --path . -- --plain-window                         # a plain 1920×960 window instead of filling the screen
godot --path . -- --always-on-top                        # a small window kept in a corner (never fills the screen)
godot --path . -- --chime                                # alert tones on for this run
godot --path . -- --no-bounce --no-title-count           # no Dock bounce, no (N) in the title
godot --path . -- --fps=24                               # fixed frame cap; --fps=0 means no cap

# headless probe: ping → snapshot → counts → sit on the event stream for 8 s; non-zero exit when unreachable
godot --headless --path . --script tools/probe_herdr.gd -- --wait=8
godot --headless --path . --script tools/probe_herdr.gd -- --socket=/absolute/path/herdr.sock
godot --headless --path . --script tools/probe_herdr.gd -- --machines    # also list and reach herdr machines

godot --path . scenes/preview.tscn          # the mock showroom (no herdr)
godot --path . scenes/avatar_studio.tscn    # the local Avatar Studio (no herdr)
```

**Operator vs `--read-only`.** By default the office is an operator: besides `ping`, `session.snapshot` and
`events.subscribe` it can send the requests listed in [the write boundary](WRITE_BOUNDARY.md), and only from
`scripts/herdr_commands.gd`. With `--read-only` that boundary is never constructed: the office sends only those three
read requests, the card has no write buttons, and the terminal monitor opens but neither reads the screen nor sends, and
says so. `--read-only` counts on either side of `--`. A near miss (`--readonly`, `--read-only=yes`, `--Read-Only`, an
em-dashed `—read-only` …) stops the office with `ARGS_ERROR` rather than guess. Both modes call only
`herdr machine list --json` to read saved machines.

When you run, screenshot or measure next to someone else's herdr session, always point `--socket=` at a fake herdr or
add `--read-only`.

Other office options (mostly for screenshots and tests):

| Option | Effect |
|---|---|
| `--pack=<manifest>` | Start with this art pack (`res://…` or an absolute path) |
| `--space=<number>` | Pan to Local's zone with this herdr workspace number, once, when Local has it (`--floor` is gone, no alias) |
| `--zoom=<2\|4\|6\|8>` | Start at this pixel scale; odd values round down to even (`--zoom=3` and `--zoom=1` are 2) |
| `--capture=<png>` | Screenshot after the first snapshot is drawn (or the OFFLINE screen after 8 s), then quit; prints `CAPTURE_OK:` |
| `--wait=<s>` | With `--capture=`, wait this many more seconds |
| `--panel=history` / `--panel=events` | Start on the bottom panel's HISTORY or EVENTS page (every run otherwise starts on AGENT) |
| `--overview=open` | Start with OVERVIEW open |
| `--strategic=open` | Start with the strategic view open |
| `--lens=held` | Hold the lens for the whole run |
| `--point=<pane key>` | Point at a pane as a hovered HUD line would |
| `--machine-socket=<name>=<path>` | Add a local socket as a machine (debugging; see [MACHINES](MACHINES.md)) |

The four scenes (office, showroom, pixel people showroom, Avatar Studio) read their options once through
`scripts/app_args.gd`; a repeated option takes its last value. `--capture=` / `--wait=` is one flow for all four
(`scripts/capture_driver.gd`).

## The office

| herdr | Office |
|---|---|
| machine | one open-plan map (the only one when there is just Local); one machine's map is shown at a time |
| workspace (**space** in the UI) | a **zone** on that map: its pods on a carpet inside low partitions, under a sign with herdr's `number` and its label; a worktree group shares the carpet's colour and the sign's stripe |
| linked worktree | a **mezzanine**: a zone of its own, placed right under its source zone the first time, numbered `3A`, `3B` |
| tab | a pod of desks; its label is written small right under it |
| pane | a seat at that pod |
| agent | the pixel person in the seat; an empty `agent` is a SHELL seat with nobody in it |

**One map per machine.** A map is one rectangular floor: an outer wall on top, an entry band under it with the pantry
counter in its corner,
side walls, and a main aisle down the right. Windows, pictures and the lift door hang only on the outer wall. Below the
entry band the zones stand in lanes, each on a carpet inside low partitions open at the top, its sign hanging from the
top-left post. Plants and side tables (each carrying a mug, a notebook, now and then a white cat) are y-sorted with everything
else.

**Stable layout.** A 32-unit grid. The map is lanes four cells wide (the narrowest pod) with a one-cell aisle between
two; the entry band is 64 units, the main aisle 64. A zone takes whole lanes under an aisle row of its own, first as many
as its pods need to stand in one row, and its pods stand in rows 192 units deep (a pod is one 32-unit desk per column, a
seat on each side). A map's lanes are fixed the first time it is
planned; a wider window only shows more of it. New tabs fill gaps first, pods grow in place, an over-wide pod gets its
own row (its zone taking more lanes, the map widening if it must). New zones take the top-most, left-most gap; a zone
that must grow does so in place or moves alone. Nothing is compacted when things go away, and a map never shrinks.
Renames, state, focus and window changes never re-lay out pods. The plan and camera position are kept per machine for
the run.

**Machine plate.** Above the map: the machine's name (`@ NAME` once there is more than Local, then LIVE / OFFLINE /
CONNECTING with any ssh error), and on the right the machine's space and pane counts. While the map cannot be laid out,
a line under it names the zone at fault (`Layout unavailable: 3 INFRA: invalid explicit seat hint`). Each zone's own
number, name, repository and checkout are on its sign (hover it); a source zone and its mezzanines share one colour
stripe. A machine with no workspace (offline, never connected, or an empty session) is an empty map: walls and door,
no zone, and the plate's note says why.

**State on the seats.**

- **blocked**: seated, hand raised, a chip on the badge's row holding the badge and how long it has waited (short form,
  `12m`, the card's clock). Hover the chip for an excerpt of the question; click it to select the agent and enter answer
  mode once the question shows. When the machine is offline or the start was not observed, no time and no chip frame
  are drawn (the raised hand and badge stay; pointing and clicking there still count).
- **done** (UNREAD: finished, not yet looked at): seated, a stack of paper next to the laptop. Done means "unread",
  never "task passed".
- **idle**: seated, a mug beside the laptop.
- **working**: seated at the desk. `launch_pending` shows the starting badge. Unknown states fall back to `unknown`.
- The pantry counter, plants, side tables, partitions and carpets are furniture only: nobody walks to the pantry, and a state
  never makes anyone get up.

**People walk.** When a pane gets an agent, a person walks in from the lift door to the seat; when a pane goes, they
walk out as a ghost you cannot click. Name plate, badge, chip, paper, mug and click area change the moment herdr says so;
the body follows within at most 6 seconds. A new workspace is a new zone its people walk into; closing one, its people
walk out (not every departure animates). An offline machine freezes in place; reconnecting, changing machine or
changing theme places everyone directly. Panning between zones and switching machines are instant, with no transition.

**Monitors and lamps.** Only seats with a pane have a monitor. The desk lamp has four levels (off / low / on / strong)
showing herdr's focused pane and whether its tab is the one open in its workspace.

**Selection.** herdr's focused pane is selected by default. Click a seat to select it yourself; when the selected pane
disappears, selection returns to herdr's focus. Clicking a seat never changes the map or pans.

**Which map is shown, and where.** One machine's map at a time: the machine you went to (its chip in the top bar, a
card's place in one of its zones, PageUp / PageDown, `N`, a list pick) while it exists; otherwise the selected pane's
machine (your pick, else herdr's focus, Local first); otherwise the first machine with a workspace; otherwise Local's
empty map. A place click pans to its zone, its sign at the top of the world. While you have picked nothing, or the pane
you picked is gone, herdr's focus moving pans to the new desk as far as it takes (and to another machine's map if it is
there); a chip or an edge arrow you click at the same moment wins, and the next move of the focus is followed again. A map
seen for the first time opens on the selected pane's pod, else on its first zone; each map keeps where you left it
panned.

**Disconnected is not idle.** When a socket goes away or the event stream breaks, the office keeps the last picture,
dims it, stops the people and shows OFFLINE (with several machines, only that machine's map), and its counts drop to
zero. It reconnects with exponential backoff from 0.5 s to 5 s.

**People and looks.** Everyone in the office is a pixel person: six layers (legs < top < body < glasses < hair <
headwear), density 2, nearest-neighbour. Clothes follow the provider; face, hair and glasses vary per pane, so several
panes of one agent are not twins. The seat's name plate says what the pane is called (its task summary from the terminal
title, else its label, tab or directory) and appears while the seat is hovered or selected, or while `L` is held; hovering
the seat shows the whole name, who sits there and in what state, and where. The Avatar Studio
(`scenes/avatar_studio.tscn`) pins each part per agent for all 23 agents in `data/agent_catalog.json` (or leaves it
VARIES), saved to `user://herdstead_avatars.json` (schema 2). A save rereads what it will write, checks the file on disk
was not changed by someone else, refuses any save that would lose data and says why, and keeps anything it cannot read
as it was.

**Fonts.** Every word the office draws is the bundled Fusion Pixel font at its native sizes: the world's labels (name
plates, zone signs, tab labels) and the HUD's small rows in its 8px cut, the HUD's body in its 10px cut,
headings in its 12px cut. Latin and Chinese glyphs are the pack's own and do not change with the OS; only glyphs the
family lacks (emoji, rare symbols) fall back to a platform font. The one exception is how long a seat has waited (the
chip's `12m`, the lens line's `4s+`): it is Tiny5 at 8, whose narrower digits fit the chip at the seat pitch.

## Top bar

After the wordmark come, with more than Local, a **chip per machine** (see [below](#machines-spaces-and-edge-arrows)),
then the **portrait strip**, who needs you, as faces: every agent of the online machines, the
blocked first in the order `N` walks them (the leftmost is whom `N` picks, with how long it has waited: `12m`, `+` after
a time means "at least"), then the done (UNREAD) oldest first, then the working and the idle in place order. A card is
the seat's person, the pane's name, and its space after a tag in the colour of its worktree group's carpet; its frame
is its state's colour, and the selected pane's card has a ring inside it (white on a horizontal card, dark on a tile's
cream window). A dropped machine's agents have no card.
On a window at least 400 units high (the tall top bar, 70 units) each card is a **tile**: the seat's person as a
head-and-shoulders portrait on a cream ground, framed in the state's colour, a small mark in its corner (`!` blocked, an
envelope for done, a green dot working, a white dot idle), and the name and the place under it; a face-only tile shows the
middle of the portrait. On a lower window (a 32-unit bar) the cards are horizontal, the small standing person beside the
words, with no mark.

- When the agents do not fit, the strip folds them by a fixed ladder: the working and the idle into a fold
  (`+12` over `working`), then the done and the blocked into faces alone, then the done into a fold, then tallies
  (`+12`), and last only as many blocked faces as fit before a `+N`. The longest-waiting blocked fold last.
- Hover a card: its whole name, provider, state, wait, space / tab (and machine). Hover a fold: who is in it.
- Click a card's face or name: select that agent (its map, its desk on screen), as a click on its desk does.
- Click a card's place (the colour tag and the space under its name): pan to that space; nothing is selected.
- Click a fold or a tally: open OVERVIEW on that state; while it is open, the same click sets or clears that chip.
- **`1 machine · 13 panes`** (every machine, and the panes the online ones carry), right of the strip, opens or closes
  OVERVIEW.
- **CHIME OFF / CHIME ON** after it switches alert tones (see [Alerts](#alerts-when-the-window-is-in-the-background)).
  Below 640 units the count and the switch give way to the strip.

The top-right corner shows the pack's name and the light: `STUDIO · DAY  [T]` or `STUDIO · NIGHT  [T]` (see
[Day and night](#themes-and-art)), and how the office runs (`LIVE / READ ONLY`, `1 OFFLINE / OPERATOR` in the blocked
colour while a machine is down). Hover that line: each machine, whether it is online and how long ago its snapshot arrived.

## Machines, spaces and edge arrows

There is no left column: the world starts 16 units in from the left, as the bottom panel does, and getting around is in
the top bar and on the keys.

- **Machines.** With more than Local, each machine has a chip after the wordmark: its name (cut short on a narrow bar,
  whole in the tooltip, which also says whether it is online and how long ago its snapshot arrived). **Click a chip to
  show that machine's map** (a machine that never connected opens as an empty map that says why); the chip of the
  machine shown stands on a darker ground. An offline machine's chip is red (connecting: grey) and none of its agents
  has a card. Many machines on a short bar: the row of chips is cut where the strip would get too short to show the
  longest-waiting blocked agent; the machines past the cut are reached by their cards and PageUp / PageDown.
- **Spaces.** A card's place (its colour tag and its space) is a button: hover it for the space as its sign reads
  (`3 INFRA`, a mezzanine's `3A HUD-LANE`) and its repository and checkout; click it to pan to that space, its sign at
  the top of the world, on its machine's map. It selects nothing. A space nobody is waiting in has no card: **PageUp /
  PageDown** walk every space of every machine in ascending number, mezzanines right after their source; a drag and
  the wheel pan; `S` shows them all at once; the OVERVIEW lists every pane, shells too, and a row click goes there.
  The card's branch box lets the page keys through.

**Edge arrows.** A zone of the shown map with a blocked desk out of view gets an arrow on the edge of the world toward
it: `↓ 3 ! 2` (the way, the zone's number, how many blocked desks are out of view). Hover it for the zone's name and the
longest wait (`3 INFRA · 2 blocked · longest 12m`), which also rings that zone's blocked cards in the top bar. Click it to pan to the
longest-waiting of those desks; it selects nothing. The arrows follow a drag or the wheel at once. At most 8, longest
wait first; the eighth says `+N` and lists the rest in its tooltip. Arrows never overlap: an edge too short for all of
its arrows keeps the longest waits and ends in its own `+N` for the rest, and shows them again when the world is wider.
An arrow covers the world where it stands, so a chip under it cannot be clicked. When the world is narrower than 440 units (the 480×320 minimum screen) an arrow drops the
number (way, badge, count). Arrows are for the map shown only: **another machine's blocked agents show as cards in the
top bar**, and NEXT reaches them.

## Bottom panel and agent card

The bottom of the screen is the bottom panel: a row of tabs, **AGENT | HISTORY | EVENTS**, with the NEWS line beside them,
over the page shown. Every run starts on AGENT, the agent card. The card and HUD are in English; a sentence that does not
fit is in the tooltip.

**Docked on a screen at least 400 units tall.** The panel is always open there, 120 units high whatever its page, so a tab
never moves the world: the portrait (the seat's person, head and shoulders, still, framed in the state's colour; greyed
when its machine is dropped), the pane's name, the state in a pill of its colour and its wait, who and where
(`CLAUDE · api / main`); a live preview of the terminal's last 6 rows (herdr's `detection` when blocked, the tail of
`recent_unwrapped` otherwise); START AGENT or NEW PANE (its title beside the kinds or the button) over Close · New space ·
branch · Worktree on one line; the pane's details (when the card is at least 1000 units wide, from a 1040-wide screen); and at the right end one column:
NEXT with `‹ ›` beside it, then **Monitor ⤢** and **Answer ⏎**, **Switch herdr here** and its note, and the outcome on one line.
There is nothing to fold, so `Esc` goes on to OVERVIEW or the strategic view.

**Two rows below 400 units.** The tabs over one line: name · state · where, how long it has waited, `Monitor ⤢`, `Open ⏎`,
`×`, NEXT and `‹ ›` (the `⤢` and `⏎` are small icons after the word; below 640 units of width they read `⤢`, `⏎`, and NEXT
shows only the name). The line reads no preview.

- `Enter`, `Open ⏎`, answer mode, and the HISTORY and EVENTS tabs open it to full height with the whole 12-row preview
  (a shell shows `SHELL` / `no agent` instead of portrait and state). Full height below 640 units gives NEXT's room to
  the preview.
- `Esc` (outside answer mode), `▾ Esc` in the actions column, or the AGENT tab after HISTORY / EVENTS fold it again;
  selecting another pane folds it too. When answer mode ends by itself after a key is sent, the panel stays open so the
  result stays visible.

On every screen:

- `×` at the card's top right (on the line, at its end) closes the card: the pick is forgotten (herdr's focus leads the
  office again, and no write is offered to anybody); the panel keeps its height and says how to open a card again, and
  NEXT stays. Picking a desk, a chip, a portrait card or a NEWS, EVENTS or HISTORY line (or `N`) opens a card again;
  herdr's focus moving never does.
- `‹ ›` step through NEXT's queue: select only, never expand or answer.
- Every pick shows the AGENT page, except a click on a HISTORY or EVENTS line, which keeps its page.
- **HISTORY** (`A` shows it, `A` again the card) lists the panes that were blocked or done this run and are not any
  more, newest first: what they waited as, the name, the space, and `OFFLINE` or `GONE`, counting only the pane's
  current agent run. Click a line to select that pane, if it is still the same terminal; a greyed line says why it
  cannot be (another terminal in the pane, a terminal nobody can verify, the machine away, the pane gone).
- The branch box of New worktree lets `PageUp` / `PageDown` through to the space step, and lets go of the keyboard on a
  click anywhere outside it and its Worktree button.

Card details keep the pane name, full directory, foreground process directory and session context; remote paths belong
to their machine. Launch state comes from `snapshot.agents[]` and is attached only when the pane id is unique and the
terminal id matches, with provider, workspace and tab checked; stale agent entries never override pane status events.
A new session invalidates the old wait clock.

**Switch herdr here** (on a remote machine: Switch herdr on <machine>) is enabled only for a seat you picked yourself,
and only while it is still the terminal you picked. It switches herdr's shared view, and **clears UNREAD for every pane of
that tab** (the note beside it says `Clears tab's UNREAD`).

**NEXT** at the right end says what pressing it would do and to whom, by name (`NEXT: Answer needs approval 12m (N)` / `Read refactor the fleet`) and how
long they have waited. Clicking it equals pressing `N`: select that agent and expand its panel; a blocked one enters
answer mode once its question shows (nothing is sent; you still press the key, so `N` then a digit answers), a done one
only expands. Under `--read-only` there is no verb; it only selects. With nothing to do it reads `All clear` and greys
out.

## Answer mode

Only for an agent seat you picked yourself. `Enter` or **Answer ⏎** in the card header opens it; opening sends nothing.
A click on a blocked agent's chip, NEXT or `N` opens it too, once the question shows; nothing opens it by itself.

Answer mode is a modal: the bottom panel, at most 640×276 units and with its tabs hidden, stands in the middle of the room under the bar over
the dimmed office, laid out top to bottom: who and where, the terminal across the whole panel, the answer keys in one
row, the reply box, and along the foot Monitor, Close and what became of the last answer. NEXT stays at its right end on
a wide enough screen. The world keeps the room the opened panel left it. The dim only darkens: clicks go
through it, so another agent's chip, desk or row picks them (and leaves answer mode) wherever the panel does not cover
it. A desk under the panel takes no click; leave with `Esc` or move on with `N`. Leaving drops the panel back along
the bottom.

- A **blocked** agent: click `1`–`9`, `y`, `n`, `⏎` (Enter) or the separate **Send Esc**.
- An **idle / done** agent: write one line in the reply box and click **Send line**; herdr types it and presses Enter
  (`agent.prompt`). At most 1024 bytes; control, invisible and bidirectional characters are refused with the reason,
  never rewritten. herdr itself refuses a blocked agent, and the card stops that first with `asking: use keys`; herdr's
  own refusals are shown in its words (`herdr refused: no agent here` / `still starting`).
- An agent **still starting** accepts only answer keys. A **shell** accepts nothing.

The keyboard in answer mode sends only `1`–`9` and `y`, and only when both the physical key and the key the layout
produces are that key (AZERTY's digit row and QWERTZ's Z/Y cannot send from the keyboard; use the buttons). `n`, ⏎ and
Send Esc are click-only. `N` leaves and jumps to the next agent that needs you (a blocked one enters its answer mode once
its question shows). `Esc` only leaves answer mode, never reaches the terminal, and leaves the panel open; press `Esc`
again or click `▾ Esc` to collapse. **The keyboard's Enter never sends.** While the reply box has focus every key is
typing. Drafts are kept per pane.

**Checked, best effort.** When you press, the card freezes the preview it shows. Before sending it rereads the same text
(for blocked, the full `detection`, up to 200 rows; the card shows the last 12 and says `12 of 31 rows`) and sends only
if it is identical and the state still allows it; otherwise `Not sent: the terminal changed, look again`. This is only
best effort: between the reread and delivery the question can still change to another with the same ending, and the card
always says `Checks the screen first; it can still change`. `Sent` means herdr accepted the key, not that the agent did
what you meant.

**Write, then look.** After any write finishes (any result), every write to that pane stays closed until the card has
shown a preview read after the write. A lost reply shows `Unknown result: look first`. Writes are never retried.

## Start agent, New pane, Close, New space, Worktree

All five are mouse clicks on the bottom panel's card only; the keyboard never triggers them. Under `--read-only` they do not
exist. None is retried; a lost reply is reported as unknown, and the next snapshot decides.

**START AGENT** (a shell seat selected): next to the preview, one button per agent kind seen in this machine's snapshot
(`CLAUDE`, `CODEX` …; with none seen, it says to start one in herdr first). Click one and herdr types that kind into the
terminal and presses Enter, under a generated name `<kind>-<n>` such as `claude-2`. Before sending, the card rereads the
terminal's recent output:

- the last line ends in `$ % > # ❯ ➜ λ »`: one click sends;
- it ends in anything else: the first click shows that line and asks `Start anyway?`; a second click on the same kind
  within 10 seconds sends;
- the read is incomplete: nothing is sent.

This is still best effort: an unfinished half-line would run together with the command, so the button always says it
will type the kind into this terminal and press Enter. After sending, the footer follows the launch
(`Starting claude-2 · 4s` → `claude-2 started`; a launch that asks at once: `claude-2 asks: answer with the keys`).
If nothing is detected after 31 seconds the office asks herdr once and says `not detected` or
`did not start: look at the terminal`. Never retried. In the world a person walks in from the lift door with an hourglass
overhead; until herdr detects the kind the card's seat line reads `CLAUDE-2 · api / main`.

**NEW PANE BESIDE <agent>** (an agent seat selected, same place): `New pane →` or `New pane ↓`, the direction chosen from
the pane's shape; refused when either side would be under 40 columns or 10 rows. herdr splits a new shell pane in the same
directory beside it, and herdr's focus does not move. When the new pane appears, the office selects it (select only; to
start an agent there, click a kind). No undo.

**Close** (any selected pane, the next rows of the same block) takes two clicks. The first only states what will close,
in the note and the terminal strip:

- `Closes w2:p3 (shell).` or `Closes CLAUDE's pane w2:p3.`
- last pane of a tab: `… and its tab w2:t1 (last pane of the tab).`
- last pane of a space: `… and space 6 "~" (last pane of the space).`
- last pane of a mezzanine: `… and mezzanine 3A "api-v2". The checkout stays on disk.`
- an agent that is working, blocked or starting: the note becomes `Kills CLAUDE, still working.` /
  `Kills CLAUDE mid-question.` / `Kills CLAUDE's launch.` (the full sentence is in the tooltip) and the button reads
  `Close · kills`.

A second click within 10 seconds sends `pane.close`: no confirmation from herdr, immediate SIGHUP, and herdr's own view
may move to another pane. Changing the selection, the state or the scope, or timing out, cancels. The last pane of a
repository's own space while its mezzanines are open (as far as the snapshot shows) has the button disabled with the
reason, because herdr would close the whole group; when the snapshot cannot yet show it is a parent, herdr refuses
(`needs herdr's own confirm`) and the card says so.

**New space** sends `workspace.create {cwd, focus:false}` with this pane's directory exactly as the snapshot gives it.
It is refused when the directory is not absolute or contains invisible characters, since herdr would silently fall back
to `$HOME`. When the new zone appears the office selects its shell (on another machine's map too). On an empty herdr the first space is
focused by herdr regardless.

**Worktree**: type a branch name in the box beside it (at most 64 bytes, only `A-Za-z0-9._/-`, no shape git rejects;
an existing branch is checked out, not created) and click. It sends
`worktree.create {workspace_id, branch, label: branch, focus:false}`; the checkout lands in herdr's own worktree
directory (`~/.herdr/worktrees/<repo>/<branch>`), and the repository's git hooks run on that machine. A mezzanine cannot be
a source. When git refuses, the footer shows only its first line (`herdr refused: git: fatal: …`).

## Terminal monitor

A near-full-screen pixel display of one pane; one at a time. Open it by clicking **Monitor ⤢** on the bottom panel
(`⤢` when narrow), or pressing `M` (opens on the pane the panel shows, or the one a NEWS, EVENTS or HISTORY line just
picked). It draws herdr's own screen (`visible`, in colour) at the pane's real rows and columns, up to 400×200 (larger
panes are clipped and the status line says so), wide characters in two cells, box drawing drawn by the monitor itself.
It reads 5 times a second while the window has focus, once a second without, and slows down when drawing is slow.
There is no cursor (herdr does not report one).

**Raw mode.** While the monitor has the keyboard, **every key goes to that terminal**, `Esc` included, and `● LIVE INPUT`
stays under the title. None of the office's shortcuts work while it is open.

- **Close**: `Ctrl+]` or the close button. `Ctrl+]` is matched by physical key (the key where `]` sits on a US keyboard,
  so any layout can close), and the layout's own `]` key works too.
- **macOS Option** types what the layout gives, as Terminal.app / iTerm2 do by default (German layout: `Option+L` is `@`,
  `Option+7` is `|`). An Option combination that yields no character (a dead key, such as `Option+U` then `U` for `ü`)
  sends nothing; the composed character is sent. For Meta, press `Esc` and then the key.
- **Linux Alt** is always `alt+…`.
- **Paste**: `Cmd+V` on macOS, `Ctrl+Shift+V` on Linux. A clipboard containing ESC, C1, control characters other than
  Tab / newline / carriage return, DEL or bidirectional controls, or larger than 64 KiB, is refused whole.
- Home / End / PgUp / PgDn / Insert / Delete cannot be sent to herdr 0.9.0; pressing one says so.
- **Wheel** scrolls a local scrollback (`recent`, up to 999 rows, read on demand, never moving herdr's scroll position);
  any key returns to the live screen.
- A new terminal (new terminal id) or a closed pane stops input; click **Follow new terminal** to continue. Starting an
  agent or `/clear` in the same terminal is not a new terminal; input continues.
- Keys still queued when the monitor closes are cancelled and never sent.
- An offline machine freezes the screen, dims it and shows OFFLINE.

The title bar has the same **Switch herdr here**.

## NEWS, EVENTS and OVERVIEW

All three read the state log: the state changes observed since this run opened, in herdr's words. It is bounded, holds
no terminal text and is never saved. Clicking an entry only selects the pane.

**NEWS** stands in the bottom panel's top row, beside its tabs: the latest 8 events, newest on the left. The time is written after the segment
that ended: `11:40 refactor the fleet · api working 38m → done` (`+` = at least; a long name is cut, the tooltip says it whole). An entry whose pane is gone is disabled (the tooltip
says so); machine entries are not clickable.

**EVENTS** is the bottom panel's third tab: the same events, newest on top, up to 200 rows, one line each. Clicking a row
selects its pane and keeps the page.

**OVERVIEW** opens from the top bar's `1 machine · 13 panes`, a fold, or `O`, over the world. One row per pane, shells too: state, how
long this segment has lasted, total blocked time this run, how many times it got stuck, and a timeline since opening
(hatching = not observed). Columns: SPACE / TAB, STATE, FOR, BLOCKED, TIMES. Click a column head to sort, chips to filter,
a row to select that pane; the bottom panel works as usual (you can answer from it). `O`, `Esc` or `X  Esc` close it; in
answer mode `Esc` leaves answer mode first. `M` does nothing while it is open.

## Lens

Hold `L`. The world becomes a data view until you let go: every agent's seat gets one line of how
long it has been in this state (the same number as OVERVIEW's FOR, `+` = at least; shells and offline machines show none,
no track shows `?`), chips are hidden, every seat's name plate shows, the floor under each pod is washed with its most
urgent state (the strategic view's cell colours), furniture dims, and the theme cell in the top bar reads `LENS · hold L`. It does not light while the monitor, OVERVIEW or
the strategic view is open or a text box has the keyboard; a press that started there has to be released first.

**Pointing.** Hovering a HUD line about a pane (a NEWS entry, an EVENTS row, a HISTORY line, a portrait card) draws a
still dashed frame in `ink` / `paper` around that seat; for a pane on another machine, its portrait card gets a ring
instead (white on a horizontal card, grey on a tile). Hovering an edge arrow rings its zone's blocked cards. Pointing never selects, reads, writes, pans or changes map.

## Strategic view

`S` replaces the world area with a diagram of the shown machine's map: a section per space, in PageUp / PageDown order, captioned
as its sign reads (`3 INFRA`; a section too tall for the room runs on into the next column under `3 INFRA …`), and in it
one box per tab (name on top), one cell per seated pane in its state's colour (working, blocked, UNREAD in their colours,
idle and starting warm white, shell dark), and the wait written in each blocked cell.
It shows at a glance who on the machine is blocked / done / working / idle and where they sit. The hover tip gives
provider, state, time and place; over a caption, the space's repository and checkout (a caption too long for its column
is cut, never shrinking the cells, and its tip starts with the whole name). Click a cell to select that pane,
close the view and pan its seat into view. `S` or `Esc` closes it. The top bar, the bottom panel, `N`
and PageUp / PageDown keep working (a card's place or a page key scrolls the diagram to that space's section; another
machine's place or chip redraws it for that machine); arrows and the wheel do not pan the world. The top bar's theme cell reads
`STRATEGIC · S`, the panel title shows `S · Esc`, and a machine whose map has no pods shows `No desks on this machine`. `S` does
nothing while the monitor or OVERVIEW is open or a text box has the keyboard.

## Keyboard

| Key | Effect |
|---|---|
| Drag, arrows, wheel (outside panels) | Pan |
| `PageUp` / `PageDown` | Pan to the previous / next space (a zone of the map; the map of another machine only past its ends). The order is ascending, so **PageUp goes to the lower-numbered space and PageDown to the higher** (the reverse of the FLOORS minimap, which listed the highest first): from a source zone down into its mezzanines, from a mezzanine up to its source; PageDown from a machine's last zone into the next machine's first, PageUp the other way; stops at the ends |
| `N` | Next agent that needs you, across every online machine and zone: only blocked ones while any are blocked, otherwise UNREAD (longest wait first; unknown start counts as longest). Selects it, shows its machine's map, pans to it and expands the panel per NEXT's verb. Never sends. To see done agents while some are blocked, click DONE |
| `Enter` (or keypad Enter) | Show the AGENT page and, on a short screen, open the bottom panel; on an answerable picked agent whose question shows, press again for answer mode |
| `1`–`9`, `y` | In answer mode: send that key |
| `Esc` | Leave answer mode; outside it, fold a short screen's opened panel; close OVERVIEW / strategic view |
| `M` | Terminal monitor on the pane the panel shows |
| `A` | The bottom panel's HISTORY page; again, the AGENT page (on a short screen it opens and folds the panel; not under OVERVIEW or the monitor) |
| `O` | OVERVIEW |
| `L` (hold) | Lens |
| `S` | Strategic view |
| `T` | Day or night: turn the light over until the clock's own day or night turns |
| `-` / `=` | Pixel scale down / up |
| `Ctrl+]` | Close the terminal monitor |

Digit keys never change zone or map (`1`–`9` are answer keys). Outside answer mode, and while the reply box has no focus, the
card takes no office keys. While the terminal monitor is open it is the reverse: every key goes to the terminal. The top
bar, edge arrows and bottom panel stay fixed on screen; only the world pans.

## Window, zoom and frame rate

The office fills the screen: its window opens maximized, so the menu bar and the Dock stay. On macOS the title bar
is see-through and the top bar stands in for it: the window's own buttons sit at its left end, a press on its bare
ground drags the window and a double click zooms it, as the title bar's would. `--plain-window` opens the plain
1920×960 window instead; a capture, `make perf`, a headless run and `--always-on-top` always do.

The plain desktop window is 1920×960. The pixel scale is fixed (default 2×); `-` / `=` step through 2×, 4×, 6×, 8×.
A bigger window shows more floor, never bigger pixels; a window too small for the scale drops to the largest even scale
that fits. The scale is the whole window's content scale (the HUD scales too), and changing it never re-lays out or
rebuilds pods or people. Scales are even so that every texel of the density-2 art lands on whole screen pixels. So the
default window has only 2× (`=` does nothing), 4× needs at least 1920×1280, and 4K (3840×2160) has 2×, 4× and 6×. Below
960×640 (which cannot hold 2×'s 480×320) the office falls to 1×: the world is drawn at one screen pixel per unit, texels
are halved and outlines break into dots. That is a degraded fallback below the supported size, not a scale. The mock
showroom is a fixed 800×480 picture.

**Frame cap.** The live office caps its own frame rate: 60 while someone is using it (a key, click, wheel, drag or
trackpad gesture in the last 1.5 s), 30 when still, 12 in the background, 8 minimised. Merely moving the mouse over it
does not count, and input always reaches the office. Minimised stays at 8 because below 7.5 fps Godot runs at most 8
physics steps per frame, which would slow frame-counted timers (request timeouts, snapshot fallback, machine list
polling, reconnect backoff). `--fps=<n>` fixes the cap at n, `--fps=0` removes it; without `--fps=`, Godot's own
`--max-fps` is honoured. Headless runs (tests, CI) never change the frame rate.

## Alerts when the window is in the background

Only for changes observed in this run; the first snapshot, reconnects and launches never alert.

- The window title gets `(N)` in front, N being the blocked agents (the top bar's blocked cards and tally).
- The Dock icon bounces once (on macOS a continuous bounce until you switch back) when an agent is still blocked after
  3 seconds; at most once per time away, never for herdr's own focused pane.
- **Chime** (off by default): two rising tones for blocked, one softer, lower tone for done, at most one per refresh and
  once per pane per 10 seconds. Toggle it with **CHIME OFF / CHIME ON** right of the top bar's strip. The
  choice is saved in `user://herdstead.cfg`, section `[alerts]`, key `chime` (on macOS the file is
  `~/Library/Application Support/Godot/app_userdata/Herdstead/herdstead.cfg`), and restored on the next start; only
  `true` turns it on. When the bar is narrow (below 640 units) the switch gives way; widen the
  window to reach it. `--chime` turns it on for this run whatever the file says; the switch can still turn it off.
- `--no-bounce` skips the Dock bounce; `--no-title-count` leaves the title alone.
- Screenshots (`--capture=`) never bounce or sound and neither read nor write the key; tests never write it either.

There are no system banners and no catch-up notifications. Alerts are not herdr requests, so `--read-only` alerts too.

## herdr machines

Every SSH machine herdr has saved is its own herdr server. Every 10 seconds Herdstead runs `herdr machine list --json`
and keeps one `ssh -L` forward to each enabled machine. Each machine is its own map, online or offline on its own;
a disconnect dims and freezes only its map. It needs passwordless SSH, a host key you have already accepted by hand,
and herdr running on the remote. For debugging, `--machine-socket=<name>=/absolute/path/herdr.sock` attaches a local
socket as a machine. Forwarding, cleanup, target validation, the debug hook and what has been verified are in
[MACHINES](MACHINES.md).

## Themes and art

**Packs.** One theme ships: Studio (`daylight`). Dusk Shift, a palette derived from it by a recipe, was
retired on 2026-09-29: night is to be a light over the one pack, not a second pack. Each runtime pack has logical 32×32 tiles (wood floor, open corridor, walls)
at density 2 (64×64 texels per tile, nearest-neighbour; the build doubles 1× sources into 2×2 blocks),
standalone props (window, door, plants, a framed picture, the pantry counter, the zones' partition kit, a side table, the
small paper stack and the idle mug), a desk-item library of 5 everyday objects and 3 white
cats, the shared pod family (desks, low screen, apron, chair, laptop), state and UI icons (herdr's five states, starting, lost
and connected, the seat mark, the panels), a native TileSet, four single-image SpriteFrames (for export only), a semantic manifest and the fonts.
The full spec is [ASSET_SPEC](ASSET_SPEC.md), the painter's brief is [ARTIST_BRIEF](ARTIST_BRIEF.md), and depth and
collision rules are in [WORLD_MODEL](WORLD_MODEL.md).

**Choosing a pack.** The office scans `res://assets/*/manifest.json` at start, sorted by pack id; `--pack=` or the saved
choice picks one. Switching rebuilds the backdrop and floor; the HUD re-dresses in place (a new Theme, new textures, no node
rebuilt). The herdr connection is untouched: camera, selection, pixel scale and online state stay. The choice is saved in
`user://herdstead.cfg` and restored; precedence is `--pack=` > saved > the scene default (daylight). A saved path that no
longer exists falls back to the default with a warning. Capture runs do not write the file. An exported build only sees
files packed into its PCK, so the export's non-resource include filter must contain `*.json`.

**Editing art.** Python 3.11+ and Pillow are only needed after editing source PNGs.

```sh
make setup           # python3 -m venv .venv + tools/requirements-dev.txt

# Edit PNGs under art/daylight/, keeping size, pivot and palette rules.
# A new image = the PNG + one entry in pack.json + make art; there is no second ID list in Python.
.venv/bin/python tools/build_assets.py      # rebuilds every pack.json under art/
.venv/bin/python tools/build_table_assets.py
.venv/bin/python tools/build_pixel_people.py
.venv/bin/python tools/build_portraits.py
make test-art        # the four Python contract tests

# The contract tests can run against any pack source (default art/daylight).
.venv/bin/python tools/test_assets.py --source /path/to/pack -v
HERDSTEAD_PACK_SOURCE=/path/to/pack .venv/bin/python tools/test_assets.py -v

make import          # godot --headless --editor --import --quit (GODOT=… for another binary)
make check-packs     # validate every pack under assets/ against scripts/art/art_contract.gd
make run
```

`make art` is those four builders plus `tools/check_build_clean.py`, the same chain CI runs: it requires the rebuild to
match the commit exactly (`assets/`), so it passes only after the new PNGs are committed.

- `art/daylight/` is the only hand-edited source; `assets/<id>/` is a build product, and the build never writes back. Remove an entry from `pack.json` and `make art` prunes the orphan PNG (with its `.import`),
  printing `PRUNED:`, so a deletion shows up as drift to commit.
- The builder rejects wrong sizes, soft alpha, pivots out of bounds, duplicate atlas cells and references to missing
  badges or animations. **Which semantic IDs a pack has, and their sizes, is decided by `pack.json` alone; which ones the
  scenes use is decided on the GDScript side**, in `scripts/art/art_contract.gd`, next to the code that uses them.
  `make check-packs` (in `make check` and CI) rejects a pack missing a key, and prints `PACK_UNUSED:` lines for IDs a pack
  has that the contract does not ask for (informational only).
- Artist guide canvases with pivots live in `docs/templates/`:

```sh
.venv/bin/python tools/artist_templates.py --source art/daylight --output docs/templates --density 2
.venv/bin/python tools/artist_templates.py --source art/daylight --output /tmp/blank-templates --blank
```

Pixel people have their own tools: `make people-templates OUT=/abs/new-dir` exports the painter's canvases, guide layers
and key-colour legend; `make people-skins` cuts or checks part skins; `make people` opens the pixel people showroom.
Portraits too: `make portrait-parts` checks the painted parts, prints a reference to paint on (`REF=<part> OUT=<dir>`)
or cuts a part from a pixelized picture (`CUT=<png> PART=<part> SHAPE=<option>`, `DROP=1`), and
`make portrait-sheet OUT=<empty dir>` writes a review contact sheet (docs/ASSET_SPEC.md, "Portraits").

**A whole new skin.**

```sh
cp -R art/daylight art/my-theme
# Change the PNGs, palette and name in art/my-theme; keep the v1 semantic IDs and geometry.
.venv/bin/python tools/build_assets.py --source art/my-theme --output assets/my-theme
make import
godot --path . -- --pack=res://assets/my-theme/manifest.json
godot --path . scenes/preview.tscn -- --pack=res://assets/my-theme/manifest.json
```

A palette-only theme derived by a recipe is gone with Dusk Shift; `tools/recolour.py` keeps the exact per-pixel
substitution the pixel people build still uses (an ambiguous palette or an off-palette pixel is refused, by file and
coordinates).

**High-density packs.** A schema v2 pack (up to 256 px per tile, see [ASSET_SPEC](ASSET_SPEC.md)) builds and loads the
same way. Textures load exactly as built; `density` only means "texels per unit", and nodes always scale back by
1/density. When the screen scale is below the pack's density the GPU minifies with mipmaps (scale 8 shows a 256 px pack
1:1). The project's import default is "no mipmaps" for the nearest families (the shipped density-2 packs are 1:1 at the
minimum scale of 2 and never minified), so a pack placed in `assets/` that will be minified (density 4, 8 or `linear`)
needs `mipmaps/generate=true` in each PNG's `.import`; `tools/test_art.gd` checks this per asset family (see
[ASSET_SPEC](ASSET_SPEC.md), "Import policy by asset family"). `--pack=` also takes an absolute path outside `res://`
(for example the build output of a pack in progress); its PNGs and fonts are then read directly, not imported.
`manifest_path` can also be set on the Office or Preview root node in the Inspector. Hand-painted TileMaps store atlas
coordinates, so a same-spec reskin should keep atlas slots; procedural scenes look tiles up by semantic ID and can
reorder the atlas.

**Day and night.** The one pack is lit by the local clock (`DayLight`, `scripts/world/day_light.gd`): day from 07:00 to
18:00, night otherwise, fading over half an hour round each. At night the world (not the HUD, which is its own canvas
layer) is darker and cooler through a `CanvasModulate`, the desk lamps and chair shadows draw harder, and the windows show
the night view (`window_night`, a texture swap). `T` turns the light over: following the clock, the other one holds until
the clock's own day or night turns. `--light=day|night` holds it (and T then swaps it); a capture holds the day unless it
asks, so screenshots never depend on the time they are taken. The time of day binds no herdr field: it is lighting, not a
signal, and a lost connection is still its own grey tint, with everyone frozen, on top of it.

**Offline tint.** A disconnected office (or a machine's map) is tinted. A pack may set an optional top-level
`"stale_modulate": "8f96b8"` (6 lower-case hex digits) in `pack.json` / `manifest.json`; without it the tint is
`Color(0.65, 0.65, 0.65)`. It is an optional additive key (`schema_version` stays 1), read through `ArtPack.stale_tint`.
A dark pack should set its own: a 0.65 grey crushes an already dark picture (the retired dusk pack used a bluish,
lighter `8f96b8`).

**Agent badges.** All 23 canonical agent IDs in herdr's registry are in `data/agent_catalog.json`: `pi`, `claude`,
`codex`, `gemini`, `cursor`, `devin`, `agy`, `cline`, `omp`, `opencode`, `copilot`, `kimi`, `kiro`, `droid`, `amp`,
`grok`, `hermes`, `kilo`, `qodercli`, `qwen`, `letta`, `maki`, `muse`. Third-party logos that could be obtained are kept
as separate badges with their sources recorded in `assets/agent_badges/ATTRIBUTIONS.md`; the rest are monograms
Herdstead generates. Logos appear only in the Avatar Studio's agent list; people in the office do not wear them.

## Screenshots and performance

Screenshots need a display; never add `--headless`.

```sh
make capture                  # the standard set, into build/captures
make capture OUT=/tmp/shots
CAPTURE_SET=ci make capture   # only the key set: showrooms, pixel people and office at 2x and 4x

# One native-viewport shot. The live scene waits for the first snapshot; with herdr unreachable it shoots OFFLINE after 8 s.
godot --path . -- --capture=/absolute/path/office.png
godot --path . -- --wait=20 --capture=/absolute/path/office.png   # wait 20 more seconds
godot --path . -- --space=3 --capture=/absolute/path/office.png    # Local's zone 3 (by herdr workspace number)

godot --path . scenes/preview.tscn -- --capture=/absolute/path/preview.png
godot --path . scenes/preview.tscn -- --offline --capture=/absolute/path/offline.png
godot --path . scenes/preview.tscn -- --overview=open --capture=/absolute/path/overview.png   # a two-hour fake log
godot --path . scenes/people_showroom.tscn -- --zoom=2 --capture=/absolute/path/people.png
godot --path . scenes/people_showroom.tscn -- --view=options --zoom=2 --capture=/absolute/path/options.png

# 28 real rendered frames, for checking typing, blinking, raised hands and pivots
godot --path . scenes/preview.tscn -- --record-dir=/absolute/path/frames

# Every asset, props on light and dark backgrounds to check transparent edges (--source takes any pack)
.venv/bin/python tools/contact_sheet.py --output /absolute/path/contact-sheet.png
```

`make capture` shoots the showrooms, the live office against a fake herdr (read-only) at 2× and 4× (4× in a 1920×1280
window) and the 480×320 minimum screen, and every panel and state worth looking at: the HISTORY page, the EVENTS
page's scrollbar, NEWS and EVENTS, OVERVIEW, lens and pointing, strategic view, machine chips and edge arrows with mezzanines and
an offline machine (`spaces-*`), the agent card in answer mode, START AGENT, NEW PANE BESIDE, Close and Worktree, and launches in
progress. A missing image fails the run. Every step has a watchdog: a step that outlives its own `--wait=` plus
`CAPTURE_MARGIN` seconds (default 60) is killed and the run fails naming that image. `CAPTURE_SET=ci` shoots only
both showrooms, the pixel people and the live office at 2× and 4× (about half a minute on CI; the whole set takes over
ten). `make walk-strips` renders
frame-by-frame strips of people walking. On Linux without a desktop, use
`xvfb-run -a godot ... --display-driver x11 --audio-driver Dummy`; `make capture` wraps itself that way when `DISPLAY` is
unset and `xvfb` is installed.

Performance is also measured in a window:

```sh
# medium (3 workspaces, 36 panes, all drawn: one map) and stress (1 workspace, 80 panes) against a fake herdr, default cap and --fps=0:
# CPU, fps, nodes, draw calls, texture memory and refresh() time, median of 3 rounds
make perf
make perf RUNS=5 FIGURES=1    # more rounds, plus 80 seated working people
make perf WALKS=1             # also people walking on the stress map
```

Extra rows: `spaces30` (30 workspaces of one tab each on one map, 189 panes, ten of them mezzanines: many zones, signs
and cards), `overview` (the stress map zoomed out so the whole map is on screen; unrelated to OVERVIEW),
`stress+overview`, `stress+lens`, `stress+strategic`, `stress400` / `stress400+strategic` (400 panes) and
`stress400+events` (the bottom panel on its EVENTS page). `refresh_ms` counts only `office.refresh()`, not the fleet feeding the state log. In the
foreground the default cap is 30 and in the background 12; `max_fps` in the output says which was measured.

## Limits

- **Writes come only from gestures.** The only writes are the ones a person makes on the bottom panel, in answer mode or
  in the terminal monitor. The one request not caused by a gesture is a single read-only `agent.get` when a launch this
  run started reaches its deadline. Refreshes, timers, state changes and the event stream never write. Nothing is
  approved automatically, nothing is inferred from terminal text, no agent is started automatically, and writes are never
  retried; an unknown result is shown as unknown. The reread before sending shortens the window between seeing and
  sending but does not close it (herdr has no "send only if the screen is still this" call).
- No hook installation, system notifications or scheduling. The only sound is the two generated chime tones, off by
  default.
- People walk only when an observation changes: no wandering, no queues. The office has no other tweens, fades or lift
  animation.
- Adding or removing panes and tabs updates only the affected nodes; panes that stay keep their person and animation.
  Changing machine or theme rebuilds the current world (plans and camera are cached, not every map's people); panning
  between zones of one map rebuilds nothing. An invalid
  or over-budget layout keeps the last valid picture and shows the error.
- Machine management is read-only: no add / remove / enable / disable / rename, nothing installed or started on the
  remote, no herdr 0.9.1 `--machine` CLI prefix (0.9.0 has neither it nor an event stream there), and disabled machines
  are not shown.
- If Herdstead is killed with SIGKILL or crashes, the `ssh -N` processes it started are reaped only at the next start. If
  the owner pid is reused by an unrelated live process, those leftovers are kept as "alive" until the start after that.

## Download and run the macOS app

The packaged app is `Herdstead-macos.zip` (universal: Apple Silicon and Intel); unzip it to get `Herdstead.app`. No Godot
install is needed. Releases are uploaded by hand to GitHub Releases from a local export.

The app is only ad-hoc signed, with no Developer ID signature or notarisation. A download carries the quarantine flag and
Gatekeeper blocks the first double-click: right-click → Open → Open in Finder, or "Open Anyway" at the bottom of
System Settings → Privacy & Security, or clear the flag. An app you exported yourself has no flag.

```sh
xattr -dr com.apple.quarantine Herdstead.app
```

A double-click connects to the default session (`~/.config/herdr/herdr.sock`); an app started from Finder does not see
the shell's `HERDR_SOCKET_PATH`. For another session or for `--pack` / `--capture`, start it from a terminal with the
options after `--`:

```sh
open Herdstead.app --args -- --socket=/absolute/path/herdr.sock
Herdstead.app/Contents/MacOS/Herdstead -- --socket=/absolute/path/herdr.sock   # log in the terminal
```

## Export locally

Needs Godot 4.7.2 and the matching export templates. The script does not download templates (about 1.3 GB); without
them it prints the install command and exits. They can also be installed from the editor (Editor → Manage Export
Templates).

```sh
make export                       # import, then export build/Herdstead.app and build/Herdstead-macos.zip
make export GODOT=/path/to/godot  # a specific Godot binary
```

`export_presets.cfg` has a single `macOS` preset with built-in ad-hoc signing and no certificate, Team ID or notarisation
credentials; never put them in that file. The non-resource include filter is `*.json, *OFL.txt, *LICENSES.txt`: the
fonts' licence files are not Godot resources and would be left out of the PCK otherwise (`*.json` is already packed as a resource in
4.7; it stays as insurance). `tools/` is not packed; `build/` is git-ignored. macOS universal / arm64 export needs Import
ETC2 ASTC on in `project.godot`; all textures are lossless, so the switch changes no art.

To check the pack's contents, no templates are needed:

```sh
make pack                                       # export the PCK, then run check_pack.gd on every pack in it
(cd build && godot --main-pack Herdstead.pck)   # run the exported PCK with the editor binary
```

## CI

`.github/workflows/ci.yml` runs on every push to main and every pull request (Ubuntu, never a real herdr). Each step calls
a Makefile target where one exists. The quality job and four Godot shards run in separate checkouts on separate runners.
They share `.github/actions/setup-ci/action.yml` for Python, Godot and the fonts/display packages. The Godot version and
sha512 stay in the workflow's top-level `env`; `actions/cache` caches only the download, verified even on a cache hit,
never the `.godot` import cache. This trades more concurrent runners for a shorter wait, not less coverage.

The quality job runs:

1. `make lint`: gdlint over `scripts/` and `tools/` (config in `gdlintrc`) and a gdformat check.
2. `make docs-check`: every backticked repo path and `make` target in README.md, AGENTS.md, docs/MACHINES.md and
   docs/MANUAL.md exists.
3. `make art`: rebuild every pack under `art/` and compare `assets/` with the commit (PNGs by pixel, since zlib output
   differs by platform; other files by byte).
4. `make test-art`: the three Python art contract tests.
5. `make import`, then `make test-tools` and `make test-harness`: developer CLI and real-engine case-runner contracts,
   including shard coverage, invalid selections, isolated fakes and retained failure logs. Python tests run once, not per shard.
6. `make check-scripts`: load every script and scene; warnings set to Error in `project.godot` fail here.
7. `make smoke`: run the main scene for one frame headless. Godot steps fail on `SCRIPT ERROR` / `Parse Error` in the log,
   because Godot still exits 0.
8. `make check-packs`: validate every pack under `assets/` with `scripts/art/art_contract.gd`.
9. `make pack`: export the PCK and run the same checks inside it with `tools/check_pack.gd` (manifest, font licences,
   every asset).
10. `CAPTURE_SET=ci make capture` (with `xvfb` and software GL): the key set only, uploading every screenshot with
    `actions/upload-artifact`, pass or fail.

The matrix jobs run `make test-shard SHARD=1/4` through `SHARD=4/4`. The runner distributes its actual invocation list
round-robin, so every Godot suite runs exactly once. No second suite registry or timing file needs to stay in sync.
Each shard imports its checkout and runs script/pack load checks, then its whole suites sequentially, with unchanged
case floors, completion markers, script-error checks, timeouts and closing fake-herdr audits. A failed shard does not
cancel the others. Every shard uploads its complete output and any retained failure logs as its own artifact.

Use `make test-list` to see the full list, or add `SHARD=1/4` to see that shard without importing or starting processes.
Shards are 1-based; zeroes, malformed values and counts that would leave any shard empty fail before work starts.
The direct runner rejects SHARD combined with SUITES, CASE or TIER; the Make shard targets clear those diagnostic filters.
Local shards must run sequentially, never in parallel against one checkout. Failure logs still print full-suite and exact-case
reruns via `make test-suite`, which clears any inherited SHARD.

The final job retains the `check` status name and requires both quality and every shard to succeed; failed, cancelled or
skipped dependencies cannot turn the aggregate green. `make check` remains the full, sequential local gate before a push:
it runs Python tests once, then sets `HERDSTEAD_SKIP_LOAD_CHECKS=1` and `HERDSTEAD_SKIP_PYTHON_TESTS=1` for the Godot runner.
A plain `make test` retains load checks and the table/tool/harness contracts. Full and quick gates clear SHARD alongside
the editing filters. One shard passing is not a replacement for either full gate.

Screenshots are for looking at; there is no golden comparison. CI does not export the `.app` or publish releases.
`tools/probe_herdr.gd` needs a real herdr and `make perf` needs a window and varies by machine, so neither runs in CI or
`make check`.

## Repository layout

```text
art/daylight/            hand-edited source pack: PNGs, pack.json, table/ (the pod family), fonts/
art/pixel_people/        people.json, the pixel people contract (canvas, pivot, facings, layers, tracks,
                         key colours, slots, looks), optional hand-drawn strips and skins/<facing>/
art/portraits/           portraits.json, the portraits contract (canvas, the nine layers bound to the people's
                         look slots, the extras, the face box), optional painted parts/
art/agent_badges/        agent logo sources and ATTRIBUTIONS.md
assets/<id>/             runtime packs built from art/ (daylight); never edited here
assets/pixel_people/     people_manifest.json and one packed sheet per facing
assets/portraits/        portraits_manifest.json and the one packed sheet of portrait cells
assets/agent_badges/     the 23 agent logos (Avatar Studio only) and ATTRIBUTIONS.md
data/agent_catalog.json  herdr agent IDs, display names, badge sources, each provider's default clothes
scenes/office.tscn       main scene, connects to herdr
scenes/preview.tscn      mock showroom (no herdr)
scenes/avatar_studio.tscn, scenes/people_showroom.tscn
scenes/ui/               HUD scenes: hud.tscn (layout lives here), bar (portrait_card, portrait_fold, machine_chip),
                         edge_arrows / edge_arrow, bottom_panel (its pages: inspector, the agent card;
                         history_list / history_row; event list / event row; news in its top row),
                         overview, strategic, terminal_monitor
scenes/world/            world prefabs: table (a pod), station, decor, chip, machine_plate, zone_sign
scenes/people/           pixel_person.tscn, pixel_portrait.tscn and the showroom cells
scripts/office.gd        OfficeScene, the composition root
scripts/herdr_client.gd  read-only socket client (ping, session.snapshot, events.subscribe)
scripts/herdr_commands.gd  HerdrCommands, the write boundary; not constructed under --read-only
scripts/herdr_fleet.gd   Local + SSH machines; the only thing the office reads data from; feeds the state log
scripts/machine_link.gd, machine_roster.gd, child_process.gd   ssh -L forwards, herdr machine list, bounded child processes
scripts/office_projection.gd  pure projection: typed snapshot → OfficeFrame
scripts/office_*.gd      navigator, camera, lens, alerts, draw helpers, window (fill the screen, bar as title bar),
                         question tips, new-pane follow, view marks (the edge arrows, as the view moves)
scripts/model/           typed models: HerdrSnapshot (the only reader of raw snapshots), OfficeFrame, StateLog,
                         command context / ticket / refusal / answers / results, layout plans
                         PickFollowsWrite (pure: where the pick goes after a write the office sent),
                         DisplayName (pure: what every surface calls a pane),
                         PortraitBarModel (pure: who the top bar's strip shows, and its fold ladder)
scripts/layout/          map and zone planning, seat planning, walk graph, validation
scripts/world/           pods (table.gd), stations, chips, the floor view, machine plate, zone signs, shell,
                         presentation (walking), pointer
scripts/ui/              HUD scripts: hud, theme, bar (portrait card, portrait fold, machine chip), edge arrows, bottom
                         panel (bottom_panel; inspector writes what card_picture, pure, says it shows; card_details,
                         card_words, card_actions, launch_block; history_list / history_row), monitor, NEWS, EVENTS,
                         OVERVIEW, strategic view
scripts/art/             typed art pack models; the only readers of manifest JSON
scripts/people/          PixelPerson and PixelPortrait prefab scripts
tools/                   builders, contract tests, fake herdr / fake ssh, test suites (test_*.gd), capture and perf
tools/fixtures/          snapshots, monitor screen dumps, herdr_methods.json
docs/                    this manual, WRITE_BOUNDARY, VISUAL_LANGUAGE, WORLD_MODEL, ASSET_SPEC, ARTIST_BRIEF,
                         MACHINES, preview.png and showroom.png (README screenshots), templates/ (generated guide canvases)
Makefile                 every command; `make` lists them
.github/workflows/ci.yml CI
.github/actions/setup-ci/ shared CI tool installation (Python, verified Godot, fonts/display)
```

The data side (`herdr_client`, `herdr_commands`, `machine_link`, `machine_roster`, `herdr_fleet`) knows nothing about
rendering. The UI side never touches client, link, roster or command objects; it reads only what `HerdrFleet` gives
and writes only through its typed calls. The contributor rules are in [AGENTS.md](../AGENTS.md).

## Licence

Code and art (tiles, furniture, characters, UI icons, theme palettes) are [MIT](../LICENSE): fork, reskin and
redistribute freely, keeping the copyright notice. The bundled Fusion Pixel fonts are not: they are under the SIL OFL 1.1
and their component fonts' own licences, Tiny5 under the SIL OFL 1.1, and the `FusionPixel-*-LICENSES.txt` and `OFL.txt`
files next to them in each pack's `fonts/` directory must travel with them. Third-party
agent logos keep their own terms; sources are listed in `assets/agent_badges/ATTRIBUTIONS.md`.
