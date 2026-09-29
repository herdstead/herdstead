# Studio (`daylight`) — asset spec (schema v1 / v2)

Two pack formats: **schema v1** is density 1; **schema v2** adds a per-pack pixel density and sampling filter,
so the same semantic IDs can be drawn at up to 256 px per tile. Both share the structural checks, and a v1 image
that meets the contract is never resampled. Sizes written "per 32 px tile" are density-1 values; v2 multiplies
them by the density.

The shipped pack, `daylight`, is **schema 2 / density 2 / nearest**: 1 world unit = 2 texture
pixels, with layout still in 32-unit tiles. Their long tables (`<pack>/table/`) and the pixel people are density
2, nearest too. Display scales are even only (2×–8×), so every texel lands on whole screen pixels. A source not
yet repainted at 2x is a 1x source the build fills in with NEAREST 2×2 blocks.

UI text is never baked into pixel art. Labels use the bundled Nunito Sans; the system CJK font is only the
fallback for CJK and missing glyphs.

## Scope

Assets for a wide, observational office in the "studio light" style: a floor is an open wooden floor, a tab is
one shared long table, a pane is a seat at it. This spec covers the art pack only: source PNGs, the runtime
pack, TileSet / SpriteFrames and the asset showroom (`scenes/preview.tscn`). The live office
(`scenes/office.tscn`) consumes the pack; see [the manual](MANUAL.md).

The only sound is the chime `OfficeAlerts.tone()` generates in code (`--chime`): no audio file, no `.import`, no
semantic ID, so no audio asset family.

## Engine and protocol notes

- The art pack (`scripts/art/` and its resources) targets **Godot 4.4+** (`TileMapLayer`); the repository needs
  4.6+ for `StreamPeerUDS` and is verified on 4.7.2.
- TileSet: atlas region size, margin and separation are independent; texture padding is on. Re-laying the atlas
  moves cells that hand-painted TileMaps reference.
- Pixel art imports Lossless; Godot 4 sets filtering on CanvasItem / Project Settings, not on the PNG. The
  `canvas_items` stretch rasterises text and HUD at screen resolution; `scale_mode=integer` keeps the scale whole.
- herdr: workspace / tab / pane / agent is the real structure; a worktree is a linked checkout. `done` means idle
  and unseen, not "the task passed". The pack assumes no fine-grained tool activity.

## Fixed pixel and import rules

| Item | Rule |
|---|---|
| View | Orthographic top-down, objects show a little of their top; figures face front. No isometric or perspective mixing |
| Tile | 32×32 PNG RGBA8 / sRGB at density 1; schema v2 multiplies by the density |
| Transparency | `nearest` (and every v1 pack): alpha 0 or 255 only, no baked backgrounds, glow or shadows, hard edges. `linear` (density > 1 only): soft edges and shadows allowed |
| Palette | 49 colours in `art/daylight/pack.json`. In a `nearest` pack every opaque pixel **exactly equals** one of them. A `linear` pack picks colours freely but must still define every key: UI text, panels, name plates and lighting take colours from it |
| Outline | `nearest`: native 1 px dark ink, stepped corners, no anti-aliasing. `linear`: soft or varying outlines, but the silhouette must still read against the floor |
| Scale | Even scales only: 2× / 4× / 6× / 8× (`-` / `=` step two at a time; `OfficeScene.content_scale_for` is the one rule). Below a 960×640 window the scale drops to 1×: degraded, below the supported size, not a scale step. No automatic trim, rotation or packing |
| Import | Lossless; Fix Alpha Border = true; Premult Alpha = false; `mipmaps/generate` by asset family (see "Import policy by asset family") |
| Resolution | Logical viewport 800×480. The desktop window defaults to 1920×960 (2× only; 4× needs 1920×1280); the smallest supported window is 960×640. `canvas_items` / `expand` / `integer`. `scenes/preview.tscn` ignores `--zoom` and may use 3× in a large window: it is not the product view |
| Text | Names, branches and state words are Labels, never baked into furniture. Nunito Sans body weight 500 / opsz 10, large titles weight 700 / opsz 12 |

When the window does not divide evenly, black bars are kept rather than stretching pixels.

## Density and natural degradation (schema v2)

A pack can be drawn at up to **256 px per tile** by declaring one density for the whole pack; no geometry number
changes.

### Two fields

| Field | Values | Meaning |
|---|---|---|
| `density` | `1` / `2` / `4` / `8` | **Required** in schema 2: pixels per density-1 pixel (32 / 64 / 128 / 256 px per tile) |
| `filter` | `"nearest"` / `"linear"` | Optional. Default `nearest` at density 1, `linear` above |

- `schema_version: 1` is still valid and means density 1, `nearest`. A v1 pack must not declare `density` or
  `filter`, and its built manifest gains no keys.
- `density 1` + `"linear"` is refused: 32 px is the pixel look and stays deterministic. For soft edges, raise the
  density.
- **A pack has one density**, the one it was built with. The pixel people (`assets/pixel_people/`) and the long
  table (`<pack>/table/`) are separate families with their own manifests; each texture is scaled and sampled by
  its own family's density and `filter`, never the pack's.

### Geometry is always in density-1 units

> **Every geometry number in `pack.json` is its density-1 value, at any density.** `tile_size` is always `32`,
> `atlas_size` always `[256, 128]`; prop and UI `size` / `pivot` and `panel`'s `nine_patch` never change.
> **Density is the only multiplier.**

Upgrading a pack means adding `schema_version: 2` and `density`, then repainting PNGs one by one. The built
`manifest.json` is in density-1 units too; the runtime multiplies.

`ArtPack.from_manifest()` checks, at the JSON boundary: container types; whole-integer geometry; an atlas of whole
32-unit cells with no repeated or out-of-range cell; positive sprite sizes; the pivot inside the canvas (edges
included); `nine_patch` as four non-negative integers leaving a positive middle; every built image decodable and
exactly declared size × density. Any failure returns null naming the pack and problem, instead of failing at
draw time. Which IDs the office uses, and whether a companion table exists, is `ArtContract`'s job.

### Canvases per density

| density | tile | 16×16 icon | `panel` | `selection` | atlas |
|---:|---:|---:|---:|---:|---:|
| 1 | 32×32 | 16×16 | 32×32 | 64×64 | 256×128 |
| 2 | 64×64 | 32×32 | 64×64 | 128×128 | 512×256 |
| 4 | 128×128 | 64×64 | 128×128 | 256×256 | 1024×512 |
| 8 | 256×256 | 128×128 | 256×256 | 512×512 | 2048×1024 |

Furniture scales the same way; each image's contract size is its own `size` in `pack.json`.

### Accepting source PNGs

An image of contract size `(w, h)` must be exactly `(w·k, h·k)`, `k ∈ {1, 2, 4, 8}`, `k ≤ d`, the same `k` on both
axes. `k > d` is refused with advice to raise `density` to `k`; any other size is refused with the list of
allowed sizes. The build scales by `d / k` with **NEAREST**, so every built PNG is contract size × d and the
atlas is `atlas_size × d` with `32·d` cells. From schema 2 on, `manifest.json` always carries the resolved
`"density"` and `"filter"`.

### Three levels of natural degradation

1. **Old packs keep working.** A schema 1 pack builds byte for byte the same.
2. **The build fills in under-density PNGs.** In a density 4 pack a 32 px image is NEAREST-scaled to 128 px,
   **deliberately blocky** so it reads as "not painted yet". Replace one image at a time; the pack is valid at
   every step. In the shipped packs the only 1x sources left are `wall.front_*` and `wall.threshold`, which the
   open office does not draw.
