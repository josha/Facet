# Facet standard icon set — provenance

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
| facet_icon_chevron_left.png | 128×128 | `chevron.leading` | `<` | content |
| facet_icon_chevron_right.png | 128×128 | `chevron.trailing` | `>` | content |
| facet_icon_chevron_up.png | 128×128 | `chevron.up` | `^` | content |
| facet_icon_chevron_down.png | 128×128 | `chevron.down` | `v` | content |
| facet_icon_chevron_up_down.png | 128×128 | `chevron.up.chevron.down` | `^v` | content |
| facet_icon_check.png | 128×128 | `checkmark` | `v` | content |
| facet_icon_radio_off.png | 128×128 | `facet:selection.radio.off` | `o` | content |
| facet_icon_radio_on.png | 128×128 | `facet:selection.radio.on` | `*` | content |
| facet_icon_check_off.png | 128×128 | `facet:selection.check.off` | `[]` | content |
| facet_icon_close.png | 128×128 | `close` | `x` | content |
| facet_icon_plus.png | 128×128 | `increment` | `+` | content |
| facet_icon_minus.png | 128×128 | `decrement` | `-` | content |
| facet_icon_menu.png | 128×128 | `menu` | `=` | content |
| facet_icon_more.png | 128×128 | `more` | `...` | content |
| facet_icon_edit.png | 128×128 | `edit` | `/` | content |
| facet_icon_trash.png | 128×128 | `trash` | `\_/` | content |
| facet_icon_flag.png | 128×128 | `flag` | `|>` | content |
| facet_icon_search.png | 128×128 | `facet:search` | `o/` | content |
| facet_icon_info.png | 128×128 | `status.info` | `i` | content |
| facet_icon_success.png | 128×128 | `status.success` | `ok` | content |
| facet_icon_warning.png | 128×128 | `status.warning` | `!` | content |
| facet_icon_error.png | 128×128 | `status.error` | `x!` | content |
| facet_icon_calendar.png | 128×128 | `calendar` | `[#]` | content |
| facet_icon_clock.png | 128×128 | `clock` | `(:)` | content |
| facet_icon_thumb_up.png | 128×128 | `vote.up` | `+1` | content |
| facet_icon_thumb_down.png | 128×128 | `vote.down` | `-1` | content |
| facet_icon_person.png | 128×128 | `person` | `@` | content |
| facet_icon_chevron_first.png | 128×128 | `chevron.first` | `\|<` | content |
| facet_icon_chevron_last.png | 128×128 | `chevron.last` | `>\|` | content |

29 PNG files: the original ten, `edit`, `trash` and `flag` (row-actions stage),
the search magnifying glass (2026-09-08), the pop-up button's stacked chevron
pair and the three selection marks (2026-09-11), and P1d's eleven common glyphs
(2026-09-18, below).

## Notes the consuming stage must know

1. **`edit`, `trash` and `flag` are the new semantic names**, added on top of the
   original ten chevron/checkmark/close/stepper/menu/more set. `edit`'s ASCII
   floor is `/` — the pencil reduced to its dominant stroke, the same move that
   made the checkmark a `v` and the menu an `=`. `trash` (row-actions stage,
   2026-08-11) is `\_/`, a waste bin's own open, tapered container; `flag` is
   `|>`, a pole flying a pennant — the same "reduce to the dominant silhouette"
   move. Both shipped as `U` and `P` first, and a phone photographed them reading
   as the LETTERS U and P sitting where an icon belongs, which is why no entry in
   that table may contain an uppercase letter any more. None
   collides with anything already in `ICON_FALLBACK_GLYPHS`, and each is the
   mark its `compactLabel = { icon = … }` / row-actions tray button draws until
   its art resolves.
2. **`tintRole` is `content` for every one of them, including the stepper's `+`/`-`.**
   The shipped packages tint their own stepper glyphs `accent`, which is right for
   art authored against a known palette. Framework art is painted under packages
   nobody checked it against, so it takes the one role measured legible on every
   variant. A package wanting gilded steppers declares its own art, as
   fantasy-ornate and pixel-quest already do.
3. **No per-state variants.** One silhouette per name; a package that wants a
   hover variant declares one and takes the rung above. `resolveIcon` therefore
   always reports `state = "default"` for framework art.
