# A UICorner on a sliced ImageLabel rounds every patch — and slice caps do not overlap

**Measured:** 2026-07-25, Studio `0.731.0.7310942`, Play Solo (Client), source stamp
`45d3b303-1710418`, rich-skinning-v2 director round 6.

Two engine facts, found together because the first one looks exactly like the
second one's absence.

## 1. Roblox CLAMPS overlapping nine-slice caps. You do not have to.

A `ScaleType = Slice` ImageLabel draws its four corner caps at
`border * SliceScale` px. The obvious worry is that a control smaller than
`2 * border` makes the two caps on an axis overlap and smear the corner art into
a blob. **It does not happen.** The engine fits the caps to the box.

Measured on `glossy_toggle_track_off` (72x32 source, `SliceCenter(14,14,58,18)`,
so 28 of combined cap on both axes), rendered at three sizes with two scales:

| box | `SliceScale = 1` | `SliceScale = extent / 28` | result |
|---|---|---|---|
| 44x24 | clean capsule | clean capsule | indistinguishable |
| 44x8 | clean capsule | clean capsule | indistinguishable |
| 20x8 | clean capsule | clean capsule | indistinguishable |

So an adapter-side "clamp `SliceScale` to `extent / (2 * border)`" guard buys
nothing and actively costs something: for a pixel package whose clamp has to
floor to a clean integer-decimation step it renders the caps SMALLER than the
engine would (pixel-quest's bar track: engine `6/16 = 0.375`, floored step
`0.25`). A guard was written, measured against the engine, and deleted.

The `2 * border < dimension` check `themes.define` runs is a statement about the
PICTURE — a slice centre with no extent stretches nothing and the engine paints a
silent blank middle. That check stays. It is not about the rendered box.

## 2. A real `UICorner` child on a SLICED ImageLabel rounds each of the nine patches

This is what actually produced the blob. Add a `UICorner` to a
`ScaleType = Slice` ImageLabel and the engine rounds **every patch
independently**: the four corner patches become diamonds, the two middle patches
become lenses, and the picture disintegrates into a cluster of rounded shapes.
Removing the `UICorner` — with everything else, `SliceScale` included, unchanged
— restores a clean capsule.

A `UIStroke` alone is harmless to the image: it draws the object's outline (a
rectangle without a `UICorner`, the rounded silhouette with one) and does not
touch the patches.

Isolating probe (one variable at a time, same art, same 44x24 box):

| row | `SliceScale` | `UICorner` | result |
|---|---|---|---|
| Z1 | 1 | no | clean capsule |
| Z2 | 24/28 | no | clean capsule |
| Z3 | 1 | **yes** | **6 rounded blobs** |
| Z4 | 24/28 | **yes** | **6 rounded blobs** |

### Why Facet hit it

`docs/lessons/stylesheet-defeat-order-sensitive.md` records that a REAL
`UICorner` child suppresses the phantom `::UICorner` rule. ADR-0020 R9's
"the image is the element" suppression turns a skinned node's corner off through
exactly that phantom rule — so it cannot reach an instance that already carries a
real one. The toggle is the one slot whose chrome is real children
(`buildToggleVisual` gives the track and knob a `UICorner` and a `Hairline` so the
palette-true switch has its pill and its edge), so it was the one slot the
suppression missed. The adapter now turns the radius and the hairline off itself
when the part is skinned, and restores them when it is not.

### The rule to carry forward

If an instance can ever wear nine-sliced art, it must not carry a real
`UICorner`. If it needs one while unskinned, the adapter owns turning it off —
no rule can, and the failure is silent, visual and only visible at small sizes.