3. **Minification belongs to GPU mipmaps; `density` only means pixels per unit** (like PPU). Textures load as
   built, never resampled on the CPU, and nodes always scale by 1/density. A density > 1 pack shown below its
   density picks a mip level through `LINEAR_WITH_MIPMAPS`, so its import must generate mipmaps. Filtering is
   per family: the pack's `filter` governs its own images; the long table samples by its own manifest (density 1
   is NEAREST; denser without a `filter` is `LINEAR_WITH_MIPMAPS`); the pixel people stay density 2 `nearest`,
   crisp even beside a density 4 `linear` pack.
   A `nearest` family is **never minified** at a supported scale: the floor is 2, where a density-2 texel is one
   screen pixel, and higher even scales magnify by whole numbers, so NEAREST never reads a mip level. Below
   960×640 the scale is 1 and outlines break into dots: degradation below the supported size, with no mipmaps
   for it. A scale change only changes the window's content scale and **rebuilds no node**; only a theme change
   (new textures) rebuilds.
   - **The tile atlas has texture padding, so its runtime copy has no mipmaps.** Padding extrudes every cell by
     1 px. It matters for `linear` density > 1 packs: at a scale that does not divide the cell (128 px cells at
     3×), bilinear sampling at a cell edge reads the neighbour and draws a seam across a floor tile. The
     density-2 atlas is sampled NEAREST at even scales and never bleeds, so padding does no harm.
   - If a `linear` density > 1 tile family ever needs mipmaps, the way out is to extrude cells in the builder and
     turn padding off.

### Import policy by asset family

| Family | Directory | Sampling | `mipmaps/generate` |
|---|---|---|---|
| A theme pack's own images (tile atlas, props, UI) | `assets/<id>/` | density 2, NEAREST | `false` |
| A theme pack's long table | `assets/<id>/table/` | density 2, NEAREST | `false` |
| Pixel people | `assets/pixel_people/` | density 2, NEAREST | `false` |
| Agent logos (Avatar Studio shows them minified by `size/64`) | `assets/agent_badges/` | LINEAR_WITH_MIPMAPS | `true` |

- **The project default (`[importer_defaults]` in `project.godot`) is `false`**, right for every nearest family.
  **A family that is still minified (only the agent logos) writes `mipmaps/generate=true` explicitly in each
  PNG's `.import`**; check that when adding one (a new provider's logo, say).
- Nearest families get no mipmaps because they are never minified in a supported window and NEAREST (not
  `NEAREST_WITH_MIPMAPS`) only reads level 0: a mip chain would cost a third more video memory and import time
  and change no pixel.
- An `.import` overrides the project default, so a policy change edits every sidecar (Godot reimports next time;
  the other fields stay).
- `test_imports_follow_their_family` (`tools/test_art.gd`) checks **every** PNG under `res://assets`: the nearest
  `*manifest.json` above it decides by its `filter`; logos (no manifest) count as minified; a PNG in no family
  fails. It also asserts the project default. `test_art_textures_as_built` checks the textures the office draws
  (pack, table and people without mipmaps, every logo with).

### Style rules by `filter`

| Check | `nearest` (strict, as v1) | `linear` (loose) |
|---|---|---|
| Transparency | alpha 0 or 255 only | any |
| Pixel colours | each opaque pixel exactly a palette colour | free |
| Palette keys | each value 6-digit lowercase hex | identical (the pack decides which keys exist; scenes' needs are step 9 of "Replace and iterate protocol") |
| `floor.wood_*` outer band | after scaling to the pack density, all four 3 px (×d) edges pixel-identical | identical: interchangeable variants' edges are structural |
| Wall connecting edges | cap/face boundary and straight-wall horizontal edges pixel-identical; a family with a T joint also checks the 6-unit side section and the joint's ports | identical; only meeting ports are compared |
| Everything else | RGBA, size rules, not empty, no holes in `floor.*` and `wall.cap_*` / `wall.face_*`, pivot inside the canvas, `nine_patch` leaves a middle, atlas cells unique and in range, font files | identical |

Per-pixel checks multiply by each image's own `k`, not the pack's `d`, so a half-repainted pack is checked at the
size each image is actually painted.

`daylight` declares `nearest`, so the build holds every source pixel to its palette. (A second pack derived from it
by recolouring, Dusk Shift, was retired on 2026-09-29: night is to be a light over the one pack.)

## Tiles (29)

`art/daylight/tiles/` and `art/daylight/walls/` hold the per-tile sources, compiled into
`assets/daylight/terrain.png`: 256×128 units, 8 columns × 4 rows, 29 cells in use and 3 transparent reserved;
region 32×32, margin 0, separation 0, padding on. `pack.json` is the authority on paths.

- `floor.wood_a/b/c`: three wood variants with identical outer 3 px, so seams never change with the variant.
- `floor.walkway`: corridor floor.
- `rug.{top,middle,bottom}_{left,center,right}`: a 9-slice rug, at least 3×3, grown by repeating the middle row
  and column, never by stretching.
- `wall.{cap,face,front}_{left,center,right}`: wall cap, back wall face and low front wall.
- `wall.side_left/right`: side walls.
- `wall.cap_t_left` / `wall.face_t_left`: the T joint where an inner cross wall meets the left shell.
- `wall.cap_end_right` / `wall.face_end_right`: a cross wall's free end before the right main aisle.
- `wall.threshold`: the front-wall threshold.

The back wall is cap + face, 64 units tall. The front wall and threshold are not used in the open office. There
are no Terrain auto-connect rules: only a rectangular shell, a left T joint and a right free end are promised —
no arbitrary inner corners, crossings or doorways.

### Wall modules

`tools/wall_templates.py` is an explicit authoring tool: it reads only the pack's IDs and palette, redraws
templates from geometry into an empty directory, and exports at density 1 / 2 / 4 / 8 (coordinates below × that
density). The normal build never calls it or overwrites painted sources. The wall sources in
`art/daylight/walls/` are density 2. `art/` is excluded by `.gdignore`, so sources create no import sidecars.

| Part | Coordinates and connection contract |
| --- | --- |
| Cell | Half-open `[0,32)×[0,32)`, default texture origin, no draw offset |
| Straight wall | cap at `(c,r)`, face at `(c,r+1)`, together `[0,32)×[0,64)`; the one-unit strip where they meet is identical |
| Cap / face | cap line y 0–12, face y 12–57, skirting y 57–64. Ends change only the outer 6 units |
| Side wall | left x 0–6 only, right x 26–32 only; outer 4 units ink + inner 2 units `cream_shadow`, alpha 0 elsewhere |
| Outer corner | the face's bottom 6-unit port equals the matching side's top; the cap closes into the corner with no port above |
| T-left | cap top and face bottom each have a 6-unit left port joining the through side wall; the right joins center |
| End-right | joins center on the left; the right 6 units close at y 60–64 over the whole wall, with no port below |

Each structural cell belongs to one module: a corner or T joint replaces the side-wall cells of its cap / face
pair, with no side wall drawn underneath. An inner cross wall is T-left, center…, End-right; the right main aisle
has no cross wall. Walls stay on Ground, cut open at the front; walkable space is validated by the FloorPlan,
never inferred from transparent pixels. The build checks port pixels and coverage; still look at seams, corners,
T joints and free ends at 2× and 4×.

## Open floor and long tables

A tab is one `OfficeTable` prefab (`scenes/world/table.tscn`) assembled from the `table/` companion pack:
`surface_left/mid_a/mid_b/right` (top and grain), `apron_*` (near edge), `divider_*` (raised privacy divider),
`leg` and `bracket`. Occlusion is Y-sort by position; there is no occlusion module. Modules repeat at their
native 32 units, never stretched. The table is 80 units deep so the two rows of laptops never overlap. It is not a
pack prop ID, because its length comes from the tab's pane count: seats sit 64 units apart, tables stand side by
side on a wide floor and wrap into rows with a walkway between.

The top is warm pixel-art oak: planks along the table, one dark seam row, sparse light grain (no dithering), a
far edge of one outline row and one lit row, a near lip of one highlight over two shadow rows; lit from the
top-left. The family is **density 2**, sampled NEAREST; canvases, rows, columns and probe points below are units,
× `DENSITY` in the PNG (`tools/build_table_assets.py`). All 18 sources are painted at density 2.

- Near thickness is **3 + 3 = 6** (three lip rows in the surface, three apron rows). The surface canvas is 32×80
  with rows 75–79 transparent; the apron is 32×3, attached at y −5. The outer three columns of each module are
  one uniform column and grain falls only in columns 3–28, so modules join in any order; the divider's panels
  repeat every 8 units, which divides 32.
- Legs are solid wood narrowing twice, a dark mount above and a small glide below. `leg` is 20×40 with its last
  opaque row at 38, hung at y −2, so the foot stands on y 37; `bracket` is 12×10 at y −11.
- Chairs are charcoal (`jacket` ramp, `ink` shadow, `deep` outline), not teal, so teal clothes against a chair
  back never merge. Both are the same office chair at a person's scale, 17 wide over rows 24–45 (22 units, about
  60% of a standing person), with armrests, a gas-lift column and a five-star base: the far one (`chair_front`,
  from the front) mostly hides behind its seated worker, and the near one (`chair_back`, from behind) reaches the
  worker's shoulder blades, so the head, neck and shoulders show over it. Both are painted (GPT Image 2.5,
  pixelized), with a one-texel `deep` outline.

