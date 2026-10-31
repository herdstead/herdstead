# Herdstead world model: workstations, space, objects and picking

The office world is built only from Godot's own systems. There is no custom depth contract, render-pass table or
occlusion texture: who covers whom follows from position, never from numbers tuned against a screenshot.

The production office uses one generic **complete workstation image** per station (`WorkstationActor`): person,
chair, desk and twin monitors are already painted together. Every station faces front; `far` and `near` mean only
the upper and lower logical rows. The family is density 2, nearest, with an 80×80-unit canvas and pivot (37.5, 70).
There is no runtime rig, customization, separate equipment, walking or ghost lifecycle in this phase. The HUD uses
the same family's generic portrait. `PixelPeople`, `PixelPortraits` and `TablePack` remain legacy authoring tools,
not the production office's drawing path; their contracts remain in [the asset spec](ASSET_SPEC.md).

## Abandoned approaches

These were tried and dropped as a whole. Do not bring them back under any name.

| Approach | Why it is gone |
|---|---|
| A depth contract: a spatial_contract.json file + `TableSpace` + 12 `z_index` passes + occlusion layers | Depth came from tuned numbers, not position. It put a person sitting on the near side of a table behind the table's occlusion layer, although someone closer to the viewer than a table cannot be hidden by it. |
| `AvatarRig` syncing six `AnimatedSprite2D` every frame | Per-frame sync code lets layers drift a frame apart. Production now keys one complete-image Sprite with one `AnimationPlayer` (rule 6). |
| A hand-kept table of hit rectangles in `office.gd` (screen + pan − origin arithmetic) | The engine's physics picking does it (see "Picking and camera framing"). |
| The native `AStarGrid2D` for walking | It walked through a thin obstacle between two clear cell centres. The later edge-checked walk graph and walking presentation are also retired from production: stationary workstations need neither routes nor actor-clearance policy. |

## Six rules

1. **Origin = foot point.** A workstation's origin is its authored pivot, shared by all its frames and its empty
   image. Standing furniture keeps its own foot point. The logical pod's origin is the left end of the lower row's feet.
2. **Depth comes only from Y-sort.** Every `Node2D` on the path from the sort root to a sorted entity has
   `y_sort_enabled = true` (nested y-sort merges into one sort group). Larger y is closer to the viewer and draws later.
3. **`z_index` has one use.** The floor is not a z value but a sibling drawn before the sort root. UI floating over
   the world (name plates, status badges, selection frames, table frames) uses the one named constant
   `OfficeWorld.OVERLAY_Z` (10). No other `z_index` is allowed: `z_index` beats Y-sort, so every extra z value is one
   more place where the position rule stops holding.
4. **A workstation is indivisible art.** Its internal person/furniture occlusion is painted, not assembled by
   nodes. The station sorts as one whole at its foot point. `OfficeTable` owns only the pod's seat markers and
   selection outline; it draws no second desk, chair, monitor, lamp or state item. Separate side-table decor remains
   a child of that side table, never of a workstation.
5. **Every workstation stays at its measured seat.** Arrival, removal and relocation reconcile directly, without
   walking, standing spots, approach points or body collisions. A permanent actor draws the empty workstation for
   both a shell pane and a vacant slot; only the shell is pickable and has pane annotations. Herdr focus is a thin
   underline, distinct from the selection outline: `OfficeStation.LIGHT_ALPHA` is `[0.0, 0.15, 0.35, 1.0]` for
   `OfficeTable.Lamp.OFF / DIM / ON / FOCUS`. `OfficeFloorView.lamp_of()` chooses the level from herdr's focus and
   active tab; a weaker underline never dims the person like a lost connection.
6. **One `AnimationPlayer` per workstation.** `WorkstationArt` builds discrete keys on `Body:frame`; each frame is
   a complete image. Working and idle loop, blocked enters then holds its looping wait and exits before the next
   state, and done nods once. Starting and unknown hold frame 0. Repeating the same state does not restart its
   animation, including a completed done nod. Pausing is separate from state selection, so reconnecting cannot
   replay the nod. Frame order and timing come from the approved manifest, not the old rig's state mapping.

## Prefabs

