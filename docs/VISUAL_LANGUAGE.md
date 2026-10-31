# Herdstead visual language: what each herdr concept is in the office

This document answers one question: **what does each thing on screen stand for in herdr, and where is each herdr field drawn?**
Depth, origins and picking are in [World model](WORLD_MODEL.md); asset sizes in [Asset spec](ASSET_SPEC.md); the HUD actions that
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
   - **Agent state (`agent_status` and launch pending) has one channel: the station** — the approved complete workstation's pose,
     the badge below it, and the blocked chip. Every state stays at the seat. There is no walking, raised-hand rig or separate
     state prop in this phase; nothing else in the world shows agent state.
   - **State start** (when this state began) has one other reading: the `N` order. The chip's wait is its one drawing at the seat.
   - **Zone aggregates are not drawn in the world** (how many UNREAD or blocked in a zone). They live in the HUD (the portrait bar, edge
     arrows), derived from the current model, never summed from events. The lens's wash under each pod is the one exception, only while held.
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
| machine | **One open-plan map** (every workspace of the machine a zone on it); only one machine's map is drawn at a time | label → the machine plate over the map (`@ name` once there is more than Local, then LIVE / OFFLINE / CONNECTING and the ssh error; a machine with no workspace is an empty map whose note says why); a zone the map cannot be laid out for is named there, inside the plate's band (`Layout unavailable: 3 INFRA: …`, in the blocked colour, cut with an ellipsis where the band is short and whole in its tooltip); label → its chip in the top bar after the wordmark (when there is more than Local; cut to 40 units, 20 below 640, whole in its tooltip), on `slate` while its map is the one shown; a click on a chip switches to that machine's map, at once and cold (a machine that never connected opens as an empty map with its note); connection → the chip's words: `paper` live, `muted` connecting, the blocked colour offline, and its tooltip (the status line's line for it); the top bar's status line (`1 OFFLINE / …` in the blocked colour while a machine is down), hover: one line per machine with LIVE / CONNECTING / OFFLINE and time since its last snapshot (`HerdrFleet.heard_since`) | HudTheme `MachineChip`, `MachineChipConnecting`, `MachineChipOffline`, `…Current` | HUD |
| Machine disconnected | **Its whole map** dims and freezes, every zone of it; counts go to zero | Invariant 4 | `stale_tint` | World |
| workspace | **One zone of an open-plan map**: its pods inside a U of low partitions, in pod rows, under its sign | number + label → the zone's sign (`OfficeZoneSign`: number, label, accent stripe, hanging from the zone's top-left post over its aisle row; hovering it shows the repository and checkout, and "worktree of 3" for a mezzanine, in the tooltip panel `%WorldTip`), and a portrait card's place, whose tooltip says the sign's words (`OfficeZoneSign.number_text()` / `title_text()` write both); `worktree.repo_name` → the repository in the sign's tooltip and the place's; **`is_linked_worktree` → the checkout directory after it** (and a mezzanine's sign reads its checkout). **Mezzanines**: on one machine, workspaces with the same non-empty `worktree.repo_key` form a group; the non-linked member (lowest number if several) is the source zone, linked ones hang under it in workspace order, labelled `3A`, `3B` … `3Z`, `3AA` … (`ZoneModel.level_label`, `OfficeProjection.group_worktrees()`). A worktree whose source is not open, and other non-linked checkouts, stay zones of their own. A mezzanine is a full zone (compound keys, same layout), placed right under its source the first time only; grouping is display only and never enters the plan. PageUp / PageDown step through the zones ascending, mezzanines right after their source (`2`, `3`, `3A`, `3B`; `OfficeNavigator.section()`, `OfficeFrame.zone_order`), and the strategic view's sections follow that order. The sign reads `3A CHECKOUT` and its tooltip "worktree of 3"; a group shares one accent stripe on its signs (`sage` / `sky` / `terra` / `teal` / `lilac`, picked by the source's compound key, `OfficeZoneSign.accent_of()`): furniture that follows structure, not state | `panel`; palette `sage` `sky` `terra` `teal` `lilac` | HUD / zone sign |
| workspace (its worktree group) | **A carpet under the zone**: one flat, muted carpet inside its partitions, from the zone's top (open, like the U) down to its bottom partition, never under its aisle row, an aisle column or a corridor | Structural binding, like the sign's stripe: the worktree group (the source's compound key for a mezzanine, the zone's own otherwise) → its family, `OfficeZoneSign.carpet_of()` = `ArtContract.CARPETS[accent_of()]`, so a group shares one carpet as it shares one stripe. Placed by the plan (`OfficeShell.carpet_rect()`) and the key alone: reads no state, wait, focus, selection or connection; the lens dims it with the furnishing, a dropped machine dims and freezes it with the map | `carpet_sage` `carpet_sky` `carpet_terra` `carpet_teal` `carpet_lilac` (nine-patch; palette `carpet_<family>` / `carpet_<family>_edge`) | Ground |
| What Herdstead is showing | The current machine chip in the top bar (the machine whose map is shown) | `MachineChip…Current` (a `slate` fill) on the shown machine (`OfficeNavigator.shown_key`); the chips show only among several machines. Which zones are in view is the view itself: nothing else marks them (the SPACES rail's in-view bars retired with it). A card's place click **pans** to its zone at once (its aisle row at the top of the world), and shows its machine's map first only when that is another machine's; it selects nothing. Local browsing state only, never herdr's focus. The zone PageUp / PageDown step from (`OfficeNavigator.current_zone()`) is not drawn | HudTheme `MachineChip*` | HUD |
| Who needs you: the portrait bar | Cards in the top bar, left to right: the blocked, the done, the working, the idle | One per agent of an online machine (invariant 4: a dropped machine's agents have none, the status line says `1 OFFLINE / …` in the blocked colour). A shell has none, nor has an agent herdr is still launching that does not ask; blocked while starting is blocked (`PaneModel.asks()`); a state the pack does not draw is idle. The blocked stand in the order `N` visits them (`OfficeNavigator.waiting()`), the done oldest first, the working and the idle in place order (`PortraitBarModel.of()`). A card: the same still generic portrait for every agent, whole on a tall bar's tile and cropped on a short bar's card; the pane's display name; its space after a tag in its worktree group's carpet family (the sign's and the carpet's, never state); a frame in its state's colour (blocked, unread, working, muted), over the portrait's edge on a tall bar's tile (B2) and round the whole card on a short bar's; on a tile, the state's small mark in the window's corner (`!`, envelope, a working dot, an idle white dot: the pack's `badge_<badge>_small`, never pulsed); a ring on the selection (paper on a card, ink on a tile's cream window); a blocked card's wait (`StateLog.wait_of()` in `wait_text()`, `+` when the start was not observed; the leftmost's is the longest). When they do not fit, a fixed ladder (`PortraitBarModel.fit()`, from the widths the scene measures): the working and the idle fold (`+12` over `working`), the done and then the blocked go face-only, the done fold, everything but the blocked faces becomes a tally (`+12`), and last the blocked keep as many faces as fit before a `+N`: the longest-waiting blocked are the last to fold. Hover: a card's whole name, provider, state and wait, space / tab, and its machine among several; its place, the zone's sign words and the sign's tooltip; a fold's names. Clicks: a card's face or name selects (a desk click's path, no answer mode); its place (the tag and the space, the lower half of its words) pans to its zone and selects nothing (an unseated pane's place is only words); a machine chip shows its machine's map; a fold or a tally opens the OVERVIEW on its state, or toggles that chip while it is open; `1 machine · 13 panes` toggles the OVERVIEW. No number key reaches a card. The window title's `(N)` is the blocked count | `WorkstationArt.portrait_texture()`; the pack's `badge_<badge>_small` (tiles only); HudTheme `PortraitCard*`, `PortraitTile`, `PortraitWindow`, `PortraitFrame*`, `PortraitFaceBare`, `PortraitFold*`, `PortraitSelected[Tile]`, `PortraitPointed[Tile]`, `PortraitPlaceButton`, `CarpetTag*` | HUD |
| Blocked out of sight | An arrow on the edge of the world toward it: `↓ 3 ! 2` (way, the zone's number as its sign writes it, blocked badge, count) | **Only the shown, online machine's map**: each zone with a blocked desk whose chip (or seat, while it draws none) is outside the world on screen gets one arrow, counting those desks, on the edge crossed by the line from the view's middle to its longest-waiting one (`EdgeArrowModel.of()`, pure); longest wait first; at most 8 (the 8th reads `+N` and its tooltip lists the rest). **Arrows never overlap and never leave the world**: an edge shows as many as it has room for between its ends (the side edges leave the top and bottom rows to the arrows there), by the arrows' own sizes, and its last place goes to a `+N` note for the zones that waited least, their lines in its tooltip (`EdgeArrowModel.fit()`, pure, per edge; `OfficeEdgeArrows` measures and folds again whenever its room or the compact form changes, with no refresh). Tooltip: `3 INFRA · 2 blocked · longest 12m` (`OfficeAttention.wait_text()`). Worked out on every refresh and whenever the camera or the world's room moves (`OfficeViewMarks.follow()`, no refresh), and once a second while any shows (the wait in the tooltip). A click **only pans** to that desk, as far as it takes (`OfficeNavigator.pan_to_desk()`): it selects nothing. Hovering one outlines its zone's blocked cards in the top bar (worked out from where the pointer is and where the arrows stand now, so it survives a refresh that hands the arrows other zones; an arrow that something else covers there, the bottom panel in answer mode, is not pointed at; a blocked agent folded into a tally has no card to outline). Below 460 units of world (`edge_arrows_compact_from`: the 480×320 minimum's 456) an arrow is compact: way, badge and count, the zone in the tooltip. None under the OVERVIEW, the strategic view or the monitor, and none for a machine that is not answering. **Another machine's blocked panes show only as cards in the top bar** (and in NEXT and the OVERVIEW). Arrows cover the world where they stand: what is under one cannot be clicked or hovered | Text + blocked badge; HudTheme `EdgeArrow`, `EdgeArrows` (`inset`, `gap`) | HUD |
| Next thing | NEXT at the right end of the bottom panel's AGENT page, with `‹ ›` beside it and the card's verbs under them | Says what a press does and to whom, by the pane's display name (`NEXT:` / `Answer needs approval`, `Read` for done; ` @ bee` with several machines; the space only in the tooltip). Same as `N`, same order: while anyone is blocked only blocked panes cycle, otherwise done; longest wait first. It selects, switches **map** only when the pane is on another machine, pans to the desk and does the verb: blocked expands the panel and enters answer mode once the question shows (`N` then a digit answers; Enter never sends); done only expands. When the office cannot write (`--read-only`, the showroom) it shows herdr's state word instead of a verb and only selects. Nothing to do: `All clear`, greyed, on the pill's own opaque `deep` fill with a `slate` edge. Docked it says `NEXT:`, whom and the wait in a row; opened on a short screen it reads down; the folded line of a narrow screen writes only the name. `‹ ›` step through the same queue, select only | Text | HUD |
| State changes observed this session | The NEWS line in the bottom panel's top row, and the panel's EVENTS page | One event ring in the state log: a state change, a pane appearing / disappearing / changing terminal, a machine going online / offline. Only herdr's words. A pane's subject is **its display name at the event** (`StateLog.Event.name`, cut to 24 grapheme clusters with `…`; the entry's tooltip says it whole) and its space. The duration is always **the segment that ended**, before the arrow: `11:40 refactor the fleet · api working 38m → done`, `idle 3s+ → blocked`; when the ended segment was not a watched state, only the new state. Also `working · new pane`, `pane closed`, `idle · new terminal`, `bee offline`; identity changes are `new terminal` / `new agent` / `new session`. Launches: `starting` on an existing shell, `new pane · starting` for a new pane (`main · api starting`). A name changing alone (a new task summary) is kept by the log (its `version` moves) but is no event. No path ever shows. NEWS: newest on the left, at most 8 fixed buttons, a new one fades in once (not a ticker), a click selects the pane (disabled with `Pane gone` when it is gone). EVENTS: newest on top, at most 200 rows, one line each (time, badge, who, what); the selected pane highlights its newest row; a row's click picks its pane and keeps the page | The pack's state badges, `ui.connected` / `ui.offline`; HudTheme `NewsBar` / `NewsItem` / `PanelTabs` | HUD |
| Something happened while away | The window title's `(N) `, a Dock bounce, an optional chime | Title: N = the blocked agents (the portrait bar's), left out when nobody is blocked or all machines are disconnected; done stays the trailing `· n UNREAD`; `--no-title-count` drops it. Alerts fire only for new STATE / APPEARED / REPLACED events that turn a pane blocked (or done) and still count by the portrait bar's rules; the first snapshot, reconnects, machine changes and launches are baseline. Nothing alerts while the window has focus, and nothing is replayed later. Dock: blocked only, on by default (`--no-bounce`), at most once per stretch in the background, only after 3 s still blocked, never for herdr's focused pane. Chime: off by default; the `CHIME OFF` / `CHIME ON` switch right of the strip (remembered in `user://herdstead.cfg` as `[alerts] chime`) or `--chime`; blocked two rising tones, done one softer tone; at most one per refresh, once per pane per 10 s. Sound is only redundancy | None (tones generated in code) | OS |
| Each pane's segments since opening | The OVERVIEW table (`1 machine · 13 panes`, a fold, or `O`) | One row per pane: AGENT (badge + the pane's display name, `StateLog.Track.name`; hourglass and `STARTING` while launching, except blocked while starting; the AGENT sort orders by that name, ties by pane key), SPACE / TAB (no tab for a workspace's lone default one), STATE, FOR (this segment), BLOCKED (total this session), TIMES (how many times blocked), TIMELINE (a state colour band; **hatching = not observed**: before the pane appeared, while disconnected, and the fold of the oldest segments past 256). The band's left edge is when the log first saw the pane; a pane present at opening starts in its state, not hatching. Axis: left-edge wall-clock time, 5 / 10 / 15 / 30 / 60-minute ticks, `now`; redrawn once a second while open. Disconnected rows dim, STATE `offline`, FOR `-`, shown only under ALL. A row click selects the pane. It covers the world without re-planning; chip reads stop. Shells have rows too: a zone of shells only is reached from here (a row click picks the shell, shows its zone and pans to its desk). | HudTheme `Timeline` (hatching `slate` on `deep`, axis `muted`) and `Overview*` | HUD |
| Start not observed | A `+` after a duration (`3m+`) | **`+` = at least this long**: the state began before the office started watching (the first snapshot of a connection). Whatever says it names the pane by its display name (the log's `name`), never by the provider word alone. NEWS, EVENTS, OVERVIEW, the portrait cards' waits and tooltips, the lens and the strategic view all read `StateLog.wait_of()`, so one blocked pane shows one number everywhere. The world writes it in the compact form (`compact_duration()`: `12m`, `3h+`; the lens line), the HUD in `wait_text()` (`1h 05m+`): the same wait, two spellings, one source. The card and the chip write no number for such a state | Text | HUD / Overlay |
| Map shell | Top outer wall + entry band + side walls; main aisle down the right; **no row walls** | Furniture. The top wall carries the lift door, windows (with a pantry, centred between the pantry and the door's clearance) and pictures; lanes of zones below the entry band (the narrowest pod spans two lanes), with aisle columns between lanes and an aisle row above each zone, plain floor. The lift door, above the main aisle's left lane, never opens and shows no state; it moves right when the map widens. No arrival/departure animation uses it | `wall.cap_* / face_* / side_*`, `window`, `door`, `wall_frame` | Ground |
| tab | A logical pod of complete workstations: far and near rows, both facing front, at 96-unit column pitch and feet −128 / 0 | label → **small text right under the pod** (the display face at 8 in `paper`, on its zone's carpet, no wider than the pod, cut with a forced ellipsis), **except the lone tab of a workspace herdr still calls by its number** (`label == str(number)` or the tab id: `DisplayName.tab_shown()`, `RoomModel.label_shown`), which says nothing there, nor in any place a pane is said to be (`PaneModel.place()`: `api`, not `api / 1`); **`workspace.active_tab_id` → the focus underlines' normal or weak level** | `WorkstationArt`; `task_light` colour | Sorted / Ground label |
| pane | A terminal bound to a workstation | Every slot has a complete workstation image; only a pane enables picking and annotations. Tab layout → columns and logical far / near row; when missing, a pane keeps its seat, then free seats fill by stable pane key. The layout rect's `width` / `height` (terminal cells, 1–4096, else 0×0) sizes the terminal monitor's grid; the floor plan never reads it | `WorkstationArt` | Sorted |
| pane without agent | SHELL: the empty complete workstation | Provider empty and not launch pending; no person, badge or `$_`. Same image as a vacant slot, distinguished by the pane's name, enabled picking and focus/selection; the card says SHELL | `WorkstationArt.empty_texture()` | Sorted / Overlay |
| **herdr focus** | **A thin underline at the workstation's foot** | `focused_pane_id` → strongest; other pane seats in active or unknown tabs → normal; inactive tabs → weak; vacant slots → off. `OfficeStation.LIGHT_ALPHA` = 0 / .15 / .35 / 1 for OFF / DIM / ON / FOCUS. **Switch herdr here** (`pane.focus`) on the card switches herdr's **shared** view (every attached terminal follows; on a remote machine, that machine's session) **and turns every `done` of that tab into `idle`**. The underline draws only the focus herdr reports back | `task_light` colour on a 62×1 `Polygon2D` | Sorted |
| **Herdstead selection** | A one-unit outline around the complete workstation + a frame around the pod, 2 units outside its render envelope; the seat's name plate shows | `picked_key`; with nothing picked it falls back to herdr's focus. Independent of the focus underline | `Line2D`; pod frame bars | Overlay |
| **Strategic view (`S`)** | A schematic of the shown machine's map over the world area, titled with the machine (`@ name` among several, and its state when not answering) (`OfficeStrategic`): **a section per zone**, in the page keys' order (`OfficeNavigator.section()`), captioned with the words on the zone's sign (`3 INFRA`); the top bar and the bottom panel stay usable | Sections flow down newspaper columns as tall as the room: one that fits a column is kept whole (in the next column when what is left of this one cannot hold it), one taller than the room splits at a pod-row boundary and repeats its caption as `3 INFRA …` (`StrategicLayout`). A caption is plain `paper` text in the sign's face (the display face at 8, in a 9-unit band, with a `slate` rule on to its column's edge), **never the zone's accent**: accents are structure in the world, and the view stays schematic; hovering a caption says what the sign's tooltip says; captions are not clickable. **A caption never changes the cell**: the cell and the columns are the desks' alone, a caption wider than its column's pods widens the column only into width the desks leave over (the first columns first), and one that still does not fit is cut with an ellipsis, its whole words leading its tooltip. Under a caption, the zone's pods in plan order (pod rows top to bottom, `origin.x` left to right), each a frame with its tab label, a far row and a near row of cells by `SeatPlacement.column`. One cell per seated pane (the largest of 32 / 24 / 16 / 12 / 8 units that fits), coloured by `StrategicModel.window_look()` (the one state scale, once the SPACES rail's windows: working / blocked / done their colours, blocked while starting blocked, idle and starting `cream`, unknown `muted`, a shell or a machine not answering `slate`); empty seats are not drawn. A blocked cell on an online machine writes its wait (`OfficeAttention.wait_text()`) when the cell is at least `wait_from` (24), else only in the hover tip (the pane's name, then `CLAUDE · NEEDS INPUT · 12m+`, then where). Provider is only in the tip (no initials, see below). Selection = four `blocked` corners, pointing = `OfficePointer`'s dashes, herdr's focus not drawn. Not a map: no plan coordinates, so nothing about aisles, pantry or furniture. Disconnected: tinted by `stale_tint`, all dark, no waits. Empty map: `No desks on this machine`. A cell click closes it, selects the pane and pans to it. A card's place (or PageUp / PageDown) while it is open scrolls it to that zone's section; a place or a chip of another machine draws it again for that machine. While open: no lens, edge arrows or question reads; `M` and `O` open over it | No new art: a `_draw()` Control, theme type `Strategic` on the pack's `panel` | HUD |
| **Herdstead pointing (hover)** | A static dashed frame 2 units outside the station's stable signal rectangle (image plus reserved annotation rows), `ink` / `paper` (`OfficePointer`, `OVERLAY_Z`), for a pane anywhere on the shown map; for a pane on another machine, a 1-unit `paper` ring 2 units inside its portrait card (`PortraitPointed`; inside the selection's ring, which is 1 unit in, so the state's edge, the selection and the pointing nest and all show), and for a zone, the same ring on each of its blocked cards; a pane folded into a fold or a tally has no card to ring | Hovering a NEWS entry, an EVENTS row, a HISTORY line, a portrait card (→ that pane) or an edge arrow (→ its zone). **It only points**: no selection, no map switch, no pan, no read, no write | No new art | Overlay / HUD |
| **Lens (hold `L`)** | Each agent station gets a "how long in this state" line in its own row, ink on a paper tag (not dimmed); every seat's name plate shows; chips are not drawn; each pod's floor gets a wash of its most urgent state; furniture dims | The line is OVERVIEW's FOR in the in-world compact form (`OfficeAttention.compact_duration()`: `12m`, `3h`, `4d`, `+` when unobserved, starting included; 30 wide at most 18 of text); none for shells, `?` without a track, nothing on a disconnected machine. Wash: blocked → `blocked`, done → `unread`, working → `working`, idle or starting → `cream`, unknown → `muted`, shells only → `slate`, disconnected all `slate`, at `LENS_WASH_ALPHA`. Furniture (floor, aisles, walls, door, windows, pictures, plants, side tables and what they carry, the pantry and its sign, partitions, zone signs) is multiplied by `LENS_DIM`; signals stay bright. The selected pod's `blocked`-coloured frame darkens by `OfficeTable.LENS_FRAME` so it shows on a blocked wash. Off while the monitor or OVERVIEW is open or a text field has the keyboard. | No new art: Label, ColorRect | Overlay / Ground |
| agent | The generic person in the complete workstation | **The pane's display name in `ink` on a paper tag as wide as the name (94 units at most, widened up to 190 into a vacant neighbour's slot), shown at all times on a map with few occupied seats (at most `FloorLayoutPolicy.FEW_SEATS`, 16, agents and shells; S3 SEATTAGS), otherwise only while the seat is hovered or selected, or `L` is held**, 10 units tall, below the badge; under `L` it moves below the lens line. Never a state signal: ink on paper in every state (the display face at 8, as written, not upper-cased; a longer name is cut with a forced ellipsis, and **hovering the seat shows the whole name** with who and in what state and where in the world tooltip `%WorldTip`; the card and the OVERVIEW say it whole too). The display name is worked out in one place, `DisplayName` (`PaneModel.name`, `StateLog.Sighting.name`): herdr's terminal title (Claude Code's task summary) unless it says nothing a provider word would not (empty once its spinner and marks are stripped, the provider, `<provider> code`, the agent's name, a shell's name); else the pane's label; else its tab's label unless herdr's default; else its directory's last component; else herdr's agent name; else `pane <id>`; never the provider word alone; at most 80 grapheme clusters. It is remote text: shown, never sent, never a key. Provider is UI words only; no per-pane look or world logo | `WorkstationArt`; name Label | Sorted / Overlay |
| provider | A kind word on the card's seat line (`CLAUDE · api / main`) and in portrait-card, seat and strategic-view tooltips | `provider` → the catalog's display word. It never changes the generic image or portrait; no world provider mark is drawn | Text | HUD |
| agent state | **The station: complete-image pose + badge + blocked chip** (see "Stationary observations and approved states") | `agent_status` → the workstation's semantic clip and the pack's state badge; `launch_pending` → static starting, but **blocked wins**. Working/idle loop, blocked enters/reclines/exits, done nods once; unknown/starting hold frame 0. No separate paper or mug, raised-hand rig, or legacy `state_tracks` lookup | `WorkstationArt`; `ui.working / blocked / unread / idle / unknown / starting` | Sorted / Overlay |
| **How long it has waited** | **The blocked chip: the badge and a duration, nothing else** | `HerdrFleet.state_since` → the duration in the in-world compact form (`OfficeAttention.compact_duration()`, never `+` here: `59s`, `12m`, `3h`, `4d`, at most `99d`, 14 wide at most), in the chip's right half, in the pack's figures face (Tiny5 at 8, as is the lens line: the world's only words outside Fusion Pixel, whose 8px digits would make `99m` 16 wide, more than the fixed 30-unit chip has for text); the same badge node moves into its left half, pulse and all. When stale or when the start was never seen, no number and no frame are drawn (an empty frame reads as a blank chip) and the badge stays in the middle of its row; the complete image, badge and click / hover area remain. Not drawn while the lens is held (the lens line says it). The HUD writes the same wait in `wait_text()` (`1h 05m`): one wait, two spellings, one source (`StateLog`) | Text; `panel` nine-patch | Overlay |
| **The blocked question** | **A HUD tip when hovering the chip** (a ten-character excerpt in the chip would say nothing) | An excerpt of `pane.read` `detection`: lines trimmed of spaces and box characters, the last line with `?` (else the last non-empty line), at most 120 characters; the full question is in the card. Read only for blocked panes on screen (`PaneModel.asks()`), on an online machine with a current snapshot, not under the monitor or OVERVIEW; one read at a time; reads of one pane start at least 10 s apart; only the latest is cached, dropped on leaving blocked; no reads while minimized; it never writes and never counts as "seen". `--read-only` writes `read-only`; before the first read, `Question not read yet` (never a "reading…" placeholder: a disconnected machine never answers). A chip click selects and enters answer mode once the question shows; a click on the seat only selects | The HUD's `HdPanel` (`%WorldTip` in `hud.tscn`, which the zone signs' tooltip shares) | HUD |
| **done (UNREAD)** | **One nod, then a still; unread badge** | `done`, not launching, has an agent → approved `done` clip once. A refresh does not replay it. UNREAD is not success | `WorkstationArt`; `ui.unread` | Sorted / Overlay |
| **idle** | **The approved idle/blink loop; idle badge** | `idle`, not launching, has an agent → approved `idle` clip. Paused and dimmed with the map on disconnect, never used as a disconnected substitute | `WorkstationArt`; `ui.idle` | Sorted / Overlay |
| State start | The `N` order | Earlier starts come first. **Unknown** is only for a state never seen to begin (the first snapshot of a connection); it counts as the longest wait and goes first, ties in projection order. Every transition watched while connected has a **known** start from when it was observed: a state change, a launch ending, a new terminal / agent / session, a pane appearing. Blocked while starting counts from when it was seen blocked; a launch that ends while still blocked, same terminal / agent / session, keeps its clock. So newcomers queue behind those already waiting | — | World |
| Pantry | A corner nook: one counter in the entry band, against the top wall at its left end | Furniture, no spots: only on maps with desks, placed by the map's plan alone; no agent activity uses it. **There is no reception** | `pantry` | Sorted |
| Pantry sign | A hanging `COFFEE` sign on the top wall over the pantry counter | Furniture, bound to nothing: hung wherever the counter is (`OfficeShell.pantry_sign()`: centred over it, foot at `SIGN_FOOT` 32, on the cream face, no wider than the counter, so off every window, the door and every zone sign), and on no map without one. Part of the shell (Ground: no footprint, behind everyone). Wood, brass and cream; no state colour (`working`, `blocked`, `unread`, `task_light`) | `pantry_sign` | Ground |
| Partition | Low cream partitions round a zone: a U open at the top, a post at each top corner | Furniture: structure, never state. Down each side, along the bottom, at the zone's edges, with its carpet inside; the open top faces its aisle row | `partition_v`, `partition_post`, `partition_corner_bl / _br`, `partition_h` | Sorted |
| Zone sign | A small hanging sign at a zone's top-left post, over its aisle row, as wide as what it says (at most 160, never past the top-right post; a long label ends in an ellipsis) | Display of the workspace's number and label, an accent stripe its worktree group shares (`OfficeZoneSign.accent_of()`); hovering it names the repository and checkout (a read of the frame the office holds, never of herdr); structure, never state | `panel`; palette `sage` `sky` `terra` `teal` `lilac` | Sorted |
| Furniture | Plants, side tables | Standing on the floor, origin = foot point, in the y-sort. **A row of plants along the top wall's foot** on the wall's own 160-unit grid (from 72), each the plant of its step, clear of the door, windows, pictures and pantry; where no step clears them (the grid and the windows line up only at some widths), one plant in the first window gap that takes it, so every top wall stands at least one; **lane gaps** (3+ free cell rows inside a lane, outside every zone) stand a piece every two rows from the gap's second, in the lane's middle column, plants and side tables taking turns; a side table carries one desk piece (see "Desk decor"). Keyed by grid step, never placed by table, tab, zone or state, so their count does not follow tab count | `plant`, `plant_b`, `side_table` | Sorted |
| Wall picture | A framed landscape on the top wall | Furniture, on the wall's cream face (`FRAME_FOOT` 48). Centred in every second gap between two neighbouring windows, where it, grown by `FRAME_GAP` (8), touches no window, the door, the pantry or a wall-end cell; placed by the windows alone. Part of the shell (Ground: no footprint). Cream sky, sage hills, terra frame; no state colour (`working`, `blocked`, `unread`, `muted`, `task_light`) | `wall_frame` | Ground |
| Desk decor | Mugs, notebooks, clipped papers, plants, headphones, now and then a white cat: one piece on each **side table**, never on a pod's desks | A side table stands in a lane gap and carries one piece from the `desk` pool, or (28%) the `cat` pool, picked by weight from a stream seeded by its placement key alone (`OfficeDecorPlanner.side_table_item()`): never by tab, zone, state or time, so refreshes, growth and theme changes keep the choice. The cat's loaf, sleep and sit are static poses, not working / idle / done | `side_table`; `desk_mug / notebook / papers / plant / headphones`, `cat_loaf / sleep / sit` | Sorted |

Bold marks state signals. The Layer column follows [World model](WORLD_MODEL.md): flat on the floor or wall → `Ground`, standing on the floor → `Sorted`.

### Looks

Production uses **one generic look** for every agent, independent of provider and pane. Person, chair, desk and twin monitors are a single
authored image; no outfit, part, colour or provider logo is substituted. Both logical rows face front. Read the pane's name on the plate,
the provider in UI words and tooltips, and state in the workstation pose and badge.

The HUD uses the same family's still generic portrait (`WorkstationArt`), whole on the tall bar and agent card, cropped on the short bar.
It does not animate or resolve a per-pane look; its frame and badge say the state. `PixelPeople`, `PixelPortraits`, `TablePack` and
Avatar Studio remain **legacy authoring tools**, not production-office customization. Their look variation, saves and asset contracts are retained
in [the asset spec](ASSET_SPEC.md).

## Stationary observations and approved states

The complete workstation stays at its measured seat. Observed arrivals are placed there directly; a shell or vacant slot uses the empty
workstation image. Relocation moves the whole station, not a body catching up with its annotations. Closing a pane vacates it; closing its
last tab or workspace removes that pod or zone in place. There are no walkers, door routes, ghosts or provider-change departure animations.

Name, badge, chip, selection and focus update from the current observation. `WorkstationActor` plays only the approved whole-image clips
in `art/daylight/workstation/manifest.json`; it does not infer activities from terminal text. Working and idle loop; blocked has its
authored entry, looping wait and exit; done nods once. Starting and unknown are static aliases of frame 0, not an idle loop.

| State | Complete image | Annotations |
|---|---|---|
| working | Approved working loop | Name plate + working badge |
| idle | Approved idle/blink loop | Name plate + idle badge; no mug signal |
| blocked (including asked while starting) | Approved reclined wait with its authored question bubble; entry and exit clips | Name plate + blocked badge/chip; the real question is only in the hover tip and card |
| done (UNREAD) | Approved one-shot nod, ending on frame 0 | Name plate + unread badge; not task success, no paper-stack signal |
| starting | Frame 0 still | Name plate + hourglass; blocked wins over starting |
| unknown | Frame 0 still | Name plate + `?` badge |
| SHELL | Empty workstation | Pane's name, picking, selection and focus still available; no state badge |
| Vacant slot | Same empty workstation | No annotation, focus or enabled click target |

**Blocked wins over starting:** a pane that asks during launch counts in BLOCKED, NEXT and the edge arrows. The card still says it is
launching and offers answer keys under the existing write-boundary rules. Starting begins only when observed, not merely because a start
request was accepted. The approved bubble is a pose, never a claim about the question's words.

The chip's 30×18 click rectangle begins at the native 80×80 seat rectangle's bottom; the two never overlap and do not change with state.
A seat click only selects; a chip click selects and enters answer mode once the question shows (never sends; read-only only selects).
Camera reveal and HUD pointing use a different, stable **signal rectangle**: `OfficeStation.signal_rect()`, (−47, −70, 94, 124), including
the native image and reserved annotation rows through the lens plate's bottom at 54. Fitting only the image could leave a selected name
under the HUD at the minimum window. Revealing the full reserved signal keeps it visible without a pan on hover, state or lens changes.
Edge arrows still aim at the actual chip while it shows, otherwise the native canvas, not this larger reservation.

Repeated same-state observations, renames, selection and focus changes do not restart the actor, even after a done nod has finished.
Disconnected (invariant 4) dims and pauses the last picture, not an idle pose; chips show no wait/frame. Socket recovery alone does not thaw
it: the next current observation must pass the layout gate. Resuming an unchanged state continues its clock and never replays a finished nod.

## HUD panels

Everything below is HUD and never changes the world. The world draws only what their actions produce in the snapshot.

### Portrait bar

The top bar's middle is who needs you, as faces (`OfficeBar`, `PortraitBarModel`, `PortraitCard`, `PortraitFold`):
- **Order**: the blocked in `N`'s order (the leftmost is whom `N` picks), the done oldest first, then the working and the idle in place
  order (machines, zones, rooms, then the panes no zone seats). Every agent of an online machine, never a shell, never a launching agent
  that does not ask, never a dropped machine's (its agents are not activity; the status line says it is down).
- **Two forms, by the bar's band** (`OfficeBar.set_tall()`, `PortraitCard.set_tall()`; the same nodes): on a tall bar (a screen at
  least `staff_tall_from` high, the 70 band) **a tile** (50×66, B2's): a 42×42 face window (`%FaceBox`, the cream ground
  `PortraitWindow`) centred over the name row and the place row (12 each, the name centred), holding the generic
  portrait (`Sprite2D`, `OfficeDraw.seat_portrait()`: the 40×40 portrait whole in the window's 40×40 clip, its bottom
  centre on the clip's), and over the portrait, in this order, the state's frame (`%FaceFrame`, `PortraitFrame<State>`: 1 unit,
  2 under the pointer), the pointed ring, the selection's ring and, in the top-left corner, the state's small mark (`%Badge`: 8×8
  units, the pack's `badge_<badge>_small`: blocked's `!` and done's envelope cover the frame's corner, the working and idle dots
  sit inside it; shown, never pulsed: it is not in `StatusBadge.GROUP`). Nothing the HUD draws is under the portrait, so the
  frame, the selection and the pointing draw over the portrait; on the cream window the selection is `ink`
  (`PortraitSelectedTile`) and the pointed ring `slate` (`PortraitPointedTile`), where a card's `paper` would not read.
  The words stand on the bar's ground (`PortraitTile`). Face-only
  26×66: the window 24×42, the portrait cropped to its middle 22 columns (a crop, never a scale); folds 40×66 and tallies 24×66.
  On a short bar (the 32 band) the horizontal card below has no mark and crops the same generic portrait,
  its pivot at the face window's middle, 37 under its top. A card keeps both faces from its first pane on, shows the
  one its form wants and dresses only that one, so a flip of the band makes no node. The wordmark, the strip,
  `1 machine · 13 panes`, the chime switch and the two lines stand in the band's middle, as the short band holds them in its own.
- **A card** (86×28, the short bar's): the same still generic portrait, cropped (`OfficeDraw.seat_face()`);
  the display name over the space; the space after a flat 3×8 tag in its worktree group's carpet colour (`CarpetTag%d`, the index of
  `OfficeZoneSign.accent_of()`: a mezzanine wears its source's); a blocked card's wait at the end of that row, never cut. Frame: `ink` with a
  1-unit edge in the state's colour, 2 under the pointer; the selection a paper ring just inside that edge; a pane a hovered HUD line
  names on another machine (or a blocked agent of the zone an edge arrow names) a paper ring 2 units in, inside the selection's
  (`PortraitPointed`): nothing covers the state's edge. Written on its own change and never laying the strip out. **The place** (tag and space) is a flat button of its own (`%PlaceButton`): the
  zone's sign in its tooltip, a click pans there and selects nothing; an unseated pane's place is only words.
- **The ladder** when the strip is short (first rung that fits): 1 all cards; 2 working and idle fold; 3 the done faces; 4 the blocked
  faces too; 5 the done fold; 6 tallies for all but the blocked faces; 7 the first k blocked faces and a `+N` tally. The bottom is four
  tallies (102 units). A pane keeps its card node while it shows; one that folds returns it to a pool, hidden: the strip's card pool
  grows to the most cards ever shown at once, bounded by its width, and never frees one. A refresh that would show the same strip
  (rung, cards, their places, folds, selection, room) writes nothing; the waits tick into the `%Wait` labels alone.
- **Machine chips** (`MachineChip`, among several machines): after the wordmark, in the fleet's order, kept by machine key; they take
  their room from the strip, never below its last rung; written on their own change (see "Machines and zones").
- **Clicks**: a card's face or name only selects (a desk click's path); its place only pans; a chip shows its machine's map; a fold or a tally opens the OVERVIEW on its state, or toggles that chip while it is
  open, and reads pressed while that chip is on; `1 machine · 13 panes` (B2's words, `OfficeTotals.count_words()`: every machine of
  the fleet, the panes of the live ones; right of the strip, only where titles are allowed) toggles the OVERVIEW.
  Nothing on the bar reads or writes. Hovering a card points at its desk, as a NEWS entry does.
- **Waits** tick on attention's beat (`OfficeAttention.waits_of()`), the OVERVIEW's FOR in the same words; `?` for a pane the log has no track of.

### Bottom panel

The bottom panel (`OfficeBottomPanel`) runs across the bottom, 16 units in: **one frame**, the pack's wood with brass corners
(`ui.panel_wood`, a 6-unit nine-patch round the HUD's dark fill; furniture of the HUD, it binds no field), with a top row of page tabs, `AGENT | HISTORY |
EVENTS` (`PanelTabs`), the NEWS line to their right, and the page shown under them. Every run starts on AGENT; nothing is remembered.

- **Docked, on a screen at least 400 units tall** (`staff_tall_from`): always open, 120 units high whatever its page (a body of 82: the
  card is laid across, the START AGENT / NEW PANE block's rows each one line and its manage buttons on one, measured against every state
  so no write control is cut), so switching tabs never moves the world. There is nothing to fold: no `Open ⏎`,
  no `▾ Esc`, and Escape goes on to the OVERVIEW and the strategic view.
- **Two rows on a shorter screen** (the 480×320 minimum and its 4x): the top row over the card's one line (name · state · place, wait,
  `Monitor ⤢`, `Open ⏎`, `×`, NEXT and `‹ ›`); `⏎` and `⤢` stand for the pack's key-hint icons `ui.key_enter` / `ui.expand` after the
  word, never a platform glyph. `Enter` or `Open ⏎` opens it to its full height (153 units) with the whole preview; so do the HISTORY and
  EVENTS tabs; `Esc` outside answer mode, `▾ Esc`, the AGENT tab (unless the card was opened) or selecting another pane folds it. A new
  terminal, agent, session or connection on the same pane does not fold it.
- **The AGENT page** is the agent card (scene name `inspector`): the portrait in a 48×48 slot (the shared generic head-and-shoulders
  portrait, a `Sprite2D` from `OfficeDraw.seat_portrait()`, still: a 42×42 window at (3, 3) on the warm `cream` ground
  (`PortraitWindow`), the 40×40 portrait whole in a clip 1 unit in, its bottom on the window's, and over its edge a 1-unit frame in the
  state's colour, the top bar's: blocked, unread (done), working, `muted` for idle and for a start that does not ask (`PortraitFrame<State>`,
  `CardPicture.Header.frame`); on a dropped machine's card an `ink` frame (`PortraitFrameStale`) and the whole window greyed by the pack's
  stale tint (invariant 4); the state's badge stays beside the name), the name, the state in a pill of its colour and its wait, the seat line; the terminal preview; START AGENT or NEW PANE
  and the manage rows; the PANE details (pane id, label, directory, session, terminal title) where the card has room for them beside START
  AGENT (`details_beside_launch_from`, 1000 units of card); at the right end one column (`%Side`, B2's): NEXT, and under it the verbs
  (Monitor, Answer, Switch herdr here, its note and the outcome, one line of it docked). Docked from 960 units wide, NEXT's pill takes
  `next_docked_wide_width` (308) so `NEXT:`, whom and an hour-long wait stay whole beside `‹ ›`; narrower, `next_wide_width` (244) and the
  tooltip says the rest. **Every pick shows it** (a desk, a portrait card, a NEWS entry, an OVERVIEW row, a square, `N`, a chip, Enter),
  except a click on a HISTORY or EVENTS line, which keeps its page (browsing the log).
- **Nothing to show**: the panel keeps its height and the AGENT page says so (`This session has no panes.`, `Waiting for herdr.`); a card the
  viewer closed (`×`) says `This card is closed: pick a desk or a card, or press N.` until their own pick opens one. NEXT stays.
- **The HISTORY page** (`A` shows it, `A` again the AGENT page) comes from the state log through `AgentHistory`: one line per pane that was blocked or done this session and is not
  now, newest first, at most 200: the badge of what it was (blocked, or done's), the name, the space, and `OFFLINE` or `GONE` at the tail
  (none for ENDED); it covers only the pane's current run. A line whose pane is still the terminal the log saw picks it on a click (checked
  again by the office); the rest are greyed, and their tooltip says why (`Not here any more: the pane closed.`). History and EVENTS read one
  log: per pane and by time.
- **The EVENTS page**: the state log's events, one line each (see the mapping table).
- **Answer mode** floats the whole panel to the middle of the screen as a modal over a dim, its top row hidden; its slot along the bottom
  stays where it was, so leaving answer mode moves nothing. Every line fits the smallest 480×320-unit screen; a sentence that does not fit
  goes whole into the tooltip.
- **Reads**: the card reads its pane only while its page shows and the panel is open (docked, or opened on a short screen), not minimized,
  with the machine online and the snapshot current; the folded line and the HISTORY / EVENTS pages read nothing.

- **State words**: done adds `UNREAD = not yet seen / Not task success.`; disconnected adds `Connection lost. / Not an idle signal.`.
  The note stands under the header, docked or opened.
  **A shell's card** has no portrait, badge or timer: `SHELL`, `no agent` (the idle herdr reports for a shell is the terminal's). There is no terminal
  icon before SHELL: the pack's terminal image `ui.working` is WORKING's badge and would read as a state.
- **Preview**: blocked reads herdr's full `detection` (up to 200 rows), other states the end of `recent_unwrapped` (12 rows); it shows the
  last 6 rows docked (`CardPicture.DOCKED_ROWS`) and the last 12 opened on a short screen and in answer mode, monospace, long lines clipped.
  The header says how many rows show, how long ago, and whether rows were cut or clipped (`6 of 31 rows · 3s ago`, `recent · 3s ago`); when
  it cannot read it says why (`No preview: offline`) and never shows blank space as terminal content.
- **Switch herdr here** (with several machines **Switch herdr on <machine>**) is open only for a station the user clicked, while it is still the
  clicked terminal: when following herdr's focus it reads `Following herdr's focus`; on a new terminal `New terminal: pick again`. The note
  `Clears tab's UNREAD` warns that every pane's UNREAD of that tab clears. Result line: `herdr switched here` / `Not sent: <reason>` /
  `Unknown result: look first`.
- **Answer mode** (**Answer ⏎**, or `Enter`) replaces details and the switch button with the keys `1`–`9`, `y`, `n`, `⏎`, **Send Esc**, a reply
  field and **Send line**, and the line `Checks the screen first; it can still change`. The result line: `Sent` (herdr took the input) /
  `herdr refused (code)` / `Not sent: …` / `Unknown result: look first`. What is offered depends only on herdr's state (blocked gets keys, idle / done
  get a line, a shell nothing), never on terminal text. Rules: [the write boundary](WRITE_BOUNDARY.md) §2.
- **Start agent and New pane** (the `%Launch` block, only on the docked or opened panel, outside answer mode). For a shell, **START AGENT**: one button per kind
  seen in this machine's snapshot, note `Types the kind + Enter in this terminal`; when the last line does not look like a prompt the first click
  shows `Start anyway? Types "claude" + Enter after:` and that line in a dark terminal strip, and a second click on the same kind sends. For an agent,
  **NEW PANE BESIDE <PROVIDER>** with `New pane →` / `New pane ↓` (the pane's shape picks the direction) and `Splits a new pane next to <pane>`. Results
  go in the card footer (`Starting claude-2 · 4s`, `claude-2 started`). Rules: [the write boundary](WRITE_BOUNDARY.md) §4.
- **Close, New space, Worktree** (two lines below, for any selected pane): `Close` and `New space`; a branch field and `Worktree`, with the note
  `New worktree: branch <b> from this space` or `Branch: <why not>`. The branch field lets PageUp / PageDown through to the zone
  step and lets go on a press anywhere outside its row (the field and Worktree). The first `Close` click only states the scope (`Closes CODEX's pane w2:p3.`, plus
  ` and its tab …`, ` and space …` or ` and mezzanine 3A "docs". The checkout stays on disk.` for a last pane; `Kills CLAUDE, still working.` when the
  agent is not idle) and relabels the button `Close · kills` or `Close · click again`; a second click within 10 s sends. The button is off for the last
  pane of the repo's own space while a mezzanine is open. Footer: `Closed w2:p3` / `New space w14` / `New worktree v1-a → w15`; a lost reply says the next
  snapshot decides. Rules: [the write boundary](WRITE_BOUNDARY.md) §5.
- In the world, a split pane first appears as an empty workstation bound to a shell; it shows the person only when a launch or agent is
  observed. A closed pane vacates its slot or removes its pod/zone when it was the last (NEWS `pane closed`), without walking. A new space or worktree is a new zone of the same map
  in the snapshot, and the office's pick of its shell pans to its pod. Selecting the new pane, even across maps, is only a selection.
  `--read-only` and the showroom have no launch block.
- **A new pane is picked only if the viewer has not navigated since** (`OfficeNavigator.nav_revision`): a zone picked (a card's place), a machine picked (its chip), an edge arrow,
  PageUp / PageDown, `N`, `‹ ›`, a portrait card, NEWS, EVENTS or HISTORY before the snapshot shows it cancels the pick and the footer says
  `…: not picked`; panning (a drag, the wheel, the arrows) and herdr's focus moving do not. **Changed with one map per machine**: PageDown then
  PageUp before the snapshot now leaves the new pane unpicked, where coming back to the same floor used to pick it.

### Terminal monitor

The terminal monitor draws herdr's own screen (`pane.read visible ansi`, in the pane's real rows and columns); it is not pixel art, so like HUD text
it uses vector glyphs. It covers the whole office, which keeps refreshing underneath, and changes nothing in the world. It is a window, neither signal
nor furniture. The title shows the pane's display name, its place (`space / tab`, no tab for a lone default one), state and wait; the status line shows `● LIVE INPUT` (raw mode), the last input's round trip,
and reasons (result unknown, refused, `no cursor from herdr`, keys herdr cannot name). A disconnected machine freezes and dims it with `○ OFFLINE`;
a new terminal shows `■ INPUT STOPPED` until **Follow new terminal**; `--read-only` shows `VIEW ONLY` and does not read. Input rules:
[the write boundary](WRITE_BOUNDARY.md) §3.

### Machines and zones

There is no left column: the world starts 16 units in, as the bottom panel does, and the SPACES rail's navigation is in the top bar.
Among several machines a **chip per machine** stands after the wordmark, in the fleet's order: the machine's label (cut to 40 units, 20 on a
bar without titles, whole in its tooltip with how it answers and when it was last heard from). **A chip click shows that machine's map**
(instant, cold: a new world, nobody walking; a machine that never connected opens as an empty map whose plate says why), and the chip of the
machine shown is the current one (`slate`). A machine that is not answering has its chip in `muted` (connecting) or the blocked colour
(offline), and none of its agents has a card. The chips take their room from the portrait strip, never so much that the strip is left less
than its last rung (four tallies): past that the row of chips is cut, and the machines beyond it are reached by their cards and the page keys.
The longest-waiting blocked agent staying in sight wins over showing every chip.

**A card's place** (its zone tag and space, the lower half of its words) is a button of its own: its tooltip is the zone's sign words over
what the sign's own tooltip says (repository, checkout, whose worktree), and a click **pans** to its zone (its aisle row at the top of the
world, as little sideways as brings its width in), switching maps only for a zone on another machine, and selects nothing. A face-only card
has no place: its click selects, which reveals the desk anyway. Zones nobody waits in are reached by **PageUp / PageDown**, a drag and `S`.
PageUp / PageDown pan zone to zone in the order `OfficeFrame.zone_order` keeps (each machine's zones ascending, each mezzanine right after
its source), so **PageUp goes to the lower-numbered zone and PageDown to the higher**, and cross machines at either end (from a machine's
last zone down into the next machine's first), stopping at the ends. A text field that holds the keyboard (the card's branch box) keeps
the page keys while it does. An edge arrow pans to its desk and selects nothing; `N`, NEXT, a
portrait card, NEWS, EVENTS and HISTORY pan to the desk, switching machine if needed; herdr's focus moving, while nothing is picked or the picked
pane is gone, pans to it as far as it takes (a chip or an edge arrow clicked before that move is drawn wins over it, and the move is not
replayed; the next one is followed). A machine's map seen for the first time opens on the selection's pod, else on its first zone
(the lowest number). Every change is instant: no transition, no lift car, no input lock. A zone that disappears is forgotten at once; a
machine that disappears takes its map with it. The `door` on the outer wall is furniture.

## Why these channels

### Why focus has a thin underline

- Herdr focus and local selection are different fields. The whole-workstation selection outline carries `picked_key`; the thin underline
  carries herdr's focused pane and active tab. It does not recolour or dim the complete image.
- One `Polygon2D` per station, x [−28, 34), y [4, 5) relative to its foot, uses `task_light` with `OfficeStation.LIGHT_ALPHA`
  0 / .15 / .35 / 1 (OFF / DIM / ON / FOCUS). `OfficeFloorView.lamp_of()` retains its old name but chooses an underline, not a desk lamp.
  No `task_lights` pack multiplier or night lamp boost changes these steps.
- **DIM is not disconnected**: only the underline weakens for an inactive tab; a lost connection dims the whole map and freezes animation.
- **Night is lighting, not a signal.** The time of day (`DayLight`, the local clock, `T` to turn it over) binds no herdr field, so rule 1
  does not apply to it and nothing reads it as a state. It darkens and cools the whole world alike (`DayLight.NIGHT_TINT`, a
  `CanvasModulate`; the HUD is its own layer); a lost connection is still its own grey `stale_tint` on top, with everyone frozen (invariant 4).
- When `active_tab_id` is missing, every tab of that workspace is unknown (`RoomModel.Active.UNKNOWN`) and drawn ON, not DIM: not said is not no.
- Zone-level focus is not drawn: the focused pane's underline says where herdr's focus is; the current machine chip and the view itself say what Herdstead is showing.

### Why one complete workstation

Person, chair, desk and twin monitors keep the approved composition and internal occlusion as one image. Every station uses the same front
view, including the logical near row. The office neither reconstructs furniture from components nor customizes the person's look.

Seats still have three bindings: **vacant** (empty image, no annotations or picking), **SHELL** (the same image, bound to a pane) and
**agent / starting** (person present). Launch pending is never drawn as a shell, even before a provider is known. The shell card says
SHELL; no `$_`, fake terminal output or additional world mark is introduced to distinguish it from a vacant slot.

### Why one open-plan map with half-walled zones, not one room per tab

A tab is a table (a pod of desks), a workspace is a zone on an open-plan map, and worktree information goes on the zone's sign and
its tooltip. Full walls around each workspace would cut the office into rooms and hide who sits where; row walls across the map spent a band of every
row on wall. So a zone is bounded by **low partitions**, a U open at the top: they say whose
workspace a desk belongs to without hiding the workstation images.

- Under the top outer wall is a 32-unit entry band (one cell, with the pantry counter against the
  wall in its left corner; it is also the first zones' aisle row, their signs hanging over it). The main aisle on the right is
  64 wide; each side wall is one 32-unit cell; the front wall is not drawn.
- Below the entry band the map is **lanes** of 4 cells with a one-cell aisle between two; the narrowest pod needs two lanes, including
  its zone's pad. A zone stands in whole lanes under an aisle row of its own, first as many as its pods need to stand in one row, its pods
  in rows as deep as a pod's reservation (320 units, ten cells). Zones are placed as a masonry that only grows, down or right: retained zones hold their
  place, a growing zone grows in place while it can and otherwise moves alone, new zones take the top-most, left-most gap.
- Only the top outer wall has windows, pictures and the lift door. There are no inner walls.
- Walls assemble on one `TileMapLayer` grid: the top wall's two courses and the side walls. The row walls' joints are no longer laid.
- The base floor covers every cell of `floor_cells`; walkways lie over the entry band and the main aisle. Each zone has **one carpet** inside its
  partitions (from its top to its bottom partition), in its worktree group's family; none under an aisle row, an aisle column or a corridor.
- A map's first plan fixes its lanes. Window size, zoom, renames, state and focus never move pods; structural changes start from the old plan,
  prefer growing in place or into gaps, and an over-wide pod gets its own row (its zone taking more lanes, the map widening if it must). A
  removed pod or zone leaves a gap; nothing re-queues, and the map never shrinks.
- Panes that stay in the same tab keep their whole station and animation clock through growth, moves and row changes; moves between tabs
  on the same map transfer the station. Machine and theme switches rebuild the current world: the cache holds plans and views, not resident actors per map.
- Plants and side tables are `StaticBody2D`s with foot points and footprints; they never take pods, zones, the entrance or aisles, and
  they are not a reading of how many tabs or agents there are. Nothing stands by the door or on the pantry counter.

A pod's width, seat feet and physical/render/reserved envelopes come from `OfficeTable.measure()` ([World model](WORLD_MODEL.md)); the
annotation rows (badge, chip, lens line, name plate) come from `OfficeStation`, with Labels sized after their face is applied.
Layout validation checks bounds, reservations, canonical measures, unique bindings and furniture clearances. Walking graphs, actor clearance,
approach points and door reachability are retired; corridors remain reserved spatial structure.

## Not drawn, and why

| Idea | Why not |
|---|---|
| Separately coloured monitors or state desk props | Production uses approved complete-image frames; no component substitutions or new state behaviour in this phase. |
| Walking or idle wandering | Production workstations are stationary. There is no walking presentation, including observed arrivals and departures. |
| `layout.zoomed`, pane `scroll` | No drawing without new art that would not clash with existing channels. `HerdrSnapshot.from_wire()` drops them (invariant 2: no field nobody draws). |
| Dusk as a runtime palette-swap shader | Dusk was derived at build time and then retired (2026-09-29). Night is light over the world, a modulate, not a palette swap. The workstation is its own shared family and keeps its authored palette. |
| A minimap scaled from plan coordinates | A map is far larger than the world area (≈ 820 × 308 at 2×): scaled down to fit, a desk would be a few units, and aisles, pantry and furniture would read as signals. The strategic view keeps only order, columns and side. |
| Zoom below 2 to see a whole map | Zoom is the window's content scale (`OfficeScene.fit_window()`, `ZOOM_MIN := 2`); at 1× density-2 nearest families lose half their outlines, and a large map still does not fit. |
| A strip of windows per zone in the HUD (the SPACES rail's) | Retired with the rail (S3 BAR-b, 2026-10-27): the carpets and seats show each zone's panes, the portrait bar says who needs you, and `S` draws every zone's seats in the same state scale (`StrategicModel.window_look()`). A second per-zone strip would say the same states again in a third place. Nor are the rail's in-view marks drawn any more: the view is what is in view. |
| The agent list (a drawer on the right, `A`) and its local attention records (snooze, hide, restore) | Retired (S3 PANEL-a2, 2026-10-28). Every job it had is done elsewhere: every pane, shells included, is a row of the OVERVIEW; who needs you, by urgency, is the portrait bar; the tree is the strategic view's sections; History is the bottom panel's HISTORY page (`A` shows it); the monitor opens from the card (`M`). The filter box has no successor (the OVERVIEW sorts by name and filters by state). Snooze and hide changed nothing herdr or the world showed, and nothing read them once the list was gone. |
| Provider initials in strategic cells | Of 23 providers five start with C and three with K; initials are ambiguous and break "one concept, one channel". Provider stays in the hover tip. |

## Asset pipeline

- `make art` rebuilds every pack: it rebuilds `assets/`, and `tools/check_build_clean.py` proves the result matches the commit (CI does
  the same). The workstation source is under `art/daylight/workstation/`; its builder validates and byte-copies, never redraws it.
- Theme semantic IDs and sizes have one source, `art/daylight/pack.json`. The complete workstation's own geometry, palette and clips are
  in its separate `manifest.json`; `PROVENANCE.md` records the approved references and the offline-derived empty image's review caveat.
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
4. Placement: flat on floor or wall (a zone's carpet, a pod's wash) → `Ground`; standing → `Sorted`, origin = foot point; side-table decor → a child of that table; floating over the
   world → `Overlay` (`OVERLAY_Z`).
5. State changes only change properties of existing nodes (`visible`, `color`, `text`); never destroy and rebuild.

## Current scope limits

All agents share one look and portrait; a vacant slot and a shell share one empty image. Names, badges, UI provider words and enabled
picking carry their distinctions. Legacy rigs, component furniture and authoring customization are not an implicit promise to restore them
to the production office.
