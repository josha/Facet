# Fantasy Ornate — source art provenance

**Stage:** `rich-skinning-v2` (ADR-0020) · **Created:** 2026-07-25 · **Seed:** `0x60D1`

Every texture in this directory is **original, repository-owned, procedurally
generated art**. There is no external imagery, no third-party asset, and no game
or OS trade dress. The single source is `source/generate_art.py`: bevelled gold
masks, guilloche/bead moulding, parametric acanthus scrolls, jewel cabochons and
fbm velvet noise over a fixed palette, from the fixed seed `0x60D1`. Re-running
the script reproduces the PNGs byte-for-byte (verified by re-run + hash compare).

The look is deliberately **distinct from the sibling `fantasy-parchment`
package**: parchment is quiet paper-and-ink, ornate is rich metal-and-jewel over
dark velvet. Both can be installed in the same session to prove a swap.

**Contact sheet (no Studio needed):** `source/preview/contact-sheet.png` — every
nine-slice is rendered at three target sizes, the tiles are rendered tiled, and
the bar is assembled at 15 / 55 / 100 %.

## Files

Slice geometry is package data: `SliceCenter = Rect(border, border, W−border,
H−border)`, `SliceScale = 1`. `—` in the border column means a whole image
(never sliced). Slot names use the ADR-0020 R1/R3/R4 vocabulary; the final
package (P5) owns the authoritative recipe wiring.

| File | Size | Nine-slice border | Role | Slot / state |
|---|---|---|---|---|
| `ornate_panel_fill.png` | 128×128 | 32 | dark velvet content-back | `panel` → `layers[1] kind="fill"` |
| `ornate_panel_frame.png` | 160×160 | 40 | gold filigree border, transparent centre | `panel` → `layers[2] kind="frame"` |
| `ornate_corner_tl.png` | 48×48 | — | corner ornament (top-left) | `panel` → `layers[3] kind="corners"`, `topLeft` |
| `ornate_corner_tr.png` | 48×48 | — | corner ornament (top-right) | `layers[3] kind="corners"`, `topRight` |
| `ornate_corner_bl.png` | 48×48 | — | corner ornament (bottom-left) | `layers[3] kind="corners"`, `bottomLeft` |
| `ornate_corner_br.png` | 48×48 | — | corner ornament (bottom-right) | `layers[3] kind="corners"`, `bottomRight` |
| `ornate_edge_rail.png` | 64×24 | — (tile 64×24) | repeating gilt rail | `layers kind="edges"` with `tile = 64`, or `kind="tile"` |
| `ornate_velvet_tile.png` | 64×64 | — (tile 64×64) | seamless damask field | `layers kind="tile"`, `tileSize = {64,64}` |
| `ornate_plaque.png` | 176×56 | 20 | blank title board (gold trim) | `panel` → `layers kind="plaque"`, `text = true` |
| `ornate_button_default.png` | 64×64 | 16 | control chrome, resting | `control.asset.default` |
| `ornate_button_hover.png` | 64×64 | 16 | control chrome, brighter gilt | `control.asset.hover` |
| `ornate_button_pressed.png` | 64×64 | 16 | control chrome, darkened + inset | `control.asset.pressed` |
| `ornate_selection_default.png` | 64×64 | 16 | quiet unselected plate | `selection.asset.default` |
| `ornate_selection_selected.png` | 64×64 | 16 | jewelled plate (new construction) | `selection.asset.selected` |
| `ornate_field.png` | 64×64 | 16 | dark inset writing surface | `field.asset` |
| `ornate_bar_track.png` | 96×28 | 12 | carved groove with gold rim | `barTrack` |
| `ornate_bar_fill.png` | 96×20 | 8 | glowing liquid, full-width | `barFill` (`direction = "ltr"`) |
| `ornate_bar_cap_start.png` | 28×36 | — | gold finial, start | `barCap.start` |
| `ornate_bar_cap_end.png` | 28×36 | — | gold finial, end | `barCap.end` |
| `ornate_bar_center.png` | 36×28 | — | crown centrepiece | `barCenter` |
| `ornate_toggle_track_off.png` | 72×32 | 14 | cold carved channel | `toggleTrack.asset.default` |
| `ornate_toggle_track_on.png` | 72×32 | 14 | warm lit channel | `toggleTrack.asset.selected` |
| `ornate_toggle_knob_default.png` | 28×28 | — | jewelled disc | `toggleKnob.asset.default` |
| `ornate_toggle_knob_pressed.png` | 28×28 | — | jewelled disc, pressed | `toggleKnob.asset.pressed` |
| `ornate_stepper_plate_default.png` | 40×40 | 12 | glyph plate, resting | `stepperPlate.asset.default` |
| `ornate_stepper_plate_pressed.png` | 40×40 | 12 | glyph plate, pressed | `stepperPlate.asset.pressed` |
| `ornate_icon_chevron_right.png` | 32×32 | — | near-white glyph | `icons["chevron.trailing"]` |
| `ornate_icon_chevron_down.png` | 32×32 | — | near-white glyph | `icons["chevron.down"]` |
| `ornate_icon_plus.png` | 32×32 | — | near-white glyph | `icons["stepper.increment"]` |
| `ornate_icon_minus.png` | 32×32 | — | near-white glyph | `icons["stepper.decrement"]` |
| `ornate_icon_check.png` | 32×32 | — | near-white glyph | `icons["check"]` |
| `ornate_icon_cross.png` | 32×32 | — | near-white glyph | `icons["close"]` |
| `ornate_icon_gear.png` | 32×32 | — | near-white glyph | `icons["settings"]` |

