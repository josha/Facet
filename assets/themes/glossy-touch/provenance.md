# Glossy Touch — source art provenance

**Stage:** `rich-skinning-v2` (ADR-0020 R7 platform pair, touch half) · **Created:** 2026-07-25 · **Seed:** `0x6E43`
(bumped from `0x6E11` → `0x6E27` in the **director art round, 2026-07-25** — see “The bar re-cut” — and
`0x6E27` → `0x6E43` in the **director round of 2026-07-26** — see “The switch re-cut”)

Every texture in this directory is **original, repository-owned, procedurally
generated art**. There is no external imagery, no third-party asset, and **no
trade dress**. The charter's reference for this package ("iOS-6-class") names a
*category* of chrome — glossy skeuomorphic touch controls, vertical gradients,
gel highlights, capsule switches, 44 px rows — not any vendor's pixels. The
palette, geometry, gradient stops, gloss construction and stripe period below
are all invented in `source/generate_art.py` and generated from the fixed seed
`0x6E43`. Re-running reproduces the PNGs byte-for-byte (verified by re-run +
hash compare).

This is the **touch half of the platform pair**; `compact-pointer` is the
desktop half. Same fixture, same view tree, different metric snapshot — that
pairing is the `selectBy` acceptance row.

**Contact sheet (no Studio needed):** `source/preview/contact-sheet.png` —
nine-slice stretch tests, the tiled stripe seam check, the striped progress bar
at 20/60/100 %, and the assembled switch in both states.

## The look, in one rule

The house "gel" is a **two-segment vertical gradient with a hard VALUE STEP at
48 % height** (the gloss line), plus a white sheen ramp over the upper segment
and a 1 px white inner rim. Because it is a function of *y only*, it is
nine-slice safe: nothing varies along a stretched axis.

## Files

Slice geometry is package data: `SliceCenter = Rect(border, border, W−border,
H−border)`, `SliceScale = 1`. `—` means a whole image (never sliced).

| File | Size | Nine-slice border | Role | Slot / state |
|---|---|---|---|---|
| `glossy_panel.png` | 96×96 | 28 | rounded card, soft gradient, drop shadow | `panel` |
| `glossy_button_default.png` | 64×44 | 16 | gel button, resting | `control.asset.default` |
| `glossy_button_pressed.png` | 64×44 | 16 | dark slab, gloss killed, inner shade | `control.asset.pressed` |
| `glossy_field.png` | 64×44 | 16 | inset well, top inner shadow | `field.asset` |
| `glossy_bar_track.png` | 96×24 | 10 | deep inset trough, hard rim + lit lower lip | `barTrack` |
| `glossy_bar_fill.png` | 96×24 | 8 | blue gel fill, full width | `barFill` (`direction = "ltr"`) |
| `glossy_stripe_tile.png` | 24×24 | — (tile 24×24) | 45° stripes, 8 px period, lit band + shaded edge | `barTrack` → `layers kind="tile"`, `tileSize = {24,24}` |
| `glossy_toggle_track_off.png` | 72×32 | 14 | grey inset capsule | `toggleTrack.asset.default` |
| `glossy_toggle_track_on.png` | 72×32 | 14 | green gel capsule | `toggleTrack.asset.selected` |
| `glossy_toggle_knob.png` | 30×30 | — | chrome gel knob | `toggleKnob.asset` |
| `glossy_stepper_plate_default.png` | 44×44 | 14 | chrome glyph plate | `stepperPlate.asset.default` |
| `glossy_stepper_plate_pressed.png` | 44×44 | 14 | blue glyph plate, inset | `stepperPlate.asset.pressed` |
| `glossy_selection_default.png` | 72×44 | 18 | quiet unselected plate | `selection.asset.default` |
| `glossy_selection_selected.png` | 72×44 | 18 | blue gel + outer glow | `selection.asset.selected` |

14 files, 22 KB total on disk.

## Notes the package-authoring stage must know

