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
     and things drawn only for a state (done's paper stack, idle's mug, blocked's chip). Every state sits at the seat; nobody leaves it
     for a state. Nothing else in the world shows agent state. Walking is a transition, not a channel.
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
| Who needs you: the portrait bar | Cards in the top bar, left to right: the blocked, the done, the working, the idle | One per agent of an online machine (invariant 4: a dropped machine's agents have none, the status line says `1 OFFLINE / …` in the blocked colour). A shell has none, nor has an agent herdr is still launching that does not ask; blocked while starting is blocked (`PaneModel.asks()`); a state the pack does not draw is idle. The blocked stand in the order `N` walks them (`OfficeNavigator.waiting()`), the done oldest first, the working and the idle in place order (`PortraitBarModel.of()`). A card: the seat's person, still (on a tall bar's tile as a portrait, on a short bar's card standing); the pane's display name; its space after a tag in its worktree group's carpet family (the sign's and the carpet's, never state); a frame in its state's colour (blocked, unread, working, muted), over the portrait's edge on a tall bar's tile (B2) and round the whole card on a short bar's; on a tile, the state's small mark in the window's corner (`!`, envelope, a working dot, an idle white dot: the pack's `badge_<badge>_small`, never pulsed); a ring on the selection (paper on a card, ink on a tile's cream window); a blocked card's wait (`StateLog.wait_of()` in `wait_text()`, `+` when the start was not observed; the leftmost's is the longest). When they do not fit, a fixed ladder (`PortraitBarModel.fit()`, from the widths the scene measures): the working and the idle fold (`+12` over `working`), the done and then the blocked go face-only, the done fold, everything but the blocked faces becomes a tally (`+12`), and last the blocked keep as many faces as fit before a `+N`: the longest-waiting blocked are the last to fold. Hover: a card's whole name, provider, state and wait, space / tab, and its machine among several; its place, the zone's sign words and the sign's tooltip; a fold's names. Clicks: a card's face or name selects (a desk click's path, no answer mode); its place (the tag and the space, the lower half of its words) pans to its zone and selects nothing (an unseated pane's place is only words); a machine chip shows its machine's map; a fold or a tally opens the OVERVIEW on its state, or toggles that chip while it is open; `1 machine · 13 panes` toggles the OVERVIEW. No number key reaches a card. The window title's `(N)` is the blocked count | The seat's portrait (`PixelPortrait`, tiles) or pixel person (cards); the pack's `badge_<badge>_small` (tiles only); HudTheme `PortraitCard*`, `PortraitTile`, `PortraitWindow`, `PortraitFrame*`, `PortraitFaceBare`, `PortraitFold*`, `PortraitSelected[Tile]`, `PortraitPointed[Tile]`, `PortraitPlaceButton`, `CarpetTag*` | HUD |
| Blocked out of sight | An arrow on the edge of the world toward it: `↓ 3 ! 2` (way, the zone's number as its sign writes it, blocked badge, count) | **Only the shown, online machine's map**: each zone with a blocked desk whose chip (or seat, while it draws none) is outside the world on screen gets one arrow, counting those desks, on the edge crossed by the line from the view's middle to its longest-waiting one (`EdgeArrowModel.of()`, pure); longest wait first; at most 8 (the 8th reads `+N` and its tooltip lists the rest). **Arrows never overlap and never leave the world**: an edge shows as many as it has room for between its ends (the side edges leave the top and bottom rows to the arrows there), by the arrows' own sizes, and its last place goes to a `+N` note for the zones that waited least, their lines in its tooltip (`EdgeArrowModel.fit()`, pure, per edge; `OfficeEdgeArrows` measures and folds again whenever its room or the compact form changes, with no refresh). Tooltip: `3 INFRA · 2 blocked · longest 12m` (`OfficeAttention.wait_text()`). Worked out on every refresh and whenever the camera or the world's room moves (`OfficeViewMarks.follow()`, no refresh), and once a second while any shows (the wait in the tooltip). A click **only pans** to that desk, as far as it takes (`OfficeNavigator.pan_to_desk()`): it selects nothing. Hovering one outlines its zone's blocked cards in the top bar (worked out from where the pointer is and where the arrows stand now, so it survives a refresh that hands the arrows other zones; an arrow that something else covers there, the bottom panel in answer mode, is not pointed at; a blocked agent folded into a tally has no card to outline). Below 460 units of world (`edge_arrows_compact_from`: the 480×320 minimum's 456) an arrow is compact: way, badge and count, the zone in the tooltip. None under the OVERVIEW, the strategic view or the monitor, and none for a machine that is not answering. **Another machine's blocked panes show only as cards in the top bar** (and in NEXT and the OVERVIEW). Arrows cover the world where they stand: what is under one cannot be clicked or hovered | Text + blocked badge; HudTheme `EdgeArrow`, `EdgeArrows` (`inset`, `gap`) | HUD |
| Next thing | NEXT at the right end of the bottom panel's AGENT page, with `‹ ›` beside it and the card's verbs under them | Says what a press does and to whom, by the pane's display name (`NEXT:` / `Answer needs approval`, `Read` for done; ` @ bee` with several machines; the space only in the tooltip). Same as `N`, same order: while anyone is blocked only blocked panes cycle, otherwise done; longest wait first. It selects, switches **map** only when the pane is on another machine, pans to the desk and does the verb: blocked expands the panel and enters answer mode once the question shows (`N` then a digit answers; Enter never sends); done only expands. When the office cannot write (`--read-only`, the showroom) it shows herdr's state word instead of a verb and only selects. Nothing to do: `All clear`, greyed, on the pill's own opaque `deep` fill with a `slate` edge. Docked it says `NEXT:`, whom and the wait in a row; opened on a short screen it reads down; the folded line of a narrow screen writes only the name. `‹ ›` step through the same queue, select only | Text | HUD |
| State changes observed this session | The NEWS line in the bottom panel's top row, and the panel's EVENTS page | One event ring in the state log: a state change, a pane appearing / disappearing / changing terminal, a machine going online / offline. Only herdr's words. A pane's subject is **its display name at the event** (`StateLog.Event.name`, cut to 24 grapheme clusters with `…`; the entry's tooltip says it whole) and its space. The duration is always **the segment that ended**, before the arrow: `11:40 refactor the fleet · api working 38m → done`, `idle 3s+ → blocked`; when the ended segment was not a watched state, only the new state. Also `working · new pane`, `pane closed`, `idle · new terminal`, `bee offline`; identity changes are `new terminal` / `new agent` / `new session`. Launches: `starting` on an existing shell, `new pane · starting` for a new pane (`main · api starting`). A name changing alone (a new task summary) is kept by the log (its `version` moves) but is no event. No path ever shows. NEWS: newest on the left, at most 8 fixed buttons, a new one fades in once (not a ticker), a click selects the pane (disabled with `Pane gone` when it is gone). EVENTS: newest on top, at most 200 rows, one line each (time, badge, who, what); the selected pane highlights its newest row; a row's click picks its pane and keeps the page | The pack's state badges, `ui.connected` / `ui.offline`; HudTheme `NewsBar` / `NewsItem` / `PanelTabs` | HUD |
| Something happened while away | The window title's `(N) `, a Dock bounce, an optional chime | Title: N = the blocked agents (the portrait bar's), left out when nobody is blocked or all machines are disconnected; done stays the trailing `· n UNREAD`; `--no-title-count` drops it. Alerts fire only for new STATE / APPEARED / REPLACED events that turn a pane blocked (or done) and still count by the portrait bar's rules; the first snapshot, reconnects, machine changes and launches are baseline. Nothing alerts while the window has focus, and nothing is replayed later. Dock: blocked only, on by default (`--no-bounce`), at most once per stretch in the background, only after 3 s still blocked, never for herdr's focused pane. Chime: off by default; the `CHIME OFF` / `CHIME ON` switch right of the strip (remembered in `user://herdstead.cfg` as `[alerts] chime`) or `--chime`; blocked two rising tones, done one softer tone; at most one per refresh, once per pane per 10 s. Sound is only redundancy | None (tones generated in code) | OS |
| Each pane's segments since opening | The OVERVIEW table (`1 machine · 13 panes`, a fold, or `O`) | One row per pane: AGENT (badge + the pane's display name, `StateLog.Track.name`; hourglass and `STARTING` while launching, except blocked while starting; the AGENT sort orders by that name, ties by pane key), SPACE / TAB (no tab for a workspace's lone default one), STATE, FOR (this segment), BLOCKED (total this session), TIMES (how many times blocked), TIMELINE (a state colour band; **hatching = not observed**: before the pane appeared, while disconnected, and the fold of the oldest segments past 256). The band's left edge is when the log first saw the pane; a pane present at opening starts in its state, not hatching. Axis: left-edge wall-clock time, 5 / 10 / 15 / 30 / 60-minute ticks, `now`; redrawn once a second while open. Disconnected rows dim, STATE `offline`, FOR `-`, shown only under ALL. A row click selects the pane. It covers the world without re-planning; chip reads stop. Shells have rows too: a zone of shells only is reached from here (a row click picks the shell, shows its zone and pans to its desk). | HudTheme `Timeline` (hatching `slate` on `deep`, axis `muted`) and `Overview*` | HUD |
| Start not observed | A `+` after a duration (`3m+`) | **`+` = at least this long**: the state began before the office started watching (the first snapshot of a connection). Whatever says it names the pane by its display name (the log's `name`), never by the provider word alone. NEWS, EVENTS, OVERVIEW, the portrait cards' waits and tooltips, the lens and the strategic view all read `StateLog.wait_of()`, so one blocked pane shows one number everywhere. The world writes it in the compact form (`compact_duration()`: `12m`, `3h+`; the lens line), the HUD in `wait_text()` (`1h 05m+`): the same wait, two spellings, one source. The card and the chip write no number for such a state | Text | HUD / Overlay |
| Map shell | Top outer wall + entry band + side walls; main aisle down the right; **no row walls** | Furniture. The top wall carries the lift door, windows (with a pantry, centred between the pantry and the door's clearance) and pictures; lanes of zones below the entry band (a lane holds the narrowest pod; a zone takes as many as its pods need), with aisle columns between lanes and an aisle row above each zone, plain floor. The lift door, above the main aisle's left lane, is where people enter and leave; it never opens and shows no state; it moves right when the map widens | `wall.cap_* / face_* / side_*`, `window`, `door`, `wall_frame` | Ground |
| tab | A pod of single desks: two facing rows of 32-unit desks across a low screen | label → **small text right under the pod** (the display face at 8 in `paper`, on its zone's carpet, no wider than the pod, cut with a forced ellipsis), **except the lone tab of a workspace herdr still calls by its number** (`label == str(number)` or the tab id: `DisplayName.tab_shown()`, `RoomModel.label_shown`), which says nothing there, nor in any place a pane is said to be (`PaneModel.place()`: `api`, not `api / 1`); **`workspace.active_tab_id` → the open pod: its lamps are lit** | Table family `desk_*`, `screen_*`, `apron_*`; `task_light` | Ground / desk |
| pane | A terminal at a seat | **Only a pane brings a laptop and a lamp**; the laptop shares the seat's axis, one 32-unit desk per column. A seat without a pane has only a chair. Tab layout → columns and far / near side; when missing, a pane keeps its seat, then free seats fill by stable pane key. The layout rect's `width` / `height` (terminal cells, 1–4096, else 0×0) sizes the terminal monitor's grid; the floor plan never reads it | Table family `monitor`, `task_light` | Desk |
| pane without agent | SHELL: an empty chair + a laptop with `$_` | Provider empty and not launch pending; static `$_` on the near screen and far lid; no blinking, no badge | Table family `monitor` views `shell_front / shell_rear` | Desk / Sorted |
| **herdr focus** | **That seat's lamp is brightest** | `focused_pane_id` → strong; other pane seats at the same pod → normal; pods that are not the active tab → weak. **Switch herdr here** (`pane.focus`) on the card switches herdr's **shared** view (every attached terminal follows; on a remote machine, that machine's session) **and turns every `done` of that tab into `idle`**. The lamp draws only the focus herdr reports back | `task_light` (off + three alpha steps, `OfficeTable` constants) | Desk |
| **Herdstead selection** | Four corner marks on the seat + a frame around the pod, 2 units outside its drawing (clear of the end desks' paper and mugs and the near chips); the seat's name plate shows | `picked_key`; with nothing picked it falls back to herdr's focus. | `ui.selection_seat` | Overlay |
| **Strategic view (`S`)** | A schematic of the shown machine's map over the world area, titled with the machine (`@ name` among several, and its state when not answering) (`OfficeStrategic`): **a section per zone**, in the page keys' order (`OfficeNavigator.section()`), captioned with the words on the zone's sign (`3 INFRA`); the top bar and the bottom panel stay usable | Sections flow down newspaper columns as tall as the room: one that fits a column is kept whole (in the next column when what is left of this one cannot hold it), one taller than the room splits at a pod-row boundary and repeats its caption as `3 INFRA …` (`StrategicLayout`). A caption is plain `paper` text in the sign's face (the display face at 8, in a 9-unit band, with a `slate` rule on to its column's edge), **never the zone's accent**: accents are structure in the world, and the view stays schematic; hovering a caption says what the sign's tooltip says; captions are not clickable. **A caption never changes the cell**: the cell and the columns are the desks' alone, a caption wider than its column's pods widens the column only into width the desks leave over (the first columns first), and one that still does not fit is cut with an ellipsis, its whole words leading its tooltip. Under a caption, the zone's pods in plan order (pod rows top to bottom, `origin.x` left to right), each a frame with its tab label, a far row and a near row of cells by `SeatPlacement.column`. One cell per seated pane (the largest of 32 / 24 / 16 / 12 / 8 units that fits), coloured by `StrategicModel.window_look()` (the one state scale, once the SPACES rail's windows: working / blocked / done their colours, blocked while starting blocked, idle and starting `cream`, unknown `muted`, a shell or a machine not answering `slate`); empty seats are not drawn. A blocked cell on an online machine writes its wait (`OfficeAttention.wait_text()`) when the cell is at least `wait_from` (24), else only in the hover tip (the pane's name, then `CLAUDE · NEEDS INPUT · 12m+`, then where). Provider is only in the tip (no initials, see below). Selection = four `blocked` corners, pointing = `OfficePointer`'s dashes, herdr's focus not drawn. Not a map: no plan coordinates, so nothing about aisles, pantry or furniture. Disconnected: tinted by `stale_tint`, all dark, no waits. Empty map: `No desks on this machine`. A cell click closes it, selects the pane and pans to it. A card's place (or PageUp / PageDown) while it is open scrolls it to that zone's section; a place or a chip of another machine draws it again for that machine. While open: no lens, edge arrows or question reads; `M` and `O` open over it | No new art: a `_draw()` Control, theme type `Strategic` on the pack's `panel` | HUD |
| **Herdstead pointing (hover)** | A static dashed frame 2 units outside the station's click area, `ink` / `paper` (`OfficePointer`, `OVERLAY_Z`), for a pane anywhere on the shown map; for a pane on another machine, a 1-unit `paper` ring 2 units inside its portrait card (`PortraitPointed`; inside the selection's ring, which is 1 unit in, so the state's edge, the selection and the pointing nest and all show), and for a zone, the same ring on each of its blocked cards; a pane folded into a fold or a tally has no card to ring | Hovering a NEWS entry, an EVENTS row, a HISTORY line, a portrait card (→ that pane) or an edge arrow (→ its zone). **It only points**: no selection, no map switch, no pan, no read, no write | No new art | Overlay / HUD |
| **Lens (hold `L`)** | Each agent station gets a "how long in this state" line in its own row, ink on a paper tag (not dimmed); every seat's name plate shows; chips are not drawn; each pod's floor gets a wash of its most urgent state; furniture dims | The line is OVERVIEW's FOR in the in-world compact form (`OfficeAttention.compact_duration()`: `12m`, `3h`, `4d`, `+` when unobserved, starting included; 30 wide at most 18 of text); none for shells, `?` without a track, nothing on a disconnected machine. Wash: blocked → `blocked`, done → `unread`, working → `working`, idle or starting → `cream`, unknown → `muted`, shells only → `slate`, disconnected all `slate`, at `LENS_WASH_ALPHA`. Furniture (floor, aisles, walls, door, windows, pictures, plants, side tables and what they carry, the pantry and its sign, partitions, zone signs) is multiplied by `LENS_DIM`; signals stay bright. The selected pod's `blocked`-coloured frame darkens by `OfficeTable.LENS_FRAME` so it shows on a blocked wash. Off while the monitor or OVERVIEW is open or a text field has the keyboard. | No new art: Label, ColorRect | Overlay / Ground |
| agent | The person seated there (pixel people) | **the pane's display name in `ink` on a paper tag as wide as the name (at most 30, or 62 when the next seat on its side of the pod is vacant: it takes that seat's slot, its start still over its own worker; a name plate), shown at all times on a map with few occupied seats (at most `FloorLayoutPolicy.FEW_SEATS`, 16, agents and shells; S3 SEATTAGS), otherwise only while the seat is hovered or selected, or `L` is held**, 10 units tall, in its own row next to the badge, 2 clear of the pod's tab label and frame (under `L`, where the lens line goes, it moves one row out). Never a state signal: ink on paper in every state (the display face at 8, as written, not upper-cased; a longer name is cut with a forced ellipsis, and **hovering the seat shows the whole name** with who and in what state and where in the world tooltip `%WorldTip`; the card and the OVERVIEW say it whole too). The display name is worked out in one place, `DisplayName` (`PaneModel.name`, `StateLog.Sighting.name`): herdr's terminal title (Claude Code's task summary) unless it says nothing a provider word would not (empty once its spinner and marks are stripped, the provider, `<provider> code`, the agent's name, a shell's name); else the pane's label; else its tab's label unless herdr's default; else its directory's last component; else herdr's agent name; else `pane <id>`; never the provider word alone; at most 80 grapheme clusters. It is remote text: shown, never sent, never a key. The provider is said as a kind word on the card's seat line (`CLAUDE · api / main`) and in the portrait card's and the seat's tooltips, and in the world as **a small mark at the seat: on the laptop's lid (far) or the chair's back (near)** (`ui.mark_<provider>`, see the row below); clothes and looks show neither provider nor state (see "Looks"). **No chest badge**: at 1 texel = 1 unit there is no room for a logo on a person; the smooth provider logos appear only in Avatar Studio | Pixel people family (`art.people`) | Sorted / Overlay |
| provider mark | A 4×3-unit mark: a simplified logo on a cream sticker, or the provider's colour with its initial, **on the far laptop's lid or on the near chair's back** (a seated near worker hides their laptop; the chair is drawn in front of them) | `provider` of a pane with an agent → `OfficeTable.mark_of()` (`ArtContract.lid_mark(provider)`); none for a shell, a launch whose kind herdr has not detected yet, an empty seat or a provider the catalog does not list; on the near chair it stays while the agent walks in. Bound to the field, not to state: never changes with state, selection or focus; a disconnected map dims it with everything else. No pixel within 48 of a state colour, so it never reads as a signal. Built with the pod (far) or the station (near), only its texture and `visible` change | `ui.mark_<provider>` | Desk / Sorted |
| agent state | **The station: pose + badge + things drawn only for the state** (see "Where people rest") | `agent_status` → the pack's `states`; `launch_pending` → starting, but **blocked wins**. Every state sits: idle sits (`desk_idle`) beside a mug; blocked raises a hand (`desk_blocked`) under a chip; done sits (`desk_idle`) beside a paper stack. What the desk shows is `OfficeStation.desk_item()`'s; animations resolve through pixel people's `state_tracks` (the office plays no track by name but `walk`) | `ui.working / blocked / unread / idle / unknown / starting` | Sorted / Overlay |
| **How long it has waited** | **The blocked chip: the badge and a duration, nothing else** | `HerdrFleet.state_since` → the duration in the in-world compact form (`OfficeAttention.compact_duration()`, never `+` here: `59s`, `12m`, `3h`, `4d`, at most `99d`, 14 wide at most), in the chip's right half, in the pack's figures face (Tiny5 at 8, as is the lens line: the world's only words outside Fusion Pixel, whose 8px digits would make `99m` 16 wide, more than the chip has at the 32-unit seat pitch); the same badge node moves into its left half, pulse and all. When stale or when the start was never seen, no number and no frame are drawn (an empty frame reads as a blank chip) and the badge stays in the middle of its row; only the raised hand and badge remain, and the click / hover area stays. Not drawn while the lens is held (the lens line says it). The HUD writes the same wait in `wait_text()` (`1h 05m`): one wait, two spellings, one source (`StateLog`) | Text; `panel` nine-patch | Overlay |
| **The blocked question** | **A HUD tip when hovering the chip** (a ten-character excerpt in the chip would say nothing) | An excerpt of `pane.read` `detection`: lines trimmed of spaces and box characters, the last line with `?` (else the last non-empty line), at most 120 characters; the full question is in the card. Read only for blocked panes on screen (`PaneModel.asks()`), on an online machine with a current snapshot, not under the monitor or OVERVIEW; one read at a time; reads of one pane start at least 10 s apart; only the latest is cached, dropped on leaving blocked; no reads while minimized; it never writes and never counts as "seen". `--read-only` writes `read-only`; before the first read, `Question not read yet` (never a "reading…" placeholder: a disconnected machine never answers). A chip click selects and enters answer mode once the question shows; a click on the seat only selects | The HUD's `HdPanel` (`%WorldTip` in `hud.tscn`, which the zone signs' tooltip shares) | HUD |
| **done (UNREAD)** | **A small stack of papers right of this seat's laptop** | `done`, not launching, has an agent → shown on the seat's one desk item (built with the pod, only its texture and `visible` change; `OfficeTable.ITEM_ASIDE` 13, on its side's working plane); frozen and dimmed with the map when disconnected | `done_stack_small` | Desk |
| **idle** | **A mug right of this seat's laptop** | `idle`, not launching, has an agent → the same desk item shows the mug (`OfficeTable.MUG_ASIDE` 12.5, opaque x+9..x+16, on its side's working plane); never both the mug and the paper; frozen and dimmed with the map when disconnected. The same picture as the desk pool's mug on a side table, a prop of its own so it is never drawn from a pool | `idle_mug` | Desk |
| State start | The `N` order | Earlier starts come first. **Unknown** is only for a state never seen to begin (the first snapshot of a connection); it counts as the longest wait and goes first, ties in projection order. Every transition watched while connected has a **known** start from when it was observed: a state change, a launch ending, a new terminal / agent / session, a pane appearing. Blocked while starting counts from when it was seen blocked; a launch that ends while still blocked, same terminal / agent / session, keeps its clock. So newcomers queue behind those already waiting | — | World |
| Pantry | A corner nook: one counter in the entry band, against the top wall at its left end | Furniture, no spots: only on maps with desks, placed by the map's plan alone; nobody walks to it or stands at it, and the walking lane runs in front of it. **There is no reception** | `pantry` | Sorted |
| Pantry sign | A hanging `COFFEE` sign on the top wall over the pantry counter | Furniture, bound to nothing: hung wherever the counter is (`OfficeShell.pantry_sign()`: centred over it, foot at `SIGN_FOOT` 52, on the cream face, no wider than the counter, so off every window, the door and every zone sign), and on no map without one. Part of the shell (Ground: no footprint, behind everyone). Wood, brass and cream; no state colour (`working`, `blocked`, `unread`, `task_light`) | `pantry_sign` | Ground |
| Partition | Low cream partitions round a zone: a U open at the top, a post at each top corner | Furniture: structure, never state. Down each side, along the bottom, at the zone's edges, the zone's carpet lying inside them; people walk into a zone from its open top, never across a partition | `partition_v`, `partition_post`, `partition_corner_bl / _br`, `partition_h` | Sorted |
| Zone sign | A small hanging sign at a zone's top-left post, over its aisle row, as wide as what it says (at most 160, never past the top-right post; a long label ends in an ellipsis) | Display of the workspace's number and label, an accent stripe its worktree group shares (`OfficeZoneSign.accent_of()`); hovering it names the repository and checkout (a read of the frame the office holds, never of herdr); structure, never state | `panel`; palette `sage` `sky` `terra` `teal` `lilac` | Sorted |
| Furniture | Plants, side tables | Standing on the floor, origin = foot point, in the y-sort. **A row of plants along the top wall's foot** on the wall's own 160-unit grid (from 72), each the plant of its step, clear of the door, windows, pictures and pantry; where no step clears them (the grid and the windows line up only at some widths), one plant in the first window gap that takes it, so every top wall stands at least one; **lane gaps** (3+ free cell rows inside a lane, outside every zone) stand a piece every two rows from the gap's second, in the lane's middle column, plants and side tables taking turns; a side table carries one desk piece (see "Desk decor"). Keyed by grid step, never placed by table, tab, zone or state, so their count does not follow tab count | `plant`, `plant_b`, `side_table` | Sorted |
| Wall picture | A framed landscape on the top wall | Furniture, on the wall's cream face (`FRAME_FOOT` 48). Centred in every second gap between two neighbouring windows, where it, grown by `FRAME_GAP` (8), touches no window, the door, the pantry or a wall-end cell; placed by the windows alone. Part of the shell (Ground: no footprint, not on the walk graph). Cream sky, sage hills, terra frame; no state colour (`working`, `blocked`, `unread`, `muted`, `task_light`) | `wall_frame` | Ground |
| Desk decor | Mugs, notebooks, clipped papers, plants, headphones, now and then a white cat: one piece on each **side table**, never on a pod's desks | A side table stands in a lane gap and carries one piece from the `desk` pool, or (28%) the `cat` pool, picked by weight from a stream seeded by its placement key alone (`OfficeDecorPlanner.side_table_item()`): never by tab, zone, state or time, so refreshes, growth and theme changes keep the choice. The cat's loaf, sleep and sit are static poses, not working / idle / done | `side_table`; `desk_mug / notebook / papers / plant / headphones`, `cat_loaf / sleep / sit` | Sorted |

Bold marks state signals. The Layer column follows [World model](WORLD_MODEL.md): flat on the floor or wall → `Ground`, standing on the floor → `Sorted`.

### Looks

A person's skin, hair style, hair colour, top, bottoms, hat / accessory and glasses follow the rules for **furniture**: they bind no herdr field
and never change with agent state, selection, focus or connection (a disconnected map dims as usual; the clothes stay). **Looks do not say the
provider** (D3, 2026-10-27): six agents of one kind are six different people. Each slot's value comes from, in order:

- the provider's default (`look` in `data/agent_catalog.json`), which a person wears only where no pane is given; a default, not an identity;
- the user's pinned choice for this provider in Avatar Studio (`user://herdstead_avatars.json`), which wins on every pane;
- for unpinned slots, a small fixed variation from SHA-256 of the provider and the pane's stable key (`HerdrFleet.pane_key`). The family varies
  every slot: skin, hair style, hair colour, glasses (1 pane in 6), and the clothes: top, bottoms, hat (6 in 8 bareheaded) and hat colour.
  The same pane with the same provider is the same person on every start and machine; Avatar Studio's preview and the showroom show one
  sample pane's pick for every row marked VARIES.

The pick never reads state, waits, focus, selection or any live field. A pane that changes provider is one person leaving and another arriving
(see **Identity** below), picked afresh; a new terminal or session is the same person.
**A portrait is the same person** (`PixelPortrait`, the agent card's; S3 PORTRAIT P2): its look is resolved by the seat's own call
(`PixelPortraits.look_of()`), so skin, hair, top, hat and glasses are the seat's. Its own extras, the expression (smile, smirk, focus),
freckles and headphones (about 1 pane in 6 each), are looks too: picked once per pane by the same hash under their own names, never by
state. A portrait is a still and shows no pose; the frame round it says the state.
**Read the pane's name on the plate, the provider on the seat's mark (the laptop's lid or the chair's back), the state in the pose and badge**:
clothing colour is neither a provider code nor a state.

## Immediate signals and walking transitions

People walk, so channels split in two: those that show the current state the moment an observation arrives, and the body catching up. Walking
itself is **not** a channel for any state; it is only the body going where the observation says.

| Channel | When it changes | What it shows |
|---|---|---|
| Name plate (at all times on a map with few occupied seats, else while hovered, selected or under the lens; its text on its own channel, `OfficeStation.show_name()`, so a new task summary renames the seat without seating the worker again), state badge, chip, paper stack, selection marks, the station's click area | At once (they are the signals) | The current observation: who sits here (by name), what state, how long, who is selected |
| Body position and pose | After arriving | Only at rest is it a state: seated at the station, the pose says the state |
| Walking (the walk strip) | From an observed change until the body settles (at most 6 s, 96–480 units/s) | Transition only: not timed, not busy or idle |
| Ghost (a person without a plate walking to the lift door) | When a pane leaves the map | Transition: this station's person has left; no plate, badge or card; clicking it selects nothing |

- **Entering**: a pane with an agent (or launching) appears; its person walks in from the lift door along the main aisle to the seat's approach
  point and sits. Plate, badge and click area are at the seat from the start; clicking the seat selects it while the person is still walking.
  Far seats are entered straight from the approach point. **Near seats have the chair in line with the approach point, and people never walk through
  chairs**: they walk along the near aisle to the stand spot's column, step onto the stand spot (now only a route knee; nobody stands there), then step
  sideways into the seat; leaving reverses it.
- **Leaving**: when a pane closes or its agent leaves (it becomes SHELL), the person walks to the lift door and vanishes
  there (a pane moving to another workspace of the same machine changes seats instead: another zone of the same map). The seat frees at once (plate first); the walker is a **ghost**. At most 32 ghosts; beyond that the oldest vanishes.
- **Changing seats** (column, side, or the whole pod moved) is the same person walking over, not a leave and an arrival.
- **Identity**: a pane that switches to a different agent (both providers known and different) is one person leaving and one arriving; the same
  agent in a new terminal or session walks nowhere (its state counts from when it was seen: a known, late start, for `N` only).
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
  walking; the reconnect is cold. Walkers stay frozen until the first drawable observation after reconnecting. A frozen person is the **only**
  one standing still anywhere, and the dimmed map says the picture is stale.
- **Accepted overlap**: plates, badges and selection marks are in the Overlay and draw over passers-by; walkers pass through each other and through
  standing or seated people. People avoid only furniture and walls ([World model](WORLD_MODEL.md), "Collision and walking").
- **The stride is a placeholder**: the body moves at constant speed and the walk strip plays at `speed ÷ 96`. The current strip's cycle is two
  steps of about 16 units over 4 frames and 0.56 s (about 29 units/s native), so at 96 units/s the feet slide about 3×. When the walk strip is
  redrawn, make one cycle's stride ÷ 0.56 s equal 96; no code change is needed.

## Where people rest

Agent state is drawn only at the station, and every state sits there: nobody leaves the seat for a state. (D2, 2026-10-27: idle used to walk
to the pantry; it sits with a mug now, and the pantry is a corner nook of furniture.)

| State | Where the person rests, doing what | What hangs where |
|---|---|---|
| working | Their seat, typing (`desk_work`) | Plate + badge at the seat |
| starting | Walks in from the lift door and sits (`desk_start`); no chip, no paper stack, no mug (`PaneModel.launching()`). This form starts with the first snapshot after herdr accepts `agent.start` (`launch_pending`, no kind yet). **Blocked wins over starting**: an agent asked a question while starting is drawn as blocked (raised hand, chip, blocked badge, the kind on the plate) and counts in BLOCKED, NEXT, the edge arrows and Waiting; that it is still launching shows only in the card (`Launching` tooltip, footer `claude-2 asks: answer with the keys`). One blocked on arrival has its chip at the seat while it is still walking in | Plate + hourglass badge (`ui.starting`) at the seat; until the kind is known the plate shows the upper-cased name herdr gave the agent (`CLAUDE-2`, `PaneModel.agent_name`) |
| unknown | Their seat, sitting still (`desk_idle`) | Plate + `?` badge at the seat |
| done (UNREAD) | Their seat, sitting (`desk_idle`); a small paper stack right of the laptop (`done_stack_small`) | Plate + badge at the seat; stack on the desk |
| blocked (including asked while starting) | Their seat, hand raised (`desk_blocked`); a chip on the badge's row with the badge and the wait; hovering it shows the question excerpt | Plate + badge + chip at the seat |
| idle | Their seat, sitting (`desk_idle`); a mug right of the laptop (`idle_mug`) | Plate + badge at the seat; mug on the desk |
| SHELL / empty seat | Nobody | SHELL's laptop / nothing |

- What hangs on a person hangs at their seat the moment the observation arrives; a body walking in follows. An empty-for-now seat keeps its
  chair and ordinary laptop (never `$_`) with nothing over it.
- One desk item per seat: the paper (done) or the mug (idle), never both, and none for any other state, a pane still launching or a shell.
  Going from one state to another swaps it in place; nobody walks.
- The chip's click area and the seat's never overlap: a seat click selects; a chip click selects and enters answer mode once the question shows
  (never sends; under `--read-only` it only selects). While a chip shows, the seat's click area gives up the tag row (far: its top drops from
  −90 to −72; near: its bottom rises from 32 to 14): every point belongs to one click area.
- Standing still happens only on a frozen, disconnected map; passers-by never stop. The pantry counter is furniture in the entry band's
  corner: nobody walks to it, and the walking lane runs in front of it.
- Disconnected (invariant 4): chips, paper stacks and mugs freeze and dim; chips show no wait or frame; nothing is re-ordered. The first
  refresh after reconnecting is cold (every start is unknown again).

## HUD panels

Everything below is HUD and never changes the world. The world draws only what their actions produce in the snapshot.

### Portrait bar

The top bar's middle is who needs you, as faces (`OfficeBar`, `PortraitBarModel`, `PortraitCard`, `PortraitFold`):
- **Order**: the blocked in `N`'s order (the leftmost is whom `N` picks), the done oldest first, then the working and the idle in place
  order (machines, zones, rooms, then the panes no zone seats). Every agent of an online machine, never a shell, never a launching agent
  that does not ask, never a dropped machine's (its agents are not activity; the status line says it is down).
- **Two forms, by the bar's band** (`OfficeBar.set_tall()`, `PortraitCard.set_tall()`; the same nodes): on a tall bar (a screen at
  least `staff_tall_from` high, the 70 band) **a tile** (50×66, B2's): a 42×42 face window (`%FaceBox`, the cream ground
  `PortraitWindow`) centred over the name row and the place row (12 each, the name centred), holding the seat's person as a
  portrait (`PixelPortrait`, `OfficeDraw.seat_portrait()`: the 40×40 portrait whole in the window's 40×40 clip, its bottom
  centre on the clip's), and over the portrait, in this order, the state's frame (`%FaceFrame`, `PortraitFrame<State>`: 1 unit,
  2 under the pointer), the pointed ring, the selection's ring and, in the top-left corner, the state's small mark (`%Badge`: 8×8
  units, the pack's `badge_<badge>_small`: blocked's `!` and done's envelope cover the frame's corner, the working and idle dots
  sit inside it; shown, never pulsed: it is not in `StatusBadge.GROUP`). Nothing the HUD draws is under the portrait, so the
  frame, the selection and the pointing all read over hair, hats and shoulders; on the cream window the selection is `ink`
  (`PortraitSelectedTile`) and the pointed ring `slate` (`PortraitPointedTile`), where a card's `paper` would not read; the portraits' face box keeps eyes, brows and
  mouth 3 units or more from every edge and clear of the mark. The words stand on the bar's ground (`PortraitTile`). Face-only
  26×66: the window 24×42, the portrait cropped to its middle 22 columns (a crop, never a scale: hair sides are cut, the face
  stays whole); folds 40×66 and tallies 24×66. On a short bar (the 32 band) the horizontal card below, no mark, with the small
  person, its foot at the face window's middle, 37 under its top. A card keeps both faces from its first pane on, shows the
  one its form wants and dresses only that one, so a flip of the band makes no node. The wordmark, the strip,
  `1 machine · 13 panes`, the chime switch and the two lines stand in the band's middle, as the short band holds them in its own.
- **A card** (86×28, the short bar's): the seat's person, standing and facing front, still (`OfficeDraw.seat_face()`);
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
- **The AGENT page** is the agent card (scene name `inspector`): the portrait in a 48×48 slot (the seat's person as a head-and-shoulders
  portrait, `PixelPortrait` from `OfficeDraw.seat_portrait()`, still: a 42×42 window at (3, 3) on the warm `cream` ground
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
- In the world, a split pane first appears as an empty seat with an ordinary laptop; a person walks in only after a launch is accepted. A closed pane
  is the reverse (the person walks out, the pod or zone disappears, NEWS `pane closed`). A new space or worktree is a new zone of the same map
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
- Zone-level focus is not drawn: the focused pane's lamp already says where herdr's focus is, and the current machine chip and the view itself say what Herdstead is showing, which is not herdr's focus.

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

- Under the top outer wall is a 64-unit entry band (two cells: the wall's drawing clearance, then the walking lane, with the pantry counter
  in its left corner, nobody at it); the main aisle on the right is
  64 wide; each side wall is one 32-unit cell; the front wall is not drawn.
- Below the entry band the map is **lanes** of 4 cells (the narrowest pod and its zone's pad) with a one-cell aisle between two; a zone stands in
  whole lanes under an aisle row of its own, first as many as its pods need to stand in one row, its pods in rows as deep as a pod's reservation. Zones are placed as a masonry that only grows, down or right: retained zones hold their
  place, a growing zone grows in place while it can and otherwise moves alone, new zones take the top-most, left-most gap.
- Only the top outer wall has windows, pictures and the lift door. There are no inner walls.
- Walls assemble on one `TileMapLayer` grid: the top wall's two courses and the side walls. The row walls' joints are no longer laid.
- The base floor covers every cell of `floor_cells`; walkways lie over the entry band and the main aisle. Each zone has **one carpet** inside its
  partitions (from its top to its bottom partition), in its worktree group's family; none under an aisle row, an aisle column or a corridor.
- A map's first plan fixes its lanes. Window size, zoom, renames, state and focus never move pods; structural changes start from the old plan,
  prefer growing in place or into gaps, and an over-wide pod gets its own row (its zone taking more lanes, the map widening if it must). A
  removed pod or zone leaves a gap; nothing re-queues, and the map never shrinks.
- Panes that stay in the same tab keep their person nodes through growth, moves and side changes. Machine and theme switches rebuild the current world:
  the cache holds plans and views, not resident people per map.
- Plants and side tables are `StaticBody2D`s with foot points and footprints; they never take pods, zones, the entrance or aisles, and
  they are not a reading of how many tabs or agents there are. Nothing stands by the door or on the pantry counter.

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
| A strip of windows per zone in the HUD (the SPACES rail's) | Retired with the rail (S3 BAR-b, 2026-10-27): the carpets and seats show each zone's panes, the portrait bar says who needs you, and `S` draws every zone's seats in the same state scale (`StrategicModel.window_look()`). A second per-zone strip would say the same states again in a third place. Nor are the rail's in-view marks drawn any more: the view is what is in view. |
| The agent list (a drawer on the right, `A`) and its local attention records (snooze, hide, restore) | Retired (S3 PANEL-a2, 2026-10-28). Every job it had is done elsewhere: every pane, shells included, is a row of the OVERVIEW; who needs you, by urgency, is the portrait bar; the tree is the strategic view's sections; History is the bottom panel's HISTORY page (`A` shows it); the monitor opens from the card (`M`). The filter box has no successor (the OVERVIEW sorts by name and filters by state). Snooze and hide changed nothing herdr or the world showed, and nothing read them once the list was gone. |
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
4. Placement: flat on floor or wall (a zone's carpet, a pod's wash) → `Ground`; standing → `Sorted`, origin = foot point; on a desk → a child of the table; floating over the
   world → `Overlay` (`OVERLAY_Z`).
5. State changes only change properties of existing nodes (`visible`, `color`, `text`); never destroy and rebuild.

## Known future conflicts

- **"Standing" and "passing by" look alike.** Only a frozen, disconnected map has people standing still: everyone else sits at their seat
  (idle too, with a mug, since D2, 2026-10-27). Passers-by never stop and carry no plate or badge (those stay at the seat). The one person
  standing still is frozen by a disconnect, and then the whole map is dimmed.