4. **All eighteen are drawn inside a 96 px content area centred in the 128 px
   box**, so the set shares one optical weight and one margin. That margin is
   what keeps a 20 px icon off a 20 px plate's edge; do not crop it out.
5. **Stroke weight is 13 px in 128-space** with round caps and joins. PIL has no
   round cap, so the generator draws caps and joins as explicit circles — that is
   what stops a chevron's tip looking chipped at 16 px.
6. **One package declines the set** and draws its own: `pixel_quest`, because a
   smooth silhouette in a 4 px pixel grid reads as a mistake and
   `ResamplerMode.Pixelated` only makes it a nearest-neighbour mistake. It may
   decline only because its own map is COMPLETE (2026-09-11). The
   `glossy_touch` / `compact_pointer` pair used to decline it as well, as a
   controlled comparison against Fantasy Ornate — which shipped `^v` and `v` to
   real screens, so that demonstration moved to `pixel_quest.buildWithoutIcons`,
   a build only a driver installs. `tests/icon_coverage.spec.luau` is the rule.
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

## Search magnifying glass (2026-09-08)

`facet_icon_search.png` uses the same deterministic generator, stroke weight,
transparent background and content tint as the existing set. It is a circular
lens with a round handle. The contact sheet includes 16 / 20 / 24 / 48 px previews.
Studio's `upload_image` returned `rbxassetid://85188541706347` for the local PNG;
the per-asset upload record stores its checksum and upload method. This upload
does not assert an Open Cloud moderation result. Facet's existing `facet:search`
slot resolves this standard art unless the theme supplies an override or opts
out of standard icons. The ASCII floor remains available for that deliberate
opt-out. Runtime load evidence is recorded in the navigation polish artifacts.

## The pop-up chevron pair and the selection marks (2026-09-11)

Four names joined the set on one day, for one reason: a player photographed
Studio drawing **characters where pictures belong** — `^v` in a picker trigger,
a bare `v` for a tick, and `*` / `o` for a radio's mark and ring.

`chevron.up.chevron.down` is the pop-up button's stacked pair. The three
selection marks are the resting and chosen states of the indicator a menu row and
a radio group draw into a reserved slot: `facet:selection.radio.off` is a ring,
`facet:selection.radio.on` is the same ring with its centre filled, and
`facet:selection.check.off` is that ring squared off into a box. The chosen CHECK
state is the existing `checkmark`, so the family is four shapes, not six. Ring and
box share one 80 px outer box inside the standard 96 px content area, so a radio
group and a checklist line up at the same optical size.

Uploaded headlessly through `tools/upload_icons.py` on 2026-09-11, all three
verified **Approved** / `Image` by `--recheck`:
`facet_icon_radio_off` `rbxassetid://73716910467356`,
`facet_icon_radio_on` `rbxassetid://113804826986290`,
`facet_icon_check_off` `rbxassetid://121698536401041`.

The other half of that defect was not an art gap at all: `menu_recipe` authored
`"o"`, `"[]"` and `"*"` as its own node text rather than reading
`ICON_FALLBACK_GLYPHS`, so those characters were not even part of the ladder the
floor is the bottom of. Every glyph a control draws now comes from that one table.

## P1d — eleven common glyphs (2026-09-18)

The owner ruled a SMALL common set for the next controls (Notice/Badge/Snackbar,
DateTimePicker, Vote, Avatar, Pagination) — continuing this set, not parity with
any reference design system's image catalog, and no art borrowed from one. Same
generator, same style, same manifest, same resolver. Three families:

- **Status badges** (`status.info`, `status.success`, `status.warning`,
  `status.error`) — a ring at the family's usual r=40 outer radius (matching
  `close`/`checkmark`/the selection marks) holding a small mark kept inside
  radius ~24–26 so its own ink never touches the ring's inner edge. `status.error`
  is a small enclosed X, deliberately smaller than the bare full-box X `close`
  draws, so the two are not the same shape at a glance; `status.success`'s tick is
  likewise reduced from the bare `checkmark`. `status.warning` breaks the ring
  pattern on purpose: a hazard triangle is the one shape a warning glyph actually
  is anywhere, and forcing it into a fourth circle would cost the one shape a
  player already recognizes.
