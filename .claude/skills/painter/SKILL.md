---
name: painter
description: Herdstead's AI painter — calls OpenAI GPT Image 2.5 Sunburst to (1) make visual drafts of a planned screen, HUD or feature before any code is written, and (2) produce pixel-art assets that meet the repo's art spec (exact canvas, pivot, palette, hard alpha, 1 px ink outline) via a generate → pixelize → check pipeline. Use it whenever the user wants to see what a design would look like, asks for a mockup / concept / visual draft, wants new or redrawn art (props, tiles, UI icons, desk items, people looks, theme packs), or mentions the painter / artist — the project's "artist" is this AI. Also use it before building a visual change so the user approves a picture, not a paragraph.
---

# Painter

The project's artist is an image model. This skill is the studio around it: a thin API client
(`scripts/paint.py`) that records provenance, and a deterministic post-processor
(`scripts/pixelize.py`) that turns a picture into a sprite the build accepts. The model is good
at composition, style and ideas; it cannot count pixels or hit exact colours. So the model
paints big, and the script does the pixel discipline.

Needs `OPENAI_API_KEY`. Run from the repo root. Python with Pillow (the repo's own dependency).

## Two jobs

| Job | Output | Where it goes | Rules |
|---|---|---|---|
| **Draft** — show a design before building it | a 1536×1024 picture of the screen / feature | `build/paint/…` or the session scratchpad; shown to the user | not an asset, never committed as art, never described as implemented |
| **Asset** — art that ships | a PNG at the contract size, palette-exact, alpha 0/255 | `art/daylight/…` only after the user approves it, then `make art` | the whole art spec (below) |

## Draft workflow

A draft is how the user approves a direction with their eyes instead of a paragraph. Use it
before building a visual change, and whenever a plan changes what the screen looks like.

1. **Get the current screen** as the base, so the draft keeps the real art style and proportions:
   `make capture OUT=<empty dir>` (needs a window, not `--headless`; ~5 min) or reuse recent
   captures. For a brand-new screen with nothing to start from, use `generate` instead of `edit`.
2. **Write the prompt to a file** (it is kept verbatim in `request.json`). Describe the layout region
   by region with the real labels and numbers, name the reference games if the user did, and end with
   the style clamp: "crisp pixel art, integer-scaled, hard edges, readable pixel font, no
   photorealism, no gradients". Templates: `references/prompts.md`.
3. **Call**:
   ```sh
   python3 .claude/skills/painter/scripts/paint.py edit \
     --image <capture.png> --prompt-file <prompt.txt> \
     --size 1536x1024 --quality high --out <empty dir>
   ```
   The model is `gpt-image-2.5-sunburst` (the default: it holds finer detail and follows edits
   more tightly). `--model flare` is faster (a flare draft took ~25 s) if the
   user asks for quick throwaway variations.
4. **Open the image and look at it** before showing it. Check that the labels say what the plan says,
   that nothing contradicts the repo's rules (e.g. answer keys shown on a bubble when the plan
   forbids it), and list what the model got wrong. Show the image to the user
   (SendUserFile if available, else the path) with those notes.
5. Iterate with edits of the draft itself (`--image <previous draft>`), one change per call. Say it
   is an AI draft; do not describe it as the implemented UI.

## Asset workflow

### 1. Find the contract first

Never guess sizes. The contract lives in the repo:
- theme pack props / tiles / UI: `art/daylight/pack.json` (`size`, `pivot`, `palette`) and
  `docs/ARTIST_BRIEF.md` §1–2 (sizes, pivots, the 10 rules that cannot move);
- the rules: `docs/ASSET_SPEC.md`, its sections on the fixed pixel and import rules and on the
  furniture and desk-item canvases and pivots;
- **the pack is density 2**: `pack.json` sizes and pivots are world units, and a repainted PNG is
  both ×2 (`window` 64×48, pivot 32,44 → a 128×96 PNG, pivot 64,88). Every `pixelize.py`
  `--size`, `--pivot`, `--fit` and `--rows` below is in PNG pixels, so ×2. A PNG still at the
  unit size is a 1x source the build fills in with 2×2 blocks (`docs/ASSET_SPEC.md`, the source-PNG
  acceptance rules under density);
- desk items: 24×24 units → a 48×48 PNG, pivot 24,44, opaque pixels only on rows 6–43 (units 3–21)
  → `--rows 6-43`;
- tiles and walls: 32×32 units → 64×64 PNGs; their join pixels are contract (below, and
  the tiles section of `docs/ASSET_SPEC.md`);
- the long-table family (`art/daylight/table/`, density 2 too): its per-pixel probes are in
  `tools/build_table_assets.py`, ×2 in the PNG; do not repaint those without reading it;