| Scene | Root | Role |
|---|---|---|
| `scenes/world/workstation_actor.tscn` | `Node2D` | One retained `Body` Sprite and one `AnimationPlayer`. `configure()` dresses the shared `WorkstationArt`; `play_state()` handles the approved state transitions; `show_empty()` uses the separate empty image with the same pivot; `pause()` / `play()` preserve the clock. No rig, recolouring or runtime compositing. |
| `scenes/world/table.tscn` | `Node2D` | A tab's logical pod: `Seats` markers and an `Overlay/Frame` with four bars. `measure()` is the sole producer of `DeskMeasure`; `setup()` accepts only its canonical width and columns; `resize()` / `relocate()` retain surviving markers and selection. **All pod geometry constants live in `scripts/world/table.gd`.** No furniture sprites or footprint collider. |
| `scenes/world/station.tscn` | `Node2D` | One complete `Actor`, the focus underline, `Overlay` and `Target`. The overlay holds the name plate, lens line, a `Line2D` selection outline, status badge and blocked chip. The 30×16 chip shows the same badge in its left half and a compact wait in its right; without a known wait it draws no frame or text, leaves the badge centred, and retains its click area. The question excerpt is the HUD's `%WorldTip`. `Target` is an `Area2D` with one 80×80 seat rectangle and a separate 30×18 chip rectangle; a chip release emits `asked`, a seat release `picked`. Both rows use identical offsets. Every slot has a permanent actor, even when vacant; a vacant slot draws the empty workstation and cannot be clicked. `rebind()` moves the whole station to its new marker without replacing the actor or its animation. No world provider mark is drawn. |
| `scenes/world/decor.tscn` | `StaticBody2D` | One standing piece of furniture (plant, side table, and the entry band's pantry counter): a `Sprite2D` placed on its foot point plus a footprint on the `FURNITURE` layer, and a `%Top` holder for what a side table carries (`hold()`, `held()`, `TOP_Y`). Footprint sizes come from each piece's `item` block in the pack (`OfficeDecor.footprint_of()`, including the two counters; [ITEMS](ITEMS.md)). **Furniture binds no herdr field**; its position comes only from the floor layout. |
| `scenes/world/chip.tscn` | `Node2D` | The blocked chip inside a station's `Overlay` (`OfficeChip`): the `panel` frame and the wait's Label, both the scene's; `show_wait()`, `clear()`, `set_lensed()` and `framed()` only change their properties. It holds no button: a click on it is the station's. |
| `scenes/world/machine_plate.tscn` | `Control` | The machine plate over the map (`OfficeMachinePlate`): the machine's name, its live state or an empty map's note, its space and pane counts, and the layout problem line; Labels in containers styled by `HudTheme`, never clickable. |
| `scenes/world/zone_sign.tscn` | `Node2D` | A zone's sign (`OfficeZoneSign`): a `panel`, the workspace's number and label and an accent stripe over the aisle row, its origin the zone's top-left partition post's foot; an `Area2D` on `PICKABLE` (`Hover`) emits `hovered(zone_key, inside)`. Display only: its text is written on every reconcile. |

Floor assembly:

```text
FloorRooms              the node dimmed as a whole when its machine disconnects
├── Ground              in this order: the shell (floor TileMapLayer, corridors, walls, framed pictures on the top
│                       wall), the zones' carpets (`Carpets`, one NinePatchRect per zone), then each pod's
│                       background: the lens's wash and tab label (drawn first)
└── Sorted (y-sort)     tables, stations, standing furniture, the entry band's pantry, each zone's partitions (a
                        y-sorted holder) and sign; each complete workstation sorts at its station's foot point
```

### Grid, measurement and stable ordering

A map (`MapModel`: one or more workspaces, each a `ZoneModel`) is laid out by `OfficeFloorLayout` into a
`FloorPlan`; `OfficeZoneLayout` lays out one zone's pod rows and `OfficeSeatPlanner` one tab's seats. `ZoneModel` /
`RoomModel` / `PaneModel` hold no render nodes; `FloorPlan` / `ZonePlacement` / `RowPlan` / `DeskPlacement` /
`SeatPlacement` hold grid bounds, table origins and seat bindings; `OfficeFloorView` / `OfficeDeskView` assemble nodes
from the plan. The office draws **one map per machine** (`BuildingModel.map`, `MapModel.of_zones()` under the machine's
key): every workspace of the machine is a zone on it, planned, drawn and panned as one world.

A machine with no workspace has an **empty map** (`MapModel.empty()`), with no zone at all (the lobby is retired). It
goes through the same planning, furnishing and assembly path as any map (outer walls, door, windows, walkways; no
desk, so no pantry), places nothing herdr gives, and is in the layout diagnostics like any map (`layout_plan()`,
`layout_problems()`, `layout_attempt_count()`). Its notices (offline, waiting, ssh error) are on the machine plate.
Workspaces arriving later are zones placed on that same map (its first plan fixed its width). An empty workspace is a
zone of one empty pod row.

The grid is fixed at **32 world units**. **The map is lanes** (`FloorLayoutPolicy`): across it a side wall (1 cell),
`lanes` lanes of `zone_width_cells` (4) with an aisle column (`lane_aisle_cells`, 1) between two of them, the main
corridor (2) and the other side wall: **5L + 3 cells** for L lanes; lane i covers columns 1 + 5i to 4 + 5i, the
aisle after it is column 5 + 5i, and the main corridor is columns 5L and 5L + 1. The narrowest pod (2 columns,
7 reserved cells) spans two lanes, right of its zone's pad. Down it: the top wall (2 cells),
the entry band (1, also the first zones' aisle row), then the zones from row 3. A map's first plan picks L = max(2, ⌊(width − 3) / 5⌋) from the
viewport width available at that moment (the default 1920×960 window at 2x: 936 units, 29 cells: five lanes, 28 cells);
after that, window or zoom changes only change how much is visible, and nothing reflows. L is raised only when a zone
needs more lanes than the map has. Never fewer than two lanes (13 cells): the smallest window (480×320 units) keeps the
top wall's window and its picture.

**A zone** (a workspace, `ZonePlacement`) stands in k adjacent lanes under an **aisle row** of its own
(`zone_aisle_cells`, 1; the first zones' aisle row is row 2, the entry band: `map_top_aisle_cells` 0,
S3 BAND): it is 5k − 1 cells wide
(the aisle columns between its lanes are its own) and whole **pod rows** deep; its **slot** is its aisle row and its
rectangle. Inside it a pad column (`zone_pad_left_cells`, 1) keeps its tables off its left partition; the rows are as
deep as a table's measured reservation (`OfficeZoneLayout.pod_row_cells()`, 10 cells), with no
walls and no cross corridors between them. **Lane span**: the fewest lanes whose 5k − 2 inner cells hold its widest
table reservation (for a reservation w cells wide, ⌈(w + 2) / 5⌉; a pod of c columns reserves 3c + 1 cells and needs
⌈(3c + 3) / 5⌉ lanes); on its first placement a
zone takes more lanes, up to the map's, while it would stand taller than `zone_tall_rows` (1) pod row: a new zone is as
wide as its pods need to stand in one row, and wraps rows only at the map's lanes. A placed zone keeps its width as it
grows (down, or right when a table is too wide for it).

**Placement is a masonry that only grows, down or right** (`OfficeFloorLayout._place()`), zones taken in (number,
key) order:

0. the map widens first, once, to the most lanes any zone needs, retained or new (`OfficeFloorLayout.final_lanes()`;
   lanes are appended on the right; the main corridor and the lift door move right; the pantry stays), so every
   decision below is taken against the final width (widened zone by zone, a zone judged against the narrower map
   moved although its own place fit the map a later zone widened);
1. every retained zone holds its slot;
2. a retained zone that must grow (taller, or wider by any number of lanes) grows in place when the cells it grows
   over, down and right, aisle row included, are free of every held slot (the ones grown earlier in the pass
   included); otherwise it alone releases its slot and moves;
3. the zones that move and the new ones, in order, take the **top-most, then left-most** gap their whole slot fits in
   over k adjacent lanes (zones from row 3, their slots from row 2); a new mezzanine first tries directly below its source's slot, in the same
   lanes; only on its first placement (grouping is display, never in the geometry signature, so a group forming or
   breaking later moves nothing).

The work is bounded before it is done: an empty workspace (one empty pod row) is charged to `max_tables` like a table;
a map whose slots cannot fit the dimensional budget even packed lane by lane (as deep as the entry band plus the
slots' lane rows, k·t for a slot k lanes wide and t rows tall, spread over the final lanes) is refused before any
placement (`_cannot_fit()`); and a first-fit search, over a per-lane index of the rows the placed slots take (a
binary search, not a scan of every slot), stops at the first top whose slot would end past `max_height_cells`. A
refusal names `map exceeds width, height or cell budget` and keeps the previous map (the plan cache's atomic
fallback).

Inside a zone the row allocator is today's: next-fit on the zone's first layout, gap reuse afterwards, growth
left-anchored, a table wider than the zone first was taking a row of its own (and widening the zone by lanes), rows
never shrinking. **The map keeps its largest extents**: its width is 5L + 3, its height the larger of the last plan's
and the lowest slot's bottom (at least `min_height_cells`, 9). Removing a zone leaves a gap a later zone may take;
removing the last or lowest zone, or emptying a lane, never shrinks the map. The keep-outs (`FloorPlan.aisles`, drawn
as plain floor) are every zone's aisle row and every inter-lane aisle column where no zone spans both lanes; no
reservation, zone or furniture stands on them or on a walkway.

`OfficeTable.measure(capacity) -> DeskMeasure` is the only source of pod geometry. A tab has two logical rows of
complete workstations, **both facing front**, on a 96-unit column pitch. Coordinates are relative to the pod's
origin at the left end of the lower row's feet. `FloorLayoutPolicy.version` is 6 for this geometry.

| Measure | Value / rule |
|---|---|
| Capacity and width | `capacity` is at least 2 and counts columns, each with two workstations; the planner grows it 2 columns at a time and keeps old capacity. Width is `max(2, capacity) × 96` (`MODULE` 96, `MIN_WIDTH` 192) |
| Column x | `48 + 96 × i`; growth never re-centres existing columns |
| Seats | far `(x, -128)`, near `(x, 0)`; row names never select a different facing |
| Complete-image canvas | `(-37.5, -70, 80, 80)` relative to either seat; 160×160 texture pixels at density 2. Far pod y [−198, −118), near [−70, 10) |
| `physical_rect` | `(0, -198, width, 208)`: y [−198, 10), the two image rows' bounding envelope, not a desktop collider |
| `render_rect` | `(0, -200, width, 256)`: y [−200, 56), enclosing the supported stationary images and annotations, including plate and lens rows |
| `reserved_rect` | `(0, -224, width + 32, 320)`: ten cells deep, with a one-cell passage on the right; bottom edge 96 |
| Pod selection frame | Two-unit bars outside `render_rect` (`FRAME_OUTSIDE` 2): top [−202, −200), bottom [56, 58), sides x [−2, 0) and [width, width + 2) |
| Tab label | The pod's width × 8 at y [60, 68), four units below `render_rect.end.y`, clear of the selection frame |

There are no separately placed laptops, desk items, provider marks, chairs, standing spots or approach points in
this measure. No trinket, cat or rug belongs to a pod; the furniture painted into a workstation is not an attachment
point for another prop.

#### Rows over a seat

Both logical rows put their annotations **below the complete image**, using the same station-local offsets.
The chip and lens row are 30 units wide; the name plate is 94, leaving 2 between occupied neighbours at the 96-unit
pitch. The badge's pulse (`OfficeAttention.PULSES`) lifts it by 0, −1 or −2. Coordinates below are half-open pod y
ranges except the selection line, whose centreline is stated explicitly.

The lens line and plate stand on a **paper tag**: the Label's own `normal` stylebox (`OfficeDraw.back_label()`:
`paper`, square, no antialiasing or margins), laid by `OfficeDraw.hug()` as wide as the text plus `TAG_PAD` (1)
on either side, at most its row's width. The plate stays centred on its column as far as its widened row allows;
a longer name is ellipsized. An empty label draws no tag. The display face at 8 uses a 10-unit plate row
(`OfficeDraw.PLATE_HEIGHT`, `plate_cut()`); compact waits use the figures face at 8.

| Row | Far (feet −128) | Near (feet 0) |
|---|---|---|
| Badge (`BADGE_AT` (0, 28), 16×16 canvas, pivot (8, 16)) | [−116, −100); pulse envelope [−118, −100) | [12, 28); pulse envelope [10, 28) |
| Chip (`CHIP_AT` (−15, 12), 30×16) | [−116, −100) | [12, 28) |
| Lens (`LENS_AT` (−15, 30), 30×12) | [−98, −86) | [30, 42) |
| Plate at rest (`PLATE_REST` (−47, 32), 94×10) | [−96, −86) | [32, 42) |
| Plate with `L` held (`PLATE_AT` (−47, 44)) | [−84, −74) | [44, 54) |
| Seat click rectangle (the full image canvas) | [−198, −118) | [−70, 10) |
| Tag-row click rectangle (badge or chip; 30×18, centre (0, 19) from the seat) | [−118, −100) | [10, 28) |
| Seat selection outline (1-unit `Line2D`, centreline x −36..41) | centreline y −197..−119 | centreline y −69..9 |
| Focus underline (`Focus`, x [−28, 34), 1 unit tall) | [−124, −123) | [4, 5) |
| Stable signal rectangle (camera and pointer; x [−47, 47)) | [−198, −74) | [−70, 54) |

The chip's wait label is x [0, 14) relative to the seat, y 2..14 within the chip. While framed, the same badge
moves −8.5 in x (`CHIP_BADGE_SHIFT`); without a known wait, or under the lens, it is centred again. The chip's
click rectangle touches but never overlaps the image's click rectangle; the seat rectangle does not change shape
when blocked. The tag row stays pickable wherever a badge is visible: a non-blocked badge only selects, while a
blocked chip requests answer mode. A shell or vacancy has neither and disables this target. If the state changes
under a still pointer, the tooltip switches between the pane's name/state and the question. The selection line is
separate from the focus underline and from the pod frame.

**Plates on a map with few seats** (S3 SEATTAGS, the user's Q-U2): a map whose occupied seats (every pane on it, agents
and shells: both carry a plate; `MapModel.pane_count()`) number at most `FloorLayoutPolicy.FEW_SEATS` (16) shows every
seat's plate at all times; above it, today's rule. `OfficeFloorView.few_seats()` decides it, per machine map, and the
floor tells every station on each refresh (`show_plates_always()`, which does something only on a change).
**A plate beside a vacant seat** takes that seat's slot too (`OfficeFloorView.widen_plates()`, per pod, on each
refresh): on the same side of the same pod, a vacant slot goes to the seat on its left when that one holds a pane,
else to the one on its right, so no slot is given twice. The row then reaches `PLATE_REACH` (96, the column pitch)
into it: [−47, 143) about its column with the right neighbour's slot, [−143, 47) with the left's, [−95, 95) with both
(190 wide at most), 10 tall. The tag still hugs its name and sits centred on its own column as far as the row lets it,
so a short name does not move and a long one keeps its start over its own worker; the next seat's row starts 2 units
past the slot. A vacant slot draws no annotation and has no enabled click target. The rows stay at the same y;
a widened plate never leaves its pod's columns.

The far plate under the lens ends at −74, four units before the near image begins at −70. At the 320-unit pod-row
pitch, the next row's render envelope begins at 120, after this row's tab label ends at 68. These are envelopes
from the layout constants, not measurements of opaque artwork.

The planner rounds `reserved_rect` outward to a grid reservation and derives the pod origin from that;
`office.gd` never copies width, column pitch or seat offsets. Seat nodes come from `table.seat(column, side)`.
`setup()` rejects non-finite numbers, widths below 192 or not divisible by 96, and columns that differ from
`measure()` for that capacity. The plate, lens and chip Labels are sized again after applying their face.

Below the top outer wall is a **32-unit entry band** of one cell row (`entry_cells` 1), also the first zones'
aisle row, where their signs hang. The main corridor on the right is 64 wide, and each side outer wall takes 32.
A map of one zone of one pod row is therefore 2 + 1 + 10 = 13 cells deep; an empty map stays at the policy minimum
of 9. The corridor and passage reservations remain spatial structure, not promises of walking routes.

`FloorPlan.floor_cells` is the one half-open integer rectangle. The base floor covers every cell of it, including
under walls, in lane gaps and in gaps left by deletions; walkways draw over that full floor. Each zone's carpet
(`OfficeShell.carpet_rect()`) lies over the floor inside its partitions and under its pods; no carpet reaches an aisle
row, an aisle column or a corridor. The total
drawing extent comes from the plan and the machine plate together; the camera never guesses bounds with stray `ceil()`
or margins.

### Shell and joints

A map's walls are drawn on one `TileMapLayer` at `Ground/Shell/Walls`; every cell ends up with exactly one semantic
ID. The top outer wall uses two courses, `wall.cap_left/center/right` and `wall.face_left/center/right`; side walls run
from top to bottom. **There are no row walls**: a zone is bounded by low partitions, not walls, so the row walls'
joints (`wall.cap_t_left / face_t_left`, `wall.cap_end_right / face_end_right`) are in no contract and laid nowhere. Only this rectangular shell is supported; it is not a general wall-network generator.

**The apron.** Past its side walls the shell carries plain wood floor (`Ground/Shell/Apron`, a `TileMapLayer` under the
floor's own), from the screen's left edge to its right one and as deep as the floor, so the HUD's side panels float
over floor rather than over the backdrop (`OfficeFloorView.apron_cells()` from the camera's room and the screen;
`set_apron()` only refills its cells). It is drawn only: no wall, walkway or furniture, never in the plan's cells, the
seats' clicks or the camera's reach. Below and beyond the floor's depth the backdrop stays.

Cap plus face make a 64-unit drawing band on Ground, behind the sorted workstations and furniture. Bricks are placed with
`set_cell()` by semantic ID; no Terrain autotiling, and no `TileMapPattern` deciding where walls and openings go.
Walkway tiles are laid on the corridors only (the entry band and the main corridor); lane aisles and aisle rows are
plain wood.

The top outer wall carries the lift door, the windows and the framed pictures. The lift door is directly over the
main corridor's left lane (`OfficeShell.door()`, its x a cell centre), so it moves right when the map widens; windows
keep `WINDOW_CLEARANCE` (64) from it. A picture hangs centred in every second gap between two neighbouring windows
(`OfficeShell.frames()`: the second, the fourth, ...), foot at `FRAME_FOOT` (48), where it, grown by `FRAME_GAP` (8),
clears every window, the door, the pantry counter and the wall's end cells: one at 23 cells, five at 53. Pictures are
drawn in the shell and have no footprint; the shell's key includes them, so a widening that
moves the door and the windows redraws the shell. The pantry's `COFFEE` sign hangs the same way, centred over the
counter's drawing with its foot at `SIGN_FOOT` (32) (`OfficeShell.pantry_sign()`): on the cream face, its hangers from
the face's top (`FACE_TOP`, 12), 5 above the coffee machine on the counter (opaque to opaque; at least 4 is pinned by
`tools/test_office_service.gd`), no wider than the counter, and among `OfficeShell.wall_covers()`, so no picture or
top-run plant comes near it.

**Partitions.** Each zone stands inside low cream partitions, a U open at the top (`OfficeShell.partition_pieces()`):
`partition_v` (6 × 32, foot (3, 32)) down each side at x0 + 3 and x1 − 3, one per cell row but the last;
`partition_corner_bl / _br` (32 × 32, foot (16, 32)) at the bottom corners; `partition_h` (32 × 10, foot (16, 10)) at
each cell centre between them along the bottom edge; and `partition_post` (6 × 12, foot (3, 12)) at each top corner,
its foot `POST_FOOT` (6) below the zone's top, where it covers the side run's top end (the art lane's mock). They are
Sorted sprites placed by id (`OfficeDraw.prop()`), in a y-sorted holder per zone (so each sorts by its own foot), made
again only when the zone's rectangle changes; they have no collider and no item block. Inside them lies the zone's
**carpet** (`OfficeShell.carpet_rect()`: the
zone's `bounds()` inset by `PARTITION_THICKNESS` on the left, right and bottom, the top at the zone's top, so it runs
under the posts and stops at the aisle row): one `NinePatchRect` per zone in `Ground/Carpets` (after `Shell`, before
the pods' backgrounds), dressed like the panel (`OfficeDraw.dress_nine_patch()`: the art's own pixels at its margins,
only the flat middle stretched), in its worktree group's family (`OfficeZoneSign.carpet_of()`, the sign's
`accent_of()` index), resized in place when the zone's rectangle changes, its texture set again only
when the family changes. No collider or footprint. The lens dims it with the
furnishing; the pod's wash lies over it. A one-lane empty zone (4 cells) carries a 116-unit carpet; the narrowest
zone holding a pod spans two lanes and carries 276. The bottom run draws at [y1 − 10, y1), 18 units under the last pod row's tab
labels, which end at y1 − 28: a tab label is `OfficeDraw.TAB_LABEL_HEIGHT` (8)
deep (`tab_face` gives up the display
face's lowest descent row; the labels are upper case).
The zone's **sign** (`scenes/world/zone_sign.tscn`) hangs from the top-left post, at its foot, and draws over the aisle
row at zone y − 14 .. + 2 (S3 BAND: 4 lower than before, its foot 2 over the zone's top, so the first zone's board keeps
4 clear of the pantry counter's front in the entry band over it; pinned by `tools/test_office_service.gd`): a `panel`, the workspace's number (a mezzanine's `3A`), its label and a 3-unit accent stripe
(the worktree group's, `OfficeZoneSign.accent_of()`). The panel is as wide as what it says
(`PAD` 4, the stripe, `GAP` 3, the number, `GAP`, the label, `PAD`), at most `MAX_WIDTH` (160) and never past the drawn
left edge of the zone's top-right post (`OfficeShell.right_post()`), the label cut with a forced ellipsis to fit; its
hover area is the drawn panel. Hovering it names the repository and checkout in the tooltip panel (`%WorldTip`). Its
text is written in the pen's display face (`OfficeDraw.display`: the pixel font over the system fallbacks, so a CJK label
is drawn); text and width follow the zone's model on every reconcile; the plan only positions it.

**There is no front wall**: `wall.front_*` and `wall.threshold` stay unused, because a wall at the near edge would
cover the nearest workstations. The door is outer-wall furniture: it does not open and no workstation enters or
leaves through it.

The shell, the partitions, the signs, the plants and the side tables are **furniture**: they do not change with agent
state, focus, selection or connection. Structural changes (a tab opened or closed, a table grown, a zone moved) may
move them; furniture has no herdr data behind it and does not stand for repos or agent counts. Standing furniture is
optional: its drawing, grown by `WALL_RUN_GAP` (8), must not cover a pod, a zone's slot (its partitions, posts and
sign; for the top-wall run every zone's rectangle and sign: its drawing reaches over the entry band's top, the first
zones' aisle row, but never down to a sign), the door, a window, a picture or the pantry counter; its footprint must not
intrude on a walkway or aisle (`OfficeFloorValidation.walkways()`: the entry band's last row, the main
corridor and every aisle). Validation checks furniture footprints and drawing envelopes against the measured
workstations, not entrance-to-seat reachability. If it does not fit, it is left out. Its candidates (`OfficeDecorPlanner`), keyed by grid step, never by tab,
zone or state:

- **the top-wall run**: plants `top/%03d` at the top wall's foot (foot y `TOP_RUN_FOOT` 64, the wall's foot line: the
  footprint in the wall's cells, the drawing over its face),
  `TOP_RUN_PITCH` (160) apart from `TOP_RUN_FROM` (72), the plant of its step (`plant_at(step)`); a step whose plant
  would meet the door, a window, a picture or the pantry counter stands empty (at 23 cells one stands, at 232). The
  grid meets a window gap only at some widths (it does at 23, 33, 43, 53 and 63 cells, never at 5L + 3 with L odd, nor
  at 13): where no step stands a plant, one stands in the first window gap that takes it (`OfficeShell.window_gaps()`:
  the middle of every gap between neighbouring windows that hangs no picture), keyed `top/w%02d` by the gap, the plant
  `plant_at(gap)`; placed by the width alone, so every map's top wall stands at least one plant (13 cells: at 200; 18,
  38, 58: 216; 28, 48: 248);
- **lane gaps**: every run of at least `LANE_GAP_MIN_CELLS` (3) free cell rows inside a lane, outside every zone's
  slot and down to the map's bottom (`OfficeDecorPlanner.lane_gaps()`), stands a piece every `LANE_GAP_STEP_CELLS` (2)
  rows from its second row, in the lane's middle column, foot `LANE_GAP_FOOT` (8) above its row's bottom, keyed
  `%02d/gap/%04d` (lane, row); pieces take turns by their number j along the run: `plant_at(j / 2)` for an even j (so its plants take turns too), a
  `side_table` for an odd one. A side table carries one piece (`DecorPlacement.item`) from the `desk` pool or, on
  28% of keys, the `cat` pool, picked by `OfficeDecorPlanner.side_table_item()` from a stream seeded by the placement
  key alone; `OfficeDecor.hold()` stands it in the piece's `%Top` at `OfficeDecor.TOP_Y` (−20), and the candidate's
  drawing covers both. A zone growing elsewhere moves none of a gap's
  pieces; one growing into a lane's gap re-keys that lane's pieces only.

Which plant image stands at a place comes from `OfficeDecorPlanner.plant_at(index)` alone (the pack's plants in turn:
with two, even places `plant`, odd `plant_b`). `OfficeFloorLayout.plan()` places the pantry, then the furniture, before
the one validation a candidate plan gets (see "Entry-band fixtures" for what it drops when that fails). Furniture never
moves a table group. The wall-front and floor position constants (door, windows, pictures, partitions, furniture feet)
all live in `OfficeShell`, so planning and drawing read the same numbers. Standing furniture stays a direct child of
`Sorted`; each pod's lens wash and tab label belong under Ground. Stations must remain separate Sorted children:
the logical pod must not flatten the two rows into one sort position.

### Entry-band fixtures

One counter stands against the top wall in the entry band: the **pantry** at the band's left end (`FloorPlan.pantry`,
typed `FixturePlacement`, planned by `OfficeFixturePlanner` in `scripts/layout/`, drawn by `decor.tscn` as an ordinary
`OfficeDecor`). **There is no reception.** The pantry is not a furniture candidate: for the furniture rules the entry
band is a walkway, and the counter stands in it on purpose. **It is a corner nook, furniture only** (D2, 2026-10-27):
nobody goes to it, and it has no occupancy spots or agent-state meaning.

Only maps with at least one desk have it. Every position is a pure function of the plan's geometry. The counter's left
edge touches the left outer wall; it meets the floor at y = 78 (`COUNTER_FOOT` = 14 from the band's top), its
footprint 64..78, from the wall's foot line: against the wall, its coffee machine over the face (5 under the `COFFEE`
sign) and its front 4 above the first zone's sign board (both gaps opaque to opaque, pinned by
`tools/test_office_service.gd`). Its footprint and drawing remain layout inputs; no actor's feet inflate them.

- **The counter must fit its bay**: a band shallower than one corridor row, or
  one whose bay left of the main corridor is narrower than the counter (64), has none;
  no real map is so narrow. When the map widens, the lift door moves with the main corridor; the counter stays.
- **Windows** (`OfficeShell.window_xs()`, a pure function; the floor view only draws what it returns): on a map with a
  pantry, windows are `WINDOW_SPACING` (128) apart, centred on the top wall between the pantry's right drawing edge and
  `WINDOW_CLEARANCE` short of the lift door, as many as fit with equal margins at both ends (2 / 4 / 12 at 13 / 23 / 53
  cells). Maps without a pantry (an empty map, an empty workspace) put one every 128 from x = 64, a cell off the side wall and
  `WINDOW_CLEARANCE` from the door. The shell's signature includes the fixtures; a fixture change redraws the shell.
- **Left out when validation fails**, never moving a table group: `OfficeFloorLayout.plan()` validates once with the
  furniture and the pantry. If that fails, the second try drops the furniture (the pantry kept); if that fails too
  (or there was no furniture), the third and last drops the pantry. The validator holds the counter to its place
  (`_fixture_problems()`: in the band's bay, its drawing on the
  floor), so one moved out of its corner is refused as standing outside the bay, as decor in a walkway is.

Desk trinkets and the white cat stand on side tables, never added to complete workstation images
(see the furniture placements above; [ITEMS](ITEMS.md) for the top plane).

### Incremental updates and caching

Table groups are identified by the stable key `(machine, workspace_id, tab_id)`, panes by `(machine, pane_id)`. The
terminal layout is first turned into column, side and order within the tab; when layout is missing, old seats are kept
first and gaps filled by stable pane key. A proportional resize of the terminal rectangles must not reorder existing
columns; explicit seat conflicts may allocate extra columns and produce a diagnostic. A new plan consults the old one,
grows in place where it can, and moves only the affected groups when it cannot; other surviving groups keep their
place.

At run time `FloorPlanCache` keeps, per map key (the machine's key), the last valid plan with its display model, and the
last attempt's input signature with its failure diagnostics and failing zones; `OfficeNavigator` keeps each map's pan
(`pan_of()`). None of this is saved to
disk. Renames, state, focus and disconnects do not invalidate the geometry cache. The same failing input reuses the old
picture and diagnostics without running the planner and never adopts an invalid display model; only a change of
structure, theme, layout policy or budget tries again. Window size does not change fixed rows; only when a new
policy is incompatible with the old plan and has not yet laid out successfully does a width change retry a cold plan
under that policy. A machine going away clears its valid plan and attempt record (`prune()` by machine key); a
workspace closing is a zone leaving its machine's map, planned like any change. Rebuilding the same plan keeps the
gaps history made; a cold plan without that history is not an equivalent rebuild. Duplicate identities, illegal
geometry or over-budget input never replace the last valid plan; the UI shows a layout error, and a first failure
keeps a bounded empty map (no zone at all).

**Planning is atomic per map.** Every zone is laid out in the same attempt, and any zone's problem fails the whole
map: its problems carry the zone's key (`zone <key>: …`), `FloorLayoutResult.failing_zones` and
`FloorPlanCache.failing_zones(key)` name the zones at fault (for the node budget, the zone the running total ran out
at), and the whole previous plan and the model it was made for stay. So a pane that moves from a failing zone to a
valid one is never seated twice, and the desk node budget is charged on the composed map, every zone's tables
together. The price, said plainly: while one workspace's input is invalid, none of its map is re-laid out or updated.

The allocation budget has three parts. Input pane / tab counts bound parsing work. Floor cell count, width and height
bound the TileMap, the shell, the partitions and the standing furniture (the top-wall run at most one plant per 160
units, the lane gaps at most one piece every two rows of a lane). `FloorLayoutPolicy.max_desk_nodes` (default 32768) separately bounds **the
sum of the nodes of all live table groups on a map**, every zone's together. `OfficeDeskView.node_budget(capacity)` charges
`11 + 34 × capacity` per pod, where capacity is retained columns, not the current pane count: 8 fixed table nodes
and 3 background nodes, plus two 16-node stations and two seat markers per column. Empty tabs, historical empty
columns and shells are charged in full, so later state changes never need to
buy actor budget; only closing a tab frees a table's budget, and nothing shrinks tables or compacts rows. This is an
allocation ceiling, not a guarantee of memory bytes, GPU or frame time; replacement nodes awaiting `queue_free` are not
part of the settled live count. The planner rejects an over-budget table before creating its per-column measurement
coordinates. An old plan is budget-checked too, and its table widths and column coordinates must match the canonical
measure for its capacity, so a small capacity cannot hide extra workstation slots. A budget change never triggers a
geometry re-layout; over budget still fails and keeps the old picture.

`OfficeFloorView` reuses `OfficeDeskView` by tab key. Growth and moves go through `table.resize()` / `relocate()` and
`station.rebind()` in place; panes still in the same tab keep their station, actor and native `AnimationPlayer`, and
keep animation progress when the state did not change. A pane moving between tabs on the same map transfers its
whole station before either tab reconciles (`take_station()` / `adopt_station()`), retaining its actor and signals.
`rebind()` positions absolutely at the new seat and never accumulates `+=`. Empty slots retain their actors too:
vacating changes the image and annotations, not the scene tree.

When the map's extent, walkways, pantry or furniture change, the shell subgroup is rebuilt; when a zone's rectangle
changes, its partitions are made again and its sign moves; when a table group's geometry changes, its wash and tab
label are updated. There is no per-brick diff. Changing machine or theme still rebuilds the current world; what is
kept is the plan and the view, not the people's nodes or animation clocks across maps.

## Picking and camera framing

- Production workstations have no body collision. Standing decor retains its `FURNITURE` body and footprint;
  a station's `Target` uses `PICKABLE`, mask 0, not monitoring, not monitorable.
- The 80×80 image target and 30×18 tag-row target are separate. The tag row selects a non-blocked agent
  through its badge; a visible blocked chip instead opens answer mode. A shell or vacancy has no active tag
  target. A state change under a still pointer switches the name/question tooltip without leaving an old one.
- **The engine picks stations.** `Target` has `input_pickable` on; the viewport converts the click to world
  coordinates and delivers it. `office.gd` keeps no hit-rectangle table and does no screen/pan/origin arithmetic.
  Event order (Godot 4.7.2): Control GUI
  dispatch → `_unhandled_input` → physics picking on the next physics frame; once any step marks the event handled,
  the later ones never see it. So a station under a HUD panel cannot be clicked, and the press position is already
  recorded in `OfficeCamera` when picking runs.
- **Only a left-button release can select.** A press is only a drag that has not moved yet; the wheel and the right
  button never select, however still. `OfficeStation` filters this (only a left release emits `picked`);
  "release within `CLICK_SLOP` (4) of the press" is `OfficeCamera.still_click()`. One place each, no duplicates. The
  viewport only picks inside the visible area: an off-screen station cannot be clicked, and `OfficeScene.reveal()`
  pans it in first.
- **Where a desk's signal is, is answered once, by `OfficeFloorView`, in the floor's own coordinates** (its root's: a
  station's rectangles are global, and the floor view converts them in one place). Four answers, each an empty
  `Rect2()` for a pane with no seat on the map or a zone the plan does not place (and two for the framing a map opens
  on, below):
  - `signal_extent(key)`: `OfficeStation.signal_rect()`, the native image plus reserved annotation rows,
    `Rect2(-47, -70, 94, 124)` relative to the seat's foot. Its bottom is the lens plate's bottom (54), even while
    that row is hidden. The pointer's dashed frame (`point()`, which `OfficePointer` grows by `GROW` and rounds out
    to whole units) and the camera's reveal both take it. Fitting only the native canvas left a selected name
    below the HUD at the minimum window; the stable reservation keeps the signal together without a pan when
    state, hover or lens changes. It reserves the ordinary 94-unit plate width, not its optional reach into a vacant slot.
  - `arrow_target(key)`: the actual 30×16 chip alone while it shows (`chip_rect()`), else the 80×80 native canvas
    (`target_rect()`). What an edge arrow aims at
    (`OfficeViewMarks`). **Not the extent, and meant so**: `EdgeArrowModel.of()` keeps an arrow while the target does
    not meet the view, so a blocked desk whose seat is in view and whose chip is not still has its arrow. Never merge
    the two answers.
  - `pod_extent(key)`: the desk's whole pod as drawn (`DeskMeasure.render_rect`), for the framing a map opens on.
  - `zone_opening(key)`: as wide as the zone's cells, from the top of its sign's drawing (the aisle row's own top
    while no sign is drawn) down to the bottom of its cells.
  - `sign_extent(key)`: the zone's sign as drawn (the aisle row above it while no sign is drawn), and `wall_face()`:
    the top wall's face, `OfficeShell.wall_face()` (every drawing on or against the top wall, `wall_covers()`, and
    every picture, `frames()`, merged, from `OfficeShell.FACE_TOP`: map y 12, the lift door's opaque top and the
    windows' drawn top; the door's sprite rows above it are transparent, measured). Only for the framing a map opens
    on.

  Each consumer converts once, through the nodes' own transforms: the pointer draws in the floor's coordinates and
  converts nothing; `OfficeScene.reveal()` / `reveal_zone()` add where the floor's root stands in the world (under
  the plate), because the pan is measured in the world; `OfficeViewMarks` takes the target to global coordinates
  (`root.to_global()`), which the view it is compared with is in. `office.gd` holds no desk or zone geometry: its
  methods only hand an answer to the camera.
