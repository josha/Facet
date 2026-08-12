# LuauUI standard icon set — provenance

**Stage:** compact-label · **Created:** 2026-07-27 · **Deterministic:** no seed, no randomness.

This is the **framework's own art**, and the first of its kind in this repository.
Every other asset folder here is `assets/themes/<package>/` and belongs to one
theme package; this one belongs to the library. It resolves **below** a package's
own icons and **above** the ASCII fallback glyph
(`src/themes/package.luau` → `resolveIcon`), so "this package ships no icon for
that name" now means *draw the framework's picture* instead of *draw the
framework's character* — and the character is still the floor beneath that. A
package declines the whole rung with `identity.standardIcons = false`.

The art is original, repository-owned and **procedurally generated**: the single
source is `source/generate_icons.py`, which draws flat geometry at 8× and
downsamples with LANCZOS. Re-running it reproduces every PNG byte for byte. No
model generated any pixel here — a 16–24 px UI glyph has to be crisp and
pixel-aligned, which is what AI raster generation is worst at, and these shapes
are strokes and polygons that code draws exactly.

**Why one near-white silhouette and not a light/dark pair.** `ImageColor3`
**multiplies**, so a white source reaches any colour a theme names while a black
one can only ever get darker. Measured across all **11 theme variants** of the
eight reference packages, `tintRole = "content"` contrasts **3.31 : 1 to
15.62 : 1** against the `control` plate these sit on — dark in every light
package, light in every dark one. One silhouette is therefore correct everywhere
and a second version would be strictly worse. The ink is `#F0F0F2` on
transparency; nothing is baked in and the tint owns the colour completely. Both
paint paths (the native `ImageColor3` sheet token and the fallback explicit
write) resolve that role from the same palette as the plate behind it, and
`tests/theme_icons.spec.luau` pins their two role vocabularies to each other.

**Contact sheet (no Studio needed):** `source/preview/contact-sheet.png` — every
icon at 16 / 20 / 24 / 48 px on mid-grey, which are the sizes they are actually
drawn at. A 128 px preview would prove nothing.

## Files

| File | Size | Semantic name | ASCII floor | Tint role |
|---|---|---|---|---|
| luauui_icon_chevron_left.png | 128×128 | `chevron.leading` | `<` | content |
| luauui_icon_chevron_right.png | 128×128 | `chevron.trailing` | `>` | content |
| luauui_icon_chevron_up.png | 128×128 | `chevron.up` | `^` | content |
| luauui_icon_chevron_down.png | 128×128 | `chevron.down` | `v` | content |
| luauui_icon_check.png | 128×128 | `checkmark` | `v` | content |
| luauui_icon_close.png | 128×128 | `close` | `x` | content |
| luauui_icon_plus.png | 128×128 | `increment` | `+` | content |
| luauui_icon_minus.png | 128×128 | `decrement` | `-` | content |
| luauui_icon_menu.png | 128×128 | `menu` | `=` | content |
| luauui_icon_more.png | 128×128 | `more` | `...` | content |
| luauui_icon_edit.png | 128×128 | `edit` | `/` | content |
| luauui_icon_trash.png | 128×128 | `trash` | `U` | content |
| luauui_icon_flag.png | 128×128 | `flag` | `P` | content |

13 files, 24 KB of PNG on disk (~100 KB including the source and contact sheet).

## Notes the consuming stage must know

1. **`edit`, `trash` and `flag` are the new semantic names**, added on top of the
   original ten chevron/checkmark/close/stepper/menu/more set. `edit`'s ASCII
   floor is `/` — the pencil reduced to its dominant stroke, the same move that
   made the checkmark a `v` and the menu an `=`. `trash` (row-actions stage,
   2026-08-11) is `U`, a waste bin's own open-container silhouette; `flag` is
   `P`, a pole with a pennant riding its top-right — the same "reduce to the
   dominant silhouette" move, not a letter standing in for the word. None
   collides with anything already in `ICON_FALLBACK_GLYPHS`, and each is the
   mark its `compactLabel = { icon = … }` / row-actions tray button draws until
   its art resolves.