### Table sources and templates

- **`art/daylight/table/` is the source**: 18 PNGs and `manifest.json`. The build only reads it: no repainting,
  no saving back, no deleting unlisted drafts.
- **`assets/<id>/table/` is the runtime copy**: `build_table_assets.py` validates the whole set, then copies PNGs
  and manifest byte for byte. It refuses missing, broken, non-RGBA or fully transparent images, sizes other than
  contract × `DENSITY`, and a mismatched manifest; a failed validation writes nothing. It prunes only stale
  PNGs / `.import` files in the runtime directory.
- **Procedural drawing is authoring only**: `make table-templates` (and `make pixel-sources`, with the desk
  library) exports into the empty directory `OUT` names; `make art` never runs it. To redo geometry, change the
  drawing functions, export, review and copy chosen files into `art/daylight/table/`. Drawings are made in units
  on a 1x canvas and scaled by `DENSITY` with NEAREST as written, except the laptop, which `laptop()` draws texel
  by texel at `DENSITY`. `shell_*` is derived from the written `monitor_*` by `shell_mark()` (covers the lid mark
  on the rear, clears two output rows on the front, then draws a texel `$_` with its cursor at `CURSOR_AT`);
  derive it again after redrawing a monitor, because the probe points are contract. The pixel contract of every image (transparent surface rows, the leg's last row,
  chair and laptop probe points) is in the docstring of `tools/build_table_assets.py`, and
  `tools/test_table_assets.py` checks each item.

The table contract is fixed (schema 2, density 2, `filter: nearest`, 18 modules, one set of size / pivot / views /
assembly) and `manifest.json` must match the builder's; the build never repairs it. Changing table geometry
means updating the contract and the world model together; changing pixels needs no code or manifest change. `make
art` copies the table, then compares against the committed products.

The table sorts as one piece by its near edge. Each pane is an `OfficeStation` (chair, occupant, badge, click
area, incremental-update boundary). Near and far panes in the same layout x column face each other; a pane with
no layout x takes a stable fallback column. The far worker's seat lies inside the table's footprint, so the table
hides their lower body; the near worker sorts before the table and the near chair back before them. The task
light is a child of the table and falls only on its top; the contact shadow is on the ground layer; neither
darkens the floor. Full depth, collision and geometry rules: [the world model](WORLD_MODEL.md).

**The laptop** is `furniture.monitor` in the table family: a 32×32-unit canvas, pivot `[16,30]`. Views
`rear_shell / front_privacy` map to `monitor_rear / monitor_front`; `shell_rear / shell_front` add a static `$_`
mark on the same silhouette. All four are 14 units wide (columns 9–22), narrower than the seated worker's
shoulders, centred on x 16; the rear is 8 tall, the front with keyboard 11, drawn texel by texel with a one-texel
`deep` outline. Silver lid with a small dark mark and lit top edge, hinge line, dark screen with two output lines,
keyboard and centred trackpad, in `muted / jacket_light / sky_light`; no stand, no runtime shrinking.
The far mark is a dark `$_` on the lid, the near one a light `$_` on the screen. `TablePack.from_manifest()` /
`TableFurniture.views` parse the views with no extra schema field. The shell mark binds only to "no provider and
not launching", never to state, focus or connection; `ArtContract` and the asset tests check all four views.

## Furniture and desk-item canvases and pivots

Coordinates start at the PNG's top-left; the pivot is the foot point, placed with `offset = -pivot`. Transparent
margins are part of the spec. Values are units (as in `pack.json`); a density-2 PNG is twice that (`window`
128×96, pivot 64,88).

| ID | Canvas | pivot |
|---|---:|---:|
| `cabinet` | 48×64 | 24,60 |
| `window` | 64×48 | 32,44 |
| `window_night` | 64×48 | 32,44 |
| `door` | 48×80 | 24,76 |
| `plant`, `plant_b` | 32×48 | 16,46 |
| `sign` | 64×24 | 32,22 |
| `wall_frame` | 40×32 | 20,30 |
| `desk_mug`, `desk_notebook`, `desk_papers`, `desk_plant`, `desk_headphones` | 24×24 | 12,22 |
| `cat_loaf`, `cat_sleep`, `cat_sit` | 24×24 | 12,22 |
| `reception` | 48×32 | 24,30 |
| `pantry` | 64×48 | 32,46 |
| `done_stack` | 24×24 | 12,22 |

This copies what `art/daylight/pack.json` lists; `pack.json` is the only source, and adding furniture needs no
code change outside it (step 0 of "Replace and iterate protocol"). Scenes use the sign, the window and lift door
on the outer wall, the standing plants and cabinet, and desk items and white cats picked by a random choice fixed
per table group (see [the visual language](VISUAL_LANGUAGE.md)).

- `plant` and `plant_b` are two pots of one fixture: same canvas, pivot and footprint (their `item` block, 20×10,
  [ITEMS](ITEMS.md)). `OfficeDecorPlanner.plant_at()` takes the `plant` pool's members in turn by position (a row's first pot is cell 0, a
  wall-foot row uses its grid step, an empty bay's pot its grid column), never by state, tab or time.
- `wall_frame` hangs on a row's back wall: no footprint, drawn in the shell, foot at row top + 48
  (`OfficeShell.FRAME_FOOT`), the sign's band; its position depends only on the wall grid and the sign's bounds
  (`OfficeShell.frame_xs()`).
- `done_stack` is a signal, not a fixture: while a done agent sits at their seat, the table shows a stack of
  paper right of that seat's laptop (`OfficeTable.PAPERS_ASIDE`); only `visible` changes.

**Desk library**: five items (mug, notebook with pencil, clipped printout, potted plant, headphones) and three
white-cat poses (loaf, sitting, asleep), each a 24×24-unit RGBA image under the pixel people's rules: a 1-unit
`deep` outline where things separate, three-tone ramps lit from the top-left, alpha 0 / 255, palette colours only.
Sources are in `art/daylight/props/` (2x, by the AI painter); `tools/draw_pixel_sources.py` drew the first
versions (`make pixel-sources OUT=<empty dir>`, never run by `make art`). The table puts their foot point on the
work surface (`OfficeTable.DECOR_*`), so opaque pixels may only fall in rows 3–21 (units; 6–43 in the 48×48 PNG):
they fit the near surface, clear the divider and lip, and leave two rows under the foot point. The generator
checks this, and `tools/test_office_geometry.gd` checks it on a real table. They are static, never posed by herdr
state; a new variant is declared as a prop with an `item` block in the `desk` (or `cat`) pool ([ITEMS](ITEMS.md)):
`make art` checks the rows rule on its pixels, and the table draws it by weight.

**Entry-band fixtures**: `reception` (wooden top, brass bell on the right, a paper name strip on a teal front,
dark skirting) and `pantry` (two cups, a coffee machine on the right, two cabinet doors). `draw_pixel_sources.py`
draws first drafts; the committed pair is 2x AI-painter art, and the tests check the footprint contract on the
committed files at their own density. A counter's opaque width is its whole canvas, which is its footprint width
(its `item` footprint: 48 and 64); its bottom outline sits one row above the foot point, and the foot point and
below are transparent. The planner lays out queue and pantry spots by that width.

