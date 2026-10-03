# Herdstead visual language: what each herdr concept is in the office

This document answers one question: **what does each thing on screen stand for in herdr, and where is each herdr field drawn?**
Depth, origins and collision are in [World model](WORLD_MODEL.md); asset sizes in [Asset spec](ASSET_SPEC.md); the HUD actions that
write to herdr follow [the write boundary](WRITE_BOUNDARY.md).

**Everything in the world is either a signal bound to a field, or furniture that never changes with state.**

## Two rules

1. **Honesty.** Every thing in the world is exactly one of two kinds; there is no third.
   - **Signal**: bound to a real field and listed in the mapping table below.
   - **Furniture**: stands for no data and is placed by the floor plan. It does not change with agent activity, focus, selection or connection.
     Structural changes (a tab opened or closed, a pod or zone grown) may adjust the shell and furniture; the same plan always rebuilds the same layout.
   Furniture must not look like a signal: plants do not wilt, the weather outside does not change, pictures are not swapped, side tables do not
   multiply with repos. It is the same idea as "disconnected is not idle" (invariant 4).
2. **One concept, one channel.** A field is never drawn two ways in the world, and two fields never share one drawing.
   - **Agent state (`agent_status` and launch pending) has one channel: the station** — the seated person's pose, the badge over their head,
     and things drawn only for a state (done's paper stack, blocked's chip). idle is the only state that leaves the seat (the map's
     pantry). Nothing else in the world shows agent state. Walking is a transition, not a channel.
   - **State start** (when this state began) has one other reading: pantry order (the same order as `N`). The chip's wait is its one
     drawing at the seat.
   - **Zone aggregates are not drawn in the world** (how many UNREAD or blocked in a zone). They live in the HUD (top bar counters, SPACES
     rows, edge arrows), derived from the current model, never summed from events. The lens's wash under each pod is the one exception, only while held.
   - **History is not drawn in the world.** Chips and the card show only how long the current segment has lasted. Segments and events
     observed since opening live only in NEWS / EVENTS / OVERVIEW, kept by the fleet's state log (`StateLog`), in memory only.
     **Stats are a mirror, never a score or a level.**
   - **herdr's focus** (the pane the user is looking at in the terminal) and **Herdstead's selection** (the station clicked here) are two
     things with two channels. **Herdstead's pointing** (hovering a HUD row) is a third, with its own drawing.
   - **The lens and the strategic view are modes, not overlays.** While `L` is held the wait moves from the chip to the lens line and the
     chip is not drawn, so it is still drawn once. `S` hides the world and shows a schematic instead; name plates, badges and chips hide
     with the world. Both read waits from the same function as OVERVIEW's FOR (`StateLog.wait_of()`).

## The mapping