- **`calendar` / `clock`** — a rounded body with two short strokes standing proud
  of the top edge (the binding tabs a page hangs from) and a ring with two
  unequal hands sharing a centre.
- **`vote.up` / `vote.down` / `person` / `chevron.first` / `chevron.last`** — see
  the two defects below; `person` is a head circle over a shoulders trapezoid,
  self-contained inside the content box like the status badges.

**Two shapes read as LETTERS on the first contact-sheet pass, caught by the same
"check your own art before shipping it" step that found the U/P letters in
2026-08-12.** `vote.up`/`vote.down` first drew a thumb as a straight round-capped
capsule the same width as the fist it rose from — the two merged into a single
bent bar that read as the letters **L** and **P**. The fix is proportion, not
detail: the thumb capsule is now under a third of the fist block's width (16px
against a 62px block, in 128-space), so the silhouette breaks into "thin digit
over wide block" instead of one continuous stroke. `chevron.first` first paired
the existing OPEN `_stroke` chevron with a bar, and two diagonal strokes meeting a
vertical one at the same two points **is** the letter **K** — confirmed on the
contact sheet, not guessed at. The fix was a FILLED triangular arrowhead
(`_poly`, the same primitive `flag`'s pennant and `edit`'s pencil already use) in
place of the open chevron, which reads as one solid mass next to the bar instead
of as more strokes joining it. `chevron.last` is the mirror.

No new primitives: every one of the eleven reuses `_ring`, `_stroke`, `_poly` and
`_dot` exactly as the existing eighteen do. `tintRole` is `content` for all
eleven, same reasoning as the rest of the set (measured legible on every
variant). Contact sheet reviewed at 16/20/24/48 px before shipping, per icon,
via the Read tool — not assumed from the drawing code.

## P1d fix round 1 — a second art pass on `vote.up`/`vote.down`/`person` (2026-09-18)

The round-0 fix above (a narrower capsule against a wider fist) was enough to
stop reading as the letters L/P **on the contact sheet's own small preview**,
but a dedicated lead art check at 16/20/24 px found it still read as "a boot"
and "a mallet/flag" — recognizably not-a-letter is a lower bar than
recognizably-a-thumb. `person`'s trapezoid shoulders also read as a chess
pawn. Both were redrawn; `info`/`success`/`warning`/`error`/`calendar`/`clock`/
`chevron.first`/`chevron.last` were untouched and stayed byte-identical.

**`vote.up` is now the conventional three-part hand silhouette**, all three
parts filled `_ring`/`_stroke`/`rounded_rectangle`-family primitives, no new
drawing primitive added:

1. a **cuff** (wrist) — a small rounded rect standing apart from the fist;
2. a **fist** — a larger rounded rect with three thin horizontal grooves cut
   into its knuckle (right) half, using `ImageDraw`'s ordinary `fill=` with a
   `(0, 0, 0, 0)` colour: Pillow's basic shapes REPLACE pixels rather than
   alpha-composite them, so drawing fully-transparent rectangles directly over
   already-opaque ink genuinely punches holes through it (verified with
   `Image.getpixel` before trusting it in the real generator — see the
   function's own docstring in `generate_icons.py`), which is what gives the
   fist finger texture at 24 px+ while it still reads as a clean block at
   16 px;
3. a **thumb** — a round-capped capsule leaning off vertical, based at the
   fist's top-left corner and overlapping it, clearly narrower than the fist
   and clearly taller than the fist's own base width.

`vote.down` is `thumb_up().transpose(Image.FLIP_TOP_BOTTOM)` on the FINISHED
image — a mirror of the pixels, not a second hand redrawn from scratch — so
the pair can never drift apart from each other again.

**`person`'s shoulders are now a half-ellipse (dome)**: `ImageDraw.pieslice`
from 180° to 360° on a bounding box gives a rounded top and a flat bottom
(verified against `getpixel` before use — a plain `getpixel` read is the only
instrument that actually sees which half of the ellipse painted), about
2.2× the head circle's own width, with the head separated from it by a small
4 px gap instead of overlapping it. The wider, rounded, separated shoulders
are what stop it reading as a pawn's round base merging straight into its own
head.

**Superseded asset ids** — abandoned, not deleted from Roblox (Open Cloud has
no delete route this tool uses), simply no longer referenced by the registry
or the manifest as of this round:

| Name | Superseded id (round 0, abandoned) | Current id (round 1) |
|---|---|---|
| `vote.up` (`facet_icon_thumb_up.png`) | `rbxassetid://114320275571678` | `rbxassetid://101016045702409` |
| `vote.down` (`facet_icon_thumb_down.png`) | `rbxassetid://126155387751193` | `rbxassetid://101348682807001` |
| `person` (`facet_icon_person.png`) | `rbxassetid://102363425807967` | `rbxassetid://75342910516929` |

Re-uploaded headlessly through `tools/upload_icons.py` (the same route, same
`assetType = "Image"` correction); all three verified **Approved** / `Image`
by `--recheck` on 2026-09-18, same day as the round-0 upload.

Blow-up preview (16/20/24/48 px, nearest-neighbour, all three fixed icons):
`source/preview/p1d-fix-round-1-blowup.png`.

## P1d fix round 2 — the thumb was too long (owner feedback, 2026-09-18)

Owner: "the thumbs are a bit comically long." The three-part shape from fix
round 1 (cuff, grooved fist, thumb capsule) is UNCHANGED; only the thumb
stroke's own endpoints and width move. Round 1's thumb ran base (58, 64) to
tip (72, 16) at width 22 — a ~40 px rise above the fist's y=56 top edge. Round
2 keeps the same base (58, 64) and the same ~15° lean, but the tip moves to
(67, 32) — a 24 px rise above the fist's top edge, roughly 60% of round 1's
length — at width 26 instead of 22. `vote.down` stayed exactly
`thumb_up().transpose(Image.FLIP_TOP_BOTTOM)`, so it inherited the shorter
thumb automatically, with no separate edit. `person` and the other eight
round-1-reviewed icons are untouched and byte-identical (confirmed by
`git status` after regenerating: only `facet_icon_thumb_up.png` and
`facet_icon_thumb_down.png` changed).

Shortening the thumb also recentred the icon without a separate shift: the
round-1 bbox (thumb tip at y≈5 once its cap is included, fist/cuff bottom at
y=110) had its vertical centre at ≈57.5, a few px above the canvas's own
y=64 centre; the round-2 bbox (tip cap top at y≈19, same bottom) centres at
≈64.5 — close enough that no additional vertical shift was needed.

**Superseded asset ids** (round 1 → round 2, same abandon-not-delete
convention as round 1):

| Name | Superseded id (round 1, abandoned) | Current id (round 2) |
|---|---|---|
| `vote.up` (`facet_icon_thumb_up.png`) | `rbxassetid://101016045702409` | `rbxassetid://75207492738442` |
| `vote.down` (`facet_icon_thumb_down.png`) | `rbxassetid://101348682807001` | `rbxassetid://105653007466295` |

Re-uploaded headlessly through `tools/upload_icons.py`; both verified
**Approved** / `Image` by `--recheck` on 2026-09-18, same day as rounds 0-1.
`person` was not re-uploaded — its pixels did not change this round, so its
round-1 id (`rbxassetid://75342910516929`) is still current.

The blow-up preview at `source/preview/p1d-fix-round-1-blowup.png` was
updated in place (same path, current pixels) rather than left describing a
now-superseded shape.

**Upload status:** see `upload-manifest.json` and `src/themes/standard_icons.luau`
for the current state of each of the eleven (Approved-and-live, or pending —
`resolveIcon` falls through to the ASCII floor above while pending, exactly as
`trash`/`flag` did between 2026-08-11 and 2026-08-12).

## Application-branch port (2026-09-20)

The eleven common icons, corrected thumbs/person, preview images and existing
asset IDs above were restored from their final committed bytes. The generator
was not run and nothing was uploaded. Historical moderation records are retained;
this port does not assert a new moderation or native-loading check. The eighteen
pre-existing PNGs and asset records are unchanged. Generator byte identity across
Pillow/compression versions is not assumed; the committed hashes remain the record.