- a new semantic ID: step 0 of the replacement protocol in `docs/ASSET_SPEC.md` (pack.json entry, `make art`,
  `ArtContract` only if a scene draws it).

### 2. Paint big, in the house style — on the target grid

The one prompt rule that matters most: **tell the model the exact pixel size of the object and ask
for that many large square blocks** — at 2x, the PNG size less the margins, e.g. `door` (a 96×160
PNG, margin 2) is "exactly 92 pixels wide and 156 tall" ("exactly 16 pixels wide and 18 tall, drawn as large square
pixels on an invisible grid, no detail smaller than one block"). Asked only for "pixel art", the
model draws a 1024 px picture with pixel-ish edges and fine detail at ~15 px pitch; downsampled to
12 px wide, the paper lines of a desk stack turned into noise. Asked for the grid,
the same object downsampled cleanly. Ask for a size a little smaller than the canvas so the
outline and margins fit.

Use `edit` with 2–4 existing sprites from `art/daylight/` as references (the script upscales
small ones with NEAREST so the model sees pixels, not blobs), plus a prompt that names the
object, the view (orthographic, front, a little top surface, never isometric), top-left light,
1 px dark outline, flat colours, one object centred on a transparent background. Ask for
`--background transparent --n 3` at `--quality medium` for exploration. Template:
`references/prompts.md`.

### 3. Pixelize to the contract

```sh
python3 .claude/skills/painter/scripts/pixelize.py <image-0.png> --out <dir> \
  --size 64x96 --pivot 32,92 --margin 2 --pack art/daylight/pack.json --outline ink
```

That is `plant` at 2x (32×48 units, pivot 16,46). To keep a repaint the size the world expects,
pass `--fit` = the current sprite's opaque bounding box ×2 (measure it; a 1x source's box doubles,
a 2x one's is already in PNG pixels), unless the new object's proportions need otherwise. Desk items:
`--size 48x48 --pivot 24,44 --rows 6-43 --outline ink`.

It thresholds alpha, crops, snaps every pixel to the pack palette, downsamples by majority vote
(never averaging: that invents colours and soft edges), places the result on the pivot and
paints the outer outline. It writes `<name>.png`, `<name>.x8.png` (on light and dark ground) and
`<name>.json`. Useful knobs: `--crop x,y,w,h` to take one object out of a sheet, `--fit WxH` to
make the object smaller than the canvas, `--key auto` when the model returned an opaque
background, `--only` to restrict to a few palette names (e.g. a UI icon's colours).

`--check <png> --size WxH --pack …` validates any PNG against the same rules.

### 3b. Tiles and modules: pin the join pixels with `tilefix.py`

A tile only joins its neighbours when the pixels the build compares
(`tools/build_assets.py` `check_tile_connections`, the long table's tests) are exactly right. While a
family is only partly repainted, those pixels must be the old ones ×2. Tiles are pixelized without an
outline (`--size 64x64 --pivot 0,64`), then:

```sh
S=.claude/skills/painter/scripts
python3 $S/tilefix.py new.png --out <dir> --edges-from art/daylight/tiles/floor.wood_a.png --band 6   # wood: outer 3 units
python3 $S/tilefix.py new.png --out <dir> --ports-from <old wall> --boxes "0,0,1,32;31,0,32,32"      # seam columns, OLD's own pixels
python3 $S/tilefix.py new.png --out <dir> --tileable              # walkway, the rug's middles: opposite edges equal
python3 $S/tilefix.py new.png --out <dir> --uniform-center 8      # panel: the stretched middle is one colour
python3 $S/tilefix.py new.png --out <dir> --columns-uniform 6     # long-table module: outer 6 columns per row
python3 $S/tilefix.py rug.png --out <dir> --slice 3x3 --size 64x64 \
  --names rug.top_left,rug.top_center,rug.top_right,rug.middle_left,rug.middle_center,rug.middle_right,rug.bottom_left,rug.bottom_center,rug.bottom_right
python3 $S/tilefix.py <dir>/new.png --check-band art/daylight/tiles/floor.wood_a.png --band 6    # only check; exit 1 names the side
```

OLD may be the 1x source (scaled ×2 with NEAREST) or a 2x one; `--boxes` are in OLD's own pixels
(units for a 1x source), x1/y1 exclusive. Fixes run in a fixed order (uniform-center,
columns-uniform, tileable, edges, ports), so copied old pixels always win. Paint a family whose
modules must agree at the join (the long-table surface) as one strip and `--slice` it. It never
overwrites a file; `make art` is still the judge.

### 4. Look before you keep

Open the `.x8.png` and a side-by-side with the sprite it replaces or sits next to. At 32 px the
model's detail collapses: typical faults are a mushy silhouette, a missing outline gap, a
one-pixel speck, a colour that reads as a state signal (a green or red that looks like a
status badge). Fix small things by hand in the PNG (it is 1:1 editable) or re-run with a
different `--fit`; regenerate when the silhouette is wrong. The repo's visual rules apply:
look at 4× (a 1920×1280 window) and at 2× in the 960×640 minimum window (the visual acceptance
rules in `AGENTS.md`),
report only what you saw.

### 5. Land it (only with the user's go)

Copy the approved PNG into `art/daylight/<category>/` under its semantic ID, add the pack.json
entry if new, then `make art` and `make check` (or at least `make test-art` + `make check-packs`).
A new palette colour is added, never changed (changing one recolours every sprite that uses it):
name it as a ramp (`<name>_light / <name> / <name>_dark`), keep it at least 12 apart (RGB Manhattan)
from every other palette colour, stay within 64 colours, and give its dusk value in
`tools/palettes/dusk.json` in the same change (`tools/test_assets.py` fails a recipe that misses a key).
`art/dusk/` is derived — never paint into it. Art commits are separate from code commits, and only
one change at a time touches `art/` and `assets/`. Keep the `request.json` of the chosen image with the
review notes (not in the repo) and say in the commit message that the source was painted by
GPT Image 2.5 and pixelized; if the source line in `docs/ASSET_SPEC.md` (fonts, sources and delivery limits) no
longer describes where art comes from, update it.

## Pixel people

The people are six key-coloured layers in 1728×96 strips per facing (density 2: a 32×48-unit frame is
64×96 texels; `docs/ASSET_SPEC.md`, "Pixel people"). A model cannot hand back layered, frame-aligned,
key-colour strips, and every frame is guarded by one-unit choreography tests. So the painter paints
**skins**: one frame of the white model, repainted, which `tools/people_skins.py` cuts into the head,
torso, hair-style and hat pictures the builder's rig then wears in every frame ("Skins" in the spec).

1. `python3 tools/people_skins.py reference --facing front --out <dir>/ref.png [--wear hair_short]`:
   the white model's `stand_idle` frame 0 in key colours ×8, and the `PIXELIZE:` arguments
   (`--size 64x96 --pivot X,92 --fit WxH --stretch`: the figure's own box, and a pivot that puts it back where it
   stands, which from the side is not the frame's centre) that bring an answer back onto its texels.
2. `paint.py edit --image <ref.png> [--image <approved style draft>]`: keep the silhouette pixel for pixel,
   paint in the key colours only (skin #7ff5ff/#2fd0e0/#1690a0, top #8ff08a/#4fc84a/#2e8a2c,
   hair #ff8ae0/#d24fb0/#8e2c78, hat #ffd76a/#e0a93a/#a8741c, ink #2a2231), transparent background.
   Head and torso on a figure without hair; each hair style or hat in its own edit.
3. `pixelize.py <image> <the PIXELIZE arguments> --people art/pixel_people/people.json
   --roles <the roles in the picture> --only <those keys and the fixed colours a face may use>`: listing
   the fixed colours keeps coffee, shoe and cup from stealing texels. `--stretch` is required: the model's
   figure is a few per cent off the white model's proportions, and a kept aspect ratio lands it a texel off,
   which `cut` refuses.
4. `make people-skins CUT=<pixelized png> PARTS=head,torso DROP=1`: registration first, then refuses a foreign
   colour on a part; a part bigger than the rig's is refused unless `DROP=1` (`--drop-outside`), which drops
   those texels and prints each (the torso's neckline always misses by a texel or two). Never overwrites a skin.
5. `make art`, then look at the showroom and the office at 2x and 4x. The eyes and their catchlights are the
   rig's (a skin cannot paint inside them): do not ask for eye whites; a sclera beside the eye is hidden by
   long hair's outline.

## Cost and restraint

Each call costs money on the user's key. Rough figures at 1024×1024 (third-party pricing summaries;
check OpenAI's pricing page if it matters): low ≈ USD 0.006, medium ≈ USD 0.013, max ≈ USD 0.21 (no dollar signs here: the skill loader treats a dollar sign followed by a digit as an argument slot);
`edit` adds input-image tokens. Explore at low / medium, finish at high. Stop
and show the user after a few calls rather than looping blindly; say how many calls you made.
`request.json` has the usage of each call.

## Guard rails in the scripts

- `paint.py` refuses a non-empty `--out` and any path inside `art/` or `assets/`: raw model output is
  never an asset.
- `pixelize.py` never overwrites a file and exits non-zero from `--check` on any violation.
- Neither script prints the API key; `request.json` records model, parameters, prompt, the SHA-256 of
  every reference, timing and usage.