A station is not one composite image: chair and worker sort by their own foot points, the laptop belongs to the
table, badge and selection float above the world, and cabinet branch labels and dynamic text are separate nodes.
Seat, laptop, divider and chair offsets live only in `scripts/world/table.gd` (0 = the table's near edge); plate
and badge offsets in `scripts/world/station.gd`. Those were measured on every frame of the pixel people: seated
head top −31; standing head −37..−25; width −8..8; a raised hand reaches −38 with the straight arm (side out to
9) and −36 with the bent arm (side out to 12; see `raised_hand` in "Pixel people"). If figures change height or
raised hand, measure again; `tools/test_office_geometry.gd` catches a plate that covers a face or drifts away.

## People and herdr agents

A theme pack carries no figures. People are one family shared by all themes, the pixel people; each pack reads one
copy (`ArtPack.people`, sharing the pack's `AgentCatalog`). A pack's `states[].animation` may only name a semantic
name that `state_tracks` in `art/pixel_people/people.json` maps in both `stand` and `desk` (checked by
`tools/build_assets.py`); the office accepts only `ArtContract.ANIMATIONS` (checked by `make check-packs`).
Stations, the agent card portrait, the showroom and Avatar Studio all draw `PixelPerson`.

**The provider is shown only by the name plate.** A unit is 2×2 texels, too small for a recognisable chest logo;
the plate carries the provider name in capitals. Clothes and looks are not a provider code: they come from the
provider's default, the user's saved choice, or a fixed variation from the pane's stable key (see
`docs/VISUAL_LANGUAGE.md`, "Looks", and "Pixel people").

### Tracks and nodes

One animation clock: each `PixelPerson` has one `AnimationPlayer` whose value tracks drive the `frame` of the six
`Sprite2D` under `Layers/` (`Legs`, `Top`, `Body`, `Glasses`, `Hair`, `Headwear`, bottom to top), all on the same
frame with no sync code. `PixelPeople.animation_library()` builds the library once per family. Clothes, facing,
sitting and standing only change textures, `flip_h` and the playing track of existing nodes; a state change only
changes the track; no node is rebuilt. Seated on the far side shows the front, on the near side the back; a
standing `done` faces the viewer.

| herdr / display state | track (`desk` / `stand`) | Intent |
|---|---|---|
| `idle` / `done` / `unknown` | `desk_idle` / `stand_idle` | slight breathing; the person keeps their identity |
| `working` | `desk_work` / `stand_idle` | typing while seated; no standing-at-work picture |
| `blocked` | `desk_blocked` / `stand_blocked` | a hand raised above the head; not drawn as failure |
| `launch_pending` | `desk_start` / `stand_start` | getting ready, with the starting badge |
| offline | freeze on the last frame | a disconnect is not idle; motion is not reset |

`Avatar Studio` previews `desk/front/working`: `D` / `S` desk / stand, `F` / `B` facing, `1`–`4` idle / working /
blocked / starting. Each slot is one `‹ value ›` row: `VARIES` (the pane's variation or the provider's default)
and every option the family draws (`[` / `]` pick the row, `←` / `→` the value, `0` unfixes, Enter saves). Only
baked swatches exist; there is no per-colour picker. Only fixed slots are saved, never motion state. Stage and card
scale people by whole numbers (stage 2×, card 1×).

`data/agent_catalog.json` holds the canonical agents verified by the herdr registry; each agent's `look` is a
sparse default outfit (top, legs, headwear and colours). The user's fixed slots are saved per provider in
`user://herdstead_avatars.json` (see "The avatar save file"). An undrawn option or unknown provider falls back slot
by slot (`PixelPeople.look_for()`). The logos in `assets/agent_badges/` (downloaded or generated monograms; sources
and licences in `assets/agent_badges/ATTRIBUTIONS.md`) appear only in Avatar Studio's agent list.

## UI assets (11) and state semantics

- 16×16 icons: working, blocked, unread, idle, unknown, offline, starting, branch, connected.
- `panel`: 32×32 NinePatch, margin 4 on each side, for detail boxes and label backgrounds.
- `selection`: 64×64 transparent corner marks, pivot 32,60.

| herdr state | Animation | Icon / meaning |
|---|---|---|
| working | working | activity mark; not "a shell command is known to run" |
| blocked | blocked | amber `!`; needs attention, no invented reason |
| done | idle (standing `stand_idle`, beside the seat, facing the viewer) | blue envelope / UNREAD; no trophy or tick |
| idle | idle | neutral ellipsis |
| unknown | idle | grey `?`; infers neither success nor failure |

starting and offline are display overlays, not new herdr states. On a disconnect the office keeps the last
positions, pauses motion, dims the picture and says STALE; idle never stands in for a lost connection.

## Replace and iterate protocol

0. **Add a prop / tile / UI icon** (no Python change):
   1. Put the PNG in `art/daylight/<props|tiles|ui>/` at contract size × the pack's density.
   2. Add an entry to the category in `art/daylight/pack.json`: `path`, plus `size` / `pivot` (`cell` for a tile).
   3. `make art`: rebuilds every pack, compares the committed products.
   4. **Only when a scene draws it**, add a constant to `scripts/art/art_contract.gd` and its `*_ids()`; until
      then `make check-packs` lists it under `PACK_UNUSED` ("in the pack, drawn by nobody"). An item a pool draws
      (a desk trinket, a cat, a pot) needs no constant: give it an `item` block with its `group`
      ([ITEMS](ITEMS.md)) and the scene that draws that pool finds it.

1. **Change one image**: replace the same-named PNG in `art/daylight/` (or `art/daylight/table/`), keeping canvas,
   pivot, transparency and palette, then `make art`. The table builder alone only validates and copies one
   theme; it never redraws a missing source. `make test-art` checks
   canvases (contract × density), source / runtime byte equality, surface / divider seams, and that sources are
   kept and rebuilds are identical.
2. **Reskin a pack**: copy `art/daylight/`, keep semantic IDs and geometry, change palette and PNGs, build with
   `--source` / `--output`. Built into `assets/<id>/`, a pack is discovered at startup: choose it with
   `--pack` or `manifest_path` on the root node (stored in `user://herdstead.cfg`; precedence `--pack=` > saved >
   scene default). A recolour-only pack derived by a
   recipe (the retired Dusk Shift) is no longer supported.
3. **Raise the density** (to schema v2), one image at a time:

   ```sh
   # copy a source pack as schema 2 + density 4, PNGs kept at their current size
   python tools/upscale_pack.py --source art/daylight --output art/<new-id> --density 4 --manifest-only
   python tools/build_assets.py --source art/<new-id> --output /tmp/<new-id>
   ```

   The pack builds at once and **looks blocky**, the honest look of "not painted yet". Replace one PNG at a time
   at the new canvas size; the build passes at every step, and 1× / 2× / 4× images may be mixed. Without
   `--manifest-only` every PNG is written scaled up (handy for painting over). The tool suffixes `id` / `name`
   (override with `--id` / `--name`) and refuses the source directory, a non-empty directory, or a lower density.
4. **Animation timing**: edit fps / durations in the source `pack.json` and rebuild. There is no pre-generated
   `.tres`: `ArtPack` builds the TileSet and `PixelPeople` the animation library from their manifests.
5. **Atlas cells**: keep coordinates stable. Procedural scenes use `ArtPack.cell(id)` and survive a re-layout;
   **a hand-painted, saved TileMapLayer stores coordinates and needs migrating**.
6. `art/daylight/` is hand-made; `assets/<id>/` and derived `art/<id>/` are products, and the build never touches
   the hand-made source. **A product holds exactly what its manifest declares**: `make art` removes PNGs (and
   their `.import`) the manifest no longer declares and prints `PRUNED:`, so `check_build_clean` reports the
   deletion as drift to commit. Otherwise a dropped `pack.json` entry would leave an orphan identical to the
   commit that nobody sees.
7. **Optional stale tint**: top-level `"stale_modulate": "rrggbb"` (6-digit lowercase hex) tints the office while
   herdr is disconnected; default `Color(0.65, 0.65, 0.65)`. Additive to schema v1, no version bump; read through
   `ArtPack.stale_tint`. A dark theme should set it, or 0.65 grey crushes the picture.
8. **Optional task-light strength**: top-level `"task_lights": "soft" | "strong"` sets how strongly the table's
   task-light wedges and chair contact shadows draw; default `"soft"`. Additive to schema v1; read through
   `ArtPack.task_lights`.
   `scripts/world/table.gd` looks only at this key, **never at the pack's name**.
   **Optional display face**: top-level `"display_font": {"path", "license"}`, like `font`, names a pixel face
   for the HUD's few fixed ASCII headings (the wordmark, FLOORS, NEWS, NEXT). Read through
   `ArtPack.display_font` with antialiasing, hinting and subpixel positioning off; `HudTheme` draws it only at
   sizes on its 8-pixel grid (`DISPLAY_SIZES`) and falls back to the main font when a pack names none.
9. **Scene dependency list**: the palette keys, props, UI, tiles, states and animations scenes use, plus the table
   modules and the pixel people (every semantic animation has a track in both poses, seated tracks draw the
   back), live in `scripts/art/art_contract.gd`, beside the code that uses them; scene code takes IDs only through
   its constants. `make check-packs` checks every pack under `assets/` and refuses one missing a key (an exported
   PCK runs the same check through `tools/check_pack.gd`). `ArtContract.unused()` reports IDs a pack has but the
   contract does not need, printed as `PACK_UNUSED:` lines (**exit code unaffected**: a pack may draw more).
   `tools/build_assets.py` checks only the pack's own shape, with **`pack.json` as the only source of IDs, sizes
   and pivots**: PNGs agree with the manifest (geometry, transparency, atlas cells, `states` references); no fixed
   count of props, icons or colours is asserted. Some palette keys serve a large surface and text or icons at
   once (`ink` outline and body text, `cream` wall and top-bar text, `paper` panel and titles, `floor` floor and
   station name background, `blocked` badge and selection frame, `muted` the top bar's theme name); a restyle
   cannot darken one use alone. `tools/test_assets.py` runs the contract tests on any theme source through
   `--source` or `HERDSTEAD_PACK_SOURCE`.

On disk a pack is only `pack.json` / `manifest.json` and PNGs, no generated `.tres`. People and the Python builders
write packs; the Godot editor never does. Loose packs (`--pack=/abs/path`, test fixtures) load from JSON too. The
three `from_manifest()` functions in `scripts/art/` are the only readers of these files and return typed classes.
A standalone export must add `*.json` to Godot's non-resource Include Filter so the manifests reach the PCK.

## Pixel people

The family (`pixel_people`) that draws every person in the office. **True pixel art**: density 1 or 2 (the shipped
`people.json` is density 2: 64×96-texel frames, three 1728×4512 sheets), nearest, never minified at a scale floor
of 2, small frame animations, recoloured at build time. Geometry, pivot, frames and choreography are in **units**;
textures are used as built and nodes scale by 1/density (`ArtFamily.dress()`). The standalone showroom
(`make people`) shows every frame.

Pipeline: `art/pixel_people/people.json` → `tools/build_pixel_people.py` (`make art`) →
`assets/pixel_people/people_manifest.json` → `PixelPeople.from_manifest()`, read once per `ArtPack` (`art.people`).
The office's requirements are in `ArtContract` (every semantic animation has a track in both poses, seated tracks
draw the back). The product manifest is not named `manifest.json`, so it is never taken for a theme.

### Contract (`people.json`, the only hand-written source)

| Field | Current value / rule |
|---|---|
| `schema_version` / `density` | `2` / `2` (schema only 2; density 1 or 2 texels per unit, multiplying frame and sheet sizes) |
| `ring_texels` | `1` (optional): ink texels per ring cell, 1 to density, absent = density. Builder only; not in the product manifest |
| `raised_hand` | `"bent"` (optional, `"straight"` or `"bent"`, absent = `"straight"`): which raised hand blocked draws. Builder only |
| `frame_size` / `pivot` | `[32, 48]` / `[16, 46]`. **The pivot's x is half the frame width**, so mirroring never moves the feet |
| `facings` / `side_faces` | `front`, `back`, `side`; the side faces right, and left is that strip with `flip_h` on every layer |
| `layers` | bottom to top `legs` (trousers, shoes), `top` (top, sleeves), `body` (head, neck, hands, eyes, things held), `glasses`, `hair`, `headwear`: the prefab's six Sprites |
| `tracks` | per motion: `facings` (first must be `front`), `durations` (seconds per frame, finite, positive), `loop` |
| `state_tracks` | `stand` / `desk` × `idle done unknown working blocked starting` → motion |
| `keys` | a three-tone key ramp (light, mid, dark) per recolourable role: `skin`, `top`, `legs`, `hair`, `hat`. Keys are loud marker colours, not final colours |
| `fixed` | kept as is: `ink` (outline, not pure black), `eye`, `catchlight`, `shoe`, `shoe_light`, `paper`, `paper_line`, `cup`, `cup_shade`, `coffee`, `lens` (lens glint), `frame` (glasses frame) |
| `slots` | exactly `AvatarLook.SLOTS`: `skin`, `hair_style`, `hair_colour`, `top`, `legs`, `headwear`, `headwear_colour`, `glasses` |
| `default_look` | the pack's default figure: one drawn option per slot |
| `variation` | slots that vary per pane and their pools (repeats weight); now skin, hair style, hair colour, glasses (about 1 pane in 6) |

Key and fixed colours are all distinct, since recolouring is a table lookup; the builder checks for ambiguity with
`recolour.remap_table()` (`tools/recolour.py`).

| Motion | Facings | Frames | Use |
|---|---|---|---|
| `stand_idle` | front, back, side | 2 | standing idle / done / unknown; the head drops 1 unit to breathe |
| `walk` | front, back, side | 4 | contact / passing / contact / passing; on passing the upper body rises 1 unit and the supporting leg lengthens; the planted foot never moves |
| `desk_idle` | front, back | 2 | seated idle / done / unknown |
| `desk_work` | front, back | 4 | typing: hands rise 1 unit in turn |
| `desk_blocked` | front, back | 2 | seated, a hand raised above the head |
| `stand_blocked` | front, side | 2 | the reception queue (side, facing the reception on the right); from the side the far hand reaches up behind the head, never covering the face |
| `desk_start` / `stand_start` | front, back | 2 | launch pending: hands on the lap / together in front, a nod on frame 2 |
| `carry_walk` | front, back, side | 4 | walking with papers |
| `drink` | front, side | 3 | pantry coffee: cup at chest, chin, mouth (played by name; `ArtContract.TRACK_DRINK` requires the front) |

**1 unit = density texels**: "1 unit" is 2 texel rows at density 2. The feet are on texel row
`pivot.y × density − 1` (45 at density 1, 91 at density 2). Strip and skin sizes and source-strip coordinates are
texels; contract and motions are units.

`stand` maps `working` to `stand_idle`: a standing person is only `done` (beside the seat), blocked (the queue) or
idle (the pantry, `drink` by name, see `OfficeRests`); working is "at your seat, typing". A standing-at-work
picture would need a new motion and a change to this row.

### Slots

A slot is either a **shape** (`layer` + `shapes`: which strip a layer draws, optionally `"none": true`) or a
**colour** (`layer` + `role` + `swatches`: a three-tone target ramp for one role, no `none`). **Each layer has at
most one shape slot and one colour slot, and each role is coloured by exactly one colour slot**, so baking adds
rather than multiplies: strips per facing = `S + L + T + G + Hs·Hc + W·Wc`, now 5 + 5 + 5 + 2 + 3·6 + 2·6 = **47**.
(Skin, top and trousers on one layer would be `S·T·L` = 125.)

| Slot | Layer | Options |
|---|---|---|
| `skin` | body (`skin` role) | `porcelain` `fair` `tan` `brown` `deep` |
| `hair_style` | hair (shape, may be `none`) | `short` `curl` `long` |
| `hair_colour` | hair (`hair` role) | `brown` `auburn` `umber` `black` `blonde` `grey` |
| `top` | top (`top` role) | `slate` `cream` `terra` `teal` `lilac` |
| `legs` | legs (`legs` role) | `charcoal` `brown` `taupe` `denim` `plum` |
| `headwear` | headwear (shape, may be `none`) | `cap` (over the hair), `hood` (`hides_hair`: no hair layer while worn) |
| `headwear_colour` | headwear (`hat` role) | `slate` `cream` `terra` `teal` `lilac` `sea` |
| `glasses` | glasses (shape, may be `none`; fixed colours only) | `round` `square` |

A v1 outfit translates through one frozen table, colours unchanged (`AgentCatalog.migrate_v1()`, for the save file
and the catalog's `look`): coat X → `top` X plus `legs` (slate→charcoal, cream→brown, terra→taupe, teal→denim,
lilac→plum); `short` → short hair, `brown`; `curl` → curly hair, `auburn`; `cap` → short hair, `umber`, headwear
`cap` in `sea`; `hood` → short hair, `brown`, headwear `hood` in the coat's colour name.

**A person's look** is decided slot by slot by `PixelPeople.look_for(provider, wanted, vary_by)`, each level
overriding the last and skipping undrawable options: the pack's `default_look` → the provider's catalog `look` → the
user's fixed options for the provider → for an unfixed slot in `variation`, `pool[u32 % pool size]`, where `u32` is
the first four bytes (big-endian) of the SHA-256 of UTF-8 `"herdstead.look/1␟provider␟pane_key␟slot"` (␟ = U+001F;
stations and portraits pass `HerdrFleet.pane_key` as `vary_by`) → what the caller explicitly wants (Studio preview,
showroom). SHA-256 makes a pane pick the same person on every run, machine and Godot version, and the tests pin
values computed outside Godot. Each slot hashes separately, so a new slot or pool reshuffles only that slot. The
choice happens only in `configure()`; state never takes part.

### Strip layout and packing

Each shape and swatch of each layer is one horizontal strip, as wide as all motions' frames together (27 frames,
864×48 units, × density texels), in contract order. A motion that skips a facing leaves its columns transparent
there. So a frame number is the same moment in every strip: one `frame` key drives all six layers, and turning only
swaps textures (plus `flip_h` for left). A motion without the wanted facing (seated has no side; `stand_blocked`
and `drink` no back) shows its front.