1. **Sources are authored AT the 44 px touch-row height** (`64×44`, `72×44`),
   not square. A 64×64 source with border 16 squeezes the gel's gloss step into
   the 12 px stretched centre band and the whole look degrades to a soft
   gradient. This was measured on the contact sheet, not assumed.
2. **`glossy_bar_fill.png` is border 8 on a 24 px-tall source** (16 < 24). An
   earlier draft used border 10 on a 20 px source, which makes `2·border == height`
   and leaves the sliced centre rect EMPTY — a silent blank-centre bug. 24 is
   this package's own `controls.progress.trackHeight`, so the fill is 1:1
   vertically at every width (see “The bar re-cut”).
3. **`glossy_bar_fill.png` is X-uniform between its slice borders** (the script
   broadcasts the centre column), so a partially revealed fill and a stretched
   fill are the same picture at every percent.
4. **The diagonal stripes are a TILE layer, not a striped sliced fill.** The
   charter asks for a "striped full-width fill"; diagonal art cannot survive a
   nine-slice stretched centre, so the honest shape (and the one that also
   demonstrates R1's `tile` kind and the rs-m1 `TileSize` finding) is:
   `barTrack` = the gel trough, plus a `tile` layer above it carrying
   `glossy_stripe_tile.png` at `tileSize = {24,24}`; the gel `barFill` draws over
   that, so a player sees a solid head against a hatched trough. The tile is
   seamless on both axes with an 8 px stripe period (3 cycles per tile, an exact
   divisor — verified on the contact sheet's 10×3 seam check), and being
   transparent-backed it also works as a pinstripe over any surface.
5. **Content insets are identical across state variants** (button
   default/pressed; selection default/selected), so R2's no-reflow check passes.
6. The knob is a whole image; **knob travel stays solver-owned** — the art never
   moves geometry (R3).
7. **No text is baked into any asset.**
8. Metric pairing: this package's snapshot is the 44 px touch snapshot; the
   sibling `compact-pointer` is ~22 px. `selectBy = { touch = glossy-touch,
   pointer = compact-pointer, gamepad = compact-pointer }`.

## The bar re-cut (director art round, 2026-07-25)

The director reviewed the desktop row live and reported that the glossy
download/progress bar "reads poorly against the quality bar of the compact /
macOS-class reference imagery". Three defects, all geometry rather than taste,
and all fixed in `generate_art.py` at the new seed `0x6E27`. Every other texture
in this package regenerates byte-identically.

1. **The trough was not a trough.** The well was drawn between `y=2` and
   `y=h-3`, so only 20 of the 24 authored pixels carried art, and its ramp ran
   196 → 248 — a 52-level spread that is invisible beside a near-white page. It
   now uses the full 24 px, runs 138 → 245 with the DARK end at the top (which is
   what makes an inset read as inset), carries a deeper top inner shadow, a hard
   1 px `EDGE` rim and a 1 px white bevel on the bottom inside lip. Two crisp
   lines, not one soft ring — that is what survives at 24 px.
2. **The gel step was inside a stretched band.** The fill was authored 20 px tall
   and DRAWN 24 (`controls.progress.trackHeight`), so nine-slicing stretched its
   middle 4 rows to 8 and the hard gloss step — the entire house look — smeared
   into a soft gradient. This is note 1 above, one control down from the button
   it was written for. Authored at 24 it is 1:1 vertically at every width. The
   ramp also deepened (`BLUE_GEL`, split 0.44, sheen 0.40, a darker seat under
   the gloss) because a 24 px bar shows a quarter of the pixels a 44 px button
   does. Its `sliceCenter` therefore moved to `{8, 8, 88, 16}`.
3. **The stripe was one low-contrast cycle.** A 12 px period at 0.55 white over a
   24 px bar is a single hatch cycle with almost no local contrast — "muddy" at
   exactly the scale the director was looking at. The period is now 8 (3 cycles
   per tile, still an exact divisor of 24 so both axes still seam), and each
   stripe is a PAIR: a 3 px lit band at 0.55 white with a 2 px shaded leading
   edge at 0.30. Contrast between two marks survives downscaling in a way one
   translucent mark does not, and the shaded half keeps the trough recessed
   rather than brighter than the page behind it.

The contact sheet's striped-progress row was also wrong and is fixed: it
composited the stripe over the FILL, while the package declares it as
`barTrack`'s second layer. It now composes as shipped.

**Re-uploaded 2026-07-25** (Studio MCP `upload_image`, same local http.server
method): `glossy_bar_track.png`, `glossy_bar_fill.png`, `glossy_stripe_tile.png`.
New content IDs are in `upload-manifest.json`; the other eleven are unchanged.

## The switch re-cut (director round 8, 2026-07-26 — seed `0x6E43`)

**Reported:** the ON toggle highlight is GREEN; it should be BLUE — the package's
own accent identity.

The art was the defect, not the framework. `toggle_track("on")` painted the
`GREEN` gel ramp with a `GREEN_BOT` rim, and green appears **nowhere else in this
package**: the palette's `accent` is `rgb(18, 92, 190)`, the selection plate is
the `BLUE` gel, the pressed stepper plate is `BLUE_DEEP` and the progress fill is
`BLUE_GEL`. A green switch belonged to no theme — it was a borrowed traffic
light in a package whose whole identity is a cool blue action colour.

**The re-cut is one substitution and nothing else:** the ON capsule now uses the
same `BLUE` ramp and `BLUE_BOT` rim the selection plate uses, at the same sheen
(0.22). Geometry, slice border (14), size (72×32), the OFF state and the chrome
gel knob are all untouched — a white knob reads on blue for exactly the reason it
read on green. `GREEN` / `GREEN_BOT` remain in the palette block, unused, because
deleting a ramp would rewrite the file's history for no benefit.

**Verified byte-scope:** at the new seed only `glossy_toggle_track_on.png` moves
(sha256 `162394fd…` → `06f2e80a…`); the other thirteen textures re-generate
byte-identically, checked by hashing the whole directory before and after.

**Re-uploaded 2026-07-26** (Studio MCP `upload_image`, same local http.server
method): `glossy_toggle_track_on.png` → `rbxassetid://98206529376640`. Recorded
in `upload-manifest.json` under `reuploaded`; the other thirteen are unchanged.

## The selected surface is a PALETTE fact, not only an art one (director round 8)

The same round changed one colour in `examples/themes/glossy_touch.luau`:
`extra.controlSelected` moved from `rgb(188, 214, 250)` — a pale blue this
package draws nowhere — to `rgb(20, 81, 194)`, which is what its selection plate
**measures** in the rows a lifted label occupies (`glossy_selection_selected`
under `$ChromeTintSelected`, median over the 25-row glyph band; live-measured
`rgb(36, 78, 186)` on the shipped bar at 1233×1067).

That is not decoration. `$ControlSelected` is what the framework paints for an
UNSKINNED selected row and what it derives `$OnSelected` from, so a package whose
palette claims one selected surface while its art paints another gets a label
nobody can read — which is exactly what happened: `$Content` on the blue gel
measured **3.74:1**, under the contract's 4.5 floor. With the palette telling the
truth the framework picks `onAccent`, and white on that plate measures **7.31:1**
(4.45–7.96 across the glyph band, versus 2.10–3.75 for the dark content colour on
every single row).

**Regenerate:** `<repo-root>/.venv/bin/python source/generate_art.py`
(Pillow 12.2.0, numpy 2.4.6 at creation time; any CWD works).

**Import/publishing:** upload each PNG as a Roblox Image asset and record the
returned content IDs in `upload-manifest.json` (skeleton committed with
`"contentId": null`). Another project reproducing the package uploads the same
PNGs under its own account and substitutes its IDs — no hidden assets.

**License:** same license as the repository; the art is generated by repository
code and carries no external claims.
