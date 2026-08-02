# Compact Pointer — source art provenance

**Stage:** `rich-skinning-v2` (ADR-0020 R7 platform pair, desktop half) · **Created:** 2026-07-25 · **Seed:** `0xC0DE`

Every texture in this directory is **original, repository-owned, procedurally
generated art**. There is no external imagery, no third-party asset, and **no
trade dress**. The charter's reference for this package ("macOS-class") names a
*category* of chrome — compact ~22 px pointer controls, near-flat surfaces, 1 px
hairline borders, subtle top-lit gradients, cool greys — not any vendor's
pixels. Palette, geometry, gradient stops and border construction are invented
in `source/generate_art.py` and generated from the fixed seed `0xC0DE`.
Re-running reproduces the PNGs byte-for-byte (verified by re-run + hash compare).

This is the **desktop half of the platform pair**; `glossy-touch` is the touch
half. Same fixture, same view tree, different metric snapshot — that pairing is
the `selectBy` acceptance row.

**Contact sheet (no Studio needed):** `source/preview/contact-sheet.png` —
nine-slice stretch tests on a light backdrop (this package is designed for a
near-white window; hairlines are invisible on a dark sheet), the assembled
progress bar and switch, and a **3× nearest zoom row** so the hairlines can be
judged without a loupe.

## The look, in one rule

Hairlines are built as `outer_shape − outer_shape_inset_by_1px`. Straight runs
come out fully opaque — a true 1 px line — while corners stay smooth. Everything
is authored **at the target control height**, so nine-slice never re-scales the
gradient and the hairline never lands on a half pixel.

## Files

Slice geometry is package data: `SliceCenter = Rect(border, border, W−border,
H−border)`, `SliceScale = 1`. `—` means a whole image (never sliced).

| File | Size | Nine-slice border | Role | Slot / state |
|---|---|---|---|---|
| `compact_panel.png` | 48×48 | 12 | flat card, hairline, top lift | `panel` |
| `compact_button_default.png` | 32×22 | 8 | neutral button, 1 px drop line | `control.asset.default` |
| `compact_button_hover.png` | 32×22 | 8 | blue-tinted wash, blue-grey hairline | `control.asset.hover` |
| `compact_button_pressed.png` | 32×22 | 8 | inverted gradient, inner shade | `control.asset.pressed` |
| `compact_field.png` | 32×22 | 8 | inset well, hairline | `field.asset` |
| `compact_bar_track.png` | 48×10 | 4 | shallow trough | `barTrack` |
| `compact_bar_fill.png` | 48×8 | 3 | accent-blue fill, full width | `barFill` (`direction = "ltr"`) |
| `compact_toggle_track_off.png` | 36×18 | 8 | grey inset capsule | `toggleTrack.asset.default` |
| `compact_toggle_track_on.png` | 36×18 | 8 | accent-blue capsule | `toggleTrack.asset.selected` |
| `compact_toggle_knob.png` | 16×16 | — | small white knob | `toggleKnob.asset` |
| `compact_stepper_plate_default.png` | 22×22 | 7 | glyph plate, resting | `stepperPlate.asset.default` |
| `compact_stepper_plate_pressed.png` | 22×22 | 7 | glyph plate, pressed | `stepperPlate.asset.pressed` |

12 files, 7.4 KB total on disk.

## Notes the package-authoring stage must know

1. **Minimum rendered sizes.** `2·border` must fit inside the rendered control:
   buttons/fields ≥ 22 px tall (border 8 → 16), `barTrack` ≥ 10 px tall
   (border 4 → 8), `barFill` ≥ 8 px, `toggleTrack` ≥ 18 px, `stepperPlate`
   ≥ 22 px, `panel` ≥ 24 px. The metric snapshot for this package must not floor
   below those numbers.
2. **Do not scale this package's art.** The whole identity is 1 px hairlines; at
   `SliceScale ≠ 1` or a stretched source they become 1.4 px grey mush. It is
   authored 1:1 at the pointer metric on purpose.
3. **`compact_bar_fill.png` is X-uniform between its slice borders**, so a
   partially revealed fill and a stretched fill are the same picture.
4. **Three real button states** — default (neutral), hover (a light blue wash +
   blue-grey hairline, the desktop hover idiom) and pressed (inverted gradient +
   inner shade). They are deliberately *subtle*; the 3× zoom row on the contact
   sheet is the intended way to check them. All three reserve the same 8 px
   chrome, so R2's identical-inset rule holds.
5. **No `selection` art is shipped for this package.** On a compact pointer
   surface the honest selection affordance is the accent fill on the control
   itself plus the framework's focus ring (`chrome.focus`, ADR-0019) — inventing
   a decorative selection plate here would fight the near-flat identity. If P5
   needs a `selection` slot for coverage, reuse
   `compact_button_hover.png`/`compact_toggle_track_on.png` rather than adding
   art that contradicts the style.
6. **No icons are shipped for this package.** R4's framework fallback glyph
   table renders through the theme font, which is exactly the right look for
   near-flat desktop chrome — an ASCII-safe glyph, never a private-use codepoint.
7. **No text is baked into any asset.**
8. Metric pairing: `selectBy = { touch = glossy-touch, pointer = compact-pointer,
   gamepad = compact-pointer }`.

**Regenerate:** `<repo-root>/.venv/bin/python source/generate_art.py`
(Pillow 12.2.0, numpy 2.4.6 at creation time; any CWD works).

**Import/publishing:** upload each PNG as a Roblox Image asset and record the
returned content IDs in `upload-manifest.json` (skeleton committed with
`"contentId": null`). Another project reproducing the package uploads the same
PNGs under its own account and substitutes its IDs — no hidden assets.

**License:** same license as the repository; the art is generated by repository
code and carries no external claims.