**All strips of a facing are packed into one sheet at build time**: `assets/pixel_people/<facing>.png`, stacked in
the product manifest's `strips` order with no gaps (864×2256 units × density). A layer's texture is an
`AtlasTexture` over its row (`PixelPeople.strip_texture()`, built once per strip).

Why: Godot's compatibility renderer batches adjacent canvas items only when texture and material match (measured:
K Sprites on one texture are 1 draw call, on separate textures K), and a person's six layers are adjacent items.
Separate strips cost 480 draw calls for 80 people and about 0.8 ms more CPU per frame than two layers (measured);
one sheet merges everyone into 1 draw call. Packing is a **build-time** step; invariant 6 forbids runtime
scaling, resampling or repacking, not this. Scene code still uses semantic IDs only (rows come from the manifest
through `PixelPeople`). Region sampling measured pixel-identical at 2× and 3×, flipped or not, and
`tools/test_pixel_people.gd` checks every imported region against the builder's strip.

If colours are ever picked at runtime, per-instance shader uniforms will not do: the compatibility renderer accepts
only 256 canvas items with instance uniforms (the 257th is refused, measured). A per-look `ShaderMaterial` over
per-facing index sheets keeps one draw call per person.

### Source strips, white model and recolouring

- **Hand-painted source strips** (optional; none ship) go in `art/pixel_people/<facing>/`: `<facing>/legs.png`,
  `<facing>/top.png`, `<facing>/body.png` and one `glasses_<shape>.png`, `hair_<style>.png`, `headwear_<shape>.png`
  per shape (10 per facing, 30 in all), in key and fixed colours. The builder checks: exact strip size; alpha 0 /
  255; every opaque pixel a key of this layer's role or a fixed colour (else file, coordinate and colour); a drawn
  facing has content on legs, top and body in every frame, an undrawn one empty columns; **a hat covers all hair
  above its brim** (every hat that does not hide hair × every hair style × every frame); a PNG the contract does
  not name is refused.
