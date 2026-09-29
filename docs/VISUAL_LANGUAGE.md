# Herdstead visual language: what each herdr concept is in the office building

This document answers one question: **what does each thing on screen stand for in herdr, and where is each herdr field drawn?**
Depth, origins and collision are in [World model](WORLD_MODEL.md); asset sizes in [Asset spec](ASSET_SPEC.md); the HUD actions that
write to herdr follow [the write boundary](WRITE_BOUNDARY.md).

**Everything in the world is either a signal bound to a field, or furniture that never changes with state.**

## Two rules

1. **Honesty.** Every thing in the world is exactly one of two kinds; there is no third.
   - **Signal**: bound to a real field and listed in the mapping table below.
   - **Furniture**: stands for no data and is placed by the floor plan. It does not change with agent activity, focus, selection or connection.
     Structural changes (a tab opened or closed, a table or floor grown) may adjust the shell and furniture; the same plan always rebuilds the same layout.
   Furniture must not look like a signal: plants do not wilt, the weather outside does not change, pictures are not swapped, cabinets do not
   multiply with repos. It is the same idea as "disconnected is not idle" (invariant 4).
2. **One concept, one channel.** A field is never drawn two ways in the world, and two fields never share one drawing.
   - **Agent state (`agent_status` and launch pending) has one channel: the station** — the seated person's pose, the badge over their head,
     and things drawn only for a state (done's paper stack, blocked's bubble). idle is the only state that leaves the seat (the floor's
     pantry). Nothing else in the world shows agent state. Walking is a transition, not a channel.
   - **State start** (when this state began) has one other reading: pantry order (the same order as `N`). The bubble's wait and patience bar
     are two drawings of the same start in the same bubble.
   - **Floor aggregates are not drawn in the world** (how many UNREAD or blocked on a floor). They live in the HUD (top bar counters, FLOORS
     rows, signposts), derived from the current model, never summed from events. The lens's carpet wash is the one exception, only while held.
   - **History is not drawn in the world.** Bubbles and the card show only how long the current segment has lasted. Segments and events
     observed since opening live only in NEWS / EVENTS / OVERVIEW, kept by the fleet's state log (`StateLog`), in memory only.
     **Stats are a mirror, never a score or a level.**
   - **herdr's focus** (the pane the user is looking at in the terminal) and **Herdstead's selection** (the station clicked here) are two
     things with two channels. **Herdstead's pointing** (hovering a HUD row) is a third, with its own drawing.
   - **The lens and the strategic view are modes, not overlays.** While `L` is held the wait moves from the bubble to the lens line and the
     bubble is not drawn, so it is still drawn once. `S` hides the world and shows a schematic instead; name plates, badges and bubbles hide
     with the world. Both read waits from the same function as OVERVIEW's FOR (`StateLog.wait_of()`).

## The mapping

