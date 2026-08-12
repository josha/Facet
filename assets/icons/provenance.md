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

## Upload closed — `trash` and `flag` (row-actions stage, uploaded 2026-08-12)

`trash` and `flag` are live: `rbxassetid://84398508341623` (trash) and
`rbxassetid://109067109704366` (flag), both verified **Approved**/`Image` via
`tools/upload_icons.py --recheck` on 2026-08-12, ids in `upload-manifest.json`
and the registry with no hand-transcription. The earlier 401 ("Invalid API
Key") had TWO causes, both fixed the same day: the key's **IP allow-list** no
longer contained this machine's public IP (Open Cloud reports an IP-rejected
request as "Invalid API Key" — check `curl -s https://api.ipify.org` against
the key's Accepted IP Addresses on create.roblox.com → API keys before
concluding a key is dead), and the secret was regenerated fresh while there
anyway. Key config: scope `assets` read+write, IP-restricted, expires
8/26/2026 (or 60 days of inactivity — a future 401 is most likely IP rotation
or that expiry, and the fix is the dashboard, not the code).

One trap for the record: an agent running the full suite concurrently with
the upload saw the tool's writes to `upload-manifest.json`/`standard_icons.luau`
appear mid-run, attributed them to the suite, and `git checkout --`-reverted
them; the records were restored from the tool's own output and re-verified
against the live API with `--recheck`. Don't run the suite and the uploader
concurrently in the same checkout.

**License:** same license as the repository; the art is generated by repository
code and carries no external claims.