- Body layers paint only what shows: a hand in front of the top is on body; a far hand behind the torso is not
  painted. Glasses are a thin frame around the eye in the mid-grey fixed `frame` (ink against the near-black eye
  would read as a blindfold); nothing opaque covers the eye (`lens` is for a painter's glint). Measured: `frame`
  against the eye 4.3:1; against skin mid tones porcelain 2.61, fair 2.09, tan 1.45, brown 1.29, deep 2.09 — faint
  on the middle skins, for finished glasses art to solve.
- **Eye against skin**: the builder prints the WCAG 2.1 contrast of the fixed `eye` against each skin's mid tone
  (`PEOPLE_EYE_CONTRAST`). The threshold is 3:1 (WCAG 2.1 SC 1.4.11, graphics needed to understand content): at 1×
  an eye is 1×2 pixels, smaller than any UI graphic. Measured: porcelain 11.23, fair 8.98, tan 6.23, brown 3.34,
  **deep 2.06**. A swatch below the threshold is neither changed nor refused. **The answer is a catchlight**: when
  `people.json` has the fixed colour `catchlight`, from density 2 on the white model paints it on
  the top-left texel of the upper cell of each eye (lit from the top-left like every part; at density 1 an eye
  has 2 texels and gets none). It belongs to the eye, painted after the skins, so no skin reaches it; a thin
  ring's corner ink is never painted over it; it lies inside the eye, so no hair (the long hair's side ink is in the column just
  outside), hat or glasses covers it (`test_every_visible_eye_has_its_catchlight_under_every_head`). The body layer
  is shared by every skin tone, hence a fixed colour. There is no sclera: a light cell beside the eye would sit
  under the long hair's ink. A hand-painted body strip must paint the catchlight texel itself.
- **The white model**: without source strips the builder draws a procedural figure under the same contract (same
  keys, checks and recolouring) and lists it in the product's `mock_files`, the painter's to-do list. It paints in
  unit **cells** of density × density texels. Each part is a sticker applied back to front: a 4-neighbour ink ring
  in its empty neighbour cells, then its fill, so a later ring cuts into an earlier part (chin, waist, arm over
  body); three-tone ramps are lit from the top-left. The whole person is painted at once, then each texel goes to
  exactly one layer, the part that painted it last: legs, top and body never overlap and together are the whole
  person, whatever the draw order. Tests guard: a continuous ink silhouette across the six layers; feet on the last
  texel row of the unit above the pivot; two 1×2-unit eyes from the front, one from the side, none from the back; a
  raised hand at least a unit above head and hat; a walk frame moves 1 unit; every fill at least 40 RGB distance
  from the ink.
- **Ring thickness** is `ring_texels`. **With a whole-cell ring** the density-2 white model is the density-1 one
  NEAREST ×2, texel for texel (Python tests; the density-1 output has pinned hashes). **With a thinner ring**
  (`test_a_thinner_ring_is_the_ring_cell_s_outer_texel`) the ink is each ring cell's outer `ring_texels` rows /
  columns; the texels on the part's side take the colour and layer of the part texel across the edge (the skin's
  colour when a skin is worn). Where two such texels meet at a convex corner, the corner texel between them is ink
  too, so the fill never touches air or an earlier part — except on an eye the white model paints, which always
  shows (`test_a_thin_ring_s_corner_never_covers_an_eye`: in `drink` the cup sits diagonally against an eye). So the
  whole person and every hair, headwear and glasses frame keep the whole-cell envelope and foot row and add only
  corner ink (`test_a_thin_ring_keeps_every_frame_s_envelope`), and the offsets in `scripts/world/station.gd`
  stand. The cost: a thinner outline and wider fill, moving the chin, waist and arm seams out by half a unit. A
  single layer may gain a corner ink texel, so only the per-person envelope is guaranteed, not the per-layer one.
  The shipped `"ring_texels": 1` gives people the same 1-texel outline as the environment's 2x art.
