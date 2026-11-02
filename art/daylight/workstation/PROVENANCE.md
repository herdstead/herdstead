# Approved whole-image workstation sources

This is the generic character, approved A desk/chair and dual-monitor animation,
not a rebuild of the old pixel-person skeleton or the modular table. There is
no rig, recolouring, resampling or compositing at runtime. The normal builder
only validates these authored images and copies their bytes. The family keeps
its own 37-colour palette; it does not extend the theme palette.

## Preserved animation and portrait

- `state-workstation.png` is a byte-for-byte copy of
  `build/reclined-wait/frames/state-workstation.png`: 640x960 RGBA, 24 row-major
  cells of 160x160 pixels, density 2, world size 80x80, pivot (37.5, 70).
  SHA-256: `f324aca6550213182c4e9b0b36a671b9d5fec6d4826c9a4aee1500e820cd248e`.
- `experiment.json` is the unmodified historical manifest from that same
  experiment. Its provenance describes the earlier experiments (including its
  then-experimental scope), not the new production integration. The palette,
  loop flags and five non-working clips are copied unchanged into `manifest.json`.
  The working-only refinement below changes its selection and timing of existing
  paintings. Static frame-0 `starting` and `unknown` aliases add no activity.
  Runtime code owns transitions between states.
- `generic-portrait.png` is the existing flattened reference from
  `build/generic-character/reference/generic-portrait.png`, copied unchanged:
  80x80 pixels, native world size 40x40 at density 2, pivot (20, 40).
  SHA-256: `58e64e8b6356495a8af88a20362d281e6401ea8c9a08cac901e3576c0422e75e`.
  It depicts the generic look, not a provider-specific or per-pane outfit.

## Quieter working motion

The working clip reuses only poses 0..7: head neutral or one texel lower,
shoulders stationary. The former two-texel head dip and moving-shoulder poses
remain in the untouched atlas but are no longer played while working.

The loop stays at 4.8 seconds with twelve hand presses (2.5 per second),
rather than the original experiment's 3.0 seconds and four presses per second.
Typing now uses three unequal phrases of 3, 5 and 4 presses, with varied hand
order and 0.08–0.14-second key holds. Hands-on-keys pauses of 0.66, 0.90 and
0.64 seconds separate the phrases instead of repeating the same four-tap beat.
This is authored timing, not random runtime jitter.

The restrained head motion is unchanged: neutral until 2.4 seconds, one texel
lower until 3.2 seconds, then neutral to the loop's end. This is one small dip
per loop rather than the original two larger dips in three seconds.
Idle, blocked entry/recline/exit, done, starting and unknown
are unchanged. This revision changes no PNG bytes, pixels, palette, pivot,
scale or runtime animation code; it adds no generated art or rig.

## Empty workstation: one offline derivation

`empty-workstation.png` was authored offline from approved pose 0, following
the chair extraction already used by `build/desk-chair-a/build_frames.py` and
`build/reclined-wait/build_frames.py`. No painter call or new generated image
was made. Coordinates below are source pixels; crop boxes exclude their right
and bottom edges.

1. Clear (0, 0, 160, 54), removing the head and shoulders. The monitors' first
   painted row is 54, which is preserved.
2. Extract (10, 151, 254, 326) from the approved A
   `build/desk-chair-a/source/selected-chair.png`
   (SHA-256 `9e0d98015313f8858f57cf57308937d96bb8ec065196b1fbb9149774c7215055`).
   Key out paper where R > 230, G > 223 and B > 196; quantize without dithering
   to this family's palette; majority-downsample to 68x34; outline opaque
   four-neighbour edges in `person.ink`. These are the pre-existing local
   Pillow helpers from `pixelize.py`, not a new image-generation request.
3. Clear (41, 102, 111, 139), removing trousers, shoes and the obscured old
   chair. Place the extracted chair's (0, 2, 68, 34) crop at (41, 102), exactly
   the registration used for the approved reclined pose. The desk lip continues
   to cover the first two chair rows. The chair back is hidden by the monitors.
4. Replace (64, 81, 76, 86) and (81, 81, 94, 86) with those same crops from
   `build/dual-monitor-typing/frames/keyboard-clear.png`
   (SHA-256 `3c975862abdd22e656c115178d816771097e5e588cb8dce0e043bd25af213278`),
   removing both keyboard hands.
5. Visual review on cream and ink exposed neck/collar remnants on the monitors'
   top edge. Restore only x=50..94 on row 54 to `person.ink` and on row 55 to
   `person.legs.0` (the adjacent grey bevel), retaining the centre seam at x=79
   in `person.eye`. Everything outside these authored regions is unchanged
   pose-0 artwork; the approved animation sheet is untouched.

Empty-image SHA-256:
`04c4ac5e6b1532c12e345091b0534687e4aada9b408ba950cbb5f475ce355a85`.

The newly exposed centre of the chair seat/gas lift/caster base in pixels
x=41..108, y=102..133 is derived from the same approved A painting, but was
previously partly hidden by the person. It warrants visual review as an
unoccupied picture; it is not claimed to be a separately approved painting.
All three runtime PNGs have hard alpha and use only the declared palette.
