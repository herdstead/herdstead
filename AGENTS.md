# AGENTS.md

For the AI agents (and people) working in this repository. The user manual is [docs/MANUAL.md](docs/MANUAL.md); this file holds only the rules for working here.
What each thing in the picture stands for in herdr, and where something new should be drawn, is in the [visual language](docs/VISUAL_LANGUAGE.md): **everything in the world is either a signal bound to a field, or furniture that does not change with state.**

Herdstead uses Godot 4.7.2 to draw herdr's machines / workspaces / tabs / panes / agents as an office building. **It is an operator by default, but only through one write boundary**:
the client sends only `ping`, `session.snapshot` and `events.subscribe`; every other request is sent only by `scripts/herdr_commands.gd` (`HerdrCommands`).
Its allowlist is twelve methods: the agent card's terminal preview (`pane.read`), **Switch herdr here** (`pane.focus`), and the two inputs of answer mode:
answer keys (`pane.send_keys`, only `1`–`9`, `y`, `n`, `enter`, `esc`, only for a blocked agent, including one still starting) and a one-line reply (`agent.prompt` with `target` + `text`;
herdr types it and presses Enter itself; only for an idle / done agent); **Start agent** (`agent.start`, only on a shell pane, only with a kind seen in this machine's snapshot, the name generated, the screen re-read before sending and the last line judged for whether it looks like a prompt)
and **New pane** (`pane.split`, always an explicit `target_pane_id` and `focus: false`, the direction taken from the pane's shape, refused when the pane is too small), plus one read-only `agent.get` for a launch the office sent itself that has reached its deadline (so that herdr settles its launch timeout; see invariant 12);
three verbs in the same block of the staff panel, sent only by mouse clicks: **Close** (`pane.close`, only `pane_id`, two real clicks, the first of which only states what will close), **New space** (`workspace.create`, only `cwd` + `focus: false`, the cwd being the pane's directory from the snapshot, verbatim)
and **Worktree** (`worktree.create`, only `workspace_id` + `branch` + `label` (= branch) + `focus: false`; the branch name is validated and never rewritten; the checkout lands in herdr's own configured directory);
the terminal monitor ([write boundary §3](docs/WRITE_BOUNDARY.md)): screen reads (`pane.read` `visible` / `recent`, `ansi`) and pass-through input
(`pane.send_keys` with the raw key table, typing through `pane.send_text`, pasting through `pane.send_input` — the only remaining use of `pane.send_input`); and the question excerpt in a station bubble's hover tooltip (`pane.read` `detection`, on-screen blocked panes only; see invariant 12). Under `--read-only` it is never constructed.
The only herdr command line the office runs is `herdr machine list --json`. Never add a request outside the allowlist; to add one, follow "If you change X, also update Y" below, and read [write boundary §1](docs/WRITE_BOUNDARY.md) first.

## Commands

Commands live only in the `Makefile`; `make help` lists them all. A new everyday command becomes a target, not prose.

| To do | Command |
|---|---|
| Every check run before committing and on CI | `make check` |
| Only the Godot + Python tests | `make test` |
| Format GDScript (`make lint` checks it) | `make fmt` |
| Run the main scene headless for one frame; fail on any script error in the log (the same step as CI) | `make smoke` |
| Every repo path and make target the entry docs name in backticks exists (the docs are listed in `tools/check_docs.py`; `make check` includes this) | `make docs-check` |
| Measure the office's CPU, frame rate, node count, draw calls, texture memory and refresh time in a window (fake herdr; not in check or CI) | `make perf`, optionally `RUNS=5`, `FIGURES=1`, `WALKS=1` (frame time while people walk) |
| Rebuild `assets/` after changing `art/` | `make art` |
| Export the pixel-people artist templates (canvases, guide layers, key-colour legend; the output directory must be empty) | `make people-templates OUT=/abs/new-dir` |
| Cut pixel-people part skins from a pixelized frame, or only check the existing skins (the reference frame and the pixelize parameters come from `reference` in `tools/people_skins.py`) | `make people-skins`; to cut, add `CUT=/abs/frame.png PARTS=head,torso`; optionally `FACING=front`, `DROP=1` (drop texels outside the part and print each one; refused by default), `WEAR=hair_short` (hair / hat drawn in the image but not cut, for alignment) |
| Screenshots (showroom + office under a fake herdr, 2x and 4x; 4x in a 1920×1280 window) | `make capture OUT=/abs/dir` |
| Run | `make run`, or `godot --path . -- --socket=…` (flags in the [manual](docs/MANUAL.md)); add `--read-only` to watch without writing. **Operator is the default**: when running, capturing or measuring beside someone else's herdr session, always point `--socket=` at a fake herdr or add `--read-only` |

Godot's exit code cannot be trusted: it is still 0 when a script fails. The gates read the log for `SCRIPT ERROR` / `Parse Error` and for each stage's `… OK` marker. The scripts already do this; do not bypass them.

## Code map

```text
herdr socket ─ HerdrClient ─┐
herdr socket ─ HerdrCommands┤ (write boundary: one connection per command; absent under --read-only)
ssh -L ─ MachineLink ───────┼─ HerdrFleet ── typed snapshot (HerdrSnapshot, read once by from_wire())
herdr machine list ─ Roster ┘        │      commands: CommandContext in, CommandTicket out (the agent card's preview, switch and answers, start and split; LaunchWatch follows a launch from snapshots only)
                                     │      state log: StateLog (each pane's state segments and a bounded event ring since opening; copies only the client's StateClock)
                                     ▼
          OfficeProjection (pure static functions) → one OfficeFrame per refresh (scripts/model)
                                     ▼
   office.gd is the composition root: OfficeNavigator decides what to show, FloorPlanCache plans floors, OfficeCamera pans
   (OfficeAttention writes the window title and its (N); OfficeAlerts only reads the state log: bounces the Dock when not in front, optional chime)
                          │                         │
                          ▼                         ▼
        OfficeFloorView + floor sign (scenes/world):   OfficeHud (scenes/ui):
        Ground + Sorted (y-sort), table / station / person   top bar counters (OfficeTotals) / left FLOORS minimap (a narrow rail under 1280) + signpost at the world's right edge /
                                                             right drawer (closed at start): the AGENTS tab's agent list (AgentListModel; its History group comes from StateLog via AgentHistory) and the EVENTS tab /
                                                             bottom staff panel (agent card, `inspector`; compact by default: a card on tall screens, one row below) + NEXT (NextModel's verbs) / bottom row NEWS (NewsItem) /
                                                             OVERVIEW, opened by PANES or O (OverviewModel; the timeline is a Control drawn in _draw())
        OfficeLens: the lens while L is held (one duration row per station, carpet tint, furniture dimmed); OfficePointer: a dashed frame off the station while a HUD row is hovered
        OfficeStrategic: the strategic view on `S` (a schematic of this floor over the world area; StrategicModel in, StrategicLayout lays out, %Plan's _draw() draws)
        OfficePresentation: people walk in and out of the lift doors, change seats, go to the pantry and back to their seats;
        who rests where is decided only by OfficeRests (pure functions); they walk on OfficeWalkGraph (the same graph FloorPlanCache's validator uses)
                          └── ArtPack + PixelPeople + TablePack (scripts/art, semantic ID → texture, palette)
```

## Invariants (do not commit a change that breaks one)

1. **The data layer knows nothing of rendering; the rendering layer never touches connections.** `herdr_client`, `herdr_commands`, `machine_link`, `machine_roster` and `herdr_fleet` hold no nodes and no assets;
   `office`, `scripts/ui` and `scripts/world` only read the data `HerdrFleet` hands out and never touch client / link / roster / commands objects;
   the agent card also reads and writes only through `HerdrFleet`'s typed calls (`context_for` / `read_pane` / `focus_pane` / `send_keys` / `send_line` /
   `can_operate` / `preview_shown` / `last_write` / `must_look`; start and split: `start_agent` / `split_pane` / `agent_kinds` / `next_agent_name` /
   `can_start` / `can_split` / `split_direction` / `launch_of` / `launch_outcome` and the static `prompt_state` / `prompt_refusal`; the three staff-panel verbs: `close_pane` / `create_space` / `create_worktree` /
   `can_close` / `can_space` / `can_worktree` / `close_scope` / `pane_cwd` / `worktree_context` and the static `branch_refusal`);
   `office.gd` decides whether a shell's card can expand, keeps the selection on an agent it started, and auto-selects the new pane of a split, reading only `launch_of` / `last_write` / `agent_kinds` / `generation`; the terminal monitor likewise goes only through `read_screen` / `type_keys` / `type_text` /
   `paste` / `input_refusal` / `screen_refusal` / `pane_size` / `queued_input`; the office's question reader (`OfficeQuestionReader`, the station bubbles)
   also only through `context_for` / `read_pane`. NEWS / EVENTS / OVERVIEW, the agent list's History group (`AgentHistory`), the top bar's `max` / hover durations, and the durations in the lens and the strategic view read the state log only through `state_log()` ("how long in this state" is computed in exactly one place, `StateLog.wait_of()`); the state log is fed only in the fleet layer, and models never call `Time.*`.
2. **Raw JSON is read once, at the edge.** The art pack's manifest is read only by `from_manifest()` in `scripts/art/`; after that everything is typed fields.
   **The raw snapshot dictionary is read in exactly one place**: `HerdrSnapshot.from_wire()`, and a state event that changes a pane goes through the same rules (`HerdrSnapshot.Pane.apply_status()`);
   `HerdrClient` checks only the envelope (`result.snapshot` is an object, `panes` is a list). `OfficeProjection` and all other code take only the typed `HerdrSnapshot` and models.
   Do not reintroduce string-keyed dictionaries or "arrays as tuples" as models; a new field goes on a class in `scripts/model/`.
3. **A pane id is unique only within one machine.** Wherever a station or a floor is identified, use the composite key (`HerdrFleet.pane_key`), never a bare `pane_id`.
4. **Disconnected is not idle.** A disconnected machine keeps its last picture, dimmed and frozen, with its counts at zero; never draw a lost connection as any kind of activity.
5. **Depth comes only from Y-sort.** `z_index` takes exactly one value, `OfficeWorld.OVERLAY_Z`; the origin is the foot point; the in-table geometry constants live only in `scripts/world/table.gd`.
   The full rules are in the [world model](docs/WORLD_MODEL.md); an approach listed under its "Abandoned approaches" must not come back under any name.
6. **Textures are used as they are.** Images are never scaled, resampled or repacked at runtime. `density` only means "texture pixels per unit"; nodes are always scaled back by `1/density`,
   and the sampling follows the asset family (the pack, the pixel people and the long tables are one family each). Every new Sprite goes through its family's `dress()` (`ArtFamily`). A zoom change rebuilds no node.
7. **HUD layout lives in scenes, not in scripts.** `scripts/ui/*.gd` has no coordinate literals and no `add_theme_*_override`; looks go through `HudTheme`'s
   `theme_type_variation`; a data change only updates properties of existing nodes, never destroys and rebuilds them. The world asks `OfficeHud.world_rect()` for its usable area and never hard-codes a panel width.
8. **Scene code finds assets only by semantic ID**, never by image path or atlas coordinates.
9. **Remote input is untrusted.** Remote snapshots, machine lists and ssh output always pass the existing sanitising and validation first, and all of them are bounded: one herdr NDJSON line
   is at most `HerdrClient.LINE_MAX` (32 MiB; over it, that channel counts as failed and a half line is never decoded; backoff then keeps growing until a snapshot is read again);
   a snapshot's record counts stay within `HerdrSnapshot`'s `MAX_*` (over them, the whole snapshot is refused: the previous picture stays, but that machine is treated as disconnected —
   dimmed, frozen, not counted online, see invariant 4 — until the next snapshot is read); a child process keeps only `ChildProcess`'s bounded tail;
   **every remote display string gets a grapheme-cluster cap at `from_wire` / `normalize`**: the workspace / tab / pane labels, titles, agent names,
   repo and checkout names and paths read by `HerdrSnapshot.from_wire()`, the machine names in `MachineRoster.normalize()`, and terminal text (`PaneReadResult` / `ScreenReadResult`) keep at most
   `TerminalText.CLUSTER_MAX` (8) code points per grapheme cluster, and a longer cluster keeps only its base character (an overlong cluster of combining marks / ZWJs can make the engine shape text for tens of seconds and freeze the whole office); ids and keys do not go through it;
   the monitor draws at most 400 × 200 cells.
   herdr lines, the machine list and forwarded sidecars are parsed only with `HerdrClient.parse_line()` (`JSON.parse_string` writes fragments it cannot read — possibly terminal text — into the log);
   requests to herdr are encoded only by `HerdrClient.request_line()`, whose encoder is the neutral `JsonText` (`scripts/json_text.gd`); the `AgentCatalog` save file uses the same one (`JSON.stringify` leaves control characters in, and writes 0x0B as the invalid `\v`).
   The ssh target is always a separate argv after `--`, never spliced into a shell string. Never add `StrictHostKeyChecking=no`.
10. GDScript warnings such as `unsafe_*`, `untyped_declaration` and `shadowed_*` are Errors, and `scripts/` and `tools/` have zero of them.
    Do not silence one with `@warning_ignore`: give the value a type (a typed class, `Dictionary[K, V]`, the accessor helpers in `tools/test_base.gd`).
11. Release builds use `--export-release`, which strips `assert()`: an error the runtime must handle uses `push_error` plus an explicit failure path, not assert.
12. **Writes go only through `HerdrCommands`.** Under `scripts/`, only `scripts/herdr_commands.gd` may spell a herdr method name other than the read-only three
    (`tools/test_commands.gd` checks this statically against `tools/fixtures/herdr_methods.json`). The full rules are in [docs/WRITE_BOUNDARY.md](docs/WRITE_BOUNDARY.md)
    (§1 the boundary, §2 answer mode, §3 raw mode, §4 Start agent and New pane, §5 Close, New space, Worktree, §6 measured herdr behaviour). The core, which every change keeps:
    - **Gestures only.** A command is triggered only by a user gesture happening now; refreshes, timers, state changes and the event stream never write.
      Answer keys are sent only by a real gesture in answer mode, and the keyboard's Enter never sends. Start agent, New pane, Close, New space and Worktree are mouse clicks on the staff panel only; the keyboard never triggers them.
    - **Context fixed at the gesture.** The `CommandContext` is fixed at the moment of the gesture — the machine and its generation, herdr's own spelling of the pane id,
      `PaneModel.identity_key()`, the card's binding version — and every later step checks that same object, never re-reading "the current selection". A refusal before sending is typed (`CommandRefusal`).
    - **Single-flight, never retried.** One write at a time, never retried automatically; a write whose reply is lost is "result unknown" and shown as such. Commands have their own connection, line cap and timeout,
      and a failure never changes the machine's online state.
    - **Audit.** Separate bounded write / read rings, in memory only, with no terminal text: a one-line reply records only its byte count; start and split record only the office's own words (kind, name, direction);
      close records the scope kind and the state word, New space the cwd's byte count, Worktree the branch name, never paths, labels or git text; raw mode records only category, event count and byte count, never key names or text.
    - **`--read-only` never constructs it.**
    - **Input to a terminal (answer mode, §2).** The key allowlist is compared literally; a line is validated at the send point (non-empty, ≤ 1024 bytes, no control / invisible / bidi / U+FFFD characters)
      and refused, never rewritten, when it fails. On press the card's displayed preview is frozen (`CommandPreview`); the same ticket takes the single-flight slot at the gesture, re-reads from the same source,
      re-checks against the latest fleet facts, compares literally and writes in the same frame. The one-line reply goes through `agent.prompt`: herdr itself refuses blocked agents and empty text but does not validate the text, so every client check stays.
      Answer keys (`pane.send_keys`) are allowed for a blocked agent that is still `launch_pending`; the one-line reply still refuses `launch_pending`.
      The re-read is only a best-effort guard against staleness and must **not** claim "it only approves the question you saw".
    - **Write-then-look.** Once a queued write ends (any result, a refusal after the re-read included; a refusal at the gesture does not count), every write on that pane stays closed
      until a preview read that started at least 0.5 seconds after that end comes back and is shown.
    - **Start agent and New pane (§4).** `agent.start` is one write on a shell pane, with the same pipeline as a one-line reply (context and full identity fixed at the gesture, preview frozen, `recent_unwrapped` re-read and compared literally,
      latest facts re-checked, single-flight, write-then-look), plus: the last line is judged by `PromptState` (PLAIN sends on one click; UNSURE needs a second real click on the same kind, within 10 seconds, with the same binding and the same preview —
      the confirmation is only a constraint on the card's gesture, since the boundary cannot tell a click from a `confirmed` passed in, so it re-reads and re-judges all the same; NO_PROMPT never sends, even confirmed). The kind comes only from the snapshot and the office generates the name;
      a name is refused within 5 seconds of the previous launch on the same pane ending, or when this run has already sent it (except the name of a launch herdr gave up at its deadline, `LaunchWatch.failed()`: herdr has released it).
      ACCEPTED only means herdr has started typing; progress and failure come only from snapshots (`LaunchWatch`), are only shown, and are never retried.
      `pane.split` is one write on the **target pane**, always with an explicit `target_pane_id` and `focus: false` and no `cwd`; the direction comes from the snapshot's rect and a minimum size is enforced. The new pane id in its result
      is used only to auto-select that pane (selection only), never for a second write: a launch there is another gesture on the new pane.
    - **Close, New space, Worktree (§5).** Mouse clicks in the staff panel's `%Launch` block, with the same pipeline as a split (context and full `identity_key()` fixed at the gesture, no screen read,
      latest facts re-checked before release, single-flight, write-then-look, never retried, a lost reply shown as "result unknown, the next snapshot decides"). `pane.close` sends only `pane_id` and needs **two real clicks**: the first only writes what will close in the explanation and the terminal strip
      (`CloseScope`: the pane / the table, floor or mezzanine the last pane takes with it; a working / blocked agent is named as killed at once) and starts 10 seconds; the second sends only with the same binding, the same identity and an unchanged scope signature.
      A change of selection or binding, a change of scope or state, entering answer mode, or the timeout cancels it. While a mezzanine is open, the button on the last pane of the repo's own floor is disabled (`GROUP_PARENT`) and nothing is sent:
      herdr would close the whole group. That is judged from the snapshot, where the parent's `worktree` field appears only after its first `worktree.create`; a parent the snapshot cannot show is stopped by herdr's own `confirmation_required`, which the card reports and never retries.
      `workspace.create` sends only `cwd` + `focus: false`, the cwd being the pane's snapshot `cwd` verbatim (`Pane.cwd_clean`: refused if sanitising changed it, if it is empty or if it is not absolute, because herdr silently falls back to `$HOME`), and refused if the directory changed by release;
      on an empty herdr the first workspace is focused regardless, and the tooltip says so.
      `worktree.create` sends only `workspace_id` (herdr's spelling, `wire_workspace_ids`) + `branch` + `label` (= branch) + `focus: false`, never `path` / `base` / `cwd` / `trust_repository`. The branch name is validated at the send point
      (`branch_refusal()`: whitespace, > 64 bytes, characters outside the set, shapes git refuses) and never rewritten, and refused if it changed between press and release; a mezzanine is never a source (`MEZZANINE_SOURCE`). Git's multi-line stderr keeps only a headline (`GitWords.headline()`:
      sanitised, cluster-capped, 200 characters); the raw text is never shown and never audited. The new workspace / pane ids in the result are used only to select that shell across floors (selection only), never for a second write.
    - **The one request a timer sends.** When a launch this run sent reaches its deadline (`LaunchWatch.TIMEOUT_MSEC`, 31 seconds) and the snapshot still shows the same terminal with the same name `launch_pending`,
      the boundary sends one read-only `agent.get` so that herdr settles its own launch timeout (its only side effect: releasing the pane and the name). At most once per launch, never asked again, never followed by a write;
      not asked when the machine was replaced or is gone, never for another client's launch; `--read-only` has no boundary, so it never asks.
    - **Raw mode (the terminal monitor's pass-through, §3, which revises §1 for this path only).** While the monitor has the keyboard, every key and every paste is itself a gesture. Key names come only from
      `HerdrCommands.raw_key_refusal()`'s table (the one measured against herdr 0.9.0: printable characters, `enter` / `tab` / `shift+tab` / `backspace` / `esc`,
      arrows with Ctrl / Alt / Shift / Ctrl+Shift, `f1`–`f12`, `ctrl+` letters and `[ \ ] ^ _ @`, `alt+` printable characters and so on; Home / End / PgUp / PgDn /
      Insert / Delete have no key name in herdr 0.9.0 and are refused with a message), on any pane (shells included) in any state, with no re-read and no write-then-look. Typing goes through `pane.send_text`
      (verbatim, never a bracketed paste, control characters refused); pasting goes only through `pane.send_input {text}`, refused whole, never truncated, when it holds ESC, C1, a control character other than Tab / newline / carriage return (the `HerdrCommands._control` set),
      a bidi control (the bidi part of the `HerdrCommands._invisible` set) or more than 64 KiB. On macOS, Option types characters; when it makes none (a dead key), nothing is sent.
      The context is still fixed at the gesture (the machine generation, the pane key and the **terminal id** — raw mode binds only the terminal, not the agent or session, so starting an agent in the shell
      or `/clear` keep input flowing; answer mode and Switch herdr here still bind the full `PaneModel.identity_key()`), and every write is re-checked against the latest fleet facts; when the terminal id changes or the pane is gone,
      input stops until **Follow new terminal** is clicked or the monitor is reopened. Closing the monitor makes every queued input not yet written CANCELLED, never sent; the one in flight ends normally. One frame's input of one kind merges into one request; each pane queues in order,
      with one request in flight, at most 256 queued events (overflow refuses the newest, `QUEUE_FULL`) and about 60 requests per second; a lost reply is recorded as "result unknown" and never resent, and later keys are still sent.
      When the machine is disconnected, the snapshot is not current, the machine was replaced or the protocol is unknown, everything queued is refused with its reason.
      The monitor reads the screen only while it is open, the machine is online with a current snapshot and the window is not minimized: 5 reads per second with focus, 1 without, one extra read right after each input and another 50 ms later,
      at most one read at a time; reads and polling never write. Under `--read-only` the monitor opens but neither reads nor sends, and says so.
    - **Reads that are not gestures.** The station bubble reader (`OfficeQuestionReader`, for the hover tooltip) is not a gesture and never writes: it reads only on-screen blocked panes (`PaneModel.asks()`, including one blocked while starting)
      on an online machine with a current snapshot, not covered by the terminal monitor or the OVERVIEW; one at a time, at least 10 seconds between the starts of two reads of the same pane (leaving blocked or changing floors does not reset it), none while minimized.
      It never calls `preview_shown`, does not count as "seen", and does not unlock write-then-look.
      Clicks in NEWS, EVENTS and OVERVIEW only select a pane (the same path as a list click) and never write; neither do the state log and their refreshes.

## If you change X, also update Y

| You changed | Also update |
|---|---|
| A semantic ID, palette key or state newly used by a scene / the HUD | `scripts/art/art_contract.gd` (`make check-packs` checks every pack against it); if the pack does not have it yet, add it to `art/daylight/pack.json`, then `make art` |
| A field added to / changed in the manifest | `ArtPack.from_manifest()` (the only place that reads the JSON) and its typed field, `tools/build_assets.py`, `docs/ASSET_SPEC.md` |
| Any source image or `pack.json` under `art/daylight/` | `make art`, and commit the products in `assets/` with it (CI rebuilds and compares) |
| A theme's colours | its `pack.json` `palette` under `art/<id>/`, then `make art`. **New images go only into `art/daylight/`**; `assets/` is a build product |
| The set of semantic IDs (one more prop / tile / icon) | only `art/daylight/pack.json`: Python has no second list. Add it to `art_contract.gd` only when a scene really draws it by id; an item drawn from a pool needs only its `item` block ([ITEMS](docs/ITEMS.md)) |
| A field of the `item` block, or a pool a scene draws from | `ItemSpec` and `ArtPack._read_item()` (the only reader), `tools/build_assets.py` `check_item()` (the same rules at build time), `ArtContract.ITEM_GROUPS`, `docs/ITEMS.md`, and cases in `tools/test_art.gd` and `tools/test_assets.py` |
| A new or renamed `.gd` / `.tscn` | commit its `.uid` with it; the directory list in the [manual](docs/MANUAL.md) |
| A new PNG | commit its `.import` with it. `mipmaps/generate` goes by asset family (`docs/ASSET_SPEC.md`, "Import policy by asset family"): the nearest families (theme packs, their long tables and the pixel people, all density 2; the minimum zoom is 2, so they are never minified) keep the project default `false`; the only family still minified is the agent logos, which write `true` explicitly in their `.import`. `tools/test_art.gd` checks every PNG under `res://assets` by family |
| The procedural drawing of the desk prop library or the long tables (`tools/draw_pixel_sources.py`, the template path of `tools/build_table_assets.py`) | `make pixel-sources OUT=<empty dir>` to draw, review, copy the chosen PNGs into `art/daylight/`, then `make art`; `make art` never calls it. The pixel contract the drawing must keep is in both scripts' docstrings, and `make test-art` checks it rule by rule |
| `OfficeTable`'s geometry constants | `docs/WORLD_MODEL.md`, and the sorting / footprint assertions in `run_tests.sh` |
| herdr protocol fields, machine list fields | `HerdrSnapshot.from_wire()` (with its typed fields and `signature()`) / `MachineRoster.normalize()` (fields are adapted only in these two), `tools/fake_herdr.py` and the fixtures |
| A new herdr method (write or read, other than the read-only three), or a new use of an existing one (such as the monitor's `ansi` screen read, the raw key table, `agent.prompt` / `agent.start` / `pane.split` and the read-only `agent.get`) | `HerdrCommands`' allowlist and payload validation (`scripts/herdr_commands.gd`, the only place that may spell a method name; the raw key table is `raw_key_refusal()`, and the monitor's key mapping `TerminalKeys` may only produce names it accepts); the typed reading of its result (like `PaneReadResult.from_wire()`, `ScreenReadResult.from_wire()`, `PaneSplitResult` / `AgentStartResult` / `AgentInfoResult`, `SpaceCreateResult` and the pure `CloseScope` / `GitWords`); herdr's error codes into `CommandRejection` (compared literally, everything else `OTHER`); `tools/fake_herdr.py` (the methods `allow` can open, the answer shapes and failure modes); gate cases in a write-boundary suite (`tools/test_commands.gd`, or a suite of its own with two fakes like `tools/test_launch.gd` / `tools/test_split.gd`: real input, zero gestures means zero writes, every refusal, result unknown never retried; raw mode in `tools/test_raw_input.gd`, plus ordering, the queue cap, the rate limit, refusal on disconnect, a terminal change, an audit without text); the `allowlist` in `tools/fixtures/herdr_methods.json` (the static check compares the method names `herdr_commands.gd` spells against it); the method allowlist in [docs/WRITE_BOUNDARY.md](docs/WRITE_BOUNDARY.md) §1; on a herdr upgrade, re-export that file's `methods` |
| The state log's event kinds (such as `LAUNCH` and REPLACED's `Changed`), segment rules or caps (`StateLog`) | `tools/test_state_log.gd`; the NEWS / EVENTS wording (`NewsItem`'s `subject()` / `what()` / `ended()`, shared by both), the overview's columns (`OverviewModel`, `OverviewLine`) and the agent list's History rows (`AgentHistory`: a run starts at `Track.run_start`, and the cache watches `StateLog.version`); the three rows "State changes observed this session", "Each pane's segments since opening" and "Start not observed" of the mapping table in `docs/VISUAL_LANGUAGE.md` |
| The Godot version | the version and sha512 at the top of `.github/workflows/ci.yml`, `.agents/setup`, and wherever README.md and the [manual](docs/MANUAL.md) name it |
| An everyday command | the `Makefile`, not README prose |
| The pixel people's (`pixel_people`) motions, facings, layers, parts, key colours or source strips | Everyone in the office is one (stations, the agent card's portrait, the showroom, Avatar Studio). `art/pixel_people/people.json` (the only hand-written source; hand-drawn source strips sit in the same directory, part skins in its skins/<facing>/, and `make people-templates` exports canvases and guides) → `tools/build_pixel_people.py` (`make art`; exact recolouring by key colour, one sheet per facing) → `PixelPeople.from_manifest()` (every `ArtPack` reads one, as `art.people`, sharing the pack's `AgentCatalog`) → `tools/test_pixel_people.py` / `tools/test_pixel_people.gd`. Layer nodes change only in `scenes/people/pixel_person.tscn` and `PixelPeople.SPRITES`; parts only in `people.json`'s `slots` and `AvatarLook.SLOTS` (the two must agree). **The names in `tracks` and `state_tracks` are used by name elsewhere** (`ArtContract`; the office plays `drink` by name): find every caller before renaming one. What the office requires of them (a track in both poses for every semantic animation, the seated pose drawing the back, a front for `drink`) is in `ArtContract`; a pack's `states[].animation` is checked by `tools/build_assets.py` against `people.json`'s `state_tracks`. The station overlay offsets (`OfficeStation`'s `PLATE_AT` and the like) are measured from the people's real pixels: when a person's height, head, hat or raised hand changes, measure them again; `tools/test_office_geometry.gd` catches a miss |
| Looks (part options, pack defaults, per-pane variation pools, provider default outfits, the save format) | `people.json`'s `slots` / `default_look` / `variation`, `look` in `data/agent_catalog.json`, `AgentCatalog` (the save schema and the frozen migration table of `migrate_v1()`: add only, never change); `docs/VISUAL_LANGUAGE.md`, "Looks" and `docs/ASSET_SPEC.md`, "Pixel people". A change to how variation is picked (`PixelPeople.pick()`, `VARIATION_SCHEME`) reshuffles everyone once: bump `/1` and update the pinned values in the tests |

## Tests

- A case is a `func test_xxx()` in a test file; the runner discovers them in source order, with no registration. The total may only go up; `run_tests.sh` checks a floor per suite.
  The one exception: when a subsystem is retired, its suite and floor go with it, and the commit message lists the coverage that moved to the new family (for each deleted suite: its case count, what it tests,
  which case covers that today, or why nothing can move); if something the office still does is left without a surviving case, add cases on the new family before deleting.
- Test public interfaces: pure functions (`OfficeProjection`), model fields, and the public methods and `%UniqueName` nodes of `OfficeHud` and its parts.
  Do not add assertions on `_private` members; the existing ones are debt, and whoever touches one pays it off.
- Interaction (clicks, drags, keys, the wheel) is tested with real input events (`Input.parse_input_event` plus waiting physics frames), never by calling the handler directly: an indentation change once let
  "pressing selects the station" slip in, because the test bypassed the input path. Run a new case once against the implementation before your change, to confirm it fails.
- Never weaken an assertion to make a test pass. When behaviour has to change, say why first, then change the assertion.
- Tests that need herdr use `tools/fake_herdr.py`, tests that need ssh use `tools/fake_ssh.py`; tests and CI never connect to a real herdr.
- The fake herdr answers only the read-only three by default, refuses everything else and records it as a violation. Suites that build an office but open no writes run with `--read-only` (`tools/run_tests.sh`);
  write-boundary cases live only in `tools/test_commands.gd`, `tools/test_raw_input.gd` (the monitor's pass-through input), `tools/test_answers.gd` (answer mode: keys and the one-line reply), `tools/test_bubbles.gd` (bubble reads, NEXT, counter clicks), `tools/test_monitor.gd`
  (terminal monitor: the grid and real input), `tools/test_overview.gd` (the staff panel answers as usual while the overview is open; the only deliberate write in that suite),
  `tools/test_launch.gd` (the boundary's `agent.prompt`, `agent.start` and `pane.split`, and the staff panel's START AGENT block), `tools/test_prompt.gd` (the card's one-line reply through `agent.prompt`),
  `tools/test_split.gd` (NEW PANE BESIDE and auto-selecting the new pane), `tools/test_close.gd` (Close's two clicks, the scope wording, every refusal) and `tools/test_spaces.gd` (New space / Worktree: the exact params, the directory and branch gates, git's one-line refusal, selecting across floors), each against two fake herdrs of its own;
  every case first does `reset`, then `allow`s the methods it needs, and the suite closes by checking that both fakes received only requests that were opened.

## Visual changes acceptance

1. Capture one set before and one after the change, with the same window (`make capture`; captures cannot use `--headless`).
2. **Actually open the images and look.** Then compare crops of plain floor, panel corners, icon edges and text baselines at contrast ×3 with nearest-neighbour magnification:
   seams of 1–3 colour steps are invisible in the original.
3. Always check 4x (1920×1280 window, `*-zoom4`) and 2x at the 960×640 minimum window (`*-min`). Zoom levels are even only (the default 1920×960 window has only 2x),
   so density-2 texels land on whole screen pixels; 1x below 960×640 is a degraded mode, not something to accept against.
4. Report only what you saw and measured. Do not write "expected to look better" as an observation.

## Commits

- Before committing, run `make fmt` and then `make check`. gdformat folds "a multi-line lambda inside a lambda" into something Godot cannot parse: give the inner lambda a name.
  The script load check in `make check` catches this; do not skip it.
- Commit art products (`art/`, `assets/`, `.import`) separately from code.
- Do not push or open PRs unless asked.

## Before building your own

Look for what the engine already has: Containers and Theme for layout, `ScrollContainer` for scrolling, `Button` for clicks in the HUD and `Area2D` for clicks in the world, Y-sort for depth,
`AnimationPlayer` / `Tween` for animation, mipmaps for minifying, typed classes for data, InputMap for keys, groups for finding a kind of node (not `set_meta` to pass data).
The big pits in this repository (a hand-written depth system, hand-written mipmaps, hand-written HUD layout, hand-written test registration) were all dug by going around the engine.
Only when nothing exists, write your own, and say why in the docs.