- **The camera pans by two rules, each a pure static of `OfficeCamera`, and they stay two; a map's first arrival adds a
  third on top of them.** A desk is *revealed*
  (`reveal()`: `framing()`, then `revealed()`): the least pan that shows its extent with `REVEAL_HEADROOM` (32) above
  it, and its pod too only when the two together fit the view with that headroom (`fits()`), else the desk alone.
  When an expanded compact panel leaves less room, headroom gives way first; if the 124-unit signal itself is
  too tall, its lower chip/name rows win over the image's top. Thus the question remains reachable in the
  99-unit world above an expanded minimum-window panel. An oversized width still keeps its left edge.
  A zone is *opened* (`open_on()`: `opened()`): its opening's top
  at the top of the world with no headroom, sideways only as far as its width needs, its left edge when it is wider
  than the view. **A map opens with its back wall in view** (S3 CAMERA, 2026-10-28; `OfficeNavigator._open()`, once
  per map per run): it is revealed on the selection's whole pod, or opened on its first zone, as before, and then
  placed (`open_with_wall()`: `with_wall()`) at the top wall's face, its top at the view's top, when the face and what
  the opening is for (the selected desk's `signal_extent()`, or the first zone's `sign_extent()`) fit the view
  together, top to bottom; whatever lies below gives way. This is decided from the current workstation envelopes
  and the HUD's actual world rectangle, not the old rig's fit at a particular window size. The face's top is taken
  even where the first rule's pan stood
  higher (S3 BAND: no strip above the wall, the machine plate's foot, under the bar; on a tall window the plate is
  above the opening), and sideways is the first rule's. Where
  they do not fit (a near seat or a second-row desk selected in a short view), what the opening is for wins: the
  first rule's pan stands, because the wall is furniture and the selection is a signal. Only the first arrival lifts
  (the navigator's one-shot `pan_opens`): a zone picked (a card's place, PageUp / PageDown, `--space`), a desk
  followed, located or picked for a new pane keep `revealed()` / `opened()` exactly. None of the three clamps:
  `_process()` clamps the pan to the map and rounds the camera's position on the next frame.
  `tools/test_desk_signal.gd` pins the answers and the three rules without an office;
  `tools/test_desk_signal_wiring.gd` pins the live office's pans, openings, pointer frames and arrows.

