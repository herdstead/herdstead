# Prompt templates

Write prompts in English (the model follows English layout and style instructions more
reliably); put the user's own labels (in any language) in quotes if the picture must show them. Keep one
prompt per file so `request.json` records it verbatim.

## Draft of a screen (edit, with the current capture as `--image`)

```text
Redesign this pixel-art office app screenshot into <what, e.g. "a management-sim game screen in
the style of Theme Hospital">, keeping the same pixel-art office, the same pixel people and the
same <palette words, e.g. "warm cream / teal / wood"> palette.

Layout (landscape):
- <region 1>: <what it shows, with the real labels and numbers in quotes>
- <region 2>: …
- <world details that carry meaning: who raises a hand, what the bubble says, what is on the desk>

Crisp pixel art, integer-scaled, hard edges, readable pixel font, no photorealism, no gradients,
no lens blur.
```

Tips: name every label you care about in quotes, the model copies them; state what must NOT
appear when a rule forbids it ("the bubble has no buttons"); ask for one change per edit when
iterating on a draft.

## Block counts at 2x

The pack is density 2: a repainted PNG is its `pack.json` size ×2, and the model is asked for the
PNG size less the margins (`--margin 2` on each side for furniture). Ask for these:

| Asset | PNG (pixelize `--size`) | pivot | blocks to ask for |
|---|---|---|---|
| `window` | 128×96 | 64,88 | 124×92 |
| `door` | 96×160 | 48,152 | 92×156 |
| `sign` | 128×48 | 64,44 | 124×44 |
| `cabinet` | 96×128 | 48,120 | 92×124 |
| `plant` | 64×96 | 32,92 | 60×92 |
| `reception` | 96×64 | 48,60 | 96×60 (full width, no side margin: its opaque width is its footprint) |
| `pantry` | 128×96 | 64,92 | 128×92 (same) |
| desk items, cats, `done_stack` | 48×48 | 24,44 | about 36×36 (rows 6–43 only) |
| UI icon | 32×32 | 16,32 (`connected` 16,16) | 28×28 |
| tile / wall | 64×64 | — | 64×64 (the join pixels come from `tilefix.py`) |

Use the object's current proportions: when the old sprite's opaque box is smaller than the canvas,
ask for that box ×2 and pixelize with `--fit` of the same size.

## A theme-pack prop (edit, with 2–4 existing sprites as `--image`)

```text
Using the attached pixel-art sprites as the style reference (same outline weight, same shading,
same palette family), draw ONE <object> as a single game sprite.
View: orthographic front view with a little of the top surface visible, never isometric or
perspective. Light from the top-left, three-step shading, 1 px dark ink outline, flat colours,
no anti-aliasing, no drop shadow, no glow. The object is centred, fills the frame, and stands on
its base at the bottom. Transparent background.
Resolution: the object is exactly <w> pixels wide and <h> pixels tall. Draw it as that many LARGE
square pixels on an invisible grid (every pixel a big flat block of one colour, all blocks the
same size), so it can be downscaled to <w>x<h> without losing anything. No detail smaller than
one block.
It is furniture, not a status signal: avoid bright green / red / yellow badge colours.
```

Call with `--background transparent --n 3 --quality medium`, then pixelize each candidate and
compare. `<w>`x`<h>` come from the table above (e.g. `door`: exactly 92 pixels wide and 156 tall).

## A UI icon (16×16 units, a 32×32 PNG)

```text
A single pixel-art UI icon of <meaning>, exactly 28x28 large square pixels on an invisible grid
(no detail smaller than one block), bold readable silhouette, 1-block dark outline, at most four
flat colours, centred, transparent background, same style as the attached icons.
```

Pixelize with `--size 32x32 --pivot 16,32 --only ink,<two or three palette names>` (`connected`:
`--pivot 16,16`) so the icon stays inside the state colours the spec assigns (see
`docs/ARTIST_BRIEF.md` §5 for what each state icon must mean).

## A desk item (24×24 units, a 48×48 PNG, rows 6–43)

Same as the prop template, "a small <item> that sits on a desk top, seen from the front, a little
of the top visible", at about 36x36 pixels (or the old item's opaque box ×2). Pixelize with
`--size 48x48 --pivot 24,44 --rows 6-43 --outline ink`.

## A people look (concept only)

```text
Using the attached pixel character (front, back and side) as the exact body, pose and proportions,
redraw only the <hair / headwear / top> as <description>. Keep the head, face and body pixel-for-
pixel the same. Pixel art, 1 px dark outline, flat colours, transparent background.
```

The result is a concept for a strip author, not a strip (see SKILL.md, "Pixel people").