2. **`tintRole` is `content` for all eleven, including the stepper's `+`/`-`.**
   The shipped packages tint their own stepper glyphs `accent`, which is right for
   art authored against a known palette. Framework art is painted under packages
   nobody checked it against, so it takes the one role measured legible on every
   variant. A package wanting gilded steppers declares its own art, as
   fantasy-ornate and pixel-quest already do.
3. **No per-state variants.** One silhouette per name; a package that wants a
   hover variant declares one and takes the rung above. `resolveIcon` therefore
   always reports `state = "default"` for framework art.
4. **All thirteen are drawn inside a 96 px content area centred in the 128 px
   box**, so the set shares one optical weight and one margin. That margin is
   what keeps a 20 px icon off a 20 px plate's edge; do not crop it out.
5. **Stroke weight is 13 px in 128-space** with round caps and joins. PIL has no
   round cap, so the generator draws caps and joins as explicit circles — that is
   what stops a chevron's tip looking chipped at 16 px.
6. **Three packages decline the set** and keep the ASCII glyph:
   `pixel_quest` (a smooth silhouette in a 4 px pixel grid reads as a mistake, and
   `ResamplerMode.Pixelated` only makes it a nearest-neighbour mistake) and the
   `glossy_touch` / `compact_pointer` pair (whose controlled comparison against
   Fantasy Ornate is the only place the ASCII floor is visible in a shipped
   package).
7. **Fantasy Ornate deliberately does NOT decline it.** It maps six names to its
   own art, invents one (`ornate:settings`), and leaves `menu` / `more` to the
   library — every rung of the ladder visible in one shipped centrepiece.

**Regenerate:** `<repo-root>/.venv/bin/python assets/icons/source/generate_icons.py`
(Pillow 12.2.0 at creation time; any CWD works).

**Import/publishing:** **fully headless**, unlike the eleven per-package assets
that shipped before it. `tools/upload_icons.py` uploads every PNG through Roblox
Open Cloud (`POST /assets/v1/assets` with **`assetType = "Image"` — not
`"Decal"`, whatever the documentation says**), polls each operation to `done`,
writes `upload-manifest.json` and pushes the returned ids into
`src/themes/standard_icons.luau`, which is the registry the framework reads. No
Studio, no human step, no hand-transcribed id. `--recheck` re-reads each asset's
moderation state and asset type afterwards; the original eleven came back
**Approved** and **`Image`** on 2026-07-27. Another project reproducing this set
uploads the same PNGs under its own account and substitutes its ids — no hidden
assets.

## Pending upload — `trash` and `flag` (row-actions stage, 2026-08-12)

`trash` and `flag` are generated, registered (`standard_icons.ART`, `contentId =
nil`) and covered by their ASCII floor (`U`/`P`) — the documented legal
pre-upload state this whole set was built to land green in — but **not yet
uploaded**. `tools/upload_icons.py` failed twice against `ROBLOX_API_KEY` in
`GameStudio/tools/API_KEYS.txt`, both times with a real (not network/parse)
rejection from Roblox's own API:

```
HTTP 401 from https://apis.roblox.com/assets/v1/assets
{"errors":[{"code":0,"message":"Invalid API Key"}]}
```

The key is present in the file but Open Cloud rejects it outright — expired or
revoked, not a transient failure; a fresh key is needed from whoever owns the
credential. Every other icon in this set (all eleven original entries) is
unaffected and stays **Approved**/`Image`.

**To resume:** refresh `ROBLOX_API_KEY` (scope `assets`, read+write), then from
`GameStudio/ui/LuauUI/` run:

```
.venv/bin/python tools/upload_icons.py
```

(`.venv` is the shared one at the monorepo root,
`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/.venv`.)
It re-derives its target list from `standard_icons.luau` itself, so it will
skip all eleven existing ids and upload only `luauui_icon_trash.png` and
`luauui_icon_flag.png`, writing the returned ids into both
`upload-manifest.json` and the registry with no hand-transcription. Then rerun
`./tools/test.sh` and `lune run tools/lune/check_docs_cli` — nothing else in
this stage's code changes.

**License:** same license as the repository; the art is generated by repository
code and carries no external claims.