33 files, 88 KB total on disk.

## Notes the package-authoring stage must know

1. **Border × 2 always fits.** Control-family borders are 16 px, so both borders
   (32 px) fit inside a 44–46 px control row without slice overlap. `barFill` is
   border 8 on a 20 px-tall source (16 < 20) — an earlier draft used border 10,
   which makes `2*border == height` and leaves the sliced centre rect EMPTY;
   that is a silent blank-centre bug, not a cosmetic one.
2. **Edge bands are uniform along their stretch axis by construction.** The
   frame's moulding profile is drawn across the FULL width/height first, and the
   flourishes live entirely inside the 40 px corner squares. Same rule for the
   plaque and bar track. Nothing smears.
3. **`ornate_bar_fill.png` is X-uniform between its slice borders** (the script
   explicitly broadcasts the centre column across the stretched band), so a
   partially revealed fill and a stretched fill are the same picture at every
   percent. Only the vertical gradient/gloss varies.
4. **`ornate_edge_rail.png` is a TILE asset, not a nine-slice.** Its guilloche +
   stud pattern has period 16 px inside a 64 px tile and is seamless at x=0/64;
   nine-slicing it stretches the studs. Declare `tileSize = {64, 24}`.
   `ornate_velvet_tile.png` is seamless on both axes, `tileSize = {64, 64}`.
5. **Selected-state jewels sit in the CORNER regions, not mid-edge.** The
   left/right slice bands stretch vertically, so a mid-edge gem would smear.
   If a package wants literal side ornaments, use a `corners` layer (the four
   `ornate_corner_*` files) rather than baking them into the sliced plate.
6. **Content insets are identical across every state variant** (button
   default/hover/pressed all reserve the same 16 px chrome; selection
   default/selected likewise), so R2's "no reflow on state change" compile check
   passes.
7. **Icons are near-white (`#F0F0F2`) on transparency** so R4 `tintRole` fully
   owns their colour. Nothing is baked in.
8. **No text is baked into any asset.** `ornate_plaque.png` is a blank board;
   the title is the plaque layer's live `text` sub-slot.
9. Suggested `iconSizes` role: 32 px at this authored scale (1:1, no resample).

**Regenerate:** `<repo-root>/.venv/bin/python source/generate_art.py`
(Pillow 12.2.0, numpy 2.4.6 at creation time; any CWD works).

**Import/publishing:** upload each PNG as a Roblox Image asset and record the
returned content IDs in `upload-manifest.json` (skeleton committed with
`"contentId": null`). Another project reproducing the package uploads the same
PNGs under its own account and substitutes its IDs — no hidden assets.

**License:** same license as the repository; the art is generated by repository
code and carries no external claims.
