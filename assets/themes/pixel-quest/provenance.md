# Pixel Quest — source art provenance

**Stage:** `rich-skinning-v2` (ADR-0020 R5, pixel mode) · **Created:** 2026-07-25 · **Seed:** `0x8B17`

Every texture in this directory is **original, repository-owned, procedurally
generated art**. There is no external imagery, no third-party asset, and no game
or OS trade dress. The single source is `source/generate_art.py`, which writes
flat blocks of a fixed 12-colour palette onto a hard design-pixel grid — no
noise, no blur, **no anti-aliasing anywhere**. Re-running reproduces the PNGs
byte-for-byte (verified by re-run + hash compare).

**Contact sheet (no Studio needed):** `source/preview/contact-sheet.png` — every
nine-slice rendered NEAREST at three sizes, the assembled HP bar at 12/50/100 %,
and the palette strip.

## The pixel discipline (what makes this package correct)

* **`pixelUnit = 4`.** Art is authored in DESIGN pixels and saved at 4 image px
  per design px (NEAREST upscale). Every PNG contains only flat 4×4 blocks, so
  `ResampleMode = Pixelated` renders it exactly and `SliceScale` stays integral.
* **Every sliced source is `2·border + 1` DESIGN pixels on each sliced axis.**
  That makes the stretched centre exactly ONE design pixel, so any target size
  replicates a single uniform colour. This is what structurally prevents the R5
  failure mode ("sharp but unevenly sized pixels" — crisp in a capture, wrong on
  a device). It is a hard authoring rule for this package, not a coincidence.
* All slice borders below are therefore `4 × border_dp`.
* Snapshot metrics should snap to multiples of 4 (R5); the preview sizes in the
  generator are all multiples of 4 for the same reason.

**Palette (12):** `INK #16121F`, `SHADE #3A2C4F`, `WOOD_D #6B4326`,
`WOOD #A8722F`, `TAN #D7A860`, `CREAM #F4E6C0` (6 chrome values) plus two 3-step
accent ramps — `RED_D #7A1F22 / RED #C8402F / RED_L #E8735A` and
`GRN_D #2F6B2A / GRN #4FA83F / GRN_L #8EDE6A`. Icons use `#F0F0F0`.

## Files

| File | Size (px) | Design px | Nine-slice border | Role | Slot / state |
|---|---|---|---|---|---|
| `pixel_plate_default.png` | 36×36 | 9×9 | 16 (4 dp) | wood plate, corner rivets | `control.asset.default` / `selection.asset.default` |
| `pixel_plate_selected.png` | 36×36 | 9×9 | 16 (4 dp) | light gilt plate, double ring, notched corners, ruby studs | `selection.asset.selected` |
| `pixel_plate_ornament.png` | 24×24 | 6×6 | — | ruby jewel ornament | `selection` → `layers kind="corners"` on the SELECTED state |
| `pixel_blank.png` | 24×24 | 6×6 | — | **entirely transparent** | the same `corners` layer's `default` — see note 3 |
| `pixel_panel.png` | 52×52 | 13×13 | 24 (6 dp) | window chrome, corner rivets | `panel.asset` (or `layers[1] kind="fill"`) |
| `pixel_field.png` | 36×36 | 9×9 | 16 (4 dp) | inset text well | `field.asset` |
| `pixel_bar_track.png` | 20×32 | 5×8 | 8 (2 dp) | carved HP rail | `barTrack` |
| `pixel_bar_fill.png` | 12×16 | 3×4 | 4 (1 dp) | full-width HP fill | `barFill` (`direction = "ltr"`) |
| `pixel_bar_cap_heart.png` | 40×40 | 10×10 | — | heart end-cap | `barCap.start` |
| `pixel_toggle_track_off.png` | 28×32 | 7×8 | 12 (3 dp) | dark channel | `toggleTrack.asset.default` |
| `pixel_toggle_track_on.png` | 28×32 | 7×8 | 12 (3 dp) | green channel | `toggleTrack.asset.selected` |
| `pixel_toggle_knob.png` | 24×24 | 6×6 | — | cream knob | `toggleKnob.asset` |
| `pixel_stepper_plate_default.png` | 28×28 | 7×7 | 12 (3 dp) | glyph plate, raised bevel | `stepperPlate.asset.default` |
| `pixel_stepper_plate_pressed.png` | 28×28 | 7×7 | 12 (3 dp) | glyph plate, inverted bevel | `stepperPlate.asset.pressed` |
| `pixel_icon_chevron_right.png` | 32×32 | 8×8 | — | near-white glyph | `icons["chevron.trailing"]` |
| `pixel_icon_chevron_down.png` | 32×32 | 8×8 | — | near-white glyph | `icons["chevron.down"]` |
| `pixel_icon_plus.png` | 32×32 | 8×8 | — | near-white glyph | `icons["stepper.increment"]` |
| `pixel_icon_minus.png` | 32×32 | 8×8 | — | near-white glyph | `icons["stepper.decrement"]` |
| `pixel_icon_check.png` | 32×32 | 8×8 | — | near-white glyph | `icons["check"]` |
| `pixel_icon_cross.png` | 32×32 | 8×8 | — | near-white glyph | `icons["close"]` |

20 files, 2.9 KB total on disk (the whole package is smaller than one ornate PNG).

## Notes the package-authoring stage must know

1. **`identity.rendering = "pixel"`, `identity.pixelUnit = 4`.** Every emitted
   image rule must carry `ResampleMode = Pixelated`; without it these PNGs turn
   to mush and the package is worthless.
2. **Selected is a different plate, not a tint** — different face value (light
   gilt vs mid wood), a second frame ring, notched corners and ruby studs. The
   chrome inset is 4 dp in BOTH states, so R2's identical-inset rule holds.
3. **Literal "side ornaments" ship as a `corners` layer**, not baked into the
   sliced plate: the left/right slice bands stretch vertically, so a mid-edge
   ornament would smear. `pixel_plate_ornament.png` is the corner asset (the
   contact sheet shows it anchored with a 4 px overhang, which is the intended
   look). The ornaments belong to the SELECTED state only, and the per-state
   asset grammar requires a `default` — so the layer's `default` is
   `pixel_blank.png`, 24×24 of pure transparency. That is the package saying
   "nothing here", explicitly, instead of shipping a dimmed jewel and hoping the
   tint hides it (added by P5 while wiring the shipping package; the generator
   reproduces every earlier PNG byte-for-byte alongside it).
4. **`pixel_bar_fill.png` is uniform along X** — every column is identical — so
   any reveal percent looks the same. The track's vertical centre band is also
   uniform, so a taller bar stretches cleanly.
5. **`pixel_bar_cap_heart.png` is a separate cap layer**, per rs-m4: it must
   survive all percents and therefore is never part of the clipped fill art.
6. Only ONE toggle knob is shipped (no pressed variant) — at 6 design pixels
   across there is no legible way to draw a "pressed" knob that is not just a
   different colour, and R2's tint rules already cover that honestly.
7. **No text is baked into any asset.**
8. Suggested `iconSizes` role: 32 px (1:1); any other size must be a multiple of
   4 or the glyphs stop being on-grid.

**Regenerate:** `<repo-root>/.venv/bin/python source/generate_art.py`
(Pillow 12.2.0, numpy 2.4.6 at creation time; any CWD works).

**Import/publishing:** upload each PNG as a Roblox Image asset and record the
returned content IDs in `upload-manifest.json` (skeleton committed with
`"contentId": null`). Another project reproducing the package uploads the same
PNGs under its own account and substitutes its IDs — no hidden assets.

**License:** same license as the repository; the art is generated by repository
code and carries no external claims.
