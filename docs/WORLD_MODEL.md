# Herdstead world model: people, space, objects, collision, walking

The office world is built only from Godot's own systems. There is no custom depth contract, render-pass table or
occlusion texture: who covers whom follows from position, never from numbers tuned against a screenshot.

The people are pixel people (`PixelPerson`): density 2, nearest filtering, six layer strips. Floors, tables and
people are all density 2; geometry is in world units and does not depend on density. The pixel people's contract and
build are in [the asset spec](ASSET_SPEC.md), "Pixel people". Changing the people never changes Y-sort, the order of
furniture, or where anyone's feet land.

## Abandoned approaches

These were tried and dropped as a whole. Do not bring them back under any name.

| Approach | Why it is gone |
|---|---|
| A depth contract: a spatial_contract.json file + `TableSpace` + 12 `z_index` passes + occlusion layers | Depth came from tuned numbers, not position. It put a person sitting on the near side of a table behind the table's occlusion layer, although someone closer to the viewer than a table cannot be hidden by it. |
| `AvatarRig` syncing six `AnimatedSprite2D` every frame | Per-frame sync code lets layers drift a frame apart. One `AnimationPlayer` per person keys every layer instead (rule 6). |
| A hand-kept table of hit rectangles in `office.gd` (screen + pan − origin arithmetic) | The engine's physics picking does it (see "Collision and walking"). |
| The native `AStarGrid2D` for walking | It walks through a thin obstacle between two clear cell centres, even with its points moved to the centres. `OfficeWalkGraph` checks edges, not only nodes. |

## Six rules

1. **Origin = foot point.** Every world object's node origin is where it touches the floor: a person's feet, a
   chair's legs, a table's near edge.
2. **Depth comes only from Y-sort.** Every `Node2D` on the path from the sort root to a sorted entity has
   `y_sort_enabled = true` (nested y-sort merges into one sort group). Larger y is closer to the viewer and draws later.
3. **`z_index` has one use.** The floor is not a z value but a sibling drawn before the sort root. UI floating over
   the world (name plates, status badges, selection frames, table frames) uses the one named constant
   `OfficeWorld.OVERLAY_Z` (10). No other `z_index` is allowed: `z_index` beats Y-sort, so every extra z value is one
   more place where the position rule stops holding.
4. **What sits on a tabletop is a child of the tabletop.** A pod of desks sorts as one whole at its near edge.
   Desktops → grommets → lamp light → far laptops → the low screen → near laptops → papers draw in node order, with
   no depth rule; nothing else stands on a desk (trinkets and the cat are not a pod's). Every seat's laptop, grommet,
   lamp and paper stack are built in `setup()`, new
   columns start switched off, and `resize()` only adds new columns, keeping existing seat markers and equipment.
   State changes go through `equip()` (has a pane, is a shell) and `light()` (four lamp levels
   `Lamp.OFF / DIM / ON / FOCUS`), which switch texture, `visible` and `color` on existing nodes and never add or
   remove nodes. The four alphas (`LAMP_ALPHA` = `[0.0, 0.10, 0.22, 0.52]`, `LAMP_STRONG` = 1.4 for lamp-lit packs)
   are table geometry and live only in `table.gd`; which seat gets which level is `OfficeFloorView.lamp_of()`'s call.
5. **Sitting = snapping to the seat `Marker2D` with collision off; standing up is only for going to the pantry
   (idle), with collision on.** A far seat lies inside the table's footprint, so the table hides the legs. A near seat
   is outside the table's edge, so the person draws wholly in front of the table, and the near chair back sorts after
   the person (closer to the viewer). Done and blocked agents stay seated (done's paper stack is a child of the table;
   blocked's chip is in the station's `Overlay`). Only idle agents that are not starting leave their seat for the
   floor's pantry (see "Entry-band fixtures"; the rule lives only in `OfficeRests.rest_of()`): the same actor node
   changes pose and walks there, is never rebuilt, keeps origin = feet, sorts by the y of its feet, faces the viewer,
   and leaves the chair where it is. The table's standing spot `table.standing(column, side)` still exists (constants
   only in `table.gd`: `STAND_ASIDE = 16` beside the column, in the gap between two chairs, the far one `FAR_STAND = 6` above the far edge, the near
   one `NEAR_STAND = NEAR_SEAT`), but nobody stands there: it is the corner where the near seat leg turns round the
   chair (see "Collision and walking"). Its numbers stay so no floor is planned differently.
6. **One `AnimationPlayer` per person.** Its value tracks drive each layer's `frame`; layers cannot drift apart and
   there is no per-frame sync code. Sitting, standing and turning swap only textures, `flip_h` and the playing track,
   never nodes.

## Prefabs