| herdr | Office | Field → drawing | Asset (semantic ID) | Layer |
|---|---|---|---|---|
| machine | A building | label → the building title in FLOORS (when there is more than Local); connection → the icon beside it (live / connecting / offline); top bar `MACHINES n/m` (online / total; blocked-colour fill when n < m), hover: one line per machine with LIVE / CONNECTING / OFFLINE and time since its last snapshot (`HerdrFleet.heard_since`) | `ui.connected` / `ui.starting` / `ui.offline` | HUD |
| Machine disconnected | Its floors dim, freeze, counts go to zero | Invariant 4 | `stale_tint` | World |
| workspace | A floor | number + label → floor plate and FLOORS row; `worktree.repo_name` → repo name on the plate; **`is_linked_worktree` → the checkout directory name after it**. **Mezzanines**: on one machine, workspaces with the same non-empty `worktree.repo_key` form a group; the non-linked member (lowest number if several) is the source floor, linked ones hang under it in workspace order, labelled `3A`, `3B` … `3Z`, `3AA` … (`FloorModel.level_label`, `OfficeProjection.group_worktrees()`). A worktree whose source is not open, and other non-linked checkouts, stay separate floors. A mezzanine is a full floor (compound keys, same layout); grouping is display only and never enters the floor plan. FLOORS indents mezzanines under their source (`3F`, `·3A`, `·3B`, `2F`; `OfficeNavigator.section()`). Below 1280 logical units FLOORS is a narrow rail: labels and windows only, names and counts in the row tooltip. The plate reads `3A · CHECKOUT` and "worktree of 3F"; a group shares one accent chip (`sage` / `sky` / `terra` / `teal` / `lilac`, `PlateAccent0`–`4`, picked by the source's compound key): furniture that follows structure, not state | `ui.branch`; palette `sage` `sky` `terra` `teal` `lilac` | HUD / floor plate |
| Herdstead's current floor | The highlighted FLOORS row | `FloorRowCurrent`; floors switch instantly, no transition. Local browsing state only, never herdr's focus | HudTheme `FloorRow` / `FloorRowCurrent` | HUD |
| A floor's panes and their states | A row of windows under the floor in FLOORS | One window per seated pane in seating order, at most 8, then `+N`. Colour: working / blocked / done their state colours (blocked while starting is blocked), idle and starting bright warm white, unknown grey, shell dark; all dark when the machine is not online (`OfficeFloorRow.window_look()`). Hover → agent and state; click = clicking the row | HudTheme `Window*`: palette `working` `blocked` `unread` `cream` `muted` `slate` on `ink` | HUD |
| pane (list) | A row in the agent list in the right drawer | One row per pane (compound key): state icon; provider (upper case) + pane label; blocked → the wait; done → `UNREAD`; disconnected → Offline (never Idle). See "Agent list" | The pack's state badges, `ui.starting`, `ui.offline` | HUD |
| Global counts | Top bar counters MACHINES / BLOCKED · max / DONE / WORKING / IDLE / PANES | Online machines only (invariant 4). Blocked while starting counts as BLOCKED (`PaneModel.asks()`); starting and not blocked counts nowhere. Hover breaks down by machine → space. `max 12m` beside BLOCKED is the longest wait (`StateLog.longest()`, with `+` when a start was not observed); hover waits come from `StateLog.wait_of()`, `?` for a pane missing from the log. Clicks: BLOCKED → the longest wait, into answer mode (again → next); DONE → the oldest (select only); WORKING / IDLE → filter the list (or OVERVIEW's chips when it is open); PANES → toggle OVERVIEW; MACHINES is hover only. The window title's `(N)` is this BLOCKED number | The pack's state badges, `ui.connected` | HUD |
| Blocked on another floor | A signpost on the world's right edge: `↑ 3F infra ! 1` | Floors of online machines, other than the shown one, with blocked panes; higher on top; arrows follow PageUp / PageDown order; another building's floors add `@ bee`; at most 6 (the 6th reads `+N floors`), at most a third of the world width. Below 360 units of world (`signposts_from`) there are none: the FLOORS narrow rail carries a blocked badge and count instead. A click switches floors. Signs cover the world: what is under them cannot be clicked or hovered | Text + blocked badge | HUD |
| Next thing | NEXT at the right end of the staff panel, with `‹ ›` beside it | Says what a press does and to whom (`NEXT:` / `Answer CLAUDE web`, `Read` for done; ` @ bee` with several machines). Same as `N`, same order: while anyone is blocked only blocked panes cycle, otherwise done; longest wait first. It selects, switches floor, pans and does the verb: blocked expands the panel and enters answer mode once the question shows (`N` then a digit answers; Enter never sends); done only expands. When the office cannot write (`--read-only`, the showroom) it shows herdr's state word instead of a verb and only selects. Nothing to do: `All clear`, greyed. Narrow screens write only provider and space. `‹ ›` step through the same queue, select only | Text | HUD |
| State changes observed this session | The bottom NEWS strip and the drawer's EVENTS tab | One event ring in the state log: a state change, a pane appearing / disappearing / changing terminal, a machine going online / offline. Only herdr's words. The duration is always **the segment that ended**, before the arrow: `11:40 CODEX ui working 38m → done`, `idle 3s+ → blocked`; when the ended segment was not a watched state, only the new state. Also `working · new pane`, `pane closed`, `idle · new terminal`, `bee offline`; identity changes are `new terminal` / `new agent` / `new session`. Launches: `starting` on an existing shell, `new pane · starting` for a new pane; until the kind is known the subject is the upper-cased name (`CLAUDE-2 api starting`). NEWS: newest on the left, at most 8 fixed buttons, a new one fades in once (not a ticker), a click selects the pane (disabled with `Pane gone` when it is gone). EVENTS: newest on top, at most 200 rows; the selected pane highlights its newest row | The pack's state badges, `ui.connected` / `ui.offline`; HudTheme `NewsBar` / `NewsItem` / `DrawerTabs` | HUD |
| Something happened while away | The window title's `(N) `, a Dock bounce, an optional chime | Title: N = BLOCKED, left out when nobody is blocked or all machines are disconnected; done stays the trailing `· n UNREAD`; `--no-title-count` drops it. Alerts fire only for new STATE / APPEARED / REPLACED events that turn a pane blocked (or done) and still count by the top bar's rules; the first snapshot, reconnects, machine changes and launches are baseline. Nothing alerts while the window has focus, and nothing is replayed later. Dock: blocked only, on by default (`--no-bounce`), at most once per stretch in the background, only after 3 s still blocked, never for herdr's focused pane. Chime: off by default; the `CHIME OFF` / `CHIME ON` switch at the right of the counter row (remembered in `user://herdstead.cfg` as `[alerts] chime`) or `--chime`; blocked two rising tones, done one softer tone; at most one per refresh, once per pane per 10 s. Sound is only redundancy | None (tones generated in code) | OS |
| Each pane's segments since opening | The OVERVIEW table (PANES or `O`) | One row per pane: AGENT (badge + provider; hourglass and `STARTING` while launching, except blocked while starting), SPACE / TAB, STATE, FOR (this segment), BLOCKED (total this session), TIMES (how many times blocked), TIMELINE (a state colour band; **hatching = not observed**: before the pane appeared, while disconnected, and the fold of the oldest segments past 256). The band's left edge is when the log first saw the pane; a pane present at opening starts in its state, not hatching. Axis: left-edge wall-clock time, 5 / 10 / 15 / 30 / 60-minute ticks, `now`; redrawn once a second while open. Disconnected rows dim, STATE `offline`, FOR `-`, shown only under ALL. A row click selects the pane. It covers the world, FLOORS and the drawer without re-planning; bubble reads stop. | HudTheme `Timeline` (hatching `slate` on `cream`, axis `ink`) and `Overview*` | HUD |
| Start not observed | A `+` after a duration (`3m+`) | **`+` = at least this long**: the state began before the office started watching (the first snapshot of a connection). NEWS, EVENTS, OVERVIEW, the top bar's `max`, counter hovers, the lens and the strategic view all read `StateLog.wait_of()` / `longest()`, so one blocked pane shows one number everywhere. The card and the bubble write no number for such a state | Text | HUD |
| Floor shell | Top outer wall + entry band + row back walls + side walls; main aisle down the right | Furniture. The top wall carries windows and the lift door (with counters, windows centred between pantry and reception); back walls carry signs and pictures and stop before the main aisle. The lift door, above the main aisle's left lane, is where people enter and leave; it never opens and shows no state | `wall.cap_* / face_* / side_*` (incl. `t_left`, `end_right`), `window`, `door`, `wall_frame` | Ground |
| tab | A shared long table | label → the sign on the wall above; **`workspace.active_tab_id` → the open table: its lamps are lit** | `sign`, `task_light` | Ground / desk |
| pane | A terminal at a seat | **Only a pane brings a laptop and a lamp**; the laptop shares the seat's axis. A seat without a pane has only a chair (static decor may sit there). Tab layout → columns and far / near side; when missing, a pane keeps its seat, then free seats fill by stable pane key. The layout rect's `width` / `height` (terminal cells, 1–4096, else 0×0) sizes the terminal monitor's grid; the floor plan never reads it | Table family `monitor`, `task_light` | Desk |
| pane without agent | SHELL: an empty chair + a laptop with `$_` | Provider empty and not launch pending; static `$_` on the near screen and far lid; no blinking, no badge | Table family `monitor` views `shell_front / shell_rear` | Desk / Sorted |
| **herdr focus** | **That seat's lamp is brightest** | `focused_pane_id` → strong; other pane seats at the same table → normal; tables that are not the active tab → weak. **Switch herdr here** (`pane.focus`) on the card switches herdr's **shared** view (every attached terminal follows; on a remote machine, that machine's session) **and turns every `done` at that table into `idle`**. The lamp draws only the focus herdr reports back | `task_light` (off + three alpha steps, `OfficeTable` constants) | Desk |
| **Herdstead selection** | Four corner marks on the seat + a frame around the table | `picked_key`; with nothing picked it falls back to herdr's focus | `ui.selection` | Overlay |
| **Strategic view (`S`)** | A schematic of the floor over the world area (`OfficeStrategic`); FLOORS, drawer, staff panel and NEWS stay usable | Tables in floor-plan order (`FloorPlan.rows` top to bottom, `origin.x` left to right; newspaper columns when needed), each an `ink` frame with its tab label, a far row and a near row of cells by `SeatPlacement.column`. One cell per seated pane (the largest of 32 / 24 / 16 / 12 / 8 units that fits), coloured by `OfficeFloorRow.window_look()`; empty seats are not drawn. A blocked cell on an online machine writes its wait (`OfficeAttention.wait_text()`) when the cell is at least `wait_from` (24), else only in the hover tip (`CLAUDE · NEEDS INPUT · 12m+`). Provider is only in the tip (no initials, see below). Selection = four `blocked` corners, pointing = `OfficePointer`'s dashes, herdr's focus not drawn. Not a map: no plan coordinates, so nothing about aisles, pantry or furniture. Disconnected: tinted by `stale_tint`, all dark, no waits. Empty floor: `No desks on this floor`. A cell click closes it, selects the pane and pans to it. While open: no lens, signposts or question reads; `M` and `O` open over it | No new art: a `_draw()` Control, theme type `Strategic` on the pack's `panel` | HUD |
| **Herdstead pointing (hover)** | A static dashed frame 2 units outside the station's click area, `ink` / `paper` (`OfficePointer`, `OVERLAY_Z`); on another floor, a 1-unit `ink` outline on that FLOORS row (`FloorRowPointed`) | Hovering a NEWS entry, an agent list row, an EVENTS row (→ that pane) or a signpost (→ that floor). **It only points**: no selection, no floor switch, no pan, no read, no write | No new art | Overlay / HUD |
| **Lens (hold `L`)** | Each agent station (or pantry spot) gets a "how long in this state" line; bubbles are not drawn; each table's carpet gets a wash of its most urgent state; furniture dims | The line is OVERVIEW's FOR (`OfficeAttention.wait_text()`, `+` when unobserved, starting included); none for shells, `?` without a track, nothing on a disconnected machine. Carpet: blocked → `blocked`, done → `unread`, working → `working`, idle or starting → `cream`, unknown → `muted`, shells only → `slate`, disconnected all `slate`, at `LENS_WASH_ALPHA`. Furniture (floor, aisles, walls, door, windows, pictures, plants, cabinets, counters, desk decor) is multiplied by `LENS_DIM`; signals stay bright. The selected table's `blocked`-coloured frame darkens by `OfficeTable.LENS_FRAME` so it shows on a blocked wash. Off while the monitor or OVERVIEW is open or a text field has the keyboard. | No new art: Label, ColorRect | Overlay / Ground |
| agent | The person seated there (pixel people) | provider → **only the upper-case provider name on the name plate**; clothes and looks show neither provider nor state (see "Looks"). **No chest badge**: at 1 texel = 1 unit there is no room for a logo; provider logos appear only in Avatar Studio | Pixel people family (`art.people`) | Sorted |
| agent state | **The station: pose + badge + things drawn only for the state** (see "Where people rest") | `agent_status` → the pack's `states`; `launch_pending` → starting, but **blocked wins**. idle leaves for the pantry; blocked raises a hand (`desk_blocked`) under a bubble; done sits (`desk_idle`) beside a paper stack. The rules live only in `OfficeRests` (`scripts/world/office_rests.gd`); animations resolve through pixel people's `state_tracks`, the pantry plays `drink` by name | `ui.working / blocked / unread / idle / unknown / starting` | Sorted / Overlay |
| **How long it has waited** | **The blocked bubble: a duration and a patience bar, nothing else** | `HerdrFleet.state_since` → the duration (at most three characters: `Ns`, `Nm` under 100 minutes, then `Nh`; `OfficeBubble.wait_text()`) and the patience bar (40 wide, empty at 10 minutes, always `blocked`-coloured). When stale or when the start was never seen, neither is drawn and neither is the frame (an empty frame reads as a speech bubble with nothing said); only the raised hand and badge remain, and the click / hover area stays. The far badge sits at the bubble's right end, drawn over it. Not drawn while the lens is held | Text; palette `muted`, `blocked`; `panel` nine-patch | Overlay |
| **The blocked question** | **A HUD tip when hovering the bubble** (a ten-character excerpt in the bubble would say nothing) | An excerpt of `pane.read` `detection`: lines trimmed of spaces and box characters, the last line with `?` (else the last non-empty line), at most 120 characters; the full question is in the card. Read only for blocked panes on screen (`PaneModel.asks()`), on an online machine with a current snapshot, not under the monitor or OVERVIEW; one read at a time; reads of one pane start at least 10 s apart; only the latest is cached, dropped on leaving blocked; no reads while minimized; it never writes and never counts as "seen". `--read-only` writes `read-only`; before the first read, `Question not read yet` (never a "reading…" placeholder: a disconnected machine never answers). A bubble click selects and enters answer mode once the question shows | The HUD's `HdPanel` (`%BubbleTip` in `hud.tscn`) | HUD |
| **done (UNREAD)** | **A stack of papers right of this seat's laptop** | `done`, not launching, has an agent → visible (built with the table, only `visible` changes; `OfficeTable.PAPERS_ASIDE`); frozen and dimmed with the floor when disconnected | `done_stack` | Desk |
| State start | Order in the pantry | Earlier starts enter first. **Unknown** is only for a state never seen to begin (the first snapshot of a connection); it counts as the longest wait and goes first, ties in projection order. Every transition watched while connected has a **known** start from when it was observed: a state change, a launch ending, a new terminal / agent / session, a pane appearing. Blocked while starting counts from when it was seen blocked; a launch that ends while still blocked, same terminal / agent / session, keeps its clock. So newcomers queue behind those already there and never push anyone out; the order matches `N` | — | World |
| Reception and pantry | Two counters in the entry band, against the top wall | Furniture: reception left of the lift door, the pantry at the band's far left; only on floors with tables; placed by the floor plan alone. **Reception is pure furniture**: its reserved queue spots stay empty | `reception`, `pantry` | Sorted |
| Furniture | Plants, filing cabinets | Standing on the floor, origin = foot point, in the y-sort. Each back wall: a plant at the start, a cabinet at the end, and **a row of plants along the wall foot** on the wall's 160-unit grid, clear of signs and table names; **an empty bay** 3+ cells wide before the main aisle gets one more plant. Never placed by table or tab, so plant count does not follow tab count. `plant` and `plant_b` alternate by grid cell (even / odd), never by state, tab or time | `plant`, `plant_b`, `cabinet` | Sorted |
| Wall picture | A framed landscape on a back wall | Furniture, in the sign height band (`FRAME_FOOT` 48 below the row top). From `OfficeShell.FRAME_FROM` (312) the wall splits into `FRAME_PITCH` (320) spans; each span has two spots (its start and `FRAME_SECOND`, 160, later) and gets at most one picture, on the first spot whose picture, grown by `FRAME_GAP` (8), touches no sign, table name, table, standing furniture, counter or wall-end cell. So pictures hang in gaps between wall-foot plants, and a moved sign affects only its span. Part of the shell (Ground: no footprint, not on the walk graph). Cream sky, sage hills, terra frame; no state colour (`working`, `blocked`, `unread`, `muted`, `task_light`) | `wall_frame` | Ground |
| Desk decor | Mugs, notebooks, clipped papers, plants, headphones; now and then a white cat | Fixed pseudo-random per table group's stable identity. The cat's loaf, sleep and sit are static poses, not working / idle / done; refreshes, growth and theme changes keep the choice | `desk_mug / notebook / papers / plant / headphones`, `cat_loaf / sleep / sit` | Desk |

Bold marks state signals. The Layer column follows [World model](WORLD_MODEL.md): flat on the floor or wall → `Ground`, standing on the floor → `Sorted`.

### Looks

A person's skin, hair style, hair colour, top, bottoms, hat / accessory and glasses follow the rules for **furniture**: they bind no herdr field
and never change with agent state, selection, focus or connection (a disconnected floor dims as usual; the clothes stay). Looks hang on the
provider; each slot's value comes from, in order:

- the provider's default (`look` in `data/agent_catalog.json`; a default, not an identity: several agents may dress alike);
- the user's pinned choice for this provider in Avatar Studio (`user://herdstead_avatars.json`);
- for unpinned slots the pixel people family lets vary (by default skin, hair style, hair colour, glasses): a small fixed variation from SHA-256 of
  the provider and the pane's stable key (`HerdrFleet.pane_key`). The same pane with the same provider is the same person on every start and
  machine, so five panes of one agent kind are not quintuplets.

The pick never reads state, waits, focus, selection or any live field. A pane that changes provider is one person leaving and another arriving
(see **Identity** below), picked afresh; a new terminal or session is the same person.
**Read the provider on the name plate, the state in the pose and badge**: clothing colour is neither a provider code nor a state.

## Immediate signals and walking transitions

People walk, so channels split in two: those that show the current state the moment an observation arrives, and the body catching up. Walking
itself is **not** a channel for any state; it is only the body going where the observation says.

| Channel | When it changes | What it shows |
|---|---|---|
| Name plate, state badge, bubble, paper stack, selection marks, the station's click area | At once (they are the signals) | The current observation: who sits here, what state, how long, who is selected |
| Body position and pose | After arriving | Only at rest is it a state: seated = at the station (pose says the state); in the pantry = idle |
| Walking (the walk strip) | From an observed change until the body settles (at most 6 s, 96–480 units/s) | Transition only: not timed, not busy or idle |
| Ghost (a person without a plate walking to the lift door) | When a pane leaves the floor | Transition: this station's person has left; no plate, badge or card; clicking it selects nothing |

- **Entering**: a pane with an agent (or launching) appears; its person walks in from the lift door along the main aisle to the seat's approach
  point and sits. Plate, badge and click area are at the seat from the start; clicking the seat selects it while the person is still walking.
  Far seats are entered straight from the approach point. **Near seats have the chair in line with the approach point, and people never walk through
  chairs**: they walk along the near aisle to the stand spot's column, step onto the stand spot (now only a route knee; nobody stands there), then step
  sideways into the seat; leaving reverses it. Pantry trips use the same legs.
- **Leaving**: when a pane closes, moves to another floor, or its agent leaves (it becomes SHELL), the person walks to the lift door and vanishes
  there. The seat frees at once (plate first); the walker is a **ghost**. At most 32 ghosts; beyond that the oldest vanishes.
- **Changing seats** (column, side, or the whole table moved) is the same person walking over, not a leave and an arrival.
- **Identity**: a pane that switches to a different agent (both providers known and different) is one person leaving and one arriving; the same
  agent in a new terminal or session walks nowhere, with **one exception** in the pantry: the new state counts from when it was seen (a known,
  late start), so in a full pantry that person yields the spot to someone seated who has waited longer and walks back to the seat.
  If a pane leaves while its person is walking in, the same person turns around; if it returns (same identity) while its person is walking out,
  that person turns back. There are never two bodies.
- **Closing a table's last pane** closes the tab: the table vanishes and the person walks out from where it stood. Closing a workspace's last pane
  removes the floor, which is a floor switch: nobody walks.
- **Cold means no walking**: first draw of a floor, floor or theme switch, the first snapshot after a reconnect, the refresh after a layout error —
  everyone appears in place, no ghosts, nothing replayed. **Individuals** also appear directly (ghosts vanish directly) when the route is too long
  for 6 s even at 480 units/s (5× the strip's native speed), when a floor change leaves them on a table or wall, or when the observation's
  pathfinding budget ran out before their turn (arrivals first, then ghosts, then re-routes). People whose route ahead is still clear and whose
  target did not move keep walking.
- **Disconnected** (invariant 4): the floor dims, walkers freeze mid-stride, ghosts vanish, and changes observed meanwhile are placed without
  walking; the reconnect is cold. Walkers stay frozen until the first drawable observation after reconnecting. A frozen person outside the pantry
  is the **only exception** to "only the pantry has people standing still", and the dimmed floor says the picture is stale.
- **Accepted overlap**: plates, badges and selection marks are in the Overlay and draw over passers-by; walkers pass through each other and through
  standing or seated people. People avoid only furniture and walls ([World model](WORLD_MODEL.md), "Collision and walking").
- **The stride is a placeholder**: the body moves at constant speed and the walk strip plays at `speed ÷ 96`. The current strip's cycle is two
  steps of about 16 units over 4 frames and 0.56 s (about 29 units/s native), so at 96 units/s the feet slide about 3×. When the walk strip is
  redrawn, make one cycle's stride ÷ 0.56 s equal 96; no code change is needed.

## Where people rest

Agent state is drawn only at the station. idle is the only state that leaves the seat; the pantry's capacity and order only choose the spot.

| State | Where the person rests, doing what | What hangs where |
|---|---|---|
| working | Their seat, typing (`desk_work`) | Plate + badge at the seat |
| starting | Walks in from the lift door and sits (`desk_start`); no bubble, no paper stack (`PaneModel.launching()`). This form starts with the first snapshot after herdr accepts `agent.start` (`launch_pending`, no kind yet). **Blocked wins over starting**: an agent asked a question while starting is drawn as blocked (raised hand, bubble, blocked badge, the kind on the plate) and counts in BLOCKED, NEXT, signposts and Waiting; that it is still launching shows only in the card (`Launching` tooltip, footer `claude-2 asks: answer with the keys`). One blocked on arrival has its bubble over the seat while it is still walking in | Plate + hourglass badge (`ui.starting`) at the seat; until the kind is known the plate shows the upper-cased name herdr gave the agent (`CLAUDE-2`, `PaneModel.agent_name`) |
| unknown | Their seat, sitting still (`desk_idle`) | Plate + `?` badge at the seat |
| done (UNREAD) | Their seat, sitting (`desk_idle`); a paper stack right of the laptop (`done_stack`) | Plate + badge at the seat; stack on the desk |
| blocked (including asked while starting) | Their seat, hand raised (`desk_blocked`); a bubble overhead with the wait and patience bar; hovering it shows the question excerpt | Plate + badge + bubble at the seat |
| idle | The floor's pantry, holding a cup (`drink`); each person has a preferred spot hashed from the pane key and, on conflict, takes the next free one in start order; when full, the rest sit (`desk_idle`) | In the pantry: badge; at the seat: plate + badge |
| SHELL / empty seat | Nobody | SHELL's laptop / nothing |

- What hangs on a person hangs where they **rest** and moves there the moment the observation arrives; the body follows. While an idle person is in
  the pantry the seat still clicks and selects the same pane (two click targets); an empty-for-now seat keeps its chair and ordinary laptop
  (never `$_`) with nothing over it.
- The bubble's click area and the seat's never overlap: a seat click selects; a bubble click selects and enters answer mode once the question shows
  (never sends; under `--read-only` it only selects). While a bubble shows, a far seat's click area gives up the badge's rows (its top drops from
  −70 to −53): every point belongs to one click area.
- Standing still happens only in the pantry or on a frozen, disconnected floor; passers-by never stop. The pantry row is not a path: people step
  into it from the aisle below.
- A new terminal or session re-orders a pantry person from that moment; in a full pantry they sit back down, and two people may swap spots when one's
  hashed spot is the other's (an accepted consequence). This is the only case where "a new session walks nowhere" fails. Likewise an agent that has
  just finished launching queues behind those already in the pantry: if it is full, it sits and nobody moves.
- A floor whose entry band cannot hold reception, the door's clearance and `MIN_QUEUE` (empty) queue spots has neither counter and so no pantry;
  one that fits reception but not the pantry plus one spot has no pantry. Idle people there sit. (Shipped floor widths always fit both; the rule is
  tested on hand-made plans.)
- Disconnected (invariant 4): pantry, bubbles and paper stacks freeze and dim; bubbles show no wait, bar or frame; nothing is re-ordered. The first
  refresh after reconnecting is cold and re-orders (every start is unknown again).

## HUD panels

Everything below is HUD and never changes the world. The world draws only what their actions produce in the snapshot.

### Staff panel

The staff panel (the agent card; scene name `inspector`) runs across the bottom. **It is one line by default at every size**: provider · state ·
location, wait, `‹ ›`, `Monitor ⤢`, `Open ⏎` and NEXT; no portrait, and the preview is neither shown nor read. `Enter` or `Open ⏎` expands it to
full height: portrait, name, state, wait, location; the terminal preview; details (`PANE`: pane id, label, directory, session, terminal title);
actions (`▾ Esc`, Monitor, Answer, Switch herdr here); NEXT. `Esc` outside answer mode, `▾ Esc` or selecting another pane collapses it; `Esc` in
answer mode only leaves answer mode. A new terminal, agent, session or connection on the same pane does not collapse it. The world gives up the
panel's height; the drawer stays as it is. Every line fits the smallest 480×320-unit screen; a sentence that does not fit goes whole into the tooltip.

- **State words**: done adds `UNREAD = not yet seen / Not task success.`; disconnected adds `Connection lost. / Not an idle signal.`.
  **A shell's card** has no portrait, badge or timer: `SHELL`, `no agent` (the idle herdr reports for a shell is the terminal's). There is no terminal
  icon before SHELL: the pack's terminal image `ui.working` is WORKING's badge and would read as a state.
- **Preview**: blocked reads herdr's full `detection` (up to 200 rows), other states the end of `recent_unwrapped`; it shows the last 12 rows,
  monospace, long lines clipped. The header says how many rows show, how long ago, and whether rows were cut or clipped (`12 of 31 rows · 3s ago`,
  `recent · 3s ago`); when it cannot read it says why (`No preview: offline`) and never shows blank space as terminal content. It reads only at full
  height, not minimized, with the machine online and the snapshot current.
- **Switch herdr here** (with several machines **Switch herdr on <machine>**) is open only for a station the user clicked, while it is still the
  clicked terminal: when following herdr's focus it reads `Following herdr's focus`; on a new terminal `New terminal: pick again`. The note
  `Clears table's UNREAD` warns that every pane's UNREAD at that table clears. Result line: `herdr switched here` / `Not sent: <reason>` /
  `Unknown result: look first`.
- **Answer mode** (**Answer ⏎**, or `Enter`) replaces details and the switch button with the keys `1`–`9`, `y`, `n`, `⏎`, **Send Esc**, a reply
  field and **Send line**, and the line `Checks the screen first; it can still change`. The result line: `Sent` (herdr took the input) /
  `herdr refused (code)` / `Not sent: …` / `Unknown result: look first`. What is offered depends only on herdr's state (blocked gets keys, idle / done
  get a line, a shell nothing), never on terminal text. Rules: [the write boundary](WRITE_BOUNDARY.md) §2.
- **Start agent and New pane** (the `%Launch` block, only on the expanded panel, outside answer mode). For a shell, **START AGENT**: one button per kind
  seen in this machine's snapshot, note `Types the kind + Enter in this terminal`; when the last line does not look like a prompt the first click
  shows `Start anyway? Types "claude" + Enter after:` and that line in a dark terminal strip, and a second click on the same kind sends. For an agent,
  **NEW PANE BESIDE <PROVIDER>** with `New pane →` / `New pane ↓` (the pane's shape picks the direction) and `Splits a new pane next to <pane>`. Results
  go in the card footer (`Starting claude-2 · 4s`, `claude-2 started`). Rules: [the write boundary](WRITE_BOUNDARY.md) §4.
- **Close, New space, Worktree** (two lines below, for any selected pane): `Close` and `New space`; a branch field and `Worktree`, with the note
  `New worktree: branch <b> from this floor` or `Branch: <why not>`. The first `Close` click only states the scope (`Closes CODEX's pane w2:p3.`, plus
  ` and its table …`, ` and floor …` or ` and mezzanine 3A "docs". The checkout stays on disk.` for a last pane; `Kills CLAUDE, still working.` when the
  agent is not idle) and relabels the button `Close · kills` or `Close · click again`; a second click within 10 s sends. The button is off for the
  repo floor's last pane while a mezzanine is open. Footer: `Closed w2:p3` / `New space w14` / `New worktree v1-a → w15`; a lost reply says the next
  snapshot decides. Rules: [the write boundary](WRITE_BOUNDARY.md) §5.
- In the world, a split pane first appears as an empty seat with an ordinary laptop; a person walks in only after a launch is accepted. A closed pane
  is the reverse (the person walks out, the table or floor disappears, NEWS `pane closed`). A new space or worktree is a new floor in the snapshot.
  Selecting the new pane, even across floors, is only a selection. `--read-only` and the showroom have no launch block.

### Agent list

The agent list lives in the right **drawer**. The drawer starts collapsed on every launch as a vertical tab `◀ AGENTS · n` (n = agents that need a
person); open, it has `AGENTS | EVENTS` tabs and `▶` to fold it. Floors are planned at the collapsed width and opening never re-plans: the open drawer
covers tables on the right, and the camera can pan to them. `A` opens it with the keyboard on the list in Flat view; `--drawer=open` starts it open.

- Rows: state icon, upper-case provider, pane label (or tab name), the wait for blocked rows (the bubble's clock; none when disconnected),
  `UNREAD` for done.
- **Flat** groups by urgency: Waiting (blocked; unknown starts first, then longest wait — the pantry and `N` order), Unread, Working (including
  starting and not blocked), Idle (including unknown), Snoozed / hidden, Offline, Shells, History. **Tree** goes machine → floor → mezzanine →
  tab → agent, with unseated panes and shells in their own groups.
- **Disconnected machines**: their agents are Offline (grey, `offline` icon, no wait), never Idle or Waiting; tree headers read `offline` with zero
  counts (invariant 4). A machine whose snapshot was rejected for exceeding limits is treated the same.
- A click selects the pane (the station-click path); double click / `Enter` opens it in the terminal monitor. The row menu (`⋯`, right click,
  Menu / `Shift+F10` / `.`) has Snooze 5 min / Resume reminder and Hide / Restore; they change only the local record, never herdr's UNREAD or the world.
- **History** comes from the state log through `AgentHistory`: one row per pane that was blocked or done this session and is not now, newest first,
  at most 200; trailing `OFFLINE` or `GONE`, none for ENDED. It covers only the pane's current run: after a new terminal, agent or session the old
  run is no longer a row (EVENTS still has the REPLACED event). History and EVENTS read one log: per pane and by time.
- A pane seats only when it and its tab declare the same workspace; a conflict is never rewritten, and the pane is listed as unseated (a click shows
  details without switching floor). Machine totals include it; floor counts include only seated panes.

### Terminal monitor

The terminal monitor draws herdr's own screen (`pane.read visible ansi`, in the pane's real rows and columns); it is not pixel art, so like HUD text
it uses vector glyphs. It covers the whole office, which keeps refreshing underneath, and changes nothing on the floor. It is a window, neither signal
nor furniture. The title shows provider, floor / table, state and wait; the status line shows `● LIVE INPUT` (raw mode), the last input's round trip,
and reasons (result unknown, refused, `no cursor from herdr`, keys herdr cannot name). A disconnected machine freezes and dims it with `○ OFFLINE`;
a new terminal shows `■ INPUT STOPPED` until **Follow new terminal**; `--read-only` shows `VIEW ONLY` and does not read. Input rules:
[the write boundary](WRITE_BOUNDARY.md) §3.

### FLOORS minimap

The left column lists floors per building (a title per machine when there is more than Local): level label, name, blocked / UNREAD counts when
non-zero, and a row of windows; higher floors on top, mezzanines indented under their source, the shown floor highlighted. FLOORS rows, signposts,
PageUp / PageDown (in drawn row order), `N`, list clicks and focus-following switch floors instantly: no transition, no lift car, no input lock.
When a floor disappears the view falls back at once to one that exists. The `door` on the outer wall is furniture.

## Why these channels

### Why the desk lamp is the focus channel

- The lamp was already there (one `Polygon2D` per column and side in `OfficeTable`); four intensity steps carry focus.
- Focus has three levels (workspace → tab → pane) and light has strengths; the selection marks are binary and already carry `picked_key`.
- It needs no new art. The steps are table geometry, constants only in `scripts/world/table.gd` (invariant 5), scaled by the pack's
  `task_lights: soft / strong` and, at night, up to `DayLight.NIGHT_LAMPS` (×1.8), so the four steps stay apart under the night tint.
- Measured (`OfficeTable.LAMP_ALPHA = [0, 0.10, 0.22, 0.52]`, ×1.4 in a strong pack, against unlit desk wood): daylight DIM +5 / ON +11 /
  FOCUS +25 levels, the retired dusk pack +13 / +28 / +66. A single +3 step is invisible in a full capture.
- **DIM cannot be read as disconnected**: disconnection makes the desk 68–69 levels **darker** (`stale_tint`); DIM is a few levels **brighter**.
- **Night is lighting, not a signal.** The time of day (`DayLight`, the local clock, `T` to turn it over) binds no herdr field, so rule 1
  does not apply to it and nothing reads it as a state. It darkens and cools the whole world alike (`DayLight.NIGHT_TINT`, a
  `CanvasModulate`; the HUD is its own layer), which keeps every channel's contrast in order; a lost connection is still its own grey
  `stale_tint` on top, with everyone frozen (invariant 4), and `tools/test_day_light.gd` holds the two apart.
- When `active_tab_id` is missing, every tab of that workspace is unknown (`RoomModel.Active.UNKNOWN`) and drawn ON, not DIM: not said is not no.
- Floor-level focus is not drawn: only one floor is drawn at a time, and the minimap's current-row highlight already means "the floor I am looking at".

### Why laptop = pane and `$_` = SHELL

A herdr pane is a terminal; the office draws a laptop. A monitor offset sideways to clear faces read as belonging to the next seat, so the laptop
shares the column centre with person and chair and sits at its own table edge. It is shaped after a silver MacBook (thin lid, narrow hinge,
keyboard and trackpad); 14 units wide, the far back 8 units high and the near front 11, small enough to leave the far worker's face, shoulders and arms visible without touching the Y-sort.

Seats come in three kinds: **empty** (a chair), **SHELL** (an empty chair + a `$_` laptop), **agent** (a person + an ordinary laptop). Launch pending is
never drawn as a shell, even before there is a provider. The `$_` is a static mark on the screen (near) or lid (far): no `>_` bubble, no blinking, no
output, so it says nothing about running, waiting or connection. The laptop uses the table family's `monitor` semantic ID, is a child of the table
and draws in node order (world model rule 4); pane or agent changes within capacity only swap textures and `visible`.

### Why one floor shell per floor, not one room per tab

A tab is a shared long table on an open floor, a workspace is a floor, and worktree information goes on the floor plate. Walls around each tab would
cut the building into cubicles, so the shell comes from `FloorPlan`'s bounds and row bands, not from each table's rectangle.

- Under the top outer wall is a 96-unit entry band (three cells: wall clearance, facilities row, aisle); the main aisle on the right is 64 wide;
  each side wall is one 32-unit cell; the front wall is not drawn.
- Each row is a fixed 416 units: a 64-unit back wall, a 288-unit table band, a 64-unit cross aisle. Back walls meet the left outer wall and end
  before the main aisle, never blocking the way from the entrance.
- Only the top outer wall has windows and the lift door. Inner walls carry tab signs and pictures, never windows.
- Walls assemble on one `TileMapLayer` grid; the left T-joint and the free end before the main aisle use `wall.cap_t_left / face_t_left` and
  `wall.cap_end_right / face_end_right`. The topology is a rectangle with parallel back walls; no Terrain auto-tiling is needed.
- The base floor covers every cell of `floor_cells`; carpets belong to table groups; aisles lie over the whole floor.
- A floor's first plan fixes its width. Window size, zoom, renames, state and focus never move tables; structural changes start from the old plan,
  prefer growing in place or into gaps, and an over-wide table gets its own row. A removed table leaves a gap; other tabs do not re-queue.
- Panes that stay in the same tab keep their person nodes through growth, moves and side changes. Floor and theme switches rebuild the current world:
  the cache holds plans and views, not resident people per floor.
- Plants and cabinets are `StaticBody2D`s with foot points and footprints; they never take table groups, the entrance or aisles, and they are not a
  reading of how many tabs or agents there are. Nothing stands by the door, between the counters or against the left outer wall.

Table width, seats, stand spots, approach points and draw extents come from `OfficeTable.measure()` ([World model](WORLD_MODEL.md)). Name plates
use the font's real size, not the requested 12: on macOS the near plate's bottom edge measures 67 and the selected table's frame reaches 72.
Layout validation runs on the graph people walk (door threshold, reach to every approach point, the legs to stand spot and seat, wall clearance for
a full person canvas), so a validated floor is a walkable floor ([World model](WORLD_MODEL.md), "Collision and walking").

## Not drawn, and why

| Idea | Why not |
|---|---|
| Laptop screens coloured by state | Needs screen rectangles in the table manifest; hard-coding them would break "table geometry only in `table.gd`, assets only by semantic ID". Add a `screen` field when the table art is next rebuilt. |
| Idle wandering | People walk only on observed changes. With no change nobody moves: walking is not a channel for any field. |
| `layout.zoomed`, pane `scroll` | No drawing without new art that would not clash with existing channels. `HerdrSnapshot.from_wire()` drops them (invariant 2: no field nobody draws). |
| Dusk as a runtime palette-swap shader | Tables are drawn from the palette by their builder and pixel people are one family shared by every pack, so a LUT would cover only tiles / props / UI. Dusk was derived at build time instead, and then retired (2026-09-29): night is to be a light over the one pack, a modulate, not a palette swap. |
| A floor minimap scaled from plan coordinates | Floors are tall (80 panes ≈ 800 × 4320 units), the world area wide (≈ 820 × 360 at 2×): at 400 panes a row would be 7 units, and aisles, pantry and furniture would read as signals. The strategic view keeps only order, columns and side. |
| Zoom below 2 to see a whole floor | Zoom is the window's content scale (`OfficeScene.fit_window()`, `ZOOM_MIN := 2`); at 1× density-2 nearest families lose half their outlines, and a large floor still does not fit. |
| Provider initials in strategic cells | Of 23 providers five start with C and three with K; initials are ambiguous and break "one concept, one channel". Provider stays in the hover tip. |

## Asset pipeline

- `make art` rebuilds every pack: it rebuilds `assets/`, and `tools/check_build_clean.py` proves the result matches the commit (CI does
  the same). Only `art/daylight/` is edited.
- Semantic IDs and sizes have one source, `art/daylight/pack.json`; Python checks only that PNGs and the manifest agree.
- `make check-packs` reports IDs in a pack that `scripts/art/art_contract.gd` does not require as `PACK_UNUSED` (today `wall.front_*` and
  `wall.threshold`). The builder prunes generated images the manifest no longer declares.

## Adding something new

1. First answer: **signal** or **furniture**? A signal gets a row in the mapping table (field, drawing, layer). Furniture is placed by the floor plan
   and clearances and reads no agent state, focus or connection.
2. A signal's field: cleaned in `HerdrSnapshot.from_wire()` (typed classes and `signature()`) or `MachineRoster.normalize()` → a typed field in
   `scripts/model/` → `OfficeProjection`; fixtures in step. For "when did it change, what was it before" read `HerdrFleet.state_log()`
   (`StateLog`); never keep another copy of a start (starts are computed once, in the client's `StateClock`).
   A new herdr method (a new card action) follows the AGENTS.md "If you change X, also update Y" row: allowlist, fake, gate tests and
   [the write boundary](WRITE_BOUNDARY.md) §1 table. The action is HUD; the world draws only its result in the snapshot.
3. Assets: semantic IDs only; add newly used IDs to `scripts/art/art_contract.gd`; Sprites go through their asset family's `dress()`.
4. Placement: flat on floor or wall → `Ground`; standing → `Sorted`, origin = foot point; on a desk → a child of the table; floating over the
   world → `Overlay` (`OVERLAY_Z`).
5. State changes only change properties of existing nodes (`visible`, `color`, `text`); never destroy and rebuild.

## Known future conflicts

- **"Standing" and "passing by" look alike.** Only the pantry and a frozen, disconnected floor have people standing still. The pantry is in the
  entry band against its counter; passers-by never stop and carry no plate or badge (those stay where the person rests). The one person standing
  still outside the pantry is frozen by a disconnect, and then the whole floor is dimmed.