## Stationary lifecycle and validation

The former walking presentation, door routes, ghosts, standing spots, route budgets and actor-clearance policy are
retired from the production office. There is no body catching up with a separately updated seat: the whole
workstation and its annotations move together when the plan changes. A pane appearing is furnished directly;
an agent leaving for a shell switches to the empty image; a closed pane vacates its slot or releases its pod/zone
when that structure disappears. Provider or terminal identity changes invent no departure animation.

**Disconnected is not idle.** `OfficeFloorView.freeze()` dims the complete map and pauses each station's actor.
Reconnecting the socket alone does not thaw it: `update_desks()` releases the hold only after a current observation
passes the layout gate. If that layout is invalid, the previous picture stays frozen. Resuming an unchanged state
continues its clock; a finished one-shot remains finished.

`OfficeFloorValidation` checks bounds and budgets, zones in whole lanes, pod rows and reservations, unique pane/seat
bindings, canonical `OfficeTable.measure()` widths, columns, feet and envelopes, and furniture footprint/drawing
clearances. It does not build a graph, inflate obstacles by a person, or promise reachability from the door. The
32-unit grid still reserves corridors and aisles and keeps furniture out, independent of animation.

## Acceptance boundaries

- Complete-image frames, empty image and generic portrait keep the authored palette, pivot and density. No rig,
  runtime cutting, recolouring or second set of furniture is constructed by the office.
- Both logical rows use the same front-facing art and measured click/annotation geometry. Focus underline,
  station selection, pod selection and HUD pointing remain distinct channels.
- Same-state refreshes and selection/name/focus changes retain the actor and its animation clock; blocked entry,
  hold and exit and the one-shot done nod follow the manifest. Disconnects preserve the last frame until a valid
  live observation can be shown.
- Layout keeps stable seats and map extents, bounded allocations and atomic failure, with corridors, furniture,
  shell, carpets and signs independent of agent state. Picking remains real engine input, with no action on a
  vacant slot and no terminal write from an animation or refresh.

Screenshots remain part of visual acceptance and must actually be opened and looked at; use the capture target in the
Makefile, never a headless capture. Review both 2x at 960×640 and 4x at 1920×1280, including shell seams, complete
workstation edges, empty seats, focus/selection, annotation rows and HUD portrait crops. The retained legacy
authoring families' rig and component contracts are not production-office acceptance criteria.
