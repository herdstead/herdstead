# Artist brief: Herdstead theme packs

For a pixel artist who does not write code. The job is **a whole new theme**: the same 68 PNGs
(16 tiles, 22 props, 12 UI images, 18 pod-family pieces) in a new style. When you are done, run
the self-check commands and hand in one folder. The program loads your pack without a single code change.

Sizes, sources and the reasons behind them are in [ASSET_SPEC.md](ASSET_SPEC.md); this brief covers
delivery only.

---

## 1. What to deliver

Copy `art/daylight/` to `art/<your-theme-id>/`, overwrite the PNGs under the same names, and change
`id`, `name` and the colour values of `palette` in `pack.json`. Do not change the folder layout or
any file name:

```text
art/<id>/
  pack.json               <- change id / name / palette values; keep the structure
  tiles/ walls/  16       32×32 units = 64×64 PNG (walls in walls/, other tiles in tiles/; pack.json's path decides)
  props/         22       see below
  ui/            12       see below
  table/         18 + manifest.json   the pod family, see below
  fonts/                  copy as is; do not replace
```

**The pack is density 2, nearest.** One world unit is 2 texture pixels, and the office only zooms
by even factors (2×, 4×, 6×, 8×), so every texel lands on a whole number of screen pixels and is
sampled nearest-neighbour. The sizes below are in **units** (the values `pack.json` holds); the PNG
you paint is twice that (the "2x" columns). You still paint pixel by pixel: a 1 px dark outline where
shapes must separate, three-step shading lit from the top left, alpha only 0 or 255, no dithering on
large floor areas. An image not yet repainted may stay at 1x; the build fills it in with NEAREST
2×2 blocks (it plainly looks "not painted yet", see §9). The pixel people are density 2 as well
(their sizes and choreography are also in units, see [ASSET_SPEC.md](ASSET_SPEC.md), "Pixel people").

**16 tiles** (all 32×32 units = 64×64 PNG, no pivot, laid on the grid as they are):
`floor.wood_a/b/c`, `floor.walkway`,
the 9 `wall.{cap,face,front}_{left,center,right}`, `wall.side_left/right` and `wall.threshold`.
There are no rugs and no inner-wall joints: a pod stands on the floor itself, and a workspace's zone is bounded
by the partition kit below, not by walls.

**Furniture** (canvas and pivot are hard constraints; the desks, chairs and laptops belong to the
pod family, not here):

| Semantic ID | Canvas (units) | Pivot (foot point) | 2x canvas (PNG) | 2x pivot |
|---|---:|---:|---:|---:|
| `window`, `window_night` | 64×48 each | 32,44 | 128×96 | 64,88 |
| `door` | 48×80 | 24,76 | 96×160 | 48,152 |
| `plant`, `plant_b` | 32×48 each | 16,46 | 64×96 | 32,92 |
| `wall_frame` | 40×32 | 20,30 | 80×64 | 40,60 |
| `pantry` | 64×48 | 32,46 | 128×96 | 64,92 |
| `side_table` | 32×32 | 16,30 | 64×64 | 32,60 |
| `partition_v` | 6×32 | 3,32 | 12×64 | 6,64 |
| `partition_post` | 6×12 | 3,12 | 12×24 | 6,24 |
| `partition_corner_bl`, `partition_corner_br` | 32×32 each | 16,32 | 64×64 | 32,64 |
| `partition_h` | 32×10 | 16,10 | 64×20 | 32,20 |

`plant` and `plant_b` are two pots of the same fixture; `window_night` is `window` with the view dark, its
frame pixel for pixel the same. `pantry` stands in the entry
band: its opaque width is the whole canvas (it is its footprint), the bottom outline sits one
row above the foot point, and the foot point row and below stay transparent.

**The partition kit** is the low wall round a workspace's zone, a U open at the top: `partition_v` runs down
each side (one per 32-unit row, so its top and bottom rows must join), `partition_h` along the bottom
(joining left and right), `partition_corner_bl` / `_br` turn the two bottom corners, and `partition_post`
caps each side run's top end (the zone's sign hangs from the left one). Keep the horizontal pieces no taller
than 10 units and the vertical ones 6 wide with nothing overhanging: they must never hide a seated person.
`side_table` is a small table that stands on the floor and carries one desk item on its top: keep the top's
middle 16 units flat and solid about 20 units above the foot point, where the item's foot lands.