- **The raised hand** (the `raised` / `waved` frames of `desk_blocked` and `stand_blocked`), chosen by
  `raised_hand`. `straight`: an arm straight up past the head with a 2×2-cell hand. `bent`: the upper arm slants out
  from the shoulder to an elbow level with the chin, the forearm goes straight up, then one row of cuff (the top's
  lightest tone; the `CUFF` letter), a 3×3-cell mitten and one cell of thumb on top — at the outer corner from the
  front, the inner corner from the back; in the waving frame forearm and hand are one cell higher. From the side
  (only `stand_blocked`) the arm is behind the head and only cuff, mitten and thumb show above the hair, as high as
  the straight hand. Both: the hand is more than a unit above every hair style and hat; seated it reaches at most
  −38 and 9 wide (units from the pivot, ink included; the bent arm −36..−35 and 12); the bent arm is never higher
  than the straight one (`RaisedHandTests`, both built at the shipped density and ring, wearing the shipped skins;
  each has pinned density-1 hashes). "3×3 hand, 1 thumb" are cells: a density-2 cell is 2×2 texels.
- Recolouring is an exact per-pixel substitution (`recolour.repaint()`); each product strip maps only its own
  layer's role, and any other key colour is an error.
- The brim is measured in units: hair above the hat's lowest **unit** row must be under the hat (at density 2,
  above the first row of the unit holding the hat's lowest texel).

### Skins

Painting whole strips frame by frame is too heavy, and the 1-unit choreography tests are more than frame-by-frame AI
output can hit. So detail comes from a **skinned white model**: a painter (or the AI painter) paints one "skin" for a
few parts, and the white model still poses, inks and animates every frame, taking only that part's fill colours from
the skin.

- Location: `art/pixel_people/skins/<facing>/<part>.png` (not "a PNG the contract does not name", but only these
  names are accepted). Parts (`SKIN_PARTS`): `head` (body layer: skin keys + fixed colours), `torso` (top),
  `hair_<style>` (hair), `headwear_<shape>` (headwear). Limbs, shoes, held paper and cup, and glasses take no skin:
  a limb is a polyline no single picture fits, and three tones suffice at 2×2 texels per cell.
- Canvas = the part's cell envelope × density (head 8×8 cells, 16×16 at density 2; torso front 8×11 cells; hair
  and hats by shape), the same for every frame: the skin's top-left sits at the envelope's top-left. Seated, the
  torso loses its last cell row and the skin's last density texel rows go unused.
- Hard constraints (file, coordinate and rule on refusal): exact canvas size; alpha 0 / 255; only this layer's role
  keys and fixed colours; **opaque only on the part's own cells in its own layer** — not outside the rounded
  corners, not on the torso front's two neckline cells (body-layer skin), not on the ink ring. **`eye` and
  `catchlight` are forbidden**: only the white model paints eyes, and either colour in a skin would count as an
  extra eye in the colour-counting tests; the builder and `cut` refuse it. Pixelize with `--only` omitting those
  two; `cut` leaves the head's eye cells empty. So the real pixel envelope (seated head −31, raised hand −38, width
  ±8) and the offsets in `scripts/world/station.gd` stand.
- A transparent skin texel keeps the white model's tone; the ink ring is always the white model's; **the eyes are
  painted after the skin**, covering whatever it holds there. Hat-over-hair still holds by the brim check: a skin
  changes fill, never which cells a hat covers.
- A hand-painted strip of the same name (`<facing>/<strip>.png`) wins over the skins on that strip.
- `mock_files` lists white-model strips that wear no skin yet; a strip leaves the list once one of its parts wears
  a skin (per facing).
- With a thin ring, the ring cell's texels on the part's side take the skin's colour, so the skin's edge colour
  reaches the ink.
