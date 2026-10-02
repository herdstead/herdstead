# Items: size, placement and physical properties

Status: **phase 1 implemented** (2026-09-29): the `item` block, `ItemSpec`, the pools, and every existing prop moved
onto them with no visible change. Phases 2–4 below are planned.

## Why

An item used to be `path`, `size` and `pivot` in `art/daylight/pack.json` `props`, and nothing else; everything a
scene needed to know about how it behaves lived in code, one list per place (the desk libraries in `ArtContract`, the
floor footprints in `OfficeDecor`, the plant alternation in `OfficeDecorPlanner`, the desk-plane rule in a drawing
tool and a Godot test). A new kind of item was a code change in three to five places. The item's own facts now live
in its pack entry, checked at build time; only the *places* (a side table's top, a lane gap, a wall slot) and
how often each draws stay in code.

## The `item` block

An optional object on a `props` entry. A prop without one is placed by code by its id (door, windows, the partition kit). There is
one pack and one list: no second list in Python or GDScript.

```json
"desk_mug": {"path": "props/desk_mug.png", "size": [24, 24], "pivot": [12, 22],
             "item": {"place": "desk", "footprint": [7, 3], "group": "desk"}},
"plant":    {"path": "props/plant.png", "size": [32, 48], "pivot": [16, 46],
             "item": {"place": "floor", "footprint": [20, 10], "group": "plant"}},
"done_stack_small": {"path": "props/done_stack_small.png", "size": [24, 24], "pivot": [12, 22],
             "item": {"place": "desk", "footprint": [6, 3]}}
```

| Field | Type | Meaning | Checked |
|---|---|---|---|
| `place` | `desk` / `floor` / `wall` | What it stands on: a working plane (a side table's top in a lane gap), the floor, the top wall. | one of the three |
| `footprint` | `[w, d]` whole units | The area it occupies at its foot point: `w` centred on the pivot, `d` back from it. On the floor it is the collider and the walk obstacle (`OfficeDecor.footprint_of()`); on a desk, the plane space it takes. | `desk`, `floor`: required; 1 ≤ `w` ≤ canvas width; `d` ≥ 1 |
| `blocks` | bool | People walk round it. | `floor` only, and only `true` for now: the walk graph takes every floor footprint as an obstacle |
| `group` | id | The pool a place draws it from (`ArtPack.items_in()`, by id, never by file order). Today: a side table's top draws one piece from `desk`, or now and then (28%) from `cat`, seeded by the side table's placement key (`OfficeDecorPlanner.side_table_item()`); a wall-run pot draws from `plant` (by the place's parity). A pod of desks draws nothing from a pool. | `[a-z0-9_]+`; absent = placed by code by id only |
| `weight` | whole number ≥ 0 | Odds within its group (`ArtPack.pick()`); `0` = never drawn. Equal weights draw as one `randi_range()` over the pool. | only with a `group`; default `1` |

Any other key refuses the pack (a misspelling must not read as an absent key). `ArtPack.from_manifest()` stays the
only reader of the JSON (invariant 2); `tools/build_assets.py` `check_item()` holds the same rules at build time.

**Size is the drawing.** Invariant 6 forbids scaling at runtime, so an item's size is its art. Checked on the pixels
at build time:

| Place | Rule | Why |
|---|---|---|
| `desk` | opaque only in unit rows 3..21 of its 24-unit canvas | its foot row lands on a working plane. Today that plane is the **side table's top**: `side_table` (32×32, pivot (16, 30), `{place: floor, footprint: [28, 10]}`, placed by code by id) is solid wood over rows −23.5..−19 above its foot across its middle 16 units, and `OfficeDecor.hold()` stands the piece's foot at `OfficeDecor.TOP_Y` = −20, a unit behind the top's front edge; every `desk` and `cat` piece keeps to that middle 16 (`tools/test_office_geometry.gd`). Keeping items smaller than the 14-unit laptop is the art's choice, not a rule |
| `floor` | footprint inside the canvas width | the counters' and plants' existing rules still apply (`tools/test_assets.py`) |
| `wall` | — | the frame band's own planner checks where it fits |

**Signals stay out of the pools.** Visual-language rule 1 is unchanged: an item in a pool is furniture, drawn at
random, never from state. A signal (`done_stack_small`) has no `group`: it is placed by code by id, and `ArtContract`
refuses it in a pool. `ArtContract.ITEM_GROUPS` names the pools scenes draw from (`desk`, `cat`, `plant`), each of
which must have a member standing where it is drawn; a pool's members count as used in `PACK_UNUSED`.

## New kinds (first batch, all furniture)

Chosen to read at 2x and not to look like a state (no lamps: the task light is a signal; no paper piles:
`done_stack_small` is one; no green / red / yellow blobs).

| Group | Items |
|---|---|
| `desk` | rubber duck, small cactus, pen cup, water bottle, sticky-note cube, desk speaker |
| `gap` (lane gaps) | water cooler, low bookshelf, printer on a stand, bin, coat rack, beanbag |
| `wall` | wall clock (a fixed face), whiteboard with doodles, cork board |

## Phases

1. **Data, no visible change** (done). `item` blocks on every placed prop; `ItemSpec`; `ArtPack.items_in()` /
   `pick()`; the desk, cat and plant pools; `OfficeDecor.FOOTPRINT` gone; the desk-plane rule checked at build time;
   `tools/test_art.gd` and `tools/test_assets.py` cases. Captures identical before and after except the desk
   trinkets, reshuffled once: the pools are ordered by id (a JSON writer that sorts keys must not change a table),
   where the old lists had their own order.
2. **Desk batch.** Paint the six desk items (painter asset workflow): each is one pack entry plus `make art`.
3. **Floor and wall batch.** A `gap` pool for the lane gaps' pieces and a `wall` pool for picture slots in the
   planners; paint the nine; the planners' fit checks already refuse what does not fit. `blocks: false` with the walk
   graph learning to let a person over a floor item, if one needs it (a rug-like item).
4. **Surfaces (later, decided 2026-09-29).** A `holds` field: a cabinet or bookshelf top takes a few desk items,
   drawn as its children, the way a side table already carries one piece (`OfficeDecor.hold()`). No stacking, no carrying: the people's cup and paper stay pixels
   in the rig until a separate proposal gives them a `grip`.

Decided on 2026-09-29: the block lives in `pack.json`; the first batch is the list above; surfaces come later.