**Desk items**: 5 everyday objects `desk_mug`, `desk_notebook`, `desk_papers`, `desk_plant`,
`desk_headphones`, 3 white-cat poses `cat_loaf`, `cat_sleep`, `cat_sit`, and `done_stack_small`, each
24×24 units, pivot 12,22 (2x: 48×48, pivot 24,44). A side table puts an item's foot point on its
top, so **opaque pixels may only fall on rows 3–21** (the top three rows and the two rows below the
foot point stay empty; rows 6–43 in the 2x PNG).
`done_stack_small` is a signal, not decoration: it is the small paper stack beside a done agent's laptop (§5),
6 units wide and 9 tall over its foot point, so it fits between the laptop and the edge of a 32-unit desk.

**The pod family** (`table/`): four desk modules, the low screen (three), the apron (three),
the bracket, chair front and back,
laptop front and back and the `$_` marker views, 17 images, also density 2 (canvas = units ×2).
The build derives none of them: it validates the 17 source PNGs and copies them as they are. A `shell_*`
view is its `monitor_*` with the `$_` mark, made by `shell_mark()` in `tools/build_table_assets.py`, which
only the template generator runs (`make table-templates`, on the monitors it has just drawn). So do not
paint a shell freehand, and when you repaint a monitor, derive its shell from it again the same way:
the silhouette stays the monitor's and the cursor's probe point is contract. Each image's canvas and the
pixels it must keep (which desk rows are transparent, the chair and laptop
probe points) are in "Open floor and pods" of [ASSET_SPEC.md](ASSET_SPEC.md) and in the notes of
`tools/build_table_assets.py`; `make test-art` checks every one.

The first versions of the desk items and the pod family were drawn by a program
(`make pixel-sources OUT=<empty dir>`); you can repaint the same-named PNGs directly over them.

**The people in the office are not in this pack.** They are the pixel people shared by every theme
(`art/pixel_people/`); you deliver no character images. You only name which animation each state
uses in `pack.json`'s `states` (§4).

**12 UI images**: 9 icons of 16×16 (`working`, `blocked`, `unread`, `idle`, `unknown`, `offline`,
`starting`, `branch`, `connected`), pivot 8,16, except `connected` at 8,8; `panel` and `hud_panel`
32×32, pivot 0,0, nine-patch margins `[4,4,4,4]` (`panel` light, for the world's chips and signs and the tools;
`hud_panel` dark, for every HUD panel); `selection_seat` 32×48, pivot 16,46 (four corner marks round a seat).
(All in units; 2x PNG: icons 32×32, `panel` and `hud_panel` 64×64 (margins of 8 texels; the middle is
stretched, so it must be one flat colour), `selection_seat` 64×96.)

---

## 2. What cannot change

1. **Canvas sizes.** The build checks every number in the tables above, image by image; 1 px off is
   rejected. To paint finer detail, raise the density of the whole pack (§9); do not change the numbers.
2. **Pivots.** The pivot is the foot point; the program places each image at `offset = -pivot`.
   Move a pivot and the furniture drifts.
3. **Semantic IDs.** `pack.json` is the pack's inventory, and the build checks every PNG against it;
   it does not demand one fixed set of IDs. But the ones the scenes draw must be there: one missing
   and `make check-packs` reports `tiles/props/ui/states: no ...` (the list is in
   `scripts/art/art_contract.gd`). Extra IDs are not an error; `make check-packs` lists them under
   `PACK_UNUSED:` (a reminder that nothing draws them).
4. **The pivot lies inside the canvas**: `0 ≤ pivot ≤ size` (a foot pivot exactly at the height is allowed).
5. **Palette key names: more is fine, fewer is not.** Drop one the program uses and it reports
   `palette: no colour named <key>`; adding your own keys is fine.
6. **Hard alpha**: only 0 or 255. No soft edges, no baked shadows or glows.
7. **Palette discipline**: every opaque pixel must **exactly equal** one of the colours in
   `pack.json`'s palette. Fix the palette first, then paint; do not pick colours as you go.
8. **No holes in floors and walls**: `floor.*`, `wall.cap_*` and `wall.face_*` are fully opaque.
9. **The outer 3 px of the three wood-floor variants must be identical**, or the random floor shows seams.
10. **The people are not drawn by this pack.** They are the shared pixel people (`art/pixel_people/`,
    one set for every theme). A pack only names an animation in `states`, and the name must be one
    that `state_tracks` in `art/pixel_people/people.json` maps for both postures.

### Palette keys you cannot darken freely

These keys serve both as large surfaces and as text or icon colours, and the program cannot
separate the two. Take care in a dark theme (the retired Dusk Shift was tuned this way):

| Key | Used for | Constraint |
|---|---|---|
| `ink` | every outline **and body text** | must stay dark |
| `cream` | walls, sign faces, top-bar status text, the idle / starting badge ground | must not get too dark |
| `paper` | the staff panel ground, the top-bar title | must stay light |
| `floor` | the floor **and the ground behind station name plates** | at least 4.5:1 against `ink` |
| `blocked` | the blocked badge **and the selection frame** | keep it saturated; it must jump off the floor |
| `muted` | the theme name in the top bar | at least 4.5:1 against the dark top-bar ground (`#26363b`) |