- **Cutting skins** (`tools/people_skins.py`, `make people-skins`): a painter repaints **one whole frame** of the
  white model, and the tool cuts it into skins by the white model's cells.
  `reference --facing <facing> [--wear hair_short,headwear_cap] --out <png>` draws that frame (default `stand_idle`
  frame 0, key colours, ×8) and prints the pixelize arguments that bring a painting back onto the same texels:
  `--size`, `--pivot` (not 32 from the side), the envelope as `--fit`, and `--stretch` (keeping the aspect ratio, a
  figure a few percent off in proportion lands a texel off).
  `cut <pixelized frame> --facing <facing> --parts head,torso --out art/pixel_people/skins/<facing>/` first aligns:
  the frame's opaque envelope must equal the white model's for that frame wearing the pictured hair and hats
  (`--wear`, default the hair and hats among `--parts`; from the side the figure is off-centre, hair reaching back
  and the cap's peak forward). Then, per part: on the part's own cells a key or fixed colour of the layer is kept, a
  transparent texel is left to the white model, and any foreign colour is refused with frame and skin coordinates.
  Hair keys on a hat's cells become the hat's dark tone (a mechanical hat-over-hair fix). Head and torso texels
  another layer covers in that frame (from the side, the near hand over the torso) are left to the white model.
  Texels outside the part's cells (ring, corners, neckline, the face hole in a hair style) are dropped, but if one
  holds the part's own key the painted part is bigger than the envelope and the whole frame is refused. It writes
  only when every part passes and never overwrites a skin; `--check` checks existing skins by the builder's rules.
  `--drop-outside` (`make people-skins … DROP=1`) drops out-of-envelope texels and prints each (`SKIN_DROPPED:`)
  instead: a model painting a torso nearly always misses the 4×2-texel neckline notch by a texel or two, and
  dropping texels outside the part's cells never takes anything from the skin. Foreign colours are still refused.
- `make people-templates` exports an empty canvas for every skin (`canvases/skins/`) with a same-named guide
  (`guides/skins/`: paintable texels in the white model's flat tones, the rest grey, eyes red) and `skins.tsv`
  (canvas, layer, allowed colours, painted or not). Colours and composition are the painter's; the builder must
  pass a skin with zero hand edits before it is committed.
- Builds are deterministic (byte-identical twice); PNGs the manifest no longer names (with their `.import`) are
  pruned and printed as `PRUNED:`.

### Product manifest and runtime

`people_manifest.json` holds only what the runtime needs: geometry, `columns`, facings, layers, each motion's
`start` / `facings` / `durations` / `loop`, `state_tracks`, `slots`, `default_look`, `variation`, `keys`, `fixed`,
`strips` (each sheet's row order), `files` (three sheets), `mock_files`. `PixelPeople.from_manifest()` is its only
reader and answers `push_error` and null for: an unknown field, schema or density; a pivot off the centre line;
wrong layers; a frame out of range; a non-finite or non-positive duration; an unknown facing; a motion whose first
facing is not the front; `state_tracks` missing a state or naming a missing motion; incomplete or unreadable slots;
a default or pool using an undrawn option; a strip some look needs missing, or one nobody uses present; a missing or
wrongly sized sheet. `strip_name(layer, look)` / `layer_texture(layer, look, facing)` give a layer's strip (empty for
shape `none` and for hair under a hood); `dress()` scales by 1/density with offset −pivot × density (in texels) and
nearest; `frame_rect()` and strip regions are in texels; `animation_library()` is built once, one animation per
motion with discrete keys on all six `frame`s, so a motion change never leaves the last motion's frame.

`PixelPerson` (`scenes/people/pixel_person.tscn`): `configure(family, provider, look)`, `vary_by(pane_key)`,
`play_state()`, `pause()` / `play()` / `is_playing()`, `sit()` / `stand_up()`, `drawing_rect()`, `footprint()` (a
12×4 foot collider, bottom edge at the foot point, physics layer `ACTORS`), `face()` (front, back, left, right),
`play_track()` (a motion by name, like walking, with no state mapping) and `hold()` (one frame, for the inspection
sheet and portraits). Clothes, facing and state change only properties of the same nodes; a layer drawing nothing
has a null texture (no draw call); a paused person stays paused on a new state; turning keeps the motion clock;
sitting turns the facing back to the look's front / back.

The three sheets' `.import` have `mipmaps/generate=false` and are lossless (`compress/mode=0`); see "Import policy by
asset family".

### The avatar save file (`user://herdstead_avatars.json`)

`{"schema_version": 2, "looks": {"<provider>": {"<slot>": "<option>" | {"rgb": "rrggbb"}}}}`, only the slots the
user fixed. `{"rgb"}` is reserved for per-colour picking: read and written back as is, not drawn. `AgentCatalog` is
its only reader and writer.

- **One id rule** for catalog agent ids and saved provider, slot and option ids, on read and write:
  `[a-z0-9][a-z0-9_-]*`, at most 64 characters, matching the whole text (`AgentCatalog.valid_id()`; `$` alone would
  let a trailing newline through), so `claude-code` saves and loads. A bad id on write is refused with a `note`.
- **A save loses and hides nothing, or does not save.** The file stays in memory as read; a save changes only the
  requested provider's requested slots (the Studio sends only rows the user touched). Undrawable ids, picked colours,
  unknown slots and top-level fields, unreadable values and entries beyond the caps are kept. Before writing, the
  text is read back by the load-time reader (`verify()`) and checked: size under the cap (size); reads back as READ
  (reads back); the provider being fixed is within the provider cap (provider cap); the set slots read back as set
  (set reads back); every slot readable before reads back unchanged (readable before); everything else is identical
  in the written JSON (pass-through). Any failure writes nothing, and `note` says "Not saved: … (check: <name>)",
  shown by the Studio instead of SAVED. Refused before the checks: replacing a provider value that is not a JSON
  object (a newer format); a pin beyond 256 providers ("too many saved providers"). A provider whose value is `{}`
  stays if untouched. Unfixing a provider may bring one formerly beyond the cap into the looks: revealing, not
  losing.
- **The file on disk must be the one read**: size and SHA-256 (or "absent") are recorded at load and after each save,
  and checked again before writing (through a symbolic link, the target). On any difference — hand-edited, replaced,
  deleted, saved by another Studio — nothing is written and `note` says "the saved file changed on disk since it
  was read; reopen to see it". A window of milliseconds remains before the rename.
- **What is written**: compact JSON in the file's original key order (new entries last), so the next start reads
  looks for the same providers. Strings go through `JsonText.encode()` (`scripts/json_text.gd`, shared with herdr
  requests): every C0 control character and DEL as `\u00XX`, readable by any strict parser (`JSON.stringify`
  writes 0x0B as the invalid `\v` and other controls raw). Values round-trip; integers within ±2^53 stay integers
  (`schema_version` is `2`, `-0` becomes `0`), other numbers are written at full precision and read back as the
  same double. **Not kept** (lost at parse, invisible to the checks): duplicate keys (last wins), anything after a
  NUL byte, `\u0000` in a string (read as U+FFFD), numbers below double range (`5e-324` reads as 0).
- **Reading is bounded**: over 256 KiB or deeper than 100 levels, the file is not read **and never written**
  (`OUT_OF_BOUNDS`, "too large / too deep for this build") and stays where it is. Entries beyond 256 providers or 32
  slots each are not read into looks (known slots first) but kept. The 100-level limit: Godot's deep copy stops at
  about 100 ("Max recursion reached") and this file's traversal recurses per level; a look needs 4. Bytes are
  checked as valid UTF-8 first (by hand, so nothing is decoded into the log), then parsed without error reporting.
- **An old file** without `schema_version` (`{"<agent>": {"hair", "outfit"}}`) is migrated in memory by the table
  above (skin still varies). The first save first copies the original to the next free name
  (`user://herdstead_avatars.v1.json`, then `.v1-2`, …); a failed copy refuses the save, and `note` says where it
  went. Entries the table cannot translate live only in the copy.
- **An unreadable file** (not UTF-8, not JSON, not an object, a non-integer version) means defaults; reading never
  writes. The first save renames it to the next free `herdstead_avatars.damaged-<time>.json`, then writes; the
  status line says where it went, and a failed write after the rename still says so. A newer file
  (`schema_version` > 2) is never read and never overwritten.
- **Writes** go to a temporary file of this save's own (process id and sequence number in the name), flushed,
  closed, then renamed over the target with `DirAccess.rename_absolute()`. On failure the old file is intact, the
  temporary file is removed, and `note` gives the path and reason (for example "is a folder"), not just an error
  code. A symbolic link (dotfiles) keeps its link and replaces its target; a chain over 8 links or a loop refuses
  the save, and a link is never replaced by a plain file. **This survives a process crash, not a power loss**: Godot
  has `flush()` but no fsync.
- In the Studio, a known slot's undrawable value shows as `<id> (not in this build)` / `#rrggbb (not in this
  build)`, an unreadable one as `<raw JSON, at most 16 characters> (not readable here)`. Both are kept when moving
  away and back; only changing the row (a new value or `0`) replaces or removes them, and the status line says
  what was removed.

### Painter templates

`make people-templates OUT=<empty dir>` runs `tools/people_templates.py`, which exports from `people.json` and the
builder's own functions (never the product manifest): `canvases/<facing>/<strip>.png` (a transparent full-size canvas
per source strip); `guides/<facing>/<strip>.png` (a separate same-size guide layer: frame edges, pivot cross, foot
line, grey over undrawn facings, a faint ghost of the white model, and brim lines on hair and headwear);
`sheets/<facing>.png` (a magnified overview); a key-colour legend (`<out>/swatches.png`: each role's three keys,
its layer, the fixed colours); `files.tsv` (each strip's size, frame, pivot, drawn columns, allowed colours, white
model or painted); the skin canvases, guides and `skins.tsv` (see "Skins"); and a README (`<out>/README.txt`, every
rule the builder checks). The output directory must be empty; painted work is never overwritten.

## Fonts, sources and licensing

- Nunito Sans (variable) comes from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/nunitosans),
  originally `NunitoSans[YTLC,opsz,wdth,wght].ttf`, unmodified, shipped as `NunitoSans.ttf` with
  `NunitoSans-OFL.txt`, which must be distributed with it. `OfficeDraw` uses the pack's font as its base, with CJK
  and missing glyphs falling back to the platform CJK font; `HudTheme` overrides only the weight of large titles.
- Tiny5 from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/tiny5) is kept with its `OFL.txt`; it is
  the pack's `display_font`, for the HUD's fixed ASCII headings only (not in the fallback chain: workspace and agent
  names can be CJK, and Tiny5 has no CJK).
- The environment's density-2 art (furniture, desk library, UI, walls, tiles, long table) is drawn by the AI painter
  (`.claude/skills/painter`, GPT Image 2.5 Sunburst): `pixelize.py` fixes canvas, pivot, palette and outline, and
  `tilefix.py` pins the connecting pixels (wood floor outer band, wall boundary rows and ports, tileable edges, the
  nine-patch middle, the table's outer columns) back onto the contract. `done_stack`, `plant_b` and `wall_frame`
  were painted new and committed exactly as `pixelize.py` wrote them (`--check` clean, no hand edits). Requests and
  candidates are not kept in the repository.
- The white model and first versions of tiles and icons come from this project's drawing scripts; every source PNG
  is directly editable. No third-party game sprites were extracted.
- Code and art are MIT licensed (`LICENSE`); Nunito Sans and Tiny5 are under the SIL OFL 1.1, and their licence
  files must be kept.
- This is a minimal, iterable asset pack, not a finished game: no real API calls, permission operations,
  scheduling or task-completion judgements.
