# OrnateGauge — source art provenance

**Stage:** `rich-skinning-v2` (ADR-0020 **R8 rung 3**) · **Created:** 2026-07-25 ·
**Seed:** `0x9A17` · **Owner:** the CONTROL `examples/themes/ornate_gauge.luau`,
not a theme package.

Every texture in this directory is **original, repository-owned, procedurally
generated art**. There is no external imagery, no third-party asset, and no game
or OS trade dress. The single source is `source/generate_art.py`.

## Why this folder is different from its siblings

Every other folder under `assets/themes/` belongs to a **theme package**. This
one belongs to a **control**. That is the whole point of the rung-3 example: a
custom control ships its own pictures the way a third-party control would, and
the theme contributes only the values a theme is allowed to own.

| Who owns what | Where it lives |
|---|---|
| the pictures | this folder, referenced by content ID from `ornate_gauge.luau` |
| the dial's size | the package: `metrics.controlSizes["gauge:dial"]` |
| the glow colour | the package: `style.themes[].extra["gauge:needle"]` |
| the corner radius | the package: `metrics.radii["gauge:ring"]` |

A package that declares none of the three still runs the gauge — the control's
declared fallbacks apply and `themes.checkCoverage` says so before play. See
`docs/extending/skinned-control.md`.

## What the art has to survive

A control paints through the **public** `UI.Image` primitive. That primitive has
no `sliceCenter` and no tint — nine-slice geometry and `ImageColor3` are theme
recipe authority, and a control may not reach them. So the art is shaped by that
constraint rather than fighting it:

* **`gauge_face.png` is horizontally invariant.** It is authored as a column of
  64 colours repeated across the width, so every column is byte-identical and
  stretching it to any width is lossless. The generator ASSERTS this after
  writing the file — "stretching whole art is fine here" is checked, not claimed.
* **`gauge_needle.png` and `gauge_endcap.png` are never stretched.** Both are
  drawn at a fixed px box by the control.
* **The end cap is used unflipped at both ends**, lit from above rather than
  from a side, because a control cannot mirror an image.

## Files

| File | Size (px) | Role | Drawn at |
|---|---|---|---|
| `gauge_face.png` | 64×64 | carved iron channel between two brass rails | `width = fill`, `height = <gauge:dial>.height` — stretched horizontally, losslessly |
| `gauge_needle.png` | 24×64 | tapered brass needle with a ruby boss — the value token | fixed 24 px wide, full dial height |
| `gauge_endcap.png` | 28×64 | fluted brass end cap with a centre boss and two rivets | fixed 28 px wide, full dial height, at both ends |

**Palette:** iron `#14110E / #2A241D / #463C2F`, brass
`#6B4E1C / #C0943A / #F0D38B`, ruby `#66141C / #C82E3A / #FF9A9A`. Chosen to sit
beside Fantasy Ornate without being it — a control's art has to read on a
parchment package *and* a pixel one.

**Contact sheet (no Studio needed):** `source/preview/contact-sheet.png` — the
dial at 320/520/760 px wide with the needle at 8 %, 50 % and 94 %, over a
checker, so the stretch and the end-cap alignment are judgeable on disk.

## Regeneration

```sh
# from the repo root's shared venv; any CWD works
/path/to/UntitledRacingGame/.venv/bin/python \
  GameStudio/ui/LuauUI/assets/themes/ornate-gauge/source/generate_art.py
```

Deterministic: re-running reproduces all three PNGs byte-for-byte on the
recorded library versions.

| Library | Version used |
|---|---|
| Pillow | 12.2.0 |
| numpy | 2.4.6 |

SHA-256 of the committed files (2026-07-25):

| File | SHA-256 |
|---|---|
| `gauge_face.png` | `d19db23dcb6d3c9b97b029a8c5fd99c790f7dc9d792575de257490c49955ccd5` |
| `gauge_needle.png` | `9d537af5b2be6c81a474c33714f151ec27b6eeae2f636baddc12338d95bfb663` |
| `gauge_endcap.png` | `d66d700de522685ce379d2be0fd103585bf43bb7a07c6c40086ac5e3d524b329` |

## Import / publishing procedure

The PNGs were published to the Roblox asset service on **2026-07-25** with the
Studio MCP `upload_image` tool over a local `python3 -m http.server` bound to
`127.0.0.1:8647` serving this directory — the same method the P4/P5 theme art
used. The resulting content IDs are recorded in `upload-manifest.json` beside
this file, and `ornate_gauge.luau` references exactly those IDs.

**Another project uploads the same PNGs under its own account and substitutes
its own IDs.** There are no hidden assets: everything the control draws is in
this folder, and everything it draws it with is in `upload-manifest.json`.

## Licence

Original art produced for this repository, released under the repository's
licence. No third-party material is included.