The top-bar ground comes from `default_clear_color` in `project.godot` and **does not change with the theme**.

---

## 3. What is free

- Every palette colour value (49 today; keep the key names, change the values as you like).
- All pixel content: shapes, materials, texture, lighting, season, time of day.
- New palette keys (the program only requires the ones it knows to exist).
- Atlas cell positions (`tiles.*.cell` in `pack.json`) may be rearranged; the program looks tiles up
  by semantic ID. **But a TileMapLayer painted and saved in the editor stores coordinates**: a
  rearrangement must migrate those.
- Animation timing: each animation's `fps` and `durations` in `pack.json`.
- **Optional**: a top-level key `"stale_modulate": "8f96b8"` (6 lower-case hex digits) sets the tint
  of the whole office while herdr is disconnected. Without it the built-in 0.65 grey is used. A dark
  theme should give its own bluish, lightly darkening value, or the disconnected office turns into a black blur.
- **Optional**: a top-level key `"task_lights": "strong"` draws the desk task lights and chair
  contact shadows harder, for a lamp-lit dark theme. Without it they are at daylight strength
  (`"soft"`). Both keys are purely additive optional fields; see the replacement protocol in
  [ASSET_SPEC.md](ASSET_SPEC.md).

---

## 4. The four animation names

Every entry in `pack.json`'s `states` names an animation. The names available are set by the shared
pixel people, in `state_tracks` of `art/pixel_people/people.json`. Today there are four:

| Animation | When it plays |
|---|---|
| `idle` | sits with eyes open, blinks now and then |
| `working` | types with alternating hands |
| `blocked` | raises one hand, waiting for an answer |
| `starting` | a still ready pose, shown together with the hourglass badge |

These names cannot change, and a pack cannot invent new ones: the build checks them against that manifest.

---

## 5. What the state badges mean

This section matters more than style. **Wrong meaning is worse than ugly art.**

| herdr state | Animation | Badge | Meaning |
|---|---|---|---|
| `working` | working | `working` | active. It does **not** mean we know what command it is running |
| `blocked` | blocked | `blocked` | needs a person to look. The reason is unknown, so do not invent one |
| `done` | idle | `unread` | **UNREAD = nobody has looked yet, not "task succeeded"**. No trophies, ticks or fireworks |
| `idle` | idle | `idle` | standing by. Something neutral, like an ellipsis |
| `unknown` | idle | `unknown` | we do not know. Do not suggest success or failure |

`starting` (launching) and `offline` (connection lost) are presentation overlays, not herdr states.
`offline` must read at a glance as "this data is old" and **must never look like idle**.
The same goes for `done_stack_small`: it sits beside a done agent, so it means UNREAD, not success.

---

## 6. Self-check

Run these yourself when you finish; do not wait for a programmer.

The first time you need Python 3.11+ and Pillow:

```sh
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements.txt
```

```sh
# 1) Build and check every contract. Any violation fails here, naming the image and the rule it breaks.
.venv/bin/python tools/build_assets.py --source art/<id> --output assets/<id>

# 2) The contract regression tests, run against your pack
.venv/bin/python tools/test_assets.py --source art/<id> -v

# 3) The full inventory: furniture laid on light and dark ground, to check the hard alpha edges
.venv/bin/python tools/contact_sheet.py --source art/<id> --output /tmp/<id>-sheet.png

# 4) Guide sheets with canvas frames and pivot crosses (--blank gives empty templates)
.venv/bin/python tools/artist_templates.py --source art/<id> --output /tmp/<id>-templates

# 5) Let Godot import, and confirm the new pack has every semantic ID the scenes need
make import
make check-packs

# 6) See it for real; in the window press T to see it by night, - / = to change the zoom
godot --path . -- --pack=res://assets/<id>/manifest.json --read-only
godot --path . scenes/preview.tscn -- --pack=res://assets/<id>/manifest.json
godot --path . scenes/preview.tscn -- --pack=res://assets/<id>/manifest.json --offline
```

The last command's `--offline` is there to check your `stale_modulate`: the disconnected office must
still show readable text and badges. `--read-only` on the office keeps it from ever writing to a
herdr session running on your machine.

**Recolouring without reshaping** by a recipe (the retired Dusk Shift) is no longer supported: a new
theme is its own pack, copied from `art/daylight` and repainted.

---

## 7. Templates

`docs/templates/` holds guide sheets generated from `pack.json` (canvas frames, pivot crosses, an
8 px grid, semantic IDs and sizes):