| Scene | Root | Role |
|---|---|---|
| `scenes/people/pixel_person.tscn` | `CharacterBody2D` | A pixel person: six layer sprites under `Layers` (`Legs`, `Top`, `Body`, `Glasses`, `Hair`, `Headwear`, bottom to top), one `AnimationPlayer`, a `Feet` collider, no chest badge. `configure` dresses, `play_state` picks the motion, `face` turns, `sit` / `stand_up`, `pace` sets the step rate; `drawing_rect()` / `footprint()` measure the person for layout. |
| `scenes/world/table.tscn` | `StaticBody2D` | A pod of single desks built from 32-unit modules, one desk per column: desktops, apron, the low screen between the two rows, two short legs, a bracket per desk, footprint collider; per column and side a seat `Marker2D`, a standing `Marker2D` (`Standing`, `standing()`: the near seat leg's corner, nobody stands there), laptop, grommet, lamp and done's paper stack (`Papers`, `show_papers()` / `papers()`, built with the table, only `visible` changes). `measure()` gives the planner its size; `resize()` / `relocate()` update in place; `equip()`, `light()` and `show_papers()` switch existing nodes. **All table geometry constants live only in `scripts/world/table.gd`.** |
| `scenes/world/station.tscn` | `Node2D` (y-sort) | One seat: chair, person (seated, or standing in the pantry when idle, rule 5), `Overlay` and `Target`. `Overlay` holds the name plate, lens line, seat mark (`selection_seat`), status badge and the blocked chip (`bubble.tscn`, `OfficeBubble`: a 30×16 `panel` with the same badge node moved into its left half and the wait in `OfficeAttention.compact_duration()` in its right half; with no writable wait (start not seen, disconnected) it draws nothing, not even the frame, the badge is back in the middle and its click area stays; it never shows the question, which is in the HUD tooltip `%BubbleTip`). The rows over a seat are listed in "Rows over a seat" below. The plate shows only while the seat's or the chip's rectangle is hovered, the seat is selected or `L` is held. Seated offsets (`PLATE_AT`, `BUBBLE_AT`, ...) are relative to the seat, the `AWAY_*` ones relative to where the person rests in the pantry, where there is no plate; a move only changes their `position`. `Target` is the click `Area2D`: this side's seat rectangle (while the chip shows it is swapped for a shorter one that leaves the tag row to the chip), `Bubble` (the chip's, enabled only while it shows; a click there emits `asked`, anywhere else `picked`; pointer enter/exit emits `bubble_hovered`; the badge draws over the chip) and `Away` (enabled with the seat rectangle while the person rests in the pantry). The other side's seat rectangle is never enabled. `rest_at()`, called by the presentation, hangs overlay and click area where the person rests. Every column has a station on both sides; one without a pane is an empty chair that cannot be clicked (no laptop, lamp off). `rebind()` rebinds the seat and sets position and click area absolutely, keeping the actor. A station hands its laptop, lamp and paper stack to the table and never touches the table's nodes. While the presentation walks the person (`walking`), `furnish()` / `rebind()` leave the person's position and motion alone, only recording the seated look, and `land()` applies it on arrival. |
| `scenes/world/decor.tscn` | `StaticBody2D` | One standing piece of furniture (plant, filing cabinet, and the entry band's counters): a `Sprite2D` placed on its foot point plus a footprint on the `FURNITURE` layer. Footprint sizes come from each piece's `item` block in the pack (`OfficeDecor.footprint_of()`, including the two counters; [ITEMS](ITEMS.md)). **Furniture binds no herdr field**; its position comes only from the floor layout. |

Floor assembly:

```text
FloorRooms              the node dimmed as a whole when its machine disconnects
├── Ground              floor TileMapLayer, shell, the lens's washes, corridors, contact shadows, wall signs and titles,
│                       framed pictures on the row walls (drawn first)
└── Sorted (y-sort)     tables, stations, standing furniture, the entry band's counters, and anything else that
                        stands on the floor and can cover or be covered by a person
```

### Grid, measurement and stable ordering

A real workspace's floor is laid out by `OfficeFloorLayout` into a `FloorPlan`; `OfficeSeatPlanner` handles one tab's
seats. `ZoneModel` / `RoomModel` / `PaneModel` hold no render nodes; `FloorPlan` / `RowPlan` / `DeskPlacement` /
`SeatPlacement` hold grid bounds, table origins and seat bindings; `OfficeFloorView` / `OfficeDeskView` assemble nodes
from the plan.

A building with no workspace still has one floor: LOBBY is an empty floor with no tabs. It goes through the same
planning, furnishing and assembly path as an empty workspace (outer walls, door, windows, walkways; no rows, so no
standing furniture), places nothing herdr gives, and is left out of the layout diagnostics (`layout_plan()`,
`layout_problems()`, `layout_attempt_count()`). Its notices (offline, waiting, ssh error) are on the floor plate.

The grid is fixed at **32 world units**. A floor's first plan picks its initial width from the viewport width
available at that moment, meeting the minimum table group and walkway sizes. After that, window or zoom changes only
change how much is visible; rows never reflow. A floor's origin is fixed and it only grows right and down. A removed
table group leaves a reusable gap; tables, rows and other groups never shrink or compact on their own. An oversized
table takes a row of its own and widens the floor to the right if needed, extending the cross corridors and moving
the main corridor to the new right edge.

`OfficeTable.measure(capacity) -> DeskMeasure` is the only source of table geometry. A tab is a **pod of single
desks**: one 32-unit desk per column, a seat on each side of it, the two rows facing across a low screen.
Coordinates are relative to the pod's origin at the left end of its near edge:

| Measure | Value / rule |
|---|---|
| Capacity and width | `capacity` is at least 2 and counts columns per side; the planner grows it 2 columns at a time and keeps old capacity. Width is `max(64, capacity × 32)` (`MIN_WIDTH` 64) |
| Column x | `16 + 32 × i`; growth never re-centres existing columns |
| `physical_rect` | `(0, -48, width, 48)` (`SURFACE_DEPTH` 48), the desktop's collision footprint only |
| `render_rect` | `(0, -90, width, 136)`: y [−90, 46), the stationary drawing: the tag rows' badge pulse envelopes, the chips, laptops, paper, the seat marks and the pod's selection frame. The plate and lens rows are transient (hover, selection, held `L`) and lie outside it |
| `reserved_rect` | `(0, -128, width + 32, 192)`: six cells, from the far approach row to the near one, with a one-cell passage on the right; bottom edge 64 |
| Seats | far `(x, -36)` (`FAR_SEAT` 12 inside the far edge), near `(x, 22)` |
| Laptops | same x as the seat; far foot `(x, -40)` (8 inside the far edge: the rear view −48..−40, clear of the far worker, who shows only above −48), near `(x, -10)` (−21..−10). 14 units wide; rear view 8 units tall, front view with keyboard 11. A shell's empty chair gets the same laptop as an agent |
| Near edge and supports | The working surface ends at `NEAR_SURFACE_EDGE = -8`; a 3-unit lip meets the apron at `APRON_DROP = -5`, `APRON_HEIGHT = 3`. Two `leg_short` legs, `LEG_DROP = -2`, centred under the end columns' near chairs (x 16 and width − 16), which hide them whenever somebody sits there; the foot ends at y 19, above the chair's gas lift. A `bracket` per desk at `BRACKET_DROP = -11`. Lamp light stops at the working surface, never past the edge |
| Low screen | `SCREEN_TOP = 16` below the far edge, `SCREEN_HEIGHT = 6` (−32..−26). The far working plane is −48..−32, the near one −26..−8 |
| Lamps | `LAMP_HALF_WIDTH = 4` at the screen, `LIGHT_HALF_WIDTH = 14` at the sitter's edge |
| Chair | `CHAIR_OFFSET` far −4 (sorts just behind the worker), near 6 (just in front; opaque down to y 28) |
| Paper stack | `done_stack_small` (6×9 opaque), `PAPERS_ASIDE = 13` right of the column: opaque x+10..x+16, clear of the laptop, of its worker's raised hand (to x+12) and of the next column's worker (from x+22), inside the desktop on the last column. Far foot `PAPERS_FAR = -33` (−42..−33, far plane), near `PAPERS_NEAR = -15` (−24..−15, near plane, above the near raised hand's top at −14) |
| Standing spots | far `(x + 16, -54)`, near `(x + 16, 22)`: the near seat leg's corner, in the gap between two chairs; nobody stands there |
| Approach points | far `(x, -80)`, near `(x, 48)`, both cell centres; read via `approach_position()`. They start the walk-graph legs to seat and standing spot (see "Collision and walking") |

No trinket, cat or rug belongs to a pod: nothing stands on a desk but a seat's own equipment and its paper.

#### Rows over a seat

Every row is 30 units wide and centred on its column, so neighbours (32 apart) keep 2 units between them. Pod y,
half-open; the badge's pulse (`OfficeAttention.PULSES`) lifts it by 0, −1 or −2:

| Row | Far (above the head; raised hand top −72) | Near (below the chair; chair bottom 28) |
|---|---|---|
| Tag (the badge, 15 opaque, centred) | [−88, −72); pulse envelope [−90, −72) | [30, 46); pulse envelope [28, 46) |
| Chip (blocked with a known wait) | `panel` [−15, 15) × [−88, −72); the badge in x [−16, −1) (one unit over the chip's left edge), the wait's 14-wide label in [0, 14): the widest form inks 13 units, so daylight stays between it and the badge and before the frame's right border | the same, over [30, 46) |
| Lens (held `L`), 30×12 | [−102, −90) | [46, 58) |
| Plate (hover, selection, held `L`), 30×12, display face at 8, upper case, forced ellipsis | [−114, −102) | [58, 70) |
| Seat click rectangle | [−90, −32); [−72, −32) while the chip shows | [−21, 46); [−21, 28) while the chip shows |
| Chip click rectangle | [−90, −72) | [28, 46) |
| Seat mark (`selection_seat`, 32×48, pivot (16, 46)) | `SELECTION_AT` (0, 10): [−72, −24) | `SELECTION_AT` (0, 4): [−20, 28) |

At the 192-unit row pitch the next row's far plate starts at 192 − 114 = 78, past this row's near plate (70): 8 units
to spare. The geometry suite pins every row, both pulse extremes, known and unknown waits and held `L` across two rows
(`test_rows_at_the_pod_pitch_never_meet`).

`reserved_rect` includes walkable space and must not be used whole as a navigation obstacle. The planner rounds it
outward to a grid reservation and derives the table origin from that; `office.gd` never copies table width, column
pitch or seat offsets. Seat nodes still come from `table.seat(column, side)` / `standing()`. `setup()` rejects
non-finite numbers, illegal widths and illegal columns at creation and on update; a width must be a multiple of 32 and
at least 64. The plate, lens and chip Labels are sized again once the display face is on: a Label is 23 units tall
before its font applies.

Each row is fixed at **320 units = back wall 64 + pod reservation 192 + cross corridor 64** (`row_height_cells` 10).
Below the top outer wall is a **96-unit entry band** of three cell rows: the first is inside the outer wall's drawing
clearance, the second is the fixture row (y = 112), the third the walking lane (y = 144). The first row has its own
back wall. The main corridor on the right is 64 wide, and each side outer wall takes 32. Every row back wall ends
before the main corridor so the vertical path is never sealed. A floor with pods is therefore 15 cells deep (one
row); the lobby and an empty workspace are 12.

`FloorPlan.floor_cells` is the one half-open integer rectangle. The base floor covers every cell of it, including
under walls, at short row ends and in gaps left by deletions; walkways draw over that full floor. The total
drawing extent comes from the plan and the floor plate together; the camera never guesses bounds with stray `ceil()`
or margins.

### Shell and joints

A workspace's walls are drawn on one `TileMapLayer` at `Ground/Shell/Walls`; every cell ends up with exactly one
semantic ID. The top outer wall uses two courses, `wall.cap_left/center/right` and `wall.face_left/center/right`;
side walls run from top to bottom. Where a row back wall meets the left outer wall it uses
`wall.cap_t_left / wall.face_t_left`; before the main corridor it ends with `wall.cap_end_right / wall.face_end_right`.
A joint replaces the straight or side wall in the same cell; two sets of end pieces are never stacked. Only this
rectangular shell with parallel row back walls is supported; it is not a general wall-network generator.

**The apron.** Past its side walls the shell carries plain wood floor (`Ground/Shell/Apron`, a `TileMapLayer` under the
floor's own), from the screen's left edge to its right one and as deep as the floor, so the HUD's side panels float
over floor rather than over the backdrop (`OfficeFloorView.apron_cells()` from the camera's room and the screen;
`set_apron()` only refills its cells). It is drawn only: no wall, walkway or furniture, never in the plan's cells, the
walk graph, a seat's click or the camera's reach. Below and beyond the floor's depth the backdrop stays.

Cap plus face make a 64-unit drawing band, the same band the people's clearance check uses. Bricks are placed with
`set_cell()` by semantic ID; no Terrain autotiling, and no `TileMapPattern` deciding where walls and openings go.

Only the top outer wall carries windows and the lift door. Row back walls carry tab signs, and framed pictures hang
between the signs (`OfficeShell.frames()`): the wall is cut into bays `FRAME_PITCH` (320) wide from `FRAME_FROM`
(312); each bay hangs at most one picture, at its start or the next gap of the wall-foot run (`FRAME_SECOND` = 160
on), at the first of those places whose picture, grown by `FRAME_GAP` (8), clears every sign, title, table and
standing piece. Pictures are drawn in the shell, have no footprint and are not on the walk graph; the shell's key
includes them, so a table that moves a sign redraws the shell. The first row's back wall is an inner wall and carries
no windows. The lift door is directly over the main corridor's left lane (`OfficeShell.door()`, its x a cell centre);
windows keep `WINDOW_CLEARANCE` (64) from it.

**There is no front wall**: `wall.front_*` and `wall.threshold` stay unused, because a wall at the near edge would
cover the seats of the nearest row. The door is outer-wall furniture (it
does not open, there is no opening); people enter and leave a floor at the door's foot (see "Collision and walking").

The shell, the plants and the cabinets are **furniture**: they do not change with agent state, focus, selection or
connection. Structural changes (a tab opened or closed, a table grown) may move them; furniture has no herdr data
behind it and does not stand for repos or agent counts. Furniture is optional: its drawing must not cover a table
group, a wall sign or title; its footprint must not intrude on a walkway; and the floor must still pass the
entrance-to-station path check with it placed. If it does not fit, it is left out.

Each row's candidates, in order:

- the filing cabinet `%06d/cabinet` at the back wall's end and the plant `%06d/plant` at its start, each
  `DECOR_FROM_END` (40) from the row's end;
- between them, **the wall-foot run** of plants `%06d/wall/%03d`, on the wall's own grid: one every
  `OfficeShell.WALL_RUN_PITCH` (160) from the first plant, keyed by grid step and never placed by tables or tabs, so
  when tables grow or move the plants that still fit keep their keys and places. A grid place whose plant would come
  within `WALL_RUN_GAP` (8) of a sign, title or other piece stays empty. The run stands on the same strip under the
  wall as the cabinet (foot y = row top + 76, `PLANT_FOOT`; cabinet `CABINET_FOOT` 80; footprint only in the row's
  second cell row, T+64..96), and the far walkway stays open;
- last, the **spare bay** plant `%06d/bay`: when a row's last table's reservation ends at least `SPARE_BAY_CELLS` (3)
  cells short of the main corridor, one plant stands on the cell centre in the middle of that gap, its foot level with
  the pods' near edge (row top + `BAY_PLANT_FOOT`, 192), with at least one full free cell column on each side. An
  empty row has no spare bay.

Which plant image is used comes from `OfficeDecorPlanner.plant_at(index)` by grid step (the spare bay by cell
column); today it is always `plant`, and a second plant kind changes only that function, moving nothing.

Candidates and choices live in `OfficeDecorPlanner` (`scripts/layout/`). `OfficeFloorLayout.plan()` places them
before the one validation a candidate plan gets; if the furnished plan fails, it drops the batch and validates the
bare floor once more (a rare second flood fill). Furniture never moves a table group. The wall-front position
constants (door, windows, signs, titles, furniture feet) all live in `OfficeShell`, so planning and drawing read the
same numbers. Standing furniture stays a direct child of `Sorted`; each table's lens wash, sign and contact shadow may be
grouped under Ground, but people must never be wrapped in a table group with y-sort off.

### Entry-band fixtures

Two counters stand against the top wall in the entry band: the **reception** left of the lift door and the
**pantry** at the band's left end (`FloorPlan.reception / pantry`, typed `FixturePlacement`, planned by
`OfficeFixturePlanner` in `scripts/layout/`, both drawn by `decor.tscn` as ordinary `OfficeDecor`). They are not
furniture candidates: for the furniture rules the entry band is a walkway, and the counters stand in it on purpose.
**Nobody queues at the reception** (blocked agents sit at their own seats); the planner still reserves its queue
slots, and the validator and walk graph still check them, only so that no floor is laid out differently. They are the
empty space in front of the counter.

Only floors with tables have them. Every position is a pure function of the plan's geometry. The reception's right
edge is `OfficeShell.DOOR_CLEARANCE` (16) left of the main corridor's left edge (the 48-wide door, centred on the left
lane, reaches 8 into the bay, and 8 more keep the counter off its frame); counters meet the floor at y = 106
(`COUNTER_FOOT` = 42 from the band's top), 6 short of the fixture row. The pantry's left edge touches the left outer
wall.

- **Queue and pantry spots** are on the fixture row (y = 112), `SPOT_PITCH` = 48 apart (a standing person's click
  rectangle is 38 wide and a wait label 40, plus 8 between neighbours; kept so no floor is laid out differently). The
  queue runs left from one cell left of the reception (its head next to the counter); pantry spots run right from the
  left wall. On the walking lane right below each spot (y = 144) is its **approach point**; its leg is "cell centre of
  the approach point → approach point → spot". Neighbouring queue slots also have a one-cell sideways **step leg**.
- **Capacity**: a band that cannot hold the reception, the door's clearance and `MIN_QUEUE` (2) slots has neither
  fixture. One that holds the reception but not the pantry plus one spot (with `FIXTURE_GAP` 16 between) has only the
  reception. When both fit, the stretch between them is split by spot count: the queue takes half (rounded up, at
  least 2, at most `MAX_QUEUE` 24), the pantry the rest (at most `MAX_PANTRY` 24). At 11 / 20 / 32 / 60 cells wide the
  queue has 2 / 5 / 9 / 18 slots and the pantry 1 / 4 / 8 / 17. When a floor widens, the reception and its queue follow
  the main corridor; the pantry stays.
- **Windows** (`OfficeShell.window_xs()`, a pure function; the floor view only draws what it returns): on a floor
  with counters, windows are `WINDOW_SPACING` (128) apart, centred on the top wall between the pantry's right drawing
  edge and the reception's left drawing edge, as many as fit with equal margins at both ends (1 / 3 / 6 / 13 at
  11 / 20 / 32 / 60 cells). The reception is left of the door, so that stretch is already beyond `WINDOW_CLEARANCE`.
  Floors without counters (lobby, empty workspace) put one every 128 from x = 64, a cell off the side wall and
  `WINDOW_CLEARANCE` from the door. The shell's signature includes the fixtures; a fixture change redraws the shell.
- **Left out when validation fails**, never moving a table group: `OfficeFloorLayout.plan()` validates once with
  furniture and fixtures. If that fails, the second try drops the furniture (with no furniture, the pantry; with no
  pantry, the reception). If that fails too, the third and last try drops the pantry when only the pantry's problems
  remain, otherwise both. Default widths pass on the first try (one flood fill).
- Who rests at which spot is a pure function of the current model in `OfficeRests` (`scripts/world/`): see
  [the visual language](VISUAL_LANGUAGE.md), "Where people rest".

Desk trinkets and the white cat are not a pod's: nothing stands on a desk but a seat's own equipment and its paper.

### Incremental updates and caching

Table groups are identified by the stable key `(machine, workspace_id, tab_id)`, panes by `(machine, pane_id)`. The
terminal layout is first turned into column, side and order within the tab; when layout is missing, old seats are kept
first and gaps filled by stable pane key. A proportional resize of the terminal rectangles must not reorder existing
columns; explicit seat conflicts may allocate extra columns and produce a diagnostic. A new plan consults the old one,
grows in place where it can, and moves only the affected groups when it cannot; other surviving groups keep their
place.

At run time `FloorPlanCache` keeps, per floor key, the last valid plan with its display model, and the last attempt's
input signature with its failure diagnostics; `OfficeNavigator` keeps each floor's view. None of this is saved to
disk. Renames, state, focus and disconnects do not invalidate the geometry cache. The same failing input reuses the old
picture and diagnostics without running the planner and never adopts an invalid display model; only a change of
structure, theme, clearance policy or budget tries again. Window size does not change fixed rows; only when a new
policy is incompatible with the old plan and has not yet laid out successfully does a width change retry a cold plan
under that policy. Closing a workspace clears its valid plan and attempt record. Rebuilding the same plan keeps the
gaps history made; a cold plan without that history is not an equivalent rebuild. Duplicate identities, illegal
geometry or over-budget input never replace the last valid plan; the UI shows a layout error, and a first failure
keeps a bounded empty floor.

The allocation budget has three parts. Input pane / tab counts bound parsing work. Floor cell count, width and height
bound the TileMap, the shell and each row's standing furniture (cabinet, start plant, the wall-foot run at most one
per 160 units, and the spare bay plant). `FloorLayoutPolicy.max_desk_nodes` (default 32768) separately bounds **the
sum of the node upper bounds of all live table groups on a floor**. `OfficeDeskView.node_budget(capacity)` charges
`26 + 71 × capacity` per pod, where capacity is the retained columns per side, not the current pane count: 26 fixed
nodes (21 of the pod: its body, 12 holders, the footprint, the overlay, the frame and its 4 bars, the 2 short legs;
5 of the background: itself, the lens's wash, the contact holder, the sign, the title) and 71 per column (20 of the
pod's: a desk, an apron and a screen module, a bracket, 2 laptops, 2 three-node grommets, 2 lamps, 2 papers, 2 seat
and 2 standing markers; 1 contact shadow; two 15-node stations and two 10-node people), measured on the dressed
prefabs at 2, 4, 18 and 250 columns (168, 310, 1304 and 17776 nodes with everybody seated). Geometry tests count the real dressed prefabs, so a scene change cannot silently break this
contract. Empty tabs, historical empty columns and shells are charged in full, so later state changes never need to
buy person budget; only closing a tab frees a table's budget, and nothing shrinks tables or compacts rows. This is an
allocation ceiling, not a guarantee of memory bytes, GPU or frame time; replacement nodes awaiting `queue_free` are not
part of the settled live count. The planner rejects an over-budget table before creating its per-column measurement
coordinates. An old plan is budget-checked too, and its table widths and column coordinates must match the canonical
measure for its capacity, so a small capacity cannot hide many surface modules. A budget change never triggers a
geometry re-layout; over budget still fails and keeps the old picture.

`OfficeFloorView` reuses `OfficeDeskView` by tab key. Growth and moves go through `table.resize()` / `relocate()` and
`station.rebind()` in place; panes still in the same tab keep their station, actor and native `AnimationPlayer`, and
keep animation progress when the pose did not change. `rebind()` positions absolutely from the click areas' original
scene offsets and never accumulates `+=`. A seat swap finishes every binding before restoring equipment state, so a
later empty seat cannot clear an earlier station's laptop. Contact shadows are owned by the table and drawn on Ground;
repeated `contact_shadows()`, a background group change or a move never duplicates old shadows.

When the wall extent or walkways change, the shell subgroup is rebuilt; when a table group's geometry changes, its wash
and sign are updated. There is no per-brick diff. Changing floor or theme still rebuilds the current world; what is
kept is the plan and the view, not the people's nodes or animation clocks across floors.

## Collision and walking

- Collision layers: `FURNITURE` (tables and other `StaticBody2D`), `ACTORS` (people, mask = `FURNITURE`) and
  `PICKABLE` (a station's `Target`: mask 0, not monitoring, not monitorable).
- **The engine picks stations.** `Target` has `input_pickable` on; the viewport converts the click to world
  coordinates and delivers it. `office.gd` keeps no hit-rectangle table and does no screen/pan/origin arithmetic.
  `PICKABLE` is its own layer so click areas never block a walking person. Event order (Godot 4.7.2): Control GUI
  dispatch → `_unhandled_input` → physics picking on the next physics frame; once any step marks the event handled,
  the later ones never see it. So a station under a HUD panel cannot be clicked, and the press position is already
  recorded in `OfficeCamera` when picking runs.
- **Only a left-button release can select.** A press is only a drag that has not moved yet; the wheel and the right
  button never select, however still. `OfficeStation` filters this (only a left release emits `picked`);
  "release within `CLICK_SLOP` (4) of the press" is `OfficeCamera.still_click()`. One place each, no duplicates. The
  viewport only picks inside the visible area: an off-screen station cannot be clicked, and `OfficeScene.reveal()`
  pans it in first.
- People are `CharacterBody2D`: standing, the feet collider is on and `move_and_slide()` is stopped by furniture;
  seated, it is off.
- **The walk graph (`OfficeWalkGraph`, `scripts/layout/`) is the one graph the layout validator checks and the people
  walk.** Nodes are cell centres (offset `(16, 16)`, 32 apart); edges join 4-neighbours. Every obstacle is inflated by
  the real person: walls, table footprints and standing furniture by the feet rectangle and offset of
  `PixelPerson.footprint()`; Ground walls also by the whole canvas of `PixelPerson.drawing_rect(art.people)` (32 × 48,
  feet at `(16, 46)`), because a wall always draws behind a person, so the person's canvas must not reach into the
  wall's drawing band. A node is blocked when its centre lies inside an obstacle; an edge is blocked when the segment
  between two centres enters an obstacle. Touching an edge does not count (`Rect2.intersects()` excludes the edges).
  Checking edges and not only nodes is what stops a thin obstacle between two clear centres from being walked through
  (the native `AStarGrid2D` connects those; a test keeps this regression). **Every edge has the same length, so a
  breadth-first search finds the shortest routes.** A route is read off the search greedily: straight on while that is
  still a shortest way, otherwise turning in the order left, right, up, down (horizontal first, like the corridors),
  so nobody zigzags down a corridor.
- **Graph cache.** Floors reach 131,072 cells, and a walk must not flood-fill one. A graph is built once per plan and
  kept (`OfficeWalkGraph.of()`); the validator builds afresh every time and puts the result in the cache (a candidate
  plan may still change between validations), and the people fetch by plan identity the very graph the validator
  built. Searches reuse scratch arrays allocated once per graph plus a visit stamp; nothing floor-sized is allocated
  per route.
- **Obstacle entries.** A route may enter an obstacle only along the obstacle's own **entries** (`Obstacle.entries`,
  pairs of end points): a table's are the far seat legs that run into its footprint; the top wall's drawing
  clearance's is the threshold leg. When a segment is checked (`clear()`), the part of it inside an obstacle must lie
  wholly on one of that obstacle's entries. Entries are the legs of this plan, at this table's current place (a
  straightened route that merges with a leg counts the same way: only the part inside the obstacle matters). Nothing
  is exempt by tab name. The validator and the people use the same check, so every segment of every live route avoids
  every obstacle except through these entries (a test checks this every frame).
- **Lift door and threshold.** The door's foot `(door x, 84)` is inside the outer wall's drawing clearance (the entry
  band's first row is blocked; the first walkable centre is at y = 112). A fixed threshold leg runs straight down from
  the door's foot to the first walkable centre below it: the entry into the wall's *drawing* clearance, entering no
  solid obstacle. Routes in start with the door's foot and the threshold leg; routes out end with them. The validator
  checks reachability from the threshold leg's end (not the whole entry band, which would make "walking connectivity
  equals the validator's" true by construction) and checks the threshold leg itself. Reachability is the door's
  distance field: one whole-floor BFS from the threshold per graph (the validator builds it first). A route in is read
  back from the goal along it; a ghost's route out is read from its start along it; neither searches again.
- **The fixture row.** On a floor with fixtures, the fixture row from the left wall to the main corridor is one
  `FIXTURE` obstacle (a band of cell centres, not inflated by the person), and the counters' footprints, inflated by
  the feet, are `FIXTURE` too. No fixture-row centre and no edge along it is walkable, so no route runs along the
  fixture row. Its entries are each spot's leg (straight up from the walking lane, `leg_to_fixture()`) and the
  queue's step legs: neighbouring slots lie end to end and collinear, so the obstacle joins them into one entry from
  tail to head, and a shift of several slots also walks along the step legs. There is no entry between queue and
  pantry.
- **To and from the fixtures.** Every seat reaches the entry band's walking lane through the main corridor (at
  `(door x, 144)` on the left lane, or the cell beside the right lane). So a route to a fixture is: the person's own
  leg back to the approach point, the door's distance field up to the lane (`OfficeWalkGraph.to_lane()`), straight
  along the lane, then up the spot's leg. Back to a seat is the reverse (`from_lane()`); fixture to fixture is down to
  the lane, along it, and up again. No per-spot distance field and no search: someone coming in reads the door's field
  and passes along this lane anyway. (The queue's step legs are still in the graph; nobody walks them.)
- **The two legs.** A table gives each column and side one approach point (a cell centre); both legs start at the
  approach point's cell centre. The standing spot is dx 24, dy 26 from the approach point, and nobody walks
  diagonally. Far side: approach → seat is one straight segment into the table's footprint (rule 5), which is this
  table's entry; approach → standing spot is an L, first along the seat's column to the standing spot's depth, then
  across, with the corner on the seat leg. Near side: the chair is in the approach point's column, and a leg must not
  pass through the chair, so it first walks along the near walkway to the standing spot's column, up to the standing
  spot, and the seat leg then steps sideways into the seat (`leg_to_seat()` / `leg_to_standing()`; the near standing
  leg is the seat leg minus its last step). Nobody stops on a standing spot: going to the pantry and back uses the
  seat leg (the near one passing the standing cell to go round the chair). The validator still checks both legs of
  every column and side with the same check and reports each blocked leg separately.
- **Speed.** `max(96, route length / 6 s)` units per second, at most `TOP_SPEED` = 480 (5 × the walk strip's own
  speed, `WALK_SPEED` 96): every walk finishes within `LONGEST_WALK` (6 s); longer routes walk faster, never truncated
  or teleported. A route that would take longer than 6 s even at 480 (2880 units) is not walked: the person is placed
  at the goal. The walk strip (4 × 0.14 s) plays at a rate scaled with speed (`PixelPerson.pace()`, speed ÷ 96); a
  reroute never walks slower than before. Once a person stops walking (seated, standing still, placed, or set down on
  disconnect), the step rate returns to 1.
- **Presentation apart from observation (`OfficePresentation`, `scripts/world/`).** When an observation arrives (a
  `ZoneModel` laid on a `FloorPlan`), plates, status badges, wait times, selection frames and click areas jump to where
  it says at once (they are signals); the body then walks there. It is one floor-level model keyed by pane key plus
  terminal identity (`PaneModel.identity_key()`). Before reconcile it compares the last presented observation with this
  one: a body that is leaving is first taken out of its seat and hung under `Sorted` as a ghost (renamed, no overlay,
  no click area), so `vacate()`, `rebind()`, reuse and release cannot touch it. A body that stays with its seat
  (sitting down, coming in, going to the pantry and back, changing seats) remains that station's `Actor` and walks in
  the station's own coordinates (the station has y-sort on, so the body sorts by its own feet); the station leaves it
  alone while `walking` and places it on `land()`. A change of agent (both providers known and different) = leave +
  come in; the same provider with a new terminal or session walks nothing. Each observation that changes a body's goal
  bumps a generation; each route carries the generation and identity it started with and is dropped on mismatch, never
  landing in a stale pose. A pane that leaves while its body is still coming in turns that same body into a ghost; the
  same pane with the same identity returning while its ghost still walks takes the ghost back, so there is never a
  second body. Bodies are placed along the path every frame, not with `move_and_slide()` (the validator allows routes
  that graze furniture, where colliders would catch the feet; walls have no colliders). A frame's leftover distance
  carries past corners, so even at 8 frames per second while minimised, a dozen units per frame, nobody leaves the
  path.
- **Walking while the plan changes.** If the final leg did not move (the goal's leg for someone coming in, the
  threshold leg for a ghost) and the rest of the route is still clear in the new plan, the person carries on along the
  old route from where they are. Everyone else reroutes from where they are: someone standing inside an obstacle (not
  on its entry) is placed at the goal; otherwise **one** BFS from the goal's cell looks at once for the ends of the two
  ways back onto the graph (back along the old route and forward along it; someone seated or standing has only their
  own leg), stops when no cheaper end can still be reached, and reads the route off greedily. `route_between()` picks
  the end with the smaller total cost.
- **Routing budget.** Routing per observation is bounded graph work (`OfficePresentation.ROUTING_BUDGET` = 12000,
  counted by `OfficeWalkGraph.expanded`: nodes the BFS expands and nodes a route read-off passes both count). Cheapest
  first: people coming in (reading the door's field), ghosts (the same), then reroutes. Whoever the budget does not
  cover is placed at the goal, as on a cold start. The budget assumes about 0.5 µs per node on a development machine:
  the worst observation on the stress floor (one table widening the whole floor, 47 people walking) routes in under
  10 ms; the `ROUTING_BUDGET` line of `make test` prints the whole observation's handling time (including starting and
  placing).
- **Cold start.** A new floor view (first draw, floor change, theme change: the only paths that rebuild the world), a
  machine that was disconnected at the last presentation (the first snapshot after reconnecting already contains every
  change made meanwhile), or a layout problem at the last refresh (the floor was not updated then): everyone is placed
  at their goal, all ghosts are dropped, history is not replayed. Layout changes reconciled in place walk as usual.
- **Disconnect (AGENTS.md invariant 4).** All ghosts are dropped; walking people freeze where they are: position, walk
  animation, remaining route and time all stop (time counts only unfrozen delta). Observation changes during the
  disconnect are placed, not walked, and the first observation after recovery is cold. After recovery and until the
  first observation is presented (indefinitely, if the recovery snapshot's layout fails), walking people stay frozen.
  Walking people do not use `VisibleOnScreenEnabler2D`.
- **Ghost cap.** At most `OfficePresentation.MAX_GHOSTS` (32) at a time; beyond that the oldest disappears first.
  Ghosts are not counted in `OfficeDeskView.node_budget()`.
- **Closing a table's last pane** closes that tab: the table is released at once and ghosts walk out from where the
  table was. Closing a workspace's last pane is a floor change (cold), so nobody walks; the lobby has no stations, so
  nobody walks there.

## Seating and the chair asset boundary

- Sitting and standing are different tracks in the same pixel-people strip (`desk_*` / `stand_*`): same strip, same
  nodes. Measured over every frame: seated, the head reaches y = −31 above the feet (a blocked worker's raised hand
  −36); standing, the head spans −37..−25; every figure is x −8..8 (16 wide, ±12 with a raised hand). A hood is
  headwear that hides the hair layer while worn.
- `chair_front` / `chair_back` are one office chair from the front and from behind: armrests, a gas-lift column
  and casters, 17 wide over rows 24–45, at a person's scale (the far one mostly hides behind its seated worker).
  `CHAIR_OFFSET.near = 6` only keeps the front/back order; there is no large offset to dodge the person. Chairs
  belong to the table family and are density 2 like the floor (painted at 2x); geometry is in units and does not
  change with density.
- The preview keeps a capped bystander in a terra top in front of the API table as a regression check.

Pose and chair-back changes happen only in the art; the depth and foot-point rules do not change.

## Gates

Besides the client / machine / incremental-update tests, `tools/run_tests.sh` checks:

- Every node on a sort path has y-sort on, and no `z_index` is non-zero except `OVERLAY_Z`; every vertex of a lamp's
  light lies inside the surface rectangle.
- Laptops on both sides share x with the seated person and sit at their own table edge, not by the divider, including
  columns added by growth. A shell's `$_` view survives growth and rebinding; starting and done agents draw no shell
  mark.
- The thinned table edge meets the legs without a seam and the feet stay put; near lamp light never passes the
  working surface. In both themes the real opaque pixel envelopes of desk decor are read and checked for overlap with
  surface clearances and each other; a fixed-identity rebuild, growth and shrink, equipment state and theme changes
  leave existing placements unchanged.
- Shell bricks are all under `Ground`, standing furniture all under `Sorted`; each piece's position is unchanged
  across state changes and intersects no seat's click area, table footprint or walkway band.
- In every occupied column: far chair y < far person y < table y < near person y < near chair y.
- A person is always the pixel-people family's six layers + one `AnimationPlayer`, no chest badge; all layers show the
  same `frame` at every moment; state changes, sitting / standing and re-dressing never replace nodes. Far people face
  the viewer; near people show their backs.
- Plate text and badges never cover any real pixel of any frame of the person; the far rows stack plate over lens
  over badge over the head (or raised hand), the near ones badge, lens, plate below the chair; the seat mark encloses
  the whole person. The chip covers neither the person (raised hand included) nor the plate text, and the badge is
  drawn over it in its left half, clear of the wait; on pods of 2 to 12 desks, the chips and their click rectangles on
  both sides of every column intersect no seat click area and no other chip. Two rows at the 192 pitch (and a pod
  across a passage cell) never meet, at every pulse lift, with and without a wait, with and without the lens; the
  near badge shares no texel with the near chair at the −2 lift. The paper stack is right of the laptop and clear of
  it, clear of its own and the next column's blocked worker, with its opaque pixels on its side's working plane, the
  last column included. The far laptop covers no pixel of the far worker. The compact duration is at most 14 wide in
  the chip and 18 in the lens row, measured on the Label once the face is on. A pointer over a seat shows only its
  plate.
- A standing person walking into a table is stopped by its footprint collider; a seated person's feet collider is
  off.
- The entry band is three cells deep; fixtures appear only on floors with tables, at positions that are a pure
  function of plan geometry (stable under growth and widening); a narrow band drops the pantry first, then both; the
  validator reports blocked queue legs and unreachable approach points separately. No edge runs along the fixture row;
  `route_between()` picks the cheaper end (compared against a reference BFS every time); an entry can only be used
  along its own length.
- No walk-graph node is inside an obstacle and no edge enters one (including a thin obstacle between two clear
  centres); validator and people share one graph, starting from the threshold's end; on stress floors (20 and 32 cells
  wide) and after growth every approach point is reachable; each blocked leg is reported on its own, and no near leg
  passes the chair's column.
- Coming in, going out (ghost), to the pantry and back (seat leg), changing seat or table, turning back and taking a
  ghost back all keep the same body; a new agent walks out and in, a new session walks nothing. Cold start, freezing on
  disconnect (position and frame asserted every frame) with a cold recovery, staying frozen when the layout fails after
  reconnect, rerouting, placing someone who stands inside a wall or table, not leaving the path at 8 fps, no walk on a
  stress floor needing a teleport or exceeding 480 units per second, the ghost cap, clicks on a ghost or an empty seat
  selecting nothing, and people walking between two tables sorting by their feet. Before comparing with a rebuild, a
  test first proves someone is walking and that the walking picture differs from the settled one, then calls
  `settle()`.
- Routes a plan change does not touch carry on unchanged; each reroute is one search per person; routing stays within
  budget, and whoever is over it is placed where they belong with step rate 1. A fixed-seed lifecycle fuzz test
  (observations, disconnects, theme changes, random walking) checks at every step: body count, no `walking` without a
  route, still people where they belong, step rate 1, frozen people not moving, every live route entering obstacles
  only through entries.
- `rest_of()` returns only the seat or the pantry. Done and blocked sit and never walk (done has the paper stack,
  blocked a raised hand and chip; starting agents and shells have neither). Idle agents walk to the pantry and play
  `drink`, and sit down when it is full; moving from one rest to another starts from where they rest; when a pantry
  resident's tab closes, the ghost walks out of the pantry. A new session reorders the pantry from that moment, and an
  agent that just finished starting does not push anyone out. Cold starts place directly. The pantry is not reordered
  while disconnected (not by clicks, `N`, or refreshes caused by another machine's snapshot). A pantry resident and the
  seat they left both select the pane; the counters do not. Pantry residents stand in front of the pantry counter, and
  people on the walkway in front of them (sorted by feet). A click on the chip (real input) selects and enters
  answer mode; a click on the seat only selects (far and near). Chip and paper stack only toggle `visible` in place and match a
  rebuild node by node. Every standing spot (tables 160 to 416 wide, every column, both sides) is outside the table
  footprint and all standing furniture, and the far standing spot is beyond the far edge.
- Illegal widths (e.g. 240, or 32 under the minimum) are rejected, repeated setup adds no nodes; growth keeps seats
  and equipment, and rebinding never accumulates seat or chip click-area offsets.
- The planner covers empty floors, empty tabs, missing and conflicting layout, stable seats, gap reuse, oversized
  tables, budget rejection and fixed-seed incremental sequences.
- Geometry tests read each real Sprite / Label envelope, check that everything stationary (badges at every lift, chips,
  seat marks) stays inside the measured range (`render_rect`; the plate and lens rows are transient and pinned by the
  cross-row case), and verify moved stations through real input: a seat click emits `picked`, a chip click `asked`.

Screenshots remain part of visual acceptance and must actually be opened and looked at; use the capture target in the
Makefile, never a headless capture. The preview keeps one bystander standing behind a table and one in front of it,
proving that sorting depends only on position; it also has one done person seated on each side with a stack of paper
on the pod (one on the last desk), and blocked people with a raised hand and a chip, one with no wait (badge only).