| herdr | Office | Field → drawing | Asset (semantic ID) | Layer |
|---|---|---|---|---|
| machine | **One open-plan map** (every workspace of the machine a zone on it); only one machine's map is drawn at a time | label → the machine plate over the map (`@ name` once there is more than Local, then LIVE / OFFLINE / CONNECTING and the ssh error; a machine with no workspace is an empty map whose note says why); a zone the map cannot be laid out for is named there, inside the plate's band (`Layout unavailable: 3 INFRA: …`, in the blocked colour, cut with an ellipsis where the band is short and whole in its tooltip); label → its heading in the SPACES rail (when there is more than Local), highlighted while its map is the one shown; a click on a heading switches to that machine's map, at once and cold (a machine that never connected opens as an empty map with its note); connection → the icon beside it (live / connecting / offline); top bar `MACHINES n/m` (online / total; blocked-colour fill when n < m), hover: one line per machine with LIVE / CONNECTING / OFFLINE and time since its last snapshot (`HerdrFleet.heard_since`) | `ui.connected` / `ui.starting` / `ui.offline` | HUD |
| Machine disconnected | **Its whole map** dims and freezes, every zone of it; counts go to zero | Invariant 4 | `stale_tint` | World |
| workspace | **One zone of an open-plan map**: its pods inside a U of low partitions, in pod rows, under its sign | number + label → the zone's sign (`OfficeZoneSign`: number, label, accent stripe, hanging from the zone's top-left post over its aisle row; hovering it shows the repository and checkout, and "worktree of 3" for a mezzanine, in the tooltip panel `%WorldTip`), and the SPACES row, which says the sign's words (`OfficeZoneSign.number_text()` / `title_text()` write both); `worktree.repo_name` → the repository in the sign's tooltip and the SPACES row's; **`is_linked_worktree` → the checkout directory after it** (and a mezzanine's sign reads its checkout). **Mezzanines**: on one machine, workspaces with the same non-empty `worktree.repo_key` form a group; the non-linked member (lowest number if several) is the source zone, linked ones hang under it in workspace order, labelled `3A`, `3B` … `3Z`, `3AA` … (`ZoneModel.level_label`, `OfficeProjection.group_worktrees()`). A worktree whose source is not open, and other non-linked checkouts, stay zones of their own. A mezzanine is a full zone (compound keys, same layout), placed right under its source the first time only; grouping is display only and never enters the plan. SPACES lists zones ascending and indents mezzanines right after their source (`2`, `3`, `·3A`, `·3B`; `OfficeNavigator.section()`). Below 1280 logical units SPACES is a narrow rail: number chips and windows only, names and counts in the row tooltip. The sign reads `3A CHECKOUT` and its tooltip "worktree of 3"; a group shares one accent stripe on its signs (`sage` / `sky` / `terra` / `teal` / `lilac`, picked by the source's compound key, `OfficeZoneSign.accent_of()`): furniture that follows structure, not state | `panel`; palette `sage` `sky` `terra` `teal` `lilac` | HUD / zone sign |
| What Herdstead is showing | The highlighted SPACES heading (the machine whose map is shown), and a slim `paper` bar at the left edge of each SPACES row whose zone is in view | `SpaceHeadingCurrent` on the shown machine (`OfficeNavigator.shown_key`). `SpaceRowInView` on every zone whose rectangle (`ZonePlacement.bounds()`) meets the world on screen, worked out on every refresh and again whenever the camera or the world's room moves (`OfficeViewMarks.follow()`: no refresh, no row rebuilt, written only when the set changes); the list scrolls its first marked row into sight. A row click **pans** to its zone at once (its aisle row at the top of the world), and shows its machine's map first only when that is another machine's. Local browsing state only, never herdr's focus. No row is highlighted as "current": the zone PageUp / PageDown step from (`OfficeNavigator.current_zone()`) is not drawn | HudTheme `SpaceHeading` / `SpaceHeadingCurrent`, `SpaceRow`, `SpaceRowInView` | HUD |
| A zone's panes and their states | A row of windows under the zone's row in SPACES | One window per seated pane in seating order, at most 8, then `+N`. Colour: working / blocked / done their state colours (blocked while starting is blocked), idle and starting bright warm white, unknown grey, shell dark; all dark when the machine is not online (`OfficeSpaceRow.window_look()`). Hover → agent and state; click = clicking the row | HudTheme `Window*`: palette `working` `blocked` `unread` `cream` `muted` `slate` on `deep` | HUD |
| pane (list) | A row in the agent list in the right drawer | One row per pane (compound key): state icon; provider (upper case) + pane label; blocked → the wait; done → `UNREAD`; disconnected → Offline (never Idle). See "Agent list" | The pack's state badges, `ui.starting`, `ui.offline` | HUD |
| Global counts | Top bar counters MACHINES / BLOCKED · max / DONE / WORKING / IDLE / PANES | Online machines only (invariant 4). Blocked while starting counts as BLOCKED (`PaneModel.asks()`); starting and not blocked counts nowhere. Hover breaks down by machine → space. `max 12m` beside BLOCKED is the longest wait (`StateLog.longest()`, with `+` when a start was not observed); hover waits come from `StateLog.wait_of()`, `?` for a pane missing from the log. Clicks: BLOCKED → the longest wait, into answer mode (again → next); DONE → the oldest (select only); WORKING / IDLE → filter the list (or OVERVIEW's chips when it is open); PANES → toggle OVERVIEW; MACHINES is hover only. The window title's `(N)` is this BLOCKED number | The pack's state badges, `ui.connected` | HUD |
| Blocked out of sight | An arrow on the edge of the world toward it: `↓ 3 ! 2` (way, the zone's number as its sign writes it, blocked badge, count) | **Only the shown, online machine's map**: each zone with a blocked desk whose chip (or seat, while it draws none) is outside the world on screen gets one arrow, counting those desks, on the edge crossed by the line from the view's middle to its longest-waiting one (`EdgeArrowModel.of()`, pure); longest wait first; at most 8 (the 8th reads `+N` and its tooltip lists the rest). **Arrows never overlap and never leave the world**: an edge shows as many as it has room for between its ends (the side edges leave the top and bottom rows to the arrows there), by the arrows' own sizes, and its last place goes to a `+N` note for the zones that waited least, their lines in its tooltip (`EdgeArrowModel.fit()`, pure, per edge; `OfficeEdgeArrows` measures and folds again whenever its room or the compact form changes, with no refresh). Tooltip: `3 INFRA · 2 blocked · longest 12m` (`OfficeAttention.wait_text()`). Worked out on every refresh and whenever the camera or the world's room moves (`OfficeViewMarks.follow()`, no refresh), and once a second while any shows (the wait in the tooltip). A click **only pans** to that desk, as far as it takes (`OfficeNavigator.pan_to_desk()`): it selects nothing. Hovering one outlines its zone's SPACES row (worked out from where the pointer is and where the arrows stand now, so it survives a refresh that hands the arrows other zones; an arrow that something else covers there, the staff panel in answer mode, is not pointed at). Below 360 units of world (`edge_arrows_compact_from`) an arrow is compact: way, badge and count, the zone in the tooltip. None under the OVERVIEW, the strategic view or the monitor, and none for a machine that is not answering. **Another machine's blocked panes show only as its SPACES rows' counts** (and in the top bar, NEXT and the list). Arrows cover the world where they stand: what is under one cannot be clicked or hovered | Text + blocked badge; HudTheme `EdgeArrow`, `EdgeArrows` (`inset`, `gap`) | HUD |
| Next thing | NEXT at the right end of the staff panel, with `‹ ›` beside it | Says what a press does and to whom (`NEXT:` / `Answer CLAUDE web`, `Read` for done; ` @ bee` with several machines). Same as `N`, same order: while anyone is blocked only blocked panes cycle, otherwise done; longest wait first. It selects, switches **map** only when the pane is on another machine, pans to the desk and does the verb: blocked expands the panel and enters answer mode once the question shows (`N` then a digit answers; Enter never sends); done only expands. When the office cannot write (`--read-only`, the showroom) it shows herdr's state word instead of a verb and only selects. Nothing to do: `All clear`, greyed. Narrow screens write only provider and space. `‹ ›` step through the same queue, select only | Text | HUD |
| State changes observed this session | The bottom NEWS strip and the drawer's EVENTS tab | One event ring in the state log: a state change, a pane appearing / disappearing / changing terminal, a machine going online / offline. Only herdr's words. The duration is always **the segment that ended**, before the arrow: `11:40 CODEX ui working 38m → done`, `idle 3s+ → blocked`; when the ended segment was not a watched state, only the new state. Also `working · new pane`, `pane closed`, `idle · new terminal`, `bee offline`; identity changes are `new terminal` / `new agent` / `new session`. Launches: `starting` on an existing shell, `new pane · starting` for a new pane; until the kind is known the subject is the upper-cased name (`CLAUDE-2 api starting`). NEWS: newest on the left, at most 8 fixed buttons, a new one fades in once (not a ticker), a click selects the pane (disabled with `Pane gone` when it is gone). EVENTS: newest on top, at most 200 rows; the selected pane highlights its newest row | The pack's state badges, `ui.connected` / `ui.offline`; HudTheme `NewsBar` / `NewsItem` / `DrawerTabs` | HUD |
| Something happened while away | The window title's `(N) `, a Dock bounce, an optional chime | Title: N = BLOCKED, left out when nobody is blocked or all machines are disconnected; done stays the trailing `· n UNREAD`; `--no-title-count` drops it. Alerts fire only for new STATE / APPEARED / REPLACED events that turn a pane blocked (or done) and still count by the top bar's rules; the first snapshot, reconnects, machine changes and launches are baseline. Nothing alerts while the window has focus, and nothing is replayed later. Dock: blocked only, on by default (`--no-bounce`), at most once per stretch in the background, only after 3 s still blocked, never for herdr's focused pane. Chime: off by default; the `CHIME OFF` / `CHIME ON` switch at the right of the counter row (remembered in `user://herdstead.cfg` as `[alerts] chime`) or `--chime`; blocked two rising tones, done one softer tone; at most one per refresh, once per pane per 10 s. Sound is only redundancy | None (tones generated in code) | OS |
| Each pane's segments since opening | The OVERVIEW table (PANES or `O`) | One row per pane: AGENT (badge + provider; hourglass and `STARTING` while launching, except blocked while starting), SPACE / TAB, STATE, FOR (this segment), BLOCKED (total this session), TIMES (how many times blocked), TIMELINE (a state colour band; **hatching = not observed**: before the pane appeared, while disconnected, and the fold of the oldest segments past 256). The band's left edge is when the log first saw the pane; a pane present at opening starts in its state, not hatching. Axis: left-edge wall-clock time, 5 / 10 / 15 / 30 / 60-minute ticks, `now`; redrawn once a second while open. Disconnected rows dim, STATE `offline`, FOR `-`, shown only under ALL. A row click selects the pane. It covers the world, SPACES and the drawer without re-planning; chip reads stop. | HudTheme `Timeline` (hatching `slate` on `deep`, axis `muted`) and `Overview*` | HUD |
| Start not observed | A `+` after a duration (`3m+`) | **`+` = at least this long**: the state began before the office started watching (the first snapshot of a connection). NEWS, EVENTS, OVERVIEW, the top bar's `max`, counter hovers, the lens and the strategic view all read `StateLog.wait_of()` / `longest()`, so one blocked pane shows one number everywhere. The world writes it in the compact form (`compact_duration()`: `12m`, `3h+`; the lens line), the HUD in `wait_text()` (`1h 05m+`): the same wait, two spellings, one source. The card and the chip write no number for such a state | Text | HUD / Overlay |
| Map shell | Top outer wall + entry band + side walls; main aisle down the right; **no row walls** | Furniture. The top wall carries the lift door, windows (with a pantry, centred between the pantry and the door's clearance) and pictures; lanes of zones below the entry band, with aisle columns between lanes and an aisle row above each zone, plain floor. The lift door, above the main aisle's left lane, is where people enter and leave; it never opens and shows no state; it moves right when the map widens | `wall.cap_* / face_* / side_*`, `window`, `door`, `wall_frame` | Ground |
| tab | A pod of single desks: two facing rows of 32-unit desks across a low screen | label → **small text right under the pod** (the display face at 8, no wider than the pod, cut with a forced ellipsis); **`workspace.active_tab_id` → the open pod: its lamps are lit** | Table family `desk_*`, `screen_*`, `apron_*`, `leg_short`; `task_light` | Ground / desk |
| pane | A terminal at a seat | **Only a pane brings a laptop and a lamp**; the laptop shares the seat's axis, one 32-unit desk per column. A seat without a pane has only a chair. Tab layout → columns and far / near side; when missing, a pane keeps its seat, then free seats fill by stable pane key. The layout rect's `width` / `height` (terminal cells, 1–4096, else 0×0) sizes the terminal monitor's grid; the floor plan never reads it | Table family `monitor`, `task_light` | Desk |
| pane without agent | SHELL: an empty chair + a laptop with `$_` | Provider empty and not launch pending; static `$_` on the near screen and far lid; no blinking, no badge | Table family `monitor` views `shell_front / shell_rear` | Desk / Sorted |
| **herdr focus** | **That seat's lamp is brightest** | `focused_pane_id` → strong; other pane seats at the same pod → normal; pods that are not the active tab → weak. **Switch herdr here** (`pane.focus`) on the card switches herdr's **shared** view (every attached terminal follows; on a remote machine, that machine's session) **and turns every `done` of that tab into `idle`**. The lamp draws only the focus herdr reports back | `task_light` (off + three alpha steps, `OfficeTable` constants) | Desk |
| **Herdstead selection** | Four corner marks on the seat + a frame around the pod, 2 units outside its drawing (clear of the end desks' paper and the near chips); the seat's name plate shows | `picked_key`; with nothing picked it falls back to herdr's focus. The mark also frames a worker resting in the pantry | `ui.selection_seat` | Overlay |
| **Strategic view (`S`)** | A schematic of the shown machine's map over the world area, titled with the machine (`@ name` among several, and its state when not answering) (`OfficeStrategic`): **a section per zone**, in the SPACES rail's order, captioned with the words on the zone's sign (`3 INFRA`); SPACES, drawer, staff panel and NEWS stay usable | Sections flow down newspaper columns as tall as the room: one that fits a column is kept whole (in the next column when what is left of this one cannot hold it), one taller than the room splits at a pod-row boundary and repeats its caption as `3 INFRA …` (`StrategicLayout`). A caption is plain `paper` text in the sign's face (the display face at 8, in a 9-unit band, with a `slate` rule on to its column's edge), **never the zone's accent**: accents are structure in the world, and the view stays schematic; hovering a caption says what the sign's tooltip says; captions are not clickable. **A caption never changes the cell**: the cell and the columns are the desks' alone, a caption wider than its column's pods widens the column only into width the desks leave over (the first columns first), and one that still does not fit is cut with an ellipsis, its whole words leading its tooltip. Under a caption, the zone's pods in plan order (pod rows top to bottom, `origin.x` left to right), each a frame with its tab label, a far row and a near row of cells by `SeatPlacement.column`. One cell per seated pane (the largest of 32 / 24 / 16 / 12 / 8 units that fits), coloured by `OfficeSpaceRow.window_look()`; empty seats are not drawn. A blocked cell on an online machine writes its wait (`OfficeAttention.wait_text()`) when the cell is at least `wait_from` (24), else only in the hover tip (`CLAUDE · NEEDS INPUT · 12m+`). Provider is only in the tip (no initials, see below). Selection = four `blocked` corners, pointing = `OfficePointer`'s dashes, herdr's focus not drawn. Not a map: no plan coordinates, so nothing about aisles, pantry or furniture. Disconnected: tinted by `stale_tint`, all dark, no waits. Empty map: `No desks on this machine`. A cell click closes it, selects the pane and pans to it. A SPACES row (or PageUp / PageDown) while it is open scrolls it to that zone's section; a row or heading of another machine draws it again for that machine. While open: no lens, edge arrows or question reads; `M` and `O` open over it | No new art: a `_draw()` Control, theme type `Strategic` on the pack's `panel` | HUD |
| **Herdstead pointing (hover)** | A static dashed frame 2 units outside the station's click area, `ink` / `paper` (`OfficePointer`, `OVERLAY_Z`), for a pane anywhere on the shown map; on another machine, or for a zone, a 1-unit `paper` outline on that zone's SPACES row (`SpaceRowPointed`; a row in view keeps its bar beside it) | Hovering a NEWS entry, an agent list row, an EVENTS row (→ that pane) or an edge arrow (→ its zone). **It only points**: no selection, no map switch, no pan, no read, no write | No new art | Overlay / HUD |
| **Lens (hold `L`)** | Each agent station (or pantry spot) gets a "how long in this state" line in its own row; every seat's name plate shows; chips are not drawn; each pod's floor gets a wash of its most urgent state; furniture dims | The line is OVERVIEW's FOR in the in-world compact form (`OfficeAttention.compact_duration()`: `12m`, `3h`, `4d`, `+` when unobserved, starting included; 30 wide at most 18 of text); none for shells, `?` without a track, nothing on a disconnected machine. Wash: blocked → `blocked`, done → `unread`, working → `working`, idle or starting → `cream`, unknown → `muted`, shells only → `slate`, disconnected all `slate`, at `LENS_WASH_ALPHA`. Furniture (floor, aisles, walls, door, windows, pictures, plants, side tables and what they carry, the pantry, partitions, zone signs) is multiplied by `LENS_DIM`; signals stay bright. The selected pod's `blocked`-coloured frame darkens by `OfficeTable.LENS_FRAME` so it shows on a blocked wash. Off while the monitor or OVERVIEW is open or a text field has the keyboard. | No new art: Label, ColorRect | Overlay / Ground |
| agent | The person seated there (pixel people) | provider → **only the upper-case provider name on a 30-wide name plate, shown only while the seat is hovered or selected, or `L` is held**, in the row next to the badge (under `L`, where the lens line goes, it moves one row out) (the display face at 8; a longer name ends in an ellipsis, the whole name is in the card and the list); clothes and looks show neither provider nor state (see "Looks"). **No chest badge**: at 1 texel = 1 unit there is no room for a logo; provider logos appear only in Avatar Studio | Pixel people family (`art.people`) | Sorted / Overlay |
| agent state | **The station: pose + badge + things drawn only for the state** (see "Where people rest") | `agent_status` → the pack's `states`; `launch_pending` → starting, but **blocked wins**. idle leaves for the pantry; blocked raises a hand (`desk_blocked`) under a chip; done sits (`desk_idle`) beside a paper stack. The rules live only in `OfficeRests` (`scripts/world/office_rests.gd`); animations resolve through pixel people's `state_tracks`, the pantry plays `drink` by name | `ui.working / blocked / unread / idle / unknown / starting` | Sorted / Overlay |
| **How long it has waited** | **The blocked chip: the badge and a duration, nothing else** | `HerdrFleet.state_since` → the duration in the in-world compact form (`OfficeAttention.compact_duration()`, never `+` here: `59s`, `12m`, `3h`, `4d`, at most `99d`, 14 wide at most), in the chip's right half; the same badge node moves into its left half, pulse and all. When stale or when the start was never seen, no number and no frame are drawn (an empty frame reads as a blank chip) and the badge stays in the middle of its row; only the raised hand and badge remain, and the click / hover area stays. Not drawn while the lens is held (the lens line says it). The HUD writes the same wait in `wait_text()` (`1h 05m`): one wait, two spellings, one source (`StateLog`) | Text; `panel` nine-patch | Overlay |
| **The blocked question** | **A HUD tip when hovering the chip** (a ten-character excerpt in the chip would say nothing) | An excerpt of `pane.read` `detection`: lines trimmed of spaces and box characters, the last line with `?` (else the last non-empty line), at most 120 characters; the full question is in the card. Read only for blocked panes on screen (`PaneModel.asks()`), on an online machine with a current snapshot, not under the monitor or OVERVIEW; one read at a time; reads of one pane start at least 10 s apart; only the latest is cached, dropped on leaving blocked; no reads while minimized; it never writes and never counts as "seen". `--read-only` writes `read-only`; before the first read, `Question not read yet` (never a "reading…" placeholder: a disconnected machine never answers). A chip click selects and enters answer mode once the question shows; a click on the seat only selects | The HUD's `HdPanel` (`%WorldTip` in `hud.tscn`, which the zone signs' tooltip shares) | HUD |
| **done (UNREAD)** | **A small stack of papers right of this seat's laptop** | `done`, not launching, has an agent → visible (built with the pod, only `visible` changes; `OfficeTable.PAPERS_ASIDE` 13, on its side's working plane); frozen and dimmed with the map when disconnected | `done_stack_small` | Desk |
| State start | Order in the pantry | Earlier starts enter first. **Unknown** is only for a state never seen to begin (the first snapshot of a connection); it counts as the longest wait and goes first, ties in projection order. Every transition watched while connected has a **known** start from when it was observed: a state change, a launch ending, a new terminal / agent / session, a pane appearing. Blocked while starting counts from when it was seen blocked; a launch that ends while still blocked, same terminal / agent / session, keeps its clock. So newcomers queue behind those already there and never push anyone out; the order matches `N` | — | World |
| Pantry | One counter in the entry band, against the top wall at its left end | Furniture: only on maps with desks, placed by the map's plan alone; its spots run from the left wall to 16 short of the main aisle (12 at the shipped 23-cell map). **There is no reception.** The fixture row stays a barrier on every map with desks, pantry or not | `pantry` | Sorted |
| Partition | Low cream partitions round a zone: a U open at the top, a post at each top corner | Furniture: structure, never state. Down each side, along the bottom, at the zone's edges; people walk into a zone from its open top, never across a partition | `partition_v`, `partition_post`, `partition_corner_bl / _br`, `partition_h` | Sorted |
| Zone sign | A small hanging sign at a zone's top-left post, over its aisle row, as wide as what it says (at most 160, never past the top-right post; a long label ends in an ellipsis) | Display of the workspace's number and label, an accent stripe its worktree group shares (`OfficeZoneSign.accent_of()`); hovering it names the repository and checkout (a read of the frame the office holds, never of herdr); structure, never state | `panel`; palette `sage` `sky` `terra` `teal` `lilac` | Sorted |
| Furniture | Plants, side tables | Standing on the floor, origin = foot point, in the y-sort. **A row of plants along the top wall's foot** on the wall's own 160-unit grid (from 72), each the plant of its step, clear of the door, windows, pictures and pantry; **lane gaps** (3+ free cell rows inside a lane, outside every zone) stand a piece every two rows from the gap's second, in the lane's middle column, plants and side tables taking turns; a side table carries one desk piece (see "Desk decor"). Keyed by grid step, never placed by table, tab, zone or state, so their count does not follow tab count | `plant`, `plant_b`, `side_table` | Sorted |
| Wall picture | A framed landscape on the top wall | Furniture, on the wall's cream face (`FRAME_FOOT` 48). Centred in every second gap between two neighbouring windows, where it, grown by `FRAME_GAP` (8), touches no window, the door, the pantry or a wall-end cell; placed by the windows alone. Part of the shell (Ground: no footprint, not on the walk graph). Cream sky, sage hills, terra frame; no state colour (`working`, `blocked`, `unread`, `muted`, `task_light`) | `wall_frame` | Ground |
| Desk decor | Mugs, notebooks, clipped papers, plants, headphones, now and then a white cat: one piece on each **side table**, never on a pod's desks | A side table stands in a lane gap and carries one piece from the `desk` pool, or (28%) the `cat` pool, picked by weight from a stream seeded by its placement key alone (`OfficeDecorPlanner.side_table_item()`): never by tab, zone, state or time, so refreshes, growth and theme changes keep the choice. The cat's loaf, sleep and sit are static poses, not working / idle / done | `side_table`; `desk_mug / notebook / papers / plant / headphones`, `cat_loaf / sleep / sit` | Sorted |

Bold marks state signals. The Layer column follows [World model](WORLD_MODEL.md): flat on the floor or wall → `Ground`, standing on the floor → `Sorted`.

### Looks

A person's skin, hair style, hair colour, top, bottoms, hat / accessory and glasses follow the rules for **furniture**: they bind no herdr field
and never change with agent state, selection, focus or connection (a disconnected map dims as usual; the clothes stay). Looks hang on the
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
| Name plate (while hovered, selected or under the lens), state badge, chip, paper stack, selection marks, the station's click area | At once (they are the signals) | The current observation: who sits here, what state, how long, who is selected |
| Body position and pose | After arriving | Only at rest is it a state: seated = at the station (pose says the state); in the pantry = idle |
| Walking (the walk strip) | From an observed change until the body settles (at most 6 s, 96–480 units/s) | Transition only: not timed, not busy or idle |
| Ghost (a person without a plate walking to the lift door) | When a pane leaves the map | Transition: this station's person has left; no plate, badge or card; clicking it selects nothing |

- **Entering**: a pane with an agent (or launching) appears; its person walks in from the lift door along the main aisle to the seat's approach
  point and sits. Plate, badge and click area are at the seat from the start; clicking the seat selects it while the person is still walking.
  Far seats are entered straight from the approach point. **Near seats have the chair in line with the approach point, and people never walk through
  chairs**: they walk along the near aisle to the stand spot's column, step onto the stand spot (now only a route knee; nobody stands there), then step
  sideways into the seat; leaving reverses it. Pantry trips use the same legs.
- **Leaving**: when a pane closes or its agent leaves (it becomes SHELL), the person walks to the lift door and vanishes
  there (a pane moving to another workspace of the same machine changes seats instead: another zone of the same map). The seat frees at once (plate first); the walker is a **ghost**. At most 32 ghosts; beyond that the oldest vanishes.
- **Changing seats** (column, side, or the whole pod moved) is the same person walking over, not a leave and an arrival.
- **Identity**: a pane that switches to a different agent (both providers known and different) is one person leaving and one arriving; the same
  agent in a new terminal or session walks nowhere, with **one exception** in the pantry: the new state counts from when it was seen (a known,
  late start), so in a full pantry that person yields the spot to someone seated who has waited longer and walks back to the seat.
  If a pane leaves while its person is walking in, the same person turns around; if it returns (same identity) while its person is walking out,
  that person turns back. There are never two bodies.
- **Closing a tab's last pane** closes the tab: its pod vanishes and the person walks out from where it stood. **Closing a workspace's last
  pane removes its zone in place** (same map, same world): its pods are released and its people leave as ghosts, within `MAX_GHOSTS` 32, the
  routing budget and the 2880-unit route cap, and never while the map is frozen or the pass is cold; not every departure animates. **A new
  workspace** is a new zone whose people walk in from the lift door.
- **Cold means no walking**: first draw of a map, a **machine** or theme switch (the only rebuilds), the first snapshot after a reconnect, the refresh after a layout error —
  everyone appears in place, no ghosts, nothing replayed. **Individuals** also appear directly (ghosts vanish directly) when the route is too long
  for 6 s even at 480 units/s (5× the strip's native speed), when a plan change leaves them on a pod or wall, or when the observation's
  pathfinding budget ran out before their turn (arrivals first, then ghosts, then re-routes). People whose route ahead is still clear and whose
  target did not move keep walking.
- **Disconnected** (invariant 4): the whole map dims, walkers freeze mid-stride, ghosts vanish, and changes observed meanwhile are placed without
  walking; the reconnect is cold. Walkers stay frozen until the first drawable observation after reconnecting. A frozen person outside the pantry
  is the **only exception** to "only the pantry has people standing still", and the dimmed map says the picture is stale.
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
| starting | Walks in from the lift door and sits (`desk_start`); no chip, no paper stack (`PaneModel.launching()`). This form starts with the first snapshot after herdr accepts `agent.start` (`launch_pending`, no kind yet). **Blocked wins over starting**: an agent asked a question while starting is drawn as blocked (raised hand, chip, blocked badge, the kind on the plate) and counts in BLOCKED, NEXT, the edge arrows and Waiting; that it is still launching shows only in the card (`Launching` tooltip, footer `claude-2 asks: answer with the keys`). One blocked on arrival has its chip at the seat while it is still walking in | Plate + hourglass badge (`ui.starting`) at the seat; until the kind is known the plate shows the upper-cased name herdr gave the agent (`CLAUDE-2`, `PaneModel.agent_name`) |
| unknown | Their seat, sitting still (`desk_idle`) | Plate + `?` badge at the seat |
| done (UNREAD) | Their seat, sitting (`desk_idle`); a small paper stack right of the laptop (`done_stack_small`) | Plate + badge at the seat; stack on the desk |
| blocked (including asked while starting) | Their seat, hand raised (`desk_blocked`); a chip on the badge's row with the badge and the wait; hovering it shows the question excerpt | Plate + badge + chip at the seat |
| idle | The map's pantry, holding a cup (`drink`); each person has a preferred spot hashed from the pane key and, on conflict, takes the next free one in start order; when full, the rest sit (`desk_idle`) | In the pantry: badge; at the seat: plate + badge |
| SHELL / empty seat | Nobody | SHELL's laptop / nothing |

- What hangs on a person hangs where they **rest** and moves there the moment the observation arrives; the body follows. While an idle person is in
  the pantry the seat still clicks and selects the same pane (two click targets); an empty-for-now seat keeps its chair and ordinary laptop
  (never `$_`) with nothing over it.
- The chip's click area and the seat's never overlap: a seat click selects; a chip click selects and enters answer mode once the question shows
  (never sends; under `--read-only` it only selects). While a chip shows, the seat's click area gives up the tag row (far: its top drops from
  −90 to −72; near: its bottom rises from 32 to 14): every point belongs to one click area.
- Standing still happens only in the pantry or on a frozen, disconnected map; passers-by never stop. The pantry row is not a path: people step
  into it from the aisle below.
- A new terminal or session re-orders a pantry person from that moment; in a full pantry they sit back down, and two people may swap spots when one's
  hashed spot is the other's (an accepted consequence). This is the only case where "a new session walks nowhere" fails. Likewise an agent that has
  just finished launching queues behind those already in the pantry: if it is full, it sits and nobody moves.
- A map whose entry band cannot hold the pantry's counter and one spot has no pantry: idle people there sit, and the fixture row stays a barrier.
  (Every real map, 13 cells and wider, fits it; the rule is tested on hand-made plans.)
- Disconnected (invariant 4): pantry, chips and paper stacks freeze and dim; chips show no wait or frame; nothing is re-ordered. The first
  refresh after reconnecting is cold and re-orders (every start is unknown again).

## HUD panels

Everything below is HUD and never changes the world. The world draws only what their actions produce in the snapshot.

### Staff panel

The staff panel (the agent card; scene name `inspector`) runs across the bottom. **It is compact by default at every size**: on a screen
at least 400 units tall a card at the bottom-left (portrait, name, the state in a pill of its colour, location, and `‹ ›`, `Monitor ⤢`,
`Open ⏎` under them) with NEXT at the right end and the office showing, but not clickable, between them; below that one line (provider
· state · location, wait, `‹ ›`, `Monitor ⤢`, `Open ⏎` and NEXT). Compact, the preview is neither shown nor read. `Enter` or `Open ⏎` expands it to
full height: portrait, name, state, wait, location; the terminal preview; details (`PANE`: pane id, label, directory, session, terminal title);
actions (`▾ Esc`, Monitor, Answer, Switch herdr here); NEXT. `Esc` outside answer mode, `▾ Esc` or selecting another pane collapses it; `Esc` in
answer mode only leaves answer mode. A new terminal, agent, session or connection on the same pane does not collapse it. The world gives up the
panel's height; the drawer stays as it is. Every line fits the smallest 480×320-unit screen; a sentence that does not fit goes whole into the tooltip.

- **State words**: done adds `UNREAD = not yet seen / Not task success.`; disconnected adds `Connection lost. / Not an idle signal.`.
  The note stands under the caption of the opened panel; the card form has no row for it (the card is as tall as the portrait).
  **A shell's card** has no portrait, badge or timer: `SHELL`, `no agent` (the idle herdr reports for a shell is the terminal's). There is no terminal
  icon before SHELL: the pack's terminal image `ui.working` is WORKING's badge and would read as a state.
- **Preview**: blocked reads herdr's full `detection` (up to 200 rows), other states the end of `recent_unwrapped`; it shows the last 12 rows,
  monospace, long lines clipped. The header says how many rows show, how long ago, and whether rows were cut or clipped (`12 of 31 rows · 3s ago`,
  `recent · 3s ago`); when it cannot read it says why (`No preview: offline`) and never shows blank space as terminal content. It reads only at full
  height, not minimized, with the machine online and the snapshot current.
- **Switch herdr here** (with several machines **Switch herdr on <machine>**) is open only for a station the user clicked, while it is still the
  clicked terminal: when following herdr's focus it reads `Following herdr's focus`; on a new terminal `New terminal: pick again`. The note
  `Clears tab's UNREAD` warns that every pane's UNREAD of that tab clears. Result line: `herdr switched here` / `Not sent: <reason>` /
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
  `New worktree: branch <b> from this space` or `Branch: <why not>`. The first `Close` click only states the scope (`Closes CODEX's pane w2:p3.`, plus
  ` and its tab …`, ` and space …` or ` and mezzanine 3A "docs". The checkout stays on disk.` for a last pane; `Kills CLAUDE, still working.` when the
  agent is not idle) and relabels the button `Close · kills` or `Close · click again`; a second click within 10 s sends. The button is off for the last
  pane of the repo's own space while a mezzanine is open. Footer: `Closed w2:p3` / `New space w14` / `New worktree v1-a → w15`; a lost reply says the next
  snapshot decides. Rules: [the write boundary](WRITE_BOUNDARY.md) §5.
- In the world, a split pane first appears as an empty seat with an ordinary laptop; a person walks in only after a launch is accepted. A closed pane
  is the reverse (the person walks out, the pod or zone disappears, NEWS `pane closed`). A new space or worktree is a new zone of the same map
  in the snapshot, and the office's pick of its shell pans to its pod. Selecting the new pane, even across maps, is only a selection.
  `--read-only` and the showroom have no launch block.
- **A new pane is picked only if the viewer has not navigated since** (`OfficeNavigator.nav_revision`): a zone picked (a SPACES row), a machine picked (its heading), an edge arrow,
  PageUp / PageDown, `N`, `‹ ›`, a counter, the list, NEWS or EVENTS before the snapshot shows it cancels the pick and the footer says
  `…: not picked`; panning (a drag, the wheel, the arrows) and herdr's focus moving do not. **Changed with one map per machine**: PageDown then
  PageUp before the snapshot now leaves the new pane unpicked, where coming back to the same floor used to pick it.

### Agent list

The agent list lives in the right **drawer**. The drawer starts collapsed on every launch as a vertical tab `◀ AGENTS · n` (n = agents that need a
person); open, it has `AGENTS | EVENTS` tabs and `▶` to fold it. Maps are planned at the collapsed width and opening never re-plans: the open drawer
covers pods on the right, and the camera can pan to them. `A` opens it with the keyboard on the list in Flat view; `--drawer=open` starts it open.

- Rows: state icon, upper-case provider, pane label (or tab name), the wait for blocked rows (the chip's clock; none when disconnected),
  `UNREAD` for done.
- **Flat** groups by urgency: Waiting (blocked; unknown starts first, then longest wait — the pantry and `N` order), Unread, Working (including
  starting and not blocked), Idle (including unknown), Snoozed / hidden, Offline, Shells, History. **Tree** goes machine → space → mezzanine →
  tab → agent, with unseated panes and shells in their own groups.
- **Disconnected machines**: their agents are Offline (grey, `offline` icon, no wait), never Idle or Waiting; tree headers read `offline` with zero
  counts (invariant 4). A machine whose snapshot was rejected for exceeding limits is treated the same.
- A click selects the pane (the station-click path); double click / `Enter` opens it in the terminal monitor. The row menu (`⋯`, right click,
  Menu / `Shift+F10` / `.`) has Snooze 5 min / Resume reminder and Hide / Restore; they change only the local record, never herdr's UNREAD or the world.
- **History** comes from the state log through `AgentHistory`: one row per pane that was blocked or done this session and is not now, newest first,
  at most 200; trailing `OFFLINE` or `GONE`, none for ENDED. It covers only the pane's current run: after a new terminal, agent or session the old
  run is no longer a row (EVENTS still has the REPLACED event). History and EVENTS read one log: per pane and by time.
- A pane seats only when it and its tab declare the same workspace; a conflict is never rewritten, and the pane is listed as unseated (a click shows
  details without switching map). Machine totals include it; zone counts include only seated panes.

### Terminal monitor

The terminal monitor draws herdr's own screen (`pane.read visible ansi`, in the pane's real rows and columns); it is not pixel art, so like HUD text
it uses vector glyphs. It covers the whole office, which keeps refreshing underneath, and changes nothing in the world. It is a window, neither signal
nor furniture. The title shows provider, space / tab, state and wait; the status line shows `● LIVE INPUT` (raw mode), the last input's round trip,
and reasons (result unknown, refused, `no cursor from herdr`, keys herdr cannot name). A disconnected machine freezes and dims it with `○ OFFLINE`;
a new terminal shows `■ INPUT STOPPED` until **Follow new terminal**; `--read-only` shows `VIEW ONLY` and does not read. Input rules:
[the write boundary](WRITE_BOUNDARY.md) §3.

### SPACES rail

The left column lists each machine's zones in a section of its own, with a heading per machine when there is more than Local. **A heading
click shows that machine's map** (instant, cold: a new world, nobody walking; a machine that never connected opens as an empty map whose plate
says why), and the heading of the machine shown is the highlighted one. Under it, the machine's zones **in ascending number**, each mezzanine
right after its source (indented where the column has names): the number chip as the zone's sign writes it (`3`, a mezzanine's `3A`; no `F`),
the sign's words (`INFRA`, a mezzanine its checkout), blocked / UNREAD counts when non-zero, and a row of windows; the tooltip adds what the
sign's own tooltip says (repository, checkout, whose worktree). Below 1280 wide the column is a narrow rail: chip, windows and the blocked
count, the rest in the tooltip. Rows whose zone is in view wear a slim bar at their left edge, which follows panning.

A row click **pans** to its zone (its aisle row at the top of the world, as little sideways as brings its width in), and switches maps only for
a zone on another machine. PageUp / PageDown pan zone to zone in drawn row order, so **PageUp goes to the lower-numbered zone and PageDown to
the higher** (the FLOORS minimap drew the highest on top, and the keys went the other way), and cross machines at either end (from a machine's
last zone down into the next machine's first), stopping at the ends. An edge arrow pans to its desk and selects nothing; `N`, NEXT, the
counters, the list, NEWS and EVENTS pan to the desk, switching machine if needed; herdr's focus moving, while nothing is picked or the picked
pane is gone, pans to it as far as it takes (a heading or an edge arrow clicked before that move is drawn wins over it, and the move is not
replayed; the next one is followed). A machine's map seen for the first time opens on the selection's pod, else on its first zone
(the lowest number). Every change is instant: no transition, no lift car, no input lock. A zone that disappears is forgotten at once; a
machine that disappears takes its map with it. The `door` on the outer wall is furniture.

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
- Zone-level focus is not drawn: the focused pane's lamp already says where herdr's focus is, and the SPACES rail's in-view bars say what Herdstead is showing, which is not herdr's focus.

### Why laptop = pane and `$_` = SHELL

A herdr pane is a terminal; the office draws a laptop. A monitor offset sideways to clear faces read as belonging to the next seat, so the laptop
shares the column centre with person and chair and sits at its own edge of the desk. It is shaped after a silver MacBook (thin lid, narrow hinge,
keyboard and trackpad); 14 units wide, the far back 8 units high and the near front 11, small enough to leave the far worker's face, shoulders and arms visible without touching the Y-sort. A near worker sits at theirs with their back to the viewer, head and shoulders over it, so only its corners show beside the head; a shell's, with nobody in the chair, shows whole (the pushed-in chair's top is below it).

Seats come in three kinds: **empty** (a chair), **SHELL** (an empty chair + a `$_` laptop), **agent** (a person + an ordinary laptop). Launch pending is
never drawn as a shell, even before there is a provider. The `$_` is a static mark on the screen (near) or lid (far): no `>_` bubble, no blinking, no
output, so it says nothing about running, waiting or connection. The laptop uses the table family's `monitor` semantic ID, is a child of the table
and draws in node order (world model rule 4); pane or agent changes within capacity only swap textures and `visible`.

### Why one open-plan map with half-walled zones, not one room per tab

A tab is a table (a pod of desks), a workspace is a zone on an open-plan map, and worktree information goes on the zone's sign and
its tooltip. Full walls around each workspace would cut the office into rooms and hide who sits where; row walls across the map spent a band of every
row on wall. So a zone is bounded by **low partitions**, a U open at the top, drawn no taller than a seated person's legs: they say whose
workspace a desk belongs to without hiding anyone, and people walk into a zone from its open top.

- Under the top outer wall is a 96-unit entry band (three cells: wall clearance, the pantry's row, the walking lane); the main aisle on the right is
  64 wide; each side wall is one 32-unit cell; the front wall is not drawn.
- Below the entry band the map is **lanes** of 9 cells with a one-cell aisle between two; a zone stands in whole lanes under an aisle row of its own,
  its pods in rows as deep as a pod's reservation. Zones are placed as a masonry that only grows, down or right: retained zones hold their
  place, a growing zone grows in place while it can and otherwise moves alone, new zones take the top-most, left-most gap.
- Only the top outer wall has windows, pictures and the lift door. There are no inner walls.
- Walls assemble on one `TileMapLayer` grid: the top wall's two courses and the side walls. The row walls' joints are no longer laid.
- The base floor covers every cell of `floor_cells`; there are no carpets; walkways lie over the entry band and the main aisle.
- A map's first plan fixes its lanes. Window size, zoom, renames, state and focus never move pods; structural changes start from the old plan,
  prefer growing in place or into gaps, and an over-wide pod gets its own row (its zone taking more lanes, the map widening if it must). A
  removed pod or zone leaves a gap; nothing re-queues, and the map never shrinks.
- Panes that stay in the same tab keep their person nodes through growth, moves and side changes. Machine and theme switches rebuild the current world:
  the cache holds plans and views, not resident people per map.
- Plants and side tables are `StaticBody2D`s with foot points and footprints; they never take pods, zones, the entrance or aisles, and
  they are not a reading of how many tabs or agents there are. Nothing stands by the door or on the pantry.

A pod's width, seats, stand spots, approach points and draw extents come from `OfficeTable.measure()` ([World model](WORLD_MODEL.md)); the rows
over a seat (badge, chip, lens line, name plate) are measured there too, on the Labels once the display face is on.
Layout validation runs on the graph people walk (door threshold, reach to every approach point, the legs to stand spot and seat, wall clearance for
a full person canvas), so a validated map is a walkable map ([World model](WORLD_MODEL.md), "Collision and walking").

## Not drawn, and why

| Idea | Why not |
|---|---|
| Laptop screens coloured by state | Needs screen rectangles in the table manifest; hard-coding them would break "table geometry only in `table.gd`, assets only by semantic ID". Add a `screen` field when the table art is next rebuilt. |
| Idle wandering | People walk only on observed changes. With no change nobody moves: walking is not a channel for any field. |
| `layout.zoomed`, pane `scroll` | No drawing without new art that would not clash with existing channels. `HerdrSnapshot.from_wire()` drops them (invariant 2: no field nobody draws). |
| Dusk as a runtime palette-swap shader | Tables are drawn from the palette by their builder and pixel people are one family shared by every pack, so a LUT would cover only tiles / props / UI. Dusk was derived at build time instead, and then retired (2026-09-29): night is to be a light over the one pack, a modulate, not a palette swap. |
| A minimap scaled from plan coordinates | A map is far larger than the world area (≈ 820 × 308 at 2×): scaled down to fit, a desk would be a few units, and aisles, pantry and furniture would read as signals. The strategic view keeps only order, columns and side. |
| Zoom below 2 to see a whole map | Zoom is the window's content scale (`OfficeScene.fit_window()`, `ZOOM_MIN := 2`); at 1× density-2 nearest families lose half their outlines, and a large map still does not fit. |
| Provider initials in strategic cells | Of 23 providers five start with C and three with K; initials are ambiguous and break "one concept, one channel". Provider stays in the hover tip. |

## Asset pipeline

- `make art` rebuilds every pack: it rebuilds `assets/`, and `tools/check_build_clean.py` proves the result matches the commit (CI does
  the same). Only `art/daylight/` is edited.
- Semantic IDs and sizes have one source, `art/daylight/pack.json`; Python checks only that PNGs and the manifest agree.
- `make check-packs` reports IDs in a pack that `scripts/art/art_contract.gd` does not require as `PACK_UNUSED` (`wall.front_*` and
  `wall.threshold`, which no scene lays, are always among them). The builder prunes generated images the manifest no longer declares.

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

- **"Standing" and "passing by" look alike.** Only the pantry and a frozen, disconnected map have people standing still. A map has one pantry, whatever the number of its zones. The pantry is in the
  entry band against its counter; passers-by never stop and carry no plate or badge (those stay where the person rests). The one person standing
  still outside the pantry is frozen by a disconnect, and then the whole map is dimmed.