- `tiles.png`: the tiles and their atlas coordinates
- `props.png`: the furniture canvases and pivots
- `ui.png`: the UI images, including `panel`'s nine-patch margins

Each sheet shows exactly what `pack.json` lists; one more entry adds one more panel.

Regenerate with `--blank` for a set of empty canvases to sketch on.

### People templates

The people in the office are the shared pixel people (`art/pixel_people/`) and are not on these
sheets. **Export the pixel-people artist templates with `make people-templates OUT=<empty dir>`**:
one blank canvas per facing and source strip, guides for frame cells and the foot line, a key-colour
legend, and a README that states every rule the builder checks. Parts, layers and key colours are in
[ASSET_SPEC.md](ASSET_SPEC.md), "Pixel people".

---

## 8. How to hand in

Hand in the whole `art/<id>/` folder (PNGs + `pack.json`), plus a screenshot or paste of the output
of steps 1 and 2 in §6. Do not hand in `assets/<id>/` (a build product the program generates itself).
Do not touch `art/daylight/`: it is the reference pack every other theme is copied from.

---

## 9. Finer detail: density (schema v2)

Every size above is in **units** (the density-1 values; one tile is 32). The shipped pack is
**density 2** (second row below), and so are the pixel people (their own asset family, see
[ASSET_SPEC.md](ASSET_SPEC.md), "Pixel people"). Each pack picks one density for all its images:

| Density | One tile | 16×16 icon | `panel` | `selection_seat` |
|---:|---:|---:|---:|---:|
| 1 | 32×32 | 16×16 | 32×32 | 32×48 |
| 2 (the shipped packs; pixel people) | 64×64 | 32×32 | 64×64 | 64×96 |
| 4 | 128×128 | 64×64 | 128×128 | 128×192 |
| 8 (maximum) | 256×256 | 128×128 | 256×256 | 256×384 |

**Your canvas = the numbers in §1 × density.** Furniture too: `door` at density 4 is 192×320.

What you deliver is exactly what the runtime samples: the program never shrinks or resamples images
on the CPU for the screen zoom. The lowest zoom is 2, so a density-2 `nearest` pack is never
minified, and its `.import` files keep the project default `mipmaps/generate=false`. Only a pack
whose density is above the lowest zoom (4, 8), or a `linear` pack, is minified by GPU mipmaps when
the zoom is below its density (every `.import` of such a pack then says `mipmaps/generate=true`; see
[ASSET_SPEC.md](ASSET_SPEC.md), "Import policy by asset family"). This does not make the picture
"sharper": how many screen pixels a unit gets is set by the zoom, not by the density. Density decides
whether there is detail left to see when the zoom goes up.

**Do not change any number in `pack.json`.** `size`, `pivot`, `tile_size` and the nine-patch
margins all keep their density-1 values; the program multiplies by the density. `door`'s pivot is
`24,76` at every density.

### Getting started

```sh
# Make a new density-4 pack, keeping the PNGs at their current size for now
.venv/bin/python tools/upscale_pack.py --source art/daylight --output art/<id> --density 4 --manifest-only
.venv/bin/python tools/build_assets.py --source art/<id> --output /tmp/<id>
```

This pack **passes every check at once**; its build output is just enlarged blocks, which is what
"not painted yet" looks like. Then **replace images one at a time**: each replacement adds detail,
the ones not replaced are still enlarged by the build, and the pack stays valid at every step.

Sizes may be mixed: a 32 px, a 64 px and a 128 px image are all accepted in the same density-4 pack
(each must be exactly 1, 2, 4 or 8 times its contract size, and no more than the pack's density).

### Which rules relax

`pack.json` may set `"filter"`: at density 1 it can only be `"nearest"`; above density 1 the default is `"linear"`.

| | `"nearest"` (pixel art, the rules of §2) | `"linear"` (painted style) |
|---|---|---|
| Translucency | no; alpha only 0 or 255 | free; soft edges and shadows are fine |
| Colours | every opaque pixel exactly equals a palette colour | free |
| Palette keys | each value is 6 lower-case hex digits | the same; the keys the scenes need are required in both modes |
| Wood-floor variant edges | checked pixel by pixel | not checked, but **you must still make the three join** |

The other rules of §2 (no holes in floors, pivot inside the canvas, semantic IDs, ...) apply in both
modes, checked at the size you actually painted.


### Guide sheets at any density

```sh
.venv/bin/python tools/artist_templates.py --source art/<id> --output /tmp/<id>-templates --density 4 --scale 1
```

The canvas frames, pivot crosses and 8 px grid scale to the size you actually paint (lower
`--scale`, or the sheets get very large).
